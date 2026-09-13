/// The floor technician surface, driven the way a person drives it (issue
/// #77, ADR-0016) — at its own address, with the wire faked beneath.
///
/// The standard is the one AGENTS.md §5 sets for the client seam: pump the
/// real app, act through the UI, and assert on what renders and on what the
/// fake wire recorded. Nothing here inspects `FloorBloc`'s state directly.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/maintenance/floor_screen.dart';
import 'package:lean_platform/maintenance/floor_technician_dialog.dart';
import 'package:lean_platform/platform/shell.dart';

import 'harness.dart';

void main() {
  testWidgets('the floor Screen renders at its own address without the desktop Shell', (tester) async {
    final wire = FakeWire(
      floorWorkOrders: [workOrderJson('101', 'WO-1', 'Replace the drive belt')],
    );

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(),
      client: wire.client,
      initialLocation: '/floor',
    );

    expect(find.byType(FloorScreen), findsOneWidget);
    expect(find.byType(PlatformShell), findsNothing);
    expect(find.text('Floor work'), findsOneWidget);
    expect(find.text('Line 1'), findsOneWidget);
    expect(find.text('Replace the drive belt'), findsOneWidget);
    expect(locationOf(tester, find.byType(FloorScreen)), '/floor');
  });

  testWidgets('the floor Screen shows its own loading placeholders while the read is in flight', (tester) async {
    final wire = FakeWire(floorWorkOrders: [workOrderJson('101', 'WO-1', 'Replace the drive belt')]);
    wire.floorGate = Completer<void>();

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(),
      client: wire.client,
      initialLocation: '/floor',
      settle: false,
    );

    expect(find.byKey(FloorScreen.loadingKey), findsOneWidget);
    expect(find.text('Replace the drive belt'), findsNothing);

    wire.floorGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Replace the drive belt'), findsOneWidget);
  });

  testWidgets('an empty floor list says plainly there is no open work', (tester) async {
    final wire = FakeWire(floorWorkOrders: const []);

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(),
      client: wire.client,
      initialLocation: '/floor',
    );

    expect(find.text('No open work'), findsOneWidget);
    expect(find.textContaining('no open work for Line 1'), findsOneWidget);
  });

  testWidgets('a failed load explains itself and a retry re-reads', (tester) async {
    final wire = FakeWire(floorWorkOrdersStatus: 500);

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(),
      client: wire.client,
      initialLocation: '/floor',
    );

    expect(find.text('The floor work could not be loaded'), findsOneWidget);
    expect(find.text('The floor work is unavailable.'), findsOneWidget);

    wire.floorWorkOrdersStatus = 200;
    wire.floorWorkOrders = [workOrderJson('101', 'WO-1', 'Replace the drive belt')];
    await tapIn(tester, find.byKey(FloorScreen.retryKey));

    expect(find.text('Replace the drive belt'), findsOneWidget);
  });

  testWidgets('starting sends one request carrying the individual identification', (tester) async {
    final wire = FakeWire(
      floorWorkOrders: [workOrderJson('101', 'WO-1', 'Replace the drive belt', status: 'approved')],
    );

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(),
      client: wire.client,
      initialLocation: '/floor',
    );

    await tapIn(tester, find.byKey(FloorScreen.startKey('101')));
    expect(find.byKey(FloorTechnicianDialog.employeeNoKey), findsOneWidget);

    await tester.enterText(find.byKey(FloorTechnicianDialog.employeeNoKey), 'EMP-20');
    await tester.enterText(find.byKey(FloorTechnicianDialog.pinKey), '4321');
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(FloorTechnicianDialog.submitKey));

    expect(wire.floorIdentifications, hasLength(1));
    expect(wire.floorIdentifications.single['employeeNo'], 'EMP-20');
    expect(wire.floorIdentifications.single['device'], 'device-credential');

    expect(wire.floorWorkOrderStarts, hasLength(1));
    expect(wire.floorWorkOrderStarts.single['id'], '101');
    expect(wire.floorWorkOrderStarts.single['device'], 'device-credential');
    expect(wire.floorWorkOrderStarts.single['identification'], 'identification-1');
    expect(find.text('In progress'), findsOneWidget);
  });

  testWidgets('completing sends one request carrying the individual identification and the note', (tester) async {
    final wire = FakeWire(
      floorWorkOrders: [
        workOrderJson('101', 'WO-1', 'Replace the drive belt', status: 'in_progress'),
      ],
    );

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(),
      client: wire.client,
      initialLocation: '/floor',
    );

    await tapIn(tester, find.byKey(FloorScreen.completeKey('101')));
    await tester.enterText(find.byKey(FloorTechnicianDialog.noteKey), 'Belt replaced');
    await tester.enterText(find.byKey(FloorTechnicianDialog.employeeNoKey), 'EMP-20');
    await tester.enterText(find.byKey(FloorTechnicianDialog.pinKey), '4321');
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(FloorTechnicianDialog.submitKey));

    expect(wire.floorIdentifications, hasLength(1));
    expect(wire.floorWorkOrderCompletions, hasLength(1));
    expect(wire.floorWorkOrderCompletions.single['identification'], 'identification-1');
    expect(wire.floorWorkOrderCompletions.single['note'], 'Belt replaced');

    // Completing takes the row out of the open list.
    expect(find.text('No open work'), findsOneWidget);
  });

  testWidgets('a wrong PIN is reported on the dialog and the row is unchanged', (tester) async {
    final wire = FakeWire(
      floorWorkOrders: [workOrderJson('101', 'WO-1', 'Replace the drive belt')],
      floorIdentifyStatus: 401,
    );

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(),
      client: wire.client,
      initialLocation: '/floor',
    );

    await tapIn(tester, find.byKey(FloorScreen.startKey('101')));
    await tester.enterText(find.byKey(FloorTechnicianDialog.employeeNoKey), 'EMP-20');
    await tester.enterText(find.byKey(FloorTechnicianDialog.pinKey), '0000');
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(FloorTechnicianDialog.submitKey));

    expect(find.byKey(FloorTechnicianDialog.failureKey), findsOneWidget);
    expect(wire.floorWorkOrderStarts, isEmpty);
  });

  testWidgets('a device with no credential says it is not registered', (tester) async {
    final wire = FakeWire(floorWorkOrders: [workOrderJson('101', 'WO-1', 'Replace the drive belt')]);

    await pumpApp(
      tester,
      gateway: FakeAuthGateway(),
      client: wire.client,
      floorDeviceGateway: FakeFloorDeviceGateway(null),
      initialLocation: '/floor',
    );

    expect(find.textContaining('not registered'), findsOneWidget);
    expect(wire.floorReads, isEmpty);
  });
}
