/// Defining a meter on an Asset (issue #79): which Asset, a code and name, the
/// unit it counts in, and whether it is cumulative or a gauge.
///
/// CONTEXT.md's PM schedule entry is the point of the choice: only a
/// cumulative meter — an hour counter or a cycle count — can drive a schedule.
/// The unit is chosen from the baseline catalogue, never typed (ADR-0023).
///
/// The form width (520): a searchable Asset, a code, a name, a unit and a kind
/// are five fields in one column and none has columns of its own, so it is a
/// form, not the wide dialog; the 560 this used to set inside an `AlertDialog`'s
/// content left the title and the action row at a width the platform chose.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/app_localizations.dart';
import '../platform/auth_gateway.dart';
import '../theme.dart';
import '../widgets/app_dialog.dart';
import '../widgets/app_search_field.dart';
import 'asset.dart';
import 'maintenance_api.dart';
import 'meter.dart';
import 'meters_bloc.dart';

class MeterFormDialog extends StatefulWidget {
  const MeterFormDialog({super.key, required this.siteId});

  /// The Site the list screen is already showing — the Asset dropdown lists
  /// only that Site's Assets.
  final String siteId;

  /// The Asset picker's own field name — the one string [assetKey] and
  /// [assetSuggestionKey] are both derived from, so neither can drift from
  /// what the field itself is built with (AGENTS.md §7).
  static const String _assetFieldName = 'meter-form-asset';

  /// The Asset picker's own `Key` (AGENTS.md §7). It was a
  /// `DropdownButtonFormField` until issue #190: a Site's whole register is a
  /// set nobody can scan, so the record is now found by typing rather than
  /// scrolled to (ADR-0023).
  static ValueKey<String> get assetKey => AppSearchField.fieldKey(_assetFieldName);

  /// One Asset suggestion row's own `Key`, keyed by the Asset's id
  /// (AGENTS.md §7).
  static ValueKey<String> assetSuggestionKey(String assetId) =>
      AppSearchField.suggestionKey(_assetFieldName, assetId);
  static const ValueKey<String> assetsFailedKey = ValueKey<String>('meter-form-assets-failed');
  static const ValueKey<String> codeKey = ValueKey<String>('meter-form-code');
  static const ValueKey<String> nameKey = ValueKey<String>('meter-form-name');
  static const ValueKey<String> uomKey = ValueKey<String>('meter-form-uom');
  static const ValueKey<String> uomFailedKey = ValueKey<String>('meter-form-uom-failed');
  static const ValueKey<String> typeKey = ValueKey<String>('meter-form-type');
  static const ValueKey<String> failureKey = ValueKey<String>('meter-form-failure');

  /// The two actions' keys are the shell's own (`AppDialog.actionKey`), named
  /// for this dialog's use of them: a `ValueKey` is equal by value, so these
  /// find exactly the buttons `AppDialog` keyed.
  static const String _submitId = 'meter-form-submit';
  static const String _cancelId = 'meter-form-cancel';
  static ValueKey<String> get submitKey => AppDialog.actionKey(_submitId);
  static ValueKey<String> get cancelKey => AppDialog.actionKey(_cancelId);

  static Future<void> open(BuildContext context, {required String siteId}) {
    final bloc = context.read<MetersBloc>();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => BlocProvider<MetersBloc>.value(
        value: bloc,
        child: MeterFormDialog(siteId: siteId),
      ),
    );
  }

  @override
  State<MeterFormDialog> createState() => _MeterFormDialogState();
}

enum _LoadStatus { loading, ready, failed }

class _MeterFormDialogState extends State<MeterFormDialog> {
  final TextEditingController _code = TextEditingController();
  final TextEditingController _name = TextEditingController();

  _LoadStatus _assetsStatus = _LoadStatus.loading;
  _LoadStatus _uomsStatus = _LoadStatus.loading;
  List<Asset> _assets = const [];
  List<UnitOfMeasure> _uoms = const [];
  String? _assetsFailure;
  String? _uomsFailure;

  String? _assetId;
  String? _uomCode;
  MeterType _type = MeterType.cumulative;

  bool _awaiting = false;
  String? _failure;

  @override
  void initState() {
    super.initState();
    _loadAssets();
    _loadUnits();
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _loadAssets() async {
    setState(() {
      _assetsStatus = _LoadStatus.loading;
      _assetsFailure = null;
    });
    final token = context.read<AuthGateway>().currentAccessToken;
    if (token == null) {
      setState(() {
        _assetsStatus = _LoadStatus.failed;
        _assetsFailure = MetersBloc.signedOutMessage;
      });
      return;
    }
    try {
      final assets = await context.read<MaintenanceApi>().fetchAssets(token, siteId: widget.siteId);
      if (!mounted) return;
      setState(() {
        _assets = assets;
        _assetsStatus = _LoadStatus.ready;
      });
    } on MaintenanceApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _assetsStatus = _LoadStatus.failed;
        _assetsFailure = error.message;
      });
    }
  }

  Future<void> _loadUnits() async {
    setState(() {
      _uomsStatus = _LoadStatus.loading;
      _uomsFailure = null;
    });
    final token = context.read<AuthGateway>().currentAccessToken;
    if (token == null) {
      setState(() {
        _uomsStatus = _LoadStatus.failed;
        _uomsFailure = MetersBloc.signedOutMessage;
      });
      return;
    }
    try {
      final uoms = await context.read<MaintenanceApi>().fetchUnitsOfMeasure(token);
      if (!mounted) return;
      setState(() {
        _uoms = uoms;
        _uomsStatus = _LoadStatus.ready;
      });
    } on MaintenanceApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _uomsStatus = _LoadStatus.failed;
        _uomsFailure = error.message;
      });
    }
  }

  bool get _complete =>
      _assetId != null &&
      _code.text.trim().isNotEmpty &&
      _name.text.trim().isNotEmpty &&
      _uomCode != null;

  void _submit() {
    if (!_complete || _awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    context.read<MetersBloc>().add(
      MeterCreateConfirmed(
        assetId: _assetId!,
        code: _code.text.trim(),
        name: _name.text.trim(),
        uomCode: _uomCode!,
        meterType: _type.wire,
      ),
    );
  }

  void _onMetersChanged(BuildContext context, MetersState state) {
    if (!_awaiting || state is! MetersLoaded || state.isMutating) return;
    if (state.mutationFailure != null) {
      setState(() {
        _awaiting = false;
        _failure = state.mutationFailure;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final l10n = AppLocalizations.of(context);
    return BlocListener<MetersBloc, MetersState>(
      listener: _onMetersChanged,
      child: AppDialog(
        title: l10n.metersDefine,
        size: AppDialogSize.form,
        actions: [
          AppDialogAction(
            id: MeterFormDialog._cancelId,
            label: l10n.commonCancel,
            kind: AppDialogActionKind.dismiss,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
          ),
          AppDialogAction(
            id: MeterFormDialog._submitId,
            label: _awaiting ? l10n.commonSaving : l10n.meterFormSubmit,
            onPressed: _complete && !_awaiting ? _submit : null,
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _AssetField(
              status: _assetsStatus,
              assets: _assets,
              failure: _assetsFailure,
              selectedId: _assetId,
              enabled: !_awaiting,
              onRetry: _loadAssets,
              onChanged: (id) => setState(() => _assetId = id),
            ),
            const SizedBox(height: Spacing.md),
            TextField(
              key: MeterFormDialog.codeKey,
              controller: _code,
              enabled: !_awaiting,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: l10n.commonCode,
                helperText: l10n.meterFormCodeHelp,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: Spacing.md),
            TextField(
              key: MeterFormDialog.nameKey,
              controller: _name,
              enabled: !_awaiting,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: l10n.commonName,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: Spacing.md),
            _UomField(
              status: _uomsStatus,
              uoms: _uoms,
              failure: _uomsFailure,
              selectedCode: _uomCode,
              enabled: !_awaiting,
              onRetry: _loadUnits,
              onChanged: (code) => setState(() => _uomCode = code),
            ),
            const SizedBox(height: Spacing.md),
            DropdownButtonFormField<MeterType>(
              key: MeterFormDialog.typeKey,
              initialValue: _type,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.meterFormType,
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final type in MeterType.values)
                  DropdownMenuItem<MeterType>(value: type, child: Text(type.label)),
              ],
              onChanged: _awaiting ? null : (value) => setState(() => _type = value!),
            ),
            Padding(
              padding: const EdgeInsets.only(top: Spacing.xs),
              child: Text(
                _type.explanation,
                style: AppTypography.dense(context)?.copyWith(color: palette.textMuted),
              ),
            ),
            if (_failure != null)
              Padding(
                key: MeterFormDialog.failureKey,
                padding: const EdgeInsets.only(top: Spacing.md),
                child: Text(
                  _failure!,
                  style: AppTypography.dense(context)?.copyWith(color: palette.statusDanger),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AssetField extends StatelessWidget {
  const _AssetField({
    required this.status,
    required this.assets,
    required this.failure,
    required this.selectedId,
    required this.enabled,
    required this.onRetry,
    required this.onChanged,
  });

  final _LoadStatus status;
  final List<Asset> assets;
  final String? failure;
  final String? selectedId;
  final bool enabled;
  final VoidCallback onRetry;
  final ValueChanged<String?> onChanged;

  /// The Asset the dialog's own id currently names, or null — the dialog
  /// keeps holding the `String?` id its submit body already reads, while the
  /// picker is controlled by the record itself, so this is how the two agree.
  Asset? get _selected {
    for (final asset in assets) {
      if (asset.id == selectedId) return asset;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final l10n = AppLocalizations.of(context);
    switch (status) {
      case _LoadStatus.loading:
        return const SizedBox(
          height: 48,
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      case _LoadStatus.failed:
        return Column(
          key: MeterFormDialog.assetsFailedKey,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              failure ?? l10n.commonAssetsFailed,
              style: AppTypography.dense(context)?.copyWith(color: palette.statusDanger),
            ),
            TextButton(onPressed: enabled ? onRetry : null, child: Text(l10n.commonTryAgain)),
          ],
        );
      case _LoadStatus.ready:
        return AppSearchField<Asset>(
          name: MeterFormDialog._assetFieldName,
          label: l10n.commonAsset,
          value: _selected,
          enabled: enabled,
          // A pick sets the dialog's own id; typing over the chosen Asset
          // retires it, so this form can never submit an id its own field has
          // stopped showing (ADR-0023 point 4).
          onChanged: (asset) => onChanged(asset?.id),
          onSelected: (asset) => onChanged(asset.id),
          // A dumb in-memory filter over the register `initState` already
          // read — no HTTP request of its own, so the field's per-term
          // debounce never reaches the wire (ADR-0023). Matched on the two
          // fields that identify an Asset: its name and its code.
          fetchSuggestions: (term) async {
            final lower = term.toLowerCase();
            return [
              for (final asset in assets)
                if (asset.name.toLowerCase().contains(lower) ||
                    asset.code.toLowerCase().contains(lower))
                  asset,
            ];
          },
          suggestionBuilder: (context, asset) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm),
            child: Text('${asset.name} (${asset.code})'),
          ),
          idOf: (asset) => asset.id,
          displayStringFor: (asset) => '${asset.name} (${asset.code})',
        );
    }
  }
}

class _UomField extends StatelessWidget {
  const _UomField({
    required this.status,
    required this.uoms,
    required this.failure,
    required this.selectedCode,
    required this.enabled,
    required this.onRetry,
    required this.onChanged,
  });

  final _LoadStatus status;
  final List<UnitOfMeasure> uoms;
  final String? failure;
  final String? selectedCode;
  final bool enabled;
  final VoidCallback onRetry;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final l10n = AppLocalizations.of(context);
    switch (status) {
      case _LoadStatus.loading:
        return const SizedBox(
          height: 48,
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      case _LoadStatus.failed:
        return Column(
          key: MeterFormDialog.uomFailedKey,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              failure ?? l10n.meterFormUomFailed,
              style: AppTypography.dense(context)?.copyWith(color: palette.statusDanger),
            ),
            TextButton(onPressed: enabled ? onRetry : null, child: Text(l10n.commonTryAgain)),
          ],
        );
      case _LoadStatus.ready:
        return DropdownButtonFormField<String>(
          key: MeterFormDialog.uomKey,
          initialValue: selectedCode,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: l10n.commonUnitOfMeasure,
            border: const OutlineInputBorder(),
          ),
          items: [
            for (final uom in uoms)
              DropdownMenuItem<String>(value: uom.code, child: Text(uom.label)),
          ],
          onChanged: enabled ? onChanged : null,
        );
    }
  }
}
