/// Cancelling a Work order raised in error (issue #63).
///
/// The dismiss button is deliberately not labelled "Cancel" — inside the
/// dialog whose confirm action *is* cancelling the Work order, "Cancel" can
/// only mean one thing, so dismissing without cancelling is labelled "Keep it
/// open" instead.
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

class WorkOrderCancelDialog extends StatefulWidget {
  const WorkOrderCancelDialog({super.key, required this.workOrder});

  /// The Work order being cancelled.
  final WorkOrder workOrder;

  static const ValueKey<String> reasonKey = ValueKey<String>('work-order-cancel-reason');

  /// The two actions' keys are the shell's own (`AppDialog.actionKey`), named
  /// for this dialog's use of them: a `ValueKey` is equal by value, so these
  /// find exactly the buttons `AppDialog` keyed (`docs/design-language.md` §11).
  static const String _submitId = 'submit';
  static const String _dismissId = 'dismiss';
  static ValueKey<String> get submitKey => AppDialog.actionKey(_submitId);
  static ValueKey<String> get dismissKey => AppDialog.actionKey(_dismissId);
  static const ValueKey<String> failureKey = ValueKey<String>('work-order-cancel-failure');

  @override
  State<WorkOrderCancelDialog> createState() => _WorkOrderCancelDialogState();
}

class _WorkOrderCancelDialogState extends State<WorkOrderCancelDialog> {
  final TextEditingController _reason = TextEditingController();

  bool _awaiting = false;
  String? _failure;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    if (_awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    final reason = _reason.text.trim();
    context.read<WorkOrdersBloc>().add(
          WorkOrderCancelConfirmed(
            workOrderId: widget.workOrder.id,
            reason: reason.isEmpty ? null : reason,
          ),
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
      // The decision width (420): a question, and a way out that keeps the Work
      // order open. Cancelling is the destructive act, so it is drawn as one and
      // separated from the dismiss; the optional reason is the answer, not a
      // form (§11).
      child: AppDialog(
        title: 'Cancel this Work order?',
        size: AppDialogSize.decision,
        actions: [
          AppDialogAction(
            id: WorkOrderCancelDialog._dismissId,
            label: 'Keep it open',
            kind: AppDialogActionKind.dismiss,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
          ),
          AppDialogAction(
            id: WorkOrderCancelDialog._submitId,
            label: 'Cancel this Work order',
            kind: AppDialogActionKind.destructive,
            onPressed: _awaiting ? null : _submit,
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: WorkOrderCancelDialog.reasonKey,
              controller: _reason,
              enabled: !_awaiting,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Why is this being cancelled? (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            if (_failure != null)
              Padding(
                key: WorkOrderCancelDialog.failureKey,
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
