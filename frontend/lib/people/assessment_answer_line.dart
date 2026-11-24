/// One of the three Options, or the Other row, as the Marker and the result read
/// it (issue #588, ADR-0068, slice 4): the key carries a tick, the candidate's
/// pick carries a filled dot. The two are independent, because a correct answer
/// can be one and a wrong answer can be the other.
///
/// Shared by the marking Screen and the result Screen so the paper reads the same
/// on both; it adds no colour or radius of its own (docs/design-language.md).
library;

import 'package:flutter/material.dart';

import '../status_tone.dart';
import '../theme.dart';

class AssessmentAnswerLine extends StatelessWidget {
  const AssessmentAnswerLine({
    super.key,
    required this.letter,
    required this.text,
    required this.chosen,
    required this.keyed,
  });

  /// `A`, `B` or `C`; null for the Other row.
  final String? letter;
  final String text;
  final bool chosen;
  final bool keyed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppColors.of(context);
    final colour = chosen ? theme.colorScheme.primary : palette.textMuted;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            chosen ? Icons.radio_button_checked : Icons.radio_button_unchecked,
            size: 18,
            color: colour,
          ),
          const SizedBox(width: Spacing.sm),
          if (letter != null) ...[
            Text('$letter.', style: theme.textTheme.bodyMedium?.copyWith(color: colour)),
            const SizedBox(width: Spacing.xs),
          ],
          Expanded(
            child: Text(text, style: theme.textTheme.bodyMedium?.copyWith(color: colour)),
          ),
          if (keyed)
            Icon(
              Icons.check_circle_outline,
              size: 18,
              color: palette.statusForeground(StatusTone.success),
            ),
        ],
      ),
    );
  }
}
