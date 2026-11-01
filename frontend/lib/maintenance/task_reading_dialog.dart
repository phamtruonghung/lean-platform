/// Recording a reading against a Work order task that names a meter (issue
/// #79): the number observed, and an optional note.
///
/// This is the "while doing a job" path the ticket asks for. The reading goes
/// to the meter the Job plan task named, not to a free-floating number, so the
/// schedule that comes due on that meter's accumulated use sees it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import '../widgets/app_dialog.dart';
import 'work_order.dart';
import 'work_order_detail_bloc.dart';

class TaskReadingDialog extends StatefulWidget {
  const TaskReadingDialog({super.key, required this.task});

  final WorkOrderTask task;

  static const ValueKey<String> readingKey = ValueKey<String>('task-reading-reading');
  static const ValueKey<String> noteKey = ValueKey<String>('task-reading-note');

  /// The two actions' keys are the shell's own (`AppDialog.actionKey`), named
  /// for this dialog's use of them: a `ValueKey` is equal by value, so these
  /// find exactly the buttons `AppDialog` keyed (`docs/design-language.md` §11).
  static const String _submitId = 'task-reading-submit';
  static const String _cancelId = 'task-reading-cancel';
  static ValueKey<String> get submitKey => AppDialog.actionKey(_submitId);
  static ValueKey<String> get cancelKey => AppDialog.actionKey(_cancelId);
  static const ValueKey<String> failureKey = ValueKey<String>('task-reading-failure');

  static Future<void> open(BuildContext context, {required WorkOrderTask task}) {
    final bloc = context.read<WorkOrderDetailBloc>();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => BlocProvider<WorkOrderDetailBloc>.value(
        value: bloc,
        child: TaskReadingDialog(task: task),
      ),
    );
  }

  @override
  State<TaskReadingDialog> createState() => _TaskReadingDialogState();
}

class _TaskReadingDialogState extends State<TaskReadingDialog> {
  final TextEditingController _reading = TextEditingController();
  final TextEditingController _note = TextEditingController();

  bool _awaiting = false;
  String? _failure;

  @override
  void dispose() {
    _reading.dispose();
    _note.dispose();
    super.dispose();
  }

  num? get _readingValue => num.tryParse(_reading.text.trim());

  void _submit() {
    if (_readingValue == null || _awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    context.read<WorkOrderDetailBloc>().add(
          WorkOrderTaskReadingConfirmed(
            taskId: widget.task.id,
            reading: _readingValue!,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          ),
        );
  }

  void _onStateChanged(BuildContext context, WorkOrderDetailState state) {
    if (!_awaiting || state is! WorkOrderDetailLoaded || state.isRecording) return;
    if (state.readingFailure != null) {
      setState(() {
        _awaiting = false;
        _failure = state.readingFailure;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final task = widget.task;
    return BlocListener<WorkOrderDetailBloc, WorkOrderDetailState>(
      listener: _onStateChanged,
      // The form width (520): two fields under an instruction (§11).
      child: AppDialog(
        title: 'Record a reading on ${task.meterName ?? task.meterCode ?? 'the meter'}',
        size: AppDialogSize.form,
        actions: [
          AppDialogAction(
            id: TaskReadingDialog._cancelId,
            label: 'Cancel',
            kind: AppDialogActionKind.dismiss,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
          ),
          AppDialogAction(
            id: TaskReadingDialog._submitId,
            label: _awaiting ? 'Saving…' : 'Record reading',
            onPressed: _readingValue != null && !_awaiting ? _submit : null,
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(task.instruction, style: AppTypography.dense(context)),
            const SizedBox(height: Spacing.md),
            TextField(
              key: TaskReadingDialog.readingKey,
              controller: _reading,
              enabled: !_awaiting,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'What the meter reads',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: Spacing.md),
            TextField(
              key: TaskReadingDialog.noteKey,
              controller: _note,
              enabled: !_awaiting,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            if (_failure != null)
              Padding(
                key: TaskReadingDialog.failureKey,
                padding: const EdgeInsets.only(top: Spacing.md),
                child: Text(
                  _failure!,
                  style: AppTypography.dense(context)?.copyWith(color: palette.statusDanger),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
