/// Goldens for the Settings Screen, in both languages, at the two widths the
/// Shell has (issue t_c68dfd6e).
///
/// **Why this Screen gets goldens when the other fifteen do not.**
/// `GOLDENS.md` deliberately keeps the golden list short — a golden per Screen
/// fails on every ordinary content change — and the card that asked for the
/// language switch re-opened that question for this one Screen on purpose: its
/// whole subject is words in two languages, and "Vietnamese fits" is not
/// something `find.text` can answer. The four PNGs here are that answer, and
/// they are also the before/after pictures on the pull request.
///
/// A real font is loaded (`harness.dart`'s `loadAppFonts`): a golden painted in
/// `flutter_test`'s placeholder boxes could not show that the diacritics in
/// "Cài đặt" and "Trang chủ" are drawn by the bundled Roboto at all.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lean_platform/platform/destinations.dart';
import 'package:lean_platform/platform/locale_cubit.dart';
import 'package:lean_platform/platform/router.dart';

import 'harness.dart';

final Map<String, dynamic> _adminBody = {
  'status': 'active',
  'account': {
    'id': '1',
    'email': 'a@b.c',
    'displayName': 'A B',
    'role': Roles.admin,
  },
};

/// Pumps the whole app on `/settings` in [languageCode], at [size].
Future<void> _pump(
  WidgetTester tester, {
  required String languageCode,
  required Size size,
}) async {
  SharedPreferences.setMockInitialValues(
    languageCode == 'vi' ? {LocaleCubit.storageKey: 'vi'} : <String, Object>{},
  );
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  await pumpApp(
    tester,
    gateway: FakeAuthGateway(accessToken: 'a-token'),
    client: meClient(() => _adminBody),
    initialLocation: Routes.settings,
  );
}

void main() {
  setUpAll(loadAppFonts);

  // 600px is below the Shell's 700px rail breakpoint — the least room the
  // Screen ever gets. 1200px is a desktop window with the expanded sidebar,
  // where the Vietnamese labels sit in a 260px column and have to fit.
  const narrow = Size(600, 800);
  const wide = Size(1200, 800);

  for (final (code, suffix) in [('en', 'en'), ('vi', 'vi')]) {
    testWidgets('the Settings Screen, $code, at the narrowest window', (tester) async {
      await _pump(tester, languageCode: code, size: narrow);

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/settings_narrow_$suffix.png'),
      );
    });

    testWidgets('the Settings Screen, $code, in an expanded Shell', (tester) async {
      await _pump(tester, languageCode: code, size: wide);

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/settings_wide_$suffix.png'),
      );
    });
  }
}
