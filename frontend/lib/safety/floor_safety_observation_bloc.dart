/// Recording a Safety observation at a shared floor device (issue #230,
/// ADR-0016) — the third flow the floor surface offers that is not about
/// work orders, beside `FloorNonconformanceBloc` and
/// `FloorSafetyIncidentBloc`.
///
/// Mirrors `FloorSafetyIncidentBloc` closely: driven by
/// [FloorDeviceGateway] and holding no `AccountBloc` anywhere, because a
/// device is not a person and the surface has to work where nobody can sign
/// in. It also takes [SafetyApi], because the record being written is
/// Safety's own — the client mirrors the Module seam (ADR-0012), and
/// `POST /api/safety/floor/observations` is Safety's own address.
///
/// There is no catalogue to read before the form can render: an observation
/// type, a category and a severity potential are fixed enums already known
/// client-side ([ObservationType], [ObservationCategory],
/// [SeverityPotential]), not admin-maintained reference data. So this Bloc
/// starts directly in [FloorSafetyObservationReady] (or
/// [FloorSafetyObservationUnavailable] if the device has no credential at
/// construction) rather than dispatching a `Started` event first.
///
/// The individual identification is deliberately absent from every state
/// object, exactly as [FloorSafetyIncidentBloc] keeps it: the employee number
/// and PIN arrive on the submit event, the handler exchanges them for a
/// token in a local variable, uses that token for the one request, and drops
/// it.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../maintenance/maintenance_api.dart';
import '../platform/floor_device_gateway.dart';
import 'safety_api.dart';

sealed class FloorSafetyObservationEvent {
  const FloorSafetyObservationEvent();
}

/// The operator has chosen what was seen and confirmed who they are. The PIN
/// is used for this one action and never stored.
class FloorSafetyObservationSubmitted extends FloorSafetyObservationEvent {
  const FloorSafetyObservationSubmitted({
    required this.observationType,
    required this.category,
    required this.severityPotential,
    required this.description,
    required this.employeeNo,
    required this.pin,
    this.isStopWork = false,
    this.actionTaken,
  });

  final String observationType;
  final String category;
  final String severityPotential;
  final String description;
  final bool isStopWork;
  final String? actionTaken;

  final String employeeNo;
  final String pin;
}

sealed class FloorSafetyObservationState {
  const FloorSafetyObservationState();
}

class FloorSafetyObservationReady extends FloorSafetyObservationState {
  const FloorSafetyObservationReady({
    this.isSubmitting = false,
    this.failure,
    this.notice,
  });

  /// A submit is in flight; the form's controls are disabled while it settles.
  final bool isSubmitting;

  /// Why the last submit did not land, for the dialog to report.
  final String? failure;

  /// What a landed record has to say for itself — who recorded it, since an
  /// observation carries no number of its own the way a Safety incident does.
  final String? notice;

  FloorSafetyObservationReady copyWith({
    bool? isSubmitting,
    String? failure,
    String? notice,
  }) =>
      FloorSafetyObservationReady(
        isSubmitting: isSubmitting ?? this.isSubmitting,
        // Cleared on every emit that does not set them, deliberately: a stale
        // refusal from a previous attempt must not linger onto a later one.
        failure: failure,
        notice: notice,
      );
}

class FloorSafetyObservationUnavailable extends FloorSafetyObservationState {
  const FloorSafetyObservationUnavailable({required this.message});
  final String message;
}

class FloorSafetyObservationBloc
    extends Bloc<FloorSafetyObservationEvent, FloorSafetyObservationState> {
  FloorSafetyObservationBloc({
    required SafetyApi safetyApi,
    required MaintenanceApi maintenanceApi,
    required FloorDeviceGateway floorDeviceGateway,
    required this.orgUnitId,
  })  : _safety = safetyApi,
        _maintenance = maintenanceApi,
        _device = floorDeviceGateway,
        super(
          floorDeviceGateway.deviceCredential == null
              ? const FloorSafetyObservationUnavailable(message: notRegisteredMessage)
              : const FloorSafetyObservationReady(),
        ) {
    on<FloorSafetyObservationSubmitted>(_onSubmitted);
  }

  final SafetyApi _safety;
  final MaintenanceApi _maintenance;
  final FloorDeviceGateway _device;

  /// The Org Unit the device is registered at — where the record is filed by
  /// default, and the top of everything the device may file one against. It
  /// comes from the floor read's own context rather than from the operator,
  /// so a device can never be talked into recording somewhere else.
  final String orgUnitId;

  static const String notRegisteredMessage =
      'This device is not registered. Ask an administrator to register it against an Org Unit.';

  Future<void> _onSubmitted(
    FloorSafetyObservationSubmitted event,
    Emitter<FloorSafetyObservationState> emit,
  ) async {
    final current = state;
    if (current is! FloorSafetyObservationReady || current.isSubmitting) return;

    final credential = _device.deviceCredential;
    if (credential == null) {
      emit(current.copyWith(failure: notRegisteredMessage));
      return;
    }

    emit(current.copyWith(isSubmitting: true));
    try {
      // Identify first, then write: the record is attributed to whoever this
      // exchange resolves to, so a wrong PIN means nothing is written at all.
      final identification = await _maintenance.identifyTechnician(
        credential,
        employeeNo: event.employeeNo,
        pin: event.pin,
      );
      await _safety.recordFloorSafetyObservation(
        credential,
        identification.token,
        orgUnitId: orgUnitId,
        observationType: event.observationType,
        category: event.category,
        severityPotential: event.severityPotential,
        description: event.description,
        isStopWork: event.isStopWork,
        actionTaken: event.actionTaken,
      );
      final settled = state;
      if (settled is! FloorSafetyObservationReady) return;
      emit(
        settled.copyWith(
          isSubmitting: false,
          notice: 'Observation recorded by ${identification.employeeName}.',
        ),
      );
    } on MaintenanceApiException catch (error) {
      _fail(emit, error.message);
    } on SafetyApiException catch (error) {
      _fail(emit, error.message);
    }
  }

  void _fail(Emitter<FloorSafetyObservationState> emit, String message) {
    final settled = state;
    if (settled is! FloorSafetyObservationReady) return;
    emit(settled.copyWith(isSubmitting: false, failure: message));
  }
}
