/// Admitting an Account from the queue (issue #41), with the wire faked.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/auth/awaiting_approval_screen.dart';
import 'package:lean_platform/home_screen.dart';
import 'package:lean_platform/people/admission_dialog.dart';
import 'package:lean_platform/platform/destinations.dart';

import 'approval_queue_test.dart' show openApprovals;
import 'harness.dart' show FakeAuthGateway, FakeWire, meClient, pendingJson, pumpApp;

final DateTime _twoDaysAgo = DateTime.now().subtract(const Duration(days: 2, hours: 1));

FakeWire _oneWaiting({int approveStatus = 200, String? approveMessage}) => FakeWire(
      queue: [pendingJson('7', 'first@b.c', _twoDaysAgo)],
      approveStatus: approveStatus,
      approveMessage: approveMessage ?? 'The Platform could not admit that Account.',
    );

Future<void> _openDecision(WidgetTester tester, FakeWire wire) async {
  await openApprovals(tester, wire);
  await tester.tap(find.byKey(const ValueKey('approval-queue-admit-7')));
  await tester.pumpAndSettle();
}

/// The dialog's body scrolls (it has to — issue #42 grows an Org Unit picker
/// inside it), and the 800x600 test surface is shorter than the five roles.
Future<void> chooseRole(WidgetTester tester, String role) async {
  await tester.ensureVisible(find.byKey(AdmissionDialog.roleKey(role)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(AdmissionDialog.roleKey(role)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the role choice offers exactly the roles the server defines', (tester) async {
    await _openDecision(tester, _oneWaiting());

    expect(find.text('Admit this Account'), findsOneWidget);
    final offered = tester
        .widgetList<RadioListTile<String>>(find.byType(RadioListTile<String>))
        .map((tile) => tile.value)
        .toList();
    expect(offered, [
      Roles.operator,
      Roles.supervisor,
      Roles.engineer,
      Roles.manager,
      Roles.admin,
    ]);
    // No free text anywhere in the decision.
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('with no role chosen nothing can be submitted and nothing is sent', (tester) async {
    final wire = _oneWaiting();
    await _openDecision(tester, wire);

    final submit = tester.widget<FilledButton>(find.byKey(AdmissionDialog.submitKey));
    expect(submit.onPressed, isNull, reason: 'no role chosen yet');

    await tester.tap(find.byKey(AdmissionDialog.submitKey));
    await tester.pumpAndSettle();

    expect(wire.approvals, isEmpty);
    expect(wire.requests.where((r) => r.endsWith('/approval')), isEmpty);
    expect(find.text('Admit this Account'), findsOneWidget);
  });

  testWidgets('choosing the administrator role makes its consequence plain', (tester) async {
    await _openDecision(tester, _oneWaiting());

    expect(find.byKey(AdmissionDialog.adminWarningKey), findsNothing);

    await chooseRole(tester, Roles.operator);
    expect(find.byKey(AdmissionDialog.adminWarningKey), findsNothing);

    await chooseRole(tester, Roles.admin);
    expect(find.byKey(AdmissionDialog.adminWarningKey), findsOneWidget);
    expect(find.textContaining('act everywhere'), findsOneWidget);
    expect(find.textContaining('No Org Unit Grants are given'), findsOneWidget);
  });

  testWidgets('a successful admission sends one request with the role and an empty Grant set, '
      'clears the row and confirms the outcome', (tester) async {
    final wire = _oneWaiting();
    await _openDecision(tester, wire);
    await chooseRole(tester, Roles.admin);

    await tester.tap(find.byKey(AdmissionDialog.submitKey));
    await tester.pumpAndSettle();

    expect(wire.approvals.length, 1);
    expect(wire.approvals.single['role'], Roles.admin);
    expect(wire.approvals.single['grants'], isEmpty);
    expect(wire.requests.where((r) => r == 'POST /api/people/accounts/7/approval').length, 1);

    // The decision is over, the row is gone, and the queue says so.
    expect(find.text('Admit this Account'), findsNothing);
    expect(find.text('first@b.c'), findsNothing);
    expect(find.textContaining('Admitted to the Platform as admin'), findsOneWidget);
    // Not a refetch: the response already said the row is gone.
    expect(wire.requests.where((r) => r == 'GET /api/people/accounts/pending').length, 1);
  });

  testWidgets('a second submission while one is in flight sends nothing', (tester) async {
    final wire = _oneWaiting();
    wire.approvalGate = Completer<void>();
    await _openDecision(tester, wire);
    await chooseRole(tester, Roles.manager);

    await tester.tap(find.byKey(AdmissionDialog.submitKey));
    await tester.pump();

    // In flight: the button says so and refuses.
    expect(find.text('Admitting…'), findsWidgets);
    expect(
      tester.widget<FilledButton>(find.byKey(AdmissionDialog.submitKey)).onPressed,
      isNull,
    );

    await tester.tap(find.byKey(AdmissionDialog.submitKey), warnIfMissed: false);
    await tester.pump();
    expect(wire.approvals.length, 1);

    wire.approvalGate!.complete();
    await tester.pumpAndSettle();
    expect(wire.approvals.length, 1);
    expect(find.text('first@b.c'), findsNothing);
  });

  testWidgets('a failed admission surfaces the server message and keeps the chosen role',
      (tester) async {
    final wire = _oneWaiting(approveStatus: 500, approveMessage: 'The database is unreachable.');
    await _openDecision(tester, wire);
    await chooseRole(tester, Roles.engineer);

    await tester.tap(find.byKey(AdmissionDialog.submitKey));
    await tester.pumpAndSettle();

    // Still open, still holding the choice, and saying what went wrong.
    expect(find.text('Admit this Account'), findsOneWidget);
    expect(find.byKey(AdmissionDialog.failureKey), findsOneWidget);
    expect(find.text('The database is unreachable.'), findsWidgets);
    final chosen = tester.widget<RadioGroup<String>>(find.byType(RadioGroup<String>));
    expect(chosen.groupValue, Roles.engineer);

    // And it can be sent again, unchanged.
    wire.approveStatus = 200;
    await tester.tap(find.byKey(AdmissionDialog.submitKey));
    await tester.pumpAndSettle();
    expect(wire.approvals.length, 2);
    expect(wire.approvals.last['role'], Roles.engineer);
    expect(find.text('first@b.c'), findsNothing);
  });

  testWidgets('an Account another administrator already admitted is reported, and the queue refreshes',
      (tester) async {
    final wire = _oneWaiting(approveStatus: 409);
    await _openDecision(tester, wire);
    await chooseRole(tester, Roles.admin);

    // Somebody else dealt with row 7 while this decision was open.
    wire.queue = [];

    await tester.tap(find.byKey(AdmissionDialog.submitKey));
    await tester.pumpAndSettle();

    expect(find.text('Admit this Account'), findsNothing);
    expect(find.byKey(const ValueKey('approval-queue-notice')), findsOneWidget);
    expect(find.textContaining('Another administrator has already dealt with'), findsOneWidget);
    expect(wire.requests.where((r) => r == 'GET /api/people/accounts/pending').length, 2);
    expect(find.text('first@b.c'), findsNothing);
  });

  testWidgets('a person admitted while waiting reaches the Platform without clearing anything',
      (tester) async {
    // One browser, one session, one stored token throughout — nothing about
    // this client changes when an administrator admits the Account.
    var admitted = false;
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: meClient(() => admitted
          ? {
              'status': 'active',
              'account': {
                'id': '1',
                'email': 'first@b.c',
                'displayName': 'First',
                'role': Roles.admin,
              },
            }
          : {
              'status': 'pending_approval',
              'account': {'email': 'first@b.c'},
            }),
      initialLocation: '/',
    );

    expect(find.byType(AwaitingApprovalScreen), findsOneWidget);

    admitted = true;
    await tester.tap(find.byKey(AwaitingApprovalScreen.checkAgainKey));
    await tester.pumpAndSettle();

    expect(find.byType(AwaitingApprovalScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
  });
}
