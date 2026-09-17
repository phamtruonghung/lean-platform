/// Recording a Non-conformance at the shared floor device (issue #207,
/// ADR-0016), driven the way a person drives it — at the floor surface's own
/// address, with the wire faked beneath.
///
/// The standard is the one AGENTS.md §5 sets for the client seam, and the one
/// `floor_technician_surface_test.dart` holds for the rest of this surface:
/// pump the real app, act through the UI, and assert on what renders and on
/// what the fake wire recorded. Nothing here inspects
/// `FloorNonconformanceBloc`'s state directly.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/maintenance/floor_screen.dart';
import 'package:lean_platform/maintenance/floor_technician_dialog.dart';
import 'package:lean_platform/quality/floor_nonconformance_dialog.dart';

import 'harness.dart';

/// The wire every test in this file starts from: a device registered at
/// Line 1 with two Products and two Defect codes to choose from, and an empty
/// work list — an operator recording a Non-conformance is not doing so because
/// a job is open.
FakeWire _wire() => FakeWire(
      floorWorkOrders: const [],
      products: [
        productJson('40', 'PRD-1', 'Gearbox'),
        productJson('41', 'PRD-2', 'Bearing'),
      ],
      defectCodes: [
        defectCodeJson('50', 'DIM-OOT', 'Out of tolerance', defaultSeverity: 'major'),
        defectCodeJson('51', 'SCR', 'Scratch', defaultSeverity: 'minor'),
      ],
    );

/// Fills the form in the way an operator at the machine does: choose the
/// Product, choose the Defect code, choose the detection point, type how much
/// and who they are. Leaves the dialog ready to submit.
Future<void> fillForm(
  WidgetTester tester, {
  String product = 'PRD-1 · Gearbox',
  String defectCode = 'DIM-OOT · Out of tolerance',
  String detectionPoint = 'In process',
  String quantity = '12',
}) async {
  await tester.tap(find.byKey(FloorNonconformanceDialog.productKey));
  await tester.pumpAndSettle();
  await tester.tap(find.text(product).last);
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(FloorNonconformanceDialog.defectCodeKey));
  await tester.pumpAndSettle();
  await tester.tap(find.text(defectCode).last);
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(FloorNonconformanceDialog.detectionPointKey));
  await tester.pumpAndSettle();
  await tester.tap(find.text(detectionPoint).last);
  await tester.pumpAndSettle();

  await tester.enterText(find.byKey(FloorNonconformanceDialog.quantityKey), quantity);
  await tester.enterText(find.byKey(FloorNonconformanceDialog.employeeNoKey), 'EMP-20');
  await tester.enterText(find.byKey(FloorNonconformanceDialog.pinKey), '4321');
  await tester.pumpAndSettle();
}

/// Opens the flow from the floor Screen, which reads the two catalogues before
/// the form can be filled in.
Future<void> openFlow(WidgetTester tester) async {
  await tapIn(tester, find.byKey(FloorScreen.recordNonconformanceKey));
}

void main() {
  testWidgets('the floor surface offers recording a Non-conformance, choosing from what it read', (tester) async {
    final wire = _wire();

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(),
      client: wire.client,
      initialLocation: '/floor',
    );

    // The action is on the surface even with nothing open on the line — a
    // find is exactly when there is no work order to hang it on.
    expect(find.byKey(FloorScreen.recordNonconformanceKey), findsOneWidget);

    await openFlow(tester);

    expect(find.text('Record a Non-conformance'), findsOneWidget);
    expect(find.byKey(FloorNonconformanceDialog.productKey), findsOneWidget);
    expect(find.byKey(FloorNonconformanceDialog.defectCodeKey), findsOneWidget);
    expect(find.byKey(FloorNonconformanceDialog.detectionPointKey), findsOneWidget);

    // Both catalogues were read through the device's own door, and both
    // carried the device's credential.
    expect(wire.floorCatalogueReads, hasLength(2));
    expect(wire.floorCatalogueReads, everyElement('device-credential'));

    // Every value with a known set is a choice drawn from what was read, not
    // something typed (ADR-0023).
    await tester.tap(find.byKey(FloorNonconformanceDialog.productKey));
    await tester.pumpAndSettle();
    expect(find.text('PRD-1 · Gearbox'), findsWidgets);
    expect(find.text('PRD-2 · Bearing'), findsWidgets);
    await tester.tap(find.text('PRD-1 · Gearbox').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(FloorNonconformanceDialog.defectCodeKey));
    await tester.pumpAndSettle();
    expect(find.text('DIM-OOT · Out of tolerance'), findsWidgets);
    await tester.tap(find.text('DIM-OOT · Out of tolerance').last);
    await tester.pumpAndSettle();

    // The Defect code's own severity is stated rather than asked for: a
    // lowering is a Quality-authority decision this door does not reach.
    expect(find.textContaining('Starts at Major'), findsOneWidget);

    await tester.tap(find.byKey(FloorNonconformanceDialog.detectionPointKey));
    await tester.pumpAndSettle();
    expect(find.text('Incoming'), findsWidgets);
    expect(find.text('Final inspection'), findsWidgets);
    expect(find.text('Customer'), findsWidgets);
    await tester.tap(find.text('In process').last);
    await tester.pumpAndSettle();

    expect(wire.floorNonconformancePosts, isEmpty);
  });

  testWidgets('recording sends one request carrying the device credential, the identification and what was chosen', (tester) async {
    final wire = _wire();

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(),
      client: wire.client,
      initialLocation: '/floor',
    );

    await openFlow(tester);
    await fillForm(tester, detectionPoint: 'Final inspection', quantity: '12');
    await tapIn(tester, find.byKey(FloorNonconformanceDialog.submitKey));

    // The technician identified themselves once, at the machine they are
    // standing at ...
    expect(wire.floorIdentifications, hasLength(1));
    expect(wire.floorIdentifications.single['employeeNo'], 'EMP-20');
    expect(wire.floorIdentifications.single['device'], 'device-credential');

    // ... and one record was written through the device's own door, carrying
    // that identification, the device's own Org Unit and the chosen values.
    expect(wire.floorNonconformancePosts, hasLength(1));
    final post = wire.floorNonconformancePosts.single;
    expect(post['device'], 'device-credential');
    expect(post['identification'], 'identification-1');

    final body = post['body'] as Map<String, dynamic>;
    expect(body['orgUnitId'], '10');
    expect(body['productId'], '40');
    expect(body['defectCodeId'], '50');
    expect(body['detectionPoint'], 'final_inspection');
    expect(body['quantity'], 12);
    // Nothing the operator did not decide is sent: no severity (the Defect
    // code's own default is the answer), no empty optional text.
    expect(body.containsKey('severity'), isFalse);
    expect(body.containsKey('lotRef'), isFalse);
    expect(body.containsKey('description'), isFalse);

    // The dialog is done with, and the number the Platform issued is what the
    // operator is left with.
    expect(find.byKey(FloorNonconformanceDialog.submitKey), findsNothing);
    expect(find.textContaining('NC-HCM-2026-'), findsOneWidget);
  });

  testWidgets('a refused record is reported on the form and nothing is written twice', (tester) async {
    final wire = _wire()
      ..floorNonconformanceStatus = 403;

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(),
      client: wire.client,
      initialLocation: '/floor',
    );

    await openFlow(tester);
    await fillForm(tester);
    await tapIn(tester, find.byKey(FloorNonconformanceDialog.submitKey));

    expect(find.byKey(FloorNonconformanceDialog.failureKey), findsOneWidget);
    expect(find.textContaining("Outside the caller's granted Org Units"), findsOneWidget);
    // The form is still open with the operator's own typing in it.
    expect(find.byKey(FloorNonconformanceDialog.submitKey), findsOneWidget);
    expect(wire.floorNonconformancePosts, hasLength(1));
  });

  testWidgets('a wrong PIN writes nothing at all', (tester) async {
    final wire = _wire()
      ..floorIdentifyStatus = 401;

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(),
      client: wire.client,
      initialLocation: '/floor',
    );

    await openFlow(tester);
    await fillForm(tester);
    await tapIn(tester, find.byKey(FloorNonconformanceDialog.submitKey));

    expect(find.byKey(FloorNonconformanceDialog.failureKey), findsOneWidget);
    expect(find.textContaining('not recognised'), findsOneWidget);
    expect(wire.floorNonconformancePosts, isEmpty);
  });

  testWidgets("a device that cannot read the catalogues says so, and offers no form", (tester) async {
    final wire = _wire()
      ..floorCataloguesStatus = 401;

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(),
      client: wire.client,
      initialLocation: '/floor',
    );

    await openFlow(tester);

    expect(find.byKey(FloorNonconformanceDialog.productKey), findsNothing);
    expect(find.text('The floor catalogue is unavailable.'), findsOneWidget);
  });

  testWidgets('the floor surface still offers the technician prompt it always did', (tester) async {
    // The record flow is an addition, not a replacement: opening it and
    // dismissing it leaves the surface exactly as it was.
    final wire = FakeWire(
      floorWorkOrders: [workOrderJson('101', 'WO-1', 'Replace the drive belt')],
      products: [productJson('40', 'PRD-1', 'Gearbox')],
      defectCodes: [defectCodeJson('50', 'DIM-OOT', 'Out of tolerance')],
    );

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(),
      client: wire.client,
      initialLocation: '/floor',
    );

    await openFlow(tester);
    await tapIn(tester, find.byKey(FloorNonconformanceDialog.dismissKey));

    expect(find.byKey(FloorNonconformanceDialog.submitKey), findsNothing);
    expect(find.byKey(FloorScreen.startKey('101')), findsOneWidget);

    await tapIn(tester, find.byKey(FloorScreen.startKey('101')));
    expect(find.byKey(FloorTechnicianDialog.employeeNoKey), findsOneWidget);
  });
}
