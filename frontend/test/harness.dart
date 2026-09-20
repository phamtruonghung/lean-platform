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

import 'package:lean_platform/actions/actions_api.dart';
import 'package:lean_platform/maintenance/maintenance_api.dart';
import 'package:lean_platform/people_api.dart';
import 'package:lean_platform/platform/auth_gateway.dart';
import 'package:lean_platform/platform/destinations.dart';
import 'package:lean_platform/platform/floor_device_gateway.dart';
import 'package:lean_platform/platform/platform_app.dart';
import 'package:lean_platform/quality/quality_api.dart';

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
Map<String, dynamic> _meBody(
  String role,
  String selfId,
  String? selfEmployeeId,
  Map<String, dynamic>? orgUnitScope,
) =>
    {
      'status': 'active',
      'account': {
        'id': selfId,
        'email': 'admin@b.c',
        'displayName': 'A B',
        'role': role,
        'employeeId': selfEmployeeId,
      },
      'orgUnitScope':
          orgUnitScope ?? {'everywhere': role == Roles.admin, 'grants': const <dynamic>[]},
    };

/// One Grant as `/me` reports it — `canWrite` is what decides whether a Screen
/// offers a write affordance. `orgUnitIds` is the Grant's whole reach, the
/// granted unit plus every descendant (issue #110); left unset, the wire keeps
/// the older "reaches only its own Org Unit" shape. `qualityAuthority` is the
/// flag independent of `canWrite` (issue #204, ADR-0035), and `safetyAuthority`
/// is the same shape again (issue #225) — both default false exactly as the
/// server's own columns do.
Map<String, dynamic> scopeGrantJson(
  String orgUnitId, {
  String siteId = '1',
  bool canWrite = false,
  bool qualityAuthority = false,
  bool safetyAuthority = false,
  List<String>? orgUnitIds,
}) =>
    {
      'orgUnitId': orgUnitId,
      'siteId': siteId,
      'canWrite': canWrite,
      'qualityAuthority': qualityAuthority,
      'safetyAuthority': safetyAuthority,
      'orgUnitIds': ?orgUnitIds,
    };

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
  String siteId = '1',
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
      'siteId': siteId,
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

/// One activity's booked hours as `workOrderCost.labourByActivity` sends it —
/// mirrors `work-order-cost.js`'s own row shape.
Map<String, dynamic> labourActivityJson(String activity, num hours, {num overtimeHours = 0}) =>
    {'activity': activity, 'hours': hours, 'overtimeHours': overtimeHours};

/// One fitted part as `workOrderCost.parts` sends it — mirrors
/// `toBookedPart` (work-order-cost.js) key for key.
Map<String, dynamic> workOrderPartJson(
  String id, {
  String? partNo,
  String description = 'Bought for this job',
  num quantity = 1,
  String uomCode = 'EA',
  num? unitCost,
  String currency = 'USD',
  num? totalCost,
  String sourced = 'purchased',
}) =>
    {
      'id': id,
      'workOrderId': '101',
      'partNo': partNo,
      'description': description,
      'quantity': quantity,
      'uomCode': uomCode,
      'unitCost': unitCost,
      'currency': currency,
      'totalCost': totalCost,
      'sourced': sourced,
      'fittedAt': null,
    };

/// What a Work order has cost so far (issue #75), as the `cost` object on the
/// detail read sends it — mirrors `workOrderCost` (work-order-cost.js). Labour
/// hours and the parts cost are two separate facts; no combined total exists.
Map<String, dynamic> workOrderCostJson({
  num labourHours = 0,
  num overtimeHours = 0,
  List<Map<String, dynamic>>? labourByActivity,
  List<Map<String, dynamic>>? parts,
  num? partsCost,
}) =>
    {
      'labourHours': labourHours,
      'overtimeHours': overtimeHours,
      'labourByActivity': labourByActivity ?? const [],
      'parts': parts ?? const [],
      'partsCost': partsCost,
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
  int? intervalDays = 30,
  String? assetMeterId,
  String? meterCode,
  String? meterName,
  String? meterType,
  num? intervalMeter,
  num? lastCompletedMeter,
  num? nextDueMeter,
  num? currentMeter,
  bool meterDue = false,
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
      'assetMeterId': assetMeterId,
      'meterCode': meterCode,
      'meterName': meterName,
      'meterType': meterType,
      'intervalMeter': intervalMeter,
      'lastCompletedMeter': lastCompletedMeter,
      'nextDueMeter': nextDueMeter,
      'currentMeter': currentMeter,
      'meterDue': meterDue,
      'anchor': anchor,
      'leadTimeDays': leadTimeDays,
      'priority': priority,
      'lastCompletedOn': lastCompletedOn,
      'nextDueOn': nextDueOn,
      'isActive': isActive,
      'daysUntilDue': daysUntilDue,
    };

/// One meter as `GET /api/maintenance/sites/:siteId/meters` sends it (issue
/// #79) — mirrors `toMeter` (meters.js) key for key.
Map<String, dynamic> meterJson(
  String id,
  String code,
  String name, {
  String assetId = '7',
  String assetCode = 'PRESS-1',
  String assetName = 'Press 1',
  String orgUnitId = '10',
  String orgUnitName = 'Line 1',
  String siteId = '1',
  String uomCode = 'H',
  String uomName = 'Hour',
  String meterType = 'cumulative',
  num rolloverOffset = 0,
  bool isActive = true,
  num? latestReading,
  String? latestReadAt,
  num accumulatedUse = 0,
}) =>
    {
      'id': id,
      'assetId': assetId,
      'assetCode': assetCode,
      'assetName': assetName,
      'orgUnitId': orgUnitId,
      'orgUnitName': orgUnitName,
      'siteId': siteId,
      'code': code,
      'name': name,
      'uomCode': uomCode,
      'uomName': uomName,
      'meterType': meterType,
      'rolloverOffset': rolloverOffset,
      'isActive': isActive,
      'latestReading': latestReading,
      'latestReadAt': latestReadAt,
      'accumulatedUse': accumulatedUse,
    };

/// One unit of measure as `GET /api/maintenance/units-of-measure` sends it
/// (issue #79, reused by #80) — the baseline catalogue the meter form, the
/// Part form and the Quality Module's Product form (#203) all choose from.
Map<String, dynamic> unitOfMeasureJson(String code, String name, {String dimension = 'time'}) => {
      'code': code,
      'name': name,
      'dimension': dimension,
    };

/// One Product as `GET /api/quality/products` sends it (issue #203) — mirrors
/// `toProduct` (products.js) key for key, `uomName` included: the API joins the
/// unit's own name onto the row, so a fixture that omitted it would let a test
/// assert a catalogue the server cannot answer.
Map<String, dynamic> productJson(
  String id,
  String code,
  String name, {
  String uomCode = 'EA',
  String uomName = 'Each',
  bool isActive = true,
}) =>
    {
      'id': id,
      'code': code,
      'name': name,
      'uomCode': uomCode,
      'uomName': uomName,
      'isActive': isActive,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };

/// One Defect code as `GET /api/quality/defect-codes` sends it (issue #203) —
/// mirrors `toDefectCode` (defect-codes.js) key for key: the tree is flat, each
/// row naming its own parent rather than carrying children.
Map<String, dynamic> defectCodeJson(
  String id,
  String code,
  String name, {
  String? parentId,
  String category = 'product',
  String defaultSeverity = 'minor',
  bool isActive = true,
}) =>
    {
      'id': id,
      'parentId': parentId,
      'code': code,
      'name': name,
      'category': category,
      'defaultSeverity': defaultSeverity,
      'isActive': isActive,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };

/// One Customer as `GET /api/quality/customers` sends it (issue #214) — mirrors
/// `toCustomer` (customers.js) key for key.
Map<String, dynamic> customerJson(
  String id,
  String code,
  String name, {
  String? contactEmail,
  bool isActive = true,
}) =>
    {
      'id': id,
      'code': code,
      'name': name,
      'contactEmail': contactEmail,
      'isActive': isActive,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };

/// One Customer complaint as `GET /api/quality/complaints/:id` and the register
/// send it (issue #214) — mirrors `toComplaint` (customer-complaints.js) key for
/// key, the nested `nonconformance` summary included: the API answers every
/// complaint with the record that controls its product, so a fixture that
/// omitted it would let a test assert a shape the server cannot send.
Map<String, dynamic> customerComplaintJson(
  String id,
  String complaintNo, {
  String status = 'open',
  String customerId = '60',
  String customerCode = 'CUST-1',
  String customerName = 'Acme Bearings',
  String productId = '40',
  String productCode = 'PRD-1',
  String productName = 'Gearbox',
  String? defectCodeId = '41',
  String? defectCodeCode = 'DIM-OOT',
  String? defectCodeName = 'Out of tolerance',
  String orgUnitId = '10',
  String orgUnitName = 'Line 1',
  String siteId = '1',
  String siteCode = 'HCM',
  String siteName = 'Ho Chi Minh',
  String complaintType = 'quality',
  String severity = 'major',
  num? quantityAffected = 20,
  String? uomCode = 'EA',
  String? customerRef,
  String? lotRef,
  String description = 'Twenty of the last delivery will not seat on the shaft.',
  String? receivedAt,
  String? responseDueDate,
  String? responseDueAt,
  bool isOverdue = false,
  int? daysOverdue,
  String? firstResponseAt,
  bool isWarranty = false,
  String? closedAt,
  String? responseNote,
  Map<String, dynamic>? nonconformance,
}) =>
    {
      'id': id,
      'complaintNo': complaintNo,
      'status': status,
      'customerId': customerId,
      'customerCode': customerCode,
      'customerName': customerName,
      'productId': productId,
      'productCode': productCode,
      'productName': productName,
      'defectCodeId': defectCodeId,
      'defectCodeCode': defectCodeCode,
      'defectCodeName': defectCodeName,
      'orgUnitId': orgUnitId,
      'orgUnitName': orgUnitName,
      'siteId': siteId,
      'siteCode': siteCode,
      'siteName': siteName,
      'complaintType': complaintType,
      'severity': severity,
      'quantityAffected': quantityAffected,
      'uomCode': uomCode,
      'customerRef': customerRef,
      'lotRef': lotRef,
      'description': description,
      'receivedAt': receivedAt ?? DateTime.now().toUtc().toIso8601String(),
      'responseDueDate': responseDueDate,
      'responseDueAt': responseDueAt,
      'isOverdue': isOverdue,
      'daysOverdue': daysOverdue,
      'firstResponseAt': firstResponseAt,
      'isWarranty': isWarranty,
      'claimCost': null,
      'currency': 'USD',
      'closedAt': closedAt,
      'responseNote': responseNote,
      'nonconformance': nonconformance,
    };

/// The Non-conformance a complaint names, as the nested summary on the
/// complaint's own read sends it (issue #214) — mirrors the projection
/// customer-complaints.js builds from the linked `quality_issues` row.
Map<String, dynamic> complaintNonconformanceJson(
  String id,
  String issueNo, {
  String status = 'open',
  String detectionPoint = 'customer',
  String severity = 'major',
  num? quantityAffected = 20,
  String? detectedOn,
}) =>
    {
      'id': id,
      'issueNo': issueNo,
      'status': status,
      'detectionPoint': detectionPoint,
      'severity': severity,
      'quantityAffected': quantityAffected,
      'detectedOn': detectedOn,
    };

/// One Supplier as `GET /api/quality/suppliers` sends it (issue #215) — mirrors
/// `toSupplier` (suppliers.js) key for key.
Map<String, dynamic> supplierJson(
  String id,
  String code,
  String name, {
  String? contactEmail,
  bool isActive = true,
}) =>
    {
      'id': id,
      'code': code,
      'name': name,
      'contactEmail': contactEmail,
      'isActive': isActive,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };

/// One supplier NCR as `GET /api/quality/supplier-ncrs/:id` and the register
/// send it (issue #215) — mirrors `toSupplierNcr` (supplier-ncrs.js) key for
/// key, the nested `nonconformance` summary included: the API answers every NCR
/// with the record that controls the received lot, so a fixture that omitted it
/// would let a test assert a shape the server cannot send.
Map<String, dynamic> supplierNcrJson(
  String id,
  String ncrNo, {
  String status = 'open',
  String supplierId = '50',
  String supplierCode = 'SUP-1',
  String supplierName = 'Northwind Fasteners',
  String? productId = '40',
  String? productCode = 'PRD-1',
  String? productName = 'Gearbox',
  String? defectCodeId = '41',
  String? defectCodeCode = 'DIM-OOT',
  String? defectCodeName = 'Out of tolerance',
  String orgUnitId = '10',
  String orgUnitName = 'Line 1',
  String siteId = '1',
  String siteCode = 'HCM',
  String siteName = 'Ho Chi Minh',
  String? incomingLotRef,
  String? purchaseRef,
  num quantityAffected = 250,
  String uomCode = 'EA',
  String disposition = 'return_to_supplier',
  String? detectedAt,
  String? responseDueDate,
  String? responseDueAt,
  bool isOverdue = false,
  int? daysOverdue,
  num? costRecovered,
  String currency = 'USD',
  String? description,
  String? closedAt,
  Map<String, dynamic>? nonconformance,
}) =>
    {
      'id': id,
      'ncrNo': ncrNo,
      'status': status,
      'supplierId': supplierId,
      'supplierCode': supplierCode,
      'supplierName': supplierName,
      'productId': productId,
      'productCode': productCode,
      'productName': productName,
      'defectCodeId': defectCodeId,
      'defectCodeCode': defectCodeCode,
      'defectCodeName': defectCodeName,
      'orgUnitId': orgUnitId,
      'orgUnitName': orgUnitName,
      'siteId': siteId,
      'siteCode': siteCode,
      'siteName': siteName,
      'incomingLotRef': incomingLotRef,
      'purchaseRef': purchaseRef,
      'quantityAffected': quantityAffected,
      'uomCode': uomCode,
      'disposition': disposition,
      'detectedAt': detectedAt ?? DateTime.now().toUtc().toIso8601String(),
      'responseDueDate': responseDueDate,
      'responseDueAt': responseDueAt,
      'isOverdue': isOverdue,
      'daysOverdue': daysOverdue,
      'costRecovered': costRecovered,
      'currency': currency,
      'description': description,
      'closedAt': closedAt,
      'nonconformance': nonconformance,
    };

/// The Non-conformance a supplier NCR names, as the nested summary on the NCR's
/// own read sends it (issue #215) — mirrors the projection supplier-ncrs.js
/// builds from the linked `quality_issues` row.
Map<String, dynamic> supplierNcrNonconformanceJson(
  String id,
  String issueNo, {
  String status = 'open',
  String detectionPoint = 'incoming',
  String severity = 'major',
  num? quantityAffected = 250,
  String? detectedOn,
}) =>
    {
      'id': id,
      'issueNo': issueNo,
      'status': status,
      'detectionPoint': detectionPoint,
      'severity': severity,
      'quantityAffected': quantityAffected,
      'detectedOn': detectedOn,
    };

/// One Non-conformance as `GET /api/quality/nonconformances/:id` and the
/// register send it (issue #205) — mirrors `toNonconformance`
/// (nonconformances.js) key for key, `quantityChanges` included: the API
/// answers every non-conformance with its own history, so a fixture that
/// omitted it would let a test assert a shape the server cannot send.
Map<String, dynamic> nonconformanceJson(
  String id,
  String issueNo, {
  String status = 'open',
  String detectionPoint = 'in_process',
  String severity = 'minor',
  num quantityAffected = 1,
  num quantityDispositioned = 0,
  String uomCode = 'EA',
  String? lotRef,
  String? detectedAt,
  String? recordedByAccountId = '1',
  String? description,
  String? immediateContainment,
  String orgUnitId = '10',
  String orgUnitName = 'Line 1',
  String siteId = '1',
  String siteCode = 'HCM',
  String siteName = 'Ho Chi Minh',
  String productId = '40',
  String productCode = 'PRD-1',
  String productName = 'Gearbox',
  String defectCodeId = '41',
  String defectCodeCode = 'DIM-OOT',
  String defectCodeName = 'Out of tolerance',
  String defectCodeDefaultSeverity = 'minor',
  String? assetId,
  String? assetCode,
  String? assetName,
  String? shiftInstanceId,
  String? productionDate,
  String? shiftCode,
  String? shiftName,
  String? closedAt,
  List<Map<String, dynamic>>? quantityChanges,
  List<Map<String, dynamic>>? dispositions,
  List<Map<String, dynamic>>? corrections,
  List<Map<String, dynamic>>? concerns,
}) =>
    {
      'id': id,
      'issueNo': issueNo,
      'status': status,
      'detectionPoint': detectionPoint,
      'severity': severity,
      'quantityAffected': quantityAffected,
      'quantityDispositioned': quantityDispositioned,
      'uomCode': uomCode,
      'lotRef': lotRef,
      'detectedAt': detectedAt ?? DateTime.now().toUtc().toIso8601String(),
      'recordedByAccountId': recordedByAccountId,
      'description': description,
      'immediateContainment': immediateContainment,
      'orgUnitId': orgUnitId,
      'orgUnitName': orgUnitName,
      'siteId': siteId,
      'siteCode': siteCode,
      'siteName': siteName,
      'productId': productId,
      'productCode': productCode,
      'productName': productName,
      'defectCodeId': defectCodeId,
      'defectCodeCode': defectCodeCode,
      'defectCodeName': defectCodeName,
      'defectCodeDefaultSeverity': defectCodeDefaultSeverity,
      'assetId': assetId,
      'assetCode': assetCode,
      'assetName': assetName,
      'shiftInstanceId': shiftInstanceId,
      'productionDate': productionDate,
      'shiftCode': shiftCode,
      'shiftName': shiftName,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      'quantityChanges': quantityChanges ?? const <Map<String, dynamic>>[],
      'closedAt': closedAt,
      'dispositions': dispositions ?? const <Map<String, dynamic>>[],
      'corrections': corrections ?? const <Map<String, dynamic>>[],
      // The Concerns this record is evidence behind (issue #208), always
      // present — an empty list is "nothing is being done about the cause",
      // which is a state the Screen renders rather than a missing field.
      'concerns': concerns ?? const <Map<String, dynamic>>[],
    };

/// One Concern as the record's own detail read names it: the Action's number,
/// title, kind and status, plus whether it is the Concern the record was raised
/// from — mirrors `toConcern` (nonconformances.js) key for key, so a fixture
/// cannot let a test assert a shape the API does not send.
Map<String, dynamic> concernJson(
  Map<String, dynamic> action, {
  bool isSource = false,
}) =>
    {
      'id': action['id'],
      'actionNo': action['actionNo'],
      'title': action['title'],
      'actionType': action['actionType'],
      'status': action['status'],
      'priority': action['priority'],
      'ownerName': action['ownerName'],
      'dueDate': action['dueDate'],
      'isOverdue': action['isOverdue'] ?? false,
      'raisedAt': action['raisedAt'],
      'orgUnitId': action['orgUnitId'],
      'orgUnitName': action['orgUnitName'],
      'isSource': isSource,
      'linkedAt': '2026-09-15T03:00:00.000Z',
    };

/// One Non-conformance among a Concern's own `nonconformances` array (issue
/// #208) — mirrors `toLinkedNonconformance` (actions.js) key for key. Built
/// from a `nonconformanceJson` row so the two fixtures cannot drift apart about
/// what a Non-conformance is called.
///
/// The `dispositions` it carries (issue #212) are the row's own, passed through
/// unchanged: the server's read sends Quality's `toDisposition` shape there, so
/// a fixture built with `dispositionJson` rows is what the API would answer,
/// and the CAPA report's own section reads exactly those keys.
Map<String, dynamic> linkedNonconformanceJson(
  Map<String, dynamic> nonconformance, {
  bool isSource = false,
}) =>
    {
      'id': nonconformance['id'],
      'issueNo': nonconformance['issueNo'],
      'status': nonconformance['status'],
      'severity': nonconformance['severity'],
      'detectionPoint': nonconformance['detectionPoint'],
      'quantityAffected': nonconformance['quantityAffected'],
      'uomCode': nonconformance['uomCode'],
      'lotRef': nonconformance['lotRef'],
      'detectedAt': nonconformance['detectedAt'],
      'orgUnitId': nonconformance['orgUnitId'],
      'orgUnitName': nonconformance['orgUnitName'],
      'productId': nonconformance['productId'],
      'productCode': nonconformance['productCode'],
      'productName': nonconformance['productName'],
      'defectCodeId': nonconformance['defectCodeId'],
      'defectCodeCode': nonconformance['defectCodeCode'],
      'defectCodeName': nonconformance['defectCodeName'],
      'dispositions': nonconformance['dispositions'] ?? const <Map<String, dynamic>>[],
      'isSource': isSource,
      'linkedAt': '2026-09-15T03:00:00.000Z',
    };

/// One row of a Non-conformance's quantity history, as the API sends it —
/// mirrors `toQuantityChange` (nonconformances.js) key for key.
Map<String, dynamic> quantityChangeJson(
  String id,
  num previousQuantity,
  num newQuantity, {
  String? note,
  String? changedAt,
  String? changedByAccountId = '1',
  String? changedByAccountName = 'Ann Operator',
  String? changedByEmployeeId,
  String? changedByEmployeeName,
}) =>
    {
      'id': id,
      'previousQuantity': previousQuantity,
      'newQuantity': newQuantity,
      'changedAt': changedAt ?? DateTime.now().toUtc().toIso8601String(),
      'note': note,
      'changedByAccountId': changedByAccountId,
      'changedByAccountName': changedByAccountName,
      'changedByEmployeeId': changedByEmployeeId,
      'changedByEmployeeName': changedByEmployeeName,
    };

/// One Disposition as the API sends it (issue #206) — mirrors
/// `toDisposition` (nonconformances.js) key for key, so a fixture cannot let a
/// test assert a shape the server does not send.
Map<String, dynamic> dispositionJson(
  String id, {
  String dispositionType = 'scrap',
  bool? isConcession,
  num quantity = 1,
  String uomCode = 'EA',
  num reworkMinutes = 0,
  String? decidedAt,
  String? reference,
  String? note,
  String? decidedByAccountId = '1',
  String? decidedByAccountName = 'Ann Operator',
  String? decidedByEmployeeId,
  String? decidedByEmployeeName,
}) =>
    {
      'id': id,
      'dispositionType': dispositionType,
      'isConcession': isConcession ?? dispositionType == 'use_as_is',
      'quantity': quantity,
      'uomCode': uomCode,
      'reworkMinutes': reworkMinutes,
      'decidedAt': decidedAt ?? DateTime.now().toUtc().toIso8601String(),
      'reference': reference,
      'note': note,
      'decidedByAccountId': decidedByAccountId,
      'decidedByAccountName': decidedByAccountName,
      'decidedByEmployeeId': decidedByEmployeeId,
      'decidedByEmployeeName': decidedByEmployeeName,
    };

/// One correction as the API sends it (issue #206) — mirrors `toCorrection`
/// (nonconformances.js) key for key.
Map<String, dynamic> correctionJson(
  String id, {
  String kind = 'severity_lowered',
  String? previousSeverity = 'major',
  String? newSeverity = 'minor',
  String? previousStatus,
  String? newStatus,
  String note = 'Only the label was misprinted.',
  String? correctedAt,
  String? correctedByAccountId = '1',
  String? correctedByAccountName = 'Ann Operator',
}) =>
    {
      'id': id,
      'kind': kind,
      'previousSeverity': previousSeverity,
      'newSeverity': newSeverity,
      'previousStatus': previousStatus,
      'newStatus': newStatus,
      'note': note,
      'correctedAt': correctedAt ?? DateTime.now().toUtc().toIso8601String(),
      'correctedByAccountId': correctedByAccountId,
      'correctedByAccountName': correctedByAccountName,
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
  String? assetMeterId,
  String? meterCode,
  String? meterName,
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
      'assetMeterId': assetMeterId,
      'meterCode': meterCode,
      'meterName': meterName,
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
  String siteId = '1',
}) {
  final row = <String, dynamic>{
    'id': id,
    // `toOrgUnit` (plant.js) carries the Site id on every row it sends; a
    // fixture that moves an Asset between Sites needs it, which is why it is
    // here rather than left out.
    'siteId': siteId,
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
/// `qualityAuthority` is the flag independent of the level (issue #204,
/// ADR-0035), and `safetyAuthority` is the same shape again (issue #225) —
/// both false unless a test gives them, the same default the server's own
/// columns have.
Map<String, dynamic> grantJson(
  String orgUnitId, {
  String name = 'Assembly',
  String siteName = 'Ho Chi Minh',
  bool canWrite = false,
  bool qualityAuthority = false,
  bool safetyAuthority = false,
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
      'qualityAuthority': qualityAuthority,
      'safetyAuthority': safetyAuthority,
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
    this.selfEmployeeId,
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
    Map<String, List<Map<String, dynamic>>>? actions,
    this.actionsStatus = 200,
    Map<String, Map<String, dynamic>>? actionDetails,
    List<Map<String, dynamic>>? pillars,
    this.pillarsStatus = 200,
    this.createActionStatus = 201,
    this.createActionMessage = 'That concern could not be raised.',
    this.completePhaseStatus = 200,
    this.completePhaseMessage = 'this Action is waiting on its plan phase, not its do',
    this.raiseConcernStatus = 201,
    this.raiseConcernMessage = 'this Non-conformance was cancelled, so no Concern can be raised from it',
    this.linkNonconformanceStatus = 201,
    this.linkNonconformanceMessage = 'this Non-conformance is already linked to this Concern',
    this.unlinkNonconformanceStatus = 200,
    this.unlinkNonconformanceMessage =
        'the Non-conformance this Concern was raised from cannot be unlinked: the Concern records where it came from',
    this.createMeasureStatus = 201,
    this.createMeasureMessage = 'a measure answers a Concern, and that Action is not one',
    this.cancelActionStatus = 200,
    this.cancelActionMessage = 'this Concern still has 1 open measure: AC-TEST-2026-00008',
    this.escalationTargets = const [],
    this.escalationTargetsStatus = 200,
    this.escalationTargetsMessage = 'Action not found',
    this.escalateActionStatus = 200,
    this.escalateActionMessage = 'this Action has ended, so there is nothing to hand up',
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
    List<Map<String, dynamic>>? unitsOfMeasure,
    this.unitsOfMeasureStatus = 200,
    Map<String, List<Map<String, dynamic>>>? meters,
    this.metersStatus = 200,
    this.createMeterStatus = 201,
    this.createMeterMessage = 'this Asset already has a meter with that code',
    this.recordReadingStatus = 201,
    this.recordReadingMessage =
        'a cumulative meter cannot read lower than its last reading; record a rollover if the counter was reset',
    this.rolloverStatus = 201,
    this.rolloverMessage = 'That rollover could not be recorded.',
    Map<String, List<Map<String, dynamic>>>? workOrderTasks,
    this.workOrderDetailStatus = 200,
    Map<String, Map<String, dynamic>>? workOrderCosts,
    this.labourBookingStatus = 201,
    this.labourBookingMessage = 'That labour could not be booked.',
    this.partBookingStatus = 201,
    this.partBookingMessage = 'That part could not be booked.',
    this.board,
    this.boardStatus = 200,
    this.boardMessage = 'The tier board is unavailable.',
    List<Map<String, dynamic>>? parts,
    this.partsStatus = 200,
    this.createPartStatus = 201,
    this.createPartMessage = 'a Part with this part number already exists',
    Map<String, List<Map<String, dynamic>>>? stores,
    this.storesStatus = 200,
    Map<String, Map<String, dynamic>>? storeRows,
    Map<String, List<Map<String, dynamic>>>? stock,
    this.storeStockStatus = 200,
    this.createReceiptStatus = 201,
    this.createReceiptMessage = 'Part X has only 0 EA on the shelf; this movement would take it below zero.',
    Map<String, dynamic>? floor,
    List<Map<String, dynamic>>? floorWorkOrders,
    this.floorWorkOrdersStatus = 200,
    this.floorIdentifyStatus = 200,
    this.floorIdentifyMessage = 'That Employee number and PIN were not recognised',
    this.floorIdentificationToken = 'identification-1',
    Map<String, dynamic>? floorEmployee,
    this.floorCataloguesStatus = 200,
    this.floorNonconformanceStatus = 201,
    this.floorNonconformanceMessage = "Outside the caller's granted Org Units",
    List<Map<String, dynamic>>? products,
    this.productsStatus = 200,
    this.createProductStatus = 201,
    this.createProductMessage = 'a Product with this code already exists',
    this.updateProductStatus = 200,
    this.updateProductMessage = 'That Product could not be changed.',
    List<Map<String, dynamic>>? defectCodes,
    this.defectCodesStatus = 200,
    this.createDefectCodeStatus = 201,
    this.createDefectCodeMessage = 'a Defect code with this code already exists',
    this.updateDefectCodeStatus = 200,
    this.updateDefectCodeMessage = 'That Defect code could not be changed.',
    List<Map<String, dynamic>>? customers,
    this.customersStatus = 200,
    this.createCustomerStatus = 201,
    this.createCustomerMessage = 'a Customer with this code already exists',
    this.updateCustomerStatus = 200,
    this.updateCustomerMessage = 'That Customer could not be changed.',
    Map<String, List<Map<String, dynamic>>>? complaints,
    this.complaintsStatus = 200,
    this.complaintsTruncated = false,
    this.createComplaintStatus = 201,
    this.createComplaintMessage = 'customerId must be a valid Customer id',
    this.respondToComplaintStatus = 200,
    this.respondToComplaintMessage = 'responseNote is required to close a complaint',
    this.complaintNonconformanceStatus = 201,
    this.complaintNonconformanceMessage = 'that Non-conformance is about another Product',
    this.linkComplaintStatus = 200,
    this.linkComplaintMessage = 'this Customer complaint already names a Non-conformance',
    List<Map<String, dynamic>>? suppliers,
    this.suppliersStatus = 200,
    this.createSupplierStatus = 201,
    this.createSupplierMessage = 'a Supplier with this code already exists',
    this.updateSupplierStatus = 200,
    this.updateSupplierMessage = 'That Supplier could not be changed.',
    Map<String, List<Map<String, dynamic>>>? supplierNcrs,
    this.supplierNcrsStatus = 200,
    this.supplierNcrsTruncated = false,
    this.createSupplierNcrStatus = 201,
    this.createSupplierNcrMessage = 'supplierId must be a valid Supplier id',
    this.supplierNcrDispositionStatus = 200,
    this.supplierNcrDispositionMessage = 'disposition must be one of: return_to_supplier, scrap',
    this.supplierNcrCloseStatus = 200,
    this.supplierNcrCloseMessage = 'that supplier NCR is closed and cannot be changed',
    this.supplierNcrNonconformanceStatus = 201,
    this.supplierNcrNonconformanceMessage =
        'productId is required: this supplier NCR carries no Product to record the Non-conformance about',
    this.linkSupplierNcrStatus = 200,
    this.linkSupplierNcrMessage = 'this supplier NCR already names a Non-conformance',
    Map<String, List<Map<String, dynamic>>>? nonconformances,
    this.nonconformancesStatus = 200,
    this.nonconformancesTruncated = false,
    this.createNonconformanceStatus = 201,
    this.createNonconformanceMessage = 'productId must be a valid Product id',
    this.changeNonconformanceStatus = 200,
    this.changeNonconformanceMessage = 'severity cannot be lowered; only a holder of Quality authority may do that',
    this.increaseNonconformanceQuantityStatus = 200,
    this.increaseNonconformanceQuantityMessage = 'the affected quantity can only be increased',
    this.recordNonconformanceActStatus = 201,
    this.recordNonconformanceActMessage =
        'that is more than the quantity still undecided on this Non-conformance',
    Map<String, Map<String, dynamic>>? capas,
    this.capasStatus = 200,
    this.capaMessage = 'That CAPA could not be read.',
    this.createCapaStatus = 201,
    this.createCapaMessage = 'this Concern already has a CAPA',
    this.addWhyStatus = 201,
    this.addWhyMessage = "writing a CAPA's root causes needs edit access at its Org Unit, "
        'or a place on its team',
    this.changeWhyStatus = 200,
    this.changeWhyMessage =
        "writing a CAPA's root causes needs edit access at its Org Unit, or a place on its team",
    this.removeWhyStatus = 200,
    this.removeWhyMessage =
        "writing a CAPA's root causes needs edit access at its Org Unit, or a place on its team",
    this.addCauseStatus = 201,
    this.addCauseMessage =
        "writing a CAPA's root causes needs edit access at its Org Unit, or a place on its team",
    this.changeCauseStatus = 200,
    this.changeCauseMessage = 'That cause could not be changed.',
    this.removeCauseStatus = 200,
    this.removeCauseMessage = 'That cause could not be removed.',
    this.startWhyFromCauseStatus = 201,
    this.startWhyFromCauseMessage =
        'only a confirmed cause can start a chain, and this one is candidate',
    this.capaListStatus = 200,
    this.capaListMessage = 'The CAPA list could not be read.',
    this.effectivenessStatus = 200,
    this.effectivenessMessage =
        "recording a CAPA's effectiveness check needs Quality authority at its Org Unit",
  })  : queue = queue ?? [],
        assets = assets ?? {},
        actions = actions ?? {},
        actionDetails = actionDetails ?? {},
        pillars = pillars ??
            [
              pillarJson('S', 'Safety', 1),
              pillarJson('Q', 'Quality', 2),
              pillarJson('D', 'Delivery', 3),
              pillarJson('C', 'Cost', 4),
              pillarJson('P', 'People', 5),
            ],
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
        unitsOfMeasure = unitsOfMeasure ??
            [
              unitOfMeasureJson('H', 'Hour'),
              unitOfMeasureJson('EA', 'Each', dimension: 'count'),
            ],
        meters = meters ?? {},
        workOrderTasks = workOrderTasks ?? {},
        workOrderCosts = workOrderCosts ?? {},
        parts = parts ?? [],
        stores = stores ?? {},
        storeRows = storeRows ?? {},
        stock = stock ?? {},
        floor = floor ?? {'orgUnitId': '10', 'orgUnitName': 'Line 1', 'siteId': '1'},
        floorWorkOrders = floorWorkOrders ?? [],
        floorEmployee = floorEmployee ??
            {'id': '20', 'employeeNo': 'EMP-20', 'displayName': 'Tess Technician'},
        products = products ?? [],
        defectCodes = defectCodes ?? [],
        customers = customers ?? [],
        complaints = complaints ?? {},
        suppliers = suppliers ?? [],
        supplierNcrs = supplierNcrs ?? {},
        nonconformances = nonconformances ?? {},
        capas = capas ?? {};

  /// `GET /api/quality/products` (issue #203) — the Product catalogue.
  List<Map<String, dynamic>> products;

  int productsStatus;

  /// `POST /api/quality/products` (administrator only).
  int createProductStatus;
  String createProductMessage;

  /// `PATCH /api/quality/products/:id` (administrator only).
  int updateProductStatus;
  String updateProductMessage;

  /// Every Product create body that actually reached the wire, decoded — so a
  /// test can assert exactly one request was sent and what it carried.
  final List<Map<String, dynamic>> productPosts = [];

  /// Every Product correction body that actually reached the wire, as
  /// `(id, body)` — so a test can assert that a correction sent only the field
  /// that changed, and that a non-administrator's Screen sent nothing at all.
  final List<(String, Map<String, dynamic>)> productPatches = [];

  /// Every Product list request's query parameters, in the order they reached
  /// the wire — `includeInactive` and `search` carried through exactly as sent,
  /// so a test proves what the Screen asked for rather than what the Fake Wire
  /// happened to apply.
  final List<Map<String, String>> productListRequests = [];

  /// `GET /api/quality/defect-codes`.
  List<Map<String, dynamic>> defectCodes;

  int defectCodesStatus;

  /// `POST /api/quality/defect-codes` (administrator only).
  int createDefectCodeStatus;
  String createDefectCodeMessage;

  /// `PATCH /api/quality/defect-codes/:id` (administrator only).
  int updateDefectCodeStatus;
  String updateDefectCodeMessage;

  /// Every Defect code create body that actually reached the wire, decoded.
  final List<Map<String, dynamic>> defectCodePosts = [];

  /// Every Defect code correction body that actually reached the wire, as
  /// `(id, body)`.
  final List<(String, Map<String, dynamic>)> defectCodePatches = [];

  /// Every Defect code list request's query parameters.
  final List<Map<String, String>> defectCodeListRequests = [];

  /// `GET /api/quality/customers` (issue #214) — the Customer list.
  List<Map<String, dynamic>> customers;
  int customersStatus;

  /// `POST /api/quality/customers` (administrator only).
  int createCustomerStatus;
  String createCustomerMessage;

  /// `PATCH /api/quality/customers/:id` (administrator only).
  int updateCustomerStatus;
  String updateCustomerMessage;

  /// Every Customer create body that reached the wire, decoded.
  final List<Map<String, dynamic>> customerPosts = [];

  /// Every Customer correction body that reached the wire, as `(id, body)`.
  final List<(String, Map<String, dynamic>)> customerPatches = [];

  /// Every Customer list request's query parameters.
  final List<Map<String, String>> customerListRequests = [];

  /// `GET /api/quality/sites/:siteId/complaints` (issue #214) — the register,
  /// keyed by Site id. The wire applies the two filters the address takes:
  /// `status`, and `orgUnitId` with everything beneath it (by walking the same
  /// `orgUnits` fixture the Non-conformance register uses).
  Map<String, List<Map<String, dynamic>>> complaints;
  int complaintsStatus;
  bool complaintsTruncated;

  /// `POST /api/quality/sites/:siteId/complaints` — recording one.
  int createComplaintStatus;
  String createComplaintMessage;

  /// `POST /api/quality/complaints/:id/respond` — closing it with its
  /// response.
  int respondToComplaintStatus;
  String respondToComplaintMessage;

  /// `POST /api/quality/complaints/:id/nonconformance` — recording the record
  /// that controls the complained-of product.
  int complaintNonconformanceStatus;
  String complaintNonconformanceMessage;

  /// `POST /api/quality/complaints/:id/link` — linking an existing one.
  int linkComplaintStatus;
  String linkComplaintMessage;

  /// Every complaint record body that reached the wire, decoded.
  final List<Map<String, dynamic>> complaintPosts = [];

  /// Every complaint response body, as `(id, body)`.
  final List<(String, Map<String, dynamic>)> complaintResponds = [];

  /// Every record-from-complaint body, as `(id, body)`.
  final List<(String, Map<String, dynamic>)> complaintNonconformancePosts = [];

  /// Every link body, as `(id, body)`.
  final List<(String, Map<String, dynamic>)> complaintLinks = [];

  /// Every complaint list request's query parameters, in the order they reached
  /// the wire — so a test proves what the Screen asked for rather than what
  /// this Fake Wire happened to apply.
  final List<Map<String, String>> complaintListRequests = [];

  /// Every complaint detail read's path, in order.
  final List<String> complaintReads = [];

  /// `GET /api/quality/suppliers` (issue #215) — the Supplier list.
  List<Map<String, dynamic>> suppliers;
  int suppliersStatus;

  /// `POST /api/quality/suppliers` (administrator only).
  int createSupplierStatus;
  String createSupplierMessage;

  /// `PATCH /api/quality/suppliers/:id` (administrator only).
  int updateSupplierStatus;
  String updateSupplierMessage;

  /// Every Supplier create body that reached the wire, decoded.
  final List<Map<String, dynamic>> supplierPosts = [];

  /// Every Supplier correction body that reached the wire, as `(id, body)`.
  final List<(String, Map<String, dynamic>)> supplierPatches = [];

  /// Every Supplier list request's query parameters.
  final List<Map<String, String>> supplierListRequests = [];

  /// `GET /api/quality/sites/:siteId/supplier-ncrs` (issue #215) — the register,
  /// keyed by Site id. The wire applies the three filters the address takes:
  /// `status`, `supplierId`, and `orgUnitId` with everything beneath it (by
  /// walking the same `orgUnits` fixture the Non-conformance register uses).
  Map<String, List<Map<String, dynamic>>> supplierNcrs;
  int supplierNcrsStatus;
  bool supplierNcrsTruncated;

  /// `POST /api/quality/sites/:siteId/supplier-ncrs` — recording one.
  int createSupplierNcrStatus;
  String createSupplierNcrMessage;

  /// `POST /api/quality/supplier-ncrs/:id/disposition` — the Supplier's
  /// disposition and what was recovered.
  int supplierNcrDispositionStatus;
  String supplierNcrDispositionMessage;

  /// `POST /api/quality/supplier-ncrs/:id/close` — the one transition.
  int supplierNcrCloseStatus;
  String supplierNcrCloseMessage;

  /// `POST /api/quality/supplier-ncrs/:id/nonconformance` — recording the record
  /// that controls the received lot.
  int supplierNcrNonconformanceStatus;
  String supplierNcrNonconformanceMessage;

  /// `POST /api/quality/supplier-ncrs/:id/link` — linking an existing one.
  int linkSupplierNcrStatus;
  String linkSupplierNcrMessage;

  /// Every supplier NCR record body that reached the wire, decoded.
  final List<Map<String, dynamic>> supplierNcrPosts = [];

  /// Every disposition body, as `(id, body)`.
  final List<(String, Map<String, dynamic>)> supplierNcrDispositions = [];

  /// Every close, as the id it named.
  final List<String> supplierNcrCloses = [];

  /// Every record-from-NCR body, as `(id, body)`.
  final List<(String, Map<String, dynamic>)> supplierNcrNonconformancePosts = [];

  /// Every link body, as `(id, body)`.
  final List<(String, Map<String, dynamic>)> supplierNcrLinks = [];

  /// Every supplier NCR list request's query parameters, in the order they
  /// reached the wire — so a test proves what the Screen asked for rather than
  /// what this Fake Wire happened to apply.
  final List<Map<String, String>> supplierNcrListRequests = [];

  /// Every supplier NCR detail read's path, in order.
  final List<String> supplierNcrReads = [];

  /// `GET /api/quality/sites/:siteId/nonconformances` (issue #205) — the
  /// register, keyed by Site id.
  ///
  /// The wire applies the filters it has enough on a row to honour honestly:
  /// `orgUnitId` (the row's own Org Unit or any descendant of it, by walking
  /// the `orgUnits` fixture), `status`, `defectCodeId`, `productId`,
  /// `severity` and the production-day range. `serve` is a client-side read
  /// filter, and what the *Screen* asked for is asserted from
  /// [nonconformanceListRequests] rather than from this.
  Map<String, List<Map<String, dynamic>>> nonconformances;
  int nonconformancesStatus;
  bool nonconformancesTruncated;

  /// `POST /api/quality/sites/:siteId/nonconformances` — recording one. A
  /// refusal is scripted with [createNonconformanceStatus], the shape every
  /// other write's `status` field keeps.
  int createNonconformanceStatus;
  String createNonconformanceMessage;

  /// `PATCH /api/quality/nonconformances/:id` — raising the severity and
  /// recording containment.
  int changeNonconformanceStatus;
  String changeNonconformanceMessage;

  /// `POST /api/quality/nonconformances/:id/quantity` — increasing the
  /// affected quantity.
  int increaseNonconformanceQuantityStatus;
  String increaseNonconformanceQuantityMessage;

  /// The five writes issue #206 adds — the Disposition, the Concession, the
  /// lowered severity, the reopen and the cancel. One refusal pair for all
  /// five: a test scripts the answer the API would give (a 409 for a
  /// Disposition larger than what is undecided, a 403 for a caller without
  /// Quality authority) and points it at whichever address it is about.
  int recordNonconformanceActStatus;
  String recordNonconformanceActMessage;

  /// Every Non-conformance list request's query parameters, in the order they
  /// reached the wire — so a test proves what the Screen asked for (which
  /// filters, and only the filters that are set) rather than what this Fake
  /// Wire happened to apply.
  final List<Map<String, String>> nonconformanceListRequests = [];

  /// Every Non-conformance detail read's path, in order — `GET
  /// /api/quality/nonconformances/:id`, so a test can prove which record the
  /// Screen went and read.
  final List<String> nonconformanceReads = [];

  /// Every recording body that actually reached the wire, decoded.
  final List<Map<String, dynamic>> nonconformancePosts = [];

  /// Every change body that reached the wire, as `(id, body)` — a severity
  /// raising or a containment, never both in one request.
  final List<(String, Map<String, dynamic>)> nonconformancePatches = [];

  /// Every quantity body that reached the wire, as `(id, body)`.
  final List<(String, Map<String, dynamic>)> nonconformanceQuantityPosts = [];

  /// Every Disposition body that reached the wire, as `(id, body)` (issue
  /// #206) — a record against an id, never the register.
  final List<(String, Map<String, dynamic>)> nonconformanceDispositionPosts = [];

  /// Every Concession body that reached the wire, as `(id, body)`.
  final List<(String, Map<String, dynamic>)> nonconformanceConcessionPosts = [];

  /// Every lowered-severity body that reached the wire, as `(id, body)`.
  final List<(String, Map<String, dynamic>)> nonconformanceLowerSeverityPosts = [];

  /// Every reopen body that reached the wire, as `(id, body)`.
  final List<(String, Map<String, dynamic>)> nonconformanceReopenPosts = [];

  /// Every cancel body that reached the wire, as `(id, body)`.
  final List<(String, Map<String, dynamic>)> nonconformanceCancelPosts = [];

  /// Looks a Non-conformance up by id across every Site's list, which is what
  /// the detail route does — a record read by address, not by Site.
  Map<String, dynamic>? nonconformanceById(String id) {
    for (final rows in nonconformances.values) {
      for (final row in rows) {
        if (row['id'] == id) return row;
      }
    }
    return null;
  }

  /// [orgUnitId] and every Org Unit beneath it, read off the `orgUnits`
  /// fixture (keyed by parent id) — what `?orgUnitId=` means on the real
  /// register, where the narrowing is the baseline's own ltree walk
  /// (`ou.path <@ $path`).
  Set<String> nonconformanceOrgUnitScope(String orgUnitId) {
    final found = <String>{orgUnitId};
    var grew = true;
    while (grew) {
      grew = false;
      for (final entry in orgUnits.entries) {
        final parent = entry.key;
        if (parent == null || !found.contains(parent)) continue;
        for (final child in entry.value) {
          if (found.add(child['id'] as String)) grew = true;
        }
      }
    }
    return found;
  }

  final String role;

  /// What `/me` reports as this caller's own Org Unit scope (issue #43).
  final Map<String, dynamic>? orgUnitScope;

  /// `GET /api/maintenance/sites/:siteId/assets`, keyed by Site id.
  Map<String, List<Map<String, dynamic>>> assets;
  int assetsStatus;

  /// `GET /api/actions/sites/:siteId/actions` (issue #176), keyed by Site id.
  ///
  /// The wire applies the filters it has enough on a row to honour honestly:
  /// `status`, `actionType`, `pillarCode` and `includeHistory` (a row whose
  /// `status` is `done`/`cancelled` is sent only when history is asked for,
  /// exactly as `actions.js`'s own `OPEN_STATUSES` clause does), plus
  /// `orgUnitId` as an **exact match** on the row's Org Unit — the real
  /// endpoint includes the whole branch beneath the one named, which a fake
  /// holding flat rows cannot model, so a test asserting the branch behaviour
  /// belongs in the backend suite rather than here.
  Map<String, List<Map<String, dynamic>>> actions;
  int actionsStatus;

  /// Every Actions read's full URI, in the order it reached the wire — the
  /// only way a widget test can prove which filters a Screen actually sent,
  /// since the recorded `requests` list carries the path and not the query.
  final List<Uri> actionReads = [];

  /// When set, an Actions read hangs until the test completes it — what "in
  /// flight" means to a widget test, the same shape `assetsGate` has.
  Completer<void>? actionsGate;

  /// `GET /api/actions/:id` — one Action by id, for the detail Screen.
  Map<String, Map<String, dynamic>> actionDetails;

  /// `GET /api/actions/pillars` — the raise form's Pillar catalogue.
  List<Map<String, dynamic>> pillars;
  int pillarsStatus;

  /// Every body sent to `POST /api/actions/sites/:siteId/actions`.
  final List<Map<String, dynamic>> actionPosts = [];
  int createActionStatus;
  String createActionMessage;

  /// The Org Units the fake says are above an Action, in the order the server
  /// would send them, and what `escalation-targets` answers with when it is not
  /// a plain 200.
  List<Map<String, dynamic>> escalationTargets;
  int escalationTargetsStatus;
  String escalationTargetsMessage;

  /// Every escalation that reached the wire, as `(actionId, body)`.
  final List<(String, Map<String, dynamic>)> escalations = [];
  int escalateActionStatus;
  String escalateActionMessage;

  /// Every cancellation that reached the wire, as `(actionId, body)`.
  final List<(String, Map<String, dynamic>)> cancellations = [];
  int cancelActionStatus;
  String cancelActionMessage;

  /// Every measure raise that reached the wire, as `(concernId, body)`.
  final List<(String, Map<String, dynamic>)> measurePosts = [];
  int createMeasureStatus;
  String createMeasureMessage;

  /// Every phase completion that reached the wire, as `(actionId, phase, body)`
  /// — the assertion a test makes about what the dialog collected.
  final List<(String, String, Map<String, dynamic>)> phaseCompletions = [];
  int completePhaseStatus;
  String completePhaseMessage;

  /// Every Concern raised from a Non-conformance that reached the wire
  /// (issue #208), as `(nonconformanceId, body)` — `POST
  /// /api/actions/nonconformances/:id/concern`.
  final List<(String, Map<String, dynamic>)> concernRaisePosts = [];
  int raiseConcernStatus;
  String raiseConcernMessage;

  /// Every link that reached the wire, as `(concernId, body)` — `POST
  /// /api/actions/:id/nonconformances`.
  final List<(String, Map<String, dynamic>)> nonconformanceLinkPosts = [];
  int linkNonconformanceStatus;
  String linkNonconformanceMessage;

  /// Every unlink that reached the wire, as `(concernId, nonconformanceId)` —
  /// `POST /api/actions/:id/nonconformances/:nonconformanceId/unlink`.
  final List<(String, String)> nonconformanceUnlinkPosts = [];
  int unlinkNonconformanceStatus;
  String unlinkNonconformanceMessage;

  /// The Concern a raise answers with, when a test wants the row the server
  /// would have written named differently. Null means the fake builds one from
  /// the request.
  Map<String, dynamic>? raisedConcern;

  /// The Non-conformance rows a link answers with, keyed by Concern id — what
  /// a test scripts the Concern's own read to show after a link. The fake
  /// appends to a stored detail when it can, and this is the escape hatch for
  /// a case where the stored detail is not the one under test.
  Map<String, List<Map<String, dynamic>>> linkedNonconformances = {};

  /// `GET /api/actions/capas/:id` (issue #209) — one CAPA by id, keyed by its
  /// own id (a CAPA's id space is `capas`', not the action log's).
  ///
  /// `POST /api/actions/:id/capa` writes into it, so a Screen that follows a
  /// raise to the CAPA's own address reads the row that write produced rather
  /// than a fixture a test had to keep in step with it.
  Map<String, Map<String, dynamic>> capas;
  int capasStatus;
  String capaMessage;

  /// Every CAPA read (issues #209, #212) — the id each `GET
  /// /api/actions/capas/:id` asked for, in the order the requests reached the
  /// wire. A report Screen makes exactly one of them, and that is a fact a test
  /// has to be able to read rather than assume.
  final List<String> capaReads = [];

  /// Every CAPA open that reached the wire, as `(concernId, body)` — so a test
  /// can assert that exactly one request was sent, what it carried, and that a
  /// caller without Quality authority sent nothing at all.
  final List<(String, Map<String, dynamic>)> capaPosts = [];

  /// `POST /api/actions/:id/capa` — the refusal a test scripts (409 for a
  /// second CAPA, 403 for a caller without Quality authority).
  int createCapaStatus;
  String createCapaMessage;

  /// The CAPA a raise answers with, when a test wants its own ids to be the
  /// ones on screen. Null means the fake builds one from the Concern.
  Map<String, dynamic>? openedCapa;

  /// Every Why added through the wire (issue #210), as `(capaId, body)` — so a
  /// test can assert exactly one request was sent, that it named the chain the
  /// dialog was opened at, and that a reader who may not write sent nothing.
  final List<(String, Map<String, dynamic>)> whyPosts = [];

  /// `POST /api/actions/capas/:id/whys` — the refusal a test scripts (403 for
  /// a caller with neither edit access nor a place on the team, 409 for a
  /// closed investigation, 400 for a chain that is not one of the two).
  int addWhyStatus;
  String addWhyMessage;

  /// Every change to one Why, as `(capaId, whyId, body)` — the body carrying
  /// only the fields the request named, which is the partial update the API
  /// takes.
  final List<(String, String, Map<String, dynamic>)> whyPatches = [];

  /// `PATCH /api/actions/capas/:id/whys/:whyId` — the refusal a test scripts.
  int changeWhyStatus;
  String changeWhyMessage;

  /// Every Why removed, as `(capaId, whyId)` — the delete this Platform's
  /// chain editing is the first to make.
  final List<(String, String)> whyDeletions = [];

  /// `DELETE /api/actions/capas/:id/whys/:whyId` — the refusal a test scripts.
  int removeWhyStatus;
  String removeWhyMessage;

  /// The next id the fake gives a Why it creates, so two adds in one test are
  /// two rows. Ids the fixture already carries are its own.
  int _nextWhyId = 900;

  /// Every candidate cause recorded through the wire (issue #213), as
  /// `(capaId, body)` — so a test can assert exactly one request was sent, that
  /// it named the 6M category the form was opened at, and that a reader who may
  /// not write sent nothing.
  final List<(String, Map<String, dynamic>)> causePosts = [];

  /// `POST /api/actions/capas/:id/causes` — the refusal a test scripts (403 for
  /// a caller with neither edit access nor a place on the team, 409 for a
  /// closed investigation, 400 for a category that is not one of the six).
  int addCauseStatus;
  String addCauseMessage;

  /// Every change to one candidate cause, as `(capaId, causeId, body)` — the
  /// body carrying only the fields the request named, which is the partial
  /// update the API takes.
  final List<(String, String, Map<String, dynamic>)> causePatches = [];

  /// `PATCH /api/actions/capas/:id/causes/:causeId` — the refusal a test
  /// scripts (400 for a verdict without its evidence).
  int changeCauseStatus;
  String changeCauseMessage;

  /// Every candidate cause removed, as `(capaId, causeId)`.
  final List<(String, String)> causeDeletions = [];

  /// `DELETE /api/actions/capas/:id/causes/:causeId` — the refusal a test
  /// scripts.
  int removeCauseStatus;
  String removeCauseMessage;

  /// Every chain started from a cause (issue #213), as
  /// `(capaId, causeId, body)` — so a test can assert the chain the form
  /// offered was the one sent, and that a candidate's row sent no offer at all.
  final List<(String, String, Map<String, dynamic>)> causeWhyPosts = [];

  /// `POST /api/actions/capas/:id/causes/:causeId/whys` — the refusal a test
  /// scripts (409 for a cause that is not confirmed, 409 for a chain that has
  /// already started).
  int startWhyFromCauseStatus;
  String startWhyFromCauseMessage;

  /// The next id the fake gives a candidate cause it creates.
  int _nextCauseId = 950;

  /// `GET /api/actions/capas` (issue #211) — the CAPA list, and the query
  /// parameters every request carried, so a test proves what the Screen asked
  /// for (`orgUnitId`, `status`, `overdue`) rather than what the fake happened
  /// to apply.
  final List<Map<String, String>> capaListRequests = [];
  int capaListStatus;
  String capaListMessage;

  /// Every effectiveness check recorded through the wire (issue #211), as
  /// `(capaId, body)` — so a test can assert exactly one request was sent, what
  /// verdict and note it carried, and that a caller the rule refuses sent
  /// nothing at all.
  final List<(String, Map<String, dynamic>)> effectivenessPosts = [];

  /// `POST /api/actions/capas/:id/effectiveness` — the refusal a test scripts
  /// (403 for a caller without Quality authority or for the team lead, 409 for
  /// a Concern that has not closed).
  int effectivenessStatus;
  String effectivenessMessage;

  /// One row of a CAPA's team, resolved off the `employees` fixture — the way
  /// the server's own read joins the directory for a display name.
  Map<String, dynamic>? _capaTeamRow(Object? employeeId) {
    if (employeeId == null) return null;
    final id = employeeId.toString();
    for (final employee in employees) {
      if (employee['id'] == id) {
        return {'employeeId': id, 'name': employee['displayName']};
      }
    }
    return {'employeeId': id, 'name': ''};
  }

  /// The stored Why with this id, or null when the CAPA does not hold one.
  static Map<String, dynamic>? _storedWhy(Map<String, dynamic> capa, String whyId) {
    for (final why in (capa['whys'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()) {
      if (why['id'].toString() == whyId) return why;
    }
    return null;
  }

  /// Applies a change to a stored CAPA's Why the way the server would
  /// (issue #210): the statement replaced when it was sent, the whole chain
  /// renumbered around a move, and a root-cause mark that replaces whatever the
  /// chain's root was. Returns whether the CAPA holds the Why at all — a
  /// request against one it does not is the server's 404.
  ///
  /// The rules, not the wording: the backend suite is where they are proved.
  /// What this buys is that a Screen's own rendering is tested against the
  /// answer the API really gives, rather than against a body a test wrote for
  /// it.
  static bool _changeStoredWhy(
    Map<String, dynamic> capa,
    String whyId,
    Map<String, dynamic> body,
  ) {
    final whys = (capa['whys'] as List<dynamic>? ?? <dynamic>[]);
    final why = _storedWhy(capa, whyId);
    if (why == null) return false;

    if (body.containsKey('statement')) {
      why['statement'] = body['statement'];
    }
    if (body['isRoot'] == true) {
      for (final other in whys.whereType<Map<String, dynamic>>()) {
        if (other['chain'] == why['chain']) {
          other['isRoot'] = other['id'].toString() == whyId;
        }
      }
    } else if (body['isRoot'] == false) {
      why['isRoot'] = false;
    }
    final sequence = body['sequence'];
    if (sequence is int) {
      final siblings = [
        for (final each in whys.whereType<Map<String, dynamic>>())
          if (each['chain'] == why['chain'] && each['id'].toString() != whyId) each,
      ];
      siblings.insert((sequence - 1).clamp(0, siblings.length), why);
      for (var index = 0; index < siblings.length; index++) {
        siblings[index]['sequence'] = index + 1;
      }
    }
    capa['whys'] = whys;
    return true;
  }

  /// Removes a stored CAPA's Why and closes the gap the way the server would
  /// (issue #210): the chain is renumbered from what is left, so it still reads
  /// 1..n. Returns whether the CAPA held it.
  static bool _removeStoredWhy(Map<String, dynamic> capa, String whyId) {
    final whys = (capa['whys'] as List<dynamic>? ?? <dynamic>[]);
    final why = _storedWhy(capa, whyId);
    if (why == null) return false;

    final chain = why['chain'];
    whys.remove(why);
    var position = 0;
    for (final each in whys.whereType<Map<String, dynamic>>()) {
      if (each['chain'] == chain) {
        position += 1;
        each['sequence'] = position;
      }
    }
    capa['whys'] = whys;
    return true;
  }

  /// The stored candidate cause with this id, or null when the CAPA's fishbone
  /// does not hold one.
  static Map<String, dynamic>? _storedCause(Map<String, dynamic> capa, String causeId) {
    for (final cause in (capa['causes'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()) {
      if (cause['id'].toString() == causeId) return cause;
    }
    return null;
  }

  /// Applies a change to a stored CAPA's candidate cause the way the server
  /// would (issue #213): the sentence and the category when they were sent, and
  /// the verdict with its evidence together — `candidate` clearing the note it
  /// no longer has a decision to be the evidence of. Returns whether the CAPA's
  /// fishbone holds the cause at all; a request against one it does not is the
  /// server's 404.
  ///
  /// The rules, not the wording: the backend suite is where they are proved.
  /// What this buys is that a Screen's own rendering is tested against the
  /// answer the API really gives.
  static bool _changeStoredCause(
    Map<String, dynamic> capa,
    String causeId,
    Map<String, dynamic> body,
  ) {
    final cause = _storedCause(capa, causeId);
    if (cause == null) return false;

    if (body.containsKey('category')) {
      cause['category'] = body['category'];
    }
    if (body.containsKey('statement')) {
      cause['statement'] = body['statement'];
    }
    if (body.containsKey('verdict')) {
      cause['verdict'] = body['verdict'];
      cause['evidenceNote'] = body['verdict'] == 'candidate' ? null : body['evidenceNote'];
    } else if (body.containsKey('evidenceNote')) {
      cause['evidenceNote'] = body['evidenceNote'];
    }
    return true;
  }

  /// Removes a stored CAPA's candidate cause the way the server does — the row
  /// goes, and the category's remaining positions are left as they were
  /// (issue #213). Returns whether the CAPA's fishbone held it.
  static bool _removeStoredCause(Map<String, dynamic> capa, String causeId) {
    final causes = (capa['causes'] as List<dynamic>? ?? <dynamic>[]);
    final cause = _storedCause(capa, causeId);
    if (cause == null) return false;

    causes.remove(cause);
    capa['causes'] = causes;
    return true;
  }

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

  /// The Employee the caller's own Account is linked to, as `/me` reports it
  /// (issue #210) — `app_users.employee_id`, which the server has always
  /// answered with. Null is the ordinary case for an administrator, who need
  /// not be an Employee; a test that wants the caller on a CAPA's *team* sets
  /// this to an Employee the CAPA names, which is the whole second half of the
  /// write rule for a CAPA's chains.
  final String? selfEmployeeId;
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

  /// When set, a `GET /api/people/skills` read hangs until the test completes
  /// it — the same device [workOrdersGate] uses, needed to prove the catalogue
  /// shows its placeholder while the read is in flight rather than a bare
  /// spinner (issue #189).
  Completer<void>? skillsGate;

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

  /// `GET /api/maintenance/units-of-measure` (issue #79, reused by #80) — the
  /// unit picker the meter form and the Part form both read.
  List<Map<String, dynamic>> unitsOfMeasure;
  int unitsOfMeasureStatus;

  /// `GET /api/maintenance/sites/:siteId/meters` (issue #79), keyed by Site id.
  Map<String, List<Map<String, dynamic>>> meters;
  int metersStatus;

  /// Every meter read's Site id, in the order it reached the wire.
  final List<String> meterSites = [];

  /// When set, a meter read hangs until the test completes it.
  Completer<void>? metersGate;

  /// `POST /api/maintenance/meters`.
  int createMeterStatus;
  String createMeterMessage;

  /// Every meter create body that actually reached the wire, decoded.
  final List<Map<String, dynamic>> meterPosts = [];

  /// `POST /api/maintenance/meters/:id/readings`.
  int recordReadingStatus;
  String recordReadingMessage;

  /// Every reading that reached the wire, as `(meterId, body)`.
  final List<(String, Map<String, dynamic>)> meterReadingPosts = [];

  /// `POST /api/maintenance/meters/:id/rollover`.
  int rolloverStatus;
  String rolloverMessage;

  /// Every rollover that reached the wire, as `(meterId, body)`.
  final List<(String, Map<String, dynamic>)> meterRolloverPosts = [];

  /// Every Work order task reading that reached the wire, as
  /// `(workOrderId, taskId, body)` (issue #79).
  final List<(String, String, Map<String, dynamic>)> taskReadingPosts = [];

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

  /// What a Work order has cost so far (issue #75), keyed by Work order id —
  /// the `cost` object the detail read answers with. Absent means the empty
  /// cost. A booking handler appends to this so the re-read reflects it.
  Map<String, Map<String, dynamic>> workOrderCosts;

  /// `POST /api/maintenance/work-orders/:id/labour` (issue #75).
  int labourBookingStatus;
  String labourBookingMessage;

  /// Every labour booking that reached the wire, as `(workOrderId, body)` — so
  /// a test can assert exactly one request was sent and what window and
  /// activity it carried.
  final List<(String, Map<String, dynamic>)> labourPosts = [];

  /// `POST /api/maintenance/work-orders/:id/parts` (issue #75).
  int partBookingStatus;
  String partBookingMessage;

  /// Every part booking that reached the wire, as `(workOrderId, body)`.
  final List<(String, Map<String, dynamic>)> partBookingPosts = [];

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

  /// `GET /api/maintenance/floor/work-orders` (issue #77) — the device's own
  /// read. [floor] is the Org Unit context the server names, and
  /// [floorWorkOrders] the Open work it returns.
  Map<String, dynamic> floor;
  List<Map<String, dynamic>> floorWorkOrders;
  int floorWorkOrdersStatus;

  /// Every floor read's device credential, in the order it reached the wire.
  final List<String> floorReads = [];

  /// When set, a floor read hangs until the test completes it — the same
  /// device [workOrdersGate] uses, needed to prove the placeholders show while
  /// the read is still in flight.
  Completer<void>? floorGate;

  /// `POST /api/maintenance/floor/identify` (issue #77).
  int floorIdentifyStatus;
  String floorIdentifyMessage;
  String floorIdentificationToken;

  /// The Employee the identify exchange resolves to.
  Map<String, dynamic> floorEmployee;

  /// Every identify request that reached the wire, as `{employeeNo, pin,
  /// device}` — so a test can assert the credential the technician typed and
  /// the device it was presented to.
  final List<Map<String, dynamic>> floorIdentifications = [];

  /// Every floor start that reached the wire, as `{id, device,
  /// identification}` — so a test can assert the transition carried an
  /// individual identification rather than a device credential alone.
  final List<Map<String, dynamic>> floorWorkOrderStarts = [];

  /// Every floor complete that reached the wire, the same shape.
  final List<Map<String, dynamic>> floorWorkOrderCompletions = [];

  /// `GET /api/quality/floor/products` and `.../defect-codes` (issue #207) —
  /// the shared device's own reads of the two catalogues it must choose from.
  /// Served off the [products]/[defectCodes] fixtures above, so a test seeds
  /// one list and both doors answer with it, the way one `products` table
  /// backs both addresses in the real API.
  int floorCataloguesStatus;

  /// Every floor catalogue read's device credential, in the order it reached
  /// the wire.
  final List<String> floorCatalogueReads = [];

  /// `POST /api/quality/floor/nonconformances` (issue #207) — recording one
  /// from a device. A refusal is scripted with [floorNonconformanceStatus],
  /// the shape every other write's `status` field keeps.
  int floorNonconformanceStatus;
  String floorNonconformanceMessage;

  /// Every floor recording that reached the wire, as `{device,
  /// identification, body}` — so a test can assert that the device credential
  /// and the individual identification each crossed the wire and exactly what
  /// was recorded.
  final List<Map<String, dynamic>> floorNonconformancePosts = [];

  int _nextEmployeeId = 900;
  int _nextAssignmentId = 500;
  int _nextJobRoleId = 950;
  int _nextSkillId = 970;
  int _nextEmployeeSkillId = 800;
  int _nextSiteId = 90;
  int _nextOrgUnitId = 990;
  int _nextProductId = 700;
  int _nextDefectCodeId = 750;
  int _nextNonconformanceId = 900;
  int _nextCustomerId = 600;
  int _nextComplaintId = 700;

  /// One complaint wherever it sits, by id — what every complaint write in this
  /// fake re-reads after changing it, since the real routes answer the whole
  /// record rather than a patch.
  Map<String, dynamic>? complaintById(String id) {
    for (final rows in complaints.values) {
      for (final row in rows) {
        if (row['id'] == id) return row;
      }
    }
    return null;
  }

  /// Replaces one complaint row wherever it sits, keeping the list's order.
  void _replaceComplaint(String id, Map<String, dynamic> updated) {
    complaints = {
      for (final entry in complaints.entries)
        entry.key: [
          for (final row in entry.value)
            if (row['id'] == id) updated else row,
        ],
    };
  }

  int _nextSupplierId = 500;
  int _nextSupplierNcrId = 800;

  /// One supplier NCR wherever it sits, by id — what every write in this fake
  /// re-reads after changing it, since the real routes answer the whole record
  /// rather than a patch.
  Map<String, dynamic>? supplierNcrById(String id) {
    for (final rows in supplierNcrs.values) {
      for (final row in rows) {
        if (row['id'] == id) return row;
      }
    }
    return null;
  }

  /// Replaces one supplier NCR row wherever it sits, keeping the list's order.
  void _replaceSupplierNcr(String id, Map<String, dynamic> updated) {
    supplierNcrs = {
      for (final entry in supplierNcrs.entries)
        entry.key: [
          for (final row in entry.value)
            if (row['id'] == id) updated else row,
        ],
    };
  }

  /// Replaces one Non-conformance row wherever it sits, keeping the list's
  /// order — what every write in this fake answers with, since the real
  /// routes answer the whole record rather than a patch.
  void _replaceNonconformance(String id, Map<String, dynamic> updated) {
    nonconformances = {
      for (final entry in nonconformances.entries)
        entry.key: [
          for (final row in entry.value)
            if (row['id'] == id) updated else row,
        ],
    };
  }

  /// Recomputes a row's cached disposition total and the status that follows
  /// from it, the way `settleDispositionStatus` (nonconformances.js) does for a
  /// real record (issue #206): the whole quantity having a Disposition closes
  /// it, part of it makes it `dispositioned`. A cancelled row is left alone,
  /// since a cancelled Non-conformance accepts nothing further.
  Map<String, dynamic> _settleDispositions(Map<String, dynamic> row) {
    if (row['status'] == 'cancelled') return row;
    final dispositions = (row['dispositions'] as List<dynamic>? ?? const []);
    var total = 0.0;
    for (final disposition in dispositions) {
      total += (disposition as Map<String, dynamic>)['quantity'] as num;
    }
    final affected = (row['quantityAffected'] as num).toDouble();
    final closed = total >= affected;
    return {
      ...row,
      'quantityDispositioned': total,
      'status': closed ? 'closed' : 'dispositioned',
      'closedAt': closed ? DateTime.now().toUtc().toIso8601String() : null,
    };
  }

  /// The production day a row is filed against — the row's own
  /// `productionDate` where it has one, and the detected date otherwise, which
  /// is the same fallback the real register's date range applies (ADR-0017's
  /// documented case of a Site with no shift calendar covering the moment).
  String _nonconformanceDayOf(Map<String, dynamic> row) {
    final productionDate = row['productionDate'] as String?;
    if (productionDate != null && productionDate.isNotEmpty) return productionDate;
    final detectedAt = row['detectedAt'] as String?;
    if (detectedAt == null || detectedAt.length < 10) return '';
    return detectedAt.substring(0, 10);
  }

  /// The Org Unit row for [orgUnitId], resolved off whatever tree rows this
  /// Fake Wire was given (any `parentId` key) — there is no Org Unit lookup
  /// endpoint for this client to call instead, the same reason
  /// `GrantedOrgUnit.where` (org_unit.dart) has no better source either.
  Map<String, dynamic>? _orgUnitRowFor(String orgUnitId) {
    for (final nodes in orgUnits.values) {
      for (final node in nodes) {
        if (node['id'] == orgUnitId) return node;
      }
    }
    return null;
  }

  /// The Org Unit name for [orgUnitId] — see [_orgUnitRowFor] for why it has
  /// to be resolved off the fixture rather than fetched.
  String _orgUnitNameFor(String orgUnitId) =>
      _orgUnitRowFor(orgUnitId)?['name'] as String? ?? 'Org Unit $orgUnitId';

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

  /// The meter row this Fake Wire holds naming [id], or null.
  Map<String, dynamic>? _meterRow(String id) {
    for (final list in meters.values) {
      for (final meter in list) {
        if (meter['id'] == id) return meter;
      }
    }
    return null;
  }

  /// Applies a reading's or rollover's own changes to every meter row this
  /// Fake Wire holds naming [id], across every Site's list. Returns the updated
  /// row, or null when no list holds it.
  Map<String, dynamic>? _applyMeterChanges(String id, Map<String, dynamic> changes) {
    Map<String, dynamic>? updated;
    meters = {
      for (final entry in meters.entries)
        entry.key: [
          for (final row in entry.value)
            if (row['id'] == id) (updated = {...row, ...changes}) else row,
        ],
    };
    return updated;
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

  /// Completes one stored Action's open phase and opens what follows, in place
  /// — so a later read of the same Action sees the state the screen does.
  Map<String, dynamic>? _completeStoredPhase(String id, String phase, Map<String, dynamic> body) {
    Map<String, dynamic>? stored = actionDetails[id];
    for (final rows in actions.values) {
      for (final row in rows) {
        if (row['id'] == id) stored = row;
      }
    }
    if (stored == null) return null;

    final phases = [
      for (final row in (stored['phases'] as List<dynamic>? ?? const []))
        Map<String, dynamic>.from(row as Map<String, dynamic>),
    ];
    final cycle = (stored['openPhase'] as Map<String, dynamic>?)?['cycle'] as int? ?? 1;
    for (final row in phases) {
      if (row['cycle'] == cycle && row['phase'] == phase) {
        row['completedAt'] = '2026-09-15T03:00:00.000Z';
        row['note'] = body['note'];
        row['outcome'] = body['outcome'];
      }
    }

    Map<String, dynamic>? next;
    switch (phase) {
      case 'plan':
        next = phaseJson(cycle, 'do');
      case 'do':
        next = phaseJson(cycle, 'check');
      case 'check':
        next = body['outcome'] == 'effective'
            ? phaseJson(cycle, 'act')
            : phaseJson(cycle + 1, 'plan');
      default:
        next = null;
    }
    if (next != null) {
      phases.add(next);
      stored['openPhase'] = next;
    } else {
      stored['openPhase'] = null;
    }
    stored['phases'] = phases;
    stored['status'] = phase == 'act' ? 'done' : 'in_progress';
    stored['actionType'] = stored['actionType'];
    return stored;
  }

  http.Client get client => MockClient((request) async {
        final path = request.url.path;
        requests.add('${request.method} $path');
        if (path == '/api/maintenance/floor/work-orders') {
          floorReads.add(request.headers['x-floor-device'] ?? '');
          if (floorGate != null) await floorGate!.future;
          if (floorWorkOrdersStatus != 200) {
            return http.Response(
              jsonEncode({'message': 'The floor work is unavailable.'}),
              floorWorkOrdersStatus,
            );
          }
          return http.Response(
            jsonEncode({'floor': floor, 'workOrders': floorWorkOrders}),
            200,
          );
        }
        if (request.method == 'POST' && path == '/api/maintenance/floor/identify') {
          final sent = jsonDecode(request.body) as Map<String, dynamic>;
          floorIdentifications.add({
            'employeeNo': sent['employeeNo'],
            'pin': sent['pin'],
            'device': request.headers['x-floor-device'],
          });
          if (floorIdentifyStatus != 200) {
            return http.Response(jsonEncode({'message': floorIdentifyMessage}), floorIdentifyStatus);
          }
          return http.Response(
            jsonEncode({
              'identification': floorIdentificationToken,
              'expiresAt': DateTime.now().add(const Duration(minutes: 2)).toUtc().toIso8601String(),
              'employee': floorEmployee,
            }),
            200,
          );
        }
        // The Supplier list and the supplier NCRs (issue #215). Mirrors
        // supplier-routes.js and supplier-ncr-routes.js: the list applies
        // `includeInactive` and `search`, the register applies the Supplier, the
        // status and the Org Unit with everything beneath it, and every write
        // answers the whole record the way the real routes do.
        if (request.method == 'POST' && path == '/api/quality/suppliers') {
          final sent = jsonDecode(request.body) as Map<String, dynamic>;
          supplierPosts.add(sent);
          if (createSupplierStatus != 201) {
            return http.Response(
              jsonEncode({'message': createSupplierMessage}),
              createSupplierStatus,
            );
          }
          final id = (_nextSupplierId++).toString();
          final created = supplierJson(
            id,
            sent['code'] as String,
            sent['name'] as String,
            contactEmail: sent['contactEmail'] as String?,
          );
          suppliers = [...suppliers, created];
          return http.Response(jsonEncode({'supplier': created}), 201);
        }
        if (request.method == 'PATCH' && path.startsWith('/api/quality/suppliers/')) {
          final id = path.substring('/api/quality/suppliers/'.length);
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          supplierPatches.add((id, body));
          if (updateSupplierStatus != 200) {
            return http.Response(
              jsonEncode({'message': updateSupplierMessage}),
              updateSupplierStatus,
            );
          }
          Map<String, dynamic>? updated;
          suppliers = [
            for (final row in suppliers)
              if (row['id'] == id) (updated = {...row, ...body}) else row,
          ];
          if (updated == null) {
            return http.Response(jsonEncode({'message': 'Supplier not found'}), 404);
          }
          return http.Response(jsonEncode({'supplier': updated}), 200);
        }
        if (path == '/api/quality/suppliers') {
          supplierListRequests.add(request.url.queryParameters);
          if (suppliersStatus != 200) {
            return http.Response(
              jsonEncode({'message': 'The Supplier list is unavailable.'}),
              suppliersStatus,
            );
          }
          final query = request.url.queryParameters;
          final includeInactive = query['includeInactive'] == 'true';
          final term = (query['search'] ?? '').trim().toLowerCase();
          final sent = [
            for (final row in suppliers)
              if (includeInactive || row['isActive'] != false)
                if (term.isEmpty ||
                    (row['code'] as String).toLowerCase().contains(term) ||
                    (row['name'] as String).toLowerCase().contains(term))
                  row,
          ];
          return http.Response(jsonEncode({'suppliers': sent}), 200);
        }
        if (path.startsWith('/api/quality/sites/') && path.endsWith('/supplier-ncrs')) {
          final siteId = path.split('/')[4];
          if (request.method == 'POST') {
            final sent = jsonDecode(request.body) as Map<String, dynamic>;
            supplierNcrPosts.add(sent);
            if (createSupplierNcrStatus != 201) {
              return http.Response(
                jsonEncode({'message': createSupplierNcrMessage}),
                createSupplierNcrStatus,
              );
            }
            final supplierId = sent['supplierId'] as String;
            final orgUnitId = sent['orgUnitId'] as String;
            Map<String, dynamic>? supplier;
            for (final row in suppliers) {
              if (row['id'] == supplierId) supplier = row;
            }
            if (supplier == null) {
              return http.Response(jsonEncode({'message': 'Supplier not found'}), 404);
            }
            final productId = sent['productId'] as String?;
            Map<String, dynamic>? product;
            for (final row in products) {
              if (row['id'] == productId) product = row;
            }
            final defectCodeId = sent['defectCodeId'] as String?;
            Map<String, dynamic>? defectCode;
            for (final code in defectCodes) {
              if (code['id'] == defectCodeId) defectCode = code;
            }
            final quantity = sent['quantity'] as num?;
            final responseDueDate = sent['responseDueDate'] as String?;
            final id = (_nextSupplierNcrId++).toString();
            final created = supplierNcrJson(
              id,
              'SN-2026-${id.padLeft(5, '0')}',
              supplierId: supplierId,
              supplierCode: supplier['code'] as String? ?? 'SUP-?',
              supplierName: supplier['name'] as String? ?? 'Supplier',
              productId: productId,
              productCode: product?['code'] as String?,
              productName: product?['name'] as String?,
              defectCodeId: defectCodeId,
              defectCodeCode: defectCode?['code'] as String?,
              defectCodeName: defectCode?['name'] as String?,
              orgUnitId: orgUnitId,
              orgUnitName: _orgUnitNameFor(orgUnitId),
              siteId: siteId,
              incomingLotRef: sent['incomingLotRef'] as String?,
              purchaseRef: sent['purchaseRef'] as String?,
              quantityAffected: quantity ?? 0,
              uomCode: sent['uomCode'] as String? ??
                  product?['uomCode'] as String? ??
                  'EA',
              disposition: sent['disposition'] as String? ?? 'return_to_supplier',
              responseDueDate: responseDueDate,
              responseDueAt: responseDueDate == null
                  ? null
                  : '${responseDueDate}T23:59:59.999999+07:00',
              description: sent['description'] as String?,
            );
            supplierNcrs = {
              ...supplierNcrs,
              siteId: [created, ...(supplierNcrs[siteId] ?? const [])],
            };
            return http.Response(jsonEncode({'supplierNcr': created}), 201);
          }
          supplierNcrListRequests.add(request.url.queryParameters);
          if (supplierNcrsStatus != 200) {
            return http.Response(
              jsonEncode({'message': 'The supplier NCR register is unavailable.'}),
              supplierNcrsStatus,
            );
          }
          final query = request.url.queryParameters;
          final orgUnitId = query['orgUnitId'];
          final scope = orgUnitId == null ? null : nonconformanceOrgUnitScope(orgUnitId);
          final status = query['status'];
          final supplierId = query['supplierId'];
          final sent = [
            for (final row in supplierNcrs[siteId] ?? const <Map<String, dynamic>>[])
              if (scope == null || scope.contains(row['orgUnitId']))
                if (status == null || row['status'] == status)
                  if (supplierId == null || row['supplierId'] == supplierId) row,
          ];
          return http.Response(
            jsonEncode({'supplierNcrs': sent, 'truncated': supplierNcrsTruncated}),
            200,
          );
        }
        if (path.startsWith('/api/quality/supplier-ncrs/')) {
          final remainder = path.substring('/api/quality/supplier-ncrs/'.length);

          if (remainder.endsWith('/disposition') && request.method == 'POST') {
            final id = remainder.substring(0, remainder.length - '/disposition'.length);
            final sent = jsonDecode(request.body) as Map<String, dynamic>;
            supplierNcrDispositions.add((id, sent));
            final row = supplierNcrById(id);
            if (row == null) {
              return http.Response(jsonEncode({'message': 'Supplier NCR not found'}), 404);
            }
            if (supplierNcrDispositionStatus != 200) {
              return http.Response(
                jsonEncode({'message': supplierNcrDispositionMessage}),
                supplierNcrDispositionStatus,
              );
            }
            final disposition = sent['disposition'] as String?;
            const allowed = [
              'return_to_supplier',
              'scrap',
              'rework_at_cost',
              'sort',
              'use_as_is',
            ];
            if (disposition == null || !allowed.contains(disposition)) {
              return http.Response(
                jsonEncode({
                  'message': 'disposition must be one of: ${allowed.join(', ')}',
                }),
                400,
              );
            }
            final cost = sent['costRecovered'] as num?;
            if (cost != null && cost < 0) {
              return http.Response(
                jsonEncode({'message': 'costRecovered must be at least 0'}),
                400,
              );
            }
            final updated = {
              ...row,
              'disposition': disposition,
              'costRecovered': cost,
              'currency': sent['currency'] as String? ?? row['currency'],
            };
            _replaceSupplierNcr(id, updated);
            return http.Response(jsonEncode({'supplierNcr': updated}), 200);
          }

          if (remainder.endsWith('/close') && request.method == 'POST') {
            final id = remainder.substring(0, remainder.length - '/close'.length);
            supplierNcrCloses.add(id);
            final row = supplierNcrById(id);
            if (row == null) {
              return http.Response(jsonEncode({'message': 'Supplier NCR not found'}), 404);
            }
            if (supplierNcrCloseStatus != 200) {
              return http.Response(
                jsonEncode({'message': supplierNcrCloseMessage}),
                supplierNcrCloseStatus,
              );
            }
            if (row['status'] == 'closed' || row['status'] == 'rejected') {
              return http.Response(
                jsonEncode({
                  'message': 'that supplier NCR is ${row['status']} and cannot be changed',
                }),
                409,
              );
            }
            final closed = {
              ...row,
              'status': 'closed',
              'closedAt': DateTime.now().toUtc().toIso8601String(),
              // A closed NCR is never marked late — the real read's own rule
              // (supplier-ncrs.js).
              'isOverdue': false,
            };
            _replaceSupplierNcr(id, closed);
            return http.Response(jsonEncode({'supplierNcr': closed}), 200);
          }

          if (remainder.endsWith('/nonconformance') && request.method == 'POST') {
            final id = remainder.substring(0, remainder.length - '/nonconformance'.length);
            final sent = jsonDecode(request.body) as Map<String, dynamic>;
            supplierNcrNonconformancePosts.add((id, sent));
            final row = supplierNcrById(id);
            if (row == null) {
              return http.Response(jsonEncode({'message': 'Supplier NCR not found'}), 404);
            }
            if (supplierNcrNonconformanceStatus != 201) {
              return http.Response(
                jsonEncode({'message': supplierNcrNonconformanceMessage}),
                supplierNcrNonconformanceStatus,
              );
            }
            final productId = (sent['productId'] as String?) ?? row['productId'] as String?;
            if (productId == null) {
              return http.Response(
                jsonEncode({
                  'message': 'productId is required: this supplier NCR carries no Product to '
                      'record the Non-conformance about',
                }),
                400,
              );
            }
            final defectCodeId =
                (sent['defectCodeId'] as String?) ?? row['defectCodeId'] as String?;
            if (defectCodeId == null) {
              return http.Response(
                jsonEncode({
                  'message': 'defectCodeId is required: this supplier NCR carries no Defect '
                      'code to record the Non-conformance with',
                }),
                400,
              );
            }
            Map<String, dynamic>? product;
            for (final candidate in products) {
              if (candidate['id'] == productId) product = candidate;
            }
            final siteId = row['siteId'] as String;
            final ncId = (_nextNonconformanceId++).toString();
            final recorded = nonconformanceJson(
              ncId,
              'NC-HCM-2026-${ncId.padLeft(5, '0')}',
              detectionPoint: 'incoming',
              severity: row['severity'] as String? ?? 'major',
              quantityAffected: (sent['quantity'] as num?) ??
                  (row['quantityAffected'] as num?) ??
                  1,
              lotRef: row['incomingLotRef'] as String?,
              description: sent['description'] as String? ?? row['description'] as String?,
              immediateContainment: sent['immediateContainment'] as String?,
              orgUnitId: row['orgUnitId'] as String,
              orgUnitName: row['orgUnitName'] as String,
              siteId: siteId,
              productId: productId,
              productCode: product?['code'] as String? ?? 'PRD-?',
              productName: product?['name'] as String? ?? 'Product',
              defectCodeId: defectCodeId,
              defectCodeCode: row['defectCodeCode'] as String? ?? 'CODE-?',
              defectCodeName: row['defectCodeName'] as String? ?? 'Defect code',
            );
            nonconformances = {
              ...nonconformances,
              siteId: [recorded, ...(nonconformances[siteId] ?? const [])],
            };
            final linked = {
              ...row,
              'productId': productId,
              'productCode': product?['code'] as String? ?? row['productCode'],
              'productName': product?['name'] as String? ?? row['productName'],
              'defectCodeId': defectCodeId,
              'nonconformance': supplierNcrNonconformanceJson(
                ncId,
                recorded['issueNo'] as String,
                detectionPoint: 'incoming',
                severity: recorded['severity'] as String,
                quantityAffected: recorded['quantityAffected'] as num?,
              ),
            };
            _replaceSupplierNcr(id, linked);
            return http.Response(
              jsonEncode({'nonconformance': recorded, 'supplierNcr': linked}),
              201,
            );
          }

          if (remainder.endsWith('/link') && request.method == 'POST') {
            final id = remainder.substring(0, remainder.length - '/link'.length);
            final sent = jsonDecode(request.body) as Map<String, dynamic>;
            supplierNcrLinks.add((id, sent));
            final row = supplierNcrById(id);
            if (row == null) {
              return http.Response(jsonEncode({'message': 'Supplier NCR not found'}), 404);
            }
            if (linkSupplierNcrStatus != 200) {
              return http.Response(
                jsonEncode({'message': linkSupplierNcrMessage}),
                linkSupplierNcrStatus,
              );
            }
            if (row['nonconformance'] != null) {
              return http.Response(
                jsonEncode({'message': 'this supplier NCR already names a Non-conformance'}),
                409,
              );
            }
            final nonconformanceId = sent['nonconformanceId'] as String?;
            Map<String, dynamic>? candidate;
            for (final rows in nonconformances.values) {
              for (final nc in rows) {
                if (nc['id'] == nonconformanceId) candidate = nc;
              }
            }
            if (candidate == null) {
              return http.Response(
                jsonEncode({'message': 'Non-conformance not found'}),
                404,
              );
            }
            final linked = {
              ...row,
              'nonconformance': supplierNcrNonconformanceJson(
                nonconformanceId!,
                candidate['issueNo'] as String,
                detectionPoint: candidate['detectionPoint'] as String? ?? 'incoming',
                severity: candidate['severity'] as String? ?? 'major',
                quantityAffected: candidate['quantityAffected'] as num?,
              ),
            };
            _replaceSupplierNcr(id, linked);
            return http.Response(jsonEncode({'supplierNcr': linked}), 200);
          }

          if (request.method == 'GET') {
            supplierNcrReads.add(path);
            final row = supplierNcrById(remainder);
            if (row == null) {
              return http.Response(jsonEncode({'message': 'Supplier NCR not found'}), 404);
            }
            return http.Response(jsonEncode({'supplierNcr': row}), 200);
          }
        }
        // The Customer list and the customer complaints (issue #214). Mirrors
        // customer-routes.js and customer-complaint-routes.js: the list applies
        // `includeInactive` and `search`, the register applies the status and
        // the Org Unit with everything beneath it, and every complaint write
        // answers the whole record the way the real routes do.
        if (request.method == 'POST' && path == '/api/quality/customers') {
          final sent = jsonDecode(request.body) as Map<String, dynamic>;
          customerPosts.add(sent);
          if (createCustomerStatus != 201) {
            return http.Response(
              jsonEncode({'message': createCustomerMessage}),
              createCustomerStatus,
            );
          }
          final id = (_nextCustomerId++).toString();
          final created = customerJson(
            id,
            sent['code'] as String,
            sent['name'] as String,
            contactEmail: sent['contactEmail'] as String?,
          );
          customers = [...customers, created];
          return http.Response(jsonEncode({'customer': created}), 201);
        }
        if (request.method == 'PATCH' && path.startsWith('/api/quality/customers/')) {
          final id = path.substring('/api/quality/customers/'.length);
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          customerPatches.add((id, body));
          if (updateCustomerStatus != 200) {
            return http.Response(
              jsonEncode({'message': updateCustomerMessage}),
              updateCustomerStatus,
            );
          }
          Map<String, dynamic>? updated;
          customers = [
            for (final row in customers)
              if (row['id'] == id) (updated = {...row, ...body}) else row,
          ];
          if (updated == null) {
            return http.Response(jsonEncode({'message': 'Customer not found'}), 404);
          }
          return http.Response(jsonEncode({'customer': updated}), 200);
        }
        if (path == '/api/quality/customers') {
          customerListRequests.add(request.url.queryParameters);
          if (customersStatus != 200) {
            return http.Response(
              jsonEncode({'message': 'The Customer list is unavailable.'}),
              customersStatus,
            );
          }
          final query = request.url.queryParameters;
          final includeInactive = query['includeInactive'] == 'true';
          final term = (query['search'] ?? '').trim().toLowerCase();
          final sent = [
            for (final row in customers)
              if (includeInactive || row['isActive'] != false)
                if (term.isEmpty ||
                    (row['code'] as String).toLowerCase().contains(term) ||
                    (row['name'] as String).toLowerCase().contains(term))
                  row,
          ];
          return http.Response(jsonEncode({'customers': sent}), 200);
        }
        if (path.startsWith('/api/quality/sites/') && path.endsWith('/complaints')) {
          final siteId = path.split('/')[4];
          if (request.method == 'POST') {
            final sent = jsonDecode(request.body) as Map<String, dynamic>;
            complaintPosts.add(sent);
            if (createComplaintStatus != 201) {
              return http.Response(
                jsonEncode({'message': createComplaintMessage}),
                createComplaintStatus,
              );
            }
            final customerId = sent['customerId'] as String;
            final productId = sent['productId'] as String;
            final orgUnitId = sent['orgUnitId'] as String;
            Map<String, dynamic>? customer;
            for (final row in customers) {
              if (row['id'] == customerId) customer = row;
            }
            Map<String, dynamic>? product;
            for (final row in products) {
              if (row['id'] == productId) product = row;
            }
            final defectCodeId = sent['defectCodeId'] as String?;
            Map<String, dynamic>? defectCode;
            for (final code in defectCodes) {
              if (code['id'] == defectCodeId) defectCode = code;
            }
            final quantity = sent['quantity'] as num?;
            final responseDueDate = sent['responseDueDate'] as String?;
            final id = (_nextComplaintId++).toString();
            final created = customerComplaintJson(
              id,
              'CC-2026-${id.padLeft(5, '0')}',
              customerId: customerId,
              customerCode: customer?['code'] as String? ?? 'CUST-?',
              customerName: customer?['name'] as String? ?? 'Customer',
              productId: productId,
              productCode: product?['code'] as String? ?? 'PRD-?',
              productName: product?['name'] as String? ?? 'Product',
              defectCodeId: defectCodeId,
              defectCodeCode: defectCode?['code'] as String?,
              defectCodeName: defectCode?['name'] as String?,
              orgUnitId: orgUnitId,
              orgUnitName: _orgUnitNameFor(orgUnitId),
              siteId: siteId,
              complaintType: sent['complaintType'] as String? ?? 'quality',
              severity: sent['severity'] as String? ?? 'major',
              quantityAffected: quantity,
              uomCode: quantity == null ? null : (product?['uomCode'] as String? ?? 'EA'),
              customerRef: sent['customerRef'] as String?,
              lotRef: sent['lotRef'] as String?,
              description: sent['description'] as String? ?? '',
              responseDueDate: responseDueDate,
              responseDueAt:
                  responseDueDate == null ? null : '${responseDueDate}T23:59:59.999999+07:00',
              isWarranty: sent['isWarranty'] == true,
            );
            complaints = {
              ...complaints,
              siteId: [created, ...(complaints[siteId] ?? const [])],
            };
            return http.Response(jsonEncode({'complaint': created}), 201);
          }
          complaintListRequests.add(request.url.queryParameters);
          if (complaintsStatus != 200) {
            return http.Response(
              jsonEncode({'message': 'The complaint register is unavailable.'}),
              complaintsStatus,
            );
          }
          final query = request.url.queryParameters;
          final orgUnitId = query['orgUnitId'];
          final scope = orgUnitId == null ? null : nonconformanceOrgUnitScope(orgUnitId);
          final status = query['status'];
          final sent = [
            for (final row in complaints[siteId] ?? const <Map<String, dynamic>>[])
              if (scope == null || scope.contains(row['orgUnitId']))
                if (status == null || row['status'] == status) row,
          ];
          return http.Response(
            jsonEncode({'complaints': sent, 'truncated': complaintsTruncated}),
            200,
          );
        }
        if (path.startsWith('/api/quality/complaints/')) {
          final remainder = path.substring('/api/quality/complaints/'.length);

          if (remainder.endsWith('/respond') && request.method == 'POST') {
            final id = remainder.substring(0, remainder.length - '/respond'.length);
            final sent = jsonDecode(request.body) as Map<String, dynamic>;
            complaintResponds.add((id, sent));
            final row = complaintById(id);
            if (row == null) {
              return http.Response(jsonEncode({'message': 'Customer complaint not found'}), 404);
            }
            if (respondToComplaintStatus != 200) {
              return http.Response(
                jsonEncode({'message': respondToComplaintMessage}),
                respondToComplaintStatus,
              );
            }
            final note = (sent['responseNote'] as String?)?.trim() ?? '';
            if (note.isEmpty) {
              return http.Response(
                jsonEncode({'message': 'responseNote is required to close a complaint'}),
                400,
              );
            }
            final closed = {
              ...row,
              'status': 'closed',
              'closedAt': DateTime.now().toUtc().toIso8601String(),
              'firstResponseAt': row['firstResponseAt'] ??
                  DateTime.now().toUtc().toIso8601String(),
              'responseNote': note,
              // A complaint that is finished with is never marked late — the
              // real read's own rule (customer-complaints.js).
              'isOverdue': false,
            };
            _replaceComplaint(id, closed);
            return http.Response(jsonEncode({'complaint': closed}), 200);
          }

          if (remainder.endsWith('/nonconformance') && request.method == 'POST') {
            final id = remainder.substring(0, remainder.length - '/nonconformance'.length);
            final sent = jsonDecode(request.body) as Map<String, dynamic>;
            complaintNonconformancePosts.add((id, sent));
            final row = complaintById(id);
            if (row == null) {
              return http.Response(jsonEncode({'message': 'Customer complaint not found'}), 404);
            }
            if (complaintNonconformanceStatus != 201) {
              return http.Response(
                jsonEncode({'message': complaintNonconformanceMessage}),
                complaintNonconformanceStatus,
              );
            }
            final siteId = row['siteId'] as String;
            final ncId = (_nextNonconformanceId++).toString();
            final recorded = nonconformanceJson(
              ncId,
              'NC-HCM-2026-${ncId.padLeft(5, '0')}',
              detectionPoint: 'customer',
              severity: row['severity'] as String? ?? 'major',
              quantityAffected: (sent['quantity'] as num?) ??
                  (row['quantityAffected'] as num?) ??
                  1,
              lotRef: row['lotRef'] as String?,
              description: sent['description'] as String? ?? row['description'] as String?,
              immediateContainment: sent['immediateContainment'] as String?,
              orgUnitId: row['orgUnitId'] as String,
              orgUnitName: row['orgUnitName'] as String,
              siteId: siteId,
              productId: row['productId'] as String,
              productCode: row['productCode'] as String,
              productName: row['productName'] as String,
              defectCodeId: (sent['defectCodeId'] as String?) ?? row['defectCodeId'] as String,
              defectCodeCode: row['defectCodeCode'] as String? ?? 'CODE-?',
              defectCodeName: row['defectCodeName'] as String? ?? 'Defect code',
            );
            nonconformances = {
              ...nonconformances,
              siteId: [recorded, ...(nonconformances[siteId] ?? const [])],
            };
            final linked = {
              ...row,
              'nonconformance': complaintNonconformanceJson(
                ncId,
                recorded['issueNo'] as String,
                detectionPoint: 'customer',
                severity: recorded['severity'] as String,
                quantityAffected: recorded['quantityAffected'] as num,
              ),
            };
            _replaceComplaint(id, linked);
            return http.Response(
              jsonEncode({'nonconformance': recorded, 'complaint': linked}),
              201,
            );
          }

          if (remainder.endsWith('/link') && request.method == 'POST') {
            final id = remainder.substring(0, remainder.length - '/link'.length);
            final sent = jsonDecode(request.body) as Map<String, dynamic>;
            complaintLinks.add((id, sent));
            final row = complaintById(id);
            if (row == null) {
              return http.Response(jsonEncode({'message': 'Customer complaint not found'}), 404);
            }
            if (linkComplaintStatus != 200) {
              return http.Response(
                jsonEncode({'message': linkComplaintMessage}),
                linkComplaintStatus,
              );
            }
            final candidateId = sent['nonconformanceId'] as String;
            final candidate = nonconformanceById(candidateId);
            if (candidate == null) {
              return http.Response(jsonEncode({'message': 'Non-conformance not found'}), 404);
            }
            final linked = {
              ...row,
              'nonconformance': complaintNonconformanceJson(
                candidateId,
                candidate['issueNo'] as String,
                status: candidate['status'] as String,
                detectionPoint: candidate['detectionPoint'] as String,
                severity: candidate['severity'] as String,
                quantityAffected: candidate['quantityAffected'] as num,
              ),
            };
            _replaceComplaint(id, linked);
            return http.Response(jsonEncode({'complaint': linked}), 200);
          }

          if (remainder.isNotEmpty && !remainder.contains('/')) {
            complaintReads.add(path);
            final row = complaintById(remainder);
            if (row == null) {
              return http.Response(jsonEncode({'message': 'Customer complaint not found'}), 404);
            }
            return http.Response(jsonEncode({'complaint': row}), 200);
          }
        }
        // The Quality Module's floor door (issue #207): the two catalogues a
        // device must choose from, and the recording it makes. Mirrors
        // quality/floor-routes.js — the reads answer the same catalogues the
        // Account-facing addresses above answer (active rows only, which is
        // all the floor read offers), and the write answers the row the API
        // would have written, with the identified Employee as its detected-by
        // and no Account at all.
        if (request.method == 'GET' &&
            (path == '/api/quality/floor/products' ||
                path == '/api/quality/floor/defect-codes')) {
          floorCatalogueReads.add(request.headers['x-floor-device'] ?? '');
          if (floorCataloguesStatus != 200) {
            return http.Response(
              jsonEncode({'message': 'The floor catalogue is unavailable.'}),
              floorCataloguesStatus,
            );
          }
          if (path.endsWith('/defect-codes')) {
            return http.Response(
              jsonEncode({
                'defectCodes': [
                  for (final code in defectCodes)
                    if (code['isActive'] != false) code,
                ],
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'products': [
                for (final product in products)
                  if (product['isActive'] != false) product,
              ],
            }),
            200,
          );
        }
        if (request.method == 'POST' && path == '/api/quality/floor/nonconformances') {
          final sent = jsonDecode(request.body) as Map<String, dynamic>;
          floorNonconformancePosts.add({
            'device': request.headers['x-floor-device'],
            'identification': request.headers['x-technician-identification'],
            'body': sent,
          });
          if (floorNonconformanceStatus != 201) {
            return http.Response(
              jsonEncode({'message': floorNonconformanceMessage}),
              floorNonconformanceStatus,
            );
          }
          final productId = sent['productId'] as String;
          final defectCodeId = sent['defectCodeId'] as String;
          final orgUnitId = sent['orgUnitId'] as String;
          Map<String, dynamic>? product;
          for (final row in products) {
            if (row['id'] == productId) product = row;
          }
          Map<String, dynamic>? defectCode;
          for (final code in defectCodes) {
            if (code['id'] == defectCodeId) defectCode = code;
          }
          final containment = sent['immediateContainment'] as String?;
          final id = (_nextNonconformanceId++).toString();
          final created = {
            ...nonconformanceJson(
              id,
              'NC-HCM-2026-${id.padLeft(5, '0')}',
              status: containment == null ? 'open' : 'contained',
              detectionPoint: sent['detectionPoint'] as String,
              severity:
                  sent['severity'] as String? ?? (defectCode?['defaultSeverity'] as String? ?? 'minor'),
              quantityAffected: sent['quantity'] as num,
              uomCode: product?['uomCode'] as String? ?? 'EA',
              lotRef: sent['lotRef'] as String?,
              // The floor door names an Employee and no Account — the two are
              // never both filled (nonconformances.js's own note).
              recordedByAccountId: null,
              description: sent['description'] as String?,
              immediateContainment: containment,
              orgUnitId: orgUnitId,
              orgUnitName: _orgUnitNameFor(orgUnitId),
              productId: productId,
              productCode: product?['code'] as String? ?? 'PRD-?',
              productName: product?['name'] as String? ?? 'Product',
              defectCodeId: defectCodeId,
              defectCodeCode: defectCode?['code'] as String? ?? 'CODE-?',
              defectCodeName: defectCode?['name'] as String? ?? 'Defect code',
              defectCodeDefaultSeverity:
                  defectCode?['defaultSeverity'] as String? ?? 'minor',
            ),
            'detectedBy': floorEmployee['id'],
          };
          return http.Response(jsonEncode({'nonconformance': created}), 201);
        }
        // The Quality Module's two catalogues (issue #203). Each pair of
        // handlers mirrors its own route file: the write answers the row the
        // real one answers with, and the read applies `includeInactive` and
        // `search` the way products.js's listProducts does — after every other
        // filter, so a test can prove a search the way the registration test
        // proves a query.
        if (request.method == 'POST' && path == '/api/quality/products') {
          final sent = jsonDecode(request.body) as Map<String, dynamic>;
          productPosts.add(sent);
          if (createProductStatus != 201) {
            return http.Response(jsonEncode({'message': createProductMessage}), createProductStatus);
          }
          final id = (_nextProductId++).toString();
          final uomCode = sent['uomCode'] as String;
          String? uomName;
          for (final row in unitsOfMeasure) {
            if (row['code'] == uomCode) uomName = row['name'] as String?;
          }
          final created = productJson(
            id,
            sent['code'] as String,
            sent['name'] as String,
            uomCode: uomCode,
            uomName: uomName ?? uomCode,
          );
          products = [...products, created];
          return http.Response(jsonEncode({'product': created}), 201);
        }
        if (request.method == 'PATCH' && path.startsWith('/api/quality/products/')) {
          final id = path.substring('/api/quality/products/'.length);
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          productPatches.add((id, body));
          if (updateProductStatus != 200) {
            return http.Response(jsonEncode({'message': updateProductMessage}), updateProductStatus);
          }
          Map<String, dynamic>? updated;
          products = [
            for (final product in products)
              if (product['id'] == id) (updated = {...product, ...body}) else product,
          ];
          if (updated == null) {
            return http.Response(jsonEncode({'message': 'Product not found'}), 404);
          }
          return http.Response(jsonEncode({'product': updated}), 200);
        }
        if (path == '/api/quality/products') {
          productListRequests.add(request.url.queryParameters);
          if (productsStatus != 200) {
            return http.Response(
              jsonEncode({'message': 'The Product catalogue is unavailable.'}),
              productsStatus,
            );
          }
          final includeInactive = request.url.queryParameters['includeInactive'] == 'true';
          final search = request.url.queryParameters['search'];
          var sent = includeInactive
              ? products
              : [for (final product in products) if (product['isActive'] != false) product];
          if (search != null && search.isNotEmpty) {
            final needle = search.toLowerCase();
            sent = [
              for (final product in sent)
                if ((product['code'] as String).toLowerCase().contains(needle) ||
                    (product['name'] as String).toLowerCase().contains(needle))
                  product,
            ];
          }
          return http.Response(jsonEncode({'products': sent}), 200);
        }
        if (request.method == 'POST' && path == '/api/quality/defect-codes') {
          final sent = jsonDecode(request.body) as Map<String, dynamic>;
          defectCodePosts.add(sent);
          if (createDefectCodeStatus != 201) {
            return http.Response(
              jsonEncode({'message': createDefectCodeMessage}),
              createDefectCodeStatus,
            );
          }
          final id = (_nextDefectCodeId++).toString();
          final created = defectCodeJson(
            id,
            sent['code'] as String,
            sent['name'] as String,
            parentId: sent['parentId']?.toString(),
            category: sent['category'] as String? ?? 'product',
            defaultSeverity: sent['defaultSeverity'] as String? ?? 'minor',
          );
          defectCodes = [...defectCodes, created];
          return http.Response(jsonEncode({'defectCode': created}), 201);
        }
        if (request.method == 'PATCH' && path.startsWith('/api/quality/defect-codes/')) {
          final id = path.substring('/api/quality/defect-codes/'.length);
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          defectCodePatches.add((id, body));
          if (updateDefectCodeStatus != 200) {
            return http.Response(
              jsonEncode({'message': updateDefectCodeMessage}),
              updateDefectCodeStatus,
            );
          }
          Map<String, dynamic>? updated;
          defectCodes = [
            for (final code in defectCodes)
              if (code['id'] == id) (updated = {...code, ...body}) else code,
          ];
          if (updated == null) {
            return http.Response(jsonEncode({'message': 'Defect code not found'}), 404);
          }
          return http.Response(jsonEncode({'defectCode': updated}), 200);
        }
        if (path == '/api/quality/defect-codes') {
          defectCodeListRequests.add(request.url.queryParameters);
          if (defectCodesStatus != 200) {
            return http.Response(
              jsonEncode({'message': 'The Defect code catalogue is unavailable.'}),
              defectCodesStatus,
            );
          }
          final includeInactive = request.url.queryParameters['includeInactive'] == 'true';
          final sent = includeInactive
              ? defectCodes
              : [for (final code in defectCodes) if (code['isActive'] != false) code];
          return http.Response(jsonEncode({'defectCodes': sent}), 200);
        }
        // The Non-conformance register, and one record with its own quantity
        // history (issue #205). Mirrors nonconformance-routes.js: the list
        // applies the filters the address takes — Org Unit and everything
        // beneath it, status, Defect code, Product, severity, a production-day
        // range — the record answers the row the API would have written, and
        // every write answers the whole record the way the real routes do.
        if (path.startsWith('/api/quality/sites/') && path.endsWith('/nonconformances')) {
          final siteId = path.split('/')[4];
          if (request.method == 'POST') {
            final sent = jsonDecode(request.body) as Map<String, dynamic>;
            nonconformancePosts.add(sent);
            if (createNonconformanceStatus != 201) {
              return http.Response(
                jsonEncode({'message': createNonconformanceMessage}),
                createNonconformanceStatus,
              );
            }
            final productId = sent['productId'] as String;
            final defectCodeId = sent['defectCodeId'] as String;
            final orgUnitId = sent['orgUnitId'] as String;
            Map<String, dynamic>? product;
            for (final row in products) {
              if (row['id'] == productId) product = row;
            }
            Map<String, dynamic>? defectCode;
            for (final code in defectCodes) {
              if (code['id'] == defectCodeId) defectCode = code;
            }
            final severity =
                sent['severity'] as String? ?? (defectCode?['defaultSeverity'] as String? ?? 'minor');
            final containment = sent['immediateContainment'] as String?;
            final id = (_nextNonconformanceId++).toString();
            final created = nonconformanceJson(
              id,
              'NC-HCM-2026-${id.padLeft(5, '0')}',
              status: containment == null ? 'open' : 'contained',
              detectionPoint: sent['detectionPoint'] as String,
              severity: severity,
              quantityAffected: sent['quantity'] as num,
              uomCode: product?['uomCode'] as String? ?? 'EA',
              lotRef: sent['lotRef'] as String?,
              recordedByAccountId: '1',
              description: sent['description'] as String?,
              immediateContainment: containment,
              orgUnitId: orgUnitId,
              orgUnitName: _orgUnitNameFor(orgUnitId),
              siteId: siteId,
              productId: productId,
              productCode: product?['code'] as String? ?? 'PRD-?',
              productName: product?['name'] as String? ?? 'Product',
              defectCodeId: defectCodeId,
              defectCodeCode: defectCode?['code'] as String? ?? 'CODE-?',
              defectCodeName: defectCode?['name'] as String? ?? 'Defect code',
              defectCodeDefaultSeverity:
                  defectCode?['defaultSeverity'] as String? ?? 'minor',
              assetId: sent['assetId'] as String?,
              detectedAt: sent['detectedAt'] as String?,
            );
            nonconformances = {
              ...nonconformances,
              siteId: [created, ...(nonconformances[siteId] ?? const [])],
            };
            return http.Response(jsonEncode({'nonconformance': created}), 201);
          }
          nonconformanceListRequests.add(request.url.queryParameters);
          if (nonconformancesStatus != 200) {
            return http.Response(
              jsonEncode({'message': 'The register is unavailable.'}),
              nonconformancesStatus,
            );
          }
          final query = request.url.queryParameters;
          final orgUnitId = query['orgUnitId'];
          final scope = orgUnitId == null ? null : nonconformanceOrgUnitScope(orgUnitId);
          final status = query['status'];
          final defectCodeId = query['defectCodeId'];
          final productId = query['productId'];
          final severity = query['severity'];
          final from = query['from'];
          final to = query['to'];
          final sent = [
            for (final row in nonconformances[siteId] ?? const <Map<String, dynamic>>[])
              if (scope == null || scope.contains(row['orgUnitId']))
                if (status == null || row['status'] == status)
                  if (defectCodeId == null || row['defectCodeId'] == defectCodeId)
                    if (productId == null || row['productId'] == productId)
                      if (severity == null || row['severity'] == severity)
                        if (from == null || _nonconformanceDayOf(row).compareTo(from) >= 0)
                          if (to == null || _nonconformanceDayOf(row).compareTo(to) <= 0) row,
          ];
          return http.Response(
            jsonEncode({'nonconformances': sent, 'truncated': nonconformancesTruncated}),
            200,
          );
        }
        if (path.startsWith('/api/quality/nonconformances/')) {
          final remainder = path.substring('/api/quality/nonconformances/'.length);
          if (remainder.endsWith('/quantity') && request.method == 'POST') {
            final id = remainder.substring(0, remainder.length - '/quantity'.length);
            final sent = jsonDecode(request.body) as Map<String, dynamic>;
            nonconformanceQuantityPosts.add((id, sent));
            final row = nonconformanceById(id);
            if (row == null) {
              return http.Response(jsonEncode({'message': 'Non-conformance not found'}), 404);
            }
            final quantity = sent['quantity'] as num;
            final current = row['quantityAffected'] as num;
            if (increaseNonconformanceQuantityStatus != 200) {
              return http.Response(
                jsonEncode({'message': increaseNonconformanceQuantityMessage}),
                increaseNonconformanceQuantityStatus,
              );
            }
            // Mirrors the real route's own refusal, so a widget test that
            // sends a decrease sees what a client sees rather than a fake
            // that quietly accepts it.
            if (quantity <= current) {
              return http.Response(
                jsonEncode({
                  'message': quantity == current
                      ? 'the affected quantity is already that; a change records a difference'
                      : 'the affected quantity can only be increased'
                }),
                409,
              );
            }
            final changes = [
              ...(row['quantityChanges'] as List<dynamic>? ?? const []),
              quantityChangeJson(
                '$id-${(row['quantityChanges'] as List<dynamic>? ?? const []).length + 1}',
                current,
                quantity,
                note: sent['note'] as String?,
                changedByAccountName: 'Ann Operator',
              ),
            ];
            final updated = {...row, 'quantityAffected': quantity, 'quantityChanges': changes};
            _replaceNonconformance(id, updated);
            return http.Response(jsonEncode({'nonconformance': updated}), 200);
          }
          // The five writes issue #206 adds, each its own address: the
          // Disposition, the Concession, the lowered severity, the reopen and
          // the cancel. Each answers the whole record, as the real routes do.
          const actAddresses = <String>[
            '/dispositions',
            '/concession',
            '/lower-severity',
            '/reopen',
            '/cancel',
          ];
          String? act;
          if (request.method == 'POST') {
            for (final suffix in actAddresses) {
              if (remainder.endsWith(suffix)) act = suffix;
            }
          }
          if (act != null) {
            final id = remainder.substring(0, remainder.length - act.length);
            final sent = jsonDecode(request.body) as Map<String, dynamic>;
            final row = nonconformanceById(id);
            if (row == null) {
              return http.Response(jsonEncode({'message': 'Non-conformance not found'}), 404);
            }
            switch (act) {
              case '/dispositions':
                nonconformanceDispositionPosts.add((id, sent));
              case '/concession':
                nonconformanceConcessionPosts.add((id, sent));
              case '/lower-severity':
                nonconformanceLowerSeverityPosts.add((id, sent));
              case '/reopen':
                nonconformanceReopenPosts.add((id, sent));
              case '/cancel':
                nonconformanceCancelPosts.add((id, sent));
            }
            if (recordNonconformanceActStatus != 201) {
              return http.Response(
                jsonEncode({'message': recordNonconformanceActMessage}),
                recordNonconformanceActStatus,
              );
            }
            final corrections = [
              ...(row['corrections'] as List<dynamic>? ?? const []),
            ];
            Map<String, dynamic> updated = {...row};
            switch (act) {
              case '/dispositions':
              case '/concession':
                final concession = act == '/concession';
                final disposition = dispositionJson(
                  '$id-d${(row['dispositions'] as List<dynamic>? ?? const []).length + 1}',
                  dispositionType:
                      concession ? 'use_as_is' : sent['dispositionType'] as String,
                  isConcession: concession,
                  quantity: sent['quantity'] as num,
                  uomCode: row['uomCode'] as String,
                  reworkMinutes: (sent['reworkMinutes'] as num?) ?? 0,
                  reference: sent['reference'] as String?,
                  note: sent['note'] as String?,
                  decidedByAccountName: 'Ann Operator',
                );
                updated = {
                  ...row,
                  'dispositions': [
                    ...(row['dispositions'] as List<dynamic>? ?? const []),
                    disposition,
                  ],
                };
                updated = _settleDispositions(updated);
              case '/lower-severity':
                corrections.add(
                  correctionJson(
                    '$id-c${corrections.length + 1}',
                    kind: 'severity_lowered',
                    previousSeverity: row['severity'] as String?,
                    newSeverity: sent['severity'] as String?,
                    note: sent['note'] as String,
                    correctedByAccountName: 'Ann Operator',
                  ),
                );
                updated = {
                  ...row,
                  'severity': sent['severity'],
                  'corrections': corrections,
                };
              case '/reopen':
                corrections.add(
                  correctionJson(
                    '$id-c${corrections.length + 1}',
                    kind: 'reopened',
                    previousSeverity: null,
                    newSeverity: null,
                    previousStatus: row['status'] as String?,
                    newStatus: 'dispositioned',
                    note: sent['note'] as String,
                    correctedByAccountName: 'Ann Operator',
                  ),
                );
                updated = {
                  ...row,
                  'status': 'dispositioned',
                  'closedAt': null,
                  'corrections': corrections,
                };
              case '/cancel':
                corrections.add(
                  correctionJson(
                    '$id-c${corrections.length + 1}',
                    kind: 'cancelled',
                    previousSeverity: null,
                    newSeverity: null,
                    previousStatus: row['status'] as String?,
                    newStatus: 'cancelled',
                    note: sent['note'] as String,
                    correctedByAccountName: 'Ann Operator',
                  ),
                );
                updated = {
                  ...row,
                  'status': 'cancelled',
                  'closedAt': DateTime.now().toUtc().toIso8601String(),
                  'corrections': corrections,
                };
            }
            _replaceNonconformance(id, updated);
            return http.Response(
              jsonEncode({'nonconformance': updated}),
              act == '/dispositions' || act == '/concession' ? 201 : 200,
            );
          }
          if (request.method == 'PATCH') {
            final sent = jsonDecode(request.body) as Map<String, dynamic>;
            nonconformancePatches.add((remainder, sent));
            final row = nonconformanceById(remainder);
            if (row == null) {
              return http.Response(jsonEncode({'message': 'Non-conformance not found'}), 404);
            }
            if (changeNonconformanceStatus != 200) {
              return http.Response(
                jsonEncode({'message': changeNonconformanceMessage}),
                changeNonconformanceStatus,
              );
            }
            final updated = {...row};
            if (sent['severity'] != null) updated['severity'] = sent['severity'];
            if (sent['immediateContainment'] != null) {
              updated['immediateContainment'] = sent['immediateContainment'];
              if (updated['status'] == 'open') updated['status'] = 'contained';
            }
            _replaceNonconformance(remainder, updated);
            return http.Response(jsonEncode({'nonconformance': updated}), 200);
          }
          nonconformanceReads.add(path);
          if (nonconformancesStatus != 200) {
            return http.Response(
              jsonEncode({'message': 'The register is unavailable.'}),
              nonconformancesStatus,
            );
          }
          final row = nonconformanceById(remainder);
          if (row == null) {
            return http.Response(jsonEncode({'message': 'Non-conformance not found'}), 404);
          }
          return http.Response(jsonEncode({'nonconformance': row}), 200);
        }
        if (path == '/api/people/me') {
          return http.Response(
            jsonEncode(_meBody(role, selfId, selfEmployeeId, orgUnitScope)),
            200,
          );
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
          // A move (issue #171) is the one Asset PATCH whose answer the fake
          // cannot produce by echoing the request back: the real server
          // re-reads the row through its own Org Unit join, so the caller sees
          // where the Asset arrived — name included — rather than the id it
          // named. A fake that only echoed the id would let a passing test
          // assert a row the server could never send.
          final movedTo = body['orgUnitId'] as String?;
          final movedToRow = movedTo == null ? null : _orgUnitRowFor(movedTo);
          Map<String, dynamic>? updated;
          assets = {
            for (final entry in assets.entries)
              entry.key: [
                for (final a in entry.value)
                  if (a['id'] == id)
                    (updated = {
                      ...a,
                      ...body,
                      if (movedToRow != null) ...{
                        'orgUnitName': movedToRow['name'] as String,
                        'orgUnitCode': movedToRow['code'] as String,
                        // The Org Unit's own Site, as `toOrgUnit` sends it —
                        // this is what tells the client a move left the Site
                        // the register is showing.
                        'siteId': movedToRow['siteId'] ?? a['siteId'],
                      },
                    })
                  else a,
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
          final meterId = sent['assetMeterId'] as String?;
          final meter = meterId == null ? null : _meterRow(meterId);
          final intervalMeter = sent['intervalMeter'] as num?;
          final created = pmScheduleJson(
            '900',
            'PM-900',
            '${jobPlan['name'] ?? 'Job plan'} - ${asset['name'] ?? 'Asset'}',
            assetId: assetId,
            assetCode: asset['code'] as String? ?? 'ASSET',
            assetName: asset['name'] as String? ?? 'Asset',
            jobPlanId: jobPlanId,
            jobPlanName: jobPlan['name'] as String? ?? 'Job plan',
            intervalDays: (sent['intervalDays'] as num?)?.toInt(),
            assetMeterId: meterId,
            meterCode: meter?['code'] as String?,
            meterName: meter?['name'] as String?,
            meterType: meter?['meterType'] as String?,
            intervalMeter: intervalMeter,
            currentMeter: meter?['accumulatedUse'] as num?,
            nextDueMeter: meter == null || intervalMeter == null
                ? null
                : (meter['accumulatedUse'] as num) + intervalMeter,
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
        if (path == '/api/maintenance/units-of-measure') {
          if (unitsOfMeasureStatus != 200) {
            return http.Response(
              jsonEncode({'message': 'The units of measure are unavailable.'}),
              unitsOfMeasureStatus,
            );
          }
          return http.Response(jsonEncode({'unitsOfMeasure': unitsOfMeasure}), 200);
        }
        if (request.method == 'POST' && path == '/api/maintenance/meters') {
          final sent = jsonDecode(request.body) as Map<String, dynamic>;
          meterPosts.add(sent);
          if (createMeterStatus != 201) {
            return http.Response(jsonEncode({'message': createMeterMessage}), createMeterStatus);
          }
          final assetId = sent['assetId'] as String;
          final siteId = _siteOfAsset(assetId);
          final siteAssets = siteId == null ? const <Map<String, dynamic>>[] : (assets[siteId] ?? []);
          final asset = siteAssets.firstWhere(
            (a) => a['id'] == assetId,
            orElse: () => const <String, dynamic>{},
          );
          final created = meterJson(
            '900',
            sent['code'] as String,
            sent['name'] as String,
            assetId: assetId,
            assetCode: asset['code'] as String? ?? 'ASSET',
            assetName: asset['name'] as String? ?? 'Asset',
            orgUnitId: asset['orgUnitId'] as String? ?? '10',
            orgUnitName: asset['orgUnitName'] as String? ?? 'Line 1',
            uomCode: sent['uomCode'] as String,
            meterType: sent['meterType'] as String? ?? 'cumulative',
          );
          if (siteId != null) {
            meters = {
              ...meters,
              siteId: [...(meters[siteId] ?? []), created],
            };
          }
          return http.Response(jsonEncode({'meter': created}), 201);
        }
        if (request.method == 'POST' &&
            path.startsWith('/api/maintenance/meters/') &&
            path.endsWith('/readings')) {
          final meterId = path.split('/')[4];
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          meterReadingPosts.add((meterId, body));
          if (recordReadingStatus != 201) {
            return http.Response(jsonEncode({'message': recordReadingMessage}), recordReadingStatus);
          }
          final current = _meterRow(meterId);
          if (current == null) {
            return http.Response(jsonEncode({'message': 'Meter not found'}), 404);
          }
          final reading = body['reading'] as num;
          final updated = _applyMeterChanges(meterId, {
            'latestReading': reading,
            'latestReadAt': DateTime.now().toUtc().toIso8601String(),
            'accumulatedUse': reading + (current['rolloverOffset'] as num),
          });
          return http.Response(
            jsonEncode({
              'reading': {'id': '900', 'assetMeterId': meterId, 'reading': reading, 'source': 'manual'},
              'meter': updated,
            }),
            201,
          );
        }
        if (request.method == 'POST' &&
            path.startsWith('/api/maintenance/meters/') &&
            path.endsWith('/rollover')) {
          final meterId = path.split('/')[4];
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          meterRolloverPosts.add((meterId, body));
          if (rolloverStatus != 201) {
            return http.Response(jsonEncode({'message': rolloverMessage}), rolloverStatus);
          }
          final current = _meterRow(meterId);
          if (current == null) {
            return http.Response(jsonEncode({'message': 'Meter not found'}), 404);
          }
          final carried = current['accumulatedUse'] as num;
          final newReading = (body['reading'] as num?) ?? 0;
          final updated = _applyMeterChanges(meterId, {
            'rolloverOffset': carried,
            'latestReading': newReading,
            'latestReadAt': DateTime.now().toUtc().toIso8601String(),
            'accumulatedUse': carried + newReading,
          });
          return http.Response(
            jsonEncode({
              'reading': {'id': '901', 'assetMeterId': meterId, 'reading': newReading, 'source': 'manual'},
              'meter': updated,
            }),
            201,
          );
        }
        if (path.startsWith('/api/maintenance/sites/') && path.endsWith('/meters')) {
          final siteId = path.split('/')[4];
          meterSites.add(siteId);
          if (metersGate != null) await metersGate!.future;
          if (metersStatus != 200) {
            return http.Response(jsonEncode({'message': 'The meters are unavailable.'}), metersStatus);
          }
          final assetId = request.url.queryParameters['assetId'];
          final includeInactive = request.url.queryParameters['includeInactive'] == 'true';
          var sent = meters[siteId] ?? [];
          if (assetId != null) {
            sent = [for (final meter in sent) if (meter['assetId'] == assetId) meter];
          }
          if (!includeInactive) {
            sent = [for (final meter in sent) if (meter['isActive'] != false) meter];
          }
          return http.Response(jsonEncode({'meters': sent}), 200);
        }
        if (request.method == 'POST' &&
            path.startsWith('/api/maintenance/work-orders/') &&
            path.contains('/tasks/') &&
            path.endsWith('/reading')) {
          // '', 'api', 'maintenance', 'work-orders', ':id', 'tasks', ':taskId', 'reading'.
          final segments = path.split('/');
          final workOrderId = segments[4];
          final taskId = segments[6];
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          taskReadingPosts.add((workOrderId, taskId, body));
          final reading = body['reading'] as num;
          Map<String, dynamic>? updatedTask;
          final tasks = workOrderTasks[workOrderId] ?? [];
          workOrderTasks = {
            ...workOrderTasks,
            workOrderId: [
              for (final task in tasks)
                if (task['id'] == taskId) (updatedTask = {...task, 'reading': reading}) else task,
            ],
          };
          if (updatedTask == null) {
            return http.Response(jsonEncode({'message': 'Work order task not found'}), 404);
          }
          return http.Response(
            jsonEncode({
              'reading': {'id': '902', 'reading': reading, 'source': 'manual'},
              'task': updatedTask,
            }),
            201,
          );
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
                'cost': workOrderCosts[id] ?? workOrderCostJson(),
              },
            }),
            200,
          );
        }
        if (request.method == 'POST' &&
            path.startsWith('/api/maintenance/work-orders/') &&
            path.endsWith('/labour')) {
          final workOrderId = path.split('/')[4];
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          labourPosts.add((workOrderId, body));
          if (labourBookingStatus != 201) {
            return http.Response(jsonEncode({'message': labourBookingMessage}), labourBookingStatus);
          }
          // Reflect the booking on the next detail read, the same way the
          // server recomputes the cost: the hours follow from the window.
          final start = DateTime.parse(body['startedAt'] as String);
          final end = DateTime.parse(body['endedAt'] as String);
          final hours = end.difference(start).inMinutes / 60;
          final prior = workOrderCosts[workOrderId] ?? workOrderCostJson();
          final activities = [
            for (final row in (prior['labourByActivity'] as List<dynamic>).cast<Map<String, dynamic>>())
              Map<String, dynamic>.from(row),
          ];
          activities.add(labourActivityJson(
            body['activity'] as String,
            hours,
            overtimeHours: body['isOvertime'] == true ? hours : 0,
          ));
          final totalHours = activities.fold<num>(0, (sum, row) => sum + (row['hours'] as num));
          final overtime = activities.fold<num>(0, (sum, row) => sum + (row['overtimeHours'] as num));
          workOrderCosts = {
            ...workOrderCosts,
            workOrderId: {
              ...prior,
              'labourHours': totalHours,
              'overtimeHours': overtime,
              'labourByActivity': activities,
            },
          };
          return http.Response(jsonEncode({'labour': {'id': '900', ...body, 'hours': hours}}), 201);
        }
        if (request.method == 'POST' &&
            path.startsWith('/api/maintenance/work-orders/') &&
            path.endsWith('/parts')) {
          final workOrderId = path.split('/')[4];
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          partBookingPosts.add((workOrderId, body));
          if (partBookingStatus != 201) {
            return http.Response(jsonEncode({'message': partBookingMessage}), partBookingStatus);
          }
          final quantity = body['quantity'] as num;
          final unitCost = body['unitCost'] as num?;
          final totalCost = unitCost == null ? null : quantity * unitCost;
          final partNo = body['partNo'] as String?;
          // A `stores` booking derives its part number from the catalogue; the
          // fake resolves it off the scripted parts, the same way the real
          // server does.
          final catalogue = body['partId'] == null
              ? null
              : parts.firstWhere(
                  (p) => p['id'].toString() == body['partId'].toString(),
                  orElse: () => const <String, dynamic>{},
                );
          final prior = workOrderCosts[workOrderId] ?? workOrderCostJson();
          final booked = workOrderPartJson(
            '900',
            partNo: (partNo ?? catalogue?['partNo']) as String?,
            description: (body['description'] as String?) ??
                (catalogue?['description'] as String?) ??
                'Booked part',
            quantity: quantity,
            uomCode: (body['uomCode'] as String?) ?? (catalogue?['uomCode'] as String?) ?? 'EA',
            unitCost: unitCost,
            totalCost: totalCost,
            sourced: body['sourced'] as String? ?? 'stores',
          );
          final bookedParts = [
            ...(prior['parts'] as List<dynamic>).cast<Map<String, dynamic>>(),
            booked,
          ];
          final priced = bookedParts.where((p) => p['totalCost'] != null);
          workOrderCosts = {
            ...workOrderCosts,
            workOrderId: {
              ...prior,
              'parts': bookedParts,
              'partsCost': priced.isEmpty
                  ? null
                  : priced.fold<num>(0, (sum, p) => sum + (p['totalCost'] as num)),
            },
          };
          return http.Response(jsonEncode({'part': booked}), 201);
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
          // A floor request is the same endpoint behind a different door
          // (issue #77): recorded separately so a test can prove the device
          // credential and the individual identification each crossed the
          // wire, without disturbing the Account-path lists above.
          final floorDevice = request.headers['x-floor-device'];
          final floorIdentification = request.headers['x-technician-identification'];
          final int status;
          final String message;
          final Map<String, dynamic> update;
          switch (action) {
            case 'start':
              workOrderStarts.add(workOrderId);
              if (floorDevice != null) {
                floorWorkOrderStarts.add({
                  'id': workOrderId,
                  'device': floorDevice,
                  'identification': floorIdentification,
                });
              }
              status = startWorkOrderStatus;
              message = startWorkOrderMessage;
              update = {'status': 'in_progress'};
            case 'complete':
              workOrderCompletions.add((workOrderId, body));
              if (floorDevice != null) {
                floorWorkOrderCompletions.add({
                  'id': workOrderId,
                  'device': floorDevice,
                  'identification': floorIdentification,
                  'note': body['note'],
                });
              }
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
          if (floorDevice != null) {
            floorWorkOrders = [
              for (final wo in floorWorkOrders)
                if (wo['id'] == workOrderId) (updated = {...wo, ...update}) else wo,
            ];
          } else {
            workOrders = {
              for (final entry in workOrders.entries)
                entry.key: [
                  for (final wo in entry.value)
                    if (wo['id'] == workOrderId) (updated = {...wo, ...update}) else wo,
                ],
            };
          }
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
          if (skillsGate != null) await skillsGate!.future;
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
                        // Quality authority (issue #204, ADR-0035) — carried
                        // through exactly as sent, so a test that ticks the
                        // picker's box sees it come back on the row rather
                        // than only on the request.
                        qualityAuthority: g['qualityAuthority'] == true,
                        // Safety authority (issue #225, ADR-0035 applied a
                        // second time) — the same round trip as
                        // qualityAuthority above.
                        safetyAuthority: g['safetyAuthority'] == true,
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
        if (path.startsWith('/api/actions/sites/') && path.endsWith('/actions')) {
          actionReads.add(request.url);
          if (actionsGate != null) await actionsGate!.future;
          if (actionsStatus != 200) {
            return http.Response(
              jsonEncode({'message': 'The action log is unavailable.'}),
              actionsStatus,
            );
          }
          if (request.method == 'POST') {
            final sent = jsonDecode(request.body) as Map<String, dynamic>;
            actionPosts.add(sent);
            if (createActionStatus != 201) {
              return http.Response(jsonEncode({'message': createActionMessage}), createActionStatus);
            }
            // The raised row comes back in the shape the server sends: the
            // Org Unit it was raised at, the type it carries (the default is
            // the concern itself), and the Site from the path.
            final siteId = path.split('/')[4];
            final created = actionJson(
              '900',
              'AC-TEST-2026-00009',
              sent['title'] as String,
              actionType: (sent['actionType'] as String?) ?? 'concern',
              orgUnitId: sent['orgUnitId'] as String,
              orgUnitName: 'Raised Line',
              siteId: siteId,
              description: sent['description'] as String?,
              pillarCode: sent['pillarCode'] as String?,
              ownerEmployeeId: sent['ownerEmployeeId'] as String?,
              ownerName: sent['ownerEmployeeId'] == null ? null : 'Ann Fitter',
              dueDate: sent['dueDate'] as String?,
              priority: (sent['priority'] as int?) ?? 3,
            );
            actions = {
              ...actions,
              siteId: [...(actions[siteId] ?? const []), created],
            };
            return http.Response(jsonEncode({'action': created}), 201);
          }
          final siteId = path.split('/')[4];
          final includeHistory = request.url.queryParameters['includeHistory'] == 'true';
          final status = request.url.queryParameters['status'];
          final actionType = request.url.queryParameters['actionType'];
          final pillarCode = request.url.queryParameters['pillarCode'];
          final orgUnitId = request.url.queryParameters['orgUnitId'];
          final sent = [
            for (final action in actions[siteId] ?? const <Map<String, dynamic>>[])
              if (includeHistory ||
                  !const {'done', 'cancelled'}.contains(action['status']))
                if (status == null || action['status'] == status)
                  if (actionType == null || action['actionType'] == actionType)
                    if (pillarCode == null || action['pillarCode'] == pillarCode)
                      if (orgUnitId == null || action['orgUnitId'] == orgUnitId) action,
          ];
          return http.Response(jsonEncode({'actions': sent, 'truncated': false}), 200);
        }
        if (request.method == 'POST' &&
            path.startsWith('/api/actions/nonconformances/') &&
            path.endsWith('/concern')) {
          // `/api/actions/nonconformances/:id/concern` (issue #208): raising a
          // Concern from a Non-conformance. The row the server would write is
          // built from the Non-conformance the address names — the Org Unit is
          // the record's own, which is the whole point of the address — and
          // both sides are recorded: the concern in `actionDetails` so its own
          // Screen reads it, the concern on the Non-conformance's row so the
          // re-read after the raise shows it.
          final remainder = path.substring('/api/actions/nonconformances/'.length);
          final nonconformanceId = remainder.substring(0, remainder.length - '/concern'.length);
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          concernRaisePosts.add((nonconformanceId, body));
          if (raiseConcernStatus != 201) {
            return http.Response(jsonEncode({'message': raiseConcernMessage}), raiseConcernStatus);
          }
          final row = nonconformanceById(nonconformanceId);
          if (row == null) {
            return http.Response(jsonEncode({'message': 'Non-conformance not found'}), 404);
          }
          final concernId = (raisedConcern?['id'] ?? '901').toString();
          final occurrence = linkedNonconformanceJson(row, isSource: true);
          final concern = actionJson(
            concernId,
            'AC-TEST-2026-00009',
            (body['title'] as String?) ?? 'A Concern',
            description: body['description'] as String?,
            orgUnitId: row['orgUnitId'] as String,
            orgUnitName: row['orgUnitName'] as String,
            siteId: row['siteId'] as String,
            priority: (body['priority'] as int?) ?? 3,
            sourceNonconformanceId: nonconformanceId,
            nonconformances: [occurrence],
          )..['openPhase'] = phaseJson(1, 'plan');
          actionDetails[concernId] = concern;
          _replaceNonconformance(nonconformanceId, {
            ...row,
            'concerns': [
              ...(row['concerns'] as List<dynamic>? ?? const []),
              concernJson(concern, isSource: true),
            ],
          });
          return http.Response(jsonEncode({'action': concern}), 201);
        }
        if (request.method == 'POST' &&
            path.startsWith('/api/actions/') &&
            path.endsWith('/unlink')) {
          // `/api/actions/:id/nonconformances/:nonconformanceId/unlink` (issue
          // #208). The link is removed from both sides, as the real route
          // leaves them, and the Concern comes back as it now stands.
          final parts = path.split('/');
          final concernId = parts[3];
          final nonconformanceId = parts[5];
          nonconformanceUnlinkPosts.add((concernId, nonconformanceId));
          if (unlinkNonconformanceStatus != 200) {
            return http.Response(
              jsonEncode({'message': unlinkNonconformanceMessage}),
              unlinkNonconformanceStatus,
            );
          }
          final concern = actionDetails[concernId];
          if (concern == null) {
            return http.Response(jsonEncode({'message': 'Action not found'}), 404);
          }
          final updated = {
            ...concern,
            'nonconformances': [
              for (final occurrence in (concern['nonconformances'] as List<dynamic>? ?? const []))
                if ((occurrence as Map<String, dynamic>)['id'].toString() != nonconformanceId)
                  occurrence,
            ],
          };
          actionDetails[concernId] = updated;
          final row = nonconformanceById(nonconformanceId);
          if (row != null) {
            _replaceNonconformance(nonconformanceId, {
              ...row,
              'concerns': [
                for (final named in (row['concerns'] as List<dynamic>? ?? const []))
                  if ((named as Map<String, dynamic>)['id'].toString() != concernId) named,
              ],
            });
          }
          return http.Response(jsonEncode({'action': updated}), 200);
        }
        if (request.method == 'POST' &&
            path.startsWith('/api/actions/') &&
            path.endsWith('/nonconformances')) {
          // `/api/actions/:id/nonconformances` (issue #208): linking a further
          // Non-conformance to a Concern. Both sides record it, exactly as the
          // real route's transaction does.
          final concernId = path.split('/')[3];
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          nonconformanceLinkPosts.add((concernId, body));
          if (linkNonconformanceStatus != 201) {
            return http.Response(
              jsonEncode({'message': linkNonconformanceMessage}),
              linkNonconformanceStatus,
            );
          }
          final concern = actionDetails[concernId];
          if (concern == null) {
            return http.Response(jsonEncode({'message': 'Action not found'}), 404);
          }
          final nonconformanceId = body['nonconformanceId'].toString();
          final row = nonconformanceById(nonconformanceId);
          if (row == null) {
            return http.Response(jsonEncode({'message': 'Non-conformance not found'}), 404);
          }
          final occurrence = linkedNonconformanceJson(
            row,
            isSource: concern['sourceNonconformanceId']?.toString() == nonconformanceId,
          );
          final updated = {
            ...concern,
            'nonconformances': [
              ...(concern['nonconformances'] as List<dynamic>? ?? const []),
              occurrence,
            ],
          };
          actionDetails[concernId] = updated;
          _replaceNonconformance(nonconformanceId, {
            ...row,
            'concerns': [
              ...(row['concerns'] as List<dynamic>? ?? const []),
              concernJson(updated, isSource: occurrence['isSource'] as bool),
            ],
          });
          return http.Response(jsonEncode({'action': updated}), 201);
        }
        if (request.method == 'GET' && path == '/api/actions/pillars') {
          if (pillarsStatus != 200) {
            return http.Response(
              jsonEncode({'message': 'The Pillar catalogue is unavailable.'}),
              pillarsStatus,
            );
          }
          return http.Response(jsonEncode({'pillars': pillars}), 200);
        }
        if (request.method == 'GET' && path.endsWith('/escalation-targets')) {
          // `/api/actions/:id/escalation-targets` (issue #180). The list is the
          // server's own tree walk; the fake is told it rather than working it
          // out, because a fake that climbed the tree would be a second
          // implementation of a rule the backend tests already pin.
          if (escalationTargetsStatus != 200) {
            return http.Response(
              jsonEncode({'message': escalationTargetsMessage}),
              escalationTargetsStatus,
            );
          }
          return http.Response(jsonEncode({'targets': escalationTargets}), 200);
        }
        if (request.method == 'POST' &&
            path.startsWith('/api/actions/') &&
            path.endsWith('/escalate')) {
          // `/api/actions/:id/escalate` (issue #180): the row keeps its status
          // and its cycle and only gains who has been told.
          final id = path.split('/')[3];
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          escalations.add((id, body));
          if (escalateActionStatus != 200) {
            return http.Response(
              jsonEncode({'message': escalateActionMessage}),
              escalateActionStatus,
            );
          }
          final stored = actionDetails[id];
          if (stored == null) {
            return http.Response(jsonEncode({'message': 'Action not found'}), 404);
          }
          final targetId = body['orgUnitId'] as String;
          Map<String, dynamic>? target;
          for (final candidate in escalationTargets) {
            if (candidate['id'].toString() == targetId) target = candidate;
          }
          stored['escalatedToOrgUnitId'] = targetId;
          stored['escalatedToOrgUnitCode'] = target?['code'];
          stored['escalatedToOrgUnitName'] = target?['name'];
          stored['escalatedAt'] = '2026-09-15T04:00:00.000Z';
          return http.Response(jsonEncode({'action': stored}), 200);
        }
        if (request.method == 'POST' &&
            path.startsWith('/api/actions/') &&
            path.endsWith('/cancel')) {
          // `/api/actions/:id/cancel` (issue #179). The stored Action ends the
          // way the server ends it: the status, the timestamp and the note the
          // cancellation wrote.
          final id = path.split('/')[3];
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          cancellations.add((id, body));
          if (cancelActionStatus != 200) {
            return http.Response(
              jsonEncode({'message': cancelActionMessage}),
              cancelActionStatus,
            );
          }
          final stored = actionDetails[id];
          if (stored == null) {
            return http.Response(jsonEncode({'message': 'Action not found'}), 404);
          }
          stored['status'] = 'cancelled';
          stored['completedAt'] = '2026-09-15T04:00:00.000Z';
          stored['closureNote'] = body['reason'];
          stored['openPhase'] = null;
          return http.Response(jsonEncode({'action': stored}), 200);
        }
        if (request.method == 'POST' &&
            path.startsWith('/api/actions/') &&
            path.endsWith('/measures')) {
          // `/api/actions/:id/measures` (issue #178). The created measure is
          // appended to the stored Concern so a re-read sees it, in the
          // shape the server sends: an Action with a parent named. The
          // ordering the real server applies (containment, then countermeasure,
          // then preventive) is asserted in the backend suite, not here.
          final concernId = path.split('/')[3];
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          measurePosts.add((concernId, body));
          if (createMeasureStatus != 201) {
            return http.Response(
              jsonEncode({'message': createMeasureMessage}),
              createMeasureStatus,
            );
          }
          final concern = actionDetails[concernId];
          if (concern == null) {
            return http.Response(jsonEncode({'message': 'Action not found'}), 404);
          }
          final measure = actionJson(
            '800',
            'AC-TEST-2026-00008',
            body['title'] as String,
            actionType: body['actionType'] as String,
            orgUnitId: (body['orgUnitId'] as String?) ?? concern['orgUnitId'] as String,
            orgUnitName: (body['orgUnitId'] as String?) == null
                ? concern['orgUnitName'] as String
                : 'Another Unit',
            siteId: concern['siteId'] as String,
            ownerName: body['ownerEmployeeId'] == null ? null : 'Ann Fitter',
            dueDate: body['dueDate'] as String?,
            priority: (body['priority'] as int?) ?? 3,
            parentId: concernId,
            parent: {
              'id': concernId,
              'actionNo': concern['actionNo'],
              'title': concern['title'],
              'actionType': concern['actionType'],
              'status': concern['status'],
            },
          )..['openPhase'] = phaseJson(1, 'plan');
          concern['measures'] = [...(concern['measures'] as List<dynamic>? ?? const []), measure];
          concern['measureCount'] = (concern['measureCount'] as int? ?? 0) + 1;
          if (body['actionType'] == 'countermeasure') {
            concern['countermeasureCount'] = (concern['countermeasureCount'] as int? ?? 0) + 1;
          }
          return http.Response(jsonEncode({'action': measure}), 201);
        }
        if (request.method == 'POST' &&
            path.startsWith('/api/actions/') &&
            path.endsWith('/complete')) {
          // `/api/actions/:id/phases/:phase/complete`. The fake walks the cycle
          // the way actions.js's own `nextPhase` does — completing the open
          // phase, opening the next (or the next cycle's Plan after a Check
          // that did not hold, or nothing after an Act) — because the point of
          // these tests is what the Screen renders from the server's answer.
          // The authority on the rule is the backend suite, not this.
          final parts = path.split('/');
          final id = parts[3];
          final phase = parts[5];
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          phaseCompletions.add((id, phase, body));
          if (completePhaseStatus != 200) {
            return http.Response(
              jsonEncode({'message': completePhaseMessage}),
              completePhaseStatus,
            );
          }
          final updated = _completeStoredPhase(id, phase, body);
          if (updated == null) {
            return http.Response(jsonEncode({'message': 'Action not found'}), 404);
          }
          return http.Response(jsonEncode({'action': updated}), 200);
        }
        if (request.method == 'POST' &&
            path.startsWith('/api/actions/capas/') &&
            path.endsWith('/causes')) {
          // `/api/actions/capas/:id/causes` (issue #213): recording a candidate
          // cause under one 6M category. The fake does what the server does —
          // the position is the category's own next one, computed here rather
          // than sent, and a new cause is a `candidate` — so a test asserting
          // the fishbone on screen is asserting rows the API would really have
          // returned.
          final capaId = path.split('/')[4];
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          causePosts.add((capaId, body));
          if (addCauseStatus != 201) {
            return http.Response(jsonEncode({'message': addCauseMessage}), addCauseStatus);
          }
          final capa = capas[capaId];
          if (capa == null) {
            return http.Response(jsonEncode({'message': 'CAPA not found'}), 404);
          }
          final category = body['category'].toString();
          // Copied rather than added to in place: a fixture's own list may be a
          // `const []` where none was passed, and the fake must be able to grow
          // the CAPA it stores.
          final causes = [...(capa['causes'] as List<dynamic>? ?? <dynamic>[])];
          final sequence = causes
                  .whereType<Map<String, dynamic>>()
                  .where((cause) => cause['category'] == category)
                  .length +
              1;
          causes.add(capaCauseJson(
            '${_nextCauseId++}',
            category,
            sequence,
            body['statement'].toString(),
          ));
          capa['causes'] = causes;
          return http.Response(jsonEncode({'capa': capa}), 201);
        }
        if (request.method == 'POST' &&
            path.startsWith('/api/actions/capas/') &&
            path.contains('/causes/') &&
            path.endsWith('/whys')) {
          // `/api/actions/capas/:id/causes/:causeId/whys` (issue #213):
          // starting one of the two chains from a confirmed cause. Declared
          // **before** #210's own `/whys` handler below, deliberately: that one
          // matches any POST under `/api/actions/capas/` ending in `/whys`, so
          // this address would be read as an add-Why against a CAPA whose id is
          // `causes`. The fake writes the chain's first Why, whose statement is
          // the caller's or the cause's own — the server's own rule.
          final parts = path.split('/');
          final capaId = parts[4];
          final causeId = parts[6];
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          causeWhyPosts.add((capaId, causeId, body));
          if (startWhyFromCauseStatus != 201) {
            return http.Response(
              jsonEncode({'message': startWhyFromCauseMessage}),
              startWhyFromCauseStatus,
            );
          }
          final capa = capas[capaId];
          if (capa == null) {
            return http.Response(jsonEncode({'message': 'CAPA not found'}), 404);
          }
          final cause = _storedCause(capa, causeId);
          if (cause == null) {
            return http.Response(jsonEncode({'message': 'candidate cause not found'}), 404);
          }
          // Copied rather than added to in place, for the same reason the cause
          // handler above copies: a fixture that passed no whys holds a
          // `const []`.
          final whys = [...(capa['whys'] as List<dynamic>? ?? <dynamic>[])];
          whys.add(capaWhyJson(
            '${_nextWhyId++}',
            1,
            (body['statement'] ?? cause['statement']).toString(),
            chain: body['chain'].toString(),
          ));
          capa['whys'] = whys;
          return http.Response(jsonEncode({'capa': capa}), 201);
        }
        if ((request.method == 'PATCH' || request.method == 'DELETE') &&
            path.startsWith('/api/actions/capas/') &&
            path.contains('/causes/')) {
          // `/api/actions/capas/:id/causes/:causeId` (issue #213) — changing
          // one candidate cause, or removing it. A change applies what the
          // server would apply: the sentence and the category when they were
          // sent, and the verdict with its evidence together — `candidate`
          // clearing the note, for the same reason the server clears it. The
          // rules themselves are the backend suite's to prove.
          final parts = path.split('/');
          final capaId = parts[4];
          final causeId = parts[6];
          final capa = capas[capaId];
          if (request.method == 'PATCH') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            causePatches.add((capaId, causeId, body));
            if (changeCauseStatus != 200) {
              return http.Response(jsonEncode({'message': changeCauseMessage}), changeCauseStatus);
            }
            if (capa == null || !_changeStoredCause(capa, causeId, body)) {
              return http.Response(jsonEncode({'message': 'candidate cause not found'}), 404);
            }
            return http.Response(jsonEncode({'capa': capa}), 200);
          }
          causeDeletions.add((capaId, causeId));
          if (removeCauseStatus != 200) {
            return http.Response(jsonEncode({'message': removeCauseMessage}), removeCauseStatus);
          }
          if (capa == null || !_removeStoredCause(capa, causeId)) {
            return http.Response(jsonEncode({'message': 'candidate cause not found'}), 404);
          }
          return http.Response(jsonEncode({'capa': capa}), 200);
        }
        if (request.method == 'POST' &&
            path.startsWith('/api/actions/') &&
            path.endsWith('/capa')) {
          // `/api/actions/:id/capa` (issue #209): opening a CAPA on a Concern.
          // The row the server would write is built from the Concern the
          // address names — the CAPA's Org Unit and title are the Concern's —
          // and its own answer carries that Concern back with the `capa` link
          // set, which is what the Screen behind the dialog reads next.
          final concernId = path.split('/')[3];
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          capaPosts.add((concernId, body));
          if (createCapaStatus != 201) {
            return http.Response(jsonEncode({'message': createCapaMessage}), createCapaStatus);
          }
          final concern = actionDetails[concernId];
          if (concern == null) {
            return http.Response(jsonEncode({'message': 'Concern not found'}), 404);
          }
          final capaId = (openedCapa?['id'] ?? '801').toString();
          final capaNo = (openedCapa?['capaNo'] ?? 'CA-TEST-2026-00001').toString();
          final linked = <String, dynamic>{
            ...concern,
            'capa': {'id': capaId, 'capaNo': capaNo, 'status': 'open'},
          };
          actionDetails[concernId] = linked;
          final capa = capaJson(
            capaId,
            capaNo,
            concern['title'] as String,
            orgUnitId: concern['orgUnitId'] as String,
            orgUnitName: concern['orgUnitName'] as String,
            siteId: concern['siteId'] as String,
            problemStatement: body['problemStatement'] as String?,
            teamLead: _capaTeamRow(body['teamLeadEmployeeId']),
            teamMembers: [
              for (final member in (body['teamMemberEmployeeIds'] as List<dynamic>? ?? const []))
                _capaTeamRow(member)!,
            ],
            concern: linked,
          );
          capas[capaId] = capa;
          return http.Response(jsonEncode({'capa': capa}), 201);
        }
        if (request.method == 'POST' &&
            path.startsWith('/api/actions/capas/') &&
            path.endsWith('/whys')) {
          // `/api/actions/capas/:id/whys` (issue #210): adding a Why to one of
          // the two chains. The fake does what the server does — the position
          // is the chain's own next one, computed here rather than sent — so a
          // test asserting the order on screen is asserting an order the API
          // would really have produced.
          final capaId = path.split('/')[4];
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          whyPosts.add((capaId, body));
          if (addWhyStatus != 201) {
            return http.Response(jsonEncode({'message': addWhyMessage}), addWhyStatus);
          }
          final capa = capas[capaId];
          if (capa == null) {
            return http.Response(jsonEncode({'message': 'CAPA not found'}), 404);
          }
          final chain = body['chain'].toString();
          final whys = (capa['whys'] as List<dynamic>? ?? <dynamic>[]);
          final sequence = whys
                  .whereType<Map<String, dynamic>>()
                  .where((why) => why['chain'] == chain)
                  .length +
              1;
          whys.add(capaWhyJson('${_nextWhyId++}', sequence, body['statement'].toString(),
              chain: chain));
          capa['whys'] = whys;
          return http.Response(jsonEncode({'capa': capa}), 201);
        }
        if ((request.method == 'PATCH' || request.method == 'DELETE') &&
            path.startsWith('/api/actions/capas/') &&
            path.contains('/whys/')) {
          // `/api/actions/capas/:id/whys/:whyId` (issue #210) — changing one
          // Why, or removing it. Both renumber the chain around the change,
          // which is the rule a Screen renders and the ticket states: a chain
          // reads 1..n with no gap, whatever was done to it. The authority on
          // all of it is the backend suite, not this.
          final parts = path.split('/');
          final capaId = parts[4];
          final whyId = parts[6];
          final capa = capas[capaId];
          if (request.method == 'PATCH') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            whyPatches.add((capaId, whyId, body));
            if (changeWhyStatus != 200) {
              return http.Response(jsonEncode({'message': changeWhyMessage}), changeWhyStatus);
            }
            if (capa == null || !_changeStoredWhy(capa, whyId, body)) {
              return http.Response(jsonEncode({'message': 'Why not found'}), 404);
            }
            return http.Response(jsonEncode({'capa': capa}), 200);
          }
          whyDeletions.add((capaId, whyId));
          if (removeWhyStatus != 200) {
            return http.Response(jsonEncode({'message': removeWhyMessage}), removeWhyStatus);
          }
          if (capa == null || !_removeStoredWhy(capa, whyId)) {
            return http.Response(jsonEncode({'message': 'Why not found'}), 404);
          }
          return http.Response(jsonEncode({'capa': capa}), 200);
        }
        if (request.method == 'POST' &&
            path.startsWith('/api/actions/capas/') &&
            path.endsWith('/effectiveness')) {
          // `/api/actions/capas/:id/effectiveness` (issue #211) — recording the
          // effectiveness check. The fake does what the server does with the
          // verdict, so a test that asserts the Screen behind the dialog
          // repainted is asserting a state the API would really have produced:
          // an `effective` check closes the investigation, a `not_effective` one
          // clears the due date and leaves the CAPA open where its Concern is
          // being worked again.
          //
          // The verifier and the time are the caller's own Account and `now()`,
          // which is what the server writes — and the one thing a fake keyed on
          // a single signed-in Account can stand in for.
          final capaId = path.split('/')[4];
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          effectivenessPosts.add((capaId, body));
          if (effectivenessStatus != 200) {
            return http.Response(
              jsonEncode({'message': effectivenessMessage}),
              effectivenessStatus,
            );
          }
          final capa = capas[capaId];
          if (capa == null) {
            return http.Response(jsonEncode({'message': 'CAPA not found'}), 404);
          }
          final effective = body['outcome'] == 'effective';
          final now = DateTime.now().toUtc().toIso8601String();
          capa['status'] = effective ? 'closed' : 'actions';
          capa['closedAt'] = effective ? now : null;
          capa['effectivenessVerifiedAt'] = now;
          capa['effectivenessVerifiedBy'] = {'accountId': selfId, 'name': 'A B'};
          capa['effectivenessNote'] = body['note'];
          if (!effective) capa['effectivenessCheckDueAt'] = null;
          capa['effectivenessCheckOverdue'] = false;
          return http.Response(jsonEncode({'capa': capa}), 200);
        }
        if (request.method == 'GET' && path == '/api/actions/capas') {
          // The CAPA list (issue #211): every stored CAPA, narrowed the way the
          // server narrows — by status and by an overdue check exactly, and by
          // Org Unit exactly. The "and everything beneath it" half is the
          // backend's own ltree walk (proved in
          // `backend/test/integration/capa-effectiveness.test.js`); what this
          // fake is for is the *request* the Screen sends and the rows it
          // renders, and `capaListRequests` is where the first of those is
          // asserted.
          capaListRequests.add({...request.url.queryParameters});
          if (capaListStatus != 200) {
            return http.Response(jsonEncode({'message': capaListMessage}), capaListStatus);
          }
          final query = request.url.queryParameters;
          final rows = [
            for (final capa in capas.values)
              if ((query['status'] == null || capa['status'] == query['status']) &&
                  (query['orgUnitId'] == null || capa['orgUnitId'] == query['orgUnitId']) &&
                  (query['overdue'] != 'true' || capa['effectivenessCheckOverdue'] == true))
                capa,
          ];
          return http.Response(jsonEncode({'capas': rows, 'truncated': false}), 200);
        }
        if (request.method == 'GET' && path.startsWith('/api/actions/capas/')) {
          // `/api/actions/capas/:id` (issue #209). Declared before the
          // one-segment `/api/actions/:id` read below, which would otherwise
          // take `capas/801` for an Action whose id is `801`.
          final capaId = path.split('/').last;
          // Recorded before anything can refuse it, so a test can assert which
          // report asked for which record even when the read fails.
          capaReads.add(capaId);
          if (capasStatus != 200) {
            return http.Response(jsonEncode({'message': capaMessage}), capasStatus);
          }
          final capa = capas[capaId];
          if (capa == null) {
            return http.Response(jsonEncode({'message': 'CAPA not found'}), 404);
          }
          return http.Response(jsonEncode({'capa': capa}), 200);
        }
        if (request.method == 'GET' && path.startsWith('/api/actions/')) {
          final id = path.split('/').last;
          final action = actionDetails[id];
          if (action == null) {
            return http.Response(jsonEncode({'message': 'Action not found'}), 404);
          }
          return http.Response(jsonEncode({'action': action}), 200);
        }
        return http.Response('{}', 404);
      });
}

/// One Action as `/api/actions` sends it (issue #176) — the client-side
/// counterpart of the backend's own `toAction`.
Map<String, dynamic> actionJson(
  String id,
  String actionNo,
  String title, {
  String actionType = 'concern',
  String status = 'open',
  String orgUnitId = '10',
  String orgUnitName = 'Line 1',
  String siteId = '1',
  String? description,
  String? pillarCode,
  String? ownerEmployeeId,
  String? ownerName,
  String? dueDate,
  bool isOverdue = false,
  int? daysOverdue,
  int priority = 3,
  String? escalatedToOrgUnitId,
  String? escalatedToOrgUnitName,
  String raisedAt = '2026-09-15T02:00:00.000Z',
  Map<String, dynamic>? parent,
  String? parentId,
  int measureCount = 0,
  int countermeasureCount = 0,
  List<Map<String, dynamic>> measures = const [],
  List<Map<String, dynamic>> phases = const [],
  Map<String, dynamic>? openPhase,
  String? sourceNonconformanceId,
  List<Map<String, dynamic>> nonconformances = const [],
  Map<String, dynamic>? capa,
}) =>
    {
      'id': id,
      'actionNo': actionNo,
      'title': title,
      'description': description,
      'actionType': actionType,
      'pillarCode': pillarCode,
      'orgUnitId': orgUnitId,
      'orgUnitName': orgUnitName,
      'siteId': siteId,
      'ownerEmployeeId': ownerEmployeeId,
      'ownerName': ownerName,
      'raisedByEmployeeId': null,
      'raisedByName': null,
      'raisedAt': raisedAt,
      'dueDate': dueDate,
      'isOverdue': isOverdue,
      'daysOverdue': daysOverdue,
      'priority': priority,
      'status': status,
      'completedAt': null,
      'closureNote': null,
      'escalatedToOrgUnitId': escalatedToOrgUnitId,
      'escalatedToOrgUnitName': escalatedToOrgUnitName,
      'escalatedAt': null,
      'sourceType': 'standalone',
      'parentId': parentId,
      'measureCount': measureCount,
      'countermeasureCount': countermeasureCount,
      'parent': parent,
      'measures': measures,
      'phases': phases,
      'openPhase': openPhase,
      // Provenance and the link list (issue #208): the Non-conformance the
      // Concern was raised from, and every occurrence it answers.
      'sourceNonconformanceId': sourceNonconformanceId,
      'nonconformances': nonconformances,
      // The CAPA opened on this Action, if one has been (issue #209) —
      // `{id, capaNo, status}` or null, which is the state every Concern is in
      // until somebody opens one.
      'capa': capa,
    };

/// One CAPA as `GET /api/actions/capas/:id` sends it (issue #209) — the
/// client-side counterpart of the backend's own `toCapa`, key for key.
///
/// `concern` is the Concern's own detail read (an [actionJson] row, with its
/// `capa` link set): the server returns the Concern with its measures and every
/// phase they have been round, so a fixture that omitted them would let a test
/// assert a CAPA the API cannot answer.
Map<String, dynamic> capaJson(
  String id,
  String capaNo,
  String title, {
  String method = '8d',
  String status = 'open',
  String orgUnitId = '10',
  String orgUnitName = 'Line 1',
  String? orgUnitCode,
  String siteId = '1',
  String? problemStatement,
  Map<String, dynamic>? teamLead,
  List<Map<String, dynamic>> teamMembers = const [],
  List<Map<String, dynamic>> whys = const [],
  List<Map<String, dynamic>> causes = const [],
  String openedAt = '2026-09-16T02:00:00.000Z',
  String? dueDate,
  int effectivenessCheckDelayDays = 30,
  String? effectivenessCheckDueAt,
  bool effectivenessCheckOverdue = false,
  String? effectivenessVerifiedAt,
  Map<String, dynamic>? effectivenessVerifiedBy,
  String? effectivenessNote,
  Map<String, dynamic>? concern,
}) =>
    {
      'id': id,
      'capaNo': capaNo,
      'title': title,
      'method': method,
      'status': status,
      'orgUnitId': orgUnitId,
      'orgUnitCode': orgUnitCode ?? orgUnitName.toUpperCase().replaceAll(' ', '-'),
      'orgUnitName': orgUnitName,
      'siteId': siteId,
      'problemStatement': problemStatement,
      'teamLead': teamLead,
      'teamMembers': teamMembers,
      // The two 5 Why chains (issue #210), in the order the server sends them:
      // `occurrence` first, then `escape`, each chain in its own order.
      'whys': whys,
      // The fishbone (issue #213), in the order the server sends it: the 6M's
      // own order, each category in the order its causes were recorded.
      'causes': causes,
      'openedAt': openedAt,
      'dueDate': dueDate,
      'closedAt': null,
      // The effectiveness check (issue #211): the delay, the date the closure
      // produced, whether that date has passed, and what a check recorded —
      // `{accountId, name}`, which is what the server writes rather than a bare
      // id, because an administrator need not be an Employee.
      'effectivenessCheckDelayDays': effectivenessCheckDelayDays,
      'effectivenessCheckDueAt': effectivenessCheckDueAt,
      'effectivenessCheckOverdue': effectivenessCheckOverdue,
      'effectivenessVerifiedAt': effectivenessVerifiedAt,
      'effectivenessVerifiedBy': effectivenessVerifiedBy,
      'effectivenessNote': effectivenessNote,
      'concern': concern,
    };

/// One Why of one of a CAPA's chains, as `GET /api/actions/capas/:id` sends it
/// (issue #210) — the client-side counterpart of the backend's own `toWhy`,
/// key for key.
Map<String, dynamic> capaWhyJson(
  String id,
  int sequence,
  String statement, {
  String chain = 'occurrence',
  bool isRoot = false,
}) =>
    {
      'id': id,
      'chain': chain,
      'sequence': sequence,
      'statement': statement,
      'isRoot': isRoot,
      'createdAt': '2026-09-16T03:00:00.000Z',
      'updatedAt': '2026-09-16T03:00:00.000Z',
    };

/// One candidate cause on a CAPA's fishbone, as `GET /api/actions/capas/:id`
/// sends it (issue #213) — the client-side counterpart of the backend's own
/// `toCause`, key for key. `verdict` defaults to `candidate` and `evidenceNote`
/// to null, which is what recording a cause produces; a decided one carries
/// both.
Map<String, dynamic> capaCauseJson(
  String id,
  String category,
  int sequence,
  String statement, {
  String verdict = 'candidate',
  String? evidenceNote,
}) =>
    {
      'id': id,
      'category': category,
      'sequence': sequence,
      'statement': statement,
      'verdict': verdict,
      'evidenceNote': evidenceNote,
      'createdAt': '2026-09-16T03:00:00.000Z',
      'updatedAt': '2026-09-16T03:00:00.000Z',
    };

/// One phase as the Action's own `phases` array sends it (issue #177).
Map<String, dynamic> phaseJson(
  int cycle,
  String phase, {
  String? id,
  String? note,
  String? completedAt,
  String? outcome,
  String? ownerName,
  String? dueDate,
}) =>
    {
      'id': id,
      'cycle': cycle,
      'phase': phase,
      'ownerEmployeeId': null,
      'ownerName': ownerName,
      'dueDate': dueDate,
      'completedAt': completedAt,
      'outcome': outcome,
      'note': note,
    };

/// One Pillar as `GET /api/actions/pillars` sends it.
Map<String, dynamic> pillarJson(String code, String name, int sortOrder) => {
      'code': code,
      'name': name,
      'description': '$name measures',
      'sortOrder': sortOrder,
    };

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

/// A floor device provisioned with [deviceCredential] (issue #77). Pass
/// `null` to prove the not-registered state a build without a credential
/// shows.
class FakeFloorDeviceGateway implements FloorDeviceGateway {
  FakeFloorDeviceGateway([this.deviceCredential = 'device-credential']);

  @override
  final String? deviceCredential;
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
  FloorDeviceGateway? floorDeviceGateway,
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
      // The Actions Module's own client over the same faked wire.
      actionsApi: ActionsApi(client: client),
      // The Quality Module's own client over the same faked wire (issue #203).
      qualityApi: QualityApi(client: client),
      // The floor surface's device credential, faked at the same seam.
      floorDeviceGateway: floorDeviceGateway ?? FakeFloorDeviceGateway(),
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

/// Types [term] into an `AppSearchField` (ADR-0023) and waits out the field's
/// own ~300ms debounce (plus a frame for the fetch's future to land), leaving
/// whatever the field now shows — suggestions, the no-match state, or nothing
/// at all below its two-character minimum — on screen for the caller to assert
/// on. No request is issued by any caller whose `fetchSuggestions` filters a
/// list it already holds, which is the point of the test that uses this.
Future<void> typeInSearchField(WidgetTester tester, Key fieldKey, String term) async {
  await tester.enterText(find.byKey(fieldKey), term);
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

/// Picks one record out of an `AppSearchField` the way a person does: type a
/// term, wait out the debounce, then tap the suggestion row the field offers.
///
/// A test that wants to assert what the field *displays* after the pick reads
/// the `TextField`'s own controller — the field writes the chosen record's
/// display string there and renders it as nothing else.
Future<void> pickSuggestion(
  WidgetTester tester, {
  required Key fieldKey,
  required String term,
  required Key suggestionKey,
}) async {
  await typeInSearchField(tester, fieldKey, term);
  await tapIn(tester, find.byKey(suggestionKey));
}

/// What an `AppSearchField` at [fieldKey] is currently displaying, read off
/// the `TextField`'s own controller.
String searchFieldText(WidgetTester tester, Key fieldKey) =>
    tester.widget<TextField>(find.byKey(fieldKey)).controller!.text;

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
