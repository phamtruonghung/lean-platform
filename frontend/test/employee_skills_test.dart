/// Recording, and re-assessing, an Employee holding a skill (issue #89), and
/// a lapsed qualification's own rendering — with the wire faked, the one
/// client seam (ADR-0012).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/people/directory_screen.dart';
import 'package:lean_platform/people/employee_detail_screen.dart';
import 'package:lean_platform/people/employee_skill_form_dialog.dart';
import 'package:lean_platform/platform/destinations.dart';

import 'harness.dart';

Future<void> openDirectory(WidgetTester tester, FakeWire wire, {String location = '/directory'}) =>
    pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: location,
    );

void main() {
  testWidgets(
      "recording an assessment sends a PUT and the skill appears on the Employee's Screen",
      (tester) async {
    final wire = FakeWire(
      employees: [employeeJson('7', 'E-7', 'Alice Nguyen')],
      employeeDetails: {'7': employeeDetailJson('7', 'E-7', 'Alice Nguyen')},
      skills: [skillJson('30', 'WELD', 'Welding')],
    );
    await openDirectory(tester, wire);
    await tapIn(tester, find.byKey(DirectoryScreen.rowKey('7')));

    await tapIn(tester, find.byKey(EmployeeDetailScreen.recordSkillKey));
    expect(find.byType(EmployeeSkillFormDialog), findsOneWidget);

    await tapIn(tester, find.byKey(EmployeeSkillFormDialog.skillKey));
    await tapIn(tester, find.text('Welding').last);
    await tapIn(tester, find.byKey(EmployeeSkillFormDialog.proficiencyKey));
    await tapIn(tester, find.text('3').last);
    await tapIn(tester, find.byKey(EmployeeSkillFormDialog.submitKey));

    expect(wire.employeeSkillPuts.single.$1, '7');
    expect(wire.employeeSkillPuts.single.$2, '30');
    expect(wire.employeeSkillPuts.single.$3, {'proficiencyLevel': 3});
    expect(find.byType(EmployeeSkillFormDialog), findsNothing);
    // The Employee's own record was re-read (not the PUT's bare response
    // spliced in), and the freshly recorded skill shows.
    expect(find.byKey(EmployeeDetailScreen.skillChipKey('30')), findsOneWidget);
    expect(find.text('Welding'), findsOneWidget);
  });

  testWidgets(
      'a re-assessment of a skill already held sends the same PUT and updates in place rather '
      'than duplicating', (tester) async {
    final wire = FakeWire(
      employees: [employeeJson('7', 'E-7', 'Alice Nguyen')],
      employeeDetails: {
        '7': employeeDetailJson(
          '7',
          'E-7',
          'Alice Nguyen',
          skills: [employeeSkillJson('500', '30', 'WELD', 'Welding', proficiencyLevel: 2)],
        ),
      },
      skills: [skillJson('30', 'WELD', 'Welding')],
    );
    await openDirectory(tester, wire);
    await tapIn(tester, find.byKey(DirectoryScreen.rowKey('7')));

    expect(find.byKey(EmployeeDetailScreen.skillChipKey('30')), findsOneWidget);

    await tapIn(tester, find.byKey(EmployeeDetailScreen.reassessSkillKey('30')));
    expect(find.byType(EmployeeSkillFormDialog), findsOneWidget);

    await tapIn(tester, find.byKey(EmployeeSkillFormDialog.proficiencyKey));
    await tapIn(tester, find.text('4').last);
    await tapIn(tester, find.byKey(EmployeeSkillFormDialog.submitKey));

    // Exactly one PUT — the same route a first assessment uses, carrying the
    // one Employee/skill pair `employee_skills`'s own UNIQUE constraint keys
    // on (skills.js's own header).
    expect(wire.employeeSkillPuts.length, 1);
    expect(wire.employeeSkillPuts.single.$1, '7');
    expect(wire.employeeSkillPuts.single.$2, '30');
    expect(wire.employeeSkillPuts.single.$3, {'proficiencyLevel': 4});
    // Still exactly one chip for this skill — updated in place, not
    // duplicated.
    expect(find.byKey(EmployeeDetailScreen.skillChipKey('30')), findsOneWidget);
  });

  testWidgets('a lapsed qualification renders as lapsed, with isLapsed scripted explicitly on the wire',
      (tester) async {
    final wire = FakeWire(
      employees: [employeeJson('7', 'E-7', 'Alice Nguyen')],
      employeeDetails: {
        '7': employeeDetailJson(
          '7',
          'E-7',
          'Alice Nguyen',
          // isLapsed scripted directly, not left for the client to infer from
          // expiresOn against the device clock — proving the render follows
          // the wire, never a device-derived date rule (issue #91).
          skills: [
            employeeSkillJson('500', '30', 'WELD', 'Welding', expiresOn: '2020-01-01', isLapsed: true),
          ],
        ),
      },
    );
    await openDirectory(tester, wire);
    await tapIn(tester, find.byKey(DirectoryScreen.rowKey('7')));

    expect(find.byKey(EmployeeDetailScreen.lapsedSkillChipKey('30')), findsOneWidget);
    expect(find.text('Welding · Lapsed'), findsOneWidget);
  });

  testWidgets('a non-administrator sees held skills but no record or re-assess control',
      (tester) async {
    final wire = FakeWire(
      role: Roles.supervisor,
      employees: [employeeJson('7', 'E-7', 'Alice Nguyen')],
      employeeDetails: {
        '7': employeeDetailJson(
          '7',
          'E-7',
          'Alice Nguyen',
          skills: [employeeSkillJson('500', '30', 'WELD', 'Welding')],
        ),
      },
    );
    await openDirectory(tester, wire);
    await tapIn(tester, find.byKey(DirectoryScreen.rowKey('7')));

    expect(find.byKey(EmployeeDetailScreen.skillChipKey('30')), findsOneWidget);
    expect(find.byKey(EmployeeDetailScreen.recordSkillKey), findsNothing);
    expect(find.byKey(EmployeeDetailScreen.reassessSkillKey('30')), findsNothing);
  });
}
