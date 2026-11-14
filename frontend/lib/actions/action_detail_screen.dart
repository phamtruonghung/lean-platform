/// One Action, and — as each later ticket lands — the PDCA cycle it is running
/// and the measures answering it (issue #176).
///
/// A Screen with its own address rather than a dialog, for the reason the Work
/// order detail Screen gives: this is what a person links to when they want
/// somebody else to look at one concern, and a dialog's address is not
/// something you send to a colleague.
///
/// **The page rhythm** (issue #396's design pass): the page head is
/// `AppPageHeader('Action')` with the two acts on the record — hand it up, call
/// it off — at the row's far end, drawn above the state switch so a load and a
/// failed read carry the same title row and back control as the record does.
/// The record's own identity is the summary card's first line, never the page's
/// title: the number, the title, the chips that say what kind of thing it is and
/// how it stands, and the Concern it answers.
///
/// **What follows the summary** is one `AppDetailSection` per question a reader
/// arrives with — where it stands, the cycle it is running, what answers it, the
/// CAPA opened on it, and the record it was raised from — so every section has
/// the same heading, the same hairline and the same gutter, and the Screen reads
/// as one document rather than five stacked widgets.
library;

import 'package:flutter/material.dart' hide Action;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_localizations.dart';
import '../platform/router.dart';
import '../status_tone.dart';
import '../theme.dart';
import '../widgets/app_detail_section.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/app_page_header.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/status_chip.dart';
import 'action.dart';
import 'action_detail_bloc.dart';
import '../l10n/vocabulary.dart';

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
  static const ValueKey<String> summaryKey = ValueKey<String>('action-detail-summary');
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

  /// The Safety observation this Action was raised from, if it was raised
  /// from one (issue #231) — the section a Concern-or-any-other-kind renders
  /// instead of [nonconformancesKey]/[safetyIncidentKey], never more than one
  /// (the single-source rule).
  static const ValueKey<String> safetyObservationKey =
      ValueKey<String>('action-detail-safety-observation');

  static ValueKey<String> addMeasureKindKey(String wire) =>
      ValueKey<String>('action-detail-add-measure-$wire');
  static ValueKey<String> measureKey(String id) => ValueKey<String>('action-measure-$id');
  static const ValueKey<String> parentKey = ValueKey<String>('action-detail-parent');
  static ValueKey<String> phaseKey(int cycle, String phase) =>
      ValueKey<String>('action-phase-$cycle-$phase');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<ActionDetailBloc>().state;
    final loaded = state is ActionDetailLoaded ? state.action : null;

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Head(action: loaded),
          Expanded(
            child: switch (state) {
              ActionDetailLoading() => const SkeletonList(rows: 5, maxWidth: maxWidth),
              ActionDetailUnavailable(message: final message) => PlatformFailureState(
                  key: failedKey,
                  title: l10n.commonThatActionCouldNotBeRead,
                  message: message,
                  retryKey: retryKey,
                  onRetry: () =>
                      context.read<ActionDetailBloc>().add(ActionDetailStarted(actionId)),
                ),
              ActionDetailLoaded(action: final action, notice: final notice) =>
                _ActionDetail(action: action, notice: notice),
            },
          ),
        ],
      ),
    );
  }
}

/// The page's own title row: the way back, `AppPageHeader('Action')`, and the
/// two acts on the record when it is still live.
///
/// It sits above the state switch, so a load, a failed read and the record are
/// told apart by their body and never by a missing page head (issue #391's
/// design law 3), and the acts appear only once there is a record to act on —
/// a control addressed at an Action that has not been read yet would be a
/// button with nothing behind it.
class _Head extends StatelessWidget {
  const _Head({this.action});

  final Action? action;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final loaded = action;
    // Both offered while the Action is still live, and neither for one that has
    // ended: a closed or cancelled record has nothing left to hand up or call
    // off, and both addresses refuse it anyway (issues #179 and #180).
    final live = loaded != null && !const {'done', 'cancelled'}.contains(loaded.status);
    final id = loaded?.id;

    return Center(
      child: AppPageFrame(
        maxWidth: ActionDetailScreen.maxWidth,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // `context.go`, never `maybePop`: every navigation in this
              // Platform replaces the location rather than pushing a page, so
              // there is nothing on the Navigator to pop (issue #183).
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  key: ActionDetailScreen.backKey,
                  onPressed: () => context.go(Routes.actions),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(AppTouchTarget.min, AppTouchTarget.min),
                  ),
                  icon: const Icon(Icons.arrow_back),
                  label: Text(l10n.commonBackToTheActionLog),
                ),
              ),
              const SizedBox(height: Spacing.sm),
              AppPageHeader(
                title: l10n.titleAction,
                actions: [
                  if (live)
                    TextButton(
                      key: ActionDetailScreen.escalateKey,
                      onPressed: () => context.go('${Routes.actions}/$id/escalate'),
                      child: Text(l10n.actionDetailHandItUp),
                    ),
                  if (live)
                    TextButton(
                      key: ActionDetailScreen.cancelKey,
                      onPressed: () => context.go('${Routes.actions}/$id/cancel'),
                      child: Text(l10n.actionDetailCallItOff),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
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
    final l10n = AppLocalizations.of(context);
    return Center(
      child: AppPageFrame(
        maxWidth: ActionDetailScreen.maxWidth,
        // A `SingleChildScrollView`, not a `ListView`, deliberately: this is a
        // document of a bounded number of sections, so every section is built
        // and laid out whether or not it is on screen — which is what a test
        // can read, and what a reader printing the page gets. A lazily-built
        // list would leave the foot of the record out of the tree until
        // somebody scrolled to it (the trade `capa_report_screen.dart` records
        // for its own document).
        child: SingleChildScrollView(
          key: ActionDetailScreen.loadedKey,
          // The page head above this view already pads its own top and the space
          // beneath itself.
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SummaryCard(action: action, notice: notice),
              const SizedBox(height: Spacing.md),
            AppDetailSection(
              title: l10n.actionDetailWhereItStands,
              children: [
                _Fact(label: l10n.commonOrgUnit, value: action.orgUnitName),
                _Fact(label: l10n.commonOwner, value: action.ownerName ?? 'Nobody yet'),
                _Fact(
                  label: l10n.requestsRaisedBy,
                  value: action.raisedByName ?? 'An Account with no Employee record',
                ),
                _Fact(label: l10n.pmSchedulesDue, value: action.dueDate ?? 'No due date'),
                if (action.escalatedToOrgUnitName != null)
                  _Fact(label: l10n.actionDetailEscalatedTo, value: action.escalatedToOrgUnitName!),
                if (action.closureNote != null)
                  _Fact(label: l10n.actionDetailClosingNote, value: action.closureNote!),
              ],
            ),
            const SizedBox(height: Spacing.md),
            _Cycle(action: action),
            const SizedBox(height: Spacing.md),
            _Measures(action: action),
            // The investigation this Concern has been turned into, if any
            // (issue #209) — only a Concern can be under one, because that is
            // what a CAPA is opened on.
            if (action.actionType == 'concern') ...[
              const SizedBox(height: Spacing.md),
              _Capa(action: action),
            ],
            const SizedBox(height: Spacing.md),
            // The evidence behind the Concern, at the foot of the record on
            // purpose: the cycle and the work answering it are what was asked
            // for first, and the source is what proves the problem is real. A
            // Concern raised from the register has none of the three, and the
            // empty state says so rather than leaving a blank. The
            // single-source rule (`action_items_single_source`) means an
            // Action is never more than one of these, so exactly one of the
            // three renders (issues #229, #231).
            if (action.safetyIncident != null)
              _SafetyIncidentSource(action: action)
            else if (action.safetyObservation != null)
              _SafetyObservationSource(action: action)
            else
              _Nonconformances(action: action),
            ],
          ),
        ),
      ),
    );
  }
}

/// The summary card: what the record *is*, before anything about how it is
/// going — its own identity (number, title), the chips that say what kind of
/// thing it is and how it stands, the description somebody wrote, and the
/// Concern it answers when it answers one.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.action, this.notice});

  final Action action;
  final String? notice;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = AppColors.of(context);

    return Card(
      key: ActionDetailScreen.summaryKey,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              action.actionNo,
              style: AppTypography.dense(context)?.copyWith(color: palette.textMuted),
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              action.title,
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: Spacing.sm),
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                StatusChip(label: action.typeLabel(l10n), tone: action.statusTone),
                StatusChip(label: action.statusLabel(l10n), tone: action.statusTone),
                if (action.pillarCode != null) Chip(label: Text(l10n.actionDetailPillar((action.pillarCode ?? '')))),
                Chip(label: Text(action.priorityLabel(l10n))),
                if (action.isOverdue)
                  StatusChip(label: l10n.commonOverdueByDays((action.daysOverdue ?? 0)), tone: StatusTone.danger),
              ],
            ),
            if (action.description != null) ...[
              const SizedBox(height: Spacing.md),
              Text(action.description!, style: AppTypography.dense(context)),
            ],
            if (notice != null) ...[
              const SizedBox(height: Spacing.sm),
              Text(
                notice!,
                key: ActionDetailScreen.noticeKey,
                style: AppTypography.dense(context),
              ),
            ],
            if (action.parent != null) ...[
              const SizedBox(height: Spacing.md),
              _Parent(parent: action.parent!),
            ],
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
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = AppColors.of(context).textMuted;
    final current = action.currentCyclePhases;
    final earlier = [
      for (final phase in action.phases)
        if (phase.cycle != action.currentCycle) phase
    ];
    final openPhase = action.openPhase;

    return AppDetailSection(
      title: l10n.actionDetailCycle(action.currentCycle),
      trailing: openPhase == null
          ? null
          : FilledButton.tonalIcon(
              key: ActionDetailScreen.completePhaseKey,
              onPressed: () => context.go(
                '${Routes.actions}/${action.id}/phases/${openPhase.phase}/complete',
              ),
              icon: const Icon(Icons.check_circle_outline),
              label: Text(l10n.actionDetailCompleteThe(openPhase.phaseLabel(l10n))),
            ),
      children: [
        if (current.isEmpty)
          Text(
            l10n.actionDetailThisActionHasNoPhasesLeft,
            style: AppTypography.dense(context)?.copyWith(color: muted),
          ),
        for (final phase in current) _PhaseRow(phase: phase),
        if (earlier.isNotEmpty) ...[
          const SizedBox(height: Spacing.md),
          Text(
            key: ActionDetailScreen.cycleHistoryKey,
            l10n.actionDetailEarlierRounds,
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
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = AppColors.of(context).textMuted;
    return Padding(
      key: ActionDetailScreen.phaseKey(phase.cycle, phase.phase),
      padding: const EdgeInsets.symmetric(vertical: Spacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              historical ? '${phase.phaseLabel(l10n)} · ${phase.cycle}' : phase.phaseLabel(l10n),
              style: AppTypography.dense(context)?.copyWith(
                fontWeight: phase.isOpen ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  phase.note ?? (phase.isOpen ? l10n.actionDetailOpenWaitingOnThis : l10n.actionDetailNoNoteRecorded),
                  style:
                      AppTypography.dense(context)?.copyWith(color: phase.isOpen ? null : muted),
                ),
                Text(
                  [
                    if (phase.ownerName != null) phase.ownerName!,
                    if (phase.dueDate != null) l10n.actionDetailDue((phase.dueDate ?? '')),
                    if (phase.completedAt != null)
                      l10n.actionDetailDone(phase.completedAt!.toLocal().toIso8601String().substring(0, 10)),
                    if (phase.outcomeLabel(l10n) != null) phase.outcomeLabel(l10n)!,
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

/// One label and its value, as every detail Screen's sections read them.
class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final muted = AppColors.of(context).textMuted;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 180,
            child: Text(label, style: AppTypography.floor(context)?.copyWith(color: muted)),
          ),
          Expanded(child: Text(value, style: AppTypography.dense(context))),
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
    final l10n = AppLocalizations.of(context);
    final muted = AppColors.of(context).textMuted;
    return InkWell(
      key: ActionDetailScreen.parentKey,
      onTap: () => context.go('${Routes.actions}/${parent.id}'),
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.actionDetailAnswers(parent.actionNo),
                    style: AppTypography.dense(context)?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: Spacing.xxs),
                  Text(parent.title, style: AppTypography.floor(context)?.copyWith(color: muted)),
                ],
              ),
            ),
            const SizedBox(width: Spacing.sm),
            StatusChip(label: parent.statusLabel(l10n), tone: parent.statusTone),
          ],
        ),
      ),
    );
  }
}

/// The CAPA section (issue #209, ADR-0034): the investigation opened on this
/// Concern, or the way to open one — and nothing at all when the caller holds
/// no Quality authority, which is the rule ADR-0035 and issue #48 set: a CAPA is
/// opened by judgement, not by anybody.
///
/// A Concern that already has one shows it rather than the button, because a
/// second is refused (409) and offering a control the server will refuse is a
/// worse interface than naming the investigation that exists.
class _Capa extends StatelessWidget {
  const _Capa({required this.action});

  final Action action;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final muted = AppColors.of(context).textMuted;
    final capa = action.capa;
    // Read here, in a build, rather than passed in from the route: a value
    // computed when the route first built would freeze the Account state as it
    // was before `/me` answered, and a holder of Quality authority would never
    // be offered the act that authority gates (ADR-0035).
    final canOpen = holdsQualityAuthority(context, action.orgUnitId);

    return KeyedSubtree(
      key: ActionDetailScreen.capaKey,
      child: AppDetailSection(
        title: l10n.commonCapa,
        children: [
          Text(
            l10n.actionDetailAFormal8dInvestigationOpenedOnThis,
            style: AppTypography.floor(context)?.copyWith(color: muted),
          ),
          if (capa != null)
            InkWell(
              key: ActionDetailScreen.capaLinkKey,
              onTap: () => context.go('${Routes.actions}/capas/${capa.id}'),
              borderRadius: BorderRadius.circular(AppRadius.card),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.actionDetailUnderInvestigation(capa.capaNo),
                            style: AppTypography.dense(context)
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: Spacing.xxs),
                          Text(
                            action.title,
                            style: AppTypography.floor(context)?.copyWith(color: muted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: Spacing.sm),
                    StatusChip(label: capa.statusLabel(l10n), tone: capa.statusTone),
                  ],
                ),
              ),
            )
          else if (canOpen)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.tonal(
                key: ActionDetailScreen.openCapaKey,
                onPressed: () => context.go('${Routes.actions}/${action.id}/capa'),
                child: Text(l10n.actionDetailOpenACapa),
              ),
            )
          else
            Text(
              key: ActionDetailScreen.noCapaKey,
              l10n.actionDetailNobodyHasOpenedACapaOnThis,
              style: AppTypography.dense(context)?.copyWith(color: muted),
            ),
        ],
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
    final l10n = AppLocalizations.of(context);
    final muted = AppColors.of(context).textMuted;
    final measures = action.measures;

    return KeyedSubtree(
      key: ActionDetailScreen.measuresHeadingKey,
      child: AppDetailSection(
        title: measures.isEmpty
            ? l10n.actionDetailMeasures
            : l10n.actionDetailMeasuresOfThemCountermeasures(measures.length, action.countermeasureCount),
        // The kind is chosen by name rather than by a picker inside the form:
        // the three words mean three different pieces of work, and a dropdown in
        // the middle of a form invites the wrong one.
        trailing: PopupMenuButton<String>(
          key: ActionDetailScreen.addMeasureKey,
          enabled: !action.isMeasure,
          tooltip: l10n.actionDetailAddAMeasure,
          onSelected: (measureType) => context.go(
            '${Routes.actions}/${action.id}/measures/$measureType/new',
          ),
          itemBuilder: (context) => [
            for (final measureType in actionMeasureTypeOrder)
              PopupMenuItem<String>(
                key: ActionDetailScreen.addMeasureKindKey(measureType),
                value: measureType,
                child: Text(l10n.actionDetailAddA(actionTypeLabel(l10n, measureType).toLowerCase())),
              ),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: Spacing.xs),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add),
                SizedBox(width: Spacing.xs),
                Text(l10n.actionDetailAddAMeasure),
              ],
            ),
          ),
        ),
        children: [
          if (measures.isNotEmpty)
            // The sentence the deployed stack was missing (issue #183): a reader
            // who has just been refused by the Act needs to be told what closes
            // a measure, and that it is something they can go and do.
            Text(
              key: ActionDetailScreen.measuresHintKey,
              l10n.actionDetailEachMeasureIsAnActionOfIts,
              style: AppTypography.floor(context)?.copyWith(color: muted),
            ),
          if (measures.isEmpty)
            Text(
              key: ActionDetailScreen.measuresEmptyKey,
              action.isMeasure
                  ? l10n.actionDetailThisActionAnswersNoConcernOfIts
                  : l10n.actionDetailNothingAnswersThisYetAContainmentStops,
              style: AppTypography.dense(context)?.copyWith(color: muted),
            ),
          for (final measure in measures) _MeasureRow(measure: measure),
        ],
      ),
    );
  }
}

/// One measure as a row inside the Measures section: its title, the facts that
/// place it, and — where the work is — the phase it is waiting on, offered at
/// the measure's own address so it is one tap earlier than opening the record.
class _MeasureRow extends StatelessWidget {
  const _MeasureRow({required this.measure});

  final Action measure;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final muted = AppColors.of(context).textMuted;
    return InkWell(
      key: ActionDetailScreen.measureKey(measure.id),
      onTap: () => context.go('${Routes.actions}/${measure.id}'),
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    measure.title,
                    style: AppTypography.dense(context)?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: Spacing.xxs),
                  Text(
                    [
                      measure.typeLabel(l10n),
                      measure.statusLabel(l10n),
                      measure.ownerName ?? l10n.commonNobodyYet,
                      // Two different facts, so both: when it is due and what
                      // it is waiting on. (They used to be exclusive, which hid
                      // the phase of exactly the measures a reader is most
                      // likely to be looking for.)
                      if (measure.isOverdue) l10n.actionDetailOverdueByDays((measure.daysOverdue ?? 0)),
                      if (measure.openPhase != null)
                        l10n.commonWaitingOnIts(measure.openPhase!.phaseLabel(l10n).toLowerCase()),
                    ].join(' · '),
                    style: AppTypography.floor(context)?.copyWith(color: muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Spacing.sm),
            // A measure waiting on a phase offers that phase's completion, at
            // the measure's own Action — the same dialog it would get two taps
            // later, one tap earlier, which is what the deployed stack's reader
            // went looking for and did not find (issue #183).
            if (measure.openPhase == null)
              Icon(Icons.chevron_right, color: muted)
            else
              TextButton(
                key: ActionDetailScreen.measureCompleteKey(measure.id),
                onPressed: () => context.go(
                  '${Routes.actions}/${measure.id}/phases/${measure.openPhase!.phase}/complete',
                ),
                child: Text(l10n.actionDetailCompleteThe2(measure.openPhase!.phaseLabel(l10n))),
              ),
          ],
        ),
      ),
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
    final l10n = AppLocalizations.of(context);
    final muted = AppColors.of(context).textMuted;
    final occurrences = action.nonconformances;

    return KeyedSubtree(
      key: ActionDetailScreen.nonconformancesKey,
      child: AppDetailSection(
        title:
            occurrences.isEmpty ? l10n.navNonConformances : l10n.actionDetailNonConformances(occurrences.length),
        children: [
          Text(
            l10n.actionDetailTheOccurrencesThisConcernAnswersOneProblem,
            style: AppTypography.floor(context)?.copyWith(color: muted),
          ),
          if (occurrences.isEmpty)
            Text(
              key: ActionDetailScreen.noNonconformancesKey,
              l10n.actionDetailNoNonConformanceIsLinkedToThis,
              style: AppTypography.dense(context)?.copyWith(color: muted),
            ),
          for (final occurrence in occurrences)
            _NonconformanceRow(action: action, occurrence: occurrence),
        ],
      ),
    );
  }
}

class _NonconformanceRow extends StatelessWidget {
  const _NonconformanceRow({required this.action, required this.occurrence});

  final Action action;
  final LinkedNonconformance occurrence;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final muted = AppColors.of(context).textMuted;
    final live = !const {'done', 'cancelled'}.contains(action.status);

    return InkWell(
      key: ActionDetailScreen.nonconformanceKey(occurrence.id),
      onTap: () => context.go('${Routes.nonConformances}/${occurrence.id}'),
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    occurrence.issueNo,
                    style: AppTypography.dense(context)?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: Spacing.xxs),
                  Text(
                    [
                      occurrence.productLabel,
                      occurrence.defectCodeLabel,
                      occurrence.quantityLabel,
                    ].join(' · '),
                    style: AppTypography.floor(context)?.copyWith(color: muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Spacing.sm),
            if (occurrence.isSource)
              TextButton(
                key: ActionDetailScreen.raisedFromKey,
                onPressed: () => context.go('${Routes.nonConformances}/${occurrence.id}'),
                child: Text(l10n.actionDetailRaisedFromThis),
              )
            // Offered only while the Concern is still live: a link on a closed
            // problem is history, and an ended Action is not offered its own
            // transition controls either.
            else if (live)
              TextButton(
                key: ActionDetailScreen.unlinkNonconformanceKey(occurrence.id),
                onPressed: () => context.go(
                  '${Routes.actions}/${action.id}/nonconformances/${occurrence.id}/unlink',
                ),
                child: Text(l10n.actionDetailUnlink),
              )
            else
              Icon(Icons.chevron_right, color: muted),
          ],
        ),
      ),
    );
  }
}

/// The words for a Safety incident's severity, observation type, category and
/// potential come from `l10n/vocabulary.dart` — the same one lookup every other
/// Screen uses, in the reader's language (ADR-0062). This Screen used to keep a
/// second copy per set because `actions` did not import `safety`; the catalogue
/// adapter imports both, so a copy here would only be drift.
/// The Safety observation this Action was raised from (issue #231) — the
/// mirror of `_SafetyIncidentSource` for the third source an Action may
/// carry. One row, linking to the observation's own address, naming what was
/// seen and how bad it could have been: an observation carries no injury
/// details of its own to withhold (#223 decision 9), so there is nothing
/// restricted to leave out here the way `_SafetyIncidentSource` does.
class _SafetyObservationSource extends StatelessWidget {
  const _SafetyObservationSource({required this.action});

  final Action action;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final muted = AppColors.of(context).textMuted;
    final observation = action.safetyObservation!;

    return KeyedSubtree(
      key: ActionDetailScreen.safetyObservationKey,
      child: AppDetailSection(
        title: l10n.titleSafetyObservation,
        children: [
          Text(
            l10n.actionDetailTheObservationThisActionWasRaisedFrom,
            style: AppTypography.floor(context)?.copyWith(color: muted),
          ),
          _SourceRow(
            onTap: () => context.go('${Routes.safetyObservations}/${observation.id}'),
            title: observationCategoryLabel(l10n, observation.category),
            subtitle:
                '${observationTypeLabel(l10n, observation.observationType)} '
                '· ${severityPotentialLabel(l10n, observation.severityPotential)}',
          ),
        ],
      ),
    );
  }
}

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
    final l10n = AppLocalizations.of(context);
    final muted = AppColors.of(context).textMuted;
    final incident = action.safetyIncident!;

    return KeyedSubtree(
      key: ActionDetailScreen.safetyIncidentKey,
      child: AppDetailSection(
        title: l10n.titleSafetyIncident,
        children: [
          Text(
            l10n.actionDetailTheIncidentThisConcernWasRaisedFrom,
            style: AppTypography.floor(context)?.copyWith(color: muted),
          ),
          _SourceRow(
            onTap: () => context.go('${Routes.safetyIncidents}/${incident.id}'),
            title: incident.incidentNo,
            subtitle: safetySeverityLabel(l10n, incident.severityLevel),
          ),
        ],
      ),
    );
  }
}

/// One linked record inside a source section: a name, the facts beneath it, and
/// the chevron that says the row opens something. A `ListTile` with no content
/// padding, which is the row this Screen has always drawn for a source record —
/// the section around it is what changed in this pass, not the row.
class _SourceRow extends StatelessWidget {
  const _SourceRow({required this.onTap, required this.title, required this.subtitle});

  final VoidCallback onTap;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final muted = AppColors.of(context).textMuted;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      title: Text(
        title,
        style: AppTypography.dense(context)?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(subtitle, style: AppTypography.floor(context)?.copyWith(color: muted)),
      trailing: Icon(Icons.chevron_right, color: muted),
    );
  }
}
