/// The header every register Screen shares: a title, an optional description,
/// the Screen's actions at the row's far end, a hairline under the lot, and
/// whatever filters sit beneath it.
///
/// **Why it exists.** Twenty-odd Screens each hand-rolled a private `_Header`
/// that drew the same title, the same muted description and the same row of
/// buttons slightly differently, so the pages did not read as one product. Home
/// (issue #375) set the shape: a `headlineSmall` title at w700 that is a real
/// header to a screen reader, a muted description, and a `cardBorder` hairline
/// under it. This is that shape, once.
///
/// **What it does not own.** No padding, no `Center`, no [AppPageFrame]. The
/// call site keeps its frame and its `Spacing.lg` / `Spacing.xl` inset, because
/// `page_alignment_test.dart` pins that inset per page and no page's left edge
/// may move. The hairline therefore spans the call site's content box, from the
/// title's own left edge.
///
/// **Actions wrap by the box, not the window.** When the box this header is
/// given is narrower than [wrapBreakpoint], scaled by the reader's text size,
/// the actions drop under the title instead of squeezing it. The width is read
/// off a `LayoutBuilder`, never `MediaQuery`: a Screen renders inside the
/// Shell's content area, and the window is the wrong width to ask about (the
/// lesson of `WorkOrdersScreen.narrowBreakpoint`). `MediaQuery` supplies only
/// the text scale: the actions row grows with it and the box does not, so at a
/// larger text size the same box needs the wrap sooner (WCAG 1.4.4, Resize
/// Text).
///
/// **[below]** is the Screen's filter row (site dropdown, chips, toggles). It
/// sits under the hairline, [Spacing.md] beneath it, so every Screen spaces its
/// filters from the rule the same way.
library;

import 'package:flutter/material.dart';

import '../theme.dart';

class AppPageHeader extends StatelessWidget {
  const AppPageHeader({
    super.key,
    required this.title,
    this.description,
    this.actions = const [],
    this.below,
  });

  final String title;
  final String? description;

  /// Buttons for the row's far end. Wrapped under the title when the box is
  /// narrower than [wrapBreakpoint] at the reader's text scale.
  final List<Widget> actions;

  /// A filter row beneath the hairline.
  final Widget? below;

  /// The widest a description may run, however wide the box.
  static const double descriptionMeasure = 640;

  /// Below this box width, at a text scale of 1, the actions wrap under the
  /// title. The breakpoint is multiplied by the reader's text-scale factor
  /// (never reduced below 1): the actions row grows with the scale and the box
  /// does not (WCAG 1.4.4).
  static const double wrapBreakpoint = 560;

  static const ValueKey<String> titleKey = ValueKey<String>('app-page-header-title');
  static const ValueKey<String> descriptionKey = ValueKey<String>('app-page-header-description');
  static const ValueKey<String> actionsKey = ValueKey<String>('app-page-header-actions');
  static const ValueKey<String> ruleKey = ValueKey<String>('app-page-header-rule');
  static const ValueKey<String> belowKey = ValueKey<String>('app-page-header-below');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppColors.of(context);

    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            key: titleKey,
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        if (description != null) ...[
          const SizedBox(height: Spacing.xs),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: descriptionMeasure),
            child: Text(
              description!,
              key: descriptionKey,
              style: theme.textTheme.bodyMedium?.copyWith(color: palette.textMuted),
            ),
          ),
        ],
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            if (actions.isEmpty) return titleBlock;
            final textScale = MediaQuery.textScalerOf(context).scale(1);
            final breakpoint = wrapBreakpoint * (textScale < 1 ? 1 : textScale);
            final wrapped = constraints.maxWidth < breakpoint;
            if (wrapped) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  titleBlock,
                  const SizedBox(height: Spacing.sm),
                  Wrap(
                    key: actionsKey,
                    spacing: Spacing.sm,
                    runSpacing: Spacing.sm,
                    children: actions,
                  ),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: titleBlock),
                const SizedBox(width: Spacing.md),
                Row(
                  key: actionsKey,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(width: Spacing.sm),
                      actions[i],
                    ],
                  ],
                ),
              ],
            );
          },
        ),
        const SizedBox(height: Spacing.md),
        // A `Divider` spans the content box, so it starts at the title's own
        // left edge.
        Divider(key: ruleKey, height: 1, thickness: 1, color: palette.cardBorder),
        if (below != null) ...[
          const SizedBox(height: Spacing.md),
          KeyedSubtree(key: belowKey, child: below!),
        ],
      ],
    );
  }
}
