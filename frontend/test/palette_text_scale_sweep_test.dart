/// The palette × text-scale sweep: every Screen in the client, at three
/// windows, in both palettes, at 100% and 200% text (issue #385, S-FIN).
///
/// **What this file is for.** Each slice of the design programme proves its own
/// Screens in the light palette at a text scale of 1 and 2. The combination that
/// shipped two defects (#379, #381) — the *dark* palette with *twice* the text in
/// a narrow window — is nobody's per-Screen job, so this file is that sweep, run
/// once over the whole client: 68 Screens × 3 windows × 2 palettes × 2 text
/// scales, driven off one table.
///
/// **What it measures per combination**, so a failure names a real defect rather
/// than "it rendered":
///
/// - nothing throws: a `RenderFlex` overflow, an unbounded constraint or a
///   failed assertion surfaces here before anything else;
/// - no text is clipped without a way to read it: a paragraph that had to
///   ellipsize (or that is taller than the box it was given) must be disclosed
///   through a `Tooltip`, which is what `DisclosingText` does — an undisclosed
///   clip is a number the reader cannot get at any size;
/// - the header's actions are still offered: the controls in the page header
///   are compared with the same window at 100% text in the light palette at
///   *every* combination, so an action that only disappears at twice the text,
///   or only in the dark palette, fails here;
/// - the rest of the page's controls are compared across palettes only: the
///   set of controls the page renders at 100% text in the light palette must
///   survive the same window in the dark palette. Twice the text is
///   deliberately not compared this way, because it legitimately changes a
///   register's shape — a table row's keyed menu button becomes a card's tap —
///   so a whole-set comparison across the text scale would fail on a design
///   that is working;
/// - the page's left edge has not moved: every paragraph in the page frame is at
///   least as far right as it was at the reference combination, and the header's
///   own inset is identical;
/// - the header's actions are still reachable: each one lies inside the window
///   and is at least the 44px target the design language asks for.
///
/// **Two kinds of Screen.** A page is pumped through the real router with the
/// wire faked (`harness.dart`'s `pumpApp`), exactly as every other test in this
/// suite does — a Screen mounted in isolation would be a third test seam
/// (AGENTS.md §5). The four platform states that no route reaches on its own
/// (session error, and the two whose guard is an Account's own status) are
/// pumped the way `platform_states_geometry_test.dart` already pumps them: a
/// small `MaterialApp` over the Screen, because there is no route to reach them
/// by and no request of their own to fake.
///
/// **The dark palette is chosen the way a browser chooses it.** `ThemeModeCubit`
/// starts at `ThemeMode.system`, so `platformBrightnessTestValue` is the input
/// the app itself reads — the same mechanism `route_title_test.dart` and
/// `floor_training_test.dart` already use, rather than reaching into the cubit.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/platform/destinations.dart';
import 'package:lean_platform/platform/session_error_screen.dart';
import 'package:lean_platform/platform/shell.dart';
import 'package:lean_platform/theme.dart';
import 'package:lean_platform/widgets/app_page_frame.dart';
import 'package:lean_platform/widgets/empty_state.dart';
import 'package:lean_platform/widgets/failure_state.dart';
import 'package:lean_platform/widgets/skeleton_list.dart';
import 'package:lean_platform/widgets/app_page_header.dart';

import 'harness.dart';

/// Whether findings are collected for a report instead of failing the test.
///
/// Off in the committed run: a finding fails the Screen's own test, with the
/// combination and the text in the reason. `--dart-define=SWEEP_PROBE=true`
/// turns it into one aggregate report (`probe report` in this file), which is
/// how the sweep's own table of what each Screen answered with was produced:
///
/// ```
/// ./scripts/flutter-ci.sh test/palette_text_scale_sweep_test.dart \
///   --dart-define=SWEEP_PROBE=true
/// ```
const bool _probe = bool.fromEnvironment('SWEEP_PROBE');

/// The findings a probe run gathers, reported by the last test in the file.
final List<String> _probeFindings = [];

/// What the probe measured, so a green sweep can be shown not to be vacuous.
final List<String> _probeTelemetry = [];

/// The three windows the card names, in logical pixels.
const List<(double, double)> _windows = [(700, 1200), (900, 1200), (1280, 900)];

/// How a Screen's left edge is judged.
enum _Layout {
  /// A page: an `AppPageFrame` whose own inset must not move.
  page,

  /// A centred state: one bounded card, centred on the window.
  centred,

  /// The floor surface: full-bleed, no page frame and no centred card.
  full,
}

class _Screen {
  const _Screen(
    this.name,
    this.file, {
    this.route,
    this.built,
    this.gateway,
    this.layout = _Layout.page,
  });

  /// The Screen class's own name, which is also the failure's own headline.
  final String name;

  /// Its file under `lib/`, for the coverage audit.
  final String file;

  /// Where the router reaches it, for a Screen reached by an address.
  final String? route;

  /// Builds the Screen directly, for the four no address reaches.
  final Widget Function()? built;

  /// Overrides the signed-in Account, for the states a guard decides.
  final FakeAuthGateway Function()? gateway;

  final _Layout layout;
}

/// One wire for every Screen that reads one: each finds the collection it asks
/// for, so what is measured is a rendered page rather than a loading
/// placeholder. A Screen whose own fixture is not here still renders (its empty
/// or failed state is laid out, and must hold too); the eight goldens pick the
/// content-rich ones.
/// The roles editor's two reads (issue #492, ADR-0061): the catalogue and a
/// couple of groups, so the sweep judges a populated editor rather than its
/// empty state — the rows carry chips and a code tail, which is what a text
/// scale and a dark palette break first.
List<Map<String, dynamic>> _sweepPermissions() => [
      permissionJson('PPL_DIRECTORY_DISPLAY', module: 'People', label: 'Directory'),
      permissionJson('MTN_WORK_ORDERS_DISPLAY', label: 'Work orders'),
    ];

List<Map<String, dynamic>> _sweepRoles() => [
      appRoleJson('1', 'ROLE_STANDARD',
          name: 'Standard',
          isDefault: true,
          permissionCodes: ['PPL_DIRECTORY_DISPLAY'],
          holderCount: 12),
      appRoleJson('2', 'ROLE_SUPERVISOR',
          name: 'Supervisor',
          legacyRole: 'supervisor',
          permissionCodes: ['PPL_DIRECTORY_DISPLAY', 'MTN_WORK_ORDERS_DISPLAY'],
          holderCount: 3),
    ];

FakeWire _wire() => FakeWire(
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      permissions: _sweepPermissions(),
      roles: _sweepRoles(),
      orgUnits: {
        null: [orgUnitJson('10', 'Assembly')],
        '10': [orgUnitJson('11', 'Line 1', parentId: '10', unitType: 'line')],
      },
      assets: {
        '1': [assetJson('1', 'PRESS-1', 'Press 1')],
      },
      workOrders: {
        '1': [workOrderJson('101', 'WO-101', 'Belt is slipping', assigneeName: 'Jane Doe')],
      },
      workOrderTasks: {
        '101': [
          workOrderTaskJson('t1', 1, 'Isolate the press', status: 'done'),
          workOrderTaskJson('t2', 2, 'Record vibration',
              assetMeterId: '5', meterName: 'Vibration', status: 'pending'),
        ],
      },
      workOrderCosts: {
        '101': workOrderCostJson(
          labourHours: 3,
          overtimeHours: 1,
          labourByActivity: [labourActivityJson('work', 3, overtimeHours: 1)],
          parts: [workOrderPartJson('p1', quantity: 2, totalCost: 40)],
          partsCost: 40,
        ),
      },
      parts: [partJson('1', 'PART-1', 'Bearing')],
      stock: {
        '1': [stockLevelJson('1', 'PART-1', 'Bearing', 12)],
      },
      // The Tier board's own read, with all five pillars, so the golden of "a
      // board" shows a populated board rather than an empty one.
      board: {
        'site': {'id': '1', 'name': 'Ho Chi Minh', 'timezone': 'Asia/Ho_Chi_Minh'},
        'orgUnit': null,
        'period': {'type': 'month', 'start': '2026-05-01', 'end': '2026-05-31'},
        'pillars': [
          boardPillarJson('S', 'Safety', sortOrder: 1, kpis: const []),
          boardPillarJson('Q', 'Quality', sortOrder: 2, kpis: const []),
          boardPillarJson('D', 'Delivery', sortOrder: 3, kpis: [
            boardKpiJson('MNT_MTBF', 'Mean time between failures',
                unit: 'hours', status: 'green', value: 42, targetValue: 40),
            boardKpiJson('MNT_MTTR', 'Mean time to repair',
                unit: 'hours', status: 'amber', value: 3.4, targetValue: 2.5),
          ]),
          boardPillarJson('C', 'Cost', sortOrder: 4, kpis: const []),
          boardPillarJson('P', 'People', sortOrder: 5, kpis: const []),
        ],
      },
      storeRows: {'1': storeJson('1', 'HCM-STORE', 'Main store')},
      stores: {
        '1': [storeJson('1', 'HCM-STORE', 'Main store')],
      },
      employees: [employeeJson('7', 'E-7', 'Alice Nguyen')],
      employeeDetails: {'7': employeeJson('7', 'E-7', 'Alice Nguyen')},
      jobRoles: [jobRoleJson('20', 'WELD', 'Welder')],
      costRates: [costRateJson('900')],
      productCosts: [productCostJson('950')],
      skills: [skillJson('30', 'WELD', 'Welding')],
      jobPlans: [jobPlanJson('1', 'JP-1', 'Monthly check')],
      meters: {
        '1': [meterJson('1', 'M-1', 'Hours')],
      },
      downtime: {
        '1': [downtimeJson('1', description: 'Guard loose')],
      },
      downtimeReasons: [downtimeReasonJson('1', 'MECH', 'Mechanical')],
      pmSchedules: {
        '1': [pmScheduleJson('1', 'PM-1', 'Monthly check')],
      },
      skillCoverage: {
        '10': [skillCoverageEntryJson('10', 'Line 1', '30', 'WELD', 'Welding')],
      },
      accounts: [accountJson('1', 'admin@b.c', role: Roles.admin)],
      queue: [pendingJson('7', 'new@b.c', DateTime.now())],
      triageRequests: {
        '1': [requestJson('1', 'REQ-1', 'Motor running hot')],
      },
      myRequests: {
        '1': [requestJson('2', 'REQ-2', 'Guard is loose')],
      },
      actions: {
        '1': [actionJson('501', 'AC-HCM-2026-00001', 'Guard keeps working loose')],
      },
      actionDetails: {
        '501': actionJson('501', 'AC-HCM-2026-00001', 'Guard keeps working loose'),
      },
      kpis: [_kpi],
      kpiTargets: {
        1: kpiTargetsJson(
          _kpi,
          current: [kpiCurrentTargetJson('Daily', 85)],
          history: [kpiHistoryEntryJson(1, 'Daily', '2026-01-01', 85)],
        ),
      },
      kpiReviewRows: [kpiReviewRowJson(1, 'Overall equipment effectiveness', unit: '%', target: 85)],
      products: [productJson('40', 'PRD-1', 'Gearbox')],
      defectCodes: [defectCodeJson('41', 'DIM-OOT', 'Out of tolerance')],
      customers: [customerJson('60', 'CUST-1', 'Acme Bearings')],
      suppliers: [supplierJson('50', 'SUP-1', 'Northwind Fasteners')],
      supplierNcrs: {
        '1': [supplierNcrJson('80', 'SN-2026-00001', responseDueDate: '2099-01-01')],
      },
      nonconformances: {
        '1': [nonconformanceJson('701', 'NC-2026-00001')],
      },
      safetyIncidents: {
        '1': [safetyIncidentJson('901', 'SI-HCM-2026-00001')],
      },
      safetyObservations: {
        '1': [safetyObservationJson('701')],
      },
      injuryTypes: [injuryTypeJson('61', 'FRA', 'Fracture')],
      bodyParts: [bodyPartJson('71', 'HAND', 'Hand')],
      complaints: {
        '1': [customerComplaintJson('70', 'CC-2026-00001', responseDueDate: '2099-01-01')],
      },
      capas: {
        '801': capaJson('801', 'CA-HCM-2026-00001', 'The guard keeps working loose',
            orgUnitId: '10', orgUnitName: 'Assembly'),
      },
      attendanceToConfirm: [attendanceToConfirmEntryJson('501')],
      attendanceSheet: attendanceSheetJson('900', '501'),
      attendanceRecords: [attendanceRecordJson('1000', '7', 'Alice Nguyen')],
      leaveRequestsMine: [leaveRequestJson('1')],
      trainingRecords: [trainingRecordJson('1')],
      employeeWorkedHours: workedHoursSummaryJson(
        days: [workedHoursDayJson('2026-05-04')],
        scheduledMinutes: 450,
        workedMinutes: 450,
      ),
      sectionAssets: {
        '30': [sectionAssetJson('a1', 'PRESS-1', 'Press 1')],
      },
      sectionDays: {
        '30': sectionDayJson(
          '30',
          shifts: [
            sectionShiftJson('500', exceptions: const ['no_handover']),
            sectionShiftJson('501', handover: _submittedHandover),
          ],
        ),
      },
      handovers: {_submittedHandover['id'] as String: _submittedHandover},
    );

/// The one submitted handover the board's second shift carries.
final Map<String, dynamic> _submittedHandover = shiftHandoverJson(
  'h501',
  orgUnitId: '30',
  shiftInstanceId: '501',
  status: 'submitted',
  authorDisplayName: 'B Team Leader',
  snapshot: const {'oee': 0.82},
  machineLines: [
    {
      'id': 'ml-a1',
      'assetId': 'a1',
      'assetCode': 'PRESS-1',
      'assetName': 'Press 1',
      'state': 'running',
      'walked': false,
    },
  ],
);

/// The one KPI behind the three KPI pages' rows.
final Map<String, dynamic> _kpi =
    kpiCatalogueRowJson(1, 'OEE', 'Overall equipment effectiveness', unit: '%');

/// Every Screen in `lib/`, once, with the window it is reached by.
final List<_Screen> _screens = [
  // The 50 pages the router reaches by an address.
  const _Screen('HomeScreen', 'lib/home_screen.dart', route: '/'),
  const _Screen('DirectoryScreen', 'lib/people/directory_screen.dart', route: '/directory'),
  const _Screen('JobRolesScreen', 'lib/people/job_roles_screen.dart', route: '/job-roles'),
  const _Screen('SkillsScreen', 'lib/people/skills_screen.dart', route: '/skills'),
  const _Screen('CostRatesScreen', 'lib/people/cost_rates_screen.dart', route: '/cost-rates'),
  const _Screen('ProductCostsScreen', 'lib/people/product_costs_screen.dart',
      route: '/product-costs'),
  const _Screen('OrgUnitsScreen', 'lib/people/org_units_screen.dart', route: '/org-units'),
  const _Screen('AssetsScreen', 'lib/maintenance/assets_screen.dart', route: '/assets'),
  const _Screen('PartsScreen', 'lib/maintenance/parts_screen.dart', route: '/parts'),
  const _Screen('StoresScreen', 'lib/maintenance/stores_screen.dart', route: '/stores'),
  const _Screen('WorkOrdersScreen', 'lib/maintenance/work_orders_screen.dart',
      route: '/work-orders'),
  const _Screen('MyRequestsScreen', 'lib/maintenance/my_requests_screen.dart',
      route: '/my-requests'),
  const _Screen('RequestsScreen', 'lib/maintenance/requests_screen.dart', route: '/requests'),
  const _Screen('DowntimeScreen', 'lib/maintenance/downtime_screen.dart', route: '/downtime'),
  const _Screen('PmSchedulesScreen', 'lib/maintenance/pm_schedules_screen.dart',
      route: '/pm-schedules'),
  const _Screen('MetersScreen', 'lib/maintenance/meters_screen.dart', route: '/meters'),
  const _Screen('JobPlansScreen', 'lib/maintenance/job_plans_screen.dart', route: '/job-plans'),
  const _Screen('AccountsScreen', 'lib/people/accounts_screen.dart', route: '/accounts'),
  // What an Account may do (issue #492, ADR-0061): the roles editor. In the
  // sweep because it is a Screen with its own address, and because its rows
  // carry chips and a code tail at the far end — the two things a text scale
  // and a dark palette break first.
  const _Screen('RolesScreen', 'lib/people/roles_screen.dart', route: '/roles'),
  const _Screen('ApprovalQueueScreen', 'lib/people/approval_queue_screen.dart',
      route: '/approvals'),
  const _Screen('ActionsScreen', 'lib/actions/actions_screen.dart', route: '/actions'),
  const _Screen('CapasScreen', 'lib/actions/capas_screen.dart', route: '/actions/capas'),
  const _Screen('TierBoardScreen', 'lib/maintenance/tier_board_screen.dart', route: '/tier-board'),
  const _Screen('SkillCoverageScreen', 'lib/people/skill_coverage_screen.dart',
      route: '/skill-coverage'),
  const _Screen('SectionBoardScreen', 'lib/production/section_board_screen.dart',
      route: '/production/sections/30/board?date=2026-05-05'),
  const _Screen('ShiftHandoverScreen', 'lib/production/shift_handover_screen.dart',
      route: '/production/sections/30/handover/500?date=2026-05-05'),
  const _Screen('KpiCatalogueScreen', 'lib/kpi/kpi_catalogue_screen.dart', route: '/kpi'),
  const _Screen('KpiReviewScreen', 'lib/kpi/kpi_review_screen.dart', route: '/kpi/review'),
  const _Screen('KpiTargetsScreen', 'lib/kpi/kpi_targets_screen.dart', route: '/kpi/1/targets'),
  const _Screen('ProductsScreen', 'lib/quality/products_screen.dart', route: '/products'),
  const _Screen('DefectCodesScreen', 'lib/quality/defect_codes_screen.dart',
      route: '/defect-codes'),
  const _Screen('NonconformancesScreen', 'lib/quality/nonconformances_screen.dart',
      route: '/non-conformances'),
  const _Screen('NonconformanceDetailScreen', 'lib/quality/nonconformance_detail_screen.dart',
      route: '/non-conformances/701'),
  const _Screen('CustomersScreen', 'lib/quality/customers_screen.dart', route: '/customers'),
  const _Screen('ComplaintsScreen', 'lib/quality/complaints_screen.dart', route: '/complaints'),
  const _Screen('ComplaintDetailScreen', 'lib/quality/complaint_detail_screen.dart',
      route: '/complaints/70'),
  const _Screen('SuppliersScreen', 'lib/quality/suppliers_screen.dart', route: '/suppliers'),
  const _Screen('SupplierNcrsScreen', 'lib/quality/supplier_ncrs_screen.dart',
      route: '/supplier-ncrs'),
  const _Screen('SupplierNcrDetailScreen', 'lib/quality/supplier_ncr_detail_screen.dart',
      route: '/supplier-ncrs/80'),
  const _Screen('IncidentsScreen', 'lib/safety/incidents_screen.dart', route: '/safety/incidents'),
  const _Screen('IncidentDetailScreen', 'lib/safety/incident_detail_screen.dart',
      route: '/safety/incidents/901'),
  const _Screen('ObservationsScreen', 'lib/safety/observations_screen.dart',
      route: '/safety/observations'),
  const _Screen('ObservationDetailScreen', 'lib/safety/observation_detail_screen.dart',
      route: '/safety/observations/701'),
  const _Screen('InjuryTypesScreen', 'lib/safety/injury_types_screen.dart',
      route: '/safety/injury-types'),
  const _Screen('BodyPartsScreen', 'lib/safety/body_parts_screen.dart', route: '/safety/body-parts'),
  const _Screen('ActionDetailScreen', 'lib/actions/action_detail_screen.dart',
      route: '/actions/501'),
  const _Screen('CapaDetailScreen', 'lib/actions/capa_detail_screen.dart',
      route: '/actions/capas/801'),
  const _Screen('CapaReportScreen', 'lib/actions/capa_report_screen.dart',
      route: '/actions/capas/801/report'),
  const _Screen('AttendanceToConfirmScreen', 'lib/people/attendance_to_confirm_screen.dart',
      route: '/attendance/to-confirm'),
  const _Screen('AttendancePickerScreen', 'lib/people/attendance_picker_screen.dart',
      route: '/attendance'),
  const _Screen('AttendanceSheetScreen', 'lib/people/attendance_sheet_screen.dart',
      route: '/attendance/501'),
  const _Screen('EmployeeDetailScreen', 'lib/people/employee_detail_screen.dart',
      route: '/directory/7'),
  const _Screen('WorkedHoursScreen', 'lib/people/worked_hours_screen.dart',
      route: '/directory/7/work-hours'),
  const _Screen('LeaveRequestsScreen', 'lib/people/leave_requests_screen.dart',
      route: '/leave-requests'),
  const _Screen('TrainingScreen', 'lib/people/training_screen.dart', route: '/training'),
  const _Screen('TrainingDetailScreen', 'lib/people/training_detail_screen.dart',
      route: '/training/1'),
  const _Screen('TrainingFormScreen', 'lib/people/training_form_screen.dart',
      route: '/training/1/form'),
  const _Screen('TrainingToConfirmScreen', 'lib/people/training_to_confirm_screen.dart',
      route: '/training/to-confirm'),
  const _Screen('MySignatureScreen', 'lib/people/my_signature_screen.dart',
      route: '/me/signature'),
  const _Screen('WorkOrderDetailScreen', 'lib/maintenance/work_order_detail_screen.dart',
      route: '/work-orders/101'),
  const _Screen('StoreStockScreen', 'lib/maintenance/store_stock_screen.dart',
      route: '/stores/1'),
  const _Screen('SlideShowScreen', 'lib/quality/slide_show_screen.dart', route: '/slide-show'),
  const _Screen('FloorScreen', 'lib/maintenance/floor_screen.dart',
      route: '/floor', layout: _Layout.full),
  // The front door, the two states a guard decides, and the three platform
  // states — the ones no page frame holds, and therefore the ones whose own
  // composition is what has to hold at twice the text.
  const _Screen('SignInScreen', 'lib/auth/sign_in_screen.dart',
      // Two panels at its own breakpoint — the form card is centred in the
      // right-hand panel, not in the window — so this one is measured like the
      // floor surface rather than like a centred state.
      route: '/sign-in', gateway: _signedOut, layout: _Layout.full),
  const _Screen('AwaitingApprovalScreen', 'lib/auth/awaiting_approval_screen.dart',
      route: '/awaiting-approval', gateway: _pending, layout: _Layout.centred),
  const _Screen('ChangePasswordScreen', 'lib/platform/change_password_screen.dart',
      route: '/change-password', layout: _Layout.centred),
  const _Screen('AccessDeniedScreen', 'lib/platform/access_denied_screen.dart',
      route: '/approvals', gateway: _operator, layout: _Layout.centred),
  const _Screen('NotFoundScreen', 'lib/platform/not_found_screen.dart',
      route: '/no-such-address', layout: _Layout.centred),
  _Screen('SessionErrorScreen', 'lib/platform/session_error_screen.dart',
      built: () => const SessionErrorScreen(message: 'the request timed out'),
      layout: _Layout.centred),
];

FakeAuthGateway _signedOut() => FakeAuthGateway();
FakeAuthGateway _pending() => FakeAuthGateway(accessToken: 'a-token');
FakeAuthGateway _operator() => FakeAuthGateway(accessToken: 'a-token');

/// The wire the four guard-decided states need: a pending Account, or an
/// operator with nothing granted, so the guard draws the state rather than the
/// page behind it.
FakeWire _stateWire(_Screen screen) {
  if (screen.name == 'AccessDeniedScreen') {
    return FakeWire(
      role: Roles.operator,
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [orgUnitJson('10', 'Line 1')],
      },
    );
  }
  // The roles editor is behind `ADM_ROLES_DISPLAY` on its address (ADR-0061),
  // and the shared wire's `/me` carries no codes at all — so this Screen alone
  // gets the one code that opens it, or the sweep would be judging the
  // AccessDenied Screen that stands in its place.
  if (screen.name == 'RolesScreen') {
    return FakeWire(
      mePermissions: const ['ADM_ROLES_DISPLAY'],
      permissions: _sweepPermissions(),
      roles: _sweepRoles(),
    );
  }
  return _wire();
}

/// Mounts one Screen, once — the app is pumped a single time per Screen and then
/// *driven* through the twelve combinations, rather than rebuilt for each.
///
/// **Why driving beats re-pumping.** A `PlatformApp` per combination is 816
/// apps across the table, and measured in the pinned image they do not come back:
/// the suite's resident memory climbed to 3.8 GiB of its 4 GiB cap and the
/// container was killed mid-file (2026-11-04). Changing the *device* instead —
/// the window, the text scale and the browser's palette — is also the more
/// faithful model of what this sweep claims: a person resizes a window and
/// changes their text size, the app does not restart.
Future<void> _mount(WidgetTester tester, _Screen screen) async {
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);

  if (screen.built != null) {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        darkTheme: buildAppTheme(Brightness.dark),
        themeMode: ThemeMode.system,
        home: screen.built!(),
      ),
    );
  } else {
    await pumpApp(
      tester,
      gateway: screen.gateway?.call() ?? FakeAuthGateway(accessToken: 'a-token'),
      client: _stateWire(screen).client,
      initialLocation: screen.route,
      // Never `pumpAndSettle`: a Screen with a progress indicator on it, or the
      // slide show's own ten-second clock, never settles.
      settle: false,
    );
  }
  await _settle(tester);
}

/// Puts the mounted Screen on a different device: [width] × [height] logical
/// pixels, in the light or dark palette, at [textScale].
Future<void> _apply(
  WidgetTester tester, {
  required double width,
  required double height,
  required bool dark,
  required double textScale,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  tester.platformDispatcher.platformBrightnessTestValue =
      dark ? Brightness.dark : Brightness.light;
  await _settle(tester);
}

/// Lets the resize, the text scale and the palette land, and any route
/// transition finish, without ever waiting on an animation that does not stop.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// A paragraph that had to clip, and was not disclosed in a `Tooltip`.
///
/// The Shell's sidebar is included: it is chrome rather than a Screen, so a clip
/// found inside it belongs to `PlatformShell` and not to the page under it, but
/// leaving the chrome out is exactly how the sidebar's one-line Destination
/// labels survived a sweep that otherwise proved every Screen. They wrap now
/// (issue #385, #445), so this check holds that fix in place too.
List<String> _undisclosedClips() {
  final out = <String>[];
  for (final element in find.byType(RichText).evaluate()) {
    final object = element.renderObject;
    if (object is! RenderParagraph) continue;
    if (!_clips(object)) continue;
    if (_insideTooltip(element)) continue;
    out.add('${object.text.toPlainText()} '
        '[maxLines=${object.maxLines} didExceed=${object.didExceedMaxLines} '
        'size=${object.size.width}x${object.size.height} '
        'intrinsic=${object.getMaxIntrinsicHeight(object.size.width)}]');
  }
  return out;
}

bool _insideSidebar(Element element) {
  var found = false;
  element.visitAncestorElements((ancestor) {
    if (ancestor.widget.key == PlatformShell.sidebarKey) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

bool _clips(RenderParagraph paragraph) {
  if (paragraph.didExceedMaxLines) return true;
  // Laid out shorter than the text needs at the width it was given: clipped
  // vertically rather than ellipsized.
  final wanted = paragraph.getMaxIntrinsicHeight(paragraph.size.width);
  return paragraph.size.height + 0.5 < wanted;
}

bool _insideTooltip(Element element) {
  var found = false;
  element.visitAncestorElements((ancestor) {
    if (ancestor.widget is Tooltip) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

/// The controls a reader can act on, keyed so two pumps can be compared.
Set<String> _actionIds() {
  final out = <String>{};
  final finder = find.byWidgetPredicate(
    (widget) =>
        widget is ButtonStyleButton ||
        widget is IconButton ||
        widget is FloatingActionButton ||
        widget is PopupMenuButton ||
        (widget is InkWell && widget.onTap != null) ||
        (widget is Checkbox && widget.onChanged != null) ||
        (widget is Switch && widget.onChanged != null) ||
        (widget is DropdownButton && widget.onChanged != null),
  );
  for (final element in finder.evaluate()) {
    if (_insideSidebar(element)) continue;
    final id = _identity(element);
    if (id != null) out.add(id);
  }
  return out;
}

/// The header's own controls, by the same identity — the actions a page keeps
/// whatever shape its rows take.
Set<String> _headerActionIds() {
  final out = <String>{};
  final box = find.byKey(AppPageHeader.actionsKey);
  if (box.evaluate().isEmpty) return out;
  final controls = find.descendant(
    of: box,
    matching: find.byWidgetPredicate((w) => w is ButtonStyleButton || w is IconButton),
  );
  for (final element in controls.evaluate()) {
    final id = _identity(element);
    if (id != null) out.add(id);
  }
  return out;
}

String? _identity(Element element) {
  final widget = element.widget;
  final key = widget.key;
  if (key != null) return 'key:$key';
  if (widget is IconButton && widget.tooltip != null) return 'tip:${widget.tooltip}';
  if (widget is PopupMenuButton && widget.tooltip != null) return 'tip:${widget.tooltip}';
  final label = _firstText(element);
  if (label != null && label.isNotEmpty) return 'label:$label';
  return null;
}

String? _firstText(Element element) {
  String? found;
  void walk(Element current) {
    if (found != null) return;
    final widget = current.widget;
    if (widget is Text) {
      final data = widget.data;
      if (data != null) {
        found = data;
        return;
      }
      final span = widget.textSpan;
      if (span != null) {
        found = span.toPlainText();
        return;
      }
    }
    current.visitChildElements(walk);
  }

  element.visitChildElements(walk);
  return found;
}

/// The left-most paragraph inside the page frame: where it starts, and what it
/// says, so a moved edge names the text that moved.
({double dx, String text})? _leftMostParagraph() {
  final paragraphs =
      find.descendant(of: find.byType(AppPageFrame), matching: find.byType(RichText));
  ({double dx, String text})? left;
  for (final element in paragraphs.evaluate()) {
    if (_insideSidebar(element)) continue;
    final object = element.renderObject;
    if (object is! RenderBox || !object.hasSize) continue;
    final dx = object.localToGlobal(Offset.zero).dx;
    if (left == null || dx < left.dx) {
      left = (dx: dx, text: object is RenderParagraph ? object.text.toPlainText() : '');
    }
  }
  return left;
}

/// The box the Screen is drawn in: the window less the Shell's sidebar, when the
/// Screen is inside the Shell. A centred state is centred in that, not in the
/// window.
Rect _surface(WidgetTester tester, double width, double height) {
  final sidebar = find.byKey(PlatformShell.sidebarKey);
  if (sidebar.evaluate().isEmpty) return Rect.fromLTWH(0, 0, width, height);
  final box = tester.getRect(sidebar.first);
  return Rect.fromLTWH(box.right, 0, width - box.right, height);
}

/// The first card outside the Shell's sidebar — the block a centred state is
/// drawn in.

void main() {
  setUpAll(loadAppFonts);

  test('every Screen in lib/ is in the sweep, and nothing stale is', () {
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .map((file) => file.path)
        .where((path) => path.endsWith('_screen.dart'))
        .toList()
      ..sort();
    final tabled = {for (final screen in _screens) screen.file};
    expect(
      [for (final path in files) if (!tabled.contains(path)) path],
      isEmpty,
      reason: 'a Screen that is not in the sweep is a Screen no one proved in the dark palette',
    );
    expect(
      [for (final path in tabled) if (!files.contains(path)) path],
      isEmpty,
      reason: 'a stale entry hides a file that no longer exists',
    );
    expect(files.length, _screens.length);
  });

  for (final screen in _screens) {
    testWidgets('${screen.name}: holds in both palettes at both text sizes', (tester) async {
      final findings = <String>[];
      final telemetry = <String>[];

      await _mount(tester, screen);

      for (final (width, height) in _windows) {
        _Measured? reference;
        for (final (dark, textScale) in const [
          (false, 1.0),
          (false, 2.0),
          (true, 1.0),
          (true, 2.0),
        ]) {
          await _apply(tester,
              width: width, height: height, dark: dark, textScale: textScale);
          final measured = _measure(tester, screen, width: width, height: height);
          final label = '$width ${dark ? 'dark' : 'light'} $textScale';
          findings.addAll(measured.findings.map((f) => '$label: $f'));

          // The first combination of each window is its reference: the light
          // palette at ordinary text.
          if (textScale == 1.0 && !dark) {
            reference = measured;
            telemetry.add('$width ${measured.paragraphs}p ${measured.actions.length}a '
                '${measured.inset == null ? "no-inset" : "inset=${measured.inset}"} '
                'state=${measured.state}');
            continue;
          }
          final base = reference!;

          // The header's actions must survive every combination: they are the
          // ones a page offers whatever shape its rows take.
          final lostHeader = base.headerActions.difference(measured.headerActions);
          if (lostHeader.isNotEmpty) {
            findings.add('$label: header actions gone: ${lostHeader.join(', ')}');
          }
          // The whole page's actions are compared palette-only: twice the text
          // legitimately changes a register's shape, and with it which control a
          // row offers (a table row's keyed menu button becomes a card's tap),
          // so a text-scale comparison of every key would fail on a design that
          // is working. The palette must change nothing at all.
          if (dark && textScale == 1.0) {
            final lost = base.actions.difference(measured.actions);
            if (lost.isNotEmpty) {
              findings.add('$label: actions gone: ${lost.take(6).join(', ')}');
            }
          }
          if (base.inset != null && measured.inset != null) {
            if ((base.inset! - measured.inset!).abs() > 0.5) {
              findings.add('$label: the left edge moved from ${base.inset} '
                  '(${base.leftmost}) to ${measured.inset} (${measured.leftmost})');
            }
          }
        }
      }

      // Dispose the mounted app inside the test: the next test mounts its own.
      await tester.pumpWidget(const SizedBox.shrink());

      if (_probe) {
        _probeTelemetry.add('${screen.name}: ${telemetry.join(' | ')}');
        if (findings.isNotEmpty) {
          _probeFindings
              .add('${screen.name} (${findings.length}): ${findings.take(10).join(' | ')}');
        }
        return;
      }
      expect(findings, isEmpty, reason: '${screen.name}: ${findings.join('\n')}');
    });
  }

  if (_probe) {
    test('probe report', () {
      fail('TELEMETRY ${_probeTelemetry.length}\n${_probeTelemetry.join('\n')}\n'
          'FINDINGS ${_probeFindings.length}\n${_probeFindings.join('\n')}');
    });
  }

  // A pixel record of the hardest combination this card exists for — the dark
  // palette, twice the text, a 700px window — for one Screen of each shape the
  // programme rebuilt. The sweep above proves the numbers; these prove the
  // drawing, which is the part a rectangle assertion cannot see (a badge tinted
  // wrongly is the right size). Regenerated only in the pinned image:
  // `./scripts/flutter-ci.sh test/palette_text_scale_sweep_test.dart
  // --update-goldens` (see GOLDENS.md).
  for (final golden in _goldens) {
    for (final dark in const [false, true]) {
      testWidgets('golden: ${golden.screen.name} in the ${dark ? 'dark' : 'light'} palette '
          'at twice the text in a 700px window', (tester) async {
        await _mount(tester, golden.screen);
        await _apply(tester, width: 700, height: 1200, dark: dark, textScale: 2);
        await expectLater(
          find.byType(MaterialApp).first,
          matchesGoldenFile('goldens/sweep_${golden.slug}_${dark ? 'dark' : 'light'}.png'),
        );
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}

/// One representative Screen of each shape the design programme rebuilt, for the
/// goldens: a register, a detail, a board, a matrix, a form, Home, the front
/// door and a platform state.
class _Golden {
  const _Golden(this.slug, this.screen);

  final String slug;
  final _Screen screen;
}

final List<_Golden> _goldens = [
  for (final (slug, name) in const [
    ('register', 'WorkOrdersScreen'),
    ('detail', 'WorkOrderDetailScreen'),
    // The Tier board rather than the Section board, deliberately: the Section
    // board draws how far into a shift the reader is from the *real* clock (its
    // `now` is a constructor parameter no route passes), so a golden of it
    // drifts by the minute. The Tier board's period comes from the wire.
    ('board', 'TierBoardScreen'),
    ('matrix', 'KpiCatalogueScreen'),
    ('form', 'TrainingFormScreen'),
    ('home', 'HomeScreen'),
    ('sign_in', 'SignInScreen'),
    ('state', 'NotFoundScreen'),
  ])
    _Golden(slug, _screens.firstWhere((screen) => screen.name == name)),
];

class _Measured {
  _Measured(this.findings, this.actions, this.headerActions, this.inset, this.leftmost,
      this.paragraphs, this.state);

  final List<String> findings;
  final Set<String> actions;
  final Set<String> headerActions;
  final double? inset;
  final String? leftmost;
  final int paragraphs;

  /// What the Screen answered with: its content, or one of the shared states.
  /// Recorded rather than judged, so the sweep's own table says which Screens
  /// proved a rendered page and which proved a state.
  final String state;
}

/// What one combination shows: what threw, what clipped, what the header's
/// actions look like, and where the page's left edge and body sit.
_Measured _measure(
  WidgetTester tester,
  _Screen screen, {
  required double width,
  required double height,
}) {
  final findings = <String>[];

  final exception = tester.takeException();
  if (exception != null) findings.add('threw: $exception');

  for (final text in _undisclosedClips()) {
    findings.add(
        'clipped text with no way to read it: "${text.length > 60 ? text.substring(0, 60) : text}"');
  }

  final surface = _surface(tester, width, height);

  double? inset;
  String? leftmost;
  switch (screen.layout) {
    case _Layout.page:
      final frame = find.byType(AppPageFrame);
      if (frame.evaluate().isEmpty) {
        findings.add('no page frame');
      } else {
        final box = tester.getRect(frame.first);
        if (box.left < surface.left - 0.5 || box.right > surface.right + 0.5) {
          findings.add('the page frame leaves the surface: ${box.left}..${box.right} '
              'of ${surface.left}..${surface.right}');
        }
        final left = _leftMostParagraph();
        if (left != null) {
          // Nothing may start left of the frame it sits in.
          if (left.dx < box.left - 0.5) {
            findings.add('text starts ${box.left - left.dx}px left of the page frame: '
                '"${left.text}"');
          }
        }
        // The header's own title is the page's left edge: it starts at the
        // frame's inset, and that inset is a token, so it must not move with the
        // palette or the text size. A page that writes no `AppPageHeader` (the
        // printed training sheet) falls back to the frame itself, and its
        // paragraphs have already been checked not to spill left of it.
        final title = find.byKey(AppPageHeader.titleKey);
        if (title.evaluate().isNotEmpty) {
          inset = tester.getTopLeft(title.first).dx - box.left;
        } else {
          inset = 0;
        }
        leftmost = left == null ? null : '${left.text}@${left.dx}';
      }
    case _Layout.centred:
      final cards = find.byType(Card).evaluate().where((e) => !_insideSidebar(e)).toList();
      if (cards.isEmpty) {
        findings.add('no bounded card around the state');
      } else {
        final box = tester.getRect(find.byElementPredicate((e) => e == cards.first));
        final centre = (box.left + box.right) / 2;
        final middle = surface.left + surface.width / 2;
        if ((centre - middle).abs() > 1.5) {
          findings.add('the card is not centred: centre $centre, the surface\'s middle is $middle');
        }
        if (box.right > surface.right + 0.5 || box.left < surface.left - 0.5) {
          findings.add('the card leaves the surface: ${box.left}..${box.right} '
              'of ${surface.left}..${surface.right}');
        }
      }
    case _Layout.full:
      break;
  }

  // The header's own actions: inside the surface, and at least a 44px target.
  final headerActions = find.byKey(AppPageHeader.actionsKey);
  if (headerActions.evaluate().isNotEmpty) {
    final controls = find.descendant(
      of: headerActions,
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton || w is IconButton),
    );
    for (final element in controls.evaluate()) {
      final box = element.renderObject as RenderBox;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      if (rect.right > surface.right + 0.5 || rect.left < surface.left - 0.5) {
        findings.add('a header action is outside the surface: ${rect.left}..${rect.right} '
            'of ${surface.left}..${surface.right}');
      }
      if (rect.height < AppTouchTarget.min - 0.5) {
        findings.add('a header action is ${rect.height}px tall, under the 44px floor');
      }
    }
    if (find.descendant(of: headerActions, matching: find.byType(Text)).evaluate().isEmpty &&
        controls.evaluate().isEmpty) {
      findings.add('the header actions box holds no control');
    }
  }

  return _Measured(
    findings,
    _actionIds(),
    _headerActionIds(),
    inset,
    leftmost,
    find.byType(RichText).evaluate().length,
    find.byType(PlatformFailureState).evaluate().isNotEmpty
        ? 'failed'
        : find.byType(PlatformEmptyState).evaluate().isNotEmpty
            ? 'empty'
            : find.byType(SkeletonList).evaluate().isNotEmpty
                ? 'loading'
                : 'content',
  );
}
