/// Home (issue #101): a role-scoped "your work" surface, with the wire faked
/// — the one client seam (ADR-0012). The real app, the real router, the real
/// Blocs, `MockClient` at the HTTP boundary and `FakeAuthGateway` at the auth
/// boundary.
///
/// What these tests claim and what they do not: that the right cards appear
/// for a given role, that a role earning neither section renders the
/// deliberate empty state rather than a blank Screen, that each card carries
/// to the right address, and that one section's own failure or loading never
/// hides the other's. Not that the server enforces who earns what — that is
/// proved wherever each read's own Screen test already proves it
/// (`work_orders_test.dart`, `approval_queue_test.dart`), and neither
/// substitutes for the other.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/home_screen.dart';
import 'package:lean_platform/maintenance/work_orders_screen.dart';
import 'package:lean_platform/people/approval_queue_screen.dart';
import 'package:lean_platform/people/directory_screen.dart';
import 'package:lean_platform/platform/destinations.dart';
import 'package:lean_platform/widgets/skeleton_list.dart';

import 'harness.dart';

FakeWire wireWith({
  String role = Roles.admin,
  Map<String, dynamic>? orgUnitScope,
  List<Map<String, dynamic>>? sites,
  Map<String, List<Map<String, dynamic>>>? workOrders,
  int workOrdersStatus = 200,
  List<Map<String, dynamic>>? queue,
  int queueStatus = 200,
}) =>
    FakeWire(
      role: role,
      orgUnitScope: orgUnitScope,
      sites: sites ?? [siteJson('1', 'HCM', 'Ho Chi Minh')],
      workOrders: workOrders ?? {'1': []},
      workOrdersStatus: workOrdersStatus,
      queue: queue ?? [],
      queueStatus: queueStatus,
    );

void main() {
  testWidgets('an operator earning no work-order Destination and no Approvals sees the deliberate '
      'empty state, never a blank Screen', (tester) async {
    final wire = wireWith(role: Roles.operator);
    await pumpApp(tester, gateway: FakeAuthGateway(accessToken: 'a-token'), client: wire.client);

    // The welcome line survives from the placeholder this Screen used to be
    // — still rendered above the cards (or, here, the empty state) by every
    // role alike.
    expect(find.text('Welcome, A B'), findsOneWidget);
    expect(find.text('admin@b.c · operator'), findsOneWidget);
    expect(find.byKey(HomeScreen.emptyKey), findsOneWidget);
    expect(find.text('Nothing is waiting on you'), findsOneWidget);
    expect(find.byKey(HomeScreen.openWorkOrdersCardKey), findsNothing);
    expect(find.byKey(HomeScreen.unassignedCardKey), findsNothing);
    expect(find.byKey(HomeScreen.approvalsCardKey), findsNothing);
    // No read this role earns nothing from — no request beyond `/me` at all.
    expect(wire.requests, ['GET /api/people/me']);
  });

  testWidgets(
      'a supervisor sees only the Work order cards, scoped to their own Org Units, and the '
      'awaiting-assignment card says so rather than claiming completeness', (tester) async {
    final wire = wireWith(
      role: Roles.supervisor,
      orgUnitScope: {'everywhere': false, 'grants': [scopeGrantJson('10')]},
      workOrders: {
        '1': [
          // Unassigned, and on the granted Org Unit: counted.
          workOrderJson('101', 'WO-101', 'Belt is slipping', orgUnitId: '10'),
          // Unassigned, but on an Org Unit this Account holds no Grant on:
          // not counted, the same coarse Grant-matching `HomeBloc` documents.
          workOrderJson('102', 'WO-102', 'Guard is loose', orgUnitId: '11'),
          // Already has an assignee: open, but not "awaiting assignment".
          workOrderJson('103', 'WO-103', 'Bearing noise', orgUnitId: '10', assignedTo: '9', assigneeName: 'Jo'),
        ],
      },
    );
    await pumpApp(tester, gateway: FakeAuthGateway(accessToken: 'a-token'), client: wire.client);

    expect(find.byKey(HomeScreen.emptyKey), findsNothing);
    expect(find.byKey(HomeScreen.openWorkOrdersCardKey), findsOneWidget);
    expect(find.byKey(HomeScreen.unassignedCardKey), findsOneWidget);
    expect(find.byKey(HomeScreen.approvalsCardKey), findsNothing);
    expect(find.text('Open work orders'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Awaiting assignment'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    // A follow-up on #101, raised before it shipped: a Grant-scoped Account
    // must never be told it is seeing every unassigned Work order — it is
    // only seeing what sits exactly on an Org Unit it holds a Grant on, not
    // what sits beneath one (`HomeWorkSummary.unassignedCount`'s own doc
    // comment).
    expect(find.text('On the Org Units granted to you, not what sits beneath them'), findsOneWidget);
    expect(find.text('Open, with nobody holding them yet'), findsNothing);
  });

  testWidgets('an administrator sees both the Work order cards and the Approvals card, and the '
      'awaiting-assignment card claims completeness — their scope really is everywhere',
      (tester) async {
    final wire = wireWith(
      workOrders: {
        '1': [workOrderJson('101', 'WO-101', 'Belt is slipping')],
      },
      queue: [pendingJson('7', 'new@b.c', DateTime.now())],
    );
    await pumpApp(tester, gateway: FakeAuthGateway(accessToken: 'a-token'), client: wire.client);

    expect(find.byKey(HomeScreen.openWorkOrdersCardKey), findsOneWidget);
    expect(find.byKey(HomeScreen.unassignedCardKey), findsOneWidget);
    expect(find.byKey(HomeScreen.approvalsCardKey), findsOneWidget);
    expect(find.text('Accounts awaiting Approval'), findsOneWidget);
    // An administrator's own scope is `everywhere` (default in this harness),
    // so unlike the supervisor above, the unscoped wording is honest here.
    expect(find.text('Open, with nobody holding them yet'), findsOneWidget);
    expect(
      find.text('On the Org Units granted to you, not what sits beneath them'),
      findsNothing,
    );
  });

  testWidgets('the open Work orders card carries to the Work orders Destination', (tester) async {
    final wire = wireWith(workOrders: {'1': [workOrderJson('101', 'WO-101', 'Belt is slipping')]});
    await pumpApp(tester, gateway: FakeAuthGateway(accessToken: 'a-token'), client: wire.client);

    await tapIn(tester, find.byKey(HomeScreen.openWorkOrdersCardKey));

    expect(find.byType(WorkOrdersScreen), findsOneWidget);
  });

  testWidgets('the awaiting-assignment card carries to the Work orders Destination too', (tester) async {
    final wire = wireWith(workOrders: {'1': [workOrderJson('101', 'WO-101', 'Belt is slipping')]});
    await pumpApp(tester, gateway: FakeAuthGateway(accessToken: 'a-token'), client: wire.client);

    await tapIn(tester, find.byKey(HomeScreen.unassignedCardKey));

    expect(find.byType(WorkOrdersScreen), findsOneWidget);
  });

  testWidgets('the Approvals card carries to the Approval queue Destination', (tester) async {
    final wire = wireWith(queue: [pendingJson('7', 'new@b.c', DateTime.now())]);
    await pumpApp(tester, gateway: FakeAuthGateway(accessToken: 'a-token'), client: wire.client);

    await tapIn(tester, find.byKey(HomeScreen.approvalsCardKey));

    expect(find.byType(ApprovalQueueScreen), findsOneWidget);
  });

  testWidgets("the empty state's own action carries an operator to the Directory", (tester) async {
    final wire = wireWith(role: Roles.operator);
    await pumpApp(tester, gateway: FakeAuthGateway(accessToken: 'a-token'), client: wire.client);

    await tapIn(tester, find.byKey(HomeScreen.emptyDirectoryActionKey));

    expect(find.byType(DirectoryScreen), findsOneWidget);
  });

  testWidgets('a failed Work order read renders the shared failure state, without hiding a '
      'working Approvals count', (tester) async {
    final wire = wireWith(
      workOrdersStatus: 503,
      queue: [pendingJson('7', 'new@b.c', DateTime.now())],
    );
    await pumpApp(tester, gateway: FakeAuthGateway(accessToken: 'a-token'), client: wire.client);

    expect(find.byKey(HomeScreen.workRetryKey), findsOneWidget);
    expect(find.text('Work orders are unavailable'), findsOneWidget);
    expect(find.byKey(HomeScreen.openWorkOrdersCardKey), findsNothing);
    // The Approvals section is untouched by the Work order section's own
    // failure — it loaded fine and still shows its count.
    expect(find.byKey(HomeScreen.approvalsCardKey), findsOneWidget);
    expect(find.text('1'), findsOneWidget);

    wire.workOrdersStatus = 200;
    wire.workOrders = {
      '1': [workOrderJson('101', 'WO-101', 'Belt is slipping')],
    };
    await tapIn(tester, find.byKey(HomeScreen.workRetryKey));

    expect(find.byKey(HomeScreen.workRetryKey), findsNothing);
    expect(find.byKey(HomeScreen.openWorkOrdersCardKey), findsOneWidget);
  });

  testWidgets('a failed Approvals read renders the shared failure state, without hiding a '
      'working Work order count', (tester) async {
    final wire = wireWith(
      workOrders: {
        '1': [workOrderJson('101', 'WO-101', 'Belt is slipping')],
      },
      queueStatus: 503,
    );
    await pumpApp(tester, gateway: FakeAuthGateway(accessToken: 'a-token'), client: wire.client);

    expect(find.byKey(HomeScreen.approvalsRetryKey), findsOneWidget);
    expect(find.byKey(HomeScreen.approvalsCardKey), findsNothing);
    expect(find.byKey(HomeScreen.openWorkOrdersCardKey), findsOneWidget);
  });

  testWidgets('the Work order section shows the shared skeleton while its own read is in flight, '
      'without waiting on the Approvals section', (tester) async {
    final wire = wireWith(
      workOrders: {'1': []},
      queue: [pendingJson('7', 'new@b.c', DateTime.now())],
    )..workOrdersGate = Completer<void>();
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      settle: false,
    );

    expect(find.byType(SkeletonGrid), findsWidgets);
    expect(find.byKey(HomeScreen.openWorkOrdersCardKey), findsNothing);
    // The Approvals section does not wait on the gated Work order read.
    expect(find.byKey(HomeScreen.approvalsCardKey), findsOneWidget);

    wire.workOrdersGate!.complete();
    await tester.pumpAndSettle();

    expect(find.byKey(HomeScreen.openWorkOrdersCardKey), findsOneWidget);
  });
}
