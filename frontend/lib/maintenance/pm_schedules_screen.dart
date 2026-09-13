/// The PM schedule list: the plans attached to a Site's Assets that raise a
/// Work order before something breaks (issue #74).
///
/// Readable by anyone whose role earns the Maintenance Module — the same rule
/// `WorkOrdersScreen`, `RequestsScreen` and `DowntimeScreen` document. The
/// create button and the deactivate/reactivate action are offered only to a
/// caller who holds a write Grant somewhere: an action the server would refuse
/// is not offered in the first place (the coarse `orgUnitScope.
/// canWriteSomewhere` signal those Screens already use).
///
/// CONTEXT.md's distinction is load-bearing in the copy: a PM schedule is what
/// raises a Work order ahead of a failure, and the anchor says which way its
/// calendar rolls when work runs late.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import 'pm_schedule.dart';
import 'pm_schedule_form_dialog.dart';
import 'pm_schedules_bloc.dart';

class PmSchedulesScreen extends StatelessWidget {
  const PmSchedulesScreen({super.key, required this.canAct});

  /// Whether this caller holds a write Grant anywhere at all — read off
  /// `/me`'s own `orgUnitScope` (issue #43), the same rule the Downtime and
  /// Triage queues apply to their own actions. False hides the create button
  /// and the row toggle entirely; it does not grey them out, because a
  /// disabled button is still an invitation to fail.
  final bool canAct;

  static const double maxWidth = 960;

  static const ValueKey<String> createKey = ValueKey<String>('pm-schedules-create');
  static const ValueKey<String> siteKey = ValueKey<String>('pm-schedules-site');
  static const ValueKey<String> noticeKey = ValueKey<String>('pm-schedules-notice');
  static const ValueKey<String> retryKey = ValueKey<String>('pm-schedules-retry');
  static const ValueKey<String> emptyKey = ValueKey<String>('pm-schedules-empty');
  static const ValueKey<String> failedKey = ValueKey<String>('pm-schedules-failed');

  static ValueKey<String> rowKey(String id) => ValueKey<String>('pm-schedule-row-$id');
  static ValueKey<String> toggleKey(String id) => ValueKey<String>('pm-schedule-toggle-$id');
  static ValueKey<String> inactiveChipKey(String id) => ValueKey<String>('pm-schedule-inactive-$id');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PmSchedulesBloc>().state;

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(state: state, canAct: canAct),
          if (state is PmSchedulesLoaded && state.notice != null) _Notice(message: state.notice!),
          Expanded(
            child: switch (state) {
              PmSchedulesLoading() => const SkeletonList(rows: 4, maxWidth: maxWidth),
              PmSchedulesUnavailable(message: final message) => PlatformFailureState(
                  key: PmSchedulesScreen.failedKey,
                  title: 'The PM schedules could not be read',
                  message: message,
                  retryKey: PmSchedulesScreen.retryKey,
                  onRetry: () => context.read<PmSchedulesBloc>().add(const PmSchedulesStarted()),
                ),
              PmSchedulesLoaded(isLoadingSchedules: true) =>
                const SkeletonList(rows: 4, maxWidth: maxWidth),
              PmSchedulesLoaded(schedules: final schedules) when schedules.isEmpty =>
                const _PmSchedulesEmpty(),
              PmSchedulesLoaded(schedules: final schedules) =>
                _PmSchedulesList(schedules: schedules, canAct: canAct),
            },
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state, required this.canAct});

  final PmSchedulesState state;
  final bool canAct;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loaded = state is PmSchedulesLoaded ? state as PmSchedulesLoaded : null;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: PmSchedulesScreen.maxWidth),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('PM schedules', style: theme.textTheme.headlineSmall),
                        const SizedBox(height: Spacing.xs),
                        Text(
                          'The Job plans attached to this Site\'s Assets that raise a Work order '
                          'before something breaks.',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  if (canAct && loaded != null)
                    FilledButton.icon(
                      key: PmSchedulesScreen.createKey,
                      onPressed: loaded.isMutating || loaded.siteId == null
                          ? null
                          : () => PmScheduleFormDialog.open(context, siteId: loaded.siteId!),
                      icon: const Icon(Icons.event_repeat_outlined),
                      label: const Text('Add a PM schedule'),
                      style: FilledButton.styleFrom(minimumSize: const Size(44, 44)),
                    ),
                ],
              ),
              if (loaded != null && loaded.sites.length > 1) ...[
                const SizedBox(height: Spacing.md),
                SizedBox(
                  width: 280,
                  child: DropdownButtonFormField<String>(
                    key: PmSchedulesScreen.siteKey,
                    initialValue: loaded.siteId,
                    isDense: true,
                    decoration: const InputDecoration(labelText: 'Site', border: OutlineInputBorder()),
                    items: [
                      for (final site in loaded.sites)
                        DropdownMenuItem<String>(value: site.id, child: Text(site.name)),
                    ],
                    onChanged: (siteId) {
                      if (siteId == null) return;
                      context.read<PmSchedulesBloc>().add(PmSchedulesSiteSelected(siteId));
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
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
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: PmSchedulesScreen.maxWidth),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.md),
          child: Container(
            key: PmSchedulesScreen.noticeKey,
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

class _PmSchedulesList extends StatelessWidget {
  const _PmSchedulesList({required this.schedules, required this.canAct});

  final List<PmSchedule> schedules;
  final bool canAct;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: PmSchedulesScreen.maxWidth),
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
          itemCount: schedules.length,
          separatorBuilder: (_, _) => const SizedBox(height: Spacing.sm),
          itemBuilder: (context, index) =>
              _PmScheduleCard(schedule: schedules[index], canAct: canAct),
        ),
      ),
    );
  }
}

class _PmScheduleCard extends StatelessWidget {
  const _PmScheduleCard({required this.schedule, required this.canAct});

  final PmSchedule schedule;
  final bool canAct;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final state = context.watch<PmSchedulesBloc>().state;
    final busy = state is PmSchedulesLoaded && state.isMutating;

    return Card(
      key: PmSchedulesScreen.rowKey(schedule.id),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(schedule.jobPlanName, style: theme.textTheme.titleSmall),
                      const SizedBox(height: Spacing.xxs),
                      Text(
                        '${schedule.assetName} (${schedule.assetCode}) · ${schedule.orgUnitName}',
                        style: muted,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Spacing.md),
                if (!schedule.isActive)
                  Chip(
                    key: PmSchedulesScreen.inactiveChipKey(schedule.id),
                    label: const Text('Inactive'),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: theme.colorScheme.errorContainer,
                    labelStyle: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.onErrorContainer),
                  ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            Wrap(
              spacing: Spacing.md,
              runSpacing: Spacing.xxs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (schedule.isMeterDriven)
                  Text(
                    'Every ${_trim(schedule.intervalMeter)} of ${schedule.meterName ?? schedule.meterCode ?? 'the meter'}',
                    style: muted,
                  )
                else
                  Text('Every ${schedule.intervalDays} days', style: muted),
                Text('Rolls from ${schedule.anchorLabel}', style: muted),
                Text('Raised ${schedule.leadTimeDays} days early', style: muted),
                Text('Priority ${schedule.priority}', style: muted),
                if (schedule.isMeterDriven && schedule.currentMeter != null && schedule.nextDueMeter != null)
                  Text(
                    'Accumulated ${_trim(schedule.currentMeter)} of ${_trim(schedule.nextDueMeter)}',
                    style: muted,
                  ),
                Text(_dueLabel(schedule), style: muted),
              ],
            ),
            if (canAct) ...[
              const SizedBox(height: Spacing.md),
              OutlinedButton(
                key: PmSchedulesScreen.toggleKey(schedule.id),
                onPressed: busy
                    ? null
                    : () => context.read<PmSchedulesBloc>().add(
                          PmScheduleActiveToggled(
                            pmScheduleId: schedule.id,
                            isActive: !schedule.isActive,
                          ),
                        ),
                style: OutlinedButton.styleFrom(minimumSize: const Size(44, 44)),
                child: Text(schedule.isActive ? 'Deactivate' : 'Reactivate'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// The next due point in words, using the server's own computed state
  /// rather than doing arithmetic on the client. A meter-driven schedule has
  /// no date; it is due once accumulated use reaches its target (ADR-0029).
  static String _dueLabel(PmSchedule schedule) {
    if (schedule.isMeterDriven) {
      if (schedule.meterDue) return 'Due now';
      if (schedule.nextDueMeter == null) return 'No meter target yet';
      return 'Due at ${_trim(schedule.nextDueMeter)}';
    }
    final nextDueOn = schedule.nextDueOn;
    if (nextDueOn == null) return 'No due date yet';
    final days = schedule.daysUntilDue;
    if (days == null) return 'Next due $nextDueOn';
    if (days < 0) return 'Overdue since $nextDueOn';
    if (days == 0) return 'Due today';
    return 'Due $nextDueOn (in $days days)';
  }

  /// A number without a trailing `.0`, the same way the meter list shows its
  /// readings.
  static String _trim(num? value) {
    if (value == null) return '—';
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toString();
  }
}

class _PmSchedulesEmpty extends StatelessWidget {
  const _PmSchedulesEmpty();

  @override
  Widget build(BuildContext context) {
    return const PlatformEmptyState.noneExist(
      key: PmSchedulesScreen.emptyKey,
      title: 'Nothing is scheduled',
      message: 'No PM schedule is attached to this Site\'s Assets yet.',
    );
  }
}
