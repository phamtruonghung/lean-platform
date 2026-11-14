/// One Training record at `/training/:id` (issue #287, ADR-0043): its number,
/// whether it is still a draft or has been sent, and its facts — the day it
/// was given, how long it lasted, where, who trained and the objective.
///
/// The Trainee section (issue #288) lists who was trained — number and name,
/// in the order they were added — under a heading carrying the count, and says
/// so when nobody is on it yet. While the record is a draft each row carries a
/// remove control and the section an add control (which opens
/// `TrainingTraineeDialog`); a sent record carries them too (issue #291) for a
/// caller who could correct it, an added Trainee being asked at once and a
/// removed one taking their answer with the row. A refused removal is rendered
/// beside the list. A draft the caller could not
/// send reads as "no such Training record" here, exactly as the server answers
/// it (404), so the address does not reveal that the draft exists.
///
/// Sending and answering (issue #289): a draft carries a send control for a
/// caller who could send it (an edit Grant reaching its Org Unit, the same
/// predicate the server asks), and the server's completeness refusal renders
/// beside it. Each Trainee's row reads its answer, the day it came and the
/// door it came through; the record's own reading — not sent, nobody has
/// answered, a decline among the answers, fully confirmed — is the server's
/// computation, shown as it arrives. A Trainee looking at a sent record they
/// are on gets the two answer controls on their own row only.
///
/// Putting a record right (issue #291): a caller who could send it is offered
/// a correction control on a draft and a sent record alike, which opens the
/// raise dialog in correction mode with the record's facts pre-filled, and on
/// a draft only a discard control behind a confirmation. A sent record is
/// never offered discard - sending is where a record becomes evidence. A
/// discarded draft takes the person back to the register.
///
/// **The page shape (issue #394).** A summary card first, then the sections —
/// `docs/design-language.md` §5's order for a detail page, and `AppDetailSection`
/// for each section so their titles, hairlines and insets are the same ones a
/// Work order or a CAPA reads at. The summary card is the record's answer to
/// "what is this and where does it stand": its number and state, what was
/// trained, the server's own reading of the answers, and — under a hairline, so
/// they read as the card's own acts rather than another fact — the controls
/// this caller may use on it, with the server's refusals beside them. Below it,
/// the facts are a section and the Trainees are a section.
///
/// **Which rule holds a mark is stated on the Trainee it belongs to.** Each
/// answered Trainee's row names the Signature its answer carries — `stored`
/// (the one they keep) or `drawn` (a stroke made as they answered) — because
/// that is ADR-0053's rule showing at the one place a reader can check it: the
/// mark is kept in the database against that Employee, and a row that said only
/// "Signed" would be repeating the colour without the fact.
///
/// The page names [maxWidth] 720, so its sections are one column at every
/// window: `detailTwoColumn` (1000) is a box this frame never hands them, and
/// stacking is the documented answer for a frame under it (§10). Naming 1040
/// here to reach two columns would re-decide the page's width, which this slice
/// does not own.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_localizations.dart';
import '../platform/router.dart';
import '../status_tone.dart';
import '../theme.dart';
import '../widgets/app_dialog.dart';
import '../widgets/app_detail_section.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/status_chip.dart';
import 'org_unit_scope.dart';
import 'training_answer_dialog.dart';
import 'training_detail_bloc.dart';
import 'training_raise_dialog.dart';
import 'training_record.dart';
import 'training_trainee_dialog.dart';

class TrainingDetailScreen extends StatelessWidget {
  const TrainingDetailScreen({
    super.key,
    required this.trainingRecordId,
    this.orgUnitScope = const OrgUnitScope.nowhere(),
    this.employeeId,
  });

  final String trainingRecordId;

  /// Where the viewing Account may edit — decides whether the send control is
  /// offered (the server's own `canAct({ write: true })` is the real gate).
  final OrgUnitScope orgUnitScope;

  /// The Employee the viewing Account is linked to, when it is: the Trainee
  /// row carrying this Employee is the one the answer controls appear on.
  final String? employeeId;

  static const double maxWidth = 720;

  static const ValueKey<String> backKey = ValueKey<String>('training-detail-back');

  /// The printed form (issue #292): the record laid out as the plant's bilingual
  /// sheet, outside the Shell. Offered to every reader, not gated — the record
  /// itself is an open read (ADR-0009).
  static const ValueKey<String> formKey = ValueKey<String>('training-detail-form');
  static const ValueKey<String> missingKey = ValueKey<String>('training-detail-missing');
  static const ValueKey<String> failedKey = ValueKey<String>('training-detail-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('training-detail-retry');
  static const ValueKey<String> numberKey = ValueKey<String>('training-detail-number');
  static const ValueKey<String> titleKey = ValueKey<String>('training-detail-title');
  static const ValueKey<String> statusKey = ValueKey<String>('training-detail-status');
  static const ValueKey<String> trainedOnKey = ValueKey<String>('training-detail-trained-on');
  static const ValueKey<String> orgUnitKey = ValueKey<String>('training-detail-org-unit');
  static const ValueKey<String> durationKey = ValueKey<String>('training-detail-duration');
  static const ValueKey<String> trainerKey = ValueKey<String>('training-detail-trainer');
  static const ValueKey<String> objectiveKey = ValueKey<String>('training-detail-objective');
  static const ValueKey<String> noTraineesKey = ValueKey<String>('training-detail-no-trainees');

  /// The Trainees section. The key names the region; #394 moved it from the
  /// section's heading `Text` onto the section itself, because `AppDetailSection`
  /// now owns that heading — it still resolves to exactly one widget, and the
  /// heading's own string ("Trainees (N)") is unchanged.
  static const ValueKey<String> traineesHeadingKey = ValueKey<String>('training-detail-trainees-heading');
  static const ValueKey<String> addTraineeKey = ValueKey<String>('training-detail-add-trainee');
  static const ValueKey<String> removeFailureKey = ValueKey<String>('training-detail-remove-failure');
  static const ValueKey<String> sendKey = ValueKey<String>('training-detail-send');
  static const ValueKey<String> correctKey = ValueKey<String>('training-detail-correct');
  static const ValueKey<String> discardKey = ValueKey<String>('training-detail-discard');

  /// The discard confirmation's two actions. #394 moved this alert onto
  /// `AppDialog` (ADR-0058), which owns its action keys, so the two accessors
  /// keep their names and now resolve to the dialog's own action keys — the
  /// rename the PR lists. Nothing else about the confirmation changed: same
  /// question, same description, same two words, same callbacks.
  static final ValueKey<String> discardConfirmKey = AppDialog.actionKey('training-discard-confirm');
  static final ValueKey<String> discardCancelKey = AppDialog.actionKey('training-discard-cancel');
  static const ValueKey<String> discardFailureKey = ValueKey<String>('training-detail-discard-failure');
  static const ValueKey<String> sendFailureKey = ValueKey<String>('training-detail-send-failure');
  static const ValueKey<String> readingKey = ValueKey<String>('training-detail-reading');
  static const ValueKey<String> answerFailureKey = ValueKey<String>('training-detail-answer-failure');

  /// The summary card, so a test can measure the sections against it.
  static const ValueKey<String> summaryKey = ValueKey<String>('training-detail-summary');
  static ValueKey<String> traineeAnswerKey(String id) => ValueKey<String>('training-detail-trainee-answer-$id');
  static ValueKey<String> traineeSignatureKey(String id) =>
      ValueKey<String>('training-detail-trainee-signature-$id');
  static const ValueKey<String> evaluationFailureKey = ValueKey<String>('training-detail-evaluation-failure');
  static ValueKey<String> evaluationKey(String id) => ValueKey<String>('training-detail-evaluation-$id');
  static ValueKey<String> evaluationChoiceKey(String id, String evaluation) =>
      ValueKey<String>('training-detail-evaluation-$id-$evaluation');
  static ValueKey<String> evaluationClearKey(String id) => ValueKey<String>('training-detail-evaluation-clear-$id');
  static ValueKey<String> confirmKey(String id) => ValueKey<String>('training-detail-confirm-$id');
  static ValueKey<String> declineKey(String id) => ValueKey<String>('training-detail-decline-$id');
  static ValueKey<String> traineeRowKey(String id) => ValueKey<String>('training-detail-trainee-$id');
  static ValueKey<String> removeTraineeKey(String id) => ValueKey<String>('training-detail-remove-trainee-$id');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<TrainingDetailBloc>().state;
    return BlocListener<TrainingDetailBloc, TrainingDetailState>(
      listenWhen: (previous, current) => current is TrainingDetailDiscarded,
      listener: (context, state) => context.go(Routes.training),
      child: Scaffold(
        body: switch (state) {
          TrainingDetailDiscarded() => const SizedBox.shrink(),
          TrainingDetailLoading() => const SkeletonList(rows: 4, maxWidth: maxWidth),
          TrainingDetailUnavailable(isMissing: true) => PlatformEmptyState.noneExist(
              key: missingKey,
              title: l10n.commonNoSuchTrainingRecord,
              message: l10n.nonconformanceDetailMissingMessage,
              icon: Icons.search_off_outlined,
              actionLabel: l10n.commonBackToTrainingRecords,
              actionKey: backKey,
              onAction: () => context.go(Routes.training),
            ),
          TrainingDetailUnavailable(message: final message) => PlatformFailureState(
              key: failedKey,
              title: l10n.trainingDetailTheTrainingRecordCouldNotBeRead,
              message: message,
              retryKey: retryKey,
              onRetry: () => context.read<TrainingDetailBloc>().add(TrainingDetailRequested(trainingRecordId)),
            ),
          TrainingDetailLoaded loaded => _Loaded(
              record: loaded.record,
              isWriting: loaded.isWriting,
              removeFailure: loaded.removeFailure,
              sendFailure: loaded.sendFailure,
              answerFailure: loaded.answerFailure,
              evaluationFailure: loaded.evaluationFailure,
              discardFailure: loaded.discardFailure,
              canSend: orgUnitScope.canWriteAt(loaded.record.orgUnitId),
              employeeId: employeeId,
            ),
        },
      ),
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({
    required this.record,
    required this.isWriting,
    required this.removeFailure,
    required this.sendFailure,
    required this.answerFailure,
    required this.evaluationFailure,
    required this.discardFailure,
    required this.canSend,
    required this.employeeId,
  });

  final TrainingRecord record;
  final bool isWriting;
  final String? removeFailure;
  final String? sendFailure;
  final String? answerFailure;
  final String? evaluationFailure;
  final String? discardFailure;
  final bool canSend;
  final String? employeeId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = AppColors.of(context);
    // A draft is only ever shown to a caller who could send it; a sent record
    // is shown to everybody, so its Trainee list is changed only by one who can
    // correct it (the server's own gate, asked again on every write).
    final canChangeTrainees = record.isDraft || canSend;
    final trainerName = record.trainerName;
    final objective = record.objective;
    return Center(
      child: AppPageFrame(
        maxWidth: TrainingDetailScreen.maxWidth,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xl),
          children: [
            // One level below the register: the way back and the way to the
            // printed sheet are crumbs above the record's own head
            // (`docs/design-language.md` §6).
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: Spacing.sm,
                children: [
                  TextButton.icon(
                    key: TrainingDetailScreen.backKey,
                    onPressed: () => context.go(Routes.training),
                    icon: const Icon(Icons.arrow_back),
                    label: Text(l10n.commonBackToTrainingRecords),
                  ),
                  TextButton.icon(
                    key: TrainingDetailScreen.formKey,
                    onPressed: () => context.go(Routes.trainingForm(record.id)),
                    icon: const Icon(Icons.description_outlined),
                    label: Text(l10n.trainingDetailTheForm),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Spacing.sm),
            // The summary card: what this record is, where it stands, and what
            // this caller may do with it.
            Card(
              key: TrainingDetailScreen.summaryKey,
              margin: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.lg, Spacing.lg, Spacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                record.number,
                                key: TrainingDetailScreen.numberKey,
                                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: palette.textPrimary,
                                    ),
                              ),
                            ),
                            const SizedBox(width: Spacing.sm),
                            StatusChip(
                              key: TrainingDetailScreen.statusKey,
                              label: record.statusLabel,
                              tone: trainingStatusTone(record.status),
                            ),
                          ],
                        ),
                        const SizedBox(height: Spacing.xxs),
                        Text(
                          record.title,
                          key: TrainingDetailScreen.titleKey,
                          style: AppTypography.dense(context)?.copyWith(
                            fontSize: Theme.of(context).textTheme.titleMedium?.fontSize,
                            color: palette.textPrimary,
                          ),
                        ),
                        const SizedBox(height: Spacing.xs),
                        Text(
                          _readingOf(record),
                          key: TrainingDetailScreen.readingKey,
                          style: AppTypography.dense(context)?.copyWith(color: palette.textMuted),
                        ),
                      ],
                    ),
                  ),
                  if (canSend) _summaryActions(context),
                ],
              ),
            ),
            const SizedBox(height: Spacing.md),
            AppDetailSection(
              title: l10n.trainingDetailTheTraining,
              children: [
                TrainingFact(
                  label: l10n.commonTrainedOn,
                  value: record.trainedOn,
                  valueKey: TrainingDetailScreen.trainedOnKey,
                ),
                TrainingFact(
                  label: l10n.commonOrgUnit,
                  value: record.orgUnitName,
                  valueKey: TrainingDetailScreen.orgUnitKey,
                ),
                TrainingFact(
                  label: l10n.trainingDetailDuration,
                  value: formatTrainingHours(record.durationHours),
                  valueKey: TrainingDetailScreen.durationKey,
                ),
                TrainingFact(
                  label: l10n.trainingDetailTrainer,
                  value: trainerName ?? 'Not recorded',
                  valueKey: TrainingDetailScreen.trainerKey,
                ),
                TrainingFact(
                  label: l10n.trainingDetailObjective,
                  value: objective == null || objective.isEmpty ? 'Not recorded' : objective,
                  valueKey: TrainingDetailScreen.objectiveKey,
                ),
              ],
            ),
            const SizedBox(height: Spacing.md),
            AppDetailSection(
              key: TrainingDetailScreen.traineesHeadingKey,
              title: l10n.trainingDetailTrainees(record.traineeCount),
              trailing: canChangeTrainees
                  ? OutlinedButton.icon(
                      key: TrainingDetailScreen.addTraineeKey,
                      onPressed: isWriting
                          ? null
                          : () => TrainingTraineeDialog.open(
                                context,
                                orgUnitId: record.orgUnitId,
                                orgUnitName: record.orgUnitName,
                              ),
                      icon: const Icon(Icons.person_add_alt_1_outlined),
                      label: Text(l10n.commonAddTrainee),
                    )
                  : null,
              children: [
                if (record.trainees.isEmpty)
                  Text(
                    l10n.trainingDetailNoTraineesAreOnThisTrainingRecord,
                    key: TrainingDetailScreen.noTraineesKey,
                    style: AppTypography.dense(context)?.copyWith(color: palette.textMuted),
                  )
                else
                  for (final trainee in record.trainees)
                    _TraineeRow(
                      trainee: trainee,
                      record: record,
                      isWriting: isWriting,
                      canSend: canSend,
                      canChangeTrainees: canChangeTrainees,
                      employeeId: employeeId,
                    ),
                if (answerFailure != null)
                  _FailureText(
                    key: TrainingDetailScreen.answerFailureKey,
                    message: answerFailure!,
                  ),
                if (evaluationFailure != null)
                  _FailureText(
                    key: TrainingDetailScreen.evaluationFailureKey,
                    message: evaluationFailure!,
                  ),
                if (removeFailure != null)
                  _FailureText(
                    key: TrainingDetailScreen.removeFailureKey,
                    message: removeFailure!,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// The record's own acts, under a hairline so they read as the card's footer
  /// rather than as one more fact above them.
  Widget _summaryActions(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Divider(height: 1, thickness: 1, color: palette.edge),
        Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.md, Spacing.lg, Spacing.md),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth <
                  AppBreakpoints.effective(context, AppBreakpoints.headerActionsWrap);
              final controls = Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (record.isDraft)
                    FilledButton.icon(
                      key: TrainingDetailScreen.sendKey,
                      onPressed: isWriting
                          ? null
                          : () => context.read<TrainingDetailBloc>().add(const TrainingRecordSent()),
                      icon: const Icon(Icons.send_outlined),
                      label: Text(l10n.trainingDetailSendToTrainees),
                    ),
                  OutlinedButton.icon(
                    key: TrainingDetailScreen.correctKey,
                    onPressed: isWriting ? null : () => TrainingRaiseDialog.openCorrection(context, record),
                    icon: const Icon(Icons.rule_outlined),
                    label: Text(l10n.commonCorrectRecord),
                  ),
                  if (record.isDraft)
                    OutlinedButton.icon(
                      key: TrainingDetailScreen.discardKey,
                      onPressed: isWriting ? null : () => _discard(context),
                      icon: const Icon(Icons.delete_outline),
                      label: Text(l10n.trainingDetailDiscardDraft),
                    ),
                ],
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (stacked)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [controls],
                    )
                  else
                    Align(alignment: Alignment.centerRight, child: controls),
                  if (sendFailure != null)
                    _FailureText(
                      key: TrainingDetailScreen.sendFailureKey,
                      message: sendFailure!,
                    ),
                  if (discardFailure != null)
                    _FailureText(
                      key: TrainingDetailScreen.discardFailureKey,
                      message: discardFailure!,
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// One fact on the summary's own section: its label at the section's left edge
/// and its value in the same column down the page. The label is three parts of
/// the row and the value five, so a longer label wraps rather than pushing the
/// values out of line; there is no hand-set pixel width here.
class TrainingFact extends StatelessWidget {
  const TrainingFact({super.key, required this.label, required this.value, required this.valueKey});

  final String label;
  final String value;
  final Key valueKey;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: Text(
            label,
            style: AppTypography.floor(context)?.copyWith(color: palette.textMuted),
          ),
        ),
        Expanded(
          flex: 5,
          child: Text(
            value,
            key: valueKey,
            style: AppTypography.dense(context)?.copyWith(color: palette.textPrimary),
          ),
        ),
      ],
    );
  }
}

/// One Trainee: who they are, what they answered, the rule that holds their
/// mark, and the two things a trainer or the Trainee themselves can do about it.
class _TraineeRow extends StatelessWidget {
  const _TraineeRow({
    required this.trainee,
    required this.record,
    required this.isWriting,
    required this.canSend,
    required this.canChangeTrainees,
    required this.employeeId,
  });

  final TrainingTrainee trainee;
  final TrainingRecord record;
  final bool isWriting;
  final bool canSend;
  final bool canChangeTrainees;
  final String? employeeId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = AppColors.of(context);
    final muted = AppTypography.floor(context)?.copyWith(color: palette.textMuted);
    return Padding(
      key: TrainingDetailScreen.traineeRowKey(trainee.id),
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${trainee.employeeNo} · ${trainee.employeeName}',
                  style: AppTypography.dense(context)?.copyWith(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (!record.isDraft)
                  Text(
                    _answerOf(trainee),
                    key: TrainingDetailScreen.traineeAnswerKey(trainee.id),
                    style: muted,
                  ),
                if (!record.isDraft && trainee.signatureAppliedAs != null)
                  Text(
                    switch (trainee.signatureAppliedAs) {
                      'stored' => 'Signed with their kept Signature',
                      _ => 'Signed with a Signature drawn as they answered',
                    },
                    key: TrainingDetailScreen.traineeSignatureKey(trainee.id),
                    style: muted,
                  ),
                if (canSend)
                  _EvaluationPicker(trainee: trainee, isWriting: isWriting)
                else if (trainee.evaluation != null)
                  Text(
                    l10n.trainingDetailEvaluated(trainingEvaluationLabel(trainee.evaluation!)),
                    key: TrainingDetailScreen.evaluationKey(trainee.id),
                    style: muted,
                  ),
                if (!record.isDraft && employeeId != null && trainee.employeeId == employeeId)
                  Padding(
                    padding: const EdgeInsets.only(top: Spacing.xs),
                    child: Wrap(
                      spacing: Spacing.sm,
                      children: [
                        FilledButton(
                          key: TrainingDetailScreen.confirmKey(trainee.id),
                          onPressed: isWriting
                              ? null
                              : () async {
                                  final bloc = context.read<TrainingDetailBloc>();
                                  final signature = await showTrainingAnswerDialog(context);
                                  if (signature == null) return;
                                  bloc.add(TrainingTraineeAnswered(trainee.id, 'confirmed', signature: signature));
                                },
                          child: Text(l10n.commonConfirm),
                        ),
                        OutlinedButton(
                          key: TrainingDetailScreen.declineKey(trainee.id),
                          onPressed: isWriting
                              ? null
                              : () => context
                                  .read<TrainingDetailBloc>()
                                  .add(TrainingTraineeAnswered(trainee.id, 'declined')),
                          child: Text(l10n.commonDecline),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (canChangeTrainees)
            IconButton(
              key: TrainingDetailScreen.removeTraineeKey(trainee.id),
              tooltip: l10n.trainingDetailRemove(trainee.employeeName),
              icon: const Icon(Icons.close),
              onPressed: isWriting
                  ? null
                  : () => context.read<TrainingDetailBloc>().add(TrainingTraineeRemoved(trainee.id)),
            ),
        ],
      ),
    );
  }
}

/// A refusal, where it belongs: under the control that was refused, in the
/// palette's own danger foreground.
class _FailureText extends StatelessWidget {
  const _FailureText({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.sm),
      child: Text(
        message,
        style: AppTypography.dense(context)
            ?.copyWith(color: AppColors.of(context).statusForeground(StatusTone.danger)),
      ),
    );
  }
}

/// Asks before discarding: a draft that goes takes its Trainees with it, and
/// it cannot be brought back. Cancel issues nothing.
Future<void> _discard(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final bloc = context.read<TrainingDetailBloc>();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AppDialog(
      title: l10n.trainingDetailDiscardThisDraft,
      description: l10n.trainingDetailTheDraftAndTheTraineesListedOn,
      size: AppDialogSize.decision,
      actions: [
        AppDialogAction(
          id: 'training-discard-cancel',
          label: l10n.commonCancel,
          kind: AppDialogActionKind.dismiss,
          onPressed: () => Navigator.of(dialogContext).pop(false),
        ),
        AppDialogAction(
          id: 'training-discard-confirm',
          label: l10n.trainingDetailDiscard,
          kind: AppDialogActionKind.destructive,
          onPressed: () => Navigator.of(dialogContext).pop(true),
        ),
      ],
    ),
  );
  if (confirmed ?? false) bloc.add(const TrainingRecordDiscarded());
}

/// The record's reading of its Trainees' answers. Four different sentences
/// for four different states, so "nobody has been asked", "nobody has
/// answered", "somebody declined" and "everybody confirmed" never blur — the
/// server computes the counts, this only words them.
String _readingOf(TrainingRecord record) {
  if (record.isDraft) return 'Not sent yet: nobody has been asked.';
  if (record.fullyConfirmed) return 'Fully confirmed by all ${record.traineeCount} Trainees.';
  if (record.declinedCount > 0) {
    return 'Not fully confirmed: ${record.declinedCount} declined, '
        '${record.confirmedCount} of ${record.traineeCount} confirmed.';
  }
  if (record.answeredCount == 0) return 'Sent: nobody has answered yet.';
  return '${record.confirmedCount} of ${record.traineeCount} confirmed.';
}

/// One Trainee's answer, the day it came and the door it came through.
String _answerOf(TrainingTrainee trainee) {
  final answer = trainee.answer;
  if (answer == null) return 'Not answered yet';
  final at = trainee.answeredAt;
  final day = at == null || at.length < 10 ? '' : ' on ${at.substring(0, 10)}';
  final door = switch (trainee.answeredVia) {
    'account' => ' from their own Account',
    'device' => ' at the floor device',
    _ => '',
  };
  return '${answer == 'confirmed' ? 'Confirmed' : 'Declined'}$day$door';
}

/// The trainer's two-value picker for one Trainee (issue #290): chosen, never
/// typed. Tapping the chip already chosen does nothing; the Clear control is
/// the way back to unevaluated, and is offered only while a value is set.
class _EvaluationPicker extends StatelessWidget {
  const _EvaluationPicker({required this.trainee, required this.isWriting});

  final TrainingTrainee trainee;
  final bool isWriting;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final current = trainee.evaluation;
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.xs),
      child: Wrap(
        key: TrainingDetailScreen.evaluationKey(trainee.id),
        spacing: Spacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(l10n.commonEvaluation),
          for (final evaluation in trainingEvaluations)
            ChoiceChip(
              key: TrainingDetailScreen.evaluationChoiceKey(trainee.id, evaluation),
              label: Text(trainingEvaluationLabel(evaluation)),
              selected: current == evaluation,
              onSelected: isWriting || current == evaluation
                  ? null
                  : (_) => context.read<TrainingDetailBloc>().add(TrainingTraineeEvaluated(trainee.id, evaluation)),
            ),
          if (current != null)
            TextButton(
              key: TrainingDetailScreen.evaluationClearKey(trainee.id),
              onPressed: isWriting
                  ? null
                  : () => context.read<TrainingDetailBloc>().add(TrainingTraineeEvaluated(trainee.id, null)),
              child: Text(l10n.commonClear),
            ),
        ],
      ),
    );
  }
}
