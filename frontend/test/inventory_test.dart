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

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/maintenance/part_form_dialog.dart';
import 'package:lean_platform/maintenance/parts_screen.dart';
import 'package:lean_platform/maintenance/receive_dialog.dart';
import 'package:lean_platform/maintenance/store_stock_screen.dart';
import 'package:lean_platform/maintenance/stores_screen.dart';
import 'package:lean_platform/platform/destinations.dart';
import 'package:lean_platform/widgets/app_filter_field.dart';
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

  // Issue #191: a register is narrowed by text, not by scrolling. Each Screen
  // owns its own term and narrows the rows it has already read — the wire's
  // own record is what proves no request was sent for the term.
  // The parts catalogue is the ticket's own stock question: "is PART-4471 in
  // stock" is four characters rather than a scroll.
  testWidgets('the parts catalogue is narrowed by a typed term, and typing costs no request', (tester) async {
    // The filter box this register now carries (issue #191) sits above the
    // rows, so a two-row register no longer fits flutter_test's default
    // 800x600 surface: the rows below the fold are `ListView` children that
    // have not been built yet, and `find.byKey` would find nothing. The taller
    // window is the fixture's, not the Screen's — the same pin this repo's
    // lazy-list tests already use.
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1000, 1200);
    addTearDown(tester.view.reset);

    final wire = FakeWire(parts: [
      partJson('7', 'BRG-6204', 'Bearing, 6204'),
      partJson('8', 'BLT-M8', 'Bolt, M8'),
    ]);
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/parts',
    );

    // Nothing narrowed yet: every row, and no count line to read.
    expect(find.byKey(PartsScreen.rowKey('7')), findsOneWidget);
    expect(find.byKey(PartsScreen.rowKey('8')), findsOneWidget);
    expect(find.byKey(PartsScreen.filterCountKey), findsNothing);

    final requestsBefore = wire.requests.length;
    await tester.enterText(find.byKey(PartsScreen.filterFieldKey), 'bearing');
    await tester.pumpAndSettle();

    // (a) the rows narrow, (c) the count line says how many of how many.
    expect(find.byKey(PartsScreen.rowKey('7')), findsOneWidget);
    expect(find.byKey(PartsScreen.rowKey('8')), findsNothing);
    expect(find.byKey(PartsScreen.filterCountKey), findsOneWidget);
    expect(find.text(AppFilterField.countLabel(1, 2)), findsOneWidget);

    // (b) narrowing a register the client already holds costs no request.
    expect(wire.requests.length, requestsBefore,
        reason: 'typing must not read anything over the wire');

    // (d) one clear affordance, and every row is back.
    await tester.tap(find.byKey(PartsScreen.filterClearKey));
    await tester.pumpAndSettle();

    expect(find.byKey(PartsScreen.rowKey('7')), findsOneWidget);
    expect(find.byKey(PartsScreen.rowKey('8')), findsOneWidget);
    expect(find.byKey(PartsScreen.filterCountKey), findsNothing);
    expect(wire.requests.length, requestsBefore);
  });

  // The negative the ticket's rule is made of: a term matching nothing is not
  // an empty catalogue. The catalogue is read and has rows; the term excludes
  // them all, and the reader must be able to tell those two apart.
  testWidgets('a term matching nothing reads as "nothing matched", never as an empty catalogue',
      (tester) async {
    // The filter box this register now carries (issue #191) sits above the
    // rows, so a two-row register no longer fits flutter_test's default
    // 800x600 surface: the rows below the fold are `ListView` children that
    // have not been built yet, and `find.byKey` would find nothing. The taller
    // window is the fixture's, not the Screen's — the same pin this repo's
    // lazy-list tests already use.
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1000, 1200);
    addTearDown(tester.view.reset);

    final wire = FakeWire(parts: [
      partJson('7', 'BRG-6204', 'Bearing, 6204'),
      partJson('8', 'BLT-M8', 'Bolt, M8'),
    ]);
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/parts',
    );

    await tester.enterText(find.byKey(PartsScreen.filterFieldKey), 'zz-nothing');
    await tester.pumpAndSettle();

    expect(find.byKey(PartsScreen.noMatchKey), findsOneWidget);
    expect(find.byKey(PartsScreen.rowKey('7')), findsNothing);
    expect(find.byKey(PartsScreen.rowKey('8')), findsNothing);
    // "Nothing matched" is not "there is nothing here".
    expect(find.byKey(PartsScreen.emptyKey), findsNothing);
    // And the box is still there to be cleared, which is the only way back.
    expect(find.byKey(PartsScreen.filterClearKey), findsOneWidget);
  });

  // Issue #191: a register is narrowed by text, not by scrolling. Each Screen
  // owns its own term and narrows the rows it has already read — the wire's
  // own record is what proves no request was sent for the term.
  testWidgets('the stores list is narrowed by a typed term, and typing costs no request', (tester) async {
    // The filter box this register now carries (issue #191) sits above the
    // rows, so a two-row register no longer fits flutter_test's default
    // 800x600 surface: the rows below the fold are `ListView` children that
    // have not been built yet, and `find.byKey` would find nothing. The taller
    // window is the fixture's, not the Screen's — the same pin this repo's
    // lazy-list tests already use.
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1000, 1200);
    addTearDown(tester.view.reset);

    final wire = FakeWire(
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      stores: {
        '1': [
          storeJson('7', 'A-STORE', 'Main store', orgUnitName: 'Line 1'),
          storeJson('8', 'B-STORE', 'Line 2 store', orgUnitName: 'Line 2'),
        ],
      },
    );
    await pumpApp(
      tester,
      gateway: FakeAuthGateway(accessToken: 'a-token'),
      client: wire.client,
      initialLocation: '/stores',
    );

    // Nothing narrowed yet: every row, and no count line to read.
    expect(find.byKey(StoresScreen.rowKey('8')), findsOneWidget);
    expect(find.byKey(StoresScreen.rowKey('7')), findsOneWidget);
    expect(find.byKey(StoresScreen.filterCountKey), findsNothing);

    final requestsBefore = wire.requests.length;
    await tester.enterText(find.byKey(StoresScreen.filterFieldKey), 'line 2');
    await tester.pumpAndSettle();

    // (a) the rows narrow, (c) the count line says how many of how many.
    expect(find.byKey(StoresScreen.rowKey('8')), findsOneWidget);
    expect(find.byKey(StoresScreen.rowKey('7')), findsNothing);
    expect(find.byKey(StoresScreen.filterCountKey), findsOneWidget);
    expect(find.text(AppFilterField.countLabel(1, 2)), findsOneWidget);

    // (b) narrowing a register the client already holds costs no request.
    expect(wire.requests.length, requestsBefore,
        reason: 'typing must not read anything over the wire');

    // (d) one clear affordance, and every row is back.
    await tester.tap(find.byKey(StoresScreen.filterClearKey));
    await tester.pumpAndSettle();

    expect(find.byKey(StoresScreen.rowKey('8')), findsOneWidget);
    expect(find.byKey(StoresScreen.rowKey('7')), findsOneWidget);
    expect(find.byKey(StoresScreen.filterCountKey), findsNothing);
    expect(wire.requests.length, requestsBefore);
  });

  // Issue #191: a register is narrowed by text, not by scrolling. Each Screen
  // owns its own term and narrows the rows it has already read — the wire's
  // own record is what proves no request was sent for the term.
  testWidgets("one store's stock is narrowed by a typed term, and typing costs no request",
      (tester) async {
    // The filter box this register now carries (issue #191) sits above the
    // rows, so a two-row register no longer fits flutter_test's default
    // 800x600 surface: the rows below the fold are `ListView` children that
    // have not been built yet, and `find.byKey` would find nothing. The taller
    // window is the fixture's, not the Screen's — the same pin this repo's
    // lazy-list tests already use.
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1000, 1200);
    addTearDown(tester.view.reset);

    final wire = FakeWire(
      storeRows: {'7': storeJson('7', 'A-STORE', 'Main store')},
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

    // Nothing narrowed yet: every row, and no count line to read.
    expect(find.byKey(StoreStockScreen.rowKey('4')), findsOneWidget);
    expect(find.byKey(StoreStockScreen.rowKey('3')), findsOneWidget);
    expect(find.byKey(StoreStockScreen.filterCountKey), findsNothing);

    final requestsBefore = wire.requests.length;
    await tester.enterText(find.byKey(StoreStockScreen.filterFieldKey), 'bolt');
    await tester.pumpAndSettle();

    // (a) the rows narrow, (c) the count line says how many of how many.
    expect(find.byKey(StoreStockScreen.rowKey('4')), findsOneWidget);
    expect(find.byKey(StoreStockScreen.rowKey('3')), findsNothing);
    expect(find.byKey(StoreStockScreen.filterCountKey), findsOneWidget);
    expect(find.text(AppFilterField.countLabel(1, 2)), findsOneWidget);

    // (b) narrowing a register the client already holds costs no request.
    expect(wire.requests.length, requestsBefore,
        reason: 'typing must not read anything over the wire');

    // (d) one clear affordance, and every row is back.
    await tester.tap(find.byKey(StoreStockScreen.filterClearKey));
    await tester.pumpAndSettle();

    expect(find.byKey(StoreStockScreen.rowKey('4')), findsOneWidget);
    expect(find.byKey(StoreStockScreen.rowKey('3')), findsOneWidget);
    expect(find.byKey(StoreStockScreen.filterCountKey), findsNothing);
    expect(wire.requests.length, requestsBefore);
  });
}
