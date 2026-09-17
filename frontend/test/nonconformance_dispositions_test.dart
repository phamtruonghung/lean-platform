/// Dispositions, Concessions and the corrections to a Non-conformance, driven
/// through the router against a faked wire (issue #206) — the same seam
/// `nonconformances_test.dart` uses: `pumpApp` with a `FakeWire`, act through
/// `WidgetTester`, and assert on what renders and on the requests the Screen
/// actually sent.
///
/// The two things this file is here to prove, beyond each dialog doing its own
/// job: the four decisions a Grant's Quality authority gates — the Concession,
/// the lowered severity, the reopen and the cancel — are *not offered* to a
/// caller who does not hold it, and **no request is sent** when they are
/// missing; and each of them, and the Disposition, has an address of its own
/// that a refresh lands on (ADR-0021).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:lean_platform/quality/nonconformance_cancel_dialog.dart';
import 'package:lean_platform/quality/nonconformance_concession_dialog.dart';
import 'package:lean_platform/quality/nonconformance_detail_screen.dart';
import 'package:lean_platform/quality/nonconformance_disposition_dialog.dart';
import 'package:lean_platform/quality/nonconformance_lower_severity_dialog.dart';
import 'package:lean_platform/quality/nonconformance_reopen_dialog.dart';

import 'harness.dart';

/// The wire every test in this file starts from: one Site, one area, one
/// Product and one Defect code, and three Non-conformances — one with nothing
/// decided about it, one partly dispositioned, and one closed with a
/// Concession and a correction on it.
///
/// [quality] is what the caller's own Grant carries: `qualityAuthority` is the
/// flag ADR-0035 puts beside the level, and every test that asserts an action
/// is or is not offered turns on it. When it is false the caller still holds a
/// write Grant reaching the record's Org Unit, which is what recording and the
/// three ordinary Dispositions need.
FakeWire _wire({bool quality = false}) => FakeWire(
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {null: [orgUnitJson('11', 'Line 1')]},
      products: [productJson('40', 'PRD-1', 'Gearbox')],
      defectCodes: [defectCodeJson('41', 'DIM-OOT', 'Out of tolerance', defaultSeverity: 'major')],
      orgUnitScope: {
        'everywhere': false,
        'grants': [scopeGrantJson('11', canWrite: true, qualityAuthority: quality)],
      },
      nonconformances: {
        '1': [
          nonconformanceJson('701', 'NC-HCM-2026-00001', severity: 'major', quantityAffected: 20,
              orgUnitId: '11', orgUnitName: 'Line 1'),
          nonconformanceJson(
            '703',
            'NC-HCM-2026-00003',
            status: 'dispositioned',
            severity: 'major',
            quantityAffected: 20,
            quantityDispositioned: 12,
            orgUnitId: '11',
            orgUnitName: 'Line 1',
            dispositions: [
              dispositionJson('703-d1', quantity: 12, note: 'Crushed and weighed in.'),
            ],
          ),
          nonconformanceJson(
            '702',
            'NC-HCM-2026-00002',
            status: 'closed',
            severity: 'minor',
            quantityAffected: 5,
            quantityDispositioned: 5,
            closedAt: '2026-04-07T09:30:00.000Z',
            orgUnitId: '11',
            orgUnitName: 'Line 1',
            dispositions: [
              dispositionJson(
                '702-d1',
                dispositionType: 'use_as_is',
                quantity: 5,
                reference: 'DEV-2026-0014',
                note: 'Customer engineering accepts the marks.',
                decidedByAccountName: 'Inspector Quai',
              ),
            ],
            corrections: [
              correctionJson(
                '702-c1',
                kind: 'severity_lowered',
                previousSeverity: 'major',
                newSeverity: 'minor',
                note: 'Only the label was misprinted.',
                correctedByAccountName: 'Inspector Quai',
              ),
            ],
          ),
        ],
      },
    );

Future<void> _pump(
  WidgetTester tester,
  FakeWire wire, {
  String location = '/non-conformances/701',
}) async {
  // Pinned taller than the default 800x600: the detail's lower sections are
  // simply not in the tree at 600px, and `find.byKey` fails on a row a lazy
  // `ListView` has not built yet.
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(800, 2200);
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
  return tester
      .widgetList<Text>(find.descendant(of: find.byKey(key), matching: find.byType(Text)))
      .last
      .data!;
}

/// Every line inside a keyed row, joined — a Disposition or a correction is
/// two `Text`s (what it is, and who decided it when), so asserting on one of
/// them would miss half the row.
String _rowText(WidgetTester tester, Key key) => tester
    .widgetList<Text>(find.descendant(of: find.byKey(key), matching: find.byType(Text)))
    .map((text) => text.data ?? '')
    .join(' · ');

/// Navigate to an address the way a refresh does — `go`, not a tap. The
/// addressed dialogs are reachable only through the Screen's own controls when
/// the caller may not use them, so the only honest way to prove what an
/// address does on its own is to go to it.
Future<void> _go(WidgetTester tester, String address) async {
  final context = tester.element(find.byKey(NonconformanceDetailScreen.backKey));
  GoRouter.of(context).go(address);
  await tester.pumpAndSettle();
}

/// One dropdown choice, the way a person makes it: open the field, tap the
/// option.
Future<void> _choose(WidgetTester tester, Key fieldKey, String option) async {
  await tapIn(tester, find.byKey(fieldKey));
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

void main() {
  // -------------------------------------------------------------------------
  // What the detail shows
  // -------------------------------------------------------------------------

  testWidgets('the detail shows the Dispositions and the corrections a record carries', (tester) async {
    final wire = _wire(quality: true);
    await _pump(tester, wire, location: '/non-conformances/702');

    // The Concession, with the granting Account, the reference and the note.
    final disposition = _rowText(tester, NonconformanceDetailScreen.dispositionRowKey('702-d1'));
    expect(disposition, contains('Concession · 5 EA'));
    expect(disposition, contains('Inspector Quai'));
    expect(disposition, contains('DEV-2026-0014'));

    // What the record was, what it became, and why.
    final correction = _rowText(tester, NonconformanceDetailScreen.correctionRowKey('702-c1'));
    expect(correction, contains('Severity lowered from Major to Minor'));
    expect(correction, contains('Inspector Quai'));
    expect(correction, contains('Only the label was misprinted.'));

    // The record is closed, and the Screen says when it finished with itself.
    expect(_textOf(tester, NonconformanceDetailScreen.statusKey), 'Closed');
    expect(find.byKey(NonconformanceDetailScreen.closedKey), findsOneWidget);
  });

  testWidgets('a record nothing has been decided about says so, in both places', (tester) async {
    final wire = _wire(quality: true);
    await _pump(tester, wire);

    expect(find.byKey(NonconformanceDetailScreen.noDispositionsKey), findsOneWidget);
    expect(find.byKey(NonconformanceDetailScreen.dispositionsKey), findsNothing);
    expect(find.byKey(NonconformanceDetailScreen.noCorrectionsKey), findsOneWidget);
    expect(find.byKey(NonconformanceDetailScreen.correctionsKey), findsNothing);
  });

  // -------------------------------------------------------------------------
  // Recording a Disposition
  // -------------------------------------------------------------------------

  testWidgets('a scrap Disposition is recorded by address, and the record comes back dispositioned',
      (tester) async {
    final wire = _wire();
    await _pump(tester, wire);

    await tapIn(tester, find.byKey(NonconformanceDetailScreen.dispositionKey));
    expect(find.byKey(NonconformanceDispositionDialog.kindKey), findsOneWidget);
    // The count still undecided is on the form, because that is the ceiling.
    expect(find.textContaining('20 EA still undecided'), findsOneWidget);

    await tester.enterText(find.byKey(NonconformanceDispositionDialog.quantityKey), '5');
    await tester.pump();
    await tester.enterText(
      find.byKey(NonconformanceDispositionDialog.noteKey),
      'Crushed and weighed in at the bin.',
    );
    await tester.pump();
    await tapIn(tester, find.byKey(NonconformanceDispositionDialog.submitKey));

    expect(wire.nonconformanceDispositionPosts, hasLength(1));
    expect(wire.nonconformanceDispositionPosts.single.$1, '701');
    expect(wire.nonconformanceDispositionPosts.single.$2, {
      'dispositionType': 'scrap',
      'quantity': 5,
      'note': 'Crushed and weighed in at the bin.',
    });

    // The dialog closed, and the record on screen is the one the server
    // answered with: the Disposition and the state that follows from it.
    expect(find.byKey(NonconformanceDispositionDialog.submitKey), findsNothing);
    expect(_textOf(tester, NonconformanceDetailScreen.statusKey), 'Dispositioned');
    final row = _rowText(tester, NonconformanceDetailScreen.dispositionRowKey('701-d1'));
    expect(row, contains('Scrap · 5 EA'));
    expect(row, contains('Ann Operator'));
  });

  testWidgets('rework asks for its minutes and sends them, and a scrap is not asked for any',
      (tester) async {
    final wire = _wire();
    await _pump(tester, wire);

    await tapIn(tester, find.byKey(NonconformanceDetailScreen.dispositionKey));
    // A scrap carries no minutes, so the field is not on the form at all.
    expect(find.byKey(NonconformanceDispositionDialog.minutesKey), findsNothing);

    await _choose(tester, NonconformanceDispositionDialog.kindKey, 'Rework');
    expect(find.byKey(NonconformanceDispositionDialog.minutesKey), findsOneWidget);
    await tester.enterText(find.byKey(NonconformanceDispositionDialog.quantityKey), '4');
    await tester.pump();
    await tester.enterText(find.byKey(NonconformanceDispositionDialog.minutesKey), '45');
    await tester.pump();
    await tapIn(tester, find.byKey(NonconformanceDispositionDialog.submitKey));

    expect(wire.nonconformanceDispositionPosts.single.$2, {
      'dispositionType': 'rework',
      'quantity': 4,
      'reworkMinutes': 45,
    });
  });

  testWidgets('a Disposition larger than what is still undecided cannot be sent', (tester) async {
    final wire = _wire();
    // Twelve of the twenty on 703 have a Disposition, so eight are left.
    await _pump(tester, wire, location: '/non-conformances/703');

    await tapIn(tester, find.byKey(NonconformanceDetailScreen.dispositionKey));
    expect(find.textContaining('8 EA still undecided'), findsOneWidget);

    await tester.enterText(find.byKey(NonconformanceDispositionDialog.quantityKey), '9');
    await tester.pump();
    // The button is disabled rather than the request refused with a 409.
    expect(
      tester.widget<FilledButton>(find.byKey(NonconformanceDispositionDialog.submitKey)).onPressed,
      isNull,
    );

    await tester.enterText(find.byKey(NonconformanceDispositionDialog.quantityKey), '8');
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byKey(NonconformanceDispositionDialog.submitKey)).onPressed,
      isNotNull,
    );
    expect(wire.nonconformanceDispositionPosts, isEmpty);
  });

  testWidgets('a refused Disposition keeps the dialog open with its values and shows the refusal',
      (tester) async {
    final wire = _wire();
    wire.recordNonconformanceActStatus = 409;
    wire.recordNonconformanceActMessage =
        'that is more than the 8 EA still undecided on this Non-conformance';
    await _pump(tester, wire, location: '/non-conformances/703');

    await tapIn(tester, find.byKey(NonconformanceDetailScreen.dispositionKey));
    await tester.enterText(find.byKey(NonconformanceDispositionDialog.quantityKey), '8');
    await tester.pump();
    await tapIn(tester, find.byKey(NonconformanceDispositionDialog.submitKey));

    expect(find.byKey(NonconformanceDispositionDialog.failureKey), findsOneWidget);
    // The refusal is on the dialog and on the Screen behind it, both reading
    // the Bloc's own `mutationFailure`.
    expect(
      find.text('that is more than the 8 EA still undecided on this Non-conformance'),
      findsWidgets,
    );
    // Still open, with what was typed still in it.
    expect(
      tester.widget<TextField>(find.byKey(NonconformanceDispositionDialog.quantityKey)).controller!.text,
      '8',
    );
  });

  // -------------------------------------------------------------------------
  // The four decisions Quality authority gates
  // -------------------------------------------------------------------------

  testWidgets('without Quality authority the four decisions are not offered, and nothing is sent',
      (tester) async {
    final wire = _wire();
    await _pump(tester, wire, location: '/non-conformances/703');

    // A write Grant reaching the Org Unit is enough for the Disposition...
    expect(find.byKey(NonconformanceDetailScreen.dispositionKey), findsOneWidget);
    // ...and is not enough for any of the four decisions (ADR-0035 keeps the
    // two flags independent).
    expect(find.byKey(NonconformanceDetailScreen.concessionKey), findsNothing);
    expect(find.byKey(NonconformanceDetailScreen.lowerSeverityKey), findsNothing);
    expect(find.byKey(NonconformanceDetailScreen.cancelKey), findsNothing);
    expect(find.byKey(NonconformanceDetailScreen.reopenKey), findsNothing);

    // And nothing was asked of the API for any of them.
    expect(wire.nonconformanceConcessionPosts, isEmpty);
    expect(wire.nonconformanceLowerSeverityPosts, isEmpty);
    expect(wire.nonconformanceReopenPosts, isEmpty);
    expect(wire.nonconformanceCancelPosts, isEmpty);
  });

  testWidgets('the reopen is not offered without Quality authority on a record that is closed',
      (tester) async {
    final wire = _wire();
    await _pump(tester, wire, location: '/non-conformances/702');
    expect(find.byKey(NonconformanceDetailScreen.reopenKey), findsNothing);
    expect(wire.nonconformanceReopenPosts, isEmpty);
  });

  testWidgets('a Concession reached by its own address without quality authority says why, and sends nothing',
      (tester) async {
    final wire = _wire();
    // A refresh lands on the address, so the address itself has to refuse —
    // the Screen's own omission is not the only guard (ADR-0021).
    await _pump(tester, wire, location: '/non-conformances/703');
    await _go(tester, '/non-conformances/703/concession');

    expect(find.byKey(NonconformanceConcessionDialog.refusedKey), findsOneWidget);
    expect(find.textContaining('needs Quality authority'), findsOneWidget);
    expect(find.byKey(NonconformanceConcessionDialog.submitKey), findsNothing);
    expect(wire.nonconformanceConcessionPosts, isEmpty);
  });

  testWidgets('a holder of Quality authority is offered the Concession, the lowering and the cancel',
      (tester) async {
    final wire = _wire(quality: true);
    await _pump(tester, wire, location: '/non-conformances/703');

    expect(find.byKey(NonconformanceDetailScreen.concessionKey), findsOneWidget);
    expect(find.byKey(NonconformanceDetailScreen.lowerSeverityKey), findsOneWidget);
    expect(find.byKey(NonconformanceDetailScreen.cancelKey), findsOneWidget);
    // Not on a record that is not closed, and not on one that already finished
    // with itself.
    expect(find.byKey(NonconformanceDetailScreen.reopenKey), findsNothing);
  });

  testWidgets('a closed Non-conformance offers the reopen to a holder of Quality authority, and no cancel',
      (tester) async {
    final wire = _wire(quality: true);
    await _pump(tester, wire, location: '/non-conformances/702');

    expect(find.byKey(NonconformanceDetailScreen.reopenKey), findsOneWidget);
    expect(find.byKey(NonconformanceDetailScreen.cancelKey), findsNothing);
  });

  testWidgets('granting a Concession sends its quantity, its reference and its note', (tester) async {
    final wire = _wire(quality: true);
    await _pump(tester, wire, location: '/non-conformances/701');

    await tapIn(tester, find.byKey(NonconformanceDetailScreen.concessionKey));
    expect(find.byKey(NonconformanceConcessionDialog.quantityKey), findsOneWidget);

    await tester.enterText(find.byKey(NonconformanceConcessionDialog.quantityKey), '6');
    await tester.pump();
    await tester.enterText(
      find.byKey(NonconformanceConcessionDialog.referenceKey),
      'DEV-2026-0020',
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(NonconformanceConcessionDialog.noteKey),
      'Customer engineering accepts the marks.',
    );
    await tester.pump();
    // Nothing is sent until all three are there.
    expect(wire.nonconformanceConcessionPosts, isEmpty);
    await tapIn(tester, find.byKey(NonconformanceConcessionDialog.submitKey));

    expect(wire.nonconformanceConcessionPosts.single.$1, '701');
    expect(wire.nonconformanceConcessionPosts.single.$2, {
      'quantity': 6,
      'reference': 'DEV-2026-0020',
      'note': 'Customer engineering accepts the marks.',
    });

    expect(find.byKey(NonconformanceConcessionDialog.submitKey), findsNothing);
    final row = _rowText(tester, NonconformanceDetailScreen.dispositionRowKey('701-d1'));
    expect(row, contains('Concession · 6 EA'));
    expect(row, contains('DEV-2026-0020'));
  });

  testWidgets('lowering the severity sends it with its note, and the record reads the lowering back',
      (tester) async {
    final wire = _wire(quality: true);
    await _pump(tester, wire, location: '/non-conformances/703');

    await tapIn(tester, find.byKey(NonconformanceDetailScreen.lowerSeverityKey));
    // Only the severities below the one on the record are offered, and the
    // Defect code's own default is not a floor: the API allows a lower one.
    await _choose(tester, NonconformanceLowerSeverityDialog.severityKey, 'Minor');
    await tester.enterText(
      find.byKey(NonconformanceLowerSeverityDialog.noteKey),
      'Only the label was misprinted.',
    );
    await tester.pump();
    await tapIn(tester, find.byKey(NonconformanceLowerSeverityDialog.submitKey));

    expect(wire.nonconformanceLowerSeverityPosts.single.$1, '703');
    expect(wire.nonconformanceLowerSeverityPosts.single.$2, {
      'severity': 'minor',
      'note': 'Only the label was misprinted.',
    });

    expect(_textOf(tester, NonconformanceDetailScreen.severityKey), 'Minor severity');
    final correction = _rowText(tester, NonconformanceDetailScreen.correctionRowKey('703-c1'));
    expect(correction, contains('Severity lowered from Major to Minor'));
    expect(correction, contains('Only the label was misprinted.'));
  });

  testWidgets('a closed Non-conformance is reopened from its own dialog with a note', (tester) async {
    final wire = _wire(quality: true);
    await _pump(tester, wire, location: '/non-conformances/702');

    await tapIn(tester, find.byKey(NonconformanceDetailScreen.reopenKey));
    await tester.enterText(
      find.byKey(NonconformanceReopenDialog.noteKey),
      'Two more pallets of the same lot turned up.',
    );
    await tester.pump();
    await tapIn(tester, find.byKey(NonconformanceReopenDialog.submitKey));

    expect(wire.nonconformanceReopenPosts.single.$1, '702');
    expect(wire.nonconformanceReopenPosts.single.$2, {
      'note': 'Two more pallets of the same lot turned up.',
    });

    expect(_textOf(tester, NonconformanceDetailScreen.statusKey), 'Dispositioned');
    final correction = _rowText(tester, NonconformanceDetailScreen.correctionRowKey('702-c2'));
    expect(correction, contains('Reopened from Closed'));
    expect(correction, contains('Two more pallets of the same lot turned up.'));
  });

  testWidgets('a Non-conformance is cancelled from its own dialog with a note, and accepts nothing after',
      (tester) async {
    final wire = _wire(quality: true);
    await _pump(tester, wire, location: '/non-conformances/703');

    await tapIn(tester, find.byKey(NonconformanceDetailScreen.cancelKey));
    await tester.enterText(
      find.byKey(NonconformanceCancelDialog.noteKey),
      'Recorded against the wrong Product.',
    );
    await tester.pump();
    await tapIn(tester, find.byKey(NonconformanceCancelDialog.submitKey));

    expect(wire.nonconformanceCancelPosts.single.$1, '703');
    expect(wire.nonconformanceCancelPosts.single.$2, {
      'note': 'Recorded against the wrong Product.',
    });

    expect(_textOf(tester, NonconformanceDetailScreen.statusKey), 'Cancelled');
    // A cancelled record is offered neither a Disposition nor a Concession,
    // because it accepts neither.
    expect(find.byKey(NonconformanceDetailScreen.dispositionKey), findsNothing);
    expect(find.byKey(NonconformanceDetailScreen.concessionKey), findsNothing);
  });
}
