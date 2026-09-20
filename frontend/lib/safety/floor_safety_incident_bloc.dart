/// Reporting a Safety incident at a shared floor device (issue #227,
/// ADR-0016, ADR-0036) — the state behind the second flow the floor surface
/// offers that is not about work orders, beside [FloorNonconformanceBloc].
///
/// Like [FloorNonconformanceBloc] this Bloc is driven by [FloorDeviceGateway]
/// and holds no `AccountBloc` anywhere: a device is not a person and the
/// surface has to work where nobody can sign in. It also takes [SafetyApi],
/// because the record being written is Safety's — the client mirrors the
/// Module seam (ADR-0012), and `POST /api/safety/floor/incidents` is Safety's
/// own address.
///
/// Unlike [FloorNonconformanceBloc] there is no catalogue to read before the
/// form can render: an incident type and a severity level are fixed enums
/// already known client-side ([IncidentType], [SeverityLevel]), not
/// admin-maintained reference data. So this Bloc starts directly in
/// [FloorSafetyIncidentReady] (or [FloorSafetyIncidentUnavailable] if the
/// device has no credential at construction) rather than dispatching a
/// `Started` event to fetch anything first.
///
/// The individual identification is deliberately absent from every state
/// object, exactly as [FloorNonconformanceBloc] keeps it: the employee number
/// and PIN arrive on the submit event, the handler exchanges them for a token
/// in a local variable, uses that token for the one request, and drops it. A
/// Screen that keeps the last person's identification is the drift ADR-0016
/// exists to prevent.
///
/// The identification exchange itself is Maintenance's
/// (`POST /api/maintenance/floor/identify`, the frozen floor address issue
/// #201 kept where deployed devices were pointed), reached through
/// [MaintenanceApi] — this Bloc asks that client for the token and Safety's
/// for the record, one HAT per Module rather than a second copy of the
/// identify call under a Safety name.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../maintenance/maintenance_api.dart';
import '../platform/floor_device_gateway.dart';
import 'safety_api.dart';

sealed class FloorSafetyIncidentEvent {
  const FloorSafetyIncidentEvent();
}

/// The operator has chosen what happened and confirmed who they are. The PIN
/// is used for this one action and never stored.
class FloorSafetyIncidentSubmitted extends FloorSafetyIncidentEvent {
  const FloorSafetyIncidentSubmitted({
    required this.incidentType,
    required this.severityLevel,
    required this.description,
    required this.occurredAt,
    required this.employeeNo,
    required this.pin,
    this.immediateAction,
  });

  final String incidentType;
  final String severityLevel;
  final String description;

  /// When it occurred, already resolved by the dialog (default: now) — the
  /// same "occurred-time defaulting to now" field the desktop form's own
  /// `AppDateTimeField` offers, ADR-0017's own filing moment.
  final String occurredAt;

  final String employeeNo;
  final String pin;
  final String? immediateAction;
}

sealed class FloorSafetyIncidentState {
  const FloorSafetyIncidentState();
}

class FloorSafetyIncidentReady extends FloorSafetyIncidentState {
  const FloorSafetyIncidentReady({
    this.isSubmitting = false,
    this.failure,
    this.notice,
  });

  /// A submit is in flight; the form's controls are disabled while it settles.
  final bool isSubmitting;

  /// Why the last submit did not land, for the dialog to report.
  final String? failure;

  /// What a landed record has to say for itself — the number the Platform
  /// issued it. The dialog closes on this and the floor Screen shows it.
  final String? notice;

  FloorSafetyIncidentReady copyWith({
    bool? isSubmitting,
    String? failure,
    String? notice,
  }) =>
      FloorSafetyIncidentReady(
        isSubmitting: isSubmitting ?? this.isSubmitting,
        // Cleared on every emit that does not set them, deliberately: a stale
        // refusal from a previous attempt must not linger onto a later one.
        failure: failure,
        notice: notice,
      );
}

class FloorSafetyIncidentUnavailable extends FloorSafetyIncidentState {
  const FloorSafetyIncidentUnavailable({required this.message});
  final String message;
}

class FloorSafetyIncidentBloc
    extends Bloc<FloorSafetyIncidentEvent, FloorSafetyIncidentState> {
  FloorSafetyIncidentBloc({
    required SafetyApi safetyApi,
    required MaintenanceApi maintenanceApi,
    required FloorDeviceGateway floorDeviceGateway,
    required this.orgUnitId,
  })  : _safety = safetyApi,
        _maintenance = maintenanceApi,
        _device = floorDeviceGateway,
        super(
          floorDeviceGateway.deviceCredential == null
              ? const FloorSafetyIncidentUnavailable(message: notRegisteredMessage)
              : const FloorSafetyIncidentReady(),
        ) {
    on<FloorSafetyIncidentSubmitted>(_onSubmitted);
  }

  final SafetyApi _safety;
  final MaintenanceApi _maintenance;
  final FloorDeviceGateway _device;

  /// The Org Unit the device is registered at — where the record is filed by
  /// default, and the top of everything the device may file one against. It
  /// comes from the floor read's own context rather than from the operator, so
  /// a device can never be talked into recording somewhere else.
  final String orgUnitId;

  static const String notRegisteredMessage =
      'This device is not registered. Ask an administrator to register it against an Org Unit.';

  Future<void> _onSubmitted(
    FloorSafetyIncidentSubmitted event,
    Emitter<FloorSafetyIncidentState> emit,
  ) async {
    final current = state;
    if (current is! FloorSafetyIncidentReady || current.isSubmitting) return;

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
      final incident = await _safety.recordFloorSafetyIncident(
        credential,
        identification.token,
        orgUnitId: orgUnitId,
        incidentType: event.incidentType,
        severityLevel: event.severityLevel,
        description: event.description,
        occurredAt: event.occurredAt,
        immediateAction: event.immediateAction,
      );
      final settled = state;
      if (settled is! FloorSafetyIncidentReady) return;
      emit(
        settled.copyWith(
          isSubmitting: false,
          notice: '${incident.incidentNo} reported by ${identification.employeeName}.',
        ),
      );
    } on MaintenanceApiException catch (error) {
      _fail(emit, error.message);
    } on SafetyApiException catch (error) {
      _fail(emit, error.message);
    }
  }

  void _fail(Emitter<FloorSafetyIncidentState> emit, String message) {
    final settled = state;
    if (settled is! FloorSafetyIncidentReady) return;
    emit(settled.copyWith(isSubmitting: false, failure: message));
  }
}
