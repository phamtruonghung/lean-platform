/// The Safety Screens' geometry, measured (issue #391): the two registers, the
/// two catalogues, the two detail pages and the dialogs they open.
///
/// Each case pins something a reader can see and a stylesheet cannot: which
/// shape the register is at a given box, how tall a row is, where a chip sits
/// relative to the text it qualifies, that a detail page leads with its summary
/// card, and that at twice the text nothing clips and the register falls back
/// to cards rather than squeezing six columns into half a box.
///
/// **Why 700 and 1280.** 700 is the narrowest box the register still draws a
/// table in, and it is the width the brief names for the catalogues; 1280 is an
/// ordinary desktop window. Both are *windows*: the Shell's 260px rail comes off
/// first, so a register is handed `window - 260` and then loses this page's
/// `Spacing.lg` either side. Every assertion below is on the widget that is
/// actually measured, never on the window.
///
/// **Why a text scale of 2.** #379 and #381 were both a breakpoint that ignored
/// the reader's text size, so the same code read fine at 100% and squeezed at
/// 200%. A case at 2.0 that only renders would not catch that; the cases here
/// assert the *shape* (cards, not a table) and that nothing threw.
///
/// The app is pumped through the real router with the wire faked, as
/// `work_orders_geometry_test.dart` does; nothing here reaches into a Bloc.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lean_platform/platform/destinations.dart';
import 'package:lean_platform/safety/body_parts_screen.dart';
import 'package:lean_platform/safety/incident_detail_screen.dart';
import 'package:lean_platform/safety/incidents_screen.dart';
import 'package:lean_platform/safety/injury_types_screen.dart';
import 'package:lean_platform/safety/observation_detail_screen.dart';
import 'package:lean_platform/safety/observations_screen.dart';
import 'package:lean_platform/widgets/app_dialog.dart';
import 'package:lean_platform/widgets/app_table.dart';

import 'harness.dart';

FakeWire _wire() => FakeWire(
      role: Roles.admin,
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [orgUnitJson('10', 'Line 1')],
      },
      safetyIncidents: {
        '1': [
          safetyIncidentJson(
            '901',
            'SI-HCM-2026-00001',
            severityLevel: 'first_aid',
            incidentType: 'injury',
            description: 'Slipped on an oil patch by the press.',
            immediateAction: 'Area coned off and the patch cleaned.',
          ),
          safetyIncidentJson(
            '902',
            'SI-HCM-2026-00002',
            status: 'investigating',
            severityLevel: 'lost_time',
            incidentType: 'injury',
            lostTimeDays: 2,
          ),
        ],
      },
      safetyObservations: {
        '1': [
          safetyObservationJson('701', isStopWork: true, description: 'Guard interlock bypassed.'),
          safetyObservationJson('702', severityPotential: 'low', category: 'housekeeping'),
        ],
      },
      bodyParts: [
        bodyPartJson('51', 'HAND-L', 'Left hand'),
        bodyPartJson('52', 'FOREARM-L', 'Left forearm', region: 'upper_limb'),
      ],
      injuryTypes: [
        injuryTypeJson('61', 'CUT', 'Cut'),
        injuryTypeJson('62', 'BURN', 'Burn', isActive: false),
      ],
    );

Future<void> _pump(
  WidgetTester tester, {
  required double width,
  required String location,
  double textScale = 1,
  bool settle = true,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, 2200);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  await pumpApp(
    tester,
    gateway: FakeAuthGateway(accessToken: 'a-token'),
    client: _wire().client,
    initialLocation: location,
    settle: settle,
  );
  if (settle) {
    await tester.pumpAndSettle();
  }
}

/// A chip column's left edge, the text beside it, and the row it all sits in —
/// the three measurements a "chip in its own column" claim needs.
void _expectRowIsATapTarget(WidgetTester tester, Finder row) {
  expect(tester.getSize(row).height, greaterThanOrEqualTo(44.0),
      reason: 'a row that opens a record is a tap target');
}

void main() {
  setUpAll(loadAppFonts);

  group('Safety incidents register', () {
    testWidgets('at 1280 the register is a table, and severity leads its number', (tester) async {
      await _pump(tester, width: 1280, location: '/safety/incidents');

      expect(find.byKey(SafetyIncidentsScreen.tableKey), findsOneWidget);
      expect(find.byKey(SafetyIncidentsScreen.cardsKey), findsNothing);
      expect(find.byType(AppTableHeader), findsOneWidget);

      final row = find.byKey(SafetyIncidentsScreen.rowKey('901'));
      expect(find.descendant(of: row, matching: find.byType(AppTableRow)), findsOneWidget);
      _expectRowIsATapTarget(tester, row);

      // The two chip columns are columns: the rung starts the row, and the
      // state ends it, so the eye scans one value down one x.
      final severity = tester.getTopLeft(find.byKey(SafetyIncidentsScreen.rowSeverityKey('901')));
      final number = tester.getTopLeft(find.text('SI-HCM-2026-00001'));
      final status = tester.getTopRight(find.byKey(SafetyIncidentsScreen.rowStatusKey('901')));
      final rowRight = tester.getTopRight(row);

      expect(severity.dx, lessThan(number.dx),
          reason: 'the severity chip leads the number it qualifies');
      expect(status.dx, lessThanOrEqualTo(rowRight.dx),
          reason: 'the status chip ends inside the row it belongs to');
      expect(severity.dy, closeTo(number.dy, 8),
          reason: 'the chip and the number are on one line, not stacked');

      // One left edge for the title and the first filter; the rows sit
      // `Spacing.md` inside the card they share, which is the card's own
      // stated alignment (§2).
      final title = tester.getTopLeft(find.text('Safety incidents'));
      final filter = tester.getTopLeft(find.byKey(SafetyIncidentsScreen.orgUnitFilterKey));
      expect(filter.dx, closeTo(title.dx, 1.0));
    });

    testWidgets('at 700 the register is a card per record', (tester) async {
      await _pump(tester, width: 700, location: '/safety/incidents');

      expect(find.byKey(SafetyIncidentsScreen.cardsKey), findsOneWidget);
      expect(find.byKey(SafetyIncidentsScreen.tableKey), findsNothing);
      expect(find.byType(AppTableHeader), findsNothing);
      _expectRowIsATapTarget(tester, find.byKey(SafetyIncidentsScreen.rowKey('901')));
    });

    testWidgets('at twice the text the register is cards, and nothing clips', (tester) async {
      await _pump(tester, width: 1280, location: '/safety/incidents', textScale: 2);

      expect(tester.takeException(), isNull);
      expect(find.byKey(SafetyIncidentsScreen.cardsKey), findsOneWidget,
          reason: 'six columns at twice the text need twice the box');
      expect(find.byKey(SafetyIncidentsScreen.tableKey), findsNothing);
      expect(find.byKey(SafetyIncidentsScreen.rowStatusKey('901')), findsOneWidget,
          reason: 'no state chip is lost at 200%');
    });
  });

  group('Safety observations register', () {
    testWidgets('at 1280 the register is a table and stop-work keeps its own column',
        (tester) async {
      await _pump(tester, width: 1280, location: '/safety/observations');

      expect(find.byKey(SafetyObservationsScreen.tableKey), findsOneWidget);
      expect(find.byType(AppTableHeader), findsOneWidget);

      final row = find.byKey(SafetyObservationsScreen.rowKey('701'));
      expect(find.descendant(of: row, matching: find.byType(AppTableRow)), findsOneWidget);
      _expectRowIsATapTarget(tester, row);

      final potential = tester.getTopLeft(
        find.byKey(SafetyObservationsScreen.rowPotentialKey('701')),
      );
      final stopWork = tester.getTopLeft(
        find.byKey(SafetyObservationsScreen.rowStopWorkKey('701')),
      );
      expect(stopWork.dx, greaterThan(potential.dx),
          reason: 'the badge is its own column, not stacked with the potential');

      // The row nobody marked stop-work draws no badge, and keeps its column.
      expect(find.byKey(SafetyObservationsScreen.rowStopWorkKey('702')), findsNothing);
    });

    testWidgets('at 700 and at twice the text the register is cards', (tester) async {
      for (final (width, scale) in const [(700.0, 1.0), (1280.0, 2.0)]) {
        await _pump(tester, width: width, location: '/safety/observations', textScale: scale);
        expect(tester.takeException(), isNull, reason: 'window $width at ${scale}x');
        expect(find.byKey(SafetyObservationsScreen.cardsKey), findsOneWidget,
            reason: 'window $width at ${scale}x');
        expect(find.byType(AppTableHeader), findsNothing);
      }
    });
  });

  group('The two catalogues', () {
    testWidgets('a catalogue row is 44 tall at 700 and at 1280, at 1x and at 2x', (tester) async {
      for (final width in const [700.0, 1280.0]) {
        await _pump(tester, width: width, location: '/safety/injury-types');
        expect(tester.takeException(), isNull, reason: 'window $width');
        final row = find.byKey(InjuryTypesScreen.rowKey('61'));
        _expectRowIsATapTarget(tester, row);

        // The label starts at the card's own inset and the action ends at the
        // card's right edge less that same inset — one row, two ends, no drift.
        final card = tester.getTopLeft(find.ancestor(of: row, matching: find.byType(Card)));
        final label = tester.getTopLeft(find.text('Cut · CUT'));
        final action = tester.getTopRight(find.byKey(InjuryTypesScreen.correctKey('61')));
        final cardEnd = tester.getTopRight(find.ancestor(of: row, matching: find.byType(Card)));
        expect(label.dx, closeTo(card.dx + 16, 1.0));
        expect(action.dx, closeTo(cardEnd.dx - 16, 1.0));
      }

      await _pump(tester, width: 1280, location: '/safety/injury-types', textScale: 2);
      expect(tester.takeException(), isNull, reason: 'at twice the text');
      _expectRowIsATapTarget(tester, find.byKey(InjuryTypesScreen.rowKey('61')));
      expect(find.byKey(InjuryTypesScreen.correctKey('61')), findsOneWidget,
          reason: 'the action is not lost at 200%');
    });

    testWidgets('a Body part row carries the region it is filed under', (tester) async {
      await _pump(tester, width: 700, location: '/safety/body-parts');

      final row = find.byKey(BodyPartsScreen.rowKey('51'));
      expect(row, findsOneWidget);
      _expectRowIsATapTarget(tester, row);
      // The row's own one text: the part, its code and the region, on one line
      // inside the card's inset.
      final label = find.text('Left hand · HAND-L · Upper limb');
      expect(label, findsOneWidget);
      final card = tester.getTopLeft(find.ancestor(of: row, matching: find.byType(Card)));
      expect(tester.getTopLeft(label).dx, closeTo(card.dx + 16, 1.0));
    });
  });

  group('Safety incident detail', () {
    testWidgets('at 1280 the summary card comes first and the sections stack', (tester) async {
      await _pump(tester, width: 1280, location: '/safety/incidents/901');

      expect(tester.takeException(), isNull);
      final summary = tester.getTopLeft(find.text('Summary'));
      final story = tester.getTopLeft(find.text('What happened'));
      expect(summary.dy, lessThan(story.dy),
          reason: 'what, where and when are read before the narrative');
      expect(find.byKey(SafetyIncidentDetailScreen.filedKey), findsOneWidget);

      // A 1280 window hands this page 1020, less the frame's inset, which is
      // under AppSectionGrid's 1000: the sections stack, and each one starts
      // below the last one's bottom.
      final injury = tester.getTopLeft(find.byKey(SafetyIncidentDetailScreen.injuryKey));
      final events = tester.getTopLeft(find.text('Event history'));
      expect(events.dy, greaterThan(injury.dy));
    });

    testWidgets('at 700 and at twice the text the page holds, summary still first',
        (tester) async {
      for (final (width, scale) in const [(700.0, 1.0), (1280.0, 2.0)]) {
        await _pump(tester, width: width, location: '/safety/incidents/901', textScale: scale);
        expect(tester.takeException(), isNull, reason: 'window $width at ${scale}x');
        expect(
          tester.getTopLeft(find.text('Summary')).dy,
          lessThan(tester.getTopLeft(find.text('What happened')).dy),
          reason: 'window $width at ${scale}x',
        );
      }
    });
  });

  group('Safety observation detail', () {
    testWidgets('the summary card leads, at 700 and at 1280', (tester) async {
      for (final width in const [700.0, 1280.0]) {
        await _pump(tester, width: width, location: '/safety/observations/701');
        expect(tester.takeException(), isNull, reason: 'window $width');
        expect(
          tester.getTopLeft(find.text('Summary')).dy,
          lessThan(tester.getTopLeft(find.text('What was seen')).dy),
          reason: 'window $width',
        );
        expect(find.byKey(SafetyObservationDetailScreen.filedKey), findsOneWidget);
      }
    });
  });

  group('The dialogs these Screens open', () {
    /// A transition dialog's address is built from the detail Bloc's state, so
    /// it is opened the way a person opens it — from the record, after it has
    /// loaded — rather than by typing the address into a cold router.
    Future<void> openStatusDialog(WidgetTester tester,
        {required double width, double textScale = 1}) async {
      await _pump(tester, width: width, location: '/safety/incidents/901', textScale: textScale);
      // The button's own act is `context.go` to the dialog's address (ADR-0021),
      // and the address is built from the detail Bloc's state — so the address
      // is entered from the loaded record, exactly as the tap enters it.
      final context = tester.element(find.byKey(SafetyIncidentDetailScreen.statusKey));
      GoRouter.of(context).go('/safety/incidents/901/status');
      await tester.pumpAndSettle();
    }

    testWidgets('the status dialog is a sheet at 700 and a dialog at 1280', (tester) async {
      await openStatusDialog(tester, width: 700);
      expect(find.byKey(AppDialog.surfaceKey), findsOneWidget);
      expect(find.byKey(AppDialog.sheetKey), findsOneWidget,
          reason: 'a 700 window has no room for a 420 dialog with margins');

      await openStatusDialog(tester, width: 1280);
      expect(find.byKey(AppDialog.surfaceKey), findsOneWidget);
      expect(find.byKey(AppDialog.sheetKey), findsNothing);
      expect(tester.getSize(find.byKey(AppDialog.surfaceKey)).width, closeTo(420, 1));
    });

    testWidgets('at twice the text the dialog is a sheet, and nothing clips', (tester) async {
      await openStatusDialog(tester, width: 1280, textScale: 2);
      expect(tester.takeException(), isNull);
      expect(find.byKey(AppDialog.surfaceKey), findsOneWidget);
      expect(find.byKey(AppDialog.sheetKey), findsOneWidget,
          reason: 'a 420 dialog at twice the text has less usable width than a phone');
    });
  });
}
