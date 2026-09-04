/// Shared test harness for the client's widget tests.
///
/// The fake wire and the `pumpApp`/`meClient` pump helpers are used by every
/// Screen's tests, so they live here — somewhere neutral — rather than inside
/// whichever Screen's test file happened to need them first (issue #60, done
/// ahead of the Maintenance Module's own tests in #55).
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:lean_platform/maintenance/maintenance_api.dart';
import 'package:lean_platform/people_api.dart';
import 'package:lean_platform/platform/auth_gateway.dart';
import 'package:lean_platform/platform/destinations.dart';
import 'package:lean_platform/platform/platform_app.dart';

// `selfId` is '1' by default, and the fixtures that have to avoid it live in
// the calling test files rather than here: they use ids '7'/'8'/'9'/'10'+, so
// '1' never accidentally collides with a row and turns it into a false "self"
// match (issue #53). A new test building an `accountJson('1', …)` fixture is
// therefore declaring that row to be the caller's own Account, which loses it
// both row actions — deliberately so in `accounts_test.dart`, and a surprise
// anywhere else.
// `orgUnitScope` is what a Screen reads to decide whether to offer a write at
// all (issue #43, first consumed by the Asset register in #56). Left unset it
// mirrors the server's own invariant: an administrator reaches everywhere and
// holds no Grant rows; anyone else holds whatever rows the test gives them.
Map<String, dynamic> _meBody(String role, String selfId, Map<String, dynamic>? orgUnitScope) => {
      'status': 'active',
      'account': {'id': selfId, 'email': 'admin@b.c', 'displayName': 'A B', 'role': role},
      'orgUnitScope':
          orgUnitScope ?? {'everywhere': role == Roles.admin, 'grants': const <dynamic>[]},
    };

/// One Grant as `/me` reports it — `canWrite` is what decides whether a Screen
/// offers a write affordance.
Map<String, dynamic> scopeGrantJson(String orgUnitId, {String siteId = '1', bool canWrite = false}) =>
    {'orgUnitId': orgUnitId, 'siteId': siteId, 'canWrite': canWrite};

/// One Asset as `GET /api/maintenance/sites/:siteId/assets` sends it.
Map<String, dynamic> assetJson(
  String id,
  String code,
  String name, {
  String orgUnitId = '10',
  String orgUnitName = 'Line 1',
  String siteId = '1',
  String assetType = 'machine',
  String criticality = 'medium',
  bool isActive = true,
  String? parentId,
}) =>
    {
      'id': id,
      'code': code,
      'name': name,
      'assetType': assetType,
      'criticality': criticality,
      'orgUnitId': orgUnitId,
      'orgUnitName': orgUnitName,
      'orgUnitCode': orgUnitName.toUpperCase().replaceAll(' ', '-'),
      'siteId': siteId,
      'isActive': isActive,
      'parentId': parentId,
      'assetLevel': 'machine',
    };

Map<String, dynamic> pendingJson(String id, String email, DateTime since) => {
      'id': id,
      'email': email,
      'createdAt': since.toUtc().toIso8601String(),
    };

Map<String, dynamic> siteJson(String id, String code, String name) =>
    {'id': id, 'code': code, 'name': name, 'timezone': 'Europe/London'};

/// An Org Unit row exactly as `plant.js` sends one — `parentId` included,
/// because a root-level response can legitimately carry a non-null one.
Map<String, dynamic> orgUnitJson(
  String id,
  String name, {
  String? parentId,
  String unitType = 'area',
}) =>
    {
      'id': id,
      'parentId': parentId,
      'code': name.toUpperCase().replaceAll(' ', '-'),
      'name': name,
      'unitType': unitType,
      'path': id,
      'sortOrder': 0,
      'isActive': true,
    };

/// One Account as `GET /api/people/accounts` sends it.
Map<String, dynamic> accountJson(
  String id,
  String email, {
  String role = Roles.operator,
  bool isActive = true,
  String approvalStatus = 'approved',
  List<Map<String, dynamic>> grants = const [],
}) =>
    {
      'id': id,
      'email': email,
      'displayName': email.split('@').first,
      'role': role,
      'isActive': isActive,
      'approvalStatus': approvalStatus,
      'grants': grants,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };

/// One Grant on an Account row, as the accounts listing sends it.
Map<String, dynamic> grantJson(
  String orgUnitId, {
  String name = 'Assembly',
  String siteName = 'Ho Chi Minh',
  bool canWrite = false,
}) =>
    {
      'orgUnitId': orgUnitId,
      'parentId': null,
      'code': name.toUpperCase().replaceAll(' ', '-'),
      'name': name,
      'unitType': 'area',
      'siteId': '1',
      'siteName': siteName,
      'canWrite': canWrite,
    };

/// The wire, faked: `/me` answers the role under test, and the queue endpoints
/// answer whatever the test scripted. Every request is recorded so a test can
/// assert what was — and was not — sent.
class FakeWire {
  FakeWire({
    this.role = Roles.admin,
    this.selfId = '1',
    List<Map<String, dynamic>>? queue,
    this.queueStatus = 200,
    this.rejectStatus = 200,
    this.approveStatus = 200,
    this.approveMessage = 'The Platform could not admit that Account.',
    List<Map<String, dynamic>>? accounts,
    this.accountsStatus = 200,
    this.patchStatus = 200,
    List<Map<String, dynamic>>? sites,
    Map<String?, List<Map<String, dynamic>>>? orgUnits,
    this.sitesStatus = 200,
    this.orgUnitsStatus = 200,
    this.orgUnitScope,
    Map<String, List<Map<String, dynamic>>>? assets,
    this.assetsStatus = 200,
    this.createAssetStatus = 201,
    this.createAssetMessage = 'an Asset with this code already exists',
    this.patchAssetStatus = 200,
    this.patchAssetMessage = 'That Asset could not be changed.',
  })  : queue = queue ?? [],
        assets = assets ?? {},
        accounts = accounts ?? [],
        sites = sites ?? [],
        orgUnits = orgUnits ?? {};

  final String role;

  /// What `/me` reports as this caller's own Org Unit scope (issue #43).
  final Map<String, dynamic>? orgUnitScope;

  /// `GET /api/maintenance/sites/:siteId/assets`, keyed by Site id.
  Map<String, List<Map<String, dynamic>>> assets;
  int assetsStatus;

  /// `POST /api/maintenance/assets`.
  int createAssetStatus;
  String createAssetMessage;

  /// Every Asset body that actually reached the wire, decoded — so a test can
  /// assert that exactly one request was sent and what Org Unit it carried.
  final List<Map<String, dynamic>> assetPosts = [];

  /// `PATCH /api/maintenance/assets/:id` — retiring, reinstating, nesting and
  /// detaching all land here (issue #61).
  int patchAssetStatus;
  String patchAssetMessage;

  /// Every Asset PATCH that actually reached the wire, as `(id, body)` — so a
  /// test can assert exactly one request was sent and what it carried.
  final List<(String, Map<String, dynamic>)> assetPatches = [];

  /// When set, an Asset PATCH hangs until the test completes it — the same
  /// device [patchGate] uses for Accounts, needed to prove a second row
  /// action while this one is in flight is reported rather than dropped.
  Completer<void>? assetPatchGate;

  /// When set, an Asset listing hangs until the test completes it.
  Completer<void>? assetsGate;

  /// The caller's own Account id, as `/me` reports it — what the Accounts
  /// Screen compares each row against (issue #53).
  final String selfId;
  List<Map<String, dynamic>> queue;
  int queueStatus;
  int rejectStatus;
  int approveStatus;
  String approveMessage;

  /// `GET /api/people/accounts` — every Account, pending ones included.
  List<Map<String, dynamic>> accounts;
  int accountsStatus;

  /// `PATCH /api/people/accounts/:id`.
  int patchStatus;

  /// When set, a PATCH hangs until the test completes it — the same device
  /// [approvalGate] uses, needed to prove what happens when a second action
  /// is dispatched while this one is still in flight.
  Completer<void>? patchGate;

  /// Every activation change that reached the wire, as `(accountId, isActive)`.
  final List<(String, bool)> activations = [];

  /// `GET /api/people/sites`.
  List<Map<String, dynamic>> sites;
  int sitesStatus;

  /// `GET /api/people/sites/:id/org-units`, keyed by the `parentId` asked for
  /// — the null key is the root level, which is a different request, not a
  /// different filter over the same one.
  Map<String?, List<Map<String, dynamic>>> orgUnits;
  int orgUnitsStatus;

  /// Every Org Unit request as `(siteId, parentId)`, so a test can prove
  /// children were asked for by parent and only on expansion.
  final List<(String, String?)> orgUnitRequests = [];

  /// When set, an Approval hangs until the test completes it — which is what
  /// "in flight" means to a widget test.
  Completer<void>? approvalGate;

  final List<String> requests = [];

  /// Every Approval body that actually reached the wire, decoded.
  final List<Map<String, dynamic>> approvals = [];

  http.Client get client => MockClient((request) async {
        final path = request.url.path;
        requests.add('${request.method} $path');
        if (path == '/api/people/me') {
          return http.Response(jsonEncode(_meBody(role, selfId, orgUnitScope)), 200);
        }
        if (path.startsWith('/api/maintenance/sites/') && path.endsWith('/assets')) {
          if (assetsGate != null) await assetsGate!.future;
          if (assetsStatus != 200) {
            return http.Response(
              jsonEncode({'message': 'The register is unavailable.'}),
              assetsStatus,
            );
          }
          final siteId = path.split('/')[4];
          final includeRetired = request.url.queryParameters['includeRetired'] == 'true';
          final siteAssets = assets[siteId] ?? [];
          final sent = includeRetired
              ? siteAssets
              : [
                  for (final a in siteAssets)
                    if (a['isActive'] != false) a,
                ];
          return http.Response(jsonEncode({'assets': sent}), 200);
        }
        if (request.method == 'POST' && path == '/api/maintenance/assets') {
          final sent = jsonDecode(request.body) as Map<String, dynamic>;
          assetPosts.add(sent);
          if (createAssetStatus != 201) {
            return http.Response(jsonEncode({'message': createAssetMessage}), createAssetStatus);
          }
          final created = assetJson(
            '900',
            sent['code'] as String,
            sent['name'] as String,
            orgUnitId: sent['orgUnitId'] as String,
            assetType: sent['assetType'] as String,
            criticality: sent['criticality'] as String,
          );
          return http.Response(jsonEncode({'asset': created}), 201);
        }
        if (request.method == 'PATCH' && path.startsWith('/api/maintenance/assets/')) {
          final id = path.split('/').last;
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          assetPatches.add((id, body));
          if (assetPatchGate != null) await assetPatchGate!.future;
          if (patchAssetStatus != 200) {
            return http.Response(jsonEncode({'message': patchAssetMessage}), patchAssetStatus);
          }
          Map<String, dynamic>? updated;
          assets = {
            for (final entry in assets.entries)
              entry.key: [
                for (final a in entry.value)
                  if (a['id'] == id) (updated = {...a, ...body}) else a,
              ],
          };
          if (updated == null) {
            return http.Response(jsonEncode({'message': 'That Asset does not exist.'}), 404);
          }
          return http.Response(jsonEncode({'asset': updated}), 200);
        }
        if (path == '/api/people/sites') {
          if (sitesStatus != 200) {
            return http.Response(jsonEncode({'message': 'Sites are unavailable.'}), sitesStatus);
          }
          return http.Response(jsonEncode({'sites': sites}), 200);
        }
        if (path.startsWith('/api/people/sites/') && path.endsWith('/org-units')) {
          final siteId = path.split('/')[4];
          final parentId = request.url.queryParameters['parentId'];
          orgUnitRequests.add((siteId, parentId));
          if (orgUnitsStatus != 200) {
            return http.Response(
              jsonEncode({'message': 'The tree is unavailable.'}),
              orgUnitsStatus,
            );
          }
          return http.Response(jsonEncode({'orgUnits': orgUnits[parentId] ?? []}), 200);
        }
        if (path == '/api/people/accounts') {
          if (accountsStatus != 200) {
            return http.Response(
              jsonEncode({'message': 'The Accounts are unavailable.'}),
              accountsStatus,
            );
          }
          return http.Response(jsonEncode({'accounts': accounts}), 200);
        }
        if (request.method == 'PATCH' && path.startsWith('/api/people/accounts/')) {
          final id = path.split('/')[4];
          final isActive = (jsonDecode(request.body) as Map<String, dynamic>)['isActive'] == true;
          activations.add((id, isActive));
          if (patchGate != null) await patchGate!.future;
          if (patchStatus != 200) {
            return http.Response(
              jsonEncode({'message': 'That Account could not be changed.'}),
              patchStatus,
            );
          }
          accounts = [
            for (final a in accounts)
              if (a['id'] == id) {...a, 'isActive': isActive} else a,
          ];
          return http.Response(jsonEncode({'account': {'id': id}}), 200);
        }
        if (path == '/api/people/accounts/pending') {
          if (queueStatus != 200) {
            return http.Response(jsonEncode({'message': 'The queue is unavailable.'}), queueStatus);
          }
          return http.Response(jsonEncode({'accounts': queue}), 200);
        }
        if (path.endsWith('/approval')) {
          approvals.add(jsonDecode(request.body) as Map<String, dynamic>);
          if (approvalGate != null) await approvalGate!.future;
          if (approveStatus != 200) {
            return http.Response(jsonEncode({'message': approveMessage}), approveStatus);
          }
          final id = path.split('/')[4];
          queue = [for (final a in queue) if (a['id'] != id) a];
          final sent = approvals.last;
          accounts = [
            for (final a in accounts)
              if (a['id'] == id)
                {
                  ...a,
                  'role': sent['role'],
                  'isActive': true,
                  'approvalStatus': 'approved',
                  'grants': [
                    for (final g in (sent['grants'] as List<dynamic>))
                      grantJson(
                        (g as Map<String, dynamic>)['orgUnitId'] as String,
                        canWrite: g['canWrite'] == true,
                      ),
                  ],
                }
              else
                a,
          ];
          return http.Response(jsonEncode({'account': {'id': id}}), 200);
        }
        if (path.endsWith('/rejection')) {
          if (rejectStatus != 200) {
            return http.Response(
              jsonEncode({'message': 'This Account is no longer pending.'}),
              rejectStatus,
            );
          }
          final id = path.split('/')[4];
          queue = [for (final a in queue) if (a['id'] != id) a];
          return http.Response(jsonEncode({'account': {'id': id}}), 200);
        }
        return http.Response('{}', 404);
      });
}

class FakeAuthGateway implements AuthGateway {
  FakeAuthGateway({String? accessToken}) : _token = accessToken;

  String? _token;
  final StreamController<String?> _controller = StreamController<String?>.broadcast();

  @override
  String? get currentAccessToken => _token;

  /// Honours [AuthGateway]'s contract: the current token first, then every
  /// change after it.
  @override
  Stream<String?> get accessTokenChanges async* {
    yield _token;
    yield* _controller.stream;
  }

  void emitToken(String? token) {
    _token = token;
    _controller.add(token);
  }

  @override
  Future<void> signInWithPassword({required String email, required String password}) async =>
      emitToken('token-for-$email');

  @override
  Future<void> signUp({required String email, required String password}) async =>
      emitToken('token-for-$email');

  @override
  Future<void> signInWithGoogle() async => emitToken('token-for-google');

  @override
  Future<void> signOut() async => emitToken(null);
}

http.Client meClient(Map<String, dynamic> Function() body, {int status = 200}) {
  return MockClient((request) async => http.Response(jsonEncode(body()), status));
}

/// [settle] is false for a test that needs to observe a Screen mid-load — a
/// gated response never settles, so `pumpAndSettle` would time out. The caller
/// then drives frames itself with `tester.pump()`.
Future<void> pumpApp(
  WidgetTester tester, {
  required FakeAuthGateway gateway,
  required http.Client client,
  String? initialLocation,
  bool settle = true,
}) async {
  await tester.pumpWidget(
    PlatformApp(
      authGateway: gateway,
      peopleApi: PeopleApi(client: client),
      // One faked wire behind both Modules' API clients, so a test scripts the
      // whole app's network in one place.
      maintenanceApi: MaintenanceApi(client: client),
      initialLocation: initialLocation,
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    // Enough frames for /me and the router to resolve, but not so many that a
    // deliberately-hanging request is waited on.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
  }
}

/// Taps something that may be scrolled out of view — the Screens under test
/// are taller than the 800x600 test surface, so a bare `tap` silently misses
/// a widget that is present but off screen.
Future<void> tapIn(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
