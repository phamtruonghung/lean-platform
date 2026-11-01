/// The row under a page header that narrows a list and acts on it: filters, a
/// count, and actions, in that order, wrapping when the box is too narrow.
///
/// **Why it exists.** Forty-three Screens each hand-rolled their own filters, a
/// count and a row of buttons, in a different order each time, and the count
/// drifted: one Screen read it in the header, the next above the list, a third
/// not at all. This is that row, once, so the narrowing controls always lead,
/// the read-out of what they narrowed to follows, and the acts sit at the far
/// end.
///
/// **Wide it is one row, narrow it is a column.** Below
/// [AppBreakpoints.toolbarWrap] (640, at a text scale of 1) the filters, the
/// count and the actions stack, each on its own line, and nothing is dropped or
/// truncated at any width. The breakpoint is read from the box a `LayoutBuilder`
/// hands this widget, never from the window, and it is scaled by the reader's
/// text size: the actions row grows with the text and the box does not, so the
/// same box needs the wrap sooner (WCAG 1.4.4, Resize Text; the defect behind
/// #379 and #381). [AppBreakpoints.effective] does that multiplication.
///
/// **The wrap is a [Column], not one big [Wrap] of everything.** A `Wrap` of
/// filters, count and buttons mixes the narrowing controls and the acting ones
/// into a single run, and the eye can no longer tell which controls change what
/// is listed from which ones do something to it. A column keeps the two groups
/// as two blocks and lets each wrap inside itself.
///
/// **Every action is laid out to at least [AppTouchTarget.min].** A button's own
/// minimum is a few pixels under it, so each action is given that height here
/// rather than trusting every call site to remember.
///
/// **It owns no padding.** Like `AppPageHeader`, the call site keeps its frame
/// and its inset, so the toolbar's first filter starts at the page's one left
/// edge and `page_alignment_test.dart` has nothing new to pin.
///
/// **It is presentation only.** It makes no request and decides nothing about
/// which filters exist; the caller hands it widgets.
library;

import 'package:flutter/material.dart';

import '../theme.dart';

class AppToolbar extends StatelessWidget {
  const AppToolbar({
    super.key,
    this.filters = const <Widget>[],
    this.count,
    this.actions = const <Widget>[],
  });

  /// The narrowing controls: an `AppFilterField`, dropdowns, chips.
  final List<Widget> filters;

  /// A short read-out such as "12 work orders". Not a button.
  final Widget? count;

  /// Buttons for the far end: `FilledButton`, `OutlinedButton`, `IconButton`.
  /// An icon-only one carries its own tooltip or semantics label.
  final List<Widget> actions;

  static const ValueKey<String> filtersKey = ValueKey<String>('app-toolbar-filters');
  static const ValueKey<String> countKey = ValueKey<String>('app-toolbar-count');
  static const ValueKey<String> actionsKey = ValueKey<String>('app-toolbar-actions');

  @override
  Widget build(BuildContext context) {
    if (filters.isEmpty && count == null && actions.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final wrapped =
            constraints.maxWidth < AppBreakpoints.effective(context, AppBreakpoints.toolbarWrap);
        final targets = [for (final action in actions) _target(action)];
        final filterWrap = Wrap(
          key: filtersKey,
          spacing: Spacing.md,
          runSpacing: Spacing.sm,
          children: filters,
        );

        if (wrapped) {
          // A block, and the gap above it only when something precedes it, so a
          // toolbar with no filters does not open with an empty run and a gap.
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (filters.isNotEmpty) filterWrap,
              if (count != null) ...[
                if (filters.isNotEmpty) const SizedBox(height: Spacing.sm),
                KeyedSubtree(key: countKey, child: count!),
              ],
              if (actions.isNotEmpty) ...[
                if (filters.isNotEmpty || count != null) const SizedBox(height: Spacing.sm),
                Wrap(
                  key: actionsKey,
                  spacing: Spacing.sm,
                  runSpacing: Spacing.sm,
                  children: targets,
                ),
              ],
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: filterWrap),
            if (count != null) ...[
              const SizedBox(width: Spacing.md),
              KeyedSubtree(key: countKey, child: count!),
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(width: Spacing.lg),
              Row(
                key: actionsKey,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < targets.length; i++) ...[
                    if (i > 0) const SizedBox(width: Spacing.sm),
                    targets[i],
                  ],
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  static Widget _target(Widget action) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppTouchTarget.min),
        child: action,
      );
}
