/// Shared test harness for the client's widget tests.
///
/// The fake wire and the `pumpApp`/`meClient` pump helpers are used by every
/// Screen's tests, so they live here — somewhere neutral — rather than inside
/// whichever Screen's test file happened to need them first (issue #60, done
/// ahead of the Maintenance Module's own tests in #55).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:lean_platform/maintenance/maintenance_api.dart';
import 'package:lean_platform/people_api.dart';
import 'package:lean_platform/platform/auth_gateway.dart';
import 'package:lean_platform/platform/destinations.dart';
import 'package:lean_platform/platform/platform_app.dart';

/// Loads the Platform's own bundled Roboto (`assets/fonts/README.md`,
/// committed there for Flutter Web's CanvasKit renderer, not for this) into
/// the test binary, under the exact family name `theme.dart`'s own
/// `buildAppTheme` sets (`fontFamily: 'Roboto'`) — without this,
/// `flutter_test`'s default font substitution paints every glyph as a solid
/// box, which is fine for a text-content assertion (`find.text` reads the
/// widget tree, not pixels) but useless for a golden: a box cannot show a
/// font-weight, line-height or text-colour regression, and #99's own user
/// stories 18–20 are specifically about those (issue #105).
///
/// A golden test calls this once, from its own `setUpAll`, before the first
/// `pumpWidget` — see `shell_test.dart`'s `goldens (#105)` group and
/// `work_orders_golden_test.dart`. Every other test in this suite is
/// unaffected: nothing here asserts on a font, so the placeholder boxes
/// `flutter_test` paints by default are exactly as good for them.
///
/// Idempotent within one loaded isolate — `flutter test` runs each test
/// *file* as its own process, so this guard only matters if a single file
/// ever called it from more than one `setUpAll`.
bool _fontsLoaded = false;

Future<void> loadAppFonts() async {
  if (_fontsLoaded) return;
  final loader = FontLoader('Roboto');
  for (final path in [
    'assets/fonts/Roboto-Regular.ttf',
    'assets/fonts/Roboto-Medium.ttf',
    'assets/fonts/Roboto-Bold.ttf',
  ]) {
    final bytes = File(path).readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
  _fontsLoaded = true;
}

// `selfId` is '1' by default, and the fixtures that have to avoid it live in
// the calling test files rather than here: they use ids '7'/'8'/'9'/'10'+, so
// '1' never accidentally collides with a row and turns it into a false "self"
// match (issue #53). A new test building an `accountJson('1', …)` fixture is
// therefore declaring that row to be the caller's own Account, which loses it
// both row actions — deliberately so in `accounts_test.dart`, and a surprise
// anywhere else.
// `orgUnitScope` is what a Screen reads to decide whether to offer a write at
// all (issue #43, first consumed by the Asset register in #56). Left unset it
// mirrors the server's own invariant: an administrator reaches everywhere and
// holds no Grant rows; anyone else holds whatever rows the test gives them.
Map<String, dynamic> _meBody(String role, String selfId, Map<String, dynamic>? orgUnitScope) => {
      'status': 'active',
      'account': {'id': selfId, 'email': 'admin@b.c', 'displayName': 'A B', 'role': role},
      'orgUnitScope':
          orgUnitScope ?? {'everywhere': role == Roles.admin, 'grants': const <dynamic>[]},
    };

/// One Grant as `/me` reports it — `canWrite` is what decides whether a Screen
/// offers a write affordance.
Map<String, dynamic> scopeGrantJson(String orgUnitId, {String siteId = '1', bool canWrite = false}) =>
    {'orgUnitId': orgUnitId, 'siteId': siteId, 'canWrite': canWrite};

/// One Asset as `GET /api/maintenance/sites/:siteId/assets` sends it.
Map<String, dynamic> assetJson(
  String id,
  String code,
  String name, {
  String orgUnitId = '10',
  String orgUnitName = 'Line 1',
  String siteId = '1',
  String assetType = 'machine',
  String criticality = 'medium',
  bool isActive = true,
  String? parentId,
}) =>
    {
      'id': id,
      'code': code,
      'name': name,
      'assetType': assetType,
      'criticality': criticality,
      'orgUnitId': orgUnitId,
      'orgUnitName': orgUnitName,
      'orgUnitCode': orgUnitName.toUpperCase().replaceAll(' ', '-'),
      'siteId': siteId,
      'isActive': isActive,
      'parentId': parentId,
      'assetLevel': 'machine',
    };

/// One Work order as `GET /api/maintenance/sites/:siteId/work-orders` sends
/// it (issue #57) — always an open one, since the server itself excludes
/// completed/closed/cancelled from that read.
///
/// Mirrors `toWorkOrder` (backend/src/modules/maintenance/work-orders.js) key
/// for key, in its own field order: a flat row, no nested `asset`/`orgUnit`
/// map and no `assignee` string. A change to one of these should prompt a
/// look at the other.
Map<String, dynamic> workOrderJson(
  String id,
  String workOrderNo,
  String summary, {
  String assetId = '7',
  String assetCode = 'PRESS-1',
  String assetName = 'Press 1',
  String orgUnitId = '10',
  String orgUnitName = 'Line 1',
  String? description,
  String workType = 'corrective',
  int priority = 3,
  // 'approved' is the first status this slice's own state machine offers
  // (issue #63) — 'open' was never a real status, a leftover the four-state
  // UI made untenable.
  String status = 'approved',
  String? assignedTo,
  String? assigneeName,
  DateTime? createdAt,
  DateTime? updatedAt,
}) =>
    {
      'id': id,
      'workOrderNo': workOrderNo,
      'assetId': assetId,
      'assetCode': assetCode,
      'assetName': assetName,
      'orgUnitId': orgUnitId,
      'orgUnitName': orgUnitName,
      'summary': summary,
      'description': description,
      'workType': workType,
      'priority': priority,
      'status': status,
      'assignedTo': assignedTo,
      'assigneeName': assigneeName,
      'createdAt': (createdAt ?? DateTime.now()).toUtc().toIso8601String(),
      'updatedAt': (updatedAt ?? DateTime.now()).toUtc().toIso8601String(),
    };

/// The Work order an accepted Request produced, as the nested `workOrder` map
/// on a Request row sends it (issue #72, ADR-0014) — `{id, workOrderNo,
/// status}`, nothing more.
Map<String, dynamic> requestWorkOrderJson(
  String id,
  String workOrderNo, {
  String status = 'approved',
}) =>
    {'id': id, 'workOrderNo': workOrderNo, 'status': status};

/// One Request as `GET /api/maintenance/sites/:siteId/requests` (the triage
/// queue), `.../requests/mine`, and the raise/accept/decline/duplicate routes
/// send it (issue #72).
///
/// Mirrors `toRequest` (backend/src/modules/maintenance/requests.js) key for
/// key, in its own field order: a flat row plus a nested `workOrder` map or
/// null. `workOrder` is non-null only for an accepted Request.
Map<String, dynamic> requestJson(
  String id,
  String requestNo,
  String summary, {
  String assetId = '7',
  String assetCode = 'PRESS-1',
  String assetName = 'Press 1',
  String orgUnitId = '10',
  String orgUnitName = 'Line 1',
  String? description,
  String urgency = 'normal',
  bool productionStopped = false,
  String? reportedBy = '20',
  String? reporterName = 'Jane Doe',
  DateTime? reportedAt,
  String status = 'new',
  DateTime? triagedAt,
  String? rejectionReason,
  String? duplicateOfId,
  Map<String, dynamic>? workOrder,
}) =>
    {
      'id': id,
      'requestNo': requestNo,
      'assetId': assetId,
      'assetCode': assetCode,
      'assetName': assetName,
      'orgUnitId': orgUnitId,
      'orgUnitName': orgUnitName,
      'summary': summary,
      'description': description,
      'urgency': urgency,
      'productionStopped': productionStopped,
      'reportedBy': reportedBy,
      'reporterName': reporterName,
      'reportedAt': (reportedAt ?? DateTime.now()).toUtc().toIso8601String(),
      'status': status,
      'triagedAt': triagedAt?.toUtc().toIso8601String(),
      'rejectionReason': rejectionReason,
      'duplicateOfId': duplicateOfId,
      'workOrder': workOrder,
    };

/// One Downtime event as `GET /api/maintenance/sites/:siteId/downtime`, the
/// Breakdown report and the two row actions send it (issue #73).
///
/// Mirrors `toDowntimeEvent` (backend/src/modules/maintenance/downtime.js) key
/// for key, in its own field order: a flat row, no nested `asset`/`orgUnit`
/// map. `status` is the generated column — `open` while `endedAt` is null,
/// `unclassified` once closed with no reason, `closed` otherwise.
Map<String, dynamic> downtimeJson(
  String id, {
  String assetId = '7',
  String assetCode = 'PRESS-1',
  String assetName = 'Press 1',
  String orgUnitId = '10',
  String orgUnitName = 'Line 1',
  DateTime? startedAt,
  DateTime? endedAt,
  num? durationMinutes,
  String status = 'open',
  String? downtimeReasonId,
  String? downtimeReasonName,
  String? description,
  String? reportedBy = '20',
  String? reporterName = 'Jane Doe',
  DateTime? classifiedAt,
  String source = 'manual',
}) =>
    {
      'id': id,
      'assetId': assetId,
      'assetCode': assetCode,
      'assetName': assetName,
      'orgUnitId': orgUnitId,
      'orgUnitName': orgUnitName,
      'startedAt': (startedAt ?? DateTime.now()).toUtc().toIso8601String(),
      'endedAt': endedAt?.toUtc().toIso8601String(),
      'durationMinutes': durationMinutes,
      'status': status,
      'downtimeReasonId': downtimeReasonId,
      'downtimeReasonName': downtimeReasonName,
      'description': description,
      'reportedBy': reportedBy,
      'reporterName': reporterName,
      'classifiedAt': classifiedAt?.toUtc().toIso8601String(),
      'source': source,
    };

/// One Downtime reason as `GET /api/maintenance/downtime-reasons` sends it
/// (issue #73) — the classify picker's own catalogue.
Map<String, dynamic> downtimeReasonJson(
  String id,
  String code,
  String name, {
  String lossCategory = 'unplanned',
  bool isPlanned = false,
  bool requiresComment = false,
}) =>
    {
      'id': id,
      'code': code,
      'name': name,
      'lossCategory': lossCategory,
      'isPlanned': isPlanned,
      'requiresComment': requiresComment,
    };

/// One Job plan task as `GET /api/maintenance/job-plans` sends it (issue #74)
/// — mirrors `toJobPlanTask` (job-plans.js) key for key, with the required
/// Skill's name already resolved by the server's own join.
Map<String, dynamic> jobPlanTaskJson(
  String id,
  int stepNo,
  String instruction, {
  String? skillId,
  String? skillName,
  num? estimatedHours,
}) =>
    {
      'id': id,
      'stepNo': stepNo,
      'instruction': instruction,
      'skillId': skillId,
      'skillName': skillName,
      'estimatedHours': estimatedHours,
    };

/// One Job plan as `GET /api/maintenance/job-plans` sends it (issue #74) —
/// mirrors `toJobPlan` (job-plans.js) key for key: a flat row plus an ordered
/// `tasks` list.
Map<String, dynamic> jobPlanJson(
  String id,
  String code,
  String name, {
  String? description,
  String workType = 'preventive',
  num? estimatedHours,
  bool requiresShutdown = false,
  String? safetyNote,
  bool isActive = true,
  List<Map<String, dynamic>> tasks = const [],
}) =>
    {
      'id': id,
      'code': code,
      'name': name,
      'description': description,
      'workType': workType,
      'estimatedHours': estimatedHours,
      'requiresShutdown': requiresShutdown,
      'safetyNote': safetyNote,
      'isActive': isActive,
      'tasks': tasks,
    };

/// One PM schedule as `GET /api/maintenance/sites/:siteId/pm-schedules` sends
/// it (issue #74) — mirrors `toPmSchedule` (pm-schedules.js) key for key: a
/// flat row, no nested `asset`/`orgUnit`/`jobPlan` maps.
Map<String, dynamic> pmScheduleJson(
  String id,
  String code,
  String name, {
  String assetId = '7',
  String assetCode = 'PRESS-1',
  String assetName = 'Press 1',
  String orgUnitId = '10',
  String orgUnitName = 'Line 1',
  String jobPlanId = '5',
  String jobPlanName = 'Annual service',
  int intervalDays = 30,
  String anchor = 'completed',
  int leadTimeDays = 7,
  int priority = 3,
  String? lastCompletedOn,
  String? nextDueOn,
  bool isActive = true,
  int? daysUntilDue,
}) =>
    {
      'id': id,
      'code': code,
      'name': name,
      'assetId': assetId,
      'assetCode': assetCode,
      'assetName': assetName,
      'orgUnitId': orgUnitId,
      'orgUnitName': orgUnitName,
      'jobPlanId': jobPlanId,
      'jobPlanName': jobPlanName,
      'intervalDays': intervalDays,
      'anchor': anchor,
      'leadTimeDays': leadTimeDays,
      'priority': priority,
      'lastCompletedOn': lastCompletedOn,
      'nextDueOn': nextDueOn,
      'isActive': isActive,
      'daysUntilDue': daysUntilDue,
    };

/// One Work order task as `GET /api/maintenance/work-orders/:id` sends it
/// (issue #74) — mirrors `toWorkOrderTask` (work-orders.js) key for key.
Map<String, dynamic> workOrderTaskJson(
  String id,
  int stepNo,
  String instruction, {
  String? skillId,
  String? skillName,
  String status = 'pending',
  String? note,
  num? reading,
}) =>
    {
      'id': id,
      'stepNo': stepNo,
      'instruction': instruction,
      'skillId': skillId,
      'skillName': skillName,
      'status': status,
      'note': note,
      'reading': reading,
    };

/// One held skill as `GET /api/people/employees/assignee-candidates` sends
/// it, nested under a candidate — mirrors `directory.js`'s per-skill shape
/// plus `isLapsed` (issue #62).
Map<String, dynamic> heldSkillJson(
  String id,
  String skillId,
  String code,
  String name, {
  int proficiencyLevel = 3,
  String? expiresOn,
  bool isLapsed = false,
}) =>
    {
      'id': id,
      'proficiencyLevel': proficiencyLevel,
      'assessedOn': '2024-01-01',
      'expiresOn': expiresOn,
      'isLapsed': isLapsed,
      'skill': {'id': skillId, 'code': code, 'name': name},
    };

/// One candidate as `GET /api/people/employees/assignee-candidates` sends
/// it (issue #62) — every Active Employee, with the skills each currently
/// holds.
Map<String, dynamic> assigneeCandidateJson(
  String id,
  String displayName, {
  String employeeNo = 'E-1',
  List<Map<String, dynamic>> skills = const [],
}) =>
    {
      'id': id,
      'employeeNo': employeeNo,
      'displayName': displayName,
      'skills': skills,
    };

/// One row of `GET /api/people/employees` (issue #86) — mirrors
/// `toEmployeeListingRow` (directory.js) exactly: `toEmployee`'s own fields
/// plus the current Org Unit and current job role (issue #91), each `{id,
/// name}` or null when there is nothing to resolve. See `Employee`'s own
/// header (`lib/people/employee.dart`).
Map<String, dynamic> employeeJson(
  String id,
  String employeeNo,
  String displayName, {
  String employmentType = 'permanent',
  bool isActive = true,
  Map<String, dynamic>? orgUnit,
  Map<String, dynamic>? jobRole,
}) =>
    {
      'id': id,
      'employeeNo': employeeNo,
      'firstName': displayName.split(' ').first,
      'lastName': displayName.contains(' ') ? displayName.split(' ').last : '',
      'displayName': displayName,
      'hiredOn': '2020-01-01',
      'terminatedOn': isActive ? null : '2024-06-01',
      'employmentType': employmentType,
      'defaultOrgUnitId': null,
      'defaultCrewId': null,
      'costCenterId': null,
      'isActive': isActive,
      'workEmail': null,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      'orgUnit': orgUnit,
      'jobRole': jobRole,
    };

/// One row of an Employee's Assignment history, as `getAssignmentHistory`
/// (directory.js) sends it, nested under `GET /api/people/employees/:id`'s
/// own `assignments`.
Map<String, dynamic> employeeAssignmentJson(
  String id, {
  required String orgUnitId,
  required String orgUnitName,
  String? jobRoleId,
  String? jobRoleName,
  required bool isCurrent,
  String effectiveFrom = '2024-01-01',
  String? effectiveTo,
}) =>
    {
      'id': id,
      'effectiveFrom': effectiveFrom,
      'effectiveTo': effectiveTo,
      'isCurrent': isCurrent,
      'crewId': null,
      'orgUnit': {
        'id': orgUnitId,
        'code': orgUnitName.toUpperCase().replaceAll(' ', '-'),
        'name': orgUnitName,
      },
      'jobRole': jobRoleId == null
          ? null
          : {'id': jobRoleId, 'code': jobRoleName!.toUpperCase().replaceAll(' ', '-'), 'name': jobRoleName},
    };

/// One skill on `GET /api/people/employees/:id`'s own `skills` — `isLapsed`
/// is sent explicitly now (issue #91): `getEmployeeDetail` (directory.js)
/// derives it server-side, the same way `listAssigneeCandidates` already
/// does, so a test scripts it directly rather than relying on the client to
/// infer it from `expiresOn` against the device clock.
Map<String, dynamic> employeeSkillJson(
  String id,
  String skillId,
  String code,
  String name, {
  int proficiencyLevel = 3,
  String? expiresOn,
  bool isLapsed = false,
}) =>
    {
      'id': id,
      'proficiencyLevel': proficiencyLevel,
      'assessedOn': '2024-01-01',
      'expiresOn': expiresOn,
      'isLapsed': isLapsed,
      'skill': {'id': skillId, 'code': code, 'name': name},
    };

/// The full body of `GET /api/people/employees/:id` and
/// `GET /api/people/employees/me` (issue #86) — the Employee's own fields
/// ([employeeJson]) plus `jobRole`, `assignments` and `skills`.
Map<String, dynamic> employeeDetailJson(
  String id,
  String employeeNo,
  String displayName, {
  String employmentType = 'permanent',
  bool isActive = true,
  Map<String, dynamic>? jobRole,
  List<Map<String, dynamic>> assignments = const [],
  List<Map<String, dynamic>> skills = const [],
}) =>
    {
      ...employeeJson(id, employeeNo, displayName, employmentType: employmentType, isActive: isActive),
      'jobRole': jobRole,
      'assignments': assignments,
      'skills': skills,
    };

/// One row of `GET /api/people/job-roles` (`job-roles.js`'s own `toJobRole`).
Map<String, dynamic> jobRoleJson(String id, String code, String name, {bool isActive = true}) => {
      'id': id,
      'code': code,
      'name': name,
      'isActive': isActive,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };

/// One row of `GET /api/people/skills` (`skills.js`'s own `toSkill`, issue
/// #89). `orgUnitId` is sent by the real route but carried by no model on
/// this client (`Skill`'s own header) — omitted here for the same reason.
Map<String, dynamic> skillJson(
  String id,
  String code,
  String name, {
  String skillCategory = 'operation',
  bool requiresCertification = false,
  int? revalidationMonths,
  bool isActive = true,
}) =>
    {
      'id': id,
      'code': code,
      'name': name,
      'skillCategory': skillCategory,
      'orgUnitId': null,
      'requiresCertification': requiresCertification,
      'revalidationMonths': revalidationMonths,
      'isActive': isActive,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };

/// One row of `GET /api/people/skills/:id/qualified-employees`
/// (`listQualifiedEmployees`, skills.js, issue #89) — already excludes a
/// lapsed qualification server-side (`QUALIFICATION_IS_CURRENT_SQL`), so
/// there is no `isLapsed` flag on this shape at all, unlike `heldSkillJson`/
/// `employeeSkillJson` beside it.
Map<String, dynamic> qualifiedEmployeeJson(
  String id,
  String employeeNo,
  String displayName, {
  int proficiencyLevel = 3,
  String? expiresOn,
}) =>
    {
      'id': id,
      'employeeNo': employeeNo,
      'displayName': displayName,
      'proficiencyLevel': proficiencyLevel,
      'assessedOn': '2024-01-01',
      'expiresOn': expiresOn,
    };

/// One row of `GET /api/people/sites/:siteId/skill-coverage`
/// (`getSiteSkillCoverage`, skills.js, issue #89) — already filtered to
/// `shortfall > 0` server-side, so every row this fixture builds is thin by
/// construction, the same way the real view's own filter guarantees it.
Map<String, dynamic> skillCoverageEntryJson(
  String orgUnitId,
  String orgUnitName,
  String skillId,
  String skillCode,
  String skillName, {
  int minimumLevel = 1,
  int minimumQualifiedHeadcount = 2,
  int qualifiedHeadcount = 0,
  int expiredHeadcount = 0,
  int shortfall = 2,
}) =>
    {
      'orgUnitId': orgUnitId,
      'orgUnitCode': orgUnitName.toUpperCase().replaceAll(' ', '-'),
      'orgUnitName': orgUnitName,
      'skillId': skillId,
      'skillCode': skillCode,
      'skillName': skillName,
      'minimumLevel': minimumLevel,
      'minimumQualifiedHeadcount': minimumQualifiedHeadcount,
      'qualifiedHeadcount': qualifiedHeadcount,
      'expiredHeadcount': expiredHeadcount,
      'shortfall': shortfall,
    };

/// One unit of measure as `GET /api/maintenance/units-of-measure` sends it
/// (issue #80) — the existing baseline catalogue the Part form chooses from.
Map<String, dynamic> unitOfMeasureJson(String code, String name, {String dimension = 'count'}) => {
      'code': code,
      'name': name,
      'dimension': dimension,
    };

/// One Part as `GET /api/maintenance/parts` sends it (issue #80) — mirrors
/// `toPart` (inventory.js) key for key.
Map<String, dynamic> partJson(
  String id,
  String partNo,
  String description, {
  String uomCode = 'EA',
  bool isActive = true,
}) =>
    {
      'id': id,
      'partNo': partNo,
      'description': description,
      'uomCode': uomCode,
      'isActive': isActive,
    };

/// One Store as `GET /api/maintenance/sites/:siteId/stores` and
/// `GET /api/maintenance/stores/:id` send it (issue #80) — mirrors `toStore`
/// (inventory.js) key for key.
Map<String, dynamic> storeJson(
  String id,
  String code,
  String name, {
  String siteId = '1',
  String orgUnitId = '10',
  String orgUnitName = 'Line 1',
  bool isActive = true,
}) =>
    {
      'id': id,
      'siteId': siteId,
      'orgUnitId': orgUnitId,
      'orgUnitName': orgUnitName,
      'code': code,
      'name': name,
      'isActive': isActive,
    };

/// One row of a store's stock as `GET
/// /api/maintenance/stores/:storeId/stock` sends it (issue #80) — mirrors
/// `toStockLevel` (inventory.js) key for key.
Map<String, dynamic> stockLevelJson(
  String partId,
  String partNo,
  String description,
  num quantity, {
  String uomCode = 'EA',
}) =>
    {
      'partId': partId,
      'partNo': partNo,
      'description': description,
      'uomCode': uomCode,
      'quantity': quantity,
    };

Map<String, dynamic> pendingJson(
  String id,
  String email,
  DateTime since, {
  Map<String, dynamic>? suggestedEmployee,
}) =>
    {
      'id': id,
      'email': email,
      'createdAt': since.toUtc().toIso8601String(),
      'suggestedEmployee': suggestedEmployee,
    };

/// The minimal Employee reference `GET /accounts/pending`'s own
/// `suggestedEmployee` sends (issue #116, ADR-0022) — `{id, employeeNo,
/// displayName}`, nothing else.
Map<String, dynamic> suggestedEmployeeJson(String id, String employeeNo, String displayName) =>
    {'id': id, 'employeeNo': employeeNo, 'displayName': displayName};

/// The Account left linked to a just-Departed Employee, as
/// `POST .../departure`'s own `linkedAccount` sends it (issue #116,
/// ADR-0022).
Map<String, dynamic> linkedAccountJson(String id, String email, {bool isActive = true}) =>
    {'id': id, 'email': email, 'isActive': isActive};

Map<String, dynamic> siteJson(
  String id,
  String code,
  String name, {
  String timezone = 'Europe/London',
  String? countryCode,
}) =>
    {
      'id': id,
      'code': code,
      'name': name,
      'timezone': timezone,
      'countryCode': countryCode,
    };

/// An Org Unit row exactly as `plant.js` sends one — `parentId` included,
/// because a root-level response can legitimately carry a non-null one.
Map<String, dynamic> orgUnitJson(
  String id,
  String name, {
  String? parentId,
  String unitType = 'area',
  String? path,
  List<Map<String, String>> ancestors = const [],
}) {
  final row = <String, dynamic>{
    'id': id,
    'parentId': parentId,
    'code': name.toUpperCase().replaceAll(' ', '-'),
    'name': name,
    'unitType': unitType,
    // Real rows carry the full root-first ancestor chain (`n<id>.n<id>...`,
    // issue #130) — a caller revealing a deeply nested search hit passes
    // its own [path] explicitly; the bare id is only a fixture default for
    // the many existing tests that never look past this node's own row.
    'path': path ?? id,
    'sortOrder': 0,
    'isActive': true,
  };
  // Only the search route resolves ancestors (`plant.searchOrgUnits`, issue
  // #145, ADR-0024); a browsed level's response omits the key entirely, so
  // this fake does too — which is what exercises the client's absent-key
  // fallback in `_orgUnitNodeFrom`. A search fixture that cares about a hit's
  // breadcrumb passes `ancestors` explicitly.
  if (ancestors.isNotEmpty) {
    row['ancestors'] = ancestors;
  }
  return row;
}

/// One Account as `GET /api/people/accounts` sends it.
Map<String, dynamic> accountJson(
  String id,
  String email, {
  String role = Roles.operator,
  bool isActive = true,
  String approvalStatus = 'approved',
  List<Map<String, dynamic>> grants = const [],
  DateTime? createdAt,
  String? employeeId,
}) =>
    {
      'id': id,
      'email': email,
      'displayName': email.split('@').first,
      'role': role,
      'isActive': isActive,
      'approvalStatus': approvalStatus,
      'grants': grants,
      'createdAt': (createdAt ?? DateTime.now()).toUtc().toIso8601String(),
      'employeeId': employeeId,
    };

/// One Grant on an Account row, as the accounts listing sends it.
Map<String, dynamic> grantJson(
  String orgUnitId, {
  String name = 'Assembly',
  String siteName = 'Ho Chi Minh',
  bool canWrite = false,
}) =>
    {
      'orgUnitId': orgUnitId,
      'parentId': null,
      'code': name.toUpperCase().replaceAll(' ', '-'),
      'name': name,
      'unitType': 'area',
      'siteId': '1',
      'siteName': siteName,
      'canWrite': canWrite,
    };

/// One KPI as `GET /api/maintenance/sites/:siteId/board` sends it (issue #76).
/// `value` and `targetValue` are `number | null` on the wire: a null `value`
/// is an unmeasured KPI, never a zero.
Map<String, dynamic> boardKpiJson(
  String code,
  String name, {
  String unit = '',
  String direction = 'higher_better',
  int decimalPlaces = 1,
  String formulaText = 'a formula',
  num? value,
  required String status,
  num? targetValue,
}) =>
    {
      'code': code,
      'name': name,
      'unit': unit,
      'direction': direction,
      'decimalPlaces': decimalPlaces,
      'formulaText': formulaText,
      'value': value,
      'status': status,
      'targetValue': targetValue,
    };

/// One Pillar as the board sends it. [hasData] defaults to whether any of
/// [kpis] carries a measured `value`, the same rule the server applies.
Map<String, dynamic> boardPillarJson(
  String code,
  String name, {
  int sortOrder = 0,
  required List<Map<String, dynamic>> kpis,
  bool? hasData,
}) =>
    {
      'code': code,
      'name': name,
      'sortOrder': sortOrder,
      'hasData': hasData ?? kpis.any((kpi) => kpi['value'] != null),
      'kpis': kpis,
    };

/// The wire, faked: `/me` answers the role under test, and the queue endpoints
/// answer whatever the test scripted. Every request is recorded so a test can
/// assert what was — and was not — sent.
class FakeWire {
  FakeWire({
    this.role = Roles.admin,
    this.selfId = '1',
    List<Map<String, dynamic>>? queue,
    this.queueStatus = 200,
    this.rejectStatus = 200,
    this.approveStatus = 200,
    this.approveMessage = 'The Platform could not admit that Account.',
    this.approveCode,
    List<Map<String, dynamic>>? accounts,
    this.accountsStatus = 200,
    this.patchStatus = 200,
    this.putEmployeeLinkStatus = 200,
    this.putEmployeeLinkMessage = 'That Employee link could not be changed.',
    Map<String, Map<String, dynamic>>? employeeLinkedAccounts,
    List<Map<String, dynamic>>? sites,
    Map<String?, List<Map<String, dynamic>>>? orgUnits,
    this.sitesStatus = 200,
    this.orgUnitsStatus = 200,
    List<String>? timezones,
    this.timezonesStatus = 200,
    this.timezonesMessage = 'The timezone list is unavailable.',
    this.orgUnitScope,
    this.createSiteStatus = 201,
    this.createSiteMessage = 'a Site with this code already exists',
    this.patchSiteStatus = 200,
    this.patchSiteMessage = 'This Site already has a shift calendar, so its timezone cannot be corrected',
    this.createOrgUnitStatus = 201,
    this.createOrgUnitMessage = 'That Org Unit could not be added.',
    this.patchOrgUnitStatus = 200,
    this.patchOrgUnitMessage = 'That Org Unit could not be changed.',
    List<Map<String, dynamic>>? orgUnitSearchResults,
    this.orgUnitSearchStatus = 200,
    this.orgUnitSearchTruncated = false,
    this.importOrgUnitsStatus = 201,
    this.importOrgUnitsMessage = 'The import contains invalid rows',
    List<Map<String, dynamic>>? importOrgUnitsErrors,
    Map<String, List<Map<String, dynamic>>>? assets,
    this.assetsStatus = 200,
    this.createAssetStatus = 201,
    this.createAssetMessage = 'an Asset with this code already exists',
    this.patchAssetStatus = 200,
    this.patchAssetMessage = 'That Asset could not be changed.',
    Map<String, List<Map<String, dynamic>>>? workOrders,
    this.workOrdersStatus = 200,
    this.createWorkOrderStatus = 201,
    this.createWorkOrderMessage = 'That Work order could not be raised.',
    List<Map<String, dynamic>>? assigneeCandidates,
    this.assigneeCandidatesStatus = 200,
    this.assignWorkOrderStatus = 200,
    this.assignWorkOrderMessage = 'That Work order could not be assigned.',
    this.startWorkOrderStatus = 200,
    this.startWorkOrderMessage = 'That Work order could not be started.',
    this.completeWorkOrderStatus = 200,
    this.completeWorkOrderMessage = 'That Work order could not be completed.',
    this.cancelWorkOrderStatus = 200,
    this.cancelWorkOrderMessage = 'That Work order could not be cancelled.',
    Map<String, List<Map<String, dynamic>>>? triageRequests,
    this.requestsStatus = 200,
    Map<String, List<Map<String, dynamic>>>? myRequests,
    this.myRequestsStatus = 200,
    this.createRequestStatus = 201,
    this.createRequestMessage = 'That Request could not be raised.',
    this.acceptRequestStatus = 200,
    this.acceptRequestMessage = 'That Request could not be accepted.',
    this.declineRequestStatus = 200,
    this.declineRequestMessage = 'That Request could not be declined.',
    this.duplicateRequestStatus = 200,
    this.duplicateRequestMessage = 'That Request could not be marked a duplicate.',
    Map<String, List<Map<String, dynamic>>>? downtime,
    this.downtimeStatus = 200,
    List<Map<String, dynamic>>? downtimeReasons,
    this.downtimeReasonsStatus = 200,
    this.createDowntimeStatus = 201,
    this.createDowntimeMessage = 'That Breakdown could not be reported.',
    this.closeDowntimeStatus = 200,
    this.closeDowntimeMessage = 'That stop could not be closed.',
    this.classifyDowntimeStatus = 200,
    this.classifyDowntimeMessage = 'That stop could not be classified.',
    List<Map<String, dynamic>>? employees,
    this.employeesStatus = 200,
    Map<String, Map<String, dynamic>>? employeeDetails,
    this.employeeDetailStatus = 200,
    this.employeeDetailMessage = 'That Employee record could not be read.',
    List<Map<String, dynamic>>? jobRoles,
    this.jobRolesStatus = 200,
    this.createEmployeeStatus = 201,
    this.createEmployeeMessage = 'That Employee could not be added.',
    this.updateEmployeeStatus = 200,
    this.updateEmployeeMessage = 'That Employee record could not be corrected.',
    this.departEmployeeStatus = 200,
    this.departEmployeeMessage = 'That departure could not be recorded.',
    this.reinstateEmployeeStatus = 200,
    this.reinstateEmployeeMessage = 'That Employee could not be reinstated.',
    this.createAssignmentStatus = 201,
    this.createAssignmentMessage = 'That Assignment could not be recorded.',
    this.createJobRoleStatus = 201,
    this.createJobRoleMessage = 'That job role could not be added.',
    this.updateJobRoleStatus = 200,
    this.updateJobRoleMessage = 'That job role could not be corrected.',
    List<Map<String, dynamic>>? skills,
    this.skillsStatus = 200,
    this.createSkillStatus = 201,
    this.createSkillMessage = 'That skill could not be added.',
    this.updateSkillStatus = 200,
    this.updateSkillMessage = 'That skill could not be corrected.',
    this.recordEmployeeSkillStatus = 200,
    this.recordEmployeeSkillMessage = 'That assessment could not be recorded.',
    List<Map<String, dynamic>>? qualifiedEmployees,
    this.qualifiedEmployeesStatus = 200,
    Map<String, List<Map<String, dynamic>>>? skillCoverage,
    this.skillCoverageStatus = 200,
    List<Map<String, dynamic>>? jobPlans,
    this.jobPlansStatus = 200,
    this.createJobPlanStatus = 201,
    this.createJobPlanMessage = 'That Job plan could not be added.',
    this.patchJobPlanStatus = 200,
    this.patchJobPlanMessage = 'That Job plan could not be changed.',
    Map<String, List<Map<String, dynamic>>>? pmSchedules,
    this.pmSchedulesStatus = 200,
    this.createPmScheduleStatus = 201,
    this.createPmScheduleMessage = 'That PM schedule could not be created.',
    this.patchPmScheduleStatus = 200,
    this.patchPmScheduleMessage = 'That PM schedule could not be changed.',
    Map<String, List<Map<String, dynamic>>>? workOrderTasks,
    this.workOrderDetailStatus = 200,
    this.board,
    this.boardStatus = 200,
    this.boardMessage = 'The tier board is unavailable.',
    List<Map<String, dynamic>>? parts,
    this.partsStatus = 200,
    this.createPartStatus = 201,
    this.createPartMessage = 'a Part with this part number already exists',
    List<Map<String, dynamic>>? unitsOfMeasure,
    this.unitsOfMeasureStatus = 200,
    Map<String, List<Map<String, dynamic>>>? stores,
    this.storesStatus = 200,
    Map<String, Map<String, dynamic>>? storeRows,
    Map<String, List<Map<String, dynamic>>>? stock,
    this.storeStockStatus = 200,
    this.createReceiptStatus = 201,
    this.createReceiptMessage = 'Part X has only 0 EA on the shelf; this movement would take it below zero.',
  })  : queue = queue ?? [],
        assets = assets ?? {},
        accounts = accounts ?? [],
        employeeLinkedAccounts = employeeLinkedAccounts ?? {},
        sites = sites ?? [],
        orgUnits = orgUnits ?? {},
        timezones = timezones ?? [],
        orgUnitSearchResults = orgUnitSearchResults ?? [],
        importOrgUnitsErrors = importOrgUnitsErrors ?? [],
        workOrders = workOrders ?? {},
        triageRequests = triageRequests ?? {},
        myRequests = myRequests ?? {},
        downtime = downtime ?? {},
        downtimeReasons = downtimeReasons ?? [],
        assigneeCandidates = assigneeCandidates ?? [],
        employees = employees ?? [],
        employeeDetails = employeeDetails ?? {},
        jobRoles = jobRoles ?? [],
        skills = skills ?? [],
        qualifiedEmployees = qualifiedEmployees ?? [],
        skillCoverage = skillCoverage ?? {},
        jobPlans = jobPlans ?? [],
        pmSchedules = pmSchedules ?? {},
        workOrderTasks = workOrderTasks ?? {},
        parts = parts ?? [],
        unitsOfMeasure = unitsOfMeasure ?? [unitOfMeasureJson('EA', 'Each')],
        stores = stores ?? {},
        storeRows = storeRows ?? {},
        stock = stock ?? {};

  final String role;

  /// What `/me` reports as this caller's own Org Unit scope (issue #43).
  final Map<String, dynamic>? orgUnitScope;

  /// `GET /api/maintenance/sites/:siteId/assets`, keyed by Site id.
  Map<String, List<Map<String, dynamic>>> assets;
  int assetsStatus;

  /// `POST /api/maintenance/assets`.
  int createAssetStatus;
  String createAssetMessage;

  /// Every Asset body that actually reached the wire, decoded — so a test can
  /// assert that exactly one request was sent and what Org Unit it carried.
  final List<Map<String, dynamic>> assetPosts = [];

  /// `PATCH /api/maintenance/assets/:id` — retiring, reinstating, nesting and
  /// detaching all land here (issue #61).
  int patchAssetStatus;
  String patchAssetMessage;

  /// Every Asset PATCH that actually reached the wire, as `(id, body)` — so a
  /// test can assert exactly one request was sent and what it carried.
  final List<(String, Map<String, dynamic>)> assetPatches = [];

  /// When set, an Asset PATCH hangs until the test completes it — the same
  /// device [patchGate] uses for Accounts, needed to prove a second row
  /// action while this one is in flight is reported rather than dropped.
  Completer<void>? assetPatchGate;

  /// When set, an Asset listing hangs until the test completes it.
  Completer<void>? assetsGate;

  /// `GET /api/maintenance/sites/:siteId/work-orders`, keyed by Site id.
  Map<String, List<Map<String, dynamic>>> workOrders;
  int workOrdersStatus;

  /// Overrides [workOrders] for one particular `(siteId, orgUnitId)` narrow,
  /// keyed as `'$siteId|$orgUnitId'` — set by a test that wants to prove a
  /// narrowed request answers with a different list than the whole Site's,
  /// distinct from a test that only cares whether `orgUnitId` was sent.
  final Map<String, List<Map<String, dynamic>>> workOrdersByFilter = {};

  /// Every Work order request as `(siteId, orgUnitId, includeHistory)`, so a
  /// test can prove the filter — and the history opt-in (issue #63) — was
  /// actually sent, or not, as the caller chose.
  final List<(String, String?, bool)> workOrderRequests = [];

  /// When set, a Work order listing hangs until the test completes it — the
  /// same device [assetsGate] uses, needed to prove the list shows its own
  /// placeholders while a read is still in flight.
  Completer<void>? workOrdersGate;

  /// `POST /api/maintenance/work-orders`.
  int createWorkOrderStatus;
  String createWorkOrderMessage;

  /// Every Work order body that actually reached the wire, decoded — so a
  /// test can assert exactly one request was sent and what it carried.
  final List<Map<String, dynamic>> workOrderPosts = [];

  /// `GET /api/people/employees/assignee-candidates` (issue #62).
  List<Map<String, dynamic>> assigneeCandidates;
  int assigneeCandidatesStatus;

  /// `PUT /api/maintenance/work-orders/:id/assignee`.
  int assignWorkOrderStatus;
  String assignWorkOrderMessage;

  /// Every assign request that actually reached the wire, as `(id, body)` —
  /// so a test can assert exactly one request was sent and what Employee it
  /// carried.
  final List<(String, Map<String, dynamic>)> workOrderAssignRequests = [];

  /// When set, an assign hangs until the test completes it — the same device
  /// [assetPatchGate] uses, needed to prove the assign action is not offered
  /// a second time while one is already in flight.
  Completer<void>? workOrderAssignGate;

  /// `POST /api/maintenance/work-orders/:id/start` (issue #63).
  int startWorkOrderStatus;
  String startWorkOrderMessage;

  /// `POST /api/maintenance/work-orders/:id/complete`.
  int completeWorkOrderStatus;
  String completeWorkOrderMessage;

  /// `POST /api/maintenance/work-orders/:id/cancel`.
  int cancelWorkOrderStatus;
  String cancelWorkOrderMessage;

  /// Every Work order id started, in the order the requests actually reached
  /// the wire — so a test can assert exactly one request was sent.
  final List<String> workOrderStarts = [];

  /// Every complete request that actually reached the wire, as `(id, body)`.
  final List<(String, Map<String, dynamic>)> workOrderCompletions = [];

  /// Every cancel request that actually reached the wire, as `(id, body)`.
  final List<(String, Map<String, dynamic>)> workOrderCancellations = [];

  /// When set, a start/complete/cancel hangs until the test completes it —
  /// one gate for all three transitions, the same shape [workOrderAssignGate]
  /// uses, needed to prove no transition is offered a second time while one
  /// is already in flight.
  Completer<void>? workOrderTransitionGate;

  /// `GET /api/maintenance/sites/:siteId/requests` — the triage queue, keyed
  /// by Site id.
  Map<String, List<Map<String, dynamic>>> triageRequests;
  int requestsStatus;

  /// Every triage-queue read's Site id, in the order it reached the wire.
  final List<String> triageRequestSites = [];

  /// When set, a triage-queue read hangs until the test completes it — the
  /// same device [workOrdersGate] uses, needed to prove the queue shows its
  /// own placeholders while a read is still in flight. Also gates the return
  /// from a triage action, since those routes update [triageRequests].
  Completer<void>? requestsGate;

  /// `GET /api/maintenance/sites/:siteId/requests/mine` — the caller's own
  /// Requests, keyed by Site id.
  Map<String, List<Map<String, dynamic>>> myRequests;
  int myRequestsStatus;

  /// Every my-requests read's Site id, in the order it reached the wire.
  final List<String> myRequestSites = [];

  /// When set, a my-requests read hangs until the test completes it.
  Completer<void>? myRequestsGate;

  /// `POST /api/maintenance/requests`.
  int createRequestStatus;
  String createRequestMessage;

  /// Every Request body that actually reached the wire, decoded — so a test
  /// can assert exactly one request was sent and what it carried.
  final List<Map<String, dynamic>> requestPosts = [];

  /// `POST /api/maintenance/requests/:id/accept`.
  int acceptRequestStatus;
  String acceptRequestMessage;

  /// Every accept request that actually reached the wire, as `(id, body)`.
  final List<(String, Map<String, dynamic>)> requestAccepts = [];

  /// `POST /api/maintenance/requests/:id/decline`.
  int declineRequestStatus;
  String declineRequestMessage;

  /// Every decline request that actually reached the wire, as `(id, body)`.
  final List<(String, Map<String, dynamic>)> requestDeclines = [];

  /// `POST /api/maintenance/requests/:id/duplicate`.
  int duplicateRequestStatus;
  String duplicateRequestMessage;

  /// Every duplicate request that actually reached the wire, as `(id, body)`.
  final List<(String, Map<String, dynamic>)> requestDuplicates = [];

  /// `GET /api/maintenance/sites/:siteId/downtime` — open stops by default,
  /// keyed by Site id. Mirrors the server's own default read.
  Map<String, List<Map<String, dynamic>>> downtime;
  int downtimeStatus;

  /// Every downtime read's Site id, in the order it reached the wire.
  final List<String> downtimeSites = [];

  /// When set, a downtime read hangs until the test completes it — the same
  /// device [requestsGate] uses, needed to prove the list shows its own
  /// placeholders while a read is still in flight.
  Completer<void>? downtimeGate;

  /// `GET /api/maintenance/downtime-reasons` — the classify picker's own
  /// catalogue.
  List<Map<String, dynamic>> downtimeReasons;
  int downtimeReasonsStatus;

  /// `POST /api/maintenance/downtime`.
  int createDowntimeStatus;
  String createDowntimeMessage;

  /// Every Breakdown body that actually reached the wire, decoded — so a test
  /// can assert exactly one request was sent and what Asset it carried.
  final List<Map<String, dynamic>> downtimePosts = [];

  /// `POST /api/maintenance/downtime/:id/close`.
  int closeDowntimeStatus;
  String closeDowntimeMessage;

  /// Every close request that actually reached the wire, as `(id, body)`.
  final List<(String, Map<String, dynamic>)> downtimeCloses = [];

  /// `POST /api/maintenance/downtime/:id/classify`.
  int classifyDowntimeStatus;
  String classifyDowntimeMessage;

  /// Every classify request that actually reached the wire, as `(id, body)`.
  final List<(String, Map<String, dynamic>)> downtimeClassifications = [];

  /// The caller's own Account id, as `/me` reports it — what the Accounts
  /// Screen compares each row against (issue #53).
  final String selfId;
  List<Map<String, dynamic>> queue;
  int queueStatus;
  int rejectStatus;
  int approveStatus;
  String approveMessage;

  /// The `code` alongside [approveMessage] (issue #119) — null reproduces a
  /// refusal that carries no code at all; a test that needs to drive
  /// [isEmployeeLinkRefusal]'s branching sets this to one of
  /// `EMPLOYEE_DEPARTED`, `EMPLOYEE_ALREADY_LINKED` or
  /// `APPROVAL_STATUS_CHANGED`, the same codes `service.js` sends.
  String? approveCode;

  /// `GET /api/people/accounts` — every Account, pending ones included.
  List<Map<String, dynamic>> accounts;
  int accountsStatus;

  /// `PATCH /api/people/accounts/:id`.
  int patchStatus;

  /// When set, a PATCH hangs until the test completes it — the same device
  /// [approvalGate] uses, needed to prove what happens when a second action
  /// is dispatched while this one is still in flight.
  Completer<void>? patchGate;

  /// Every activation change that reached the wire, as `(accountId, isActive)`.
  final List<(String, bool)> activations = [];

  /// `PUT /api/people/accounts/:id/employee` (issue #116, ADR-0022).
  int putEmployeeLinkStatus;
  String putEmployeeLinkMessage;

  /// Every Employee-link PUT that reached the wire, as `(accountId,
  /// employeeId)` — `employeeId` null both when the request cleared the link
  /// and (impossible to tell apart from here) when the field truly was
  /// `null`, the same "prove what was sent" idiom [employeeLinkedAccounts]'s
  /// own neighbours already use.
  final List<(String, String?)> employeeLinkPuts = [];

  /// The Account a given Employee id is linked to, as `POST
  /// .../departure`'s own `linkedAccount` reports it (issue #116, ADR-0022) —
  /// scripted per test, since this Fake Wire keeps no real link between
  /// [accounts] and [employees] the way the real schema's `employee_id`
  /// column does.
  Map<String, Map<String, dynamic>> employeeLinkedAccounts;

  /// `GET /api/people/sites`.
  List<Map<String, dynamic>> sites;
  int sitesStatus;

  /// `GET /api/people/timezones` (issue #123/#127, ADR-0023) — the whole
  /// list `SiteFormDialog` fetches once when it opens. A test asserting the
  /// fetch happened only once reads [requests] for
  /// `'GET /api/people/timezones'`, the same generic device every other
  /// once-per-open fetch in this suite already uses.
  List<String> timezones;
  int timezonesStatus;
  String timezonesMessage;

  /// `GET /api/people/sites/:id/org-units`, keyed by the `parentId` asked for
  /// — the null key is the root level, which is a different request, not a
  /// different filter over the same one.
  Map<String?, List<Map<String, dynamic>>> orgUnits;
  int orgUnitsStatus;

  /// Every Org Unit request as `(siteId, parentId)`, so a test can prove
  /// children were asked for by parent and only on expansion — and, for
  /// issue #90, by a level's own refresh after a write.
  final List<(String, String?)> orgUnitRequests = [];

  /// `POST /api/people/sites` (issue #90, administrator only).
  int createSiteStatus;
  String createSiteMessage;

  /// Every Site create body that actually reached the wire, decoded.
  final List<Map<String, dynamic>> sitePosts = [];

  /// `PATCH /api/people/sites/:id` (issue #137) — correcting a Site. The
  /// default 409 message reproduces ADR-0025's refusal, the case a widget test
  /// most needs to surface.
  int patchSiteStatus;
  String patchSiteMessage;

  /// Every Site correction that actually reached the wire, as `(siteId, body)`.
  final List<(String, Map<String, dynamic>)> sitePatches = [];

  /// `POST /api/people/sites/:siteId/org-units` (issue #90) — gated server-side
  /// by `requireOrgUnitCreateScope` (ADR-0008), not reproduced here: this Fake
  /// Wire always honours the request, the same "prove what was sent, not that
  /// the server enforced anything" idiom [employeeRequests] already follows.
  int createOrgUnitStatus;
  String createOrgUnitMessage;

  /// Every Org Unit create request as `(siteId, body)`.
  final List<(String, Map<String, dynamic>)> orgUnitPosts = [];

  /// `PATCH /api/people/org-units/:id` (issue #90) — retiring and reinstating
  /// both land here, the same single route [setOrgUnitActive] uses.
  int patchOrgUnitStatus;
  String patchOrgUnitMessage;

  /// Every Org Unit PATCH that actually reached the wire, as `(id, body)`.
  final List<(String, Map<String, dynamic>)> orgUnitPatches = [];

  /// `GET /api/people/sites/:siteId/org-units/search` (issue #90/#35) — one
  /// scripted list, the same shape [qualifiedEmployees] already uses: a test
  /// proves `search` was sent by asserting [orgUnitSearchRequests], not by
  /// asserting the list narrowed.
  List<Map<String, dynamic>> orgUnitSearchResults;
  int orgUnitSearchStatus;

  /// Whether the scripted [orgUnitSearchResults] should be reported truncated
  /// (AC5) — carried on the response exactly as `plant.searchOrgUnits` would.
  bool orgUnitSearchTruncated;

  /// Every search request as `(siteId, search)`.
  final List<(String, String?)> orgUnitSearchRequests = [];

  /// `POST /api/people/sites/:siteId/org-units/import` (issue #90, ADR-0011).
  /// `201` by default; set to `422` alongside [importOrgUnitsErrors] to prove
  /// a caller renders every row's own reason, not only the first.
  int importOrgUnitsStatus;
  String importOrgUnitsMessage;

  /// One entry per offending row (`{row, code, field, message}`,
  /// `org-unit-import.js`'s own shape) — sent back only when
  /// [importOrgUnitsStatus] is `422`.
  List<Map<String, dynamic>> importOrgUnitsErrors;

  /// Every import request as `(siteId, body)` — `body` is the whole decoded
  /// `{orgUnits: [...]}` envelope, so a test can assert exactly one request
  /// was sent and what it carried.
  final List<(String, Map<String, dynamic>)> orgUnitImportPosts = [];

  /// When set, an Approval hangs until the test completes it — which is what
  /// "in flight" means to a widget test.
  Completer<void>? approvalGate;

  final List<String> requests = [];

  /// Every Approval body that actually reached the wire, decoded.
  final List<Map<String, dynamic>> approvals = [];

  /// `GET /api/people/employees` (issue #86) — the whole Directory this Fake
  /// Wire knows about. Filtered by [FakeWire.client] itself for `search` (a
  /// case-insensitive substring of `displayName`) and `includeDeparted`
  /// (`isActive`), the two filters the wire has enough on a row to honour
  /// honestly, plus `limit` (issue #123/#128 — `AppSearchField`'s own
  /// suggestion fetch), applied the same way `listEmployees`'s own SQL `LIMIT`
  /// does: after every other filter, truncating the match set rather than the
  /// whole Directory; `orgUnitId` and `jobRoleId` are recorded on
  /// [employeeRequests] but not applied — the real `listEmployees` filters by
  /// a current Assignment this Fake Wire has no equivalent row for (Employee
  /// rows carry no Org Unit or job role at all — see `Employee`'s own
  /// header), so a test proves those two filters by asserting what was SENT,
  /// not by asserting the list narrowed.
  List<Map<String, dynamic>> employees;
  int employeesStatus;

  /// Every `GET /api/people/employees` request's query parameters, in the
  /// order they reached the wire. `limit` (issue #123) is carried through
  /// exactly as sent, unparsed — a test that cares whether a caller bounded
  /// its own fetch asserts this key directly rather than the (unfiltered)
  /// [employees] list length.
  final List<Map<String, String?>> employeeRequests = [];

  /// `GET /api/people/employees/:id` and `GET /api/people/employees/me`,
  /// keyed by Employee id — `'me'` is the key `GET .../me` itself is served
  /// from, distinct from any real Employee id.
  Map<String, Map<String, dynamic>> employeeDetails;
  int employeeDetailStatus;
  String employeeDetailMessage;

  /// `GET /api/people/job-roles`.
  List<Map<String, dynamic>> jobRoles;
  int jobRolesStatus;

  /// `POST /api/people/employees` (issue #87, administrator only).
  int createEmployeeStatus;
  String createEmployeeMessage;

  /// Every create body that actually reached the wire, decoded — so a test
  /// can assert exactly one request was sent and what it carried.
  final List<Map<String, dynamic>> employeePosts = [];

  /// `PATCH /api/people/employees/:id`.
  int updateEmployeeStatus;
  String updateEmployeeMessage;

  /// Every correction body that actually reached the wire, as `(id, body)` —
  /// so a test can assert exactly one request was sent and that it carried
  /// only the field that actually changed.
  final List<(String, Map<String, dynamic>)> employeePatches = [];

  /// `POST /api/people/employees/:id/departure`.
  int departEmployeeStatus;
  String departEmployeeMessage;

  /// Every departure body that actually reached the wire, as `(id, body)`.
  final List<(String, Map<String, dynamic>)> employeeDepartures = [];

  /// `POST /api/people/employees/:id/reinstatement`.
  int reinstateEmployeeStatus;
  String reinstateEmployeeMessage;

  /// Every Employee id reinstated, in the order the requests reached the wire.
  final List<String> employeeReinstatements = [];

  /// `POST /api/people/employees/:id/assignments` (issue #88) — not
  /// administrator only, unlike every write above (ADR-0010).
  int createAssignmentStatus;
  String createAssignmentMessage;

  /// Every assignment body that actually reached the wire, as `(employeeId,
  /// body)` — so a test can assert exactly one request was sent and what it
  /// carried.
  final List<(String, Map<String, dynamic>)> assignmentPosts = [];

  /// `POST /api/people/job-roles` (issue #88, administrator only).
  int createJobRoleStatus;
  String createJobRoleMessage;

  /// Every job role create body that actually reached the wire, decoded.
  final List<Map<String, dynamic>> jobRolePosts = [];

  /// `PATCH /api/people/job-roles/:id` (issue #88, administrator only).
  int updateJobRoleStatus;
  String updateJobRoleMessage;

  /// Every job role correction body that actually reached the wire, as
  /// `(id, body)`.
  final List<(String, Map<String, dynamic>)> jobRolePatches = [];

  /// `GET /api/people/skills` (issue #89).
  List<Map<String, dynamic>> skills;
  int skillsStatus;

  /// `POST /api/people/skills` (administrator only).
  int createSkillStatus;
  String createSkillMessage;

  /// Every skill create body that actually reached the wire, decoded.
  final List<Map<String, dynamic>> skillPosts = [];

  /// `PATCH /api/people/skills/:id` (administrator only).
  int updateSkillStatus;
  String updateSkillMessage;

  /// Every skill correction body that actually reached the wire, as
  /// `(id, body)`.
  final List<(String, Map<String, dynamic>)> skillPatches = [];

  /// `PUT /api/people/employees/:id/skills/:skillId` — an upsert, so a
  /// second call for the same pair is a re-assessment, not a duplicate
  /// (skill-routes.js's own header). Administrator only.
  int recordEmployeeSkillStatus;
  String recordEmployeeSkillMessage;

  /// Every assessment PUT that actually reached the wire, as
  /// `(employeeId, skillId, body)` — so a test can assert exactly one
  /// request was sent, and that a re-assessment sent the same PUT rather
  /// than a second, different one.
  final List<(String, String, Map<String, dynamic>)> employeeSkillPuts = [];

  /// `GET /api/people/skills/:id/qualified-employees` — one scripted list,
  /// same shape [assigneeCandidates] already uses: a test proves `orgUnitId`
  /// and `minimumLevel` were sent by asserting [qualifiedEmployeeRequests],
  /// not by asserting the list narrowed.
  List<Map<String, dynamic>> qualifiedEmployees;
  int qualifiedEmployeesStatus;

  /// Every qualified-employees request as `(skillId, orgUnitId,
  /// minimumLevel)`.
  final List<(String, String?, String?)> qualifiedEmployeeRequests = [];

  /// `GET /api/people/sites/:siteId/skill-coverage`, keyed by Site id
  /// (administrator only).
  Map<String, List<Map<String, dynamic>>> skillCoverage;
  int skillCoverageStatus;

  /// Every Site id a coverage report was asked for, in the order the
  /// requests reached the wire.
  final List<String> skillCoverageRequests = [];

  /// `GET /api/maintenance/job-plans` (issue #74) — the shared catalogue,
  /// deactivated rows included by default, the same shape the real route's
  /// own includeInactive handling follows.
  List<Map<String, dynamic>> jobPlans;
  int jobPlansStatus;

  /// `POST /api/maintenance/job-plans` (administrator only).
  int createJobPlanStatus;
  String createJobPlanMessage;

  /// Every Job plan create body that actually reached the wire, decoded — so a
  /// test can assert exactly one request was sent and what tasks and Skill it
  /// carried.
  final List<Map<String, dynamic>> jobPlanPosts = [];

  /// `PATCH /api/maintenance/job-plans/:id` (administrator only) — deactivate
  /// and reactivate both land here.
  int patchJobPlanStatus;
  String patchJobPlanMessage;

  /// Every Job plan PATCH that reached the wire, as `(id, body)`.
  final List<(String, Map<String, dynamic>)> jobPlanPatches = [];

  /// When set, a Job plan read hangs until the test completes it — the same
  /// device [downtimeGate] uses, needed to prove the list shows placeholders
  /// while a read is in flight.
  Completer<void>? jobPlansGate;

  /// `GET /api/maintenance/sites/:siteId/pm-schedules`, keyed by Site id.
  Map<String, List<Map<String, dynamic>>> pmSchedules;
  int pmSchedulesStatus;

  /// `POST /api/maintenance/pm-schedules`.
  int createPmScheduleStatus;
  String createPmScheduleMessage;

  /// Every PM schedule create body that actually reached the wire, decoded.
  final List<Map<String, dynamic>> pmSchedulePosts = [];

  /// `PATCH /api/maintenance/pm-schedules/:id` — deactivate and reactivate
  /// both land here.
  int patchPmScheduleStatus;
  String patchPmScheduleMessage;

  /// Every PM schedule PATCH that reached the wire, as `(id, body)`.
  final List<(String, Map<String, dynamic>)> pmSchedulePatches = [];

  /// When set, a PM schedule read hangs until the test completes it.
  Completer<void>? pmSchedulesGate;

  /// `GET /api/maintenance/work-orders/:id` (issue #74) — the tasks copied
  /// onto each Work order, keyed by Work order id, merged onto whatever row
  /// [workOrders] holds for the same id.
  Map<String, List<Map<String, dynamic>>> workOrderTasks;
  int workOrderDetailStatus;

  /// Every Work order id a detail read was made for, in the order the
  /// requests reached the wire.
  final List<String> workOrderDetailRequests = [];

  /// When set, a Work order detail read hangs until the test completes it.
  Completer<void>? workOrderDetailGate;

  /// `GET /api/maintenance/sites/:siteId/board` (issue #76) — the scripted
  /// board body, or null for an empty board (no Pillars). The Site, Org Unit,
  /// period and date the request carried are scripted onto the body by the
  /// test; this fake answers the same body whoever asks.
  Map<String, dynamic>? board;
  int boardStatus;
  String boardMessage;

  /// Every board read as `(siteId, orgUnitId, periodType, date)`, in the order
  /// the requests reached the wire — so a test can prove a control change sent
  /// exactly one request carrying the new value.
  final List<(String, String?, String, String?)> boardRequests = [];

  /// When set, a board read hangs until the test completes it — the same
  /// device [pmSchedulesGate] uses, needed to prove the board shows its own
  /// placeholder while a read is still in flight.
  Completer<void>? boardGate;

  /// `GET /api/maintenance/parts` (issue #80) — the shared catalogue.
  List<Map<String, dynamic>> parts;
  int partsStatus;

  /// `POST /api/maintenance/parts` (administrator only).
  int createPartStatus;
  String createPartMessage;

  /// Every Part body that actually reached the wire, decoded — so a test can
  /// assert exactly one request was sent and what it carried.
  final List<Map<String, dynamic>> partPosts = [];

  /// `GET /api/maintenance/units-of-measure` — the Part form's own picker.
  List<Map<String, dynamic>> unitsOfMeasure;
  int unitsOfMeasureStatus;

  /// `GET /api/maintenance/sites/:siteId/stores`, keyed by Site id.
  Map<String, List<Map<String, dynamic>>> stores;
  int storesStatus;

  /// Every Site id a stores read was made for, in the order it reached the
  /// wire.
  final List<String> storeSites = [];

  /// The single store rows `GET /api/maintenance/stores/:id` and
  /// `GET /api/maintenance/stores/:id/stock` answer with, keyed by store id.
  Map<String, Map<String, dynamic>> storeRows;

  /// `GET /api/maintenance/stores/:storeId/stock`, keyed by store id.
  Map<String, List<Map<String, dynamic>>> stock;
  int storeStockStatus;

  /// Every stock read's store id, in the order it reached the wire.
  final List<String> stockReads = [];

  /// `POST /api/maintenance/stores/:storeId/receipts`.
  int createReceiptStatus;
  String createReceiptMessage;

  /// Every receipt that actually reached the wire, as `(storeId, body)` — so a
  /// test can assert exactly one request was sent and what it carried.
  final List<(String, Map<String, dynamic>)> receiptPosts = [];

  int _nextEmployeeId = 900;
  int _nextAssignmentId = 500;
  int _nextJobRoleId = 950;
  int _nextSkillId = 970;
  int _nextEmployeeSkillId = 800;
  int _nextSiteId = 90;
  int _nextOrgUnitId = 990;

  /// The Org Unit name for [orgUnitId], resolved off whatever tree rows this
  /// Fake Wire was given (any `parentId` key) — there is no Org Unit lookup
  /// endpoint for this client to call instead, the same reason
  /// `GrantedOrgUnit.where` (org_unit.dart) has no better source either.
  String _orgUnitNameFor(String orgUnitId) {
    for (final nodes in orgUnits.values) {
      for (final node in nodes) {
        if (node['id'] == orgUnitId) return node['name'] as String;
      }
    }
    return 'Org Unit $orgUnitId';
  }

  String? _jobRoleNameFor(String? jobRoleId) {
    if (jobRoleId == null) return null;
    for (final jobRole in jobRoles) {
      if (jobRole['id'] == jobRoleId) return jobRole['name'] as String;
    }
    return null;
  }

  /// Mirrors `createAssignment`'s own transfer semantics (directory.js): the
  /// Employee's currently open Assignment (`effectiveTo == null`), if there is
  /// one, is closed with the new row's own `effectiveFrom`; the new
  /// Assignment is inserted as current. Applied to every `employeeDetails`
  /// entry naming this Employee, the same `_applyEmployeeChanges` shape uses.
  Map<String, dynamic> _applyAssignment(String employeeId, Map<String, dynamic> body) {
    final orgUnitId = body['orgUnitId'] as String;
    final jobRoleId = body['jobRoleId'] as String?;
    final effectiveFrom = body['effectiveFrom'] as String;
    final newId = (_nextAssignmentId++).toString();

    final created = employeeAssignmentJson(
      newId,
      orgUnitId: orgUnitId,
      orgUnitName: _orgUnitNameFor(orgUnitId),
      jobRoleId: jobRoleId,
      jobRoleName: _jobRoleNameFor(jobRoleId),
      isCurrent: true,
      effectiveFrom: effectiveFrom,
    );

    Map<String, dynamic> close(Map<String, dynamic> detail) {
      final existing = (detail['assignments'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>();
      final closed = [
        for (final assignment in existing)
          if (assignment['effectiveTo'] == null)
            {...assignment, 'effectiveTo': effectiveFrom, 'isCurrent': false}
          else
            assignment,
      ];
      return {...detail, 'assignments': [created, ...closed]};
    }

    employeeDetails = {
      for (final entry in employeeDetails.entries)
        entry.key: entry.value['id'] == employeeId ? close(entry.value) : entry.value,
    };

    return created;
  }

  /// The skill's own `(code, name)` for [skillId], resolved off whatever
  /// catalogue this Fake Wire was given — the same "no lookup endpoint, so
  /// resolve off what is already on hand" idiom [_orgUnitNameFor] follows.
  (String, String) _skillCodeNameFor(String skillId) {
    for (final skill in skills) {
      if (skill['id'] == skillId) return (skill['code'] as String, skill['name'] as String);
    }
    return ('SKILL-$skillId', 'Skill $skillId');
  }

  /// A lapsed qualification the same way `QUALIFICATION_IS_CURRENT_SQL`
  /// decides it server-side: expired against *today*, an expiry of null
  /// meaning "never expires". Mirrors the real trigger's own reasoning
  /// closely enough for this Fake Wire's own upsert below to answer an
  /// honest `isLapsed` after a PUT — a widget test that cares about a
  /// *specific* lapsed row still scripts `isLapsed` explicitly on
  /// `employeeSkillJson` rather than relying on this.
  bool _isLapsedFor(String? expiresOn) {
    if (expiresOn == null) return false;
    final expiry = DateTime.tryParse(expiresOn);
    if (expiry == null) return false;
    final today = DateTime.now();
    return expiry.isBefore(DateTime(today.year, today.month, today.day));
  }

  /// Records, or re-assesses, an Employee holding a skill — mirrors
  /// `recordEmployeeSkill`'s own upsert (skills.js): a second call for the
  /// same `(employeeId, skillId)` pair updates the existing row in place
  /// rather than appending a duplicate. Applied to every `employeeDetails`
  /// entry naming this Employee, the same shape [_applyAssignment] uses.
  /// Returns the bare `employeeSkill` row, the same shape the real route's
  /// own response carries — unused by `PeopleApi.recordEmployeeSkill` itself
  /// (it re-reads the record instead, per its own header), but built anyway
  /// so this Fake Wire answers something shaped like the real response.
  Map<String, dynamic> _applyEmployeeSkill(String employeeId, String skillId, Map<String, dynamic> body) {
    final (code, name) = _skillCodeNameFor(skillId);
    final proficiencyLevel = body['proficiencyLevel'] as int;
    final expiresOn = body['expiresOn'] as String?;
    final isLapsed = _isLapsedFor(expiresOn);

    Map<String, dynamic>? existingRow;
    for (final detail in employeeDetails.values) {
      if (detail['id'] != employeeId) continue;
      for (final row in (detail['skills'] as List<dynamic>? ?? const [])) {
        final mapped = row as Map<String, dynamic>;
        if ((mapped['skill'] as Map<String, dynamic>)['id'] == skillId) existingRow = mapped;
      }
    }
    final rowId = (existingRow?['id'] as String?) ?? (_nextEmployeeSkillId++).toString();
    final updated = employeeSkillJson(
      rowId,
      skillId,
      code,
      name,
      proficiencyLevel: proficiencyLevel,
      expiresOn: expiresOn,
      isLapsed: isLapsed,
    );

    Map<String, dynamic> upsert(Map<String, dynamic> detail) {
      final existing = (detail['skills'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
      final matchedIndex =
          existing.indexWhere((row) => (row['skill'] as Map<String, dynamic>)['id'] == skillId);
      final rows = [...existing];
      if (matchedIndex >= 0) {
        rows[matchedIndex] = updated;
      } else {
        rows.add(updated);
      }
      return {...detail, 'skills': rows};
    }

    employeeDetails = {
      for (final entry in employeeDetails.entries)
        entry.key: entry.value['id'] == employeeId ? upsert(entry.value) : entry.value,
    };

    return updated;
  }

  /// Applies a triage action's own changes to every Request row this Fake Wire
  /// holds naming [id] — both the triage queue ([triageRequests]) and the caller's
  /// own list ([myRequests]) — so a re-read honestly shows the change. Returns
  /// the updated row, or null when no list holds it.
  Map<String, dynamic>? _applyRequestChanges(String id, Map<String, dynamic> changes) {
    Map<String, dynamic>? updated;
    Map<String, List<Map<String, dynamic>>> apply(Map<String, List<Map<String, dynamic>>> source) => {
          for (final entry in source.entries)
            entry.key: [
              for (final row in entry.value)
                if (row['id'] == id) (updated = {...row, ...changes}) else row,
            ],
        };
    triageRequests = apply(triageRequests);
    myRequests = apply(myRequests);
    return updated;
  }

  /// Applies a downtime action's own changes to every Downtime event row this
  /// Fake Wire holds naming [id], across every Site's list. Returns the updated
  /// row, or null when no list holds it — so a close/classify response honestly
  /// carries the updated row the real server would send.
  Map<String, dynamic>? _applyDowntimeChanges(String id, Map<String, dynamic> changes) {
    Map<String, dynamic>? updated;
    downtime = {
      for (final entry in downtime.entries)
        entry.key: [
          for (final row in entry.value)
            if (row['id'] == id) (updated = {...row, ...changes}) else row,
        ],
    };
    return updated;
  }

  /// The Site whose Asset register holds [assetId], so a reported Breakdown
  /// lands in the same Site's list — the Fake Wire keeps no real Assets-to-Site
  /// link beyond [assets] itself.
  String? _siteOfAsset(String assetId) {
    for (final entry in assets.entries) {
      for (final asset in entry.value) {
        if (asset['id'] == assetId) return entry.key;
      }
    }
    return null;
  }

  /// The Downtime event row this Fake Wire holds naming [id], or null.
  Map<String, dynamic>? _downtimeRow(String id) {
    for (final list in downtime.values) {
      for (final row in list) {
        if (row['id'] == id) return row;
      }
    }
    return null;
  }

  /// Applies a write's own changes to every row this Fake Wire holds naming
  /// [id] — both [employees] (the listing) and [employeeDetails] (the detail
  /// view, keyed by id or by `'me'`) — so a re-read after a successful write,
  /// exactly what `DirectoryBloc`/`EmployeeDetailBloc` do rather than splice
  /// the write's own bare response in, actually shows the change.
  void _applyEmployeeChanges(String id, Map<String, dynamic> changes) {
    Map<String, dynamic> merge(Map<String, dynamic> row) {
      final merged = {...row, ...changes};
      // `display_name` is a Postgres GENERATED column (`first_name || ' ' ||
      // last_name`, baseline migration) — recomputed here so a correction to
      // either name is honestly reflected, the same way the real column
      // would be, rather than left stale until some unrelated field changed.
      if (changes.containsKey('firstName') || changes.containsKey('lastName')) {
        merged['displayName'] = '${merged['firstName']} ${merged['lastName']}';
      }
      return merged;
    }

    employees = [
      for (final e in employees)
        if (e['id'] == id) merge(e) else e,
    ];
    employeeDetails = {
      for (final entry in employeeDetails.entries)
        entry.key: entry.value['id'] == id ? merge(entry.value) : entry.value,
    };
  }

  http.Client get client => MockClient((request) async {
        final path = request.url.path;
        requests.add('${request.method} $path');
        if (path == '/api/people/me') {
          return http.Response(jsonEncode(_meBody(role, selfId, orgUnitScope)), 200);
        }
        if (path.startsWith('/api/maintenance/sites/') && path.endsWith('/board')) {
          final siteId = path.split('/')[4];
          final orgUnitId = request.url.queryParameters['orgUnitId'];
          final periodType = request.url.queryParameters['periodType'] ?? '';
          final date = request.url.queryParameters['date'];
          boardRequests.add((siteId, orgUnitId, periodType, date));
          if (boardGate != null) await boardGate!.future;
          if (boardStatus != 200) {
            return http.Response(jsonEncode({'message': boardMessage}), boardStatus);
          }
          return http.Response(
            jsonEncode(
              board ??
                  {
                    'site': {'id': siteId, 'name': 'Site', 'timezone': 'Europe/London'},
                    'orgUnit': null,
                    'period': {'type': periodType, 'start': '2026-01-01', 'end': '2026-01-01'},
                    'pillars': const <dynamic>[],
                  },
            ),
            200,
          );
        }
        if (path == '/api/maintenance/downtime-reasons') {
          if (downtimeReasonsStatus != 200) {
            return http.Response(
              jsonEncode({'message': 'The downtime reasons are unavailable.'}),
              downtimeReasonsStatus,
            );
          }
          return http.Response(jsonEncode({'downtimeReasons': downtimeReasons}), 200);
        }
        if (path.startsWith('/api/maintenance/sites/') && path.endsWith('/downtime')) {
          final siteId = path.split('/')[4];
          downtimeSites.add(siteId);
          if (downtimeGate != null) await downtimeGate!.future;
          if (downtimeStatus != 200) {
            return http.Response(
              jsonEncode({'message': 'The downtime events are unavailable.'}),
              downtimeStatus,
            );
          }
          final includeClosed = request.url.queryParameters['includeClosed'] == 'true';
          final siteEvents = downtime[siteId] ?? [];
          // Mirrors the server's own default read: a closed stop is out unless
          // history was asked for by name.
          final sent = includeClosed
              ? siteEvents
              : [
                  for (final event in siteEvents)
                    if (event['endedAt'] == null) event,
                ];
          return http.Response(jsonEncode({'downtimeEvents': sent}), 200);
        }
        if (request.method == 'POST' && path == '/api/maintenance/downtime') {
          final sent = jsonDecode(request.body) as Map<String, dynamic>;
          downtimePosts.add(sent);
          if (createDowntimeStatus != 201) {
            return http.Response(jsonEncode({'message': createDowntimeMessage}), createDowntimeStatus);
          }
          final startedAt = sent['startedAt'] as String?;
          final created = downtimeJson(
            '900',
            assetId: sent['assetId'] as String,
            startedAt: startedAt == null ? null : DateTime.parse(startedAt),
            description: sent['description'] as String?,
          );
          final siteId = _siteOfAsset(created['assetId'] as String);
          if (siteId != null) {
            downtime = {
              ...downtime,
              siteId: [created, ...(downtime[siteId] ?? [])],
            };
          }
          final workOrder = workOrderJson('900', 'WO-900', 'Breakdown');
          return http.Response(
            jsonEncode({'downtimeEvent': created, 'workOrder': workOrder}),
            201,
          );
        }
        if (request.method == 'POST' &&
            path.startsWith('/api/maintenance/downtime/') &&
            path.endsWith('/close')) {
          final id = path.split('/')[4];
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          downtimeCloses.add((id, body));
          if (closeDowntimeStatus != 200) {
            return http.Response(jsonEncode({'message': closeDowntimeMessage}), closeDowntimeStatus);
          }
          final current = _downtimeRow(id);
          if (current == null) {
            return http.Response(jsonEncode({'message': 'That Downtime event does not exist.'}), 404);
          }
          final endedAt = body['endedAt'] as String? ?? DateTime.now().toUtc().toIso8601String();
          final started = DateTime.tryParse(current['startedAt'] as String? ?? '');
          final ended = DateTime.tryParse(endedAt);
          final updated = _applyDowntimeChanges(id, {
            'endedAt': endedAt,
            'status': current['downtimeReasonId'] != null ? 'closed' : 'unclassified',
            if (started != null && ended != null)
              'durationMinutes': ended.difference(started).inMinutes,
          });
          return http.Response(jsonEncode({'downtimeEvent': updated}), 200);
        }
        if (request.method == 'POST' &&
            path.startsWith('/api/maintenance/downtime/') &&
            path.endsWith('/classify')) {
          final id = path.split('/')[4];
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          downtimeClassifications.add((id, body));
          if (classifyDowntimeStatus != 200) {
            return http.Response(
              jsonEncode({'message': classifyDowntimeMessage}),
              classifyDowntimeStatus,
            );
          }
          final current = _downtimeRow(id);
          if (current == null) {
            return http.Response(jsonEncode({'message': 'That Downtime event does not exist.'}), 404);
          }
          final reasonId = body['downtimeReasonId']?.toString();
          String? reasonName;
          for (final reason in downtimeReasons) {
            if (reason['id'].toString() == reasonId) reasonName = reason['name'] as String;
          }
          final updated = _applyDowntimeChanges(id, {
            'downtimeReasonId': reasonId,
            'downtimeReasonName': reasonName,
            if (body['description'] != null) 'description': body['description'],
            'classifiedAt': DateTime.now().toUtc().toIso8601String(),
            'status': current['endedAt'] == null ? 'open' : 'closed',
          });
          return http.Response(jsonEncode({'downtimeEvent': updated}), 200);
        }
        if (path.startsWith('/api/maintenance/sites/') && path.endsWith('/assets')) {
          if (assetsGate != null) await assetsGate!.future;
          if (assetsStatus != 200) {
            return http.Response(
              jsonEncode({'message': 'The register is unavailable.'}),
              assetsStatus,
            );
          }
          final siteId = path.split('/')[4];
          final includeRetired = request.url.queryParameters['includeRetired'] == 'true';
          final siteAssets = assets[siteId] ?? [];
          final sent = includeRetired
              ? siteAssets
              : [
                  for (final a in siteAssets)
                    if (a['isActive'] != false) a,
                ];
          return http.Response(jsonEncode({'assets': sent}), 200);
        }
        if (request.method == 'POST' && path == '/api/maintenance/assets') {
          final sent = jsonDecode(request.body) as Map<String, dynamic>;
          assetPosts.add(sent);
          if (createAssetStatus != 201) {
            return http.Response(jsonEncode({'message': createAssetMessage}), createAssetStatus);
          }
          final created = assetJson(
            '900',
            sent['code'] as String,
            sent['name'] as String,
            orgUnitId: sent['orgUnitId'] as String,
            assetType: sent['assetType'] as String,
            criticality: sent['criticality'] as String,
          );
          return http.Response(jsonEncode({'asset': created}), 201);
        }
        if (request.method == 'PATCH' && path.startsWith('/api/maintenance/assets/')) {
          final id = path.split('/').last;
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          assetPatches.add((id, body));
          if (assetPatchGate != null) await assetPatchGate!.future;
          if (patchAssetStatus != 200) {
            return http.Response(jsonEncode({'message': patchAssetMessage}), patchAssetStatus);
          }
          Map<String, dynamic>? updated;
          assets = {
            for (final entry in assets.entries)
              entry.key: [
                for (final a in entry.value)
                  if (a['id'] == id) (updated = {...a, ...body}) else a,
              ],
          };
          if (updated == null) {
            return http.Response(jsonEncode({'message': 'That Asset does not exist.'}), 404);
          }
          return http.Response(jsonEncode({'asset': updated}), 200);
        }
        if (request.method == 'POST' && path == '/api/maintenance/job-plans') {
          final sent = jsonDecode(request.body) as Map<String, dynamic>;
          jobPlanPosts.add(sent);
          if (createJobPlanStatus != 201) {
            return http.Response(jsonEncode({'message': createJobPlanMessage}), createJobPlanStatus);
          }
          final created = jobPlanJson(
            '900',
            sent['code'] as String,
            sent['name'] as String,
            description: sent['description'] as String?,
            workType: sent['workType'] as String,
            estimatedHours: sent['estimatedHours'] as num?,
            requiresShutdown: sent['requiresShutdown'] == true,
            safetyNote: sent['safetyNote'] as String?,
            tasks: [
              for (final row in (sent['tasks'] as List<dynamic>? ?? const []))
                jobPlanTaskJson(
                  't${(row as Map<String, dynamic>)['stepNo']}',
                  (row['stepNo'] as num).toInt(),
                  row['instruction'] as String,
                  skillId: row['skillId']?.toString(),
                  skillName: row['skillId'] == null
                      ? null
                      : _skillCodeNameFor(row['skillId'].toString()).$2,
                  estimatedHours: row['estimatedHours'] as num?,
                ),
            ],
          );
          jobPlans = [...jobPlans, created];
          return http.Response(jsonEncode({'jobPlan': created}), 201);
        }
        if (request.method == 'PATCH' && path.startsWith('/api/maintenance/job-plans/')) {
          final id = path.split('/')[4];
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          jobPlanPatches.add((id, body));
          if (patchJobPlanStatus != 200) {
            return http.Response(jsonEncode({'message': patchJobPlanMessage}), patchJobPlanStatus);
          }
          Map<String, dynamic>? updated;
          jobPlans = [
            for (final plan in jobPlans)
              if (plan['id'] == id) (updated = {...plan, ...body}) else plan,
          ];
          if (updated == null) {
            return http.Response(jsonEncode({'message': 'Job plan not found'}), 404);
          }
          return http.Response(jsonEncode({'jobPlan': updated}), 200);
        }
        if (path == '/api/maintenance/job-plans') {
          if (jobPlansGate != null) await jobPlansGate!.future;
          if (jobPlansStatus != 200) {
            return http.Response(
              jsonEncode({'message': 'The Job plans are unavailable.'}),
              jobPlansStatus,
            );
          }
          final includeInactive = request.url.queryParameters['includeInactive'] != 'false';
          final sent = includeInactive
              ? jobPlans
              : [for (final plan in jobPlans) if (plan['isActive'] != false) plan];
          return http.Response(jsonEncode({'jobPlans': sent}), 200);
        }
        if (request.method == 'POST' && path == '/api/maintenance/pm-schedules') {
          final sent = jsonDecode(request.body) as Map<String, dynamic>;
          pmSchedulePosts.add(sent);
          if (createPmScheduleStatus != 201) {
            return http.Response(jsonEncode({'message': createPmScheduleMessage}), createPmScheduleStatus);
          }
          final assetId = sent['assetId'] as String;
          final jobPlanId = sent['jobPlanId'] as String;
          final siteId = _siteOfAsset(assetId);
          final siteAssets = siteId == null ? const <Map<String, dynamic>>[] : (assets[siteId] ?? []);
          final asset = siteAssets.firstWhere(
            (a) => a['id'] == assetId,
            orElse: () => const <String, dynamic>{},
          );
          final jobPlan = jobPlans.firstWhere(
            (p) => p['id'] == jobPlanId,
            orElse: () => const <String, dynamic>{},
          );
          final created = pmScheduleJson(
            '900',
            'PM-900',
            '${jobPlan['name'] ?? 'Job plan'} - ${asset['name'] ?? 'Asset'}',
            assetId: assetId,
            assetCode: asset['code'] as String? ?? 'ASSET',
            assetName: asset['name'] as String? ?? 'Asset',
            jobPlanId: jobPlanId,
            jobPlanName: jobPlan['name'] as String? ?? 'Job plan',
            intervalDays: (sent['intervalDays'] as num).toInt(),
            anchor: sent['anchor'] as String? ?? 'completed',
            leadTimeDays: (sent['leadTimeDays'] as num?)?.toInt() ?? 7,
            priority: (sent['priority'] as num?)?.toInt() ?? 3,
            nextDueOn: sent['nextDueOn'] as String?,
          );
          if (siteId != null) {
            pmSchedules = {
              ...pmSchedules,
              siteId: [...(pmSchedules[siteId] ?? []), created],
            };
          }
          return http.Response(jsonEncode({'pmSchedule': created}), 201);
        }
        if (request.method == 'PATCH' && path.startsWith('/api/maintenance/pm-schedules/')) {
          final id = path.split('/')[4];
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          pmSchedulePatches.add((id, body));
          if (patchPmScheduleStatus != 200) {
            return http.Response(jsonEncode({'message': patchPmScheduleMessage}), patchPmScheduleStatus);
          }
          Map<String, dynamic>? updated;
          pmSchedules = {
            for (final entry in pmSchedules.entries)
              entry.key: [
                for (final schedule in entry.value)
                  if (schedule['id'] == id) (updated = {...schedule, ...body}) else schedule,
              ],
          };
          if (updated == null) {
            return http.Response(jsonEncode({'message': 'PM schedule not found'}), 404);
          }
          return http.Response(jsonEncode({'pmSchedule': updated}), 200);
        }
        if (path.startsWith('/api/maintenance/sites/') && path.endsWith('/pm-schedules')) {
          final siteId = path.split('/')[4];
          if (pmSchedulesGate != null) await pmSchedulesGate!.future;
          if (pmSchedulesStatus != 200) {
            return http.Response(
              jsonEncode({'message': 'The PM schedules are unavailable.'}),
              pmSchedulesStatus,
            );
          }
          final includeInactive = request.url.queryParameters['includeInactive'] == 'true';
          final siteSchedules = pmSchedules[siteId] ?? [];
          final sent = includeInactive
              ? siteSchedules
              : [for (final schedule in siteSchedules) if (schedule['isActive'] != false) schedule];
          return http.Response(jsonEncode({'pmSchedules': sent}), 200);
        }
        if (request.method == 'GET' && path.startsWith('/api/maintenance/work-orders/')) {
          final id = path.split('/')[4];
          workOrderDetailRequests.add(id);
          if (workOrderDetailGate != null) await workOrderDetailGate!.future;
          if (workOrderDetailStatus != 200) {
            return http.Response(
              jsonEncode({'message': 'That Work order could not be read.'}),
              workOrderDetailStatus,
            );
          }
          Map<String, dynamic>? row;
          for (final list in workOrders.values) {
            for (final workOrder in list) {
              if (workOrder['id'] == id) row = workOrder;
            }
          }
          if (row == null) {
            return http.Response(jsonEncode({'message': 'That Work order does not exist.'}), 404);
          }
          return http.Response(
            jsonEncode({
              'workOrder': {
                ...row,
                'pmScheduleId': null,
                'tasks': workOrderTasks[id] ?? const [],
              },
            }),
            200,
          );
        }
        if (path.startsWith('/api/maintenance/sites/') && path.endsWith('/work-orders')) {
          final siteId = path.split('/')[4];
          final orgUnitId = request.url.queryParameters['orgUnitId'];
          final includeHistory = request.url.queryParameters['includeHistory'] == 'true';
          workOrderRequests.add((siteId, orgUnitId, includeHistory));
          if (workOrdersGate != null) await workOrdersGate!.future;
          if (workOrdersStatus != 200) {
            return http.Response(
              jsonEncode({'message': 'Work orders are unavailable.'}),
              workOrdersStatus,
            );
          }
          final scripted = workOrdersByFilter['$siteId|${orgUnitId ?? ''}'];
          final siteWorkOrders = scripted ?? (workOrders[siteId] ?? []);
          // Mirrors the Asset register's own `includeRetired` filtering
          // above: completed/cancelled rows are excluded unless history was
          // asked for (issue #63).
          const historyStatuses = {'completed', 'cancelled'};
          final sent = includeHistory
              ? siteWorkOrders
              : [
                  for (final wo in siteWorkOrders)
                    if (!historyStatuses.contains(wo['status'])) wo,
                ];
          return http.Response(jsonEncode({'workOrders': sent}), 200);
        }
        if (request.method == 'POST' &&
            path.startsWith('/api/maintenance/work-orders/') &&
            (path.endsWith('/start') || path.endsWith('/complete') || path.endsWith('/cancel'))) {
          // '', 'api', 'maintenance', 'work-orders', ':id', 'start'|'complete'|
          // 'cancel' — segment 4 is the Work order id, segment 5 the action.
          final segments = path.split('/');
          final workOrderId = segments[4];
          final action = segments[5];
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          // Recorded before the gate, exactly as the assign handler's own
          // comment insists — so a test can assert what was sent while the
          // response still hangs.
          final int status;
          final String message;
          final Map<String, dynamic> update;
          switch (action) {
            case 'start':
              workOrderStarts.add(workOrderId);
              status = startWorkOrderStatus;
              message = startWorkOrderMessage;
              update = {'status': 'in_progress'};
            case 'complete':
              workOrderCompletions.add((workOrderId, body));
              status = completeWorkOrderStatus;
              message = completeWorkOrderMessage;
              update = {'status': 'completed', 'completionNote': body['note']};
            case 'cancel':
            default:
              workOrderCancellations.add((workOrderId, body));
              status = cancelWorkOrderStatus;
              message = cancelWorkOrderMessage;
              update = {'status': 'cancelled', 'completionNote': body['reason']};
          }
          if (workOrderTransitionGate != null) await workOrderTransitionGate!.future;
          if (status != 200) {
            return http.Response(jsonEncode({'message': message}), status);
          }
          Map<String, dynamic>? updated;
          workOrders = {
            for (final entry in workOrders.entries)
              entry.key: [
                for (final wo in entry.value)
                  if (wo['id'] == workOrderId) (updated = {...wo, ...update}) else wo,
              ],
          };
          if (updated == null) {
            return http.Response(jsonEncode({'message': 'That Work order does not exist.'}), 404);
          }
          return http.Response(jsonEncode({'workOrder': updated}), 200);
        }
        if (request.method == 'PUT' &&
            path.startsWith('/api/maintenance/work-orders/') &&
            path.endsWith('/assignee')) {
          // '', 'api', 'maintenance', 'work-orders', ':id', 'assignee' —
          // segment 4 is the Work order id.
          final workOrderId = path.split('/')[4];
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          // Recorded before the gate, exactly as the asset PATCH handler
          // does — so a test can assert what was sent while the response
          // still hangs.
          workOrderAssignRequests.add((workOrderId, body));
          if (workOrderAssignGate != null) await workOrderAssignGate!.future;
          if (assignWorkOrderStatus != 200) {
            return http.Response(
              jsonEncode({'message': assignWorkOrderMessage}),
              assignWorkOrderStatus,
            );
          }
          final employeeId = body['employeeId'] as String?;
          String? assigneeName;
          for (final candidate in assigneeCandidates) {
            if (candidate['id'] == employeeId) {
              assigneeName = candidate['displayName'] as String;
              break;
            }
          }
          Map<String, dynamic>? updated;
          workOrders = {
            for (final entry in workOrders.entries)
              entry.key: [
                for (final wo in entry.value)
                  if (wo['id'] == workOrderId)
                    (updated = {...wo, 'assignedTo': employeeId, 'assigneeName': assigneeName})
                  else
                    wo,
              ],
          };
          if (updated == null) {
            return http.Response(jsonEncode({'message': 'That Work order does not exist.'}), 404);
          }
          return http.Response(jsonEncode({'workOrder': updated}), 200);
        }
        if (request.method == 'POST' && path == '/api/maintenance/work-orders') {
          final sent = jsonDecode(request.body) as Map<String, dynamic>;
          workOrderPosts.add(sent);
          if (createWorkOrderStatus != 201) {
            return http.Response(
              jsonEncode({'message': createWorkOrderMessage}),
              createWorkOrderStatus,
            );
          }
          final created = workOrderJson(
            '900',
            'WO-900',
            sent['summary'] as String,
            assetId: sent['assetId'] as String,
            workType: sent['workType'] as String,
            priority: sent['priority'] as int,
          );
          return http.Response(jsonEncode({'workOrder': created}), 201);
        }
        if (request.method == 'POST' && path == '/api/maintenance/requests') {
          final sent = jsonDecode(request.body) as Map<String, dynamic>;
          requestPosts.add(sent);
          if (createRequestStatus != 201) {
            return http.Response(jsonEncode({'message': createRequestMessage}), createRequestStatus);
          }
          final created = requestJson(
            '900',
            'MR-900',
            sent['summary'] as String,
            assetId: sent['assetId'] as String,
            description: sent['description'] as String?,
            urgency: sent['urgency'] as String? ?? 'normal',
            productionStopped: sent['productionStopped'] == true,
          );
          return http.Response(jsonEncode({'request': created}), 201);
        }
        if (request.method == 'POST' &&
            path.startsWith('/api/maintenance/requests/') &&
            path.endsWith('/accept')) {
          final id = path.split('/')[4];
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          requestAccepts.add((id, body));
          if (acceptRequestStatus != 200) {
            return http.Response(jsonEncode({'message': acceptRequestMessage}), acceptRequestStatus);
          }
          final workOrder = requestWorkOrderJson('900', 'WO-900');
          final updated = _applyRequestChanges(id, {
            'status': 'accepted',
            'triagedAt': DateTime.now().toUtc().toIso8601String(),
            'workOrder': workOrder,
          });
          if (updated == null) {
            return http.Response(jsonEncode({'message': 'That Request does not exist.'}), 404);
          }
          return http.Response(jsonEncode({'request': updated, 'workOrder': workOrder}), 200);
        }
        if (request.method == 'POST' &&
            path.startsWith('/api/maintenance/requests/') &&
            path.endsWith('/decline')) {
          final id = path.split('/')[4];
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          requestDeclines.add((id, body));
          if (declineRequestStatus != 200) {
            return http.Response(jsonEncode({'message': declineRequestMessage}), declineRequestStatus);
          }
          final updated = _applyRequestChanges(id, {
            'status': 'rejected',
            'rejectionReason': body['reason'],
            'triagedAt': DateTime.now().toUtc().toIso8601String(),
          });
          if (updated == null) {
            return http.Response(jsonEncode({'message': 'That Request does not exist.'}), 404);
          }
          return http.Response(jsonEncode({'request': updated}), 200);
        }
        if (request.method == 'POST' &&
            path.startsWith('/api/maintenance/requests/') &&
            path.endsWith('/duplicate')) {
          final id = path.split('/')[4];
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          requestDuplicates.add((id, body));
          if (duplicateRequestStatus != 200) {
            return http.Response(
              jsonEncode({'message': duplicateRequestMessage}),
              duplicateRequestStatus,
            );
          }
          final updated = _applyRequestChanges(id, {
            'status': 'duplicate',
            'duplicateOfId': body['duplicateOfId']?.toString(),
            'triagedAt': DateTime.now().toUtc().toIso8601String(),
          });
          if (updated == null) {
            return http.Response(jsonEncode({'message': 'That Request does not exist.'}), 404);
          }
          return http.Response(jsonEncode({'request': updated}), 200);
        }
        if (path.startsWith('/api/maintenance/sites/') && path.endsWith('/requests/mine')) {
          final siteId = path.split('/')[4];
          myRequestSites.add(siteId);
          if (myRequestsGate != null) await myRequestsGate!.future;
          if (myRequestsStatus != 200) {
            return http.Response(
              jsonEncode({'message': 'Your requests are unavailable.'}),
              myRequestsStatus,
            );
          }
          return http.Response(jsonEncode({'requests': myRequests[siteId] ?? []}), 200);
        }
        if (path.startsWith('/api/maintenance/sites/') && path.endsWith('/requests')) {
          final siteId = path.split('/')[4];
          triageRequestSites.add(siteId);
          if (requestsGate != null) await requestsGate!.future;
          if (requestsStatus != 200) {
            return http.Response(
              jsonEncode({'message': 'The requests are unavailable.'}),
              requestsStatus,
            );
          }
          return http.Response(jsonEncode({'requests': triageRequests[siteId] ?? []}), 200);
        }
        if (path == '/api/people/employees/assignee-candidates') {
          if (assigneeCandidatesStatus != 200) {
            return http.Response(
              jsonEncode({'message': 'The candidates are unavailable.'}),
              assigneeCandidatesStatus,
            );
          }
          return http.Response(jsonEncode({'candidates': assigneeCandidates}), 200);
        }
        if (request.method == 'POST' && path == '/api/people/employees') {
          final sent = jsonDecode(request.body) as Map<String, dynamic>;
          employeePosts.add(sent);
          if (createEmployeeStatus != 201) {
            return http.Response(jsonEncode({'message': createEmployeeMessage}), createEmployeeStatus);
          }
          final id = (_nextEmployeeId++).toString();
          final firstName = sent['firstName'] as String? ?? '';
          final lastName = sent['lastName'] as String? ?? '';
          final displayName = [firstName, lastName].where((n) => n.isNotEmpty).join(' ');
          final created = employeeJson(
            id,
            sent['employeeNo'] as String,
            displayName,
            employmentType: sent['employmentType'] as String? ?? 'permanent',
          );
          employees = [...employees, created];
          // The real route's own RETURNING clause answers the bare
          // `toEmployee` shape — no `orgUnit`, no `jobRole` — so this mirrors
          // that exactly rather than the listing row [employees] itself just
          // got, which does carry both (issue #87's own trap).
          final bare = {...created}..remove('orgUnit')..remove('jobRole');
          return http.Response(jsonEncode({'employee': bare}), 201);
        }
        if (request.method == 'PATCH' && path.startsWith('/api/people/employees/')) {
          final id = path.substring('/api/people/employees/'.length);
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          employeePatches.add((id, body));
          if (updateEmployeeStatus != 200) {
            return http.Response(jsonEncode({'message': updateEmployeeMessage}), updateEmployeeStatus);
          }
          _applyEmployeeChanges(id, body);
          final matched = [
            for (final e in employees) if (e['id'] == id) e,
            for (final d in employeeDetails.values) if (d['id'] == id) d,
          ];
          if (matched.isEmpty) {
            return http.Response(jsonEncode({'message': 'Employee not found'}), 404);
          }
          final bare = {...matched.first}..remove('orgUnit')..remove('jobRole');
          return http.Response(jsonEncode({'employee': bare}), 200);
        }
        if (request.method == 'POST' &&
            path.startsWith('/api/people/employees/') &&
            path.endsWith('/departure')) {
          // '', 'api', 'people', 'employees', ':id', 'departure'.
          final id = path.split('/')[4];
          final body = request.body.isEmpty
              ? const <String, dynamic>{}
              : jsonDecode(request.body) as Map<String, dynamic>;
          employeeDepartures.add((id, body));
          if (departEmployeeStatus != 200) {
            return http.Response(jsonEncode({'message': departEmployeeMessage}), departEmployeeStatus);
          }
          final terminatedOn = body['terminatedOn'] as String? ?? '2024-06-01';
          _applyEmployeeChanges(id, {'isActive': false, 'terminatedOn': terminatedOn});
          final matched = [
            for (final e in employees) if (e['id'] == id) e,
            for (final d in employeeDetails.values) if (d['id'] == id) d,
          ];
          if (matched.isEmpty) {
            return http.Response(jsonEncode({'message': 'Employee not found'}), 404);
          }
          final bare = {...matched.first}..remove('orgUnit')..remove('jobRole');
          // `linkedAccount` rides along on this one response only (issue
          // #116, ADR-0022) — null when nothing was scripted for this
          // Employee id.
          bare['linkedAccount'] = employeeLinkedAccounts[id];
          return http.Response(jsonEncode({'employee': bare}), 200);
        }
        if (request.method == 'POST' &&
            path.startsWith('/api/people/employees/') &&
            path.endsWith('/reinstatement')) {
          final id = path.split('/')[4];
          employeeReinstatements.add(id);
          if (reinstateEmployeeStatus != 200) {
            return http.Response(
              jsonEncode({'message': reinstateEmployeeMessage}),
              reinstateEmployeeStatus,
            );
          }
          _applyEmployeeChanges(id, {'isActive': true, 'terminatedOn': null});
          final matched = [
            for (final e in employees) if (e['id'] == id) e,
            for (final d in employeeDetails.values) if (d['id'] == id) d,
          ];
          if (matched.isEmpty) {
            return http.Response(jsonEncode({'message': 'Employee not found'}), 404);
          }
          final bare = {...matched.first}..remove('orgUnit')..remove('jobRole');
          return http.Response(jsonEncode({'employee': bare}), 200);
        }
        if (request.method == 'POST' &&
            path.startsWith('/api/people/employees/') &&
            path.endsWith('/assignments')) {
          // '', 'api', 'people', 'employees', ':id', 'assignments'.
          final id = path.split('/')[4];
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          assignmentPosts.add((id, body));
          if (createAssignmentStatus != 201) {
            return http.Response(
              jsonEncode({'message': createAssignmentMessage}),
              createAssignmentStatus,
            );
          }
          final created = _applyAssignment(id, body);
          return http.Response(jsonEncode({'assignment': created}), 201);
        }
        if (request.method == 'PUT' &&
            path.startsWith('/api/people/employees/') &&
            path.contains('/skills/')) {
          // '', 'api', 'people', 'employees', ':id', 'skills', ':skillId'.
          final segments = path.split('/');
          final employeeId = segments[4];
          final skillId = segments[6];
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          employeeSkillPuts.add((employeeId, skillId, body));
          if (recordEmployeeSkillStatus != 200) {
            return http.Response(
              jsonEncode({'message': recordEmployeeSkillMessage}),
              recordEmployeeSkillStatus,
            );
          }
          // Always 200, never 201 — an upsert, mirroring skill-routes.js's
          // own PUT exactly (this file's own header on why).
          final employeeSkill = _applyEmployeeSkill(employeeId, skillId, body);
          return http.Response(jsonEncode({'employeeSkill': employeeSkill}), 200);
        }
        if (path == '/api/people/employees') {
          final search = request.url.queryParameters['search'];
          final orgUnitId = request.url.queryParameters['orgUnitId'];
          final jobRoleId = request.url.queryParameters['jobRoleId'];
          final includeDeparted = request.url.queryParameters['includeDeparted'] == 'true';
          final limit = request.url.queryParameters['limit'];
          employeeRequests.add({
            'search': search,
            'orgUnitId': orgUnitId,
            'jobRoleId': jobRoleId,
            'includeDeparted': includeDeparted.toString(),
            'limit': limit,
          });
          if (employeesStatus != 200) {
            return http.Response(jsonEncode({'message': 'The Directory is unavailable.'}), employeesStatus);
          }
          var sent = employees;
          if (!includeDeparted) {
            sent = [for (final e in sent) if (e['isActive'] != false) e];
          }
          if (search != null && search.isNotEmpty) {
            final needle = search.toLowerCase();
            sent = [
              for (final e in sent)
                if ((e['displayName'] as String).toLowerCase().contains(needle)) e,
            ];
          }
          final limitValue = limit == null ? null : int.tryParse(limit);
          if (limitValue != null && limitValue > 0 && sent.length > limitValue) {
            sent = sent.sublist(0, limitValue);
          }
          return http.Response(jsonEncode({'employees': sent}), 200);
        }
        // GET /api/people/employees/me and GET /api/people/employees/:id
        // (issue #86) — `me` is a distinct fixture key, not a real Employee
        // id, mirroring directory-routes.js's own declaration-order trick
        // (GET /employees/me is matched before :id could ever swallow it).
        if (path.startsWith('/api/people/employees/')) {
          final id = path.substring('/api/people/employees/'.length);
          if (employeeDetailStatus != 200) {
            return http.Response(jsonEncode({'message': employeeDetailMessage}), employeeDetailStatus);
          }
          final detail = employeeDetails[id];
          if (detail == null) {
            return http.Response(
              jsonEncode({
                'message': id == 'me'
                    ? 'This Account has no linked Employee record'
                    : 'Employee not found',
              }),
              404,
            );
          }
          return http.Response(jsonEncode({'employee': detail}), 200);
        }
        if (request.method == 'POST' && path == '/api/people/job-roles') {
          final sent = jsonDecode(request.body) as Map<String, dynamic>;
          jobRolePosts.add(sent);
          if (createJobRoleStatus != 201) {
            return http.Response(jsonEncode({'message': createJobRoleMessage}), createJobRoleStatus);
          }
          final id = (_nextJobRoleId++).toString();
          final created = jobRoleJson(id, sent['code'] as String, sent['name'] as String);
          jobRoles = [...jobRoles, created];
          return http.Response(jsonEncode({'jobRole': created}), 201);
        }
        if (request.method == 'PATCH' && path.startsWith('/api/people/job-roles/')) {
          final id = path.substring('/api/people/job-roles/'.length);
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          jobRolePatches.add((id, body));
          if (updateJobRoleStatus != 200) {
            return http.Response(jsonEncode({'message': updateJobRoleMessage}), updateJobRoleStatus);
          }
          Map<String, dynamic>? updated;
          jobRoles = [
            for (final jobRole in jobRoles)
              if (jobRole['id'] == id) (updated = {...jobRole, ...body}) else jobRole,
          ];
          if (updated == null) {
            return http.Response(jsonEncode({'message': 'Job role not found'}), 404);
          }
          return http.Response(jsonEncode({'jobRole': updated}), 200);
        }
        if (path == '/api/people/job-roles') {
          if (jobRolesStatus != 200) {
            return http.Response(jsonEncode({'message': 'Job roles are unavailable.'}), jobRolesStatus);
          }
          final includeInactive = request.url.queryParameters['includeInactive'] == 'true';
          final sent = includeInactive
              ? jobRoles
              : [for (final jobRole in jobRoles) if (jobRole['isActive'] != false) jobRole];
          return http.Response(jsonEncode({'jobRoles': sent}), 200);
        }
        if (request.method == 'POST' && path == '/api/people/skills') {
          final sent = jsonDecode(request.body) as Map<String, dynamic>;
          skillPosts.add(sent);
          if (createSkillStatus != 201) {
            return http.Response(jsonEncode({'message': createSkillMessage}), createSkillStatus);
          }
          final id = (_nextSkillId++).toString();
          final created = skillJson(
            id,
            sent['code'] as String,
            sent['name'] as String,
            skillCategory: sent['skillCategory'] as String? ?? 'operation',
            requiresCertification: sent['requiresCertification'] == true,
            revalidationMonths: (sent['revalidationMonths'] as num?)?.toInt(),
          );
          skills = [...skills, created];
          return http.Response(jsonEncode({'skill': created}), 201);
        }
        if (request.method == 'PATCH' &&
            path.startsWith('/api/people/skills/') &&
            !path.endsWith('/qualified-employees')) {
          final id = path.substring('/api/people/skills/'.length);
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          skillPatches.add((id, body));
          if (updateSkillStatus != 200) {
            return http.Response(jsonEncode({'message': updateSkillMessage}), updateSkillStatus);
          }
          Map<String, dynamic>? updated;
          skills = [
            for (final skill in skills)
              if (skill['id'] == id) (updated = {...skill, ...body}) else skill,
          ];
          if (updated == null) {
            return http.Response(jsonEncode({'message': 'Skill not found'}), 404);
          }
          return http.Response(jsonEncode({'skill': updated}), 200);
        }
        if (path.startsWith('/api/people/skills/') && path.endsWith('/qualified-employees')) {
          // '', 'api', 'people', 'skills', ':id', 'qualified-employees'.
          final skillId = path.split('/')[4];
          final orgUnitId = request.url.queryParameters['orgUnitId'];
          final minimumLevel = request.url.queryParameters['minimumLevel'];
          qualifiedEmployeeRequests.add((skillId, orgUnitId, minimumLevel));
          if (qualifiedEmployeesStatus != 200) {
            return http.Response(
              jsonEncode({'message': 'That skill could not be read.'}),
              qualifiedEmployeesStatus,
            );
          }
          if (orgUnitId == null) {
            return http.Response(
              jsonEncode({'message': 'orgUnitId is required and must be a valid Org Unit id'}),
              400,
            );
          }
          return http.Response(jsonEncode({'employees': qualifiedEmployees}), 200);
        }
        if (path == '/api/people/skills') {
          if (skillsStatus != 200) {
            return http.Response(jsonEncode({'message': 'The skill catalogue is unavailable.'}), skillsStatus);
          }
          final includeInactive = request.url.queryParameters['includeInactive'] == 'true';
          final skillCategory = request.url.queryParameters['skillCategory'];
          var sent = includeInactive ? skills : [for (final skill in skills) if (skill['isActive'] != false) skill];
          if (skillCategory != null) {
            sent = [for (final skill in sent) if (skill['skillCategory'] == skillCategory) skill];
          }
          return http.Response(jsonEncode({'skills': sent}), 200);
        }
        if (path.startsWith('/api/people/sites/') && path.endsWith('/skill-coverage')) {
          final siteId = path.split('/')[4];
          skillCoverageRequests.add(siteId);
          if (skillCoverageStatus != 200) {
            return http.Response(
              jsonEncode({'message': 'Skill coverage is unavailable.'}),
              skillCoverageStatus,
            );
          }
          return http.Response(jsonEncode({'coverage': skillCoverage[siteId] ?? []}), 200);
        }
        if (request.method == 'POST' && path == '/api/people/sites') {
          final sent = jsonDecode(request.body) as Map<String, dynamic>;
          sitePosts.add(sent);
          if (createSiteStatus != 201) {
            return http.Response(jsonEncode({'message': createSiteMessage}), createSiteStatus);
          }
          final id = (_nextSiteId++).toString();
          final created = siteJson(id, sent['code'] as String, sent['name'] as String);
          sites = [...sites, created];
          return http.Response(jsonEncode({'site': created}), 201);
        }
        if (path == '/api/people/sites') {
          if (sitesStatus != 200) {
            return http.Response(jsonEncode({'message': 'Sites are unavailable.'}), sitesStatus);
          }
          return http.Response(jsonEncode({'sites': sites}), 200);
        }
        if (request.method == 'PATCH' && path.startsWith('/api/people/sites/')) {
          // '', 'api', 'people', 'sites', ':siteId'.
          final siteId = path.split('/')[4];
          final sent = jsonDecode(request.body) as Map<String, dynamic>;
          sitePatches.add((siteId, sent));
          if (patchSiteStatus != 200) {
            return http.Response(jsonEncode({'message': patchSiteMessage}), patchSiteStatus);
          }
          final index = sites.indexWhere((site) => site['id'] == siteId);
          final updated = {
            if (index != -1) ...sites[index],
            ...sent,
            'id': siteId,
          };
          if (index != -1) sites[index] = updated;
          return http.Response(jsonEncode({'site': updated}), 200);
        }
        if (path == '/api/people/timezones') {
          if (timezonesStatus != 200) {
            return http.Response(jsonEncode({'message': timezonesMessage}), timezonesStatus);
          }
          return http.Response(jsonEncode({'timezones': timezones}), 200);
        }
        if (path.startsWith('/api/people/sites/') && path.endsWith('/org-units/search')) {
          // '', 'api', 'people', 'sites', ':siteId', 'org-units', 'search'.
          final siteId = path.split('/')[4];
          final search = request.url.queryParameters['search'];
          orgUnitSearchRequests.add((siteId, search));
          if (orgUnitSearchStatus != 200) {
            return http.Response(
              jsonEncode({'message': 'Search is unavailable.'}),
              orgUnitSearchStatus,
            );
          }
          return http.Response(
            jsonEncode({'orgUnits': orgUnitSearchResults, 'truncated': orgUnitSearchTruncated}),
            200,
          );
        }
        if (request.method == 'POST' &&
            path.startsWith('/api/people/sites/') &&
            path.endsWith('/org-units/import')) {
          // '', 'api', 'people', 'sites', ':siteId', 'org-units', 'import'.
          final siteId = path.split('/')[4];
          final sent = jsonDecode(request.body) as Map<String, dynamic>;
          orgUnitImportPosts.add((siteId, sent));
          if (importOrgUnitsStatus == 422) {
            return http.Response(
              jsonEncode({'message': importOrgUnitsMessage, 'errors': importOrgUnitsErrors}),
              422,
            );
          }
          if (importOrgUnitsStatus != 201) {
            return http.Response(jsonEncode({'message': importOrgUnitsMessage}), importOrgUnitsStatus);
          }
          // A best-effort application, not a real topological insert: rows
          // are applied in payload order, each resolved against whatever this
          // Fake Wire already knows by `code` (an existing Org Unit, or an
          // earlier row in the same payload) — enough for a widget test to
          // prove a successful import actually shows up on a re-read, without
          // reimplementing org-unit-import.js's own validation here.
          final codeToId = <String, String>{
            for (final entry in orgUnits.entries)
              for (final node in entry.value) node['code'] as String: node['id'] as String,
          };
          final created = <Map<String, dynamic>>[];
          for (final row in (sent['orgUnits'] as List<dynamic>).cast<Map<String, dynamic>>()) {
            final parentCode = row['parentCode'] as String?;
            final parentId = parentCode == null ? null : codeToId[parentCode];
            final id = (_nextOrgUnitId++).toString();
            final node = orgUnitJson(
              id,
              row['name'] as String,
              parentId: parentId,
              unitType: row['unitType'] as String? ?? 'area',
            )..['code'] = row['code'];
            codeToId[row['code'] as String] = id;
            created.add(node);
            orgUnits = {
              ...orgUnits,
              parentId: [...(orgUnits[parentId] ?? []), node],
            };
          }
          return http.Response(jsonEncode({'orgUnits': created}), 201);
        }
        if (request.method == 'POST' &&
            path.startsWith('/api/people/sites/') &&
            path.endsWith('/org-units')) {
          final siteId = path.split('/')[4];
          final sent = jsonDecode(request.body) as Map<String, dynamic>;
          orgUnitPosts.add((siteId, sent));
          if (createOrgUnitStatus != 201) {
            return http.Response(jsonEncode({'message': createOrgUnitMessage}), createOrgUnitStatus);
          }
          final parentId = sent['parentId'] as String?;
          final id = (_nextOrgUnitId++).toString();
          final created = orgUnitJson(
            id,
            sent['name'] as String,
            parentId: parentId,
            unitType: sent['unitType'] as String,
          )..['code'] = sent['code'];
          orgUnits = {
            ...orgUnits,
            parentId: [...(orgUnits[parentId] ?? []), created],
          };
          return http.Response(jsonEncode({'orgUnit': created}), 201);
        }
        if (path.startsWith('/api/people/sites/') && path.endsWith('/org-units')) {
          final siteId = path.split('/')[4];
          final parentId = request.url.queryParameters['parentId'];
          orgUnitRequests.add((siteId, parentId));
          if (orgUnitsStatus != 200) {
            return http.Response(
              jsonEncode({'message': 'The tree is unavailable.'}),
              orgUnitsStatus,
            );
          }
          return http.Response(jsonEncode({'orgUnits': orgUnits[parentId] ?? []}), 200);
        }
        if (request.method == 'PATCH' && path.startsWith('/api/people/org-units/')) {
          final id = path.substring('/api/people/org-units/'.length);
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          orgUnitPatches.add((id, body));
          if (patchOrgUnitStatus != 200) {
            return http.Response(jsonEncode({'message': patchOrgUnitMessage}), patchOrgUnitStatus);
          }
          Map<String, dynamic>? updated;
          orgUnits = {
            for (final entry in orgUnits.entries)
              entry.key: [
                for (final node in entry.value)
                  if (node['id'] == id) (updated = {...node, ...body}) else node,
              ],
          };
          if (updated == null) {
            return http.Response(jsonEncode({'message': 'That Org Unit does not exist.'}), 404);
          }
          return http.Response(jsonEncode({'orgUnit': updated}), 200);
        }
        if (path == '/api/people/accounts') {
          if (accountsStatus != 200) {
            return http.Response(
              jsonEncode({'message': 'The Accounts are unavailable.'}),
              accountsStatus,
            );
          }
          return http.Response(jsonEncode({'accounts': accounts}), 200);
        }
        if (request.method == 'PATCH' && path.startsWith('/api/people/accounts/')) {
          final id = path.split('/')[4];
          final isActive = (jsonDecode(request.body) as Map<String, dynamic>)['isActive'] == true;
          activations.add((id, isActive));
          if (patchGate != null) await patchGate!.future;
          if (patchStatus != 200) {
            return http.Response(
              jsonEncode({'message': 'That Account could not be changed.'}),
              patchStatus,
            );
          }
          accounts = [
            for (final a in accounts)
              if (a['id'] == id) {...a, 'isActive': isActive} else a,
          ];
          return http.Response(jsonEncode({'account': {'id': id}}), 200);
        }
        if (request.method == 'PUT' &&
            path.startsWith('/api/people/accounts/') &&
            path.endsWith('/employee')) {
          // '', 'api', 'people', 'accounts', ':id', 'employee'.
          final id = path.split('/')[4];
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final employeeId = body['employeeId'] as String?;
          employeeLinkPuts.add((id, employeeId));
          if (putEmployeeLinkStatus != 200) {
            return http.Response(jsonEncode({'message': putEmployeeLinkMessage}), putEmployeeLinkStatus);
          }
          accounts = [
            for (final a in accounts)
              if (a['id'] == id) {...a, 'employeeId': employeeId} else a,
          ];
          return http.Response(jsonEncode({'account': {'id': id, 'employeeId': employeeId}}), 200);
        }
        if (path == '/api/people/accounts/pending') {
          if (queueStatus != 200) {
            return http.Response(jsonEncode({'message': 'The queue is unavailable.'}), queueStatus);
          }
          return http.Response(jsonEncode({'accounts': queue}), 200);
        }
        if (path.endsWith('/approval')) {
          approvals.add(jsonDecode(request.body) as Map<String, dynamic>);
          if (approvalGate != null) await approvalGate!.future;
          if (approveStatus != 200) {
            return http.Response(
              jsonEncode({'message': approveMessage, if (approveCode != null) 'code': approveCode}),
              approveStatus,
            );
          }
          final id = path.split('/')[4];
          queue = [for (final a in queue) if (a['id'] != id) a];
          final sent = approvals.last;
          // `employeeId` is optional (issue #116, ADR-0022): omitted leaves
          // whatever link the Account already holds untouched, the same
          // "only touch a key that was actually sent" contract
          // `approveAccount`'s own `parseOptionalEmployeeId` keeps server-side
          // — so this only ever writes the field when the request actually
          // carried the key, never defaulting a bare absence to null.
          accounts = [
            for (final a in accounts)
              if (a['id'] == id)
                {
                  ...a,
                  'role': sent['role'],
                  'isActive': true,
                  'approvalStatus': 'approved',
                  if (sent.containsKey('employeeId')) 'employeeId': sent['employeeId'],
                  'grants': [
                    for (final g in (sent['grants'] as List<dynamic>))
                      grantJson(
                        (g as Map<String, dynamic>)['orgUnitId'] as String,
                        canWrite: g['canWrite'] == true,
                      ),
                  ],
                }
              else
                a,
          ];
          return http.Response(jsonEncode({'account': {'id': id}}), 200);
        }
        if (path.endsWith('/rejection')) {
          if (rejectStatus != 200) {
            return http.Response(
              jsonEncode({'message': 'This Account is no longer pending.'}),
              rejectStatus,
            );
          }
          final id = path.split('/')[4];
          queue = [for (final a in queue) if (a['id'] != id) a];
          return http.Response(jsonEncode({'account': {'id': id}}), 200);
        }
        if (path == '/api/maintenance/units-of-measure') {
          if (unitsOfMeasureStatus != 200) {
            return http.Response(
              jsonEncode({'message': 'The units of measure are unavailable.'}),
              unitsOfMeasureStatus,
            );
          }
          return http.Response(jsonEncode({'unitsOfMeasure': unitsOfMeasure}), 200);
        }
        if (request.method == 'POST' && path == '/api/maintenance/parts') {
          final sent = jsonDecode(request.body) as Map<String, dynamic>;
          partPosts.add(sent);
          if (createPartStatus != 201) {
            return http.Response(jsonEncode({'message': createPartMessage}), createPartStatus);
          }
          final created = partJson(
            '900',
            sent['partNo'] as String,
            sent['description'] as String,
            uomCode: sent['uomCode'] as String,
          );
          parts = [...parts, created];
          return http.Response(jsonEncode({'part': created}), 201);
        }
        if (path == '/api/maintenance/parts') {
          if (partsStatus != 200) {
            return http.Response(jsonEncode({'message': 'The parts catalogue is unavailable.'}), partsStatus);
          }
          final includeInactive = request.url.queryParameters['includeInactive'] == 'true';
          final sent = includeInactive ? parts : [for (final p in parts) if (p['isActive'] != false) p];
          return http.Response(jsonEncode({'parts': sent}), 200);
        }
        if (path.startsWith('/api/maintenance/sites/') && path.endsWith('/stores')) {
          final siteId = path.split('/')[4];
          storeSites.add(siteId);
          if (storesStatus != 200) {
            return http.Response(jsonEncode({'message': 'The stores are unavailable.'}), storesStatus);
          }
          final includeInactive = request.url.queryParameters['includeInactive'] == 'true';
          final siteStores = stores[siteId] ?? [];
          final sent = includeInactive
              ? siteStores
              : [for (final s in siteStores) if (s['isActive'] != false) s];
          return http.Response(jsonEncode({'stores': sent}), 200);
        }
        if (request.method == 'POST' &&
            path.startsWith('/api/maintenance/stores/') &&
            path.endsWith('/receipts')) {
          final storeId = path.split('/')[4];
          final sent = jsonDecode(request.body) as Map<String, dynamic>;
          receiptPosts.add((storeId, sent));
          if (createReceiptStatus != 201) {
            return http.Response(jsonEncode({'message': createReceiptMessage}), createReceiptStatus);
          }
          final partId = sent['partId'].toString();
          final quantity = sent['quantity'] as num;
          final existing = [...(stock[storeId] ?? const <Map<String, dynamic>>[])];
          final index = existing.indexWhere((row) => row['partId'].toString() == partId);
          final prior = index >= 0 ? existing[index]['quantity'] as num : 0;
          final onHand = prior + quantity;
          final part = parts.firstWhere(
            (p) => p['id'].toString() == partId,
            orElse: () => const <String, dynamic>{},
          );
          final row = stockLevelJson(
            partId,
            part['partNo'] as String? ?? 'PART',
            part['description'] as String? ?? '',
            onHand,
            uomCode: part['uomCode'] as String? ?? 'EA',
          );
          if (index >= 0) {
            existing[index] = row;
          } else {
            existing.add(row);
          }
          stock = {...stock, storeId: existing};
          return http.Response(
            jsonEncode({
              'movement': {
                'id': '900',
                'partId': partId,
                'partNo': row['partNo'],
                'description': row['description'],
                'uomCode': row['uomCode'],
                'storeId': storeId,
                'quantity': quantity,
                'movementType': 'receipt',
                'reason': sent['reason'] ?? 'received',
                'occurredAt': DateTime.now().toUtc().toIso8601String(),
              },
              'onHand': onHand,
            }),
            201,
          );
        }
        if (path.startsWith('/api/maintenance/stores/') && path.endsWith('/stock')) {
          final storeId = path.split('/')[4];
          stockReads.add(storeId);
          if (storeStockStatus != 200) {
            return http.Response(jsonEncode({'message': 'That store could not be read.'}), storeStockStatus);
          }
          final store = storeRows[storeId];
          if (store == null) {
            return http.Response(jsonEncode({'message': 'Store not found'}), 404);
          }
          return http.Response(jsonEncode({'store': store, 'stock': stock[storeId] ?? []}), 200);
        }
        if (request.method == 'GET' &&
            path.startsWith('/api/maintenance/stores/') &&
            path.split('/').length == 5) {
          final storeId = path.split('/')[4];
          final store = storeRows[storeId];
          if (store == null) {
            return http.Response(jsonEncode({'message': 'Store not found'}), 404);
          }
          return http.Response(jsonEncode({'store': store}), 200);
        }
        return http.Response('{}', 404);
      });
}

class FakeAuthGateway implements AuthGateway {
  FakeAuthGateway({String? accessToken}) : _token = accessToken;

  String? _token;
  final StreamController<String?> _controller = StreamController<String?>.broadcast();

  @override
  String? get currentAccessToken => _token;

  /// Honours [AuthGateway]'s contract: the current token first, then every
  /// change after it.
  @override
  Stream<String?> get accessTokenChanges async* {
    yield _token;
    yield* _controller.stream;
  }

  void emitToken(String? token) {
    _token = token;
    _controller.add(token);
  }

  @override
  Future<void> signInWithPassword({required String email, required String password}) async =>
      emitToken('token-for-$email');

  @override
  Future<void> signUp({required String email, required String password}) async =>
      emitToken('token-for-$email');

  @override
  Future<void> signInWithGoogle() async => emitToken('token-for-google');

  @override
  Future<void> signOut() async => emitToken(null);
}

http.Client meClient(Map<String, dynamic> Function() body, {int status = 200}) {
  return MockClient((request) async => http.Response(jsonEncode(body()), status));
}

/// [settle] is false for a test that needs to observe a Screen mid-load — a
/// gated response never settles, so `pumpAndSettle` would time out. The caller
/// then drives frames itself with `tester.pump()`.
Future<void> pumpApp(
  WidgetTester tester, {
  required FakeAuthGateway gateway,
  required http.Client client,
  String? initialLocation,
  bool settle = true,
}) async {
  await tester.pumpWidget(
    PlatformApp(
      authGateway: gateway,
      peopleApi: PeopleApi(client: client),
      // One faked wire behind both Modules' API clients, so a test scripts the
      // whole app's network in one place.
      maintenanceApi: MaintenanceApi(client: client),
      initialLocation: initialLocation,
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    // Enough frames for /me and the router to resolve, but not so many that a
    // deliberately-hanging request is waited on.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
  }
}

/// Taps something that may be scrolled out of view — the Screens under test
/// are taller than the 800x600 test surface, so a bare `tap` silently misses
/// a widget that is present but off screen.
Future<void> tapIn(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// The address the router is currently sitting on (issue #104) — resolved
/// off whichever pumped Screen's own element is given, the same shape the
/// advisor's own prototype for this ticket verified: a dialog opened by
/// address must move the location forward, and dismissing it must move the
/// location back to the Screen underneath, and a test proves both by
/// reading this rather than by inspecting a Bloc's own state.
String locationOf(WidgetTester tester, Finder screenFinder) =>
    GoRouter.of(tester.element(screenFinder)).routerDelegate.currentConfiguration.uri.toString();

/// Picks [date] through the real `showDatePicker` dialog an `AppDateField`
/// opens (issue #126) — taps [fieldKey] to open it, then switches the
/// picker into its own keyboard-entry mode (the picker's `InputDatePicker
/// FormField`, a widget entirely separate from the read-only `AppDateField`
/// beneath it) rather than walking the calendar month by month, so a test
/// can land on an arbitrary date deterministically. `MM/DD/YYYY` is the
/// picker's own default (US) format — `MaterialLocalizations.
/// formatCompactDate`, unrelated to the `YYYY-MM-DD` `AppDateField` itself
/// displays and sends.
Future<void> pickDate(WidgetTester tester, Key fieldKey, DateTime date) async {
  await tapIn(tester, find.byKey(fieldKey));
  await tester.tap(find.byTooltip('Switch to input'));
  await tester.pumpAndSettle();
  String twoDigits(int n) => n.toString().padLeft(2, '0');
  await tester.enterText(
    find.byType(TextFormField),
    '${twoDigits(date.month)}/${twoDigits(date.day)}/${date.year}',
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}
