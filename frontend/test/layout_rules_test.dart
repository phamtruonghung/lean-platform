/// The client's layout rules, enforced against the source rather than trusted
/// (issue #195).
///
/// **Why a source test rather than a widget test.** The two patterns here are
/// things a Screen can *type*, and typing them is how #193 happened in
/// twenty-five Screens at once. A rendered assertion can only catch the page it
/// renders; reading every file under `lib/` catches the next one before anybody
/// looks at it. This is the same device `theme_skeleton_test.dart` uses to keep
/// every colour in `theme.dart` — it has held the palette for dozens of pull
/// requests precisely because it is a test and not a convention.
///
/// **Three rules, all narrow, each traceable to a bug that shipped.**
///
/// 1. **A Screen's page frame is `AppPageFrame`, not a bare `ConstrainedBox`.**
///    `Center(child: ConstrainedBox(constraints: BoxConstraints(maxWidth: X)))`
///    sizes itself to its child, so a page whose content is a title, a
///    description and a row of buttons shrink-wrapped to its longest sentence and
///    floated to the middle of the window: measured on `/stores`, 142px right of
///    the card beneath it. `AppPageFrame` is the same constraint around a
///    `SizedBox(width: double.infinity)`, which cannot shrink-wrap. The two
///    allowed values are the centred cards — `PlatformEmptyState`,
///    `PlatformFailureState` and the sign-in / awaiting-Approval blocks at 400 and
///    460 — which are centred on purpose and would be wrecked by stretching.
/// 2. **A `Card` whose direct child is a `Column` states its
///    `crossAxisAlignment`.** `Column`'s default is `center`, so a row that sizes
///    to its own content — a `Wrap` of a name and its actions — floats to the
///    middle of its card: on `/skills` the row's text started 43px inside a card
///    that began at the card's left edge, with its actions against the text. The
///    rule is *state it*, not *state `stretch`*: an explicit `start` or `center`
///    is a decision somebody made, and the default being the decision is what
///    this forbids.
/// 3. **A `Row`/`Wrap` that puts a labelled field beside a button is an
///    `AppFilterRow`.** Measured on the pinned SDK: a labelled outline field is
///    56px at a text scale of 1 and 80px at 2, and a `ButtonStyleButton` beside
///    it is 48 whatever the text size — the defect the owner reported on
///    `/actions` ("the drop box is always higher than the others", #472). The
///    parent card carried the filter row (`AppFilterRow.controlHeight`), and a
///    dialog's content column has the same shape when it mixes the two: a
///    `Row(children: [DropdownButtonFormField(...), OutlinedButton(...)])` is
///    that defect by construction, wherever it is written. The rule is *say the
///    height once*, not *never mix them*: `AppFilterRow` is a `Wrap` and takes
///    any children, so a dialog row that needs this uses it too.
///    An `IconButton` is deliberately outside the rule — an icon is not a
///    bordered control, and a 48px icon box beside a 56px field is a different
///    question from a button and a field that must read as one line.
///
/// **What it deliberately does not enforce**, so that it is not deleted in a
/// month: one shared page *header* (the headers still differ by Screen, a
/// documented exclusion in #193), vertical rhythm, page widths, where a card of
/// rows must live, or anything about copy. Only the three shapes above.
///
/// Dialogs are out of scope for rule 1: a dialog's box is a bounded content
/// width, not a page — the Screen-versus-dialog distinction `CONTEXT.md` draws.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Rule 1: a page frame written by hand, with a `maxWidth` that is not one of the
/// two centred-card widths.
final _handRolledPageFrame = RegExp(
  r'ConstrainedBox\(\s*constraints:\s*(?:const\s+)?BoxConstraints\(\s*maxWidth:\s*([^,)\s]+)',
  multiLine: true,
);

/// Rule 2: a `Card` whose direct child is a `Column`, so the section between the
/// two can be checked for an explicit alignment.
final _cardWithColumnChild = RegExp(
  r'Card\(\s*(?:margin:\s*[^,]+,\s*)?child:\s*Column\(',
  multiLine: true,
);

/// The two widths the centred state and sign-in cards use, and the only
/// `ConstrainedBox` widths a Screen may still state.
const allowedStateWidths = <String>{'400', '460'};

/// Every violation in one file's source, as `line: message` — a *pure* function
/// over (path, source), so the guard's own logic can be tested against
/// deliberately violating text without planting a violation in the tree.
List<String> layoutViolations(String path, String source) {
  final violations = <String>[];

  if (path.endsWith('_screen.dart')) {
    for (final match in _handRolledPageFrame.allMatches(source)) {
      final width = match.group(1)!;
      if (allowedStateWidths.contains(width)) continue;
      final line = source.substring(0, match.start).split('\n').length;
      violations.add(
        '$path:$line: a page frame stated by hand (maxWidth: $width). A Screen lays '
        'its content out in `AppPageFrame` (lib/widgets/app_page_frame.dart), which '
        'cannot shrink-wrap; the only widths a Screen may state are the centred '
        'cards ${allowedStateWidths.join(' and ')}.',
      );
    }
  }

  for (final match in _cardWithColumnChild.allMatches(source)) {
    // The segment from the Card's own column to its first child list — far
    // enough to see whether the column stated its alignment.
    final segment = source.substring(match.end, (match.end + 400).clamp(0, source.length));
    final head = segment.split('children:').first;
    if (head.contains('crossAxisAlignment')) continue;
    final line = source.substring(0, match.start).split('\n').length;
    violations.add(
      '$path:$line: a `Card` whose `Column` does not state its crossAxisAlignment, '
      'so the Column default (centre) decides where a row that sizes to its own '
      'content lands. Use `AppListCard` for a card of rows '
      '(lib/widgets/app_list_card.dart), or state the alignment explicitly.',
    );
  }

  return violations;
}

/// Rule 3: a `Row`/`Wrap` that mixes a labelled field with a button. The
/// negative lookbehind is what keeps `AppFilterRow(` out of it — the widget whose
/// whole job is the fix.
final _rowOrWrap = RegExp(r'(?<![\w.])(?:Row|Wrap)\s*\(');

/// The controls that carry a floating label and an outline. Every one of them is
/// `AppFilterRow.controlHeight` tall (56 at a text scale of 1, 80 at 2), whatever
/// its own `isDense`. A type argument may sit between the name and the `(`
/// (`DropdownButtonFormField<String>(`), so it is matched as part of the shape.
final _labelledField = RegExp(
  r'\b(TextField|TextFormField|DropdownButtonFormField|AppFilterField|AppDateField|'
  r'AppDateTimeField|AppSearchField)\s*(?:<[^()<>]*>)?\s*\(',
);

/// Every button is a `ButtonStyleButton`: 48 tall, whatever the reader's text
/// size. `IconButton` is deliberately absent — an icon is not a bordered control.
final _buttons = RegExp(r'\b(OutlinedButton|FilledButton|ElevatedButton|TextButton)\b');

/// [source] with comments and string literals blanked, newlines kept: a `(` or
/// `)` inside either cannot move a depth scan, and a line read off the result is
/// still the line in the file.
String _withoutProse(String source) {
  final out = StringBuffer();
  var i = 0;
  while (i < source.length) {
    final char = source[i];
    if (char == '/' && i + 1 < source.length && source[i + 1] == '/') {
      while (i < source.length && source[i] != '\n') {
        out.write(' ');
        i++;
      }
      continue;
    }
    if (char == '/' && i + 1 < source.length && source[i + 1] == '*') {
      while (i < source.length &&
          !(source[i] == '*' && i + 1 < source.length && source[i + 1] == '/')) {
        out.write(source[i] == '\n' ? '\n' : ' ');
        i++;
      }
      out.write('  ');
      i = (i + 2).clamp(0, source.length);
      continue;
    }
    if (char == "'" || char == '"') {
      final triple = i + 2 < source.length && source[i + 1] == char && source[i + 2] == char;
      final quote = triple ? char * 3 : char;
      out.write(' ' * quote.length);
      i += quote.length;
      while (i < source.length) {
        if (source.startsWith(quote, i)) {
          out.write(' ' * quote.length);
          i += quote.length;
          break;
        }
        if (source[i] == r'\' && i + 1 < source.length) {
          out.write('  ');
          i += 2;
          continue;
        }
        out.write(source[i] == '\n' ? '\n' : ' ');
        i++;
      }
      continue;
    }
    out.write(char);
    i++;
  }
  return out.toString();
}

/// The index of the `)` closing the `(` at [open], or the end of the source when
/// the file is unbalanced — a syntax error is `flutter analyze`'s problem, not
/// this rule's.
int _matchingParen(String source, int open) {
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    if (source[i] == '(') depth++;
    if (source[i] == ')') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return source.length;
}

/// Rule 3's violations in one file, as `line: message` — a *pure* function over
/// (path, source), so the rule's own logic is testable against deliberately
/// violating text without planting a violation in the tree.
List<String> controlRowViolations(String path, String source) {
  final clean = _withoutProse(source);
  final violations = <String>[];
  for (final match in _rowOrWrap.allMatches(clean)) {
    final open = clean.indexOf('(', match.start);
    final body = clean.substring(open + 1, _matchingParen(clean, open));
    final field = _labelledField.firstMatch(body)?.group(1);
    final button = _buttons.firstMatch(body)?.group(1);
    if (field == null || button == null) continue;
    final row = match.group(0)!.replaceAll(RegExp(r'\s*\($'), '');
    final line = source.substring(0, match.start).split('\n').length;
    violations.add(
      '$path:$line: a $row puts a `$field` beside a `$button`. A labelled field is '
      '`AppFilterRow.controlHeight` tall (56 at 1x text, 80 at 2x) and a button is 48, '
      'so the box is 8px proud of the button beside it and 32px proud at 200% text. Lay '
      'the row out in `AppFilterRow` (lib/widgets/app_filter_row.dart), which gives every '
      'child that height as a floor; never size the button by hand.',
    );
  }
  return violations;
}

/// Every hand-written Dart file under `lib/`, so the guard covers the next Screen
/// as well as the ones that exist.
List<File> _libSources() {
  final lib = Directory('lib');
  expect(lib.existsSync(), isTrue, reason: 'run this from frontend/');
  return lib
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

void main() {
  test('no Screen states its own page frame', () {
    final violations = <String>[
      for (final file in _libSources())
        ...layoutViolations(file.path, file.readAsStringSync()),
    ];
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  // The guard's own logic, against the exact text #193 shipped — so a change that
  // quietly stops matching fails here rather than passing everything.
  test('the checker reports the shapes it exists to forbid', () {
    final pageFrame = layoutViolations(
      'lib/people/some_screen.dart',
      '''
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: const Text('x'),
        ),
      );
      ''',
    );
    expect(pageFrame, hasLength(1));
    expect(pageFrame.single, contains('AppPageFrame'));

    final card = layoutViolations(
      'lib/people/some_screen.dart',
      '''
      return Card(
        margin: EdgeInsets.zero,
        child: Column(
          children: [const Text('x')],
        ),
      );
      ''',
    );
    expect(card, hasLength(1));
    expect(card.single, contains('crossAxisAlignment'));
  });

  test('the checker allows what the client is supposed to write', () {
    // A page frame, and a centred state card.
    expect(
      layoutViolations(
        'lib/people/some_screen.dart',
        '''
        return Center(
          child: AppPageFrame(
            maxWidth: SomeScreen.maxWidth,
            child: const Text('x'),
          ),
        );
        ''',
      ),
      isEmpty,
    );
    expect(
      layoutViolations(
        'lib/people/some_screen.dart',
        '''
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: const Text('x'),
          ),
        );
        ''',
      ),
      isEmpty,
    );
    // A card of rows that states its alignment, whatever it states.
    expect(
      layoutViolations(
        'lib/people/some_screen.dart',
        '''
        return Card(
          margin: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [const Text('x')],
          ),
        );
        ''',
      ),
      isEmpty,
    );
    // A dialog's own bounded box is not a page.
    expect(
      layoutViolations(
        'lib/people/some_dialog.dart',
        '''
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: const Text('x'),
          ),
        );
        ''',
      ),
      isEmpty,
    );
  });

  test('no row puts a labelled field beside a button outside AppFilterRow', () {
    final violations = <String>[
      for (final file in _libSources())
        ...controlRowViolations(file.path, file.readAsStringSync()),
    ];
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  // The rule's own logic, against the shape it exists to forbid — so a change
  // that quietly stops matching fails here instead of passing everything.
  test('the control-row checker reports the shape it forbids', () {
    final violations = controlRowViolations(
      'lib/actions/some_dialog.dart',
      '''
      Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              items: const [],
              onChanged: (_) {},
            ),
          ),
          OutlinedButton(onPressed: () {}, child: const Text('Change')),
        ],
      );
      ''',
    );
    expect(violations, hasLength(1));
    expect(violations.single, contains('some_dialog.dart:'));
    expect(violations.single, contains('AppFilterRow'));
  });

  test('the control-row checker allows the fix and the shapes it does not own', () {
    // The fix: the same row inside AppFilterRow.
    expect(
      controlRowViolations(
        'lib/actions/some_dialog.dart',
        '''
        AppFilterRow(
          children: [
            DropdownButtonFormField<String>(items: const [], onChanged: (_) {}),
            OutlinedButton(onPressed: () {}, child: const Text('Change')),
          ],
        );
        ''',
      ),
      isEmpty,
    );
    // A row of buttons only: already one height, and not this rule's business.
    expect(
      controlRowViolations(
        'lib/actions/some_dialog.dart',
        '''
        Row(
          children: [
            OutlinedButton(onPressed: () {}, child: const Text('Cancel')),
            FilledButton(onPressed: () {}, child: const Text('Save')),
          ],
        );
        ''',
      ),
      isEmpty,
    );
    // An icon beside a field: a different question, stated in the rule.
    expect(
      controlRowViolations(
        'lib/actions/some_dialog.dart',
        '''
        Row(
          children: [
            Expanded(child: TextField(decoration: InputDecoration(labelText: 'Step'))),
            IconButton(onPressed: () {}, icon: const Icon(Icons.close)),
          ],
        );
        ''',
      ),
      isEmpty,
    );
    // A `)` inside a string must not end the scan early, or this row is missed.
    expect(
      controlRowViolations(
        'lib/actions/some_dialog.dart',
        '''
        Row(
          children: [
            Text('Due (optional)'),
            TextField(decoration: InputDecoration(labelText: 'Due')),
            TextButton(onPressed: () {}, child: const Text('Today')),
          ],
        );
        ''',
      ),
      hasLength(1),
    );
  });
}
