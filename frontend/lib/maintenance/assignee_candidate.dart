/// A candidate for assignment to a Work order, as `GET
/// /api/maintenance/work-orders/:id/candidates` sends it (issue #62): an
/// active Employee at the Work order's Site, each carrying what they currently
/// hold.
///
/// The server sends a flat list of candidates, each with a `qualifications`
/// array (note the backend's own `groupCandidateRows`). A qualification with
/// `isLapsed` shows the distinction issue #11 built — "never trained" (an
/// empty list) and "needs revalidating" (a lapsed entry) are different
/// answers, and this model keeps them apart the way the backend does.
library;

import 'package:flutter/foundation.dart';

@immutable
class AssigneeCandidate {
  const AssigneeCandidate({
    required this.id,
    required this.employeeNo,
    required this.firstName,
    required this.lastName,
    required this.displayName,
    required this.qualifications,
  });

  final String id;
  final String employeeNo;
  final String firstName;
  final String lastName;

  /// What the picker shows for who this person is. The backend sends it
  /// separately from first/last because a call `displayName` could be a
  /// formatted one the plant prefers, and the caller should show it as-is.
  final String displayName;

  final List<Qualification> qualifications;
}

@immutable
class Qualification {
  const Qualification({
    required this.skillId,
    required this.skillCode,
    required this.skillName,
    required this.proficiencyLevel,
    required this.assessedOn,
    required this.expiresOn,
    required this.isLapsed,
  });

  final String skillId;
  final String skillCode;
  final String skillName;
  final int proficiencyLevel;

  /// The date the qualification was assessed, as a `YYYY-MM-DD` string, or
  /// null when the backend sent no date for it.
  final String? assessedOn;

  /// The date the qualification expires, as a `YYYY-MM-DD` string, or null
  /// when it does not expire.
  final String? expiresOn;

  /// Whether this qualification has already lapsed (its `expiresOn` is in
  /// the past). Shown as lapsed rather than dropped — the whole distinction
  /// issue #62 asks the picker to preserve.
  final bool isLapsed;
}