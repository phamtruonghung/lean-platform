/// `AppStatTile`: the Home tile, lifted.
///
/// Mounted like `app_page_header_test.dart`: a small `MaterialApp` with the
/// app's own theme and no `FakeWire`, because the tile makes no request and owns
/// no navigation (that is the point of `onTap`). The tile sits in a `SizedBox`
/// so the box is what it sees, and the text scale is set by a `MediaQuery`
/// inside the app.
///
/// The measured claims are the ones the Home tile makes in its own comment: the
/// icon tile is 40 by 40, the keyboard focus ring moves no pixel of layout, and
/// at a large text size the caption stays inside the card.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/theme.dart';
import 'package:lean_platform/widgets/app_stat_tile.dart';

import 'harness.dart';

const _goldenKey = ValueKey<String>('test-stat-tile-golden');

Future<void> _pump(
  WidgetTester tester, {
  double boxWidth = 400,
  double textScale = 1,
  String label = 'Open work',
  String figure = '12',
  String? caption = '3 need assigning',
  IconData? icon = Icons.build_outlined,
  VoidCallback? onTap,
  bool quiet = false,
  bool disableAnimations = false,
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
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              disableAnimations: disableAnimations,
            ),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: boxWidth,
                child: AppStatTile(
                  label: label,
                  figure: figure,
                  caption: caption,
                  icon: icon,
                  onTap: onTap,
                  quiet: quiet,
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

  testWidgets('the icon tile is exactly 40 by 40', (tester) async {
    await _pump(tester, onTap: () {});
    expect(tester.getSize(find.byKey(AppStatTile.iconTileKey)), const Size(40, 40));
    expect(AppStatTile.iconTileSize, 40);
    expect(AppStatTile.iconTileRadius, 10);
  });

  testWidgets('the icon tile wears the navigation pair: its fill and its icon colour', (tester) async {
    await _pump(tester, onTap: () {});
    final context = tester.element(find.byKey(AppStatTile.iconTileKey));
    final palette = AppColors.of(context);
    final tile = tester.widget<Container>(find.byKey(AppStatTile.iconTileKey));
    final decoration = tile.decoration! as BoxDecoration;
    expect(decoration.color, palette.navSelectedBackground);
    expect(decoration.borderRadius, BorderRadius.circular(10));
    expect(
      tester.widget<Icon>(find.descendant(of: find.byKey(AppStatTile.iconTileKey), matching: find.byType(Icon))).color,
      palette.navSelectedForeground,
    );
  });

  for (final width in [700.0, 1280.0]) {
    testWidgets('at $width of box the tile fills its box and its height is the content\'s',
        (tester) async {
      await _pump(tester, boxWidth: width, onTap: () {});
      final size = tester.getSize(find.byType(AppStatTile));
      expect(size.width, width);
      // 16 padding either side, the 40px icon row, then 12 and three text lines.
      expect(size.height, greaterThan(2 * Spacing.lg + 40 + Spacing.md));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the tile is as tall at 700 as at 1280: its height does not depend on its width',
      (tester) async {
    await _pump(tester, boxWidth: 1280, onTap: () {});
    final wide = tester.getSize(find.byType(AppStatTile)).height;
    await _pump(tester, boxWidth: 700, onTap: () {});
    final narrow = tester.getSize(find.byType(AppStatTile)).height;
    expect(narrow, closeTo(wide, 0.01));
  });

  testWidgets('the text starts at the tile\'s padding edge, Spacing.lg inside it', (tester) async {
    await _pump(tester, onTap: () {});
    final tile = tester.getTopLeft(find.byType(AppStatTile));
    for (final key in [AppStatTile.labelKey, AppStatTile.figureKey, AppStatTile.captionKey]) {
      expect(tester.getTopLeft(find.byKey(key)).dx, tile.dx + Spacing.lg);
    }
    expect(tester.getTopLeft(find.byKey(AppStatTile.iconTileKey)).dx, tile.dx + Spacing.lg);
  });

  testWidgets('label, figure and caption are stacked Spacing.xs apart under the icon row', (tester) async {
    await _pump(tester, onTap: () {});
    final icon = tester.getBottomRight(find.byKey(AppStatTile.iconTileKey));
    final label = find.byKey(AppStatTile.labelKey);
    final figure = find.byKey(AppStatTile.figureKey);
    final caption = find.byKey(AppStatTile.captionKey);
    expect(tester.getTopLeft(label).dy, icon.dy + Spacing.md);
    expect(tester.getTopLeft(figure).dy, tester.getBottomRight(label).dy + Spacing.xs);
    expect(tester.getTopLeft(caption).dy, tester.getBottomRight(figure).dy + Spacing.xs);
  });

  testWidgets('at 2x text the caption is still inside the tile and nothing overflows', (tester) async {
    await _pump(tester, boxWidth: 700, textScale: 2, onTap: () {});
    final tile = find.byType(AppStatTile);
    expect(
      tester.getBottomRight(find.byKey(AppStatTile.captionKey)).dy,
      lessThanOrEqualTo(tester.getBottomRight(tile).dy + 1),
    );
    expect(
      tester.getBottomRight(find.byKey(AppStatTile.captionKey)).dy + Spacing.lg,
      closeTo(tester.getBottomRight(tile).dy, 1),
      reason: 'the card grows with the text and keeps its padding beneath',
    );
    expect(tester.getSize(find.byKey(AppStatTile.iconTileKey)), const Size(40, 40));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a figure that has something to read is headlineLarge at w700', (tester) async {
    await _pump(tester, onTap: () {});
    final text = tester.widget<Text>(find.byKey(AppStatTile.figureKey));
    final theme = Theme.of(tester.element(find.byKey(AppStatTile.figureKey)));
    expect(text.style?.fontWeight, FontWeight.w700);
    expect(text.style?.fontSize, theme.textTheme.headlineLarge?.fontSize);
    expect(text.style?.fontSize, 26);
  });

  testWidgets('a quiet figure is titleMedium at w400 in the muted text colour', (tester) async {
    await _pump(tester, figure: '0', quiet: true, onTap: () {});
    final text = tester.widget<Text>(find.byKey(AppStatTile.figureKey));
    final context = tester.element(find.byKey(AppStatTile.figureKey));
    expect(text.style?.fontWeight, FontWeight.w400);
    expect(text.style?.color, AppColors.of(context).textMuted);
    expect(text.style?.fontSize, Theme.of(context).textTheme.titleMedium?.fontSize);
  });

  testWidgets('the label and the caption are dense and muted', (tester) async {
    await _pump(tester, onTap: () {});
    final context = tester.element(find.byKey(AppStatTile.labelKey));
    for (final key in [AppStatTile.labelKey, AppStatTile.captionKey]) {
      final text = tester.widget<Text>(find.byKey(key));
      expect(text.style?.color, AppColors.of(context).textMuted);
      expect(text.style?.fontSize, Theme.of(context).textTheme.bodyMedium?.fontSize);
    }
  });

  testWidgets('the figure is shown exactly as the caller formatted it', (tester) async {
    await _pump(tester, figure: '1,234', onTap: () {});
    expect(find.text('1,234'), findsOneWidget);
  });

  testWidgets('with an onTap the tile is a link: tapping it calls back and a chevron is drawn',
      (tester) async {
    var taps = 0;
    await _pump(tester, onTap: () => taps++);
    expect(find.byKey(AppStatTile.chevronKey), findsOneWidget);
    await tester.tap(find.byType(InkWell));
    expect(taps, 1);
  });

  testWidgets('with no onTap the tile is not a link: no InkWell and no chevron', (tester) async {
    await _pump(tester);
    expect(find.descendant(of: find.byType(AppStatTile), matching: find.byType(InkWell)), findsNothing);
    expect(find.byKey(AppStatTile.chevronKey), findsNothing);
    expect(find.text('Open work'), findsOneWidget);
  });

  testWidgets('with no icon the tile is text only, with the label Spacing.lg below the top',
      (tester) async {
    await _pump(tester, icon: null);
    expect(find.byKey(AppStatTile.iconTileKey), findsNothing);
    expect(
      tester.getTopLeft(find.byKey(AppStatTile.labelKey)).dy,
      tester.getTopLeft(find.byType(AppStatTile)).dy + Spacing.lg,
    );
  });

  testWidgets('with no caption the caption line and its gap are absent', (tester) async {
    await _pump(tester, caption: null, onTap: () {});
    expect(find.byKey(AppStatTile.captionKey), findsNothing);
    expect(
      tester.getBottomRight(find.byKey(AppStatTile.figureKey)).dy + Spacing.lg,
      closeTo(tester.getBottomRight(find.byType(AppStatTile)).dy, 1),
    );
  });

  testWidgets('the chevron is decorative: it sits inside an ExcludeSemantics that excludes', (tester) async {
    await _pump(tester, onTap: () {});
    final excluded = find.ancestor(of: find.byKey(AppStatTile.chevronKey), matching: find.byType(ExcludeSemantics));
    expect(excluded, findsWidgets);
    expect(tester.widget<ExcludeSemantics>(excluded.first).excluding, isTrue);
    expect(
      tester.widget<Icon>(find.byKey(AppStatTile.chevronKey)).color,
      AppColors.of(tester.element(find.byKey(AppStatTile.chevronKey))).textMuted,
    );
  });

  testWidgets('the hover fill is rowHoverFill, the fade is 200ms and there is no ripple', (tester) async {
    await _pump(tester, onTap: () {});
    final ink = tester.widget<InkWell>(find.byType(InkWell));
    expect(ink.hoverColor, AppColors.of(tester.element(find.byType(InkWell))).rowHoverFill);
    expect(ink.hoverDuration, const Duration(milliseconds: 200));
    expect(ink.splashFactory, NoSplash.splashFactory);
    expect(ink.borderRadius, BorderRadius.circular(AppRadius.card));
  });

  testWidgets('under reduced motion the hover fade is instant', (tester) async {
    await _pump(tester, onTap: () {}, disableAnimations: true);
    expect(tester.widget<InkWell>(find.byType(InkWell)).hoverDuration, Duration.zero);
  });

  testWidgets('a keyboard focus draws a 2px ring by swapping the shape and moves no pixel of layout',
      (tester) async {
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
    await _pump(tester, onTap: () {});
    final before = tester.getSize(find.byType(AppStatTile));
    expect(tester.widget<Card>(find.byType(Card)).shape, isNull, reason: 'no ring until focused');

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final shape = tester.widget<Card>(find.byType(Card)).shape! as RoundedRectangleBorder;
    final palette = AppColors.of(tester.element(find.byType(Card)));
    expect(shape.side.width, 2);
    expect(shape.side.color, palette.focusRing);
    expect(shape.borderRadius, BorderRadius.circular(AppRadius.card));
    expect(tester.getSize(find.byType(AppStatTile)), before);
    expect(tester.getTopLeft(find.byKey(AppStatTile.labelKey)).dx, Spacing.lg);
  });

  testWidgets('the tile is a Card with no margin', (tester) async {
    await _pump(tester, onTap: () {});
    expect(tester.widget<Card>(find.byType(Card)).margin, EdgeInsets.zero);
  });

  testWidgets('two tiles in one row, one quiet, match the golden', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 300);
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
                  width: 900,
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: AppStatTile(
                            label: 'Open work',
                            figure: '12',
                            caption: '3 need assigning',
                            icon: Icons.build_outlined,
                            onTap: () {},
                          ),
                        ),
                        const SizedBox(width: Spacing.md),
                        Expanded(
                          child: AppStatTile(
                            label: 'Overdue',
                            figure: '0',
                            caption: 'Nothing is late',
                            icon: Icons.schedule,
                            quiet: true,
                            onTap: () {},
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
      ),
    );
    await expectLater(find.byKey(_goldenKey), matchesGoldenFile('goldens/app_stat_tile.png'));
  });
}
