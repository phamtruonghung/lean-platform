/// The Accounts Screen (issue #36, reworked into a table by issue #112),
/// with the wire faked.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/people/account_correction_dialog.dart';
import 'package:lean_platform/people/accounts_screen.dart';
import 'package:lean_platform/people/approval_queue_screen.dart';
import 'package:lean_platform/people/org_unit.dart';
import 'package:lean_platform/people/org_unit_picker.dart';
import 'package:lean_platform/people/pending_account.dart' show waitingFor;
import 'package:lean_platform/platform/access_denied_screen.dart';
import 'package:lean_platform/platform/destinations.dart';
import 'package:lean_platform/platform/router.dart';
import 'package:lean_platform/platform/shell.dart';

import 'harness.dart'
    show FakeAuthGateway, FakeWire, accountJson, grantJson, orgUnitJson, pumpApp,
        siteJson, tapIn;
import 'org_unit_picker_test.dart' show grant;

Future<void> openAccounts(WidgetTester tester, FakeWire wire) => pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: Routes.accounts,
    );

FakeWire _plant({List<Map<String, dynamic>>? accounts}) => FakeWire(
      accounts: accounts,
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [orgUnitJson('10', 'Assembly', unitType: 'area')],
        '10': [orgUnitJson('11', 'Line 1', parentId: '10', unitType: 'line')],
      },
    );

Future<void> openCorrection(WidgetTester tester, String id) async {
  await tapIn(tester, find.byKey(AccountsScreen.correctKey(id)));
}

/// Switches the pumped app to the narrow (<700px) layout — the same device
/// `work_orders_test.dart` uses for its own narrow-layout tests.
void goNarrow(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(600, 800);
  addTearDown(tester.view.reset);
}

void main() {
  // The wide table (issue #112, Decision A). The default test surface is
  // wider than `AccountsScreen.narrowBreakpoint`, so every test that does not
  // call `goNarrow` exercises this layout.

  testWidgets(
      'at >= 700px the table renders a header row and one row per Account, with the columns '
      'Name, Email, Role, Standing, Since, Grants, Actions, and no horizontal scrolling, '
      'and never uses DataTable', (tester) async {
    await openAccounts(
      tester,
      _plant(accounts: [
        accountJson('7', 'admitted@b.c',
            role: Roles.supervisor, grants: [grantJson('10', canWrite: true)]),
        accountJson('8', 'off@b.c', role: Roles.operator, isActive: false),
      ]),
    );

    expect(find.byType(AccountsScreen), findsOneWidget);
    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Role'), findsOneWidget);
    expect(find.text('Standing'), findsOneWidget);
    expect(find.text('Since'), findsOneWidget);
    expect(find.text('Grants'), findsOneWidget);
    expect(find.text('Actions'), findsOneWidget);

    expect(find.byKey(AccountsScreen.rowKey('7')), findsOneWidget);
    expect(find.byKey(AccountsScreen.rowKey('8')), findsOneWidget);
    expect(find.text('admitted@b.c'), findsOneWidget);
    expect(find.text('off@b.c'), findsOneWidget);
    expect(find.text('Supervisor'), findsOneWidget);
    expect(find.text('Deactivated'), findsOneWidget);

    expect(
      find.descendant(of: find.byType(AccountsScreen), matching: find.byType(DataTable)),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(AccountsScreen),
        matching: find.byType(SingleChildScrollView),
      ),
      findsNothing,
    );
  });

  // The narrow layout (issue #112, Decision A) — Grants rendering (Decision
  // D) is unchanged from what this Screen rendered before this issue.

  testWidgets(
      'below 700px the list renders one card per Account, and the Grants rendering is the '
      'unchanged prose/chip shape', (tester) async {
    goNarrow(tester);
    await openAccounts(
      tester,
      _plant(accounts: [
        accountJson('7', 'admitted@b.c',
            role: Roles.supervisor, grants: [grantJson('10', canWrite: true)]),
        accountJson('8', 'admin@b.c', role: Roles.admin),
        accountJson('9', 'nogrants@b.c', role: Roles.operator),
      ]),
    );

    expect(find.byKey(AccountsScreen.rowKey('7')), findsOneWidget);
    expect(find.text('Supervisor · Active'), findsOneWidget);
    expect(find.text('Ho Chi Minh › Assembly · View and edit'), findsOneWidget);
    expect(
      find.text('Acts everywhere, in every Site. No Org Unit Grants, and none needed.'),
      findsOneWidget,
    );
    expect(
      find.text('No Org Unit Grants. Can sign in, but cannot act in any Org Unit.'),
      findsOneWidget,
    );

    expect(
      find.descendant(
        of: find.byType(AccountsScreen),
        matching: find.byType(SingleChildScrollView),
      ),
      findsNothing,
    );
  });

  // Both layouts share one row key (issue #112, Decision A).

  testWidgets("both layouts key each Account's row with the same shared row key", (tester) async {
    final wire = _plant(accounts: [accountJson('7', 'admitted@b.c')]);
    await openAccounts(tester, wire);
    expect(find.byKey(AccountsScreen.rowKey('7')), findsOneWidget);

    goNarrow(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(AccountsScreen.rowKey('7')), findsOneWidget);
  });

  // Every Account, pending included (issue #112, Decision B), ordered
  // pending first and then by email.

  testWidgets(
      'a pending Account appears with Standing reading Awaiting Approval, and rows are ordered '
      'pending first, then by email', (tester) async {
    await openAccounts(
      tester,
      _plant(accounts: [
        accountJson('7', 'zed@b.c'),
        accountJson('8', 'ann@b.c', approvalStatus: 'pending', isActive: false),
        accountJson('9', 'mid@b.c'),
      ]),
    );

    expect(find.text('ann@b.c'), findsOneWidget);
    expect(find.text('Awaiting Approval'), findsOneWidget);

    final pendingY = tester.getTopLeft(find.byKey(AccountsScreen.rowKey('8'))).dy;
    final midY = tester.getTopLeft(find.byKey(AccountsScreen.rowKey('9'))).dy;
    final zedY = tester.getTopLeft(find.byKey(AccountsScreen.rowKey('7'))).dy;

    // Pending outranks every already-decided row regardless of email...
    expect(pendingY, lessThan(midY));
    expect(pendingY, lessThan(zedY));
    // ...and the already-decided rows are then ordered by email.
    expect(midY, lessThan(zedY));
  });

  // The Since cell (issue #112, Decision C): `ManagedAccount` parses
  // `createdAt`, rendered the way `PendingAccount.waitingSince` already is.

  testWidgets("ManagedAccount parses createdAt from GET /accounts, and the Since cell renders it",
      (tester) async {
    final createdAt = DateTime.now().subtract(const Duration(days: 3));
    await openAccounts(
      tester,
      _plant(accounts: [accountJson('7', 'admitted@b.c', createdAt: createdAt)]),
    );

    expect(find.text(waitingFor(createdAt)), findsOneWidget);
  });

  // The Grants cell (issue #112, Decision D): a count, not a wall of chips,
  // with the full list on hover.

  testWidgets(
      'the Grants cell reads Everywhere for an admin, None for an Account with no Grants, and '
      'a count otherwise, with the full list on hover', (tester) async {
    await openAccounts(
      tester,
      _plant(accounts: [
        accountJson('7', 'admin@b.c', role: Roles.admin),
        accountJson('8', 'nogrants@b.c'),
        accountJson('9', 'twogrants@b.c', grants: [
          grantJson('10', name: 'Assembly', canWrite: true),
          grantJson('11', name: 'Line 1'),
        ]),
      ]),
    );

    expect(find.text('Everywhere'), findsOneWidget);
    expect(find.text('None'), findsOneWidget);
    expect(find.text('2 Org Units'), findsOneWidget);

    final tooltip = tester.widget<Tooltip>(find.byKey(AccountsScreen.grantsKey('9')));
    expect(tooltip.message, contains('Ho Chi Minh › Assembly · View and edit'));
    expect(tooltip.message, contains('Ho Chi Minh › Line 1 · View'));
  });

  // A pending row's own action (issue #112, Decision E).

  testWidgets(
      "a pending row's Actions cell offers Review in Approvals, which navigates to the Approval "
      'queue, and offers neither correction nor deactivation', (tester) async {
    await openAccounts(
      tester,
      _plant(accounts: [
        accountJson('8', 'waiting@b.c', approvalStatus: 'pending', isActive: false),
      ]),
    );

    expect(find.byKey(AccountsScreen.correctKey('8')), findsNothing);
    expect(find.byKey(AccountsScreen.activeKey('8')), findsNothing);
    expect(find.byKey(AccountsScreen.reviewInApprovalsKey('8')), findsOneWidget);

    await tapIn(tester, find.byKey(AccountsScreen.reviewInApprovalsKey('8')));
    expect(find.byType(ApprovalQueueScreen), findsOneWidget);
  });

  testWidgets('an empty register says plainly there are no Accounts yet', (tester) async {
    await openAccounts(tester, _plant(accounts: []));
    expect(find.text('No Accounts yet'), findsOneWidget);
    expect(find.text('The Accounts could not be loaded'), findsNothing);
  });

  testWidgets('a failed load explains itself and the retry works', (tester) async {
    final wire = _plant(accounts: [])..accountsStatus = 500;
    await openAccounts(tester, wire);
    expect(find.text('The Accounts could not be loaded'), findsOneWidget);
    expect(find.text('The Accounts are unavailable.'), findsOneWidget);

    wire.accountsStatus = 200;
    wire.accounts = [accountJson('7', 'admitted@b.c')];
    await tester.tap(find.byKey(AccountsScreen.retryKey));
    await tester.pumpAndSettle();
    expect(find.text('admitted@b.c'), findsOneWidget);
    expect(find.text('The Accounts could not be loaded'), findsNothing);
  });

  testWidgets('the correction dialog opens holding the current role and Grants, and reuses the picker',
      (tester) async {
    await openAccounts(
      tester,
      _plant(accounts: [
        accountJson('7', 'admitted@b.c',
            role: Roles.supervisor, grants: [grantJson('10', canWrite: true)]),
      ]),
    );
    await openCorrection(tester, '7');

    expect(find.byType(AccountCorrectionDialog), findsOneWidget);
    // The one picker the Approval queue already uses, not a second one.
    expect(find.byType(OrgUnitPicker), findsOneWidget);
    // Pre-filled: the Grant it already holds is in the Granted pane.
    expect(find.text('Granted (1)'), findsOneWidget);
    expect(find.byKey(OrgUnitPicker.removeKey('10')), findsOneWidget);
    // And the role it already holds is the one selected.
    final chosen = tester
        .widgetList<RadioGroup<String>>(find.byType(RadioGroup<String>))
        .first
        .groupValue;
    expect(chosen, Roles.supervisor);
  });

  testWidgets('changing the role and the Grant set sends the whole set, and the list shows it',
      (tester) async {
    final wire = _plant(accounts: [
      accountJson('7', 'admitted@b.c',
          role: Roles.supervisor, grants: [grantJson('10', canWrite: true)]),
    ]);
    await openAccounts(tester, wire);
    await openCorrection(tester, '7');

    // Drop the Grant it holds, expand and grant a different Org Unit instead.
    await tapIn(tester, find.byKey(OrgUnitPicker.removeKey('10')));
    await tapIn(tester, find.byKey(OrgUnitPicker.expandKey('10')));
    await grant(tester, '11', GrantLevel.view);
    await tapIn(tester, find.byKey(AccountCorrectionDialog.roleKey(Roles.engineer)));
    await tapIn(tester, find.byKey(AccountCorrectionDialog.submitKey));

    expect(wire.approvals.single, {
      'role': Roles.engineer,
      'grants': [
        {'orgUnitId': '11', 'canWrite': false},
      ],
      'expectedApprovalStatus': 'approved',
    });
    expect(find.byType(AccountCorrectionDialog), findsNothing);
    expect(find.text('Engineer'), findsOneWidget);
    expect(find.byKey(AccountsScreen.noticeKey), findsOneWidget);
  });

  testWidgets('deactivating asks first, and reactivating does not', (tester) async {
    final wire = _plant(accounts: [accountJson('7', 'admitted@b.c')]);
    await openAccounts(tester, wire);

    await tapIn(tester, find.byKey(AccountsScreen.activeKey('7')));
    expect(find.text('Deactivate this Account?'), findsOneWidget);
    await tapIn(tester, find.widgetWithText(TextButton, 'Cancel'));
    expect(wire.activations, isEmpty);

    await tapIn(tester, find.byKey(AccountsScreen.activeKey('7')));
    await tapIn(tester, find.widgetWithText(FilledButton, 'Deactivate'));
    expect(wire.activations, [('7', false)]);
    expect(find.text('Deactivated'), findsOneWidget);

    // Back in, with no question asked: reactivating takes nothing away.
    await tapIn(tester, find.byKey(AccountsScreen.activeKey('7')));
    expect(wire.activations, [('7', false), ('7', true)]);
    expect(find.text('Active'), findsOneWidget);
  });

  testWidgets(
      'a second row\'s action while one is already in flight is reported, not silently '
      'dropped, and an open correction dialog does not mistake it for its own success',
      (tester) async {
    final wire = _plant(
      accounts: [accountJson('7', 'first@b.c'), accountJson('8', 'second@b.c')],
    )..patchGate = Completer<void>();
    await openAccounts(tester, wire);

    // Row 7's deactivation starts, and hangs — the patchGate holds it open,
    // the same device the Approval queue's own admission tests use to make
    // "in flight" observable.
    await tapIn(tester, find.byKey(AccountsScreen.activeKey('7')));
    await tapIn(tester, find.widgetWithText(FilledButton, 'Deactivate'));

    // Row 8's correction is opened and submitted while row 7 is still busy.
    await openCorrection(tester, '8');
    await tapIn(tester, find.byKey(AccountCorrectionDialog.submitKey));

    // Reported, not a silent no-op: the dialog stays open and says why,
    // rather than reading row 7's eventual, unrelated settlement as its own
    // success and closing having saved nothing.
    expect(find.byType(AccountCorrectionDialog), findsOneWidget);
    expect(find.byKey(AccountCorrectionDialog.failureKey), findsOneWidget);
    expect(find.textContaining('Another action is already in progress'), findsOneWidget);
    expect(wire.approvals, isEmpty);

    wire.patchGate!.complete();
    await tester.pumpAndSettle();
    expect(wire.activations, [('7', false)]);
  });

  testWidgets('a non-administrator reaches neither the destination nor the Screen',
      (tester) async {
    final wire = _plant(accounts: [accountJson('7', 'admitted@b.c')])..accountsStatus = 200;
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: FakeWire(role: Roles.supervisor, accounts: wire.accounts).client,
      initialLocation: Routes.accounts,
    );

    expect(find.byType(AccountsScreen), findsNothing);
    expect(find.byType(AccessDeniedScreen), findsOneWidget);
    expect(find.byKey(PlatformShell.sidebarKey), findsOneWidget);
    expect(find.text('Accounts'), findsNothing);
  });

  testWidgets('an administrator gets the destination in the sidebar', (tester) async {
    await openAccounts(tester, _plant(accounts: []));
    expect(
      find.descendant(
        of: find.byKey(PlatformShell.sidebarKey),
        matching: find.text('Accounts'),
      ),
      findsOneWidget,
    );
  });

  // Issue #53: an administrator cannot act on their own Account, so the
  // Screen never even offers a button the server would refuse.
  testWidgets(
      "the caller's own row offers neither action and explains why, and a different row is unaffected",
      (tester) async {
    // FakeWire's default selfId is '1' — this row's id matches it, so it is
    // the caller's own Account.
    await openAccounts(
      tester,
      _plant(accounts: [
        accountJson('1', 'admin@b.c', role: Roles.admin),
        accountJson('7', 'other@b.c'),
      ]),
    );

    expect(find.byKey(AccountsScreen.activeKey('1')), findsNothing);
    expect(find.byKey(AccountsScreen.correctKey('1')), findsNothing);
    expect(find.byKey(AccountsScreen.selfKey('1')), findsOneWidget);

    expect(find.byKey(AccountsScreen.activeKey('7')), findsOneWidget);
    expect(find.byKey(AccountsScreen.correctKey('7')), findsOneWidget);
    expect(find.byKey(AccountsScreen.selfKey('7')), findsNothing);
  });

  testWidgets("a different administrator's row keeps both actions — the guard keys on identity, not the admin role",
      (tester) async {
    await openAccounts(
      tester,
      _plant(accounts: [
        accountJson('9', 'other-admin@b.c', role: Roles.admin),
      ]),
    );

    expect(find.byKey(AccountsScreen.activeKey('9')), findsOneWidget);
    expect(find.byKey(AccountsScreen.correctKey('9')), findsOneWidget);
    expect(find.byKey(AccountsScreen.selfKey('9')), findsNothing);
  });

  // The narrow card shares `_RowActions` with the wide table (issue #112,
  // Decision A), but — unlike the wide table's fixed-width actions column —
  // sits directly in a `Row` with no width of its own. The caller's own row
  // once overflowed here: its explanation is the one `_RowActions` branch
  // long enough to need the `Flexible` the wide table gets for free from its
  // `SizedBox`. These three tests are what actually closes "no action is
  // offered on the caller's own row, at either width" — the wide-only
  // versions above do not exercise this `Row` at all.

  testWidgets(
      "at < 700px the caller's own row still offers neither action and explains why, and a "
      "different row is unaffected", (tester) async {
    goNarrow(tester);
    // FakeWire's default selfId is '1' — this row's id matches it.
    await openAccounts(
      tester,
      _plant(accounts: [
        accountJson('1', 'admin@b.c', role: Roles.admin),
        accountJson('7', 'other@b.c'),
      ]),
    );

    expect(find.byKey(AccountsScreen.activeKey('1')), findsNothing);
    expect(find.byKey(AccountsScreen.correctKey('1')), findsNothing);
    expect(find.byKey(AccountsScreen.selfKey('1')), findsOneWidget);

    expect(find.byKey(AccountsScreen.activeKey('7')), findsOneWidget);
    expect(find.byKey(AccountsScreen.correctKey('7')), findsOneWidget);
    expect(find.byKey(AccountsScreen.selfKey('7')), findsNothing);
  });

  testWidgets("at < 700px a pending row still offers only Review in Approvals", (tester) async {
    goNarrow(tester);
    await openAccounts(
      tester,
      _plant(accounts: [
        accountJson('8', 'waiting@b.c', approvalStatus: 'pending', isActive: false),
      ]),
    );

    expect(find.byKey(AccountsScreen.correctKey('8')), findsNothing);
    expect(find.byKey(AccountsScreen.activeKey('8')), findsNothing);
    expect(find.byKey(AccountsScreen.reviewInApprovalsKey('8')), findsOneWidget);
  });

  testWidgets("at < 700px an approved row still offers Deactivate/Reactivate alongside Change",
      (tester) async {
    goNarrow(tester);
    await openAccounts(tester, _plant(accounts: [accountJson('7', 'admitted@b.c')]));

    expect(find.byKey(AccountsScreen.activeKey('7')), findsOneWidget);
    expect(find.byKey(AccountsScreen.correctKey('7')), findsOneWidget);
  });
}
