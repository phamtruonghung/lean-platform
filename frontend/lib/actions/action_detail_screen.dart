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
import '../widgets/app_page_frame.dart';
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
  static const ValueKey<String> measuresHintKey = ValueKey<String>('action-detail-measures-hint');

  static ValueKey<String> measureCompleteKey(String id) =>
      ValueKey<String>('action-detail-measure-complete-$id');
  static const ValueKey<String> completePhaseKey = ValueKey<String>('action-detail-complete-phase');
  static const ValueKey<String> cycleHistoryKey = ValueKey<String>('action-detail-cycle-history');
  static const ValueKey<String> noticeKey = ValueKey<String>('action-detail-notice');
  static const ValueKey<String> cancelKey = ValueKey<String>('action-detail-cancel');
  static const ValueKey<String> escalateKey = ValueKey<String>('action-detail-escalate');

  /// The CAPA opened on this Concern, or the way to open one (issue #209):
  /// whether the problem is under investigation is a fact about this record, so
  /// it reads here rather than on a Screen of its own.
  static const ValueKey<String> capaKey = ValueKey<String>('action-detail-capa');
  static const ValueKey<String> openCapaKey = ValueKey<String>('action-detail-open-capa');
  static const ValueKey<String> capaLinkKey = ValueKey<String>('action-detail-capa-link');
  static const ValueKey<String> noCapaKey = ValueKey<String>('action-detail-no-capa');

  static const ValueKey<String> addMeasureKey = ValueKey<String>('action-detail-add-measure');
  static const ValueKey<String> measuresHeadingKey = ValueKey<String>('action-detail-measures');

  /// The Non-conformances this Concern answers (issue #208): the section, its
  /// empty state, one row per occurrence and the row's own unlink control.
  static const ValueKey<String> nonconformancesKey =
      ValueKey<String>('action-detail-nonconformances');
  static const ValueKey<String> noNonconformancesKey =
      ValueKey<String>('action-detail-no-nonconformances');
  static const ValueKey<String> raisedFromKey = ValueKey<String>('action-detail-raised-from');

  static ValueKey<String> nonconformanceKey(String id) =>
      ValueKey<String>('action-nonconformance-$id');

  static ValueKey<String> unlinkNonconformanceKey(String id) =>
      ValueKey<String>('action-nonconformance-unlink-$id');

  /// The Safety incident this Concern was raised from, if it was raised from
  /// one (issue #229) — the section a Concern renders instead of
  /// [nonconformancesKey], never both (the single-source rule).
  static const ValueKey<String> safetyIncidentKey =
      ValueKey<String>('action-detail-safety-incident');

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
      child: AppPageFrame(
        maxWidth: ActionDetailScreen.maxWidth,
        child: ListView(
          key: ActionDetailScreen.loadedKey,
          padding: const EdgeInsets.all(Spacing.xl),
          children: [
            // A `Wrap`, not a `Row`: the back label is a Destination's name and
            // the status chip is a word, and together they are wider than an
            // 800px window — where a `Row` overflows and a `Wrap` puts the chip
            // on its own line. `spaceBetween` keeps the chip hard right at every
            // width the app is used at.
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: Spacing.sm,
              runSpacing: Spacing.sm,
              children: [
                // `context.go`, never `maybePop`: every navigation in this
                // Platform replaces the location rather than pushing a page
                // (Work orders, the Directory, this Module), so there is
                // nothing on the Navigator to pop and `maybePop` is a button
                // that does nothing at all — which is exactly how it behaved on
                // the deployed stack (issue #183). WorkOrderDetailScreen's own
                // "Back to Work orders" is the convention this copies.
                TextButton.icon(
                  key: ActionDetailScreen.backKey,
                  onPressed: () => context.go(Routes.actions),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back to the action log'),
                ),
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
            // The investigation this Concern has been turned into, if any
            // (issue #209) — only a Concern can be under one, because that is
            // what a CAPA is opened on.
            if (action.actionType == 'concern') ...[
              const SizedBox(height: Spacing.lg),
              _Capa(action: action),
            ],
            const SizedBox(height: Spacing.lg),
            _Measures(action: action),
            const SizedBox(height: Spacing.lg),
            // The evidence behind the Concern, at the foot of the record on
            // purpose: the cycle and the work answering it are what was asked
            // for first, and the source is what proves the problem is real. A
            // Concern raised from the register has neither, and the empty
            // state says so rather than leaving a blank. The single-source
            // rule (`action_items_single_source`) means a Concern is never
            // both, so exactly one of the two renders (issue #229).
            if (action.safetyIncident != null)
              _SafetyIncidentSource(action: action)
            else
              _Nonconformances(action: action),
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

/// The CAPA opened on this Concern (issue #209, ADR-0034), or the way to open
/// one — and nothing at all when the caller holds no Quality authority, which
/// is the rule ADR-0035 and issue #48 set: a CAPA is opened by judgement, not
/// by anybody.
///
/// A Concern that already has one shows it rather than the button, because a
/// second is refused (409) and offering a control the server will refuse is a
/// worse interface than naming the investigation that exists.
class _Capa extends StatelessWidget {
  const _Capa({required this.action});

  final Action action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final capa = action.capa;
    // Read here, in a build, rather than passed in from the route: a value
    // computed when the route first built would freeze the Account state as it
    // was before `/me` answered, and a holder of Quality authority would never
    // be offered the act that authority gates (ADR-0035).
    final canOpen = holdsQualityAuthority(context, action.orgUnitId);

    return Column(
      key: ActionDetailScreen.capaKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('CAPA', style: theme.textTheme.titleSmall),
        const SizedBox(height: Spacing.xs),
        Text(
          'A formal 8D investigation opened on this Concern: its team, its problem description '
          'and — as those slices land — its root causes and its effectiveness check. Its actions '
          'are the ones below, recorded once in the action log and read there.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: Spacing.sm),
        if (capa != null)
          Card(
            key: ActionDetailScreen.capaLinkKey,
            child: ListTile(
              onTap: () => context.go('${Routes.actions}/capas/${capa.id}'),
              title: Text('Under investigation: ${capa.capaNo}'),
              subtitle: Text(action.title),
              trailing: StatusChip(label: capa.statusLabel, tone: capa.statusTone),
            ),
          )
        else if (canOpen)
          FilledButton.tonal(
            key: ActionDetailScreen.openCapaKey,
            onPressed: () => context.go('${Routes.actions}/${action.id}/capa'),
            child: const Text('Open a CAPA…'),
          )
        else
          Text(
            key: ActionDetailScreen.noCapaKey,
            "Nobody has opened a CAPA on this Concern. Opening one needs Quality authority at "
            "this Concern's Org Unit.",
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
      ],
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
        if (measures.isNotEmpty) ...[
          const SizedBox(height: Spacing.xs),
          // The sentence the deployed stack was missing (issue #183): a reader
          // who has just been refused by the Act needs to be told what closes a
          // measure, and that it is something they can go and do.
          Text(
            key: ActionDetailScreen.measuresHintKey,
            'Each measure is an Action of its own: open one and run its own cycle to its Act, and '
            'it counts as closed.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
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
              // Where the work is, on the row itself: a measure waiting on a
              // phase offers that phase's completion, addressed at the
              // measure's own Action — the same dialog it would get two taps
              // later, one tap earlier, which is what the deployed stack's
              // reader went looking for and did not find (issue #183). A
              // measure with nothing open still opens, with the chevron the
              // register's own rows carry.
              trailing: measure.openPhase == null
                  ? const Icon(Icons.chevron_right)
                  : TextButton(
                      key: ActionDetailScreen.measureCompleteKey(measure.id),
                      onPressed: () => context.go(
                        '${Routes.actions}/${measure.id}/phases/'
                        '${measure.openPhase!.phase}/complete',
                      ),
                      child: Text('Complete the ${measure.openPhase!.phaseLabel}…'),
                    ),
              subtitle: Text(
                [
                  measure.typeLabel,
                  measure.statusLabel,
                  measure.ownerName ?? 'Nobody yet',
                  // Two different facts, so both: when it is due and what it is
                  // waiting on. (They used to be exclusive, which hid the phase
                  // of exactly the measures a reader is most likely to be
                  // looking for.)
                  if (measure.isOverdue) 'overdue by ${measure.daysOverdue} days',
                  if (measure.openPhase != null)
                    'waiting on its ${measure.openPhase!.phaseLabel.toLowerCase()}',
                ].join(' · '),
              ),
            ),
          ),
      ],
    );
  }
}

/// The Non-conformances this Concern answers (issue #208) — the record it was
/// raised from first, then every occurrence gathered to it since. Each row is
/// a link to the Non-conformance's own address, which is the half of "each
/// record shows the other" that lives on this Screen; the source row says so
/// and offers no unlink, because the service refuses that one.
///
/// The row carries the four facts a reader of a Concern needs — the number,
/// the Product, the Defect code and the quantity — and deliberately no status
/// chip: that vocabulary is the Quality Module's, this Module does not import
/// it (the dependency runs the other way, see `actions.dart`), and the row's
/// own address is where the record's state is read.
class _Nonconformances extends StatelessWidget {
  const _Nonconformances({required this.action});

  final Action action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final occurrences = action.nonconformances;
    final live = !const {'done', 'cancelled'}.contains(action.status);

    return Column(
      key: ActionDetailScreen.nonconformancesKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          occurrences.isEmpty ? 'Non-conformances' : 'Non-conformances (${occurrences.length})',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: Spacing.xs),
        Text(
          'The occurrences this Concern answers. One problem that shows up several times stays one '
          'Concern, so a further occurrence is linked here rather than raised as another.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: Spacing.sm),
        if (occurrences.isEmpty)
          Text(
            key: ActionDetailScreen.noNonconformancesKey,
            'No Non-conformance is linked to this Concern.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        for (final occurrence in occurrences)
          Card(
            key: ActionDetailScreen.nonconformanceKey(occurrence.id),
            margin: const EdgeInsets.only(bottom: Spacing.sm),
            child: ListTile(
              onTap: () => context.go('${Routes.nonConformances}/${occurrence.id}'),
              title: Text(occurrence.issueNo),
              subtitle: Text(
                [
                  occurrence.productLabel,
                  occurrence.defectCodeLabel,
                  occurrence.quantityLabel,
                ].join(' · '),
              ),
              trailing: occurrence.isSource
                  ? TextButton(
                      key: ActionDetailScreen.raisedFromKey,
                      onPressed: () => context.go('${Routes.nonConformances}/${occurrence.id}'),
                      child: const Text('Raised from this'),
                    )
                  // Offered only while the Concern is still live: a link on a
                  // closed problem is history, and an ended Action is not
                  // offered its own transition controls either.
                  : live
                      ? TextButton(
                          key: ActionDetailScreen.unlinkNonconformanceKey(occurrence.id),
                          onPressed: () => context.go(
                            '${Routes.actions}/${action.id}/nonconformances/'
                            '${occurrence.id}/unlink',
                          ),
                          child: const Text('Unlink…'),
                        )
                      : const Icon(Icons.chevron_right),
            ),
          ),
      ],
    );
  }
}

/// The words this Screen prints for a Safety incident's severity level (issue
/// #229) — a deliberate second copy of the Safety Module's own map, the same
/// trade `capa_report_screen.dart`'s own `_severityLabels` makes and for the
/// same reason: the ladder's words belong to `safety`, whose client entry
/// point this Module does not import (the dependency runs one way — see
/// `actions.dart`).
const Map<String, String> _severityLabels = {
  'near_miss': 'No injury',
  'first_aid': 'First aid',
  'medical_treatment': 'Medical treatment',
  'restricted_work': 'Restricted work',
  'lost_time': 'Lost time',
  'fatality': 'Fatality',
};

/// The Safety incident this Concern was raised from (issue #229) — the mirror
/// of `_Nonconformances` for the other source a Concern may carry. One row,
/// linking to the incident's own address, naming its number and severity and
/// **never its injury details**: this Module's own read selects neither the
/// identified Employee, the Injury type nor the Body part (`actions.js`'s
/// header explains why), so there is nothing here that could leak them.
class _SafetyIncidentSource extends StatelessWidget {
  const _SafetyIncidentSource({required this.action});

  final Action action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final incident = action.safetyIncident!;

    return Column(
      key: ActionDetailScreen.safetyIncidentKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Safety incident', style: theme.textTheme.titleSmall),
        const SizedBox(height: Spacing.xs),
        Text(
          'The incident this Concern was raised from — its number and its severity, never who '
          'was hurt or their diagnosis.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: Spacing.sm),
        Card(
          child: ListTile(
            onTap: () => context.go('${Routes.safetyIncidents}/${incident.id}'),
            title: Text(incident.incidentNo),
            subtitle: Text(_severityLabels[incident.severityLevel] ?? incident.severityLevel),
            trailing: const Icon(Icons.chevron_right),
          ),
        ),
      ],
    );
  }
}
