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
 * There are no HTTP endpoints yet for `skills` or `employee_skills` — issue
 * #11 owns that write surface later — so those fixtures are still inserted
 * directly via SQL (`pool.query`). `job_roles` and `employee_assignments` DO
 * have HTTP endpoints now (issue #10, sections 19 onward, below), and
 * `employees` has had one since issue #9 (section 10 onward). The shared
 * fixtures built once in test.before — sites, Org Units, the job role, the
 * skill, and every Employee sections 1-9 read — still go in directly via SQL
 * regardless: those sections' assertions depend on the fixtures' exact,
 * stable shape, and routing them through the write surface this file itself
 * is exercising would make a fixture failure indistinguishable from a test
 * failure. Every Employee, job role and assignment a section 10-onward test
 * needs is instead created through the real route it means to exercise
 * (POST /employees, POST /job-roles, POST /employees/:id/assignments), never
 * direct SQL, and cleaned up by that same test.
 *
 * Every route this file exercises sits behind `authenticate` + `requireActive`
 * only — no Org Unit scope, no grants needed anywhere below (ADR-0009: the
 * directory is deliberately not Org-Unit-scoped), which is also why this
 * file never inserts an `app_user_org_units` row. Issue #10's write routes
 * (POST /job-roles, PATCH /job-roles/:id, POST /employees/:id/assignments)
 * are administrator-only instead (same reasoning as issue #9's own write
 * surface — see directory-routes.js's own header).
 *
 * Needs a database with every migration applied. Set DATABASE_URL first —
 * see the README's Tests section.
 */

const test = require('node:test');
const assert = require('node:assert');
const { createTestJwks } = require('../helpers/jwks');

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

  // Belt and braces: any Employee a write-surface test (issue #9's own pass,
  // or issue #10's assignment tests below) failed to clean up itself is
  // still removed here, so a failing assertion mid-test never leaks a row
  // into the next run's UNIQUE-constraint namespace. This must happen BEFORE
  // job_roles/org_units/sites are deleted below: an employee created by an
  // issue #10 test may still have an employee_assignments row naming one of
  // this file's own job roles or Org Units, and employee_assignments has no
  // ON DELETE on job_role_id/org_unit_id (only on employee_id, which cascades
  // employee_assignments away the moment the employee itself is deleted here).
  // Deleting job_roles/org_units first would hit that FK and fail the whole
  // hook.
  if (writeTestEmployeeIds.length > 0) {
    await pool.query('DELETE FROM employees WHERE id = ANY($1)', [writeTestEmployeeIds]);
  }

  await pool.query('DELETE FROM skills WHERE id = ANY($1)', [insertedSkillIds]);
  await pool.query('DELETE FROM job_roles WHERE id = ANY($1)', [insertedJobRoleIds]);
  await pool.query('DELETE FROM org_units WHERE id = ANY($1)', [insertedOrgUnitIds]);
  await pool.query('DELETE FROM sites WHERE id = ANY($1)', [insertedSiteIds]);

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

// ---------------------------------------------------------------------------
// Issue #10 (job roles and Org Unit assignments) — administrator-only writes,
// same reasoning as issue #9's own write surface (see directory-routes.js's
// own header). As with the section above, every Employee, job role and
// assignment a test below creates is its own — never a shared fixture from
// test.before — and is cleaned up via writeTestEmployeeIds/insertedJobRoleIds/
// insertedOrgUnitIds/insertedSiteIds, which this file's one test.after
// already sweeps.
// ---------------------------------------------------------------------------

async function createJobRoleRequest(body, token = adminToken) {
  return fetch(`${base}/api/people/job-roles`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
}

async function patchJobRoleRequest(id, body, token = adminToken) {
  return fetch(`${base}/api/people/job-roles/${id}`, {
    method: 'PATCH',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
}

async function assignEmployeeRequest(employeeId, body, token = adminToken) {
  return fetch(`${base}/api/people/employees/${employeeId}/assignments`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
}

async function getEmployeeDetailRequest(id, token = readerToken) {
  return fetch(`${base}/api/people/employees/${id}`, { headers: token });
}

async function newTestEmployee(overrides = {}) {
  const response = await createEmployeeRequest(newEmployeeBody(overrides));
  const { employee } = await response.json();
  writeTestEmployeeIds.push(employee.id);
  return employee.id;
}

// A second Site and a root Org Unit within it, for the one test that needs
// to prove a job role is usable across two different Sites (criterion 1) —
// none of the shared test.before fixtures are at a second Site, so this
// builds its own, the same direct-SQL device test.before itself uses.
async function insertSecondSiteOrgUnit() {
  const { rows: [siteRow] } = await pool.query(
    `INSERT INTO sites (code, name, timezone) VALUES ($1, 'Directory Test Second Site', 'Asia/Ho_Chi_Minh') RETURNING id`,
    [uniqueCode('ST2')]
  );
  insertedSiteIds.push(siteRow.id);

  const { rows: [orgUnitRow] } = await pool.query(
    `INSERT INTO org_units (site_id, code, name, unit_type) VALUES ($1, $2, 'Second Site Area', 'area') RETURNING id`,
    [siteRow.id, uniqueCode('OU2')]
  );
  insertedOrgUnitIds.push(orgUnitRow.id);
  return orgUnitRow.id;
}

// ---------------------------------------------------------------------------
// 19. Job roles are defined once and shared by every Site (criterion 1) —
//     the same job role id is usable for Employees at two different Sites.
// ---------------------------------------------------------------------------

test('a job role is created once and is visible when assigning an Employee at any Site', async () => {
  const roleResponse = await createJobRoleRequest({ code: uniqueCode('JR'), name: 'Shared Fitter' });
  assert.strictEqual(roleResponse.status, 201);
  const { jobRole: sharedRole } = await roleResponse.json();
  insertedJobRoleIds.push(sharedRole.id);

  const secondSiteOrgUnit = await insertSecondSiteOrgUnit();

  const employeeAtFirstSite = await newTestEmployee();
  const employeeAtSecondSite = await newTestEmployee();

  const firstResponse = await assignEmployeeRequest(employeeAtFirstSite, {
    orgUnitId: grandchildUnit,
    jobRoleId: sharedRole.id
  });
  assert.strictEqual(firstResponse.status, 201);
  const { assignment: firstAssignment } = await firstResponse.json();
  assert.strictEqual(firstAssignment.jobRole.id, sharedRole.id);

  const secondResponse = await assignEmployeeRequest(employeeAtSecondSite, {
    orgUnitId: secondSiteOrgUnit,
    jobRoleId: sharedRole.id
  });
  assert.strictEqual(secondResponse.status, 201);
  const { assignment: secondAssignment } = await secondResponse.json();
  assert.strictEqual(secondAssignment.jobRole.id, sharedRole.id);
});

// ---------------------------------------------------------------------------
// 20. An Employee can be assigned to an Org Unit, and it shows on their
//     record (criterion 2).
// ---------------------------------------------------------------------------

test('an administrator assigns an Employee to an Org Unit, and it shows on their record', async () => {
  const employeeId = await newTestEmployee();

  const response = await assignEmployeeRequest(employeeId, { orgUnitId: grandchildUnit });
  assert.strictEqual(response.status, 201);
  const { assignment } = await response.json();
  assert.strictEqual(assignment.orgUnit.id, grandchildUnit);

  const detailResponse = await getEmployeeDetailRequest(employeeId);
  const { employee } = await detailResponse.json();
  assert.strictEqual(employee.assignments.length, 1);
  assert.strictEqual(employee.assignments[0].orgUnit.id, grandchildUnit);
});

// ---------------------------------------------------------------------------
// 21. A transfer records a new assignment and leaves the previous one intact
//     (criterion 3): the old row keeps its own effective_from and gains an
//     effective_to equal to the new assignment's effective_from; the new one
//     is current.
// ---------------------------------------------------------------------------

test('a transfer records a new assignment and leaves the previous one intact', async () => {
  const employeeId = await newTestEmployee();

  const firstResponse = await assignEmployeeRequest(employeeId, {
    orgUnitId: ancestorUnit,
    effectiveFrom: '2020-01-01'
  });
  assert.strictEqual(firstResponse.status, 201);

  const transferResponse = await assignEmployeeRequest(employeeId, {
    orgUnitId: grandchildUnit,
    effectiveFrom: '2021-06-01'
  });
  assert.strictEqual(transferResponse.status, 201);
  const { assignment: transfer } = await transferResponse.json();
  assert.strictEqual(transfer.effectiveFrom, '2021-06-01');
  assert.strictEqual(transfer.effectiveTo, null);
  assert.strictEqual(transfer.orgUnit.id, grandchildUnit);

  const detailResponse = await getEmployeeDetailRequest(employeeId);
  const { employee } = await detailResponse.json();
  assert.strictEqual(employee.assignments.length, 2);

  // Newest first: the transfer, then the original, now closed.
  assert.strictEqual(employee.assignments[0].orgUnit.id, grandchildUnit);
  assert.strictEqual(employee.assignments[0].effectiveFrom, '2021-06-01');
  assert.strictEqual(employee.assignments[0].effectiveTo, null);

  assert.strictEqual(employee.assignments[1].orgUnit.id, ancestorUnit);
  assert.strictEqual(employee.assignments[1].effectiveFrom, '2020-01-01');
  assert.strictEqual(employee.assignments[1].effectiveTo, '2021-06-01');
});

// ---------------------------------------------------------------------------
// 22. The directory can be filtered by job role, and an Employee holding a
//     different role is excluded (criterion 4).
// ---------------------------------------------------------------------------

test('the directory can be filtered by job role, and an Employee holding a different role is excluded', async () => {
  const roleAResponse = await createJobRoleRequest({ code: uniqueCode('JR'), name: 'Filter Role A' });
  const { jobRole: roleA } = await roleAResponse.json();
  insertedJobRoleIds.push(roleA.id);

  const roleBResponse = await createJobRoleRequest({ code: uniqueCode('JR'), name: 'Filter Role B' });
  const { jobRole: roleB } = await roleBResponse.json();
  insertedJobRoleIds.push(roleB.id);

  const employeeWithRoleA = await newTestEmployee();
  const employeeWithRoleB = await newTestEmployee();

  await assignEmployeeRequest(employeeWithRoleA, { orgUnitId: grandchildUnit, jobRoleId: roleA.id });
  await assignEmployeeRequest(employeeWithRoleB, { orgUnitId: grandchildUnit, jobRoleId: roleB.id });

  const response = await listEmployeesRequest(`?jobRoleId=${roleA.id}`);
  assert.strictEqual(response.status, 200);
  const { employees } = await response.json();
  const ids = employees.map((e) => e.id);

  assert.ok(ids.includes(employeeWithRoleA), 'an Employee currently holding the filtered role should match');
  assert.ok(!ids.includes(employeeWithRoleB), 'an Employee holding a different role should not match');
});

// ---------------------------------------------------------------------------
// 23. An Employee with no current assignment does not match a job-role
//     filter — there is no default job role to fall back to.
// ---------------------------------------------------------------------------

test('an Employee with no current assignment does not match a job-role filter', async () => {
  const roleResponse = await createJobRoleRequest({ code: uniqueCode('JR'), name: 'Unassigned Filter Role' });
  const { jobRole: role } = await roleResponse.json();
  insertedJobRoleIds.push(role.id);

  const unassignedEmployee = await newTestEmployee();

  const response = await listEmployeesRequest(`?jobRoleId=${role.id}`);
  assert.strictEqual(response.status, 200);
  const { employees } = await response.json();
  assert.ok(!employees.map((e) => e.id).includes(unassignedEmployee));
});

// ---------------------------------------------------------------------------
// 24. An Employee's assignment history is visible on their record, newest
//     first, each with its Org Unit and job role named (criterion 5 — this
//     verifies getEmployeeDetail's existing behaviour and needed no new
//     production code; see the write-up in the final report).
// ---------------------------------------------------------------------------

test("an Employee's assignment history is visible on their record, newest first, each with its Org Unit and job role named", async () => {
  const roleResponse = await createJobRoleRequest({ code: uniqueCode('JR'), name: 'History Role' });
  const { jobRole: role } = await roleResponse.json();
  insertedJobRoleIds.push(role.id);

  const employeeId = await newTestEmployee();

  await assignEmployeeRequest(employeeId, { orgUnitId: ancestorUnit, effectiveFrom: '2019-01-01' });
  await assignEmployeeRequest(employeeId, {
    orgUnitId: grandchildUnit,
    jobRoleId: role.id,
    effectiveFrom: '2020-01-01'
  });

  const detailResponse = await getEmployeeDetailRequest(employeeId);
  assert.strictEqual(detailResponse.status, 200);
  const { employee } = await detailResponse.json();

  assert.strictEqual(employee.assignments.length, 2);
  assert.strictEqual(employee.assignments[0].orgUnit.id, grandchildUnit);
  assert.strictEqual(employee.assignments[0].jobRole.id, role.id);
  assert.strictEqual(employee.assignments[0].jobRole.code, role.code);
  assert.strictEqual(employee.assignments[1].orgUnit.id, ancestorUnit);
  assert.strictEqual(employee.assignments[1].jobRole, null);
});

// ---------------------------------------------------------------------------
// 25. A non-administrator gets 403 from POST /job-roles, PATCH
//     /job-roles/:id and POST /employees/:id/assignments.
// ---------------------------------------------------------------------------

test('a non-administrator gets 403 from POST /job-roles, PATCH /job-roles/:id and POST /employees/:id/assignments', async () => {
  const createResponse = await createJobRoleRequest({ code: uniqueCode('JR'), name: 'Should Not Exist' }, memberToken);
  assert.strictEqual(createResponse.status, 403);

  // jobRole is a shared read fixture, but a 403 refusal never reaches the
  // database write path, so this never mutates it.
  const patchResponse = await patchJobRoleRequest(jobRole.id, { isActive: false }, memberToken);
  assert.strictEqual(patchResponse.status, 403);

  // richEmployee is a shared read fixture; same reasoning.
  const assignResponse = await assignEmployeeRequest(richEmployee, { orgUnitId: grandchildUnit }, memberToken);
  assert.strictEqual(assignResponse.status, 403);
});

// ---------------------------------------------------------------------------
// 26. A duplicate job role code is a 409.
// ---------------------------------------------------------------------------

test('a duplicate job role code is a 409', async () => {
  const code = uniqueCode('JR');
  const first = await createJobRoleRequest({ code, name: 'First Of Its Code' });
  assert.strictEqual(first.status, 201);
  const { jobRole: firstRole } = await first.json();
  insertedJobRoleIds.push(firstRole.id);

  const second = await createJobRoleRequest({ code, name: 'Second Of Its Code' });
  assert.strictEqual(second.status, 409);
  const secondBody = await second.json();
  assert.match(secondBody.message, /job role/i);
});

// ---------------------------------------------------------------------------
// 27. A backdated assignment overlapping existing history is a 409, not a
//     500 (employee_assignments_no_overlap, SQLSTATE 23P01).
// ---------------------------------------------------------------------------

test('a backdated assignment overlapping existing history is a 409, not a 500', async () => {
  const employeeId = await newTestEmployee();

  const firstResponse = await assignEmployeeRequest(employeeId, {
    orgUnitId: grandchildUnit,
    effectiveFrom: '2020-01-01'
  });
  assert.strictEqual(firstResponse.status, 201);

  // Backdated well before the existing (still open-ended) assignment began —
  // this does not qualify as "a current assignment as of effectiveFrom" (the
  // 2020 row starts after it), so assignEmployee inserts outright rather than
  // closing anything first, and the two open-ended ranges collide.
  const overlapResponse = await assignEmployeeRequest(employeeId, {
    orgUnitId: ancestorUnit,
    effectiveFrom: '2019-06-01'
  });
  assert.strictEqual(overlapResponse.status, 409);
  const overlapBody = await overlapResponse.json();
  assert.match(overlapBody.message, /assignment/i);
});

// ---------------------------------------------------------------------------
// 28. Assigning to an Org Unit that does not exist, or an Employee that does
//     not exist, is a 404.
// ---------------------------------------------------------------------------

test('assigning to an Org Unit that does not exist, or an Employee that does not exist, is a 404', async () => {
  const employeeId = await newTestEmployee();
  const missingId = '999999999';

  const missingOrgUnitResponse = await assignEmployeeRequest(employeeId, { orgUnitId: missingId });
  assert.strictEqual(missingOrgUnitResponse.status, 404);

  const missingEmployeeResponse = await assignEmployeeRequest(missingId, { orgUnitId: grandchildUnit });
  assert.strictEqual(missingEmployeeResponse.status, 404);
});

// ---------------------------------------------------------------------------
// 29. Assigning with a jobRoleId that does not exist is a 404, the same as
//     an unknown orgUnitId — not the unmapped foreign-key 500 a review of
//     this ticket's first pass caught.
// ---------------------------------------------------------------------------

test('assigning with a jobRoleId that does not exist is a 404', async () => {
  const employeeId = await newTestEmployee();
  const missingId = '999999999';

  const response = await assignEmployeeRequest(employeeId, { orgUnitId: grandchildUnit, jobRoleId: missingId });
  assert.strictEqual(response.status, 404);
});

// ---------------------------------------------------------------------------
// 30. Assigning twice with the same effectiveFrom is a clean 400 (the
//     equal-bounds guard), not left to fall through to Postgres's own
//     employee_assignments_range_valid CHECK violation.
// ---------------------------------------------------------------------------

test('assigning again with the same effectiveFrom as the current assignment is a 400, not a 500', async () => {
  const employeeId = await newTestEmployee();

  const firstResponse = await assignEmployeeRequest(employeeId, {
    orgUnitId: ancestorUnit,
    effectiveFrom: '2022-01-01'
  });
  assert.strictEqual(firstResponse.status, 201);

  const sameDateResponse = await assignEmployeeRequest(employeeId, {
    orgUnitId: grandchildUnit,
    effectiveFrom: '2022-01-01'
  });
  assert.strictEqual(sameDateResponse.status, 400);
  const body = await sameDateResponse.json();
  assert.match(body.message, /current assignment began/i);
});

// ---------------------------------------------------------------------------
// 31. A postdated (future-effective) transfer closes the currently-open
//     assignment at that future date, but the record still reflects the OLD
//     assignment as current today, and the NEW one as not yet started. This
//     is the "current as of effectiveFrom" rule doing real work: a naive
//     "whichever row has no effective_to, or was inserted most recently, is
//     current" implementation would get this wrong.
// ---------------------------------------------------------------------------

test('a postdated (future-dated) transfer closes the open assignment at that future date, without changing who is current today', async () => {
  const employeeId = await newTestEmployee();
  const futureDate = '2099-01-01'; // far enough out to never collide with CURRENT_DATE.

  const openResponse = await assignEmployeeRequest(employeeId, {
    orgUnitId: ancestorUnit,
    effectiveFrom: '2020-01-01'
  });
  assert.strictEqual(openResponse.status, 201);

  const futureResponse = await assignEmployeeRequest(employeeId, {
    orgUnitId: grandchildUnit,
    effectiveFrom: futureDate
  });
  assert.strictEqual(futureResponse.status, 201);
  const { assignment: futureAssignment } = await futureResponse.json();
  assert.strictEqual(futureAssignment.effectiveFrom, futureDate);
  assert.strictEqual(futureAssignment.effectiveTo, null);

  const detailResponse = await getEmployeeDetailRequest(employeeId);
  const { employee } = await detailResponse.json();
  assert.strictEqual(employee.assignments.length, 2);
  // Newest effective_from first — the future row — but its effective_to is
  // still null (it is the new open end of the Employee's history); the old
  // row is now closed exactly at the future row's own effectiveFrom.
  assert.strictEqual(employee.assignments[0].orgUnit.id, grandchildUnit);
  assert.strictEqual(employee.assignments[0].effectiveTo, null);
  assert.strictEqual(employee.assignments[1].orgUnit.id, ancestorUnit);
  assert.strictEqual(employee.assignments[1].effectiveTo, futureDate);

  // As of TODAY, the old (ancestorUnit) assignment is still the current one
  // — its effective_to is in the future — and the new (grandchildUnit) one
  // has not started yet. Checked through the same "current" rule the Org
  // Unit filter uses, not by reading effectiveFrom/effectiveTo directly.
  const stillAtAncestor = await listEmployeesRequest(`?orgUnitId=${ancestorUnit}`);
  const { employees: stillAtAncestorList } = await stillAtAncestor.json();
  assert.ok(
    stillAtAncestorList.map((e) => e.id).includes(employeeId),
    'the Employee should still resolve as currently at the old Org Unit today'
  );

  const notYetAtGrandchild = await listEmployeesRequest(`?orgUnitId=${grandchildUnit}`);
  const { employees: notYetAtGrandchildList } = await notYetAtGrandchild.json();
  assert.ok(
    !notYetAtGrandchildList.map((e) => e.id).includes(employeeId),
    'the Employee should not yet resolve as currently at the new Org Unit before the future date arrives'
  );
});

// ---------------------------------------------------------------------------
// 32. effectiveFrom defaults to today (CURRENT_DATE) when omitted — checked
//     against Postgres's own clock, not a JS Date computed in this test, so
//     a timezone slip in the production toDateString(today) conversion would
//     actually be caught rather than incidentally matched.
// ---------------------------------------------------------------------------

async function currentDateStringFromDatabase() {
  const { rows: [{ today }] } = await pool.query('SELECT CURRENT_DATE AS today');
  const y = today.getFullYear();
  const m = String(today.getMonth() + 1).padStart(2, '0');
  const d = String(today.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

test('omitting effectiveFrom defaults the new assignment to today', async () => {
  const employeeId = await newTestEmployee();
  const expectedToday = await currentDateStringFromDatabase();

  const response = await assignEmployeeRequest(employeeId, { orgUnitId: grandchildUnit });
  assert.strictEqual(response.status, 201);
  const { assignment } = await response.json();
  assert.strictEqual(assignment.effectiveFrom, expectedToday);
});

// ---------------------------------------------------------------------------
// 33. GET /job-roles lists a created job role.
// ---------------------------------------------------------------------------

async function listJobRolesRequest(query = '', token = readerToken) {
  return fetch(`${base}/api/people/job-roles${query}`, { headers: token });
}

test('GET /job-roles lists a job role once it is created', async () => {
  const createResponse = await createJobRoleRequest({ code: uniqueCode('JR'), name: 'Catalogue Listing Role' });
  assert.strictEqual(createResponse.status, 201);
  const { jobRole: created } = await createResponse.json();
  insertedJobRoleIds.push(created.id);

  const listResponse = await listJobRolesRequest();
  assert.strictEqual(listResponse.status, 200);
  const { jobRoles } = await listResponse.json();
  assert.ok(jobRoles.map((r) => r.id).includes(created.id));
});

// ---------------------------------------------------------------------------
// 34. Deactivating a job role removes it from the default listing, and it
//     still shows under ?includeInactive=true — the same shape as an Org
//     Unit's own deactivation.
// ---------------------------------------------------------------------------

test('deactivating a job role removes it from the default listing, and includeInactive=true still shows it', async () => {
  const createResponse = await createJobRoleRequest({ code: uniqueCode('JR'), name: 'Soon Deactivated Role' });
  const { jobRole: created } = await createResponse.json();
  insertedJobRoleIds.push(created.id);

  const patchResponse = await patchJobRoleRequest(created.id, { isActive: false });
  assert.strictEqual(patchResponse.status, 200);
  const { jobRole: patched } = await patchResponse.json();
  assert.strictEqual(patched.isActive, false);

  const defaultList = await listJobRolesRequest();
  const { jobRoles: defaultJobRoles } = await defaultList.json();
  assert.ok(!defaultJobRoles.map((r) => r.id).includes(created.id));

  const withInactive = await listJobRolesRequest('?includeInactive=true');
  const { jobRoles: withInactiveJobRoles } = await withInactive.json();
  assert.ok(withInactiveJobRoles.map((r) => r.id).includes(created.id));
});
