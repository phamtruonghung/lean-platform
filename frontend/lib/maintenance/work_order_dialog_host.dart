/// Resolves the Work order a dialog route was addressed at, out of the list
/// `WorkOrdersBloc` already holds (issue #104) — there is no single-Work-
/// order read endpoint, and #99 forbids adding one for this pass, so the
/// list already in memory (or the loading placeholder while that is still
/// arriving) is the only source this host has to work from.
///
/// Three outcomes besides success, each its own explained dialog rather than
/// a blank Screen or a silent redirect — a typed URL that used to be valid
/// should say why it no longer works:
///
/// - [loadingKey]: the list has not answered yet. Not the same as "not
///   found" — the row may still turn out to be there.
/// - [notFoundKey]: the list has answered and the id is not in it — the
///   Work order may have left the current Site/Org Unit filter, or the
///   history toggle currently hides it.
/// - [notAvailableKey]: the id resolved to a real row, but either the coarse
///   permission gate ([permitted]) or the row's own current status
///   ([permittedForStatus]) refuses this particular route — a caller with no
///   write Grant anywhere hitting `/work-orders/101/assign` directly, or a
///   caller hitting `/work-orders/101/complete` on a row that is no longer
///   `in_progress`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'work_order.dart';
import 'work_orders_bloc.dart';

class WorkOrderDialogHost extends StatelessWidget {
  const WorkOrderDialogHost({
    super.key,
    required this.workOrderId,
    required this.builder,
    this.permitted = true,
    this.permittedForStatus,
  });

  /// The Work order this route was addressed at.
  final String workOrderId;

  /// Builds the real dialog once [workOrderId] has resolved to a row that
  /// both guards below let through.
  final Widget Function(WorkOrder workOrder) builder;

  /// The coarse permission gate — `canAssignWorkOrder`/`canWorkWorkOrder` as
  /// already threaded into `WorkOrdersScreen` (router.dart reads the same
  /// `orgUnitScope.canWriteSomewhere` signal for the nested dialog routes).
  /// False refuses before the Work order is even resolved out of the list:
  /// a caller with no write Grant anywhere gets the same refusal regardless
  /// of which row they typed.
  final bool permitted;

  /// Given the resolved row's own current [WorkOrder.status], whether this
  /// route's transition still applies — `offersComplete` for `/complete`,
  /// `offersCancel` for `/cancel`. Null means "always", for a route with no
  /// status precondition (`/assign`, which is offered regardless of status —
  /// see `_RowActions`'s own reasoning in `work_orders_screen.dart`).
  final bool Function(String status)? permittedForStatus;

  static const ValueKey<String> loadingKey = ValueKey<String>('work-order-dialog-loading');
  static const ValueKey<String> notFoundKey = ValueKey<String>('work-order-dialog-not-found');
  static const ValueKey<String> notAvailableKey = ValueKey<String>('work-order-dialog-not-available');

  @override
  Widget build(BuildContext context) {
    if (!permitted) {
      return _refusal(
        context,
        title: 'You cannot do that here',
        message: 'You do not hold a write Grant that reaches this Work order.',
      );
    }

    final state = context.watch<WorkOrdersBloc>().state;
    if (state is! WorkOrdersLoaded || state.isLoadingWorkOrders) {
      return const AlertDialog(
        key: loadingKey,
        content: SizedBox(height: 80, child: Center(child: CircularProgressIndicator())),
      );
    }

    for (final workOrder in state.workOrders) {
      if (workOrder.id != workOrderId) continue;
      final statusGuard = permittedForStatus;
      if (statusGuard != null && !statusGuard(workOrder.status)) {
        return _refusal(
          context,
          title: 'That is no longer available',
          message: 'This Work order is now ${workOrder.statusLabel}, which no longer offers '
              'this action.',
        );
      }
      return builder(workOrder);
    }

    return AlertDialog(
      key: notFoundKey,
      title: const Text('That Work order is not in this list'),
      content: const Text(
        'It may have been completed, cancelled, or it is outside the Site or Org Unit the '
        'list is currently showing.',
      ),
      actions: [TextButton(onPressed: () => context.pop(), child: const Text('Back to the list'))],
    );
  }

  Widget _refusal(BuildContext context, {required String title, required String message}) {
    return AlertDialog(
      key: notAvailableKey,
      title: Text(title),
      content: Text(message),
      actions: [TextButton(onPressed: () => context.pop(), child: const Text('Back to the list'))],
    );
  }
}
