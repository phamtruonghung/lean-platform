/// Completing a Work order: what was found, recorded as the job's own note
/// (issue #63).
///
/// This is a dialog, not a Screen and not a Destination — CONTEXT.md's own
/// Screen entry says a dialog inside a Screen is not a Screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import '../widgets/app_dialog.dart';
import 'work_order.dart';
import 'work_orders_bloc.dart';

class WorkOrderCompleteDialog extends StatefulWidget {
  const WorkOrderCompleteDialog({super.key, required this.workOrder});

  /// The Work order being completed.
  final WorkOrder workOrder;

  static const ValueKey<String> noteKey = ValueKey<String>('work-order-complete-note');

  /// The two actions' keys are the shell's own (`AppDialog.actionKey`), named
  /// for this dialog's use of them: a `ValueKey` is equal by value, so these
  /// find exactly the buttons `AppDialog` keyed (`docs/design-language.md` §11).
  static const String _submitId = 'submit';
  static const String _dismissId = 'dismiss';
  static ValueKey<String> get submitKey => AppDialog.actionKey(_submitId);
  static ValueKey<String> get dismissKey => AppDialog.actionKey(_dismissId);
  static const ValueKey<String> failureKey = ValueKey<String>('work-order-complete-failure');

  @override
  State<WorkOrderCompleteDialog> createState() => _WorkOrderCompleteDialogState();
}

class _WorkOrderCompleteDialogState extends State<WorkOrderCompleteDialog> {
  final TextEditingController _note = TextEditingController();

  bool _awaiting = false;
  String? _failure;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  bool get _complete => _note.text.trim().isNotEmpty;

  void _submit() {
    if (!_complete || _awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    context.read<WorkOrdersBloc>().add(
          WorkOrderCompleteConfirmed(workOrderId: widget.workOrder.id, note: _note.text.trim()),
        );
  }

  void _onWorkOrdersChanged(BuildContext context, WorkOrdersState state) {
    if (!_awaiting || state is! WorkOrdersLoaded || state.isTransitioning) return;
    if (state.transitionFailure != null) {
      setState(() {
        _awaiting = false;
        _failure = state.transitionFailure;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    return BlocListener<WorkOrdersBloc, WorkOrdersState>(
      listener: _onWorkOrdersChanged,
      // The decision width (420): one question and two actions. The one
      // free-text field is the answer to the question, not a form (§11).
      child: AppDialog(
        title: 'Complete this Work order',
        size: AppDialogSize.decision,
        actions: [
          AppDialogAction(
            id: WorkOrderCompleteDialog._dismissId,
            label: 'Cancel',
            kind: AppDialogActionKind.dismiss,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
          ),
          AppDialogAction(
            id: WorkOrderCompleteDialog._submitId,
            label: 'Complete',
            onPressed: _complete && !_awaiting ? _submit : null,
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: WorkOrderCompleteDialog.noteKey,
              controller: _note,
              enabled: !_awaiting,
              maxLines: 4,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'What was found?',
                border: OutlineInputBorder(),
              ),
            ),
            if (_failure != null)
              Padding(
                key: WorkOrderCompleteDialog.failureKey,
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
