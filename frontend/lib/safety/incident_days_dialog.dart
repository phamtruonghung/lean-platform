/// Recording what the injury cost: the lost-time and restricted days (issue
/// #228).
///
/// Addressed rather than popped — `/safety/incidents/:id/days` (ADR-0021).
/// The Screen offers this address only to a caller holding Safety authority
/// at the incident's Org Unit (ADR-0039); the API refuses anyone else with a
/// 403. Not offered once the incident is closed.
///
/// Both counts are required on every submission — zero is a real answer, and
/// this is the act that "settles" the days closing above the no-injury rung
/// waits on: a caller who sends only one of the two has not said what the
/// other one is.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../platform/router.dart';
import '../theme.dart';
import 'incident_detail_bloc.dart';
import 'safety_incident.dart';

class SafetyIncidentDaysDialog extends StatefulWidget {
  const SafetyIncidentDaysDialog({super.key, required this.incident});

  final SafetyIncident incident;

  static const ValueKey<String> loadingKey = ValueKey<String>('safety-incident-days-loading');
  static const ValueKey<String> lostTimeKey = ValueKey<String>('safety-incident-days-lost-time');
  static const ValueKey<String> restrictedKey =
      ValueKey<String>('safety-incident-days-restricted');
  static const ValueKey<String> submitKey = ValueKey<String>('safety-incident-days-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('safety-incident-days-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('safety-incident-days-failure');
  static const ValueKey<String> refusedKey = ValueKey<String>('safety-incident-days-refused');

  @override
  State<SafetyIncidentDaysDialog> createState() => _SafetyIncidentDaysDialogState();
}

class _SafetyIncidentDaysDialogState extends State<SafetyIncidentDaysDialog> {
  late final TextEditingController _lostTime =
      TextEditingController(text: widget.incident.lostTimeDays.toString());
  late final TextEditingController _restricted =
      TextEditingController(text: widget.incident.restrictedDays.toString());

  bool _awaiting = false;
  String? _failure;

  @override
  void dispose() {
    _lostTime.dispose();
    _restricted.dispose();
    super.dispose();
  }

  int? get _lostTimeDays => int.tryParse(_lostTime.text.trim());
  int? get _restrictedDays => int.tryParse(_restricted.text.trim());

  bool get _complete {
    final lostTime = _lostTimeDays;
    final restricted = _restrictedDays;
    return !_awaiting && lostTime != null && lostTime >= 0 && restricted != null && restricted >= 0;
  }

  void _submit() {
    final lostTime = _lostTimeDays;
    final restricted = _restrictedDays;
    if (!_complete || lostTime == null || restricted == null) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    context.read<SafetyIncidentDetailBloc>().add(
          SafetyIncidentDaysRecorded(lostTimeDays: lostTime, restrictedDays: restricted),
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

    if (!holdsSafetyAuthority(context, incident.orgUnitId)) {
      return AlertDialog(
        key: SafetyIncidentDaysDialog.refusedKey,
        content: const Text(
          "Recording the days needs Safety authority at this Safety incident's Org Unit.",
        ),
      );
    }
    if (incident.isClosed) {
      return AlertDialog(
        key: SafetyIncidentDaysDialog.refusedKey,
        content: const Text('This Safety incident is closed; its days cannot be changed.'),
      );
    }

    return BlocListener<SafetyIncidentDetailBloc, SafetyIncidentDetailState>(
      listener: _onDetailChanged,
      child: AlertDialog(
        title: const Text('Record the days'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'What ${incident.incidentNo} cost — zero is a real answer, and settles it.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: SafetyIncidentDaysDialog.lostTimeKey,
                  controller: _lostTime,
                  enabled: !_awaiting,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Lost-time days',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: SafetyIncidentDaysDialog.restrictedKey,
                  controller: _restricted,
                  enabled: !_awaiting,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Restricted days',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_failure != null)
                  Padding(
                    key: SafetyIncidentDaysDialog.failureKey,
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
            key: SafetyIncidentDaysDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: SafetyIncidentDaysDialog.submitKey,
            onPressed: _complete ? _submit : null,
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
