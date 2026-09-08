/*
 * The Employee directory, over HTTP (issue #9), against a real database and
 * a real (locally issued) JWKS — the same seam as accounts.test.js,
 * plant.test.js and approval.test.js (see any of their own headers, and the
 * README's Tests section).
 *
 * This file does not truncate `app_users`, `org_units` or `sites`: all three
 * are shared with the other integration files, and `npm run test:integration`
 * runs every file in this directory with `--test-concurrency=1`, so two files
 * truncating the same table between runs would still corrupt whichever ran
 * first if either forgot its own cleanup. Instead this file inserts its own
 * `app_users` rows under a `process.pid`-unique `external_subject`, and uses
 * a `uniqueCode`-style helper (the same device as plant.test.js/
 * approval.test.js) for every UNIQUE constraint value this file touches:
 * `employees.employee_no`, `job_roles.code`, `skills.code`, `sites.code`, and
 * `(site_id, code)` on `org_units`. Every row inserted, across `app_users`,
 * `sites`, `org_units`, `job_roles`, `skills`, `employees`,
 * `employee_assignments` and `employee_skills`, is deleted again in
 * `test.after()`.
 *
 * There are no HTTP endpoints yet for `job_roles`, `skills`,
 * `employee_skills` or `employee_assignments` — issues #10 and #11 own those
 * write surfaces later — so those fixtures are inserted directly via SQL
 * (`pool.query`). Employees are ALSO inserted via direct SQL: this pass of
 * issue #9 is read-only (criteria 5 and 6, adding/editing/departing/
 * reinstating an Employee, are a later pass), so there is no POST /employees
 * to drive them through instead.
 *
 * Every route this file exercises sits behind `authenticate` + `requireActive`
 * only — no Org Unit scope, no grants needed anywhere below (ADR-0009: the
 * directory is deliberately not Org-Unit-scoped), which is also why this
 * file never inserts an `app_user_org_units` row.
 *
 * Needs a database with every migration applied. Set DATABASE_URL first —
 * see the README's Tests section.
 */

const test = require('node:test');
const assert = require('node:assert');
const { createTestJwks } = require('../helpers/jwks');
const skillFixtures = require('../helpers/skills');

const ISSUER = 'https://example.supabase.co/auth/v1';
const AUDIENCE = 'authenticated';

let jwks;
let server;
let base;
let pool;
let closePool;

let readerToken; // an ordinary approved, active Account — no grants needed.
let memberToken; // approved, active, non-admin, employee_id set (criterion 7).
let noEmployeeToken; // approved, active, employee_id NULL (criterion 8).
let pendingToken; // unapproved/inactive (criterion 9).

const insertedAccountIds = [];
const insertedSiteIds = [];
const insertedOrgUnitIds = [];
const insertedJobRoleIds = [];
const insertedSkillIds = [];
const insertedEmployeeIds = [];

let codeCounter = 0;
// Unique across processes (process.pid) and within one run (the counter) —
// the same device plant.test.js's and approval.test.js's own uniqueCode use,
// so a UNIQUE constraint (employee_no, job_roles.code, skills.code, sites.code,
// (site_id, code) on org_units) is never collided on by this file's own
// fixtures or by a previous run's leftovers.
function uniqueCode(prefix) {
  codeCounter += 1;
  return `${prefix}${process.pid}${codeCounter}`;
}

async function authHeader(subject) {
  const token = await jwks.signToken(
    { sub: subject, email: `${subject}@example.com` },
    { issuer: ISSUER, audience: AUDIENCE }
  );
  return { authorization: `Bearer ${token}` };
}

// Fixtures shared by every test in this file — the directory's own read
// surface has no side effects, so one set of Employees, Org Units, a job
// role and a skill built once in test.before covers every criterion.
let site;
let ancestorUnit; // area
let childUnit; // department, under ancestorUnit
let grandchildUnit; // line, under childUnit — two levels down from ancestorUnit
let outsideUnit; // a separate root, not beneath ancestorUnit at all
let jobRole;
let skill;

let richEmployee; // current assignment at grandchildUnit, with jobRole and a skill
let outsideEmployee; // current assignment at outsideUnit
let defaultOnlyEmployee; // no current assignment; default_org_unit_id = grandchildUnit
let departedEmployee; // is_active = FALSE
let searchTargetEmployee; // 'Zbigniew Nowak' — matched by the search tests
let searchOtherEmployee; // 'Marek Kowalski' — must NOT match the search tests

async function insertOrgUnit({ parentId, unitType, name }) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, $2, $3, $4, $5) RETURNING id`,
    [site.id, parentId ?? null, uniqueCode('OU'), name, unitType]
  );
  insertedOrgUnitIds.push(row.id);
  return row.id;
}

async function insertEmployee({ firstName, lastName, isActive = true, terminatedOn = null, defaultOrgUnitId = null }) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO employees (employee_no, first_name, last_name, is_active, terminated_on, default_org_unit_id)
     VALUES ($1, $2, $3, $4, $5, $6) RETURNING id`,
    [uniqueCode('EMP'), firstName, lastName, isActive, terminatedOn, defaultOrgUnitId]
  );
  insertedEmployeeIds.push(row.id);
  return row.id;
}

async function insertAssignment({ employeeId, orgUnitId, jobRoleId = null, effectiveFrom, effectiveTo = null }) {
  await pool.query(
    `INSERT INTO employee_assignments (employee_id, org_unit_id, job_role_id, effective_from, effective_to)
     VALUES ($1, $2, $3, $4, $5)`,
    [employeeId, orgUnitId, jobRoleId, effectiveFrom, effectiveTo]
  );
}

// Thin wrappers over the shared fixtures in test/helpers/skills.js: this
// file's own tracking (insertedSkillIds) and skill-name convention live
// here, the SQL itself lives there, shared with work-orders.test.js.
async function insertSkill({ revalidationMonths = null } = {}) {
  const row = await skillFixtures.insertSkill(pool, uniqueCode, {
    name: 'Assignee Candidate Skill',
    revalidationMonths
  });
  insertedSkillIds.push(row.id);
  return row;
}

async function insertEmployeeSkill({ employeeId, skillId, assessedOn, expiresOn }) {
  return skillFixtures.insertEmployeeSkill(pool, { employeeId, skillId, assessedOn, expiresOn });
}

async function candidatesRequest(query = '', token = readerToken) {
  return fetch(`${base}/api/people/employees/assignee-candidates${query}`, { headers: token });
}

test.before(async () => {
  jwks = await createTestJwks();
  process.env.SUPABASE_JWKS_URL = jwks.url;
  process.env.SUPABASE_JWT_ISSUER = ISSUER;
  process.env.SUPABASE_JWT_AUDIENCE = AUDIENCE;
  process.env.BACKEND_PORT = '0';

  ({ server } = require('../../src/index'));
  ({ closePool } = require('../../src/platform/db'));
  pool = require('../../src/platform/db').getPool();

  if (!server.listening) {
    await new Promise((resolve, reject) => {
      server.once('listening', resolve);
      server.once('error', reject);
    });
  }
  base = `http://127.0.0.1:${server.address().port}`;

  // ---------------------------------------------------------------------
  // Accounts
  // ---------------------------------------------------------------------
  const readerSubject = `directory-reader-${process.pid}`;
  const noEmployeeSubject = `directory-no-employee-${process.pid}`;
  const pendingSubject = `directory-pending-${process.pid}`;
  const memberSubject = `directory-member-${process.pid}`;

  const { rows: [reader] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status)
     VALUES ($1, 'Directory Test Reader', 'operator', $2, TRUE, 'approved') RETURNING id`,
    [`${readerSubject}@example.com`, readerSubject]
  );
  const { rows: [pendingAccount] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status)
     VALUES ($1, 'Directory Test Pending', 'operator', $2, FALSE, 'pending') RETURNING id`,
    [`${pendingSubject}@example.com`, pendingSubject]
  );
  insertedAccountIds.push(reader.id, pendingAccount.id);
  readerToken = await authHeader(readerSubject);
  pendingToken = await authHeader(pendingSubject);

  // ---------------------------------------------------------------------
  // Site and Org Unit tree: ancestorUnit -> childUnit -> grandchildUnit,
  // plus outsideUnit, a separate root not beneath ancestorUnit at all.
  // ---------------------------------------------------------------------
  const { rows: [siteRow] } = await pool.query(
    `INSERT INTO sites (code, name, timezone) VALUES ($1, 'Directory Test Site', 'Asia/Ho_Chi_Minh') RETURNING id`,
    [uniqueCode('ST')]
  );
  site = siteRow;
  insertedSiteIds.push(site.id);

  ancestorUnit = await insertOrgUnit({ unitType: 'area', name: 'Directory Test Area' });
  childUnit = await insertOrgUnit({ parentId: ancestorUnit, unitType: 'department', name: 'Directory Test Department' });
  grandchildUnit = await insertOrgUnit({ parentId: childUnit, unitType: 'line', name: 'Directory Test Line' });
  outsideUnit = await insertOrgUnit({ unitType: 'area', name: 'Directory Test Outside Area' });

  // ---------------------------------------------------------------------
  // A job role and a skill (issue #10/#11's own tables — read-only here).
  // ---------------------------------------------------------------------
  const { rows: [jobRoleRow] } = await pool.query(
    `INSERT INTO job_roles (code, name) VALUES ($1, 'Directory Test Fitter') RETURNING id, code, name`,
    [uniqueCode('JR')]
  );
  jobRole = jobRoleRow;
  insertedJobRoleIds.push(jobRole.id);

  const { rows: [skillRow] } = await pool.query(
    `INSERT INTO skills (code, name) VALUES ($1, 'Directory Test Welding') RETURNING id, code, name`,
    [uniqueCode('SK')]
  );
  skill = skillRow;
  insertedSkillIds.push(skill.id);

  // ---------------------------------------------------------------------
  // Employees
  // ---------------------------------------------------------------------
  richEmployee = await insertEmployee({ firstName: 'Ada', lastName: 'Lovelace' });
  // A past, non-current assignment (job role null), then the current one
  // (grandchildUnit, jobRole) — proves getEmployeeDetail returns every
  // assignment, newest first, not only the current one.
  await insertAssignment({
    employeeId: richEmployee,
    orgUnitId: ancestorUnit,
    effectiveFrom: '2020-01-01',
    effectiveTo: '2021-01-01'
  });
  await insertAssignment({
    employeeId: richEmployee,
    orgUnitId: grandchildUnit,
    jobRoleId: jobRole.id,
    effectiveFrom: '2021-01-01',
    effectiveTo: null
  });
  await pool.query(
    `INSERT INTO employee_skills (employee_id, skill_id, proficiency_level, assessed_on)
     VALUES ($1, $2, 3, '2021-06-01')`,
    [richEmployee, skill.id]
  );

  outsideEmployee = await insertEmployee({ firstName: 'Otto', lastName: 'Outside' });
  await insertAssignment({ employeeId: outsideEmployee, orgUnitId: outsideUnit, effectiveFrom: '2021-01-01' });

  defaultOnlyEmployee = await insertEmployee({
    firstName: 'Debra',
    lastName: 'Default',
    defaultOrgUnitId: grandchildUnit
  });

  departedEmployee = await insertEmployee({
    firstName: 'Delia',
    lastName: 'Departed',
    isActive: false,
    terminatedOn: '2024-01-01'
  });

  searchTargetEmployee = await insertEmployee({ firstName: 'Zbigniew', lastName: 'Nowak' });
  searchOtherEmployee = await insertEmployee({ firstName: 'Marek', lastName: 'Kowalski' });

  // The Member (criterion 7): an approved, active, non-admin Account linked
  // to richEmployee via app_users.employee_id.
  const { rows: [member] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status, employee_id)
     VALUES ($1, 'Directory Test Member', 'operator', $2, TRUE, 'approved', $3) RETURNING id`,
    [`${memberSubject}@example.com`, memberSubject, richEmployee]
  );
  insertedAccountIds.push(member.id);
  memberToken = await authHeader(memberSubject);

  // An approved, active Account with no linked Employee (criterion 8).
  const { rows: [noEmployee] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status)
     VALUES ($1, 'Directory Test No Employee', 'operator', $2, TRUE, 'approved') RETURNING id`,
    [`${noEmployeeSubject}@example.com`, noEmployeeSubject]
  );
  insertedAccountIds.push(noEmployee.id);
  noEmployeeToken = await authHeader(noEmployeeSubject);

  // The write-surface administrator (issue #9, criteria 5/6) — folded into
  // this same hook rather than a second top-level test.before(): node:test
  // runs a root before() registered after the first test() immediately and
  // un-awaited (it does not queue behind an in-flight root before()), so a
  // second one here would race this one instead of running after it — see
  // the comment above the write-surface section below for the fuller story.
  const adminSubject = `directory-admin-${process.pid}`;
  const { rows: [admin] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status)
     VALUES ($1, 'Directory Test Admin', 'admin', $2, TRUE, 'approved') RETURNING id`,
    [`${adminSubject}@example.com`, adminSubject]
  );
  insertedAccountIds.push(admin.id); // cleaned up by this same hook's own test.after, below.
  adminToken = await authHeader(adminSubject);
});

test.after(async () => {
  await pool.query('DELETE FROM employee_skills WHERE employee_id = ANY($1)', [insertedEmployeeIds]);
  await pool.query('DELETE FROM employee_assignments WHERE employee_id = ANY($1)', [insertedEmployeeIds]);
  await pool.query('DELETE FROM app_users WHERE id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM employees WHERE id = ANY($1)', [insertedEmployeeIds]);
  await pool.query('DELETE FROM skills WHERE id = ANY($1)', [insertedSkillIds]);
  await pool.query('DELETE FROM job_roles WHERE id = ANY($1)', [insertedJobRoleIds]);
  await pool.query('DELETE FROM org_units WHERE id = ANY($1)', [insertedOrgUnitIds]);
  await pool.query('DELETE FROM sites WHERE id = ANY($1)', [insertedSiteIds]);

  // Belt and braces: any Employee a write-surface test below failed to clean
  // up itself is still removed here, so a failing assertion mid-test never
  // leaks a row into the next run's UNIQUE-constraint namespace.
  if (writeTestEmployeeIds.length > 0) {
    await pool.query('DELETE FROM employees WHERE id = ANY($1)', [writeTestEmployeeIds]);
  }

  await new Promise((resolve) => server.close(resolve));
  await closePool();
  await jwks.close();
});

async function listEmployeesRequest(query = '', token = readerToken) {
  return fetch(`${base}/api/people/employees${query}`, { headers: token });
}

// ---------------------------------------------------------------------------
// 1. Active Employees by default; a Departed one is absent.
// ---------------------------------------------------------------------------

test('the list shows Active Employees by default, and a Departed Employee is absent from it', async () => {
  const response = await listEmployeesRequest();
  assert.strictEqual(response.status, 200);
  const { employees } = await response.json();
  const ids = employees.map((e) => e.id);

  assert.ok(ids.includes(richEmployee), 'an Active Employee should be in the default list');
  assert.ok(!ids.includes(departedEmployee), 'a Departed Employee should not be in the default list');
});

// ---------------------------------------------------------------------------
// 2. Departed Employees can be included on request.
// ---------------------------------------------------------------------------

test('?includeDeparted=true includes the Departed Employee; the default and ?includeDeparted=false do not', async () => {
  const withDeparted = await listEmployeesRequest('?includeDeparted=true');
  const { employees: withDepartedList } = await withDeparted.json();
  assert.ok(withDepartedList.map((e) => e.id).includes(departedEmployee));

  const explicitFalse = await listEmployeesRequest('?includeDeparted=false');
  const { employees: explicitFalseList } = await explicitFalse.json();
  assert.ok(!explicitFalseList.map((e) => e.id).includes(departedEmployee));

  // Any string other than the exact literal "true" must not widen the list —
  // a stray or malformed value is the failure mode this guards against, not
  // a shorthand for "true".
  const garbage = await listEmployeesRequest('?includeDeparted=yes');
  const { employees: garbageList } = await garbage.json();
  assert.ok(!garbageList.map((e) => e.id).includes(departedEmployee));
});

// ---------------------------------------------------------------------------
// 3. Searched by name, case-insensitively, on part of either the first or
//    last name.
// ---------------------------------------------------------------------------

test('search by name matches on part of a first name and on part of a last name, case-insensitively, and excludes a non-matching Employee', async () => {
  const byFirstName = await listEmployeesRequest('?search=BIGNI'); // part of 'Zbigniew', wrong case
  const { employees: byFirstNameList } = await byFirstName.json();
  const byFirstNameIds = byFirstNameList.map((e) => e.id);
  assert.ok(byFirstNameIds.includes(searchTargetEmployee));
  assert.ok(!byFirstNameIds.includes(searchOtherEmployee));

  const byLastName = await listEmployeesRequest('?search=owak'); // part of 'Nowak'
  const { employees: byLastNameList } = await byLastName.json();
  const byLastNameIds = byLastNameList.map((e) => e.id);
  assert.ok(byLastNameIds.includes(searchTargetEmployee));
  assert.ok(!byLastNameIds.includes(searchOtherEmployee));
});

// ---------------------------------------------------------------------------
// 4. The Org Unit filter resolves through the tree, not by exact match.
// ---------------------------------------------------------------------------

test('the Org Unit filter resolves through the tree: an Employee assigned to a descendant Org Unit is returned, and one assigned outside the subtree is not', async () => {
  const response = await listEmployeesRequest(`?orgUnitId=${ancestorUnit}`);
  assert.strictEqual(response.status, 200);
  const { employees } = await response.json();
  const ids = employees.map((e) => e.id);

  // richEmployee's CURRENT assignment is at grandchildUnit, two levels
  // beneath ancestorUnit, not ancestorUnit itself — a naive
  // `org_unit_id = ancestorUnit` filter would miss them entirely.
  assert.ok(ids.includes(richEmployee), 'an Employee assigned to a descendant Org Unit should match');
  assert.ok(!ids.includes(outsideEmployee), 'an Employee assigned outside the subtree should not match');
});

// ---------------------------------------------------------------------------
// 5. No current assignment: matched via default_org_unit_id instead.
// ---------------------------------------------------------------------------

test('an Employee with no current assignment is matched by their default_org_unit_id when filtering by Org Unit', async () => {
  const response = await listEmployeesRequest(`?orgUnitId=${grandchildUnit}`);
  assert.strictEqual(response.status, 200);
  const { employees } = await response.json();
  const ids = employees.map((e) => e.id);

  assert.ok(ids.includes(defaultOnlyEmployee), 'an Employee with no current assignment should match on default_org_unit_id');
});

// ---------------------------------------------------------------------------
// 6. The detail view shows job role, Org Unit assignments and skills.
// ---------------------------------------------------------------------------

test('the detail view (GET /employees/:id) shows job role, Org Unit assignments and skills correctly', async () => {
  const response = await fetch(`${base}/api/people/employees/${richEmployee}`, { headers: readerToken });
  assert.strictEqual(response.status, 200);
  const { employee } = await response.json();

  assert.strictEqual(employee.id, richEmployee);
  assert.deepStrictEqual(employee.jobRole, { id: jobRole.id, code: jobRole.code, name: jobRole.name });

  assert.strictEqual(employee.assignments.length, 2);
  // Newest first.
  assert.strictEqual(employee.assignments[0].orgUnit.id, grandchildUnit);
  assert.strictEqual(employee.assignments[0].jobRole.id, jobRole.id);
  assert.strictEqual(employee.assignments[1].orgUnit.id, ancestorUnit);
  assert.strictEqual(employee.assignments[1].jobRole, null);

  assert.strictEqual(employee.skills.length, 1);
  assert.strictEqual(employee.skills[0].skill.id, skill.id);
  assert.strictEqual(employee.skills[0].skill.code, skill.code);
  assert.strictEqual(employee.skills[0].proficiencyLevel, 3);
});

// ---------------------------------------------------------------------------
// 7. A Member sees their own Employee record via GET /employees/me.
// ---------------------------------------------------------------------------

test('a Member (a non-administrator, approved Account with employee_id set) gets their own record from GET /employees/me', async () => {
  const response = await fetch(`${base}/api/people/employees/me`, { headers: memberToken });
  assert.strictEqual(response.status, 200);
  const { employee } = await response.json();
  assert.strictEqual(employee.id, richEmployee);
  // The same detail shape as GET /employees/:id.
  assert.deepStrictEqual(employee.jobRole, { id: jobRole.id, code: jobRole.code, name: jobRole.name });
});

// ---------------------------------------------------------------------------
// 8. An Account with no linked Employee gets a 404, not a 500.
// ---------------------------------------------------------------------------

test('an Account with no linked Employee gets a 404 from GET /employees/me, not a 500', async () => {
  const response = await fetch(`${base}/api/people/employees/me`, { headers: noEmployeeToken });
  assert.strictEqual(response.status, 404);
  const body = await response.json();
  assert.match(body.message, /no linked Employee/i);
});

// ---------------------------------------------------------------------------
// 9. An unapproved or inactive Account is refused, like every other route
//    behind requireActive.
// ---------------------------------------------------------------------------

test('an unapproved or inactive Account gets a 403 from the list (GET /employees), like every other route behind requireActive', async () => {
  const response = await listEmployeesRequest('', pendingToken);
  assert.strictEqual(response.status, 403);
  const body = await response.json();
  assert.strictEqual(body.status, 'pending_approval');
});

// ---------------------------------------------------------------------------
// GET /employees/assignee-candidates (issue #62) — who a Work order could
// be given to, and what each of them currently holds. No qualification check
// anywhere here or on the write path it feeds — ADR-0018.
// ---------------------------------------------------------------------------

test('GET /employees/assignee-candidates lists Active Employees with the skills each holds', async () => {
  const candidateSkill = await insertSkill();
  const employee = await insertEmployee({ firstName: 'Candidate', lastName: 'Current' });
  await insertEmployeeSkill({
    employeeId: employee,
    skillId: candidateSkill.id,
    assessedOn: '2021-06-01',
    expiresOn: '2099-01-01'
  });

  const response = await candidatesRequest();
  assert.strictEqual(response.status, 200);
  const { candidates } = await response.json();

  const found = candidates.find((c) => c.id === employee);
  assert.ok(found, 'the Active Employee should be among the candidates');
  assert.ok(found.employeeNo);
  assert.ok(found.displayName);

  const heldSkill = found.skills.find((s) => s.skill.id === candidateSkill.id);
  assert.ok(heldSkill, 'the recorded skill should be on the candidate');
  assert.strictEqual(heldSkill.proficiencyLevel, 3);
  assert.strictEqual(heldSkill.expiresOn, '2099-01-01');
  assert.deepStrictEqual(heldSkill.skill, { id: candidateSkill.id, code: candidateSkill.code, name: candidateSkill.name });
});

test('a lapsed qualification is listed with isLapsed true, not omitted', async () => {
  const lapsedSkill = await insertSkill();
  const employee = await insertEmployee({ firstName: 'Candidate', lastName: 'Lapsed' });
  await insertEmployeeSkill({
    employeeId: employee,
    skillId: lapsedSkill.id,
    assessedOn: '2020-01-01',
    expiresOn: '2021-01-01'
  });

  const response = await candidatesRequest();
  const { candidates } = await response.json();
  const found = candidates.find((c) => c.id === employee);
  assert.ok(found, 'a candidate holding only a lapsed qualification is still listed');

  const heldSkill = found.skills.find((s) => s.skill.id === lapsedSkill.id);
  assert.ok(heldSkill);
  assert.strictEqual(heldSkill.isLapsed, true);
  assert.strictEqual(heldSkill.expiresOn, '2021-01-01');
});

test('a qualification with no expiry, and one expiring in the future, are both isLapsed false', async () => {
  // revalidationMonths null means the employee_skills_set_expiry trigger
  // never derives an expiry for this skill, so an omitted expiresOn really
  // means "never expires", not "the trigger picked a date for me".
  const neverExpiresSkill = await insertSkill({ revalidationMonths: null });
  const futureSkill = await insertSkill();

  const neverExpiresEmployee = await insertEmployee({ firstName: 'Candidate', lastName: 'NeverExpires' });
  await insertEmployeeSkill({ employeeId: neverExpiresEmployee, skillId: neverExpiresSkill.id, expiresOn: null });

  const futureEmployee = await insertEmployee({ firstName: 'Candidate', lastName: 'FutureExpiry' });
  await insertEmployeeSkill({ employeeId: futureEmployee, skillId: futureSkill.id, expiresOn: '2099-01-01' });

  const { candidates } = await (await candidatesRequest()).json();

  const neverExpiresCandidate = candidates.find((c) => c.id === neverExpiresEmployee);
  const neverExpiresHeld = neverExpiresCandidate.skills.find((s) => s.skill.id === neverExpiresSkill.id);
  assert.strictEqual(neverExpiresHeld.expiresOn, null);
  assert.strictEqual(neverExpiresHeld.isLapsed, false);

  const futureCandidate = candidates.find((c) => c.id === futureEmployee);
  const futureHeld = futureCandidate.skills.find((s) => s.skill.id === futureSkill.id);
  assert.strictEqual(futureHeld.expiresOn, '2099-01-01');
  assert.strictEqual(futureHeld.isLapsed, false);
});

test('a candidate who holds nothing comes back with an empty skills list, not omitted', async () => {
  const response = await candidatesRequest();
  const { candidates } = await response.json();
  const found = candidates.find((c) => c.id === defaultOnlyEmployee);
  assert.ok(found, 'an Employee with no employee_skills row should still be listed');
  assert.deepStrictEqual(found.skills, []);
});

test('a Departed Employee is not among the candidates', async () => {
  const response = await candidatesRequest();
  const { candidates } = await response.json();
  assert.ok(!candidates.map((c) => c.id).includes(departedEmployee));
});

test('?orgUnitId= narrows to that Org Unit and everything beneath it', async () => {
  const narrowed = await candidatesRequest(`?orgUnitId=${ancestorUnit}`);
  assert.strictEqual(narrowed.status, 200);
  const { candidates } = await narrowed.json();
  const ids = candidates.map((c) => c.id);

  // richEmployee's CURRENT assignment is at grandchildUnit, two levels
  // beneath ancestorUnit — a descendant, so it matches the narrowed list.
  assert.ok(ids.includes(richEmployee));
  // outsideEmployee's assignment is at outsideUnit, a separate root entirely.
  assert.ok(!ids.includes(outsideEmployee));
});

test('an unknown ?orgUnitId= is a 404 and a malformed one is a 400', async () => {
  const unknown = await candidatesRequest('?orgUnitId=999999999');
  assert.strictEqual(unknown.status, 404);
  const unknownBody = await unknown.json();
  assert.strictEqual(unknownBody.message, 'Org Unit not found');

  const malformed = await candidatesRequest('?orgUnitId=not-an-id');
  assert.strictEqual(malformed.status, 400);
  const malformedBody = await malformed.json();
  assert.strictEqual(malformedBody.message, 'orgUnitId must be a valid Org Unit id');
});

test('expiresOn crosses the wire as a calendar date, not a locale-shifted instant', async () => {
  const skillForDate = await insertSkill();
  const employee = await insertEmployee({ firstName: 'Candidate', lastName: 'DateCheck' });
  await insertEmployeeSkill({ employeeId: employee, skillId: skillForDate.id, expiresOn: '2030-03-15' });

  const { candidates } = await (await candidatesRequest()).json();
  const found = candidates.find((c) => c.id === employee);
  const heldSkill = found.skills.find((s) => s.skill.id === skillForDate.id);
  assert.strictEqual(heldSkill.expiresOn, '2030-03-15');
});

test('any approved Account may read the candidates, with no Grant anywhere', async () => {
  // readerToken is an ordinary approved, active Account with no Grant of any
  // kind (this file's own header) — ADR-0009.
  const response = await candidatesRequest('', readerToken);
  assert.strictEqual(response.status, 200);
});

// ---------------------------------------------------------------------------
// Pass 2 (issue #9, criteria 5 and 6): the write surface — add, edit, mark
// Departed, reinstate — all administrator-only.
//
// Everything above this point is read-only and shares the fixtures built
// once in test.before. The tests below must NOT touch any of those shared
// Employees (richEmployee, outsideEmployee, defaultOnlyEmployee,
// departedEmployee, searchTargetEmployee, searchOtherEmployee) since the
// read tests above depend on their exact state and node:test does not
// guarantee these tests run after them within one process, let alone across
// runs. Every Employee a test below creates is its own, via POST /employees
// (never direct SQL, since the whole point is exercising the new route), and
// is deleted again by that test — accumulated in writeTestEmployeeIds below
// and swept up by the file's one test.after (belt and braces for a failing
// assertion mid-test), rather than by a second test.before/test.after pair:
// node:test runs a root before() registered after the first test() has
// already started immediately and un-awaited, racing rather than queuing
// behind the file's first before() (which is what assigns `pool`), so a
// second pair here would be a genuine bug, not just a style choice — see the
// adminToken setup folded into the file's one test.before, above, for where
// this Account is actually created.
// ---------------------------------------------------------------------------

let adminToken; // an approved, active administrator — the only role that may reach any write route.
const writeTestEmployeeIds = [];

function newEmployeeBody(overrides = {}) {
  return {
    employeeNo: uniqueCode('WEMP'),
    firstName: 'Write',
    lastName: 'Test',
    ...overrides
  };
}

async function createEmployeeRequest(body, token = adminToken) {
  const response = await fetch(`${base}/api/people/employees`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  return response;
}

async function patchEmployeeRequest(id, body, token = adminToken) {
  return fetch(`${base}/api/people/employees/${id}`, {
    method: 'PATCH',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
}

async function departEmployeeRequest(id, body = {}, token = adminToken) {
  return fetch(`${base}/api/people/employees/${id}/departure`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
}

async function reinstateEmployeeRequest(id, token = adminToken) {
  return fetch(`${base}/api/people/employees/${id}/reinstatement`, {
    method: 'POST',
    headers: token
  });
}

// ---------------------------------------------------------------------------
// 10. An administrator adds an Employee; it appears in the list and in its
//     own detail view.
// ---------------------------------------------------------------------------

test('an administrator adds an Employee, and it then appears in the list and in its own detail view', async () => {
  const body = newEmployeeBody({ firstName: 'Grace', lastName: 'Hopper' });
  const response = await createEmployeeRequest(body);
  assert.strictEqual(response.status, 201);
  const { employee } = await response.json();
  writeTestEmployeeIds.push(employee.id);

  assert.strictEqual(employee.employeeNo, body.employeeNo);
  assert.strictEqual(employee.firstName, 'Grace');
  assert.strictEqual(employee.lastName, 'Hopper');
  assert.strictEqual(employee.isActive, true);

  const listResponse = await listEmployeesRequest();
  const { employees } = await listResponse.json();
  assert.ok(employees.map((e) => e.id).includes(employee.id));

  const detailResponse = await fetch(`${base}/api/people/employees/${employee.id}`, { headers: readerToken });
  assert.strictEqual(detailResponse.status, 200);
  const { employee: detail } = await detailResponse.json();
  assert.strictEqual(detail.id, employee.id);
});

// ---------------------------------------------------------------------------
// 11. An administrator edits an existing Employee; editing one field leaves
//     the others intact.
// ---------------------------------------------------------------------------

test('an administrator edits an existing Employee, and an edit of one field leaves the others intact', async () => {
  const createResponse = await createEmployeeRequest(
    newEmployeeBody({ firstName: 'Katherine', lastName: 'Johnson', employmentType: 'temporary' })
  );
  const { employee: created } = await createResponse.json();
  writeTestEmployeeIds.push(created.id);

  const patchResponse = await patchEmployeeRequest(created.id, { lastName: 'Goble' });
  assert.strictEqual(patchResponse.status, 200);
  const { employee: patched } = await patchResponse.json();

  assert.strictEqual(patched.lastName, 'Goble');
  // Untouched fields survive a partial edit.
  assert.strictEqual(patched.firstName, 'Katherine');
  assert.strictEqual(patched.employmentType, 'temporary');
  assert.strictEqual(patched.employeeNo, created.employeeNo);
});

// ---------------------------------------------------------------------------
// 12. A duplicate employeeNo, and a duplicate workEmail differing only in
//     case, are each a 409.
// ---------------------------------------------------------------------------

test('a duplicate employeeNo is a 409', async () => {
  const body = newEmployeeBody();
  const first = await createEmployeeRequest(body);
  const { employee } = await first.json();
  writeTestEmployeeIds.push(employee.id);

  const second = await createEmployeeRequest(newEmployeeBody({ employeeNo: body.employeeNo }));
  assert.strictEqual(second.status, 409);
  const secondBody = await second.json();
  assert.match(secondBody.message, /employee.?no/i);
});

test('a duplicate workEmail, differing only in case, is a 409', async () => {
  const email = `${uniqueCode('dup')}@example.com`;
  const first = await createEmployeeRequest(newEmployeeBody({ workEmail: email }));
  const { employee } = await first.json();
  writeTestEmployeeIds.push(employee.id);

  const second = await createEmployeeRequest(newEmployeeBody({ workEmail: email.toUpperCase() }));
  assert.strictEqual(second.status, 409);
  const secondBody = await second.json();
  assert.match(secondBody.message, /work.?email/i);
});

// ---------------------------------------------------------------------------
// 13. A missing required field, and an invalid employmentType, are each a
//     400.
// ---------------------------------------------------------------------------

test('a missing required field is a 400', async () => {
  const response = await createEmployeeRequest({ employeeNo: uniqueCode('WEMP'), lastName: 'NoFirstName' });
  assert.strictEqual(response.status, 400);
});

test('an invalid employmentType is a 400', async () => {
  const response = await createEmployeeRequest(newEmployeeBody({ employmentType: 'volunteer' }));
  assert.strictEqual(response.status, 400);
});

// ---------------------------------------------------------------------------
// 14. An administrator marks an Employee Departed: absent from the default
//     list, present under ?includeDeparted=true, terminatedOn set.
// ---------------------------------------------------------------------------

test('an administrator marks an Employee as Departed: it leaves the default list, appears under ?includeDeparted=true, and terminatedOn is set', async () => {
  const createResponse = await createEmployeeRequest(newEmployeeBody({ hiredOn: '2020-01-01' }));
  const { employee: created } = await createResponse.json();
  writeTestEmployeeIds.push(created.id);

  const departResponse = await departEmployeeRequest(created.id, { terminatedOn: '2024-06-01' });
  assert.strictEqual(departResponse.status, 200);
  const { employee: departed } = await departResponse.json();
  assert.strictEqual(departed.isActive, false);
  assert.strictEqual(departed.terminatedOn, '2024-06-01');

  const defaultList = await listEmployeesRequest();
  const { employees: defaultEmployees } = await defaultList.json();
  assert.ok(!defaultEmployees.map((e) => e.id).includes(created.id));

  const withDeparted = await listEmployeesRequest('?includeDeparted=true');
  const { employees: withDepartedEmployees } = await withDeparted.json();
  assert.ok(withDepartedEmployees.map((e) => e.id).includes(created.id));
});

// ---------------------------------------------------------------------------
// 15. An administrator reinstates a Departed Employee: back in the default
//     list, terminatedOn cleared to null.
// ---------------------------------------------------------------------------

test('an administrator reinstates a Departed Employee: it returns to the default list and terminatedOn is back to null', async () => {
  const createResponse = await createEmployeeRequest(newEmployeeBody({ hiredOn: '2020-01-01' }));
  const { employee: created } = await createResponse.json();
  writeTestEmployeeIds.push(created.id);

  await departEmployeeRequest(created.id, { terminatedOn: '2024-06-01' });

  const reinstateResponse = await reinstateEmployeeRequest(created.id);
  assert.strictEqual(reinstateResponse.status, 200);
  const { employee: reinstated } = await reinstateResponse.json();
  assert.strictEqual(reinstated.isActive, true);
  assert.strictEqual(reinstated.terminatedOn, null);

  const defaultList = await listEmployeesRequest();
  const { employees: defaultEmployees } = await defaultList.json();
  assert.ok(defaultEmployees.map((e) => e.id).includes(created.id));
});

// ---------------------------------------------------------------------------
// 16. A departure date before the hire date is a clean 400, not a 500
//     (employees_dates_valid).
// ---------------------------------------------------------------------------

test('a departure date before the hire date is a clean 400, not a 500', async () => {
  const createResponse = await createEmployeeRequest(newEmployeeBody({ hiredOn: '2024-01-01' }));
  const { employee: created } = await createResponse.json();
  writeTestEmployeeIds.push(created.id);

  const departResponse = await departEmployeeRequest(created.id, { terminatedOn: '2020-01-01' });
  assert.strictEqual(departResponse.status, 400);
});

// ---------------------------------------------------------------------------
// 17. A non-administrator (an approved, active Member) gets 403 from every
//     write route — criterion 7's "cannot edit it", the most important test
//     in this pass. Asserted against each of the four routes, not just one.
// ---------------------------------------------------------------------------

test('a non-administrator (an approved, active Member) gets 403 from all four write routes', async () => {
  const createResponse = await createEmployeeRequest(newEmployeeBody(), memberToken);
  assert.strictEqual(createResponse.status, 403);

  // richEmployee is a shared read fixture, but a 403 refusal never reaches
  // the database write path at all, so exercising the other three routes
  // against it does not mutate it.
  const patchResponse = await patchEmployeeRequest(richEmployee, { lastName: 'ShouldNotChange' }, memberToken);
  assert.strictEqual(patchResponse.status, 403);

  const departResponse = await departEmployeeRequest(richEmployee, {}, memberToken);
  assert.strictEqual(departResponse.status, 403);

  const reinstateResponse = await reinstateEmployeeRequest(richEmployee, memberToken);
  assert.strictEqual(reinstateResponse.status, 403);
});

// ---------------------------------------------------------------------------
// 18. An Employee id that does not exist is a 404 on edit, departure and
//     reinstatement.
// ---------------------------------------------------------------------------

test('an Employee id that does not exist is a 404 on edit, departure and reinstatement', async () => {
  const missingId = '999999999';

  const patchResponse = await patchEmployeeRequest(missingId, { lastName: 'Nobody' });
  assert.strictEqual(patchResponse.status, 404);

  const departResponse = await departEmployeeRequest(missingId);
  assert.strictEqual(departResponse.status, 404);

  const reinstateResponse = await reinstateEmployeeRequest(missingId);
  assert.strictEqual(reinstateResponse.status, 404);
});
