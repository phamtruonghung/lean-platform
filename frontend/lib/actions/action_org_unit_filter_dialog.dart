/// The register's Org Unit filter (issue #176): a Site's tree, browsed one
/// level at a time, picking one Org Unit to narrow the log to — or clearing
/// back to the whole Site.
///
/// The same shape the tier board's own filter dialog has, for the same reason:
/// the chooser is reused rather than re-drawn, and the two buttons a *filter*
/// needs (clear, cancel) are the two a form does not.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../maintenance/maintenance.dart';
import '../people/people.dart';
import '../people_api.dart';
import '../platform/auth_gateway.dart';
import 'actions_bloc.dart';

class ActionOrgUnitFilterDialog extends StatelessWidget {
  const ActionOrgUnitFilterDialog({super.key});

  static const ValueKey<String> allOrgUnitsKey = ValueKey<String>('actions-filter-all');
  static const ValueKey<String> cancelKey = ValueKey<String>('actions-filter-cancel');

  /// Opens the filter over the register. `showDialog` builds its route under
  /// the Navigator, which is not a descendant of the route-scoped
  /// `BlocProvider<ActionsBloc>` the Screen lives in — so that Bloc is handed
  /// across explicitly, the shape `TierBoardOrgUnitFilterDialog.open` uses.
  ///
  /// The picker opens on the Site the register is showing, so a caller does not
  /// have to re-find where they were: the filter may only name an Org Unit in
  /// the Site already on screen.
  static Future<void> open(BuildContext context, {String? siteId}) {
    final actionsBloc = context.read<ActionsBloc>();
    final peopleApi = context.read<PeopleApi>();
    final authGateway = context.read<AuthGateway>();
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => BlocProvider<ActionsBloc>.value(
        value: actionsBloc,
        child: BlocProvider<OrgUnitPickerBloc>(
          create: (_) => OrgUnitPickerBloc(
            peopleApi: peopleApi,
            authGateway: authGateway,
            initialSiteId: siteId,
          )..add(const OrgUnitPickerStarted()),
          child: const ActionOrgUnitFilterDialog(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ActionsBloc>().state;
    final selectedId = state is ActionsLoaded ? state.orgUnitFilterId : null;

    return AlertDialog(
      title: const Text('Filter by Org Unit'),
      content: SizedBox(
        width: 420,
        height: 420,
        child: OrgUnitChooser(
          selectedId: selectedId,
          // The register is one Site's, so the chooser may not name an Org Unit
          // in another one.
          showSitePicker: false,
          title: 'Narrow the log',
          description: 'Choose the Org Unit whose Actions and everything beneath it you want to '
              'read, or clear back to the whole Site.',
          onSelected: (node) {
            context.read<ActionsBloc>().add(
                  ActionsOrgUnitFilterSelected(orgUnitId: node.id, orgUnitName: node.name),
                );
            Navigator.of(context).pop();
          },
        ),
      ),
      actions: [
        TextButton(
          key: allOrgUnitsKey,
          onPressed: () {
            context.read<ActionsBloc>().add(const ActionsOrgUnitFilterCleared());
            Navigator.of(context).pop();
          },
          child: const Text('All Org Units'),
        ),
        TextButton(
          key: cancelKey,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
