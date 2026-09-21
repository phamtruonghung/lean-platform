/*
 * Recording a Safety observation at a shared floor device over HTTP (issue
 * #230, ADR-0016), against a real database and a real (locally issued)
 * JWKS — the same seam floor-safety-incident.test.js uses, whose fixture
 * scaffolding this file mirrors closely, with safety-observations.test.js's
 * own field names and conventions on top.
 *
 * The point of every test here is the one AGENTS.md §5 makes for the backend
 * seam: the device door's refusals are proven at the HTTP door with real
 * requests carrying real headers, and the record the door writes is read
 * back out of the database — never by asserting that a Screen hid a button
 * and never by calling the service function.
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

async function json(response) {
  return { status: response.status, body: await response.json() };
}

async function insertAccount({ role = 'operator', grants = [] } = {}) {
  const subject = uniqueCode('fsoacct');
  const { rows: [account] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status)
     VALUES ($1, 'Floor Safety Observation Test Account', $2, $3, TRUE, 'approved') RETURNING id`,
    [`${subject}@example.com`, role, subject]
  );
  insertedAccountIds.push(account.id);

  for (const grant of grants) {
    await pool.query(
      `INSERT INTO app_user_org_units (app_user_id, org_unit_id, can_write)
       VALUES ($1, $2, $3)`,
      [account.id, grant.orgUnitId, grant.write ?? true]
    );
  }

  return { id: account.id, token: await authHeader(subject) };
}

async function insertSite() {
  const { rows: [site] } = await pool.query(
    `INSERT INTO sites (code, name, timezone)
     VALUES ($1, 'Floor Safety Observation Test Site', 'Asia/Ho_Chi_Minh') RETURNING id, code`,
    [uniqueCode('FSO')]
  );
  insertedSiteIds.push(site.id);
  return site;
}

async function insertOrgUnit(siteId, { parentId = null, unitType = 'area', name = 'FSO Unit' } = {}) {
  const { rows: [orgUnit] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, $2, $3, $4, $5) RETURNING id, code, name, path`,
    [siteId, parentId, uniqueCode('FSOOU'), name, unitType]
  );
  insertedOrgUnitIds.push(orgUnit.id);
  return orgUnit;
}

async function insertEmployee({ displayName = 'Ola Observer' } = {}) {
  const [firstName, ...rest] = displayName.split(' ');
  const { rows: [employee] } = await pool.query(
    `INSERT INTO employees (employee_no, first_name, last_name, is_active)
     VALUES ($1, $2, $3, TRUE) RETURNING id, employee_no, display_name`,
    [uniqueCode('FSOEMP'), firstName, rest.join(' ') || 'Employee']
  );
  insertedEmployeeIds.push(employee.id);
  return employee;
}

async function postJson(path, headers, body) {
  const response = await fetch(`${base}${path}`, {
    method: 'POST',
    headers: { ...headers, 'content-type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body)
  });
  return json(response);
}

async function putJson(path, headers, body) {
  const response = await fetch(`${base}${path}`, {
    method: 'PUT',
    headers: { ...headers, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  return json(response);
}

// Registers a device against an Org Unit through the real endpoint, People's
// own route mounted under the frozen `/api/maintenance` prefix (issue #201).
async function registerDevice(orgUnitId, name = 'Line 1 terminal') {
  const { status, body } = await postJson('/api/maintenance/floor-devices', admin.token, {
    orgUnitId,
    name
  });
  assert.strictEqual(status, 201, JSON.stringify(body));
  insertedDeviceIds.push(body.device.id);
  return body;
}

async function setTechnicianPin(employeeId, pin) {
  const { status, body } = await putJson(
    `/api/maintenance/floor-technician-credentials/${employeeId}`,
    admin.token,
    { pin }
  );
  assert.strictEqual(status, 200, JSON.stringify(body));
  return body;
}

async function identify(deviceCredential, employeeNo, pin) {
  return postJson(
    '/api/maintenance/floor/identify',
    { 'x-floor-device': deviceCredential },
    { employeeNo, pin }
  );
}

// The floor door's two headers. Omitting `identification` is what proves the
// device alone can never write.
function floorHeaders(deviceCredential, identification) {
  return {
    'x-floor-device': deviceCredential,
    ...(identification ? { 'x-technician-identification': identification } : {})
  };
}

// Records through the floor door — the address this ticket creates.
async function recordFromFloor(deviceCredential, identification, body) {
  return postJson(
    '/api/safety/floor/observations',
    floorHeaders(deviceCredential, identification),
    body
  );
}

// Records through the Account door, the slice this ticket also builds.
async function recordFromAccount(token, siteId, body) {
  return postJson(`/api/safety/sites/${siteId}/observations`, token, body);
}

let admin;
let site;
let area;
let deviceLine;
let deviceCell;
let otherLine;

let device;
let technician;

// A valid identification, minted fresh for one test. Short-lived by design
// (two minutes), so every test that writes asks for its own.
async function identifyTechnician() {
  const { status, body } = await identify(device.credential, technician.employee_no, '4321');
  assert.strictEqual(status, 200, JSON.stringify(body));
  return body.identification;
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

  admin = await insertAccount({ role: 'admin' });

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

  technician = await insertEmployee({ displayName: 'Ola Observer' });
  const registered = await registerDevice(deviceLine.id, 'Device Line terminal');
  device = { id: registered.device.id, credential: registered.credential };
  await setTechnicianPin(technician.id, '4321');
});

test.after(async () => {
  // Children before parents: a Safety observation references the Org Unit,
  // the Account (recorded_by_account_id) and the Employee (observer_employee_id).
  await pool.query(
    `DELETE FROM safety_observations
      WHERE org_unit_id IN (SELECT id FROM org_units WHERE site_id = ANY($1))`,
    [insertedSiteIds]
  );
  await pool.query(
    'DELETE FROM technician_identifications WHERE floor_device_id = ANY($1)',
    [insertedDeviceIds]
  );
  await pool.query('DELETE FROM employee_floor_credentials WHERE employee_id = ANY($1)', [
    insertedEmployeeIds
  ]);
  await pool.query('DELETE FROM floor_devices WHERE id = ANY($1)', [insertedDeviceIds]);
  await pool.query('DELETE FROM employees WHERE id = ANY($1)', [insertedEmployeeIds]);
  await pool.query('DELETE FROM app_user_org_units WHERE app_user_id = ANY($1)', [
    insertedAccountIds
  ]);
  await pool.query('DELETE FROM app_users WHERE id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM org_units WHERE id = ANY($1)', [insertedOrgUnitIds]);
  await pool.query('DELETE FROM sites WHERE id = ANY($1)', [insertedSiteIds]);
  await new Promise((resolve) => server.close(resolve));
  await closePool();
  await jwks.close();
});

// ---------------------------------------------------------------------------
// Recording: the device's own Org Unit and beneath it.
// ---------------------------------------------------------------------------

test('a device with a valid credential and identification records at its own Org Unit, naming the Employee as observer', async () => {
  const identification = await identifyTechnician();

  const { status, body } = await recordFromFloor(device.credential, identification, {
    orgUnitId: String(deviceLine.id),
    observationType: 'unsafe_condition',
    category: 'housekeeping',
    severityPotential: 'medium',
    description: 'Boxes stacked too close to a fire exit.'
  });

  assert.strictEqual(status, 201, JSON.stringify(body));
  assert.strictEqual(body.observation.orgUnitId, String(deviceLine.id));
  assert.strictEqual(body.observation.observationType, 'unsafe_condition');

  // The identified Employee is the observer, and there is no Account on this
  // path at all (ADR-0016: the device is not a person and most of a plant
  // cannot sign in).
  assert.strictEqual(String(body.observation.observerEmployeeId), String(technician.id));
  assert.strictEqual(body.observation.recordedByAccountId, null);

  const { rows: [row] } = await pool.query(
    'SELECT observer_employee_id, recorded_by_account_id FROM safety_observations WHERE id = $1',
    [body.observation.id]
  );
  assert.strictEqual(String(row.observer_employee_id), String(technician.id));
  assert.strictEqual(row.recorded_by_account_id, null);
});

test('a device records a Safety observation beneath its own Org Unit too', async () => {
  const identification = await identifyTechnician();

  const { status, body } = await recordFromFloor(device.credential, identification, {
    orgUnitId: String(deviceCell.id),
    observationType: 'safe_act',
    category: 'procedure',
    severityPotential: 'low',
    description: 'A machine was locked out correctly before service.'
  });

  assert.strictEqual(status, 201, JSON.stringify(body));
  assert.strictEqual(body.observation.orgUnitId, String(deviceCell.id));
  assert.strictEqual(String(body.observation.observerEmployeeId), String(technician.id));
});

test('a device may not record at an Org Unit outside its own subtree', async () => {
  const identification = await identifyTechnician();

  const { status, body } = await recordFromFloor(device.credential, identification, {
    orgUnitId: String(otherLine.id),
    observationType: 'unsafe_act',
    category: 'traffic',
    severityPotential: 'medium',
    description: 'Attempting to record outside the device subtree.'
  });

  assert.strictEqual(status, 403);
  assert.strictEqual(body.message, "Outside the caller's granted Org Units");

  // Nothing was written: the refusal happened before the record was made.
  const { rows } = await pool.query(
    'SELECT id FROM safety_observations WHERE org_unit_id = $1',
    [otherLine.id]
  );
  assert.strictEqual(rows.length, 0);
});

// ---------------------------------------------------------------------------
// Every observation names its recorder; neither door may leave one blank.
// ---------------------------------------------------------------------------

test('the observer is the identified Employee and there is no recording Account, asserted explicitly', async () => {
  const identification = await identifyTechnician();

  const { status, body } = await recordFromFloor(device.credential, identification, {
    orgUnitId: String(deviceLine.id),
    observationType: 'unsafe_act',
    category: 'ergonomics',
    severityPotential: 'low',
    description: 'An awkward lift was performed without help.'
  });

  assert.strictEqual(status, 201, JSON.stringify(body));
  assert.strictEqual(String(body.observation.observerEmployeeId), String(technician.id));
  assert.strictEqual(body.observation.observerEmployeeName, technician.display_name);
  assert.strictEqual(body.observation.recordedByAccountId, null);
  assert.strictEqual(body.observation.recordedByAccountName, null);

  // Neither door may ever produce an observation with no author at all.
  assert.ok(
    body.observation.observerEmployeeId !== null || body.observation.recordedByAccountId !== null,
    'the observation has no author'
  );
});

test('a Safety observation recorded by an Account is unchanged: recorded-by-account, no observer employee', async () => {
  const recorder = await insertAccount({
    role: 'operator',
    grants: [{ orgUnitId: deviceLine.id, write: true }]
  });

  const { status, body } = await recordFromAccount(recorder.token, site.id, {
    orgUnitId: String(deviceLine.id),
    observationType: 'safe_act',
    category: 'machine_guarding',
    severityPotential: 'low',
    description: 'A guard was replaced immediately after maintenance.'
  });

  assert.strictEqual(status, 201, JSON.stringify(body));
  assert.strictEqual(String(body.observation.recordedByAccountId), String(recorder.id));
  assert.strictEqual(body.observation.observerEmployeeId, null);

  assert.ok(
    body.observation.observerEmployeeId !== null || body.observation.recordedByAccountId !== null,
    'the observation has no author'
  );
});

// ---------------------------------------------------------------------------
// The door: a device alone never writes, and an identification is proven.
// ---------------------------------------------------------------------------

test('a request with no device credential, or an unknown one, is refused', async () => {
  const body = {
    orgUnitId: String(deviceLine.id),
    observationType: 'safe_act',
    category: 'other',
    severityPotential: 'low',
    description: 'No device credential at all.'
  };

  const noDevice = await postJson('/api/safety/floor/observations', {}, body);
  assert.strictEqual(noDevice.status, 401);

  const unknownDevice = await postJson(
    '/api/safety/floor/observations',
    { 'x-floor-device': 'not-a-real-credential' },
    body
  );
  assert.strictEqual(unknownDevice.status, 401);
  assert.strictEqual(unknownDevice.body.message, 'Invalid or inactive floor device');
});

test('a device credential on its own is refused every write', async () => {
  const { status, body } = await recordFromFloor(device.credential, null, {
    orgUnitId: String(deviceLine.id),
    observationType: 'safe_act',
    category: 'other',
    severityPotential: 'low',
    description: 'No identification presented.'
  });

  assert.strictEqual(status, 401);
  assert.strictEqual(body.message, 'An individual identification is required to write here');
});

test('a make-believe identification is refused', async () => {
  const { status, body } = await recordFromFloor(device.credential, 'made-up-token', {
    orgUnitId: String(deviceLine.id),
    observationType: 'safe_act',
    category: 'other',
    severityPotential: 'low',
    description: 'A made-up identification token.'
  });

  assert.strictEqual(status, 401);
  assert.strictEqual(body.message, 'This identification is invalid or has expired');
});

test('an expired identification is refused', async () => {
  const identification = await identifyTechnician();

  // Move the window into the past rather than sleeping: this is the same row
  // the server reads, and the write below is a real HTTP request.
  await pool.query(
    `UPDATE technician_identifications
        SET expires_at = now() - interval '1 second'
      WHERE floor_device_id = $1`,
    [device.id]
  );

  const { status } = await recordFromFloor(device.credential, identification, {
    orgUnitId: String(deviceLine.id),
    observationType: 'safe_act',
    category: 'other',
    severityPotential: 'low',
    description: 'An expired identification.'
  });

  assert.strictEqual(status, 401);
});

// ---------------------------------------------------------------------------
// The same rules on both doors — recordSafetyObservation is reused, not
// duplicated: one invalid body, sent through both doors, gets the same 400.
// ---------------------------------------------------------------------------

test('the same field-validation rule refuses an invalid category on both doors', async () => {
  const identification = await identifyTechnician();
  const recorder = await insertAccount({
    role: 'operator',
    grants: [{ orgUnitId: deviceLine.id, write: true }]
  });

  const invalidBody = {
    orgUnitId: String(deviceLine.id),
    observationType: 'unsafe_act',
    category: 'not-a-real-category',
    severityPotential: 'low',
    description: 'The same invalid body sent through both doors.'
  };

  const floorResult = await recordFromFloor(device.credential, identification, invalidBody);
  const accountResult = await recordFromAccount(recorder.token, site.id, invalidBody);

  assert.strictEqual(floorResult.status, 400);
  assert.strictEqual(accountResult.status, 400);
  assert.strictEqual(floorResult.body.message, accountResult.body.message);
});
