/// The Customer list (issue #214), driven through the router against a faked
/// wire — the same seam `nonconformances_test.dart` uses: `pumpApp` with a
/// `FakeWire`, act through `WidgetTester`, and assert on what renders and on
/// the requests the Screen actually sent.
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
import 'package:lean_platform/quality/customer_form_dialog.dart';
import 'package:lean_platform/quality/customers_screen.dart';

import 'harness.dart';

/// One Site and two Customers — one still traded with, one retired — so the
/// list has a row to narrow away and an inactive row to reach.
FakeWire _wire({String role = Roles.admin}) => FakeWire(
      role: role,
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [orgUnitJson('10', 'Assembly')],
      },
      customers: [
        customerJson('60', 'CUST-1', 'Acme Bearings', contactEmail: 'quality@acme.example.com'),
        customerJson('61', 'CUST-2', 'Zenith Castings', isActive: false),
      ],
    );

Future<void> _pump(
  WidgetTester tester,
  FakeWire wire, {
  String location = '/customers',
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
  testWidgets('the list shows every Customer with its code and contact address, and the filter '
      'box narrows it without asking the server again', (tester) async {
    final wire = _wire();
    await _pump(tester, wire);

    // The address is its own Destination, so it was read the moment it opened —
    // and for the retired rows too, so one can be reached and reactivated.
    expect(wire.customerListRequests, isNotEmpty);
    expect(wire.customerListRequests.last, {'includeInactive': 'true'});

    expect(find.byKey(CustomersScreen.rowKey('60')), findsOneWidget);
    expect(find.byKey(CustomersScreen.rowKey('61')), findsOneWidget);
    expect(
      find.text('Acme Bearings · CUST-1 · quality@acme.example.com'),
      findsOneWidget,
    );
    // A Customer the plant no longer trades with says so, rather than being
    // hidden or silently listed as current.
    expect(find.byKey(CustomersScreen.inactiveChipKey('61')), findsOneWidget);

    // The filter box narrows the rows the Screen already holds and issues no
    // request at all (issue #187's finding control): what it read once, it
    // read once.
    final reads = wire.customerListRequests.length;
    await tester.enterText(find.byKey(CustomersScreen.filterFieldKey), 'Acme');
    await tester.pumpAndSettle();

    expect(wire.customerListRequests, hasLength(reads));
    expect(find.byKey(CustomersScreen.rowKey('60')), findsOneWidget);
    expect(find.byKey(CustomersScreen.rowKey('61')), findsNothing);

    // A term matching nothing is a different fact from an empty catalogue, and
    // the count line says how much of the list is on screen.
    await tester.enterText(find.byKey(CustomersScreen.filterFieldKey), 'nothing here');
    await tester.pumpAndSettle();
    expect(find.byKey(CustomersScreen.noMatchKey), findsOneWidget);

    // The clear affordance brings the whole list back.
    await tapIn(tester, find.byKey(CustomersScreen.filterClearKey));
    expect(find.byKey(CustomersScreen.rowKey('61')), findsOneWidget);
  });

  testWidgets('an administrator defines a Customer and corrects one, and each request carries '
      'exactly what the form decided', (tester) async {
    final wire = _wire();
    await _pump(tester, wire);

    // Defining one: the code, the name and an optional contact address.
    await tapIn(tester, find.byKey(CustomersScreen.addKey));
    await tester.enterText(find.byKey(CustomerFormDialog.codeKey), 'CUST-3');
    await tester.enterText(find.byKey(CustomerFormDialog.nameKey), 'Delta Fasteners');
    await tester.enterText(find.byKey(CustomerFormDialog.emailKey), 'ap@delta.example.com');
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(CustomerFormDialog.submitKey));

    expect(wire.customerPosts, hasLength(1));
    expect(wire.customerPosts.single, {
      'code': 'CUST-3',
      'name': 'Delta Fasteners',
      'contactEmail': 'ap@delta.example.com',
    });

    // Correcting one: only the field that actually changed is sent, which is
    // `updateCustomer`'s own `hasOwnProperty` contract at the other end.
    await tapIn(tester, find.byKey(CustomersScreen.correctKey('60')));
    // The code is what a complaint quotes, so it is not a field a correction
    // may rewrite — the field is there and shut.
    expect(
      tester.widget<TextField>(find.byKey(CustomerFormDialog.codeKey)).enabled,
      isFalse,
    );
    await tester.enterText(find.byKey(CustomerFormDialog.nameKey), 'Acme Bearings Ltd');
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(CustomerFormDialog.submitKey));

    expect(wire.customerPatches, hasLength(1));
    expect(wire.customerPatches.single.$1, '60');
    expect(wire.customerPatches.single.$2, {'name': 'Acme Bearings Ltd'});
  });

  testWidgets('defining and correcting a Customer are not offered to anyone but an administrator',
      (tester) async {
    final wire = _wire(role: Roles.engineer);
    await _pump(tester, wire);

    // The list itself is open to any approved Account — the ticket's own
    // criterion — and the write affordances inside it are not.
    expect(find.byKey(CustomersScreen.rowKey('60')), findsOneWidget);
    expect(find.byKey(CustomersScreen.addKey), findsNothing);
    expect(find.byKey(CustomersScreen.correctKey('60')), findsNothing);
    expect(wire.customerPosts, isEmpty);
  });

  testWidgets("a code already taken is refused with the API's own sentence, and the form stays "
      'open with what was typed', (tester) async {
    final wire = _wire()
      ..createCustomerStatus = 409
      ..createCustomerMessage = 'a Customer with this code already exists';
    await _pump(tester, wire);

    await tapIn(tester, find.byKey(CustomersScreen.addKey));
    await tester.enterText(find.byKey(CustomerFormDialog.codeKey), 'CUST-1');
    await tester.enterText(find.byKey(CustomerFormDialog.nameKey), 'A second Acme');
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(CustomerFormDialog.submitKey));

    expect(find.byKey(CustomerFormDialog.failureKey), findsOneWidget);
    expect(find.text('a Customer with this code already exists'), findsOneWidget);
    // Still open, with the code still in it: the caller fixes the one thing
    // that was wrong rather than retyping the Customer.
    expect(
      tester.widget<TextField>(find.byKey(CustomerFormDialog.codeKey)).controller!.text,
      'CUST-1',
    );
  });
}
