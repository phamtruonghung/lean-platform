/// The KPI catalogue's top edge: its filled band as `AppListCard`'s first row.
///
/// Since #395 the catalogue's column labels sit on `tableHeaderFill`, and that
/// band is the first row *inside* the catalogue's `AppListCard`
/// (`kpi_catalogue_screen.dart`), so its fill is the card's own top edge. The
/// card's shape is a 14px `AppRadius.card` round rectangle; a `Card` left at
/// `Material`'s `Clip.none` default paints its child outside that rectangle,
/// and the band's square top corners then show as two nubs of `tableHeaderFill`
/// on the canvas beside the card's rounded corners — `#334155` on `#0F172A` in
/// the dark palette, which is where it is plainest (issue #461).
///
/// **Why a golden.** Nothing in the widget tree records this: the band's own
/// rectangle is the card's full width either way, and the card's `shape`
/// carries the radius whether or not anything is clipped to it. Only pixels
/// can tell a clipped card from an unclipped one, so these two goldens are the
/// whole of the assertion — the card and its band at the width the catalogue
/// gives it in a 1280px window (`868`, the 900px page less its 16px gutters)
/// and in a 700px one (`668`), dark palette.
///
/// Mounted like `app_stat_tile_test.dart`: a small `MaterialApp` with the app's
/// own theme and no `FakeWire`, because the subject makes no request and owns
/// no navigation. `AppListCard` is a shared layout primitive (#189), so this
/// does not reopen `test/GOLDENS.md`'s "no golden per Screen" scope: it goldens
/// the primitive as the catalogue composes it, not the Screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/kpi/kpi_catalogue_screen.dart';
import 'package:lean_platform/kpi/kpi_matrix.dart';
import 'package:lean_platform/theme.dart';
import 'package:lean_platform/widgets/app_list_card.dart';

import 'harness.dart';

const _goldenKey = ValueKey<String>('test-kpi-catalogue-band-golden');

/// The catalogue's own columns, mirrored from `kpi_catalogue_screen.dart`'s
/// private `_columns` (same labels, same flexes): the band's real contents, so
/// the narrow golden also holds the wrap the `Direction` label takes there.
const List<MatrixColumn> _columns = [
  MatrixColumn(flex: 4, label: 'KPI', headerKey: ValueKey<String>('band-kpi')),
  MatrixColumn(flex: 1, label: 'Unit', headerKey: ValueKey<String>('band-unit')),
  MatrixColumn(flex: 2, label: 'Direction', headerKey: ValueKey<String>('band-direction')),
  MatrixColumn(flex: 2, label: 'Daily', headerKey: ValueKey<String>('band-daily')),
  MatrixColumn(flex: 2, label: 'Weekly', headerKey: ValueKey<String>('band-weekly')),
  MatrixColumn(flex: 2, label: 'Monthly', headerKey: ValueKey<String>('band-monthly')),
  MatrixColumn(flex: 2, label: 'Today', headerKey: ValueKey<String>('band-today')),
];

/// One body row, in the shape `_KpiRowTile` draws: the same padding, the same
/// cell weights, so the hairline under the band sits where it does on `/kpi`.
final Widget _bodyRow = Padding(
  padding: matrixRowPadding,
  child: Row(
    children: [
      matrixCell(flex: 4, child: Text('OEE')),
      matrixCell(flex: 1, child: Text('%')),
      matrixCell(flex: 2, child: Text('≥')),
      matrixCell(flex: 2, child: Text('85.0')),
      matrixCell(flex: 2, child: Text('82.5')),
      matrixCell(flex: 2, child: Text('80.0')),
      matrixCell(flex: 2, child: Text('Met')),
    ],
  ),
);

Future<void> _pump(WidgetTester tester, {required double cardWidth}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(cardWidth + 160, 220);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(Brightness.dark),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: Builder(
            builder: (context) => RepaintBoundary(
              key: _goldenKey,
              // The canvas the catalogue's card sits on, painted *inside* the
              // boundary: the corner the band would paint over is only
              // readable as a corner against the colour a reader sees.
              child: ColoredBox(
                color: AppColors.of(context).canvas,
                child: Padding(
                  // Canvas around the card on all four sides: the corner the
                  // fill would paint over is what the 24px of it is there to
                  // show.
                  padding: const EdgeInsets.all(Spacing.xl),
                  child: SizedBox(
                    width: cardWidth,
                    child: AppListCard(
                      rows: [
                        const MatrixHeaderRow(
                          key: KpiCatalogueScreen.headerRowKey,
                          columns: _columns,
                        ),
                        _bodyRow,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('the band is the card\'s top edge, full width, in both goldens', (tester) async {
    for (final cardWidth in [868.0, 668.0]) {
      await _pump(tester, cardWidth: cardWidth);
      final card = tester.getRect(find.byType(Card));
      final band = tester.getRect(find.byType(MatrixHeaderRow));
      expect(band.width, card.width, reason: 'the band spans the card at $cardWidth');
      expect(band.left, card.left, reason: 'the band starts at the card\'s left edge');
      expect(band.top, card.top, reason: 'the band is the card\'s top edge');
      expect(card.width, cardWidth);
    }
  });

  testWidgets('the band at a 1280px window follows the card\'s rounded corners', (tester) async {
    await _pump(tester, cardWidth: 868);
    await expectLater(
      find.byKey(_goldenKey),
      matchesGoldenFile('goldens/kpi_catalogue_band_wide_dark.png'),
    );
  });

  testWidgets('the band at a 700px window follows the card\'s rounded corners', (tester) async {
    await _pump(tester, cardWidth: 668);
    await expectLater(
      find.byKey(_goldenKey),
      matchesGoldenFile('goldens/kpi_catalogue_band_narrow_dark.png'),
    );
  });
}
