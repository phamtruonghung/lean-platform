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
