/*
 * Leave requests (issue #265, ADR-0042), over HTTP: an Employee asks for time
 * off, a holder of an edit Grant reaching their Org Unit approves or rejects,
 * and the requester may cancel while it is pending. Same seam as
 * work-hours.test.js and plant.test.js — a real database and a real (locally
 * issued) JWKS, every row inserted by this file and deleted again in
 * `test.after()`, no shared table truncated.
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
let admin;
let site;
let unitA;
let unitB;
let holId;
let sickId;
let lateId;
const insertedSiteIds = [];
const insertedOrgUnitIds = [];
const insertedEmployeeIds = [];
const insertedAccountIds = [];

let counter = 0;
function uniqueCode(prefix) {
  counter += 1;
  return `${prefix}${process.pid}${counter}`;
}

async function authHeader(subject) {
  const token = await jwks.signToken(
    { sub: subject, email: `${subject}@example.com` },
    { issuer: ISSUER, audience: AUDIENCE }
  );
  return { authorization: `Bearer ${token}` };
}

async function json(response) {
  return { status: response.status, body: await response.json() };
}

async function insertAccount({ role = 'operator', grants = [], employeeId = null } = {}) {
  const subject = uniqueCode('lracct');
  const { rows: [account] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status, employee_id)
     VALUES ($1, 'Leave Test Account', $2, $3, TRUE, 'approved', $4) RETURNING id`,
    [`${subject}@example.com`, role, subject, employeeId]
  );
  insertedAccountIds.push(account.id);
  for (const grant of grants) {
    await pool.query(
      `INSERT INTO app_user_org_units (app_user_id, org_unit_id, can_write) VALUES ($1, $2, $3)`,
      [account.id, grant.orgUnitId, grant.write ?? true]
    );
  }
  return { id: account.id, token: await authHeader(subject) };
}

async function insertEmployee({ orgUnitId = null, isActive = true } = {}) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO employees (employee_no, first_name, last_name, is_active, default_org_unit_id)
     VALUES ($1, 'Leave', 'Employee', $2, $3) RETURNING id, employee_no`,
    [uniqueCode('LREMP'), isActive, orgUnitId]
  );
  insertedEmployeeIds.push(row.id);
  return row;
}

async function insertOrgUnit(name) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, NULL, $2, $3, 'area') RETURNING id, name`,
    [site.id, uniqueCode('LROU'), name]
  );
  insertedOrgUnitIds.push(row.id);
  return row;
}

async function call(token, method, path, body) {
  const response = await fetch(`${base}/api/people${path}`, {
    method,
    headers: { ...token, ...(body === undefined ? {} : { 'content-type': 'application/json' }) },
    body: body === undefined ? undefined : JSON.stringify(body)
  });
  return json(response);
}

const submit = (token, body) => call(token, 'POST', '/leave-requests', body);

async function reasonId(code) {
  const { rows: [row] } = await pool.query('SELECT id FROM absence_reasons WHERE code = $1', [code]);
  return row.id;
}

// A pending request for `employee` on behalf of that Employee by an admin.
async function pendingFor(employee, startsOn = '2026-11-02', endsOn = '2026-11-04', extra = {}) {
  const { status, body } = await submit(admin.token, {
    employeeId: employee.id, absenceReasonId: holId, startsOn, endsOn, ...extra
  });
  assert.equal(status, 201);
  return body.leaveRequest;
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

  ({ rows: [site] } = await pool.query(
    `INSERT INTO sites (code, name, timezone) VALUES ($1, 'Leave Test Site', 'Asia/Ho_Chi_Minh') RETURNING id`,
    [uniqueCode('LRS')]
  ));
  insertedSiteIds.push(site.id);
  unitA = await insertOrgUnit('Leave Unit A');
  unitB = await insertOrgUnit('Leave Unit B');

  holId = await reasonId('HOL');
  sickId = await reasonId('SICK');
  lateId = await reasonId('LATE');

  admin = await insertAccount({ role: 'admin' });
});

test.after(async () => {
  await pool.query('DELETE FROM leave_requests WHERE employee_id = ANY($1)', [insertedEmployeeIds]);
  await pool.query('DELETE FROM app_user_org_units WHERE app_user_id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM app_users WHERE id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM employees WHERE id = ANY($1)', [insertedEmployeeIds]);
  await pool.query('DELETE FROM org_units WHERE id = ANY($1)', [insertedOrgUnitIds]);
  await pool.query('DELETE FROM sites WHERE id = ANY($1)', [insertedSiteIds]);
  await new Promise((resolve) => server.close(resolve));
  await closePool();
  await jwks.close();
});

// ---------------------------------------------------------------------------
// Absence reasons
// ---------------------------------------------------------------------------

test('absence reasons report isRequestable and the requestable filter includes HOL, SICK and UNPAID and excludes LATE', async () => {
  const all = await call(admin.token, 'GET', '/absence-reasons');
  assert.equal(all.status, 200);
  const byCode = Object.fromEntries(all.body.absenceReasons.map((r) => [r.code, r]));
  assert.equal(byCode.HOL.isRequestable, true);
  assert.equal(byCode.LATE.isRequestable, false);

  const requestable = await call(admin.token, 'GET', '/absence-reasons?requestable=true');
  const codes = requestable.body.absenceReasons.map((r) => r.code);
  for (const code of ['HOL', 'SICK', 'UNPAID']) assert.ok(codes.includes(code), `${code} should be requestable`);
  assert.ok(!codes.includes('LATE'));
  assert.ok(requestable.body.absenceReasons.every((r) => r.isRequestable === true));
});

// ---------------------------------------------------------------------------
// Submitting
// ---------------------------------------------------------------------------

test('an Employee submits leave for themselves: 201, pending, inclusive days, Org Unit snapshotted', async () => {
  const employee = await insertEmployee({ orgUnitId: unitA.id });
  const me = await insertAccount({ employeeId: employee.id });

  const { status, body } = await submit(me.token, {
    absenceReasonId: holId, startsOn: '2026-12-01', endsOn: '2026-12-05', note: ' Family trip '
  });
  assert.equal(status, 201);
  const lr = body.leaveRequest;
  assert.equal(lr.status, 'pending');
  assert.equal(lr.days, 5);
  assert.equal(lr.startsOn, '2026-12-01');
  assert.equal(lr.endsOn, '2026-12-05');
  assert.equal(lr.note, 'Family trip');
  assert.equal(lr.employee.id, String(employee.id));
  assert.equal(lr.employee.employeeNo, employee.employee_no);
  assert.deepEqual(lr.absenceReason, { id: String(holId), code: 'HOL', name: 'Annual leave' });
  assert.deepEqual(lr.orgUnit, { id: String(unitA.id), name: unitA.name });
  assert.equal(lr.requestedBy.id, String(me.id));
  assert.equal(lr.decidedBy, null);
  assert.equal(lr.cancelledBy, null);
  assert.equal(lr.canDecide, false, 'nobody decides their own leave');
  assert.equal(lr.canCancel, true);
});

test('submitting without employeeId from an Account linked to no Employee is a 400', async () => {
  const unlinked = await insertAccount();
  const { status, body } = await submit(unlinked.token, {
    absenceReasonId: holId, startsOn: '2026-12-01', endsOn: '2026-12-02'
  });
  assert.equal(status, 400);
  assert.match(body.message, /not linked to an Employee/);
});

test('an unknown Employee is a 404 and a malformed body is a 400', async () => {
  const missing = await submit(admin.token, {
    employeeId: '999999999', absenceReasonId: holId, startsOn: '2026-12-01', endsOn: '2026-12-02'
  });
  assert.equal(missing.status, 404);

  const employee = await insertEmployee({ orgUnitId: unitA.id });
  for (const bad of [
    { absenceReasonId: 'x', startsOn: '2026-12-01', endsOn: '2026-12-02' },
    { absenceReasonId: holId, startsOn: '2026-02-31', endsOn: '2026-03-02' },
    { absenceReasonId: holId, startsOn: '12/01/2026', endsOn: '2026-12-02' },
    { absenceReasonId: holId, startsOn: '2026-12-01', endsOn: '2026-12-02', note: 5 }
  ]) {
    const { status } = await submit(admin.token, { employeeId: employee.id, ...bad });
    assert.equal(status, 400, JSON.stringify(bad));
  }
});

test('recording on behalf of an Employee needs an edit Grant reaching their Org Unit', async () => {
  const employee = await insertEmployee({ orgUnitId: unitA.id });
  const payload = { employeeId: employee.id, absenceReasonId: holId, startsOn: '2026-12-08', endsOn: '2026-12-09' };

  const editor = await insertAccount({ grants: [{ orgUnitId: unitA.id, write: true }] });
  const allowed = await submit(editor.token, payload);
  assert.equal(allowed.status, 201);
  assert.equal(allowed.body.leaveRequest.requestedBy.id, String(editor.id));

  const viewer = await insertAccount({ grants: [{ orgUnitId: unitA.id, write: false }] });
  const readOnly = await submit(viewer.token, { ...payload, startsOn: '2026-12-15', endsOn: '2026-12-16' });
  assert.equal(readOnly.status, 403);

  const elsewhere = await insertAccount({ grants: [{ orgUnitId: unitB.id, write: true }] });
  const outside = await submit(elsewhere.token, { ...payload, startsOn: '2026-12-15', endsOn: '2026-12-16' });
  assert.equal(outside.status, 403);

  // An Employee with no Org Unit at all can only be acted for by an administrator.
  const homeless = await insertEmployee();
  const refused = await submit(editor.token, { ...payload, employeeId: homeless.id });
  assert.equal(refused.status, 403);
  const adminOk = await submit(admin.token, { ...payload, employeeId: homeless.id });
  assert.equal(adminOk.status, 201);
  assert.equal(adminOk.body.leaveRequest.orgUnit, null);
});

test('a reason that is not requestable is a 400, as is one that does not exist', async () => {
  const employee = await insertEmployee({ orgUnitId: unitA.id });
  const notRequestable = await submit(admin.token, {
    employeeId: employee.id, absenceReasonId: lateId, startsOn: '2026-12-01', endsOn: '2026-12-01'
  });
  assert.equal(notRequestable.status, 400);
  const unknown = await submit(admin.token, {
    employeeId: employee.id, absenceReasonId: '999999999', startsOn: '2026-12-01', endsOn: '2026-12-01'
  });
  assert.equal(unknown.status, 400);
});

test('a range that ends before it starts is a 400', async () => {
  const employee = await insertEmployee({ orgUnitId: unitA.id });
  const { status, body } = await submit(admin.token, {
    employeeId: employee.id, absenceReasonId: holId, startsOn: '2026-12-10', endsOn: '2026-12-09'
  });
  assert.equal(status, 400);
  assert.match(body.message, /endsOn/);
});

test('a departed Employee cannot take leave: 409', async () => {
  const gone = await insertEmployee({ orgUnitId: unitA.id, isActive: false });
  const { status } = await submit(admin.token, {
    employeeId: gone.id, absenceReasonId: holId, startsOn: '2026-12-01', endsOn: '2026-12-02'
  });
  assert.equal(status, 409);
});

test('overlap with a pending or approved request is a 409; rejected and cancelled requests free their days', async () => {
  const employee = await insertEmployee({ orgUnitId: unitA.id });
  const first = await pendingFor(employee, '2027-01-10', '2027-01-14');
  const body = (startsOn, endsOn) => ({ employeeId: employee.id, absenceReasonId: sickId, startsOn, endsOn });

  const clash = await submit(admin.token, body('2027-01-14', '2027-01-16'));
  assert.equal(clash.status, 409);
  assert.match(clash.body.message, /overlaps another pending or approved leave request/);
  assert.doesNotMatch(clash.body.message, /leave_requests/, 'a raw database message is never echoed');

  // Adjacent days do not overlap.
  assert.equal((await submit(admin.token, body('2027-01-15', '2027-01-15'))).status, 201);

  // Rejected frees the days.
  const decider = await insertAccount({ grants: [{ orgUnitId: unitA.id }] });
  assert.equal((await call(decider.token, 'POST', `/leave-requests/${first.id}/reject`, {})).status, 200);
  assert.equal((await submit(admin.token, body('2027-01-12', '2027-01-12'))).status, 201);

  // Cancelled frees the days.
  const second = await pendingFor(employee, '2027-02-01', '2027-02-03');
  assert.equal((await call(admin.token, 'POST', `/leave-requests/${second.id}/cancel`)).status, 200);
  assert.equal((await submit(admin.token, body('2027-02-02', '2027-02-02'))).status, 201);

  // Approved still blocks.
  const third = await pendingFor(employee, '2027-03-01', '2027-03-03');
  assert.equal((await call(decider.token, 'POST', `/leave-requests/${third.id}/approve`, {})).status, 200);
  assert.equal((await submit(admin.token, body('2027-03-03', '2027-03-04'))).status, 409);
});

// ---------------------------------------------------------------------------
// Lists
// ---------------------------------------------------------------------------

test('mine lists the caller\'s own and submitted-for requests; to-decide lists only those the Grant reaches, never the caller\'s own', async () => {
  const employee = await insertEmployee({ orgUnitId: unitA.id });
  const me = await insertAccount({ employeeId: employee.id, grants: [{ orgUnitId: unitA.id }] });
  const colleague = await insertEmployee({ orgUnitId: unitA.id });
  const stranger = await insertEmployee({ orgUnitId: unitB.id });

  const own = (await submit(me.token, { absenceReasonId: holId, startsOn: '2027-04-01', endsOn: '2027-04-02' })).body.leaveRequest;
  const forColleague = (await submit(me.token, {
    employeeId: colleague.id, absenceReasonId: holId, startsOn: '2027-04-01', endsOn: '2027-04-02'
  })).body.leaveRequest;
  const elsewhere = await pendingFor(stranger, '2027-04-01', '2027-04-02');

  const mine = await call(me.token, 'GET', '/leave-requests');
  assert.equal(mine.status, 200);
  assert.deepEqual(mine.body.leaveRequests.map((r) => r.id).sort(), [own.id, forColleague.id].sort());

  const toDecide = await call(me.token, 'GET', '/leave-requests?view=to-decide&status=pending');
  assert.equal(toDecide.status, 200);
  const ids = toDecide.body.leaveRequests.map((r) => r.id);
  assert.ok(ids.includes(forColleague.id), 'a colleague\'s request at a reached Org Unit is listed');
  assert.ok(!ids.includes(own.id), 'own request is excluded');
  assert.ok(!ids.includes(elsewhere.id), 'out-of-reach request is excluded');
  assert.ok(toDecide.body.leaveRequests.every((r) => r.canDecide === true));

  // A read-only Grant reaches nothing for deciding.
  const viewer = await insertAccount({ grants: [{ orgUnitId: unitA.id, write: false }] });
  assert.deepEqual((await call(viewer.token, 'GET', '/leave-requests?view=to-decide')).body.leaveRequests, []);

  // An administrator sees everywhere, including a null Org Unit.
  const homeless = await insertEmployee();
  const nullUnit = await pendingFor(homeless, '2027-04-10', '2027-04-11');
  const adminList = await call(admin.token, 'GET', '/leave-requests?view=to-decide&status=pending');
  const adminIds = adminList.body.leaveRequests.map((r) => r.id);
  for (const id of [forColleague.id, elsewhere.id, nullUnit.id]) assert.ok(adminIds.includes(id));

  // Newest first.
  assert.ok(Number(mine.body.leaveRequests[0].id) > Number(mine.body.leaveRequests[1].id));
});

test('an invalid view or status is a 400', async () => {
  assert.equal((await call(admin.token, 'GET', '/leave-requests?view=everything')).status, 400);
  assert.equal((await call(admin.token, 'GET', '/leave-requests?status=maybe')).status, 400);
});

// ---------------------------------------------------------------------------
// Reading one
// ---------------------------------------------------------------------------

test('GET by id is visible to the requester, the Employee, a reaching decider and an administrator; anyone else gets 404', async () => {
  const employee = await insertEmployee({ orgUnitId: unitA.id });
  const subject = await insertAccount({ employeeId: employee.id });
  const lr = (await submit(subject.token, { absenceReasonId: sickId, startsOn: '2027-05-01', endsOn: '2027-05-01', note: 'Diagnosis detail' })).body.leaveRequest;

  const proxy = await insertAccount({ grants: [{ orgUnitId: unitA.id }] });
  const behalf = await insertEmployee({ orgUnitId: unitA.id });
  const byProxy = (await submit(proxy.token, { employeeId: behalf.id, absenceReasonId: sickId, startsOn: '2027-05-01', endsOn: '2027-05-01' })).body.leaveRequest;

  assert.equal((await call(subject.token, 'GET', `/leave-requests/${lr.id}`)).status, 200);
  assert.equal((await call(proxy.token, 'GET', `/leave-requests/${lr.id}`)).status, 200, 'a reaching edit Grant');
  assert.equal((await call(admin.token, 'GET', `/leave-requests/${lr.id}`)).status, 200);
  assert.equal((await call(proxy.token, 'GET', `/leave-requests/${byProxy.id}`)).status, 200, 'the requester');

  const unrelated = await insertAccount();
  assert.equal((await call(unrelated.token, 'GET', `/leave-requests/${lr.id}`)).status, 404);
  const otherUnit = await insertAccount({ grants: [{ orgUnitId: unitB.id }] });
  assert.equal((await call(otherUnit.token, 'GET', `/leave-requests/${lr.id}`)).status, 404);
  const readOnly = await insertAccount({ grants: [{ orgUnitId: unitA.id, write: false }] });
  assert.equal((await call(readOnly.token, 'GET', `/leave-requests/${lr.id}`)).status, 404);

  assert.equal((await call(admin.token, 'GET', '/leave-requests/999999999')).status, 404);
  assert.equal((await call(admin.token, 'GET', '/leave-requests/abc')).status, 404);
});

// ---------------------------------------------------------------------------
// Deciding
// ---------------------------------------------------------------------------

test('an edit-Grant holder approves, recording the decider, time and note; the decision is audited', async () => {
  const employee = await insertEmployee({ orgUnitId: unitA.id });
  const lr = await pendingFor(employee);
  const decider = await insertAccount({ grants: [{ orgUnitId: unitA.id }] });

  const { status, body } = await call(decider.token, 'POST', `/leave-requests/${lr.id}/approve`, { note: 'Enjoy' });
  assert.equal(status, 200);
  assert.equal(body.leaveRequest.status, 'approved');
  assert.equal(body.leaveRequest.decidedBy.id, String(decider.id));
  assert.equal(body.leaveRequest.decisionNote, 'Enjoy');
  assert.ok(body.leaveRequest.decidedAt);
  assert.equal(body.leaveRequest.canDecide, false);
  assert.equal(body.leaveRequest.canCancel, false);

  const { rows } = await pool.query(
    `SELECT changed_by FROM audit_log
      WHERE table_name = 'leave_requests' AND record_id = $1 AND operation = 'UPDATE'`,
    [lr.id]
  );
  assert.equal(rows.length, 1);
  assert.equal(String(rows[0].changed_by), String(decider.id));
});

test('reject carries an optional note, and none is also fine', async () => {
  const employee = await insertEmployee({ orgUnitId: unitA.id });
  const decider = await insertAccount({ grants: [{ orgUnitId: unitA.id }] });

  const withNote = await call(decider.token, 'POST', `/leave-requests/${(await pendingFor(employee, '2027-06-01', '2027-06-02')).id}/reject`, { note: 'Peak week' });
  assert.equal(withNote.status, 200);
  assert.equal(withNote.body.leaveRequest.status, 'rejected');
  assert.equal(withNote.body.leaveRequest.decisionNote, 'Peak week');

  const bare = await call(decider.token, 'POST', `/leave-requests/${(await pendingFor(employee, '2027-06-05', '2027-06-06')).id}/reject`);
  assert.equal(bare.status, 200);
  assert.equal(bare.body.leaveRequest.decisionNote, null);
});

test('a read-only Grant or one elsewhere cannot decide (it cannot even see the request: 404), and the Employee own Account is refused with 403', async () => {
  const employee = await insertEmployee({ orgUnitId: unitA.id });
  const lr = await pendingFor(employee);

  const readOnly = await insertAccount({ grants: [{ orgUnitId: unitA.id, write: false }] });
  // A read-only Grant cannot see the request at all, so deciding it is a 404.
  assert.equal((await call(readOnly.token, 'POST', `/leave-requests/${lr.id}/approve`, {})).status, 404);

  // Neither does a Grant elsewhere.
  const elsewhere = await insertAccount({ grants: [{ orgUnitId: unitB.id }] });
  assert.equal((await call(elsewhere.token, 'POST', `/leave-requests/${lr.id}/approve`, {})).status, 404);

  // The Employee's own Account can see its request but may not decide it: 403.
  const subjectEmployee = await insertEmployee({ orgUnitId: unitA.id });
  const subjectAccount = await insertAccount({ employeeId: subjectEmployee.id });
  const own = (await submit(subjectAccount.token, { absenceReasonId: holId, startsOn: '2027-07-10', endsOn: '2027-07-10' })).body.leaveRequest;
  assert.equal((await call(subjectAccount.token, 'POST', `/leave-requests/${own.id}/approve`, {})).status, 403);
  assert.equal((await call(subjectAccount.token, 'POST', `/leave-requests/${own.id}/reject`, {})).status, 403);

  assert.equal((await call(admin.token, 'POST', '/leave-requests/999999999/approve', {})).status, 404);
});

test('nobody decides their own leave, an administrator linked to that Employee included', async () => {
  const employee = await insertEmployee({ orgUnitId: unitA.id });
  const selfAdmin = await insertAccount({ role: 'admin', employeeId: employee.id });
  const lr = (await submit(selfAdmin.token, { absenceReasonId: holId, startsOn: '2027-08-01', endsOn: '2027-08-02' })).body.leaveRequest;
  assert.equal(lr.canDecide, false);

  const approve = await call(selfAdmin.token, 'POST', `/leave-requests/${lr.id}/approve`, {});
  assert.equal(approve.status, 403);
  const reject = await call(selfAdmin.token, 'POST', `/leave-requests/${lr.id}/reject`, {});
  assert.equal(reject.status, 403);

  // Another administrator can.
  assert.equal((await call(admin.token, 'POST', `/leave-requests/${lr.id}/approve`, {})).status, 200);
});

test('deciding a request that is no longer pending is a 409', async () => {
  const employee = await insertEmployee({ orgUnitId: unitA.id });
  const lr = await pendingFor(employee);
  const decider = await insertAccount({ grants: [{ orgUnitId: unitA.id }] });
  assert.equal((await call(decider.token, 'POST', `/leave-requests/${lr.id}/approve`, {})).status, 200);
  assert.equal((await call(decider.token, 'POST', `/leave-requests/${lr.id}/approve`, {})).status, 409);
  assert.equal((await call(decider.token, 'POST', `/leave-requests/${lr.id}/reject`, {})).status, 409);
});

// ---------------------------------------------------------------------------
// Cancelling
// ---------------------------------------------------------------------------

test('the requester cancels a pending request; the Employee\'s own Account may too', async () => {
  const employee = await insertEmployee({ orgUnitId: unitA.id });
  const subject = await insertAccount({ employeeId: employee.id });
  const proxy = await insertAccount({ grants: [{ orgUnitId: unitA.id }] });

  const byProxy = (await submit(proxy.token, {
    employeeId: employee.id, absenceReasonId: holId, startsOn: '2027-09-01', endsOn: '2027-09-01'
  })).body.leaveRequest;
  const cancelledByProxy = await call(proxy.token, 'POST', `/leave-requests/${byProxy.id}/cancel`);
  assert.equal(cancelledByProxy.status, 200);
  assert.equal(cancelledByProxy.body.leaveRequest.status, 'cancelled');
  assert.equal(cancelledByProxy.body.leaveRequest.cancelledBy.id, String(proxy.id));
  assert.ok(cancelledByProxy.body.leaveRequest.cancelledAt);

  const other = (await submit(proxy.token, {
    employeeId: employee.id, absenceReasonId: holId, startsOn: '2027-09-01', endsOn: '2027-09-01'
  })).body.leaveRequest;
  const bySubject = await call(subject.token, 'POST', `/leave-requests/${other.id}/cancel`);
  assert.equal(bySubject.status, 200);
  assert.equal(bySubject.body.leaveRequest.cancelledBy.id, String(subject.id));
});

test('someone else cannot cancel: a decider who can see it gets 403, a stranger 404', async () => {
  const employee = await insertEmployee({ orgUnitId: unitA.id });
  const lr = await pendingFor(employee);
  const decider = await insertAccount({ grants: [{ orgUnitId: unitA.id }] });
  assert.equal((await call(decider.token, 'POST', `/leave-requests/${lr.id}/cancel`)).status, 403);
  const stranger = await insertAccount();
  assert.equal((await call(stranger.token, 'POST', `/leave-requests/${lr.id}/cancel`)).status, 404);
});

test('a request cannot be cancelled once approved: 409', async () => {
  const employee = await insertEmployee({ orgUnitId: unitA.id });
  const subject = await insertAccount({ employeeId: employee.id });
  const lr = (await submit(subject.token, { absenceReasonId: holId, startsOn: '2027-10-01', endsOn: '2027-10-01' })).body.leaveRequest;
  const decider = await insertAccount({ grants: [{ orgUnitId: unitA.id }] });
  assert.equal((await call(decider.token, 'POST', `/leave-requests/${lr.id}/approve`, {})).status, 200);
  assert.equal((await call(subject.token, 'POST', `/leave-requests/${lr.id}/cancel`)).status, 409);
});
