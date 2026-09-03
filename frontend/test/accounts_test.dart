/// The accounts-management Screen (issue #36), with the wire faked.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/people/account_correction_dialog.dart';
import 'package:lean_platform/people/accounts_screen.dart';
import 'package:lean_platform/people/org_unit.dart';
import 'package:lean_platform/people/org_unit_picker.dart';
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
  await tapIn(tester, find.byKey(AccountRow.correctKey(id)));
}

void main() {
  testWidgets('admitted Accounts are listed with role, Grants and standing; pending ones are not',
      (tester) async {
    await openAccounts(
      tester,
      _plant(accounts: [
        accountJson('7', 'admitted@b.c',
            role: Roles.supervisor, grants: [grantJson('10', canWrite: true)]),
        accountJson('8', 'off@b.c', role: Roles.operator, isActive: false),
        accountJson('9', 'turned-away@b.c', approvalStatus: 'rejected', isActive: false),
        accountJson('10', 'waiting@b.c', approvalStatus: 'pending', isActive: false),
      ]),
    );

    expect(find.byType(AccountsScreen), findsOneWidget);
    expect(find.text('admitted@b.c'), findsOneWidget);
    expect(find.text('Supervisor · Active'), findsOneWidget);
    expect(find.text('Operator · Deactivated'), findsOneWidget);
    expect(find.text('Operator · Rejected'), findsOneWidget);
    expect(find.text('Ho Chi Minh › Assembly · View and edit'), findsOneWidget);
    // Still waiting, so it belongs to the Approval queue and not here.
    expect(find.text('waiting@b.c'), findsNothing);
  });

  testWidgets('an empty register says plainly that nobody has been let in', (tester) async {
    await openAccounts(tester, _plant(accounts: []));
    expect(find.text('Nobody has been let in yet'), findsOneWidget);
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
    expect(find.text('Engineer · Active'), findsOneWidget);
    expect(find.byKey(AccountsScreen.noticeKey), findsOneWidget);
  });

  testWidgets('deactivating asks first, and reactivating does not', (tester) async {
    final wire = _plant(accounts: [accountJson('7', 'admitted@b.c')]);
    await openAccounts(tester, wire);

    await tapIn(tester, find.byKey(AccountRow.activeKey('7')));
    expect(find.text('Deactivate this Account?'), findsOneWidget);
    await tapIn(tester, find.widgetWithText(TextButton, 'Cancel'));
    expect(wire.activations, isEmpty);

    await tapIn(tester, find.byKey(AccountRow.activeKey('7')));
    await tapIn(tester, find.widgetWithText(FilledButton, 'Deactivate'));
    expect(wire.activations, [('7', false)]);
    expect(find.text('Operator · Deactivated'), findsOneWidget);

    // Back in, with no question asked: reactivating takes nothing away.
    await tapIn(tester, find.byKey(AccountRow.activeKey('7')));
    expect(wire.activations, [('7', false), ('7', true)]);
    expect(find.text('Operator · Active'), findsOneWidget);
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
    await tapIn(tester, find.byKey(AccountRow.activeKey('7')));
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

    expect(find.byKey(AccountRow.activeKey('1')), findsNothing);
    expect(find.byKey(AccountRow.correctKey('1')), findsNothing);
    expect(find.byKey(AccountRow.selfKey('1')), findsOneWidget);

    expect(find.byKey(AccountRow.activeKey('7')), findsOneWidget);
    expect(find.byKey(AccountRow.correctKey('7')), findsOneWidget);
    expect(find.byKey(AccountRow.selfKey('7')), findsNothing);
  });

  testWidgets("a different administrator's row keeps both actions — the guard keys on identity, not the admin role",
      (tester) async {
    await openAccounts(
      tester,
      _plant(accounts: [
        accountJson('9', 'other-admin@b.c', role: Roles.admin),
      ]),
    );

    expect(find.byKey(AccountRow.activeKey('9')), findsOneWidget);
    expect(find.byKey(AccountRow.correctKey('9')), findsOneWidget);
    expect(find.byKey(AccountRow.selfKey('9')), findsNothing);
  });
}
