/// The requester's view of Requests (issue #72), with the wire faked — the
/// same one client seam ADR-0012 allows. Covers the acceptance criteria the
/// ticket names for the client: an operator is offered the raise Destination
/// and not the triage queue, raising sends one request, and an accepted
/// Request shows the Work order it became.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/maintenance/request_form_dialog.dart';
import 'package:lean_platform/maintenance/requests_screen.dart';
import 'package:lean_platform/maintenance/triage_screen.dart';
import 'package:lean_platform/platform/access_denied_screen.dart';
import 'package:lean_platform/platform/destinations.dart';

import 'harness.dart';

FakeWire wireWith({
  String role = Roles.admin,
  Map<String, dynamic>? orgUnitScope,
  List<Map<String, dynamic>>? sites,
  List<Map<String, dynamic>>? requests,
  int requestsStatus = 200,
  int createRequestStatus = 201,
  String createRequestMessage = 'That Request could not be raised.',
  Map<String, List<Map<String, dynamic>>>? assets,
}) =>
    FakeWire(
      role: role,
      orgUnitScope: orgUnitScope,
      sites: sites ?? [siteJson('1', 'HCM', 'Ho Chi Minh')],
      assets: assets ?? {'1': [assetJson('7', 'PRESS-1', 'Press 1')]},
      requests: requests ?? [],
      requestsStatus: requestsStatus,
      createRequestStatus: createRequestStatus,
      createRequestMessage: createRequestMessage,
    );

void main() {
  testWidgets('an operator is offered Requests and not the triage queue', (tester) async {
    final wire = wireWith(
      role: Roles.operator,
      orgUnitScope: {'everywhere': false, 'grants': [scopeGrantJson('10')]},
      requests: [requestJson('101', 'RQT-101', 'Belt is slipping')],
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/requests',
    );

    expect(find.byType(RequestsScreen), findsOneWidget);
    expect(find.byType(TriageScreen), findsNothing);
    // Requests is in the sidebar for an operator; Triage and Work orders are
    // not (the screen's own title is 'My requests', so the exact label
    // 'Requests' matches only the sidebar entry).
    expect(find.text('Requests'), findsOneWidget);
    expect(find.text('Triage'), findsNothing);
    expect(find.text('Work orders'), findsNothing);
  });

  testWidgets('an operator typing the triage address is refused', (tester) async {
    final wire = wireWith(
      role: Roles.operator,
      orgUnitScope: {'everywhere': false, 'grants': [scopeGrantJson('10')]},
      requests: [],
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/triage',
    );

    expect(find.byType(AccessDeniedScreen), findsOneWidget);
    expect(find.byType(TriageScreen), findsNothing);
  });

  testWidgets('the requester sees what became of each Request, including the Work order an accepted one became', (tester) async {
    final wire = wireWith(
      requests: [
        requestJson('101', 'RQT-101', 'Belt is slipping',
            status: 'accepted', workOrder: requestedWorkOrderJson('900', 'WO-900')),
        requestJson('102', 'RQT-102', 'Guard is loose', status: 'new'),
        requestJson('103', 'RQT-103', 'Noisy pump',
            status: 'rejected', rejectionReason: 'Covered by the PM schedule.'),
      ],
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/requests',
    );

    expect(find.byKey(RequestsScreen.rowKey('101')), findsOneWidget);
    expect(find.byKey(RequestsScreen.rowKey('102')), findsOneWidget);
    expect(find.byKey(RequestsScreen.rowKey('103')), findsOneWidget);
    // Accepted shows the Work order it became (ADR-0014).
    expect(find.textContaining('Accepted as WO-900'), findsOneWidget);
    // Declined shows the reason the requester will read.
    expect(find.textContaining('Covered by the PM schedule'), findsOneWidget);
  });

  testWidgets('an empty requester history says plainly there is nothing yet', (tester) async {
    final wire = wireWith(requests: []);
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/requests',
    );

    expect(find.byKey(RequestsScreen.emptyKey), findsOneWidget);
    expect(find.text('No requests yet'), findsOneWidget);
  });

  testWidgets('raising a Request sends exactly one request with the right body, and the row shows up', (tester) async {
    final wire = wireWith(
      requests: [],
      assets: {
        '1': [assetJson('7', 'PRESS-1', 'Press 1')],
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/requests',
    );

    await tapIn(tester, find.byKey(RequestsScreen.raiseKey));
    await tester.pumpAndSettle();

    await tapIn(tester, find.byKey(RequestFormDialog.assetKey));
    await tapIn(tester, find.text('Press 1 (PRESS-1)').last);
    await tester.enterText(find.byKey(RequestFormDialog.summaryKey), 'Belt is slipping');
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(RequestFormDialog.urgencyKey));
    await tapIn(tester, find.text('High').last);
    await tapIn(tester, find.byKey(RequestFormDialog.submitKey));

    expect(wire.requestPosts, hasLength(1));
    final sent = wire.requestPosts.single;
    expect(sent['assetId'], '7');
    expect(sent['summary'], 'Belt is slipping');
    expect(sent['urgency'], 'high');
    expect(sent.containsKey('orgUnitId'), isFalse);
    expect(sent.containsKey('requestNo'), isFalse);

    expect(find.byType(RequestFormDialog), findsNothing);
    expect(find.text('Belt is slipping'), findsOneWidget);
  });

  testWidgets('a refusal to raise is surfaced in the dialog, which stays open', (tester) async {
    final wire = wireWith(requests: [], createRequestStatus: 403)
      ..createRequestMessage = 'You do not hold a Grant reaching this Asset.';
    wire.assets = {
      '1': [assetJson('7', 'PRESS-1', 'Press 1')],
    };
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/requests',
    );

    await tapIn(tester, find.byKey(RequestsScreen.raiseKey));
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(RequestFormDialog.assetKey));
    await tapIn(tester, find.text('Press 1 (PRESS-1)').last);
    await tester.enterText(find.byKey(RequestFormDialog.summaryKey), 'Belt is slipping');
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(RequestFormDialog.urgencyKey));
    await tapIn(tester, find.text('Normal').last);
    await tapIn(tester, find.byKey(RequestFormDialog.submitKey));

    expect(find.byType(RequestFormDialog), findsOneWidget);
    expect(find.byKey(RequestFormDialog.failureKey), findsOneWidget);
    expect(find.text('You do not hold a Grant reaching this Asset.'), findsOneWidget);
  });
}