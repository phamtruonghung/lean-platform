/// The supplier NCR surface, driven through the router against a faked wire
/// (issue #215) — the same seam `complaints_test.dart` uses: `pumpApp` with a
/// `FakeWire`, act through `WidgetTester`, and assert on what renders and on the
/// requests the Screen actually sent.
///
/// Covers the ticket's own criteria for this half: the register lists a Site's
/// supplier NCRs with the past-due ones marked, what controls each lot named and
/// the Supplier's own answer shown; the Supplier, the status and the Org Unit
/// filters are sent to the server rather than applied to the rows on screen; the
/// record form posts the Supplier, the quantity and its unit with whatever else
/// it was given; the detail shows the NCR, the control and the disposition; the
/// disposition form and the close each post what they should; and recording a
/// Non-conformance from an NCR that names no Product asks for one.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/maintenance/org_unit_chooser.dart';
import 'package:lean_platform/quality/supplier_ncr_detail_screen.dart';
import 'package:lean_platform/quality/supplier_ncr_disposition_dialog.dart';
import 'package:lean_platform/quality/supplier_ncr_form_dialog.dart';
import 'package:lean_platform/quality/supplier_ncr_nonconformance_dialog.dart';
import 'package:lean_platform/quality/supplier_ncr_supplier_filter_dialog.dart';
import 'package:lean_platform/quality/supplier_ncrs_screen.dart';

import 'harness.dart';

/// One Site, two Suppliers, one Product and a Defect code, three supplier NCRs —
/// one long past its due day, open, with the material under control and its
/// disposition recorded; one open with nothing controlling it and no Product
/// named; and one closed — and the Non-conformance the first is controlled by.
FakeWire _wire() => FakeWire(
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [orgUnitJson('10', 'Assembly')],
        '10': [orgUnitJson('11', 'Goods In', parentId: '10', unitType: 'line')],
      },
      suppliers: [
        supplierJson('50', 'SUP-1', 'Northwind Fasteners'),
        supplierJson('51', 'SUP-2', 'Baltic Steels'),
      ],
      products: [productJson('40', 'PRD-1', 'Gearbox')],
      defectCodes: [defectCodeJson('41', 'DIM-OOT', 'Out of tolerance')],
      nonconformances: {
        '1': [
          nonconformanceJson(
            '950',
            'NC-HCM-2026-00050',
            orgUnitId: '10',
            orgUnitName: 'Assembly',
            detectionPoint: 'incoming',
          ),
        ],
      },
      supplierNcrs: {
        '1': [
          supplierNcrJson(
            '80',
            'SN-2026-00001',
            orgUnitId: '10',
            incomingLotRef: 'LOT-4771',
            responseDueDate: '2020-06-01',
            isOverdue: true,
            daysOverdue: 12,
            disposition: 'scrap',
            costRecovered: 250,
            nonconformance: supplierNcrNonconformanceJson('950', 'NC-HCM-2026-00050'),
          ),
          supplierNcrJson(
            '81',
            'SN-2026-00002',
            orgUnitId: '11',
            orgUnitName: 'Goods In',
            responseDueDate: '2099-01-01',
            // Neither a Product nor a Defect code: the lot is what the
            // inspector had in front of them, and the record-NC road has to ask
            // for both.
            productId: null,
            productCode: null,
            productName: null,
            defectCodeId: null,
            defectCodeCode: null,
            defectCodeName: null,
          ),
          supplierNcrJson(
            '82',
            'SN-2026-00003',
            orgUnitId: '10',
            productId: null,
            productCode: null,
            productName: null,
            status: 'closed',
            closedAt: '2026-04-10T09:00:00Z',
          ),
        ],
      },
    );

Future<void> _pump(
  WidgetTester tester,
  FakeWire wire, {
  String location = '/supplier-ncrs',
  Size size = const Size(800, 1200),
}) async {
  // Pinned taller than the default 800x600 so a Screen's whole content is
  // built: the register's third card and the detail's lower sections are simply
  // not in the tree at 600px, and `find.byKey` fails on a row a lazy `ListView`
  // has not built yet.
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  await pumpApp(
    tester,
    gateway: FakeAuthGateway(accessToken: 'a-token'),
    client: wire.client,
    initialLocation: location,
  );
}

/// One dropdown choice, the way a person makes it: open the field, tap the
/// option. `last` because the closed field can already be showing the word the
/// menu is about to offer again.
Future<void> _choose(WidgetTester tester, Key fieldKey, String option) async {
  await tapIn(tester, find.byKey(fieldKey));
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

void main() {
  // -------------------------------------------------------------------------
  // The register
  // -------------------------------------------------------------------------

  testWidgets("the register lists a Site's supplier NCRs, marks the past-due one, names what "
      'controls each lot and shows the disposition', (tester) async {
    final wire = _wire();
    await _pump(tester, wire);

    // The address is its own Destination, so it was read the moment it opened.
    expect(wire.supplierNcrListRequests, isNotEmpty);

    expect(find.byKey(SupplierNcrsScreen.rowKey('80')), findsOneWidget);
    expect(find.byKey(SupplierNcrsScreen.rowKey('81')), findsOneWidget);
    expect(find.byKey(SupplierNcrsScreen.rowKey('82')), findsOneWidget);

    // Who it came from, what it was, and what was wrong with it.
    expect(
      find.text('Northwind Fasteners · Gearbox · Out of tolerance'),
      findsWidgets,
    );
    // An NCR that names no Product says what it does have rather than nothing.
    expect(find.text('Northwind Fasteners'), findsWidgets);

    // The marking the ticket asks for: an NCR past the day the Supplier was
    // given says so on its own face, with how late it is.
    expect(find.byKey(SupplierNcrsScreen.rowOverdueKey('80')), findsOneWidget);
    expect(
      find.text('Past the answer date of 2020-06-01 by 12 days'),
      findsOneWidget,
    );
    // A closed NCR is not marked late, whatever its due day was.
    expect(find.byKey(SupplierNcrsScreen.rowDueKey('82')), findsOneWidget);
    expect(find.text('No answer date was given'), findsWidgets);

    // The plant's own answer for the material and what was clawed back, on the
    // row.
    expect(find.text('Scrap · 250 USD'), findsOneWidget);
    // "Nothing recovered" is one half of a row's own line, so it is matched as
    // part of it rather than as a whole Text.
    expect(find.textContaining('Nothing recovered'), findsWidgets);

    // And the control, named where there is one and its absence said out loud
    // where there is not.
    expect(find.text('Controlled by NC-HCM-2026-00050'), findsOneWidget);
    expect(find.text('No Non-conformance controls this lot yet'), findsWidgets);
  });

  testWidgets('the Supplier, the status and the Org Unit filters are sent to the server, not '
      'applied to the rows on screen', (tester) async {
    final wire = _wire();
    await _pump(tester, wire);

    // The status is a closed set, chosen from a menu (ADR-0023), and the choice
    // is what the server is asked to narrow by.
    await _choose(tester, SupplierNcrsScreen.statusFilterKey, 'Closed');

    expect(wire.supplierNcrListRequests.last, {'status': 'closed'});
    expect(find.byKey(SupplierNcrsScreen.rowKey('80')), findsNothing);
    expect(find.byKey(SupplierNcrsScreen.rowKey('82')), findsOneWidget);

    // The Supplier is the ticket's own first filter, chosen from the catalogue
    // the register already read: the picker is an `AppSearchField` whose
    // suggestions come from that list, so typing issues no request.
    final readsBeforeTyping = wire.supplierNcrListRequests.length;
    await tapIn(tester, find.byKey(SupplierNcrsScreen.supplierFilterKey));
    await typeInSearchField(
      tester,
      SupplierNcrSupplierFilterDialog.supplierFieldKey,
      'Baltic',
    );
    expect(wire.supplierNcrListRequests, hasLength(readsBeforeTyping));
    await tapIn(
      tester,
      find.byKey(SupplierNcrSupplierFilterDialog.supplierSuggestionKey('51')),
    );

    expect(wire.supplierNcrListRequests.last, {'status': 'closed', 'supplierId': '51'});

    // The Org Unit narrows by *area*: the chosen unit and everything beneath it,
    // which is the server's own ltree walk.
    await tapIn(tester, find.byKey(SupplierNcrsScreen.orgUnitFilterKey));
    await tapIn(tester, find.byKey(OrgUnitChooser.chooseKey('10')));
    expect(wire.supplierNcrListRequests.last, {
      'status': 'closed',
      'supplierId': '51',
      'orgUnitId': '10',
    });

    // Clearing sends the register's own read, unfiltered.
    await tapIn(tester, find.byKey(SupplierNcrsScreen.clearFiltersKey));
    expect(wire.supplierNcrListRequests.last, isEmpty);
  });

  testWidgets('a filter that matched nothing is a filter to clear', (tester) async {
    final wire = _wire()..supplierNcrs = const {};
    await _pump(tester, wire);

    await _choose(tester, SupplierNcrsScreen.statusFilterKey, 'Issued');

    expect(find.byKey(SupplierNcrsScreen.emptyMatchedKey), findsOneWidget);
    expect(find.byKey(SupplierNcrsScreen.emptyClearFiltersKey), findsOneWidget);
  });

  testWidgets('a Site with nothing on its register says so, rather than looking like a filter that '
      'matched nothing', (tester) async {
    // Two `pumpApp` calls in one test share the app-level `AccountBloc`, so a
    // second wire in the same test would answer as the first (the harness's own
    // documented trap) — which is why this is its own test.
    final wire = _wire()..supplierNcrs = const {};
    await _pump(tester, wire);

    expect(find.byKey(SupplierNcrsScreen.emptyKey), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // Recording one
  // -------------------------------------------------------------------------

  testWidgets('the record form posts the Supplier, the lot, the quantity and its unit, and the '
      'optional fields it was given', (tester) async {
    final wire = _wire();
    await _pump(tester, wire);
    await tapIn(tester, find.byKey(SupplierNcrsScreen.recordKey));

    // Every choice is a dropdown over a catalogue the register already read, so
    // opening the form issued no request for them.
    await _choose(
      tester,
      SupplierNcrFormDialog.supplierKey,
      'Northwind Fasteners · SUP-1',
    );
    await _choose(tester, SupplierNcrFormDialog.productKey, 'Gearbox · PRD-1');
    await _choose(
      tester,
      SupplierNcrFormDialog.defectCodeKey,
      'Out of tolerance · DIM-OOT',
    );
    await tester.enterText(find.byKey(SupplierNcrFormDialog.quantityKey), '250');
    await tester.enterText(find.byKey(SupplierNcrFormDialog.lotKey), 'LOT-4771');
    await tester.enterText(find.byKey(SupplierNcrFormDialog.purchaseKey), 'PO-88213');
    await tester.enterText(
      find.byKey(SupplierNcrFormDialog.descriptionKey),
      'The thread on the M8 bolts is undersized.',
    );
    await tapIn(tester, find.byKey(OrgUnitChooser.chooseKey('10')));
    await tester.pumpAndSettle();

    // Nothing is sent until the form is complete and submitted.
    expect(wire.supplierNcrPosts, isEmpty);
    await tapIn(tester, find.byKey(SupplierNcrFormDialog.submitKey));

    expect(wire.supplierNcrPosts, hasLength(1));
    expect(wire.supplierNcrPosts.single, {
      'orgUnitId': '10',
      'supplierId': '50',
      'quantity': 250,
      // The unit is the Product's own when one is named, and a unit the plant
      // uses is never free text (ADR-0023).
      'uomCode': 'EA',
      'productId': '40',
      'defectCodeId': '41',
      'incomingLotRef': 'LOT-4771',
      'purchaseRef': 'PO-88213',
      'description': 'The thread on the M8 bolts is undersized.',
    });
  });

  testWidgets('the record form refuses to submit without a Supplier, a quantity, a unit of '
      'measure and an Org Unit', (tester) async {
    final wire = _wire();
    await _pump(tester, wire);
    await tapIn(tester, find.byKey(SupplierNcrsScreen.recordKey));

    FilledButton submit() =>
        tester.widget<FilledButton>(find.byKey(SupplierNcrFormDialog.submitKey));

    expect(submit().onPressed, isNull);

    await _choose(
      tester,
      SupplierNcrFormDialog.supplierKey,
      'Northwind Fasteners · SUP-1',
    );
    expect(submit().onPressed, isNull, reason: 'an NCR is a quantity of something');
    await tester.enterText(find.byKey(SupplierNcrFormDialog.quantityKey), '250');
    await tester.pumpAndSettle();
    expect(submit().onPressed, isNull, reason: 'a quantity is in a unit the plant uses');
    // A lot with no Product named has no unit to inherit, so the unit is chosen:
    // the catalogue is Maintenance's own list.
    await _choose(tester, SupplierNcrFormDialog.uomKey, 'Each (EA)');
    expect(submit().onPressed, isNull, reason: 'an NCR is filed at an Org Unit');
    await tapIn(tester, find.byKey(OrgUnitChooser.chooseKey('10')));
    await tester.pumpAndSettle();
    expect(submit().onPressed, isNotNull);
    expect(wire.supplierNcrPosts, isEmpty);
  });

  testWidgets("a refusal from the API is shown beside the form's own button, which stays open",
      (tester) async {
    final wire = _wire()
      ..createSupplierNcrStatus = 403
      ..createSupplierNcrMessage = "Outside the caller's granted Org Units";
    await _pump(tester, wire);
    await tapIn(tester, find.byKey(SupplierNcrsScreen.recordKey));

    await _choose(
      tester,
      SupplierNcrFormDialog.supplierKey,
      'Northwind Fasteners · SUP-1',
    );
    await tester.enterText(find.byKey(SupplierNcrFormDialog.quantityKey), '10');
    await _choose(tester, SupplierNcrFormDialog.uomKey, 'Each (EA)');
    await tapIn(tester, find.byKey(OrgUnitChooser.chooseKey('10')));
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(SupplierNcrFormDialog.submitKey));

    expect(find.byKey(SupplierNcrFormDialog.failureKey), findsOneWidget);
    expect(find.text("Outside the caller's granted Org Units"), findsOneWidget);
    expect(find.byKey(SupplierNcrFormDialog.submitKey), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // One NCR, its disposition, its closure and the road to a Non-conformance
  // -------------------------------------------------------------------------

  testWidgets('the detail shows the NCR, the record that controls the lot and the disposition, and '
      'closing it is a request of its own', (tester) async {
    final wire = _wire();
    await _pump(tester, wire, location: '/supplier-ncrs/80');

    expect(wire.supplierNcrReads, contains('/api/quality/supplier-ncrs/80'));
    expect(find.byKey(SupplierNcrDetailScreen.loadedKey), findsOneWidget);
    expect(find.text('SN-2026-00001'), findsOneWidget);
    expect(find.text('Northwind Fasteners · Gearbox'), findsOneWidget);
    // The control that exists, and the door to it.
    expect(
      find.byKey(SupplierNcrDetailScreen.controlledKey('NC-HCM-2026-00050')),
      findsOneWidget,
    );
    expect(find.text('Found at goods-in, so this NCR is where it started.'), findsOneWidget);

    // The commercial half: what was decided about the material, and what was
    // recovered for it.
    expect(find.byKey(SupplierNcrDetailScreen.dispositionKey), findsOneWidget);
    expect(find.text('Scrap'), findsOneWidget);
    expect(find.text('Recovered 250 USD.'), findsOneWidget);

    // Closing is one transition and one request, with nothing to fill in.
    await tapIn(tester, find.byKey(SupplierNcrDetailScreen.closeKey));
    expect(wire.supplierNcrCloses, ['80']);
  });

  testWidgets('the disposition form posts the disposition and the cost recovered the caller decided',
      (tester) async {
    final wire = _wire();
    await _pump(tester, wire, location: '/supplier-ncrs/81');
    await tapIn(tester, find.byKey(SupplierNcrDetailScreen.dispositionButtonKey));

    // The disposition is one of the baseline's own five, so it is chosen from a
    // menu rather than typed (ADR-0023).
    await _choose(
      tester,
      SupplierNcrDispositionDialog.dispositionKey,
      'Rework at the Supplier\'s cost',
    );
    await tester.enterText(find.byKey(SupplierNcrDispositionDialog.costKey), '1875.5');
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(SupplierNcrDispositionDialog.submitKey));

    expect(wire.supplierNcrDispositions, hasLength(1));
    expect(wire.supplierNcrDispositions.single.$1, '81');
    expect(wire.supplierNcrDispositions.single.$2, {
      'disposition': 'rework_at_cost',
      'costRecovered': 1875.5,
      'currency': 'USD',
    });
  });

  testWidgets('recording a Non-conformance from an NCR that names no Product asks for one, and '
      'posts the record it creates', (tester) async {
    final wire = _wire();
    // The NCR that names no Product — the one the Product picker exists for —
    // reached through the detail's own door, the way a person reaches it.
    await _pump(tester, wire, location: '/supplier-ncrs/81');
    await tapIn(tester, find.byKey(SupplierNcrDetailScreen.recordKey));

    // The quantity is prefilled from what arrived, and the Defect code is asked
    // for because this NCR carries none either.
    expect(
      tester
          .widget<TextField>(find.byKey(SupplierNcrNonconformanceDialog.quantityKey))
          .controller!
          .text,
      '250',
    );
    await _choose(
      tester,
      SupplierNcrNonconformanceDialog.productKey,
      'Gearbox · PRD-1',
    );
    await _choose(
      tester,
      SupplierNcrNonconformanceDialog.defectCodeKey,
      'Out of tolerance · DIM-OOT',
    );
    await tester.enterText(
      find.byKey(SupplierNcrNonconformanceDialog.containmentKey),
      'The pallet is quarantined.',
    );
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(SupplierNcrNonconformanceDialog.submitKey));

    expect(wire.supplierNcrNonconformancePosts, hasLength(1));
    expect(wire.supplierNcrNonconformancePosts.single.$1, '81');
    expect(wire.supplierNcrNonconformancePosts.single.$2, {
      'productId': '40',
      'quantity': 250,
      'defectCodeId': '41',
      'immediateContainment': 'The pallet is quarantined.',
    });
    // The wire recorded the Non-conformance at goods-in, which is what the
    // detail then shows: each record names the other.
    expect(wire.nonconformances['1']!.first['detectionPoint'], 'incoming');
  });

  testWidgets("a refusal from the disposition form is shown beside its own button, which stays "
      'open with what was decided', (tester) async {
    final wire = _wire()
      ..supplierNcrDispositionStatus = 409
      ..supplierNcrDispositionMessage = 'that supplier NCR is closed and cannot be changed';
    await _pump(tester, wire, location: '/supplier-ncrs/81');
    await tapIn(tester, find.byKey(SupplierNcrDetailScreen.dispositionButtonKey));

    await tester.enterText(find.byKey(SupplierNcrDispositionDialog.costKey), '100');
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(SupplierNcrDispositionDialog.submitKey));

    expect(find.byKey(SupplierNcrDispositionDialog.failureKey), findsOneWidget);
    // The API's own sentence reaches the Screen as well as the dialog — the
    // refusal is shown twice on purpose, so this asserts the dialog's own copy
    // separately from the count.
    expect(find.text('that supplier NCR is closed and cannot be changed'), findsWidgets);
  });
}
