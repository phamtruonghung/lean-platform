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
import '../widgets/app_detail_section.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/app_page_header.dart';
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

  /// The page names 1040 so a box of 1000 is reachable: at a 1280 window the
  /// Shell leaves a page box of 1020, and `AppBreakpoints.detailTwoColumn`
  /// (1000) is compared with that box. Under the old 760 it was unreachable at
  /// any window (`docs/design-language.md` §10).
  static const double maxWidth = 1040;

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
          _Header(loaded: state is WorkOrderDetailLoaded),
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
                _WorkOrderBody(workOrder: workOrder, canBook: canBook, canRecord: canRecord),
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

/// Opens a dialog under the Navigator route-scoped `WorkOrderDetailBloc`
/// lives in — `showDialog` builds its route as a sibling, not a descendant,
/// so the Bloc is handed across explicitly the same way `ReceiveDialog.open`
/// hands `StoreStockBloc` across.
void _openDialog(BuildContext context, Widget dialog) {
  final bloc = context.read<WorkOrderDetailBloc>();
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => BlocProvider<WorkOrderDetailBloc>.value(value: bloc, child: dialog),
  );
}

/// The page's own head: the way back, then the shared `AppPageHeader`. What the
/// Work order *is* (its number, summary, Asset, state) is the summary card's,
/// below, once it has loaded.
class _Header extends StatelessWidget {
  const _Header({required this.loaded});

  final bool loaded;

  @override
  Widget build(BuildContext context) {
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
              AppPageHeader(
                title: 'Work order',
                description: loaded ? null : 'The tasks copied from the Job plan that raised it.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkOrderBody extends StatelessWidget {
  const _WorkOrderBody({required this.workOrder, required this.canBook, required this.canRecord});

  final WorkOrder workOrder;
  final bool canBook;
  final bool canRecord;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AppPageFrame(
        maxWidth: WorkOrderDetailScreen.maxWidth,
        // The box is the page's, before its `Spacing.lg` inset: at a 1280 window
        // that is 1020, over 1000, so the booking rail appears; the sections
        // themselves are handed 988. It is the box, not the window, and it is
        // compared at the reader's text scale, so at 2x it stays one column.
        child: LayoutBuilder(
          builder: (context, constraints) {
            final twoColumns = canBook &&
                constraints.maxWidth >=
                    AppBreakpoints.effective(context, AppBreakpoints.detailTwoColumn);
            final sections = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TasksSection(workOrder: workOrder, canRecord: canRecord),
                const SizedBox(height: Spacing.md),
                _CostSection(cost: workOrder.cost),
              ],
            );
            return ListView(
              padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
              children: [
                _SummaryCard(
                  workOrder: workOrder,
                  actions: canBook && !twoColumns ? _BookingActions(workOrder: workOrder) : null,
                ),
                const SizedBox(height: Spacing.md),
                if (twoColumns)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: sections),
                      const SizedBox(width: Spacing.md),
                      Expanded(child: _BookingActions(workOrder: workOrder, stacked: true)),
                    ],
                  )
                else
                  sections,
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The record's identifying fields, first. There is no date on a Work order
/// (`WorkOrder` carries no created, raised or scheduled field), so the card
/// renders no "when" rather than inventing one.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.workOrder, this.actions});

  final WorkOrder workOrder;

  /// The booking actions, when the page is one column and the rail is not there.
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppColors.of(context);

    Widget fact(String label, String value) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: AppTypography.floor(context)?.copyWith(color: palette.textMuted)),
            Text(value, style: AppTypography.dense(context)?.copyWith(color: palette.textPrimary)),
          ],
        );

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    workOrder.workOrderNo,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600, color: palette.textPrimary),
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                // The same `StatusChip` every list uses: the detail read is where
                // somebody checks what state this job is in (issue #168).
                StatusChip(label: workOrder.statusLabel, tone: workOrder.statusTone),
              ],
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              workOrder.summary,
              style: AppTypography.dense(context)?.copyWith(color: palette.textPrimary),
            ),
            const SizedBox(height: Spacing.md),
            Wrap(
              spacing: Spacing.xl,
              runSpacing: Spacing.md,
              children: [
                fact('Asset', '${workOrder.assetName} (${workOrder.assetCode})'),
                fact('Org Unit', workOrder.orgUnitName),
                fact('Work type', workOrder.workTypeLabel),
                fact('Priority', '${workOrder.priority}'),
                fact('Assignee', workOrder.assigneeName ?? 'Unassigned'),
              ],
            ),
            if (actions != null) ...[
              const SizedBox(height: Spacing.md),
              actions!,
            ],
          ],
        ),
      ),
    );
  }
}

/// "Book labour" and "Book a part": in the summary card's action row on one
/// column, stacked in the right rail on two.
class _BookingActions extends StatelessWidget {
  const _BookingActions({required this.workOrder, this.stacked = false});

  final WorkOrder workOrder;
  final bool stacked;

  static final ButtonStyle _style =
      FilledButton.styleFrom(minimumSize: const Size(AppTouchTarget.min, AppTouchTarget.min));

  @override
  Widget build(BuildContext context) {
    final labour = FilledButton.icon(
      key: WorkOrderDetailScreen.bookLabourKey,
      onPressed: () => _openDialog(context, LabourBookingDialog(workOrderId: workOrder.id)),
      style: _style,
      icon: const Icon(Icons.schedule),
      label: const Text('Book labour'),
    );
    final part = FilledButton.icon(
      key: WorkOrderDetailScreen.bookPartKey,
      onPressed: () => _openDialog(context, PartBookingDialog(siteId: workOrder.siteId)),
      style: _style,
      icon: const Icon(Icons.inventory_2_outlined),
      label: const Text('Book a part'),
    );
    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [labour, const SizedBox(height: Spacing.sm), part],
      );
    }
    return Wrap(spacing: Spacing.sm, runSpacing: Spacing.sm, children: [labour, part]);
  }
}

class _TasksSection extends StatelessWidget {
  const _TasksSection({required this.workOrder, required this.canRecord});

  final WorkOrder workOrder;
  final bool canRecord;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    return AppDetailSection(
      title: 'Tasks',
      children: [
        if (workOrder.tasks.isEmpty)
          Text(
            'No steps were copied onto this Work order.',
            key: WorkOrderDetailScreen.emptyTasksKey,
            style: AppTypography.dense(context)?.copyWith(color: palette.textMuted),
          )
        else
          for (final task in workOrder.tasks) _WorkOrderTaskRow(task: task, canRecord: canRecord),
      ],
    );
  }
}

/// What the Work order has cost so far, shown as its two separate facts:
/// hours by activity, and the parts fitted with their total. The distinction
/// is stated on the screen rather than buried, because summing labour here
/// with plant labour cost would double-count every technician (the schema's
/// own warning above `work_order_labour`).
class _CostSection extends StatelessWidget {
  const _CostSection({required this.cost});

  final WorkOrderCost? cost;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final dense = AppTypography.dense(context)?.copyWith(color: palette.textPrimary);
    final muted = AppTypography.dense(context)?.copyWith(color: palette.textMuted);
    final note = AppTypography.floor(context)?.copyWith(color: palette.textMuted);
    final shown = cost ?? const WorkOrderCost.empty();

    return AppDetailSection(
      title: 'Cost so far',
      children: [
        if (!shown.hasLabour)
          Text('No labour has been booked.', key: WorkOrderDetailScreen.emptyLabourKey, style: muted)
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final activity in shown.labourByActivity)
                Padding(
                  key: WorkOrderDetailScreen.activityKey(activity.activity),
                  padding: const EdgeInsets.only(bottom: Spacing.sm),
                  child: _line(
                    Text(activity.label, style: dense),
                    Text(
                      activity.overtimeHours > 0
                          ? '${_hours(activity.hours)} · ${_hours(activity.overtimeHours)} overtime'
                          : _hours(activity.hours),
                      style: dense,
                    ),
                  ),
                ),
              Text(
                'Booked labour is part of the plant labour cost already reported, not new money.',
                key: WorkOrderDetailScreen.labourHoursKey,
                style: note,
              ),
              if (shown.overtimeHours > 0)
                Padding(
                  key: WorkOrderDetailScreen.overtimeKey,
                  padding: const EdgeInsets.only(top: Spacing.xs),
                  child: Text('${_hours(shown.overtimeHours)} of it is overtime.', style: dense),
                ),
            ],
          ),
        if (!shown.hasParts)
          Text('No parts have been fitted.', key: WorkOrderDetailScreen.emptyPartsKey, style: muted)
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final part in shown.parts)
                Padding(
                  key: WorkOrderDetailScreen.partKey(part.id),
                  padding: const EdgeInsets.only(bottom: Spacing.sm),
                  child: _line(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(part.name, style: dense),
                        Text('${_count(part.quantity)} ${part.uomCode} · ${part.sourcedLabel}',
                            style: note),
                      ],
                    ),
                    Text(
                      part.totalCost == null
                          ? 'No cost recorded'
                          : _money(part.totalCost!, part.currency),
                      style: dense,
                    ),
                  ),
                ),
              Row(
                key: WorkOrderDetailScreen.partsTotalKey,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      'Parts are new cost — the one maintenance component that adds.',
                      style: note,
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Text(
                    shown.partsCost == null
                        ? 'No cost recorded'
                        : _money(shown.partsCost!, shown.parts.first.currency),
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(color: palette.textPrimary),
                  ),
                ],
              ),
            ],
          ),
      ],
    );
  }

  /// A label and a figure beside it, both of which wrap rather than push the
  /// other out: at 2x text "3 h · 1 h overtime" is wider than half the card.
  static Widget _line(Widget label, Widget figure) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: label),
          const SizedBox(width: Spacing.sm),
          Flexible(child: Align(alignment: Alignment.centerRight, child: figure)),
        ],
      );

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
    final palette = AppColors.of(context);
    final muted = AppTypography.floor(context)?.copyWith(color: palette.textMuted);
    return Row(
      key: WorkOrderDetailScreen.taskKey(task.id),
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
              Text(
                task.instruction,
                style: AppTypography.dense(context)?.copyWith(color: palette.textPrimary),
              ),
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
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(AppTouchTarget.min, AppTouchTarget.min),
                  ),
                  child: const Text('Record a reading'),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: Spacing.sm),
        StatusChip(label: task.statusLabel, tone: task.statusTone),
      ],
    );
  }
}
