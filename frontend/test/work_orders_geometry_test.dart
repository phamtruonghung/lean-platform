/// The Work order register's geometry, measured (issue #387).
///
/// The register is an `AppTableHeader` band and one `AppTableRow` per Work order
/// at or above 800 of box, and a card per Work order below it. This pins what a
/// reader can see of that: the band is 32 and a row exactly 52 (the 44px
/// control inside it plus the `Spacing.xs` `AppTableRow` pads above and below;
/// design-language §6 moves it from 56 and says a control is never under 44), a header label starts where its cells start, a column's left edge
/// is the same on every row, the actions column ends where the row's padding
/// says, and the card layout has a height of its own that does not drift. The
/// same structure is asserted at a text scale of 2, with no overflow.
///
/// The app is pumped through the real router with the wire faked, as
/// `work_orders_test.dart` does; nothing here reaches into a Bloc.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/maintenance/work_orders_screen.dart';
import 'package:lean_platform/theme.dart';
import 'package:lean_platform/widgets/app_table.dart';
import 'package:lean_platform/widgets/disclosing_text.dart';
import 'package:lean_platform/widgets/app_toolbar.dart';

import 'contrast.dart';
import 'harness.dart';

FakeWire _wire() => FakeWire(
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [orgUnitJson('10', 'Assembly')],
        '10': [orgUnitJson('11', 'Line 1', parentId: '10', unitType: 'line')],
      },
      assets: {'1': []},
      workOrders: {
        '1': [
          workOrderJson('101', 'WO-101', 'Belt is slipping', assigneeName: 'Jane Doe'),
          workOrderJson('102', 'WO-102', 'Guard is loose',
              assetCode: 'CONV-2', assetName: 'Infeed conveyor', status: 'in_progress'),
        ],
      },
    );

FakeWire _realisticWire() => FakeWire(
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [orgUnitJson('10', 'Assembly')],
      },
      assets: {'1': []},
      workOrders: {
        '1': [
          workOrderJson('101', 'WO-BUC-2026-00001', 'Replace the worn drive belt on the infeed',
              orgUnitName: 'Final Assembly Line 1', assigneeName: 'Jane Doe'),
        ],
      },
    );

Future<void> _pump(WidgetTester tester,
    {required double width, double textScale = 1, FakeWire? wire}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, 1000);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  await pumpApp(
    tester,
    gateway: FakeAuthGateway(accessToken: 'a-token'),
    client: (wire ?? _wire()).client,
    initialLocation: '/work-orders',
  );
}

Finder _inRow(String id, Key cell) => find.descendant(
      of: find.byKey(WorkOrdersScreen.rowKey(id)),
      matching: find.byKey(cell),
    );

void main() {
  testWidgets('at 1280 the band is 32, a row is exactly 52, and the columns line up', (tester) async {
    await _pump(tester, width: 1280);

    expect(find.byType(AppTableHeader), findsOneWidget);
    expect(tester.getSize(find.byType(AppTableHeader)).height, AppTableHeader.height);

    for (final id in ['101', '102']) {
      expect(tester.getSize(find.byKey(WorkOrdersScreen.rowKey(id))).height,
          AppTouchTarget.min + 2 * Spacing.xs,
          reason: 'Work order $id: the 44px control inside it plus Spacing.xs above and below, '
              'not 56');
    }

    // A header label starts at the same x as its column's first cell. Actions is
    // end-aligned, so its right edges are the ones that meet.
    final labels = ['WO#', 'Summary', 'Asset', 'Org Unit', 'Status', 'Assignee'];
    for (var i = 0; i < labels.length; i++) {
      final label = find.byKey(AppTableHeader.labelKey(labels[i]));
      final cell = _inRow('101', AppTableRow.cellKey(i));
      expect(tester.getTopLeft(label).dx, tester.getTopLeft(cell).dx,
          reason: '${labels[i]} label and its cell');
      // And the same x on the second row.
      expect(tester.getTopLeft(_inRow('102', AppTableRow.cellKey(i))).dx,
          tester.getTopLeft(cell).dx);
    }
    final actionsLabel = find.byKey(AppTableHeader.labelKey('Actions'));
    expect(tester.getBottomRight(actionsLabel).dx,
        tester.getBottomRight(_inRow('101', AppTableRow.cellKey(6))).dx);

    // The status column's left edge is equal across the two rows.
    expect(tester.getTopLeft(_inRow('101', AppTableRow.cellKey(4))).dx,
        tester.getTopLeft(_inRow('102', AppTableRow.cellKey(4))).dx);

    // The actions column ends flush with the row's content box: the row's right
    // edge less its `Spacing.md` padding and the slot's `Spacing.sm` gutter.
    for (final id in ['101', '102']) {
      final row = tester.getBottomRight(find.byKey(WorkOrdersScreen.rowKey(id))).dx;
      final actions = tester.getBottomRight(_inRow(id, AppTableRow.cellKey(6))).dx;
      expect(actions, row - Spacing.md - Spacing.sm);
    }
  });

  testWidgets('at 1280 every row control is at least 44 wide and tall', (tester) async {
    await _pump(tester, width: 1280);
    final controls = {
      'Start 101': WorkOrdersScreen.startKey('101'),
      'kebab 101': WorkOrdersScreen.rowActionsKey('101'),
      'Complete 102': WorkOrdersScreen.completeKey('102'),
      'kebab 102': WorkOrdersScreen.rowActionsKey('102'),
    };
    for (final entry in controls.entries) {
      final size = tester.getSize(find.byKey(entry.value));
      expect(size.height, AppTouchTarget.min, reason: '${entry.key} height');
      expect(size.width, greaterThanOrEqualTo(AppTouchTarget.min), reason: '${entry.key} width');
    }
  });

  testWidgets('at 1280 the rows are no taller than 52, so a working day\'s list fits',
      (tester) async {
    await _pump(tester, width: 1280);
    final first = tester.getTopLeft(find.byKey(WorkOrdersScreen.rowKey('101'))).dy;
    final second = tester.getTopLeft(find.byKey(WorkOrdersScreen.rowKey('102'))).dy;
    expect(second - first, AppTouchTarget.min + 2 * Spacing.xs);
    // Rows that fit in the 900px under the band: the page above the first row is
    // measured, not assumed.
    final bandBottom = tester.getBottomRight(find.byType(AppTableHeader)).dy;
    const body = 900.0;
    final rows = ((body - bandBottom) / (AppTouchTarget.min + 2 * Spacing.xs)).floor();
    expect(rows, greaterThanOrEqualTo(10),
        reason: 'a 900px page shows at least ten rows below a band at $bandBottom');
    expect(tester.takeException(), isNull);
  });

  testWidgets('at 700 the register is one card per Work order, at a measured height',
      (tester) async {
    await _pump(tester, width: 700);

    expect(find.byType(AppTableHeader), findsNothing);
    final a = find.byKey(WorkOrdersScreen.rowKey('101'));
    final b = find.byKey(WorkOrdersScreen.rowKey('102'));
    expect(a, findsOneWidget);
    expect(tester.getTopLeft(a).dx, tester.getTopLeft(b).dx);
    expect(tester.getSize(a).width, tester.getSize(b).width);
    // The first fixture is a one-line card; the second's Asset wraps, so it is
    // taller, and a card grows with its text rather than being cut to a height.
    expect(tester.getSize(b).height, greaterThanOrEqualTo(tester.getSize(a).height));
    expect(tester.getSize(a).height, _cardHeight, reason: 'the card height quoted in the file');
    expect(tester.takeException(), isNull);
  });

  testWidgets('at 900 the register is cards, at the list\'s inset', (tester) async {
    await _pump(tester, width: 900);

    expect(find.byType(AppTableHeader), findsNothing, reason: 'a 608 box is under 800');
    final a = find.byKey(WorkOrdersScreen.rowKey('101'));
    final b = find.byKey(WorkOrdersScreen.rowKey('102'));
    expect(a, findsOneWidget);
    const sidebar = 260.0;
    expect(tester.getTopLeft(a).dx, sidebar + Spacing.lg);
    expect(tester.getBottomRight(a).dx, 900 - Spacing.lg);
    expect(tester.getSize(a).width, 900 - sidebar - 2 * Spacing.lg);
    expect(tester.getTopLeft(b).dx, tester.getTopLeft(a).dx);
    expect(tester.getTopLeft(b).dy, greaterThan(tester.getBottomRight(a).dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets('at 1280 with realistic content the WO# fits and every clipped cell discloses',
      (tester) async {
    await _pump(tester, width: 1280, wire: _realisticWire());

    final wo = _inRow('101', AppTableRow.cellKey(0));
    final woParagraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: wo, matching: find.text('WO-BUC-2026-00001')));
    expect(woParagraph.didExceedMaxLines, isFalse, reason: 'its column is measured to fit it');

    // Every text cell: if its paragraph is clipped it must be a DisclosingText.
    for (final i in [0, 1, 2, 3, 5]) {
      final cell = _inRow('101', AppTableRow.cellKey(i));
      final paragraphs = find.descendant(of: cell, matching: find.byType(RichText));
      expect(paragraphs, findsOneWidget, reason: 'cell $i');
      final paragraph = tester.renderObject<RenderParagraph>(paragraphs);
      // ignore: avoid_print
      print('cell $i: slot ${tester.getSize(cell).width} text ${paragraph.size.width} clipped ${paragraph.didExceedMaxLines}');
      if (paragraph.didExceedMaxLines) {
        expect(find.descendant(of: cell, matching: find.byType(DisclosingText)), findsOneWidget,
            reason: 'cell $i is clipped, so it must be disclosed');
      }
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('at 1280 and 700 the toolbar carries the count, and nothing overflows',
      (tester) async {
    for (final width in [1280.0, 700.0]) {
      await _pump(tester, width: width);
      expect(find.byType(AppToolbar), findsOneWidget, reason: 'width $width');
      expect(find.byKey(WorkOrdersScreen.countKey), findsOneWidget, reason: 'width $width');
      expect(find.byKey(WorkOrdersScreen.showHistoryKey), findsOneWidget, reason: 'width $width');
      expect(tester.takeException(), isNull, reason: 'width $width');
    }
  });

  testWidgets('at a text scale of 2, at 1280 and at 700, it is cards and nothing overflows',
      (tester) async {
    for (final width in [1280.0, 700.0]) {
      await _pump(tester, width: width, textScale: 2);
      expect(find.byType(AppTableHeader), findsNothing, reason: 'the 800 doubles at 2x ($width)');
      final a = find.byKey(WorkOrdersScreen.rowKey('101'));
      expect(a, findsOneWidget);
      // The card sits at the list's own inset and is as wide as the box less it;
      // the second card is below the fold at this size, so it is not measured.
      const sidebar = 260.0;
      final frame = (width - sidebar) < 960 ? width - sidebar : 960.0;
      expect(tester.getTopLeft(a).dx, sidebar + (width - sidebar - frame) / 2 + Spacing.lg,
          reason: 'one left edge: the Shell\'s sidebar, then the list inset ($width)');
      expect(tester.getBottomRight(a).dx, sidebar + (width - sidebar - frame) / 2 + frame - Spacing.lg);
      expect(find.byKey(WorkOrdersScreen.raiseKey), findsOneWidget);
      expect(find.byKey(WorkOrdersScreen.rowActionsKey('101')), findsOneWidget);
      expect(find.byKey(WorkOrdersScreen.startKey('101')), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'width $width');
    }
  });

  testWidgets('the dialog failure text is readable on the card', (tester) async {
    // The only new foreground/background pair in this slice: `statusDanger` text
    // on a `card`, in both palettes.
    for (final palette in [AppPalette.light, AppPalette.dark]) {
      final ratio = contrastRatio(palette.statusDanger, palette.card);
      // ignore: avoid_print
      print('statusDanger on card: ${ratio.toStringAsFixed(2)}:1');
      expect(ratio, greaterThanOrEqualTo(4.5));
    }
  });
}

/// Measured from this test, see the card's comment in `work_orders_screen.dart`.
const double _cardHeight = 208;
