/// One Work order's own state (issue #74): its tasks, fetched from the
/// single-Work-order read the Site-wide list deliberately leaves them off.
///
/// Route-scoped, like `WorkOrdersBloc`: one Screen's reading of the server,
/// re-read on arrival rather than restored stale. The id is handed in at
/// construction because the Screen it drives is addressed at one Work order.
///
/// Recording a reading against a task that names a meter (issue #79) writes
/// through the Maintenance API and then re-reads the Work order, so the task's
/// new reading and the meter's own accumulated use are both the server's
/// answer rather than a client-side splice.
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

/// The task-reading form has decided: record [reading] against the meter
/// [taskId] names (issue #79).
class WorkOrderTaskReadingConfirmed extends WorkOrderDetailEvent {
  const WorkOrderTaskReadingConfirmed({
    required this.taskId,
    required this.reading,
    this.note,
  });

  final String taskId;
  final num reading;
  final String? note;
}

sealed class WorkOrderDetailState {
  const WorkOrderDetailState();
}

class WorkOrderDetailLoading extends WorkOrderDetailState {
  const WorkOrderDetailLoading();
}

class WorkOrderDetailLoaded extends WorkOrderDetailState {
  const WorkOrderDetailLoaded({
    required this.workOrder,
    this.isRecording = false,
    this.readingFailure,
    this.notice,
  });

  final WorkOrder workOrder;

  /// A task reading is in flight — one flag, the same reasoning
  /// `PmSchedulesLoaded.isMutating` gives its own writes.
  final bool isRecording;

  /// Why the last task reading did not land. Reported by the open dialog,
  /// which stays open so the caller can fix the number.
  final String? readingFailure;

  /// What the last successful task reading had to say for itself.
  final String? notice;

  WorkOrderDetailLoaded copyWith({
    WorkOrder? workOrder,
    bool? isRecording,
    String? readingFailure,
    String? notice,
  }) =>
      WorkOrderDetailLoaded(
        workOrder: workOrder ?? this.workOrder,
        isRecording: isRecording ?? this.isRecording,
        readingFailure: readingFailure,
        notice: notice,
      );
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
    on<WorkOrderTaskReadingConfirmed>(_onTaskReadingConfirmed);
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

  Future<void> _onTaskReadingConfirmed(
    WorkOrderTaskReadingConfirmed event,
    Emitter<WorkOrderDetailState> emit,
  ) async {
    final current = state;
    if (current is! WorkOrderDetailLoaded || current.isRecording) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(readingFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isRecording: true, readingFailure: null));
    try {
      await _maintenance.recordTaskReading(
        token,
        workOrderId,
        event.taskId,
        reading: event.reading,
        note: event.note,
      );
      // Re-read rather than splice: the server owns both the task's reading
      // and the meter's accumulated use, and the detail read is the honest
      // way to show what it decided.
      final workOrder = await _maintenance.fetchWorkOrder(token, workOrderId);
      emit(WorkOrderDetailLoaded(workOrder: workOrder, notice: 'The reading has been recorded.'));
    } on MaintenanceApiException catch (error) {
      final settled = state;
      if (settled is! WorkOrderDetailLoaded) return;
      emit(settled.copyWith(isRecording: false, readingFailure: error.message));
    }
  }
}
