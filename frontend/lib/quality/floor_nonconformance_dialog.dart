/// Recording a Non-conformance at the shared floor device (issue #207,
/// ADR-0016) — the one flow on the floor surface that writes a Quality record
/// rather than a Work order.
///
/// It is a dialog, not a Screen: CONTEXT.md's own Screen entry says a dialog
/// inside a Screen is not a Screen, and this appears for one action and
/// disappears with it. It is reached the way `FloorTechnicianDialog` is —
/// `showDialog` from the floor Screen, with the Bloc provided by the caller —
/// and not by address, which is the floor surface's own convention rather than
/// the desktop Shell's (ADR-0021 decides the Shell's dialogs are addresses;
/// the floor surface is not the Shell, and its technician prompt has never had
/// one).
///
/// **Product, Defect code and detection point are chosen from lists read off
/// the device's own door**, which is why the flow reads before it can be
/// filled in: ADR-0023's rule is that a value with a known set is chosen,
/// never typed, and a device standing at a machine cannot choose without
/// knowing the set. They are dropdowns rather than an `AppSearchField` — the
/// desktop form's own Product picker — because this form is filled in with a
/// finger at arm's length, where a search box means typing on a tablet; the
/// catalogues are short, and the device already holds the whole list.
///
/// **The severity is not offered**: the record starts at the chosen Defect
/// code's own default, which the form states rather than leaving the operator
/// wondering. Lowering it is a Quality-authority decision (ADR-0035) that the
/// API refuses a recorder outright, so offering it here would be a form asking
/// a question whose answer is already no — the same reasoning the desktop
/// form's own severity picker follows from the other side.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'defect_code.dart';
import 'floor_nonconformance_bloc.dart';
import 'nonconformance.dart';

class FloorNonconformanceDialog extends StatefulWidget {
  const FloorNonconformanceDialog({super.key});

  static const ValueKey<String> productKey = ValueKey<String>('floor-nc-product');
  static const ValueKey<String> defectCodeKey = ValueKey<String>('floor-nc-defect-code');
  static const ValueKey<String> detectionPointKey = ValueKey<String>('floor-nc-detection-point');
  static const ValueKey<String> quantityKey = ValueKey<String>('floor-nc-quantity');
  static const ValueKey<String> lotRefKey = ValueKey<String>('floor-nc-lot');
  static const ValueKey<String> descriptionKey = ValueKey<String>('floor-nc-description');
  static const ValueKey<String> employeeNoKey = ValueKey<String>('floor-nc-employee-no');
  static const ValueKey<String> pinKey = ValueKey<String>('floor-nc-pin');
  static const ValueKey<String> submitKey = ValueKey<String>('floor-nc-submit');
  static const ValueKey<String> dismissKey = ValueKey<String>('floor-nc-dismiss');
  static const ValueKey<String> failureKey = ValueKey<String>('floor-nc-failure');

  @override
  State<FloorNonconformanceDialog> createState() => _FloorNonconformanceDialogState();
}

class _FloorNonconformanceDialogState extends State<FloorNonconformanceDialog> {
  final TextEditingController _quantity = TextEditingController();
  final TextEditingController _lotRef = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final TextEditingController _employeeNo = TextEditingController();
  final TextEditingController _pin = TextEditingController();

  String? _productId;
  String? _defectCodeId;
  String? _detectionPoint;
  bool _awaiting = false;

  @override
  void dispose() {
    _quantity.dispose();
    _lotRef.dispose();
    _description.dispose();
    _employeeNo.dispose();
    _pin.dispose();
    super.dispose();
  }

  /// What the chosen Defect code's own severity is, for the line that says
  /// where the record starts. Read off the list the Bloc already holds rather
  /// than off a second read.
  String? _chosenDefaultSeverity(FloorNonconformanceReady ready) {
    for (final code in ready.defectCodes) {
      if (code.id == _defectCodeId) return code.defaultSeverity;
    }
    return null;
  }

  bool _ready() {
    final quantity = num.tryParse(_quantity.text.trim());
    return _productId != null &&
        _defectCodeId != null &&
        _detectionPoint != null &&
        quantity != null &&
        quantity > 0 &&
        _employeeNo.text.trim().isNotEmpty &&
        _pin.text.trim().isNotEmpty;
  }

  void _submit() {
    if (!_ready() || _awaiting) return;
    setState(() => _awaiting = true);
    context.read<FloorNonconformanceBloc>().add(
          FloorNonconformanceSubmitted(
            productId: _productId!,
            defectCodeId: _defectCodeId!,
            detectionPoint: _detectionPoint!,
            quantity: _quantity.text.trim(),
            lotRef: _lotRef.text.trim(),
            description: _description.text.trim(),
            employeeNo: _employeeNo.text.trim(),
            pin: _pin.text.trim(),
          ),
        );
  }

  /// A landed record closes the dialog and hands its number back to the floor
  /// Screen, which is where the confirmation belongs: the operator's next
  /// glance is at the line, not at a dialog that has done its job. A refusal
  /// keeps the dialog open with the operator's own typing still in it.
  void _onChanged(BuildContext context, FloorNonconformanceState state) {
    if (state is FloorNonconformanceReady && state.notice != null) {
      if (_awaiting) Navigator.of(context).pop(state.notice);
      return;
    }
    if (!_awaiting) return;
    if (state is FloorNonconformanceReady && !state.isSubmitting && state.failure != null) {
      setState(() => _awaiting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<FloorNonconformanceBloc, FloorNonconformanceState>(
      listener: _onChanged,
      child: BlocBuilder<FloorNonconformanceBloc, FloorNonconformanceState>(
        builder: (context, state) => AlertDialog(
          title: const Text('Record a Non-conformance'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: switch (state) {
                FloorNonconformanceLoading() => const Padding(
                    padding: EdgeInsets.symmetric(vertical: Spacing.xl),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                FloorNonconformanceUnavailable(message: final message) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: Spacing.xl),
                    child: Text(message, style: Theme.of(context).textTheme.bodyLarge),
                  ),
                FloorNonconformanceReady() => _form(
                    busy: state.isSubmitting || _awaiting,
                    state: state,
                  ),
              },
            ),
          ),
          actions: [
            TextButton(
              key: FloorNonconformanceDialog.dismissKey,
              onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: FloorNonconformanceDialog.submitKey,
              onPressed: state is FloorNonconformanceReady && _ready() && !_awaiting
                  ? _submit
                  : null,
              child: const Text('Record it'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _form({required FloorNonconformanceReady state, required bool busy}) {
    final theme = Theme.of(context);
    final defaultSeverity = _chosenDefaultSeverity(state);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'What was found not to conform? Everything with a known set is chosen '
          'from what this device can see.',
          style: AppTypography.body(context)?.copyWith(color: AppColors.textMuted),
        ),
        const SizedBox(height: Spacing.md),
        DropdownButtonFormField<String?>(
          key: FloorNonconformanceDialog.productKey,
          initialValue: _productId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Product',
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('Choose a Product')),
            for (final product in state.products)
              DropdownMenuItem<String?>(
                value: product.id,
                child: Text('${product.code} · ${product.name}', overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: busy ? null : (id) => setState(() => _productId = id),
        ),
        const SizedBox(height: Spacing.md),
        DropdownButtonFormField<String?>(
          key: FloorNonconformanceDialog.defectCodeKey,
          initialValue: _defectCodeId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Defect code',
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('Choose a code')),
            for (final code in state.defectCodes)
              DropdownMenuItem<String?>(
                value: code.id,
                child: Text('${code.code} · ${code.name}', overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: busy ? null : (id) => setState(() => _defectCodeId = id),
        ),
        const SizedBox(height: Spacing.md),
        DropdownButtonFormField<String?>(
          key: FloorNonconformanceDialog.detectionPointKey,
          initialValue: _detectionPoint,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Detected at',
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('Choose a point')),
            for (final point in DetectionPoint.values)
              DropdownMenuItem<String?>(
                value: point,
                child: Text(DetectionPoint.label(point)),
              ),
          ],
          onChanged: busy ? null : (point) => setState(() => _detectionPoint = point),
        ),
        if (defaultSeverity != null)
          Padding(
            padding: const EdgeInsets.only(top: Spacing.sm),
            child: Text(
              "Starts at ${DefectSeverity.label(defaultSeverity)} — this Defect code's own severity.",
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
          ),
        const SizedBox(height: Spacing.md),
        TextField(
          key: FloorNonconformanceDialog.quantityKey,
          controller: _quantity,
          enabled: !busy,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'How much of it',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: Spacing.md),
        TextField(
          key: FloorNonconformanceDialog.lotRefKey,
          controller: _lotRef,
          enabled: !busy,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Lot or batch (if it has one)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: Spacing.md),
        TextField(
          key: FloorNonconformanceDialog.descriptionKey,
          controller: _description,
          enabled: !busy,
          maxLines: 3,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'What did you see?',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: Spacing.lg),
        Text(
          'Who found it? Your Employee number and PIN identify you for this record '
          'only — it is filed as your find.',
          style: AppTypography.body(context)?.copyWith(color: AppColors.textMuted),
        ),
        const SizedBox(height: Spacing.md),
        TextField(
          key: FloorNonconformanceDialog.employeeNoKey,
          controller: _employeeNo,
          enabled: !busy,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Employee number',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: Spacing.md),
        TextField(
          key: FloorNonconformanceDialog.pinKey,
          controller: _pin,
          enabled: !busy,
          obscureText: true,
          keyboardType: TextInputType.number,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'PIN',
            border: OutlineInputBorder(),
          ),
        ),
        if (state.failure != null)
          Padding(
            key: FloorNonconformanceDialog.failureKey,
            padding: const EdgeInsets.only(top: Spacing.md),
            child: Text(
              state.failure!,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
            ),
          ),
      ],
    );
  }
}
