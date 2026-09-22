/// Marking an exception on one attendance row (issue #249, ADR-0040): a
/// status chosen from the fixed six-value set, an absence reason chosen from
/// the catalogue when the status needs one, worked minutes, overtime
/// minutes, and a note. Every value here is chosen from a list, never typed
/// (AGENTS.md §7, ADR-0023) — the status and the absence reason are both
/// `DropdownButtonFormField`s over a set small enough to scan, not an
/// `AppSearchField` (that widget is for a set nobody can scan, like the
/// Directory the stand-in picker searches).
///
/// Opened both for a normal correction and for a correction after the sheet
/// is already confirmed (ADR-0040: "a confirmed sheet can still be
/// corrected") — this dialog does not know or care which; the Bloc's own
/// `AttendanceRecordCorrected` handler makes no distinction either.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import 'attendance.dart';
import 'attendance_sheet_bloc.dart';

class AttendanceRecordDialog extends StatefulWidget {
  const AttendanceRecordDialog({
    super.key,
    required this.record,
    required this.absenceReasons,
  });

  final AttendanceRecord record;
  final List<AbsenceReason> absenceReasons;

  static const ValueKey<String> statusFieldKey = ValueKey<String>('attendance-record-status');
  static const ValueKey<String> reasonFieldKey = ValueKey<String>('attendance-record-reason');
  static const ValueKey<String> workedMinutesFieldKey =
      ValueKey<String>('attendance-record-worked-minutes');
  static const ValueKey<String> overtimeMinutesFieldKey =
      ValueKey<String>('attendance-record-overtime-minutes');
  static const ValueKey<String> noteFieldKey = ValueKey<String>('attendance-record-note');
  static const ValueKey<String> saveKey = ValueKey<String>('attendance-record-save');
  static const ValueKey<String> cancelKey = ValueKey<String>('attendance-record-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('attendance-record-failure');

  /// Opens the dialog over the sheet Screen — the same explicit Bloc hand-off
  /// every dialog in this Module uses (`EmployeeDepartureDialog.open`'s own
  /// pattern), `showDialog`'s route sitting outside the route-scoped
  /// `BlocProvider`.
  static Future<void> open(
    BuildContext context,
    AttendanceRecord record,
    List<AbsenceReason> absenceReasons,
  ) {
    final bloc = context.read<AttendanceSheetBloc>();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => BlocProvider<AttendanceSheetBloc>.value(
        value: bloc,
        child: AttendanceRecordDialog(record: record, absenceReasons: absenceReasons),
      ),
    );
  }

  @override
  State<AttendanceRecordDialog> createState() => _AttendanceRecordDialogState();
}

class _AttendanceRecordDialogState extends State<AttendanceRecordDialog> {
  late String _status = widget.record.attendanceStatus;
  late String? _absenceReasonId = widget.record.absenceReason?.id;
  late final TextEditingController _workedMinutes =
      TextEditingController(text: widget.record.workedMinutes.toString());
  late final TextEditingController _overtimeMinutes =
      TextEditingController(text: widget.record.overtimeMinutes.toString());
  late final TextEditingController _note = TextEditingController(text: widget.record.note ?? '');

  bool _awaiting = false;
  String? _failure;

  @override
  void dispose() {
    _workedMinutes.dispose();
    _overtimeMinutes.dispose();
    _note.dispose();
    super.dispose();
  }

  void _submit() {
    if (_awaiting) return;

    final changes = <String, Object?>{'attendanceStatus': _status};
    if (attendanceStatusNeedsReason(_status)) {
      if (_absenceReasonId == null) {
        setState(() => _failure = 'Choose a reason for this absence.');
        return;
      }
      changes['absenceReasonId'] = _absenceReasonId;
    } else {
      changes['workedMinutes'] = int.tryParse(_workedMinutes.text) ?? 0;
      changes['overtimeMinutes'] = int.tryParse(_overtimeMinutes.text) ?? 0;
    }
    changes['note'] = _note.text.trim().isEmpty ? null : _note.text.trim();

    setState(() {
      _awaiting = true;
      _failure = null;
    });
    context
        .read<AttendanceSheetBloc>()
        .add(AttendanceRecordCorrected(recordId: widget.record.id, changes: changes));
  }

  void _onStateChanged(BuildContext context, AttendanceSheetState state) {
    if (!_awaiting || state is! AttendanceSheetLoaded || state.isMutating) return;
    if (state.mutationFailure != null) {
      setState(() {
        _awaiting = false;
        _failure = state.mutationFailure;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final needsReason = attendanceStatusNeedsReason(_status);
    return BlocListener<AttendanceSheetBloc, AttendanceSheetState>(
      listener: _onStateChanged,
      child: AlertDialog(
        title: Text('Mark ${widget.record.displayName}'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  key: AttendanceRecordDialog.statusFieldKey,
                  initialValue: _status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: [
                    for (final status in attendanceStatuses)
                      DropdownMenuItem(value: status, child: Text(attendanceStatusLabel(status))),
                  ],
                  onChanged: _awaiting ? null : (value) => setState(() => _status = value!),
                ),
                if (needsReason) ...[
                  const SizedBox(height: Spacing.md),
                  DropdownButtonFormField<String>(
                    key: AttendanceRecordDialog.reasonFieldKey,
                    initialValue: _absenceReasonId,
                    decoration: const InputDecoration(labelText: 'Reason'),
                    items: [
                      for (final reason in widget.absenceReasons)
                        DropdownMenuItem(value: reason.id, child: Text(reason.name)),
                    ],
                    onChanged: _awaiting ? null : (value) => setState(() => _absenceReasonId = value),
                  ),
                ] else ...[
                  const SizedBox(height: Spacing.md),
                  TextField(
                    key: AttendanceRecordDialog.workedMinutesFieldKey,
                    controller: _workedMinutes,
                    enabled: !_awaiting,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Worked minutes'),
                  ),
                  const SizedBox(height: Spacing.md),
                  TextField(
                    key: AttendanceRecordDialog.overtimeMinutesFieldKey,
                    controller: _overtimeMinutes,
                    enabled: !_awaiting,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Overtime minutes'),
                  ),
                ],
                const SizedBox(height: Spacing.md),
                TextField(
                  key: AttendanceRecordDialog.noteFieldKey,
                  controller: _note,
                  enabled: !_awaiting,
                  decoration: const InputDecoration(labelText: 'Note (optional)'),
                ),
                if (_failure != null)
                  Padding(
                    key: AttendanceRecordDialog.failureKey,
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
            key: AttendanceRecordDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: AttendanceRecordDialog.saveKey,
            onPressed: _awaiting ? null : _submit,
            child: Text(_awaiting ? 'Saving…' : 'Save'),
          ),
        ],
      ),
    );
  }
}
