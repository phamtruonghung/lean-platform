/// The Work order list (issue #57), with the wire faked — the one client
/// seam (ADR-0012). The real app, the real router, the real Blocs,
/// `MockClient` at the HTTP boundary and `FakeAuthGateway` at the auth
/// boundary.
///
/// What these tests claim and what they do not: that the affordance to raise
/// is absent for a caller the server would refuse, and that a narrowed read
/// sends the right query — not that the server actually enforces either. That
/// is proved on the backend, in whatever integration suite covers issue #57
/// there, and neither substitutes for the other (mirroring `assets_test.dart`'s
/// own Testing Decisions).
///
/// Assigning a Work order (issue #62) adds the same shape of claim, and the
/// same limit: these tests claim the affordance is absent for a caller the
/// server would refuse and that assigning sends exactly one request carrying
/// the chosen Employee — not that the server enforces scope, refuses a
/// Departed Employee, or lets a lapsed qualification through unblocked. Those
/// are proved in `backend/test/integration/work-orders.test.js`, and neither
/// substitutes for the other.
///
/// Working a Work order — start, complete, cancel (issue #63) — adds the same
/// shape of claim again: that the right action is offered for a row's status
/// and no other, that each sends exactly one request carrying whatever the
/// dialog collected, that a completed or cancelled row leaves the open list
/// without a re-read, and that the history toggle asks the server for it. Not
/// that the server enforces the state machine, the write-Grant scope, or the
/// "already started"/"already completed" refusals — those are proved in
/// `backend/test/integration/work-orders.test.js`, and neither substitutes
/// for the other.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/maintenance/org_unit_chooser.dart';
import 'package:lean_platform/maintenance/work_order_assign_dialog.dart';
import 'package:lean_platform/maintenance/work_order_cancel_dialog.dart';
import 'package:lean_platform/maintenance/work_order_complete_dialog.dart';
import 'package:lean_platform/maintenance/work_order_dialog_host.dart';
import 'package:lean_platform/maintenance/work_order_form_dialog.dart';
import 'package:lean_platform/maintenance/work_orders_screen.dart';
import 'package:lean_platform/platform/access_denied_screen.dart';
import 'package:lean_platform/platform/destinations.dart';
import 'package:lean_platform/theme.dart';
import 'package:lean_platform/widgets/skeleton_list.dart';

import 'harness.dart';

/// Opens a row's overflow menu (issue #104, Decision C) — [WorkOrdersScreen
/// .assignKey]/[WorkOrdersScreen.cancelKey] moved from an always-rendered
/// inline button into this menu's own items, so any test that used to tap
/// one of those keys directly now opens the menu first. The action each key
/// names, and what tapping it does, is unchanged — only where it sits in
/// the tree moved.
Future<void> openRowMenu(WidgetTester tester, String id) =>
    tapIn(tester, find.byKey(WorkOrdersScreen.rowActionsKey(id)));

FakeWire wireWith({
  String role = Roles.admin,
  Map<String, dynamic>? orgUnitScope,
  List<Map<String, dynamic>>? sites,
  Map<String, List<Map<String, dynamic>>>? workOrders,
  int workOrdersStatus = 200,
  Map<String, List<Map<String, dynamic>>>? assets,
  int createWorkOrderStatus = 201,
  List<Map<String, dynamic>>? assigneeCandidates,
  int assignWorkOrderStatus = 200,
  int startWorkOrderStatus = 200,
  int completeWorkOrderStatus = 200,
  int cancelWorkOrderStatus = 200,
}) =>
    FakeWire(
      role: role,
      orgUnitScope: orgUnitScope,
      sites: sites ?? [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [orgUnitJson('10', 'Assembly')],
        '10': [orgUnitJson('11', 'Line 1', parentId: '10', unitType: 'line')],
      },
      assets: assets ?? {'1': []},
      workOrders: workOrders,
      workOrdersStatus: workOrdersStatus,
      createWorkOrderStatus: createWorkOrderStatus,
      assigneeCandidates: assigneeCandidates ?? [],
      assignWorkOrderStatus: assignWorkOrderStatus,
      startWorkOrderStatus: startWorkOrderStatus,
      completeWorkOrderStatus: completeWorkOrderStatus,
      cancelWorkOrderStatus: cancelWorkOrderStatus,
    );

void main() {
  testWidgets('the list renders what it is given: Asset, job, state and who has it',
      (tester) async {
    final wire = wireWith(
      workOrders: {
        '1': [
          workOrderJson('101', 'WO-101', 'Belt is slipping', assigneeName: 'Jane Doe'),
          workOrderJson('102', 'WO-102', 'Guard is loose', assetCode: 'CONV-2', assetName: 'Infeed conveyor'),
        ],
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders',
    );

    expect(find.byKey(WorkOrdersScreen.rowKey('101')), findsOneWidget);
    expect(find.byKey(WorkOrdersScreen.rowKey('102')), findsOneWidget);
    expect(find.text('Belt is slipping'), findsOneWidget);
    expect(find.text('Press 1 (PRESS-1) · Corrective'), findsOneWidget);
    expect(find.text('Jane Doe'), findsOneWidget);
    // Nobody has row 102 yet — shown plainly, never as a blank.
    expect(find.text('Unassigned'), findsOneWidget);
    expect(find.text('Approved'), findsWidgets);
  });

  testWidgets('a list still loading shows placeholders in its own shape', (tester) async {
    final wire = wireWith(workOrders: {'1': []})..workOrdersGate = Completer<void>();
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders',
      settle: false,
    );

    expect(find.byType(SkeletonList), findsOneWidget);
    expect(find.byKey(WorkOrdersScreen.emptyKey), findsNothing);

    wire.workOrdersGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(SkeletonList), findsNothing);
  });

  testWidgets('an empty list says plainly there is no open work', (tester) async {
    final wire = wireWith(workOrders: {'1': []});
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders',
    );

    expect(find.byKey(WorkOrdersScreen.emptyKey), findsOneWidget);
    expect(find.byKey(WorkOrdersScreen.failedKey), findsNothing);
    expect(find.byKey(WorkOrdersScreen.emptyFilteredKey), findsNothing);
    expect(find.text('No open work at this Site'), findsOneWidget);
  });

  // Issue #103: the shared empty/loading/error states, migrated onto this
  // Screen as the ticket's own worked example.

  testWidgets('the whole-Site empty state carries the action to raise a Work order, for a caller '
      'who holds a write Grant', (tester) async {
    final wire = wireWith(workOrders: {'1': []});
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders',
    );

    expect(find.byKey(WorkOrdersScreen.emptyKey), findsOneWidget);
    expect(find.byKey(WorkOrdersScreen.emptyRaiseKey), findsOneWidget);
  });

  testWidgets('the whole-Site empty state carries no action for a caller with no write Grant',
      (tester) async {
    final wire = wireWith(
      role: Roles.supervisor,
      orgUnitScope: {'everywhere': false, 'grants': [scopeGrantJson('10')]},
      workOrders: {'1': []},
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders',
    );

    expect(find.byKey(WorkOrdersScreen.emptyKey), findsOneWidget);
    expect(find.byKey(WorkOrdersScreen.emptyRaiseKey), findsNothing);
  });

  testWidgets(
      'a filter that matches nothing renders as its own distinct empty state, with its own '
      'action to clear the filter', (tester) async {
    final wire = wireWith(
      workOrders: {
        '1': [workOrderJson('101', 'WO-101', 'Belt is slipping')],
      },
    );
    // The whole Site has an open Work order, but nothing at Assembly (org
    // unit 10) — the "your filter matched nothing" story, distinct from
    // "nothing has ever been raised" (issue #103).
    wire.workOrdersByFilter['1|10'] = [];
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders',
    );

    await tapIn(tester, find.byKey(WorkOrdersScreen.filterKey));
    await tapIn(tester, find.byKey(OrgUnitChooser.chooseKey('10')));

    expect(find.byKey(WorkOrdersScreen.emptyFilteredKey), findsOneWidget);
    expect(find.byKey(WorkOrdersScreen.emptyKey), findsNothing);
    expect(find.text('No work orders match'), findsOneWidget);
    expect(find.byKey(WorkOrdersScreen.emptyClearFiltersKey), findsOneWidget);

    await tapIn(tester, find.byKey(WorkOrdersScreen.emptyClearFiltersKey));

    expect(wire.workOrderRequests.last, ('1', null, false));
    expect(find.text('Belt is slipping'), findsOneWidget);
    expect(find.byKey(WorkOrdersScreen.filterKey), findsOneWidget);
  });

  testWidgets(
      'a scope-refused read renders as its own explained state, never as the ordinary empty '
      'state', (tester) async {
    // Maintenance's own list read cannot 403 today (it is Site-wide
    // regardless of Grants, ADR-0009) — this scripts one anyway, exactly as
    // #103's own testing guidance asks, to prove the Screen's classification
    // and rendering are correct ahead of the Org-Unit-scoped reads #72–#80
    // will add.
    final wire = wireWith(workOrders: {'1': []}, workOrdersStatus: 403);
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders',
    );

    expect(find.byKey(WorkOrdersScreen.scopeRefusedKey), findsOneWidget);
    expect(find.byKey(WorkOrdersScreen.emptyKey), findsNothing);
    expect(find.byKey(WorkOrdersScreen.failedKey), findsNothing);
    expect(find.text('Not visible to you'), findsOneWidget);
    // No retry offered — retrying answers the same refusal (this widget's
    // own doc comment).
    expect(find.byKey(WorkOrdersScreen.retryKey), findsNothing);
  });

  testWidgets('a failed load explains itself and the retry works', (tester) async {
    final wire = wireWith(workOrdersStatus: 503);
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders',
    );

    expect(find.byKey(WorkOrdersScreen.failedKey), findsOneWidget);
    expect(find.byKey(WorkOrdersScreen.emptyKey), findsNothing);
    expect(find.text('Work orders are unavailable.'), findsOneWidget);

    wire.workOrdersStatus = 200;
    wire.workOrders = {
      '1': [workOrderJson('101', 'WO-101', 'Belt is slipping')],
    };
    await tapIn(tester, find.byKey(WorkOrdersScreen.retryKey));

    expect(find.byKey(WorkOrdersScreen.failedKey), findsNothing);
    expect(find.text('Belt is slipping'), findsOneWidget);
  });

  testWidgets(
      "a retry after switching Site re-opens on the caller's Site, not back on the first",
      (tester) async {
    final wire = wireWith(
      workOrders: {
        '1': [workOrderJson('101', 'WO-101', 'Belt is slipping')],
      },
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh'), siteJson('2', 'DN', 'Da Nang')],
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders',
    );

    expect(find.text('Belt is slipping'), findsOneWidget);

    wire.workOrdersStatus = 503;
    await tapIn(tester, find.byKey(WorkOrdersScreen.siteKey));
    await tapIn(tester, find.text('Da Nang').last);

    expect(find.byKey(WorkOrdersScreen.failedKey), findsOneWidget);

    wire.workOrdersStatus = 200;
    wire.workOrders = {
      '1': [workOrderJson('101', 'WO-101', 'Belt is slipping')],
      '2': [workOrderJson('202', 'WO-202', 'Da Nang alarm fault')],
    };
    await tapIn(tester, find.byKey(WorkOrdersScreen.retryKey));

    expect(find.byKey(WorkOrdersScreen.failedKey), findsNothing);
    expect(find.text('Da Nang alarm fault'), findsOneWidget);
    expect(find.text('Belt is slipping'), findsNothing);
  });

  testWidgets(
      'narrowing to an Org Unit sends ?orgUnitId= and shows the narrowed result; clearing '
      'returns to the whole Site', (tester) async {
    final wire = wireWith(
      workOrders: {
        '1': [
          workOrderJson('101', 'WO-101', 'Belt is slipping'),
          workOrderJson('102', 'WO-102', 'Guard is loose', orgUnitId: '10', orgUnitName: 'Assembly'),
        ],
      },
    );
    wire.workOrdersByFilter['1|10'] = [
      workOrderJson('102', 'WO-102', 'Guard is loose', orgUnitId: '10', orgUnitName: 'Assembly'),
    ];
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders',
    );

    expect(find.text('Belt is slipping'), findsOneWidget);
    expect(find.text('Guard is loose'), findsOneWidget);
    expect(wire.workOrderRequests, [('1', null, false)]);

    await tapIn(tester, find.byKey(WorkOrdersScreen.filterKey));
    await tapIn(tester, find.byKey(OrgUnitChooser.chooseKey('10')));

    expect(wire.workOrderRequests.last, ('1', '10', false));
    expect(find.text('Guard is loose'), findsOneWidget);
    expect(find.text('Belt is slipping'), findsNothing);
    expect(find.byKey(WorkOrdersScreen.clearFilterKey), findsOneWidget);

    await tapIn(tester, find.byKey(WorkOrdersScreen.clearFilterKey));

    expect(wire.workOrderRequests.last, ('1', null, false));
    expect(find.text('Belt is slipping'), findsOneWidget);
    expect(find.text('Guard is loose'), findsOneWidget);
    expect(find.byKey(WorkOrdersScreen.filterKey), findsOneWidget);
  });

  testWidgets(
      'raising sends exactly one request, with the right body, and without orgUnitId or a '
      'number', (tester) async {
    final wire = wireWith(
      workOrders: {'1': []},
      assets: {
        '1': [assetJson('7', 'PRESS-1', 'Press 1')],
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders',
    );

    await tapIn(tester, find.byKey(WorkOrdersScreen.raiseKey));
    await tester.pumpAndSettle();

    await tapIn(tester, find.byKey(WorkOrderFormDialog.assetKey));
    await tapIn(tester, find.text('Press 1 (PRESS-1)').last);

    await tester.enterText(find.byKey(WorkOrderFormDialog.summaryKey), 'Belt is slipping');
    await tester.pumpAndSettle();

    await tapIn(tester, find.byKey(WorkOrderFormDialog.workTypeKey));
    await tapIn(tester, find.text('Corrective').last);

    await tapIn(tester, find.byKey(WorkOrderFormDialog.priorityKey));
    await tapIn(tester, find.text('3 - Normal').last);

    await tapIn(tester, find.byKey(WorkOrderFormDialog.submitKey));

    expect(wire.workOrderPosts.length, 1);
    final sent = wire.workOrderPosts.single;
    expect(sent['assetId'], '7');
    expect(sent['summary'], 'Belt is slipping');
    expect(sent['workType'], 'corrective');
    expect(sent['priority'], 3);
    expect(sent.containsKey('orgUnitId'), isFalse);
    expect(sent.containsKey('workOrderNo'), isFalse);
    expect(sent.containsKey('number'), isFalse);

    expect(find.byType(WorkOrderFormDialog), findsNothing);
    expect(find.text('Belt is slipping'), findsOneWidget);
  });

  testWidgets('a refusal is surfaced in the form, which stays open', (tester) async {
    final wire = wireWith(
      workOrders: {'1': []},
      assets: {
        '1': [assetJson('7', 'PRESS-1', 'Press 1')],
      },
      createWorkOrderStatus: 403,
    )..createWorkOrderMessage = 'You do not hold a Grant reaching this Asset.';
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders',
    );

    await tapIn(tester, find.byKey(WorkOrdersScreen.raiseKey));
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(WorkOrderFormDialog.assetKey));
    await tapIn(tester, find.text('Press 1 (PRESS-1)').last);
    await tester.enterText(find.byKey(WorkOrderFormDialog.summaryKey), 'Belt is slipping');
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(WorkOrderFormDialog.workTypeKey));
    await tapIn(tester, find.text('Corrective').last);
    await tapIn(tester, find.byKey(WorkOrderFormDialog.priorityKey));
    await tapIn(tester, find.text('3 - Normal').last);
    await tapIn(tester, find.byKey(WorkOrderFormDialog.submitKey));

    expect(find.byType(WorkOrderFormDialog), findsOneWidget);
    expect(find.byKey(WorkOrderFormDialog.failureKey), findsOneWidget);
    expect(find.text('You do not hold a Grant reaching this Asset.'), findsOneWidget);
  });

  testWidgets('a retired Asset is not offered when raising', (tester) async {
    final wire = wireWith(
      workOrders: {'1': []},
      assets: {
        '1': [
          assetJson('7', 'PRESS-1', 'Press 1'),
          assetJson('8', 'PRESS-2', 'Press 2', isActive: false),
        ],
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders',
    );

    await tapIn(tester, find.byKey(WorkOrdersScreen.raiseKey));
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(WorkOrderFormDialog.assetKey));

    expect(find.text('Press 1 (PRESS-1)'), findsOneWidget);
    expect(find.text('Press 2 (PRESS-2)'), findsNothing);
  });

  testWidgets('an operator is offered neither the destination nor the Screen', (tester) async {
    final wire = wireWith(role: Roles.operator, workOrders: {'1': []});
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders',
    );

    expect(find.byType(AccessDeniedScreen), findsOneWidget);
    expect(find.byType(WorkOrdersScreen), findsNothing);
    expect(find.widgetWithText(NavigationRail, 'Work orders'), findsNothing);
    expect(wire.requests.any((r) => r.contains('/api/maintenance/')), isFalse);
  });

  testWidgets('a supervisor gets the destination and the Screen', (tester) async {
    final wire = wireWith(
      role: Roles.supervisor,
      orgUnitScope: {'everywhere': false, 'grants': [scopeGrantJson('10', canWrite: true)]},
      workOrders: {'1': []},
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders',
    );

    expect(find.byType(WorkOrdersScreen), findsOneWidget);
    expect(find.text('Work orders'), findsWidgets);
    expect(find.byKey(WorkOrdersScreen.raiseKey), findsOneWidget);
  });

  testWidgets('a supervisor with no write Grant is offered no way to raise', (tester) async {
    final wire = wireWith(
      role: Roles.supervisor,
      orgUnitScope: {'everywhere': false, 'grants': [scopeGrantJson('10')]},
      workOrders: {
        '1': [workOrderJson('101', 'WO-101', 'Belt is slipping')],
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders',
    );

    // The list itself is Site-wide: they read every open Work order
    // regardless.
    expect(find.text('Belt is slipping'), findsOneWidget);
    expect(find.byKey(WorkOrdersScreen.raiseKey), findsNothing);
  });

  // Assigning a Work order (issue #62). What these tests claim and what they
  // do not: that the affordance to assign is absent for a caller the server
  // would refuse, and that one request is sent carrying the chosen Employee —
  // not that the server enforces scope or that a lapsed qualification does
  // not block. Those are proved in
  // `backend/test/integration/work-orders.test.js`, and neither substitutes
  // for the other.

  testWidgets('the assign dialog lists candidates with what each of them holds', (tester) async {
    final wire = wireWith(
      workOrders: {
        '1': [workOrderJson('101', 'WO-101', 'Belt is slipping')],
      },
      assigneeCandidates: [
        assigneeCandidateJson(
          '20',
          'Jane Doe',
          skills: [heldSkillJson('1', '5', 'WELD', 'Welding')],
        ),
        assigneeCandidateJson(
          '21',
          'John Smith',
          skills: [heldSkillJson('2', '6', 'ELEC', 'Electrical')],
        ),
      ],
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders',
    );

    await openRowMenu(tester, '101');
    await tapIn(tester, find.byKey(WorkOrdersScreen.assignKey('101')));
    await tester.pumpAndSettle();

    expect(find.text('Jane Doe'), findsOneWidget);
    expect(find.text('John Smith'), findsOneWidget);
    expect(find.byKey(WorkOrderAssignDialog.skillChipKey('20', '5')), findsOneWidget);
    expect(find.byKey(WorkOrderAssignDialog.skillChipKey('21', '6')), findsOneWidget);
  });

  testWidgets('a lapsed qualification is shown as lapsed, and is not the same as holding nothing',
      (tester) async {
    final wire = wireWith(
      workOrders: {
        '1': [workOrderJson('101', 'WO-101', 'Belt is slipping')],
      },
      assigneeCandidates: [
        assigneeCandidateJson(
          '20',
          'Jane Doe',
          skills: [
            heldSkillJson('1', '5', 'WELD', 'Welding', isLapsed: true, expiresOn: '2020-01-01'),
          ],
        ),
        assigneeCandidateJson(
          '21',
          'John Smith',
          skills: [heldSkillJson('2', '6', 'ELEC', 'Electrical')],
        ),
        assigneeCandidateJson('22', 'Ana Silva'),
      ],
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders',
    );

    await openRowMenu(tester, '101');
    await tapIn(tester, find.byKey(WorkOrdersScreen.assignKey('101')));
    await tester.pumpAndSettle();

    // The lapsed holder: both keys present, and the text says so.
    expect(find.byKey(WorkOrderAssignDialog.skillChipKey('20', '5')), findsOneWidget);
    expect(find.byKey(WorkOrderAssignDialog.lapsedChipKey('20', '5')), findsOneWidget);
    expect(find.text('Welding · Lapsed'), findsOneWidget);

    // A current holder: the skill chip is present, the lapsed one is not.
    expect(find.byKey(WorkOrderAssignDialog.skillChipKey('21', '6')), findsOneWidget);
    expect(find.byKey(WorkOrderAssignDialog.lapsedChipKey('21', '6')), findsNothing);

    // A candidate with nothing recorded: the plain fact, not a blank.
    expect(find.text('No qualifications recorded'), findsOneWidget);
  });

  testWidgets('a candidate with only a lapsed qualification can still be chosen and assigned',
      (tester) async {
    final wire = wireWith(
      workOrders: {
        '1': [workOrderJson('101', 'WO-101', 'Belt is slipping')],
      },
      assigneeCandidates: [
        assigneeCandidateJson(
          '20',
          'Jane Doe',
          skills: [
            heldSkillJson('1', '5', 'WELD', 'Welding', isLapsed: true, expiresOn: '2020-01-01'),
          ],
        ),
      ],
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders',
    );

    await openRowMenu(tester, '101');
    await tapIn(tester, find.byKey(WorkOrdersScreen.assignKey('101')));
    await tester.pumpAndSettle();

    await tapIn(tester, find.byKey(WorkOrderAssignDialog.candidateKey('20')));
    await tapIn(tester, find.byKey(WorkOrderAssignDialog.submitKey));

    expect(wire.workOrderAssignRequests.length, 1);
    expect(wire.workOrderAssignRequests.single.$2, {'employeeId': '20'});
  });

  testWidgets('assigning sends exactly one request, carrying the chosen Employee', (tester) async {
    final wire = wireWith(
      workOrders: {
        '1': [workOrderJson('101', 'WO-101', 'Belt is slipping')],
      },
      assigneeCandidates: [
        assigneeCandidateJson('20', 'Jane Doe'),
        assigneeCandidateJson('21', 'John Smith'),
      ],
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders',
    );

    await openRowMenu(tester, '101');
    await tapIn(tester, find.byKey(WorkOrdersScreen.assignKey('101')));
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(WorkOrderAssignDialog.candidateKey('21')));
    await tapIn(tester, find.byKey(WorkOrderAssignDialog.submitKey));

    expect(wire.workOrderAssignRequests.length, 1);
    final (id, body) = wire.workOrderAssignRequests.single;
    expect(id, '101');
    expect(body, {'employeeId': '21'});
  });

  testWidgets('the assignee appears on the row afterwards, without re-reading the list',
      (tester) async {
    final wire = wireWith(
      workOrders: {
        '1': [workOrderJson('101', 'WO-101', 'Belt is slipping')],
      },
      assigneeCandidates: [assigneeCandidateJson('20', 'Jane Doe')],
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders',
    );

    final requestsBefore = wire.workOrderRequests.length;

    await openRowMenu(tester, '101');
    await tapIn(tester, find.byKey(WorkOrdersScreen.assignKey('101')));
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(WorkOrderAssignDialog.candidateKey('20')));
    await tapIn(tester, find.byKey(WorkOrderAssignDialog.submitKey));

    expect(find.byType(WorkOrderAssignDialog), findsNothing);
    expect(find.text('Jane Doe'), findsOneWidget);
    expect(wire.workOrderRequests.length, requestsBefore);
  });

  testWidgets('a row already assigned offers Reassign, and moving it replaces the name',
      (tester) async {
    final wire = wireWith(
      workOrders: {
        '1': [
          workOrderJson('101', 'WO-101', 'Belt is slipping', assignedTo: '20', assigneeName: 'Jane Doe'),
        ],
      },
      assigneeCandidates: [
        assigneeCandidateJson('20', 'Jane Doe'),
        assigneeCandidateJson('21', 'John Smith'),
      ],
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders',
    );

    // Assign/Reassign lives in the row's own overflow menu since issue #104
    // (Decision C) rather than as an always-rendered inline button — opening
    // the menu is what proves the label already reads "Reassign" for a row
    // that already has somebody.
    await openRowMenu(tester, '101');
    expect(find.widgetWithText(PopupMenuItem<Key>, 'Reassign'), findsOneWidget);
    await tapIn(tester, find.byKey(WorkOrdersScreen.assignKey('101')));
    await tester.pumpAndSettle();
    // The dialog's own submit button follows the menu item in switching to
    // Reassign for an already-assigned Work order.
    expect(find.widgetWithText(FilledButton, 'Reassign'), findsOneWidget);
    await tapIn(tester, find.byKey(WorkOrderAssignDialog.candidateKey('21')));
    await tapIn(tester, find.byKey(WorkOrderAssignDialog.submitKey));

    expect(find.text('John Smith'), findsOneWidget);
    expect(find.text('Jane Doe'), findsNothing);
  });

  testWidgets('a refusal is surfaced in the dialog, which stays open', (tester) async {
    final wire = wireWith(
      workOrders: {
        '1': [workOrderJson('101', 'WO-101', 'Belt is slipping')],
      },
      assigneeCandidates: [assigneeCandidateJson('20', 'Jane Doe')],
      assignWorkOrderStatus: 403,
    )..assignWorkOrderMessage = 'You do not hold a Grant reaching this Work order.';
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders',
    );

    await openRowMenu(tester, '101');
    await tapIn(tester, find.byKey(WorkOrdersScreen.assignKey('101')));
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(WorkOrderAssignDialog.candidateKey('20')));
    await tapIn(tester, find.byKey(WorkOrderAssignDialog.submitKey));

    expect(find.byType(WorkOrderAssignDialog), findsOneWidget);
    expect(find.byKey(WorkOrderAssignDialog.failureKey), findsOneWidget);
    expect(find.text('You do not hold a Grant reaching this Work order.'), findsOneWidget);
  });

  testWidgets('a caller with no write Grant is offered no way to assign', (tester) async {
    final wire = wireWith(
      role: Roles.supervisor,
      orgUnitScope: {'everywhere': false, 'grants': [scopeGrantJson('10')]},
      workOrders: {
        '1': [workOrderJson('101', 'WO-101', 'Belt is slipping')],
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders',
    );

    expect(find.text('Belt is slipping'), findsOneWidget);
    expect(find.byKey(WorkOrdersScreen.assignKey('101')), findsNothing);
  });

  testWidgets('a Departed Employee is not offered as a candidate', (tester) async {
    final wire = wireWith(
      workOrders: {
        '1': [workOrderJson('101', 'WO-101', 'Belt is slipping')],
      },
      // The server excludes a Departed Employee from this list entirely — the
      // client offers only who it was given (AC8's client half).
      assigneeCandidates: [assigneeCandidateJson('20', 'Jane Doe')],
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders',
    );

    await openRowMenu(tester, '101');
    await tapIn(tester, find.byKey(WorkOrdersScreen.assignKey('101')));
    await tester.pumpAndSettle();

    expect(find.text('Jane Doe'), findsOneWidget);
    expect(find.byType(RadioListTile<String>), findsOneWidget);
  });

  testWidgets('the assign action is not offered while an assign is in flight', (tester) async {
    final wire = wireWith(
      workOrders: {
        '1': [workOrderJson('101', 'WO-101', 'Belt is slipping')],
      },
      assigneeCandidates: [assigneeCandidateJson('20', 'Jane Doe')],
    )..workOrderAssignGate = Completer<void>();
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders',
    );

    await openRowMenu(tester, '101');
    await tapIn(tester, find.byKey(WorkOrdersScreen.assignKey('101')));
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(WorkOrderAssignDialog.candidateKey('20')));
    // The assign starts and hangs on the gate — `tapIn`'s own `pumpAndSettle`
    // only waits out animations, not the pending request, the same as
    // `assets_test.dart`'s own gated-mutation test.
    await tapIn(tester, find.byKey(WorkOrderAssignDialog.submitKey));

    // The row's own overflow trigger reflects the Bloc's isAssigning
    // underneath the still-open dialog — since issue #104 (Decision C) the
    // menu cannot even be opened while busy, so this is read off the
    // trigger's own `onPressed` rather than a menu item that cannot be
    // reached inside a closed menu.
    final trigger = tester.widget<IconButton>(find.byKey(WorkOrdersScreen.rowActionsKey('101')));
    expect(trigger.onPressed, isNull);

    wire.workOrderAssignGate!.complete();
    await tester.pumpAndSettle();
  });

  // Working a Work order — start, complete, cancel (issue #63). What these
  // tests claim and what they do not: that the right action is offered for a
  // row's status and no other, that each sends exactly one request carrying
  // whatever the dialog collected, that a completed or cancelled row leaves
  // the open list without a re-read, and that the history toggle asks the
  // server for it. Not that the server enforces the state machine, the
  // write-Grant scope, or the "already started"/"already completed"
  // refusals. Those are proved in `backend/test/integration/work-orders.test.js`,
  // and neither substitutes for the other.

  testWidgets('an approved row offers Start and Cancel, and no Complete', (tester) async {
    final wire = wireWith(
      workOrders: {
        '1': [workOrderJson('101', 'WO-101', 'Belt is slipping')],
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders',
    );

    // Start is still inline (issue #104, Decision C), so this assertion
    // stays exactly as it was.
    expect(find.byKey(WorkOrdersScreen.startKey('101')), findsOneWidget);
    expect(find.byKey(WorkOrdersScreen.completeKey('101')), findsNothing);

    // Cancel moved into the row's own overflow menu — its presence can only
    // be asserted once that menu is open, since `PopupMenuItem`'s own
    // `itemBuilder`-equivalent is not built into the tree while the menu is
    // closed.
    await openRowMenu(tester, '101');
    expect(find.byKey(WorkOrdersScreen.cancelKey('101')), findsOneWidget);
  });

  testWidgets('an in_progress row offers Complete and Cancel, and no Start', (tester) async {
    final wire = wireWith(
      workOrders: {
        '1': [workOrderJson('101', 'WO-101', 'Belt is slipping', status: 'in_progress')],
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders',
    );

    // Complete is still inline (issue #104, Decision C), so this assertion
    // stays exactly as it was.
    expect(find.byKey(WorkOrdersScreen.completeKey('101')), findsOneWidget);
    expect(find.byKey(WorkOrdersScreen.startKey('101')), findsNothing);

    // Cancel moved into the row's own overflow menu — see the same note on
    // the `approved` row test above.
    await openRowMenu(tester, '101');
    expect(find.byKey(WorkOrdersScreen.cancelKey('101')), findsOneWidget);
  });

  testWidgets('a completed row offers no transition at all', (tester) async {
    final wire = wireWith(
      workOrders: {
        '1': [workOrderJson('101', 'WO-101', 'Belt is slipping', status: 'completed')],
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders',
    );

    // The completed row is only reachable through history — the default read
    // excludes it, the same as the server's own open-list filter.
    await tapIn(tester, find.byKey(WorkOrdersScreen.showHistoryKey));

    expect(find.byKey(WorkOrdersScreen.rowKey('101')), findsOneWidget);
    expect(find.byKey(WorkOrdersScreen.startKey('101')), findsNothing);
    expect(find.byKey(WorkOrdersScreen.completeKey('101')), findsNothing);
    expect(find.byKey(WorkOrdersScreen.cancelKey('101')), findsNothing);
  });

  testWidgets('starting sends exactly one request, and the row moves to In progress',
      (tester) async {
    final wire = wireWith(
      workOrders: {
        '1': [workOrderJson('101', 'WO-101', 'Belt is slipping')],
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders',
    );

    await tapIn(tester, find.byKey(WorkOrdersScreen.startKey('101')));

    expect(wire.workOrderStarts, ['101']);
    expect(find.text('In progress'), findsOneWidget);
  });

  testWidgets('completing sends exactly one request, carrying the note', (tester) async {
    final wire = wireWith(
      workOrders: {
        '1': [workOrderJson('101', 'WO-101', 'Belt is slipping', status: 'in_progress')],
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders',
    );

    await tapIn(tester, find.byKey(WorkOrdersScreen.completeKey('101')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(WorkOrderCompleteDialog.noteKey), 'Belt replaced');
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(WorkOrderCompleteDialog.submitKey));

    expect(wire.workOrderCompletions.length, 1);
    final (id, body) = wire.workOrderCompletions.single;
    expect(id, '101');
    expect(body['note'], 'Belt replaced');
  });

  testWidgets('cancelling sends exactly one request, carrying the reason', (tester) async {
    final wire = wireWith(
      workOrders: {
        '1': [workOrderJson('101', 'WO-101', 'Belt is slipping')],
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders',
    );

    await openRowMenu(tester, '101');
    await tapIn(tester, find.byKey(WorkOrdersScreen.cancelKey('101')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(WorkOrderCancelDialog.reasonKey), 'Raised by mistake');
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(WorkOrderCancelDialog.submitKey));

    expect(wire.workOrderCancellations.length, 1);
    final (id, body) = wire.workOrderCancellations.single;
    expect(id, '101');
    expect(body['reason'], 'Raised by mistake');
  });

  testWidgets('a completed row leaves the open list without a re-read', (tester) async {
    final wire = wireWith(
      workOrders: {
        '1': [workOrderJson('101', 'WO-101', 'Belt is slipping', status: 'in_progress')],
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders',
    );

    final requestsBefore = wire.workOrderRequests.length;

    await tapIn(tester, find.byKey(WorkOrdersScreen.completeKey('101')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(WorkOrderCompleteDialog.noteKey), 'Belt replaced');
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(WorkOrderCompleteDialog.submitKey));

    expect(find.byKey(WorkOrdersScreen.rowKey('101')), findsNothing);
    expect(wire.workOrderRequests.length, requestsBefore);
  });

  testWidgets('a cancelled row leaves the open list without a re-read', (tester) async {
    final wire = wireWith(
      workOrders: {
        '1': [workOrderJson('101', 'WO-101', 'Belt is slipping')],
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders',
    );

    final requestsBefore = wire.workOrderRequests.length;

    await openRowMenu(tester, '101');
    await tapIn(tester, find.byKey(WorkOrdersScreen.cancelKey('101')));
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(WorkOrderCancelDialog.submitKey));

    expect(find.byKey(WorkOrdersScreen.rowKey('101')), findsNothing);
    expect(wire.workOrderRequests.length, requestsBefore);
  });

  testWidgets('a caller with no write Grant is offered no transition at all', (tester) async {
    final wire = wireWith(
      role: Roles.supervisor,
      orgUnitScope: {'everywhere': false, 'grants': [scopeGrantJson('10')]},
      workOrders: {
        '1': [workOrderJson('101', 'WO-101', 'Belt is slipping')],
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders',
    );

    expect(find.byKey(WorkOrdersScreen.startKey('101')), findsNothing);
    expect(find.byKey(WorkOrdersScreen.completeKey('101')), findsNothing);
    expect(find.byKey(WorkOrdersScreen.cancelKey('101')), findsNothing);
  });

  testWidgets('no transition is offered while one is in flight', (tester) async {
    final wire = wireWith(
      workOrders: {
        '1': [workOrderJson('101', 'WO-101', 'Belt is slipping')],
      },
    )..workOrderTransitionGate = Completer<void>();
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders',
    );

    // The start starts and hangs on the gate — `tapIn`'s own `pumpAndSettle`
    // only waits out animations, not the pending request, the same as
    // `assets_test.dart`'s own gated-mutation test.
    await tapIn(tester, find.byKey(WorkOrdersScreen.startKey('101')));

    // `isTransitioning` disables every row's own actions underneath, the
    // same as `isAssigning` already does. Cancel sits behind the row's
    // overflow trigger since issue #104 (Decision C), so it is that
    // trigger's own `onPressed` that is checked — the menu cannot even be
    // opened while busy, so there is no menu item to reach into.
    final startButton = tester.widget<OutlinedButton>(find.byKey(WorkOrdersScreen.startKey('101')));
    expect(startButton.onPressed, isNull);
    final overflowTrigger =
        tester.widget<IconButton>(find.byKey(WorkOrdersScreen.rowActionsKey('101')));
    expect(overflowTrigger.onPressed, isNull);

    wire.workOrderTransitionGate!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('a refusal is surfaced in the complete dialog, which stays open', (tester) async {
    final wire = wireWith(
      workOrders: {
        '1': [workOrderJson('101', 'WO-101', 'Belt is slipping', status: 'in_progress')],
      },
      completeWorkOrderStatus: 409,
    )..completeWorkOrderMessage =
        'this Work order has not been started, so it cannot be completed';
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders',
    );

    await tapIn(tester, find.byKey(WorkOrdersScreen.completeKey('101')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(WorkOrderCompleteDialog.noteKey), 'Belt replaced');
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(WorkOrderCompleteDialog.submitKey));

    expect(find.byType(WorkOrderCompleteDialog), findsOneWidget);
    expect(find.byKey(WorkOrderCompleteDialog.failureKey), findsOneWidget);
    expect(
      find.text('this Work order has not been started, so it cannot be completed'),
      findsOneWidget,
    );
  });

  testWidgets('showing history asks the server for it and brings completed rows back',
      (tester) async {
    final wire = wireWith(
      workOrders: {
        '1': [
          workOrderJson('101', 'WO-101', 'Belt is slipping'),
          workOrderJson('102', 'WO-102', 'Guard is loose', status: 'completed'),
        ],
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders',
    );

    expect(find.text('Belt is slipping'), findsOneWidget);
    expect(find.text('Guard is loose'), findsNothing);

    await tapIn(tester, find.byKey(WorkOrdersScreen.showHistoryKey));

    expect(wire.workOrderRequests.last.$3, isTrue);
    expect(find.text('Guard is loose'), findsOneWidget);
  });

  testWidgets(
      'a transition on a row that is showing in history replaces it in place rather than '
      'removing it', (tester) async {
    final wire = wireWith(
      workOrders: {
        '1': [workOrderJson('101', 'WO-101', 'Belt is slipping', status: 'in_progress')],
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders',
    );

    await tapIn(tester, find.byKey(WorkOrdersScreen.showHistoryKey));
    expect(find.byKey(WorkOrdersScreen.rowKey('101')), findsOneWidget);

    final requestsBefore = wire.workOrderRequests.length;

    await tapIn(tester, find.byKey(WorkOrdersScreen.completeKey('101')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(WorkOrderCompleteDialog.noteKey), 'Belt replaced');
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(WorkOrderCompleteDialog.submitKey));

    expect(find.byKey(WorkOrdersScreen.rowKey('101')), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(wire.workOrderRequests.length, requestsBefore);
  });

  // Addressable dialogs (issue #104, Decision A, ADR-0019). What these tests
  // claim: each of the four dialogs is reachable by its own `go_router`
  // address, over a list that stays visible and readable underneath; that
  // dismissing one returns the address to the list; and that a stale or
  // unauthorised address is refused with its own explained dialog rather
  // than a hang or a silent redirect. Not that the server enforces any of
  // the underlying writes — that is `work-orders.test.js`'s job.

  testWidgets('a deep link straight to the raise address opens the dialog over the list',
      (tester) async {
    final wire = wireWith(
      workOrders: {
        '1': [workOrderJson('101', 'WO-101', 'Belt is slipping')],
      },
      assets: {
        '1': [assetJson('7', 'PRESS-1', 'Press 1')],
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders/new',
    );

    expect(find.byType(WorkOrderFormDialog), findsOneWidget);
    expect(find.byKey(WorkOrdersScreen.rowKey('101')), findsOneWidget);
  });

  testWidgets('a deep link straight to the assign address opens the dialog over the list',
      (tester) async {
    final wire = wireWith(
      workOrders: {
        '1': [workOrderJson('101', 'WO-101', 'Belt is slipping')],
      },
      assigneeCandidates: [assigneeCandidateJson('20', 'Jane Doe')],
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders/101/assign',
    );

    expect(find.byType(WorkOrderAssignDialog), findsOneWidget);
    expect(find.byKey(WorkOrdersScreen.rowKey('101')), findsOneWidget);
  });

  testWidgets('a deep link straight to the complete address opens the dialog over the list',
      (tester) async {
    final wire = wireWith(
      workOrders: {
        '1': [workOrderJson('101', 'WO-101', 'Belt is slipping', status: 'in_progress')],
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders/101/complete',
    );

    expect(find.byType(WorkOrderCompleteDialog), findsOneWidget);
    expect(find.byKey(WorkOrdersScreen.rowKey('101')), findsOneWidget);
  });

  testWidgets('a deep link straight to the cancel address opens the dialog over the list',
      (tester) async {
    final wire = wireWith(
      workOrders: {
        '1': [workOrderJson('101', 'WO-101', 'Belt is slipping')],
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders/101/cancel',
    );

    expect(find.byType(WorkOrderCancelDialog), findsOneWidget);
    expect(find.byKey(WorkOrdersScreen.rowKey('101')), findsOneWidget);
  });

  testWidgets(
      'the raise button navigates to its own address, and dismissing the dialog returns to '
      'the list address', (tester) async {
    final wire = wireWith(
      workOrders: {'1': []},
      assets: {
        '1': [assetJson('7', 'PRESS-1', 'Press 1')],
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders',
    );

    await tapIn(tester, find.byKey(WorkOrdersScreen.raiseKey));

    expect(locationOf(tester, find.byType(WorkOrdersScreen)), '/work-orders/new');

    await tapIn(tester, find.byKey(WorkOrderFormDialog.cancelKey));

    expect(find.byType(WorkOrderFormDialog), findsNothing);
    expect(locationOf(tester, find.byType(WorkOrdersScreen)), '/work-orders');
  });

  testWidgets(
      "the row overflow's Assign item navigates to its own address, and dismissing the "
      'dialog returns to the list address', (tester) async {
    final wire = wireWith(
      workOrders: {
        '1': [workOrderJson('101', 'WO-101', 'Belt is slipping')],
      },
      assigneeCandidates: [assigneeCandidateJson('20', 'Jane Doe')],
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders',
    );

    await openRowMenu(tester, '101');
    await tapIn(tester, find.byKey(WorkOrdersScreen.assignKey('101')));

    expect(locationOf(tester, find.byType(WorkOrdersScreen)), '/work-orders/101/assign');

    await tapIn(tester, find.byKey(WorkOrderAssignDialog.cancelKey));

    expect(find.byType(WorkOrderAssignDialog), findsNothing);
    expect(locationOf(tester, find.byType(WorkOrdersScreen)), '/work-orders');
  });

  testWidgets(
      'the Complete button navigates to its own address, and dismissing the dialog returns '
      'to the list address', (tester) async {
    final wire = wireWith(
      workOrders: {
        '1': [workOrderJson('101', 'WO-101', 'Belt is slipping', status: 'in_progress')],
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders',
    );

    await tapIn(tester, find.byKey(WorkOrdersScreen.completeKey('101')));

    expect(locationOf(tester, find.byType(WorkOrdersScreen)), '/work-orders/101/complete');

    await tapIn(tester, find.byKey(WorkOrderCompleteDialog.dismissKey));

    expect(find.byType(WorkOrderCompleteDialog), findsNothing);
    expect(locationOf(tester, find.byType(WorkOrdersScreen)), '/work-orders');
  });

  testWidgets(
      "the row overflow's Cancel item navigates to its own address, and dismissing the "
      'dialog returns to the list address', (tester) async {
    final wire = wireWith(
      workOrders: {
        '1': [workOrderJson('101', 'WO-101', 'Belt is slipping')],
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders',
    );

    await openRowMenu(tester, '101');
    await tapIn(tester, find.byKey(WorkOrdersScreen.cancelKey('101')));

    expect(locationOf(tester, find.byType(WorkOrdersScreen)), '/work-orders/101/cancel');

    await tapIn(tester, find.byKey(WorkOrderCancelDialog.dismissKey));

    expect(find.byType(WorkOrderCancelDialog), findsNothing);
    expect(locationOf(tester, find.byType(WorkOrdersScreen)), '/work-orders');
  });

  testWidgets('an id not in the loaded list renders the not-found dialog, not a hang',
      (tester) async {
    final wire = wireWith(
      workOrders: {
        '1': [workOrderJson('101', 'WO-101', 'Belt is slipping')],
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders/999/assign',
    );

    expect(find.byKey(WorkOrderDialogHost.notFoundKey), findsOneWidget);
    expect(find.byType(WorkOrderAssignDialog), findsNothing);
  });

  testWidgets(
      "a still-loading list renders the dialog host's own loading placeholder, not "
      'not-found', (tester) async {
    final wire = wireWith(
      workOrders: {
        '1': [workOrderJson('101', 'WO-101', 'Belt is slipping')],
      },
    )..workOrdersGate = Completer<void>();
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders/101/assign',
      settle: false,
    );

    expect(find.byKey(WorkOrderDialogHost.loadingKey), findsOneWidget);
    expect(find.byKey(WorkOrderDialogHost.notFoundKey), findsNothing);

    wire.workOrdersGate!.complete();
    await tester.pumpAndSettle();

    expect(find.byType(WorkOrderAssignDialog), findsOneWidget);
  });

  testWidgets(
      'a caller with no write Grant hitting the assign address directly is refused, and no '
      'candidates request is sent', (tester) async {
    final wire = wireWith(
      role: Roles.supervisor,
      orgUnitScope: {'everywhere': false, 'grants': [scopeGrantJson('10')]},
      workOrders: {
        '1': [workOrderJson('101', 'WO-101', 'Belt is slipping')],
      },
      assigneeCandidates: [assigneeCandidateJson('20', 'Jane Doe')],
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders/101/assign',
    );

    expect(find.byKey(WorkOrderDialogHost.notAvailableKey), findsOneWidget);
    expect(find.byType(WorkOrderAssignDialog), findsNothing);
    expect(wire.requests.any((r) => r.contains('assignee-candidates')), isFalse);
  });

  testWidgets(
      'hitting the complete address on a row that is approved, not in_progress, is refused '
      'rather than opening a form that would 409', (tester) async {
    final wire = wireWith(
      workOrders: {
        '1': [workOrderJson('101', 'WO-101', 'Belt is slipping')],
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders/101/complete',
    );

    expect(find.byKey(WorkOrderDialogHost.notAvailableKey), findsOneWidget);
    expect(find.byType(WorkOrderCompleteDialog), findsNothing);
  });

  // Filter chips (issue #104, Decision D).

  testWidgets(
      'the applied Org Unit filter renders as a removable chip, and its delete affordance '
      'clears it the same way it always did', (tester) async {
    final wire = wireWith(
      workOrders: {
        '1': [
          workOrderJson('101', 'WO-101', 'Belt is slipping'),
          workOrderJson('102', 'WO-102', 'Guard is loose', orgUnitId: '10', orgUnitName: 'Assembly'),
        ],
      },
    );
    wire.workOrdersByFilter['1|10'] = [
      workOrderJson('102', 'WO-102', 'Guard is loose', orgUnitId: '10', orgUnitName: 'Assembly'),
    ];
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders',
    );

    await tapIn(tester, find.byKey(WorkOrdersScreen.filterKey));
    await tapIn(tester, find.byKey(OrgUnitChooser.chooseKey('10')));

    expect(find.byType(Chip), findsWidgets);
    expect(find.text('Narrowed to Assembly'), findsOneWidget);

    await tapIn(tester, find.byKey(WorkOrdersScreen.clearFilterKey));

    expect(wire.workOrderRequests.last, ('1', null, false));
    expect(find.text('Belt is slipping'), findsOneWidget);
    expect(find.text('Guard is loose'), findsOneWidget);
    expect(find.byKey(WorkOrdersScreen.filterKey), findsOneWidget);
  });

  // The narrow layout (issue #104, Decision E).

  testWidgets(
      'below 700px the list renders as cards carrying the number, summary, Asset, Org Unit, '
      'status and the primary action, with no horizontal scroll', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(600, 800);
    addTearDown(tester.view.reset);

    final wire = wireWith(
      workOrders: {
        '1': [workOrderJson('101', 'WO-101', 'Belt is slipping')],
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders',
    );

    expect(find.byKey(WorkOrdersScreen.rowKey('101')), findsOneWidget);
    expect(find.text('WO-101'), findsOneWidget);
    expect(find.text('Belt is slipping'), findsOneWidget);
    expect(find.text('Press 1 (PRESS-1) · Corrective'), findsOneWidget);
    expect(find.text('Line 1'), findsOneWidget);
    expect(find.text('Approved'), findsOneWidget);
    expect(find.byKey(WorkOrdersScreen.startKey('101')), findsOneWidget);
    expect(find.byKey(WorkOrdersScreen.rowActionsKey('101')), findsOneWidget);

    // No horizontally-scrolling container wraps the row content — the shape
    // this ticket bans outright, at every width.
    expect(
      find.descendant(
        of: find.byType(WorkOrdersScreen),
        matching: find.byType(SingleChildScrollView),
      ),
      findsNothing,
    );
  });

  // Accessibility (issue #104): a visible focus indicator for a control this
  // Screen adds (the overflow trigger) and one it already had (a row's own
  // primary button) — verified by reading the resolved `ButtonStyle` back
  // off a pumped `Theme.of(context)`, per this ticket's own suggestion,
  // rather than simulating a real Tab key press: every control here is a
  // standard Material button (`OutlinedButton`, `IconButton`), which is
  // focusable and reachable in paint order by default with no custom
  // `FocusTraversalOrder` applied anywhere on this Screen, so paint order —
  // header, then filter, then each row top to bottom, primary before
  // overflow — already is tab order.

  testWidgets(
      "a row's primary button and its overflow trigger both resolve the theme's own focus "
      'ring for a focused state', (tester) async {
    final wire = wireWith(
      workOrders: {
        '1': [workOrderJson('101', 'WO-101', 'Belt is slipping')],
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders',
    );

    final theme = Theme.of(tester.element(find.byType(WorkOrdersScreen)));
    final outlinedFocusSide =
        theme.outlinedButtonTheme.style?.side?.resolve({WidgetState.focused});
    final outlinedFocusOverlay =
        theme.outlinedButtonTheme.style?.overlayColor?.resolve({WidgetState.focused});
    final iconFocusSide = theme.iconButtonTheme.style?.side?.resolve({WidgetState.focused});

    expect(outlinedFocusSide?.color, AppComponentColors.focusRing);
    expect(outlinedFocusOverlay, isNotNull);
    expect(iconFocusSide?.color, AppComponentColors.focusRing);

    // Unfocused, neither control claims the ring — it is only ever the
    // focused state's own decoration.
    expect(theme.outlinedButtonTheme.style?.side?.resolve({}), isNull);
  });
}
