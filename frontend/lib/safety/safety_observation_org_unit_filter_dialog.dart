/// The observation register's Org Unit filter (issue #230): a Site's tree,
/// browsed one level at a time, picking one Org Unit to narrow the register
/// to — or clearing back to the whole Site.
///
/// The same shape `SafetyOrgUnitFilterDialog` has, for the same reason: the
/// chooser is reused rather than re-drawn. Narrowing to an Org Unit includes
/// everything beneath it — the ticket's own criterion — which is the
/// server's ltree walk, not a filter the client applies.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../maintenance/maintenance.dart';
import '../people/people.dart';
import '../people_api.dart';
import '../platform/auth_gateway.dart';
import 'safety_observations_bloc.dart';

class SafetyObservationOrgUnitFilterDialog extends StatelessWidget {
  const SafetyObservationOrgUnitFilterDialog({super.key});

  static const ValueKey<String> allOrgUnitsKey =
      ValueKey<String>('safety-observations-filter-all');
  static const ValueKey<String> cancelKey = ValueKey<String>('safety-observations-filter-cancel');

  /// Opens the filter over the register. `showDialog` builds its route under
  /// the Navigator, which is not a descendant of the route-scoped
  /// `BlocProvider<SafetyObservationsBloc>` the Screen lives in — so that Bloc
  /// is handed across explicitly, the shape `SafetyOrgUnitFilterDialog.open`
  /// uses.
  static Future<void> open(BuildContext context, {String? siteId}) {
    final bloc = context.read<SafetyObservationsBloc>();
    final peopleApi = context.read<PeopleApi>();
    final authGateway = context.read<AuthGateway>();
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => BlocProvider<SafetyObservationsBloc>.value(
        value: bloc,
        child: BlocProvider<OrgUnitPickerBloc>(
          create: (_) => OrgUnitPickerBloc(
            peopleApi: peopleApi,
            authGateway: authGateway,
            initialSiteId: siteId,
          )..add(const OrgUnitPickerStarted()),
          child: const SafetyObservationOrgUnitFilterDialog(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SafetyObservationsBloc>().state;
    final selectedId = state is SafetyObservationsLoaded ? state.filters.orgUnitId : null;

    return AlertDialog(
      title: const Text('Filter by Org Unit'),
      content: SizedBox(
        width: 420,
        height: 420,
        child: OrgUnitChooser(
          selectedId: selectedId,
          showSitePicker: false,
          title: 'Narrow the register',
          description: 'Choose the Org Unit whose Safety observations and everything beneath it '
              'you want to read, or clear back to the whole Site.',
          onSelected: (node) {
            context.read<SafetyObservationsBloc>().add(
                  SafetyObservationsOrgUnitFilterSet(orgUnitId: node.id, name: node.name),
                );
            Navigator.of(context).pop();
          },
        ),
      ),
      actions: [
        TextButton(
          key: allOrgUnitsKey,
          onPressed: () {
            context.read<SafetyObservationsBloc>().add(const SafetyObservationsFiltersCleared());
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
