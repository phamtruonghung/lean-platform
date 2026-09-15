/// One Action, and — as each later ticket lands — the PDCA cycle it is running
/// and the measures answering it (issue #176).
///
/// A Screen with its own address rather than a dialog, for the reason the Work
/// order detail Screen gives: this is what a person links to when they want
/// somebody else to look at one concern, and a dialog's address is not
/// something you send to a colleague.
library;

import 'package:flutter/material.dart' hide Action;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../platform/router.dart';
import '../status_tone.dart';
import '../theme.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/status_chip.dart';
import 'action.dart';
import 'action_detail_bloc.dart';

class ActionDetailScreen extends StatelessWidget {
  const ActionDetailScreen({super.key, required this.actionId});

  /// The Action this address names — carried down from the route rather than
  /// re-read off the Bloc, so a retry asks for the same Action the address did.
  final String actionId;

  static const double maxWidth = 900;
  static const ValueKey<String> retryKey = ValueKey<String>('action-detail-retry');
  static const ValueKey<String> failedKey = ValueKey<String>('action-detail-failed');
  static const ValueKey<String> loadedKey = ValueKey<String>('action-detail-loaded');
  static const ValueKey<String> backKey = ValueKey<String>('action-detail-back');
  static const ValueKey<String> measuresEmptyKey = ValueKey<String>('action-detail-measures-empty');
  static const ValueKey<String> completePhaseKey = ValueKey<String>('action-detail-complete-phase');
  static const ValueKey<String> cycleHistoryKey = ValueKey<String>('action-detail-cycle-history');
  static const ValueKey<String> noticeKey = ValueKey<String>('action-detail-notice');
  static const ValueKey<String> cancelKey = ValueKey<String>('action-detail-cancel');
  static const ValueKey<String> escalateKey = ValueKey<String>('action-detail-escalate');

  static const ValueKey<String> addMeasureKey = ValueKey<String>('action-detail-add-measure');
  static const ValueKey<String> measuresHeadingKey = ValueKey<String>('action-detail-measures');
  static ValueKey<String> addMeasureKindKey(String wire) =>
      ValueKey<String>('action-detail-add-measure-$wire');
  static ValueKey<String> measureKey(String id) => ValueKey<String>('action-measure-$id');
  static const ValueKey<String> parentKey = ValueKey<String>('action-detail-parent');
  static ValueKey<String> phaseKey(int cycle, String phase) =>
      ValueKey<String>('action-phase-$cycle-$phase');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ActionDetailBloc>().state;

    return Scaffold(
      body: switch (state) {
        ActionDetailLoading() => const SkeletonList(rows: 5, maxWidth: maxWidth),
        ActionDetailUnavailable(message: final message) => PlatformFailureState(
            key: failedKey,
            title: 'That Action could not be read',
            message: message,
            retryKey: retryKey,
            onRetry: () => context.read<ActionDetailBloc>().add(ActionDetailStarted(actionId)),
          ),
        ActionDetailLoaded(action: final action, notice: final notice) =>
          _ActionDetail(action: action, notice: notice),
      },
    );
  }
}

class _ActionDetail extends StatelessWidget {
  const _ActionDetail({required this.action, this.notice});

  final Action action;

  /// What the last phase completion had to say for itself, read off the state
  /// because the dialog that asked has closed by the time it is worth showing.
  ///
  /// A *refusal* is deliberately not repeated here: the dialog that asked stays
  /// open with the reason in it, so a second copy on the Screen underneath is
  /// one message with two mouths. (`ActionDetailLoaded.completionFailure` is
  /// what that dialog listens for.)
  final String? notice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: ActionDetailScreen.maxWidth),
        child: ListView(
          key: ActionDetailScreen.loadedKey,
          padding: const EdgeInsets.all(Spacing.xl),
          children: [
            Row(
              children: [
                TextButton.icon(
                  key: ActionDetailScreen.backKey,
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back'),
                ),
                const Spacer(),
                StatusChip(
                  label: action.statusLabel,
                  tone: action.statusTone,
                ),
              ],
            ),
            const SizedBox(height: Spacing.md),
            Row(
              children: [
                // Expanded rather than a Spacer: the number is what gives way
                // when the two actions beside it need the width, not the Row.
                Expanded(
                  child: Text(action.actionNo, style: theme.textTheme.labelLarge),
                ),
                // Both offered while the Action is still live, and neither for
                // one that has ended: a closed or cancelled record has nothing
                // left to hand up or call off, and both addresses refuse it
                // anyway (issues #179 and #180).
                if (!const {'done', 'cancelled'}.contains(action.status))
                  TextButton(
                    key: ActionDetailScreen.escalateKey,
                    onPressed: () => context.go('${Routes.actions}/${action.id}/escalate'),
                    child: const Text('Hand it up…'),
                  ),
                if (!const {'done', 'cancelled'}.contains(action.status))
                  TextButton(
                    key: ActionDetailScreen.cancelKey,
                    onPressed: () => context.go('${Routes.actions}/${action.id}/cancel'),
                    child: const Text('Call it off…'),
                  ),
              ],
            ),
            const SizedBox(height: Spacing.xs),
            Text(action.title, style: theme.textTheme.headlineSmall),
            if (notice != null) ...[
              const SizedBox(height: Spacing.sm),
              Text(key: ActionDetailScreen.noticeKey, notice!, style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: Spacing.sm),
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                StatusChip(label: action.typeLabel, tone: action.statusTone),
                if (action.pillarCode != null) Chip(label: Text('Pillar ${action.pillarCode}')),
                Chip(label: Text(action.priorityLabel)),
                if (action.isOverdue)
                  StatusChip(label: 'Overdue by ${action.daysOverdue} days', tone: StatusTone.danger),
              ],
            ),
            if (action.description != null) ...[
              const SizedBox(height: Spacing.md),
              Text(action.description!, style: theme.textTheme.bodyMedium),
            ],
            if (action.parent != null) ...[
              const SizedBox(height: Spacing.md),
              _Parent(parent: action.parent!),
            ],
            const SizedBox(height: Spacing.lg),
            _Cycle(action: action),
            const SizedBox(height: Spacing.lg),
            _Facts(action: action),
            const SizedBox(height: Spacing.lg),
            _Measures(action: action),
          ],
        ),
      ),
    );
  }
}

/// The cycle the Action is running: the current round's four phases, the open
/// one marked and offered for completion, and every earlier round beneath it —
/// a Check that found it did not hold is why the Action is on its second turn,
/// and that record is the point of keeping the phases at all (ADR-0033).
class _Cycle extends StatelessWidget {
  const _Cycle({required this.action});

  final Action action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = action.currentCyclePhases;
    final earlier = [for (final phase in action.phases) if (phase.cycle != action.currentCycle) phase];
    final openPhase = action.openPhase;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Cycle ${action.currentCycle}',
              style: theme.textTheme.titleSmall,
            ),
            const Spacer(),
            if (openPhase != null)
              FilledButton.tonalIcon(
                key: ActionDetailScreen.completePhaseKey,
                onPressed: () => context.go(
                  '${Routes.actions}/${action.id}/phases/${openPhase.phase}/complete',
                ),
                icon: const Icon(Icons.check_circle_outline),
                label: Text('Complete the ${openPhase.phaseLabel}'),
              ),
          ],
        ),
        const SizedBox(height: Spacing.sm),
        if (current.isEmpty)
          Text(
            'This Action has no phases left.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        for (final phase in current) _PhaseRow(phase: phase),
        if (earlier.isNotEmpty) ...[
          const SizedBox(height: Spacing.lg),
          Text(
            key: ActionDetailScreen.cycleHistoryKey,
            'Earlier rounds',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: Spacing.sm),
          for (final phase in earlier) _PhaseRow(phase: phase, historical: true),
        ],
      ],
    );
  }
}

class _PhaseRow extends StatelessWidget {
  const _PhaseRow({required this.phase, this.historical = false});

  final ActionPhase phase;
  final bool historical;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      key: ActionDetailScreen.phaseKey(phase.cycle, phase.phase),
      padding: const EdgeInsets.symmetric(vertical: Spacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              historical ? '${phase.phaseLabel} · ${phase.cycle}' : phase.phaseLabel,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: phase.isOpen ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  phase.note ?? (phase.isOpen ? 'Open — waiting on this' : 'No note recorded'),
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: phase.isOpen ? null : muted),
                ),
                Text(
                  [
                    if (phase.ownerName != null) phase.ownerName!,
                    if (phase.dueDate != null) 'due ${phase.dueDate}',
                    if (phase.completedAt != null)
                      'done ${phase.completedAt!.toLocal().toIso8601String().substring(0, 10)}',
                    if (phase.outcomeLabel != null) phase.outcomeLabel!,
                  ].join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Facts extends StatelessWidget {
  const _Facts({required this.action});

  final Action action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Where it stands', style: theme.textTheme.titleSmall),
        const SizedBox(height: Spacing.sm),
        _Fact(label: 'Org Unit', value: action.orgUnitName),
        _Fact(label: 'Owner', value: action.ownerName ?? 'Nobody yet'),
        _Fact(label: 'Raised by', value: action.raisedByName ?? 'An Account with no Employee record'),
        _Fact(label: 'Due', value: action.dueDate ?? 'No due date'),
        if (action.escalatedToOrgUnitName != null)
          _Fact(label: 'Escalated to', value: action.escalatedToOrgUnitName!),
        if (action.closureNote != null) _Fact(label: 'Closing note', value: action.closureNote!),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 180,
            child: Text(
              label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// The Concern this Action answers (issue #178) — a measure's own Screen says
/// what it is about, and offers the way there.
class _Parent extends StatelessWidget {
  const _Parent({required this.parent});

  final ActionParent parent;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: ActionDetailScreen.parentKey,
      child: ListTile(
        onTap: () => context.go('${Routes.actions}/${parent.id}'),
        title: Text('Answers ${parent.actionNo}'),
        subtitle: Text(parent.title),
        trailing: StatusChip(label: parent.statusLabel, tone: parent.statusTone),
      ),
    );
  }
}

/// The measures answering this Action (issue #178): each one an Action of its
/// own, with its own cycle, listed containment first because that is what stops
/// the bleeding. The empty state is the honest one rather than a placeholder —
/// an Action with no measures is a real state, and for a Concern it is the state
/// that cannot be closed (issue #179 refuses exactly that).
class _Measures extends StatelessWidget {
  const _Measures({required this.action});

  final Action action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final measures = action.measures;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // `Expanded`, not a `Spacer`: the heading carries the counts, and
            // at a narrow width it wraps rather than pushing the menu button
            // off the edge.
            Expanded(
              child: Text(
                key: ActionDetailScreen.measuresHeadingKey,
                measures.isEmpty
                    ? 'Measures'
                    : 'Measures (${measures.length}, '
                        '${action.countermeasureCount} of them countermeasures)',
                style: theme.textTheme.titleSmall,
              ),
            ),
            // The kind is chosen by name rather than by a picker inside the
            // form: the three words mean three different pieces of work, and a
            // dropdown in the middle of a form invites the wrong one.
            PopupMenuButton<String>(
              key: ActionDetailScreen.addMeasureKey,
              enabled: !action.isMeasure,
              tooltip: 'Add a measure',
              onSelected: (measureType) => context.go(
                '${Routes.actions}/${action.id}/measures/$measureType/new',
              ),
              itemBuilder: (context) => [
                for (final measureType in actionMeasureTypeOrder)
                  PopupMenuItem<String>(
                    key: ActionDetailScreen.addMeasureKindKey(measureType),
                    value: measureType,
                    child: Text('Add a ${actionTypeLabel(measureType).toLowerCase()}…'),
                  ),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: Spacing.xs),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.add),
                    SizedBox(width: Spacing.xs),
                    Text('Add a measure'),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Spacing.sm),
        if (measures.isEmpty)
          Text(
            key: ActionDetailScreen.measuresEmptyKey,
            action.isMeasure
                ? 'This Action answers no Concern of its own.'
                : 'Nothing answers this yet. A containment stops the effect now; a countermeasure '
                    'removes the cause.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        for (final measure in measures)
          Card(
            key: ActionDetailScreen.measureKey(measure.id),
            margin: const EdgeInsets.only(bottom: Spacing.sm),
            child: ListTile(
              onTap: () => context.go('${Routes.actions}/${measure.id}'),
              title: Text(measure.title),
              subtitle: Text(
                [
                  measure.typeLabel,
                  measure.statusLabel,
                  measure.ownerName ?? 'Nobody yet',
                  if (measure.isOverdue) 'overdue by ${measure.daysOverdue} days',
                  if (measure.openPhase != null && !measure.isOverdue)
                    'waiting on its ${measure.openPhase!.phaseLabel.toLowerCase()}',
                ].join(' · '),
              ),
            ),
          ),
      ],
    );
  }
}
