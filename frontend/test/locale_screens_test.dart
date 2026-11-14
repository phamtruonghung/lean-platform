/// The language switch reaching the Screens themselves (issue t_0ac0eb9e).
///
/// **What these tests claim, through the same door a person uses.** The app is
/// pumped whole — the real router, the real Shell, the real Blocs, `MockClient`
/// at the HTTP boundary (`harness.dart`) — and every assertion is about what
/// renders: Home's greeting and cards, the Work orders register's heading,
/// buttons and column headers, the change-password dialog opened from the
/// account menu, and the words the browser tab was told to show.
///
/// **The English is asserted too, and it is the same words the Screen shipped
/// with.** A migration that quietly reworded a Screen would pass a
/// Vietnamese-only test; asserting both languages is what catches it. Nothing
/// here reads a Bloc's state or a `LocaleCubit` field directly, which is
/// AGENTS.md §5's rule for the frontend seam.
///
/// The choice is seeded into `shared_preferences` before the pump rather than
/// tapped, because `settings_test.dart` already proves the tap and the store;
/// what this file adds is that the *other* Screens follow it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lean_platform/home_screen.dart';
import 'package:lean_platform/maintenance/work_orders_screen.dart';
import 'package:lean_platform/people/directory_screen.dart';
import 'package:lean_platform/platform/change_password_dialog.dart';
import 'package:lean_platform/platform/destinations.dart';
import 'package:lean_platform/platform/locale_cubit.dart';
import 'package:lean_platform/platform/router.dart';
import 'package:lean_platform/platform/shell.dart';
import 'package:lean_platform/quality/nonconformances_screen.dart';

import 'harness.dart';

/// One open Work order, one Site, and no queued Requests: enough for Home's
/// Maintenance group and the Work orders register to have something to say.
/// [employees] fills the Directory when a case needs a row to read.
FakeWire _wire({List<Map<String, dynamic>>? employees}) => FakeWire(
      role: Roles.admin,
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      employees: employees ?? const <Map<String, dynamic>>[],
      workOrders: {
        '1': [workOrderJson('101', 'WO-101', 'Belt is slipping')],
      },
      queue: const <Map<String, dynamic>>[],
      actions: {'1': <Map<String, dynamic>>[]},
      employeeDetails: const <String, Map<String, dynamic>>{},
      // Enough for the Non-conformance register to hold one row and for the
      // form it opens to offer a Product and a Defect code.
      products: [productJson('40', 'PRD-1', 'Gearbox')],
      defectCodes: [defectCodeJson('41', 'DIM-OOT', 'Out of tolerance')],
      nonconformances: {
        '1': [nonconformanceJson('701', 'NC-HCM-2026-00001')],
      },
    );

/// Pumps the whole app at [at], in [language] (`null` = never chosen, so the
/// shipped English), with a browser that records every title it is given.
Future<RecordingDocumentChrome> _pump(
  WidgetTester tester, {
  required String at,
  String? language,
  List<Map<String, dynamic>>? employees,
}) async {
  SharedPreferences.setMockInitialValues(
    language == null ? <String, Object>{} : {LocaleCubit.storageKey: language},
  );
  tester.view.devicePixelRatio = 1.0;
  // Wide enough for the register's table, tall enough for its header and one
  // row: the narrow card is the same words in a different arrangement, and the
  // geometry tests already own that.
  tester.view.physicalSize = const Size(1200, 1000);
  addTearDown(tester.view.reset);

  final wire = _wire(employees: employees);
  final chrome = RecordingDocumentChrome();
  await pumpApp(
    tester,
    gateway: FakeAuthGateway(accessToken: 'a-token'),
    client: wire.client,
    initialLocation: at,
    documentChrome: chrome,
  );
  return chrome;
}

Future<void> _chooseVietnamese(WidgetTester tester) async {
  await tapIn(tester, find.byKey(PlatformShell.accountMenuKey));
  await tapIn(tester, find.byKey(PlatformShell.changePasswordKey));
}

void main() {
  testWidgets('Home greets and counts in Vietnamese, and not a word of the English is left',
      (tester) async {
    await _pump(tester, at: Routes.home, language: 'vi');

    // The greeting, which is the one string Home composes from a name.
    expect(find.text('Chào A B'), findsOneWidget);
    expect(find.text('Welcome, A B'), findsNothing);
    // A group heading, and the two cards under the Maintenance group.
    expect(find.text('Bảo trì'), findsOneWidget);
    expect(find.text('Maintenance'), findsNothing);
    expect(find.text('Lệnh công việc đang mở'), findsOneWidget);
    expect(find.text('Đã tạo và chưa hoàn thành'), findsOneWidget);
    expect(find.text('Chờ phân công'), findsOneWidget);
    expect(find.text('Open work orders'), findsNothing);

    // The heading a test finds by key is still keyed by the Module's English
    // name, so one finder works in either language.
    expect(find.byKey(HomeScreen.groupKey('Maintenance')), findsOneWidget);
  });

  testWidgets('the Work orders register is Vietnamese end to end: heading, action, count and every '
      'column header', (tester) async {
    await _pump(tester, at: Routes.workOrders, language: 'vi');

    // The Screen's heading and its sidebar Destination are the same catalogue
    // word, so both render it.
    expect(find.text('Lệnh công việc'), findsWidgets);
    expect(find.text('Tạo lệnh công việc'), findsOneWidget);
    expect(
      find.text('Công việc được tạo tại Nhà máy này, gắn với Thiết bị nào và ai đang phụ trách.'),
      findsOneWidget,
    );
    // The count above the register, in the singular because there is one row.
    expect(find.text('1 lệnh công việc'), findsOneWidget);
    for (final header in const ['Số WO', 'Nội dung', 'Tài sản', 'Trạng thái', 'Người phụ trách', 'Thao tác']) {
      expect(find.text(header), findsWidgets, reason: 'column header $header');
    }
    expect(find.text('Work orders'), findsNothing);
    expect(find.text('Summary'), findsNothing);
    // The register still holds the row it was given.
    expect(find.byKey(WorkOrdersScreen.rowKey('101')), findsOneWidget);
  });

  testWidgets('the browser tab is named in the chosen language', (tester) async {
    final vietnamese = await _pump(tester, at: Routes.workOrders, language: 'vi');
    expect(vietnamese.title, 'Lệnh công việc · Platform');

    // A fresh State, so the second pass really starts in English.
    await tester.pumpWidget(const SizedBox.shrink());
    final english = await _pump(tester, at: Routes.workOrders);
    expect(english.title, 'Work orders · Platform');
  });

  testWidgets('the change-password dialog the account menu opens is Vietnamese',
      (tester) async {
    await _pump(tester, at: Routes.home, language: 'vi');
    await _chooseVietnamese(tester);

    expect(find.byKey(ChangePasswordDialog.submitKey), findsOneWidget);
    // The title and the submit button are both the one catalogue word; the two
    // field labels and the cancel button are theirs.
    expect(find.text('Đổi mật khẩu'), findsNWidgets(2));
    expect(find.text('Mật khẩu hiện tại'), findsOneWidget);
    expect(find.text('Mật khẩu mới'), findsOneWidget);
    expect(find.text('Huỷ'), findsOneWidget);
    expect(find.text('Change password'), findsNothing);
    expect(find.text('Cancel'), findsNothing);

    // A local refusal — an empty current-password field — is in the same
    // language as the dialog it appears in.
    await tapIn(tester, find.byKey(ChangePasswordDialog.submitKey));
    expect(find.text('Hãy nhập mật khẩu hiện tại.'), findsOneWidget);
  });

  testWidgets('English is still the shipped default, and its words are the ones these Screens '
      'have always had', (tester) async {
    await _pump(tester, at: Routes.workOrders);

    expect(find.text('Work orders'), findsWidgets);
    expect(find.text('Raise a Work order'), findsOneWidget);
    expect(find.text('1 Work order'), findsOneWidget);
    expect(find.text('Summary'), findsOneWidget);
    expect(find.text('Lệnh công việc'), findsNothing);
  });

  testWidgets('the Non-conformance register and the form it opens are Vietnamese', (tester) async {
    await _pump(tester, at: Routes.nonConformances, language: 'vi');

    // The page head (the sidebar Destination's own word), the action that opens
    // the form, and the columns the register measures and labels itself.
    expect(find.text('Sản phẩm không phù hợp'), findsWidgets);
    expect(find.text('Ghi nhận không phù hợp'), findsOneWidget);
    for (final header in const [
      'Không phù hợp',
      'Phát hiện gì',
      'Số lượng',
      'Đã ghi nhận',
      'Thao tác',
    ]) {
      expect(find.text(header), findsWidgets, reason: 'column header $header');
    }
    expect(find.text('Record a Non-conformance'), findsNothing);
    expect(find.text('What was found'), findsNothing);
    expect(find.byKey(NonconformancesScreen.rowKey('701')), findsOneWidget);

    // The form the register opens speaks the register's language, not the
    // English it had before this sweep.
    await tapIn(tester, find.byKey(NonconformancesScreen.recordKey));
    expect(find.text('Ghi nhận không phù hợp'), findsNWidgets(2));
    expect(find.text('Sản phẩm'), findsWidgets);
    expect(find.text('Mã lỗi'), findsWidgets);
    expect(find.text('Phát hiện ở đâu'), findsOneWidget);
    expect(find.text('Huỷ'), findsOneWidget);
    expect(find.text('Record a Non-conformance'), findsNothing);
    expect(find.text('Cancel'), findsNothing);
  });

  testWidgets('the Non-conformance register is English by default, in the words it shipped with',
      (tester) async {
    await _pump(tester, at: Routes.nonConformances);

    expect(find.text('Non-conformances'), findsWidgets);
    expect(find.text('Record a Non-conformance'), findsOneWidget);
    for (final header in const ['What was found', 'Quantity', 'Filed', 'Actions']) {
      expect(find.text(header), findsWidgets, reason: 'column header $header');
    }
    expect(find.text('Sản phẩm không phù hợp'), findsNothing);
    expect(find.text('Ghi nhận không phù hợp'), findsNothing);
  });

  testWidgets('the Directory register is Vietnamese end to end: heading, its one action, and every '
      'column header the register measures itself by', (tester) async {
    await _pump(
      tester,
      at: Routes.directory,
      language: 'vi',
      employees: [employeeJson('7', 'E-7', 'Alice Nguyen')],
    );

    // The heading (the sidebar Destination's own word) and the one action that
    // opens the Employee form.
    expect(find.text('Danh bạ'), findsWidgets);
    expect(find.text('Thêm Nhân viên'), findsOneWidget);
    expect(
      find.text('Ai làm việc ở đây — tìm kiếm, lọc, và Nhân viên đã rời được ẩn đi cho tới khi cần '
          'xem.'),
      findsOneWidget,
    );
    // The band: six headers, and the two whose width the register measures from
    // the label it is drawing (`Code`, `State`) are measured from these.
    for (final header in const [
      'Nhân viên',
      'Mã',
      'Đơn vị tổ chức',
      'Chức danh công việc',
      'Hình thức làm việc',
      'Trạng thái',
    ]) {
      expect(find.text(header), findsWidgets, reason: 'column header $header');
    }
    expect(find.text('Employee'), findsNothing);
    expect(find.text('Job role'), findsNothing);
    expect(find.text('Employment'), findsNothing);
    // The register still holds the row it was given.
    expect(find.byKey(DirectoryScreen.rowKey('7')), findsOneWidget);
  });
}
