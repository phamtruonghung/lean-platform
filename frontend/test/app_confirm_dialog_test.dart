/// `AppConfirmDialog`: the destructive form of `AppDialog`.
///
/// Mounted like `app_dialog_test.dart`: a small `MaterialApp` with the app's own
/// theme, and the dialog opened through `showDialog` so that `Esc` and focus are
/// tested on a route. The colours are read back off the pumped button and compared
/// with the palette they must come from, and the contrast of that pair is measured
/// with `contrast.dart` rather than quoted.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/theme.dart';
import 'package:lean_platform/widgets/app_confirm_dialog.dart';
import 'package:lean_platform/widgets/app_dialog.dart';

import 'contrast.dart';
import 'harness.dart';

const _invokerKey = ValueKey<String>('test-invoker');
const _goldenKey = ValueKey<String>('test-confirm-golden');

class _Calls {
  int confirm = 0;
  int dismiss = 0;
}

AppConfirmDialog _dialog(_Calls calls) => AppConfirmDialog(
      title: 'Cancel this Work order?',
      description: 'It leaves the open list and cannot be reopened.',
      confirmLabel: 'Cancel this Work order',
      dismissLabel: 'Keep it open',
      onConfirm: () => calls.confirm++,
      onDismiss: () => calls.dismiss++,
    );

Future<void> _open(
  WidgetTester tester,
  _Calls calls, {
  Size window = const Size(1280, 900),
  Brightness brightness = Brightness.light,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = window;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(brightness),
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            key: _invokerKey,
            onPressed: () => showDialog<void>(context: context, builder: (_) => _dialog(calls)),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(_invokerKey));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('at 1280 of box the confirm dialog is exactly 420 wide', (tester) async {
    await _open(tester, _Calls());
    expect(tester.getSize(find.byKey(AppDialog.surfaceKey)).width, 420);
    expect(find.byKey(AppDialog.sheetKey), findsNothing);
    expect(find.text('Cancel this Work order?'), findsOneWidget);
    expect(find.byKey(AppConfirmDialog.titleKey), findsOneWidget);
    expect(find.byKey(AppConfirmDialog.descriptionKey), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('at 700 of box the confirm dialog is a sheet', (tester) async {
    await _open(tester, _Calls(), window: const Size(700, 800));
    expect(find.byKey(AppDialog.sheetKey), findsOneWidget);
    expect(tester.getSize(find.byKey(AppDialog.surfaceKey)).width, 700);
    expect(tester.takeException(), isNull);
  });

  for (final (name, brightness, palette) in [
    ('light', Brightness.light, AppPalette.light),
    ('dark', Brightness.dark, AppPalette.dark),
  ]) {
    testWidgets('in $name the confirm button is filled statusDanger with the canvas on it',
        (tester) async {
      await _open(tester, _Calls(), brightness: brightness);
      final confirm = tester.widget<FilledButton>(find.byKey(AppConfirmDialog.confirmKey));
      expect(confirm.style!.backgroundColor!.resolve(const {}), palette.statusDanger);
      expect(confirm.style!.foregroundColor!.resolve(const {}), palette.canvas);
      // The label really is drawn in that colour.
      final context = tester.element(find.descendant(
          of: find.byKey(AppConfirmDialog.confirmKey),
          matching: find.text('Cancel this Work order')));
      expect(DefaultTextStyle.of(context).style.color, palette.canvas);
    });
  }

  test('canvas on statusDanger is 6.18:1 in light and 9.41:1 in dark, both over the 4.5 floor', () {
    final light = contrastRatio(AppPalette.light.canvas, AppPalette.light.statusDanger);
    final dark = contrastRatio(AppPalette.dark.canvas, AppPalette.dark.statusDanger);
    expect(light, closeTo(6.18, 0.005));
    expect(dark, closeTo(9.41, 0.005));
    expect(light, greaterThanOrEqualTo(4.5));
    expect(dark, greaterThanOrEqualTo(4.5));
  });

  test('white on the dark statusDanger is 1.90:1, which is why the label is the canvas', () {
    expect(contrastRatio(const Color(0xFFFFFFFF), AppPalette.dark.statusDanger), closeTo(1.90, 0.005));
  });

  testWidgets('both actions are at least 44 tall', (tester) async {
    await _open(tester, _Calls());
    for (final key in [AppConfirmDialog.confirmKey, AppConfirmDialog.dismissKey]) {
      expect(tester.getSize(find.byKey(key)).height, greaterThanOrEqualTo(AppTouchTarget.min));
    }
  });

  testWidgets('the destructive action is right-most, the dismiss is left of it, and tapping each calls its own',
      (tester) async {
    final calls = _Calls();
    await _open(tester, calls);
    final confirm = find.byKey(AppConfirmDialog.confirmKey);
    final dismiss = find.byKey(AppConfirmDialog.dismissKey);
    expect(tester.getTopLeft(confirm).dx, greaterThan(tester.getBottomRight(dismiss).dx));
    expect(tester.getBottomRight(confirm).dx,
        tester.getBottomRight(find.byKey(AppDialog.surfaceKey)).dx - Spacing.lg);
    expect(find.text('Cancel this Work order'), findsOneWidget);
    expect(find.text('Keep it open'), findsOneWidget);
    await tester.tap(dismiss);
    await tester.pump();
    expect(calls.dismiss, 1);
    expect(calls.confirm, 0);
    await tester.tap(confirm);
    await tester.pump();
    expect(calls.confirm, 1);
  });

  testWidgets('Esc cancels: the dismiss callback runs and the confirm does not', (tester) async {
    final calls = _Calls();
    await _open(tester, calls);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(calls.dismiss, 1);
    expect(calls.confirm, 0);
  });

  testWidgets('Enter on opening presses the dismiss, never the destructive confirm', (tester) async {
    final calls = _Calls();
    await _open(tester, calls);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(calls.confirm, 0);
    expect(calls.dismiss, 1);
  });

  testWidgets('a null callback renders its button disabled, and the widget never pops by itself',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(
          body: AppConfirmDialog(
            title: 'Cancel this Work order?',
            confirmLabel: 'Cancel this Work order',
            dismissLabel: 'Keep it open',
          ),
        ),
      ),
    );
    expect(tester.widget<FilledButton>(find.byKey(AppConfirmDialog.confirmKey)).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(find.byKey(AppConfirmDialog.dismissKey)).onPressed, isNull);
    expect(find.byKey(AppConfirmDialog.descriptionKey), findsNothing);
  });

  group('goldens', () {
    Future<void> pour(WidgetTester tester, Brightness brightness) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 264);
      addTearDown(tester.view.reset);
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
                  // 768 of box is a dialog (701 and up), not a sheet.
                  child: SizedBox(width: 768, height: 232, child: _dialog(_Calls())),
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('the confirm dialog matches its light golden', (tester) async {
      await pour(tester, Brightness.light);
      await expectLater(
          find.byKey(_goldenKey), matchesGoldenFile('goldens/app_confirm_dialog_light.png'));
    });

    testWidgets('the confirm dialog matches its dark golden', (tester) async {
      await pour(tester, Brightness.dark);
      await expectLater(
          find.byKey(_goldenKey), matchesGoldenFile('goldens/app_confirm_dialog_dark.png'));
    });
  });
}
