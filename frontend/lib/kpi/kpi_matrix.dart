/// The catalogue's matrix chrome, and the one matching rule both KPI Screens
/// share (issue #363, narrowed by #365).
///
/// The chrome is `/kpi`'s alone: [MatrixColumn], [MatrixHeaderRow],
/// [matrixCell] and the padding and gap they share build that Screen a header
/// row over aligned body rows inside an `AppListCard`. A Screen declares its
/// columns once and builds both its header and each body row's cells from
/// those, so a header label and its cells start at the same x by construction.
/// It lives here, belonging to no Screen in particular, so the chrome cannot
/// drift from itself: one row padding, one header label style, one cell gap.
///
/// What both Screens share is the rule, not the chrome. `/kpi` and
/// `/kpi/review` narrow the same way — [kpiMatchesSearch] over
/// [foldForSearch]'s diacritic-free forms, the catalogue matching on code or
/// title and the review on its title alone — and the review takes that rule
/// and nothing else from this file: since #365 it is a tiled grid of
/// equal-width cards (`_ReviewGrid` in `kpi_review_screen.dart`), with no
/// header row, columns or cells of the matrix kind. The rule lives here so two
/// copies of it cannot drift apart.
library;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Horizontal padding of every row of the matrix, header and body alike.
const double matrixRowHorizontalPadding = Spacing.md;

/// Vertical padding of every row of the matrix, header and body alike.
const double matrixRowVerticalPadding = Spacing.sm;

/// The padding of a matrix row — one value, so no Screen invents its own.
const EdgeInsets matrixRowPadding = EdgeInsets.symmetric(
  horizontal: matrixRowHorizontalPadding,
  vertical: matrixRowVerticalPadding,
);

/// The gap kept to the right of every cell, so adjacent columns never touch.
const double matrixCellGap = Spacing.sm;

/// One column: its weight, its label and the `Key` of its header cell.
class MatrixColumn {
  const MatrixColumn({required this.flex, required this.label, required this.headerKey});

  final int flex;
  final String label;
  final Key headerKey;
}

/// A body cell of [column]: the same `Expanded` weight and gap as its header.
Widget matrixCell({required int flex, required Widget child, Key? key}) =>
    Expanded(
      key: key,
      flex: flex,
      child: Padding(padding: const EdgeInsets.only(right: matrixCellGap), child: child),
    );

/// The header row: one `Expanded` cell per column, labelled in the shared style.
///
/// **It is a band, not a row (issue #395).** It used to be a row of labels in
/// the same weight and nearly the same colour as the cells beneath it, so the
/// catalogue read as a table whose first line happened to be words. It now
/// spends the two things `AppTableHeader` spends for the same reason — a fill
/// (`tableHeaderFill`) and a weight (w600, in `textMuted`, the pair that
/// measures 6.50:1 on the band in the light palette and 6.97:1 in dark) — so the
/// KPI catalogue and every maintenance register have one band, not two. It
/// draws no bottom rule of its own: `AppListCard` already puts a hairline
/// between this row and the first body row, and a second one would read as a
/// 2px line.
///
/// Each label is a header to a screen reader, which the plain row it replaced
/// was not.
class MatrixHeaderRow extends StatelessWidget {
  const MatrixHeaderRow({super.key, required this.columns});

  final List<MatrixColumn> columns;

  /// The band's own minimum height — the same 32 a register's band holds, so a
  /// catalogue and a register start their first row at the same y.
  static const double bandHeight = 32;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
          color: palette.textMuted,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        );
    return Container(
      constraints: const BoxConstraints(minHeight: bandHeight),
      decoration: BoxDecoration(color: palette.tableHeaderFill),
      padding: matrixRowPadding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (final column in columns)
            matrixCell(
              flex: column.flex,
              key: column.headerKey,
              child: Semantics(header: true, child: Text(column.label, style: style)),
            ),
        ],
      ),
    );
  }
}

/// Folded forms of the vowels Vietnamese (and Latin) text carries marks on,
/// keyed by the base letter they fold to. Lower case only: [foldForSearch]
/// lower-cases first.
const Map<String, String> _foldGroups = {
  'a': 'àáảãạăằắẳẵặâầấẩẫậäåāą',
  'e': 'èéẻẽẹêềếểễệëēęě',
  'i': 'ìíỉĩịïīî',
  'o': 'òóỏõọôồốổỗộơờớởỡợöøōő',
  'u': 'ùúủũụưừứửữựüūůű',
  'y': 'ỳýỷỹỵÿ',
  'd': 'đ',
};

final Map<String, String> _foldMap = {
  for (final MapEntry(key: base, value: marked) in _foldGroups.entries)
    for (final char in marked.split('')) char: base,
};

/// Lower-cases and folds Vietnamese/Latin diacritics, so `hieu suat` finds
/// `Hiệu suất`. Combining marks (U+0300–U+036F, as decomposed text carries
/// them) are dropped too.
String foldForSearch(String value) {
  final buffer = StringBuffer();
  for (final rune in value.toLowerCase().runes) {
    if (rune >= 0x0300 && rune <= 0x036F) continue;
    final char = String.fromCharCode(rune);
    buffer.write(_foldMap[char] ?? char);
  }
  return buffer.toString();
}

/// Whether a KPI matches [term] by its code or its title, both folded: a
/// case- and diacritic-insensitive substring. The term is trimmed; an empty
/// term matches everything. A caller with no code passes `''`.
bool kpiMatchesSearch({required String code, required String title, required String term}) {
  final folded = foldForSearch(term.trim());
  if (folded.isEmpty) return true;
  return foldForSearch(code).contains(folded) || foldForSearch(title).contains(folded);
}
