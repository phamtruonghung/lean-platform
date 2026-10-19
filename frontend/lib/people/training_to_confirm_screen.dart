/// The Training-to-confirm queue (issue #289, ADR-0043): the sent Training
/// records the signed-in Trainee has not answered yet, oldest first, each with
/// the facts a person needs to answer honestly — what, when, how long, where,
/// who trained — and the two answer controls, Confirm and Decline.
///
/// **Address, deliberately nested under `/training` rather than a second
/// sidebar Destination** — the `/attendance/to-confirm` shape (issue #250):
/// its own bookmarkable address filed under the Training Destination, reached
/// from a Home card. Offered to every approved Account, since the server
/// answers an Account linked to no Employee with an empty list.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../people_api.dart';
import '../platform/auth_gateway.dart';
import '../platform/router.dart';
import '../theme.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import 'training_answer_dialog.dart';
import 'training_record.dart';
import 'training_to_confirm_bloc.dart';

class TrainingToConfirmScreen extends StatelessWidget {
  const TrainingToConfirmScreen({super.key});

  static const double maxWidth = 720;

  static const ValueKey<String> failureKey = ValueKey<String>('training-to-confirm-failure');
  static const ValueKey<String> retryKey = ValueKey<String>('training-to-confirm-retry');
  static const ValueKey<String> emptyKey = ValueKey<String>('training-to-confirm-empty');
  static const ValueKey<String> loadingKey = ValueKey<String>('training-to-confirm-loading');
  static const ValueKey<String> answerFailureKey = ValueKey<String>('training-to-confirm-answer-failure');
  static ValueKey<String> rowKey(String traineeId) => ValueKey<String>('training-to-confirm-row-$traineeId');
  static ValueKey<String> confirmKey(String traineeId) => ValueKey<String>('training-to-confirm-confirm-$traineeId');
  static ValueKey<String> declineKey(String traineeId) => ValueKey<String>('training-to-confirm-decline-$traineeId');

  @override
  Widget build(BuildContext context) {
    return BlocProvider<TrainingToConfirmBloc>(
      create: (_) => TrainingToConfirmBloc(
        peopleApi: context.read<PeopleApi>(),
        authGateway: context.read<AuthGateway>(),
      )..add(const TrainingToConfirmStarted()),
      child: const _Body(),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = context.watch<TrainingToConfirmBloc>().state;
    final bloc = context.read<TrainingToConfirmBloc>();

    final Widget content;
    if (state.failure != null) {
      content = PlatformFailureState(
        key: TrainingToConfirmScreen.failureKey,
        title: 'Your Training to confirm could not be read',
        message: state.failure!,
        retryKey: TrainingToConfirmScreen.retryKey,
        onRetry: () => bloc.add(const TrainingToConfirmStarted()),
      );
    } else if (state.isLoading) {
      content = const Center(
        key: TrainingToConfirmScreen.loadingKey,
        child: Padding(padding: EdgeInsets.all(Spacing.lg), child: CircularProgressIndicator()),
      );
    } else if (state.entries.isEmpty) {
      content = const PlatformEmptyState.noneExist(
        key: TrainingToConfirmScreen.emptyKey,
        title: 'Nothing waiting on you',
        message: 'No Training record has been sent to you that you have not answered.',
        icon: Icons.school_outlined,
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final entry in state.entries) _EntryCard(entry: entry, isWriting: state.isWriting),
          if (state.answerFailure != null)
            Padding(
              key: TrainingToConfirmScreen.answerFailureKey,
              padding: const EdgeInsets.only(top: Spacing.sm),
              child: Text(
                state.answerFailure!,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
              ),
            ),
        ],
      );
    }

    return Scaffold(
      body: Center(
        child: AppPageFrame(
          maxWidth: TrainingToConfirmScreen.maxWidth,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xl),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => context.go(Routes.training),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back to Training records'),
                ),
              ),
              const SizedBox(height: Spacing.sm),
              Text('Training to confirm', style: theme.textTheme.headlineSmall),
              const SizedBox(height: Spacing.sm),
              Text(
                'Training records sent to you that you have not answered yet, oldest first. '
                'Confirm that you attended, or decline because the record is wrong.',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: Spacing.lg),
              content,
            ],
          ),
        ),
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry, required this.isWriting});

  final TrainingToConfirm entry;
  final bool isWriting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bloc = context.read<TrainingToConfirmBloc>();
    final trainer = entry.trainerName;
    final objective = entry.objective;
    return Card(
      key: TrainingToConfirmScreen.rowKey(entry.traineeId),
      margin: const EdgeInsets.only(bottom: Spacing.md),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => context.go('${Routes.training}/${entry.id}'),
              child: Text('${entry.number} · ${entry.title}', style: theme.textTheme.titleMedium),
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              '${entry.trainedOn} · ${formatTrainingHours(entry.durationHours)} · ${entry.orgUnitName}'
              '${trainer == null ? '' : ' · trained by $trainer'}',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (objective != null && objective.isNotEmpty) ...[
              const SizedBox(height: Spacing.xs),
              Text(objective, style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: Spacing.md),
            Wrap(
              spacing: Spacing.sm,
              children: [
                FilledButton(
                  key: TrainingToConfirmScreen.confirmKey(entry.traineeId),
                  onPressed: isWriting
                      ? null
                      : () async {
                          final signature = await showTrainingAnswerDialog(context);
                          if (signature == null) return;
                          bloc.add(TrainingToConfirmAnswered(entry.traineeId, 'confirmed', signature: signature));
                        },
                  child: const Text('Confirm'),
                ),
                OutlinedButton(
                  key: TrainingToConfirmScreen.declineKey(entry.traineeId),
                  onPressed: isWriting ? null : () => bloc.add(TrainingToConfirmAnswered(entry.traineeId, 'declined')),
                  child: const Text('Decline'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
