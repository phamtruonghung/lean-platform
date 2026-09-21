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

import '../platform/floor_device_gateway.dart';
import '../quality/floor_nonconformance_bloc.dart';
import '../quality/floor_nonconformance_dialog.dart';
import '../quality/quality_api.dart';
import '../safety/floor_safety_incident_bloc.dart';
import '../safety/floor_safety_incident_dialog.dart';
import '../safety/floor_safety_observation_bloc.dart';
import '../safety/floor_safety_observation_dialog.dart';
import '../safety/safety_api.dart';
import '../theme.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/status_chip.dart';
import 'floor_bloc.dart';
import 'floor_technician_dialog.dart';
import 'maintenance_api.dart';
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

  /// The Record-a-Non-conformance action (issue #207) — the floor surface's
  /// own door into Quality's record, offered from the header so it is there
  /// whether or not there is open work on the line.
  static const ValueKey<String> recordNonconformanceKey =
      ValueKey<String>('floor-record-nonconformance');

  /// The Report-a-Safety-incident action (issue #227) — the floor surface's
  /// own door into Safety's record, offered beside the Non-conformance action
  /// for the same reason: it is reachable whether or not the line has
  /// anything open.
  static const ValueKey<String> reportSafetyIncidentKey =
      ValueKey<String>('floor-report-safety-incident');

  /// The Record-a-Safety-observation action (issue #230) — the floor
  /// surface's own door into recording the leading indicator, offered beside
  /// the other two actions for the same reason: reachable whether or not the
  /// line has anything open.
  static const ValueKey<String> recordSafetyObservationKey =
      ValueKey<String>('floor-record-safety-observation');

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

  /// Records a Non-conformance from this device (issue #207).
  ///
  /// The Bloc is built here, from the repositories this Screen's own context
  /// reaches, and handed to the dialog the same way [FloorBloc] is handed to
  /// the technician prompt — a dialog pushed by `showDialog` is a route of its
  /// own and does not sit under this Screen's providers. It carries the Org
  /// Unit the device is registered at, which is what the record is filed
  /// against, and it is created fresh per action so nothing an operator typed
  /// outlives the record they typed it for.
  ///
  /// What lands comes back as the Non-conformance's own number, which is shown
  /// on this Screen rather than in the dialog: the operator is looking at the
  /// line, and "NC-HCM-2026-00042 is on the log" is the sentence they need.
  Future<void> _recordNonconformance(BuildContext context, String orgUnitId) async {
    final recorded = await showDialog<String>(
      context: context,
      builder: (_) => BlocProvider<FloorNonconformanceBloc>(
        create: (context) => FloorNonconformanceBloc(
          qualityApi: context.read<QualityApi>(),
          maintenanceApi: context.read<MaintenanceApi>(),
          floorDeviceGateway: context.read<FloorDeviceGateway>(),
          orgUnitId: orgUnitId,
        )..add(const FloorNonconformanceStarted()),
        child: const FloorNonconformanceDialog(),
      ),
    );
    if (recorded == null || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(recorded)));
  }

  /// Reports a Safety incident from this device (issue #227), mirroring
  /// [_recordNonconformance] exactly: the Bloc is built here, from the
  /// repositories this Screen's own context reaches, and handed to the dialog
  /// fresh per action, carrying the Org Unit the device is registered at.
  ///
  /// The identified Employee is recorded as the reporter and there is no
  /// Account on this path at all (ADR-0016), and there is no anonymous option
  /// anywhere in the flow (ADR-0036) — identification is required before the
  /// dialog's submit button is ever enabled.
  ///
  /// What lands comes back as the incident's own number, shown on this Screen
  /// rather than in the dialog, the same "the operator is looking at the
  /// line" reasoning [_recordNonconformance] gives.
  Future<void> _reportSafetyIncident(BuildContext context, String orgUnitId) async {
    final reported = await showDialog<String>(
      context: context,
      builder: (_) => BlocProvider<FloorSafetyIncidentBloc>(
        create: (context) => FloorSafetyIncidentBloc(
          safetyApi: context.read<SafetyApi>(),
          maintenanceApi: context.read<MaintenanceApi>(),
          floorDeviceGateway: context.read<FloorDeviceGateway>(),
          orgUnitId: orgUnitId,
        ),
        child: const FloorSafetyIncidentDialog(),
      ),
    );
    if (reported == null || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(reported)));
  }

  /// Records a Safety observation from this device (issue #230), mirroring
  /// [_reportSafetyIncident] exactly: the Bloc is built here, from the
  /// repositories this Screen's own context reaches, and handed to the
  /// dialog fresh per action, carrying the Org Unit the device is registered
  /// at.
  ///
  /// The identified Employee is recorded as the observer and there is no
  /// Account on this path at all (ADR-0016).
  ///
  /// What lands comes back as a plain confirmation — an observation carries
  /// no number of its own the way a Safety incident does — shown on this
  /// Screen rather than in the dialog, the same "the operator is looking at
  /// the line" reasoning [_reportSafetyIncident] gives.
  Future<void> _recordSafetyObservation(BuildContext context, String orgUnitId) async {
    final recorded = await showDialog<String>(
      context: context,
      builder: (_) => BlocProvider<FloorSafetyObservationBloc>(
        create: (context) => FloorSafetyObservationBloc(
          safetyApi: context.read<SafetyApi>(),
          maintenanceApi: context.read<MaintenanceApi>(),
          floorDeviceGateway: context.read<FloorDeviceGateway>(),
          orgUnitId: orgUnitId,
        ),
        child: const FloorSafetyObservationDialog(),
      ),
    );
    if (recorded == null || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(recorded)));
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
                // Offered whatever the list holds — an empty line is exactly
                // when somebody has found something and needs somewhere to say
                // so — and disabled only while a transition is in flight, the
                // same rule the row actions follow.
                onRecordNonconformance: isActing
                    ? null
                    : () => _recordNonconformance(context, info.orgUnitId),
                onReportSafetyIncident: isActing
                    ? null
                    : () => _reportSafetyIncident(context, info.orgUnitId),
                onRecordSafetyObservation: isActing
                    ? null
                    : () => _recordSafetyObservation(context, info.orgUnitId),
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
    this.onRecordNonconformance,
    this.onReportSafetyIncident,
    this.onRecordSafetyObservation,
    this.notice,
  });

  final Widget child;
  final String? orgUnitName;
  final VoidCallback? onRefresh;
  final VoidCallback? onRecordNonconformance;
  final VoidCallback? onReportSafetyIncident;
  final VoidCallback? onRecordSafetyObservation;
  final String? notice;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: Theme.of(context).colorScheme.primary,
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.md, Spacing.md, Spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The title and Refresh, on their own row: with three actions
              // now offered below (issue #230 added the third), a single Row
              // holding the title, every action and Refresh no longer fits
              // even at a tablet's own width — this two-tier shape is what
              // keeps that row from ever overflowing regardless of how many
              // actions this surface grows to offer.
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
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
              if (onRecordNonconformance != null ||
                  onReportSafetyIncident != null ||
                  onRecordSafetyObservation != null) ...[
                const SizedBox(height: Spacing.sm),
                // The action strip under the title: a `Wrap`, not a fixed
                // Row, so a fourth action or a longer label wraps onto a
                // second line instead of overflowing — the same shape this
                // repo's own action groups already use (e.g.
                // work_orders_screen.dart, capa_detail_screen.dart).
                Wrap(
                  spacing: Spacing.sm,
                  runSpacing: Spacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // Recording a Non-conformance is the one Quality action
                    // the floor surface offers (issue #207) — it is not work
                    // on a row, so it is offered here, reachable whether or
                    // not the line has anything open.
                    if (onRecordNonconformance != null)
                      FilledButton.icon(
                        key: FloorScreen.recordNonconformanceKey,
                        onPressed: onRecordNonconformance,
                        style: FilledButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.onPrimary,
                          foregroundColor: Theme.of(context).colorScheme.primary,
                          // A 48px-tall target, but not `Size.fromHeight` —
                          // that is an infinite WIDTH, which a button inside
                          // a Wrap cannot take (only a stretched one can).
                          minimumSize: const Size(0, 48),
                        ),
                        icon: const Icon(Icons.report_outlined),
                        label: const Text('Non-conformance'),
                      ),
                    // Reporting a Safety incident is the one Safety action
                    // the floor surface offers (issue #227), beside the
                    // Non-conformance action for the same reason —
                    // reachable whether or not the line has anything open.
                    if (onReportSafetyIncident != null)
                      FilledButton.icon(
                        key: FloorScreen.reportSafetyIncidentKey,
                        onPressed: onReportSafetyIncident,
                        style: FilledButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.onPrimary,
                          foregroundColor: Theme.of(context).colorScheme.primary,
                          minimumSize: const Size(0, 48),
                        ),
                        icon: const Icon(Icons.health_and_safety_outlined),
                        label: const Text('Safety incident'),
                      ),
                    // Recording a Safety observation is the third action the
                    // floor surface offers (issue #230), beside the other
                    // two for the same reason — reachable whether or not the
                    // line has anything open.
                    if (onRecordSafetyObservation != null)
                      FilledButton.icon(
                        key: FloorScreen.recordSafetyObservationKey,
                        onPressed: onRecordSafetyObservation,
                        style: FilledButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.onPrimary,
                          foregroundColor: Theme.of(context).colorScheme.primary,
                          minimumSize: const Size(0, 48),
                        ),
                        icon: const Icon(Icons.visibility_outlined),
                        label: const Text('Observation'),
                      ),
                  ],
                ),
              ],
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
      child: AppPageFrame(
        maxWidth: 900,
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
