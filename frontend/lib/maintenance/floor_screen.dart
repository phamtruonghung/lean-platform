/// The floor-facing surface (issue #77, ADR-0016): what is open at a shared
/// device's machine, and how a technician records it.
///
/// This is its own Screen, with its own address and its own layout — NOT the
/// desktop Shell narrowed until a tablet fits. It is not a Destination and is
/// never reached through the Shell's sidebar (issue #33: the Shell is
/// desktop-first, and this surface is designed rather than adapted). It reads
/// TALLER and larger than a desktop list on purpose: it is read at arm's
/// length, standing at a machine.
///
/// The device cannot sign in, so nothing here touches `AccountBloc`. It reads
/// through the device credential and writes through the technician's own
/// identification, obtained for one action at a time by
/// [FloorTechnicianDialog].
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/status_chip.dart';
import 'floor_bloc.dart';
import 'floor_technician_dialog.dart';
import 'work_order.dart';

class FloorScreen extends StatelessWidget {
  const FloorScreen({super.key});

  /// The Start action on a row, so a test can target it without depending on
  /// its label.
  static ValueKey<String> startKey(String workOrderId) =>
      ValueKey<String>('floor-start-$workOrderId');

  /// The Complete action on a row.
  static ValueKey<String> completeKey(String workOrderId) =>
      ValueKey<String>('floor-complete-$workOrderId');

  /// The retry a failed load offers.
  static const ValueKey<String> retryKey = ValueKey<String>('floor-retry');

  /// The refresh action in the header.
  static const ValueKey<String> refreshKey = ValueKey<String>('floor-refresh');

  /// The floor list's own loading placeholders, so a test can tell a slow read
  /// from an empty or failed one.
  static const ValueKey<String> loadingKey = ValueKey<String>('floor-loading');

  Future<void> _start(BuildContext context, WorkOrder workOrder) =>
      _identify(context, workOrder, requireNote: false);

  Future<void> _complete(BuildContext context, WorkOrder workOrder) =>
      _identify(context, workOrder, requireNote: true);

  Future<void> _identify(
    BuildContext context,
    WorkOrder workOrder, {
    required bool requireNote,
  }) async {
    final bloc = context.read<FloorBloc>();
    await showDialog<void>(
      context: context,
      builder: (_) => BlocProvider<FloorBloc>.value(
        value: bloc,
        child: FloorTechnicianDialog(
          workOrderId: workOrder.id,
          workOrderNo: workOrder.workOrderNo,
          requireNote: requireNote,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: BlocBuilder<FloorBloc, FloorState>(
          builder: (context, state) => switch (state) {
            FloorLoading() => const _FloorFrame(
                orgUnitName: null,
                child: _FloorSkeleton(key: loadingKey),
              ),
            FloorUnavailable(message: final message) => _FloorFrame(
                orgUnitName: null,
                child: PlatformFailureState(
                  title: 'The floor work could not be loaded',
                  message: message,
                  retryKey: retryKey,
                  onRetry: () => context.read<FloorBloc>().add(const FloorStarted()),
                ),
              ),
            FloorLoaded(
              info: final info,
              workOrders: final workOrders,
              isActing: final isActing,
              notice: final notice,
            ) =>
              _FloorFrame(
                orgUnitName: info.orgUnitName,
                onRefresh: isActing
                    ? null
                    : () => context.read<FloorBloc>().add(const FloorStarted()),
                notice: notice,
                child: workOrders.isEmpty
                    ? PlatformEmptyState.noneExist(
                        title: 'No open work',
                        message: 'There is no open work for ${info.orgUnitName} right now.',
                        actionLabel: 'Refresh',
                        actionKey: refreshKey,
                        onAction: () => context.read<FloorBloc>().add(const FloorStarted()),
                        icon: Icons.check_circle_outline,
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.md, Spacing.lg, Spacing.xl),
                        itemCount: workOrders.length,
                        separatorBuilder: (_, _) => const SizedBox(height: Spacing.md),
                        itemBuilder: (_, index) => _FloorWorkOrderCard(
                          workOrder: workOrders[index],
                          isActing: isActing,
                          onStart: () => _start(context, workOrders[index]),
                          onComplete: () => _complete(context, workOrders[index]),
                        ),
                      ),
              ),
          },
        ),
      ),
    );
  }
}

/// The persistent floor chrome — the device's own area named at the top, the
/// work beneath. Deliberately not the Shell: no sidebar, no account footer,
/// no Destination. A device has no person to sign out.
class _FloorFrame extends StatelessWidget {
  const _FloorFrame({
    required this.child,
    this.orgUnitName,
    this.onRefresh,
    this.notice,
  });

  final Widget child;
  final String? orgUnitName;
  final VoidCallback? onRefresh;
  final String? notice;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: Theme.of(context).colorScheme.primary,
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.md, Spacing.md, Spacing.md),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Floor work',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: Theme.of(context).colorScheme.onPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    if (orgUnitName != null)
                      Text(
                        orgUnitName!,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onPrimary,
                            ),
                      ),
                  ],
                ),
              ),
              if (onRefresh != null)
                IconButton(
                  key: FloorScreen.refreshKey,
                  onPressed: onRefresh,
                  color: Theme.of(context).colorScheme.onPrimary,
                  iconSize: 32,
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh),
                ),
            ],
          ),
        ),
        if (notice != null)
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.secondaryContainer,
            padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: Spacing.sm),
            child: Text(notice!, style: Theme.of(context).textTheme.bodyLarge),
          ),
        Expanded(child: child),
      ],
    );
  }
}

/// One large card: what the job is, where, and the one action it offers. Sized
/// and typed for reading at arm's length.
class _FloorWorkOrderCard extends StatelessWidget {
  const _FloorWorkOrderCard({
    required this.workOrder,
    required this.isActing,
    required this.onStart,
    required this.onComplete,
  });

  final WorkOrder workOrder;
  final bool isActing;
  final VoidCallback onStart;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: Spacing.xs),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text('P${workOrder.priority}', style: theme.textTheme.titleMedium),
                ),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: Text(
                    workOrder.workOrderNo,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                // The floor surface is not the desktop list narrowed (ADR-0016),
                // but a status means the same thing on both — issue #168's own
                // user story 7 names this surface, and it was the last list in
                // the Platform showing a state as plain text while every other
                // one painted it.
                StatusChip(label: workOrder.statusLabel, tone: workOrder.statusTone),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            Text('${workOrder.assetCode} · ${workOrder.assetName}', style: theme.textTheme.titleLarge),
            const SizedBox(height: Spacing.xxs),
            Text(workOrder.summary, style: theme.textTheme.titleLarge),
            const SizedBox(height: Spacing.md),
            if (workOrder.status == 'approved')
              FilledButton.icon(
                key: FloorScreen.startKey(workOrder.id),
                onPressed: isActing ? null : onStart,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64)),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start'),
              )
            else if (workOrder.status == 'in_progress')
              FilledButton.icon(
                key: FloorScreen.completeKey(workOrder.id),
                onPressed: isActing ? null : onComplete,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64)),
                icon: const Icon(Icons.check),
                label: const Text('Complete'),
              ),
          ],
        ),
      ),
    );
  }
}

/// The floor list's own loading shape: a few tall, large-text placeholders in
/// the same card language the real rows use, rather than the desktop
/// SkeletonList's compact rows.
class _FloorSkeleton extends StatelessWidget {
  const _FloorSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final fill = Theme.of(context).colorScheme.surfaceContainerHighest;
    Widget bar(double fraction, double height) => Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: fraction,
            child: Container(
              height: height,
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(AppRadius.card / 2),
              ),
            ),
          ),
        );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: ListView.separated(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.md, Spacing.lg, Spacing.xl),
          itemCount: 4,
          separatorBuilder: (_, _) => const SizedBox(height: Spacing.md),
          itemBuilder: (_, _) => Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(Spacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  bar(0.3, 18),
                  const SizedBox(height: Spacing.md),
                  bar(0.7, 24),
                  const SizedBox(height: Spacing.sm),
                  bar(0.5, 24),
                  const SizedBox(height: Spacing.lg),
                  Container(
                    height: 64,
                    decoration: BoxDecoration(
                      color: fill,
                      borderRadius: BorderRadius.circular(AppRadius.card / 2),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
