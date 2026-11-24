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
/// by shrinking a tap target. A row whose own `onTap` is set is 44 — that is the
/// floor this widget applies, and a row that holds a control is given one, so the
/// control is never the only thing to press. Content is centred, which is what
/// yields the board's 6px above and below a 20px line without a 6 on the
/// [Spacing] ladder.
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
import 'app_focus_ring.dart';

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
    this.minWidth,
  });

  final String label;
  final int flex;
  final double? width;
  final AppColumnAlign align;

  /// A flex column's floor, measured by the caller from a translated label (the
  /// header's own, or the longest word a cell prints), **including** the slot's
  /// `Spacing.sm` right gutter. While the column's flex share is at or above it
  /// nothing changes; when the share would fall below it the column is pinned to
  /// this width and the rest is shared among the remaining flex columns. Null
  /// (the default) is a plain flex column. Ignored when [width] is set.
  final double? minWidth;
}

/// The widths of the slots of [columns] in a row [maxWidth] wide, as the
/// columns to lay out: [columns] itself, untouched, unless some flex column's
/// [AppTableColumn.minWidth] would not fit its share (`Flex`'s own arithmetic:
/// room left after the fixed widths, times flex over the flex total). Then each
/// column whose floor binds becomes a fixed one, and the share is recomputed
/// among the rest until nothing more binds. The band and every row call this
/// with the same width, so their slots agree.
List<AppTableColumn> _resolve(List<AppTableColumn> columns, double maxWidth) {
  if (!maxWidth.isFinite || columns.every((c) => c.minWidth == null || c.width != null)) {
    return columns;
  }
  var fixed = 0.0;
  for (final c in columns) {
    fixed += c.width ?? 0;
  }
  final pinned = <int>{};
  var changed = true;
  while (changed) {
    changed = false;
    var room = maxWidth - fixed;
    var totalFlex = 0;
    for (var i = 0; i < columns.length; i++) {
      if (columns[i].width != null) continue;
      if (pinned.contains(i)) {
        room -= columns[i].minWidth!;
      } else {
        totalFlex += columns[i].flex;
      }
    }
    if (totalFlex == 0) break;
    for (var i = 0; i < columns.length; i++) {
      final c = columns[i];
      if (c.width != null || pinned.contains(i) || c.minWidth == null) continue;
      if (room * c.flex / totalFlex < c.minWidth!) {
        pinned.add(i);
        changed = true;
      }
    }
  }
  if (pinned.isEmpty) return columns;
  return [
    for (var i = 0; i < columns.length; i++)
      pinned.contains(i)
          ? AppTableColumn(
              columns[i].label,
              width: columns[i].minWidth,
              align: columns[i].align,
            )
          : columns[i],
  ];
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

  /// The band's label style, less its colour — what a caller measures a floor
  /// ([AppTableColumn.minWidth]) in.
  static TextStyle? labelStyle(BuildContext context) =>
      Theme.of(context).textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          );

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final style = labelStyle(context)?.copyWith(color: palette.textMuted);
    return Container(
      constraints: const BoxConstraints(minHeight: height),
      padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.xs),
      decoration: BoxDecoration(
        color: palette.tableHeaderFill,
        border: Border(bottom: BorderSide(color: palette.edge)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final resolved = _resolve(columns, constraints.maxWidth);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (final column in resolved)
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
          );
        },
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final resolved = _resolve(columns, constraints.maxWidth);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (var i = 0; i < resolved.length; i++)
                _slot(resolved[i], KeyedSubtree(key: cellKey(i), child: cells[i])),
            ],
          );
        },
      ),
    );
    if (onTap != null) {
      // A row that opens a record is a keyboard stop (issue #401): an `InkWell`
      // is focusable and `Enter`/`Space` activate it, and [AppFocusRing] is what
      // makes the stop visible — the same 2px ring a Destination or a button
      // wears, traced over this row's own square bounds.
      content = AppFocusRing(
        child: InkWell(
          onTap: onTap,
          hoverColor: palette.rowHoverFill,
          splashFactory: NoSplash.splashFactory,
          child: content,
        ),
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
