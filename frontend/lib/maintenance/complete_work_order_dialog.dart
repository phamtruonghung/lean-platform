/// Completing a Work order (issue #63): captures what was found, then hands
/// the decision to the `WorkOrdersBloc` via [WorkOrderCompletePressed], which
/// records when the work ended and moves the row to completed. The dialog
/// decides; the Bloc only ever sees a decision already made.
///
/// The note is optional — a job may end with nothing particular to say — so
/// the dialog's Complete button is enabled even with an empty field. The
/// field is a convenience for the person closing the job, not a gate.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import 'work_orders_bloc.dart';

class CompleteWorkOrderDialog extends StatelessWidget {
  const CompleteWorkOrderDialog({super.key, required this.workOrderId});

  /// The Work order being completed. Whatever note is given is sent to the
  /// server for exactly this Work order; the returned (completed) row leaves
  /// the open list.
  final String workOrderId;

  static const ValueKey<String> noteKey = ValueKey<String>('complete-dialog-note');
  static const ValueKey<String> cancelKey = ValueKey<String>('complete-dialog-cancel');
  static const ValueKey<String> confirmKey = ValueKey<String>('complete-dialog-confirm');

  /// Opens the dialog over the list. `showDialog` builds its route under the
  /// Navigator, which is not a descendant of the route-scoped
  /// `BlocProvider<WorkOrdersBloc>` the list lives in — so the Bloc is handed
  /// across explicitly, the same shape `AssignWorkOrderDialog.open` uses.
  static Future<void> open(BuildContext context, {required String workOrderId}) {
    final bloc = context.read<WorkOrdersBloc>();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => BlocProvider<WorkOrdersBloc>.value(
        value: bloc,
        child: CompleteWorkOrderDialog(workOrderId: workOrderId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = TextEditingController();
    return AlertDialog(
      title: const Text('Complete this Work order'),
      content: SizedBox(
        width: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Records when the work ended and the Work order as complete. '
              'Optional note saying what you found — the field is not required.',
              style:
                  theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: Spacing.md),
            TextField(
              key: CompleteWorkOrderDialog.noteKey,
              controller: controller,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'What was found (optional)',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: CompleteWorkOrderDialog.cancelKey,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: CompleteWorkOrderDialog.confirmKey,
          onPressed: () {
            final note = controller.text.trim();
            context.read<WorkOrdersBloc>().add(
                  WorkOrderCompletePressed(workOrderId, completionNote: note.isEmpty ? null : note),
                );
          },
          child: const Text('Complete'),
        ),
      ],
    );
  }
}