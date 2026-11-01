/// `AppSectionGrid`: a detail page's sections, two columns from 1000 of box.
///
/// Mounted like `app_page_header_test.dart`: a small `MaterialApp` with the
/// app's own theme and no `FakeWire`. The grid sits in a `SizedBox` so the
/// **box** is what it sees while the window stays a fixed 2300 wide, wider than
/// any box here, to prove the columns are chosen by the box and not the window;
/// the text scale is set by a `MediaQuery` inside the app.
///
/// The sections are real `AppDetailSection`s, since that is what the grid exists
/// to lay out, and the measured claims are the ones its comment makes: two share
/// a `dy` and a width wide, they stack narrow, and a section whose text wraps
/// does not leave its neighbour short.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/theme.dart';
import 'package:lean_platform/widgets/app_detail_section.dart';
import 'package:lean_platform/widgets/app_section_grid.dart';

import 'harness.dart';

const _aKey = ValueKey<String>('test-section-a');
const _bKey = ValueKey<String>('test-section-b');
const _cKey = ValueKey<String>('test-section-c');
const _goldenKey = ValueKey<String>('test-section-grid-golden');

List<Widget> _sections({int count = 2, bool tallSecond = false}) => [
      AppDetailSection(
        key: _aKey,
        title: 'Summary',
        children: const [Text('Raised by Sam Hall')],
      ),
      AppDetailSection(
        key: _bKey,
        title: 'Parts used',
        children: [
          const Text('Bearing 6204'),
          if (tallSecond) ...[
            const Text('Grease cartridge'),
            const Text('Drive belt B42'),
            const Text('Coolant filter'),
          ],
        ],
      ),
      if (count > 2)
        AppDetailSection(
          key: _cKey,
          title: 'History',
          children: const [Text('Raised on Monday')],
        ),
    ];

Future<void> _pump(
  WidgetTester tester, {
  double boxWidth = 1280,
  double textScale = 1,
  int count = 2,
  bool tallSecond = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(2300, 900);
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
                child: AppSectionGrid(sections: _sections(count: count, tallSecond: tallSecond)),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// True when the second section sits beside the first rather than under it.
bool _twoColumns(WidgetTester tester) =>
    tester.getTopLeft(find.byKey(_bKey)).dy == tester.getTopLeft(find.byKey(_aKey)).dy;

void main() {
  setUpAll(loadAppFonts);

  testWidgets('at 1280 two sections share a dy and are the same width, Spacing.md apart', (tester) async {
    await _pump(tester, boxWidth: 1280);
    final a = find.byKey(_aKey);
    final b = find.byKey(_bKey);
    expect(tester.getTopLeft(b).dy, tester.getTopLeft(a).dy);
    expect(tester.getSize(b).width, tester.getSize(a).width);
    expect(tester.getTopLeft(b).dx - tester.getBottomRight(a).dx, Spacing.md);
    expect(tester.getTopLeft(a).dx, 0);
    expect(tester.getBottomRight(b).dx, 1280);
    expect(tester.takeException(), isNull);
  });

  testWidgets('at 700 the second section sits under the first, one column at the box width',
      (tester) async {
    await _pump(tester, boxWidth: 700);
    final a = find.byKey(_aKey);
    final b = find.byKey(_bKey);
    expect(tester.getTopLeft(b).dy, greaterThan(tester.getBottomRight(a).dy));
    expect(tester.getTopLeft(b).dy - tester.getBottomRight(a).dy, Spacing.md);
    expect(tester.getSize(a).width, 700);
    expect(tester.getSize(b).width, 700);
    expect(tester.getTopLeft(b).dx, tester.getTopLeft(a).dx);
  });

  testWidgets('at 700 with 2x text it is still one column and nothing overflows', (tester) async {
    await _pump(tester, boxWidth: 700, textScale: 2);
    expect(_twoColumns(tester), isFalse);
    expect(tester.getTopLeft(find.byKey(_bKey)).dy, greaterThan(tester.getBottomRight(find.byKey(_aKey)).dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets('at 1280 with 2x text it is one column: the breakpoint doubles to 2000', (tester) async {
    await _pump(tester, boxWidth: 1280, textScale: 2);
    expect(_twoColumns(tester), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the grid goes two-column at 1000 of box width, not one pixel under it', (tester) async {
    await _pump(tester, boxWidth: AppBreakpoints.detailTwoColumn - 1);
    expect(_twoColumns(tester), isFalse);
    await _pump(tester, boxWidth: AppBreakpoints.detailTwoColumn);
    expect(_twoColumns(tester), isTrue);
  });

  testWidgets('at 2x text the edge doubles: one column at 1999, two at 2000', (tester) async {
    await _pump(tester, boxWidth: AppBreakpoints.detailTwoColumn * 2 - 1, textScale: 2);
    expect(_twoColumns(tester), isFalse);
    await _pump(tester, boxWidth: AppBreakpoints.detailTwoColumn * 2, textScale: 2);
    expect(_twoColumns(tester), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('below 1x text the breakpoint is not lowered: 1000 is two columns at 0.8, 999 is one',
      (tester) async {
    await _pump(tester, boxWidth: AppBreakpoints.detailTwoColumn, textScale: 0.8);
    expect(_twoColumns(tester), isTrue);
    await _pump(tester, boxWidth: AppBreakpoints.detailTwoColumn - 1, textScale: 0.8);
    expect(_twoColumns(tester), isFalse);
  });

  testWidgets('the grid chooses by the box, not the window: a 600 box in a 2300 window is one column',
      (tester) async {
    await _pump(tester, boxWidth: 600);
    expect(tester.view.physicalSize.width, 2300);
    expect(_twoColumns(tester), isFalse);
  });

  testWidgets('two sections in a row share a height, so a taller neighbour does not leave one short',
      (tester) async {
    await _pump(tester, boxWidth: 1280, tallSecond: true);
    expect(tester.getSize(find.byKey(_aKey)).height, tester.getSize(find.byKey(_bKey)).height);
    expect(tester.getBottomRight(find.byKey(_aKey)).dy, tester.getBottomRight(find.byKey(_bKey)).dy);
  });

  testWidgets('narrow, sections keep their own heights', (tester) async {
    await _pump(tester, boxWidth: 700, tallSecond: true);
    expect(tester.getSize(find.byKey(_aKey)).height, lessThan(tester.getSize(find.byKey(_bKey)).height));
  });

  testWidgets('an odd last section takes a row of its own at the full box width, wide', (tester) async {
    await _pump(tester, boxWidth: 1280, count: 3);
    final c = find.byKey(_cKey);
    expect(tester.getTopLeft(c).dy - tester.getBottomRight(find.byKey(_aKey)).dy, Spacing.md);
    expect(tester.getTopLeft(c).dx, 0);
    expect(tester.getSize(c).width, 1280, reason: 'a Wrap would leave this half-width and ragged');
  });

  testWidgets('three sections narrow are one column of the same width', (tester) async {
    await _pump(tester, boxWidth: 700, count: 3);
    for (final key in [_aKey, _bKey, _cKey]) {
      expect(tester.getSize(find.byKey(key)).width, 700);
      expect(tester.getTopLeft(find.byKey(key)).dx, 0);
    }
    expect(tester.getTopLeft(find.byKey(_cKey)).dy, greaterThan(tester.getBottomRight(find.byKey(_bKey)).dy));
  });

  testWidgets('wideColumns is two, and the section order is read left to right, then down',
      (tester) async {
    expect(AppSectionGrid.wideColumns, 2);
    await _pump(tester, boxWidth: 1280, count: 3);
    expect(tester.getTopLeft(find.byKey(_bKey)).dx, greaterThan(tester.getTopLeft(find.byKey(_aKey)).dx));
    expect(tester.getTopLeft(find.byKey(_cKey)).dy, greaterThan(tester.getTopLeft(find.byKey(_bKey)).dy));
  });

  testWidgets('no sections draws nothing and does not throw', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: 1280, child: AppSectionGrid(sections: [])),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(AppSectionGrid)).height, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the wide grid matches its golden at 1280', (tester) async {
    await _pumpGolden(tester, boxWidth: 1280, windowWidth: 1400);
    await expectLater(find.byKey(_goldenKey), matchesGoldenFile('goldens/app_section_grid_wide.png'));
  });

  testWidgets('the narrow grid matches its golden at 700', (tester) async {
    await _pumpGolden(tester, boxWidth: 700, windowWidth: 800);
    await expectLater(find.byKey(_goldenKey), matchesGoldenFile('goldens/app_section_grid_narrow.png'));
  });
}

Future<void> _pumpGolden(
  WidgetTester tester, {
  required double boxWidth,
  required double windowWidth,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(windowWidth, 700);
  addTearDown(tester.view.reset);
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
                width: boxWidth,
                child: AppSectionGrid(
                  sections: [
                    AppDetailSection(
                      title: 'Summary',
                      children: const [
                        Text('Raised by Sam Hall'),
                        Text('Priority: high'),
                      ],
                    ),
                    AppDetailSection(
                      title: 'Parts used',
                      trailing: TextButton(onPressed: () {}, child: const Text('Add part')),
                      children: const [
                        Text('Bearing 6204, quantity 2'),
                        Text('Grease cartridge, quantity 1'),
                        Text('Drive belt B42, quantity 1'),
                      ],
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
