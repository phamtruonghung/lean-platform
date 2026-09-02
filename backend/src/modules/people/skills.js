/*
 * The skills matrix (issue #11, CONTEXT.md's Employee definition and the
 * migration's own "the skills matrix" header — see
 * migrations/1756000000000_baseline.js lines ~1417-1546). Three tables are in
 * play, and this file draws the same line plant.js/job-roles.js already draw
 * between a shared catalogue and the records that reference it:
 *
 *   - `skills` is the catalogue itself — mirrors job_roles.js almost exactly:
 *     a baseline table with no `site_id` column at all, so "skills shared by
 *     every Site" is true by construction, the same way job_roles.js's own
 *     header explains for job roles. Deactivation, never deletion — the same
 *     reasoning job-roles.js gives (`skill_requirements.skill_id` and
 *     `employee_skills.skill_id` may still reference a retired skill).
 *   - `employee_skills` is the write surface this file owns for "an Employee
 *     holds a skill at a given proficiency, as of an assessment date, until
 *     an expiry". `directory.js`'s own header already says as much: "Issue
 *     #11 (skills) owns the write surface for `employee_skills`; this file
 *     only ever reads it." recordEmployeeSkill below is that write surface.
 *   - `skill_requirements` (what an Org Unit needs) is never written here —
 *     nothing in this issue creates or edits a requirement row, only reads
 *     the coverage the baseline's own `v_skill_coverage` view already
 *     computes from it (getSiteSkillCoverage below).
 *
 * Like plant.js and job-roles.js, this file stays unaware of who is calling
 * or why — no role check, no Org Unit scope, nothing about HTTP.
 * skill-routes.js owns every authorization decision, including the one
 * ADR-0010's own Consequences section pre-decided for this issue:
 * `employee_skills` writes are administrator-only (`requireAdmin`), not
 * Org-Unit-scoped the way `POST /employees/:id/assignments` is — a skill
 * names an Employee and a competency, not an Org Unit, so ADR-0009's original
 * "an Employee record is not owned by an Org Unit" reasoning holds here
 * unchanged. See that ADR rather than re-litigating the question here.
 *
 * recordEmployeeSkill's own trigger subtlety: `employee_skills_set_expiry` is
 * `BEFORE INSERT OR UPDATE OF assessed_on, skill_id` — it only fires when
 * `assessed_on` (or `skill_id`) is actually part of the statement's own SET
 * list, not on any UPDATE whatsoever. The `ON CONFLICT ... DO UPDATE` below
 * always includes `assessed_on` in its SET clause (falling back to
 * CURRENT_DATE when the caller did not supply one, matching the column's own
 * DB default) specifically so a re-assessment always re-triggers the
 * auto-expiry derivation from the skill's `revalidation_months` when the
 * caller omits `expiresOn` — see that function's own comment for the detail.
 */

const { getPool, withActor } = require('../../platform/db');
const { httpError, notFound, parseId } = require('./errors');
const { getOrgUnit, getSite } = require('./plant');
const { getEmployee } = require('./directory');

function requireNonEmptyString(field, value) {
  if (typeof value !== 'string' || value.trim() === '') {
    throw httpError(400, `${field} is required`);
  }
}

function requireBoolean(field, value) {
  if (typeof value !== 'boolean') {
    throw httpError(400, `${field} must be a boolean`);
  }
}

// Postgres DATE comes back as a JS Date parsed at local midnight — see
// directory.js's own toDateString for the full reasoning this duplicates
// rather than imports, following the same small-helper-per-file idiom
// requireNonEmptyString already follows across this Module (plant.js,
// job-roles.js, directory.js each carry their own copy).
function toDateString(value) {
  if (value == null) return null;
  if (!(value instanceof Date)) return String(value);
  const y = value.getFullYear();
  const m = String(value.getMonth() + 1).padStart(2, '0');
  const d = String(value.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

// A calendar date, not just a string shaped like one — mirrors directory.js's
// own requireDateString exactly, including the UTC round-trip that catches a
// day/month Date would otherwise silently roll over (2024-02-30 -> March 1st).
function requireDateString(field, value) {
  if (typeof value !== 'string' || !DATE_RE.test(value)) {
    throw httpError(400, `${field} must be a YYYY-MM-DD date`);
  }
  const [year, month, day] = value.split('-').map(Number);
  const parsed = new Date(Date.UTC(year, month - 1, day));
  if (parsed.getUTCFullYear() !== year || parsed.getUTCMonth() !== month - 1 || parsed.getUTCDate() !== day) {
    throw httpError(400, `${field} must be a valid calendar date`);
  }
}

// ---------------------------------------------------------------------------
// The skill catalogue
// ---------------------------------------------------------------------------

// Mirrors the CHECK constraint on skills.skill_category in the baseline.
const SKILL_CATEGORIES = ['operation', 'quality', 'safety', 'maintenance', 'logistics', 'leadership'];

const SKILL_COLUMNS =
  'id, code, name, skill_category, org_unit_id, requires_certification, ' +
  'revalidation_months, is_active, created_at, updated_at';

function toSkill(row) {
  return {
    id: row.id,
    code: row.code,
    name: row.name,
    skillCategory: row.skill_category,
    orgUnitId: row.org_unit_id,
    requiresCertification: row.requires_certification,
    revalidationMonths: row.revalidation_months,
    isActive: row.is_active,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

function validateSkillCategory(value) {
  if (!SKILL_CATEGORIES.includes(value)) {
    throw httpError(400, `skillCategory must be one of: ${SKILL_CATEGORIES.join(', ')}`);
  }
  return value;
}

function validateRevalidationMonths(value) {
  if (value === undefined || value === null) return null;
  if (!Number.isInteger(value) || value <= 0) {
    throw httpError(400, 'revalidationMonths must be a positive integer');
  }
  return value;
}

// orgUnitId is a narrower per-plant-area scoping HINT on an otherwise-shared
// skill, not a mechanism that reintroduces Site-scoping to the catalogue
// itself — `skills` has no `site_id` column at all, exactly like `job_roles`,
// so the catalogue's shared-ness is structural regardless of whether any
// given row sets this. NULL (undefined/null here) means site-wide/shared,
// the normal case. Resolved the same way directory.js's createAssignment
// resolves orgUnitId: parseId, then plant.getOrgUnit (404 if it names
// nothing).
async function resolveOptionalOrgUnitId(orgUnitId) {
  if (orgUnitId === undefined || orgUnitId === null) return null;
  const parsedOrgUnitId = parseId(orgUnitId);
  if (parsedOrgUnitId === null) {
    throw httpError(400, 'orgUnitId must be a valid Org Unit id');
  }
  await getOrgUnit(parsedOrgUnitId); // 404s if it does not exist.
  return parsedOrgUnitId;
}

// A write against `skills` can fail for one reason this file turns into a
// clean 4xx rather than a 500: the `code` UNIQUE constraint, named
// `skills_code_key` (confirmed against the actual error Postgres raises for
// an inline `UNIQUE` column constraint, not assumed — the same check
// job-roles.js's own mapJobRoleWriteError documents for job_roles_code_key).
// Anything else is a genuine failure and is rethrown as-is.
function mapSkillWriteError(error) {
  if (error.code === '23505' && error.constraint === 'skills_code_key') {
    return httpError(409, 'a skill with this code already exists');
  }
  return error;
}

// Active skills by default, ordered by name — includeInactive widens to
// every skill. skillCategory narrows by AND, same combining rule as
// listEmployees's own filters. Open read: any approved Account needs this to
// browse the catalogue, the same reasoning job-roles.js's listJobRoles gives
// for its own catalogue (shared reference data other reads filter by).
async function listSkills({ includeInactive, skillCategory } = {}) {
  const conditions = [];
  const params = [];

  if (!includeInactive) {
    conditions.push('is_active = TRUE');
  }
  if (skillCategory) {
    params.push(skillCategory);
    conditions.push(`skill_category = $${params.length}`);
  }

  const whereClause = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';
  const { rows } = await getPool().query(
    `SELECT ${SKILL_COLUMNS} FROM skills ${whereClause} ORDER BY name`,
    params
  );
  return rows.map(toSkill);
}

// Mirrors plant.getOrgUnit/job-roles.getJobRole exactly: null id and "no such
// row" are both a 404, one query.
async function getSkill(id) {
  if (id === null) throw notFound('Skill');
  const { rows } = await getPool().query(
    `SELECT ${SKILL_COLUMNS} FROM skills WHERE id = $1`,
    [id]
  );
  if (!rows[0]) throw notFound('Skill');
  return toSkill(rows[0]);
}

async function createSkill(input, accountId) {
  const { code, name, skillCategory, orgUnitId, requiresCertification, revalidationMonths } = input ?? {};

  requireNonEmptyString('code', code);
  requireNonEmptyString('name', name);

  const skillCategoryValue = skillCategory === undefined ? 'operation' : validateSkillCategory(skillCategory);
  const resolvedOrgUnitId = await resolveOptionalOrgUnitId(orgUnitId);

  let requiresCertificationValue = false;
  if (requiresCertification !== undefined) {
    requireBoolean('requiresCertification', requiresCertification);
    requiresCertificationValue = requiresCertification;
  }

  const revalidationMonthsValue = validateRevalidationMonths(revalidationMonths);

  try {
    return await withActor(accountId, async (client) => {
      const { rows: [row] } = await client.query(
        `INSERT INTO skills (code, name, skill_category, org_unit_id, requires_certification, revalidation_months)
         VALUES ($1, $2, $3, $4, $5, $6)
         RETURNING ${SKILL_COLUMNS}`,
        [
          code.trim(), name.trim(), skillCategoryValue, resolvedOrgUnitId,
          requiresCertificationValue, revalidationMonthsValue
        ]
      );
      return toSkill(row);
    });
  } catch (error) {
    throw mapSkillWriteError(error);
  }
}

// input's keys, mapped to their column — every one optional and independently
// settable, following updateJobRole/updateEmployee's own hasOwnProperty
// idiom: an absent key never touches its column, so a one-field PATCH cannot
// blank the others. No DELETE — deactivation only (isActive = false),
// mirroring job-roles.js's own reasoning: `skill_requirements.skill_id` and
// `employee_skills.skill_id` may still reference a retired skill, so its
// history must stay readable.
const SKILL_WRITABLE_COLUMNS = {
  code: 'code',
  name: 'name',
  skillCategory: 'skill_category',
  orgUnitId: 'org_unit_id',
  requiresCertification: 'requires_certification',
  revalidationMonths: 'revalidation_months',
  isActive: 'is_active'
};

async function updateSkill(id, input, accountId) {
  await getSkill(id); // 404s if it does not exist.

  const body = input ?? {};
  const sets = [];
  const params = [];

  for (const [key, column] of Object.entries(SKILL_WRITABLE_COLUMNS)) {
    if (!Object.prototype.hasOwnProperty.call(body, key)) continue;
    let value = body[key];

    if (key === 'code') requireNonEmptyString('code', value);
    if (key === 'name') requireNonEmptyString('name', value);
    if (key === 'skillCategory') value = validateSkillCategory(value);
    // eslint-disable-next-line no-await-in-loop
    if (key === 'orgUnitId') value = await resolveOptionalOrgUnitId(value);
    if (key === 'requiresCertification') requireBoolean('requiresCertification', value);
    if (key === 'revalidationMonths') value = validateRevalidationMonths(value);
    if (key === 'isActive') requireBoolean('isActive', value);
    if (typeof value === 'string') value = value.trim();

    params.push(value);
    sets.push(`${column} = $${params.length}`);
  }

  if (sets.length === 0) {
    // Nothing to change — the existing row, unmodified, rather than issuing
    // an UPDATE with an empty SET list (which Postgres would reject outright).
    return getSkill(id);
  }

  params.push(id);
  try {
    return await withActor(accountId, async (client) => {
      const { rows: [row] } = await client.query(
        `UPDATE skills SET ${sets.join(', ')} WHERE id = $${params.length} RETURNING ${SKILL_COLUMNS}`,
        params
      );
      return toSkill(row);
    });
  } catch (error) {
    throw mapSkillWriteError(error);
  }
}

// ---------------------------------------------------------------------------
// An Employee holding a skill (employee_skills) — the write surface
// directory.js's own header says this file owns. ADR-0010's Consequences
// section gates this administrator-only, one layer up in skill-routes.js;
// this function stays unaware of that, same as every write in plant.js/
// directory.js.
// ---------------------------------------------------------------------------

// `employee_skills_expiry_valid` (expires_on <= assessed_on) is the one
// reason this write can fail that this file turns into a clean 400 rather
// than a 500 — 23514 is Postgres's SQLSTATE for check_violation, confirmed
// against the actual error, not assumed (same idiom as directory.js's own
// mapEmployeeWriteError for employees_dates_valid). Anything else is rethrown
// as-is.
function mapEmployeeSkillWriteError(error) {
  if (error.code === '23514' && error.constraint === 'employee_skills_expiry_valid') {
    return httpError(400, 'expiresOn must be after assessedOn');
  }
  return error;
}

function toEmployeeSkill(row, skill) {
  return {
    id: row.id,
    proficiencyLevel: row.proficiency_level,
    assessedOn: toDateString(row.assessed_on),
    assessedBy: row.assessed_by,
    expiresOn: toDateString(row.expires_on),
    evidenceRef: row.evidence_ref,
    note: row.note,
    skill: { id: skill.id, code: skill.code, name: skill.name }
  };
}

// Records (or re-assesses) an Employee holding a skill. `employee_skills` has
// `UNIQUE (employee_id, skill_id)` — one row per Employee per skill — so this
// is an idempotent upsert (`INSERT ... ON CONFLICT ... DO UPDATE`), not a
// plain INSERT: a re-assessment (new proficiency level, new assessed date,
// renewed expiry) is the normal way this row changes over time, and a second
// call for the same Employee/skill pair is the same real-world action
// (assess this Employee against this skill) whether it is the first time or
// the fifth — treating it as a 409 conflict would be wrong.
//
// The `SET assessed_on = EXCLUDED.assessed_on` below is always present in the
// UPDATE's own SET list, even when the caller did not supply `assessedOn` —
// see this file's own header for why that is load-bearing: the trigger only
// fires on an UPDATE that actually touches `assessed_on` (or `skill_id`), and
// this is what makes a re-assessment call always re-derive `expires_on` from
// the skill's `revalidation_months` when the caller leaves `expiresOn` out.
// If the caller DOES pass `expiresOn`, `EXCLUDED.expires_on` carries that
// value through and the trigger leaves a non-NULL `NEW.expires_on` alone.
async function recordEmployeeSkill(employeeId, skillId, input, accountId) {
  const employee = await getEmployee(employeeId); // 404s if it does not exist.
  const skill = await getSkill(skillId); // 404s if it does not exist.

  const { proficiencyLevel, assessedOn, expiresOn, evidenceRef, note } = input ?? {};

  if (!Number.isInteger(proficiencyLevel) || proficiencyLevel < 0 || proficiencyLevel > 4) {
    throw httpError(400, 'proficiencyLevel must be an integer between 0 and 4');
  }
  if (assessedOn !== undefined && assessedOn !== null) {
    requireDateString('assessedOn', assessedOn);
  }
  if (expiresOn !== undefined && expiresOn !== null) {
    requireDateString('expiresOn', expiresOn);
  }

  try {
    return await withActor(accountId, async (client) => {
      const { rows: [row] } = await client.query(
        `INSERT INTO employee_skills
           (employee_id, skill_id, proficiency_level, assessed_on, expires_on, evidence_ref, note)
         VALUES ($1, $2, $3, COALESCE($4::date, CURRENT_DATE), $5, $6, $7)
         ON CONFLICT (employee_id, skill_id) DO UPDATE
            SET proficiency_level = EXCLUDED.proficiency_level,
                assessed_on       = EXCLUDED.assessed_on,
                expires_on        = EXCLUDED.expires_on,
                evidence_ref      = EXCLUDED.evidence_ref,
                note              = EXCLUDED.note
         RETURNING id, proficiency_level, assessed_on, assessed_by, expires_on, evidence_ref, note`,
        [employee.id, skill.id, proficiencyLevel, assessedOn ?? null, expiresOn ?? null, evidenceRef ?? null, note ?? null]
      );
      return toEmployeeSkill(row, skill);
    });
  } catch (error) {
    throw mapEmployeeSkillWriteError(error);
  }
}

// ---------------------------------------------------------------------------
// Reads that combine skills with Employees/Org Units.
// ---------------------------------------------------------------------------

function validateMinimumLevel(value) {
  if (value === undefined || value === null) return 1;
  if (!Number.isInteger(value) || value < 1 || value > 4) {
    throw httpError(400, 'minimumLevel must be an integer between 1 and 4');
  }
  return value;
}

// Who holds a given skill, scoped to an Org Unit, excluding a lapsed
// qualification — the issue's own acceptance criterion. orgUnitId is
// REQUIRED: the criterion is explicitly "scoped to an Org Unit", so this does
// not invent an unscoped plant-wide variant nobody asked for.
//
// Reuses exactly directory.js's listEmployees orgUnitId pattern: a
// `LEFT JOIN LATERAL` resolves the Employee's current employee_assignments
// row (falling back to default_org_unit_id when there is none), then
// `resolved_ou.path <@ target.path` is the same GiST-indexed "everything
// beneath this Org Unit" test plant.getOrgUnitSubtree/listEmployees both use.
// "Not lapsed" is `expires_on IS NULL OR expires_on > CURRENT_DATE` — the
// exact predicate the baseline's own `v_skill_coverage` view uses for
// `qualified_headcount`, so this read and that view can never quietly
// disagree about what "qualified" means. Excludes Departed Employees by
// default (`e.is_active = TRUE`) — no toggle, out of scope for this issue.
async function listQualifiedEmployees(skillId, { orgUnitId, minimumLevel } = {}) {
  const skill = await getSkill(skillId); // 404s if it does not exist.

  if (orgUnitId === undefined || orgUnitId === null) {
    throw httpError(400, 'orgUnitId is required');
  }
  const parsedOrgUnitId = parseId(orgUnitId);
  if (parsedOrgUnitId === null) {
    throw httpError(400, 'orgUnitId must be a valid Org Unit id');
  }
  const targetOrgUnit = await getOrgUnit(parsedOrgUnitId); // 404s if it does not exist.

  const minimumLevelValue = validateMinimumLevel(minimumLevel);

  const { rows } = await getPool().query(
    `SELECT e.id, e.employee_no, e.display_name,
            es.proficiency_level, es.assessed_on, es.expires_on
       FROM employees e
       LEFT JOIN LATERAL (
         SELECT ea.org_unit_id
           FROM employee_assignments ea
          WHERE ea.employee_id = e.id
            AND ea.effective_from <= CURRENT_DATE
            AND (ea.effective_to IS NULL OR ea.effective_to > CURRENT_DATE)
          LIMIT 1
       ) current_assignment ON TRUE
       JOIN org_units resolved_ou
         ON resolved_ou.id = COALESCE(current_assignment.org_unit_id, e.default_org_unit_id)
       JOIN employee_skills es
         ON es.employee_id = e.id AND es.skill_id = $1
      WHERE e.is_active = TRUE
        AND resolved_ou.path <@ $2::ltree
        AND (es.expires_on IS NULL OR es.expires_on > CURRENT_DATE)
        AND es.proficiency_level >= $3
      ORDER BY e.display_name`,
    [skill.id, targetOrgUnit.path, minimumLevelValue]
  );

  return rows.map((row) => ({
    id: row.id,
    employeeNo: row.employee_no,
    displayName: row.display_name,
    proficiencyLevel: row.proficiency_level,
    assessedOn: toDateString(row.assessed_on),
    expiresOn: toDateString(row.expires_on)
  }));
}

// Thin skill coverage at a Site, for an administrator — literally the
// baseline's own `v_skill_coverage` view (org_unit_id, skill_id and every
// headcount figure it already computes from `skill_requirements`, excluding
// lapsed) filtered to `shortfall > 0`. shortfall > 0 IS "thin": this is the
// report the issue's own criterion asks for, not a separate full-coverage
// report nobody asked for. COUNT(...) comes back from Postgres as bigint —
// this pool has no bigint type parser (see db.js's own header) — so each
// headcount figure below is converted through Number(), safe here since a
// per-Org-Unit-and-skill headcount is never anywhere near
// Number.MAX_SAFE_INTEGER.
async function getSiteSkillCoverage(siteId) {
  await getSite(siteId); // 404s if it does not exist.

  const { rows } = await getPool().query(
    `SELECT vsc.org_unit_id, ou.code AS org_unit_code, ou.name AS org_unit_name,
            vsc.skill_id, vsc.skill_code, vsc.skill_name,
            vsc.minimum_level, vsc.minimum_qualified_headcount,
            vsc.qualified_headcount, vsc.expired_headcount, vsc.shortfall
       FROM v_skill_coverage vsc
       JOIN org_units ou ON ou.id = vsc.org_unit_id
      WHERE ou.site_id = $1
        AND vsc.shortfall > 0
      ORDER BY ou.code, vsc.skill_code`,
    [siteId]
  );

  return rows.map((row) => ({
    orgUnitId: row.org_unit_id,
    orgUnitCode: row.org_unit_code,
    orgUnitName: row.org_unit_name,
    skillId: row.skill_id,
    skillCode: row.skill_code,
    skillName: row.skill_name,
    minimumLevel: row.minimum_level,
    minimumQualifiedHeadcount: row.minimum_qualified_headcount,
    qualifiedHeadcount: Number(row.qualified_headcount),
    expiredHeadcount: Number(row.expired_headcount),
    shortfall: Number(row.shortfall)
  }));
}

module.exports = {
  listSkills,
  getSkill,
  createSkill,
  updateSkill,
  recordEmployeeSkill,
  listQualifiedEmployees,
  getSiteSkillCoverage
};
