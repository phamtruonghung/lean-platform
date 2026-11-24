/// One Attempt's result (issue #588, ADR-0068, slice 4):
/// `/assessments/:id/attempts/:attemptId/result`.
///
/// **After marking** the Screen shows the score as `7/10 — not passed`, the pass
/// mark it was derived against, both numbers (the machine's and the Marker's),
/// and every Question with the candidate's Answer, the key, the point and the
/// explanation.
///
/// **Before marking** there is no result, and that is a state rather than a
/// failure: the server answers 409 (spec section 3.12), and the Screen says the
/// paper is awaiting marking and lists only the candidate's own Answers — no key,
/// no points, no number.
///
/// **The design is the app's own.** Page frame, header, cards, chips and banners
/// are the shared widgets; the verdict word comes from the one vocabulary lookup
/// ([assessmentVerdictLabel], ADR-0062) and the pass/fail answer from the server.
/// No colour, radius or layout pattern is introduced here (docs/design-language.md).
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
import '../widgets/app_page_frame.dart';
import '../widgets/app_page_header.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/status_chip.dart';
import 'assessment.dart';
import 'assessment_answer_line.dart';
import 'assessment_result_bloc.dart';

class AssessmentResultScreen extends StatelessWidget {
  const AssessmentResultScreen({
    super.key,
    required this.assessmentId,
    required this.attemptId,
  });

  static const double maxWidth = 900;

  static const ValueKey<String> scoreKey = ValueKey<String>('assessment-result-score');
  static const ValueKey<String> verdictKey = ValueKey<String>('assessment-result-verdict');
  static const ValueKey<String> awaitingKey = ValueKey<String>('assessment-result-awaiting');
  static const ValueKey<String> failedKey = ValueKey<String>('assessment-result-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('assessment-result-retry');
  static const ValueKey<String> backKey = ValueKey<String>('assessment-result-back');

  static ValueKey<String> questionKey(int position) =>
      ValueKey<String>('assessment-result-question-$position');

  final String assessmentId;
  final String attemptId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<AssessmentResultBloc>().state;

    return Scaffold(
      body: switch (state) {
        AssessmentResultLoading() => const SkeletonList(maxWidth: maxWidth),
        AssessmentResultUnavailable(message: final message) => PlatformFailureState(
            key: failedKey,
            title: l10n.assessmentResultFailedTitle,
            message: message,
            retryKey: retryKey,
            onRetry: () => context.read<AssessmentResultBloc>().add(
                  AssessmentResultStarted(attemptId),
                ),
          ),
        AssessmentResultAwaitingMarking() => _Frame(
            title: l10n.assessmentResultAwaitingTitle,
            description: null,
            children: [
              AppBanner(
                key: awaitingKey,
                tone: StatusTone.info,
                message: l10n.assessmentResultAwaiting,
              ),
              if (state.answers.isNotEmpty) const SizedBox(height: Spacing.lg),
              _Questions(questions: state.answers, showKey: false),
            ],
          ),
        AssessmentResultLoaded(result: final result) => _Frame(
            title: l10n.assessmentResultTitle,
            description: [
              ?result.attempt.assessmentNumber,
              ?result.attempt.assessmentTitle,
              ?result.attempt.employeeName,
              if (result.attempt.attemptNo > 1)
                l10n.assessmentAttemptNumber(result.attempt.attemptNo),
            ].join(' · '),
            children: [
              _ScoreBand(result: result),
              const SizedBox(height: Spacing.lg),
              _Questions(questions: result.questions, showKey: true),
            ],
          ),
      },
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame({required this.title, required this.description, required this.children});

  final String title;
  final String? description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: AppPageFrame(
        maxWidth: AssessmentResultScreen.maxWidth,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xl),
          children: [
            AppPageHeader(
              title: title,
              description: description,
              actions: [
                OutlinedButton.icon(
                  key: AssessmentResultScreen.backKey,
                  onPressed: () => context.go(Routes.assessments),
                  icon: const Icon(Icons.arrow_back),
                  label: Text(l10n.assessmentBackToRegister),
                ),
              ],
            ),
            const SizedBox(height: Spacing.lg),
            ...children,
            const SizedBox(height: Spacing.xl),
          ],
        ),
      ),
    );
  }
}

/// The score line, the pass mark it was derived against, both numbers and who
/// marked it.
class _ScoreBand extends StatelessWidget {
  const _ScoreBand({required this.result});

  final AssessmentResult result;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = AppColors.of(context);
    final verdict = result.verdict;
    final finalScore = verdict.finalScore;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: Spacing.md,
              runSpacing: Spacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  key: AssessmentResultScreen.scoreKey,
                  finalScore == null
                      ? '—'
                      : l10n.assessmentAttemptScore(
                          finalScore,
                          verdict.questionCount,
                          assessmentVerdictLabel(l10n, passed: verdict.passed),
                        ),
                  style: theme.textTheme.headlineSmall,
                ),
                StatusChip(
                  key: AssessmentResultScreen.verdictKey,
                  label: assessmentVerdictLabel(l10n, passed: verdict.passed),
                  tone: verdict.passed ? StatusTone.success : StatusTone.danger,
                ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              l10n.assessmentResultPassMark(verdict.passMark, verdict.questionCount),
              style: theme.textTheme.bodyMedium,
            ),
            if (verdict.score != null && finalScore != null) ...[
              const SizedBox(height: Spacing.xs),
              Text(
                l10n.assessmentResultMachineScore(verdict.score!, finalScore),
                style: theme.textTheme.bodySmall?.copyWith(color: palette.textMuted),
              ),
            ],
            if (result.attempt.markedByName case final name?) ...[
              const SizedBox(height: Spacing.xs),
              Text(
                l10n.assessmentResultMarkedBy(name),
                style: theme.textTheme.bodySmall?.copyWith(color: palette.textMuted),
              ),
            ],
            if (result.attempt.markingNote case final note? when note.isNotEmpty) ...[
              const SizedBox(height: Spacing.xs),
              Text(
                l10n.assessmentResultMarkingNote(note),
                style: theme.textTheme.bodySmall?.copyWith(color: palette.textMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Questions extends StatelessWidget {
  const _Questions({required this.questions, required this.showKey});

  final List<AssessmentMarkedQuestion> questions;

  /// False before marking: the paper shows the candidate's own Answers and
  /// nothing the Marker has not released.
  final bool showKey;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final question in questions) ...[
          _QuestionCard(
            key: AssessmentResultScreen.questionKey(question.position),
            question: question,
            total: questions.length,
            showKey: showKey,
          ),
          const SizedBox(height: Spacing.md),
        ],
      ],
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    super.key,
    required this.question,
    required this.total,
    required this.showKey,
  });

  final AssessmentMarkedQuestion question;
  final int total;
  final bool showKey;

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
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.assessmentPositionOf(question.position, total),
                    style: theme.textTheme.labelSmall?.copyWith(color: palette.textMuted),
                  ),
                ),
                if (showKey)
                  StatusChip(
                    label: l10n.assessmentResultPoints(question.points),
                    tone: question.points > 0 ? StatusTone.success : StatusTone.neutral,
                  ),
              ],
            ),
            const SizedBox(height: Spacing.xs),
            Text(question.questionText, style: theme.textTheme.titleSmall),
            const SizedBox(height: Spacing.md),
            for (final letter in const ['A', 'B', 'C'])
              AssessmentAnswerLine(
                letter: letter,
                text: question.optionText(letter) ?? '',
                chosen: question.chosenOption == letter && !question.isOther,
                keyed: showKey && question.correctOption == letter,
              ),
            if (question.isOther) ...[
              const SizedBox(height: Spacing.sm),
              AssessmentAnswerLine(
                letter: null,
                text: l10n.assessmentResultOther(question.otherText ?? ''),
                chosen: true,
                keyed: false,
              ),
            ],
            if (question.isBlank) ...[
              const SizedBox(height: Spacing.sm),
              Text(
                l10n.assessmentResultNoAnswer,
                style: theme.textTheme.bodySmall?.copyWith(color: palette.textMuted),
              ),
            ],
            if (showKey) ...[
              const SizedBox(height: Spacing.sm),
              Text(
                l10n.assessmentResultCorrectAnswer(
                  question.correctOption,
                  question.optionText(question.correctOption) ?? '',
                ),
                style: theme.textTheme.bodySmall,
              ),
              if (question.explanation case final explanation? when explanation.isNotEmpty) ...[
                const SizedBox(height: Spacing.xs),
                Text(
                  l10n.assessmentExplanationIs(explanation),
                  style: theme.textTheme.bodySmall?.copyWith(color: palette.textMuted),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
