/// Defining a meter on an Asset (issue #79): which Asset, a code and name, the
/// unit it counts in, and whether it is cumulative or a gauge.
///
/// CONTEXT.md's PM schedule entry is the point of the choice: only a
/// cumulative meter — an hour counter or a cycle count — can drive a schedule.
/// The unit is chosen from the baseline catalogue, never typed (ADR-0023).
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../platform/auth_gateway.dart';
import '../theme.dart';
import 'asset.dart';
import 'maintenance_api.dart';
import 'meter.dart';
import 'meters_bloc.dart';

class MeterFormDialog extends StatefulWidget {
  const MeterFormDialog({super.key, required this.siteId});

  /// The Site the list screen is already showing — the Asset dropdown lists
  /// only that Site's Assets.
  final String siteId;

  static const ValueKey<String> assetKey = ValueKey<String>('meter-form-asset');
  static const ValueKey<String> assetsFailedKey = ValueKey<String>('meter-form-assets-failed');
  static const ValueKey<String> codeKey = ValueKey<String>('meter-form-code');
  static const ValueKey<String> nameKey = ValueKey<String>('meter-form-name');
  static const ValueKey<String> uomKey = ValueKey<String>('meter-form-uom');
  static const ValueKey<String> uomFailedKey = ValueKey<String>('meter-form-uom-failed');
  static const ValueKey<String> typeKey = ValueKey<String>('meter-form-type');
  static const ValueKey<String> submitKey = ValueKey<String>('meter-form-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('meter-form-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('meter-form-failure');

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
    final theme = Theme.of(context);
    return BlocListener<MetersBloc, MetersState>(
      listener: _onMetersChanged,
      child: AlertDialog(
        title: const Text('Define a meter'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
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
                  decoration: const InputDecoration(
                    labelText: 'Code',
                    helperText: 'How this meter is known on the Asset, e.g. RUN-HRS.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: MeterFormDialog.nameKey,
                  controller: _name,
                  enabled: !_awaiting,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    border: OutlineInputBorder(),
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
                  decoration: const InputDecoration(
                    labelText: 'Kind of meter',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final type in MeterType.values)
                      DropdownMenuItem<MeterType>(value: type, child: Text(type.label)),
                  ],
                  onChanged: _awaiting ? null : (value) => setState(() => _type = value!),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: Spacing.xs),
                  child: Text(_type.explanation, style: theme.textTheme.bodySmall),
                ),
                if (_failure != null)
                  Padding(
                    key: MeterFormDialog.failureKey,
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
            key: MeterFormDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: MeterFormDialog.submitKey,
            onPressed: _complete && !_awaiting ? _submit : null,
            child: Text(_awaiting ? 'Saving…' : 'Define'),
          ),
        ],
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    switch (status) {
      case _LoadStatus.loading:
        return const SizedBox(
          height: 48,
          child: Center(
            child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        );
      case _LoadStatus.failed:
        return Column(
          key: MeterFormDialog.assetsFailedKey,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              failure ?? 'The Assets could not be read.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
            ),
            TextButton(onPressed: enabled ? onRetry : null, child: const Text('Try again')),
          ],
        );
      case _LoadStatus.ready:
        return DropdownButtonFormField<String>(
          key: MeterFormDialog.assetKey,
          initialValue: selectedId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Asset', border: OutlineInputBorder()),
          items: [
            for (final asset in assets)
              DropdownMenuItem<String>(value: asset.id, child: Text('${asset.name} (${asset.code})')),
          ],
          onChanged: enabled ? onChanged : null,
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
    final theme = Theme.of(context);
    switch (status) {
      case _LoadStatus.loading:
        return const SizedBox(
          height: 48,
          child: Center(
            child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        );
      case _LoadStatus.failed:
        return Column(
          key: MeterFormDialog.uomFailedKey,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              failure ?? 'The units of measure could not be read.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
            ),
            TextButton(onPressed: enabled ? onRetry : null, child: const Text('Try again')),
          ],
        );
      case _LoadStatus.ready:
        return DropdownButtonFormField<String>(
          key: MeterFormDialog.uomKey,
          initialValue: selectedCode,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Unit of measure',
            border: OutlineInputBorder(),
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
