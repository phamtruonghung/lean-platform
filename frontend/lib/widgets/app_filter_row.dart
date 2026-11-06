/// The row a Screen's narrowing controls sit in: one height, one set of gaps.
///
/// **Why it exists.** A filter row mixes three kinds of control —
/// `DropdownButtonFormField`, `AppFilterField`, and a button that opens a
/// picker (`OutlinedButton.icon`, `TextButton`) — and they do not agree on a
/// height. Material lays a `ButtonStyleButton` out at 48 whatever the reader's
/// text size, and a *labelled* outline field reserves a line for its floating
/// label on top of that same target, so the field renders 56 tall beside a
/// 48-tall button at a text scale of 1 (measured on the pinned SDK; see
/// [controlHeight]). Centred in a `Wrap`, the field is the taller box and the
/// buttons sit low against it — which is exactly the defect the owner reported
/// on `/actions`: "the drop box is always higher than the others".
///
/// **One height, measured, and it is the field's.** [controlHeight] is the
/// height of a labelled outline field at `isDense: true`, which is the tallest
/// control a filter row carries: 56 at a text scale of 1, and 24 logical pixels
/// more for every 1.0 of text scale on top of that (Material's content line
/// grows with the text, its label line and border do not). Every child is given
/// that as a **floor**, so no control is ever squeezed — a `Column` that carries
/// a caption keeps its caption — and the buttons are raised to meet the field
/// rather than the field being flattened to meet the buttons.
///
/// **Why not 44.** [AppTouchTarget.min] is the platform's tap floor, and it is
/// the *floor* here too (the theme sets it on every button and every input, see
/// `theme.dart`). It is not the row's height: measured, a labelled outline field
/// forced to 44 (or 48) holds its value text only by letting the floating label
/// overlap it once the text scale passes 1.5. A row levelled at 44 would trade
/// the owner's 8px misalignment for clipped filter values at 200% text, which
/// `test/palette_text_scale_sweep_test.dart` exists to refuse.
///
/// **A caption hangs below the row, not inside its control.** `AppFilterField`
/// draws its helper text and its "Showing 3 of 340" line *under* the box rather
/// than in the input's own `helperText` slot, so the control the row lines up is
/// the box. That is why the alignment is [WrapCrossAlignment.start]: controls
/// share one top edge, and a widget that carries a caption below its box stops
/// at the same line as its neighbours' boxes instead of being centred and
/// dropping its box by half the caption's height.
///
/// **It is a `Wrap`, so the row wraps.** Narrow, or at 200% text, the controls
/// flow onto a second line with the same gaps — nothing is dropped, truncated or
/// shrunk ([runSpacing] between lines). Screens do not pick their own gaps:
/// [Spacing.md] between controls and [Spacing.sm] between lines is the page
/// rhythm in `docs/design-language.md` §5.
///
/// **It is presentation only**: it lays out the widgets it is handed and decides
/// nothing about which filters exist or what they narrow.
library;

import 'package:flutter/material.dart';

import '../theme.dart';

class AppFilterRow extends StatelessWidget {
  const AppFilterRow({
    super.key,
    required this.children,
    this.spacing = Spacing.md,
    this.runSpacing = Spacing.sm,
  });

  /// The narrowing controls, in reading order: dropdowns, an `AppFilterField`,
  /// the buttons that open a picker. Each is laid out to at least
  /// [controlHeight].
  final List<Widget> children;

  /// The gap between two controls on one line.
  final double spacing;

  /// The gap between two lines of controls.
  final double runSpacing;

  /// The height every control in a filter row is laid out to — the height of a
  /// labelled outline field, `isDense: true`, at the reader's text size.
  ///
  /// **Measured, and pinned.** On the pinned SDK a labelled dense outline field
  /// renders 56 / 62 / 68 / 74 / 80 at text scales 1 / 1.25 / 1.5 / 1.75 / 2 —
  /// that is `32 + 24 × scale` — while a button stays at 48 until scale 2.5.
  /// `test/app_filter_row_test.dart` asserts the field's own rendered height is
  /// this number at five text scales, so a Material change that moves the
  /// metric fails a test that names it rather than quietly clipping a row.
  ///
  /// The 32 is the part of the metric the text scale does not move (the outline
  /// border plus the space Material reserves for the label's own line); the 24
  /// is the content line, which does. [AppLayout.atTextScale] clamps the factor
  /// at 1, so a reader who sets *smaller* text keeps the 56 rather than getting
  /// a control under the tap floor.
  static double controlHeight(BuildContext context) => 32 + AppLayout.atTextScale(context, 24);

  @override
  Widget build(BuildContext context) {
    final height = controlHeight(context);
    return Wrap(
      spacing: spacing,
      runSpacing: runSpacing,
      crossAxisAlignment: WrapCrossAlignment.start,
      children: [
        for (final child in children)
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: height),
            child: child,
          ),
      ],
    );
  }
}
