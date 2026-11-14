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

import '../l10n/app_localizations.dart';
import '../theme.dart';
import '../widgets/app_dialog.dart';
import 'incident_detail_bloc.dart';
import 'safety_incident.dart';
import '../l10n/vocabulary.dart';

class SafetyIncidentStatusDialog extends StatefulWidget {
  const SafetyIncidentStatusDialog({super.key, required this.incident});

  final SafetyIncident incident;

  static const ValueKey<String> loadingKey = ValueKey<String>('safety-incident-status-loading');
  /// The actions' ids, and the keys `AppDialog` gives them
  /// (`docs/design-language.md` §11). A `ValueKey` is equal by value, so these
  /// find exactly the buttons the shell keyed.
  static const String _submitId = 'safety-incident-status-submit';
  static const String _dismissId = 'safety-incident-status-cancel';
  static const String _closeId = 'safety-incident-status-refused-close';
  static ValueKey<String> get submitKey => AppDialog.actionKey(_submitId);
  static ValueKey<String> get cancelKey => AppDialog.actionKey(_dismissId);
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
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final incident = widget.incident;
    final next = incident.nextStatus;

    if (next == null) {
      // A refused dialog still needs a way out: the sentence is the dialog's
      // own description and the single action closes it.
      return AppDialog(
        key: SafetyIncidentStatusDialog.refusedKey,
        title: l10n.incidentStatusMoveTheStatus,
        size: AppDialogSize.decision,
        description: incident.isClosed
            ? l10n.incidentStatusThisSafetyIncidentIsClosedItsStatus
            : l10n.incidentStatusThisSafetyIncidentIsAlreadyOnlyClosing(incident.statusLabel(l10n).toLowerCase()),
        actions: [
          AppDialogAction(
            id: SafetyIncidentStatusDialog._closeId,
            label: l10n.downtimeClose,
            kind: AppDialogActionKind.dismiss,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      );
    }

    return BlocListener<SafetyIncidentDetailBloc, SafetyIncidentDetailState>(
      listener: _onDetailChanged,
      // A decision (420): one sentence restating the move, and two actions —
      // there are no fields, because there is nothing to fill in.
      child: AppDialog(
        title: l10n.incidentStatusMoveTheStatus,
        size: AppDialogSize.decision,
        description: l10n.incidentStatusMovesFromTo(incident.incidentNo, incident.statusLabel(l10n), safetyIncidentStatusLabel(l10n, next)),
        actions: [
          AppDialogAction(
            id: SafetyIncidentStatusDialog._dismissId,
            label: l10n.commonCancel,
            kind: AppDialogActionKind.dismiss,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
          ),
          AppDialogAction(
            id: SafetyIncidentStatusDialog._submitId,
            label: l10n.incidentStatusMoveTo(safetyIncidentStatusLabel(l10n, next)),
            onPressed: _awaiting ? null : () => _submit(next),
          ),
        ],
        child: _failure == null
            ? null
            : Padding(
                key: SafetyIncidentStatusDialog.failureKey,
                padding: const EdgeInsets.only(top: Spacing.md),
                child: Text(
                  _failure!,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                ),
              ),
      ),
    );
  }
}
