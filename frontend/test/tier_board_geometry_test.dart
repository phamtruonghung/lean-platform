/// The tier board, measured (issue #387).
///
/// One lane per Pillar, stacked, under a legend of the tones the KPI rows
/// actually paint. This pins what a reader can see of that at 1280, at 700, and
/// at a text scale of 2: the legend above the first lane, a lane's header above
/// its first row, every row on the lane's own left edge and its full width, each
/// KPI's status chip inside the lane's box, the table arrangement where the lane
/// is wide and the stacked one where it is not, nothing scrolling sideways, and no
/// overflow.
///
/// The app is pumped through the real router with the wire faked, as
/// `tier_board_test.dart` does; nothing here reaches into a Bloc. `/tier-board` is
/// pinned by `page_alignment_test.dart`, which this does not replace.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/maintenance/tier_board_screen.dart';
import 'package:lean_platform/widgets/app_table.dart';
import 'package:lean_platform/widgets/status_chip.dart';

import 'harness.dart';
import 'tier_board_test.dart' show boardBody, boardWire;

FakeWire _wire() => boardWire(
      board: boardBody(
        pillars: [
          boardPillarJson(
            'S',
            'Safety',
            sortOrder: 1,
            kpis: [
              boardKpiJson('SAF_NEARMISS', 'Near misses reported',
                  unit: 'count', decimalPlaces: 0, value: 5, status: 'green'),
              boardKpiJson('SAF_TRIR', 'Recordable injury rate (TRIR)',
                  unit: 'per 200k hrs', decimalPlaces: 2, value: 5.71, status: 'red'),
              boardKpiJson('SAF_LTIFR', 'Lost time injury frequency (LTIFR)',
                  unit: 'per 1M hrs', decimalPlaces: 2, value: null, status: 'no_data'),
            ],
          ),
          boardPillarJson('Q', 'Quality', sortOrder: 2, kpis: const []),
          boardPillarJson(
            'D',
            'Delivery',
            sortOrder: 3,
            kpis: [
              boardKpiJson('MNT_MTBF', 'Mean time between failures',
                  unit: 'hours', decimalPlaces: 1, value: 7, status: 'no_target'),
            ],
          ),
          boardPillarJson('C', 'Cost', sortOrder: 4, kpis: const []),
          boardPillarJson('P', 'People', sortOrder: 5, kpis: const []),
        ],
      ),
    );

Future<void> _open(WidgetTester tester, {required double width, double textScale = 1}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, 4000);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  await pumpApp(
    tester,
    gateway: FakeAuthGateway(accessToken: 'a-token'),
    client: _wire().client,
    initialLocation: '/tier-board',
  );
  expect(find.byType(TierBoardScreen), findsOneWidget);
}

void _expectBoard(WidgetTester tester, {required bool table}) {
  final lane = find.byKey(TierBoardScreen.pillarKey('S'));
  final laneRect = tester.getRect(lane);
  final heading = find.text('Safety');
  expect(heading, findsOneWidget);

  // Lanes are stacked, in the order the server sent them, one per Pillar.
  var previousBottom = double.negativeInfinity;
  for (final code in ['S', 'Q', 'D', 'C', 'P']) {
    final rect = tester.getRect(find.byKey(TierBoardScreen.pillarKey(code)));
    expect(rect.left, laneRect.left, reason: 'lane $code is on the lanes\' left edge');
    expect(rect.width, laneRect.width, reason: 'lane $code is the full width');
    expect(rect.top, greaterThanOrEqualTo(previousBottom));
    previousBottom = rect.bottom;
  }

  // The legend holds only the tones in use (success, danger, neutral) and sits
  // above the first lane.
  for (final word in ['Success', 'Danger', 'Neutral']) {
    final chip = find.widgetWithText(StatusChip, word);
    expect(chip, findsOneWidget, reason: 'the legend names $word');
    expect(tester.getBottomRight(chip).dy, lessThanOrEqualTo(laneRect.top));
  }
  expect(find.widgetWithText(StatusChip, 'Warning'), findsNothing);
  expect(find.widgetWithText(StatusChip, 'Info'), findsNothing);

  // A lane's header is above its first row, and the count sits beside the name.
  final codes = ['SAF_NEARMISS', 'SAF_TRIR', 'SAF_LTIFR'];
  final rows = [for (final code in codes) find.byKey(TierBoardScreen.kpiKey(code))];
  expect(tester.getBottomRight(heading).dy, lessThanOrEqualTo(tester.getTopLeft(rows.first).dy));
  expect(tester.getTopLeft(heading).dx, greaterThan(laneRect.left));
  expect(find.descendant(of: lane, matching: find.text('3')), findsOneWidget);

  // Every row is on the lane's left edge, the full width of the lane, and in
  // order; a row never shrinks to its content.
  var rowBottom = tester.getTopLeft(rows.first).dy;
  for (final row in rows) {
    final rect = tester.getRect(row);
    expect(rect.left, laneRect.left);
    expect(rect.width, laneRect.width);
    expect(rect.top, greaterThanOrEqualTo(rowBottom));
    rowBottom = rect.bottom;
  }
  expect(rowBottom, lessThanOrEqualTo(laneRect.bottom));

  // Each status chip is inside the lane, the number is not clipped, and the
  // number and the chip do not overlap.
  for (final code in codes) {
    final chip = tester.getRect(find.byKey(TierBoardScreen.kpiStatusKey(code)));
    final value = tester.getRect(find.byKey(TierBoardScreen.kpiValueKey(code)));
    expect(chip.right, lessThanOrEqualTo(laneRect.right));
    expect(chip.left, greaterThanOrEqualTo(laneRect.left));
    expect(value.left, greaterThanOrEqualTo(laneRect.left));
    expect(value.right, lessThanOrEqualTo(chip.left));
  }

  if (table) {
    expect(find.byType(AppTableRow), findsNWidgets(4));
    // Numbers end-aligned and chips end-aligned: one right edge for each column.
    final numberRight = [
      for (final row in rows)
        tester
            .getBottomRight(find.descendant(
              of: row,
              matching: find.byKey(AppTableRow.cellKey(1)),
            ))
            .dx,
    ];
    expect(numberRight.toSet().length, 1, reason: 'one right edge for the numbers');
    final chipRight = [
      for (final code in codes) tester.getBottomRight(find.byKey(TierBoardScreen.kpiStatusKey(code))).dx,
    ];
    expect(chipRight.toSet().length, 1, reason: 'one right edge for the chips');
    // A row nobody can tap is the 32px floor or more.
    for (final row in rows) {
      expect(tester.getSize(row).height, greaterThanOrEqualTo(AppTableRow.height));
    }
  } else {
    expect(find.byType(AppTableRow), findsNothing);
    // Stacked: the name is above the number and chip, which share a line.
    for (final code in codes) {
      final row = tester.getRect(find.byKey(TierBoardScreen.kpiKey(code)));
      final value = tester.getRect(find.byKey(TierBoardScreen.kpiValueKey(code)));
      expect(value.top, greaterThan(row.top));
    }
  }

  // Nothing scrolls sideways.
  // Scoped to the lanes: the date field's own text editor is a horizontal
  // `Scrollable` in the header, which is not the board.
  final horizontal = find.descendant(
    of: find.byType(SingleChildScrollView),
    matching: find.byWidgetPredicate(
      (widget) => widget is Scrollable && widget.axis == Axis.horizontal,
    ),
  );
  expect(horizontal, findsNothing);
  for (final code in ['S', 'Q', 'D', 'C', 'P']) {
    expect(tester.getRect(find.byKey(TierBoardScreen.pillarKey(code))).right,
        lessThanOrEqualTo(tester.view.physicalSize.width));
  }
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets('at 1280 the lanes are stacked, one table per lane, under the legend',
      (tester) async {
    await _open(tester, width: 1280);
    _expectBoard(tester, table: true);
  });

  testWidgets('at 700 the lanes are stacked, a KPI per card, under the legend', (tester) async {
    await _open(tester, width: 700);
    _expectBoard(tester, table: false);
  });

  testWidgets('at a text scale of 2, at 1280, the board holds and nothing overflows',
      (tester) async {
    await _open(tester, width: 1280, textScale: 2);
    _expectBoard(tester, table: false);
    expect(tester.takeException(), isNull);
  });

  testWidgets('at a text scale of 2, at 700, the board holds and nothing overflows',
      (tester) async {
    await _open(tester, width: 700, textScale: 2);
    _expectBoard(tester, table: false);
    expect(tester.takeException(), isNull);
  });
}
