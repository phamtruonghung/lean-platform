/// The Trainees on a Training record (issue #288, ADR-0043) — the Trainee
/// section of the record's Screen and the add dialog — with the wire faked,
/// the one client seam (AGENTS.md section 5). Everything asserted is rendered
/// text, a Key, or a request the fake wire recorded.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/people/training_detail_screen.dart';
import 'package:lean_platform/people/training_trainee_dialog.dart';
import 'package:lean_platform/platform/destinations.dart';
import 'package:lean_platform/widgets/failure_state.dart';

import 'harness.dart';

FakeWire _wire({
  required List<Map<String, dynamic>> trainingRecords,
  int traineeWriteStatus = 200,
  String traineeWriteMessage = 'That Trainee could not be saved.',
  int employeesStatus = 200,
}) =>
    FakeWire(
      role: Roles.admin,
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      employees: [
        employeeJson('7', 'E-7', 'Alice Nguyen'),
        employeeJson('8', 'E-8', 'Bao Tran'),
      ],
      employeesStatus: employeesStatus,
      trainingRecords: trainingRecords,
      traineeWriteStatus: traineeWriteStatus,
      traineeWriteMessage: traineeWriteMessage,
    );

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

FilledButton _submit(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(TrainingTraineeDialog.submitKey));

Future<void> _openDialog(WidgetTester tester, FakeWire wire) async {
  await _open(tester, wire);
  await tapIn(tester, find.byKey(TrainingDetailScreen.addTraineeKey));
}

void main() {
  group('the Trainee section', () {
    testWidgets('lists each Trainee by number and name in order, under a heading carrying the count',
        (tester) async {
      final wire = _wire(trainingRecords: [
        trainingRecordJson('1', trainees: [
          traineeJson('11', '8', 'E-8', 'Bao Tran'),
          traineeJson('12', '7', 'E-7', 'Alice Nguyen'),
        ]),
      ]);
      await _open(tester, wire);

      expect(find.text('Trainees (2)'), findsOneWidget);
      expect(find.byKey(TrainingDetailScreen.traineeRowKey('11')), findsOneWidget);
      expect(find.byKey(TrainingDetailScreen.traineeRowKey('12')), findsOneWidget);
      expect(find.text('E-8 · Bao Tran'), findsOneWidget);
      expect(find.text('E-7 · Alice Nguyen'), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(TrainingDetailScreen.traineeRowKey('11'))).dy,
        lessThan(tester.getTopLeft(find.byKey(TrainingDetailScreen.traineeRowKey('12'))).dy),
      );
      expect(find.byKey(TrainingDetailScreen.noTraineesKey), findsNothing);
    });

    testWidgets('with nobody on it the section says so, and still offers to add', (tester) async {
      await _open(tester, _wire(trainingRecords: [trainingRecordJson('1')]));

      expect(find.text('Trainees (0)'), findsOneWidget);
      expect(find.byKey(TrainingDetailScreen.noTraineesKey), findsOneWidget);
      expect(find.text('No Trainees are on this Training record yet.'), findsOneWidget);
      expect(find.byKey(TrainingDetailScreen.addTraineeKey), findsOneWidget);
    });

    testWidgets('a sent record carries the add and the remove controls too, for a caller who can correct it',
        (tester) async {
      await _open(
        tester,
        _wire(trainingRecords: [
          trainingRecordJson('1', status: 'sent', trainees: [traineeJson('11', '7', 'E-7', 'Alice Nguyen')]),
        ]),
      );

      expect(find.text('E-7 · Alice Nguyen'), findsOneWidget);
      expect(find.byKey(TrainingDetailScreen.addTraineeKey), findsOneWidget);
      expect(find.byKey(TrainingDetailScreen.removeTraineeKey('11')), findsOneWidget);
    });

    testWidgets('the remove control issues the DELETE and the row goes', (tester) async {
      final wire = _wire(trainingRecords: [
        trainingRecordJson('1', trainees: [
          traineeJson('11', '7', 'E-7', 'Alice Nguyen'),
          traineeJson('12', '8', 'E-8', 'Bao Tran'),
        ]),
      ]);
      await _open(tester, wire);

      await tapIn(tester, find.byKey(TrainingDetailScreen.removeTraineeKey('11')));

      expect(wire.traineeWrites.single.$1, 'DELETE /api/people/training/1/trainees/11');
      expect(wire.traineeWrites.single.$2, isEmpty);
      expect(find.byKey(TrainingDetailScreen.traineeRowKey('11')), findsNothing);
      expect(find.byKey(TrainingDetailScreen.traineeRowKey('12')), findsOneWidget);
      expect(find.text('Trainees (1)'), findsOneWidget);
    });

    testWidgets('a refused removal is shown on the Screen and the row stays', (tester) async {
      final wire = _wire(
        trainingRecords: [
          trainingRecordJson('1', trainees: [traineeJson('11', '7', 'E-7', 'Alice Nguyen')]),
        ],
        traineeWriteStatus: 403,
        traineeWriteMessage: "Outside the caller's granted Org Units",
      );
      await _open(tester, wire);

      await tapIn(tester, find.byKey(TrainingDetailScreen.removeTraineeKey('11')));

      expect(find.byKey(TrainingDetailScreen.removeFailureKey), findsOneWidget);
      expect(find.text("Outside the caller's granted Org Units"), findsOneWidget);
      expect(find.byKey(TrainingDetailScreen.traineeRowKey('11')), findsOneWidget);
    });
  });

  group('the add dialog', () {
    testWidgets('keeps the submit gate shut until an Employee is picked, and sends nothing meanwhile',
        (tester) async {
      final wire = _wire(trainingRecords: [trainingRecordJson('1')]);
      await _openDialog(tester, wire);

      expect(find.byType(TrainingTraineeDialog), findsOneWidget);
      expect(_submit(tester).onPressed, isNull);
      expect(wire.traineeWrites, isEmpty);

      await pickSuggestion(
        tester,
        fieldKey: TrainingTraineeDialog.employeeFieldKey(),
        term: 'Alice',
        suggestionKey: TrainingTraineeDialog.employeeSuggestionKey('7'),
      );
      expect(_submit(tester).onPressed, isNotNull);
      expect(searchFieldText(tester, TrainingTraineeDialog.employeeFieldKey()), 'Alice Nguyen');
    });

    testWidgets('defaults to the record\'s own Org Unit\'s Employees', (tester) async {
      final wire = _wire(trainingRecords: [trainingRecordJson('1', orgUnitId: '10', orgUnitName: 'Assembly')]);
      await _openDialog(tester, wire);

      await typeInSearchField(tester, TrainingTraineeDialog.employeeFieldKey(), 'Alice');

      expect(wire.employeeRequests.last['orgUnitId'], '10');
      expect(wire.employeeRequests.last['search'], 'Alice');
    });

    testWidgets('reaches any Employee in the Directory when asked to', (tester) async {
      final wire = _wire(trainingRecords: [trainingRecordJson('1', orgUnitId: '10')]);
      await _openDialog(tester, wire);

      await tapIn(tester, find.text('Whole Directory'));
      await typeInSearchField(tester, TrainingTraineeDialog.employeeFieldKey(), 'Bao');

      expect(wire.employeeRequests.last['orgUnitId'], isNull);
      expect(find.byKey(TrainingTraineeDialog.employeeSuggestionKey('8')), findsOneWidget);
    });

    testWidgets('submitting sends one POST naming the Employee, closes, and the Trainee is listed',
        (tester) async {
      final wire = _wire(trainingRecords: [trainingRecordJson('1')]);
      await _openDialog(tester, wire);

      await pickSuggestion(
        tester,
        fieldKey: TrainingTraineeDialog.employeeFieldKey(),
        term: 'Alice',
        suggestionKey: TrainingTraineeDialog.employeeSuggestionKey('7'),
      );
      await tapIn(tester, find.byKey(TrainingTraineeDialog.submitKey));

      expect(wire.traineeWrites.single.$1, 'POST /api/people/training/1/trainees');
      expect(wire.traineeWrites.single.$2, {'employeeId': '7'});
      expect(find.byType(TrainingTraineeDialog), findsNothing);
      expect(find.text('E-7 · Alice Nguyen'), findsOneWidget);
      expect(find.text('Trainees (1)'), findsOneWidget);
    });

    testWidgets('a term nothing matches says so and leaves the gate shut', (tester) async {
      final wire = _wire(trainingRecords: [trainingRecordJson('1')]);
      await _openDialog(tester, wire);

      await typeInSearchField(tester, TrainingTraineeDialog.employeeFieldKey(), 'Zzzzz');

      expect(find.text('No matches'), findsOneWidget);
      expect(_submit(tester).onPressed, isNull);
    });

    testWidgets('a failed read shows the failure state and leaves the gate shut', (tester) async {
      final wire = _wire(trainingRecords: [trainingRecordJson('1')], employeesStatus: 500);
      await _openDialog(tester, wire);

      await typeInSearchField(tester, TrainingTraineeDialog.employeeFieldKey(), 'Alice');

      expect(find.byType(PlatformFailureState), findsOneWidget);
      expect(_submit(tester).onPressed, isNull);
    });

    testWidgets('a server refusal is shown inside the dialog, which stays open', (tester) async {
      final wire = _wire(
        trainingRecords: [trainingRecordJson('1')],
        traineeWriteStatus: 409,
        traineeWriteMessage: 'this Employee is already a Trainee on this Training record',
      );
      await _openDialog(tester, wire);

      await pickSuggestion(
        tester,
        fieldKey: TrainingTraineeDialog.employeeFieldKey(),
        term: 'Alice',
        suggestionKey: TrainingTraineeDialog.employeeSuggestionKey('7'),
      );
      await tapIn(tester, find.byKey(TrainingTraineeDialog.submitKey));

      expect(find.byKey(TrainingTraineeDialog.failureKey), findsOneWidget);
      expect(find.text('this Employee is already a Trainee on this Training record'), findsOneWidget);
      expect(find.byType(TrainingTraineeDialog), findsOneWidget);
      expect(wire.traineeWrites.length, 1);
    });

    testWidgets('cancelling closes the dialog without sending anything', (tester) async {
      final wire = _wire(trainingRecords: [trainingRecordJson('1')]);
      await _openDialog(tester, wire);

      await tapIn(tester, find.byKey(TrainingTraineeDialog.cancelKey));

      expect(find.byType(TrainingTraineeDialog), findsNothing);
      expect(wire.traineeWrites, isEmpty);
    });
  });
}
