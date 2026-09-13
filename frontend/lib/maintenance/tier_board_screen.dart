/// The tier board: the KPIs a Site's work produces, reported under the five
/// Pillars, over a chosen period (issue #76).
///
/// Readable by any approved Account whose role earns it, across the whole Site
/// and whatever its own Grants (ADR-0009) — a tier board a supervisor can only
/// half-see is not a tier board. The Destination and the route are deliberately
/// ungated for that reason.
///
/// CONTEXT.md's vocabulary is load-bearing in the copy: a **Pillar** is a
/// heading the numbers report under (not a Module, not an area), a **KPI** is
/// one number under it, and a **Production day** is the Site-local span a
/// period is resolved against — never the calendar day a clock happened to
/// show. The Screen renders Pillars in the order the server sent them and never
/// hard-codes a Module-to-Pillar mapping.
///
/// The one distinction this Screen exists to keep honest: a KPI with no data
/// shows "No data" and an em dash, never `0`. An unmeasured number and a
/// measured zero are different facts (issue #76's own AC), and a board that
/// renders zero where nothing was measured lies about the plant.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import '../widgets/app_date_field.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import 'tier_board.dart';
import 'tier_board_bloc.dart';
import 'tier_board_org_unit_filter_dialog.dart';

class TierBoardScreen extends StatelessWidget {
  const TierBoardScreen({super.key});

  static const double maxWidth = 1200;

  /// The board's date control is an `AppDateField` (ADR-0023); it is named here
  /// so the Screen's own key accessor and the widget share one string.
  static const String dateFieldName = 'tier-board-date';

  static const ValueKey<String> siteKey = ValueKey<String>('tier-board-site');
  static const ValueKey<String> orgUnitFilterKey = ValueKey<String>('tier-board-org-unit-filter');
  static const ValueKey<String> periodTypeKey = ValueKey<String>('tier-board-period-type');

  /// The date control's own key, equal to the `AppDateField` it renders.
  static final ValueKey<String> dateKey = AppDateField.fieldKey(dateFieldName);

  static const ValueKey<String> loadingKey = ValueKey<String>('tier-board-loading');
  static const ValueKey<String> failedKey = ValueKey<String>('tier-board-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('tier-board-retry');
  static const ValueKey<String> emptyKey = ValueKey<String>('tier-board-empty');

  static ValueKey<String> pillarKey(String code) => ValueKey<String>('tier-board-pillar-$code');
  static ValueKey<String> pillarNoDataKey(String code) =>
      ValueKey<String>('tier-board-pillar-no-data-$code');
  static ValueKey<String> kpiKey(String code) => ValueKey<String>('tier-board-kpi-$code');
  static ValueKey<String> kpiValueKey(String code) =>
      ValueKey<String>('tier-board-kpi-value-$code');
  static ValueKey<String> kpiStatusKey(String code) =>
      ValueKey<String>('tier-board-kpi-status-$code');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TierBoardBloc>().state;

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(state: state),
          Expanded(
            child: switch (state) {
              TierBoardLoading() => const _BoardSkeleton(),
              TierBoardUnavailable(message: final message) => PlatformFailureState(
                  key: failedKey,
                  title: 'The tier board could not be read',
                  message: message,
                  retryKey: retryKey,
                  onRetry: () => context.read<TierBoardBloc>().add(const TierBoardStarted()),
                ),
              TierBoardLoaded(isLoadingBoard: true) => const _BoardSkeleton(),
              TierBoardLoaded(board: final board)
                  when board == null || board.pillars.isEmpty =>
                const _TierBoardEmpty(),
              TierBoardLoaded(board: final board) => _TierBoardView(board: board!),
            },
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state});

  final TierBoardState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loaded = state is TierBoardLoaded ? state as TierBoardLoaded : null;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: TierBoardScreen.maxWidth),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tier board', style: theme.textTheme.headlineSmall),
              const SizedBox(height: Spacing.xs),
              Text(
                'The numbers this Site\'s work produces, reported under the five Pillars. '
                'Every Pillar is shown whether or not anything reports under it yet.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              if (loaded != null) ...[
                const SizedBox(height: Spacing.md),
                _Controls(state: loaded),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The four controls, each dispatching exactly one event on change.
class _Controls extends StatelessWidget {
  const _Controls({required this.state});

  final TierBoardLoaded state;

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<TierBoardBloc>();
    return Wrap(
      spacing: Spacing.sm,
      runSpacing: Spacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (state.sites.length > 1)
          SizedBox(
            width: 220,
            child: DropdownButtonFormField<String>(
              key: TierBoardScreen.siteKey,
              initialValue: state.siteId,
              isDense: true,
              decoration: const InputDecoration(labelText: 'Site', border: OutlineInputBorder()),
              items: [
                for (final site in state.sites)
                  DropdownMenuItem<String>(value: site.id, child: Text(site.name)),
              ],
              onChanged: (siteId) {
                if (siteId == null) return;
                bloc.add(TierBoardSiteSelected(siteId));
              },
            ),
          ),
        SizedBox(
          width: 150,
          child: DropdownButtonFormField<String>(
            key: TierBoardScreen.periodTypeKey,
            initialValue: state.periodType,
            isDense: true,
            decoration: const InputDecoration(labelText: 'Period', border: OutlineInputBorder()),
            items: [
              for (final periodType in BoardPeriodType.selectable)
                DropdownMenuItem<String>(value: periodType.wire, child: Text(periodType.label)),
            ],
            onChanged: (periodType) {
              if (periodType == null) return;
              bloc.add(TierBoardPeriodTypeSelected(periodType));
            },
          ),
        ),
        SizedBox(
          width: 220,
          child: AppDateField(
            name: TierBoardScreen.dateFieldName,
            label: 'Date',
            value: state.date,
            optional: true,
            enabled: !state.isLoadingBoard,
            onChanged: (date) => bloc.add(TierBoardDateChanged(date)),
          ),
        ),
        OutlinedButton.icon(
          key: TierBoardScreen.orgUnitFilterKey,
          onPressed: state.isLoadingBoard
              ? null
              : () => TierBoardOrgUnitFilterDialog.open(context),
          icon: const Icon(Icons.account_tree_outlined, size: 18),
          label: Text(state.orgUnitFilterName ?? 'All Org Units'),
          style: OutlinedButton.styleFrom(minimumSize: const Size(44, 44)),
        ),
      ],
    );
  }
}

/// Placeholders in the board's own shape: five Pillar columns, so the wait
/// reads as the board arriving rather than as an unrelated spinner.
class _BoardSkeleton extends StatelessWidget {
  const _BoardSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SkeletonGrid(
      key: TierBoardScreen.loadingKey,
      tiles: 5,
      crossAxisCount: 5,
      maxWidth: TierBoardScreen.maxWidth,
    );
  }
}

class _TierBoardEmpty extends StatelessWidget {
  const _TierBoardEmpty();

  @override
  Widget build(BuildContext context) {
    return const PlatformEmptyState.noneExist(
      key: TierBoardScreen.emptyKey,
      title: 'No Pillars to show',
      message: 'This Site has no Pillars to report against yet.',
    );
  }
}

class _TierBoardView extends StatelessWidget {
  const _TierBoardView({required this.board});

  final TierBoard board;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: TierBoardScreen.maxWidth),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
          child: Wrap(
            spacing: Spacing.md,
            runSpacing: Spacing.md,
            crossAxisAlignment: WrapCrossAlignment.start,
            children: [
              for (final pillar in board.pillars) _PillarColumn(pillar: pillar),
            ],
          ),
        ),
      ),
    );
  }
}

class _PillarColumn extends StatelessWidget {
  const _PillarColumn({required this.pillar});

  final Pillar pillar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted);

    return SizedBox(
      width: 220,
      child: Card(
        key: TierBoardScreen.pillarKey(pillar.code),
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(pillar.name, style: theme.textTheme.titleMedium),
              const SizedBox(height: Spacing.xs),
              // A Pillar with nothing measured says so rather than standing as
              // an empty box. Its KPIs still render beneath — each honestly
              // reading "No data" — so a later read that fills one in shows
              // without this note having hidden the shape of the Pillar.
              if (!pillar.hasData) ...[
                Text(
                  'No data yet',
                  key: TierBoardScreen.pillarNoDataKey(pillar.code),
                  style: muted,
                ),
                const SizedBox(height: Spacing.sm),
              ],
              if (pillar.kpis.isEmpty)
                Text('No KPI is defined under this Pillar yet.', style: muted)
              else
                for (var i = 0; i < pillar.kpis.length; i++) ...[
                  if (i > 0) const SizedBox(height: Spacing.sm),
                  _KpiCard(kpi: pillar.kpis[i]),
                ],
            ],
          ),
        ),
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.kpi});

  final BoardKpi kpi;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted);

    return Container(
      key: TierBoardScreen.kpiKey(kpi.code),
      padding: const EdgeInsets.all(Spacing.sm),
      decoration: BoxDecoration(
        border: Border.all(color: AppComponentColors.cardBorder),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Tooltip(
            message: kpi.formulaText,
            child: Text(kpi.name, style: theme.textTheme.bodyMedium),
          ),
          const SizedBox(height: Spacing.xxs),
          Wrap(
            spacing: Spacing.xxs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                kpi.formattedValue,
                key: TierBoardScreen.kpiValueKey(kpi.code),
                style: theme.textTheme.titleLarge,
              ),
              if (kpi.unit.isNotEmpty) Text(kpi.unit, style: muted),
            ],
          ),
          const SizedBox(height: Spacing.xs),
          _StatusIndicator(kpi: kpi),
        ],
      ),
    );
  }
}

class _StatusIndicator extends StatelessWidget {
  const _StatusIndicator({required this.kpi});

  final BoardKpi kpi;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (IconData icon, Color color) = switch (kpi.status) {
      BoardKpi.greenStatus => (Icons.check_circle_outline, AppColors.statusSuccess),
      BoardKpi.amberStatus => (Icons.error_outline, AppColors.statusWarning),
      BoardKpi.redStatus => (Icons.cancel_outlined, AppColors.statusDanger),
      BoardKpi.noTargetStatus => (Icons.remove_circle_outline, scheme.onSurfaceVariant),
      _ => (Icons.horizontal_rule, scheme.onSurfaceVariant),
    };

    return Row(
      key: TierBoardScreen.kpiStatusKey(kpi.code),
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: Spacing.xxs),
        Text(
          kpi.statusLabel,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color),
        ),
      ],
    );
  }
}
