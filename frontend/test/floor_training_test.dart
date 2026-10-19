/// A Trainee with no Account answering at the shared floor device (issue #293,
/// ADR-0016, ADR-0043), driven the way a person drives it: at the floor
/// surface's own address, with the wire faked beneath. Asserts on what renders
/// and on what the fake wire recorded; never on a Bloc's state.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/maintenance/floor_screen.dart';
import 'package:lean_platform/people/floor_training_dialog.dart';

import 'harness.dart';

FakeWire _wire() => FakeWire(floorWorkOrders: const [])
  ..floorTrainingToConfirm = [
    trainingToConfirmJson('7', id: '1', title: 'Lockout and tagout refresher'),
    trainingToConfirmJson('8', id: '2', number: 'TR-HCM-2026-00002', title: 'Forklift safety'),
  ];

/// Opens the dialog from the floor Screen and identifies.
Future<void> identify(WidgetTester tester) async {
  await tapIn(tester, find.byKey(FloorScreen.trainingKey));
  await tester.enterText(find.byKey(FloorTrainingDialog.employeeNoKey), 'EMP-20');
  await tester.enterText(find.byKey(FloorTrainingDialog.pinKey), '4321');
  await tester.pumpAndSettle();
  await tapIn(tester, find.byKey(FloorTrainingDialog.submitKey));
}

void main() {
  testWidgets('after identifying, the Employee\'s outstanding training is listed with both actions', (tester) async {
    final wire = _wire();
    await pumpApp(tester, gateway: FakeAuthGateway(), client: wire.client, initialLocation: '/floor');

    await identify(tester);

    expect(wire.floorIdentifications.single['employeeNo'], 'EMP-20');
    // The list is read through the device's own door, carrying the device
    // credential and the identification just issued.
    final read = wire.floorTrainingRequests.single;
    expect(read['request'], 'GET /api/maintenance/floor/training/to-confirm');
    expect(read['device'], 'device-credential');
    expect(read['identification'], 'identification-1');

    expect(find.byKey(FloorTrainingDialog.listKey), findsOneWidget);
    expect(find.textContaining('Lockout and tagout refresher'), findsOneWidget);
    expect(find.textContaining('Forklift safety'), findsOneWidget);
    for (final id in ['7', '8']) {
      expect(find.byKey(FloorTrainingDialog.confirmKey(id)), findsOneWidget);
      expect(find.byKey(FloorTrainingDialog.declineKey(id)), findsOneWidget);
    }
  });

  testWidgets('confirming sends the answer with both credentials and the row leaves', (tester) async {
    final wire = _wire();
    await pumpApp(tester, gateway: FakeAuthGateway(), client: wire.client, initialLocation: '/floor');
    await identify(tester);

    await tapIn(tester, find.byKey(FloorTrainingDialog.confirmKey('7')));

    final post = wire.floorTrainingRequests.last;
    expect(post['request'], 'POST /api/maintenance/floor/training/trainees/7/answer');
    expect(post['device'], 'device-credential');
    expect(post['identification'], 'identification-1');
    expect(post['body'], {'answer': 'confirmed'});
    expect(find.byKey(FloorTrainingDialog.rowKey('7')), findsNothing);
    expect(find.byKey(FloorTrainingDialog.rowKey('8')), findsOneWidget);
  });

  testWidgets('declining sends the declined answer and the row leaves', (tester) async {
    final wire = _wire();
    await pumpApp(tester, gateway: FakeAuthGateway(), client: wire.client, initialLocation: '/floor');
    await identify(tester);

    await tapIn(tester, find.byKey(FloorTrainingDialog.declineKey('8')));

    final post = wire.floorTrainingRequests.last;
    expect(post['request'], 'POST /api/maintenance/floor/training/trainees/8/answer');
    expect(post['body'], {'answer': 'declined'});
    expect(find.byKey(FloorTrainingDialog.rowKey('8')), findsNothing);
    expect(find.byKey(FloorTrainingDialog.rowKey('7')), findsOneWidget);
  });

  testWidgets('answering the last row says nothing is waiting', (tester) async {
    final wire = _wire()..floorTrainingToConfirm = [trainingToConfirmJson('7')];
    await pumpApp(tester, gateway: FakeAuthGateway(), client: wire.client, initialLocation: '/floor');
    await identify(tester);

    await tapIn(tester, find.byKey(FloorTrainingDialog.confirmKey('7')));

    expect(find.byKey(FloorTrainingDialog.emptyKey), findsOneWidget);
  });

  testWidgets('a refused answer is reported and the row stays', (tester) async {
    final wire = _wire()
      ..floorTrainingAnswerStatus = 403
      ..floorTrainingAnswerMessage = 'Only the Trainee can answer for themselves';
    await pumpApp(tester, gateway: FakeAuthGateway(), client: wire.client, initialLocation: '/floor');
    await identify(tester);

    await tapIn(tester, find.byKey(FloorTrainingDialog.confirmKey('7')));

    expect(find.byKey(FloorTrainingDialog.failureKey), findsOneWidget);
    expect(find.text('Only the Trainee can answer for themselves'), findsOneWidget);
    expect(find.byKey(FloorTrainingDialog.rowKey('7')), findsOneWidget);
  });

  testWidgets('a failed read is reported on the identify step and nothing is listed', (tester) async {
    final wire = _wire()..floorTrainingToConfirmStatus = 500;
    await pumpApp(tester, gateway: FakeAuthGateway(), client: wire.client, initialLocation: '/floor');

    await identify(tester);

    expect(find.byKey(FloorTrainingDialog.failureKey), findsOneWidget);
    expect(find.text('Your training is unavailable.'), findsOneWidget);
    expect(find.byKey(FloorTrainingDialog.listKey), findsNothing);
  });

  testWidgets('a wrong PIN is reported and no training is read', (tester) async {
    final wire = _wire()..floorIdentifyStatus = 401;
    await pumpApp(tester, gateway: FakeAuthGateway(), client: wire.client, initialLocation: '/floor');

    await identify(tester);

    expect(find.byKey(FloorTrainingDialog.failureKey), findsOneWidget);
    expect(wire.floorTrainingRequests, isEmpty);
  });
}
