/// The Production Module's HTTP surface, from the Flutter app's side — the
/// client half of `backend/src/modules/production/` (ADR-0012's mirror of
/// ADR-0006), mounted by the server under `/api/production`.
///
/// Today it carries the Shift handover (issue #339, spec #332): the Section's
/// day and its Assets, opening and reading one handover, writing its lines and
/// header while it is a draft, submitting it, and acknowledging it. Every write
/// answers with the whole handover, so the Screen re-renders from what the
/// server now holds rather than patching its own copy.
///
/// Its own exception type, for the reason `QualityApiException` is its own: a
/// caller can tell which Module's address failed without reading the message.
/// Submit's completeness refusal carries more than a sentence — the Assets,
/// lines, blocks and Actions it is missing — so the exception carries it as a
/// [HandoverRefusal] beside the message.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'handover.dart';

class ProductionApiException implements Exception {
  ProductionApiException(this.message, {this.statusCode, this.code, this.refusal});

  final String message;
  final int? statusCode;

  /// The API's own machine-readable code, when it sent one
  /// (`HANDOVER_EXISTS`, `INCOMPLETE_HANDOVER`, ...).
  final String? code;

  /// Submit's named gaps, when the refusal was `INCOMPLETE_HANDOVER`.
  final HandoverRefusal? refusal;

  @override
  String toString() => message;
}

class ProductionApi {
  ProductionApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String _base = '/api/production';

  /// A Section's production day (`GET /sections/:orgUnitId/handovers`): every
  /// shift instance with its live handover or none, its late flag, its
  /// acknowledgement latency and its exceptions. Without [date] the server
  /// answers the Site's own today.
  Future<SectionDay> fetchSectionDay(String accessToken, String orgUnitId, {String? date}) async {
    final path = '$_base/sections/$orgUnitId/handovers';
    final uri = Uri.parse(path).replace(queryParameters: date == null ? null : {'date': date});
    final response = await _send(() => _client.get(uri, headers: _headers(accessToken)), path);
    return _read(response, (body) => SectionDay.fromJson(body));
  }

  /// The Section's active Assets (`GET /sections/:orgUnitId/assets`) — the
  /// machines a handover owes one Machine status line each.
  Future<List<SectionAsset>> fetchSectionAssets(String accessToken, String orgUnitId) async {
    final path = '$_base/sections/$orgUnitId/assets';
    final response = await _send(() => _client.get(Uri.parse(path), headers: _headers(accessToken)), path);
    return _read(response, (body) => [
          for (final asset in body['assets'] as List<dynamic>)
            SectionAsset.fromJson(asset as Map<String, dynamic>),
        ]);
  }

  /// Opens a draft for a Section and one of its shift instances
  /// (`POST /handovers`). Refused 409 `HANDOVER_EXISTS` when the pair already
  /// has a live handover.
  Future<ShiftHandover> openHandover(
    String accessToken, {
    required String orgUnitId,
    required String shiftInstanceId,
  }) =>
      _write('POST', '$_base/handovers', accessToken, {
        'orgUnitId': orgUnitId,
        'shiftInstanceId': shiftInstanceId,
      });

  /// One handover with its lines (`GET /handovers/:id`).
  Future<ShiftHandover> fetchHandover(String accessToken, String id) async {
    final path = '$_base/handovers/$id';
    final response = await _send(() => _client.get(Uri.parse(path), headers: _headers(accessToken)), path);
    return _read(response, (body) => ShiftHandover.fromJson(body['handover'] as Map<String, dynamic>));
  }

  /// Writes one Asset's Machine status line whole
  /// (`PUT /handovers/:id/machine-lines/:assetId`); a field left out is
  /// cleared, which is why [line] carries the line's references through.
  Future<ShiftHandover> putMachineLine(
    String accessToken,
    String id, {
    required String assetId,
    required Map<String, Object?> line,
  }) =>
      _write('PUT', '$_base/handovers/$id/machine-lines/$assetId', accessToken, line);

  /// A draft's header fields (`PATCH /handovers/:id`): `changePointsNone`,
  /// `jointWalkDone`, `criticalItems`, `deviationReason`. Only what is sent
  /// changes.
  Future<ShiftHandover> updateHandover(String accessToken, String id, Map<String, Object?> fields) =>
      _write('PATCH', '$_base/handovers/$id', accessToken, fields);

  /// Adds one Change point (`POST /handovers/:id/change-points`).
  Future<ShiftHandover> addChangePoint(
    String accessToken,
    String id, {
    required String dimension,
    required String description,
    required String watchNote,
  }) =>
      _write('POST', '$_base/handovers/$id/change-points', accessToken, {
        'dimension': dimension,
        'description': description,
        'watchNote': watchNote,
      });

  /// Removes one Change point (`DELETE /handovers/:id/change-points/:cpId`).
  Future<ShiftHandover> deleteChangePoint(String accessToken, String id, String changePointId) =>
      _write('DELETE', '$_base/handovers/$id/change-points/$changePointId', accessToken, null);

  /// Links one of the Section's open Actions with its disposition
  /// (`POST /handovers/:id/actions`). A reassignment names its new owner and a
  /// closure says what closed it; the server refuses either without.
  Future<ShiftHandover> linkAction(
    String accessToken,
    String id, {
    required String actionId,
    required String disposition,
    String? ownerEmployeeId,
    String? closureNote,
  }) =>
      _write('POST', '$_base/handovers/$id/actions', accessToken, {
        'actionId': actionId,
        'disposition': disposition,
        'ownerEmployeeId': ?ownerEmployeeId,
        'closureNote': ?closureNote,
      });

  /// Removes one Action's link (`DELETE /handovers/:id/actions/:linkId`).
  Future<ShiftHandover> unlinkAction(String accessToken, String id, String linkId) =>
      _write('DELETE', '$_base/handovers/$id/actions/$linkId', accessToken, null);

  /// Submits a draft (`POST /handovers/:id/submit`). A 409
  /// `INCOMPLETE_HANDOVER` leaves here with its named gaps on
  /// [ProductionApiException.refusal].
  Future<ShiftHandover> submitHandover(String accessToken, String id) =>
      _write('POST', '$_base/handovers/$id/submit', accessToken, null);

  /// The incoming Team Leader's acknowledgement
  /// (`POST /handovers/:id/acknowledge`): an optional note and, for each
  /// watched Change point answered, its result.
  Future<ShiftHandover> acknowledgeHandover(
    String accessToken,
    String id, {
    String? note,
    required List<Map<String, Object?>> changePointResults,
  }) =>
      _write('POST', '$_base/handovers/$id/acknowledge', accessToken, {
        'note': ?note,
        'changePointResults': changePointResults,
      });

  Map<String, String> _headers(String accessToken, {bool json = false}) => {
        'authorization': 'Bearer $accessToken',
        if (json) 'content-type': 'application/json',
      };

  Future<ShiftHandover> _write(String method, String path, String accessToken, Map<String, Object?>? body) async {
    final uri = Uri.parse(path);
    final headers = _headers(accessToken, json: body != null);
    final encoded = body == null ? null : jsonEncode(body);
    final response = await _send(
      () => switch (method) {
        'POST' => _client.post(uri, headers: headers, body: encoded),
        'PUT' => _client.put(uri, headers: headers, body: encoded),
        'PATCH' => _client.patch(uri, headers: headers, body: encoded),
        _ => _client.delete(uri, headers: headers, body: encoded),
      },
      path,
    );
    return _read(response, (answer) => ShiftHandover.fromJson(answer['handover'] as Map<String, dynamic>));
  }

  T _read<T>(http.Response response, T Function(Map<String, dynamic> body) parse) {
    try {
      return parse(jsonDecode(response.body) as Map<String, dynamic>);
    } catch (error) {
      throw ProductionApiException('The API answered with something this app could not read: $error');
    }
  }

  // Mirrors QualityApi._send: a transport failure and a non-2xx answer both
  // leave here as the Module's own exception, carrying the API's own message
  // and code when it sent them.
  static const Duration _requestTimeout = Duration(seconds: 30);

  Future<http.Response> _send(Future<http.Response> Function() send, String path) async {
    final http.Response response;
    try {
      response = await send().timeout(_requestTimeout);
    } on TimeoutException {
      throw ProductionApiException('The API did not answer within ${_requestTimeout.inSeconds} seconds.');
    } catch (error) {
      throw ProductionApiException('Could not reach the API: $error');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      Map<String, dynamic>? body;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) body = decoded;
      } catch (_) {
        body = null;
      }
      final code = body?['code'] as String?;
      throw ProductionApiException(
        body?['message'] as String? ?? 'The API answered ${response.statusCode} for $path.',
        statusCode: response.statusCode,
        code: code,
        refusal: code == 'INCOMPLETE_HANDOVER' && body != null ? HandoverRefusal.fromJson(body) : null,
      );
    }
    return response;
  }
}
