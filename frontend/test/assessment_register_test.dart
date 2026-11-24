/// The Assessments register (issue #588, ADR-0068, slice 3) — the wire faked,
/// the one client seam (ADR-0012, AGENTS.md §5).
///
/// What a person sees on `/assessments`: their own Attempts first, the
/// Assessments they created and every Assessment behind two more chips, and the
/// one action that matters on an Attempt — Start. Every assertion is on rendered
/// text, a `Key`, or a request the fake wire recorded; nothing reads a Bloc.
library;

import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/people/assessment_sitting_screen.dart';
import 'package:lean_platform/people/assessments_screen.dart';
import 'package:lean_platform/platform/destinations.dart';
import 'package:lean_platform/platform/router.dart';

import 'harness.dart';

const _display = 'PPL_ASSESSMENT_DISPLAY';
const _change = 'PPL_ASSESSMENT_CHANGE';
const _sit = 'PPL_ASSESSMENT_SIT';

FakeWire _wire({
  List<String> permissions = const [_display, _change, _sit],
  List<Map<String, dynamic>> mine = const [],
  List<Map<String, dynamic>> register = const [],
  int mineStatus = 200,
}) {
  final wire = FakeWire(
    role: Roles.supervisor,
    mePermissions: permissions,
    sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
  );
  wire.myAssessmentAttempts = mine;
  wire.myAssessmentAttemptsStatus = mineStatus;
  wire.assessmentRegister = register;
  return wire;
}

void _tall(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1200, 2400);
  addTearDown(tester.view.reset);
}

Future<void> _open(WidgetTester tester, FakeWire wire, {String location = Routes.assessments}) {
  _tall(tester);
  return pumpApp(
    tester,
    gateway: FakeAuthGateway(accessToken: 'a-token'),
    client: wire.client,
    initialLocation: location,
  );
}

void main() {
  testWidgets('the register opens on the caller\'s own Attempts, with Start on one that has not begun',
      (tester) async {
    final wire = _wire(
      mine: [
        assessmentAttemptJson(
          41,
          assessmentId: '5',
          assessmentNumber: 'AS-HCM-2026-00005',
          assessmentTitle: 'Kiểm tra quy trình Braiding',
          processName: 'Braiding',
          questionCount: 10,
        ),
      ],
      register: [assessmentJson(5, assignedCount: 1)],
    );
    await _open(tester, wire);
    await tester.pumpAndSettle();

    expect(find.text('Assessments'), findsWidgets);
    expect(find.text('Kiểm tra quy trình Braiding'), findsOneWidget);
    expect(find.text('Not started'), findsOneWidget);
    expect(find.byKey(AssessmentsScreen.attemptActionKey('41')), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    // The three chips are all there, and the first is the one selected.
    expect(find.byKey(AssessmentsScreen.tabKey(0)), findsOneWidget);
    expect(find.byKey(AssessmentsScreen.tabKey(1)), findsOneWidget);
    expect(find.byKey(AssessmentsScreen.tabKey(2)), findsOneWidget);
  });

  testWidgets('an Account linked to no Employee is an empty tab, not a failure', (tester) async {
    final wire = _wire(mineStatus: 403, register: const []);
    await _open(tester, wire);
    await tester.pumpAndSettle();

    expect(find.byKey(AssessmentsScreen.emptyKey), findsOneWidget);
    expect(find.text('No assessment is assigned to you.'), findsOneWidget);
    expect(find.byKey(AssessmentsScreen.failedKey), findsNothing);
  });

  testWidgets('the I created tab lists Assessments with their four sitting counts', (tester) async {
    final wire = _wire(
      register: [
        assessmentJson(
          9,
          title: 'Kiểm tra Cutting',
          orgUnitName: 'Cutting MTU',
          questionCount: 15,
          minutes: 30,
          dueOn: '2026-12-01',
          assignedCount: 4,
          runningCount: 1,
          awaitingMarkingCount: 2,
          markedCount: 3,
        ),
      ],
    );
    await _open(tester, wire);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(AssessmentsScreen.tabKey(1)));
    await tester.pumpAndSettle();

    expect(find.byKey(AssessmentsScreen.assessmentRowKey('9')), findsOneWidget);
    expect(find.text('Kiểm tra Cutting'), findsOneWidget);
    expect(find.textContaining('Cutting MTU'), findsWidgets);
    expect(find.textContaining('15 Questions'), findsWidgets);
    expect(find.textContaining('30 minutes'), findsWidgets);
    expect(find.textContaining('due 2026-12-01'), findsWidgets);
    expect(find.textContaining('4 not started'), findsOneWidget);
  });

  testWidgets('Start opens the sitting Screen for that Attempt', (tester) async {
    final wire = _wire(
      mine: [assessmentAttemptJson(41, assessmentId: '5', assessmentTitle: 'Kiểm tra Braiding')],
      register: [assessmentJson(5)],
    );
    wire.assessmentPaper = assessmentPaperJson(attemptId: 41, assessmentId: 5);
    await _open(tester, wire);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(AssessmentsScreen.attemptActionKey('41')));
    await tester.pumpAndSettle();

    expect(find.byKey(AssessmentSittingScreen.countdownKey), findsOneWidget);
  });

  testWidgets('New assessment is not offered to a caller who may only read assessments', (tester) async {
    final reader = _wire(permissions: const [_display, _sit]);
    await _open(tester, reader);
    await tester.pumpAndSettle();
    expect(find.byKey(AssessmentsScreen.newAssessmentKey), findsNothing);
  });

  testWidgets('New assessment opens the create form for a caller who may change assessments', (tester) async {
    final writer = _wire();
    await _open(tester, writer);
    await tester.pumpAndSettle();
    expect(find.byKey(AssessmentsScreen.newAssessmentKey), findsOneWidget);

    await tester.tap(find.byKey(AssessmentsScreen.newAssessmentKey));
    await tester.pumpAndSettle();
    // The create form, at its own address.
    expect(find.text('Who sits it'), findsOneWidget);
  });
}
