/// The Safety observation surface, driven through the router against a
/// faked wire (issue #230) — the same seam `safety_incidents_test.dart`
/// uses: `pumpApp` with a `FakeWire`, act through `WidgetTester`, and assert
/// on what renders and on the requests the Screen actually sent.
///
/// Covers the ticket's three Screens and the requests behind them: the
/// register with its filters and its worst-first order, one observation's
/// detail, and the record form.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/maintenance/org_unit_chooser.dart';
import 'package:lean_platform/safety/observation_detail_screen.dart';
import 'package:lean_platform/safety/observation_form_dialog.dart';
import 'package:lean_platform/safety/observations_screen.dart';

import 'harness.dart';

/// The wire every test in this file starts from: one Site, one area with a
/// line beneath it, and three Safety observations spanning three severity
/// potentials, so the worst-first order is a real claim rather than
/// coincidence with insertion order.
FakeWire _wire() => FakeWire(
      orgUnitScope: {
        'everywhere': false,
        'grants': [scopeGrantJson('10', canWrite: true)],
      },
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [orgUnitJson('10', 'Assembly')],
        '10': [orgUnitJson('11', 'Line 1', parentId: '10', unitType: 'line')],
      },
      safetyObservations: {
        '1': [
          safetyObservationJson(
            '701',
            observationType: 'unsafe_condition',
            category: 'housekeeping',
            severityPotential: 'low',
            orgUnitId: '10',
            orgUnitName: 'Assembly',
            description: 'A trip hazard on the floor.',
            observedAt: '2026-06-01T08:00:00Z',
            productionDate: '2026-06-01',
            shiftCode: 'DAY',
            shiftName: 'Day shift',
          ),
          safetyObservationJson(
            '702',
            observationType: 'unsafe_act',
            category: 'working_at_height',
            severityPotential: 'fatal',
            orgUnitId: '11',
            orgUnitName: 'Line 1',
            description: 'Working at height with no harness.',
            isStopWork: true,
            observedAt: '2026-06-01T09:00:00Z',
            productionDate: '2026-06-01',
            shiftCode: 'DAY',
            shiftName: 'Day shift',
          ),
          safetyObservationJson(
            '703',
            observationType: 'unsafe_act',
            category: 'machine_guarding',
            severityPotential: 'medium',
            orgUnitId: '10',
            orgUnitName: 'Assembly',
            description: 'A guard was left open briefly.',
            observedAt: '2026-06-01T10:00:00Z',
          ),
        ],
      },
    );

Future<void> _pump(
  WidgetTester tester,
  FakeWire wire, {
  String location = '/safety/observations',
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

  testWidgets('the register lists a Site\'s observations worst-first by severity potential',
      (tester) async {
    final wire = _wire();
    await _pump(tester, wire);

    expect(wire.safetyObservationListRequests, isNotEmpty);

    // Worst-first: fatal (702), then medium (703), then low (701) — the
    // server's own order, which this wire's fixture reproduces (it does not
    // arrive in that order from the fixture list itself).
    final rowOrder = [
      tester.getTopLeft(find.byKey(SafetyObservationsScreen.rowKey('702'))).dy,
      tester.getTopLeft(find.byKey(SafetyObservationsScreen.rowKey('703'))).dy,
      tester.getTopLeft(find.byKey(SafetyObservationsScreen.rowKey('701'))).dy,
    ];
    expect(rowOrder, List<double>.from(rowOrder)..sort(), reason: 'rows should be worst-first');

    expect(_textOf(tester, SafetyObservationsScreen.rowPotentialKey('702')), 'Fatal');
    expect(find.byKey(SafetyObservationsScreen.rowStopWorkKey('702')), findsOneWidget);
    // Stop-work is its own badge, not folded into a low-severity row.
    expect(find.byKey(SafetyObservationsScreen.rowStopWorkKey('701')), findsNothing);
    expect(
      _textOf(tester, SafetyObservationsScreen.rowFiledKey('702')),
      'Line 1 · filed against 2026-06-01 · Day shift',
    );
  });

  testWidgets(
      'a Site with no observations recorded says the leading indicator is empty, and still '
      'offers the record form', (tester) async {
    final empty = FakeWire(
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [orgUnitJson('10', 'Assembly')],
      },
    );
    await _pump(tester, empty);

    expect(find.byKey(SafetyObservationsScreen.emptyKey), findsOneWidget);
    expect(
      find.text('No observations recorded. The leading indicator is empty.'),
      findsOneWidget,
    );
    expect(find.byKey(SafetyObservationsScreen.recordKey), findsOneWidget);
  });

  testWidgets(
      'the register narrows by Org Unit (and beneath it), type, category, potential, stop-work '
      'and date range, sending exactly the query the address takes', (tester) async {
    final wire = _wire();
    await _pump(tester, wire);

    await _choose(tester, SafetyObservationsScreen.typeFilterKey, 'Unsafe act');
    expect(wire.safetyObservationListRequests.last, {'observationType': 'unsafe_act'});

    await _choose(tester, SafetyObservationsScreen.categoryFilterKey, 'Machine guarding');
    expect(wire.safetyObservationListRequests.last, {
      'observationType': 'unsafe_act',
      'category': 'machine_guarding',
    });

    await _choose(tester, SafetyObservationsScreen.severityPotentialFilterKey, 'Medium');
    expect(wire.safetyObservationListRequests.last, {
      'observationType': 'unsafe_act',
      'category': 'machine_guarding',
      'severityPotential': 'medium',
    });

    await _choose(tester, SafetyObservationsScreen.stopWorkFilterKey, 'Not stop-work');
    expect(wire.safetyObservationListRequests.last, {
      'observationType': 'unsafe_act',
      'category': 'machine_guarding',
      'severityPotential': 'medium',
      'isStopWork': 'false',
    });

    await pickDate(tester, SafetyObservationsScreen.fromDateKey, DateTime(2026, 6, 1));
    expect(wire.safetyObservationListRequests.last, {
      'observationType': 'unsafe_act',
      'category': 'machine_guarding',
      'severityPotential': 'medium',
      'isStopWork': 'false',
      'from': '2026-06-01',
    });

    // The Org Unit filter names one area, and the server includes everything
    // beneath it — the ticket's own criterion.
    await tapIn(tester, find.byKey(SafetyObservationsScreen.orgUnitFilterKey));
    await tapIn(tester, find.byKey(OrgUnitChooser.chooseKey('10')));
    expect(wire.safetyObservationListRequests.last, {
      'observationType': 'unsafe_act',
      'category': 'machine_guarding',
      'severityPotential': 'medium',
      'isStopWork': 'false',
      'from': '2026-06-01',
      'orgUnitId': '10',
    });

    await tapIn(tester, find.byKey(SafetyObservationsScreen.clearFiltersKey));
    expect(wire.safetyObservationListRequests.last, isEmpty);
    expect(find.byKey(SafetyObservationsScreen.rowKey('701')), findsOneWidget);
  });

  testWidgets(
      'the register can be filtered to observations with no Action against them, so a walk\'s '
      'unanswered items are findable (issue #231)', (tester) async {
    final wire = FakeWire(
      orgUnitScope: {
        'everywhere': false,
        'grants': [scopeGrantJson('10', canWrite: true)],
      },
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {null: [orgUnitJson('10', 'Assembly')]},
      safetyObservations: {
        '1': [
          safetyObservationJson(
            '701',
            severityPotential: 'fatal',
            orgUnitId: '10',
            orgUnitName: 'Assembly',
            description: 'Already answered.',
            actions: [
              safetyObservationActionJson(
                actionJson('501', 'AC-HCM-2026-00001', 'Fix it', status: 'open'),
              ),
            ],
          ),
          safetyObservationJson(
            '702',
            severityPotential: 'medium',
            orgUnitId: '10',
            orgUnitName: 'Assembly',
            description: 'Nobody has followed up.',
          ),
        ],
      },
    );
    await _pump(tester, wire);

    expect(find.byKey(SafetyObservationsScreen.rowKey('701')), findsOneWidget);
    expect(find.byKey(SafetyObservationsScreen.rowKey('702')), findsOneWidget);

    await _choose(tester, SafetyObservationsScreen.hasActionFilterKey, 'No Action raised');
    expect(wire.safetyObservationListRequests.last, {'hasAction': 'false'});
    expect(find.byKey(SafetyObservationsScreen.rowKey('701')), findsNothing);
    expect(find.byKey(SafetyObservationsScreen.rowKey('702')), findsOneWidget);

    await _choose(tester, SafetyObservationsScreen.hasActionFilterKey, 'Action raised');
    expect(wire.safetyObservationListRequests.last, {'hasAction': 'true'});
    expect(find.byKey(SafetyObservationsScreen.rowKey('701')), findsOneWidget);
    expect(find.byKey(SafetyObservationsScreen.rowKey('702')), findsNothing);
  });

  // -------------------------------------------------------------------------
  // Recording
  // -------------------------------------------------------------------------

  testWidgets('recording sends exactly what was chosen, chosen from the known sets', (tester) async {
    final wire = _wire();
    await _pump(tester, wire);
    await tapIn(tester, find.byKey(SafetyObservationsScreen.recordKey));

    await _choose(tester, SafetyObservationFormDialog.typeKey, 'Unsafe act');
    await _choose(tester, SafetyObservationFormDialog.categoryKey, 'PPE');
    await _choose(tester, SafetyObservationFormDialog.severityPotentialKey, 'High');
    await tester.enterText(
      find.byKey(SafetyObservationFormDialog.descriptionKey),
      'No gloves worn while handling sheet metal.',
    );
    await tester.pump();
    await tapIn(tester, find.byKey(OrgUnitChooser.chooseKey('10')));
    await tapIn(tester, find.byKey(SafetyObservationFormDialog.submitKey));

    final body = wire.safetyObservationPosts.single;
    expect(body['orgUnitId'], '10');
    expect(body['observationType'], 'unsafe_act');
    expect(body['category'], 'ppe');
    expect(body['severityPotential'], 'high');
    expect(body['description'], 'No gloves worn while handling sheet metal.');
    expect(body['isStopWork'], false);
    // Not chosen; not sent.
    expect(body.containsKey('actionTaken'), isFalse);
    expect(body.containsKey('observedAt'), isFalse);

    // The form closes on success and the register re-reads, showing the row
    // the server answered with.
    expect(find.byKey(SafetyObservationFormDialog.submitKey), findsNothing);
  });

  testWidgets('stop-work and the action taken are sent when chosen', (tester) async {
    final wire = _wire();
    await _pump(tester, wire);
    await tapIn(tester, find.byKey(SafetyObservationsScreen.recordKey));

    await _choose(tester, SafetyObservationFormDialog.typeKey, 'Unsafe condition');
    await _choose(tester, SafetyObservationFormDialog.categoryKey, 'Energy isolation');
    await _choose(tester, SafetyObservationFormDialog.severityPotentialKey, 'Fatal');
    await tester.enterText(
      find.byKey(SafetyObservationFormDialog.descriptionKey),
      'A technician stopped work on a machine with a failed lockout.',
    );
    await tester.enterText(
      find.byKey(SafetyObservationFormDialog.actionTakenKey),
      'Machine isolated and tagged out.',
    );
    await tester.tap(find.byKey(SafetyObservationFormDialog.stopWorkKey));
    await tester.pump();
    await tapIn(tester, find.byKey(OrgUnitChooser.chooseKey('10')));
    await tapIn(tester, find.byKey(SafetyObservationFormDialog.submitKey));

    final body = wire.safetyObservationPosts.single;
    expect(body['isStopWork'], true);
    expect(body['actionTaken'], 'Machine isolated and tagged out.');
  });

  testWidgets(
      'recording needs at least a type, category, potential, description and Org Unit before '
      'it may be submitted', (tester) async {
    final wire = _wire();
    await _pump(tester, wire);
    await tapIn(tester, find.byKey(SafetyObservationsScreen.recordKey));

    expect(
      tester.widget<FilledButton>(find.byKey(SafetyObservationFormDialog.submitKey)).onPressed,
      isNull,
    );

    await _choose(tester, SafetyObservationFormDialog.typeKey, 'Safe act');
    await _choose(tester, SafetyObservationFormDialog.categoryKey, 'Other');
    await _choose(tester, SafetyObservationFormDialog.severityPotentialKey, 'Low');
    await tester.enterText(find.byKey(SafetyObservationFormDialog.descriptionKey), 'x');
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byKey(SafetyObservationFormDialog.submitKey)).onPressed,
      isNull,
    );

    await tapIn(tester, find.byKey(OrgUnitChooser.chooseKey('10')));
    expect(
      tester.widget<FilledButton>(find.byKey(SafetyObservationFormDialog.submitKey)).onPressed,
      isNotNull,
    );
  });

  testWidgets('a refused recording keeps the form open with its values and shows the refusal',
      (tester) async {
    final wire = _wire();
    wire.createSafetyObservationStatus = 403;
    wire.createSafetyObservationMessage = "Outside the caller's granted Org Units";
    await _pump(tester, wire);

    await tapIn(tester, find.byKey(SafetyObservationsScreen.recordKey));
    await _choose(tester, SafetyObservationFormDialog.typeKey, 'Unsafe act');
    await _choose(tester, SafetyObservationFormDialog.categoryKey, 'Traffic');
    await _choose(tester, SafetyObservationFormDialog.severityPotentialKey, 'Medium');
    await tester.enterText(
      find.byKey(SafetyObservationFormDialog.descriptionKey),
      'A refused recording.',
    );
    await tester.pump();
    await tapIn(tester, find.byKey(OrgUnitChooser.chooseKey('10')));
    await tapIn(tester, find.byKey(SafetyObservationFormDialog.submitKey));

    expect(find.byKey(SafetyObservationFormDialog.failureKey), findsOneWidget);
    expect(find.text("Outside the caller's granted Org Units"), findsOneWidget);
    expect(find.byKey(SafetyObservationFormDialog.submitKey), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(SafetyObservationFormDialog.descriptionKey))
          .controller!
          .text,
      'A refused recording.',
    );
  });

  // -------------------------------------------------------------------------
  // The detail Screen
  // -------------------------------------------------------------------------

  testWidgets('the detail Screen reads one observation by its own address', (tester) async {
    final wire = _wire();
    await _pump(tester, wire, location: '/safety/observations/702');

    expect(find.text('Unsafe act'), findsWidgets);
    expect(_textOf(tester, SafetyObservationDetailScreen.potentialKey), 'Fatal');
    expect(find.byKey(SafetyObservationDetailScreen.stopWorkKey), findsOneWidget);
    expect(find.text('Working at height with no harness.'), findsOneWidget);
    expect(
      _textOf(tester, SafetyObservationDetailScreen.filedKey),
      '2026-06-01 · Day shift',
    );

    await tapIn(tester, find.byKey(SafetyObservationDetailScreen.backKey));
    expect(find.byKey(SafetyObservationsScreen.rowKey('702')), findsOneWidget);
  });

  testWidgets('an unknown Safety observation address renders the not-found state', (tester) async {
    final wire = _wire();
    await _pump(tester, wire, location: '/safety/observations/999999999');

    expect(find.byKey(SafetyObservationDetailScreen.missingKey), findsOneWidget);
    await tapIn(tester, find.byKey(SafetyObservationDetailScreen.backKey));
    expect(find.byKey(SafetyObservationsScreen.rowKey('701')), findsOneWidget);
  });

  testWidgets('an observation has no status, resolution or closure anywhere on the detail Screen',
      (tester) async {
    final wire = _wire();
    await _pump(tester, wire, location: '/safety/observations/701');

    // #223 decision 9: an observation is a fact, and nothing on this Screen
    // offers to change its state.
    expect(find.textContaining('Status'), findsNothing);
    expect(find.textContaining('Closed'), findsNothing);
    expect(find.textContaining('Resolution'), findsNothing);
  });
}
