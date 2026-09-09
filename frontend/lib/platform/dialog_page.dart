import 'package:flutter/material.dart';

/// A [Page] whose route is a [DialogRoute] rather than an opaque full-screen
/// route (issue #104, ADR-0019) — what lets a Work order transition
/// (assign, complete, cancel) or the raise form be a real `go_router`
/// address while still looking exactly like the `showDialog` it replaces:
/// a [DialogRoute] is a [PopupRoute], so it is non-opaque and paints over
/// whatever page sits beneath it in the Navigator, the same "list stays
/// visible underneath" look every dialog already had.
///
/// Before #104, each of the four Work order dialogs opened itself with a
/// bare `showDialog(...)`, which builds its route directly under the
/// Navigator with no address of its own — a refresh loses the open dialog,
/// and a link to "assign this Work order" cannot be sent to anyone. This
/// class is what lets `router.dart` give each transition its own child
/// `GoRoute` instead, so the address survives a refresh the way ADR-0019
/// already requires of the three backend transition routes it names.
///
/// [barrierDismissible] defaults to `false` to match every one of the four
/// dialogs' own former `showDialog` call, which all passed the same value:
/// dismissing by tapping outside was never offered, only the dialog's own
/// Cancel/dismiss control.
class DialogPage<T> extends Page<T> {
  const DialogPage({
    required this.builder,
    this.barrierDismissible = false,
    super.key,
    super.name,
    super.arguments,
    super.restorationId,
  });

  final WidgetBuilder builder;
  final bool barrierDismissible;

  @override
  Route<T> createRoute(BuildContext context) => DialogRoute<T>(
        context: context,
        settings: this,
        builder: builder,
        barrierDismissible: barrierDismissible,
      );
}
