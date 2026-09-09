/// Sites and the Org Unit tree an Account may see (issue #90): creating a
/// Site, adding an Org Unit beneath a parent it holds write scope on (or
/// starting a new root branch, administrator only — ADR-0008), retiring or
/// reinstating one, searching a Site's tree by name, and importing a branch
/// in bulk.
///
/// Drives two Blocs side by side, never merging them into one: `OrgUnitPickerBloc`
/// for the tree itself — Sites, expand/collapse, the rows already flattened
/// for drawing — exactly the job its own header states, unchanged by this
/// ticket; `OrgUnitAdminBloc` for every write and the search/import queries,
/// which that Bloc was never built to hold. `OrgUnitPicker` the widget is not
/// reused here, the same reason `EmployeeAssignmentDialog`'s own header gives
/// for its `_DestinationPicker`: it is a Grant editor built for the Approval
/// flow, add/remove-Grant semantics and a Granted pane included, none of
/// which this Screen wants. `_Tree` below is a third view over the one shared
/// `OrgUnitPickerBloc`, the same amount of duplication that dialog and
/// `SkillQualifiedEmployeesDialog`'s own `_ScopePicker` already accept for the
/// same reason — the Bloc is shared, the view is not.
///
/// Offered to every approved Account — `GET /api/people/sites` and
/// `GET .../org-units` carry no role check of their own (ADR-0009's "a plant
/// directory is not a secret" applies here too), the same openness
/// `Routes.jobRoles`/`Routes.skills` already have. Only the write affordances
/// are gated: creating a root Org Unit to [isAdmin] (ADR-0008), everything
/// else offered to any role with the server's own scope check
/// (`OUTSIDE_GRANTED_ORG_UNITS`) as the real gate — this Screen does not try
/// to guess who holds write scope on a particular row, the same limitation
/// `EmployeeAssignmentDialog`'s own header already accepts for `OrgUnitNode`
/// carrying no read/write distinction.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import 'org_unit.dart';
import 'org_unit_admin_bloc.dart';
import 'org_unit_form_dialog.dart';
import 'org_unit_import_dialog.dart';
import 'org_unit_picker_bloc.dart';
import 'site_form_dialog.dart';

class OrgUnitsScreen extends StatefulWidget {
  const OrgUnitsScreen({super.key, required this.isAdmin});

  /// Whether this caller may create a Site or start a new root Org Unit
  /// branch (ADR-0008) — read off `/me`'s own role, the same shape
  /// `JobRolesScreen.isAdmin`/`SkillsScreen.isAdmin` already follow.
  final bool isAdmin;

  static const double maxWidth = 900;

  static const ValueKey<String> siteKey = ValueKey<String>('org-units-site');
  static const ValueKey<String> addSiteKey = ValueKey<String>('org-units-add-site');
  static const ValueKey<String> addRootKey = ValueKey<String>('org-units-add-root');
  static const ValueKey<String> importKey = ValueKey<String>('org-units-import');
  static const ValueKey<String> searchFieldKey = ValueKey<String>('org-units-search-field');
  static const ValueKey<String> searchSubmitKey = ValueKey<String>('org-units-search-submit');
  static const ValueKey<String> searchClearKey = ValueKey<String>('org-units-search-clear');
  static const ValueKey<String> searchTruncatedKey = ValueKey<String>('org-units-search-truncated');
  static const ValueKey<String> searchEmptyKey = ValueKey<String>('org-units-search-empty');
  static const ValueKey<String> searchFailureKey = ValueKey<String>('org-units-search-failure');
  static const ValueKey<String> emptySitesKey = ValueKey<String>('org-units-empty-sites');
  static const ValueKey<String> emptyTreeKey = ValueKey<String>('org-units-empty-tree');
  static const ValueKey<String> treeFailureKey = ValueKey<String>('org-units-tree-failed');
  static const ValueKey<String> mutationFailureKey = ValueKey<String>('org-units-mutation-failed');

  static ValueKey<String> expandKey(String id) => ValueKey<String>('org-units-expand-$id');
  static ValueKey<String> addChildKey(String id) => ValueKey<String>('org-units-add-child-$id');
  static ValueKey<String> retireKey(String id) => ValueKey<String>('org-units-retire-$id');
  static ValueKey<String> reinstateKey(String id) => ValueKey<String>('org-units-reinstate-$id');
  static ValueKey<String> retiredChipKey(String id) => ValueKey<String>('org-units-retired-$id');
  static ValueKey<String> searchResultKey(String id) => ValueKey<String>('org-units-search-result-$id');

  @override
  State<OrgUnitsScreen> createState() => _OrgUnitsScreenState();
}

class _OrgUnitsScreenState extends State<OrgUnitsScreen> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _onAdminChanged(BuildContext context, OrgUnitAdminState state) {
    final effect = state.effect;
    if (effect == null) return;
    final pickerBloc = context.read<OrgUnitPickerBloc>();
    switch (effect) {
      case OrgUnitAdminSitesChanged():
        pickerBloc.add(const OrgUnitPickerStarted());
      case OrgUnitAdminLevelChanged(parentId: final parentId):
        pickerBloc.add(OrgUnitPickerRefreshed(parentId: parentId));
      case OrgUnitAdminTreeReplaced(siteId: final siteId):
        pickerBloc.add(OrgUnitPickerSiteSelected(siteId));
    }
    context.read<OrgUnitAdminBloc>().add(const OrgUnitAdminEffectConsumed());
  }

  void _submitSearch(BuildContext context, String siteId) {
    final term = _search.text.trim();
    if (term.isEmpty) return;
    context.read<OrgUnitAdminBloc>().add(OrgUnitAdminSearchRequested(siteId: siteId, search: term));
  }

  void _clearSearch(BuildContext context) {
    _search.clear();
    context.read<OrgUnitAdminBloc>().add(const OrgUnitAdminSearchCleared());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pickerState = context.watch<OrgUnitPickerBloc>().state;
    final adminState = context.watch<OrgUnitAdminBloc>().state;
    final siteId = pickerState.siteId;

    return Scaffold(
      body: BlocListener<OrgUnitAdminBloc, OrgUnitAdminState>(
        listener: _onAdminChanged,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: OrgUnitsScreen.maxWidth),
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
                          Text('Org Units', style: theme.textTheme.headlineSmall),
                          const SizedBox(height: Spacing.xs),
                          Text(
                            "A Site's own shape — where a KPI is measured, an Account is "
                            'granted, and an Asset sits.',
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    if (widget.isAdmin)
                      FilledButton.icon(
                        key: OrgUnitsScreen.addSiteKey,
                        onPressed: adminState.isMutating
                            ? null
                            : () => SiteFormDialog.open(context),
                        icon: const Icon(Icons.add_business_outlined),
                        label: const Text('Add Site'),
                      ),
                  ],
                ),
                const SizedBox(height: Spacing.lg),
                if (pickerState.sitesStatus == SitesStatus.loading)
                  const Center(child: CircularProgressIndicator())
                else if (pickerState.sitesStatus == SitesStatus.failed)
                  _Failed(
                    message: pickerState.sitesFailure!,
                    onRetry: () =>
                        context.read<OrgUnitPickerBloc>().add(const OrgUnitPickerStarted()),
                  )
                else if (pickerState.sites.isEmpty)
                  Text(
                    'There are no Sites yet.',
                    key: OrgUnitsScreen.emptySitesKey,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  )
                else ...[
                  if (pickerState.sites.length > 1) ...[
                    SizedBox(
                      width: 280,
                      child: DropdownButtonFormField<String>(
                        key: OrgUnitsScreen.siteKey,
                        initialValue: siteId,
                        isDense: true,
                        decoration: const InputDecoration(labelText: 'Site', border: OutlineInputBorder()),
                        items: [
                          for (final site in pickerState.sites)
                            DropdownMenuItem<String>(value: site.id, child: Text(site.name)),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          context.read<OrgUnitPickerBloc>().add(OrgUnitPickerSiteSelected(value));
                          context.read<OrgUnitAdminBloc>().add(const OrgUnitAdminSearchCleared());
                        },
                      ),
                    ),
                    const SizedBox(height: Spacing.md),
                  ],
                  if (siteId != null) ...[
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: OrgUnitsScreen.searchFieldKey,
                            controller: _search,
                            decoration: const InputDecoration(
                              labelText: 'Search this Site by name',
                              border: OutlineInputBorder(),
                            ),
                            onSubmitted: (_) => _submitSearch(context, siteId),
                          ),
                        ),
                        const SizedBox(width: Spacing.sm),
                        FilledButton(
                          key: OrgUnitsScreen.searchSubmitKey,
                          onPressed: () => _submitSearch(context, siteId),
                          child: const Text('Search'),
                        ),
                        if (adminState.searchStatus != OrgUnitAdminSearchStatus.idle) ...[
                          const SizedBox(width: Spacing.sm),
                          TextButton(
                            key: OrgUnitsScreen.searchClearKey,
                            onPressed: () => _clearSearch(context),
                            child: const Text('Clear'),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: Spacing.md),
                    Wrap(
                      spacing: Spacing.sm,
                      runSpacing: Spacing.sm,
                      children: [
                        if (widget.isAdmin)
                          OutlinedButton.icon(
                            key: OrgUnitsScreen.addRootKey,
                            onPressed: adminState.isMutating
                                ? null
                                : () => OrgUnitFormDialog.open(context, siteId: siteId, parentId: null),
                            icon: const Icon(Icons.add),
                            label: const Text('Add root Org Unit'),
                          ),
                        OutlinedButton.icon(
                          key: OrgUnitsScreen.importKey,
                          onPressed: () => OrgUnitImportDialog.open(context, siteId: siteId),
                          icon: const Icon(Icons.upload_file_outlined),
                          label: const Text('Import a branch'),
                        ),
                      ],
                    ),
                    const SizedBox(height: Spacing.md),
                    if (adminState.mutationFailure != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Spacing.md),
                        child: Text(
                          adminState.mutationFailure!,
                          key: OrgUnitsScreen.mutationFailureKey,
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                        ),
                      ),
                    if (adminState.searchStatus != OrgUnitAdminSearchStatus.idle)
                      _SearchResults(state: adminState)
                    else
                      _Tree(state: pickerState, siteId: siteId, isMutating: adminState.isMutating),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({required this.state});

  final OrgUnitAdminState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (state.searchStatus == OrgUnitAdminSearchStatus.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.searchStatus == OrgUnitAdminSearchStatus.failed) {
      return Text(
        state.searchFailure ?? '',
        key: OrgUnitsScreen.searchFailureKey,
        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (state.searchTruncated)
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.sm),
            child: Text(
              'Only the first matches are shown — narrow the search to see the rest.',
              key: OrgUnitsScreen.searchTruncatedKey,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        if (state.searchResults.isEmpty)
          Text(
            'Nothing matched.',
            key: OrgUnitsScreen.searchEmptyKey,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          )
        else
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (final orgUnit in state.searchResults)
                  Padding(
                    key: OrgUnitsScreen.searchResultKey(orgUnit.id),
                    padding: const EdgeInsets.all(Spacing.md),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text('${orgUnit.name} · ${orgUnit.code}', style: theme.textTheme.bodyMedium),
                        ),
                        if (!orgUnit.isActive)
                          Chip(
                            label: const Text('Retired'),
                            visualDensity: VisualDensity.compact,
                            backgroundColor: theme.colorScheme.errorContainer,
                            labelStyle: theme.textTheme.labelSmall
                                ?.copyWith(color: theme.colorScheme.onErrorContainer),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Tree extends StatelessWidget {
  const _Tree({required this.state, required this.siteId, required this.isMutating});

  final OrgUnitPickerState state;
  final String siteId;
  final bool isMutating;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (state.rootsLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.rootsFailure != null) {
      return _Failed(
        message: state.rootsFailure!,
        onRetry: () => context
            .read<OrgUnitPickerBloc>()
            .add(OrgUnitPickerSiteSelected(state.siteId!)),
      );
    }
    if (state.rows.isEmpty) {
      return Text(
        'Nothing to browse in this Site yet.',
        key: OrgUnitsScreen.emptyTreeKey,
        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      );
    }
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          for (final row in state.rows)
            _TreeRow(
              row: row,
              siteId: siteId,
              isRoot: state.rootIds.contains(row.node.id),
              isMutating: isMutating,
            ),
        ],
      ),
    );
  }
}

class _TreeRow extends StatelessWidget {
  const _TreeRow({
    required this.row,
    required this.siteId,
    required this.isRoot,
    required this.isMutating,
  });

  final OrgUnitRow row;
  final String siteId;

  /// Whether [row] sits at the level `OrgUnitPickerBloc` answered as the
  /// root — used only to decide which level to refresh after a write against
  /// this row, since a non-administrator's own root-level rows can carry a
  /// real, non-null `parentId` (ADR-0008): refreshing "this row's own
  /// parentId" would be wrong for those rows, refreshing null (the root
  /// level actually asked for) is right for all of them.
  final bool isRoot;

  final bool isMutating;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bloc = context.read<OrgUnitPickerBloc>();
    final node = row.node;
    final refreshParentId = isRoot ? null : node.parentId;

    return Padding(
      padding: EdgeInsets.fromLTRB(Spacing.sm + row.depth * Spacing.lg, Spacing.xs, Spacing.sm, Spacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 32,
                height: 32,
                child: row.isLoadingChildren
                    ? const Padding(
                        padding: EdgeInsets.all(Spacing.sm),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        key: OrgUnitsScreen.expandKey(node.id),
                        padding: EdgeInsets.zero,
                        iconSize: 18,
                        tooltip: row.isExpanded ? 'Collapse' : 'Expand',
                        onPressed: () => bloc.add(
                          row.isExpanded
                              ? OrgUnitPickerCollapsed(node.id)
                              : OrgUnitPickerExpanded(node.id),
                        ),
                        icon: Icon(row.isExpanded ? Icons.expand_more : Icons.chevron_right),
                      ),
              ),
              Expanded(
                child: Text(
                  '${node.name} · ${node.code}',
                  overflow: TextOverflow.ellipsis,
                  style: node.isActive
                      ? theme.textTheme.bodyMedium
                      : theme.textTheme.bodyMedium?.copyWith(
                          decoration: TextDecoration.lineThrough,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                ),
              ),
              if (!node.isActive)
                Padding(
                  key: OrgUnitsScreen.retiredChipKey(node.id),
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
                  child: Chip(
                    label: const Text('Retired'),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: theme.colorScheme.errorContainer,
                    labelStyle:
                        theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onErrorContainer),
                  ),
                ),
              IconButton(
                key: OrgUnitsScreen.addChildKey(node.id),
                tooltip: 'Add an Org Unit here',
                iconSize: 18,
                onPressed: isMutating
                    ? null
                    : () => OrgUnitFormDialog.open(context, siteId: siteId, parentId: node.id),
                icon: const Icon(Icons.add_circle_outline),
              ),
              node.isActive
                  ? OutlinedButton(
                      key: OrgUnitsScreen.retireKey(node.id),
                      onPressed: isMutating ? null : () => _retire(context, node, refreshParentId),
                      child: const Text('Retire'),
                    )
                  : OutlinedButton(
                      key: OrgUnitsScreen.reinstateKey(node.id),
                      onPressed: isMutating
                          ? null
                          : () => context.read<OrgUnitAdminBloc>().add(
                                OrgUnitAdminActiveSet(
                                  orgUnitId: node.id,
                                  isActive: true,
                                  refreshParentId: refreshParentId,
                                ),
                              ),
                      child: const Text('Reinstate'),
                    ),
            ],
          ),
          if (row.failure != null)
            Padding(
              padding: const EdgeInsets.only(left: 32),
              child: Text(
                row.failure!,
                style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _retire(BuildContext context, OrgUnitNode node, String? refreshParentId) async {
    final bloc = context.read<OrgUnitAdminBloc>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Retire this Org Unit?'),
        content: Text(
          '${node.name} will read as retired rather than deleted, and can be '
          'reinstated at any time.',
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
      bloc.add(
        OrgUnitAdminActiveSet(orgUnitId: node.id, isActive: false, refreshParentId: refreshParentId),
      );
    }
  }
}

class _Failed extends StatelessWidget {
  const _Failed({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      key: OrgUnitsScreen.treeFailureKey,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: Spacing.sm),
            TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
