/// `AppConfirmDialog`: the destructive form of [AppDialog] — one question, a
/// description, a way out and the act that cannot be undone.
///
/// It is an [AppDialog] at [AppDialogSize.decision] (420) with two actions: the
/// dismiss at the inline start and the confirm at the inline end, filled in
/// `statusDanger` with `canvas` on it (6.18:1 light, 9.41:1 dark; white on the dark
/// `statusDanger` would be 1.90:1, which is why the pair is not the primary
/// button's). `Esc` runs the dismiss callback, so it cancels, and initial focus is
/// on the dismiss action, so Enter on opening does not confirm.
///
/// **It owns no state and does not pop the route itself.** [onConfirm] and
/// [onDismiss] are the caller's callbacks and do whatever the caller's do, usually
/// a Bloc event and a `Navigator.pop` (or, on an addressable dialog, a `go`). Both
/// strings are the caller's, verbatim: a dismiss that must not say "Cancel" because
/// the confirm is itself a cancellation ("Keep it open") is the caller's wording.
/// Either callback null renders its button disabled, which is how a caller shows a
/// request in flight.
library;

import 'package:flutter/material.dart';

import 'app_dialog.dart';

class AppConfirmDialog extends StatelessWidget {
  const AppConfirmDialog({
    super.key,
    required this.title,
    this.description,
    required this.confirmLabel,
    required this.dismissLabel,
    this.onConfirm,
    this.onDismiss,
  });

  final String title;
  final String? description;
  final String confirmLabel;
  final String dismissLabel;
  final VoidCallback? onConfirm;
  final VoidCallback? onDismiss;

  // The shell's own keys, named for this dialog's use of them: a `ValueKey` is
  // equal by value, so these find exactly the widgets `AppDialog` keyed.
  static final ValueKey<String> confirmKey = AppDialog.actionKey(_confirmId);
  static final ValueKey<String> dismissKey = AppDialog.actionKey(_dismissId);
  static const ValueKey<String> titleKey = AppDialog.titleKey;
  static const ValueKey<String> descriptionKey = AppDialog.descriptionKey;

  static const String _confirmId = 'confirm';
  static const String _dismissId = 'dismiss';

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: title,
      description: description,
      size: AppDialogSize.decision,
      actions: [
        AppDialogAction(
          id: _dismissId,
          label: dismissLabel,
          onPressed: onDismiss,
          kind: AppDialogActionKind.dismiss,
        ),
        AppDialogAction(
          id: _confirmId,
          label: confirmLabel,
          onPressed: onConfirm,
          kind: AppDialogActionKind.destructive,
        ),
      ],
    );
  }
}
