/// The Employee directory (issue #86), with the wire faked — the one client
/// seam (ADR-0012). The real app, the real router, the real Blocs,
/// `MockClient` at the HTTP boundary and `FakeAuthGateway` at the auth
/// boundary.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/people/directory_org_unit_filter_dialog.dart';
import 'package:lean_platform/people/directory_screen.dart';
import 'package:lean_platform/people/employee_detail_screen.dart';
import 'package:lean_platform/platform/access_denied_screen.dart';
import 'package:lean_platform/platform/destinations.dart';
import 'package:lean_platform/platform/shell.dart';

import 'harness.dart';

Future<void> openDirectory(WidgetTester tester, FakeWire wire, {String location = '/directory'}) =>
    pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: location,
    );

void main() {
  testWidgets('the Directory renders the Employees it is given, Departed excluded by default',
      (tester) async {
    final wire = FakeWire(
      employees: [
        employeeJson('7', 'E-7', 'Alice Nguyen'),
        employeeJson('8', 'E-8', 'Bao Tran', isActive: false),
      ],
    );
    await openDirectory(tester, wire);

    expect(find.byType(DirectoryScreen), findsOneWidget);
    expect(find.text('Alice Nguyen'), findsOneWidget);
    expect(find.byKey(DirectoryScreen.rowKey('7')), findsOneWidget);
    // Departed by default: excluded, not silently mixed in.
    expect(find.text('Bao Tran'), findsNothing);
  });

  testWidgets('searching narrows the list and sends exactly one request carrying "search"',
      (tester) async {
    final wire = FakeWire(
      employees: [
        employeeJson('7', 'E-7', 'Alice Nguyen'),
        employeeJson('8', 'E-8', 'Bob Le'),
      ],
    );
    await openDirectory(tester, wire);

    expect(find.text('Alice Nguyen'), findsOneWidget);
    expect(find.text('Bob Le'), findsOneWidget);

    await tester.enterText(find.byKey(DirectoryScreen.searchFieldKey), 'Alice');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text('Alice Nguyen'), findsOneWidget);
    expect(find.text('Bob Le'), findsNothing);
    expect(wire.employeeRequests.where((r) => r['search'] == 'Alice').length, 1);
  });

  testWidgets('the Org Unit filter sends orgUnitId, chosen by browsing the tree', (tester) async {
    final wire = FakeWire(
      employees: [employeeJson('7', 'E-7', 'Alice Nguyen')],
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [orgUnitJson('10', 'Assembly')],
      },
    );
    await openDirectory(tester, wire);

    await tapIn(tester, find.byKey(DirectoryScreen.orgUnitFilterKey));
    expect(find.byKey(DirectoryOrgUnitFilterDialog.rowKey('10')), findsOneWidget);
    await tapIn(tester, find.byKey(DirectoryOrgUnitFilterDialog.rowKey('10')));

    expect(find.byType(DirectoryOrgUnitFilterDialog), findsNothing);
    expect(wire.employeeRequests.last['orgUnitId'], '10');
    expect(find.text('Assembly'), findsOneWidget);
  });

  testWidgets('clearing the Org Unit filter sends no orgUnitId', (tester) async {
    final wire = FakeWire(
      employees: [employeeJson('7', 'E-7', 'Alice Nguyen')],
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [orgUnitJson('10', 'Assembly')],
      },
    );
    await openDirectory(tester, wire);

    await tapIn(tester, find.byKey(DirectoryScreen.orgUnitFilterKey));
    await tapIn(tester, find.byKey(DirectoryOrgUnitFilterDialog.rowKey('10')));
    expect(wire.employeeRequests.last['orgUnitId'], '10');

    await tapIn(tester, find.byKey(DirectoryScreen.orgUnitFilterKey));
    await tapIn(tester, find.byKey(DirectoryOrgUnitFilterDialog.allOrgUnitsKey));

    expect(wire.employeeRequests.last['orgUnitId'], isNull);
    expect(find.text('All Org Units'), findsOneWidget);
  });

  testWidgets('the job role filter sends jobRoleId', (tester) async {
    final wire = FakeWire(
      employees: [employeeJson('7', 'E-7', 'Alice Nguyen')],
      jobRoles: [jobRoleJson('20', 'WELD', 'Welder')],
    );
    await openDirectory(tester, wire);

    await tapIn(tester, find.byKey(DirectoryScreen.jobRoleFilterKey));
    await tapIn(tester, find.text('Welder').last);

    expect(wire.employeeRequests.last['jobRoleId'], '20');
  });

  testWidgets('the departed toggle sends includeDeparted=true and reveals the Departed row',
      (tester) async {
    final wire = FakeWire(
      employees: [
        employeeJson('7', 'E-7', 'Alice Nguyen'),
        employeeJson('8', 'E-8', 'Bao Tran', isActive: false),
      ],
    );
    await openDirectory(tester, wire);

    expect(find.text('Bao Tran'), findsNothing);

    await tapIn(tester, find.byKey(DirectoryScreen.includeDepartedKey));

    expect(wire.employeeRequests.last['includeDeparted'], 'true');
    expect(find.text('Bao Tran'), findsOneWidget);
    expect(find.byKey(DirectoryScreen.departedChipKey('8')), findsOneWidget);
    expect(find.byKey(DirectoryScreen.departedChipKey('7')), findsNothing);
  });

  testWidgets(
      'a row opens the Employee detail Screen: the Assignment history, current distinguished '
      'from past, and skills', (tester) async {
    final wire = FakeWire(
      employees: [employeeJson('7', 'E-7', 'Alice Nguyen')],
      employeeDetails: {
        '7': employeeDetailJson(
          '7',
          'E-7',
          'Alice Nguyen',
          jobRole: {'id': '5', 'code': 'WELD', 'name': 'Welder'},
          assignments: [
            employeeAssignmentJson(
              '100',
              orgUnitId: '10',
              orgUnitName: 'Assembly',
              jobRoleId: '5',
              jobRoleName: 'Welder',
              isCurrent: true,
              effectiveFrom: '2024-06-01',
            ),
            employeeAssignmentJson(
              '99',
              orgUnitId: '11',
              orgUnitName: 'Line 1',
              isCurrent: false,
              effectiveFrom: '2022-01-01',
              effectiveTo: '2024-06-01',
            ),
          ],
          skills: [employeeSkillJson('200', '30', 'WELD-CERT', 'Welding Certificate')],
        ),
      },
    );
    await openDirectory(tester, wire);

    await tapIn(tester, find.byKey(DirectoryScreen.rowKey('7')));

    expect(find.byType(EmployeeDetailScreen), findsOneWidget);
    expect(find.text('Alice Nguyen'), findsOneWidget);
    expect(find.byKey(EmployeeDetailScreen.assignmentRowKey('100')), findsOneWidget);
    expect(find.byKey(EmployeeDetailScreen.assignmentRowKey('99')), findsOneWidget);
    // The current Assignment is distinguished; the past one is not.
    expect(find.byKey(EmployeeDetailScreen.currentAssignmentKey('100')), findsOneWidget);
    expect(find.byKey(EmployeeDetailScreen.currentAssignmentKey('99')), findsNothing);
    expect(find.text('Assembly · Welder'), findsOneWidget);
    expect(find.text('Line 1'), findsOneWidget);
    // The skills held.
    expect(find.byKey(EmployeeDetailScreen.skillChipKey('30')), findsOneWidget);
    expect(find.text('Welding Certificate'), findsOneWidget);
  });

  testWidgets('a lapsed qualification is shown as lapsed, not omitted', (tester) async {
    final wire = FakeWire(
      employees: [employeeJson('7', 'E-7', 'Alice Nguyen')],
      employeeDetails: {
        '7': employeeDetailJson(
          '7',
          'E-7',
          'Alice Nguyen',
          skills: [
            employeeSkillJson('200', '30', 'WELD-CERT', 'Welding Certificate'),
            employeeSkillJson('201', '31', 'FORK', 'Forklift', expiresOn: '2000-01-01'),
          ],
        ),
      },
    );
    await openDirectory(tester, wire);
    await tapIn(tester, find.byKey(DirectoryScreen.rowKey('7')));

    // The current one carries no lapsed marker.
    expect(find.byKey(EmployeeDetailScreen.skillChipKey('30')), findsOneWidget);
    expect(find.byKey(EmployeeDetailScreen.lapsedSkillChipKey('30')), findsNothing);
    // The expired one is distinguished, not left out.
    expect(find.byKey(EmployeeDetailScreen.skillChipKey('31')), findsOneWidget);
    expect(find.byKey(EmployeeDetailScreen.lapsedSkillChipKey('31')), findsOneWidget);
    expect(find.text('Forklift · Lapsed'), findsOneWidget);
  });

  testWidgets("a Member reaches their own record via My record, with no edit control on it",
      (tester) async {
    final wire = FakeWire(
      role: Roles.operator,
      employees: [employeeJson('9', 'E-9', 'Operator One')],
      employeeDetails: {
        'me': employeeDetailJson('9', 'E-9', 'Operator One'),
      },
    );
    await openDirectory(tester, wire);

    await tapIn(tester, find.byKey(DirectoryScreen.myRecordKey));

    expect(find.byType(EmployeeDetailScreen), findsOneWidget);
    expect(find.text('Operator One'), findsOneWidget);
    expect(wire.requests, contains('GET /api/people/employees/me'));
    // No edit affordance anywhere on this Screen — writes are a separate
    // ticket, and a Member must see none even once they land.
    expect(find.byIcon(Icons.edit), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Edit'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Edit'), findsNothing);
  });

  testWidgets('the own-record address works directly too, and reports plainly when there is none',
      (tester) async {
    final wire = FakeWire(role: Roles.operator, employeeDetailStatus: 404);
    await openDirectory(tester, wire, location: '/directory/me');

    expect(find.byKey(EmployeeDetailScreen.failedKey), findsOneWidget);
  });

  testWidgets('the Directory destination is offered to every approved Account, operator included',
      (tester) async {
    final wire = FakeWire(role: Roles.operator, employees: []);
    await openDirectory(tester, wire);

    expect(find.byType(DirectoryScreen), findsOneWidget);
    expect(find.byType(AccessDeniedScreen), findsNothing);
    // 'Directory' also appears as the Screen's own header, so this looks
    // specifically inside the sidebar rather than matching either occurrence.
    expect(
      find.descendant(of: find.byKey(PlatformShell.sidebarKey), matching: find.text('Directory')),
      findsOneWidget,
    );
  });
}
