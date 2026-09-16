/// The box a Screen's content is laid out in (issue #193).
///
/// **Why it exists.** A `Center` around a `ConstrainedBox` sizes itself to its
/// child, and a `Column` of `Text`s sizes itself to its longest line. Put the
/// two together and a page whose content is a title, a description and a row of
/// buttons — nothing that wants to be wide — shrink-wraps to the width of its
/// own longest sentence and then floats to the middle of the window: measured,
/// `/stores`' title and description started 142px right of the card beneath
/// them, and `/approval-queue`'s 106px. The two are the same defect, and which
/// pages showed it depended on whether their content happened to contain
/// something that forces a width (a table, a `ListView`, an input) — so it read
/// as "some pages look wrong" rather than as one bug.
///
/// `SizedBox(width: double.infinity)` inside the constraint is the whole fix:
/// the box is the page's width (or [maxWidth], whichever is smaller) whatever
/// the child would have preferred, so a title, a description, a row of buttons
/// and the list below them all start at the same left edge.
///
/// **It stays inside the caller's own `Center`.** Every Screen already writes
/// `Center(child: ConstrainedBox(constraints: BoxConstraints(maxWidth: X), …))`,
/// so this replaces only the `ConstrainedBox` — the `Center` still does the one
/// thing it is good for here (centring a 900px page in a wider window), and no
/// call site had to have its parens rearranged to adopt this.
///
/// **Not every constrained box is a page.** The shared states — `EmptyState`,
/// `FailureState`, and the sign-in and awaiting-Approval cards at 400–460px —
/// are centred blocks on purpose and keep their own `ConstrainedBox`; a state
/// card that stretched to the page width would be a wrecked layout, not a fixed
/// one.
library;

import 'package:flutter/material.dart';

import '../theme.dart';

class AppPageFrame extends StatelessWidget {
  const AppPageFrame({
    super.key,
    required this.child,
    this.maxWidth = AppLayout.pageWidth,
  });

  final Widget child;

  /// The widest this page's content may be. Defaults to the Platform's own page
  /// width; a Screen that lays out a wide table or a board passes its own, and
  /// a Screen that names one keeps its own constant
  /// (`static const double maxWidth = AppLayout.pageWidth`).
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      // The line that stops a page drifting to the middle: a child that would
      // rather be narrow gets the page's width anyway.
      child: SizedBox(width: double.infinity, child: child),
    );
  }
}
