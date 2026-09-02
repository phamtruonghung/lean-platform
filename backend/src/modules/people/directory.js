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
 * check, no Org Unit scope, nothing about HTTP. Read directory-routes.js's
 * own header, and ADR-0009, for why the directory is deliberately not
 * gated by authorization.js the way plant-routes.js's Sites and Org Units
 * are: unlike an Org Unit or a Site, an Employee reaching this file is never
 * one the caller had to already be "entitled to name" — every function here
 * assumes only that the caller has already cleared authenticate/requireActive
 * one layer up.
 *
 * "Departed" is never a delete. It is `employees.is_active = FALSE`, with
 * `terminated_on` recording when — nothing in this Module, or any other,
 * ever removes an Employee row, since their history is what answers "who
 * worked here last March" (issue #9's own acceptance criteria; see also the
 * CONTEXT.md glossary's Departed entry).
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
 * Issue #10 (job roles and Org Unit assignments) adds two more write
 * surfaces, both owned here rather than in a new service file:
 *
 *  - Job roles (listJobRoles/createJobRole/setJobRoleActive). `job_roles` is
 *    only ever meaningful as an attribute of an Employee's assignment — this
 *    file already reads and maps it for the detail view (getEmployeeDetail,
 *    below) — so a fourth service+routes pair in this Module for a handful
 *    of CRUD functions over one small table would be a seam with nothing
 *    behind it. The table itself carries no `site_id`: criterion 1 ("Job
 *    roles are defined once and shared by every Site") is exactly what a
 *    global table already means structurally, not a rule this file has to
 *    enforce.
 *
 *  - Assignments (assignEmployee). A transfer is a new assignment that
 *    closes the previous one, in one transaction — see assignEmployee's own
 *    comment for why order (close, then insert) matters against the
 *    `employee_assignments_no_overlap` exclusion constraint. Issue #11
 *    (skills) still owns `employee_skills`'s own write surface; this file
 *    still only ever reads that one, for the detail view.
 */

const { getPool, withActor } = require('../../platform/db');
const { httpError, notFound, parseId } = require('./errors');
const { getOrgUnit } = require('./plant');

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
// the activity filter by AND — a caller narrowing by name, Org Unit or job
// role is never widening past "active only" by accident.
//
// An Employee is "at" an Org Unit by their CURRENT employee_assignments row
// (effective_from <= today AND (effective_to IS NULL OR effective_to >
// today)); when they have no current assignment, this falls back to
// employees.default_org_unit_id. This is the rule the whole orgUnitId filter
// turns on — see the LEFT JOIN LATERAL below, which resolves exactly that
// per employee, in the same query as everything else, never a query per row.
//
// orgUnitId filters through the tree, not by exact match (issue #9's own
// criterion): the resolved org unit's `path` is tested with `path <@` against
// the filter unit's own path, the same GiST-indexed pattern plant.js's
// getOrgUnitSubtree uses for "everything beneath this Org Unit" — an Employee
// assigned to a descendant of the filtered Org Unit is included, not only one
// assigned to it exactly.
//
// jobRoleId (issue #10, criterion 4) turns on the exact same "current
// assignment" rule, and reuses the same LEFT JOIN LATERAL rather than a
// second one — it is extended to also carry job_role_id, so a query using
// both filters together still resolves the current assignment once. Unlike
// the Org Unit filter, there is no default-job-role fallback: a job role is
// never a "default" the way default_org_unit_id is, only ever a current
// fact, so an Employee with no current assignment has a NULL
// current_assignment.job_role_id and never matches a jobRoleId filter — which
// is correct, since they hold no role right now.
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

  const wantsOrgUnitFilter = orgUnitId !== undefined && orgUnitId !== null;
  const wantsJobRoleFilter = jobRoleId !== undefined && jobRoleId !== null;

  let assignmentJoin = '';
  if (wantsOrgUnitFilter || wantsJobRoleFilter) {
    // LEFT JOIN LATERAL resolves the Employee's current assignment (Org Unit
    // and job role together) once per employee, in this one query — never an
    // N+1, and never a second lateral for the second filter.
    assignmentJoin = `
      LEFT JOIN LATERAL (
        SELECT ea.org_unit_id, ea.job_role_id
          FROM employee_assignments ea
         WHERE ea.employee_id = e.id
           AND ea.effective_from <= CURRENT_DATE
           AND (ea.effective_to IS NULL OR ea.effective_to > CURRENT_DATE)
         LIMIT 1
      ) current_assignment ON TRUE`;
  }

  if (wantsOrgUnitFilter) {
    // A tiny separate query to resolve the filter Org Unit's own path — 404s
    // if it does not exist at all, the same existence check every other Org
    // Unit id this Module accepts gets (plant.getOrgUnit).
    const target = await getOrgUnit(orgUnitId);
    params.push(target.path);
    // COALESCE falls back to the default when there is no current
    // assignment row at all.
    assignmentJoin += `
      JOIN org_units resolved_ou
        ON resolved_ou.id = COALESCE(current_assignment.org_unit_id, e.default_org_unit_id)`;
    conditions.push(`resolved_ou.path <@ $${params.length}::ltree`);
  }

  if (wantsJobRoleFilter) {
    params.push(jobRoleId);
    conditions.push(`current_assignment.job_role_id = $${params.length}`);
  }

  const whereClause = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';

  const { rows } = await getPool().query(
    `SELECT ${EMPLOYEE_COLUMNS_QUALIFIED}
       FROM employees e
       ${assignmentJoin}
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

// The Employee detail view's own acceptance criterion: job role, Org Unit
// assignments and skills, alongside the Employee record itself. Three
// queries total (the Employee, the assignments, the skills) — never a query
// per assignment or per skill.
async function getEmployeeDetail(id) {
  const employee = await getEmployee(id); // throws the 404.

  const { rows: assignmentRows } = await getPool().query(
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
    [id]
  );

  const assignments = assignmentRows.map(toAssignment);

  // jobRole on the detail view itself is the CURRENT assignment's job role —
  // the same "current" rule listEmployees's Org Unit filter turns on,
  // computed in SQL (is_current, above) rather than compared against
  // `new Date()` in JS: pg parses a DATE column back as a JS Date object, not
  // a string, so a JS-side comparison against today's date would need to
  // reproduce Postgres's own date semantics instead of just asking Postgres.
  const currentAssignment = assignmentRows.find((row) => row.is_current);
  const jobRole = currentAssignment?.job_role_id
    ? { id: currentAssignment.job_role_id, code: currentAssignment.job_role_code, name: currentAssignment.job_role_name }
    : null;

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

// ---------------------------------------------------------------------------
// Job roles (issue #10, criterion 1) — "defined once and shared by every
// Site" is exactly what the baseline's `job_roles` table already is
// structurally (no `site_id` column at all), not a rule enforced here. See
// this file's own header for why job roles live here rather than in a
// separate service.
// ---------------------------------------------------------------------------

const JOB_ROLE_COLUMNS = 'id, code, name, is_active, created_at, updated_at';

function toJobRole(row) {
  return {
    id: row.id,
    code: row.code,
    name: row.name,
    isActive: row.is_active,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

// Active job roles by default, ordered by name; includeInactive also brings
// in deactivated ones — the same shape as listEmployees's includeDeparted,
// for the same reason: a caller narrowing a listing should never silently
// widen it by omission.
async function listJobRoles({ includeInactive } = {}) {
  const whereClause = includeInactive ? '' : 'WHERE is_active = TRUE';
  const { rows } = await getPool().query(
    `SELECT ${JOB_ROLE_COLUMNS} FROM job_roles ${whereClause} ORDER BY name`
  );
  return rows.map(toJobRole);
}

// Mirrors getEmployee exactly: null id and "no such row" are both a 404, one
// query, no scope check (job roles are catalogue data, read by any approved
// Account — see directory-routes.js's own header). assignEmployee below uses
// this the same way it uses plant.getOrgUnit, to 404 a jobRoleId naming
// nothing at all rather than let it fall through to the foreign-key
// violation Postgres would otherwise raise on the INSERT.
async function getJobRole(id) {
  if (id === null) throw notFound('job role');
  const { rows } = await getPool().query(
    `SELECT ${JOB_ROLE_COLUMNS} FROM job_roles WHERE id = $1`,
    [id]
  );
  if (!rows[0]) throw notFound('job role');
  return toJobRole(rows[0]);
}

// A write against `job_roles` can fail for one reason this file turns into a
// clean 4xx rather than a 500: the `code` UNIQUE constraint. Anything else is
// a genuine failure and is rethrown as-is, same as mapEmployeeWriteError.
function mapJobRoleWriteError(error) {
  if (error.code === '23505') {
    return httpError(409, 'a job role with this code already exists');
  }
  return error;
}

async function createJobRole({ code, name } = {}, accountId) {
  requireNonEmptyString('code', code);
  requireNonEmptyString('name', name);

  try {
    return await withActor(accountId, async (client) => {
      const { rows: [row] } = await client.query(
        `INSERT INTO job_roles (code, name) VALUES ($1, $2) RETURNING ${JOB_ROLE_COLUMNS}`,
        [code.trim(), name.trim()]
      );
      return toJobRole(row);
    });
  } catch (error) {
    throw mapJobRoleWriteError(error);
  }
}

// Deactivation, not deletion — past assignments still reference the role
// (employee_assignments.job_role_id has no ON DELETE, and never should:
// deleting a role a Departed Employee once held would erase the fact they
// held it). Mirrors plant.setOrgUnitActive exactly.
async function setJobRoleActive(id, isActive, accountId) {
  await getJobRole(id); // 404s if it does not exist.

  return withActor(accountId, async (client) => {
    const { rows: [row] } = await client.query(
      `UPDATE job_roles SET is_active = $1 WHERE id = $2 RETURNING ${JOB_ROLE_COLUMNS}`,
      [isActive, id]
    );
    return toJobRole(row);
  });
}

// ---------------------------------------------------------------------------
// Assignments (issue #10, criteria 2 and 3) — where an Employee works, and as
// what, over time. See the baseline's own comment above `employee_assignments`
// for why this is history rather than columns on `employees`.
// ---------------------------------------------------------------------------

const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;

// A supplied effectiveFrom must be a real calendar date, not just a string
// shaped like one — a `YYYY-MM-DD` regex alone would still accept
// '2024-02-30'. Validated here so a bad value comes back as a clean 400
// instead of a Postgres cast error, the same reasoning as every other
// CHECK-mirroring validator in this Module.
function requireDateString(field, value) {
  if (typeof value !== 'string' || !DATE_PATTERN.test(value)) {
    throw httpError(400, `${field} must be a valid YYYY-MM-DD date`);
  }
  const [year, month, day] = value.split('-').map(Number);
  const date = new Date(Date.UTC(year, month - 1, day));
  if (date.getUTCFullYear() !== year || date.getUTCMonth() !== month - 1 || date.getUTCDate() !== day) {
    throw httpError(400, `${field} must be a valid YYYY-MM-DD date`);
  }
}

// A write against `employee_assignments` can fail two ways this file turns
// into a clean 4xx rather than a 500:
//
//  - `employee_assignments_no_overlap` (SQLSTATE 23P01, an EXCLUDE USING
//    gist violation — confirmed against a real error, not assumed) when the
//    new row's range overlaps an existing one for the same Employee. The
//    realistic cause is a backdated assignment landing in the middle of an
//    Employee's existing history — "conflicting key value violates
//    exclusion constraint" names neither the Employee nor the date, so this
//    replaces it with something a caller can actually act on.
//  - `employee_assignments_range_valid` (SQLSTATE 23514, a CHECK violation)
//    if the equal-bounds guard below is ever bypassed and an UPDATE reaches
//    Postgres with `effective_to = effective_from`. Mapped here as a second
//    line of defence, not the primary one — the guard itself is what a
//    caller should actually hit.
function mapAssignmentWriteError(error) {
  if (error.code === '23P01') {
    return httpError(409, 'this Employee already has an assignment covering that date');
  }
  if (error.code === '23514' && error.constraint === 'employee_assignments_range_valid') {
    return httpError(400, "effectiveFrom must be after the Employee's current assignment began");
  }
  return error;
}

// The shape both getEmployeeDetail's own `assignments` entries and
// assignEmployee's own return value use (Org Unit and job role named, not
// just id'd) — one mapper for both, since the two queries that feed it
// (getEmployeeDetail's own SELECT, and assignEmployee's WITH/INSERT/SELECT)
// are deliberately shaped to return the same columns.
function toAssignment(row) {
  return {
    id: row.id,
    effectiveFrom: toDateString(row.effective_from),
    effectiveTo: toDateString(row.effective_to),
    crewId: row.crew_id,
    orgUnit: { id: row.org_unit_id, code: row.org_unit_code, name: row.org_unit_name },
    jobRole: row.job_role_id
      ? { id: row.job_role_id, code: row.job_role_code, name: row.job_role_name }
      : null
  };
}

// A transfer (criterion 3) is a new assignment that closes the previous one,
// in one transaction: "intact" means the old row is never deleted or
// rewritten, only given the `effective_to` its replacement's own
// `effectiveFrom` supplies. Order matters — the previous assignment is
// closed before the new one is inserted, since `employee_assignments_no_overlap`
// (a GiST exclusion constraint) evaluates the whole table as it stands at
// each statement: inserting first, while the old row is still open-ended,
// would always conflict with it.
//
// crewId is not accepted here at all: crews are per-Site and out of scope
// for this ticket (see the issue's own note), and a `crewId` this file did
// not validate would reach the same unmapped foreign-key violation a bad
// jobRoleId used to. `crew_id` simply stays NULL on every assignment this
// function creates until the ticket that owns crews adds it back
// deliberately, with its own existence check.
async function assignEmployee(employeeId, { orgUnitId, jobRoleId, effectiveFrom } = {}, accountId) {
  await getEmployee(employeeId); // 404s if it does not exist.

  const orgUnitIdValue = parseId(orgUnitId);
  if (orgUnitIdValue === null) {
    throw httpError(400, 'orgUnitId is required');
  }
  await getOrgUnit(orgUnitIdValue); // 404s if it does not exist.

  let jobRoleIdValue = null;
  if (jobRoleId !== undefined && jobRoleId !== null) {
    jobRoleIdValue = parseId(jobRoleId);
    if (jobRoleIdValue === null) {
      throw httpError(400, 'jobRoleId must be a valid job role id');
    }
    await getJobRole(jobRoleIdValue); // 404s if it does not exist.
  }

  // effectiveFrom defaults to CURRENT_DATE (issue #10's own default) —
  // resolved against Postgres's own clock, not the Node process's, for the
  // same reason getEmployeeDetail computes is_current in SQL rather than
  // against `new Date()`: pg's DATE columns are compared by Postgres's own
  // date semantics, so the "today" this function reasons about in JS (the
  // equality check against an existing current assignment, below) has to be
  // the same "today" the database would use.
  let effectiveFromValue;
  if (effectiveFrom === undefined || effectiveFrom === null) {
    const { rows: [{ today }] } = await getPool().query('SELECT CURRENT_DATE AS today');
    effectiveFromValue = toDateString(today);
  } else {
    requireDateString('effectiveFrom', effectiveFrom);
    effectiveFromValue = effectiveFrom;
  }

  try {
    return await withActor(accountId, async (client) => {
      // The Employee's assignment current as of effectiveFrom, if any — the
      // exact "current" rule listEmployees's own filters turn on, just
      // evaluated at effectiveFrom instead of CURRENT_DATE, since a transfer
      // can be backdated or postdated relative to today.
      const { rows: [current] } = await client.query(
        `SELECT id, effective_from FROM employee_assignments
          WHERE employee_id = $1
            AND effective_from <= $2
            AND (effective_to IS NULL OR effective_to > $2)
          LIMIT 1`,
        [employeeId, effectiveFromValue]
      );

      if (current) {
        if (toDateString(current.effective_from) === effectiveFromValue) {
          // Closing the current assignment at its own effective_from would
          // produce an empty range ('[)' with equal bounds), tripping
          // `employee_assignments_range_valid` (effective_to > effective_from,
          // SQLSTATE 23514) — rejected here instead, with a message naming
          // the actual problem, rather than left to fall through to that
          // CHECK's own opaque one. mapAssignmentWriteError still maps 23514
          // as a second line of defence in case this guard is ever bypassed.
          throw httpError(400, "effectiveFrom must be after the Employee's current assignment began");
        }
        await client.query(
          'UPDATE employee_assignments SET effective_to = $1 WHERE id = $2',
          [effectiveFromValue, current.id]
        );
      }

      const { rows: [row] } = await client.query(
        `WITH inserted AS (
           INSERT INTO employee_assignments (employee_id, org_unit_id, job_role_id, effective_from)
           VALUES ($1, $2, $3, $4)
           RETURNING id, org_unit_id, job_role_id, crew_id, effective_from, effective_to
         )
         SELECT i.id, i.effective_from, i.effective_to, i.crew_id,
                ou.id AS org_unit_id, ou.code AS org_unit_code, ou.name AS org_unit_name,
                jr.id AS job_role_id, jr.code AS job_role_code, jr.name AS job_role_name
           FROM inserted i
           JOIN org_units ou ON ou.id = i.org_unit_id
           LEFT JOIN job_roles jr ON jr.id = i.job_role_id`,
        [employeeId, orgUnitIdValue, jobRoleIdValue, effectiveFromValue]
      );

      return toAssignment(row);
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
  listJobRoles,
  createJobRole,
  setJobRoleActive,
  assignEmployee
};
