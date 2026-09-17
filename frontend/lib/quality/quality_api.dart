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
/// Today it carries the Module's first slice (issue #203) — the Product
/// catalogue and the Defect code tree, each read by every approved Account and
/// written by an administrator, plus the unit of measure a Product is measured
/// in — and its first behaviour beyond those catalogues (issue #205): the
/// Non-conformance register, one Non-conformance with its quantity history,
/// recording one, raising its severity or recording its containment, and
/// increasing the affected quantity.
///
/// **The Non-conformance register is read per Site**, off
/// `GET /api/quality/sites/:siteId/nonconformances` — the address
/// nonconformance-routes.js publishes, the same shape the action log uses. The
/// Site is the only scope question the address asks (anyone who can see the
/// Site reads its Non-conformances), and every filter — Org Unit and
/// everything beneath it, status, Defect code, Product, severity, a production-
/// day range — is a read filter over an already-visible register.
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
import 'nonconformance.dart';
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

  /// A Site's Non-conformances (`GET /api/quality/sites/:siteId/nonconformances`),
  /// newest first, narrowed by whatever [filters] carries. Anyone who can see
  /// the Site may read it: the register is Site-wide with no Grant filter, and
  /// the Org Unit filter narrows by area rather than by entitlement.
  Future<NonconformanceRegister> fetchNonconformances(
    String accessToken,
    String siteId, {
    NonconformanceFilters filters = const NonconformanceFilters(),
  }) async {
    final path = '/api/quality/sites/$siteId/nonconformances';
    final query = filters.queryParameters;
    final uri = Uri.parse(path).replace(queryParameters: query.isEmpty ? null : query);
    final response = await _send(
      () => _client.get(uri, headers: {'authorization': 'Bearer $accessToken'}),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return NonconformanceRegister(
        nonconformances: [
          for (final row in body['nonconformances'] as List<dynamic>)
            Nonconformance.fromJson(row as Map<String, dynamic>),
        ],
        truncated: body['truncated'] == true,
      );
    } catch (error) {
      throw QualityApiException('The API answered with something this app could not read: $error');
    }
  }

  /// One Non-conformance with its quantity history
  /// (`GET /api/quality/nonconformances/:id`) — what the detail Screen reads.
  Future<Nonconformance> fetchNonconformance(String accessToken, String id) async {
    final path = '/api/quality/nonconformances/$id';
    final response = await _send(
      () => _client.get(Uri.parse(path), headers: {'authorization': 'Bearer $accessToken'}),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return Nonconformance.fromJson(body['nonconformance'] as Map<String, dynamic>);
    } catch (error) {
      throw QualityApiException('The API answered with something this app could not read: $error');
    }
  }

  /// Records a Non-conformance (`POST /api/quality/sites/:siteId/nonconformances`).
  /// It is recorded at [orgUnitId] and needs a Grant that reaches it with
  /// edit; the API refuses anything else (403), and refuses a Product or a
  /// Defect code that is unknown (404), retired (409) or missing (400).
  ///
  /// Only the keys a caller actually decided are sent: the severity is omitted
  /// when the Defect code's own default is the answer, and the optional Asset,
  /// lot reference, detail and containment are omitted when they are empty,
  /// rather than sent as nulls the API would have to interpret.
  Future<Nonconformance> recordNonconformance(
    String accessToken,
    String siteId, {
    required String orgUnitId,
    required String productId,
    required String defectCodeId,
    required String detectionPoint,
    required num quantity,
    String? severity,
    String? assetId,
    String? lotRef,
    String? description,
    String? immediateContainment,
    String? detectedAt,
  }) async {
    final path = '/api/quality/sites/$siteId/nonconformances';
    final body = <String, Object?>{
      'orgUnitId': orgUnitId,
      'productId': productId,
      'defectCodeId': defectCodeId,
      'detectionPoint': detectionPoint,
      'quantity': quantity,
    };
    if (severity != null) body['severity'] = severity;
    if (assetId != null) body['assetId'] = assetId;
    if (lotRef != null && lotRef.trim().isNotEmpty) body['lotRef'] = lotRef.trim();
    if (description != null && description.trim().isNotEmpty) {
      body['description'] = description.trim();
    }
    if (immediateContainment != null && immediateContainment.trim().isNotEmpty) {
      body['immediateContainment'] = immediateContainment.trim();
    }
    if (detectedAt != null) body['detectedAt'] = detectedAt;

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
      return Nonconformance.fromJson(answer['nonconformance'] as Map<String, dynamic>);
    } catch (error) {
      throw QualityApiException('The API answered with something this app could not read: $error');
    }
  }

  /// Raises a Non-conformance's severity, records its immediate containment, or
  /// both (`PATCH /api/quality/nonconformances/:id`). Only the keys present are
  /// sent, the same contract `updateProduct` carries. Lowering the severity is
  /// refused by the API (403) — that decision belongs to a holder of Quality
  /// authority and arrives with a later slice.
  Future<Nonconformance> updateNonconformance(
    String accessToken,
    String id, {
    String? severity,
    String? immediateContainment,
  }) async {
    final path = '/api/quality/nonconformances/$id';
    final body = <String, Object?>{};
    if (severity != null) body['severity'] = severity;
    if (immediateContainment != null) body['immediateContainment'] = immediateContainment.trim();

    final response = await _send(
      () => _client.patch(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode(body),
      ),
      path,
    );
    try {
      final answer = jsonDecode(response.body) as Map<String, dynamic>;
      return Nonconformance.fromJson(answer['nonconformance'] as Map<String, dynamic>);
    } catch (error) {
      throw QualityApiException('The API answered with something this app could not read: $error');
    }
  }

  /// Increases the affected quantity (`POST /api/quality/nonconformances/:id/quantity`),
  /// keeping what it was before. The API refuses a decrease — and a change that
  /// changes nothing — with 409; this call is not the guard against either.
  Future<Nonconformance> increaseNonconformanceQuantity(
    String accessToken,
    String id, {
    required num quantity,
    String? note,
  }) async {
    final path = '/api/quality/nonconformances/$id/quantity';
    final body = <String, Object?>{'quantity': quantity};
    if (note != null && note.trim().isNotEmpty) body['note'] = note.trim();
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
      return Nonconformance.fromJson(answer['nonconformance'] as Map<String, dynamic>);
    } catch (error) {
      throw QualityApiException('The API answered with something this app could not read: $error');
    }
  }

  /// Records a Disposition of a Non-conformance's product (issue #206) —
  /// scrap, rework with the minutes it took, or return to the supplier
  /// (`POST /api/quality/nonconformances/:id/dispositions`). It needs the same
  /// access as recording (a write Grant reaching the record's Org Unit); the
  /// API refuses anything else (403), refuses more than what is still
  /// undecided (409), and refuses minutes on anything that is not a rework
  /// (400) — this call is not the guard against any of them.
  Future<Nonconformance> recordDisposition(
    String accessToken,
    String id, {
    required String dispositionType,
    required num quantity,
    num? reworkMinutes,
    String? note,
  }) {
    final body = <String, Object?>{
      'dispositionType': dispositionType,
      'quantity': quantity,
    };
    if (reworkMinutes != null) body['reworkMinutes'] = reworkMinutes;
    if (note != null && note.trim().isNotEmpty) body['note'] = note.trim();
    return _postNonconformance(accessToken, '/api/quality/nonconformances/$id/dispositions', body);
  }

  /// Grants a Concession (issue #206) — a Disposition to use the product as it
  /// is, which accepts it rather than dealing with it
  /// (`POST /api/quality/nonconformances/:id/concession`). It needs Quality
  /// authority at the record's Org Unit and the API refuses it with a 403
  /// otherwise; the reference it was granted under and the note saying why are
  /// both required (400 without either), and the granting Account comes back
  /// on the record as `decidedByAccountName`.
  Future<Nonconformance> grantConcession(
    String accessToken,
    String id, {
    required num quantity,
    required String reference,
    required String note,
  }) =>
      _postNonconformance(accessToken, '/api/quality/nonconformances/$id/concession', {
        'quantity': quantity,
        'reference': reference.trim(),
        'note': note.trim(),
      });

  /// Lowers a Non-conformance's severity (issue #206)
  /// (`POST /api/quality/nonconformances/:id/lower-severity`). Quality
  /// authority at the record's Org Unit and a note are both required — the API
  /// refuses without either (403 and 400) — and the change comes back on the
  /// record as a correction carrying who made it, when, and the note.
  Future<Nonconformance> lowerNonconformanceSeverity(
    String accessToken,
    String id, {
    required String severity,
    required String note,
  }) =>
      _postNonconformance(accessToken, '/api/quality/nonconformances/$id/lower-severity', {
        'severity': severity,
        'note': note.trim(),
      });

  /// Reopens a closed Non-conformance (issue #206)
  /// (`POST /api/quality/nonconformances/:id/reopen`). Quality authority and a
  /// note are both required, and only a closed record can be reopened — the
  /// API refuses anything else with a 409.
  Future<Nonconformance> reopenNonconformance(
    String accessToken,
    String id, {
    required String note,
  }) =>
      _postNonconformance(accessToken, '/api/quality/nonconformances/$id/reopen', {
        'note': note.trim(),
      });

  /// Cancels a Non-conformance recorded in error (issue #206)
  /// (`POST /api/quality/nonconformances/:id/cancel`). Quality authority and a
  /// note are both required, and a cancelled record accepts no further
  /// Dispositions or quantity changes (409).
  Future<Nonconformance> cancelNonconformance(
    String accessToken,
    String id, {
    required String note,
  }) =>
      _postNonconformance(accessToken, '/api/quality/nonconformances/$id/cancel', {
        'note': note.trim(),
      });

  // The five writes above answer with the whole record — its dispositions, its
  // corrections and its quantity history included — the way every other write
  // in this Module does, so a caller never has to patch its own copy.
  Future<Nonconformance> _postNonconformance(
    String accessToken,
    String path,
    Map<String, Object?> body,
  ) async {
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
      return Nonconformance.fromJson(answer['nonconformance'] as Map<String, dynamic>);
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
