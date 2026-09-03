import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:lean_platform/people/approval_queue_screen.dart';
import 'package:lean_platform/people/pending_account.dart';
import 'package:lean_platform/platform/access_denied_screen.dart';
import 'package:lean_platform/platform/destinations.dart';
import 'package:lean_platform/platform/router.dart';
import 'package:lean_platform/platform/shell.dart';

import 'router_redirect_test.dart' show FakeAuthGateway, pumpApp;

// `selfId` is '1' by default — every existing test-fixture Account/Org Unit
// in this file uses ids '7'/'8'/'9'/'10'+, so '1' never accidentally
// collides with an existing row and turns it into a false "self" match
// (issue #53).
Map<String, dynamic> _meBody(String role, String selfId) => {
      'status': 'active',
      'account': {'id': selfId, 'email': 'admin@b.c', 'displayName': 'A B', 'role': role},
    };

/// Two days and a bit, so flooring never lands on "1 day" while the test runs.
final DateTime _twoDaysAgo = DateTime.now().subtract(const Duration(days: 2, hours: 1));
final DateTime _threeHoursAgo = DateTime.now().subtract(const Duration(hours: 3, minutes: 1));

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
  })  : queue = queue ?? [],
        accounts = accounts ?? [],
        sites = sites ?? [],
        orgUnits = orgUnits ?? {};

  final String role;

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
          return http.Response(jsonEncode(_meBody(role, selfId)), 200);
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

Future<void> openApprovals(WidgetTester tester, FakeWire wire) => pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: Routes.approvals,
    );

void main() {
  testWidgets('the queue renders the Accounts it is given', (tester) async {
    final wire = FakeWire(queue: [
      pendingJson('7', 'first@b.c', _twoDaysAgo),
      pendingJson('8', 'second@b.c', _threeHoursAgo),
    ]);
    await openApprovals(tester, wire);

    expect(find.byType(ApprovalQueueScreen), findsOneWidget);
    expect(find.text('first@b.c'), findsOneWidget);
    expect(find.text('second@b.c'), findsOneWidget);
    expect(find.text('Waiting 2 days'), findsOneWidget);
    expect(find.text('Waiting 3 hours'), findsOneWidget);
  });

  testWidgets('an empty queue says plainly that nothing is waiting', (tester) async {
    await openApprovals(tester, FakeWire(queue: []));

    expect(find.text('Nobody is waiting'), findsOneWidget);
    expect(find.text('The queue could not be loaded'), findsNothing);
  });

  testWidgets('a failed load explains itself and the retry works', (tester) async {
    final wire = FakeWire(queueStatus: 500);
    await openApprovals(tester, wire);

    expect(find.text('The queue could not be loaded'), findsOneWidget);
    expect(find.text('The queue is unavailable.'), findsOneWidget);
    expect(find.text('Nobody is waiting'), findsNothing);

    wire.queueStatus = 200;
    wire.queue = [pendingJson('7', 'first@b.c', _twoDaysAgo)];
    await tester.tap(find.byKey(const ValueKey('approval-queue-retry')));
    await tester.pumpAndSettle();

    expect(find.text('first@b.c'), findsOneWidget);
    expect(find.text('The queue could not be loaded'), findsNothing);
  });

  testWidgets('rejecting asks first, and cancelling sends nothing', (tester) async {
    final wire = FakeWire(queue: [pendingJson('7', 'first@b.c', _twoDaysAgo)]);
    await openApprovals(tester, wire);

    await tester.tap(find.byKey(const ValueKey('approval-queue-reject-7')));
    await tester.pumpAndSettle();
    expect(find.text('Reject this Account?'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Reject this Account?'), findsNothing);
    expect(wire.requests.where((r) => r.endsWith('/rejection')), isEmpty);
    expect(find.text('first@b.c'), findsOneWidget);
  });

  testWidgets('confirming sends the rejection and the row leaves the queue', (tester) async {
    final wire = FakeWire(queue: [
      pendingJson('7', 'first@b.c', _twoDaysAgo),
      pendingJson('8', 'second@b.c', _threeHoursAgo),
    ]);
    await openApprovals(tester, wire);

    await tester.tap(find.byKey(const ValueKey('approval-queue-reject-7')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Reject'));
    await tester.pumpAndSettle();

    expect(
      wire.requests,
      contains('POST /api/people/accounts/7/rejection'),
    );
    expect(find.text('first@b.c'), findsNothing);
    expect(find.text('second@b.c'), findsOneWidget);
  });

  testWidgets('an Account another administrator already dealt with is reported, and the queue refreshes',
      (tester) async {
    final wire = FakeWire(queue: [
      pendingJson('7', 'first@b.c', _twoDaysAgo),
      pendingJson('8', 'second@b.c', _threeHoursAgo),
    ], rejectStatus: 409);
    await openApprovals(tester, wire);

    // Somebody else dealt with row 7 while this queue was on screen.
    wire.queue = [pendingJson('8', 'second@b.c', _threeHoursAgo)];

    await tester.tap(find.byKey(const ValueKey('approval-queue-reject-7')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Reject'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('approval-queue-notice')), findsOneWidget);
    expect(
      find.textContaining('Another administrator has already dealt with'),
      findsOneWidget,
    );
    // Refreshed, not merely reported: the stale row is gone because the queue
    // was re-read, not because this client removed it.
    expect(
      wire.requests.where((r) => r == 'GET /api/people/accounts/pending').length,
      2,
    );
    expect(find.text('first@b.c'), findsNothing);
    expect(find.text('second@b.c'), findsOneWidget);
  });

  testWidgets('a non-administrator sees neither the destination nor the Screen', (tester) async {
    final wire = FakeWire(role: Roles.supervisor, queue: [pendingJson('7', 'first@b.c', _twoDaysAgo)]);
    await openApprovals(tester, wire);

    expect(find.byType(ApprovalQueueScreen), findsNothing);
    expect(find.byType(AccessDeniedScreen), findsOneWidget);
    // The Shell is still there — they are admitted, just not to this Screen.
    expect(find.byKey(PlatformShell.sidebarKey), findsOneWidget);
    expect(find.text('Approvals'), findsNothing);
    // Nothing was even asked of the queue endpoint.
    expect(wire.requests.where((r) => r.contains('pending')), isEmpty);
  });

  testWidgets('an administrator gets the destination in the sidebar', (tester) async {
    await openApprovals(tester, FakeWire(queue: []));
    expect(find.text('Approvals'), findsOneWidget);
  });

  test('waitingFor floors to the coarsest unit that is still true', () {
    final now = DateTime(2026, 9, 2, 12);
    expect(waitingFor(now.subtract(const Duration(seconds: 30)), now: now), 'Waiting less than a minute');
    expect(waitingFor(now.subtract(const Duration(minutes: 1)), now: now), 'Waiting 1 minute');
    expect(waitingFor(now.subtract(const Duration(minutes: 59)), now: now), 'Waiting 59 minutes');
    expect(waitingFor(now.subtract(const Duration(hours: 1)), now: now), 'Waiting 1 hour');
    expect(waitingFor(now.subtract(const Duration(hours: 47)), now: now), 'Waiting 1 day');
    expect(waitingFor(now.subtract(const Duration(days: 3)), now: now), 'Waiting 3 days');
  });
}
