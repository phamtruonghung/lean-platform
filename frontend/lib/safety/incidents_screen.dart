/// The Safety incident register (issue #226, CONTEXT.md's **Safety
/// incident**): what went wrong at this Site, where it happened, and where it
/// sits on the severity ladder.
///
/// Read Site-wide by anyone who can see the Site, whatever their Grants —
/// the same rule the Non-conformance register, the Work order list, the
/// Asset register and the action log already follow (#55, ADR-0009,
/// ADR-0032). Recording is offered to everyone too: the server is the real
/// gate on where one may be recorded (a write Grant reaching that Org Unit,
/// or the administrator role).
///
/// **Two chips a row, separated by role rather than stacked** (the binding
/// design comment on #223): severity on the left, with the number, Org Unit
/// and date — what happened — and status on the right — what is being done
/// about it.
///
/// **The empty register is good news, and must not be celebrated.** A plant
/// with no recorded incidents may simply not be reporting, which is the exact
/// failure ADR-0036 trades against — so the copy is flat, never "All clear".
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
import 'safety_incident.dart';
import 'safety_incidents_bloc.dart';
import 'safety_org_unit_filter_dialog.dart';

class SafetyIncidentsScreen extends StatelessWidget {
  const SafetyIncidentsScreen({super.key});

  static const double maxWidth = 1100;

  static const ValueKey<String> recordKey = ValueKey<String>('safety-incidents-record');
  static const ValueKey<String> siteKey = ValueKey<String>('safety-incidents-site');
  static const ValueKey<String> orgUnitFilterKey =
      ValueKey<String>('safety-incidents-filter-org-unit');
  static const ValueKey<String> statusFilterKey =
      ValueKey<String>('safety-incidents-filter-status');
  static const ValueKey<String> typeFilterKey = ValueKey<String>('safety-incidents-filter-type');
  static const ValueKey<String> severityFilterKey =
      ValueKey<String>('safety-incidents-filter-severity');
  static const ValueKey<String> recordableFilterKey =
      ValueKey<String>('safety-incidents-filter-recordable');
  static const ValueKey<String> fromDateKey = ValueKey<String>('safety-incidents-filter-from');
  static const ValueKey<String> toDateKey = ValueKey<String>('safety-incidents-filter-to');
  static const ValueKey<String> clearFiltersKey = ValueKey<String>('safety-incidents-clear-filters');
  static const ValueKey<String> truncatedKey = ValueKey<String>('safety-incidents-truncated');
  static const ValueKey<String> emptyKey = ValueKey<String>('safety-incidents-empty');
  static const ValueKey<String> emptyMatchedKey = ValueKey<String>('safety-incidents-empty-matched');
  static const ValueKey<String> emptyClearFiltersKey =
      ValueKey<String>('safety-incidents-empty-clear');
  static const ValueKey<String> failedKey = ValueKey<String>('safety-incidents-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('safety-incidents-retry');
  static const ValueKey<String> noSiteKey = ValueKey<String>('safety-incidents-no-site');
  static const ValueKey<String> formLoadingKey = ValueKey<String>('safety-incidents-form-loading');

  static ValueKey<String> rowKey(String id) => ValueKey<String>('safety-incident-row-$id');
  static ValueKey<String> rowStatusKey(String id) =>
      ValueKey<String>('safety-incident-status-$id');
  static ValueKey<String> rowSeverityKey(String id) =>
      ValueKey<String>('safety-incident-severity-$id');
  static ValueKey<String> rowFiledKey(String id) => ValueKey<String>('safety-incident-filed-$id');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SafetyIncidentsBloc>().state;

    return _RefreshOnMount(
      child: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(state: state),
            Expanded(
              child: switch (state) {
                SafetyIncidentsLoading() => const SkeletonList(rows: 4, maxWidth: maxWidth),
                SafetyIncidentsUnavailable(message: final message) => PlatformFailureState(
                    key: failedKey,
                    title: 'The Safety incident register could not be read',
                    message: message,
                    retryKey: retryKey,
                    onRetry: () =>
                        context.read<SafetyIncidentsBloc>().add(const SafetyIncidentsStarted()),
                  ),
                SafetyIncidentsLoaded(siteId: null) => const PlatformEmptyState.noneExist(
                    key: noSiteKey,
                    title: 'No Site to show',
                    message: 'Your Account can see no Site yet, so there is nothing to read here.',
                    icon: Icons.factory_outlined,
                  ),
                SafetyIncidentsLoaded(incidents: final rows, filters: final filters)
                    when rows.isEmpty =>
                  _Empty(isFiltered: filters.isSet),
                SafetyIncidentsLoaded(incidents: final rows) => _Register(rows: rows),
              },
            ),
            if (state is SafetyIncidentsLoaded && state.truncated) const _Truncated(),
          ],
        ),
      ),
    );
  }
}

/// Asks the register to re-read whenever the Screen is entered — the same
/// reasoning `NonconformancesScreen`'s own `_RefreshOnMount` carries (issue
/// #183).
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
      context.read<SafetyIncidentsBloc>().add(const SafetyIncidentsRefreshed());
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _Header extends StatelessWidget {
  const _Header({required this.state});

  final SafetyIncidentsState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loaded = state is SafetyIncidentsLoaded ? state as SafetyIncidentsLoaded : null;

    return Center(
      child: AppPageFrame(
        maxWidth: SafetyIncidentsScreen.maxWidth,
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
                      Text('Safety incidents', style: theme.textTheme.headlineSmall),
                      const SizedBox(height: Spacing.xs),
                      Text(
                        'What went wrong at this Site, where it happened, and where it sits on '
                        'the severity ladder.',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                  if (loaded != null)
                    FilledButton.icon(
                      key: SafetyIncidentsScreen.recordKey,
                      onPressed: loaded.isRecording || loaded.siteId == null
                          ? null
                          : () => context.go('${Routes.safetyIncidents}/record'),
                      icon: const Icon(Icons.add),
                      label: const Text('Record a Safety incident'),
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

/// The Site chooser and the six ways to narrow the register. Each is a read
/// filter over an already-visible list, so each sends a request rather than
/// hiding rows the client happens to hold.
class _Filters extends StatelessWidget {
  const _Filters({required this.loaded});

  final SafetyIncidentsLoaded loaded;

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
              key: SafetyIncidentsScreen.siteKey,
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
                context.read<SafetyIncidentsBloc>().add(SafetyIncidentsSiteSelected(siteId));
              },
            ),
          ),
        OutlinedButton.icon(
          key: SafetyIncidentsScreen.orgUnitFilterKey,
          onPressed: () => SafetyOrgUnitFilterDialog.open(context, siteId: loaded.siteId),
          icon: const Icon(Icons.account_tree_outlined),
          label: Text(filters.orgUnitName ?? 'All Org Units'),
        ),
        SizedBox(
          width: 170,
          child: DropdownButtonFormField<String?>(
            key: SafetyIncidentsScreen.statusFilterKey,
            initialValue: filters.status,
            isDense: true,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Any status')),
              for (final status in SafetyIncidentStatus.values)
                DropdownMenuItem<String?>(
                  value: status,
                  child: Text(SafetyIncidentStatus.label(status)),
                ),
            ],
            onChanged: (status) => context
                .read<SafetyIncidentsBloc>()
                .add(SafetyIncidentsStatusFilterChanged(status)),
          ),
        ),
        SizedBox(
          width: 190,
          child: DropdownButtonFormField<String?>(
            key: SafetyIncidentsScreen.typeFilterKey,
            initialValue: filters.incidentType,
            isDense: true,
            isExpanded: true,
            decoration:
                const InputDecoration(labelText: 'Incident type', border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Any type')),
              for (final type in IncidentType.values)
                DropdownMenuItem<String?>(value: type, child: Text(IncidentType.label(type))),
            ],
            onChanged: (type) =>
                context.read<SafetyIncidentsBloc>().add(SafetyIncidentsTypeFilterChanged(type)),
          ),
        ),
        SizedBox(
          width: 190,
          child: DropdownButtonFormField<String?>(
            key: SafetyIncidentsScreen.severityFilterKey,
            initialValue: filters.severityLevel,
            isDense: true,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Severity', border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Any severity')),
              // Ladder order, never alphabetical (the binding design comment
              // on #223) — the same order the record form's own dropdown
              // renders.
              for (final level in SeverityLevel.values)
                DropdownMenuItem<String?>(
                  value: level,
                  child: Text(SeverityLevel.label(level)),
                ),
            ],
            onChanged: (level) => context
                .read<SafetyIncidentsBloc>()
                .add(SafetyIncidentsSeverityFilterChanged(level)),
          ),
        ),
        SizedBox(
          width: 170,
          child: DropdownButtonFormField<bool?>(
            key: SafetyIncidentsScreen.recordableFilterKey,
            initialValue: filters.isRecordable,
            isDense: true,
            isExpanded: true,
            decoration:
                const InputDecoration(labelText: 'Recordable', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem<bool?>(value: null, child: Text('Any')),
              DropdownMenuItem<bool?>(value: true, child: Text('Recordable')),
              DropdownMenuItem<bool?>(value: false, child: Text('Not recordable')),
            ],
            onChanged: (value) => context
                .read<SafetyIncidentsBloc>()
                .add(SafetyIncidentsRecordableFilterChanged(value)),
          ),
        ),
        SizedBox(
          width: 165,
          child: AppDateField(
            key: SafetyIncidentsScreen.fromDateKey,
            name: 'safety-incidents-from',
            label: 'Occurred from',
            value: filters.from,
            optional: true,
            onChanged: (value) => context
                .read<SafetyIncidentsBloc>()
                .add(SafetyIncidentsDateRangeChanged(from: value, clearFrom: value == null)),
          ),
        ),
        SizedBox(
          width: 165,
          child: AppDateField(
            key: SafetyIncidentsScreen.toDateKey,
            name: 'safety-incidents-to',
            label: 'Occurred to',
            value: filters.to,
            optional: true,
            onChanged: (value) => context
                .read<SafetyIncidentsBloc>()
                .add(SafetyIncidentsDateRangeChanged(to: value, clearTo: value == null)),
          ),
        ),
        if (filters.isSet)
          TextButton(
            key: SafetyIncidentsScreen.clearFiltersKey,
            onPressed: () =>
                context.read<SafetyIncidentsBloc>().add(const SafetyIncidentsFiltersCleared()),
            child: Text('Clear filters', style: theme.textTheme.bodyMedium),
          ),
      ],
    );
  }
}

/// The register was capped — said out loud rather than left to be inferred,
/// the same rule `NonconformancesScreen`'s own `_Truncated` follows
/// (ADR-0026).
class _Truncated extends StatelessWidget {
  const _Truncated();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: AppPageFrame(
        maxWidth: SafetyIncidentsScreen.maxWidth,
        child: Padding(
          key: SafetyIncidentsScreen.truncatedKey,
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.sm),
          child: Text(
            'There are more Safety incidents than this list shows. Narrow it by Org Unit, by '
            'status or by date to see the rest.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

/// Two empty stories, told apart (issue #103, and the binding design comment
/// on #223): a Site with no incidents recorded is good news that must not be
/// celebrated, and a filter that matched nothing is a filter to clear.
class _Empty extends StatelessWidget {
  const _Empty({required this.isFiltered});

  final bool isFiltered;

  @override
  Widget build(BuildContext context) {
    if (isFiltered) {
      return PlatformEmptyState.noneMatched(
        key: SafetyIncidentsScreen.emptyMatchedKey,
        title: 'Nothing matches these filters',
        message: 'The register has Safety incidents, but none of them is in the area, state, '
            'type, severity, recordability or dates you picked.',
        actionLabel: 'Clear the filters',
        actionKey: SafetyIncidentsScreen.emptyClearFiltersKey,
        onAction: () =>
            context.read<SafetyIncidentsBloc>().add(const SafetyIncidentsFiltersCleared()),
      );
    }
    // Flat, deliberately — never "All clear". A plant with no incidents may
    // simply not be reporting, which is the exact failure ADR-0036 trades
    // against.
    return const PlatformEmptyState.noneExist(
      key: SafetyIncidentsScreen.emptyKey,
      title: 'No incidents recorded for this period',
      message: 'No Safety incident has been recorded at this Site for the area and dates shown.',
      icon: Icons.health_and_safety_outlined,
    );
  }
}

class _Register extends StatelessWidget {
  const _Register({required this.rows});

  final List<SafetyIncident> rows;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AppPageFrame(
        maxWidth: SafetyIncidentsScreen.maxWidth,
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
          itemCount: rows.length,
          itemBuilder: (context, index) => _SafetyIncidentRow(incident: rows[index]),
        ),
      ),
    );
  }
}

class _SafetyIncidentRow extends StatelessWidget {
  const _SafetyIncidentRow({required this.incident});

  final SafetyIncident incident;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final row = incident;

    return Card(
      key: SafetyIncidentsScreen.rowKey(row.id),
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      child: InkWell(
        onTap: () => context.go('${Routes.safetyIncidents}/${row.id}'),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          // Two chips, separated by role rather than stacked (the binding
          // design comment on #223): severity on the left, with the number,
          // Org Unit and date — what happened — and status on the right —
          // what is being done about it.
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
                          key: SafetyIncidentsScreen.rowSeverityKey(row.id),
                          label: row.severityLabel,
                          tone: row.severityTone,
                        ),
                        Text(row.incidentNo, style: theme.textTheme.labelMedium),
                      ],
                    ),
                    const SizedBox(height: Spacing.xs),
                    Text(row.incidentTypeLabel, style: theme.textTheme.titleMedium),
                    const SizedBox(height: Spacing.xxs),
                    Text(
                      '${row.orgUnitName} · filed against ${row.filedAgainst}',
                      key: SafetyIncidentsScreen.rowFiledKey(row.id),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Spacing.sm),
              StatusChip(
                key: SafetyIncidentsScreen.rowStatusKey(row.id),
                label: row.statusLabel,
                tone: row.statusTone,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
