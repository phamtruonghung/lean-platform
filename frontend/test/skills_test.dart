/// The skill catalogue (issue #89): every skill the plant recognises, an
/// administrator's own write surface over it, and "who holds this skill"
/// (AC5) — with the wire faked, the one client seam (ADR-0012).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/people/skill_form_dialog.dart';
import 'package:lean_platform/people/skill_qualified_employees_dialog.dart';
import 'package:lean_platform/people/skills_screen.dart';
import 'package:lean_platform/platform/destinations.dart';
import 'package:lean_platform/widgets/app_list_card.dart';
import 'package:lean_platform/widgets/skeleton_list.dart';

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

  // The three shared states, one row shape, one page width (issue #189). This
  // Screen used to load with a bare `CircularProgressIndicator`, empty with a
  // single sentence, fail with a private widget, draw its rows with no rule
  // between them and put its actions beneath a row's text — all of it drift
  // from the sibling catalogue it was modelled on, and all of it what the user
  // saw as "this one is not [ok]".

  testWidgets('while its read is in flight it shows the shared skeleton, not a bare spinner',
      (tester) async {
    final wire = FakeWire(skills: [skillJson('30', 'WELD', 'Welding')])
      ..skillsGate = Completer<void>();
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/skills',
      settle: false,
    );

    expect(find.byType(SkeletonList), findsOneWidget);
    // The bare spinner this Screen used to load behind is gone: the placeholder
    // is the same one the other catalogues show.
    expect(find.byType(CircularProgressIndicator), findsNothing);

    wire.skillsGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Welding · WELD · operation'), findsOneWidget);
  });

  testWidgets('an empty catalogue offers the shared empty state, and the action that fills it',
      (tester) async {
    final wire = FakeWire(skills: []);
    await openSkills(tester, wire);

    expect(find.byKey(SkillsScreen.emptyKey), findsOneWidget);
    expect(find.text('No skills yet'), findsOneWidget);

    await tapIn(tester, find.byKey(SkillsScreen.emptyAddKey));
    expect(find.byType(SkillFormDialog), findsOneWidget);
  });

  testWidgets('a non-administrator gets the empty state without the write affordance',
      (tester) async {
    final wire = FakeWire(role: Roles.operator, skills: []);
    await openSkills(tester, wire);

    expect(find.byKey(SkillsScreen.emptyKey), findsOneWidget);
    expect(find.byKey(SkillsScreen.emptyAddKey), findsNothing);
    expect(find.byKey(SkillsScreen.addKey), findsNothing);
  });

  testWidgets('a failed read renders the shared failure state, and its retry re-reads',
      (tester) async {
    final wire = FakeWire(
      skills: [skillJson('30', 'WELD', 'Welding')],
      skillsStatus: 503,
    );
    await openSkills(tester, wire);

    expect(find.byKey(SkillsScreen.failedKey), findsOneWidget);
    expect(find.text('The skill catalogue could not be read'), findsOneWidget);
    expect(find.text('Welding · WELD · operation'), findsNothing);

    wire.skillsStatus = 200;
    await tapIn(tester, find.byKey(SkillsScreen.retryKey));

    expect(find.byKey(SkillsScreen.failedKey), findsNothing);
    expect(find.text('Welding · WELD · operation'), findsOneWidget);
  });

  testWidgets('a row carries its actions beside its text, and rows are ruled apart',
      (tester) async {
    // A window wide enough for the two outlined buttons to sit beside the
    // name: at a narrower one the row's own `Wrap` gives them their own line
    // rather than overflowing, which is the other half of this row's design.
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 1000);
    addTearDown(tester.view.reset);

    final wire = FakeWire(
      skills: [
        skillJson('30', 'WELD', 'Welding'),
        skillJson('31', 'FIRST-AID', 'First aid', isActive: false),
      ],
    );
    await openSkills(tester, wire);

    final text = tester.getRect(find.text('Welding · WELD · operation'));
    final whoHolds = tester.getRect(find.byKey(SkillsScreen.whoHoldsKey('30')));
    final correct = tester.getRect(find.byKey(SkillsScreen.correctKey('30')));

    // Both actions to the right of the text, on the same line rather than
    // beneath it — the row used to be two lines tall with its right half empty.
    expect(whoHolds.left, greaterThan(text.right));
    expect(correct.left, greaterThan(whoHolds.right));
    expect(whoHolds.center.dy, closeTo(text.center.dy, 8));

    // Two rows, one rule between them, from the shared list card — scoped to
    // the card, since the Shell draws a hairline of its own.
    expect(find.byType(AppListCard), findsOneWidget);
    expect(
      find.descendant(of: find.byType(AppListCard), matching: find.byType(Divider)),
      findsOneWidget,
    );
  });

  testWidgets('the catalogue page is the Platform page width, not a narrower one',
      (tester) async {
    // A window wide enough for the 900px page to fit whole.
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 1000);
    addTearDown(tester.view.reset);

    final wire = FakeWire(skills: [skillJson('30', 'WELD', 'Welding')]);
    await openSkills(tester, wire);

    // 900 minus the page's own 16px insets is 868; the old 760px page could
    // not produce a catalogue wider than 728.
    expect(tester.getSize(find.byType(AppListCard)).width, greaterThan(800));
  });
}
