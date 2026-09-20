/// Reporting a Safety incident at the shared floor device (issue #227,
/// ADR-0016, ADR-0036), driven the way a person drives it — at the floor
/// surface's own address, with the wire faked beneath.
///
/// The standard is the one AGENTS.md §5 sets for the client seam, and the one
/// `floor_nonconformance_test.dart` holds for its own sibling flow: pump the
/// real app, act through the UI, and assert on what renders and on what the
/// fake wire recorded. Nothing here inspects `FloorSafetyIncidentBloc`'s state
/// directly.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/maintenance/floor_screen.dart';
import 'package:lean_platform/maintenance/floor_technician_dialog.dart';
import 'package:lean_platform/safety/floor_safety_incident_dialog.dart';

import 'harness.dart';

/// The wire every test in this file starts from: a device registered at
/// Line 1, with an empty work list — an operator reporting a Safety incident
/// is not doing so because a job is open.
FakeWire _wire() => FakeWire(floorWorkOrders: const []);

/// Fills the form in the way an operator at the machine does: choose the
/// incident type, choose the severity, describe what happened, type who they
/// are. Leaves the dialog ready to submit.
Future<void> fillForm(
  WidgetTester tester, {
  String incidentType = 'Near miss',
  String severity = 'No injury',
  String description = 'A pallet nearly tipped while being moved.',
}) async {
  await tester.tap(find.byKey(FloorSafetyIncidentDialog.incidentTypeKey));
  await tester.pumpAndSettle();
  await tester.tap(find.text(incidentType).last);
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(FloorSafetyIncidentDialog.severityKey));
  await tester.pumpAndSettle();
  await tester.tap(find.text(severity).last);
  await tester.pumpAndSettle();

  await tester.enterText(find.byKey(FloorSafetyIncidentDialog.descriptionKey), description);
  await tester.enterText(find.byKey(FloorSafetyIncidentDialog.employeeNoKey), 'EMP-20');
  await tester.enterText(find.byKey(FloorSafetyIncidentDialog.pinKey), '4321');
  await tester.pumpAndSettle();
}

/// Opens the flow from the floor Screen. Unlike the Non-conformance flow,
/// there is no catalogue to read first — incident type and severity are fixed
/// enums already known client-side — so the form is ready the moment the
/// dialog opens.
Future<void> openFlow(WidgetTester tester) async {
  await tapIn(tester, find.byKey(FloorScreen.reportSafetyIncidentKey));
}

void main() {
  testWidgets(
    'the floor surface offers reporting a Safety incident, dropdowns in ladder order with recordable marked',
    (tester) async {
      final wire = _wire();

      await pumpApp(
        tester,
        gateway: FakeAuthGateway(),
        client: wire.client,
        initialLocation: '/floor',
      );

      // The action is on the surface even with nothing open on the line — a
      // Safety incident is exactly when there is no work order to hang it on.
      expect(find.byKey(FloorScreen.reportSafetyIncidentKey), findsOneWidget);

      await openFlow(tester);

      expect(find.text('Report a Safety incident'), findsOneWidget);
      expect(find.byKey(FloorSafetyIncidentDialog.incidentTypeKey), findsOneWidget);
      expect(find.byKey(FloorSafetyIncidentDialog.severityKey), findsOneWidget);

      // Incident type: the full fixed set, chosen from a dropdown, never
      // typed (ADR-0023).
      await tester.tap(find.byKey(FloorSafetyIncidentDialog.incidentTypeKey));
      await tester.pumpAndSettle();
      expect(find.text('Injury'), findsWidgets);
      expect(find.text('Near miss'), findsWidgets);
      expect(find.text('Property damage'), findsWidgets);
      expect(find.text('Environmental'), findsWidgets);
      expect(find.text('Fire'), findsWidgets);
      expect(find.text('Ergonomic'), findsWidgets);
      expect(find.text('Security'), findsWidgets);
      await tester.tap(find.text('Near miss').last);
      await tester.pumpAndSettle();

      // Severity: the full ladder, in ladder order (no injury through
      // fatality, never alphabetical), with the recordable line marked — the
      // same helper SafetyIncidentFormDialog's own dropdown is built from
      // (issue #227's "reuse, don't rewrite" requirement).
      await tester.tap(find.byKey(FloorSafetyIncidentDialog.severityKey));
      await tester.pumpAndSettle();
      expect(find.text('No injury'), findsWidgets);
      expect(find.text('First aid'), findsWidgets);
      expect(find.text('Medical treatment · recordable'), findsWidgets);
      expect(find.text('Restricted work · recordable'), findsWidgets);
      expect(find.text('Lost time · recordable'), findsWidgets);
      expect(find.text('Fatality · recordable'), findsWidgets);
      await tester.tap(find.text('No injury').last);
      await tester.pumpAndSettle();

      expect(wire.floorSafetyIncidentPosts, isEmpty);
    },
  );

  testWidgets(
    'reporting sends one request carrying the device credential, the identification and what was chosen',
    (tester) async {
      final wire = _wire();

      await pumpApp(
        tester,
        gateway: FakeAuthGateway(),
        client: wire.client,
        initialLocation: '/floor',
      );

      await openFlow(tester);
      await fillForm(
        tester,
        incidentType: 'Environmental',
        severity: 'First aid',
        description: 'A small spill was contained quickly.',
      );
      await tapIn(tester, find.byKey(FloorSafetyIncidentDialog.submitKey));

      // The technician identified themselves once, at the machine they are
      // standing at ...
      expect(wire.floorIdentifications, hasLength(1));
      expect(wire.floorIdentifications.single['employeeNo'], 'EMP-20');
      expect(wire.floorIdentifications.single['device'], 'device-credential');

      // ... and one record was written through the device's own door, carrying
      // that identification, the device's own Org Unit and the chosen values.
      expect(wire.floorSafetyIncidentPosts, hasLength(1));
      final post = wire.floorSafetyIncidentPosts.single;
      expect(post['device'], 'device-credential');
      expect(post['identification'], 'identification-1');

      final body = post['body'] as Map<String, dynamic>;
      expect(body['orgUnitId'], '10');
      expect(body['incidentType'], 'environmental');
      expect(body['severityLevel'], 'first_aid');
      expect(body['description'], 'A small spill was contained quickly.');
      expect(body.containsKey('occurredAt'), isTrue);
      // Nothing the operator did not decide is sent: no Asset, no Employee
      // involved, no immediate action left empty, and — the ticket's own
      // explicit ask — never an anonymous flag anywhere in this body.
      expect(body.containsKey('assetId'), isFalse);
      expect(body.containsKey('employeeId'), isFalse);
      expect(body.containsKey('immediateAction'), isFalse);
      expect(body.containsKey('isAnonymous'), isFalse);

      // The dialog is done with, and the number the Platform issued is what
      // the operator is left with.
      expect(find.byKey(FloorSafetyIncidentDialog.submitKey), findsNothing);
      expect(find.textContaining('SI-HCM-2026-'), findsOneWidget);
    },
  );

  testWidgets('a refused report (403 out-of-scope) is reported on the form and nothing is written twice', (tester) async {
    final wire = _wire()..floorSafetyIncidentStatus = 403;

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(),
      client: wire.client,
      initialLocation: '/floor',
    );

    await openFlow(tester);
    await fillForm(tester);
    await tapIn(tester, find.byKey(FloorSafetyIncidentDialog.submitKey));

    expect(find.byKey(FloorSafetyIncidentDialog.failureKey), findsOneWidget);
    expect(find.textContaining("Outside the caller's granted Org Units"), findsOneWidget);
    // The form is still open with the operator's own typing in it.
    expect(find.byKey(FloorSafetyIncidentDialog.submitKey), findsOneWidget);
    expect(wire.floorSafetyIncidentPosts, hasLength(1));
  });

  testWidgets('a wrong PIN writes nothing at all', (tester) async {
    final wire = _wire()..floorIdentifyStatus = 401;

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(),
      client: wire.client,
      initialLocation: '/floor',
    );

    await openFlow(tester);
    await fillForm(tester);
    await tapIn(tester, find.byKey(FloorSafetyIncidentDialog.submitKey));

    expect(find.byKey(FloorSafetyIncidentDialog.failureKey), findsOneWidget);
    expect(find.textContaining('not recognised'), findsOneWidget);
    expect(wire.floorSafetyIncidentPosts, isEmpty);
  });

  testWidgets('no anonymous affordance anywhere in the flow', (tester) async {
    final wire = _wire();

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(),
      client: wire.client,
      initialLocation: '/floor',
    );

    await openFlow(tester);

    // Nothing in the dialog's copy suggests a way to skip identification or
    // report without a name (ADR-0036) — checked case-insensitively so
    // "Anonymous" or "ANONYMOUS" would be caught too.
    final anonymousMention = find.byWidgetPredicate(
      (widget) =>
          widget is Text &&
          (widget.data ?? '').toLowerCase().contains('anonymous'),
    );
    expect(anonymousMention, findsNothing);

    final skipMention = find.byWidgetPredicate(
      (widget) =>
          widget is Text && (widget.data ?? '').toLowerCase().contains('skip'),
    );
    expect(skipMention, findsNothing);

    // Identification is mandatory: the employee number and PIN fields are
    // always present, and submit stays disabled until both are filled in
    // alongside every other required field.
    expect(find.byKey(FloorSafetyIncidentDialog.employeeNoKey), findsOneWidget);
    expect(find.byKey(FloorSafetyIncidentDialog.pinKey), findsOneWidget);

    await tester.tap(find.byKey(FloorSafetyIncidentDialog.incidentTypeKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Near miss').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(FloorSafetyIncidentDialog.severityKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No injury').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(FloorSafetyIncidentDialog.descriptionKey),
      'Something happened.',
    );
    await tester.pumpAndSettle();

    // Every field except identification is filled in, and submit is still
    // disabled — there is no way to report without naming who is reporting.
    final submitButton =
        tester.widget<FilledButton>(find.byKey(FloorSafetyIncidentDialog.submitKey));
    expect(submitButton.onPressed, isNull);

    expect(wire.floorSafetyIncidentPosts, isEmpty);
  });

  testWidgets('the existing technician-prompt/work-order flow on the floor surface is unaffected', (tester) async {
    // The report flow is an addition, not a replacement: opening it and
    // dismissing it leaves the surface exactly as it was.
    final wire = FakeWire(
      floorWorkOrders: [workOrderJson('101', 'WO-1', 'Replace the drive belt')],
    );

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(),
      client: wire.client,
      initialLocation: '/floor',
    );

    await openFlow(tester);
    await tapIn(tester, find.byKey(FloorSafetyIncidentDialog.dismissKey));

    expect(find.byKey(FloorSafetyIncidentDialog.submitKey), findsNothing);
    expect(find.byKey(FloorScreen.startKey('101')), findsOneWidget);

    await tapIn(tester, find.byKey(FloorScreen.startKey('101')));
    expect(find.byKey(FloorTechnicianDialog.employeeNoKey), findsOneWidget);
  });
}
