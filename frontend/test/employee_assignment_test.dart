/// Assigning an Employee to an Org Unit, and transferring one who already
/// holds an open Assignment (issue #88), with the wire faked — the one client
/// seam (ADR-0012). The real app, the real router, the real Blocs,
/// `MockClient` at the HTTP boundary and `FakeAuthGateway` at the auth
/// boundary.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/people/directory_screen.dart';
import 'package:lean_platform/people/employee_assignment_dialog.dart';
import 'package:lean_platform/people/employee_detail_screen.dart';
import 'package:lean_platform/platform/destinations.dart';

import 'harness.dart';

Future<void> openDirectory(WidgetTester tester, FakeWire wire, {String location = '/directory'}) =>
    pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: location,
    );

/// One Site, and two Lines directly at its root — enough for the destination
/// picker to render without any expansion.
FakeWire _plant({
  String role = Roles.admin,
  Map<String, dynamic>? orgUnitScope,
  List<Map<String, dynamic>> employees = const [],
  Map<String, Map<String, dynamic>> employeeDetails = const {},
  int createAssignmentStatus = 201,
  String createAssignmentMessage = 'That Assignment could not be recorded.',
}) =>
    FakeWire(
      role: role,
      orgUnitScope: orgUnitScope,
      employees: employees,
      employeeDetails: employeeDetails,
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [orgUnitJson('10', 'Line 1'), orgUnitJson('11', 'Line 2')],
      },
      jobRoles: [jobRoleJson('20', 'WELD', 'Welder')],
      createAssignmentStatus: createAssignmentStatus,
      createAssignmentMessage: createAssignmentMessage,
    );

Future<void> _chooseJobRole(WidgetTester tester, String name) async {
  await tapIn(tester, find.byKey(EmployeeAssignmentDialog.jobRoleKey));
  await tapIn(tester, find.text(name).last);
}

void main() {
  testWidgets(
      'assigning sends one request carrying orgUnitId, jobRoleId and effectiveFrom, and the '
      'Assignment shows as current afterwards', (tester) async {
    final wire = _plant(
      employees: [employeeJson('7', 'E-7', 'Alice Nguyen')],
      employeeDetails: {'7': employeeDetailJson('7', 'E-7', 'Alice Nguyen')},
    );
    await openDirectory(tester, wire);
    await tapIn(tester, find.byKey(DirectoryScreen.rowKey('7')));

    await tapIn(tester, find.byKey(EmployeeDetailScreen.assignKey));
    expect(find.byType(EmployeeAssignmentDialog), findsOneWidget);

    await tapIn(tester, find.byKey(EmployeeAssignmentDialog.orgUnitKey('10')));
    await _chooseJobRole(tester, 'Welder');
    await tester.enterText(find.byKey(EmployeeAssignmentDialog.effectiveFromKey), '2024-08-01');
    await tapIn(tester, find.byKey(EmployeeAssignmentDialog.submitKey));

    expect(wire.assignmentPosts.single.$1, '7');
    expect(wire.assignmentPosts.single.$2, {
      'orgUnitId': '10',
      'jobRoleId': '20',
      'effectiveFrom': '2024-08-01',
    });
    expect(find.byType(EmployeeAssignmentDialog), findsNothing);

    // The Employee's own record was re-read (not the create response
    // spliced in), and the freshly recorded Assignment reads as current.
    expect(find.byKey(EmployeeDetailScreen.assignmentRowKey('500')), findsOneWidget);
    expect(find.byKey(EmployeeDetailScreen.currentAssignmentKey('500')), findsOneWidget);
  });

  testWidgets('a transfer leaves the previous Assignment visible as past, with its end date',
      (tester) async {
    final wire = _plant(
      employees: [employeeJson('7', 'E-7', 'Alice Nguyen')],
      employeeDetails: {
        '7': employeeDetailJson(
          '7',
          'E-7',
          'Alice Nguyen',
          assignments: [
            employeeAssignmentJson(
              '99',
              orgUnitId: '10',
              orgUnitName: 'Line 1',
              isCurrent: true,
              effectiveFrom: '2024-01-01',
            ),
          ],
        ),
      },
    );
    await openDirectory(tester, wire);
    await tapIn(tester, find.byKey(DirectoryScreen.rowKey('7')));

    // Before the transfer: one Assignment, current, open-ended.
    expect(find.byKey(EmployeeDetailScreen.currentAssignmentKey('99')), findsOneWidget);

    await tapIn(tester, find.byKey(EmployeeDetailScreen.assignKey));
    await tapIn(tester, find.byKey(EmployeeAssignmentDialog.orgUnitKey('11')));
    await tester.enterText(find.byKey(EmployeeAssignmentDialog.effectiveFromKey), '2024-08-01');
    await tapIn(tester, find.byKey(EmployeeAssignmentDialog.submitKey));

    // The new Assignment reads as current…
    expect(find.byKey(EmployeeDetailScreen.assignmentRowKey('500')), findsOneWidget);
    expect(find.byKey(EmployeeDetailScreen.currentAssignmentKey('500')), findsOneWidget);
    // …and the previous one is still on screen, now past, with its own end
    // date — never edited away, per CONTEXT.md's own Assignment entry.
    expect(find.byKey(EmployeeDetailScreen.assignmentRowKey('99')), findsOneWidget);
    expect(find.byKey(EmployeeDetailScreen.currentAssignmentKey('99')), findsNothing);
    expect(find.text('2024-01-01 – 2024-08-01'), findsOneWidget);
  });

  testWidgets('a refusal for want of write scope on the destination shows the API\'s own message',
      (tester) async {
    final wire = _plant(
      employees: [employeeJson('7', 'E-7', 'Alice Nguyen')],
      employeeDetails: {'7': employeeDetailJson('7', 'E-7', 'Alice Nguyen')},
      createAssignmentStatus: 403,
      createAssignmentMessage: "Outside the caller's granted Org Units",
    );
    await openDirectory(tester, wire);
    await tapIn(tester, find.byKey(DirectoryScreen.rowKey('7')));
    await tapIn(tester, find.byKey(EmployeeDetailScreen.assignKey));

    await tapIn(tester, find.byKey(EmployeeAssignmentDialog.orgUnitKey('10')));
    await tester.enterText(find.byKey(EmployeeAssignmentDialog.effectiveFromKey), '2024-08-01');
    await tapIn(tester, find.byKey(EmployeeAssignmentDialog.submitKey));

    // The dialog stays open, and shows the scope refusal verbatim — not a
    // generic "that failed".
    expect(find.byType(EmployeeAssignmentDialog), findsOneWidget);
    expect(find.byKey(EmployeeAssignmentDialog.failureKey), findsOneWidget);
    expect(find.text("Outside the caller's granted Org Units"), findsOneWidget);
  });

  testWidgets('an overlapping or backdated Assignment (409) surfaces against the form',
      (tester) async {
    final wire = _plant(
      employees: [employeeJson('7', 'E-7', 'Alice Nguyen')],
      employeeDetails: {'7': employeeDetailJson('7', 'E-7', 'Alice Nguyen')},
      createAssignmentStatus: 409,
      createAssignmentMessage: 'overlaps an existing assignment for this Employee',
    );
    await openDirectory(tester, wire);
    await tapIn(tester, find.byKey(DirectoryScreen.rowKey('7')));
    await tapIn(tester, find.byKey(EmployeeDetailScreen.assignKey));

    await tapIn(tester, find.byKey(EmployeeAssignmentDialog.orgUnitKey('10')));
    await tester.enterText(find.byKey(EmployeeAssignmentDialog.effectiveFromKey), '2024-01-01');
    await tapIn(tester, find.byKey(EmployeeAssignmentDialog.submitKey));

    expect(find.byType(EmployeeAssignmentDialog), findsOneWidget);
    expect(find.byKey(EmployeeAssignmentDialog.failureKey), findsOneWidget);
    expect(find.text('overlaps an existing assignment for this Employee'), findsOneWidget);
  });

  testWidgets('a Departed Employee is not offered the assign action', (tester) async {
    final wire = _plant(
      employees: [employeeJson('8', 'E-8', 'Bao Tran', isActive: false)],
      employeeDetails: {'8': employeeDetailJson('8', 'E-8', 'Bao Tran', isActive: false)},
    );
    await openDirectory(tester, wire);
    await tapIn(tester, find.byKey(DirectoryScreen.includeDepartedKey));
    await tapIn(tester, find.byKey(DirectoryScreen.rowKey('8')));

    expect(find.byKey(EmployeeDetailScreen.departedKey), findsOneWidget);
    expect(find.byKey(EmployeeDetailScreen.assignKey), findsNothing);
  });

  testWidgets(
      'an Account holding a write Grant but not the administrator role is offered the assign '
      'action (ADR-0010)', (tester) async {
    final wire = _plant(
      role: Roles.supervisor,
      orgUnitScope: {
        'everywhere': false,
        'grants': [scopeGrantJson('10', canWrite: true)],
      },
      employees: [employeeJson('7', 'E-7', 'Alice Nguyen')],
      employeeDetails: {'7': employeeDetailJson('7', 'E-7', 'Alice Nguyen')},
    );
    await openDirectory(tester, wire);
    await tapIn(tester, find.byKey(DirectoryScreen.rowKey('7')));

    // Offered despite holding no administrator role at all — this is
    // ADR-0010's whole point: write scope on the destination, not a role.
    expect(find.byKey(EmployeeDetailScreen.assignKey), findsOneWidget);
    // The administrator-only actions stay hidden, same as before issue #88.
    expect(find.byKey(EmployeeDetailScreen.correctKey), findsNothing);
    expect(find.byKey(EmployeeDetailScreen.departKey), findsNothing);

    await tapIn(tester, find.byKey(EmployeeDetailScreen.assignKey));
    await tapIn(tester, find.byKey(EmployeeAssignmentDialog.orgUnitKey('10')));
    await tester.enterText(find.byKey(EmployeeAssignmentDialog.effectiveFromKey), '2024-08-01');
    await tapIn(tester, find.byKey(EmployeeAssignmentDialog.submitKey));

    expect(wire.assignmentPosts.single.$1, '7');
    expect(find.byType(EmployeeAssignmentDialog), findsNothing);
  });
}
