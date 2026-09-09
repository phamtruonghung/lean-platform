import 'package:flutter/material.dart';

import '../theme.dart';

/// Which of the two empty stories this Screen is telling (issue #103, #99's
/// Implementation Decisions) — the useful action differs, so this decides
/// icon and wording pattern rather than folding both into one
/// undifferentiated "nothing here" widget:
///
/// - [noneExist] — nothing has ever been recorded here. The resolving
///   action CREATES the missing thing.
/// - [noneMatched] — records exist, but the caller's own filter matched
///   none of them. The resolving action CLEARS the filter, never creates a
///   record nobody asked for.
///
/// A Screen with both a filter and a genuinely-empty backing collection
/// (`WorkOrdersScreen`, this ticket's own worked example) picks between the
/// two per read rather than always reaching for one — see
/// `_WorkOrdersEmpty` in `maintenance/work_orders_screen.dart`.
enum EmptyStateVariant { noneExist, noneMatched }

/// The shared "nothing here" state (issue #103): an icon, a title, a
/// sentence of explanation, and — optionally — the one action that resolves
/// it. [PlatformEmptyState.noneExist] and [PlatformEmptyState.noneMatched]
/// are separate named constructors rather than one constructor plus a
/// boolean, so a call site cannot forget which story it is telling and a
/// test can key its `find.byType`/`find.byWidgetPredicate` off [variant]
/// directly.
///
/// [actionLabel]/[onAction] are both-or-neither: some reads have nothing to
/// create and no filter to clear (`SkillCoverageScreen`'s "every
/// requirement is met" — a genuinely good-news empty with no button to
/// offer), so the action is simply omitted rather than forced onto a
/// Screen that has none to give.
///
/// Carries `Semantics(liveRegion: true)` so a screen reader announces the
/// state the moment it replaces loading or list content in place (#99 user
/// story 17) — the same reasoning [PlatformFailureState] and
/// [PlatformScopeRefusedState] give their own wrapper.
class PlatformEmptyState extends StatelessWidget {
  const PlatformEmptyState.noneExist({
    super.key,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.actionKey,
    this.icon = Icons.inbox_outlined,
  }) : variant = EmptyStateVariant.noneExist;

  const PlatformEmptyState.noneMatched({
    super.key,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.actionKey,
    this.icon = Icons.filter_alt_off_outlined,
  }) : variant = EmptyStateVariant.noneMatched;

  final EmptyStateVariant variant;
  final String title;
  final String message;

  /// Both null, or both set — see this class's own doc comment.
  final String? actionLabel;
  final VoidCallback? onAction;

  /// The action button's own `Key`, so a test can target it without
  /// depending on its label text (AGENTS.md §7's "public static Key
  /// accessors" convention) — supplied by the migrated Screen's own static
  /// key, e.g. `WorkOrdersScreen.emptyClearFiltersKey`.
  final Key? actionKey;

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasAction = actionLabel != null && onAction != null;
    return Semantics(
      liveRegion: true,
      label: '$title. $message',
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          // Scrollable, not a bare Column, for the same reason
          // `WorkOrdersScreen`'s own pre-#103 empty state already was: on a
          // short viewport this can sit underneath a success notice above
          // it and together be taller than the space left for it.
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Spacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 48, color: AppColors.textMuted),
                const SizedBox(height: Spacing.md),
                Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
                const SizedBox(height: Spacing.sm),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: AppTypography.body(context)?.copyWith(color: AppColors.textMuted),
                ),
                if (hasAction) ...[
                  const SizedBox(height: Spacing.md),
                  FilledButton.tonal(
                    key: actionKey,
                    onPressed: onAction,
                    // Every interactive target is at least 44x44 (#99 user
                    // story 28) — a filled/tonal button's own default is
                    // shorter, so this is set explicitly rather than
                    // inherited.
                    style: FilledButton.styleFrom(minimumSize: const Size(44, 44)),
                    child: Text(actionLabel!),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
