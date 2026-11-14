/// `AppFilterRow`: the controls in a filter row are one height, at every width
/// and every text size.
///
/// The defect this file guards (owner report, `/actions`): a dropdown sat 8px
/// taller than the button beside it, and 32px taller at 200% text, because a
/// labelled outline field reserves a line for its floating label that a
/// `ButtonStyleButton` does not. The geometry is **measured** (`getSize`,
/// `getTopLeft`) rather than inferred from "it renders", for the same reason
/// `app_toolbar_test.dart` measures: the wrong row renders perfectly.
///
/// Mounted like `app_toolbar_test.dart` — a small `MaterialApp` with the app's
/// own theme, no `FakeWire` (this row makes no request) — with the width given
/// by a `SizedBox` around it and the text scale set through the `MediaQuery`
/// inside the app, where a real reader's setting reaches the widget.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/l10n/app_localizations.dart';

import 'package:lean_platform/theme.dart';
import 'package:lean_platform/widgets/app_dialog.dart';
import 'package:lean_platform/widgets/app_filter_field.dart';
import 'package:lean_platform/widgets/app_filter_row.dart';

const _dropdownKey = ValueKey<String>('probe-dropdown');
const _buttonKey = ValueKey<String>('probe-button');
const _textButtonKey = ValueKey<String>('probe-text-button');
const _filterFieldName = 'probe';

/// The four kinds of control a filter row mixes, in the order `/actions` has
/// them.
Widget _dropdown() => SizedBox(
      width: 220,
      child: DropdownButtonFormField<String>(
        key: _dropdownKey,
        initialValue: 'a',
        isDense: true,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Site', border: OutlineInputBorder()),
        items: const [
          DropdownMenuItem<String>(value: 'a', child: Text('Plant A')),
          DropdownMenuItem<String>(value: 'b', child: Text('Plant B')),
        ],
        onChanged: (_) {},
      ),
    );

Widget _row() => AppFilterRow(
      children: [
        _dropdown(),
        SizedBox(
          width: 260,
          child: AppFilterField(
            name: _filterFieldName,
            label: 'Filter Actions',
            helperText: 'By title.',
            term: '',
            onChanged: (_) {},
          ),
        ),
        OutlinedButton.icon(
          key: _buttonKey,
          onPressed: () {},
          icon: const Icon(Icons.account_tree_outlined),
          label: const Text('All Org Units'),
        ),
        TextButton(
          key: _textButtonKey,
          onPressed: () {},
          child: const Text('Clear filters'),
        ),
      ],
    );

Future<double> _pump(
  WidgetTester tester, {
  required Widget child,
  double width = 1280,
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(2400, 1200);
  addTearDown(tester.view.reset);
  late double controlHeight;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildAppTheme(),
      home: Scaffold(
        body: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: Builder(
                  builder: (inner) {
                    controlHeight = AppFilterRow.controlHeight(inner);
                    return child;
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return controlHeight;
}

/// The control box of the filter field — not the widget, which also carries the
/// helper caption under its box.
Finder get _filterFieldBox => find.byKey(AppFilterField.fieldKey(_filterFieldName));

// ---- The row inside a dialog (#477) --------------------------------------
//
// The parent card (#472) left form dialogs out on the ground that a button sits
// *under* a field there, not beside one — true, measured over all 115 dialog
// files: none of them puts a labelled field beside a box-drawn button
// (`TextButton`, `OutlinedButton`, `FilledButton`, `ElevatedButton`), and the one
// row that pairs a field with an `IconButton` pairs it with an icon, not a
// bordered box. This group answers the question that split the card out, because
// the answer decides whether the shape can be adopted at all: **does
// `AppFilterRow` work inside `AppDialog`?** A dialog's content column is 420–640
// wide (design-language §11), not a page — 488 after the padding at the `form`
// width — so a row that levels a 220px dropdown with two buttons has to wrap
// there. Measured, at the `form` width and as a sheet, at 1x and 2x: it is one
// height and it wraps.
const _dialogInvokerKey = ValueKey<String>('probe-dialog-invoker');
const _dialogFieldKey = ValueKey<String>('probe-dialog-field');

/// The row a dialog would carry: a labelled dropdown and a labelled text field
/// beside a bordered button and a text button — the mix the filter row exists
/// for, in the content column instead of on a page.
Widget _dialogRow() => AppFilterRow(
      children: [
        _dropdown(),
        SizedBox(
          width: 160,
          child: TextField(
            key: _dialogFieldKey,
            decoration: const InputDecoration(
              labelText: 'Raise this many days early',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        OutlinedButton(
          key: _buttonKey,
          onPressed: () {},
          child: const Text('Pick a date'),
        ),
        TextButton(key: _textButtonKey, onPressed: () {}, child: const Text('Clear')),
      ],
    );

/// Opens [AppDialog] at `form` width around [_dialogRow] and returns the height
/// the row is levelled to, measured inside the dialog's own context.
///
/// It is opened through `showDialog` from a button because a dialog is a route
/// (the convention `app_dialog_test.dart` sets): the route hands `AppDialog` the
/// whole window, so `physicalSize` is the box here, and the sheet trigger is
/// decided from that box and the text scale, not from a `SizedBox` a test made.
Future<double> _pumpInDialog(
  WidgetTester tester, {
  Size window = const Size(1280, 900),
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = window;
  addTearDown(tester.view.reset);
  late double controlHeight;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildAppTheme(),
      debugShowCheckedModeBanner: false,
      // The text scale lives on the app's own `builder`, above the Navigator: a
      // dialog is a route, and `MediaQuery` placed *under* the Navigator would
      // not reach it (no `InheritedTheme.capture` carries it across the route).
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (inner) {
            controlHeight = AppFilterRow.controlHeight(inner);
            return Align(
              alignment: Alignment.topLeft,
              child: OutlinedButton(
                key: _dialogInvokerKey,
                onPressed: () => showDialog<void>(
                  context: inner,
                  builder: (_) => AppDialog(
                    title: 'Log a measure',
                    description: 'What will be done, and by when.',
                    size: AppDialogSize.form,
                    actions: [
                      AppDialogAction(
                        id: 'cancel',
                        label: 'Cancel',
                        kind: AppDialogActionKind.dismiss,
                        onPressed: () {},
                      ),
                      AppDialogAction(id: 'save', label: 'Save', onPressed: () {}),
                    ],
                    child: _dialogRow(),
                  ),
                ),
                child: const Text('Open'),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(_dialogInvokerKey));
  await tester.pumpAndSettle();
  return controlHeight;
}


void main() {
  for (final width in <double>[700, 900, 1280]) {
    for (final textScale in <double>[1, 2]) {
      testWidgets('every control in the row is one height — ${width}px, ${textScale}x',
          (tester) async {
        final controlHeight = await _pump(tester, child: _row(), width: width, textScale: textScale);

        expect(controlHeight, greaterThanOrEqualTo(AppTouchTarget.min),
            reason: 'the row never goes under the platform tap floor');

        for (final finder in <Finder>[
          find.byKey(_dropdownKey),
          _filterFieldBox,
          find.byKey(_buttonKey),
          find.byKey(_textButtonKey),
        ]) {
          expect(tester.getSize(finder).height, controlHeight,
              reason: '$finder is not the row height at ${width}px, ${textScale}x');
        }
      });
    }
  }

  testWidgets('the controls share one top edge, so their boxes line up', (tester) async {
    await _pump(tester, child: _row());

    final top = tester.getTopLeft(find.byKey(_dropdownKey)).dy;
    for (final finder in <Finder>[
      _filterFieldBox,
      find.byKey(_buttonKey),
      find.byKey(_textButtonKey),
    ]) {
      expect(tester.getTopLeft(finder).dy, top, reason: '$finder is not level with the dropdown');
    }
  });

  testWidgets('the row wraps at 700px with 200% text, and stays one height', (tester) async {
    await _pump(tester, child: _row(), width: 700, textScale: 2);

    // More than one line: the dropdown's bottom is above the last control's top.
    final dropdownBottom = tester.getBottomLeft(find.byKey(_dropdownKey)).dy;
    final lastTop = tester.getTopLeft(find.byKey(_textButtonKey)).dy;
    expect(lastTop, greaterThan(dropdownBottom), reason: 'the row did not wrap, so this case proves nothing');
  });

  // **The number in `AppFilterRow.controlHeight` is Material's, measured.** If a
  // Material change moves the metric, the row's own floor is stale and would
  // clip a control — so this test compares the constant against a bare field's
  // own rendered height at five text scales, and names the divergence.
  for (final textScale in <double>[1, 1.25, 1.5, 1.75, 2]) {
    testWidgets('controlHeight is the labelled field\'s own height at ${textScale}x',
        (tester) async {
      final controlHeight = await _pump(tester, child: _dropdown(), textScale: textScale);
      expect(tester.getSize(find.byKey(_dropdownKey)).height, controlHeight,
          reason: 'a labelled dense outline field is no longer ${controlHeight}px at ${textScale}x '
              '— AppFilterRow.controlHeight needs re-measuring');
    });
  }

  // The reason the row is 56 at a text scale of 1 and not 44: at twice the text a
  // labelled field holds its value only if the box is this tall. Forcing it lower
  // runs the floating label through the value it labels.
  testWidgets('at 200% text the label and the value do not overlap', (tester) async {
    await _pump(tester, child: _row(), width: 1280, textScale: 2);

    final label = tester.getRect(find.text('Site'));
    final value = tester.getRect(find.text('Plant A').first);
    expect(value.top, greaterThanOrEqualTo(label.bottom),
        reason: 'the floating label runs into the value it labels');
  });

  testWidgets('a control narrower than the row keeps its own width', (tester) async {
    await _pump(tester, child: _row(), width: 1280);
    expect(tester.getSize(find.byKey(_dropdownKey)).width, 220);
  });

  // ---- In a dialog (#477) ------------------------------------------------
  //
  // The card that carried the filter row left dialogs out; this is the answer to
  // the question it left open — does the shape hold in a dialog's own column, at
  // its own widths and as a sheet? Every control the row is given must be the
  // row height, whatever the box the dialog has.
  for (final (window, textScale, shape) in <(Size, double, String)>[
    (const Size(1280, 900), 1, 'a 520 form on a wide window'),
    (const Size(1280, 900), 2, 'a sheet, at 200% text'),
    (const Size(640, 900), 1, 'a sheet, in a 640px box'),
  ]) {
    testWidgets('a dialog row is one height — $shape', (tester) async {
      final controlHeight = await _pumpInDialog(tester, window: window, textScale: textScale);

      expect(controlHeight, greaterThanOrEqualTo(AppTouchTarget.min),
          reason: 'the row never goes under the platform tap floor');

      for (final finder in <Finder>[
        find.byKey(_dropdownKey),
        find.byKey(_dialogFieldKey),
        find.byKey(_buttonKey),
        find.byKey(_textButtonKey),
      ]) {
        expect(tester.getSize(finder).height, controlHeight,
            reason: '$finder is not the row height in $shape');
      }
    });
  }

  testWidgets('a 520 form is narrower than the row, so the row wraps there and keeps its height',
      (tester) async {
    final controlHeight = await _pumpInDialog(tester);

    // The dialog's content column is narrower than the row's natural width, so
    // the last control is on a second line: the case is real, not a page in
    // disguise.
    expect(
      tester.getTopLeft(find.byKey(_textButtonKey)).dy,
      greaterThan(tester.getBottomLeft(find.byKey(_dropdownKey)).dy),
      reason: 'the row did not wrap in the 520 form, so this case proves nothing',
    );
    expect(tester.getSize(find.byKey(_textButtonKey)).height, controlHeight);
  });
}
