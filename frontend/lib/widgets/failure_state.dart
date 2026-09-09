import 'package:flutter/material.dart';

import '../theme.dart';

/// The shared "that failed" state (issue #103): names what broke and offers
/// a retry. Every call site of this widget reaches it from a read that
/// changed nothing — a Bloc only ever emits this from a load, never from a
/// write already known to have landed — so there is nothing left to say
/// about safety beyond [message] itself.
///
/// [message] is always something already written for a person —
/// `PeopleApiException`/`MaintenanceApiException`'s own `.message`, or a
/// Bloc's own constant such as `signedOutMessage` — never `error.toString()`
/// or a raw exception. A bare exception string names internals (a stack
/// trace, a package name) that mean nothing to whoever is looking at the
/// Screen and sometimes leak more than a UI should show.
///
/// Carries `Semantics(liveRegion: true)` so a screen reader announces the
/// failure the moment it replaces loading or list content in place (#99
/// user story 17).
class PlatformFailureState extends StatelessWidget {
  const PlatformFailureState({
    super.key,
    required this.title,
    required this.message,
    required this.onRetry,
    this.retryKey,
    this.retryLabel = 'Try again',
    this.icon = Icons.cloud_off_outlined,
  });

  final String title;
  final String message;
  final VoidCallback onRetry;

  /// The retry button's own `Key` (AGENTS.md §7) — supplied by the migrated
  /// Screen's own static key, e.g. `WorkOrdersScreen.retryKey`.
  final Key? retryKey;
  final String retryLabel;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      label: '$title. $message',
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
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
                const SizedBox(height: Spacing.md),
                FilledButton.tonal(
                  key: retryKey,
                  onPressed: onRetry,
                  style: FilledButton.styleFrom(minimumSize: const Size(44, 44)),
                  child: Text(retryLabel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The fifth case (issue #103, #99's Implementation Decisions): a read came
/// back refused rather than empty, because a Grant reaches downward only
/// (CONTEXT.md's Grant and Entry point entries, ADR-0008) — the caller may
/// simply be asking from outside every Org Unit they hold one on. Rendered
/// as its own explained state so a scope problem is never mistaken for
/// missing data (#99 user story 15): this never folds into
/// [PlatformEmptyState], which would tell a caller "nothing is here" when
/// the true story is "you cannot see here" — the single most likely
/// confusion this Platform can produce, per #103's own ticket text.
///
/// No retry button, unlike [PlatformFailureState]: retrying with the same
/// Grants answers exactly the same refusal, so the one useful next step is a
/// person to ask, not a button to press — this names who.
///
/// A caller reaches this class by a Bloc classifying its own failure as
/// scope-refused off the API exception's `statusCode == 403` (see
/// `WorkOrdersUnavailable.isScopeRefused` in `maintenance/work_orders_bloc.dart`
/// for the worked example) — never by matching the server's own wording, so
/// the client is not coupled to a sentence the server is free to reword.
class PlatformScopeRefusedState extends StatelessWidget {
  const PlatformScopeRefusedState({super.key, this.scopeName});

  /// The Org Unit (or other scope) the caller was asking about, when the
  /// caller knows it — "You have no Grant on Line 3 …" rather than the
  /// generic wording, the same way #103's own ticket text phrases the
  /// example. Null falls back to the generic phrasing when the Screen has
  /// nothing more specific to name.
  final String? scopeName;

  String get _message {
    final scope = scopeName;
    return scope == null
        ? 'You have no Grant reaching here — ask an administrator to widen your Approval.'
        : 'You have no Grant on $scope — ask an administrator to widen your Approval.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = _message;
    return Semantics(
      liveRegion: true,
      label: 'Not visible to you. $message',
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(Spacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Deliberately not `cloud_off_outlined` — an ordinary
                // failure and a scope refusal must be visually distinct at
                // a glance, not only in their copy, so a caller who is
                // pattern-matching the icon before reading the sentence
                // still tells the two apart.
                Icon(Icons.lock_outline, size: 48, color: AppColors.statusWarning),
                const SizedBox(height: Spacing.md),
                Text('Not visible to you', style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
                const SizedBox(height: Spacing.sm),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: AppTypography.body(context)?.copyWith(color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
