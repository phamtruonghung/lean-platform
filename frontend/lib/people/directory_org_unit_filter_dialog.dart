/// The Directory's own Org Unit filter (issue #86, AC3): a Site's tree,
/// browsed one level at a time, picking one Org Unit to narrow the list to.
///
/// Drives `OrgUnitPickerBloc` — the same state machine `OrgUnitPicker`
/// (People's Grant editor) already browses — rather than writing a second
/// tree Bloc. That widget itself is not reused: it is a Grant editor, add/
/// remove semantics and a Granted pane included, built for `AdmissionDialog`
/// (`org_unit_picker.dart`'s own header). This dialog wants a single-select
/// choice with no Granted set at all, so it draws its own, much smaller view
/// over the same Bloc, the same way `maintenance/org_unit_chooser.dart`
/// already does for the Asset form.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../people_api.dart';
import '../platform/auth_gateway.dart';
import '../theme.dart';
import 'directory_bloc.dart';
import 'org_unit_picker_bloc.dart';

class DirectoryOrgUnitFilterDialog extends StatelessWidget {
  const DirectoryOrgUnitFilterDialog({super.key});

  static const ValueKey<String> siteKey = ValueKey<String>('directory-org-unit-filter-site');
  static const ValueKey<String> allOrgUnitsKey = ValueKey<String>('directory-org-unit-filter-all');
  static const ValueKey<String> failureKey = ValueKey<String>('directory-org-unit-filter-failed');
  static ValueKey<String> expandKey(String id) =>
      ValueKey<String>('directory-org-unit-filter-expand-$id');
  static ValueKey<String> rowKey(String id) => ValueKey<String>('directory-org-unit-filter-row-$id');

  /// Opens the filter over the Directory list. `showDialog` builds its route
  /// under the Navigator, which is not a descendant of the route-scoped
  /// `BlocProvider<DirectoryBloc>` the list lives in — so that Bloc is handed
  /// across explicitly, the same shape `WorkOrderAssignDialog.open` uses for
  /// `WorkOrdersBloc`.
  static Future<void> open(BuildContext context) {
    final directoryBloc = context.read<DirectoryBloc>();
    final peopleApi = context.read<PeopleApi>();
    final authGateway = context.read<AuthGateway>();
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => BlocProvider<DirectoryBloc>.value(
        value: directoryBloc,
        child: BlocProvider<OrgUnitPickerBloc>(
          create: (context) => OrgUnitPickerBloc(peopleApi: peopleApi, authGateway: authGateway)
            ..add(const OrgUnitPickerStarted()),
          child: const DirectoryOrgUnitFilterDialog(),
        ),
      ),
    );
  }

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
      body = _Failure(
        message: state.sitesFailure!,
        onRetry: () => bloc.add(const OrgUnitPickerStarted()),
      );
    } else if (state.rootsFailure != null) {
      body = _Failure(
        message: state.rootsFailure!,
        onRetry: () => bloc.add(OrgUnitPickerSiteSelected(state.siteId!)),
      );
    } else if (state.sites.isEmpty) {
      body = const Text('There are no Sites to browse yet.');
    } else if (state.rows.isEmpty) {
      body = const Text('Nothing to browse in this Site.');
    } else {
      body = ListView.builder(
        shrinkWrap: true,
        itemCount: state.rows.length,
        itemBuilder: (context, index) => _Row(row: state.rows[index], bloc: bloc),
      );
    }

    return AlertDialog(
      title: const Text('Filter by Org Unit'),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (state.sites.length > 1) ...[
              DropdownButtonFormField<String>(
                key: siteKey,
                initialValue: state.siteId,
                isDense: true,
                decoration: const InputDecoration(labelText: 'Site', border: OutlineInputBorder()),
                items: [
                  for (final site in state.sites)
                    DropdownMenuItem<String>(value: site.id, child: Text(site.name)),
                ],
                onChanged: (siteId) {
                  if (siteId == null) return;
                  bloc.add(OrgUnitPickerSiteSelected(siteId));
                },
              ),
              const SizedBox(height: Spacing.sm),
            ],
            Expanded(child: DefaultTextStyle.merge(style: theme.textTheme.bodyMedium!, child: body)),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: allOrgUnitsKey,
          onPressed: () {
            context.read<DirectoryBloc>().add(const DirectoryOrgUnitFilterChanged());
            Navigator.of(context).pop();
          },
          child: const Text('All Org Units'),
        ),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.row, required this.bloc});

  final OrgUnitRow row;
  final OrgUnitPickerBloc bloc;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: row.depth * Spacing.lg),
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
                    key: DirectoryOrgUnitFilterDialog.expandKey(row.node.id),
                    padding: EdgeInsets.zero,
                    iconSize: 18,
                    tooltip: row.isExpanded ? 'Collapse' : 'Expand',
                    onPressed: () => bloc.add(
                      row.isExpanded
                          ? OrgUnitPickerCollapsed(row.node.id)
                          : OrgUnitPickerExpanded(row.node.id),
                    ),
                    icon: Icon(row.isExpanded ? Icons.expand_more : Icons.chevron_right),
                  ),
          ),
          Expanded(
            child: InkWell(
              key: DirectoryOrgUnitFilterDialog.rowKey(row.node.id),
              onTap: () {
                context.read<DirectoryBloc>().add(
                      DirectoryOrgUnitFilterChanged(orgUnitId: row.node.id, orgUnitName: row.node.name),
                    );
                Navigator.of(context).pop();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
                child: Text(row.node.name),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Failure extends StatelessWidget {
  const _Failure({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message, key: DirectoryOrgUnitFilterDialog.failureKey),
        const SizedBox(height: Spacing.xs),
        TextButton(onPressed: onRetry, child: const Text('Try again')),
      ],
    );
  }
}
