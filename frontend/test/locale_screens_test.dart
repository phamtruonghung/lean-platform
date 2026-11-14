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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lean_platform/home_screen.dart';
import 'package:lean_platform/l10n/app_localizations.dart';
import 'package:lean_platform/l10n/notices.dart';
import 'package:lean_platform/maintenance/work_orders_screen.dart';
import 'package:lean_platform/people/accounts_screen.dart';
import 'package:lean_platform/people/account_correction_dialog.dart';
import 'package:lean_platform/people/directory_screen.dart';
import 'package:lean_platform/people/managed_account.dart' show ApprovalStatuses;
import 'package:lean_platform/maintenance/tier_board_screen.dart';
import 'package:lean_platform/platform/change_password_dialog.dart';
import 'package:lean_platform/platform/destinations.dart';
import 'package:lean_platform/platform/locale_cubit.dart';
import 'package:lean_platform/platform/router.dart';
import 'package:lean_platform/platform/shell.dart';
import 'package:lean_platform/quality/nonconformances_screen.dart';
import 'package:lean_platform/theme.dart';
import 'package:lean_platform/widgets/app_confirm_dialog.dart';
import 'package:lean_platform/widgets/app_dialog.dart';
import 'package:lean_platform/widgets/failure_state.dart';

import 'harness.dart';

/// One open Work order, one Site, and no queued Requests: enough for Home's
/// Maintenance group and the Work orders register to have something to say.
/// [employees] fills the Directory when a case needs a row to read, and
/// [accounts] the Accounts register when a case needs a role chip.
FakeWire _wire({
  List<Map<String, dynamic>>? employees,
  List<Map<String, dynamic>>? accounts,
}) =>
    FakeWire(
      role: Roles.admin,
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      employees: employees ?? const <Map<String, dynamic>>[],
      accounts: accounts ?? const <Map<String, dynamic>>[],
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
      // One Customer complaint whose product is controlled by a Non-conformance
      // found by the customer: the detail screen picks its sentence from the
      // stored detection point, so it is the record a Vietnamese assertion
      // needs.
      complaints: {
        '1': [
          customerComplaintJson(
            '70',
            'CC-2026-00001',
            nonconformance: complaintNonconformanceJson('950', 'NC-HCM-2026-00050'),
          ),
        ],
      },
    );

/// Pumps the whole app at [at], in [language] (`null` = never chosen, so the
/// shipped English), with a browser that records every title it is given.
Future<RecordingDocumentChrome> _pump(
  WidgetTester tester, {
  required String at,
  String? language,
  List<Map<String, dynamic>>? employees,
  List<Map<String, dynamic>>? accounts,
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

  final wire = _wire(employees: employees, accounts: accounts);
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

  testWidgets('a Customer complaint detail in Vietnamese still picks the sentence from the stored '
      'detection point', (tester) async {
    await _pump(tester, at: '/complaints/70', language: 'vi');

    // The record says `detectionPoint: 'customer'` — a token the database
    // stores, and one the screen must compare to as a token. The words change
    // with the language; the branch does not. Comparing the token to the
    // Vietnamese label instead made this false in Vietnamese only, so a
    // Vietnamese reader was told the Non-conformance was recorded somewhere
    // rather than found by the customer.
    expect(
      find.text('Do khách hàng phát hiện, nên khiếu nại này là nơi mọi việc bắt đầu.'),
      findsOneWidget,
    );
    expect(find.textContaining('Ghi nhận ngày customer'), findsNothing);
  });

  testWidgets('a status chip, a job-role chip and the signed-out message all speak Vietnamese '
      '(ADR-0062)', (tester) async {
    // 1. The Work order's own status chip. `workOrderJson` defaults to
    // `approved`, a wire token the model keeps and the catalogue names; before
    // this slice the chip printed the model's English word in both languages.
    await _pump(tester, at: Routes.workOrders, language: 'vi');
    expect(find.text('Đã duyệt'), findsOneWidget);
    expect(find.text('Approved'), findsNothing);

    // The English is still what English gets — the same chip, the same row.
    await tester.pumpWidget(const SizedBox.shrink());
    await _pump(tester, at: Routes.workOrders);
    expect(find.text('Approved'), findsOneWidget);
    expect(find.text('Đã duyệt'), findsNothing);

    // 2. A job-role chip on the Accounts register: `admissionRoles` used to
    // carry the English label and description themselves.
    await tester.pumpWidget(const SizedBox.shrink());
    await _pump(
      tester,
      at: Routes.accounts,
      language: 'vi',
      accounts: [accountJson('7', 'sup@b.c', role: Roles.supervisor)],
    );
    expect(find.text('Giám sát'), findsWidgets);
    expect(find.text('Supervisor'), findsNothing);

    // 3. The standing chip beside that role chip. `ManagedAccount.standing` used
    // to return the English words themselves, so a Vietnamese register said
    // "Supervisor" and "Active" on the same row.
    expect(find.text('Đang hoạt động'), findsOneWidget);
    expect(find.text('Active'), findsNothing);
  });

  testWidgets('every Account standing is a catalogue word under Vietnamese, and the English is '
      'gone', (tester) async {
    // The four standings the chip can show, one row each — the account is
    // approved (and so Active), approved but switched off, still waiting, and
    // turned away. `accountStandingLabel` is the one lookup behind all four.
    await _pump(
      tester,
      at: Routes.accounts,
      language: 'vi',
      accounts: [
        accountJson('7', 'active@b.c'),
        accountJson('8', 'gone@b.c', isActive: false),
        accountJson('9', 'waiting@b.c', approvalStatus: ApprovalStatuses.pending),
        accountJson('10', 'refused@b.c', approvalStatus: ApprovalStatuses.rejected),
      ],
    );

    expect(find.text('Đang hoạt động'), findsOneWidget);
    expect(find.text('Đã vô hiệu'), findsOneWidget);
    expect(find.text('Chờ phê duyệt'), findsOneWidget);
    expect(find.text('Bị từ chối'), findsOneWidget);
    for (final english in const ['Active', 'Deactivated', 'Awaiting Approval', 'Rejected']) {
      expect(find.text(english), findsNothing, reason: 'English standing $english');
    }

    // The Grants a row carries, where the wide table puts them: the tooltip's
    // sentence names the level and the authority in the reader's language too.
    await tester.pumpWidget(const SizedBox.shrink());
    await _pump(
      tester,
      at: Routes.accounts,
      language: 'vi',
      accounts: [
        accountJson(
          '7',
          'holder@b.c',
          grants: [
            grantJson('10', name: 'Assembly', canWrite: true, qualityAuthority: true),
          ],
        ),
      ],
    );
    expect(
      find.byTooltip('Ho Chi Minh › Assembly · Xem và sửa · Thẩm quyền Chất lượng'),
      findsOneWidget,
    );
    expect(find.byTooltip('Ho Chi Minh › Assembly · View and edit · Quality authority'), findsNothing);
  });

  testWidgets('the Tier board period selector reads Vietnamese, and offers no English',
      (tester) async {
    // `BoardPeriodType.label` used to be the enum's own English word, so the
    // selector on a reachable Destination said Day / Week / Month under
    // Vietnamese (ADR-0062's "the board's fixed sets").
    await _pump(tester, at: Routes.tierBoard, language: 'vi');

    // The Bloc starts on `day`, so that is the item the closed selector draws.
    // (`Ngày` is also the date field's label — the same word, as Vietnamese has
    // it; the sentinel below is what proves the period word is the catalogue's.)
    expect(find.text('Ngày'), findsWidgets);
    expect(find.text('Day'), findsNothing);

    await tapIn(tester, find.byKey(TierBoardScreen.periodTypeKey));
    await tester.pumpAndSettle();
    for (final vietnamese in const ['Tuần', 'Tháng']) {
      expect(find.text(vietnamese), findsWidgets, reason: 'period $vietnamese');
    }
    for (final english in const ['Day', 'Week', 'Month']) {
      expect(find.text(english), findsNothing, reason: 'period $english');
    }
  });

  testWidgets('the signed-out sentence renders in the chosen language from the Bloc code it '
      'travels as', (tester) async {
    // A Bloc has no `BuildContext`, so the sentence travels as
    // `BlocNotice.sessionEnded` and the widget that renders a failed read
    // resolves it (`l10n/notices.dart`). This pumps that seam directly: the
    // whole-app path signs out and leaves the Screen before the sentence can
    // be read, which `local_auth_test.dart` already covers.
    Future<void> show(Locale locale) => tester.pumpWidget(
          MaterialApp(
            locale: locale,
            theme: buildAppTheme(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => PlatformFailureState(
                title: AppLocalizations.of(context).commonStatus,
                message: BlocNotice.sessionEnded,
                onRetry: () {},
              ),
            ),
          ),
        );

    await show(const Locale('vi'));
    expect(find.text('Phiên làm việc đã kết thúc. Vui lòng đăng nhập lại để tiếp tục.'), findsOneWidget);
    expect(find.textContaining('This session has ended'), findsNothing);

    await show(const Locale('en'));
    expect(find.text('This session has ended. Sign in again to continue.'), findsOneWidget);

    // A server's own sentence is prose, not a code: it is never looked up.
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('vi'),
        theme: buildAppTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => PlatformFailureState(
            title: AppLocalizations.of(context).commonStatus,
            message: 'The server refused that read.',
            onRetry: () {},
          ),
        ),
      ),
    );
    expect(find.text('The server refused that read.'), findsOneWidget);
  });

  testWidgets('a register chip that used to be an English table is Vietnamese too',
      (tester) async {
    // `ComplaintStatus` keeps its wires and nothing else: the word on this chip
    // is `complaintStatusLabel` (`l10n/vocabulary.dart`), the same lookup a
    // Work order's own status chip already goes through (ADR-0062).
    await _pump(tester, at: Routes.complaints, language: 'vi');

    expect(find.text('Mở'), findsWidgets);
    expect(find.text('Open'), findsNothing);
  });

  testWidgets('a dialog description that carries a Bloc code is a sentence, not the code',
      (tester) async {
    // A dialog had no resolver until this round: `AppDialog(description: …)`
    // printed whatever it was handed, so a Bloc's code reached the reader. This
    // is the same seam as a Screen's banner, proved on the dialog's own shell.
    Future<void> show(Locale locale) => tester.pumpWidget(
          MaterialApp(
            locale: locale,
            theme: buildAppTheme(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: AppDialog(
                  title: AppLocalizations.of(context).commonStatus,
                  description: BlocNotice.sessionEnded,
                  actions: const <AppDialogAction>[],
                  child: const SizedBox(height: 20),
                ),
              ),
            ),
          ),
        );

    await show(const Locale('vi'));
    expect(find.text('Phiên làm việc đã kết thúc. Vui lòng đăng nhập lại để tiếp tục.'), findsOneWidget);
    expect(find.textContaining('notice:'), findsNothing);

    await show(const Locale('en'));
    expect(find.text('This session has ended. Sign in again to continue.'), findsOneWidget);
    expect(find.textContaining('notice:'), findsNothing);
  });

  testWidgets('a dialog that keeps its own failure word prints it in Vietnamese',
      (tester) async {
    // The end-to-end half: a real dialog, a real Bloc and a real in-flight
    // refusal. `AccountsBloc` says `BlocNotice.actionInFlight`; the dialog's own
    // failure block is a `NoticeText`, so the sentence — not `notice:…` — is
    // what the reader sees.
    SharedPreferences.setMockInitialValues({LocaleCubit.storageKey: 'vi'});
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.reset);

    final wire = FakeWire(
      accounts: [accountJson('7', 'first@b.c'), accountJson('8', 'second@b.c')],
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [orgUnitJson('10', 'Assembly', unitType: 'area')],
        '10': [orgUnitJson('11', 'Line 1', parentId: '10', unitType: 'line')],
      },
    )..patchGate = Completer<void>();
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: Routes.accounts,
    );

    // Row 7's deactivation starts and hangs on the wire, so the Bloc is busy.
    await tapIn(tester, find.byKey(AccountsScreen.rowActionsKey('7')));
    await tapIn(tester, find.byKey(AccountsScreen.activeKey('7')));
    await tapIn(tester, find.byKey(AppConfirmDialog.confirmKey));

    // Row 8's correction is submitted while that is still in flight.
    await tapIn(tester, find.byKey(AccountsScreen.rowActionsKey('8')));
    await tapIn(tester, find.byKey(AccountsScreen.correctKey('8')));
    await tapIn(tester, find.byKey(AccountCorrectionDialog.submitKey));

    expect(find.byKey(AccountCorrectionDialog.failureKey), findsOneWidget);
    expect(
      find.text('Một thao tác khác đang được thực hiện. Vui lòng thử lại sau giây lát.'),
      findsOneWidget,
    );
    expect(find.textContaining('notice:'), findsNothing);
    expect(find.textContaining('Another action is already in progress'), findsNothing);

    wire.patchGate!.complete();
    await tester.pumpAndSettle();
  });
}
