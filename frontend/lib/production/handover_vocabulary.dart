/// The fixed sets a Shift handover is written in (issue #339), declared once.
///
/// Every list here is the backend's own enum, mirrored value for value from
/// `backend/src/modules/production/handovers.js` — `MACHINE_STATES`,
/// `ABNORMALITY_TYPES`, `CHANGE_POINT_DIMENSIONS`, `DISPOSITIONS`,
/// `WATCH_RESULTS` and `DEVIATION_REASONS` — and in the server's own order.
/// The client derives nothing from them: it offers them in a picker (a fixed
/// set of under a dozen is a dropdown, `docs/frontend-layout.md` §3) and sends
/// the chosen wire value back. The pickers and the widget tests both read this
/// file, so a value cannot be offered by one and expected by the other.
///
/// These are **wires only**. The words each one reads as are in
/// `l10n/vocabulary.dart` (`handoverMachineStateLabel` and its six neighbours),
/// so a Vietnamese reader gets a Vietnamese picker (ADR-0062).
library;

abstract final class HandoverVocabulary {
  /// The eight states a machine is left in. The first two are normal running:
  /// any other state owes a note saying why (`NORMAL_RUNNING_STATES`).
  static const List<String> machineStates = [
    'running',
    'running_manual',
    'idle',
    'down',
    'maintenance',
    'cleaning',
    'changeover',
    'isolated',
  ];

  static const List<String> normalRunningStates = ['running', 'running_manual'];

  /// TPM's seven abnormality types (docs/research/shift-handover.md §2).
  static const List<String> abnormalityTypes = [
    'minor_flaw',
    'unfulfilled_basic_condition',
    'inaccessible_place',
    'contamination_source',
    'quality_defect_source',
    'unnecessary_item',
    'unsafe_place',
  ];

  /// The four dimensions a Change point is recorded under (the 4M).
  static const List<String> changePointDimensions = ['man', 'machine', 'material', 'method'];

  /// What a handover does with each of the Section's open Actions.
  static const List<String> dispositions = ['carried', 'reassigned', 'closed'];

  /// What the incoming shift found when it ran a Change point's watch.
  static const List<String> watchResults = ['ok', 'concern', 'not_run'];

  /// Why a handover did not go the standard way.
  static const List<String> deviationReasons = ['none', 'late', 'partial', 'no_incoming_team_leader'];

  /// A shift boundary's exceptions on the Section's day, in the server's
  /// fixed order (`toExceptions`).
  static const List<String> exceptions = [
    'no_handover',
    'unacknowledged',
    'amended_after_acknowledgement',
  ];

  /// The wire a machine state starts at — the one a picker opens on.
  static String get defaultMachineState => machineStates.first;

  /// The wire a deviation reason starts at — the standard handover.
  static String get defaultDeviationReason => deviationReasons.first;

  /// The wire a Change point dimension starts at.
  static String get defaultDimension => changePointDimensions.first;
}
