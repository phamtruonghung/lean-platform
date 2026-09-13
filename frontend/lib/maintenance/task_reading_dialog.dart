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
import 'work_order.dart';
import 'work_order_detail_bloc.dart';

class TaskReadingDialog extends StatefulWidget {
  const TaskReadingDialog({super.key, required this.task});

  final WorkOrderTask task;

  static const ValueKey<String> readingKey = ValueKey<String>('task-reading-reading');
  static const ValueKey<String> noteKey = ValueKey<String>('task-reading-note');
  static const ValueKey<String> submitKey = ValueKey<String>('task-reading-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('task-reading-cancel');
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
    final theme = Theme.of(context);
    final task = widget.task;
    return BlocListener<WorkOrderDetailBloc, WorkOrderDetailState>(
      listener: _onStateChanged,
      child: AlertDialog(
        title: Text('Record a reading on ${task.meterName ?? task.meterCode ?? 'the meter'}'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(task.instruction, style: theme.textTheme.bodyMedium),
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
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            key: TaskReadingDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: TaskReadingDialog.submitKey,
            onPressed: _readingValue != null && !_awaiting ? _submit : null,
            child: Text(_awaiting ? 'Saving…' : 'Record reading'),
          ),
        ],
      ),
    );
  }
}
