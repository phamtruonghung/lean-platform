/// Goldens for Home, in both languages, at the two widths the Shell has
/// (issue t_e5226530).
///
/// **Why this Screen gets goldens.** `GOLDENS.md` keeps the golden list short,
/// and Home had none. It gets four now because Vietnamese labels are wider: the
/// stat tiles put a label, a count and a caption in a column sized for English,
/// and "Lệnh công việc đang mở" and "Tài khoản chờ phê duyệt" are longer than
/// "Open work orders" and "Accounts awaiting Approval". Whether they still fit
/// is a question of pixels, not of `find.text`; the four PNGs hold the measured
/// layout in place so a regression shows on the design gate.
///
/// The Account is the administrator of `home_test.dart`'s own "an administrator
/// sees both the Work order cards and the Approvals card" test: one Work order
/// and one pending approval, so every group (Actions, Maintenance, People) is
/// drawn with real counts.
///
/// **Determinism.** The pending approval's date is the fixed
/// `DateTime(2026, 1, 5, 9)`, never `DateTime.now()`. Home reads only the
/// *count* of the approval queue (`HomeBloc` counts the rows; no row, date or
/// relative time is rendered on this Screen), so the date cannot reach a pixel,
/// but pinning it means the PNG could never depend on the clock even if Home
/// began to draw it. No clock injection is needed and `lib/` is untouched.
///
/// A real font is loaded (`harness.dart`'s `loadAppFonts`), as in every other
/// golden here: a golden painted in `flutter_test`'s placeholder boxes could
/// not show that the Vietnamese diacritics are drawn by the bundled Roboto.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lean_platform/platform/locale_cubit.dart';

import 'harness.dart';

/// Mirrors `home_test.dart`'s own `wireWith` (not imported — no test file here
/// imports another test file for its helpers other than `harness.dart` itself,
/// so this stays a local duplicate).
FakeWire wireWith({
  String role = Roles.admin,
  Map<String, dynamic>? orgUnitScope,
  List<Map<String, dynamic>>? sites,
  Map<String, List<Map<String, dynamic>>>? workOrders,
  int workOrdersStatus = 200,
  List<Map<String, dynamic>>? queue,
  int queueStatus = 200,
  Map<String, List<Map<String, dynamic>>>? actions,
  Map<String, Map<String, dynamic>>? employeeDetails,
  int employeeDetailStatus = 200,
  String employeeDetailMessage = 'This Account has no linked Employee record',
}) =>
    FakeWire(
      role: role,
      orgUnitScope: orgUnitScope,
      sites: sites ?? [siteJson('1', 'HCM', 'Ho Chi Minh')],
      workOrders: workOrders ?? {'1': []},
      workOrdersStatus: workOrdersStatus,
      queue: queue ?? [],
      queueStatus: queueStatus,
      actions: actions ?? {'1': []},
      employeeDetails: employeeDetails ?? const {},
      employeeDetailStatus: employeeDetailStatus,
      employeeDetailMessage: employeeDetailMessage,
    );

/// Pumps the whole app on Home in [languageCode], at [size].
Future<void> _pump(
  WidgetTester tester, {
  required String languageCode,
  required Size size,
}) async {
  // The mock is static: every test seeds it, English ones with the empty map,
  // so a Vietnamese seed cannot leak into the next test.
  SharedPreferences.setMockInitialValues(
    languageCode == 'vi' ? {LocaleCubit.storageKey: 'vi'} : <String, Object>{},
  );
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  final wire = wireWith(
    workOrders: {
      '1': [workOrderJson('101', 'WO-101', 'Belt is slipping')],
    },
    queue: [pendingJson('7', 'new@b.c', DateTime(2026, 1, 5, 9))],
  );
  await pumpApp(tester, gateway: FakeAuthGateway(accessToken: 'a-token'), client: wire.client);
}

void main() {
  setUpAll(loadAppFonts);

  // 600px is below the Shell's 700px rail breakpoint — the least room Home
  // ever gets. 1200px is a desktop window with the expanded 260px sidebar.
  const narrow = Size(600, 800);
  const wide = Size(1200, 800);

  for (final (code, suffix) in [('en', 'en'), ('vi', 'vi')]) {
    /// What the administrator's Home really draws in this language. Each pair
    /// is an arb key's value: `homeOpenWorkOrders` (app_en.arb:211 / app_vi.arb:211),
    /// `homeAwaitingAssignment` (219) and `accountsAwaitingApproval` (235).
    void expectLanguage() {
      const english = [
        'Open work orders',
        'Awaiting assignment',
        'Accounts awaiting Approval',
      ];
      const vietnamese = [
        'Lệnh công việc đang mở',
        'Chờ phân công',
        'Tài khoản chờ phê duyệt',
      ];
      for (final text in code == 'vi' ? vietnamese : english) {
        expect(find.text(text), findsOneWidget);
      }
      if (code == 'vi') {
        // The greeting, `homeGreeting` (app_vi.arb:168) — and none of the
        // English wording survives anywhere on the Screen.
        expect(find.text('Chào A B'), findsOneWidget);
        for (final text in english) {
          expect(find.text(text), findsNothing);
        }
      }
    }

    testWidgets('Home, $code, at the narrowest window', (tester) async {
      await _pump(tester, languageCode: code, size: narrow);
      expectLanguage();

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/home_narrow_$suffix.png'),
      );
    });

    testWidgets('Home, $code, in an expanded Shell', (tester) async {
      await _pump(tester, languageCode: code, size: wide);
      expectLanguage();

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/home_wide_$suffix.png'),
      );
    });
  }
}
