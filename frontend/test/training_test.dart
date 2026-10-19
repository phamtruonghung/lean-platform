/// The Training record register, the raise dialog and one record's Screen
/// (issue #287, ADR-0043) — with the wire faked, the one client seam
/// (AGENTS.md section 5). Everything asserted is rendered text, a Key, or a
/// request the fake wire recorded.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lean_platform/people/training_detail_screen.dart';
import 'package:lean_platform/people/training_raise_dialog.dart';
import 'package:lean_platform/people/training_screen.dart';
import 'package:lean_platform/platform/destinations.dart';
import 'package:lean_platform/platform/router.dart';

import 'harness.dart';

FakeWire _wire({
  List<Map<String, dynamic>>? trainingRecords,
  int trainingStatus = 200,
  bool trainingTruncated = false,
  int trainingWriteStatus = 201,
  String trainingWriteMessage = 'That Training record could not be saved.',
  String role = Roles.admin,
  Map<String, dynamic>? orgUnitScope,
}) =>
    FakeWire(
      role: role,
      orgUnitScope: orgUnitScope,
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [orgUnitJson('10', 'Assembly')],
        '10': [orgUnitJson('11', 'Line 1', parentId: '10', unitType: 'line')],
      },
      employees: [employeeJson('7', 'E-7', 'Alice Nguyen')],
      trainingRecords: trainingRecords,
      trainingStatus: trainingStatus,
      trainingTruncated: trainingTruncated,
      trainingWriteStatus: trainingWriteStatus,
      trainingWriteMessage: trainingWriteMessage,
    );

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

int _postCount(FakeWire wire) => wire.requests.where((r) => r == 'POST /api/people/training').length;

void main() {
  group('register', () {
    testWidgets('says so when the server capped the register', (tester) async {
      final capped = _wire(
        trainingRecords: [trainingRecordJson('1', title: 'Forklift safety', status: 'sent')],
        trainingTruncated: true,
      );
      await _open(tester, capped, Routes.training);
      expect(find.byKey(TrainingScreen.rowKey('1')), findsOneWidget);
      expect(find.byKey(TrainingScreen.truncatedKey), findsOneWidget);
    });

    testWidgets('says nothing about a cap when the register is whole', (tester) async {
      final whole = _wire(trainingRecords: [trainingRecordJson('1', title: 'Forklift safety', status: 'sent')]);
      await _open(tester, whole, Routes.training);
      expect(find.byKey(TrainingScreen.rowKey('1')), findsOneWidget);
      expect(find.byKey(TrainingScreen.truncatedKey), findsNothing);
    });

    testWidgets(
        'shows each record with its number, title, day, Org Unit, hours and trainer, and marks '
        'only the drafts', (tester) async {
      final wire = _wire(trainingRecords: [
        trainingRecordJson(
          '1',
          number: 'TR-HCM-2026-00001',
          title: 'Forklift safety',
          trainedOn: '2026-05-04',
          orgUnitName: 'Assembly',
          durationHours: 1.5,
          trainerName: 'Alice Nguyen',
          status: 'draft',
        ),
        trainingRecordJson('2', number: 'TR-HCM-2026-00002', title: 'Welding basics', status: 'sent'),
      ]);
      await _open(tester, wire, Routes.training);

      expect(find.byKey(TrainingScreen.rowKey('1')), findsOneWidget);
      expect(find.byKey(TrainingScreen.rowKey('2')), findsOneWidget);
      expect(find.text('TR-HCM-2026-00001 · Forklift safety'), findsOneWidget);
      expect(find.textContaining('2026-05-04'), findsWidgets);
      expect(find.textContaining('Assembly'), findsWidgets);
      expect(find.textContaining('1.5 h'), findsOneWidget);
      expect(find.textContaining('Trainer: Alice Nguyen'), findsOneWidget);
      expect(find.byKey(TrainingScreen.draftKey('1')), findsOneWidget);
      expect(find.byKey(TrainingScreen.draftKey('2')), findsNothing);
      // No filter was set, so the read carried none.
      expect(wire.trainingReads.single, isEmpty);
    });

    testWidgets('an empty register shows its own empty state', (tester) async {
      await _open(tester, _wire(), Routes.training);

      expect(find.byKey(TrainingScreen.emptyKey), findsOneWidget);
      expect(find.text('No Training records yet'), findsOneWidget);
    });

    testWidgets('a failed read shows its own failure state and retrying reads again', (tester) async {
      final wire = _wire(trainingStatus: 500);
      await _open(tester, wire, Routes.training);

      expect(find.byKey(TrainingScreen.failureKey), findsOneWidget);
      expect(find.text('Training records are unavailable.'), findsOneWidget);
      expect(find.byKey(TrainingScreen.emptyKey), findsNothing);

      wire.trainingStatus = 200;
      await tapIn(tester, find.byKey(TrainingScreen.retryKey));
      expect(wire.trainingReads.length, 2);
      expect(find.byKey(TrainingScreen.failureKey), findsNothing);
    });

    testWidgets('choosing an Org Unit filters the read by it, and clearing it reads again',
        (tester) async {
      final wire = _wire(trainingRecords: [trainingRecordJson('1')]);
      await _open(tester, wire, Routes.training);

      await tapIn(tester, find.byKey(TrainingScreen.orgUnitBrowseToggleKey));
      await tapIn(tester, find.byKey(TrainingScreen.orgUnitRowKey('10')));

      expect(wire.trainingReads.last, {'orgUnitId': '10'});
      expect(find.byKey(TrainingScreen.orgUnitChosenKey), findsOneWidget);
      expect(find.text('Org Unit: Assembly'), findsOneWidget);

      await tapIn(tester, find.byKey(TrainingScreen.orgUnitClearKey));
      expect(wire.trainingReads.last, isEmpty);
    });

    testWidgets('choosing a From date sends it as a filter on the next read', (tester) async {
      final wire = _wire(trainingRecords: [trainingRecordJson('1')]);
      await _open(tester, wire, Routes.training);
      expect(wire.trainingReads.single, isEmpty);

      await pickDate(tester, TrainingScreen.fromFieldKey, DateTime(2026, 5, 1));

      expect(wire.trainingReads.last, {'from': '2026-05-01'});
    });

    testWidgets('a filter that matches nothing says so rather than offering to raise one',
        (tester) async {
      final wire = _wire();
      await _open(tester, wire, Routes.training);
      await tapIn(tester, find.byKey(TrainingScreen.orgUnitBrowseToggleKey));
      await tapIn(tester, find.byKey(TrainingScreen.orgUnitRowKey('10')));

      expect(find.text('No Training records match'), findsOneWidget);
      expect(find.byKey(TrainingScreen.emptyRaiseKey), findsNothing);
    });

    testWidgets('a caller with no edit Grant is not offered the raise control', (tester) async {
      final wire = _wire(
        role: Roles.operator,
        orgUnitScope: {
          'everywhere': false,
          'grants': [scopeGrantJson('10')],
        },
        trainingRecords: [trainingRecordJson('1')],
      );
      await _open(tester, wire, Routes.training);

      expect(find.byKey(TrainingScreen.rowKey('1')), findsOneWidget);
      expect(find.byKey(TrainingScreen.raiseKey), findsNothing);
    });

    testWidgets('tapping a row opens that record at its own address', (tester) async {
      final wire = _wire(trainingRecords: [trainingRecordJson('1')]);
      await _open(tester, wire, Routes.training);

      await tapIn(tester, find.byKey(TrainingScreen.rowKey('1')));

      expect(find.byType(TrainingDetailScreen), findsOneWidget);
      expect(locationOf(tester, find.byType(TrainingDetailScreen)), '/training/1');
    });
  });

  group('raise dialog', () {
    Future<void> openDialog(WidgetTester tester, FakeWire wire) async {
      await _open(tester, wire, Routes.training);
      await tapIn(tester, find.byKey(TrainingScreen.raiseKey));
    }

    FilledButton submit(WidgetTester tester) =>
        tester.widget<FilledButton>(find.byKey(TrainingRaiseDialog.submitKey));

    testWidgets('the submit gate stays closed until Org Unit, title, day and a positive duration '
        'are all present, and nothing is sent meanwhile', (tester) async {
      final wire = _wire();
      await openDialog(tester, wire);

      expect(submit(tester).onPressed, isNull);

      await tester.enterText(find.byKey(TrainingRaiseDialog.titleKey), 'Forklift safety');
      await tester.pumpAndSettle();
      expect(submit(tester).onPressed, isNull);

      await pickDate(tester, TrainingRaiseDialog.trainedOnKey, DateTime(2026, 5, 4));
      expect(submit(tester).onPressed, isNull);

      await tester.enterText(find.byKey(TrainingRaiseDialog.durationKey), '0');
      await tester.pumpAndSettle();
      await tapIn(tester, find.byKey(TrainingRaiseDialog.orgUnitKey('10')));
      expect(submit(tester).onPressed, isNull, reason: 'zero hours is not a duration');

      await tester.enterText(find.byKey(TrainingRaiseDialog.durationKey), '1.5');
      await tester.pumpAndSettle();
      expect(submit(tester).onPressed, isNotNull);

      expect(_postCount(wire), 0);
      expect(wire.trainingWrites, isEmpty);
    });

    testWidgets('submitting sends one POST with the chosen facts, closes, and the new draft '
        'is in the register', (tester) async {
      final wire = _wire();
      await openDialog(tester, wire);

      await tester.enterText(find.byKey(TrainingRaiseDialog.titleKey), '  Forklift safety ');
      await pickDate(tester, TrainingRaiseDialog.trainedOnKey, DateTime(2026, 5, 4));
      await tester.enterText(find.byKey(TrainingRaiseDialog.durationKey), '1.5');
      await tester.enterText(find.byKey(TrainingRaiseDialog.objectiveKey), 'Isolate energy safely');
      await pickSuggestion(
        tester,
        fieldKey: TrainingRaiseDialog.trainerFieldKey(),
        term: 'Alice',
        suggestionKey: TrainingRaiseDialog.trainerSuggestionKey('7'),
      );
      await tapIn(tester, find.byKey(TrainingRaiseDialog.orgUnitKey('10')));
      await tapIn(tester, find.byKey(TrainingRaiseDialog.submitKey));

      expect(_postCount(wire), 1);
      expect(wire.trainingWrites.single, {
        'orgUnitId': '10',
        'title': 'Forklift safety',
        'trainedOn': '2026-05-04',
        'durationHours': 1.5,
        'trainerEmployeeId': '7',
        'objective': 'Isolate energy safely',
      });
      expect(find.byType(TrainingRaiseDialog), findsNothing);
      expect(find.text('TR-HCM-2026-00001 · Forklift safety'), findsOneWidget);
      expect(find.byKey(TrainingScreen.draftKey('new-1')), findsOneWidget);
    });

    testWidgets('the optional trainer and objective are left out of the request when blank',
        (tester) async {
      final wire = _wire();
      await openDialog(tester, wire);

      await tester.enterText(find.byKey(TrainingRaiseDialog.titleKey), 'Forklift safety');
      await pickDate(tester, TrainingRaiseDialog.trainedOnKey, DateTime(2026, 5, 4));
      await tester.enterText(find.byKey(TrainingRaiseDialog.durationKey), '2');
      await tapIn(tester, find.byKey(TrainingRaiseDialog.orgUnitKey('10')));
      await tapIn(tester, find.byKey(TrainingRaiseDialog.submitKey));

      expect(wire.trainingWrites.single, {
        'orgUnitId': '10',
        'title': 'Forklift safety',
        'trainedOn': '2026-05-04',
        'durationHours': 2,
      });
    });

    testWidgets('a server refusal is shown in the dialog, which stays open with its entries',
        (tester) async {
      final wire = _wire(
        trainingWriteStatus: 403,
        trainingWriteMessage: "Outside the caller's granted Org Units",
      );
      await openDialog(tester, wire);

      await tester.enterText(find.byKey(TrainingRaiseDialog.titleKey), 'Forklift safety');
      await pickDate(tester, TrainingRaiseDialog.trainedOnKey, DateTime(2026, 5, 4));
      await tester.enterText(find.byKey(TrainingRaiseDialog.durationKey), '2');
      await tapIn(tester, find.byKey(TrainingRaiseDialog.orgUnitKey('10')));
      await tapIn(tester, find.byKey(TrainingRaiseDialog.submitKey));

      expect(find.byKey(TrainingRaiseDialog.failureKey), findsOneWidget);
      expect(find.text("Outside the caller's granted Org Units"), findsOneWidget);
      expect(find.byType(TrainingRaiseDialog), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byKey(TrainingRaiseDialog.titleKey)).controller!.text,
        'Forklift safety',
      );
      expect(_postCount(wire), 1);
    });

    testWidgets('cancelling closes the dialog without sending anything', (tester) async {
      final wire = _wire();
      await openDialog(tester, wire);

      await tapIn(tester, find.byKey(TrainingRaiseDialog.cancelKey));

      expect(find.byType(TrainingRaiseDialog), findsNothing);
      expect(_postCount(wire), 0);
    });
  });

  group('one record', () {
    testWidgets('shows the record, its number, a draft marker and an empty Trainee list',
        (tester) async {
      final wire = _wire(trainingRecords: [
        trainingRecordJson(
          '1',
          number: 'TR-HCM-2026-00001',
          title: 'Forklift safety',
          trainedOn: '2026-05-04',
          orgUnitName: 'Assembly',
          durationHours: 1.5,
          trainerName: 'Alice Nguyen',
          objective: 'Isolate energy safely',
          status: 'draft',
        ),
      ]);
      await _open(tester, wire, '/training/1');

      expect(find.text('TR-HCM-2026-00001'), findsOneWidget);
      expect(find.text('Forklift safety'), findsOneWidget);
      expect(find.text('Draft'), findsOneWidget);
      expect(find.text('2026-05-04'), findsOneWidget);
      expect(find.text('Assembly'), findsOneWidget);
      expect(find.text('1.5 h'), findsOneWidget);
      expect(find.text('Alice Nguyen'), findsOneWidget);
      expect(find.text('Isolate energy safely'), findsOneWidget);
      expect(find.byKey(TrainingDetailScreen.noTraineesKey), findsOneWidget);
      expect(find.text('No Trainees are on this Training record yet.'), findsOneWidget);
    });

    testWidgets('a sent record is marked sent', (tester) async {
      final wire = _wire(trainingRecords: [trainingRecordJson('1', status: 'sent')]);
      await _open(tester, wire, '/training/1');

      expect(find.text('Sent'), findsOneWidget);
      expect(find.text('Draft'), findsNothing);
    });

    testWidgets('an unknown record reads as missing, not as a failure', (tester) async {
      await _open(tester, _wire(), '/training/99');

      expect(find.byKey(TrainingDetailScreen.missingKey), findsOneWidget);
      expect(find.byKey(TrainingDetailScreen.failedKey), findsNothing);
    });

    testWidgets('moving from one record to another re-reads rather than showing the first',
        (tester) async {
      final wire = _wire(trainingRecords: [
        trainingRecordJson('1', number: 'TR-HCM-2026-00001'),
        trainingRecordJson('2', number: 'TR-HCM-2026-00002'),
      ]);
      await _open(tester, wire, '/training/1');
      expect(find.text('TR-HCM-2026-00001'), findsOneWidget);

      GoRouter.of(tester.element(find.byType(TrainingDetailScreen))).go('/training/2');
      await tester.pumpAndSettle();

      expect(find.text('TR-HCM-2026-00002'), findsOneWidget);
      expect(find.text('TR-HCM-2026-00001'), findsNothing);
    });
  });
}
