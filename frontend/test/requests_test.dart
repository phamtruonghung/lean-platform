/// Maintenance requests and triage (issue #72), with the wire faked — the one
/// client seam (ADR-0012). The real app, the real router, the real Blocs,
/// `MockClient` at the HTTP boundary and `FakeAuthGateway` at the auth
/// boundary.
///
/// What these tests claim and what they do not: that an operator is offered
/// the raise Destination and not the triage queue or the Work order Screen;
/// that raising sends exactly one `POST /api/maintenance/requests` carrying
/// the chosen Asset, summary, urgency and `productionStopped`; that an
/// accepted Request shows the Work order it became; and that declining needs a
/// reason. Not that the server enforces scope, derives the Org Unit, or issues
/// the Request number — those are proved on the backend, in
/// `backend/test/integration/maintenance-requests.test.js`, and neither
/// substitutes for the other.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/maintenance/my_requests_screen.dart';
import 'package:lean_platform/maintenance/request_decline_dialog.dart';
import 'package:lean_platform/maintenance/request_duplicate_dialog.dart';
import 'package:lean_platform/maintenance/request_form_dialog.dart';
import 'package:lean_platform/maintenance/requests_screen.dart';
import 'package:lean_platform/platform/access_denied_screen.dart';
import 'package:lean_platform/platform/destinations.dart';
import 'package:lean_platform/widgets/skeleton_list.dart';

import 'harness.dart';

FakeWire wireWith({
  String role = Roles.operator,
  Map<String, dynamic>? orgUnitScope,
  List<Map<String, dynamic>>? sites,
  Map<String, List<Map<String, dynamic>>>? assets,
  Map<String, List<Map<String, dynamic>>>? requests,
  Map<String, List<Map<String, dynamic>>>? myRequests,
  int requestsStatus = 200,
  int myRequestsStatus = 200,
  int createRequestStatus = 201,
  int acceptRequestStatus = 200,
  int declineRequestStatus = 200,
  int duplicateRequestStatus = 200,
}) =>
    FakeWire(
      role: role,
      orgUnitScope: orgUnitScope,
      sites: sites ?? [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [orgUnitJson('10', 'Assembly')],
      },
      assets: assets ?? {'1': []},
      triageRequests: requests,
      myRequests: myRequests,
      requestsStatus: requestsStatus,
      myRequestsStatus: myRequestsStatus,
      createRequestStatus: createRequestStatus,
      acceptRequestStatus: acceptRequestStatus,
      declineRequestStatus: declineRequestStatus,
      duplicateRequestStatus: duplicateRequestStatus,
    );

void main() {
  // The operator-facing half: the raise Destination, and my-requests.

  testWidgets('an operator is offered the raise Destination and not the triage queue or Work orders',
      (tester) async {
    final wire = wireWith(role: Roles.operator, myRequests: {'1': []});
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/my-requests',
    );

    expect(find.byKey(const ValueKey('nav-item-My requests')), findsOneWidget);
    expect(find.byKey(const ValueKey('nav-item-Triage queue')), findsNothing);
    expect(find.byKey(const ValueKey('nav-item-Work orders')), findsNothing);
    expect(find.byType(MyRequestsScreen), findsOneWidget);
  });

  testWidgets('an operator who types the triage address is refused it', (tester) async {
    final wire = wireWith(role: Roles.operator, requests: {'1': []});
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/requests',
    );

    expect(find.byType(AccessDeniedScreen), findsOneWidget);
    expect(find.byType(RequestsScreen), findsNothing);
    expect(wire.triageRequestSites, isEmpty);
  });

  testWidgets('a supervisor is offered the triage queue Destination', (tester) async {
    final wire = wireWith(
      role: Roles.supervisor,
      orgUnitScope: {'everywhere': false, 'grants': [scopeGrantJson('10', canWrite: true)]},
      requests: {'1': []},
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/requests',
    );

    expect(find.byKey(const ValueKey('nav-item-Triage queue')), findsOneWidget);
    expect(find.byType(RequestsScreen), findsOneWidget);
  });

  testWidgets(
      'raising sends exactly one POST with the chosen Asset, summary, urgency and productionStopped',
      (tester) async {
    final wire = wireWith(
      role: Roles.operator,
      orgUnitScope: {'everywhere': false, 'grants': [scopeGrantJson('10')]},
      assets: {
        '1': [assetJson('7', 'PRESS-1', 'Press 1')],
      },
      myRequests: {'1': []},
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/my-requests',
    );

    await tapIn(tester, find.byKey(MyRequestsScreen.raiseKey));
    await tester.pumpAndSettle();

    await tapIn(tester, find.byKey(RequestFormDialog.assetKey));
    await tapIn(tester, find.text('Press 1 (PRESS-1)').last);

    await tester.enterText(find.byKey(RequestFormDialog.summaryKey), 'Belt is slipping');
    await tester.pumpAndSettle();

    await tapIn(tester, find.byKey(RequestFormDialog.urgencyKey));
    await tapIn(tester, find.text('High').last);

    await tapIn(tester, find.byKey(RequestFormDialog.productionStoppedKey));

    await tapIn(tester, find.byKey(RequestFormDialog.submitKey));

    expect(wire.requestPosts.length, 1);
    final sent = wire.requestPosts.single;
    expect(sent['assetId'], '7');
    expect(sent['summary'], 'Belt is slipping');
    expect(sent['urgency'], 'high');
    expect(sent['productionStopped'], isTrue);
    // The client sends neither the derived Org Unit nor the Request number.
    expect(sent.containsKey('orgUnitId'), isFalse);
    expect(sent.containsKey('requestNo'), isFalse);

    expect(find.byType(RequestFormDialog), findsNothing);
    expect(find.text('MR-900'), findsOneWidget);
  });

  testWidgets('an accepted Request shows the Work order it became', (tester) async {
    final wire = wireWith(
      role: Roles.operator,
      orgUnitScope: {'everywhere': false, 'grants': [scopeGrantJson('10')]},
      myRequests: {
        '1': [
          maintenanceRequestJson(
            '101',
            'MR-101',
            'Pump is noisy',
            status: 'accepted',
            workOrder: requestWorkOrderJson('900', 'WO-900'),
          ),
        ],
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/my-requests',
    );

    expect(find.byKey(MyRequestsScreen.rowKey('101')), findsOneWidget);
    expect(find.text('Became Work order WO-900'), findsOneWidget);
  });

  // Triage: the three row actions and the queue's own states.

  testWidgets('the triage queue lists the open Requests with their actions', (tester) async {
    final wire = wireWith(
      role: Roles.supervisor,
      orgUnitScope: {'everywhere': false, 'grants': [scopeGrantJson('10', canWrite: true)]},
      requests: {
        '1': [maintenanceRequestJson('101', 'MR-101', 'Pump is noisy', urgency: 'high')],
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/requests',
    );

    expect(find.byKey(RequestsScreen.rowKey('101')), findsOneWidget);
    expect(find.text('Pump is noisy'), findsOneWidget);
    expect(find.text('High'), findsOneWidget);
    expect(find.byKey(RequestsScreen.acceptKey('101')), findsOneWidget);
    expect(find.byKey(RequestsScreen.declineKey('101')), findsOneWidget);
    expect(find.byKey(RequestsScreen.duplicateKey('101')), findsOneWidget);
  });

  testWidgets('accepting raises a Work order and the Request leaves the queue', (tester) async {
    final wire = wireWith(
      role: Roles.supervisor,
      orgUnitScope: {'everywhere': false, 'grants': [scopeGrantJson('10', canWrite: true)]},
      requests: {
        '1': [maintenanceRequestJson('101', 'MR-101', 'Pump is noisy')],
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/requests',
    );

    await tapIn(tester, find.byKey(RequestsScreen.acceptKey('101')));

    expect(wire.requestAccepts.length, 1);
    expect(wire.requestAccepts.single.$1, '101');
    expect(find.byKey(RequestsScreen.rowKey('101')), findsNothing);
    expect(find.textContaining('WO-900'), findsOneWidget);
  });

  testWidgets('declining requires a reason, and sends it once it is given', (tester) async {
    final wire = wireWith(
      role: Roles.supervisor,
      orgUnitScope: {'everywhere': false, 'grants': [scopeGrantJson('10', canWrite: true)]},
      requests: {
        '1': [maintenanceRequestJson('101', 'MR-101', 'Pump is noisy')],
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/requests',
    );

    await tapIn(tester, find.byKey(RequestsScreen.declineKey('101')));
    await tester.pumpAndSettle();

    // With no reason typed, the submit button is disabled and nothing is sent.
    final submit = tester.widget<FilledButton>(find.byKey(RequestDeclineDialog.submitKey));
    expect(submit.onPressed, isNull);
    expect(wire.requestDeclines, isEmpty);

    await tester.enterText(find.byKey(RequestDeclineDialog.reasonKey), 'Duplicate of MR-100');
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(RequestDeclineDialog.submitKey));

    expect(wire.requestDeclines.length, 1);
    final (id, body) = wire.requestDeclines.single;
    expect(id, '101');
    expect(body, {'reason': 'Duplicate of MR-100'});
    expect(find.byKey(RequestsScreen.rowKey('101')), findsNothing);
  });

  testWidgets('marking a duplicate names the surviving Request', (tester) async {
    final wire = wireWith(
      role: Roles.supervisor,
      orgUnitScope: {'everywhere': false, 'grants': [scopeGrantJson('10', canWrite: true)]},
      requests: {
        '1': [
          maintenanceRequestJson('101', 'MR-101', 'Pump is noisy'),
          maintenanceRequestJson('102', 'MR-102', 'Pump is making a noise'),
        ],
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/requests',
    );

    await tapIn(tester, find.byKey(RequestsScreen.duplicateKey('101')));
    await tester.pumpAndSettle();

    // The surviving Request is named and selectable; the one being marked is
    // not one of its own candidates.
    expect(find.byKey(RequestDuplicateDialog.candidateKey('102')), findsOneWidget);
    expect(find.byKey(RequestDuplicateDialog.candidateKey('101')), findsNothing);

    await tapIn(tester, find.byKey(RequestDuplicateDialog.candidateKey('102')));
    await tapIn(tester, find.byKey(RequestDuplicateDialog.submitKey));

    expect(wire.requestDuplicates.length, 1);
    final (id, body) = wire.requestDuplicates.single;
    expect(id, '101');
    expect(body, {'duplicateOfId': '102'});
  });

  testWidgets('the triage queue shows placeholders while it loads', (tester) async {
    final wire = wireWith(
      role: Roles.supervisor,
      orgUnitScope: {'everywhere': false, 'grants': [scopeGrantJson('10', canWrite: true)]},
      requests: {'1': []},
    )..requestsGate = Completer<void>();
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/requests',
      settle: false,
    );

    expect(find.byType(SkeletonList), findsOneWidget);
    expect(find.byKey(RequestsScreen.emptyKey), findsNothing);

    wire.requestsGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(SkeletonList), findsNothing);
  });

  testWidgets('an empty triage queue says plainly that nothing is waiting', (tester) async {
    final wire = wireWith(
      role: Roles.supervisor,
      orgUnitScope: {'everywhere': false, 'grants': [scopeGrantJson('10', canWrite: true)]},
      requests: {'1': []},
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/requests',
    );

    expect(find.byKey(RequestsScreen.emptyKey), findsOneWidget);
    expect(find.byKey(RequestsScreen.failedKey), findsNothing);
    expect(find.text('Nothing is waiting'), findsOneWidget);
  });

  testWidgets('a failed triage load explains itself and the retry works', (tester) async {
    final wire = wireWith(
      role: Roles.supervisor,
      orgUnitScope: {'everywhere': false, 'grants': [scopeGrantJson('10', canWrite: true)]},
      requestsStatus: 503,
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/requests',
    );

    expect(find.byKey(RequestsScreen.failedKey), findsOneWidget);
    expect(find.byKey(RequestsScreen.emptyKey), findsNothing);
    expect(find.text('The requests are unavailable.'), findsOneWidget);

    wire.requestsStatus = 200;
    wire.triageRequests = {
      '1': [maintenanceRequestJson('101', 'MR-101', 'Pump is noisy')],
    };
    await tapIn(tester, find.byKey(RequestsScreen.retryKey));

    expect(find.byKey(RequestsScreen.failedKey), findsNothing);
    expect(find.text('Pump is noisy'), findsOneWidget);
  });
}
