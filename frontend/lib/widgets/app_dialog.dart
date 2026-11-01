/// `AppDialog`: the one shell a Platform dialog is drawn in, at one of four
/// widths, and a bottom sheet when the box is narrow or the text is large.
///
/// **Why it exists.** 112 of the 113 `*dialog*.dart` files under `lib/` build an
/// `AlertDialog` and set the width on a `SizedBox` *inside* its `content:`, so the
/// title and the action row are not the width the author chose, the platform's own
/// padding decides the rest, and the actions are centred. Seven hand-set widths
/// (420, 520, 460, 560, 480, 640, 620) answer four real questions. This is those
/// four, once. `docs/design-language.md` section 11 argues each number.
///
/// **The shell, top to bottom.** A title row (`titleMedium`, w600, `textPrimary`;
/// at most one trailing icon control, [trailing]), an optional [description]
/// (`dense`, `textMuted`, [Spacing.xs] under the title), a content area that is
/// the only scroller, and an action row pinned under it. Fill `card`, radius
/// [AppRadius.card], a hairline of `edge`, no elevation. Title, description and
/// content sit [Spacing.lg] in from the edge; the action row is [Spacing.lg] in
/// and [Spacing.md] above and below; the gap from the title block to the content
/// is [Spacing.md] and from the content to the action row [Spacing.lg].
///
/// **The actions.** Dismiss kinds at the inline start, a [Spacing.lg] gap, then
/// destructive and primary at the inline end: primary right-most, destructive
/// separated from it and never first. Each is at least [AppTouchTarget.min] tall,
/// keeps its caller's label verbatim and carries [actionKey] of its `id`. A null
/// `onPressed` renders the action disabled. A label that does not fit wraps inside
/// its button; nothing overflows.
///
/// **A sheet when the box is narrow or the text is large.** At or below
/// [AppBreakpoints.dialogSheet] of box, or at or above
/// [AppBreakpoints.dialogSheetTextScale] of text scale, the dialog is a bottom
/// sheet: full width, anchored to the bottom, [AppRadius.card] on the top corners
/// only, the title and action rows pinned, the content the only scroller, and the
/// action row full-width with the primary action filling the inline end. **The box
/// is measured by the `LayoutBuilder` at this widget's root, and a dialog route is
/// handed the whole window** (no Shell chrome around it), so that box *is* the
/// window here. That is deliberate and the one place a window-sized box is right;
/// do not "fix" it into `MediaQuery.sizeOf`, which would ignore a dialog hosted in
/// anything narrower. The box is compared as it is, not multiplied by the text
/// scale: the text scale is a trigger of its own.
///
/// **What this widget guarantees**
///
/// - a `Semantics(scopesRoute, namesRoute)` wrapper labelled with the title, so a
///   screen reader announces the dialog by name ([surfaceKey] carries it);
/// - focus stays inside while it is open: the dialog is its own focus scope,
///   inside the route's, and a scope traps Tab (proved in `app_dialog_test.dart`,
///   not assumed). A focused action that is disabled while a request is in flight
///   leaves focus on that scope, so `Esc` still works when the actions re-enable;
/// - focus starts on the first focusable thing in [child], or, when it has none,
///   on the primary action, or, when there is no primary action, on the dismiss
///   action (so that a destructive confirm never opens with Enter armed on the
///   destructive button), or, last, on the destructive action. Only an *enabled*
///   action is a candidate; with none enabled, the dialog's scope has focus;
/// - `Esc` runs the dialog's own dismiss action, so Esc on a destructive confirm
///   cancels; with no dismiss action it pops the route; and with a dismiss action
///   that is disabled (a request in flight) it does nothing, like the button;
/// - focus returns to the control that opened the dialog when the route closes
///   (the route does it; `app_dialog_test.dart` measures that it does);
/// - every action is 44px, and every colour is a token.
///
/// **What the caller still owns**: its strings, its field keys and labels, its
/// enable conditions (`onPressed == null`), its own failure text inline in
/// [child], what each callback does (this widget never pops the route for a
/// caller, except the Esc-with-no-dismiss-action case above), and
/// `DialogPage(barrierDismissible: ...)` where the dialog is addressable.
///
/// It is presentation only: it makes no request and imports no Bloc.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// How much a dialog has to hold, which is its width.
enum AppDialogSize {
  /// One question, a description, two actions. No fields.
  decision(420),

  /// A list or filter to choose one thing from.
  picker(460),

  /// A short form, up to about six fields.
  form(520),

  /// A long form, or content with its own columns.
  wide(640);

  const AppDialogSize(this.width);

  /// The width at a box that can hold it, in logical pixels.
  final double width;
}

/// What an action means, which decides where it sits and how it is drawn.
enum AppDialogActionKind {
  /// The way out that changes nothing: Cancel, Keep it open, Close. `Esc` runs it.
  dismiss,

  /// The dialog's own act. Right-most.
  primary,

  /// The act that destroys or cannot be undone. Filled in the danger colour,
  /// separated from the primary and never first.
  destructive,
}

class AppDialogAction {
  const AppDialogAction({
    required this.id,
    required this.label,
    this.onPressed,
    this.kind = AppDialogActionKind.primary,
  });

  /// Names the action's `Key` ([AppDialog.actionKey]).
  final String id;

  /// The caller's own words, shown verbatim.
  final String label;

  /// Null renders the action disabled.
  final VoidCallback? onPressed;

  final AppDialogActionKind kind;
}

class AppDialog extends StatefulWidget {
  const AppDialog({
    super.key,
    required this.title,
    this.description,
    this.child,
    required this.actions,
    this.size = AppDialogSize.form,
    this.trailing,
  });

  final String title;

  /// One or two sentences under the title.
  final String? description;

  /// The content area: the only part that scrolls.
  final Widget? child;

  final List<AppDialogAction> actions;

  final AppDialogSize size;

  /// At most one icon control at the end of the title row. The caller gives it a
  /// tooltip or a semantics label; it is laid out to at least 44px.
  final Widget? trailing;

  static const ValueKey<String> surfaceKey = ValueKey<String>('app-dialog-surface');
  static const ValueKey<String> titleKey = ValueKey<String>('app-dialog-title');
  static const ValueKey<String> descriptionKey = ValueKey<String>('app-dialog-description');
  static const ValueKey<String> contentKey = ValueKey<String>('app-dialog-content');
  static const ValueKey<String> actionsKey = ValueKey<String>('app-dialog-actions');

  /// Present only while the dialog is a sheet.
  static const ValueKey<String> sheetKey = ValueKey<String>('app-dialog-sheet');

  static ValueKey<String> actionKey(String id) => ValueKey<String>('app-dialog-action-$id');

  /// True when a dialog in [boxWidth] of box, at the reader's text scale, is a
  /// sheet. Exposed so a caller sizing something to match asks the same question.
  static bool isSheet(BuildContext context, double boxWidth) =>
      boxWidth <= AppBreakpoints.dialogSheet ||
      MediaQuery.textScalerOf(context).scale(1) >= AppBreakpoints.dialogSheetTextScale;

  @override
  State<AppDialog> createState() => _AppDialogState();
}

class _AppDialogState extends State<AppDialog> {
  // Survives the dialog becoming a sheet and back, so a field's text, focus and
  // scroll offset do not reset when the box crosses the breakpoint.
  final GlobalKey _bodyKey = GlobalKey(debugLabel: 'app dialog body');
  // The dialog's own scope, *inside* the Shortcuts and Actions below. A focused
  // action that is disabled (a request in flight) loses focus to its nearest
  // scope, and that must be one still under the Esc handler, not the route's.
  final FocusScopeNode _scope = FocusScopeNode(debugLabel: 'app dialog');
  final FocusNode _contentFocus =
      FocusNode(debugLabel: 'app dialog content', skipTraversal: true, canRequestFocus: false);
  final FocusNode _initialActionFocus = FocusNode(debugLabel: 'app dialog initial action');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _placeFocus());
  }

  @override
  void dispose() {
    _scope.dispose();
    _contentFocus.dispose();
    _initialActionFocus.dispose();
    super.dispose();
  }

  void _placeFocus() {
    if (!mounted) return;
    final current = FocusManager.instance.primaryFocus;
    // A field the caller autofocused already has it.
    if (current != null && current.ancestors.contains(_scope)) return;
    final inContent = _contentFocus.traversalDescendants.where((node) => node.canRequestFocus);
    if (inContent.isNotEmpty) {
      inContent.first.requestFocus();
    } else if (_initialAction != null) {
      _initialActionFocus.requestFocus();
    } else {
      // Nothing to focus (every action disabled): the scope itself, so Esc and
      // Tab still have somewhere under the dialog to start from.
      _scope.requestFocus();
    }
  }

  AppDialogAction? get _initialAction {
    for (final kind in const [
      AppDialogActionKind.primary,
      AppDialogActionKind.dismiss,
      AppDialogActionKind.destructive,
    ]) {
      for (final action in widget.actions) {
        if (action.kind == kind && action.onPressed != null) return action;
      }
    }
    return null;
  }

  void _dismiss() {
    for (final action in widget.actions) {
      if (action.kind == AppDialogActionKind.dismiss) {
        action.onPressed?.call();
        return;
      }
    }
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final sheet = AppDialog.isSheet(context, constraints.maxWidth);
        final width = sheet
            ? constraints.maxWidth
            : widget.size.width < constraints.maxWidth - 2 * Spacing.xl
                ? widget.size.width
                : constraints.maxWidth - 2 * Spacing.xl;
        final side = BorderSide(color: palette.cardBorder);
        final radius = BorderRadius.circular(AppRadius.card);
        final body = KeyedSubtree(
          key: _bodyKey,
          child: _body(context, contentMaxHeight: constraints.maxHeight * 0.6, sheet: sheet),
        );
        return Dialog(
          key: sheet ? AppDialog.sheetKey : null,
          backgroundColor: palette.card,
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          alignment: sheet ? Alignment.bottomCenter : Alignment.center,
          insetPadding: sheet
              ? EdgeInsets.zero
              : const EdgeInsets.symmetric(horizontal: Spacing.xl, vertical: Spacing.xl),
          shape: RoundedRectangleBorder(
            borderRadius: sheet ? BorderRadius.vertical(top: radius.topLeft) : radius,
            side: side,
          ),
          child: Semantics(
            key: AppDialog.surfaceKey,
            scopesRoute: true,
            namesRoute: true,
            explicitChildNodes: true,
            label: widget.title,
            child: SizedBox(
              width: width,
              child: Shortcuts(
                shortcuts: const <ShortcutActivator, Intent>{
                  SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
                },
                child: Actions(
                  actions: <Type, Action<Intent>>{
                    DismissIntent: CallbackAction<DismissIntent>(onInvoke: (_) {
                      _dismiss();
                      return null;
                    }),
                  },
                  child: FocusScope(node: _scope, child: body),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _body(BuildContext context, {required double contentMaxHeight, required bool sheet}) {
    final palette = AppColors.of(context);
    final theme = Theme.of(context);
    final description = widget.description;
    final child = widget.child;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.lg, Spacing.lg, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  // Centres the first line of the title on a 44px trailing control.
                  padding: EdgeInsets.only(top: widget.trailing == null ? 0 : Spacing.sm),
                  child: Semantics(
                    header: true,
                    child: Text(
                      widget.title,
                      key: AppDialog.titleKey,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600, color: palette.textPrimary),
                    ),
                  ),
                ),
              ),
              if (widget.trailing != null)
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: AppTouchTarget.min,
                    minHeight: AppTouchTarget.min,
                  ),
                  child: Center(child: widget.trailing),
                ),
            ],
          ),
        ),
        if (description != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xs, Spacing.lg, 0),
            child: Text(
              description,
              key: AppDialog.descriptionKey,
              style: AppTypography.dense(context)?.copyWith(color: palette.textMuted),
            ),
          ),
        if (child != null) ...[
          const SizedBox(height: Spacing.md),
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: contentMaxHeight),
              child: SingleChildScrollView(
                key: AppDialog.contentKey,
                padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
                child: Focus(focusNode: _contentFocus, child: child),
              ),
            ),
          ),
        ],
        const SizedBox(height: Spacing.lg),
        Padding(
          key: AppDialog.actionsKey,
          padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: Spacing.md),
          child: _actionRow(context, sheet: sheet),
        ),
      ],
    );
  }

  Widget _actionRow(BuildContext context, {required bool sheet}) {
    final initial = _initialAction;
    Widget button(AppDialogAction action) => _ActionButton(
          action: action,
          focusNode: identical(action, initial) ? _initialActionFocus : null,
        );

    List<AppDialogAction> of(AppDialogActionKind kind) =>
        [for (final a in widget.actions) if (a.kind == kind) a];
    final dismiss = of(AppDialogActionKind.dismiss);
    final destructive = of(AppDialogActionKind.destructive);
    final primary = of(AppDialogActionKind.primary);

    // A group of peers [Spacing.sm] apart. A button is flexible so a label that
    // does not fit wraps inside it rather than overflowing the row; in a sheet the
    // end group's buttons fill the space.
    Widget group(List<AppDialogAction> actions, {required bool fill}) => Row(
          mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
          children: [
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0) const SizedBox(width: Spacing.sm),
              fill ? Expanded(child: button(actions[i])) : Flexible(child: button(actions[i])),
            ],
          ],
        );

    final hasStart = dismiss.isNotEmpty;
    final endGroups = [if (destructive.isNotEmpty) destructive, if (primary.isNotEmpty) primary];
    final hasEnd = endGroups.isNotEmpty;

    Widget end({required bool fill}) => Row(
          mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
          children: [
            for (var i = 0; i < endGroups.length; i++) ...[
              if (i > 0) const SizedBox(width: Spacing.lg),
              fill
                  ? Expanded(flex: endGroups[i].length, child: group(endGroups[i], fill: true))
                  : Flexible(child: group(endGroups[i], fill: false)),
            ],
          ],
        );

    // The dismiss group takes its natural width, up to two fifths of the row, so a
    // long label wraps instead of crowding out the act; the end group takes what is
    // left. (Two flexible children would split the free space between them whether
    // or not the first used its share, and wrap a label that had room.)
    return LayoutBuilder(
      builder: (context, constraints) => Row(
        mainAxisAlignment: sheet || (hasStart && hasEnd)
            ? MainAxisAlignment.spaceBetween
            : hasEnd
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
        children: [
          if (hasStart)
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.4),
              child: group(dismiss, fill: false),
            ),
          if (hasStart && hasEnd) const SizedBox(width: Spacing.lg),
          if (hasEnd) sheet ? Expanded(child: end(fill: true)) : Flexible(child: end(fill: false)),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.action, this.focusNode});

  final AppDialogAction action;
  final FocusNode? focusNode;

  static const Size _minimum = Size(AppTouchTarget.min, AppTouchTarget.min);

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final label = Text(action.label);
    final key = AppDialog.actionKey(action.id);
    return switch (action.kind) {
      AppDialogActionKind.dismiss => OutlinedButton(
          key: key,
          focusNode: focusNode,
          onPressed: action.onPressed,
          style: OutlinedButton.styleFrom(minimumSize: _minimum),
          child: label,
        ),
      AppDialogActionKind.primary => FilledButton(
          key: key,
          focusNode: focusNode,
          onPressed: action.onPressed,
          style: FilledButton.styleFrom(minimumSize: _minimum),
          child: label,
        ),
      // The canvas, not white: white on the dark palette's statusDanger (#FCA5A5)
      // is 1.90:1. The canvas on statusDanger is 6.18:1 light and 9.41:1 dark.
      AppDialogActionKind.destructive => FilledButton(
          key: key,
          focusNode: focusNode,
          onPressed: action.onPressed,
          style: FilledButton.styleFrom(
            minimumSize: _minimum,
            backgroundColor: palette.statusDanger,
            foregroundColor: palette.canvas,
          ),
          child: label,
        ),
    };
  }
}
