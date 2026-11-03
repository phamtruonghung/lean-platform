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
///
/// **Its shell is `AppDialog`** (issue #398, `docs/design-language.md` §11):
/// one date field is the `form` width, and the closed-incident refusal is a
/// `decision` dialog whose single dismiss action is the way out it needs.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import '../widgets/app_date_time_field.dart';
import '../widgets/app_dialog.dart';
import 'incident_detail_bloc.dart';
import 'safety_incident.dart';

class SafetyIncidentDueDateDialog extends StatefulWidget {
  const SafetyIncidentDueDateDialog({super.key, required this.incident});

  final SafetyIncident incident;

  static const ValueKey<String> loadingKey = ValueKey<String>('safety-incident-due-date-loading');
  static const ValueKey<String> fieldKey = ValueKey<String>('safety-incident-due-date-value');
  static const ValueKey<String> failureKey = ValueKey<String>('safety-incident-due-date-failure');
  static const ValueKey<String> refusedKey = ValueKey<String>('safety-incident-due-date-refused');

  /// The actions' ids, and the keys `AppDialog` gives them
  /// (`docs/design-language.md` §11).
  static const String _submitId = 'safety-incident-due-date-submit';
  static const String _dismissId = 'safety-incident-due-date-cancel';
  static const String _closeId = 'safety-incident-due-date-refused-close';
  static ValueKey<String> get submitKey => AppDialog.actionKey(_submitId);
  static ValueKey<String> get cancelKey => AppDialog.actionKey(_dismissId);

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
      // A refused dialog still needs a way out: the sentence is its own
      // description and the single action closes it.
      return AppDialog(
        key: SafetyIncidentDueDateDialog.refusedKey,
        title: 'Investigation due date',
        size: AppDialogSize.decision,
        description:
            'This Safety incident is closed; its investigation due date cannot be changed.',
        actions: [
          AppDialogAction(
            id: SafetyIncidentDueDateDialog._closeId,
            label: 'Close',
            kind: AppDialogActionKind.dismiss,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      );
    }

    return BlocListener<SafetyIncidentDetailBloc, SafetyIncidentDetailState>(
      listener: _onDetailChanged,
      // A form (520): one optional date (§11).
      child: AppDialog(
        title: 'Investigation due date',
        size: AppDialogSize.form,
        description: "${incident.incidentNo}'s investigation deadline.",
        actions: [
          AppDialogAction(
            id: SafetyIncidentDueDateDialog._dismissId,
            label: 'Cancel',
            kind: AppDialogActionKind.dismiss,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
          ),
          AppDialogAction(
            id: SafetyIncidentDueDateDialog._submitId,
            label: 'Save',
            onPressed: _awaiting ? null : _submit,
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
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
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
