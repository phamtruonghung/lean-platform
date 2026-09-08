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
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/maintenance/org_unit_chooser.dart';
import 'package:lean_platform/maintenance/work_order_assign_dialog.dart';
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
  List<Map<String, dynamic>>? assigneeCandidates,
  int assignWorkOrderStatus = 200,
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

    expect(find.widgetWithText(OutlinedButton, 'Reassign'), findsOneWidget);

    await tapIn(tester, find.byKey(WorkOrdersScreen.assignKey('101')));
    await tester.pumpAndSettle();
    // The dialog's own submit button follows the title and the row button in
    // switching to Reassign for an already-assigned Work order.
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

    await tapIn(tester, find.byKey(WorkOrdersScreen.assignKey('101')));
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(WorkOrderAssignDialog.candidateKey('20')));
    // The assign starts and hangs on the gate — `tapIn`'s own `pumpAndSettle`
    // only waits out animations, not the pending request, the same as
    // `assets_test.dart`'s own gated-mutation test.
    await tapIn(tester, find.byKey(WorkOrderAssignDialog.submitKey));

    // The row's own button reflects the Bloc's isAssigning underneath the
    // still-open dialog.
    final button = tester.widget<OutlinedButton>(find.byKey(WorkOrdersScreen.assignKey('101')));
    expect(button.onPressed, isNull);

    wire.workOrderAssignGate!.complete();
    await tester.pumpAndSettle();
  });
}
