/// One Work order's detail, measured (issue #387).
///
/// The page is a summary card, then `AppDetailSection`s. In a page box under
/// `AppBreakpoints.detailTwoColumn` (1000), at the reader's text scale, it is one
/// column and the booking actions sit in the summary card's own action row; from
/// 1000 the sections are the left column and the actions are a right rail. This
/// pins what a reader can see of that at 1280, at 700, and at a text scale of 2,
/// with no overflow at any of them.
///
/// The app is pumped through the real router with the wire faked, as
/// `work_order_cost_test.dart` does; nothing here reaches into a Bloc.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/maintenance/work_order_detail_screen.dart';
import 'package:lean_platform/theme.dart';
import 'package:lean_platform/widgets/app_detail_section.dart';

import 'contrast.dart';
import 'harness.dart';

FakeWire _wire() => FakeWire(
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [orgUnitJson('10', 'Assembly')],
      },
      workOrders: {
        '1': [workOrderJson('101', 'WO-101', 'Belt is slipping', assigneeName: 'Jane Doe')],
      },
      workOrderTasks: {
        '101': [
          workOrderTaskJson('t1', 1, 'Isolate the press', status: 'done'),
          workOrderTaskJson('t2', 2, 'Record vibration',
              assetMeterId: '5', meterName: 'Vibration', status: 'pending'),
        ],
      },
      workOrderCosts: {
        '101': workOrderCostJson(
          labourHours: 3,
          overtimeHours: 1,
          labourByActivity: [labourActivityJson('work', 3, overtimeHours: 1)],
          parts: [workOrderPartJson('p1', quantity: 2, totalCost: 40)],
          partsCost: 40,
        ),
      },
    );

Future<void> _open(WidgetTester tester, {required double width, double textScale = 1}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, 1000);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  await pumpApp(
    tester,
    gateway: FakeAuthGateway(accessToken: 'a-token'),
    client: _wire().client,
    initialLocation: '/work-orders/101',
  );
  expect(find.byType(WorkOrderDetailScreen), findsOneWidget);
}

Finder _section(String title) => find.ancestor(
      of: find.byKey(AppDetailSection.titleKey(title)),
      matching: find.byType(Card),
    );

Finder get _summary => find.descendant(
      of: find.byType(WorkOrderDetailScreen),
      matching: find.byType(Card),
    ).first;

void _expectOneColumn(WidgetTester tester) {
  final summary = _summary;
  final tasks = _section('Tasks');
  final cost = _section('Cost so far');
  expect(tasks, findsOneWidget);
  expect(cost, findsOneWidget);

  // One left edge for the summary and both sections, and each under the last.
  expect(tester.getTopLeft(tasks).dx, tester.getTopLeft(summary).dx);
  expect(tester.getTopLeft(cost).dx, tester.getTopLeft(tasks).dx);
  expect(tester.getSize(tasks).width, tester.getSize(summary).width);
  expect(tester.getTopLeft(tasks).dy, greaterThan(tester.getBottomRight(summary).dy - 1));
  expect(tester.getTopLeft(cost).dy, greaterThan(tester.getBottomRight(tasks).dy - 1));

  // The booking actions are in the summary card, above the sections.
  for (final key in [WorkOrderDetailScreen.bookLabourKey, WorkOrderDetailScreen.bookPartKey]) {
    final button = find.byKey(key);
    expect(button, findsOneWidget);
    expect(find.descendant(of: summary, matching: find.byKey(key)), findsOneWidget);
    expect(tester.getBottomRight(button).dy, lessThanOrEqualTo(tester.getBottomRight(summary).dy));
    expect(tester.getSize(button).height, greaterThanOrEqualTo(AppTouchTarget.min));
  }
  expect(find.byKey(WorkOrderDetailScreen.recordReadingKey('t2')), findsOneWidget);
  // At least the floor: the framework pads a 44px button's tap region to 48.
  expect(tester.getSize(find.byKey(WorkOrderDetailScreen.recordReadingKey('t2'))).height,
      greaterThanOrEqualTo(AppTouchTarget.min));
}

void main() {
  testWidgets('at 1280 the sections are the left column and the booking actions a right rail',
      (tester) async {
    await _open(tester, width: 1280);

    final tasks = _section('Tasks');
    final cost = _section('Cost so far');
    expect(tester.getTopLeft(cost).dx, tester.getTopLeft(tasks).dx);
    expect(tester.getBottomRight(cost).dx, tester.getBottomRight(tasks).dx);

    final labour = find.byKey(WorkOrderDetailScreen.bookLabourKey);
    final part = find.byKey(WorkOrderDetailScreen.bookPartKey);
    for (final rail in [labour, part]) {
      expect(tester.getTopLeft(rail).dx, greaterThan(tester.getBottomRight(tasks).dx),
          reason: 'the rail is strictly right of the sections');
      expect(tester.getSize(rail).height, greaterThanOrEqualTo(AppTouchTarget.min));
      expect(find.descendant(of: _summary, matching: find.byKey(WorkOrderDetailScreen.bookLabourKey)),
          findsNothing, reason: 'two columns: the actions are not in the summary card');
    }
    expect(tester.getTopLeft(part).dx, tester.getTopLeft(labour).dx);
    expect(tester.getTopLeft(part).dy, greaterThan(tester.getBottomRight(labour).dy - 1));

    // The summary is first and spans the sections and the rail.
    expect(tester.getBottomRight(_summary).dy,
        lessThanOrEqualTo(tester.getTopLeft(tasks).dy));
    expect(tester.getTopLeft(_summary).dx, tester.getTopLeft(tasks).dx);
    expect(tester.getBottomRight(_summary).dx, tester.getBottomRight(labour).dx);
    expect(tester.getSize(find.byKey(WorkOrderDetailScreen.recordReadingKey('t2'))).height,
        greaterThanOrEqualTo(AppTouchTarget.min));
    expect(tester.takeException(), isNull);
  });

  testWidgets('at 700 it is one column and the booking actions are above the sections',
      (tester) async {
    await _open(tester, width: 700);
    _expectOneColumn(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('at 900 it is one column and the booking actions are above the sections',
      (tester) async {
    await _open(tester, width: 900);
    _expectOneColumn(tester);
    // The 640 box less the page's own inset: the card is within the window, and
    // the actions sit above the sections.
    expect(tester.getBottomRight(_summary).dx, lessThanOrEqualTo(900));
    expect(tester.getSize(_summary).width, greaterThan(0));
    expect(tester.getTopLeft(find.byKey(WorkOrderDetailScreen.bookLabourKey)).dy,
        lessThan(tester.getTopLeft(_section('Tasks')).dy));
    expect(tester.takeException(), isNull);
  });

  for (final width in [1280.0, 700.0]) {
    testWidgets('at a text scale of 2, at $width, it is one column and nothing overflows',
        (tester) async {
      await _open(tester, width: width, textScale: 2);
      _expectOneColumn(tester);
      expect(find.byKey(WorkOrderDetailScreen.backKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the summary card shows no date and says who holds the Work order', (tester) async {
    await _open(tester, width: 1280);
    expect(find.descendant(of: _summary, matching: find.text('WO-101')), findsOneWidget);
    expect(find.descendant(of: _summary, matching: find.text('Belt is slipping')), findsOneWidget);
    expect(find.descendant(of: _summary, matching: find.text('Press 1 (PRESS-1)')), findsOneWidget);
    expect(find.descendant(of: _summary, matching: find.text('Jane Doe')), findsOneWidget);
  });

  testWidgets('muted and primary text are readable on the card they sit on', (tester) async {
    // The new foreground/background pairs on this page: `textMuted` and
    // `textPrimary` on a `card`, in both palettes (the failure text, `statusDanger`
    // on `card`, is measured in `work_orders_geometry_test.dart`).
    for (final palette in [AppPalette.light, AppPalette.dark]) {
      final muted = contrastRatio(palette.textMuted, palette.card);
      final primary = contrastRatio(palette.textPrimary, palette.card);
      // ignore: avoid_print
      print('textMuted on card: ${muted.toStringAsFixed(2)}:1, '
          'textPrimary on card: ${primary.toStringAsFixed(2)}:1');
      expect(muted, greaterThanOrEqualTo(4.5));
      expect(primary, greaterThanOrEqualTo(4.5));
    }
  });
}
