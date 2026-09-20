/*
 * Recording a Safety incident at a shared floor device over HTTP (issue #227,
 * ADR-0016, ADR-0036), against a real database and a real (locally issued)
 * JWKS — the same seam floor-nonconformance.test.js uses, whose fixture
 * scaffolding this file mirrors closely, with safety-incidents.test.js's own
 * field names and conventions on top.
 *
 * The point of every test here is the one AGENTS.md §5 makes for the backend
 * seam: the device door's refusals are proven at the HTTP door with real
 * requests carrying real headers, and the record the door writes is read back
 * out of the database — never by asserting that a Screen hid a button and
 * never by calling the service function.
 *
 * Two doors are exercised side by side on purpose, in the same file: one test
 * sends the same invalid body through both, so "the same ladder-consistency
 * rule applies on the floor door as on the Account door" is a comparison of
 * two answers rather than a claim about a shared function — proof that
 * recordSafetyIncident is reused rather than duplicated.
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
  const subject = uniqueCode('fsiacct');
  const { rows: [account] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status)
     VALUES ($1, 'Floor Safety Incident Test Account', $2, $3, TRUE, 'approved') RETURNING id`,
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
     VALUES ($1, 'Floor Safety Incident Test Site', 'Asia/Ho_Chi_Minh') RETURNING id, code`,
    [uniqueCode('FSS')]
  );
  insertedSiteIds.push(site.id);
  return site;
}

async function insertOrgUnit(siteId, { parentId = null, unitType = 'area', name = 'FSI Unit' } = {}) {
  const { rows: [orgUnit] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, $2, $3, $4, $5) RETURNING id, code, name, path`,
    [siteId, parentId, uniqueCode('FSIOU'), name, unitType]
  );
  insertedOrgUnitIds.push(orgUnit.id);
  return orgUnit;
}

async function insertEmployee({ displayName = 'Floor Technician' } = {}) {
  const [firstName, ...rest] = displayName.split(' ');
  const { rows: [employee] } = await pool.query(
    `INSERT INTO employees (employee_no, first_name, last_name, is_active)
     VALUES ($1, $2, $3, TRUE) RETURNING id, employee_no, display_name`,
    [uniqueCode('FSEMP'), firstName, rest.join(' ') || 'Employee']
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
  return postJson('/api/safety/floor/incidents', floorHeaders(deviceCredential, identification), body);
}

// Records through the Account door, the slice issue #226 built.
async function recordFromAccount(token, siteId, body) {
  return postJson(`/api/safety/sites/${siteId}/incidents`, token, body);
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

  technician = await insertEmployee({ displayName: 'Tess Technician' });
  const registered = await registerDevice(deviceLine.id, 'Device Line terminal');
  device = { id: registered.device.id, credential: registered.credential };
  await setTechnicianPin(technician.id, '4321');
});

test.after(async () => {
  // Children before parents: a Safety incident references the Org Unit, the
  // Account (recorded_by_account_id) and the Employee (reported_by), so it
  // goes first.
  await pool.query(
    `DELETE FROM safety_incidents
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

test('a device with a valid credential and identification records at its own Org Unit, naming the Employee as reported-by', async () => {
  const identification = await identifyTechnician();

  const { status, body } = await recordFromFloor(device.credential, identification, {
    orgUnitId: String(deviceLine.id),
    occurredAt: '2026-04-10T08:00:00Z',
    incidentType: 'near_miss',
    severityLevel: 'near_miss',
    description: 'A pallet nearly tipped while being moved.'
  });

  assert.strictEqual(status, 201, JSON.stringify(body));
  assert.match(body.incident.incidentNo, /^SI-[A-Z0-9]+-\d{4}-\d{5}$/);
  assert.strictEqual(body.incident.orgUnitId, String(deviceLine.id));
  assert.strictEqual(body.incident.incidentType, 'near_miss');
  assert.strictEqual(body.incident.severityLevel, 'near_miss');

  // The identified Employee is the reporter, and there is no Account on this
  // path at all (ADR-0016: the device is not a person and most of a plant
  // cannot sign in).
  assert.strictEqual(String(body.incident.reportedBy), String(technician.id));
  assert.strictEqual(body.incident.recordedByAccountId, null);

  const { rows: [row] } = await pool.query(
    'SELECT reported_by, recorded_by_account_id, is_anonymous FROM safety_incidents WHERE id = $1',
    [body.incident.id]
  );
  assert.strictEqual(String(row.reported_by), String(technician.id));
  assert.strictEqual(row.recorded_by_account_id, null);
  assert.strictEqual(row.is_anonymous, false);
});

test('a device records a Safety incident beneath its own Org Unit too', async () => {
  const identification = await identifyTechnician();

  const { status, body } = await recordFromFloor(device.credential, identification, {
    orgUnitId: String(deviceCell.id),
    occurredAt: '2026-04-10T09:00:00Z',
    incidentType: 'property_damage',
    severityLevel: 'near_miss',
    description: 'A guard rail was scraped by a forklift.'
  });

  assert.strictEqual(status, 201, JSON.stringify(body));
  assert.strictEqual(body.incident.orgUnitId, String(deviceCell.id));
  assert.strictEqual(String(body.incident.reportedBy), String(technician.id));
});

test('a device may not record at an Org Unit outside its own subtree', async () => {
  const identification = await identifyTechnician();

  const { status, body } = await recordFromFloor(device.credential, identification, {
    orgUnitId: String(otherLine.id),
    occurredAt: '2026-04-10T08:00:00Z',
    incidentType: 'near_miss',
    severityLevel: 'near_miss',
    description: 'Attempting to record outside the device subtree.'
  });

  assert.strictEqual(status, 403);
  assert.strictEqual(body.message, "Outside the caller's granted Org Units");

  // Nothing was written: the refusal happened before the record was made.
  const { rows } = await pool.query(
    'SELECT id FROM safety_incidents WHERE org_unit_id = $1',
    [otherLine.id]
  );
  assert.strictEqual(rows.length, 0);
});

// ---------------------------------------------------------------------------
// The reporter is the identified Employee, and no Account ever records here.
// ---------------------------------------------------------------------------

test('the reporter is the identified Employee and there is no recording Account, asserted explicitly', async () => {
  const identification = await identifyTechnician();

  const { status, body } = await recordFromFloor(device.credential, identification, {
    orgUnitId: String(deviceLine.id),
    occurredAt: '2026-04-10T10:00:00Z',
    incidentType: 'injury',
    severityLevel: 'first_aid',
    description: 'A small splinter was removed at first aid.'
  });

  assert.strictEqual(status, 201, JSON.stringify(body));
  assert.strictEqual(String(body.incident.reportedBy), String(technician.id));
  assert.strictEqual(body.incident.reportedByName, technician.display_name);
  assert.strictEqual(body.incident.recordedByAccountId, null);
  assert.strictEqual(body.incident.recordedByAccountName, null);

  // Neither door may ever produce an incident with no author at all.
  assert.ok(
    body.incident.reportedBy !== null || body.incident.recordedByAccountId !== null,
    'the incident has no author'
  );
});

test('a Safety incident recorded by an Account is unchanged: recorded-by-account, no reported-by', async () => {
  const recorder = await insertAccount({
    role: 'operator',
    grants: [{ orgUnitId: deviceLine.id, write: true }]
  });

  const { status, body } = await recordFromAccount(recorder.token, site.id, {
    orgUnitId: String(deviceLine.id),
    occurredAt: '2026-04-10T11:00:00Z',
    incidentType: 'environmental',
    severityLevel: 'near_miss',
    description: 'A small spill was contained quickly.'
  });

  assert.strictEqual(status, 201, JSON.stringify(body));
  assert.strictEqual(String(body.incident.recordedByAccountId), String(recorder.id));
  assert.strictEqual(body.incident.reportedBy, null);

  // Neither door may ever produce an incident with no author at all.
  assert.ok(
    body.incident.reportedBy !== null || body.incident.recordedByAccountId !== null,
    'the incident has no author'
  );
});

// ---------------------------------------------------------------------------
// The door: a device alone never writes, and an identification is proven.
// ---------------------------------------------------------------------------

test('a request with no device credential, or an unknown one, is refused', async () => {
  const body = {
    orgUnitId: String(deviceLine.id),
    occurredAt: '2026-04-10T08:00:00Z',
    incidentType: 'near_miss',
    severityLevel: 'near_miss',
    description: 'No device credential at all.'
  };

  const noDevice = await postJson('/api/safety/floor/incidents', {}, body);
  assert.strictEqual(noDevice.status, 401);

  const unknownDevice = await postJson(
    '/api/safety/floor/incidents',
    { 'x-floor-device': 'not-a-real-credential' },
    body
  );
  assert.strictEqual(unknownDevice.status, 401);
  assert.strictEqual(unknownDevice.body.message, 'Invalid or inactive floor device');
});

test('a device credential on its own is refused every write', async () => {
  const { status, body } = await recordFromFloor(device.credential, null, {
    orgUnitId: String(deviceLine.id),
    occurredAt: '2026-04-10T08:00:00Z',
    incidentType: 'near_miss',
    severityLevel: 'near_miss',
    description: 'No identification presented.'
  });

  assert.strictEqual(status, 401);
  assert.strictEqual(body.message, 'An individual identification is required to write here');
});

test('a make-believe identification is refused', async () => {
  const { status, body } = await recordFromFloor(device.credential, 'made-up-token', {
    orgUnitId: String(deviceLine.id),
    occurredAt: '2026-04-10T08:00:00Z',
    incidentType: 'near_miss',
    severityLevel: 'near_miss',
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
    occurredAt: '2026-04-10T08:00:00Z',
    incidentType: 'near_miss',
    severityLevel: 'near_miss',
    description: 'An expired identification.'
  });

  assert.strictEqual(status, 401);
});

test('an identification issued on one device is refused on another', async () => {
  const second = await registerDevice(deviceCell.id, 'Cell terminal');
  const identification = await identifyTechnician();

  const { status } = await recordFromFloor(second.credential, identification, {
    orgUnitId: String(deviceCell.id),
    occurredAt: '2026-04-10T08:00:00Z',
    incidentType: 'near_miss',
    severityLevel: 'near_miss',
    description: 'An identification minted on a different device.'
  });

  assert.strictEqual(status, 401);
});

// ---------------------------------------------------------------------------
// The same rules on both doors — recordSafetyIncident is reused, not
// duplicated.
// ---------------------------------------------------------------------------

test('the ladder-consistency rule is the same on the floor door as on the Account door', async () => {
  const ruleWriter = await insertAccount({
    role: 'supervisor',
    grants: [{ orgUnitId: deviceLine.id, write: true }]
  });
  const identification = await identifyTechnician();

  const cases = [
    {
      what: 'lostTimeDays on the near_miss rung: nobody was hurt',
      body: {
        orgUnitId: String(deviceLine.id),
        occurredAt: '2026-04-10T08:00:00Z',
        incidentType: 'near_miss',
        severityLevel: 'near_miss',
        description: 'Claiming lost time on a near miss.',
        lostTimeDays: 1
      },
      pattern: /lostTimeDays/
    },
    {
      what: 'lostTimeDays below the lost_time rung',
      body: {
        orgUnitId: String(deviceLine.id),
        occurredAt: '2026-04-10T08:00:00Z',
        incidentType: 'injury',
        severityLevel: 'first_aid',
        description: 'Claiming lost time at first aid.',
        lostTimeDays: 1
      },
      pattern: /lostTimeDays/
    },
    {
      what: 'a severityLevel that is not one of the set',
      body: {
        orgUnitId: String(deviceLine.id),
        occurredAt: '2026-04-10T08:00:00Z',
        incidentType: 'injury',
        severityLevel: 'catastrophic',
        description: 'Not a real rung on the ladder.'
      },
      pattern: /severityLevel/
    }
  ];

  for (const one of cases) {
    const floor = await recordFromFloor(device.credential, identification, one.body);
    const account = await recordFromAccount(ruleWriter.token, site.id, one.body);

    assert.strictEqual(
      floor.status,
      account.status,
      `${one.what}: floor answered ${floor.status}, the Account door ${account.status}`
    );
    assert.strictEqual(
      floor.body.message,
      account.body.message,
      `${one.what}: the two doors gave different sentences`
    );
    assert.strictEqual(floor.status, 400, `${one.what} was accepted`);
    assert.match(floor.body.message, one.pattern);
  }
});

// ---------------------------------------------------------------------------
// No anonymous option was ever offered or accepted.
// ---------------------------------------------------------------------------

test('isAnonymous sent from the floor is ignored: the row is never anonymous', async () => {
  const identification = await identifyTechnician();

  const { status, body } = await recordFromFloor(device.credential, identification, {
    orgUnitId: String(deviceLine.id),
    occurredAt: '2026-04-10T08:00:00Z',
    incidentType: 'near_miss',
    severityLevel: 'near_miss',
    description: 'Attempting to report anonymously from the floor.',
    isAnonymous: true
  });

  assert.strictEqual(status, 201, JSON.stringify(body));
  assert.strictEqual(String(body.incident.reportedBy), String(technician.id));

  const { rows: [row] } = await pool.query(
    'SELECT is_anonymous FROM safety_incidents WHERE id = $1',
    [body.incident.id]
  );
  assert.strictEqual(row.is_anonymous, false);
});
