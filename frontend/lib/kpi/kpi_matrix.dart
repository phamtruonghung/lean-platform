/// The matrix chrome and the one matching rule the two KPI Screens share
/// (issue #363): `/kpi` and `/kpi/review` are both a header row over aligned
/// body rows inside an `AppListCard`, narrowed by an `AppFilterField`.
///
/// They live in one file so the two Screens cannot drift: the same row padding,
/// the same header label style, the same cell gap, and one search rule. A
/// Screen declares its columns once, as [MatrixColumn]s, and builds both its
/// header ([MatrixHeaderRow]) and each body row's cells ([matrixCell]) from
/// those, so a header label and its cells start at the same x by construction.
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
class MatrixHeaderRow extends StatelessWidget {
  const MatrixHeaderRow({super.key, required this.columns});

  final List<MatrixColumn> columns;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600);
    return Padding(
      padding: matrixRowPadding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final column in columns)
            matrixCell(flex: column.flex, key: column.headerKey, child: Text(column.label, style: style)),
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
