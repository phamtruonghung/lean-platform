/// The Quality Module's HTTP client, read for what it sends and what it makes
/// of the answer (issue #203).
///
/// The same seam `people_api_test.dart` uses for `PeopleApi`: a `MockClient`
/// standing in for the wire, asserting the URL, the query parameters and the
/// decoded body rather than driving a Screen through it. It is the only place
/// the catalogue's own `?search=` is exercised: the two Screens carry no
/// finding control yet — the sweep that adds one to each catalogue is a
/// different ticket — so the address's own capability is pinned here, where it
/// can be, instead of by a Screen that would be that sweep arriving early.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:lean_platform/quality/nonconformance.dart';
import 'package:lean_platform/quality/quality_api.dart';

void main() {
  group('QualityApi.fetchProducts', () {
    test('asks for the retired Products too when told to, and parses every field the row carries',
        () async {
      late Uri sent;
      final client = MockClient((request) async {
        sent = request.url;
        return http.Response(
          jsonEncode({
            'products': [
              {
                'id': 7,
                'code': 'PRD-1',
                'name': 'Gearbox',
                'uomCode': 'EA',
                'uomName': 'Each',
                'isActive': false,
                'createdAt': '2026-01-01T00:00:00.000Z',
                'updatedAt': '2026-01-01T00:00:00.000Z',
              }
            ],
          }),
          200,
        );
      });

      final products = await QualityApi(client: client).fetchProducts('the-token', includeInactive: true);

      expect(sent.path, '/api/quality/products');
      expect(sent.queryParameters, {'includeInactive': 'true'});
      expect(products.single.id, '7');
      expect(products.single.code, 'PRD-1');
      expect(products.single.name, 'Gearbox');
      expect(products.single.uomCode, 'EA');
      expect(products.single.uomName, 'Each');
      expect(products.single.isActive, isFalse);
    });

    test('narrows by a term, sent as the search parameter', () async {
      late Uri sent;
      final client = MockClient((request) async {
        sent = request.url;
        return http.Response(jsonEncode({'products': <dynamic>[]}), 200);
      });

      final products = await QualityApi(client: client).fetchProducts('the-token', search: '  gear  ');

      expect(sent.queryParameters, {'search': 'gear'});
      expect(products, isEmpty);
    });

    test('answers with no query at all when neither is asked for', () async {
      late Uri sent;
      final client = MockClient((request) async {
        sent = request.url;
        return http.Response(jsonEncode({'products': <dynamic>[]}), 200);
      });

      await QualityApi(client: client).fetchProducts('the-token');

      expect(sent.query, isEmpty);
    });

    test("surfaces the API's own message when the catalogue cannot be read", () async {
      final client = MockClient(
        (request) async => http.Response(jsonEncode({'message': 'The Product catalogue is unavailable.'}), 500),
      );

      expect(
        () => QualityApi(client: client).fetchProducts('the-token'),
        throwsA(
          isA<QualityApiException>()
              .having((error) => error.message, 'message', 'The Product catalogue is unavailable.')
              .having((error) => error.statusCode, 'statusCode', 500),
        ),
      );
    });
  });

  group('QualityApi writes', () {
    test('creates a Product with exactly its code, name and unit of measure', () async {
      late Map<String, dynamic> body;
      final client = MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'product': {
              'id': 8,
              'code': 'PRD-2',
              'name': 'Bearing shell',
              'uomCode': 'H',
              'uomName': 'Hour',
              'isActive': true,
            },
          }),
          201,
        );
      });

      final product = await QualityApi(client: client)
          .createProduct('the-token', code: 'PRD-2', name: 'Bearing shell', uomCode: 'H');

      expect(body, {'code': 'PRD-2', 'name': 'Bearing shell', 'uomCode': 'H'});
      expect(product.id, '8');
      expect(product.uomName, 'Hour');
    });

    test('creates a Defect code with its parent when one was chosen, and omits it when none was',
        () async {
      final bodies = <Map<String, dynamic>>[];
      final client = MockClient((request) async {
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(
          jsonEncode({
            'defectCode': {
              'id': 9,
              'parentId': null,
              'code': 'DIM-OVL',
              'name': 'Ovality',
              'category': 'process',
              'defaultSeverity': 'critical',
              'isActive': true,
            },
          }),
          201,
        );
      });
      final api = QualityApi(client: client);

      await api.createDefectCode('the-token',
          code: 'DIM-OVL',
          name: 'Ovality',
          category: 'process',
          defaultSeverity: 'critical',
          parentId: '10');
      await api.createDefectCode('the-token',
          code: 'DIM-OVL', name: 'Ovality', category: 'process', defaultSeverity: 'critical');

      expect(bodies.first['parentId'], '10');
      expect(bodies.last.containsKey('parentId'), isFalse);
    });

    test('a correction sends only the keys it was handed, a cleared parent included', () async {
      late Map<String, dynamic> body;
      final client = MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'defectCode': {
              'id': 11,
              'parentId': null,
              'code': 'DIM-OOT',
              'name': 'Out of tolerance',
              'category': 'material',
              'defaultSeverity': 'major',
              'isActive': true,
            },
          }),
          200,
        );
      });

      await QualityApi(client: client)
          .updateDefectCode('the-token', '11', {'parentId': null, 'isActive': false});

      expect(body, {'parentId': null, 'isActive': false});
    });

    test("a refused write carries the API's own sentence and status", () async {
      final client = MockClient(
        (request) async => http.Response(
          jsonEncode({'message': 'a Defect code with this code already exists'}),
          409,
        ),
      );

      expect(
        () => QualityApi(client: client).createDefectCode('the-token',
            code: 'DIM', name: 'Dimensional', category: 'product', defaultSeverity: 'minor'),
        throwsA(
          isA<QualityApiException>()
              .having((error) => error.message, 'message', 'a Defect code with this code already exists')
              .having((error) => error.statusCode, 'statusCode', 409),
        ),
      );
    });
  });

  group('QualityApi.fetchUnitsOfMeasure', () {
    test('reads the units the plant uses off Maintenance\'s own address', () async {
      late Uri sent;
      final client = MockClient((request) async {
        sent = request.url;
        return http.Response(
          jsonEncode({
            'unitsOfMeasure': [
              {'code': 'EA', 'name': 'Each', 'dimension': 'count'},
            ],
          }),
          200,
        );
      });

      final units = await QualityApi(client: client).fetchUnitsOfMeasure('the-token');

      // The address is Maintenance's, deliberately: one endpoint over the
      // baseline's one units table (quality_api.dart's own header).
      expect(sent.path, '/api/maintenance/units-of-measure');
      expect(units.single.code, 'EA');
      expect(units.single.label, 'Each (EA)');
    });
  });

  group('QualityApi.fetchNonconformances', () {
    test('reads a Site\'s register, sending only the filters that are set', () async {
      late Uri sent;
      final client = MockClient((request) async {
        sent = request.url;
        return http.Response(
          jsonEncode({
            'nonconformances': [
              {
                'id': 701,
                'issueNo': 'NC-HCM-2026-00001',
                'status': 'contained',
                'detectionPoint': 'final_inspection',
                'severity': 'major',
                'quantityAffected': '12.0000',
                'quantityDispositioned': 0,
                'uomCode': 'EA',
                'lotRef': 'LOT-77',
                'detectedAt': '2026-04-06T08:00:00.000Z',
                'recordedByAccountId': 1,
                'orgUnitId': 11,
                'orgUnitName': 'Line 1',
                'siteId': 1,
                'siteCode': 'HCM',
                'productId': 40,
                'productCode': 'PRD-1',
                'productName': 'Gearbox',
                'defectCodeId': 41,
                'defectCodeCode': 'DIM-OOT',
                'defectCodeName': 'Out of tolerance',
                'defectCodeDefaultSeverity': 'minor',
                'shiftInstanceId': 5,
                'productionDate': '2026-04-06',
                'shiftName': 'Day shift',
                'quantityChanges': [
                  {
                    'id': 1,
                    'previousQuantity': 12,
                    'newQuantity': 20,
                    'changedAt': '2026-04-06T09:00:00.000Z',
                    'note': 'Sorting the bin found eight more.',
                    'changedByAccountId': 1,
                    'changedByAccountName': 'Ann Operator',
                  }
                ],
              }
            ],
            'truncated': false,
          }),
          200,
        );
      });

      final register = await QualityApi(client: client).fetchNonconformances(
        'the-token',
        '1',
        filters: const NonconformanceFilters(
          orgUnitId: '10',
          status: 'contained',
          defectCodeId: '41',
          productId: '40',
          severity: 'major',
          from: '2026-04-01',
          to: '2026-04-30',
        ),
      );

      expect(sent.path, '/api/quality/sites/1/nonconformances');
      expect(sent.queryParameters, {
        'orgUnitId': '10',
        'status': 'contained',
        'defectCodeId': '41',
        'productId': '40',
        'severity': 'major',
        'from': '2026-04-01',
        'to': '2026-04-30',
      });
      expect(register.truncated, isFalse);
      final row = register.nonconformances.single;
      expect(row.id, '701');
      expect(row.issueNo, 'NC-HCM-2026-00001');
      // A numeric column arrives as a string and is a number here — the client
      // prints it, so the model decides what type it is.
      expect(row.quantityAffected, 12);
      expect(row.quantityChanges.single.previousQuantity, 12);
      expect(row.quantityChanges.single.newQuantity, 20);
      expect(row.quantityChanges.single.changedBy, 'Ann Operator');
      expect(row.filedAgainst, '2026-04-06 · Day shift');
    });

    test('sends no query at all when no filter is set', () async {
      late Uri sent;
      final client = MockClient((request) async {
        sent = request.url;
        return http.Response(jsonEncode({'nonconformances': [], 'truncated': true}), 200);
      });

      final register =
          await QualityApi(client: client).fetchNonconformances('the-token', '1');

      expect(sent.queryParameters, isEmpty);
      expect(register.nonconformances, isEmpty);
      expect(register.truncated, isTrue);
    });
  });

  group('QualityApi.recordNonconformance', () {
    test('records at the Org Unit it was found at, sending only what was decided', () async {
      late http.Request sent;
      final client = MockClient((request) async {
        sent = request;
        return http.Response(
          jsonEncode({
            'nonconformance': {
              'id': 702,
              'issueNo': 'NC-HCM-2026-00002',
              'status': 'contained',
              'detectionPoint': 'in_process',
              'severity': 'major',
              'quantityAffected': 12,
              'quantityDispositioned': 0,
              'uomCode': 'EA',
              'orgUnitId': 10,
              'orgUnitName': 'Assembly',
              'siteId': 1,
              'productId': 40,
              'defectCodeId': 41,
              'assetId': 7,
              'immediateContainment': 'Quarantined the bin.',
              'quantityChanges': <dynamic>[],
            },
          }),
          201,
        );
      });

      final recorded = await QualityApi(client: client).recordNonconformance(
        'the-token',
        '1',
        orgUnitId: '10',
        productId: '40',
        defectCodeId: '41',
        detectionPoint: 'in_process',
        quantity: 12,
        assetId: '7',
        immediateContainment: 'Quarantined the bin.',
      );

      expect(sent.method, 'POST');
      expect(sent.url.path, '/api/quality/sites/1/nonconformances');
      // The optional keys that were not decided are absent rather than null:
      // the API never has to interpret a blank.
      expect(jsonDecode(sent.body), {
        'orgUnitId': '10',
        'productId': '40',
        'defectCodeId': '41',
        'detectionPoint': 'in_process',
        'quantity': 12,
        'assetId': '7',
        'immediateContainment': 'Quarantined the bin.',
      });
      expect(recorded.issueNo, 'NC-HCM-2026-00002');
      expect(recorded.statusLabel, 'Contained');
    });

    test('carries a raised severity, and a refusal reaches the caller with the API\'s own words', () async {
      late Map<String, dynamic> body;
      final client = MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({'message': "severity cannot be set below this Defect code's own major"}),
          403,
        );
      });

      await expectLater(
        QualityApi(client: client).recordNonconformance(
          'the-token',
          '1',
          orgUnitId: '10',
          productId: '40',
          defectCodeId: '41',
          detectionPoint: 'audit',
          quantity: 1,
          severity: 'minor',
        ),
        throwsA(
          isA<QualityApiException>()
              .having((error) => error.statusCode, 'statusCode', 403)
              .having(
                (error) => error.message,
                'message',
                "severity cannot be set below this Defect code's own major",
              ),
        ),
      );
      expect(body['severity'], 'minor');
    });
  });

  group('QualityApi.updateNonconformance', () {
    test('raises the severity and records containment on the record\'s own address', () async {
      final sent = <http.Request>[];
      final client = MockClient((request) async {
        sent.add(request);
        return http.Response(
          jsonEncode({
            'nonconformance': {
              'id': 701,
              'issueNo': 'NC-HCM-2026-00001',
              'status': 'contained',
              'severity': 'critical',
              'quantityAffected': 12,
              'orgUnitId': 11,
              'quantityChanges': <dynamic>[],
            },
          }),
          200,
        );
      });

      final api = QualityApi(client: client);
      final raised = await api.updateNonconformance('the-token', '701', severity: 'critical');
      final contained = await api.updateNonconformance(
        'the-token',
        '701',
        immediateContainment: 'Stopped the line.',
      );

      expect(sent.first.method, 'PATCH');
      expect(sent.first.url.path, '/api/quality/nonconformances/701');
      expect(jsonDecode(sent.first.body), {'severity': 'critical'});
      expect(jsonDecode(sent.last.body), {'immediateContainment': 'Stopped the line.'});
      expect(raised.severity, 'critical');
      // The whole record comes back from every write — the Screen never
      // patches its own copy.
      expect(contained.statusLabel, 'Contained');
      expect(contained.quantityAffected, 12);
    });
  });

  group('QualityApi.increaseNonconformanceQuantity', () {
    test('posts the new quantity and its note, and reads the grown history off the answer', () async {
      late http.Request sent;
      final client = MockClient((request) async {
        sent = request;
        return http.Response(
          jsonEncode({
            'nonconformance': {
              'id': 701,
              'issueNo': 'NC-HCM-2026-00001',
              'status': 'open',
              'severity': 'major',
              'quantityAffected': 20,
              'orgUnitId': 11,
              'quantityChanges': [
                {
                  'id': 1,
                  'previousQuantity': 12,
                  'newQuantity': 20,
                  'changedByAccountName': 'Ann Operator',
                  'note': 'Sorting the bin found eight more.',
                }
              ],
            },
          }),
          200,
        );
      });

      final grown = await QualityApi(client: client).increaseNonconformanceQuantity(
        'the-token',
        '701',
        quantity: 20,
        note: 'Sorting the bin found eight more.',
      );

      expect(sent.url.path, '/api/quality/nonconformances/701/quantity');
      expect(jsonDecode(sent.body), {
        'quantity': 20,
        'note': 'Sorting the bin found eight more.',
      });
      expect(grown.quantityAffected, 20);
      expect(grown.quantityChanged, isTrue);
      expect(grown.quantityChanges.single.newQuantity, 20);
    });

    test('a refusal arrives as the Module\'s own exception carrying the API\'s sentence', () async {
      final client = MockClient(
        (request) async => http.Response(
          jsonEncode({'message': 'the affected quantity can only be increased'}),
          409,
        ),
      );

      await expectLater(
        QualityApi(client: client)
            .increaseNonconformanceQuantity('the-token', '701', quantity: 11),
        throwsA(
          isA<QualityApiException>()
              .having((error) => error.statusCode, 'statusCode', 409)
              .having(
                (error) => error.message,
                'message',
                'the affected quantity can only be increased',
              ),
        ),
      );
    });
  });
}
