/// The maintenance schedule registers' geometry, measured (issue #388): Meters,
/// Job plans, PM schedules and Downtime.
///
/// The same measurements as `maintenance_catalogue_registers_test.dart`, over the
/// four registers that state their own breakpoint or carry a disclosure: Meters
/// and PM schedules state 960 of box because their columns are what made 700
/// clip, Downtime states 900, and Job plans takes the 700 default. A register
/// that measures the box it was handed switches at the window of its own number
/// plus the Shell's 260px rail — 1220 for Meters and PM schedules, 1160 for
/// Downtime, 960 for Job plans — and each was found by pumping a window and
/// checking which side of the edge it fell on.
///
/// The last case proves what the register would otherwise hide: a Job plan's
/// steps and a PM schedule's rules are one press beneath their own row, the row
/// keeps its height, the block appears, and the toggle is a button a screen
/// reader can press. The app's own fonts are loaded first
/// (`setUpAll(loadAppFonts)`), so every height here is the app's.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/maintenance/downtime_screen.dart';
import 'package:lean_platform/maintenance/job_plans_screen.dart';
import 'package:lean_platform/maintenance/meters_screen.dart';
import 'package:lean_platform/maintenance/pm_schedules_screen.dart';
import 'package:lean_platform/maintenance/row_disclosure.dart';
import 'package:lean_platform/platform/destinations.dart';

import 'harness.dart';
import 'register_geometry_support.dart';

/// A supervisor holding a write Grant at Org Unit 10 — the caller the row
/// actions of Meters, PM schedules and Downtime are offered to.
const Map<String, dynamic> _writeGrant = {
  'everywhere': false,
  'grants': [
    {'orgUnitId': '10', 'siteId': '1', 'canWrite': true},
  ],
};

final _meters = RegisterSpec(
  name: 'Meters',
  location: '/meters',
  wire: () => FakeWire(
    role: Roles.admin,
    orgUnitScope: _writeGrant,
    sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
    orgUnits: {
      null: [orgUnitJson('10', 'Assembly')],
    },
    assets: {'1': []},
    meters: {
      '1': [
        meterJson('5', 'RUN-HRS', 'Running hours', accumulatedUse: 900, latestReading: 900),
        meterJson('6', 'CYCLES', 'Cycles', latestReading: 12, accumulatedUse: 1200),
      ],
    },
  ),
  rowKey: MetersScreen.rowKey,
  ids: const ['5', '6'],
  columns: const [
    ('Code', false),
    ('Name', false),
    ('Asset', false),
    ('Type', false),
    ('Unit', false),
    ('Latest reading', true),
    ('Accumulated use', true),
    ('Actions', true),
  ],
  // "Record a reading" (44) plus `Spacing.xs` above and below.
  rowHeights: const {'5': 52, '6': 52},
  cardHeights: const {'5': 156, '6': 156},
  tableFromWindow: 1220,
  primaryKey: MetersScreen.readingKey,
  numericColumn: 5,
);

final _jobPlans = RegisterSpec(
  name: 'Job plans',
  location: '/job-plans',
  wire: () => FakeWire(
    role: Roles.admin,
    sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
    orgUnits: {
      null: [orgUnitJson('10', 'Assembly')],
    },
    assets: {'1': []},
    jobPlans: [
      jobPlanJson('5', 'JP-1', 'Annual service',
          estimatedHours: 4,
          tasks: [jobPlanTaskJson('1', 1, 'Grease the bearings')]),
      jobPlanJson('6', 'JP-2', 'Belt replacement', estimatedHours: 2.5),
    ],
  ),
  rowKey: JobPlansScreen.rowKey,
  ids: const ['5', '6'],
  columns: const [
    ('Plan', false),
    ('Steps', false),
    ('Estimated hours', true),
    ('Shutdown', false),
    ('Actions', true),
  ],
  // The steps toggle (44) plus `Spacing.xs` above and below.
  rowHeights: const {'5': 52, '6': 52},
  // A plan with a description or steps draws more card; a plan without draws
  // less, so the two heights are measured separately.
  cardHeights: const {'5': 202, '6': 178},
  tableFromWindow: 960,
  primaryKey: JobPlansScreen.toggleKey,
  numericColumn: 2,
);

final _pmSchedules = RegisterSpec(
  name: 'PM schedules',
  location: '/pm-schedules',
  wire: () => FakeWire(
    role: Roles.admin,
    orgUnitScope: _writeGrant,
    sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
    orgUnits: {
      null: [orgUnitJson('10', 'Assembly')],
    },
    assets: {'1': []},
    pmSchedules: {
      '1': [
        pmScheduleJson('9', 'PM-1', 'Monthly service', priority: 3, nextDueOn: '2026-11-30'),
        pmScheduleJson('10', 'PM-2', 'Quarterly service', priority: 5, nextDueOn: '2026-12-30'),
      ],
    },
  ),
  rowKey: PmSchedulesScreen.rowKey,
  ids: const ['9', '10'],
  columns: const [
    ('Job plan', false),
    ('Asset', false),
    ('Interval', false),
    ('Priority', true),
    ('Due', false),
    ('Rules', false),
    ('Actions', true),
  ],
  // The rules toggle (44) plus `Spacing.xs` above and below.
  rowHeights: const {'9': 52, '10': 52},
  cardHeights: const {'9': 172, '10': 172},
  tableFromWindow: 1220,
  primaryKey: PmSchedulesScreen.toggleKey,
  numericColumn: 3,
  // A priority is 1–5 by the database's own check, so every value is one digit
  // and the digit-count discriminator is unavailable here; the column's right
  // edge is carried by the band label's own edge above.
  numericDigitsVary: false,
);

final _downtime = RegisterSpec(
  name: 'Downtime',
  location: '/downtime',
  wire: () => FakeWire(
    role: Roles.admin,
    orgUnitScope: _writeGrant,
    sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
    orgUnits: {
      null: [orgUnitJson('10', 'Assembly')],
    },
    assets: {'1': []},
    downtime: {
      '1': [
        downtimeJson('11', assetCode: 'PRESS-1', assetName: 'Press 1'),
        downtimeJson('12', assetCode: 'CONV-2', assetName: 'Infeed conveyor'),
      ],
    },
  ),
  rowKey: DowntimeScreen.rowKey,
  ids: const ['11', '12'],
  columns: const [
    ('Asset', false),
    ('Status', false),
    ('Started', false),
    ('Reason', false),
    ('Reported by', false),
    ('Details', false),
    ('Actions', true),
  ],
  // Close (44) beside the kebab, plus `Spacing.xs` above and below.
  rowHeights: const {'11': 52, '12': 52},
  cardHeights: const {'11': 156, '12': 156},
  tableFromWindow: 1160,
  primaryKey: DowntimeScreen.closeKey,
);

void main() {
  setUpAll(loadAppFonts);

  registerGeometryTests(_meters);
  registerGeometryTests(_jobPlans);
  registerGeometryTests(_pmSchedules);
  registerGeometryTests(_downtime);

  // Inside the register the framework merges the toggle's node into its row's, so
  // the label is not a node of its own to find here — these assert the `Semantics`
  // widget's own properties, and `row_disclosure_test.dart` proves the merged tree
  // a screen reader is handed.
  Semantics toggleLabelled(WidgetTester tester, String label) => tester.widget<Semantics>(
      find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.label == label));

  testWidgets('a Job plan\'s steps are one press beneath their row', (tester) async {
    await pumpAt(tester, _jobPlans, width: 1280);

    final planRow = find.byKey(JobPlansScreen.rowKey('5'));
    final planDisclosure = find.ancestor(of: planRow, matching: find.byType(RowDisclosure));
    expect(find.text('Grease the bearings'), findsNothing, reason: 'collapsed by default');
    final closedHeight = tester.getSize(planDisclosure).height;
    expect(tester.getSize(planRow).height, 52);
    expect(find.byTooltip('Show 1 step'), findsOneWidget);
    final closedToggle = toggleLabelled(tester, 'Show 1 step');
    expect(closedToggle.properties.button, isTrue, reason: 'a screen reader sees a button');
    expect(closedToggle.properties.onTap, isNotNull, reason: 'and can press it');
    expect(closedToggle.properties.expanded, isFalse);

    await tester.tap(find.byKey(JobPlansScreen.stepsKey('5')));
    await tester.pumpAndSettle();
    expect(find.text('Grease the bearings'), findsOneWidget);
    expect(tester.getSize(planDisclosure).height, greaterThan(closedHeight),
        reason: 'the block is under the row, so the disclosure grows');
    expect(tester.getSize(planRow).height, 52, reason: 'the row keeps its height');
    expect(find.byTooltip('Hide 1 step'), findsOneWidget);
    final openToggle = toggleLabelled(tester, 'Hide 1 step');
    expect(openToggle.properties.expanded, isTrue, reason: 'the label follows the state');
    expect(openToggle.properties.onTap, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a PM schedule\'s rules are one press beneath their row', (tester) async {
    await pumpAt(tester, _pmSchedules, width: 1280);

    final scheduleRow = find.byKey(PmSchedulesScreen.rowKey('9'));
    final scheduleDisclosure = find.ancestor(of: scheduleRow, matching: find.byType(RowDisclosure));
    expect(find.text('Raised 7 days early'), findsNothing, reason: 'collapsed by default');
    final scheduleClosed = tester.getSize(scheduleDisclosure).height;

    await tester.tap(find.byKey(PmSchedulesScreen.rulesKey('9')));
    await tester.pumpAndSettle();
    expect(find.text('Raised 7 days early'), findsOneWidget);
    expect(find.textContaining('Rolls from'), findsOneWidget);
    expect(tester.getSize(scheduleDisclosure).height, greaterThan(scheduleClosed));
    expect(tester.getSize(scheduleRow).height, 52, reason: 'the row keeps its height');
    expect(toggleLabelled(tester, 'Hide 2 rules').properties.expanded, isTrue);
    expect(tester.takeException(), isNull);
  });
}
