/// One store's stock (issue #80): what is on the shelf, and the receive action
/// that adds to it. Readable by anyone whose role earns the Module, whatever
/// their Grants (ADR-0009); receiving is offered only to a caller who holds a
/// write Grant somewhere, because an action the server would refuse is not
/// offered in the first place.
///
/// **A register of four columns, and a list card per part below 700px of
/// content.** At or above [StoreStockScreen.narrowBreakpoint] (at a text scale of
/// 1) the shelf is an `AppTableHeader` band and one `AppTableRow` per part, both
/// built from the one column spec [_columns]: the part number, the description,
/// the quantity (right-aligned, tabular figures, so a column of them compares by
/// eye) and its unit. Below it, the card row this Screen has always had.
///
/// **The way back is a crumb.** A store's stock is reached from the Stores
/// register, so a `Stores ›` crumb above the title takes the reader back to
/// `/stores`; the title that follows it is the store's own name, which is the
/// crumb's last segment. It is not drawn twice because the header already is
/// that name.
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
import '../widgets/app_table.dart';
import '../widgets/app_toolbar.dart';
import '../widgets/disclosing_text.dart';
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

  /// The content width (at a text scale of 1) below which the register gives way
  /// to the card rows, measured by the `LayoutBuilder` in `_LoadedState`, never
  /// the window. Four columns is inside the five-column rule, so this is the
  /// Platform's own [AppBreakpoints.registerTable].
  static const double narrowBreakpoint = AppBreakpoints.registerTable;

  /// The `Stores` crumb above the title: the way back to `/stores`.
  static const ValueKey<String> storesCrumbKey = ValueKey<String>('store-stock-stores-crumb');
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
      level.partNo.toLowerCase().contains(term) || level.description.toLowerCase().contains(term);

  /// The rows actually rendered — every one of them while the term is empty.
  List<StockLevel> get _matchingStock {
    final term = _term.trim().toLowerCase();
    if (term.isEmpty) return widget.state.stock;
    return widget.state.stock.where((level) => _matches(level, term)).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
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
            // The crumb back to the Stores register. A text button laid out to the
            // 44px floor, announced as what it does rather than as a bare word.
            Align(
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    key: StoreStockScreen.storesCrumbKey,
                    onPressed: () => context.go(Routes.stores),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(AppTouchTarget.min, AppTouchTarget.min),
                    ),
                    child: const Text('Stores', semanticsLabel: 'Back to Stores'),
                  ),
                  ExcludeSemantics(
                    child: Icon(
                      Icons.chevron_right,
                      size: Spacing.xl,
                      color: AppColors.of(context).textMuted,
                    ),
                  ),
                ],
              ),
            ),
            AppPageHeader(
              title: state.store.name,
              description: '${state.store.code} · ${state.store.orgUnitName}',
              actions: [
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
              // A toolbar's `Wrap` hands its children unbounded width, which a text
              // field cannot take, so the field is given the box's own width.
              LayoutBuilder(
                builder: (context, box) => AppToolbar(
                  filters: [
                    SizedBox(
                      width: box.maxWidth,
                      child: AppFilterField(
                        name: StoreStockScreen.filterFieldName,
                        label: 'Filter stock',
                        helperText: 'By part number or description.',
                        term: _term,
                        onChanged: (term) => setState(() => _term = term),
                        shown: matches.length,
                        total: state.stock.length,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Spacing.md),
              if (matches.isEmpty)
                PlatformEmptyState.noneMatched(
                  key: StoreStockScreen.noMatchKey,
                  title: 'No parts match',
                  message:
                      'This store holds stock, but nothing on its shelf matches '
                      '"${_term.trim()}". Try a different part number or description.',
                )
              else
                // Measured on the box the list actually got, scaled by the
                // reader's text size (design-language §10).
                LayoutBuilder(
                  builder: (context, constraints) {
                    final narrow =
                        constraints.maxWidth <
                        AppBreakpoints.effective(context, StoreStockScreen.narrowBreakpoint);
                    if (narrow) {
                      // One row per part on the shelf, ruled apart from its
                      // neighbours (issue #189).
                      return AppListCard(
                        rows: [for (final level in matches) _StockRow(level: level)],
                      );
                    }
                    final columns = _columns();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppTableHeader(columns: columns),
                        for (final level in matches) _StockTableRow(columns: columns, level: level),
                      ],
                    );
                  },
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The register's one column spec. The part number is a code and reads quieter
/// than the description it identifies; the quantity is the one number, so it is
/// end-aligned and set in tabular figures. Nobody can tap a stock row, so a row
/// is the 32px of one that holds nothing to press.
List<AppTableColumn> _columns() => const [
  AppTableColumn('Part number', flex: 2),
  AppTableColumn('Description', flex: 5),
  AppTableColumn('Quantity', flex: 1, align: AppColumnAlign.end),
  AppTableColumn('Unit', flex: 1),
];

class _StockTableRow extends StatelessWidget {
  const _StockTableRow({required this.columns, required this.level});

  final List<AppTableColumn> columns;
  final StockLevel level;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final dense = AppTypography.dense(context);
    return KeyedSubtree(
      key: StoreStockScreen.rowKey(level.partId),
      child: AppTableRow(
        columns: columns,
        cells: [
          DisclosingText(level.partNo, style: dense?.copyWith(color: palette.textMuted)),
          DisclosingText(level.description, style: dense?.copyWith(color: palette.textPrimary)),
          Text(
            '${level.quantity}',
            maxLines: 1,
            style: AppTableRow.numberStyle(context)?.copyWith(color: palette.textPrimary),
          ),
          Text(
            level.uomCode,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: dense?.copyWith(color: palette.textMuted),
          ),
        ],
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
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
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
