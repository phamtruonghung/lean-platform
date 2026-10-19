/// The Training record's printed form at `/training/:id/form` (issue #292,
/// parent #286) — with the wire faked, the one client seam (AGENTS.md section
/// 5). Everything asserted is rendered text, a Key, or a request the fake wire
/// recorded.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lean_platform/people/training_detail_screen.dart';
import 'package:lean_platform/people/training_form_screen.dart';
import 'package:lean_platform/people/training_screen.dart';
import 'package:lean_platform/platform/destinations.dart';
import 'package:lean_platform/platform/router.dart';
import 'package:lean_platform/platform/shell.dart';

import 'harness.dart';

FakeWire _wire(
  List<Map<String, dynamic>> records, {
  int trainingStatus = 200,
  String role = Roles.admin,
}) =>
    FakeWire(
      role: role,
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [orgUnitJson('10', 'Assembly')],
      },
      trainingRecords: records,
      trainingStatus: trainingStatus,
    );

Future<void> _open(WidgetTester tester, FakeWire wire, String location, {http.Client? client}) {
  // A tall window, as the other Training tests pin: the form scrolls, but the
  // register's own list is lazy and would leave a row below the fold unbuilt.
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  return pumpApp(
    tester,
    gateway: FakeAuthGateway(accessToken: 'a-token'),
    client: client ?? wire.client,
    initialLocation: location,
  );
}

/// A real 1 x 1 PNG, so `Image.memory` decodes it.
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

Map<String, dynamic> _record({
  String id = '1',
  String status = 'sent',
  double durationHours = 2,
  String? trainerName = 'Tina Trainer',
  String? objective = 'Everyone can isolate the press',
  List<Map<String, dynamic>>? trainees,
}) =>
    trainingRecordJson(
      id,
      number: 'TR-HCM-2026-00001',
      title: 'Lockout and tagout refresher',
      trainedOn: '2026-05-04',
      durationHours: durationHours,
      trainerEmployeeId: '9',
      trainerName: trainerName,
      objective: objective,
      status: status,
      trainees: trainees ?? [traineeJson('t1', '7', 'E-7', 'Alice Nguyen')],
    );

/// The requests that name a Training record — the app's own start-up requests
/// (`/me` and the like) are the same on every Screen and are not the question.
List<String> _trainingRequests(FakeWire wire) =>
    wire.requests.where((request) => request.contains('/api/people/training')).toList();

/// The faked wire, except that the record's own read answers 500 while
/// [failing] says so — FakeWire only scripts a 404 for it.
class _FlakyRecordClient extends http.BaseClient {
  _FlakyRecordClient(this._inner, this._failing);

  final http.Client _inner;
  final bool Function() _failing;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (_failing() && request.method == 'GET' && request.url.path.startsWith('/api/people/training/')) {
      return Future.value(http.StreamedResponse(
        Stream.value('{"message":"The record is unavailable."}'.codeUnits),
        500,
        headers: {'content-type': 'application/json'},
      ));
    }
    return _inner.send(request);
  }
}

void main() {
  group('the form', () {
    testWidgets('prints every label in both languages, the facts and the record number',
        (tester) async {
      await _open(tester, _wire([_record(durationHours: 1.5)]), Routes.trainingForm('1'));

      expect(find.byKey(TrainingFormScreen.loadedKey), findsOneWidget);
      for (final label in const [
        'Training Record',
        'Biên bản ghi nhận đào tạo',
        'Training title:',
        'Nội dung đào tạo:',
        'Date of Training:',
        'Ngày đào tạo:',
        'Training duration ( Hr):',
        'Thời gian đào tạo( giờ):',
        'Name of the trainer:',
        'Người đào tạo:',
        'Objective of the training:',
        'Mục tiêu của đào tạo:',
        'Attendance list/ danh sách tham gia :',
        'No.',
        'STT',
        'Employee Number',
        'Employee name',
        'Họ và tên nhân viên',
        'Signature',
        'Ký tên',
        'Evaluation',
        'Paper',
        'Job-training.',
        'Trainer/ Người đào tạo',
        'Date/ngày',
        'Humans Resource/ BP NS',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }

      expect(find.text('TR-HCM-2026-00001'), findsOneWidget);
      expect(find.byKey(TrainingFormScreen.numberKey), findsOneWidget);
      expect(find.text('Lockout and tagout refresher'), findsOneWidget);
      expect(find.text('2026-05-04'), findsOneWidget);
      // The label already says hours, so the value is a bare number.
      expect(find.text('1.5'), findsOneWidget);
      expect(find.text('Everyone can isolate the press'), findsOneWidget);
      // The trainer's name is the fact, and again printed under the signature
      // label at the foot.
      expect(find.text('Tina Trainer'), findsNWidgets(2));
    });

    testWidgets('a whole number of hours has no decimal point', (tester) async {
      await _open(tester, _wire([_record(durationHours: 2)]), Routes.trainingForm('1'));

      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('a record with no trainer and no objective prints them blank', (tester) async {
      await _open(
        tester,
        _wire([_record(trainerName: null, objective: null)]),
        Routes.trainingForm('1'),
      );

      expect(find.byKey(TrainingFormScreen.loadedKey), findsOneWidget);
      expect(find.text('Not recorded'), findsNothing);
      expect(find.text('null'), findsNothing);
    });

    testWidgets('rows follow the order the Trainees were added, not the alphabet', (tester) async {
      await _open(
        tester,
        _wire([
          _record(trainees: [
            traineeJson('t1', '1', 'E-1', 'Zed Zimmer'),
            traineeJson('t2', '2', 'E-2', 'Anh Nguyen'),
            traineeJson('t3', '3', 'E-3', 'Minh Tran'),
          ]),
        ]),
        Routes.trainingForm('1'),
      );

      double top(String id) => tester.getTopLeft(find.byKey(TrainingFormScreen.traineeRowKey(id))).dy;
      expect(top('t1'), lessThan(top('t2')));
      expect(top('t2'), lessThan(top('t3')));

      // The number column counts from one, in that same order.
      Finder numberIn(String id, String text) => find.descendant(
            of: find.byKey(TrainingFormScreen.traineeRowKey(id)),
            matching: find.text(text),
          );
      expect(numberIn('t1', '1'), findsOneWidget);
      expect(numberIn('t2', '2'), findsOneWidget);
      expect(numberIn('t3', '3'), findsOneWidget);
      expect(numberIn('t1', 'E-1'), findsOneWidget);
      expect(numberIn('t1', 'Zed Zimmer'), findsOneWidget);
    });

    testWidgets('more than five Trainees print one row each, and no blank rows are added',
        (tester) async {
      await _open(
        tester,
        _wire([
          _record(trainees: [
            for (var i = 1; i <= 7; i++) traineeJson('t$i', '$i', 'E-$i', 'Trainee $i'),
          ]),
        ]),
        Routes.trainingForm('1'),
      );

      for (var i = 1; i <= 7; i++) {
        expect(find.byKey(TrainingFormScreen.traineeRowKey('t$i')), findsOneWidget);
      }
      expect(find.byKey(TrainingFormScreen.traineeRowKey('t8')), findsNothing);
    });

    testWidgets('a Trainee who has not answered has an empty Signature cell; a confirmed one shows '
        'the day', (tester) async {
      await _open(
        tester,
        _wire([
          _record(trainees: [
            traineeJson('t1', '1', 'E-1', 'Alice Nguyen', answer: 'confirmed', answeredAt: '2026-05-06T09:30:00.000Z'),
            traineeJson('t2', '2', 'E-2', 'Bao Tran'),
          ]),
        ]),
        Routes.trainingForm('1'),
      );

      final confirmed = find.byKey(TrainingFormScreen.signatureCellKey('t1'));
      final pending = find.byKey(TrainingFormScreen.signatureCellKey('t2'));
      expect(find.descendant(of: confirmed, matching: find.text('2026-05-06')), findsOneWidget);
      expect(find.descendant(of: pending, matching: find.byType(Text)), findsNothing);
    });

    testWidgets('an applied Signature prints as its image with the day beneath it, in both languages',
        (tester) async {
      final wire = _wire([
        _record(trainees: [
          traineeJson('t1', '1', 'E-1', 'Alice Nguyen',
              answer: 'confirmed', answeredAt: '2026-05-06T09:30:00.000Z', signatureAppliedAs: 'stored'),
          traineeJson('t2', '2', 'E-2', 'Bao Tran',
              answer: 'confirmed', answeredAt: '2026-05-06T09:30:00.000Z', signatureAppliedAs: 'drawn'),
          traineeJson('t3', '3', 'E-3', 'Chi Le'),
        ]),
      ])
        ..traineeSignatures['t1'] = _png
        ..traineeSignatures['t2'] = _png;
      await _open(tester, wire, Routes.trainingForm('1'));
      await tester.pumpAndSettle();

      for (final id in ['t1', 't2']) {
        final cell = find.byKey(TrainingFormScreen.signatureCellKey(id));
        expect(find.descendant(of: cell, matching: find.byKey(TrainingFormScreen.signatureImageKey(id))),
            findsOneWidget);
        expect(find.descendant(of: cell, matching: find.byType(Image)), findsOneWidget);
        expect(find.descendant(of: cell, matching: find.text('2026-05-06')), findsOneWidget);
      }
      expect(wire.traineeSignatureReads, [
        'GET /api/people/training/trainees/t1/signature',
        'GET /api/people/training/trainees/t2/signature',
      ]);
      // The empty cell asks for nothing, and the column heads stay bilingual.
      expect(find.byKey(TrainingFormScreen.signatureImageKey('t3')), findsNothing);
      expect(find.text('Signature'), findsOneWidget);
      expect(find.text('Ký tên'), findsOneWidget);
    });

    testWidgets('a decline never prints an image, even if the row holds one', (tester) async {
      final wire = _wire([
        _record(trainees: [
          traineeJson('t1', '1', 'E-1', 'Alice Nguyen',
              answer: 'declined', answeredAt: '2026-05-07T09:30:00.000Z', answeredOn: '2026-05-07', signatureAppliedAs: 'stored'),
        ]),
      ])
        ..traineeSignatures['t1'] = _png;
      await _open(tester, wire, Routes.trainingForm('1'));
      await tester.pumpAndSettle();

      final cell = find.byKey(TrainingFormScreen.signatureCellKey('t1'));
      expect(find.descendant(of: cell, matching: find.byType(Image)), findsNothing);
      expect(find.descendant(of: cell, matching: find.text('Declined 2026-05-07')), findsOneWidget);
      expect(wire.traineeSignatureReads, isEmpty);
    });

    testWidgets('a cell whose image fails to fetch still prints its date and shows no error',
        (tester) async {
      final wire = _wire([
        _record(trainees: [
          traineeJson('t1', '1', 'E-1', 'Alice Nguyen',
              answer: 'confirmed', answeredAt: '2026-05-06T09:30:00.000Z', signatureAppliedAs: 'stored'),
        ]),
      ])
        ..traineeSignatureStatus = 500;
      await _open(tester, wire, Routes.trainingForm('1'));
      await tester.pumpAndSettle();

      final cell = find.byKey(TrainingFormScreen.signatureCellKey('t1'));
      expect(wire.traineeSignatureReads, ['GET /api/people/training/trainees/t1/signature']);
      expect(find.descendant(of: cell, matching: find.byType(Image)), findsNothing);
      expect(find.descendant(of: cell, matching: find.text('2026-05-06')), findsOneWidget);
      expect(find.byKey(TrainingFormScreen.failedKey), findsNothing);
      expect(find.byKey(TrainingFormScreen.loadedKey), findsOneWidget);
    });

    testWidgets('the cell prints the Site\'s local day the server resolved, not the UTC day', (tester) async {
      final wire = _wire([
        _record(trainees: [
          traineeJson('t1', '1', 'E-1', 'Alice Nguyen',
              answer: 'confirmed',
              answeredAt: '2026-05-06T18:00:00.000Z',
              answeredOn: '2026-05-07',
              signatureAppliedAs: 'stored'),
          traineeJson('t2', '2', 'E-2', 'Bao Tran',
              answer: 'declined', answeredAt: '2026-05-06T18:00:00.000Z', answeredOn: '2026-05-07'),
        ]),
      ])
        ..traineeSignatures['t1'] = _png;
      await _open(tester, wire, Routes.trainingForm('1'));
      await tester.pumpAndSettle();

      final image = find.byKey(TrainingFormScreen.signatureCellKey('t1'));
      expect(find.descendant(of: image, matching: find.text('2026-05-07')), findsOneWidget);
      expect(find.descendant(of: image, matching: find.text('2026-05-06')), findsNothing);
      final declined = find.byKey(TrainingFormScreen.signatureCellKey('t2'));
      expect(find.descendant(of: declined, matching: find.text('Declined 2026-05-07')), findsOneWidget);
    });

    testWidgets('a decline reads as a decline, never as a signature', (tester) async {
      await _open(
        tester,
        _wire([
          _record(trainees: [
            traineeJson('t1', '1', 'E-1', 'Alice Nguyen', answer: 'declined', answeredAt: '2026-05-07T09:30:00.000Z', answeredOn: '2026-05-07'),
          ]),
        ]),
        Routes.trainingForm('1'),
      );

      expect(
        find.descendant(
          of: find.byKey(TrainingFormScreen.signatureCellKey('t1')),
          matching: find.text('Declined 2026-05-07'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('an X marks the Evaluation the trainer recorded, and only that one', (tester) async {
      await _open(
        tester,
        _wire([
          _record(trainees: [
            traineeJson('t1', '1', 'E-1', 'Alice Nguyen', evaluation: 'paper'),
            traineeJson('t2', '2', 'E-2', 'Bao Tran', evaluation: 'job_training'),
            traineeJson('t3', '3', 'E-3', 'Cam Le'),
          ]),
        ]),
        Routes.trainingForm('1'),
      );

      Finder x(Key cell) => find.descendant(of: find.byKey(cell), matching: find.text('X'));
      expect(x(TrainingFormScreen.paperMarkKey('t1')), findsOneWidget);
      expect(x(TrainingFormScreen.jobTrainingMarkKey('t1')), findsNothing);
      expect(x(TrainingFormScreen.paperMarkKey('t2')), findsNothing);
      expect(x(TrainingFormScreen.jobTrainingMarkKey('t2')), findsOneWidget);
      expect(x(TrainingFormScreen.paperMarkKey('t3')), findsNothing);
      expect(x(TrainingFormScreen.jobTrainingMarkKey('t3')), findsNothing);
      expect(find.text('X'), findsNWidgets(2));
    });

    testWidgets('a draft prints in full, with every Signature cell empty', (tester) async {
      // A draft has never been sent, so no Trainee has answered.
      await _open(
        tester,
        _wire([
          _record(status: 'draft', trainees: [
            traineeJson('t1', '1', 'E-1', 'Alice Nguyen'),
            traineeJson('t2', '2', 'E-2', 'Bao Tran'),
          ]),
        ]),
        Routes.trainingForm('1'),
      );

      expect(find.byKey(TrainingFormScreen.loadedKey), findsOneWidget);
      for (final id in const ['t1', 't2']) {
        expect(find.byKey(TrainingFormScreen.traineeRowKey(id)), findsOneWidget);
        expect(
          find.descendant(of: find.byKey(TrainingFormScreen.signatureCellKey(id)), matching: find.byType(Text)),
          findsNothing,
        );
      }
    });

    testWidgets('a sent, partly answered record prints in full', (tester) async {
      await _open(
        tester,
        _wire([
          _record(trainees: [
            traineeJson('t1', '1', 'E-1', 'Alice Nguyen', answer: 'confirmed', answeredAt: '2026-05-06T09:30:00.000Z'),
            traineeJson('t2', '2', 'E-2', 'Bao Tran', answer: 'declined', answeredAt: '2026-05-07T09:30:00.000Z', answeredOn: '2026-05-07'),
            traineeJson('t3', '3', 'E-3', 'Cam Le'),
          ]),
        ]),
        Routes.trainingForm('1'),
      );

      expect(find.byKey(TrainingFormScreen.loadedKey), findsOneWidget);
      for (final id in const ['t1', 't2', 't3']) {
        expect(find.byKey(TrainingFormScreen.traineeRowKey(id)), findsOneWidget);
      }
      Finder cell(String id) => find.byKey(TrainingFormScreen.signatureCellKey(id));
      expect(find.descendant(of: cell('t1'), matching: find.text('2026-05-06')), findsOneWidget);
      expect(find.descendant(of: cell('t2'), matching: find.text('Declined 2026-05-07')), findsOneWidget);
      expect(find.descendant(of: cell('t3'), matching: find.byType(Text)), findsNothing);
    });

    testWidgets('the Human Resources cell is blank and no Account name is printed', (tester) async {
      await _open(tester, _wire([_record()]), Routes.trainingForm('1'));

      expect(find.byKey(TrainingFormScreen.hrSignatureKey), findsOneWidget);
      expect(
        find.descendant(of: find.byKey(TrainingFormScreen.hrSignatureKey), matching: find.byType(Text)),
        findsNothing,
      );
      // The harness signs in as the Account named "A B"; the form never prints
      // who is looking at it.
      expect(find.text('A B'), findsNothing);
      expect(find.textContaining('admin@'), findsNothing);
    });

    testWidgets('it renders outside the Shell, with no control on it', (tester) async {
      await _open(tester, _wire([_record()]), Routes.trainingForm('1'));

      expect(find.byKey(TrainingFormScreen.loadedKey), findsOneWidget);
      expect(find.byKey(PlatformShell.sidebarKey), findsNothing);
      expect(find.byType(TextButton), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
      expect(find.byType(IconButton), findsNothing);
    });

    testWidgets('a 404 reads as a missing record, worded as the record\'s own Screen words it',
        (tester) async {
      await _open(tester, _wire([_record()]), Routes.trainingForm('9'));

      expect(find.byKey(TrainingFormScreen.missingKey), findsOneWidget);
      expect(find.text('No such Training record'), findsOneWidget);
      expect(find.byKey(TrainingFormScreen.failedKey), findsNothing);
      expect(find.byKey(TrainingFormScreen.loadedKey), findsNothing);
    });

    testWidgets('any other failed read shows the failure state and retrying reads again',
        (tester) async {
      final wire = _wire([_record()]);
      var failing = true;
      await _open(
        tester,
        wire,
        Routes.trainingForm('1'),
        client: _FlakyRecordClient(wire.client, () => failing),
      );

      expect(find.byKey(TrainingFormScreen.failedKey), findsOneWidget);
      expect(find.byKey(TrainingFormScreen.missingKey), findsNothing);

      failing = false;
      await tapIn(tester, find.byKey(TrainingFormScreen.retryKey));
      expect(find.byKey(TrainingFormScreen.loadedKey), findsOneWidget);
    });
  });

  group('what it asks of the server', () {
    testWidgets('opening the form issues only the read the record\'s own Screen makes',
        (tester) async {
      final wire = _wire([_record()]);
      await _open(tester, wire, Routes.trainingForm('1'));

      expect(_trainingRequests(wire), ['GET /api/people/training/1']);
    });

    testWidgets('the record\'s own Screen makes that same one read', (tester) async {
      final wire = _wire([_record()]);
      await _open(tester, wire, '${Routes.training}/1');

      expect(_trainingRequests(wire), ['GET /api/people/training/1']);
    });
  });

  group('reaching it', () {
    Future<void> reachFromRecordScreen(WidgetTester tester, String role) async {
      final wire = _wire([_record()], role: role);
      await _open(tester, wire, '${Routes.training}/1');
      expect(find.byKey(TrainingFormScreen.loadedKey), findsNothing);
      final before = wire.requests.length;

      await tapIn(tester, find.byKey(TrainingDetailScreen.formKey));

      expect(find.byKey(TrainingFormScreen.loadedKey), findsOneWidget);
      expect(find.byKey(PlatformShell.sidebarKey), findsNothing);
      expect(wire.requests.sublist(before), ['GET /api/people/training/1']);
    }

    testWidgets('from the record\'s own Screen, as an administrator', (tester) async {
      await reachFromRecordScreen(tester, Roles.admin);
    });

    // Operator is the lowest role and is admitted: the Training destination is
    // offered to every approved Account (destinations.dart), with no redirect of
    // its own. A separate test, as two pumpApp calls would share one AccountBloc.
    testWidgets('from the record\'s own Screen, as an operator with no elevated role',
        (tester) async {
      await reachFromRecordScreen(tester, Roles.operator);
    });

    testWidgets('from a register row, asking the server for nothing but the record', (tester) async {
      final wire = _wire([_record()]);
      await _open(tester, wire, Routes.training);
      expect(find.byKey(TrainingScreen.formKey('1')), findsOneWidget);
      final before = wire.requests.length;

      await tapIn(tester, find.byKey(TrainingScreen.formKey('1')));

      expect(find.byKey(TrainingFormScreen.loadedKey), findsOneWidget);
      expect(find.byKey(PlatformShell.sidebarKey), findsNothing);
      expect(wire.requests.sublist(before), ['GET /api/people/training/1']);
    });
  });
}
