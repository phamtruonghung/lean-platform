/// The skill catalogue (issue #89, issue #11's client half, CONTEXT.md's
/// Employee entry — "the holder of a qualification"): every skill the plant
/// recognises (`GET /api/people/skills`, `backend/src/modules/people/
/// skills.js`), laid over an administrator's own write surface for it
/// (`POST`/`PATCH /api/people/skills`, skill-routes.js).
///
/// Shared by every Site, the same way [JobRole] already is (ADR-0005's
/// reasoning applies here too — `skills` has no `site_id` column at all,
/// skills.js's own header) — fetching it needs no Site or Org Unit. A skill
/// may carry an `orgUnitId` *hint* server-side (a narrower per-plant-area
/// scoping suggestion, not a mechanism that scopes the catalogue to one
/// Site — skills.js's own header on `resolveOptionalOrgUnitId`), but this
/// model does not carry it: nothing on this client reads it, and showing it
/// would risk implying the catalogue itself is Site-scoped, which it is not.
library;

import 'package:flutter/foundation.dart';

/// Mirrors the CHECK constraint on `skills.skill_category`
/// (`skills.js`'s own `SKILL_CATEGORIES`) — read from the source, not
/// guessed, so the add/correct form's own dropdown never offers a value the
/// server would refuse.
const List<String> skillCategories = [
  'operation',
  'quality',
  'safety',
  'maintenance',
  'logistics',
  'leadership',
];

@immutable
class Skill {
  const Skill({
    required this.id,
    required this.code,
    required this.name,
    required this.skillCategory,
    this.requiresCertification = false,
    this.revalidationMonths,
    this.isActive = true,
  });

  final String id;
  final String code;
  final String name;
  final String skillCategory;
  final bool requiresCertification;

  /// A positive integer of months, or null when this skill never needs
  /// revalidating.
  final int? revalidationMonths;

  /// False for a deactivated skill (skills.js's own header: "deactivation,
  /// never deletion" — `skill_requirements.skill_id` and
  /// `employee_skills.skill_id` may still reference a retired one).
  final bool isActive;
}

/// One row of `GET /api/people/skills/:id/qualified-employees`
/// (`listQualifiedEmployees`, skills.js) — who holds a given skill, at what
/// proficiency, scoped to an Org Unit and already excluding a lapsed
/// qualification (the route's own `QUALIFICATION_IS_CURRENT_SQL` predicate),
/// so unlike [Skill.isActive]/`HeldSkill.isLapsed` there is no "lapsed" flag
/// to read here — a row simply would not be answered at all once its
/// qualification lapses.
@immutable
class QualifiedEmployee {
  const QualifiedEmployee({
    required this.id,
    required this.employeeNo,
    required this.displayName,
    required this.proficiencyLevel,
    required this.expiresOn,
  });

  final String id;
  final String employeeNo;
  final String displayName;
  final int proficiencyLevel;

  /// `YYYY-MM-DD`, or null when this qualification never expires — the same
  /// wire shape [Skill] and `HeldSkill` both keep for every other calendar
  /// date, never parsed into a `DateTime` here.
  final String? expiresOn;
}

/// One row of `GET /api/people/sites/:siteId/skill-coverage`
/// (`getSiteSkillCoverage`, skills.js) — one Org Unit's shortfall against one
/// skill's own requirement. Already filtered to `shortfall > 0` server-side
/// (skills.js's own header: "this IS the report the issue's own criterion
/// asks for"), so every row this model represents is thin by definition.
@immutable
class SkillCoverageEntry {
  const SkillCoverageEntry({
    required this.orgUnitId,
    required this.orgUnitCode,
    required this.orgUnitName,
    required this.skillId,
    required this.skillCode,
    required this.skillName,
    required this.minimumLevel,
    required this.minimumQualifiedHeadcount,
    required this.qualifiedHeadcount,
    required this.expiredHeadcount,
    required this.shortfall,
  });

  final String orgUnitId;
  final String orgUnitCode;
  final String orgUnitName;
  final String skillId;
  final String skillCode;
  final String skillName;
  final int minimumLevel;
  final int minimumQualifiedHeadcount;
  final int qualifiedHeadcount;
  final int expiredHeadcount;
  final int shortfall;
}
