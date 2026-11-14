/// One Safety observation (issue #230): what was seen, where, when, and how
/// bad it could have been.
///
/// **The page head** is `AppPageHeader('Safety observation')`, drawn above the
/// state switch so every state carries it — the loading skeleton, a failed
/// read, the missing record and the loaded record alike (issue #391's design
/// law 3: one page rhythm; the shape the Non-conformance and Work order detail
/// Screens keep). What the record *is* — its type, its severity potential, the
/// stop-work badge — is the summary card's first line, never the page's title.
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

import '../l10n/app_localizations.dart';
import '../platform/router.dart';
import '../theme.dart';
import '../widgets/app_detail_section.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/app_page_header.dart';
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
  static const ValueKey<String> summaryKey =
      ValueKey<String>('safety-observation-detail-summary');
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
    final l10n = AppLocalizations.of(context);
    final state = context.watch<SafetyObservationDetailBloc>().state;

    // The page head sits above the state switch, so a load, a failed read, a
    // missing record and the record itself all carry the same title row and
    // back control (issue #391's design law 3). The missing state is the one
    // state whose back control belongs to its empty state — that state already
    // offers exactly this control under [SafetyObservationDetailScreen.backKey],
    // and two widgets may not share one key.
    final missing = state is SafetyObservationDetailUnavailable && state.isMissing;

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Head(showBack: !missing),
          Expanded(
            child: switch (state) {
              SafetyObservationDetailLoading() =>
                const SkeletonList(rows: 4, maxWidth: maxWidth),
              SafetyObservationDetailUnavailable(isMissing: true) =>
                PlatformEmptyState.noneExist(
                  key: missingKey,
                  title: l10n.observationDetailNoSuchSafetyObservation,
                  message: l10n.nonconformanceDetailMissingMessage,
                  icon: Icons.search_off_outlined,
                  actionLabel: l10n.observationDetailBackToSafetyObservations,
                  actionKey: backKey,
                  onAction: () => context.go(Routes.safetyObservations),
                ),
              SafetyObservationDetailUnavailable(message: final message) => PlatformFailureState(
                  key: failedKey,
                  title: l10n.observationDetailTheSafetyObservationCouldNotBeRead,
                  message: message,
                  retryKey: retryKey,
                  onRetry: () => context
                      .read<SafetyObservationDetailBloc>()
                      .add(const SafetyObservationDetailRefreshed()),
                ),
              SafetyObservationDetailLoaded() => _Loaded(state: state),
            },
          ),
        ],
      ),
    );
  }
}

/// The page's own title row: the way back, then `AppPageHeader`. It lives above
/// the state switch, so the loading, failed, missing and loaded states are told
/// apart by their body and never by a missing page head.
class _Head extends StatelessWidget {
  const _Head({this.showBack = true});

  /// False in the missing state, whose empty state carries the back control
  /// under the same [SafetyObservationDetailScreen.backKey].
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: AppPageFrame(
        maxWidth: SafetyObservationDetailScreen.maxWidth,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showBack) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: SafetyObservationDetailScreen.backKey,
                    onPressed: () => context.go(Routes.safetyObservations),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(AppTouchTarget.min, AppTouchTarget.min),
                    ),
                    icon: const Icon(Icons.arrow_back),
                    label: Text(l10n.observationDetailBackToSafetyObservations),
                  ),
                ),
                const SizedBox(height: Spacing.sm),
              ],
              AppPageHeader(title: l10n.titleSafetyObservation),
            ],
          ),
        ),
      ),
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({required this.state});

  final SafetyObservationDetailLoaded state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final row = state.observation;

    return Center(
      child: AppPageFrame(
        maxWidth: SafetyObservationDetailScreen.maxWidth,
        child: ListView(
          // The page head above this list already pads the top (`Spacing.xl`)
          // and the space beneath itself (`Spacing.lg`).
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
          children: [
            // The summary card first — what the record *is* (its type, its
            // severity potential, the stop-work badge), then where, when and
            // what kind (issue #391; the shape S4's own Summary card keeps).
            _SummaryCard(observation: row),
            const SizedBox(height: Spacing.md),
            AppDetailSection(
              title: l10n.safetyWhatWasSeen,
              children: [
                    _Fact(label: l10n.commonDescription, value: row.description ?? 'None given'),
                    _Fact(
                      label: l10n.observationDetailActionTaken,
                      value: row.actionTaken ?? 'None recorded yet',
                    ),
                    _Fact(label: l10n.observationDetailRecordedBy, value: row.recordedByLabel),
              ],
            ),
            // What is being done about it (issue #231). Below the record's
            // own story, the same order the Safety incident Screen keeps for
            // its own Concern card: the observation itself comes first, the
            // work that answers it second.
            const SizedBox(height: Spacing.md),
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

/// What the record *is*, at the top of the page's first card: the observation's
/// type, its severity potential and — where it applies — the stop-work badge,
/// then the summary facts beneath. (Issue #391's design law 3, and the shape
/// S4's own Summary card keeps: the page title names the Screen, never the
/// record.)
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.observation});

  final SafetyObservation observation;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Card(
      key: SafetyObservationDetailScreen.summaryKey,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // A `Wrap`: the type and its badges must not overflow at a narrow
            // width, and the observation's own type is what a reader looks for.
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(observation.observationTypeLabel, style: theme.textTheme.headlineSmall),
                StatusChip(
                  key: SafetyObservationDetailScreen.potentialKey,
                  label: observation.severityPotentialLabel,
                  tone: observation.severityPotentialTone,
                ),
                if (observation.isStopWork)
                  Chip(
                    key: SafetyObservationDetailScreen.stopWorkKey,
                    label: Text(l10n.safetyStopWork),
                  ),
              ],
            ),
            const SizedBox(height: Spacing.md),
            Text(l10n.commonSummary, style: theme.textTheme.titleMedium),
            const SizedBox(height: Spacing.sm),
            _Fact(label: l10n.commonCategory, value: observation.categoryLabel),
            _Fact(label: l10n.commonOrgUnit, value: observation.orgUnitName),
            _Fact(
              label: l10n.nonconformanceDetailFiledAgainst,
              key: SafetyObservationDetailScreen.filedKey,
              value: observation.filedAgainst,
            ),
            _Fact(label: l10n.observationDetailObservedAt, value: observation.observedAt ?? 'Not recorded'),
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
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final actions = observation.actions;

    return AppDetailSection(
      key: SafetyObservationDetailScreen.actionsKey,
      title: l10n.observationDetailClosingTheLoop,
      children: [
            Text(
              l10n.observationDetailTheObservationItselfIsRecordedHereWhat,
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
                l10n.observationDetailNothingIsBeingDoneAboutThisYet,
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
                            if (action.isOverdue) l10n.nonconformanceDetailOverdue,
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
              label: Text(l10n.commonRaiseAnAction),
            ),
      ],
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
