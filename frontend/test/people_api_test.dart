import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:lean_platform/people_api.dart';

void main() {
  group('PeopleApi.fetchMe', () {
    test('requests /api/people/me with a bearer token', () async {
      late Uri requestedUri;
      late String? authHeader;
      final client = MockClient((request) async {
        requestedUri = request.url;
        authHeader = request.headers['authorization'];
        return http.Response(
          jsonEncode({
            'status': 'active',
            'account': {'id': '1', 'email': 'a@b.c', 'displayName': 'A B', 'role': 'administrator'},
          }),
          200,
        );
      });
      final api = PeopleApi(client: client);

      await api.fetchMe('the-token');

      expect(requestedUri.path, '/api/people/me');
      expect(authHeader, 'Bearer the-token');
    });

    test('a pending_approval body yields AccountPendingApproval', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'status': 'pending_approval',
            'account': {'email': 'a@b.c'},
          }),
          200,
        );
      });
      final api = PeopleApi(client: client);

      final status = await api.fetchMe('the-token');

      expect(status, isA<AccountPendingApproval>());
      expect(status.email, 'a@b.c');
    });

    test('an active-shaped body yields AccountActive with the right fields', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'status': 'active',
            'account': {'id': '1', 'email': 'a@b.c', 'displayName': 'A B', 'role': 'administrator'},
          }),
          200,
        );
      });
      final api = PeopleApi(client: client);

      final status = await api.fetchMe('the-token');

      expect(status, isA<AccountActive>());
      final active = status as AccountActive;
      expect(active.email, 'a@b.c');
      expect(active.displayName, 'A B');
      expect(active.role, 'administrator');
    });

    test('a non-200 status throws PeopleApiException', () async {
      final client = MockClient((request) async => http.Response('server error', 500));
      final api = PeopleApi(client: client);

      expect(
        () => api.fetchMe('the-token'),
        throwsA(isA<PeopleApiException>().having((e) => e.statusCode, 'statusCode', 500)),
      );
    });

    test('an admin-shaped orgUnitScope (everywhere: true, no grants) parses correctly', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'status': 'active',
            'account': {'id': '1', 'email': 'a@b.c', 'displayName': 'A B', 'role': 'admin'},
            'orgUnitScope': {'everywhere': true, 'grants': []},
          }),
          200,
        );
      });
      final api = PeopleApi(client: client);

      final status = await api.fetchMe('the-token');

      final active = status as AccountActive;
      expect(active.orgUnitScope.everywhere, isTrue);
      expect(active.orgUnitScope.grants, isEmpty);
      expect(active.orgUnitScope.canWriteSomewhere, isTrue);
    });

    test(
      'a scoped orgUnitScope parses grant ids sent as JSON numbers and as JSON strings alike',
      () async {
        final client = MockClient((request) async {
          return http.Response(
            jsonEncode({
              'status': 'active',
              'account': {'id': '1', 'email': 'a@b.c', 'displayName': 'A B', 'role': 'supervisor'},
              'orgUnitScope': {
                'everywhere': false,
                'grants': [
                  {'orgUnitId': 101, 'siteId': 201, 'canWrite': true},
                  {'orgUnitId': '102', 'siteId': '202', 'canWrite': false},
                ],
              },
            }),
            200,
          );
        });
        final api = PeopleApi(client: client);

        final status = await api.fetchMe('the-token');

        final active = status as AccountActive;
        expect(active.orgUnitScope.everywhere, isFalse);
        expect(active.orgUnitScope.grants, hasLength(2));

        final numericGrant = active.orgUnitScope.grants[0];
        expect(numericGrant.orgUnitId, '101');
        expect(numericGrant.siteId, '201');
        expect(numericGrant.canWrite, isTrue);

        final stringGrant = active.orgUnitScope.grants[1];
        expect(stringGrant.orgUnitId, '102');
        expect(stringGrant.siteId, '202');
        expect(stringGrant.canWrite, isFalse);

        expect(active.orgUnitScope.canWriteSomewhere, isTrue);
      },
    );

    test('a body with no orgUnitScope key at all yields OrgUnitScope.nowhere()', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'status': 'active',
            'account': {'id': '1', 'email': 'a@b.c', 'displayName': 'A B', 'role': 'administrator'},
          }),
          200,
        );
      });
      final api = PeopleApi(client: client);

      final status = await api.fetchMe('the-token');

      final active = status as AccountActive;
      expect(active.orgUnitScope.everywhere, isFalse);
      expect(active.orgUnitScope.grants, isEmpty);
      expect(active.orgUnitScope.canWriteSomewhere, isFalse);
    });
  });
}
