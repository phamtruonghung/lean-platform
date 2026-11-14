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

import '../l10n/app_localizations.dart';
import '../platform/router.dart';
import '../theme.dart';
import '../widgets/app_dialog.dart';
import 'incident_detail_bloc.dart';
import 'safety_incident.dart';
import '../widgets/notice_text.dart';

class SafetyIncidentDaysDialog extends StatefulWidget {
  const SafetyIncidentDaysDialog({super.key, required this.incident});

  final SafetyIncident incident;

  static const ValueKey<String> loadingKey = ValueKey<String>('safety-incident-days-loading');
  static const ValueKey<String> lostTimeKey = ValueKey<String>('safety-incident-days-lost-time');
  static const ValueKey<String> restrictedKey =
      ValueKey<String>('safety-incident-days-restricted');
  /// The actions' ids, and the keys `AppDialog` gives them
  /// (`docs/design-language.md` §11).
  static const String _submitId = 'safety-incident-days-submit';
  static const String _dismissId = 'safety-incident-days-cancel';
  static const String _closeId = 'safety-incident-days-refused-close';
  static ValueKey<String> get submitKey => AppDialog.actionKey(_submitId);
  static ValueKey<String> get cancelKey => AppDialog.actionKey(_dismissId);
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
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final incident = widget.incident;

    if (!holdsSafetyAuthority(context, incident.orgUnitId)) {
      // A refused dialog still needs a way out: the sentence is its own
      // description and the single action closes it.
      return AppDialog(
        key: SafetyIncidentDaysDialog.refusedKey,
        title: l10n.commonRecordTheDays,
        size: AppDialogSize.decision,
        description:
            l10n.incidentDaysRecordingTheDaysNeedsSafetyAuthorityAt,
        actions: [
          AppDialogAction(
            id: SafetyIncidentDaysDialog._closeId,
            label: l10n.downtimeClose,
            kind: AppDialogActionKind.dismiss,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      );
    }
    if (incident.isClosed) {
      return AppDialog(
        key: SafetyIncidentDaysDialog.refusedKey,
        title: l10n.commonRecordTheDays,
        size: AppDialogSize.decision,
        description: l10n.incidentDaysThisSafetyIncidentIsClosedItsDays,
        actions: [
          AppDialogAction(
            id: SafetyIncidentDaysDialog._closeId,
            label: l10n.downtimeClose,
            kind: AppDialogActionKind.dismiss,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      );
    }

    return BlocListener<SafetyIncidentDetailBloc, SafetyIncidentDetailState>(
      listener: _onDetailChanged,
      // A form (520): two numeric fields (§11).
      child: AppDialog(
        title: l10n.commonRecordTheDays,
        size: AppDialogSize.form,
        description: l10n.incidentDaysWhatCostZeroIsARealAnswer(incident.incidentNo),
        actions: [
          AppDialogAction(
            id: SafetyIncidentDaysDialog._dismissId,
            label: l10n.commonCancel,
            kind: AppDialogActionKind.dismiss,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
          ),
          AppDialogAction(
            id: SafetyIncidentDaysDialog._submitId,
            label: l10n.commonSave,
            onPressed: _complete ? _submit : null,
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: SafetyIncidentDaysDialog.lostTimeKey,
              controller: _lostTime,
              enabled: !_awaiting,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: l10n.commonLostTimeDays,
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
              decoration: InputDecoration(
                labelText: l10n.commonRestrictedDays,
                border: OutlineInputBorder(),
              ),
            ),
            if (_failure != null)
              Padding(
                key: SafetyIncidentDaysDialog.failureKey,
                padding: const EdgeInsets.only(top: Spacing.md),
                child: NoticeText(
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
