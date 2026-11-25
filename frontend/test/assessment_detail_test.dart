/// One Assessment's detail (issue #588, ADR-0068, slice 6) — the wire faked, the
/// one client seam (ADR-0012, AGENTS.md §5).
///
/// What a person sees at `/assessments/:id`: the facts and counts, each
/// Employee's Attempts with the one that counts first, and the actions the
/// server would let them take — each one off, with its reason printed, where it
/// would refuse. Every assertion is on rendered text, a `Key`, a button's enabled
/// state or a request the fake wire recorded; nothing reads a Bloc.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/people/assessment_assign_dialog.dart';
import 'package:lean_platform/people/assessment_detail_screen.dart';
import 'package:lean_platform/people/assessment_marking_screen.dart';
import 'package:lean_platform/people/assessment_reason_dialog.dart';
import 'package:lean_platform/platform/destinations.dart';
import 'package:lean_platform/platform/router.dart';
import 'package:lean_platform/widgets/app_confirm_dialog.dart';

import 'harness.dart';

const _display = 'PPL_ASSESSMENT_DISPLAY';
const _change = 'PPL_ASSESSMENT_CHANGE';
const _mark = 'PPL_ASSESSMENT_MARK';

FakeWire _wire({
  List<String> permissions = const [_display, _change, _mark],
  required Map<String, dynamic> assessment,
}) {
  final wire = FakeWire(
    role: Roles.supervisor,
    mePermissions: permissions,
    sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
    orgUnitSearchResults: [orgUnitJson('11', 'Braiding')],
  );
  wire.assessmentRegister = [assessment];
  wire.assignPreviewCount = 3;
  return wire;
}

Future<void> _open(WidgetTester tester, FakeWire wire) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1200, 3200);
  addTearDown(tester.view.reset);
  await pumpApp(
    tester,
    gateway: FakeAuthGateway(accessToken: 'a-token'),
    client: wire.client,
    initialLocation: Routes.assessment('5'),
  );
  await tester.pumpAndSettle();
}

bool _enabled(WidgetTester tester, Key key) {
  final button = tester.widget<ButtonStyleButton>(find.byKey(key));
  return button.onPressed != null;
}

Future<void> _giveReason(WidgetTester tester, String reason) async {
  await tester.enterText(find.byKey(AssessmentReasonDialog.fieldKey), reason);
  await tester.pump();
  await tester.tap(find.byKey(AssessmentReasonDialog.submitKey));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the facts, the counts and the status are read from the server', (tester) async {
    final wire = _wire(
      assessment: assessmentJson(
        5,
        title: 'Kiểm tra Braiding',
        number: 'AS-HCM-2026-00005',
        questionCount: 15,
        minutes: 30,
        passMark: 12,
        attemptsAllowed: 2,
        dueOn: '2026-12-01',
        assignedCount: 4,
        runningCount: 1,
        awaitingMarkingCount: 2,
        markedCount: 3,
      ),
    );
    await _open(tester, wire);

    expect(find.text('Kiểm tra Braiding'), findsWidgets);
    expect(find.textContaining('AS-HCM-2026-00005'), findsWidgets);
    final facts = find.byKey(AssessmentDetailScreen.factsKey);
    expect(find.descendant(of: facts, matching: find.text('Braiding')), findsOneWidget);
    expect(find.descendant(of: facts, matching: find.text('15 Questions')), findsOneWidget);
    expect(find.descendant(of: facts, matching: find.text('30 minutes')), findsOneWidget);
    expect(find.descendant(of: facts, matching: find.text('12')), findsOneWidget);
    expect(find.descendant(of: facts, matching: find.text('2026-12-01')), findsOneWidget);
    expect(find.descendant(of: facts, matching: find.text('Assigned')), findsOneWidget);
    expect(find.textContaining('4 not started'), findsOneWidget);
    expect(find.textContaining('3 marked'), findsOneWidget);
  });

  group('Attempts per Employee', () {
    testWidgets('the counting score leads, and earlier sittings follow labelled by number',
        (tester) async {
      final wire = _wire(
        assessment: assessmentJson(
          5,
          attemptsAllowed: 3,
          attempts: [
            // An's first sitting is the one that counts; the second has not been marked.
            assessmentAttemptJson(41,
                assessmentId: '5',
                attemptNo: 1,
                status: 'marked',
                finalScore: 9,
                passed: true,
                scoreHidden: false,
                isCounting: true,
                isLatest: false,
                markedByName: 'Marker Person'),
            assessmentAttemptJson(42,
                assessmentId: '5', attemptNo: 2, status: 'submitted', isLatest: true),
            // Binh has nothing marked: the latest sitting leads.
            assessmentAttemptJson(51,
                assessmentId: '5',
                employeeId: '8',
                employeeName: 'Binh',
                attemptNo: 1,
                status: 'expired',
                isLatest: false),
            assessmentAttemptJson(52,
                assessmentId: '5',
                employeeId: '8',
                employeeName: 'Binh',
                attemptNo: 2,
                status: 'assigned',
                isLatest: true),
          ],
        ),
      );
      await _open(tester, wire);

      expect(find.byKey(AssessmentDetailScreen.attemptScoreKey('41')), findsOneWidget);
      expect(find.text('9/10 — passed'), findsOneWidget);
      expect(find.byKey(AssessmentDetailScreen.countingKey('41')), findsOneWidget);
      expect(find.text('Attempt 1'), findsNWidgets(2));
      expect(find.text('Attempt 2'), findsNWidgets(2));

      double top(Key key) => tester.getTopLeft(find.byKey(key)).dy;
      // An: the counting Attempt 1 above the later, unmarked Attempt 2.
      expect(
        top(AssessmentDetailScreen.attemptRowKey('41')),
        lessThan(top(AssessmentDetailScreen.attemptRowKey('42'))),
      );
      // Binh: nothing counts, so the latest (2) is above the earlier (1).
      expect(
        top(AssessmentDetailScreen.attemptRowKey('52')),
        lessThan(top(AssessmentDetailScreen.attemptRowKey('51'))),
      );
    });

    testWidgets('a score the caller may not read renders a dash', (tester) async {
      final wire = _wire(
        assessment: assessmentJson(
          5,
          attempts: [
            assessmentAttemptJson(41,
                assessmentId: '5', status: 'marked', scoreHidden: true, isCounting: true),
          ],
        ),
      );
      await _open(tester, wire);

      expect(
        tester.widget<Text>(find.byKey(AssessmentDetailScreen.attemptScoreKey('41'))).data,
        '—',
      );
    });
  });

  group('actions that would be refused say why', () {
    testWidgets('a closed Assessment refuses Assign, Close and Allow a retake', (tester) async {
      final wire = _wire(
        assessment: assessmentJson(
          5,
          status: 'closed',
          attemptsAllowed: 3,
          attempts: [
            assessmentAttemptJson(41, assessmentId: '5', status: 'marked', isCounting: true),
          ],
        ),
      );
      await _open(tester, wire);

      expect(_enabled(tester, AssessmentDetailScreen.assignKey), isFalse);
      expect(_enabled(tester, AssessmentDetailScreen.closeKey), isFalse);
      expect(_enabled(tester, AssessmentDetailScreen.retakeKey('41')), isFalse);
      expect(find.byKey(AssessmentDetailScreen.assignReasonKey), findsOneWidget);
      expect(find.text('This assessment is closed.'), findsNWidgets(3));
      expect(wire.assessmentCloses, isEmpty);
    });

    testWidgets('a draft Assessment says it is still a draft', (tester) async {
      final wire = _wire(assessment: assessmentJson(5, status: 'draft'));
      await _open(tester, wire);

      expect(_enabled(tester, AssessmentDetailScreen.assignKey), isFalse);
      expect(
        find.text('This assessment is still a draft. People are assigned when it is created.'),
        findsNWidgets(2),
      );
    });

    testWidgets('a retake is refused once every Attempt allowed has been used', (tester) async {
      final wire = _wire(
        assessment: assessmentJson(
          5,
          attemptsAllowed: 1,
          attempts: [
            assessmentAttemptJson(41, assessmentId: '5', status: 'marked', isCounting: true),
          ],
        ),
      );
      await _open(tester, wire);

      expect(_enabled(tester, AssessmentDetailScreen.retakeKey('41')), isFalse);
      expect(find.text('The 1 Attempt allowed has been used.'), findsOneWidget);
    });

    testWidgets('a retake is refused on an Attempt that is not finished', (tester) async {
      final wire = _wire(
        assessment: assessmentJson(
          5,
          attemptsAllowed: 3,
          attempts: [assessmentAttemptJson(41, assessmentId: '5', status: 'in_progress')],
        ),
      );
      await _open(tester, wire);

      expect(_enabled(tester, AssessmentDetailScreen.retakeKey('41')), isFalse);
      expect(
        find.text('Only a finished Attempt (submitted, marked or expired) can be retaken.'),
        findsOneWidget,
      );
    });

    testWidgets('a retake is refused on an Attempt that is not the latest', (tester) async {
      final wire = _wire(
        assessment: assessmentJson(
          5,
          attemptsAllowed: 3,
          attempts: [
            assessmentAttemptJson(41,
                assessmentId: '5', attemptNo: 1, status: 'expired', isLatest: false),
            assessmentAttemptJson(42,
                assessmentId: '5', attemptNo: 2, status: 'expired', isLatest: true),
          ],
        ),
      );
      await _open(tester, wire);

      expect(_enabled(tester, AssessmentDetailScreen.retakeKey('41')), isFalse);
      expect(find.text('A later Attempt already exists for this person.'), findsOneWidget);
      expect(_enabled(tester, AssessmentDetailScreen.retakeKey('42')), isTrue);
    });

    testWidgets('without the change permission every change is off and names the permission',
        (tester) async {
      final wire = _wire(
        permissions: const [_display],
        assessment: assessmentJson(
          5,
          attemptsAllowed: 3,
          attempts: [
            assessmentAttemptJson(41, assessmentId: '5', status: 'expired'),
            assessmentAttemptJson(42, assessmentId: '5', employeeId: '8', status: 'assigned'),
          ],
        ),
      );
      await _open(tester, wire);

      expect(_enabled(tester, AssessmentDetailScreen.assignKey), isFalse);
      expect(_enabled(tester, AssessmentDetailScreen.closeKey), isFalse);
      expect(_enabled(tester, AssessmentDetailScreen.retakeKey('41')), isFalse);
      expect(_enabled(tester, AssessmentDetailScreen.cancelKey('42')), isFalse);
      expect(find.text('You do not have permission to change assessments.'), findsWidgets);
    });

    testWidgets('outside the caller\'s reach the Assessment and the Attempt say so', (tester) async {
      final wire = _wire(
        assessment: assessmentJson(
          5,
          viewerMayChange: false,
          attemptsAllowed: 3,
          attempts: [
            assessmentAttemptJson(41,
                assessmentId: '5', status: 'expired', viewerMayChange: false),
          ],
        ),
      );
      await _open(tester, wire);

      expect(_enabled(tester, AssessmentDetailScreen.assignKey), isFalse);
      expect(_enabled(tester, AssessmentDetailScreen.closeKey), isFalse);
      expect(_enabled(tester, AssessmentDetailScreen.retakeKey('41')), isFalse);
      expect(find.text('This is outside the Org Units you may change.'), findsNWidgets(3));
    });

    testWidgets('Mark is off, and says why, when the caller may not mark', (tester) async {
      final wire = _wire(
        assessment: assessmentJson(
          5,
          viewerMayMark: false,
          attempts: [assessmentAttemptJson(41, assessmentId: '5', status: 'submitted')],
        ),
      );
      await _open(tester, wire);

      expect(_enabled(tester, AssessmentDetailScreen.markKey('41')), isFalse);
      expect(
        find.text('You do not have permission to mark this assessment\'s papers.'),
        findsOneWidget,
      );
    });
  });

  group('the actions that are allowed', () {
    testWidgets('Mark opens that Attempt\'s marking paper', (tester) async {
      final wire = _wire(
        assessment: assessmentJson(
          5,
          attempts: [assessmentAttemptJson(41, assessmentId: '5', status: 'submitted')],
        ),
      );
      await _open(tester, wire);
      expect(_enabled(tester, AssessmentDetailScreen.markKey('41')), isTrue);

      await tapIn(tester, find.byKey(AssessmentDetailScreen.markKey('41')));

      expect(find.byKey(AssessmentMarkingScreen.rowKey(1)), findsOneWidget);
    });

    testWidgets('cancelling an Attempt sends the reason, trimmed', (tester) async {
      final wire = _wire(
        assessment: assessmentJson(
          5,
          attempts: [assessmentAttemptJson(41, assessmentId: '5', status: 'assigned')],
        ),
      );
      await _open(tester, wire);

      await tapIn(tester, find.byKey(AssessmentDetailScreen.cancelKey('41')));
      await _giveReason(tester, '  Left the company  ');

      expect(wire.assessmentAttemptCancels.length, 1);
      expect(wire.assessmentAttemptCancels.single.$1, '41');
      expect(wire.assessmentAttemptCancels.single.$2, {'reason': 'Left the company'});
      expect(find.byKey(AssessmentReasonDialog.fieldKey), findsNothing);
    });

    testWidgets('a reason that is too short is refused before any request', (tester) async {
      final wire = _wire(
        assessment: assessmentJson(
          5,
          attempts: [assessmentAttemptJson(41, assessmentId: '5', status: 'assigned')],
        ),
      );
      await _open(tester, wire);

      await tapIn(tester, find.byKey(AssessmentDetailScreen.cancelKey('41')));
      await _giveReason(tester, ' ab ');

      expect(find.text('Give a reason of at least 3 characters.'), findsOneWidget);
      expect(find.byKey(AssessmentReasonDialog.fieldKey), findsOneWidget);
      expect(wire.assessmentAttemptCancels, isEmpty);
    });

    testWidgets('allowing a retake sends the reason', (tester) async {
      final wire = _wire(
        assessment: assessmentJson(
          5,
          attemptsAllowed: 2,
          attempts: [
            assessmentAttemptJson(41, assessmentId: '5', status: 'marked', isCounting: true),
          ],
        ),
      );
      await _open(tester, wire);
      expect(_enabled(tester, AssessmentDetailScreen.retakeKey('41')), isTrue);

      await tapIn(tester, find.byKey(AssessmentDetailScreen.retakeKey('41')));
      expect(find.text('Reason for the retake'), findsOneWidget);
      await _giveReason(tester, 'The paper was interrupted');

      expect(wire.assessmentAttemptRetakes.length, 1);
      expect(wire.assessmentAttemptRetakes.single.$1, '41');
      expect(wire.assessmentAttemptRetakes.single.$2, {'reason': 'The paper was interrupted'});
    });

    testWidgets('a refusal from the server is shown as it came', (tester) async {
      final wire = _wire(
        assessment: assessmentJson(
          5,
          attemptsAllowed: 2,
          attempts: [
            assessmentAttemptJson(41, assessmentId: '5', status: 'marked', isCounting: true),
          ],
        ),
      );
      wire.assessmentAttemptWriteStatus = 409;
      wire.assessmentAttemptWriteMessage = 'A later Attempt was created a moment ago.';
      await _open(tester, wire);

      await tapIn(tester, find.byKey(AssessmentDetailScreen.retakeKey('41')));
      await _giveReason(tester, 'Because');

      expect(find.byKey(AssessmentDetailScreen.failureKey), findsOneWidget);
      expect(find.text('A later Attempt was created a moment ago.'), findsOneWidget);
    });

    testWidgets('ending a sitting asks first, then sends it', (tester) async {
      final wire = _wire(
        assessment: assessmentJson(
          5,
          attempts: [assessmentAttemptJson(41, assessmentId: '5', status: 'in_progress')],
        ),
      );
      await _open(tester, wire);

      await tapIn(tester, find.byKey(AssessmentDetailScreen.endSittingKey('41')));
      expect(find.text('End this sitting?'), findsOneWidget);
      expect(wire.assessmentSittingEnds, isEmpty);
      await tester.tap(find.byKey(AppConfirmDialog.confirmKey));
      await tester.pumpAndSettle();

      expect(wire.assessmentSittingEnds, ['41']);
    });

    testWidgets('closing the Assessment asks first, then sends it', (tester) async {
      final wire = _wire(assessment: assessmentJson(5));
      await _open(tester, wire);

      await tapIn(tester, find.byKey(AssessmentDetailScreen.closeKey));
      expect(find.text('Close this assessment?'), findsOneWidget);
      expect(wire.assessmentCloses, isEmpty);
      await tester.tap(find.byKey(AppConfirmDialog.confirmKey));
      await tester.pumpAndSettle();

      expect(wire.assessmentCloses, ['5']);
    });

    testWidgets('assigning more people sends the group the dialog built', (tester) async {
      final wire = _wire(assessment: assessmentJson(5));
      await _open(tester, wire);

      await tapIn(tester, find.byKey(AssessmentDetailScreen.assignKey));
      // Nothing chosen yet: the confirm is off.
      expect(
        tester.widget<ButtonStyleButton>(find.byKey(AssessmentAssignDialog.submitKey)).onPressed,
        isNull,
      );

      await typeInSearchField(tester, AssessmentAssignDialog.orgUnitSearchKey, 'Br');
      await tester.pump();
      await tapIn(tester, find.byKey(AssessmentAssignDialog.orgUnitSuggestionKey('11')));
      expect(find.byKey(AssessmentAssignDialog.orgUnitChipKey('11')), findsOneWidget);
      expect(find.text('This will reach 3 Employees.'), findsOneWidget);

      await tester.tap(find.byKey(AssessmentAssignDialog.submitKey));
      await tester.pumpAndSettle();

      expect(wire.assessmentAssigns.length, 1);
      expect(wire.assessmentAssigns.single.$1, '5');
      expect(wire.assessmentAssigns.single.$2['orgUnitIds'], ['11']);
    });
  });
}
