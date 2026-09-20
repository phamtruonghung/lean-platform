/// Setting or changing the investigation due date (issue #228).
///
/// Addressed rather than popped — `/safety/incidents/:id/due-date`
/// (ADR-0021) — and offered to anyone with an edit Grant reaching the
/// incident's Org Unit; the API refuses anyone else with a 403. Not offered
/// once the incident is closed — the API refuses that with a 409, said at the
/// address rather than left to a form that cannot succeed.
///
/// `null` clears the date: a due date set in error should be removable, not
/// only replaceable with another one.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import '../widgets/app_date_time_field.dart';
import 'incident_detail_bloc.dart';
import 'safety_incident.dart';

class SafetyIncidentDueDateDialog extends StatefulWidget {
  const SafetyIncidentDueDateDialog({super.key, required this.incident});

  final SafetyIncident incident;

  static const ValueKey<String> loadingKey = ValueKey<String>('safety-incident-due-date-loading');
  static const ValueKey<String> fieldKey = ValueKey<String>('safety-incident-due-date-value');
  static const ValueKey<String> submitKey = ValueKey<String>('safety-incident-due-date-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('safety-incident-due-date-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('safety-incident-due-date-failure');
  static const ValueKey<String> refusedKey = ValueKey<String>('safety-incident-due-date-refused');

  @override
  State<SafetyIncidentDueDateDialog> createState() => _SafetyIncidentDueDateDialogState();
}

class _SafetyIncidentDueDateDialogState extends State<SafetyIncidentDueDateDialog> {
  late DateTime? _dueDate = _parse(widget.incident.investigationDueAt);

  bool _awaiting = false;
  String? _failure;

  static DateTime? _parse(String? value) => value == null ? null : DateTime.tryParse(value);

  void _submit() {
    if (_awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    context.read<SafetyIncidentDetailBloc>().add(
          SafetyIncidentDueDateSet(investigationDueAt: _dueDate?.toUtc().toIso8601String()),
        );
  }

  bool _done = false;

  void _onDetailChanged(BuildContext context, SafetyIncidentDetailState state) {
    if (_done || !_awaiting || state is! SafetyIncidentDetailLoaded || state.isMutating) return;
    if (state.mutationFailure != null) {
      setState(() {
        _awaiting = false;
        _failure = state.mutationFailure;
      });
      return;
    }
    _done = true;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final incident = widget.incident;

    if (incident.isClosed) {
      return AlertDialog(
        key: SafetyIncidentDueDateDialog.refusedKey,
        content: const Text(
          'This Safety incident is closed; its investigation due date cannot be changed.',
        ),
      );
    }

    return BlocListener<SafetyIncidentDetailBloc, SafetyIncidentDetailState>(
      listener: _onDetailChanged,
      child: AlertDialog(
        title: const Text('Investigation due date'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${incident.incidentNo}\'s investigation deadline.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: Spacing.md),
                AppDateTimeField(
                  key: SafetyIncidentDueDateDialog.fieldKey,
                  name: 'safety-incident-due-date',
                  label: 'Investigation due at',
                  optional: true,
                  value: _dueDate,
                  enabled: !_awaiting,
                  onChanged: (value) => setState(() => _dueDate = value),
                ),
                if (_failure != null)
                  Padding(
                    key: SafetyIncidentDueDateDialog.failureKey,
                    padding: const EdgeInsets.only(top: Spacing.md),
                    child: Text(
                      _failure!,
                      style:
                          theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            key: SafetyIncidentDueDateDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: SafetyIncidentDueDateDialog.submitKey,
            onPressed: _awaiting ? null : _submit,
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
