/// The marking queue (issue #588, ADR-0068, slice 4): `/assessments/marking`.
///
/// One row per `submitted` Attempt the caller may mark, oldest first — the
/// person, the process, when it was submitted, and how many "Khác" answers are
/// waiting for a decision. The row's one action opens the paper.
///
/// **Reused, not invented.** The page frame, the header, the list card, the
/// status chip and the empty/failure states are the app's own widgets, the same
/// ones the Assessments register draws with; this Screen adds no colour, no
/// radius and no layout of its own (docs/design-language.md).
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_localizations.dart';
import '../platform/router.dart';
import '../status_tone.dart';
import '../theme.dart';
import '../widgets/app_list_card.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/app_page_header.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/status_chip.dart';
import 'assessment.dart';
import 'assessment_marking_queue_bloc.dart';

class AssessmentMarkingQueueScreen extends StatelessWidget {
  const AssessmentMarkingQueueScreen({super.key});

  static const double maxWidth = 1080;

  static const ValueKey<String> refreshKey = ValueKey<String>('assessment-marking-refresh');
  static const ValueKey<String> emptyKey = ValueKey<String>('assessment-marking-empty');
  static const ValueKey<String> failedKey = ValueKey<String>('assessment-marking-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('assessment-marking-retry');

  static ValueKey<String> rowKey(String attemptId) =>
      ValueKey<String>('assessment-marking-row-$attemptId');
  static ValueKey<String> openKey(String attemptId) =>
      ValueKey<String>('assessment-marking-open-$attemptId');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<AssessmentMarkingQueueBloc>().state;

    return Scaffold(
      body: switch (state) {
        AssessmentMarkingQueueLoading() => const SkeletonList(maxWidth: maxWidth),
        AssessmentMarkingQueueUnavailable(message: final message) => PlatformFailureState(
            key: failedKey,
            title: l10n.assessmentMarkingFailedTitle,
            message: message,
            retryKey: retryKey,
            onRetry: () => context.read<AssessmentMarkingQueueBloc>().add(
                  const AssessmentMarkingQueueStarted(),
                ),
          ),
        AssessmentMarkingQueueLoaded() => _Loaded(state: state),
      },
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({required this.state});

  final AssessmentMarkingQueueLoaded state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bloc = context.read<AssessmentMarkingQueueBloc>();

    return Center(
      child: AppPageFrame(
        maxWidth: AssessmentMarkingQueueScreen.maxWidth,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xl),
          children: [
            AppPageHeader(
              title: l10n.assessmentMarkingTitle,
              description: l10n.assessmentMarkingDescription,
              actions: [
                OutlinedButton.icon(
                  key: AssessmentMarkingQueueScreen.refreshKey,
                  onPressed: state.isRefreshing
                      ? null
                      : () => bloc.add(const AssessmentMarkingQueueRefreshed()),
                  icon: const Icon(Icons.refresh),
                  label: Text(l10n.commonRefresh),
                ),
              ],
            ),
            const SizedBox(height: Spacing.lg),
            if (state.entries.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: Spacing.xxl),
                child: PlatformEmptyState.noneExist(
                  key: AssessmentMarkingQueueScreen.emptyKey,
                  title: l10n.assessmentMarkingEmptyTitle,
                  message: l10n.assessmentMarkingEmpty,
                ),
              )
            else
              AppListCard(rows: [
                for (final entry in state.entries)
                  _QueueRow(key: AssessmentMarkingQueueScreen.rowKey(entry.id), entry: entry),
              ]),
            if (state.isRefreshing) ...[
              const SizedBox(height: Spacing.lg),
              const Center(child: CircularProgressIndicator()),
            ],
            const SizedBox(height: Spacing.xl),
          ],
        ),
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({super.key, required this.entry});

  final AssessmentMarkingEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = AppColors.of(context);
    final submitted = entry.submittedAt;

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
                    Text(entry.employeeName ?? '', style: theme.textTheme.titleSmall),
                    if (entry.attemptNo > 1)
                      StatusChip(
                        label: l10n.assessmentAttemptNumber(entry.attemptNo),
                        tone: StatusTone.neutral,
                      ),
                    StatusChip(
                      label: l10n.assessmentMarkingOtherCount(entry.otherAnswerCount),
                      tone: entry.otherAnswerCount > 0 ? StatusTone.warning : StatusTone.neutral,
                    ),
                    if (entry.submittedLate)
                      StatusChip(label: l10n.assessmentMarkingLate, tone: StatusTone.warning),
                  ],
                ),
                const SizedBox(height: Spacing.xs),
                Text(
                  '${entry.assessmentNumber ?? ''} · ${entry.assessmentTitle ?? ''}',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: Spacing.xs),
                Text(
                  [
                    ?entry.processName,
                    ?entry.orgUnitName,
                    if (submitted != null)
                      l10n.assessmentMarkingSubmittedAt(_dateText(l10n, submitted)),
                  ].join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(color: palette.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: Spacing.md),
          FilledButton.tonal(
            key: AssessmentMarkingQueueScreen.openKey(entry.id),
            onPressed: () => context.go(Routes.assessmentMarking(entry.assessmentId, entry.id)),
            child: Text(l10n.assessmentMarkingOpen),
          ),
        ],
      ),
    );
  }
}

/// The day a paper was submitted, in the reader's locale — the clock time is the
/// server's business and the queue is read by day.
String _dateText(AppLocalizations l10n, DateTime moment) {
  final local = moment.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  return '$day/$month/${local.year}';
}
