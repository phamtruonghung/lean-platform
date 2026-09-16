/// Parts and labour booking on the client (issue #75): booking a window of
/// labour, booking a part, and seeing the Work order's cost summary update —
/// with the wire faked at the HTTP boundary (ADR-0012). The real app, the real
/// router, the real Blocs.
///
/// What these tests claim and what they do not: that a booking sends exactly
/// one request with the right fields, that a `stores` booking names its part
/// and store, and that the re-read cost summary renders. They do not claim the
/// server enforced anything — the derived hours, the stock decrement, the
/// insufficient-stock refusal and the Grant scope refusal are proved on the
/// backend in `backend/test/integration/work-order-cost.test.js`, and neither
/// test substitutes for the other.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/maintenance/labour_booking_dialog.dart';
import 'package:lean_platform/maintenance/part_booking_dialog.dart';
import 'package:lean_platform/maintenance/work_order_detail_screen.dart';
import 'package:lean_platform/maintenance/work_orders_screen.dart';
import 'package:lean_platform/platform/destinations.dart';

import 'harness.dart';

FakeWire wireWith({
  Map<String, List<Map<String, dynamic>>>? workOrders,
  Map<String, Map<String, dynamic>>? workOrderCosts,
  List<Map<String, dynamic>>? employees,
  List<Map<String, dynamic>>? parts,
  Map<String, List<Map<String, dynamic>>>? stores,
}) =>
    FakeWire(
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [orgUnitJson('10', 'Assembly')],
      },
      workOrders: workOrders ??
          {
            '1': [workOrderJson('101', 'WO-101', 'Belt is slipping')],
          },
      workOrderCosts: workOrderCosts ?? {'101': workOrderCostJson()},
      employees: employees ?? [employeeJson('20', 'EMP-20', 'Jane Doe')],
      parts: parts ?? [partJson('3', 'BRG-6204', 'Bearing, 6204')],
      stores: stores ??
          {
            '1': [storeJson('7', 'A-STORE', 'Main store')],
          },
    );

Future<void> openDetail(WidgetTester tester, FakeWire wire) async {
  await pumpApp(
    tester,
    gateway: FakeAuthGateway(accessToken: 'a-token'),
    client: wire.client,
    initialLocation: '/work-orders',
  );
  await tapIn(tester, find.byKey(WorkOrdersScreen.detailsKey('101')));
  expect(find.byType(WorkOrderDetailScreen), findsOneWidget);
}

void main() {
  testWidgets('booking labour sends exactly one request and the cost summary updates',
      (tester) async {
    final wire = wireWith();
    await openDetail(tester, wire);

    // Nothing booked yet: the summary says so plainly.
    expect(find.byKey(WorkOrderDetailScreen.emptyLabourKey), findsOneWidget);

    await tapIn(tester, find.byKey(WorkOrderDetailScreen.bookLabourKey));
    await pickSuggestion(
      tester,
      fieldKey: LabourBookingDialog.employeeKey,
      term: 'Jane',
      suggestionKey: LabourBookingDialog.employeeSuggestionKey('20'),
    );
    await tapIn(tester, find.byKey(LabourBookingDialog.activityKey));
    await tapIn(tester, find.text('Work').last);
    await tapIn(tester, find.byKey(LabourBookingDialog.overtimeKey));
    await tapIn(tester, find.byKey(LabourBookingDialog.submitKey));

    expect(wire.labourPosts, hasLength(1));
    final (workOrderId, body) = wire.labourPosts.single;
    expect(workOrderId, '101');
    expect(body['employeeId'], '20');
    expect(body['activity'], 'work');
    expect(body['isOvertime'], true);
    // The hours are the server's business: a client-sent figure is never sent.
    expect(body.containsKey('hours'), isFalse);

    // The re-read cost summary now shows the booked activity.
    expect(find.byKey(WorkOrderDetailScreen.emptyLabourKey), findsNothing);
    expect(find.byKey(WorkOrderDetailScreen.activityKey('work')), findsOneWidget);
    expect(find.text('Work'), findsOneWidget);
  });

  testWidgets('booking a stored part sends exactly one request and decrements in the summary',
      (tester) async {
    final wire = wireWith();
    await openDetail(tester, wire);

    expect(find.byKey(WorkOrderDetailScreen.emptyPartsKey), findsOneWidget);

    await tapIn(tester, find.byKey(WorkOrderDetailScreen.bookPartKey));
    await pickSuggestion(
      tester,
      fieldKey: PartBookingDialog.partKey,
      term: 'BRG',
      suggestionKey: PartBookingDialog.partSuggestionKey('3'),
    );
    await pickSuggestion(
      tester,
      fieldKey: PartBookingDialog.storeKey,
      term: 'Main',
      suggestionKey: PartBookingDialog.storeSuggestionKey('7'),
    );
    await tester.enterText(find.byKey(PartBookingDialog.quantityKey), '3');
    await tester.enterText(find.byKey(PartBookingDialog.unitCostKey), '12.5');
    await tester.pump();
    await tapIn(tester, find.byKey(PartBookingDialog.submitKey));

    expect(wire.partBookingPosts, hasLength(1));
    final (workOrderId, body) = wire.partBookingPosts.single;
    expect(workOrderId, '101');
    expect(body['sourced'], 'stores');
    expect(body['partId'], '3');
    expect(body['storeId'], '7');
    expect(body['quantity'], 3);
    expect(body['unitCost'], 12.5);

    expect(find.byKey(WorkOrderDetailScreen.emptyPartsKey), findsNothing);
    expect(find.byKey(WorkOrderDetailScreen.partKey('900')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(WorkOrderDetailScreen.partsTotalKey),
        matching: find.text('37.5 USD'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a part bought for the job needs no store, and names no catalogue part',
      (tester) async {
    final wire = wireWith();
    await openDetail(tester, wire);

    await tapIn(tester, find.byKey(WorkOrderDetailScreen.bookPartKey));
    await tapIn(tester, find.byKey(PartBookingDialog.sourcedKey));
    await tapIn(tester, find.text('Purchased').last);
    await tester.enterText(find.byKey(PartBookingDialog.partNoKey), 'BOUGHT-1');
    await tester.enterText(find.byKey(PartBookingDialog.descriptionKey), 'Bought for this job');
    await tapIn(tester, find.byKey(PartBookingDialog.uomKey));
    await tapIn(tester, find.text('Each (EA)').last);
    await tester.enterText(find.byKey(PartBookingDialog.quantityKey), '2');
    await tester.pump();
    await tapIn(tester, find.byKey(PartBookingDialog.submitKey));

    expect(wire.partBookingPosts, hasLength(1));
    final (_, body) = wire.partBookingPosts.single;
    expect(body['sourced'], 'purchased');
    expect(body['partNo'], 'BOUGHT-1');
    expect(body['description'], 'Bought for this job');
    expect(body['uomCode'], 'EA');
    expect(body.containsKey('partId'), isFalse);
    expect(body.containsKey('storeId'), isFalse);
  });

  testWidgets('a caller with no write Grant anywhere is offered no booking button',
      (tester) async {
    final wire = FakeWire(
      role: Roles.supervisor,
      orgUnitScope: const {'everywhere': false, 'grants': <dynamic>[]},
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [orgUnitJson('10', 'Assembly')],
      },
      workOrders: {
        '1': [workOrderJson('101', 'WO-101', 'Belt is slipping')],
      },
      workOrderCosts: {'101': workOrderCostJson()},
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/work-orders',
    );
    await tapIn(tester, find.byKey(WorkOrdersScreen.detailsKey('101')));

    expect(find.byType(WorkOrderDetailScreen), findsOneWidget);
    expect(find.byKey(WorkOrderDetailScreen.bookLabourKey), findsNothing);
    expect(find.byKey(WorkOrderDetailScreen.bookPartKey), findsNothing);
  });
}
