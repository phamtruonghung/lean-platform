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
import 'assignee_candidate.dart';
import 'maintenance_request.dart';
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

  /// The open Work orders across a whole Site (issue #57) — the server
  /// excludes completed/closed/cancelled from this read, so nothing further
  /// filters the result here. [orgUnitId] narrows to that Org Unit and
  /// everything beneath it; an unknown one is a 404, surfaced through
  /// [_send] like any other refusal.
  Future<List<WorkOrder>> fetchWorkOrders(
    String accessToken, {
    required String siteId,
    String? orgUnitId,
  }) async {
    final path = '/api/maintenance/sites/$siteId/work-orders';
    final uri = orgUnitId != null
        ? Uri.parse(path).replace(queryParameters: {'orgUnitId': orgUnitId})
        : Uri.parse(path);
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

  /// The assignee picker for one Work order (issue #62): every active
  /// Employee at the Work order's Site, each with their `qualifications`.
  /// A read — the server answers it for any approved Account whose role earns
  /// the Module, whatever its Grants.
  Future<List<AssigneeCandidate>> fetchCandidates(
    String accessToken, {
    required String workOrderId,
  }) async {
    final path = '/api/maintenance/work-orders/$workOrderId/candidates';
    final response = await _send(
      () => _client.get(Uri.parse(path), headers: {'authorization': 'Bearer $accessToken'}),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return [
        for (final candidate in body['candidates'] as List<dynamic>)
          _candidateFrom(candidate as Map<String, dynamic>),
      ];
    } catch (error) {
      throw MaintenanceApiException('The API answered with something this app could not read: $error');
    }
  }

  /// Assigns a Work order to [employeeId] (`PATCH /api/maintenance/work-orders/:id`
  /// with `assignedTo`). The server refuses a caller without a write Grant
  /// reaching the Work order's Asset Org Unit (403), an unknown Work order or
  /// Employee (404), and a departed Employee (400) — this call just reports
  /// whatever the server decided.
  Future<WorkOrder> assignWorkOrder(
    String accessToken,
    String workOrderId, {
    required String employeeId,
  }) async {
    final path = '/api/maintenance/work-orders/$workOrderId';
    final response = await _send(
      () => _client.patch(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode({'assignedTo': employeeId}),
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

  /// Starts a Work order (`POST /api/maintenance/work-orders/:id/start`):
  /// records when work began and moves it to in-progress (issue #63). The
  /// server stamps the timestamp, never the client; and refuses a Work order
  /// that is not 'approved' (agreed). A write Grant reaching the Work order's
  /// Asset Org Unit is required.
  Future<WorkOrder> startWorkOrder(String accessToken, String workOrderId) =>
      _transitionWorkOrder(accessToken, workOrderId, 'start');

  /// Completes a Work order (`POST /api/maintenance/work-orders/:id/complete`):
  /// records when work ended and takes a note of what was found (issue #63).
  /// [completionNote] is optional; the server refuses to complete a Work
  /// order that was never started, so a duration is never invented.
  Future<WorkOrder> completeWorkOrder(
    String accessToken,
    String workOrderId, {
    String? completionNote,
  }) =>
      _transitionWorkOrder(
        accessToken,
        workOrderId,
        'complete',
        body: completionNote == null ? null : {'completionNote': completionNote},
      );

  /// Cancels a Work order (`POST /api/maintenance/work-orders/:id/cancel`) —
  /// one raised in error is cancelled rather than left open pretending to be
  /// work (issue #63). The server allows it from 'approved' or 'in_progress'.
  Future<WorkOrder> cancelWorkOrder(String accessToken, String workOrderId) =>
      _transitionWorkOrder(accessToken, workOrderId, 'cancel');

  /// The one shape all three lifecycle transitions share: a bare POST to the
  /// transition's sub-resource (with at most a `completionNote` body on
  /// /complete), answered with the updated Work order — the same
  /// `{ workOrder }` envelope every other Write in this Module returns.
  Future<WorkOrder> _transitionWorkOrder(
    String accessToken,
    String workOrderId,
    String transition, {
    Map<String, dynamic>? body,
  }) async {
    final path = '/api/maintenance/work-orders/$workOrderId/$transition';
    final response = await _send(
      () => _client.post(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: body == null ? null : jsonEncode(body),
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

  /// Raises a Request against [assetId] (issue #72). Deliberately no
  /// `orgUnitId` and no Request number: the server derives the former from
  /// the Asset by trigger and issues the latter from the Site's own RQT
  /// sequence, so the client sends neither. `urgency` is the operator's
  /// judgement; the platform keeps it separate from a Work order's priority.
  Future<MaintenanceRequest> createRequest(
    String accessToken, {
    required String assetId,
    required String summary,
    required String urgency,
    bool productionStopped = false,
    String? description,
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

  /// The triage queue — every open Request across a whole Site (issue #72).
  /// [orgUnitId] narrows to that Org Unit and everything beneath it. A read,
  /// Site-wide in the ADR-0009 sense: no Grant filter.
  Future<List<MaintenanceRequest>> fetchTriageQueue(
    String accessToken, {
    required String siteId,
    String? orgUnitId,
  }) async {
    final path = '/api/maintenance/sites/$siteId/requests';
    final uri = orgUnitId != null
        ? Uri.parse(path).replace(queryParameters: {'orgUnitId': orgUnitId})
        : Uri.parse(path);
    final response = await _send(
      () => _client.get(uri, headers: {'authorization': 'Bearer $accessToken'}),
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

  /// The Requests this Account raised, and what became of each (issue #72).
  /// A read, inherently scoped to the caller — the server only ever returns
  /// rows that Account itself created.
  Future<List<MaintenanceRequest>> fetchMyRequests(String accessToken) async {
    const path = '/api/maintenance/requests/mine';
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

  /// Accepts a Request (issue #72): raises the Work order for it, which points
  /// back at the Request (ADR-0014). The server decides `workType` and
  /// `priority` are set here by maintenance — urgency is the operator's
  /// judgement and is never copied across. Returns the created Work order and
  /// the updated Request.
  Future<({RequestedWorkOrder workOrder, MaintenanceRequest request})> acceptRequest(
    String accessToken,
    String requestId, {
    required String workType,
    required int priority,
    String? description,
  }) async {
    final path = '/api/maintenance/requests/$requestId/accept';
    final response = await _send(
      () => _client.post(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode({
          'workType': workType,
          'priority': priority,
          'description': ?description,
        }),
      ),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final workOrder = _requestedWorkOrderFrom(body['workOrder'] as Map<String, dynamic>);
      final request = _requestFrom(body['request'] as Map<String, dynamic>);
      return (workOrder: workOrder, request: request);
    } catch (error) {
      throw MaintenanceApiException('The API answered with something this app could not read: $error');
    }
  }

  /// Declines a Request (issue #72), which requires a reason.
  Future<MaintenanceRequest> declineRequest(
    String accessToken,
    String requestId, {
    required String reason,
  }) async {
    final path = '/api/maintenance/requests/$requestId/decline';
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

  /// Marks one Request as a duplicate of [duplicateOfId] (issue #72); the
  /// surviving Request is named on the row.
  Future<MaintenanceRequest> markRequestDuplicate(
    String accessToken,
    String requestId, {
    required String duplicateOfId,
  }) async {
    final path = '/api/maintenance/requests/$requestId/duplicate';
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

  static MaintenanceRequest _requestFrom(Map<String, dynamic> request) => MaintenanceRequest(
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
        status: request['status'] as String,
        requestedByName: request['requestedByName'] as String?,
        reportedAt: DateTime.tryParse(request['reportedAt'] as String) ?? DateTime.now(),
        rejectionReason: request['rejectionReason'] as String?,
        duplicateOfId: request['duplicateOfId']?.toString(),
        duplicateOfNo: request['duplicateOfNo'] as String?,
        workOrder: request['workOrder'] == null
            ? null
            : _requestedWorkOrderFrom(request['workOrder'] as Map<String, dynamic>),
      );

  static RequestedWorkOrder _requestedWorkOrderFrom(Map<String, dynamic> workOrder) =>
      RequestedWorkOrder(
        id: workOrder['id'].toString(),
        workOrderNo: workOrder['workOrderNo'] as String,
        status: workOrder['status'] as String,
        assignedTo: workOrder['assignedTo']?.toString(),
        actualEnd: workOrder['actualEnd'] == null
            ? null
            : DateTime.tryParse(workOrder['actualEnd'] as String),
      );

  static AssigneeCandidate _candidateFrom(Map<String, dynamic> candidate) => AssigneeCandidate(
        id: candidate['id'].toString(),
        employeeNo: candidate['employeeNo'] as String,
        firstName: candidate['firstName'] as String,
        lastName: candidate['lastName'] as String,
        displayName: candidate['displayName'] as String,
        qualifications: [
          for (final qualification in candidate['qualifications'] as List<dynamic>? ?? const [])
            _qualificationFrom(qualification as Map<String, dynamic>),
        ],
      );

  static Qualification _qualificationFrom(Map<String, dynamic> qualification) => Qualification(
        skillId: qualification['skillId'].toString(),
        skillCode: qualification['skillCode'] as String,
        skillName: qualification['skillName'] as String,
        proficiencyLevel: (qualification['proficiencyLevel'] as num?)?.toInt() ?? 0,
        assessedOn: qualification['assessedOn'] as String?,
        expiresOn: qualification['expiresOn'] as String?,
        isLapsed: qualification['isLapsed'] as bool? ?? false,
      );

  // The server sends a flat row — `id, workOrderNo, assetId, assetCode,
  // assetName, orgUnitId, orgUnitName, summary, description, workType,
  // priority, status, assignedTo, assigneeName, createdAt, updatedAt`
  // (`toWorkOrder`, work-orders.js) — no nested `asset`/`orgUnit` map and no
  // `assignee` string, so this reads the same flat keys `_assetFrom` already
  // does for the Asset register.
  static WorkOrder _workOrderFrom(Map<String, dynamic> workOrder) => WorkOrder(
        id: workOrder['id'].toString(),
        workOrderNo: workOrder['workOrderNo'] as String,
        assetId: workOrder['assetId'].toString(),
        assetCode: workOrder['assetCode'] as String,
        assetName: workOrder['assetName'] as String,
        orgUnitId: workOrder['orgUnitId'].toString(),
        orgUnitName: workOrder['orgUnitName'] as String,
        summary: workOrder['summary'] as String,
        workType: workOrder['workType'] as String,
        priority: (workOrder['priority'] as num).toInt(),
        status: workOrder['status'] as String,
        assignedTo: workOrder['assignedTo']?.toString(),
        assigneeName: workOrder['assigneeName'] as String?,
        actualStart: workOrder['actualStart'] == null
            ? null
            : DateTime.tryParse(workOrder['actualStart'] as String),
        actualEnd: workOrder['actualEnd'] == null
            ? null
            : DateTime.tryParse(workOrder['actualEnd'] as String),
        completionNote: workOrder['completionNote'] as String?,
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

  /// Accepts any 2xx, unlike `PeopleApi._send`'s `!= 200`: creating an Asset
  /// answers 201, which is the status this Module's own POST actually returns.
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
