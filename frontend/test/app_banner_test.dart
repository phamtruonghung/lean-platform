/// `AppBanner`: the one inline surface for an outcome.
///
/// Mounted like `app_toolbar_test.dart`: a small `MaterialApp` with the app's own
/// theme and no `FakeWire`. The width tests wrap the banner in a `SizedBox` so that
/// the **box** is what it sees; the window is a fixed size wider than any box used,
/// and the text scale is set with a `MediaQuery` inside the app, where a real
/// reader's setting reaches the widget. Colours are read off the rendered tree and
/// compared with the palette; contrast is measured with `contrast.dart`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/status_tone.dart';
import 'package:lean_platform/theme.dart';
import 'package:lean_platform/widgets/app_banner.dart';

import 'contrast.dart';
import 'harness.dart';

const _goldenKey = ValueKey<String>('test-banner-golden');
const _longMessage =
    'The Work order could not be moved. Check your connection and try again; nothing was changed.';

Future<void> _pump(
  WidgetTester tester, {
  double boxWidth = 900,
  double textScale = 1,
  Brightness brightness = Brightness.light,
  StatusTone tone = StatusTone.danger,
  String message = 'The Work order could not be moved.',
  String? title = 'Not saved',
  Widget? action,
  VoidCallback? onDismiss,
  String? dismissTooltip,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(2300, 900);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(brightness),
      home: Scaffold(
        body: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: boxWidth,
                child: AppBanner(
                  tone: tone,
                  message: message,
                  title: title,
                  action: action,
                  onDismiss: onDismiss,
                  dismissTooltip: dismissTooltip ?? 'Dismiss',
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Widget _retry([VoidCallback? onPressed]) => OutlinedButton(
      key: const ValueKey('test-retry'),
      onPressed: onPressed ?? () {},
      child: const Text('Try again'),
    );

const _palettes = [
  (Brightness.light, AppPalette.light),
  (Brightness.dark, AppPalette.dark),
];

void main() {
  setUpAll(loadAppFonts);

  for (final (brightness, palette) in _palettes) {
    for (final tone in StatusTone.values) {
      testWidgets('${brightness.name} ${tone.name}: fill and text come from the tone',
          (tester) async {
        await _pump(tester, tone: tone, brightness: brightness);
        final decoration = tester.widget<DecoratedBox>(find.byKey(AppBanner.bannerKey)).decoration
            as BoxDecoration;
        expect(decoration.color, palette.statusFill(tone));
        expect(decoration.borderRadius, BorderRadius.circular(AppRadius.card));
        expect(tester.widget<Text>(find.byKey(AppBanner.messageKey)).style!.color,
            palette.statusForeground(tone));
        expect(tester.widget<Text>(find.byKey(AppBanner.titleKey)).style!.color,
            palette.statusForeground(tone));
        expect(tester.widget<Icon>(find.byType(Icon).first).color, palette.statusForeground(tone));
      });
    }
  }

  test('foreground on its own fill is the quoted pair for every tone, and never under 4.5', () {
    const expected = {
      StatusTone.neutral: (6.50, 6.97),
      StatusTone.info: (8.49, 8.49),
      StatusTone.success: (6.49, 6.49),
      StatusTone.warning: (6.38, 9.28),
      StatusTone.danger: (5.30, 5.28),
    };
    for (final tone in StatusTone.values) {
      final (light, dark) = expected[tone]!;
      final measuredLight = contrastRatio(
          AppPalette.light.statusForeground(tone), AppPalette.light.statusFill(tone));
      final measuredDark = contrastRatio(
          AppPalette.dark.statusForeground(tone), AppPalette.dark.statusFill(tone));
      expect(measuredLight, closeTo(light, 0.01), reason: 'light ${tone.name}');
      expect(measuredDark, closeTo(dark, 0.01), reason: 'dark ${tone.name}');
      expect(measuredLight, greaterThanOrEqualTo(4.5));
      expect(measuredDark, greaterThanOrEqualTo(4.5));
    }
  });

  testWidgets('the message is rendered with and without a title, an action and a dismiss',
      (tester) async {
    await _pump(tester, title: null);
    expect(find.text('The Work order could not be moved.'), findsOneWidget);
    expect(find.byKey(AppBanner.titleKey), findsNothing);
    expect(find.byKey(AppBanner.actionKey), findsNothing);
    expect(find.byKey(AppBanner.dismissKey), findsNothing);
    await _pump(tester, action: _retry(), onDismiss: () {});
    expect(find.text('The Work order could not be moved.'), findsOneWidget);
    expect(find.text('Not saved'), findsOneWidget);
    expect(find.byKey(AppBanner.actionKey), findsOneWidget);
    expect(find.byKey(AppBanner.dismissKey), findsOneWidget);
  });

  testWidgets('the icon is excluded from semantics, the message is in it, and the region is live',
      (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, action: _retry(), onDismiss: () {});
    expect(
      find.descendant(
        of: find.byKey(AppBanner.bannerKey),
        matching: find.ancestor(of: find.byType(Icon).first, matching: find.byType(ExcludeSemantics)),
      ),
      findsOneWidget,
      reason: 'the tone icon sits under an ExcludeSemantics',
    );
    final node = tester.getSemantics(find.byKey(AppBanner.bannerKey));
    expect(node.flagsCollection.isLiveRegion, isTrue);
    expect(node.label, contains('The Work order could not be moved.'));
    expect(node.label, contains('Not saved'));
    handle.dispose();
  });

  testWidgets('dismiss is a 44px icon control that carries its tooltip, and it fires', (tester) async {
    var dismissed = 0;
    await _pump(tester, onDismiss: () => dismissed++);
    final size = tester.getSize(find.byKey(AppBanner.dismissKey));
    expect(size.width, greaterThanOrEqualTo(AppTouchTarget.min));
    expect(size.height, greaterThanOrEqualTo(AppTouchTarget.min));
    expect(tester.widget<IconButton>(find.byKey(AppBanner.dismissKey)).tooltip, 'Dismiss');
    expect(find.byTooltip('Dismiss'), findsOneWidget);
    await tester.tap(find.byKey(AppBanner.dismissKey));
    expect(dismissed, 1);
  });

  testWidgets('a custom dismiss tooltip is the control\'s tooltip', (tester) async {
    await _pump(tester, onDismiss: () {}, dismissTooltip: 'Close this message');
    expect(find.byTooltip('Close this message'), findsOneWidget);
  });

  testWidgets('an action is at least 44 tall and fires when tapped', (tester) async {
    var pressed = 0;
    await _pump(tester, action: _retry(() => pressed++));
    expect(tester.getSize(find.byKey(AppBanner.actionKey)).height,
        greaterThanOrEqualTo(AppTouchTarget.min));
    await tester.tap(find.byKey(const ValueKey('test-retry')));
    expect(pressed, 1);
  });

  testWidgets('at 900 of box the action sits beside the message, at the inline end', (tester) async {
    await _pump(tester, boxWidth: 900, action: _retry(), onDismiss: () {});
    final action = find.byKey(AppBanner.actionKey);
    final message = find.byKey(AppBanner.messageKey);
    expect(tester.getTopLeft(action).dx, greaterThan(tester.getBottomRight(message).dx - 1));
    expect(tester.getTopLeft(action).dy, lessThan(tester.getBottomRight(message).dy));
    expect(tester.getTopLeft(find.byKey(AppBanner.dismissKey)).dx,
        greaterThan(tester.getBottomRight(action).dx));
    expect(tester.takeException(), isNull);
  });

  testWidgets('at 440 of box the action drops under the message', (tester) async {
    await _pump(tester, boxWidth: 440, action: _retry(), onDismiss: () {});
    final action = find.byKey(AppBanner.actionKey);
    final message = find.byKey(AppBanner.messageKey);
    expect(tester.getTopLeft(action).dy, greaterThanOrEqualTo(tester.getBottomRight(message).dy));
    expect(tester.getBottomRight(action).dx,
        tester.getBottomRight(find.byKey(AppBanner.bannerKey)).dx - Spacing.md,
        reason: 'it sits at the inline end, under the message');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the action drops below AppBreakpoints.headerActionsWrap: 559 drops, 560 does not',
      (tester) async {
    bool dropped() =>
        tester.getTopLeft(find.byKey(AppBanner.actionKey)).dy >=
        tester.getBottomRight(find.byKey(AppBanner.messageKey)).dy;
    await _pump(tester, boxWidth: 559, action: _retry(), message: 'Not saved.', title: null);
    expect(dropped(), isTrue);
    await _pump(tester, boxWidth: 560, action: _retry(), message: 'Not saved.', title: null);
    expect(dropped(), isFalse);
  });

  testWidgets('the wrap breakpoint is scaled by the text: at 2x, 900 of box drops the action',
      (tester) async {
    await _pump(tester, boxWidth: 900, textScale: 2, action: _retry());
    expect(
      tester.getTopLeft(find.byKey(AppBanner.actionKey)).dy,
      greaterThanOrEqualTo(tester.getBottomRight(find.byKey(AppBanner.messageKey)).dy),
    );
    expect(tester.takeException(), isNull);
  });

  for (final box in [700.0, 900.0, 1280.0]) {
    testWidgets('at textScaler 2.0 and ${box.toInt()} of box nothing overflows', (tester) async {
      await _pump(
        tester,
        boxWidth: box,
        textScale: 2,
        message: _longMessage,
        action: _retry(),
        onDismiss: () {},
      );
      expect(tester.takeException(), isNull);
      expect(find.text(_longMessage), findsOneWidget);
      expect(tester.getBottomRight(find.byKey(AppBanner.bannerKey)).dx, lessThanOrEqualTo(box));
    });
  }

  testWidgets('at 320 of box and textScaler 2.0 with every part present nothing overflows',
      (tester) async {
    await _pump(
      tester,
      boxWidth: 320,
      textScale: 2,
      message: _longMessage,
      action: _retry(),
      onDismiss: () {},
    );
    expect(tester.takeException(), isNull);
  });

  group('goldens', () {
    Future<void> pour(WidgetTester tester, Brightness brightness) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(700, 520);
      addTearDown(tester.view.reset);
      const messages = {
        StatusTone.neutral: 'Work order WO-1042 was cancelled.',
        StatusTone.info: 'Three Work orders are waiting for an Assignee.',
        StatusTone.success: 'Work order WO-1042 was moved to Line 2.',
        StatusTone.warning: 'This Asset is down; the Work order may be late.',
        StatusTone.danger: 'The Work order could not be moved.',
      };
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(brightness),
          debugShowCheckedModeBanner: false,
          home: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: _goldenKey,
              child: Material(
                child: Padding(
                  padding: const EdgeInsets.all(Spacing.lg),
                  child: SizedBox(
                    width: 668,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final tone in StatusTone.values) ...[
                          AppBanner(
                            tone: tone,
                            message: messages[tone]!,
                            title: tone == StatusTone.danger ? 'Not saved' : null,
                            action: tone == StatusTone.danger ? _retry() : null,
                            onDismiss: tone == StatusTone.neutral ||
                                    tone == StatusTone.success ||
                                    tone == StatusTone.danger
                                ? () {}
                                : null,
                          ),
                          if (tone != StatusTone.danger) const SizedBox(height: Spacing.md),
                        ],
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

    testWidgets('the five banners match their light golden', (tester) async {
      await pour(tester, Brightness.light);
      await expectLater(find.byKey(_goldenKey), matchesGoldenFile('goldens/app_banner_light.png'));
    });

    testWidgets('the five banners match their dark golden', (tester) async {
      await pour(tester, Brightness.dark);
      await expectLater(find.byKey(_goldenKey), matchesGoldenFile('goldens/app_banner_dark.png'));
    });
  });
}
