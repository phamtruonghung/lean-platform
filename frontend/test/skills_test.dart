/// The skill catalogue (issue #89): every skill the plant recognises, an
/// administrator's own write surface over it, and "who holds this skill"
/// (AC5) — with the wire faked, the one client seam (ADR-0012).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/people/skill_form_dialog.dart';
import 'package:lean_platform/people/skill_qualified_employees_dialog.dart';
import 'package:lean_platform/people/skills_screen.dart';
import 'package:lean_platform/platform/destinations.dart';

import 'harness.dart';

Future<void> openSkills(WidgetTester tester, FakeWire wire) => pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/skills',
    );

void main() {
  testWidgets('the skill catalogue renders, deactivated rows included, for an administrator',
      (tester) async {
    final wire = FakeWire(
      skills: [
        skillJson('30', 'WELD', 'Welding', skillCategory: 'operation'),
        skillJson('31', 'FIRST-AID', 'First aid', skillCategory: 'safety', isActive: false),
      ],
    );
    await openSkills(tester, wire);

    expect(find.byType(SkillsScreen), findsOneWidget);
    expect(find.text('Welding · WELD · operation'), findsOneWidget);
    expect(find.text('First aid · FIRST-AID · safety'), findsOneWidget);
    expect(find.byKey(SkillsScreen.inactiveChipKey('31')), findsOneWidget);
    expect(find.byKey(SkillsScreen.addKey), findsOneWidget);
  });

  testWidgets('an administrator can add a skill, and it appears in the list', (tester) async {
    final wire = FakeWire(skills: [skillJson('30', 'WELD', 'Welding')]);
    await openSkills(tester, wire);

    await tapIn(tester, find.byKey(SkillsScreen.addKey));
    await tester.enterText(find.byKey(SkillFormDialog.codeKey), 'FORK');
    await tester.enterText(find.byKey(SkillFormDialog.nameKey), 'Forklift operation');
    await tapIn(tester, find.byKey(SkillFormDialog.submitKey));

    expect(wire.skillPosts.single, {
      'code': 'FORK',
      'name': 'Forklift operation',
      'skillCategory': 'operation',
      'requiresCertification': false,
    });
    expect(find.byType(SkillFormDialog), findsNothing);
    expect(find.text('Forklift operation · FORK · operation'), findsOneWidget);
  });

  testWidgets('an administrator can correct a skill, sending only the changed field',
      (tester) async {
    final wire = FakeWire(skills: [skillJson('30', 'WELD', 'Welding')]);
    await openSkills(tester, wire);

    await tapIn(tester, find.byKey(SkillsScreen.correctKey('30')));
    expect(find.byType(SkillFormDialog), findsOneWidget);
    // Pre-filled from the row already on screen, not left blank.
    expect(find.text('Welding'), findsOneWidget);

    await tester.enterText(find.byKey(SkillFormDialog.nameKey), 'Advanced Welding');
    await tapIn(tester, find.byKey(SkillFormDialog.submitKey));

    expect(wire.skillPatches.single.$1, '30');
    expect(wire.skillPatches.single.$2, {'name': 'Advanced Welding'});
    expect(find.byType(SkillFormDialog), findsNothing);
    expect(find.text('Advanced Welding · WELD · operation'), findsOneWidget);
  });

  testWidgets('a non-administrator sees the catalogue but no write control', (tester) async {
    final wire = FakeWire(role: Roles.supervisor, skills: [skillJson('30', 'WELD', 'Welding')]);
    await openSkills(tester, wire);

    expect(find.text('Welding · WELD · operation'), findsOneWidget);
    expect(find.byKey(SkillsScreen.addKey), findsNothing);
    expect(find.byKey(SkillsScreen.correctKey('30')), findsNothing);
    // "Who holds this" is an open read (skill-routes.js's own header) —
    // offered regardless of role.
    expect(find.byKey(SkillsScreen.whoHoldsKey('30')), findsOneWidget);
  });

  testWidgets('the qualified-employee list sends both orgUnitId and minimumLevel', (tester) async {
    final wire = FakeWire(
      skills: [skillJson('30', 'WELD', 'Welding')],
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [orgUnitJson('10', 'Line 1')],
      },
      qualifiedEmployees: [qualifiedEmployeeJson('7', 'E-7', 'Alice Nguyen', proficiencyLevel: 3)],
    );
    await openSkills(tester, wire);

    await tapIn(tester, find.byKey(SkillsScreen.whoHoldsKey('30')));
    expect(find.byType(SkillQualifiedEmployeesDialog), findsOneWidget);

    await tapIn(tester, find.byKey(SkillQualifiedEmployeesDialog.orgUnitKey('10')));
    await tapIn(tester, find.byKey(SkillQualifiedEmployeesDialog.minimumLevelKey));
    await tapIn(tester, find.text('3').last);
    await tapIn(tester, find.byKey(SkillQualifiedEmployeesDialog.searchKey));

    expect(wire.qualifiedEmployeeRequests.single, ('30', '10', '3'));
    expect(find.text('Alice Nguyen · E-7'), findsOneWidget);
  });

  testWidgets('choosing no Org Unit leaves the search disabled, never firing a request that would 400',
      (tester) async {
    final wire = FakeWire(
      skills: [skillJson('30', 'WELD', 'Welding')],
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [orgUnitJson('10', 'Line 1')],
      },
    );
    await openSkills(tester, wire);

    await tapIn(tester, find.byKey(SkillsScreen.whoHoldsKey('30')));
    expect(find.byType(SkillQualifiedEmployeesDialog), findsOneWidget);

    final button = tester.widget<FilledButton>(find.byKey(SkillQualifiedEmployeesDialog.searchKey));
    expect(button.onPressed, isNull);
    expect(wire.qualifiedEmployeeRequests, isEmpty);
  });
}
