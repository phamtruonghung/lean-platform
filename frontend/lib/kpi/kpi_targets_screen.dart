/// One KPI's Targets (ADR-0055) at `/kpi/:kpiId/targets`: what is in force
/// today per grain, and the whole history, newest first. Reached from a
/// catalogue row — it needs a `kpiId`, so it is not a Destination of its own;
/// the Shell lights the catalogue's entry while it is open.
///
/// **Change Target is offered only with write authority** (`canWrite`, from
/// `/me`'s `orgUnitScope.canWriteSomewhere`). A KPI Target is never edited: the
/// dialog appends a new entry from a date, and this history shows every entry
/// ever made, newest first as the server orders it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../platform/router.dart';
import '../theme.dart';
import '../widgets/app_list_card.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import 'change_target_dialog.dart';
import 'kpi_catalogue.dart';
import 'kpi_targets_bloc.dart';

class KpiTargetsScreen extends StatelessWidget {
  const KpiTargetsScreen({super.key, required this.kpiId, required this.canWrite});

  final int kpiId;
  final bool canWrite;

  static const double maxWidth = AppLayout.pageWidth;

  static const ValueKey<String> siteKey = ValueKey<String>('kpi-targets-site');
  static const ValueKey<String> backKey = ValueKey<String>('kpi-targets-back');
  static const ValueKey<String> changeTargetKey = ValueKey<String>('kpi-targets-change');
  static const ValueKey<String> headerKey = ValueKey<String>('kpi-targets-header');
  static const ValueKey<String> currentKey = ValueKey<String>('kpi-targets-current');
  static const ValueKey<String> historyKey = ValueKey<String>('kpi-targets-history');
  static const ValueKey<String> failedKey = ValueKey<String>('kpi-targets-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('kpi-targets-retry');
  static const ValueKey<String> emptyKey = ValueKey<String>('kpi-targets-empty');
  static ValueKey<String> currentRowKey(String grain) => ValueKey<String>('kpi-targets-current-$grain');
  static ValueKey<String> historyRowKey(int targetId) => ValueKey<String>('kpi-targets-history-$targetId');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<KpiTargetsBloc>().state;
    return Scaffold(
      body: switch (state) {
        KpiTargetsLoading() => const SkeletonList(maxWidth: KpiTargetsScreen.maxWidth),
        KpiTargetsUnavailable(message: final message) => PlatformFailureState(
            key: KpiTargetsScreen.failedKey,
            title: 'The Targets could not be read',
            message: message,
            retryKey: KpiTargetsScreen.retryKey,
            onRetry: () => context.read<KpiTargetsBloc>().add(KpiTargetsStarted(kpiId: kpiId)),
          ),
        KpiTargetsLoaded() => _Loaded(state: state, canWrite: canWrite),
      },
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({required this.state, required this.canWrite});

  final KpiTargetsLoaded state;
  final bool canWrite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kpi = state.targets.kpi;
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Center(
      child: AppPageFrame(
        maxWidth: KpiTargetsScreen.maxWidth,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xl),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: KpiTargetsScreen.backKey,
                onPressed: () => context.go(Routes.kpi),
                icon: const Icon(Icons.arrow_back),
                label: const Text('KPI catalogue'),
              ),
            ),
            Text('${kpi.kpi} · ${kpi.title}', key: KpiTargetsScreen.headerKey, style: theme.textTheme.headlineSmall),
            const SizedBox(height: Spacing.xs),
            Text('KPI Targets, ${kpi.direction} ${kpi.unit}'.trim(), style: muted),
            const SizedBox(height: Spacing.md),
            Wrap(
              spacing: Spacing.md,
              runSpacing: Spacing.md,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (state.sites.length > 1)
                  SizedBox(
                    width: 280,
                    child: DropdownButtonFormField<String>(
                      key: KpiTargetsScreen.siteKey,
                      initialValue: state.siteId,
                      isDense: true,
                      decoration: const InputDecoration(labelText: 'Site', border: OutlineInputBorder()),
                      items: [
                        for (final site in state.sites)
                          DropdownMenuItem<String>(value: site.id, child: Text(site.name)),
                      ],
                      onChanged: (siteId) {
                        if (siteId == null) return;
                        context.read<KpiTargetsBloc>().add(KpiTargetsSiteSelected(siteId));
                      },
                    ),
                  ),
                if (canWrite)
                  FilledButton.icon(
                    key: KpiTargetsScreen.changeTargetKey,
                    onPressed: () => ChangeTargetDialog.open(context, siteToday: state.siteToday),
                    icon: const Icon(Icons.edit_calendar_outlined),
                    label: const Text('Change Target'),
                  ),
              ],
            ),
            const SizedBox(height: Spacing.lg),
            Text('Currently in force', style: theme.textTheme.titleMedium),
            const SizedBox(height: Spacing.sm),
            if (state.targets.current.isEmpty)
              Text('No Target is in force today.', key: KpiTargetsScreen.currentKey, style: muted)
            else
              Column(
                key: KpiTargetsScreen.currentKey,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final entry in state.targets.current)
                    Padding(
                      key: KpiTargetsScreen.currentRowKey(entry.grain),
                      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
                      child: Text(
                        '${entry.grain}: ${formatTarget(kpi, entry.target)} (from ${entry.validFrom})',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                ],
              ),
            const SizedBox(height: Spacing.lg),
            Text('History', style: theme.textTheme.titleMedium),
            const SizedBox(height: Spacing.sm),
            if (state.targets.history.isEmpty)
              const PlatformEmptyState.noneExist(
                key: KpiTargetsScreen.emptyKey,
                title: 'No Target has been set',
                message: 'Every entry made for this KPI will be listed here.',
                icon: Icons.flag_outlined,
              )
            else
              AppListCard(
                key: KpiTargetsScreen.historyKey,
                rows: [
                  const _HistoryHeader(),
                  for (final entry in state.targets.history) _HistoryRow(entry: entry, kpi: kpi),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

const int _fromFlex = 2;
const int _grainFlex = 2;
const int _targetFlex = 2;
const int _noteFlex = 3;
const int _byFlex = 2;
const int _atFlex = 2;

class _HistoryHeader extends StatelessWidget {
  const _HistoryHeader();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600);
    Widget cell(int flex, String label) => Expanded(flex: flex, child: Text(label, style: style));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          cell(_fromFlex, 'Valid from'),
          cell(_grainFlex, 'Grain'),
          cell(_targetFlex, 'Target'),
          cell(_noteFlex, 'Note'),
          cell(_byFlex, 'Entered by'),
          cell(_atFlex, 'Entered at'),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry, required this.kpi});

  final KpiHistoryEntry entry;
  final KpiSummary kpi;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = theme.textTheme.bodyMedium;
    final target = entry.target == null ? 'No target' : formatTarget(kpi, entry.target!);
    final note = entry.note;
    return Padding(
      key: KpiTargetsScreen.historyRowKey(entry.targetId),
      padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: _fromFlex, child: Text(entry.validFrom, style: body)),
          Expanded(flex: _grainFlex, child: Text(entry.grain, style: body)),
          Expanded(
            flex: _targetFlex,
            child: Text(target, style: body),
          ),
          Expanded(flex: _noteFlex, child: Text(note == null || note.isEmpty ? '—' : note, style: body)),
          Expanded(flex: _byFlex, child: Text(entry.appUser ?? entry.enteredBy ?? '—', style: body)),
          Expanded(
            flex: _atFlex,
            child: Text(entry.enteredAt == null ? '—' : formatEnteredAt(entry.enteredAt!), style: body),
          ),
        ],
      ),
    );
  }
}
