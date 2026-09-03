import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/people/approval_queue_screen.dart';
import 'package:lean_platform/people/pending_account.dart';
import 'package:lean_platform/platform/access_denied_screen.dart';
import 'package:lean_platform/platform/destinations.dart';
import 'package:lean_platform/platform/router.dart';
import 'package:lean_platform/platform/shell.dart';

import 'harness.dart' show FakeAuthGateway, FakeWire, pendingJson, pumpApp;

/// Two days and a bit, so flooring never lands on "1 day" while the test runs.
final DateTime _twoDaysAgo = DateTime.now().subtract(const Duration(days: 2, hours: 1));
final DateTime _threeHoursAgo = DateTime.now().subtract(const Duration(hours: 3, minutes: 1));

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
