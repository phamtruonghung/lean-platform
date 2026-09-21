/// The Safety incident surface, driven through the router against a faked
/// wire (issue #226) — the same seam `nonconformances_test.dart` uses:
/// `pumpApp` with a `FakeWire`, act through `WidgetTester`, and assert on
/// what renders and on the requests the Screen actually sent.
///
/// Covers the ticket's three Screens and the requests behind them: the
/// register with its filters, one incident's detail, and the record form.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/maintenance/org_unit_chooser.dart';
import 'package:lean_platform/platform/destinations.dart';
import 'package:lean_platform/safety/incident_detail_screen.dart';
import 'package:lean_platform/safety/incident_form_dialog.dart';
import 'package:lean_platform/safety/incidents_screen.dart';

import 'harness.dart';

/// The wire every test in this file starts from: one Site, one area with a
/// line beneath it, and two Safety incidents — one no-injury near miss and
/// one recordable medical-treatment injury. Each test mutates only what it
/// is about.
/// [safety] is what the caller's own Grant carries (`safetyAuthority`,
/// ADR-0039). It defaults to holding it, because most of this file is about
/// recording rather than about who may classify — the one test that turns on
/// the difference says so by passing `safety: false`, which is issue #224's
/// rule that naming the injured Employee is part of the injury classification
/// and needs Safety authority reaching the Org Unit.
FakeWire _wire({bool safety = true}) => FakeWire(
      orgUnitScope: {
        'everywhere': false,
        'grants': [scopeGrantJson('10', canWrite: true, safetyAuthority: safety)],
      },
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [orgUnitJson('10', 'Assembly')],
        '10': [orgUnitJson('11', 'Line 1', parentId: '10', unitType: 'line')],
      },
      assets: {
        '1': [assetJson('1', 'PRESS-1', 'Press 1', orgUnitId: '11', orgUnitName: 'Line 1')],
      },
      employees: [employeeJson('7', 'E-7', 'Alice Nguyen')],
      safetyIncidents: {
        '1': [
          safetyIncidentJson(
            '901',
            'SI-HCM-2026-00001',
            incidentType: 'injury',
            severityLevel: 'medical_treatment',
            isRecordable: true,
            orgUnitId: '11',
            orgUnitName: 'Line 1',
            productionDate: '2026-04-06',
            shiftCode: 'DAY',
            shiftName: 'Day shift',
            description: 'Caught a hand at the press.',
          ),
          safetyIncidentJson(
            '902',
            'SI-HCM-2026-00002',
            incidentType: 'near_miss',
            severityLevel: 'near_miss',
            isRecordable: false,
            orgUnitId: '10',
            orgUnitName: 'Assembly',
            description: 'A pallet nearly fell from a rack.',
          ),
        ],
      },
    );

Future<void> _pump(
  WidgetTester tester,
  FakeWire wire, {
  String location = '/safety/incidents',
  Size size = const Size(800, 1200),
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  await pumpApp(
    tester,
    gateway: FakeAuthGateway(accessToken: 'a-token'),
    client: wire.client,
    initialLocation: location,
  );
}

String _textOf(WidgetTester tester, Key key) {
  final widget = tester.widget(find.byKey(key));
  if (widget is Text) return widget.data!;
  return tester
      .widgetList<Text>(find.descendant(of: find.byKey(key), matching: find.byType(Text)))
      .last
      .data!;
}

Future<void> _choose(WidgetTester tester, Key fieldKey, String option) async {
  await tapIn(tester, find.byKey(fieldKey));
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

void main() {
  // -------------------------------------------------------------------------
  // The register
  // -------------------------------------------------------------------------

  testWidgets(
      'the register lists a Site\'s Safety incidents with severity on the left and status on '
      'the right', (tester) async {
    final wire = _wire();
    await _pump(tester, wire);

    expect(wire.safetyIncidentListRequests, isNotEmpty);

    expect(find.byKey(SafetyIncidentsScreen.rowKey('901')), findsOneWidget);
    expect(find.text('SI-HCM-2026-00001'), findsOneWidget);
    expect(find.text('Injury'), findsOneWidget);
    expect(_textOf(tester, SafetyIncidentsScreen.rowSeverityKey('901')), 'Medical treatment');
    expect(_textOf(tester, SafetyIncidentsScreen.rowStatusKey('901')), 'Open');
    expect(
      _textOf(tester, SafetyIncidentsScreen.rowFiledKey('901')),
      'Line 1 · filed against 2026-04-06 · Day shift',
    );

    // The no-injury rung, read the same way.
    expect(_textOf(tester, SafetyIncidentsScreen.rowSeverityKey('902')), 'No injury');
  });

  testWidgets(
      'a Site with no incidents recorded says so flatly, and still offers the record form',
      (tester) async {
    final empty = FakeWire(
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [orgUnitJson('10', 'Assembly')],
      },
    );
    await _pump(tester, empty);

    expect(find.byKey(SafetyIncidentsScreen.emptyKey), findsOneWidget);
    // Flat, deliberately — never "All clear" (the binding design comment on
    // #223): a plant with no incidents may simply not be reporting.
    expect(find.text('No incidents recorded for this period'), findsOneWidget);
    expect(find.text('All clear'), findsNothing);
    expect(find.byKey(SafetyIncidentsScreen.recordKey), findsOneWidget);
  });

  testWidgets('the register narrows by each filter, and sends exactly the query the address takes',
      (tester) async {
    final wire = _wire();
    await _pump(tester, wire);

    await _choose(tester, SafetyIncidentsScreen.statusFilterKey, 'Closed');
    expect(wire.safetyIncidentListRequests.last, {'status': 'closed'});
    expect(find.byKey(SafetyIncidentsScreen.emptyMatchedKey), findsOneWidget);

    await _choose(tester, SafetyIncidentsScreen.statusFilterKey, 'Any status');
    await _choose(tester, SafetyIncidentsScreen.typeFilterKey, 'Near miss');
    expect(wire.safetyIncidentListRequests.last, {'incidentType': 'near_miss'});

    await _choose(tester, SafetyIncidentsScreen.severityFilterKey, 'Fatality');
    expect(wire.safetyIncidentListRequests.last, {
      'incidentType': 'near_miss',
      'severityLevel': 'fatality',
    });

    await _choose(tester, SafetyIncidentsScreen.recordableFilterKey, 'Recordable');
    expect(wire.safetyIncidentListRequests.last, {
      'incidentType': 'near_miss',
      'severityLevel': 'fatality',
      'isRecordable': 'true',
    });

    await pickDate(tester, SafetyIncidentsScreen.fromDateKey, DateTime(2026, 4, 6));
    expect(wire.safetyIncidentListRequests.last, {
      'incidentType': 'near_miss',
      'severityLevel': 'fatality',
      'isRecordable': 'true',
      'from': '2026-04-06',
    });

    // The Org Unit filter names one area, and the server includes everything
    // beneath it — the ticket's own criterion.
    await tapIn(tester, find.byKey(SafetyIncidentsScreen.orgUnitFilterKey));
    await tapIn(tester, find.byKey(OrgUnitChooser.chooseKey('10')));
    expect(wire.safetyIncidentListRequests.last, {
      'incidentType': 'near_miss',
      'severityLevel': 'fatality',
      'isRecordable': 'true',
      'from': '2026-04-06',
      'orgUnitId': '10',
    });
    expect(find.text('Assembly'), findsWidgets);

    await tapIn(tester, find.byKey(SafetyIncidentsScreen.clearFiltersKey));
    expect(wire.safetyIncidentListRequests.last, isEmpty);
    expect(find.byKey(SafetyIncidentsScreen.rowKey('901')), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // Recording
  // -------------------------------------------------------------------------

  testWidgets(
      'the severity dropdown renders in ladder order and marks the recordable line, never '
      'alphabetically', (tester) async {
    final wire = _wire();
    await _pump(tester, wire);
    await tapIn(tester, find.byKey(SafetyIncidentsScreen.recordKey));

    await tapIn(tester, find.byKey(SafetyIncidentFormDialog.severityKey));

    // Each rung's own word is offered somewhere while the menu is open — a
    // closed `DropdownButtonFormField` keeps its own hidden copy of every
    // item around for sizing, so a label can legitimately match twice (the
    // hidden one and the visible popup one); `.last` is the one the popup
    // itself painted, so its position is what the ladder order is checked
    // against. Ladder order is no injury through fatality; alphabetical
    // would read Fatality, First aid, Lost time, Medical treatment, No
    // injury, Restricted work instead, so this tells the two apart rather
    // than merely checking membership.
    const rungLabelsInLadderOrder = [
      'No injury',
      'First aid',
      'Medical treatment · recordable',
      'Restricted work · recordable',
      'Lost time · recordable',
      'Fatality · recordable',
    ];
    for (final label in rungLabelsInLadderOrder) {
      expect(find.text(label), findsWidgets, reason: 'menu should offer "$label"');
    }
    final positions = [
      for (final label in rungLabelsInLadderOrder) tester.getTopLeft(find.text(label).last).dy,
    ];
    expect(
      positions,
      List<double>.from(positions)..sort(),
      reason: 'the rungs should render top to bottom in ladder order',
    );

    await tester.tap(find.text('No injury').last);
    await tester.pumpAndSettle();
  });

  testWidgets(
      'the injured Employee is not offered without Safety authority, and no classification is sent',
      (tester) async {
    // Issue #224, ADR-0037: naming who was hurt is part of the injury
    // classification, and the API refuses it from a caller holding only a
    // write Grant with a 403. Nobody is shown a field whose only answer would
    // be a refusal — and recording an incident without one stays exactly as
    // open as issue #226 made it.
    final wire = _wire(safety: false);
    await _pump(tester, wire);

    await tapIn(tester, find.byKey(SafetyIncidentsScreen.recordKey));
    await _choose(tester, SafetyIncidentFormDialog.incidentTypeKey, 'Injury');
    await _choose(tester, SafetyIncidentFormDialog.severityKey, 'First aid');
    await tester.enterText(
      find.byKey(SafetyIncidentFormDialog.descriptionKey),
      'Cut a finger on a burr while deburring a part.',
    );
    await tester.pump();

    await tapIn(tester, find.byKey(OrgUnitChooser.chooseKey('10')));
    expect(find.byKey(SafetyIncidentFormDialog.chosenOrgUnitKey), findsOneWidget);

    expect(find.byKey(SafetyIncidentFormDialog.employeeFieldKey()), findsNothing);

    await tapIn(tester, find.byKey(SafetyIncidentFormDialog.submitKey));

    final body = wire.safetyIncidentPosts.single;
    expect(body.containsKey('employeeId'), isFalse);
    expect(body.containsKey('injuryTypeId'), isFalse);
    expect(body.containsKey('bodyPartId'), isFalse);
    expect(body['description'], 'Cut a finger on a burr while deburring a part.');
  });

  testWidgets('the record form chooses every known-set value and sends the whole record',
      (tester) async {
    final wire = _wire();
    await _pump(tester, wire);

    await tapIn(tester, find.byKey(SafetyIncidentsScreen.recordKey));

    await _choose(tester, SafetyIncidentFormDialog.incidentTypeKey, 'Injury');
    await _choose(tester, SafetyIncidentFormDialog.severityKey, 'First aid');
    await tester.enterText(
      find.byKey(SafetyIncidentFormDialog.descriptionKey),
      'Cut a finger on a burr while deburring a part.',
    );
    await tester.pump();

    // The optional Asset, chosen from the Site's own register.
    await pickSuggestion(
      tester,
      fieldKey: SafetyIncidentFormDialog.assetFieldKey(),
      term: 'Press',
      suggestionKey: SafetyIncidentFormDialog.assetSuggestionKey('1'),
    );
    expect(searchFieldText(tester, SafetyIncidentFormDialog.assetFieldKey()), 'Press 1 (PRESS-1)');

    // The Org Unit comes first now (issue #224): naming the injured Employee
    // is part of the injury classification, so the picker is offered only once
    // an Org Unit is chosen AND the caller holds Safety authority there — it
    // cannot exist before there is an Org Unit to ask about.
    await tapIn(tester, find.byKey(OrgUnitChooser.chooseKey('10')));
    expect(find.byKey(SafetyIncidentFormDialog.chosenOrgUnitKey), findsOneWidget);

    // The optional injured Employee.
    await pickSuggestion(
      tester,
      fieldKey: SafetyIncidentFormDialog.employeeFieldKey(),
      term: 'Alice',
      suggestionKey: SafetyIncidentFormDialog.employeeSuggestionKey('7'),
    );
    expect(searchFieldText(tester, SafetyIncidentFormDialog.employeeFieldKey()), 'Alice Nguyen');

    expect(wire.safetyIncidentPosts, isEmpty);
    await tapIn(tester, find.byKey(SafetyIncidentFormDialog.submitKey));

    expect(wire.safetyIncidentPosts, hasLength(1));
    final body = wire.safetyIncidentPosts.single;
    expect(body['orgUnitId'], '10');
    expect(body['incidentType'], 'injury');
    expect(body['severityLevel'], 'first_aid');
    expect(body['description'], 'Cut a finger on a burr while deburring a part.');
    expect(body['assetId'], '1');
    expect(body['employeeId'], '7');
    // occurredAt is required and defaults to now — a real timestamp is always
    // sent, without a test having to drive the date-time picker.
    expect(body.containsKey('occurredAt'), isTrue);
    expect(body['occurredAt'], isA<String>());
    // Not chosen; not sent.
    expect(body.containsKey('immediateAction'), isFalse);
    expect(body.containsKey('reportedAt'), isFalse);

    // The form closes on success and the register re-reads, showing the row
    // the server answered with.
    expect(find.byKey(SafetyIncidentFormDialog.submitKey), findsNothing);
    expect(find.text('SI-HCM-2026-01000'), findsOneWidget);
  });

  testWidgets('recording needs at least an incident type, severity, description, occurredAt and '
      'Org Unit before it may be submitted', (tester) async {
    final wire = _wire();
    await _pump(tester, wire);
    await tapIn(tester, find.byKey(SafetyIncidentsScreen.recordKey));

    expect(
      tester.widget<FilledButton>(find.byKey(SafetyIncidentFormDialog.submitKey)).onPressed,
      isNull,
    );

    await _choose(tester, SafetyIncidentFormDialog.incidentTypeKey, 'Injury');
    await _choose(tester, SafetyIncidentFormDialog.severityKey, 'First aid');
    await tester.enterText(find.byKey(SafetyIncidentFormDialog.descriptionKey), 'x');
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byKey(SafetyIncidentFormDialog.submitKey)).onPressed,
      isNull,
    );

    await tapIn(tester, find.byKey(OrgUnitChooser.chooseKey('10')));
    expect(
      tester.widget<FilledButton>(find.byKey(SafetyIncidentFormDialog.submitKey)).onPressed,
      isNotNull,
    );
  });

  testWidgets('a refused recording keeps the form open with its values and shows the refusal',
      (tester) async {
    final wire = _wire();
    wire.createSafetyIncidentStatus = 403;
    wire.createSafetyIncidentMessage = "Outside the caller's granted Org Units";
    await _pump(tester, wire);

    await tapIn(tester, find.byKey(SafetyIncidentsScreen.recordKey));
    await _choose(tester, SafetyIncidentFormDialog.incidentTypeKey, 'Injury');
    await _choose(tester, SafetyIncidentFormDialog.severityKey, 'First aid');
    await tester.enterText(
      find.byKey(SafetyIncidentFormDialog.descriptionKey),
      'A refused recording.',
    );
    await tester.pump();
    await tapIn(tester, find.byKey(OrgUnitChooser.chooseKey('10')));
    await tapIn(tester, find.byKey(SafetyIncidentFormDialog.submitKey));

    expect(find.byKey(SafetyIncidentFormDialog.failureKey), findsOneWidget);
    expect(find.text("Outside the caller's granted Org Units"), findsOneWidget);
    expect(find.byKey(SafetyIncidentFormDialog.submitKey), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byKey(SafetyIncidentFormDialog.descriptionKey)).controller!.text,
      'A refused recording.',
    );
  });

  // -------------------------------------------------------------------------
  // The detail Screen
  // -------------------------------------------------------------------------

  testWidgets('the detail Screen reads one incident by its own address', (tester) async {
    final wire = _wire();
    await _pump(tester, wire, location: '/safety/incidents/901');

    expect(find.text('SI-HCM-2026-00001'), findsOneWidget);
    expect(_textOf(tester, SafetyIncidentDetailScreen.statusKey), 'Open');
    expect(_textOf(tester, SafetyIncidentDetailScreen.severityKey), 'Medical treatment');
    expect(find.text('Recordable'), findsOneWidget);
    expect(find.text('Caught a hand at the press.'), findsOneWidget);
    expect(
      _textOf(tester, SafetyIncidentDetailScreen.filedKey),
      '2026-04-06 · Day shift',
    );

    await tapIn(tester, find.byKey(SafetyIncidentDetailScreen.backKey));
    expect(find.byKey(SafetyIncidentsScreen.rowKey('901')), findsOneWidget);
  });

  testWidgets('an unknown Safety incident address renders the not-found state', (tester) async {
    final wire = _wire();
    await _pump(tester, wire, location: '/safety/incidents/999999999');

    expect(find.byKey(SafetyIncidentDetailScreen.missingKey), findsOneWidget);
    await tapIn(tester, find.byKey(SafetyIncidentDetailScreen.backKey));
    expect(find.byKey(SafetyIncidentsScreen.rowKey('901')), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // The Destination
  // -------------------------------------------------------------------------

  testWidgets('the Incidents Destination is offered under the Safety group', (tester) async {
    final wire = _wire();
    await _pump(tester, wire);

    expect(
      platformDestinations.any(
        (destination) => destination.path == '/safety/incidents' && destination.group == 'Safety',
      ),
      isTrue,
    );
    expect(find.text('SAFETY'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('nav-item-Incidents')), findsOneWidget);
  });
}
