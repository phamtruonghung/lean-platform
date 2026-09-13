/// One Work order's own state (issue #74): its tasks, fetched from the
/// single-Work-order read the Site-wide list deliberately leaves them off.
///
/// Route-scoped, like `WorkOrdersBloc`: one Screen's reading of the server,
/// re-read on arrival rather than restored stale. The id is handed in at
/// construction because the Screen it drives is addressed at one Work order.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../platform/auth_gateway.dart';
import 'maintenance_api.dart';
import 'work_order.dart';

sealed class WorkOrderDetailEvent {
  const WorkOrderDetailEvent();
}

/// Fetch the Work order this Bloc was built for, or retry a failed read.
class WorkOrderDetailStarted extends WorkOrderDetailEvent {
  const WorkOrderDetailStarted();
}

sealed class WorkOrderDetailState {
  const WorkOrderDetailState();
}

class WorkOrderDetailLoading extends WorkOrderDetailState {
  const WorkOrderDetailLoading();
}

class WorkOrderDetailLoaded extends WorkOrderDetailState {
  const WorkOrderDetailLoaded({required this.workOrder});
  final WorkOrder workOrder;
}

class WorkOrderDetailUnavailable extends WorkOrderDetailState {
  const WorkOrderDetailUnavailable({required this.message});
  final String message;
}

class WorkOrderDetailBloc extends Bloc<WorkOrderDetailEvent, WorkOrderDetailState> {
  WorkOrderDetailBloc({
    required MaintenanceApi maintenanceApi,
    required AuthGateway authGateway,
    required this.workOrderId,
  })  : _maintenance = maintenanceApi,
        _auth = authGateway,
        super(const WorkOrderDetailLoading()) {
    on<WorkOrderDetailStarted>(_onStarted);
  }

  final MaintenanceApi _maintenance;
  final AuthGateway _auth;
  final String workOrderId;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';

  Future<void> _onStarted(WorkOrderDetailStarted event, Emitter<WorkOrderDetailState> emit) async {
    emit(const WorkOrderDetailLoading());
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const WorkOrderDetailUnavailable(message: signedOutMessage));
      return;
    }
    try {
      final workOrder = await _maintenance.fetchWorkOrder(token, workOrderId);
      emit(WorkOrderDetailLoaded(workOrder: workOrder));
    } on MaintenanceApiException catch (error) {
      emit(WorkOrderDetailUnavailable(message: error.message));
    }
  }
}
