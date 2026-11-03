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
import '../widgets/app_dialog.dart';
import 'safety_observations_bloc.dart';

class SafetyObservationOrgUnitFilterDialog extends StatelessWidget {
  const SafetyObservationOrgUnitFilterDialog({super.key});

  /// The two actions' keys are the dialog shell's own (`AppDialog.actionKey`),
  /// named for this dialog's use of them (`docs/design-language.md` §11).
  static final ValueKey<String> allOrgUnitsKey =
      AppDialog.actionKey('safety-observations-filter-all');
  static final ValueKey<String> cancelKey =
      AppDialog.actionKey('safety-observations-filter-cancel');

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

    return AppDialog(
      title: 'Filter by Org Unit',
      // One tree of names, at the width this dialog has always been: `decision`
      // is 420, the box the hand-sized `AlertDialog` used, so moving the shell
      // onto [AppDialog] changes nothing a reader feels. `picker` (460) is for
      // a dialog written for the tree, which this one is not.
      size: AppDialogSize.decision,
      // Clearing is this dialog's own act (the primary, right-most); Cancel is
      // the dismiss, which is what `Esc` runs.
      actions: [
        AppDialogAction(
          id: 'safety-observations-filter-cancel',
          label: 'Cancel',
          kind: AppDialogActionKind.dismiss,
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppDialogAction(
          id: 'safety-observations-filter-all',
          label: 'All Org Units',
          onPressed: () {
            context.read<SafetyObservationsBloc>().add(const SafetyObservationsFiltersCleared());
            Navigator.of(context).pop();
          },
        ),
      ],
      // The chooser is a tree with a scroll of its own, so it is given a height
      // and the dialog's own content area scrolls around it.
      child: SizedBox(
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
    );
  }
}
