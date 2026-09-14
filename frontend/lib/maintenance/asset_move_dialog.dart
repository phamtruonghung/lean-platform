/// Changing where an Asset sits (issue #171): the one thing the register set
/// at creation and could not correct afterwards.
///
/// The Org Unit half is `OrgUnitChooser`, driven by a dialog-scoped
/// `OrgUnitPickerBloc` built here — the same pairing `AssetFormDialog` uses for
/// placing a new Asset, and neither the widget nor the Bloc outlives the
/// dialog that mounted them.
///
/// What this dialog does *not* do is wait for the server. The move is
/// dispatched and the dialog closes; the register's own notice line reports
/// what happened, exactly as it already does for retiring and for nesting. A
/// refusal here is a Grant problem — the caller's reach does not cover both
/// Org Units — and picking a different Org Unit inside this dialog would not
/// fix it, so there is nothing for a staying-open form to offer.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../people/people.dart';
import '../people_api.dart';
import '../platform/auth_gateway.dart';
import '../theme.dart';
import 'asset.dart';
import 'assets_bloc.dart';
import 'org_unit_chooser.dart';

class AssetMoveDialog extends StatefulWidget {
  const AssetMoveDialog({super.key, required this.asset});

  /// The Asset whose placement is being changed. The dialog does not edit it —
  /// the Bloc owns the row — but it names where the Asset sits now, so the
  /// caller can see what is about to change.
  final Asset asset;

  static const ValueKey<String> chosenKey = ValueKey<String>('asset-move-chosen');
  static const ValueKey<String> submitKey = ValueKey<String>('asset-move-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('asset-move-cancel');

  /// Opens the dialog over the register. `showDialog` builds its route under
  /// the Navigator, which is not a descendant of the route-scoped
  /// `BlocProvider` the register lives in — so the Bloc is handed across
  /// explicitly, the same reason `AssetFormDialog.open` does it.
  ///
  /// The chooser opens on the Site the **Asset** sits at rather than the one
  /// the register happens to be showing: the question is where this machine
  /// goes next, and it starts from where the machine is.
  static Future<void> open(BuildContext context, {required Asset asset}) {
    final assetsBloc = context.read<AssetsBloc>();
    final peopleApi = context.read<PeopleApi>();
    final authGateway = context.read<AuthGateway>();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => MultiBlocProvider(
        providers: [
          BlocProvider<AssetsBloc>.value(value: assetsBloc),
          BlocProvider<OrgUnitPickerBloc>(
            create: (_) => OrgUnitPickerBloc(
              peopleApi: peopleApi,
              authGateway: authGateway,
              initialSiteId: asset.siteId,
            )..add(const OrgUnitPickerStarted()),
          ),
        ],
        child: AssetMoveDialog(asset: asset),
      ),
    );
  }

  @override
  State<AssetMoveDialog> createState() => _AssetMoveDialogState();
}

class _AssetMoveDialogState extends State<AssetMoveDialog> {
  OrgUnitNode? _chosen;

  /// Where it already sits is not somewhere it can move to. A move to the same
  /// Org Unit would ask the server for nothing it does not already have, so
  /// the submit stays disabled until the choice differs — the same "a value
  /// somebody has to choose" discipline the create form applies, minus the
  /// pointless round trip.
  bool get _complete => _chosen != null && _chosen!.id != widget.asset.orgUnitId;

  void _submit() {
    if (!_complete) return;
    context.read<AssetsBloc>().add(
          AssetOrgUnitChanged(assetId: widget.asset.id, orgUnitId: _chosen!.id),
        );
    Navigator.of(context).pop();
  }

  /// A chosen Org Unit belongs to the Site it was chosen in, so browsing to a
  /// different Site discards it — the rule `AssetFormDialog` already applies,
  /// and for the same reason: leaving it would let the "will sit at" line
  /// describe a choice the caller has browsed away from, with a live-looking
  /// submit button behind it.
  void _onSiteChanged(BuildContext context, OrgUnitPickerState state) {
    setState(() => _chosen = null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MultiBlocListener(
      listeners: [
        BlocListener<OrgUnitPickerBloc, OrgUnitPickerState>(
          listenWhen: (previous, current) => previous.siteId != current.siteId,
          listener: _onSiteChanged,
        ),
      ],
      child: AlertDialog(
        title: const Text('Change where this Asset sits'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${widget.asset.name} (${widget.asset.code}) sits at '
                  '${widget.asset.orgUnitName} now.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: Spacing.lg),
                OrgUnitChooser(
                  // The Org Unit it is at is shown as the standing choice, so
                  // the tree reads as "this one, or another".
                  selectedId: widget.asset.orgUnitId,
                  title: 'Move it to',
                  description: 'Where this Asset will sit. It decides who may '
                      'raise and close work against it; work already recorded '
                      'against it stays where it happened.',
                  onSelected: (node) => setState(() => _chosen = node),
                ),
                if (_chosen != null)
                  Padding(
                    key: AssetMoveDialog.chosenKey,
                    padding: const EdgeInsets.only(top: Spacing.sm),
                    child: Text(
                      'This Asset will sit at ${_chosen!.name}.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            key: AssetMoveDialog.cancelKey,
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: AssetMoveDialog.submitKey,
            onPressed: _complete ? _submit : null,
            child: const Text('Change Org Unit'),
          ),
        ],
      ),
    );
  }
}
