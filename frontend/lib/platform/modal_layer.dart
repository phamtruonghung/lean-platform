/// The Shell's half of a modal's barrier.
///
/// A Screen is a route of the `ShellRoute`'s own navigator (ADR-0012), and every
/// popup over it — the raise form, a decision, a departure — is a route of that
/// *same* navigator. That is deliberate: it is what lets a dialog read the blocs
/// its Screen was built with (`LeaveRequestsBloc`, `ComplaintDetailBloc` and the
/// rest are created per area, inside the Shell), and ADR-0021's addressable
/// dialogs depend on it too.
///
/// The price is geometry. A `DialogRoute`'s `ModalBarrier` fills the navigator's
/// box, and the navigator's box is the *content* area — the sidebar column sits
/// beside it, not in it. So the dim stopped dead at the sidebar's edge and the
/// chrome stayed bright (and clickable) under an open dialog, which is what
/// "the popup does not cover the screen" looked like.
///
/// The alternative — presenting modals on the root navigator — would cover the
/// window and lose every route-scoped bloc above, because a route on the root
/// navigator is a child of `MaterialApp` and not of the Shell. So the Shell
/// keeps the modal where it is and **continues the barrier across its own
/// column**: [ModalLayer] is the one thing the Shell cannot see from where it
/// builds — which popup is on top — and [ModalScrim] is the barrier it paints
/// with it.
library;

import 'package:flutter/material.dart';

/// What the Shell needs to know about the popups presented over its Screens:
/// the topmost one, so the chrome outside the Screen's box can be shaded the
/// same way the Screen is.
///
/// Attached to the router's observers, so it hears every navigator go_router
/// builds — the root one and each `ShellRoute`'s inner one, which is where the
/// popups live.
///
/// **Only a route that shades anything counts.** A `PopupRoute` with no
/// `barrierColor` — a dropdown's menu, a popup menu, an autocomplete's list — is
/// a popup over a control, not a modal over a Screen, and the chrome must stay
/// available under it. `DialogRoute` and `ModalBottomSheetRoute` both carry one.
class ModalLayer extends NavigatorObserver {
  /// The topmost route whose barrier the Shell must continue, or null when the
  /// chrome is free.
  final ValueNotifier<ModalRoute<dynamic>?> top = ValueNotifier<ModalRoute<dynamic>?>(null);

  /// Every route currently shading the Screen, bottom first.
  final List<ModalRoute<dynamic>> _shaded = <ModalRoute<dynamic>>[];

  /// Whether a flush is already booked for the end of this frame.
  bool _flushScheduled = false;

  /// Whether [route] is a modal over a Screen rather than a menu over a
  /// control.
  static bool _shades(Route<dynamic> route) {
    if (route is! ModalRoute<dynamic> || route.opaque) return false;
    final Color? barrier = route.barrierColor;
    return barrier != null && barrier.a > 0;
  }

  /// Publishes the new top at the end of the frame rather than now: a
  /// `Navigator` announces a push from inside its own build (`didUpdateWidget`
  /// → `_updatePages`), and a listener marked dirty there is the "setState
  /// called during build" assertion. One frame later is invisible — the modal's
  /// own barrier is fading in over the same frame.
  void _publish() {
    if (_flushScheduled) return;
    _flushScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _flushScheduled = false;
      final ModalRoute<dynamic>? next = _shaded.isEmpty ? null : _shaded.last;
      if (!identical(top.value, next)) top.value = next;
    });
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (!_shades(route)) return;
    final ModalRoute<dynamic> modal = route as ModalRoute<dynamic>;
    if (_shaded.contains(modal)) return;
    _shaded.add(modal);
    _publish();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is! ModalRoute<dynamic> || !_shaded.contains(route)) return;
    // The route is on its way out but its own barrier is still fading: hold the
    // chrome's shade until that finishes, so the sidebar does not go bright a
    // frame before the Screen does.
    final Animation<double>? animation = route.animation;
    if (animation == null || animation.status == AnimationStatus.dismissed) {
      _unshade(route);
      return;
    }
    animation.addStatusListener((AnimationStatus status) {
      if (status == AnimationStatus.dismissed) _unshade(route);
    });
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is ModalRoute<dynamic>) _unshade(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute is ModalRoute<dynamic>) _unshade(oldRoute);
    if (newRoute != null) didPush(newRoute, null);
  }

  void _unshade(ModalRoute<dynamic> route) {
    if (!_shaded.remove(route)) return;
    _publish();
  }
}

/// The chrome's share of an open modal's barrier: [route]'s own colour, over the
/// Shell's column, on the route's own animation.
///
/// Drawn in the same colour and on the same curve as the barrier the modal
/// paints over the Screen beside it, so the two read as one shade across the
/// window rather than as a strip that stops at the sidebar.
class ModalScrim extends StatelessWidget {
  const ModalScrim({super.key, required this.route});

  /// The modal whose barrier this continues.
  final ModalRoute<dynamic> route;

  @override
  Widget build(BuildContext context) {
    // The route's own animation, not a curve of our own: a dialog fades its
    // barrier in over its transition, and a shade that appeared at full
    // strength would show the seam this exists to remove. Both ends are the
    // route's colour, so the fade is that colour's own alpha and not a lerp
    // through some other grey.
    final Color barrier = route.barrierColor ?? Theme.of(context).colorScheme.scrim;
    final Animation<double> animation = route.animation ?? kAlwaysCompleteAnimation;
    return AnimatedModalBarrier(
      color: animation.drive(
        ColorTween(begin: barrier.withValues(alpha: 0), end: barrier),
      ),
      // A barrier-dismissible dialog can be dismissed by tapping beside it, and
      // the chrome is beside it. A dialog that is not dismissible ignores the
      // tap, as the Screen does.
      dismissible: route.barrierDismissible,
      onDismiss: route.barrierDismissible ? () => route.navigator?.maybePop() : null,
      // The route's own barrier is the one assistive technology announces; a
      // second one beside it would read the dismissal twice.
      barrierSemanticsDismissible: false,
    );
  }
}
