/// `AppBanner`: the one inline surface the Platform reports an outcome on.
///
/// **Why one.** The client's gap is not that it has no transient feedback (Flutter
/// has a `SnackBar`); it is that most of its Screens have nowhere stable to put a
/// persistent one, so each draws its own tinted `Container` in its own spot.
/// `docs/design-language.md` section 12 says where this goes (first child of a
/// page's body, never an overlay, never inside a dialog) and what is never a snack.
///
/// **What it is.** A [tone]'s fill and foreground from the palette
/// (`statusFill` / `statusForeground`), [AppRadius.card], [Spacing.md] padding, a
/// decorative tone icon ([Spacing.sm] before the text, hidden from semantics: the
/// words carry the meaning, never the colour alone), an optional [title] in `dense`
/// w600, the [message] in `dense`, an optional [action] (laid out to at least
/// [AppTouchTarget.min] tall, at the inline end) and an optional dismiss
/// `IconButton` (44px box, [dismissTooltip]).
///
/// **It announces itself.** `Semantics(container: true, liveRegion: true)`, so a
/// screen reader reads it when it appears.
///
/// **Narrow, the action drops under the message.** Below
/// [AppBreakpoints.headerActionsWrap] of box, scaled by the reader's text size
/// ([AppBreakpoints.effective]), read from the `LayoutBuilder` at this widget's root
/// and never from the window.
///
/// **Contrast, measured** (WCAG 2.x, foreground on its own fill, light / dark):
/// neutral 6.50 / 6.97, info 8.49 / 8.49, success 6.49 / 6.49, warning 6.38 / 9.28,
/// danger 5.30 / 5.28.
///
/// It is presentation only: it makes no request and holds no state; the caller
/// shows and removes it.
library;

import 'package:flutter/material.dart';

import '../status_tone.dart';
import '../theme.dart';

class AppBanner extends StatelessWidget {
  const AppBanner({
    super.key,
    required this.tone,
    required this.message,
    this.title,
    this.action,
    this.onDismiss,
    this.dismissTooltip = 'Dismiss',
  });

  final StatusTone tone;
  final String message;
  final String? title;

  /// A button for the inline end: a retry, an undo, a link to the thing made.
  final Widget? action;

  /// Null shows no dismiss control.
  final VoidCallback? onDismiss;
  final String dismissTooltip;

  static const ValueKey<String> bannerKey = ValueKey<String>('app-banner');
  static const ValueKey<String> messageKey = ValueKey<String>('app-banner-message');
  static const ValueKey<String> titleKey = ValueKey<String>('app-banner-title');
  static const ValueKey<String> actionKey = ValueKey<String>('app-banner-action');
  static const ValueKey<String> dismissKey = ValueKey<String>('app-banner-dismiss');

  static const double _iconSize = 20;

  static IconData _icon(StatusTone tone) => switch (tone) {
        StatusTone.neutral => Icons.notes,
        StatusTone.info => Icons.info_outline,
        StatusTone.success => Icons.check_circle_outline,
        StatusTone.warning => Icons.warning_amber_outlined,
        StatusTone.danger => Icons.error_outline,
      };

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final foreground = palette.statusForeground(tone);
    final dense = AppTypography.dense(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth <
            AppBreakpoints.effective(context, AppBreakpoints.headerActionsWrap);
        final dropAction = action != null && narrow;

        final text = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (title != null)
              Text(
                title!,
                key: titleKey,
                style: dense?.copyWith(fontWeight: FontWeight.w600, color: foreground),
              ),
            Text(message, key: messageKey, style: dense?.copyWith(color: foreground)),
          ],
        );

        final actionTarget = action == null
            ? null
            : KeyedSubtree(
                key: actionKey,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: AppTouchTarget.min),
                  child: action,
                ),
              );

        final dismiss = onDismiss == null
            ? null
            : ConstrainedBox(
                constraints: const BoxConstraints.tightFor(
                  width: AppTouchTarget.min,
                  height: AppTouchTarget.min,
                ),
                child: IconButton(
                  key: dismissKey,
                  tooltip: dismissTooltip,
                  onPressed: onDismiss,
                  color: foreground,
                  icon: const Icon(Icons.close, size: _iconSize),
                ),
              );

        return Semantics(
          container: true,
          liveRegion: true,
          child: DecoratedBox(
            key: bannerKey,
            decoration: BoxDecoration(
              color: palette.statusFill(tone),
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Padding(
              padding: const EdgeInsets.all(Spacing.md),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // The icon and the words hold the top; the controls at the end
                  // are centred on whatever height that leaves, so a one-line
                  // banner reads as one line beside a 44px control.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ExcludeSemantics(
                              child: Icon(_icon(tone), size: _iconSize, color: foreground),
                            ),
                            const SizedBox(width: Spacing.sm),
                            Expanded(child: text),
                          ],
                        ),
                      ),
                      if (actionTarget != null && !dropAction) ...[
                        const SizedBox(width: Spacing.sm),
                        actionTarget,
                      ],
                      if (dismiss != null) ...[
                        const SizedBox(width: Spacing.sm),
                        dismiss,
                      ],
                    ],
                  ),
                  if (dropAction)
                    Padding(
                      padding: const EdgeInsets.only(top: Spacing.sm),
                      child: Align(alignment: AlignmentDirectional.centerEnd, child: actionTarget),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
