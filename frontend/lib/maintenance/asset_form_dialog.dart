/// Adding an Asset (what it is called, what kind of thing it is, how critical
/// it is, and — the decision that outlives all the others — where it sits) or
/// correcting one (issue #173): [asset] decides which, the same shape
/// `SiteFormDialog` uses for correcting a Site — null creates, an Asset
/// corrects, seeding every field from its stored values.
///
/// The Org Unit half is `OrgUnitChooser`, driven by a dialog-scoped
/// `OrgUnitPickerBloc` built here and read once, at submission — only when
/// adding. A correction carries no Org Unit chooser at all: where an Asset
/// sits is its own action with its own two-Org-Unit rule (issue #171,
/// `AssetMoveDialog`), and offering it here would mean a save that has to
/// send two requests with a possible half-applied outcome, which is exactly
/// what the route's one-operation rule (issue #61 review, Fix A) exists to
/// prevent. This dialog says so in one line instead, pointing at the
/// register's own "Change Org Unit…" action.
///
/// The four field controls are shared between both paths on purpose (issue
/// #173, user story 22) — one `TextField`/`DropdownButtonFormField` set, not
/// two copies that could drift apart in labels, options or validation.
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
  const AssetFormDialog({super.key, this.asset});

  /// The Asset being corrected, or null when adding one (issue #173). Its
  /// stored values seed the four fields.
  final Asset? asset;

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
  /// [asset] present opens in correction mode (issue #173): no
  /// `OrgUnitPickerBloc` is built at all, since a correction offers no Org
  /// Unit chooser. Absent, this opens to add, and the chooser opens on the
  /// Site the register is already showing, so the caller does not have to
  /// re-find where they were.
  static Future<void> open(BuildContext context, {String? siteId, Asset? asset}) {
    final assetsBloc = context.read<AssetsBloc>();
    if (asset != null) {
      return showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => BlocProvider<AssetsBloc>.value(
          value: assetsBloc,
          child: AssetFormDialog(asset: asset),
        ),
      );
    }
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

  /// Whether this dialog is correcting an existing Asset rather than adding
  /// one (issue #173) — read once, off the widget the dialog was built with,
  /// so every branch below reads the same test [widget.asset] does.
  bool get _isCorrecting => widget.asset != null;

  @override
  void initState() {
    super.initState();
    final asset = widget.asset;
    if (asset != null) {
      _code.text = asset.code;
      _name.text = asset.name;
      for (final type in AssetType.values) {
        if (type.wire == asset.assetType) _type = type;
      }
      for (final level in Criticality.values) {
        if (level.wire == asset.criticality) _criticality = level;
      }
    }
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  bool get _complete {
    final fieldsComplete =
        _code.text.trim().isNotEmpty && _name.text.trim().isNotEmpty && _type != null;
    // A correction carries no Org Unit chooser at all (issue #173) — where
    // an Asset sits stays exactly as it was, so nothing here waits on
    // `_orgUnit`, unlike the add path.
    return _isCorrecting ? fieldsComplete : fieldsComplete && _orgUnit != null;
  }

  void _submit() {
    if (!_complete || _awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    final asset = widget.asset;
    if (asset == null) {
      context.read<AssetsBloc>().add(
            AssetAddConfirmed(
              orgUnitId: _orgUnit!.id,
              code: _code.text.trim(),
              name: _name.text.trim(),
              assetType: _type!.wire,
              criticality: _criticality.wire,
            ),
          );
    } else {
      context.read<AssetsBloc>().add(
            AssetCorrectionConfirmed(
              assetId: asset.id,
              code: _code.text.trim(),
              name: _name.text.trim(),
              assetType: _type!.wire,
              criticality: _criticality.wire,
            ),
          );
    }
  }

  void _onAssetsChanged(BuildContext context, AssetsState state) {
    if (!_awaiting || state is! AssetsLoaded) return;
    final asset = widget.asset;
    if (asset == null) {
      if (state.isAdding) return;
      if (state.addFailure != null) {
        setState(() {
          _awaiting = false;
          _failure = state.addFailure;
        });
        return;
      }
    } else {
      // The row's own mutation-in-flight marker covers "still running" —
      // no dedicated flag for a correction, the same reuse issue #173's own
      // Implementation Decisions call for.
      if (state.mutatingAssetId == asset.id) return;
      if (state.correctionFailure != null) {
        setState(() {
          _awaiting = false;
          _failure = state.correctionFailure;
        });
        return;
      }
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
        // No `OrgUnitPickerBloc` exists at all in correction mode (`open`
        // never builds one — a correction offers no Org Unit chooser), so
        // this listener is skipped rather than reaching for a provider that
        // is not there.
        if (!_isCorrecting)
          BlocListener<OrgUnitPickerBloc, OrgUnitPickerState>(
            listenWhen: (previous, current) => previous.siteId != current.siteId,
            listener: _onOrgUnitSiteChanged,
          ),
      ],
      child: AlertDialog(
        title: Text(_isCorrecting ? 'Correct details' : 'Add an Asset'),
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
                if (_isCorrecting)
                  // No Org Unit chooser here (issue #173): where an Asset
                  // sits is its own action, with its own two-Org-Unit rule
                  // (issue #171) and its own transaction — this dialog only
                  // ever carries one.
                  Text(
                    'Where this Asset sits is changed with its own "Change Org Unit…" action.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  )
                else ...[
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
                ],
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
            child: Text(_awaiting ? 'Saving…' : (_isCorrecting ? 'Save' : 'Add Asset')),
          ),
        ],
      ),
    );
  }
}
