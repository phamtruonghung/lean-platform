/// The sitting (issue #588, ADR-0068, slice 3), at
/// `/assessments/:assessmentId/attempts/:attemptId/sit`.
///
/// **One Question per screen, with a navigator.** A paper is 10 or 15 Questions
/// and a phone on the floor is 360 px wide; showing one at a time is the only
/// layout that leaves the stem and three Options legible together. Back/Next
/// move between them and a row of position chips jumps, so a skipped Question is
/// one tap away rather than three.
///
/// **The countdown is in the sticky header**, next to the position and the save
/// tick, so it is visible whatever Question is on screen. It counts down from
/// the difference between the server's `deadlineAt` and `serverNow` using a
/// [Stopwatch] — the device's wall clock is never read — and when it reaches
/// zero it asks the Bloc for the paper again rather than deciding anything
/// itself: the server owns the finalise.
///
/// **Autosave on every change, with a quiet tick.** An Option tap saves at once;
/// the Other answer saves after the typist stops. "Saved" appears beside the
/// clock for a moment and then fades; a refusal is the server's own sentence and
/// stays.
///
/// **"Khác" is a fourth row, visually separate, not an Option column.** Its
/// label is the owner's own words — "Khác: ghi câu trả lời của bạn" — and it
/// carries a text field. Choosing it clears any Option; choosing an Option
/// clears it. It scores 0 until a Marker decides (spec section 10), which the
/// Screen says rather than implies.
///
/// **Submit is behind a confirmation naming the unanswered count**, because a
/// paper submitted by accident cannot be reopened by the candidate.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_localizations.dart';
import '../platform/router.dart';
import '../theme.dart';
import '../widgets/app_confirm_dialog.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/app_page_header.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/notice_text.dart';
import '../widgets/skeleton_list.dart';
import 'assessment_sitting_bloc.dart';

class AssessmentSittingScreen extends StatefulWidget {
  const AssessmentSittingScreen({
    super.key,
    required this.assessmentId,
    required this.attemptId,
  });

  final String assessmentId;
  final String attemptId;

  static const double maxWidth = 760;

  static const ValueKey<String> countdownKey = ValueKey<String>('assessment-sitting-countdown');
  static const ValueKey<String> positionKey = ValueKey<String>('assessment-sitting-position');
  static const ValueKey<String> savedTickKey = ValueKey<String>('assessment-sitting-saved');
  static const ValueKey<String> questionKey = ValueKey<String>('assessment-sitting-question');
  static const ValueKey<String> otherFieldKey = ValueKey<String>('assessment-sitting-other');
  static const ValueKey<String> otherRowKey = ValueKey<String>('assessment-sitting-other-row');
  static const ValueKey<String> previousKey = ValueKey<String>('assessment-sitting-previous');
  static const ValueKey<String> nextKey = ValueKey<String>('assessment-sitting-next');
  static const ValueKey<String> submitKey = ValueKey<String>('assessment-sitting-submit');
  static const ValueKey<String> submittedKey = ValueKey<String>('assessment-sitting-submitted');
  static const ValueKey<String> saveFailureKey = ValueKey<String>('assessment-sitting-save-failure');
  static const ValueKey<String> failedKey = ValueKey<String>('assessment-sitting-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('assessment-sitting-retry');

  static ValueKey<String> optionKey(String letter) => ValueKey<String>('assessment-sitting-option-$letter');
  static ValueKey<String> jumpKey(int position) => ValueKey<String>('assessment-sitting-jump-$position');

  @override
  State<AssessmentSittingScreen> createState() => _AssessmentSittingScreenState();
}

class _AssessmentSittingScreenState extends State<AssessmentSittingScreen> {
  final _other = TextEditingController();

  Timer? _ticker;
  Timer? _otherDebounce;
  final Stopwatch _elapsed = Stopwatch();

  /// The position the Other field currently edits, so moving between Questions
  /// loads that Question's own text instead of the previous one's.
  int? _otherPosition;

  /// The paper the stopwatch was started against, so a new paper restarts it.
  String? _timedAttemptId;
  bool _expirySent = false;

  @override
  void dispose() {
    _ticker?.cancel();
    _otherDebounce?.cancel();
    _other.dispose();
    super.dispose();
  }

  void _watch(AssessmentSittingLoaded state) {
    if (_timedAttemptId != state.paper.attempt.id) {
      _timedAttemptId = state.paper.attempt.id;
      _expirySent = false;
      _elapsed
        ..reset()
        ..start();
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {});
        if (!_expirySent && _remainingFor(state) <= Duration.zero) {
          _expirySent = true;
          context.read<AssessmentSittingBloc>().add(const AssessmentSittingExpired());
        }
      });
    }
    final question = state.current;
    if (question != null && question.position != _otherPosition) {
      _otherPosition = question.position;
      _other.text = question.otherText ?? '';
    }
  }

  Duration _remainingFor(AssessmentSittingLoaded state) {
    final left = state.paper.remainingAtFetch - _elapsed.elapsed;
    return left.isNegative ? Duration.zero : left;
  }

  String _clock(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _onOtherChanged(String text, int position) {
    _otherDebounce?.cancel();
    _otherDebounce = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      context
          .read<AssessmentSittingBloc>()
          .add(AssessmentSittingOtherChanged(position: position, text: text));
    });
  }

  Future<void> _submit(AppLocalizations l10n, AssessmentSittingLoaded state) async {
    final bloc = context.read<AssessmentSittingBloc>();
    final unanswered = state.unansweredCount;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AppConfirmDialog(
        title: l10n.assessmentSubmitTitle,
        description: unanswered == 0
            ? l10n.assessmentSubmitMessageAllAnswered
            : l10n.assessmentSubmitMessageUnanswered(unanswered),
        confirmLabel: l10n.assessmentSubmitConfirm,
        dismissLabel: l10n.commonCancel,
        onDismiss: () => Navigator.of(dialogContext).pop(false),
        onConfirm: () => Navigator.of(dialogContext).pop(true),
      ),
    );
    if (confirmed ?? false) bloc.add(const AssessmentSittingSubmitted());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<AssessmentSittingBloc>().state;

    if (state is AssessmentSittingLoaded) _watch(state);

    return Scaffold(
      body: switch (state) {
        AssessmentSittingLoading() => const SkeletonDetail(maxWidth: AssessmentSittingScreen.maxWidth),
        AssessmentSittingUnavailable(message: final message) => PlatformFailureState(
            key: AssessmentSittingScreen.failedKey,
            title: l10n.assessmentsFailedTitle,
            message: message,
            retryKey: AssessmentSittingScreen.retryKey,
            onRetry: () => context
                .read<AssessmentSittingBloc>()
                .add(AssessmentSittingStarted(widget.attemptId)),
          ),
        AssessmentSittingLoaded() => _sitting(context, l10n, state),
      },
    );
  }

  Widget _sitting(BuildContext context, AppLocalizations l10n, AssessmentSittingLoaded state) {
    final theme = Theme.of(context);
    final palette = AppColors.of(context);
    final attempt = state.paper.attempt;
    final question = state.current;

    if (state.submitted) {
      return Center(
        child: AppPageFrame(
          maxWidth: AssessmentSittingScreen.maxWidth,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xl),
            children: [
              AppPageHeader(title: attempt.assessmentTitle ?? '', description: attempt.assessmentNumber),
              const SizedBox(height: Spacing.xl),
              PlatformEmptyState.noneExist(
                key: AssessmentSittingScreen.submittedKey,
                title: l10n.assessmentSubmittedTitle,
                message: attempt.submittedLate
                    ? l10n.assessmentSubmittedLateMessage
                    : l10n.assessmentSubmittedMessage,
              ),
              const SizedBox(height: Spacing.lg),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: FilledButton(
                  onPressed: () => context.go(Routes.assessments),
                  child: Text(l10n.assessmentBackToRegister),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final remaining = _remainingFor(state);

    return Center(
      child: AppPageFrame(
        maxWidth: AssessmentSittingScreen.maxWidth,
        child: Column(
          children: [
            // The sticky header: the clock, the position and the tick, always in
            // view whatever Question is on screen.
            Padding(
              padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.lg, Spacing.lg, Spacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(attempt.assessmentTitle ?? '', style: theme.textTheme.titleMedium),
                        const SizedBox(height: Spacing.xs),
                        Text(
                          [
                            if (attempt.assessmentNumber != null) attempt.assessmentNumber!,
                            if (attempt.processName != null) attempt.processName!,
                          ].join(' · '),
                          style: theme.textTheme.bodySmall?.copyWith(color: palette.textMuted),
                        ),
                      ],
                    ),
                  ),
                  if (state.saving) ...[
                    const SizedBox(width: Spacing.sm),
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ],
                  if (state.savedTick > 0 && !state.saving) ...[
                    const SizedBox(width: Spacing.sm),
                    Text(
                      l10n.assessmentAnswerSaved,
                      key: AssessmentSittingScreen.savedTickKey,
                      style: theme.textTheme.labelSmall?.copyWith(color: palette.textMuted),
                    ),
                  ],
                  const SizedBox(width: Spacing.md),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.md,
                      vertical: Spacing.sm,
                    ),
                    decoration: BoxDecoration(
                      color: palette.cardBorder.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.timer_outlined, size: 18),
                        const SizedBox(width: Spacing.xs),
                        Text(
                          _clock(remaining),
                          key: AssessmentSittingScreen.countdownKey,
                          style: theme.textTheme.titleSmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: question == null
                  ? const SizedBox.shrink()
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.lg, Spacing.lg, Spacing.lg),
                      children: [
                        Text(
                          l10n.assessmentPositionOf(question.position, state.paper.questions.length),
                          key: AssessmentSittingScreen.positionKey,
                          style: theme.textTheme.labelLarge?.copyWith(color: palette.textMuted),
                        ),
                        const SizedBox(height: Spacing.sm),
                        Text(
                          question.questionText,
                          key: AssessmentSittingScreen.questionKey,
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: Spacing.lg),
                        for (final letter in const ['A', 'B', 'C'])
                          _OptionRow(
                            key: AssessmentSittingScreen.optionKey(letter),
                            letter: letter,
                            text: question.optionText(letter) ?? '',
                            selected: question.chosenOption == letter && question.otherText == null,
                            onTap: () => context.read<AssessmentSittingBloc>().add(
                                  AssessmentSittingOptionChosen(
                                    position: question.position,
                                    option: letter,
                                  ),
                                ),
                          ),
                        const SizedBox(height: Spacing.lg),
                        const Divider(),
                        const SizedBox(height: Spacing.sm),
                        // The fourth row: visually separate, never an Option.
                        InkWell(
                          key: AssessmentSittingScreen.otherRowKey,
                          onTap: () => context
                              .read<AssessmentSittingBloc>()
                              .add(AssessmentSittingOptionChosen(
                                position: question.position,
                                option: null,
                              )),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
                            child: Text(
                              l10n.assessmentOtherAnswerLabel,
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: question.otherText != null ? theme.colorScheme.primary : null,
                              ),
                            ),
                          ),
                        ),
                        TextField(
                          key: AssessmentSittingScreen.otherFieldKey,
                          controller: _other,
                          minLines: 1,
                          maxLines: 4,
                          decoration: InputDecoration(
                            hintText: l10n.assessmentOtherAnswerHint,
                            border: const OutlineInputBorder(),
                            helperText: l10n.assessmentOtherAnswerHelper,
                          ),
                          onChanged: (text) => _onOtherChanged(text, question.position),
                        ),
                        if (state.saveFailure != null) ...[
                          const SizedBox(height: Spacing.md),
                          NoticeText(
                            state.saveFailure!,
                            key: AssessmentSittingScreen.saveFailureKey,
                          ),
                        ],
                        if (state.submitFailure != null) ...[
                          const SizedBox(height: Spacing.md),
                          NoticeText(state.submitFailure!),
                        ],
                        const SizedBox(height: Spacing.xl),
                        Wrap(
                          spacing: Spacing.sm,
                          runSpacing: Spacing.xs,
                          children: [
                            for (final other in state.paper.questions)
                              ChoiceChip(
                                key: AssessmentSittingScreen.jumpKey(other.position),
                                label: Text('${other.position}'),
                                selected: other.position == question.position,
                                onSelected: (_) {
                                  // A chip marked as answered, so a skipped
                                  // Question is visible in the row itself.
                                  if (other.isAnswered) return;
                                  context.read<AssessmentSittingBloc>().add(
                                        AssessmentSittingMoved(other.position - 1),
                                      );
                                },
                              ),
                          ],
                        ),
                      ],
                    ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.sm, Spacing.lg, Spacing.sm),
              child: Row(
                children: [
                  OutlinedButton(
                    key: AssessmentSittingScreen.previousKey,
                    onPressed: state.index == 0
                        ? null
                        : () => context
                            .read<AssessmentSittingBloc>()
                            .add(AssessmentSittingMoved(state.index - 1)),
                    child: Text(l10n.assessmentPrevious),
                  ),
                  const SizedBox(width: Spacing.sm),
                  OutlinedButton(
                    key: AssessmentSittingScreen.nextKey,
                    onPressed: state.index >= state.paper.questions.length - 1
                        ? null
                        : () => context
                            .read<AssessmentSittingBloc>()
                            .add(AssessmentSittingMoved(state.index + 1)),
                    child: Text(l10n.assessmentNext),
                  ),
                  const Spacer(),
                  Text(
                    l10n.assessmentAnsweredCount(state.answeredCount, state.paper.questions.length),
                    style: theme.textTheme.labelMedium?.copyWith(color: palette.textMuted),
                  ),
                  const SizedBox(width: Spacing.md),
                  FilledButton(
                    key: AssessmentSittingScreen.submitKey,
                    onPressed: state.submitting ? null : () => _submit(l10n, state),
                    child: Text(l10n.assessmentSubmit),
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

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    super.key,
    required this.letter,
    required this.text,
    required this.selected,
    required this.onTap,
  });

  final String letter;
  final String text;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Container(
          padding: const EdgeInsets.all(Spacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: selected ? theme.colorScheme.primary : Theme.of(context).dividerColor,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 20,
              ),
              const SizedBox(width: Spacing.sm),
              Text('$letter.', style: theme.textTheme.titleSmall),
              const SizedBox(width: Spacing.sm),
              Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
            ],
          ),
        ),
      ),
    );
  }
}
