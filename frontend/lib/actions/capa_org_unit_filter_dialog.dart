/// The CAPA list's Org Unit filter (issue #211): the tree, browsed one level at
/// a time, picking one Org Unit to narrow the investigations to — or clearing
/// back to every one of them.
///
/// The same shape `ActionOrgUnitFilterDialog` has, for the same reason: the
/// chooser is reused rather than re-drawn, and the two buttons a *filter* needs
/// (clear, cancel) are the two a form does not.
///
/// One difference, and it is the CAPA list's own scope: the Site picker is
/// shown (`showSitePicker` is left at its default), because a CAPA list is not
/// a Site's — reading one is platform-wide (ADR-0009), so a filter that could
/// only name an Org Unit in one Site would be hiding the rest of the plant by
/// accident. The picker offers the Sites first when there is more than one, and
/// the chosen Org Unit's own Site comes with it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/app_localizations.dart';
import '../maintenance/maintenance.dart';
import '../people/people.dart';
import '../people_api.dart';
import '../platform/auth_gateway.dart';
import '../widgets/app_dialog.dart';
import 'capas_bloc.dart';

class CapaOrgUnitFilterDialog extends StatelessWidget {
  const CapaOrgUnitFilterDialog({super.key});

  static final ValueKey<String> allOrgUnitsKey = AppDialog.actionKey('all-org-units');
  static final ValueKey<String> cancelKey = AppDialog.actionKey('cancel');

  /// Opens the filter over the list. `showDialog` builds its route under the
  /// Navigator, which is not a descendant of the route-scoped
  /// `BlocProvider<CapasBloc>` the Screen lives in — so that Bloc is handed
  /// across explicitly, the shape `ActionOrgUnitFilterDialog.open` uses.
  static Future<void> open(BuildContext context) {
    final capasBloc = context.read<CapasBloc>();
    final peopleApi = context.read<PeopleApi>();
    final authGateway = context.read<AuthGateway>();
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => BlocProvider<CapasBloc>.value(
        value: capasBloc,
        child: BlocProvider<OrgUnitPickerBloc>(
          create: (_) => OrgUnitPickerBloc(
            peopleApi: peopleApi,
            authGateway: authGateway,
          )..add(const OrgUnitPickerStarted()),
          child: const CapaOrgUnitFilterDialog(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<CapasBloc>().state;
    final selectedId = state is CapasLoaded ? state.orgUnitFilterId : null;

    return AppDialog(
      title: l10n.commonFilterByOrgUnit,
      // A picker: one thing chosen from a list (issue #398's four widths).
      size: AppDialogSize.picker,
      actions: [
        // Clearing is this dialog's own act (primary, and therefore last);
        // `Cancel` is the dismiss action `Esc` runs.
        AppDialogAction(
          id: 'all-org-units',
          label: l10n.commonAllOrgUnits,
          onPressed: () {
            context.read<CapasBloc>().add(const CapasOrgUnitFilterCleared());
            Navigator.of(context).pop();
          },
        ),
        AppDialogAction(
          id: 'cancel',
          label: l10n.commonCancel,
          kind: AppDialogActionKind.dismiss,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
      child: SizedBox(
        height: 420,
        child: OrgUnitChooser(
          selectedId: selectedId,
          title: l10n.workOrdersNarrowTitle,
          description: l10n.capaOrgUnitFilterChooseTheOrgUnitWhoseInvestigationsAnd,
          onSelected: (node) {
            context.read<CapasBloc>().add(
                  CapasOrgUnitFilterSelected(orgUnitId: node.id, orgUnitName: node.name),
                );
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }
}
