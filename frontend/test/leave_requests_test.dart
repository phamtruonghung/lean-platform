/// Leave requests (issue #265): the caller's own list, asking for leave with
/// every value chosen, the "To decide" view and the decisions, cancelling, and
/// how a refusal reads — with the one client seam faked (ADR-0012).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/people/leave_request_cancel_dialog.dart';
import 'package:lean_platform/people/leave_request_decision_dialog.dart';
import 'package:lean_platform/people/leave_request_form_dialog.dart';
import 'package:lean_platform/people/leave_requests_screen.dart';
import 'package:lean_platform/platform/destinations.dart';
import 'package:lean_platform/widgets/app_date_field.dart';

import 'harness.dart';

final _editGrantScope = {
  'everywhere': false,
  'grants': [scopeGrantJson('10', canWrite: true)],
};

final _readGrantScope = {
  'everywhere': false,
  'grants': [scopeGrantJson('10')],
};

List<Map<String, dynamic>> _leaveTypes() => [
      absenceReasonJson('HOL', 'Annual leave', isRequestable: true),
      absenceReasonJson('UNP', 'Unpaid leave', isRequestable: true),
      absenceReasonJson('SICK', 'Sickness'),
    ];

Future<void> openLeaveRequests(WidgetTester tester, FakeWire wire, {String location = '/leave-requests'}) =>
    pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: location,
    );

String _today() {
  final now = DateTime.now();
  String pad(int n, int width) => n.toString().padLeft(width, '0');
  return '${pad(now.year, 4)}-${pad(now.month, 2)}-${pad(now.day, 2)}';
}

void main() {
  testWidgets('lists the caller\'s own requests, each with its status and period', (tester) async {
    final wire = FakeWire(
      role: Roles.operator,
      orgUnitScope: _readGrantScope,
      absenceReasons: _leaveTypes(),
      leaveRequestsMine: [
        leaveRequestJson('1', note: 'Family trip', canCancel: true),
        leaveRequestJson('2', status: 'rejected', decisionNote: 'Peak season'),
      ],
    );
    await openLeaveRequests(tester, wire);

    expect(find.byKey(LeaveRequestsScreen.rowKey('1')), findsOneWidget);
    expect(find.byKey(LeaveRequestsScreen.rowKey('2')), findsOneWidget);
    expect(find.text('Ada Lovelace · Annual leave'), findsNWidgets(2));
    expect(find.text('2026-06-01 to 2026-06-03 · 3 days'), findsNWidgets(2));
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Rejected'), findsOneWidget);
    expect(find.text('Note: Family trip'), findsOneWidget);
    expect(find.text('Decision note: Peak season'), findsOneWidget);
    expect(wire.leaveRequestReads.first['view'], 'mine');
  });

  testWidgets('an empty list says so and offers to request leave', (tester) async {
    final wire = FakeWire(role: Roles.operator, absenceReasons: _leaveTypes());
    await openLeaveRequests(tester, wire);

    expect(find.byKey(LeaveRequestsScreen.emptyKey), findsOneWidget);
    expect(find.byKey(LeaveRequestsScreen.emptyRequestKey), findsOneWidget);
  });

  testWidgets('a failed read shows the failure with a retry', (tester) async {
    final wire = FakeWire(role: Roles.operator, leaveRequestsStatus: 500);
    await openLeaveRequests(tester, wire);

    expect(find.byKey(LeaveRequestsScreen.failedKey), findsOneWidget);
    expect(find.byKey(LeaveRequestsScreen.retryKey), findsOneWidget);
  });

  testWidgets('asking for leave sends the chosen type, dates and note, then refreshes the list',
      (tester) async {
    final wire = FakeWire(role: Roles.operator, absenceReasons: _leaveTypes());
    await openLeaveRequests(tester, wire);
    final readsBefore = wire.leaveRequestReads.length;

    await tapIn(tester, find.byKey(LeaveRequestsScreen.requestKey));
    expect(find.byKey(LeaveRequestFormDialog.typeFieldKey), findsOneWidget);
    // Only the requestable absence reasons are offered, and they were asked
    // for by the server's own filter.
    expect(wire.absenceReasonRequests.first['requestable'], 'true');

    await tapIn(tester, find.byKey(LeaveRequestFormDialog.typeFieldKey));
    expect(find.text('Sickness'), findsNothing);
    await tapIn(tester, find.text('Unpaid leave').last);

    // Submit stays shut until both days are chosen.
    expect(tester.widget<FilledButton>(find.byKey(LeaveRequestFormDialog.submitKey)).onPressed, isNull);
    await tapIn(tester, find.byKey(AppDateField.fieldKey(LeaveRequestFormDialog.startsOnName)));
    await tapIn(tester, find.text('OK'));
    await tapIn(tester, find.byKey(AppDateField.fieldKey(LeaveRequestFormDialog.endsOnName)));
    await tapIn(tester, find.text('OK'));
    await tester.enterText(find.byKey(LeaveRequestFormDialog.noteKey), 'Moving house');
    await tapIn(tester, find.byKey(LeaveRequestFormDialog.submitKey));

    final today = _today();
    expect(wire.leaveRequestWrites.single.$1, '/api/people/leave-requests');
    expect(wire.leaveRequestWrites.single.$2, {
      'absenceReasonId': 'UNP',
      'startsOn': today,
      'endsOn': today,
      'note': 'Moving house',
    });
    // The dialog closed and the list was read again, now holding the new row.
    expect(find.byKey(LeaveRequestFormDialog.submitKey), findsNothing);
    expect(wire.leaveRequestReads.length, greaterThan(readsBefore));
    expect(find.byKey(LeaveRequestsScreen.rowKey('new-1')), findsOneWidget);
  });

  testWidgets('a leave type list that cannot be read blocks submission', (tester) async {
    final wire = FakeWire(role: Roles.operator, absenceReasonsStatus: 500);
    await openLeaveRequests(tester, wire);

    await tapIn(tester, find.byKey(LeaveRequestsScreen.emptyRequestKey));

    expect(find.byKey(LeaveRequestFormDialog.typesFailedKey), findsOneWidget);
    expect(find.byKey(LeaveRequestFormDialog.typeFieldKey), findsNothing);
    expect(tester.widget<FilledButton>(find.byKey(LeaveRequestFormDialog.submitKey)).onPressed, isNull);
    expect(wire.leaveRequestWrites, isEmpty);
  });

  testWidgets('a refused request shows the server message and keeps the dialog open', (tester) async {
    final wire = FakeWire(
      role: Roles.operator,
      absenceReasons: _leaveTypes(),
      leaveRequestWriteStatus: 409,
      leaveRequestWriteMessage: 'You already have leave on those days.',
    );
    await openLeaveRequests(tester, wire);

    await tapIn(tester, find.byKey(LeaveRequestsScreen.requestKey));
    await tapIn(tester, find.byKey(LeaveRequestFormDialog.typeFieldKey));
    await tapIn(tester, find.text('Annual leave').last);
    await tapIn(tester, find.byKey(AppDateField.fieldKey(LeaveRequestFormDialog.startsOnName)));
    await tapIn(tester, find.text('OK'));
    await tapIn(tester, find.byKey(AppDateField.fieldKey(LeaveRequestFormDialog.endsOnName)));
    await tapIn(tester, find.text('OK'));
    await tapIn(tester, find.byKey(LeaveRequestFormDialog.submitKey));

    expect(find.text('You already have leave on those days.'), findsOneWidget);
    expect(find.byKey(LeaveRequestFormDialog.submitKey), findsOneWidget);
  });

  testWidgets('To decide is hidden for an Account with no edit Grant', (tester) async {
    final wire = FakeWire(role: Roles.operator, orgUnitScope: _readGrantScope);
    await openLeaveRequests(tester, wire);

    expect(find.byKey(LeaveRequestsScreen.viewToDecideKey), findsNothing);
    expect(find.byKey(LeaveRequestsScreen.viewMineKey), findsNothing);
  });

  testWidgets('To decide is shown for an Account holding an edit Grant, and reads that view',
      (tester) async {
    final wire = FakeWire(
      role: Roles.supervisor,
      orgUnitScope: _editGrantScope,
      leaveRequestsToDecide: [leaveRequestJson('5', employeeName: 'Grace Hopper', canDecide: true)],
    );
    await openLeaveRequests(tester, wire);

    await tapIn(tester, find.byKey(LeaveRequestsScreen.viewToDecideKey));

    expect(wire.leaveRequestReads.last['view'], 'to-decide');
    expect(find.byKey(LeaveRequestsScreen.rowKey('5')), findsOneWidget);
    expect(find.text('Grace Hopper · Annual leave'), findsOneWidget);
  });

  testWidgets('approving sends the note to the approve route and refreshes', (tester) async {
    final wire = FakeWire(
      role: Roles.supervisor,
      orgUnitScope: _editGrantScope,
      leaveRequestsToDecide: [leaveRequestJson('5', canDecide: true)],
    );
    await openLeaveRequests(tester, wire);
    await tapIn(tester, find.byKey(LeaveRequestsScreen.viewToDecideKey));

    await tapIn(tester, find.byKey(LeaveRequestsScreen.approveKey('5')));
    await tester.enterText(find.byKey(LeaveRequestDecisionDialog.noteKey), 'Enjoy');
    await tapIn(tester, find.byKey(LeaveRequestDecisionDialog.submitKey));

    expect(wire.leaveRequestWrites.single.$1, '/api/people/leave-requests/5/approve');
    expect(wire.leaveRequestWrites.single.$2, {'note': 'Enjoy'});
    expect(find.byKey(LeaveRequestDecisionDialog.submitKey), findsNothing);
    // Decided, so it has left the To decide list.
    expect(find.byKey(LeaveRequestsScreen.rowKey('5')), findsNothing);
  });

  testWidgets('rejecting sends the note to the reject route', (tester) async {
    final wire = FakeWire(
      role: Roles.supervisor,
      orgUnitScope: _editGrantScope,
      leaveRequestsToDecide: [leaveRequestJson('5', canDecide: true)],
    );
    await openLeaveRequests(tester, wire);
    await tapIn(tester, find.byKey(LeaveRequestsScreen.viewToDecideKey));

    await tapIn(tester, find.byKey(LeaveRequestsScreen.rejectKey('5')));
    await tester.enterText(find.byKey(LeaveRequestDecisionDialog.noteKey), 'Peak season');
    await tapIn(tester, find.byKey(LeaveRequestDecisionDialog.submitKey));

    expect(wire.leaveRequestWrites.single.$1, '/api/people/leave-requests/5/reject');
    expect(wire.leaveRequestWrites.single.$2, {'note': 'Peak season'});
  });

  testWidgets('a decision with no note sends none', (tester) async {
    final wire = FakeWire(
      role: Roles.supervisor,
      orgUnitScope: _editGrantScope,
      leaveRequestsToDecide: [leaveRequestJson('5', canDecide: true)],
    );
    await openLeaveRequests(tester, wire);
    await tapIn(tester, find.byKey(LeaveRequestsScreen.viewToDecideKey));

    await tapIn(tester, find.byKey(LeaveRequestsScreen.approveKey('5')));
    await tapIn(tester, find.byKey(LeaveRequestDecisionDialog.submitKey));

    expect(wire.leaveRequestWrites.single.$2, isEmpty);
  });

  testWidgets('a refused decision shows the server message', (tester) async {
    final wire = FakeWire(
      role: Roles.supervisor,
      orgUnitScope: _editGrantScope,
      leaveRequestsToDecide: [leaveRequestJson('5', canDecide: true)],
      leaveRequestWriteStatus: 409,
      leaveRequestWriteMessage: 'Someone already decided this request.',
    );
    await openLeaveRequests(tester, wire);
    await tapIn(tester, find.byKey(LeaveRequestsScreen.viewToDecideKey));

    await tapIn(tester, find.byKey(LeaveRequestsScreen.approveKey('5')));
    await tapIn(tester, find.byKey(LeaveRequestDecisionDialog.submitKey));

    expect(find.text('Someone already decided this request.'), findsOneWidget);
    expect(find.byKey(LeaveRequestDecisionDialog.submitKey), findsOneWidget);
  });

  testWidgets('cancelling asks to confirm, then posts to the cancel route', (tester) async {
    final wire = FakeWire(
      role: Roles.operator,
      leaveRequestsMine: [leaveRequestJson('1', canCancel: true)],
    );
    await openLeaveRequests(tester, wire);

    await tapIn(tester, find.byKey(LeaveRequestsScreen.cancelKey('1')));
    expect(wire.leaveRequestWrites, isEmpty);
    await tapIn(tester, find.byKey(LeaveRequestCancelDialog.submitKey));

    expect(wire.leaveRequestWrites.single.$1, '/api/people/leave-requests/1/cancel');
    expect(find.text('Cancelled'), findsOneWidget);
    expect(find.byKey(LeaveRequestsScreen.cancelKey('1')), findsNothing);
  });

  testWidgets('keeping the request sends nothing', (tester) async {
    final wire = FakeWire(
      role: Roles.operator,
      leaveRequestsMine: [leaveRequestJson('1', canCancel: true)],
    );
    await openLeaveRequests(tester, wire);

    await tapIn(tester, find.byKey(LeaveRequestsScreen.cancelKey('1')));
    await tapIn(tester, find.byKey(LeaveRequestCancelDialog.backKey));

    expect(wire.leaveRequestWrites, isEmpty);
    expect(find.byKey(LeaveRequestsScreen.rowKey('1')), findsOneWidget);
  });

  testWidgets('Approve, Reject and Cancel request appear only where the server allows them',
      (tester) async {
    final wire = FakeWire(
      role: Roles.supervisor,
      orgUnitScope: _editGrantScope,
      leaveRequestsMine: [
        leaveRequestJson('1'),
        leaveRequestJson('2', canCancel: true),
        leaveRequestJson('3', canDecide: true),
      ],
    );
    await openLeaveRequests(tester, wire);

    expect(find.byKey(LeaveRequestsScreen.approveKey('1')), findsNothing);
    expect(find.byKey(LeaveRequestsScreen.rejectKey('1')), findsNothing);
    expect(find.byKey(LeaveRequestsScreen.cancelKey('1')), findsNothing);
    expect(find.byKey(LeaveRequestsScreen.cancelKey('2')), findsOneWidget);
    expect(find.byKey(LeaveRequestsScreen.approveKey('2')), findsNothing);
    expect(find.byKey(LeaveRequestsScreen.approveKey('3')), findsOneWidget);
    expect(find.byKey(LeaveRequestsScreen.rejectKey('3')), findsOneWidget);
    expect(find.byKey(LeaveRequestsScreen.cancelKey('3')), findsNothing);
  });

  testWidgets('a decision address opened directly finds its request in To decide', (tester) async {
    final wire = FakeWire(
      role: Roles.supervisor,
      orgUnitScope: _editGrantScope,
      leaveRequestsToDecide: [leaveRequestJson('5', canDecide: true)],
    );
    await openLeaveRequests(tester, wire, location: '/leave-requests/5/approve');

    expect(find.byKey(LeaveRequestDecisionDialog.submitKey), findsOneWidget);
    expect(find.byKey(LeaveRequestDecisionDialog.notFoundKey), findsNothing);
  });

  testWidgets('the sidebar offers Leave requests to every active Account', (tester) async {
    final wire = FakeWire(role: Roles.operator);
    await openLeaveRequests(tester, wire);

    expect(find.text('Leave requests'), findsWidgets);
  });
}
