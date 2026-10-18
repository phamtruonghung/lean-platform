/// One Training record at `/training/:id` (issue #287, ADR-0043): its number,
/// whether it is still a draft or has been sent, and its facts — the day it
/// was given, how long it lasted, where, who trained and the objective.
///
/// The Trainee section (issue #288) lists who was trained — number and name,
/// in the order they were added — under a heading carrying the count, and says
/// so when nobody is on it yet. While the record is a draft each row carries a
/// remove control and the section an add control (which opens
/// `TrainingTraineeDialog`); once it is sent the list is shown without them. A
/// refused removal is rendered beside the list. A draft the caller could not
/// send reads as "no such Training record" here, exactly as the server answers
/// it (404), so the address does not reveal that the draft exists.
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
import 'training_detail_bloc.dart';
import 'training_record.dart';
import 'training_trainee_dialog.dart';

class TrainingDetailScreen extends StatelessWidget {
  const TrainingDetailScreen({super.key, required this.trainingRecordId});

  final String trainingRecordId;

  static const double maxWidth = 720;

  static const ValueKey<String> backKey = ValueKey<String>('training-detail-back');
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
  static ValueKey<String> traineeRowKey(String id) => ValueKey<String>('training-detail-trainee-$id');
  static ValueKey<String> removeTraineeKey(String id) => ValueKey<String>('training-detail-remove-trainee-$id');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TrainingDetailBloc>().state;
    return Scaffold(
      body: switch (state) {
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
        TrainingDetailLoaded(record: final record, isWriting: final isWriting, removeFailure: final failure) =>
          _Loaded(record: record, isWriting: isWriting, removeFailure: failure),
      },
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({required this.record, required this.isWriting, required this.removeFailure});

  final TrainingRecord record;
  final bool isWriting;
  final String? removeFailure;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final trainerName = record.trainerName;
    final objective = record.objective;
    return Center(
      child: AppPageFrame(
        maxWidth: TrainingDetailScreen.maxWidth,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xl),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: TrainingDetailScreen.backKey,
                onPressed: () => context.go(Routes.training),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back to Training records'),
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
                if (record.isDraft)
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
                  trailing: record.isDraft
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
