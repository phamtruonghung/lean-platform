/// The register's "escalated to" filter (issue #180): the plant manager's own
/// queue, in one click.
///
/// The same shape [ActionOrgUnitFilterDialog] has, and for the same reasons: a
/// chooser rather than a re-drawn tree, a Site's own Org Units only, and the
/// two buttons a *filter* needs — clear, cancel — rather than a form's.
///
/// It is a different question from the Org Unit filter beside it, which is why
/// it is a second control rather than another mode of the first: "Actions at
/// Line 1" is about where the work is, and "handed up to Line 1" is about who
/// has been told. A concern at the line that was escalated to the area is in
/// the second list and not the first.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../maintenance/maintenance.dart';
import '../people/people.dart';
import '../people_api.dart';
import '../platform/auth_gateway.dart';
import 'actions_bloc.dart';

class ActionEscalatedToFilterDialog extends StatelessWidget {
  const ActionEscalatedToFilterDialog({super.key});

  static const ValueKey<String> anyoneKey = ValueKey<String>('actions-filter-escalated-anyone');
  static const ValueKey<String> cancelKey = ValueKey<String>('actions-filter-escalated-cancel');

  /// Opens the filter over the register. `showDialog` builds its route under the
  /// Navigator, which is not a descendant of the route-scoped
  /// `BlocProvider<ActionsBloc>` the Screen lives in — so that Bloc is handed
  /// across explicitly, the shape the Org Unit filter already uses.
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
          child: const ActionEscalatedToFilterDialog(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ActionsBloc>().state;
    final selectedId = state is ActionsLoaded ? state.escalatedToOrgUnitFilterId : null;

    return AlertDialog(
      title: const Text('Filter by what was handed up'),
      content: SizedBox(
        width: 420,
        height: 420,
        child: OrgUnitChooser(
          selectedId: selectedId,
          showSitePicker: false,
          title: 'Whose queue',
          description: 'Choose the Org Unit that concerns were handed up to — what is waiting on '
              'the area, not what sits at the line — or clear back to everything.',
          onSelected: (node) {
            context.read<ActionsBloc>().add(
                  ActionsEscalatedToFilterSelected(
                    orgUnitId: node.id,
                    orgUnitName: node.name,
                  ),
                );
            Navigator.of(context).pop();
          },
        ),
      ),
      actions: [
        TextButton(
          key: anyoneKey,
          onPressed: () {
            context.read<ActionsBloc>().add(const ActionsEscalatedToFilterCleared());
            Navigator.of(context).pop();
          },
          child: const Text('Anyone'),
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
