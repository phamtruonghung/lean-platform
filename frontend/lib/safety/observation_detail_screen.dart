/// One Safety observation (issue #230): what was seen, where, when, and how
/// bad it could have been.
///
/// Readable by anyone who can see the Site (the server's own rule — Org Unit
/// scope decides where an Account may act, not what it may know about), so
/// this Screen gates nothing about reading it. There is no injury-style
/// restriction here the way `SafetyIncidentDetailScreen` has: an observation
/// names nobody's health information, so every field on the record renders
/// for every reader.
///
/// **An observation has no status, no event history and no closure** (#223
/// decision 9). This Screen offers nothing to change that fact directly, but
/// it does offer the one act that answers it: raising an Action from the
/// observation, in the action log (issue #231) — mirrors
/// `SafetyIncidentDetailScreen`'s own `_ConcernsCard` closely. Anyone who can
/// see the Site may raise one, whatever their Grants — the same weak
/// question the observation's own read already asks, never a Grant.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../platform/router.dart';
import '../theme.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/status_chip.dart';
import 'observation_detail_bloc.dart';
import 'safety_observation.dart';

class SafetyObservationDetailScreen extends StatelessWidget {
  const SafetyObservationDetailScreen({super.key, required this.observationId});

  final String observationId;

  static const double maxWidth = 900;

  static const ValueKey<String> backKey = ValueKey<String>('safety-observation-back');
  static const ValueKey<String> potentialKey =
      ValueKey<String>('safety-observation-detail-potential');
  static const ValueKey<String> stopWorkKey =
      ValueKey<String>('safety-observation-detail-stop-work');
  static const ValueKey<String> filedKey = ValueKey<String>('safety-observation-detail-filed');
  static const ValueKey<String> failedKey = ValueKey<String>('safety-observation-detail-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('safety-observation-detail-retry');
  static const ValueKey<String> missingKey = ValueKey<String>('safety-observation-detail-missing');

  // The Actions raised from this observation (issue #231): the section, its
  // empty state, one row per Action, the notice from the last raise, and the
  // control that raises one.
  static const ValueKey<String> actionsKey = ValueKey<String>('safety-observation-detail-actions');
  static const ValueKey<String> noActionsKey =
      ValueKey<String>('safety-observation-detail-no-actions');
  static const ValueKey<String> raiseActionKey =
      ValueKey<String>('safety-observation-detail-raise-action');
  static const ValueKey<String> actionNoticeKey =
      ValueKey<String>('safety-observation-detail-action-notice');

  static ValueKey<String> actionRowKey(String id) =>
      ValueKey<String>('safety-observation-action-$id');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SafetyObservationDetailBloc>().state;

    return Scaffold(
      body: switch (state) {
        SafetyObservationDetailLoading() => const SkeletonList(rows: 4, maxWidth: maxWidth),
        SafetyObservationDetailUnavailable(isMissing: true) => PlatformEmptyState.noneExist(
            key: missingKey,
            title: 'No such Safety observation',
            message: 'Nothing is recorded at this address. It may have been removed, or '
                'the address may be wrong.',
            icon: Icons.search_off_outlined,
            actionLabel: 'Back to Safety observations',
            actionKey: backKey,
            onAction: () => context.go(Routes.safetyObservations),
          ),
        SafetyObservationDetailUnavailable(message: final message) => PlatformFailureState(
            key: failedKey,
            title: 'The Safety observation could not be read',
            message: message,
            retryKey: retryKey,
            onRetry: () => context
                .read<SafetyObservationDetailBloc>()
                .add(const SafetyObservationDetailRefreshed()),
          ),
        SafetyObservationDetailLoaded() => _Loaded(state: state),
      },
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({required this.state});

  final SafetyObservationDetailLoaded state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final row = state.observation;

    return Center(
      child: AppPageFrame(
        maxWidth: SafetyObservationDetailScreen.maxWidth,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xl),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: SafetyObservationDetailScreen.backKey,
                onPressed: () => context.go(Routes.safetyObservations),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back to Safety observations'),
              ),
            ),
            const SizedBox(height: Spacing.sm),
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(row.observationTypeLabel, style: theme.textTheme.headlineSmall),
                StatusChip(
                  key: SafetyObservationDetailScreen.potentialKey,
                  label: row.severityPotentialLabel,
                  tone: row.severityPotentialTone,
                ),
                if (row.isStopWork)
                  Chip(
                    key: SafetyObservationDetailScreen.stopWorkKey,
                    label: const Text('Stop-work'),
                  ),
              ],
            ),
            const SizedBox(height: Spacing.lg),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Spacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('What was seen', style: theme.textTheme.titleMedium),
                    const SizedBox(height: Spacing.sm),
                    _Fact(label: 'Category', value: row.categoryLabel),
                    _Fact(label: 'Org Unit', value: row.orgUnitName),
                    _Fact(
                      label: 'Filed against',
                      key: SafetyObservationDetailScreen.filedKey,
                      value: row.filedAgainst,
                    ),
                    _Fact(label: 'Observed at', value: row.observedAt ?? 'Not recorded'),
                    _Fact(label: 'Description', value: row.description ?? 'None given'),
                    _Fact(
                      label: 'Action taken',
                      value: row.actionTaken ?? 'None recorded yet',
                    ),
                    _Fact(label: 'Recorded by', value: row.recordedByLabel),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Spacing.lg),
            // What is being done about it (issue #231). Below the record's
            // own story, the same order the Safety incident Screen keeps for
            // its own Concern card: the observation itself comes first, the
            // work that answers it second.
            _ActionsCard(
              observation: row,
              notice: state.notice,
              busy: state.isRaisingAction,
            ),
          ],
        ),
      ),
    );
  }
}

/// The Actions raised from this observation (issue #231) — mirrors
/// `SafetyIncidentDetailScreen`'s own `_ConcernsCard` shape closely: the card
/// is drawn even when there is nothing, because "nobody has picked this up
/// yet" is a state a reader of an observation needs to see, and the control
/// that changes it (raising an Action) sits exactly there. Anyone who can see
/// the Site may raise one — a Grant is not asked here or by the server
/// (#231's own acceptance criterion for this path, the same weak question the
/// observation's own read already asks).
class _ActionsCard extends StatelessWidget {
  const _ActionsCard({required this.observation, required this.busy, this.notice});

  final SafetyObservation observation;

  /// The raise is in flight: the control goes quiet so a second one cannot be
  /// started against the observation mid-change.
  final bool busy;

  /// What the last raise had to say for itself, from the Bloc's own state —
  /// the dialog that asked has closed by the time it is worth reading.
  final String? notice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actions = observation.actions;

    return Card(
      key: SafetyObservationDetailScreen.actionsKey,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Closing the loop', style: theme.textTheme.titleMedium),
            const SizedBox(height: Spacing.xs),
            Text(
              'The observation itself is recorded here; what somebody does about it is owned '
              'in the action log, as an Action.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (notice != null) ...[
              const SizedBox(height: Spacing.sm),
              Text(
                key: SafetyObservationDetailScreen.actionNoticeKey,
                notice!,
                style: theme.textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: Spacing.sm),
            if (actions.isEmpty)
              Text(
                key: SafetyObservationDetailScreen.noActionsKey,
                'Nothing is being done about this yet.',
                style: theme.textTheme.bodyMedium,
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final action in actions)
                    // `ListTile` carries the row's own `Key`, so a test finds
                    // the row by the Action's id rather than by its text.
                    Card(
                      key: SafetyObservationDetailScreen.actionRowKey(action.id),
                      margin: const EdgeInsets.only(bottom: Spacing.sm),
                      child: ListTile(
                        onTap: () => context.go('${Routes.actions}/${action.id}'),
                        title: Text(action.title),
                        subtitle: Text(
                          [
                            action.actionNo,
                            action.typeLabel,
                            if (action.ownerName != null) action.ownerName!,
                            if (action.isOverdue) 'overdue',
                          ].join(' · '),
                        ),
                        trailing: StatusChip(
                          label: action.statusLabel,
                          tone: action.statusTone,
                        ),
                      ),
                    ),
                ],
              ),
            const SizedBox(height: Spacing.sm),
            FilledButton.icon(
              key: SafetyObservationDetailScreen.raiseActionKey,
              onPressed: busy
                  ? null
                  : () => context.go('${Routes.safetyObservations}/${observation.id}/raise-action'),
              icon: const Icon(Icons.assignment_add),
              label: const Text('Raise an Action'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.xxs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          Text(value, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
