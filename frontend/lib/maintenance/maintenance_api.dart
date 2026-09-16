/// The Maintenance Module's HTTP surface, from the Flutter app's side.
///
/// Its own class next to its own Module, rather than a second `lib/*_api.dart`
/// at the root: `people_api.dart` sits there for historical reasons (it
/// predates `lib/people/`), and copying that is not the shape ADR-0012 asks
/// for. Nothing here reads a People endpoint — the Asset Screen still needs
/// `PeopleApi.fetchSites` and the tree, and it calls that directly.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'asset.dart';
import 'downtime_event.dart';
import 'floor_info.dart';
import 'job_plan.dart';
import 'meter.dart';
import 'part.dart';
import 'pm_schedule.dart';
import 'request.dart';
import 'stock_level.dart';
import 'store.dart';
import 'tier_board.dart';
import 'work_order.dart';

/// The request could not be answered at all. Deliberately its own type rather
/// than People's `PeopleApiException`: ADR-0006's third clause keeps generic
/// plumbing on each Module's own side, and the client mirrors it.
class MaintenanceApiException implements Exception {
  MaintenanceApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class MaintenanceApi {
  MaintenanceApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Every Asset at a Site — active only, unless [includeRetired] asks for
  /// the retired ones too (issue #61). The API reads Site-wide whatever the
  /// caller's Grants, so nothing is filtered here either.
  Future<List<Asset>> fetchAssets(
    String accessToken, {
    required String siteId,
    bool includeRetired = false,
  }) async {
    final path = '/api/maintenance/sites/$siteId/assets';
    final uri = includeRetired
        ? Uri.parse(path).replace(queryParameters: {'includeRetired': 'true'})
        : Uri.parse(path);
    final response = await _send(
      () => _client.get(uri, headers: {'authorization': 'Bearer $accessToken'}),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return [
        for (final asset in body['assets'] as List<dynamic>) _assetFrom(asset as Map<String, dynamic>),
      ];
    } catch (error) {
      throw MaintenanceApiException('The API answered with something this app could not read: $error');
    }
  }

  /// Places a new Asset in the tree. [orgUnitId] is the whole of "where this
  /// machine is": the server derives the Site from it, and issue #57's work
  /// orders will derive their own Org Unit from the Asset in turn.
  Future<Asset> createAsset(
    String accessToken, {
    required String orgUnitId,
    required String code,
    required String name,
    required String assetType,
    required String criticality,
  }) async {
    const path = '/api/maintenance/assets';
    final response = await _send(
      () => _client.post(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode({
          'orgUnitId': orgUnitId,
          'code': code,
          'name': name,
          'assetType': assetType,
          'criticality': criticality,
        }),
      ),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return _assetFrom(body['asset'] as Map<String, dynamic>);
    } catch (error) {
      throw MaintenanceApiException('The API answered with something this app could not read: $error');
    }
  }

  /// Retires or reinstates one Asset (`PATCH /api/maintenance/assets/:id`).
  /// Not a deletion: retiring only excludes the row from the default read,
  /// and the server itself refuses to retire one still carrying active parts
  /// (409) — this call just reports whatever it decides.
  Future<Asset> setAssetActive(String accessToken, String id, {required bool isActive}) =>
      _patchAsset(accessToken, id, {'isActive': isActive});

  /// Nests one Asset beneath another, or detaches it back to top-level when
  /// [parentId] is null. The server independently refuses a self-parent or a
  /// cycle (400) — this call is not the guard against either.
  Future<Asset> setAssetParent(String accessToken, String id, {required String? parentId}) =>
      _patchAsset(accessToken, id, {'parentId': parentId});

  /// Changes where one Asset sits (issue #171) — the placement that decides
  /// who may work on it. The server independently requires a write Grant
  /// reaching BOTH the Org Unit the Asset is leaving and the one it is going
  /// to (403), and refuses a malformed or unknown destination (400/404); this
  /// call just reports whatever it decides, and the row it answers with
  /// carries the new Org Unit's own name.
  Future<Asset> setAssetOrgUnit(String accessToken, String id, {required String orgUnitId}) =>
      _patchAsset(accessToken, id, {'orgUnitId': orgUnitId});

  /// Corrects an Asset's own four fields (issue #173) — a full replacement
  /// of code, name, assetType and criticality, validated server-side by the
  /// create route's own rules. The Asset's placement, its parent and
  /// whether it is retired are untouched: each has its own call above, and a
  /// body naming any of them alongside these four is refused (400).
  Future<Asset> correctAsset(
    String accessToken,
    String id, {
    required String code,
    required String name,
    required String assetType,
    required String criticality,
  }) =>
      _patchAsset(accessToken, id, {
        'code': code,
        'name': name,
        'assetType': assetType,
        'criticality': criticality,
      });

  Future<Asset> _patchAsset(String accessToken, String id, Map<String, dynamic> body) async {
    final path = '/api/maintenance/assets/$id';
    final response = await _send(
      () => _client.patch(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode(body),
      ),
      path,
    );
    try {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      return _assetFrom(decoded['asset'] as Map<String, dynamic>);
    } catch (error) {
      throw MaintenanceApiException('The API answered with something this app could not read: $error');
    }
  }

  /// The open Work orders across a whole Site (issue #57), or open-plus-
  /// history when [includeHistory] asks for it (issue #63) — the server
  /// excludes completed/cancelled from the default read, and `closed` stays
  /// unoffered either way. [orgUnitId] narrows to that Org Unit and
  /// everything beneath it; an unknown one is a 404, surfaced through
  /// [_send] like any other refusal.
  Future<List<WorkOrder>> fetchWorkOrders(
    String accessToken, {
    required String siteId,
    String? orgUnitId,
    bool includeHistory = false,
  }) async {
    final path = '/api/maintenance/sites/$siteId/work-orders';
    final queryParameters = {
      'orgUnitId': ?orgUnitId,
      if (includeHistory) 'includeHistory': 'true',
    };
    final uri = queryParameters.isEmpty
        ? Uri.parse(path)
        : Uri.parse(path).replace(queryParameters: queryParameters);
    final response = await _send(
      () => _client.get(uri, headers: {'authorization': 'Bearer $accessToken'}),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return [
        for (final workOrder in body['workOrders'] as List<dynamic>)
          _workOrderFrom(workOrder as Map<String, dynamic>),
      ];
    } catch (error) {
      throw MaintenanceApiException('The API answered with something this app could not read: $error');
    }
  }

  /// Raises a new Work order against [assetId]. Deliberately no `orgUnitId`
  /// and no Work order number in this call: the server derives the former
  /// from the Asset and issues the latter from the Site's own sequence, so
  /// the client sends neither.
  Future<WorkOrder> createWorkOrder(
    String accessToken, {
    required String assetId,
    required String summary,
    required String workType,
    required int priority,
    String? description,
  }) async {
    const path = '/api/maintenance/work-orders';
    final response = await _send(
      () => _client.post(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode({
          'assetId': assetId,
          'summary': summary,
          'workType': workType,
          'priority': priority,
          'description': ?description,
        }),
      ),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return _workOrderFrom(body['workOrder'] as Map<String, dynamic>);
    } catch (error) {
      throw MaintenanceApiException('The API answered with something this app could not read: $error');
    }
  }

  /// Gives a Work order to an Employee, or moves it to a different one
  /// (`PUT /api/maintenance/work-orders/:id/assignee`). One call for both:
  /// assigning and reassigning are the same idempotent replacement of a
  /// single value (AC1, AC5). The server refuses a Departed Employee (409)
  /// and a caller with no write Grant reaching the Work order's Org Unit
  /// (403) — this call reports whatever it decides, and no qualification is
  /// consulted anywhere on this path (AC4).
  Future<WorkOrder> assignWorkOrder(
    String accessToken,
    String id, {
    required String employeeId,
  }) async {
    final path = '/api/maintenance/work-orders/$id/assignee';
    final response = await _send(
      () => _client.put(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode({'employeeId': employeeId}),
      ),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return _workOrderFrom(body['workOrder'] as Map<String, dynamic>);
    } catch (error) {
      throw MaintenanceApiException('The API answered with something this app could not read: $error');
    }
  }

  /// Starts a Work order: moves it to `in_progress` and stamps when work
  /// began (`POST /api/maintenance/work-orders/:id/start`, issue #63). No
  /// body — starting asks for nothing and takes nothing.
  Future<WorkOrder> startWorkOrder(String accessToken, String id) =>
      _postWorkOrderAction(accessToken, id, 'start', const {});

  /// Completes a Work order: stamps when it ended and records [note], what
  /// was found (`POST /api/maintenance/work-orders/:id/complete`). The
  /// server refuses one that was never started (409) before writing anything.
  Future<WorkOrder> completeWorkOrder(String accessToken, String id, {required String note}) =>
      _postWorkOrderAction(accessToken, id, 'complete', {'note': note});

  /// Cancels a Work order raised in error
  /// (`POST /api/maintenance/work-orders/:id/cancel`). [reason] is optional —
  /// undoing a mistake should not demand prose to explain it.
  Future<WorkOrder> cancelWorkOrder(String accessToken, String id, {String? reason}) =>
      _postWorkOrderAction(accessToken, id, 'cancel', {'reason': ?reason});

  Future<WorkOrder> _postWorkOrderAction(
    String accessToken,
    String id,
    String action,
    Map<String, dynamic> body,
  ) async {
    final path = '/api/maintenance/work-orders/$id/$action';
    final response = await _send(
      () => _client.post(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode(body),
      ),
      path,
    );
    try {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      return _workOrderFrom(decoded['workOrder'] as Map<String, dynamic>);
    } catch (error) {
      throw MaintenanceApiException('The API answered with something this app could not read: $error');
    }
  }

  /// Raises a new Request against [assetId] (issue #72). Deliberately no
  /// `orgUnitId` and no Request number in this call: the server derives the
  /// former from the Asset by trigger and issues the latter from the Site's
  /// own sequence, so the client sends neither. `productionStopped` is a JSON
  /// boolean, and [urgency] is the reporter's judgement — never the Work
  /// order's `priority`, which acceptance sets separately.
  Future<Request> raiseRequest(
    String accessToken, {
    required String assetId,
    required String summary,
    String? description,
    required String urgency,
    required bool productionStopped,
  }) async {
    const path = '/api/maintenance/requests';
    final response = await _send(
      () => _client.post(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode({
          'assetId': assetId,
          'summary': summary,
          'urgency': urgency,
          'productionStopped': productionStopped,
          'description': ?description,
        }),
      ),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return _requestFrom(body['request'] as Map<String, dynamic>);
    } catch (error) {
      throw MaintenanceApiException('The API answered with something this app could not read: $error');
    }
  }

  /// The triage queue: every Request still awaiting a decision at a Site
  /// (`GET /api/maintenance/sites/:siteId/requests`). Site-wide and carrying
  /// no Grant filter (ADR-0009).
  Future<List<Request>> fetchTriageRequests(
    String accessToken, {
    required String siteId,
  }) async {
    final path = '/api/maintenance/sites/$siteId/requests';
    final response = await _send(
      () => _client.get(Uri.parse(path), headers: {'authorization': 'Bearer $accessToken'}),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return [
        for (final request in body['requests'] as List<dynamic>)
          _requestFrom(request as Map<String, dynamic>),
      ];
    } catch (error) {
      throw MaintenanceApiException('The API answered with something this app could not read: $error');
    }
  }

  /// The caller's own Requests at a Site, every status
  /// (`GET /api/maintenance/sites/:siteId/requests/mine`) — what the person
  /// who raised one follows to see what became of it (ADR-0014).
  Future<List<Request>> fetchMyRequests(
    String accessToken, {
    required String siteId,
  }) async {
    final path = '/api/maintenance/sites/$siteId/requests/mine';
    final response = await _send(
      () => _client.get(Uri.parse(path), headers: {'authorization': 'Bearer $accessToken'}),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return [
        for (final request in body['requests'] as List<dynamic>)
          _requestFrom(request as Map<String, dynamic>),
      ];
    } catch (error) {
      throw MaintenanceApiException('The API answered with something this app could not read: $error');
    }
  }

  /// Accepts a Request: raises a Work order for it and moves the Request to
  /// `accepted` in one transaction (ADR-0014). [priority] is maintenance's own
  /// judgement, not the reporter's `urgency` — the caller chooses it on the
  /// accept dialog. The Work order is always `corrective`; the backend takes
  /// only `priority`.
  Future<Request> acceptRequest(
    String accessToken,
    String id, {
    required int priority,
  }) async {
    final path = '/api/maintenance/requests/$id/accept';
    final response = await _send(
      () => _client.post(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode({'priority': priority}),
      ),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return _requestFrom(body['request'] as Map<String, dynamic>);
    } catch (error) {
      throw MaintenanceApiException('The API answered with something this app could not read: $error');
    }
  }

  /// Declines a Request. [reason] is required — the database refuses a
  /// rejection without one (`maintenance_requests_rejected_has_reason`), and
  /// "why was my ask refused" is a fair question.
  Future<Request> declineRequest(
    String accessToken,
    String id, {
    required String reason,
  }) async {
    final path = '/api/maintenance/requests/$id/decline';
    final response = await _send(
      () => _client.post(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode({'reason': reason}),
      ),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return _requestFrom(body['request'] as Map<String, dynamic>);
    } catch (error) {
      throw MaintenanceApiException('The API answered with something this app could not read: $error');
    }
  }

  /// Marks a Request as a duplicate of [duplicateOfId], the Request that
  /// survives.
  Future<Request> markRequestDuplicate(
    String accessToken,
    String id, {
    required String duplicateOfId,
  }) async {
    final path = '/api/maintenance/requests/$id/duplicate';
    final response = await _send(
      () => _client.post(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode({'duplicateOfId': duplicateOfId}),
      ),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return _requestFrom(body['request'] as Map<String, dynamic>);
    } catch (error) {
      throw MaintenanceApiException('The API answered with something this app could not read: $error');
    }
  }

  /// The classify picker's own catalogue
  /// (`GET /api/maintenance/downtime-reasons`, issue #73) — every active
  /// Downtime reason, readable by any approved Account (ADR-0005's shared
  /// global catalogue).
  Future<List<DowntimeReason>> fetchDowntimeReasons(String accessToken) async {
    const path = '/api/maintenance/downtime-reasons';
    final response = await _send(
      () => _client.get(Uri.parse(path), headers: {'authorization': 'Bearer $accessToken'}),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return [
        for (final reason in body['downtimeReasons'] as List<dynamic>)
          _downtimeReasonFrom(reason as Map<String, dynamic>),
      ];
    } catch (error) {
      throw MaintenanceApiException('The API answered with something this app could not read: $error');
    }
  }

  /// The open Downtime events across a whole Site — "what is down right now" —
  /// or open-plus-history when [includeClosed] asks for it
  /// (`GET /api/maintenance/sites/:siteId/downtime`, issue #73). Site-wide and
  /// carrying no Grant filter (ADR-0009).
  Future<List<DowntimeEvent>> fetchDowntimeEvents(
    String accessToken, {
    required String siteId,
    bool includeClosed = false,
  }) async {
    final path = '/api/maintenance/sites/$siteId/downtime';
    final uri = includeClosed
        ? Uri.parse(path).replace(queryParameters: {'includeClosed': 'true'})
        : Uri.parse(path);
    final response = await _send(
      () => _client.get(uri, headers: {'authorization': 'Bearer $accessToken'}),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return [
        for (final event in body['downtimeEvents'] as List<dynamic>)
          _downtimeEventFrom(event as Map<String, dynamic>),
      ];
    } catch (error) {
      throw MaintenanceApiException('The API answered with something this app could not read: $error');
    }
  }

  /// Reports a Breakdown against [assetId] (`POST /api/maintenance/downtime`,
  /// issue #73). Deliberately no `orgUnitId` and no Work order number in this
  /// call: the server derives the former from the Asset by trigger and issues
  /// the latter from the Site's own sequence. A duplicate report of an Asset
  /// already recorded as down is a 409 whose message names the Asset and since
  /// when — carried verbatim on [MaintenanceApiException.message] so the
  /// dialog can stay open and show it.
  Future<DowntimeEvent> reportBreakdown(
    String accessToken, {
    required String assetId,
    DateTime? startedAt,
    String? description,
  }) async {
    const path = '/api/maintenance/downtime';
    final response = await _send(
      () => _client.post(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode({
          'assetId': assetId,
          'startedAt': ?_timestamp(startedAt),
          'description': ?description,
        }),
      ),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return _downtimeEventFrom(body['downtimeEvent'] as Map<String, dynamic>);
    } catch (error) {
      throw MaintenanceApiException('The API answered with something this app could not read: $error');
    }
  }

  /// Closes a still-open Downtime event (`POST /api/maintenance/downtime/:id/close`,
  /// issue #73). [endedAt] is optional — omitted means now, the honest default
  /// when a caller closes a stop as it ends. The server owns the resulting
  /// duration and status; nothing here computes either.
  Future<DowntimeEvent> closeDowntimeEvent(
    String accessToken,
    String id, {
    DateTime? endedAt,
  }) async {
    final path = '/api/maintenance/downtime/$id/close';
    final response = await _send(
      () => _client.post(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode({'endedAt': ?_timestamp(endedAt)}),
      ),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return _downtimeEventFrom(body['downtimeEvent'] as Map<String, dynamic>);
    } catch (error) {
      throw MaintenanceApiException('The API answered with something this app could not read: $error');
    }
  }

  /// Classifies a Downtime event against [downtimeReasonId]
  /// (`POST /api/maintenance/downtime/:id/classify`, issue #73). A reason whose
  /// `requiresComment` is true is refused by the server (400) when no
  /// [description] is given — the classify dialog blocks that before the call.
  Future<DowntimeEvent> classifyDowntimeEvent(
    String accessToken,
    String id, {
    required String downtimeReasonId,
    String? description,
  }) async {
    final path = '/api/maintenance/downtime/$id/classify';
    final response = await _send(
      () => _client.post(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode({
          'downtimeReasonId': downtimeReasonId,
          'description': ?description,
        }),
      ),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return _downtimeEventFrom(body['downtimeEvent'] as Map<String, dynamic>);
    } catch (error) {
      throw MaintenanceApiException('The API answered with something this app could not read: $error');
    }
  }

  /// The Job plan catalogue (`GET /api/maintenance/job-plans`, issue #74) —
  /// the shared, administrator-managed description of each recurring job,
  /// each carrying its ordered tasks with the required Skill's name already
  /// resolved by the server's own join. Every plan is read by default
  /// [includeInactive], so the catalogue can reach a deactivated plan worth
  /// reactivating; `includeInactive: false` narrows to active ones, the same
  /// shape [fetchSkills] already follows.
  Future<List<JobPlan>> fetchJobPlans(String accessToken, {bool includeInactive = true}) async {
    const path = '/api/maintenance/job-plans';
    final uri = includeInactive
        ? Uri.parse(path)
        : Uri.parse(path).replace(queryParameters: {'includeInactive': 'false'});
    final response = await _send(
      () => _client.get(uri, headers: {'authorization': 'Bearer $accessToken'}),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return [
        for (final plan in body['jobPlans'] as List<dynamic>)
          _jobPlanFrom(plan as Map<String, dynamic>),
      ];
    } catch (error) {
      throw MaintenanceApiException('The API answered with something this app could not read: $error');
    }
  }

  /// Creates a Job plan and its tasks in one request (`POST
  /// /api/maintenance/job-plans`, administrator only, issue #74). [workType]
  /// is one of `jobPlanWorkTypes`; each task's `skillId` is optional, and a
  /// task that names none is sent without the key.
  Future<JobPlan> createJobPlan(
    String accessToken, {
    required String code,
    required String name,
    String? description,
    required String workType,
    num? estimatedHours,
    bool? requiresShutdown,
    String? safetyNote,
    required List<JobPlanTaskDraft> tasks,
  }) async {
    const path = '/api/maintenance/job-plans';
    final response = await _send(
      () => _client.post(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode({
          'code': code,
          'name': name,
          'workType': workType,
          'description': ?description,
          'estimatedHours': ?estimatedHours,
          'requiresShutdown': ?requiresShutdown,
          'safetyNote': ?safetyNote,
          'tasks': [
            for (final task in tasks)
              {
                'stepNo': task.stepNo,
                'instruction': task.instruction,
                'skillId': ?task.skillId,
                'estimatedHours': ?task.estimatedHours,
              },
          ],
        }),
      ),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return _jobPlanFrom(body['jobPlan'] as Map<String, dynamic>);
    } catch (error) {
      throw MaintenanceApiException('The API answered with something this app could not read: $error');
    }
  }

  /// Deactivates or reactivates a Job plan (`PATCH
  /// /api/maintenance/job-plans/:id`, administrator only, issue #74).
  /// Deactivation is never deletion — the plan stays readable, and a Work
  /// order already copied from it keeps its tasks.
  Future<JobPlan> setJobPlanActive(String accessToken, String id, {required bool isActive}) async {
    final path = '/api/maintenance/job-plans/$id';
    final response = await _send(
      () => _client.patch(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode({'isActive': isActive}),
      ),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return _jobPlanFrom(body['jobPlan'] as Map<String, dynamic>);
    } catch (error) {
      throw MaintenanceApiException('The API answered with something this app could not read: $error');
    }
  }

  /// The PM schedules at a Site (`GET
  /// /api/maintenance/sites/:siteId/pm-schedules`, issue #74) — active ones
  /// by default, inactive ones too when [includeInactive] asks for them by
  /// name. Site-wide and carrying no Grant filter (ADR-0009).
  Future<List<PmSchedule>> fetchPmSchedules(
    String accessToken, {
    required String siteId,
    bool includeInactive = false,
  }) async {
    final path = '/api/maintenance/sites/$siteId/pm-schedules';
    final uri = includeInactive
        ? Uri.parse(path).replace(queryParameters: {'includeInactive': 'true'})
        : Uri.parse(path);
    final response = await _send(
      () => _client.get(uri, headers: {'authorization': 'Bearer $accessToken'}),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return [
        for (final schedule in body['pmSchedules'] as List<dynamic>)
          _pmScheduleFrom(schedule as Map<String, dynamic>),
      ];
    } catch (error) {
      throw MaintenanceApiException('The API answered with something this app could not read: $error');
    }
  }

  /// Attaches a Job plan to an Asset as a PM schedule (`POST
  /// /api/maintenance/pm-schedules`, issue #74). No `orgUnitId` and no code:
  /// the server derives the former from the Asset and issues the latter from
  /// the Site's own sequence. The interval is one of two mechanisms (issue
  /// #79): [intervalDays] for elapsed time, or [assetMeterId] plus
  /// [intervalMeter] for accumulated use. Exactly one must be given; the
  /// server refuses neither or both. [nextDueOn] is a `YYYY-MM-DD` date and
  /// applies only to the calendar mechanism.
  Future<PmSchedule> createPmSchedule(
    String accessToken, {
    required String assetId,
    required String jobPlanId,
    required String anchor,
    int? intervalDays,
    String? assetMeterId,
    num? intervalMeter,
    int? leadTimeDays,
    int? priority,
    String? nextDueOn,
  }) async {
    const path = '/api/maintenance/pm-schedules';
    final response = await _send(
      () => _client.post(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode({
          'assetId': assetId,
          'jobPlanId': jobPlanId,
          'intervalDays': ?intervalDays,
          'assetMeterId': ?assetMeterId,
          'intervalMeter': ?intervalMeter,
          'anchor': anchor,
          'leadTimeDays': ?leadTimeDays,
          'priority': ?priority,
          'nextDueOn': ?nextDueOn,
        }),
      ),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return _pmScheduleFrom(body['pmSchedule'] as Map<String, dynamic>);
    } catch (error) {
      throw MaintenanceApiException('The API answered with something this app could not read: $error');
    }
  }

  /// Deactivates or reactivates a PM schedule (`PATCH
  /// /api/maintenance/pm-schedules/:id`, issue #74). A schedule switched off
  /// stops raising Work orders but stays readable.
  Future<PmSchedule> setPmScheduleActive(String accessToken, String id, {required bool isActive}) async {
    final path = '/api/maintenance/pm-schedules/$id';
    final response = await _send(
      () => _client.patch(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode({'isActive': isActive}),
      ),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return _pmScheduleFrom(body['pmSchedule'] as Map<String, dynamic>);
    } catch (error) {
      throw MaintenanceApiException('The API answered with something this app could not read: $error');
    }
  }

  /// The meters at a Site (`GET /api/maintenance/sites/:siteId/meters`, issue
  /// #79) — active ones by default, retired ones too when [includeInactive]
  /// asks for them by name. [assetId] narrows to one Asset's meters, which is
  /// what the PM schedule form reads. Site-wide and carrying no Grant filter
  /// (ADR-0009).
  Future<List<AssetMeter>> fetchMeters(
    String accessToken, {
    required String siteId,
    String? assetId,
    bool includeInactive = false,
  }) async {
    final path = '/api/maintenance/sites/$siteId/meters';
    final queryParameters = {
      'assetId': ?assetId,
      if (includeInactive) 'includeInactive': 'true',
    };
    final uri = queryParameters.isEmpty
        ? Uri.parse(path)
        : Uri.parse(path).replace(queryParameters: queryParameters);
    final response = await _send(
      () => _client.get(uri, headers: {'authorization': 'Bearer $accessToken'}),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return [
        for (final meter in body['meters'] as List<dynamic>)
          _meterFrom(meter as Map<String, dynamic>),
      ];
    } catch (error) {
      throw MaintenanceApiException('The API answered with something this app could not read: $error');
    }
  }

  /// The unit-of-measure catalogue the meter form (issue #79) and the Part
  /// form (issue #80) both choose from (`GET
  /// /api/maintenance/units-of-measure`) — the baseline reference table, so a
  /// unit is chosen rather than typed (ADR-0023).
  Future<List<UnitOfMeasure>> fetchUnitsOfMeasure(String accessToken) async {
    const path = '/api/maintenance/units-of-measure';
    final response = await _send(
      () => _client.get(Uri.parse(path), headers: {'authorization': 'Bearer $accessToken'}),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return [
        for (final unit in body['unitsOfMeasure'] as List<dynamic>)
          _unitOfMeasureFrom(unit as Map<String, dynamic>),
      ];
    } catch (error) {
      throw MaintenanceApiException('The API answered with something this app could not read: $error');
    }
  }

  /// Defines a meter on an Asset (`POST /api/maintenance/meters`, issue #79).
  /// A write Grant reaching the Asset's Org Unit is required (403).
  Future<AssetMeter> createMeter(
    String accessToken, {
    required String assetId,
    required String code,
    required String name,
    required String uomCode,
    required String meterType,
  }) async {
    const path = '/api/maintenance/meters';
    final response = await _send(
      () => _client.post(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode({
          'assetId': assetId,
          'code': code,
          'name': name,
          'uomCode': uomCode,
          'meterType': meterType,
        }),
      ),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return _meterFrom(body['meter'] as Map<String, dynamic>);
    } catch (error) {
      throw MaintenanceApiException('The API answered with something this app could not read: $error');
    }
  }

  /// Records a manual reading against a meter (`POST
  /// /api/maintenance/meters/:id/readings`, issue #79). A backwards reading on
  /// a cumulative meter is refused by the server with a named code; this call
  /// reports whatever it decides. Returns the meter as it now stands, so the
  /// caller can show the new accumulated use without a second read.
  Future<AssetMeter> recordMeterReading(
    String accessToken,
    String meterId, {
    required num reading,
    String? note,
    DateTime? readAt,
  }) async {
    final path = '/api/maintenance/meters/$meterId/readings';
    final response = await _send(
      () => _client.post(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode({
          'reading': reading,
          'note': ?note,
          'readAt': ?_timestamp(readAt),
        }),
      ),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return _meterFrom(body['meter'] as Map<String, dynamic>);
    } catch (error) {
      throw MaintenanceApiException('The API answered with something this app could not read: $error');
    }
  }

  /// Records an explicit rollover or replacement (`POST
  /// /api/maintenance/meters/:id/rollover`, issue #79). [reading] is the new
  /// counter's own starting value and defaults to zero server-side (ADR-0029).
  Future<AssetMeter> rolloverMeter(
    String accessToken,
    String meterId, {
    num? reading,
    String? note,
    DateTime? readAt,
  }) async {
    final path = '/api/maintenance/meters/$meterId/rollover';
    final response = await _send(
      () => _client.post(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode({
          'reading': ?reading,
          'note': ?note,
          'readAt': ?_timestamp(readAt),
        }),
      ),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return _meterFrom(body['meter'] as Map<String, dynamic>);
    } catch (error) {
      throw MaintenanceApiException('The API answered with something this app could not read: $error');
    }
  }

  /// One Work order with the tasks copied from the Job plan that raised it
  /// (`GET /api/maintenance/work-orders/:id`, issue #74) — the detail read the
  /// Site-wide list deliberately leaves tasks off (it would be an N+1). A
  /// malformed or unknown id is surfaced through [_send] like any other
  /// refusal.
  Future<WorkOrder> fetchWorkOrder(String accessToken, String id) async {
    final path = '/api/maintenance/work-orders/$id';
    final response = await _send(
      () => _client.get(Uri.parse(path), headers: {'authorization': 'Bearer $accessToken'}),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return _workOrderFrom(body['workOrder'] as Map<String, dynamic>);
    } catch (error) {
      throw MaintenanceApiException('The API answered with something this app could not read: $error');
    }
  }

  /// Records a reading while working a Work order task that names a meter
  /// (`POST /api/maintenance/work-orders/:id/tasks/:taskId/reading`, issue
  /// #79). The server records the reading against the meter — applying the
  /// cumulative backward check — and stamps the value onto the copied task.
  /// Returns the updated task; the caller re-reads the Work order for the
  /// meter's own accumulated use.
  Future<WorkOrderTask> recordTaskReading(
    String accessToken,
    String workOrderId,
    String taskId, {
    required num reading,
    String? note,
    DateTime? readAt,
  }) async {
    final path = '/api/maintenance/work-orders/$workOrderId/tasks/$taskId/reading';
    final response = await _send(
      () => _client.post(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode({
          'reading': reading,
          'note': ?note,
          'readAt': ?_timestamp(readAt),
        }),
      ),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return _workOrderTaskFrom(body['task'] as Map<String, dynamic>);
    } catch (error) {
      throw MaintenanceApiException('The API answered with something this app could not read: $error');
    }
  }

  /// Books an Employee's window of time against a Work order
  /// (`POST /api/maintenance/work-orders/:id/labour`, issue #75). The window
  /// is the only input that decides the hours — `hours` is never sent, because
  /// the server's own column is generated from `startedAt`/`endedAt` and a
  /// client-sent figure is ignored. [startedAt]/[endedAt] cross the wire as
  /// UTC instants; [activity] is one of `LabourActivity`'s wires. A write
  /// Grant reaching the Work order's Asset's Org Unit is required (403).
  /// Nothing is returned: the caller re-reads the Work order, whose own detail
  /// read now carries the updated cost.
  Future<void> bookLabour(
    String accessToken,
    String workOrderId, {
    required String employeeId,
    required DateTime startedAt,
    required DateTime endedAt,
    required String activity,
    bool isOvertime = false,
    String? note,
  }) async {
    final path = '/api/maintenance/work-orders/$workOrderId/labour';
    await _send(
      () => _client.post(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode({
          'employeeId': employeeId,
          'startedAt': startedAt.toUtc().toIso8601String(),
          'endedAt': endedAt.toUtc().toIso8601String(),
          'activity': activity,
          'isOvertime': isOvertime,
          'note': ?note,
        }),
      ),
      path,
    );
  }

  /// Books a part against a Work order
  /// (`POST /api/maintenance/work-orders/:id/parts`, issue #75). `sourced`
  /// decides which fields apply: a `stores` booking names the catalogue
  /// [partId] and the [storeId] it came from and decrements that shelf; a
  /// `purchased`, `refurbished` or `cannibalised` booking names its own
  /// [partNo] (free text, may be null), [description] and [uomCode] and
  /// touches no stock. Nothing is returned: the caller re-reads the Work
  /// order for the updated cost, the same as [bookLabour].
  Future<void> bookWorkOrderPart(
    String accessToken,
    String workOrderId, {
    required String sourced,
    required num quantity,
    String? partId,
    String? storeId,
    String? partNo,
    String? description,
    String? uomCode,
    num? unitCost,
  }) async {
    final path = '/api/maintenance/work-orders/$workOrderId/parts';
    await _send(
      () => _client.post(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode({
          'sourced': sourced,
          'quantity': quantity,
          'partId': ?partId,
          'storeId': ?storeId,
          'partNo': ?partNo,
          'description': ?description,
          'uomCode': ?uomCode,
          'unitCost': ?unitCost,
        }),
      ),
      path,
    );
  }

  /// The tier board (`GET /api/maintenance/sites/:siteId/board`, issue #76):
  /// the KPIs under all five Pillars for a Site, optionally narrowed to an Org
  /// Unit and everything beneath it, over one period. [periodType] is required
  /// by the server (`shift`/`day`/`week`/`month`); [date] is a `YYYY-MM-DD`
  /// production day the server resolves to the period containing it, and is
  /// omitted to let the Site's own shift calendar decide which production day
  /// "today" falls in. A `shift` period additionally needs [shiftInstanceId]
  /// — the model and this call carry it, though no picker offers it yet. The
  /// read is Site-wide and carries no Grant filter (ADR-0009).
  Future<TierBoard> fetchBoard(
    String accessToken, {
    required String siteId,
    required String periodType,
    String? orgUnitId,
    String? date,
    String? shiftInstanceId,
  }) async {
    final path = '/api/maintenance/sites/$siteId/board';
    final queryParameters = {
      'periodType': periodType,
      'orgUnitId': ?orgUnitId,
      'date': ?date,
      'shiftInstanceId': ?shiftInstanceId,
    };
    final uri = Uri.parse(path).replace(queryParameters: queryParameters);
    final response = await _send(
      () => _client.get(uri, headers: {'authorization': 'Bearer $accessToken'}),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return _tierBoardFrom(body);
    } catch (error) {
      throw MaintenanceApiException('The API answered with something this app could not read: $error');
    }
  }

  /// The shared parts catalogue (`GET /api/maintenance/parts`, issue #80) —
  /// active parts by default, retired ones too when [includeInactive] asks for
  /// them by name. Readable by any approved Account (ADR-0005's shared
  /// catalogue).
  Future<List<Part>> fetchParts(String accessToken, {bool includeInactive = false}) async {
    const path = '/api/maintenance/parts';
    final uri = includeInactive
        ? Uri.parse(path).replace(queryParameters: {'includeInactive': 'true'})
        : Uri.parse(path);
    final response = await _send(
      () => _client.get(uri, headers: {'authorization': 'Bearer $accessToken'}),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return [
        for (final part in body['parts'] as List<dynamic>) _partFrom(part as Map<String, dynamic>),
      ];
    } catch (error) {
      throw MaintenanceApiException('The API answered with something this app could not read: $error');
    }
  }

  /// Defines a Part in the shared catalogue (`POST /api/maintenance/parts`,
  /// administrator only, issue #80). [uomCode] is one of the codes
  /// [fetchUnitsOfMeasure] lists.
  Future<Part> createPart(
    String accessToken, {
    required String partNo,
    required String description,
    required String uomCode,
  }) async {
    const path = '/api/maintenance/parts';
    final response = await _send(
      () => _client.post(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode({'partNo': partNo, 'description': description, 'uomCode': uomCode}),
      ),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return _partFrom(body['part'] as Map<String, dynamic>);
    } catch (error) {
      throw MaintenanceApiException('The API answered with something this app could not read: $error');
    }
  }

  /// The stores at a Site (`GET /api/maintenance/sites/:siteId/stores`, issue
  /// #80) — active ones by default. Site-wide and carrying no Grant filter
  /// (ADR-0009).
  Future<List<Store>> fetchStores(
    String accessToken, {
    required String siteId,
    bool includeInactive = false,
  }) async {
    final path = '/api/maintenance/sites/$siteId/stores';
    final uri = includeInactive
        ? Uri.parse(path).replace(queryParameters: {'includeInactive': 'true'})
        : Uri.parse(path);
    final response = await _send(
      () => _client.get(uri, headers: {'authorization': 'Bearer $accessToken'}),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return [
        for (final store in body['stores'] as List<dynamic>) _storeFrom(store as Map<String, dynamic>),
      ];
    } catch (error) {
      throw MaintenanceApiException('The API answered with something this app could not read: $error');
    }
  }

  /// One store and the stock it holds (`GET
  /// /api/maintenance/stores/:storeId/stock`, issue #80). The read carries no
  /// Grant filter (ADR-0009); the level is the sum of the store's movements,
  /// derived server-side.
  Future<(Store, List<StockLevel>)> fetchStoreStock(String accessToken, String storeId) async {
    final path = '/api/maintenance/stores/$storeId/stock';
    final response = await _send(
      () => _client.get(Uri.parse(path), headers: {'authorization': 'Bearer $accessToken'}),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return (
        _storeFrom(body['store'] as Map<String, dynamic>),
        [
          for (final row in body['stock'] as List<dynamic>)
            _stockLevelFrom(row as Map<String, dynamic>),
        ],
      );
    } catch (error) {
      throw MaintenanceApiException('The API answered with something this app could not read: $error');
    }
  }

  /// Receives [quantity] of a Part into a store (`POST
  /// /api/maintenance/stores/:storeId/receipts`, issue #80). A write Grant
  /// reaching the store's Org Unit is required; the server refuses a movement
  /// that would take the shelf below zero (409) with a message naming the part
  /// and what is actually on the shelf. Returns the resulting level.
  Future<num> receiveStock(
    String accessToken,
    String storeId, {
    required String partId,
    required num quantity,
    String? reason,
    DateTime? occurredAt,
  }) async {
    final path = '/api/maintenance/stores/$storeId/receipts';
    final response = await _send(
      () => _client.post(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode({
          'partId': partId,
          'quantity': quantity,
          'reason': ?reason,
          'occurredAt': ?_timestamp(occurredAt),
        }),
      ),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return body['onHand'] as num;
    } catch (error) {
      throw MaintenanceApiException('The API answered with something this app could not read: $error');
    }
  }

  /// A local time the picker chose, as the UTC instant the wire carries —
  /// `timestamptz` on the server side. The server supplies now() when the
  /// field is left blank, so a caller sends nothing rather than a default.
  static String? _timestamp(DateTime? value) {
    if (value == null) return null;
    return value.toUtc().toIso8601String();
  }

  // The server sends a flat row — `id, workOrderNo, assetId, assetCode,
  // assetName, orgUnitId, orgUnitName, siteId, summary, description,
  // workType, priority, status, assignedTo, assigneeName, createdAt,
  // updatedAt` (`toWorkOrder`, work-orders.js) — no nested `asset`/`orgUnit`
  // map and no `assignee` string, so this reads the same flat keys
  // `_assetFrom` already does for the Asset register. The `cost` object
  // (issue #75) rides only the detail read.
  static WorkOrder _workOrderFrom(Map<String, dynamic> workOrder) => WorkOrder(
        id: workOrder['id'].toString(),
        workOrderNo: workOrder['workOrderNo'] as String,
        assetId: workOrder['assetId'].toString(),
        assetCode: workOrder['assetCode'] as String,
        assetName: workOrder['assetName'] as String,
        orgUnitId: workOrder['orgUnitId'].toString(),
        orgUnitName: workOrder['orgUnitName'] as String,
        siteId: workOrder['siteId'].toString(),
        summary: workOrder['summary'] as String,
        workType: workOrder['workType'] as String,
        priority: (workOrder['priority'] as num).toInt(),
        status: workOrder['status'] as String,
        assignedTo: workOrder['assignedTo']?.toString(),
        assigneeName: workOrder['assigneeName'] as String?,
        tasks: [
          for (final task in (workOrder['tasks'] as List<dynamic>? ?? const []))
            _workOrderTaskFrom(task as Map<String, dynamic>),
        ],
        cost: workOrder['cost'] == null
            ? null
            : _workOrderCostFrom(workOrder['cost'] as Map<String, dynamic>),
      );

  // `workOrderCost` (work-order-cost.js): `labourHours, overtimeHours,
  // labourByActivity, parts, partsCost`. Labour hours and the parts cost are
  // returned as two separate facts and never summed — see the backend's own
  // warning that booked labour is a slice of plant labour cost while parts
  // are new money.
  static WorkOrderCost _workOrderCostFrom(Map<String, dynamic> cost) => WorkOrderCost(
        labourHours: cost['labourHours'] as num? ?? 0,
        overtimeHours: cost['overtimeHours'] as num? ?? 0,
        labourByActivity: [
          for (final row in (cost['labourByActivity'] as List<dynamic>? ?? const []))
            WorkOrderLabourActivity(
              activity: (row as Map<String, dynamic>)['activity'] as String,
              hours: row['hours'] as num? ?? 0,
              overtimeHours: row['overtimeHours'] as num? ?? 0,
            ),
        ],
        parts: [
          for (final row in (cost['parts'] as List<dynamic>? ?? const []))
            _workOrderPartFrom(row as Map<String, dynamic>),
        ],
        partsCost: cost['partsCost'] as num?,
      );

  // `toBookedPart` (work-order-cost.js): `id, workOrderId, partNo,
  // description, quantity, uomCode, unitCost, currency, totalCost, sourced,
  // fittedAt`.
  static WorkOrderPartLine _workOrderPartFrom(Map<String, dynamic> part) => WorkOrderPartLine(
        id: part['id'].toString(),
        partNo: part['partNo'] as String?,
        description: part['description'] as String,
        quantity: part['quantity'] as num,
        uomCode: part['uomCode'] as String,
        unitCost: part['unitCost'] as num?,
        currency: part['currency'] as String? ?? 'USD',
        totalCost: part['totalCost'] as num?,
        sourced: part['sourced'] as String,
      );

  // `toWorkOrderTask` (work-orders.js): `id, stepNo, instruction, skillId,
  // skillName, status, note, reading, assetMeterId, meterCode, meterName` —
  // the fields a copied step carries, with the required Skill's name resolved
  // by the server's join and the meter the step records to, if any (issue
  // #79).
  static WorkOrderTask _workOrderTaskFrom(Map<String, dynamic> task) => WorkOrderTask(
        id: task['id'].toString(),
        stepNo: (task['stepNo'] as num).toInt(),
        instruction: task['instruction'] as String,
        skillId: task['skillId']?.toString(),
        skillName: task['skillName'] as String?,
        status: task['status'] as String? ?? 'pending',
        note: task['note'] as String?,
        reading: task['reading'] as num?,
        assetMeterId: task['assetMeterId']?.toString(),
        meterCode: task['meterCode'] as String?,
        meterName: task['meterName'] as String?,
      );

  // `toJobPlan` (job-plans.js) sends a flat row plus an ordered `tasks` list;
  // `toJobPlanTask` carries the required Skill's name from that file's own
  // join. A later field added to one side should prompt a look at the other.
  static JobPlan _jobPlanFrom(Map<String, dynamic> plan) => JobPlan(
        id: plan['id'].toString(),
        code: plan['code'] as String,
        name: plan['name'] as String,
        description: plan['description'] as String?,
        workType: plan['workType'] as String,
        estimatedHours: plan['estimatedHours'] as num?,
        requiresShutdown: plan['requiresShutdown'] as bool? ?? false,
        safetyNote: plan['safetyNote'] as String?,
        isActive: plan['isActive'] as bool? ?? true,
        tasks: [
          for (final task in (plan['tasks'] as List<dynamic>? ?? const []))
            _jobPlanTaskFrom(task as Map<String, dynamic>),
        ],
      );

  static JobPlanTask _jobPlanTaskFrom(Map<String, dynamic> task) => JobPlanTask(
        id: task['id'].toString(),
        stepNo: (task['stepNo'] as num).toInt(),
        instruction: task['instruction'] as String,
        skillId: task['skillId']?.toString(),
        skillName: task['skillName'] as String?,
        estimatedHours: task['estimatedHours'] as num?,
      );

  // `toPmSchedule` (pm-schedules.js) sends a flat row key for key: `id, code,
  // name, assetId, assetCode, assetName, orgUnitId, orgUnitName, jobPlanId,
  // jobPlanName, intervalDays, assetMeterId, meterCode, meterName, meterType,
  // intervalMeter, lastCompletedMeter, nextDueMeter, currentMeter, meterDue,
  // anchor, leadTimeDays, priority, lastCompletedOn, nextDueOn, isActive,
  // daysUntilDue`. `intervalDays` is null for a meter-only schedule and
  // `intervalMeter`/`currentMeter`/`nextDueMeter` are null for a calendar one.
  static PmSchedule _pmScheduleFrom(Map<String, dynamic> schedule) => PmSchedule(
        id: schedule['id'].toString(),
        code: schedule['code'] as String,
        name: schedule['name'] as String,
        assetId: schedule['assetId'].toString(),
        assetCode: schedule['assetCode'] as String,
        assetName: schedule['assetName'] as String,
        orgUnitId: schedule['orgUnitId'].toString(),
        orgUnitName: schedule['orgUnitName'] as String,
        jobPlanId: schedule['jobPlanId'].toString(),
        jobPlanName: schedule['jobPlanName'] as String,
        intervalDays: (schedule['intervalDays'] as num?)?.toInt(),
        assetMeterId: schedule['assetMeterId']?.toString(),
        meterCode: schedule['meterCode'] as String?,
        meterName: schedule['meterName'] as String?,
        meterType: schedule['meterType'] as String?,
        intervalMeter: schedule['intervalMeter'] as num?,
        lastCompletedMeter: schedule['lastCompletedMeter'] as num?,
        nextDueMeter: schedule['nextDueMeter'] as num?,
        currentMeter: schedule['currentMeter'] as num?,
        meterDue: schedule['meterDue'] as bool? ?? false,
        anchor: schedule['anchor'] as String,
        leadTimeDays: (schedule['leadTimeDays'] as num?)?.toInt() ?? 7,
        priority: (schedule['priority'] as num?)?.toInt() ?? 3,
        lastCompletedOn: schedule['lastCompletedOn'] as String?,
        nextDueOn: schedule['nextDueOn'] as String?,
        isActive: schedule['isActive'] as bool? ?? true,
        daysUntilDue: (schedule['daysUntilDue'] as num?)?.toInt(),
      );

  // `toMeter` (meters.js): `id, assetId, assetCode, assetName, orgUnitId,
  // orgUnitName, siteId, code, name, uomCode, uomName, meterType,
  // rolloverOffset, isActive, latestReading, latestReadAt, accumulatedUse`.
  static AssetMeter _meterFrom(Map<String, dynamic> meter) => AssetMeter(
        id: meter['id'].toString(),
        assetId: meter['assetId'].toString(),
        assetCode: meter['assetCode'] as String,
        assetName: meter['assetName'] as String,
        orgUnitId: meter['orgUnitId'].toString(),
        orgUnitName: meter['orgUnitName'] as String,
        siteId: meter['siteId'].toString(),
        code: meter['code'] as String,
        name: meter['name'] as String,
        uomCode: meter['uomCode'] as String,
        uomName: meter['uomName'] as String,
        meterType: meter['meterType'] as String,
        rolloverOffset: meter['rolloverOffset'] as num? ?? 0,
        isActive: meter['isActive'] as bool? ?? true,
        latestReading: meter['latestReading'] as num?,
        latestReadAt: meter['latestReadAt'] as String?,
        accumulatedUse: meter['accumulatedUse'] as num? ?? 0,
      );

  static UnitOfMeasure _unitOfMeasureFrom(Map<String, dynamic> unit) => UnitOfMeasure(
        code: unit['code'] as String,
        name: unit['name'] as String,
        dimension: unit['dimension'] as String,
      );

  // `getBoard` (board.js) sends the Site, the optional chosen Org Unit, the
  // resolved period and one entry per Pillar in catalogue order. `value` and
  // `targetValue` are `number | null`: a null `value` is the wire's own way of
  // saying "nothing was measured", which is why it is parsed as a nullable
  // double and never defaulted to zero.
  static TierBoard _tierBoardFrom(Map<String, dynamic> board) => TierBoard(
        site: _boardSiteFrom(board['site'] as Map<String, dynamic>),
        orgUnit: board['orgUnit'] == null
            ? null
            : _boardOrgUnitFrom(board['orgUnit'] as Map<String, dynamic>),
        period: _boardPeriodFrom(board['period'] as Map<String, dynamic>),
        pillars: [
          for (final pillar in (board['pillars'] as List<dynamic>? ?? const []))
            _pillarFrom(pillar as Map<String, dynamic>),
        ],
      );

  static BoardSite _boardSiteFrom(Map<String, dynamic> site) => BoardSite(
        id: site['id'].toString(),
        name: site['name'] as String,
        timezone: site['timezone'] as String,
      );

  static BoardOrgUnit _boardOrgUnitFrom(Map<String, dynamic> orgUnit) => BoardOrgUnit(
        id: orgUnit['id'].toString(),
        name: orgUnit['name'] as String,
        path: orgUnit['path'] as String,
      );

  static BoardPeriod _boardPeriodFrom(Map<String, dynamic> period) => BoardPeriod(
        type: period['type'] as String,
        start: period['start'] as String,
        end: period['end'] as String,
      );

  static Pillar _pillarFrom(Map<String, dynamic> pillar) => Pillar(
        code: pillar['code'] as String,
        name: pillar['name'] as String,
        sortOrder: (pillar['sortOrder'] as num).toInt(),
        hasData: pillar['hasData'] as bool? ?? false,
        kpis: [
          for (final kpi in (pillar['kpis'] as List<dynamic>? ?? const []))
            _boardKpiFrom(kpi as Map<String, dynamic>),
        ],
      );

  static BoardKpi _boardKpiFrom(Map<String, dynamic> kpi) => BoardKpi(
        code: kpi['code'] as String,
        name: kpi['name'] as String,
        unit: kpi['unit'] as String? ?? '',
        direction: kpi['direction'] as String,
        decimalPlaces: (kpi['decimalPlaces'] as num?)?.toInt() ?? 0,
        formulaText: kpi['formulaText'] as String? ?? '',
        value: (kpi['value'] as num?)?.toDouble(),
        status: kpi['status'] as String,
        targetValue: (kpi['targetValue'] as num?)?.toDouble(),
      );

  // `toRequest` (requests.js) sends a flat row, the same shape `toWorkOrder`
  // does: `id, requestNo, assetId, assetCode, assetName, orgUnitId,
  // orgUnitName, summary, description, urgency, productionStopped, reportedBy,
  // reporterName, reportedAt, status, triagedAt, rejectionReason,
  // duplicateOfId`, plus a nested `workOrder` map or null. A later field added
  // to one side should prompt a look at the other.
  static Request _requestFrom(Map<String, dynamic> request) => Request(
        id: request['id'].toString(),
        requestNo: request['requestNo'] as String,
        assetId: request['assetId'].toString(),
        assetCode: request['assetCode'] as String,
        assetName: request['assetName'] as String,
        orgUnitId: request['orgUnitId'].toString(),
        orgUnitName: request['orgUnitName'] as String,
        summary: request['summary'] as String,
        description: request['description'] as String?,
        urgency: request['urgency'] as String,
        productionStopped: request['productionStopped'] as bool? ?? false,
        reportedBy: request['reportedBy']?.toString(),
        reporterName: request['reporterName'] as String?,
        reportedAt: request['reportedAt'] as String?,
        status: request['status'] as String,
        triagedAt: request['triagedAt'] as String?,
        rejectionReason: request['rejectionReason'] as String?,
        duplicateOfId: request['duplicateOfId']?.toString(),
        workOrder: request['workOrder'] == null
            ? null
            : _requestWorkOrderFrom(request['workOrder'] as Map<String, dynamic>),
      );

  static RequestWorkOrder _requestWorkOrderFrom(Map<String, dynamic> workOrder) => RequestWorkOrder(
        id: workOrder['id'].toString(),
        workOrderNo: workOrder['workOrderNo'] as String,
        status: workOrder['status'] as String,
      );

  // `toDowntimeEvent` (downtime.js) sends a flat row key for key: `id,
  // assetId, assetCode, assetName, orgUnitId, orgUnitName, startedAt,
  // endedAt, durationMinutes, status, downtimeReasonId, downtimeReasonName,
  // description, reportedBy, reporterName, classifiedAt, source`.
  static DowntimeEvent _downtimeEventFrom(Map<String, dynamic> event) => DowntimeEvent(
        id: event['id'].toString(),
        assetId: event['assetId'].toString(),
        assetCode: event['assetCode'] as String,
        assetName: event['assetName'] as String,
        orgUnitId: event['orgUnitId'].toString(),
        orgUnitName: event['orgUnitName'] as String,
        startedAt: event['startedAt'] as String?,
        endedAt: event['endedAt'] as String?,
        durationMinutes: event['durationMinutes'] as num?,
        status: event['status'] as String,
        downtimeReasonId: event['downtimeReasonId']?.toString(),
        downtimeReasonName: event['downtimeReasonName'] as String?,
        description: event['description'] as String?,
        reportedBy: event['reportedBy']?.toString(),
        reporterName: event['reporterName'] as String?,
        classifiedAt: event['classifiedAt'] as String?,
        source: event['source'] as String,
      );

  static DowntimeReason _downtimeReasonFrom(Map<String, dynamic> reason) => DowntimeReason(
        id: reason['id'].toString(),
        code: reason['code'] as String,
        name: reason['name'] as String,
        lossCategory: reason['lossCategory'] as String,
        isPlanned: reason['isPlanned'] as bool? ?? false,
        requiresComment: reason['requiresComment'] as bool? ?? false,
      );

  static Asset _assetFrom(Map<String, dynamic> asset) => Asset(
        id: asset['id'].toString(),
        code: asset['code'] as String,
        name: asset['name'] as String,
        assetType: asset['assetType'] as String,
        criticality: asset['criticality'] as String,
        orgUnitId: asset['orgUnitId'].toString(),
        orgUnitName: asset['orgUnitName'] as String? ?? '',
        siteId: asset['siteId'].toString(),
        isActive: asset['isActive'] as bool? ?? true,
        parentId: asset['parentId']?.toString(),
      );

  // `toPart` (inventory.js) sends `id, partNo, description, uomCode, isActive,
  // createdAt, updatedAt`. A later field added to one side should prompt a
  // look at the other.
  static Part _partFrom(Map<String, dynamic> part) => Part(
        id: part['id'].toString(),
        partNo: part['partNo'] as String,
        description: part['description'] as String,
        uomCode: part['uomCode'] as String,
        isActive: part['isActive'] as bool? ?? true,
      );

  // `toStore` (inventory.js) sends `id, siteId, orgUnitId, orgUnitCode,
  // orgUnitName, code, name, isActive, createdAt, updatedAt`.
  static Store _storeFrom(Map<String, dynamic> store) => Store(
        id: store['id'].toString(),
        siteId: store['siteId'].toString(),
        orgUnitId: store['orgUnitId'].toString(),
        orgUnitName: store['orgUnitName'] as String,
        code: store['code'] as String,
        name: store['name'] as String,
        isActive: store['isActive'] as bool? ?? true,
      );

  // `toStockLevel` (inventory.js) sends `partId, partNo, description, uomCode,
  // quantity`; the quantity is already a JSON number, derived from movements.
  static StockLevel _stockLevelFrom(Map<String, dynamic> row) => StockLevel(
        partId: row['partId'].toString(),
        partNo: row['partNo'] as String,
        description: row['description'] as String,
        uomCode: row['uomCode'] as String,
        quantity: row['quantity'] as num,
      );

  /// The open Work orders at the shared floor device's Org Unit and beneath
  /// it (`GET /api/maintenance/floor/work-orders`, issue #77). The device's
  /// own credential is what authenticates this read — no Account bearer token
  /// is involved, and the server decides the scope from the device itself, so
  /// this call names no Org Unit and cannot ask for one.
  Future<(FloorInfo, List<WorkOrder>)> fetchFloorWorkOrders(String deviceCredential) async {
    const path = '/api/maintenance/floor/work-orders';
    final response = await _send(
      () => _client.get(Uri.parse(path), headers: {'x-floor-device': deviceCredential}),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final floor = body['floor'] as Map<String, dynamic>;
      return (
        FloorInfo(
          orgUnitId: floor['orgUnitId'].toString(),
          orgUnitName: floor['orgUnitName'] as String,
          siteId: floor['siteId'].toString(),
        ),
        [
          for (final workOrder in body['workOrders'] as List<dynamic>)
            _workOrderFrom(workOrder as Map<String, dynamic>),
        ],
      );
    } catch (error) {
      throw MaintenanceApiException('The API answered with something this app could not read: $error');
    }
  }

  /// Exchanges a technician's Employee number and PIN for a short-lived
  /// identification (`POST /api/maintenance/floor/identify`, issue #77). The
  /// device credential must be presented too: an identification is issued for
  /// one device and is refused on another. A wrong number and a wrong PIN
  /// answer identically.
  Future<FloorIdentification> identifyTechnician(
    String deviceCredential, {
    required String employeeNo,
    required String pin,
  }) async {
    const path = '/api/maintenance/floor/identify';
    final response = await _send(
      () => _client.post(
        Uri.parse(path),
        headers: {'x-floor-device': deviceCredential, 'content-type': 'application/json'},
        body: jsonEncode({'employeeNo': employeeNo, 'pin': pin}),
      ),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final employee = body['employee'] as Map<String, dynamic>;
      return FloorIdentification(
        token: body['identification'] as String,
        employeeId: employee['id'].toString(),
        employeeName: employee['displayName'] as String,
      );
    } catch (error) {
      throw MaintenanceApiException('The API answered with something this app could not read: $error');
    }
  }

  /// Starts a Work order from the floor (`POST
  /// /api/maintenance/work-orders/:id/start`, issue #77) — the same endpoint
  /// the desktop Shell calls (#63), carrying the device credential and the
  /// individual identification instead of an Account bearer token.
  Future<WorkOrder> startFloorWorkOrder(
    String deviceCredential,
    String identification,
    String id,
  ) =>
      _floorWorkOrderAction(deviceCredential, identification, id, 'start', const {});

  /// Completes a Work order from the floor (`POST
  /// /api/maintenance/work-orders/:id/complete`, issue #77). [note] is what
  /// was found, required by the same rule the desktop path follows.
  Future<WorkOrder> completeFloorWorkOrder(
    String deviceCredential,
    String identification,
    String id, {
    required String note,
  }) =>
      _floorWorkOrderAction(deviceCredential, identification, id, 'complete', {'note': note});

  Future<WorkOrder> _floorWorkOrderAction(
    String deviceCredential,
    String identification,
    String id,
    String action,
    Map<String, dynamic> body,
  ) async {
    final path = '/api/maintenance/work-orders/$id/$action';
    final response = await _send(
      () => _client.post(
        Uri.parse(path),
        headers: {
          'x-floor-device': deviceCredential,
          'x-technician-identification': identification,
          'content-type': 'application/json',
        },
        body: jsonEncode(body),
      ),
      path,
    );
    try {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      return _workOrderFrom(decoded['workOrder'] as Map<String, dynamic>);
    } catch (error) {
      throw MaintenanceApiException('The API answered with something this app could not read: $error');
    }
  }

  /// Accepts any 2xx, the same rule `PeopleApi._send` follows (issue #87):
  /// creating an Asset answers 201, which is the status this Module's own
  /// POST actually returns.
  Future<http.Response> _send(Future<http.Response> Function() send, String path) async {
    final http.Response response;
    try {
      response = await send();
    } catch (error) {
      throw MaintenanceApiException('Could not reach the API: $error');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw MaintenanceApiException(
        _messageFrom(response) ?? 'The API answered ${response.statusCode} for $path.',
        statusCode: response.statusCode,
      );
    }
    return response;
  }

  static String? _messageFrom(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map<String, dynamic> && body['message'] is String) {
        return body['message'] as String;
      }
    } catch (_) {
      // Not JSON, or not that shape: the caller's generic message stands.
    }
    return null;
  }
}
