/// The KPI Module's HTTP surface, from the Flutter app's side — the client half
/// of `backend/src/modules/kpi/` (ADR-0012's mirror of ADR-0006, ADR-0055),
/// mounted by the server under `/api/kpi`.
///
/// Query parameters and bodies are snake_case, exactly as the routes read them
/// (unlike the older Modules' camelCase). Every call carries `site_id`: the
/// server asks the Site's root Org Unit whether the caller may act.
///
/// Its own exception type, for the reason `ProductionApiException` is its own.
/// A refusal is surfaced as the API's own `message` (`Outside the caller's
/// granted Org Units`), never as "the API answered 403".
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'kpi_catalogue.dart';

class KpiApiException implements Exception {
  KpiApiException(this.message, {this.statusCode, this.code});

  final String message;
  final int? statusCode;

  /// The API's own machine-readable code, when it sent one
  /// (`OUTSIDE_GRANTED_ORG_UNITS`).
  final String? code;

  @override
  String toString() => message;
}

class KpiApi {
  KpiApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String _base = '/api/kpi';

  /// The catalogue as it reads on one day (`GET /catalogue`). Without [date]
  /// the server answers the Site's own today in `review_date`.
  Future<KpiCatalogue> fetchCatalogue(String accessToken, {required String siteId, String? date}) async {
    final path = '$_base/catalogue';
    final uri = Uri.parse(path).replace(queryParameters: {'site_id': siteId, 'date': ?date});
    final response = await _send(() => _client.get(uri, headers: _headers(accessToken)), path);
    return _read(response, KpiCatalogue.fromJson);
  }

  /// Adds a KPI (`POST /catalogue`); answers the server's `kpi_id`. A
  /// duplicate name is a 409.
  Future<int> addKpi(
    String accessToken, {
    required String siteId,
    required String kpi,
    required String title,
    required String unit,
    required String direction,
    required int decimals,
    String? valueMeasure,
  }) async {
    final path = '$_base/catalogue';
    final response = await _send(
      () => _client.post(
        Uri.parse(path),
        headers: _headers(accessToken, json: true),
        body: jsonEncode({
          'site_id': siteId,
          'kpi': kpi,
          'title': title,
          'unit': unit,
          'direction': direction,
          'decimals': decimals,
          'value_measure': valueMeasure,
        }),
      ),
      path,
    );
    return _read(response, (body) => (body['kpi_id'] as num).toInt());
  }

  /// One KPI's Targets (`GET /targets`): in force today, and the history.
  Future<KpiTargets> fetchTargets(String accessToken, {required String siteId, required int kpiId}) async {
    final path = '$_base/targets';
    final uri = Uri.parse(path).replace(queryParameters: {'site_id': siteId, 'kpi_id': '$kpiId'});
    final response = await _send(() => _client.get(uri, headers: _headers(accessToken)), path);
    return _read(response, KpiTargets.fromJson);
  }

  /// Appends a Target (`POST /targets`). [target] null means "no target from
  /// [validFrom] on": the key is always sent, because the route refuses a body
  /// without it.
  Future<int> addTarget(
    String accessToken, {
    required String siteId,
    required int kpiId,
    required String grain,
    required String validFrom,
    required double? target,
    String? note,
  }) async {
    final path = '$_base/targets';
    final response = await _send(
      () => _client.post(
        Uri.parse(path),
        headers: _headers(accessToken, json: true),
        body: jsonEncode({
          'site_id': siteId,
          'kpi_id': kpiId,
          'grain': grain,
          'valid_from': validFrom,
          'target': target,
          'note': note,
        }),
      ),
      path,
    );
    return _read(response, (body) => (body['target_id'] as num).toInt());
  }

  /// One day's KPI Review (`GET /review`). Without [date] the server answers
  /// the Site's last working day, and `site_today` carries the Site's own today.
  Future<KpiReview> fetchReview(String accessToken, {required String siteId, String? date}) async {
    final path = '$_base/review';
    final uri = Uri.parse(path).replace(queryParameters: {'site_id': siteId, 'date': ?date});
    final response = await _send(() => _client.get(uri, headers: _headers(accessToken)), path);
    return _read(response, KpiReview.fromJson);
  }

  /// Saves a day's KPI Review, all or nothing (`POST /review`); answers how
  /// many entries the server saved.
  Future<int> saveReview(
    String accessToken, {
    required String siteId,
    required String date,
    required List<ReviewEntryInput> entries,
  }) async {
    final path = '$_base/review';
    final response = await _send(
      () => _client.post(
        Uri.parse(path),
        headers: _headers(accessToken, json: true),
        body: jsonEncode({
          'site_id': siteId,
          'date': date,
          'entries': [for (final entry in entries) entry.toJson()],
        }),
      ),
      path,
    );
    return _read(response, (body) => (body['saved'] as num).toInt());
  }

  Map<String, String> _headers(String accessToken, {bool json = false}) => {
        'authorization': 'Bearer $accessToken',
        if (json) 'content-type': 'application/json',
      };

  T _read<T>(http.Response response, T Function(Map<String, dynamic> body) parse) {
    try {
      return parse(jsonDecode(response.body) as Map<String, dynamic>);
    } catch (error) {
      throw KpiApiException('The API answered with something this app could not read: $error');
    }
  }

  // Mirrors ProductionApi._send: a transport failure and a non-2xx answer both
  // leave here as the Module's own exception, carrying the API's own message
  // and code when it sent them.
  static const Duration _requestTimeout = Duration(seconds: 30);

  Future<http.Response> _send(Future<http.Response> Function() send, String path) async {
    final http.Response response;
    try {
      response = await send().timeout(_requestTimeout);
    } on TimeoutException {
      throw KpiApiException('The API did not answer within ${_requestTimeout.inSeconds} seconds.');
    } catch (error) {
      throw KpiApiException('Could not reach the API: $error');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      Map<String, dynamic>? body;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) body = decoded;
      } catch (_) {
        body = null;
      }
      throw KpiApiException(
        body?['message'] as String? ?? 'The API answered ${response.statusCode} for $path.',
        statusCode: response.statusCode,
        code: body?['code'] as String?,
      );
    }
    return response;
  }
}
