/// Preventive maintenance — Job plans and PM schedules (issue #74), with the
/// wire faked — the one client seam (ADR-0012). The real app, the real router,
/// the real Blocs, `MockClient` at the HTTP boundary and `FakeAuthGateway` at
/// the auth boundary.
///
/// What these tests claim and what they do not: that a Job plan renders with
/// its ordered steps and each step's required Skill's name; that an
/// administrator can create one and the POST carries every task and the
/// chosen Skill; that a PM schedule can be attached to an Asset and the POST
/// carries the Asset, the Job plan, the interval and the anchor; that a Work
/// order's copied task shows its required Skill's name on the detail view;
/// that the two lists' loading, empty and failure-with-retry states render;
/// and that the Destination and route gating matches the role sets. Not that
/// the server enforces scope, validates the work type, or computes the next
/// due date — those are proved in
/// `backend/test/integration/preventive-maintenance.test.js`, and neither
/// substitutes for the other.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/maintenance/job_plan_form_dialog.dart';
import 'package:lean_platform/maintenance/job_plans_screen.dart';
import 'package:lean_platform/maintenance/pm_schedule_form_dialog.dart';
import 'package:lean_platform/maintenance/pm_schedules_screen.dart';
import 'package:lean_platform/maintenance/work_order_detail_screen.dart';
import 'package:lean_platform/maintenance/work_orders_screen.dart';
import 'package:lean_platform/platform/access_denied_screen.dart';
import 'package:lean_platform/platform/destinations.dart';
import 'package:lean_platform/widgets/app_filter_field.dart';
import 'package:lean_platform/widgets/skeleton_list.dart';
import 'harness.dart';

FakeWire wireWith({
  String role = Roles.admin,
  Map<String, dynamic>? orgUnitScope,
  List<Map<String, dynamic>>? sites,
  Map<String, List<Map<String, dynamic>>>? assets,
  List<Map<String, dynamic>>? jobPlans,
  int jobPlansStatus = 200,
  int createJobPlanStatus = 201,
  Map<String, List<Map<String, dynamic>>>? pmSchedules,
  int pmSchedulesStatus = 200,
  int createPmScheduleStatus = 201,
  Map<String, List<Map<String, dynamic>>>? workOrders,
  Map<String, List<Map<String, dynamic>>>? workOrderTasks,
  int workOrderDetailStatus = 200,
  List<Map<String, dynamic>>? skills,
}) =>
    FakeWire(
      role: role,
      orgUnitScope: orgUnitScope,
      sites: sites ?? [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [orgUnitJson('10', 'Assembly')],
      },
      assets: assets ?? {'1': []},
      jobPlans: jobPlans,
      jobPlansStatus: jobPlansStatus,
      createJobPlanStatus: createJobPlanStatus,
      pmSchedules: pmSchedules,
      pmSchedulesStatus: pmSchedulesStatus,
      createPmScheduleStatus: createPmScheduleStatus,
      workOrders: workOrders,
      workOrderTasks: workOrderTasks,
      workOrderDetailStatus: workOrderDetailStatus,
      skills: skills,
    );

/// A supervisor holding a write Grant at Org Unit 10 — the caller every PM
/// schedule action test uses.
const Map<String, dynamic> _writeGrant = {
  'everywhere': false,
  'grants': [
    {'orgUnitId': '10', 'siteId': '1', 'canWrite': true},
  ],
};

void main() {
  // The `Job plans` Destination is administrator-only; the route admits the
  // Module's role set to read but offers no write controls to a
  // non-administrator. The `PM schedules` Destination follows the Module's
  // role set exactly.

  testWidgets('an administrator is offered Job plans and PM schedules', (tester) async {
    final wire = wireWith(role: Roles.admin, jobPlans: const [], pmSchedules: {'1': []});
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/job-plans',
    );

    expect(find.byKey(const ValueKey('nav-item-Job plans')), findsOneWidget);
    expect(find.byKey(const ValueKey('nav-item-PM schedules')), findsOneWidget);
  });

  testWidgets('a supervisor is offered PM schedules but not Job plans', (tester) async {
    final wire = wireWith(
      role: Roles.supervisor,
      orgUnitScope: _writeGrant,
      pmSchedules: {'1': []},
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/pm-schedules',
    );

    expect(find.byKey(const ValueKey('nav-item-PM schedules')), findsOneWidget);
    expect(find.byKey(const ValueKey('nav-item-Job plans')), findsNothing);
  });

  testWidgets('an operator who types the PM schedules address is refused it', (tester) async {
    final wire = wireWith(role: Roles.operator, pmSchedules: {'1': []});
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/pm-schedules',
    );

    expect(find.byType(AccessDeniedScreen), findsOneWidget);
    expect(find.byType(PmSchedulesScreen), findsNothing);
  });

  testWidgets('a supervisor reads the Job plan catalogue but is offered no write controls',
      (tester) async {
    final wire = wireWith(
      role: Roles.supervisor,
      orgUnitScope: _writeGrant,
      jobPlans: [jobPlanJson('1', 'JP-1', 'Annual service')],
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/job-plans',
    );

    expect(find.byType(JobPlansScreen), findsOneWidget);
    expect(find.byKey(JobPlansScreen.addKey), findsNothing);
    expect(find.byKey(JobPlansScreen.toggleKey('1')), findsNothing);
  });

  testWidgets('a Job plan renders with its ordered steps and each required Skill',
      (tester) async {
    final wire = wireWith(
      jobPlans: [
        jobPlanJson(
          '1',
          'JP-1',
          'Annual service',
          workType: 'preventive',
          tasks: [
            jobPlanTaskJson('t1', 1, 'Isolate the motor', skillId: '3', skillName: 'Electrical'),
            jobPlanTaskJson('t2', 2, 'Replace the filter', estimatedHours: 1),
          ],
        ),
      ],
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/job-plans',
    );

    expect(find.byKey(JobPlansScreen.rowKey('1')), findsOneWidget);
    expect(find.text('Annual service'), findsOneWidget);
    expect(find.text('Isolate the motor'), findsOneWidget);
    expect(find.text('Requires Electrical'), findsOneWidget);
    expect(find.text('Replace the filter'), findsOneWidget);
    expect(find.text('No skill required'), findsOneWidget);
  });

  testWidgets('an administrator creates a Job plan and the POST carries the tasks and Skill',
      (tester) async {
    final wire = wireWith(
      jobPlans: const [],
      skills: [skillJson('3', 'ELEC', 'Electrical')],
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/job-plans',
    );

    await tapIn(tester, find.byKey(JobPlansScreen.addKey));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(JobPlanFormDialog.codeKey), 'JP-2');
    await tester.enterText(find.byKey(JobPlanFormDialog.nameKey), 'Quarterly inspection');
    await tester.enterText(
      find.byKey(JobPlanFormDialog.taskInstructionKey(0)),
      'Check the guard',
    );
    await tester.pumpAndSettle();

    await tapIn(tester, find.byKey(JobPlanFormDialog.taskSkillKey(0)));
    await tapIn(tester, find.text('Electrical').last);

    await tapIn(tester, find.byKey(JobPlanFormDialog.submitKey));

    expect(find.byType(JobPlanFormDialog), findsNothing);
    expect(wire.jobPlanPosts.length, 1);
    final sent = wire.jobPlanPosts.single;
    expect(sent['code'], 'JP-2');
    expect(sent['name'], 'Quarterly inspection');
    final tasks = (sent['tasks'] as List<dynamic>).cast<Map<String, dynamic>>();
    expect(tasks.length, 1);
    expect(tasks.single['instruction'], 'Check the guard');
    expect(tasks.single['skillId'], '3');
  });

  testWidgets('an administrator deactivates a Job plan', (tester) async {
    final wire = wireWith(jobPlans: [jobPlanJson('1', 'JP-1', 'Annual service')]);
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/job-plans',
    );

    await tapIn(tester, find.byKey(JobPlansScreen.toggleKey('1')));

    expect(wire.jobPlanPatches.length, 1);
    final (id, body) = wire.jobPlanPatches.single;
    expect(id, '1');
    expect(body['isActive'], isFalse);
    expect(find.byKey(JobPlansScreen.inactiveChipKey('1')), findsOneWidget);
  });

  testWidgets('a PM schedule is attached to an Asset and the POST carries the choices',
      (tester) async {
    final wire = wireWith(
      role: Roles.supervisor,
      orgUnitScope: _writeGrant,
      assets: {
        '1': [assetJson('7', 'PRESS-1', 'Press 1')],
      },
      jobPlans: [jobPlanJson('5', 'JP-5', 'Annual service')],
      pmSchedules: {'1': []},
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/pm-schedules',
    );

    await tapIn(tester, find.byKey(PmSchedulesScreen.createKey));
    await tester.pumpAndSettle();

    await tapIn(tester, find.byKey(PmScheduleFormDialog.assetKey));
    await tapIn(tester, find.text('Press 1 (PRESS-1)').last);
    await tapIn(tester, find.byKey(PmScheduleFormDialog.jobPlanKey));
    await tapIn(tester, find.text('Annual service').last);
    await tester.enterText(find.byKey(PmScheduleFormDialog.intervalKey), '30');
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(PmScheduleFormDialog.anchorKey));
    await tapIn(tester, find.text('Due date').last);

    await tapIn(tester, find.byKey(PmScheduleFormDialog.submitKey));

    expect(find.byType(PmScheduleFormDialog), findsNothing);
    expect(wire.pmSchedulePosts.length, 1);
    final sent = wire.pmSchedulePosts.single;
    expect(sent['assetId'], '7');
    expect(sent['jobPlanId'], '5');
    expect(sent['intervalDays'], 30);
    expect(sent['anchor'], 'due');
  });

  testWidgets('a Work order row opens its detail, where a task shows its required Skill',
      (tester) async {
    final wire = wireWith(
      workOrders: {
        '1': [workOrderJson('101', 'WO-101', 'Belt is slipping')],
      },
      workOrderTasks: {
        '101': [
          workOrderTaskJson('t1', 1, 'Lock out the motor', skillId: '3', skillName: 'Electrical'),
        ],
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders',
    );

    await tapIn(tester, find.byKey(WorkOrdersScreen.detailsKey('101')));

    expect(find.byType(WorkOrderDetailScreen), findsOneWidget);
    expect(wire.workOrderDetailRequests, ['101']);
    expect(find.text('Lock out the motor'), findsOneWidget);
    expect(find.text('Requires Electrical'), findsOneWidget);
  });

  testWidgets('the Job plans list shows placeholders while it loads', (tester) async {
    final wire = wireWith(jobPlans: const [])..jobPlansGate = Completer<void>();
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/job-plans',
      settle: false,
    );

    expect(find.byType(SkeletonList), findsOneWidget);
    expect(find.byKey(JobPlansScreen.emptyKey), findsNothing);

    wire.jobPlansGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(SkeletonList), findsNothing);
  });

  testWidgets('an empty Job plan catalogue says so plainly', (tester) async {
    final wire = wireWith(jobPlans: const []);
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/job-plans',
    );

    expect(find.byKey(JobPlansScreen.emptyKey), findsOneWidget);
    expect(find.byKey(JobPlansScreen.failedKey), findsNothing);
  });

  testWidgets('a failed Job plan load explains itself and the retry works', (tester) async {
    final wire = wireWith(jobPlansStatus: 503);
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/job-plans',
    );

    expect(find.byKey(JobPlansScreen.failedKey), findsOneWidget);
    expect(find.text('The Job plans are unavailable.'), findsOneWidget);

    wire.jobPlansStatus = 200;
    wire.jobPlans = [jobPlanJson('1', 'JP-1', 'Annual service')];
    await tapIn(tester, find.byKey(JobPlansScreen.retryKey));

    expect(find.byKey(JobPlansScreen.failedKey), findsNothing);
    expect(find.byKey(JobPlansScreen.rowKey('1')), findsOneWidget);
  });

  testWidgets('the PM schedule list shows placeholders while it loads', (tester) async {
    final wire = wireWith(pmSchedules: {'1': []})..pmSchedulesGate = Completer<void>();
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/pm-schedules',
      settle: false,
    );

    expect(find.byType(SkeletonList), findsOneWidget);
    expect(find.byKey(PmSchedulesScreen.emptyKey), findsNothing);

    wire.pmSchedulesGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(SkeletonList), findsNothing);
  });

  testWidgets('an empty PM schedule list says so plainly', (tester) async {
    final wire = wireWith(pmSchedules: {'1': []});
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/pm-schedules',
    );

    expect(find.byKey(PmSchedulesScreen.emptyKey), findsOneWidget);
    expect(find.byKey(PmSchedulesScreen.failedKey), findsNothing);
  });

  testWidgets('a failed PM schedule load explains itself and the retry works', (tester) async {
    final wire = wireWith(pmSchedulesStatus: 503);
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/pm-schedules',
    );

    expect(find.byKey(PmSchedulesScreen.failedKey), findsOneWidget);
    expect(find.text('The PM schedules are unavailable.'), findsOneWidget);

    wire.pmSchedulesStatus = 200;
    wire.pmSchedules = {
      '1': [pmScheduleJson('1', 'PM-1', 'Annual service - Press 1')],
    };
    await tapIn(tester, find.byKey(PmSchedulesScreen.retryKey));

    expect(find.byKey(PmSchedulesScreen.failedKey), findsNothing);
    expect(find.byKey(PmSchedulesScreen.rowKey('1')), findsOneWidget);
  });

  // Issue #191: a register is narrowed by text, not by scrolling. Each Screen
  // owns its own term and narrows the rows it has already read — the wire's
  // own record is what proves no request was sent for the term.
  testWidgets('the PM schedules are narrowed by a typed term, and typing costs no request', (tester) async {
    // The filter box this register now carries (issue #191) sits above the
    // rows, so a two-row register no longer fits flutter_test's default
    // 800x600 surface: the rows below the fold are `ListView` children that
    // have not been built yet, and `find.byKey` would find nothing. The taller
    // window is the fixture's, not the Screen's — the same pin this repo's
    // lazy-list tests already use.
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1000, 1200);
    addTearDown(tester.view.reset);

    final wire = wireWith(
      pmSchedules: {
        '1': [
          pmScheduleJson('9', 'PM-9', 'Quarterly press service'),
          pmScheduleJson('10', 'PM-10', 'Conveyor belt check',
              assetCode: 'CONV-2', assetName: 'Infeed conveyor'),
        ],
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/pm-schedules',
    );

    // Nothing narrowed yet: every row, and no count line to read.
    expect(find.byKey(PmSchedulesScreen.rowKey('10')), findsOneWidget);
    expect(find.byKey(PmSchedulesScreen.rowKey('9')), findsOneWidget);
    expect(find.byKey(PmSchedulesScreen.filterCountKey), findsNothing);

    final requestsBefore = wire.requests.length;
    await tester.enterText(find.byKey(PmSchedulesScreen.filterFieldKey), 'conveyor');
    await tester.pumpAndSettle();

    // (a) the rows narrow, (c) the count line says how many of how many.
    expect(find.byKey(PmSchedulesScreen.rowKey('10')), findsOneWidget);
    expect(find.byKey(PmSchedulesScreen.rowKey('9')), findsNothing);
    expect(find.byKey(PmSchedulesScreen.filterCountKey), findsOneWidget);
    expect(find.text(AppFilterField.countLabel(1, 2)), findsOneWidget);

    // (b) narrowing a register the client already holds costs no request.
    expect(wire.requests.length, requestsBefore,
        reason: 'typing must not read anything over the wire');

    // (d) one clear affordance, and every row is back.
    await tester.tap(find.byKey(PmSchedulesScreen.filterClearKey));
    await tester.pumpAndSettle();

    expect(find.byKey(PmSchedulesScreen.rowKey('10')), findsOneWidget);
    expect(find.byKey(PmSchedulesScreen.rowKey('9')), findsOneWidget);
    expect(find.byKey(PmSchedulesScreen.filterCountKey), findsNothing);
    expect(wire.requests.length, requestsBefore);
  });

  // Issue #191: a register is narrowed by text, not by scrolling. Each Screen
  // owns its own term and narrows the rows it has already read — the wire's
  // own record is what proves no request was sent for the term.
  testWidgets('the Job plans are narrowed by a typed term, and typing costs no request', (tester) async {
    // The filter box this register now carries (issue #191) sits above the
    // rows, so a two-row register no longer fits flutter_test's default
    // 800x600 surface: the rows below the fold are `ListView` children that
    // have not been built yet, and `find.byKey` would find nothing. The taller
    // window is the fixture's, not the Screen's — the same pin this repo's
    // lazy-list tests already use.
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1000, 1200);
    addTearDown(tester.view.reset);

    final wire = wireWith(
      jobPlans: [
        jobPlanJson('5', 'JP-5', 'Press service'),
        jobPlanJson('6', 'JP-6', 'Conveyor belt replacement',
            description: 'Replace the belt'),
      ],
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/job-plans',
    );

    // Nothing narrowed yet: every row, and no count line to read.
    expect(find.byKey(JobPlansScreen.rowKey('6')), findsOneWidget);
    expect(find.byKey(JobPlansScreen.rowKey('5')), findsOneWidget);
    expect(find.byKey(JobPlansScreen.filterCountKey), findsNothing);

    final requestsBefore = wire.requests.length;
    await tester.enterText(find.byKey(JobPlansScreen.filterFieldKey), 'conveyor');
    await tester.pumpAndSettle();

    // (a) the rows narrow, (c) the count line says how many of how many.
    expect(find.byKey(JobPlansScreen.rowKey('6')), findsOneWidget);
    expect(find.byKey(JobPlansScreen.rowKey('5')), findsNothing);
    expect(find.byKey(JobPlansScreen.filterCountKey), findsOneWidget);
    expect(find.text(AppFilterField.countLabel(1, 2)), findsOneWidget);

    // (b) narrowing a register the client already holds costs no request.
    expect(wire.requests.length, requestsBefore,
        reason: 'typing must not read anything over the wire');

    // (d) one clear affordance, and every row is back.
    await tester.tap(find.byKey(JobPlansScreen.filterClearKey));
    await tester.pumpAndSettle();

    expect(find.byKey(JobPlansScreen.rowKey('6')), findsOneWidget);
    expect(find.byKey(JobPlansScreen.rowKey('5')), findsOneWidget);
    expect(find.byKey(JobPlansScreen.filterCountKey), findsNothing);
    expect(wire.requests.length, requestsBefore);
  });
}
