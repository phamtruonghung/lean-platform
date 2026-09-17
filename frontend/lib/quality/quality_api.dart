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
import 'customer.dart';
import 'customer_complaint.dart';
import 'defect_code.dart';
import 'nonconformance.dart';
import 'product.dart';
import 'supplier.dart';
import 'supplier_ncr.dart';

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

  /// The two catalogues and the recording as the shared floor device sees them
  /// (issue #207, ADR-0016) — `GET /api/quality/floor/products`,
  /// `GET /api/quality/floor/defect-codes` and
  /// `POST /api/quality/floor/nonconformances`.
  ///
  /// These are the Module's own `/api/quality/floor/...` addresses, and they
  /// are the device's door rather than a second credential on the Account
  /// routes: a device presents its own credential and, to write, an individual
  /// identification — no bearer token is involved, because a device at a
  /// machine is not a person and most of a plant cannot sign in (CONTEXT.md).
  /// The catalogues are read through this door because a Non-conformance names
  /// a Product and a Defect code, and ADR-0023's rule is that a value with a
  /// known set is chosen rather than typed.
  Future<List<Product>> fetchFloorProducts(String deviceCredential) async {
    const path = '/api/quality/floor/products';
    final response = await _send(
      () => _client.get(Uri.parse(path), headers: {'x-floor-device': deviceCredential}),
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

  /// The Defect code tree as the device sees it — the same read as
  /// [fetchProducts] above, over the other catalogue.
  Future<List<DefectCode>> fetchFloorDefectCodes(String deviceCredential) async {
    const path = '/api/quality/floor/defect-codes';
    final response = await _send(
      () => _client.get(Uri.parse(path), headers: {'x-floor-device': deviceCredential}),
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

  /// Records a Non-conformance at the shared floor device
  /// (`POST /api/quality/floor/nonconformances`, issue #207). The device
  /// credential says which machine it is, [identification] says which Employee
  /// is standing at it, and the identified Employee comes back as the record's
  /// detected-by.
  ///
  /// [orgUnitId] is where the record is filed — the device's own Org Unit, or
  /// anything beneath it; the API refuses one outside that reach with a 403.
  /// A missing, invalid or expired identification is a 401, and every field,
  /// severity and quantity rule is the same as the Account door's
  /// [recordNonconformance], because both call the same service.
  Future<Nonconformance> recordFloorNonconformance(
    String deviceCredential,
    String identification, {
    required String orgUnitId,
    required String productId,
    required String defectCodeId,
    required String detectionPoint,
    required num quantity,
    String? severity,
    String? lotRef,
    String? description,
    String? immediateContainment,
  }) async {
    const path = '/api/quality/floor/nonconformances';
    final body = <String, Object?>{
      'orgUnitId': orgUnitId,
      'productId': productId,
      'defectCodeId': defectCodeId,
      'detectionPoint': detectionPoint,
      'quantity': quantity,
    };
    if (severity != null) body['severity'] = severity;
    if (lotRef != null && lotRef.trim().isNotEmpty) body['lotRef'] = lotRef.trim();
    if (description != null && description.trim().isNotEmpty) {
      body['description'] = description.trim();
    }
    if (immediateContainment != null && immediateContainment.trim().isNotEmpty) {
      body['immediateContainment'] = immediateContainment.trim();
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

  // -------------------------------------------------------------------------
  // Customers and customer complaints (issue #214)
  // -------------------------------------------------------------------------

  /// The Customer list (`GET /api/quality/customers`), readable and searchable
  /// by any approved Account. Active Customers only, unless [includeInactive]
  /// asks for the retired ones too — which is what the list's own Screen asks
  /// for, so a deactivated Customer can be reached and reactivated.
  ///
  /// [search] narrows by code or name on the server; the Screen's own filter
  /// box matches the rows it already holds instead, and issues no request
  /// (issue #187's two controls).
  Future<List<Customer>> fetchCustomers(
    String accessToken, {
    String? search,
    bool includeInactive = false,
  }) async {
    const path = '/api/quality/customers';
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
        for (final customer in body['customers'] as List<dynamic>)
          Customer.fromJson(customer as Map<String, dynamic>),
      ];
    } catch (error) {
      throw QualityApiException('The API answered with something this app could not read: $error');
    }
  }

  /// Defines a Customer (`POST /api/quality/customers`, administrator only).
  /// A code already taken is refused (409) with the service's own sentence.
  Future<Customer> createCustomer(
    String accessToken, {
    required String code,
    required String name,
    String? contactEmail,
  }) async {
    const path = '/api/quality/customers';
    final body = <String, Object?>{'code': code, 'name': name};
    if (contactEmail != null && contactEmail.trim().isNotEmpty) {
      body['contactEmail'] = contactEmail.trim();
    }
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
      return Customer.fromJson(answer['customer'] as Map<String, dynamic>);
    } catch (error) {
      throw QualityApiException('The API answered with something this app could not read: $error');
    }
  }

  /// Corrects a Customer (`PATCH /api/quality/customers/:id`, administrator
  /// only): only the keys in [changes], which is `updateCustomer`'s own
  /// `hasOwnProperty` contract at the other end. A code is refused (400).
  Future<Customer> updateCustomer(
    String accessToken,
    String id,
    Map<String, Object?> changes,
  ) async {
    final path = '/api/quality/customers/$id';
    final response = await _send(
      () => _client.patch(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode(changes),
      ),
      path,
    );
    try {
      final answer = jsonDecode(response.body) as Map<String, dynamic>;
      return Customer.fromJson(answer['customer'] as Map<String, dynamic>);
    } catch (error) {
      throw QualityApiException('The API answered with something this app could not read: $error');
    }
  }

  /// A Site's complaints (`GET /api/quality/sites/:siteId/complaints`), newest
  /// first, narrowed by the status and the Org Unit the register's filters
  /// carry. Visible to anyone who can see the Site, the same rule the
  /// Non-conformance register follows.
  Future<ComplaintRegister> fetchComplaints(
    String accessToken,
    String siteId, {
    ComplaintFilters filters = const ComplaintFilters(),
  }) async {
    final path = '/api/quality/sites/$siteId/complaints';
    final query = filters.queryParameters;
    final uri = Uri.parse(path).replace(queryParameters: query.isEmpty ? null : query);
    final response = await _send(
      () => _client.get(uri, headers: {'authorization': 'Bearer $accessToken'}),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return ComplaintRegister(
        complaints: [
          for (final row in body['complaints'] as List<dynamic>)
            CustomerComplaint.fromJson(row as Map<String, dynamic>),
        ],
        truncated: body['truncated'] == true,
      );
    } catch (error) {
      throw QualityApiException('The API answered with something this app could not read: $error');
    }
  }

  /// One complaint with the Customer, the Product, the Defect code and the
  /// Non-conformance controlling the complained-of product
  /// (`GET /api/quality/complaints/:id`) — what the detail Screen reads.
  Future<CustomerComplaint> fetchComplaint(String accessToken, String id) async {
    final path = '/api/quality/complaints/$id';
    final response = await _send(
      () => _client.get(Uri.parse(path), headers: {'authorization': 'Bearer $accessToken'}),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return CustomerComplaint.fromJson(body['complaint'] as Map<String, dynamic>);
    } catch (error) {
      throw QualityApiException('The API answered with something this app could not read: $error');
    }
  }

  /// Records a complaint (`POST /api/quality/sites/:siteId/complaints`) at
  /// [orgUnitId], which needs a Grant reaching it with edit — the API refuses
  /// anything else (403) and refuses a Customer, Product or Defect code that is
  /// unknown (404), retired (409) or missing (400).
  ///
  /// Only what the caller decided is sent: a null field is absent rather than
  /// sent as a null the API would have to interpret.
  Future<CustomerComplaint> recordComplaint(
    String accessToken,
    String siteId, {
    required String orgUnitId,
    required String customerId,
    required String productId,
    required String description,
    String? defectCodeId,
    num? quantity,
    String? uomCode,
    String? responseDueDate,
    bool isWarranty = false,
    String? complaintType,
    String? severity,
    String? customerRef,
    String? lotRef,
  }) async {
    final path = '/api/quality/sites/$siteId/complaints';
    final body = <String, Object?>{
      'orgUnitId': orgUnitId,
      'customerId': customerId,
      'productId': productId,
      'description': description,
      'isWarranty': isWarranty,
    };
    if (defectCodeId != null) body['defectCodeId'] = defectCodeId;
    if (quantity != null) body['quantity'] = quantity;
    if (uomCode != null && uomCode.trim().isNotEmpty) body['uomCode'] = uomCode.trim();
    if (responseDueDate != null) body['responseDueDate'] = responseDueDate;
    if (complaintType != null) body['complaintType'] = complaintType;
    if (severity != null) body['severity'] = severity;
    if (customerRef != null && customerRef.trim().isNotEmpty) {
      body['customerRef'] = customerRef.trim();
    }
    if (lotRef != null && lotRef.trim().isNotEmpty) body['lotRef'] = lotRef.trim();

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
      return CustomerComplaint.fromJson(answer['complaint'] as Map<String, dynamic>);
    } catch (error) {
      throw QualityApiException('The API answered with something this app could not read: $error');
    }
  }

  /// Closes a complaint with the response the customer was given
  /// (`POST /api/quality/complaints/:id/respond`). The note is required: the
  /// API refuses a complaint closed with nothing said back (400), and refuses
  /// one that is already closed (409).
  Future<CustomerComplaint> closeComplaint(
    String accessToken,
    String id, {
    required String responseNote,
  }) async {
    final path = '/api/quality/complaints/$id/respond';
    final response = await _send(
      () => _client.post(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode({'responseNote': responseNote}),
      ),
      path,
    );
    try {
      final answer = jsonDecode(response.body) as Map<String, dynamic>;
      return CustomerComplaint.fromJson(answer['complaint'] as Map<String, dynamic>);
    } catch (error) {
      throw QualityApiException('The API answered with something this app could not read: $error');
    }
  }

  /// Records the Non-conformance that controls the complained-of product
  /// (`POST /api/quality/complaints/:id/nonconformance`) — `detection_point =
  /// customer`, the complaint's Product, and its Defect code, quantity and
  /// description unless [defectCodeId] or [quantity] name their own (a
  /// complaint may carry neither).
  ///
  /// Answers with both records: the caller is looking at the complaint and
  /// reading the record it just created at the same time.
  Future<(Nonconformance, CustomerComplaint)> recordComplaintNonconformance(
    String accessToken,
    String id, {
    num? quantity,
    String? defectCodeId,
    String? description,
    String? immediateContainment,
    String? lotRef,
    String? severity,
  }) async {
    final path = '/api/quality/complaints/$id/nonconformance';
    final body = <String, Object?>{};
    if (quantity != null) body['quantity'] = quantity;
    if (defectCodeId != null) body['defectCodeId'] = defectCodeId;
    if (description != null && description.trim().isNotEmpty) {
      body['description'] = description.trim();
    }
    if (immediateContainment != null && immediateContainment.trim().isNotEmpty) {
      body['immediateContainment'] = immediateContainment.trim();
    }
    if (lotRef != null && lotRef.trim().isNotEmpty) body['lotRef'] = lotRef.trim();
    if (severity != null) body['severity'] = severity;

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
      return (
        Nonconformance.fromJson(answer['nonconformance'] as Map<String, dynamic>),
        CustomerComplaint.fromJson(answer['complaint'] as Map<String, dynamic>),
      );
    } catch (error) {
      throw QualityApiException('The API answered with something this app could not read: $error');
    }
  }

  /// Links a Non-conformance that already exists to the complaint
  /// (`POST /api/quality/complaints/:id/link`). The API refuses a complaint that
  /// already names one (409) and a Non-conformance about another Product (409),
  /// which is why the picker offers only this complaint's own Product.
  Future<CustomerComplaint> linkComplaintNonconformance(
    String accessToken,
    String id, {
    required String nonconformanceId,
  }) async {
    final path = '/api/quality/complaints/$id/link';
    final response = await _send(
      () => _client.post(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode({'nonconformanceId': nonconformanceId}),
      ),
      path,
    );
    try {
      final answer = jsonDecode(response.body) as Map<String, dynamic>;
      return CustomerComplaint.fromJson(answer['complaint'] as Map<String, dynamic>);
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

  // -------------------------------------------------------------------------
  // Suppliers and supplier NCRs (issue #215)
  // -------------------------------------------------------------------------

  /// The Supplier list (`GET /api/quality/suppliers`), readable and searchable
  /// by any approved Account. Active Suppliers only, unless [includeInactive]
  /// asks for the retired ones too — which is what the list's own Screen asks
  /// for, so a deactivated Supplier can be reached and reactivated.
  ///
  /// [search] narrows by code or name on the server; the Screen's own filter box
  /// matches the rows it already holds instead, and issues no request (issue
  /// #187's two controls).
  Future<List<Supplier>> fetchSuppliers(
    String accessToken, {
    String? search,
    bool includeInactive = false,
  }) async {
    const path = '/api/quality/suppliers';
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
        for (final supplier in body['suppliers'] as List<dynamic>)
          Supplier.fromJson(supplier as Map<String, dynamic>),
      ];
    } catch (error) {
      throw QualityApiException('The API answered with something this app could not read: $error');
    }
  }

  /// Defines a Supplier (`POST /api/quality/suppliers`, administrator only).
  /// A code already taken is refused (409) with the service's own sentence.
  Future<Supplier> createSupplier(
    String accessToken, {
    required String code,
    required String name,
    String? contactEmail,
  }) async {
    const path = '/api/quality/suppliers';
    final body = <String, Object?>{'code': code, 'name': name};
    if (contactEmail != null && contactEmail.trim().isNotEmpty) {
      body['contactEmail'] = contactEmail.trim();
    }
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
      return Supplier.fromJson(answer['supplier'] as Map<String, dynamic>);
    } catch (error) {
      throw QualityApiException('The API answered with something this app could not read: $error');
    }
  }

  /// Corrects a Supplier (`PATCH /api/quality/suppliers/:id`, administrator
  /// only): only the keys in [changes], which is `updateSupplier`'s own
  /// `hasOwnProperty` contract at the other end. A code is refused (400).
  Future<Supplier> updateSupplier(
    String accessToken,
    String id,
    Map<String, Object?> changes,
  ) async {
    final path = '/api/quality/suppliers/$id';
    final response = await _send(
      () => _client.patch(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode(changes),
      ),
      path,
    );
    try {
      final answer = jsonDecode(response.body) as Map<String, dynamic>;
      return Supplier.fromJson(answer['supplier'] as Map<String, dynamic>);
    } catch (error) {
      throw QualityApiException('The API answered with something this app could not read: $error');
    }
  }

  /// A Site's supplier NCRs (`GET /api/quality/sites/:siteId/supplier-ncrs`),
  /// newest first, narrowed by the Supplier, the status and the Org Unit the
  /// register's filters carry. Visible to anyone who can see the Site, the same
  /// rule the Non-conformance and complaint registers follow.
  Future<SupplierNcrRegister> fetchSupplierNcrs(
    String accessToken,
    String siteId, {
    SupplierNcrFilters filters = const SupplierNcrFilters(),
  }) async {
    final path = '/api/quality/sites/$siteId/supplier-ncrs';
    final query = filters.queryParameters;
    final uri = Uri.parse(path).replace(queryParameters: query.isEmpty ? null : query);
    final response = await _send(
      () => _client.get(uri, headers: {'authorization': 'Bearer $accessToken'}),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return SupplierNcrRegister(
        supplierNcrs: [
          for (final row in body['supplierNcrs'] as List<dynamic>)
            SupplierNcr.fromJson(row as Map<String, dynamic>),
        ],
        truncated: body['truncated'] == true,
      );
    } catch (error) {
      throw QualityApiException('The API answered with something this app could not read: $error');
    }
  }

  /// One supplier NCR with the Supplier, the Product, the Defect code and the
  /// Non-conformance that controls the received lot
  /// (`GET /api/quality/supplier-ncrs/:id`) — what the detail Screen reads.
  Future<SupplierNcr> fetchSupplierNcr(String accessToken, String id) async {
    final path = '/api/quality/supplier-ncrs/$id';
    final response = await _send(
      () => _client.get(Uri.parse(path), headers: {'authorization': 'Bearer $accessToken'}),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return SupplierNcr.fromJson(body['supplierNcr'] as Map<String, dynamic>);
    } catch (error) {
      throw QualityApiException('The API answered with something this app could not read: $error');
    }
  }

  /// Records a supplier NCR (`POST /api/quality/sites/:siteId/supplier-ncrs`).
  /// The Supplier, the quantity and its unit are what an NCR cannot be without;
  /// the Product, the Defect code, the references and the due day are optional,
  /// and a retired Product or Defect code is refused (409) by the service.
  Future<SupplierNcr> recordSupplierNcr(
    String accessToken,
    String siteId, {
    required String orgUnitId,
    required String supplierId,
    required num quantity,
    required String uomCode,
    String? productId,
    String? defectCodeId,
    String? incomingLotRef,
    String? purchaseRef,
    String? description,
    String? responseDueDate,
  }) async {
    final path = '/api/quality/sites/$siteId/supplier-ncrs';
    final body = <String, Object?>{
      'orgUnitId': orgUnitId,
      'supplierId': supplierId,
      'quantity': quantity,
      'uomCode': uomCode,
    };
    if (productId != null && productId.isNotEmpty) body['productId'] = productId;
    if (defectCodeId != null && defectCodeId.isNotEmpty) body['defectCodeId'] = defectCodeId;
    if (incomingLotRef != null && incomingLotRef.trim().isNotEmpty) {
      body['incomingLotRef'] = incomingLotRef.trim();
    }
    if (purchaseRef != null && purchaseRef.trim().isNotEmpty) {
      body['purchaseRef'] = purchaseRef.trim();
    }
    if (description != null && description.trim().isNotEmpty) {
      body['description'] = description.trim();
    }
    if (responseDueDate != null && responseDueDate.trim().isNotEmpty) {
      body['responseDueDate'] = responseDueDate.trim();
    }
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
      return SupplierNcr.fromJson(answer['supplierNcr'] as Map<String, dynamic>);
    } catch (error) {
      throw QualityApiException('The API answered with something this app could not read: $error');
    }
  }

  /// Records the Supplier's disposition and what was recovered
  /// (`POST /api/quality/supplier-ncrs/:id/disposition`). The disposition is
  /// required and comes from the baseline's own five, and a negative recovery
  /// is refused (400).
  Future<SupplierNcr> recordSupplierNcrDisposition(
    String accessToken,
    String id, {
    required String disposition,
    num? costRecovered,
    String? currency,
  }) async {
    final path = '/api/quality/supplier-ncrs/$id/disposition';
    final body = <String, Object?>{'disposition': disposition};
    if (costRecovered != null) body['costRecovered'] = costRecovered;
    if (currency != null && currency.trim().isNotEmpty) body['currency'] = currency.trim();
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
      return SupplierNcr.fromJson(answer['supplierNcr'] as Map<String, dynamic>);
    } catch (error) {
      throw QualityApiException('The API answered with something this app could not read: $error');
    }
  }

  /// Closes a supplier NCR (`POST /api/quality/supplier-ncrs/:id/close`) — the
  /// one transition this slice has. A second close is refused (409).
  Future<SupplierNcr> closeSupplierNcr(String accessToken, String id) async {
    final path = '/api/quality/supplier-ncrs/$id/close';
    final response = await _send(
      () => _client.post(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode(<String, Object?>{}),
      ),
      path,
    );
    try {
      final answer = jsonDecode(response.body) as Map<String, dynamic>;
      return SupplierNcr.fromJson(answer['supplierNcr'] as Map<String, dynamic>);
    } catch (error) {
      throw QualityApiException('The API answered with something this app could not read: $error');
    }
  }

  /// Records the Non-conformance that controls the received lot
  /// (`POST /api/quality/supplier-ncrs/:id/nonconformance`) — `detection_point =
  /// incoming`, the NCR's Product and Defect code where it carries them, and the
  /// ones named in [productId] and [defectCodeId] where it does not.
  ///
  /// Answers with both records: the caller is looking at the NCR and reading the
  /// record it just created at the same time.
  Future<(Nonconformance, SupplierNcr)> recordSupplierNcrNonconformance(
    String accessToken,
    String id, {
    String? productId,
    num? quantity,
    String? defectCodeId,
    String? immediateContainment,
  }) async {
    final path = '/api/quality/supplier-ncrs/$id/nonconformance';
    final body = <String, Object?>{};
    if (productId != null && productId.isNotEmpty) body['productId'] = productId;
    if (quantity != null) body['quantity'] = quantity;
    if (defectCodeId != null && defectCodeId.isNotEmpty) body['defectCodeId'] = defectCodeId;
    if (immediateContainment != null && immediateContainment.trim().isNotEmpty) {
      body['immediateContainment'] = immediateContainment.trim();
    }
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
      return (
        Nonconformance.fromJson(answer['nonconformance'] as Map<String, dynamic>),
        SupplierNcr.fromJson(answer['supplierNcr'] as Map<String, dynamic>),
      );
    } catch (error) {
      throw QualityApiException('The API answered with something this app could not read: $error');
    }
  }

  /// Links a Non-conformance that already exists to the NCR
  /// (`POST /api/quality/supplier-ncrs/:id/link`). The API refuses an NCR that
  /// already names one (409), a Non-conformance that is not there (404) and one
  /// about another Product (409) — which is why the picker is filtered to this
  /// NCR's Product, and left unfiltered when it names none.
  Future<SupplierNcr> linkSupplierNcrNonconformance(
    String accessToken,
    String id, {
    required String nonconformanceId,
  }) async {
    final path = '/api/quality/supplier-ncrs/$id/link';
    final response = await _send(
      () => _client.post(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode(<String, Object?>{'nonconformanceId': nonconformanceId}),
      ),
      path,
    );
    try {
      final answer = jsonDecode(response.body) as Map<String, dynamic>;
      return SupplierNcr.fromJson(answer['supplierNcr'] as Map<String, dynamic>);
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
