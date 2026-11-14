/// The register's Org Unit filter (issue #226): a Site's tree, browsed one
/// level at a time, picking one Org Unit to narrow the register to — or
/// clearing back to the whole Site.
///
/// The same shape `NonconformanceOrgUnitFilterDialog` has, for the same
/// reason: the chooser is reused rather than re-drawn. Narrowing to an Org
/// Unit includes everything beneath it — the ticket's own criterion, and
/// what "everything under Line 3" means in this Platform. That is the
/// server's ltree walk, not a filter the client applies.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/app_localizations.dart';
import '../maintenance/maintenance.dart';
import '../people/people.dart';
import '../people_api.dart';
import '../platform/auth_gateway.dart';
import '../widgets/app_dialog.dart';
import 'safety_incidents_bloc.dart';

class SafetyOrgUnitFilterDialog extends StatelessWidget {
  const SafetyOrgUnitFilterDialog({super.key});

  /// The two actions' keys are the dialog shell's own (`AppDialog.actionKey`),
  /// named for this dialog's use of them: a `ValueKey` is equal by value, so
  /// these find exactly the buttons `AppDialog` keyed
  /// (`docs/design-language.md` §11).
  static final ValueKey<String> allOrgUnitsKey =
      AppDialog.actionKey('safety-incidents-filter-all');
  static final ValueKey<String> cancelKey =
      AppDialog.actionKey('safety-incidents-filter-cancel');

  /// Opens the filter over the register. `showDialog` builds its route under
  /// the Navigator, which is not a descendant of the route-scoped
  /// `BlocProvider<SafetyIncidentsBloc>` the Screen lives in — so that Bloc is
  /// handed across explicitly, the shape `NonconformanceOrgUnitFilterDialog.open`
  /// uses.
  static Future<void> open(BuildContext context, {String? siteId}) {
    final bloc = context.read<SafetyIncidentsBloc>();
    final peopleApi = context.read<PeopleApi>();
    final authGateway = context.read<AuthGateway>();
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => BlocProvider<SafetyIncidentsBloc>.value(
        value: bloc,
        child: BlocProvider<OrgUnitPickerBloc>(
          create: (_) => OrgUnitPickerBloc(
            peopleApi: peopleApi,
            authGateway: authGateway,
            initialSiteId: siteId,
          )..add(const OrgUnitPickerStarted()),
          child: const SafetyOrgUnitFilterDialog(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<SafetyIncidentsBloc>().state;
    final selectedId = state is SafetyIncidentsLoaded ? state.filters.orgUnitId : null;

    return AppDialog(
      title: l10n.commonFilterByOrgUnit,
      // One tree of names, at the width this dialog has always been: `decision`
      // is 420, the box the hand-sized `AlertDialog` used, so moving the shell
      // onto [AppDialog] changes nothing a reader feels. `picker` (460) is for
      // a dialog written for the tree, which this one is not.
      size: AppDialogSize.decision,
      // Clearing is this dialog's own act (the primary, right-most); Cancel is
      // the dismiss, which is what `Esc` runs.
      actions: [
        AppDialogAction(
          id: 'safety-incidents-filter-cancel',
          label: l10n.commonCancel,
          kind: AppDialogActionKind.dismiss,
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppDialogAction(
          id: 'safety-incidents-filter-all',
          label: l10n.commonAllOrgUnits,
          onPressed: () {
            context.read<SafetyIncidentsBloc>().add(const SafetyIncidentsFiltersCleared());
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
          title: l10n.commonNarrowTheRegister,
          description: l10n.safetyOrgUnitFilterChooseTheOrgUnitWhoseSafetyIncidents,
          onSelected: (node) {
            context.read<SafetyIncidentsBloc>().add(
                  SafetyIncidentsOrgUnitFilterSet(orgUnitId: node.id, name: node.name),
                );
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }
}
