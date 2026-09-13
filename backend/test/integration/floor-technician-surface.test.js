/*
 * The floor technician surface over HTTP (issue #77, ADR-0016), against a real
 * database and a real (locally issued) JWKS — the same seam as
 * work-orders.test.js, whose fixture scaffolding this file mirrors.
 *
 * The point of every test here is the one AGENTS.md §5 makes for the backend
 * seam: a device-only write being refused is proven at the HTTP door, not by
 * asserting that a Screen hid a button. The device credential, the technician
 * identification and the Org Unit scope are all exercised by real requests
 * carrying real headers.
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
const insertedWorkOrderIds = [];
const insertedEmployeeIds = [];
const insertedDeviceIds = [];

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

async function insertAccount({ role = 'supervisor', isActive = true } = {}) {
  const subject = uniqueCode('acct');
  const { rows: [row] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status)
     VALUES ($1, 'Floor Test Account', $2, $3, $4, 'approved') RETURNING id`,
    [`${subject}@example.com`, role, subject, isActive]
  );
  insertedAccountIds.push(row.id);
  return { id: row.id, token: await authHeader(subject) };
}

async function insertGrant({ accountId, orgUnitId, canWrite = false }) {
  await pool.query(
    `INSERT INTO app_user_org_units (app_user_id, org_unit_id, can_write) VALUES ($1, $2, $3)`,
    [accountId, orgUnitId, canWrite]
  );
}

async function insertSite() {
  const { rows: [row] } = await pool.query(
    `INSERT INTO sites (code, name, timezone) VALUES ($1, 'Floor Test Site', 'Asia/Ho_Chi_Minh') RETURNING id, code`,
    [uniqueCode('ST')]
  );
  insertedSiteIds.push(row.id);
  return row;
}

async function insertOrgUnit(siteId, { parentId = null, unitType = 'area', name = 'Floor Test Unit' } = {}) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, $2, $3, $4, $5) RETURNING id, code, name`,
    [siteId, parentId, uniqueCode('OU'), name, unitType]
  );
  insertedOrgUnitIds.push(row.id);
  return row;
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

async function insertEmployee({ isActive = true, displayName = 'Floor Technician' } = {}) {
  const [firstName, ...rest] = displayName.split(' ');
  const lastName = rest.join(' ') || 'Employee';
  const { rows: [row] } = await pool.query(
    `INSERT INTO employees (employee_no, first_name, last_name, is_active)
     VALUES ($1, $2, $3, $4) RETURNING id, employee_no, display_name`,
    [uniqueCode('EMP'), firstName, lastName, isActive]
  );
  insertedEmployeeIds.push(row.id);
  return row;
}

async function postJson(path, headers, body) {
  const response = await fetch(`${base}${path}`, {
    method: 'POST',
    headers: { ...headers, 'content-type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body)
  });
  const payload = await response.json().catch(() => null);
  return { response, payload };
}

async function putJson(path, headers, body) {
  const response = await fetch(`${base}${path}`, {
    method: 'PUT',
    headers: { ...headers, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  const payload = await response.json().catch(() => null);
  return { response, payload };
}

async function getJson(path, headers) {
  const response = await fetch(`${base}${path}`, { headers });
  const payload = await response.json().catch(() => null);
  return { response, payload };
}

// Registers a device through the real endpoint and returns its credential —
// the one-time secret only this response ever carries.
async function registerDevice(admin, orgUnitId, name = 'Line 1 terminal') {
  const { response, payload } = await postJson(
    '/api/maintenance/floor-devices',
    admin.token,
    { orgUnitId, name }
  );
  assert.strictEqual(response.status, 201, JSON.stringify(payload));
  insertedDeviceIds.push(payload.device.id);
  return payload;
}

async function setTechnicianPin(admin, employeeId, pin) {
  const { response, payload } = await putJson(
    `/api/maintenance/floor-technician-credentials/${employeeId}`,
    admin.token,
    { pin }
  );
  assert.strictEqual(response.status, 200, JSON.stringify(payload));
  return payload;
}

async function identify(deviceCredential, employeeNo, pin) {
  const response = await fetch(`${base}/api/maintenance/floor/identify`, {
    method: 'POST',
    headers: { 'x-floor-device': deviceCredential, 'content-type': 'application/json' },
    body: JSON.stringify({ employeeNo, pin })
  });
  const payload = await response.json().catch(() => null);
  return { response, payload };
}

function floorHeaders(deviceCredential, identification) {
  return {
    'x-floor-device': deviceCredential,
    ...(identification ? { 'x-technician-identification': identification } : {})
  };
}

async function startWorkOrder(headers, workOrderId) {
  return postJson(`/api/maintenance/work-orders/${workOrderId}/start`, headers);
}

async function completeWorkOrder(headers, workOrderId, note) {
  return postJson(`/api/maintenance/work-orders/${workOrderId}/complete`, headers, { note });
}

async function raiseWorkOrder(admin, assetId, summary) {
  const { response, payload } = await postJson('/api/maintenance/work-orders', admin.token, {
    assetId,
    summary,
    workType: 'corrective',
    priority: 3
  });
  assert.strictEqual(response.status, 201, JSON.stringify(payload));
  insertedWorkOrderIds.push(payload.workOrder.id);
  return payload.workOrder;
}

let admin;
let lineWriter;
let otherWriter;

let site;
let area;
let deviceLine;
let deviceCell;
let otherLine;

let device;
let technician;
let otherTechnician;

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
  lineWriter = await insertAccount({ role: 'supervisor' });
  otherWriter = await insertAccount({ role: 'supervisor' });

  site = await insertSite();
  area = await insertOrgUnit(site.id, { name: 'Floor Area' });
  deviceLine = await insertOrgUnit(site.id, {
    parentId: area.id,
    unitType: 'line',
    name: 'Device Line'
  });
  deviceCell = await insertOrgUnit(site.id, {
    parentId: deviceLine.id,
    unitType: 'cell',
    name: 'Device Cell'
  });
  otherLine = await insertOrgUnit(site.id, {
    parentId: area.id,
    unitType: 'line',
    name: 'Other Line'
  });

  await insertGrant({ accountId: lineWriter.id, orgUnitId: deviceLine.id, canWrite: true });
  await insertGrant({ accountId: otherWriter.id, orgUnitId: otherLine.id, canWrite: true });

  technician = await insertEmployee({ displayName: 'Tess Technician' });
  otherTechnician = await insertEmployee({ displayName: 'Owen Other' });

  const registered = await registerDevice(admin, deviceLine.id, 'Device Line terminal');
  device = { id: registered.device.id, credential: registered.credential };
  await setTechnicianPin(admin, technician.id, '4321');
});

test.after(async () => {
  await pool.query('DELETE FROM work_orders WHERE id = ANY($1)', [insertedWorkOrderIds]);
  await pool.query(
    'DELETE FROM technician_identifications WHERE floor_device_id = ANY($1)',
    [insertedDeviceIds]
  );
  await pool.query(
    'DELETE FROM employee_floor_credentials WHERE employee_id = ANY($1)',
    [insertedEmployeeIds]
  );
  await pool.query('DELETE FROM floor_devices WHERE id = ANY($1)', [insertedDeviceIds]);
  await pool.query('DELETE FROM employees WHERE id = ANY($1)', [insertedEmployeeIds]);
  await pool.query('DELETE FROM assets WHERE id = ANY($1)', [insertedAssetIds]);
  await pool.query('DELETE FROM app_users WHERE id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM org_units WHERE id = ANY($1)', [insertedOrgUnitIds]);
  await pool.query('DELETE FROM sites WHERE id = ANY($1)', [insertedSiteIds]);
  await new Promise((resolve) => server.close(resolve));
  await closePool();
  await jwks.close();
});

// ---------------------------------------------------------------------------
// Registering a device and provisioning a technician credential.
// ---------------------------------------------------------------------------

test('an administrator registers a device against an Org Unit and gets a credential exactly once', async () => {
  const registered = await registerDevice(admin, deviceLine.id, 'Second terminal');
  assert.ok(registered.credential, 'the credential is returned');
  assert.strictEqual(registered.device.orgUnitId, String(deviceLine.id));
  assert.strictEqual(registered.device.name, 'Second terminal');

  // The presentable value is nowhere on the row — only its hash.
  const { rows: [row] } = await pool.query(
    'SELECT credential_hash FROM floor_devices WHERE id = $1',
    [registered.device.id]
  );
  assert.notStrictEqual(row.credential_hash, registered.credential);
  assert.match(row.credential_hash, /^[0-9a-f]{64}$/);
});

test('a write Grant reaching the Org Unit may register a device, and one that does not reach it may not', async () => {
  const registered = await registerDevice(lineWriter, deviceLine.id, 'Granted terminal');
  assert.strictEqual(registered.device.orgUnitId, String(deviceLine.id));

  const refused = await postJson('/api/maintenance/floor-devices', otherWriter.token, {
    orgUnitId: deviceLine.id,
    name: 'Should not exist'
  });
  assert.strictEqual(refused.response.status, 403);
  assert.strictEqual(refused.payload.message, "Outside the caller's granted Org Units");
});

test('only an administrator sets a technician PIN', async () => {
  const pin = await putJson(
    `/api/maintenance/floor-technician-credentials/${technician.id}`,
    lineWriter.token,
    { pin: '9999' }
  );
  assert.strictEqual(pin.response.status, 403);

  const unknown = await putJson(
    '/api/maintenance/floor-technician-credentials/999999999',
    admin.token,
    { pin: '9999' }
  );
  assert.strictEqual(unknown.response.status, 404);
});

test('a device registered against an unknown Org Unit is a 404', async () => {
  const { response, payload } = await postJson('/api/maintenance/floor-devices', admin.token, {
    orgUnitId: '999999999',
    name: 'Nowhere'
  });
  assert.strictEqual(response.status, 404);
  assert.strictEqual(payload.message, 'Org Unit not found');
});

test('a PIN is never stored in the clear and is never returned', async () => {
  const employee = await insertEmployee({ displayName: 'Prue Pin' });
  const response = await putJson(
    `/api/maintenance/floor-technician-credentials/${employee.id}`,
    admin.token,
    { pin: '1357' }
  );
  assert.strictEqual(response.response.status, 200);
  assert.ok(!JSON.stringify(response.payload).includes('1357'));

  const { rows: [row] } = await pool.query(
    'SELECT pin_hash FROM employee_floor_credentials WHERE employee_id = $1',
    [employee.id]
  );
  assert.ok(row.pin_hash.startsWith('scrypt$'));
  assert.ok(!row.pin_hash.includes('1357'));
});

// ---------------------------------------------------------------------------
// Reading: only the device's own Org Unit and beneath.
// ---------------------------------------------------------------------------

test('the floor read refuses a request with no device credential at all', async () => {
  const { response } = await getJson('/api/maintenance/floor/work-orders', {});
  assert.strictEqual(response.status, 401);
});

test('the floor read refuses an unknown device credential', async () => {
  const { response } = await getJson('/api/maintenance/floor/work-orders', {
    'x-floor-device': 'not-a-real-credential'
  });
  assert.strictEqual(response.status, 401);
});

test("the floor read shows the device's Org Unit and everything beneath it, and nothing outside", async () => {
  const insideAtLine = await insertAsset(deviceLine.id, { name: 'Press on the line' });
  const insideAtCell = await insertAsset(deviceCell.id, { name: 'Press in the cell' });
  const outside = await insertAsset(otherLine.id, { name: 'Press elsewhere' });

  const insideLineWo = await raiseWorkOrder(admin, insideAtLine.id, 'On the device line');
  const insideCellWo = await raiseWorkOrder(admin, insideAtCell.id, 'In the device cell');
  const outsideWo = await raiseWorkOrder(admin, outside.id, 'On a sibling line');

  const { response, payload } = await getJson(
    '/api/maintenance/floor/work-orders',
    floorHeaders(device.credential)
  );
  assert.strictEqual(response.status, 200);
  assert.strictEqual(payload.floor.orgUnitId, String(deviceLine.id));

  const ids = payload.workOrders.map((w) => w.id);
  assert.ok(ids.includes(insideLineWo.id), 'the device Org Unit itself is in scope');
  assert.ok(ids.includes(insideCellWo.id), 'a descendant is in scope');
  assert.ok(!ids.includes(outsideWo.id), 'a sibling branch is out of scope');
});

// ---------------------------------------------------------------------------
// Every write: the device alone can never, the identification decides.
// ---------------------------------------------------------------------------

test('a device credential is refused every write on its own', async () => {
  const asset = await insertAsset(deviceLine.id);
  const workOrder = await raiseWorkOrder(admin, asset.id, 'Device-only start');

  const start = await startWorkOrder(floorHeaders(device.credential), workOrder.id);
  assert.strictEqual(start.response.status, 401);

  const { rows: [row] } = await pool.query('SELECT status FROM work_orders WHERE id = $1', [
    workOrder.id
  ]);
  assert.strictEqual(row.status, 'approved');
});

test('a make-believe identification is refused', async () => {
  const asset = await insertAsset(deviceLine.id);
  const workOrder = await raiseWorkOrder(admin, asset.id, 'Fake identification');

  const { response } = await startWorkOrder(
    floorHeaders(device.credential, 'made-up-token'),
    workOrder.id
  );
  assert.strictEqual(response.status, 401);
});

test('a wrong PIN is refused, and never says whether the Employee exists', async () => {
  const wrongPin = await identify(device.credential, technician.employee_no, '0000');
  assert.strictEqual(wrongPin.response.status, 401);

  const unknown = await identify(device.credential, 'EMP-DOES-NOT-EXIST', '4321');
  assert.strictEqual(unknown.response.status, 401);
  assert.strictEqual(unknown.payload.message, wrongPin.payload.message);
});

test('a write succeeds only with an individual identification, and records who did it', async () => {
  const asset = await insertAsset(deviceLine.id);
  const workOrder = await raiseWorkOrder(admin, asset.id, 'Identified start');
  const identified = await identify(device.credential, technician.employee_no, '4321');
  assert.strictEqual(identified.response.status, 200);
  const token = identified.payload.identification;

  const start = await startWorkOrder(floorHeaders(device.credential, token), workOrder.id);
  assert.strictEqual(start.response.status, 200, JSON.stringify(start.payload));
  assert.strictEqual(start.payload.workOrder.status, 'in_progress');

  const { rows: [started] } = await pool.query(
    'SELECT started_by, status FROM work_orders WHERE id = $1',
    [workOrder.id]
  );
  assert.strictEqual(String(started.started_by), String(technician.id));

  const complete = await completeWorkOrder(
    floorHeaders(device.credential, token),
    workOrder.id,
    'Repaired on the floor'
  );
  assert.strictEqual(complete.response.status, 200, JSON.stringify(complete.payload));
  assert.strictEqual(complete.payload.workOrder.status, 'completed');

  const { rows: [completed] } = await pool.query(
    'SELECT completed_by, completion_note FROM work_orders WHERE id = $1',
    [workOrder.id]
  );
  assert.strictEqual(String(completed.completed_by), String(technician.id));
  assert.strictEqual(completed.completion_note, 'Repaired on the floor');
});

test('a technician who is not assigned the work can still record it, and is recorded accurately', async () => {
  const asset = await insertAsset(deviceLine.id);
  const workOrder = await raiseWorkOrder(admin, asset.id, 'Somebody else was assigned');

  // Assigned to a different Employee entirely.
  await putJson(`/api/maintenance/work-orders/${workOrder.id}/assignee`, admin.token, {
    employeeId: otherTechnician.id
  });

  const identified = await identify(device.credential, technician.employee_no, '4321');
  const token = identified.payload.identification;
  await startWorkOrder(floorHeaders(device.credential, token), workOrder.id);
  const complete = await completeWorkOrder(
    floorHeaders(device.credential, token),
    workOrder.id,
    'Done by whoever was at the machine'
  );
  assert.strictEqual(complete.response.status, 200);

  const { rows: [row] } = await pool.query(
    'SELECT assigned_to, completed_by FROM work_orders WHERE id = $1',
    [workOrder.id]
  );
  assert.strictEqual(String(row.assigned_to), String(otherTechnician.id));
  assert.strictEqual(String(row.completed_by), String(technician.id));
});

test("an identification is not reusable beyond its window", async () => {
  const asset = await insertAsset(deviceLine.id);
  const workOrder = await raiseWorkOrder(admin, asset.id, 'Expired identification');
  const identified = await identify(device.credential, technician.employee_no, '4321');
  const token = identified.payload.identification;

  // Move the window into the past rather than sleeping: this is the same row
  // the server reads, and the write below is still a real HTTP request.
  await pool.query(
    `UPDATE technician_identifications
        SET expires_at = now() - interval '1 second'
      WHERE floor_device_id = $1`,
    [device.id]
  );

  const start = await startWorkOrder(floorHeaders(device.credential, token), workOrder.id);
  assert.strictEqual(start.response.status, 401);
});

test('an identification issued on one device is refused on another', async () => {
  const second = await registerDevice(admin, deviceCell.id, 'Second terminal');
  const asset = await insertAsset(deviceLine.id);
  const workOrder = await raiseWorkOrder(admin, asset.id, 'Cross-device identification');

  const identified = await identify(device.credential, technician.employee_no, '4321');
  const token = identified.payload.identification;

  const crossDevice = await startWorkOrder(floorHeaders(second.credential, token), workOrder.id);
  assert.strictEqual(crossDevice.response.status, 401);
});

test("a device cannot write a Work order outside its own Org Unit's subtree", async () => {
  const asset = await insertAsset(otherLine.id);
  const workOrder = await raiseWorkOrder(admin, asset.id, 'Outside the device tree');
  const identified = await identify(device.credential, technician.employee_no, '4321');

  const { response } = await startWorkOrder(
    floorHeaders(device.credential, identified.payload.identification),
    workOrder.id
  );
  assert.strictEqual(response.status, 403);
});

// ---------------------------------------------------------------------------
// The desktop door is unchanged.
// ---------------------------------------------------------------------------

test('an Account can still start and complete a Work order without any device header', async () => {
  const asset = await insertAsset(deviceLine.id);
  const workOrder = await raiseWorkOrder(admin, asset.id, 'Desktop completion stays');

  const start = await startWorkOrder(admin.token, workOrder.id);
  assert.strictEqual(start.response.status, 200);
  const complete = await completeWorkOrder(admin.token, workOrder.id, 'Closed from the office');
  assert.strictEqual(complete.response.status, 200);

  // An Account is not an Employee, so completed_by stays null as it always has.
  const { rows: [row] } = await pool.query('SELECT completed_by FROM work_orders WHERE id = $1', [
    workOrder.id
  ]);
  assert.strictEqual(row.completed_by, null);
});

test('a request with no bearer token and no device header is still refused', async () => {
  const asset = await insertAsset(deviceLine.id);
  const workOrder = await raiseWorkOrder(admin, asset.id, 'No door');

  const response = await fetch(`${base}/api/maintenance/work-orders/${workOrder.id}/start`, {
    method: 'POST'
  });
  assert.strictEqual(response.status, 401);
});
