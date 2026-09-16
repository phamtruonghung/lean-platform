/// Every form picker finds a record instead of scrolling a catalogue (issue
/// #190, ADR-0023).
///
/// Nine dialogs used to offer a whole collection — every Asset at a Site, the
/// parts catalogue, every Employee in the plant — as a
/// `DropdownButtonFormField`, and the eleven pickers behind them are now
/// `AppSearchField`s whose `fetchSuggestions` filters the very list the dialog
/// already read. This file drives all eleven the way a person does, at the
/// client's one seam (AGENTS.md §5): the real Screen and the real dialog over
/// `FakeWire` at the HTTP boundary and `FakeAuthGateway` at the auth boundary,
/// asserting on rendered suggestions, on the field's own displayed text, and on
/// the requests `FakeWire` recorded — never on a Bloc's state.
///
/// One row per picker, four assertions per row:
///
/// 1. typing narrows the suggestions to the matching record and issues **no**
///    request at all — a count of the wire's requests before and after typing,
///    which is ADR-0023's reading half and the reason `fetchSuggestions` here
///    filters a list in memory rather than asking the server;
/// 2. picking a suggestion fills the field with the record's own display string
///    and the submitted body carries its id;
/// 3. a term matching nothing renders the shared no-match state, not an
///    ambiguous empty box;
/// 4. the form's own submit gate still closes while no record is picked — the
///    same assertion each dialog's dropdown-era test made. One picker is
///    deliberately exempt: a Job plan step's required Skill is optional, so
///    what holds there is that the body omits `skillId` while nothing is picked
///    (`_PickerCase.required`).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/maintenance/asset.dart';
import 'package:lean_platform/maintenance/breakdown_report_dialog.dart';
import 'package:lean_platform/maintenance/downtime_screen.dart';
import 'package:lean_platform/maintenance/job_plan.dart';
import 'package:lean_platform/maintenance/job_plan_form_dialog.dart';
import 'package:lean_platform/maintenance/job_plans_screen.dart';
import 'package:lean_platform/maintenance/labour_booking_dialog.dart';
import 'package:lean_platform/maintenance/meter_form_dialog.dart';
import 'package:lean_platform/maintenance/meters_screen.dart';
import 'package:lean_platform/maintenance/my_requests_screen.dart';
import 'package:lean_platform/maintenance/part.dart';
import 'package:lean_platform/maintenance/part_booking_dialog.dart';
import 'package:lean_platform/maintenance/pm_schedule_form_dialog.dart';
import 'package:lean_platform/maintenance/pm_schedules_screen.dart';
import 'package:lean_platform/maintenance/request_form_dialog.dart';
import 'package:lean_platform/maintenance/store.dart';
import 'package:lean_platform/maintenance/work_order_detail_screen.dart';
import 'package:lean_platform/maintenance/work_order_form_dialog.dart';
import 'package:lean_platform/maintenance/work_orders_screen.dart';
import 'package:lean_platform/people/directory_screen.dart';
import 'package:lean_platform/people/employee.dart';
import 'package:lean_platform/people/employee_detail_screen.dart';
import 'package:lean_platform/people/employee_skill_form_dialog.dart';
import 'package:lean_platform/people/skill.dart';
import 'package:lean_platform/platform/destinations.dart';
import 'package:lean_platform/widgets/app_search_field.dart';
import 'package:lean_platform/widgets/empty_state.dart';

import 'harness.dart';

/// A supervisor holding a write Grant at Org Unit 10 — the caller the
/// maintenance Screens under test offer their write affordances to.
const Map<String, dynamic> _writeGrant = {
  'everywhere': false,
  'grants': [
    {'orgUnitId': '10', 'siteId': '1', 'canWrite': true},
  ],
};

/// The wire every case starts from: one Site, the Org Unit under it, and — for
/// the operator case — the read-only scope a Request is raised with.
FakeWire _wire({
  String role = Roles.supervisor,
  Map<String, dynamic>? orgUnitScope = _writeGrant,
  Map<String, List<Map<String, dynamic>>>? assets,
  Map<String, List<Map<String, dynamic>>>? workOrders,
  Map<String, Map<String, dynamic>>? workOrderCosts,
  Map<String, List<Map<String, dynamic>>>? meters,
  Map<String, List<Map<String, dynamic>>>? pmSchedules,
  List<Map<String, dynamic>>? jobPlans,
  Map<String, List<Map<String, dynamic>>>? downtime,
  Map<String, List<Map<String, dynamic>>>? myRequests,
  List<Map<String, dynamic>>? employees,
  Map<String, Map<String, dynamic>>? employeeDetails,
  List<Map<String, dynamic>>? skills,
  List<Map<String, dynamic>>? parts,
  Map<String, List<Map<String, dynamic>>>? stores,
}) =>
    FakeWire(
      role: role,
      orgUnitScope: orgUnitScope,
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [orgUnitJson('10', 'Assembly')],
        '10': [orgUnitJson('11', 'Line 1', parentId: '10', unitType: 'line')],
      },
      assets: assets,
      workOrders: workOrders,
      workOrderCosts: workOrderCosts,
      meters: meters,
      pmSchedules: pmSchedules,
      jobPlans: jobPlans,
      downtime: downtime,
      myRequests: myRequests,
      employees: employees,
      employeeDetails: employeeDetails,
      skills: skills,
      parts: parts,
      stores: stores,
    );

/// One converted picker, with everything the four assertions need to drive it:
/// where the dialog is, how a person opens it, what to type, which record must
/// match (and which must not), what the field shows once that record is picked,
/// and what the form's own submit body carries for it.
class _PickerCase {
  _PickerCase({
    required this.dialog,
    required this.picker,
    required this.wire,
    required this.location,
    required this.open,
    required this.fieldKey,
    required this.fieldType,
    required this.fieldLabel,
    required this.term,
    required this.recordId,
    required this.matchSuggestion,
    required this.otherSuggestion,
    required this.display,
    required this.fillOtherFields,
    required this.submitKey,
    required this.submittedId,
    this.required = true,
  });

  /// The dialog under test, as a person would name it.
  final String dialog;

  /// The picker under test, as a person would name it.
  final String picker;

  final FakeWire wire;

  /// The address the Screen under the dialog is reached at.
  final String location;

  /// Opens the dialog off that Screen, the way a person does.
  final Future<void> Function(WidgetTester tester) open;

  /// The picker's field key — the `AppSearchField`'s own `TextField` key.
  final Key fieldKey;

  /// What the field says it picks — the label a screen reader announces in
  /// place of the magnifier glyph (ADR-0023, issue #190's user story 14).
  final String fieldLabel;

  /// The picker's own widget, so a state can be proved to render *inside* the
  /// field rather than anywhere on the Screen beneath it.
  final Finder Function() fieldType;

  /// A term of two or more characters matching one record and not the other.
  final String term;

  /// The id of the record [term] matches.
  final String recordId;

  final Key matchSuggestion;
  final Key otherSuggestion;

  /// The display string the field shows once that record is picked.
  final String display;

  /// Fills every *other* field the dialog's submit gate reads, so the picker is
  /// the only thing left between the form and submission.
  final Future<void> Function(WidgetTester tester) fillOtherFields;

  final Key submitKey;

  /// The id the dialog's own POST body carries for this picker, read off the
  /// wire's recorded posts — null where the picker is optional and nothing was
  /// picked.
  final String? Function(FakeWire wire) submittedId;

  /// False for a picker the form deliberately allows to stay empty.
  final bool required;

  String get label => '$dialog, $picker';
}

/// Every picker this ticket converted, built fresh per test so no test can see
/// another's recorded requests.
List<_PickerCase Function()> _cases() => [
      // ---------------------------------------------------------------- Asset
      () => _PickerCase(
            dialog: 'the Work order form',
            picker: 'Asset picker',
            wire: _wire(
              workOrders: {'1': []},
              assets: {
                '1': [
                  assetJson('7', 'PRESS-1', 'Press 1'),
                  assetJson('8', 'FAN-2', 'Fan 2'),
                ],
              },
            ),
            location: '/work-orders',
            open: (tester) async {
              await tapIn(tester, find.byKey(WorkOrdersScreen.raiseKey));
              await tester.pumpAndSettle();
            },
            fieldKey: WorkOrderFormDialog.assetKey,
            fieldType: () => find.byType(AppSearchField<Asset>),
            fieldLabel: 'Asset',
            term: 'Press',
            recordId: '7',
            matchSuggestion: WorkOrderFormDialog.assetSuggestionKey('7'),
            otherSuggestion: WorkOrderFormDialog.assetSuggestionKey('8'),
            display: 'Press 1 (PRESS-1)',
            fillOtherFields: (tester) async {
              await tester.enterText(
                find.byKey(WorkOrderFormDialog.summaryKey),
                'Belt is slipping',
              );
              await tester.pumpAndSettle();
              await tapIn(tester, find.byKey(WorkOrderFormDialog.workTypeKey));
              await tapIn(tester, find.text('Corrective').last);
              await tapIn(tester, find.byKey(WorkOrderFormDialog.priorityKey));
              await tapIn(tester, find.text('3 - Normal').last);
            },
            submitKey: WorkOrderFormDialog.submitKey,
            submittedId: (wire) => wire.workOrderPosts.single['assetId'] as String?,
          ),
      () => _PickerCase(
            dialog: 'the Request form',
            picker: 'Asset picker',
            wire: _wire(
              role: Roles.operator,
              orgUnitScope: {
                'everywhere': false,
                'grants': [scopeGrantJson('10')],
              },
              assets: {
                '1': [
                  assetJson('7', 'PRESS-1', 'Press 1'),
                  assetJson('8', 'FAN-2', 'Fan 2'),
                ],
              },
              myRequests: {'1': []},
            ),
            location: '/my-requests',
            open: (tester) async {
              await tapIn(tester, find.byKey(MyRequestsScreen.raiseKey));
              await tester.pumpAndSettle();
            },
            fieldKey: RequestFormDialog.assetKey,
            fieldType: () => find.byType(AppSearchField<Asset>),
            fieldLabel: 'Asset',
            term: 'Press',
            recordId: '7',
            matchSuggestion: RequestFormDialog.assetSuggestionKey('7'),
            otherSuggestion: RequestFormDialog.assetSuggestionKey('8'),
            display: 'Press 1 (PRESS-1)',
            fillOtherFields: (tester) async {
              await tester.enterText(
                find.byKey(RequestFormDialog.summaryKey),
                'Belt is slipping',
              );
              await tester.pumpAndSettle();
              await tapIn(tester, find.byKey(RequestFormDialog.urgencyKey));
              await tapIn(tester, find.text('High').last);
            },
            submitKey: RequestFormDialog.submitKey,
            submittedId: (wire) => wire.requestPosts.single['assetId'] as String?,
          ),
      () => _PickerCase(
            dialog: 'the meter form',
            picker: 'Asset picker',
            wire: _wire(
              assets: {
                '1': [
                  assetJson('7', 'PRESS-1', 'Press 1'),
                  assetJson('8', 'FAN-2', 'Fan 2'),
                ],
              },
            ),
            location: '/meters',
            open: (tester) async {
              await tapIn(tester, find.byKey(MetersScreen.createKey));
              await tester.pumpAndSettle();
            },
            fieldKey: MeterFormDialog.assetKey,
            fieldType: () => find.byType(AppSearchField<Asset>),
            fieldLabel: 'Asset',
            term: 'Press',
            recordId: '7',
            matchSuggestion: MeterFormDialog.assetSuggestionKey('7'),
            otherSuggestion: MeterFormDialog.assetSuggestionKey('8'),
            display: 'Press 1 (PRESS-1)',
            fillOtherFields: (tester) async {
              await tester.enterText(find.byKey(MeterFormDialog.codeKey), 'CYC');
              await tester.enterText(find.byKey(MeterFormDialog.nameKey), 'Cycles');
              await tester.pumpAndSettle();
              await tapIn(tester, find.byKey(MeterFormDialog.uomKey));
              await tapIn(tester, find.text('Each (EA)').last);
            },
            submitKey: MeterFormDialog.submitKey,
            submittedId: (wire) => wire.meterPosts.single['assetId'] as String?,
          ),
      () => _PickerCase(
            dialog: 'the PM schedule form',
            picker: 'Asset picker',
            wire: _wire(
              assets: {
                '1': [
                  assetJson('7', 'PRESS-1', 'Press 1'),
                  assetJson('8', 'FAN-2', 'Fan 2'),
                ],
              },
              jobPlans: [jobPlanJson('5', 'JP-5', 'Annual service')],
              pmSchedules: {'1': []},
            ),
            location: '/pm-schedules',
            open: (tester) async {
              await tapIn(tester, find.byKey(PmSchedulesScreen.createKey));
              await tester.pumpAndSettle();
            },
            fieldKey: PmScheduleFormDialog.assetKey,
            fieldType: () => find.byType(AppSearchField<Asset>),
            fieldLabel: 'Asset',
            term: 'Press',
            recordId: '7',
            matchSuggestion: PmScheduleFormDialog.assetSuggestionKey('7'),
            otherSuggestion: PmScheduleFormDialog.assetSuggestionKey('8'),
            display: 'Press 1 (PRESS-1)',
            fillOtherFields: (tester) async {
              await pickSuggestion(
                tester,
                fieldKey: PmScheduleFormDialog.jobPlanKey,
                term: 'Annual',
                suggestionKey: PmScheduleFormDialog.jobPlanSuggestionKey('5'),
              );
              await tester.enterText(find.byKey(PmScheduleFormDialog.intervalKey), '30');
              await tester.pumpAndSettle();
            },
            submitKey: PmScheduleFormDialog.submitKey,
            submittedId: (wire) => wire.pmSchedulePosts.single['assetId'] as String?,
          ),
      () => _PickerCase(
            dialog: 'the PM schedule form',
            picker: 'Job plan picker',
            wire: _wire(
              assets: {'1': [assetJson('7', 'PRESS-1', 'Press 1')]},
              jobPlans: [
                jobPlanJson('5', 'JP-5', 'Annual service'),
                jobPlanJson('6', 'JP-6', 'Fan service'),
              ],
              pmSchedules: {'1': []},
            ),
            location: '/pm-schedules',
            open: (tester) async {
              await tapIn(tester, find.byKey(PmSchedulesScreen.createKey));
              await tester.pumpAndSettle();
            },
            fieldKey: PmScheduleFormDialog.jobPlanKey,
            fieldType: () => find.byType(AppSearchField<JobPlan>),
            fieldLabel: 'Job plan',
            term: 'Annual',
            recordId: '5',
            matchSuggestion: PmScheduleFormDialog.jobPlanSuggestionKey('5'),
            otherSuggestion: PmScheduleFormDialog.jobPlanSuggestionKey('6'),
            display: 'Annual service',
            fillOtherFields: (tester) async {
              await pickSuggestion(
                tester,
                fieldKey: PmScheduleFormDialog.assetKey,
                term: 'Press',
                suggestionKey: PmScheduleFormDialog.assetSuggestionKey('7'),
              );
              await tester.enterText(find.byKey(PmScheduleFormDialog.intervalKey), '30');
              await tester.pumpAndSettle();
            },
            submitKey: PmScheduleFormDialog.submitKey,
            submittedId: (wire) => wire.pmSchedulePosts.single['jobPlanId'] as String?,
          ),
      () => _PickerCase(
            dialog: 'the Breakdown report',
            picker: 'Asset picker',
            wire: _wire(
              assets: {
                '1': [
                  assetJson('7', 'PRESS-1', 'Press 1'),
                  assetJson('8', 'FAN-2', 'Fan 2'),
                ],
              },
              downtime: {'1': []},
            ),
            location: '/downtime',
            open: (tester) async {
              await tapIn(tester, find.byKey(DowntimeScreen.reportKey));
              await tester.pumpAndSettle();
            },
            fieldKey: BreakdownReportDialog.assetKey,
            fieldType: () => find.byType(AppSearchField<Asset>),
            fieldLabel: 'Asset',
            term: 'Press',
            recordId: '7',
            matchSuggestion: BreakdownReportDialog.assetSuggestionKey('7'),
            otherSuggestion: BreakdownReportDialog.assetSuggestionKey('8'),
            display: 'Press 1 (PRESS-1)',
            // The Asset is the only field this form requires, so nothing else
            // stands between it and submission — the picker's own gate is all
            // there is to assert on.
            fillOtherFields: (tester) async {},
            submitKey: BreakdownReportDialog.submitKey,
            submittedId: (wire) => wire.downtimePosts.single['assetId'] as String?,
          ),
      // ---------------------------------------------------------------- Part
      () => _PickerCase(
            dialog: 'the part booking',
            picker: 'Part picker',
            wire: _wire(
              workOrders: {
                '1': [workOrderJson('101', 'WO-101', 'Belt is slipping')],
              },
              workOrderCosts: {'101': workOrderCostJson()},
              parts: [
                partJson('3', 'BRG-6204', 'Bearing, 6204'),
                partJson('4', 'BLT-M8', 'Bolt, M8'),
              ],
              stores: {
                '1': [
                  storeJson('7', 'A-STORE', 'Main store'),
                  storeJson('8', 'B-STORE', 'Backup store'),
                ],
              },
            ),
            location: '/work-orders',
            open: (tester) async {
              await tapIn(tester, find.byKey(WorkOrdersScreen.detailsKey('101')));
              await tapIn(tester, find.byKey(WorkOrderDetailScreen.bookPartKey));
            },
            fieldKey: PartBookingDialog.partKey,
            fieldType: () => find.byType(AppSearchField<Part>),
            fieldLabel: 'Part',
            term: 'BRG',
            recordId: '3',
            matchSuggestion: PartBookingDialog.partSuggestionKey('3'),
            otherSuggestion: PartBookingDialog.partSuggestionKey('4'),
            display: 'BRG-6204 · Bearing, 6204',
            fillOtherFields: (tester) async {
              await pickSuggestion(
                tester,
                fieldKey: PartBookingDialog.storeKey,
                term: 'Main',
                suggestionKey: PartBookingDialog.storeSuggestionKey('7'),
              );
            },
            submitKey: PartBookingDialog.submitKey,
            submittedId: (wire) => wire.partBookingPosts.single.$2['partId'] as String?,
          ),
      // --------------------------------------------------------------- Store
      () => _PickerCase(
            dialog: 'the part booking',
            picker: 'Store picker',
            wire: _wire(
              workOrders: {
                '1': [workOrderJson('101', 'WO-101', 'Belt is slipping')],
              },
              workOrderCosts: {'101': workOrderCostJson()},
              parts: [partJson('3', 'BRG-6204', 'Bearing, 6204')],
              stores: {
                '1': [
                  storeJson('7', 'A-STORE', 'Main store'),
                  storeJson('8', 'B-STORE', 'Backup store'),
                ],
              },
            ),
            location: '/work-orders',
            open: (tester) async {
              await tapIn(tester, find.byKey(WorkOrdersScreen.detailsKey('101')));
              await tapIn(tester, find.byKey(WorkOrderDetailScreen.bookPartKey));
            },
            fieldKey: PartBookingDialog.storeKey,
            fieldType: () => find.byType(AppSearchField<Store>),
            fieldLabel: 'Store',
            term: 'Main',
            recordId: '7',
            matchSuggestion: PartBookingDialog.storeSuggestionKey('7'),
            otherSuggestion: PartBookingDialog.storeSuggestionKey('8'),
            display: 'A-STORE · Main store',
            fillOtherFields: (tester) async {
              await pickSuggestion(
                tester,
                fieldKey: PartBookingDialog.partKey,
                term: 'BRG',
                suggestionKey: PartBookingDialog.partSuggestionKey('3'),
              );
            },
            submitKey: PartBookingDialog.submitKey,
            submittedId: (wire) => wire.partBookingPosts.single.$2['storeId'] as String?,
          ),
      // ------------------------------------------------------------ Employee
      () => _PickerCase(
            dialog: 'the labour booking',
            picker: 'Employee picker',
            wire: _wire(
              workOrders: {
                '1': [workOrderJson('101', 'WO-101', 'Belt is slipping')],
              },
              workOrderCosts: {'101': workOrderCostJson()},
              employees: [
                employeeJson('20', 'EMP-20', 'Jane Doe'),
                employeeJson('21', 'EMP-21', 'John Roe'),
              ],
            ),
            location: '/work-orders',
            open: (tester) async {
              await tapIn(tester, find.byKey(WorkOrdersScreen.detailsKey('101')));
              await tapIn(tester, find.byKey(WorkOrderDetailScreen.bookLabourKey));
            },
            fieldKey: LabourBookingDialog.employeeKey,
            fieldType: () => find.byType(AppSearchField<Employee>),
            fieldLabel: 'Employee',
            term: 'Jane',
            recordId: '20',
            matchSuggestion: LabourBookingDialog.employeeSuggestionKey('20'),
            otherSuggestion: LabourBookingDialog.employeeSuggestionKey('21'),
            display: 'Jane Doe',
            fillOtherFields: (tester) async {
              await tapIn(tester, find.byKey(LabourBookingDialog.activityKey));
              await tapIn(tester, find.text('Work').last);
            },
            submitKey: LabourBookingDialog.submitKey,
            submittedId: (wire) => wire.labourPosts.single.$2['employeeId'] as String?,
          ),
      // --------------------------------------------------------------- Skill
      () => _PickerCase(
            dialog: 'the Job plan form',
            picker: "a step's required Skill picker",
            wire: _wire(
              role: Roles.admin,
              orgUnitScope: null,
              jobPlans: const [],
              skills: [
                skillJson('3', 'ELEC', 'Electrical'),
                skillJson('4', 'MECH', 'Mechanical'),
              ],
            ),
            location: '/job-plans',
            open: (tester) async {
              await tapIn(tester, find.byKey(JobPlansScreen.addKey));
              await tester.pumpAndSettle();
            },
            fieldKey: JobPlanFormDialog.taskSkillKey(0),
            fieldType: () => find.byType(AppSearchField<Skill>),
            fieldLabel: 'Required skill (optional)',
            term: 'Elect',
            recordId: '3',
            matchSuggestion: JobPlanFormDialog.taskSkillSuggestionKey(0, '3'),
            otherSuggestion: JobPlanFormDialog.taskSkillSuggestionKey(0, '4'),
            display: 'Electrical',
            fillOtherFields: (tester) async {
              await tester.enterText(find.byKey(JobPlanFormDialog.codeKey), 'JP-2');
              await tester.enterText(
                find.byKey(JobPlanFormDialog.nameKey),
                'Quarterly inspection',
              );
              await tester.enterText(
                find.byKey(JobPlanFormDialog.taskInstructionKey(0)),
                'Check the guard',
              );
              await tester.pumpAndSettle();
            },
            submitKey: JobPlanFormDialog.submitKey,
            submittedId: (wire) =>
                ((wire.jobPlanPosts.single['tasks'] as List<dynamic>).first
                    as Map<String, dynamic>)['skillId'] as String?,
            // A step's Skill is optional on purpose — "a step that requires no
            // Skill simply omits skillId" — so this is the one picker whose
            // absence does not close the form's submit gate.
            required: false,
          ),
      () => _PickerCase(
            dialog: 'the Employee skill form',
            picker: 'Skill picker',
            wire: _wire(
              role: Roles.admin,
              orgUnitScope: null,
              employees: [employeeJson('7', 'E-7', 'Alice Nguyen')],
              employeeDetails: {'7': employeeDetailJson('7', 'E-7', 'Alice Nguyen')},
              skills: [
                skillJson('30', 'WELD', 'Welding'),
                skillJson('31', 'ELEC', 'Electrical'),
              ],
            ),
            location: '/directory',
            open: (tester) async {
              await tapIn(tester, find.byKey(DirectoryScreen.rowKey('7')));
              await tapIn(tester, find.byKey(EmployeeDetailScreen.recordSkillKey));
            },
            fieldKey: EmployeeSkillFormDialog.skillKey,
            fieldType: () => find.byType(AppSearchField<Skill>),
            fieldLabel: 'Skill',
            term: 'Weld',
            recordId: '30',
            matchSuggestion: EmployeeSkillFormDialog.skillSuggestionKey('30'),
            otherSuggestion: EmployeeSkillFormDialog.skillSuggestionKey('31'),
            display: 'Welding',
            // The Skill is the only field this form requires.
            fillOtherFields: (tester) async {},
            submitKey: EmployeeSkillFormDialog.submitKey,
            submittedId: (wire) => wire.employeeSkillPuts.single.$2,
          ),
    ];

/// Pumps the app to the Screen under test and opens the dialog off it — the
/// same two steps a person takes.
Future<void> _openPicker(WidgetTester tester, _PickerCase c) async {
  await pumpApp(
    tester,
    gateway: FakeAuthGateway(accessToken: 'a-token'),
    client: c.wire.client,
    initialLocation: c.location,
  );
  await c.open(tester);
}

void main() {
  for (final make in _cases()) {
    // One throwaway instance per row, only to name the group and decide which
    // shape of the last assertion holds — every test below builds its own, so
    // no test can see another's recorded requests.
    final shape = make();

    group('${shape.label} (issue #190, ADR-0023)', () {
      testWidgets(
          'typing narrows to the matching record with no request per keystroke: one character '
          'issues nothing and shows nothing, two characters match and still issue nothing',
          (tester) async {
        final c = make();
        await _openPicker(tester, c);

        // The field says what it picks, so a screen reader announces "Asset"
        // rather than a magnifier glyph (issue #190's user story 14).
        expect(
          find.descendant(of: c.fieldType(), matching: find.text(c.fieldLabel)),
          findsOneWidget,
        );

        final before = c.wire.requests.length;

        // Below the field's own two-character minimum — not even a debounced
        // fetch is issued, and nothing is offered yet.
        await typeInSearchField(tester, c.fieldKey, c.term.substring(0, 1));
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          c.wire.requests.length,
          before,
          reason: 'one character is below the field minimum — no request at all',
        );
        expect(find.byKey(c.matchSuggestion), findsNothing);

        await typeInSearchField(tester, c.fieldKey, c.term);
        expect(find.byKey(c.matchSuggestion), findsOneWidget);
        expect(find.byKey(c.otherSuggestion), findsNothing);
        expect(
          c.wire.requests.length,
          before,
          reason: 'the picker filters the list the dialog already read — the writing half '
              'of ADR-0023 costs nothing on the wire, let alone a request per keystroke',
        );
      });

      testWidgets(
          "picking a suggestion fills the field with the record's own display string and the "
          'submitted body carries its id', (tester) async {
        final c = make();
        await _openPicker(tester, c);
        await c.fillOtherFields(tester);

        await pickSuggestion(
          tester,
          fieldKey: c.fieldKey,
          term: c.term,
          suggestionKey: c.matchSuggestion,
        );

        expect(
          searchFieldText(tester, c.fieldKey),
          c.display,
          reason: 'the person can check what they picked before submitting',
        );
        // The suggestion list is gone — a pick ends the search.
        expect(find.byKey(c.matchSuggestion), findsNothing);

        await tapIn(tester, find.byKey(c.submitKey));

        expect(c.submittedId(c.wire), c.recordId);
      });

      testWidgets('a term matching nothing renders the shared no-match state', (tester) async {
        final c = make();
        await _openPicker(tester, c);

        await typeInSearchField(tester, c.fieldKey, 'zzzz');

        expect(find.byKey(c.matchSuggestion), findsNothing);
        expect(
          find.descendant(
            of: c.fieldType(),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is PlatformEmptyState &&
                  widget.variant == EmptyStateVariant.noneMatched,
            ),
          ),
          findsOneWidget,
        );
        expect(find.text('Nothing matched "zzzz" — try a different term.'), findsOneWidget);
      });

      testWidgets(
          'typing over a picked record retires it, so the form cannot submit an id its own '
          'field has stopped showing', (tester) async {
        final c = make();
        await _openPicker(tester, c);
        await c.fillOtherFields(tester);

        await pickSuggestion(
          tester,
          fieldKey: c.fieldKey,
          term: c.term,
          suggestionKey: c.matchSuggestion,
        );
        expect(searchFieldText(tester, c.fieldKey), c.display);

        // ADR-0023 point 4's own hazard: the person is searching again, not
        // looking at their choice, so the choice is retired at that keystroke.
        await typeInSearchField(tester, c.fieldKey, 'zzzz');

        if (c.required) {
          expect(
            tester.widget<FilledButton>(find.byKey(c.submitKey)).onPressed,
            isNull,
            reason: 'the pick was retired, so the form is waiting again',
          );
          return;
        }

        await tapIn(tester, find.byKey(c.submitKey));
        expect(
          c.submittedId(c.wire),
          isNull,
          reason: 'the retired pick is not on the wire',
        );
      });

      testWidgets(
          shape.required
              ? 'submission is blocked until a record is picked'
              : 'the form still submits with no record picked, naming nothing on the wire',
          (tester) async {
        final c = make();
        await _openPicker(tester, c);
        await c.fillOtherFields(tester);

        if (c.required) {
          expect(
            tester.widget<FilledButton>(find.byKey(c.submitKey)).onPressed,
            isNull,
            reason: 'nothing has been picked yet',
          );

          await pickSuggestion(
            tester,
            fieldKey: c.fieldKey,
            term: c.term,
            suggestionKey: c.matchSuggestion,
          );

          expect(
            tester.widget<FilledButton>(find.byKey(c.submitKey)).onPressed,
            isNotNull,
            reason: 'the pick is the last thing the form was waiting for',
          );
          return;
        }

        await tapIn(tester, find.byKey(c.submitKey));
        expect(
          c.submittedId(c.wire),
          isNull,
          reason: 'a step no Skill was picked for names no skillId at all',
        );
      });
    });
  }
}
