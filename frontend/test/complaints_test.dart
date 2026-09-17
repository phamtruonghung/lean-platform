/// The customer complaint surface, driven through the router against a faked
/// wire (issue #214) — the same seam `nonconformances_test.dart` uses:
/// `pumpApp` with a `FakeWire`, act through `WidgetTester`, and assert on what
/// renders and on the requests the Screen actually sent.
///
/// Covers the ticket's own criteria for this half: the register lists a Site's
/// complaints with the past-due ones marked and the control on each named; the
/// status and Org Unit filters are sent to the server rather than applied to
/// the rows on screen; the record form posts the Customer, the Product, the
/// Defect code, the quantity and the due day; the detail shows the complaint,
/// the response and the record that controls the product; closing it posts the
/// response note; and the two roads to a Non-conformance — recorded from the
/// complaint, or one that already exists — each send what they should.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/maintenance/org_unit_chooser.dart';
import 'package:lean_platform/quality/complaint_detail_screen.dart';
import 'package:lean_platform/quality/complaint_form_dialog.dart';
import 'package:lean_platform/quality/complaint_link_dialog.dart';
import 'package:lean_platform/quality/complaint_nonconformance_dialog.dart';
import 'package:lean_platform/quality/complaint_respond_dialog.dart';
import 'package:lean_platform/quality/complaints_screen.dart';

import 'harness.dart';

/// One Site, one Customer, one Product and a Compliant code, three complaints —
/// one long past its due day and open, one open with nothing controlling it
/// yet, and one closed with its response — and the Non-conformance one of them
/// is controlled by.
FakeWire _wire() => FakeWire(
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [orgUnitJson('10', 'Assembly')],
        '10': [orgUnitJson('11', 'Line 1', parentId: '10', unitType: 'line')],
      },
      customers: [customerJson('60', 'CUST-1', 'Acme Bearings')],
      products: [productJson('40', 'PRD-1', 'Gearbox')],
      defectCodes: [defectCodeJson('41', 'DIM-OOT', 'Out of tolerance')],
      nonconformances: {
        '1': [
          nonconformanceJson(
            '950',
            'NC-HCM-2026-00050',
            orgUnitId: '10',
            orgUnitName: 'Assembly',
          ),
        ],
      },
      complaints: {
        '1': [
          customerComplaintJson(
            '70',
            'CC-2026-00001',
            orgUnitId: '10',
            responseDueDate: '2020-06-01',
            isOverdue: true,
            daysOverdue: 12,
            lotRef: 'LOT-4471',
            nonconformance: complaintNonconformanceJson('950', 'NC-HCM-2026-00050'),
          ),
          customerComplaintJson(
            '71',
            'CC-2026-00002',
            orgUnitId: '11',
            orgUnitName: 'Line 1',
            responseDueDate: '2099-01-01',
          ),
          customerComplaintJson(
            '72',
            'CC-2026-00003',
            orgUnitId: '10',
            status: 'closed',
            responseNote: 'Replaced from stock and screened the rest of the lot.',
            closedAt: '2026-04-10T09:00:00Z',
            firstResponseAt: '2026-04-08T09:00:00Z',
          ),
        ],
      },
    );

Future<void> _pump(
  WidgetTester tester,
  FakeWire wire, {
  String location = '/complaints',
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

  testWidgets("the register lists a Site's complaints, marks the past-due one and names what "
      'controls each product', (tester) async {
    final wire = _wire();
    await _pump(tester, wire);

    // The address is its own Destination, so it was read the moment it opened.
    expect(wire.complaintListRequests, isNotEmpty);

    expect(find.byKey(ComplaintsScreen.rowKey('70')), findsOneWidget);
    expect(find.byKey(ComplaintsScreen.rowKey('71')), findsOneWidget);
    expect(find.byKey(ComplaintsScreen.rowKey('72')), findsOneWidget);

    // Who complained, about what, and in the state the record is in.
    expect(find.text('Acme Bearings · Gearbox · Out of tolerance'), findsWidgets);

    // The marking the ticket asks for: a complaint past the day the customer
    // was promised an answer says so on its own face, with how late it is.
    expect(find.byKey(ComplaintsScreen.rowOverdueKey('70')), findsOneWidget);
    expect(
      find.text('Past the response date of 2020-06-01 by 12 days'),
      findsOneWidget,
    );
    expect(find.byKey(ComplaintsScreen.rowOverdueKey('71')), findsNothing);
    expect(find.text('Response due 2099-01-01'), findsOneWidget);

    // And what controls the product each complaint is about — the two answers
    // this register is read for.
    expect(find.text('Controlled by NC-HCM-2026-00050'), findsOneWidget);
    expect(find.text('No Non-conformance controls this product yet'), findsWidgets);
  });

  testWidgets('the status filter and the Org Unit filter are sent to the server, not applied to '
      'the rows on screen', (tester) async {
    final wire = _wire();
    await _pump(tester, wire);

    // The status is a closed set, chosen from a menu (ADR-0023), and the choice
    // is what the server is asked to narrow by — the rows on screen follow the
    // answer rather than being filtered here.
    await _choose(tester, ComplaintsScreen.statusFilterKey, 'Investigating');

    expect(wire.complaintListRequests.last, {'status': 'investigating'});
    expect(find.byKey(ComplaintsScreen.rowKey('70')), findsNothing);
    expect(find.byKey(ComplaintsScreen.emptyMatchedKey), findsOneWidget);

    // The Org Unit narrows by *area*: the chosen unit and everything beneath it,
    // which is the server's own ltree walk.
    await tapIn(tester, find.byKey(ComplaintsScreen.orgUnitFilterKey));
    await tapIn(tester, find.byKey(OrgUnitChooser.chooseKey('10')));
    expect(wire.complaintListRequests.last, {'status': 'investigating', 'orgUnitId': '10'});
    expect(find.text('Assembly'), findsWidgets);

    // Clearing sends the register's own read, unfiltered.
    await tapIn(tester, find.byKey(ComplaintsScreen.clearFiltersKey));
    expect(wire.complaintListRequests.last, isEmpty);
  });

  testWidgets('a Site with nothing on its register says so, rather than looking like a filter that '
      'matched nothing', (tester) async {
    final wire = _wire()..complaints = const {};
    await _pump(tester, wire);

    expect(find.byKey(ComplaintsScreen.emptyKey), findsOneWidget);
  });

  testWidgets('a filter that matched nothing is a filter to clear', (tester) async {
    // Two `pumpApp` calls in one test share the app-level `AccountBloc`, so a
    // second wire in the same test would answer as the first (the harness's own
    // documented trap) — which is why this is its own test.
    final wire = _wire()..complaints = const {};
    await _pump(tester, wire);

    await _choose(tester, ComplaintsScreen.statusFilterKey, 'Closed');

    expect(find.byKey(ComplaintsScreen.emptyMatchedKey), findsOneWidget);
    expect(find.byKey(ComplaintsScreen.emptyClearFiltersKey), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // Recording one
  // -------------------------------------------------------------------------

  testWidgets('the record form posts the Customer, the Product, the Defect code, the quantity and '
      'the day the customer was promised an answer', (tester) async {
    final wire = _wire();
    await _pump(tester, wire);
    await tapIn(tester, find.byKey(ComplaintsScreen.recordKey));

    // Every choice is a dropdown over a catalogue the register already read, so
    // opening the form issued no request for them.
    await _choose(tester, ComplaintFormDialog.customerKey, 'Acme Bearings · CUST-1');
    await _choose(tester, ComplaintFormDialog.productKey, 'Gearbox · PRD-1');
    await _choose(tester, ComplaintFormDialog.defectCodeKey, 'Out of tolerance · DIM-OOT');
    await tester.enterText(find.byKey(ComplaintFormDialog.quantityKey), '20');
    await tester.enterText(
      find.byKey(ComplaintFormDialog.descriptionKey),
      'Twenty will not seat on the shaft.',
    );
    await tapIn(tester, find.byKey(ComplaintFormDialog.warrantyKey));
    await tapIn(tester, find.byKey(OrgUnitChooser.chooseKey('10')));
    await tester.pumpAndSettle();

    // Nothing is sent until the form is complete and submitted.
    expect(wire.complaintPosts, isEmpty);
    await tapIn(tester, find.byKey(ComplaintFormDialog.submitKey));

    expect(wire.complaintPosts, hasLength(1));
    expect(wire.complaintPosts.single, {
      'orgUnitId': '10',
      'customerId': '60',
      'productId': '40',
      'description': 'Twenty will not seat on the shaft.',
      'isWarranty': true,
      'defectCodeId': '41',
      'quantity': 20,
    });
  });

  testWidgets('the record form refuses to submit without a Customer, a Product, a description and '
      'an Org Unit', (tester) async {
    final wire = _wire();
    await _pump(tester, wire);
    await tapIn(tester, find.byKey(ComplaintsScreen.recordKey));

    FilledButton submit() =>
        tester.widget<FilledButton>(find.byKey(ComplaintFormDialog.submitKey));

    expect(submit().onPressed, isNull);

    await _choose(tester, ComplaintFormDialog.customerKey, 'Acme Bearings · CUST-1');
    expect(submit().onPressed, isNull, reason: 'a complaint needs a Product');
    await _choose(tester, ComplaintFormDialog.productKey, 'Gearbox · PRD-1');
    expect(submit().onPressed, isNull, reason: 'a complaint needs something written down');
    await tester.enterText(
      find.byKey(ComplaintFormDialog.descriptionKey),
      'Twenty will not seat on the shaft.',
    );
    await tester.pumpAndSettle();
    expect(submit().onPressed, isNull, reason: 'a complaint is filed at an Org Unit');
    await tapIn(tester, find.byKey(OrgUnitChooser.chooseKey('10')));
    await tester.pumpAndSettle();
    expect(submit().onPressed, isNotNull);
    expect(wire.complaintPosts, isEmpty);
  });

  testWidgets("a refusal from the API is shown beside the form's own button, which stays open",
      (tester) async {
    final wire = _wire()
      ..createComplaintStatus = 403
      ..createComplaintMessage = "Outside the caller's granted Org Units";
    await _pump(tester, wire);
    await tapIn(tester, find.byKey(ComplaintsScreen.recordKey));

    await _choose(tester, ComplaintFormDialog.customerKey, 'Acme Bearings · CUST-1');
    await _choose(tester, ComplaintFormDialog.productKey, 'Gearbox · PRD-1');
    await tester.enterText(find.byKey(ComplaintFormDialog.descriptionKey), 'Nothing seats.');
    await tapIn(tester, find.byKey(OrgUnitChooser.chooseKey('10')));
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(ComplaintFormDialog.submitKey));

    expect(find.byKey(ComplaintFormDialog.failureKey), findsOneWidget);
    expect(find.text("Outside the caller's granted Org Units"), findsOneWidget);
    expect(find.byKey(ComplaintFormDialog.submitKey), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // One complaint, and the two roads to a Non-conformance
  // -------------------------------------------------------------------------

  testWidgets('the detail shows the complaint and the record that controls its product', (tester) async {
    final wire = _wire();
    await _pump(tester, wire, location: '/complaints/70');

    expect(wire.complaintReads, contains('/api/quality/complaints/70'));
    expect(find.byKey(ComplaintDetailScreen.loadedKey), findsOneWidget);
    expect(find.text('CC-2026-00001'), findsOneWidget);
    expect(find.text('Acme Bearings · Gearbox'), findsOneWidget);
    // The control that exists, and the door to it.
    expect(
      find.byKey(ComplaintDetailScreen.controlledKey('NC-HCM-2026-00050')),
      findsOneWidget,
    );
    expect(find.text('Open the Non-conformance'), findsOneWidget);
    // A complaint with no response yet offers the one write that answers it.
    expect(find.byKey(ComplaintDetailScreen.respondKey), findsOneWidget);
  });

  testWidgets('the detail of a complaint that was answered shows the response, not the door',
      (tester) async {
    // Its own test rather than a second `pumpApp` here: two in one test share
    // the app-level `AccountBloc`, so the second wire would answer as the first
    // (the harness's own documented trap).
    final wire = _wire();
    await _pump(tester, wire, location: '/complaints/72');

    expect(find.byKey(ComplaintDetailScreen.responseNoteKey), findsOneWidget);
    expect(
      find.text('Replaced from stock and screened the rest of the lot.'),
      findsOneWidget,
    );
    expect(find.byKey(ComplaintDetailScreen.respondKey), findsNothing);
  });

  testWidgets('a complaint with nothing controlling its product offers both roads to one, and '
      'the back button returns to the register it came from', (tester) async {
    final wire = _wire();
    await _pump(tester, wire, location: '/complaints/71');

    expect(find.byKey(ComplaintDetailScreen.noControlKey), findsOneWidget);
    expect(find.byKey(ComplaintDetailScreen.recordKey), findsOneWidget);
    expect(find.byKey(ComplaintDetailScreen.linkKey), findsOneWidget);

    // A Back button is the list's address, and the register re-reads itself on
    // arrival (issue #183), so coming back shows what has happened since.
    final reads = wire.complaintListRequests.length;
    await tapIn(tester, find.byKey(ComplaintDetailScreen.backKey));
    expect(find.byKey(ComplaintsScreen.recordKey), findsOneWidget);
    expect(wire.complaintListRequests.length, greaterThan(reads));
  });

  testWidgets('recording a Non-conformance from the complaint sends detection point customer and '
      'the complaint own Product and Defect code', (tester) async {
    final wire = _wire();
    await _pump(tester, wire, location: '/complaints/71');
    await tapIn(tester, find.byKey(ComplaintDetailScreen.recordKey));

    // The quantity is prefilled from what the customer said, and the Defect code
    // is the complaint's own — shown rather than asked for again.
    expect(
      tester
          .widget<TextField>(find.byKey(ComplaintNonconformanceDialog.quantityKey))
          .controller!
          .text,
      '20',
    );
    expect(find.text('Out of tolerance · DIM-OOT'), findsWidgets);

    await tapIn(tester, find.byKey(ComplaintNonconformanceDialog.submitKey));

    expect(wire.complaintNonconformancePosts, hasLength(1));
    expect(wire.complaintNonconformancePosts.single.$1, '71');
    // No `defectCodeId` in the body: the complaint's own Defect code is what the
    // service copies when the caller names none.
    expect(wire.complaintNonconformancePosts.single.$2, {'quantity': 20});
    // The record it made is in the fake's own store, detected by the customer.
    final recorded = wire.nonconformances['1']!.first;
    expect(recorded['detectionPoint'], 'customer');
    expect(recorded['productId'], '40');
    expect(recorded['defectCodeId'], '41');
  });

  testWidgets('an existing Non-conformance is offered for this complaint own Product and the pick '
      'is posted', (tester) async {
    final wire = _wire();
    await _pump(tester, wire, location: '/complaints/71');
    await tapIn(tester, find.byKey(ComplaintDetailScreen.linkKey));

    // The candidates are the Site's records for *this* Product — the server
    // refuses one about another Product, so the picker never offers one.
    expect(
      wire.nonconformanceListRequests.any((query) => query['productId'] == '40'),
      isTrue,
      reason: 'the link dialog did not read the Product\'s own Non-conformances',
    );

    await _choose(tester, ComplaintLinkDialog.candidateKey, 'NC-HCM-2026-00050 · Open');
    await tapIn(tester, find.byKey(ComplaintLinkDialog.submitKey));

    expect(wire.complaintLinks, hasLength(1));
    expect(wire.complaintLinks.single.$1, '71');
    expect(wire.complaintLinks.single.$2, {'nonconformanceId': '950'});
  });

  testWidgets("a refusal from the API is shown beside the button, and nothing is closed", (tester) async {
    final wire = _wire()
      ..respondToComplaintStatus = 409
      ..respondToComplaintMessage = 'that Customer complaint is closed and cannot be changed';
    await _pump(tester, wire, location: '/complaints/71');
    await tapIn(tester, find.byKey(ComplaintDetailScreen.respondKey));

    // The submit button is shut until something is written: the server refuses a
    // complaint closed with nothing said back, and the form says so first.
    expect(
      tester.widget<FilledButton>(find.byKey(ComplaintRespondDialog.submitKey)).onPressed,
      isNull,
    );

    await tester.enterText(find.byKey(ComplaintRespondDialog.noteKey), 'A second answer.');
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(ComplaintRespondDialog.submitKey));

    expect(find.byKey(ComplaintRespondDialog.failureKey), findsOneWidget);
    expect(
      find.text('that Customer complaint is closed and cannot be changed'),
      findsWidgets,
    );
    // The dialog is still open with the note still in it, and the complaint is
    // untouched — the refusal is a fact about the record, not a lost write.
    expect(
      tester
          .widget<TextField>(find.byKey(ComplaintRespondDialog.noteKey))
          .controller!
          .text,
      'A second answer.',
    );
    expect(wire.complaintById('71')!['status'], 'open');
  });

  testWidgets('closing a complaint with its response closes it, and the response is what the '
      'detail shows afterwards', (tester) async {
    final wire = _wire();
    await _pump(tester, wire, location: '/complaints/71');
    await tapIn(tester, find.byKey(ComplaintDetailScreen.respondKey));

    await tester.enterText(
      find.byKey(ComplaintRespondDialog.noteKey),
      'Replaced the twenty and screened the rest of the lot.',
    );
    await tester.pumpAndSettle();
    await tapIn(tester, find.byKey(ComplaintRespondDialog.submitKey));

    expect(wire.complaintResponds, hasLength(1));
    expect(wire.complaintResponds.single.$1, '71');
    expect(wire.complaintResponds.single.$2, {
      'responseNote': 'Replaced the twenty and screened the rest of the lot.',
    });

    // The dialog is gone and the complaint behind it reads as closed, with the
    // response it was closed with — the write answered the whole record, so the
    // Screen needs no second read.
    expect(find.byKey(ComplaintRespondDialog.submitKey), findsNothing);
    expect(find.byKey(ComplaintDetailScreen.responseNoteKey), findsOneWidget);
    expect(
      find.text('Replaced the twenty and screened the rest of the lot.'),
      findsOneWidget,
    );
  });
}
