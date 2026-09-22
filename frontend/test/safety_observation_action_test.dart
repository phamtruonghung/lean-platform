/// Raising an Action from a Safety observation, and the cross-links it puts
/// on each record — driven through the router against a faked wire (issue
/// #231), at the same seam every other Safety and Actions widget test uses:
/// `pumpApp` with a `FakeWire`, act through `WidgetTester`, and assert on what
/// renders and on the requests the Screen actually sent. The scaffolding
/// mirrors `safety_incident_concern_test.dart` closely — this is the same
/// shape of path, with the Safety observation standing where the Safety
/// incident stood.
///
/// What this file proves: the observation's detail offers raising an Action
/// without asking for a Grant, and says when nothing is being done about it;
/// raising one sends the chosen kind, the title, the description and the
/// priority to the Actions Module's own address, with no `orgUnitId` in the
/// body, because the Action lands at the observation's own Org Unit; a
/// refusal keeps the dialog open with the server's own sentence; the
/// observation's detail names the Action raised from it with its status,
/// linking to the Action's own address; and the Action's own detail names the
/// observation back — its type, category and severity potential, and neither
/// a Safety incident nor a Non-conformance section, because the single-source
/// rule means never more than one.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/actions/action_detail_screen.dart';
import 'package:lean_platform/safety/observation_detail_screen.dart';
import 'package:lean_platform/safety/observation_raise_action_dialog.dart';

import 'harness.dart';

/// One Safety observation as its own detail read returns it, with the Actions
/// raised from it named the way `toSafetyObservation` sends them.
Map<String, dynamic> _observation({
  String id = '801',
  String observationType = 'unsafe_condition',
  String category = 'housekeeping',
  String severityPotential = 'high',
  List<Map<String, dynamic>> actions = const [],
}) =>
    safetyObservationJson(
      id,
      observationType: observationType,
      category: category,
      severityPotential: severityPotential,
      orgUnitId: '11',
      orgUnitName: 'Line 1',
      description: 'Pallets stacked against a fire exit.',
      actions: actions,
    );

/// An Action as the action log sends it — what the raise answers with, and
/// what the Action Screen renders back.
Map<String, dynamic> _action({
  String id = '501',
  String actionNo = 'AC-HCM-2026-00001',
  String title = 'Clear the fire exit and re-stack the pallets',
  String actionType = 'containment',
  String status = 'open',
  String? ownerName,
  String safetyObservationId = '801',
  String observationType = 'unsafe_condition',
  String category = 'housekeeping',
  String severityPotential = 'high',
}) =>
    actionJson(
      id,
      actionNo,
      title,
      actionType: actionType,
      status: status,
      orgUnitId: '11',
      orgUnitName: 'Line 1',
      ownerName: ownerName,
      description: 'Immediate containment while a permanent storage fix is found.',
      sourceSafetyObservationId: safetyObservationId,
      safetyObservation: linkedSafetyObservationJson(
        safetyObservationId,
        observationType: observationType,
        category: category,
        severityPotential: severityPotential,
      ),
    );

/// The wire every test starts from: one Site, one area, and one Safety
/// observation with nothing being done about it yet.
FakeWire _wire({
  List<Map<String, dynamic>> actionsOn801 = const [],
  Map<String, Map<String, dynamic>>? actionDetails,
}) =>
    FakeWire(
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {null: [orgUnitJson('11', 'Line 1')]},
      orgUnitScope: {
        'everywhere': false,
        'grants': [scopeGrantJson('11', canWrite: true)],
      },
      safetyObservations: {
        '1': [_observation(actions: actionsOn801)],
      },
      actionDetails: actionDetails ??
          {
            '501': _action(),
          },
    );

/// Pinned taller than the default 800x600: the Actions card sits at the foot
/// of a lazy `ListView`, and `find.byKey` on a row it has not built yet fails
/// with "Found 0 widgets" — not a missing feature but a viewport that never
/// reached it.
Future<void> _pump(
  WidgetTester tester,
  FakeWire wire, {
  String location = '/safety/observations/801',
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

/// Every line inside a keyed row, joined — a linked Action row is several
/// `Text`s, so asserting on one of them would miss half of it.
String _rowText(WidgetTester tester, Key key) => tester
    .widgetList<Text>(find.descendant(of: find.byKey(key), matching: find.byType(Text)))
    .map((text) => text.data ?? '')
    .join(' · ');

String _locationOf(WidgetTester tester, Finder finder) => locationOf(tester, finder);

void main() {
  // -------------------------------------------------------------------------
  // The Safety observation detail Screen (issue #231)
  // -------------------------------------------------------------------------

  testWidgets(
      'the Safety observation detail offers raising an Action, and says when nothing is being done about it',
      (tester) async {
    final wire = _wire();
    await _pump(tester, wire);

    expect(find.byKey(SafetyObservationDetailScreen.actionsKey), findsOneWidget);
    expect(find.byKey(SafetyObservationDetailScreen.noActionsKey), findsOneWidget);
    expect(find.byKey(SafetyObservationDetailScreen.raiseActionKey), findsOneWidget);
    expect(wire.safetyObservationActionRaisePosts, isEmpty);
  });

  testWidgets(
      'raising an Action from a Safety observation needs no Grant, and offers the control to a caller holding only a read Grant',
      (tester) async {
    // #231's own permission, the same one the ticket names for this path: a
    // read-only Grant is enough to see the Site, and the raise control is
    // offered on that alone.
    final wire = FakeWire(
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {null: [orgUnitJson('11', 'Line 1')]},
      orgUnitScope: {
        'everywhere': false,
        'grants': [scopeGrantJson('11', canWrite: false)],
      },
      safetyObservations: {
        '1': [_observation()],
      },
      actionDetails: {'501': _action()},
    );
    await _pump(tester, wire);

    expect(find.byKey(SafetyObservationDetailScreen.raiseActionKey), findsOneWidget);
  });

  testWidgets(
      'the detail shows the Action raised from the observation, with its status, and it links to the Action\'s own address',
      (tester) async {
    final action = _action(ownerName: 'Sam Safety');
    final wire = _wire(actionsOn801: [safetyObservationActionJson(action)]);
    await _pump(tester, wire);

    expect(find.byKey(SafetyObservationDetailScreen.noActionsKey), findsNothing);
    final row = _rowText(tester, SafetyObservationDetailScreen.actionRowKey('501'));
    expect(row, contains('Clear the fire exit and re-stack the pallets'));
    expect(row, contains('AC-HCM-2026-00001'));
    expect(row, contains('Sam Safety'));
    // The status is the action log's own five words, through the Actions
    // Module's entry point rather than a second copy of the map.
    expect(row, contains('Open'));

    await tapIn(tester, find.byKey(SafetyObservationDetailScreen.actionRowKey('501')));
    expect(_locationOf(tester, find.byKey(ActionDetailScreen.loadedKey)), '/actions/501');
  });

  testWidgets(
      'raising an Action sends the chosen kind, its title, its description and its priority, and nothing about the Org Unit',
      (tester) async {
    final wire = _wire();
    await _pump(tester, wire);

    await tapIn(tester, find.byKey(SafetyObservationDetailScreen.raiseActionKey));
    expect(find.byKey(SafetyObservationRaiseActionDialog.titleKey), findsOneWidget);
    // Nothing can be sent until a kind and a title are chosen — the submit
    // button is closed.
    expect(
      tester
          .widget<FilledButton>(find.byKey(SafetyObservationRaiseActionDialog.submitKey))
          .onPressed,
      isNull,
    );
    expect(wire.safetyObservationActionRaisePosts, isEmpty);

    await tester.enterText(
      find.byKey(SafetyObservationRaiseActionDialog.titleKey),
      'Clear the fire exit and re-stack the pallets',
    );
    await tester.pump();
    // Still closed: a kind has not been chosen yet.
    expect(
      tester
          .widget<FilledButton>(find.byKey(SafetyObservationRaiseActionDialog.submitKey))
          .onPressed,
      isNull,
    );

    await tapIn(tester, find.byKey(SafetyObservationRaiseActionDialog.actionTypeKey));
    await tapIn(tester, find.text('Containment').last);
    await tester.enterText(
      find.byKey(SafetyObservationRaiseActionDialog.descriptionKey),
      'Immediate containment while a permanent storage fix is found.',
    );
    await tester.pump();
    await tapIn(tester, find.byKey(SafetyObservationRaiseActionDialog.priorityKey));
    await tapIn(tester, find.text('P2').last);
    await tapIn(tester, find.byKey(SafetyObservationRaiseActionDialog.submitKey));

    // One request, to the Action log's own address for raising an Action from
    // a Safety observation — and no `orgUnitId` in it, because the Action
    // lands at the observation's own Org Unit.
    expect(wire.safetyObservationActionRaisePosts.length, 1);
    expect(wire.safetyObservationActionRaisePosts.single.$1, '801');
    expect(wire.safetyObservationActionRaisePosts.single.$2, {
      'actionType': 'containment',
      'title': 'Clear the fire exit and re-stack the pallets',
      'description': 'Immediate containment while a permanent storage fix is found.',
      'priority': 2,
    });
    expect(wire.safetyObservationActionRaisePosts.single.$2.containsKey('orgUnitId'), isFalse);

    // The dialog has closed and the Screen the raise was made from now names
    // the Action — read back from the record, not inferred from the answer.
    expect(find.byKey(SafetyObservationRaiseActionDialog.submitKey), findsNothing);
    expect(find.byKey(SafetyObservationDetailScreen.actionNoticeKey), findsOneWidget);
    expect(
      _rowText(tester, SafetyObservationDetailScreen.actionRowKey('901')),
      contains('AC-TEST-2026-00009'),
    );
  });

  testWidgets(
      'a refused raise keeps the dialog open with the server\'s own sentence, and sends nothing else',
      (tester) async {
    final wire = _wire()
      ..raiseSafetyObservationActionStatus = 403
      ..raiseSafetyObservationActionMessage = 'you do not have permission to see this Site';
    await _pump(tester, wire);

    await tapIn(tester, find.byKey(SafetyObservationDetailScreen.raiseActionKey));
    await tapIn(tester, find.byKey(SafetyObservationRaiseActionDialog.actionTypeKey));
    await tapIn(tester, find.text('Countermeasure').last);
    await tester.enterText(
      find.byKey(SafetyObservationRaiseActionDialog.titleKey),
      'Not mine to raise',
    );
    await tester.pump();
    await tapIn(tester, find.byKey(SafetyObservationRaiseActionDialog.submitKey));

    expect(wire.safetyObservationActionRaisePosts.length, 1);
    expect(find.text('you do not have permission to see this Site'), findsOneWidget);
    // The Screen's own copy of the failure is not a second one: the dialog
    // that asked is still open, holding the sentence, and the form is still
    // usable.
    expect(find.byKey(SafetyObservationRaiseActionDialog.submitKey), findsOneWidget);
    expect(find.byKey(SafetyObservationDetailScreen.noActionsKey), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // The Action Screen names the Safety observation back (issue #231)
  // -------------------------------------------------------------------------

  testWidgets(
      'the Action Screen names the Safety observation it was raised from, with its type, category and severity potential, and links to its own address',
      (tester) async {
    final wire = _wire();
    await _pump(tester, wire, location: '/actions/501');

    expect(find.byKey(ActionDetailScreen.safetyObservationKey), findsOneWidget);
    final row = _rowText(tester, ActionDetailScreen.safetyObservationKey);
    expect(row, contains('Housekeeping'));
    expect(row, contains('Unsafe condition'));
    expect(row, contains('High'));

    await tapIn(
      tester,
      find.descendant(
        of: find.byKey(ActionDetailScreen.safetyObservationKey),
        matching: find.byType(ListTile),
      ),
    );
    expect(
      _locationOf(tester, find.byKey(SafetyObservationDetailScreen.backKey)),
      '/safety/observations/801',
    );
  });

  testWidgets(
      'an Action raised from a Safety observation shows no Non-conformances section and no Safety incident section — the single-source rule means never more than one',
      (tester) async {
    final wire = _wire();
    await _pump(tester, wire, location: '/actions/501');

    expect(find.byKey(ActionDetailScreen.nonconformancesKey), findsNothing);
    expect(find.byKey(ActionDetailScreen.noNonconformancesKey), findsNothing);
    expect(find.byKey(ActionDetailScreen.safetyIncidentKey), findsNothing);
  });
}
