/*
 * The People retrofit (ADR-0061, issue #509) keeps the audience every route had
 * before it — measured over HTTP against a real database and a real local
 * session, the same seam directory.test.js, attendance.test.js and
 * leave-requests.test.js use.
 *
 * Why this file exists. Every code the retrofit added to a read is seeded on
 * ROLE_STANDARD, the default group every approved Account carries, so "the
 * existing suite still passes" cannot on its own show the gates refused nobody:
 * a read gate that only admitted supervisors would leave that suite green. And
 * the routes this round left on their standing — every Attendance, Training and
 * leave-transition write, the Org Unit assignment, the two cost catalogues'
 * reads — must still admit who they admitted before, which is the other half of
 * "behaviour changes for nobody".
 *
 * So both questions are asked here as the Account that would notice first: an
 * `operator`, holding the default group and an edit Grant on its own area. The
 * administrator-only half is measured on an `admin` beside it, and the last three
 * tests go the other way and prove the gates are wired at all, by removing one
 * code from every role and watching exactly its own addresses start refusing.
 *
 * ADR-0061's slice 5b then gated the People writes: the Attendance, Training and
 * leave-decision routes ask their managing codes, which are supervisor-and-above,
 * while the two self-service acts — answering one's own training question and
 * raising one's own leave request — ask codes every role holds. Both halves are
 * measured here as the same operator and a `supervisor` beside it;
 * people-self-service-permission-roles.test.js carries the same proof written
 * round the card's own acceptance list.
 *
 * Needs a database with every migration applied, including
 * 1803400000000_permissions-and-roles.js. Set DATABASE_URL first.
 */

const test = require('node:test');
const assert = require('node:assert');
const { tokenFor } = require('../helpers/session');

let server;
let base;
let pool;
let closePool;

const insertedAccountIds = [];
const insertedSiteIds = [];
const insertedOrgUnitIds = [];
const insertedEmployeeIds = [];
const insertedCrewIds = [];
const insertedShiftDefinitionIds = [];
const insertedShiftInstanceIds = [];
const insertedJobRoleIds = [];
const insertedSkillIds = [];
const insertedTrainingRecordIds = [];
const insertedLeaveRequestIds = [];
const insertedAssignmentIds = [];

let counter = 0;
function uniqueCode(prefix) {
  counter += 1;
  return `${prefix}${process.pid}${counter}`;
}

// A 1 x 1 PNG: the magic bytes and IHDR chunk signatures.decodeImage checks,
// with a real width and height of 1. Its content is never displayed here.
const ONE_PIXEL_PNG =
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8AAAwAB/gAB/wMKAAAAAElFTkSuQmCC';

async function authHeader(subject) {
  const token = await tokenFor(subject);
  return { authorization: 'Bearer ' + token };
}

async function json(response) {
  return { status: response.status, body: await response.json().catch(() => null) };
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

// `grants` are `{ orgUnitId, write }` pairs; `write` defaults to false so a test
// says exactly which standing it is granting.
async function insertAccount({ role = 'operator', grants = [], employeeId = null } = {}) {
  const subject = uniqueCode('ppacct');
  const { rows: [account] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status, employee_id)
     VALUES ($1, $2, $3, $4, TRUE, 'approved', $5) RETURNING id`,
    [`${subject}@example.com`, `People Permission ${subject}`, role, subject, employeeId]
  );
  insertedAccountIds.push(account.id);

  for (const grant of grants) {
    await pool.query(
      `INSERT INTO app_user_org_units (app_user_id, org_unit_id, can_write)
       VALUES ($1, $2, $3)`,
      [account.id, grant.orgUnitId, grant.write ?? false]
    );
  }

  return { id: account.id, role, token: await authHeader(subject) };
}

async function insertSite() {
  const { rows: [site] } = await pool.query(
    `INSERT INTO sites (code, name, timezone) VALUES ($1, $2, $3) RETURNING id, code, name`,
    [uniqueCode('PPS'), 'People Permission Test Site', 'Asia/Ho_Chi_Minh']
  );
  insertedSiteIds.push(site.id);
  return site;
}

async function insertOrgUnit(siteId, { unitType = 'area', name = 'People Area' } = {}) {
  const { rows: [orgUnit] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, NULL, $2, $3, $4) RETURNING id, code, name, path`,
    [siteId, uniqueCode('PPOU'), name, unitType]
  );
  insertedOrgUnitIds.push(orgUnit.id);
  return orgUnit;
}

async function insertEmployee({ orgUnitId = null, crewId = null }) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO employees (employee_no, first_name, last_name, is_active, default_org_unit_id, default_crew_id)
     VALUES ($1, 'People', 'Employee', TRUE, $2, $3) RETURNING id, employee_no`,
    [uniqueCode('PPEMP'), orgUnitId, crewId]
  );
  insertedEmployeeIds.push(row.id);
  return row;
}

async function insertShiftDefinition(siteId) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO shift_definitions (site_id, code, name, start_time, duration_minutes, break_minutes)
     VALUES ($1, $2, 'Day shift', '06:00', 480, 30)
     RETURNING id, duration_minutes, break_minutes`,
    [siteId, uniqueCode('PPSD')]
  );
  insertedShiftDefinitionIds.push(row.id);
  return row;
}

// Built by hand rather than through `generate_shift_instances`, the same reason
// attendance.test.js's own fixture gives: the generator never sets crew_id.
async function insertShiftInstance(site, orgUnit, shiftDefinition, crewId) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO shift_instances
       (site_id, org_unit_id, shift_definition_id, crew_id, production_date,
        starts_at, ends_at, planned_production_minutes)
     VALUES ($1, $2, $3, $4, '2026-05-04',
             '2026-05-04T06:00:00Z', '2026-05-04T14:00:00Z',
             $5)
     RETURNING id, site_id, org_unit_id`,
    [site.id, orgUnit.id, shiftDefinition.id, crewId, 450]
  );
  insertedShiftInstanceIds.push(row.id);
  return row;
}

async function get(path, token) {
  const response = await fetch(`${base}${path}`, { headers: token });
  return json(response);
}

async function post(path, token, body) {
  const response = await fetch(`${base}${path}`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body ?? {})
  });
  if (path.startsWith('/api/people/training') && response.status === 201) {
    const payload = await response.clone().json().catch(() => null);
    if (payload?.trainingRecord?.id) insertedTrainingRecordIds.push(payload.trainingRecord.id);
  }
  if (path === '/api/people/leave-requests' && response.status === 201) {
    const payload = await response.clone().json().catch(() => null);
    if (payload?.leaveRequest?.id) insertedLeaveRequestIds.push(payload.leaveRequest.id);
  }
  if (path.endsWith('/assignments') && response.status === 201) {
    const payload = await response.clone().json().catch(() => null);
    if (payload?.assignment?.id) insertedAssignmentIds.push(payload.assignment.id);
  }
  return json(response);
}

async function patch(path, token, body) {
  const response = await fetch(`${base}${path}`, {
    method: 'PATCH',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body ?? {})
  });
  return json(response);
}

async function put(path, token, body) {
  const response = await fetch(`${base}${path}`, {
    method: 'PUT',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body ?? {})
  });
  return json(response);
}

let adminToken;
let operator; // role operator: the default group, an edit Grant on its own area.
let site;
let area;
let operatorEmployee;
let otherEmployee;
let shiftInstance;
let absenceReasonId;
let skillId;
let trainingRecordId;

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

  site = await insertSite();
  area = await insertOrgUnit(site.id);

  const admin = await insertAccount({ role: 'admin' });
  adminToken = admin.token;

  operatorEmployee = await insertEmployee({ orgUnitId: area.id });
  otherEmployee = await insertEmployee({ orgUnitId: area.id });

  operator = await insertAccount({
    role: 'operator',
    employeeId: operatorEmployee.id,
    grants: [{ orgUnitId: area.id, write: true }]
  });

  const crew = await pool.query(
    `INSERT INTO crews (site_id, code, name) VALUES ($1, $2, 'Crew A') RETURNING id`,
    [site.id, uniqueCode('PPCR')]
  );
  insertedCrewIds.push(crew.rows[0].id);
  const shiftDefinition = await insertShiftDefinition(site.id);
  shiftInstance = await insertShiftInstance(site, area, shiftDefinition, crew.rows[0].id);

  const { rows: [reason] } = await pool.query('SELECT id FROM absence_reasons ORDER BY id LIMIT 1');
  absenceReasonId = reason.id;

  // One Skill and one Training record, created through the API as the
  // administrator the codes allow — so this file measures the retrofit rather
  // than hand-made rows.
  const skill = await post('/api/people/skills', adminToken, {
    code: uniqueCode('PPSK'),
    name: 'Press operation',
    skillCategory: 'operation'
  });
  assert.strictEqual(skill.status, 201, JSON.stringify(skill.body));
  skillId = skill.body.skill.id;
  insertedSkillIds.push(skillId);

  const training = await post('/api/people/training', adminToken, {
    orgUnitId: area.id,
    title: 'Lockout / tagout refresher',
    trainedOn: '2026-03-10',
    durationHours: 1.5
  });
  assert.strictEqual(training.status, 201, JSON.stringify(training.body));
  trainingRecordId = training.body.trainingRecord.id;
});

test.after(async () => {
  // Children before parents, FK-safe order. A rejected `test.after` hangs the
  // file on the framework's timeout and cancels the files behind it.
  await pool.query('DELETE FROM leave_requests WHERE id = ANY($1)', [insertedLeaveRequestIds]);
  await pool.query('DELETE FROM employee_assignments WHERE id = ANY($1)', [insertedAssignmentIds]);
  await pool.query('DELETE FROM training_records WHERE id = ANY($1)', [insertedTrainingRecordIds]);
  await pool.query('DELETE FROM employee_skills WHERE employee_id = ANY($1)', [insertedEmployeeIds]);
  await pool.query('DELETE FROM skills WHERE id = ANY($1)', [insertedSkillIds]);
  await pool.query('DELETE FROM employee_signatures WHERE employee_id = ANY($1)', [insertedEmployeeIds]);
  await pool.query('DELETE FROM attendance_records WHERE shift_instance_id = ANY($1)', [insertedShiftInstanceIds]);
  await pool.query('DELETE FROM attendance_sheets WHERE shift_instance_id = ANY($1)', [insertedShiftInstanceIds]);
  await pool.query('DELETE FROM shift_instances WHERE id = ANY($1)', [insertedShiftInstanceIds]);
  await pool.query('DELETE FROM shift_definitions WHERE id = ANY($1)', [insertedShiftDefinitionIds]);
  await pool.query('DELETE FROM crews WHERE id = ANY($1)', [insertedCrewIds]);
  await pool.query('DELETE FROM app_user_org_units WHERE app_user_id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM account_sessions WHERE app_user_id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM app_users WHERE id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM employees WHERE id = ANY($1)', [insertedEmployeeIds]);
  await pool.query('DELETE FROM job_roles WHERE id = ANY($1)', [insertedJobRoleIds]);
  await pool.query('DELETE FROM org_units WHERE id = ANY($1)', [insertedOrgUnitIds]);
  await pool.query('DELETE FROM sites WHERE id = ANY($1)', [insertedSiteIds]);
  await new Promise((resolve) => server.close(resolve));
  await closePool();
});

// ---------------------------------------------------------------------------
// The premise the retrofit rests on, executed rather than asserted: an Account
// holding the default group alone really does hold every code the gates ask,
// and none of the codes the findings would have asked.
// ---------------------------------------------------------------------------

const retrofittedCodes = [
  'PPL_DIRECTORY_DISPLAY',
  'PPL_JOB_ROLES_DISPLAY',
  'PPL_SKILLS_DISPLAY',
  'PPL_ATTENDANCE_DISPLAY',
  'PPL_TRAINING_DISPLAY',
  'PPL_TRAINING_ANSWER_OWN',
  'PPL_LEAVE_REQUESTS_DISPLAY',
  'PPL_LEAVE_REQUESTS_RAISE',
  'PPL_SIGNATURE_OWN'
];

const findingCodes = [
  'PPL_DIRECTORY_CHANGE',
  'PPL_SKILLS_CHANGE',
  'PPL_ATTENDANCE_CHANGE',
  'PPL_TRAINING_CHANGE',
  'PPL_LEAVE_REQUESTS_DECIDE',
  'PPL_COST_RATES_MAINTAIN',
  'PPL_PRODUCT_COSTS_MAINTAIN',
  'INS_SKILL_COVERAGE_DISPLAY'
];

test('an operator holds every code the retrofit asks, and none of the codes the findings would ask', async () => {
  const { status, body } = await get('/api/people/me', operator.token);
  assert.strictEqual(status, 200, JSON.stringify(body));

  for (const code of retrofittedCodes) {
    assert.ok(body.permissions.includes(code), `an operator must hold ${code}`);
  }

  // The findings, measured: each of these is seeded administrator-only or
  // supervisor-and-above, while the routes the retrofit left ungated admit a
  // role holding an edit Grant — this operator.
  for (const code of findingCodes) {
    assert.ok(!body.permissions.includes(code), `an operator must NOT hold ${code}`);
  }
});

// ---------------------------------------------------------------------------
// Every read the retrofit gated admits the operator, unchanged. One request per
// route, the whole pass/fail set in one place.
// ---------------------------------------------------------------------------

test('every retrofitted read answers an operator exactly as it did before', async () => {
  const reads = [
    ['/api/people/employees', 200],
    ['/api/people/employees/me', 200],
    ['/api/people/employees/assignee-candidates', 200],
    [`/api/people/employees/${operatorEmployee.id}`, 200],
    ['/api/people/job-roles', 200],
    ['/api/people/skills', 200],
    [`/api/people/skills/${skillId}/qualified-employees?orgUnitId=${area.id}`, 200],
    ['/api/people/absence-reasons', 200],
    ['/api/people/attendance-to-confirm', 200],
    [`/api/people/employees/${operatorEmployee.id}/work-hours`, 200],
    [`/api/people/org-units/${area.id}/shift-instances?date=2026-05-04`, 200],
    [`/api/people/shift-instances/${shiftInstance.id}/attendance-sheet`, 200],
    ['/api/people/training', 200],
    [`/api/people/training/${trainingRecordId}`, 200],
    ['/api/people/training/to-confirm', 200],
    ['/api/people/leave-requests', 200],
    // The two catalogue reads are ungated on purpose (a finding): the
    // resolution read is how a non-administrator sees the cost the tier board
    // already shows them.
    ['/api/people/cost-rates', 200],
    ['/api/people/cost-rates/scopes', 200],
    [`/api/people/cost-rates/resolution?orgUnitId=${area.id}&rateType=labor_per_hour&at=2026-05-04`, 200],
    ['/api/people/product-costs', 200],
    ['/api/people/product-costs/products', 200]
  ];

  for (const [path, expected] of reads) {
    const { status, body } = await get(path, operator.token);
    assert.strictEqual(status, expected, `${path}: ${JSON.stringify(body)}`);
  }
});

// ---------------------------------------------------------------------------
// The self-service half of the signature trap: PPL_SIGNATURE_OWN is held by
// every role, so an operator keeps their own mark and is refused nothing there.
// ---------------------------------------------------------------------------

test('an operator keeps their own signature: PUT, GET and DELETE /me/signature are all admitted', async () => {
  const saved = await put('/api/people/me/signature', operator.token, { image: ONE_PIXEL_PNG });
  assert.strictEqual(saved.status, 200, JSON.stringify(saved.body));

  const read = await fetch(`${base}/api/people/me/signature`, { headers: operator.token });
  assert.strictEqual(read.status, 200);
  assert.strictEqual(read.headers.get('content-type'), 'image/png');

  const removed = await fetch(`${base}/api/people/me/signature`, {
    method: 'DELETE',
    headers: operator.token
  });
  assert.strictEqual(removed.status, 204);
});

// ---------------------------------------------------------------------------
// The administrator's half: the same eight routes refuse the operator with a
// PERMISSION_REQUIRED naming the code, and admit the administrator. The
// signature admin door asks PPL_DIRECTORY_CHANGE, never PPL_SIGNATURE_OWN.
// ---------------------------------------------------------------------------

test('the administrator-only routes refuse an operator with the code and admit an administrator', async () => {
  const employeeBody = { employeeNo: uniqueCode('PPWEMP'), firstName: 'Ada', lastName: 'Admin' };

  const refusedCreate = await post('/api/people/employees', operator.token, employeeBody);
  assert.strictEqual(refusedCreate.status, 403, JSON.stringify(refusedCreate.body));
  assert.strictEqual(refusedCreate.body.code, 'PERMISSION_REQUIRED');
  assert.strictEqual(refusedCreate.body.permission, 'PPL_DIRECTORY_CHANGE');

  const refusedPatch = await patch(`/api/people/employees/${otherEmployee.id}`, operator.token, {
    firstName: 'Nope'
  });
  assert.strictEqual(refusedPatch.status, 403, JSON.stringify(refusedPatch.body));
  assert.strictEqual(refusedPatch.body.permission, 'PPL_DIRECTORY_CHANGE');

  const refusedJobRole = await post('/api/people/job-roles', operator.token, {
    code: uniqueCode('PPJR'),
    name: 'Refused role'
  });
  assert.strictEqual(refusedJobRole.status, 403, JSON.stringify(refusedJobRole.body));
  assert.strictEqual(refusedJobRole.body.permission, 'PPL_JOB_ROLES_CHANGE');

  const refusedSkill = await post('/api/people/skills', operator.token, {
    code: uniqueCode('PPSK'),
    name: 'Refused skill'
  });
  assert.strictEqual(refusedSkill.status, 403, JSON.stringify(refusedSkill.body));
  assert.strictEqual(refusedSkill.body.permission, 'PPL_SKILLS_CHANGE');

  const refusedEmployeeSkill = await put(
    `/api/people/employees/${operatorEmployee.id}/skills/${skillId}`,
    operator.token,
    { proficiencyLevel: 3 }
  );
  assert.strictEqual(refusedEmployeeSkill.status, 403, JSON.stringify(refusedEmployeeSkill.body));
  assert.strictEqual(refusedEmployeeSkill.body.permission, 'PPL_SKILLS_CHANGE');

  // The Insights code, not the Skills display code: this read was deliberately
  // narrower than a directory read before the retrofit, and stays so.
  const refusedCoverage = await get(`/api/people/sites/${site.id}/skill-coverage`, operator.token);
  assert.strictEqual(refusedCoverage.status, 403, JSON.stringify(refusedCoverage.body));
  assert.strictEqual(refusedCoverage.body.permission, 'INS_SKILL_COVERAGE_DISPLAY');

  const refusedRate = await post('/api/people/cost-rates', operator.token, {
    scopeType: 'site',
    scopeId: site.id,
    rateType: 'labor_per_hour',
    amount: 1,
    effectiveFrom: '2030-01-01'
  });
  assert.strictEqual(refusedRate.status, 403, JSON.stringify(refusedRate.body));
  assert.strictEqual(refusedRate.body.permission, 'PPL_COST_RATES_MAINTAIN');

  const refusedProductCost = await post('/api/people/product-costs', operator.token, {
    productId: 1,
    standardCost: 1,
    effectiveFrom: '2030-01-01'
  });
  assert.strictEqual(refusedProductCost.status, 403, JSON.stringify(refusedProductCost.body));
  assert.strictEqual(refusedProductCost.body.permission, 'PPL_PRODUCT_COSTS_MAINTAIN');

  // The administrator's signature door takes somebody else's Employee id, so it
  // is a directory-maintenance act and asks that code — not the self-service one.
  const refusedSignature = await put(`/api/people/employees/${otherEmployee.id}/signature`, operator.token, {
    image: ONE_PIXEL_PNG
  });
  assert.strictEqual(refusedSignature.status, 403, JSON.stringify(refusedSignature.body));
  assert.strictEqual(refusedSignature.body.permission, 'PPL_DIRECTORY_CHANGE');

  // ...and the same eight admit the administrator.
  const created = await post('/api/people/employees', adminToken, employeeBody);
  assert.strictEqual(created.status, 201, JSON.stringify(created.body));
  insertedEmployeeIds.push(created.body.employee.id);

  const patched = await patch(`/api/people/employees/${created.body.employee.id}`, adminToken, {
    firstName: 'Ada'
  });
  assert.strictEqual(patched.status, 200, JSON.stringify(patched.body));

  const jobRole = await post('/api/people/job-roles', adminToken, {
    code: uniqueCode('PPJR'),
    name: 'Admitted role'
  });
  assert.strictEqual(jobRole.status, 201, JSON.stringify(jobRole.body));
  insertedJobRoleIds.push(jobRole.body.jobRole.id);

  const skill = await post('/api/people/skills', adminToken, {
    code: uniqueCode('PPSK'),
    name: 'Admitted skill',
    skillCategory: 'operation'
  });
  assert.strictEqual(skill.status, 201, JSON.stringify(skill.body));
  insertedSkillIds.push(skill.body.skill.id);

  const employeeSkill = await put(
    `/api/people/employees/${operatorEmployee.id}/skills/${skill.body.skill.id}`,
    adminToken,
    { proficiencyLevel: 3 }
  );
  assert.strictEqual(employeeSkill.status, 200, JSON.stringify(employeeSkill.body));

  const coverage = await get(`/api/people/sites/${site.id}/skill-coverage`, adminToken);
  assert.strictEqual(coverage.status, 200, JSON.stringify(coverage.body));

  const signature = await put(`/api/people/employees/${otherEmployee.id}/signature`, adminToken, {
    image: ONE_PIXEL_PNG
  });
  assert.strictEqual(signature.status, 200, JSON.stringify(signature.body));
});

// ---------------------------------------------------------------------------
// The writes slice 5b narrowed, and the one phase 2d narrowed after it. Each is
// measured as the operator whose edit Grant admitted it before: the code now
// refuses it, and (for the three managing codes slice 5b gated) a supervisor
// holding the same Grant keeps the write.
// ---------------------------------------------------------------------------

test('the managing writes refuse an edit-Grant operator by code, and admit a supervisor holding the same Grant', async () => {
  const training = await post('/api/people/training', operator.token, {
    orgUnitId: area.id,
    title: 'Raised by an operator with an edit Grant',
    trainedOn: '2026-04-01',
    durationHours: 1
  });
  assert.strictEqual(training.status, 403, JSON.stringify(training.body));
  assert.strictEqual(training.body.code, 'PERMISSION_REQUIRED');
  assert.strictEqual(training.body.permission, 'PPL_TRAINING_CHANGE');

  const confirmed = await post(
    `/api/people/shift-instances/${shiftInstance.id}/attendance-sheet/confirm`,
    operator.token,
    {}
  );
  assert.strictEqual(confirmed.status, 403, JSON.stringify(confirmed.body));
  assert.strictEqual(confirmed.body.permission, 'PPL_ATTENDANCE_CHANGE');

  // The assignment write asks `PPL_DIRECTORY_CHANGE` since phase 2d: it stood
  // on the destination's edit Grant alone, which admitted this operator, and
  // directory-routes.js's own header plus the phase 2d PR body state that
  // narrowing. The administrator reaches it; this operator does not.
  const assignment = await post(`/api/people/employees/${otherEmployee.id}/assignments`, operator.token, {
    orgUnitId: area.id
  });
  assert.strictEqual(assignment.status, 403, JSON.stringify(assignment.body));
  assert.strictEqual(assignment.body.code, 'PERMISSION_REQUIRED');
  assert.strictEqual(assignment.body.permission, 'PPL_DIRECTORY_CHANGE');

  // A leave request for somebody else, then the decision on it. Raising asks
  // PPL_LEAVE_REQUESTS_RAISE and this operator holds it; deciding asks
  // PPL_LEAVE_REQUESTS_DECIDE and it does not.
  const request = await post('/api/people/leave-requests', operator.token, {
    employeeId: otherEmployee.id,
    absenceReasonId,
    startsOn: '2026-06-01',
    endsOn: '2026-06-02',
    note: 'Recorded on behalf of an Employee who cannot sign in.'
  });
  assert.strictEqual(request.status, 201, JSON.stringify(request.body));

  const decided = await post(`/api/people/leave-requests/${request.body.leaveRequest.id}/approve`, operator.token, {
    note: 'Approved by the edit-Grant holder.'
  });
  assert.strictEqual(decided.status, 403, JSON.stringify(decided.body));
  assert.strictEqual(decided.body.permission, 'PPL_LEAVE_REQUESTS_DECIDE');

  // The supervisor holds the three managing codes, and the same three writes
  // answer: the seed migration's whole point.
  const supervisor = await insertAccount({
    role: 'supervisor',
    grants: [{ orgUnitId: area.id, write: true }]
  });

  const supervisorTraining = await post('/api/people/training', supervisor.token, {
    orgUnitId: area.id,
    title: 'Raised by a supervisor with an edit Grant',
    trainedOn: '2026-04-01',
    durationHours: 1
  });
  assert.strictEqual(supervisorTraining.status, 201, JSON.stringify(supervisorTraining.body));

  const supervisorConfirmed = await post(
    `/api/people/shift-instances/${shiftInstance.id}/attendance-sheet/confirm`,
    supervisor.token,
    {}
  );
  assert.strictEqual(supervisorConfirmed.status, 200, JSON.stringify(supervisorConfirmed.body));

  const supervisorDecided = await post(
    `/api/people/leave-requests/${request.body.leaveRequest.id}/approve`,
    supervisor.token,
    { note: 'Approved by a supervisor.' }
  );
  assert.strictEqual(supervisorDecided.status, 200, JSON.stringify(supervisorDecided.body));
  assert.strictEqual(supervisorDecided.body.leaveRequest.status, 'approved');
});

// ---------------------------------------------------------------------------
// And the gates are wired at all. Three mutants, each removing one code from
// every role that holds it and watching exactly its own addresses start
// refusing — then putting it back.
//
// Every role that holds it, not just the default group: `effectivePermissions`
// unions the default group, the role the Account's own `app_users.role` earns
// (this operator's is ROLE_OPERATOR) and any explicit assignment, so removing a
// code from ROLE_STANDARD alone would leave the operator holding it through
// ROLE_OPERATOR — and then the mutant would prove nothing.
// ---------------------------------------------------------------------------

async function removeCodeEverywhere(code) {
  const { rows } = await pool.query(
    'SELECT app_role_id FROM app_role_permissions WHERE permission_code = $1',
    [code]
  );
  assert.ok(rows.length > 0, `${code} must be seeded on at least one role`);
  await pool.query('DELETE FROM app_role_permissions WHERE permission_code = $1', [code]);
  return rows.map((row) => row.app_role_id);
}

async function restoreCodeEverywhere(roleIds, code) {
  for (const roleId of roleIds) {
    await pool.query(
      'INSERT INTO app_role_permissions (app_role_id, permission_code) VALUES ($1, $2)',
      [roleId, code]
    );
  }
}

test('removing PPL_TRAINING_DISPLAY from every role refuses the Training reads and nothing else', async () => {
  const roleIds = await removeCodeEverywhere('PPL_TRAINING_DISPLAY');
  try {
    for (const path of ['/api/people/training', `/api/people/training/${trainingRecordId}`, '/api/people/training/to-confirm']) {
      const refused = await get(path, operator.token);
      assert.strictEqual(refused.status, 403, `${path}: ${JSON.stringify(refused.body)}`);
      assert.strictEqual(refused.body.code, 'PERMISSION_REQUIRED');
      assert.strictEqual(refused.body.permission, 'PPL_TRAINING_DISPLAY');
    }

    // Neighbouring gates are untouched: the directory asks its own code, and
    // raising a Training record asks PPL_TRAINING_CHANGE, which nobody removed.
    const directory = await get('/api/people/employees', operator.token);
    assert.strictEqual(directory.status, 200, JSON.stringify(directory.body));

    const raised = await post('/api/people/training', operator.token, {
      orgUnitId: area.id,
      title: 'Raised while the DISPLAY code was removed',
      trainedOn: '2026-04-02',
      durationHours: 1
    });
    assert.strictEqual(raised.status, 403, JSON.stringify(raised.body));
    assert.strictEqual(raised.body.permission, 'PPL_TRAINING_CHANGE');
  } finally {
    await restoreCodeEverywhere(roleIds, 'PPL_TRAINING_DISPLAY');
  }

  // Restored, the same address answers again — the gate reads the tables on
  // every request rather than caching what it saw at sign-in.
  const allowed = await get('/api/people/training', operator.token);
  assert.strictEqual(allowed.status, 200, JSON.stringify(allowed.body));
});

test('removing PPL_DIRECTORY_DISPLAY from every role refuses the Employee reads and nothing else', async () => {
  // Not a CHANGE code: `effectivePermissions` answers every code true for an
  // administrator before any role is read (authorization.js's own note, and the
  // reason the administrator-only codes cannot be mutated from an admin seat),
  // so the only mutants that prove anything are codes a non-administrator holds.
  const roleIds = await removeCodeEverywhere('PPL_DIRECTORY_DISPLAY');
  try {
    for (const path of [
      '/api/people/employees',
      '/api/people/employees/me',
      '/api/people/employees/assignee-candidates',
      `/api/people/employees/${operatorEmployee.id}`
    ]) {
      const refused = await get(path, operator.token);
      assert.strictEqual(refused.status, 403, `${path}: ${JSON.stringify(refused.body)}`);
      assert.strictEqual(refused.body.code, 'PERMISSION_REQUIRED');
      assert.strictEqual(refused.body.permission, 'PPL_DIRECTORY_DISPLAY');
    }

    // Neighbouring gates still answer: the Training register asks its own code,
    // and the caller's own permission list is not a gated route.
    const training = await get('/api/people/training', operator.token);
    assert.strictEqual(training.status, 200, JSON.stringify(training.body));

    const me = await get('/api/people/me', operator.token);
    assert.strictEqual(me.status, 200, JSON.stringify(me.body));
  } finally {
    await restoreCodeEverywhere(roleIds, 'PPL_DIRECTORY_DISPLAY');
  }

  const allowed = await get('/api/people/employees', operator.token);
  assert.strictEqual(allowed.status, 200, JSON.stringify(allowed.body));
});

test('removing PPL_SIGNATURE_OWN refuses a person their own mark, and leaves the administrator door open', async () => {
  const roleIds = await removeCodeEverywhere('PPL_SIGNATURE_OWN');
  try {
    const refused = await put('/api/people/me/signature', operator.token, { image: ONE_PIXEL_PNG });
    assert.strictEqual(refused.status, 403, JSON.stringify(refused.body));
    assert.strictEqual(refused.body.code, 'PERMISSION_REQUIRED');
    assert.strictEqual(refused.body.permission, 'PPL_SIGNATURE_OWN');

    // The administrator's door asks PPL_DIRECTORY_CHANGE, which nobody removed:
    // the two audiences of this file are genuinely separate gates.
    const kept = await put(`/api/people/employees/${otherEmployee.id}/signature`, adminToken, {
      image: ONE_PIXEL_PNG
    });
    assert.strictEqual(kept.status, 200, JSON.stringify(kept.body));
  } finally {
    await restoreCodeEverywhere(roleIds, 'PPL_SIGNATURE_OWN');
  }

  const allowed = await put('/api/people/me/signature', operator.token, { image: ONE_PIXEL_PNG });
  assert.strictEqual(allowed.status, 200, JSON.stringify(allowed.body));
});
