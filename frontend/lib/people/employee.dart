/// The Employee directory's own models (issue #86, CONTEXT.md's Employee and
/// Directory entries): one row of the list, and one Employee's full record.
///
/// Two different shapes on purpose, matching the two different things the
/// wire actually sends. `GET /api/people/employees` (`listEmployees`,
/// `backend/src/modules/people/directory.js`) answers a flat row naming the
/// Employee's current Org Unit and current job role (issue #91) — see
/// [Employee]'s own header. `GET /api/people/employees/:id` and
/// `GET /api/people/employees/me` (`getEmployeeDetail`) answer the richer
/// [EmployeeDetail]: the current job role, the whole Assignment history, and
/// the skills held.
library;

import 'package:flutter/foundation.dart';

import 'assignee_candidate.dart' show HeldSkill;

/// One row of the Directory list.
///
/// Carries the current Org Unit's and current job role's name (issue #91),
/// resolved server-side by `listEmployees` (directory.js) in the same one
/// query the list was always built from — never a query per Employee, and
/// never a second lookup against [EmployeeDetail] just to show either on the
/// list itself (AC5's own "name, job role, Org Unit" criterion).
@immutable
class Employee {
  const Employee({
    required this.id,
    required this.employeeNo,
    required this.displayName,
    required this.employmentType,
    required this.isActive,
    required this.orgUnitName,
    required this.jobRoleName,
  });

  final String id;
  final String employeeNo;
  final String displayName;
  final String employmentType;

  /// False for a Departed Employee (CONTEXT.md's own Departed entry) — a
  /// flag, never a deletion, and included in the list only when
  /// `includeDeparted=true` was sent.
  final bool isActive;

  /// The current Org Unit's name, or null when there is nothing to resolve —
  /// no current Assignment and no `defaultOrgUnitId` either (directory.js's
  /// own fallback rule).
  final String? orgUnitName;

  /// The current job role's name, or null when there is no current
  /// Assignment at all — a job role exists nowhere but on an Assignment, so
  /// it has no fallback the way the Org Unit does.
  final String? jobRoleName;
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

/// One Employee's full record — the Directory's detail view (AC5), plus the
/// administrator's own write surface over it (issue #87).
///
/// [firstName], [lastName], [hiredOn], [employmentType] and [workEmail] are
/// carried alongside the fields issue #86 already read, because
/// `getEmployeeDetail` (directory.js) answers `{ ...toEmployee(row), jobRole,
/// assignments, skills }` — the whole of `toEmployee`'s own shape was always
/// on the wire, this model simply did not read the rest of it until there was
/// a correction form that needed to pre-fill from it.
@immutable
class EmployeeDetail {
  const EmployeeDetail({
    required this.id,
    required this.employeeNo,
    required this.firstName,
    required this.lastName,
    required this.displayName,
    required this.isActive,
    required this.hiredOn,
    required this.terminatedOn,
    required this.employmentType,
    required this.workEmail,
    required this.jobRoleName,
    required this.assignments,
    required this.qualifications,
  });

  final String id;
  final String employeeNo;
  final String firstName;
  final String lastName;
  final String displayName;
  final bool isActive;

  /// `YYYY-MM-DD`, or null — the same wire shape [EmployeeAssignment.effectiveFrom]
  /// uses and the same reason: a DATE column has no time component, so this is
  /// never parsed into a `DateTime`.
  final String? hiredOn;

  /// Set only for a Departed Employee (CONTEXT.md's own Departed entry) — a
  /// flag and a date, never a deletion.
  final String? terminatedOn;

  final String employmentType;
  final String? workEmail;

  /// The current Assignment's job role, or null when there is none — the same
  /// rule `getEmployeeDetail` computes server-side, not re-derived here.
  final String? jobRoleName;

  /// Newest first, exactly as the wire sends it.
  final List<EmployeeAssignment> assignments;

  /// The skills this Employee holds, [HeldSkill] reused from
  /// `assignee_candidate.dart` rather than a second model of the same shape
  /// (proficiency, expiry, lapsed) — see `PeopleApi`'s own note on
  /// `isLapsed` being read straight off the wire (issue #91), never
  /// re-derived here.
  final List<HeldSkill> qualifications;
}
