/// Raising a Concern from a Safety incident, and the cross-links it puts on
/// each record — driven through the router against a faked wire (issue #229),
/// at the same seam every other Safety and Actions widget test uses: `pumpApp`
/// with a `FakeWire`, act through `WidgetTester`, and assert on what renders
/// and on the requests the Screen actually sent. The scaffolding mirrors
/// `concern_nonconformances_test.dart` closely — this is the same shape of
/// path, with the Safety incident standing where the Non-conformance stood.
///
/// What this file proves: the incident's detail offers raising a Concern
/// without asking for a Grant, and says when nothing is being done about the
/// cause; raising one sends the title, the note and the priority to the
/// Actions Module's own address, with no `orgUnitId` in the body, because the
/// Concern lands at the incident's own Org Unit; a refusal keeps the dialog
/// open with the server's own sentence; the incident's detail names the
/// Concern raised from it with its status, linking to the Concern's own
/// address; and the Concern's own detail names the incident back — its number
/// and severity, and nothing about who was hurt, because this Module's own
/// read never carries that.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/actions/action_detail_screen.dart';
import 'package:lean_platform/safety/incident_detail_screen.dart';
import 'package:lean_platform/safety/incident_raise_concern_dialog.dart';

import 'harness.dart';

/// One Safety incident as its own detail read returns it, with the Concerns
/// raised from it named the way `toSafetyIncident` sends them.
Map<String, dynamic> _incident({
  String id = '801',
  String incidentNo = 'SI-HCM-2026-00001',
  String severityLevel = 'medical_treatment',
  List<Map<String, dynamic>> concerns = const [],
}) =>
    safetyIncidentJson(
      id,
      incidentNo,
      severityLevel: severityLevel,
      orgUnitId: '11',
      orgUnitName: 'Line 1',
      concerns: concerns,
    );

/// A Concern as the action log sends it — what the raise answers with, and
/// what the Concern Screen renders back.
Map<String, dynamic> _concern({
  String id = '501',
  String actionNo = 'AC-HCM-2026-00001',
  String title = 'The press guard keeps working loose',
  String status = 'open',
  String? ownerName,
  String safetyIncidentId = '801',
  String safetyIncidentNo = 'SI-HCM-2026-00001',
  String severityLevel = 'medical_treatment',
}) =>
    actionJson(
      id,
      actionNo,
      title,
      status: status,
      orgUnitId: '11',
      orgUnitName: 'Line 1',
      ownerName: ownerName,
      description: 'Third time this shift the interlock has been bypassed.',
      sourceSafetyIncidentId: safetyIncidentId,
      safetyIncident: linkedSafetyIncidentJson(
        safetyIncidentId,
        safetyIncidentNo,
        severityLevel: severityLevel,
      ),
    );

/// The wire every test starts from: one Site, one area, and one Safety
/// incident with nothing being done about its cause.
FakeWire _wire({
  List<Map<String, dynamic>> concernsOn801 = const [],
  Map<String, Map<String, dynamic>>? actionDetails,
}) =>
    FakeWire(
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {null: [orgUnitJson('11', 'Line 1')]},
      orgUnitScope: {
        'everywhere': false,
        'grants': [scopeGrantJson('11', canWrite: true)],
      },
      safetyIncidents: {
        '1': [_incident(concerns: concernsOn801)],
      },
      actionDetails: actionDetails ??
          {
            '501': _concern(),
          },
    );

/// Pinned taller than the default 800x600: the Concerns card sits at the foot
/// of a lazy `ListView`, and `find.byKey` on a row it has not built yet fails
/// with "Found 0 widgets" — not a missing feature but a viewport that never
/// reached it.
Future<void> _pump(
  WidgetTester tester,
  FakeWire wire, {
  String location = '/safety/incidents/801',
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(800, 2600);
  addTearDown(tester.view.reset);

  await pumpApp(
    tester,
    gateway: FakeAuthGateway(accessToken: 'a-token'),
    client: wire.client,
    initialLocation: location,
  );
}

/// Every line inside a keyed row, joined — a linked Concern row is several
/// `Text`s, so asserting on one of them would miss half of it.
String _rowText(WidgetTester tester, Key key) => tester
    .widgetList<Text>(find.descendant(of: find.byKey(key), matching: find.byType(Text)))
    .map((text) => text.data ?? '')
    .join(' · ');

String _locationOf(WidgetTester tester, Finder finder) => locationOf(tester, finder);

void main() {
  // -------------------------------------------------------------------------
  // The Safety incident detail Screen (issue #229)
  // -------------------------------------------------------------------------

  testWidgets(
      'the Safety incident detail offers raising a Concern, and says when nothing is being done about the cause',
      (tester) async {
    final wire = _wire();
    await _pump(tester, wire);

    expect(find.byKey(SafetyIncidentDetailScreen.concernsKey), findsOneWidget);
    expect(find.byKey(SafetyIncidentDetailScreen.noConcernsKey), findsOneWidget);
    expect(find.byKey(SafetyIncidentDetailScreen.raiseConcernKey), findsOneWidget);
    expect(wire.safetyConcernRaisePosts, isEmpty);
  });

  testWidgets(
      'raising a Concern from a Safety incident needs no Grant, and offers the control to a caller holding only a read Grant',
      (tester) async {
    // #198's Concern rule, the same one the ticket names for this path: a
    // read-only Grant is enough to see the Site, and the raise control is
    // offered on that alone.
    final wire = FakeWire(
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {null: [orgUnitJson('11', 'Line 1')]},
      orgUnitScope: {
        'everywhere': false,
        'grants': [scopeGrantJson('11', canWrite: false)],
      },
      safetyIncidents: {
        '1': [_incident()],
      },
      actionDetails: {'501': _concern()},
    );
    await _pump(tester, wire);

    expect(find.byKey(SafetyIncidentDetailScreen.raiseConcernKey), findsOneWidget);
  });

  testWidgets(
      'the detail shows the Concern raised from the incident, with its status, and it links to the Concern\'s own address',
      (tester) async {
    final concern = _concern(ownerName: 'Sam Safety');
    final wire = _wire(concernsOn801: [safetyIncidentConcernJson(concern)]);
    await _pump(tester, wire);

    expect(find.byKey(SafetyIncidentDetailScreen.noConcernsKey), findsNothing);
    final row = _rowText(tester, SafetyIncidentDetailScreen.concernRowKey('501'));
    expect(row, contains('The press guard keeps working loose'));
    expect(row, contains('AC-HCM-2026-00001'));
    expect(row, contains('Sam Safety'));
    // The status is the action log's own five words, through the Actions
    // Module's entry point rather than a second copy of the map.
    expect(row, contains('Open'));

    await tapIn(tester, find.byKey(SafetyIncidentDetailScreen.concernRowKey('501')));
    expect(_locationOf(tester, find.byKey(ActionDetailScreen.loadedKey)), '/actions/501');
  });

  testWidgets(
      'raising a Concern sends its title, its note and its priority, and nothing about the Org Unit',
      (tester) async {
    final wire = _wire();
    await _pump(tester, wire);

    await tapIn(tester, find.byKey(SafetyIncidentDetailScreen.raiseConcernKey));
    expect(find.byKey(SafetyIncidentRaiseConcernDialog.titleKey), findsOneWidget);
    // Nothing can be sent until there is a title, which is the one field the
    // Action log's own rules refuse without — the submit button is closed.
    expect(
      tester.widget<FilledButton>(find.byKey(SafetyIncidentRaiseConcernDialog.submitKey)).onPressed,
      isNull,
    );
    expect(wire.safetyConcernRaisePosts, isEmpty);

    await tester.enterText(
      find.byKey(SafetyIncidentRaiseConcernDialog.titleKey),
      'The press guard keeps working loose',
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(SafetyIncidentRaiseConcernDialog.descriptionKey),
      'Third time this shift the interlock has been bypassed.',
    );
    await tester.pump();
    await tapIn(tester, find.byKey(SafetyIncidentRaiseConcernDialog.priorityKey));
    await tapIn(tester, find.text('P2').last);
    await tapIn(tester, find.byKey(SafetyIncidentRaiseConcernDialog.submitKey));

    // One request, to the Action log's own address for raising a Concern from
    // a Safety incident — and no `orgUnitId` in it, because the Concern lands
    // at the incident's own Org Unit.
    expect(wire.safetyConcernRaisePosts.length, 1);
    expect(wire.safetyConcernRaisePosts.single.$1, '801');
    expect(wire.safetyConcernRaisePosts.single.$2, {
      'title': 'The press guard keeps working loose',
      'description': 'Third time this shift the interlock has been bypassed.',
      'priority': 2,
    });
    expect(wire.safetyConcernRaisePosts.single.$2.containsKey('orgUnitId'), isFalse);

    // The dialog has closed and the Screen the raise was made from now names
    // the Concern — read back from the record, not inferred from the answer.
    expect(find.byKey(SafetyIncidentRaiseConcernDialog.submitKey), findsNothing);
    expect(find.byKey(SafetyIncidentDetailScreen.concernNoticeKey), findsOneWidget);
    expect(
      _rowText(tester, SafetyIncidentDetailScreen.concernRowKey('901')),
      contains('AC-TEST-2026-00009'),
    );
  });

  testWidgets(
      'a refused raise keeps the dialog open with the server\'s own sentence, and sends nothing else',
      (tester) async {
    final wire = _wire()
      ..raiseSafetyConcernStatus = 403
      ..raiseSafetyConcernMessage = 'you do not have permission to see this Site';
    await _pump(tester, wire);

    await tapIn(tester, find.byKey(SafetyIncidentDetailScreen.raiseConcernKey));
    await tester.enterText(
      find.byKey(SafetyIncidentRaiseConcernDialog.titleKey),
      'Not mine to raise',
    );
    await tester.pump();
    await tapIn(tester, find.byKey(SafetyIncidentRaiseConcernDialog.submitKey));

    expect(wire.safetyConcernRaisePosts.length, 1);
    expect(find.text('you do not have permission to see this Site'), findsOneWidget);
    // The Screen's own copy of the failure is not a second one: the dialog
    // that asked is still open, holding the sentence, and the form is still
    // usable.
    expect(find.byKey(SafetyIncidentRaiseConcernDialog.submitKey), findsOneWidget);
    expect(find.byKey(SafetyIncidentDetailScreen.noConcernsKey), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // The Concern Screen names the Safety incident back (issue #229)
  // -------------------------------------------------------------------------

  testWidgets(
      'the Concern Screen names the Safety incident it was raised from, with its number and severity, and links to its own address',
      (tester) async {
    final wire = _wire();
    await _pump(tester, wire, location: '/actions/501');

    expect(find.byKey(ActionDetailScreen.safetyIncidentKey), findsOneWidget);
    final row = _rowText(tester, ActionDetailScreen.safetyIncidentKey);
    expect(row, contains('SI-HCM-2026-00001'));
    expect(row, contains('Medical treatment'));

    await tapIn(
      tester,
      find.descendant(
        of: find.byKey(ActionDetailScreen.safetyIncidentKey),
        matching: find.byType(ListTile),
      ),
    );
    expect(
      _locationOf(tester, find.byKey(SafetyIncidentDetailScreen.backKey)),
      '/safety/incidents/801',
    );
  });

  testWidgets(
      'a Concern raised from a Safety incident shows no Non-conformances section — the single-source rule means never both',
      (tester) async {
    final wire = _wire();
    await _pump(tester, wire, location: '/actions/501');

    expect(find.byKey(ActionDetailScreen.nonconformancesKey), findsNothing);
    expect(find.byKey(ActionDetailScreen.noNonconformancesKey), findsNothing);
  });
}
