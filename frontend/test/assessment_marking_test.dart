/// Marking, the award and the result (issue #588, ADR-0068, slice 4) — the wire
/// faked, the one client seam (ADR-0012, AGENTS.md §5).
///
/// What a person sees and does on `/assessments/marking`,
/// `/assessments/5/attempts/41/marking` and `/assessments/5/attempts/41/result`:
/// the queue with its count of "Khác" answers, a paper whose Other answer the
/// Marker awards a point and whose award goes out as one POST, and a result that
/// reads `7/10` with the verdict word — or says the paper is awaiting marking.
/// Every assertion is on rendered text, a `Key`, or a request the fake wire
/// recorded; nothing reads a Bloc.
library;

import 'dart:ui' show Size;

import 'package:flutter/widgets.dart' show Text;
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/people/assessment_marking_queue_screen.dart';
import 'package:lean_platform/people/assessment_marking_screen.dart';
import 'package:lean_platform/people/assessment_result_screen.dart';
import 'package:lean_platform/people/assessments_screen.dart';
import 'package:lean_platform/platform/destinations.dart';
import 'package:lean_platform/platform/router.dart';

import 'harness.dart';

const _display = 'PPL_ASSESSMENT_DISPLAY';
const _change = 'PPL_ASSESSMENT_CHANGE';
const _sit = 'PPL_ASSESSMENT_SIT';
const _mark = 'PPL_ASSESSMENT_MARK';

FakeWire _wire({List<String> permissions = const [_display, _change, _mark]}) {
  return FakeWire(
    role: Roles.supervisor,
    mePermissions: permissions,
    sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
  );
}

void _tall(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1200, 4800);
  addTearDown(tester.view.reset);
}

Future<void> _open(WidgetTester tester, FakeWire wire, String location) {
  _tall(tester);
  return pumpApp(
    tester,
    gateway: FakeAuthGateway(accessToken: 'a-token'),
    client: wire.client,
    initialLocation: location,
  );
}

void main() {
  testWidgets('the queue lists a submitted paper with its Khác count and opens it', (tester) async {
    final wire = _wire();
    wire.assessmentMarkingQueue = [
      {
        ...assessmentAttemptJson(
          41,
          assessmentId: '5',
          status: 'submitted',
          submittedAt: '2026-11-24T10:15:00.000Z',
          assessmentNumber: 'AS-HCM-2026-00005',
          assessmentTitle: 'Kiểm tra quy trình Braiding',
          processName: 'Braiding',
          questionCount: 10,
          passMark: 8,
        ),
        'employeeName': 'Sitter Person',
        'orgUnitName': 'Team A',
        'otherAnswerCount': 2,
      },
    ];
    await _open(tester, wire, Routes.assessmentMarkingQueue);
    await tester.pumpAndSettle();

    expect(find.byKey(AssessmentMarkingQueueScreen.rowKey('41')), findsOneWidget);
    expect(find.text('Sitter Person'), findsOneWidget);
    expect(find.text('2 Khác answers'), findsOneWidget);
    expect(find.textContaining('AS-HCM-2026-00005'), findsOneWidget);

    await tester.tap(find.byKey(AssessmentMarkingQueueScreen.openKey('41')));
    await tester.pumpAndSettle();
    expect(find.byKey(AssessmentMarkingScreen.rowKey(7)), findsOneWidget);
  });

  testWidgets('an empty queue says nothing is waiting', (tester) async {
    await _open(tester, _wire(), Routes.assessmentMarkingQueue);
    await tester.pumpAndSettle();

    expect(find.byKey(AssessmentMarkingQueueScreen.emptyKey), findsOneWidget);
    expect(find.text('Nothing to mark'), findsOneWidget);
  });

  testWidgets('the Marker awards the Other answer a point and the POST carries it', (tester) async {
    final wire = _wire();
    wire.assessmentMarkingPaper = assessmentMarkingPaperJson(attemptId: 41);
    await _open(tester, wire, Routes.assessmentMarking('5', '41'));
    await tester.pumpAndSettle();

    // Both numbers are at the top: the machine's 6, and the running total.
    expect(
      find.descendant(
        of: find.byKey(AssessmentMarkingScreen.machineScoreKey),
        matching: find.text('6/10'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(AssessmentMarkingScreen.finalScoreKey),
        matching: find.text('6/10'),
      ),
      findsOneWidget,
    );
    // The Other answer is on the paper, with its own note field.
    expect(find.text('E. Dừng máy rồi báo Team Leader'), findsOneWidget);
    expect(find.byKey(AssessmentMarkingScreen.answerNoteKey(7)), findsOneWidget);
    expect(find.byKey(AssessmentMarkingScreen.answerNoteKey(1)), findsNothing);

    await tester.ensureVisible(find.byKey(AssessmentMarkingScreen.oneKey(7)));
    await tester.tap(find.byKey(AssessmentMarkingScreen.oneKey(7)));
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(AssessmentMarkingScreen.finalScoreKey),
        matching: find.text('7/10'),
      ),
      findsOneWidget,
    );

    await tester.enterText(find.byKey(AssessmentMarkingScreen.answerNoteKey(7)), 'Hay hơn đáp án');
    await tester.enterText(find.byKey(AssessmentMarkingScreen.noteKey), 'Đã xem câu Khác');
    await tester.ensureVisible(find.byKey(AssessmentMarkingScreen.submitKey));
    await tester.tap(find.byKey(AssessmentMarkingScreen.submitKey));
    await tester.pumpAndSettle();

    expect(wire.assessmentMarks, hasLength(1));
    final (attemptId, body) = wire.assessmentMarks.single;
    expect(attemptId, '41');
    expect(body, {
      'answers': [
        {'position': 7, 'points': 1, 'note': 'Hay hơn đáp án'},
      ],
      'note': 'Đã xem câu Khác',
    });
  });

  testWidgets('a paper that was already marked is a refusal the Marker can read', (tester) async {
    final wire = _wire();
    wire.assessmentMarkingPaper = assessmentMarkingPaperJson(attemptId: 41);
    wire.markAssessmentStatus = 409;
    await _open(tester, wire, Routes.assessmentMarking('5', '41'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(AssessmentMarkingScreen.submitKey));
    await tester.tap(find.byKey(AssessmentMarkingScreen.submitKey));
    await tester.pumpAndSettle();

    expect(find.byKey(AssessmentMarkingScreen.noticeKey), findsOneWidget);
    expect(find.textContaining('already marked'), findsWidgets);
  });

  testWidgets('the result reads 7/10 with the localised verdict, the key and the explanation',
      (tester) async {
    final wire = _wire(permissions: const [_display, _sit]);
    await _open(tester, wire, Routes.assessmentResult('5', '41'));
    await tester.pumpAndSettle();

    expect(find.byKey(AssessmentResultScreen.scoreKey), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(AssessmentResultScreen.scoreKey)).data,
      '7/10 — not passed',
    );
    expect(find.text('not passed'), findsOneWidget); // the verdict chip
    expect(find.text('Pass mark: 8 of 10'), findsOneWidget);
    expect(find.text('Machine score 6, final score 7'), findsOneWidget);
    expect(find.text('Correct answer: C. Phương án C 1'), findsOneWidget);
    expect(find.text('Explanation: Lý do 1.'), findsOneWidget);
    expect(find.byKey(AssessmentResultScreen.awaitingKey), findsNothing);
  });

  testWidgets('before marking the result is awaiting marking, with no score and no key', (tester) async {
    final wire = _wire(permissions: const [_display, _sit]);
    wire.assessmentResultStatus = 409;
    wire.assessmentPaper = assessmentPaperJson(
      attemptId: 41,
      assessmentId: 5,
      status: 'submitted',
      answers: {1: ('C', null)},
    );
    await _open(tester, wire, Routes.assessmentResult('5', '41'));
    await tester.pumpAndSettle();

    expect(find.byKey(AssessmentResultScreen.awaitingKey), findsOneWidget);
    expect(find.text('Awaiting marking'), findsOneWidget);
    expect(find.byKey(AssessmentResultScreen.scoreKey), findsNothing);
    expect(find.byKey(AssessmentResultScreen.failedKey), findsNothing);
    expect(find.textContaining('Correct answer'), findsNothing);
    // Their own Answers, and only those.
    expect(find.byKey(AssessmentResultScreen.questionKey(1)), findsOneWidget);
  });

  testWidgets('the register shows a marked Attempt\'s score, and a dash where none was sent',
      (tester) async {
    final wire = _wire(permissions: const [_display, _sit]);
    wire.myAssessmentAttempts = [
      {
        ...assessmentAttemptJson(
          41,
          assessmentId: '5',
          status: 'marked',
          assessmentNumber: 'AS-HCM-2026-00005',
          assessmentTitle: 'Kiểm tra Braiding',
          questionCount: 10,
          passMark: 8,
        ),
        'score': 6,
        'finalScore': 7,
        'passed': false,
        'scoreHidden': false,
      },
      {
        ...assessmentAttemptJson(
          42,
          assessmentId: '6',
          status: 'marked',
          assessmentNumber: 'AS-HCM-2026-00006',
          assessmentTitle: 'Kiểm tra Cutting',
          questionCount: 10,
          passMark: 8,
        ),
      },
    ];
    await _open(tester, wire, Routes.assessments);
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(AssessmentsScreen.attemptScoreKey('41'))).data,
      '7/10 — not passed',
    );
    expect(tester.widget<Text>(find.byKey(AssessmentsScreen.attemptScoreKey('42'))).data, '—');
    expect(find.byKey(AssessmentsScreen.attemptResultKey('41')), findsOneWidget);
  });
}
