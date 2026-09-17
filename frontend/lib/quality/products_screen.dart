/// The Product catalogue (issue #203, ADR-0005's shared catalogue, CONTEXT.md's
/// Product entry): what the plant makes, in one list shared by every Site, laid
/// over an administrator's own write surface for it (`POST`/
/// `PATCH /api/quality/products`, product-routes.js).
///
/// Offered to every approved Account, the same openness `JobRolesScreen` and
/// `SkillsScreen` already have: `GET /api/quality/products` carries no admin
/// and no Org Unit scope of its own (product-routes.js's own header), so
/// hiding this Screen behind a role would gate a destination the route itself
/// never refuses. Only the write affordances inside it ([isAdmin]) are gated.
///
/// No search control on this page, deliberately. The address can narrow by
/// code or name (`?search=`, exercised in `quality_api_test.dart`), but the
/// sweep that puts a finding control on each catalogue Screen is a different
/// ticket, and a Screen that grows one here — `AppFilterField`, which narrows
/// rows the caller already holds and issues no request — would be that sweep
/// arriving early and unannounced. What this page owes issue #203 is the
/// catalogue and the administrator's write surface over it.
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
import 'product.dart';
import 'product_form_dialog.dart';
import 'products_bloc.dart';

class ProductsScreen extends StatelessWidget {
  const ProductsScreen({super.key, required this.isAdmin});

  /// Whether this caller may define or correct a Product — read off `/me`'s
  /// own role, the same shape `JobRolesScreen.isAdmin` follows.
  final bool isAdmin;

  /// The Platform's own page width (issue #189): a catalogue page is the width
  /// every other catalogue is, rather than a number of its own.
  static const double maxWidth = AppLayout.pageWidth;

  static const ValueKey<String> addKey = ValueKey<String>('products-add');
  static const ValueKey<String> failedKey = ValueKey<String>('products-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('products-retry');
  static const ValueKey<String> emptyKey = ValueKey<String>('products-empty');
  static const ValueKey<String> emptyAddKey = ValueKey<String>('products-empty-add');
  static ValueKey<String> rowKey(String id) => ValueKey<String>('products-row-$id');
  static ValueKey<String> correctKey(String id) => ValueKey<String>('products-correct-$id');
  static ValueKey<String> inactiveChipKey(String id) => ValueKey<String>('products-inactive-$id');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ProductsBloc>().state;

    return Scaffold(
      body: switch (state) {
        ProductsLoading() => const SkeletonList(maxWidth: ProductsScreen.maxWidth),
        ProductsUnavailable(message: final message) => PlatformFailureState(
            key: ProductsScreen.failedKey,
            title: 'The Product catalogue could not be read',
            message: message,
            retryKey: ProductsScreen.retryKey,
            onRetry: () => context.read<ProductsBloc>().add(const ProductsStarted()),
          ),
        ProductsLoaded() => _Loaded(state: state, isAdmin: isAdmin),
      },
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({required this.state, required this.isAdmin});

  final ProductsLoaded state;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: AppPageFrame(
        maxWidth: ProductsScreen.maxWidth,
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
                      Text('Products', style: theme.textTheme.headlineSmall),
                      const SizedBox(height: Spacing.xs),
                      Text(
                        'What the plant makes — one catalogue shared by every Site, '
                        'and what each Product is measured in.',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (isAdmin)
                  FilledButton.icon(
                    key: ProductsScreen.addKey,
                    onPressed: state.isMutating ? null : () => ProductFormDialog.open(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Add Product'),
                  ),
              ],
            ),
            const SizedBox(height: Spacing.lg),
            if (state.products.isEmpty)
              PlatformEmptyState.noneExist(
                key: ProductsScreen.emptyKey,
                title: 'No Products yet',
                message: 'Nothing has been defined in the catalogue.',
                icon: Icons.category_outlined,
                actionLabel: isAdmin ? 'Add Product' : null,
                actionKey: ProductsScreen.emptyAddKey,
                onAction: isAdmin ? () => ProductFormDialog.open(context) : null,
              )
            else
              AppListCard(
                rows: [
                  for (final product in state.products)
                    _ProductRow(product: product, isAdmin: isAdmin, isMutating: state.isMutating),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.product, required this.isAdmin, required this.isMutating});

  final Product product;
  final bool isAdmin;
  final bool isMutating;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: ProductsScreen.rowKey(product.id),
      padding: const EdgeInsets.all(Spacing.md),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    // The unit of measure is on the row rather than only in the
                    // form: it is what a quantity of this Product is read in,
                    // and the reason the field is a choice at all (ADR-0023).
                    '${product.name} · ${product.code} · ${product.uomName}',
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                if (!product.isActive) ...[
                  const SizedBox(width: Spacing.sm),
                  StatusChip(
                    key: ProductsScreen.inactiveChipKey(product.id),
                    label: 'Inactive',
                    tone: StatusTone.neutral,
                  ),
                ],
              ],
            ),
          ),
          if (isAdmin)
            OutlinedButton(
              key: ProductsScreen.correctKey(product.id),
              onPressed: isMutating ? null : () => ProductFormDialog.open(context, product: product),
              child: const Text('Correct'),
            ),
        ],
      ),
    );
  }
}
