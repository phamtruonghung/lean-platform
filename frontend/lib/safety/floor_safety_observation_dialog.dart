/// Recording a Safety observation at the shared floor device (issue #230,
/// ADR-0016) — the third flow the floor surface offers that is not about
/// work orders, beside `FloorNonconformanceDialog` and
/// `FloorSafetyIncidentDialog`.
///
/// It is a dialog, not a Screen: CONTEXT.md's own Screen entry says a dialog
/// inside a Screen is not a Screen, and this appears for one action and
/// disappears with it. It is reached the way `FloorSafetyIncidentDialog` is —
/// `showDialog` from the floor Screen, with the Bloc provided by the caller —
/// and not by address, the floor surface's own convention.
///
/// **Type, category and severity potential are `DropdownButtonFormField`s,
/// never typed** (ADR-0023), built from the same `ObservationType.dropdownItems()`,
/// `ObservationCategory.dropdownItems()` and `SeverityPotential.dropdownItems()`
/// helpers `SafetyObservationFormDialog` uses.
///
/// Identification — Employee number and PIN — is mandatory to even reach the
/// submit button, the same requirement `FloorSafetyIncidentDialog` already
/// carries: naming the recorder is what makes a floor record attributable to
/// a person.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/app_localizations.dart';
import '../theme.dart';
import 'floor_safety_observation_bloc.dart';
import 'safety_observation.dart';
import '../l10n/vocabulary.dart';
import '../widgets/notice_text.dart';

class FloorSafetyObservationDialog extends StatefulWidget {
  const FloorSafetyObservationDialog({super.key});

  static const ValueKey<String> typeKey = ValueKey<String>('floor-so-type');
  static const ValueKey<String> categoryKey = ValueKey<String>('floor-so-category');
  static const ValueKey<String> severityPotentialKey = ValueKey<String>('floor-so-potential');
  static const ValueKey<String> descriptionKey = ValueKey<String>('floor-so-description');
  static const ValueKey<String> actionTakenKey = ValueKey<String>('floor-so-action-taken');
  static const ValueKey<String> stopWorkKey = ValueKey<String>('floor-so-stop-work');
  static const ValueKey<String> employeeNoKey = ValueKey<String>('floor-so-employee-no');
  static const ValueKey<String> pinKey = ValueKey<String>('floor-so-pin');
  static const ValueKey<String> submitKey = ValueKey<String>('floor-so-submit');
  static const ValueKey<String> dismissKey = ValueKey<String>('floor-so-dismiss');
  static const ValueKey<String> failureKey = ValueKey<String>('floor-so-failure');

  @override
  State<FloorSafetyObservationDialog> createState() => _FloorSafetyObservationDialogState();
}

class _FloorSafetyObservationDialogState extends State<FloorSafetyObservationDialog> {
  final TextEditingController _description = TextEditingController();
  final TextEditingController _actionTaken = TextEditingController();
  final TextEditingController _employeeNo = TextEditingController();
  final TextEditingController _pin = TextEditingController();

  String? _observationType;
  String? _category;
  String? _severityPotential;
  bool _isStopWork = false;

  bool _awaiting = false;

  @override
  void dispose() {
    _description.dispose();
    _actionTaken.dispose();
    _employeeNo.dispose();
    _pin.dispose();
    super.dispose();
  }

  bool _ready() {
    return _observationType != null &&
        _category != null &&
        _severityPotential != null &&
        _description.text.trim().isNotEmpty &&
        _employeeNo.text.trim().isNotEmpty &&
        _pin.text.trim().isNotEmpty;
  }

  void _submit() {
    if (!_ready() || _awaiting) return;
    setState(() => _awaiting = true);
    final actionTaken = _actionTaken.text.trim();
    context.read<FloorSafetyObservationBloc>().add(
          FloorSafetyObservationSubmitted(
            observationType: _observationType!,
            category: _category!,
            severityPotential: _severityPotential!,
            description: _description.text.trim(),
            isStopWork: _isStopWork,
            actionTaken: actionTaken.isEmpty ? null : actionTaken,
            employeeNo: _employeeNo.text.trim(),
            pin: _pin.text.trim(),
          ),
        );
  }

  /// A landed record closes the dialog and hands its notice back to the floor
  /// Screen, which is where the confirmation belongs — the same choice
  /// `FloorSafetyIncidentDialog._onChanged` makes. A refusal keeps the dialog
  /// open with the operator's own typing still in it.
  void _onChanged(BuildContext context, FloorSafetyObservationState state) {
    if (state is FloorSafetyObservationReady && state.notice != null) {
      if (_awaiting) Navigator.of(context).pop(state.notice);
      return;
    }
    if (!_awaiting) return;
    if (state is FloorSafetyObservationReady && !state.isSubmitting && state.failure != null) {
      setState(() => _awaiting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return BlocListener<FloorSafetyObservationBloc, FloorSafetyObservationState>(
      listener: _onChanged,
      child: BlocBuilder<FloorSafetyObservationBloc, FloorSafetyObservationState>(
        builder: (context, state) => AlertDialog(
          title: Text(l10n.safetyObservationRecordTitle),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: switch (state) {
                FloorSafetyObservationUnavailable(message: final message) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: Spacing.xl),
                    child: NoticeText(message, style: Theme.of(context).textTheme.bodyLarge),
                  ),
                FloorSafetyObservationReady() => _form(
                    busy: state.isSubmitting || _awaiting,
                    state: state,
                  ),
              },
            ),
          ),
          actions: [
            TextButton(
              key: FloorSafetyObservationDialog.dismissKey,
              onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              key: FloorSafetyObservationDialog.submitKey,
              onPressed:
                  state is FloorSafetyObservationReady && _ready() && !_awaiting ? _submit : null,
              child: Text(l10n.nonconformanceFormRecord),
            ),
          ],
        ),
      ),
    );
  }

  Widget _form({required FloorSafetyObservationReady state, required bool busy}) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.safetyObservationFloorIntro,
          style: AppTypography.body(context)?.copyWith(color: AppColors.of(context).textMuted),
        ),
        const SizedBox(height: Spacing.md),
        DropdownButtonFormField<String?>(
          key: FloorSafetyObservationDialog.typeKey,
          initialValue: _observationType,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: l10n.commonType,
            border: const OutlineInputBorder(),
          ),
          items: ObservationType.dropdownItems(
            label: (type) => observationTypeLabel(l10n, type),
            placeholder: l10n.safetyAnyType,
          ),
          onChanged: busy ? null : (type) => setState(() => _observationType = type),
        ),
        const SizedBox(height: Spacing.md),
        DropdownButtonFormField<String?>(
          key: FloorSafetyObservationDialog.categoryKey,
          initialValue: _category,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: l10n.commonCategory,
            border: const OutlineInputBorder(),
          ),
          items: ObservationCategory.dropdownItems(
            label: (category) => observationCategoryLabel(l10n, category),
            placeholder: l10n.safetyAnyCategory,
          ),
          onChanged: busy ? null : (category) => setState(() => _category = category),
        ),
        const SizedBox(height: Spacing.md),
        DropdownButtonFormField<String?>(
          key: FloorSafetyObservationDialog.severityPotentialKey,
          initialValue: _severityPotential,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: l10n.safetySeverityPotential,
            border: const OutlineInputBorder(),
          ),
          items: SeverityPotential.dropdownItems(
            label: (potential) => severityPotentialLabel(l10n, potential),
            placeholder: l10n.safetyAnyPotential,
          ),
          onChanged: busy ? null : (potential) => setState(() => _severityPotential = potential),
        ),
        const SizedBox(height: Spacing.md),
        TextField(
          key: FloorSafetyObservationDialog.descriptionKey,
          controller: _description,
          enabled: !busy,
          minLines: 2,
          maxLines: 4,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: l10n.safetyWhatWasSeen,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: Spacing.md),
        TextField(
          key: FloorSafetyObservationDialog.actionTakenKey,
          controller: _actionTaken,
          enabled: !busy,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: l10n.safetyActionTaken,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: Spacing.md),
        SwitchListTile(
          key: FloorSafetyObservationDialog.stopWorkKey,
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.safetyStopWorkExercised),
          value: _isStopWork,
          onChanged: busy ? null : (value) => setState(() => _isStopWork = value),
        ),
        const SizedBox(height: Spacing.lg),
        Text(
          l10n.safetyObservationFloorWho,
          style: AppTypography.body(context)?.copyWith(color: AppColors.of(context).textMuted),
        ),
        const SizedBox(height: Spacing.md),
        TextField(
          key: FloorSafetyObservationDialog.employeeNoKey,
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
          key: FloorSafetyObservationDialog.pinKey,
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
            key: FloorSafetyObservationDialog.failureKey,
            padding: const EdgeInsets.only(top: Spacing.md),
            child: NoticeText(
              state.failure!,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
            ),
          ),
      ],
    );
  }
}
