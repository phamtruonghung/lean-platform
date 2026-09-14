import 'package:flutter/material.dart';

import '../status_tone.dart';
import '../theme.dart';

/// A status, painted with the meaning it carries (issue #168).
///
/// Every list surface in the Platform used to render a status as a plain
/// Material `Chip` at that `Chip`'s own default greys, so "Approved" and
/// "On hold" — the two states somebody scanning a maintenance list most needs
/// to tell apart — were painted identically. This widget is that same `Chip`
/// with its fill and label colour resolved from a [StatusTone].
///
/// Deliberately thin. It keeps `visualDensity: VisualDensity.compact` and the
/// `labelLarge` label style the call sites already had — the wide Work orders
/// table measures its own Status column from `labelLarge`
/// (`_statusColumnWidth`), so a different label style here would silently
/// clip the longest status again, which is the bug issue #105 fixed — and it
/// adds no interaction, no state and no knowledge of any Bloc. All it adds is
/// colour.
///
/// **The label is always rendered.** Colour groups a status; it never carries
/// one on its own. That is the design skill's own "don't convey information by
/// colour alone" rule, and it is why a reader who cannot tell the five tints
/// apart — or who is reading a monochrome printout — loses nothing: the word is
/// right there in the chip.
///
/// The border Material draws around a `Chip` by default is dropped: against a
/// tinted fill its own cool grey outline reads as a second, competing edge.
/// The fill alone is enough of a shape.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, required this.tone});

  /// The status in the domain's own words — `WorkOrder.statusLabel`,
  /// `Request.statusLabel` and their neighbours.
  final String label;

  /// What that status means; see [StatusTone].
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label),
      visualDensity: VisualDensity.compact,
      backgroundColor: AppComponentColors.statusFill(tone),
      labelStyle: Theme.of(context)
          .textTheme
          .labelLarge
          ?.copyWith(color: AppComponentColors.statusForeground(tone)),
      side: BorderSide.none,
    );
  }
}
