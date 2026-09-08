/// Shared test harness for the client's widget tests.
///
/// The fake wire and the `pumpApp`/`meClient` pump helpers are used by every
/// Screen's tests, so they live here — somewhere neutral — rather than inside
/// whichever Screen's test file happened to need them first (issue #60, done
/// ahead of the Maintenance Module's own tests in #55).
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:lean_platform/maintenance/maintenance_api.dart';
import 'package:lean_platform/people_api.dart';
import 'package:lean_platform/platform/auth_gateway.dart';
import 'package:lean_platform/platform/destinations.dart';
import 'package:lean_platform/platform/platform_app.dart';

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

/// One row of `GET /api/people/employees` (issue #86) — mirrors `toEmployee`
/// (directory.js) exactly: no job role, no Org Unit, since the list endpoint
/// carries neither. See `Employee`'s own header (`lib/people/employee.dart`).
Map<String, dynamic> employeeJson(
  String id,
  String employeeNo,
  String displayName, {
  String employmentType = 'permanent',
  bool isActive = true,
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

/// One skill on `GET /api/people/employees/:id`'s own `skills` — deliberately
/// without `isLapsed`, unlike [heldSkillJson]: `getEmployeeDetail`
/// (directory.js) never computes it, only `listAssigneeCandidates` does. See
/// `PeopleApi._isLapsed`'s own header for why the client derives it here.
Map<String, dynamic> employeeSkillJson(
  String id,
  String skillId,
  String code,
  String name, {
  int proficiencyLevel = 3,
  String? expiresOn,
}) =>
    {
      'id': id,
      'proficiencyLevel': proficiencyLevel,
      'assessedOn': '2024-01-01',
      'expiresOn': expiresOn,
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

Map<String, dynamic> pendingJson(String id, String email, DateTime since) => {
      'id': id,
      'email': email,
      'createdAt': since.toUtc().toIso8601String(),
    };

Map<String, dynamic> siteJson(String id, String code, String name) =>
    {'id': id, 'code': code, 'name': name, 'timezone': 'Europe/London'};

/// An Org Unit row exactly as `plant.js` sends one — `parentId` included,
/// because a root-level response can legitimately carry a non-null one.
Map<String, dynamic> orgUnitJson(
  String id,
  String name, {
  String? parentId,
  String unitType = 'area',
}) =>
    {
      'id': id,
      'parentId': parentId,
      'code': name.toUpperCase().replaceAll(' ', '-'),
      'name': name,
      'unitType': unitType,
      'path': id,
      'sortOrder': 0,
      'isActive': true,
    };

/// One Account as `GET /api/people/accounts` sends it.
Map<String, dynamic> accountJson(
  String id,
  String email, {
  String role = Roles.operator,
  bool isActive = true,
  String approvalStatus = 'approved',
  List<Map<String, dynamic>> grants = const [],
}) =>
    {
      'id': id,
      'email': email,
      'displayName': email.split('@').first,
      'role': role,
      'isActive': isActive,
      'approvalStatus': approvalStatus,
      'grants': grants,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
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
    List<Map<String, dynamic>>? accounts,
    this.accountsStatus = 200,
    this.patchStatus = 200,
    List<Map<String, dynamic>>? sites,
    Map<String?, List<Map<String, dynamic>>>? orgUnits,
    this.sitesStatus = 200,
    this.orgUnitsStatus = 200,
    this.orgUnitScope,
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
    List<Map<String, dynamic>>? employees,
    this.employeesStatus = 200,
    Map<String, Map<String, dynamic>>? employeeDetails,
    this.employeeDetailStatus = 200,
    this.employeeDetailMessage = 'That Employee record could not be read.',
    List<Map<String, dynamic>>? jobRoles,
    this.jobRolesStatus = 200,
  })  : queue = queue ?? [],
        assets = assets ?? {},
        accounts = accounts ?? [],
        sites = sites ?? [],
        orgUnits = orgUnits ?? {},
        workOrders = workOrders ?? {},
        assigneeCandidates = assigneeCandidates ?? [],
        employees = employees ?? [],
        employeeDetails = employeeDetails ?? {},
        jobRoles = jobRoles ?? [];

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

  /// The caller's own Account id, as `/me` reports it — what the Accounts
  /// Screen compares each row against (issue #53).
  final String selfId;
  List<Map<String, dynamic>> queue;
  int queueStatus;
  int rejectStatus;
  int approveStatus;
  String approveMessage;

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

  /// `GET /api/people/sites`.
  List<Map<String, dynamic>> sites;
  int sitesStatus;

  /// `GET /api/people/sites/:id/org-units`, keyed by the `parentId` asked for
  /// — the null key is the root level, which is a different request, not a
  /// different filter over the same one.
  Map<String?, List<Map<String, dynamic>>> orgUnits;
  int orgUnitsStatus;

  /// Every Org Unit request as `(siteId, parentId)`, so a test can prove
  /// children were asked for by parent and only on expansion.
  final List<(String, String?)> orgUnitRequests = [];

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
  /// honestly; `orgUnitId` and `jobRoleId` are recorded on
  /// [employeeRequests] but not applied — the real `listEmployees` filters by
  /// a current Assignment this Fake Wire has no equivalent row for (Employee
  /// rows carry no Org Unit or job role at all — see `Employee`'s own
  /// header), so a test proves those two filters by asserting what was SENT,
  /// not by asserting the list narrowed.
  List<Map<String, dynamic>> employees;
  int employeesStatus;

  /// Every `GET /api/people/employees` request's query parameters, in the
  /// order they reached the wire.
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

  http.Client get client => MockClient((request) async {
        final path = request.url.path;
        requests.add('${request.method} $path');
        if (path == '/api/people/me') {
          return http.Response(jsonEncode(_meBody(role, selfId, orgUnitScope)), 200);
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
        if (path == '/api/people/employees/assignee-candidates') {
          if (assigneeCandidatesStatus != 200) {
            return http.Response(
              jsonEncode({'message': 'The candidates are unavailable.'}),
              assigneeCandidatesStatus,
            );
          }
          return http.Response(jsonEncode({'candidates': assigneeCandidates}), 200);
        }
        if (path == '/api/people/employees') {
          final search = request.url.queryParameters['search'];
          final orgUnitId = request.url.queryParameters['orgUnitId'];
          final jobRoleId = request.url.queryParameters['jobRoleId'];
          final includeDeparted = request.url.queryParameters['includeDeparted'] == 'true';
          employeeRequests.add({
            'search': search,
            'orgUnitId': orgUnitId,
            'jobRoleId': jobRoleId,
            'includeDeparted': includeDeparted.toString(),
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
        if (path == '/api/people/job-roles') {
          if (jobRolesStatus != 200) {
            return http.Response(jsonEncode({'message': 'Job roles are unavailable.'}), jobRolesStatus);
          }
          return http.Response(jsonEncode({'jobRoles': jobRoles}), 200);
        }
        if (path == '/api/people/sites') {
          if (sitesStatus != 200) {
            return http.Response(jsonEncode({'message': 'Sites are unavailable.'}), sitesStatus);
          }
          return http.Response(jsonEncode({'sites': sites}), 200);
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
            return http.Response(jsonEncode({'message': approveMessage}), approveStatus);
          }
          final id = path.split('/')[4];
          queue = [for (final a in queue) if (a['id'] != id) a];
          final sent = approvals.last;
          accounts = [
            for (final a in accounts)
              if (a['id'] == id)
                {
                  ...a,
                  'role': sent['role'],
                  'isActive': true,
                  'approvalStatus': 'approved',
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
