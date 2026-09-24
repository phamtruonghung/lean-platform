/// The product standard cost catalogue (issue #252, ADR-0005's shared
/// catalogue): what one unit of a Product is costed at, and from when — what
/// the baseline's cost-of-poor-quality view prices scrap with.
///
/// `CostRatesScreen`'s shape exactly, and for the same reasons — see that
/// file's own header for why closed periods are shown rather than hidden, and
/// why the Destination is an administrator's while the Screen itself is not
/// gated (`GET /api/people/product-costs` carries no admin and no Org Unit
/// scope of its own).
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../status_tone.dart';
import '../theme.dart';
import '../widgets/app_list_card.dart';
import '../widgets/app_page_frame.dart';
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

  static const double maxWidth = AppLayout.pageWidth;

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
    final theme = Theme.of(context);
    return Center(
      child: AppPageFrame(
        maxWidth: ProductCostsScreen.maxWidth,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xl),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Product standard costs', style: theme.textTheme.headlineSmall),
                      const SizedBox(height: Spacing.xs),
                      Text(
                        'What a unit is costed at — one catalogue shared by every Site, and what '
                        'scrap and rework are priced with. A cost is never overwritten: it is '
                        'closed, and a new one opened, so a cost reported for an earlier month '
                        'stays what it was.',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
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
              AppListCard(
                rows: [
                  for (final productCost in state.productCosts)
                    _ProductCostRow(
                      productCost: productCost,
                      isAdmin: isAdmin,
                      isMutating: state.isMutating,
                      products: state.products,
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _ProductCostRow extends StatelessWidget {
  const _ProductCostRow({
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
    final theme = Theme.of(context);
    return Padding(
      key: ProductCostsScreen.rowKey(productCost.id),
      padding: const EdgeInsets.all(Spacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        '${productCost.productLabel} · ${productCost.costLabel}',
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    if (!productCost.isCurrent) ...[
                      const SizedBox(width: Spacing.sm),
                      StatusChip(
                        key: ProductCostsScreen.closedChipKey(productCost.id),
                        label: 'Closed',
                        tone: StatusTone.neutral,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: Spacing.xs),
                Text(
                  productCost.periodLabel,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (isAdmin) ...[
            OutlinedButton(
              key: ProductCostsScreen.correctKey(productCost.id),
              onPressed: isMutating
                  ? null
                  : () => ProductCostFormDialog.open(
                        context,
                        mode: ProductCostFormMode.correct,
                        products: products,
                        productCost: productCost,
                      ),
              child: const Text('Correct'),
            ),
            const SizedBox(width: Spacing.sm),
            OutlinedButton(
              key: ProductCostsScreen.reviseKey(productCost.id),
              onPressed: isMutating
                  ? null
                  : () => ProductCostFormDialog.open(
                        context,
                        mode: ProductCostFormMode.revise,
                        products: products,
                        productCost: productCost,
                      ),
              child: const Text('Revise'),
            ),
          ],
        ],
      ),
    );
  }
}
