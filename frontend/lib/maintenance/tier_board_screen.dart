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

import '../status_tone.dart';
import '../theme.dart';
import '../widgets/app_date_field.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/app_page_header.dart';
import '../widgets/app_table.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/status_chip.dart';
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
    final loaded = state is TierBoardLoaded ? state as TierBoardLoaded : null;

    return Center(
      child: AppPageFrame(
        maxWidth: TierBoardScreen.maxWidth,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.lg),
          child: AppPageHeader(
            title: 'Tier board',
            description:
                'The numbers this Site\'s work produces, reported under the five Pillars. '
                'Every Pillar is shown whether or not anything reports under it yet.',
            below: loaded == null ? null : _Controls(state: loaded),
          ),
        ),
      ),
    );
  }
}

/// A control's width at the reader's text scale: the 1x widths were measured for
/// 1x text, and a dropdown's label and value grow with it, so the box grows too
/// (never below its 1x width). A `Wrap` clamps it to the line if the line is
/// narrower.
double _controlWidth(BuildContext context, double base) {
  final scale = MediaQuery.textScalerOf(context).scale(1);
  return base * (scale < 1 ? 1 : scale);
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
            width: _controlWidth(context, 220),
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
          width: _controlWidth(context, 150),
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
          width: _controlWidth(context, 220),
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

/// Placeholders in the board's own shape: five Pillar tiles, so the wait reads
/// as the board arriving rather than as an unrelated spinner. Five across where
/// the box can hold them, two across where it cannot (a tile five-across in a
/// phone-width box is too short for its own bars), decided from the box and the
/// reader's text scale, like the lane rows.
class _BoardSkeleton extends StatelessWidget {
  const _BoardSkeleton();

  static const int _wideColumns = 5;
  static const int _narrowColumns = 2;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SkeletonGrid(
        key: TierBoardScreen.loadingKey,
        tiles: 5,
        crossAxisCount:
            constraints.maxWidth >= AppBreakpoints.effective(context, AppBreakpoints.registerTable)
                ? _wideColumns
                : _narrowColumns,
        maxWidth: TierBoardScreen.maxWidth,
      ),
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

/// The board (docs/design-language.md section 6): a legend of the tones the
/// rows actually paint, then one lane per Pillar, stacked, each lane a header and
/// one row per KPI. Nothing in a lane scrolls: the page's own `SingleChildScrollView`
/// is the one scroller, vertical, so nothing scrolls sideways at any width or
/// text scale.
class _TierBoardView extends StatelessWidget {
  const _TierBoardView({required this.board});

  final TierBoard board;

  /// A tone's own word, which is what `StatusTone` calls it: the enum's name,
  /// sentence-cased like every other chip label. The same source and the same
  /// convention as the floor's legend (`status_tone.dart`, and the tone legend in
  /// `docs/design-language.md` section 13): a private copy, because that one is
  /// private to its Screen and `widgets/` is not this slice's to change.
  static String toneWord(StatusTone tone) =>
      '${tone.name[0].toUpperCase()}${tone.name.substring(1)}';

  @override
  Widget build(BuildContext context) {
    // Only the tones the rows use, in the enum's own order.
    final tones = [
      for (final tone in StatusTone.values)
        if (board.pillars.any((pillar) => pillar.kpis.any((kpi) => _toneOf(kpi) == tone))) tone,
    ];
    return Center(
      child: AppPageFrame(
        maxWidth: TierBoardScreen.maxWidth,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (tones.isNotEmpty)
                Wrap(
                  spacing: Spacing.sm,
                  runSpacing: Spacing.sm,
                  children: [
                    for (final tone in tones) StatusChip(label: toneWord(tone), tone: tone),
                  ],
                ),
              for (final pillar in board.pillars) ...[
                const SizedBox(height: Spacing.md),
                _PillarLane(pillar: pillar),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A KPI's tone, decided here and not in `tier_board.dart`: green is success,
/// amber warning, red danger; no target, no data and a status this build does not
/// know are neutral. The label stays `BoardKpi.statusLabel`.
StatusTone _toneOf(BoardKpi kpi) => switch (kpi.status) {
      BoardKpi.greenStatus => StatusTone.success,
      BoardKpi.amberStatus => StatusTone.warning,
      BoardKpi.redStatus => StatusTone.danger,
      _ => StatusTone.neutral,
    };

class _PillarLane extends StatelessWidget {
  const _PillarLane({required this.pillar});

  final Pillar pillar;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final muted = AppTypography.dense(context)?.copyWith(color: palette.textMuted);
    const inset = EdgeInsets.symmetric(horizontal: Spacing.md);

    return Card(
      key: TierBoardScreen.pillarKey(pillar.code),
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Spacing.md, Spacing.md, Spacing.md, Spacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: Text(
                    pillar.name,
                    style: AppTypography.dense(context)?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Text(
                  '${pillar.kpis.length}',
                  style: AppTypography.floor(context)?.copyWith(color: palette.textMuted),
                ),
              ],
            ),
          ),
          // A Pillar with nothing measured says so rather than standing as an
          // empty box. Its KPIs still render beneath — each honestly reading
          // "No data" — so a later read that fills one in shows without this
          // note having hidden the shape of the Pillar.
          if (!pillar.hasData)
            Padding(
              padding: inset.copyWith(bottom: Spacing.sm),
              child: Text(
                'No data yet',
                key: TierBoardScreen.pillarNoDataKey(pillar.code),
                style: muted,
              ),
            ),
          if (pillar.kpis.isEmpty)
            Padding(
              padding: inset.copyWith(bottom: Spacing.md),
              child: Text('No KPI is defined under this Pillar yet.', style: muted),
            )
          else
            for (final kpi in pillar.kpis) _KpiRow(kpi: kpi),
        ],
      ),
    );
  }
}

/// One KPI: its name, its number, and its standing as a chip in its own slot.
///
/// A table row (name flex 4, number flex 2 end-aligned, chip flex 2 end-aligned)
/// when the lane's own box is wide enough, measured from the `LayoutBuilder` and
/// compared with the reader's text scale counted (`AppBreakpoints.registerTable`,
/// the same threshold the registers turn at). Narrower, or at a large text size,
/// the name takes its own line and the number and chip share the one under it, so
/// nothing is clipped and nothing scrolls sideways.
class _KpiRow extends StatelessWidget {
  const _KpiRow({required this.kpi});

  final BoardKpi kpi;

  static const List<AppTableColumn> _columns = [
    AppTableColumn('KPI', flex: 4),
    AppTableColumn('Value', flex: 2, align: AppColumnAlign.end),
    AppTableColumn('Status', flex: 2, align: AppColumnAlign.end),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final name = Tooltip(
      message: kpi.formulaText,
      child: Text(
        kpi.name,
        style: AppTypography.dense(context)?.copyWith(color: palette.textPrimary),
      ),
    );
    final value = Text(
      kpi.formattedValue,
      key: TierBoardScreen.kpiValueKey(kpi.code),
      style: AppTableRow.numberStyle(context)?.copyWith(color: palette.textPrimary),
    );
    final unit = kpi.unit.isEmpty
        ? null
        : Text(
            kpi.unit,
            style: AppTypography.floor(context)?.copyWith(color: palette.textMuted),
          );
    final chip = StatusChip(
      key: TierBoardScreen.kpiStatusKey(kpi.code),
      label: kpi.statusLabel,
      tone: _toneOf(kpi),
    );
    final figure = Wrap(
      spacing: Spacing.xxs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [value, ?unit],
    );

    return KeyedSubtree(
      key: TierBoardScreen.kpiKey(kpi.code),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >=
              AppBreakpoints.effective(context, AppBreakpoints.registerTable)) {
            return AppTableRow(
              columns: _columns,
              cells: [
                name,
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: Spacing.xxs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [value, ?unit],
                ),
                chip,
              ],
            );
          }
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm),
            foregroundDecoration:
                BoxDecoration(border: Border(bottom: BorderSide(color: palette.edge))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                name,
                const SizedBox(height: Spacing.xs),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: figure),
                    const SizedBox(width: Spacing.sm),
                    chip,
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
