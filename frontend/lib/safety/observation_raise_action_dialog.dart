/// Raising an Action from a Safety observation (issue #231) — closing the
/// loop on a safety walk: an unsafe condition becomes something somebody
/// owns.
///
/// Addressed rather than popped — `/safety/observations/:id/raise-action`
/// (ADR-0021): a refresh lands on the record with the form open, and a
/// colleague can be handed the address of the act itself.
///
/// Mirrors `SafetyIncidentRaiseConcernDialog` closely, with the one
/// difference #231's own acceptance criterion asks for: the caller chooses
/// the Action's **kind** from `ActionType`'s own known set, rather than
/// always raising a Concern. The server fills the rest in by its own rules:
/// the Org Unit is the observation's own, the number comes from the Site's
/// own sequence, and the Action starts on a cycle-1 Plan of its own.
///
/// The write goes to the Actions Module (its own route, through its own
/// client entry point) and the answer is the Action, so the dialog closes on
/// the Bloc's own `notice` and the Screen beneath it re-reads the
/// observation.
///
/// **Its shell is `AppDialog`** (issue #398, `docs/design-language.md` §11):
/// four fields is the `form` width, the shell owns the title row, the one
/// scroller and the action row, and the sentence about where the Action is
/// raised is the dialog's own `description`.
library;

import 'package:flutter/material.dart' hide Action;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../actions/actions.dart';
import '../l10n/app_localizations.dart';
import '../theme.dart';
import '../widgets/app_dialog.dart';
import 'observation_detail_bloc.dart';
import 'safety_observation.dart';

class SafetyObservationRaiseActionDialog extends StatefulWidget {
  const SafetyObservationRaiseActionDialog({super.key, required this.observation});

  final SafetyObservation observation;

  static const ValueKey<String> loadingKey =
      ValueKey<String>('safety-observation-raise-action-loading');
  static const ValueKey<String> actionTypeKey =
      ValueKey<String>('safety-observation-raise-action-type');
  static const ValueKey<String> titleKey =
      ValueKey<String>('safety-observation-raise-action-title');
  static const ValueKey<String> descriptionKey =
      ValueKey<String>('safety-observation-raise-action-description');
  static const ValueKey<String> priorityKey =
      ValueKey<String>('safety-observation-raise-action-priority');
  static const ValueKey<String> failureKey =
      ValueKey<String>('safety-observation-raise-action-failure');

  /// The actions' ids, and the keys `AppDialog` gives them
  /// (`docs/design-language.md` §11).
  static const String _submitId = 'safety-observation-raise-action-submit';
  static const String _dismissId = 'safety-observation-raise-action-cancel';
  static ValueKey<String> get submitKey => AppDialog.actionKey(_submitId);
  static ValueKey<String> get cancelKey => AppDialog.actionKey(_dismissId);

  @override
  State<SafetyObservationRaiseActionDialog> createState() =>
      _SafetyObservationRaiseActionDialogState();
}

class _SafetyObservationRaiseActionDialogState
    extends State<SafetyObservationRaiseActionDialog> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _description = TextEditingController();

  String? _actionType;
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

  bool get _complete =>
      _actionType != null && _title.text.trim().isNotEmpty && !_awaiting;

  void _submit() {
    if (!_complete) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    final description = _description.text.trim();
    context.read<SafetyObservationDetailBloc>().add(
          SafetyObservationActionRaised(
            actionType: _actionType!,
            title: _title.text.trim(),
            description: description.isEmpty ? null : description,
            priority: _priority,
          ),
        );
  }

  /// The Bloc reports the outcome on its own state rather than returning one,
  /// so this is where the dialog learns it landed: still in flight, refused
  /// with a sentence, or done and ready to close.
  void _onDetailChanged(BuildContext context, SafetyObservationDetailState state) {
    if (_done || !_awaiting) return;
    if (state is! SafetyObservationDetailLoaded) return;
    if (state.isRaisingAction) return;
    final failure = state.actionRaiseFailure;
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
    final record = widget.observation;

    return BlocListener<SafetyObservationDetailBloc, SafetyObservationDetailState>(
      listener: _onDetailChanged,
      // A form (520): four fields (§11).
      child: AppDialog(
        title: l10n.commonRaiseAnAction,
        size: AppDialogSize.form,
        description: l10n.observationRaiseActionThisObservationIsRecordedAtAndThe(record.orgUnitName),
        actions: [
          AppDialogAction(
            id: SafetyObservationRaiseActionDialog._dismissId,
            label: l10n.commonCancel,
            kind: AppDialogActionKind.dismiss,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
          ),
          AppDialogAction(
            id: SafetyObservationRaiseActionDialog._submitId,
            label: l10n.actionFormRaiseIt,
            onPressed: _complete ? _submit : null,
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String?>(
              key: SafetyObservationRaiseActionDialog.actionTypeKey,
              initialValue: _actionType,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.commonKindOfAction,
                helperText: l10n.observationRaiseActionChooseWhatThisIs,
                border: OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem<String?>(value: null, child: Text(l10n.observationRaiseActionChooseAKind)),
                for (final type in ActionType.values)
                  DropdownMenuItem<String?>(value: type.wire, child: Text(type.label)),
              ],
              onChanged: _awaiting
                  ? null
                  : (value) => setState(() => _actionType = value),
            ),
            const SizedBox(height: Spacing.md),
            TextField(
              key: SafetyObservationRaiseActionDialog.titleKey,
              controller: _title,
              enabled: !_awaiting,
              maxLines: 1,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: l10n.observationRaiseActionWhatNeedsDoing,
                helperText: l10n.observationRaiseActionTheActionIsReadInTheAction,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: Spacing.md),
            TextField(
              key: SafetyObservationRaiseActionDialog.descriptionKey,
              controller: _description,
              enabled: !_awaiting,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: l10n.commonAnythingKnownYet,
                helperText: l10n.observationRaiseActionOptionalTheSafetyObservationItselfIsAlready,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: Spacing.md),
            DropdownButtonFormField<int>(
              key: SafetyObservationRaiseActionDialog.priorityKey,
              initialValue: _priority,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.commonPriority,
                helperText: l10n.common1IsWorst,
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
                key: SafetyObservationRaiseActionDialog.failureKey,
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
