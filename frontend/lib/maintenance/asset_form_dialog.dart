/// Adding an Asset: what it is called, what kind of thing it is, how critical
/// it is, and — the decision that outlives all the others — where it sits.
///
/// The Org Unit half is `OrgUnitChooser`, driven by a dialog-scoped
/// `OrgUnitPickerBloc` built here and read once, at submission. Same shape as
/// `AdmissionDialog`'s use of the Grant picker: widget and Bloc travel
/// together, and neither outlives the dialog that mounted them.
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

class AssetFormDialog extends StatefulWidget {
  const AssetFormDialog({super.key});

  static const ValueKey<String> codeKey = ValueKey<String>('asset-form-code');
  static const ValueKey<String> nameKey = ValueKey<String>('asset-form-name');
  static const ValueKey<String> typeKey = ValueKey<String>('asset-form-type');
  static const ValueKey<String> criticalityKey = ValueKey<String>('asset-form-criticality');
  static const ValueKey<String> submitKey = ValueKey<String>('asset-form-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('asset-form-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('asset-form-failure');
  static const ValueKey<String> chosenKey = ValueKey<String>('asset-form-chosen');

  /// Opens the form over the register. `showDialog` builds its route under the
  /// Navigator, which is not a descendant of the route-scoped `BlocProvider`
  /// the register lives in — so the Bloc is handed across explicitly.
  ///
  /// The chooser opens on the Site the register is already showing, so the
  /// caller does not have to re-find where they were.
  static Future<void> open(BuildContext context, {String? siteId}) {
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
              initialSiteId: siteId,
            )..add(const OrgUnitPickerStarted()),
          ),
        ],
        child: const AssetFormDialog(),
      ),
    );
  }

  @override
  State<AssetFormDialog> createState() => _AssetFormDialogState();
}

class _AssetFormDialogState extends State<AssetFormDialog> {
  final TextEditingController _code = TextEditingController();
  final TextEditingController _name = TextEditingController();

  /// Null until chosen — never defaulted, so "a kind was chosen" is not true
  /// without anybody choosing it. Criticality is the exception and defaults to
  /// medium, matching the column's own DEFAULT.
  AssetType? _type;
  Criticality _criticality = Criticality.medium;
  OrgUnitNode? _orgUnit;

  bool _awaiting = false;
  String? _failure;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  bool get _complete =>
      _code.text.trim().isNotEmpty &&
      _name.text.trim().isNotEmpty &&
      _type != null &&
      _orgUnit != null;

  void _submit() {
    if (!_complete || _awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    context.read<AssetsBloc>().add(
          AssetAddConfirmed(
            orgUnitId: _orgUnit!.id,
            code: _code.text.trim(),
            name: _name.text.trim(),
            assetType: _type!.wire,
            criticality: _criticality.wire,
          ),
        );
  }

  void _onAssetsChanged(BuildContext context, AssetsState state) {
    if (!_awaiting || state is! AssetsLoaded || state.isAdding) return;
    if (state.addFailure != null) {
      setState(() {
        _awaiting = false;
        _failure = state.addFailure;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  // A chosen Org Unit belongs to the Site it was chosen in, so switching the
  // chooser to a different Site necessarily discards it — keeping it would
  // submit an Asset to a Site the caller is no longer looking at, with the
  // "will sit at" line and a live-looking submit button both lying about it.
  void _onOrgUnitSiteChanged(BuildContext context, OrgUnitPickerState state) {
    setState(() => _orgUnit = null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MultiBlocListener(
      listeners: [
        BlocListener<AssetsBloc, AssetsState>(listener: _onAssetsChanged),
        BlocListener<OrgUnitPickerBloc, OrgUnitPickerState>(
          listenWhen: (previous, current) => previous.siteId != current.siteId,
          listener: _onOrgUnitSiteChanged,
        ),
      ],
      child: AlertDialog(
        title: const Text('Add an Asset'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: AssetFormDialog.codeKey,
                  controller: _code,
                  enabled: !_awaiting,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Code',
                    helperText: 'Unique across the whole Platform, not just this Site.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: AssetFormDialog.nameKey,
                  controller: _name,
                  enabled: !_awaiting,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
                ),
                const SizedBox(height: Spacing.md),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<AssetType>(
                        key: AssetFormDialog.typeKey,
                        initialValue: _type,
                        decoration: const InputDecoration(
                          labelText: 'Kind',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final type in AssetType.values)
                            DropdownMenuItem<AssetType>(value: type, child: Text(type.label)),
                        ],
                        onChanged: _awaiting ? null : (value) => setState(() => _type = value),
                      ),
                    ),
                    const SizedBox(width: Spacing.md),
                    Expanded(
                      child: DropdownButtonFormField<Criticality>(
                        key: AssetFormDialog.criticalityKey,
                        initialValue: _criticality,
                        decoration: const InputDecoration(
                          labelText: 'Criticality',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final level in Criticality.values)
                            DropdownMenuItem<Criticality>(value: level, child: Text(level.label)),
                        ],
                        onChanged: _awaiting
                            ? null
                            : (value) => setState(() => _criticality = value ?? _criticality),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Spacing.lg),
                OrgUnitChooser(
                  selectedId: _orgUnit?.id,
                  enabled: !_awaiting,
                  onSelected: (node) => setState(() => _orgUnit = node),
                ),
                if (_orgUnit != null)
                  Padding(
                    key: AssetFormDialog.chosenKey,
                    padding: const EdgeInsets.only(top: Spacing.sm),
                    child: Text(
                      'This Asset will sit at ${_orgUnit!.name}.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                if (_failure != null)
                  Padding(
                    key: AssetFormDialog.failureKey,
                    padding: const EdgeInsets.only(top: Spacing.md),
                    child: Text(
                      _failure!,
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            key: AssetFormDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: AssetFormDialog.submitKey,
            onPressed: _complete && !_awaiting ? _submit : null,
            child: const Text('Add Asset'),
          ),
        ],
      ),
    );
  }
}
