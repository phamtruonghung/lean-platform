import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/maintenance/row_disclosure.dart';
import 'package:lean_platform/theme.dart';
import 'package:lean_platform/widgets/app_table.dart';

const ValueKey<String> _toggleKey = ValueKey<String>('test-disclosure-toggle');
const ValueKey<String> _bodyKey = ValueKey<String>('test-disclosure-body');

const List<AppTableColumn> _columns = [
  AppTableColumn('Name', flex: 3),
  AppTableColumn('Steps', flex: 2),
];

Future<void> _pump(WidgetTester tester, {bool disableAnimations = false}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(Brightness.light),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: disableAnimations),
          child: Scaffold(
            body: SizedBox(
              width: 600,
              child: RowDisclosure(
                key: const ValueKey<String>('plan-1'),
                toggleKey: _toggleKey,
                label: '3 steps',
                rowBuilder: (context, toggle) =>
                    AppTableRow(columns: _columns, cells: [const Text('Annual service'), toggle]),
                child: const Text('1. Isolate the motor', key: _bodyKey),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('the block is not in the tree until the toggle is pressed', (tester) async {
    await _pump(tester);
    expect(find.byKey(_bodyKey), findsNothing);
  });

  testWidgets('pressing the toggle shows the block and pressing it again hides it', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(_toggleKey));
    await tester.pumpAndSettle();
    expect(find.byKey(_bodyKey), findsOneWidget);

    await tester.tap(find.byKey(_toggleKey));
    await tester.pumpAndSettle();
    expect(find.byKey(_bodyKey), findsNothing);
  });

  testWidgets('the toggle is at least 44 by 44', (tester) async {
    await _pump(tester);
    final size = tester.getSize(find.byKey(_toggleKey));
    expect(size.width, greaterThanOrEqualTo(AppTouchTarget.min));
    expect(size.height, greaterThanOrEqualTo(AppTouchTarget.min));
  });

  testWidgets('the toggle carries a tooltip and a semantics label that follow its state', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.byTooltip('Show 3 steps'), findsOneWidget);
    expect(find.bySemanticsLabel('Show 3 steps'), findsOneWidget);

    await tester.tap(find.byKey(_toggleKey));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Hide 3 steps'), findsOneWidget);
    expect(find.bySemanticsLabel('Hide 3 steps'), findsOneWidget);
  });

  testWidgets('the caller\'s label is shown beside the chevron', (tester) async {
    await _pump(tester);
    expect(find.text('3 steps'), findsOneWidget);
  });

  testWidgets('its motion is at most 200ms, and zero when animations are disabled', (tester) async {
    await _pump(tester);
    expect(
      tester.widget<AnimatedRotation>(find.byType(AnimatedRotation)).duration,
      lessThanOrEqualTo(const Duration(milliseconds: 200)),
    );
    expect(
      tester.widget<AnimatedSize>(find.byType(AnimatedSize)).duration,
      lessThanOrEqualTo(const Duration(milliseconds: 200)),
    );

    await _pump(tester, disableAnimations: true);
    expect(tester.widget<AnimatedRotation>(find.byType(AnimatedRotation)).duration, Duration.zero);
    expect(tester.widget<AnimatedSize>(find.byType(AnimatedSize)).duration, Duration.zero);
  });

  testWidgets('the block starts at the row\'s own first-cell edge', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(_toggleKey));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.byKey(_bodyKey)).dx,
      tester.getTopLeft(find.text('Annual service')).dx,
    );
  });
  testWidgets(
    'a screen reader gets a button with a tap action, and performing it toggles the block',
    (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);

      final node = tester.getSemantics(find.bySemanticsLabel('Show 3 steps'));
      expect(node, isSemantics(isButton: true, hasTapAction: true, label: 'Show 3 steps'));
      expect(find.byKey(_bodyKey), findsNothing);

      tester.semantics.tap(find.semantics.byLabel('Show 3 steps'));
      await tester.pumpAndSettle();
      expect(find.byKey(_bodyKey), findsOneWidget);
      expect(find.bySemanticsLabel('Hide 3 steps'), findsOneWidget);
      handle.dispose();
    },
  );

  testWidgets('an open row scrolled far out of a ListView and back is still open', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: Scaffold(
          body: ListView(
            children: [
              for (var i = 0; i < 40; i++)
                RowDisclosure(
                  key: ValueKey<String>('plan-$i'),
                  toggleKey: ValueKey<String>('toggle-$i'),
                  label: '1 step',
                  rowBuilder: (context, toggle) =>
                      AppTableRow(columns: _columns, cells: [Text('Plan $i'), toggle]),
                  child: Text('Body $i', key: ValueKey<String>('body-$i')),
                ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey<String>('toggle-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('body-0')), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -6000));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('toggle-0')), findsNothing);

    await tester.drag(find.byType(ListView), const Offset(0, 6000));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('body-0')), findsOneWidget);
  });
}
