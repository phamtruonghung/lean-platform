/// Reporting a Safety incident at the shared floor device (issue #227,
/// ADR-0016, ADR-0036) — the second flow the floor surface offers that is not
/// about work orders, beside `FloorNonconformanceDialog`.
///
/// It is a dialog, not a Screen: CONTEXT.md's own Screen entry says a dialog
/// inside a Screen is not a Screen, and this appears for one action and
/// disappears with it. It is reached the way `FloorNonconformanceDialog` is —
/// `showDialog` from the floor Screen, with the Bloc provided by the caller —
/// and not by address, the floor surface's own convention.
///
/// **Incident type and severity are `DropdownButtonFormField`s, never typed**
/// (ADR-0023), built from the same `IncidentType.dropdownItems()` and
/// `SeverityLevel.dropdownItems()` helpers `SafetyIncidentFormDialog` uses —
/// the ladder order and the "· recordable" marking are shared, not rewritten
/// for this smaller form.
///
/// **The floor form's fields, and nothing else** (issue #223's own binding
/// comment on the floor form): occurred-time (defaulting to now), incident
/// type, severity, description, immediate action. No injury classification,
/// no Asset, no Employee-involved picker — those all need Safety authority or
/// judgement a floor identification never carries.
///
/// **There is no anonymous option anywhere in this flow, ever** (ADR-0036).
/// Identification — Employee number and PIN — is mandatory to even reach the
/// submit button, exactly as `FloorNonconformanceDialog` already requires it,
/// and nothing in this file's copy suggests a way to skip it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import '../widgets/app_date_time_field.dart';
import 'floor_safety_incident_bloc.dart';
import 'safety_incident.dart';

class FloorSafetyIncidentDialog extends StatefulWidget {
  const FloorSafetyIncidentDialog({super.key});

  static const ValueKey<String> incidentTypeKey = ValueKey<String>('floor-si-incident-type');
  static const ValueKey<String> severityKey = ValueKey<String>('floor-si-severity');
  static const ValueKey<String> descriptionKey = ValueKey<String>('floor-si-description');
  static const ValueKey<String> immediateActionKey =
      ValueKey<String>('floor-si-immediate-action');
  static const ValueKey<String> occurredAtKey = ValueKey<String>('floor-si-occurred-at');
  static const ValueKey<String> employeeNoKey = ValueKey<String>('floor-si-employee-no');
  static const ValueKey<String> pinKey = ValueKey<String>('floor-si-pin');
  static const ValueKey<String> submitKey = ValueKey<String>('floor-si-submit');
  static const ValueKey<String> dismissKey = ValueKey<String>('floor-si-dismiss');
  static const ValueKey<String> failureKey = ValueKey<String>('floor-si-failure');

  @override
  State<FloorSafetyIncidentDialog> createState() => _FloorSafetyIncidentDialogState();
}

class _FloorSafetyIncidentDialogState extends State<FloorSafetyIncidentDialog> {
  final TextEditingController _description = TextEditingController();
  final TextEditingController _immediateAction = TextEditingController();
  final TextEditingController _employeeNo = TextEditingController();
  final TextEditingController _pin = TextEditingController();

  String? _incidentType;
  String? _severityLevel;

  // Defaulted to now rather than left null: occurredAt is required by the
  // service (safety-incidents.js's own requireTimestamp), and a form that
  // opened with no value would force every operator through the picker just
  // to record "now" — the common case, the same default
  // `SafetyIncidentFormDialog` gives its own occurred-at field.
  DateTime? _occurredAt = DateTime.now();

  bool _awaiting = false;

  @override
  void dispose() {
    _description.dispose();
    _immediateAction.dispose();
    _employeeNo.dispose();
    _pin.dispose();
    super.dispose();
  }

  bool _ready() {
    return _incidentType != null &&
        _severityLevel != null &&
        _occurredAt != null &&
        _description.text.trim().isNotEmpty &&
        _employeeNo.text.trim().isNotEmpty &&
        _pin.text.trim().isNotEmpty;
  }

  void _submit() {
    if (!_ready() || _awaiting) return;
    setState(() => _awaiting = true);
    final immediateAction = _immediateAction.text.trim();
    context.read<FloorSafetyIncidentBloc>().add(
          FloorSafetyIncidentSubmitted(
            incidentType: _incidentType!,
            severityLevel: _severityLevel!,
            description: _description.text.trim(),
            occurredAt: _occurredAt!.toUtc().toIso8601String(),
            employeeNo: _employeeNo.text.trim(),
            pin: _pin.text.trim(),
            immediateAction: immediateAction.isEmpty ? null : immediateAction,
          ),
        );
  }

  /// A landed record closes the dialog and hands its number back to the floor
  /// Screen, which is where the confirmation belongs: the operator's next
  /// glance is at the line, not at a dialog that has done its job. A refusal
  /// keeps the dialog open with the operator's own typing still in it.
  void _onChanged(BuildContext context, FloorSafetyIncidentState state) {
    if (state is FloorSafetyIncidentReady && state.notice != null) {
      if (_awaiting) Navigator.of(context).pop(state.notice);
      return;
    }
    if (!_awaiting) return;
    if (state is FloorSafetyIncidentReady && !state.isSubmitting && state.failure != null) {
      setState(() => _awaiting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<FloorSafetyIncidentBloc, FloorSafetyIncidentState>(
      listener: _onChanged,
      child: BlocBuilder<FloorSafetyIncidentBloc, FloorSafetyIncidentState>(
        builder: (context, state) => AlertDialog(
          title: const Text('Report a Safety incident'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: switch (state) {
                FloorSafetyIncidentUnavailable(message: final message) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: Spacing.xl),
                    child: Text(message, style: Theme.of(context).textTheme.bodyLarge),
                  ),
                FloorSafetyIncidentReady() => _form(
                    busy: state.isSubmitting || _awaiting,
                    state: state,
                  ),
              },
            ),
          ),
          actions: [
            TextButton(
              key: FloorSafetyIncidentDialog.dismissKey,
              onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: FloorSafetyIncidentDialog.submitKey,
              onPressed:
                  state is FloorSafetyIncidentReady && _ready() && !_awaiting ? _submit : null,
              child: const Text('Report it'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _form({required FloorSafetyIncidentReady state, required bool busy}) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'What happened? Everything with a known set is chosen from a fixed list.',
          style: AppTypography.body(context)?.copyWith(color: AppColors.textMuted),
        ),
        const SizedBox(height: Spacing.md),
        DropdownButtonFormField<String?>(
          key: FloorSafetyIncidentDialog.incidentTypeKey,
          initialValue: _incidentType,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Incident type',
            border: OutlineInputBorder(),
          ),
          items: IncidentType.dropdownItems(),
          onChanged: busy ? null : (type) => setState(() => _incidentType = type),
        ),
        const SizedBox(height: Spacing.md),
        // Ladder order, never alphabetical, and marking where the recordable
        // line falls (the binding design comment on #223) — the same
        // SeverityLevel.dropdownItems() helper SafetyIncidentFormDialog uses.
        DropdownButtonFormField<String?>(
          key: FloorSafetyIncidentDialog.severityKey,
          initialValue: _severityLevel,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Severity',
            border: OutlineInputBorder(),
          ),
          items: SeverityLevel.dropdownItems(),
          onChanged: busy ? null : (level) => setState(() => _severityLevel = level),
        ),
        const SizedBox(height: Spacing.md),
        TextField(
          key: FloorSafetyIncidentDialog.descriptionKey,
          controller: _description,
          enabled: !busy,
          minLines: 2,
          maxLines: 4,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'What happened',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: Spacing.md),
        TextField(
          key: FloorSafetyIncidentDialog.immediateActionKey,
          controller: _immediateAction,
          enabled: !busy,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Immediate action (optional)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: Spacing.md),
        AppDateTimeField(
          key: FloorSafetyIncidentDialog.occurredAtKey,
          name: 'floor-safety-incident-occurred-at',
          label: 'Occurred at',
          value: _occurredAt,
          enabled: !busy,
          onChanged: (value) => setState(() => _occurredAt = value),
        ),
        const SizedBox(height: Spacing.lg),
        Text(
          'Who is reporting this? Your Employee number and PIN identify you for '
          'this record only — it is filed as your report.',
          style: AppTypography.body(context)?.copyWith(color: AppColors.textMuted),
        ),
        const SizedBox(height: Spacing.md),
        TextField(
          key: FloorSafetyIncidentDialog.employeeNoKey,
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
          key: FloorSafetyIncidentDialog.pinKey,
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
            key: FloorSafetyIncidentDialog.failureKey,
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
