/// The Non-conformance surface, driven through the router against a faked
/// wire (issue #205) — the same seam `actions_test.dart` uses: `pumpApp` with
/// a `FakeWire`, act through `WidgetTester`, and assert on what renders and on
/// the requests the Screen actually sent.
///
/// Covers the ticket's three Screens and the requests behind them: the
/// register with its filters, one record's detail with its quantity history,
/// and the record form — plus the two controls that change a record after it
/// is recorded (raising the severity, recording containment, and increasing
/// the affected quantity).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/maintenance/org_unit_chooser.dart';
import 'package:lean_platform/platform/destinations.dart';
import 'package:lean_platform/quality/nonconformance_detail_screen.dart';
import 'package:lean_platform/quality/nonconformance_form_dialog.dart';
import 'package:lean_platform/quality/nonconformance_quantity_dialog.dart';
import 'package:lean_platform/quality/nonconformance_update_dialog.dart';
import 'package:lean_platform/quality/nonconformances_screen.dart';

import 'harness.dart';

/// The wire every test in this file starts from: one Site, one area with a
/// line beneath it, one Product, two Defect codes, and two Non-conformances —
/// one open and raised once, one contained. Each test mutates only what it is
/// about.
FakeWire _wire() => FakeWire(
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [orgUnitJson('10', 'Assembly')],
        '10': [orgUnitJson('11', 'Line 1', parentId: '10', unitType: 'line')],
      },
      products: [productJson('40', 'PRD-1', 'Gearbox')],
      defectCodes: [
        defectCodeJson('41', 'DIM-OOT', 'Out of tolerance', defaultSeverity: 'major'),
        defectCodeJson('42', 'SCR', 'Scratch', defaultSeverity: 'minor'),
      ],
      nonconformances: {
        '1': [
          nonconformanceJson(
            '701',
            'NC-HCM-2026-00001',
            severity: 'major',
            quantityAffected: 20,
            productionDate: '2026-04-06',
            shiftCode: 'DAY',
            shiftName: 'Day shift',
            orgUnitId: '11',
            orgUnitName: 'Line 1',
            lotRef: 'LOT-77',
            quantityChanges: [
              quantityChangeJson('701-1', 12, 20, note: 'Sorting the bin found eight more.'),
            ],
          ),
          nonconformanceJson(
            '702',
            'NC-HCM-2026-00002',
            status: 'contained',
            severity: 'minor',
            quantityAffected: 5,
            orgUnitId: '10',
            orgUnitName: 'Assembly',
            defectCodeId: '42',
            defectCodeCode: 'SCR',
            defectCodeName: 'Scratch',
            immediateContainment: 'Quarantined the bin at the line end.',
          ),
        ],
      },
    );

Future<void> _pump(
  WidgetTester tester,
  FakeWire wire, {
  String location = '/non-conformances',
  Size size = const Size(800, 1200),
}) async {
  // Pinned taller than the default 800x600 so a Screen's whole content is
  // built: the register's second card and the detail's lower sections are
  // simply not in the tree at 600px, and `find.byKey` fails on a row a lazy
  // `ListView` has not built yet.
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

String _textOf(WidgetTester tester, Key key) {
  final widget = tester.widget(find.byKey(key));
  if (widget is Text) return widget.data!;
  // A keyed chip or row carries exactly one `Text`; a keyed fact carries its
  // label and then its value, so the value is the last one inside it.
  return tester
      .widgetList<Text>(find.descendant(of: find.byKey(key), matching: find.byType(Text)))
      .last
      .data!;
}

/// The values the menu that is currently open offers, read off the built
/// `DropdownMenuItem`s. A closed dropdown builds only the item it is showing,
/// so this is only meaningful while a menu is open — and it is the honest way
/// to assert that a control does *not* offer something, since the word could
/// also be on the Screen behind the menu.
Set<String> _openedMenuValues(WidgetTester tester) => tester
    .widgetList<DropdownMenuItem<String?>>(find.byType(DropdownMenuItem<String?>))
    .map((item) => item.value)
    .whereType<String>()
    .toSet();

/// One dropdown choice, the way a person makes it: open the field, tap the
/// option. `last` because the closed field can already be showing the word
/// the menu is about to offer again.
Future<void> _choose(WidgetTester tester, Key fieldKey, String option) async {
  await tapIn(tester, find.byKey(fieldKey));
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

void main() {
  // -------------------------------------------------------------------------
  // The register
  // -------------------------------------------------------------------------

  testWidgets('the register lists a Site\'s Non-conformances with their state, severity, count '
      'and how they were filed', (tester) async {
    final wire = _wire();
    await _pump(tester, wire);

    // The address is its own Destination, so it was read the moment it opened.
    expect(wire.nonconformanceListRequests, isNotEmpty);

    expect(find.byKey(NonconformancesScreen.rowKey('701')), findsOneWidget);
    expect(find.text('NC-HCM-2026-00001'), findsOneWidget);
    expect(find.text('Gearbox · Out of tolerance · In process'), findsOneWidget);
    expect(_textOf(tester, NonconformancesScreen.rowStatusKey('701')), 'Open');
    expect(_textOf(tester, NonconformancesScreen.rowSeverityKey('701')), 'Major');
    // The affected quantity, and that it has grown since it was written down.
    expect(_textOf(tester, NonconformancesScreen.rowQuantityKey('701')), '20 EA affected · raised 1 time');
    // The production day and shift the database filed it against (ADR-0017).
    expect(_textOf(tester, NonconformancesScreen.rowFiledKey('701')), 'Line 1 · filed against 2026-04-06 · Day shift');

    // The contained one, read the same way.
    expect(_textOf(tester, NonconformancesScreen.rowStatusKey('702')), 'Contained');
    expect(_textOf(tester, NonconformancesScreen.rowQuantityKey('702')), '5 EA affected');
  });

  testWidgets('the register offers a record form and a Site with nothing on it says so', (tester) async {
    final empty = FakeWire(
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {null: [orgUnitJson('10', 'Assembly')]},
      products: [productJson('40', 'PRD-1', 'Gearbox')],
      defectCodes: [defectCodeJson('41', 'DIM-OOT', 'Out of tolerance')],
    );
    await _pump(tester, empty);

    expect(find.byKey(NonconformancesScreen.emptyKey), findsOneWidget);
    // Offering the record form is the register's own job: the server is the
    // gate on whether recording is allowed, so the button is not hidden.
    expect(find.byKey(NonconformancesScreen.recordKey), findsOneWidget);
  });

  testWidgets('the register narrows by each filter, and sends exactly the query the address takes',
      (tester) async {
    final wire = _wire();
    await _pump(tester, wire);

    await _choose(tester, NonconformancesScreen.statusFilterKey, 'Dispositioned');
    expect(wire.nonconformanceListRequests.last, {'status': 'dispositioned'});
    // Nothing matches, and the empty state says which story this is.
    expect(find.byKey(NonconformancesScreen.emptyMatchedKey), findsOneWidget);

    await _choose(tester, NonconformancesScreen.defectCodeFilterKey, 'Scratch · SCR');
    expect(wire.nonconformanceListRequests.last, {
      'status': 'dispositioned',
      'defectCodeId': '42',
    });

    await _choose(tester, NonconformancesScreen.productFilterKey, 'Gearbox · PRD-1');
    expect(wire.nonconformanceListRequests.last, {
      'status': 'dispositioned',
      'defectCodeId': '42',
      'productId': '40',
    });

    await _choose(tester, NonconformancesScreen.severityFilterKey, 'Critical');
    expect(wire.nonconformanceListRequests.last, {
      'status': 'dispositioned',
      'defectCodeId': '42',
      'productId': '40',
      'severity': 'critical',
    });

    // A production day, chosen from a date picker rather than typed
    // (ADR-0023) — and it is the day, not an instant.
    await pickDate(tester, NonconformancesScreen.fromDateKey, DateTime(2026, 4, 6));
    expect(wire.nonconformanceListRequests.last, {
      'status': 'dispositioned',
      'defectCodeId': '42',
      'productId': '40',
      'severity': 'critical',
      'from': '2026-04-06',
    });

    // The Org Unit filter names one area, and the server includes everything
    // beneath it — the ticket's own criterion, which the address makes true.
    await tapIn(tester, find.byKey(NonconformancesScreen.orgUnitFilterKey));
    await tapIn(tester, find.byKey(OrgUnitChooser.chooseKey('10')));
    expect(wire.nonconformanceListRequests.last, {
      'status': 'dispositioned',
      'defectCodeId': '42',
      'productId': '40',
      'severity': 'critical',
      'from': '2026-04-06',
      'orgUnitId': '10',
    });
    // The button names the area rather than the id.
    expect(find.text('Assembly'), findsWidgets);

    // And clearing sends the register's own read, unfiltered.
    await tapIn(tester, find.byKey(NonconformancesScreen.clearFiltersKey));
    expect(wire.nonconformanceListRequests.last, isEmpty);
    expect(find.byKey(NonconformancesScreen.rowKey('701')), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // Recording
  // -------------------------------------------------------------------------

  testWidgets('the record form chooses every known-set value and sends the whole record', (tester) async {
    final wire = _wire();
    await _pump(tester, wire);

    await tapIn(tester, find.byKey(NonconformancesScreen.recordKey));

    // The Product is a record, chosen from the catalogue the register read —
    // typing issues no request of its own.
    final listRequestsBefore = wire.nonconformanceListRequests.length;
    await pickSuggestion(
      tester,
      fieldKey: NonconformanceFormDialog.productFieldKey(),
      term: 'Gear',
      suggestionKey: NonconformanceFormDialog.productSuggestionKey('40'),
    );
    expect(wire.nonconformanceListRequests.length, listRequestsBefore);
    expect(searchFieldText(tester, NonconformanceFormDialog.productFieldKey()), 'Gearbox (PRD-1)');

    await _choose(tester, NonconformanceFormDialog.defectCodeKey, 'Out of tolerance · DIM-OOT');
    await _choose(tester, NonconformanceFormDialog.detectionPointKey, 'Final inspection');
    await tester.enterText(find.byKey(NonconformanceFormDialog.quantityKey), '12');
    await tester.pump();
    await tester.enterText(find.byKey(NonconformanceFormDialog.lotRefKey), 'LOT-88');
    await tester.pump();
    // The Org Unit is People's own chooser — where the product was found, and
    // what decides who may act on the record.
    await tapIn(tester, find.byKey(OrgUnitChooser.chooseKey('10')));
    expect(find.byKey(NonconformanceFormDialog.chosenOrgUnitKey), findsOneWidget);

    // Nothing is sent until the form is complete and submitted.
    expect(wire.nonconformancePosts, isEmpty);
    await tapIn(tester, find.byKey(NonconformanceFormDialog.submitKey));

    expect(wire.nonconformancePosts, hasLength(1));
    expect(wire.nonconformancePosts.single, {
      'orgUnitId': '10',
      'productId': '40',
      'defectCodeId': '41',
      'detectionPoint': 'final_inspection',
      'quantity': 12,
      'lotRef': 'LOT-88',
    });

    // The form closes on success and the register re-reads, showing the row
    // the server answered with.
    expect(find.byKey(NonconformanceFormDialog.submitKey), findsNothing);
    expect(find.text('NC-HCM-2026-00900'), findsOneWidget);
  });

  testWidgets('a refused recording keeps the form open with its values and shows the refusal',
      (tester) async {
    final wire = _wire();
    wire.createNonconformanceStatus = 403;
    wire.createNonconformanceMessage = "Outside the caller's granted Org Units";
    await _pump(tester, wire);

    await tapIn(tester, find.byKey(NonconformancesScreen.recordKey));
    await pickSuggestion(
      tester,
      fieldKey: NonconformanceFormDialog.productFieldKey(),
      term: 'Gear',
      suggestionKey: NonconformanceFormDialog.productSuggestionKey('40'),
    );
    await _choose(tester, NonconformanceFormDialog.defectCodeKey, 'Out of tolerance · DIM-OOT');
    await _choose(tester, NonconformanceFormDialog.detectionPointKey, 'In process');
    await tester.enterText(find.byKey(NonconformanceFormDialog.quantityKey), '3');
    await tester.pump();
    await tapIn(tester, find.byKey(OrgUnitChooser.chooseKey('10')));
    await tapIn(tester, find.byKey(NonconformanceFormDialog.submitKey));

    expect(find.byKey(NonconformanceFormDialog.failureKey), findsOneWidget);
    expect(find.text("Outside the caller's granted Org Units"), findsOneWidget);
    // Still open, with what was typed still in it — a caller fixes the one
    // thing that was wrong rather than retyping the record.
    expect(find.byKey(NonconformanceFormDialog.submitKey), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(NonconformanceFormDialog.quantityKey)).controller!.text, '3');
  });

  testWidgets('the record form offers only severities at or above the chosen Defect code\'s own',
      (tester) async {
    final wire = _wire();
    await _pump(tester, wire);
    await tapIn(tester, find.byKey(NonconformancesScreen.recordKey));

    // Before a Defect code is chosen there is no floor to compare against, so
    // the severity cannot be chosen at all.
    expect(find.text('Choose a Defect code first'), findsOneWidget);

    // A Defect code whose default is `major`: `minor` is not on offer, and
    // `critical` is.
    await _choose(tester, NonconformanceFormDialog.defectCodeKey, 'Out of tolerance · DIM-OOT');
    await tapIn(tester, find.byKey(NonconformanceFormDialog.severityKey));
    expect(_openedMenuValues(tester), contains('critical'));
    // `minor` is below the Defect code's own default, and this slice refuses
    // it, so the form never offers it.
    expect(_openedMenuValues(tester), isNot(contains('minor')));
    await tester.tap(find.text('Critical').last);
    await tester.pumpAndSettle();

    // And a raised severity rides on the recording.
    await pickSuggestion(
      tester,
      fieldKey: NonconformanceFormDialog.productFieldKey(),
      term: 'Gear',
      suggestionKey: NonconformanceFormDialog.productSuggestionKey('40'),
    );
    await _choose(tester, NonconformanceFormDialog.detectionPointKey, 'Audit');
    await tester.enterText(find.byKey(NonconformanceFormDialog.quantityKey), '2');
    await tester.pump();
    await tapIn(tester, find.byKey(OrgUnitChooser.chooseKey('10')));
    await tapIn(tester, find.byKey(NonconformanceFormDialog.submitKey));

    expect(wire.nonconformancePosts.single['severity'], 'critical');
  });

  // -------------------------------------------------------------------------
  // The detail, and the two controls that change a record
  // -------------------------------------------------------------------------

  testWidgets('the detail reads one Non-conformance by its address and shows its quantity history',
      (tester) async {
    final wire = _wire();
    await _pump(tester, wire, location: '/non-conformances/701', size: const Size(800, 1700));

    expect(wire.nonconformanceReads.last, '/api/quality/nonconformances/701');
    expect(find.text('NC-HCM-2026-00001'), findsOneWidget);
    expect(_textOf(tester, NonconformanceDetailScreen.statusKey), 'Open');
    expect(_textOf(tester, NonconformanceDetailScreen.filedKey), '2026-04-06 · Day shift');
    expect(_textOf(tester, NonconformanceDetailScreen.quantityKey), '20 EA');
    expect(find.textContaining('Gearbox · PRD-1').first, findsOneWidget);
    expect(find.text('LOT-77'), findsOneWidget);
    expect(find.text('Quarantined the bin at the line end.'), findsNothing);

    // The history, in the order it happened: what it was, what it is, who
    // changed it and why.
    final history = _textOf(tester, NonconformanceDetailScreen.changeKey('701-1'));
    expect(history, contains('12 → 20 EA'));
    expect(history, contains('Ann Operator'));
    expect(history, contains('Sorting the bin found eight more.'));
  });

  testWidgets('a record with no changes says the quantity has never moved', (tester) async {
    final wire = _wire();
    await _pump(tester, wire, location: '/non-conformances/702', size: const Size(800, 1700));

    expect(find.byKey(NonconformanceDetailScreen.noHistoryKey), findsOneWidget);
    expect(find.byKey(NonconformanceDetailScreen.quantityHistoryKey), findsNothing);
  });

  testWidgets('the detail offers increasing the quantity, and the grown history comes back with the record',
      (tester) async {
    final wire = _wire();
    await _pump(tester, wire, location: '/non-conformances/701', size: const Size(800, 1700));

    await tapIn(tester, find.byKey(NonconformanceDetailScreen.increaseQuantityKey));
    expect(find.byKey(NonconformanceQuantityDialog.quantityKey), findsOneWidget);
    // It says what the record currently covers, and that it can only grow.
    expect(find.textContaining('20 EA'), findsWidgets);

    await tester.enterText(find.byKey(NonconformanceQuantityDialog.quantityKey), '26');
    await tester.pump();
    await tester.enterText(
      find.byKey(NonconformanceQuantityDialog.noteKey),
      'The whole shift output is suspect.',
    );
    await tester.pump();
    await tapIn(tester, find.byKey(NonconformanceQuantityDialog.submitKey));

    expect(wire.nonconformanceQuantityPosts, hasLength(1));
    expect(wire.nonconformanceQuantityPosts.single.$1, '701');
    expect(wire.nonconformanceQuantityPosts.single.$2, {
      'quantity': 26,
      'note': 'The whole shift output is suspect.',
    });

    // The dialog closed, and the record on screen is the one the server
    // answered with: the new count and both history rows.
    expect(find.byKey(NonconformanceQuantityDialog.submitKey), findsNothing);
    expect(_textOf(tester, NonconformanceDetailScreen.quantityKey), '26 EA');
    expect(_textOf(tester, NonconformanceDetailScreen.changeKey('701-2')), contains('20 → 26 EA'));
  });

  testWidgets('the increase dialog refuses a number that is not an increase before sending anything',
      (tester) async {
    final wire = _wire();
    await _pump(tester, wire, location: '/non-conformances/701', size: const Size(800, 1700));

    await tapIn(tester, find.byKey(NonconformanceDetailScreen.increaseQuantityKey));
    await tester.enterText(find.byKey(NonconformanceQuantityDialog.quantityKey), '19');
    await tester.pump();
    // The button is disabled rather than the request refused — the record's
    // rule is one-way in this slice.
    final button = tester.widget<FilledButton>(find.byKey(NonconformanceQuantityDialog.submitKey));
    expect(button.onPressed, isNull);

    await tester.enterText(find.byKey(NonconformanceQuantityDialog.quantityKey), '21');
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byKey(NonconformanceQuantityDialog.submitKey)).onPressed,
      isNotNull,
    );
    expect(wire.nonconformanceQuantityPosts, isEmpty);
  });

  testWidgets('the severity can be raised from the detail, and a lowering is never offered',
      (tester) async {
    final wire = _wire();
    // Pinned taller than the 1700 the shorter detail tests use: issue #208
    // added a section at the foot of this Screen, and a `tapIn` on a control
    // below the fold scrolls the list far enough to cull the number and the
    // chips at the top of it — where the severity is read.
    await _pump(tester, wire, location: '/non-conformances/701', size: const Size(800, 2100));

    await tapIn(tester, find.byKey(NonconformanceDetailScreen.updateKey));
    // The record is `major`; `minor` is below it and is a Quality-authority
    // decision this slice refuses, so it is not among the choices.
    await tapIn(tester, find.byKey(NonconformanceUpdateDialog.severityKey));
    expect(_openedMenuValues(tester), isNot(contains('minor')));
    expect(_openedMenuValues(tester), contains('critical'));
    await tester.tap(find.text('Critical').last);
    await tester.pumpAndSettle();

    await tapIn(tester, find.byKey(NonconformanceUpdateDialog.raiseKey));
    expect(wire.nonconformancePatches, hasLength(1));
    expect(wire.nonconformancePatches.single.$1, '701');
    expect(wire.nonconformancePatches.single.$2, {'severity': 'critical'});

    expect(find.byKey(NonconformanceUpdateDialog.raiseKey), findsNothing);
    expect(_textOf(tester, NonconformanceDetailScreen.severityKey), 'Critical severity');
  });

  testWidgets('recording immediate containment makes the record contained', (tester) async {
    final wire = _wire();
    // Pinned taller for the reason the severity test above records: the
    // section issue #208 added at the foot of this Screen is what the tapped
    // control's scroll would otherwise cull the header for.
    await _pump(tester, wire, location: '/non-conformances/701', size: const Size(800, 2100));

    expect(_textOf(tester, NonconformanceDetailScreen.statusKey), 'Open');

    await tapIn(tester, find.byKey(NonconformanceDetailScreen.updateKey));
    // An open record is contained by nothing yet, so the field starts empty.
    expect(
      tester.widget<TextField>(find.byKey(NonconformanceUpdateDialog.containmentKey)).controller!.text,
      '',
    );
    await tester.enterText(
      find.byKey(NonconformanceUpdateDialog.containmentKey),
      'Stopped the line and sorted the last hour of output.',
    );
    await tester.pump();
    await tapIn(tester, find.byKey(NonconformanceUpdateDialog.containKey));

    expect(wire.nonconformancePatches.single.$2, {
      'immediateContainment': 'Stopped the line and sorted the last hour of output.',
    });
    expect(_textOf(tester, NonconformanceDetailScreen.statusKey), 'Contained');

    // And it is on the register too, read fresh.
    await tapIn(tester, find.byKey(NonconformanceDetailScreen.backKey));
    expect(wire.nonconformanceListRequests, isNotEmpty);
    expect(_textOf(tester, NonconformancesScreen.rowStatusKey('701')), 'Contained');
  });

  testWidgets('the Non-conformances Destination is offered under the Quality group', (tester) async {
    final wire = _wire();
    await _pump(tester, wire);

    expect(
      platformDestinations.any(
        (destination) => destination.path == '/non-conformances' && destination.group == 'Quality',
      ),
      isTrue,
    );
    expect(find.text('QUALITY'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('nav-item-Non-conformances')), findsOneWidget);
  });
}
