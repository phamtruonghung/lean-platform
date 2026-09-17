/// One CAPA (issue #209): the investigation opened on a Concern — its number,
/// its team, what the investigation says the problem is, and the Concern's own
/// Containments, Countermeasures and Preventive actions with their PDCA phases.
///
/// A Screen with its own address rather than a dialog, for the reason the
/// Action detail Screen gives: this is what somebody sends to a colleague when
/// they want a second pair of eyes on an investigation, and a dialog's address
/// is not something you send to anybody.
///
/// **What is deliberately not here.** The team and the problem description are
/// *changed* over HTTP (`PATCH /api/actions/capas/:id`, proved in
/// `backend/test/integration/capas.test.js`) but this slice gives no control
/// for changing them: #209's own ticket asks for two Screens — opening one and
/// reading one — and an edit form that could set a team is the same form the
/// open dialog already is. What this Screen owes a reader is the record, and
/// the ADR-0034 shape of it: no second list of the work, because the Concern's
/// measures *are* the work.
library;

import 'package:flutter/material.dart' hide Action;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../platform/router.dart';
import '../theme.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/status_chip.dart';
import 'action.dart';
import 'capa.dart';
import 'capa_detail_bloc.dart';

class CapaDetailScreen extends StatelessWidget {
  const CapaDetailScreen({super.key, required this.capaId});

  /// The CAPA this address names — carried down from the route rather than
  /// re-read off the Bloc, so a retry asks for the same record.
  final String capaId;

  /// The page's own width. The Action detail Screen's 900, because this is the
  /// same kind of page: one record, read top to bottom.
  static const double maxWidth = 900;

  static const ValueKey<String> loadedKey = ValueKey<String>('capa-detail-loaded');
  static const ValueKey<String> failedKey = ValueKey<String>('capa-detail-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('capa-detail-retry');
  static const ValueKey<String> backKey = ValueKey<String>('capa-detail-back');
  static const ValueKey<String> problemKey = ValueKey<String>('capa-detail-problem');
  static const ValueKey<String> noProblemKey = ValueKey<String>('capa-detail-no-problem');
  static const ValueKey<String> teamKey = ValueKey<String>('capa-detail-team');
  static const ValueKey<String> noTeamKey = ValueKey<String>('capa-detail-no-team');
  static const ValueKey<String> concernKey = ValueKey<String>('capa-detail-concern');
  static const ValueKey<String> measuresKey = ValueKey<String>('capa-detail-measures');
  static const ValueKey<String> noMeasuresKey = ValueKey<String>('capa-detail-no-measures');

  static ValueKey<String> measureKey(String id) => ValueKey<String>('capa-measure-$id');

  static ValueKey<String> measurePhaseKey(String measureId, int cycle, String phase) =>
      ValueKey<String>('capa-measure-$measureId-phase-$cycle-$phase');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CapaDetailBloc>().state;

    return Scaffold(
      body: switch (state) {
        CapaDetailLoading() => const SkeletonList(rows: 5, maxWidth: maxWidth),
        CapaDetailUnavailable(message: final message) => PlatformFailureState(
            key: failedKey,
            title: 'That CAPA could not be read',
            message: message,
            retryKey: retryKey,
            onRetry: () => context.read<CapaDetailBloc>().add(CapaDetailStarted(capaId)),
          ),
        CapaDetailLoaded(capa: final capa) => _CapaDetail(capa: capa),
      },
    );
  }
}

class _CapaDetail extends StatelessWidget {
  const _CapaDetail({required this.capa});

  final Capa capa;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final concern = capa.concern;
    // Where "back" goes is the Concern, because that is where this Screen was
    // opened from and where the problem lives. A CAPA whose Concern could not
    // be read (a row written outside the service, which the link's own
    // uniqueness makes impossible through the API) falls back to the log rather
    // than to a dead address.
    final backTarget = concern == null ? Routes.actions : '${Routes.actions}/${concern.id}';

    return Center(
      child: AppPageFrame(
        maxWidth: CapaDetailScreen.maxWidth,
        child: ListView(
          key: CapaDetailScreen.loadedKey,
          padding: const EdgeInsets.all(Spacing.xl),
          children: [
            // A `Wrap`, not a `Row`: the back label and the status chip are
            // wider together than an 800px window, and a `Wrap` puts the chip
            // on its own line rather than overflowing.
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: Spacing.sm,
              runSpacing: Spacing.sm,
              children: [
                TextButton.icon(
                  key: CapaDetailScreen.backKey,
                  onPressed: () => context.go(backTarget),
                  icon: const Icon(Icons.arrow_back),
                  label: Text(
                    concern == null ? 'Back to the action log' : 'Back to ${concern.actionNo}',
                  ),
                ),
                StatusChip(label: capa.statusLabel, tone: capa.statusTone),
              ],
            ),
            const SizedBox(height: Spacing.md),
            Text(capa.capaNo, style: theme.textTheme.labelLarge),
            const SizedBox(height: Spacing.xs),
            Text(capa.title, style: theme.textTheme.headlineSmall),
            const SizedBox(height: Spacing.sm),
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // The method is a chip rather than a field: every CAPA this
                // slice opens is an 8D, and a reader wants to know which
                // discipline they are reading rather than to change it.
                Chip(label: Text('${capa.methodLabel} investigation')),
                Chip(label: Text(capa.orgUnitName)),
                if (capa.dueDate != null) Chip(label: Text('due ${capa.dueDate}')),
                if (!capa.isOpen) StatusChip(label: capa.statusLabel, tone: capa.statusTone),
              ],
            ),
            const SizedBox(height: Spacing.lg),
            _Team(capa: capa),
            const SizedBox(height: Spacing.lg),
            _Problem(capa: capa),
            if (concern != null) ...[
              const SizedBox(height: Spacing.lg),
              _ConcernCard(concern: concern),
              const SizedBox(height: Spacing.lg),
              _ConcernMeasures(concern: concern),
            ],
          ],
        ),
      ),
    );
  }
}

/// The team (D1): the lead first, because they are the role — the one who
/// cannot verify their own fix later — and then everybody else.
///
/// A team nobody has been named to yet is a real state and says so: the
/// judgement an investigation starts with is that the problem needs one, and
/// who investigates it is decided next.
class _Team extends StatelessWidget {
  const _Team({required this.capa});

  final Capa capa;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final team = capa.team;
    return Column(
      key: CapaDetailScreen.teamKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Team', style: theme.textTheme.titleSmall),
        const SizedBox(height: Spacing.sm),
        if (team.isEmpty)
          Text(
            key: CapaDetailScreen.noTeamKey,
            'Nobody is on this investigation yet.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        for (final member in team)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Spacing.xxs),
            child: Text(
              member.employeeId == capa.teamLead?.employeeId
                  ? '${member.name} · team lead'
                  : member.name,
              style: theme.textTheme.bodyMedium,
            ),
          ),
      ],
    );
  }
}

/// The problem description (D2) — what the investigation adds on top of the
/// Concern's own title, and the reason a team investigates the same problem
/// rather than four readings of it.
class _Problem extends StatelessWidget {
  const _Problem({required this.capa});

  final Capa capa;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final problem = capa.problemStatement;
    return Column(
      key: CapaDetailScreen.problemKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('The problem', style: theme.textTheme.titleSmall),
        const SizedBox(height: Spacing.sm),
        Text(
          key: problem == null ? CapaDetailScreen.noProblemKey : null,
          problem ?? 'Nobody has written the problem description yet.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: problem == null ? theme.colorScheme.onSurfaceVariant : null,
          ),
        ),
      ],
    );
  }
}

/// The Concern this investigation is about — a link back to the record whose
/// measures are this CAPA's own work.
class _ConcernCard extends StatelessWidget {
  const _ConcernCard({required this.concern});

  final Action concern;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: CapaDetailScreen.concernKey,
      child: ListTile(
        onTap: () => context.go('${Routes.actions}/${concern.id}'),
        title: Text('The Concern: ${concern.actionNo}'),
        subtitle: Text(concern.title),
        trailing: StatusChip(label: concern.statusLabel, tone: concern.statusTone),
      ),
    );
  }
}

/// The Concern's Containments, Countermeasures and Preventive actions, each
/// with the phase it is waiting on and every round it has been round.
///
/// This is ADR-0034 made readable: these are the CAPA's actions (D3, D5-D7),
/// recorded once in the Action log, and a second list of them here would be the
/// drift the ADR rejected. Tapping one opens that Action's own Screen, which is
/// where its cycle is run.
class _ConcernMeasures extends StatelessWidget {
  const _ConcernMeasures({required this.concern});

  final Action concern;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final measures = concern.measures;
    return Column(
      key: CapaDetailScreen.measuresKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          measures.isEmpty
              ? 'What the Concern has done'
              : 'What the Concern has done (${measures.length})',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: Spacing.xs),
        Text(
          'The containment (D3), the countermeasures (D5-D6) and the preventive actions (D7) are '
          "the Concern's own, recorded once in the action log — this is where they are read, not "
          'where they are recorded again.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: Spacing.sm),
        if (measures.isEmpty)
          Text(
            key: CapaDetailScreen.noMeasuresKey,
            'Nothing answers this Concern yet, so there is no work to show.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        for (final measure in measures)
          Card(
            key: CapaDetailScreen.measureKey(measure.id),
            margin: const EdgeInsets.only(bottom: Spacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  onTap: () => context.go('${Routes.actions}/${measure.id}'),
                  title: Text(measure.title),
                  subtitle: Text(
                    [
                      measure.typeLabel,
                      measure.statusLabel,
                      measure.ownerName ?? 'Nobody yet',
                      if (measure.openPhase != null)
                        'waiting on its ${measure.openPhase!.phaseLabel.toLowerCase()}',
                    ].join(' · '),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                ),
                // Every phase of every round, so a Check that did not hold and
                // sent the work round again is visible here rather than only on
                // the measure's own Screen (ADR-0033).
                for (final phase in measure.phases)
                  Padding(
                    key: CapaDetailScreen.measurePhaseKey(measure.id, phase.cycle, phase.phase),
                    padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xs),
                    child: Text(
                      [
                        'Cycle ${phase.cycle} · ${phase.phaseLabel}',
                        if (phase.completedAt != null) 'done' else 'open',
                        if (phase.outcomeLabel != null) phase.outcomeLabel!,
                        if (phase.note != null) phase.note!,
                      ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: phase.isOpen ? null : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
