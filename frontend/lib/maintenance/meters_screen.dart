/// The meters list: the instruments an Asset's accumulated use is read from
/// (issue #79).
///
/// Readable by anyone whose role earns the Maintenance Module — the same rule
/// the Work orders, Requests, Downtime and PM schedule Screens document. The
/// define button and the record-reading action are offered only to a caller
/// who holds a write Grant somewhere: an action the server would refuse is not
/// offered in the first place (the coarse `orgUnitScope.canWriteSomewhere`
/// signal those Screens already use).
///
/// CONTEXT.md's PM schedule entry is the point of the copy: a meter is how a
/// schedule comes due on accumulated use rather than elapsed time, and only a
/// cumulative meter can drive one.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import 'meter.dart';
import 'meter_form_dialog.dart';
import 'meters_bloc.dart';
import 'reading_form_dialog.dart';

class MetersScreen extends StatelessWidget {
  const MetersScreen({super.key, required this.canAct});

  /// Whether this caller holds a write Grant anywhere at all — read off
  /// `/me`'s own `orgUnitScope` (issue #43), the same rule the PM schedule
  /// Screen applies to its own actions.
  final bool canAct;

  static const double maxWidth = 960;

  static const ValueKey<String> createKey = ValueKey<String>('meters-create');
  static const ValueKey<String> siteKey = ValueKey<String>('meters-site');
  static const ValueKey<String> noticeKey = ValueKey<String>('meters-notice');
  static const ValueKey<String> retryKey = ValueKey<String>('meters-retry');
  static const ValueKey<String> emptyKey = ValueKey<String>('meters-empty');
  static const ValueKey<String> failedKey = ValueKey<String>('meters-failed');

  static ValueKey<String> rowKey(String id) => ValueKey<String>('meter-row-$id');
  static ValueKey<String> readingKey(String id) => ValueKey<String>('meter-reading-$id');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<MetersBloc>().state;

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(state: state, canAct: canAct),
          if (state is MetersLoaded && state.notice != null) _Notice(message: state.notice!),
          Expanded(
            child: switch (state) {
              MetersLoading() => const SkeletonList(rows: 4, maxWidth: maxWidth),
              MetersUnavailable(message: final message) => PlatformFailureState(
                  key: MetersScreen.failedKey,
                  title: 'The meters could not be read',
                  message: message,
                  retryKey: MetersScreen.retryKey,
                  onRetry: () => context.read<MetersBloc>().add(const MetersStarted()),
                ),
              MetersLoaded(isLoadingMeters: true) => const SkeletonList(rows: 4, maxWidth: maxWidth),
              MetersLoaded(meters: final meters) when meters.isEmpty => const _MetersEmpty(),
              MetersLoaded(meters: final meters) => _MetersList(meters: meters, canAct: canAct),
            },
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state, required this.canAct});

  final MetersState state;
  final bool canAct;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loaded = state is MetersLoaded ? state as MetersLoaded : null;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: MetersScreen.maxWidth),
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
                        Text('Meters', style: theme.textTheme.headlineSmall),
                        const SizedBox(height: Spacing.xs),
                        Text(
                          'The running counts a PM schedule can come due on, and the readings taken '
                          'against them.',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  if (canAct && loaded != null)
                    FilledButton.icon(
                      key: MetersScreen.createKey,
                      onPressed: loaded.isMutating || loaded.siteId == null
                          ? null
                          : () => MeterFormDialog.open(context, siteId: loaded.siteId!),
                      icon: const Icon(Icons.speed_outlined),
                      label: const Text('Define a meter'),
                      style: FilledButton.styleFrom(minimumSize: const Size(44, 44)),
                    ),
                ],
              ),
              if (loaded != null && loaded.sites.length > 1) ...[
                const SizedBox(height: Spacing.md),
                SizedBox(
                  width: 280,
                  child: DropdownButtonFormField<String>(
                    key: MetersScreen.siteKey,
                    initialValue: loaded.siteId,
                    isDense: true,
                    decoration: const InputDecoration(labelText: 'Site', border: OutlineInputBorder()),
                    items: [
                      for (final site in loaded.sites)
                        DropdownMenuItem<String>(value: site.id, child: Text(site.name)),
                    ],
                    onChanged: (siteId) {
                      if (siteId == null) return;
                      context.read<MetersBloc>().add(MetersSiteSelected(siteId));
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
        constraints: const BoxConstraints(maxWidth: MetersScreen.maxWidth),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.md),
          child: Container(
            key: MetersScreen.noticeKey,
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

class _MetersList extends StatelessWidget {
  const _MetersList({required this.meters, required this.canAct});

  final List<AssetMeter> meters;
  final bool canAct;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: MetersScreen.maxWidth),
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
          itemCount: meters.length,
          separatorBuilder: (_, _) => const SizedBox(height: Spacing.sm),
          itemBuilder: (context, index) => _MeterCard(meter: meters[index], canAct: canAct),
        ),
      ),
    );
  }
}

class _MeterCard extends StatelessWidget {
  const _MeterCard({required this.meter, required this.canAct});

  final AssetMeter meter;
  final bool canAct;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final state = context.watch<MetersBloc>().state;
    final busy = state is MetersLoaded && state.isMutating;

    return Card(
      key: MetersScreen.rowKey(meter.id),
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
                      Text('${meter.name} (${meter.code})', style: theme.textTheme.titleSmall),
                      const SizedBox(height: Spacing.xxs),
                      Text(
                        '${meter.assetName} (${meter.assetCode}) · ${meter.orgUnitName}',
                        style: muted,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Spacing.md),
                Chip(label: Text(meter.meterTypeLabel), visualDensity: VisualDensity.compact),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            Wrap(
              spacing: Spacing.md,
              runSpacing: Spacing.xxs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Latest: ${meter.latestReadingLabel}', style: muted),
                Text('Accumulated use: ${meter.accumulatedLabel}', style: muted),
                if (meter.rolloverOffset > 0)
                  Text('Carried forward: ${meter.rolloverOffset} ${meter.uomCode}', style: muted),
              ],
            ),
            if (canAct) ...[
              const SizedBox(height: Spacing.md),
              OutlinedButton(
                key: MetersScreen.readingKey(meter.id),
                onPressed: busy ? null : () => ReadingFormDialog.open(context, meter: meter),
                style: OutlinedButton.styleFrom(minimumSize: const Size(44, 44)),
                child: const Text('Record a reading'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetersEmpty extends StatelessWidget {
  const _MetersEmpty();

  @override
  Widget build(BuildContext context) {
    return const PlatformEmptyState.noneExist(
      key: MetersScreen.emptyKey,
      title: 'No meters yet',
      message: 'No meter is defined on this Site\'s Assets yet.',
    );
  }
}
