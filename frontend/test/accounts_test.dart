/// The Accounts Screen (issue #36, reworked into a table by issue #112),
/// with the wire faked.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/people/account_correction_dialog.dart';
import 'package:lean_platform/people/account_employee_dialog.dart';
import 'package:lean_platform/people/accounts_screen.dart';
import 'package:lean_platform/people/approval_queue_screen.dart';
import 'package:lean_platform/people/employee_link_picker.dart';
import 'package:lean_platform/people/org_unit.dart';
import 'package:lean_platform/people/org_unit_picker.dart';
import 'package:lean_platform/people/pending_account.dart' show waitingFor;
import 'package:lean_platform/platform/access_denied_screen.dart';
import 'package:lean_platform/platform/destinations.dart';
import 'package:lean_platform/platform/router.dart';
import 'package:lean_platform/platform/shell.dart';

import 'harness.dart'
    show FakeAuthGateway, FakeWire, accountJson, employeeJson, grantJson, orgUnitJson, pumpApp,
        siteJson, tapIn;
import 'org_unit_picker_test.dart' show grant;

Future<void> openAccounts(WidgetTester tester, FakeWire wire) => pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: Routes.accounts,
    );

FakeWire _plant({List<Map<String, dynamic>>? accounts, List<Map<String, dynamic>>? employees}) =>
    FakeWire(
      accounts: accounts,
      employees: employees,
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [orgUnitJson('10', 'Assembly', unitType: 'area')],
        '10': [orgUnitJson('11', 'Line 1', parentId: '10', unitType: 'line')],
      },
    );

Future<void> openEmployeeLink(WidgetTester tester, String id) async {
  await tapIn(tester, find.byKey(AccountsScreen.linkEmployeeKey(id)));
}

Future<void> openCorrection(WidgetTester tester, String id) async {
  await tapIn(tester, find.byKey(AccountsScreen.correctKey(id)));
}

/// Switches the pumped app to the narrow (<850px of content) layout — the
/// same device `work_orders_test.dart` uses for its own narrow-layout tests.
void goNarrow(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(600, 800);
  addTearDown(tester.view.reset);
}

/// Switches the pumped app to a window wide enough to guarantee the table
/// layout regardless of the Shell's own sidebar width (issue #120):
/// `AccountsScreen` now measures its own *content* width, not the window
/// (`AccountsScreen.narrowBreakpoint`'s own doc comment), so a test whose
/// assertions only make sense against the wide table can no longer rely on
/// flutter_test's default logical window size (800×600) the way it could
/// before this issue — that default sits well under 850px of content once
/// the Shell's own 260px expanded sidebar is subtracted, and would silently
/// render cards instead.
void goWide(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1200, 900);
  addTearDown(tester.view.reset);
}

void main() {
  // The wide table (issue #112, Decision A).

  testWidgets(
      'at >= 850px of content the table renders a header row and one row per Account, with the '
      'columns Name, Email, Role, Standing, Since, Grants, Actions, and no horizontal scrolling, '
      'and never uses DataTable', (tester) async {
    goWide(tester);
    await openAccounts(
      tester,
      _plant(accounts: [
        accountJson('7', 'admitted@b.c',
            role: Roles.supervisor, grants: [grantJson('10', canWrite: true)]),
        accountJson('8', 'off@b.c', role: Roles.operator, isActive: false),
      ]),
    );

    expect(find.byType(AccountsScreen), findsOneWidget);
    // Scoped to the Screen rather than a bare `find.text('Actions')` (issue
    // #176): 'Actions' is now also the Shell's own group heading for the
    // Actions Module, which is on screen beside this table and would make a
    // bare finder find two widgets. What this asserts is unchanged — the
    // table's own header carries all seven column labels, once each.
    expect(find.descendant(of: find.byType(AccountsScreen), matching: find.text('Name')),
        findsOneWidget);
    expect(find.descendant(of: find.byType(AccountsScreen), matching: find.text('Email')),
        findsOneWidget);
    expect(find.descendant(of: find.byType(AccountsScreen), matching: find.text('Role')),
        findsOneWidget);
    expect(find.descendant(of: find.byType(AccountsScreen), matching: find.text('Standing')),
        findsOneWidget);
    expect(find.descendant(of: find.byType(AccountsScreen), matching: find.text('Since')),
        findsOneWidget);
    expect(find.descendant(of: find.byType(AccountsScreen), matching: find.text('Grants')),
        findsOneWidget);
    expect(find.descendant(of: find.byType(AccountsScreen), matching: find.text('Actions')),
        findsOneWidget);

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
      'below 850px of content the list renders one card per Account, and the Grants rendering is the '
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

  // Regression (issue #120): this Screen used to decide cards-versus-table
  // off `MediaQuery.sizeOf(context).width` — the whole browser window — even
  // though it only ever renders inside the Shell's own content area.
  // `PlatformShell`'s own rail breakpoint (`shell.dart`) also sits at 700px
  // of window, and switches to its 260px expanded sidebar at exactly that
  // width, not below it — so at a 700px window this Screen used to see
  // "700px, that's the table" while the box it actually had was 440px, and
  // rendered a table so cramped its own columns ran together. Proved here the
  // same honest way `work_orders_test.dart` proved the same bug for #105: at
  // the exact width the two breakpoints used to collide, assert the Screen
  // renders cards, not the table — using only text a person can read (the
  // table header's own column labels, which cards never render), not a third
  // seam into any render object or Bloc state.
  //
  // The fixture below (an approved, non-self, non-pending Account with a
  // Grant) is deliberate, not incidental: it is the one row shape that
  // renders both "Deactivate" and "Change" plus the Employee-link icon, and
  // at this test's own 440px content width that three-control case is also
  // what exposed `_AccountCard`'s own pre-#120 overflow (its actions used to
  // sit beside the info column in one `Row`, which this width does not leave
  // room for) — so this one test doubles as the regression guard for both
  // defects, and a widget test fails on its own if either reappears.
  testWidgets(
      "at a 700px window — where the Shell's own sidebar breakpoint and this Screen's old, "
      'mistaken window-based breakpoint used to collide — the list renders as cards, not the '
      'corrupted table the pre-#120 window-based breakpoint produced', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(700, 800);
    addTearDown(tester.view.reset);

    await openAccounts(
      tester,
      _plant(accounts: [
        accountJson('7', 'admitted@b.c',
            role: Roles.supervisor, grants: [grantJson('10', canWrite: true)]),
      ]),
    );

    // The table header's own column labels are the one thing only the wide
    // (table) layout ever renders — their absence, alongside the row's own
    // content still being fully present, is what distinguishes cards from a
    // squeezed table without reaching into anything but text on screen.
    // Scoped to this Screen for the same reason the header assertions above
    // are (issue #176): the Shell's own 'Actions' group heading is on screen
    // and is not this table's.
    expect(find.descendant(of: find.byType(AccountsScreen), matching: find.text('Name')),
        findsNothing);
    expect(find.descendant(of: find.byType(AccountsScreen), matching: find.text('Actions')),
        findsNothing);
    expect(find.byKey(AccountsScreen.rowKey('7')), findsOneWidget);
    expect(find.text('admitted@b.c'), findsOneWidget);
  });

  // Both layouts share one row key (issue #112, Decision A).

  testWidgets("both layouts key each Account's row with the same shared row key", (tester) async {
    goWide(tester);
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
    // The Standing cell asserted below ('Awaiting Approval' alone) is the
    // wide table's own separate column (issue #120) — the narrow card folds
    // role and standing into one combined string instead.
    goWide(tester);
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
    // The Since cell is a wide-table-only column (issue #120) — the narrow
    // card never renders it, so this test needs the wide window explicit.
    goWide(tester);
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
    // The Grants cell asserted here (`_GrantsCell`) is the wide-table-only
    // shape (issue #120) — the narrow card renders `_Grants`'s own prose/chip
    // shape instead, covered separately above.
    goWide(tester);
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
    // The Role cell asserted below ('Engineer' alone) is the wide table's own
    // separate column (issue #120) — the narrow card folds role and standing
    // into one combined string instead.
    goWide(tester);
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
    // The Standing cell asserted below ('Deactivated'/'Active' alone) is the
    // wide table's own separate column (issue #120) — the narrow card folds
    // role and standing into one combined string instead.
    goWide(tester);
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
  // Decision A). Since issue #120 it sits on its own full-width line at the
  // bottom of the card, the same shape `work_orders_screen.dart`'s own
  // `_WorkOrderCard` uses, rather than beside the info column in a `Row` with
  // no width of its own — see `_RowActions`'s own doc comment for why that
  // moved. These three tests are what actually closes "no action is offered
  // on the caller's own row, at either width" — the wide-only versions above
  // do not exercise the narrow card at all.

  testWidgets(
      "at < 850px of content the caller's own row still offers neither action and explains why, and a "
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

  testWidgets("at < 850px of content a pending row still offers only Review in Approvals", (tester) async {
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

  testWidgets("at < 850px of content an approved row still offers Deactivate/Reactivate alongside Change",
      (tester) async {
    goNarrow(tester);
    await openAccounts(tester, _plant(accounts: [accountJson('7', 'admitted@b.c')]));

    expect(find.byKey(AccountsScreen.activeKey('7')), findsOneWidget);
    expect(find.byKey(AccountsScreen.correctKey('7')), findsOneWidget);
  });

  // The Employee link (issue #116, ADR-0022).

  testWidgets('the Employee cell names the linked Employee, or says none — neither is a problem',
      (tester) async {
    await openAccounts(
      tester,
      _plant(
        accounts: [
          accountJson('7', 'linked@b.c', employeeId: '40'),
          accountJson('8', 'unlinked@b.c'),
        ],
        employees: [employeeJson('40', 'EMP-40', 'Jane Doe')],
      ),
    );

    expect(find.byKey(AccountsScreen.employeeKey('7')), findsOneWidget);
    expect(find.text('EMP-40 · Jane Doe'), findsOneWidget);
    expect(find.byKey(AccountsScreen.employeeKey('8')), findsOneWidget);
    expect(find.text('No Employee linked'), findsOneWidget);
  });

  testWidgets('linking an Employee from the Accounts Screen sends PUT /accounts/:id/employee',
      (tester) async {
    final wire = _plant(
      accounts: [accountJson('7', 'unlinked@b.c')],
      employees: [employeeJson('40', 'EMP-40', 'Jane Doe')],
    );
    await openAccounts(tester, wire);

    await openEmployeeLink(tester, '7');
    expect(find.byType(AccountEmployeeDialog), findsOneWidget);

    await tester.enterText(find.byKey(EmployeeLinkPicker.searchFieldKey), 'Jane');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    await tapIn(tester, find.byKey(EmployeeLinkPicker.resultKey('40')));
    await tapIn(tester, find.byKey(AccountEmployeeDialog.submitKey));

    expect(wire.employeeLinkPuts, [('7', '40')]);
    expect(find.byType(AccountEmployeeDialog), findsNothing);
    expect(find.text('EMP-40 · Jane Doe'), findsOneWidget);
    expect(find.byKey(AccountsScreen.noticeKey), findsOneWidget);
  });

  testWidgets('unlinking an Employee from the Accounts Screen sends employeeId: null',
      (tester) async {
    final wire = _plant(
      accounts: [accountJson('7', 'linked@b.c', employeeId: '40')],
      employees: [employeeJson('40', 'EMP-40', 'Jane Doe')],
    );
    await openAccounts(tester, wire);

    await openEmployeeLink(tester, '7');
    await tapIn(tester, find.byKey(EmployeeLinkPicker.clearKey));
    await tapIn(tester, find.byKey(AccountEmployeeDialog.submitKey));

    expect(wire.employeeLinkPuts, [('7', null)]);
    expect(find.text('No Employee linked'), findsOneWidget);
  });

  testWidgets("the link control is absent on the caller's own row, matching the backend's "
      'ADR-0013 refusal', (tester) async {
    await openAccounts(
      tester,
      _plant(
        accounts: [
          accountJson('1', 'admin@b.c', role: Roles.admin, employeeId: '40'),
          accountJson('7', 'other@b.c'),
        ],
        employees: [employeeJson('40', 'EMP-40', 'Jane Doe')],
      ),
    );

    expect(find.byKey(AccountsScreen.linkEmployeeKey('1')), findsNothing);
    // The value cell still names the link — showing it is not an action.
    expect(find.byKey(AccountsScreen.employeeKey('1')), findsOneWidget);
    expect(find.text('EMP-40 · Jane Doe'), findsOneWidget);

    expect(find.byKey(AccountsScreen.linkEmployeeKey('7')), findsOneWidget);
  });

  testWidgets('each of the three Employee-link refusals surfaces its own message', (tester) async {
    final wire = _plant(accounts: [accountJson('7', 'unlinked@b.c')])
      ..putEmployeeLinkStatus = 404
      ..putEmployeeLinkMessage = 'employeeId does not name an existing Employee';
    await openAccounts(tester, wire);

    await openEmployeeLink(tester, '7');
    await tapIn(tester, find.byKey(AccountEmployeeDialog.submitKey));

    expect(find.byKey(AccountEmployeeDialog.failureKey), findsOneWidget);
    expect(find.text('employeeId does not name an existing Employee'), findsOneWidget);

    wire.putEmployeeLinkStatus = 409;
    wire.putEmployeeLinkMessage = 'This Employee has Departed and cannot be linked to an Account';
    await tapIn(tester, find.byKey(AccountEmployeeDialog.submitKey));
    expect(find.text('This Employee has Departed and cannot be linked to an Account'), findsOneWidget);

    wire.putEmployeeLinkMessage = 'This Employee is already linked to a different Account';
    await tapIn(tester, find.byKey(AccountEmployeeDialog.submitKey));
    expect(find.text('This Employee is already linked to a different Account'), findsOneWidget);
  });
}
