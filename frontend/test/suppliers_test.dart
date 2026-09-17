/// The Supplier list (issue #215), driven through the router against a faked
/// wire — the same seam `customers_test.dart` uses: `pumpApp` with a `FakeWire`,
/// act through `WidgetTester`, and assert on what renders and on the requests
/// the Screen actually sent.
///
/// Covers the ticket's own criteria for this half: the list is readable by any
/// approved Account, the filter box narrows the rows the Screen holds without
/// asking the server anything, the write affordances are the administrator's
/// alone, a duplicate code is refused with the API's own sentence, and a
/// correction sends only the field that changed.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/platform/destinations.dart';
import 'package:lean_platform/quality/supplier_form_dialog.dart';
import 'package:lean_platform/quality/suppliers_screen.dart';

import 'harness.dart';

/// One Site and two Suppliers — one still bought from, one retired — so the
/// list has a row to narrow away and an inactive row to reach.
FakeWire _wire({String role = Roles.admin}) => FakeWire(
      role: role,
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [orgUnitJson('10', 'Assembly')],
      },
      suppliers: [
        supplierJson(
          '50',
          'SUP-1',
          'Northwind Fasteners',
          contactEmail: 'quality@northwind.example.com',
        ),
        supplierJson('51', 'SUP-2', 'Zenith Castings', isActive: false),
      ],
    );

Future<void> _pump(
  WidgetTester tester,
  FakeWire wire, {
  String location = '/suppliers',
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(800, 1200);
  addTearDown(tester.view.reset);

  await pumpApp(
    tester,
    gateway: FakeAuthGateway(accessToken: 'a-token'),
    client: wire.client,
    initialLocation: location,
  );
}

void main() {
  testWidgets('the list shows every Supplier with its code and contact address, and the filter '
      'box narrows it without asking the server again', (tester) async {
    final wire = _wire();
    await _pump(tester, wire);

    // The address is its own Destination, so it was read the moment it opened —
    // and for the retired rows too, so one can be reached and reactivated.
    expect(wire.supplierListRequests, isNotEmpty);
    expect(wire.supplierListRequests.last, {'includeInactive': 'true'});

    expect(find.byKey(SuppliersScreen.rowKey('50')), findsOneWidget);
    expect(find.byKey(SuppliersScreen.rowKey('51')), findsOneWidget);
    expect(
      find.text('Northwind Fasteners · SUP-1 · quality@northwind.example.com'),
      findsOneWidget,
    );
    // A Supplier the plant no longer buys from says so, rather than being hidden
    // or silently listed as current.
    expect(find.byKey(SuppliersScreen.inactiveChipKey('51')), findsOneWidget);

    // The filter box narrows the rows the Screen already holds and issues no
    // request at all (issue #187's finding control): what it read once, it read
    // once.
    final reads = wire.supplierListRequests.length;
    await tester.enterText(find.byKey(SuppliersScreen.filterFieldKey), 'Northwind');
    await tester.pumpAndSettle();

    expect(wire.supplierListRequests, hasLength(reads));
    expect(find.byKey(SuppliersScreen.rowKey('50')), findsOneWidget);
    expect(find.byKey(SuppliersScreen.rowKey('51')), findsNothing);

    // A term matching nothing is a different fact from an empty catalogue, and
    // the count line says how much of the list is on screen.
    await tester.enterText(find.byKey(SuppliersScreen.filterFieldKey), 'nothing here');
    await tester.pumpAndSettle();
    expect(find.byKey(SuppliersScreen.noMatchKey), findsOneWidget);

    // The clear affordance brings the whole list back.
    await tapIn(tester, find.byKey(SuppliersScreen.filterClearKey));
    expect(find.byKey(SuppliersScreen.rowKey('51')), findsOneWidget);
  });

  testWidgets('an administrator defines a Supplier and corrects one, and each request carries '
      'exactly what the form decided', (tester) async {
    final wire = _wire();
    await _pump(tester, wire);

    // Defining one: the code, the name and an optional contact address.
    await tapIn(tester, find.byKey(SuppliersScreen.addKey));
    await tester.enterText(find.byKey(SupplierFormDialog.codeKey), 'SUP-3');
    await tester.enterText(find.byKey(SupplierFormDialog.nameKey), 'Baltic Steels');
    await tester.enterText(
      find.byKey(SupplierFormDialog.emailKey),
      'claims@baltic.example.com',
    );
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(SupplierFormDialog.submitKey));

    expect(wire.supplierPosts, hasLength(1));
    expect(wire.supplierPosts.single, {
      'code': 'SUP-3',
      'name': 'Baltic Steels',
      'contactEmail': 'claims@baltic.example.com',
    });

    // Correcting one: only the field that actually changed is sent, which is
    // `updateSupplier`'s own `hasOwnProperty` contract at the other end.
    await tapIn(tester, find.byKey(SuppliersScreen.correctKey('50')));
    // The code is what a supplier NCR quotes, so it is not a field a correction
    // may rewrite — the field is there and shut.
    expect(
      tester.widget<TextField>(find.byKey(SupplierFormDialog.codeKey)).enabled,
      isFalse,
    );
    await tester.enterText(find.byKey(SupplierFormDialog.nameKey), 'Northwind Fasteners Ltd');
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(SupplierFormDialog.submitKey));

    expect(wire.supplierPatches, hasLength(1));
    expect(wire.supplierPatches.single.$1, '50');
    expect(wire.supplierPatches.single.$2, {'name': 'Northwind Fasteners Ltd'});
  });

  testWidgets('defining and correcting a Supplier are not offered to anyone but an administrator',
      (tester) async {
    final wire = _wire(role: Roles.engineer);
    await _pump(tester, wire);

    // The list itself is open to any approved Account — the ticket's own
    // criterion — and the write affordances inside it are not.
    expect(find.byKey(SuppliersScreen.rowKey('50')), findsOneWidget);
    expect(find.byKey(SuppliersScreen.addKey), findsNothing);
    expect(find.byKey(SuppliersScreen.correctKey('50')), findsNothing);
    expect(wire.supplierPosts, isEmpty);
  });

  testWidgets("a code already taken is refused with the API's own sentence, and the form stays "
      'open with what was typed', (tester) async {
    final wire = _wire()
      ..createSupplierStatus = 409
      ..createSupplierMessage = 'a Supplier with this code already exists';
    await _pump(tester, wire);

    await tapIn(tester, find.byKey(SuppliersScreen.addKey));
    await tester.enterText(find.byKey(SupplierFormDialog.codeKey), 'SUP-1');
    await tester.enterText(find.byKey(SupplierFormDialog.nameKey), 'A second Northwind');
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(SupplierFormDialog.submitKey));

    expect(find.byKey(SupplierFormDialog.failureKey), findsOneWidget);
    expect(find.text('a Supplier with this code already exists'), findsOneWidget);
    // Still open, with the code still in it: the caller fixes the one thing that
    // was wrong rather than retyping the Supplier.
    expect(
      tester.widget<TextField>(find.byKey(SupplierFormDialog.codeKey)).controller!.text,
      'SUP-1',
    );
  });
}
