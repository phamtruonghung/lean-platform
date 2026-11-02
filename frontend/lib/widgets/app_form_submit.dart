/// `AppFormSubmit`: `Enter`, in a form's single-line field, submits that form's
/// primary action (issue #401).
///
/// The policy the Platform writes down once: a reader who has typed the last
/// thing a form needs presses `Enter` and the form does what its primary button
/// does. The rule is deliberately narrow, and each half of it is a decision:
///
/// - **Only from a single-line field.** `Enter` in a multi-line field is a
///   newline the reader asked for; a form that submits there either loses their
///   paragraph or refuses the paragraph's own line break. A field's `maxLines`
///   is what decides, so a comment box that grows to five lines keeps `Enter`.
/// - **Never instead of a button.** With an action focused, `Enter` is that
///   action's own activation — Flutter's `ActivateIntent` — and a button the
///   reader has navigated to must do exactly what the button says, not what the
///   form's primary happens to be. This widget returns `KeyEventResult.ignored`
///   whenever the primary focus is not inside a single-line `EditableText`, so
///   the event falls through to the framework's own handling untouched.
/// - **Only when the form can submit.** A null [onSubmit] is the same null the
///   primary button's `onPressed` carries while a request is in flight; the
///   key does nothing rather than starting a second one.
///
/// **Why a `Focus.onKeyEvent` and not a `Shortcuts`/`Actions` pair.** Measured
/// in the pinned image: a `Shortcuts` layer installed between a focused button
/// and the app's own default shortcuts takes `Enter` before `ActivateIntent`
/// reaches the button, so an action stops activating (probed: `pressed = 0`).
/// A `Focus` handler can decline — `ignored` passes the event up the chain to
/// the framework's shortcuts — which is the one behaviour the rule needs.
///
/// A `TextField.onSubmitted` is not a substitute: it fires for a soft keyboard's
/// own action key, and in the pinned image a hardware `Enter` key event does not
/// reach it (measured: `onSubmitted` did not fire, this widget did). Both paths
/// are kept, so a phone and a keyboard do the same thing by different routes.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppFormSubmit extends StatelessWidget {
  const AppFormSubmit({super.key, required this.onSubmit, required this.child});

  /// What `Enter` submits — the form's primary action, and `null` exactly when
  /// that action is disabled.
  final VoidCallback? onSubmit;

  /// The form, fields included.
  final Widget child;

  /// Whether the primary focus currently sits in a single-line text field.
  ///
  /// The field is found by walking up from the focus node's own context to its
  /// `EditableText`, which is where `maxLines` lives for both `TextField` and
  /// `TextFormField`. Public so a test can state the rule it is relying on.
  static bool focusIsInSingleLineField() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    EditableText? field;
    context.visitAncestorElements((element) {
      final widget = element.widget;
      if (widget is EditableText) {
        field = widget;
        return false;
      }
      return true;
    });
    final found = field;
    return found != null && (found.maxLines == null || found.maxLines == 1);
  }

  @override
  Widget build(BuildContext context) {
    final submit = onSubmit;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key != LogicalKeyboardKey.enter &&
            key != LogicalKeyboardKey.numpadEnter) {
          return KeyEventResult.ignored;
        }
        if (submit == null || !focusIsInSingleLineField()) {
          return KeyEventResult.ignored;
        }
        submit();
        return KeyEventResult.handled;
      },
      child: child,
    );
  }
}
