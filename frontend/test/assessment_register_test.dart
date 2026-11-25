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

import 'package:lean_platform/people/assessment_detail_screen.dart';
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

  group('the All tab\'s filters', () {
    FakeWire wire() => _wire(
          register: [
            assessmentJson(5, orgUnitId: '11', orgUnitName: 'Braiding', title: 'Kiểm tra Braiding'),
            assessmentJson(6, orgUnitId: '12', orgUnitName: 'Cutting', title: 'Kiểm tra Cutting'),
          ],
        );

    Future<void> openAll(WidgetTester tester, FakeWire wire) async {
      await _open(tester, wire);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AssessmentsScreen.tabKey(2)));
      await tester.pumpAndSettle();
    }

    testWidgets('the process, status, dates and below pass mark are sent as query parameters',
        (tester) async {
      final w = wire();
      await openAll(tester, w);
      // The opening reads carry no filter at all.
      expect(w.assessmentRegisterReads.every((read) => !read.containsKey('orgUnitId')), isTrue);
      expect(w.assessmentRegisterReads.every((read) => !read.containsKey('failed')), isTrue);

      await tester.tap(find.byKey(AssessmentsScreen.filterProcessKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cutting').last);
      await tester.pumpAndSettle();
      expect(w.assessmentRegisterReads.last['orgUnitId'], '12');

      await tester.tap(find.byKey(AssessmentsScreen.filterStatusKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Closed').last);
      await tester.pumpAndSettle();
      expect(w.assessmentRegisterReads.last['status'], 'closed');
      expect(w.assessmentRegisterReads.last['orgUnitId'], '12');

      await pickDate(tester, AssessmentsScreen.filterFromKey, DateTime(2026, 11, 1));
      await tester.pumpAndSettle();
      expect(w.assessmentRegisterReads.last['from'], '2026-11-01');
      await pickDate(tester, AssessmentsScreen.filterToKey, DateTime(2026, 11, 30));
      await tester.pumpAndSettle();
      expect(w.assessmentRegisterReads.last['to'], '2026-11-30');

      await tester.tap(find.byKey(AssessmentsScreen.filterFailedKey));
      await tester.pumpAndSettle();
      expect(w.assessmentRegisterReads.last, {
        'orgUnitId': '12',
        'status': 'closed',
        'from': '2026-11-01',
        'to': '2026-11-30',
        'failed': 'true',
      });
    });

    testWidgets('tapping a row opens that Assessment\'s detail', (tester) async {
      final w = wire();
      w.assessmentRegister = [
        assessmentJson(
          5,
          title: 'Kiểm tra Braiding',
          attempts: [assessmentAttemptJson(41, assessmentId: '5', employeeName: 'Tran Van An')],
        ),
      ];
      await openAll(tester, w);

      await tester.tap(find.byKey(AssessmentsScreen.assessmentRowKey('5')));
      await tester.pumpAndSettle();

      expect(find.byKey(AssessmentDetailScreen.factsKey), findsOneWidget);
      expect(find.text('Tran Van An'), findsOneWidget);
    });
  });
}
