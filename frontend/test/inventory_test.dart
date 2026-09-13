/// Inventory on the client (issue #80): the parts catalogue, a store's stock,
/// and receiving — with the wire faked at the HTTP boundary (ADR-0012). The
/// real app, the real router, the real Blocs.
///
/// What these tests claim and what they do not: that the catalogue lists,
/// that a part can be added, that a store's stock renders, and that receiving
/// sends exactly one request. They do not claim the server enforced anything —
/// the refusal to go below zero and the Grant scope refusal are proved on the
/// backend in `backend/test/integration/inventory.test.js`, and neither test
/// substitutes for the other.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/maintenance/part_form_dialog.dart';
import 'package:lean_platform/maintenance/parts_screen.dart';
import 'package:lean_platform/maintenance/receive_dialog.dart';
import 'package:lean_platform/maintenance/store_stock_screen.dart';
import 'package:lean_platform/maintenance/stores_screen.dart';
import 'package:lean_platform/platform/destinations.dart';

import 'harness.dart';

void main() {
  testWidgets('the parts catalogue lists what it is given, unit of measure included', (tester) async {
    final wire = FakeWire(
      parts: [
        partJson('7', 'BRG-6204', 'Bearing, 6204'),
        partJson('8', 'BLT-M8', 'Bolt, M8', uomCode: 'EA'),
      ],
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/parts',
    );

    expect(find.text('BRG-6204'), findsOneWidget);
    expect(find.text('Bearing, 6204'), findsOneWidget);
    expect(find.text('BLT-M8'), findsOneWidget);
    expect(find.byKey(PartsScreen.rowKey('7')), findsOneWidget);
  });

  testWidgets('adding a part sends exactly one request and the new row appears', (tester) async {
    final wire = FakeWire(parts: []);
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/parts',
    );

    await tapIn(tester, find.byKey(PartsScreen.addKey));
    await tester.enterText(find.byKey(PartFormDialog.partNoKey), 'BRG-6204');
    await tester.enterText(find.byKey(PartFormDialog.descriptionKey), 'Bearing, 6204');
    await tapIn(tester, find.byKey(PartFormDialog.uomKey));
    await tapIn(tester, find.text('Each (EA)').last);
    await tapIn(tester, find.byKey(PartFormDialog.submitKey));

    expect(wire.partPosts, hasLength(1));
    expect(wire.partPosts.single['partNo'], 'BRG-6204');
    expect(wire.partPosts.single['description'], 'Bearing, 6204');
    expect(wire.partPosts.single['uomCode'], 'EA');
    expect(find.text('BRG-6204'), findsOneWidget);
  });

  testWidgets("a store's stock renders the derived level", (tester) async {
    final wire = FakeWire(
      storeRows: {'7': storeJson('7', 'A-STORE', 'Main store', orgUnitName: 'Line 1')},
      stock: {
        '7': [
          stockLevelJson('3', 'BRG-6204', 'Bearing, 6204', 14),
          stockLevelJson('4', 'BLT-M8', 'Bolt, M8', 250),
        ],
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/stores/7',
    );

    expect(find.text('Main store'), findsOneWidget);
    expect(find.text('A-STORE · Line 1'), findsOneWidget);
    expect(find.text('BRG-6204'), findsOneWidget);
    expect(find.text('14 EA'), findsOneWidget);
    expect(find.text('250 EA'), findsOneWidget);
    expect(find.byKey(StoreStockScreen.rowKey('3')), findsOneWidget);
  });

  testWidgets('receiving sends exactly one request, and the re-read shows the new level', (tester) async {
    final wire = FakeWire(
      parts: [partJson('3', 'BRG-6204', 'Bearing, 6204')],
      storeRows: {'7': storeJson('7', 'A-STORE', 'Main store')},
      stock: {
        '7': [stockLevelJson('3', 'BRG-6204', 'Bearing, 6204', 14)],
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/stores/7',
    );

    await tapIn(tester, find.byKey(StoreStockScreen.receiveKey));
    await tapIn(tester, find.byKey(ReceiveDialog.partKey));
    await tapIn(tester, find.text('BRG-6204 · Bearing, 6204').last);
    await tester.enterText(find.byKey(ReceiveDialog.quantityKey), '5');
    await tapIn(tester, find.byKey(ReceiveDialog.submitKey));

    expect(wire.receiptPosts, hasLength(1));
    expect(wire.receiptPosts.single.$1, '7');
    expect(wire.receiptPosts.single.$2['partId'], '3');
    expect(wire.receiptPosts.single.$2['quantity'], 5);
    expect(find.text('19 EA'), findsOneWidget);
  });

  testWidgets('the stores list renders and a row opens its stock', (tester) async {
    final wire = FakeWire(
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      stores: {
        '1': [storeJson('7', 'A-STORE', 'Main store', orgUnitName: 'Line 1')],
      },
      storeRows: {'7': storeJson('7', 'A-STORE', 'Main store', orgUnitName: 'Line 1')},
      stock: {
        '7': [stockLevelJson('3', 'BRG-6204', 'Bearing, 6204', 14)],
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/stores',
    );

    expect(find.text('Main store'), findsOneWidget);
    expect(find.text('A-STORE · Line 1'), findsOneWidget);
    expect(find.byKey(StoresScreen.rowKey('7')), findsOneWidget);

    await tapIn(tester, find.byKey(StoresScreen.rowKey('7')));
    expect(find.text('14 EA'), findsOneWidget);
  });

  testWidgets('a caller whose role does not earn the Module is locked out by address', (tester) async {
    final wire = FakeWire(role: Roles.operator, stores: {'1': []});
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/parts',
    );

    expect(find.text('Not available to you'), findsOneWidget);
  });
}
