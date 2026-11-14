/// The cost rate catalogue (issue #252, ADR-0005's shared catalogue): the money
/// the Platform costs things at — an hour of labour, an hour a machine is down,
/// the premium on an overtime hour — laid over an administrator's own write
/// surface for it (`POST`/`PATCH /api/people/cost-rates` and the revision
/// route, cost-rate-routes.js).
///
/// `JobRolesScreen`'s shape, and for the same reasons, with one thing neither
/// it nor any other catalogue Screen has: every row carries its **period**, and
/// a closed period is shown rather than hidden. That is the point of the
/// catalogue — a cost reported for September has to stay what it was in
/// September, so the rate that produced it must stay readable.
///
/// Its **Destination** is an administrator's (see `destinations.dart`), because
/// a plant's labour rates are commercially sensitive in a way a job role list is
/// not. The Screen itself is not gated, because the read behind it is not:
/// `GET /api/people/cost-rates` carries no admin and no Org Unit scope of its
/// own, so a non-administrator who follows a link here sees the catalogue with
/// no write affordances on it — exactly what they would see on `/job-roles`.
///
/// **This page does not tell anyone what a given Org Unit's rate is.** The rate
/// that actually applies somewhere falls back from the Asset to the nearest
/// ancestor Org Unit to the Site, in the database
/// (`resolve_cost_rate`), and `GET /api/people/cost-rates/resolution` is what
/// answers that question. Re-spelling the fallback here, over a list of rows,
/// is exactly the second implementation the ticket rules out.
///
/// **It is a register, not a catalogue (issue #392, `design-language.md` §5 and
/// §6).** A rate is read *across*: two rates are compared by their amount and by
/// when each applied, and neither comparison is possible when the amount sits
/// inside a sentence beside the rate's kind. So the page says its columns once,
/// as [_columns], and builds both the band and every row's cells from that list
/// — which is what makes the header label and the cells beneath it start at the
/// same x by construction. Above [narrowBreakpoint] of content width the table
/// is drawn; below it one card per rate. The breakpoint is read from the box a
/// `LayoutBuilder` hands the list, never from the window, and scaled by the
/// reader's text size (§10; the class of bug #379 and #381).
///
/// **Money is the one place alignment is not a taste call (§6, §13).** The
/// amount column is end-aligned in tabular figures, so a column of rates
/// compares down its right edge and its digits line up inside that edge, and the
/// unit lives in the column *label* — `Amount (EUR)` — rather than being
/// repeated on every cell. Where the catalogue cannot name one unit the label
/// says only `Amount` and each cell carries its own, because a multiplier
/// (`× 1.5`) is dimensionless: a header claiming EUR over a column of
/// multipliers would be a lie the reader cannot see.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/app_localizations.dart';
import '../status_tone.dart';
import '../theme.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/app_page_header.dart';
import '../widgets/app_table.dart';
import '../widgets/disclosing_text.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/status_chip.dart';
import 'cost_rate.dart';
import 'cost_rate_form_dialog.dart';
import 'cost_rates_bloc.dart';
import '../l10n/vocabulary.dart';

class CostRatesScreen extends StatelessWidget {
  const CostRatesScreen({super.key, required this.isAdmin});

  /// Whether this caller may set or correct a rate — read off `/me`'s own role,
  /// the same shape `JobRolesScreen.isAdmin` follows.
  final bool isAdmin;

  /// A register's width, not a catalogue's: five columns and two actions are
  /// read across, and the money column wants the room (§6).
  static const double maxWidth = 1100;

  /// Five columns or fewer, so `AppBreakpoints.registerTable` (700) is the
  /// number, read through [AppBreakpoints.effective] and never asked of the
  /// window.
  static const double narrowBreakpoint = AppBreakpoints.registerTable;

  static const ValueKey<String> addKey = ValueKey<String>('cost-rates-add');
  static const ValueKey<String> failedKey = ValueKey<String>('cost-rates-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('cost-rates-retry');
  static const ValueKey<String> emptyKey = ValueKey<String>('cost-rates-empty');
  static const ValueKey<String> emptyAddKey = ValueKey<String>('cost-rates-empty-add');
  static ValueKey<String> rowKey(String id) => ValueKey<String>('cost-rates-row-$id');
  static ValueKey<String> correctKey(String id) => ValueKey<String>('cost-rates-correct-$id');
  static ValueKey<String> reviseKey(String id) => ValueKey<String>('cost-rates-revise-$id');
  static ValueKey<String> closedChipKey(String id) => ValueKey<String>('cost-rates-closed-$id');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<CostRatesBloc>().state;

    return Scaffold(
      body: switch (state) {
        CostRatesLoading() => const SkeletonList(maxWidth: CostRatesScreen.maxWidth),
        CostRatesUnavailable(message: final message) => PlatformFailureState(
            key: CostRatesScreen.failedKey,
            title: l10n.costRatesTheCostRateCatalogueCouldNotBe,
            message: message,
            retryKey: CostRatesScreen.retryKey,
            onRetry: () => context.read<CostRatesBloc>().add(const CostRatesStarted()),
          ),
        CostRatesLoaded() => _Loaded(state: state, isAdmin: isAdmin),
      },
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({required this.state, required this.isAdmin});

  final CostRatesLoaded state;
  final bool isAdmin;

  void _add(BuildContext context) => CostRateFormDialog.open(
        context,
        mode: CostRateFormMode.add,
        scopes: state.scopes,
        scopesFailure: state.scopesFailure,
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: AppPageFrame(
        maxWidth: CostRatesScreen.maxWidth,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xl),
          children: [
            AppPageHeader(
              title: l10n.navCostRates,
              description:
                  l10n.costRatesWhatAnHourCostsOneCatalogueShared,
              actions: [
                if (isAdmin)
                  FilledButton.icon(
                    key: CostRatesScreen.addKey,
                    onPressed: state.isMutating ? null : () => _add(context),
                    icon: const Icon(Icons.add),
                    label: Text(l10n.costRatesAddCostRate),
                  ),
              ],
            ),
            const SizedBox(height: Spacing.lg),
            if (state.costRates.isEmpty)
              PlatformEmptyState.noneExist(
                key: CostRatesScreen.emptyKey,
                title: l10n.costRatesNoCostRatesYet,
                message: l10n.costRatesUntilARateIsSetEveryCost,
                icon: Icons.payments_outlined,
                actionLabel: isAdmin ? l10n.costRatesAddCostRate : null,
                actionKey: CostRatesScreen.emptyAddKey,
                onAction: isAdmin ? () => _add(context) : null,
              )
            else
              _Register(state: state, isAdmin: isAdmin),
          ],
        ),
      ),
    );
  }
}

/// The one column spec: [AppTableHeader] and every [AppTableRow] are built from
/// it, so a label and its cells start at the same x.
List<AppTableColumn> _columns(BuildContext context, List<CostRate> rows) => [
      AppTableColumn(AppLocalizations.of(context).costRatesRate, flex: 4),
      AppTableColumn(
        _amountColumnLabel(rows),
        width: _amountColumnWidth(context, rows),
        align: AppColumnAlign.end,
      ),
      AppTableColumn(AppLocalizations.of(context).commonScope, flex: 5),
      AppTableColumn(AppLocalizations.of(context).commonPeriod, flex: 5),
      AppTableColumn(AppLocalizations.of(context).commonActions, width: _actionsColumnWidth(context), align: AppColumnAlign.end),
    ];

/// Whether the column can name one unit for every row: true only when every
/// rate is money in the same currency. A multiplier makes it false — `× 1.5`
/// is dimensionless, and §13 puts the unit on the label only when the label's
/// unit is true of every cell under it.
bool _oneUnit(List<CostRate> rows) =>
    rows.every((row) => !costRateIsMultiplier(row.rateType)) &&
    rows.map((row) => row.currency).toSet().length == 1;

String _amountColumnLabel(List<CostRate> rows) =>
    _oneUnit(rows) ? 'Amount (${rows.first.currency})' : 'Amount';

/// The figure a cell shows: the bare amount where the column carries the unit,
/// and the amount with its own unit where it cannot.
String _amountCell(CostRate row, {required bool oneUnit}) => oneUnit
    ? (costRateIsMultiplier(row.rateType) ? '× ${row.amount}' : '${row.amount}')
    : row.amountLabel;

/// The amount column: the widest figure in the list, plus the slot's own
/// gutter. Measured rather than guessed, so a four-figure rate is not clipped
/// and a three-figure one does not leave a gulf.
double _amountColumnWidth(BuildContext context, List<CostRate> rows) {
  final oneUnit = _oneUnit(rows);
  var widest = 0.0;
  for (final row in rows) {
    final width = _measure(
      context,
      _amountCell(row, oneUnit: oneUnit),
      AppTableRow.numberStyle(context),
    );
    if (width > widest) widest = width;
  }
  final header = _measure(
    context,
    _amountColumnLabel(rows),
    Theme.of(context).textTheme.labelMedium,
  );
  return (widest > header ? widest : header) + 2 * Spacing.sm;
}

/// Correct and Revise side by side, at the 44px floor each button states for
/// itself, plus the slot's gutter. The button's own horizontal padding is
/// [Spacing.xl] a side — `OutlinedButton`'s default, and what the quality
/// registers measure for the same reason (#390).
double _actionsColumnWidth(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  final label = Theme.of(context).textTheme.labelLarge;
  final correct = _measure(context, l10n.commonCorrect, label) + 2 * Spacing.xl;
  final revise = _measure(context, l10n.commonRevise, label) + 2 * Spacing.xl;
  return correct + Spacing.sm + revise + 2 * Spacing.sm;
}

double _measure(BuildContext context, String text, TextStyle? style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  return painter.width;
}

class _Register extends StatelessWidget {
  const _Register({required this.state, required this.isAdmin});

  final CostRatesLoaded state;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    // The box this list actually got, scaled by the reader's text size (§10) —
    // never the window.
    return LayoutBuilder(
      builder: (context, box) {
        final narrow =
            box.maxWidth < AppBreakpoints.effective(context, CostRatesScreen.narrowBreakpoint);
        final columns = _columns(context, state.costRates);
        final oneUnit = _oneUnit(state.costRates);

        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < state.costRates.length; index++) ...[
                if (index > 0) const SizedBox(height: Spacing.sm),
                _CostRateCard(
                  costRate: state.costRates[index],
                  isAdmin: isAdmin,
                  isMutating: state.isMutating,
                  scopes: state.scopes,
                ),
              ],
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTableHeader(columns: columns),
            for (final costRate in state.costRates)
              _CostRateTableRow(
                columns: columns,
                costRate: costRate,
                oneUnit: oneUnit,
                isAdmin: isAdmin,
                isMutating: state.isMutating,
                scopes: state.scopes,
              ),
          ],
        );
      },
    );
  }
}

/// The framework's padded tap target is lifted on the row's buttons: each one
/// states its own [AppTouchTarget.min] through `minimumSize`, and the padded
/// target would add height to a row that already carries the 44.
Widget _shrinkWrapTargets(BuildContext context, Widget child) => Theme(
      data: Theme.of(context).copyWith(materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
      child: child,
    );

class _CostRateTableRow extends StatelessWidget {
  const _CostRateTableRow({
    required this.columns,
    required this.costRate,
    required this.oneUnit,
    required this.isAdmin,
    required this.isMutating,
    required this.scopes,
  });

  final List<AppTableColumn> columns;
  final CostRate costRate;
  final bool oneUnit;
  final bool isAdmin;
  final bool isMutating;
  final List<CostRateScope> scopes;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = AppColors.of(context);
    final dense = AppTypography.dense(context);
    final row = costRate;

    return KeyedSubtree(
      key: CostRatesScreen.rowKey(row.id),
      child: AppTableRow(
        columns: columns,
        cells: [
          DisclosingText(costRateTypeLabel(l10n, row.rateType), style: dense?.copyWith(color: palette.textPrimary)),
          Text(
            _amountCell(row, oneUnit: oneUnit),
            style: AppTableRow.numberStyle(context)?.copyWith(color: palette.textPrimary),
            maxLines: 1,
            softWrap: false,
          ),
          DisclosingText(row.scopeLabel(l10n), style: dense?.copyWith(color: palette.textMuted)),
          _periodCell(context, row),
          _shrinkWrapTargets(
            context,
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isAdmin) ...[
                  OutlinedButton(
                    key: CostRatesScreen.correctKey(row.id),
                    onPressed: isMutating
                        ? null
                        : () => CostRateFormDialog.open(
                              context,
                              mode: CostRateFormMode.correct,
                              scopes: scopes,
                              costRate: row,
                            ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(AppTouchTarget.min, AppTouchTarget.min),
                    ),
                    child: Text(l10n.commonCorrect),
                  ),
                  const SizedBox(width: Spacing.sm),
                  OutlinedButton(
                    key: CostRatesScreen.reviseKey(row.id),
                    onPressed: isMutating
                        ? null
                        : () => CostRateFormDialog.open(
                              context,
                              mode: CostRateFormMode.revise,
                              scopes: scopes,
                              costRate: row,
                            ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(AppTouchTarget.min, AppTouchTarget.min),
                    ),
                    child: Text(l10n.commonRevise),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The period, with the closed chip beside it. One function for both shapes, so
/// the table row and the card say the same thing about the same record.
Widget _periodCell(BuildContext context, CostRate row) {
  final l10n = AppLocalizations.of(context);
  final dense = AppTypography.dense(context);
  final palette = AppColors.of(context);
  return _shrinkWrapTargets(
    context,
    Wrap(
      spacing: Spacing.sm,
      runSpacing: Spacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        DisclosingText(row.periodLabel, style: dense?.copyWith(color: palette.textMuted)),
        if (!row.isCurrent)
          StatusChip(
            key: CostRatesScreen.closedChipKey(row.id),
            label: l10n.commonClosed,
            tone: StatusTone.neutral,
          ),
      ],
    ),
  );
}

/// One rate as a card, for a box that cannot hold five columns: the same four
/// facts stacked, and the same two actions. A narrow box is a narrow box, not a
/// reason to drop what a reader decides on (§6).
class _CostRateCard extends StatelessWidget {
  const _CostRateCard({
    required this.costRate,
    required this.isAdmin,
    required this.isMutating,
    required this.scopes,
  });

  final CostRate costRate;
  final bool isAdmin;
  final bool isMutating;
  final List<CostRateScope> scopes;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dense = AppTypography.dense(context);
    final floor = AppTypography.floor(context);
    final palette = AppColors.of(context);
    final row = costRate;

    return Card(
      key: CostRatesScreen.rowKey(row.id),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    costRateTypeLabel(l10n, row.rateType),
                    style: dense?.copyWith(color: palette.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                // Outside a column the figure carries its own unit (§13).
                Text(
                  row.amountLabel,
                  style: AppTableRow.numberStyle(context)?.copyWith(color: palette.textPrimary),
                  maxLines: 1,
                ),
              ],
            ),
            const SizedBox(height: Spacing.xs),
            Text(row.scopeLabel(l10n), style: floor?.copyWith(color: palette.textMuted)),
            const SizedBox(height: Spacing.xxs),
            _periodCell(context, row),
            if (isAdmin) ...[
              const SizedBox(height: Spacing.sm),
              Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.sm,
                children: [
                  OutlinedButton(
                    key: CostRatesScreen.correctKey(row.id),
                    onPressed: isMutating
                        ? null
                        : () => CostRateFormDialog.open(
                              context,
                              mode: CostRateFormMode.correct,
                              scopes: scopes,
                              costRate: row,
                            ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(AppTouchTarget.min, AppTouchTarget.min),
                    ),
                    child: Text(l10n.commonCorrect),
                  ),
                  OutlinedButton(
                    key: CostRatesScreen.reviseKey(row.id),
                    onPressed: isMutating
                        ? null
                        : () => CostRateFormDialog.open(
                              context,
                              mode: CostRateFormMode.revise,
                              scopes: scopes,
                              costRate: row,
                            ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(AppTouchTarget.min, AppTouchTarget.min),
                    ),
                    child: Text(l10n.commonRevise),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
