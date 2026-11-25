/// An Employee with no Account sitting an Assessment at the shared floor device
/// (issue #588, ADR-0068, slice 5), driven the way a person drives it: at the
/// floor surface's own address, with the wire faked beneath. Asserts on what
/// renders and on what the fake wire recorded; never on a Bloc's state.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/maintenance/floor_screen.dart';
import 'package:lean_platform/people/floor_assessment_dialog.dart';
import 'package:lean_platform/widgets/app_confirm_dialog.dart';

import 'harness.dart';

FakeWire _wire({Map<int, (String?, String?)> answers = const {}}) => FakeWire(floorWorkOrders: const [])
  ..floorAssessmentsMine = [
    assessmentAttemptJson(
      41,
      assessmentId: '5',
      status: 'assigned',
      assessmentNumber: 'AS-HCM-2026-00001',
      assessmentTitle: 'Kiểm tra quy trình Braiding',
      processName: 'Braiding',
      questionCount: 10,
      passMark: 8,
    ),
  ]
  ..floorAssessmentPaper = assessmentPaperJson(attemptId: 41, assessmentId: 5, answers: answers);

void _tablet(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1280, 1000);
  addTearDown(tester.view.reset);
}

Future<void> _identify(WidgetTester tester) async {
  await tester.enterText(find.byKey(FloorAssessmentDialog.employeeNoKey), 'EMP-20');
  await tester.enterText(find.byKey(FloorAssessmentDialog.pinKey), '4321');
  await tester.pumpAndSettle();
  await tapIn(tester, find.byKey(FloorAssessmentDialog.submitKey));
}

/// Opens the dialog from the floor Screen, identifies and starts the Attempt.
Future<void> _sit(WidgetTester tester, FakeWire wire) async {
  _tablet(tester);
  await pumpApp(tester, gateway: FakeAuthGateway(), client: wire.client, initialLocation: '/floor');
  await tapIn(tester, find.byKey(FloorScreen.assessmentKey));
  await _identify(tester);
  await tapIn(tester, find.byKey(FloorAssessmentDialog.startKey('41')));
}

String _clockOf(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(FloorAssessmentDialog.countdownKey)).data!;

void main() {
  testWidgets('after identifying, the open Attempts the device reaches are listed with Start', (tester) async {
    final wire = _wire();
    _tablet(tester);
    await pumpApp(tester, gateway: FakeAuthGateway(), client: wire.client, initialLocation: '/floor');
    await tapIn(tester, find.byKey(FloorScreen.assessmentKey));
    await _identify(tester);

    expect(wire.floorIdentifications.single['employeeNo'], 'EMP-20');
    final read = wire.floorAssessmentRequests.single;
    expect(read['request'], 'GET /api/maintenance/floor/assessments/mine');
    expect(read['device'], 'device-credential');
    expect(read['identification'], 'identification-1');
    expect(read['sitting'], isNull);

    expect(find.byKey(FloorAssessmentDialog.listKey), findsOneWidget);
    expect(find.textContaining('Kiểm tra quy trình Braiding'), findsOneWidget);
    expect(find.text('Not started'), findsOneWidget);
    expect(find.byKey(FloorAssessmentDialog.startKey('41')), findsOneWidget);
  });

  testWidgets('starting shows one Question with the candidate and the countdown pinned in the header',
      (tester) async {
    final wire = _wire();
    await _sit(tester, wire);

    final start = wire.floorAssessmentRequests.last;
    expect(start['request'], 'POST /api/maintenance/floor/assessments/41/start');
    expect(start['identification'], 'identification-1', reason: 'start runs on the 120-second identification');
    expect(start['sitting'], isNull);

    expect(find.byKey(FloorAssessmentDialog.candidateKey), findsOneWidget);
    expect(find.text('Tess Technician'), findsOneWidget);
    expect(_clockOf(tester), matches(RegExp(r'^(19:5\d|20:00)$')));
    expect(find.text('Question 1 of 10'), findsOneWidget);
    expect(find.text('Câu số 1 của quy trình này là gì?'), findsOneWidget);
    expect(find.text('Câu số 2 của quy trình này là gì?'), findsNothing, reason: 'one Question per screen');
  });

  testWidgets('the navigator has a chip per Question, and Next, Previous and a chip move through the paper',
      (tester) async {
    final wire = _wire(answers: {1: ('A', null), 2: (null, 'Khác')});
    await _sit(tester, wire);

    for (var position = 1; position <= 10; position += 1) {
      expect(find.byKey(FloorAssessmentDialog.jumpKey(position)), findsOneWidget);
    }
    expect(find.byTooltip('Question 1: Answered'), findsOneWidget);
    expect(find.byTooltip('Question 2: Khác'), findsOneWidget);
    expect(find.byTooltip('Question 3: Blank'), findsOneWidget);

    await tapIn(tester, find.byKey(FloorAssessmentDialog.nextKey));
    expect(find.text('Question 2 of 10'), findsOneWidget);
    expect(find.text('Câu số 2 của quy trình này là gì?'), findsOneWidget);

    await tapIn(tester, find.byKey(FloorAssessmentDialog.previousKey));
    expect(find.text('Question 1 of 10'), findsOneWidget);

    await tapIn(tester, find.byKey(FloorAssessmentDialog.jumpKey(7)));
    expect(find.text('Question 7 of 10'), findsOneWidget);
    // Jumping to a Question that is already answered works too.
    await tapIn(tester, find.byKey(FloorAssessmentDialog.jumpKey(1)));
    expect(find.text('Question 1 of 10'), findsOneWidget);
  });

  testWidgets('an answer is autosaved under the sitting token, not the identification', (tester) async {
    final wire = _wire();
    await _sit(tester, wire);

    await tapIn(tester, find.byKey(FloorAssessmentDialog.optionKey('C')));

    final save = wire.floorAssessmentRequests.last;
    expect(save['request'], 'PATCH /api/maintenance/floor/assessments/41/answers/1');
    expect(save['device'], 'device-credential');
    expect(save['sitting'], 'sitting-1');
    expect(save['identification'], isNull, reason: 'the 120-second identification is not sent on a sitting route');
    expect(save['body'], {'chosenOption': 'C'});
    expect(find.byKey(FloorAssessmentDialog.savedTickKey), findsOneWidget);
    expect(find.byTooltip('Question 1: Answered'), findsOneWidget);
  });

  testWidgets('an autosave re-anchors the countdown to the instant its payload came from', (tester) async {
    final wire = _wire();
    await _sit(tester, wire);
    expect(_clockOf(tester), matches(RegExp(r'^(19:5\d|20:00)$')));

    // Real seconds on purpose: the dialog counts with the monotonic Stopwatch,
    // which a fake clock does not move, and the defect pinned here is an age
    // subtracted twice.
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 4)));
    await tester.tap(find.byKey(FloorAssessmentDialog.optionKey('A')));
    await tester.pumpAndSettle();

    // The payload is produced thirty seconds later against the same deadline.
    expect(_clockOf(tester), matches(RegExp(r'^(19:30|19:29)$')));
  });

  testWidgets('clearing the Other field saves a blank Answer without otherText', (tester) async {
    final wire = _wire();
    await _sit(tester, wire);

    await tester.enterText(find.byKey(FloorAssessmentDialog.otherFieldKey), 'Dừng máy rồi báo Team Leader');
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    expect(wire.floorAssessmentRequests.last['body'], {'otherText': 'Dừng máy rồi báo Team Leader'});

    await tester.enterText(find.byKey(FloorAssessmentDialog.otherFieldKey), '');
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    final blank = wire.floorAssessmentRequests.last['body'] as Map<String, dynamic>;
    expect(blank.containsKey('otherText'), isFalse);
    expect(blank.containsKey('chosenOption'), isFalse);
  });

  testWidgets('Submit names the blank Questions by number, then sends under the sitting token', (tester) async {
    final wire = _wire(answers: {
      for (var position = 1; position <= 10; position += 1)
        if (position != 4 && position != 9) position: ('C', null),
    });
    await _sit(tester, wire);

    await tapIn(tester, find.byKey(FloorAssessmentDialog.submitPaperKey));
    expect(find.byKey(AppConfirmDialog.confirmKey), findsOneWidget);
    expect(find.textContaining('Questions 4, 9 are blank'), findsOneWidget);
    expect(wire.floorAssessmentRequests.where((r) => (r['request'] as String).contains('/submit')), isEmpty);

    await tapIn(tester, find.byKey(AppConfirmDialog.confirmKey));

    final submit = wire.floorAssessmentRequests.firstWhere((r) => (r['request'] as String).contains('/submit'));
    expect(submit['request'], 'POST /api/maintenance/floor/assessments/41/submit');
    expect(submit['sitting'], 'sitting-1');
    expect(submit['identification'], isNull);
    // Not marked yet: the paper awaits marking and no score is shown.
    expect(find.byKey(FloorAssessmentDialog.submittedKey), findsOneWidget);
    expect(find.text('Awaiting marking'), findsOneWidget);
    expect(find.byKey(FloorAssessmentDialog.resultKey), findsNothing);
  });

  testWidgets('once a Marker has marked it, the result is the score and the verdict', (tester) async {
    final wire = _wire(answers: {for (var position = 1; position <= 10; position += 1) position: ('C', null)});
    await _sit(tester, wire);
    await tapIn(tester, find.byKey(FloorAssessmentDialog.submitPaperKey));
    await tapIn(tester, find.byKey(AppConfirmDialog.confirmKey));
    expect(find.byKey(FloorAssessmentDialog.resultKey), findsNothing);

    wire.floorAssessmentResult = assessmentResultJson(attemptId: 41);
    await tapIn(tester, find.byKey(FloorAssessmentDialog.checkResultKey));

    expect(find.byKey(FloorAssessmentDialog.resultKey), findsOneWidget);
    expect(find.text('7/10 — not passed'), findsOneWidget);
    expect(wire.floorAssessmentRequests.last['request'], 'GET /api/maintenance/floor/assessments/41/result');
    expect(wire.floorAssessmentRequests.last['sitting'], 'sitting-1');
  });

  testWidgets('a 401 on a sitting route returns to number and PIN, and re-identifying resumes the same paper',
      (tester) async {
    final wire = _wire();
    await _sit(tester, wire);
    await tapIn(tester, find.byKey(FloorAssessmentDialog.optionKey('B')));

    // A Team Leader ended the sitting: the next answer is refused.
    wire.floorSittingStatus = 401;
    await tapIn(tester, find.byKey(FloorAssessmentDialog.optionKey('C')));

    expect(find.byKey(FloorAssessmentDialog.employeeNoKey), findsOneWidget);
    expect(find.byKey(FloorAssessmentDialog.pinKey), findsOneWidget);
    expect(find.byKey(FloorAssessmentDialog.questionKey), findsNothing);
    expect(find.byKey(FloorAssessmentDialog.failureKey), findsOneWidget);
    expect(find.textContaining('This sitting has ended'), findsOneWidget);

    // Identify again: same paper, a new token.
    wire
      ..floorSittingStatus = 200
      ..floorSittingToken = 'sitting-2'
      ..floorIdentificationToken = 'identification-2';
    await _identify(tester);
    expect(wire.floorIdentifications, hasLength(2));
    await tapIn(tester, find.byKey(FloorAssessmentDialog.startKey('41')));
    final restart = wire.floorAssessmentRequests.last;
    expect(restart['request'], 'POST /api/maintenance/floor/assessments/41/start');
    expect(restart['identification'], 'identification-2');
    expect(find.text('Question 1 of 10'), findsOneWidget);
    expect(_clockOf(tester), matches(RegExp(r'^(19:\d{2}|20:00)$')), reason: 'the countdown is running, not latched at 00:00');

    await tapIn(tester, find.byKey(FloorAssessmentDialog.optionKey('A')));
    expect(wire.floorAssessmentRequests.last['sitting'], 'sitting-2');
  });
}
