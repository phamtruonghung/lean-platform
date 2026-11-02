/// The product standard cost catalogue (issue #252, ADR-0005's shared
/// catalogue): what one unit of a Product is costed at, and from when — what
/// the baseline's cost-of-poor-quality view prices scrap with.
///
/// `CostRatesScreen`'s shape exactly, and for the same reasons — see that
/// file's own header for why closed periods are shown rather than hidden, and
/// why the Destination is an administrator's while the Screen itself is not
/// gated (`GET /api/people/product-costs` carries no admin and no Org Unit
/// scope of its own).
///
/// **It is a register (issue #392, `design-language.md` §5, §6 and §13).** A
/// standard cost is read across — what one unit is costed at is compared with
/// the next unit's, and with what the same unit cost last quarter — so the page
/// states its columns once ([_columns]) and builds the band and every row's
/// cells from that list, and the money column is end-aligned in tabular figures
/// under a label that names its currency, `Amount (EUR)`, with every cell a bare
/// figure beneath it. Above [narrowBreakpoint] of content width the table is
/// drawn and below it one card per cost; the number is read from the box a
/// `LayoutBuilder` hands the list and scaled by the reader's text size (§10).
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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
import 'product_cost.dart';
import 'product_cost_form_dialog.dart';
import 'product_costs_bloc.dart';

class ProductCostsScreen extends StatelessWidget {
  const ProductCostsScreen({super.key, required this.isAdmin});

  final bool isAdmin;

  /// A register's width, not a catalogue's (§6).
  static const double maxWidth = 1100;

  /// Four columns or fewer, so `AppBreakpoints.registerTable` (700) is the
  /// number — read through [AppBreakpoints.effective], never asked of the
  /// window.
  static const double narrowBreakpoint = AppBreakpoints.registerTable;

  static const ValueKey<String> addKey = ValueKey<String>('product-costs-add');
  static const ValueKey<String> failedKey = ValueKey<String>('product-costs-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('product-costs-retry');
  static const ValueKey<String> emptyKey = ValueKey<String>('product-costs-empty');
  static const ValueKey<String> emptyAddKey = ValueKey<String>('product-costs-empty-add');
  static ValueKey<String> rowKey(String id) => ValueKey<String>('product-costs-row-$id');
  static ValueKey<String> correctKey(String id) => ValueKey<String>('product-costs-correct-$id');
  static ValueKey<String> reviseKey(String id) => ValueKey<String>('product-costs-revise-$id');
  static ValueKey<String> closedChipKey(String id) => ValueKey<String>('product-costs-closed-$id');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ProductCostsBloc>().state;

    return Scaffold(
      body: switch (state) {
        ProductCostsLoading() => const SkeletonList(maxWidth: ProductCostsScreen.maxWidth),
        ProductCostsUnavailable(message: final message) => PlatformFailureState(
            key: ProductCostsScreen.failedKey,
            title: 'The standard cost catalogue could not be read',
            message: message,
            retryKey: ProductCostsScreen.retryKey,
            onRetry: () => context.read<ProductCostsBloc>().add(const ProductCostsStarted()),
          ),
        ProductCostsLoaded() => _Loaded(state: state, isAdmin: isAdmin),
      },
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({required this.state, required this.isAdmin});

  final ProductCostsLoaded state;
  final bool isAdmin;

  void _add(BuildContext context) => ProductCostFormDialog.open(
        context,
        mode: ProductCostFormMode.add,
        products: state.products,
        productsFailure: state.productsFailure,
      );

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AppPageFrame(
        maxWidth: ProductCostsScreen.maxWidth,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xl),
          children: [
            AppPageHeader(
              title: 'Product standard costs',
              description:
                  'What a unit is costed at — one catalogue shared by every Site, and what '
                  'scrap and rework are priced with. A cost is never overwritten: it is '
                  'closed, and a new one opened, so a cost reported for an earlier month '
                  'stays what it was.',
              actions: [
                if (isAdmin)
                  FilledButton.icon(
                    key: ProductCostsScreen.addKey,
                    onPressed: state.isMutating ? null : () => _add(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Add standard cost'),
                  ),
              ],
            ),
            const SizedBox(height: Spacing.lg),
            if (state.productCosts.isEmpty)
              PlatformEmptyState.noneExist(
                key: ProductCostsScreen.emptyKey,
                title: 'No standard costs yet',
                message: 'Until a cost is set, scrap and rework are priced at nothing.',
                icon: Icons.sell_outlined,
                actionLabel: isAdmin ? 'Add standard cost' : null,
                actionKey: ProductCostsScreen.emptyAddKey,
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

/// The one column spec: the band and every row are built from it, so a label
/// and its cells start at the same x.
List<AppTableColumn> _columns(BuildContext context, List<ProductCost> rows) => [
      const AppTableColumn('Product', flex: 5),
      AppTableColumn(
        _amountColumnLabel(rows),
        width: _amountColumnWidth(context, rows),
        align: AppColumnAlign.end,
      ),
      const AppTableColumn('Period', flex: 5),
      AppTableColumn('Actions', width: _actionsColumnWidth(context), align: AppColumnAlign.end),
    ];

/// Whether one currency is true of every row — §13 puts the unit on the label
/// only when the label's unit holds for every cell under it.
bool _oneUnit(List<ProductCost> rows) => rows.map((row) => row.currency).toSet().length == 1;

String _amountColumnLabel(List<ProductCost> rows) =>
    _oneUnit(rows) ? 'Amount (${rows.first.currency})' : 'Amount';

/// The bare figure where the column names the unit, and the figure with its own
/// unit where it cannot.
String _amountCell(ProductCost row, {required bool oneUnit}) =>
    oneUnit ? '${row.standardCost}' : row.costLabel;

/// The amount column: the widest figure or label, plus the slot's gutter.
double _amountColumnWidth(BuildContext context, List<ProductCost> rows) {
  final oneUnit = _oneUnit(rows);
  var widest = 0.0;
  for (final row in rows) {
    final width = _measure(context, _amountCell(row, oneUnit: oneUnit), AppTableRow.numberStyle(context));
    if (width > widest) widest = width;
  }
  final header = _measure(context, _amountColumnLabel(rows), Theme.of(context).textTheme.labelMedium);
  return (widest > header ? widest : header) + 2 * Spacing.sm;
}

/// Correct and Revise side by side at the 44px floor each states, plus the
/// slot's gutter. The button's own horizontal padding is [Spacing.xl] a side —
/// `OutlinedButton`'s default, and what the quality registers measure for the
/// same reason (#390).
double _actionsColumnWidth(BuildContext context) {
  final label = Theme.of(context).textTheme.labelLarge;
  final correct = _measure(context, 'Correct', label) + 2 * Spacing.xl;
  final revise = _measure(context, 'Revise', label) + 2 * Spacing.xl;
  return correct + Spacing.sm + revise + 2 * Spacing.sm;
}

/// The width of one line of [text] in [style], in the reader's own text size —
/// a column measured in the metrics that will actually be drawn in it.
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

  final ProductCostsLoaded state;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final narrow = box.maxWidth <
            AppBreakpoints.effective(context, ProductCostsScreen.narrowBreakpoint);
        final columns = _columns(context, state.productCosts);
        final oneUnit = _oneUnit(state.productCosts);

        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < state.productCosts.length; index++) ...[
                if (index > 0) const SizedBox(height: Spacing.sm),
                _ProductCostCard(
                  productCost: state.productCosts[index],
                  isAdmin: isAdmin,
                  isMutating: state.isMutating,
                  products: state.products,
                ),
              ],
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTableHeader(columns: columns),
            for (final productCost in state.productCosts)
              _ProductCostTableRow(
                columns: columns,
                productCost: productCost,
                oneUnit: oneUnit,
                isAdmin: isAdmin,
                isMutating: state.isMutating,
                products: state.products,
              ),
          ],
        );
      },
    );
  }
}

/// The framework's padded tap target is lifted on the row's buttons: each one
/// states its own [AppTouchTarget.min] and the padded target would add height
/// to a row that already carries the 44.
Widget _shrinkWrapTargets(BuildContext context, Widget child) => Theme(
      data: Theme.of(context).copyWith(materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
      child: child,
    );

class _ProductCostTableRow extends StatelessWidget {
  const _ProductCostTableRow({
    required this.columns,
    required this.productCost,
    required this.oneUnit,
    required this.isAdmin,
    required this.isMutating,
    required this.products,
  });

  final List<AppTableColumn> columns;
  final ProductCost productCost;
  final bool oneUnit;
  final bool isAdmin;
  final bool isMutating;
  final List<CostableProduct> products;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final dense = AppTypography.dense(context);
    final row = productCost;

    return KeyedSubtree(
      key: ProductCostsScreen.rowKey(row.id),
      child: AppTableRow(
        columns: columns,
        cells: [
          DisclosingText(row.productLabel, style: dense?.copyWith(color: palette.textPrimary)),
          Text(
            _amountCell(row, oneUnit: oneUnit),
            style: AppTableRow.numberStyle(context)?.copyWith(color: palette.textPrimary),
            maxLines: 1,
            softWrap: false,
          ),
          _periodCell(context, row),
          _actions(context, row),
        ],
      ),
    );
  }

  Widget _actions(BuildContext context, ProductCost row) => _shrinkWrapTargets(
        context,
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isAdmin) ...[
              OutlinedButton(
                key: ProductCostsScreen.correctKey(row.id),
                onPressed: isMutating
                    ? null
                    : () => ProductCostFormDialog.open(
                          context,
                          mode: ProductCostFormMode.correct,
                          products: products,
                          productCost: row,
                        ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(AppTouchTarget.min, AppTouchTarget.min),
                ),
                child: const Text('Correct'),
              ),
              const SizedBox(width: Spacing.sm),
              OutlinedButton(
                key: ProductCostsScreen.reviseKey(row.id),
                onPressed: isMutating
                    ? null
                    : () => ProductCostFormDialog.open(
                          context,
                          mode: ProductCostFormMode.revise,
                          products: products,
                          productCost: row,
                        ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(AppTouchTarget.min, AppTouchTarget.min),
                ),
                child: const Text('Revise'),
              ),
            ],
          ],
        ),
      );
}

/// The period with the closed chip beside it — one function for both shapes, so
/// the row and the card say the same thing about the same record.
Widget _periodCell(BuildContext context, ProductCost row) {
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
            key: ProductCostsScreen.closedChipKey(row.id),
            label: 'Closed',
            tone: StatusTone.neutral,
          ),
      ],
    ),
  );
}

/// One cost as a card, for a box that cannot hold four columns: the same facts
/// stacked and the same two actions.
class _ProductCostCard extends StatelessWidget {
  const _ProductCostCard({
    required this.productCost,
    required this.isAdmin,
    required this.isMutating,
    required this.products,
  });

  final ProductCost productCost;
  final bool isAdmin;
  final bool isMutating;
  final List<CostableProduct> products;

  @override
  Widget build(BuildContext context) {
    final dense = AppTypography.dense(context);
    final palette = AppColors.of(context);
    final row = productCost;

    return Card(
      key: ProductCostsScreen.rowKey(row.id),
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
                    row.productLabel,
                    style: dense?.copyWith(color: palette.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                // Outside a column the figure carries its own unit (§13).
                Text(
                  row.costLabel,
                  style: AppTableRow.numberStyle(context)?.copyWith(color: palette.textPrimary),
                  maxLines: 1,
                ),
              ],
            ),
            const SizedBox(height: Spacing.xs),
            _periodCell(context, row),
            if (isAdmin) ...[
              const SizedBox(height: Spacing.sm),
              Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.sm,
                children: [
                  OutlinedButton(
                    key: ProductCostsScreen.correctKey(row.id),
                    onPressed: isMutating
                        ? null
                        : () => ProductCostFormDialog.open(
                              context,
                              mode: ProductCostFormMode.correct,
                              products: products,
                              productCost: row,
                            ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(AppTouchTarget.min, AppTouchTarget.min),
                    ),
                    child: const Text('Correct'),
                  ),
                  OutlinedButton(
                    key: ProductCostsScreen.reviseKey(row.id),
                    onPressed: isMutating
                        ? null
                        : () => ProductCostFormDialog.open(
                              context,
                              mode: ProductCostFormMode.revise,
                              products: products,
                              productCost: row,
                            ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(AppTouchTarget.min, AppTouchTarget.min),
                    ),
                    child: const Text('Revise'),
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
