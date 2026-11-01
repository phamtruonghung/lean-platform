/// `AppDetailSection`: a titled card on a detail Screen.
///
/// Mounted like `app_page_header_test.dart`: a small `MaterialApp` with the
/// app's own theme and no `FakeWire`, the section in a `SizedBox` so the box is
/// what it sees, and the text scale set by a `MediaQuery` inside the app.
///
/// What is measured is the section's one left edge (the title and its rows start
/// at the same x), that the hairline spans the card, and that a large text size
/// grows the card rather than overflowing it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/theme.dart';
import 'package:lean_platform/widgets/app_detail_section.dart';

import 'harness.dart';

const _firstKey = ValueKey<String>('test-first-row');
const _secondKey = ValueKey<String>('test-second-row');
const _trailingKey = ValueKey<String>('test-trailing');
const _goldenKey = ValueKey<String>('test-detail-section-golden');

Future<void> _pump(
  WidgetTester tester, {
  double boxWidth = 700,
  double textScale = 1,
  String title = 'Parts used',
  bool trailing = true,
  bool rows = true,
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
                child: AppDetailSection(
                  title: title,
                  trailing: trailing
                      ? TextButton(key: _trailingKey, onPressed: () {}, child: const Text('Add part'))
                      : null,
                  children: rows
                      ? const [
                          Text('Bearing 6204', key: _firstKey),
                          Text('Grease cartridge', key: _secondKey),
                        ]
                      : const [],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(loadAppFonts);

  for (final width in [700.0, 1280.0]) {
    testWidgets('at $width of box the title and the first row share one left edge', (tester) async {
      await _pump(tester, boxWidth: width);
      expect(
        tester.getTopLeft(find.byKey(AppDetailSection.titleKey('Parts used'))).dx,
        tester.getTopLeft(find.byKey(_firstKey)).dx,
      );
      expect(
        tester.getTopLeft(find.byKey(AppDetailSection.titleKey('Parts used'))).dx,
        tester.getTopLeft(find.byType(Card)).dx + Spacing.lg,
      );
    });

    testWidgets('at $width of box the hairline spans the card, edge to edge', (tester) async {
      await _pump(tester, boxWidth: width);
      final card = tester.getSize(find.byType(Card));
      expect(card.width, width);
      expect(tester.getSize(find.byKey(AppDetailSection.dividerKey)).width, card.width);
      expect(tester.getTopLeft(find.byKey(AppDetailSection.dividerKey)).dx, tester.getTopLeft(find.byType(Card)).dx);
    });
  }

  testWidgets('the trailing action sits at the far end of the title row, Spacing.lg inside the card',
      (tester) async {
    await _pump(tester);
    final card = tester.getBottomRight(find.byType(Card));
    expect(tester.getBottomRight(find.byKey(_trailingKey)).dx, card.dx - Spacing.lg);
    expect(
      tester.getTopLeft(find.byKey(_trailingKey)).dx,
      greaterThan(tester.getBottomRight(find.byKey(AppDetailSection.titleKey('Parts used'))).dx - 1),
    );
  });

  testWidgets('the hairline sits under the title row and above the rows', (tester) async {
    await _pump(tester);
    final divider = tester.getTopLeft(find.byKey(AppDetailSection.dividerKey)).dy;
    expect(divider, greaterThanOrEqualTo(tester.getBottomRight(find.byKey(AppDetailSection.titleKey('Parts used'))).dy));
    expect(divider, greaterThanOrEqualTo(tester.getBottomRight(find.byKey(_trailingKey)).dy));
    expect(tester.getTopLeft(find.byKey(_firstKey)).dy, divider + 1 + Spacing.md);
  });

  testWidgets('the title has Spacing.md above it and Spacing.sm between it and the hairline',
      (tester) async {
    await _pump(tester, trailing: false);
    final title = find.byKey(AppDetailSection.titleKey('Parts used'));
    expect(tester.getTopLeft(title).dy - tester.getTopLeft(find.byType(Card)).dy, Spacing.md);
    expect(tester.getTopLeft(find.byKey(AppDetailSection.dividerKey)).dy - tester.getBottomRight(title).dy, Spacing.sm);
  });

  testWidgets('rows are Spacing.sm apart and Spacing.lg clear of the card\'s bottom', (tester) async {
    await _pump(tester);
    expect(
      tester.getTopLeft(find.byKey(_secondKey)).dy - tester.getBottomRight(find.byKey(_firstKey)).dy,
      Spacing.sm,
    );
    expect(
      tester.getBottomRight(find.byType(Card)).dy - tester.getBottomRight(find.byKey(_secondKey)).dy,
      Spacing.lg,
    );
  });

  testWidgets('the title is a header to a screen reader, titleMedium at w600 in the primary text colour',
      (tester) async {
    await _pump(tester);
    final handle = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.byKey(AppDetailSection.titleKey('Parts used'))),
      matchesSemantics(label: 'Parts used', isHeader: true),
    );
    handle.dispose();
    final text = tester.widget<Text>(find.byKey(AppDetailSection.titleKey('Parts used')));
    final context = tester.element(find.byKey(AppDetailSection.titleKey('Parts used')));
    expect(text.style?.fontWeight, FontWeight.w600);
    expect(text.style?.fontSize, Theme.of(context).textTheme.titleMedium?.fontSize);
    expect(text.style?.fontSize, 16);
    expect(text.style?.color, AppColors.of(context).textPrimary);
  });

  testWidgets('the hairline is the palette edge, one pixel thick', (tester) async {
    await _pump(tester);
    final divider = tester.widget<Divider>(find.byKey(AppDetailSection.dividerKey));
    expect(divider.color, AppColors.of(tester.element(find.byKey(AppDetailSection.dividerKey))).edge);
    expect(divider.thickness, 1);
    expect(divider.height, 1);
  });

  testWidgets('the card\'s column states that it stretches, and the card has no margin', (tester) async {
    await _pump(tester);
    final card = tester.widget<Card>(find.byType(Card));
    expect(card.margin, EdgeInsets.zero);
    final column = tester.widget<Column>(find.descendant(of: find.byType(Card), matching: find.byType(Column)).first);
    expect(column.crossAxisAlignment, CrossAxisAlignment.stretch);
  });

  testWidgets('with no rows there is no body and the card ends under the hairline', (tester) async {
    await _pump(tester, rows: false);
    expect(find.byKey(AppDetailSection.bodyKey), findsNothing);
    expect(
      tester.getBottomRight(find.byType(Card)).dy,
      closeTo(tester.getBottomRight(find.byKey(AppDetailSection.dividerKey)).dy, 1),
    );
  });

  testWidgets('with no trailing action the title takes the whole row', (tester) async {
    await _pump(tester, trailing: false);
    expect(find.byKey(_trailingKey), findsNothing);
    expect(tester.getBottomRight(find.byKey(AppDetailSection.titleKey('Parts used'))).dx,
        tester.getBottomRight(find.byType(Card)).dx - Spacing.lg);
  });

  testWidgets('at 2x text nothing overflows, the card grows and the left edge is still shared',
      (tester) async {
    await _pump(tester, boxWidth: 700);
    final normal = tester.getSize(find.byType(Card)).height;
    await _pump(tester, boxWidth: 700, textScale: 2);
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(Card)).height, greaterThan(normal));
    expect(
      tester.getTopLeft(find.byKey(AppDetailSection.titleKey('Parts used'))).dx,
      tester.getTopLeft(find.byKey(_firstKey)).dx,
    );
    expect(tester.getBottomRight(find.byKey(_secondKey)).dy, lessThan(tester.getBottomRight(find.byType(Card)).dy));
  });

  testWidgets('at 2x text a long title beside an action wraps instead of overflowing', (tester) async {
    await _pump(
      tester,
      boxWidth: 400,
      textScale: 2,
      title: 'Parts and consumables used on this work order',
    );
    expect(tester.takeException(), isNull);
    expect(
      tester.getBottomRight(find.byKey(_trailingKey)).dx,
      lessThanOrEqualTo(tester.getBottomRight(find.byType(Card)).dx),
    );
  });

  testWidgets('the section matches its golden at 700', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 400);
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
                  width: 700,
                  child: AppDetailSection(
                    title: 'Parts used',
                    trailing: TextButton(onPressed: () {}, child: const Text('Add part')),
                    children: const [
                      Text('Bearing 6204, quantity 2'),
                      Text('Grease cartridge, quantity 1'),
                      Text('Drive belt B42, quantity 1'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await expectLater(find.byKey(_goldenKey), matchesGoldenFile('goldens/app_detail_section.png'));
  });
}
