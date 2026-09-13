/// Meters and readings (issue #79), with the wire faked — the one client seam
/// (ADR-0012). The real app, the real router, the real Blocs, `MockClient` at
/// the HTTP boundary and `FakeAuthGateway` at the auth boundary.
///
/// What these tests claim and what they do not: that a meter renders with its
/// latest reading and accumulated use; that recording a reading and recording
/// a rollover each send the right request and update what renders; that a
/// meter-driven PM schedule shows its interval in accumulated use and whether
/// it is due; that the create form carries a meter and its interval; and that
/// a reading can be recorded while working a Work order task that names a
/// meter. Not that the server refuses a backwards reading or resolves a shift
/// instance — those are proved in
/// `backend/test/integration/meter-driven-pm.test.js`, and neither substitutes
/// for the other.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/maintenance/meter_form_dialog.dart';
import 'package:lean_platform/maintenance/meters_screen.dart';
import 'package:lean_platform/maintenance/pm_schedule_form_dialog.dart';
import 'package:lean_platform/maintenance/pm_schedules_screen.dart';
import 'package:lean_platform/maintenance/reading_form_dialog.dart';
import 'package:lean_platform/maintenance/task_reading_dialog.dart';
import 'package:lean_platform/maintenance/work_order_detail_screen.dart';
import 'package:lean_platform/maintenance/work_orders_screen.dart';
import 'package:lean_platform/platform/destinations.dart';

import 'harness.dart';

/// A supervisor holding a write Grant at Org Unit 10 — the caller every meter
/// action test uses.
const Map<String, dynamic> _writeGrant = {
  'everywhere': false,
  'grants': [
    {'orgUnitId': '10', 'siteId': '1', 'canWrite': true},
  ],
};

FakeWire wireWith({
  String role = Roles.supervisor,
  Map<String, dynamic>? orgUnitScope = _writeGrant,
  Map<String, List<Map<String, dynamic>>>? assets,
  Map<String, List<Map<String, dynamic>>>? meters,
  Map<String, List<Map<String, dynamic>>>? pmSchedules,
  List<Map<String, dynamic>>? jobPlans,
  Map<String, List<Map<String, dynamic>>>? workOrders,
  Map<String, List<Map<String, dynamic>>>? workOrderTasks,
}) =>
    FakeWire(
      role: role,
      orgUnitScope: orgUnitScope,
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [orgUnitJson('10', 'Assembly')],
      },
      assets: assets ?? {'1': []},
      meters: meters,
      pmSchedules: pmSchedules,
      jobPlans: jobPlans,
      workOrders: workOrders,
      workOrderTasks: workOrderTasks,
    );

void main() {
  testWidgets('a meter renders with its latest reading and accumulated use', (tester) async {
    final wire = wireWith(
      meters: {
        '1': [
          meterJson(
            '5',
            'RUN-HRS',
            'Running hours',
            assetId: '7',
            accumulatedUse: 900,
            latestReading: 900,
          ),
        ],
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/meters',
    );

    expect(find.byType(MetersScreen), findsOneWidget);
    expect(find.byKey(MetersScreen.rowKey('5')), findsOneWidget);
    expect(find.textContaining('Latest: 900 H'), findsOneWidget);
    expect(find.textContaining('Accumulated use: 900 H'), findsOneWidget);
    expect(wire.meterSites, ['1']);
  });

  testWidgets('a supervisor is offered the Meters Destination', (tester) async {
    final wire = wireWith(meters: {'1': []});
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/meters',
    );

    expect(find.byKey(const ValueKey('nav-item-Meters')), findsOneWidget);
  });

  testWidgets('recording a reading posts it and shows the new accumulated use', (tester) async {
    final wire = wireWith(
      meters: {
        '1': [
          meterJson(
            '5',
            'RUN-HRS',
            'Running hours',
            assetId: '7',
            accumulatedUse: 900,
            latestReading: 900,
          ),
        ],
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/meters',
    );

    await tapIn(tester, find.byKey(MetersScreen.readingKey('5')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(ReadingFormDialog.readingKey), '950');
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(ReadingFormDialog.submitKey));

    expect(find.byType(ReadingFormDialog), findsNothing);
    expect(wire.meterReadingPosts.length, 1);
    final (meterId, body) = wire.meterReadingPosts.single;
    expect(meterId, '5');
    expect(body['reading'], 950);
    expect(find.textContaining('Accumulated use: 950 H'), findsOneWidget);
  });

  testWidgets('recording a rollover posts it and carries the accumulated use forward', (tester) async {
    final wire = wireWith(
      meters: {
        '1': [
          meterJson(
            '5',
            'RUN-HRS',
            'Running hours',
            assetId: '7',
            accumulatedUse: 900,
            latestReading: 900,
          ),
        ],
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/meters',
    );

    await tapIn(tester, find.byKey(MetersScreen.readingKey('5')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(ReadingFormDialog.readingKey), '0');
    await tapIn(tester, find.byKey(ReadingFormDialog.rolloverKey));
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(ReadingFormDialog.submitKey));

    expect(wire.meterRolloverPosts.length, 1);
    final (meterId, body) = wire.meterRolloverPosts.single;
    expect(meterId, '5');
    expect(body['reading'], 0);
    expect(find.textContaining('Carried forward: 900 H'), findsOneWidget);
  });

  testWidgets('defining a meter posts the Asset, unit and kind', (tester) async {
    final wire = wireWith(assets: {
      '1': [assetJson('7', 'PRESS-1', 'Press 1')],
    });
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/meters',
    );

    await tapIn(tester, find.byKey(MetersScreen.createKey));
    await tester.pumpAndSettle();

    await tapIn(tester, find.byKey(MeterFormDialog.assetKey));
    await tapIn(tester, find.text('Press 1 (PRESS-1)').last);
    await tester.enterText(find.byKey(MeterFormDialog.codeKey), 'CYC');
    await tester.enterText(find.byKey(MeterFormDialog.nameKey), 'Cycles');
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(MeterFormDialog.uomKey));
    await tapIn(tester, find.text('Each (EA)').last);
    await tapIn(tester, find.byKey(MeterFormDialog.submitKey));

    expect(find.byType(MeterFormDialog), findsNothing);
    expect(wire.meterPosts.length, 1);
    final sent = wire.meterPosts.single;
    expect(sent['assetId'], '7');
    expect(sent['code'], 'CYC');
    expect(sent['uomCode'], 'EA');
    expect(sent['meterType'], 'cumulative');
  });

  testWidgets('a meter-driven schedule shows its accumulated-use state', (tester) async {
    final wire = wireWith(
      pmSchedules: {
        '1': [
          pmScheduleJson(
            '9',
            'PM-9',
            '500-hour service - Compressor',
            intervalDays: null,
            assetMeterId: '5',
            meterCode: 'RUN-HRS',
            meterName: 'Running hours',
            meterType: 'cumulative',
            intervalMeter: 500,
            currentMeter: 600,
            nextDueMeter: 500,
            meterDue: true,
          ),
        ],
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/pm-schedules',
    );

    expect(find.byKey(PmSchedulesScreen.rowKey('9')), findsOneWidget);
    expect(find.text('Every 500 of Running hours'), findsOneWidget);
    expect(find.text('Accumulated 600 of 500'), findsOneWidget);
    expect(find.text('Due now'), findsOneWidget);
  });

  testWidgets('the schedule form can choose accumulated use and posts the meter and interval',
      (tester) async {
    final wire = wireWith(
      assets: {
        '1': [assetJson('7', 'PRESS-1', 'Press 1')],
      },
      jobPlans: [jobPlanJson('5', 'JP-5', 'Annual service')],
      meters: {
        '1': [
          meterJson('5', 'RUN-HRS', 'Running hours', assetId: '7'),
        ],
      },
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
    await tapIn(tester, find.byKey(PmScheduleFormDialog.basisKey));
    await tapIn(tester, find.text('Accumulated use').last);
    await tester.pumpAndSettle();

    await tapIn(tester, find.byKey(PmScheduleFormDialog.meterKey));
    await tapIn(tester, find.textContaining('Running hours (RUN-HRS)').last);
    await tester.enterText(find.byKey(PmScheduleFormDialog.intervalMeterKey), '500');
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(PmScheduleFormDialog.submitKey));

    expect(find.byType(PmScheduleFormDialog), findsNothing);
    expect(wire.pmSchedulePosts.length, 1);
    final sent = wire.pmSchedulePosts.single;
    expect(sent['assetMeterId'], '5');
    expect(sent['intervalMeter'], 500);
    expect(sent['intervalDays'], isNull);
  });

  testWidgets('a reading can be recorded while working a Work order task that names a meter',
      (tester) async {
    final wire = wireWith(
      workOrders: {
        '1': [workOrderJson('101', 'WO-101', 'Belt is slipping')],
      },
      workOrderTasks: {
        '101': [
          workOrderTaskJson(
            't1',
            1,
            'Record vibration',
            assetMeterId: '5',
            meterName: 'Vibration',
          ),
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
    await tester.pumpAndSettle();

    expect(find.byType(WorkOrderDetailScreen), findsOneWidget);
    expect(find.text('Records Vibration'), findsOneWidget);

    await tapIn(tester, find.byKey(WorkOrderDetailScreen.recordReadingKey('t1')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(TaskReadingDialog.readingKey), '4.2');
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(TaskReadingDialog.submitKey));

    expect(find.byType(TaskReadingDialog), findsNothing);
    expect(wire.taskReadingPosts.length, 1);
    final (workOrderId, taskId, body) = wire.taskReadingPosts.single;
    expect(workOrderId, '101');
    expect(taskId, 't1');
    expect(body['reading'], 4.2);
    expect(find.text('Reading 4.2'), findsOneWidget);
  });
}
