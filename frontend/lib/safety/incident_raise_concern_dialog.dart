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
///
/// **Its shell is `AppDialog`** (issue #398, `docs/design-language.md` §11):
/// three fields is the `form` width, the shell owns the title row, the one
/// scroller and the action row, and the sentence about where the Concern is
/// raised is the dialog's own `description`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/app_localizations.dart';
import '../theme.dart';
import '../widgets/app_dialog.dart';
import 'incident_detail_bloc.dart';
import 'safety_incident.dart';
import '../l10n/vocabulary.dart';

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
  static const ValueKey<String> failureKey =
      ValueKey<String>('safety-incident-raise-concern-failure');

  /// The actions' ids, and the keys `AppDialog` gives them
  /// (`docs/design-language.md` §11).
  static const String _submitId = 'safety-incident-raise-concern-submit';
  static const String _dismissId = 'safety-incident-raise-concern-cancel';
  static ValueKey<String> get submitKey => AppDialog.actionKey(_submitId);
  static ValueKey<String> get cancelKey => AppDialog.actionKey(_dismissId);

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
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final record = widget.incident;

    return BlocListener<SafetyIncidentDetailBloc, SafetyIncidentDetailState>(
      listener: _onDetailChanged,
      // A form (520): three fields (§11).
      child: AppDialog(
        title: l10n.nonconformanceRaiseConcern,
        size: AppDialogSize.form,
        description: l10n.incidentRaiseConcernIsRecordedAtAndTheConcernIs(record.incidentNo, record.orgUnitName),
        actions: [
          AppDialogAction(
            id: SafetyIncidentRaiseConcernDialog._dismissId,
            label: l10n.commonCancel,
            kind: AppDialogActionKind.dismiss,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
          ),
          AppDialogAction(
            id: SafetyIncidentRaiseConcernDialog._submitId,
            label: l10n.actionFormRaiseIt,
            onPressed: _complete ? _submit : null,
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: SafetyIncidentRaiseConcernDialog.titleKey,
              controller: _title,
              enabled: !_awaiting,
              maxLines: 1,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: l10n.incidentRaiseConcernWhatIsTheCauseToSolve,
                helperText: l10n.incidentRaiseConcernTheConcernIsReadInTheAction,
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
              decoration: InputDecoration(
                labelText: l10n.commonAnythingKnownYet,
                helperText: l10n.incidentRaiseConcernOptionalTheSafetyIncidentItselfIsAlready,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: Spacing.md),
            DropdownButtonFormField<int>(
              key: SafetyIncidentRaiseConcernDialog.priorityKey,
              initialValue: _priority,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.commonPriority,
                helperText: l10n.common1IsWorst,
                border: OutlineInputBorder(),
              ),
              items: [
                for (final (priority, label) in actionPriorityChoices(l10n))
                  DropdownMenuItem<int>(value: priority, child: Text(label)),
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
    );
  }
}
