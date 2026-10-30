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
import '../widgets/app_list_card.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import 'add_kpi_dialog.dart';
import 'kpi_catalogue.dart';
import 'kpi_catalogue_bloc.dart';

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

class _Loaded extends StatelessWidget {
  const _Loaded({required this.state, required this.canWrite});

  final KpiCatalogueLoaded state;
  final bool canWrite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final catalogue = state.catalogue;
    return Center(
      child: AppPageFrame(
        maxWidth: KpiCatalogueScreen.maxWidth,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xl),
          children: [
            Text('KPI catalogue', style: theme.textTheme.headlineSmall),
            const SizedBox(height: Spacing.xs),
            Text(
              catalogue == null
                  ? 'The KPIs of the MTU line, with the Target in force per grain.'
                  : 'The KPIs of the MTU line, with the Target in force per grain and the '
                      'review state for today, ${catalogue.reviewDate}.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
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
                      key: KpiCatalogueScreen.siteKey,
                      initialValue: state.siteId,
                      isDense: true,
                      decoration: const InputDecoration(labelText: 'Site', border: OutlineInputBorder()),
                      items: [
                        for (final site in state.sites)
                          DropdownMenuItem<String>(value: site.id, child: Text(site.name)),
                      ],
                      onChanged: (siteId) {
                        if (siteId == null) return;
                        context.read<KpiCatalogueBloc>().add(KpiCatalogueSiteSelected(siteId));
                      },
                    ),
                  ),
                if (canWrite)
                  FilledButton.icon(
                    key: KpiCatalogueScreen.addKpiKey,
                    onPressed: () => AddKpiDialog.open(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Add KPI'),
                  ),
              ],
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
            else
              AppListCard(
                rows: [
                  const _HeaderRow(),
                  for (final kpi in catalogue.kpis) _KpiRowTile(kpi: kpi, siteId: state.siteId),
                ],
              ),
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

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600);
    Widget cell(int flex, String label) => Expanded(flex: flex, child: Text(label, style: style));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          cell(_kpiFlex, 'KPI'),
          cell(_unitFlex, 'Unit'),
          cell(_directionFlex, 'Direction'),
          cell(_grainFlex, 'Daily'),
          cell(_grainFlex, 'Weekly'),
          cell(_grainFlex, 'Monthly'),
          cell(_todayFlex, 'Today'),
        ],
      ),
    );
  }
}

class _KpiRowTile extends StatelessWidget {
  const _KpiRowTile({required this.kpi, required this.siteId});

  final KpiRow kpi;
  final String siteId;

  String _target(KpiTarget? target) => target == null ? '—' : formatTarget(kpi, target.target);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = theme.textTheme.bodyMedium;
    return InkWell(
      key: KpiCatalogueScreen.rowKey(kpi.kpiId),
      onTap: () => context.go(Routes.kpiTargets(kpi.kpiId, siteId: siteId)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: _kpiFlex,
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
            Expanded(flex: _unitFlex, child: Text(kpi.unit.isEmpty ? '—' : kpi.unit, style: body)),
            Expanded(flex: _directionFlex, child: Text(kpi.direction, style: body)),
            Expanded(flex: _grainFlex, child: Text(_target(kpi.daily), style: body)),
            Expanded(flex: _grainFlex, child: Text(_target(kpi.weekly), style: body)),
            Expanded(flex: _grainFlex, child: Text(_target(kpi.monthly), style: body)),
            Expanded(flex: _todayFlex, child: Text(KpiCatalogueScreen.todayLabel(kpi.review), style: body)),
          ],
        ),
      ),
    );
  }
}
