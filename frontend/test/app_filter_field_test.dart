/// `AppFilterField` on its own (issue #187) — the shared filter box's own
/// contract, tested the way `app_search_field_test.dart` and
/// `app_date_field_test.dart` test their widgets: mounted in a real
/// `MaterialApp` with the app's own theme, driven through `WidgetTester`, and
/// asserted on what renders.
///
/// What these tests claim: that the count line follows the term rather than the
/// caller, that the clear affordance exists only while there is something to
/// clear and reports an empty term, that a caller which cannot count its rows
/// gets no count line, and that the field is controlled — the term it shows is
/// the caller's, never its own. What they do not claim: anything about what a
/// caller filters with the term, which is the caller's business and is tested
/// where the caller lives (`work_orders_test.dart`'s own assign-dialog cases).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/theme.dart';
import 'package:lean_platform/widgets/app_filter_field.dart';

/// A caller: holds the term the way a Screen does, and offers the two counts —
/// or neither, for the case where only some of its rows are on screen.
class _Host extends StatefulWidget {
  const _Host({this.counts = true, this.enabled = true});

  final bool counts;
  final bool enabled;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  String term = '';

  /// Every term this widget reported, in order — so a test can assert the clear
  /// affordance reported exactly `''` rather than, say, a space.
  final List<String> reported = [];

  /// Clears the term the way a Screen clearing its own filter for a reason of
  /// its own would — from outside the widget, and without the widget's help.
  void clearTermFromOutside() => setState(() => term = '');

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            child: AppFilterField(
              name: 'test-filter',
              label: 'Find a record',
              term: term,
              enabled: widget.enabled,
              shown: widget.counts ? 2 : null,
              total: widget.counts ? 9 : null,
              onChanged: (value) => setState(() {
                reported.add(value);
                term = value;
              }),
            ),
          ),
        ),
      ),
    );
  }
}

void main() {
  Future<_HostState> pumpHost(
    WidgetTester tester, {
    bool counts = true,
    bool enabled = true,
  }) async {
    await tester.pumpWidget(_Host(counts: counts, enabled: enabled));
    return tester.state<_HostState>(find.byType(_Host));
  }

  testWidgets('the count line appears with the term and leaves with it',
      (WidgetTester tester) async {
    await pumpHost(tester);

    // Nothing narrowing the list means nothing to report about it.
    expect(find.byKey(AppFilterField.countKey('test-filter')), findsNothing);

    await tester.enterText(find.byKey(AppFilterField.fieldKey('test-filter')), 'pre');
    await tester.pumpAndSettle();

    expect(find.byKey(AppFilterField.countKey('test-filter')), findsOneWidget);
    expect(find.text(AppFilterField.countLabel(2, 9)), findsOneWidget);
  });

  testWidgets('a caller that cannot count its rows gets no count line',
      (WidgetTester tester) async {
    await pumpHost(tester, counts: false);

    await tester.enterText(find.byKey(AppFilterField.fieldKey('test-filter')), 'pre');
    await tester.pumpAndSettle();

    expect(find.byKey(AppFilterField.countKey('test-filter')), findsNothing);
  });

  testWidgets('the clear affordance exists only while there is something to clear',
      (WidgetTester tester) async {
    final host = await pumpHost(tester);

    expect(find.byKey(AppFilterField.clearKey('test-filter')), findsNothing);

    await tester.enterText(find.byKey(AppFilterField.fieldKey('test-filter')), 'press');
    await tester.pumpAndSettle();
    expect(find.byKey(AppFilterField.clearKey('test-filter')), findsOneWidget);

    await tester.tap(find.byKey(AppFilterField.clearKey('test-filter')));
    await tester.pumpAndSettle();

    // An empty term, not a space: the caller filters with exactly this.
    expect(host.reported.last, '');
    expect(host.term, '');
    expect(find.byKey(AppFilterField.clearKey('test-filter')), findsNothing);
    expect(find.byKey(AppFilterField.countKey('test-filter')), findsNothing);
    // And the field itself is empty again, so the next search does not start
    // from the text that was just cleared.
    expect(tester.widget<TextField>(find.byKey(AppFilterField.fieldKey('test-filter'))).controller?.text,
        '');
  });

  testWidgets('the field follows the caller: a term changed from outside replaces what is on screen',
      (WidgetTester tester) async {
    final host = await pumpHost(tester);

    await tester.enterText(find.byKey(AppFilterField.fieldKey('test-filter')), 'press');
    await tester.pumpAndSettle();
    expect(host.term, 'press');

    // The caller resets its own filter for a reason of its own — the field is
    // controlled, so what it shows is the caller's term, never its own memory
    // of what was typed.
    host.clearTermFromOutside();
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byKey(AppFilterField.fieldKey('test-filter'))).controller?.text,
      '',
    );
    expect(find.byKey(AppFilterField.clearKey('test-filter')), findsNothing);
  });

  testWidgets('a disabled filter box is disabled, and reports nothing', (WidgetTester tester) async {
    await pumpHost(tester, enabled: false);

    expect(tester.widget<TextField>(find.byKey(AppFilterField.fieldKey('test-filter'))).enabled,
        isFalse);
    // A box that cannot be typed into has nothing to clear, so the affordance
    // that would call back with an empty term is not offered either.
    expect(find.byKey(AppFilterField.clearKey('test-filter')), findsNothing);
  });
}
