/// Marking one submitted paper (issue #588, ADR-0068, slice 4):
/// `/assessments/:id/attempts/:attemptId/marking`.
///
/// **The Marker sees the whole paper at once.** Every Question with its stem,
/// its three Options, the key, the explanation and the candidate's Answer, and
/// beside each Answer the two controls that decide its point. The paper is a
/// list rather than a one-question-at-a-time flow: marking is reading a record,
/// not sitting it, and a Marker comparing twelve answers needs to scroll, not to
/// page.
///
/// **Both numbers are at the top** (spec section 8). The machine's score never
/// moves; the final score is the server's answer after the award, so before the
/// award this Screen shows the running total of the points *the Marker has set*
/// and labels it as such — it never claims a final score nobody has written.
///
/// **The design is the app's own.** The page frame, header, list card, notice
/// text, chips and text fields are the shared widgets, and the palette tokens
/// are the theme's; this Screen introduces no colour, radius or layout pattern
/// (docs/design-language.md).
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_localizations.dart';
import '../l10n/vocabulary.dart';
import '../platform/router.dart';
import '../theme.dart';
import '../widgets/app_banner.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/app_page_header.dart';
import '../widgets/failure_state.dart';
import '../widgets/notice_text.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/status_chip.dart';
import '../status_tone.dart';
import 'assessment.dart';
import 'assessment_answer_line.dart';
import 'assessment_marking_bloc.dart';

class AssessmentMarkingScreen extends StatelessWidget {
  const AssessmentMarkingScreen({
    super.key,
    required this.assessmentId,
    required this.attemptId,
  });

  static const double maxWidth = 900;

  static const ValueKey<String> submitKey = ValueKey<String>('assessment-marking-submit');
  static const ValueKey<String> noteKey = ValueKey<String>('assessment-marking-note');
  static const ValueKey<String> noticeKey = ValueKey<String>('assessment-marking-notice');
  static const ValueKey<String> failedKey = ValueKey<String>('assessment-marking-paper-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('assessment-marking-paper-retry');
  static const ValueKey<String> machineScoreKey = ValueKey<String>('assessment-marking-machine-score');
  static const ValueKey<String> finalScoreKey = ValueKey<String>('assessment-marking-final-score');
  static const ValueKey<String> backKey = ValueKey<String>('assessment-marking-back');

  static ValueKey<String> rowKey(int position) =>
      ValueKey<String>('assessment-marking-question-$position');
  static ValueKey<String> zeroKey(int position) =>
      ValueKey<String>('assessment-marking-zero-$position');
  static ValueKey<String> oneKey(int position) =>
      ValueKey<String>('assessment-marking-one-$position');
  static ValueKey<String> answerNoteKey(int position) =>
      ValueKey<String>('assessment-marking-answer-note-$position');
  static ValueKey<String> resultKey = const ValueKey<String>('assessment-marking-result');

  final String assessmentId;
  final String attemptId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<AssessmentMarkingBloc>().state;

    return Scaffold(
      body: switch (state) {
        AssessmentMarkingLoading() => const SkeletonList(maxWidth: maxWidth),
        AssessmentMarkingUnavailable(message: final message) => PlatformFailureState(
            key: failedKey,
            title: l10n.assessmentMarkingPaperFailedTitle,
            message: message,
            retryKey: retryKey,
            onRetry: () => context.read<AssessmentMarkingBloc>().add(
                  AssessmentMarkingStarted(attemptId),
                ),
          ),
        AssessmentMarkingLoaded() => _Loaded(
            state: state,
            assessmentId: assessmentId,
            attemptId: attemptId,
          ),
      },
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({
    required this.state,
    required this.assessmentId,
    required this.attemptId,
  });

  final AssessmentMarkingLoaded state;
  final String assessmentId;
  final String attemptId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final bloc = context.read<AssessmentMarkingBloc>();
    final attempt = state.paper.attempt;
    final alreadyMarked = attempt.status == attemptMarked;

    // The award landed: the result is the next thing the Marker wants, and it is
    // the record rather than a fresh guess.
    if (state.marked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          context.go(Routes.assessmentResult(assessmentId, attemptId));
        }
      });
    }

    return Center(
      child: AppPageFrame(
        maxWidth: AssessmentMarkingScreen.maxWidth,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xl),
          children: [
            AppPageHeader(
              title: l10n.assessmentMarkingPaperTitle(attempt.employeeName ?? ''),
              description: [
                ?attempt.assessmentNumber,
                ?attempt.assessmentTitle,
                ?attempt.processName,
              ].join(' · '),
              actions: [
                OutlinedButton.icon(
                  key: AssessmentMarkingScreen.backKey,
                  onPressed: () => context.go(Routes.assessmentMarkingQueue),
                  icon: const Icon(Icons.arrow_back),
                  label: Text(l10n.assessmentQueueAction),
                ),
              ],
            ),
            const SizedBox(height: Spacing.lg),
            _ScoreBand(state: state),
            const SizedBox(height: Spacing.lg),
            if (state.notice case final notice?) ...[
              AppBanner(
                key: AssessmentMarkingScreen.noticeKey,
                tone: StatusTone.warning,
                message: notice,
              ),
              const SizedBox(height: Spacing.md),
            ],
            for (final question in state.paper.questions) ...[
              _QuestionCard(
                key: AssessmentMarkingScreen.rowKey(question.position),
                question: question,
                total: state.paper.questions.length,
                points: state.pointsFor(question),
                note: state.answerNotes[question.position] ?? '',
                enabled: !state.marked && !alreadyMarked && !state.isSaving,
                onPoints: (points) => bloc.add(
                  AssessmentMarkingPointSet(question.position, points),
                ),
                onNote: (note) => bloc.add(
                  AssessmentMarkingAnswerNoteChanged(question.position, note),
                ),
              ),
              const SizedBox(height: Spacing.md),
            ],
            const SizedBox(height: Spacing.sm),
            Text(l10n.assessmentMarkingNote, style: theme.textTheme.titleSmall),
            const SizedBox(height: Spacing.xs),
            TextField(
              key: AssessmentMarkingScreen.noteKey,
              minLines: 1,
              maxLines: 4,
              enabled: !state.marked && !alreadyMarked && !state.isSaving,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                helperText: l10n.assessmentMarkingNoteHelper,
                helperMaxLines: 3,
              ),
              onChanged: (note) => bloc.add(AssessmentMarkingNoteChanged(note)),
            ),
            if (alreadyMarked) ...[
              const SizedBox(height: Spacing.md),
              NoticeText(l10n.assessmentMarkingAlreadyMarked),
              const SizedBox(height: Spacing.sm),
              OutlinedButton.icon(
                key: AssessmentMarkingScreen.resultKey,
                onPressed: () => context.go(Routes.assessmentResult(assessmentId, attemptId)),
                icon: const Icon(Icons.assignment_turned_in_outlined),
                label: Text(l10n.assessmentResultAction),
              ),
            ] else ...[
              const SizedBox(height: Spacing.lg),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  key: AssessmentMarkingScreen.submitKey,
                  onPressed: state.isSaving
                      ? null
                      : () => bloc.add(const AssessmentMarkingSubmitted()),
                  icon: const Icon(Icons.done_all),
                  label: Text(l10n.assessmentMarkingSubmit),
                ),
              ),
            ],
            const SizedBox(height: Spacing.xl),
          ],
        ),
      ),
    );
  }
}

/// The two numbers, side by side: what the machine made of the paper, and what
/// the award makes of it — the second labelled as the Marker's own running total
/// until the server has written it.
class _ScoreBand extends StatelessWidget {
  const _ScoreBand({required this.state});

  final AssessmentMarkingLoaded state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final attempt = state.paper.attempt;
    final total = state.paper.questions.length;
    final finalScore = state.marked || attempt.status == attemptMarked
        ? attempt.finalScore
        : null;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Wrap(
          spacing: Spacing.xl,
          runSpacing: Spacing.md,
          children: [
            _ScoreTile(
              key: AssessmentMarkingScreen.machineScoreKey,
              label: l10n.assessmentMarkingMachineScore,
              figure: '${attempt.score ?? 0}/$total',
            ),
            _ScoreTile(
              key: AssessmentMarkingScreen.finalScoreKey,
              label: finalScore == null ? l10n.assessmentMarkingDraftScore : l10n.assessmentMarkingFinalScore,
              figure: '${finalScore ?? state.draftTotal}/$total',
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.assessmentMarkingPassMark(attempt.passMark ?? 0, total),
                  style: theme.textTheme.bodyMedium,
                ),
                // The verdict is the server's (derived at read, spec section
                // 3.13); the Screen only chooses its word and its tone.
                if (finalScore != null && attempt.passed != null) ...[
                  const SizedBox(height: Spacing.xs),
                  StatusChip(
                    label: assessmentVerdictLabel(l10n, passed: attempt.passed!),
                    tone: attempt.passed! ? StatusTone.success : StatusTone.danger,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ScoreTile extends StatelessWidget {
  const _ScoreTile({super.key, required this.label, required this.figure});

  final String label;
  final String figure;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelSmall?.copyWith(color: palette.textMuted)),
        const SizedBox(height: Spacing.xs),
        Text(figure, style: theme.textTheme.headlineSmall),
      ],
    );
  }
}

/// One Question on the marking paper: the stem, the Options with the key and the
/// candidate's pick marked, the explanation, and the two controls that decide
/// the point.
class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    super.key,
    required this.question,
    required this.total,
    required this.points,
    required this.note,
    required this.enabled,
    required this.onPoints,
    required this.onNote,
  });

  final AssessmentMarkedQuestion question;
  final int total;
  final int points;
  final String note;
  final bool enabled;
  final ValueChanged<int> onPoints;
  final ValueChanged<String> onNote;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = AppColors.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.assessmentPositionOf(question.position, total),
              style: theme.textTheme.labelSmall?.copyWith(color: palette.textMuted),
            ),
            const SizedBox(height: Spacing.xs),
            Text(question.questionText, style: theme.textTheme.titleSmall),
            const SizedBox(height: Spacing.md),
            for (final letter in const ['A', 'B', 'C'])
              AssessmentAnswerLine(
                letter: letter,
                text: question.optionText(letter) ?? '',
                chosen: question.chosenOption == letter && !question.isOther,
                keyed: question.correctOption == letter,
              ),
            if (question.isOther) ...[
              const SizedBox(height: Spacing.sm),
              AssessmentAnswerLine(
                letter: null,
                text: l10n.assessmentOtherAnswerLabel,
                chosen: true,
                keyed: false,
              ),
              Padding(
                padding: const EdgeInsets.only(left: Spacing.lg, top: Spacing.xs),
                child: Text(question.otherText ?? '', style: theme.textTheme.bodyMedium),
              ),
            ],
            if (!question.isOther && question.chosenOption == null) ...[
              const SizedBox(height: Spacing.sm),
              Text(
                l10n.assessmentResultNoAnswer,
                style: theme.textTheme.bodySmall?.copyWith(color: palette.textMuted),
              ),
            ],
            if (question.explanation case final explanation? when explanation.isNotEmpty) ...[
              const SizedBox(height: Spacing.sm),
              Text(
                l10n.assessmentExplanationIs(explanation),
                style: theme.textTheme.bodySmall?.copyWith(color: palette.textMuted),
              ),
            ],
            const SizedBox(height: Spacing.md),
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(l10n.assessmentMarkingAwardLabel, style: theme.textTheme.labelMedium),
                ChoiceChip(
                  key: AssessmentMarkingScreen.zeroKey(question.position),
                  label: Text(l10n.assessmentMarkingNoPoint),
                  selected: points == 0,
                  onSelected: enabled ? (_) => onPoints(0) : null,
                ),
                ChoiceChip(
                  key: AssessmentMarkingScreen.oneKey(question.position),
                  label: Text(l10n.assessmentMarkingAwardPoint),
                  selected: points == 1,
                  onSelected: enabled ? (_) => onPoints(1) : null,
                ),
              ],
            ),
            if (question.isOther) ...[
              const SizedBox(height: Spacing.sm),
              TextField(
                key: AssessmentMarkingScreen.answerNoteKey(question.position),
                enabled: enabled,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: l10n.assessmentMarkingAnswerNote,
                ),
                onChanged: onNote,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
