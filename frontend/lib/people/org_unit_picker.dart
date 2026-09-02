/// The Org Unit picker: a Site's tree browsed on the left, the Grant set being
/// submitted on the right.
///
/// Composed by `AdmissionDialog` and by nothing else today, but knowing
/// nothing about Approval: it reads and writes `OrgUnitPickerBloc` only, so a
/// later Screen that must choose Org Units mounts this same pair.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import 'org_unit.dart';
import 'org_unit_picker_bloc.dart';

class OrgUnitPicker extends StatelessWidget {
  const OrgUnitPicker({super.key, this.enabled = true, this.height = 260});

  /// False while the surrounding Screen has a submission in flight.
  final bool enabled;
  final double height;

  static const ValueKey<String> siteKey = ValueKey<String>('org-unit-picker-site');
  static const ValueKey<String> emptyGrantedKey = ValueKey<String>('org-unit-picker-none-granted');
  static const ValueKey<String> treeFailureKey = ValueKey<String>('org-unit-picker-tree-failed');
  static ValueKey<String> expandKey(String id) => ValueKey<String>('org-unit-picker-expand-$id');
  static ValueKey<String> addKey(String id) => ValueKey<String>('org-unit-picker-add-$id');
  static ValueKey<String> levelKey(String id, GrantLevel level) =>
      ValueKey<String>('org-unit-picker-level-${level.name}-$id');
  static ValueKey<String> grantedBadgeKey(String id) =>
      ValueKey<String>('org-unit-picker-granted-$id');
  static ValueKey<String> removeKey(String id) => ValueKey<String>('org-unit-picker-remove-$id');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = context.watch<OrgUnitPickerBloc>().state;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Org Unit Grants', style: theme.textTheme.titleSmall),
        const SizedBox(height: Spacing.xs),
        Text(
          'Everything on the right is what this Account will hold. Nothing is '
          'added to what it has now — this is the whole set.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: Spacing.sm),
        if (state.sites.length > 1) _SitePicker(state: state, enabled: enabled),
        if (state.sites.length > 1) const SizedBox(height: Spacing.sm),
        SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Wider than the Granted pane: browsing is where the work is, and
              // an indented tree runs out of horizontal room first.
              Expanded(flex: 3, child: _TreePane(state: state, enabled: enabled)),
              const SizedBox(width: Spacing.md),
              Expanded(flex: 2, child: _GrantedPane(state: state, enabled: enabled)),
            ],
          ),
        ),
      ],
    );
  }
}

class _SitePicker extends StatelessWidget {
  const _SitePicker({required this.state, required this.enabled});

  final OrgUnitPickerState state;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      key: OrgUnitPicker.siteKey,
      initialValue: state.siteId,
      isDense: true,
      decoration: const InputDecoration(labelText: 'Site', border: OutlineInputBorder()),
      items: [
        for (final site in state.sites)
          DropdownMenuItem<String>(value: site.id, child: Text(site.name)),
      ],
      onChanged: enabled
          ? (siteId) {
              if (siteId == null) return;
              context.read<OrgUnitPickerBloc>().add(OrgUnitPickerSiteSelected(siteId));
            }
          : null,
    );
  }
}

class _Pane extends StatelessWidget {
  const _Pane({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.edge),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Spacing.md, Spacing.sm, Spacing.md, Spacing.xs),
            child: Text(
              title,
              style: theme.textTheme.labelLarge
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          const Divider(height: 1),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _TreePane extends StatelessWidget {
  const _TreePane({required this.state, required this.enabled});

  final OrgUnitPickerState state;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final bloc = context.read<OrgUnitPickerBloc>();

    Widget body;
    if (state.sitesStatus == SitesStatus.loading || state.rootsLoading) {
      body = const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)));
    } else if (state.sitesStatus == SitesStatus.failed) {
      // Re-issues the Sites fetch that actually failed, not the whole picker.
      body = _PaneMessage(
        key: OrgUnitPicker.treeFailureKey,
        message: state.sitesFailure!,
        onRetry: enabled ? () => bloc.add(const OrgUnitPickerStarted()) : null,
      );
    } else if (state.rootsFailure != null) {
      // The same event a Site switch fires — re-reads this Site's root level.
      body = _PaneMessage(
        key: OrgUnitPicker.treeFailureKey,
        message: state.rootsFailure!,
        onRetry: enabled ? () => bloc.add(OrgUnitPickerSiteSelected(state.siteId!)) : null,
      );
    } else if (state.sites.isEmpty) {
      body = const _PaneMessage(message: 'There are no Sites to browse yet.');
    } else if (state.rows.isEmpty) {
      body = const _PaneMessage(message: 'Nothing to browse in this Site.');
    } else {
      final rows = state.rows;
      body = ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
        itemCount: rows.length,
        itemBuilder: (context, index) => _TreeRow(row: rows[index], state: state, enabled: enabled),
      );
    }

    return _Pane(title: state.site?.name ?? 'Browse', child: DefaultTextStyle.merge(style: theme.textTheme.bodyMedium!, child: body));
  }
}

class _TreeRow extends StatelessWidget {
  const _TreeRow({required this.row, required this.state, required this.enabled});

  final OrgUnitRow row;
  final OrgUnitPickerState state;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bloc = context.read<OrgUnitPickerBloc>();
    final granted = state.isGranted(row.node.id);
    final level = state.levelOf(row.node.id);

    return Padding(
      padding: EdgeInsets.fromLTRB(Spacing.sm + row.depth * Spacing.lg, 0, Spacing.sm, 0),
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
                        key: OrgUnitPicker.expandKey(row.node.id),
                        padding: EdgeInsets.zero,
                        iconSize: 18,
                        tooltip: row.isExpanded ? 'Collapse' : 'Expand',
                        // Every row offers this: the API does not say whether
                        // an Org Unit has children until it is asked, so the
                        // alternative would be guessing.
                        onPressed: enabled
                            ? () => bloc.add(
                                  row.isExpanded
                                      ? OrgUnitPickerCollapsed(row.node.id)
                                      : OrgUnitPickerExpanded(row.node.id),
                                )
                            : null,
                        icon: Icon(row.isExpanded ? Icons.expand_more : Icons.chevron_right),
                      ),
              ),
              Expanded(
                child: Text(
                  row.node.name,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              if (granted)
                Padding(
                  key: OrgUnitPicker.grantedBadgeKey(row.node.id),
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
                  child: Text(
                    'Granted · ${level!.label}',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.primary),
                  ),
                )
              else
                PopupMenuButton<GrantLevel>(
                  key: OrgUnitPicker.addKey(row.node.id),
                  enabled: enabled,
                  tooltip: 'Grant this Org Unit',
                  icon: const Icon(Icons.add_circle_outline, size: 18),
                  // The level is part of the act of adding, not a default
                  // applied afterwards: this menu has no "just add it" item.
                  itemBuilder: (context) => [
                    for (final choice in GrantLevel.values)
                      PopupMenuItem<GrantLevel>(
                        key: OrgUnitPicker.levelKey(row.node.id, choice),
                        value: choice,
                        child: Text(choice.label),
                      ),
                  ],
                  onSelected: (choice) => bloc.add(
                    OrgUnitPickerGrantAdded(orgUnitId: row.node.id, level: choice),
                  ),
                ),
            ],
          ),
          if (row.failure != null)
            Padding(
              padding: const EdgeInsets.only(left: 32, bottom: Spacing.xs),
              child: Text(
                row.failure!,
                style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.error),
              ),
            )
          else if (row.isExpanded && row.childrenLoaded && row.childCount == 0)
            Padding(
              padding: const EdgeInsets.only(left: 32, bottom: Spacing.xs),
              child: Text(
                'Nothing beneath this',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}

class _GrantedPane extends StatelessWidget {
  const _GrantedPane({required this.state, required this.enabled});

  final OrgUnitPickerState state;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bloc = context.read<OrgUnitPickerBloc>();

    return _Pane(
      title: 'Granted (${state.granted.length})',
      child: state.granted.isEmpty
          ? const _PaneMessage(
              key: OrgUnitPicker.emptyGrantedKey,
              message: 'No Org Units granted. This Account will be able to sign '
                  'in but not act anywhere.',
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
              itemCount: state.granted.length,
              itemBuilder: (context, index) {
                final entry = state.granted[index];
                return Padding(
                  padding: const EdgeInsets.fromLTRB(Spacing.md, Spacing.xs, Spacing.xs, Spacing.xs),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(entry.orgUnit.name, style: theme.textTheme.bodyMedium),
                            // Where it sits, so two Org Units with the same
                            // name are not mistaken for each other.
                            Text(
                              entry.where,
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            ),
                            Text(
                              entry.level.label,
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(color: theme.colorScheme.primary),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        key: OrgUnitPicker.removeKey(entry.orgUnit.id),
                        iconSize: 18,
                        tooltip: 'Remove this Grant',
                        onPressed: enabled
                            ? () => bloc.add(OrgUnitPickerGrantRemoved(entry.orgUnit.id))
                            : null,
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class _PaneMessage extends StatelessWidget {
  const _PaneMessage({super.key, required this.message, this.onRetry});

  final String message;

  /// Present only for a failure this pane can actually recover from by
  /// re-asking; null for an ordinary informational message (an empty Site,
  /// nothing beneath a node).
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(Spacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: Spacing.xs),
            TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ],
      ),
    );
  }
}
