/// The tier board's Org Unit filter (issue #76): a Site's tree, browsed one
/// level at a time, picking one Org Unit to narrow the rollup to — or clearing
/// back to the whole Site.
///
/// Drives `OrgUnitPickerBloc` — the same state machine the Asset form's own
/// `OrgUnitChooser` already browses — rather than writing a second tree Bloc.
/// The chooser itself is reused, not re-drawn: it is already a single-select
/// view with no Granted set, and a filter is exactly that. The two buttons this
/// dialog adds are the ones a filter needs and a form does not: "All Org Units"
/// to clear, and Cancel to leave the choice as it was.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../people/people.dart';
import '../people_api.dart';
import '../platform/auth_gateway.dart';
import '../widgets/app_dialog.dart';
import 'org_unit_chooser.dart';
import 'tier_board_bloc.dart';

class TierBoardOrgUnitFilterDialog extends StatelessWidget {
  const TierBoardOrgUnitFilterDialog({super.key});

  /// The two actions' keys are the shell's own (`AppDialog.actionKey`), named
  /// for this dialog's use of them: a `ValueKey` is equal by value, so these
  /// find exactly the buttons `AppDialog` keyed (`docs/design-language.md` §11).
  static const String _allOrgUnitsId = 'all-org-units';
  static const String _cancelId = 'tier-board-org-unit-filter-cancel';
  static ValueKey<String> get allOrgUnitsKey => AppDialog.actionKey(_allOrgUnitsId);
  static ValueKey<String> get cancelKey => AppDialog.actionKey(_cancelId);

  /// Opens the filter over the board. `showDialog` builds its route under the
  /// Navigator, which is not a descendant of the route-scoped
  /// `BlocProvider<TierBoardBloc>` the Screen lives in — so that Bloc is handed
  /// across explicitly, the same shape `DirectoryOrgUnitFilterDialog.open`
  /// uses for its own list.
  static Future<void> open(BuildContext context) {
    final boardBloc = context.read<TierBoardBloc>();
    final peopleApi = context.read<PeopleApi>();
    final authGateway = context.read<AuthGateway>();
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => BlocProvider<TierBoardBloc>.value(
        value: boardBloc,
        child: BlocProvider<OrgUnitPickerBloc>(
          create: (_) => OrgUnitPickerBloc(peopleApi: peopleApi, authGateway: authGateway)
            ..add(const OrgUnitPickerStarted()),
          child: const TierBoardOrgUnitFilterDialog(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TierBoardBloc>().state;
    final selectedId = state is TierBoardLoaded ? state.orgUnitFilterId : null;

    // The picker width (460): one tree to choose a single Org Unit from (§11).
    return AppDialog(
      title: 'Filter by Org Unit',
      size: AppDialogSize.picker,
      actions: [
        AppDialogAction(
          id: _cancelId,
          label: 'Cancel',
          kind: AppDialogActionKind.dismiss,
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppDialogAction(
          id: _allOrgUnitsId,
          label: 'All Org Units',
          onPressed: () {
            context.read<TierBoardBloc>().add(const TierBoardOrgUnitFilterCleared());
            Navigator.of(context).pop();
          },
        ),
      ],
      child: SizedBox(
        height: 420,
        child: OrgUnitChooser(
          selectedId: selectedId,
          title: 'Narrow the board',
          description: 'Choose the Org Unit whose numbers and everything beneath it you want '
              'to read, or clear back to the whole Site.',
          onSelected: (node) {
            context.read<TierBoardBloc>().add(
                  TierBoardOrgUnitFilterSelected(orgUnitId: node.id, orgUnitName: node.name),
                );
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }
}
