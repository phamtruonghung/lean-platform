/*
 * Maintenance requests over HTTP (issue #72), against a real database and a
 * real (locally issued) JWKS — the same seam as work-orders.test.js, whose
 * fixture scaffolding this file mirrors closely. Assets and Accounts are
 * inserted directly against the database rather than through POST /assets and
 * the Approval flow: this file is about requests, and both of those are
 * already covered by their own files.
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
const insertedEmployeeIds = [];
const insertedSiteIds = [];
const insertedOrgUnitIds = [];
const insertedAssetIds = [];
const insertedRequestIds = [];
const insertedWorkOrderIds = [];

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

async function insertAccount({
  role = 'supervisor',
  isActive = true,
  approvalStatus = 'approved',
  employeeId = null
} = {}) {
  const subject = uniqueCode('acct');
  const { rows: [row] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status, employee_id)
     VALUES ($1, 'Request Test Account', $2, $3, $4, $5, $6) RETURNING id`,
    [`${subject}@example.com`, role, subject, isActive, approvalStatus, employeeId]
  );
  insertedAccountIds.push(row.id);
  return { id: row.id, token: await authHeader(subject) };
}

// display_name is GENERATED ALWAYS as first_name || ' ' || last_name, so the
// round trip through the two real columns is what makes the returned name
// match what a test passed in — the same reason work-orders.test.js splits it.
async function insertEmployee({ isActive = true, displayName = 'Reporter Test' } = {}) {
  const [firstName, ...rest] = displayName.split(' ');
  const lastName = rest.join(' ') || 'Employee';
  const { rows: [row] } = await pool.query(
    `INSERT INTO employees (employee_no, first_name, last_name, is_active)
     VALUES ($1, $2, $3, $4) RETURNING id, display_name`,
    [uniqueCode('EMP'), firstName, lastName, isActive]
  );
  insertedEmployeeIds.push(row.id);
  return row;
}

async function insertSite() {
  const { rows: [row] } = await pool.query(
    `INSERT INTO sites (code, name, timezone) VALUES ($1, 'Request Test Site', 'Asia/Ho_Chi_Minh') RETURNING id, code`,
    [uniqueCode('ST')]
  );
  insertedSiteIds.push(row.id);
  return row;
}

async function insertOrgUnit(siteId, { parentId = null, unitType = 'area', name = 'Request Test Unit' } = {}) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, $2, $3, $4, $5) RETURNING id, code, name`,
    [siteId, parentId, uniqueCode('OU'), name, unitType]
  );
  insertedOrgUnitIds.push(row.id);
  return row;
}

async function insertGrant({ accountId, orgUnitId, canWrite = false }) {
  await pool.query(
    `INSERT INTO app_user_org_units (app_user_id, org_unit_id, can_write) VALUES ($1, $2, $3)`,
    [accountId, orgUnitId, canWrite]
  );
}

async function insertAsset(orgUnitId, { name = 'Press 1' } = {}) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO assets (org_unit_id, code, name, asset_type, criticality)
     VALUES ($1, $2, $3, 'machine', 'high') RETURNING id, org_unit_id`,
    [orgUnitId, uniqueCode('AS'), name]
  );
  insertedAssetIds.push(row.id);
  return row;
}

function requestBody(assetId, overrides = {}) {
  return { assetId, summary: 'Guard is loose on the press', ...overrides };
}

async function postRequest(token, body) {
  const response = await fetch(`${base}/api/maintenance/requests`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  const payload = await response.json().catch(() => null);
  if (payload?.request?.id) insertedRequestIds.push(payload.request.id);
  return { response, payload };
}

async function getQueue(token, siteId) {
  const response = await fetch(`${base}/api/maintenance/sites/${siteId}/requests`, { headers: token });
  const payload = await response.json().catch(() => null);
  return { response, payload };
}

async function getMine(token, siteId) {
  const response = await fetch(`${base}/api/maintenance/sites/${siteId}/requests/mine`, { headers: token });
  const payload = await response.json().catch(() => null);
  return { response, payload };
}

async function triage(token, requestId, action, body) {
  const response = await fetch(`${base}/api/maintenance/requests/${requestId}/${action}`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body)
  });
  const payload = await response.json().catch(() => null);
  if (payload?.workOrder?.id) insertedWorkOrderIds.push(payload.workOrder.id);
  return { response, payload };
}

async function postWorkOrder(token, body) {
  const response = await fetch(`${base}/api/maintenance/work-orders`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  const payload = await response.json().catch(() => null);
  if (payload?.workOrder?.id) insertedWorkOrderIds.push(payload.workOrder.id);
  return { response, payload };
}

let admin;
let noGrantAccount;   // approved, no Grant anywhere at all.
let readOnlyAccount;  // read Grant on grantedLine.
let writerAccount;    // write Grant on grantedLine.
let siblingWriter;    // write Grant on otherLine only.
let reporterAccount;  // read Grant on grantedLine, linked to reporterEmployee.

let reporterEmployee;
let reporter2Account; // read Grant on grantedLine, linked to a different Employee.
let reporter2Employee;

let site;
let otherSite;
let grantedArea;
let grantedLine;
let otherLine;

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

  admin = await insertAccount({ role: 'admin' });
  noGrantAccount = await insertAccount();
  readOnlyAccount = await insertAccount();
  writerAccount = await insertAccount();
  siblingWriter = await insertAccount();

  reporterEmployee = await insertEmployee({ displayName: 'Raising Reporter' });
  reporterAccount = await insertAccount({ employeeId: reporterEmployee.id });
  reporter2Employee = await insertEmployee({ displayName: 'Other Reporter' });
  reporter2Account = await insertAccount({ employeeId: reporter2Employee.id });

  site = await insertSite();
  otherSite = await insertSite();
  grantedArea = await insertOrgUnit(site.id, { name: 'Granted Area' });
  grantedLine = await insertOrgUnit(site.id, { parentId: grantedArea.id, unitType: 'line', name: 'Line 1' });
  otherLine = await insertOrgUnit(site.id, { parentId: grantedArea.id, unitType: 'line', name: 'Line 2' });

  await insertGrant({ accountId: readOnlyAccount.id, orgUnitId: grantedLine.id, canWrite: false });
  await insertGrant({ accountId: writerAccount.id, orgUnitId: grantedLine.id, canWrite: true });
  await insertGrant({ accountId: siblingWriter.id, orgUnitId: otherLine.id, canWrite: true });
  await insertGrant({ accountId: reporterAccount.id, orgUnitId: grantedLine.id, canWrite: false });
  await insertGrant({ accountId: reporter2Account.id, orgUnitId: grantedLine.id, canWrite: false });
});

test.after(async () => {
  await pool.query('DELETE FROM work_orders WHERE id = ANY($1) OR maintenance_request_id = ANY($2)', [
    insertedWorkOrderIds,
    insertedRequestIds
  ]);
  await pool.query('DELETE FROM maintenance_requests WHERE id = ANY($1)', [insertedRequestIds]);
  await pool.query('DELETE FROM assets WHERE id = ANY($1)', [insertedAssetIds]);
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
// Raising a request.
// ---------------------------------------------------------------------------

test('raising records who and when, derives the Org Unit from the Asset, and starts as new', async () => {
  const asset = await insertAsset(grantedLine.id);
  const { response, payload } = await postRequest(reporterAccount.token, requestBody(asset.id));
  assert.strictEqual(response.status, 201);

  const request = payload.request;
  assert.strictEqual(request.status, 'new');
  assert.strictEqual(request.assetId, String(asset.id));
  assert.strictEqual(request.orgUnitId, String(grantedLine.id));
  assert.strictEqual(request.reportedBy, String(reporterEmployee.id));
  assert.strictEqual(request.reporterName, reporterEmployee.display_name);
  assert.ok(request.reportedAt);
  assert.ok(request.requestNo);
  assert.strictEqual(request.urgency, 'normal');
  assert.strictEqual(request.productionStopped, false);
  assert.strictEqual(request.workOrder, null);

  const { rows: [row] } = await pool.query(
    `SELECT request_no, org_unit_id, reported_by, reported_at, status
       FROM maintenance_requests WHERE id = $1`,
    [request.id]
  );
  assert.strictEqual(row.status, 'new');
  assert.strictEqual(String(row.org_unit_id), String(grantedLine.id));
  assert.strictEqual(String(row.reported_by), String(reporterEmployee.id));
  assert.ok(row.reported_at);
  assert.ok(row.request_no);
});

test("the request's Org Unit is derived from the Asset — a different orgUnitId in the body is ignored", async () => {
  const asset = await insertAsset(grantedLine.id);
  const { response, payload } = await postRequest(
    reporterAccount.token,
    requestBody(asset.id, { orgUnitId: otherLine.id })
  );
  assert.strictEqual(response.status, 201);
  assert.strictEqual(payload.request.orgUnitId, String(grantedLine.id));

  const { rows } = await pool.query('SELECT org_unit_id FROM maintenance_requests WHERE id = $1', [
    payload.request.id
  ]);
  assert.strictEqual(String(rows[0].org_unit_id), String(grantedLine.id));
});

test("the number is issued by the Site's own sequence, and two Sites number independently", async () => {
  // Fresh Sites, used nowhere else in this file: the 'MR' sequence is scoped
  // by (prefix, Site code, year), so a Site that has never had a request
  // raised on it is the only honest way to assert the run starts at 00001.
  const freshSiteA = await insertSite();
  const freshSiteB = await insertSite();
  const areaA = await insertOrgUnit(freshSiteA.id, { name: 'Area A' });
  const areaB = await insertOrgUnit(freshSiteB.id, { name: 'Area B' });
  const assetA = await insertAsset(areaA.id);
  const assetB = await insertAsset(areaB.id);

  const a1 = await postRequest(admin.token, requestBody(assetA.id));
  const b1 = await postRequest(admin.token, requestBody(assetB.id));
  assert.strictEqual(a1.response.status, 201);
  assert.strictEqual(b1.response.status, 201);

  const year = new Date().getUTCFullYear();
  assert.strictEqual(a1.payload.request.requestNo, `MR-${freshSiteA.code}-${year}-00001`);
  assert.strictEqual(b1.payload.request.requestNo, `MR-${freshSiteB.code}-${year}-00001`);
  assert.notStrictEqual(a1.payload.request.requestNo, b1.payload.request.requestNo);
});

test('validation: bad urgency, non-boolean productionStopped, and an empty summary are each a clean 400', async () => {
  const asset = await insertAsset(grantedLine.id);
  for (const overrides of [
    { urgency: 'whenever' },
    { productionStopped: 'true' },
    { summary: '   ' }
  ]) {
    const { response } = await postRequest(reporterAccount.token, requestBody(asset.id, overrides));
    assert.strictEqual(response.status, 400, JSON.stringify(overrides));
  }
});

test('naming an Asset that does not exist on raise is a 404 naming the Asset; malformed is also a clean 404', async () => {
  const missing = await postRequest(reporterAccount.token, requestBody('999999999'));
  assert.strictEqual(missing.response.status, 404);
  assert.strictEqual(missing.payload.message, 'Asset not found');

  const malformed = await postRequest(reporterAccount.token, requestBody('not-an-id'));
  assert.strictEqual(malformed.response.status, 404);
});

// ---------------------------------------------------------------------------
// Who may raise one: read scope on the Asset's Org Unit.
// ---------------------------------------------------------------------------

test('a read Grant reaching the Asset\'s Org Unit may raise a request', async () => {
  const asset = await insertAsset(grantedLine.id);
  const { response } = await postRequest(readOnlyAccount.token, requestBody(asset.id));
  assert.strictEqual(response.status, 201);
});

test('an approved Account with no Grant anywhere cannot raise a request', async () => {
  const asset = await insertAsset(grantedLine.id);
  const { response, payload } = await postRequest(noGrantAccount.token, requestBody(asset.id));
  assert.strictEqual(response.status, 403);
  assert.strictEqual(payload.message, "Outside the caller's granted Org Units");
});

test('a write Grant on a sibling branch does not reach across', async () => {
  const asset = await insertAsset(grantedLine.id);
  const { response } = await postRequest(siblingWriter.token, requestBody(asset.id));
  assert.strictEqual(response.status, 403);
});

// ---------------------------------------------------------------------------
// The triage queue: Site-wide read, awaiting a decision, oldest first.
// ---------------------------------------------------------------------------

test('a request with no bearer token is refused', async () => {
  const response = await fetch(`${base}/api/maintenance/sites/${site.id}/requests`);
  assert.strictEqual(response.status, 401);
});

test('the Site-wide queue returns requests the caller holds no Grant over', async () => {
  const asset = await insertAsset(otherLine.id);
  const created = await postRequest(admin.token, requestBody(asset.id, { summary: 'No grant here' }));
  assert.strictEqual(created.response.status, 201);

  const { response, payload } = await getQueue(noGrantAccount.token, site.id);
  assert.strictEqual(response.status, 200);
  assert.ok(payload.requests.some((r) => r.id === created.payload.request.id));
});

test('the queue is oldest first, admits new and triaged, and excludes anything already decided', async () => {
  const asset = await insertAsset(grantedLine.id);
  const first = await postRequest(reporterAccount.token, requestBody(asset.id, { summary: 'First raised' }));
  const second = await postRequest(reporterAccount.token, requestBody(asset.id, { summary: 'Second raised' }));
  assert.strictEqual(first.response.status, 201);
  assert.strictEqual(second.response.status, 201);

  // There is no HTTP action that parks a request in 'triaged' on its own
  // (accept/decline/duplicate are the three ends this slice offers), so the
  // one status the queue admits besides 'new' is written directly.
  await pool.query(`UPDATE maintenance_requests SET status = 'triaged', triaged_at = now() WHERE id = $1`, [
    first.payload.request.id
  ]);

  const queue = await getQueue(admin.token, site.id);
  const firstIndex = queue.payload.requests.findIndex((r) => r.id === first.payload.request.id);
  const secondIndex = queue.payload.requests.findIndex((r) => r.id === second.payload.request.id);
  assert.ok(firstIndex !== -1, 'a triaged request is still on the queue');
  assert.ok(secondIndex !== -1, 'a new request is on the queue');
  assert.ok(firstIndex < secondIndex, 'the older request comes first');

  const accepted = await triage(admin.token, second.payload.request.id, 'accept', {});
  assert.strictEqual(accepted.response.status, 200);
  const after = await getQueue(admin.token, site.id);
  assert.ok(!after.payload.requests.some((r) => r.id === second.payload.request.id));
});

test('an unknown Site on the queue is a 404, not an empty list', async () => {
  const { response, payload } = await getQueue(admin.token, '999999999');
  assert.strictEqual(response.status, 404);
  assert.strictEqual(payload.message, 'Site not found');
});

// ---------------------------------------------------------------------------
// The requester's own list.
// ---------------------------------------------------------------------------

test("the requester's own list carries all statuses and only their own requests", async () => {
  const asset = await insertAsset(grantedLine.id);
  const mineRaised = await postRequest(reporterAccount.token, requestBody(asset.id, { summary: 'My request' }));
  const theirsRaised = await postRequest(reporter2Account.token, requestBody(asset.id, { summary: 'Their request' }));
  assert.strictEqual(mineRaised.response.status, 201);
  assert.strictEqual(theirsRaised.response.status, 201);

  const declined = await triage(admin.token, mineRaised.payload.request.id, 'decline', { reason: 'Already covered' });
  assert.strictEqual(declined.response.status, 200);

  const { response, payload } = await getMine(reporterAccount.token, site.id);
  assert.strictEqual(response.status, 200);
  const found = payload.requests.find((r) => r.id === mineRaised.payload.request.id);
  assert.ok(found, 'my own, now-declined request is still listed');
  assert.strictEqual(found.status, 'rejected');
  assert.ok(!payload.requests.some((r) => r.id === theirsRaised.payload.request.id));
});

test('an Account with no linked Employee gets an empty own list', async () => {
  const { response, payload } = await getMine(noGrantAccount.token, site.id);
  assert.strictEqual(response.status, 200);
  assert.deepStrictEqual(payload.requests, []);
});

test('a request with no bearer token is refused on the own list', async () => {
  const response = await fetch(`${base}/api/maintenance/sites/${site.id}/requests/mine`);
  assert.strictEqual(response.status, 401);
});

// ---------------------------------------------------------------------------
// Accepting: raises a linked Work order (ADR-0014).
// ---------------------------------------------------------------------------

test('accepting moves the request to accepted and raises a linked work order in one transaction', async () => {
  const asset = await insertAsset(grantedLine.id);
  const raised = await postRequest(reporterAccount.token, requestBody(asset.id, { summary: 'Accept me' }));
  assert.strictEqual(raised.response.status, 201);

  const { response, payload } = await triage(admin.token, raised.payload.request.id, 'accept', {});
  assert.strictEqual(response.status, 200);

  assert.strictEqual(payload.request.status, 'accepted');
  assert.ok(payload.request.triagedAt);
  assert.ok(payload.request.workOrder);
  assert.strictEqual(payload.request.workOrder.status, 'approved');
  assert.ok(payload.request.workOrder.workOrderNo);
  assert.strictEqual(payload.workOrder.maintenanceRequestId, String(raised.payload.request.id));

  const { rows: [workOrder] } = await pool.query(
    `SELECT maintenance_request_id, asset_id, org_unit_id, summary, work_type, priority, status
       FROM work_orders WHERE id = $1`,
    [payload.workOrder.id]
  );
  assert.strictEqual(String(workOrder.maintenance_request_id), String(raised.payload.request.id));
  assert.strictEqual(String(workOrder.asset_id), String(asset.id));
  assert.strictEqual(String(workOrder.org_unit_id), String(grantedLine.id));
  assert.strictEqual(workOrder.summary, 'Accept me');
  assert.strictEqual(workOrder.work_type, 'corrective');
  assert.strictEqual(workOrder.priority, 3);
  assert.strictEqual(workOrder.status, 'approved');

  const { rows: [request] } = await pool.query(
    'SELECT status, triaged_at FROM maintenance_requests WHERE id = $1',
    [raised.payload.request.id]
  );
  assert.strictEqual(request.status, 'accepted');
  assert.ok(request.triaged_at);
});

test('accepting takes an explicit workType and priority, and never copies urgency into priority', async () => {
  const asset = await insertAsset(grantedLine.id);
  const raised = await postRequest(
    reporterAccount.token,
    requestBody(asset.id, { summary: 'Explicit acceptance', urgency: 'immediate' })
  );
  assert.strictEqual(raised.response.status, 201);

  const { response, payload } = await triage(admin.token, raised.payload.request.id, 'accept', {
    priority: 1,
    workType: 'preventive'
  });
  assert.strictEqual(response.status, 200);

  const { rows: [workOrder] } = await pool.query(
    'SELECT work_type, priority FROM work_orders WHERE id = $1',
    [payload.workOrder.id]
  );
  assert.strictEqual(workOrder.work_type, 'preventive');
  assert.strictEqual(workOrder.priority, 1);

  // The reporter said 'immediate'; maintenance said priority 1. The two are
  // different judgements and the request keeps its own.
  const { rows: [request] } = await pool.query('SELECT urgency FROM maintenance_requests WHERE id = $1', [
    raised.payload.request.id
  ]);
  assert.strictEqual(request.urgency, 'immediate');
});

test('accept validation: a bad priority or workType is a clean 400', async () => {
  const asset = await insertAsset(grantedLine.id);
  const raised = await postRequest(reporterAccount.token, requestBody(asset.id, { summary: 'Bad accept body' }));
  for (const body of [{ priority: 0 }, { priority: 6 }, { priority: 1.5 }, { workType: 'urgent' }]) {
    const { response } = await triage(admin.token, raised.payload.request.id, 'accept', body);
    assert.strictEqual(response.status, 400, JSON.stringify(body));
  }
});

test('a request already triaged cannot be accepted again', async () => {
  const asset = await insertAsset(grantedLine.id);
  const raised = await postRequest(reporterAccount.token, requestBody(asset.id, { summary: 'Accept twice' }));
  await triage(admin.token, raised.payload.request.id, 'accept', {});

  const again = await triage(admin.token, raised.payload.request.id, 'accept', {});
  assert.strictEqual(again.response.status, 409);
  assert.strictEqual(again.payload.message, 'this Request has already been triaged');
});

test("a write Grant reaching the Request's Org Unit may accept; a read-only Grant is refused", async () => {
  const asset = await insertAsset(grantedLine.id);
  const forReader = await postRequest(reporterAccount.token, requestBody(asset.id, { summary: 'Read-only accept' }));
  const refused = await triage(readOnlyAccount.token, forReader.payload.request.id, 'accept', {});
  assert.strictEqual(refused.response.status, 403);
  assert.strictEqual(refused.payload.message, "Outside the caller's granted Org Units");

  const forWriter = await postRequest(reporterAccount.token, requestBody(asset.id, { summary: 'Writer accept' }));
  const allowed = await triage(writerAccount.token, forWriter.payload.request.id, 'accept', {});
  assert.strictEqual(allowed.response.status, 200);
});

test('a write Grant on a sibling branch does not reach across on triage', async () => {
  const asset = await insertAsset(grantedLine.id);
  const raised = await postRequest(reporterAccount.token, requestBody(asset.id, { summary: 'Sibling triage' }));
  const { response } = await triage(siblingWriter.token, raised.payload.request.id, 'accept', {});
  assert.strictEqual(response.status, 403);
});

test('an approved Account with no Grant anywhere cannot triage', async () => {
  const asset = await insertAsset(grantedLine.id);
  const raised = await postRequest(reporterAccount.token, requestBody(asset.id, { summary: 'No grant triage' }));
  const { response } = await triage(noGrantAccount.token, raised.payload.request.id, 'accept', {});
  assert.strictEqual(response.status, 403);
});

test('an unknown request id is a 404 naming the Request, checked before scope; malformed is a clean 404', async () => {
  const missing = await triage(admin.token, '999999999', 'accept', {});
  assert.strictEqual(missing.response.status, 404);
  assert.strictEqual(missing.payload.message, 'Request not found');

  const malformed = await triage(admin.token, 'not-an-id', 'accept', {});
  assert.strictEqual(malformed.response.status, 404);
});

test('triaging with no bearer token is refused', async () => {
  const asset = await insertAsset(grantedLine.id);
  const raised = await postRequest(reporterAccount.token, requestBody(asset.id, { summary: 'No token triage' }));
  const response = await fetch(`${base}/api/maintenance/requests/${raised.payload.request.id}/accept`, {
    method: 'POST'
  });
  assert.strictEqual(response.status, 401);
});

// ---------------------------------------------------------------------------
// Declining: a reason is required.
// ---------------------------------------------------------------------------

test('declining requires a reason — none, empty or blank is a clean 400', async () => {
  const asset = await insertAsset(grantedLine.id);
  const raised = await postRequest(reporterAccount.token, requestBody(asset.id, { summary: 'Decline blank' }));
  for (const body of [undefined, {}, { reason: '' }, { reason: '   ' }]) {
    const { response, payload } = await triage(admin.token, raised.payload.request.id, 'decline', body);
    assert.strictEqual(response.status, 400, JSON.stringify(body));
    assert.strictEqual(payload.message, 'reason is required');
  }
});

test('declining stores the reason and moves the request to rejected', async () => {
  const asset = await insertAsset(grantedLine.id);
  const raised = await postRequest(reporterAccount.token, requestBody(asset.id, { summary: 'Decline me' }));
  const { response, payload } = await triage(admin.token, raised.payload.request.id, 'decline', {
    reason: '  A work order already covers this  '
  });
  assert.strictEqual(response.status, 200);
  assert.strictEqual(payload.request.status, 'rejected');
  assert.strictEqual(payload.request.rejectionReason, 'A work order already covers this');
  assert.ok(payload.request.triagedAt);

  const { rows: [row] } = await pool.query('SELECT rejection_reason FROM maintenance_requests WHERE id = $1', [
    raised.payload.request.id
  ]);
  assert.strictEqual(row.rejection_reason, 'A work order already covers this');
});

test('a request already triaged cannot be declined', async () => {
  const asset = await insertAsset(grantedLine.id);
  const raised = await postRequest(reporterAccount.token, requestBody(asset.id, { summary: 'Decline twice' }));
  await triage(admin.token, raised.payload.request.id, 'decline', { reason: 'No' });

  const again = await triage(admin.token, raised.payload.request.id, 'decline', { reason: 'Again' });
  assert.strictEqual(again.response.status, 409);
  assert.strictEqual(again.payload.message, 'this Request has already been triaged');
});

// ---------------------------------------------------------------------------
// Marking duplicate.
// ---------------------------------------------------------------------------

test('marking a duplicate names the surviving request and moves this one to duplicate', async () => {
  const asset = await insertAsset(grantedLine.id);
  const original = await postRequest(reporterAccount.token, requestBody(asset.id, { summary: 'Original' }));
  const duplicate = await postRequest(reporterAccount.token, requestBody(asset.id, { summary: 'Re-raised' }));

  const { response, payload } = await triage(admin.token, duplicate.payload.request.id, 'duplicate', {
    duplicateOfId: original.payload.request.id
  });
  assert.strictEqual(response.status, 200);
  assert.strictEqual(payload.request.status, 'duplicate');
  assert.strictEqual(payload.request.duplicateOfId, String(original.payload.request.id));
  assert.ok(payload.request.triagedAt);

  const { rows: [row] } = await pool.query('SELECT duplicate_of_id FROM maintenance_requests WHERE id = $1', [
    duplicate.payload.request.id
  ]);
  assert.strictEqual(String(row.duplicate_of_id), String(original.payload.request.id));

  // The survivor is untouched.
  const { rows: [survivor] } = await pool.query('SELECT status FROM maintenance_requests WHERE id = $1', [
    original.payload.request.id
  ]);
  assert.strictEqual(survivor.status, 'new');
});

test('a request cannot be marked a duplicate of itself', async () => {
  const asset = await insertAsset(grantedLine.id);
  const raised = await postRequest(reporterAccount.token, requestBody(asset.id, { summary: 'Self duplicate' }));
  const { response } = await triage(admin.token, raised.payload.request.id, 'duplicate', {
    duplicateOfId: raised.payload.request.id
  });
  assert.strictEqual(response.status, 400);
});

test('a malformed or unknown duplicateOfId is refused cleanly', async () => {
  const asset = await insertAsset(grantedLine.id);
  const raised = await postRequest(reporterAccount.token, requestBody(asset.id, { summary: 'Bad duplicate target' }));

  const malformed = await triage(admin.token, raised.payload.request.id, 'duplicate', { duplicateOfId: 'nope' });
  assert.strictEqual(malformed.response.status, 400);

  const unknown = await triage(admin.token, raised.payload.request.id, 'duplicate', { duplicateOfId: '999999999' });
  assert.strictEqual(unknown.response.status, 404);
  assert.strictEqual(unknown.payload.message, 'Request not found');
});

test('a request already triaged cannot be marked duplicate', async () => {
  const asset = await insertAsset(grantedLine.id);
  const first = await postRequest(reporterAccount.token, requestBody(asset.id, { summary: 'Dup already' }));
  const second = await postRequest(reporterAccount.token, requestBody(asset.id, { summary: 'Dup target' }));
  await triage(admin.token, second.payload.request.id, 'duplicate', { duplicateOfId: first.payload.request.id });

  const again = await triage(admin.token, second.payload.request.id, 'duplicate', {
    duplicateOfId: first.payload.request.id
  });
  assert.strictEqual(again.response.status, 409);
  assert.strictEqual(again.payload.message, 'this Request has already been triaged');
});

// ---------------------------------------------------------------------------
// The work order path is unchanged: one raised directly has no request behind
// it (ADR-0014), and an accepted one is the only shape that gets a link.
// ---------------------------------------------------------------------------

test('a directly-raised work order has no request behind it, and an unaccepted request has no work order', async () => {
  const asset = await insertAsset(grantedLine.id);
  const raised = await postWorkOrder(admin.token, {
    assetId: asset.id,
    summary: 'Raised by maintenance itself',
    workType: 'corrective',
    priority: 3
  });
  assert.strictEqual(raised.response.status, 201);

  const { rows: [workOrder] } = await pool.query('SELECT maintenance_request_id FROM work_orders WHERE id = $1', [
    raised.payload.workOrder.id
  ]);
  assert.strictEqual(workOrder.maintenance_request_id, null);

  const request = await postRequest(reporterAccount.token, requestBody(asset.id, { summary: 'Not yet accepted' }));
  const { payload } = await getMine(reporterAccount.token, site.id);
  const listed = payload.requests.find((r) => r.id === request.payload.request.id);
  assert.ok(listed);
  assert.strictEqual(listed.workOrder, null);
});
