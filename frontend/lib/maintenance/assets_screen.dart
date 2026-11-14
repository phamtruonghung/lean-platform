/// The Asset register: what machines the Platform thinks exist at a Site, and
/// where each one sits.
///
/// Readable by anyone whose role earns the Module, whatever their Grants
/// (#55, ADR-0009's reasoning carried to Maintenance). Adding is offered only
/// to a caller who holds a write Grant somewhere — an action the server would
/// refuse is not offered in the first place.
///
/// **A register of the tree, and a card per Asset below 700px of content.** At
/// or above [AssetsScreen.narrowBreakpoint] (at a text scale of 1) the Assets
/// are an `AppTableHeader` band and one `AppTableRow` per Asset, both built from
/// the one column spec [_columns]; the tree is the first cell's indent
/// (`depth * Spacing.xl`) and the band's first label stays at depth 0. Below it,
/// one card per Asset, as before. Never horizontal scroll.
///
/// **A register row offers one act inline and keeps the rest in a kebab.** A row
/// with four buttons is four lines tall, and density is what the register is
/// for, so Retire (or Reinstate) stays inline, as the next *status* change, and
/// Correct details…, Change Org Unit… and Nest under…/Detach go in the overflow
/// beside it, the shape `WorkOrdersScreen`'s rows settled. The card has the room
/// and keeps all of them inline.
///
/// There are two toolbars, for a reason: the Site and "Show retired" live in
/// the header's `AppToolbar`, because they must stay reachable when the register
/// is empty and `_AssetsList` does not exist then; the filter box lives in a
/// second `AppToolbar` inside `_AssetsList`, immediately above the rows, because
/// its term is that widget's own state and it only means something with rows.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/app_localizations.dart';
import '../l10n/notices.dart';
import '../status_tone.dart';
import '../theme.dart';
import '../widgets/app_confirm_dialog.dart';
import '../widgets/app_dialog.dart';
import '../widgets/app_filter_field.dart';
import '../widgets/empty_state.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/app_page_header.dart';
import '../widgets/app_table.dart';
import '../widgets/app_toolbar.dart';
import '../widgets/disclosing_text.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/status_chip.dart';
import 'asset.dart';
import 'asset_form_dialog.dart';
import 'asset_move_dialog.dart';
import 'assets_bloc.dart';
import 'name_with_chip.dart';

class AssetsScreen extends StatelessWidget {
  const AssetsScreen({super.key, required this.canPlaceAnAsset, required this.canCorrectAsset});

  /// Whether this caller holds a write Grant anywhere at all — read off
  /// `/me`'s own `orgUnitScope` (issue #43). False hides the add affordance
  /// entirely; it does not grey it out, because a disabled button is still an
  /// invitation to fail.
  final bool canPlaceAnAsset;

  /// Whether this caller holds a write Grant *reaching the Org Unit a given
  /// Asset sits at* (issue #173) — read off `/me`'s own `orgUnitScope`
  /// (issue #43), the same `OrgUnitScope.canWriteAt` mechanism
  /// `canAssignWorkOrder` already uses on `WorkOrdersScreen`. A predicate,
  /// not a bool, because the answer is per-row: a write Grant on one line
  /// says nothing about an Asset on another. Unlike this register's other
  /// row actions (Retire, Change Org Unit…, Nest under…/Detach, which are
  /// always offered and rely on the server's own 403), the correction
  /// affordance is absent outright for a caller this check refuses — issue
  /// #173's own Testing Decisions ask for no such action to be offered at
  /// all, not merely a disabled one.
  final bool Function(String orgUnitId) canCorrectAsset;

  static const double maxWidth = 900;

  /// The content width (at a text scale of 1) below which the register gives way
  /// to one card per Asset, measured by `_AssetsList`'s `LayoutBuilder` and not
  /// the window: that box is the Screen's own content, before the page padding
  /// and the row's. It is [AppBreakpoints.registerTable] (700), the Platform's
  /// number for a register of five columns. At 700 the cells have about 640px:
  /// the Actions column is one button and the kebab (about 170) and Criticality
  /// about 90, which leaves about 380 for Name, Code · Type and Org Unit at 3:3:2,
  /// enough for a name and a code to read and for `DisclosingText` to disclose
  /// the rest.
  static const double narrowBreakpoint = AppBreakpoints.registerTable;
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

  /// The overflow trigger for one register row (the Work order row's shape): a
  /// kebab holding Correct details…, Change Org Unit… and Nest under…/Detach, each
  /// under the key its inline button carries in the card. Its own `onPressed` is
  /// null while any mutation is in flight, so "no act is offered while one is
  /// running" is proved by reading it. Present in the register only; the card
  /// keeps every act inline.
  static ValueKey<String> rowActionsKey(String id) => ValueKey<String>('asset-actions-$id');
  static ValueKey<String> correctKey(String id) => ValueKey<String>('asset-correct-$id');
  static ValueKey<String> nestKey(String id) => ValueKey<String>('asset-nest-$id');
  static ValueKey<String> detachKey(String id) => ValueKey<String>('asset-detach-$id');
  static ValueKey<String> orgUnitKey(String id) => ValueKey<String>('asset-org-unit-$id');
  static ValueKey<String> parentOptionKey(String id) => ValueKey<String>('asset-parent-option-$id');
  static const ValueKey<String> parentChooserKey = ValueKey<String>('asset-parent-chooser');

  /// The filter box's `name` (issue #191), seeding [filterFieldKey],
  /// [filterClearKey] and [filterCountKey] — kept in one place so the field's
  /// own name and the keys a test reaches it by cannot drift, the same device
  /// `WorkOrderAssignDialog.searchFieldName` uses (issue #187).
  static const String filterFieldName = 'assets-filter';

  static ValueKey<String> get filterFieldKey => AppFilterField.fieldKey(filterFieldName);
  static ValueKey<String> get filterClearKey => AppFilterField.clearKey(filterFieldName);
  static ValueKey<String> get filterCountKey => AppFilterField.countKey(filterFieldName);

  /// What a term matching none of this Site's Assets renders — a different fact
  /// from [emptyKey]: "nothing matched" is not "there is nothing here".
  static const ValueKey<String> noMatchKey = ValueKey<String>('assets-no-match');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<AssetsBloc>().state;

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(state: state, canPlaceAnAsset: canPlaceAnAsset),
          if (state is AssetsLoaded && state.notice != null) _Notice(message: noticeText(l10n, state.notice!)),
          Expanded(
            child: switch (state) {
              AssetsLoading() => const SkeletonList(rows: 4, maxWidth: maxWidth),
              AssetsUnavailable(message: final message) => PlatformFailureState(
                key: AssetsScreen.failedKey,
                title: l10n.assetsTheRegisterCouldNotBeRead,
                message: message,
                retryKey: AssetsScreen.retryKey,
                onRetry: () => context.read<AssetsBloc>().add(const AssetsStarted()),
              ),
              AssetsLoaded(isLoadingAssets: true) => const SkeletonList(
                rows: 4,
                maxWidth: maxWidth,
              ),
              AssetsLoaded(assets: final assets) when assets.isEmpty =>
                PlatformEmptyState.noneExist(
                  key: AssetsScreen.emptyKey,
                  title: l10n.assetsNoAssetsOnTheRegisterYet,
                  message: l10n.assetsNothingHasBeenRecordedAtThisSite,
                  icon: Icons.precision_manufacturing_outlined,
                ),
              AssetsLoaded(
                assets: final assets,
                mutatingAssetId: final mutatingAssetId,
                isAdding: final isAdding,
              ) =>
                _AssetsList(
                  assets: assets,
                  mutatingAssetId: mutatingAssetId,
                  isAdding: isAdding,
                  canCorrectAsset: canCorrectAsset,
                ),
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
    final l10n = AppLocalizations.of(context);
    final loaded = state is AssetsLoaded ? state as AssetsLoaded : null;

    return Center(
      child: AppPageFrame(
        maxWidth: AssetsScreen.maxWidth,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.lg),
          child: AppPageHeader(
            title: l10n.navAssets,
            description:
                l10n.assetsEveryMachineOnTheRegisterAtThis,
            actions: [
              if (canPlaceAnAsset && loaded != null)
                FilledButton.icon(
                  key: AssetsScreen.addKey,
                  onPressed: loaded.isAdding
                      ? null
                      : () => AssetFormDialog.open(context, siteId: loaded.siteId),
                  icon: const Icon(Icons.add),
                  label: Text(l10n.commonAddAnAsset),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(AppTouchTarget.min, AppTouchTarget.min),
                  ),
                ),
            ],
            // The Site and the "Show retired" toggle in one toolbar
            // (design-language §5): both narrow what the register lists.
            below: loaded == null
                ? null
                : AppToolbar(
                    filters: [
                      if (loaded.sites.length > 1)
                        SizedBox(
                          width: 280,
                          child: DropdownButtonFormField<String>(
                            key: AssetsScreen.siteKey,
                            initialValue: loaded.siteId,
                            isDense: true,
                            decoration: InputDecoration(
                              labelText: l10n.commonSite,
                              border: OutlineInputBorder(),
                            ),
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
                      FilterChip(
                        key: AssetsScreen.showRetiredKey,
                        label: Text(l10n.assetsShowRetired),
                        selected: loaded.showRetired,
                        // Same guard as the row actions below: toggling this while a
                        // mutation is in flight would interleave the re-read with the
                        // mutation's own write and could wipe a pending success
                        // `notice` before the caller ever sees it. Not a new
                        // mechanism — `mutatingAssetId != null || isAdding` is the
                        // one guard, just checked here too.
                        onSelected: loaded.mutatingAssetId != null || loaded.isAdding
                            ? null
                            : (value) =>
                                  context.read<AssetsBloc>().add(AssetsShowRetiredChanged(value)),
                      ),
                    ],
                  ),
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
                    style: AppTypography.dense(context)
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

  const _AssetTree._({
    required this.nodesById,
    required this.rootIds,
    required this.childIdsByParent,
  });

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

/// The Asset register's list. Stateful only because the filter box's term is
/// the Screen's own (issue #191): a filter is a view of the rows the Bloc
/// already holds, not a state of the domain, so typing costs a `setState` and
/// never a Bloc event — ADR-0012 asks for a Bloc where a Screen drives a
/// state machine, not for one per text field.
class _AssetsList extends StatefulWidget {
  const _AssetsList({
    required this.assets,
    required this.mutatingAssetId,
    required this.isAdding,
    required this.canCorrectAsset,
  });

  final List<Asset> assets;
  final String? mutatingAssetId;

  /// An add is in flight — a row's own actions are gated on this alongside
  /// [mutatingAssetId], the same as the "Add an Asset" button and the "Show
  /// retired" chip.
  final bool isAdding;

  final bool Function(String orgUnitId) canCorrectAsset;

  @override
  State<_AssetsList> createState() => _AssetsListState();
}

class _AssetsListState extends State<_AssetsList> {
  /// What the filter box is narrowing the register to, `''` when nothing is.
  String _term = '';

  /// Whether [asset] matches [term], already lower-cased and trimmed: a
  /// case-insensitive substring over the two fields that identify an Asset —
  /// its name and its code, which is how a technician standing at the machine
  /// names it (issue #191, user story 2). No ranking and no fuzzy matching,
  /// the same rule the assign dialog's own filter uses (issue #187).
  static bool _matches(Asset asset, String term) =>
      asset.name.toLowerCase().contains(term) || asset.code.toLowerCase().contains(term);

  /// The rows actually rendered — every one of them while the term is empty.
  List<Asset> get _matchingAssets {
    final term = _term.trim().toLowerCase();
    if (term.isEmpty) return widget.assets;
    return widget.assets.where((asset) => _matches(asset, term)).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Filtered here, immediately before the rows are built, and the tree is
    // built from the *matches*: `_AssetTree` treats an Asset whose parent is
    // absent as a root, so a machine found at any depth still renders with
    // whatever nesting it can still show, and never disappears because its
    // parent's name did not match (issue #191).
    final matches = _matchingAssets;
    final tree = _AssetTree(matches);
    final rows = tree.rows;
    // Every row's actions are disabled by any mutation in flight, not only
    // the row it belongs to — a second row's confirm-then-dispatch would
    // otherwise reach the Bloc while the first is still mid-write and be
    // silently reported as dropped rather than ever executed.
    final disabled = widget.mutatingAssetId != null || widget.isAdding;
    // The box this Screen actually got from its own parent, scaled by the
    // reader's text size (design-language §10) — never the window.
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow =
            constraints.maxWidth < AppBreakpoints.effective(context, AssetsScreen.narrowBreakpoint);
        final columns = _columns(context);
        return Center(
          child: AppPageFrame(
            maxWidth: AssetsScreen.maxWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
                  // A `Wrap` inside the toolbar hands its children unbounded width, which
                  // a text field cannot take, so the field is given the box's own width.
                  child: LayoutBuilder(
                    builder: (context, box) => AppToolbar(
                      filters: [
                        SizedBox(
                          width: box.maxWidth,
                          child: AppFilterField(
                            name: AssetsScreen.filterFieldName,
                            label: l10n.assetsFilterAssets,
                            helperText: l10n.jobRolesByNameOrCode,
                            term: _term,
                            onChanged: (term) => setState(() => _term = term),
                            shown: matches.length,
                            total: widget.assets.length,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                Expanded(
                  child: matches.isEmpty
                      ? PlatformEmptyState.noneMatched(
                          key: AssetsScreen.noMatchKey,
                          title: l10n.assetsNoAssetsMatch,
                          message:
                              l10n.assetsThisSiteHasAssetsOnTheRegister(_term.trim()),
                        )
                      : narrow
                      ? ListView.separated(
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
                              canCorrectAsset: widget.canCorrectAsset,
                            );
                          },
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
                          children: [
                            AppTableHeader(columns: columns),
                            for (final (asset, depth) in rows)
                              _AssetTableRow(
                                columns: columns,
                                asset: asset,
                                depth: depth,
                                tree: tree,
                                disabled: disabled,
                                canCorrectAsset: widget.canCorrectAsset,
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The Actions column's measured width: the wider of the two inline labels
/// ("Reinstate" is wider than "Retire") in the button's label style at the
/// reader's text scale, the button's own horizontal padding either side
/// (`Spacing.xl`), the gap, the kebab at [AppTouchTarget.min], and the slot's
/// `Spacing.sm` gutter. It is a column of [_columns], so the band's label and
/// every row's actions share it by construction.
double _actionsColumnWidth(BuildContext context) {
  final painter = TextPainter(
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  );
  var widest = 0.0;
  for (final label in const ['Retire', 'Reinstate']) {
    painter.text = TextSpan(text: label, style: Theme.of(context).textTheme.labelLarge);
    painter.layout();
    if (painter.width > widest) widest = painter.width;
  }
  return widest + 2 * Spacing.xl + Spacing.sm + AppTouchTarget.min + Spacing.sm;
}

/// The Criticality column's measured width: the widest of the four labels in a
/// compact `Chip`'s own label style at the reader's text scale, plus the chip's
/// padding and the slot's `Spacing.sm` gutter.
double _criticalityColumnWidth(BuildContext context) {
  final painter = TextPainter(
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  );
  var widest = 0.0;
  for (final level in Criticality.values) {
    painter.text = TextSpan(text: level.label, style: Theme.of(context).textTheme.labelLarge);
    painter.layout();
    if (painter.width > widest) widest = painter.width;
  }
  // The chip's own horizontal padding and label padding (`Spacing.xxl`), then
  // the slot's gutter.
  return widest + Spacing.xxl + Spacing.sm;
}

/// The register's one column spec. [AppTableHeader] and every [AppTableRow] are
/// built from this list, so a header label and its cells start at the same x.
List<AppTableColumn> _columns(BuildContext context) => [
  AppTableColumn(AppLocalizations.of(context).commonName, flex: 3),
  AppTableColumn(AppLocalizations.of(context).assetsCodeType, flex: 3),
  AppTableColumn(AppLocalizations.of(context).commonOrgUnit, flex: 2),
  AppTableColumn(AppLocalizations.of(context).commonCriticality, width: _criticalityColumnWidth(context)),
  AppTableColumn(AppLocalizations.of(context).groupActions, width: _actionsColumnWidth(context), align: AppColumnAlign.end),
];

/// The card's inner width (at a text scale of 1) below which the Org Unit and
/// the criticality wrap under the name instead of sitting beside it. Measured
/// on the card's own box, so a deep row in the tree, which loses `depth *
/// Spacing.xl` to its indent, wraps sooner.
const double _cardMetaBesideName = 400;

class _AssetRow extends StatelessWidget {
  const _AssetRow({
    required this.asset,
    required this.depth,
    required this.tree,
    required this.disabled,
    required this.canCorrectAsset,
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

  final bool Function(String orgUnitId) canCorrectAsset;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
              // The Org Unit and the criticality sit beside the name while the
              // box can hold them, and wrap under it when it cannot: scaled by
              // the reader's text size, because the name grows with the text and
              // the box does not (design-language §10). A `Row` here overflowed
              // at 2x text in a phone-width box.
              LayoutBuilder(
                builder: (context, box) {
                  final meta = [
                    Text(asset.orgUnitName, style: AppTypography.dense(context)),
                    Chip(label: Text(asset.criticalityLabel), visualDensity: VisualDensity.compact),
                  ];
                  final info = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              asset.name,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.dense(context)?.copyWith(
                                fontWeight: FontWeight.w500,
                                // A retired Asset must read as retired at a
                                // glance, not only through the chip beside
                                // it — a strikethrough survives even where
                                // the chip has scrolled out of view.
                                decoration: asset.isActive ? null : TextDecoration.lineThrough,
                                color: asset.isActive ? null : AppColors.of(context).textMuted,
                              ),
                            ),
                          ),
                          if (!asset.isActive) ...[
                            const SizedBox(width: Spacing.sm),
                            StatusChip(
                              key: AssetsScreen.retiredChipKey(asset.id),
                              label: l10n.orgUnitsRetired,
                              tone: StatusTone.neutral,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: Spacing.xxs),
                      Text(
                        '${asset.code} · ${asset.typeLabel}',
                        style: AppTypography.floor(context)
                            ?.copyWith(color: AppColors.of(context).textMuted),
                      ),
                    ],
                  );
                  if (box.maxWidth < AppBreakpoints.effective(context, _cardMetaBesideName)) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        info,
                        const SizedBox(height: Spacing.sm),
                        Wrap(
                          spacing: Spacing.lg,
                          runSpacing: Spacing.xs,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: meta,
                        ),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: info),
                      meta[0],
                      const SizedBox(width: Spacing.lg),
                      meta[1],
                    ],
                  );
                },
              ),
              const SizedBox(height: Spacing.sm),
              _AssetActions(
                asset: asset,
                tree: tree,
                disabled: disabled,
                canCorrectAsset: canCorrectAsset,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One Asset's actions as inline buttons, for the card: it has the room, and the
/// register row offers the same acts through [_AssetRowActions] under the same
/// keys and enable conditions.
///
/// A `Wrap` rather than a `Row` since issue #171: up to four actions are wide
/// enough to overflow the narrowest box, and a second line of buttons is honest
/// where a clipped one is not. Each is [AppTouchTarget.min] tall.
class _AssetActions extends StatelessWidget {
  const _AssetActions({
    required this.asset,
    required this.tree,
    required this.disabled,
    required this.canCorrectAsset,
  });

  final Asset asset;
  final _AssetTree tree;
  final bool disabled;
  final bool Function(String orgUnitId) canCorrectAsset;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    const size = Size(AppTouchTarget.min, AppTouchTarget.min);
    final style = OutlinedButton.styleFrom(minimumSize: size);
    return Wrap(
      spacing: Spacing.sm,
      runSpacing: Spacing.sm,
      children: [
        OutlinedButton(
          key: asset.isActive
              ? AssetsScreen.retireKey(asset.id)
              : AssetsScreen.reinstateKey(asset.id),
          onPressed: disabled ? null : () => _toggleActive(context, asset),
          style: style,
          child: Text(asset.isActive ? l10n.orgUnitsRetire : l10n.commonReinstate),
        ),
        // Absent outright for a caller without a write Grant reaching this
        // Asset's Org Unit (issue #173) — unlike every other action on this
        // row, which is offered unconditionally and relies on the server's own
        // 403.
        if (canCorrectAsset(asset.orgUnitId))
          OutlinedButton(
            key: AssetsScreen.correctKey(asset.id),
            onPressed: disabled ? null : () => AssetFormDialog.open(context, asset: asset),
            style: style,
            child: Text(l10n.assetsCorrectDetails),
          ),
        // Labelled for what it changes, not "Move": the register already reads
        // "move" as Nest under…/Detach, which moves an Asset in the tree rather
        // than across Org Units.
        OutlinedButton(
          key: AssetsScreen.orgUnitKey(asset.id),
          onPressed: disabled ? null : () => AssetMoveDialog.open(context, asset: asset),
          style: style,
          child: Text(l10n.assetsChangeOrgUnit),
        ),
        if (asset.parentId != null)
          OutlinedButton(
            key: AssetsScreen.detachKey(asset.id),
            onPressed: disabled
                ? null
                : () => context.read<AssetsBloc>().add(
                    AssetParentChanged(assetId: asset.id, parentId: null),
                  ),
            style: style,
            child: Text(l10n.assetsDetach),
          )
        else
          OutlinedButton(
            key: AssetsScreen.nestKey(asset.id),
            onPressed: disabled ? null : () => _openParentChooser(context, tree, asset),
            style: style,
            child: Text(l10n.assetsNestUnder),
          ),
      ],
    );
  }
}

/// One Asset's actions in a register row: Retire (or Reinstate) inline, and the
/// rest in a kebab — the shape of `WorkOrdersScreen`'s `_RowActions`, for the
/// same reason: a row is 52px (a 44px control and `Spacing.xs` above and below)
/// only when it holds one line of controls.
///
/// The overflow is opened with [showMenu] from an `IconButton`, not a
/// `PopupMenuButton`, so its `onPressed` is a real field a test can read:
/// [disabled] makes it null, exactly as it disables Retire. Correct details… is
/// absent from the menu, not disabled, for a caller [canCorrectAsset] refuses.
class _AssetRowActions extends StatelessWidget {
  const _AssetRowActions({
    required this.asset,
    required this.tree,
    required this.disabled,
    required this.canCorrectAsset,
  });

  final Asset asset;
  final _AssetTree tree;
  final bool disabled;
  final bool Function(String orgUnitId) canCorrectAsset;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    const size = Size(AppTouchTarget.min, AppTouchTarget.min);
    final items = <(Key, String, VoidCallback)>[
      if (canCorrectAsset(asset.orgUnitId))
        (
          AssetsScreen.correctKey(asset.id),
          'Correct details…',
          () => AssetFormDialog.open(context, asset: asset),
        ),
      (
        AssetsScreen.orgUnitKey(asset.id),
        'Change Org Unit…',
        () => AssetMoveDialog.open(context, asset: asset),
      ),
      if (asset.parentId != null)
        (
          AssetsScreen.detachKey(asset.id),
          'Detach',
          () =>
              context.read<AssetsBloc>().add(AssetParentChanged(assetId: asset.id, parentId: null)),
        )
      else
        (
          AssetsScreen.nestKey(asset.id),
          'Nest under…',
          () => _openParentChooser(context, tree, asset),
        ),
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OutlinedButton(
          key: asset.isActive
              ? AssetsScreen.retireKey(asset.id)
              : AssetsScreen.reinstateKey(asset.id),
          onPressed: disabled ? null : () => _toggleActive(context, asset),
          style: OutlinedButton.styleFrom(minimumSize: size),
          child: Text(asset.isActive ? l10n.orgUnitsRetire : l10n.commonReinstate),
        ),
        const SizedBox(width: Spacing.sm),
        Builder(
          builder: (buttonContext) => IconButton(
            key: AssetsScreen.rowActionsKey(asset.id),
            tooltip: l10n.commonMoreActions,
            icon: const Icon(Icons.more_vert),
            style: IconButton.styleFrom(minimumSize: size),
            onPressed: disabled ? null : () => _openMenu(buttonContext, items),
          ),
        ),
      ],
    );
  }

  Future<void> _openMenu(BuildContext context, List<(Key, String, VoidCallback)> items) async {
    final button = context.findRenderObject() as RenderBox;
    final overlay = Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
    final selected = await showMenu<Key>(
      context: context,
      position: position,
      items: [
        for (final (key, label, _) in items)
          PopupMenuItem<Key>(key: key, value: key, child: Text(label)),
      ],
    );
    if (selected == null) return;
    for (final (key, _, run) in items) {
      if (key == selected) {
        run();
        return;
      }
    }
  }
}

/// One Asset as a row of the register. The tree is drawn by the first cell's
/// indent (`depth * Spacing.xl`) — the band's own first label stays at depth 0 —
/// and a retired Asset reads as retired twice: a line through its name and a
/// `StatusChip`, so it still reads where the chip has been clipped away.
class _AssetTableRow extends StatelessWidget {
  const _AssetTableRow({
    required this.columns,
    required this.asset,
    required this.depth,
    required this.tree,
    required this.disabled,
    required this.canCorrectAsset,
  });

  final List<AppTableColumn> columns;
  final Asset asset;
  final int depth;
  final _AssetTree tree;
  final bool disabled;
  final bool Function(String orgUnitId) canCorrectAsset;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = AppColors.of(context);
    final dense = AppTypography.dense(context);
    final muted = dense?.copyWith(color: palette.textMuted);
    // The framework's padded tap target is lifted on the chip and the buttons:
    // each button states its own 44 through `minimumSize`, and the padded target
    // would add height to the row.
    Widget shrinkWrapTargets(Widget child) => Theme(
      data: Theme.of(context).copyWith(materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
      child: child,
    );

    return KeyedSubtree(
      key: AssetsScreen.rowKey(asset.id),
      child: AppTableRow(
        columns: columns,
        cells: [
          Padding(
            padding: EdgeInsets.only(left: depth * Spacing.xl),
            child: NameWithChip(
              name: DisclosingText(
                asset.name,
                style: dense?.copyWith(
                  color: asset.isActive ? palette.textPrimary : palette.textMuted,
                  decoration: asset.isActive ? null : TextDecoration.lineThrough,
                ),
              ),
              chipLabel: 'Retired',
              chip: asset.isActive
                  ? null
                  : shrinkWrapTargets(
                      StatusChip(
                        key: AssetsScreen.retiredChipKey(asset.id),
                        label: l10n.orgUnitsRetired,
                        tone: StatusTone.neutral,
                      ),
                    ),
            ),
          ),
          DisclosingText('${asset.code} · ${asset.typeLabel}', style: muted),
          DisclosingText(asset.orgUnitName, style: muted),
          shrinkWrapTargets(
            Chip(label: Text(asset.criticalityLabel), visualDensity: VisualDensity.compact),
          ),
          shrinkWrapTargets(
            _AssetRowActions(
              asset: asset,
              tree: tree,
              disabled: disabled,
              canCorrectAsset: canCorrectAsset,
            ),
          ),
        ],
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
  final l10n = AppLocalizations.of(context);
  final bloc = context.read<AssetsBloc>();
  if (!asset.isActive) {
    bloc.add(AssetActiveToggled(assetId: asset.id, isActive: true));
    return;
  }
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AppConfirmDialog(
      title: l10n.assetsRetireThisAsset,
      description:
          l10n.assetsWillNoLongerAppearOnTheActive(asset.name),
      confirmLabel: l10n.orgUnitsRetire,
      dismissLabel: 'Cancel',
      onDismiss: () => Navigator.of(dialogContext).pop(false),
      onConfirm: () => Navigator.of(dialogContext).pop(true),
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
  final l10n = AppLocalizations.of(context);
  final bloc = context.read<AssetsBloc>();
  final excluded = {asset.id, ...tree.descendantsOf(asset.id)};
  final candidates = [
    for (final id in tree.nodesById.keys)
      if (!excluded.contains(id) && tree.nodesById[id]!.isActive) tree.nodesById[id]!,
  ];
  final chosenId = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AppDialog(
      key: AssetsScreen.parentChooserKey,
      title: l10n.assetsNestUnder,
      // A picker (460): one Asset to choose from a list. It stays a bare
      // `showDialog` that returns the id, dismissed by its Cancel, Esc or the
      // barrier exactly as the `SimpleDialog` it replaces was.
      size: AppDialogSize.picker,
      actions: [
        AppDialogAction(
          id: 'asset-parent-chooser-cancel',
          label: l10n.commonCancel,
          kind: AppDialogActionKind.dismiss,
          onPressed: () => Navigator.of(dialogContext).pop(),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (candidates.isEmpty)
            Text(
              l10n.assetsThereIsNothingElseOnThisRegister,
              style: AppTypography.dense(dialogContext)
                  ?.copyWith(color: AppColors.of(dialogContext).textPrimary),
            ),
          for (final candidate in candidates)
            _ParentOption(
              key: AssetsScreen.parentOptionKey(candidate.id),
              label: '${candidate.name} (${candidate.code})',
              onPressed: () => Navigator.of(dialogContext).pop(candidate.id),
            ),
        ],
      ),
    ),
  );
  if (chosenId != null) {
    bloc.add(AssetParentChanged(assetId: asset.id, parentId: chosenId));
  }
}

/// One choice in the "Nest under…" picker: the whole line is the target, and at
/// least [AppTouchTarget.min] tall.
class _ParentOption extends StatelessWidget {
  const _ParentOption({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      hoverColor: AppColors.of(context).rowHoverFill,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppTouchTarget.min),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
            child: Text(
              label,
              style: AppTypography.dense(context)
                  ?.copyWith(color: AppColors.of(context).textPrimary),
            ),
          ),
        ),
      ),
    );
  }
}
