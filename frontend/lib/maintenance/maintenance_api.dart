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
