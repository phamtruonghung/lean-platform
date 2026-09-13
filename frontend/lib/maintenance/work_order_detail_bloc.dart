/// One Work order's own state (issue #74): its tasks, and what it has cost so
/// far (issue #75), fetched from the single-Work-order read the Site-wide list
/// deliberately leaves both off.
///
/// Route-scoped, like `WorkOrdersBloc`: one Screen's reading of the server,
/// re-read on arrival rather than restored stale. The id is handed in at
/// construction because the Screen it drives is addressed at one Work order.
///
/// Booking labour or a part lives here rather than on `WorkOrdersBloc`
/// because the cost summary it changes lives on this Screen: after a booking
/// the Work order is re-read, so the summary the caller just changed is the
/// one the server now reports. A booking that failed keeps the failure on the
/// state so the open dialog can show it and stay open.
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

/// The labour dialog has decided: this Employee worked this window on this
/// Work order. The window is the only input that decides the hours — the
/// server generates them, so none are sent.
class WorkOrderLabourBookingConfirmed extends WorkOrderDetailEvent {
  const WorkOrderLabourBookingConfirmed({
    required this.employeeId,
    required this.startedAt,
    required this.endedAt,
    required this.activity,
    this.isOvertime = false,
    this.note,
  });

  final String employeeId;
  final DateTime startedAt;
  final DateTime endedAt;
  final String activity;
  final bool isOvertime;
  final String? note;
}

/// The parts dialog has decided: this part was fitted. `sourced` decides
/// whether a store is drawn down; the stores fields are only set for a
/// `stores` booking.
class WorkOrderPartBookingConfirmed extends WorkOrderDetailEvent {
  const WorkOrderPartBookingConfirmed({
    required this.sourced,
    required this.quantity,
    this.partId,
    this.storeId,
    this.partNo,
    this.description,
    this.uomCode,
    this.unitCost,
  });

  final String sourced;
  final num quantity;
  final String? partId;
  final String? storeId;
  final String? partNo;
  final String? description;
  final String? uomCode;
  final num? unitCost;
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
    this.isBooking = false,
    this.bookingFailure,
  });

  final WorkOrder workOrder;

  /// A booking is in flight. Kept on the state, not only in the dialog, so the
  /// Screen can refuse a second one.
  final bool isBooking;

  /// Why the last booking did not land. Reported by the open dialog, which
  /// stays open so the caller can fix the input.
  final String? bookingFailure;

  WorkOrderDetailLoaded copyWith({
    WorkOrder? workOrder,
    bool? isBooking,
    String? bookingFailure,
  }) =>
      WorkOrderDetailLoaded(
        workOrder: workOrder ?? this.workOrder,
        isBooking: isBooking ?? this.isBooking,
        // Always overwritten, never carried forward — the same rule
        // StoreStockLoaded.copyWith gives receiveFailure.
        bookingFailure: bookingFailure,
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
    on<WorkOrderLabourBookingConfirmed>(_onLabourBookingConfirmed);
    on<WorkOrderPartBookingConfirmed>(_onPartBookingConfirmed);
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

  Future<void> _onLabourBookingConfirmed(
    WorkOrderLabourBookingConfirmed event,
    Emitter<WorkOrderDetailState> emit,
  ) async {
    await _book(
      emit,
      (token) => _maintenance.bookLabour(
        token,
        workOrderId,
        employeeId: event.employeeId,
        startedAt: event.startedAt,
        endedAt: event.endedAt,
        activity: event.activity,
        isOvertime: event.isOvertime,
        note: event.note,
      ),
    );
  }

  Future<void> _onPartBookingConfirmed(
    WorkOrderPartBookingConfirmed event,
    Emitter<WorkOrderDetailState> emit,
  ) async {
    await _book(
      emit,
      (token) => _maintenance.bookWorkOrderPart(
        token,
        workOrderId,
        sourced: event.sourced,
        quantity: event.quantity,
        partId: event.partId,
        storeId: event.storeId,
        partNo: event.partNo,
        description: event.description,
        uomCode: event.uomCode,
        unitCost: event.unitCost,
      ),
    );
  }

  /// The one path both bookings share: mark the booking in flight, call the
  /// API, then re-read the Work order so the cost summary reflects what the
  /// server now holds. The re-read is deliberately a second request rather
  /// than patching the response in — the cost is a server-owned aggregate, and
  /// the server is the only thing that knows all of its terms.
  Future<void> _book(
    Emitter<WorkOrderDetailState> emit,
    Future<void> Function(String token) send,
  ) async {
    final current = state;
    if (current is! WorkOrderDetailLoaded || current.isBooking) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(bookingFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isBooking: true, bookingFailure: null));
    try {
      await send(token);
      final workOrder = await _maintenance.fetchWorkOrder(token, workOrderId);
      final settled = state;
      if (settled is! WorkOrderDetailLoaded) return;
      emit(settled.copyWith(workOrder: workOrder, isBooking: false));
    } on MaintenanceApiException catch (error) {
      final settled = state;
      if (settled is! WorkOrderDetailLoaded) return;
      emit(settled.copyWith(isBooking: false, bookingFailure: error.message));
    }
  }
}
