/// Recording a Safety observation (issue #230): a safe act, an unsafe act,
/// or an unsafe condition, under one category, ranked by the worst credible
/// outcome, with the action taken on the spot and whether stop-work
/// authority was exercised.
///
/// Addressed rather than popped — `/safety/observations/record` (ADR-0021,
/// the same choice `SafetyIncidentFormDialog` makes) — so a refresh lands on
/// the register with the form open, and a widget test drives it through the
/// router the way `nonconformances_test.dart` drives its own record form.
///
/// **Type, category and severity potential are `DropdownButtonFormField`s,
/// never typed** (ADR-0023): three, ten and four fixed values,
/// `docs/frontend-layout.md`'s set-size rule. No Asset and no Employee
/// picker here — an observation names no injured party and no equipment the
/// way a Safety incident may, so this form is shorter than
/// `SafetyIncidentFormDialog` by design, not by omission.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../maintenance/maintenance.dart';
import '../people/people.dart';
import '../theme.dart';
import '../widgets/app_date_time_field.dart';
import 'safety_observation.dart';
import 'safety_observations_bloc.dart';

class SafetyObservationFormDialog extends StatefulWidget {
  const SafetyObservationFormDialog({super.key, required this.siteId});

  /// The Site the register is showing. The Org Unit chooser opens on it, and
  /// the recording is sent to it.
  final String siteId;

  static const ValueKey<String> typeKey = ValueKey<String>('safety-observation-form-type');
  static const ValueKey<String> categoryKey =
      ValueKey<String>('safety-observation-form-category');
  static const ValueKey<String> severityPotentialKey =
      ValueKey<String>('safety-observation-form-severity-potential');
  static const ValueKey<String> descriptionKey =
      ValueKey<String>('safety-observation-form-description');
  static const ValueKey<String> actionTakenKey =
      ValueKey<String>('safety-observation-form-action-taken');
  static const ValueKey<String> stopWorkKey =
      ValueKey<String>('safety-observation-form-stop-work');
  static const ValueKey<String> observedAtKey =
      ValueKey<String>('safety-observation-form-observed-at');
  static const ValueKey<String> submitKey = ValueKey<String>('safety-observation-form-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('safety-observation-form-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('safety-observation-form-failure');
  static const ValueKey<String> chosenOrgUnitKey =
      ValueKey<String>('safety-observation-form-chosen-org-unit');

  @override
  State<SafetyObservationFormDialog> createState() => _SafetyObservationFormDialogState();
}

class _SafetyObservationFormDialogState extends State<SafetyObservationFormDialog> {
  final TextEditingController _description = TextEditingController();
  final TextEditingController _actionTaken = TextEditingController();

  String? _observationType;
  String? _category;
  String? _severityPotential;
  bool _isStopWork = false;
  OrgUnitNode? _orgUnit;

  // Left null rather than defaulted: the baseline column itself defaults to
  // now() on the server, and a form for something usually recorded on the
  // spot need not force a caller through the picker for the common case.
  DateTime? _observedAt;

  bool _awaiting = false;
  String? _failure;

  @override
  void dispose() {
    _description.dispose();
    _actionTaken.dispose();
    super.dispose();
  }

  bool get _complete =>
      _orgUnit != null &&
      _observationType != null &&
      _category != null &&
      _severityPotential != null &&
      _description.text.trim().isNotEmpty;

  void _submit() {
    if (!_complete || _awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });

    final description = _description.text.trim();
    final actionTaken = _actionTaken.text.trim();

    context.read<SafetyObservationsBloc>().add(
          SafetyObservationRecordConfirmed(
            orgUnitId: _orgUnit!.id,
            observationType: _observationType!,
            category: _category!,
            severityPotential: _severityPotential!,
            description: description,
            isStopWork: _isStopWork,
            actionTaken: actionTaken.isEmpty ? null : actionTaken,
            observedAt: _observedAt?.toUtc().toIso8601String(),
          ),
        );
  }

  /// Whether this form has finished with its one act — the same guard
  /// `SafetyIncidentFormDialog._done` keeps, and for the same reason: the
  /// Bloc emits twice on the way out (once when the recording lands, once
  /// when the re-read answers), and both look like success to this listener.
  bool _done = false;

  void _onRegisterChanged(BuildContext context, SafetyObservationsState state) {
    if (_done || !_awaiting || state is! SafetyObservationsLoaded || state.isRecording) return;
    if (state.recordFailure != null) {
      setState(() {
        _awaiting = false;
        _failure = state.recordFailure;
      });
      return;
    }
    _done = true;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BlocListener<SafetyObservationsBloc, SafetyObservationsState>(
      listener: _onRegisterChanged,
      child: AlertDialog(
        title: const Text('Record a Safety observation'),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: Spacing.md,
                  runSpacing: Spacing.sm,
                  children: [
                    SizedBox(
                      width: 260,
                      child: DropdownButtonFormField<String?>(
                        key: SafetyObservationFormDialog.typeKey,
                        initialValue: _observationType,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Type',
                          helperText: 'A safe act, an unsafe act, or an unsafe condition.',
                          border: OutlineInputBorder(),
                        ),
                        items: ObservationType.dropdownItems(),
                        onChanged: _awaiting
                            ? null
                            : (type) => setState(() => _observationType = type),
                      ),
                    ),
                    SizedBox(
                      width: 260,
                      child: DropdownButtonFormField<String?>(
                        key: SafetyObservationFormDialog.categoryKey,
                        initialValue: _category,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Category',
                          border: OutlineInputBorder(),
                        ),
                        items: ObservationCategory.dropdownItems(),
                        onChanged:
                            _awaiting ? null : (category) => setState(() => _category = category),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Spacing.md),
                DropdownButtonFormField<String?>(
                  key: SafetyObservationFormDialog.severityPotentialKey,
                  initialValue: _severityPotential,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Severity potential',
                    helperText: 'The worst credible outcome, not what actually happened.',
                    border: OutlineInputBorder(),
                  ),
                  items: SeverityPotential.dropdownItems(),
                  onChanged: _awaiting
                      ? null
                      : (potential) => setState(() => _severityPotential = potential),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: SafetyObservationFormDialog.descriptionKey,
                  controller: _description,
                  enabled: !_awaiting,
                  minLines: 2,
                  maxLines: 4,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    helperText: 'What was seen.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: SafetyObservationFormDialog.actionTakenKey,
                  controller: _actionTaken,
                  enabled: !_awaiting,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Action taken (optional)',
                    helperText: 'What was done on the spot.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                SwitchListTile(
                  key: SafetyObservationFormDialog.stopWorkKey,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Stop-work authority was exercised'),
                  subtitle: const Text(
                    'Rare, and the single strongest signal that the safety culture is real.',
                  ),
                  value: _isStopWork,
                  onChanged: _awaiting ? null : (value) => setState(() => _isStopWork = value),
                ),
                const SizedBox(height: Spacing.md),
                AppDateTimeField(
                  key: SafetyObservationFormDialog.observedAtKey,
                  name: 'safety-observation-observed-at',
                  label: 'Observed at (optional)',
                  helperText: 'When it was seen, if not now. This is what decides the '
                      'production day and shift it is filed against.',
                  value: _observedAt,
                  optional: true,
                  enabled: !_awaiting,
                  onChanged: (value) => setState(() => _observedAt = value),
                ),
                const SizedBox(height: Spacing.lg),
                OrgUnitChooser(
                  selectedId: _orgUnit?.id,
                  enabled: !_awaiting,
                  showSitePicker: false,
                  title: 'Where it was seen',
                  description: 'Choose the Org Unit the observation was made at. This is what '
                      'decides who may act on it.',
                  onSelected: (node) => setState(() => _orgUnit = node),
                ),
                if (_orgUnit != null)
                  Padding(
                    key: SafetyObservationFormDialog.chosenOrgUnitKey,
                    padding: const EdgeInsets.only(top: Spacing.sm),
                    child: Text(
                      'This Safety observation will be recorded at ${_orgUnit!.name}.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                if (_failure != null)
                  Padding(
                    key: SafetyObservationFormDialog.failureKey,
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
            key: SafetyObservationFormDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: SafetyObservationFormDialog.submitKey,
            onPressed: _complete && !_awaiting ? _submit : null,
            child: const Text('Record it'),
          ),
        ],
      ),
    );
  }
}
