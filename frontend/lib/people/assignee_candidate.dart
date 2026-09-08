/// Who a Work order could be given to, and what each candidate currently
/// holds (`GET /api/people/employees/assignee-candidates`, issue #62).
///
/// People owns this model, since People owns the data (ADR-0012's client
/// mirror of ADR-0006) — Maintenance's assign dialog consumes it over this
/// Module's own entry point, `people.dart`, the same way it already consumes
/// `Site`.
library;

import 'package:flutter/foundation.dart';

/// One qualification an Employee currently holds, or once held.
///
/// [expiresOn] is the wire's `YYYY-MM-DD` string, or null when it never
/// expires. The server has already decided [isLapsed] against its own
/// `CURRENT_DATE` — nothing here re-derives it from the device clock, the
/// same discipline `WorkOrder` keeps for every other server-decided fact.
@immutable
class HeldSkill {
  const HeldSkill({
    required this.id,
    required this.skillId,
    required this.code,
    required this.name,
    required this.proficiencyLevel,
    required this.expiresOn,
    required this.isLapsed,
  });

  final String id;
  final String skillId;
  final String code;
  final String name;
  final int proficiencyLevel;
  final String? expiresOn;
  final bool isLapsed;
}

/// One Active Employee who could be given a Work order, with what they
/// currently hold. Never a Departed one — the server's own filter, not
/// re-checked here (AC8).
@immutable
class AssigneeCandidate {
  const AssigneeCandidate({
    required this.id,
    required this.employeeNo,
    required this.displayName,
    required this.skills,
  });

  final String id;
  final String employeeNo;
  final String displayName;

  /// Empty, never omitted, for a candidate who holds nothing — "never
  /// trained" is a fact worth showing (AC3).
  final List<HeldSkill> skills;
}
