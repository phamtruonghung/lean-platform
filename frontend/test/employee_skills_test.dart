/// Recording, and re-assessing, an Employee holding a skill (issue #89), and
/// a lapsed qualification's own rendering — with the wire faked, the one
/// client seam (ADR-0012).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/people/directory_screen.dart';
import 'package:lean_platform/people/employee_detail_screen.dart';
import 'package:lean_platform/people/employee_skill_form_dialog.dart';
import 'package:lean_platform/platform/destinations.dart';
import 'package:lean_platform/widgets/app_date_field.dart';

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

    await pickSuggestion(
      tester,
      fieldKey: EmployeeSkillFormDialog.skillKey,
      term: 'Weld',
      suggestionKey: EmployeeSkillFormDialog.skillSuggestionKey('30'),
    );
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

  // AppDateField (issue #126, ADR-0023) at this form's own two date fields —
  // distinct `name`s (`skill-assessed-on`, `skill-expires-on`) are exactly
  // why `AppDateField.name` is parameterised (its own header): two fields on
  // one form need two sets of keys, not one colliding pair.

  testWidgets(
      'the assessed-on field opens a date picker on tap, and picking a date fills it displayed '
      'as YYYY-MM-DD', (tester) async {
    final wire = FakeWire(
      employees: [employeeJson('7', 'E-7', 'Alice Nguyen')],
      employeeDetails: {'7': employeeDetailJson('7', 'E-7', 'Alice Nguyen')},
      skills: [skillJson('30', 'WELD', 'Welding')],
    );
    await openDirectory(tester, wire);
    await tapIn(tester, find.byKey(DirectoryScreen.rowKey('7')));
    await tapIn(tester, find.byKey(EmployeeDetailScreen.recordSkillKey));

    expect(find.byType(DatePickerDialog), findsNothing);
    await tapIn(tester, find.byKey(EmployeeSkillFormDialog.assessedOnKey));
    expect(find.byType(DatePickerDialog), findsOneWidget);

    await tester.tap(find.byTooltip('Switch to input'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '02/10/2024');
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.byType(DatePickerDialog), findsNothing);
    expect(find.text('2024-02-10'), findsOneWidget);
  });

  testWidgets('the assessed-on field cannot be filled by typing', (tester) async {
    final wire = FakeWire(
      employees: [employeeJson('7', 'E-7', 'Alice Nguyen')],
      employeeDetails: {'7': employeeDetailJson('7', 'E-7', 'Alice Nguyen')},
      skills: [skillJson('30', 'WELD', 'Welding')],
    );
    await openDirectory(tester, wire);
    await tapIn(tester, find.byKey(DirectoryScreen.rowKey('7')));
    await tapIn(tester, find.byKey(EmployeeDetailScreen.recordSkillKey));

    final fieldKey = AppDateField.fieldKey('skill-assessed-on');
    await tester.enterText(find.byKey(fieldKey), '2099-12-31');
    await tester.pump();

    expect(find.text('2099-12-31'), findsNothing);
    final field = tester.widget<TextField>(find.byKey(fieldKey));
    expect(field.readOnly, isTrue);
    expect(field.controller!.text, isEmpty);
  });

  testWidgets(
      'clearing a picked assessed-on date returns it to empty, and the request omits '
      'assessedOn exactly as a never-picked one does', (tester) async {
    final wire = FakeWire(
      employees: [employeeJson('7', 'E-7', 'Alice Nguyen')],
      employeeDetails: {'7': employeeDetailJson('7', 'E-7', 'Alice Nguyen')},
      skills: [skillJson('30', 'WELD', 'Welding')],
    );
    await openDirectory(tester, wire);
    await tapIn(tester, find.byKey(DirectoryScreen.rowKey('7')));
    await tapIn(tester, find.byKey(EmployeeDetailScreen.recordSkillKey));

    await pickSuggestion(
      tester,
      fieldKey: EmployeeSkillFormDialog.skillKey,
      term: 'Weld',
      suggestionKey: EmployeeSkillFormDialog.skillSuggestionKey('30'),
    );

    expect(find.byKey(AppDateField.clearKey('skill-assessed-on')), findsNothing);
    await pickDate(tester, EmployeeSkillFormDialog.assessedOnKey, DateTime(2024, 2, 10));
    expect(find.text('2024-02-10'), findsOneWidget);
    expect(find.byKey(AppDateField.clearKey('skill-assessed-on')), findsOneWidget);

    await tapIn(tester, find.byKey(AppDateField.clearKey('skill-assessed-on')));
    expect(find.text('2024-02-10'), findsNothing);
    expect(find.byKey(AppDateField.clearKey('skill-assessed-on')), findsNothing);

    await tapIn(tester, find.byKey(EmployeeSkillFormDialog.submitKey));

    expect(wire.employeeSkillPuts.single.$3, {'proficiencyLevel': 1});
  });

  testWidgets(
      'the expires-on field opens a date picker on tap, and picking a date fills it displayed '
      'as YYYY-MM-DD', (tester) async {
    final wire = FakeWire(
      employees: [employeeJson('7', 'E-7', 'Alice Nguyen')],
      employeeDetails: {'7': employeeDetailJson('7', 'E-7', 'Alice Nguyen')},
      skills: [skillJson('30', 'WELD', 'Welding')],
    );
    await openDirectory(tester, wire);
    await tapIn(tester, find.byKey(DirectoryScreen.rowKey('7')));
    await tapIn(tester, find.byKey(EmployeeDetailScreen.recordSkillKey));

    expect(find.byType(DatePickerDialog), findsNothing);
    await tapIn(tester, find.byKey(EmployeeSkillFormDialog.expiresOnKey));
    expect(find.byType(DatePickerDialog), findsOneWidget);

    await tester.tap(find.byTooltip('Switch to input'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '09/05/2026');
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.byType(DatePickerDialog), findsNothing);
    expect(find.text('2026-09-05'), findsOneWidget);
  });

  testWidgets('the expires-on field cannot be filled by typing', (tester) async {
    final wire = FakeWire(
      employees: [employeeJson('7', 'E-7', 'Alice Nguyen')],
      employeeDetails: {'7': employeeDetailJson('7', 'E-7', 'Alice Nguyen')},
      skills: [skillJson('30', 'WELD', 'Welding')],
    );
    await openDirectory(tester, wire);
    await tapIn(tester, find.byKey(DirectoryScreen.rowKey('7')));
    await tapIn(tester, find.byKey(EmployeeDetailScreen.recordSkillKey));

    final fieldKey = AppDateField.fieldKey('skill-expires-on');
    await tester.enterText(find.byKey(fieldKey), '2099-12-31');
    await tester.pump();

    expect(find.text('2099-12-31'), findsNothing);
    final field = tester.widget<TextField>(find.byKey(fieldKey));
    expect(field.readOnly, isTrue);
    expect(field.controller!.text, isEmpty);
  });

  testWidgets(
      'clearing a picked expires-on date returns it to empty, and the request omits '
      'expiresOn exactly as a never-picked one does', (tester) async {
    final wire = FakeWire(
      employees: [employeeJson('7', 'E-7', 'Alice Nguyen')],
      employeeDetails: {'7': employeeDetailJson('7', 'E-7', 'Alice Nguyen')},
      skills: [skillJson('30', 'WELD', 'Welding')],
    );
    await openDirectory(tester, wire);
    await tapIn(tester, find.byKey(DirectoryScreen.rowKey('7')));
    await tapIn(tester, find.byKey(EmployeeDetailScreen.recordSkillKey));

    await pickSuggestion(
      tester,
      fieldKey: EmployeeSkillFormDialog.skillKey,
      term: 'Weld',
      suggestionKey: EmployeeSkillFormDialog.skillSuggestionKey('30'),
    );

    expect(find.byKey(AppDateField.clearKey('skill-expires-on')), findsNothing);
    await pickDate(tester, EmployeeSkillFormDialog.expiresOnKey, DateTime(2026, 9, 5));
    expect(find.text('2026-09-05'), findsOneWidget);
    expect(find.byKey(AppDateField.clearKey('skill-expires-on')), findsOneWidget);

    await tapIn(tester, find.byKey(AppDateField.clearKey('skill-expires-on')));
    expect(find.text('2026-09-05'), findsNothing);
    expect(find.byKey(AppDateField.clearKey('skill-expires-on')), findsNothing);

    await tapIn(tester, find.byKey(EmployeeSkillFormDialog.submitKey));

    expect(wire.employeeSkillPuts.single.$3, {'proficiencyLevel': 1});
  });

  testWidgets(
      're-assessing a held skill with a stored expiresOn displays it on the expires-on field',
      (tester) async {
    final wire = FakeWire(
      employees: [employeeJson('7', 'E-7', 'Alice Nguyen')],
      employeeDetails: {
        '7': employeeDetailJson(
          '7',
          'E-7',
          'Alice Nguyen',
          skills: [
            employeeSkillJson('500', '30', 'WELD', 'Welding', expiresOn: '2027-03-15'),
          ],
        ),
      },
      skills: [skillJson('30', 'WELD', 'Welding')],
    );
    await openDirectory(tester, wire);
    await tapIn(tester, find.byKey(DirectoryScreen.rowKey('7')));

    await tapIn(tester, find.byKey(EmployeeDetailScreen.reassessSkillKey('30')));
    expect(find.byType(EmployeeSkillFormDialog), findsOneWidget);

    // The stored expiry shows already, without picking anything — but the
    // assessed-on field starts genuinely blank even on a re-assessment (this
    // dialog's own header: never pre-filled from the record being
    // re-assessed).
    expect(find.text('2027-03-15'), findsOneWidget);
    final assessedOnField =
        tester.widget<TextField>(find.byKey(AppDateField.fieldKey('skill-assessed-on')));
    expect(assessedOnField.controller!.text, isEmpty);
  });
}
