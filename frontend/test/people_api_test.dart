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

    // Issue #204, ADR-0035: Quality authority is per Grant, independent of
    // its level, and `/me` reports it beside each Grant's reach — so the
    // client can answer the same per-Org-Unit question the server's own
    // `canAct({ quality: true })` answers, by the mechanism ADR-0027 already
    // established for `canWrite`.
    test('Quality authority parses per Grant, and reaches exactly what that Grant reaches', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'status': 'active',
            'account': {'id': '1', 'email': 'a@b.c', 'displayName': 'A B', 'role': 'engineer'},
            'orgUnitScope': {
              'everywhere': false,
              'grants': [
                // A view-only Grant carrying Quality authority on a department.
                {
                  'orgUnitId': '10',
                  'siteId': '1',
                  'canWrite': false,
                  'qualityAuthority': true,
                  'orgUnitIds': ['10', '11'],
                },
                // An edit Grant that does not carry it, on a sibling.
                {'orgUnitId': '12', 'siteId': '1', 'canWrite': true, 'qualityAuthority': false},
              ],
            },
          }),
          200,
        );
      });
      final api = PeopleApi(client: client);

      final status = await api.fetchMe('the-token') as AccountActive;
      final scope = status.orgUnitScope;

      expect(scope.grants[0].qualityAuthority, isTrue);
      expect(scope.grants[0].canWrite, isFalse, reason: 'the flag is independent of the level');
      expect(scope.grants[1].qualityAuthority, isFalse);
      expect(scope.grants[1].canWrite, isTrue);

      // The granted unit and everything beneath it; never a sibling, never an
      // ancestor, and never an Org Unit an unflagged Grant reaches.
      expect(scope.canHoldQualityAt('10'), isTrue);
      expect(scope.canHoldQualityAt('11'), isTrue);
      expect(scope.canHoldQualityAt('12'), isFalse);
      expect(scope.canHoldQualityAt('99'), isFalse);
      expect(scope.canWriteAt('12'), isTrue);
      // The only Grant that may write is the one on the sibling '12', and it
      // was sent without a reach list, so it reaches no further than its own
      // Org Unit (ADR-0027): a flagged Grant on '10' never widens it upward.
      expect(scope.canWriteAt('10'), isFalse);
    });

    // The default a Grant sent without the key gets: no authority. An older
    // server, or a fixture written before the flag existed, must never read
    // as holding a permission nobody granted.
    test('a Grant sent without qualityAuthority holds none', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'status': 'active',
            'account': {'id': '1', 'email': 'a@b.c', 'displayName': 'A B', 'role': 'engineer'},
            'orgUnitScope': {
              'everywhere': false,
              'grants': [
                {'orgUnitId': '10', 'siteId': '1', 'canWrite': true},
              ],
            },
          }),
          200,
        );
      });
      final api = PeopleApi(client: client);

      final status = await api.fetchMe('the-token') as AccountActive;
      expect(status.orgUnitScope.grants.single.qualityAuthority, isFalse);
      expect(status.orgUnitScope.canHoldQualityAt('10'), isFalse);
    });

    test('an administrator holds Quality authority everywhere, with no Grants at all', () async {
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

      final status = await api.fetchMe('the-token') as AccountActive;
      expect(status.orgUnitScope.canHoldQualityAt('anything-at-all'), isTrue);
    });
  });

  // The Accounts Screen's own read (issue #204): a Grant there carries the
  // flag too, which is where an administrator audits who may accept bad
  // product and where the correction dialog's checkbox is seeded from.
  group('PeopleApi.fetchAccounts', () {
    test('a Grant on an Account row parses its Quality authority', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'accounts': [
              {
                'id': '7',
                'email': 'auditor@b.c',
                'displayName': 'auditor',
                'role': 'supervisor',
                'isActive': true,
                'approvalStatus': 'approved',
                'createdAt': '2026-01-01T00:00:00.000Z',
                'grants': [
                  {
                    'orgUnitId': '10',
                    'parentId': null,
                    'code': 'ASSEMBLY',
                    'name': 'Assembly',
                    'unitType': 'area',
                    'siteId': '1',
                    'siteName': 'Ho Chi Minh',
                    'canWrite': false,
                    'qualityAuthority': true,
                  },
                  {
                    'orgUnitId': '11',
                    'parentId': '10',
                    'code': 'LINE-1',
                    'name': 'Line 1',
                    'unitType': 'line',
                    'siteId': '1',
                    'siteName': 'Ho Chi Minh',
                    'canWrite': true,
                  },
                ],
              },
            ],
          }),
          200,
        );
      });
      final api = PeopleApi(client: client);

      final accounts = await api.fetchAccounts('the-token');
      final grants = accounts.single.grants;

      expect(grants[0].qualityAuthority, isTrue);
      expect(grants[0].canWrite, isFalse);
      expect(grants[1].qualityAuthority, isFalse);
      // And it travels into the picker a correction opens on, so saving the
      // form cannot silently drop it.
      expect(grants[0].toGranted().quality, isTrue);
      expect(grants[1].toGranted().quality, isFalse);
      expect(grants[0].toGranted().toJson(), {
        'orgUnitId': '10',
        'canWrite': false,
        'qualityAuthority': true,
        'safetyAuthority': false,
      });
    });
  });
}
