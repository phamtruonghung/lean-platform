/// One Assessment's detail, at `/assessments/:id` (issue #588, ADR-0068, spec
/// section 8, slice 6): the facts, the four sitting counts and every Attempt,
/// with what a person may do about them.
///
/// **Attempts are grouped per Employee.** The Attempt whose score counts (the
/// person's latest marked one, as the server says with `isCounting`) comes first
/// and is drawn as the primary row; the earlier sittings sit beneath it, each
/// labelled by number. A person with no marked Attempt has their latest sitting
/// first. The Screen never works out which one counts: it reads the flag.
///
/// **An action the server would refuse is disabled, and says why.** The button is
/// off, a tooltip carries the reason and the same sentence is printed under it, so
/// a reader who cannot hover still learns it. The reason is the first refusal that
/// applies, in the order of the spec: the Assessment's own state, then the
/// Attempt's, then permission and reach. The server still decides; these are the
/// refusals it is known to make, said before the request instead of after.
///
/// **Mark is a link**, not an action here: it opens the marking Screen for that
/// paper, and is offered only on a submitted Attempt.
///
/// A score appears only on a marked Attempt, and where the server sent none
/// (`scoreHidden`) the Screen shows `—` (spec section 3.14).
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
import '../widgets/app_confirm_dialog.dart';
import '../widgets/app_detail_section.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/app_page_header.dart';
import '../widgets/disclosing_text.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/status_chip.dart';
import 'assessment.dart';
import 'assessment_assign_dialog.dart';
import 'assessment_detail_bloc.dart';
import 'assessment_reason_dialog.dart';

class AssessmentDetailScreen extends StatelessWidget {
  const AssessmentDetailScreen({super.key});

  static const double maxWidth = 1080;

  static const ValueKey<String> failedKey = ValueKey<String>('assessment-detail-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('assessment-detail-retry');
  static const ValueKey<String> failureKey = ValueKey<String>('assessment-detail-failure');
  static const ValueKey<String> backKey = ValueKey<String>('assessment-detail-back');
  static const ValueKey<String> factsKey = ValueKey<String>('assessment-detail-facts');
  static const ValueKey<String> countsKey = ValueKey<String>('assessment-detail-counts');
  static const ValueKey<String> statusKey = ValueKey<String>('assessment-detail-status');
  static const ValueKey<String> assignKey = ValueKey<String>('assessment-detail-assign');
  static const ValueKey<String> assignReasonKey = ValueKey<String>('assessment-detail-assign-reason');
  static const ValueKey<String> closeKey = ValueKey<String>('assessment-detail-close');
  static const ValueKey<String> closeReasonKey = ValueKey<String>('assessment-detail-close-reason');
  static const ValueKey<String> attemptsEmptyKey = ValueKey<String>('assessment-detail-attempts-empty');

  static ValueKey<String> employeeKey(String employeeId) =>
      ValueKey<String>('assessment-detail-employee-$employeeId');
  static ValueKey<String> attemptRowKey(String id) => ValueKey<String>('assessment-detail-attempt-$id');
  static ValueKey<String> attemptScoreKey(String id) => ValueKey<String>('assessment-detail-score-$id');
  static ValueKey<String> countingKey(String id) => ValueKey<String>('assessment-detail-counting-$id');
  static ValueKey<String> cancelKey(String id) => ValueKey<String>('assessment-detail-cancel-$id');
  static ValueKey<String> cancelReasonKey(String id) =>
      ValueKey<String>('assessment-detail-cancel-reason-$id');
  static ValueKey<String> retakeKey(String id) => ValueKey<String>('assessment-detail-retake-$id');
  static ValueKey<String> retakeReasonKey(String id) =>
      ValueKey<String>('assessment-detail-retake-reason-$id');
  static ValueKey<String> endSittingKey(String id) => ValueKey<String>('assessment-detail-end-sitting-$id');
  static ValueKey<String> endSittingReasonKey(String id) =>
      ValueKey<String>('assessment-detail-end-sitting-reason-$id');
  static ValueKey<String> markKey(String id) => ValueKey<String>('assessment-detail-mark-$id');
  static ValueKey<String> markReasonKey(String id) => ValueKey<String>('assessment-detail-mark-reason-$id');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<AssessmentDetailBloc>().state;

    return Scaffold(
      body: switch (state) {
        AssessmentDetailLoading() => const SkeletonDetail(maxWidth: maxWidth),
        AssessmentDetailUnavailable(message: final message) => PlatformFailureState(
            key: failedKey,
            title: l10n.assessmentDetailFailedTitle,
            message: message,
            retryKey: retryKey,
            onRetry: () => context.read<AssessmentDetailBloc>().add(const AssessmentDetailStarted()),
          ),
        AssessmentDetailLoaded() => _Loaded(state: state),
      },
    );
  }
}

/// The first refusal that applies to an Assessment-level change (Assign, Close),
/// or null when none does.
String? _assessmentRefusal(AppLocalizations l10n, Assessment assessment, {required bool mayChange}) {
  if (assessment.isDraft) return l10n.assessmentReasonDraft;
  if (assessment.isClosed) return l10n.assessmentReasonClosed;
  if (!mayChange) return l10n.assessmentReasonNoChange;
  if (!assessment.viewerMayChange) return l10n.assessmentReasonOutsideReach;
  return null;
}

/// The permission half of an Attempt-level change.
String? _attemptPermissionRefusal(
  AppLocalizations l10n,
  AssessmentAttempt attempt, {
  required bool mayChange,
}) {
  if (!mayChange) return l10n.assessmentReasonNoChange;
  if (!attempt.viewerMayChange) return l10n.assessmentReasonOutsideReach;
  return null;
}

/// The first refusal that applies to a retake, in the spec's order: the
/// Assessment, then the Attempt, then who is asking.
String? _retakeRefusal(
  AppLocalizations l10n,
  Assessment assessment,
  AssessmentAttempt attempt, {
  required bool mayChange,
}) {
  if (assessment.isDraft) return l10n.assessmentReasonDraft;
  if (assessment.isClosed) return l10n.assessmentReasonClosed;
  final finished = attempt.status == attemptSubmitted ||
      attempt.status == attemptMarked ||
      attempt.status == attemptExpired;
  if (!finished) return l10n.assessmentReasonNotFinal;
  if (!attempt.isLatest) return l10n.assessmentReasonNotLatest;
  if (attempt.attemptNo >= assessment.attemptsAllowed) {
    return l10n.assessmentReasonExhausted(assessment.attemptsAllowed);
  }
  return _attemptPermissionRefusal(l10n, attempt, mayChange: mayChange);
}

StatusTone _attemptTone(String status) => switch (status) {
      attemptInProgress => StatusTone.info,
      attemptSubmitted => StatusTone.warning,
      attemptMarked => StatusTone.success,
      _ => StatusTone.neutral,
    };

class _Loaded extends StatelessWidget {
  const _Loaded({required this.state});

  final AssessmentDetailLoaded state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = AppColors.of(context);
    final bloc = context.read<AssessmentDetailBloc>();
    final assessment = state.assessment;
    final mayChange = bloc.mayChange;

    final assignRefusal = _assessmentRefusal(l10n, assessment, mayChange: mayChange);

    return Center(
      child: AppPageFrame(
        maxWidth: AssessmentDetailScreen.maxWidth,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xl),
          children: [
            AppPageHeader(
              title: assessment.title,
              description: [
                assessment.number,
                if (assessment.orgUnitName != null) assessment.orgUnitName!,
              ].join(' · '),
              actions: [
                OutlinedButton.icon(
                  key: AssessmentDetailScreen.backKey,
                  onPressed: () => context.go(Routes.assessments),
                  icon: const Icon(Icons.arrow_back),
                  label: Text(l10n.assessmentBackToRegister),
                ),
              ],
            ),
            const SizedBox(height: Spacing.lg),
            if (state.failure case final failure?) ...[
              AppBanner(
                key: AssessmentDetailScreen.failureKey,
                tone: StatusTone.danger,
                message: failure,
              ),
              const SizedBox(height: Spacing.md),
            ],
            AppDetailSection(
              title: l10n.assessmentDetailFactsTitle,
              children: [
                Wrap(
                  key: AssessmentDetailScreen.factsKey,
                  spacing: Spacing.xl,
                  runSpacing: Spacing.md,
                  children: [
                    _Fact(label: l10n.assessmentFactProcess, value: assessment.orgUnitName ?? '—'),
                    _Fact(
                      label: l10n.assessmentFactPaperSize,
                      value: l10n.assessmentPaperSizeShort(assessment.questionCount),
                    ),
                    _Fact(
                      label: l10n.assessmentMinutesLabel,
                      value: l10n.assessmentMinutesShort(assessment.minutes),
                    ),
                    _Fact(label: l10n.assessmentPassMarkLabel, value: '${assessment.passMark}'),
                    _Fact(
                      label: l10n.assessmentFactAttemptsAllowed,
                      value: '${assessment.attemptsAllowed}',
                    ),
                    _Fact(
                      label: l10n.assessmentDueDateLabel,
                      value: assessment.dueOn ?? l10n.assessmentFactNone,
                    ),
                    _Fact(
                      label: l10n.commonStatus,
                      value: assessment.statusLabel(l10n),
                      valueKey: AssessmentDetailScreen.statusKey,
                    ),
                  ],
                ),
                DisclosingText(
                  l10n.assessmentSittingCounts(
                    assessment.assignedCount,
                    assessment.runningCount,
                    assessment.awaitingMarkingCount,
                    assessment.markedCount,
                  ),
                  key: AssessmentDetailScreen.countsKey,
                  style: theme.textTheme.bodyMedium?.copyWith(color: palette.textMuted),
                ),
              ],
            ),
            const SizedBox(height: Spacing.lg),
            AppDetailSection(
              title: l10n.assessmentActionsTitle,
              children: [
                Wrap(
                  spacing: Spacing.md,
                  runSpacing: Spacing.md,
                  crossAxisAlignment: WrapCrossAlignment.start,
                  children: [
                    _ActionButton(
                      buttonKey: AssessmentDetailScreen.assignKey,
                      reasonKey: AssessmentDetailScreen.assignReasonKey,
                      icon: Icons.group_add_outlined,
                      label: l10n.assessmentAssignButton,
                      reason: assignRefusal,
                      busy: state.isWriting,
                      filled: true,
                      onPressed: () => _assign(context, bloc, assessment),
                    ),
                    _ActionButton(
                      buttonKey: AssessmentDetailScreen.closeKey,
                      reasonKey: AssessmentDetailScreen.closeReasonKey,
                      icon: Icons.lock_outline,
                      label: l10n.assessmentCloseButton,
                      reason: assignRefusal,
                      busy: state.isWriting,
                      onPressed: () => _close(context, bloc),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: Spacing.lg),
            AppDetailSection(
              title: l10n.assessmentAttemptsTitle,
              children: [
                if (assessment.attempts.isEmpty)
                  Text(
                    l10n.assessmentAttemptsEmpty,
                    key: AssessmentDetailScreen.attemptsEmptyKey,
                    style: theme.textTheme.bodyMedium?.copyWith(color: palette.textMuted),
                  )
                else
                  for (final group in _groupByEmployee(assessment.attempts))
                    _EmployeeGroup(
                      key: AssessmentDetailScreen.employeeKey(group.first.employeeId),
                      assessment: assessment,
                      attempts: group,
                      mayChange: mayChange,
                      busy: state.isWriting,
                    ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _assign(BuildContext context, AssessmentDetailBloc bloc, Assessment assessment) async {
    final group = await AssessmentAssignDialog.open(context, siteId: assessment.siteId);
    if (group == null) return;
    bloc.add(AssessmentDetailAssigned(group));
  }

  Future<void> _close(BuildContext context, AssessmentDetailBloc bloc) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AppConfirmDialog(
        title: l10n.assessmentCloseTitle,
        description: l10n.assessmentCloseMessage,
        confirmLabel: l10n.assessmentCloseButton,
        dismissLabel: l10n.commonBack,
        onDismiss: () => Navigator.of(dialogContext).pop(false),
        onConfirm: () => Navigator.of(dialogContext).pop(true),
      ),
    );
    if (confirmed ?? false) bloc.add(const AssessmentDetailClosed());
  }
}

/// The Attempts as one list per Employee, in the order the server first named
/// each person. Within a person the Attempt that counts leads, or, when none is
/// marked, the latest; every other sitting follows, newest first.
List<List<AssessmentAttempt>> _groupByEmployee(List<AssessmentAttempt> attempts) {
  final byEmployee = <String, List<AssessmentAttempt>>{};
  for (final attempt in attempts) {
    byEmployee.putIfAbsent(attempt.employeeId, () => []).add(attempt);
  }
  return [
    for (final group in byEmployee.values)
      () {
        final ordered = [...group]..sort((a, b) => b.attemptNo.compareTo(a.attemptNo));
        final lead = ordered.firstWhere((attempt) => attempt.isCounting, orElse: () => ordered.first);
        return [lead, ...ordered.where((attempt) => attempt != lead)];
      }(),
  ];
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value, this.valueKey});

  final String label;
  final String value;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: theme.textTheme.bodySmall?.copyWith(color: palette.textMuted)),
        const SizedBox(height: Spacing.xs),
        Text(value, key: valueKey, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}

/// A button that is off for a named reason: the reason is the tooltip and is
/// printed under the button, so it reads without hovering.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.buttonKey,
    required this.reasonKey,
    required this.icon,
    required this.label,
    required this.reason,
    required this.busy,
    required this.onPressed,
    this.filled = false,
  });

  final Key buttonKey;
  final Key reasonKey;
  final IconData icon;
  final String label;

  /// Why the action is refused, or null when it is available.
  final String? reason;

  /// A write is in flight: off, with nothing to explain.
  final bool busy;
  final bool filled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppColors.of(context);
    final callback = reason == null && !busy ? onPressed : null;
    final button = filled
        ? FilledButton.icon(key: buttonKey, onPressed: callback, icon: Icon(icon), label: Text(label))
        : OutlinedButton.icon(key: buttonKey, onPressed: callback, icon: Icon(icon), label: Text(label));
    // No width of its own: the parent `Wrap` bounds it to the row, and a
    // Screen states no widths but the centred cards (layout_rules_test).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (reason != null) Tooltip(message: reason!, child: button) else button,
        if (reason != null)
          Padding(
            padding: const EdgeInsets.only(top: Spacing.xs),
            child: Text(
              reason!,
              key: reasonKey,
              style: theme.textTheme.bodySmall?.copyWith(color: palette.textMuted),
            ),
          ),
      ],
    );
  }
}

class _EmployeeGroup extends StatelessWidget {
  const _EmployeeGroup({
    super.key,
    required this.assessment,
    required this.attempts,
    required this.mayChange,
    required this.busy,
  });

  final Assessment assessment;
  final List<AssessmentAttempt> attempts;
  final bool mayChange;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppColors.of(context);
    final lead = attempts.first;
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(lead.employeeName ?? lead.employeeId, style: theme.textTheme.titleSmall),
          const SizedBox(height: Spacing.xs),
          _AttemptRow(
            key: AssessmentDetailScreen.attemptRowKey(lead.id),
            assessment: assessment,
            attempt: lead,
            primary: true,
            mayChange: mayChange,
            busy: busy,
          ),
          for (final earlier in attempts.skip(1))
            Padding(
              padding: const EdgeInsets.only(left: Spacing.lg, top: Spacing.sm),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(left: BorderSide(color: palette.edge)),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(left: Spacing.md),
                  child: _AttemptRow(
                    key: AssessmentDetailScreen.attemptRowKey(earlier.id),
                    assessment: assessment,
                    attempt: earlier,
                    primary: false,
                    mayChange: mayChange,
                    busy: busy,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AttemptRow extends StatelessWidget {
  const _AttemptRow({
    super.key,
    required this.assessment,
    required this.attempt,
    required this.primary,
    required this.mayChange,
    required this.busy,
  });

  final Assessment assessment;
  final AssessmentAttempt attempt;

  /// The row that leads its Employee's group: drawn at full weight, the others
  /// in the muted body style.
  final bool primary;
  final bool mayChange;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = AppColors.of(context);
    final bloc = context.read<AssessmentDetailBloc>();
    final muted = theme.textTheme.bodySmall?.copyWith(color: palette.textMuted);
    final name = attempt.employeeName ?? attempt.employeeId;

    final String? scoreText = attempt.status == attemptMarked
        ? (attempt.scoreHidden || attempt.finalScore == null
            ? l10n.assessmentScoreHidden
            : l10n.assessmentAttemptScore(
                attempt.finalScore!,
                assessment.questionCount,
                assessmentVerdictLabel(l10n, passed: attempt.passed ?? false),
              ))
        : null;

    final permission = _attemptPermissionRefusal(l10n, attempt, mayChange: mayChange);
    final retakeReason = _retakeRefusal(l10n, assessment, attempt, mayChange: mayChange);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: Spacing.sm,
          runSpacing: Spacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              l10n.assessmentAttemptNumber(attempt.attemptNo),
              style: primary ? theme.textTheme.titleSmall : theme.textTheme.bodyMedium,
            ),
            StatusChip(label: attempt.statusLabel(l10n), tone: _attemptTone(attempt.status)),
            if (attempt.isCounting)
              StatusChip(
                key: AssessmentDetailScreen.countingKey(attempt.id),
                label: l10n.assessmentAttemptCounting,
                tone: StatusTone.success,
              ),
          ],
        ),
        if (scoreText != null) ...[
          const SizedBox(height: Spacing.xs),
          Text(
            scoreText,
            key: AssessmentDetailScreen.attemptScoreKey(attempt.id),
            style: primary ? theme.textTheme.titleMedium : theme.textTheme.bodyMedium,
          ),
        ],
        const SizedBox(height: Spacing.xs),
        Text(
          [
            if (attempt.orgUnitName != null) attempt.orgUnitName!,
            if (attempt.markedByName != null) l10n.assessmentResultMarkedBy(attempt.markedByName!),
            if (attempt.submittedLate) l10n.assessmentMarkingLate,
          ].join(' · '),
          style: muted,
        ),
        if (attempt.retakeReason != null)
          Padding(
            padding: const EdgeInsets.only(top: Spacing.xs),
            child: Text(l10n.assessmentRetakeIs(attempt.retakeReason!), style: muted),
          ),
        const SizedBox(height: Spacing.sm),
        Wrap(
          spacing: Spacing.md,
          runSpacing: Spacing.sm,
          crossAxisAlignment: WrapCrossAlignment.start,
          children: [
            if (attempt.status == attemptSubmitted)
              _ActionButton(
                buttonKey: AssessmentDetailScreen.markKey(attempt.id),
                reasonKey: AssessmentDetailScreen.markReasonKey(attempt.id),
                icon: Icons.fact_check_outlined,
                label: l10n.assessmentMarkingOpen,
                reason: assessment.viewerMayMark ? null : l10n.assessmentReasonNoMark,
                busy: busy,
                onPressed: () => context.go(Routes.assessmentMarking(assessment.id, attempt.id)),
              ),
            if (attempt.status == attemptAssigned)
              _ActionButton(
                buttonKey: AssessmentDetailScreen.cancelKey(attempt.id),
                reasonKey: AssessmentDetailScreen.cancelReasonKey(attempt.id),
                icon: Icons.cancel_outlined,
                label: l10n.assessmentCancelAttemptButton,
                reason: permission,
                busy: busy,
                onPressed: () async {
                  final reason = await AssessmentReasonDialog.open(
                    context,
                    title: l10n.assessmentCancelAttemptTitle,
                    description: l10n.assessmentCancelAttemptMessage(name, attempt.attemptNo),
                    label: l10n.assessmentCancelReasonLabel,
                    confirmLabel: l10n.assessmentCancelAttemptButton,
                  );
                  if (reason != null) bloc.add(AssessmentDetailAttemptCancelled(attempt.id, reason));
                },
              ),
            if (attempt.status == attemptInProgress)
              _ActionButton(
                buttonKey: AssessmentDetailScreen.endSittingKey(attempt.id),
                reasonKey: AssessmentDetailScreen.endSittingReasonKey(attempt.id),
                icon: Icons.stop_circle_outlined,
                label: l10n.assessmentEndSittingButton,
                reason: permission,
                busy: busy,
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) => AppConfirmDialog(
                      title: l10n.assessmentEndSittingTitle,
                      description: l10n.assessmentEndSittingMessage,
                      confirmLabel: l10n.assessmentEndSittingButton,
                      dismissLabel: l10n.commonBack,
                      onDismiss: () => Navigator.of(dialogContext).pop(false),
                      onConfirm: () => Navigator.of(dialogContext).pop(true),
                    ),
                  );
                  if (confirmed ?? false) bloc.add(AssessmentDetailSittingEnded(attempt.id));
                },
              ),
            _ActionButton(
              buttonKey: AssessmentDetailScreen.retakeKey(attempt.id),
              reasonKey: AssessmentDetailScreen.retakeReasonKey(attempt.id),
              icon: Icons.replay,
              label: l10n.assessmentRetakeButton,
              reason: retakeReason,
              busy: busy,
              onPressed: () async {
                final reason = await AssessmentReasonDialog.open(
                  context,
                  title: l10n.assessmentRetakeTitle,
                  description: l10n.assessmentRetakeMessage(name),
                  label: l10n.assessmentRetakeReasonLabel,
                  confirmLabel: l10n.assessmentRetakeButton,
                );
                if (reason != null) bloc.add(AssessmentDetailRetakeAllowed(attempt.id, reason));
              },
            ),
          ],
        ),
      ],
    );
  }
}
