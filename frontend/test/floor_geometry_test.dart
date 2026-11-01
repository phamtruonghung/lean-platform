/// The plant floor, measured (issue #387).
///
/// One lane per Org Unit, grouped on the client in first-seen order, under a
/// legend of the tones the lanes actually paint. This pins what a reader can see
/// of that at 1280, at 700, and at a text scale of 2: the legend above the first
/// lane, a lane's header above its first tile, every tile on one left edge and
/// the full width of the lane, `Spacing.sm` between tiles, the 64px action kept,
/// nothing scrolling sideways, and no overflow.
///
/// The app is pumped through the real router with the wire faked, as
/// `floor_technician_surface_test.dart` does; nothing here reaches into a Bloc.
/// The floor is not on `page_alignment_test.dart` (ADR-0016) and stays off it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/maintenance/floor_screen.dart';
import 'package:lean_platform/theme.dart';

import 'harness.dart';

FakeWire _wire() => FakeWire(
      floorWorkOrders: [
        workOrderJson('1', 'WO-1', 'Replace the drive belt',
            orgUnitName: 'Assembly', status: 'approved'),
        workOrderJson('2', 'WO-2', 'Grease the bearings',
            orgUnitName: 'Assembly', status: 'in_progress'),
        workOrderJson('3', 'WO-3', 'Check the sealer', orgUnitName: 'Packing', status: 'on_hold'),
      ],
    );

Future<void> _open(WidgetTester tester, {required double width, double textScale = 1}) async {
  tester.view.devicePixelRatio = 1.0;
  // Tall enough that every lane is built at 2x text: the list builds lazily.
  tester.view.physicalSize = Size(width, 4000);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  await pumpApp(
    tester,
    gateway: FakeAuthGateway(),
    client: _wire().client,
    initialLocation: '/floor',
  );
  expect(find.byType(FloorScreen), findsOneWidget);
}

Finder _tile(String workOrderNo) => find.ancestor(
      of: find.text(workOrderNo),
      matching: find.byType(Card),
    );

void _expectBoard(WidgetTester tester, {required double width}) {
  final assembly = find.text('Assembly');
  final packing = find.text('Packing');
  expect(assembly, findsOneWidget);
  expect(packing, findsOneWidget);

  // Lanes are in first-seen order, and each is counted beside its name.
  expect(tester.getTopLeft(packing).dy, greaterThan(tester.getTopLeft(assembly).dy));
  expect(find.text('2'), findsOneWidget);
  expect(find.text('1'), findsOneWidget);

  // The legend holds only the tones in use (info, warning) and sits above the
  // first lane.
  final info = find.text('Info');
  final warning = find.text('Warning');
  expect(info, findsOneWidget);
  expect(warning, findsOneWidget);
  expect(find.text('Danger'), findsNothing);
  expect(find.text('Success'), findsNothing);
  expect(find.text('Neutral'), findsNothing);
  expect(tester.getBottomRight(info).dy, lessThanOrEqualTo(tester.getTopLeft(assembly).dy));
  expect(tester.getBottomRight(warning).dy, lessThanOrEqualTo(tester.getTopLeft(assembly).dy));

  // A lane's header is above its first tile.
  final first = _tile('WO-1');
  final second = _tile('WO-2');
  final third = _tile('WO-3');
  expect(tester.getBottomRight(assembly).dy, lessThanOrEqualTo(tester.getTopLeft(first).dy));
  expect(tester.getBottomRight(packing).dy, lessThanOrEqualTo(tester.getTopLeft(third).dy));
  expect(tester.getTopLeft(packing).dy,
      greaterThanOrEqualTo(tester.getBottomRight(second).dy));

  // One left edge for the legend, the headers and every tile; full width.
  final left = tester.getTopLeft(first).dx;
  expect(tester.getTopLeft(second).dx, left);
  expect(tester.getTopLeft(third).dx, left);
  expect(tester.getTopLeft(assembly).dx, left);
  expect(tester.getTopLeft(packing).dx, left);
  expect(tester.getTopLeft(find.text('Info')).dx, greaterThanOrEqualTo(left));
  expect(left, Spacing.lg);
  for (final tile in [first, second, third]) {
    expect(tester.getSize(tile).width, width - 2 * Spacing.lg);
  }
  // Tiles in a lane are Spacing.sm apart.
  expect(tester.getTopLeft(second).dy - tester.getBottomRight(first).dy, Spacing.sm);

  // The 64px action is kept.
  for (final key in [FloorScreen.startKey('1'), FloorScreen.completeKey('2')]) {
    expect(find.byKey(key), findsOneWidget);
    expect(tester.getSize(find.byKey(key)).height, greaterThanOrEqualTo(64));
  }

  // Nothing scrolls sideways.
  final horizontal = find.byWidgetPredicate(
    (widget) => widget is Scrollable && widget.axis == Axis.horizontal,
  );
  expect(horizontal, findsNothing);
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets('at 1280 the lanes are stacked full width under the legend', (tester) async {
    await _open(tester, width: 1280);
    _expectBoard(tester, width: 1280);
  });

  testWidgets('at 700 the lanes are stacked full width under the legend', (tester) async {
    await _open(tester, width: 700);
    _expectBoard(tester, width: 700);
  });

  for (final width in [1280.0, 700.0]) {
    testWidgets('at a text scale of 2, at $width, the board holds and nothing overflows',
        (tester) async {
      await _open(tester, width: width, textScale: 2);
      _expectBoard(tester, width: width);
      expect(find.byKey(FloorScreen.refreshKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
