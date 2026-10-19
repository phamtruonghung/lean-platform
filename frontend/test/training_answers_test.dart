/// Sending a Training record and a Trainee's own answer (issue #289,
/// ADR-0043): the queue at `/training/to-confirm`, the Home card, the send
/// control on a draft and the answer controls on a Trainee's own row — with
/// the wire faked, the one client seam (AGENTS.md section 5). Everything
/// asserted is rendered text, a Key, or a request the fake wire recorded.
///
/// An authority or Account-change case is TWO tests, never two `pumpApp`
/// calls in one: the app-level providers survive a re-pump and the second wire
/// would answer as the first.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/home_screen.dart';
import 'package:lean_platform/people/training_answer_dialog.dart';
import 'package:lean_platform/people/training_detail_screen.dart';
import 'package:lean_platform/people/training_to_confirm_screen.dart';
import 'package:lean_platform/platform/destinations.dart';

import 'harness.dart';

Future<void> _open(WidgetTester tester, FakeWire wire, String location) {
  // A lazy ListView builds only what is on screen, so `find.byKey` cannot see
  // a row below the fold of the default 800x600 window. Pin a taller one.
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  return pumpApp(
    tester,
    gateway: FakeAuthGateway(accessToken: 'a-token'),
    client: wire.client,
    initialLocation: location,
  );
}

Map<String, dynamic> _completeDraft() => trainingRecordJson(
      '1',
      trainerEmployeeId: '9',
      trainerName: 'Tina Trainer',
      objective: 'Everyone can isolate the press',
      trainees: [traineeJson('t1', '7', 'E-7', 'Alice Nguyen'), traineeJson('t2', '8', 'E-8', 'Bao Tran')],
    );

Map<String, dynamic> _sent({String? answer1, String? answer2}) => trainingRecordJson(
      '1',
      status: 'sent',
      trainerEmployeeId: '9',
      trainerName: 'Tina Trainer',
      objective: 'Everyone can isolate the press',
      trainees: [
        traineeJson('t1', '7', 'E-7', 'Alice Nguyen', answer: answer1),
        traineeJson('t2', '8', 'E-8', 'Bao Tran', answer: answer2),
      ],
    );

void main() {
  group('the queue at /training/to-confirm', () {
    testWidgets('lists the caller\'s outstanding answers with the record\'s facts and both controls',
        (tester) async {
      final wire = FakeWire(
        role: Roles.operator,
        trainingToConfirm: [
          trainingToConfirmJson('t1', id: '1', title: 'Lockout and tagout refresher'),
          trainingToConfirmJson('t5', id: '2', number: 'TR-HCM-2026-00002', title: 'Forklift safety'),
        ],
      );
      await _open(tester, wire, '/training/to-confirm');

      // The address is the queue, not a record whose id is `to-confirm`.
      expect(find.byType(TrainingToConfirmScreen), findsOneWidget);
      expect(find.byKey(TrainingDetailScreen.missingKey), findsNothing);
      expect(find.byKey(TrainingToConfirmScreen.rowKey('t1')), findsOneWidget);
      expect(find.byKey(TrainingToConfirmScreen.rowKey('t5')), findsOneWidget);
      expect(find.text('TR-HCM-2026-00001 · Lockout and tagout refresher'), findsOneWidget);
      expect(find.text('TR-HCM-2026-00002 · Forklift safety'), findsOneWidget);
      expect(find.textContaining('trained by Tina Trainer'), findsWidgets);
      expect(find.text('Everyone can isolate the press'), findsWidgets);
      expect(find.byKey(TrainingToConfirmScreen.confirmKey('t1')), findsOneWidget);
      expect(find.byKey(TrainingToConfirmScreen.declineKey('t1')), findsOneWidget);
    });

    testWidgets('says plainly when nothing is waiting', (tester) async {
      await _open(tester, FakeWire(role: Roles.operator), '/training/to-confirm');

      expect(find.byKey(TrainingToConfirmScreen.emptyKey), findsOneWidget);
      expect(find.text('Nothing waiting on you'), findsOneWidget);
    });

    testWidgets('a failed read explains itself, and retry reads again', (tester) async {
      final wire = FakeWire(role: Roles.operator, trainingToConfirmStatus: 500);
      await _open(tester, wire, '/training/to-confirm');

      expect(find.byKey(TrainingToConfirmScreen.failureKey), findsOneWidget);
      expect(find.text('Your Training to confirm is unavailable.'), findsOneWidget);
      expect(find.byKey(TrainingToConfirmScreen.emptyKey), findsNothing);

      wire.trainingToConfirmStatus = 200;
      wire.trainingToConfirm = [trainingToConfirmJson('t1')];
      await tapIn(tester, find.byKey(TrainingToConfirmScreen.retryKey));
      expect(find.byKey(TrainingToConfirmScreen.rowKey('t1')), findsOneWidget);
    });

    testWidgets('confirming sends the answer and the row leaves the queue', (tester) async {
      final wire = FakeWire(
        role: Roles.operator,
        trainingToConfirm: [trainingToConfirmJson('t1'), trainingToConfirmJson('t5', id: '2', title: 'Other')],
      );
      await _open(tester, wire, '/training/to-confirm');
      await tapIn(tester, find.byKey(TrainingToConfirmScreen.confirmKey('t1')));
      await tapIn(tester, find.byKey(TrainingAnswerDialog.noneKey));

      expect(wire.trainingAnswers.length, 1);
      expect(wire.trainingAnswers.single.$1, 'POST /api/people/training/trainees/t1/answer');
      expect(wire.trainingAnswers.single.$2, {'answer': 'confirmed'});
      expect(find.byKey(TrainingToConfirmScreen.rowKey('t1')), findsNothing);
      expect(find.byKey(TrainingToConfirmScreen.rowKey('t5')), findsOneWidget);
    });

    testWidgets('declining sends a declined answer', (tester) async {
      final wire = FakeWire(role: Roles.operator, trainingToConfirm: [trainingToConfirmJson('t1')]);
      await _open(tester, wire, '/training/to-confirm');
      await tapIn(tester, find.byKey(TrainingToConfirmScreen.declineKey('t1')));

      expect(wire.trainingAnswers.length, 1);
      expect(wire.trainingAnswers.single.$1, 'POST /api/people/training/trainees/t1/answer');
      expect(wire.trainingAnswers.single.$2, {'answer': 'declined'});
      expect(find.byKey(TrainingToConfirmScreen.emptyKey), findsOneWidget);
    });

    testWidgets('a refused answer leaves the row where it was and says why', (tester) async {
      final wire = FakeWire(
        role: Roles.operator,
        trainingToConfirm: [trainingToConfirmJson('t1')],
        trainingAnswerStatus: 403,
      );
      await _open(tester, wire, '/training/to-confirm');
      await tapIn(tester, find.byKey(TrainingToConfirmScreen.confirmKey('t1')));
      await tapIn(tester, find.byKey(TrainingAnswerDialog.noneKey));

      expect(find.byKey(TrainingToConfirmScreen.rowKey('t1')), findsOneWidget);
      expect(find.byKey(TrainingToConfirmScreen.answerFailureKey), findsOneWidget);
      expect(find.text('Only the Trainee can answer for themselves'), findsOneWidget);
    });
  });

  group('the Home card', () {
    testWidgets('counts the caller\'s outstanding answers and carries to the queue', (tester) async {
      final wire = FakeWire(
        role: Roles.operator,
        trainingToConfirm: [trainingToConfirmJson('t1'), trainingToConfirmJson('t5', id: '2')],
      );
      await _open(tester, wire, '/');

      final card = find.byKey(HomeScreen.trainingToConfirmCardKey);
      expect(card, findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('2')), findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('Training to confirm')), findsOneWidget);

      await tapIn(tester, card);
      expect(find.byType(TrainingToConfirmScreen), findsOneWidget);
    });

    testWidgets('reads zero for an Account with nothing waiting', (tester) async {
      await _open(tester, FakeWire(role: Roles.operator), '/');

      final card = find.byKey(HomeScreen.trainingToConfirmCardKey);
      expect(find.descendant(of: card, matching: find.text('0')), findsOneWidget);
    });

    testWidgets('a failed read is the card\'s own failure and hides nothing else', (tester) async {
      await _open(tester, FakeWire(role: Roles.operator, trainingToConfirmStatus: 500), '/');

      expect(find.text('Your Training to confirm is unavailable'), findsOneWidget);
      expect(find.byKey(HomeScreen.trainingToConfirmCardKey), findsNothing);
      expect(find.byKey(HomeScreen.myActionsCardKey), findsOneWidget);
    });
  });

  group('sending from the record', () {
    testWidgets('an administrator sends a draft, and the record reads as sent', (tester) async {
      final wire = FakeWire(role: Roles.admin, trainingRecords: [_completeDraft()]);
      await _open(tester, wire, '/training/1');

      expect(find.text('Not sent yet: nobody has been asked.'), findsOneWidget);
      await tapIn(tester, find.byKey(TrainingDetailScreen.sendKey));

      expect(wire.trainingSends, ['POST /api/people/training/1/send']);
      expect(find.byKey(TrainingDetailScreen.sendKey), findsNothing);
      expect(find.text('Sent: nobody has answered yet.'), findsOneWidget);
    });

    testWidgets('the completeness refusal renders beside the send control', (tester) async {
      final wire = FakeWire(
        role: Roles.admin,
        trainingRecords: [_completeDraft()],
        trainingSendStatus: 409,
        trainingSendMessage: 'A Training record needs a trainer before it is sent',
      );
      await _open(tester, wire, '/training/1');
      await tapIn(tester, find.byKey(TrainingDetailScreen.sendKey));

      expect(find.byKey(TrainingDetailScreen.sendFailureKey), findsOneWidget);
      expect(find.text('A Training record needs a trainer before it is sent'), findsOneWidget);
      // The control is still there: nothing was sent, so it can be tried again.
      expect(find.byKey(TrainingDetailScreen.sendKey), findsOneWidget);
      expect(find.text('Not sent yet: nobody has been asked.'), findsOneWidget);
    });

    testWidgets('a reader with no edit Grant at the record\'s Org Unit is not offered the send control',
        (tester) async {
      // A supervisor holding only a view Grant reads sent records but cannot
      // see, let alone send, a draft — so the draft here is reached by an
      // Account whose edit Grant is elsewhere.
      final wire = FakeWire(
        role: Roles.supervisor,
        orgUnitScope: {
          'everywhere': false,
          'grants': [scopeGrantJson('99', canWrite: true)],
        },
        trainingRecords: [_completeDraft()],
      );
      await _open(tester, wire, '/training/1');

      expect(find.byKey(TrainingDetailScreen.numberKey), findsOneWidget);
      expect(find.byKey(TrainingDetailScreen.sendKey), findsNothing);
    });
  });

  group('a Trainee\'s answer on the record', () {
    testWidgets('the Trainee sees the two controls on their own row only, and declining sends the answer',
        (tester) async {
      final wire = FakeWire(role: Roles.operator, selfEmployeeId: '7', trainingRecords: [_sent()]);
      await _open(tester, wire, '/training/1');

      expect(find.byKey(TrainingDetailScreen.confirmKey('t1')), findsOneWidget);
      expect(find.byKey(TrainingDetailScreen.declineKey('t1')), findsOneWidget);
      expect(find.byKey(TrainingDetailScreen.confirmKey('t2')), findsNothing);
      expect(find.byKey(TrainingDetailScreen.declineKey('t2')), findsNothing);

      await tapIn(tester, find.byKey(TrainingDetailScreen.declineKey('t1')));

      expect(wire.trainingAnswers.length, 1);
      expect(wire.trainingAnswers.single.$1, 'POST /api/people/training/trainees/t1/answer');
      expect(wire.trainingAnswers.single.$2, {'answer': 'declined'});
      expect(find.text('Declined on 2026-05-06 from their own Account'), findsOneWidget);
      expect(find.text('Not answered yet'), findsOneWidget);
    });

    testWidgets('confirming sends a confirmed answer', (tester) async {
      final wire = FakeWire(role: Roles.operator, selfEmployeeId: '7', trainingRecords: [_sent()]);
      await _open(tester, wire, '/training/1');
      await tapIn(tester, find.byKey(TrainingDetailScreen.confirmKey('t1')));
      await tapIn(tester, find.byKey(TrainingAnswerDialog.noneKey));

      expect(wire.trainingAnswers.length, 1);
      expect(wire.trainingAnswers.single.$1, 'POST /api/people/training/trainees/t1/answer');
      expect(wire.trainingAnswers.single.$2, {'answer': 'confirmed'});
      expect(find.text('Confirmed on 2026-05-06 from their own Account'), findsOneWidget);
    });

    testWidgets('an Account that is not on the record is offered no answer control', (tester) async {
      final wire = FakeWire(role: Roles.admin, selfEmployeeId: '55', trainingRecords: [_sent()]);
      await _open(tester, wire, '/training/1');

      expect(find.byKey(TrainingDetailScreen.confirmKey('t1')), findsNothing);
      expect(find.byKey(TrainingDetailScreen.declineKey('t1')), findsNothing);
      expect(find.byKey(TrainingDetailScreen.confirmKey('t2')), findsNothing);
    });

    testWidgets('a draft offers no answer control even to a Trainee on it', (tester) async {
      final wire = FakeWire(role: Roles.admin, selfEmployeeId: '7', trainingRecords: [_completeDraft()]);
      await _open(tester, wire, '/training/1');

      expect(find.byKey(TrainingDetailScreen.confirmKey('t1')), findsNothing);
    });

    testWidgets('a refused answer renders beside the list', (tester) async {
      final wire = FakeWire(
        role: Roles.operator,
        selfEmployeeId: '7',
        trainingRecords: [_sent()],
        trainingAnswerStatus: 403,
      );
      await _open(tester, wire, '/training/1');
      await tapIn(tester, find.byKey(TrainingDetailScreen.confirmKey('t1')));
      await tapIn(tester, find.byKey(TrainingAnswerDialog.noneKey));

      expect(find.byKey(TrainingDetailScreen.answerFailureKey), findsOneWidget);
      expect(find.text('Only the Trainee can answer for themselves'), findsOneWidget);
    });
  });

  group('the record\'s reading of its answers', () {
    testWidgets('sent with nobody answered reads as waiting on everybody', (tester) async {
      await _open(tester, FakeWire(role: Roles.admin, trainingRecords: [_sent()]), '/training/1');
      expect(find.text('Sent: nobody has answered yet.'), findsOneWidget);
    });

    testWidgets('a draft reads as not sent', (tester) async {
      await _open(tester, FakeWire(role: Roles.admin, trainingRecords: [_completeDraft()]), '/training/1');
      expect(find.text('Not sent yet: nobody has been asked.'), findsOneWidget);
    });

    testWidgets('one declined reads as not fully confirmed, with each answer and its door', (tester) async {
      await _open(
        tester,
        FakeWire(role: Roles.admin, trainingRecords: [_sent(answer1: 'confirmed', answer2: 'declined')]),
        '/training/1',
      );
      expect(find.text('Not fully confirmed: 1 declined, 1 of 2 confirmed.'), findsOneWidget);
      expect(find.text('Confirmed on 2026-05-06 from their own Account'), findsOneWidget);
      expect(find.text('Declined on 2026-05-06 from their own Account'), findsOneWidget);
    });

    testWidgets('all confirmed reads as fully confirmed', (tester) async {
      await _open(
        tester,
        FakeWire(role: Roles.admin, trainingRecords: [_sent(answer1: 'confirmed', answer2: 'confirmed')]),
        '/training/1',
      );
      expect(find.text('Fully confirmed by all 2 Trainees.'), findsOneWidget);
    });
  });

  group('the signature step of confirming', () {
    testWidgets('Confirm opens the dialog and sends nothing until a choice is made', (tester) async {
      final wire = FakeWire(role: Roles.operator, selfEmployeeId: '7', trainingRecords: [_sent()]);
      await _open(tester, wire, '/training/1');
      await tapIn(tester, find.byKey(TrainingDetailScreen.confirmKey('t1')));

      expect(find.byKey(TrainingAnswerDialog.dialogKey), findsOneWidget);
      expect(find.byKey(TrainingAnswerDialog.useStoredKey), findsOneWidget);
      expect(find.byKey(TrainingAnswerDialog.drawKey), findsOneWidget);
      expect(find.byKey(TrainingAnswerDialog.noneKey), findsOneWidget);
      expect(wire.trainingAnswers, isEmpty);

      await tapIn(tester, find.byKey(TrainingAnswerDialog.cancelKey));
      expect(find.byKey(TrainingAnswerDialog.dialogKey), findsNothing);
      expect(wire.trainingAnswers, isEmpty);
    });

    testWidgets('"Use my Signature" sends use: stored and the record reads it back', (tester) async {
      final wire = FakeWire(role: Roles.operator, selfEmployeeId: '7', trainingRecords: [_sent()]);
      await _open(tester, wire, '/training/1');
      await tapIn(tester, find.byKey(TrainingDetailScreen.confirmKey('t1')));
      await tapIn(tester, find.byKey(TrainingAnswerDialog.useStoredKey));

      expect(wire.trainingAnswers.length, 1);
      expect(wire.trainingAnswers.single.$1, 'POST /api/people/training/trainees/t1/answer');
      expect(wire.trainingAnswers.single.$2, {
        'answer': 'confirmed',
        'signature': {'use': 'stored'},
      });
      expect(find.byKey(TrainingDetailScreen.traineeSignatureKey('t1')), findsOneWidget);
      expect(find.text('Signed with their kept Signature'), findsOneWidget);
    });

    testWidgets('"No Signature" sends the answer alone', (tester) async {
      final wire = FakeWire(role: Roles.operator, selfEmployeeId: '7', trainingRecords: [_sent()]);
      await _open(tester, wire, '/training/1');
      await tapIn(tester, find.byKey(TrainingDetailScreen.confirmKey('t1')));
      await tapIn(tester, find.byKey(TrainingAnswerDialog.noneKey));

      expect(wire.trainingAnswers.single.$2, {'answer': 'confirmed'});
      expect(find.byKey(TrainingDetailScreen.traineeSignatureKey('t1')), findsNothing);
    });

    testWidgets('"Draw one now" cannot be sent untouched, and sends the drawn PNG once drawn',
        (tester) async {
      final wire = FakeWire(role: Roles.operator, selfEmployeeId: '7', trainingRecords: [_sent()]);
      await _open(tester, wire, '/training/1');
      await tapIn(tester, find.byKey(TrainingDetailScreen.confirmKey('t1')));
      await tapIn(tester, find.byKey(TrainingAnswerDialog.drawKey));

      expect(find.byKey(TrainingAnswerDialog.padKey), findsOneWidget);
      final submit = find.byKey(TrainingAnswerDialog.submitDrawnKey);
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);

      await tester.drag(find.byKey(TrainingAnswerDialog.padKey), const Offset(120, 40));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
      expect(wire.trainingAnswers, isEmpty);

      // Rendering the strokes to a PNG goes through the engine, which a
      // fake-async test clock does not drive.
      await tester.runAsync(() async {
        await tester.tap(submit);
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await tester.pumpAndSettle();

      expect(wire.trainingAnswers.length, 1);
      final sent = wire.trainingAnswers.single.$2;
      expect(sent['answer'], 'confirmed');
      final image = (sent['signature'] as Map<String, dynamic>)['image'] as String;
      expect(base64Decode(image).sublist(0, 8), [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
      expect(find.text('Signed with a Signature drawn as they answered'), findsOneWidget);
    });

    testWidgets('the queue offers the same three choices, and a decline opens no dialog', (tester) async {
      final wire = FakeWire(role: Roles.operator, trainingToConfirm: [trainingToConfirmJson('t1')]);
      await _open(tester, wire, '/training/to-confirm');
      await tapIn(tester, find.byKey(TrainingToConfirmScreen.confirmKey('t1')));
      expect(find.byKey(TrainingAnswerDialog.useStoredKey), findsOneWidget);
      await tapIn(tester, find.byKey(TrainingAnswerDialog.useStoredKey));
      expect(wire.trainingAnswers.single.$2, {
        'answer': 'confirmed',
        'signature': {'use': 'stored'},
      });
    });

    testWidgets('declining opens no dialog', (tester) async {
      final wire = FakeWire(role: Roles.operator, trainingToConfirm: [trainingToConfirmJson('t1')]);
      await _open(tester, wire, '/training/to-confirm');
      await tapIn(tester, find.byKey(TrainingToConfirmScreen.declineKey('t1')));
      expect(find.byKey(TrainingAnswerDialog.dialogKey), findsNothing);
      expect(wire.trainingAnswers.single.$2, {'answer': 'declined'});
    });

    testWidgets('a refused stored Signature renders the server\'s words and leaves the row', (tester) async {
      final wire = FakeWire(
        role: Roles.operator,
        trainingToConfirm: [trainingToConfirmJson('t1')],
        trainingAnswerStatus: 400,
        trainingAnswerMessage: 'no Signature kept: draw one now or answer without one',
      );
      await _open(tester, wire, '/training/to-confirm');
      await tapIn(tester, find.byKey(TrainingToConfirmScreen.confirmKey('t1')));
      await tapIn(tester, find.byKey(TrainingAnswerDialog.useStoredKey));

      expect(find.byKey(TrainingToConfirmScreen.rowKey('t1')), findsOneWidget);
      expect(find.text('no Signature kept: draw one now or answer without one'), findsOneWidget);
    });
  });
}
