/// A register's name cell: the record's name with its status chip beside it, and
/// under it when there is not room for both.
///
/// **Why it exists.** An `Inactive` or `Retired` chip is a fixed width and the
/// name is not, and a register column is a share of the box. Where the share is
/// narrower than the chip plus a name worth reading, a `Row` of the two overflows;
/// clipping the chip hides the very fact it states. So when the cell cannot hold
/// the chip and [minNameWidth] of name side by side, the chip drops under the
/// name instead. That only ever makes the one row taller; nothing is clipped and
/// nothing is lost.
///
/// The chip's width is measured, not guessed: its label in the chip's own label
/// style at the reader's text scale, plus the chip's padding. It is presentation
/// only and imports no Bloc.
library;

import 'package:flutter/material.dart';

import '../theme.dart';

class NameWithChip extends StatelessWidget {
  const NameWithChip({super.key, required this.name, this.chip, this.chipLabel = ''});

  /// The name, which may ellipsize: a `DisclosingText`, or a column of one.
  final Widget name;

  /// The status chip, or null when the record has none to show.
  final Widget? chip;

  /// The chip's label, used only to measure it.
  final String chipLabel;

  /// The least width of name worth drawing beside the chip.
  static const double minNameWidth = AppTouchTarget.min * 2;

  @override
  Widget build(BuildContext context) {
    final chip = this.chip;
    if (chip == null) return name;
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: chipLabel, style: Theme.of(context).textTheme.labelLarge),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        // The chip's own horizontal padding and label padding (`Spacing.xxl`).
        final chipWidth = painter.width + Spacing.xxl;
        final fits = constraints.maxWidth >= chipWidth + Spacing.sm + minNameWidth;
        if (fits) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: name),
              const SizedBox(width: Spacing.sm),
              chip,
            ],
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            name,
            const SizedBox(height: Spacing.xs),
            chip,
          ],
        );
      },
    );
  }
}
