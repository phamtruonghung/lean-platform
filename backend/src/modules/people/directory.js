/*
 * The Employee directory (issue #9, CONTEXT.md's Employee definition):
 * listing, searching and filtering Employees, and the detail view behind an
 * Employee's job role, Org Unit assignments and skills. `employees`,
 * `employee_assignments`, `job_roles`, `employee_skills` and `skills` are all
 * baseline tables — see migrations/1756000000000_baseline.js's own header on
 * "The People pillar" for why `employees` is the rich table and why
 * assignments are kept as history rather than as columns on it.
 *
 * Like plant.js, this file stays unaware of who is calling or why — no role
 * check, no Org Unit scope, nothing about HTTP, in every function including
 * createAssignment (issue #10) even though its own route is the one write in
 * this Module gated by Org Unit scope rather than requireAdmin (ADR-0010):
 * that gate lives entirely in directory-routes.js, one layer up, the same as
 * every other authorization decision this file stays out of. Read
 * directory-routes.js's own header, and ADR-0009, for why the read surface
 * is deliberately not gated by authorization.js the way plant-routes.js's
 * Sites and Org Units are: unlike an Org Unit or a Site, an Employee
 * reaching this file is never one the caller had to already be "entitled to
 * name" — every function here assumes only that the caller has already
 * cleared authenticate/requireActive one layer up.
 *
 * "Departed" is never a delete. It is `employees.is_active = FALSE`, with
 * `terminated_on` recording when — nothing in this Module, or any other,
 * ever removes an Employee row, since their history is what answers "who
 * worked here last March" (issue #9's own acceptance criteria; see also the
 * CONTEXT.md glossary's Departed entry).
 *
 * Issue #11 (skills) owns the write surface for `employee_skills`; this file
 * only ever reads it, for the detail view's own acceptance criterion.
 *
 * Pass 2 (issue #9, criteria 5 and 6) adds the write surface: an
 * administrator adding, editing, departing and reinstating an Employee.
 * createEmployee, updateEmployee, setEmployeeDeparted and reinstateEmployee
 * below copy plant.js's own idioms exactly — requireNonEmptyString,
 * withActor(accountId, ...) around every write so created_by/updated_by are
 * recorded, and a mapEmployeeWriteError that turns a constraint failure into
 * a clean 4xx the same way mapSiteWriteError/mapOrgUnitWriteError do — since
 * this file and that one are read by the same people and should not
 * gratuitously disagree about how a Module's write surface is shaped.
 * directory-routes.js is the one place that decides who may call these
 * (administrator only); this file still stays unaware of that, exactly as
 * the header above already says of the read surface.
 *
 * Issue #10 adds createAssignment: an Employee's placement at an Org Unit,
 * kept here rather than in a file of its own (the assignment history above
 * is already read here, and the route is nested under /employees) and
 * gated differently again — write scope on the destination Org Unit, not
 * requireAdmin (ADR-0010) — but this function stays just as unaware of that
 * as every other write in this file. job-roles.js is its own small sibling
 * module for the `job_roles` catalogue itself (list/create/update), imported
 * here only for getJobRole, the same way plant.js's getOrgUnit already is.
 */

const { getPool, withActor } = require('../../platform/db');
const { httpError, notFound, parseId } = require('./errors');
const { getOrgUnit } = require('./plant');
const { getJobRole } = require('./job-roles');

function requireNonEmptyString(field, value) {
  if (typeof value !== 'string' || value.trim() === '') {
    throw httpError(400, `${field} is required`);
  }
}

// Mirrors the CHECK constraint on employees.employment_type in the baseline.
// Validated here too so a bad value comes back as a 400 with a clear message
// instead of a raw constraint-violation error.
const EMPLOYMENT_TYPES = ['permanent', 'temporary', 'agency', 'contractor', 'apprentice'];

const EMPLOYEE_COLUMNS =
  'id, employee_no, first_name, last_name, display_name, hired_on, terminated_on, ' +
  'employment_type, default_org_unit_id, default_crew_id, cost_center_id, is_active, ' +
  'work_email, created_at, updated_at';

// Same columns, `e.`-qualified — needed only in listEmployees, whose
// orgUnitId filter joins org_units and employee_assignments, both of which
// share column names with employees (id, is_active): an unqualified
// EMPLOYEE_COLUMNS would be ambiguous the moment that join is present.
const EMPLOYEE_COLUMNS_QUALIFIED = EMPLOYEE_COLUMNS
  .split(', ')
  .map((column) => `e.${column}`)
  .join(', ');

// Postgres DATE has no time zone, but node-postgres parses it into a JS Date
// at LOCAL midnight, which JSON.stringify then renders as a UTC instant — a
// terminated_on of 2024-06-01 leaves a process running in, say, Asia/Saigon
// (+07:00) as '2024-05-31T17:00:00.000Z' over the wire. A calendar date must
// cross the wire as one, so every DATE column this file returns (hired_on,
// terminated_on, and effectiveFrom/effectiveTo on the detail view's
// assignments) goes through this instead of the row value as-is. Local
// getters, not toISOString(), because local midnight is what pg's own parser
// built the Date from in the first place.
function toDateString(value) {
  if (value == null) return null;
  if (!(value instanceof Date)) return String(value);
  const y = value.getFullYear();
  const m = String(value.getMonth() + 1).padStart(2, '0');
  const d = String(value.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

function toEmployee(row) {
  return {
    id: row.id,
    employeeNo: row.employee_no,
    firstName: row.first_name,
    lastName: row.last_name,
    displayName: row.display_name,
    hiredOn: toDateString(row.hired_on),
    terminatedOn: toDateString(row.terminated_on),
    employmentType: row.employment_type,
    defaultOrgUnitId: row.default_org_unit_id,
    defaultCrewId: row.default_crew_id,
    costCenterId: row.cost_center_id,
    isActive: row.is_active,
    workEmail: row.work_email,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

// Postgres's own LIKE/ILIKE escape rules: `\` must be escaped first, so a
// literal backslash in the search text does not turn the `%`/`_` escapes
// added after it into something else. The `ESCAPE '\'` clause below is what
// makes these three characters, and only these three, special in the pattern
// this function builds.
function escapeLikePattern(value) {
  return value.replace(/\\/g, '\\\\').replace(/%/g, '\\%').replace(/_/g, '\\_');
}

// Active Employees by default (issue #9's own default), ordered by
// display_name; includeDeparted also brings in Departed ones (is_active =
// FALSE). search, orgUnitId and jobRoleId are all optional and combine with
// the activity filter, and with each other, by AND — a caller narrowing by
// name, Org Unit or job role is never widening past "active only" by
// accident, nor does one filter loosen another.
//
// An Employee is "at" an Org Unit, and "holds" a job role, by their CURRENT
// employee_assignments row (effective_from <= today AND (effective_to IS
// NULL OR effective_to > today)) — issue #10's own current-assignment rule,
// resolved once per employee by the LEFT JOIN LATERAL below and reused by
// both filters, never a query per row. orgUnitId additionally falls back to
// employees.default_org_unit_id when there is no current assignment at all
// (issue #9's own rule); jobRoleId has no such fallback (issue #10's own
// criterion 4) — a job role exists nowhere but on an assignment, so an
// Employee with no current assignment, or whose current assignment carries
// no job role, simply does not match a jobRoleId filter.
//
// orgUnitId filters through the tree, not by exact match (issue #9's own
// criterion): the resolved org unit's `path` is tested with `path <@` against
// the filter unit's own path, the same GiST-indexed pattern plant.js's
// getOrgUnitSubtree uses for "everything beneath this Org Unit" — an Employee
// assigned to a descendant of the filtered Org Unit is included, not only one
// assigned to it exactly.
async function listEmployees({ search, orgUnitId, jobRoleId, includeDeparted } = {}) {
  const conditions = [];
  const params = [];

  if (!includeDeparted) {
    conditions.push('e.is_active = TRUE');
  }

  if (search) {
    params.push(`%${escapeLikePattern(search)}%`);
    conditions.push(`e.display_name ILIKE $${params.length} ESCAPE '\\'`);
  }

  const hasOrgUnitFilter = orgUnitId !== undefined && orgUnitId !== null;
  const hasJobRoleFilter = jobRoleId !== undefined && jobRoleId !== null;

  // The lateral resolving the current assignment is emitted whenever EITHER
  // filter is present — issue #10 widens what was, before it, an orgUnitId
  // -only join, since job_role_id is read off the exact same current-
  // assignment row org_unit_id already was.
  let currentAssignmentJoin = '';
  if (hasOrgUnitFilter || hasJobRoleFilter) {
    currentAssignmentJoin = `
      LEFT JOIN LATERAL (
        SELECT ea.org_unit_id, ea.job_role_id
          FROM employee_assignments ea
         WHERE ea.employee_id = e.id
           AND ea.effective_from <= CURRENT_DATE
           AND (ea.effective_to IS NULL OR ea.effective_to > CURRENT_DATE)
         LIMIT 1
      ) current_assignment ON TRUE`;
  }

  let orgUnitJoin = '';
  if (hasOrgUnitFilter) {
    // A tiny separate query to resolve the filter Org Unit's own path — 404s
    // if it does not exist at all, the same existence check every other Org
    // Unit id this Module accepts gets (plant.getOrgUnit).
    const target = await getOrgUnit(orgUnitId);
    params.push(target.path);
    // COALESCE falls back to default_org_unit_id when there is no current
    // assignment row at all.
    orgUnitJoin = `
      JOIN org_units resolved_ou
        ON resolved_ou.id = COALESCE(current_assignment.org_unit_id, e.default_org_unit_id)`;
    conditions.push(`resolved_ou.path <@ $${params.length}::ltree`);
  }

  if (hasJobRoleFilter) {
    await getJobRole(jobRoleId); // 404s if it does not exist at all.
    params.push(jobRoleId);
    conditions.push(`current_assignment.job_role_id = $${params.length}`);
  }

  const whereClause = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';

  const { rows } = await getPool().query(
    `SELECT ${EMPLOYEE_COLUMNS_QUALIFIED}
       FROM employees e
       ${currentAssignmentJoin}
       ${orgUnitJoin}
       ${whereClause}
      ORDER BY e.display_name`,
    params
  );
  return rows.map(toEmployee);
}

// Mirrors plant.getOrgUnit exactly: null id and "no such row" are both a 404,
// one query, no scope check (this Module's directory is deliberately not
// scoped — see the file header and ADR-0009).
async function getEmployee(id) {
  if (id === null) throw notFound('Employee');
  const { rows } = await getPool().query(
    `SELECT ${EMPLOYEE_COLUMNS} FROM employees WHERE id = $1`,
    [id]
  );
  if (!rows[0]) throw notFound('Employee');
  return toEmployee(rows[0]);
}

// The full assignment history for one Employee, newest first — the detail
// view's own query (issue #9), factored out here so issue #10's
// createAssignment can hand back the row it just inserted in the exact same
// shape, computed by the exact same rule, rather than a second,
// differently-written query that could quietly drift from this one.
// `isCurrent` is computed in SQL (the same "effective_from <= today AND
// (effective_to IS NULL OR effective_to > today)" rule listEmployees's own
// filters turn on) rather than compared against `new Date()` in JS: pg parses
// a DATE column back as a JS Date object, not a string, so a JS-side
// comparison against today's date would need to reproduce Postgres's own
// date semantics instead of just asking Postgres. One query, never a query
// per assignment.
async function getAssignmentHistory(employeeId) {
  const { rows } = await getPool().query(
    `SELECT a.id, a.effective_from, a.effective_to, a.crew_id,
            ou.id AS org_unit_id, ou.code AS org_unit_code, ou.name AS org_unit_name,
            jr.id AS job_role_id, jr.code AS job_role_code, jr.name AS job_role_name,
            (a.effective_from <= CURRENT_DATE
             AND (a.effective_to IS NULL OR a.effective_to > CURRENT_DATE)) AS is_current
       FROM employee_assignments a
       JOIN org_units ou ON ou.id = a.org_unit_id
       LEFT JOIN job_roles jr ON jr.id = a.job_role_id
      WHERE a.employee_id = $1
      ORDER BY a.effective_from DESC`,
    [employeeId]
  );

  return rows.map((row) => ({
    id: row.id,
    effectiveFrom: toDateString(row.effective_from),
    effectiveTo: toDateString(row.effective_to),
    isCurrent: row.is_current,
    crewId: row.crew_id,
    orgUnit: { id: row.org_unit_id, code: row.org_unit_code, name: row.org_unit_name },
    jobRole: row.job_role_id
      ? { id: row.job_role_id, code: row.job_role_code, name: row.job_role_name }
      : null
  }));
}

// The Employee detail view's own acceptance criterion: job role, Org Unit
// assignments and skills, alongside the Employee record itself. Three
// queries total (the Employee, the assignments, the skills) — never a query
// per assignment or per skill.
async function getEmployeeDetail(id) {
  const employee = await getEmployee(id); // throws the 404.

  const assignments = await getAssignmentHistory(id);

  // jobRole on the detail view itself is the CURRENT assignment's job role —
  // issue #10's own current-assignment rule, already computed per row above
  // (isCurrent) rather than recomputed here.
  const currentAssignment = assignments.find((assignment) => assignment.isCurrent);
  const jobRole = currentAssignment ? currentAssignment.jobRole : null;

  const { rows: skillRows } = await getPool().query(
    `SELECT es.id, es.proficiency_level, es.assessed_on, es.expires_on,
            s.id AS skill_id, s.code AS skill_code, s.name AS skill_name
       FROM employee_skills es
       JOIN skills s ON s.id = es.skill_id
      WHERE es.employee_id = $1
      ORDER BY s.name`,
    [id]
  );

  const skills = skillRows.map((row) => ({
    id: row.id,
    proficiencyLevel: row.proficiency_level,
    assessedOn: row.assessed_on,
    expiresOn: row.expires_on,
    skill: { id: row.skill_id, code: row.skill_code, name: row.skill_name }
  }));

  return { ...employee, jobRole, assignments, skills };
}

// A write against `employees` can fail for three reasons this file turns
// into a clean 4xx rather than a 500: the `employee_no` UNIQUE constraint,
// the case-insensitive `employees_work_email_key` index, and the baseline's
// own `employees_dates_valid` CHECK (a terminated_on before hired_on).
// `employee_no` and `work_email` are two different mistakes — "duplicate
// key" alone leaves the caller guessing which field to fix — so this looks
// at error.constraint (Postgres names both, `employees_employee_no_key`
// being the implicit name Postgres gives an inline `UNIQUE` column
// constraint) rather than only error.code. Anything else is a genuine
// failure and is rethrown as-is, same as mapSiteWriteError/
// mapOrgUnitWriteError.
function mapEmployeeWriteError(error) {
  if (error.code === '23505') {
    if (error.constraint === 'employees_employee_no_key') {
      return httpError(409, 'an Employee with this employee_no already exists');
    }
    if (error.constraint === 'employees_work_email_key') {
      return httpError(409, 'an Employee with this work_email already exists');
    }
    return httpError(409, 'a duplicate value conflicts with an existing Employee');
  }
  // 23514 is Postgres's SQLSTATE for check_violation — confirmed against the
  // actual error raised by employees_dates_valid, not assumed.
  if (error.code === '23514' && error.constraint === 'employees_dates_valid') {
    return httpError(400, 'terminatedOn cannot be before hiredOn');
  }
  return error;
}

// Required: employeeNo, firstName, lastName. Optional: hiredOn,
// employmentType (defaults to the baseline's own default, 'permanent'),
// defaultOrgUnitId, defaultCrewId, costCenterId, workEmail. is_active and
// terminated_on are never settable here — a brand new Employee is always
// Active, by definition (see updateEmployee's own comment for why those two
// columns have no route into this file except through
// setEmployeeDeparted/reinstateEmployee).
async function createEmployee(input, accountId) {
  const {
    employeeNo, firstName, lastName, hiredOn, employmentType,
    defaultOrgUnitId, defaultCrewId, costCenterId, workEmail
  } = input ?? {};

  requireNonEmptyString('employeeNo', employeeNo);
  requireNonEmptyString('firstName', firstName);
  requireNonEmptyString('lastName', lastName);

  const employmentTypeValue = employmentType ?? 'permanent';
  if (!EMPLOYMENT_TYPES.includes(employmentTypeValue)) {
    throw httpError(400, `employmentType must be one of: ${EMPLOYMENT_TYPES.join(', ')}`);
  }

  try {
    return await withActor(accountId, async (client) => {
      const { rows: [row] } = await client.query(
        `INSERT INTO employees (employee_no, first_name, last_name, hired_on, employment_type,
                                 default_org_unit_id, default_crew_id, cost_center_id, work_email)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
         RETURNING ${EMPLOYEE_COLUMNS}`,
        [
          employeeNo.trim(), firstName.trim(), lastName.trim(), hiredOn ?? null, employmentTypeValue,
          defaultOrgUnitId ?? null, defaultCrewId ?? null, costCenterId ?? null, workEmail ?? null
        ]
      );
      return toEmployee(row);
    });
  } catch (error) {
    throw mapEmployeeWriteError(error);
  }
}

// input's keys, mapped to their column — every one of them optional, and
// deliberately not including is_active or terminated_on: those two are owned
// by setEmployeeDeparted/reinstateEmployee, which record terminated_on
// alongside is_active in the same statement. A second path into is_active
// here, one that could flip it without also setting (or clearing)
// terminated_on, is exactly the bug issue #9 closes — so there is no key in
// this map, and no amount of body content, that can reach either column.
const EMPLOYEE_WRITABLE_COLUMNS = {
  employeeNo: 'employee_no',
  firstName: 'first_name',
  lastName: 'last_name',
  hiredOn: 'hired_on',
  employmentType: 'employment_type',
  defaultOrgUnitId: 'default_org_unit_id',
  defaultCrewId: 'default_crew_id',
  costCenterId: 'cost_center_id',
  workEmail: 'work_email'
};

// 404s first (mirrors plant.js's own update-ish paths, e.g. setOrgUnitActive)
// then builds the SET list from only the keys actually present in the body —
// `hasOwnProperty`, not `!== undefined`, so an explicit `{ workEmail: null }`
// (clearing it) is still honoured while an absent key never touches its
// column at all. This is what keeps a one-field edit from blanking every
// other field, the issue's own criterion.
async function updateEmployee(id, input, accountId) {
  await getEmployee(id); // 404s if it does not exist.

  const body = input ?? {};
  const sets = [];
  const params = [];

  for (const [key, column] of Object.entries(EMPLOYEE_WRITABLE_COLUMNS)) {
    if (!Object.prototype.hasOwnProperty.call(body, key)) continue;
    let value = body[key];

    if (key === 'employeeNo') requireNonEmptyString('employeeNo', value);
    if (key === 'firstName') requireNonEmptyString('firstName', value);
    if (key === 'lastName') requireNonEmptyString('lastName', value);
    if (key === 'employmentType' && !EMPLOYMENT_TYPES.includes(value)) {
      throw httpError(400, `employmentType must be one of: ${EMPLOYMENT_TYPES.join(', ')}`);
    }
    if (typeof value === 'string') value = value.trim();

    params.push(value);
    sets.push(`${column} = $${params.length}`);
  }

  if (sets.length === 0) {
    // Nothing to change — the existing row, unmodified, rather than issuing
    // an UPDATE with an empty SET list (which Postgres would reject outright).
    return getEmployee(id);
  }

  params.push(id);
  try {
    return await withActor(accountId, async (client) => {
      const { rows: [row] } = await client.query(
        `UPDATE employees SET ${sets.join(', ')} WHERE id = $${params.length} RETURNING ${EMPLOYEE_COLUMNS}`,
        params
      );
      return toEmployee(row);
    });
  } catch (error) {
    throw mapEmployeeWriteError(error);
  }
}

// is_active = FALSE, terminated_on = the supplied date or CURRENT_DATE — the
// two columns updateEmployee above refuses to touch, set together here so
// "Departed" never exists without a terminated_on to go with it. A
// terminatedOn before hired_on trips employees_dates_valid, surfaced as a
// clean 400 by mapEmployeeWriteError, not a 500.
async function setEmployeeDeparted(id, { terminatedOn } = {}, accountId) {
  await getEmployee(id); // 404s if it does not exist.

  try {
    return await withActor(accountId, async (client) => {
      const { rows: [row] } = await client.query(
        `UPDATE employees
            SET is_active = FALSE,
                terminated_on = COALESCE($1, CURRENT_DATE)
          WHERE id = $2
          RETURNING ${EMPLOYEE_COLUMNS}`,
        [terminatedOn ?? null, id]
      );
      return toEmployee(row);
    });
  } catch (error) {
    throw mapEmployeeWriteError(error);
  }
}

// The other half of setEmployeeDeparted: is_active back to TRUE,
// terminated_on back to NULL — an Employee cannot be Active with a
// terminated_on left over from a previous departure.
async function reinstateEmployee(id, accountId) {
  await getEmployee(id); // 404s if it does not exist.

  return withActor(accountId, async (client) => {
    const { rows: [row] } = await client.query(
      `UPDATE employees
          SET is_active = TRUE,
              terminated_on = NULL
        WHERE id = $1
        RETURNING ${EMPLOYEE_COLUMNS}`,
      [id]
    );
    return toEmployee(row);
  });
}

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

// A calendar date, not just a string shaped like one — `new Date(...)`
// silently rolls an invalid day/month over into the next one (2024-02-30
// becomes March 1st) rather than rejecting it, so this round-trips through
// UTC components and checks they survived, the same way a real calendar date
// must.
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

// A write against `employee_assignments` can fail for three reasons this
// file turns into a clean 4xx rather than a 500 — each confirmed against the
// actual error Postgres raises, not assumed:
//   - 23P01 (exclusion_violation), employee_assignments_no_overlap: the new
//     row's range overlaps one already on file for this Employee. This is
//     what a same-employee double-booking, or a backdated assignment landing
//     inside an existing range, both look like at the database.
//   - 23503 (foreign_key_violation): an unknown crewId. orgUnitId and
//     jobRoleId are both resolved through their own getters (plant.getOrgUnit,
//     job-roles.getJobRole) before the INSERT is ever attempted, so a bad
//     value for either is already a 404 by this point — crewId has no such
//     getter in this Module, so its own FK is the only one still able to
//     fire here.
// Anything else is a genuine failure and is rethrown as-is, same as
// mapEmployeeWriteError.
function mapAssignmentWriteError(error) {
  if (error.code === '23P01' && error.constraint === 'employee_assignments_no_overlap') {
    return httpError(409, 'overlaps an existing assignment for this Employee');
  }
  if (error.code === '23503') {
    return httpError(400, 'crewId does not name a real crew');
  }
  return error;
}

// Assigning an Employee to an Org Unit (issue #10, criteria 2 and 3). Lives
// here rather than in a new file — see this file's own header — because the
// route is nested under /employees and the assignment history this writes
// is the exact same history getEmployeeDetail/getAssignmentHistory already
// read. directory-routes.js is the one place that decides who may call this
// (write scope on the destination Org Unit — ADR-0010); this function stays
// unaware of that, same as every other write in this file.
//
// Transfer semantics — issue #10's own criterion 3, and what the baseline's
// `employee_assignments_no_overlap` EXCLUDE constraint forces the shape of:
// an Employee has at most one *open* assignment (effective_to IS NULL) at a
// time, so recording a transfer means closing that one before a new one can
// be opened, never editing it in place. All of the following runs inside one
// transaction (withActor), with the existing open row locked FOR UPDATE
// first so two concurrent transfers can never both read it as still open:
//
//   1. No open assignment at all: just insert the new one.
//   2. An open assignment starting before the new effectiveFrom: close it
//      (effective_to = the new row's effectiveFrom) and insert the new one.
//      The old row keeps its own id, Org Unit, job role and effective_from —
//      it only gains an effective_to. This is "leaves the previous one
//      intact".
//   3. An open assignment starting exactly on the new effectiveFrom: a
//      zero-length assignment is meaningless (and would trip
//      employee_assignments_range_valid if attempted), so this is a 409 —
//      correcting today's assignment is an edit, not a transfer.
//   4. An open assignment starting AFTER the new effectiveFrom: this is a
//      backdated assignment reaching into a range that is already spoken
//      for, not a transfer at all, so it is deliberately not closed here —
//      the INSERT below is left to fail on employee_assignments_no_overlap
//      instead (mapAssignmentWriteError's own 23P01 case), the same failure
//      a backdated assignment landing inside any other historical range
//      would get.
async function createAssignment(employeeId, input, accountId) {
  const employee = await getEmployee(employeeId); // 404s if it does not exist.
  if (!employee.isActive) {
    throw httpError(409, 'this Employee has departed and cannot be assigned');
  }

  const { orgUnitId, jobRoleId, crewId, effectiveFrom } = input ?? {};

  if (orgUnitId === undefined || orgUnitId === null) {
    throw httpError(400, 'orgUnitId is required');
  }
  const parsedOrgUnitId = parseId(orgUnitId);
  if (parsedOrgUnitId === null) {
    throw httpError(400, 'orgUnitId must be a valid Org Unit id');
  }
  const orgUnit = await getOrgUnit(parsedOrgUnitId); // 404s if it does not exist.

  let parsedJobRoleId = null;
  let jobRole = null;
  if (jobRoleId !== undefined && jobRoleId !== null) {
    parsedJobRoleId = parseId(jobRoleId);
    if (parsedJobRoleId === null) {
      throw httpError(400, 'jobRoleId must be a valid job role id');
    }
    jobRole = await getJobRole(parsedJobRoleId); // 404s if it does not exist.
  }

  let parsedCrewId = null;
  if (crewId !== undefined && crewId !== null) {
    parsedCrewId = parseId(crewId);
    if (parsedCrewId === null) {
      throw httpError(400, 'crewId must be a valid crew id');
    }
  }

  if (effectiveFrom !== undefined && effectiveFrom !== null) {
    requireDateString('effectiveFrom', effectiveFrom);
  }

  try {
    return await withActor(accountId, async (client) => {
      // Resolved once, up front, so "no effectiveFrom given" and "given but
      // equal to today" are the exact same value from here on — comparisons
      // below go through toDateString (string equality/ordering on
      // YYYY-MM-DD), not JS Date comparison, for the same reason
      // toDateString itself exists (see its own comment).
      const { rows: [{ resolved_effective_from: resolvedEffectiveFrom }] } = await client.query(
        'SELECT COALESCE($1::date, CURRENT_DATE) AS resolved_effective_from',
        [effectiveFrom ?? null]
      );
      const newEffectiveFrom = toDateString(resolvedEffectiveFrom);

      // Locked so a second, concurrent transfer for the same Employee can
      // never also read this row as open.
      const { rows: [openAssignment] } = await client.query(
        `SELECT id, effective_from FROM employee_assignments
          WHERE employee_id = $1 AND effective_to IS NULL
          FOR UPDATE`,
        [employeeId]
      );

      if (openAssignment) {
        const openEffectiveFrom = toDateString(openAssignment.effective_from);
        if (openEffectiveFrom === newEffectiveFrom) {
          throw httpError(409, 'this Employee already has an assignment beginning on that date');
        }
        if (openEffectiveFrom < newEffectiveFrom) {
          await client.query(
            'UPDATE employee_assignments SET effective_to = $1 WHERE id = $2',
            [newEffectiveFrom, openAssignment.id]
          );
        }
        // openEffectiveFrom > newEffectiveFrom: deliberately left open — see
        // this function's own header, case 4. The INSERT below will fail on
        // employee_assignments_no_overlap instead.
      }

      const { rows: [row] } = await client.query(
        `INSERT INTO employee_assignments (employee_id, org_unit_id, job_role_id, crew_id, effective_from)
         VALUES ($1, $2, $3, $4, $5)
         RETURNING id, effective_from, effective_to, crew_id,
                   (effective_from <= CURRENT_DATE
                    AND (effective_to IS NULL OR effective_to > CURRENT_DATE)) AS is_current`,
        [employeeId, parsedOrgUnitId, parsedJobRoleId, parsedCrewId, newEffectiveFrom]
      );

      return {
        id: row.id,
        effectiveFrom: toDateString(row.effective_from),
        effectiveTo: toDateString(row.effective_to),
        isCurrent: row.is_current,
        crewId: row.crew_id,
        orgUnit: { id: orgUnit.id, code: orgUnit.code, name: orgUnit.name },
        jobRole: jobRole ? { id: jobRole.id, code: jobRole.code, name: jobRole.name } : null
      };
    });
  } catch (error) {
    throw mapAssignmentWriteError(error);
  }
}

module.exports = {
  listEmployees,
  getEmployee,
  getEmployeeDetail,
  createEmployee,
  updateEmployee,
  setEmployeeDeparted,
  reinstateEmployee,
  createAssignment
};
