/// Choosing the one Org Unit an Asset sits at, by browsing the same tree the
/// Approval flow grants from.
///
/// This is a second *view* of `OrgUnitPickerBloc`, not a second tree browser.
/// Everything that makes browsing work — the Sites, the root level and its
/// entry-point semantics (ADR-0008), fetching children only on expansion, the
/// per-branch failure — is the People Bloc's, reached through People's client
/// entry point. What is not reused is `OrgUnitPicker` itself: that widget is a
/// Grant editor, with a Granted pane, a read/edit level on every add, and copy
/// about what an Account will hold. An Asset needs exactly one Org Unit and no
/// level, so bending that widget into a single-select would have meant
/// branching every pane, label and affordance in it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../people/people.dart';
import '../theme.dart';

class OrgUnitChooser extends StatelessWidget {
  const OrgUnitChooser({
    super.key,
    required this.selectedId,
    required this.onSelected,
    this.enabled = true,
    this.height = 240,
    this.showSitePicker = true,
    this.title = 'Where it sits',
    this.description = "Choose the Org Unit this machine belongs to. This is what decides "
        'who may raise and close work against it.',
  });

  /// The Org Unit currently chosen, owned by the form above rather than by the
  /// Bloc: "which one did I pick" is this form's decision, and the Bloc's job
  /// is the tree.
  final String? selectedId;
  final ValueChanged<OrgUnitNode> onSelected;
  final bool enabled;
  final double height;

  /// Whether a caller with more than one Site may switch Site from inside
  /// this chooser. Placing an Asset needs that — the caller may cover more
  /// than one Site and is not limited to whichever one happened to be showing
  /// (`AssetFormDialog`). A caller that is already scoped to one particular
  /// Site — the Work order list's Org Unit filter, say — sets this false so
  /// the chooser cannot name an Org Unit in a Site other than the one already
  /// on screen.
  final bool showSitePicker;

  /// The section header above the tree, and the sentence beneath it —
  /// callers whose context is not "placing an Asset" (a filter, say) supply
  /// their own rather than inheriting copy that does not fit.
  final String title;
  final String description;

  static const ValueKey<String> siteKey = ValueKey<String>('org-unit-chooser-site');
  static const ValueKey<String> failureKey = ValueKey<String>('org-unit-chooser-failed');
  static ValueKey<String> expandKey(String id) => ValueKey<String>('org-unit-chooser-expand-$id');
  static ValueKey<String> chooseKey(String id) => ValueKey<String>('org-unit-chooser-choose-$id');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = context.watch<OrgUnitPickerBloc>().state;
    final bloc = context.read<OrgUnitPickerBloc>();

    Widget body;
    if (state.sitesStatus == SitesStatus.loading || state.rootsLoading) {
      body = const Center(
        child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    } else if (state.sitesStatus == SitesStatus.failed) {
      body = _ChooserMessage(
        key: failureKey,
        message: state.sitesFailure!,
        onRetry: enabled ? () => bloc.add(const OrgUnitPickerStarted()) : null,
      );
    } else if (state.rootsFailure != null) {
      body = _ChooserMessage(
        key: failureKey,
        message: state.rootsFailure!,
        onRetry: enabled ? () => bloc.add(OrgUnitPickerSiteSelected(state.siteId!)) : null,
      );
    } else if (state.rows.isEmpty) {
      body = const _ChooserMessage(message: 'Nothing to browse in this Site.');
    } else {
      body = ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
        itemCount: state.rows.length,
        itemBuilder: (context, index) => _ChooserRow(
          row: state.rows[index],
          isSelected: state.rows[index].node.id == selectedId,
          enabled: enabled,
          onSelected: onSelected,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: theme.textTheme.titleSmall),
        const SizedBox(height: Spacing.xs),
        Text(
          description,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: Spacing.sm),
        if (showSitePicker && state.sites.length > 1) ...[
          DropdownButtonFormField<String>(
            key: siteKey,
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
                    bloc.add(OrgUnitPickerSiteSelected(siteId));
                  }
                : null,
          ),
          const SizedBox(height: Spacing.sm),
        ],
        Container(
          height: height,
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.edge),
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: DefaultTextStyle.merge(style: theme.textTheme.bodyMedium!, child: body),
        ),
      ],
    );
  }
}

class _ChooserRow extends StatelessWidget {
  const _ChooserRow({
    required this.row,
    required this.isSelected,
    required this.enabled,
    required this.onSelected,
  });

  final OrgUnitRow row;
  final bool isSelected;
  final bool enabled;
  final ValueChanged<OrgUnitNode> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bloc = context.read<OrgUnitPickerBloc>();

    return Padding(
      padding: EdgeInsets.fromLTRB(Spacing.sm + row.depth * Spacing.lg, 0, Spacing.sm, 0),
      child: Row(
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
                    key: OrgUnitChooser.expandKey(row.node.id),
                    padding: EdgeInsets.zero,
                    iconSize: 18,
                    tooltip: row.isExpanded ? 'Collapse' : 'Expand',
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
            child: TextButton(
              key: OrgUnitChooser.chooseKey(row.node.id),
              onPressed: enabled ? () => onSelected(row.node) : null,
              style: TextButton.styleFrom(
                alignment: Alignment.centerLeft,
                foregroundColor: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurface,
              ),
              child: Row(
                children: [
                  Icon(
                    isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    size: 16,
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(child: Text(row.node.name, overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChooserMessage extends StatelessWidget {
  const _ChooserMessage({super.key, required this.message, this.onRetry});

  final String message;
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
