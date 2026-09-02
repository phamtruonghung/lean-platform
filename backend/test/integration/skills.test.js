/*
 * The skills matrix, over HTTP (issue #11), against a real database and a
 * real (locally issued) JWKS — the same seam as plant.test.js/
 * assignments.test.js (see either file's own header, and the README's Tests
 * section).
 *
 * This file does not truncate `app_users`, `sites`, `org_units`, `employees`
 * or `skills`: all are shared with the other integration files, and
 * `npm run test:integration` runs every file with `--test-concurrency=1`, so
 * a truncate here would still corrupt whichever file ran first. Instead this
 * file inserts its own rows under a `process.pid`-unique `uniqueCode`, the
 * same device plant.test.js/assignments.test.js use, for every UNIQUE
 * constraint value it touches: `skills.code`, `employees.employee_no`,
 * `sites.code`, `(site_id, code)` on `org_units`, and `external_subject` on
 * `app_users`. Every row inserted — across `app_users`, `app_user_org_units`,
 * `sites`, `org_units`, `skills`, `skill_requirements`, `employees`,
 * `employee_assignments` and `employee_skills` — is deleted again in
 * `test.after()`, in FK-safe order.
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
const insertedSkillIds = [];
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
     VALUES ($1, 'Skills Test Account', $2, $3, $4, $5) RETURNING id`,
    [`${subject}@example.com`, role, subject, isActive, approvalStatus]
  );
  insertedAccountIds.push(row.id);
  return { id: row.id, token: await authHeader(subject) };
}

async function insertSite() {
  const { rows: [row] } = await pool.query(
    `INSERT INTO sites (code, name, timezone) VALUES ($1, 'Skills Test Site', 'Asia/Ho_Chi_Minh') RETURNING id`,
    [uniqueCode('ST')]
  );
  insertedSiteIds.push(row.id);
  return row.id;
}

async function insertOrgUnit(siteId, { parentId = null, unitType = 'area', name = 'Skills Test Org Unit' } = {}) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, $2, $3, $4, $5) RETURNING id, path`,
    [siteId, parentId, uniqueCode('OU'), name, unitType]
  );
  insertedOrgUnitIds.push(row.id);
  return row.id;
}

async function insertSkill({ name = 'Skills Test Welding', revalidationMonths = null } = {}) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO skills (code, name, revalidation_months) VALUES ($1, $2, $3) RETURNING id, code, name`,
    [uniqueCode('SK'), name, revalidationMonths]
  );
  insertedSkillIds.push(row.id);
  return row;
}

async function insertEmployee({ firstName = 'Skills', lastName = 'Test', isActive = true } = {}) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO employees (employee_no, first_name, last_name, is_active)
     VALUES ($1, $2, $3, $4) RETURNING id`,
    [uniqueCode('EMP'), firstName, lastName, isActive]
  );
  insertedEmployeeIds.push(row.id);
  return row.id;
}

async function insertAssignment({ employeeId, orgUnitId }) {
  await pool.query(
    `INSERT INTO employee_assignments (employee_id, org_unit_id, effective_from)
     VALUES ($1, $2, CURRENT_DATE)`,
    [employeeId, orgUnitId]
  );
}

async function insertRawEmployeeSkill({ employeeId, skillId, proficiencyLevel = 3, assessedOn = null, expiresOn = null }) {
  await pool.query(
    `INSERT INTO employee_skills (employee_id, skill_id, proficiency_level, assessed_on, expires_on)
     VALUES ($1, $2, $3, COALESCE($4::date, CURRENT_DATE), $5)`,
    [employeeId, skillId, proficiencyLevel, assessedOn, expiresOn]
  );
}

async function insertSkillRequirement({ orgUnitId, skillId, minimumLevel = 2, minimumQualifiedHeadcount = 1 }) {
  await pool.query(
    `INSERT INTO skill_requirements (org_unit_id, skill_id, minimum_level, minimum_qualified_headcount)
     VALUES ($1, $2, $3, $4)`,
    [orgUnitId, skillId, minimumLevel, minimumQualifiedHeadcount]
  );
}

let adminAccount;
let readerAccount; // approved, active, non-admin, no grants.

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
});

test.after(async () => {
  await pool.query('DELETE FROM employee_skills WHERE employee_id = ANY($1)', [insertedEmployeeIds]);
  await pool.query('DELETE FROM employee_assignments WHERE employee_id = ANY($1)', [insertedEmployeeIds]);
  await pool.query('DELETE FROM skill_requirements WHERE skill_id = ANY($1)', [insertedSkillIds]);
  await pool.query('DELETE FROM app_user_org_units WHERE app_user_id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM app_users WHERE id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM employees WHERE id = ANY($1)', [insertedEmployeeIds]);
  await pool.query('DELETE FROM skills WHERE id = ANY($1)', [insertedSkillIds]);
  await pool.query('DELETE FROM org_units WHERE id = ANY($1)', [insertedOrgUnitIds]);
  await pool.query('DELETE FROM sites WHERE id = ANY($1)', [insertedSiteIds]);

  await new Promise((resolve) => server.close(resolve));
  await closePool();
  await jwks.close();
});

// ---------------------------------------------------------------------------
// Requests
// ---------------------------------------------------------------------------

async function listSkillsRequest(query = '', token = readerAccount.token) {
  return fetch(`${base}/api/people/skills${query}`, { headers: token });
}

async function createSkillRequest(body, token = adminAccount.token) {
  return fetch(`${base}/api/people/skills`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
}

async function patchSkillRequest(id, body, token = adminAccount.token) {
  return fetch(`${base}/api/people/skills/${id}`, {
    method: 'PATCH',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
}

async function putEmployeeSkillRequest(employeeId, skillId, body, token = adminAccount.token) {
  return fetch(`${base}/api/people/employees/${employeeId}/skills/${skillId}`, {
    method: 'PUT',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
}

async function getEmployeeDetailRequest(employeeId, token = adminAccount.token) {
  const response = await fetch(`${base}/api/people/employees/${employeeId}`, { headers: token });
  return { response, body: await response.json() };
}

async function qualifiedEmployeesRequest(skillId, query, token = readerAccount.token) {
  return fetch(`${base}/api/people/skills/${skillId}/qualified-employees${query}`, { headers: token });
}

async function skillCoverageRequest(siteId, token = adminAccount.token) {
  return fetch(`${base}/api/people/sites/${siteId}/skill-coverage`, { headers: token });
}

// ---------------------------------------------------------------------------
// 1 & 2: create a Skill, and authorization on the write surface.
// ---------------------------------------------------------------------------

test('an administrator creates a Skill (201), and it round-trips code/name/category', async () => {
  const code = uniqueCode('SK');
  const response = await createSkillRequest({ code, name: 'Robotic Welding', skillCategory: 'operation' });
  assert.strictEqual(response.status, 201);
  const { skill } = await response.json();
  insertedSkillIds.push(skill.id);

  assert.strictEqual(skill.code, code);
  assert.strictEqual(skill.name, 'Robotic Welding');
  assert.strictEqual(skill.skillCategory, 'operation');
  assert.strictEqual(skill.isActive, true);
  assert.strictEqual(skill.requiresCertification, false);
  assert.strictEqual(skill.orgUnitId, null);
});

test('a non-admin gets 403 creating a Skill; an unauthenticated or inactive caller gets 401/403', async () => {
  const nonAdmin = await createSkillRequest({ code: uniqueCode('SK'), name: 'x' }, readerAccount.token);
  assert.strictEqual(nonAdmin.status, 403);

  const unauthenticated = await fetch(`${base}/api/people/skills`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ code: uniqueCode('SK'), name: 'x' })
  });
  assert.strictEqual(unauthenticated.status, 401);

  const pending = await insertAccount({ isActive: false, approvalStatus: 'pending' });
  const inactive = await createSkillRequest({ code: uniqueCode('SK'), name: 'x' }, pending.token);
  assert.strictEqual(inactive.status, 403);
  const body = await inactive.json();
  assert.strictEqual(body.status, 'pending_approval');
});

// ---------------------------------------------------------------------------
// 3: skills are NOT Site-scoped.
// ---------------------------------------------------------------------------

test('skills are not Site-scoped: created once, listed the same regardless of Site/Org Unit context, with no siteId on the row', async () => {
  // Two distinct Sites exist, but GET /skills carries no siteId (or any
  // other Site-shaped) query param at all — there is nothing to scope by,
  // which is itself part of the assertion: the catalogue is shared by every
  // Site (ADR-0005's shape), not filtered per-Site the way GET
  // /sites/:siteId/org-units is.
  await insertSite();
  await insertSite();

  const created = await (await createSkillRequest({ code: uniqueCode('SK'), name: 'Shared Skill' })).json();
  insertedSkillIds.push(created.skill.id);

  assert.strictEqual(Object.prototype.hasOwnProperty.call(created.skill, 'siteId'), false);

  const list1 = await (await listSkillsRequest()).json();
  const list2 = await (await listSkillsRequest()).json();
  assert.ok(list1.skills.map((s) => s.id).includes(created.skill.id));
  assert.ok(list2.skills.map((s) => s.id).includes(created.skill.id));
});

// ---------------------------------------------------------------------------
// 4 & 5: recording an Employee holding a skill, with expiry; lapsed
// qualifications stay visible on the detail view but are excluded from the
// qualified-employees query.
// ---------------------------------------------------------------------------

test('recording an Employee holding a skill with an expiry round-trips proficiencyLevel/expiresOn', async () => {
  const employeeId = await insertEmployee({ firstName: 'Holder', lastName: 'Skill' });
  const skill = await insertSkill({ name: 'Record Test Skill' });

  const response = await putEmployeeSkillRequest(employeeId, skill.id, {
    proficiencyLevel: 3,
    assessedOn: '2024-01-01',
    expiresOn: '2030-01-01',
    evidenceRef: 'cert-123',
    note: 'first assessment'
  });
  assert.ok(response.status === 200 || response.status === 201);
  const { employeeSkill } = await response.json();
  assert.strictEqual(employeeSkill.proficiencyLevel, 3);
  assert.strictEqual(employeeSkill.assessedOn, '2024-01-01');
  assert.strictEqual(employeeSkill.expiresOn, '2030-01-01');
  assert.strictEqual(employeeSkill.evidenceRef, 'cert-123');
  assert.strictEqual(employeeSkill.note, 'first assessment');
  assert.strictEqual(employeeSkill.skill.id, skill.id);
});

test('a lapsed qualification stays visible (with its real past expiresOn) on the Employee detail view, but is excluded from qualified-employees', async () => {
  const site = await insertSite();
  const orgUnit = await insertOrgUnit(site, { name: 'Lapsed Test Unit' });
  const employeeId = await insertEmployee({ firstName: 'Lapsed', lastName: 'Holder' });
  const skill = await insertSkill({ name: 'Lapsed Test Skill' });

  await insertAssignment({ employeeId, orgUnitId: orgUnit });
  await insertRawEmployeeSkill({
    employeeId,
    skillId: skill.id,
    proficiencyLevel: 3,
    assessedOn: '2015-01-01',
    expiresOn: '2016-01-01' // long past
  });

  const { response, body } = await getEmployeeDetailRequest(employeeId);
  assert.strictEqual(response.status, 200);
  const skillEntry = body.employee.skills.find((s) => s.skill.id === skill.id);
  assert.ok(skillEntry, 'the lapsed skill should still be visible on the detail view');
  assert.strictEqual(skillEntry.expiresOn, '2016-01-01');

  const qualifiedResponse = await qualifiedEmployeesRequest(skill.id, `?orgUnitId=${orgUnit}`);
  assert.strictEqual(qualifiedResponse.status, 200);
  const { employees } = await qualifiedResponse.json();
  assert.ok(!employees.map((e) => e.id).includes(employeeId), 'a lapsed holder should be excluded');
});

// ---------------------------------------------------------------------------
// 6: qualified-employees scoped to an Org Unit.
// ---------------------------------------------------------------------------

test('GET /skills/:id/qualified-employees scoped to an Org Unit returns a qualified holder, excludes a lapsed one and one at an unrelated Org Unit branch', async () => {
  const site = await insertSite();
  const targetUnit = await insertOrgUnit(site, { name: 'Qualified Target Unit' });
  const unrelatedUnit = await insertOrgUnit(site, { name: 'Qualified Unrelated Unit' });
  const skill = await insertSkill({ name: 'Qualified Test Skill' });

  const qualifiedEmployee = await insertEmployee({ firstName: 'Qualified', lastName: 'Holder' });
  await insertAssignment({ employeeId: qualifiedEmployee, orgUnitId: targetUnit });
  await insertRawEmployeeSkill({ employeeId: qualifiedEmployee, skillId: skill.id, proficiencyLevel: 3 });

  const lapsedEmployee = await insertEmployee({ firstName: 'LapsedBranch', lastName: 'Holder' });
  await insertAssignment({ employeeId: lapsedEmployee, orgUnitId: targetUnit });
  await insertRawEmployeeSkill({
    employeeId: lapsedEmployee, skillId: skill.id, proficiencyLevel: 3,
    assessedOn: '2015-01-01', expiresOn: '2016-01-01'
  });

  const unrelatedEmployee = await insertEmployee({ firstName: 'Unrelated', lastName: 'Holder' });
  await insertAssignment({ employeeId: unrelatedEmployee, orgUnitId: unrelatedUnit });
  await insertRawEmployeeSkill({ employeeId: unrelatedEmployee, skillId: skill.id, proficiencyLevel: 3 });

  const response = await qualifiedEmployeesRequest(skill.id, `?orgUnitId=${targetUnit}`);
  assert.strictEqual(response.status, 200);
  const { employees } = await response.json();
  const ids = employees.map((e) => e.id);
  assert.ok(ids.includes(qualifiedEmployee));
  assert.ok(!ids.includes(lapsedEmployee));
  assert.ok(!ids.includes(unrelatedEmployee));
});

test('GET /skills/:id/qualified-employees without orgUnitId is a 400', async () => {
  const skill = await insertSkill({ name: 'No Org Unit Test Skill' });
  const response = await qualifiedEmployeesRequest(skill.id, '');
  assert.strictEqual(response.status, 400);
});

// ---------------------------------------------------------------------------
// 7: skill coverage — shortfall, and admin-only.
// ---------------------------------------------------------------------------

test('GET /sites/:siteId/skill-coverage shows a shortfall when a requirement has a headcount gap, and a non-admin gets 403', async () => {
  const site = await insertSite();
  const orgUnit = await insertOrgUnit(site, { name: 'Coverage Test Unit' });
  const skill = await insertSkill({ name: 'Coverage Test Skill' });

  await insertSkillRequirement({ orgUnitId: orgUnit, skillId: skill.id, minimumLevel: 2, minimumQualifiedHeadcount: 2 });
  // Only one qualified holder against a requirement of 2 — a shortfall of 1.
  const holder = await insertEmployee({ firstName: 'Coverage', lastName: 'Holder' });
  await insertAssignment({ employeeId: holder, orgUnitId: orgUnit });
  await insertRawEmployeeSkill({ employeeId: holder, skillId: skill.id, proficiencyLevel: 3 });

  const response = await skillCoverageRequest(site);
  assert.strictEqual(response.status, 200);
  const { coverage } = await response.json();
  const row = coverage.find((c) => c.orgUnitId === orgUnit && c.skillId === skill.id);
  assert.ok(row, 'the shortfall row should appear');
  assert.strictEqual(row.minimumQualifiedHeadcount, 2);
  assert.strictEqual(row.qualifiedHeadcount, 1);
  assert.strictEqual(row.shortfall, 1);

  const nonAdminResponse = await skillCoverageRequest(site, readerAccount.token);
  assert.strictEqual(nonAdminResponse.status, 403);
});

// ---------------------------------------------------------------------------
// 8: re-assessment upsert path, and the always-re-triggering expiry.
// ---------------------------------------------------------------------------

test('PUTting the same Employee+skill twice upserts (one row), and omitting expiresOn re-derives a fresh expiry from revalidationMonths each time', async () => {
  const employeeId = await insertEmployee({ firstName: 'Upsert', lastName: 'Holder' });
  const skill = await insertSkill({ name: 'Upsert Test Skill', revalidationMonths: 12 });

  const first = await putEmployeeSkillRequest(employeeId, skill.id, {
    proficiencyLevel: 1,
    assessedOn: '2024-01-01'
  });
  assert.ok(first.status === 200 || first.status === 201);
  const { employeeSkill: firstSkill } = await first.json();
  assert.strictEqual(firstSkill.proficiencyLevel, 1);
  assert.strictEqual(firstSkill.expiresOn, '2025-01-01'); // 2024-01-01 + 12 months, trigger-derived.

  const secondReal = await putEmployeeSkillRequest(employeeId, skill.id, {
    proficiencyLevel: 3,
    assessedOn: '2024-06-01'
  });
  assert.ok(secondReal.status === 200 || secondReal.status === 201);
  const { employeeSkill: secondSkill } = await secondReal.json();
  assert.strictEqual(secondSkill.id, firstSkill.id, 'still one row, same id, upserted not duplicated');
  assert.strictEqual(secondSkill.proficiencyLevel, 3);
  assert.strictEqual(secondSkill.assessedOn, '2024-06-01');
  assert.strictEqual(secondSkill.expiresOn, '2025-06-01'); // re-derived from the NEW assessedOn.

  const { rows } = await pool.query(
    'SELECT COUNT(*)::int AS count FROM employee_skills WHERE employee_id = $1 AND skill_id = $2',
    [employeeId, skill.id]
  );
  assert.strictEqual(rows[0].count, 1);
});

// ---------------------------------------------------------------------------
// A few more 400/404s worth covering directly.
// ---------------------------------------------------------------------------

test('creating a Skill with a duplicate code is a 409', async () => {
  const code = uniqueCode('SK');
  const first = await (await createSkillRequest({ code, name: 'dup base' })).json();
  insertedSkillIds.push(first.skill.id);

  const second = await createSkillRequest({ code, name: 'dup again' });
  assert.strictEqual(second.status, 409);
});

test('PATCH deactivates a Skill, which stays readable', async () => {
  const created = await (await createSkillRequest({ code: uniqueCode('SK'), name: 'to deactivate' })).json();
  insertedSkillIds.push(created.skill.id);

  const deactivated = await (await patchSkillRequest(created.skill.id, { isActive: false })).json();
  assert.strictEqual(deactivated.skill.isActive, false);

  const listResponse = await listSkillsRequest();
  const { skills } = await listResponse.json();
  assert.ok(!skills.map((s) => s.id).includes(created.skill.id));

  const withInactive = await (await listSkillsRequest('?includeInactive=true')).json();
  assert.ok(withInactive.skills.map((s) => s.id).includes(created.skill.id));
});

test('an expiresOn before assessedOn is a clean 400, not a 500', async () => {
  const employeeId = await insertEmployee({ firstName: 'BadExpiry', lastName: 'Holder' });
  const skill = await insertSkill({ name: 'Bad Expiry Test Skill' });

  const response = await putEmployeeSkillRequest(employeeId, skill.id, {
    proficiencyLevel: 2,
    assessedOn: '2024-06-01',
    expiresOn: '2024-01-01'
  });
  assert.strictEqual(response.status, 400);
});

test('an unknown Employee or Skill id on PUT is a 404', async () => {
  const skill = await insertSkill({ name: 'Unknown Employee Test Skill' });
  const unknownEmployee = await putEmployeeSkillRequest('999999999', skill.id, { proficiencyLevel: 1 });
  assert.strictEqual(unknownEmployee.status, 404);

  const employeeId = await insertEmployee();
  const unknownSkill = await putEmployeeSkillRequest(employeeId, '999999999', { proficiencyLevel: 1 });
  assert.strictEqual(unknownSkill.status, 404);
});
