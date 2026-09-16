/// One store's stock (issue #80): what is on the shelf, and the receive action
/// that adds to it. Readable by anyone whose role earns the Module, whatever
/// their Grants (ADR-0009); receiving is offered only to a caller who holds a
/// write Grant somewhere, because an action the server would refuse is not
/// offered in the first place.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import '../widgets/app_filter_field.dart';
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

  /// The filter box's `name` (issue #191), seeding [filterFieldKey],
  /// [filterClearKey] and [filterCountKey] — kept in one place so the field's
  /// own name and the keys a test reaches it by cannot drift, the same device
  /// `WorkOrderAssignDialog.searchFieldName` uses (issue #187).
  static const String filterFieldName = 'store-stock-filter';

  static ValueKey<String> get filterFieldKey => AppFilterField.fieldKey(filterFieldName);
  static ValueKey<String> get filterClearKey => AppFilterField.clearKey(filterFieldName);
  static ValueKey<String> get filterCountKey => AppFilterField.countKey(filterFieldName);

  /// What a term matching none of the shelf's parts renders — a different
  /// fact from [emptyKey] ("nothing on the shelf"): "is PART-4471 here" is
  /// answered by a term, and "not here" must not read as "this store is
  /// empty".
  static const ValueKey<String> noMatchKey = ValueKey<String>('store-stock-no-match');

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

/// The shelf's loaded view. Stateful only because the filter box's term is
/// the Screen's own (issue #191): a filter is a view of the rows the Bloc
/// already holds, not a state of the domain, so typing costs a `setState` and
/// never a Bloc event.
class _Loaded extends StatefulWidget {
  const _Loaded({required this.state, required this.canReceive});

  final StoreStockLoaded state;
  final bool canReceive;

  @override
  State<_Loaded> createState() => _LoadedState();
}

class _LoadedState extends State<_Loaded> {
  /// What the filter box is narrowing the shelf to, `''` when nothing is.
  String _term = '';

  /// Whether [level] matches [term], already lower-cased and trimmed: a
  /// case-insensitive substring over the two fields that identify the part on
  /// the shelf — its part number and its description. The same rule the
  /// catalogue's own filter uses (issue #187), so "is PART-4471 here" is one
  /// term on either Screen.
  static bool _matches(StockLevel level, String term) =>
      level.partNo.toLowerCase().contains(term) ||
      level.description.toLowerCase().contains(term);

  /// The rows actually rendered — every one of them while the term is empty.
  List<StockLevel> get _matchingStock {
    final term = _term.trim().toLowerCase();
    if (term.isEmpty) return widget.state.stock;
    return widget.state.stock.where((level) => _matches(level, term)).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = widget.state;
    // Filtered here, immediately before the row widgets are built, so a term
    // can only ever narrow rows this Screen already read (issue #191).
    final matches = _matchingStock;
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
                if (widget.canReceive && state.parts.isNotEmpty)
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
            else ...[
              // A filter box over an empty shelf would be a control that can
              // do nothing, so it appears with the rows — and stays while a
              // term excludes them all, because the reader still has to be
              // able to clear it.
              AppFilterField(
                name: StoreStockScreen.filterFieldName,
                label: 'Filter stock',
                helperText: 'By part number or description.',
                term: _term,
                onChanged: (term) => setState(() => _term = term),
                shown: matches.length,
                total: state.stock.length,
              ),
              const SizedBox(height: Spacing.lg),
              if (matches.isEmpty)
                PlatformEmptyState.noneMatched(
                  key: StoreStockScreen.noMatchKey,
                  title: 'No parts match',
                  message: 'This store holds stock, but nothing on its shelf matches '
                      '"${_term.trim()}". Try a different part number or description.',
                )
              else
                // One row per part on the shelf, ruled apart from its
                // neighbours (issue #189).
                AppListCard(
                  rows: [for (final level in matches) _StockRow(level: level)],
                ),
            ],
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
