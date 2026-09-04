/// The Asset register: what machines the Platform thinks exist at a Site, and
/// where each one sits.
///
/// Readable by anyone whose role earns the Module, whatever their Grants
/// (#55, ADR-0009's reasoning carried to Maintenance). Adding is offered only
/// to a caller who holds a write Grant somewhere — an action the server would
/// refuse is not offered in the first place.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import '../widgets/skeleton_list.dart';
import 'asset.dart';
import 'asset_form_dialog.dart';
import 'assets_bloc.dart';

class AssetsScreen extends StatelessWidget {
  const AssetsScreen({super.key, required this.canPlaceAnAsset});

  /// Whether this caller holds a write Grant anywhere at all — read off
  /// `/me`'s own `orgUnitScope` (issue #43). False hides the add affordance
  /// entirely; it does not grey it out, because a disabled button is still an
  /// invitation to fail.
  final bool canPlaceAnAsset;

  static const double maxWidth = 900;
  static const ValueKey<String> addKey = ValueKey<String>('assets-add');
  static const ValueKey<String> siteKey = ValueKey<String>('assets-site');
  static const ValueKey<String> noticeKey = ValueKey<String>('assets-notice');
  static const ValueKey<String> retryKey = ValueKey<String>('assets-retry');
  static const ValueKey<String> emptyKey = ValueKey<String>('assets-empty');
  static const ValueKey<String> failedKey = ValueKey<String>('assets-failed');
  static ValueKey<String> rowKey(String id) => ValueKey<String>('asset-row-$id');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AssetsBloc>().state;

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(state: state, canPlaceAnAsset: canPlaceAnAsset),
          if (state is AssetsLoaded && state.notice != null) _Notice(message: state.notice!),
          Expanded(
            child: switch (state) {
              AssetsLoading() => const SkeletonList(rows: 4, maxWidth: maxWidth),
              AssetsUnavailable(message: final message) => _AssetsFailed(message: message),
              AssetsLoaded(isLoadingAssets: true) =>
                const SkeletonList(rows: 4, maxWidth: maxWidth),
              AssetsLoaded(assets: final assets) when assets.isEmpty => const _AssetsEmpty(),
              AssetsLoaded(assets: final assets) => _AssetsList(assets: assets),
            },
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state, required this.canPlaceAnAsset});

  final AssetsState state;
  final bool canPlaceAnAsset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loaded = state is AssetsLoaded ? state as AssetsLoaded : null;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AssetsScreen.maxWidth),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Assets', style: theme.textTheme.headlineSmall),
                        const SizedBox(height: Spacing.xs),
                        Text(
                          'Every machine on the register at this Site, and the Org '
                          'Unit each one sits at.',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  if (canPlaceAnAsset && loaded != null)
                    FilledButton.icon(
                      key: AssetsScreen.addKey,
                      onPressed: loaded.isAdding
                          ? null
                          : () => AssetFormDialog.open(context, siteId: loaded.siteId),
                      icon: const Icon(Icons.add),
                      label: const Text('Add an Asset'),
                    ),
                ],
              ),
              if (loaded != null && loaded.sites.length > 1) ...[
                const SizedBox(height: Spacing.md),
                SizedBox(
                  width: 280,
                  child: DropdownButtonFormField<String>(
                    key: AssetsScreen.siteKey,
                    initialValue: loaded.siteId,
                    isDense: true,
                    decoration: const InputDecoration(labelText: 'Site', border: OutlineInputBorder()),
                    items: [
                      for (final site in loaded.sites)
                        DropdownMenuItem<String>(value: site.id, child: Text(site.name)),
                    ],
                    onChanged: (siteId) {
                      if (siteId == null) return;
                      context.read<AssetsBloc>().add(AssetsSiteSelected(siteId));
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

class _Notice extends StatelessWidget {
  const _Notice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AssetsScreen.maxWidth),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.md),
          child: Container(
            key: AssetsScreen.noticeKey,
            padding: const EdgeInsets.all(Spacing.md),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 20, color: theme.colorScheme.onSecondaryContainer),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(
                    message,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSecondaryContainer),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AssetsList extends StatelessWidget {
  const _AssetsList({required this.assets});

  final List<Asset> assets;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AssetsScreen.maxWidth),
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
          itemCount: assets.length,
          separatorBuilder: (_, _) => const SizedBox(height: Spacing.sm),
          itemBuilder: (context, index) {
            final asset = assets[index];
            return Card(
              key: AssetsScreen.rowKey(asset.id),
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(Spacing.lg),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(asset.name, style: theme.textTheme.titleSmall),
                          const SizedBox(height: Spacing.xxs),
                          Text(
                            '${asset.code} · ${asset.typeLabel}',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    Text(asset.orgUnitName, style: theme.textTheme.bodyMedium),
                    const SizedBox(width: Spacing.lg),
                    Chip(
                      label: Text(asset.criticalityLabel),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AssetsEmpty extends StatelessWidget {
  const _AssetsEmpty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      key: AssetsScreen.emptyKey,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.precision_manufacturing_outlined, size: 48, color: theme.colorScheme.outline),
              const SizedBox(height: Spacing.md),
              Text('No Assets on the register yet', style: theme.textTheme.titleMedium),
              const SizedBox(height: Spacing.sm),
              Text(
                'Nothing has been recorded at this Site. Add a machine and it '
                'can be worked on the same day.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AssetsFailed extends StatelessWidget {
  const _AssetsFailed({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      key: AssetsScreen.failedKey,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined, size: 48, color: theme.colorScheme.outline),
              const SizedBox(height: Spacing.md),
              Text('The register could not be read', style: theme.textTheme.titleMedium),
              const SizedBox(height: Spacing.sm),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: Spacing.md),
              FilledButton.tonal(
                key: AssetsScreen.retryKey,
                onPressed: () => context.read<AssetsBloc>().add(const AssetsStarted()),
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
