/*
 * Recording a Non-conformance at a shared floor device over HTTP (issue #207,
 * ADR-0016), against a real database and a real (locally issued) JWKS — the
 * same seam floor-technician-surface.test.js uses, whose fixture scaffolding
 * this file mirrors, with nonconformances.test.js's Product/Defect-code
 * creation on top.
 *
 * The point of every test here is the one AGENTS.md §5 makes for the backend
 * seam: the device door's refusals are proven at the HTTP door with real
 * requests carrying real headers, and the record the door writes is read back
 * out of the database — never by asserting that a Screen hid a button and
 * never by calling the service function.
 *
 * Two doors are exercised side by side on purpose, in the same file: several
 * tests send one identical body through both, so "the same field, severity and
 * quantity rules apply as recording with an Account" is a comparison of two
 * answers rather than a claim about a shared function.
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
const insertedProductCodes = [];
const insertedDefectCodeCodes = [];

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
  const subject = uniqueCode('fncacct');
  const { rows: [account] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status)
     VALUES ($1, 'Floor Non-conformance Test Account', $2, $3, TRUE, 'approved') RETURNING id`,
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
     VALUES ($1, 'Floor Non-conformance Test Site', 'Asia/Ho_Chi_Minh') RETURNING id, code`,
    [uniqueCode('FNS')]
  );
  insertedSiteIds.push(site.id);
  return site;
}

async function insertOrgUnit(siteId, { parentId = null, unitType = 'area', name = 'FN Unit' } = {}) {
  const { rows: [orgUnit] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, $2, $3, $4, $5) RETURNING id, code, name, path`,
    [siteId, parentId, uniqueCode('FNOU'), name, unitType]
  );
  insertedOrgUnitIds.push(orgUnit.id);
  return orgUnit;
}

async function insertEmployee({ displayName = 'Floor Operator' } = {}) {
  const [firstName, ...rest] = displayName.split(' ');
  const { rows: [employee] } = await pool.query(
    `INSERT INTO employees (employee_no, first_name, last_name, is_active)
     VALUES ($1, $2, $3, TRUE) RETURNING id, employee_no, display_name`,
    [uniqueCode('FEMP'), firstName, rest.join(' ') || 'Employee']
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

async function getJson(path, headers) {
  const response = await fetch(`${base}${path}`, { headers });
  return json(response);
}

async function createProduct({ uomCode = 'EA' } = {}) {
  const code = uniqueCode('FNP-');
  const { status, body } = await postJson('/api/quality/products', admin.token, {
    code,
    name: `Product ${code}`,
    uomCode
  });
  assert.strictEqual(status, 201, `creating ${code} failed: ${JSON.stringify(body)}`);
  insertedProductCodes.push(code);
  return body.product;
}

async function createDefectCode({ defaultSeverity = 'minor' } = {}) {
  const code = uniqueCode('FND-');
  const { status, body } = await postJson('/api/quality/defect-codes', admin.token, {
    code,
    name: `Defect ${code}`,
    category: 'product',
    defaultSeverity
  });
  assert.strictEqual(status, 201, `creating ${code} failed: ${JSON.stringify(body)}`);
  insertedDefectCodeCodes.push(code);
  return body.defectCode;
}

// A retired Product: a Non-conformance cannot be recorded against one (409
// through either door), and the floor read does not offer it as a choice.
async function deactivateProduct(productId) {
  const response = await fetch(`${base}/api/quality/products/${productId}`, {
    method: 'PATCH',
    headers: { ...admin.token, 'content-type': 'application/json' },
    body: JSON.stringify({ isActive: false })
  });
  assert.strictEqual(response.status, 200);
}

// Registers a device against an Org Unit through the real endpoint, which is
// People's own route mounted under the frozen `/api/maintenance` prefix
// (issue #201), and returns the one-time credential.
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

// Records through the floor door — the address this ticket creates. `headers`
// is passed whole so a test can vary one header at a time.
async function recordFromFloor(deviceCredential, identification, body) {
  return postJson(
    '/api/quality/floor/nonconformances',
    floorHeaders(deviceCredential, identification),
    body
  );
}

// Records through the Account door, the slice issue #205 built.
async function recordFromAccount(token, siteId, body) {
  return postJson(`/api/quality/sites/${siteId}/nonconformances`, token, body);
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
  // Children before parents: a Non-conformance references the Org Unit, the
  // Product, the Defect code, the Account and the Employee (detected_by), so
  // it goes first; its quantity history cascades with it.
  await pool.query(
    `DELETE FROM quality_issues
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
  await pool.query('DELETE FROM products WHERE code = ANY($1)', [insertedProductCodes]);
  await pool.query('DELETE FROM defect_codes WHERE code = ANY($1)', [insertedDefectCodeCodes]);
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

test("a device with a valid credential and identification records at its own Org Unit, naming the Employee as detected-by", async () => {
  const product = await createProduct();
  const defectCode = await createDefectCode({ defaultSeverity: 'major' });
  const identification = await identifyTechnician();

  const { status, body } = await recordFromFloor(device.credential, identification, {
    orgUnitId: String(deviceLine.id),
    productId: product.id,
    defectCodeId: defectCode.id,
    detectionPoint: 'in_process',
    quantity: 12
  });

  assert.strictEqual(status, 201, JSON.stringify(body));
  assert.match(body.nonconformance.issueNo, /^NC-[A-Z0-9]+-\d{4}-\d{5}$/);
  assert.strictEqual(body.nonconformance.orgUnitId, String(deviceLine.id));
  assert.strictEqual(body.nonconformance.severity, 'major');
  assert.strictEqual(body.nonconformance.quantityAffected, 12);

  // The identified Employee is the detected-by, and there is no Account on
  // this path at all (ADR-0016: the device is not a person and most of a
  // plant cannot sign in).
  assert.strictEqual(String(body.nonconformance.detectedBy), String(technician.id));
  assert.strictEqual(body.nonconformance.recordedByAccountId, null);

  const { rows: [row] } = await pool.query(
    'SELECT detected_by, recorded_by_account_id FROM quality_issues WHERE id = $1',
    [body.nonconformance.id]
  );
  assert.strictEqual(String(row.detected_by), String(technician.id));
  assert.strictEqual(row.recorded_by_account_id, null);
});

test("a device records a Non-conformance beneath its own Org Unit too", async () => {
  const product = await createProduct();
  const defectCode = await createDefectCode();
  const identification = await identifyTechnician();

  const { status, body } = await recordFromFloor(device.credential, identification, {
    orgUnitId: String(deviceCell.id),
    productId: product.id,
    defectCodeId: defectCode.id,
    detectionPoint: 'final_inspection',
    quantity: '3'
  });

  assert.strictEqual(status, 201, JSON.stringify(body));
  assert.strictEqual(body.nonconformance.orgUnitId, String(deviceCell.id));
  assert.strictEqual(String(body.nonconformance.detectedBy), String(technician.id));
});

test("a device may not record at an Org Unit outside its own subtree", async () => {
  const product = await createProduct();
  const defectCode = await createDefectCode();
  const identification = await identifyTechnician();

  const { status, body } = await recordFromFloor(device.credential, identification, {
    orgUnitId: String(otherLine.id),
    productId: product.id,
    defectCodeId: defectCode.id,
    detectionPoint: 'in_process',
    quantity: 1
  });

  assert.strictEqual(status, 403);
  assert.strictEqual(body.message, "Outside the caller's granted Org Units");

  // Nothing was written: the refusal happened before the record was made.
  const { rows } = await pool.query(
    'SELECT id FROM quality_issues WHERE org_unit_id = $1',
    [otherLine.id]
  );
  assert.strictEqual(rows.length, 0);
});

// ---------------------------------------------------------------------------
// The door: a device alone never writes, and an identification is proven.
// ---------------------------------------------------------------------------

test('a request with no device credential, or an unknown one, is refused', async () => {
  const product = await createProduct();
  const defectCode = await createDefectCode();

  const body = {
    orgUnitId: String(deviceLine.id),
    productId: product.id,
    defectCodeId: defectCode.id,
    detectionPoint: 'in_process',
    quantity: 1
  };

  const noDevice = await postJson('/api/quality/floor/nonconformances', {}, body);
  assert.strictEqual(noDevice.status, 401);

  const unknownDevice = await postJson(
    '/api/quality/floor/nonconformances',
    { 'x-floor-device': 'not-a-real-credential' },
    body
  );
  assert.strictEqual(unknownDevice.status, 401);
  assert.strictEqual(unknownDevice.body.message, 'Invalid or inactive floor device');
});

test('a device credential on its own is refused every write', async () => {
  const product = await createProduct();
  const defectCode = await createDefectCode();

  const { status, body } = await recordFromFloor(device.credential, null, {
    orgUnitId: String(deviceLine.id),
    productId: product.id,
    defectCodeId: defectCode.id,
    detectionPoint: 'in_process',
    quantity: 1
  });

  assert.strictEqual(status, 401);
  assert.strictEqual(body.message, 'An individual identification is required to write here');
});

test('a make-believe identification is refused', async () => {
  const product = await createProduct();
  const defectCode = await createDefectCode();

  const { status, body } = await recordFromFloor(device.credential, 'made-up-token', {
    orgUnitId: String(deviceLine.id),
    productId: product.id,
    defectCodeId: defectCode.id,
    detectionPoint: 'in_process',
    quantity: 1
  });

  assert.strictEqual(status, 401);
  assert.strictEqual(body.message, 'This identification is invalid or has expired');
});

test('an expired identification is refused', async () => {
  const product = await createProduct();
  const defectCode = await createDefectCode();
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
    productId: product.id,
    defectCodeId: defectCode.id,
    detectionPoint: 'in_process',
    quantity: 1
  });

  assert.strictEqual(status, 401);
});

test('an identification issued on one device is refused on another', async () => {
  const second = await registerDevice(deviceCell.id, 'Cell terminal');
  const product = await createProduct();
  const defectCode = await createDefectCode();
  const identification = await identifyTechnician();

  const { status } = await recordFromFloor(second.credential, identification, {
    orgUnitId: String(deviceCell.id),
    productId: product.id,
    defectCodeId: defectCode.id,
    detectionPoint: 'in_process',
    quantity: 1
  });

  assert.strictEqual(status, 401);
});

// ---------------------------------------------------------------------------
// The same rules on both doors.
// ---------------------------------------------------------------------------

test('the field, severity and quantity rules are the same on the floor door as on the Account door', async () => {
  const ruleWriter = await insertAccount({
    role: 'supervisor',
    grants: [{ orgUnitId: deviceLine.id, write: true }]
  });
  const product = await createProduct();
  const strictCode = await createDefectCode({ defaultSeverity: 'major' });
  const retired = await createProduct();
  await deactivateProduct(retired.id);
  const identification = await identifyTechnician();

  const cases = [
    {
      what: 'a detection point that is not one of the set',
      body: {
        orgUnitId: String(deviceLine.id),
        productId: product.id,
        defectCodeId: strictCode.id,
        detectionPoint: 'opne',
        quantity: 4
      }
    },
    {
      what: 'a quantity that is not positive',
      body: {
        orgUnitId: String(deviceLine.id),
        productId: product.id,
        defectCodeId: strictCode.id,
        detectionPoint: 'in_process',
        quantity: 0
      }
    },
    {
      what: "a severity below the Defect code's own default",
      body: {
        orgUnitId: String(deviceLine.id),
        productId: product.id,
        defectCodeId: strictCode.id,
        detectionPoint: 'in_process',
        quantity: 4,
        severity: 'minor'
      }
    },
    {
      what: 'a Product that does not exist',
      body: {
        orgUnitId: String(deviceLine.id),
        productId: '999999999',
        defectCodeId: strictCode.id,
        detectionPoint: 'in_process',
        quantity: 4
      }
    },
    {
      what: 'a Product the plant has retired',
      body: {
        orgUnitId: String(deviceLine.id),
        productId: retired.id,
        defectCodeId: strictCode.id,
        detectionPoint: 'in_process',
        quantity: 4
      }
    },
    {
      what: 'an Org Unit that does not exist',
      body: {
        orgUnitId: '999999999',
        productId: product.id,
        defectCodeId: strictCode.id,
        detectionPoint: 'in_process',
        quantity: 4
      }
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
    assert.ok(floor.status >= 400, `${one.what} was accepted`);
  }
});

test('a Non-conformance recorded by an Account is unchanged: recorded-by-account, no detected-by', async () => {
  const recorder = await insertAccount({
    role: 'operator',
    grants: [{ orgUnitId: deviceLine.id, write: true }]
  });
  const product = await createProduct();
  const defectCode = await createDefectCode();

  const { status, body } = await recordFromAccount(recorder.token, site.id, {
    orgUnitId: String(deviceLine.id),
    productId: product.id,
    defectCodeId: defectCode.id,
    detectionPoint: 'in_process',
    quantity: 2
  });

  assert.strictEqual(status, 201, JSON.stringify(body));
  assert.strictEqual(String(body.nonconformance.recordedByAccountId), String(recorder.id));
  assert.strictEqual(body.nonconformance.detectedBy, null);
});

// ---------------------------------------------------------------------------
// Nothing requiring Quality authority is reachable from the device.
// ---------------------------------------------------------------------------

test('nothing that needs Quality authority can be done from the floor device', async () => {
  const product = await createProduct();
  const defectCode = await createDefectCode();
  const identification = await identifyTechnician();

  const recorded = await recordFromFloor(device.credential, identification, {
    orgUnitId: String(deviceLine.id),
    productId: product.id,
    defectCodeId: defectCode.id,
    detectionPoint: 'in_process',
    quantity: 5
  });
  assert.strictEqual(recorded.status, 201, JSON.stringify(recorded.body));
  const id = recorded.body.nonconformance.id;

  // Every one of the four acts a holder of Quality authority may take is
  // presented with this device's own credential and a valid identification,
  // and none of them is reachable: they are mounted behind an Account session,
  // not behind the floor door, so the device is refused before anything about
  // the record is looked at.
  const acts = [
    ['concession', { quantity: 5, reference: 'DEV-1', note: 'accept it' }],
    ['lower-severity', { severity: 'minor', note: 'less bad than we thought' }],
    ['reopen', { note: 'closed too early' }],
    ['cancel', { note: 'recorded in error' }]
  ];

  for (const [path, body] of acts) {
    const { status } = await postJson(
      `/api/quality/nonconformances/${id}/${path}`,
      floorHeaders(device.credential, identification),
      body
    );
    assert.strictEqual(status, 401, `${path} was reachable from the floor device`);

    // And there is no floor address for any of them either.
    const floorPath = await postJson(
      `/api/quality/floor/nonconformances/${id}/${path}`,
      floorHeaders(device.credential, identification),
      body
    );
    assert.strictEqual(floorPath.status, 404, `${path} exists under the floor door`);
  }

  const { rows: [row] } = await pool.query(
    'SELECT status, severity FROM quality_issues WHERE id = $1',
    [id]
  );
  assert.strictEqual(row.status, 'open');
  assert.strictEqual(row.severity, defectCode.defaultSeverity);
});

// ---------------------------------------------------------------------------
// The device's two reads: what it must choose from.
// ---------------------------------------------------------------------------

test('the floor device reads the Product and Defect code catalogues it chooses from', async () => {
  const product = await createProduct();
  const defectCode = await createDefectCode({ defaultSeverity: 'critical' });

  const products = await getJson('/api/quality/floor/products', floorHeaders(device.credential));
  assert.strictEqual(products.status, 200);
  const productRow = products.body.products.find((row) => row.id === product.id);
  assert.ok(productRow, 'the Product a device would record against is offered');
  assert.strictEqual(productRow.code, product.code);

  const codes = await getJson(
    '/api/quality/floor/defect-codes',
    floorHeaders(device.credential)
  );
  assert.strictEqual(codes.status, 200);
  const codeRow = codes.body.defectCodes.find((row) => row.id === defectCode.id);
  assert.ok(codeRow, 'the Defect code a device would record against is offered');
  assert.strictEqual(codeRow.defaultSeverity, 'critical');
});

test('the floor reads need a device credential, and a retired Product is not offered', async () => {
  assert.strictEqual((await getJson('/api/quality/floor/products', {})).status, 401);
  assert.strictEqual(
    (await getJson('/api/quality/floor/defect-codes', { 'x-floor-device': 'nope' })).status,
    401
  );

  const retired = await createProduct();
  await deactivateProduct(retired.id);

  const { body } = await getJson('/api/quality/floor/products', floorHeaders(device.credential));
  assert.ok(!body.products.some((row) => row.id === retired.id), 'a retired Product is not a choice');
});
