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
import 'work_order.dart';
import 'work_orders_bloc.dart';

class WorkOrderCancelDialog extends StatefulWidget {
  const WorkOrderCancelDialog({super.key, required this.workOrder});

  /// The Work order being cancelled.
  final WorkOrder workOrder;

  static const ValueKey<String> reasonKey = ValueKey<String>('work-order-cancel-reason');
  static const ValueKey<String> submitKey = ValueKey<String>('work-order-cancel-submit');
  static const ValueKey<String> dismissKey = ValueKey<String>('work-order-cancel-dismiss');
  static const ValueKey<String> failureKey = ValueKey<String>('work-order-cancel-failure');

  /// Opens the dialog over the list. `showDialog` builds its route under the
  /// Navigator, which is not a descendant of the route-scoped
  /// `BlocProvider<WorkOrdersBloc>` the list lives in — so the Bloc is handed
  /// across explicitly, the same shape `WorkOrderAssignDialog.open` uses.
  static Future<void> open(BuildContext context, {required WorkOrder workOrder}) {
    final bloc = context.read<WorkOrdersBloc>();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => BlocProvider<WorkOrdersBloc>.value(
        value: bloc,
        child: WorkOrderCancelDialog(workOrder: workOrder),
      ),
    );
  }

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
    final theme = Theme.of(context);
    return BlocListener<WorkOrdersBloc, WorkOrdersState>(
      listener: _onWorkOrdersChanged,
      child: AlertDialog(
        title: const Text('Cancel this Work order?'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
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
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            key: WorkOrderCancelDialog.dismissKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Keep it open'),
          ),
          FilledButton(
            key: WorkOrderCancelDialog.submitKey,
            onPressed: _awaiting ? null : _submit,
            child: const Text('Cancel this Work order'),
          ),
        ],
      ),
    );
  }
}
