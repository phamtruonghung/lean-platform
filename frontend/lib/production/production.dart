/// The Production Module's entry point — the client equivalent of
/// `modules/production/index.js`. Another Module imports this file and nothing
/// else under `lib/production/` (ADR-0012; `tool/check_module_seams.dart`
/// enforces it). No other Module consumes anything of this one yet, so it
/// exports only its API client, the same minimum `quality.dart` started from.
library;

export 'production_api.dart' show ProductionApi, ProductionApiException;
