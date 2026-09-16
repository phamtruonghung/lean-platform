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
import '../widgets/app_filter_field.dart';
import '../widgets/app_page_frame.dart';
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

  /// The filter box's `name` (issue #191), seeding [filterFieldKey],
  /// [filterClearKey] and [filterCountKey] — kept in one place so the field's
  /// own name and the keys a test reaches it by cannot drift, the same device
  /// `WorkOrderAssignDialog.searchFieldName` uses (issue #187).
  static const String filterFieldName = 'meters-filter';

  static ValueKey<String> get filterFieldKey => AppFilterField.fieldKey(filterFieldName);
  static ValueKey<String> get filterClearKey => AppFilterField.clearKey(filterFieldName);
  static ValueKey<String> get filterCountKey => AppFilterField.countKey(filterFieldName);

  /// What a term matching none of this Site's meters renders — a different fact
  /// from [emptyKey]: "nothing matched" is not "there is nothing here".
  static const ValueKey<String> noMatchKey = ValueKey<String>('meters-no-match');

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
      child: AppPageFrame(
        maxWidth: MetersScreen.maxWidth,
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
      child: AppPageFrame(
        maxWidth: MetersScreen.maxWidth,
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

/// The list of meters. Stateful only because the filter box's term is the
/// Screen's own (issue #191): a filter is a view of the rows the Bloc already
/// holds, not a state of the domain, so typing costs a `setState` and never a
/// Bloc event.
class _MetersList extends StatefulWidget {
  const _MetersList({required this.meters, required this.canAct});

  final List<AssetMeter> meters;
  final bool canAct;

  @override
  State<_MetersList> createState() => _MetersListState();
}

class _MetersListState extends State<_MetersList> {
  /// What the filter box is narrowing the Site's meters to, `''` when nothing
  /// is.
  String _term = '';

  /// Whether [meter] matches [term], already lower-cased and trimmed: a
  /// case-insensitive substring over the meter's own name and code and the
  /// Asset it reads — the four ways a planner names the instrument they mean.
  /// No ranking and no fuzzy matching, the same rule the assign dialog's own
  /// filter uses (issue #187).
  static bool _matches(AssetMeter meter, String term) =>
      meter.name.toLowerCase().contains(term) ||
      meter.code.toLowerCase().contains(term) ||
      meter.assetName.toLowerCase().contains(term) ||
      meter.assetCode.toLowerCase().contains(term);

  /// The rows actually rendered — every one of them while the term is empty.
  List<AssetMeter> get _matchingMeters {
    final term = _term.trim().toLowerCase();
    if (term.isEmpty) return widget.meters;
    return widget.meters.where((meter) => _matches(meter, term)).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    // Filtered here, immediately before the row widgets are built, so a term
    // can only ever narrow rows this Screen already read (issue #191).
    final matches = _matchingMeters;
    return Center(
      child: AppPageFrame(
        maxWidth: MetersScreen.maxWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
              child: AppFilterField(
                name: MetersScreen.filterFieldName,
                label: 'Filter meters',
                helperText: 'By meter name, code or Asset.',
                term: _term,
                onChanged: (term) => setState(() => _term = term),
                shown: matches.length,
                total: widget.meters.length,
              ),
            ),
            const SizedBox(height: Spacing.md),
            Expanded(
              child: matches.isEmpty
                  ? PlatformEmptyState.noneMatched(
                      key: MetersScreen.noMatchKey,
                      title: 'No meters match',
                      message: 'This Site has meters, but none matches "${_term.trim()}". '
                          'Try a different name, code or Asset.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
                      itemCount: matches.length,
                      separatorBuilder: (_, _) => const SizedBox(height: Spacing.sm),
                      itemBuilder: (context, index) =>
                          _MeterCard(meter: matches[index], canAct: widget.canAct),
                    ),
            ),
          ],
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
