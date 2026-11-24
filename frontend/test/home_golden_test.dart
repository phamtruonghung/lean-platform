/// Goldens for Home, in both languages, at the two widths the Shell has.
///
/// **Why Home gets goldens.** Home's only picture until now is the 2x-text
/// sweep (`sweep_home_*` in `palette_text_scale_sweep_test.dart`), which is
/// English and answers a different question. Vietnamese labels are wider than
/// the English ones the cards were laid out around, and a clip or an ellipsis
/// raises no exception — `find.text` still finds the string — so only pixels can
/// say that "Lệnh công việc đang mở" and its caption still fit their card.
/// t_0ac0eb9e batch 1 translated Home and the Work orders register without a
/// Vietnamese golden; `settings_golden_test.dart` set the pattern for adding
/// them, and `work_orders_golden_test.dart` carries the register's.
///
/// The app is pumped whole (`pumpApp`, the real router and Shell, the wire
/// faked), with an admin, one Site and one open Work order so the cards have
/// content to lay out rather than an empty state. A real font is loaded
/// (`harness.dart`'s `loadAppFonts`): placeholder boxes cannot show that the
/// diacritics are drawn at all.
///
/// The four PNGs are `home_narrow_{en,vi}.png` (600px, below the Shell's rail
/// breakpoint — the least room Home gets) and `home_wide_{en,vi}.png` (1200px,
/// the expanded Shell).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lean_platform/platform/destinations.dart';
import 'package:lean_platform/platform/locale_cubit.dart';
import 'package:lean_platform/platform/router.dart';

import 'harness.dart';

/// One open Work order, one Site, nothing queued — the same shape
/// `locale_screens_test.dart`'s `_wire` gives Home's Maintenance group.
FakeWire _wire() => FakeWire(
      role: Roles.admin,
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      workOrders: {
        '1': [workOrderJson('101', 'WO-101', 'Belt is slipping')],
      },
      queue: const <Map<String, dynamic>>[],
      actions: {'1': <Map<String, dynamic>>[]},
      employeeDetails: const <String, Map<String, dynamic>>{},
    );

/// Pumps the whole app on Home in [languageCode], at [size].
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
    client: _wire().client,
    initialLocation: Routes.home,
  );
}

/// A Vietnamese golden that silently rendered English would be a second English
/// golden: prove the words before the pixels.
void _expectLanguage(String languageCode) {
  if (languageCode == 'vi') {
    expect(find.text('Chào A B'), findsOneWidget);
    expect(find.text('Welcome, A B'), findsNothing);
    expect(find.text('Bảo trì'), findsOneWidget);
    expect(find.text('Maintenance'), findsNothing);
    expect(find.text('Lệnh công việc đang mở'), findsOneWidget);
    expect(find.text('Đã tạo và chưa hoàn thành'), findsOneWidget);
    expect(find.text('Open work orders'), findsNothing);
  } else {
    expect(find.text('Welcome, A B'), findsOneWidget);
    expect(find.text('Open work orders'), findsOneWidget);
    expect(find.text('Chào A B'), findsNothing);
  }
}

void main() {
  setUpAll(loadAppFonts);

  const narrow = Size(600, 800);
  const wide = Size(1200, 800);

  for (final code in ['en', 'vi']) {
    testWidgets('Home, $code, at the narrowest window', (tester) async {
      await _pump(tester, languageCode: code, size: narrow);
      _expectLanguage(code);

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/home_narrow_$code.png'),
      );
    });

    testWidgets('Home, $code, in an expanded Shell', (tester) async {
      await _pump(tester, languageCode: code, size: wide);
      _expectLanguage(code);

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/home_wide_$code.png'),
      );
    });
  }
}
