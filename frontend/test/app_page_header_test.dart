/// `AppPageHeader`: the title / description / actions / hairline / filters block
/// every register Screen shares.
///
/// Like `app_filter_field_test.dart`, this mounts the widget in a small
/// `MaterialApp` with the app's own theme: it makes no request of its own, so
/// `harness.dart`'s `FakeWire` has nothing to answer. What the Screens do with
/// it is held by their own tests and by `page_alignment_test.dart`.
///
/// The width tests wrap the header in a `SizedBox` narrower than the window, to
/// prove the actions wrap by the box the header is given and not by
/// `MediaQuery`: the window stays 1000px wide throughout.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/theme.dart';
import 'package:lean_platform/widgets/app_page_header.dart';

const _actionKey = ValueKey<String>('test-action');
const _belowKey = ValueKey<String>('test-below');

Future<void> _pump(
  WidgetTester tester, {
  double boxWidth = 900,
  double windowWidth = 1000,
  String title = 'Things',
  String? description = 'What this page is for.',
  bool actions = true,
  bool below = true,
  double textScale = 1,
  List<Widget>? actionWidgets,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(windowWidth, 800);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        // The text scale sits inside the MaterialApp, where a real reader's
        // setting reaches the header; the box width is still the SizedBox's.
        body: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: boxWidth,
                child: AppPageHeader(
                  title: title,
                  description: description,
                  actions: actionWidgets ??
                      (actions
                          ? [FilledButton(key: _actionKey, onPressed: () {}, child: const Text('Add a thing'))]
                          : const []),
                  below: below ? const Text('Filters', key: _belowKey) : null,
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
  testWidgets('the title is a header to a screen reader, at headlineSmall w700', (tester) async {
    await _pump(tester);
    final handle = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.byKey(AppPageHeader.titleKey)),
      matchesSemantics(label: 'Things', isHeader: true),
    );
    handle.dispose();
    final text = tester.widget<Text>(find.byKey(AppPageHeader.titleKey));
    final theme = buildAppTheme();
    expect(text.style?.fontWeight, FontWeight.w700);
    expect(text.style?.fontSize, theme.textTheme.headlineSmall?.fontSize);
  });

  testWidgets('the description is bodyMedium in the muted text colour', (tester) async {
    await _pump(tester);
    final text = tester.widget<Text>(find.byKey(AppPageHeader.descriptionKey));
    final context = tester.element(find.byKey(AppPageHeader.descriptionKey));
    expect(text.style?.color, AppColors.of(context).textMuted);
    expect(text.style?.fontSize, Theme.of(context).textTheme.bodyMedium?.fontSize);
  });

  testWidgets('a header with no description draws none', (tester) async {
    await _pump(tester, description: null);
    expect(find.byKey(AppPageHeader.descriptionKey), findsNothing);
    expect(find.byKey(AppPageHeader.titleKey), findsOneWidget);
  });

  testWidgets('a long description is bounded to 640px however wide the box', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1600, 800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 1500,
              child: AppPageHeader(title: 'Things', description: 'word ' * 200),
            ),
          ),
        ),
      ),
    );
    final size = tester.getSize(find.byKey(AppPageHeader.descriptionKey));
    expect(size.width, lessThanOrEqualTo(AppPageHeader.descriptionMeasure));
    expect(size.width, greaterThan(500));
  });

  testWidgets('wide: the actions sit at the far end of the title row', (tester) async {
    await _pump(tester, boxWidth: 900);
    final title = tester.getRect(find.byKey(AppPageHeader.titleKey));
    final action = tester.getRect(find.byKey(_actionKey));
    expect(action.right, 900, reason: 'at the far end of the box');
    expect(action.left, greaterThan(title.right));
    expect(action.center.dy, lessThan(tester.getRect(find.byKey(AppPageHeader.ruleKey)).top));
    // Same row: the action's vertical span overlaps the title's.
    expect(action.top, lessThan(title.bottom));
  });

  testWidgets('narrow: the actions wrap under the title, by the box and not the window',
      (tester) async {
    // The window is 1000px wide; only the box is narrow.
    await _pump(tester, boxWidth: 400);
    final title = tester.getRect(find.byKey(AppPageHeader.titleKey));
    final action = tester.getRect(find.byKey(_actionKey));
    expect(action.top, greaterThanOrEqualTo(title.bottom));
    expect(action.left, title.left, reason: 'wrapped actions start at the title edge');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the same header in a wide box in the same window does not wrap', (tester) async {
    await _pump(tester, boxWidth: AppPageHeader.wrapBreakpoint);
    final title = tester.getRect(find.byKey(AppPageHeader.titleKey));
    final action = tester.getRect(find.byKey(_actionKey));
    expect(action.top, lessThan(title.bottom));
  });

  testWidgets('below 1x text the breakpoint is not lowered: the actions stay on the title row at it',
      (tester) async {
    // An Android "small font" (0.85) must not see headers wrap earlier than
    // they did before the breakpoint scaled: the multiplier is clamped at 1
    // from below.
    await _pump(tester, boxWidth: AppPageHeader.wrapBreakpoint, textScale: 0.8);
    final title = tester.getRect(find.byKey(AppPageHeader.titleKey));
    final action = tester.getRect(find.byKey(_actionKey));
    expect(action.top, lessThan(title.bottom));
    expect(action.left, greaterThan(title.right));
  });

  testWidgets('below 1x text the actions still wrap one pixel under the breakpoint', (tester) async {
    // Without the clamp the breakpoint at 0.8 would be 448 and this box would
    // not wrap; the clamp holds it at the unscaled breakpoint.
    await _pump(tester, boxWidth: AppPageHeader.wrapBreakpoint - 1, textScale: 0.8);
    final title = tester.getRect(find.byKey(AppPageHeader.titleKey));
    final action = tester.getRect(find.byKey(_actionKey));
    expect(action.top, greaterThanOrEqualTo(title.bottom));
    expect(action.left, title.left, reason: 'wrapped actions start at the title edge');
    expect(tester.takeException(), isNull);
  });

  testWidgets('at 2x text the actions wrap one pixel under the doubled breakpoint', (tester) async {
    // The breakpoint doubles with the reader's text size, so a box one pixel
    // under it still wraps. The window is wider than the box: Align passes
    // loose constraints, and a box wider than the window would be clamped.
    await _pump(
      tester,
      boxWidth: AppPageHeader.wrapBreakpoint * 2 - 1,
      windowWidth: 1200,
      textScale: 2,
    );
    final title = tester.getRect(find.byKey(AppPageHeader.titleKey));
    final action = tester.getRect(find.byKey(_actionKey));
    expect(action.top, greaterThanOrEqualTo(title.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('at 2x text the actions return to the title row at the doubled breakpoint',
      (tester) async {
    // The upper edge: a constant multiplier for every scale above 1 would
    // keep wrapping here. The window is wider than the box so the box is
    // really this wide.
    await _pump(
      tester,
      boxWidth: AppPageHeader.wrapBreakpoint * 2,
      windowWidth: 1200,
      textScale: 2,
    );
    final title = tester.getRect(find.byKey(AppPageHeader.titleKey));
    final action = tester.getRect(find.byKey(_actionKey));
    expect(action.top, lessThan(title.bottom));
    expect(action.right, 1120, reason: 'at the far end of the box');
  });

  testWidgets('at 2x text the Directory title keeps one line: the actions wrap, not squeeze it',
      (tester) async {
    // The breakpoint scales with the reader's text size (WCAG 1.4.4): the
    // actions row grows with the scale and the box does not.
    await _pump(
      tester,
      boxWidth: AppPageHeader.wrapBreakpoint,
      title: 'Directory',
      description: null,
      below: false,
      textScale: 2,
      actionWidgets: [
        FilledButton.icon(
          key: _actionKey,
          onPressed: () {},
          icon: const Icon(Icons.person_add_alt_1_outlined),
          label: const Text('Add Employee'),
        ),
        OutlinedButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.badge_outlined),
          label: const Text('My record'),
        ),
      ],
    );
    final paragraph = tester.renderObject<RenderParagraph>(find.byKey(AppPageHeader.titleKey));
    // One box per line: a title squeezed to a sliver breaks across many.
    final lines = paragraph
        .getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: 'Directory'.length))
        .map((box) => box.top.round())
        .toSet();
    expect(lines, hasLength(1));
    expect(tester.takeException(), isNull);
    expect(
      tester.getRect(find.byKey(_actionKey)).top,
      greaterThanOrEqualTo(tester.getRect(find.byKey(AppPageHeader.titleKey)).bottom),
      reason: 'the actions wrap under the title',
    );
  });

  testWidgets('a hairline in the card border colour sits under the whole block', (tester) async {
    await _pump(tester);
    final divider = tester.widget<Divider>(find.byKey(AppPageHeader.ruleKey));
    final context = tester.element(find.byKey(AppPageHeader.ruleKey));
    expect(divider.thickness, 1);
    expect(divider.height, 1);
    expect(divider.color, AppColors.of(context).cardBorder);
    final rule = tester.getRect(find.byKey(AppPageHeader.ruleKey));
    expect(rule.top, greaterThanOrEqualTo(tester.getRect(find.byKey(AppPageHeader.descriptionKey)).bottom));
    expect(rule.top, greaterThanOrEqualTo(tester.getRect(find.byKey(_actionKey)).bottom));
    expect(rule.left, tester.getRect(find.byKey(AppPageHeader.titleKey)).left);
  });

  testWidgets('below sits under the hairline, spaced from it', (tester) async {
    await _pump(tester);
    final rule = tester.getRect(find.byKey(AppPageHeader.ruleKey));
    final below = tester.getRect(find.byKey(_belowKey));
    expect(find.byKey(AppPageHeader.belowKey), findsOneWidget);
    expect(below.top, rule.bottom + Spacing.md);
  });

  testWidgets('no below draws no gap beneath the hairline', (tester) async {
    await _pump(tester, below: false);
    expect(find.byKey(AppPageHeader.belowKey), findsNothing);
    final rule = tester.getRect(find.byKey(AppPageHeader.ruleKey));
    expect(tester.getSize(find.byType(AppPageHeader)).height, rule.bottom);
  });

  testWidgets('it adds no outer padding: the title starts at the box edge', (tester) async {
    await _pump(tester);
    expect(tester.getRect(find.byKey(AppPageHeader.titleKey)).left, 0);
    expect(tester.getRect(find.byKey(AppPageHeader.titleKey)).top, 0);
  });
}
