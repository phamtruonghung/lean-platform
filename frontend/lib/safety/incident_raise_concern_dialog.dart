/// Raising a Concern from a Safety incident (issue #229).
///
/// Addressed rather than popped — `/safety/incidents/:id/raise-concern`
/// (ADR-0021): a refresh lands on the record with the form open, and a
/// colleague can be handed the address of the act itself.
///
/// Mirrors `NonconformanceRaiseConcernDialog` closely, field for field and for
/// the same reason: this is the case where somebody has just found a cause
/// worth solving and wants it looked at, so the form is short on purpose —
/// a title, what is known, and the priority. The server fills the rest in by
/// its own rules: the Org Unit is the incident's own, the number comes from
/// the Site's own sequence, and the Concern starts on a cycle-1 Plan of its
/// own.
///
/// The write goes to the Actions Module (its own route, through its own
/// client entry point) and the answer is the Concern, so the dialog closes on
/// the Bloc's own `notice` and the Screen beneath it re-reads the incident.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../actions/actions.dart';
import '../theme.dart';
import 'incident_detail_bloc.dart';
import 'safety_incident.dart';

class SafetyIncidentRaiseConcernDialog extends StatefulWidget {
  const SafetyIncidentRaiseConcernDialog({super.key, required this.incident});

  final SafetyIncident incident;

  static const ValueKey<String> loadingKey =
      ValueKey<String>('safety-incident-raise-concern-loading');
  static const ValueKey<String> titleKey = ValueKey<String>('safety-incident-raise-concern-title');
  static const ValueKey<String> descriptionKey =
      ValueKey<String>('safety-incident-raise-concern-description');
  static const ValueKey<String> priorityKey =
      ValueKey<String>('safety-incident-raise-concern-priority');
  static const ValueKey<String> submitKey =
      ValueKey<String>('safety-incident-raise-concern-submit');
  static const ValueKey<String> cancelKey =
      ValueKey<String>('safety-incident-raise-concern-cancel');
  static const ValueKey<String> failureKey =
      ValueKey<String>('safety-incident-raise-concern-failure');

  @override
  State<SafetyIncidentRaiseConcernDialog> createState() =>
      _SafetyIncidentRaiseConcernDialogState();
}

class _SafetyIncidentRaiseConcernDialogState extends State<SafetyIncidentRaiseConcernDialog> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _description = TextEditingController();

  int _priority = 3;
  bool _awaiting = false;
  bool _done = false;
  String? _failure;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  bool get _complete => _title.text.trim().isNotEmpty && !_awaiting;

  void _submit() {
    if (!_complete) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    final description = _description.text.trim();
    context.read<SafetyIncidentDetailBloc>().add(
          SafetyIncidentConcernRaised(
            title: _title.text.trim(),
            description: description.isEmpty ? null : description,
            priority: _priority,
          ),
        );
  }

  /// The Bloc reports the outcome on its own state rather than returning one,
  /// so this is where the dialog learns it landed: still in flight, refused
  /// with a sentence, or done and ready to close.
  void _onDetailChanged(BuildContext context, SafetyIncidentDetailState state) {
    if (_done || !_awaiting) return;
    if (state is! SafetyIncidentDetailLoaded) return;
    if (state.isRaisingConcern) return;
    final failure = state.concernRaiseFailure;
    if (failure != null) {
      setState(() {
        _awaiting = false;
        _failure = failure;
      });
      return;
    }
    _done = true;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final record = widget.incident;

    return BlocListener<SafetyIncidentDetailBloc, SafetyIncidentDetailState>(
      listener: _onDetailChanged,
      child: AlertDialog(
        title: const Text('Raise a Concern'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${record.incidentNo} is recorded at ${record.orgUnitName}, and the Concern is '
                  'raised there — a problem is solved where it happened.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: SafetyIncidentRaiseConcernDialog.titleKey,
                  controller: _title,
                  enabled: !_awaiting,
                  maxLines: 1,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'What is the cause to solve?',
                    helperText: 'The Concern is read in the action log, so say the problem, not the '
                        'injury.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: SafetyIncidentRaiseConcernDialog.descriptionKey,
                  controller: _description,
                  enabled: !_awaiting,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Anything known yet',
                    helperText: 'Optional. The Safety incident itself is already linked as evidence.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                DropdownButtonFormField<int>(
                  key: SafetyIncidentRaiseConcernDialog.priorityKey,
                  initialValue: _priority,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Priority',
                    helperText: '1 is worst.',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final entry in actionPriorityLabels.entries)
                      DropdownMenuItem<int>(value: entry.key, child: Text(entry.value)),
                  ],
                  onChanged: _awaiting ? null : (value) => setState(() => _priority = value ?? 3),
                ),
                if (_failure != null)
                  Padding(
                    key: SafetyIncidentRaiseConcernDialog.failureKey,
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
            key: SafetyIncidentRaiseConcernDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: SafetyIncidentRaiseConcernDialog.submitKey,
            onPressed: _complete ? _submit : null,
            child: const Text('Raise it'),
          ),
        ],
      ),
    );
  }
}
