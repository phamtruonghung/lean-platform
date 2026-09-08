/// Completing a Work order: what was found, recorded as the job's own note
/// (issue #63).
///
/// This is a dialog, not a Screen and not a Destination — CONTEXT.md's own
/// Screen entry says a dialog inside a Screen is not a Screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import 'work_order.dart';
import 'work_orders_bloc.dart';

class WorkOrderCompleteDialog extends StatefulWidget {
  const WorkOrderCompleteDialog({super.key, required this.workOrder});

  /// The Work order being completed.
  final WorkOrder workOrder;

  static const ValueKey<String> noteKey = ValueKey<String>('work-order-complete-note');
  static const ValueKey<String> submitKey = ValueKey<String>('work-order-complete-submit');
  static const ValueKey<String> dismissKey = ValueKey<String>('work-order-complete-dismiss');
  static const ValueKey<String> failureKey = ValueKey<String>('work-order-complete-failure');

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
        child: WorkOrderCompleteDialog(workOrder: workOrder),
      ),
    );
  }

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
    final theme = Theme.of(context);
    return BlocListener<WorkOrdersBloc, WorkOrdersState>(
      listener: _onWorkOrdersChanged,
      child: AlertDialog(
        title: const Text('Complete this Work order'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
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
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            key: WorkOrderCompleteDialog.dismissKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: WorkOrderCompleteDialog.submitKey,
            onPressed: _complete && !_awaiting ? _submit : null,
            child: const Text('Complete'),
          ),
        ],
      ),
    );
  }
}
