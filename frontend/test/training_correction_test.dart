/// Putting a Training record right (issue #291, ADR-0043): the correction
/// dialog on a draft and on a sent record, the discard confirmation on a
/// draft, and the Trainee controls on a sent record - with the wire faked, the
/// one client seam (AGENTS.md section 5). Everything asserted is rendered
/// text, a Key, or a request the fake wire recorded.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/people/training_detail_screen.dart';
import 'package:lean_platform/people/training_raise_dialog.dart';
import 'package:lean_platform/people/training_trainee_dialog.dart';
import 'package:lean_platform/platform/destinations.dart';

import 'harness.dart';

Map<String, dynamic> _record({String status = 'draft'}) => trainingRecordJson(
      '1',
      title: 'Lockout and tagout refresher',
      trainedOn: '2026-05-04',
      durationHours: 2,
      trainerEmployeeId: '8',
      trainerName: 'Bao Tran',
      objective: 'Everyone can isolate the press',
      status: status,
      trainees: [traineeJson('11', '7', 'E-7', 'Alice Nguyen')],
    );

FakeWire _wire({
  required Map<String, dynamic> record,
  String role = Roles.admin,
  Map<String, dynamic>? orgUnitScope,
  int recordWriteStatus = 200,
  String recordWriteMessage = 'That Training record could not be changed.',
}) =>
    FakeWire(
      role: role,
      orgUnitScope: orgUnitScope,
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [orgUnitJson('10', 'Assembly')],
      },
      employees: [
        employeeJson('7', 'E-7', 'Alice Nguyen'),
        employeeJson('8', 'E-8', 'Bao Tran'),
      ],
      trainingRecords: [record],
      recordWriteStatus: recordWriteStatus,
      recordWriteMessage: recordWriteMessage,
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

String _text(WidgetTester tester, Key key) => tester.widget<TextField>(find.byKey(key)).controller!.text;

FilledButton _submit(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(TrainingRaiseDialog.submitKey));

void main() {
  group('the correction dialog', () {
    for (final status in ['draft', 'sent']) {
      testWidgets('opens on a $status record with its facts pre-filled and no Org Unit picker', (tester) async {
        await _open(tester, _wire(record: _record(status: status)));

        await tapIn(tester, find.byKey(TrainingDetailScreen.correctKey));

        expect(find.text('Correct training record'), findsWidgets);
        expect(_text(tester, TrainingRaiseDialog.titleKey), 'Lockout and tagout refresher');
        expect(_text(tester, TrainingRaiseDialog.durationKey), '2');
        expect(_text(tester, TrainingRaiseDialog.objectiveKey), 'Everyone can isolate the press');
        expect(searchFieldText(tester, TrainingRaiseDialog.trainerFieldKey()), 'Bao Tran');
        expect(
          find.descendant(of: find.byKey(TrainingRaiseDialog.trainedOnKey), matching: find.text('2026-05-04')),
          findsOneWidget,
        );
        expect(find.text('Where it was given'), findsNothing);
        expect(_submit(tester).onPressed, isNotNull);
      });
    }

    testWidgets('restating a sent record issues one PATCH with every fact, and the Screen shows the correction',
        (tester) async {
      final wire = _wire(record: _record(status: 'sent'));
      await _open(tester, wire);
      await tapIn(tester, find.byKey(TrainingDetailScreen.correctKey));

      await tester.enterText(find.byKey(TrainingRaiseDialog.titleKey), 'Lockout and tagout, corrected');
      await tester.pumpAndSettle();
      await tapIn(tester, find.byKey(TrainingRaiseDialog.submitKey));

      expect(wire.recordWrites.single.$1, 'PATCH /api/people/training/1');
      expect(wire.recordWrites.single.$2, {
        'title': 'Lockout and tagout, corrected',
        'trainedOn': '2026-05-04',
        'durationHours': 2.0,
        'trainerEmployeeId': '8',
        'objective': 'Everyone can isolate the press',
      });
      expect(find.byType(TrainingRaiseDialog), findsNothing);
      expect(find.text('Lockout and tagout, corrected'), findsOneWidget);
    });

    testWidgets('a draft is corrected the same way, and clearing the objective sends it as null', (tester) async {
      final wire = _wire(record: _record());
      await _open(tester, wire);
      await tapIn(tester, find.byKey(TrainingDetailScreen.correctKey));

      await tester.enterText(find.byKey(TrainingRaiseDialog.objectiveKey), '');
      await tester.pumpAndSettle();
      await tapIn(tester, find.byKey(TrainingRaiseDialog.submitKey));

      expect(wire.recordWrites.single.$1, 'PATCH /api/people/training/1');
      expect(wire.recordWrites.single.$2['objective'], isNull);
      expect(wire.recordWrites.single.$2['title'], 'Lockout and tagout refresher');
    });

    testWidgets('a refusal is shown inside the dialog, which stays open with what was entered', (tester) async {
      final wire = _wire(
        record: _record(),
        recordWriteStatus: 403,
        recordWriteMessage: "Outside the caller's granted Org Units",
      );
      await _open(tester, wire);
      await tapIn(tester, find.byKey(TrainingDetailScreen.correctKey));
      await tester.enterText(find.byKey(TrainingRaiseDialog.titleKey), 'Changed');
      await tester.pumpAndSettle();

      await tapIn(tester, find.byKey(TrainingRaiseDialog.submitKey));

      expect(find.byKey(TrainingRaiseDialog.failureKey), findsOneWidget);
      expect(find.text("Outside the caller's granted Org Units"), findsOneWidget);
      expect(_text(tester, TrainingRaiseDialog.titleKey), 'Changed');
    });

    testWidgets('the submit gate shuts when the title is emptied, and nothing is sent', (tester) async {
      final wire = _wire(record: _record());
      await _open(tester, wire);
      await tapIn(tester, find.byKey(TrainingDetailScreen.correctKey));

      await tester.enterText(find.byKey(TrainingRaiseDialog.titleKey), '  ');
      await tester.pumpAndSettle();

      expect(_submit(tester).onPressed, isNull);
      expect(wire.recordWrites, isEmpty);
    });

    testWidgets('a caller with no edit Grant is offered neither the correction nor the discard', (tester) async {
      final wire = _wire(
        record: _record(),
        role: Roles.operator,
        orgUnitScope: {
          'everywhere': false,
          'grants': [scopeGrantJson('10')],
        },
      );
      await _open(tester, wire);

      expect(find.byKey(TrainingDetailScreen.numberKey), findsOneWidget);
      expect(find.byKey(TrainingDetailScreen.correctKey), findsNothing);
      expect(find.byKey(TrainingDetailScreen.discardKey), findsNothing);
    });
  });

  group('discarding a draft', () {
    testWidgets('asks first, and cancelling issues nothing', (tester) async {
      final wire = _wire(record: _record());
      await _open(tester, wire);

      await tapIn(tester, find.byKey(TrainingDetailScreen.discardKey));
      expect(find.text('Discard this draft?'), findsOneWidget);
      await tapIn(tester, find.byKey(TrainingDetailScreen.discardCancelKey));

      expect(find.text('Discard this draft?'), findsNothing);
      expect(wire.recordWrites, isEmpty);
      expect(find.byKey(TrainingDetailScreen.numberKey), findsOneWidget);
    });

    testWidgets('confirming issues the DELETE and returns to the register', (tester) async {
      final wire = _wire(record: _record());
      await _open(tester, wire);

      await tapIn(tester, find.byKey(TrainingDetailScreen.discardKey));
      await tapIn(tester, find.byKey(TrainingDetailScreen.discardConfirmKey));

      expect(wire.recordWrites.single.$1, 'DELETE /api/people/training/1');
      expect(find.byType(TrainingDetailScreen), findsNothing);
    });

    testWidgets('a refusal is shown on the Screen and the draft stays', (tester) async {
      final wire = _wire(
        record: _record(),
        recordWriteStatus: 409,
        recordWriteMessage: 'A sent Training record is evidence and cannot be discarded; correct it instead',
      );
      await _open(tester, wire);

      await tapIn(tester, find.byKey(TrainingDetailScreen.discardKey));
      await tapIn(tester, find.byKey(TrainingDetailScreen.discardConfirmKey));

      expect(find.byKey(TrainingDetailScreen.discardFailureKey), findsOneWidget);
      expect(find.byKey(TrainingDetailScreen.numberKey), findsOneWidget);
    });

    testWidgets('a sent record offers no discard', (tester) async {
      await _open(tester, _wire(record: _record(status: 'sent')));

      expect(find.byKey(TrainingDetailScreen.correctKey), findsOneWidget);
      expect(find.byKey(TrainingDetailScreen.discardKey), findsNothing);
    });
  });

  group('the Trainees of a sent record', () {
    testWidgets('removing one issues the DELETE, and the row goes', (tester) async {
      final wire = _wire(record: _record(status: 'sent'));
      await _open(tester, wire);

      await tapIn(tester, find.byKey(TrainingDetailScreen.removeTraineeKey('11')));

      expect(wire.traineeWrites.single.$1, 'DELETE /api/people/training/1/trainees/11');
      expect(find.byKey(TrainingDetailScreen.traineeRowKey('11')), findsNothing);
    });

    testWidgets('adding one issues the POST naming the Employee, and the row appears', (tester) async {
      final wire = _wire(record: _record(status: 'sent'));
      await _open(tester, wire);

      await tapIn(tester, find.byKey(TrainingDetailScreen.addTraineeKey));
      await pickSuggestion(
        tester,
        fieldKey: TrainingTraineeDialog.employeeFieldKey(),
        term: 'Bao',
        suggestionKey: TrainingTraineeDialog.employeeSuggestionKey('8'),
      );
      await tapIn(tester, find.byKey(TrainingTraineeDialog.submitKey));

      expect(wire.traineeWrites.single.$1, 'POST /api/people/training/1/trainees');
      expect(wire.traineeWrites.single.$2, {'employeeId': '8'});
      expect(find.text('E-8 · Bao Tran'), findsOneWidget);
    });
  });
}
