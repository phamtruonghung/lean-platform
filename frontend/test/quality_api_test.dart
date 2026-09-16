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
}
