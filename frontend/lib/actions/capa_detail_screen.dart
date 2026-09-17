/// One CAPA (issue #209): the investigation opened on a Concern — its number,
/// its team, what the investigation says the problem is, the two 5 Why chains
/// its team reasons with (issue #210), and the Concern's own Containments,
/// Countermeasures and Preventive actions with their PDCA phases.
///
/// A Screen with its own address rather than a dialog, for the reason the
/// Action detail Screen gives: this is what somebody sends to a colleague when
/// they want a second pair of eyes on an investigation, and a dialog's address
/// is not something you send to anybody.
///
/// **The chains are written from here (issue #210).** A writer — edit access at
/// the CAPA's Org Unit, or a place on its team (`mayEditCapaChains`) — adds a
/// Why to either chain, revises one, moves one along its chain, marks one as
/// the chain's confirmed root cause, and removes one; each of those acts that
/// needs a form has its own address, and the two that do not (marking a root
/// cause, moving a Why) are the row's own controls. A reader sees both chains
/// and no controls, which is the honest rendering of what the server would
/// allow them.
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
import '../status_tone.dart';
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

  /// The report (issue #212) — the same investigation laid out as an 8D at its
  /// own address, outside the Shell, which is what an auditor or a customer is
  /// handed. The one control in this header that leads *away* from the record
  /// rather than changing it.
  static const ValueKey<String> reportKey = ValueKey<String>('capa-detail-report');
  static const ValueKey<String> problemKey = ValueKey<String>('capa-detail-problem');
  static const ValueKey<String> noProblemKey = ValueKey<String>('capa-detail-no-problem');
  static const ValueKey<String> teamKey = ValueKey<String>('capa-detail-team');
  static const ValueKey<String> noTeamKey = ValueKey<String>('capa-detail-no-team');
  static const ValueKey<String> concernKey = ValueKey<String>('capa-detail-concern');
  static const ValueKey<String> measuresKey = ValueKey<String>('capa-detail-measures');
  static const ValueKey<String> noMeasuresKey = ValueKey<String>('capa-detail-no-measures');

  /// The chains (issue #210): the section, one block per chain, the Why rows
  /// inside it, and the two sentences the Screen says about writing them.
  static const ValueKey<String> chainsKey = ValueKey<String>('capa-detail-chains');
  static const ValueKey<String> chainsReadOnlyKey =
      ValueKey<String>('capa-detail-chains-read-only');
  static const ValueKey<String> chainsClosedKey = ValueKey<String>('capa-detail-chains-closed');

  /// The fishbone (issue #213): the section, one block per 6M category, the
  /// cause rows inside it, and the two sentences the Screen says about writing
  /// it. Read before the chains, because that is the order a team works in.
  static const ValueKey<String> fishboneKey = ValueKey<String>('capa-detail-fishbone');
  static const ValueKey<String> fishboneReadOnlyKey =
      ValueKey<String>('capa-detail-fishbone-read-only');
  static const ValueKey<String> fishboneClosedKey =
      ValueKey<String>('capa-detail-fishbone-closed');

  static ValueKey<String> causeCategoryKey(String category) =>
      ValueKey<String>('capa-cause-category-$category');

  static ValueKey<String> causeCategoryEmptyKey(String category) =>
      ValueKey<String>('capa-cause-category-$category-empty');

  static ValueKey<String> addCauseKey(String category) =>
      ValueKey<String>('capa-cause-category-$category-add');

  static ValueKey<String> causeKey(String id) => ValueKey<String>('capa-cause-$id');

  static ValueKey<String> causeVerdictKey(String id) => ValueKey<String>('capa-cause-$id-verdict');

  static ValueKey<String> causeEvidenceKey(String id) => ValueKey<String>('capa-cause-$id-evidence');

  static ValueKey<String> causeDecideKey(String id) => ValueKey<String>('capa-cause-$id-decide');

  static ValueKey<String> causeEditKey(String id) => ValueKey<String>('capa-cause-$id-edit');

  static ValueKey<String> causeRemoveKey(String id) => ValueKey<String>('capa-cause-$id-remove');

  static ValueKey<String> causeStartWhyKey(String id) =>
      ValueKey<String>('capa-cause-$id-start-why');

  /// What the last write to this investigation did, and why the last one did
  /// not land — the page's own, above every section rather than inside the one
  /// that happened to make the request first. #210 put them under the chains
  /// because a chain write was the only write this Screen had; #211 adds a
  /// second kind (recording the effectiveness check), and a notice about the
  /// investigation closing does not belong under the heading "Root cause".
  static const ValueKey<String> noticeKey = ValueKey<String>('capa-detail-notice');
  static const ValueKey<String> failureKey = ValueKey<String>('capa-detail-failure');

  static ValueKey<String> chainKey(String chain) => ValueKey<String>('capa-chain-$chain');

  static ValueKey<String> chainRootKey(String chain) =>
      ValueKey<String>('capa-chain-$chain-root');

  static ValueKey<String> noWhysKey(String chain) => ValueKey<String>('capa-chain-$chain-empty');

  static ValueKey<String> addWhyKey(String chain) => ValueKey<String>('capa-chain-$chain-add');

  static ValueKey<String> whyKey(String id) => ValueKey<String>('capa-why-$id');

  static ValueKey<String> whyRootChipKey(String id) => ValueKey<String>('capa-why-$id-root');

  static ValueKey<String> whyMarkRootKey(String id) => ValueKey<String>('capa-why-$id-mark-root');

  static ValueKey<String> whyEditKey(String id) => ValueKey<String>('capa-why-$id-edit');

  static ValueKey<String> whyRemoveKey(String id) => ValueKey<String>('capa-why-$id-remove');

  static ValueKey<String> whyEarlierKey(String id) => ValueKey<String>('capa-why-$id-earlier');

  static ValueKey<String> whyLaterKey(String id) => ValueKey<String>('capa-why-$id-later');

  static ValueKey<String> measureKey(String id) => ValueKey<String>('capa-measure-$id');

  static ValueKey<String> measurePhaseKey(String measureId, int cycle, String phase) =>
      ValueKey<String>('capa-measure-$measureId-phase-$cycle-$phase');

  /// The effectiveness check (issue #211): the section, what it is waiting on,
  /// what it recorded, and the one control the act has.
  static const ValueKey<String> effectivenessKey =
      ValueKey<String>('capa-detail-effectiveness');
  static const ValueKey<String> effectivenessDueKey =
      ValueKey<String>('capa-detail-effectiveness-due');
  static const ValueKey<String> effectivenessOverdueKey =
      ValueKey<String>('capa-detail-effectiveness-overdue');
  static const ValueKey<String> effectivenessNotYetKey =
      ValueKey<String>('capa-detail-effectiveness-not-yet');
  static const ValueKey<String> effectivenessOutcomeKey =
      ValueKey<String>('capa-detail-effectiveness-outcome');
  static const ValueKey<String> effectivenessVerifiedByKey =
      ValueKey<String>('capa-detail-effectiveness-verified-by');
  static const ValueKey<String> effectivenessNoteKey =
      ValueKey<String>('capa-detail-effectiveness-note');
  static const ValueKey<String> effectivenessReopenedKey =
      ValueKey<String>('capa-detail-effectiveness-reopened');
  static const ValueKey<String> effectivenessCheckKey =
      ValueKey<String>('capa-detail-effectiveness-check');
  static const ValueKey<String> effectivenessNotYoursKey =
      ValueKey<String>('capa-detail-effectiveness-not-yours');
  static const ValueKey<String> effectivenessTeamLeadKey =
      ValueKey<String>('capa-detail-effectiveness-team-lead');

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
        CapaDetailLoaded(capa: final capa) => _CapaDetail(
            capa: capa,
            notice: state.notice,
            failure: state.mutationFailure,
          ),
      },
    );
  }
}

class _CapaDetail extends StatelessWidget {
  const _CapaDetail({required this.capa, this.notice, this.failure});

  final Capa capa;

  /// What the last change to the chains did, and why the last one did not land
  /// — the Screen's own copy of what the dialog over it has already said, so a
  /// reader who dismissed a refusal can still see it (issue #210).
  final String? notice;
  final String? failure;

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
            // A `Wrap`, not a `Row`: the back label, the report link and the
            // status chip are wider together than an 800px window, and a `Wrap`
            // puts what does not fit on its own line rather than overflowing.
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
                // The report, offered to every reader rather than gated: the
                // record itself is a Site-wide read (ADR-0009), and a reader
                // who may read the investigation may hand its report to an
                // auditor.
                TextButton.icon(
                  key: CapaDetailScreen.reportKey,
                  onPressed: () => context.go(Routes.capaReport(capa.id)),
                  icon: const Icon(Icons.description_outlined),
                  label: const Text('The report'),
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
            // What the last write did, and why the last one did not land —
            // above the sections rather than inside one of them, because there
            // are now two kinds of write this Screen makes (a chain's, #210,
            // and the effectiveness check's, #211) and only one notice.
            if (notice != null)
              Padding(
                key: CapaDetailScreen.noticeKey,
                padding: const EdgeInsets.only(bottom: Spacing.md),
                child: Text(notice!, style: theme.textTheme.bodyMedium),
              ),
            if (failure != null)
              Padding(
                key: CapaDetailScreen.failureKey,
                padding: const EdgeInsets.only(bottom: Spacing.md),
                child: Text(
                  failure!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            _Team(capa: capa),
            const SizedBox(height: Spacing.lg),
            _Problem(capa: capa),
            const SizedBox(height: Spacing.lg),
            // The fishbone before the chains, because that is the order the
            // team works in: the candidate causes are reasoned about first, and
            // a chain begins from the one the evidence confirmed (issue #213).
            _Fishbone(capa: capa),
            const SizedBox(height: Spacing.lg),
            _Chains(capa: capa),
            if (concern != null) ...[
              const SizedBox(height: Spacing.lg),
              _ConcernCard(concern: concern),
              const SizedBox(height: Spacing.lg),
              _ConcernMeasures(concern: concern),
            ],
            const SizedBox(height: Spacing.lg),
            // Last, because it is the last thing that happens: the
            // investigation has finished, the Concern has closed, and somebody
            // else has verified that the fix held (issue #211).
            _Effectiveness(capa: capa),
          ],
        ),
      ),
    );
  }
}

/// The effectiveness check (issue #211) — D8 of the 8D, and the step CONTEXT.md
/// says a CAPA closes on: "a root cause is confirmed for both why it happened
/// and why it was not detected, its Concern is closed, and someone holding
/// Quality authority other than its team lead has verified, some time later,
/// that the problem has not come back".
///
/// Four states, and each says which it is: nothing is due while the Concern is
/// open (with the delay that will decide the date), the date once it has closed,
/// the overdue mark when that date has passed, and the verdict, the verifier and
/// the note once a check has been recorded. Nothing is hidden on a closed
/// investigation: what was recorded is exactly what a reader of a closed CAPA
/// came for, and it is what the report #212 renders.
///
/// The one control is the check, offered only to a holder of Quality authority
/// who is not the team lead (`mayRecordCapaEffectiveness`) — the client's half
/// of the server's own two-part gate. A team lead gets a sentence of their own
/// rather than a button whose request would come back 403, and so does a reader
/// without the authority.
class _Effectiveness extends StatelessWidget {
  const _Effectiveness({required this.capa});

  final Capa capa;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final verifiedAt = capa.effectivenessVerifiedAt;
    final dueAt = capa.effectivenessCheckDueAt;

    return Column(
      key: CapaDetailScreen.effectivenessKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Effectiveness', style: theme.textTheme.titleSmall),
        const SizedBox(height: Spacing.xs),
        Text(
          'A CAPA closes only when both chains have a confirmed root cause, its Concern is '
          'closed, and somebody holding Quality authority other than its team lead has '
          'verified, some time later, that the problem has not come back.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: Spacing.sm),
        if (verifiedAt != null) ...[
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StatusChip(
                key: CapaDetailScreen.effectivenessOutcomeKey,
                label: capaEffectivenessOutcomeLabel(capa.effectivenessOutcome!),
                tone: capaEffectivenessOutcomeTone(capa.effectivenessOutcome!),
              ),
              Text(
                key: CapaDetailScreen.effectivenessVerifiedByKey,
                'recorded by ${capa.effectivenessVerifiedBy?.name ?? 'an Account'} on '
                '${verifiedAt.toLocal().toIso8601String().substring(0, 10)}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          if (capa.effectivenessNote != null)
            Padding(
              key: CapaDetailScreen.effectivenessNoteKey,
              padding: const EdgeInsets.only(top: Spacing.sm),
              child: Text(capa.effectivenessNote!, style: theme.textTheme.bodyMedium),
            ),
          if (capa.status == 'actions')
            Padding(
              key: CapaDetailScreen.effectivenessReopenedKey,
              padding: const EdgeInsets.only(top: Spacing.sm),
              child: Text(
                'The check did not hold, so the Concern is open again in its next cycle: the '
                'work is on its Screen, in the Concern this investigation answers.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
        ] else if (dueAt != null) ...[
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                key: CapaDetailScreen.effectivenessDueKey,
                'The Concern has closed, so the effectiveness check is due on $dueAt.',
                style: theme.textTheme.bodyMedium,
              ),
              if (capa.effectivenessCheckOverdue)
                StatusChip(
                  key: CapaDetailScreen.effectivenessOverdueKey,
                  label: 'Overdue',
                  tone: StatusTone.warning,
                ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          if (mayRecordCapaEffectiveness(context, capa))
            FilledButton.icon(
              key: CapaDetailScreen.effectivenessCheckKey,
              onPressed: () =>
                  context.go('${Routes.actions}/capas/${capa.id}/effectiveness'),
              icon: const Icon(Icons.verified_outlined),
              label: const Text('Record the effectiveness check'),
            )
          else if (isCapaTeamLeadAccount(context, capa))
            Text(
              key: CapaDetailScreen.effectivenessTeamLeadKey,
              'You lead this investigation, so somebody else records the check: a holder of '
              'Quality authority who is not on the team lead\'s Account.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            )
          else
            Text(
              key: CapaDetailScreen.effectivenessNotYoursKey,
              'Recording the check needs Quality authority at this Org Unit.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
        ] else
          Text(
            key: CapaDetailScreen.effectivenessNotYetKey,
            'The check falls due ${capa.effectivenessCheckDelayDays} days after the Concern '
            'closes, and the Concern has not closed yet.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
      ],
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

/// The fishbone (issue #213) — candidate causes by 6M category, each with the
/// verdict its evidence produced. The step before the root-cause analysis, and
/// the reason it is worth having one: a team lists what it suspects before it
/// decides, and the bones nobody has looked at are as legible on this Screen as
/// the causes on them.
///
/// **All six bones are always shown**, in the order an Ishikawa diagram is
/// drawn. One with nothing under it says so rather than disappearing: a
/// category the team has not considered is exactly what a reader — an auditor,
/// a colleague picking the investigation up — needs to see, and a diagram that
/// rendered only the categories in use would hide the question "did anybody
/// think about the method?".
///
/// A `candidate` cause is a suspicion with a verdict still to come; `confirmed`
/// and `ruled_out` carry the evidence in the row, because a verdict without its
/// evidence is the thing this ticket exists to stop. The one control that
/// crosses into the chains is offered only where the server would accept it: a
/// **confirmed** cause, and a chain that has not been started — both of which a
/// reader can see are true from the row and the chain beside it.
///
/// Who may write is asked once, here, and answered by `mayEditCapaChains` — the
/// client's half of the server's own rule, shared with the chains because it is
/// one rule (edit access at the CAPA's Org Unit, or a place on its team). A
/// reader who may not write gets the fishbone and a sentence saying so rather
/// than buttons whose requests would come back 403; a closed investigation gets
/// the fishbone and a sentence saying it is a record. Reading is Site-wide, the
/// same as reading any Action, so the causes themselves are never hidden.
class _Fishbone extends StatelessWidget {
  const _Fishbone({required this.capa});

  final Capa capa;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mayWrite = capa.isOpen && mayEditCapaChains(context, capa);

    return Column(
      key: CapaDetailScreen.fishboneKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Candidate causes', style: theme.textTheme.titleSmall),
        const SizedBox(height: Spacing.xs),
        Text(
          'The fishbone: what the team suspected, by 6M category, and what the evidence said '
          'about each one. The chain that follows begins with the cause it confirmed.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        if (!capa.isOpen)
          Padding(
            key: CapaDetailScreen.fishboneClosedKey,
            padding: const EdgeInsets.only(top: Spacing.sm),
            child: Text(
              'This investigation is over, so its fishbone is a record rather than a worklist.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          )
        else if (!mayWrite)
          Padding(
            key: CapaDetailScreen.fishboneReadOnlyKey,
            padding: const EdgeInsets.only(top: Spacing.sm),
            child: Text(
              "Writing a CAPA's root causes needs edit access at its Org Unit, or a place on "
              'its team.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        const SizedBox(height: Spacing.md),
        for (final category in capaCauseCategoryOrder) ...[
          _Bone(capa: capa, category: category, mayWrite: mayWrite),
          const SizedBox(height: Spacing.md),
        ],
      ],
    );
  }
}

/// One of the six bones: its heading with how many causes hang from it, the
/// sentence a bone nobody has recorded anything on reads, and its causes.
class _Bone extends StatelessWidget {
  const _Bone({required this.capa, required this.category, required this.mayWrite});

  final Capa capa;
  final String category;
  final bool mayWrite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final causes = capa.causesIn(category);

    return Column(
      key: CapaDetailScreen.causeCategoryKey(category),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // A `Wrap`, not a `Row`: the heading and the add control are wider
        // together than the body of an 800px window, and a Wrap drops the
        // control onto its own line rather than overflowing.
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: Spacing.sm,
          runSpacing: Spacing.sm,
          children: [
            Text(
              causes.isEmpty
                  ? capaCauseCategoryLabel(category)
                  : '${capaCauseCategoryLabel(category)} (${causes.length})',
              style: theme.textTheme.titleSmall,
            ),
            if (mayWrite)
              TextButton.icon(
                key: CapaDetailScreen.addCauseKey(category),
                onPressed: () => context.go(
                  '${Routes.actions}/capas/${capa.id}/causes/$category/new',
                ),
                icon: const Icon(Icons.add),
                label: const Text('Record a cause'),
              ),
          ],
        ),
        if (causes.isEmpty)
          Padding(
            key: CapaDetailScreen.causeCategoryEmptyKey(category),
            padding: const EdgeInsets.only(top: Spacing.xs),
            child: Text(
              'Nothing is recorded under ${capaCauseCategoryLabel(category)}.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        for (final cause in causes)
          _CauseRow(capa: capa, cause: cause, mayWrite: mayWrite),
      ],
    );
  }
}

/// One candidate cause: what the team suspected, the verdict the evidence
/// produced with the evidence itself, and the controls a writer has over it.
///
/// The controls are a `Wrap` rather than a `Row` — up to four of them, in a card
/// under a 260px sidebar — for the reason every row of controls in this client
/// is one. `Start a chain from it` is offered only for a **confirmed** cause
/// whose chain has not begun, which are the server's own two conditions: an
/// offer the request would refuse is worse than no offer.
class _CauseRow extends StatelessWidget {
  const _CauseRow({required this.capa, required this.cause, required this.mayWrite});

  final Capa capa;
  final CapaCause cause;
  final bool mayWrite;

  /// Whether a chain may begin with this cause (issue #213): the evidence
  /// confirmed it, and one of the two chains is still empty.
  bool get _canStartChain => cause.isConfirmed && capa.chainsNotStarted.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = '${Routes.actions}/capas/${capa.id}/causes/${cause.category}/${cause.id}';

    return Card(
      key: CapaDetailScreen.causeKey(cause.id),
      margin: const EdgeInsets.only(top: Spacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.md, Spacing.lg, 0),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: Spacing.sm,
              runSpacing: Spacing.sm,
              children: [
                Text('Cause ${cause.sequence}', style: theme.textTheme.titleSmall),
                StatusChip(
                  key: CapaDetailScreen.causeVerdictKey(cause.id),
                  label: cause.verdictLabel,
                  tone: cause.verdictTone,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xs, Spacing.lg, 0),
            child: Text(cause.statement, style: theme.textTheme.bodyMedium),
          ),
          if (cause.evidenceNote != null)
            Padding(
              key: CapaDetailScreen.causeEvidenceKey(cause.id),
              padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xs, Spacing.lg, 0),
              child: Text(
                'Evidence: ${cause.evidenceNote}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          if (mayWrite)
            Padding(
              padding: const EdgeInsets.fromLTRB(Spacing.sm, Spacing.xs, Spacing.sm, Spacing.sm),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: Spacing.xs,
                runSpacing: Spacing.xs,
                children: [
                  TextButton(
                    key: CapaDetailScreen.causeDecideKey(cause.id),
                    onPressed: () => context.go('$base/verdict'),
                    child: Text(cause.isDecided ? 'Change the verdict' : 'Decide it'),
                  ),
                  TextButton(
                    key: CapaDetailScreen.causeEditKey(cause.id),
                    onPressed: () => context.go('$base/edit'),
                    child: const Text('Revise'),
                  ),
                  if (_canStartChain)
                    TextButton(
                      key: CapaDetailScreen.causeStartWhyKey(cause.id),
                      onPressed: () => context.go('$base/why'),
                      child: const Text('Start a chain from it'),
                    ),
                  TextButton(
                    key: CapaDetailScreen.causeRemoveKey(cause.id),
                    onPressed: () => context.go('$base/remove'),
                    child: const Text('Remove'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The two 5 Why chains (issue #210) — the root-cause analysis, D4 of the 8D.
///
/// Both chains are always shown, in the order they are reasoned: why the
/// problem happened, then why it was not detected. Each is a list of Whys in
/// their own order, with the one the chain stopped at marked as its confirmed
/// root cause; a chain with no root yet says so, because that is the state #211
/// refuses to close a CAPA on and the reader of an investigation wants to know
/// which of the two questions is still open.
///
/// Who may write is asked once, here, and answered by `mayEditCapaChains` —
/// the client's half of the server's own rule. A reader who may not write gets
/// the chains and a sentence saying so rather than buttons whose requests would
/// come back 403; a closed investigation gets the chains and a sentence saying
/// it is a record. Reading is Site-wide, the same as reading any Action, so the
/// chains themselves are never hidden.
class _Chains extends StatelessWidget {
  const _Chains({required this.capa});

  final Capa capa;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mayWrite = capa.isOpen && mayEditCapaChains(context, capa);

    return Column(
      key: CapaDetailScreen.chainsKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Root cause', style: theme.textTheme.titleSmall),
        const SizedBox(height: Spacing.xs),
        Text(
          'Two chains, each ending at one confirmed root cause: why the problem happened, '
          'and why it was not detected.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        if (!capa.isOpen)
          Padding(
            key: CapaDetailScreen.chainsClosedKey,
            padding: const EdgeInsets.only(top: Spacing.sm),
            child: Text(
              'This investigation is over, so its chains are a record rather than a worklist.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          )
        else if (!mayWrite)
          Padding(
            key: CapaDetailScreen.chainsReadOnlyKey,
            padding: const EdgeInsets.only(top: Spacing.sm),
            child: Text(
              "Writing a CAPA's root causes needs edit access at its Org Unit, or a place on "
              'its team.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        const SizedBox(height: Spacing.md),
        for (final chain in capaChainOrder) ...[
          _Chain(capa: capa, chain: chain, mayWrite: mayWrite),
          const SizedBox(height: Spacing.md),
        ],
      ],
    );
  }
}

/// One chain: its heading, the one sentence saying what it asks, its Whys in
/// order, and where it stopped.
class _Chain extends StatelessWidget {
  const _Chain({required this.capa, required this.chain, required this.mayWrite});

  final Capa capa;
  final String chain;
  final bool mayWrite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final whys = capa.whysIn(chain);
    final root = capa.rootCauseOf(chain);

    return Column(
      key: CapaDetailScreen.chainKey(chain),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // A `Wrap`, not a `Row`: the heading and the add button are wider
        // together than the body of an 800px window, and a Wrap drops the
        // button onto its own line rather than overflowing.
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: Spacing.sm,
          runSpacing: Spacing.sm,
          children: [
            Text(
              whys.isEmpty
                  ? capaChainLabel(chain)
                  : '${capaChainLabel(chain)} (${whys.length})',
              style: theme.textTheme.titleSmall,
            ),
            if (mayWrite)
              TextButton.icon(
                key: CapaDetailScreen.addWhyKey(chain),
                onPressed: () =>
                    context.go('${Routes.actions}/capas/${capa.id}/whys/$chain/new'),
                icon: const Icon(Icons.add),
                label: const Text('Add a Why'),
              ),
          ],
        ),
        const SizedBox(height: Spacing.xs),
        Text(
          chain == 'occurrence'
              ? 'Why the problem happened, one step at a time.'
              : 'Why it was not detected, one step at a time.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: Spacing.sm),
        if (whys.isEmpty)
          Text(
            key: CapaDetailScreen.noWhysKey(chain),
            'Nobody has started this chain yet.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        for (final why in whys)
          _WhyRow(
            capa: capa,
            chain: chain,
            why: why,
            mayWrite: mayWrite,
            isLast: why.sequence == whys.length,
          ),
        Padding(
          key: CapaDetailScreen.chainRootKey(chain),
          padding: const EdgeInsets.only(top: Spacing.xs),
          child: Text(
            root == null
                ? 'This chain has no confirmed root cause yet.'
                : 'Confirmed root cause: ${root.statement}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: root == null
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}

/// One Why: where it sits, what it says, and the controls a writer has over it.
///
/// The controls are a `Wrap` rather than a `Row`, because there are five of
/// them and the body of the window at the widget tests' own surface is under
/// 500px: a Row would overflow the moment the labels grew, where a Wrap moves
/// them onto a second line. Moving a Why is offered as two disabled-at-the-ends
/// buttons rather than a drag, so the position sent is always a position in the
/// chain — the server's own 400 for "past the end" is unreachable from here.
class _WhyRow extends StatelessWidget {
  const _WhyRow({
    required this.capa,
    required this.chain,
    required this.why,
    required this.mayWrite,
    required this.isLast,
  });

  final Capa capa;
  final String chain;
  final CapaWhy why;
  final bool mayWrite;
  final bool isLast;

  void _change(BuildContext context, {int? sequence, bool? isRoot}) {
    context.read<CapaDetailBloc>().add(
          CapaDetailWhyChanged(whyId: why.id, sequence: sequence, isRoot: isRoot),
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      key: CapaDetailScreen.whyKey(why.id),
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.md, Spacing.lg, 0),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: Spacing.sm,
              runSpacing: Spacing.sm,
              children: [
                Text('Why ${why.sequence}', style: theme.textTheme.titleSmall),
                if (why.isRoot)
                  StatusChip(
                    key: CapaDetailScreen.whyRootChipKey(why.id),
                    label: 'Confirmed root cause',
                    tone: StatusTone.success,
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xs, Spacing.lg, 0),
            child: Text(why.statement, style: theme.textTheme.bodyMedium),
          ),
          if (mayWrite)
            Padding(
              padding: const EdgeInsets.fromLTRB(Spacing.sm, Spacing.xs, Spacing.sm, Spacing.sm),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: Spacing.xs,
                runSpacing: Spacing.xs,
                children: [
                  // Marking a second Why replaces the first, so the button never
                  // has to say "unmark the other one first" — it is the same
                  // request either way, and the server is what makes them one
                  // conclusion.
                  TextButton(
                    key: CapaDetailScreen.whyMarkRootKey(why.id),
                    onPressed: () => _change(context, isRoot: !why.isRoot),
                    child: Text(why.isRoot ? 'Clear the root cause' : 'This is the root cause'),
                  ),
                  TextButton(
                    key: CapaDetailScreen.whyEditKey(why.id),
                    onPressed: () => context.go(
                      '${Routes.actions}/capas/${capa.id}/whys/$chain/${why.id}/edit',
                    ),
                    child: const Text('Revise'),
                  ),
                  TextButton(
                    key: CapaDetailScreen.whyRemoveKey(why.id),
                    onPressed: () => context.go(
                      '${Routes.actions}/capas/${capa.id}/whys/$chain/${why.id}/remove',
                    ),
                    child: const Text('Remove'),
                  ),
                  IconButton(
                    key: CapaDetailScreen.whyEarlierKey(why.id),
                    tooltip: 'Move it earlier in the chain',
                    onPressed:
                        why.sequence > 1 ? () => _change(context, sequence: why.sequence - 1) : null,
                    icon: const Icon(Icons.arrow_upward),
                  ),
                  IconButton(
                    key: CapaDetailScreen.whyLaterKey(why.id),
                    tooltip: 'Move it later in the chain',
                    onPressed: isLast ? null : () => _change(context, sequence: why.sequence + 1),
                    icon: const Icon(Icons.arrow_downward),
                  ),
                ],
              ),
            ),
        ],
      ),
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
