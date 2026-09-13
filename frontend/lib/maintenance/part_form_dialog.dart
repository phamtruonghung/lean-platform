/// Adding a Part to the shared catalogue (issue #80): `POST
/// /api/maintenance/parts`, administrator only (inventory-routes.js).
///
/// The unit of measure is a value with a known set, so it is *chosen* from
/// the existing `units_of_measure` catalogue, never typed (ADR-0023): this
/// dialog fetches the list once when it opens, and a list it cannot fetch
/// blocks submission rather than falling back to free text.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../platform/auth_gateway.dart';
import '../theme.dart';
import '../widgets/failure_state.dart';
import 'maintenance_api.dart';
import 'part.dart';
import 'parts_bloc.dart';

class PartFormDialog extends StatefulWidget {
  const PartFormDialog({super.key});

  static const ValueKey<String> partNoKey = ValueKey<String>('part-form-part-no');
  static const ValueKey<String> descriptionKey = ValueKey<String>('part-form-description');
  static const ValueKey<String> uomKey = ValueKey<String>('part-form-uom');
  static const ValueKey<String> submitKey = ValueKey<String>('part-form-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('part-form-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('part-form-failure');
  static const ValueKey<String> unitsFailedKey = ValueKey<String>('part-form-units-failed');
  static const ValueKey<String> unitsRetryKey = ValueKey<String>('part-form-units-retry');

  /// Opens the form over the catalogue. `showDialog` builds its route under
  /// the Navigator, which is not a descendant of the route-scoped
  /// `BlocProvider<PartsBloc>` the Screen lives in — so that Bloc is handed
  /// across explicitly, the same device every other dialog in this Module uses.
  static Future<void> open(BuildContext context) {
    final bloc = context.read<PartsBloc>();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => BlocProvider<PartsBloc>.value(
        value: bloc,
        child: const PartFormDialog(),
      ),
    );
  }

  @override
  State<PartFormDialog> createState() => _PartFormDialogState();
}

class _PartFormDialogState extends State<PartFormDialog> {
  final TextEditingController _partNo = TextEditingController();
  final TextEditingController _description = TextEditingController();
  String? _uomCode;

  bool _loadingUnits = true;
  String? _unitsFailure;
  List<UnitOfMeasure> _units = const [];

  bool _awaiting = false;
  String? _failure;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadUnits());
  }

  @override
  void dispose() {
    _partNo.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _loadUnits() async {
    final token = context.read<AuthGateway>().currentAccessToken;
    if (token == null) {
      setState(() {
        _loadingUnits = false;
        _unitsFailure = 'This session has ended. Sign in again to continue.';
      });
      return;
    }
    setState(() {
      _loadingUnits = true;
      _unitsFailure = null;
    });
    try {
      final units = await context.read<MaintenanceApi>().fetchUnitsOfMeasure(token);
      if (!mounted) return;
      setState(() {
        _units = units;
        _uomCode = units.any((unit) => unit.code == _uomCode) ? _uomCode : null;
        _loadingUnits = false;
      });
    } on MaintenanceApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingUnits = false;
        _unitsFailure = error.message;
      });
    }
  }

  bool get _complete =>
      _partNo.text.trim().isNotEmpty && _description.text.trim().isNotEmpty && _uomCode != null;

  void _submit() {
    if (!_complete || _awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    context.read<PartsBloc>().add(
          PartAddConfirmed(
            partNo: _partNo.text.trim(),
            description: _description.text.trim(),
            uomCode: _uomCode!,
          ),
        );
  }

  void _onPartsChanged(BuildContext context, PartsState state) {
    if (!_awaiting || state is! PartsLoaded || state.isAdding) return;
    if (state.addFailure != null) {
      setState(() {
        _awaiting = false;
        _failure = state.addFailure;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BlocListener<PartsBloc, PartsState>(
      listener: _onPartsChanged,
      child: AlertDialog(
        title: const Text('Add part'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: PartFormDialog.partNoKey,
                  controller: _partNo,
                  enabled: !_awaiting,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Part number', border: OutlineInputBorder()),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: PartFormDialog.descriptionKey,
                  controller: _description,
                  enabled: !_awaiting,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder()),
                ),
                const SizedBox(height: Spacing.md),
                if (_loadingUnits)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: Spacing.md),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_unitsFailure != null)
                  PlatformFailureState(
                    key: PartFormDialog.unitsFailedKey,
                    title: 'The units of measure could not be read',
                    message: _unitsFailure!,
                    retryKey: PartFormDialog.unitsRetryKey,
                    onRetry: _loadUnits,
                  )
                else
                  DropdownButtonFormField<String>(
                    key: PartFormDialog.uomKey,
                    initialValue: _uomCode,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Unit of measure', border: OutlineInputBorder()),
                    items: [
                      for (final unit in _units)
                        DropdownMenuItem<String>(
                          value: unit.code,
                          child: Text(
                            '${unit.name} (${unit.code})',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _awaiting ? null : (value) => setState(() => _uomCode = value),
                  ),
                if (_failure != null)
                  Padding(
                    key: PartFormDialog.failureKey,
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
            key: PartFormDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: PartFormDialog.submitKey,
            onPressed: _complete && !_awaiting ? _submit : null,
            child: Text(_awaiting ? 'Saving…' : 'Add part'),
          ),
        ],
      ),
    );
  }
}
