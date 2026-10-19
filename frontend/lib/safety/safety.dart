/// The Safety Module's entry point — the client equivalent of
/// `modules/safety/index.js`. Another Module imports this file and nothing
/// else under `lib/safety/` (ADR-0012; `tool/check_module_seams.dart`
/// enforces it). It exports only what another Module actually consumes: the
/// Floor's report-an-Incident and record-an-Observation flows.
library;

export 'floor_safety_incident_bloc.dart'
    show
        FloorSafetyIncidentBloc,
        FloorSafetyIncidentEvent,
        FloorSafetyIncidentSubmitted,
        FloorSafetyIncidentState,
        FloorSafetyIncidentReady,
        FloorSafetyIncidentUnavailable;
export 'floor_safety_incident_dialog.dart' show FloorSafetyIncidentDialog;
export 'floor_safety_observation_bloc.dart'
    show
        FloorSafetyObservationBloc,
        FloorSafetyObservationEvent,
        FloorSafetyObservationSubmitted,
        FloorSafetyObservationState,
        FloorSafetyObservationReady,
        FloorSafetyObservationUnavailable;
export 'floor_safety_observation_dialog.dart' show FloorSafetyObservationDialog;
export 'safety_api.dart' show SafetyApi, SafetyApiException;
