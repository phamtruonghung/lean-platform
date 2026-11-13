/// Settings, and the language switch it carries (issue t_c68dfd6e).
///
/// **What these tests claim, through the same door a person uses.** The app is
/// pumped whole — the real router, the real Shell, the real Blocs, `MockClient`
/// at the HTTP boundary (`harness.dart`) — and every assertion is about what
/// renders: the Settings Screen's own title and control, the sidebar's words,
/// and the value the browser store was left with. Nothing here reads a Bloc's
/// state object or a `LocaleCubit` field directly, which is AGENTS.md §5's rule
/// for the frontend seam.
///
/// **Persistence is proved in two halves, not by pumping the app twice.** A
/// second `pumpWidget` of the same app reuses the existing `State` (see
/// `shell_wraps_screens_test.dart`'s own note), so "reload" cannot be simulated
/// that way. Instead: choosing a language is proved by reading the value back
/// out of `shared_preferences`, and a reload is proved by seeding that same
/// store before the app is pumped and asserting the stored language is what
/// renders. Together they are exactly "the choice survives a reload".
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lean_platform/platform/destinations.dart';
import 'package:lean_platform/platform/locale_cubit.dart';
import 'package:lean_platform/platform/router.dart';
import 'package:lean_platform/platform/settings_screen.dart';

import 'harness.dart';

/// An admitted administrator — the widest sidebar there is, so the tests below
/// can assert on group headings as well as a single Destination.
final Map<String, dynamic> _adminBody = {
  'status': 'active',
  'account': {
    'id': '1',
    'email': 'a@b.c',
    'displayName': 'A B',
    'role': Roles.admin,
  },
};

Future<void> _pumpSettings(WidgetTester tester) => pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: meClient(() => _adminBody),
      initialLocation: Routes.settings,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a person who never chose reads English, and finds Settings in the sidebar',
      (tester) async {
    await _pumpSettings(tester);

    expect(find.byType(SettingsScreen), findsOneWidget);
    // The Screen's own title, and its entry in the sidebar: two, and both the
    // shipped English — nothing was translated behind a reader's back.
    expect(find.text('Settings'), findsNWidgets(2));
    expect(find.text('Language'), findsOneWidget);
    expect(find.byKey(SettingsScreen.languageOptionKey('en')), findsOneWidget);
    expect(find.byKey(SettingsScreen.languageOptionKey('vi')), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('PEOPLE'), findsOneWidget);

    // Nothing was written to storage by simply looking at the Screen: only an
    // explicit choice is stored (`LocaleCubit`'s own doc comment).
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(LocaleCubit.storageKey), isNull);
  });

  testWidgets('choosing Vietnamese switches the whole Platform at once, and remembers it',
      (tester) async {
    await _pumpSettings(tester);

    await tapIn(tester, find.byKey(SettingsScreen.languageOptionKey('vi')));

    // The Screen's title and the sidebar entry for it.
    expect(find.text('Cài đặt'), findsNWidgets(2));
    // The rest of the Shell, without any navigation: a Destination, and the
    // heading group it is filed under.
    expect(find.text('Trang chủ'), findsOneWidget);
    expect(find.text('NHÂN SỰ'), findsOneWidget);
    // The English strings are gone, not merely joined by Vietnamese ones.
    expect(find.text('Settings'), findsNothing);
    expect(find.text('Home'), findsNothing);

    // Remembered on this browser, so the next load opens in Vietnamese.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(LocaleCubit.storageKey), 'vi');
  });

  testWidgets('a stored choice is the language the next load opens in', (tester) async {
    SharedPreferences.setMockInitialValues({LocaleCubit.storageKey: 'vi'});

    await _pumpSettings(tester);

    expect(find.text('Cài đặt'), findsNWidgets(2));
    expect(find.text('Trang chủ'), findsOneWidget);
    expect(find.text('Settings'), findsNothing);
  });

  testWidgets('an old or hand-edited stored value falls back to English', (tester) async {
    SharedPreferences.setMockInitialValues({LocaleCubit.storageKey: 'fr'});

    await _pumpSettings(tester);

    expect(find.text('Settings'), findsNWidgets(2));
    expect(find.text('Cài đặt'), findsNothing);
  });

  testWidgets('neither language overflows the Screen at the narrowest window', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    // 600px: the same narrow window the Shell's own goldens use, below its
    // 700px rail breakpoint — the least room the Settings Screen ever gets.
    tester.view.physicalSize = const Size(600, 800);
    addTearDown(tester.view.reset);

    for (final (code, title) in [('en', 'Settings'), ('vi', 'Cài đặt')]) {
      SharedPreferences.setMockInitialValues(
        code == 'vi' ? {LocaleCubit.storageKey: 'vi'} : <String, Object>{},
      );
      // A fresh `State`, so each pass really starts in its own language: a
      // second `pumpWidget` of the same app would reuse the first one's.
      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpSettings(tester);

      expect(tester.takeException(), isNull, reason: 'the Settings Screen overflowed in $code');
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.text(title), findsWidgets);
    }
  });
}
