/// The Quality Module's entry point — the client equivalent of
/// `modules/quality/index.js`. Another Module imports this file and nothing
/// else under `lib/quality/` (ADR-0012; `tool/check_module_seams.dart`
/// enforces it). It exports only what another Module actually consumes: the
/// Floor's raise-a-Nonconformance flow.
library;

export 'floor_nonconformance_bloc.dart'
    show
        FloorNonconformanceBloc,
        FloorNonconformanceEvent,
        FloorNonconformanceStarted,
        FloorNonconformanceSubmitted,
        FloorNonconformanceState,
        FloorNonconformanceLoading,
        FloorNonconformanceReady,
        FloorNonconformanceUnavailable;
export 'floor_nonconformance_dialog.dart' show FloorNonconformanceDialog;
export 'quality_api.dart' show QualityApi, QualityApiException;
