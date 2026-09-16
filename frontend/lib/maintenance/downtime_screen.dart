/// The Downtime Screen: the machines not running at a Site, each offering
/// Close and Classify, with one action to report a Breakdown (issue #73).
///
/// Readable by anyone whose role earns the Maintenance Module — the same rule
/// `WorkOrdersScreen` and `RequestsScreen` document. The row actions and the
/// report button are offered only to a caller who holds a write Grant
/// somewhere: an action the server would refuse is not offered in the first
/// place (the coarse `orgUnitScope.canWriteSomewhere` signal those Screens
/// already use).
///
/// CONTEXT.md's distinction is load-bearing in the copy: reporting a Breakdown
/// is the machine stopping, and the Downtime it produces is the period the
/// machine was not running — this Screen never derives or shows a
/// client-computed duration, only the status and reason the server sent.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/status_chip.dart';
import 'breakdown_report_dialog.dart';
import 'downtime_bloc.dart';
import 'downtime_classify_dialog.dart';
import 'downtime_close_dialog.dart';
import 'downtime_event.dart';

class DowntimeScreen extends StatelessWidget {
  const DowntimeScreen({super.key, required this.canAct});

  /// Whether this caller holds a write Grant anywhere at all — read off
  /// `/me`'s own `orgUnitScope` (issue #43), the same rule the Work order and
  /// Triage queues apply to their own row actions. False hides Close, Classify
  /// and Report entirely; it does not grey them out, because a disabled button
  /// is still an invitation to fail.
  final bool canAct;

  static const double maxWidth = 960;

  static const ValueKey<String> reportKey = ValueKey<String>('downtime-report');
  static const ValueKey<String> siteKey = ValueKey<String>('downtime-site');
  static const ValueKey<String> noticeKey = ValueKey<String>('downtime-notice');
  static const ValueKey<String> retryKey = ValueKey<String>('downtime-retry');
  static const ValueKey<String> emptyKey = ValueKey<String>('downtime-empty');
  static const ValueKey<String> failedKey = ValueKey<String>('downtime-failed');

  static ValueKey<String> rowKey(String id) => ValueKey<String>('downtime-row-$id');
  static ValueKey<String> closeKey(String id) => ValueKey<String>('downtime-close-$id');
  static ValueKey<String> classifyKey(String id) => ValueKey<String>('downtime-classify-$id');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<DowntimeBloc>().state;

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(state: state, canAct: canAct),
          if (state is DowntimeLoaded && state.notice != null) _Notice(message: state.notice!),
          Expanded(
            child: switch (state) {
              DowntimeLoading() => const SkeletonList(rows: 4, maxWidth: maxWidth),
              DowntimeUnavailable(message: final message) => PlatformFailureState(
                  key: DowntimeScreen.failedKey,
                  title: 'The downtime events could not be read',
                  message: message,
                  retryKey: DowntimeScreen.retryKey,
                  onRetry: () => context.read<DowntimeBloc>().add(const DowntimeStarted()),
                ),
              DowntimeLoaded(isLoadingEvents: true) =>
                const SkeletonList(rows: 4, maxWidth: maxWidth),
              DowntimeLoaded(events: final events) when events.isEmpty =>
                const _DowntimeEmpty(),
              DowntimeLoaded(events: final events) =>
                _DowntimeList(events: events, canAct: canAct),
            },
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state, required this.canAct});

  final DowntimeState state;
  final bool canAct;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loaded = state is DowntimeLoaded ? state as DowntimeLoaded : null;

    return Center(
      child: AppPageFrame(
        maxWidth: DowntimeScreen.maxWidth,
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
                        Text('Downtime', style: theme.textTheme.headlineSmall),
                        const SizedBox(height: Spacing.xs),
                        Text(
                          'The machines not running at this Site, the reasons they stopped, '
                          'and how long they have been down.',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  if (canAct && loaded != null)
                    FilledButton.icon(
                      key: DowntimeScreen.reportKey,
                      onPressed: loaded.isReporting || loaded.siteId == null
                          ? null
                          : () => _openReport(context, loaded.siteId!),
                      icon: const Icon(Icons.warning_amber_outlined),
                      label: const Text('Report a breakdown'),
                      style: FilledButton.styleFrom(minimumSize: const Size(44, 44)),
                    ),
                ],
              ),
              if (loaded != null && loaded.sites.length > 1) ...[
                const SizedBox(height: Spacing.md),
                SizedBox(
                  width: 280,
                  child: DropdownButtonFormField<String>(
                    key: DowntimeScreen.siteKey,
                    initialValue: loaded.siteId,
                    isDense: true,
                    decoration: const InputDecoration(labelText: 'Site', border: OutlineInputBorder()),
                    items: [
                      for (final site in loaded.sites)
                        DropdownMenuItem<String>(value: site.id, child: Text(site.name)),
                    ],
                    onChanged: (siteId) {
                      if (siteId == null) return;
                      context.read<DowntimeBloc>().add(DowntimeSiteSelected(siteId));
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

  /// The report dialog is opened with the same `showDialog` shape the Triage
  /// queue's dialogs use: it pushes onto the root Navigator, above the
  /// route-scoped [DowntimeBloc], so the Bloc is re-provided by value.
  Future<void> _openReport(BuildContext context, String siteId) {
    final bloc = context.read<DowntimeBloc>();
    return showDialog<void>(
      context: context,
      builder: (_) => BlocProvider<DowntimeBloc>.value(
        value: bloc,
        child: BreakdownReportDialog(siteId: siteId),
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
        maxWidth: DowntimeScreen.maxWidth,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.md),
          child: Container(
            key: DowntimeScreen.noticeKey,
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

class _DowntimeList extends StatelessWidget {
  const _DowntimeList({required this.events, required this.canAct});

  final List<DowntimeEvent> events;
  final bool canAct;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AppPageFrame(
        maxWidth: DowntimeScreen.maxWidth,
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
          itemCount: events.length,
          separatorBuilder: (_, _) => const SizedBox(height: Spacing.sm),
          itemBuilder: (context, index) => _DowntimeCard(event: events[index], canAct: canAct),
        ),
      ),
    );
  }
}

class _DowntimeCard extends StatelessWidget {
  const _DowntimeCard({required this.event, required this.canAct});

  final DowntimeEvent event;
  final bool canAct;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final state = context.watch<DowntimeBloc>().state;
    final busy = state is DowntimeLoaded && state.isActing;

    return Card(
      key: DowntimeScreen.rowKey(event.id),
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
                      Text(event.assetName, style: theme.textTheme.titleSmall),
                      const SizedBox(height: Spacing.xxs),
                      Text('${event.assetCode} · ${event.orgUnitName}', style: muted),
                    ],
                  ),
                ),
                const SizedBox(width: Spacing.md),
                StatusChip(label: event.statusLabel, tone: event.statusTone),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            Wrap(
              spacing: Spacing.md,
              runSpacing: Spacing.xxs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Started ${_formatInstant(event.startedAt)}', style: muted),
                if (event.downtimeReasonName != null)
                  Text('Reason: ${event.downtimeReasonName}', style: muted),
                if (event.reporterName != null)
                  Text('Reported by ${event.reporterName}', style: muted),
              ],
            ),
            if (canAct && (event.isOpen || !event.isClassified)) ...[
              const SizedBox(height: Spacing.md),
              Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.sm,
                children: [
                  if (event.isOpen)
                    FilledButton(
                      key: DowntimeScreen.closeKey(event.id),
                      onPressed: busy ? null : () => _openClose(context),
                      style: FilledButton.styleFrom(minimumSize: const Size(44, 44)),
                      child: const Text('Close'),
                    ),
                  if (!event.isClassified)
                    OutlinedButton(
                      key: DowntimeScreen.classifyKey(event.id),
                      onPressed: busy ? null : () => _openClassify(context),
                      style: OutlinedButton.styleFrom(minimumSize: const Size(44, 44)),
                      child: const Text('Classify'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openClose(BuildContext context) {
    final bloc = context.read<DowntimeBloc>();
    return showDialog<void>(
      context: context,
      builder: (_) => BlocProvider<DowntimeBloc>.value(
        value: bloc,
        child: DowntimeCloseDialog(downtimeEvent: event),
      ),
    );
  }

  Future<void> _openClassify(BuildContext context) {
    final bloc = context.read<DowntimeBloc>();
    return showDialog<void>(
      context: context,
      builder: (_) => BlocProvider<DowntimeBloc>.value(
        value: bloc,
        child: DowntimeClassifyDialog(downtimeEvent: event),
      ),
    );
  }
}

class _DowntimeEmpty extends StatelessWidget {
  const _DowntimeEmpty();

  @override
  Widget build(BuildContext context) {
    return const PlatformEmptyState.noneExist(
      key: DowntimeScreen.emptyKey,
      title: 'Nothing is down',
      message: 'No machine is recorded as down at this Site.',
    );
  }
}

/// A wire `timestamptz` shown in the device's own local time, formatted by
/// hand the way `AppDateField`/`AppDateTimeField` format theirs (no `intl`).
String _formatInstant(String? value) {
  final parsed = value == null ? null : DateTime.tryParse(value);
  if (parsed == null) return 'now';
  final local = parsed.toLocal();
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${pad(local.month)}-${pad(local.day)} '
      '${pad(local.hour)}:${pad(local.minute)}';
}
