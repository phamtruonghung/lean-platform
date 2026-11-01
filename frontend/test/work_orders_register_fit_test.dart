/// What the Work order register's cells can hold in the app's own font (issue
/// #387).
///
/// `work_orders_geometry_test.dart` runs in the test framework's default font,
/// whose glyphs are square and wide, so it cannot say whether a real value fits.
/// This file loads Roboto (`loadAppFonts`) and measures, at a 1280 window with
/// realistic content, that the WO# column holds its number, that the Summary has
/// more than the 141.5px the old split gave it, that "Unassigned" and an ordinary
/// person's name are not clipped (issue #168 raised the Assignee's share for
/// exactly those), and that any cell that does clip is a `DisclosingText`.
///
/// The app is pumped through the real router with the wire faked; nothing here
/// reaches into a Bloc.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/maintenance/work_orders_screen.dart';
import 'package:lean_platform/widgets/app_table.dart';
import 'package:lean_platform/widgets/disclosing_text.dart';

import 'harness.dart';

FakeWire _wire({String? assignee}) => FakeWire(
      sites: [siteJson('1', 'HCM', 'Ho Chi Minh')],
      orgUnits: {
        null: [orgUnitJson('10', 'Assembly')],
      },
      assets: {'1': []},
      workOrders: {
        '1': [
          workOrderJson('101', 'WO-BUC-2026-00001', 'Replace the worn drive belt on the infeed',
              orgUnitName: 'Final Assembly Line 1', assigneeName: assignee),
        ],
      },
    );

Future<void> _pump(WidgetTester tester,
    {required double width, double textScale = 1, String? assignee}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, 1000);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  await pumpApp(
    tester,
    gateway: FakeAuthGateway(accessToken: 'a-token'),
    client: _wire(assignee: assignee).client,
    initialLocation: '/work-orders',
  );
}

Finder _cell(int i) => find.descendant(
      of: find.byKey(WorkOrdersScreen.rowKey('101')),
      matching: find.byKey(AppTableRow.cellKey(i)),
    );

/// The width the cell's text asks for on one line, and the width it was given.
({double need, double got}) _fit(WidgetTester tester, int i) {
  final paragraph =
      tester.renderObject<RenderParagraph>(find.descendant(of: _cell(i), matching: find.byType(RichText)));
  final need = (TextPainter(
    text: paragraph.text,
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(tester.element(_cell(i))),
  )..layout())
      .width;
  return (need: need, got: tester.getSize(_cell(i)).width);
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('at 1280 the WO# fits, the Summary is wider than before, and a name is not clipped',
      (tester) async {
    for (final assignee in [null, 'Nguyen Van Anh']) {
      await _pump(tester, width: 1280, assignee: assignee);

      final wo = _fit(tester, 0);
      expect(wo.need, lessThanOrEqualTo(wo.got), reason: 'the WO# column is measured to fit it');
      expect(_fit(tester, 1).got, greaterThan(141.5), reason: 'the Summary had 141.5 before');
      final who = _fit(tester, 5);
      expect(who.need, lessThanOrEqualTo(who.got),
          reason: '${assignee ?? 'Unassigned'} fits the Assignee column');

      // Whatever does not fit is disclosed.
      for (final i in [0, 1, 2, 3, 5]) {
        final fit = _fit(tester, i);
        if (fit.need > fit.got) {
          expect(find.descendant(of: _cell(i), matching: find.byType(DisclosingText)),
              findsOneWidget, reason: 'cell $i is clipped, so it must be disclosed');
        }
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('at the narrowest table windows nothing overflows and every clipped cell discloses',
      (tester) async {
    for (final (width, scale) in [(1093.0, 1.0), (1245.0, 1.19)]) {
      await _pump(tester, width: width, textScale: scale, assignee: 'Nguyen Van Anh');
      expect(find.byType(AppTableHeader), findsOneWidget, reason: 'a table at $width x$scale');
      for (final i in [1, 2, 3, 5]) {
        final fit = _fit(tester, i);
        expect(fit.got, greaterThan(0), reason: 'cell $i at $width x$scale');
        if (fit.need > fit.got) {
          expect(find.descendant(of: _cell(i), matching: find.byType(DisclosingText)),
              findsOneWidget, reason: 'cell $i at $width x$scale');
        }
      }
      expect(tester.takeException(), isNull, reason: 'width $width x$scale');
    }
  });
}
