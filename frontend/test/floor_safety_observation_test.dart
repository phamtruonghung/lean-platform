/// Recording a Safety observation at the shared floor device (issue #230,
/// ADR-0016), driven the way a person drives it — at the floor surface's own
/// address, with the wire faked beneath.
///
/// The standard is the one AGENTS.md §5 sets for the client seam, and the one
/// `floor_safety_incident_test.dart` holds for its own sibling flow: pump the
/// real app, act through the UI, and assert on what renders and on what the
/// fake wire recorded. Nothing here inspects `FloorSafetyObservationBloc`'s
/// state directly.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/maintenance/floor_screen.dart';
import 'package:lean_platform/safety/floor_safety_observation_dialog.dart';

import 'harness.dart';

/// The wire every test in this file starts from: a device registered at
/// Line 1, with an empty work list — an operator recording a Safety
/// observation is not doing so because a job is open.
FakeWire _wire() => FakeWire(floorWorkOrders: const []);

/// Fills the form in the way an operator at the machine does: choose the
/// type, category and potential, describe what was seen, type who they are.
/// Leaves the dialog ready to submit.
Future<void> fillForm(
  WidgetTester tester, {
  String type = 'Unsafe condition',
  String category = 'Housekeeping',
  String potential = 'Low',
  String description = 'A trip hazard on the floor.',
}) async {
  await tester.tap(find.byKey(FloorSafetyObservationDialog.typeKey));
  await tester.pumpAndSettle();
  await tester.tap(find.text(type).last);
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(FloorSafetyObservationDialog.categoryKey));
  await tester.pumpAndSettle();
  await tester.tap(find.text(category).last);
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(FloorSafetyObservationDialog.severityPotentialKey));
  await tester.pumpAndSettle();
  await tester.tap(find.text(potential).last);
  await tester.pumpAndSettle();

  await tester.enterText(find.byKey(FloorSafetyObservationDialog.descriptionKey), description);
  await tester.enterText(find.byKey(FloorSafetyObservationDialog.employeeNoKey), 'EMP-20');
  await tester.enterText(find.byKey(FloorSafetyObservationDialog.pinKey), '4321');
  await tester.pumpAndSettle();
}

/// Opens the flow from the floor Screen. Unlike the Non-conformance flow,
/// there is no catalogue to read first — type, category and potential are
/// fixed enums already known client-side — so the form is ready the moment
/// the dialog opens.
Future<void> openFlow(WidgetTester tester) async {
  await tapIn(tester, find.byKey(FloorScreen.recordSafetyObservationKey));
}

void main() {
  testWidgets(
    'the floor surface offers recording a Safety observation, choices from the known sets',
    (tester) async {
      final wire = _wire();

      await pumpApp(
        tester,
        gateway: FakeAuthGateway(),
        client: wire.client,
        initialLocation: '/floor',
      );

      // The action is on the surface even with nothing open on the line — an
      // observation is exactly when there is no work order to hang it on.
      expect(find.byKey(FloorScreen.recordSafetyObservationKey), findsOneWidget);

      await openFlow(tester);

      expect(find.text('Record a Safety observation'), findsOneWidget);
      expect(find.byKey(FloorSafetyObservationDialog.typeKey), findsOneWidget);
      expect(find.byKey(FloorSafetyObservationDialog.categoryKey), findsOneWidget);
      expect(find.byKey(FloorSafetyObservationDialog.severityPotentialKey), findsOneWidget);

      // Type: the full fixed set, chosen from a dropdown, never typed
      // (ADR-0023).
      await tester.tap(find.byKey(FloorSafetyObservationDialog.typeKey));
      await tester.pumpAndSettle();
      expect(find.text('Safe act'), findsWidgets);
      expect(find.text('Unsafe act'), findsWidgets);
      expect(find.text('Unsafe condition'), findsWidgets);
      await tester.tap(find.text('Unsafe act').last);
      await tester.pumpAndSettle();

      // Severity potential: the full fixed set.
      await tester.tap(find.byKey(FloorSafetyObservationDialog.severityPotentialKey));
      await tester.pumpAndSettle();
      expect(find.text('Low'), findsWidgets);
      expect(find.text('Medium'), findsWidgets);
      expect(find.text('High'), findsWidgets);
      expect(find.text('Fatal'), findsWidgets);
      await tester.tap(find.text('Low').last);
      await tester.pumpAndSettle();

      expect(wire.floorSafetyObservationPosts, isEmpty);
    },
  );

  testWidgets(
    'recording sends one request carrying the device credential, the identification and what '
    'was chosen',
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
        type: 'Unsafe act',
        category: 'Traffic',
        potential: 'Medium',
        description: 'A forklift took a corner too fast.',
      );
      await tapIn(tester, find.byKey(FloorSafetyObservationDialog.submitKey));

      // The technician identified themselves once, at the machine they are
      // standing at ...
      expect(wire.floorIdentifications, hasLength(1));
      expect(wire.floorIdentifications.single['employeeNo'], 'EMP-20');
      expect(wire.floorIdentifications.single['device'], 'device-credential');

      // ... and one record was written through the device's own door,
      // carrying that identification, the device's own Org Unit and the
      // chosen values.
      expect(wire.floorSafetyObservationPosts, hasLength(1));
      final post = wire.floorSafetyObservationPosts.single;
      expect(post['device'], 'device-credential');
      expect(post['identification'], 'identification-1');

      final body = post['body'] as Map<String, dynamic>;
      expect(body['orgUnitId'], '10');
      expect(body['observationType'], 'unsafe_act');
      expect(body['category'], 'traffic');
      expect(body['severityPotential'], 'medium');
      expect(body['description'], 'A forklift took a corner too fast.');
      expect(body['isStopWork'], false);
      // Nothing the operator did not decide is sent.
      expect(body.containsKey('actionTaken'), isFalse);

      // The dialog is done with, and the operator is told who recorded it.
      expect(find.byKey(FloorSafetyObservationDialog.submitKey), findsNothing);
      expect(find.textContaining('recorded by'), findsOneWidget);
    },
  );

  testWidgets('stop-work is sent when the switch is toggled', (tester) async {
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
      type: 'Unsafe condition',
      category: 'Energy isolation',
      potential: 'Fatal',
      description: 'A technician stopped work on a machine with a failed lockout.',
    );
    await tester.tap(find.byKey(FloorSafetyObservationDialog.stopWorkKey));
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(FloorSafetyObservationDialog.submitKey));

    final body =
        (wire.floorSafetyObservationPosts.single['body'] as Map<String, dynamic>);
    expect(body['isStopWork'], true);
  });

  testWidgets(
      'a refused record (403 out-of-scope) is reported on the form and nothing is written twice',
      (tester) async {
    final wire = _wire()..floorSafetyObservationStatus = 403;

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(),
      client: wire.client,
      initialLocation: '/floor',
    );

    await openFlow(tester);
    await fillForm(tester);
    await tapIn(tester, find.byKey(FloorSafetyObservationDialog.submitKey));

    expect(find.byKey(FloorSafetyObservationDialog.failureKey), findsOneWidget);
    expect(find.textContaining("Outside the caller's granted Org Units"), findsOneWidget);
    // The form is still open with the operator's own typing in it.
    expect(find.byKey(FloorSafetyObservationDialog.submitKey), findsOneWidget);
    expect(wire.floorSafetyObservationPosts, hasLength(1));
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
    await tapIn(tester, find.byKey(FloorSafetyObservationDialog.submitKey));

    expect(find.byKey(FloorSafetyObservationDialog.failureKey), findsOneWidget);
    expect(find.textContaining('not recognised'), findsOneWidget);
    expect(wire.floorSafetyObservationPosts, isEmpty);
  });

  testWidgets('identification is mandatory: submit stays disabled without it', (tester) async {
    final wire = _wire();

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(),
      client: wire.client,
      initialLocation: '/floor',
    );

    await openFlow(tester);

    expect(find.byKey(FloorSafetyObservationDialog.employeeNoKey), findsOneWidget);
    expect(find.byKey(FloorSafetyObservationDialog.pinKey), findsOneWidget);

    await tester.tap(find.byKey(FloorSafetyObservationDialog.typeKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Safe act').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(FloorSafetyObservationDialog.categoryKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PPE').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(FloorSafetyObservationDialog.severityPotentialKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Low').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(FloorSafetyObservationDialog.descriptionKey),
      'Something was seen.',
    );
    await tester.pumpAndSettle();

    // Every field except identification is filled in, and submit is still
    // disabled — there is no way to record without naming who is recording.
    final submitButton =
        tester.widget<FilledButton>(find.byKey(FloorSafetyObservationDialog.submitKey));
    expect(submitButton.onPressed, isNull);

    expect(wire.floorSafetyObservationPosts, isEmpty);
  });

  testWidgets(
      'the existing technician-prompt/work-order flow on the floor surface is unaffected',
      (tester) async {
    // The observation flow is an addition, not a replacement: opening it and
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
    await tapIn(tester, find.byKey(FloorSafetyObservationDialog.dismissKey));

    expect(find.text('WO-1'), findsOneWidget);
    expect(wire.floorSafetyObservationPosts, isEmpty);
  });
}
