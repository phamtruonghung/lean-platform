/// One store's stock (issue #80): what is on the shelf, and the receive action
/// that adds to it. Readable by anyone whose role earns the Module, whatever
/// their Grants (ADR-0009); receiving is offered only to a caller who holds a
/// write Grant somewhere, because an action the server would refuse is not
/// offered in the first place.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import '../widgets/app_list_card.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import 'receive_dialog.dart';
import 'stock_level.dart';
import 'store_stock_bloc.dart';

class StoreStockScreen extends StatelessWidget {
  const StoreStockScreen({super.key, required this.canReceive});

  /// Whether this caller holds a write Grant anywhere at all — read off
  /// `/me`'s own `orgUnitScope`. False hides the receive affordance entirely.
  final bool canReceive;

  /// The Platform's own page width (issue #189): this Screen used to declare
  /// 800, one of five numbers six catalogue Screens each picked for themselves.
  static const double maxWidth = AppLayout.pageWidth;
  static const ValueKey<String> receiveKey = ValueKey<String>('store-stock-receive');
  static const ValueKey<String> failedKey = ValueKey<String>('store-stock-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('store-stock-retry');
  static const ValueKey<String> emptyKey = ValueKey<String>('store-stock-empty');
  static ValueKey<String> rowKey(String partId) => ValueKey<String>('store-stock-row-$partId');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<StoreStockBloc>().state;

    return Scaffold(
      body: switch (state) {
        StoreStockLoading() => const SkeletonList(maxWidth: maxWidth),
        StoreStockUnavailable(message: final message) => PlatformFailureState(
            key: StoreStockScreen.failedKey,
            title: 'This store could not be read',
            message: message,
            retryKey: StoreStockScreen.retryKey,
            onRetry: () => context.read<StoreStockBloc>().add(const StoreStockStarted()),
          ),
        StoreStockLoaded() => _Loaded(state: state, canReceive: canReceive),
      },
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({required this.state, required this.canReceive});

  final StoreStockLoaded state;
  final bool canReceive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: AppPageFrame(
        maxWidth: StoreStockScreen.maxWidth,
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
                      Text(state.store.name, style: theme.textTheme.headlineSmall),
                      const SizedBox(height: Spacing.xs),
                      Text(
                        '${state.store.code} · ${state.store.orgUnitName}',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (canReceive && state.parts.isNotEmpty)
                  FilledButton.icon(
                    key: StoreStockScreen.receiveKey,
                    onPressed: state.isReceiving
                        ? null
                        : () => ReceiveDialog.open(context, parts: state.parts),
                    icon: const Icon(Icons.add),
                    label: const Text('Receive stock'),
                  ),
              ],
            ),
            const SizedBox(height: Spacing.lg),
            if (state.stock.isEmpty)
              const PlatformEmptyState.noneExist(
                key: StoreStockScreen.emptyKey,
                title: 'Nothing on the shelf',
                message: 'No part has moved in or out of this store yet.',
                icon: Icons.inventory_2_outlined,
              )
            else
              // One row per part on the shelf, ruled apart from its
              // neighbours (issue #189).
              AppListCard(
                rows: [for (final level in state.stock) _StockRow(level: level)],
              ),
          ],
        ),
      ),
    );
  }
}

class _StockRow extends StatelessWidget {
  const _StockRow({required this.level});

  final StockLevel level;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: StoreStockScreen.rowKey(level.partId),
      padding: const EdgeInsets.all(Spacing.md),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(level.partNo, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 2),
                Text(
                  level.description,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Text('${level.quantity} ${level.uomCode}', style: theme.textTheme.titleMedium),
        ],
      ),
    );
  }
}
