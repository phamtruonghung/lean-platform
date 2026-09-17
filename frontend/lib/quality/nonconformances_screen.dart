/// The Non-conformance register (issue #205, CONTEXT.md's
/// **Non-conformance**): what has been found not to conform at this Site, how
/// much of it there is, and where it was found.
///
/// Read Site-wide by anyone who can see the Site, whatever their Grants — the
/// same rule the Work order list, the Asset register, the action log and the
/// tier board already follow (#55, ADR-0009, ADR-0032). Recording is offered
/// to everyone too: the server is the real gate on where one may be recorded
/// (a write Grant reaching that Org Unit), and hiding the button would gate an
/// address that answers a clean refusal with a sentence the caller can act on.
///
/// Every filter is a read filter over the already-visible register and sends a
/// request rather than hiding rows client-side, so a narrowed read is what the
/// server's own indexes and its ltree walk are for. The Org Unit filter
/// includes everything *beneath* the chosen area, which is the ticket's own
/// criterion and what "everything under Line 3" means in this Platform.
///
/// Nothing here is typed that has a known set (ADR-0023): the status, the
/// Defect code, the Product and the severity are chosen from what the server
/// offers, and the two ends of the date range are dates, not free text.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../platform/router.dart';
import '../status_tone.dart';
import '../theme.dart';
import '../widgets/app_date_field.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/status_chip.dart';
import 'defect_code.dart';
import 'nonconformance.dart';
import 'nonconformance_org_unit_filter_dialog.dart';
import 'nonconformances_bloc.dart';

class NonconformancesScreen extends StatelessWidget {
  const NonconformancesScreen({super.key});

  static const double maxWidth = 1100;

  static const ValueKey<String> recordKey = ValueKey<String>('nonconformances-record');
  static const ValueKey<String> siteKey = ValueKey<String>('nonconformances-site');
  static const ValueKey<String> orgUnitFilterKey = ValueKey<String>('nonconformances-filter-org-unit');
  static const ValueKey<String> statusFilterKey = ValueKey<String>('nonconformances-filter-status');
  static const ValueKey<String> defectCodeFilterKey =
      ValueKey<String>('nonconformances-filter-defect-code');
  static const ValueKey<String> productFilterKey = ValueKey<String>('nonconformances-filter-product');
  static const ValueKey<String> severityFilterKey =
      ValueKey<String>('nonconformances-filter-severity');
  static const ValueKey<String> fromDateKey = ValueKey<String>('nonconformances-filter-from');
  static const ValueKey<String> toDateKey = ValueKey<String>('nonconformances-filter-to');
  static const ValueKey<String> clearFiltersKey = ValueKey<String>('nonconformances-clear-filters');
  static const ValueKey<String> truncatedKey = ValueKey<String>('nonconformances-truncated');
  static const ValueKey<String> emptyKey = ValueKey<String>('nonconformances-empty');
  static const ValueKey<String> emptyMatchedKey = ValueKey<String>('nonconformances-empty-matched');
  static const ValueKey<String> emptyClearFiltersKey =
      ValueKey<String>('nonconformances-empty-clear');
  static const ValueKey<String> failedKey = ValueKey<String>('nonconformances-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('nonconformances-retry');
  static const ValueKey<String> noSiteKey = ValueKey<String>('nonconformances-no-site');
  static const ValueKey<String> formLoadingKey = ValueKey<String>('nonconformances-form-loading');

  static ValueKey<String> rowKey(String id) => ValueKey<String>('nonconformance-row-$id');
  static ValueKey<String> rowStatusKey(String id) =>
      ValueKey<String>('nonconformance-status-$id');
  static ValueKey<String> rowSeverityKey(String id) =>
      ValueKey<String>('nonconformance-severity-$id');
  static ValueKey<String> rowQuantityKey(String id) =>
      ValueKey<String>('nonconformance-quantity-$id');
  static ValueKey<String> rowFiledKey(String id) => ValueKey<String>('nonconformance-filed-$id');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NonconformancesBloc>().state;

    return _RefreshOnMount(
      child: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(state: state),
            Expanded(
              child: switch (state) {
                NonconformancesLoading() => const SkeletonList(rows: 4, maxWidth: maxWidth),
                NonconformancesUnavailable(message: final message) => PlatformFailureState(
                    key: failedKey,
                    title: 'The Non-conformance register could not be read',
                    message: message,
                    retryKey: retryKey,
                    onRetry: () =>
                        context.read<NonconformancesBloc>().add(const NonconformancesStarted()),
                  ),
                NonconformancesLoaded(siteId: null) => const PlatformEmptyState.noneExist(
                    key: noSiteKey,
                    title: 'No Site to show',
                    message: 'Your Account can see no Site yet, so there is nothing to read here.',
                    icon: Icons.factory_outlined,
                  ),
                NonconformancesLoaded(
                  nonconformances: final rows,
                  filters: final filters
                )
                    when rows.isEmpty =>
                  _Empty(isFiltered: filters.isSet),
                NonconformancesLoaded(nonconformances: final rows) => _Register(rows: rows),
              },
            ),
            if (state is NonconformancesLoaded && state.truncated) const _Truncated(),
          ],
        ),
      ),
    );
  }
}

/// Asks the register to re-read whenever the Screen is entered (issue #183).
///
/// The `ShellRoute` creates `NonconformancesBloc` once and keeps it alive while
/// a caller reads a Non-conformance and comes back, so a Screen that only read
/// on `NonconformancesStarted` painted the list as it was when they left —
/// records written elsewhere, quantities grown, none of it visible. The Bloc
/// ignores the ask while its first load is still in flight.
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
    // After this frame, never during it: dispatching an event from `initState`
    // is a side effect while the tree is being built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<NonconformancesBloc>().add(const NonconformancesRefreshed());
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _Header extends StatelessWidget {
  const _Header({required this.state});

  final NonconformancesState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loaded = state is NonconformancesLoaded ? state as NonconformancesLoaded : null;

    return Center(
      child: AppPageFrame(
        maxWidth: NonconformancesScreen.maxWidth,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // A `Wrap`, not a `Row`: the button's label is long and the
              // header must not overflow at a narrow width.
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: Spacing.md,
                runSpacing: Spacing.sm,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Non-conformances', style: theme.textTheme.headlineSmall),
                      const SizedBox(height: Spacing.xs),
                      Text(
                        'What was found not to conform at this Site, where it was found, and how '
                        'much of it there is.',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                  if (loaded != null)
                    FilledButton.icon(
                      key: NonconformancesScreen.recordKey,
                      onPressed: loaded.isRecording || loaded.siteId == null
                          ? null
                          : () => context.go('${Routes.nonConformances}/new'),
                      icon: const Icon(Icons.add),
                      label: const Text('Record a Non-conformance'),
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

  final NonconformancesLoaded loaded;

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
              key: NonconformancesScreen.siteKey,
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
                context.read<NonconformancesBloc>().add(NonconformancesSiteSelected(siteId));
              },
            ),
          ),
        OutlinedButton.icon(
          key: NonconformancesScreen.orgUnitFilterKey,
          onPressed: () => NonconformanceOrgUnitFilterDialog.open(context, siteId: loaded.siteId),
          icon: const Icon(Icons.account_tree_outlined),
          label: Text(filters.orgUnitName ?? 'All Org Units'),
        ),
        SizedBox(
          width: 180,
          child: DropdownButtonFormField<String?>(
            key: NonconformancesScreen.statusFilterKey,
            initialValue: filters.status,
            isDense: true,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Any status')),
              for (final status in NonconformanceStatus.values)
                DropdownMenuItem<String?>(
                  value: status,
                  child: Text(NonconformanceStatus.label(status)),
                ),
            ],
            onChanged: (status) => context
                .read<NonconformancesBloc>()
                .add(NonconformancesStatusFilterChanged(status)),
          ),
        ),
        SizedBox(
          width: 210,
          child: DropdownButtonFormField<String?>(
            key: NonconformancesScreen.defectCodeFilterKey,
            initialValue: filters.defectCodeId,
            isDense: true,
            isExpanded: true,
            decoration:
                const InputDecoration(labelText: 'Defect code', border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Every Defect code')),
              for (final code in loaded.defectCodes)
                DropdownMenuItem<String?>(
                  value: code.id,
                  child: Text('${code.name} · ${code.code}'),
                ),
            ],
            onChanged: (id) => context
                .read<NonconformancesBloc>()
                .add(NonconformancesDefectCodeFilterChanged(id)),
          ),
        ),
        SizedBox(
          width: 200,
          child: DropdownButtonFormField<String?>(
            key: NonconformancesScreen.productFilterKey,
            initialValue: filters.productId,
            isDense: true,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Product', border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Every Product')),
              for (final product in loaded.products)
                DropdownMenuItem<String?>(
                  value: product.id,
                  child: Text('${product.name} · ${product.code}'),
                ),
            ],
            onChanged: (id) =>
                context.read<NonconformancesBloc>().add(NonconformancesProductFilterChanged(id)),
          ),
        ),
        SizedBox(
          width: 170,
          child: DropdownButtonFormField<String?>(
            key: NonconformancesScreen.severityFilterKey,
            initialValue: filters.severity,
            isDense: true,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Severity', border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Any severity')),
              for (final severity in DefectSeverity.values)
                DropdownMenuItem<String?>(
                  value: severity,
                  child: Text(DefectSeverity.label(severity)),
                ),
            ],
            onChanged: (severity) => context
                .read<NonconformancesBloc>()
                .add(NonconformancesSeverityFilterChanged(severity)),
          ),
        ),
        SizedBox(
          width: 165,
          child: AppDateField(
            key: NonconformancesScreen.fromDateKey,
            name: 'nonconformances-from',
            label: 'Detected from',
            value: filters.from,
            optional: true,
            onChanged: (value) => context
                .read<NonconformancesBloc>()
                .add(NonconformancesDateRangeChanged(from: value, clearFrom: value == null)),
          ),
        ),
        SizedBox(
          width: 165,
          child: AppDateField(
            key: NonconformancesScreen.toDateKey,
            name: 'nonconformances-to',
            label: 'Detected to',
            value: filters.to,
            optional: true,
            onChanged: (value) => context
                .read<NonconformancesBloc>()
                .add(NonconformancesDateRangeChanged(to: value, clearTo: value == null)),
          ),
        ),
        if (filters.isSet)
          TextButton(
            key: NonconformancesScreen.clearFiltersKey,
            onPressed: () =>
                context.read<NonconformancesBloc>().add(const NonconformancesFiltersCleared()),
            child: Text('Clear filters', style: theme.textTheme.bodyMedium),
          ),
      ],
    );
  }
}

/// The register was capped. Said out loud rather than left to be inferred from
/// a list that happens to end: a capped list must not read as a whole Site
/// (ADR-0026's rule, applied to a register).
class _Truncated extends StatelessWidget {
  const _Truncated();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: AppPageFrame(
        maxWidth: NonconformancesScreen.maxWidth,
        child: Padding(
          key: NonconformancesScreen.truncatedKey,
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.sm),
          child: Text(
            'There are more Non-conformances than this list shows. Narrow it by Org Unit, by '
            'status or by date to see the rest.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

/// Two empty stories, told apart (issue #103): a Site with nothing on its
/// register is a good-news empty, and a filter that matched nothing is a
/// filter to clear. The wrong one would send a caller looking for a record
/// that exists.
class _Empty extends StatelessWidget {
  const _Empty({required this.isFiltered});

  final bool isFiltered;

  @override
  Widget build(BuildContext context) {
    if (isFiltered) {
      return PlatformEmptyState.noneMatched(
        key: NonconformancesScreen.emptyMatchedKey,
        title: 'Nothing matches these filters',
        message: 'The register has Non-conformances, but none of them is in the area, state, '
            'Defect code, Product, severity or dates you picked.',
        actionLabel: 'Clear the filters',
        actionKey: NonconformancesScreen.emptyClearFiltersKey,
        onAction: () =>
            context.read<NonconformancesBloc>().add(const NonconformancesFiltersCleared()),
      );
    }
    return const PlatformEmptyState.noneExist(
      key: NonconformancesScreen.emptyKey,
      title: 'Nothing has been found not to conform',
      message: 'No Non-conformance has been recorded at this Site.',
      icon: Icons.fact_check_outlined,
    );
  }
}

class _Register extends StatelessWidget {
  const _Register({required this.rows});

  final List<Nonconformance> rows;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AppPageFrame(
        maxWidth: NonconformancesScreen.maxWidth,
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
          itemCount: rows.length,
          itemBuilder: (context, index) => _NonconformanceRow(nonconformance: rows[index]),
        ),
      ),
    );
  }
}

class _NonconformanceRow extends StatelessWidget {
  const _NonconformanceRow({required this.nonconformance});

  final Nonconformance nonconformance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final row = nonconformance;

    return Card(
      key: NonconformancesScreen.rowKey(row.id),
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      child: InkWell(
        onTap: () => context.go('${Routes.nonConformances}/${row.id}'),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: Spacing.xs,
                runSpacing: Spacing.xxs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(row.issueNo, style: theme.textTheme.labelMedium),
                  StatusChip(
                    key: NonconformancesScreen.rowStatusKey(row.id),
                    label: row.statusLabel,
                    tone: row.statusTone,
                  ),
                  StatusChip(
                    key: NonconformancesScreen.rowSeverityKey(row.id),
                    label: row.severityLabel,
                    tone: _severityTone(row.severity),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.xs),
              Text(
                '${row.productName} · ${row.defectCodeName} · ${row.detectionPointLabel}',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: Spacing.xxs),
              Text(
                '${row.orgUnitName} · filed against ${row.filedAgainst}',
                key: NonconformancesScreen.rowFiledKey(row.id),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: Spacing.xxs),
              Text(
                // The count, and whether it has grown since it was first
                // written down — a reader deciding what to do about it needs
                // the number that is true now.
                '${_number(row.quantityAffected)} ${row.uomCode} affected'
                '${row.quantityChanged ? ' · raised ${row.quantityChanges.length} time'
                    '${row.quantityChanges.length == 1 ? '' : 's'}' : ''}',
                key: NonconformancesScreen.rowQuantityKey(row.id),
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A severity's meaning in the shared status vocabulary (issue #168): a
/// critical find wants attention, a major one wants a decision, a minor one is
/// the quietest of the three.
StatusTone _severityTone(String severity) => switch (severity) {
      'critical' => StatusTone.danger,
      'major' => StatusTone.warning,
      _ => StatusTone.neutral,
    };

/// A quantity without a trailing `.0` — 12, not 12.0, since that is how a
/// person writes a count of pieces.
String _number(double value) =>
    value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toString();
