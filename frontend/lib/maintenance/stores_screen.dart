/// The stores at a Site (issue #80): the shelves that hold parts, each at an
/// Org Unit. Readable by anyone whose role earns the Module, whatever their
/// Grants (ADR-0009's reasoning carried to Maintenance); tapping a store opens
/// its stock.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../platform/router.dart';
import '../theme.dart';
import '../widgets/app_filter_field.dart';
import '../widgets/app_list_card.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import 'store.dart';
import 'stores_bloc.dart';

class StoresScreen extends StatelessWidget {
  const StoresScreen({super.key});

  /// The Platform's own page width (issue #189): this Screen used to declare
  /// 800, one of five numbers six catalogue Screens each picked for themselves.
  static const double maxWidth = AppLayout.pageWidth;
  static const ValueKey<String> siteKey = ValueKey<String>('stores-site');
  static const ValueKey<String> failedKey = ValueKey<String>('stores-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('stores-retry');
  static const ValueKey<String> emptyKey = ValueKey<String>('stores-empty');
  static ValueKey<String> rowKey(String id) => ValueKey<String>('stores-row-$id');

  /// The filter box's `name` (issue #191), seeding [filterFieldKey],
  /// [filterClearKey] and [filterCountKey] — kept in one place so the field's
  /// own name and the keys a test reaches it by cannot drift, the same device
  /// `WorkOrderAssignDialog.searchFieldName` uses (issue #187).
  static const String filterFieldName = 'stores-filter';

  static ValueKey<String> get filterFieldKey => AppFilterField.fieldKey(filterFieldName);
  static ValueKey<String> get filterClearKey => AppFilterField.clearKey(filterFieldName);
  static ValueKey<String> get filterCountKey => AppFilterField.countKey(filterFieldName);

  /// What a term matching none of the Site's stores renders — a different fact
  /// from [emptyKey]: "nothing matched" is not "there is nothing here".
  static const ValueKey<String> noMatchKey = ValueKey<String>('stores-no-match');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<StoresBloc>().state;

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(state: state),
          Expanded(
            child: switch (state) {
              StoresLoading() => const SkeletonList(maxWidth: maxWidth),
              StoresUnavailable(message: final message) => PlatformFailureState(
                  key: StoresScreen.failedKey,
                  title: 'The stores could not be read',
                  message: message,
                  retryKey: StoresScreen.retryKey,
                  onRetry: () => context.read<StoresBloc>().add(const StoresStarted()),
                ),
              StoresLoaded(isLoadingStores: true) => const SkeletonList(maxWidth: maxWidth),
              StoresLoaded(stores: final stores) when stores.isEmpty => const _StoresEmpty(),
              StoresLoaded(stores: final stores) => _StoresList(stores: stores),
            },
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state});

  final StoresState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loaded = state is StoresLoaded ? state as StoresLoaded : null;

    return Center(
      child: AppPageFrame(
        maxWidth: StoresScreen.maxWidth,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Stores', style: theme.textTheme.headlineSmall),
              const SizedBox(height: Spacing.xs),
              Text(
                'The shelves that hold parts at this Site.',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              if (loaded != null && loaded.sites.length > 1) ...[
                const SizedBox(height: Spacing.md),
                SizedBox(
                  width: 280,
                  child: DropdownButtonFormField<String>(
                    key: StoresScreen.siteKey,
                    initialValue: loaded.siteId,
                    isDense: true,
                    decoration: const InputDecoration(labelText: 'Site', border: OutlineInputBorder()),
                    items: [
                      for (final site in loaded.sites)
                        DropdownMenuItem<String>(value: site.id, child: Text(site.name)),
                    ],
                    onChanged: (siteId) {
                      if (siteId == null) return;
                      context.read<StoresBloc>().add(StoresSiteSelected(siteId));
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StoresEmpty extends StatelessWidget {
  const _StoresEmpty();

  @override
  Widget build(BuildContext context) => const Center(
        child: PlatformEmptyState.noneExist(
          key: StoresScreen.emptyKey,
          title: 'No stores yet',
          message: 'Nothing here holds parts.',
          icon: Icons.warehouse_outlined,
        ),
      );
}

/// The list of stores. Stateful only because the filter box's term is the
/// Screen's own (issue #191): a filter is a view of the rows the Bloc already
/// holds, not a state of the domain, so typing costs a `setState` and never a
/// Bloc event — ADR-0012 asks for a Bloc where a Screen drives a state
/// machine, not for one per text field.
class _StoresList extends StatefulWidget {
  const _StoresList({required this.stores});

  final List<Store> stores;

  @override
  State<_StoresList> createState() => _StoresListState();
}

class _StoresListState extends State<_StoresList> {
  /// What the filter box is narrowing the Site's stores to, `''` when nothing
  /// is.
  String _term = '';

  /// Whether [store] matches [term], already lower-cased and trimmed: a
  /// case-insensitive substring over the two fields that identify a store —
  /// its name and its code. No ranking and no fuzzy matching, the same rule
  /// the assign dialog's own filter uses (issue #187).
  static bool _matches(Store store, String term) =>
      store.name.toLowerCase().contains(term) || store.code.toLowerCase().contains(term);

  /// The rows actually rendered — every one of them while the term is empty.
  List<Store> get _matchingStores {
    final term = _term.trim().toLowerCase();
    if (term.isEmpty) return widget.stores;
    return widget.stores.where((store) => _matches(store, term)).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Filtered here, immediately before the row widgets are built, so a term
    // can only ever narrow rows this Screen already read (issue #191).
    final matches = _matchingStores;
    return Center(
      child: AppPageFrame(
        maxWidth: StoresScreen.maxWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Above the rows and at the page's own padding, so the header
            // keeps one rhythm (issue #191).
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
              child: AppFilterField(
                name: StoresScreen.filterFieldName,
                label: 'Filter stores',
                helperText: 'By name or code.',
                term: _term,
                onChanged: (term) => setState(() => _term = term),
                shown: matches.length,
                total: widget.stores.length,
              ),
            ),
            const SizedBox(height: Spacing.md),
            Expanded(
              child: matches.isEmpty
                  ? PlatformEmptyState.noneMatched(
                      key: StoresScreen.noMatchKey,
                      title: 'No stores match',
                      message: 'This Site has stores, but none matches "${_term.trim()}". '
                          'Try a different name or code, or clear the filter.',
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
                      children: [
                        // One row per Store, ruled apart from its neighbours
                        // (issue #189) — the same list card every catalogue now
                        // sits in.
                        AppListCard(
                          rows: [
                            for (final store in matches)
                              ListTile(
                                key: StoresScreen.rowKey(store.id),
                                title: Text(store.name),
                                subtitle: Text('${store.code} · ${store.orgUnitName}'),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => context.go('${Routes.stores}/${store.id}'),
                              ),
                          ],
                        ),
                        const SizedBox(height: Spacing.md),
                        Text(
                          'Tapping a store shows what is on its shelf.',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
