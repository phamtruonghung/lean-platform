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
library;

/// One wire value and the words a person reads it as.
class HandoverChoice {
  const HandoverChoice(this.wire, this.label);

  final String wire;
  final String label;
}

String _labelIn(List<HandoverChoice> choices, String? wire) {
  if (wire == null) return '—';
  for (final choice in choices) {
    if (choice.wire == wire) return choice.label;
  }
  return wire;
}

abstract final class HandoverVocabulary {
  /// The eight states a machine is left in. The first two are normal running:
  /// any other state owes a note saying why (`NORMAL_RUNNING_STATES`).
  static const List<HandoverChoice> machineStates = [
    HandoverChoice('running', 'Running'),
    HandoverChoice('running_manual', 'Running (manual)'),
    HandoverChoice('idle', 'Idle'),
    HandoverChoice('down', 'Down'),
    HandoverChoice('maintenance', 'Maintenance'),
    HandoverChoice('cleaning', 'Cleaning'),
    HandoverChoice('changeover', 'Changeover'),
    HandoverChoice('isolated', 'Isolated'),
  ];

  static const List<String> normalRunningStates = ['running', 'running_manual'];

  /// TPM's seven abnormality types (docs/research/shift-handover.md §2).
  static const List<HandoverChoice> abnormalityTypes = [
    HandoverChoice('minor_flaw', 'Minor flaw'),
    HandoverChoice('unfulfilled_basic_condition', 'Unfulfilled basic condition'),
    HandoverChoice('inaccessible_place', 'Inaccessible place'),
    HandoverChoice('contamination_source', 'Contamination source'),
    HandoverChoice('quality_defect_source', 'Quality defect source'),
    HandoverChoice('unnecessary_item', 'Unnecessary item'),
    HandoverChoice('unsafe_place', 'Unsafe place'),
  ];

  /// The four dimensions a Change point is recorded under (the 4M).
  static const List<HandoverChoice> changePointDimensions = [
    HandoverChoice('man', 'Man'),
    HandoverChoice('machine', 'Machine'),
    HandoverChoice('material', 'Material'),
    HandoverChoice('method', 'Method'),
  ];

  /// What a handover does with each of the Section's open Actions.
  static const List<HandoverChoice> dispositions = [
    HandoverChoice('carried', 'Carried'),
    HandoverChoice('reassigned', 'Reassigned'),
    HandoverChoice('closed', 'Closed'),
  ];

  /// What the incoming shift found when it ran a Change point's watch.
  static const List<HandoverChoice> watchResults = [
    HandoverChoice('ok', 'OK'),
    HandoverChoice('concern', 'Concern'),
    HandoverChoice('not_run', 'Not run'),
  ];

  /// Why a handover did not go the standard way.
  static const List<HandoverChoice> deviationReasons = [
    HandoverChoice('none', 'None'),
    HandoverChoice('late', 'Late'),
    HandoverChoice('partial', 'Partial'),
    HandoverChoice('no_incoming_team_leader', 'No incoming Team Leader'),
  ];

  /// A shift boundary's exceptions on the Section's day, in the server's
  /// fixed order (`toExceptions`).
  static const List<HandoverChoice> exceptions = [
    HandoverChoice('no_handover', 'No handover recorded'),
    HandoverChoice('unacknowledged', 'Unacknowledged'),
    HandoverChoice('amended_after_acknowledgement', 'Amended after acknowledgement'),
  ];

  static String machineStateLabel(String? wire) => _labelIn(machineStates, wire);
  static String abnormalityTypeLabel(String? wire) => _labelIn(abnormalityTypes, wire);
  static String dimensionLabel(String? wire) => _labelIn(changePointDimensions, wire);
  static String dispositionLabel(String? wire) => _labelIn(dispositions, wire);
  static String watchResultLabel(String? wire) => _labelIn(watchResults, wire);
  static String deviationReasonLabel(String? wire) => _labelIn(deviationReasons, wire);
  static String exceptionLabel(String? wire) => _labelIn(exceptions, wire);
}
