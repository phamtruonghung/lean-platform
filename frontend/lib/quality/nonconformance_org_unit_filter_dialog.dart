/// The register's Org Unit filter (issue #205): a Site's tree, browsed one
/// level at a time, picking one Org Unit to narrow the register to — or
/// clearing back to the whole Site.
///
/// The same shape `ActionOrgUnitFilterDialog` has, for the same reason: the
/// chooser is reused rather than re-drawn, and the two buttons a *filter*
/// needs (clear, cancel) are the two a form does not.
///
/// Narrowing to an Org Unit includes everything beneath it — the ticket's own
/// criterion, and what "everything under Line 3" means in this Platform. That
/// is the server's ltree walk, not a filter the client applies.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/app_localizations.dart';
import '../maintenance/maintenance.dart';
import '../people/people.dart';
import '../people_api.dart';
import '../platform/auth_gateway.dart';
import '../widgets/app_dialog.dart';
import 'nonconformances_bloc.dart';

class NonconformanceOrgUnitFilterDialog extends StatelessWidget {
  const NonconformanceOrgUnitFilterDialog({super.key});

  static final ValueKey<String> allOrgUnitsKey =
      AppDialog.actionKey('nonconformances-filter-all');
  static final ValueKey<String> cancelKey = AppDialog.actionKey('nonconformances-filter-cancel');

  /// Opens the filter over the register. `showDialog` builds its route under
  /// the Navigator, which is not a descendant of the route-scoped
  /// `BlocProvider<NonconformancesBloc>` the Screen lives in — so that Bloc is
  /// handed across explicitly, the shape `ActionOrgUnitFilterDialog.open`
  /// uses.
  ///
  /// The picker opens on the Site the register is showing, so a caller does
  /// not have to re-find where they were: the filter may only name an Org Unit
  /// in the Site already on screen.
  static Future<void> open(BuildContext context, {String? siteId}) {
    final bloc = context.read<NonconformancesBloc>();
    final peopleApi = context.read<PeopleApi>();
    final authGateway = context.read<AuthGateway>();
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => BlocProvider<NonconformancesBloc>.value(
        value: bloc,
        child: BlocProvider<OrgUnitPickerBloc>(
          create: (_) => OrgUnitPickerBloc(
            peopleApi: peopleApi,
            authGateway: authGateway,
            initialSiteId: siteId,
          )..add(const OrgUnitPickerStarted()),
          child: const NonconformanceOrgUnitFilterDialog(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<NonconformancesBloc>().state;
    final selectedId = state is NonconformancesLoaded ? state.filters.orgUnitId : null;

    return AppDialog(
      title: l10n.commonFilterByOrgUnit,
      size: AppDialogSize.decision,
      // Clearing is this dialog's own act (the primary, right-most); Cancel is
      // the dismiss, which is what `Esc` runs.
      actions: [
        AppDialogAction(
          id: 'nonconformances-filter-cancel',
          label: l10n.commonCancel,
          kind: AppDialogActionKind.dismiss,
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppDialogAction(
          id: 'nonconformances-filter-all',
          label: l10n.commonAllOrgUnits,
          onPressed: () {
            context.read<NonconformancesBloc>().add(const NonconformancesFiltersCleared());
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
          // The register is one Site's, so the chooser may not name an Org Unit
          // in another one.
          showSitePicker: false,
          title: l10n.commonNarrowTheRegister,
          description: l10n.nonconformanceOrgUnitFilterChooseTheOrgUnitWhoseNonConformances,
          onSelected: (node) {
            context.read<NonconformancesBloc>().add(
                  NonconformancesOrgUnitFilterSet(orgUnitId: node.id, name: node.name),
                );
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }
}
