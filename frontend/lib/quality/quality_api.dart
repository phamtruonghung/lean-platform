/// The Quality Module's HTTP surface, from the Flutter app's side — the
/// client half of `backend/src/modules/quality/` (ADR-0012's mirror of
/// ADR-0006).
///
/// Its own class inside its own Module's folder, rather than a second
/// `lib/*_api.dart` at the root: `lib/people_api.dart` sits there for
/// historical reasons (it predates `lib/people/`), and copying that is not the
/// shape ADR-0012 asks for — `maintenance_api.dart` and `actions_api.dart`
/// are the pattern. Its own exception type too, for the same reason
/// `MaintenanceApiException` is its own: a caller can tell which Module's
/// address failed without reading the message.
///
/// Today it carries the Module's first slice (issue #203): the Product
/// catalogue and the Defect code tree, each read by every approved Account and
/// written by an administrator, plus the unit of measure a Product is measured
/// in.
///
/// **The unit of measure comes from Maintenance's address, deliberately.**
/// `GET /api/maintenance/units-of-measure` is the baseline's own reference
/// table, published there since issue #79 and read by the Part form (#80)
/// off the same address. A Product is measured in the same units, so this
/// reads that address with [fetchUnitsOfMeasure] rather than republishing the
/// same table under `/api/quality`: one endpoint over one table, and one
/// `UnitOfMeasure` model — reached through Maintenance's own client entry
/// point (`lib/maintenance/maintenance.dart`) rather than by importing the
/// file it happens to live in. The prefix is an address kept, not a claim
/// about which Module owns the units, the same note `people/floor-routes.js`
/// makes about the floor device's `/api/maintenance` addresses.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../maintenance/maintenance.dart';
import 'defect_code.dart';
import 'product.dart';

/// The request could not be answered at all. Deliberately its own type rather
/// than People's or Maintenance's: ADR-0006's third clause keeps generic
/// plumbing on each Module's own side, and the client mirrors it.
class QualityApiException implements Exception {
  QualityApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class QualityApi {
  QualityApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// The Product catalogue (`GET /api/quality/products`). Active Products
  /// only, unless [includeInactive] asks for the retired ones too — which is
  /// what the catalogue's own Screen asks for, so a deactivated Product can be
  /// reached and reactivated.
  ///
  /// [search] narrows by code or name, the two things a caller has to hand
  /// when they are looking for a Product to record against. The address
  /// supports it because issue #203's own criterion asks for it ("any active
  /// Account can list and search Products by code or name"); the Screen itself
  /// carries no filter control yet, since the sweep that adds one to the
  /// catalogues is a different ticket.
  Future<List<Product>> fetchProducts(
    String accessToken, {
    String? search,
    bool includeInactive = false,
  }) async {
    const path = '/api/quality/products';
    final query = <String, String>{
      if (includeInactive) 'includeInactive': 'true',
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
    };
    final uri = Uri.parse(path).replace(queryParameters: query.isEmpty ? null : query);
    final response = await _send(
      () => _client.get(uri, headers: {'authorization': 'Bearer $accessToken'}),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return [
        for (final product in body['products'] as List<dynamic>)
          Product.fromJson(product as Map<String, dynamic>),
      ];
    } catch (error) {
      throw QualityApiException('The API answered with something this app could not read: $error');
    }
  }

  /// Defines a new Product (`POST /api/quality/products`, administrator only).
  /// Its unit of measure is one the plant uses; the API refuses anything else
  /// (400), and refuses a code already taken (409).
  Future<Product> createProduct(
    String accessToken, {
    required String code,
    required String name,
    required String uomCode,
  }) async {
    const path = '/api/quality/products';
    final response = await _send(
      () => _client.post(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode({'code': code, 'name': name, 'uomCode': uomCode}),
      ),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return Product.fromJson(body['product'] as Map<String, dynamic>);
    } catch (error) {
      throw QualityApiException('The API answered with something this app could not read: $error');
    }
  }

  /// Corrects a Product (`PATCH /api/quality/products/:id`, administrator
  /// only). [changes] carries only the keys that actually changed — the name
  /// and whether it is still in use; the API refuses a `code` or a `uomCode`
  /// rather than quietly rewriting either.
  Future<Product> updateProduct(
    String accessToken,
    String id,
    Map<String, Object?> changes,
  ) async {
    final path = '/api/quality/products/$id';
    final response = await _send(
      () => _client.patch(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode(changes),
      ),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return Product.fromJson(body['product'] as Map<String, dynamic>);
    } catch (error) {
      throw QualityApiException('The API answered with something this app could not read: $error');
    }
  }

  /// The Defect code tree, flat: each row names its own `parentId`, its
  /// category and the severity a Non-conformance recorded against it starts
  /// at. Active codes only, unless [includeInactive] asks for the retired ones
  /// too.
  Future<List<DefectCode>> fetchDefectCodes(
    String accessToken, {
    bool includeInactive = false,
  }) async {
    final path = includeInactive
        ? '/api/quality/defect-codes?includeInactive=true'
        : '/api/quality/defect-codes';
    final response = await _send(
      () => _client.get(Uri.parse(path), headers: {'authorization': 'Bearer $accessToken'}),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return [
        for (final code in body['defectCodes'] as List<dynamic>)
          DefectCode.fromJson(code as Map<String, dynamic>),
      ];
    } catch (error) {
      throw QualityApiException('The API answered with something this app could not read: $error');
    }
  }

  /// Defines a new Defect code (`POST /api/quality/defect-codes`,
  /// administrator only). [parentId] is optional — a code with none sits at
  /// the top of the tree. The API refuses a code already taken (409), a parent
  /// that does not exist (404) and a parent that would make the tree cyclic
  /// (400); this call is not the guard against any of them.
  Future<DefectCode> createDefectCode(
    String accessToken, {
    required String code,
    required String name,
    required String category,
    required String defaultSeverity,
    String? parentId,
  }) async {
    const path = '/api/quality/defect-codes';
    // The parent is omitted entirely when none was chosen rather than sent as
    // a null: a code at the top of the tree is one the API is never asked to
    // place anywhere.
    final body = <String, Object?>{
      'code': code,
      'name': name,
      'category': category,
      'defaultSeverity': defaultSeverity,
    };
    if (parentId != null) body['parentId'] = parentId;
    final response = await _send(
      () => _client.post(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode(body),
      ),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return DefectCode.fromJson(body['defectCode'] as Map<String, dynamic>);
    } catch (error) {
      throw QualityApiException('The API answered with something this app could not read: $error');
    }
  }

  /// Corrects a Defect code (`PATCH /api/quality/defect-codes/:id`,
  /// administrator only). [changes] carries only the keys that actually
  /// changed — its name, its category, its default severity, where it sits in
  /// the tree (`parentId`, null to detach it) and whether it is still in use.
  /// Its `code` is refused by the API rather than quietly rewritten.
  Future<DefectCode> updateDefectCode(
    String accessToken,
    String id,
    Map<String, Object?> changes,
  ) async {
    final path = '/api/quality/defect-codes/$id';
    final response = await _send(
      () => _client.patch(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode(changes),
      ),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return DefectCode.fromJson(body['defectCode'] as Map<String, dynamic>);
    } catch (error) {
      throw QualityApiException('The API answered with something this app could not read: $error');
    }
  }

  /// The units of measure the plant uses, read from Maintenance's own address
  /// — see this file's own header for why it is not republished under
  /// `/api/quality`.
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
          UnitOfMeasure.fromJson(unit as Map<String, dynamic>),
      ];
    } catch (error) {
      throw QualityApiException('The API answered with something this app could not read: $error');
    }
  }

  // Mirrors MaintenanceApi._send: a transport failure and a non-2xx answer
  // both leave here as the Module's own exception, carrying the API's own
  // message when it sent one (so a 409's sentence reaches the form that
  // caused it rather than being replaced by a status code).
  Future<http.Response> _send(Future<http.Response> Function() send, String path) async {
    final http.Response response;
    try {
      response = await send();
    } catch (error) {
      throw QualityApiException('Could not reach the API: $error');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw QualityApiException(
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
