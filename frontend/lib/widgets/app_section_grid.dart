/// A detail page's sections: one column, or two from
/// [AppBreakpoints.detailTwoColumn] (1000) of box width.
///
/// **Why 1000 and not 900.** Two sections of a readable measure plus a 12px
/// gutter need more than the page's own 900, so a page that spends this at two
/// columns must name a wider frame than the default; the Work orders register
/// and the CAPA report already do. The number is the box a `LayoutBuilder` hands
/// this widget, scaled by the reader's text size ([AppBreakpoints.effective]),
/// never the window: a section squeezed to half of a narrow box is worse than the
/// same section stacked, and at 200% text the same box is half as wide as it
/// looks.
///
/// **`Expanded` rows, not a `Wrap`.** A `Wrap` never stretches a partly filled
/// run, so with an odd number of sections the last one sits at its natural width
/// and the right-hand edge goes ragged: the trap `docs/frontend-layout.md`
/// records. Each row here is a `Row` of `Expanded` children, so a lone last
/// section is the section itself, at full width.
///
/// **The two sections in a row share a height.** The row is an `IntrinsicHeight`
/// with a stretching cross axis, so a section whose text wraps does not leave its
/// neighbour a short card floating beside it. `IntrinsicHeight` is affordable
/// here for the reason `home_screen.dart`'s `_CardRow` gives: at most two
/// children, and a detail page is short. It would not be affordable on a long
/// list, which is why this widget is for sections and not for rows.
///
/// **It owns no padding and no scrolling.** Rows are `Spacing.md` apart and the
/// gutter is `Spacing.md`, the same twelve a Screen leaves between one card and
/// the next.
library;

import 'package:flutter/material.dart';

import '../theme.dart';

class AppSectionGrid extends StatelessWidget {
  const AppSectionGrid({super.key, required this.sections});

  final List<Widget> sections;

  /// How many sections share a row when the box is wide enough.
  static const int wideColumns = 2;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide =
            constraints.maxWidth >= AppBreakpoints.effective(context, AppBreakpoints.detailTwoColumn);
        final perRow = wide ? wideColumns : 1;
        final rows = <List<Widget>>[
          for (var start = 0; start < sections.length; start += perRow)
            sections.sublist(start, start + perRow > sections.length ? sections.length : start + perRow),
        ];
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var r = 0; r < rows.length; r++) ...[
              if (r > 0) const SizedBox(height: Spacing.md),
              if (rows[r].length == 1)
                rows[r].single
              else
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < rows[r].length; i++) ...[
                        if (i > 0) const SizedBox(width: Spacing.md),
                        Expanded(child: rows[r][i]),
                      ],
                    ],
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}
