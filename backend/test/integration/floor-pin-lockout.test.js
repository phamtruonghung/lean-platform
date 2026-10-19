/*
 * The floor PIN lockout over HTTP (ADR-0047, ADR-0016), against a real
 * database and a real (locally issued) JWKS: wrong PINs are counted per
 * (device, Employee number) and per device, a locked pair is refused with 423
 * even for the right PIN, a right PIN clears the Employee's count, and an
 * administrator setting a PIN lifts a lock.
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

const insertedAccountIds = [];
const insertedSiteIds = [];
const insertedOrgUnitIds = [];
const insertedEmployeeIds = [];
const insertedDeviceIds = [];

let counter = 0;
function uniqueCode(prefix) {
  counter += 1;
  return `${prefix}${process.pid}${counter}`;
}

async function send(method, path, headers, body) {
  const response = await fetch(`${base}${path}`, {
    method,
    headers: { ...headers, 'content-type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body)
  });
  return { response, payload: await response.json().catch(() => null) };
}

async function newDevice() {
  const { payload } = await send('POST', '/api/maintenance/floor-devices', admin, {
    orgUnitId: orgUnitId,
    name: 'Lockout terminal'
  });
  insertedDeviceIds.push(payload.device.id);
  return { id: payload.device.id, credential: payload.credential };
}

async function newEmployee(pin) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO employees (employee_no, first_name, last_name)
     VALUES ($1, 'Lock', 'Out') RETURNING id, employee_no`,
    [uniqueCode('LOCK')]
  );
  insertedEmployeeIds.push(row.id);
  await setPin(row.id, pin);
  return row;
}

async function setPin(employeeId, pin) {
  const { response } = await send(
    'PUT',
    `/api/maintenance/floor-technician-credentials/${employeeId}`,
    admin,
    { pin }
  );
  assert.strictEqual(response.status, 200);
}

function identify(device, employeeNo, pin) {
  return send('POST', '/api/maintenance/floor/identify', { 'x-floor-device': device.credential }, {
    employeeNo,
    pin
  });
}

async function failTimes(device, employee, times) {
  for (let i = 0; i < times; i += 1) {
    const { response } = await identify(device, employee.employee_no, '0000');
    assert.strictEqual(response.status, 401);
  }
}

let orgUnitId;

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

  const subject = uniqueCode('lockacct');
  const { rows: [account] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status)
     VALUES ($1, 'Lockout Admin', 'admin', $2, TRUE, 'approved') RETURNING id`,
    [`${subject}@example.com`, subject]
  );
  insertedAccountIds.push(account.id);
  const token = await jwks.signToken(
    { sub: subject, email: `${subject}@example.com` },
    { issuer: ISSUER, audience: AUDIENCE }
  );
  admin = { authorization: `Bearer ${token}` };

  const { rows: [site] } = await pool.query(
    `INSERT INTO sites (code, name, timezone)
     VALUES ($1, 'Lockout Site', 'Asia/Ho_Chi_Minh') RETURNING id`,
    [uniqueCode('ST')]
  );
  insertedSiteIds.push(site.id);
  const { rows: [orgUnit] } = await pool.query(
    `INSERT INTO org_units (site_id, code, name, unit_type)
     VALUES ($1, $2, 'Lockout Unit', 'area') RETURNING id`,
    [site.id, uniqueCode('OU')]
  );
  insertedOrgUnitIds.push(orgUnit.id);
  orgUnitId = orgUnit.id;
});

test.after(async () => {
  await pool.query('DELETE FROM floor_pin_attempts WHERE floor_device_id = ANY($1)', [insertedDeviceIds]);
  await pool.query('DELETE FROM technician_identifications WHERE floor_device_id = ANY($1)', [insertedDeviceIds]);
  await pool.query('DELETE FROM employee_floor_credentials WHERE employee_id = ANY($1)', [insertedEmployeeIds]);
  await pool.query('DELETE FROM floor_devices WHERE id = ANY($1)', [insertedDeviceIds]);
  await pool.query('DELETE FROM employees WHERE id = ANY($1)', [insertedEmployeeIds]);
  await pool.query('DELETE FROM app_users WHERE id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM org_units WHERE id = ANY($1)', [insertedOrgUnitIds]);
  await pool.query('DELETE FROM sites WHERE id = ANY($1)', [insertedSiteIds]);
  await new Promise((resolve) => server.close(resolve));
  await closePool();
  await jwks.close();
});

test('a wrong PIN stays a 401 until the fifth, then the pair is locked with a 423 even for the right PIN', async () => {
  const device = await newDevice();
  const employee = await newEmployee('4321');

  await failTimes(device, employee, 5);

  const right = await identify(device, employee.employee_no, '4321');
  assert.strictEqual(right.response.status, 423);
  assert.strictEqual(right.payload.code, 'pin_locked');
  assert.ok(right.payload.retryAfterSeconds > 0 && right.payload.retryAfterSeconds <= 900);
  assert.strictEqual(
    right.response.headers.get('retry-after'),
    String(right.payload.retryAfterSeconds)
  );
  assert.match(right.payload.message, /administrator/);
});

test('the lock is per Employee: another Employee on the same device is unaffected', async () => {
  const device = await newDevice();
  const locked = await newEmployee('4321');
  const other = await newEmployee('8765');

  await failTimes(device, locked, 5);

  const { response } = await identify(device, other.employee_no, '8765');
  assert.strictEqual(response.status, 200);
});

test('a correct PIN resets the Employee counter', async () => {
  const device = await newDevice();
  const employee = await newEmployee('4321');

  await failTimes(device, employee, 4);
  assert.strictEqual((await identify(device, employee.employee_no, '4321')).response.status, 200);
  await failTimes(device, employee, 4);

  // Four since the reset is not five: still a 401, not a lock.
  assert.strictEqual((await identify(device, employee.employee_no, '4321')).response.status, 200);
});

test('a guess at a number nobody holds locks the same way, so the lock does not reveal who exists', async () => {
  const device = await newDevice();
  const ghost = { employee_no: uniqueCode('NOBODY') };

  await failTimes(device, ghost, 5);

  const { response, payload } = await identify(device, ghost.employee_no, '0000');
  assert.strictEqual(response.status, 423);
  assert.strictEqual(payload.code, 'pin_locked');
});

test('the lock lifts after its window and the run starts over', async () => {
  const device = await newDevice();
  const employee = await newEmployee('4321');

  await failTimes(device, employee, 5);
  await pool.query(
    `UPDATE floor_pin_attempts SET locked_until = now() - interval '1 second'
      WHERE floor_device_id = $1 AND employee_no = $2`,
    [device.id, employee.employee_no]
  );

  // One more wrong PIN is the first of a new run, not an instant re-lock.
  assert.strictEqual((await identify(device, employee.employee_no, '0000')).response.status, 401);
  assert.strictEqual((await identify(device, employee.employee_no, '4321')).response.status, 200);
});

test('an administrator setting the PIN lifts the lock on every device', async () => {
  const device = await newDevice();
  const employee = await newEmployee('4321');

  await failTimes(device, employee, 5);
  assert.strictEqual((await identify(device, employee.employee_no, '4321')).response.status, 423);

  await setPin(employee.id, '1357');

  assert.strictEqual((await identify(device, employee.employee_no, '1357')).response.status, 200);
});

test('thirty wrong PINs across Employees lock the whole device, and a right PIN does not reset that', async () => {
  const device = await newDevice();
  const employee = await newEmployee('4321');

  // Spread over distinct numbers so no single pair reaches its own limit.
  for (let i = 0; i < 30; i += 1) {
    if (i === 10 || i === 20) {
      assert.strictEqual((await identify(device, employee.employee_no, '4321')).response.status, 200);
    }
    const { response } = await identify(device, `${uniqueCode('SPRAY')}`, '0000');
    assert.strictEqual(response.status, 401);
  }

  const { response, payload } = await identify(device, employee.employee_no, '4321');
  assert.strictEqual(response.status, 423);
  assert.strictEqual(payload.code, 'pin_locked');

  // Another device is untouched.
  const other = await newDevice();
  assert.strictEqual((await identify(other, employee.employee_no, '4321')).response.status, 200);
});

test('an existing four-digit PIN keeps working', async () => {
  const device = await newDevice();
  const employee = await newEmployee('1234');
  assert.strictEqual((await identify(device, employee.employee_no, '1234')).response.status, 200);
});
