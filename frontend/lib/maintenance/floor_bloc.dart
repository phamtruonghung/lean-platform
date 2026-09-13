/// The floor surface's state (issue #77, ADR-0016): the shared device's Open
/// work, and the two transitions a technician can record there.
///
/// It is driven by [FloorDeviceGateway] rather than by an Account session.
/// There is no access token and no `AccountBloc` anywhere in this Bloc: a
/// device is not a person, and the surface must work where nobody can sign in.
///
/// The individual identification is deliberately absent from every state
/// object. Each write event carries the Employee number and PIN it was
/// confirmed with, the handler exchanges them for a token in a local variable,
/// uses that token for the one request, and drops it — so "the last person"
/// is never something the Screen still holds. That is ADR-0016's "walking
/// away must not leave the next person acting as the last one" made structural
/// rather than a matter of Screen discipline.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../platform/floor_device_gateway.dart';
import 'floor_info.dart';
import 'maintenance_api.dart';
import 'work_order.dart';

sealed class FloorEvent {
  const FloorEvent();
}

/// Load the device's Open work, and the retry a failed load offers.
class FloorStarted extends FloorEvent {
  const FloorStarted();
}

/// A technician has confirmed who they are and wants to start a Work order.
/// [employeeNo] and [pin] are the identification; they are used for this one
/// action and never stored.
class FloorStartRequested extends FloorEvent {
  const FloorStartRequested({
    required this.workOrderId,
    required this.employeeNo,
    required this.pin,
  });

  final String workOrderId;
  final String employeeNo;
  final String pin;
}

/// A technician has confirmed who they are and wants to complete a Work order.
class FloorCompleteRequested extends FloorEvent {
  const FloorCompleteRequested({
    required this.workOrderId,
    required this.note,
    required this.employeeNo,
    required this.pin,
  });

  final String workOrderId;
  final String note;
  final String employeeNo;
  final String pin;
}

sealed class FloorState {
  const FloorState();
}

class FloorLoading extends FloorState {
  const FloorLoading();
}

class FloorLoaded extends FloorState {
  const FloorLoaded({
    required this.info,
    this.workOrders = const [],
    this.isActing = false,
    this.actionFailure,
    this.notice,
  });

  final FloorInfo info;
  final List<WorkOrder> workOrders;

  /// A start or complete is in flight. Every row's actions are disabled while
  /// it settles, the same one-flag-for-every-transition shape
  /// `WorkOrdersLoaded.isTransitioning` uses.
  final bool isActing;

  /// Why the last action did not land, for whichever identification dialog is
  /// open to report. Cleared on the next state that does not set it.
  final String? actionFailure;

  /// What the last action had to say for itself — "WO-… started by …".
  final String? notice;

  FloorLoaded copyWith({
    List<WorkOrder>? workOrders,
    bool? isActing,
    String? actionFailure,
    String? notice,
  }) =>
      FloorLoaded(
        info: info,
        workOrders: workOrders ?? this.workOrders,
        isActing: isActing ?? this.isActing,
        // Both cleared on every emit that does not set them, deliberately: a
        // stale failure from a previous action must not linger onto a later,
        // unrelated one.
        actionFailure: actionFailure,
        notice: notice,
      );
}

class FloorUnavailable extends FloorState {
  const FloorUnavailable({required this.message});
  final String message;
}

class FloorBloc extends Bloc<FloorEvent, FloorState> {
  FloorBloc({
    required MaintenanceApi maintenanceApi,
    required FloorDeviceGateway floorDeviceGateway,
  })  : _maintenance = maintenanceApi,
        _device = floorDeviceGateway,
        super(const FloorLoading()) {
    on<FloorStarted>(_onStarted);
    on<FloorStartRequested>(_onStartRequested);
    on<FloorCompleteRequested>(_onCompleteRequested);
  }

  final MaintenanceApi _maintenance;
  final FloorDeviceGateway _device;

  static const String notRegisteredMessage =
      'This device is not registered. Ask an administrator to register it against an Org Unit.';

  Future<void> _onStarted(FloorStarted event, Emitter<FloorState> emit) async {
    emit(const FloorLoading());
    final credential = _device.deviceCredential;
    if (credential == null) {
      emit(const FloorUnavailable(message: notRegisteredMessage));
      return;
    }
    try {
      final (info, workOrders) = await _maintenance.fetchFloorWorkOrders(credential);
      emit(FloorLoaded(info: info, workOrders: workOrders));
    } on MaintenanceApiException catch (error) {
      emit(FloorUnavailable(message: error.message));
    }
  }

  Future<void> _onStartRequested(
    FloorStartRequested event,
    Emitter<FloorState> emit,
  ) async {
    final current = state;
    if (current is! FloorLoaded || current.isActing) return;

    final credential = _device.deviceCredential;
    if (credential == null) {
      emit(current.copyWith(actionFailure: notRegisteredMessage));
      return;
    }

    emit(current.copyWith(isActing: true));
    try {
      final identification = await _maintenance.identifyTechnician(
        credential,
        employeeNo: event.employeeNo,
        pin: event.pin,
      );
      final workOrder = await _maintenance.startFloorWorkOrder(
        credential,
        identification.token,
        event.workOrderId,
      );
      final settled = state;
      if (settled is! FloorLoaded) return;
      emit(
        settled.copyWith(
          isActing: false,
          workOrders: _replace(settled.workOrders, workOrder),
          notice: '${workOrder.workOrderNo} started by ${identification.employeeName}.',
        ),
      );
    } on MaintenanceApiException catch (error) {
      final settled = state;
      if (settled is! FloorLoaded) return;
      emit(settled.copyWith(isActing: false, actionFailure: error.message));
    }
  }

  Future<void> _onCompleteRequested(
    FloorCompleteRequested event,
    Emitter<FloorState> emit,
  ) async {
    final current = state;
    if (current is! FloorLoaded || current.isActing) return;

    final credential = _device.deviceCredential;
    if (credential == null) {
      emit(current.copyWith(actionFailure: notRegisteredMessage));
      return;
    }

    emit(current.copyWith(isActing: true));
    try {
      final identification = await _maintenance.identifyTechnician(
        credential,
        employeeNo: event.employeeNo,
        pin: event.pin,
      );
      final workOrder = await _maintenance.completeFloorWorkOrder(
        credential,
        identification.token,
        event.workOrderId,
        note: event.note,
      );
      final settled = state;
      if (settled is! FloorLoaded) return;
      emit(
        settled.copyWith(
          isActing: false,
          // Completing takes the row out of the open list this Screen shows.
          workOrders: [
            for (final existing in settled.workOrders)
              if (existing.id != workOrder.id) existing,
          ],
          notice: '${workOrder.workOrderNo} completed by ${identification.employeeName}.',
        ),
      );
    } on MaintenanceApiException catch (error) {
      final settled = state;
      if (settled is! FloorLoaded) return;
      emit(settled.copyWith(isActing: false, actionFailure: error.message));
    }
  }

  List<WorkOrder> _replace(List<WorkOrder> workOrders, WorkOrder updated) => [
        for (final existing in workOrders)
          if (existing.id == updated.id) updated else existing,
      ];
}
