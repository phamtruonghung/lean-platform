/*
 * The People write retrofit (ADR-0061, slice 5b), measured over HTTP against a
 * real database and a real local session — the same seam
 * people-permission-roles.test.js, training.test.js, attendance.test.js and
 * leave-requests.test.js use.
 *
 * Why this file exists. The rest of the People suite builds its writers as
 * administrators or supervisors, and a narrower gate that admitted only
 * administrators would leave them all green. Each half of the card's claim is
 * asserted here as the Account that would notice:
 *
 *   1. the **managing** side — a supervisor holding an edit Grant raises a
 *      Training record, confirms an Attendance sheet and approves a leave
 *      request, and an operator holding the very same Grant is refused each of
 *      them with `PERMISSION_REQUIRED` and the code named;
 *   2. the **self-service** side — an operator still answers their own training
 *      question and raises (and cancels) their own leave request, because
 *      `PPL_TRAINING_ANSWER_OWN` and `PPL_LEAVE_REQUESTS_RAISE` are seeded on
 *      every role. Those two routes answer every Account by construction, so
 *      the last tests remove each code from every role and watch exactly its own
 *      address start refusing — that is what proves the gates are wired rather
 *      than absent.
 *
 * A third thing is checked along the way: the code is a door, not the identity
 * rule. An operator answering somebody else's Trainee row is refused with the
 * identity sentence, not the permission one — no code makes an answer someone
 * else's to give.
 *
 * Needs a database with every migration applied, including
 * 1803600000000_self-service-people-codes.js. Set DATABASE_URL first.
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
const insertedShiftDefinitionIds = [];
const insertedShiftInstanceIds = [];
const insertedTrainingRecordIds = [];
const insertedLeaveRequestIds = [];

let counter = 0;
function uniqueCode(prefix) {
  counter += 1;
  return `${prefix}${process.pid}${counter}`;
}

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

async function insertAccount({ role = 'operator', grants = [], employeeId = null } = {}) {
  const subject = uniqueCode('pwacct');
  const { rows: [account] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status, employee_id)
     VALUES ($1, $2, $3, $4, TRUE, 'approved', $5) RETURNING id`,
    [`${subject}@example.com`, `People Write ${subject}`, role, subject, employeeId]
  );
  insertedAccountIds.push(account.id);

  for (const grant of grants) {
    await pool.query(
      `INSERT INTO app_user_org_units (app_user_id, org_unit_id, can_write) VALUES ($1, $2, $3)`,
      [account.id, grant.orgUnitId, grant.write ?? false]
    );
  }

  return { id: account.id, role, token: await authHeader(subject) };
}

async function insertSite() {
  const { rows: [site] } = await pool.query(
    `INSERT INTO sites (code, name, timezone) VALUES ($1, 'People Write Test Site', 'Asia/Ho_Chi_Minh') RETURNING id`,
    [uniqueCode('PWS')]
  );
  insertedSiteIds.push(site.id);
  return site;
}

async function insertOrgUnit(siteId) {
  const { rows: [orgUnit] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, NULL, $2, 'People Write Area', 'area') RETURNING id`,
    [siteId, uniqueCode('PWOU')]
  );
  insertedOrgUnitIds.push(orgUnit.id);
  return orgUnit;
}

async function insertEmployee({ orgUnitId = null } = {}) {
  const { rows: [employee] } = await pool.query(
    `INSERT INTO employees (employee_no, first_name, last_name, is_active, default_org_unit_id)
     VALUES ($1, 'People', 'Write', TRUE, $2) RETURNING id`,
    [uniqueCode('PWEMP'), orgUnitId]
  );
  insertedEmployeeIds.push(employee.id);
  return employee;
}

async function insertShiftDefinition(siteId) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO shift_definitions (site_id, code, name, start_time, duration_minutes, break_minutes)
     VALUES ($1, $2, 'Day shift', '06:00', 480, 30) RETURNING id`,
    [siteId, uniqueCode('PWSD')]
  );
  insertedShiftDefinitionIds.push(row.id);
  return row;
}

async function insertShiftInstance(siteId, orgUnitId, shiftDefinitionId) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO shift_instances
       (site_id, org_unit_id, shift_definition_id, crew_id, production_date,
        starts_at, ends_at, planned_production_minutes)
     VALUES ($1, $2, $3, NULL, '2026-05-04',
             '2026-05-04T06:00:00Z', '2026-05-04T14:00:00Z', 450)
     RETURNING id`,
    [siteId, orgUnitId, shiftDefinitionId]
  );
  insertedShiftInstanceIds.push(row.id);
  return row;
}

async function post(path, token, body) {
  const response = await fetch(`${base}${path}`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body ?? {})
  });
  return json(response);
}

let adminToken;
let operator;
let supervisor;
let site;
let area;
let operatorEmployee;
let otherEmployee;
let trainerEmployee;
let shiftInstance;
let absenceReasonId;

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
  trainerEmployee = await insertEmployee({ orgUnitId: area.id });

  // Both hold an edit Grant on the very same Org Unit. The only difference
  // between them is the role, which is exactly what the codes answer.
  operator = await insertAccount({
    role: 'operator',
    employeeId: operatorEmployee.id,
    grants: [{ orgUnitId: area.id, write: true }]
  });
  supervisor = await insertAccount({
    role: 'supervisor',
    grants: [{ orgUnitId: area.id, write: true }]
  });

  const shiftDefinition = await insertShiftDefinition(site.id);
  shiftInstance = await insertShiftInstance(site.id, area.id, shiftDefinition.id);

  const { rows: [reason] } = await pool.query(
    'SELECT id FROM absence_reasons WHERE is_requestable AND is_active ORDER BY id LIMIT 1'
  );
  absenceReasonId = reason.id;
});

test.after(async () => {
  await pool.query('DELETE FROM leave_requests WHERE id = ANY($1)', [insertedLeaveRequestIds]);
  await pool.query('DELETE FROM training_records WHERE id = ANY($1)', [insertedTrainingRecordIds]);
  await pool.query('DELETE FROM attendance_records WHERE shift_instance_id = ANY($1)', [insertedShiftInstanceIds]);
  await pool.query('DELETE FROM attendance_sheets WHERE shift_instance_id = ANY($1)', [insertedShiftInstanceIds]);
  await pool.query('DELETE FROM shift_instances WHERE id = ANY($1)', [insertedShiftInstanceIds]);
  await pool.query('DELETE FROM shift_definitions WHERE id = ANY($1)', [insertedShiftDefinitionIds]);
  await pool.query('DELETE FROM app_user_org_units WHERE app_user_id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM account_sessions WHERE app_user_id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM app_users WHERE id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM employees WHERE id = ANY($1)', [insertedEmployeeIds]);
  await pool.query('DELETE FROM org_units WHERE id = ANY($1)', [insertedOrgUnitIds]);
  await pool.query('DELETE FROM sites WHERE id = ANY($1)', [insertedSiteIds]);
  await new Promise((resolve) => server.close(resolve));
  await closePool();
});

// A draft Training record with one Trainee, raised and sent as the
// administrator: the fixture the answer tests need, not a thing under test.
async function sentRecordWithTrainee(employeeId) {
  const raised = await post('/api/people/training', adminToken, {
    orgUnitId: area.id,
    title: 'Lockout / tagout refresher',
    trainedOn: '2026-03-10',
    durationHours: 1.5,
    trainerEmployeeId: trainerEmployee.id,
    objective: 'Name the isolation points on the press.'
  });
  assert.strictEqual(raised.status, 201, JSON.stringify(raised.body));
  const recordId = raised.body.trainingRecord.id;
  insertedTrainingRecordIds.push(recordId);

  const added = await post(`/api/people/training/${recordId}/trainees`, adminToken, { employeeId });
  assert.strictEqual(added.status, 201, JSON.stringify(added.body));
  const trainee = added.body.trainingRecord.trainees.find((row) => String(row.employeeId) === String(employeeId));

  const sent = await post(`/api/people/training/${recordId}/send`, adminToken, {});
  assert.strictEqual(sent.status, 200, JSON.stringify(sent.body));
  return { recordId, traineeId: trainee.id };
}

// ---------------------------------------------------------------------------
// The managing writes: the code is the door, the Grant is still what confines it
// ---------------------------------------------------------------------------

test('a supervisor raises a Training record, confirms an Attendance sheet and approves a leave request; an operator holding the same Grant is refused each by code', async () => {
  // Training: supervisor 201, operator 403 naming PPL_TRAINING_CHANGE.
  const supervisorTraining = await post('/api/people/training', supervisor.token, {
    orgUnitId: area.id,
    title: 'Raised by a supervisor',
    trainedOn: '2026-04-01',
    durationHours: 1
  });
  assert.strictEqual(supervisorTraining.status, 201, JSON.stringify(supervisorTraining.body));
  insertedTrainingRecordIds.push(supervisorTraining.body.trainingRecord.id);

  const operatorTraining = await post('/api/people/training', operator.token, {
    orgUnitId: area.id,
    title: 'Refused: an operator holds no TRAINING_CHANGE',
    trainedOn: '2026-04-01',
    durationHours: 1
  });
  assert.strictEqual(operatorTraining.status, 403, JSON.stringify(operatorTraining.body));
  assert.strictEqual(operatorTraining.body.code, 'PERMISSION_REQUIRED');
  assert.strictEqual(operatorTraining.body.permission, 'PPL_TRAINING_CHANGE');

  // Attendance: operator refused first (nothing is written), supervisor confirms.
  const operatorConfirm = await post(
    `/api/people/shift-instances/${shiftInstance.id}/attendance-sheet/confirm`,
    operator.token,
    {}
  );
  assert.strictEqual(operatorConfirm.status, 403, JSON.stringify(operatorConfirm.body));
  assert.strictEqual(operatorConfirm.body.permission, 'PPL_ATTENDANCE_CHANGE');

  const supervisorConfirm = await post(
    `/api/people/shift-instances/${shiftInstance.id}/attendance-sheet/confirm`,
    supervisor.token,
    {}
  );
  assert.strictEqual(supervisorConfirm.status, 200, JSON.stringify(supervisorConfirm.body));
  assert.ok(supervisorConfirm.body.sheet.confirmedAt);

  // Leave: the operator raises one for somebody else (its RAISE code allows
  // that), cannot approve it, and the supervisor does.
  const raised = await post('/api/people/leave-requests', operator.token, {
    employeeId: otherEmployee.id,
    absenceReasonId,
    startsOn: '2026-06-01',
    endsOn: '2026-06-02',
    note: 'Recorded on behalf of an Employee who cannot sign in.'
  });
  assert.strictEqual(raised.status, 201, JSON.stringify(raised.body));
  const leaveRequestId = raised.body.leaveRequest.id;
  insertedLeaveRequestIds.push(leaveRequestId);

  const operatorApprove = await post(`/api/people/leave-requests/${leaveRequestId}/approve`, operator.token, {
    note: 'Should not be possible.'
  });
  assert.strictEqual(operatorApprove.status, 403, JSON.stringify(operatorApprove.body));
  assert.strictEqual(operatorApprove.body.permission, 'PPL_LEAVE_REQUESTS_DECIDE');

  const supervisorApprove = await post(`/api/people/leave-requests/${leaveRequestId}/approve`, supervisor.token, {
    note: 'Approved by a supervisor.'
  });
  assert.strictEqual(supervisorApprove.status, 200, JSON.stringify(supervisorApprove.body));
  assert.strictEqual(supervisorApprove.body.leaveRequest.status, 'approved');
});

// ---------------------------------------------------------------------------
// The self-service writes: every role holds the code, so the person keeps the act
// ---------------------------------------------------------------------------

test('an operator answers their own training question, and an operator answering somebody else is refused by identity, not by code', async () => {
  const own = await sentRecordWithTrainee(operatorEmployee.id);
  const answered = await post(`/api/people/training/trainees/${own.traineeId}/answer`, operator.token, {
    answer: 'confirmed'
  });
  assert.strictEqual(answered.status, 200, JSON.stringify(answered.body));

  // A second record whose Trainee is somebody else: the code is held, and the
  // identity rule is what refuses — the sentence, not PERMISSION_REQUIRED.
  const someoneElses = await sentRecordWithTrainee(otherEmployee.id);
  const refused = await post(`/api/people/training/trainees/${someoneElses.traineeId}/answer`, operator.token, {
    answer: 'confirmed'
  });
  assert.strictEqual(refused.status, 403, JSON.stringify(refused.body));
  assert.strictEqual(refused.body.code, undefined);
  assert.match(refused.body.message, /Only the Trainee can answer for themselves/);
});

test('an operator raises and cancels their own leave request', async () => {
  const raised = await post('/api/people/leave-requests', operator.token, {
    absenceReasonId,
    startsOn: '2026-07-01',
    endsOn: '2026-07-02',
    note: 'My own leave.'
  });
  assert.strictEqual(raised.status, 201, JSON.stringify(raised.body));
  insertedLeaveRequestIds.push(raised.body.leaveRequest.id);

  const cancelled = await post(`/api/people/leave-requests/${raised.body.leaveRequest.id}/cancel`, operator.token, {});
  assert.strictEqual(cancelled.status, 200, JSON.stringify(cancelled.body));
  assert.strictEqual(cancelled.body.leaveRequest.status, 'cancelled');
});

// ---------------------------------------------------------------------------
// And the self-service gates are wired at all. Each code is removed from every
// role that holds it, its own address refuses, and restoring it admits again.
// ---------------------------------------------------------------------------

async function removeCodeEverywhere(code) {
  const { rows } = await pool.query(
    'SELECT app_role_id FROM app_role_permissions WHERE permission_code = $1',
    [code]
  );
  assert.strictEqual(rows.length, 6, `${code} must be seeded on all six roles`);
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

test('removing PPL_TRAINING_ANSWER_OWN refuses the Trainee their own answer and nothing else', async () => {
  const { traineeId } = await sentRecordWithTrainee(operatorEmployee.id);

  const roleIds = await removeCodeEverywhere('PPL_TRAINING_ANSWER_OWN');
  try {
    const refused = await post(`/api/people/training/trainees/${traineeId}/answer`, operator.token, {
      answer: 'confirmed'
    });
    assert.strictEqual(refused.status, 403, JSON.stringify(refused.body));
    assert.strictEqual(refused.body.code, 'PERMISSION_REQUIRED');
    assert.strictEqual(refused.body.permission, 'PPL_TRAINING_ANSWER_OWN');

    // The register read is a different door and stays open.
    const register = await fetch(`${base}/api/people/training`, { headers: operator.token });
    assert.strictEqual(register.status, 200);
  } finally {
    await restoreCodeEverywhere(roleIds, 'PPL_TRAINING_ANSWER_OWN');
  }

  const allowed = await post(`/api/people/training/trainees/${traineeId}/answer`, operator.token, {
    answer: 'confirmed'
  });
  assert.strictEqual(allowed.status, 200, JSON.stringify(allowed.body));
});

test('removing PPL_LEAVE_REQUESTS_RAISE refuses raising and one\'s own cancellation, and leaves deciding alone', async () => {
  const pending = await post('/api/people/leave-requests', operator.token, {
    employeeId: otherEmployee.id,
    absenceReasonId,
    startsOn: '2026-08-01',
    endsOn: '2026-08-02'
  });
  assert.strictEqual(pending.status, 201, JSON.stringify(pending.body));
  const pendingId = pending.body.leaveRequest.id;
  insertedLeaveRequestIds.push(pendingId);

  const roleIds = await removeCodeEverywhere('PPL_LEAVE_REQUESTS_RAISE');
  try {
    const refusedRaise = await post('/api/people/leave-requests', operator.token, {
      absenceReasonId,
      startsOn: '2026-08-10',
      endsOn: '2026-08-11'
    });
    assert.strictEqual(refusedRaise.status, 403, JSON.stringify(refusedRaise.body));
    assert.strictEqual(refusedRaise.body.permission, 'PPL_LEAVE_REQUESTS_RAISE');

    const refusedCancel = await post(`/api/people/leave-requests/${pendingId}/cancel`, operator.token, {});
    assert.strictEqual(refusedCancel.status, 403, JSON.stringify(refusedCancel.body));
    assert.strictEqual(refusedCancel.body.permission, 'PPL_LEAVE_REQUESTS_RAISE');

    // The supervisor's decision door is the other code and still opens.
    const decided = await post(`/api/people/leave-requests/${pendingId}/approve`, supervisor.token, {});
    assert.strictEqual(decided.status, 200, JSON.stringify(decided.body));
  } finally {
    await restoreCodeEverywhere(roleIds, 'PPL_LEAVE_REQUESTS_RAISE');
  }
});

// A quick guard on the write shape this file relies on: the two managing codes
// stay supervisor-and-above, so the operator's refusals above are the seed's
// doing and not a Grant problem.
test('the managing codes are held by a supervisor and not by an operator', async () => {
  const me = await fetch(`${base}/api/people/me`, { headers: operator.token });
  const operatorPermissions = (await me.json()).permissions;
  assert.ok(!operatorPermissions.includes('PPL_TRAINING_CHANGE'));
  assert.ok(!operatorPermissions.includes('PPL_ATTENDANCE_CHANGE'));
  assert.ok(!operatorPermissions.includes('PPL_LEAVE_REQUESTS_DECIDE'));
  assert.ok(operatorPermissions.includes('PPL_TRAINING_ANSWER_OWN'));
  assert.ok(operatorPermissions.includes('PPL_LEAVE_REQUESTS_RAISE'));

  const supervisorMe = await fetch(`${base}/api/people/me`, { headers: supervisor.token });
  const supervisorPermissions = (await supervisorMe.json()).permissions;
  assert.ok(supervisorPermissions.includes('PPL_TRAINING_CHANGE'));
  assert.ok(supervisorPermissions.includes('PPL_ATTENDANCE_CHANGE'));
  assert.ok(supervisorPermissions.includes('PPL_LEAVE_REQUESTS_DECIDE'));
  assert.ok(supervisorPermissions.includes('PPL_TRAINING_ANSWER_OWN'));
  assert.ok(supervisorPermissions.includes('PPL_LEAVE_REQUESTS_RAISE'));
});
