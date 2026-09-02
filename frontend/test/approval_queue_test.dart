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

Map<String, dynamic> _meBody(String role) => {
      'status': 'active',
      'account': {'email': 'admin@b.c', 'displayName': 'A B', 'role': role},
    };

/// Two days and a bit, so flooring never lands on "1 day" while the test runs.
final DateTime _twoDaysAgo = DateTime.now().subtract(const Duration(days: 2, hours: 1));
final DateTime _threeHoursAgo = DateTime.now().subtract(const Duration(hours: 3, minutes: 1));

Map<String, dynamic> _pending(String id, String email, DateTime since) => {
      'id': id,
      'email': email,
      'createdAt': since.toUtc().toIso8601String(),
    };

/// The wire, faked: `/me` answers the role under test, and the queue endpoints
/// answer whatever the test scripted. Every request is recorded so a test can
/// assert what was — and was not — sent.
class FakeWire {
  FakeWire({
    this.role = Roles.admin,
    List<Map<String, dynamic>>? queue,
    this.queueStatus = 200,
    this.rejectStatus = 200,
  }) : queue = queue ?? [];

  final String role;
  List<Map<String, dynamic>> queue;
  int queueStatus;
  int rejectStatus;

  final List<String> requests = [];

  http.Client get client => MockClient((request) async {
        final path = request.url.path;
        requests.add('${request.method} $path');
        if (path == '/api/people/me') {
          return http.Response(jsonEncode(_meBody(role)), 200);
        }
        if (path == '/api/people/accounts/pending') {
          if (queueStatus != 200) {
            return http.Response(jsonEncode({'message': 'The queue is unavailable.'}), queueStatus);
          }
          return http.Response(jsonEncode({'accounts': queue}), 200);
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

Future<void> _open(WidgetTester tester, FakeWire wire) => pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: Routes.approvals,
    );

void main() {
  testWidgets('the queue renders the Accounts it is given', (tester) async {
    final wire = FakeWire(queue: [
      _pending('7', 'first@b.c', _twoDaysAgo),
      _pending('8', 'second@b.c', _threeHoursAgo),
    ]);
    await _open(tester, wire);

    expect(find.byType(ApprovalQueueScreen), findsOneWidget);
    expect(find.text('first@b.c'), findsOneWidget);
    expect(find.text('second@b.c'), findsOneWidget);
    expect(find.text('Waiting 2 days'), findsOneWidget);
    expect(find.text('Waiting 3 hours'), findsOneWidget);
  });

  testWidgets('an empty queue says plainly that nothing is waiting', (tester) async {
    await _open(tester, FakeWire(queue: []));

    expect(find.text('Nobody is waiting'), findsOneWidget);
    expect(find.text('The queue could not be loaded'), findsNothing);
  });

  testWidgets('a failed load explains itself and the retry works', (tester) async {
    final wire = FakeWire(queueStatus: 500);
    await _open(tester, wire);

    expect(find.text('The queue could not be loaded'), findsOneWidget);
    expect(find.text('The queue is unavailable.'), findsOneWidget);
    expect(find.text('Nobody is waiting'), findsNothing);

    wire.queueStatus = 200;
    wire.queue = [_pending('7', 'first@b.c', _twoDaysAgo)];
    await tester.tap(find.byKey(const ValueKey('approval-queue-retry')));
    await tester.pumpAndSettle();

    expect(find.text('first@b.c'), findsOneWidget);
    expect(find.text('The queue could not be loaded'), findsNothing);
  });

  testWidgets('rejecting asks first, and cancelling sends nothing', (tester) async {
    final wire = FakeWire(queue: [_pending('7', 'first@b.c', _twoDaysAgo)]);
    await _open(tester, wire);

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
      _pending('7', 'first@b.c', _twoDaysAgo),
      _pending('8', 'second@b.c', _threeHoursAgo),
    ]);
    await _open(tester, wire);

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
      _pending('7', 'first@b.c', _twoDaysAgo),
      _pending('8', 'second@b.c', _threeHoursAgo),
    ], rejectStatus: 409);
    await _open(tester, wire);

    // Somebody else dealt with row 7 while this queue was on screen.
    wire.queue = [_pending('8', 'second@b.c', _threeHoursAgo)];

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
    final wire = FakeWire(role: Roles.supervisor, queue: [_pending('7', 'first@b.c', _twoDaysAgo)]);
    await _open(tester, wire);

    expect(find.byType(ApprovalQueueScreen), findsNothing);
    expect(find.byType(AccessDeniedScreen), findsOneWidget);
    // The Shell is still there — they are admitted, just not to this Screen.
    expect(find.byKey(PlatformShell.sidebarKey), findsOneWidget);
    expect(find.text('Approvals'), findsNothing);
    // Nothing was even asked of the queue endpoint.
    expect(wire.requests.where((r) => r.contains('pending')), isEmpty);
  });

  testWidgets('an administrator gets the destination in the sidebar', (tester) async {
    await _open(tester, FakeWire(queue: []));
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
