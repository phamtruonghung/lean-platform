/// The Employee directory's own models (issue #86, CONTEXT.md's Employee and
/// Directory entries): one row of the list, and one Employee's full record.
///
/// Two different shapes on purpose, matching the two different things the
/// wire actually sends. `GET /api/people/employees` (`listEmployees`,
/// `backend/src/modules/people/directory.js`) answers a flat row with no job
/// role or Org Unit at all — see [Employee]'s own header for why the list
/// Screen cannot show either. `GET /api/people/employees/:id` and
/// `GET /api/people/employees/me` (`getEmployeeDetail`) answer the richer
/// [EmployeeDetail]: the current job role, the whole Assignment history, and
/// the skills held.
library;

import 'package:flutter/foundation.dart';

import 'assignee_candidate.dart' show HeldSkill;

/// One row of the Directory list.
///
/// Deliberately carries no job role and no Org Unit: `listEmployees`
/// (directory.js) selects only the Employee's own columns — no join, no
/// `currentAssignmentJoin` projection — so the list has nothing to show for
/// either. Both are read from [EmployeeDetail] instead, one Employee at a
/// time, on the Screen a row is reached from (AC5). Widening the list itself
/// to carry them would need a backend change, out of scope for this ticket.
@immutable
class Employee {
  const Employee({
    required this.id,
    required this.employeeNo,
    required this.displayName,
    required this.employmentType,
    required this.isActive,
  });

  final String id;
  final String employeeNo;
  final String displayName;
  final String employmentType;

  /// False for a Departed Employee (CONTEXT.md's own Departed entry) — a
  /// flag, never a deletion, and included in the list only when
  /// `includeDeparted=true` was sent.
  final bool isActive;
}

/// One entry of an Employee's Assignment history (`getAssignmentHistory`,
/// directory.js) — an Org Unit, a job role (nullable — an Assignment need not
/// carry one), and the span it held.
@immutable
class EmployeeAssignment {
  const EmployeeAssignment({
    required this.id,
    required this.effectiveFrom,
    required this.effectiveTo,
    required this.isCurrent,
    required this.orgUnitName,
    required this.jobRoleName,
  });

  final String id;

  /// `YYYY-MM-DD`, the wire's own calendar-date string (directory.js's
  /// `toDateString`) — never parsed into a `DateTime` here, the same
  /// discipline the backend keeps for exactly the reason its own header
  /// gives: a DATE column has no time component to begin with.
  final String effectiveFrom;
  final String? effectiveTo;

  /// Server-decided (directory.js's own SQL), never re-derived from the
  /// device clock — what distinguishes the current Assignment from past ones
  /// (AC5).
  final bool isCurrent;

  final String orgUnitName;
  final String? jobRoleName;
}

/// One Employee's full record — the Directory's detail view (AC5).
@immutable
class EmployeeDetail {
  const EmployeeDetail({
    required this.id,
    required this.employeeNo,
    required this.displayName,
    required this.isActive,
    required this.jobRoleName,
    required this.assignments,
    required this.qualifications,
  });

  final String id;
  final String employeeNo;
  final String displayName;
  final bool isActive;

  /// The current Assignment's job role, or null when there is none — the same
  /// rule `getEmployeeDetail` computes server-side, not re-derived here.
  final String? jobRoleName;

  /// Newest first, exactly as the wire sends it.
  final List<EmployeeAssignment> assignments;

  /// The skills this Employee holds, [HeldSkill] reused from
  /// `assignee_candidate.dart` rather than a second model of the same shape
  /// (proficiency, expiry, lapsed) — see `PeopleApi`'s own note on why
  /// `isLapsed` is derived on this client rather than read off the wire for
  /// this one endpoint.
  final List<HeldSkill> qualifications;
}
