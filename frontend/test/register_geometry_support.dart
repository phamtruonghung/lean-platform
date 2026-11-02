/// What the maintenance registers' geometry tests share (issue #388): one way to
/// pump a Screen at a window and a text scale, and the measurements every register
/// owes, written once so the three test files say only what is particular to each
/// Screen. Nothing here reaches into a Bloc; it measures boxes, as
/// `work_orders_geometry_test.dart` does.
///
/// **Each file loads the app's own fonts first** (`setUpAll(loadAppFonts)`, the
/// way the golden tests do). Without them `flutter_test` paints a placeholder
/// font whose every glyph is a square twice as wide as Roboto's, and every
/// number pinned here would be a property of that placeholder rather than of the
/// app: measured, My requests' fixed columns overflow a 900px box by 9.9px in
/// the placeholder font and fit it with room in Roboto's. The registers size
/// their fixed columns from their own content, so the font is part of the
/// measurement.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lean_platform/widgets/app_table.dart';

import 'harness.dart';

/// One register, as a test sees it.
class RegisterSpec {
  const RegisterSpec({
    required this.name,
    required this.location,
    required this.wire,
    required this.rowKey,
    required this.ids,
    required this.columns,
    required this.rowHeights,
    required this.cardHeights,
    required this.tableFromWindow,
    required this.primaryKey,
    this.numericColumn,
    this.numericDigitsVary = true,
  });

  final String name;
  final String location;
  final FakeWire Function() wire;
  final Key Function(String id) rowKey;

  /// The record ids the fixture holds, in the order the Screen lists them.
  final List<String> ids;

  /// The band's labels in column order; `true` marks an end-aligned column.
  final List<(String label, bool end)> columns;

  /// A row's height at 1280, per id (the Screen's own file states it).
  final Map<String, double> rowHeights;

  /// A card's height at a 700 window, per id, in the test font. Measured, not
  /// assumed: a card grows with its own text, so two records differ.
  final Map<String, double> cardHeights;

  /// **The window at which this Screen switches from cards to its table**,
  /// measured. A register is handed a box, not the window — the Shell's 260px
  /// rail comes off first — and where a Screen measures the *list's own* box it
  /// also loses the frame and the list's `Spacing.lg` inset either side, so a
  /// stated `narrowBreakpoint` of 700 is a window of 960 on one Screen and 992 on
  /// another. The number here is the window, found by pumping one and checking
  /// which side of the edge it fell on; each test file says how it was measured.
  final double tableFromWindow;

  /// The control a reader must still be able to reach at a text scale of 2.
  final Key Function(String id) primaryKey;

  /// The index of the end-aligned number column, where the register has one.
  final int? numericColumn;

  /// Whether the fixture's numbers in [numericColumn] have different digit
  /// counts — the discriminator that a shared right edge means right alignment
  /// rather than equal widths. A 1–5 priority is always one digit, so that
  /// register sets this false and its column is carried by the label's own edge.
  final bool numericDigitsVary;
}

Future<void> pumpAt(
  WidgetTester tester,
  RegisterSpec spec, {
  required double width,
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, 1000);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  await pumpApp(
    tester,
    gateway: FakeAuthGateway(accessToken: 'a-token'),
    client: spec.wire().client,
    initialLocation: spec.location,
  );
}

Finder cellIn(Key rowKey, int index) => find.descendant(
      of: find.byKey(rowKey),
      matching: find.byKey(AppTableRow.cellKey(index)),
    );

/// Registers the measurements every register owes.
void registerGeometryTests(RegisterSpec spec) {
  final name = spec.name;

  testWidgets('$name: at 1280 the band is ${AppTableHeader.height.toInt()} and each row is its '
      'stated height', (tester) async {
    await pumpAt(tester, spec, width: 1280);

    expect(find.byType(AppTableHeader), findsOneWidget);
    expect(tester.getSize(find.byType(AppTableHeader)).height, AppTableHeader.height);
    for (final id in spec.ids) {
      expect(tester.getSize(find.byKey(spec.rowKey(id))).height, spec.rowHeights[id],
          reason: '$name row $id');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('$name: at 1280 every band label meets its cell, on every row', (tester) async {
    await pumpAt(tester, spec, width: 1280);

    // A start-aligned column's label and cell share a LEFT edge; an end-aligned
    // one's share a RIGHT edge, because that is the edge the alignment makes
    // meaningful. Both are the one column spec building band and rows.
    for (var i = 0; i < spec.columns.length; i++) {
      final (label, end) = spec.columns[i];
      final labelBox = find.byKey(AppTableHeader.labelKey(label));
      expect(labelBox, findsOneWidget, reason: '$name band label "$label"');
      for (final id in spec.ids) {
        final cell = cellIn(spec.rowKey(id), i);
        expect(cell, findsOneWidget, reason: '$name row $id cell $i');
        final labelEdge =
            end ? tester.getBottomRight(labelBox).dx : tester.getTopLeft(labelBox).dx;
        final cellEdge = end ? tester.getBottomRight(cell).dx : tester.getTopLeft(cell).dx;
        expect((labelEdge - cellEdge).abs(), lessThanOrEqualTo(1.0),
            reason: '$name "$label" label and the cell of row $id, ${end ? 'right' : 'left'} edge');
      }
    }
    expect(tester.takeException(), isNull);
  });

  final numeric = spec.numericColumn;
  if (numeric != null) {
    testWidgets('$name: at 1280 the "${spec.columns[numeric].$1}" cells share one right edge and '
        'set their digits in tabular figures', (tester) async {
      await pumpAt(tester, spec, width: 1280);

      final edges = <double>[];
      final texts = <String>[];
      for (final id in spec.ids) {
        final text = find
            .descendant(of: cellIn(spec.rowKey(id), numeric), matching: find.byType(Text))
            .first;
        edges.add(tester.getBottomRight(text).dx);
        final widget = tester.widget<Text>(text);
        texts.add(widget.data ?? widget.textSpan!.toPlainText());
        expect(widget.style?.fontFeatures, contains(const FontFeature.tabularFigures()),
            reason: '$name row $id: tabular figures');
      }
      if (spec.numericDigitsVary) {
        expect(texts.map((t) => t.length).toSet().length, greaterThan(1),
            reason: "the fixture's numbers have different digit counts, so a shared right edge "
                'is alignment rather than equal width: $texts');
      }
      for (final edge in edges) {
        expect(edge, edges.first, reason: 'one right edge across $texts');
      }
    });
  }

  testWidgets('$name: at 700 it is cards, each at its measured height', (tester) async {
    await pumpAt(tester, spec, width: 700);

    expect(find.byType(AppTableHeader), findsNothing);
    for (final id in spec.ids) {
      final card = find.byKey(spec.rowKey(id));
      expect(card, findsOneWidget, reason: '$name row key $id still resolves');
      expect(tester.getSize(card).height, spec.cardHeights[id], reason: '$name card $id');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('$name: at a text scale of 2, at 1280 and at 700, nothing overflows and the first '
      "row's control is still reachable", (tester) async {
    for (final width in [1280.0, 700.0]) {
      await pumpAt(tester, spec, width: width, textScale: 2);
      expect(tester.takeException(), isNull, reason: '$name at $width x2');
      final control = find.byKey(spec.primaryKey(spec.ids.first));
      expect(control, findsOneWidget, reason: '$name control at $width x2');
      // A card at twice the text is often taller than the viewport, so the
      // control is reached by scrolling — that is the reader's own way to it,
      // and "still there" means it can be reached and hit, not that it happens
      // to be above the fold.
      await tester.ensureVisible(control);
      await tester.pumpAndSettle();
      expect(control.hitTestable(), findsOneWidget, reason: '$name control hittable at $width x2');
    }
  });

  testWidgets('$name: the window of ${spec.tableFromWindow.toInt()} is the edge between cards and '
      'the table, and the table does not overflow there', (tester) async {
    final edge = spec.tableFromWindow;
    await pumpAt(tester, spec, width: edge - 1);
    expect(find.byType(AppTableHeader), findsNothing, reason: '$name: a window of ${edge - 1}');
    expect(find.byKey(spec.rowKey(spec.ids.first)), findsOneWidget);
    expect(tester.takeException(), isNull);

    await pumpAt(tester, spec, width: edge);
    expect(find.byType(AppTableHeader), findsOneWidget, reason: '$name: a window of $edge');
    expect(tester.takeException(), isNull, reason: '$name: the fixed columns fit at $edge');
  });

  testWidgets('$name: the same window at a text scale of 2 is cards, because the edge doubles',
      (tester) async {
    await pumpAt(tester, spec, width: spec.tableFromWindow, textScale: 2);
    expect(find.byType(AppTableHeader), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
