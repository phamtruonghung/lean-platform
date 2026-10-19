/*
 * A Trainee with no Account answering at the shared floor device over HTTP
 * (issue #293, ADR-0016, ADR-0043), against a real database and a real
 * (locally issued) JWKS - the same seam and fixture scaffolding as
 * floor-safety-observation.test.js and training.test.js. Every refusal is
 * proven at the HTTP door with real headers, and the columns the door writes
 * are read back out of the database.
 *
 * Needs a database with every migration applied. Set DATABASE_URL first.
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
const insertedRecordIds = [];

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

async function insertAccount({ role = 'operator', employeeId = null } = {}) {
  const subject = uniqueCode('ftracct');
  const { rows: [account] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status, employee_id)
     VALUES ($1, 'Floor Training Test Account', $2, $3, TRUE, 'approved', $4) RETURNING id`,
    [`${subject}@example.com`, role, subject, employeeId]
  );
  insertedAccountIds.push(account.id);
  return { id: account.id, token: await authHeader(subject) };
}

async function insertSite() {
  const { rows: [site] } = await pool.query(
    `INSERT INTO sites (code, name, timezone)
     VALUES ($1, 'Floor Training Test Site', 'Asia/Ho_Chi_Minh') RETURNING id, code`,
    [uniqueCode('FTR')]
  );
  insertedSiteIds.push(site.id);
  return site;
}

async function insertOrgUnit(siteId, { parentId = null, unitType = 'area', name = 'FTR Unit' } = {}) {
  const { rows: [orgUnit] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, $2, $3, $4, $5) RETURNING id, name`,
    [siteId, parentId, uniqueCode('FTROU'), name, unitType]
  );
  insertedOrgUnitIds.push(orgUnit.id);
  return orgUnit;
}

async function insertEmployee(displayName = 'Tara Trainee') {
  const [firstName, ...rest] = displayName.split(' ');
  const { rows: [employee] } = await pool.query(
    `INSERT INTO employees (employee_no, first_name, last_name, is_active)
     VALUES ($1, $2, $3, TRUE) RETURNING id, employee_no, display_name`,
    [uniqueCode('FTREMP'), firstName, rest.join(' ') || 'Employee']
  );
  insertedEmployeeIds.push(employee.id);
  return employee;
}

async function request(method, path, headers, body) {
  const response = await fetch(`${base}${path}`, {
    method,
    headers: { ...headers, ...(body === undefined ? {} : { 'content-type': 'application/json' }) },
    body: body === undefined ? undefined : JSON.stringify(body)
  });
  return { status: response.status, body: await response.json().catch(() => null) };
}

async function registerDevice(orgUnitId, name) {
  const { status, body } = await request('POST', '/api/maintenance/floor-devices', admin.token, {
    orgUnitId,
    name
  });
  assert.strictEqual(status, 201, JSON.stringify(body));
  insertedDeviceIds.push(body.device.id);
  return { id: body.device.id, credential: body.credential };
}

async function setPin(employeeId, pin) {
  const { status, body } = await request(
    'PUT',
    `/api/maintenance/floor-technician-credentials/${employeeId}`,
    admin.token,
    { pin }
  );
  assert.strictEqual(status, 200, JSON.stringify(body));
}

async function identify(device, employee, pin = '4321') {
  const { status, body } = await request(
    'POST',
    '/api/maintenance/floor/identify',
    { 'x-floor-device': device.credential },
    { employeeNo: employee.employee_no, pin }
  );
  assert.strictEqual(status, 200, JSON.stringify(body));
  return body.identification;
}

function floorHeaders(device, identification) {
  return {
    ...(device ? { 'x-floor-device': device.credential } : {}),
    ...(identification ? { 'x-technician-identification': identification } : {})
  };
}

const listAtFloor = (headers) => request('GET', '/api/maintenance/floor/training/to-confirm', headers);
const answerAtFloor = (headers, traineeId, answer) =>
  request(
    'POST',
    `/api/maintenance/floor/training/trainees/${traineeId}/answer`,
    headers,
    answer === undefined ? {} : { answer }
  );
const answerAtAccount = (account, traineeId, answer) =>
  request('POST', `/api/people/training/trainees/${traineeId}/answer`, account.token, { answer });

// A record straight into the table (this file is about the door, not sending),
// with one Trainee row; returns the ids.
async function insertTrainee({ orgUnit, employee, status = 'sent', title = 'Floor training' }) {
  const { rows: [record] } = await pool.query(
    `INSERT INTO training_records (site_id, org_unit_id, number, title, trained_on, duration_hours,
                                   trainer_employee_id, objective, status, sent_at, sent_by_account_id)
     VALUES ($1, $2, $3, $4, '2026-03-10', 1.5, $5, 'Know the lockout steps', $6,
             CASE WHEN $6 = 'sent' THEN now() END,
             CASE WHEN $6 = 'sent' THEN $7::bigint END)
     RETURNING id`,
    [site.id, orgUnit.id, uniqueCode('TR-FTR-'), title, trainer.id, status, admin.id]
  );
  insertedRecordIds.push(record.id);
  const { rows: [trainee] } = await pool.query(
    `INSERT INTO training_trainees (training_record_id, employee_id) VALUES ($1, $2) RETURNING id`,
    [record.id, employee.id]
  );
  return { recordId: record.id, traineeId: trainee.id };
}

const traineeRow = async (id) =>
  (await pool.query(
    `SELECT answer, answered_at, answered_by_account_id, answered_by_employee_id
       FROM training_trainees WHERE id = $1`,
    [id]
  )).rows[0];

let admin;
let site;
let area;
let deviceLine;
let deviceCell;
let otherLine;
let trainer;
let device;
let otherDevice; // at the other line
let tara; // the Trainee at the floor
let tara2; // a colleague with no relation to the identification

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
  deviceLine = await insertOrgUnit(site.id, { parentId: area.id, unitType: 'line', name: 'Device Line' });
  deviceCell = await insertOrgUnit(site.id, { parentId: deviceLine.id, unitType: 'cell', name: 'Device Cell' });
  otherLine = await insertOrgUnit(site.id, { parentId: area.id, unitType: 'line', name: 'Other Line' });

  trainer = await insertEmployee('Tina Trainer');
  tara = await insertEmployee('Tara Trainee');
  tara2 = await insertEmployee('Tom Colleague');
  device = await registerDevice(deviceLine.id, 'Device Line terminal');
  otherDevice = await registerDevice(otherLine.id, 'Other Line terminal');
  await setPin(tara.id, '4321');
  await setPin(tara2.id, '4321');
});

test.after(async () => {
  // Children before parents.
  await pool.query('DELETE FROM training_trainees WHERE training_record_id = ANY($1)', [insertedRecordIds]);
  await pool.query('DELETE FROM training_records WHERE id = ANY($1)', [insertedRecordIds]);
  await pool.query('DELETE FROM technician_identifications WHERE floor_device_id = ANY($1)', [insertedDeviceIds]);
  await pool.query('DELETE FROM employee_floor_credentials WHERE employee_id = ANY($1)', [insertedEmployeeIds]);
  await pool.query('DELETE FROM floor_devices WHERE id = ANY($1)', [insertedDeviceIds]);
  await pool.query('DELETE FROM app_user_org_units WHERE app_user_id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM app_users WHERE id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM employees WHERE id = ANY($1)', [insertedEmployeeIds]);
  await pool.query('DELETE FROM org_units WHERE id = ANY($1)', [[...insertedOrgUnitIds].reverse()]);
  await pool.query('DELETE FROM sites WHERE id = ANY($1)', [insertedSiteIds]);
  await new Promise((resolve) => server.close(resolve));
  await closePool();
  await jwks.close();
});

test('the listing holds only the identified Employee\'s own unanswered rows on sent records the device reaches', async () => {
  const lister = await insertEmployee('Lena Lister');
  await setPin(lister.id, '4321');
  const atLine = await insertTrainee({ orgUnit: deviceLine, employee: lister, title: 'At the line' });
  const atCell = await insertTrainee({ orgUnit: deviceCell, employee: lister, title: 'At the cell' });
  const elsewhere = await insertTrainee({ orgUnit: otherLine, employee: lister, title: 'Elsewhere' });
  const draft = await insertTrainee({ orgUnit: deviceLine, employee: lister, status: 'draft', title: 'Draft' });
  const answered = await insertTrainee({ orgUnit: deviceLine, employee: lister, title: 'Answered' });
  const someoneElses = await insertTrainee({ orgUnit: deviceLine, employee: tara2, title: 'Someone else' });
  await pool.query(
    `UPDATE training_trainees SET answer = 'confirmed', answered_at = now(), answered_by_employee_id = $2 WHERE id = $1`,
    [answered.traineeId, lister.id]
  );

  const identification = await identify(device, lister);
  const { status, body } = await listAtFloor(floorHeaders(device, identification));
  assert.strictEqual(status, 200, JSON.stringify(body));
  const ids = body.trainingToConfirm.map((row) => row.traineeId);
  assert.ok(ids.includes(atLine.traineeId));
  assert.ok(ids.includes(atCell.traineeId));
  for (const excluded of [elsewhere, draft, answered, someoneElses]) {
    assert.ok(!ids.includes(excluded.traineeId), `row ${excluded.traineeId} should not be listed`);
  }
  assert.strictEqual(ids.length, 2);
  assert.strictEqual(body.trainingToConfirm[0].title, 'At the line');
});

test('confirming at the floor writes the Employee as actor and no Account, and the record\'s read says "device"', async () => {
  const { recordId, traineeId } = await insertTrainee({ orgUnit: deviceCell, employee: tara });
  const identification = await identify(device, tara);

  const { status, body } = await answerAtFloor(floorHeaders(device, identification), traineeId, 'confirmed');
  assert.strictEqual(status, 200, JSON.stringify(body));
  assert.strictEqual(body.trainingRecord.id, recordId);
  const [trainee] = body.trainingRecord.trainees;
  assert.strictEqual(trainee.answer, 'confirmed');
  assert.strictEqual(trainee.answeredVia, 'device');

  const row = await traineeRow(traineeId);
  assert.strictEqual(row.answer, 'confirmed');
  assert.ok(row.answered_at);
  assert.strictEqual(String(row.answered_by_employee_id), String(tara.id));
  assert.strictEqual(row.answered_by_account_id, null);

  const { rows: audit } = await pool.query(
    `SELECT operation FROM audit_log WHERE table_name = 'training_trainees' AND record_id = $1 ORDER BY id`,
    [traineeId]
  );
  assert.deepStrictEqual(audit.map((r) => r.operation), ['INSERT', 'UPDATE']);

  // Answered rows leave the listing.
  const listed = await listAtFloor(floorHeaders(device, identification));
  assert.ok(!listed.body.trainingToConfirm.some((r) => r.traineeId === traineeId));
});

test('declining at the floor writes the same columns', async () => {
  const { traineeId } = await insertTrainee({ orgUnit: deviceLine, employee: tara });
  const identification = await identify(device, tara);
  const { status } = await answerAtFloor(floorHeaders(device, identification), traineeId, 'declined');
  assert.strictEqual(status, 200);
  const row = await traineeRow(traineeId);
  assert.strictEqual(row.answer, 'declined');
  assert.strictEqual(String(row.answered_by_employee_id), String(tara.id));
  assert.strictEqual(row.answered_by_account_id, null);
});

test('an answer changed between the two doors keeps exactly one actor', async () => {
  const account = await insertAccount({ employeeId: tara.id });
  const { traineeId } = await insertTrainee({ orgUnit: deviceLine, employee: tara });
  const identification = await identify(device, tara);

  assert.strictEqual((await answerAtFloor(floorHeaders(device, identification), traineeId, 'confirmed')).status, 200);
  let row = await traineeRow(traineeId);
  assert.strictEqual(row.answered_by_account_id, null);
  assert.ok(row.answered_by_employee_id);

  const viaAccount = await answerAtAccount(account, traineeId, 'declined');
  assert.strictEqual(viaAccount.status, 200, JSON.stringify(viaAccount.body));
  row = await traineeRow(traineeId);
  assert.strictEqual(row.answer, 'declined');
  assert.strictEqual(String(row.answered_by_account_id), String(account.id));
  assert.strictEqual(row.answered_by_employee_id, null);

  assert.strictEqual((await answerAtFloor(floorHeaders(device, identification), traineeId, 'confirmed')).status, 200);
  row = await traineeRow(traineeId);
  assert.strictEqual(row.answer, 'confirmed');
  assert.strictEqual(row.answered_by_account_id, null);
  assert.strictEqual(String(row.answered_by_employee_id), String(tara.id));
});

test('a missing identification is a 401 on both routes', async () => {
  const { traineeId } = await insertTrainee({ orgUnit: deviceLine, employee: tara });
  const list = await listAtFloor(floorHeaders(device));
  assert.strictEqual(list.status, 401);
  const answer = await answerAtFloor(floorHeaders(device), traineeId, 'confirmed');
  assert.strictEqual(answer.status, 401);
  assert.strictEqual((await traineeRow(traineeId)).answer, null);
});

test('an expired identification is a 401', async () => {
  const { traineeId } = await insertTrainee({ orgUnit: deviceLine, employee: tara });
  const identification = await identify(device, tara);
  await pool.query(
    `UPDATE technician_identifications SET expires_at = now() - interval '1 minute' WHERE floor_device_id = $1`,
    [device.id]
  );
  assert.strictEqual((await listAtFloor(floorHeaders(device, identification))).status, 401);
  assert.strictEqual((await answerAtFloor(floorHeaders(device, identification), traineeId, 'confirmed')).status, 401);
  assert.strictEqual((await traineeRow(traineeId)).answer, null);
});

test('an identification issued to another device is a 401', async () => {
  const { traineeId } = await insertTrainee({ orgUnit: deviceLine, employee: tara });
  const foreign = await identify(otherDevice, tara);
  assert.strictEqual((await listAtFloor(floorHeaders(device, foreign))).status, 401);
  assert.strictEqual((await answerAtFloor(floorHeaders(device, foreign), traineeId, 'confirmed')).status, 401);
  assert.strictEqual((await traineeRow(traineeId)).answer, null);
});

test('a missing, unknown or switched-off device is a 401', async () => {
  const { traineeId } = await insertTrainee({ orgUnit: deviceLine, employee: tara });
  const identification = await identify(device, tara);
  assert.strictEqual((await listAtFloor({ 'x-technician-identification': identification })).status, 401);
  assert.strictEqual(
    (await answerAtFloor({ 'x-floor-device': 'not-a-credential', 'x-technician-identification': identification }, traineeId, 'confirmed')).status,
    401
  );
  const switchedOff = await registerDevice(deviceLine.id, 'Switched off');
  const offIdentification = await identify(switchedOff, tara);
  await pool.query('UPDATE floor_devices SET is_active = FALSE WHERE id = $1', [switchedOff.id]);
  const refused = await answerAtFloor(floorHeaders(switchedOff, offIdentification), traineeId, 'confirmed');
  assert.strictEqual(refused.status, 401);
  assert.strictEqual(refused.body.message, 'Invalid or inactive floor device');
  assert.strictEqual((await listAtFloor(floorHeaders(switchedOff, offIdentification))).status, 401);
  assert.strictEqual((await traineeRow(traineeId)).answer, null);
});

test('a record whose Org Unit is outside the device\'s reach is a 403', async () => {
  const { traineeId } = await insertTrainee({ orgUnit: otherLine, employee: tara });
  const identification = await identify(device, tara);
  const { status, body } = await answerAtFloor(floorHeaders(device, identification), traineeId, 'confirmed');
  assert.strictEqual(status, 403);
  assert.strictEqual(body.message, "Outside the caller's granted Org Units");
  assert.strictEqual((await traineeRow(traineeId)).answer, null);
});

test('another Trainee\'s row is a 403', async () => {
  const { traineeId } = await insertTrainee({ orgUnit: deviceLine, employee: tara2 });
  const identification = await identify(device, tara);
  const { status, body } = await answerAtFloor(floorHeaders(device, identification), traineeId, 'confirmed');
  assert.strictEqual(status, 403);
  assert.strictEqual(body.message, 'Only the Trainee can answer for themselves');
  assert.strictEqual((await traineeRow(traineeId)).answer, null);
});

test('an unknown answer is a 400, an unknown Trainee a 404, a draft\'s Trainee a 404', async () => {
  const { traineeId } = await insertTrainee({ orgUnit: deviceLine, employee: tara });
  const draft = await insertTrainee({ orgUnit: deviceLine, employee: tara, status: 'draft' });
  const headers = floorHeaders(device, await identify(device, tara));

  assert.strictEqual((await answerAtFloor(headers, traineeId, 'maybe')).status, 400);
  assert.strictEqual((await answerAtFloor(headers, traineeId, undefined)).status, 400);
  assert.strictEqual((await answerAtFloor(headers, 999999999, 'confirmed')).status, 404);
  assert.strictEqual((await answerAtFloor(headers, 'abc', 'confirmed')).status, 404);
  const early = await answerAtFloor(headers, draft.traineeId, 'confirmed');
  assert.strictEqual(early.status, 404);
  assert.strictEqual((await traineeRow(draft.traineeId)).answer, null);
  assert.strictEqual((await traineeRow(traineeId)).answer, null);
});
