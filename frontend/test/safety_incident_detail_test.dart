/// Making a recorded Safety incident answerable (issue #228), driven through
/// the router against a faked wire — the same seam
/// `nonconformance_dispositions_test.dart` uses for the equivalent Quality
/// slice: `pumpApp` with a `FakeWire`, act through `WidgetTester`, and assert
/// on what renders and on the requests the Screen actually sent.
///
/// What this file proves, beyond each dialog doing its own job: the detail
/// shows the event history; the investigation due date and the ordinary
/// status move are offered to anyone with an edit Grant; and the three
/// decisions Safety authority gates — correcting the severity, recording the
/// days, and closing — are **not offered** to a caller who does not hold it,
/// and **no request is sent** when they are missing (ADR-0039, #223 decision
/// 4 and 5).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:lean_platform/safety/incident_close_dialog.dart';
import 'package:lean_platform/safety/incident_days_dialog.dart';
import 'package:lean_platform/safety/incident_detail_screen.dart';
import 'package:lean_platform/safety/incident_severity_dialog.dart';
import 'package:lean_platform/safety/incident_status_dialog.dart';

import 'harness.dart';

/// The wire every test in this file starts from: one Site, one area, and
/// three Safety incidents — one open at `first_aid`, one `investigating`
/// above the no-injury rung with its days already settled, and one closed.
///
/// [safety] is what the caller's own Grant carries: `safetyAuthority` is the
/// flag ADR-0039 puts beside the level, and every test that asserts a
/// decision is or is not offered turns on it. When it is false the caller
/// still holds a write Grant reaching the incident's Org Unit, which is what
/// the investigation due date and the ordinary status move need.
FakeWire _wire({bool safety = false}) => FakeWire(
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {null: [orgUnitJson('11', 'Line 1')]},
      orgUnitScope: {
        'everywhere': false,
        'grants': [scopeGrantJson('11', canWrite: true, safetyAuthority: safety)],
      },
      safetyIncidents: {
        '1': [
          safetyIncidentJson(
            '801',
            'SI-HCM-2026-00001',
            severityLevel: 'first_aid',
            orgUnitId: '11',
            orgUnitName: 'Line 1',
          ),
          safetyIncidentJson(
            '802',
            'SI-HCM-2026-00002',
            status: 'investigating',
            severityLevel: 'medical_treatment',
            orgUnitId: '11',
            orgUnitName: 'Line 1',
            events: [
              safetyIncidentEventJson(
                '802-e1',
                kind: 'status',
                previousValue: 'open',
                newValue: 'investigating',
                changedByAccountName: 'Ann Operator',
              ),
              safetyIncidentEventJson(
                '802-e2',
                kind: 'days',
                previousValue: 'lostTimeDays=0,restrictedDays=0',
                newValue: 'lostTimeDays=0,restrictedDays=2',
                changedByAccountName: 'Sam Safety',
              ),
            ],
          ),
          safetyIncidentJson(
            '803',
            'SI-HCM-2026-00003',
            status: 'closed',
            incidentType: 'near_miss',
            severityLevel: 'near_miss',
            closedAt: '2026-04-07T09:30:00.000Z',
            orgUnitId: '11',
            orgUnitName: 'Line 1',
            events: [
              safetyIncidentEventJson(
                '803-e1',
                kind: 'closure',
                previousValue: 'open',
                newValue: 'closed',
                note: 'Nobody was hurt; closing.',
                changedByAccountName: 'Sam Safety',
              ),
            ],
          ),
        ],
      },
    );

Future<void> _pump(
  WidgetTester tester,
  FakeWire wire, {
  String location = '/safety/incidents/801',
}) async {
  // Pinned taller than the default 800x600: the detail's lower sections are
  // simply not in the tree at 600px, and `find.byKey` fails on a row a lazy
  // `ListView` has not built yet.
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(800, 2200);
  addTearDown(tester.view.reset);

  await pumpApp(
    tester,
    gateway: FakeAuthGateway(accessToken: 'a-token'),
    client: wire.client,
    initialLocation: location,
  );
}

String _rowText(WidgetTester tester, Key key) => tester
    .widgetList<Text>(find.descendant(of: find.byKey(key), matching: find.byType(Text)))
    .map((text) => text.data ?? '')
    .join(' · ');

/// Navigate to an address the way a refresh does — `go`, not a tap. The
/// addressed dialogs are reachable only through the Screen's own controls
/// when the caller may not use them, so the only honest way to prove what an
/// address does on its own is to go to it.
Future<void> _go(WidgetTester tester, String address) async {
  final context = tester.element(find.byKey(SafetyIncidentDetailScreen.backKey));
  GoRouter.of(context).go(address);
  await tester.pumpAndSettle();
}

/// One dropdown choice, the way a person makes it: open the field, tap the
/// option — mirrors `nonconformance_dispositions_test.dart`'s own `_choose`.
Future<void> _choose(WidgetTester tester, Key fieldKey, String option) async {
  await tapIn(tester, find.byKey(fieldKey));
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

void main() {
  // -------------------------------------------------------------------------
  // The event history
  // -------------------------------------------------------------------------

  testWidgets('the detail shows the event history a record carries', (tester) async {
    final wire = _wire(safety: true);
    await _pump(tester, wire, location: '/safety/incidents/802');

    final statusEvent = _rowText(tester, SafetyIncidentDetailScreen.eventRowKey('802-e1'));
    expect(statusEvent, contains('Status moved from Open to Investigating'));
    expect(statusEvent, contains('Ann Operator'));

    final daysEvent = _rowText(tester, SafetyIncidentDetailScreen.eventRowKey('802-e2'));
    expect(daysEvent, contains('Days recorded'));
    expect(daysEvent, contains('Sam Safety'));
  });

  testWidgets('a record nothing has changed about says so', (tester) async {
    final wire = _wire();
    await _pump(tester, wire);

    expect(find.byKey(SafetyIncidentDetailScreen.noEventsKey), findsOneWidget);
    expect(find.byKey(SafetyIncidentDetailScreen.eventsKey), findsNothing);
  });

  testWidgets('a closed incident shows its closure in the history, with the note', (tester) async {
    final wire = _wire(safety: true);
    await _pump(tester, wire, location: '/safety/incidents/803');

    final closure = _rowText(tester, SafetyIncidentDetailScreen.eventRowKey('803-e1'));
    expect(closure, contains('Closed'));
    expect(closure, contains('Sam Safety'));
    expect(closure, contains('Nobody was hurt; closing.'));
    expect(find.byKey(SafetyIncidentDetailScreen.closedKey), findsOneWidget);
  });

  testWidgets('a classification change shows in the history, with who and when (issue #224)',
      (tester) async {
    final wire = FakeWire(
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {null: [orgUnitJson('11', 'Line 1')]},
      orgUnitScope: {
        'everywhere': false,
        'grants': [scopeGrantJson('11', canWrite: true, safetyAuthority: true)],
      },
      safetyIncidents: {
        '1': [
          safetyIncidentJson(
            '804',
            'SI-HCM-2026-00004',
            severityLevel: 'first_aid',
            orgUnitId: '11',
            orgUnitName: 'Line 1',
            events: [
              safetyIncidentEventJson(
                '804-e1',
                kind: 'classification',
                previousValue: 'employeeId=none,injuryType=none,bodyPart=none',
                newValue: 'employeeId=42,injuryType=FRACTURE,bodyPart=LEFT_HAND',
                changedByAccountName: 'Sam Safety',
              ),
            ],
          ),
        ],
      },
    );
    await _pump(tester, wire, location: '/safety/incidents/804');

    final classification = _rowText(tester, SafetyIncidentDetailScreen.eventRowKey('804-e1'));
    expect(classification, contains('Classified'));
    expect(classification, contains('Sam Safety'));
  });

  // -------------------------------------------------------------------------
  // The investigation due date and the ordinary status move — an edit Grant
  // is enough, and the Screen offers both without asking about authority.
  // -------------------------------------------------------------------------

  testWidgets('an edit Grant is enough for the due date and the status move on an open incident',
      (tester) async {
    final wire = _wire();
    await _pump(tester, wire);

    expect(find.byKey(SafetyIncidentDetailScreen.dueDateKey), findsOneWidget);
    expect(find.byKey(SafetyIncidentDetailScreen.moveStatusKey), findsOneWidget);
  });

  testWidgets('neither the due date nor the status move is offered once the incident is closed',
      (tester) async {
    final wire = _wire();
    await _pump(tester, wire, location: '/safety/incidents/803');

    expect(find.byKey(SafetyIncidentDetailScreen.dueDateKey), findsNothing);
    expect(find.byKey(SafetyIncidentDetailScreen.moveStatusKey), findsNothing);
  });

  testWidgets('the status move is refused by its own address once the incident is closed',
      (tester) async {
    final wire = _wire();
    await _pump(tester, wire, location: '/safety/incidents/803');
    await _go(tester, '/safety/incidents/803/status');

    expect(find.byKey(SafetyIncidentStatusDialog.refusedKey), findsOneWidget);
    expect(find.byKey(SafetyIncidentStatusDialog.submitKey), findsNothing);
    expect(wire.safetyIncidentStatusPosts, isEmpty);
  });

  testWidgets('moving the status is sent by address, and the record comes back with the change',
      (tester) async {
    final wire = _wire();
    await _pump(tester, wire);

    await tester.tap(find.byKey(SafetyIncidentDetailScreen.moveStatusKey));
    await tester.pumpAndSettle();
    expect(find.text('Move to Investigating'), findsWidgets);

    await tester.tap(find.byKey(SafetyIncidentStatusDialog.submitKey));
    await tester.pumpAndSettle();

    expect(wire.safetyIncidentStatusPosts, hasLength(1));
    expect(wire.safetyIncidentStatusPosts.single.$2['status'], 'investigating');
    expect(find.byKey(SafetyIncidentDetailScreen.statusKey), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // The three decisions Safety authority gates
  // -------------------------------------------------------------------------

  testWidgets(
      'without Safety authority, correcting the severity, recording the days and closing are '
      'not offered, and nothing is sent', (tester) async {
    final wire = _wire();
    await _pump(tester, wire, location: '/safety/incidents/802');

    // A write Grant reaching the Org Unit is enough for the due date and the
    // ordinary status move...
    expect(find.byKey(SafetyIncidentDetailScreen.dueDateKey), findsOneWidget);
    expect(find.byKey(SafetyIncidentDetailScreen.moveStatusKey), findsOneWidget);
    // ...and is not enough for any of the three decisions (ADR-0039 keeps
    // Safety authority independent of `canWrite`).
    expect(find.byKey(SafetyIncidentDetailScreen.changeSeverityKey), findsNothing);
    expect(find.byKey(SafetyIncidentDetailScreen.recordDaysKey), findsNothing);
    expect(find.byKey(SafetyIncidentDetailScreen.closeKey), findsNothing);

    // And nothing was asked of the API for any of them.
    expect(wire.safetyIncidentSeverityPosts, isEmpty);
    expect(wire.safetyIncidentDaysPosts, isEmpty);
    expect(wire.safetyIncidentClosePosts, isEmpty);
  });

  testWidgets('a holder of Safety authority is offered the severity correction, the days and the close',
      (tester) async {
    final wire = _wire(safety: true);
    await _pump(tester, wire, location: '/safety/incidents/802');

    expect(find.byKey(SafetyIncidentDetailScreen.changeSeverityKey), findsOneWidget);
    expect(find.byKey(SafetyIncidentDetailScreen.recordDaysKey), findsOneWidget);
    expect(find.byKey(SafetyIncidentDetailScreen.closeKey), findsOneWidget);
  });

  testWidgets(
      'a closed incident still offers the severity correction to a holder of authority — #223 '
      "decision 5's own exception — but not the days or the close", (tester) async {
    // #223 decision 5: correcting a severity restates the period it occurred
    // in, and routinely comes after the incident it corrects has closed — so
    // this is the one decision still offered once closed.
    final wire = _wire(safety: true);
    await _pump(tester, wire, location: '/safety/incidents/803');

    expect(find.byKey(SafetyIncidentDetailScreen.changeSeverityKey), findsOneWidget);
    expect(find.byKey(SafetyIncidentDetailScreen.recordDaysKey), findsNothing);
    expect(find.byKey(SafetyIncidentDetailScreen.closeKey), findsNothing);
  });

  testWidgets('the severity dialog reached by its own address without Safety authority says why, '
      'and sends nothing', (tester) async {
    final wire = _wire();
    // A refresh lands on the address, so the address itself has to refuse —
    // the Screen's own omission is not the only guard (ADR-0021).
    await _pump(tester, wire, location: '/safety/incidents/802');
    await _go(tester, '/safety/incidents/802/severity');

    expect(find.byKey(SafetyIncidentSeverityDialog.refusedKey), findsOneWidget);
    expect(find.textContaining('needs Safety authority'), findsOneWidget);
    expect(find.byKey(SafetyIncidentSeverityDialog.submitKey), findsNothing);
    expect(wire.safetyIncidentSeverityPosts, isEmpty);
  });

  testWidgets('the close dialog reached by its own address without Safety authority says why, '
      'and sends nothing', (tester) async {
    final wire = _wire();
    await _pump(tester, wire, location: '/safety/incidents/802');
    await _go(tester, '/safety/incidents/802/close');

    expect(find.byKey(SafetyIncidentCloseDialog.refusedKey), findsOneWidget);
    expect(find.textContaining('needs Safety authority'), findsOneWidget);
    expect(find.byKey(SafetyIncidentCloseDialog.submitKey), findsNothing);
    expect(wire.safetyIncidentClosePosts, isEmpty);
  });

  testWidgets('the days dialog reached by its own address without Safety authority says why, '
      'and sends nothing', (tester) async {
    final wire = _wire();
    await _pump(tester, wire, location: '/safety/incidents/802');
    await _go(tester, '/safety/incidents/802/days');

    expect(find.byKey(SafetyIncidentDaysDialog.refusedKey), findsOneWidget);
    expect(find.byKey(SafetyIncidentDaysDialog.submitKey), findsNothing);
    expect(wire.safetyIncidentDaysPosts, isEmpty);
  });

  testWidgets('the close dialog refuses an already-closed incident, even to a holder of authority',
      (tester) async {
    final wire = _wire(safety: true);
    await _pump(tester, wire, location: '/safety/incidents/803');
    await _go(tester, '/safety/incidents/803/close');

    expect(find.byKey(SafetyIncidentCloseDialog.refusedKey), findsOneWidget);
    expect(find.textContaining('already closed'), findsOneWidget);
    expect(wire.safetyIncidentClosePosts, isEmpty);
  });

  // -------------------------------------------------------------------------
  // The three decisions, exercised end to end by a holder of Safety authority
  // -------------------------------------------------------------------------

  testWidgets('correcting the severity is sent with a note, by address', (tester) async {
    final wire = _wire(safety: true);
    await _pump(tester, wire, location: '/safety/incidents/801');

    await tester.tap(find.byKey(SafetyIncidentDetailScreen.changeSeverityKey));
    await tester.pumpAndSettle();

    // No note yet: the submit is disabled.
    await tester.tap(find.byKey(SafetyIncidentSeverityDialog.submitKey));
    await tester.pumpAndSettle();
    expect(wire.safetyIncidentSeverityPosts, isEmpty);

    await _choose(tester, SafetyIncidentSeverityDialog.severityKey, 'Lost time');
    await tester.enterText(
      find.byKey(SafetyIncidentSeverityDialog.noteKey),
      'Turned out to be worse than first thought.',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(SafetyIncidentSeverityDialog.submitKey));
    await tester.pumpAndSettle();

    expect(wire.safetyIncidentSeverityPosts, hasLength(1));
    final (id, sent) = wire.safetyIncidentSeverityPosts.single;
    expect(id, '801');
    expect(sent['severityLevel'], 'lost_time');
    expect(sent['note'], 'Turned out to be worse than first thought.');
  });

  testWidgets('recording the days requires both counts, and sends them by address', (tester) async {
    final wire = _wire(safety: true);
    await _pump(tester, wire, location: '/safety/incidents/802');

    await tester.tap(find.byKey(SafetyIncidentDetailScreen.recordDaysKey));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(SafetyIncidentDaysDialog.lostTimeKey), '0');
    await tester.enterText(find.byKey(SafetyIncidentDaysDialog.restrictedKey), '3');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(SafetyIncidentDaysDialog.submitKey));
    await tester.pumpAndSettle();

    expect(wire.safetyIncidentDaysPosts, hasLength(1));
    final (id, sent) = wire.safetyIncidentDaysPosts.single;
    expect(id, '802');
    expect(sent['lostTimeDays'], 0);
    expect(sent['restrictedDays'], 3);
  });

  testWidgets('closing requires a note, and sends it by address — the record comes back closed',
      (tester) async {
    final wire = _wire(safety: true);
    await _pump(tester, wire, location: '/safety/incidents/801');

    await tester.tap(find.byKey(SafetyIncidentDetailScreen.closeKey));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(SafetyIncidentCloseDialog.submitKey));
    await tester.pumpAndSettle();
    expect(wire.safetyIncidentClosePosts, isEmpty);

    await tester.enterText(
      find.byKey(SafetyIncidentCloseDialog.noteKey),
      'First aid only; nothing further needed.',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(SafetyIncidentCloseDialog.submitKey));
    await tester.pumpAndSettle();

    expect(wire.safetyIncidentClosePosts, hasLength(1));
    final (id, sent) = wire.safetyIncidentClosePosts.single;
    expect(id, '801');
    expect(sent['note'], 'First aid only; nothing further needed.');
    expect(find.byKey(SafetyIncidentDetailScreen.closedKey), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // Closing over an open Concern (#223 decision 4) is a backend behaviour;
  // the client side of it is simply that this Screen never asks about a
  // Concern before offering or sending a close, which the close dialog's own
  // tests above already exercise — there is no additional gate here to prove
  // absent.
  // -------------------------------------------------------------------------
}
