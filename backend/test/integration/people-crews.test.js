/*
 * The crew picker on the Assessment assign form — `GET /api/people/sites/:siteId/crews`
 * and the two refusals `assign` makes about a crew — measured over HTTP against a
 * real database and a real local session, the seam people-assessment-attempts.test.js
 * uses.
 *
 * Every case builds its own Site, so a crew list is private to the case, and
 * `test.after` deletes exactly what this file inserted: Assessments (their Attempts
 * cascade), the Question bank, Grants, Accounts, Employees (their assignments
 * cascade), crews, Org Units and Sites.
 */

const test = require('node:test');
const assert = require('node:assert');
const { tokenFor } = require('../helpers/session');

let server;
let base;
let pool;
let closePool;

const insertedAccountIds = [];
const insertedEmployeeIds = [];
const insertedSiteIds = [];
const insertedOrgUnitIds = [];
const insertedCrewIds = [];

let counter = 0;
function unique(prefix) {
  counter += 1;
  return `${prefix}${process.pid}${counter}`;
}

async function insertAccount({ role }) {
  const subject = unique('acct');
  const { rows: [row] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status)
     VALUES ($1, 'Crew Picker Test Account', $2, $3, true, 'approved') RETURNING id`,
    [`${subject}@example.com`, role, subject]
  );
  insertedAccountIds.push(row.id);
  return { id: row.id, role, token: { authorization: `Bearer ${await tokenFor(subject)}` } };
}

async function insertGrant({ accountId, orgUnitId, canWrite }) {
  await pool.query(
    'INSERT INTO app_user_org_units (app_user_id, org_unit_id, can_write) VALUES ($1, $2, $3)',
    [accountId, orgUnitId, canWrite]
  );
}

async function insertSite() {
  const { rows: [site] } = await pool.query(
    `INSERT INTO sites (code, name, timezone)
     VALUES ($1, 'Crew Picker Test Site', 'Asia/Ho_Chi_Minh') RETURNING id`,
    [unique('ST')]
  );
  insertedSiteIds.push(site.id);
  return site.id;
}

async function insertOrgUnit({ siteId, name }) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, NULL, $2, $3, 'area') RETURNING id`,
    [siteId, unique('OU'), name]
  );
  insertedOrgUnitIds.push(row.id);
  return row.id;
}

async function insertCrew({ siteId, code = unique('CREW'), name, isActive = true }) {
  const { rows: [row] } = await pool.query(
    'INSERT INTO crews (site_id, code, name, is_active) VALUES ($1, $2, $3, $4) RETURNING id, code, name',
    [siteId, code, name ?? `Crew ${code}`, isActive]
  );
  insertedCrewIds.push(row.id);
  return row;
}

async function insertEmployee({ orgUnitId = null, crewId = null, isActive = true, firstName = 'Crew' }) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO employees (employee_no, first_name, last_name, default_org_unit_id, default_crew_id, is_active)
     VALUES ($1, $2, 'Member', $3, $4, $5) RETURNING id`,
    [unique('E'), firstName, orgUnitId, crewId, isActive]
  );
  insertedEmployeeIds.push(row.id);
  return row.id;
}

// An open-ended assignment, current from long ago, carrying the crew.
async function assignToCrew({ employeeId, orgUnitId, crewId }) {
  await pool.query(
    `INSERT INTO employee_assignments (employee_id, org_unit_id, crew_id, effective_from)
     VALUES ($1, $2, $3, DATE '2000-01-01')`,
    [employeeId, orgUnitId, crewId]
  );
}

async function insertQuestions(orgUnitId, count) {
  for (let i = 1; i <= count; i += 1) {
    await pool.query(
      `INSERT INTO assessment_questions
         (org_unit_id, question_text, option_a, option_b, option_c, correct_option, explanation)
       VALUES ($1, $2, 'A', 'B', 'C', 'C', 'Lý do.')`,
      [orgUnitId, `Câu ${i} của quy trình này là gì?`]
    );
  }
}

async function call(account, path, { method = 'GET', body } = {}) {
  const response = await fetch(`${base}${path}`, {
    method,
    headers: {
      ...account.token,
      ...(body === undefined ? {} : { 'content-type': 'application/json' })
    },
    body: body === undefined ? undefined : JSON.stringify(body)
  });
  const payload = await response.json().catch(() => null);
  return { response, payload, status: response.status };
}

let admin;
let supervisor;

test.before(async () => {
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

  admin = await insertAccount({ role: 'admin' });
  supervisor = await insertAccount({ role: 'supervisor' });
});

test.after(async () => {
  await pool.query('DELETE FROM assessments WHERE site_id = ANY($1)', [insertedSiteIds]);
  await pool.query('DELETE FROM assessment_questions WHERE org_unit_id = ANY($1)', [insertedOrgUnitIds]);
  await pool.query('DELETE FROM app_user_org_units WHERE app_user_id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM app_users WHERE id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM employees WHERE id = ANY($1)', [insertedEmployeeIds]);
  await pool.query('DELETE FROM crews WHERE id = ANY($1)', [insertedCrewIds]);
  await pool.query('DELETE FROM org_units WHERE id = ANY($1)', [insertedOrgUnitIds]);
  await pool.query('DELETE FROM sites WHERE id = ANY($1)', [insertedSiteIds]);
  await new Promise((resolve) => server.close(resolve));
  await closePool();
});

// A Site with a process Org Unit (a bank of 10 Questions, a write Grant for the
// supervisor) and a team Org Unit.
async function stageSite() {
  const siteId = await insertSite();
  const processUnitId = await insertOrgUnit({ siteId, name: `Cutting MTU ${unique('P')}` });
  const teamUnitId = await insertOrgUnit({ siteId, name: `Team ${unique('T')}` });
  await insertGrant({ accountId: supervisor.id, orgUnitId: processUnitId, canWrite: true });
  await insertQuestions(processUnitId, 10);
  return { siteId, processUnitId, teamUnitId };
}

async function createAssessment(orgUnitId) {
  const created = await call(supervisor, '/api/people/assessments', {
    method: 'POST',
    body: { orgUnitId, title: 'Kiểm tra quy trình Cutting MTU', questionCount: 10 }
  });
  assert.strictEqual(created.status, 201, JSON.stringify(created.payload));
  return created.payload.assessment;
}

async function attemptCount(assessmentId) {
  const { rows: [row] } = await pool.query(
    'SELECT count(*)::int AS n FROM assessment_attempts WHERE assessment_id = $1',
    [assessmentId]
  );
  return row.n;
}

test('the crew list returns a seeded crew with an employeeCount of its active members, by open assignment or by default crew', async () => {
  const { siteId, teamUnitId } = await stageSite();
  const crew = await insertCrew({ siteId, name: 'Crew Alpha' });
  const otherCrew = await insertCrew({ siteId, name: 'Crew Beta' });

  const viaAssignment = await insertEmployee({ orgUnitId: teamUnitId });
  await assignToCrew({ employeeId: viaAssignment, orgUnitId: teamUnitId, crewId: crew.id });
  await insertEmployee({ orgUnitId: teamUnitId, crewId: crew.id }); // default crew only
  await insertEmployee({ orgUnitId: teamUnitId, crewId: crew.id, isActive: false }); // never counts

  // An Employee whose default is this crew but whose current assignment names
  // another crew belongs to the other crew, not this one.
  const moved = await insertEmployee({ orgUnitId: teamUnitId, crewId: crew.id });
  await assignToCrew({ employeeId: moved, orgUnitId: teamUnitId, crewId: otherCrew.id });

  const listed = await call(admin, `/api/people/sites/${siteId}/crews`);
  assert.strictEqual(listed.status, 200, JSON.stringify(listed.payload));
  assert.deepStrictEqual(listed.payload.crews.map((row) => row.code), [crew.code, otherCrew.code]);
  const [alpha, beta] = listed.payload.crews;
  assert.deepStrictEqual(alpha, {
    id: String(crew.id),
    siteId: String(siteId),
    code: crew.code,
    name: 'Crew Alpha',
    isActive: true,
    employeeCount: 2
  });
  assert.strictEqual(beta.employeeCount, 1);
  assert.strictEqual(listed.payload.truncated, false);
});

test('the crew list search filters on code or name, and treats a percent sign literally', async () => {
  const { siteId } = await stageSite();
  const welding = await insertCrew({ siteId, code: unique('WLD'), name: 'Welding Night' });
  const cutting = await insertCrew({ siteId, code: unique('CUT'), name: 'Cutting Day' });

  const byName = await call(admin, `/api/people/sites/${siteId}/crews?search=welding`);
  assert.strictEqual(byName.status, 200, JSON.stringify(byName.payload));
  assert.deepStrictEqual(byName.payload.crews.map((row) => row.id), [String(welding.id)]);

  const byCode = await call(admin, `/api/people/sites/${siteId}/crews?search=${cutting.code.toLowerCase()}`);
  assert.deepStrictEqual(byCode.payload.crews.map((row) => row.id), [String(cutting.id)]);

  const percent = await call(admin, `/api/people/sites/${siteId}/crews?search=%25`);
  assert.deepStrictEqual(percent.payload.crews, []);
});

test('an inactive crew is hidden from the crew list unless includeInactive is true', async () => {
  const { siteId } = await stageSite();
  const live = await insertCrew({ siteId, name: 'Crew Live' });
  const retired = await insertCrew({ siteId, name: 'Crew Retired', isActive: false });

  const hidden = await call(admin, `/api/people/sites/${siteId}/crews`);
  assert.deepStrictEqual(hidden.payload.crews.map((row) => row.id), [String(live.id)]);

  const shown = await call(admin, `/api/people/sites/${siteId}/crews?includeInactive=true`);
  assert.strictEqual(shown.status, 200, JSON.stringify(shown.payload));
  assert.deepStrictEqual(shown.payload.crews.map((row) => row.id).sort(), [String(live.id), String(retired.id)].sort());
  assert.strictEqual(shown.payload.crews.find((row) => row.id === String(retired.id)).isActive, false);
});

test('the crew list is a 404 for an unknown Site and a 403 for an Account without PPL_ORG_UNITS_DISPLAY', async () => {
  const { siteId } = await stageSite();

  const missing = await call(admin, '/api/people/sites/999999999/crews');
  assert.strictEqual(missing.status, 404, JSON.stringify(missing.payload));

  // The Account holds a Grant in the Site, so only the permission is missing.
  // The code is taken off the two groups that carry it for an operator and put
  // back, exactly as it was, in `finally`.
  const operator = await insertAccount({ role: 'operator' });
  const unitId = await insertOrgUnit({ siteId, name: `Reader ${unique('R')}` });
  await insertGrant({ accountId: operator.id, orgUnitId: unitId, canWrite: false });

  const removed = await pool.query(
    `DELETE FROM app_role_permissions rp
      USING app_roles r
      WHERE r.id = rp.app_role_id AND r.code IN ('ROLE_STANDARD', 'ROLE_OPERATOR')
        AND rp.permission_code = 'PPL_ORG_UNITS_DISPLAY'
      RETURNING rp.app_role_id`
  );
  try {
    const refused = await call(operator, `/api/people/sites/${siteId}/crews`);
    assert.strictEqual(refused.status, 403, JSON.stringify(refused.payload));
    assert.strictEqual(refused.payload.permission, 'PPL_ORG_UNITS_DISPLAY');
  } finally {
    for (const row of removed.rows) {
      await pool.query(
        `INSERT INTO app_role_permissions (app_role_id, permission_code)
         VALUES ($1, 'PPL_ORG_UNITS_DISPLAY') ON CONFLICT DO NOTHING`,
        [row.app_role_id]
      );
    }
  }
});

test('assign refuses a crew that reaches nobody with a 400 naming its code, even when the rest of the group reaches people, and creates no Attempt', async () => {
  const { siteId, processUnitId, teamUnitId } = await stageSite();
  const empty = await insertCrew({ siteId, code: unique('DEMO-CREW-Z'), name: 'Crew Z' });
  await insertEmployee({ orgUnitId: teamUnitId, crewId: null });
  // Only an inactive Employee is on the crew: it still reaches nobody.
  await insertEmployee({ orgUnitId: teamUnitId, crewId: empty.id, isActive: false });
  const assessment = await createAssessment(processUnitId);

  const refused = await call(supervisor, `/api/people/assessments/${assessment.id}/assign`, {
    method: 'POST',
    body: { orgUnitIds: [teamUnitId], crewIds: [empty.id] }
  });
  assert.strictEqual(refused.status, 400, JSON.stringify(refused.payload));
  assert.ok(refused.payload.message.includes(empty.code), refused.payload.message);
  assert.ok(refused.payload.message.includes('reaches nobody'), refused.payload.message);
  assert.strictEqual(await attemptCount(assessment.id), 0);

  const unknown = await call(supervisor, `/api/people/assessments/${assessment.id}/assign`, {
    method: 'POST',
    body: { orgUnitIds: [teamUnitId], crewIds: ['999999999'] }
  });
  assert.strictEqual(unknown.status, 400, JSON.stringify(unknown.payload));
  assert.ok(unknown.payload.message.includes('no crew with id 999999999'), unknown.payload.message);
  assert.strictEqual(await attemptCount(assessment.id), 0);
});

test('assign-preview counts a person once across a crew, an Org Unit and a named Employee, and assign creates exactly that many Attempts', async () => {
  const { siteId, processUnitId, teamUnitId } = await stageSite();
  const crew = await insertCrew({ siteId, name: 'Crew Overlap' });
  const elsewhereId = await insertOrgUnit({ siteId, name: `Elsewhere ${unique('E')}` });

  const inBoth = await insertEmployee({ orgUnitId: teamUnitId, crewId: crew.id });   // Org Unit and crew
  const teamOnly = await insertEmployee({ orgUnitId: teamUnitId });                  // Org Unit and named
  const crewOnly = await insertEmployee({ orgUnitId: elsewhereId, crewId: crew.id }); // crew and named
  const assessment = await createAssessment(processUnitId);

  const group = {
    orgUnitIds: [teamUnitId],
    crewIds: [crew.id],
    employeeIds: [teamOnly, crewOnly]
  };
  const preview = await call(
    supervisor,
    `/api/people/assessments/assign-preview?orgUnitIds=${teamUnitId}&crewIds=${crew.id}&employeeIds=${teamOnly},${crewOnly}`
  );
  assert.strictEqual(preview.status, 200, JSON.stringify(preview.payload));
  assert.strictEqual(preview.payload.count, 3, 'three distinct people, though five memberships');
  assert.deepStrictEqual(
    preview.payload.employees.map((row) => String(row.employeeId)).sort(),
    [inBoth, teamOnly, crewOnly].map(String).sort()
  );

  const assigned = await call(supervisor, `/api/people/assessments/${assessment.id}/assign`, {
    method: 'POST',
    body: group
  });
  assert.strictEqual(assigned.status, 201, JSON.stringify(assigned.payload));
  assert.strictEqual(assigned.payload.assigned, 3);
  assert.strictEqual(await attemptCount(assessment.id), 3);
});
