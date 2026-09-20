/// Closing a Safety incident, with a note (issue #228, #223 decision 4) —
/// the judgement of someone accountable for the place.
///
/// Addressed rather than popped — `/safety/incidents/:id/close` (ADR-0021).
/// The Screen offers this address only to a caller holding Safety authority
/// at the incident's Org Unit (ADR-0039); the API refuses anyone else with a
/// 403, a missing note with a 400, and — for any rung above the no-injury one
/// — days that have not been settled with a 409.
///
/// **Never refused for an open Concern raised from the incident.** #223
/// decision 4 states this in so many words: a Concern closes only on a
/// countermeasure that held, which is months, and this record does not wait
/// on it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../platform/router.dart';
import '../theme.dart';
import 'incident_detail_bloc.dart';
import 'safety_incident.dart';

class SafetyIncidentCloseDialog extends StatefulWidget {
  const SafetyIncidentCloseDialog({super.key, required this.incident});

  final SafetyIncident incident;

  static const ValueKey<String> loadingKey = ValueKey<String>('safety-incident-close-loading');
  static const ValueKey<String> noteKey = ValueKey<String>('safety-incident-close-note');
  static const ValueKey<String> submitKey = ValueKey<String>('safety-incident-close-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('safety-incident-close-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('safety-incident-close-failure');
  static const ValueKey<String> refusedKey = ValueKey<String>('safety-incident-close-refused');

  @override
  State<SafetyIncidentCloseDialog> createState() => _SafetyIncidentCloseDialogState();
}

class _SafetyIncidentCloseDialogState extends State<SafetyIncidentCloseDialog> {
  final TextEditingController _note = TextEditingController();

  bool _awaiting = false;
  String? _failure;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  bool get _complete => _note.text.trim().isNotEmpty && !_awaiting;

  void _submit() {
    if (!_complete) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    context.read<SafetyIncidentDetailBloc>().add(SafetyIncidentClosed(note: _note.text));
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

    // Read here, in a build, for the reason the Screen reads it there.
    if (!holdsSafetyAuthority(context, incident.orgUnitId)) {
      return AlertDialog(
        key: SafetyIncidentCloseDialog.refusedKey,
        content: const Text(
          "Closing a Safety incident needs Safety authority at its Org Unit.",
        ),
      );
    }
    if (incident.isClosed) {
      return AlertDialog(
        key: SafetyIncidentCloseDialog.refusedKey,
        content: const Text('This Safety incident is already closed.'),
      );
    }

    return BlocListener<SafetyIncidentDetailBloc, SafetyIncidentDetailState>(
      listener: _onDetailChanged,
      child: AlertDialog(
        title: const Text('Close this Safety incident'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${incident.incidentNo} will be closed. A Concern raised from it, if any, keeps '
                  'working the cause on its own.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: SafetyIncidentCloseDialog.noteKey,
                  controller: _note,
                  enabled: !_awaiting,
                  minLines: 2,
                  maxLines: 3,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Note',
                    helperText: 'Why this incident is being closed.',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_failure != null)
                  Padding(
                    key: SafetyIncidentCloseDialog.failureKey,
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
            key: SafetyIncidentCloseDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Leave it open'),
          ),
          FilledButton(
            key: SafetyIncidentCloseDialog.submitKey,
            onPressed: _complete ? _submit : null,
            child: const Text('Close it'),
          ),
        ],
      ),
    );
  }
}
