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
import '../widgets/app_page_frame.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/status_chip.dart';
import 'labour_booking_dialog.dart';
import 'part_booking_dialog.dart';
import 'task_reading_dialog.dart';
import 'work_order.dart';
import 'work_order_detail_bloc.dart';

class WorkOrderDetailScreen extends StatelessWidget {
  const WorkOrderDetailScreen({
    super.key,
    required this.workOrderId,
    this.canBook = false,
    this.canRecord = false,
  });

  final String workOrderId;

  /// Whether this caller holds a write Grant anywhere at all — read off
  /// `/me`'s own `orgUnitScope`, the same coarse signal `AssetsScreen` and
  /// `StoreStockScreen` use. False hides the two booking affordances
  /// entirely, because an action the server would refuse is not offered in
  /// the first place.
  final bool canBook;

  /// Whether this caller holds a write Grant somewhere at all — the same
  /// coarse signal the list's own writable affordances use. A task that names
  /// a meter offers a reading action only to a caller who could write one.
  final bool canRecord;

  static const double maxWidth = 760;

  static const ValueKey<String> backKey = ValueKey<String>('work-order-detail-back');
  static const ValueKey<String> retryKey = ValueKey<String>('work-order-detail-retry');
  static const ValueKey<String> failedKey = ValueKey<String>('work-order-detail-failed');
  static const ValueKey<String> emptyTasksKey = ValueKey<String>('work-order-detail-empty-tasks');
  static const ValueKey<String> noticeKey = ValueKey<String>('work-order-detail-notice');
  static const ValueKey<String> bookLabourKey = ValueKey<String>('work-order-detail-book-labour');
  static const ValueKey<String> bookPartKey = ValueKey<String>('work-order-detail-book-part');
  static const ValueKey<String> emptyLabourKey = ValueKey<String>('work-order-cost-empty-labour');
  static const ValueKey<String> emptyPartsKey = ValueKey<String>('work-order-cost-empty-parts');
  static const ValueKey<String> labourHoursKey = ValueKey<String>('work-order-cost-labour-hours');
  static const ValueKey<String> overtimeKey = ValueKey<String>('work-order-cost-overtime');
  static const ValueKey<String> partsTotalKey = ValueKey<String>('work-order-cost-parts-total');
  static ValueKey<String> activityKey(String activity) =>
      ValueKey<String>('work-order-cost-activity-$activity');
  static ValueKey<String> partKey(String id) => ValueKey<String>('work-order-cost-part-$id');
  static ValueKey<String> taskKey(String id) => ValueKey<String>('work-order-task-$id');
  static ValueKey<String> recordReadingKey(String id) =>
      ValueKey<String>('work-order-task-reading-$id');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<WorkOrderDetailBloc>().state;

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            workOrder: state is WorkOrderDetailLoaded ? state.workOrder : null,
            canBook: canBook,
          ),
          if (state is WorkOrderDetailLoaded && state.notice != null)
            _Notice(message: state.notice!),
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
                _WorkOrderBody(workOrder: workOrder, canRecord: canRecord),
            },
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: AppPageFrame(
        maxWidth: WorkOrderDetailScreen.maxWidth,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.md),
          child: Container(
            key: WorkOrderDetailScreen.noticeKey,
            padding: const EdgeInsets.all(Spacing.md),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 20, color: theme.colorScheme.onSecondaryContainer),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(
                    message,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSecondaryContainer),
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

class _Header extends StatelessWidget {
  const _Header({required this.workOrder, required this.canBook});

  final WorkOrder? workOrder;
  final bool canBook;

  /// Opens a dialog under the Navigator route-scoped `WorkOrderDetailBloc`
  /// lives in — `showDialog` builds its route as a sibling, not a descendant,
  /// so the Bloc is handed across explicitly the same way `ReceiveDialog.open`
  /// hands `StoreStockBloc` across.
  void _open(BuildContext context, Widget dialog) {
    final bloc = context.read<WorkOrderDetailBloc>();
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BlocProvider<WorkOrderDetailBloc>.value(value: bloc, child: dialog),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: AppPageFrame(
        maxWidth: WorkOrderDetailScreen.maxWidth,
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
                  '(${workOrder!.assetCode})',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                // This Screen used to render the Work order's own status as
                // one more word in the identity line above (issue #168's own
                // user story 7, corrected here after review): the detail read
                // is where somebody checks *what state this job is in*, and it
                // was the one place in the Platform still showing that state as
                // plain text. It is the same `StatusChip` every list uses, next
                // to the identity rather than inside it.
                const SizedBox(height: Spacing.sm),
                StatusChip(label: workOrder!.statusLabel, tone: workOrder!.statusTone),
                if (canBook) ...[
                  const SizedBox(height: Spacing.md),
                  Wrap(
                    spacing: Spacing.sm,
                    runSpacing: Spacing.xs,
                    children: [
                      FilledButton.icon(
                        key: WorkOrderDetailScreen.bookLabourKey,
                        onPressed: () => _open(
                          context,
                          LabourBookingDialog(workOrderId: workOrder!.id),
                        ),
                        icon: const Icon(Icons.schedule),
                        label: const Text('Book labour'),
                      ),
                      FilledButton.icon(
                        key: WorkOrderDetailScreen.bookPartKey,
                        onPressed: () => _open(
                          context,
                          PartBookingDialog(siteId: workOrder!.siteId),
                        ),
                        icon: const Icon(Icons.inventory_2_outlined),
                        label: const Text('Book a part'),
                      ),
                    ],
                  ),
                ],
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

class _WorkOrderBody extends StatelessWidget {
  const _WorkOrderBody({required this.workOrder, required this.canRecord});

  final WorkOrder workOrder;
  final bool canRecord;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: AppPageFrame(
        maxWidth: WorkOrderDetailScreen.maxWidth,
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
                    for (final task in workOrder.tasks)
                      _WorkOrderTaskRow(task: task, canRecord: canRecord),
                  ],
                ),
              ),
            const SizedBox(height: Spacing.xl),
            _CostSummary(cost: workOrder.cost),
          ],
        ),
      ),
    );
  }
}

/// What the Work order has cost so far, shown as its two separate facts:
/// hours by activity, and the parts fitted with their total. The distinction
/// is stated on the screen rather than buried, because summing labour here
/// with plant labour cost would double-count every technician (the schema's
/// own warning above `work_order_labour`).
class _CostSummary extends StatelessWidget {
  const _CostSummary({required this.cost});

  final WorkOrderCost? cost;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final shown = cost ?? const WorkOrderCost.empty();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Cost so far', style: theme.textTheme.titleSmall),
        const SizedBox(height: Spacing.sm),
        if (!shown.hasLabour)
          Text(
            'No labour has been booked.',
            key: WorkOrderDetailScreen.emptyLabourKey,
            style: muted,
          )
        else
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (final activity in shown.labourByActivity)
                  ListTile(
                    key: WorkOrderDetailScreen.activityKey(activity.activity),
                    dense: true,
                    title: Text(activity.label),
                    trailing: Text(
                      activity.overtimeHours > 0
                          ? '${_hours(activity.hours)} · ${_hours(activity.overtimeHours)} overtime'
                          : _hours(activity.hours),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                Padding(
                  key: WorkOrderDetailScreen.labourHoursKey,
                  padding: const EdgeInsets.fromLTRB(Spacing.md, Spacing.sm, Spacing.md, Spacing.md),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Booked labour is part of the plant labour cost already reported, not new money.',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ),
                if (shown.overtimeHours > 0)
                  Padding(
                    key: WorkOrderDetailScreen.overtimeKey,
                    padding: const EdgeInsets.fromLTRB(Spacing.md, 0, Spacing.md, Spacing.sm),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${_hours(shown.overtimeHours)} of it is overtime.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: Spacing.lg),
        if (!shown.hasParts)
          Text(
            'No parts have been fitted.',
            key: WorkOrderDetailScreen.emptyPartsKey,
            style: muted,
          )
        else
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (final part in shown.parts)
                  ListTile(
                    key: WorkOrderDetailScreen.partKey(part.id),
                    dense: true,
                    title: Text(part.name),
                    subtitle: Text(
                      '${_count(part.quantity)} ${part.uomCode} · ${part.sourcedLabel}',
                    ),
                    trailing: Text(
                      part.totalCost == null
                          ? 'No cost recorded'
                          : _money(part.totalCost!, part.currency),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                Padding(
                  key: WorkOrderDetailScreen.partsTotalKey,
                  padding: const EdgeInsets.fromLTRB(Spacing.md, Spacing.sm, Spacing.md, Spacing.md),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Parts are new cost — the one maintenance component that adds.',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ),
                      Text(
                        shown.partsCost == null
                            ? 'No cost recorded'
                            : _money(shown.partsCost!, shown.parts.first.currency),
                        style: theme.textTheme.titleSmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// A quantity or hours figure without a pointless trailing `.0` — `2.5`
  /// stays `2.5`, `2.0` reads as `2`.
  static String _count(num value) =>
      value == value.roundToDouble() ? value.toInt().toString() : value.toString();

  static String _hours(num value) => '${_count(value)} h';

  static String _money(num value, String currency) => '${_count(value)} $currency';
}


class _WorkOrderTaskRow extends StatelessWidget {
  const _WorkOrderTaskRow({required this.task, required this.canRecord});

  final WorkOrderTask task;
  final bool canRecord;

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
                    if (task.hasMeter)
                      Text('Records ${task.meterName ?? task.meterCode}', style: muted),
                    if (task.note != null) Text(task.note!, style: muted),
                    if (task.reading != null) Text('Reading ${task.reading}', style: muted),
                  ],
                ),
                if (task.hasMeter && canRecord) ...[
                  const SizedBox(height: Spacing.xs),
                  OutlinedButton(
                    key: WorkOrderDetailScreen.recordReadingKey(task.id),
                    onPressed: () => TaskReadingDialog.open(context, task: task),
                    style: OutlinedButton.styleFrom(minimumSize: const Size(44, 44)),
                    child: const Text('Record a reading'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: Spacing.sm),
          StatusChip(label: task.statusLabel, tone: task.statusTone),
        ],
      ),
    );
  }
}
