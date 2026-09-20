/// The Safety Module's HTTP surface, from the Flutter app's side — the client
/// half of `backend/src/modules/safety/` (ADR-0012's mirror of ADR-0006).
///
/// Its own class inside its own Module's folder, the shape `QualityApi` and
/// `ActionsApi` already take rather than a second `lib/*_api.dart` at the
/// root. Its own exception type too, for the same reason `QualityApiException`
/// is its own: a caller can tell which Module's address failed without
/// reading the message.
///
/// Today it carries the Module's first slice (issue #226): the Safety
/// incident register, one incident's detail, and recording one. **The
/// register is read per Site**, off `GET /api/safety/sites/:siteId/incidents`
/// — the address `safety-incident-routes.js` publishes, the same shape the
/// Non-conformance register uses. The Site is the only scope question the
/// address asks (anyone who can see the Site reads its incidents), and every
/// filter — Org Unit and everything beneath it, status, incident type,
/// severity level, recordability, a production-day range — is a read filter
/// over an already-visible register.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'safety_incident.dart';

/// The request could not be answered at all. Deliberately its own type
/// rather than another Module's, mirroring `QualityApiException`.
class SafetyApiException implements Exception {
  SafetyApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class SafetyApi {
  SafetyApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// The Site's Safety incidents, newest first
  /// (`GET /api/safety/sites/:siteId/incidents`), narrowed by [filters].
  Future<SafetyIncidentRegister> fetchSafetyIncidents(
    String accessToken,
    String siteId, {
    SafetyIncidentFilters filters = const SafetyIncidentFilters(),
  }) async {
    final path = '/api/safety/sites/$siteId/incidents';
    final query = filters.queryParameters;
    final uri = Uri.parse(path).replace(queryParameters: query.isEmpty ? null : query);
    final response = await _send(
      () => _client.get(uri, headers: {'authorization': 'Bearer $accessToken'}),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return SafetyIncidentRegister(
        incidents: [
          for (final row in body['incidents'] as List<dynamic>)
            SafetyIncident.fromJson(row as Map<String, dynamic>),
        ],
        truncated: body['truncated'] == true,
      );
    } catch (error) {
      throw SafetyApiException('The API answered with something this app could not read: $error');
    }
  }

  /// One Safety incident (`GET /api/safety/incidents/:id`) — what the detail
  /// Screen reads.
  Future<SafetyIncident> fetchSafetyIncident(String accessToken, String id) async {
    final path = '/api/safety/incidents/$id';
    final response = await _send(
      () => _client.get(Uri.parse(path), headers: {'authorization': 'Bearer $accessToken'}),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return SafetyIncident.fromJson(body['incident'] as Map<String, dynamic>);
    } catch (error) {
      throw SafetyApiException('The API answered with something this app could not read: $error');
    }
  }

  /// Records a Safety incident (`POST /api/safety/sites/:siteId/incidents`).
  /// It is recorded at [orgUnitId] and needs a Grant that reaches it with
  /// edit, or the administrator role; the API refuses anything else (403).
  ///
  /// Only the keys a caller actually decided are sent: the optional Asset,
  /// Employee, immediate action, lost-time and restricted days, and
  /// `reportedAt` are omitted when they are empty rather than sent as nulls
  /// the API would have to interpret.
  Future<SafetyIncident> recordSafetyIncident(
    String accessToken,
    String siteId, {
    required String orgUnitId,
    required String occurredAt,
    required String incidentType,
    required String severityLevel,
    required String description,
    String? assetId,
    String? employeeId,
    String? reportedAt,
    String? immediateAction,
    int? lostTimeDays,
    int? restrictedDays,
  }) async {
    final path = '/api/safety/sites/$siteId/incidents';
    final body = <String, Object?>{
      'orgUnitId': orgUnitId,
      'occurredAt': occurredAt,
      'incidentType': incidentType,
      'severityLevel': severityLevel,
      'description': description,
    };
    if (assetId != null) body['assetId'] = assetId;
    if (employeeId != null) body['employeeId'] = employeeId;
    if (reportedAt != null) body['reportedAt'] = reportedAt;
    if (immediateAction != null && immediateAction.trim().isNotEmpty) {
      body['immediateAction'] = immediateAction.trim();
    }
    if (lostTimeDays != null && lostTimeDays > 0) body['lostTimeDays'] = lostTimeDays;
    if (restrictedDays != null && restrictedDays > 0) body['restrictedDays'] = restrictedDays;

    final response = await _send(
      () => _client.post(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode(body),
      ),
      path,
    );
    try {
      final answer = jsonDecode(response.body) as Map<String, dynamic>;
      return SafetyIncident.fromJson(answer['incident'] as Map<String, dynamic>);
    } catch (error) {
      throw SafetyApiException('The API answered with something this app could not read: $error');
    }
  }

  /// Records a Safety incident at a shared floor device
  /// (`POST /api/safety/floor/incidents`, issue #227), mirroring
  /// `QualityApi.recordFloorNonconformance` closely. [deviceCredential]
  /// selects the door and [identification] says which Employee is standing at
  /// the machine — the identified Employee becomes the incident's reporter,
  /// and there is no recording Account on this path at all (ADR-0016).
  ///
  /// [orgUnitId] is where the record is filed — the device's own Org Unit, or
  /// anything beneath it; the API refuses one outside that reach with a 403
  /// carrying People's own `OUTSIDE_GRANTED_ORG_UNITS` wording. A missing,
  /// invalid or expired identification is a 401, and every field and
  /// ladder-consistency rule is the same as the Account door's
  /// [recordSafetyIncident], because both call the same service.
  ///
  /// Only the fields the floor form actually collects are sent — no Asset, no
  /// Employee involved, no `reportedAt`, no `isAnonymous` (there is no
  /// anonymous option anywhere in this flow, ADR-0036).
  Future<SafetyIncident> recordFloorSafetyIncident(
    String deviceCredential,
    String identification, {
    required String orgUnitId,
    required String incidentType,
    required String severityLevel,
    required String description,
    required String occurredAt,
    String? immediateAction,
  }) async {
    const path = '/api/safety/floor/incidents';
    final body = <String, Object?>{
      'orgUnitId': orgUnitId,
      'incidentType': incidentType,
      'severityLevel': severityLevel,
      'description': description,
      'occurredAt': occurredAt,
    };
    if (immediateAction != null && immediateAction.trim().isNotEmpty) {
      body['immediateAction'] = immediateAction.trim();
    }

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
      final answer = jsonDecode(response.body) as Map<String, dynamic>;
      return SafetyIncident.fromJson(answer['incident'] as Map<String, dynamic>);
    } catch (error) {
      throw SafetyApiException('The API answered with something this app could not read: $error');
    }
  }

  /// Sets or changes the investigation due date (issue #228,
  /// `PATCH /api/safety/incidents/:id/investigation-due-date`). Needs an edit
  /// Grant reaching the incident's Org Unit; the API refuses anyone else with
  /// a 403, and refuses a closed incident with a 409. `null` clears it.
  Future<SafetyIncident> setInvestigationDueDate(
    String accessToken,
    String id, {
    String? investigationDueAt,
  }) async {
    final path = '/api/safety/incidents/$id/investigation-due-date';
    final response = await _send(
      () => _client.patch(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode({'investigationDueAt': investigationDueAt}),
      ),
      path,
    );
    return _incidentFrom(response);
  }

  /// Moves the status one step along the ladder (issue #228,
  /// `POST /api/safety/incidents/:id/status`): `open -> investigating ->
  /// actions_pending`. `closed` is never a valid [status] here — closing is
  /// [closeSafetyIncident]'s own address. Needs an edit Grant reaching the
  /// incident's Org Unit; a move that is not the ladder's own next step is a
  /// 409.
  Future<SafetyIncident> moveSafetyIncidentStatus(
    String accessToken,
    String id, {
    required String status,
  }) async {
    final path = '/api/safety/incidents/$id/status';
    final response = await _send(
      () => _client.post(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode({'status': status}),
      ),
      path,
    );
    return _incidentFrom(response);
  }

  /// Corrects the severity level, with a note (issue #228, #223 decision 5,
  /// `POST /api/safety/incidents/:id/severity`). Needs Safety authority
  /// reaching the incident's Org Unit (ADR-0039) — the API refuses anyone
  /// else with a 403, and refuses a missing note with a 400. Accepted even on
  /// a closed incident: a correction restates the period it occurred in.
  Future<SafetyIncident> changeSafetyIncidentSeverity(
    String accessToken,
    String id, {
    required String severityLevel,
    required String note,
  }) async {
    final path = '/api/safety/incidents/$id/severity';
    final response = await _send(
      () => _client.post(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode({'severityLevel': severityLevel, 'note': note}),
      ),
      path,
    );
    return _incidentFrom(response);
  }

  /// Records what the injury cost: the lost-time and restricted days (issue
  /// #228, `POST /api/safety/incidents/:id/days`). Needs Safety authority
  /// reaching the incident's Org Unit — both counts are required on every
  /// call, because this is the act that "settles" the days that closing above
  /// the no-injury rung waits on (zero is an answer, but it has to be said).
  Future<SafetyIncident> recordSafetyIncidentDays(
    String accessToken,
    String id, {
    required int lostTimeDays,
    required int restrictedDays,
  }) async {
    final path = '/api/safety/incidents/$id/days';
    final response = await _send(
      () => _client.post(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode({'lostTimeDays': lostTimeDays, 'restrictedDays': restrictedDays}),
      ),
      path,
    );
    return _incidentFrom(response);
  }

  /// Closes the incident, with a note (issue #228, #223 decision 4,
  /// `POST /api/safety/incidents/:id/close`). Needs Safety authority reaching
  /// the incident's Org Unit — the API refuses anyone else with a 403,
  /// refuses a missing note with a 400, and refuses one above the no-injury
  /// rung whose days are not settled with a 409. Never refused for an open
  /// Concern raised from the incident.
  Future<SafetyIncident> closeSafetyIncident(
    String accessToken,
    String id, {
    required String note,
  }) async {
    final path = '/api/safety/incidents/$id/close';
    final response = await _send(
      () => _client.post(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode({'note': note}),
      ),
      path,
    );
    return _incidentFrom(response);
  }

  SafetyIncident _incidentFrom(http.Response response) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return SafetyIncident.fromJson(body['incident'] as Map<String, dynamic>);
    } catch (error) {
      throw SafetyApiException('The API answered with something this app could not read: $error');
    }
  }

  // Mirrors QualityApi._send: a transport failure and a non-2xx answer both
  // leave here as the Module's own exception, carrying the API's own message
  // when it sent one (so a 400's sentence reaches the form that caused it
  // rather than being replaced by a status code).
  Future<http.Response> _send(Future<http.Response> Function() send, String path) async {
    final http.Response response;
    try {
      response = await send();
    } catch (error) {
      throw SafetyApiException('Could not reach the API: $error');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SafetyApiException(
        _messageFrom(response) ?? 'The API answered ${response.statusCode} for $path.',
        statusCode: response.statusCode,
      );
    }
    return response;
  }

  String? _messageFrom(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map<String, dynamic> && body['message'] is String) {
        return body['message'] as String;
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}
