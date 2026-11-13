/// A Trainee's answer at the shared floor device (issue #293, ADR-0016,
/// ADR-0043): the trainings waiting on whoever identifies here, each with
/// Confirm and Decline.
///
/// It is a dialog, not a Screen: CONTEXT.md's Screen entry says a dialog inside
/// a Screen is not a Screen, and the floor surface is reached as it already is
/// (no new Destination, no new Shell chrome). It is opened by `showDialog` from
/// the floor Screen, with the Bloc provided by the caller, the way the floor's
/// other flows are.
///
/// Confirming first asks what the answer is signed with (issue #319, ADR-0052):
/// the Signature the identified Employee keeps - read through the device's own
/// door and shown before it is applied - a mark drawn now, or none. With no
/// Signature kept there is no stored control. A decline carries none.
///
/// Two steps in one dialog: identify (Employee number and PIN), then the
/// Employee's own outstanding rows for this device. Done closes it and with it
/// the identification.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/app_localizations.dart';
import '../theme.dart';
import '../widgets/app_scan_field.dart';
import 'floor_training_bloc.dart';
import 'training_answer_dialog.dart';
import 'training_record.dart';

class FloorTrainingDialog extends StatefulWidget {
  const FloorTrainingDialog({super.key});

  static const ValueKey<String> employeeNoKey = ValueKey<String>('floor-training-employee-no');
  static const ValueKey<String> pinKey = ValueKey<String>('floor-training-pin');
  static const ValueKey<String> submitKey = ValueKey<String>('floor-training-submit');
  static const ValueKey<String> doneKey = ValueKey<String>('floor-training-done');
  static const ValueKey<String> failureKey = ValueKey<String>('floor-training-failure');
  static const ValueKey<String> listKey = ValueKey<String>('floor-training-list');
  static const ValueKey<String> emptyKey = ValueKey<String>('floor-training-empty');
  static ValueKey<String> rowKey(String traineeId) => ValueKey<String>('floor-training-row-$traineeId');
  static ValueKey<String> confirmKey(String traineeId) => ValueKey<String>('floor-training-confirm-$traineeId');
  static ValueKey<String> declineKey(String traineeId) => ValueKey<String>('floor-training-decline-$traineeId');

  @override
  State<FloorTrainingDialog> createState() => _FloorTrainingDialogState();
}

class _FloorTrainingDialogState extends State<FloorTrainingDialog> {
  final TextEditingController _employeeNo = TextEditingController();
  final TextEditingController _pin = TextEditingController();

  @override
  void dispose() {
    _employeeNo.dispose();
    _pin.dispose();
    super.dispose();
  }

  bool get _ready => _employeeNo.text.trim().isNotEmpty && _pin.text.trim().isNotEmpty;

  void _identify() {
    if (!_ready) return;
    context.read<FloorTrainingBloc>().add(
          FloorTrainingIdentified(employeeNo: _employeeNo.text.trim(), pin: _pin.text.trim()),
        );
    // The PIN has done its one job; do not leave it in the field.
    _pin.clear();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return BlocBuilder<FloorTrainingBloc, FloorTrainingState>(
      builder: (context, state) => AlertDialog(
        title: Text(state.isIdentified
            ? l10n.floorTrainingTrainingFor(state.employeeName ?? '')
            : l10n.floorTrainingYourTraining),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: state.isIdentified ? _list(state) : _identifyForm(state),
          ),
        ),
        actions: [
          TextButton(
            key: FloorTrainingDialog.doneKey,
            onPressed: state.isBusy ? null : () => Navigator.of(context).pop(),
            child: Text(state.isIdentified ? l10n.floorTrainingDone : l10n.commonCancel),
          ),
          if (!state.isIdentified)
            FilledButton(
              key: FloorTrainingDialog.submitKey,
              onPressed: _ready && !state.isBusy ? _identify : null,
              child: Text(l10n.floorTrainingShowMyTraining),
            ),
        ],
      ),
    );
  }

  // Confirming asks what the answer is signed with first (issue #319): the
  // Signature the Employee keeps - shown, read through the device's own door -
  // a mark drawn now, or none. Dismissing the choice sends nothing.
  Future<void> _confirm(TrainingToConfirm entry, FloorTrainingState state) async {
    final bloc = context.read<FloorTrainingBloc>();
    final signature = await showTrainingAnswerDialog(
      context,
      storedImage: state.signature,
      offersStored: state.signature != null,
    );
    if (signature == null) return;
    bloc.add(FloorTrainingAnswered(entry.traineeId, 'confirmed', signature: signature));
  }

  Widget _failure(FloorTrainingState state) {
    if (state.failure == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      key: FloorTrainingDialog.failureKey,
      padding: const EdgeInsets.only(top: Spacing.md),
      child: Text(state.failure!, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error)),
    );
  }

  Widget _identifyForm(FloorTrainingState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          AppLocalizations.of(context).floorTrainingWhoAreYouYourEmployeeNumberAnd,
          style: AppTypography.body(context)?.copyWith(color: AppColors.of(context).textMuted),
        ),
        const SizedBox(height: Spacing.md),
        AppScanField(
          key: FloorTrainingDialog.employeeNoKey,
          controller: _employeeNo,
          label: AppLocalizations.of(context).commonEmployeeNumber,
          helperText: AppLocalizations.of(context).floorTrainingScanTheBadgeOrTypeTheNumber,
          enabled: !state.isBusy,
          autofocus: true,
          advanceFocusOnScan: true,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: Spacing.md),
        TextField(
          key: FloorTrainingDialog.pinKey,
          controller: _pin,
          enabled: !state.isBusy,
          obscureText: true,
          keyboardType: TextInputType.number,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: AppLocalizations.of(context).commonPin, border: OutlineInputBorder()),
        ),
        _failure(state),
      ],
    );
  }

  Widget _list(FloorTrainingState state) {
    final theme = Theme.of(context);
    if (state.entries.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            key: FloorTrainingDialog.emptyKey,
            padding: const EdgeInsets.symmetric(vertical: Spacing.lg),
            child: Text(AppLocalizations.of(context).floorTrainingNothingIsWaitingOnYouAtThis, style: theme.textTheme.bodyLarge),
          ),
          _failure(state),
        ],
      );
    }
    return Column(
      key: FloorTrainingDialog.listKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final entry in state.entries) _row(entry, state),
        _failure(state),
      ],
    );
  }

  Widget _row(TrainingToConfirm entry, FloorTrainingState state) {
    final isBusy = state.isBusy;
    final theme = Theme.of(context);
    final trainer = entry.trainerName;
    final objective = entry.objective;
    return Card(
      key: FloorTrainingDialog.rowKey(entry.traineeId),
      margin: const EdgeInsets.only(bottom: Spacing.md),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${entry.number} · ${entry.title}', style: theme.textTheme.titleMedium),
            const SizedBox(height: Spacing.xs),
            Text(
              '${entry.trainedOn} · ${formatTrainingHours(entry.durationHours)} · ${entry.orgUnitName}'
              '${trainer == null ? '' : ' · trained by $trainer'}',
              style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.of(context).textMuted),
            ),
            if (objective != null && objective.isNotEmpty) ...[
              const SizedBox(height: Spacing.xs),
              Text(objective, style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: Spacing.md),
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.sm,
              children: [
                FilledButton(
                  key: FloorTrainingDialog.confirmKey(entry.traineeId),
                  onPressed: isBusy ? null : () => _confirm(entry, state),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                  child: Text(AppLocalizations.of(context).commonConfirm),
                ),
                OutlinedButton(
                  key: FloorTrainingDialog.declineKey(entry.traineeId),
                  onPressed: isBusy
                      ? null
                      : () => context.read<FloorTrainingBloc>().add(FloorTrainingAnswered(entry.traineeId, 'declined')),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                  child: Text(AppLocalizations.of(context).commonDecline),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
