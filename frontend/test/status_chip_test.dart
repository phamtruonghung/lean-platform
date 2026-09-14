/// A status carries a meaning, not only a name (issue #168).
///
/// Two claims, both behavioural:
///
/// 1. A status rendered on a real Screen is painted the tone its own model
///    maps it to — asserted on the fill and label colour a `StatusChip`
///    actually resolves once pumped, never by calling a getter directly.
///    The prior art is `screens_theme_test.dart`, which reads resolved theme
///    values off a pumped widget the same way, and `work_orders_test.dart`,
///    which pumps the real Screen over `FakeWire` (the one client seam,
///    ADR-0012).
/// 2. Every tone's fill/foreground pair meets the 4.5:1 floor the spec's own
///    user story 6 asks for. This is a measurement rather than a comment, so
///    a later token change that quietly drops below the floor fails here
///    instead of shipping.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/maintenance/work_orders_screen.dart';
import 'package:lean_platform/status_tone.dart';
import 'package:lean_platform/theme.dart';
import 'package:lean_platform/widgets/status_chip.dart';

import 'harness.dart';

/// Pins the test surface for one test (issue #168).
///
/// Both layouts render their rows inside a lazy `ListView`, so a row below the
/// fold is not merely off screen — it is not built at all, and a finder for it
/// finds nothing. A surface tall enough for every scripted row is therefore
/// part of the fixture rather than a detail, and it is pinned explicitly for
/// the same reason `work_orders_golden_test.dart` pins its own: the default
/// 800x600 surface would otherwise decide which rows exist.
///
/// The width also picks the layout under test — 1600px of window leaves
/// 1340px of content past the Shell's 260px sidebar, which is the table; 900px
/// leaves 640px, which is the cards.
Future<void> _pinSurface(WidgetTester tester, {required double width}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 2400);
  addTearDown(tester.view.reset);
}

/// The Wire, faked the way the Screen's own tests fake it — Sites, Org Units
/// and Assets included, because this Screen reads a Site at a time and will
/// not read anything without one.
FakeWire _wireWith(Map<String, List<Map<String, dynamic>>> workOrders) => FakeWire(
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [orgUnitJson('10', 'Assembly')],
        '10': [orgUnitJson('11', 'Line 1', parentId: '10', unitType: 'line')],
      },
      assets: {'1': []},
      workOrders: workOrders,
    );

/// The tone a given row's own Status chip was painted with, read off the
/// pumped widget tree — the fill the `StatusChip` handed to its `Chip`, which
/// is the colour a person sees.
Color? _rowStatusFill(WidgetTester tester, String rowId) {
  final chip = tester.widget<Chip>(find.descendant(
    of: find.descendant(
      of: find.byKey(WorkOrdersScreen.rowKey(rowId)),
      matching: find.byType(StatusChip),
    ),
    matching: find.byType(Chip),
  ));
  return chip.backgroundColor;
}

/// The relative luminance WCAG's own contrast ratio is built from.
double _luminance(Color colour) {
  double channel(double value) =>
      value <= 0.03928 ? value / 12.92 : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(colour.r) + 0.7152 * channel(colour.g) + 0.0722 * channel(colour.b);
}

double _contrastRatio(Color foreground, Color background) {
  final a = _luminance(foreground);
  final b = _luminance(background);
  return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
}

void main() {
  group('a Work order\'s status is painted with the meaning it carries', () {
    testWidgets('every status shows its own tone, and its own word', (tester) async {
      // All eight wire statuses on one Screen, so the assertion is about the
      // mapping rather than about one row's luck.
      //
      // History is asked for first, and that is not a convenience: an open read
      // never contains completed, closed or cancelled rows (the server excludes
      // them, and `work_orders_test.dart` proves the Screen honours that), so a
      // closed Work order's own tone is only ever seen through the history
      // read. Asserting those three without asking for history would have been
      // a test that could not fail for the right reason.
      final wire = _wireWith({
        '1': [
          workOrderJson('101', 'WO-101', 'A draft', status: 'draft'),
          workOrderJson('102', 'WO-102', 'Ready to work', status: 'approved'),
          workOrderJson('103', 'WO-103', 'Booked in', status: 'scheduled'),
          workOrderJson('104', 'WO-104', 'Being worked', status: 'in_progress'),
          workOrderJson('105', 'WO-105', 'Waiting on a part', status: 'on_hold'),
          workOrderJson('106', 'WO-106', 'Finished', status: 'completed'),
          workOrderJson('107', 'WO-107', 'Filed away', status: 'closed'),
          workOrderJson('108', 'WO-108', 'Called off', status: 'cancelled'),
        ],
      });

      await _pinSurface(tester, width: 1600);
      await pumpApp(
        tester,
        gateway: FakeAuthGateway(accessToken: 'a-token'),
        client: wire.client,
        initialLocation: '/work-orders',
      );
      await tapIn(tester, find.byKey(WorkOrdersScreen.showHistoryKey));
      expect(wire.workOrderRequests.last, ('1', null, true));

      expect(_rowStatusFill(tester, '101'), AppComponentColors.statusFill(StatusTone.neutral));
      expect(_rowStatusFill(tester, '102'), AppComponentColors.statusFill(StatusTone.info));
      expect(_rowStatusFill(tester, '103'), AppComponentColors.statusFill(StatusTone.info));
      expect(_rowStatusFill(tester, '104'), AppComponentColors.statusFill(StatusTone.info));
      expect(_rowStatusFill(tester, '105'), AppComponentColors.statusFill(StatusTone.warning));
      expect(_rowStatusFill(tester, '106'), AppComponentColors.statusFill(StatusTone.success));
      expect(_rowStatusFill(tester, '107'), AppComponentColors.statusFill(StatusTone.success));
      expect(_rowStatusFill(tester, '108'), AppComponentColors.statusFill(StatusTone.neutral));

      // The word is still there, on every one of them: colour groups a status,
      // it never carries one on its own (user story 5).
      for (final label in ['Draft', 'Approved', 'Scheduled', 'In progress', 'On hold',
        'Completed', 'Closed', 'Cancelled']) {
        expect(find.text(label), findsWidgets, reason: '$label should still be readable');
      }
    });

    testWidgets('the one status that wants a decision is the only warning',
        (tester) async {
      // The whole point of the mapping, asserted as a relationship rather than
      // as eight separate colours: of a live Work order's statuses, exactly one
      // is painted as something the reader has to act on.
      final wire = _wireWith({
        '1': [
          workOrderJson('101', 'WO-101', 'Ready to work', status: 'approved'),
          workOrderJson('102', 'WO-102', 'Being worked', status: 'in_progress'),
          workOrderJson('103', 'WO-103', 'Waiting on a part', status: 'on_hold'),
        ],
      });

      await _pinSurface(tester, width: 900);
      await pumpApp(
        tester,
        gateway: FakeAuthGateway(accessToken: 'a-token'),
        client: wire.client,
        initialLocation: '/work-orders',
      );

      final warning = AppComponentColors.statusFill(StatusTone.warning);
      final fills = [
        _rowStatusFill(tester, '101'),
        _rowStatusFill(tester, '102'),
        _rowStatusFill(tester, '103'),
      ];
      expect(fills.where((fill) => fill == warning), hasLength(1));
      expect(_rowStatusFill(tester, '103'), warning);
    });
  });

  group('every tone is readable against its own fill', () {
    test('the 4.5:1 floor holds for all five tones', () {
      for (final tone in StatusTone.values) {
        final ratio = _contrastRatio(
          AppComponentColors.statusForeground(tone),
          AppComponentColors.statusFill(tone),
        );
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason: '$tone measured ${ratio.toStringAsFixed(2)}:1 against its own fill',
        );
      }
    });
  });
}
