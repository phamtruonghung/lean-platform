/// The Safety observation register (issue #230, CONTEXT.md's **Safety
/// observation**): what was seen before anything went wrong at this Site,
/// where it happened, and how bad it could have been.
///
/// Read Site-wide by anyone who can see the Site, whatever their Grants — the
/// same rule the Safety incident register follows (#55, ADR-0009, ADR-0032).
/// Recording is offered to everyone too: the server is the real gate on where
/// one may be recorded (a write Grant reaching that Org Unit, or the
/// administrator role).
///
/// **Worst-first by severity potential** (the binding design comment on
/// #223) — the entire reason the field exists, so it is the register's
/// default order, never date. Severity potential paints as `fatal` ->
/// danger, `high` -> warning, `medium` -> info, `low` -> neutral, and
/// **stop-work is its own labelled badge, not a tone** — it is a fact about
/// what somebody did, not a state the observation is in.
///
/// **The empty register is bad news, unlike the incident register's.** A
/// leading indicator with nothing on it means nobody is walking, so the copy
/// says so rather than reading as good news the way an empty incident
/// register does.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../platform/router.dart';
import '../theme.dart';
import '../widgets/app_date_field.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/status_chip.dart';
import 'safety_observation.dart';
import 'safety_observation_org_unit_filter_dialog.dart';
import 'safety_observations_bloc.dart';

class SafetyObservationsScreen extends StatelessWidget {
  const SafetyObservationsScreen({super.key});

  static const double maxWidth = 1100;

  static const ValueKey<String> recordKey = ValueKey<String>('safety-observations-record');
  static const ValueKey<String> siteKey = ValueKey<String>('safety-observations-site');
  static const ValueKey<String> orgUnitFilterKey =
      ValueKey<String>('safety-observations-filter-org-unit');
  static const ValueKey<String> typeFilterKey =
      ValueKey<String>('safety-observations-filter-type');
  static const ValueKey<String> categoryFilterKey =
      ValueKey<String>('safety-observations-filter-category');
  static const ValueKey<String> severityPotentialFilterKey =
      ValueKey<String>('safety-observations-filter-severity-potential');
  static const ValueKey<String> stopWorkFilterKey =
      ValueKey<String>('safety-observations-filter-stop-work');
  static const ValueKey<String> fromDateKey = ValueKey<String>('safety-observations-filter-from');
  static const ValueKey<String> toDateKey = ValueKey<String>('safety-observations-filter-to');
  static const ValueKey<String> clearFiltersKey =
      ValueKey<String>('safety-observations-clear-filters');
  static const ValueKey<String> truncatedKey = ValueKey<String>('safety-observations-truncated');
  static const ValueKey<String> emptyKey = ValueKey<String>('safety-observations-empty');
  static const ValueKey<String> emptyMatchedKey =
      ValueKey<String>('safety-observations-empty-matched');
  static const ValueKey<String> emptyClearFiltersKey =
      ValueKey<String>('safety-observations-empty-clear');
  static const ValueKey<String> failedKey = ValueKey<String>('safety-observations-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('safety-observations-retry');
  static const ValueKey<String> noSiteKey = ValueKey<String>('safety-observations-no-site');
  static const ValueKey<String> formLoadingKey =
      ValueKey<String>('safety-observations-form-loading');

  static ValueKey<String> rowKey(String id) => ValueKey<String>('safety-observation-row-$id');
  static ValueKey<String> rowPotentialKey(String id) =>
      ValueKey<String>('safety-observation-potential-$id');
  static ValueKey<String> rowStopWorkKey(String id) =>
      ValueKey<String>('safety-observation-stop-work-$id');
  static ValueKey<String> rowFiledKey(String id) =>
      ValueKey<String>('safety-observation-filed-$id');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SafetyObservationsBloc>().state;

    return _RefreshOnMount(
      child: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(state: state),
            Expanded(
              child: switch (state) {
                SafetyObservationsLoading() => const SkeletonList(rows: 4, maxWidth: maxWidth),
                SafetyObservationsUnavailable(message: final message) => PlatformFailureState(
                    key: failedKey,
                    title: 'The Safety observation register could not be read',
                    message: message,
                    retryKey: retryKey,
                    onRetry: () =>
                        context.read<SafetyObservationsBloc>().add(const SafetyObservationsStarted()),
                  ),
                SafetyObservationsLoaded(siteId: null) => const PlatformEmptyState.noneExist(
                    key: noSiteKey,
                    title: 'No Site to show',
                    message: 'Your Account can see no Site yet, so there is nothing to read here.',
                    icon: Icons.factory_outlined,
                  ),
                SafetyObservationsLoaded(observations: final rows, filters: final filters)
                    when rows.isEmpty =>
                  _Empty(isFiltered: filters.isSet),
                SafetyObservationsLoaded(observations: final rows) => _Register(rows: rows),
              },
            ),
            if (state is SafetyObservationsLoaded && state.truncated) const _Truncated(),
          ],
        ),
      ),
    );
  }
}

/// Asks the register to re-read whenever the Screen is entered — the same
/// reasoning `SafetyIncidentsScreen`'s own `_RefreshOnMount` carries.
class _RefreshOnMount extends StatefulWidget {
  const _RefreshOnMount({required this.child});

  final Widget child;

  @override
  State<_RefreshOnMount> createState() => _RefreshOnMountState();
}

class _RefreshOnMountState extends State<_RefreshOnMount> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<SafetyObservationsBloc>().add(const SafetyObservationsRefreshed());
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _Header extends StatelessWidget {
  const _Header({required this.state});

  final SafetyObservationsState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loaded = state is SafetyObservationsLoaded ? state as SafetyObservationsLoaded : null;

    return Center(
      child: AppPageFrame(
        maxWidth: SafetyObservationsScreen.maxWidth,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: Spacing.md,
                runSpacing: Spacing.sm,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Safety observations', style: theme.textTheme.headlineSmall),
                      const SizedBox(height: Spacing.xs),
                      Text(
                        'What was seen before anything went wrong, ranked worst-first by the '
                        'worst credible outcome.',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                  if (loaded != null)
                    FilledButton.icon(
                      key: SafetyObservationsScreen.recordKey,
                      onPressed: loaded.isRecording || loaded.siteId == null
                          ? null
                          : () => context.go('${Routes.safetyObservations}/record'),
                      icon: const Icon(Icons.add),
                      label: const Text('Record an observation'),
                    ),
                ],
              ),
              if (loaded != null) ...[
                const SizedBox(height: Spacing.md),
                _Filters(loaded: loaded),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The Site chooser and the five ways to narrow the register. Each is a read
/// filter over an already-visible list, so each sends a request rather than
/// hiding rows the client happens to hold.
class _Filters extends StatelessWidget {
  const _Filters({required this.loaded});

  final SafetyObservationsLoaded loaded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filters = loaded.filters;

    return Wrap(
      spacing: Spacing.md,
      runSpacing: Spacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (loaded.sites.length > 1)
          SizedBox(
            width: 200,
            child: DropdownButtonFormField<String>(
              key: SafetyObservationsScreen.siteKey,
              initialValue: loaded.siteId,
              isDense: true,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Site', border: OutlineInputBorder()),
              items: [
                for (final site in loaded.sites)
                  DropdownMenuItem<String>(value: site.id, child: Text(site.name)),
              ],
              onChanged: (siteId) {
                if (siteId == null) return;
                context.read<SafetyObservationsBloc>().add(SafetyObservationsSiteSelected(siteId));
              },
            ),
          ),
        OutlinedButton.icon(
          key: SafetyObservationsScreen.orgUnitFilterKey,
          onPressed: () =>
              SafetyObservationOrgUnitFilterDialog.open(context, siteId: loaded.siteId),
          icon: const Icon(Icons.account_tree_outlined),
          label: Text(filters.orgUnitName ?? 'All Org Units'),
        ),
        SizedBox(
          width: 190,
          child: DropdownButtonFormField<String?>(
            key: SafetyObservationsScreen.typeFilterKey,
            initialValue: filters.observationType,
            isDense: true,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Any type')),
              for (final type in ObservationType.values)
                DropdownMenuItem<String?>(value: type, child: Text(ObservationType.label(type))),
            ],
            onChanged: (type) => context
                .read<SafetyObservationsBloc>()
                .add(SafetyObservationsTypeFilterChanged(type)),
          ),
        ),
        SizedBox(
          width: 190,
          child: DropdownButtonFormField<String?>(
            key: SafetyObservationsScreen.categoryFilterKey,
            initialValue: filters.category,
            isDense: true,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Any category')),
              for (final category in ObservationCategory.values)
                DropdownMenuItem<String?>(
                  value: category,
                  child: Text(ObservationCategory.label(category)),
                ),
            ],
            onChanged: (category) => context
                .read<SafetyObservationsBloc>()
                .add(SafetyObservationsCategoryFilterChanged(category)),
          ),
        ),
        SizedBox(
          width: 190,
          child: DropdownButtonFormField<String?>(
            key: SafetyObservationsScreen.severityPotentialFilterKey,
            initialValue: filters.severityPotential,
            isDense: true,
            isExpanded: true,
            decoration:
                const InputDecoration(labelText: 'Severity potential', border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Any potential')),
              // Worst-first order is the register's own order; the filter's
              // own dropdown renders `SeverityPotential.values`' ascending
              // order for the same reason the record form does — the picker
              // is a scan of "how bad could this be", not a scan of the list
              // it narrows.
              for (final potential in SeverityPotential.values)
                DropdownMenuItem<String?>(
                  value: potential,
                  child: Text(SeverityPotential.label(potential)),
                ),
            ],
            onChanged: (potential) => context
                .read<SafetyObservationsBloc>()
                .add(SafetyObservationsSeverityPotentialFilterChanged(potential)),
          ),
        ),
        SizedBox(
          width: 170,
          child: DropdownButtonFormField<bool?>(
            key: SafetyObservationsScreen.stopWorkFilterKey,
            initialValue: filters.isStopWork,
            isDense: true,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Stop-work', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem<bool?>(value: null, child: Text('Any')),
              DropdownMenuItem<bool?>(value: true, child: Text('Stop-work only')),
              DropdownMenuItem<bool?>(value: false, child: Text('Not stop-work')),
            ],
            onChanged: (value) => context
                .read<SafetyObservationsBloc>()
                .add(SafetyObservationsStopWorkFilterChanged(value)),
          ),
        ),
        SizedBox(
          width: 165,
          child: AppDateField(
            key: SafetyObservationsScreen.fromDateKey,
            name: 'safety-observations-from',
            label: 'Observed from',
            value: filters.from,
            optional: true,
            onChanged: (value) => context
                .read<SafetyObservationsBloc>()
                .add(SafetyObservationsDateRangeChanged(from: value, clearFrom: value == null)),
          ),
        ),
        SizedBox(
          width: 165,
          child: AppDateField(
            key: SafetyObservationsScreen.toDateKey,
            name: 'safety-observations-to',
            label: 'Observed to',
            value: filters.to,
            optional: true,
            onChanged: (value) => context
                .read<SafetyObservationsBloc>()
                .add(SafetyObservationsDateRangeChanged(to: value, clearTo: value == null)),
          ),
        ),
        if (filters.isSet)
          TextButton(
            key: SafetyObservationsScreen.clearFiltersKey,
            onPressed: () => context
                .read<SafetyObservationsBloc>()
                .add(const SafetyObservationsFiltersCleared()),
            child: Text('Clear filters', style: theme.textTheme.bodyMedium),
          ),
      ],
    );
  }
}

/// The register was capped — said out loud rather than left to be inferred
/// (ADR-0026), the same rule `SafetyIncidentsScreen`'s own `_Truncated`
/// follows.
class _Truncated extends StatelessWidget {
  const _Truncated();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: AppPageFrame(
        maxWidth: SafetyObservationsScreen.maxWidth,
        child: Padding(
          key: SafetyObservationsScreen.truncatedKey,
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.sm),
          child: Text(
            'There are more Safety observations than this list shows. Narrow it by Org Unit, '
            'by type or by date to see the rest.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

/// Two empty stories, told apart — the opposite of the incident register's
/// own pair (the binding design comment on #223): an observation register
/// with no rows is bad news, because the leading indicator being empty means
/// nobody is walking.
class _Empty extends StatelessWidget {
  const _Empty({required this.isFiltered});

  final bool isFiltered;

  @override
  Widget build(BuildContext context) {
    if (isFiltered) {
      return PlatformEmptyState.noneMatched(
        key: SafetyObservationsScreen.emptyMatchedKey,
        title: 'Nothing matches these filters',
        message: 'The register has Safety observations, but none of them is in the area, type, '
            'category, potential, stop-work or dates you picked.',
        actionLabel: 'Clear the filters',
        actionKey: SafetyObservationsScreen.emptyClearFiltersKey,
        onAction: () =>
            context.read<SafetyObservationsBloc>().add(const SafetyObservationsFiltersCleared()),
      );
    }
    return const PlatformEmptyState.noneExist(
      key: SafetyObservationsScreen.emptyKey,
      title: 'No observations recorded. The leading indicator is empty.',
      message: 'No Safety observation has been recorded at this Site for the area and dates '
          'shown.',
      icon: Icons.visibility_outlined,
    );
  }
}

class _Register extends StatelessWidget {
  const _Register({required this.rows});

  final List<SafetyObservation> rows;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AppPageFrame(
        maxWidth: SafetyObservationsScreen.maxWidth,
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
          itemCount: rows.length,
          itemBuilder: (context, index) => _SafetyObservationRow(observation: rows[index]),
        ),
      ),
    );
  }
}

class _SafetyObservationRow extends StatelessWidget {
  const _SafetyObservationRow({required this.observation});

  final SafetyObservation observation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final row = observation;

    return Card(
      key: SafetyObservationsScreen.rowKey(row.id),
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      child: InkWell(
        onTap: () => context.go('${Routes.safetyObservations}/${row.id}'),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: Spacing.xs,
                      runSpacing: Spacing.xxs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        StatusChip(
                          key: SafetyObservationsScreen.rowPotentialKey(row.id),
                          label: row.severityPotentialLabel,
                          tone: row.severityPotentialTone,
                        ),
                        // Stop-work is a labelled badge, never a tone (the
                        // binding design comment on #223) — it is a fact
                        // about what somebody did, not a state the
                        // observation is in.
                        if (row.isStopWork)
                          Chip(
                            key: SafetyObservationsScreen.rowStopWorkKey(row.id),
                            label: const Text('Stop-work'),
                            visualDensity: VisualDensity.compact,
                          ),
                        Text(row.observationTypeLabel, style: theme.textTheme.labelMedium),
                      ],
                    ),
                    const SizedBox(height: Spacing.xs),
                    Text(row.categoryLabel, style: theme.textTheme.titleMedium),
                    const SizedBox(height: Spacing.xxs),
                    Text(
                      '${row.orgUnitName} · filed against ${row.filedAgainst}',
                      key: SafetyObservationsScreen.rowFiledKey(row.id),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
