/// The create form for an Assessment (issue #588, ADR-0068, slice 3) — the wire
/// faked, the one client seam (ADR-0012, AGENTS.md §5).
///
/// What a person does on `/assessments/new`: pick the process, type a title,
/// choose a paper size (the two defaults restate with it), add an Org Unit and
/// read the reach the server answered, then create and assign in one submit.
library;


import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/people/assessment_create_screen.dart';
import 'package:lean_platform/platform/destinations.dart';
import 'package:lean_platform/platform/router.dart';

import 'harness.dart';

const _display = 'PPL_ASSESSMENT_DISPLAY';
const _change = 'PPL_ASSESSMENT_CHANGE';

const _process = '11';
const _crew = '21';

FakeWire _wire() {
  final wire = FakeWire(
    role: Roles.supervisor,
    mePermissions: const [_display, _change],
    sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
    orgUnitSearchResults: [orgUnitJson(_process, 'Braiding')],
  );
  wire.crewSearchResults = [crewJson(_crew, 'Crew A', employeeCount: 12)];
  wire.assignPreviewCount = 4;
  return wire;
}

void _tall(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1200, 3200);
  addTearDown(tester.view.reset);
}

Future<void> _open(WidgetTester tester, FakeWire wire) {
  _tall(tester);
  return pumpApp(
    tester,
    gateway: FakeAuthGateway(accessToken: 'a-token'),
    client: wire.client,
    initialLocation: Routes.assessmentNew,
  );
}

Future<void> _addOrgUnit(WidgetTester tester) async {
  await typeInSearchField(tester, AssessmentCreateScreen.orgUnitSearchKey, 'Br');
  await tester.pump();
  await tapIn(tester, find.byKey(AssessmentCreateScreen.orgUnitSuggestionKey(_process)));
}

Future<void> _addCrew(WidgetTester tester) async {
  await typeInSearchField(tester, AssessmentCreateScreen.crewSearchKey, 'Cr');
  await tester.pump();
  await tapIn(tester, find.byKey(AssessmentCreateScreen.crewSuggestionKey(_crew)));
}

void main() {
  testWidgets('the paper size restates the two defaults while they are untouched', (tester) async {
    await _open(tester, _wire());
    await tester.pumpAndSettle();

    expect(find.text('Who sits it'), findsOneWidget);
    // 10 Questions: 20 minutes, pass mark 8.
    expect(find.widgetWithText(TextField, '20'), findsOneWidget);
    expect(find.widgetWithText(TextField, '8'), findsOneWidget);

    await tester.tap(find.byKey(AssessmentCreateScreen.sizeKey(15)));
    await tester.pumpAndSettle();

    // 15 Questions: 30 minutes, pass mark 12.
    expect(find.widgetWithText(TextField, '30'), findsOneWidget);
    expect(find.widgetWithText(TextField, '12'), findsOneWidget);
  });

  testWidgets('a typed minute count is kept when the paper size changes', (tester) async {
    await _open(tester, _wire());
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(AssessmentCreateScreen.minutesKey), '25');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AssessmentCreateScreen.sizeKey(15)));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, '25'), findsOneWidget);
    // The pass mark had not been touched, so it still moves with the size.
    expect(find.widgetWithText(TextField, '12'), findsOneWidget);
  });

  testWidgets('the reach is the server\'s answer for the group, and an unresolved Employee is warned about',
      (tester) async {
    final wire = _wire();
    wire.assignPreviewUnresolvedNames = ['Homeless Sitter'];
    await _open(tester, wire);
    await tester.pumpAndSettle();

    await _addOrgUnit(tester);
    await tester.pumpAndSettle();

    expect(wire.assignPreviewReads, isNotEmpty);
    expect(find.text('This will reach 4 Employees.'), findsOneWidget);
    expect(find.textContaining('Homeless Sitter'), findsOneWidget);
  });

  testWidgets('picking a Crew shows its member count on the chip and the preview asks for its id',
      (tester) async {
    final wire = _wire();
    await _open(tester, wire);
    await tester.pumpAndSettle();

    await _addCrew(tester);
    await tester.pumpAndSettle();

    expect(wire.crewSearchRequests.last, ('1', 'Cr'));
    expect(
      find.descendant(
        of: find.byKey(AssessmentCreateScreen.crewChipKey(_crew)),
        matching: find.text('Crew A · 12 Employees'),
      ),
      findsOneWidget,
    );
    expect(wire.assignPreviewReads.last, contains('crewIds=$_crew'));
    expect(find.text('This will reach 4 Employees.'), findsOneWidget);
  });

  testWidgets('a group of only a Crew is enough to create and assign: the assign body carries the Crew id',
      (tester) async {
    final wire = _wire();
    await _open(tester, wire);
    await tester.pumpAndSettle();

    await typeInSearchField(tester, AssessmentCreateScreen.processSearchKey, 'Br');
    await tester.pump();
    await tapIn(tester, find.byKey(AssessmentCreateScreen.processSuggestionKey(_process)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(AssessmentCreateScreen.titleKey), 'Braiding basics');
    await _addCrew(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(AssessmentCreateScreen.submitKey));
    await tester.pumpAndSettle();

    expect(wire.assessmentPosts, hasLength(1));
    expect(wire.assessmentAssigns, hasLength(1));
    expect(wire.assessmentAssigns.single.$2['crewIds'], [_crew]);
    expect(wire.assessmentAssigns.single.$2['orgUnitIds'], isEmpty);
  });
}
