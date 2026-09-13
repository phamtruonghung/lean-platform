/// One Work order's detail: what it is, and the tasks copied onto it from the
/// Job plan that raised it — each with its instruction, status and the Skill
/// it requires (issue #74).
///
/// This is a Screen of its own, reached at `/work-orders/:id`, rather than
/// tasks fetched for every list row: the Site-wide list deliberately carries
/// none (attaching them would be an N+1), so the detail read is the one place
/// a Work order's tasks are shown. Coming back is a `go` to the list, not a
/// `pop`: the detail address is a real route, so a refresh lands on the detail
/// again rather than losing it — the same addressability `WorkOrdersScreen`'s
/// own header records.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../platform/router.dart';
import '../theme.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import 'work_order.dart';
import 'work_order_detail_bloc.dart';

class WorkOrderDetailScreen extends StatelessWidget {
  const WorkOrderDetailScreen({super.key, required this.workOrderId});

  final String workOrderId;

  static const double maxWidth = 760;

  static const ValueKey<String> backKey = ValueKey<String>('work-order-detail-back');
  static const ValueKey<String> retryKey = ValueKey<String>('work-order-detail-retry');
  static const ValueKey<String> failedKey = ValueKey<String>('work-order-detail-failed');
  static const ValueKey<String> emptyTasksKey = ValueKey<String>('work-order-detail-empty-tasks');
  static ValueKey<String> taskKey(String id) => ValueKey<String>('work-order-task-$id');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<WorkOrderDetailBloc>().state;

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(workOrder: state is WorkOrderDetailLoaded ? state.workOrder : null),
          Expanded(
            child: switch (state) {
              WorkOrderDetailLoading() => const SkeletonDetail(maxWidth: maxWidth),
              WorkOrderDetailUnavailable(message: final message) => PlatformFailureState(
                  key: WorkOrderDetailScreen.failedKey,
                  title: 'This Work order could not be read',
                  message: message,
                  retryKey: WorkOrderDetailScreen.retryKey,
                  onRetry: () =>
                      context.read<WorkOrderDetailBloc>().add(const WorkOrderDetailStarted()),
                ),
              WorkOrderDetailLoaded(workOrder: final workOrder) =>
                _WorkOrderTasks(workOrder: workOrder),
            },
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.workOrder});

  final WorkOrder? workOrder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: WorkOrderDetailScreen.maxWidth),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextButton.icon(
                key: WorkOrderDetailScreen.backKey,
                onPressed: () => context.go(Routes.workOrders),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back to Work orders'),
              ),
              const SizedBox(height: Spacing.sm),
              Text('Work order', style: theme.textTheme.headlineSmall),
              const SizedBox(height: Spacing.xs),
              if (workOrder != null) ...[
                Text(workOrder!.summary, style: theme.textTheme.titleMedium),
                const SizedBox(height: Spacing.xxs),
                Text(
                  '${workOrder!.workOrderNo} · ${workOrder!.assetName} '
                  '(${workOrder!.assetCode}) · ${workOrder!.statusLabel}',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ] else
                Text(
                  'The tasks copied from the Job plan that raised it.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkOrderTasks extends StatelessWidget {
  const _WorkOrderTasks({required this.workOrder});

  final WorkOrder workOrder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: WorkOrderDetailScreen.maxWidth),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
          children: [
            Text('Tasks', style: theme.textTheme.titleSmall),
            const SizedBox(height: Spacing.sm),
            if (workOrder.tasks.isEmpty)
              Text(
                'No steps were copied onto this Work order.',
                key: WorkOrderDetailScreen.emptyTasksKey,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              )
            else
              Card(
                margin: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final task in workOrder.tasks) _WorkOrderTaskRow(task: task),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _WorkOrderTaskRow extends StatelessWidget {
  const _WorkOrderTaskRow({required this.task});

  final WorkOrderTask task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Padding(
      key: WorkOrderDetailScreen.taskKey(task.id),
      padding: const EdgeInsets.all(Spacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Text('${task.stepNo}.', style: muted),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(task.instruction, style: theme.textTheme.bodyMedium),
                const SizedBox(height: Spacing.xxs),
                Wrap(
                  spacing: Spacing.md,
                  runSpacing: Spacing.xxs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // The required Skill's name is the fact the ticket's own
                    // criterion asks to be visible on a Work order's task.
                    if (task.hasSkill)
                      Text('Requires ${task.skillName}', style: muted)
                    else
                      Text('No skill required', style: muted),
                    if (task.note != null) Text(task.note!, style: muted),
                    if (task.reading != null) Text('Reading ${task.reading}', style: muted),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: Spacing.sm),
          Chip(label: Text(task.statusLabel), visualDensity: VisualDensity.compact),
        ],
      ),
    );
  }
}
