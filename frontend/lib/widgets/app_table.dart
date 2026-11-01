/// The register's column-label band and its rows, built from one column spec.
///
/// **The band is not a row, and a row is not a header.** The Work orders table
/// used to set its labels in the same size and nearly the same colour as the
/// metadata beneath them, separated by one hairline, so the band read as a fifth
/// row of data. [AppTableHeader] therefore spends two things a row does not: a
/// fill (`tableHeaderFill`) and a weight (w600, in `textMuted`, a pair that
/// measures 6.50:1 on the band in the light palette and 6.97:1 in dark). It is
/// sentence case, never uppercased: uppercase is the Shell's Destination-group
/// device, and the labels are the domain's own words ("WO#", "Org Unit"). It has
/// no hover and no tap, and each label is a header to a screen reader.
///
/// **One column spec spends twice.** [AppTableHeader] and [AppTableRow] both
/// build every column from the same [AppTableColumn], through the same private
/// slot, so a label and its cells start at the same x by construction rather
/// than by two hand-kept lists of `flex` numbers agreeing. `kpi_test.dart`
/// already pins that for the two KPI Screens; this makes the next Screen unable
/// to get it wrong.
///
/// **A row is 32px when nobody can tap it and [AppTouchTarget.min] when
/// somebody can.** The reference board's `6px + line + 6px` is about 32, and the
/// Work orders row says 56; the whole distance between that board's density and
/// this Platform is paid here, on a row that holds nothing to press, and never
/// by shrinking a tap target. A row that is itself the target (`onTap`) or that
/// holds a control is 44. Content is centred, which is what yields the board's
/// 6px above and below a 20px line without a 6 on the [Spacing] ladder.
///
/// **Alignment is a property of the column kind, not a per-call choice.** A
/// quantity (a count, an amount of money) is [AppColumnAlign.end] so a column of
/// them can be compared by eye, and [numberStyle] gives its digits tabular
/// figures so they line up too. A name or a code is [AppColumnAlign.start]:
/// right-aligned words read badly left to right. The code column is `textMuted`
/// and the name column `textPrimary`, the reference board's own `.z`: the
/// identifier reads quieter than the thing it identifies. Those two colours are
/// the caller's, set on the cell it hands in.
///
/// **It draws no outside rim and adds no card.** It lives inside an
/// `AppListCard` or a `Card` the call site supplies, exactly as an
/// `AppListCard` row does; the only lines it draws are the hairline under the
/// band and under each row, in the palette's `edge`.
library;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Which edge a column's content sits against.
enum AppColumnAlign { start, end }

/// One column of a register: its label, and the width it asks for.
///
/// `flex` is spent only when `width` is null. A tone or action column states a
/// fixed `width` because its content is bounded; reach for `flex` otherwise, or
/// the column's edge will move with the window.
class AppTableColumn {
  const AppTableColumn(
    this.label, {
    this.flex = 1,
    this.width,
    this.align = AppColumnAlign.start,
  });

  final String label;
  final int flex;
  final double? width;
  final AppColumnAlign align;
}

/// The one place a column becomes a layout slot, so the band and the rows agree.
Widget _slot(AppTableColumn column, Widget child) {
  final aligned = Align(
    heightFactor: 1,
    alignment: column.align == AppColumnAlign.end ? Alignment.centerRight : Alignment.centerLeft,
    child: child,
  );
  final padded = Padding(padding: const EdgeInsets.only(right: Spacing.sm), child: aligned);
  final width = column.width;
  return width != null
      ? SizedBox(width: width, child: padded)
      : Expanded(flex: column.flex, child: padded);
}

/// The column-label band. See the library comment for why it is not a row.
class AppTableHeader extends StatelessWidget {
  const AppTableHeader({super.key, required this.columns});

  final List<AppTableColumn> columns;

  /// The band's minimum height.
  static const double height = 32;

  static ValueKey<String> labelKey(String label) => ValueKey<String>('app-table-header-$label');

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
          color: palette.textMuted,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        );
    return Container(
      constraints: const BoxConstraints(minHeight: height),
      padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.xs),
      decoration: BoxDecoration(
        color: palette.tableHeaderFill,
        border: Border(bottom: BorderSide(color: palette.edge)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (final column in columns)
            _slot(
              column,
              Semantics(
                header: true,
                child: Text(
                  column.label,
                  key: labelKey(column.label),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One record of a register. [cells] line up with [columns] one to one.
///
/// With an [onTap] the whole row, padding included, is the target and carries
/// the palette's `rowHoverFill`; without one it is a plain 32px row with no
/// hover, because a band that follows the pointer over something that does
/// nothing advertises a click that is not there.
class AppTableRow extends StatelessWidget {
  const AppTableRow({
    super.key,
    required this.columns,
    required this.cells,
    this.onTap,
  }) : assert(cells.length == columns.length, 'one cell per column');

  final List<AppTableColumn> columns;
  final List<Widget> cells;
  final VoidCallback? onTap;

  /// The height of a row nobody can tap.
  static const double height = 32;

  static ValueKey<String> cellKey(int index) => ValueKey<String>('app-table-cell-$index');

  /// The style for a quantity: `dense` with tabular figures, so the digits of a
  /// column of counts or amounts line up as well as their right edges.
  static TextStyle? numberStyle(BuildContext context) =>
      AppTypography.dense(context)?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    // The padding sits inside the InkWell, not around it, so the whole row is
    // the tap target and the 44px is a target the pointer can actually hit.
    Widget content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < columns.length; i++)
            _slot(columns[i], KeyedSubtree(key: cellKey(i), child: cells[i])),
        ],
      ),
    );
    if (onTap != null) {
      content = InkWell(
        onTap: onTap,
        hoverColor: palette.rowHoverFill,
        splashFactory: NoSplash.splashFactory,
        child: content,
      );
    }
    return Container(
      constraints: BoxConstraints(minHeight: onTap == null ? height : AppTouchTarget.min),
      // A foreground decoration, not a `decoration`: a border on `decoration`
      // pads the child by its own width and would leave the tap target 43px
      // inside a 44px row. The hairline is painted over the row, moving nothing.
      foregroundDecoration: BoxDecoration(border: Border(bottom: BorderSide(color: palette.edge))),
      child: content,
    );
  }
}
