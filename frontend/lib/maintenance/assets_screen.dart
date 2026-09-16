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

import '../status_tone.dart';
import '../theme.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/status_chip.dart';
import 'asset.dart';
import 'asset_form_dialog.dart';
import 'asset_move_dialog.dart';
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
  static const ValueKey<String> showRetiredKey = ValueKey<String>('assets-show-retired');
  static const ValueKey<String> noticeKey = ValueKey<String>('assets-notice');
  static const ValueKey<String> retryKey = ValueKey<String>('assets-retry');
  static const ValueKey<String> emptyKey = ValueKey<String>('assets-empty');
  static const ValueKey<String> failedKey = ValueKey<String>('assets-failed');
  static ValueKey<String> rowKey(String id) => ValueKey<String>('asset-row-$id');
  static ValueKey<String> retiredChipKey(String id) => ValueKey<String>('asset-retired-$id');
  static ValueKey<String> retireKey(String id) => ValueKey<String>('asset-retire-$id');
  static ValueKey<String> reinstateKey(String id) => ValueKey<String>('asset-reinstate-$id');
  static ValueKey<String> nestKey(String id) => ValueKey<String>('asset-nest-$id');
  static ValueKey<String> detachKey(String id) => ValueKey<String>('asset-detach-$id');
  static ValueKey<String> orgUnitKey(String id) => ValueKey<String>('asset-org-unit-$id');
  static ValueKey<String> parentOptionKey(String id) => ValueKey<String>('asset-parent-option-$id');
  static const ValueKey<String> parentChooserKey = ValueKey<String>('asset-parent-chooser');

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
              AssetsLoaded(
                assets: final assets,
                mutatingAssetId: final mutatingAssetId,
                isAdding: final isAdding
              ) =>
                _AssetsList(assets: assets, mutatingAssetId: mutatingAssetId, isAdding: isAdding),
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
      child: AppPageFrame(
        maxWidth: AssetsScreen.maxWidth,
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
              if (loaded != null) ...[
                const SizedBox(height: Spacing.md),
                FilterChip(
                  key: AssetsScreen.showRetiredKey,
                  label: const Text('Show retired'),
                  selected: loaded.showRetired,
                  // Same guard as the row actions below: toggling this while a
                  // mutation is in flight would interleave the re-read with the
                  // mutation's own write and could wipe a pending success
                  // `notice` before the caller ever sees it. Not a new
                  // mechanism — `mutatingAssetId != null || isAdding` is the
                  // one guard, just checked here too.
                  onSelected: loaded.mutatingAssetId != null || loaded.isAdding
                      ? null
                      : (value) => context.read<AssetsBloc>().add(AssetsShowRetiredChanged(value)),
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
      child: AppPageFrame(
        maxWidth: AssetsScreen.maxWidth,
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

/// The flat list the Bloc loaded, arranged into what the register draws:
/// which ids sit at the top, and which sit beneath which parent (issue #61).
///
/// Built once, from [rootIds] and [childIdsByParent] and nothing else — the
/// same uniform shape issue #42 settled on for exactly this reason. An Asset
/// whose `parentId` names a row not present in this list (another Site, or
/// retired and filtered out) is classified a root here, never dropped: a
/// non-null `parentId` is never assumed to resolve.
class _AssetTree {
  factory _AssetTree(List<Asset> assets) {
    final nodesById = {for (final asset in assets) asset.id: asset};
    final childIdsByParent = <String, List<String>>{};
    final rootIds = <String>[];
    for (final asset in assets) {
      final parentId = asset.parentId;
      if (parentId != null && nodesById.containsKey(parentId)) {
        (childIdsByParent[parentId] ??= <String>[]).add(asset.id);
      } else {
        rootIds.add(asset.id);
      }
    }
    return _AssetTree._(nodesById: nodesById, rootIds: rootIds, childIdsByParent: childIdsByParent);
  }

  const _AssetTree._({required this.nodesById, required this.rootIds, required this.childIdsByParent});

  final Map<String, Asset> nodesById;
  final List<String> rootIds;
  final Map<String, List<String>> childIdsByParent;

  /// Every id beneath [id], any depth. Used only to keep the parent chooser
  /// from offering an Asset its own descendant — a courtesy filter, not the
  /// guard: the server refuses a cycle independently.
  Set<String> descendantsOf(String id) {
    final result = <String>{};
    void walk(String parentId) {
      for (final childId in childIdsByParent[parentId] ?? const <String>[]) {
        if (result.add(childId)) walk(childId);
      }
    }

    walk(id);
    return result;
  }

  /// Depth-first from [rootIds] downward through [childIdsByParent] and
  /// nothing else. Sibling order at every level is whatever order the ids
  /// arrived in within their parent's list — a filtered subsequence of the
  /// assets the server already sent in `(orgUnitName, code)` order, so that
  /// ordering survives unchanged.
  ///
  /// The register must render every Asset it was given, full stop — a
  /// display must not silently drop rows because the graph it was handed
  /// disagreed with its assumptions. A well-formed tree reaches every node
  /// from [rootIds] alone, but a cycle does not: every node in it has a
  /// present parent, so the constructor above never classifies any of them a
  /// root, and without the fallback below they would vanish from `rows`
  /// entirely with no empty state shown, since [nodesById] itself is not
  /// empty. The fallback renders anything the walk from [rootIds] never
  /// reached as a flat top-level row instead, so malformed data degrades to
  /// an ungrouped list rather than losing rows outright. The server refuses
  /// to create a cycle, so this only guards against malformed data reaching
  /// the client some other way — and doubles as loop protection for the walk
  /// itself, which would otherwise recurse forever around the cycle.
  List<(Asset, int)> get rows {
    final result = <(Asset, int)>[];
    final reached = <String>{};
    void walk(List<String> ids, int depth) {
      for (final id in ids) {
        if (!reached.add(id)) continue;
        final asset = nodesById[id];
        if (asset == null) continue;
        result.add((asset, depth));
        final children = childIdsByParent[id];
        if (children != null) walk(children, depth + 1);
      }
    }

    walk(rootIds, 0);
    for (final id in nodesById.keys) {
      walk([id], 0);
    }
    return result;
  }
}

class _AssetsList extends StatelessWidget {
  const _AssetsList({required this.assets, required this.mutatingAssetId, required this.isAdding});

  final List<Asset> assets;
  final String? mutatingAssetId;

  /// An add is in flight — a row's own actions are gated on this alongside
  /// [mutatingAssetId], the same as the "Add an Asset" button and the "Show
  /// retired" chip.
  final bool isAdding;

  @override
  Widget build(BuildContext context) {
    final tree = _AssetTree(assets);
    final rows = tree.rows;
    // Every row's actions are disabled by any mutation in flight, not only
    // the row it belongs to — a second row's confirm-then-dispatch would
    // otherwise reach the Bloc while the first is still mid-write and be
    // silently reported as dropped rather than ever executed.
    final disabled = mutatingAssetId != null || isAdding;
    return Center(
      child: AppPageFrame(
        maxWidth: AssetsScreen.maxWidth,
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
          itemCount: rows.length,
          separatorBuilder: (_, _) => const SizedBox(height: Spacing.sm),
          itemBuilder: (context, index) {
            final (asset, depth) = rows[index];
            return _AssetRow(
              asset: asset,
              depth: depth,
              tree: tree,
              disabled: disabled,
            );
          },
        ),
      ),
    );
  }
}

class _AssetRow extends StatelessWidget {
  const _AssetRow({
    required this.asset,
    required this.depth,
    required this.tree,
    required this.disabled,
  });

  final Asset asset;
  final int depth;
  final _AssetTree tree;

  /// Whether this row's actions are tappable at all: true whenever any
  /// mutation — this row's own or another's — or an add is in flight. Not
  /// only the row a mutation is running for: another row's confirm-then
  /// -dispatch must not be able to reach the Bloc while a different write is
  /// still in progress.
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(left: depth * Spacing.xl),
      child: Card(
        key: AssetsScreen.rowKey(asset.id),
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(Spacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                asset.name,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  // A retired Asset must read as retired at a
                                  // glance, not only through the chip beside
                                  // it — a strikethrough survives even where
                                  // the chip has scrolled out of view.
                                  decoration: asset.isActive ? null : TextDecoration.lineThrough,
                                  color: asset.isActive
                                      ? null
                                      : theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            if (!asset.isActive) ...[
                              const SizedBox(width: Spacing.sm),
                              StatusChip(key: AssetsScreen.retiredChipKey(asset.id), label: 'Retired', tone: StatusTone.neutral),
                            ],
                          ],
                        ),
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
              const SizedBox(height: Spacing.sm),
              // A `Wrap` rather than a `Row` since issue #171: three actions
              // are wide enough to overflow at the narrowest window the Shell
              // allows, and a second line of buttons is honest where a clipped
              // one is not. With one or two actions the layout is unchanged.
              Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.sm,
                children: [
                  OutlinedButton(
                    key: asset.isActive
                        ? AssetsScreen.retireKey(asset.id)
                        : AssetsScreen.reinstateKey(asset.id),
                    onPressed: disabled ? null : () => _toggleActive(context, asset),
                    child: Text(asset.isActive ? 'Retire' : 'Reinstate'),
                  ),
                  // Labelled for what it changes, not "Move": the register
                  // already reads "move" as Nest under…/Detach, which moves an
                  // Asset in the tree rather than across Org Units.
                  OutlinedButton(
                    key: AssetsScreen.orgUnitKey(asset.id),
                    onPressed: disabled ? null : () => AssetMoveDialog.open(context, asset: asset),
                    child: const Text('Change Org Unit…'),
                  ),
                  if (asset.parentId != null)
                    OutlinedButton(
                      key: AssetsScreen.detachKey(asset.id),
                      onPressed: disabled
                          ? null
                          : () => context
                              .read<AssetsBloc>()
                              .add(AssetParentChanged(assetId: asset.id, parentId: null)),
                      child: const Text('Detach'),
                    )
                  else
                    OutlinedButton(
                      key: AssetsScreen.nestKey(asset.id),
                      onPressed: disabled ? null : () => _openParentChooser(context, tree, asset),
                      child: const Text('Nest under…'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks first before retiring, the same shape `_toggleActive` in
/// `accounts_screen.dart` uses for deactivating: nothing is deleted, and the
/// server itself still refuses this independently for an Asset with active
/// parts still fitted (409). Reinstating is not asked about — it takes
/// nothing away.
Future<void> _toggleActive(BuildContext context, Asset asset) async {
  final bloc = context.read<AssetsBloc>();
  if (!asset.isActive) {
    bloc.add(AssetActiveToggled(assetId: asset.id, isActive: true));
    return;
  }
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Retire this Asset?'),
      content: Text(
        '${asset.name} will no longer appear on the active register. Nothing '
        'is deleted, and it can be reinstated at any time.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Retire'),
        ),
      ],
    ),
  );
  if (confirmed ?? false) {
    bloc.add(AssetActiveToggled(assetId: asset.id, isActive: false));
  }
}

/// Offers every active Asset already loaded for this Site as a parent, apart
/// from the obviously impossible: the Asset itself, and whatever sits beneath
/// it already. A retired Asset is excluded too — the server rejects nesting
/// under one with 409, so offering it here would only earn the caller a
/// refusal after they had already chosen it. All three are courtesy filters;
/// the server still refuses a self-parent, a cycle, or a retired parent
/// independently.
Future<void> _openParentChooser(BuildContext context, _AssetTree tree, Asset asset) async {
  final bloc = context.read<AssetsBloc>();
  final excluded = {asset.id, ...tree.descendantsOf(asset.id)};
  final candidates = [
    for (final id in tree.nodesById.keys)
      if (!excluded.contains(id) && tree.nodesById[id]!.isActive) tree.nodesById[id]!,
  ];
  final chosenId = await showDialog<String>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      key: AssetsScreen.parentChooserKey,
      title: const Text('Nest under…'),
      children: [
        if (candidates.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: Spacing.lg),
            child: Text('There is nothing else on this register it could sit beneath.'),
          ),
        for (final candidate in candidates)
          SimpleDialogOption(
            key: AssetsScreen.parentOptionKey(candidate.id),
            onPressed: () => Navigator.of(dialogContext).pop(candidate.id),
            child: Text('${candidate.name} (${candidate.code})'),
          ),
      ],
    ),
  );
  if (chosenId != null) {
    bloc.add(AssetParentChanged(assetId: asset.id, parentId: chosenId));
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
