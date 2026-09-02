/*
 * Job roles and Org Unit assignments (issue #10, CONTEXT.md's Employee and
 * Org Unit definitions), against a real database and a real (locally issued)
 * JWKS — the same seam as directory.test.js and plant.test.js (see either
 * file's own header, and the README's Tests section).
 *
 * Unlike directory.test.js, this file DOES need `app_user_org_units` rows:
 * the assignment write route (POST /employees/:id/assignments) is scoped to
 * the destination Org Unit (ADR-0010), so exercising it needs callers with a
 * write grant, a read-only grant, and a grant elsewhere in the tree.
 *
 * This file does not truncate `app_users`, `sites`, `org_units`, `employees`
 * or `job_roles`: all are shared with the other integration files, and
 * `npm run test:integration` runs every file with `--test-concurrency=1`, so
 * a truncate here would still corrupt whichever file ran first. Instead this
 * file inserts its own rows under a `process.pid`-unique `uniqueCode`, the
 * same device directory.test.js/plant.test.js use, for every UNIQUE
 * constraint value it touches: `employees.employee_no`, `job_roles.code`,
 * `sites.code`, `(site_id, code)` on `org_units`, and `external_subject` on
 * `app_users`. Every row inserted — across `app_users`, `app_user_org_units`,
 * `sites`, `org_units`, `job_roles`, `employees` and `employee_assignments` —
 * is deleted again in `test.after()`, in FK-safe order.
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

const insertedAccountIds = [];
const insertedSiteIds = [];
const insertedOrgUnitIds = [];
const insertedJobRoleIds = [];
const insertedEmployeeIds = [];

let codeCounter = 0;
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

async function insertAccount({ role = 'operator', isActive = true, approvalStatus = 'approved' } = {}) {
  const subject = uniqueCode('acct');
  const { rows: [row] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status)
     VALUES ($1, 'Assignment Test Account', $2, $3, $4, $5) RETURNING id`,
    [`${subject}@example.com`, role, subject, isActive, approvalStatus]
  );
  insertedAccountIds.push(row.id);
  return { id: row.id, token: await authHeader(subject) };
}

async function insertSite() {
  const { rows: [row] } = await pool.query(
    `INSERT INTO sites (code, name, timezone) VALUES ($1, 'Assignment Test Site', 'Asia/Ho_Chi_Minh') RETURNING id`,
    [uniqueCode('ST')]
  );
  insertedSiteIds.push(row.id);
  return row.id;
}

async function insertOrgUnit(siteId, { parentId = null, unitType = 'area', name = 'Assignment Test Org Unit' } = {}) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, $2, $3, $4, $5) RETURNING id`,
    [siteId, parentId, uniqueCode('OU'), name, unitType]
  );
  insertedOrgUnitIds.push(row.id);
  return row.id;
}

async function insertGrant({ accountId, orgUnitId, canWrite }) {
  await pool.query(
    `INSERT INTO app_user_org_units (app_user_id, org_unit_id, can_write) VALUES ($1, $2, $3)`,
    [accountId, orgUnitId, canWrite]
  );
}

async function insertJobRole(name = 'Assignment Test Fitter') {
  const { rows: [row] } = await pool.query(
    `INSERT INTO job_roles (code, name) VALUES ($1, $2) RETURNING id, code, name`,
    [uniqueCode('JR'), name]
  );
  insertedJobRoleIds.push(row.id);
  return row;
}

async function insertEmployee({ firstName = 'Assign', lastName = 'Test', isActive = true } = {}) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO employees (employee_no, first_name, last_name, is_active)
     VALUES ($1, $2, $3, $4) RETURNING id`,
    [uniqueCode('EMP'), firstName, lastName, isActive]
  );
  insertedEmployeeIds.push(row.id);
  return row.id;
}

// A fixture assignment inserted directly, bypassing the route under test —
// used only to set up a PRE-EXISTING open assignment for the same-day and
// backdated-overlap conflict tests, which is state the route itself cannot
// produce on its own without already exercising the very path being tested.
async function insertRawAssignment({ employeeId, orgUnitId, jobRoleId = null, effectiveFrom, effectiveTo = null }) {
  await pool.query(
    `INSERT INTO employee_assignments (employee_id, org_unit_id, job_role_id, effective_from, effective_to)
     VALUES ($1, $2, $3, COALESCE($4::date, CURRENT_DATE), $5)`,
    [employeeId, orgUnitId, jobRoleId, effectiveFrom ?? null, effectiveTo]
  );
}

let adminAccount; // administrator, no grants — canAct short-circuits true.
let readerAccount; // approved, active, non-admin, no grants — the directory's own "any approved Account" caller.

let scopeSite;
let scopeUnit; // the destination Org Unit write/read grants target directly.
let elsewhereUnit; // a separate root at scopeSite, not an ancestor or descendant of scopeUnit.
let writeGrantAccount; // can_write = TRUE on scopeUnit.
let readGrantAccount; // can_write = FALSE on scopeUnit.
let elsewhereGrantAccount; // can_write = TRUE on elsewhereUnit only.

let sharedRole; // job role used across criterion 1/2/3 fixtures.
let filterRole; // job role used only by the criterion-4 (filter) fixtures.

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

  adminAccount = await insertAccount({ role: 'admin' });
  readerAccount = await insertAccount();

  scopeSite = await insertSite();
  scopeUnit = await insertOrgUnit(scopeSite, { name: 'Scope Unit' });
  elsewhereUnit = await insertOrgUnit(scopeSite, { name: 'Elsewhere Unit' });

  writeGrantAccount = await insertAccount();
  await insertGrant({ accountId: writeGrantAccount.id, orgUnitId: scopeUnit, canWrite: true });

  readGrantAccount = await insertAccount();
  await insertGrant({ accountId: readGrantAccount.id, orgUnitId: scopeUnit, canWrite: false });

  elsewhereGrantAccount = await insertAccount();
  await insertGrant({ accountId: elsewhereGrantAccount.id, orgUnitId: elsewhereUnit, canWrite: true });

  sharedRole = await insertJobRole('Assignment Test Fitter');
  filterRole = await insertJobRole('Assignment Test Millwright');
});

test.after(async () => {
  await pool.query('DELETE FROM employee_assignments WHERE employee_id = ANY($1)', [insertedEmployeeIds]);
  await pool.query('DELETE FROM app_user_org_units WHERE app_user_id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM app_users WHERE id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM employees WHERE id = ANY($1)', [insertedEmployeeIds]);
  await pool.query('DELETE FROM job_roles WHERE id = ANY($1)', [insertedJobRoleIds]);
  await pool.query('DELETE FROM org_units WHERE id = ANY($1)', [insertedOrgUnitIds]);
  await pool.query('DELETE FROM sites WHERE id = ANY($1)', [insertedSiteIds]);

  await new Promise((resolve) => server.close(resolve));
  await closePool();
  await jwks.close();
});

// ---------------------------------------------------------------------------
// Requests
// ---------------------------------------------------------------------------

async function listJobRolesRequest(query = '', token = readerAccount.token) {
  return fetch(`${base}/api/people/job-roles${query}`, { headers: token });
}

async function createJobRoleRequest(body, token = adminAccount.token) {
  return fetch(`${base}/api/people/job-roles`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
}

async function patchJobRoleRequest(id, body, token = adminAccount.token) {
  return fetch(`${base}/api/people/job-roles/${id}`, {
    method: 'PATCH',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
}

async function createAssignmentRequest(employeeId, body, token = adminAccount.token) {
  return fetch(`${base}/api/people/employees/${employeeId}/assignments`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
}

async function getEmployeeDetail(employeeId, token = adminAccount.token) {
  const response = await fetch(`${base}/api/people/employees/${employeeId}`, { headers: token });
  return { response, body: await response.json() };
}

async function listEmployeesRequest(query = '', token = readerAccount.token) {
  return fetch(`${base}/api/people/employees${query}`, { headers: token });
}

// ---------------------------------------------------------------------------
// 401s: every new route, unauthenticated.
// ---------------------------------------------------------------------------

test('every new route is refused with no bearer token', async () => {
  const employeeId = await insertEmployee();

  assert.strictEqual((await fetch(`${base}/api/people/job-roles`)).status, 401);
  assert.strictEqual(
    (await fetch(`${base}/api/people/job-roles`, { method: 'POST' })).status,
    401
  );
  assert.strictEqual(
    (await fetch(`${base}/api/people/job-roles/1`, { method: 'PATCH' })).status,
    401
  );
  assert.strictEqual(
    (await fetch(`${base}/api/people/employees/${employeeId}/assignments`, { method: 'POST' })).status,
    401
  );
});

// ---------------------------------------------------------------------------
// A pending/inactive Account is refused the same way every other route
// behind requireActive refuses one (matches directory.test.js/plant.test.js).
// ---------------------------------------------------------------------------

test('a pending Account gets 403 (pending_approval) from GET /job-roles', async () => {
  const pending = await insertAccount({ isActive: false, approvalStatus: 'pending' });
  const response = await listJobRolesRequest('', pending.token);
  assert.strictEqual(response.status, 403);
  const body = await response.json();
  assert.strictEqual(body.status, 'pending_approval');
});

// ---------------------------------------------------------------------------
// Job role catalogue: create, list, duplicate, missing field, PATCH.
// ---------------------------------------------------------------------------

test('a non-admin gets 403 from POST and PATCH /job-roles', async () => {
  const createResponse = await createJobRoleRequest({ code: uniqueCode('JR'), name: 'x' }, readerAccount.token);
  assert.strictEqual(createResponse.status, 403);

  const patchResponse = await patchJobRoleRequest(sharedRole.id, { name: 'y' }, readerAccount.token);
  assert.strictEqual(patchResponse.status, 403);
});

test('any approved Account (not just an admin) can GET /job-roles', async () => {
  const response = await listJobRolesRequest('', readerAccount.token);
  assert.strictEqual(response.status, 200);
  const { jobRoles } = await response.json();
  assert.ok(Array.isArray(jobRoles));
});

test('an administrator creates a job role, and it appears in the default (active-only) list', async () => {
  const code = uniqueCode('JR');
  const response = await createJobRoleRequest({ code, name: 'Assignment Test Welder' });
  assert.strictEqual(response.status, 201);
  const { jobRole } = await response.json();
  insertedJobRoleIds.push(jobRole.id);

  assert.strictEqual(jobRole.code, code);
  assert.strictEqual(jobRole.name, 'Assignment Test Welder');
  assert.strictEqual(jobRole.isActive, true);

  const listResponse = await listJobRolesRequest();
  const { jobRoles } = await listResponse.json();
  assert.ok(jobRoles.map((jr) => jr.id).includes(jobRole.id));
});

test('a duplicate job role code is a 409 naming code', async () => {
  const created = await (await createJobRoleRequest({ code: uniqueCode('JR'), name: 'dup base' })).json();
  insertedJobRoleIds.push(created.jobRole.id);

  const second = await createJobRoleRequest({ code: created.jobRole.code, name: 'dup again' });
  assert.strictEqual(second.status, 409);
  const body = await second.json();
  assert.match(body.message, /code/i);
});

test('a missing code or name on job role creation is a 400', async () => {
  const noCode = await createJobRoleRequest({ name: 'no code' });
  assert.strictEqual(noCode.status, 400);

  const noName = await createJobRoleRequest({ code: uniqueCode('JR') });
  assert.strictEqual(noName.status, 400);
});

test('an inactive job role is excluded from the default list and included under ?includeInactive=true', async () => {
  const created = await (await createJobRoleRequest({ code: uniqueCode('JR'), name: 'to deactivate' })).json();
  const id = created.jobRole.id;
  insertedJobRoleIds.push(id);

  await patchJobRoleRequest(id, { isActive: false });

  const defaultList = await (await listJobRolesRequest()).json();
  assert.ok(!defaultList.jobRoles.map((jr) => jr.id).includes(id));

  const withInactive = await (await listJobRolesRequest('?includeInactive=true')).json();
  assert.ok(withInactive.jobRoles.map((jr) => jr.id).includes(id));

  // Any string other than the exact literal "true" must not widen the list.
  const garbage = await (await listJobRolesRequest('?includeInactive=yes')).json();
  assert.ok(!garbage.jobRoles.map((jr) => jr.id).includes(id));
});

test('PATCH renames a job role, and PATCH deactivates one, each leaving other fields untouched', async () => {
  const created = await (await createJobRoleRequest({ code: uniqueCode('JR'), name: 'Original Name' })).json();
  const id = created.jobRole.id;
  insertedJobRoleIds.push(id);

  const renamed = await (await patchJobRoleRequest(id, { name: 'Renamed' })).json();
  assert.strictEqual(renamed.jobRole.name, 'Renamed');
  assert.strictEqual(renamed.jobRole.code, created.jobRole.code);
  assert.strictEqual(renamed.jobRole.isActive, true);

  const deactivated = await (await patchJobRoleRequest(id, { isActive: false })).json();
  assert.strictEqual(deactivated.jobRole.isActive, false);
  assert.strictEqual(deactivated.jobRole.name, 'Renamed');
});

test('PATCH on an unknown job role id is a 404', async () => {
  const response = await patchJobRoleRequest('999999999', { name: 'nobody' });
  assert.strictEqual(response.status, 404);
});

// ---------------------------------------------------------------------------
// Criterion 1: one job role, used by assignments at TWO different Sites.
// ---------------------------------------------------------------------------

test('criterion 1: the same job role is used by assignments at two different Sites, and both detail views name it', async () => {
  const site1 = await insertSite();
  const unit1 = await insertOrgUnit(site1, { name: 'Site 1 Unit' });
  const site2 = await insertSite();
  const unit2 = await insertOrgUnit(site2, { name: 'Site 2 Unit' });

  const employee1 = await insertEmployee({ firstName: 'Site1', lastName: 'Employee' });
  const employee2 = await insertEmployee({ firstName: 'Site2', lastName: 'Employee' });

  const response1 = await createAssignmentRequest(employee1, { orgUnitId: unit1, jobRoleId: sharedRole.id });
  assert.strictEqual(response1.status, 201);
  const response2 = await createAssignmentRequest(employee2, { orgUnitId: unit2, jobRoleId: sharedRole.id });
  assert.strictEqual(response2.status, 201);

  const { body: detail1 } = await getEmployeeDetail(employee1);
  const { body: detail2 } = await getEmployeeDetail(employee2);
  assert.strictEqual(detail1.employee.jobRole.id, sharedRole.id);
  assert.strictEqual(detail2.employee.jobRole.id, sharedRole.id);
});

// ---------------------------------------------------------------------------
// Criterion 2: assign -> 201, and the detail view shows it as current.
// ---------------------------------------------------------------------------

test('criterion 2: assigning an Employee to an Org Unit succeeds, and the detail view shows it as the current assignment', async () => {
  const employeeId = await insertEmployee({ firstName: 'Basic', lastName: 'Assign' });
  const unit = await insertOrgUnit(scopeSite, { name: 'Basic Assign Unit' });

  const response = await createAssignmentRequest(employeeId, { orgUnitId: unit, jobRoleId: sharedRole.id });
  assert.strictEqual(response.status, 201);
  const { assignment } = await response.json();
  assert.match(assignment.effectiveFrom, /^\d{4}-\d{2}-\d{2}$/);
  assert.strictEqual(assignment.effectiveTo, null);
  assert.strictEqual(assignment.isCurrent, true);
  assert.strictEqual(assignment.orgUnit.id, unit);
  assert.strictEqual(assignment.jobRole.id, sharedRole.id);

  const { body } = await getEmployeeDetail(employeeId);
  assert.strictEqual(body.employee.assignments.length, 1);
  assert.strictEqual(body.employee.assignments[0].isCurrent, true);
  assert.strictEqual(body.employee.assignments[0].orgUnit.id, unit);
  assert.strictEqual(body.employee.assignments[0].jobRole.id, sharedRole.id);
  assert.strictEqual(body.employee.jobRole.id, sharedRole.id);
});

// ---------------------------------------------------------------------------
// Criterion 3: transfer records a new assignment and leaves the first intact.
// ---------------------------------------------------------------------------

test('criterion 3: a transfer closes the first assignment (same id, same Org Unit, same job role, same effective_from, new effective_to) and the new one is current; history is newest-first', async () => {
  const employeeId = await insertEmployee({ firstName: 'Transfer', lastName: 'Employee' });
  const fromUnit = await insertOrgUnit(scopeSite, { name: 'Transfer From Unit' });
  const toUnit = await insertOrgUnit(scopeSite, { name: 'Transfer To Unit' });

  const first = await createAssignmentRequest(employeeId, {
    orgUnitId: fromUnit,
    jobRoleId: sharedRole.id,
    effectiveFrom: '2022-01-01'
  });
  assert.strictEqual(first.status, 201);
  const { assignment: firstAssignment } = await first.json();

  const second = await createAssignmentRequest(employeeId, {
    orgUnitId: toUnit,
    jobRoleId: sharedRole.id,
    effectiveFrom: '2023-01-01'
  });
  assert.strictEqual(second.status, 201);
  const { assignment: secondAssignment } = await second.json();
  assert.strictEqual(secondAssignment.effectiveFrom, '2023-01-01');
  assert.strictEqual(secondAssignment.effectiveTo, null);
  assert.strictEqual(secondAssignment.isCurrent, true);

  const { body } = await getEmployeeDetail(employeeId);
  assert.strictEqual(body.employee.assignments.length, 2);

  // Newest first.
  const [current, closed] = body.employee.assignments;
  assert.strictEqual(current.id, secondAssignment.id);
  assert.strictEqual(current.isCurrent, true);
  assert.strictEqual(current.orgUnit.id, toUnit);

  assert.strictEqual(closed.id, firstAssignment.id);
  assert.strictEqual(closed.orgUnit.id, fromUnit);
  assert.strictEqual(closed.jobRole.id, sharedRole.id);
  assert.strictEqual(closed.effectiveFrom, '2022-01-01');
  assert.strictEqual(closed.effectiveTo, '2023-01-01');
  assert.strictEqual(closed.isCurrent, false);
});

// ---------------------------------------------------------------------------
// Authorization: write scope on the DESTINATION Org Unit.
// ---------------------------------------------------------------------------

test('a caller with a write grant on the destination Org Unit can assign (201)', async () => {
  const employeeId = await insertEmployee({ firstName: 'WriteGrant', lastName: 'Employee' });
  const response = await createAssignmentRequest(
    employeeId,
    { orgUnitId: scopeUnit, jobRoleId: sharedRole.id },
    writeGrantAccount.token
  );
  assert.strictEqual(response.status, 201);
});

test('an administrator with no grants at all can assign (201)', async () => {
  const employeeId = await insertEmployee({ firstName: 'Admin', lastName: 'Employee' });
  const response = await createAssignmentRequest(
    employeeId,
    { orgUnitId: scopeUnit, jobRoleId: sharedRole.id },
    adminAccount.token
  );
  assert.strictEqual(response.status, 201);
});

test('a caller with only a read grant on the destination Org Unit cannot assign (403)', async () => {
  const employeeId = await insertEmployee({ firstName: 'ReadGrant', lastName: 'Employee' });
  const response = await createAssignmentRequest(
    employeeId,
    { orgUnitId: scopeUnit, jobRoleId: sharedRole.id },
    readGrantAccount.token
  );
  assert.strictEqual(response.status, 403);
  const body = await response.json();
  assert.match(body.message, /granted Org Unit/i);
});

test('a caller holding a grant elsewhere in the tree cannot assign into the destination Org Unit (403)', async () => {
  const employeeId = await insertEmployee({ firstName: 'Elsewhere', lastName: 'Employee' });
  const response = await createAssignmentRequest(
    employeeId,
    { orgUnitId: scopeUnit, jobRoleId: sharedRole.id },
    elsewhereGrantAccount.token
  );
  assert.strictEqual(response.status, 403);
});

// ---------------------------------------------------------------------------
// Conflicts: same-day, backdated overlap, Departed Employee.
// ---------------------------------------------------------------------------

test('a second assignment beginning the same day as an existing open one is a 409', async () => {
  const employeeId = await insertEmployee({ firstName: 'SameDay', lastName: 'Employee' });
  const unit = await insertOrgUnit(scopeSite, { name: 'Same Day Unit' });
  await insertRawAssignment({ employeeId, orgUnitId: unit, effectiveFrom: null }); // effective_from = CURRENT_DATE

  const response = await createAssignmentRequest(employeeId, { orgUnitId: unit, jobRoleId: sharedRole.id });
  assert.strictEqual(response.status, 409);
  const body = await response.json();
  assert.match(body.message, /already has an assignment/i);
});

test('a backdated assignment overlapping an existing open one is a 409', async () => {
  const employeeId = await insertEmployee({ firstName: 'Backdated', lastName: 'Employee' });
  const unit = await insertOrgUnit(scopeSite, { name: 'Backdated Unit' });
  await insertRawAssignment({ employeeId, orgUnitId: unit, effectiveFrom: '2020-01-01' });

  const response = await createAssignmentRequest(employeeId, {
    orgUnitId: unit,
    jobRoleId: sharedRole.id,
    effectiveFrom: '2019-01-01'
  });
  assert.strictEqual(response.status, 409);
  const body = await response.json();
  assert.match(body.message, /overlaps/i);
});

test('assigning a Departed Employee is a 409, not a 500 or a silent success', async () => {
  const employeeId = await insertEmployee({ firstName: 'Departed', lastName: 'Employee', isActive: false });
  const response = await createAssignmentRequest(employeeId, { orgUnitId: scopeUnit, jobRoleId: sharedRole.id });
  assert.strictEqual(response.status, 409);
  const body = await response.json();
  assert.match(body.message, /departed/i);
});

// ---------------------------------------------------------------------------
// 404s and 400s.
// ---------------------------------------------------------------------------

test('an unknown Employee id is a 404', async () => {
  const response = await createAssignmentRequest('999999999', { orgUnitId: scopeUnit, jobRoleId: sharedRole.id });
  assert.strictEqual(response.status, 404);
});

test('an unknown Org Unit id is a 404', async () => {
  const employeeId = await insertEmployee();
  const response = await createAssignmentRequest(employeeId, { orgUnitId: '999999999', jobRoleId: sharedRole.id });
  assert.strictEqual(response.status, 404);
});

test('an unknown jobRoleId is a 404', async () => {
  const employeeId = await insertEmployee();
  const unit = await insertOrgUnit(scopeSite, { name: 'Unknown Role Unit' });
  const response = await createAssignmentRequest(employeeId, { orgUnitId: unit, jobRoleId: '999999999' });
  assert.strictEqual(response.status, 404);
});

test('a malformed Employee id, Org Unit id, and jobRoleId are each a 400 naming the field', async () => {
  const employeeId = await insertEmployee();
  const unit = await insertOrgUnit(scopeSite, { name: 'Malformed Unit' });

  const malformedEmployee = await createAssignmentRequest('not-an-id', { orgUnitId: unit });
  assert.strictEqual(malformedEmployee.status, 400);

  const malformedOrgUnit = await createAssignmentRequest(employeeId, { orgUnitId: 'not-an-id' });
  assert.strictEqual(malformedOrgUnit.status, 400);
  const orgUnitBody = await malformedOrgUnit.json();
  assert.match(orgUnitBody.message, /orgUnitId/);

  const malformedJobRole = await createAssignmentRequest(employeeId, { orgUnitId: unit, jobRoleId: 'not-an-id' });
  assert.strictEqual(malformedJobRole.status, 400);
  const jobRoleBody = await malformedJobRole.json();
  assert.match(jobRoleBody.message, /jobRoleId/);
});

test('a missing orgUnitId is a 400', async () => {
  const employeeId = await insertEmployee();
  const response = await createAssignmentRequest(employeeId, {});
  assert.strictEqual(response.status, 400);
});

// ---------------------------------------------------------------------------
// Criterion 4: filtering the directory by job role.
// ---------------------------------------------------------------------------

test('criterion 4: ?jobRoleId= returns only current holders of that role, excludes one whose assignment in that role has ended, and 404s on an unknown role', async () => {
  const unit = await insertOrgUnit(scopeSite, { name: 'Role Filter Unit' });

  const currentHolder = await insertEmployee({ firstName: 'CurrentHolder', lastName: 'RoleFilter' });
  await insertRawAssignment({ employeeId: currentHolder, orgUnitId: unit, jobRoleId: filterRole.id, effectiveFrom: '2021-01-01' });

  const endedHolder = await insertEmployee({ firstName: 'EndedHolder', lastName: 'RoleFilter' });
  await insertRawAssignment({
    employeeId: endedHolder,
    orgUnitId: unit,
    jobRoleId: filterRole.id,
    effectiveFrom: '2018-01-01',
    effectiveTo: '2019-01-01'
  });
  await insertRawAssignment({ employeeId: endedHolder, orgUnitId: unit, jobRoleId: null, effectiveFrom: '2019-01-01' });

  const response = await listEmployeesRequest(`?jobRoleId=${filterRole.id}`);
  assert.strictEqual(response.status, 200);
  const { employees } = await response.json();
  const ids = employees.map((e) => e.id);
  assert.ok(ids.includes(currentHolder), 'a current holder of the filtered role should be included');
  assert.ok(!ids.includes(endedHolder), 'an Employee whose assignment in that role has ended should be excluded');

  const unknown = await listEmployeesRequest('?jobRoleId=999999999');
  assert.strictEqual(unknown.status, 404);
});

test('criterion 4: jobRoleId combines with search and with orgUnitId by AND', async () => {
  const unitP = await insertOrgUnit(scopeSite, { name: 'Role Filter Unit P' });
  const unitQ = await insertOrgUnit(scopeSite, { name: 'Role Filter Unit Q' });

  const searchTarget = await insertEmployee({ firstName: 'Wioletta', lastName: 'RoleFilterSearch' });
  await insertRawAssignment({ employeeId: searchTarget, orgUnitId: unitP, jobRoleId: filterRole.id, effectiveFrom: '2021-01-01' });

  const searchDecoy = await insertEmployee({ firstName: 'Marek', lastName: 'RoleFilterSearch' });
  await insertRawAssignment({ employeeId: searchDecoy, orgUnitId: unitP, jobRoleId: filterRole.id, effectiveFrom: '2021-01-01' });

  const atUnitQ = await insertEmployee({ firstName: 'AtUnitQ', lastName: 'RoleFilterOrgUnit' });
  await insertRawAssignment({ employeeId: atUnitQ, orgUnitId: unitQ, jobRoleId: filterRole.id, effectiveFrom: '2021-01-01' });

  // search narrows within the role filter.
  const bySearch = await listEmployeesRequest(`?jobRoleId=${filterRole.id}&search=Wioletta`);
  const { employees: bySearchList } = await bySearch.json();
  const bySearchIds = bySearchList.map((e) => e.id);
  assert.ok(bySearchIds.includes(searchTarget));
  assert.ok(!bySearchIds.includes(searchDecoy));

  // orgUnitId narrows within the role filter.
  const byOrgUnit = await listEmployeesRequest(`?jobRoleId=${filterRole.id}&orgUnitId=${unitP}`);
  const { employees: byOrgUnitList } = await byOrgUnit.json();
  const byOrgUnitIds = byOrgUnitList.map((e) => e.id);
  assert.ok(byOrgUnitIds.includes(searchTarget));
  assert.ok(byOrgUnitIds.includes(searchDecoy));
  assert.ok(!byOrgUnitIds.includes(atUnitQ), 'an Employee holding the role at a different Org Unit should not match');
});

// ---------------------------------------------------------------------------
// Criterion 5: the detail view's assignments array is the full history, in
// order, with isCurrent set — already exercised throughout (criterion 2 and
// 3's own assertions), asserted once more explicitly here with three
// assignments spanning past, closed and current.
// ---------------------------------------------------------------------------

test('criterion 5: the detail view shows the full assignment history, newest first, with isCurrent set correctly on each row', async () => {
  const employeeId = await insertEmployee({ firstName: 'History', lastName: 'Employee' });
  const unitA = await insertOrgUnit(scopeSite, { name: 'History Unit A' });
  const unitB = await insertOrgUnit(scopeSite, { name: 'History Unit B' });
  const unitC = await insertOrgUnit(scopeSite, { name: 'History Unit C' });

  await insertRawAssignment({ employeeId, orgUnitId: unitA, effectiveFrom: '2018-01-01', effectiveTo: '2019-01-01' });
  await insertRawAssignment({ employeeId, orgUnitId: unitB, effectiveFrom: '2019-01-01', effectiveTo: '2020-01-01' });
  await insertRawAssignment({ employeeId, orgUnitId: unitC, jobRoleId: sharedRole.id, effectiveFrom: '2020-01-01' });

  const { body } = await getEmployeeDetail(employeeId);
  const { assignments } = body.employee;
  assert.strictEqual(assignments.length, 3);
  assert.deepStrictEqual(assignments.map((a) => a.orgUnit.id), [unitC, unitB, unitA]);
  assert.deepStrictEqual(assignments.map((a) => a.isCurrent), [true, false, false]);
  assert.strictEqual(assignments[0].jobRole.id, sharedRole.id);
});
