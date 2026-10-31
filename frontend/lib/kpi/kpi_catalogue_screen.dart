/// The KPI catalogue (ADR-0055) at `/kpi`: every KPI of the MTU line with the
/// Target in force per grain and today's review state.
///
/// A ruled grid of `AppListCard` rows rather than a `DataTable`, so a row keeps
/// its own `Key` and is tappable as a whole; each column is an `Expanded` of
/// its own and wraps rather than overflows at the Shell's page width. A row
/// opens that KPI's Targets (`/kpi/:kpiId/targets`).
///
/// "Today" is the server's: the read carries no `date`, so `review_date` is the
/// Site's own today and the Today column is that day's judgement.
///
/// **Add KPI is offered only with write authority** (`canWrite`, read at the
/// router from `/me`'s `orgUnitScope.canWriteSomewhere`, as every other Screen
/// does). The server is still the gate: its 403 renders as its own sentence in
/// the dialog.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../platform/router.dart';
import '../theme.dart';
import '../widgets/app_filter_field.dart';
import '../widgets/app_list_card.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/app_page_header.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import 'add_kpi_dialog.dart';
import 'kpi_catalogue.dart';
import 'kpi_catalogue_bloc.dart';
import 'kpi_matrix.dart';

class KpiCatalogueScreen extends StatelessWidget {
  const KpiCatalogueScreen({super.key, required this.canWrite});

  /// Whether the caller holds a write Grant anywhere (or is an administrator).
  final bool canWrite;

  static const double maxWidth = AppLayout.pageWidth;

  static const ValueKey<String> siteKey = ValueKey<String>('kpi-catalogue-site');
  static const ValueKey<String> addKpiKey = ValueKey<String>('kpi-catalogue-add');
  static const ValueKey<String> failedKey = ValueKey<String>('kpi-catalogue-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('kpi-catalogue-retry');
  static const ValueKey<String> emptyKey = ValueKey<String>('kpi-catalogue-empty');
  static ValueKey<String> rowKey(int kpiId) => ValueKey<String>('kpi-catalogue-row-$kpiId');

  static const ValueKey<String> headerRowKey = ValueKey<String>('kpi-catalogue-header');
  static const ValueKey<String> noMatchKey = ValueKey<String>('kpi-catalogue-no-match');
  static const String filterFieldName = 'kpi-catalogue-filter';
  static ValueKey<String> get filterFieldKey => AppFilterField.fieldKey(filterFieldName);
  static ValueKey<String> get filterClearKey => AppFilterField.clearKey(filterFieldName);
  static ValueKey<String> get filterCountKey => AppFilterField.countKey(filterFieldName);

  /// The header cell of one column, by its label (`'KPI'`, `'Unit'`, …).
  static ValueKey<String> columnHeaderKey(String column) =>
      ValueKey<String>('kpi-catalogue-column-$column');

  /// The body cell of one column of one KPI's row.
  static ValueKey<String> cellKey(int kpiId, String column) =>
      ValueKey<String>('kpi-catalogue-cell-$kpiId-$column');

  /// The label a review state is shown under in the Today column.
  static String todayLabel(KpiReviewEntry? review) =>
      review == null ? 'Not reviewed' : ReviewStatus.label(review.status);

  @override
  Widget build(BuildContext context) {
    final state = context.watch<KpiCatalogueBloc>().state;
    return Scaffold(
      body: switch (state) {
        KpiCatalogueLoading() => const SkeletonList(maxWidth: KpiCatalogueScreen.maxWidth),
        KpiCatalogueUnavailable(message: final message) => PlatformFailureState(
            key: KpiCatalogueScreen.failedKey,
            title: 'The KPI catalogue could not be read',
            message: message,
            retryKey: KpiCatalogueScreen.retryKey,
            onRetry: () => context.read<KpiCatalogueBloc>().add(const KpiCatalogueStarted()),
          ),
        KpiCatalogueLoaded() => _Loaded(state: state, canWrite: canWrite),
      },
    );
  }
}

/// Stateful only because the filter box's term is the Screen's own: a filter is
/// a view of the rows the Bloc already holds, so typing is a `setState`.
class _Loaded extends StatefulWidget {
  const _Loaded({required this.state, required this.canWrite});

  final KpiCatalogueLoaded state;
  final bool canWrite;

  @override
  State<_Loaded> createState() => _LoadedState();
}

class _LoadedState extends State<_Loaded> {
  /// What the filter box is narrowing the catalogue to, `''` when nothing is.
  String _term = '';

  @override
  void didUpdateWidget(covariant _Loaded oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A different Site is a different catalogue.
    if (oldWidget.state.siteId != widget.state.siteId) _term = '';
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final canWrite = widget.canWrite;
    final catalogue = state.catalogue;
    // Filtered here, immediately before the row widgets are built.
    final matches = catalogue == null
        ? const <KpiRow>[]
        : [
            for (final kpi in catalogue.kpis)
              if (kpiMatchesSearch(code: kpi.kpi, title: kpi.title, term: _term)) kpi,
          ];
    return Center(
      child: AppPageFrame(
        maxWidth: KpiCatalogueScreen.maxWidth,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xl),
          children: [
            AppPageHeader(
              title: 'KPI catalogue',
              description: catalogue == null
                  ? 'The KPIs of the MTU line, with the Target in force per grain.'
                  : 'The KPIs of the MTU line, with the Target in force per grain and the '
                      'review state for today, ${catalogue.reviewDate}.',
              actions: [
                if (canWrite)
                  FilledButton.icon(
                    key: KpiCatalogueScreen.addKpiKey,
                    onPressed: () => AddKpiDialog.open(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Add KPI'),
                  ),
              ],
              below: state.sites.length > 1
                  ? SizedBox(
                      width: 280,
                      child: DropdownButtonFormField<String>(
                        key: KpiCatalogueScreen.siteKey,
                        initialValue: state.siteId,
                        isDense: true,
                        decoration:
                            const InputDecoration(labelText: 'Site', border: OutlineInputBorder()),
                        items: [
                          for (final site in state.sites)
                            DropdownMenuItem<String>(value: site.id, child: Text(site.name)),
                        ],
                        onChanged: (siteId) {
                          if (siteId == null) return;
                          context.read<KpiCatalogueBloc>().add(KpiCatalogueSiteSelected(siteId));
                        },
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: Spacing.lg),
            if (state.isLoadingCatalogue || catalogue == null)
              const SkeletonList(rows: 3, maxWidth: KpiCatalogueScreen.maxWidth)
            else if (catalogue.kpis.isEmpty)
              const PlatformEmptyState.noneExist(
                key: KpiCatalogueScreen.emptyKey,
                title: 'No KPIs in the catalogue yet',
                message: 'Nothing has been added to the KPI catalogue.',
                icon: Icons.insights_outlined,
              )
            else ...[
              AppFilterField(
                name: KpiCatalogueScreen.filterFieldName,
                label: 'Filter KPIs',
                helperText: 'By code or title.',
                term: _term,
                onChanged: (term) => setState(() => _term = term),
                shown: matches.length,
                total: catalogue.kpis.length,
              ),
              const SizedBox(height: Spacing.lg),
              if (matches.isEmpty)
                PlatformEmptyState.noneMatched(
                  key: KpiCatalogueScreen.noMatchKey,
                  title: 'No KPIs match',
                  message: 'Nothing in the catalogue matches "${_term.trim()}". Try a '
                      'different code or title, or clear the filter.',
                )
              else
                AppListCard(
                  rows: [
                    MatrixHeaderRow(key: KpiCatalogueScreen.headerRowKey, columns: _columns),
                    for (final kpi in matches) _KpiRowTile(kpi: kpi, siteId: state.siteId),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }
}

// Column weights shared by the header and the rows, so they line up.
const int _kpiFlex = 4;
const int _unitFlex = 1;
const int _directionFlex = 1;
const int _grainFlex = 2;
const int _todayFlex = 2;

MatrixColumn _column(int flex, String label) =>
    MatrixColumn(flex: flex, label: label, headerKey: KpiCatalogueScreen.columnHeaderKey(label));

final List<MatrixColumn> _columns = [
  _column(_kpiFlex, 'KPI'),
  _column(_unitFlex, 'Unit'),
  _column(_directionFlex, 'Direction'),
  _column(_grainFlex, 'Daily'),
  _column(_grainFlex, 'Weekly'),
  _column(_grainFlex, 'Monthly'),
  _column(_todayFlex, 'Today'),
];

class _KpiRowTile extends StatelessWidget {
  const _KpiRowTile({required this.kpi, required this.siteId});

  final KpiRow kpi;
  final String siteId;

  String _target(KpiTarget? target) => target == null ? '—' : formatTarget(kpi, target.target);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = theme.textTheme.bodyMedium;
    Widget cell(int flex, String column, Widget child) =>
        matrixCell(flex: flex, key: KpiCatalogueScreen.cellKey(kpi.kpiId, column), child: child);
    return InkWell(
      key: KpiCatalogueScreen.rowKey(kpi.kpiId),
      onTap: () => context.go(Routes.kpiTargets(kpi.kpiId, siteId: siteId)),
      child: Padding(
        padding: matrixRowPadding,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            matrixCell(
              flex: _kpiFlex,
              key: KpiCatalogueScreen.cellKey(kpi.kpiId, 'KPI'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(kpi.kpi, style: body?.copyWith(fontWeight: FontWeight.w600)),
                  Text(
                    kpi.title,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            cell(_unitFlex, 'Unit', Text(kpi.unit.isEmpty ? '—' : kpi.unit, style: body)),
            cell(_directionFlex, 'Direction', Text(kpi.direction, style: body)),
            cell(_grainFlex, 'Daily', Text(_target(kpi.daily), style: body)),
            cell(_grainFlex, 'Weekly', Text(_target(kpi.weekly), style: body)),
            cell(_grainFlex, 'Monthly', Text(_target(kpi.monthly), style: body)),
            cell(_todayFlex, 'Today', Text(KpiCatalogueScreen.todayLabel(kpi.review), style: body)),
          ],
        ),
      ),
    );
  }
}
