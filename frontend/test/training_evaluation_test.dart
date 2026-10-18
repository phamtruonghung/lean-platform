/// What the trainer recorded about each Trainee (issue #290, ADR-0043): the
/// two-value picker on the detail Screen, its clear affordance and the request
/// it issues - with the wire faked, the one client seam (AGENTS.md section 5).
/// Everything asserted is rendered text, a Key, or a request the fake wire
/// recorded.
///
/// A caller-without-a-Grant case is its own test, never a second `pumpApp` in
/// one test: the app-level providers survive a re-pump.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/people/training_detail_screen.dart';
import 'package:lean_platform/platform/destinations.dart';

import 'harness.dart';

Future<void> _open(WidgetTester tester, FakeWire wire) {
  // A lazy ListView builds only what is on screen, so `find.byKey` cannot see
  // a row below the fold of the default 800x600 window. Pin a taller one.
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  return pumpApp(
    tester,
    gateway: FakeAuthGateway(accessToken: 'a-token'),
    client: wire.client,
    initialLocation: '/training/1',
  );
}

Map<String, dynamic> _record({String status = 'draft', String? evaluation1, String? evaluation2}) =>
    trainingRecordJson(
      '1',
      status: status,
      trainerEmployeeId: '9',
      trainerName: 'Tina Trainer',
      objective: 'Everyone can isolate the press',
      trainees: [
        traineeJson('t1', '7', 'E-7', 'Alice Nguyen', evaluation: evaluation1),
        traineeJson('t2', '8', 'E-8', 'Bao Tran', evaluation: evaluation2),
      ],
    );

void main() {
  testWidgets('the picker offers exactly Paper and Job-training, on each Trainee', (tester) async {
    await _open(tester, FakeWire(role: Roles.admin, trainingRecords: [_record()]));

    for (final id in ['t1', 't2']) {
      expect(find.byKey(TrainingDetailScreen.evaluationChoiceKey(id, 'paper')), findsOneWidget);
      expect(find.byKey(TrainingDetailScreen.evaluationChoiceKey(id, 'job_training')), findsOneWidget);
    }
    final picker = find.byKey(TrainingDetailScreen.evaluationKey('t1'));
    expect(find.descendant(of: picker, matching: find.byType(ChoiceChip)), findsNWidgets(2));
    expect(find.descendant(of: picker, matching: find.text('Paper')), findsOneWidget);
    expect(find.descendant(of: picker, matching: find.text('Job-training')), findsOneWidget);
    // Chosen, never typed, and nothing to clear on a Trainee nobody evaluated.
    expect(find.byType(TextField), findsNothing);
    expect(find.byKey(TrainingDetailScreen.evaluationClearKey('t1')), findsNothing);
  });

  testWidgets('choosing Paper issues the request and the choice reads back', (tester) async {
    final wire = FakeWire(role: Roles.admin, trainingRecords: [_record()]);
    await _open(tester, wire);
    await tapIn(tester, find.byKey(TrainingDetailScreen.evaluationChoiceKey('t1', 'paper')));

    expect(wire.traineeEvaluations.length, 1);
    expect(wire.traineeEvaluations.single.$1, 'PATCH /api/people/training/1/trainees/t1');
    expect(wire.traineeEvaluations.single.$2, {'evaluation': 'paper'});
    final chip = tester.widget<ChoiceChip>(find.byKey(TrainingDetailScreen.evaluationChoiceKey('t1', 'paper')));
    expect(chip.selected, isTrue);
    expect(find.byKey(TrainingDetailScreen.evaluationClearKey('t1')), findsOneWidget);
  });

  testWidgets('choosing Job-training issues the request, on a sent record too', (tester) async {
    final wire = FakeWire(role: Roles.admin, trainingRecords: [_record(status: 'sent')]);
    await _open(tester, wire);
    await tapIn(tester, find.byKey(TrainingDetailScreen.evaluationChoiceKey('t2', 'job_training')));

    expect(wire.traineeEvaluations.length, 1);
    expect(wire.traineeEvaluations.single.$1, 'PATCH /api/people/training/1/trainees/t2');
    expect(wire.traineeEvaluations.single.$2, {'evaluation': 'job_training'});
    final chip = tester.widget<ChoiceChip>(find.byKey(TrainingDetailScreen.evaluationChoiceKey('t2', 'job_training')));
    expect(chip.selected, isTrue);
  });

  testWidgets('clearing returns the Trainee to unevaluated with evaluation: null', (tester) async {
    final wire = FakeWire(role: Roles.admin, trainingRecords: [_record(evaluation1: 'paper')]);
    await _open(tester, wire);
    await tapIn(tester, find.byKey(TrainingDetailScreen.evaluationClearKey('t1')));

    expect(wire.traineeEvaluations.length, 1);
    expect(wire.traineeEvaluations.single.$1, 'PATCH /api/people/training/1/trainees/t1');
    expect(wire.traineeEvaluations.single.$2, {'evaluation': null});
    final chip = tester.widget<ChoiceChip>(find.byKey(TrainingDetailScreen.evaluationChoiceKey('t1', 'paper')));
    expect(chip.selected, isFalse);
    expect(find.byKey(TrainingDetailScreen.evaluationClearKey('t1')), findsNothing);
  });

  testWidgets('a refused evaluation says why and leaves the choice as it was', (tester) async {
    final wire = FakeWire(
      role: Roles.admin,
      trainingRecords: [_record()],
      traineeWriteStatus: 403,
      traineeWriteMessage: "Outside the caller's granted Org Units",
    );
    await _open(tester, wire);
    await tapIn(tester, find.byKey(TrainingDetailScreen.evaluationChoiceKey('t1', 'paper')));

    expect(find.byKey(TrainingDetailScreen.evaluationFailureKey), findsOneWidget);
    expect(find.text("Outside the caller's granted Org Units"), findsOneWidget);
    final chip = tester.widget<ChoiceChip>(find.byKey(TrainingDetailScreen.evaluationChoiceKey('t1', 'paper')));
    expect(chip.selected, isFalse);
  });

  testWidgets('a caller with no edit Grant at the Org Unit sees the recorded value as text and no picker',
      (tester) async {
    final wire = FakeWire(
      role: Roles.supervisor,
      orgUnitScope: {
        'everywhere': false,
        'grants': [scopeGrantJson('99', canWrite: true)],
      },
      trainingRecords: [_record(status: 'sent', evaluation1: 'job_training')],
    );
    await _open(tester, wire);

    expect(find.byKey(TrainingDetailScreen.traineeRowKey('t1')), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.byKey(TrainingDetailScreen.evaluationClearKey('t1')), findsNothing);
    expect(find.byKey(TrainingDetailScreen.evaluationKey('t1')), findsOneWidget);
    expect(find.text('Evaluated: Job-training'), findsOneWidget);
    // Nobody evaluated t2, so it shows nothing at all.
    expect(find.byKey(TrainingDetailScreen.evaluationKey('t2')), findsNothing);
  });
}
