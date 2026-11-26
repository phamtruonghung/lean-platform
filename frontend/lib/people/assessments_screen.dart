/// The Assessments register (issue #588, ADR-0068, slice 3): three tabs over
/// two shapes of row.
///
/// **"Assigned to me"** lists the caller's own Attempts — the Assessment's
/// number and title, the process it draws from, its status, how long is left and
/// whether anything is waiting to be marked. An Attempt that has not been
/// started carries the one action that matters, **Start**, which opens the
/// sitting Screen; a running one carries **Continue**.
///
/// **"I created" and "All"** list Assessments — number, title, process, paper
/// size, due date and the four sitting counts, which are never hidden whatever
/// the caller's reach.
///
/// The tab strip is three `ChoiceChip`s, the shape `LeaveRequestsScreen` uses for
/// its own three filters: the app has no tab-bar idiom and this Screen does not
/// introduce one.
///
/// A score appears on a row only once the Attempt is marked (spec section 3.12),
/// and only where the server sent one: a score the caller may not read arrives
/// as null and renders `—` (spec section 3.14). The Screen never works one out.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_localizations.dart';
import '../l10n/vocabulary.dart';
import '../platform/router.dart';
import '../status_tone.dart';
import '../theme.dart';
import '../widgets/app_banner.dart';
import '../widgets/app_date_field.dart';
import '../widgets/app_filter_row.dart';
import '../widgets/app_list_card.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/app_page_header.dart';
import '../widgets/disclosing_text.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/status_chip.dart';
import 'assessment.dart';
import 'assessments_bloc.dart';

class AssessmentsScreen extends StatelessWidget {
  const AssessmentsScreen({super.key});

  static const double maxWidth = 1080;

  static const ValueKey<String> newAssessmentKey = ValueKey<String>('assessments-new');
  static const ValueKey<String> markingQueueKey = ValueKey<String>('assessments-marking-queue');
  static const ValueKey<String> questionBankKey = ValueKey<String>('assessments-question-bank');
  static const ValueKey<String> refreshKey = ValueKey<String>('assessments-refresh');
  static const ValueKey<String> emptyKey = ValueKey<String>('assessments-empty');
  static const ValueKey<String> failedKey = ValueKey<String>('assessments-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('assessments-retry');
  static const ValueKey<String> noticeKey = ValueKey<String>('assessments-notice');

  static const ValueKey<String> filterProcessKey = ValueKey<String>('assessments-filter-process');
  static const ValueKey<String> filterStatusKey = ValueKey<String>('assessments-filter-status');
  static const ValueKey<String> filterFromKey = ValueKey<String>('assessments-filter-from');
  static const ValueKey<String> filterToKey = ValueKey<String>('assessments-filter-to');
  static const ValueKey<String> filterFailedKey = ValueKey<String>('assessments-filter-failed');

  static ValueKey<String> tabKey(int tab) => ValueKey<String>('assessments-tab-$tab');
  static ValueKey<String> attemptRowKey(String id) => ValueKey<String>('assessment-attempt-row-$id');
  static ValueKey<String> attemptActionKey(String id) => ValueKey<String>('assessment-attempt-action-$id');
  static ValueKey<String> attemptScoreKey(String id) => ValueKey<String>('assessment-attempt-score-$id');
  static ValueKey<String> attemptResultKey(String id) => ValueKey<String>('assessment-attempt-result-$id');
  static ValueKey<String> assessmentRowKey(String id) => ValueKey<String>('assessment-row-$id');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<AssessmentsBloc>().state;

    return Scaffold(
      body: switch (state) {
        AssessmentsLoading() => const SkeletonList(maxWidth: maxWidth),
        AssessmentsUnavailable(message: final message) => PlatformFailureState(
            key: failedKey,
            title: l10n.assessmentsFailedTitle,
            message: message,
            retryKey: retryKey,
            onRetry: () => context.read<AssessmentsBloc>().add(const AssessmentsStarted()),
          ),
        AssessmentsLoaded() => _Loaded(state: state),
      },
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({required this.state});

  final AssessmentsLoaded state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = AppColors.of(context);
    final bloc = context.read<AssessmentsBloc>();

    final rows = switch (state.tab) {
      assignedToMeTab => _mineRows(context, l10n),
      iCreatedTab => _assessmentRows(context, l10n, state.created),
      _ => _assessmentRows(context, l10n, state.all),
    };

    return Center(
      child: AppPageFrame(
        maxWidth: AssessmentsScreen.maxWidth,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xl),
          children: [
            AppPageHeader(
              title: l10n.assessmentsTitle,
              description: l10n.assessmentsDescription,
              actions: [
                OutlinedButton.icon(
                  key: AssessmentsScreen.refreshKey,
                  onPressed: state.isRefreshing
                      ? null
                      : () => bloc.add(const AssessmentsRefreshed()),
                  icon: const Icon(Icons.refresh),
                  label: Text(l10n.commonRefresh),
                ),
                OutlinedButton.icon(
                  key: AssessmentsScreen.questionBankKey,
                  onPressed: () => context.go(Routes.assessmentQuestions),
                  icon: const Icon(Icons.library_books_outlined),
                  label: Text(l10n.assessmentQuestionsTitle),
                ),
                if (state.mayMark)
                  OutlinedButton.icon(
                    key: AssessmentsScreen.markingQueueKey,
                    onPressed: () => context.go(Routes.assessmentMarkingQueue),
                    icon: const Icon(Icons.fact_check_outlined),
                    label: Text(l10n.assessmentQueueAction),
                  ),
                if (state.mayChange)
                  FilledButton.icon(
                    key: AssessmentsScreen.newAssessmentKey,
                    onPressed: () => context.go(Routes.assessmentNew),
                    icon: const Icon(Icons.add),
                    label: Text(l10n.assessmentNew),
                  ),
              ],
              below: Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.sm,
                children: [
                  ChoiceChip(
                    key: AssessmentsScreen.tabKey(assignedToMeTab),
                    label: Text(l10n.assessmentTabAssignedToMe),
                    selected: state.tab == assignedToMeTab,
                    onSelected: (_) => bloc.add(const AssessmentsTabSelected(assignedToMeTab)),
                  ),
                  ChoiceChip(
                    key: AssessmentsScreen.tabKey(iCreatedTab),
                    label: Text(l10n.assessmentTabICreated),
                    selected: state.tab == iCreatedTab,
                    onSelected: (_) => bloc.add(const AssessmentsTabSelected(iCreatedTab)),
                  ),
                  ChoiceChip(
                    key: AssessmentsScreen.tabKey(allAssessmentsTab),
                    label: Text(l10n.assessmentTabAll),
                    selected: state.tab == allAssessmentsTab,
                    onSelected: (_) => bloc.add(const AssessmentsTabSelected(allAssessmentsTab)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Spacing.lg),
            if (state.tab == allAssessmentsTab) ...[
              _Filters(state: state),
              const SizedBox(height: Spacing.lg),
            ],
            if (state.notice case final notice?) ...[
              AppBanner(key: AssessmentsScreen.noticeKey, tone: StatusTone.info, message: notice),
              const SizedBox(height: Spacing.md),
            ],
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: Spacing.xxl),
                child: state.tab == allAssessmentsTab && !state.filter.isEmpty
                    ? PlatformEmptyState.noneMatched(
                        key: AssessmentsScreen.emptyKey,
                        title: l10n.assessmentFilterNoMatchTitle,
                        message: l10n.assessmentFilterNoMatchMessage,
                      )
                    : PlatformEmptyState.noneExist(
                        key: AssessmentsScreen.emptyKey,
                        title: l10n.assessmentRegisterEmptyTitle,
                        message: switch (state.tab) {
                          assignedToMeTab => l10n.assessmentRegisterEmptyMine,
                          iCreatedTab => l10n.assessmentRegisterEmptyCreated,
                          _ => l10n.assessmentRegisterEmptyAll,
                        },
                      ),
              )
            else
              AppListCard(rows: rows),
            if (state.isRefreshing) ...[
              const SizedBox(height: Spacing.lg),
              const Center(child: CircularProgressIndicator()),
            ],
            const SizedBox(height: Spacing.xl),
            Text(
              l10n.assessmentScoreHiddenNote,
              style: theme.textTheme.bodySmall?.copyWith(color: palette.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _mineRows(BuildContext context, AppLocalizations l10n) {
    return [
      for (final attempt in state.mine)
        _AttemptRow(key: AssessmentsScreen.attemptRowKey(attempt.id), attempt: attempt),
    ];
  }

  List<Widget> _assessmentRows(
    BuildContext context,
    AppLocalizations l10n,
    List<Assessment> assessments,
  ) {
    return [
      for (final assessment in assessments)
        _AssessmentRow(key: AssessmentsScreen.assessmentRowKey(assessment.id), assessment: assessment),
    ];
  }
}

class _AttemptRow extends StatelessWidget {
  const _AttemptRow({super.key, required this.attempt});

  final AssessmentAttempt attempt;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = AppColors.of(context);
    final theme = Theme.of(context);
    final number = attempt.assessmentNumber ?? '';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: Spacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: Spacing.sm,
                  runSpacing: Spacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      attempt.assessmentTitle ?? '',
                      style: theme.textTheme.titleSmall,
                    ),
                    StatusChip(label: attempt.statusLabel(l10n), tone: _attemptTone(attempt)),
                  ],
                ),
                const SizedBox(height: Spacing.xs),
                Text(
                  [
                    if (number.isNotEmpty) number,
                    if (attempt.processName != null) attempt.processName!,
                    if (attempt.questionCount != null)
                      l10n.assessmentPaperSizeShort(attempt.questionCount!),
                    if (attempt.dueOn != null) l10n.assessmentDueOn(attempt.dueOn!),
                  ].join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(color: palette.textMuted),
                ),
                if (attempt.status == attemptMarked) ...[
                  const SizedBox(height: Spacing.xs),
                  Text(
                    key: AssessmentsScreen.attemptScoreKey(attempt.id),
                    attempt.scoreLabel(l10n) ?? '—',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: Spacing.md),
          if (attempt.isRunning || attempt.status == attemptAssigned)
            FilledButton(
              key: AssessmentsScreen.attemptActionKey(attempt.id),
              onPressed: () => context.go(
                Routes.assessmentSitting(attempt.assessmentId, attempt.id),
              ),
              child: Text(
                attempt.isRunning ? l10n.assessmentContinue : l10n.assessmentStart,
              ),
            )
          else if (attempt.status == attemptMarked || attempt.status == attemptSubmitted)
            OutlinedButton(
              key: AssessmentsScreen.attemptResultKey(attempt.id),
              onPressed: () => context.go(
                Routes.assessmentResult(attempt.assessmentId, attempt.id),
              ),
              child: Text(l10n.assessmentResultAction),
            ),
        ],
      ),
    );
  }

  StatusTone _attemptTone(AssessmentAttempt attempt) {
    return switch (attempt.status) {
      attemptInProgress => StatusTone.info,
      attemptSubmitted => StatusTone.warning,
      attemptMarked => StatusTone.success,
      _ => StatusTone.neutral,
    };
  }
}

class _AssessmentRow extends StatelessWidget {
  const _AssessmentRow({super.key, required this.assessment});

  final Assessment assessment;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = AppColors.of(context);
    final theme = Theme.of(context);

    // The whole row opens the Assessment's detail (slice 6).
    return InkWell(
      onTap: () => context.go(Routes.assessment(assessment.id)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: Spacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: Spacing.sm,
                    runSpacing: Spacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(assessment.title, style: theme.textTheme.titleSmall),
                      StatusChip(
                        label: assessment.statusLabel(l10n),
                        tone: assessment.isDraft
                            ? StatusTone.neutral
                            : assessment.isClosed
                                ? StatusTone.neutral
                                : StatusTone.info,
                      ),
                    ],
                  ),
                  const SizedBox(height: Spacing.xs),
                  Text(
                    [
                      assessment.number,
                      if (assessment.orgUnitName != null) assessment.orgUnitName!,
                      l10n.assessmentPaperSizeShort(assessment.questionCount),
                      l10n.assessmentMinutesShort(assessment.minutes),
                      if (assessment.dueOn != null) l10n.assessmentDueOn(assessment.dueOn!),
                    ].join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(color: palette.textMuted),
                  ),
                  const SizedBox(height: Spacing.xs),
                  DisclosingText(
                    l10n.assessmentSittingCounts(
                      assessment.assignedCount,
                      assessment.runningCount,
                      assessment.awaitingMarkingCount,
                      assessment.markedCount,
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(color: palette.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The "All" tab's narrowing controls (slice 6): the process, the status, a date
/// range on the due date and "below pass mark". Each change is one event; the
/// Bloc reads the register again with the query parameters it implies.
class _Filters extends StatelessWidget {
  const _Filters({required this.state});

  final AssessmentsLoaded state;

  static const List<String> _statuses = [assessmentDraft, assessmentAssigned, assessmentClosed];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bloc = context.read<AssessmentsBloc>();
    final filter = state.filter;
    // A chosen process that the register no longer lists would make the
    // dropdown assert; fall back to "all" in the control and keep the filter.
    // The controls keep their own chosen value between reads: only the control
    // itself ever clears one, so they are never re-seeded.
    final processId = state.processes.any((process) => process.id == filter.orgUnitId)
        ? filter.orgUnitId
        : null;

    return AppFilterRow(
      children: [
        SizedBox(
          width: 240,
          child: DropdownButtonFormField<String?>(
            key: AssessmentsScreen.filterProcessKey,
            initialValue: processId,
            isDense: true,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: l10n.assessmentFilterProcess,
              border: const OutlineInputBorder(),
            ),
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: Text(l10n.assessmentFilterAllProcesses),
              ),
              for (final process in state.processes)
                DropdownMenuItem<String?>(
                  value: process.id,
                  child: Text(process.name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (value) => bloc.add(AssessmentsFiltered(
              value == null
                  ? filter.copyWith(clearOrgUnit: true)
                  : filter.copyWith(orgUnitId: value),
            )),
          ),
        ),
        SizedBox(
          width: 200,
          child: DropdownButtonFormField<String?>(
            key: AssessmentsScreen.filterStatusKey,
            initialValue: filter.status,
            isDense: true,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: l10n.assessmentFilterStatus,
              border: const OutlineInputBorder(),
            ),
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: Text(l10n.assessmentFilterAnyStatus),
              ),
              for (final status in _statuses)
                DropdownMenuItem<String?>(
                  value: status,
                  child: Text(assessmentStateLabel(l10n, status)),
                ),
            ],
            onChanged: (value) => bloc.add(AssessmentsFiltered(
              value == null ? filter.copyWith(clearStatus: true) : filter.copyWith(status: value),
            )),
          ),
        ),
        SizedBox(
          width: 200,
          child: AppDateField(
            key: AssessmentsScreen.filterFromKey,
            name: 'assessments-filter-from',
            label: l10n.commonFrom,
            value: filter.from,
            optional: true,
            onChanged: (value) => bloc.add(AssessmentsFiltered(
              value == null ? filter.copyWith(clearFrom: true) : filter.copyWith(from: value),
            )),
          ),
        ),
        SizedBox(
          width: 200,
          child: AppDateField(
            key: AssessmentsScreen.filterToKey,
            name: 'assessments-filter-to',
            label: l10n.commonTo,
            value: filter.to,
            optional: true,
            onChanged: (value) => bloc.add(AssessmentsFiltered(
              value == null ? filter.copyWith(clearTo: true) : filter.copyWith(to: value),
            )),
          ),
        ),
        Align(
          alignment: Alignment.center,
          child: FilterChip(
            key: AssessmentsScreen.filterFailedKey,
            label: Text(l10n.assessmentFilterBelowPassMark),
            selected: filter.failed,
            onSelected: (value) => bloc.add(AssessmentsFiltered(filter.copyWith(failed: value))),
          ),
        ),
      ],
    );
  }
}
