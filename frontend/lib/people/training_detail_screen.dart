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
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../platform/router.dart';
import '../theme.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/status_chip.dart';
import 'org_unit_scope.dart';
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
  static const ValueKey<String> traineesHeadingKey = ValueKey<String>('training-detail-trainees-heading');
  static const ValueKey<String> addTraineeKey = ValueKey<String>('training-detail-add-trainee');
  static const ValueKey<String> removeFailureKey = ValueKey<String>('training-detail-remove-failure');
  static const ValueKey<String> sendKey = ValueKey<String>('training-detail-send');
  static const ValueKey<String> correctKey = ValueKey<String>('training-detail-correct');
  static const ValueKey<String> discardKey = ValueKey<String>('training-detail-discard');
  static const ValueKey<String> discardConfirmKey = ValueKey<String>('training-detail-discard-confirm');
  static const ValueKey<String> discardCancelKey = ValueKey<String>('training-detail-discard-cancel');
  static const ValueKey<String> discardFailureKey = ValueKey<String>('training-detail-discard-failure');
  static const ValueKey<String> sendFailureKey = ValueKey<String>('training-detail-send-failure');
  static const ValueKey<String> readingKey = ValueKey<String>('training-detail-reading');
  static const ValueKey<String> answerFailureKey = ValueKey<String>('training-detail-answer-failure');
  static ValueKey<String> traineeAnswerKey(String id) => ValueKey<String>('training-detail-trainee-answer-$id');
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
              title: 'No such Training record',
              message: 'Nothing is recorded at this address. It may have been removed, or '
                  'the address may be wrong.',
              icon: Icons.search_off_outlined,
              actionLabel: 'Back to Training records',
              actionKey: backKey,
              onAction: () => context.go(Routes.training),
            ),
          TrainingDetailUnavailable(message: final message) => PlatformFailureState(
              key: failedKey,
              title: 'The Training record could not be read',
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
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final trainerName = record.trainerName;
    final objective = record.objective;
    // A draft is only ever shown to a caller who could send it; a sent record
    // is shown to everybody, so its Trainee list is changed only by one who can
    // correct it (the server's own gate, asked again on every write).
    final canChangeTrainees = record.isDraft || canSend;
    return Center(
      child: AppPageFrame(
        maxWidth: TrainingDetailScreen.maxWidth,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xl),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: Spacing.sm,
                children: [
                  TextButton.icon(
                    key: TrainingDetailScreen.backKey,
                    onPressed: () => context.go(Routes.training),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Back to Training records'),
                  ),
                  TextButton.icon(
                    key: TrainingDetailScreen.formKey,
                    onPressed: () => context.go(Routes.trainingForm(record.id)),
                    icon: const Icon(Icons.description_outlined),
                    label: const Text('The form'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Spacing.sm),
            Row(
              children: [
                Flexible(
                  child: Text(
                    record.number,
                    key: TrainingDetailScreen.numberKey,
                    style: theme.textTheme.headlineSmall,
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
            const SizedBox(height: Spacing.xs),
            Text(record.title, key: TrainingDetailScreen.titleKey, style: theme.textTheme.titleMedium),
            const SizedBox(height: Spacing.sm),
            Text(_readingOf(record), key: TrainingDetailScreen.readingKey, style: muted),
            if (record.isDraft && canSend) ...[
              const SizedBox(height: Spacing.md),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  key: TrainingDetailScreen.sendKey,
                  onPressed: isWriting ? null : () => context.read<TrainingDetailBloc>().add(const TrainingRecordSent()),
                  icon: const Icon(Icons.send_outlined),
                  label: const Text('Send to Trainees'),
                ),
              ),
              if (sendFailure != null)
                Padding(
                  key: TrainingDetailScreen.sendFailureKey,
                  padding: const EdgeInsets.only(top: Spacing.sm),
                  child: Text(
                    sendFailure!,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
            ],
            if (canSend) ...[
              const SizedBox(height: Spacing.md),
              Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.sm,
                children: [
                  OutlinedButton.icon(
                    key: TrainingDetailScreen.correctKey,
                    onPressed: isWriting ? null : () => TrainingRaiseDialog.openCorrection(context, record),
                    icon: const Icon(Icons.rule_outlined),
                    label: const Text('Correct record'),
                  ),
                  if (record.isDraft)
                    OutlinedButton.icon(
                      key: TrainingDetailScreen.discardKey,
                      onPressed: isWriting ? null : () => _discard(context),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Discard draft'),
                    ),
                ],
              ),
              if (discardFailure != null)
                Padding(
                  key: TrainingDetailScreen.discardFailureKey,
                  padding: const EdgeInsets.only(top: Spacing.sm),
                  child: Text(
                    discardFailure!,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
            ],
            const SizedBox(height: Spacing.lg),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(Spacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Fact(label: 'Trained on', value: record.trainedOn, valueKey: TrainingDetailScreen.trainedOnKey),
                    _Fact(label: 'Org Unit', value: record.orgUnitName, valueKey: TrainingDetailScreen.orgUnitKey),
                    _Fact(
                      label: 'Duration',
                      value: formatTrainingHours(record.durationHours),
                      valueKey: TrainingDetailScreen.durationKey,
                    ),
                    _Fact(
                      label: 'Trainer',
                      value: trainerName ?? 'Not recorded',
                      valueKey: TrainingDetailScreen.trainerKey,
                    ),
                    _Fact(
                      label: 'Objective',
                      value: objective == null || objective.isEmpty ? 'Not recorded' : objective,
                      valueKey: TrainingDetailScreen.objectiveKey,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Spacing.lg),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Trainees (${record.traineeCount})',
                    key: TrainingDetailScreen.traineesHeadingKey,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (canChangeTrainees)
                  OutlinedButton.icon(
                    key: TrainingDetailScreen.addTraineeKey,
                    onPressed: isWriting
                        ? null
                        : () => TrainingTraineeDialog.open(
                              context,
                              orgUnitId: record.orgUnitId,
                              orgUnitName: record.orgUnitName,
                            ),
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                    label: const Text('Add Trainee'),
                  ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            if (record.trainees.isEmpty)
              Text(
                'No Trainees are on this Training record yet.',
                key: TrainingDetailScreen.noTraineesKey,
                style: muted,
              )
            else
              for (final trainee in record.trainees)
                ListTile(
                  key: TrainingDetailScreen.traineeRowKey(trainee.id),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text('${trainee.employeeNo} · ${trainee.employeeName}'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!record.isDraft)
                        Text(
                          _answerOf(trainee),
                          key: TrainingDetailScreen.traineeAnswerKey(trainee.id),
                        ),
                      if (canSend)
                        _EvaluationPicker(trainee: trainee, isWriting: isWriting)
                      else if (trainee.evaluation != null)
                        Text(
                          'Evaluated: ${trainingEvaluationLabel(trainee.evaluation!)}',
                          key: TrainingDetailScreen.evaluationKey(trainee.id),
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
                                    : () => context
                                        .read<TrainingDetailBloc>()
                                        .add(TrainingTraineeAnswered(trainee.id, 'confirmed')),
                                child: const Text('Confirm'),
                              ),
                              OutlinedButton(
                                key: TrainingDetailScreen.declineKey(trainee.id),
                                onPressed: isWriting
                                    ? null
                                    : () => context
                                        .read<TrainingDetailBloc>()
                                        .add(TrainingTraineeAnswered(trainee.id, 'declined')),
                                child: const Text('Decline'),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  trailing: canChangeTrainees
                      ? IconButton(
                          key: TrainingDetailScreen.removeTraineeKey(trainee.id),
                          tooltip: 'Remove ${trainee.employeeName}',
                          icon: const Icon(Icons.close),
                          onPressed: isWriting
                              ? null
                              : () => context.read<TrainingDetailBloc>().add(TrainingTraineeRemoved(trainee.id)),
                        )
                      : null,
                ),
            if (answerFailure != null)
              Padding(
                key: TrainingDetailScreen.answerFailureKey,
                padding: const EdgeInsets.only(top: Spacing.sm),
                child: Text(
                  answerFailure!,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                ),
              ),
            if (evaluationFailure != null)
              Padding(
                key: TrainingDetailScreen.evaluationFailureKey,
                padding: const EdgeInsets.only(top: Spacing.sm),
                child: Text(
                  evaluationFailure!,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                ),
              ),
            if (removeFailure != null)
              Padding(
                key: TrainingDetailScreen.removeFailureKey,
                padding: const EdgeInsets.only(top: Spacing.sm),
                child: Text(
                  removeFailure!,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Asks before discarding: a draft that goes takes its Trainees with it, and
/// it cannot be brought back. Cancel issues nothing.
Future<void> _discard(BuildContext context) async {
  final bloc = context.read<TrainingDetailBloc>();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Discard this draft?'),
      content: const Text(
        'The draft and the Trainees listed on it will be deleted, and it cannot be brought back. '
        'Nobody has been asked about it yet.',
      ),
      actions: [
        TextButton(
          key: TrainingDetailScreen.discardCancelKey,
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: TrainingDetailScreen.discardConfirmKey,
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Discard'),
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
    final current = trainee.evaluation;
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.xs),
      child: Wrap(
        key: TrainingDetailScreen.evaluationKey(trainee.id),
        spacing: Spacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('Evaluation'),
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
              child: const Text('Clear'),
            ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value, required this.valueKey});

  final String label;
  final String value;
  final Key valueKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(child: Text(value, key: valueKey, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
