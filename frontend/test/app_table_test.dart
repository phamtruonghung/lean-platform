/// `AppTableHeader` and `AppTableRow`: the register's band and rows, built from
/// one column spec.
///
/// Mounted like `app_page_header_test.dart`: a small `MaterialApp` with the
/// app's own theme and no `FakeWire`. The table is wrapped in a `SizedBox` so the
/// **box** is what it sees, and the text scale is set by a `MediaQuery` inside
/// the app. The assertions are measured: where a header label and its cells
/// start, how tall a row is, and where an end-aligned cell ends.
///
/// The row-height cases use plain text cells on purpose. A `StatusChip` is a
/// Material `Chip` with its own height, and a row is allowed to grow for a tall
/// cell; what is pinned here is the height of a row whose cells fit the rule.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/status_tone.dart';
import 'package:lean_platform/theme.dart';
import 'package:lean_platform/widgets/app_table.dart';
import 'package:lean_platform/widgets/status_chip.dart';

import 'harness.dart';

const _columns = <AppTableColumn>[
  AppTableColumn('Code', flex: 2),
  AppTableColumn('Summary', flex: 4),
  AppTableColumn('Qty', width: 80, align: AppColumnAlign.end),
  AppTableColumn('Status', width: 120),
];

const _goldenKey = ValueKey<String>('test-table-golden');

List<Widget> _textCells(BuildContext context, {String code = 'WO-1001', String qty = '12'}) => [
      Text(code, style: AppTypography.dense(context)?.copyWith(color: AppColors.of(context).textMuted)),
      Text('Replace the conveyor belt', style: AppTypography.dense(context)),
      Text(qty, style: AppTableRow.numberStyle(context)),
      Text('Open', style: AppTypography.dense(context)),
    ];

Future<void> _pump(
  WidgetTester tester, {
  double boxWidth = 900,
  double textScale = 1,
  VoidCallback? onTap,
  int rows = 2,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1400, 900);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: boxWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const AppTableHeader(columns: _columns),
                    for (var i = 0; i < rows; i++)
                      Builder(
                        builder: (context) => AppTableRow(
                          columns: _columns,
                          cells: _textCells(context, qty: '${i + 1}2'),
                          onTap: onTap,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Finder _cell(int index) => find.byKey(AppTableRow.cellKey(index)).first;

void main() {
  setUpAll(loadAppFonts);

  for (final width in [700.0, 1280.0]) {
    testWidgets('at $width of box a start-aligned header label and its cell start at the same x',
        (tester) async {
      await _pump(tester, boxWidth: width);
      for (final entry in {0: 'Code', 1: 'Summary', 3: 'Status'}.entries) {
        expect(
          tester.getTopLeft(find.byKey(AppTableHeader.labelKey(entry.value))).dx,
          closeTo(tester.getTopLeft(_cell(entry.key)).dx, 1),
          reason: '${entry.value} label and cell share one column spec',
        );
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('at $width of box an end-aligned header label and its cell end at the same x',
        (tester) async {
      await _pump(tester, boxWidth: width);
      expect(
        tester.getBottomRight(find.byKey(AppTableHeader.labelKey('Qty'))).dx,
        closeTo(tester.getBottomRight(_cell(2)).dx, 1),
      );
    });
  }

  testWidgets('at 2x text the labels and cells still start at the same x and nothing overflows',
      (tester) async {
    await _pump(tester, boxWidth: 700, textScale: 2);
    for (final entry in {0: 'Code', 1: 'Summary', 3: 'Status'}.entries) {
      expect(
        tester.getTopLeft(find.byKey(AppTableHeader.labelKey(entry.value))).dx,
        closeTo(tester.getTopLeft(_cell(entry.key)).dx, 1),
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('a row nobody can tap is exactly AppTableRow.height tall', (tester) async {
    await _pump(tester);
    expect(tester.getSize(find.byType(AppTableRow).first).height, AppTableRow.height);
    expect(AppTableRow.height, 32);
  });

  testWidgets('a row directly under a bounded parent is still exactly AppTableRow.height tall',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 900,
              child: Builder(
                builder: (context) => AppTableRow(columns: _columns, cells: _textCells(context)),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(AppTableRow)).height, AppTableRow.height);
  });

  testWidgets('a row with an onTap is exactly AppTouchTarget.min tall, and the whole row is the target',
      (tester) async {
    await _pump(tester, onTap: () {});
    final row = find.byType(AppTableRow).first;
    expect(tester.getSize(row).height, AppTouchTarget.min);
    expect(tester.getSize(find.descendant(of: row, matching: find.byType(InkWell))).height, AppTouchTarget.min);
    expect(
      tester.getSize(find.descendant(of: row, matching: find.byType(InkWell))).width,
      tester.getSize(row).width,
    );
  });

  testWidgets('the header band is at least AppTableHeader.height tall and full width', (tester) async {
    await _pump(tester);
    final size = tester.getSize(find.byType(AppTableHeader));
    expect(size.height, AppTableHeader.height);
    expect(size.width, 900);
  });

  testWidgets('an end-aligned column ends to the right of a start-aligned one', (tester) async {
    await _pump(tester);
    expect(tester.getBottomRight(_cell(2)).dx, greaterThan(tester.getBottomRight(_cell(1)).dx));
    // The Qty column is 80 wide with a Spacing.sm inset: its digits end 8 short
    // of the column's right edge, which is itself the Status column's left edge.
    expect(
      tester.getBottomRight(_cell(2)).dx,
      closeTo(tester.getTopLeft(_cell(3)).dx - Spacing.sm, 1),
    );
  });

  testWidgets('a column that states a width is that wide, and flex columns share the rest by weight',
      (tester) async {
    await _pump(tester, boxWidth: 900);
    final code = tester.getTopLeft(_cell(0)).dx;
    final summary = tester.getTopLeft(_cell(1)).dx;
    final qty = tester.getTopLeft(find.byKey(AppTableHeader.labelKey('Qty'))).dx;
    final status = tester.getTopLeft(_cell(3)).dx;
    // 900 less 24 of horizontal padding, 200 of fixed columns: 676 for 6 shares.
    final share = (900 - 2 * Spacing.md - 80 - 120) / 6;
    expect(summary - code, closeTo(share * 2, 1));
    expect(status, closeTo(900 - Spacing.md - 120, 1));
    expect(qty, lessThan(status));
  });

  testWidgets('each header label is a header to a screen reader, in sentence case', (tester) async {
    await _pump(tester);
    final handle = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.byKey(AppTableHeader.labelKey('Summary'))),
      matchesSemantics(label: 'Summary', isHeader: true),
    );
    handle.dispose();
    expect(find.text('Summary'), findsOneWidget);
    expect(find.text('SUMMARY'), findsNothing);
  });

  testWidgets('the label is labelMedium at w600 in the muted text colour, on the band fill',
      (tester) async {
    await _pump(tester);
    final text = tester.widget<Text>(find.byKey(AppTableHeader.labelKey('Code')));
    final context = tester.element(find.byKey(AppTableHeader.labelKey('Code')));
    final palette = AppColors.of(context);
    expect(text.style?.fontWeight, FontWeight.w600);
    expect(text.style?.color, palette.textMuted);
    expect(text.style?.fontSize, Theme.of(context).textTheme.labelMedium?.fontSize);
    expect(text.style?.fontSize, 12);
    final decorated = tester.widget<Container>(
      find.descendant(of: find.byType(AppTableHeader), matching: find.byType(Container)).first,
    );
    final decoration = decorated.decoration! as BoxDecoration;
    expect(decoration.color, palette.tableHeaderFill);
  });

  testWidgets('a row with no onTap has no InkWell, so nothing hovers; the band never has one',
      (tester) async {
    await _pump(tester);
    expect(find.descendant(of: find.byType(AppTableRow).first, matching: find.byType(InkWell)), findsNothing);
    expect(find.descendant(of: find.byType(AppTableHeader), matching: find.byType(InkWell)), findsNothing);
  });

  testWidgets('a tappable row calls onTap, hovers in rowHoverFill and has no ripple', (tester) async {
    var taps = 0;
    await _pump(tester, onTap: () => taps++);
    final ink = find.descendant(of: find.byType(AppTableRow).first, matching: find.byType(InkWell));
    await tester.tap(ink);
    expect(taps, 1);
    final widget = tester.widget<InkWell>(ink);
    expect(widget.hoverColor, AppColors.of(tester.element(ink)).rowHoverFill);
    expect(widget.splashFactory, NoSplash.splashFactory);
  });

  testWidgets('every row ends in a hairline of the palette edge', (tester) async {
    await _pump(tester);
    final context = tester.element(find.byType(AppTableRow).first);
    final container = tester.widget<Container>(
      find.descendant(of: find.byType(AppTableRow).first, matching: find.byType(Container)).first,
    );
    final border = (container.foregroundDecoration! as BoxDecoration).border! as Border;
    expect(border.bottom.color, AppColors.of(context).edge);
    expect(border.top, BorderSide.none);
  });

  testWidgets('numberStyle is the dense style with tabular figures', (tester) async {
    await _pump(tester);
    final text = tester.widget<Text>(
      find.descendant(of: _cell(2), matching: find.byType(Text)).first,
    );
    expect(text.style?.fontFeatures, contains(const FontFeature.tabularFigures()));
    expect(text.style?.fontSize, Theme.of(tester.element(_cell(2))).textTheme.bodyMedium?.fontSize);
  });

  testWidgets('a row with a different number of cells than columns is refused', (tester) async {
    expect(
      () => AppTableRow(columns: _columns, cells: const [Text('only one')]),
      throwsAssertionError,
    );
  });

  testWidgets('the table matches its golden: a band, three rows, one count, one code, one tone',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 400);
    addTearDown(tester.view.reset);
    const columns = <AppTableColumn>[
      AppTableColumn('WO#', flex: 2),
      AppTableColumn('Summary', flex: 4),
      AppTableColumn('Hours', width: 80, align: AppColumnAlign.end),
      AppTableColumn('Status', width: 140),
    ];
    Widget row(BuildContext context, String no, String summary, String hours, String status, StatusTone tone,
            {VoidCallback? onTap}) =>
        AppTableRow(
          columns: columns,
          onTap: onTap,
          cells: [
            Text(no, style: AppTypography.dense(context)?.copyWith(color: AppColors.of(context).textMuted)),
            Text(summary, style: AppTypography.dense(context)?.copyWith(color: AppColors.of(context).textPrimary)),
            Text(hours, style: AppTableRow.numberStyle(context)),
            StatusChip(label: status, tone: tone),
          ],
        );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        debugShowCheckedModeBanner: false,
        home: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: _goldenKey,
            child: Material(
              child: Padding(
                padding: const EdgeInsets.all(Spacing.lg),
                child: SizedBox(
                  width: 900,
                  child: Builder(
                    builder: (context) => Card(
                      margin: EdgeInsets.zero,
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const AppTableHeader(columns: columns),
                          row(context, 'WO-1001', 'Replace the conveyor belt', '12.5', 'In progress', StatusTone.info),
                          row(context, 'WO-1002', 'Grease the press bearings', '3', 'Done', StatusTone.success,
                              onTap: () {}),
                          row(context, 'WO-1003', 'Inspect the coolant pump', '140.25', 'Waiting', StatusTone.warning),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await expectLater(find.byKey(_goldenKey), matchesGoldenFile('goldens/app_table.png'));
  });
}
