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
/// knowing the set. The Product and the detection point stay
/// `DropdownButtonFormField`s — a menu is the better control for a finger at
/// arm's length, and the device holds the whole list. **The Defect code is an
/// `AppSearchField`**, because it is the one field here a person reads off the
/// part in their hand: a dropdown has no text buffer, so a reader's burst
/// cannot reach it at all, while a search field over the same list commits an
/// exact code (equal, case-insensitive, reader noise stripped) as a pick
/// (`app_search_field.dart`). Its suggestion list filters the catalogue the
/// device's own door already read, in memory, so nothing here issues a request
/// per term.
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

import '../l10n/app_localizations.dart';
import '../theme.dart';
import '../widgets/app_search_field.dart';
import 'defect_code.dart';
import 'floor_nonconformance_bloc.dart';
import 'nonconformance.dart';
import '../l10n/vocabulary.dart';

class FloorNonconformanceDialog extends StatefulWidget {
  const FloorNonconformanceDialog({super.key});

  static const ValueKey<String> productKey = ValueKey<String>('floor-nc-product');
  static const ValueKey<String> detectionPointKey = ValueKey<String>('floor-nc-detection-point');
  static const ValueKey<String> quantityKey = ValueKey<String>('floor-nc-quantity');
  static const ValueKey<String> lotRefKey = ValueKey<String>('floor-nc-lot');
  static const ValueKey<String> descriptionKey = ValueKey<String>('floor-nc-description');
  static const ValueKey<String> employeeNoKey = ValueKey<String>('floor-nc-employee-no');
  static const ValueKey<String> pinKey = ValueKey<String>('floor-nc-pin');
  static const ValueKey<String> submitKey = ValueKey<String>('floor-nc-submit');
  static const ValueKey<String> dismissKey = ValueKey<String>('floor-nc-dismiss');
  static const ValueKey<String> failureKey = ValueKey<String>('floor-nc-failure');

  /// The Defect code picker's own name, and the two `Key`s an `AppSearchField`
  /// derives from it — the field itself and each suggestion row. A test types
  /// or scans into the field and taps a suggestion through these (AGENTS.md §7:
  /// the widget exposes its own accessors rather than a test building a `Key`).
  static const String defectCodeFieldName = 'floor-nc-defect-code';

  static ValueKey<String> defectCodeFieldKey() => AppSearchField.fieldKey(defectCodeFieldName);

  static ValueKey<String> defectCodeSuggestionKey(String id) =>
      AppSearchField.suggestionKey(defectCodeFieldName, id);

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

  /// The chosen Defect code itself, not just its id: the picker reports the
  /// record it stands for, and the record is what the severity line reads.
  DefectCode? _defectCode;
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
  /// where the record starts. The record the picker reported, not a second
  /// lookup in the list the Bloc already holds.
  String? _chosenDefaultSeverity() => _defectCode?.defaultSeverity;

  bool _ready() {
    final quantity = num.tryParse(_quantity.text.trim());
    return _productId != null &&
        _defectCode != null &&
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
            defectCodeId: _defectCode!.id,
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
    final l10n = AppLocalizations.of(context);
    return BlocListener<FloorNonconformanceBloc, FloorNonconformanceState>(
      listener: _onChanged,
      child: BlocBuilder<FloorNonconformanceBloc, FloorNonconformanceState>(
        builder: (context, state) => AlertDialog(
          title: Text(l10n.nonconformanceRecord),
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
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              key: FloorNonconformanceDialog.submitKey,
              onPressed: state is FloorNonconformanceReady && _ready() && !_awaiting
                  ? _submit
                  : null,
              child: Text(l10n.nonconformanceFormRecord),
            ),
          ],
        ),
      ),
    );
  }

  Widget _form({required FloorNonconformanceReady state, required bool busy}) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final defaultSeverity = _chosenDefaultSeverity();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.nonconformanceFloorIntro,
          style: AppTypography.body(context)?.copyWith(color: AppColors.of(context).textMuted),
        ),
        const SizedBox(height: Spacing.md),
        DropdownButtonFormField<String?>(
          key: FloorNonconformanceDialog.productKey,
          initialValue: _productId,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: l10n.commonProduct,
            border: const OutlineInputBorder(),
          ),
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text(l10n.nonconformanceFloorChooseProduct),
            ),
            for (final product in state.products)
              DropdownMenuItem<String?>(
                value: product.id,
                child: Text('${product.code} · ${product.name}', overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: busy ? null : (id) => setState(() => _productId = id),
        ),
        const SizedBox(height: Spacing.md),
        AppSearchField<DefectCode>(
          name: FloorNonconformanceDialog.defectCodeFieldName,
          label: l10n.commonDefectCode,
          enabled: !busy,
          // The field reports the record it now stands for, picked or cleared —
          // a pick and a scan land on the same handler.
          value: _defectCode,
          onChanged: (code) => setState(() => _defectCode = code),
          onSelected: (code) => setState(() => _defectCode = code),
          // A dumb in-memory filter over the catalogue this device's own door
          // already read — no request of its own, so the field's per-term
          // debounce never reaches the wire (ADR-0023). Matched on the two
          // fields that identify a Defect code: its code and its name.
          fetchSuggestions: (term) async {
            final lower = term.toLowerCase();
            return [
              for (final code in state.defectCodes)
                if (code.code.toLowerCase().contains(lower) ||
                    code.name.toLowerCase().contains(lower))
                  code,
            ];
          },
          suggestionBuilder: (context, code) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm),
            child: Text('${code.code} · ${code.name}', overflow: TextOverflow.ellipsis),
          ),
          idOf: (code) => code.id,
          displayStringFor: (code) => '${code.code} · ${code.name}',
          // A reader sends the code alone, never the `CODE · Name` the field
          // shows — this is what makes a scan of `DIM-OOT` pick that code.
          codeOf: (code) => code.code,
        ),
        const SizedBox(height: Spacing.md),
        DropdownButtonFormField<String?>(
          key: FloorNonconformanceDialog.detectionPointKey,
          initialValue: _detectionPoint,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: l10n.nonconformanceFloorDetectedAt,
            border: const OutlineInputBorder(),
          ),
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text(l10n.nonconformanceFormChoosePoint),
            ),
            for (final point in DetectionPoint.values)
              DropdownMenuItem<String?>(
                value: point,
                child: Text(detectionPointLabel(l10n, point)),
              ),
          ],
          onChanged: busy ? null : (point) => setState(() => _detectionPoint = point),
        ),
        if (defaultSeverity != null)
          Padding(
            padding: const EdgeInsets.only(top: Spacing.sm),
            child: Text(
              l10n.nonconformanceFloorStartsAt(defectSeverityLabel(l10n, defaultSeverity)),
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.of(context).textMuted),
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
          decoration: InputDecoration(
            labelText: l10n.nonconformanceFloorHowMuch,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: Spacing.md),
        TextField(
          key: FloorNonconformanceDialog.lotRefKey,
          controller: _lotRef,
          enabled: !busy,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: l10n.nonconformanceFloorLot,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: Spacing.md),
        TextField(
          key: FloorNonconformanceDialog.descriptionKey,
          controller: _description,
          enabled: !busy,
          maxLines: 3,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: l10n.nonconformanceFloorWhatDidYouSee,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: Spacing.lg),
        Text(
          l10n.nonconformanceFloorWhoFound,
          style: AppTypography.body(context)?.copyWith(color: AppColors.of(context).textMuted),
        ),
        const SizedBox(height: Spacing.md),
        TextField(
          key: FloorNonconformanceDialog.employeeNoKey,
          controller: _employeeNo,
          enabled: !busy,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: l10n.nonconformanceFloorEmployeeNumber,
            border: const OutlineInputBorder(),
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
          decoration: InputDecoration(
            labelText: l10n.nonconformanceFloorPin,
            border: const OutlineInputBorder(),
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
