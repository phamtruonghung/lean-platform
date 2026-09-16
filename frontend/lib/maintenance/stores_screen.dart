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

class _StoresList extends StatelessWidget {
  const _StoresList({required this.stores});

  final List<Store> stores;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: AppPageFrame(
        maxWidth: StoresScreen.maxWidth,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
          children: [
            // One row per Store, ruled apart from its neighbours (issue
            // #189) — the same list card every catalogue now sits in.
            AppListCard(
              rows: [
                for (final store in stores)
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
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
