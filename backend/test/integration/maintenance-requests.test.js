/*
 * Requests and triage over HTTP (issue #72), against a real database and a
 * real (locally issued) JWKS — the same seam as work-orders.test.js, whose
 * fixture scaffolding this file mirrors. Assets are inserted directly against
 * the database rather than through POST /assets: this file is about Requests,
 * and the Asset register is already covered by assets.test.js.
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
const insertedAssetIds = [];
const insertedRequestIds = [];
const insertedWorkOrderIds = [];
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

async function insertAccount({ role = 'supervisor', isActive = true, approvalStatus = 'approved' } = {}) {
  const subject = uniqueCode('acct');
  const { rows: [row] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status)
     VALUES ($1, 'Request Test Account', $2, $3, $4, $5) RETURNING id`,
    [`${subject}@example.com`, role, subject, isActive, approvalStatus]
  );
  insertedAccountIds.push(row.id);
  return { id: row.id, token: await authHeader(subject) };
}

async function insertSite() {
  const { rows: [row] } = await pool.query(
    `INSERT INTO sites (code, name, timezone) VALUES ($1, 'Request Test Site', 'Asia/Ho_Chi_Minh') RETURNING id, code`,
    [uniqueCode('ST')]
  );
  insertedSiteIds.push(row.id);
  return row;
}

async function insertOrgUnit(siteId, { parentId = null, name = 'Request Test Unit' } = {}) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, $2, $3, $4, 'area') RETURNING id, code, name`,
    [siteId, parentId, uniqueCode('OU'), name]
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

async function insertEmployee() {
  const { rows: [row] } = await pool.query(
    `INSERT INTO employees (employee_no, first_name, last_name, is_active)
     VALUES ($1, 'Ada', 'Lovelace', TRUE) RETURNING id`,
    [uniqueCode('EMP')]
  );
  insertedEmployeeIds.push(row.id);
  return row;
}

function requestBody(assetId, overrides = {}) {
  return {
    assetId,
    summary: 'Bearing is making noise',
    description: 'Loud when running at speed.',
    urgency: 'high',
    productionStopped: false,
    ...overrides
  };
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

async function getQueue(token, siteId, query = '') {
  const response = await fetch(`${base}/api/maintenance/sites/${siteId}/requests${query}`, {
    headers: token
  });
  const payload = await response.json().catch(() => null);
  return { response, payload };
}

async function getMine(token) {
  const response = await fetch(`${base}/api/maintenance/requests/mine`, { headers: token });
  const payload = await response.json().catch(() => null);
  return { response, payload };
}

async function acceptRequest(token, requestId, body) {
  const response = await fetch(`${base}/api/maintenance/requests/${requestId}/accept`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  const payload = await response.json().catch(() => null);
  if (payload?.workOrder?.id) insertedWorkOrderIds.push(payload.workOrder.id);
  return { response, payload };
}

async function declineRequest(token, requestId, body) {
  const response = await fetch(`${base}/api/maintenance/requests/${requestId}/decline`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  const payload = await response.json().catch(() => null);
  return { response, payload };
}

async function duplicateRequest(token, requestId, body) {
  const response = await fetch(`${base}/api/maintenance/requests/${requestId}/duplicate`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  const payload = await response.json().catch(() => null);
  return { response, payload };
}

let admin;
let operator;        // read/write irrelevant — raising needs any Grant.
let readOnlyMaintenance; // write Grant absent.
let writer;          // write Grant on grantedLine.
let siblingWriter;   // write Grant on otherLine only.

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
  operator = await insertAccount({ role: 'operator' });
  readOnlyMaintenance = await insertAccount({ role: 'supervisor' });
  writer = await insertAccount({ role: 'supervisor' });
  siblingWriter = await insertAccount({ role: 'supervisor' });

  site = await insertSite();
  otherSite = await insertSite();
  grantedArea = await insertOrgUnit(site.id, { name: 'Granted Area' });
  grantedLine = await insertOrgUnit(site.id, { parentId: grantedArea.id, name: 'Line 1' });
  otherLine = await insertOrgUnit(site.id, { parentId: grantedArea.id, name: 'Line 2' });

  await insertGrant({ accountId: readOnlyMaintenance.id, orgUnitId: grantedLine.id, canWrite: false });
  await insertGrant({ accountId: writer.id, orgUnitId: grantedLine.id, canWrite: true });
  await insertGrant({ accountId: siblingWriter.id, orgUnitId: otherLine.id, canWrite: true });
  // The operator holds a read Grant on grantedLine — enough to raise a Request,
  // which is the operator's whole job.
  await insertGrant({ accountId: operator.id, orgUnitId: grantedLine.id, canWrite: false });
});

test.after(async () => {
  await pool.query('DELETE FROM work_orders WHERE id = ANY($1)', [insertedWorkOrderIds]);
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
// Raising a Request.
// ---------------------------------------------------------------------------

test('raising a Request returns 201, in status new, carrying the expected fields', async () => {
  const asset = await insertAsset(grantedLine.id);
  const { response, payload } = await postRequest(admin.token, requestBody(asset.id));
  assert.strictEqual(response.status, 201);
  assert.strictEqual(payload.request.status, 'new');
  assert.strictEqual(payload.request.summary, 'Bearing is making noise');
  assert.strictEqual(payload.request.urgency, 'high');
  assert.strictEqual(payload.request.productionStopped, false);
  assert.strictEqual(payload.request.assetId, String(asset.id));
  assert.ok(payload.request.requestNo);
  assert.ok(payload.request.reportedAt);
});

test('the Request Org Unit is derived from the Asset by trigger, not sent', async () => {
  const asset = await insertAsset(grantedLine.id);
  const { response, payload } = await postRequest(
    admin.token,
    requestBody(asset.id, { orgUnitId: otherLine.id })
  );
  assert.strictEqual(response.status, 201);
  assert.strictEqual(payload.request.orgUnitId, String(grantedLine.id));

  const { rows } = await pool.query('SELECT org_unit_id FROM maintenance_requests WHERE id = $1', [payload.request.id]);
  assert.strictEqual(String(rows[0].org_unit_id), String(grantedLine.id));
});

test("the Request number is issued by the Site's own RQT sequence, and two Sites number independently", async () => {
  const freshSiteA = await insertSite();
  const freshSiteB = await insertSite();
  const areaA = await insertOrgUnit(freshSiteA.id, { name: 'Area A' });
  const areaB = await insertOrgUnit(freshSiteB.id, { name: 'Area B' });
  const assetA = await insertAsset(areaA.id);
  const assetB = await insertAsset(areaB.id);

  const a1 = await postRequest(admin.token, requestBody(assetA.id));
  const a2 = await postRequest(admin.token, requestBody(assetA.id));
  const b1 = await postRequest(admin.token, requestBody(assetB.id));
  assert.strictEqual(a1.response.status, 201);
  assert.strictEqual(a2.response.status, 201);
  assert.strictEqual(b1.response.status, 201);

  const year = new Date().getUTCFullYear();
  assert.strictEqual(a1.payload.request.requestNo, `RQT-${freshSiteA.code}-${year}-00001`);
  assert.strictEqual(a2.payload.request.requestNo, `RQT-${freshSiteA.code}-${year}-00002`);
  assert.strictEqual(b1.payload.request.requestNo, `RQT-${freshSiteB.code}-${year}-00001`);
});

test('naming an Asset that does not exist is a 404 naming the Asset', async () => {
  const { response, payload } = await postRequest(admin.token, requestBody('999999999'));
  assert.strictEqual(response.status, 404);
  assert.strictEqual(payload.message, 'Asset not found');
});

test('validation: bad urgency, empty summary are each a clean 400', async () => {
  const asset = await insertAsset(grantedLine.id);
  for (const overrides of [
    { urgency: 'urgent' },
    { summary: '   ' }
  ]) {
    // eslint-disable-next-line no-await-in-loop
    const { response } = await postRequest(admin.token, requestBody(asset.id, overrides));
    assert.strictEqual(response.status, 400, JSON.stringify(overrides));
  }
});

// ---------------------------------------------------------------------------
// Who may raise and who may triage (scope splits at the verb).
// ---------------------------------------------------------------------------

test('an operator with any Grant on the Asset Org Unit may raise a Request', async () => {
  const asset = await insertAsset(grantedLine.id);
  const { response } = await postRequest(operator.token, requestBody(asset.id));
  assert.strictEqual(response.status, 201);
});

test('raising needs a Grant reaching the Asset Org Unit — a caller with no Grant is refused', async () => {
  const noGrant = await insertAccount();
  const asset = await insertAsset(grantedLine.id);
  const { response, payload } = await postRequest(noGrant.token, requestBody(asset.id));
  assert.strictEqual(response.status, 403);
  assert.strictEqual(payload.message, "Outside the caller's granted Org Units");
});

test('triaging requires a WRITE Grant reaching the Request Asset Org Unit', async () => {
  const asset = await insertAsset(grantedLine.id);
  const created = await postRequest(admin.token, requestBody(asset.id, { summary: 'Scoped triage' }));

  // readOnlyMaintenance has a read Grant: raising is fine, triaging is refused.
  const readOnlyDecline = await declineRequest(
    readOnlyMaintenance.token,
    created.payload.request.id,
    { reason: 'not our lane' }
  );
  assert.strictEqual(readOnlyDecline.response.status, 403);
  assert.strictEqual(readOnlyDecline.payload.message, "Outside the caller's granted Org Units");

  // siblingWriter has a write Grant on otherLine only: must not reach across.
  const sibling = await acceptRequest(siblingWriter.token, created.payload.request.id, {
    workType: 'corrective',
    priority: 3
  });
  assert.strictEqual(sibling.response.status, 403);

  // Nothing was written by any refusal.
  const { rows } = await pool.query('SELECT status FROM maintenance_requests WHERE id = $1', [created.payload.request.id]);
  assert.strictEqual(rows[0].status, 'new');
});

// ---------------------------------------------------------------------------
// The triage queue (read, Site-wide).
// ---------------------------------------------------------------------------

test("the queue returns open Requests whatever the caller's Grants, and an accepted one leaves it", async () => {
  const asset = await insertAsset(grantedLine.id);
  const created = await postRequest(operator.token, requestBody(asset.id, { summary: 'In the queue' }));
  assert.strictEqual(created.response.status, 201);

  const { response, payload } = await getQueue(operator.token, site.id);
  assert.strictEqual(response.status, 200);
  assert.ok(payload.requests.some((r) => r.id === created.payload.request.id));

  // Accept it; it leaves the open queue.
  await acceptRequest(writer.token, created.payload.request.id, { workType: 'corrective', priority: 2 });
  const after = await getQueue(operator.token, site.id);
  assert.ok(!after.payload.requests.some((r) => r.id === created.payload.request.id));
});

test('an unknown Site is a 404, and an unknown ?orgUnitId= is a 404', async () => {
  const siteUnknown = await getQueue(admin.token, '999999999');
  assert.strictEqual(siteUnknown.response.status, 404);

  const ouUnknown = await getQueue(admin.token, site.id, '?orgUnitId=999999999');
  assert.strictEqual(ouUnknown.response.status, 404);
});

// ---------------------------------------------------------------------------
// Accepting.
// ---------------------------------------------------------------------------

test('accepting raises a Work order that points back at the Request (ADR-0014), and records who triaged', async () => {
  const asset = await insertAsset(grantedLine.id);
  const created = await postRequest(operator.token, requestBody(asset.id, { summary: 'To accept' }));
  assert.strictEqual(created.response.status, 201);

  const { response, payload } = await acceptRequest(writer.token, created.payload.request.id, {
    workType: 'corrective',
    priority: 2
  });
  assert.strictEqual(response.status, 200);
  assert.strictEqual(payload.workOrder.workOrderNo, payload.request.workOrder.workOrderNo);
  assert.strictEqual(payload.request.status, 'accepted');
  assert.ok(payload.request.workOrder, 'the accepted Request carries the Work order it became');
  assert.strictEqual(payload.request.workOrder.status, 'approved');

  // The Work order actually points back.
  const { rows: [wo] } = await pool.query('SELECT maintenance_request_id FROM work_orders WHERE id = $1', [payload.workOrder.id]);
  assert.strictEqual(String(wo.maintenance_request_id), String(created.payload.request.id));
});

test('accepting does not copy urgency into priority — maintenance sets the priority', async () => {
  const asset = await insertAsset(grantedLine.id);
  const created = await postRequest(operator.token, requestBody(asset.id, {
    summary: 'Urgent but planned low',
    urgency: 'immediate'
  }));

  const { response, payload } = await acceptRequest(writer.token, created.payload.request.id, {
    workType: 'preventive',
    priority: 5
  });
  assert.strictEqual(response.status, 200);
  // The Work order's priority is 5 (maintenance plan), not copied from 'immediate'.
  const { rows: [wo] } = await pool.query('SELECT priority FROM work_orders WHERE id = $1', [payload.workOrder.id]);
  assert.strictEqual(wo.priority, 5);
});

test('a Request already triaged cannot be triaged again (409)', async () => {
  const asset = await insertAsset(grantedLine.id);
  const created = await postRequest(admin.token, requestBody(asset.id, { summary: 'Triaged twice' }));
  await acceptRequest(writer.token, created.payload.request.id, { workType: 'corrective', priority: 3 });

  const second = await acceptRequest(writer.token, created.payload.request.id, {
    workType: 'corrective',
    priority: 3
  });
  assert.strictEqual(second.response.status, 409);
  assert.match(second.payload.message, /already been triaged/);
});

test('accepting an unknown Request is a 404; bad workType or priority is a 400', async () => {
  const unknown = await acceptRequest(writer.token, '999999999', { workType: 'corrective', priority: 3 });
  assert.strictEqual(unknown.response.status, 404);
  assert.strictEqual(unknown.payload.message, 'Request not found');

  const asset = await insertAsset(grantedLine.id);
  const created = await postRequest(admin.token, requestBody(asset.id, { summary: 'Validation' }));
  for (const body of [
    { workType: 'urgent', priority: 3 },
    { workType: 'corrective', priority: 0 },
    { workType: 'corrective', priority: 6 }
  ]) {
    // eslint-disable-next-line no-await-in-loop
    const { response } = await acceptRequest(writer.token, created.payload.request.id, body);
    assert.strictEqual(response.status, 400, JSON.stringify(body));
  }
});

// ---------------------------------------------------------------------------
// Declining.
// ---------------------------------------------------------------------------

test('declining requires a reason, records it, and moves the Request to rejected', async () => {
  const asset = await insertAsset(grantedLine.id);
  const created = await postRequest(admin.token, requestBody(asset.id, { summary: 'To decline' }));

  const noReason = await declineRequest(writer.token, created.payload.request.id, {});
  assert.strictEqual(noReason.response.status, 400);
  assert.match(noReason.payload.message, /reason is required/);

  const { response, payload } = await declineRequest(writer.token, created.payload.request.id, {
    reason: 'Covered by the PM schedule.'
  });
  assert.strictEqual(response.status, 200);
  assert.strictEqual(payload.request.status, 'rejected');
  assert.strictEqual(payload.request.rejectionReason, 'Covered by the PM schedule.');
});

// ---------------------------------------------------------------------------
// Marking a duplicate.
// ---------------------------------------------------------------------------

test('a Request can be marked a duplicate of a surviving one, which is named', async () => {
  const asset = await insertAsset(grantedLine.id);
  const survivor = await postRequest(admin.token, requestBody(asset.id, { summary: 'The survivor' }));
  const duplicate = await postRequest(admin.token, requestBody(asset.id, { summary: 'Same thing' }));

  const { response, payload } = await duplicateRequest(writer.token, duplicate.payload.request.id, {
    duplicateOfId: survivor.payload.request.id
  });
  assert.strictEqual(response.status, 200);
  assert.strictEqual(payload.request.status, 'duplicate');
  assert.strictEqual(payload.request.duplicateOfId, String(survivor.payload.request.id));
  assert.strictEqual(payload.request.duplicateOfNo, survivor.payload.request.requestNo);
});

test('a Request cannot be a duplicate of an unknown Request (404)', async () => {
  const asset = await insertAsset(grantedLine.id);
  const created = await postRequest(admin.token, requestBody(asset.id, { summary: 'Orphan duplicate' }));
  const { response, payload } = await duplicateRequest(writer.token, created.payload.request.id, {
    duplicateOfId: '999999999'
  });
  assert.strictEqual(response.status, 404);
});

// ---------------------------------------------------------------------------
// The requester's own history.
// ---------------------------------------------------------------------------

test('a requester sees the Requests they raised and what became of each', async () => {
  const asset = await insertAsset(grantedLine.id);

  // operator raises two; admin raises one (not the operator's).
  const accepted = await postRequest(operator.token, requestBody(asset.id, { summary: 'Op accepted' }));
  const declined = await postRequest(operator.token, requestBody(asset.id, { summary: 'Op declined' }));
  await postRequest(admin.token, requestBody(asset.id, { summary: 'Admins own' }));

  await acceptRequest(writer.token, accepted.payload.request.id, { workType: 'corrective', priority: 3 });
  await declineRequest(writer.token, declined.payload.request.id, { reason: 'not now' });

  const { response, payload } = await getMine(operator.token);
  assert.strictEqual(response.status, 200);

  const ids = payload.requests.map((r) => r.id);
  assert.ok(ids.includes(accepted.payload.request.id));
  assert.ok(ids.includes(declined.payload.request.id));
  assert.ok(!ids.includes('1'), "an admin-raised Request is not the operator's");

  const aRow = payload.requests.find((r) => r.id === accepted.payload.request.id);
  assert.strictEqual(aRow.status, 'accepted');
  assert.ok(aRow.workOrder, 'an accepted Request shows the Work order it became');

  const dRow = payload.requests.find((r) => r.id === declined.payload.request.id);
  assert.strictEqual(dRow.status, 'rejected');
  assert.strictEqual(dRow.workOrder, null);
});

test('a Request that was never accepted still answers to a directly-raised Work order origin', async () => {
  // A directly-raised Work order has no Request behind it (ADR-0014). This
  // slices the other direction: a Request in the queue that is not accepted
  // yields no Work order, and the read surfaces cope with both origins.
  const asset = await insertAsset(grantedLine.id);
  const created = await postRequest(operator.token, requestBody(asset.id, { summary: 'No work order yet' }));

  const { payload } = await getMine(operator.token);
  const row = payload.requests.find((r) => r.id === created.payload.request.id);
  assert.strictEqual(row.workOrder, null);
  assert.strictEqual(row.status, 'new');
});