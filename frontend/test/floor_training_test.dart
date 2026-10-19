/// A Trainee with no Account answering at the shared floor device (issue #293,
/// ADR-0016, ADR-0043), driven the way a person drives it: at the floor
/// surface's own address, with the wire faked beneath. Asserts on what renders
/// and on what the fake wire recorded; never on a Bloc's state.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/maintenance/floor_screen.dart';
import 'package:lean_platform/people/floor_training_dialog.dart';
import 'package:lean_platform/people/training_answer_dialog.dart';

import 'harness.dart';

FakeWire _wire() => FakeWire(floorWorkOrders: const [])
  ..floorTrainingToConfirm = [
    trainingToConfirmJson('7', id: '1', title: 'Lockout and tagout refresher'),
    trainingToConfirmJson('8', id: '2', number: 'TR-HCM-2026-00002', title: 'Forklift safety'),
  ];

final Uint8List _keptPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

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
    final read = wire.floorTrainingRequests.first;
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
    await tapIn(tester, find.byKey(TrainingAnswerDialog.noneKey));

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
    await tapIn(tester, find.byKey(TrainingAnswerDialog.noneKey));

    expect(find.byKey(FloorTrainingDialog.emptyKey), findsOneWidget);
  });

  testWidgets('a refused answer is reported and the row stays', (tester) async {
    final wire = _wire()
      ..floorTrainingAnswerStatus = 403
      ..floorTrainingAnswerMessage = 'Only the Trainee can answer for themselves';
    await pumpApp(tester, gateway: FakeAuthGateway(), client: wire.client, initialLocation: '/floor');
    await identify(tester);

    await tapIn(tester, find.byKey(FloorTrainingDialog.confirmKey('7')));
    await tapIn(tester, find.byKey(TrainingAnswerDialog.noneKey));

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

  group('the Signature a confirmed answer carries (issue #319)', () {
    testWidgets('with a Signature kept, Confirm shows it and offers using it or drawing one', (tester) async {
      final wire = _wire()..floorSignature = _keptPng;
      await pumpApp(tester, gateway: FakeAuthGateway(), client: wire.client, initialLocation: '/floor');
      await identify(tester);

      // Read through the device's own door, with both credentials.
      final read = wire.floorTrainingRequests.firstWhere((r) => r['request'] == 'GET /api/maintenance/floor/signature');
      expect(read['device'], 'device-credential');
      expect(read['identification'], 'identification-1');

      await tapIn(tester, find.byKey(FloorTrainingDialog.confirmKey('7')));

      expect(find.byKey(TrainingAnswerDialog.storedImageKey), findsOneWidget);
      expect(find.byKey(TrainingAnswerDialog.useStoredKey), findsOneWidget);
      expect(find.byKey(TrainingAnswerDialog.drawKey), findsOneWidget);
      expect(find.byKey(TrainingAnswerDialog.noneKey), findsOneWidget);
      // Nothing is sent until a choice is made.
      expect(wire.floorTrainingRequests.where((r) => (r['request'] as String).startsWith('POST')), isEmpty);
    });

    testWidgets('"Use my Signature" sends use: stored and the row leaves', (tester) async {
      final wire = _wire()..floorSignature = _keptPng;
      await pumpApp(tester, gateway: FakeAuthGateway(), client: wire.client, initialLocation: '/floor');
      await identify(tester);

      await tapIn(tester, find.byKey(FloorTrainingDialog.confirmKey('7')));
      await tapIn(tester, find.byKey(TrainingAnswerDialog.useStoredKey));

      final post = wire.floorTrainingRequests.last;
      expect(post['request'], 'POST /api/maintenance/floor/training/trainees/7/answer');
      expect(post['device'], 'device-credential');
      expect(post['identification'], 'identification-1');
      expect(post['body'], {
        'answer': 'confirmed',
        'signature': {'use': 'stored'},
      });
      expect(find.byKey(FloorTrainingDialog.rowKey('7')), findsNothing);
    });

    testWidgets('"Draw one now" sends the drawn PNG as an inline image', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final wire = _wire()..floorSignature = _keptPng;
      await pumpApp(tester, gateway: FakeAuthGateway(), client: wire.client, initialLocation: '/floor');
      await identify(tester);

      await tapIn(tester, find.byKey(FloorTrainingDialog.confirmKey('7')));
      await tapIn(tester, find.byKey(TrainingAnswerDialog.drawKey));
      final submit = find.byKey(TrainingAnswerDialog.submitDrawnKey);
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);

      await tester.drag(find.byKey(TrainingAnswerDialog.padKey), const Offset(120, 40));
      await tester.pumpAndSettle();
      // Rendering the strokes to a PNG goes through the engine, which a
      // fake-async test clock does not drive.
      await tester.runAsync(() async {
        await tester.tap(submit);
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await tester.pumpAndSettle();

      final post = wire.floorTrainingRequests.last;
      expect(post['request'], 'POST /api/maintenance/floor/training/trainees/7/answer');
      final body = post['body'] as Map<String, dynamic>;
      expect(body['answer'], 'confirmed');
      final image = (body['signature'] as Map<String, dynamic>)['image'] as String;
      expect(base64Decode(image).sublist(0, 8), [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
      expect(find.byKey(FloorTrainingDialog.rowKey('7')), findsNothing);
    });

    testWidgets('with no Signature kept there is no stored option, only drawing or none', (tester) async {
      final wire = _wire();
      await pumpApp(tester, gateway: FakeAuthGateway(), client: wire.client, initialLocation: '/floor');
      await identify(tester);

      await tapIn(tester, find.byKey(FloorTrainingDialog.confirmKey('7')));

      expect(find.byKey(TrainingAnswerDialog.dialogKey), findsOneWidget);
      expect(find.byKey(TrainingAnswerDialog.useStoredKey), findsNothing);
      expect(find.byKey(TrainingAnswerDialog.storedImageKey), findsNothing);
      expect(find.byKey(TrainingAnswerDialog.drawKey), findsOneWidget);
      expect(find.text('You keep no Signature. Draw one now for this answer, or confirm without a Signature.'), findsOneWidget);

      await tapIn(tester, find.byKey(TrainingAnswerDialog.noneKey));
      expect(wire.floorTrainingRequests.last['body'], {'answer': 'confirmed'});
    });

    testWidgets('cancelling the choice sends nothing, and a decline opens no choice', (tester) async {
      final wire = _wire()..floorSignature = _keptPng;
      await pumpApp(tester, gateway: FakeAuthGateway(), client: wire.client, initialLocation: '/floor');
      await identify(tester);

      await tapIn(tester, find.byKey(FloorTrainingDialog.confirmKey('7')));
      await tapIn(tester, find.byKey(TrainingAnswerDialog.cancelKey));
      expect(find.byKey(FloorTrainingDialog.rowKey('7')), findsOneWidget);
      expect(wire.floorTrainingRequests.where((r) => (r['request'] as String).startsWith('POST')), isEmpty);

      await tapIn(tester, find.byKey(FloorTrainingDialog.declineKey('7')));
      expect(find.byKey(TrainingAnswerDialog.dialogKey), findsNothing);
      expect(wire.floorTrainingRequests.last['body'], {'answer': 'declined'});
    });
  });
}
