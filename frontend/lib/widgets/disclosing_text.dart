import 'package:flutter/material.dart';

/// Text that says what it had to clip (issue #168).
///
/// A table cell that ellipsizes its value ("Press 1 (PRESS-…") leaves the
/// reader guessing, and a hover-only tooltip would be an affordance a pointer
/// has and a keyboard does not. This wraps a value in a Material `Tooltip`,
/// which on the pinned Flutter 3.44.0 is reachable three ways — measured
/// against `RawTooltip`'s own source rather than assumed:
///
/// - **hover**, for anyone with a pointer;
/// - **long press**, for a touch screen;
/// - **announced**, because `Tooltip`'s own semantics label carries the full
///   value to assistive technology (`excludeFromSemantics` stays at its
///   default `false` here).
///
/// **What it is not**: a keyboard-focus trigger. `RawTooltip` on 3.44.0 has no
/// focus handler at all (it registers a mouse `MouseRegion` and long-press/tap
/// recognisers and nothing else), so claiming this discloses on focus would be
/// claiming something the framework does not do. A sighted keyboard user
/// reaches the full value the same way they reach anything else on the row:
/// the row itself is a link to the Work order's own detail, whose header
/// states every field in full. The columns around this widget are also sized
/// so that clipping is the exception rather than the everyday path — see
/// `_WorkOrdersList`'s own column split.
///
/// The value is always rendered in full *as text* under the tooltip too — the
/// tooltip discloses the clipped rendering, it never replaces the value.
class DisclosingText extends StatelessWidget {
  const DisclosingText(this.value, {super.key, this.style});

  /// The whole value, clipped on screen and disclosed in full by the tooltip.
  final String value;

  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: value,
      // Long enough that a pointer crossing a table does not flash a tooltip
      // at every column, short enough that stopping on a cell feels answered.
      waitDuration: const Duration(milliseconds: 500),
      child: Text(
        value,
        style: style,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
