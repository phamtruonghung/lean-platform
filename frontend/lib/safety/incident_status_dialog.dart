/// Moving the status one step along the ladder (issue #228):
/// `open -> investigating -> actions_pending`.
///
/// Addressed rather than popped — `/safety/incidents/:id/status` (ADR-0021) —
/// and offered to anyone with an edit Grant reaching the incident's Org Unit;
/// the API refuses anyone else with a 403. `closed` is never offered here:
/// closing needs Safety authority, a note and the days settled, none of which
/// this ordinary move asks for, so it has its own address
/// (`SafetyIncidentCloseDialog`).
///
/// There is only ever one legal next step, so this is a confirmation rather
/// than a picker: the ladder's own next word is the one word offered.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import 'incident_detail_bloc.dart';
import 'safety_incident.dart';

class SafetyIncidentStatusDialog extends StatefulWidget {
  const SafetyIncidentStatusDialog({super.key, required this.incident});

  final SafetyIncident incident;

  static const ValueKey<String> loadingKey = ValueKey<String>('safety-incident-status-loading');
  static const ValueKey<String> submitKey = ValueKey<String>('safety-incident-status-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('safety-incident-status-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('safety-incident-status-failure');
  static const ValueKey<String> refusedKey = ValueKey<String>('safety-incident-status-refused');

  @override
  State<SafetyIncidentStatusDialog> createState() => _SafetyIncidentStatusDialogState();
}

class _SafetyIncidentStatusDialogState extends State<SafetyIncidentStatusDialog> {
  bool _awaiting = false;
  String? _failure;

  void _submit(String next) {
    if (_awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    context.read<SafetyIncidentDetailBloc>().add(SafetyIncidentStatusMoved(status: next));
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
    final next = incident.nextStatus;

    if (next == null) {
      return AlertDialog(
        key: SafetyIncidentStatusDialog.refusedKey,
        content: Text(
          incident.isClosed
              ? 'This Safety incident is closed; its status cannot be moved.'
              : 'This Safety incident is already ${incident.statusLabel.toLowerCase()}; '
                  'only closing moves it further.',
        ),
      );
    }

    return BlocListener<SafetyIncidentDetailBloc, SafetyIncidentDetailState>(
      listener: _onDetailChanged,
      child: AlertDialog(
        title: const Text('Move the status'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${incident.incidentNo} moves from ${incident.statusLabel} to '
                '${SafetyIncidentStatus.label(next)}.',
                style: theme.textTheme.bodyMedium,
              ),
              if (_failure != null)
                Padding(
                  key: SafetyIncidentStatusDialog.failureKey,
                  padding: const EdgeInsets.only(top: Spacing.md),
                  child: Text(
                    _failure!,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            key: SafetyIncidentStatusDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: SafetyIncidentStatusDialog.submitKey,
            onPressed: _awaiting ? null : () => _submit(next),
            child: Text('Move to ${SafetyIncidentStatus.label(next)}'),
          ),
        ],
      ),
    );
  }
}
