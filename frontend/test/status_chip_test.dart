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
///
///    This claim is asserted on **every surface the spec's own user story 7
///    names**: the Work orders Screen, a Request's own list, the Downtime log
///    and a Work order's own steps. The vocabulary is shared
///    (`lib/status_tone.dart`), so a single surface passing proves the widget
///    works but not that the other three map onto it — each status-bearing
///    model keeps its own map, and each map is the one its Screen reads.
/// 2. Every tone's fill/foreground pair meets the 4.5:1 floor the spec's own
///    user story 6 asks for — measured on the pair a `StatusChip` actually
///    resolves, not on the tokens in isolation (the rendered ratio is computed
///    inside `_expectTone`, from the colours read back off a pumped widget),
///    with one token-level sweep underneath it for a tone no Screen paints yet.
///    A measurement rather than a comment, so a later token change that quietly
///    drops below the floor fails here instead of shipping.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/maintenance/downtime_screen.dart';
import 'package:lean_platform/maintenance/my_requests_screen.dart';
import 'package:lean_platform/maintenance/work_order_detail_screen.dart';
import 'package:lean_platform/maintenance/work_orders_screen.dart';
import 'package:lean_platform/platform/destinations.dart';
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

/// The Wire behind the Work orders Screen, faked the way that Screen's own
/// tests fake it — Sites, Org Units and Assets included, because this Screen
/// reads a Site at a time and will not read anything without one.
///
/// `workOrderTasks` is what the detail read merges onto a row, keyed by Work
/// order id, so the same builder serves both the list and the detail.
FakeWire _workOrderWire(
  Map<String, List<Map<String, dynamic>>> workOrders, {
  Map<String, List<Map<String, dynamic>>>? workOrderTasks,
}) =>
    FakeWire(
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [orgUnitJson('10', 'Assembly')],
        '10': [orgUnitJson('11', 'Line 1', parentId: '10', unitType: 'line')],
      },
      assets: {'1': []},
      workOrders: workOrders,
      workOrderTasks: workOrderTasks,
    );

/// The Wire behind a Request's own list (`/my-requests`) — the operator the
/// raise Destination belongs to, holding a read Grant at Org Unit 10, the same
/// caller `requests_test.dart` pumps with.
FakeWire _requestWire(List<Map<String, dynamic>> myRequests) => FakeWire(
      role: Roles.operator,
      orgUnitScope: {
        'everywhere': false,
        'grants': [scopeGrantJson('10')],
      },
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [orgUnitJson('10', 'Assembly')],
      },
      assets: {'1': []},
      myRequests: {'1': myRequests},
    );

/// The Wire behind the Downtime log — the supervisor holding a write Grant at
/// Org Unit 10, the same caller `downtime_test.dart` pumps with.
FakeWire _downtimeWire(List<Map<String, dynamic>> downtime) => FakeWire(
      role: Roles.supervisor,
      orgUnitScope: {
        'everywhere': false,
        'grants': [scopeGrantJson('10', canWrite: true)],
      },
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [orgUnitJson('10', 'Assembly')],
      },
      assets: {
        '1': [assetJson('7', 'PRESS-1', 'Press 1')],
      },
      downtime: {'1': downtime},
    );

/// The tone a given row's own Status chip was painted with, read off the
/// pumped widget tree — the fill the `StatusChip` handed to its `Chip`, which
/// is the colour a person sees.
Color? _statusFillIn(WidgetTester tester, Finder row) =>
    _renderedChipIn(tester, row).$1;

/// The fill and the label colour a `StatusChip` actually resolved inside
/// [row], read off the pumped widget tree.
///
/// Both halves, not just the fill: a review of the first version of this file
/// pointed out that its header claimed the fill *and* the label colour were
/// asserted while only the fill was read, and that the contrast floor was
/// checked against the tokens rather than against what a `StatusChip`
/// resolves. Reading the pair back off a rendered widget closes both.
(Color?, Color?) _renderedChipIn(WidgetTester tester, Finder row) {
  final chip = tester.widget<Chip>(find.descendant(
    of: find.descendant(of: row, matching: find.byType(StatusChip)),
    matching: find.byType(Chip),
  ));
  return (chip.backgroundColor, chip.labelStyle?.color);
}

/// Asserts everything a status has to be, off the rendered widget: the fill it
/// was painted with, the colour of its own label, and the contrast ratio
/// *between those two rendered colours* — which is the measurement issue #168's
/// testing decisions ask for, and the one a person's eyes actually make.
void _expectTone(WidgetTester tester, Finder row, StatusTone tone, {required String label}) {
  final (fill, foreground) = _renderedChipIn(tester, row);
  expect(fill, AppComponentColors.statusFill(tone), reason: '$label fill');
  expect(foreground, AppComponentColors.statusForeground(tone), reason: '$label label colour');
  final ratio = _contrastRatio(foreground!, fill!);
  expect(
    ratio,
    greaterThanOrEqualTo(4.5),
    reason: '$label measured ${ratio.toStringAsFixed(2)}:1 as rendered',
  );
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
    Finder row(String id) => find.byKey(WorkOrdersScreen.rowKey(id));

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
      final wire = _workOrderWire({
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

      // Fill, label colour and the rendered contrast ratio, per status — read
      // off each row's own chip rather than off the tokens.
      _expectTone(tester, row('101'), StatusTone.neutral, label: 'Draft');
      _expectTone(tester, row('102'), StatusTone.info, label: 'Approved');
      _expectTone(tester, row('103'), StatusTone.info, label: 'Scheduled');
      _expectTone(tester, row('104'), StatusTone.info, label: 'In progress');
      _expectTone(tester, row('105'), StatusTone.warning, label: 'On hold');
      _expectTone(tester, row('106'), StatusTone.success, label: 'Completed');
      _expectTone(tester, row('107'), StatusTone.success, label: 'Closed');
      _expectTone(tester, row('108'), StatusTone.neutral, label: 'Cancelled');

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
      final wire = _workOrderWire({
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
        _statusFillIn(tester, row('101')),
        _statusFillIn(tester, row('102')),
        _statusFillIn(tester, row('103')),
      ];
      expect(fills.where((fill) => fill == warning), hasLength(1));
      expect(_statusFillIn(tester, row('103')), warning);
    });
  });

  // The other three surfaces user story 7 names. Each one is a different map
  // in a different file (`request.dart`, `downtime_event.dart`,
  // `work_order.dart`'s own task map), so each one is a separate chance to
  // drift — the shared vocabulary is only shared if every Screen reads it.
  group('a Request\'s own list carries the same vocabulary', () {
    testWidgets('every Request state shows its own tone, and its own word', (tester) async {
      final wire = _requestWire([
        requestJson('101', 'MR-101', 'Pump is noisy', status: 'new'),
        requestJson('102', 'MR-102', 'Guard is loose', status: 'triaged'),
        requestJson(
          '103',
          'MR-103',
          'Belt is slipping',
          status: 'accepted',
          workOrder: requestWorkOrderJson('900', 'WO-900'),
        ),
        requestJson('104', 'MR-104', 'Not a job for us', status: 'rejected'),
        requestJson('105', 'MR-105', 'Already raised', status: 'duplicate'),
      ]);

      await _pinSurface(tester, width: 900);
      await pumpApp(
        tester,
        gateway: FakeAuthGateway(accessToken: 'a-token'),
        client: wire.client,
        initialLocation: '/my-requests',
      );

      Finder row(String id) => find.byKey(MyRequestsScreen.rowKey(id));

      // `new` is this list's `warning` for the same reason `on_hold` is the
      // Work orders table's: it is the one state waiting on the reader.
      expect(_statusFillIn(tester, row('101')), AppComponentColors.statusFill(StatusTone.warning));
      expect(_statusFillIn(tester, row('102')), AppComponentColors.statusFill(StatusTone.info));
      expect(_statusFillIn(tester, row('103')), AppComponentColors.statusFill(StatusTone.success));
      // A decline and a duplicate are decisions somebody made, not faults — so
      // neither is painted `danger`.
      expect(_statusFillIn(tester, row('104')), AppComponentColors.statusFill(StatusTone.neutral));
      expect(_statusFillIn(tester, row('105')), AppComponentColors.statusFill(StatusTone.neutral));

      for (final label in ['New', 'Triaged', 'Accepted', 'Rejected', 'Duplicate']) {
        expect(find.text(label), findsWidgets, reason: '$label should still be readable');
      }
    });
  });

  group('the Downtime log carries the same vocabulary', () {
    testWidgets('a running stop is the one that catches the eye, and a closed one is quiet',
        (tester) async {
      final wire = _downtimeWire([
        downtimeJson('1', status: 'open'),
        downtimeJson(
          '2',
          status: 'unclassified',
          startedAt: DateTime.utc(2024, 1, 1, 6),
          endedAt: DateTime.utc(2024, 1, 1, 8),
          durationMinutes: 120,
        ),
        downtimeJson(
          '3',
          status: 'closed',
          startedAt: DateTime.utc(2024, 1, 1, 6),
          endedAt: DateTime.utc(2024, 1, 1, 7),
          durationMinutes: 60,
          downtimeReasonId: '5',
          downtimeReasonName: 'Mechanical',
        ),
      ]);

      await _pinSurface(tester, width: 900);
      await pumpApp(
        tester,
        gateway: FakeAuthGateway(accessToken: 'a-token'),
        client: wire.client,
        initialLocation: '/downtime',
      );

      Finder row(String id) => find.byKey(DowntimeScreen.rowKey(id));

      // Only the open stop is on this Screen, and that is the read's own shape
      // rather than a gap in the test: the Downtime log is served open stops by
      // default (the Wire fakes exactly that), and this Screen offers no
      // history toggle the way the Work orders list does. `DowntimeEvent`'s own
      // tone map covers all three of its states — a closed stop is `success`
      // and an unclassified one `info` — but only `open` reaches a reader
      // today, so only `open` is asserted here. Asserting the other two through
      // this Screen would have been a test that could not fail for the right
      // reason: rows 2 and 3 never render, so it would have failed on the Wire
      // rather than on the vocabulary.
      expect(_statusFillIn(tester, row('1')), AppComponentColors.statusFill(StatusTone.warning));
      expect(find.text('Open'), findsWidgets);
    });
  });

  group('a Work order\'s own steps carry the same vocabulary', () {
    testWidgets('a failed step is the only fault, and a finished one stops competing',
        (tester) async {
      final wire = _workOrderWire(
        {
          '1': [workOrderJson('101', 'WO-101', 'Belt is slipping', status: 'in_progress')],
        },
        workOrderTasks: {
          '101': [
            workOrderTaskJson('t1', 1, 'Isolate the press', status: 'done'),
            workOrderTaskJson('t2', 2, 'Replace the belt', status: 'pending'),
            workOrderTaskJson('t3', 3, 'Check the guard', status: 'skipped'),
            workOrderTaskJson('t4', 4, 'Re-tension the belt', status: 'failed'),
          ],
        },
      );

      await _pinSurface(tester, width: 900);
      await pumpApp(
        tester,
        gateway: FakeAuthGateway(accessToken: 'a-token'),
        client: wire.client,
        initialLocation: '/work-orders',
      );

      // Reached the way a person reaches it — the row's own link, not the
      // address directly, so the tap path is exercised too.
      await tapIn(tester, find.byKey(WorkOrdersScreen.detailsKey('101')));
      expect(find.byType(WorkOrderDetailScreen), findsOneWidget);

      Finder step(String id) => find.byKey(WorkOrderDetailScreen.taskKey(id));

      // The rendered pair and its ratio for every step — this is the only place
      // `danger` reaches a reader, so it is the only place its rendered
      // contrast can be measured at all.
      _expectTone(tester, step('t1'), StatusTone.success, label: 'Done');
      _expectTone(tester, step('t2'), StatusTone.neutral, label: 'Pending');
      // Somebody chose to step over it, so it is not a warning.
      _expectTone(tester, step('t3'), StatusTone.neutral, label: 'Skipped');
      _expectTone(tester, step('t4'), StatusTone.danger, label: 'Failed');

      // `danger` is reserved for faults: of these four states, exactly the
      // failed one is painted with it.
      final danger = AppComponentColors.statusFill(StatusTone.danger);
      final fills = [
        _statusFillIn(tester, step('t1')),
        _statusFillIn(tester, step('t2')),
        _statusFillIn(tester, step('t3')),
        _statusFillIn(tester, step('t4')),
      ];
      expect(fills.where((fill) => fill == danger), hasLength(1));

      for (final label in ['Done', 'Pending', 'Skipped', 'Failed']) {
        expect(find.text(label), findsWidgets, reason: '$label should still be readable');
      }
    });
  });

  group('every tone is readable against its own fill', () {
    // The rendering path is measured above, tone by tone, on the Screens that
    // show each one. This is the sweep underneath it: it covers all five tones
    // including any a Screen does not currently render, so a token change that
    // drops below the floor is caught even when no surface paints it yet.
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
