/// Admitting an Account from the queue (issue #41), with the wire faked.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/auth/awaiting_approval_screen.dart';
import 'package:lean_platform/home_screen.dart';
import 'package:lean_platform/people/admission_dialog.dart';
import 'package:lean_platform/people/employee_link_picker.dart';
import 'package:lean_platform/platform/destinations.dart';

import 'approval_queue_test.dart' show openApprovals;
import 'harness.dart'
    show
        FakeAuthGateway,
        FakeWire,
        employeeJson,
        meClient,
        pendingJson,
        pumpApp,
        suggestedEmployeeJson,
        tapIn;

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
    // No free text for the role itself — the only TextField in the decision
    // is the Employee link picker's own Directory search (issue #116).
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byKey(EmployeeLinkPicker.searchFieldKey), findsOneWidget);
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
    final wire = _oneWaiting(approveStatus: 409)..approveCode = 'APPROVAL_STATUS_CHANGED';
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

  // The Employee link (issue #116, ADR-0022): the Approval flow offers the
  // suggested Employee, confirming it as part of approving rather than in a
  // separate step.

  testWidgets(
      'the suggested Employee renders, named by employee number and display name, and is '
      'sent on approval', (tester) async {
    final wire = FakeWire(
      queue: [
        pendingJson(
          '7',
          'first@b.c',
          _twoDaysAgo,
          suggestedEmployee: suggestedEmployeeJson('40', 'EMP-40', 'Jane Doe'),
        ),
      ],
    );
    await _openDecision(tester, wire);

    expect(find.textContaining('EMP-40'), findsOneWidget);
    expect(find.textContaining('Jane Doe'), findsOneWidget);

    await chooseRole(tester, Roles.operator);
    await tester.tap(find.byKey(AdmissionDialog.submitKey));
    await tester.pumpAndSettle();

    expect(wire.approvals.single['employeeId'], '40');
  });

  testWidgets('an administrator can override the suggestion by typing into the Directory search, '
      'and the chosen id is sent instead', (tester) async {
    final wire = FakeWire(
      queue: [
        pendingJson(
          '7',
          'first@b.c',
          _twoDaysAgo,
          suggestedEmployee: suggestedEmployeeJson('40', 'EMP-40', 'Jane Doe'),
        ),
      ],
      employees: [employeeJson('41', 'EMP-41', 'Alex Rios')],
    );
    await _openDecision(tester, wire);

    // No Search button to tap any more (issue #129) — typing and waiting out
    // `AppSearchField`'s own debounce is what surfaces a match.
    await tester.enterText(find.byKey(EmployeeLinkPicker.searchFieldKey), 'Alex');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(find.byKey(EmployeeLinkPicker.resultKey('41')), findsOneWidget);
    await tapIn(tester, find.byKey(EmployeeLinkPicker.resultKey('41')));

    expect(find.textContaining('Alex Rios'), findsOneWidget);
    expect(find.textContaining('Jane Doe'), findsNothing);

    await chooseRole(tester, Roles.operator);
    await tester.tap(find.byKey(AdmissionDialog.submitKey));
    await tester.pumpAndSettle();

    expect(wire.approvals.single['employeeId'], '41');
  });

  // Issue #129 (ADR-0023): the picker's search box is `AppSearchField`, no
  // Search button remains, and a pick reports the Employee to the
  // surrounding form (here, `AdmissionDialog`) and closes the suggestion
  // list, without navigating anywhere.

  testWidgets('typing 2+ characters shows matching Employees with name, job role and Org Unit',
      (tester) async {
    final wire = FakeWire(
      queue: [pendingJson('7', 'first@b.c', _twoDaysAgo)],
      employees: [
        employeeJson(
          '41',
          'EMP-41',
          'Alex Rios',
          orgUnit: {'id': '10', 'name': 'Assembly'},
          jobRole: {'id': '5', 'name': 'Welder'},
        ),
      ],
    );
    await _openDecision(tester, wire);

    // Below the 2-character minimum: no suggestion renders at all.
    await tester.enterText(find.byKey(EmployeeLinkPicker.searchFieldKey), 'a');
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byKey(EmployeeLinkPicker.resultKey('41')), findsNothing);

    await tester.enterText(find.byKey(EmployeeLinkPicker.searchFieldKey), 'alex');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(find.byKey(EmployeeLinkPicker.resultKey('41')), findsOneWidget);
    expect(find.text('EMP-41 · Alex Rios'), findsOneWidget);
    expect(find.text('Welder · Assembly'), findsOneWidget);
  });

  testWidgets('picking a suggestion reports the Employee to the surrounding form and closes the '
      'suggestion list, without navigating', (tester) async {
    final wire = FakeWire(
      queue: [pendingJson('7', 'first@b.c', _twoDaysAgo)],
      employees: [employeeJson('41', 'EMP-41', 'Alex Rios')],
    );
    await _openDecision(tester, wire);

    await tester.enterText(find.byKey(EmployeeLinkPicker.searchFieldKey), 'alex');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    expect(find.byKey(EmployeeLinkPicker.resultKey('41')), findsOneWidget);

    await tapIn(tester, find.byKey(EmployeeLinkPicker.resultKey('41')));

    // Reported to the surrounding form: the confirmation line above the
    // search box now names the pick.
    expect(find.text('Linked to: EMP-41 · Alex Rios'), findsOneWidget);
    // The suggestion list is gone.
    expect(find.byKey(EmployeeLinkPicker.resultKey('41')), findsNothing);
    // Nothing navigational happened — still the same dialog, still the
    // Approval queue underneath it.
    expect(find.byType(AdmissionDialog), findsOneWidget);
    expect(find.text('Admit this Account'), findsOneWidget);
  });

  testWidgets('the suggestion fetch carries the limit parameter', (tester) async {
    final wire = FakeWire(
      queue: [pendingJson('7', 'first@b.c', _twoDaysAgo)],
      employees: [employeeJson('41', 'EMP-41', 'Alex Rios')],
    );
    await _openDecision(tester, wire);

    await tester.enterText(find.byKey(EmployeeLinkPicker.searchFieldKey), 'alex');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(wire.employeeRequests.last['search'], 'alex');
    expect(wire.employeeRequests.last['limit'], '10');
  });

  testWidgets('approving with no Employee at all sends no employeeId — the head-office and '
      'integration Accounts are ordinary, not errors', (tester) async {
    final wire = FakeWire(
      queue: [
        pendingJson(
          '7',
          'first@b.c',
          _twoDaysAgo,
          suggestedEmployee: suggestedEmployeeJson('40', 'EMP-40', 'Jane Doe'),
        ),
      ],
    );
    await _openDecision(tester, wire);

    await tapIn(tester, find.byKey(EmployeeLinkPicker.clearKey));
    expect(find.text('No Employee will be linked.'), findsOneWidget);

    await chooseRole(tester, Roles.operator);
    await tester.tap(find.byKey(AdmissionDialog.submitKey));
    await tester.pumpAndSettle();

    expect(wire.approvals.single.containsKey('employeeId'), isFalse);
    expect(find.textContaining('Admitted to the Platform as operator'), findsOneWidget);
  });

  testWidgets('a pending Account with no suggestion renders the search, not an empty slot or a '
      'warning', (tester) async {
    final wire = _oneWaiting();
    await _openDecision(tester, wire);

    expect(find.byKey(EmployeeLinkPicker.searchFieldKey), findsOneWidget);
    expect(find.text('No Employee will be linked.'), findsOneWidget);

    await chooseRole(tester, Roles.admin);
    await tester.tap(find.byKey(AdmissionDialog.submitKey));
    await tester.pumpAndSettle();

    expect(wire.approvals.single.containsKey('employeeId'), isFalse);
  });

  // Each of the three Approval refusals from #115 surfaces its own message,
  // not the generic "someone else already dealt with it" 409 — even though
  // two of the three share that status code. Which of the two 409s this is
  // (issue #119) is driven by the server's own `code`, not by matching either
  // message's wording — see the two tests below that keep the production
  // message but swap in an unrelated one to prove the branch follows `code`.

  testWidgets('an employeeId naming no Employee at all (404) surfaces its own message',
      (tester) async {
    final wire = FakeWire(
      queue: [
        pendingJson(
          '7',
          'first@b.c',
          _twoDaysAgo,
          suggestedEmployee: suggestedEmployeeJson('40', 'EMP-40', 'Jane Doe'),
        ),
      ],
      approveStatus: 404,
      approveMessage: 'employeeId does not name an existing Employee',
    )..approveCode = 'EMPLOYEE_NOT_FOUND';
    await _openDecision(tester, wire);
    await chooseRole(tester, Roles.operator);

    await tester.tap(find.byKey(AdmissionDialog.submitKey));
    await tester.pumpAndSettle();

    expect(find.text('Admit this Account'), findsOneWidget);
    expect(find.text('employeeId does not name an existing Employee'), findsWidgets);
  });

  testWidgets('an employeeId naming a Departed Employee (409) surfaces its own message, not the '
      'generic already-dealt-with notice', (tester) async {
    final wire = FakeWire(
      queue: [
        pendingJson(
          '7',
          'first@b.c',
          _twoDaysAgo,
          suggestedEmployee: suggestedEmployeeJson('40', 'EMP-40', 'Jane Doe'),
        ),
      ],
      approveStatus: 409,
      approveMessage: 'This Employee has Departed and cannot be linked to an Account',
    )..approveCode = 'EMPLOYEE_DEPARTED';
    await _openDecision(tester, wire);
    await chooseRole(tester, Roles.operator);

    await tester.tap(find.byKey(AdmissionDialog.submitKey));
    await tester.pumpAndSettle();

    expect(find.text('Admit this Account'), findsOneWidget);
    expect(find.text('This Employee has Departed and cannot be linked to an Account'), findsWidgets);
    expect(find.textContaining('Another administrator has already dealt with'), findsNothing);
  });

  testWidgets('an employeeId already linked to a different Account (409) surfaces its own '
      'message, not the generic already-dealt-with notice', (tester) async {
    final wire = FakeWire(
      queue: [
        pendingJson(
          '7',
          'first@b.c',
          _twoDaysAgo,
          suggestedEmployee: suggestedEmployeeJson('40', 'EMP-40', 'Jane Doe'),
        ),
      ],
      approveStatus: 409,
      approveMessage: 'This Employee is already linked to a different Account',
    )..approveCode = 'EMPLOYEE_ALREADY_LINKED';
    await _openDecision(tester, wire);
    await chooseRole(tester, Roles.operator);

    await tester.tap(find.byKey(AdmissionDialog.submitKey));
    await tester.pumpAndSettle();

    expect(find.text('Admit this Account'), findsOneWidget);
    expect(find.text('This Employee is already linked to a different Account'), findsWidgets);
    expect(find.textContaining('Another administrator has already dealt with'), findsNothing);
  });

  // The branch is driven by `code`, not by matching either refusal's wording
  // (issue #119) — these two swap in a message that names neither Employee
  // refusal and neither the precondition's own wording, and shows the code
  // alone still routes correctly: an Employee-link code keeps the dialog open
  // with that message, and a 409 carrying no code at all (a caller older than
  // this issue, or a refusal that never opted in) still falls back to "someone
  // else already dealt with it", the same default it had before any code
  // existed.

  testWidgets('a 409 carrying EMPLOYEE_ALREADY_LINKED keeps the dialog open with an arbitrary '
      'message — the code decides, not the wording', (tester) async {
    final wire = FakeWire(
      queue: [pendingJson('7', 'first@b.c', _twoDaysAgo)],
      approveStatus: 409,
      approveMessage: 'Something unrelated to either refusal',
    )..approveCode = 'EMPLOYEE_ALREADY_LINKED';
    await _openDecision(tester, wire);
    await chooseRole(tester, Roles.operator);

    await tester.tap(find.byKey(AdmissionDialog.submitKey));
    await tester.pumpAndSettle();

    expect(find.text('Admit this Account'), findsOneWidget);
    expect(find.text('Something unrelated to either refusal'), findsWidgets);
    expect(find.textContaining('Another administrator has already dealt with'), findsNothing);
  });

  testWidgets('a 409 carrying no code at all still falls back to the generic already-dealt-with '
      'notice and refreshes the queue', (tester) async {
    final wire = FakeWire(
      queue: [pendingJson('7', 'first@b.c', _twoDaysAgo)],
      approveStatus: 409,
      approveMessage: 'This Employee has Departed and cannot be linked to an Account',
    );
    await _openDecision(tester, wire);
    await chooseRole(tester, Roles.operator);

    wire.queue = [];

    await tester.tap(find.byKey(AdmissionDialog.submitKey));
    await tester.pumpAndSettle();

    expect(find.text('Admit this Account'), findsNothing);
    expect(find.textContaining('Another administrator has already dealt with'), findsOneWidget);
  });
}
