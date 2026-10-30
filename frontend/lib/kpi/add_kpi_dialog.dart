/// Adding a KPI to the catalogue (ADR-0055): `POST /api/kpi/catalogue`.
///
/// **Add stays disabled until the form could be accepted**: the KPI name and
/// the Title are non-blank, and Decimals parses to a whole number from 0 to 6
/// (the server's own rule). The server is still the gate: a duplicate name is
/// a 409, and it — like a 403 — renders as the API's own `message` in an inline
/// line under the form while the dialog stays open.
///
/// The body is exactly `{site_id, kpi, title, unit, direction, decimals,
/// value_measure}`: `unit` is `''` when left blank, `value_measure` is `null`
/// when left blank, `decimals` is an int. Direction is chosen (`>=` or `<=`),
/// never typed; a seeded KPI may carry `<` or `>`, which this form does not
/// offer for a new one.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import 'kpi_catalogue.dart';
import 'kpi_catalogue_bloc.dart';

class AddKpiDialog extends StatefulWidget {
  const AddKpiDialog({super.key});

  static const ValueKey<String> nameKey = ValueKey<String>('add-kpi-name');
  static const ValueKey<String> titleKey = ValueKey<String>('add-kpi-title');
  static const ValueKey<String> unitKey = ValueKey<String>('add-kpi-unit');
  static const ValueKey<String> directionKey = ValueKey<String>('add-kpi-direction');
  static const ValueKey<String> decimalsKey = ValueKey<String>('add-kpi-decimals');
  static const ValueKey<String> valueMeasureKey = ValueKey<String>('add-kpi-value-measure');
  static const ValueKey<String> submitKey = ValueKey<String>('add-kpi-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('add-kpi-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('add-kpi-failure');

  static const List<String> directions = ['>=', '<='];

  /// Opens the form over the catalogue. The Bloc is handed across explicitly
  /// because `showDialog` builds under the Navigator, not under the Screen's
  /// route-scoped `BlocProvider`.
  static Future<void> open(BuildContext context) {
    final bloc = context.read<KpiCatalogueBloc>();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => BlocProvider<KpiCatalogueBloc>.value(
        value: bloc,
        child: const AddKpiDialog(),
      ),
    );
  }

  @override
  State<AddKpiDialog> createState() => _AddKpiDialogState();
}

class _AddKpiDialogState extends State<AddKpiDialog> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _title = TextEditingController();
  final TextEditingController _unit = TextEditingController();
  final TextEditingController _decimals = TextEditingController(text: '0');
  final TextEditingController _valueMeasure = TextEditingController();
  String _direction = AddKpiDialog.directions.first;

  bool _awaiting = false;
  String? _failure;

  @override
  void dispose() {
    _name.dispose();
    _title.dispose();
    _unit.dispose();
    _decimals.dispose();
    _valueMeasure.dispose();
    super.dispose();
  }

  /// Decimals as a whole number from 0 to 6, or null.
  int? get _decimalsValue {
    final value = int.tryParse(_decimals.text.trim());
    if (value == null || value < 0 || value > 6) return null;
    return value;
  }

  bool get _complete =>
      _name.text.trim().isNotEmpty && _title.text.trim().isNotEmpty && _decimalsValue != null;

  void _submit() {
    if (!_complete || _awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    final measure = _valueMeasure.text.trim();
    context.read<KpiCatalogueBloc>().add(
          KpiAdded(
            NewKpi(
              kpi: _name.text.trim(),
              title: _title.text.trim(),
              unit: _unit.text.trim(),
              direction: _direction,
              decimals: _decimalsValue!,
              valueMeasure: measure.isEmpty ? null : measure,
            ),
          ),
        );
  }

  void _onCatalogueChanged(BuildContext context, KpiCatalogueState state) {
    if (!_awaiting || state is! KpiCatalogueLoaded || state.isMutating) return;
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
    final decimalsText = _decimals.text.trim();
    return BlocListener<KpiCatalogueBloc, KpiCatalogueState>(
      listener: _onCatalogueChanged,
      child: AlertDialog(
        title: const Text('Add KPI'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: AddKpiDialog.nameKey,
                  controller: _name,
                  enabled: !_awaiting,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'KPI', helperText: 'The code, e.g. OEE', border: OutlineInputBorder()),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: AddKpiDialog.titleKey,
                  controller: _title,
                  enabled: !_awaiting,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: AddKpiDialog.unitKey,
                  controller: _unit,
                  enabled: !_awaiting,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Unit (optional)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: Spacing.md),
                DropdownButtonFormField<String>(
                  key: AddKpiDialog.directionKey,
                  initialValue: _direction,
                  decoration: const InputDecoration(
                    labelText: 'Direction',
                    helperText: '>= is met at or above the Target, <= at or below it',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final direction in AddKpiDialog.directions)
                      DropdownMenuItem<String>(value: direction, child: Text(direction)),
                  ],
                  onChanged: _awaiting
                      ? null
                      : (value) {
                          if (value != null) setState(() => _direction = value);
                        },
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: AddKpiDialog.decimalsKey,
                  controller: _decimals,
                  enabled: !_awaiting,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Decimals',
                    helperText: 'A whole number from 0 to 6',
                    errorText: decimalsText.isNotEmpty && _decimalsValue == null
                        ? 'Decimals must be a whole number from 0 to 6'
                        : null,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: AddKpiDialog.valueMeasureKey,
                  controller: _valueMeasure,
                  enabled: !_awaiting,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Value measure (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_failure != null)
                  Padding(
                    key: AddKpiDialog.failureKey,
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
            key: AddKpiDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: AddKpiDialog.submitKey,
            onPressed: _complete && !_awaiting ? _submit : null,
            child: Text(_awaiting ? 'Adding…' : 'Add'),
          ),
        ],
      ),
    );
  }
}
