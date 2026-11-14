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

import '../l10n/app_localizations.dart';
import '../maintenance/maintenance.dart';
import '../people/people.dart';
import '../people_api.dart';
import '../platform/auth_gateway.dart';
import '../widgets/app_dialog.dart';
import 'actions_bloc.dart';

class ActionEscalatedToFilterDialog extends StatelessWidget {
  const ActionEscalatedToFilterDialog({super.key});

  static final ValueKey<String> anyoneKey = AppDialog.actionKey('anyone');
  static final ValueKey<String> cancelKey = AppDialog.actionKey('cancel');

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
    final l10n = AppLocalizations.of(context);
    final state = context.watch<ActionsBloc>().state;
    final selectedId = state is ActionsLoaded ? state.escalatedToOrgUnitFilterId : null;

    return AppDialog(
      title: l10n.actionEscalatedToFilterFilterByWhatWasHandedUp,
      // A picker, at the same width as the Org Unit filter beside it: the two
      // are the same question about different columns (issue #398).
      size: AppDialogSize.picker,
      actions: [
        // Clearing is this dialog's own act (primary, and therefore last);
        // `Cancel` is the dismiss action `Esc` runs.
        AppDialogAction(
          id: 'anyone',
          label: l10n.actionEscalatedToFilterAnyone,
          onPressed: () {
            context.read<ActionsBloc>().add(const ActionsEscalatedToFilterCleared());
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
          showSitePicker: false,
          title: l10n.actionEscalatedToFilterWhoseQueue,
          description: l10n.actionEscalatedToFilterChooseTheOrgUnitThatConcernsWere,
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
    );
  }
}
