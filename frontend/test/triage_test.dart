/// The triage queue (issue #72), with the wire faked. Covers the acceptance
/// criteria the ticket names for the client: accepting, declining and marking
/// a duplicate each send one request, the decided Request leaves the open
/// queue, and a caller without a write Grant is offered no triage action.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/maintenance/triage_dialogs.dart';
import 'package:lean_platform/maintenance/triage_screen.dart';
import 'package:lean_platform/platform/destinations.dart';

import 'harness.dart';

FakeWire wireWith({
  String role = Roles.supervisor,
  Map<String, dynamic>? orgUnitScope,
  List<Map<String, dynamic>>? requests,
  int requestsStatus = 200,
  int acceptStatus = 200,
  int declineStatus = 200,
  int duplicateStatus = 200,
  String? acceptMessage,
}) =>
    FakeWire(
      role: role,
      // Defaults to a supervisor holding a write Grant on the Site's Org Unit,
      // which is what earns the triage affordances (issue #72).
      orgUnitScope: orgUnitScope ??
          {'everywhere': false, 'grants': [scopeGrantJson('10', canWrite: true)]},
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      requests: requests ?? [],
      requestsStatus: requestsStatus,
      acceptStatus: acceptStatus,
      declineStatus: declineStatus,
      duplicateStatus: duplicateStatus,
      acceptMessage: acceptMessage ?? 'That Request could not be accepted.',
    );

void main() {
  testWidgets('a maintenance role gets the triage Destination', (tester) async {
    final wire = wireWith(requests: []);
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/triage',
    );

    expect(find.byType(TriageScreen), findsOneWidget);
    expect(find.text('Triage'), findsWidgets);
  });

  testWidgets('a loading queue shows placeholders; a failed load explains itself and retries', (tester) async {
    final wire = wireWith(requestsStatus: 503);
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/triage',
    );

    expect(find.byKey(TriageScreen.failedKey), findsOneWidget);
    expect(find.text('The queue could not be read'), findsOneWidget);

    wire.requestsStatus = 200;
    wire.requestRows = [requestJson('101', 'RQT-101', 'Belt is slipping')];
    await tapIn(tester, find.byKey(TriageScreen.retryKey));

    expect(find.byKey(TriageScreen.failedKey), findsNothing);
    expect(find.text('Belt is slipping'), findsOneWidget);
  });

  testWidgets('an empty queue says plainly there is nothing waiting', (tester) async {
    final wire = wireWith(requests: []);
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/triage',
    );

    expect(find.byKey(TriageScreen.emptyKey), findsOneWidget);
    expect(find.text('Nothing waiting'), findsOneWidget);
  });

  testWidgets('accepting sends one request with the maintenance plan, and the Request leaves the queue', (tester) async {
    final wire = wireWith(
      requests: [requestJson('101', 'RQT-101', 'Belt is slipping')],
      acceptStatus: 200,
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/triage',
    );

    expect(find.byKey(TriageScreen.acceptKey('101')), findsOneWidget);
    await tapIn(tester, find.byKey(TriageScreen.acceptKey('101')));

    await tapIn(tester, find.byKey(AcceptRequestDialog.workTypeKey));
    await tapIn(tester, find.text('Corrective').last);
    await tapIn(tester, find.byKey(AcceptRequestDialog.priorityKey));
    await tapIn(tester, find.text('2 - Urgent').last);
    await tapIn(tester, find.byKey(AcceptRequestDialog.confirmKey));

    expect(wire.triagePosts, hasLength(1));
    final (id, action, body) = wire.triagePosts.single;
    expect(id, '101');
    expect(action, 'accept');
    expect(body?['workType'], 'corrective');
    expect(body?['priority'], 2);

    // Accepted Request leaves the open queue.
    expect(find.byType(AcceptRequestDialog), findsNothing);
    expect(find.byKey(TriageScreen.rowKey('101')), findsNothing);
  });

  testWidgets('declining requires a reason and sends it; the Request leaves the queue', (tester) async {
    final wire = wireWith(
      requests: [requestJson('101', 'RQT-101', 'Belt is slipping')],
      declineStatus: 200,
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/triage',
    );

    await tapIn(tester, find.byKey(TriageScreen.declineKey('101')));
    // Decline is disabled without a reason.
    expect(tester.widget<FilledButton>(find.byKey(DeclineRequestDialog.confirmKey)).onPressed, isNull);

    await tester.enterText(find.byKey(DeclineRequestDialog.reasonKey), 'Covered by the PM schedule.');
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(DeclineRequestDialog.confirmKey));

    expect(wire.triagePosts, hasLength(1));
    final (id, action, body) = wire.triagePosts.single;
    expect(id, '101');
    expect(action, 'decline');
    expect(body?['reason'], 'Covered by the PM schedule.');

    expect(find.byType(DeclineRequestDialog), findsNothing);
    expect(find.byKey(TriageScreen.rowKey('101')), findsNothing);
  });

  testWidgets('marking a duplicate sends the surviving id and the Request leaves the queue', (tester) async {
    final wire = wireWith(
      requests: [
        requestJson('101', 'RQT-101', 'Belt is slipping'),
        requestJson('102', 'RQT-102', 'Also slipping'),
      ],
      duplicateStatus: 200,
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/triage',
    );

    await tapIn(tester, find.byKey(TriageScreen.duplicateKey('101')));
    await tapIn(tester, find.byKey(DuplicateRequestDialog.targetKey));
    await tapIn(tester, find.text('Also slipping').last);
    await tapIn(tester, find.byKey(DuplicateRequestDialog.confirmKey));

    expect(wire.triagePosts, hasLength(1));
    final (id, action, body) = wire.triagePosts.single;
    expect(id, '101');
    expect(action, 'duplicate');
    expect(body?['duplicateOfId'], '102');

    expect(find.byType(DuplicateRequestDialog), findsNothing);
    expect(find.byKey(TriageScreen.rowKey('101')), findsNothing);
    // The surviving Request stays.
    expect(find.byKey(TriageScreen.rowKey('102')), findsOneWidget);
  });

  testWidgets('a caller with no write Grant is offered no triage action on any row', (tester) async {
    final wire = wireWith(
      role: Roles.supervisor,
      orgUnitScope: {'everywhere': false, 'grants': [scopeGrantJson('10')]},
      requests: [requestJson('101', 'RQT-101', 'Belt is slipping')],
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/triage',
    );

    // The queue is still readable Site-wide, but no triage affordance appears.
    expect(find.byKey(TriageScreen.rowKey('101')), findsOneWidget);
    expect(find.byKey(TriageScreen.acceptKey('101')), findsNothing);
    expect(find.byKey(TriageScreen.declineKey('101')), findsNothing);
    expect(find.byKey(TriageScreen.duplicateKey('101')), findsNothing);
  });
}