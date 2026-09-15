/// The Actions Module's HTTP surface, from the Flutter app's side.
///
/// Its own class next to its own Module, mirroring
/// `maintenance/maintenance_api.dart` — the client half of ADR-0012's
/// Module-for-Module mirror. Nothing here reads a People endpoint: the
/// register's Site chooser and the raise form's owner picker call `PeopleApi`
/// directly, the same way the Asset register does.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'action.dart';

/// The request could not be answered at all. Deliberately its own type rather
/// than People's `PeopleApiException` or Maintenance's: ADR-0006's third clause
/// keeps generic plumbing on each Module's own side, and the client mirrors it.
class ActionsApiException implements Exception {
  ActionsApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class ActionsApi {
  ActionsApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// A Site's action log (issue #176) — open Actions by default, history when
  /// [includeHistory] asks for it, narrowed by whichever filters are set. The
  /// API reads Site-wide whatever the caller's Grants, so nothing is filtered
  /// here either.
  Future<ActionRegister> fetchActions(
    String accessToken, {
    required String siteId,
    String? orgUnitId,
    String? status,
    String? actionType,
    String? ownerEmployeeId,
    String? pillarCode,
    bool includeHistory = false,
  }) async {
    final path = '/api/actions/sites/$siteId/actions';
    final query = <String, String>{
      'orgUnitId': ?orgUnitId,
      'status': ?status,
      'actionType': ?actionType,
      'ownerEmployeeId': ?ownerEmployeeId,
      'pillarCode': ?pillarCode,
      if (includeHistory) 'includeHistory': 'true',
    };
    final uri = Uri.parse(path)
        .replace(queryParameters: query.isEmpty ? null : query);
    final response = await _send(
      () => _client.get(uri, headers: {'authorization': 'Bearer $accessToken'}),
      path,
    );
    final body = _decode(response, path);
    return ActionRegister(
      actions: [
        for (final action in body['actions'] as List<dynamic>)
          _actionFrom(action as Map<String, dynamic>),
      ],
      truncated: body['truncated'] == true,
    );
  }

  /// One Action (`GET /api/actions/:id`), with the collections a detail read
  /// carries: its parent and its measures.
  Future<Action> fetchAction(String accessToken, String id) async {
    final path = '/api/actions/$id';
    final response = await _send(
      () => _client.get(Uri.parse(path), headers: {'authorization': 'Bearer $accessToken'}),
      path,
    );
    return _actionFrom(_decode(response, path)['action'] as Map<String, dynamic>);
  }

  /// Raises one Action (issue #176).
  ///
  /// The Org Unit is required and is the caller's decision; everything else is
  /// optional, and each null is left out of the body rather than sent as one —
  /// so the server's own defaults (type `concern`, priority 3, no due date)
  /// are what a caller gets when they choose nothing, rather than this client
  /// inventing a value the form never showed.
  Future<Action> raiseAction(
    String accessToken, {
    required String siteId,
    required String orgUnitId,
    required String title,
    String? description,
    String? actionType,
    String? pillarCode,
    String? ownerEmployeeId,
    String? dueDate,
    int? priority,
  }) async {
    final path = '/api/actions/sites/$siteId/actions';
    final body = <String, dynamic>{
      'orgUnitId': orgUnitId,
      'title': title,
      'description': ?description,
      'actionType': ?actionType,
      'pillarCode': ?pillarCode,
      'ownerEmployeeId': ?ownerEmployeeId,
      'dueDate': ?dueDate,
      'priority': ?priority,
    };
    final response = await _send(
      () => _client.post(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode(body),
      ),
      path,
    );
    return _actionFrom(_decode(response, path)['action'] as Map<String, dynamic>);
  }

  /// Raises a measure against the Concern it answers (issue #178).
  ///
  /// A measure is an Action, so everything except the parent link is the raise
  /// form's own body — and every optional field is left out rather than sent as
  /// a null, so the server's defaults are what a caller gets when they choose
  /// nothing.
  Future<Action> raiseMeasure(
    String accessToken,
    String concernId, {
    required String actionType,
    required String title,
    String? description,
    String? orgUnitId,
    String? ownerEmployeeId,
    String? dueDate,
    int? priority,
  }) async {
    final path = '/api/actions/$concernId/measures';
    final body = <String, dynamic>{
      'actionType': actionType,
      'title': title,
      'description': ?description,
      'orgUnitId': ?orgUnitId,
      'ownerEmployeeId': ?ownerEmployeeId,
      'dueDate': ?dueDate,
      'priority': ?priority,
    };
    final response = await _send(
      () => _client.post(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode(body),
      ),
      path,
    );
    return _actionFrom(_decode(response, path)['action'] as Map<String, dynamic>);
  }

  /// Completes the Action's open phase (issue #177) and answers with the
  /// Action as it now stands, phases included — so the caller renders the row
  /// the server just wrote rather than a guess at it.
  ///
  /// `outcome` is sent only when a verdict was chosen: a plan, a do and an act
  /// have none, and sending `null` for them would be this client inventing a
  /// field the server refuses.
  Future<Action> completePhase(
    String accessToken,
    String actionId,
    String phase, {
    required String note,
    String? outcome,
  }) async {
    final path = '/api/actions/$actionId/phases/$phase/complete';
    final body = <String, dynamic>{'note': note, 'outcome': ?outcome};
    final response = await _send(
      () => _client.post(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode(body),
      ),
      path,
    );
    return _actionFrom(_decode(response, path)['action'] as Map<String, dynamic>);
  }

  /// Calls one Action off (issue #179).
  ///
  /// The reason is optional and only sent when there is one: cancelling
  /// withdraws a claim rather than making one, so it carries no evidence and
  /// the server COALESCEs whatever arrives over any note already on the row.
  Future<Action> cancelAction(String accessToken, String actionId, {String? reason}) async {
    final path = '/api/actions/$actionId/cancel';
    final body = <String, dynamic>{'reason': ?reason};
    final response = await _send(
      () => _client.post(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode(body),
      ),
      path,
    );
    return _actionFrom(_decode(response, path)['action'] as Map<String, dynamic>);
  }

  /// The five Pillars, for the raise form's chooser (ADR-0023: a value with a
  /// known set is chosen, never typed).
  Future<List<Pillar>> fetchPillars(String accessToken) async {
    const path = '/api/actions/pillars';
    final response = await _send(
      () => _client.get(Uri.parse(path), headers: {'authorization': 'Bearer $accessToken'}),
      path,
    );
    final body = _decode(response, path);
    return [
      for (final pillar in body['pillars'] as List<dynamic>)
        Pillar(
          code: (pillar as Map<String, dynamic>)['code'] as String,
          name: pillar['name'] as String,
          description: pillar['description'] as String?,
        ),
    ];
  }

  Map<String, dynamic> _decode(http.Response response, String path) {
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (error) {
      throw ActionsApiException('The API answered with something this app could not read: $error');
    }
  }

  /// One Action off the wire. Every id is a string: the server sends BIGINTs
  /// as strings, and a client that coerced them to int would break on the
  /// first id past 2^53.
  static Action _actionFrom(Map<String, dynamic> json) => Action(
        id: json['id'].toString(),
        actionNo: json['actionNo'] as String,
        title: json['title'] as String,
        description: json['description'] as String?,
        actionType: json['actionType'] as String,
        pillarCode: json['pillarCode'] as String?,
        orgUnitId: json['orgUnitId'].toString(),
        orgUnitName: json['orgUnitName'] as String,
        siteId: json['siteId'].toString(),
        ownerEmployeeId: json['ownerEmployeeId']?.toString(),
        ownerName: json['ownerName'] as String?,
        raisedByEmployeeId: json['raisedByEmployeeId']?.toString(),
        raisedByName: json['raisedByName'] as String?,
        raisedAt: json['raisedAt'] == null ? null : DateTime.parse(json['raisedAt'] as String),
        dueDate: json['dueDate'] as String?,
        isOverdue: json['isOverdue'] == true,
        daysOverdue: json['daysOverdue'] as int?,
        priority: json['priority'] as int,
        status: json['status'] as String,
        completedAt: json['completedAt'] == null ? null : DateTime.parse(json['completedAt'] as String),
        closureNote: json['closureNote'] as String?,
        escalatedToOrgUnitId: json['escalatedToOrgUnitId']?.toString(),
        escalatedToOrgUnitName: json['escalatedToOrgUnitName'] as String?,
        escalatedAt: json['escalatedAt'] == null ? null : DateTime.parse(json['escalatedAt'] as String),
        sourceType: json['sourceType'] as String?,
        parentId: json['parentId']?.toString(),
        measureCount: (json['measureCount'] as int?) ?? 0,
        countermeasureCount: (json['countermeasureCount'] as int?) ?? 0,
        openPhase: json['openPhase'] == null
            ? null
            : _phaseFrom(json['openPhase'] as Map<String, dynamic>),
        phases: [
          for (final phase in (json['phases'] as List<dynamic>? ?? const []))
            _phaseFrom(phase as Map<String, dynamic>),
        ],
        parent: json['parent'] == null
            ? null
            : _parentFrom(json['parent'] as Map<String, dynamic>),
        measures: [
          for (final measure in (json['measures'] as List<dynamic>? ?? const []))
            _actionFrom(measure as Map<String, dynamic>),
        ],
      );

  /// The Concern a measure answers, named rather than nested — see
  /// `ActionParent`.
  static ActionParent _parentFrom(Map<String, dynamic> json) => ActionParent(
        id: json['id'].toString(),
        actionNo: json['actionNo'] as String,
        title: json['title'] as String,
        actionType: json['actionType'] as String,
        status: json['status'] as String,
      );

  static ActionPhase _phaseFrom(Map<String, dynamic> json) => ActionPhase(
        cycle: json['cycle'] as int,
        phase: json['phase'] as String,
        id: json['id']?.toString(),
        ownerEmployeeId: json['ownerEmployeeId']?.toString(),
        ownerName: json['ownerName'] as String?,
        dueDate: json['dueDate'] as String?,
        completedAt:
            json['completedAt'] == null ? null : DateTime.parse(json['completedAt'] as String),
        outcome: json['outcome'] as String?,
        note: json['note'] as String?,
      );

  /// The same error shape Maintenance's and People's clients use: the server's
  /// own message where it sent one, and a status-and-path sentence where it did
  /// not — never a raw exception, which names internals a screen should not
  /// show.
  Future<http.Response> _send(Future<http.Response> Function() send, String path) async {
    final http.Response response;
    try {
      response = await send();
    } catch (error) {
      throw ActionsApiException('Could not reach the API: $error');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ActionsApiException(
        _messageFrom(response) ?? 'The API answered ${response.statusCode} for $path.',
        statusCode: response.statusCode,
      );
    }
    return response;
  }

  static String? _messageFrom(http.Response response) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final message = body['message'];
      return message is String && message.isNotEmpty ? message : null;
    } catch (_) {
      return null;
    }
  }
}
