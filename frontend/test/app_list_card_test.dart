/// `AppListCard` on its own (issue #189) — the shared card a catalogue's rows
/// sit in. Mounted in a real `MaterialApp` with the app's own theme, asserted
/// on what renders, the way the other shared widgets' own tests are.
///
/// What these tests claim: that a rule is drawn between rows and never around
/// the outside, that a one-row catalogue gets no stray rule, and that the rows
/// are the caller's own widgets rather than rebuilt ones — a wrapping
/// implementation would move every row's `Key` one level down the tree, and the
/// last of these tests is what fails if that ever happens.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/theme.dart';
import 'package:lean_platform/widgets/app_list_card.dart';

Future<void> pumpCard(WidgetTester tester, List<Widget> rows) => tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Center(
            child: SizedBox(width: 600, child: AppListCard(rows: rows)),
          ),
        ),
      ),
    );

void main() {
  testWidgets('a rule is drawn between rows, and none around the outside',
      (WidgetTester tester) async {
    await pumpCard(tester, const [
      Text('Welding · WELD'),
      Text('First aid · FIRST-AID'),
      Text('Forklift operation · FORK'),
    ]);

    // Three rows, two rules — the rule belongs between records, not to the
    // card's own edges.
    expect(find.byType(Divider), findsNWidgets(2));

    final card = tester.getRect(find.byType(Card));
    for (final divider in tester.widgetList<Divider>(find.byType(Divider))) {
      expect(divider.color, AppColors.edge);
      expect(divider.thickness, 1);
    }
    // Every row is inside the card's own box — nothing is drawn outside it.
    for (final row in ['Welding · WELD', 'First aid · FIRST-AID', 'Forklift operation · FORK']) {
      expect(card.contains(tester.getRect(find.text(row)).center), isTrue);
    }
  });

  testWidgets('one row gets no rule at all', (WidgetTester tester) async {
    await pumpCard(tester, const [Text('Welding · WELD')]);

    expect(find.byType(Divider), findsNothing);
  });

  testWidgets('the rows are the caller\'s own widgets, keys and all',
      (WidgetTester tester) async {
    const rowKey = ValueKey<String>('catalogue-row-1');
    await pumpCard(tester, const [
      Padding(key: rowKey, padding: EdgeInsets.all(12), child: Text('Welding · WELD')),
      Padding(padding: EdgeInsets.all(12), child: Text('First aid · FIRST-AID')),
    ]);

    // The key is still findable at its own level: an implementation that
    // wrapped each row would have moved it into a wrapper, and every test in
    // the repo that finds a catalogue row by key would be finding a different
    // element than before.
    expect(find.byKey(rowKey), findsOneWidget);
    expect(tester.widget<Padding>(find.byKey(rowKey)).padding, const EdgeInsets.all(12));
  });
}
