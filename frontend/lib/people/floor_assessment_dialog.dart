/// An Employee with no Account sitting an Assessment at the shared floor device
/// (issue #588, ADR-0068, slice 5): the second door onto the same Attempt the
/// sitting Screen gives an Account.
///
/// It is a dialog, not a Screen: CONTEXT.md's Screen entry says a dialog inside a
/// Screen is not a Screen, and the floor surface is reached as it already is (no
/// new Destination, no new Shell chrome). It is opened by `showDialog` from the
/// floor Screen with the Bloc provided by the caller, the way
/// [FloorTrainingDialog] is, and `barrierDismissible: false`, so a stray tap
/// beside a running paper cannot close it.
///
/// Four steps in one dialog, driven by [FloorAssessmentState]:
///
///  * **identify** — Employee number and PIN, the training dialog's own fields;
///  * **list** — the open Attempts this device reaches, each with Start or
///    Continue;
///  * **sit** — one Question per screen, the sticky header carrying the
///    candidate's name, the position, the save tick and the countdown, a
///    navigator marking each Question answered, Other or blank, and Previous /
///    Next. Every answer is saved as it is given, under the sitting token;
///  * **closed** — "awaiting marking", or the score once a Marker has marked it.
///
/// The paper fills the dialog (`Dialog.fullscreen`) on a 10-inch touch tablet, in
/// the same 760 px column the Account door's sitting Screen uses, with the same
/// strings. The countdown is the one described in `assessment_sitting_screen.dart`:
/// a [Stopwatch] over `deadlineAt - serverNow`, re-anchored whenever **either the
/// Attempt or the payload's `serverNow` changes** (every autosave answers with a
/// fresh one), with the expiry latch cleared on a fresh running paper.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/app_localizations.dart';
import '../l10n/vocabulary.dart';
import '../status_tone.dart';
import '../theme.dart';
import '../widgets/app_confirm_dialog.dart';
import '../widgets/app_scan_field.dart';
import '../widgets/notice_text.dart';
import '../widgets/status_chip.dart';
import 'assessment.dart';
import 'floor_assessment_bloc.dart';

class FloorAssessmentDialog extends StatefulWidget {
  const FloorAssessmentDialog({super.key});

  static const double maxWidth = 760;

  static const ValueKey<String> employeeNoKey = ValueKey<String>('floor-assessment-employee-no');
  static const ValueKey<String> pinKey = ValueKey<String>('floor-assessment-pin');
  static const ValueKey<String> submitKey = ValueKey<String>('floor-assessment-submit');
  static const ValueKey<String> doneKey = ValueKey<String>('floor-assessment-done');
  static const ValueKey<String> failureKey = ValueKey<String>('floor-assessment-failure');
  static const ValueKey<String> listKey = ValueKey<String>('floor-assessment-list');
  static const ValueKey<String> emptyKey = ValueKey<String>('floor-assessment-empty');
  static const ValueKey<String> candidateKey = ValueKey<String>('floor-assessment-candidate');
  static const ValueKey<String> countdownKey = ValueKey<String>('floor-assessment-countdown');
  static const ValueKey<String> positionKey = ValueKey<String>('floor-assessment-position');
  static const ValueKey<String> savedTickKey = ValueKey<String>('floor-assessment-saved');
  static const ValueKey<String> questionKey = ValueKey<String>('floor-assessment-question');
  static const ValueKey<String> otherRowKey = ValueKey<String>('floor-assessment-other-row');
  static const ValueKey<String> otherFieldKey = ValueKey<String>('floor-assessment-other');
  static const ValueKey<String> navigatorKey = ValueKey<String>('floor-assessment-navigator');
  static const ValueKey<String> previousKey = ValueKey<String>('floor-assessment-previous');
  static const ValueKey<String> nextKey = ValueKey<String>('floor-assessment-next');
  static const ValueKey<String> submitPaperKey = ValueKey<String>('floor-assessment-submit-paper');
  static const ValueKey<String> saveFailureKey = ValueKey<String>('floor-assessment-save-failure');
  static const ValueKey<String> submittedKey = ValueKey<String>('floor-assessment-submitted');
  static const ValueKey<String> resultKey = ValueKey<String>('floor-assessment-result');
  static const ValueKey<String> checkResultKey = ValueKey<String>('floor-assessment-check-result');

  static ValueKey<String> rowKey(String attemptId) => ValueKey<String>('floor-assessment-row-$attemptId');
  static ValueKey<String> startKey(String attemptId) => ValueKey<String>('floor-assessment-start-$attemptId');
  static ValueKey<String> optionKey(String letter) => ValueKey<String>('floor-assessment-option-$letter');
  static ValueKey<String> jumpKey(int position) => ValueKey<String>('floor-assessment-jump-$position');

  @override
  State<FloorAssessmentDialog> createState() => _FloorAssessmentDialogState();
}

class _FloorAssessmentDialogState extends State<FloorAssessmentDialog> {
  final TextEditingController _employeeNo = TextEditingController();
  final TextEditingController _pin = TextEditingController();
  final TextEditingController _other = TextEditingController();

  Timer? _ticker;
  Timer? _otherDebounce;
  final Stopwatch _elapsed = Stopwatch();

  /// The position the Other field currently edits, so moving between Questions
  /// loads that Question's own text instead of the previous one's.
  int? _otherPosition;

  /// The payload the stopwatch was anchored against: the Attempt **and** the
  /// server instant it was produced at. Anchoring on the Attempt alone subtracts
  /// the sitting's age twice once an autosave has replaced the payload.
  String? _timedAttemptId;
  DateTime? _timedServerNow;

  /// The newest payload, so the ticking closure reads the current paper.
  FloorAssessmentSitting? _latest;
  bool _expirySent = false;

  @override
  void dispose() {
    _ticker?.cancel();
    _otherDebounce?.cancel();
    _employeeNo.dispose();
    _pin.dispose();
    _other.dispose();
    super.dispose();
  }

  bool get _ready => _employeeNo.text.trim().isNotEmpty && _pin.text.trim().isNotEmpty;

  void _identify() {
    if (!_ready) return;
    context.read<FloorAssessmentBloc>().add(
          FloorAssessmentIdentified(employeeNo: _employeeNo.text.trim(), pin: _pin.text.trim()),
        );
    // The PIN has done its one job; do not leave it in the field.
    _pin.clear();
  }

  // The sitting has ended, or never began: nothing the next paper anchors on may
  // survive, so a restarted paper counts as a new Attempt with a cleared latch.
  void _leaveSitting() {
    _latest = null;
    _timedAttemptId = null;
    _timedServerNow = null;
    _otherPosition = null;
    _otherDebounce?.cancel();
  }

  void _watch(FloorAssessmentSitting state) {
    _latest = state;
    final attemptId = state.paper.attempt.id;
    final serverNow = state.paper.serverNow;
    if (_timedAttemptId != attemptId || _timedServerNow != serverNow) {
      final newAttempt = _timedAttemptId != attemptId;
      _timedAttemptId = attemptId;
      _timedServerNow = serverNow;
      // A re-anchored clock can expire, so the ask is re-armed — but only while
      // the server still reports the paper as running with time left on it.
      if (newAttempt || (state.paper.isRunning && state.paper.remainingAtFetch > Duration.zero)) {
        _expirySent = false;
      }
      _elapsed
        ..reset()
        ..start();
    }
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final latest = _latest;
      if (latest == null) return;
      setState(() {});
      if (!_expirySent && latest.paper.isRunning && !latest.submitted && _remainingFor(latest) <= Duration.zero) {
        _expirySent = true;
        context.read<FloorAssessmentBloc>().add(const FloorAssessmentExpired());
      }
    });
    final question = state.current;
    if (question != null && question.position != _otherPosition) {
      _otherPosition = question.position;
      _other.text = question.otherText ?? '';
    }
  }

  Duration _remainingFor(FloorAssessmentSitting state) {
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
      context.read<FloorAssessmentBloc>().add(FloorAssessmentOtherChanged(position: position, text: text));
    });
  }

  Future<void> _submit(AppLocalizations l10n, FloorAssessmentSitting state) async {
    final bloc = context.read<FloorAssessmentBloc>();
    final blanks = state.blankPositions;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AppConfirmDialog(
        title: l10n.assessmentSubmitTitle,
        description: blanks.isEmpty
            ? l10n.assessmentSubmitMessageAllAnswered
            : l10n.floorAssessmentSubmitMessageBlanks(blanks.join(', ')),
        confirmLabel: l10n.assessmentSubmitConfirm,
        dismissLabel: l10n.commonCancel,
        onDismiss: () => Navigator.of(dialogContext).pop(false),
        onConfirm: () => Navigator.of(dialogContext).pop(true),
      ),
    );
    if (confirmed ?? false) bloc.add(const FloorAssessmentSubmitted());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return BlocBuilder<FloorAssessmentBloc, FloorAssessmentState>(
      builder: (context, state) {
        if (state is! FloorAssessmentSitting) _leaveSitting();
        return switch (state) {
          FloorAssessmentIdentifying() => _identifyDialog(l10n, state),
          FloorAssessmentListed() => _listDialog(l10n, state),
          FloorAssessmentSitting() => _sittingDialog(l10n, state),
        };
      },
    );
  }

  // -------------------------------------------------------------------------
  // Identify
  // -------------------------------------------------------------------------

  Widget _failure(String? failure) {
    if (failure == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      key: FloorAssessmentDialog.failureKey,
      padding: const EdgeInsets.only(top: Spacing.md),
      child: NoticeText(failure, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error)),
    );
  }

  Widget _identifyDialog(AppLocalizations l10n, FloorAssessmentIdentifying state) {
    return AlertDialog(
      title: Text(l10n.floorAssessmentYourAssessment),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.floorAssessmentWhoAreYou,
                style: AppTypography.body(context)?.copyWith(color: AppColors.of(context).textMuted),
              ),
              const SizedBox(height: Spacing.md),
              AppScanField(
                key: FloorAssessmentDialog.employeeNoKey,
                controller: _employeeNo,
                label: l10n.commonEmployeeNumber,
                helperText: l10n.floorTrainingScanTheBadgeOrTypeTheNumber,
                enabled: !state.isBusy,
                autofocus: true,
                advanceFocusOnScan: true,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: Spacing.md),
              TextField(
                key: FloorAssessmentDialog.pinKey,
                controller: _pin,
                enabled: !state.isBusy,
                obscureText: true,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(labelText: l10n.commonPin, border: const OutlineInputBorder()),
              ),
              _failure(state.failure),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: FloorAssessmentDialog.doneKey,
          onPressed: state.isBusy ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: FloorAssessmentDialog.submitKey,
          onPressed: _ready && !state.isBusy ? _identify : null,
          style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
          child: Text(l10n.floorAssessmentShowMine),
        ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // List
  // -------------------------------------------------------------------------

  Widget _listDialog(AppLocalizations l10n, FloorAssessmentListed state) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(l10n.floorAssessmentFor(state.employeeName)),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: state.attempts.isEmpty
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      key: FloorAssessmentDialog.emptyKey,
                      padding: const EdgeInsets.symmetric(vertical: Spacing.lg),
                      child: Text(l10n.floorAssessmentNothingWaiting, style: theme.textTheme.bodyLarge),
                    ),
                    _failure(state.failure),
                  ],
                )
              : Column(
                  key: FloorAssessmentDialog.listKey,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final attempt in state.attempts) _attemptRow(l10n, attempt, state),
                    _failure(state.failure),
                  ],
                ),
        ),
      ),
      actions: [
        TextButton(
          key: FloorAssessmentDialog.doneKey,
          onPressed: state.isBusy ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.floorAssessmentDone),
        ),
      ],
    );
  }

  Widget _attemptRow(AppLocalizations l10n, AssessmentAttempt attempt, FloorAssessmentListed state) {
    final theme = Theme.of(context);
    final tone = attempt.isRunning ? StatusTone.info : StatusTone.neutral;
    final due = attempt.dueOn;
    return Card(
      key: FloorAssessmentDialog.rowKey(attempt.id),
      margin: const EdgeInsets.only(bottom: Spacing.md),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(attempt.assessmentTitle ?? '', style: theme.textTheme.titleMedium)),
                StatusChip(label: attempt.statusLabel(l10n), tone: tone),
              ],
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              [
                if (attempt.assessmentNumber != null) attempt.assessmentNumber!,
                if (attempt.processName != null) attempt.processName!,
                if (attempt.attemptNo > 1) l10n.assessmentAttemptNumber(attempt.attemptNo),
                if (due != null) l10n.assessmentDueOn(due),
              ].join(' · '),
              style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.of(context).textMuted),
            ),
            const SizedBox(height: Spacing.md),
            FilledButton(
              key: FloorAssessmentDialog.startKey(attempt.id),
              onPressed: state.isBusy
                  ? null
                  : () => context.read<FloorAssessmentBloc>().add(FloorAssessmentStarted(attempt.id)),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
              child: Text(attempt.isRunning ? l10n.assessmentContinue : l10n.assessmentStart),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Sit
  // -------------------------------------------------------------------------

  Widget _sittingDialog(AppLocalizations l10n, FloorAssessmentSitting state) {
    _watch(state);
    return state.submitted ? _closedDialog(l10n, state) : _paperDialog(l10n, state);
  }

  Widget _closedDialog(AppLocalizations l10n, FloorAssessmentSitting state) {
    final theme = Theme.of(context);
    final attempt = state.paper.attempt;
    final result = state.result;
    return AlertDialog(
      title: Text(attempt.assessmentTitle ?? l10n.assessmentSubmittedTitle),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: result == null
              ? Column(
                  key: FloorAssessmentDialog.submittedKey,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l10n.assessmentResultAwaitingTitle, style: theme.textTheme.titleMedium),
                    const SizedBox(height: Spacing.sm),
                    Text(
                      attempt.submittedLate
                          ? l10n.assessmentSubmittedLateMessage
                          : l10n.assessmentSubmittedMessage,
                      style: theme.textTheme.bodyLarge,
                    ),
                    _failure(state.resultFailure),
                  ],
                )
              : Column(
                  key: FloorAssessmentDialog.resultKey,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.assessmentAttemptScore(
                        result.verdict.finalScore ?? 0,
                        result.verdict.questionCount,
                        assessmentVerdictLabel(l10n, passed: result.verdict.passed),
                      ),
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: Spacing.sm),
                    Text(
                      l10n.assessmentResultPassMark(result.verdict.passMark, result.verdict.questionCount),
                      style: theme.textTheme.bodyLarge,
                    ),
                  ],
                ),
        ),
      ),
      actions: [
        if (result == null)
          TextButton(
            key: FloorAssessmentDialog.checkResultKey,
            onPressed: () => context.read<FloorAssessmentBloc>().add(const FloorAssessmentResultRequested()),
            child: Text(l10n.floorAssessmentCheckResult),
          ),
        FilledButton(
          key: FloorAssessmentDialog.doneKey,
          onPressed: () => Navigator.of(context).pop(),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
          child: Text(l10n.floorAssessmentDone),
        ),
      ],
    );
  }

  Widget _paperDialog(AppLocalizations l10n, FloorAssessmentSitting state) {
    final theme = Theme.of(context);
    final palette = AppColors.of(context);
    final attempt = state.paper.attempt;
    final question = state.current;
    final remaining = _remainingFor(state);
    final bloc = context.read<FloorAssessmentBloc>();

    return Dialog.fullscreen(
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: FloorAssessmentDialog.maxWidth),
            child: Column(
              children: [
                // The sticky header: the candidate, the position's paper, the tick
                // and the clock, always in view whatever Question is on screen.
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
                            const SizedBox(height: Spacing.xs),
                            Row(
                              children: [
                                Icon(Icons.person_outline, size: 18, color: palette.textMuted),
                                const SizedBox(width: Spacing.xs),
                                Flexible(
                                  child: Text(
                                    state.employeeName,
                                    key: FloorAssessmentDialog.candidateKey,
                                    style: theme.textTheme.titleSmall,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (state.saving) ...[
                        const SizedBox(width: Spacing.sm),
                        const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                      ],
                      if (state.savedTick > 0 && !state.saving) ...[
                        const SizedBox(width: Spacing.sm),
                        Text(
                          l10n.assessmentAnswerSaved,
                          key: FloorAssessmentDialog.savedTickKey,
                          style: theme.textTheme.labelSmall?.copyWith(color: palette.textMuted),
                        ),
                      ],
                      const SizedBox(width: Spacing.md),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm),
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
                              key: FloorAssessmentDialog.countdownKey,
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
                          padding: const EdgeInsets.all(Spacing.lg),
                          children: [
                            Text(
                              l10n.assessmentPositionOf(question.position, state.paper.questions.length),
                              key: FloorAssessmentDialog.positionKey,
                              style: theme.textTheme.labelLarge?.copyWith(color: palette.textMuted),
                            ),
                            const SizedBox(height: Spacing.sm),
                            Text(
                              question.questionText,
                              key: FloorAssessmentDialog.questionKey,
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: Spacing.lg),
                            for (final letter in const ['A', 'B', 'C'])
                              _OptionRow(
                                key: FloorAssessmentDialog.optionKey(letter),
                                letter: letter,
                                text: question.optionText(letter) ?? '',
                                selected: question.chosenOption == letter && question.otherText == null,
                                onTap: () => bloc.add(
                                  FloorAssessmentOptionChosen(position: question.position, option: letter),
                                ),
                              ),
                            const SizedBox(height: Spacing.md),
                            const Divider(),
                            // The fourth row: visually separate, never an Option.
                            InkWell(
                              key: FloorAssessmentDialog.otherRowKey,
                              onTap: () => bloc.add(
                                FloorAssessmentOptionChosen(position: question.position, option: null),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: Spacing.md),
                                child: Text(
                                  l10n.assessmentOtherAnswerLabel,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    color: question.otherText != null ? theme.colorScheme.primary : null,
                                  ),
                                ),
                              ),
                            ),
                            TextField(
                              key: FloorAssessmentDialog.otherFieldKey,
                              controller: _other,
                              minLines: 1,
                              maxLines: 4,
                              decoration: InputDecoration(
                                hintText: l10n.assessmentOtherAnswerHint,
                                border: const OutlineInputBorder(),
                                helperText: l10n.assessmentOtherAnswerHelper,
                                helperMaxLines: 3,
                              ),
                              onChanged: (text) => _onOtherChanged(text, question.position),
                            ),
                            if (state.saveFailure != null) ...[
                              const SizedBox(height: Spacing.md),
                              NoticeText(state.saveFailure!, key: FloorAssessmentDialog.saveFailureKey),
                            ],
                            if (state.submitFailure != null) ...[
                              const SizedBox(height: Spacing.md),
                              NoticeText(state.submitFailure!),
                            ],
                          ],
                        ),
                ),
                const Divider(height: 1),
                // The navigator is pinned above the buttons, so a skipped
                // Question is always one tap away.
                Padding(
                  key: FloorAssessmentDialog.navigatorKey,
                  padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.sm, Spacing.lg, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: Spacing.sm,
                        runSpacing: Spacing.sm,
                        children: [
                          for (var i = 0; i < state.paper.questions.length; i += 1)
                            _NavigatorChip(
                              key: FloorAssessmentDialog.jumpKey(state.paper.questions[i].position),
                              question: state.paper.questions[i],
                              current: i == state.index,
                              onTap: () => bloc.add(FloorAssessmentMoved(i)),
                            ),
                        ],
                      ),
                      const SizedBox(height: Spacing.xs),
                      Text(
                        '${l10n.assessmentNavigatorAnswered} · ${l10n.assessmentNavigatorOther} · ${l10n.assessmentNavigatorBlank}',
                        style: theme.textTheme.labelSmall?.copyWith(color: palette.textMuted),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.sm, Spacing.lg, Spacing.md),
                  child: Row(
                    children: [
                      OutlinedButton(
                        key: FloorAssessmentDialog.previousKey,
                        onPressed: state.index == 0 ? null : () => bloc.add(FloorAssessmentMoved(state.index - 1)),
                        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                        child: Text(l10n.assessmentPrevious),
                      ),
                      const SizedBox(width: Spacing.sm),
                      OutlinedButton(
                        key: FloorAssessmentDialog.nextKey,
                        onPressed: state.index >= state.paper.questions.length - 1
                            ? null
                            : () => bloc.add(FloorAssessmentMoved(state.index + 1)),
                        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                        child: Text(l10n.assessmentNext),
                      ),
                      const SizedBox(width: Spacing.md),
                      Expanded(
                        child: Text(
                          l10n.assessmentAnsweredCount(state.answeredCount, state.paper.questions.length),
                          style: theme.textTheme.labelMedium?.copyWith(color: palette.textMuted),
                        ),
                      ),
                      FilledButton(
                        key: FloorAssessmentDialog.submitPaperKey,
                        onPressed: state.submitting ? null : () => _submit(l10n, state),
                        style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                        child: Text(l10n.assessmentSubmit),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
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
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.all(Spacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: selected ? theme.colorScheme.primary : theme.dividerColor,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, size: 20),
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

/// One navigator chip: the Question's number, filled when answered with an
/// Option, tinted when it holds an Other answer, outlined when blank; the current
/// one is ringed. 48 px square, a touch target.
class _NavigatorChip extends StatelessWidget {
  const _NavigatorChip({
    super.key,
    required this.question,
    required this.current,
    required this.onTap,
  });

  final AssessmentPaperQuestion question;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final other = question.otherText != null;
    final answered = question.chosenOption != null;
    final (fill, text, state) = switch ((answered, other)) {
      (true, _) => (scheme.primary, scheme.onPrimary, l10n.assessmentNavigatorAnswered),
      (_, true) => (scheme.secondaryContainer, scheme.onSecondaryContainer, l10n.assessmentNavigatorOther),
      _ => (null, scheme.onSurface, l10n.assessmentNavigatorBlank),
    };
    return Tooltip(
      message: l10n.assessmentNavigatorChip(question.position, state),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: current ? scheme.primary : Theme.of(context).dividerColor,
              width: current ? 3 : 1,
            ),
          ),
          child: Text(
            '${question.position}',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(color: text),
          ),
        ),
      ),
    );
  }
}
