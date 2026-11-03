/// Correcting a Safety incident's severity level, with a note (issue #228,
/// #223 decision 5).
///
/// Addressed rather than popped — `/safety/incidents/:id/severity`
/// (ADR-0021). The Screen offers this address only to a caller holding
/// Safety authority at the incident's Org Unit (ADR-0039); the API refuses
/// anyone else with a 403.
///
/// **Correcting a severity restates the period the incident occurred in** —
/// `is_recordable` is `GENERATED ALWAYS` and an incident is filed by the day
/// it occurred on, so upgrading a first-aid case to lost-time moves that
/// period's own recordable count and rates. That is what injury recordkeeping
/// requires, not a bug, which is also why this dialog is offered even on a
/// closed incident: a correction routinely comes long after the incident it
/// corrects has closed.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../platform/router.dart';
import '../theme.dart';
import '../widgets/app_dialog.dart';
import 'incident_detail_bloc.dart';
import 'safety_incident.dart';

class SafetyIncidentSeverityDialog extends StatefulWidget {
  const SafetyIncidentSeverityDialog({super.key, required this.incident});

  final SafetyIncident incident;

  static const ValueKey<String> loadingKey = ValueKey<String>('safety-incident-severity-loading');
  static const ValueKey<String> severityKey = ValueKey<String>('safety-incident-severity-value');
  static const ValueKey<String> noteKey = ValueKey<String>('safety-incident-severity-note');
  /// The actions' ids, and the keys `AppDialog` gives them
  /// (`docs/design-language.md` §11).
  static const String _submitId = 'safety-incident-severity-submit';
  static const String _dismissId = 'safety-incident-severity-cancel';
  static const String _closeId = 'safety-incident-severity-refused-close';
  static ValueKey<String> get submitKey => AppDialog.actionKey(_submitId);
  static ValueKey<String> get cancelKey => AppDialog.actionKey(_dismissId);
  static const ValueKey<String> failureKey = ValueKey<String>('safety-incident-severity-failure');
  static const ValueKey<String> refusedKey = ValueKey<String>('safety-incident-severity-refused');

  @override
  State<SafetyIncidentSeverityDialog> createState() => _SafetyIncidentSeverityDialogState();
}

class _SafetyIncidentSeverityDialogState extends State<SafetyIncidentSeverityDialog> {
  final TextEditingController _note = TextEditingController();

  String? _severity;
  bool _awaiting = false;
  String? _failure;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  /// Every rung but the one already on the record — a correction can go
  /// either way, unlike Quality's one-way lowering.
  List<String> get _offerableSeverities =>
      [for (final level in SeverityLevel.values) if (level != widget.incident.severityLevel) level];

  bool get _complete => _severity != null && _note.text.trim().isNotEmpty && !_awaiting;

  void _submit() {
    final severity = _severity;
    if (!_complete || severity == null) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    context.read<SafetyIncidentDetailBloc>().add(
          SafetyIncidentSeverityChanged(severityLevel: severity, note: _note.text),
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

    // Read here, in a build, for the reason the Screen reads it there: a
    // value frozen when the route first built would answer for a half-known
    // Account.
    if (!holdsSafetyAuthority(context, incident.orgUnitId)) {
      // A refused dialog still needs a way out: the sentence is its own
      // description and the single action closes it.
      return AppDialog(
        key: SafetyIncidentSeverityDialog.refusedKey,
        title: 'Correct the severity',
        size: AppDialogSize.decision,
        description:
            "Correcting the severity needs Safety authority at this Safety incident's Org Unit.",
        actions: [
          AppDialogAction(
            id: SafetyIncidentSeverityDialog._closeId,
            label: 'Close',
            kind: AppDialogActionKind.dismiss,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      );
    }

    return BlocListener<SafetyIncidentDetailBloc, SafetyIncidentDetailState>(
      listener: _onDetailChanged,
      // A form (520): one select and one note (§11).
      child: AppDialog(
        title: 'Correct the severity',
        size: AppDialogSize.form,
        description: '${incident.incidentNo} is ${incident.severityLabel.toLowerCase()}. '
            'Correcting it restates the period it occurred in.',
        actions: [
          AppDialogAction(
            id: SafetyIncidentSeverityDialog._dismissId,
            label: 'Cancel',
            kind: AppDialogActionKind.dismiss,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
          ),
          AppDialogAction(
            id: SafetyIncidentSeverityDialog._submitId,
            label: 'Correct it',
            onPressed: _complete ? _submit : null,
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String?>(
              key: SafetyIncidentSeverityDialog.severityKey,
              initialValue: _severity,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Correct the severity to',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Leave the severity alone'),
                ),
                for (final level in _offerableSeverities)
                  DropdownMenuItem<String?>(
                    value: level,
                    child: Text(SeverityLevel.label(level)),
                  ),
              ],
              onChanged: _awaiting ? null : (value) => setState(() => _severity = value),
            ),
            const SizedBox(height: Spacing.md),
            TextField(
              key: SafetyIncidentSeverityDialog.noteKey,
              controller: _note,
              enabled: !_awaiting,
              minLines: 2,
              maxLines: 3,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Note',
                helperText: 'Why the severity is being corrected.',
                border: OutlineInputBorder(),
              ),
            ),
            if (_failure != null)
              Padding(
                key: SafetyIncidentSeverityDialog.failureKey,
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
