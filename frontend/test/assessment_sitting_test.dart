/// The sitting (issue #588, ADR-0068, slice 3) — the wire faked, the one client
/// seam (ADR-0012, AGENTS.md §5).
///
/// What a person sees and does on
/// `/assessments/5/attempts/41/sit`: one Question at a time, the countdown the
/// server's own instants produce, an Answer saved the moment it is made, the
/// Other row's own field, and a Submit that names how many Questions are still
/// unanswered before it sends anything.
library;

import 'dart:ui' show Size;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/people/assessment_sitting_screen.dart';
import 'package:lean_platform/platform/destinations.dart';
import 'package:lean_platform/platform/router.dart';
import 'package:lean_platform/widgets/app_confirm_dialog.dart';

import 'harness.dart';

const _display = 'PPL_ASSESSMENT_DISPLAY';
const _sit = 'PPL_ASSESSMENT_SIT';

FakeWire _wire({int questions = 10, Map<int, (String?, String?)> answers = const {}}) {
  final wire = FakeWire(
    role: Roles.operator,
    mePermissions: const [_display, _sit],
    sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
  );
  wire.assessmentPaper = assessmentPaperJson(
    attemptId: 41,
    assessmentId: 5,
    questions: questions,
    answers: answers,
  );
  return wire;
}

String _sitting() => Routes.assessmentSitting('5', '41');

void _tall(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1200, 2400);
  addTearDown(tester.view.reset);
}

Future<void> _open(WidgetTester tester, FakeWire wire) {
  _tall(tester);
  return pumpApp(
    tester,
    gateway: FakeAuthGateway(accessToken: 'a-token'),
    client: wire.client,
    initialLocation: _sitting(),
  );
}

void main() {
  testWidgets('one Question at a time, with the countdown the server instants produce', (tester) async {
    await _open(tester, _wire());
    await tester.pumpAndSettle();

    expect(find.byKey(AssessmentSittingScreen.questionKey), findsOneWidget);
    expect(find.text('Câu số 1 của quy trình này là gì?'), findsOneWidget);
    expect(find.text('Phương án C 1'), findsOneWidget);
    // serverNow 10:00, deadline 10:20 → twenty minutes left. A second of the
    // test's own pumping may already have elapsed, so the assertion is that the
    // clock is counting down from twenty minutes, not that it is frozen.
    final countdown = tester.widget<Text>(find.byKey(AssessmentSittingScreen.countdownKey)).data!;
    expect(countdown, matches(RegExp(r'^(19|20):\d{2}$')));
    expect(find.text('Question 1 of 10'), findsOneWidget);
    // The second Question is not on screen.
    expect(find.text('Câu số 2 của quy trình này là gì?'), findsNothing);
  });

  testWidgets('tapping an Option saves that Answer for that position', (tester) async {
    final wire = _wire();
    await _open(tester, wire);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(AssessmentSittingScreen.optionKey('C')));
    await tester.pumpAndSettle();

    expect(wire.assessmentAnswers, hasLength(1));
    final (attemptId, position, body) = wire.assessmentAnswers.single;
    expect(attemptId, '41');
    expect(position, 1);
    expect(body['chosenOption'], 'C');
    expect(find.byKey(AssessmentSittingScreen.savedTickKey), findsOneWidget);
  });

  testWidgets('Next and Previous move through the paper, and a jump chip goes straight there', (tester) async {
    final wire = _wire();
    await _open(tester, wire);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(AssessmentSittingScreen.nextKey));
    await tester.pumpAndSettle();
    expect(find.text('Câu số 2 của quy trình này là gì?'), findsOneWidget);
    expect(find.text('Question 2 of 10'), findsOneWidget);

    await tester.tap(find.byKey(AssessmentSittingScreen.previousKey));
    await tester.pumpAndSettle();
    expect(find.text('Question 1 of 10'), findsOneWidget);

    await tester.tap(find.byKey(AssessmentSittingScreen.jumpKey(7)));
    await tester.pumpAndSettle();
    expect(find.text('Question 7 of 10'), findsOneWidget);
  });

  testWidgets('the Other row is its own field, saved after the typist stops', (tester) async {
    final wire = _wire();
    await _open(tester, wire);
    await tester.pumpAndSettle();

    expect(find.text('Khác: ghi câu trả lời của bạn'), findsOneWidget);
    await tester.enterText(find.byKey(AssessmentSittingScreen.otherFieldKey), 'Dừng máy rồi báo Team Leader');
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();

    expect(wire.assessmentAnswers, hasLength(1));
    final (_, position, body) = wire.assessmentAnswers.single;
    expect(position, 1);
    expect(body['otherText'], 'Dừng máy rồi báo Team Leader');
    expect(body.containsKey('chosenOption'), isFalse, reason: 'an Other answer is never also an Option');
  });

  testWidgets('Submit names the unanswered count and sends nothing until it is confirmed', (tester) async {
    final wire = _wire(answers: {1: ('A', null), 2: ('B', null), 3: (null, 'Khác')});
    await _open(tester, wire);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(AssessmentSittingScreen.submitKey));
    await tester.pumpAndSettle();

    expect(find.byKey(AppConfirmDialog.confirmKey), findsOneWidget);
    expect(find.textContaining('7 Questions are still unanswered'), findsOneWidget);
    expect(wire.assessmentSubmits, isEmpty);

    await tester.tap(find.byKey(AppConfirmDialog.dismissKey));
    await tester.pumpAndSettle();
    expect(wire.assessmentSubmits, isEmpty);

    await tester.tap(find.byKey(AssessmentSittingScreen.submitKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppConfirmDialog.confirmKey));
    await tester.pumpAndSettle();

    expect(wire.assessmentSubmits, ['41']);
    expect(find.byKey(AssessmentSittingScreen.submittedKey), findsOneWidget);
    expect(find.text('Submitted'), findsOneWidget);
  });

  testWidgets('a paper the server has already finalised reads as submitted, with no editable Answer',
      (tester) async {
    final wire = _wire();
    wire.assessmentPaper = assessmentPaperJson(
      attemptId: 41,
      assessmentId: 5,
      status: 'submitted',
    );
    await _open(tester, wire);
    await tester.pumpAndSettle();

    expect(find.byKey(AssessmentSittingScreen.submittedKey), findsOneWidget);
    expect(find.byKey(AssessmentSittingScreen.questionKey), findsNothing);
  });
}
