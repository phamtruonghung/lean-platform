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

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/home_screen.dart';
import 'package:lean_platform/maintenance/work_orders_screen.dart';
import 'package:lean_platform/people/approval_queue_screen.dart';
import 'package:lean_platform/actions/actions_screen.dart';
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
  Map<String, List<Map<String, dynamic>>>? actions,
  // The caller's own Employee record, under the key `/employees/me` is served
  // from. Absent by default, which is the Account-with-no-link case the card
  // has its own wording for (`employeeDetailStatus` 404s it).
  Map<String, Map<String, dynamic>>? employeeDetails,
  int employeeDetailStatus = 200,
  String employeeDetailMessage = 'This Account has no linked Employee record',
}) =>
    FakeWire(
      role: role,
      orgUnitScope: orgUnitScope,
      sites: sites ?? [siteJson('1', 'HCM', 'Ho Chi Minh')],
      workOrders: workOrders ?? {'1': []},
      workOrdersStatus: workOrdersStatus,
      queue: queue ?? [],
      queueStatus: queueStatus,
      actions: actions ?? {'1': []},
      employeeDetails: employeeDetails ?? const {},
      employeeDetailStatus: employeeDetailStatus,
      employeeDetailMessage: employeeDetailMessage,
    );

void main() {
  testWidgets('an operator sees what is assigned to them and nothing else, and their Account '
      'carries no Employee link — which the card says rather than showing a zero', (tester) async {
    // Issue #185. Home used to have a deliberate no-cards empty state for this
    // role (#99 user story 6); the Actions Destination belongs to every role
    // (ADR-0032), so there is no such role left and this card is what an
    // operator's Home shows instead.
    final wire = wireWith(role: Roles.operator);
    await pumpApp(tester, gateway: FakeAuthGateway(accessToken: 'a-token'), client: wire.client);

    // The welcome line survives from the placeholder this Screen used to be —
    // still rendered above the cards by every role alike.
    expect(find.text('Welcome, A B'), findsOneWidget);
    expect(find.text('admin@b.c · operator'), findsOneWidget);
    expect(find.byKey(HomeScreen.myActionsCardKey), findsOneWidget);
    expect(find.text('Assigned to you'), findsOneWidget);
    expect(find.byKey(HomeScreen.openWorkOrdersCardKey), findsNothing);
    expect(find.byKey(HomeScreen.unassignedCardKey), findsNothing);
    expect(find.byKey(HomeScreen.approvalsCardKey), findsNothing);
    // A zero would be a lie here: the Account cannot be assigned anything at
    // all until it is linked to an Employee.
    expect(
      find.textContaining('not linked to an Employee record, so no Action can be assigned'),
      findsOneWidget,
    );
    // The reads this section makes, and no others: the caller's own Employee,
    // and nothing beyond it — with no link there is no owner to filter by, so
    // the Sites and the log are not read at all. (The default fixture serves
    // `/employees/me` the way the server does for this Account: a 404 saying
    // 'This Account has no linked Employee record'.)
    expect(wire.requests, ['GET /api/people/me', 'GET /api/people/employees/me']);
  });

  testWidgets('an Account link to an Employee turns the card into a count of what is assigned',
      (tester) async {
    final wire = wireWith(
      role: Roles.operator,
      employeeDetails: {'me': employeeDetailJson('7', 'EMP-007', 'Nour Haddad')},
      actions: {
        '1': [
          actionJson('501', 'AC-HCM-2026-00001', 'Guard keeps working loose'),
          actionJson('502', 'AC-HCM-2026-00002', 'Pallet wrapper jams'),
        ],
      },
    );
    await pumpApp(tester, gateway: FakeAuthGateway(accessToken: 'a-token'), client: wire.client);

    expect(find.byKey(HomeScreen.myActionsCardKey), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Open Actions whose owner is you'), findsOneWidget);
    // The read names the caller's own Employee: what is counted is what is
    // assigned to *them*, not what the Site holds (ADR-0009 lets the register
    // return everything). Asserted on the recorded URI — the fake's own
    // `requests` list records paths without their query.
    expect(wire.actionReads, isNotEmpty);
    expect(wire.actionReads.last.queryParameters['ownerEmployeeId'], '7');
  });

  testWidgets('the assigned-to-you card carries to the action log', (tester) async {
    final wire = wireWith(
      role: Roles.operator,
      employeeDetails: {'me': employeeDetailJson('7', 'EMP-007', 'Nour Haddad')},
    );
    await pumpApp(tester, gateway: FakeAuthGateway(accessToken: 'a-token'), client: wire.client);

    await tapIn(tester, find.byKey(HomeScreen.myActionsCardKey));

    expect(find.byType(ActionsScreen), findsOneWidget);
  });

  testWidgets('a failed read of what is assigned to you is its own failure, and hides nothing',
      (tester) async {
    final wire = wireWith(
      role: Roles.admin,
      employeeDetailStatus: 503,
      employeeDetailMessage: 'The Directory is unavailable',
      queue: [pendingJson('7', 'new@b.c', DateTime.now())],
    );
    await pumpApp(tester, gateway: FakeAuthGateway(accessToken: 'a-token'), client: wire.client);

    expect(find.text('Your Actions are unavailable'), findsOneWidget);
    expect(find.text('The Directory is unavailable'), findsOneWidget);
    // The Approvals section read on regardless.
    expect(find.byKey(HomeScreen.approvalsCardKey), findsOneWidget);

    // And its own retry asks again, rather than reloading the whole Screen.
    await tapIn(tester, find.byKey(HomeScreen.myActionsRetryKey));
    expect(wire.requests.where((r) => r.contains('employees/me')).length, 2);
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
          // Unassigned, but on an Org Unit this Grant does not reach — the
          // wire here reports a reach of only '10' (no `orgUnitIds`), so '11'
          // is outside it and is not counted. A Grant that *did* reach '11'
          // would count it; see the beneath-a-grant test below.
          workOrderJson('102', 'WO-102', 'Guard is loose', orgUnitId: '11'),
          // Already has an assignee: open, but not "awaiting assignment".
          workOrderJson('103', 'WO-103', 'Bearing noise', orgUnitId: '10', assignedTo: '9', assigneeName: 'Jo'),
        ],
      },
    );
    await pumpApp(tester, gateway: FakeAuthGateway(accessToken: 'a-token'), client: wire.client);

    expect(find.byKey(HomeScreen.openWorkOrdersCardKey), findsOneWidget);
    expect(find.byKey(HomeScreen.unassignedCardKey), findsOneWidget);
    expect(find.byKey(HomeScreen.approvalsCardKey), findsNothing);
    expect(find.text('Open work orders'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Awaiting assignment'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    // A scoped Account must never be told it is seeing every unassigned Work
    // order — it is only seeing what its Grants reach. Since issue #110 that
    // reach includes everything beneath a granted Org Unit, so the old "not
    // what sits beneath them" caveat is gone and the card says what the number
    // truly is (`HomeWorkSummary.unassignedCount`'s own doc comment).
    expect(find.text('On the Org Units granted to you, and everything beneath them'), findsOneWidget);
    expect(find.text('Open, with nobody holding them yet'), findsNothing);
  });

  testWidgets(
      'a Work order beneath a granted Org Unit is counted — the awaiting-assignment number reaches '
      'downward the way the Grant does (issue #110)', (tester) async {
    final wire = wireWith(
      role: Roles.supervisor,
      orgUnitScope: {
        'everywhere': false,
        'grants': [
          scopeGrantJson('10', orgUnitIds: ['10', '11']),
        ],
      },
      workOrders: {
        '1': [
          // On the granted Org Unit itself.
          workOrderJson('101', 'WO-101', 'Belt is slipping', orgUnitId: '10'),
          // Beneath the granted Org Unit — the case the old count dropped.
          workOrderJson('102', 'WO-102', 'Guard is loose', orgUnitId: '11'),
          // Outside the Grant's reach: still not counted.
          workOrderJson('103', 'WO-103', 'Bearing noise', orgUnitId: '12'),
        ],
      },
    );
    await pumpApp(tester, gateway: FakeAuthGateway(accessToken: 'a-token'), client: wire.client);

    expect(find.byKey(HomeScreen.unassignedCardKey), findsOneWidget);
    // 101 and 102 count; 103 does not.
    expect(find.text('2'), findsOneWidget);
    expect(
      find.text('On the Org Units granted to you, and everything beneath them'),
      findsOneWidget,
    );
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
      find.text('On the Org Units granted to you, and everything beneath them'),
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

  // The cards are one grid (issue #188). What these tests claim is the geometry
  // a reader can see — cards side by side at equal widths and equal heights, a
  // next row starting at the left edge the previous one did, a lone card
  // filling its own row instead of sitting at a column width, and one column
  // when the page is narrow — never a particular pixel value beyond the surface
  // each test pins for itself.
  //
  // The window width is what makes a column count here, and it is not the page
  // width: the Shell takes 260px of it above its own 700px breakpoint and 64px
  // below it, so a 1200px window leaves Home its full 900px page and a 620px
  // window leaves it ~500px. Both numbers are asserted through what renders
  // rather than recomputed here, so a Shell width change fails these tests as a
  // layout change rather than silently re-flowing the grid.

  /// The four cards an administrator's Home carries, at a window wide enough
  /// for Home's own 900px page — the surface the grid is judged on.
  Future<FakeWire> pumpWideAdminHome(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 1400);
    addTearDown(tester.view.reset);

    final wire = wireWith(
      workOrders: {
        '1': [workOrderJson('101', 'WO-101', 'Belt is slipping')],
      },
      queue: [pendingJson('7', 'new@b.c', DateTime.now())],
    );
    await pumpApp(tester, gateway: FakeAuthGateway(accessToken: 'a-token'), client: wire.client);
    return wire;
  }

  testWidgets('the cards sit side by side at one size, and the next row starts where the first did',
      (tester) async {
    await pumpWideAdminHome(tester);

    // Section order: what is assigned to you (its context line is the long
    // one in this fixture, since this Account carries no Employee link), the
    // two Work order cards, then Approvals.
    final myActionsSize = tester.getSize(find.byKey(HomeScreen.myActionsCardKey));
    final openOrdersSize = tester.getSize(find.byKey(HomeScreen.openWorkOrdersCardKey));
    final approvalsSize = tester.getSize(find.byKey(HomeScreen.approvalsCardKey));
    final unassignedSize = tester.getSize(find.byKey(HomeScreen.unassignedCardKey));

    // Equal widths within a row: two columns of the same 900px page.
    expect(openOrdersSize.width, myActionsSize.width);
    expect(approvalsSize.width, unassignedSize.width);
    expect(approvalsSize.width, myActionsSize.width);

    // Equal heights within a row, although one card's context line is three
    // times the length of its neighbour's — a row shares the height of its
    // tallest card rather than leaving a ragged bottom edge.
    expect(openOrdersSize.height, myActionsSize.height);

    // The second row starts at the same left edge the first one did, and above
    // it: no card is islanded in the middle of a row, which is exactly what
    // the three independent `Wrap`s this replaced produced.
    final firstRowLeft = tester.getTopLeft(find.byKey(HomeScreen.myActionsCardKey)).dx;
    final secondRowLeft = tester.getTopLeft(find.byKey(HomeScreen.unassignedCardKey)).dx;
    expect(secondRowLeft, firstRowLeft);
    expect(
      tester.getTopLeft(find.byKey(HomeScreen.approvalsCardKey)).dx,
      tester.getTopLeft(find.byKey(HomeScreen.openWorkOrdersCardKey)).dx,
    );
    expect(
      tester.getTopLeft(find.byKey(HomeScreen.unassignedCardKey)).dy,
      greaterThan(tester.getTopLeft(find.byKey(HomeScreen.myActionsCardKey)).dy),
    );
  });

  testWidgets('a lone card fills its own row rather than sitting at a column width',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 1400);
    addTearDown(tester.view.reset);

    // An operator's Home carries one card (#185).
    final wire = wireWith(role: Roles.operator);
    await pumpApp(tester, gateway: FakeAuthGateway(accessToken: 'a-token'), client: wire.client);

    // Half of Home's 900px page would be ~420px; the whole content box is 852.
    expect(tester.getSize(find.byKey(HomeScreen.myActionsCardKey)).width, greaterThan(800));
  });

  testWidgets('a narrow page lays the cards out in one column', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(620, 1600);
    addTearDown(tester.view.reset);

    final wire = wireWith(
      workOrders: {
        '1': [workOrderJson('101', 'WO-101', 'Belt is slipping')],
      },
      queue: [pendingJson('7', 'new@b.c', DateTime.now())],
    );
    await pumpApp(tester, gateway: FakeAuthGateway(accessToken: 'a-token'), client: wire.client);

    final left = tester.getTopLeft(find.byKey(HomeScreen.myActionsCardKey)).dx;
    for (final key in [
      HomeScreen.openWorkOrdersCardKey,
      HomeScreen.unassignedCardKey,
      HomeScreen.approvalsCardKey,
    ]) {
      expect(tester.getTopLeft(find.byKey(key)).dx, left);
    }
    // One column means each card is the full content width, not half of it.
    expect(
      tester.getSize(find.byKey(HomeScreen.openWorkOrdersCardKey)).width,
      tester.getSize(find.byKey(HomeScreen.myActionsCardKey)).width,
    );
    expect(
      tester.getTopLeft(find.byKey(HomeScreen.unassignedCardKey)).dy,
      greaterThan(tester.getTopLeft(find.byKey(HomeScreen.openWorkOrdersCardKey)).dy),
    );
  });
}
