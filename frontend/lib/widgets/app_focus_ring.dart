/// `AppFocusRing`: the Platform's one visible keyboard-focus cue, drawn over a
/// control's own bounds from the `focusRing` token (issue #401).
///
/// Before this, three surfaces each drew their own ring — a `Card` whose
/// `shape` swapped ([AppStatTile]'s tile), a `Container` whose
/// `foregroundDecoration` carried a border (the KPI catalogue's row), and
/// everything else relying on `ThemeData.focusColor`'s 12% wash, which is a
/// tint rather than a ring and all but invisible on a pale surface. One rule
/// needs one widget: a keyboard reader is told where they are the same way on
/// every control, and a test asserts one shape instead of three.
///
/// **It costs no pixel of layout.** The ring is a foreground `DecoratedBox` —
/// no padding, no constraints — so it paints over the child's own edge and takes
/// no part in layout: the same reasoning `AppTableRow`'s hairline and the KPI
/// row already record.
///
/// **It is only worn by a keyboard.** `FocusHighlightMode.traditional` gates
/// it, exactly as `AppStatTile` and `buildAppTheme`'s own `focusedSide` do: a
/// pressed pointer leaves no ring behind on a surface that is now mouse-driven.
///
/// **It listens, it does not participate.** A `canRequestFocus: false`,
/// `skipTraversal: true` `Focus` reports whether anything inside it has focus
/// (`FocusNode.hasFocus` is true for an ancestor of the primary focus) without
/// becoming a tab stop of its own; the control inside keeps its focus node,
/// its `onTap` and its own 44px target exactly as it was.
///
/// Non-text contrast floor 3:1 — measured at 8.72:1 light and 8.11:1 dark on a
/// card, which `palette_contrast_test.dart` pins and `docs/design-language.md`
/// §9 tabulates.
library;

import 'package:flutter/material.dart';

import '../theme.dart';

class AppFocusRing extends StatefulWidget {
  const AppFocusRing({
    super.key,
    required this.child,
    this.borderRadius = BorderRadius.zero,
  });

  /// The control the ring is drawn around. Its own focus node is what the ring
  /// follows; nothing here re-parents or re-targets focus.
  final Widget child;

  /// The ring's corners. A row is square (`BorderRadius.zero`); a Destination
  /// or a card matches the radius of the surface it is drawn on, so the ring
  /// traces that surface rather than cutting its corners.
  final BorderRadius borderRadius;

  /// The ring's width, so a test measures the same 2 the token is drawn at
  /// ([AppFocusRing.isRing]).
  static const double ringWidth = 2;

  /// Whether [decoration] is this widget's ring, drawn in [focusRing].
  ///
  /// The one shape a test asserts. `AppFocusRing` is deliberately a silent
  /// widget — no key that appears and disappears, because a key that changes
  /// remounts the subtree under it and would lose the control's own state — so
  /// a test reads the painted decoration instead of hunting for a marker.
  static bool isRing(Decoration? decoration, Color focusRing) {
    if (decoration is! BoxDecoration) return false;
    final border = decoration.border;
    if (border is! Border) return false;
    return border.top.width == ringWidth &&
        border.top.color == focusRing &&
        border.right.color == focusRing &&
        border.bottom.color == focusRing &&
        border.left.color == focusRing;
  }

  @override
  State<AppFocusRing> createState() => _AppFocusRingState();
}

class _AppFocusRingState extends State<AppFocusRing> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final ringed =
        _focused &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) {
        if (focused != _focused) setState(() => _focused = focused);
      },
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        // **Always a decoration, never null.** A `Container` materialises its
        // foreground `DecoratedBox` only when the decoration is non-null, so
        // swapping `null` for the ring changes the widget at this slot from the
        // control to a `DecoratedBox` around it — which deactivates the control's
        // own element and, with it, the `FocusNode` the keyboard just landed on
        // (measured on the register's rows: the row node was disposed in the
        // same frame it gained focus, and `FocusManager` restored focus from its
        // history to the control before it). An empty `BoxDecoration` paints
        // nothing and keeps the slot's widget type stable, so gaining and losing
        // the ring never remounts the control inside it.
        decoration: ringed
            ? BoxDecoration(
                borderRadius: widget.borderRadius,
                border: Border.all(
                  color: palette.focusRing,
                  width: AppFocusRing.ringWidth,
                ),
              )
            : const BoxDecoration(),
        child: widget.child,
      ),
    );
  }
}
