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
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/maintenance/org_unit_chooser.dart';
import 'package:lean_platform/maintenance/work_order_form_dialog.dart';
import 'package:lean_platform/maintenance/work_orders_screen.dart';
import 'package:lean_platform/platform/access_denied_screen.dart';
import 'package:lean_platform/platform/destinations.dart';
import 'package:lean_platform/widgets/skeleton_list.dart';

import 'harness.dart';

FakeWire wireWith({
  String role = Roles.admin,
  Map<String, dynamic>? orgUnitScope,
  List<Map<String, dynamic>>? sites,
  Map<String, List<Map<String, dynamic>>>? workOrders,
  int workOrdersStatus = 200,
  Map<String, List<Map<String, dynamic>>>? assets,
  int createWorkOrderStatus = 201,
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
    expect(find.text('open'), findsWidgets);
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
    expect(find.text('No open work at this Site'), findsOneWidget);
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
    expect(wire.workOrderRequests, [('1', null)]);

    await tapIn(tester, find.byKey(WorkOrdersScreen.filterKey));
    await tapIn(tester, find.byKey(OrgUnitChooser.chooseKey('10')));

    expect(wire.workOrderRequests.last, ('1', '10'));
    expect(find.text('Guard is loose'), findsOneWidget);
    expect(find.text('Belt is slipping'), findsNothing);
    expect(find.byKey(WorkOrdersScreen.clearFilterKey), findsOneWidget);

    await tapIn(tester, find.byKey(WorkOrdersScreen.clearFilterKey));

    expect(wire.workOrderRequests.last, ('1', null));
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
}
