/// Which palette the Platform wears, and that the choice is kept (issue #366,
/// ADR-0056). Driven through `PlatformApp` where that is natural: the account
/// menu's `Dark palette` item, the palette the Shell then renders, and the
/// choice surviving a reload. `ThemeModeCubit` is read directly only where it
/// is itself the contract: how it reads storage on construction, and `toggle`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lean_platform/auth/sign_in_screen.dart';
import 'package:lean_platform/people/accounts_screen.dart';
import 'package:lean_platform/platform/router.dart';
import 'package:lean_platform/platform/shell.dart';
import 'package:lean_platform/platform/theme_mode_cubit.dart';
import 'package:lean_platform/theme.dart';
import 'package:lean_platform/widgets/palette_toggle.dart';

import 'harness.dart' show FakeAuthGateway, FakeWire, accountJson, locationOf, pumpApp, tapIn;

const _key = 'platform.theme_mode';

Future<void> _open(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1200, 900);
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  final wire = FakeWire(accounts: [accountJson('1', 'me@b.c', role: 'admin')]);
  await pumpApp(
    tester,
    gateway: FakeAuthGateway(accessToken: 'a-token'),
    client: wire.client,
    initialLocation: Routes.accounts,
  );
}

/// The palette the Shell actually rendered with.
AppPalette _shellPalette(WidgetTester tester) =>
    AppColors.of(tester.element(find.byKey(PlatformShell.sidebarKey)));

Color? _sidebarFill(WidgetTester tester) {
  final box = tester.widget<Container>(find.byKey(PlatformShell.sidebarKey));
  return (box.decoration as BoxDecoration).color;
}

Future<void> _openMenu(WidgetTester tester) =>
    tapIn(tester, find.byKey(PlatformShell.accountMenuKey));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the Platform follows the system until a person chooses', () {
    testWidgets('nothing stored: light on a light system, dark on a dark one', (tester) async {
      await _open(tester);
      expect(_shellPalette(tester), AppPalette.light);

      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      expect(_shellPalette(tester), AppPalette.dark);
      expect(_sidebarFill(tester), AppPalette.dark.card);
    });

    testWidgets('a stored "dark" wins over a light system, on the first frames', (tester) async {
      SharedPreferences.setMockInitialValues({_key: 'dark'});
      await _open(tester);
      expect(_shellPalette(tester), AppPalette.dark);
    });

    testWidgets('a stored "light" wins over a dark system', (tester) async {
      SharedPreferences.setMockInitialValues({_key: 'light'});
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await _open(tester);
      expect(_shellPalette(tester), AppPalette.light);
    });

    testWidgets('an unrecognised stored value is the system\'s own, and never an error',
        (tester) async {
      SharedPreferences.setMockInitialValues({_key: 'sepia'});
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await _open(tester);
      expect(_shellPalette(tester), AppPalette.dark);
      expect(tester.takeException(), isNull);
    });
  });

  group('choosing Dark palette in the account menu', () {
    testWidgets('turns the Shell dark, shows the check mark, and keeps the address',
        (tester) async {
      await _open(tester);
      expect(_shellPalette(tester), AppPalette.light);
      expect(locationOf(tester, find.byType(AccountsScreen)), Routes.accounts);

      await _openMenu(tester);
      expect(
        find.descendant(
            of: find.byKey(PlatformShell.themeToggleKey), matching: find.byIcon(Icons.check)),
        findsNothing,
      );
      await tapIn(tester, find.byKey(PlatformShell.themeToggleKey));

      expect(_shellPalette(tester), AppPalette.dark);
      expect(_sidebarFill(tester), AppPalette.dark.card);
      expect(locationOf(tester, find.byType(AccountsScreen)), Routes.accounts);
      expect(find.byType(AccountsScreen), findsOneWidget);

      await _openMenu(tester);
      expect(
        find.descendant(
            of: find.byKey(PlatformShell.themeToggleKey), matching: find.byIcon(Icons.check)),
        findsOneWidget,
      );
    });

    testWidgets('choosing it again goes back to light', (tester) async {
      await _open(tester);
      await _openMenu(tester);
      await tapIn(tester, find.byKey(PlatformShell.themeToggleKey));
      await _openMenu(tester);
      await tapIn(tester, find.byKey(PlatformShell.themeToggleKey));

      expect(_shellPalette(tester), AppPalette.light);
    });

    testWidgets('on a dark system the item is already checked, and switches to light',
        (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await _open(tester);
      expect(_shellPalette(tester), AppPalette.dark);

      await _openMenu(tester);
      expect(
        find.descendant(
            of: find.byKey(PlatformShell.themeToggleKey), matching: find.byIcon(Icons.check)),
        findsOneWidget,
      );
      await tapIn(tester, find.byKey(PlatformShell.themeToggleKey));
      expect(_shellPalette(tester), AppPalette.light);
    });

    testWidgets('the choice survives a reload', (tester) async {
      await _open(tester);
      await _openMenu(tester);
      await tapIn(tester, find.byKey(PlatformShell.themeToggleKey));
      expect(_shellPalette(tester), AppPalette.dark);

      // A reload: the whole app is torn down and built again over the same store.
      await tester.pumpWidget(const SizedBox());
      await _open(tester);
      expect(_shellPalette(tester), AppPalette.dark);
    });
  });

  group('ThemeModeCubit', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    Future<void> settle() => Future<void>.delayed(Duration.zero);

    test('starts at system and stays there when nothing is stored', () async {
      final cubit = ThemeModeCubit();
      addTearDown(cubit.close);
      expect(cubit.state, ThemeMode.system);
      await settle();
      expect(cubit.state, ThemeMode.system);
    });

    test('reads a stored value on construction, without blocking the first state', () async {
      SharedPreferences.setMockInitialValues({_key: 'dark'});
      final cubit = ThemeModeCubit();
      addTearDown(cubit.close);
      expect(cubit.state, ThemeMode.system);
      await settle();
      expect(cubit.state, ThemeMode.dark);
    });

    test('light and dark round-trip through a re-constructed cubit', () async {
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        final first = ThemeModeCubit();
        await first.setMode(mode);
        expect(first.state, mode);
        await first.close();

        final second = ThemeModeCubit();
        addTearDown(second.close);
        await settle();
        expect(second.state, mode);
      }
    });

    test('an unrecognised stored value is system', () async {
      SharedPreferences.setMockInitialValues({_key: 'sepia'});
      final cubit = ThemeModeCubit();
      addTearDown(cubit.close);
      await settle();
      expect(cubit.state, ThemeMode.system);
    });

    test('a late read does not overwrite a choice already made', () async {
      SharedPreferences.setMockInitialValues({_key: 'dark'});
      final cubit = ThemeModeCubit();
      addTearDown(cubit.close);
      await cubit.setMode(ThemeMode.light);
      await settle();
      expect(cubit.state, ThemeMode.light);
    });

    test('a read that lands after close emits nothing and throws nothing', () async {
      SharedPreferences.setMockInitialValues({_key: 'dark'});
      final cubit = ThemeModeCubit();
      await cubit.close();
      await settle();
      expect(cubit.isClosed, isTrue);
    });

    test('toggle from a dark effective brightness goes to light, otherwise to dark', () async {
      final cubit = ThemeModeCubit();
      addTearDown(cubit.close);

      // system follows the platform's brightness
      await cubit.toggle(Brightness.dark);
      expect(cubit.state, ThemeMode.light);
      await cubit.setMode(ThemeMode.system);
      await cubit.toggle(Brightness.light);
      expect(cubit.state, ThemeMode.dark);

      // an explicit mode ignores the platform's
      await cubit.toggle(Brightness.light);
      expect(cubit.state, ThemeMode.light);
      await cubit.toggle(Brightness.dark);
      expect(cubit.state, ThemeMode.dark);
    });
  });

  group('ThemeMode.isDarkPalette', () {
    test('an explicit mode ignores the platform, system follows it', () {
      expect(ThemeMode.dark.isDarkPalette(Brightness.light), isTrue);
      expect(ThemeMode.light.isDarkPalette(Brightness.dark), isFalse);
      expect(ThemeMode.system.isDarkPalette(Brightness.dark), isTrue);
      expect(ThemeMode.system.isDarkPalette(Brightness.light), isFalse);
    });
  });

  // The switch on the front door (issue #415). Before this, the only control
  // was the account menu inside the Shell, which the sign-in Screen is not
  // inside — so the page the site opens on could not be changed at all.
  group('the front door carries the switch (issue #415)', () {
    Future<void> openFrontDoor(WidgetTester tester, {Size size = const Size(1200, 900)}) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await pumpApp(
        tester,
        gateway: FakeAuthGateway(),
        client: FakeWire().client,
        initialLocation: Routes.signIn,
      );
      expect(find.byType(SignInScreen), findsOneWidget);
    }

    AppPalette frontDoorPalette(WidgetTester tester) =>
        AppColors.of(tester.element(find.byKey(SignInScreen.formCardKey)));

    testWidgets('a signed-out caller can switch the palette, and it is remembered',
        (tester) async {
      await openFrontDoor(tester);
      expect(frontDoorPalette(tester), AppPalette.light);
      expect(find.byKey(PaletteToggle.buttonKey), findsOneWidget);

      await tapIn(tester, find.byKey(PaletteToggle.buttonKey));

      expect(frontDoorPalette(tester), AppPalette.dark);
      expect(find.byType(SignInScreen), findsOneWidget,
          reason: 'switching the palette is not navigating');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_key), 'dark');

      // ... and it survives a reload, from the same store, signed out.
      await tester.pumpWidget(const SizedBox());
      await openFrontDoor(tester);
      expect(frontDoorPalette(tester), AppPalette.dark);
    });

    testWidgets('a second tap goes back to light, and stores that', (tester) async {
      await openFrontDoor(tester, size: const Size(375, 812));
      await tapIn(tester, find.byKey(PaletteToggle.buttonKey));
      expect(frontDoorPalette(tester), AppPalette.dark);

      await tapIn(tester, find.byKey(PaletteToggle.buttonKey));
      expect(frontDoorPalette(tester), AppPalette.light);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_key), 'light');
    });

    testWidgets('on a dark system the switch offers light, and delivers it', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await openFrontDoor(tester);
      expect(frontDoorPalette(tester), AppPalette.dark);
      expect(find.byTooltip(PaletteToggle.toLightTooltip), findsOneWidget);

      await tapIn(tester, find.byKey(PaletteToggle.buttonKey));
      expect(frontDoorPalette(tester), AppPalette.light);
    });
  });

  // The same switch beside sign-out (issue #415): a person inside the app no
  // longer has to know that the palette lives under their own name.
  group("the Shell's footer carries the switch (issue #415)", () {
    testWidgets('beside sign-out, on the same row, and it switches without the menu',
        (tester) async {
      await _open(tester);
      expect(_shellPalette(tester), AppPalette.light);

      final toggle = find.byKey(PaletteToggle.buttonKey);
      expect(toggle, findsOneWidget);
      final box = tester.getRect(toggle);
      final signOut = tester.getRect(find.byIcon(Icons.logout));
      expect((box.center.dy - signOut.center.dy).abs(), lessThanOrEqualTo(1),
          reason: 'the switch sits in the footer row, beside sign-out');
      expect(box.right, lessThanOrEqualTo(signOut.left),
          reason: 'and immediately before it, at the inline end');
      expect(box.height, greaterThanOrEqualTo(44));
      expect(box.width, greaterThanOrEqualTo(44));

      // No account menu was opened: the popup's own item is not on screen.
      expect(find.byKey(PlatformShell.themeToggleKey), findsNothing);
      await tapIn(tester, toggle);

      expect(_shellPalette(tester), AppPalette.dark);
      expect(_sidebarFill(tester), AppPalette.dark.card);
      expect(find.byType(AccountsScreen), findsOneWidget);
    });

    testWidgets('it is on the 64px rail too, and still fills 44px', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(640, 900);
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final wire = FakeWire(accounts: [accountJson('1', 'me@b.c', role: 'admin')]);
      await pumpApp(
        tester,
        gateway: FakeAuthGateway(accessToken: 'a-token'),
        client: wire.client,
        initialLocation: Routes.accounts,
      );

      final toggle = find.byKey(PaletteToggle.buttonKey);
      expect(toggle, findsOneWidget);
      final box = tester.getRect(toggle);
      expect(box.height, greaterThanOrEqualTo(44));
      expect(box.width, greaterThanOrEqualTo(44));
      expect(box.right, lessThanOrEqualTo(PlatformShell.collapsedWidth));

      await tapIn(tester, toggle);
      expect(_sidebarFill(tester), AppPalette.dark.card);
    });
  });
}
