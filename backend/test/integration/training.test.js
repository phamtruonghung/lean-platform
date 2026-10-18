/*
 * The Training record over HTTP (issue #287, ADR-0043), against a real
 * database and a real (locally issued) JWKS — the same seam and the same
 * account setup as plant.test.js: this file inserts its own `app_users`,
 * `sites`, `org_units` and `employees` rows directly and deletes them again
 * in `test.after()`.
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

async function insertAccount({ role = 'supervisor', employeeId = null } = {}) {
  const subject = uniqueCode('trn');
  const { rows: [row] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status, employee_id)
     VALUES ($1, 'Training Test Account', $2, $3, TRUE, 'approved', $4) RETURNING id`,
    [`${subject}@example.com`, role, subject, employeeId]
  );
  insertedAccountIds.push(row.id);
  return { id: row.id, token: await authHeader(subject) };
}

async function insertSite() {
  const { rows: [row] } = await pool.query(
    `INSERT INTO sites (code, name, timezone) VALUES ($1, 'Training Test Site', 'Asia/Ho_Chi_Minh')
     RETURNING id, code`,
    [uniqueCode('TS')]
  );
  insertedSiteIds.push(row.id);
  return row;
}

async function insertOrgUnit(siteId, { parentId = null, name = 'Training Unit' } = {}) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, $2, $3, $4, 'area') RETURNING id, name`,
    [siteId, parentId, uniqueCode('OU'), name]
  );
  insertedOrgUnitIds.push(row.id);
  return row;
}

async function insertEmployee() {
  const { rows: [row] } = await pool.query(
    `INSERT INTO employees (employee_no, first_name, last_name, is_active)
     VALUES ($1, 'Tina', 'Trainer', TRUE) RETURNING id, display_name`,
    [uniqueCode('EMP')]
  );
  insertedEmployeeIds.push(row.id);
  return row;
}

async function insertGrant({ accountId, orgUnitId, canWrite }) {
  await pool.query(
    `INSERT INTO app_user_org_units (app_user_id, org_unit_id, can_write) VALUES ($1, $2, $3)`,
    [accountId, orgUnitId, canWrite]
  );
}

// Puts a record in the sent state directly, for the tests that are about
// something other than sending; the CHECK wants all three sent columns.
async function markSent(id) {
  await pool.query(
    `UPDATE training_records SET status = 'sent', sent_at = now(), sent_by_account_id = $2 WHERE id = $1`,
    [id, sender.id]
  );
}

async function call(method, path, token, body) {
  const response = await fetch(`${base}/api/people${path}`, {
    method,
    headers: { ...token, ...(body ? { 'content-type': 'application/json' } : {}) },
    body: body ? JSON.stringify(body) : undefined
  });
  const payload = await response.json().catch(() => null);
  return { response, payload };
}

async function raise(token, orgUnitId, overrides = {}) {
  const result = await call('POST', '/training', token, {
    orgUnitId,
    title: 'Lockout / tagout refresher',
    trainedOn: '2026-03-10',
    durationHours: 1.5,
    ...overrides
  });
  if (result.response.status === 201) insertedRecordIds.push(result.payload.trainingRecord.id);
  return result;
}

let site;
let otherSite;
let line;
let cell; // beneath `line`
let otherLine;
let admin;
let sender; // edit Grant on `line`
let reader; // approved, no Grants
let viewer; // read-only Grant on `line`
let trainer;

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

  site = await insertSite();
  otherSite = await insertSite();
  line = await insertOrgUnit(site.id, { name: 'Training Line' });
  cell = await insertOrgUnit(site.id, { parentId: line.id, name: 'Training Cell' });
  otherLine = await insertOrgUnit(otherSite.id, { name: 'Other Site Line' });
  trainer = await insertEmployee();

  admin = await insertAccount({ role: 'admin' });
  sender = await insertAccount();
  reader = await insertAccount({ role: 'operator' });
  viewer = await insertAccount();
  await insertGrant({ accountId: sender.id, orgUnitId: line.id, canWrite: true });
  await insertGrant({ accountId: viewer.id, orgUnitId: line.id, canWrite: false });
});

test.after(async () => {
  await pool.query('DELETE FROM training_trainees WHERE training_record_id = ANY($1)', [insertedRecordIds]);
  await pool.query('DELETE FROM training_records WHERE id = ANY($1)', [insertedRecordIds]);
  await pool.query('DELETE FROM app_user_org_units WHERE app_user_id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM app_users WHERE id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM employees WHERE id = ANY($1)', [insertedEmployeeIds]);
  // Children before parents.
  await pool.query('DELETE FROM org_units WHERE id = ANY($1)', [[...insertedOrgUnitIds].reverse()]);
  await pool.query('DELETE FROM sites WHERE id = ANY($1)', [insertedSiteIds]);
  await new Promise((resolve) => server.close(resolve));
  await closePool();
  await jwks.close();
});

// ---------------------------------------------------------------------------
// Raising, and the number.
// ---------------------------------------------------------------------------

test('raising a training record returns 201, a draft, with its facts and the trainer named', async () => {
  const { response, payload } = await raise(sender.token, line.id, {
    trainerEmployeeId: trainer.id,
    objective: 'Everyone can isolate the press'
  });
  assert.strictEqual(response.status, 201);
  const record = payload.trainingRecord;
  assert.strictEqual(record.status, 'draft');
  assert.strictEqual(record.title, 'Lockout / tagout refresher');
  assert.strictEqual(record.trainedOn, '2026-03-10');
  assert.strictEqual(record.durationHours, 1.5);
  assert.strictEqual(record.orgUnitId, line.id);
  assert.strictEqual(record.orgUnitName, 'Training Line');
  assert.strictEqual(record.trainerEmployeeId, trainer.id);
  assert.strictEqual(record.trainerName, trainer.display_name);
  assert.strictEqual(record.objective, 'Everyone can isolate the press');
});

test('trainer and objective are optional when raising', async () => {
  const { response, payload } = await raise(sender.token, line.id);
  assert.strictEqual(response.status, 201);
  assert.strictEqual(payload.trainingRecord.trainerEmployeeId, null);
  assert.strictEqual(payload.trainingRecord.objective, null);
});

test("the number is TR-<site code>-<year>-NNNNN, per Site, unique and never interleaved", async () => {
  const year = new Date().getUTCFullYear();
  const first = await raise(admin.token, line.id);
  const second = await raise(admin.token, cell.id);
  const elsewhere = await raise(admin.token, otherLine.id);

  const pattern = (code) => new RegExp(`^TR-${code}-${year}-\\d{5}$`);
  assert.match(first.payload.trainingRecord.number, pattern(site.code));
  assert.match(second.payload.trainingRecord.number, pattern(site.code));
  assert.match(elsewhere.payload.trainingRecord.number, pattern(otherSite.code));

  const sequence = (record) => Number(record.number.split('-').pop());
  assert.strictEqual(sequence(second.payload.trainingRecord), sequence(first.payload.trainingRecord) + 1);
  assert.strictEqual(sequence(elsewhere.payload.trainingRecord), 1);
  assert.notStrictEqual(first.payload.trainingRecord.number, second.payload.trainingRecord.number);
});

// ---------------------------------------------------------------------------
// Refusals, and their order.
// ---------------------------------------------------------------------------

test('a missing title, trainedOn or durationHours is a 400', async () => {
  for (const overrides of [
    { title: '' },
    { title: undefined },
    { trainedOn: undefined },
    { trainedOn: '10/03/2026' },
    { durationHours: undefined },
    { durationHours: 0 },
    { durationHours: -2 },
    { durationHours: '2' },
    { orgUnitId: undefined }
  ]) {
    const { response } = await raise(sender.token, line.id, overrides);
    assert.strictEqual(response.status, 400, JSON.stringify(overrides));
  }
});

test('an unknown Org Unit is a 404, for an administrator as well (not a 500)', async () => {
  const adminResult = await raise(admin.token, '999999999');
  assert.strictEqual(adminResult.response.status, 404);
  assert.strictEqual(adminResult.payload.message, 'Org Unit not found');
  // Existence before scope: a caller with no Grants gets the same 404, not a 403.
  const readerResult = await raise(reader.token, '999999999');
  assert.strictEqual(readerResult.response.status, 404);
});

test('an unknown trainer Employee is a 404', async () => {
  const { response, payload } = await raise(sender.token, line.id, { trainerEmployeeId: '999999999' });
  assert.strictEqual(response.status, 404);
  assert.strictEqual(payload.message, 'Employee not found');
});

test('an unknown trainer is a 404 before scope is asked about', async () => {
  const { response } = await raise(reader.token, line.id, { trainerEmployeeId: '999999999' });
  assert.strictEqual(response.status, 404);
});

test('outside the caller\'s Grants is a 403 carrying the canonical message', async () => {
  const { response, payload } = await raise(sender.token, otherLine.id);
  assert.strictEqual(response.status, 403);
  assert.strictEqual(payload.message, "Outside the caller's granted Org Units");
});

test('a read-only Grant cannot raise (write: true is asked)', async () => {
  const { response } = await raise(viewer.token, line.id);
  assert.strictEqual(response.status, 403);
});

test('an edit Grant on a parent reaches a Cell beneath it', async () => {
  const { response } = await raise(sender.token, cell.id);
  assert.strictEqual(response.status, 201);
});

// ---------------------------------------------------------------------------
// Draft visibility.
// ---------------------------------------------------------------------------

test('a draft is read by a sender and an administrator but is a 404 and absent for an unrelated reader', async () => {
  const { payload } = await raise(sender.token, line.id, { title: 'Draft visibility probe' });
  const id = payload.trainingRecord.id;

  for (const who of [sender, admin]) {
    const one = await call('GET', `/training/${id}`, who.token);
    assert.strictEqual(one.response.status, 200);
    const register = await call('GET', '/training', who.token);
    assert.ok(register.payload.trainingRecords.some((r) => r.id === id));
  }
  for (const who of [reader, viewer]) {
    const one = await call('GET', `/training/${id}`, who.token);
    assert.strictEqual(one.response.status, 404);
    const register = await call('GET', '/training', who.token);
    assert.strictEqual(register.response.status, 200);
    assert.ok(!register.payload.trainingRecords.some((r) => r.id === id));
  }
});

test('a sent record is read by any approved Account, register and own address', async () => {
  const { payload } = await raise(sender.token, line.id, { title: 'Sent visibility probe' });
  const id = payload.trainingRecord.id;
  await markSent(id);

  const one = await call('GET', `/training/${id}`, reader.token);
  assert.strictEqual(one.response.status, 200);
  assert.strictEqual(one.payload.trainingRecord.status, 'sent');
  const register = await call('GET', '/training', reader.token);
  assert.ok(register.payload.trainingRecords.some((r) => r.id === id));
});

test('an unknown or malformed record id is a 404', async () => {
  assert.strictEqual((await call('GET', '/training/999999999', admin.token)).response.status, 404);
  assert.strictEqual((await call('GET', '/training/abc', admin.token)).response.status, 404);
});

// ---------------------------------------------------------------------------
// The register's filters.
// ---------------------------------------------------------------------------

test('the register filters by Org Unit including everything beneath it, and by date range', async () => {
  const atLine = (await raise(admin.token, line.id, { title: 'Filter at line', trainedOn: '2025-01-10' })).payload.trainingRecord;
  const atCell = (await raise(admin.token, cell.id, { title: 'Filter at cell', trainedOn: '2025-02-10' })).payload.trainingRecord;
  const atOther = (await raise(admin.token, otherLine.id, { title: 'Filter elsewhere', trainedOn: '2025-02-11' })).payload.trainingRecord;

  const ids = (result) => result.payload.trainingRecords.map((r) => r.id);

  const underLine = await call('GET', `/training?orgUnitId=${line.id}`, admin.token);
  assert.ok(ids(underLine).includes(atLine.id));
  assert.ok(ids(underLine).includes(atCell.id));
  assert.ok(!ids(underLine).includes(atOther.id));

  const underCell = await call('GET', `/training?orgUnitId=${cell.id}`, admin.token);
  assert.ok(!ids(underCell).includes(atLine.id));
  assert.ok(ids(underCell).includes(atCell.id));

  const ranged = await call('GET', `/training?orgUnitId=${line.id}&from=2025-02-01&to=2025-02-28`, admin.token);
  assert.deepStrictEqual(ids(ranged), [atCell.id]);

  const fromOnly = await call('GET', '/training?from=2025-02-11&to=2025-02-11', admin.token);
  assert.ok(ids(fromOnly).includes(atOther.id));
  assert.ok(!ids(fromOnly).includes(atCell.id));
});

test('a bad filter is a 400 and an unknown Org Unit filter is a 404', async () => {
  assert.strictEqual((await call('GET', '/training?from=yesterday', admin.token)).response.status, 400);
  assert.strictEqual((await call('GET', '/training?orgUnitId=abc', admin.token)).response.status, 400);
  assert.strictEqual((await call('GET', '/training?orgUnitId=999999999', admin.token)).response.status, 404);
});

// ---------------------------------------------------------------------------
// Corrections while a draft.
// ---------------------------------------------------------------------------

// A full restatement of a record's own facts, as a correction must carry.
const RESTATEMENT = {
  title: 'Restated', trainedOn: '2026-05-02', durationHours: 2, objective: 'Restated objective'
};

test('a draft\'s own facts are corrected as a full restatement, and a fact left out is cleared', async () => {
  const { payload } = await raise(sender.token, line.id, { title: 'Before' });
  const id = payload.trainingRecord.id;

  const { response, payload: corrected } = await call('PATCH', `/training/${id}`, sender.token, {
    title: 'After',
    trainedOn: '2026-04-01',
    durationHours: 3,
    trainerEmployeeId: trainer.id,
    objective: 'Because'
  });
  assert.strictEqual(response.status, 200);
  const record = corrected.trainingRecord;
  assert.strictEqual(record.title, 'After');
  assert.strictEqual(record.trainedOn, '2026-04-01');
  assert.strictEqual(record.durationHours, 3);
  assert.strictEqual(record.trainerName, trainer.display_name);
  assert.strictEqual(record.number, payload.trainingRecord.number);
  assert.strictEqual(record.orgUnitId, line.id);

  // Restating again without a trainer or an objective clears both, as raising would.
  const cleared = await call('PATCH', `/training/${id}`, sender.token, {
    title: 'After', trainedOn: '2026-04-01', durationHours: 3
  });
  assert.strictEqual(cleared.response.status, 200);
  assert.strictEqual(cleared.payload.trainingRecord.trainerEmployeeId, null);
  assert.strictEqual(cleared.payload.trainingRecord.objective, null);
  assert.strictEqual(cleared.payload.trainingRecord.title, 'After');
});

test('correcting refuses in order: unknown record 404, scope 403, then invalid 400 / unknown trainer 404', async () => {
  const { payload } = await raise(sender.token, line.id);
  const id = payload.trainingRecord.id;

  assert.strictEqual((await call('PATCH', '/training/999999999', admin.token, { title: 'x' })).response.status, 404);
  assert.strictEqual((await call('PATCH', `/training/${id}`, reader.token, { title: 'x' })).response.status, 403);
  assert.strictEqual((await call('PATCH', `/training/${id}`, viewer.token, { title: 'x' })).response.status, 403);
  assert.strictEqual((await call('PATCH', `/training/${id}`, sender.token, { title: '' })).response.status, 400);
  assert.strictEqual((await call('PATCH', `/training/${id}`, sender.token, { durationHours: 0 })).response.status, 400);
  assert.strictEqual((await call('PATCH', `/training/${id}`, sender.token, {})).response.status, 400);
  // A partial body is not a restatement: it is refused as the raise route refuses it.
  assert.strictEqual((await call('PATCH', `/training/${id}`, sender.token, { title: 'Only a title' })).response.status, 400);
  assert.strictEqual((await call('PATCH', `/training/${id}`, sender.token, {
    ...RESTATEMENT, trainerEmployeeId: '999999999'
  })).response.status, 404);
});

test('the Org Unit of a record is not correctable', async () => {
  const { payload } = await raise(sender.token, line.id);
  const id = payload.trainingRecord.id;
  const { response } = await call('PATCH', `/training/${id}`, sender.token, { orgUnitId: cell.id });
  assert.strictEqual(response.status, 400);
});

test('a sent record\'s own facts are corrected, audited, and the Trainees\' answers are kept', async () => {
  const mine = await insertTrainee();
  const { record, ids } = await sentRecord([mine]);
  await call('POST', `/training/trainees/${ids[0]}/answer`, mine.account.token, { answer: 'confirmed' });
  const auditedUpdates = () => pool.query(
    `SELECT changed_by FROM audit_log
      WHERE table_name = 'training_records' AND record_id = $1 AND operation = 'UPDATE'
      ORDER BY id`,
    [record.id]
  );
  const { rows: beforeRows } = await auditedUpdates(); // sending is one UPDATE already.

  const { response, payload } = await call('PATCH', `/training/${record.id}`, sender.token, {
    ...RESTATEMENT, trainerEmployeeId: trainer.id
  });
  assert.strictEqual(response.status, 200);
  const corrected = payload.trainingRecord;
  assert.strictEqual(corrected.status, 'sent');
  assert.strictEqual(corrected.title, 'Restated');
  assert.strictEqual(corrected.trainedOn, '2026-05-02');
  assert.strictEqual(corrected.durationHours, 2);
  assert.strictEqual(corrected.objective, 'Restated objective');
  assert.strictEqual(corrected.number, record.number);
  assert.strictEqual(corrected.sentAt, (await call('GET', `/training/${record.id}`, reader.token)).payload.trainingRecord.sentAt);
  assert.strictEqual(corrected.trainees[0].answer, 'confirmed');

  const { rows } = await auditedUpdates();
  assert.strictEqual(rows.length, beforeRows.length + 1);
  assert.strictEqual(String(rows[rows.length - 1].changed_by), String(sender.id));
});

test('a correction is audited on training_records for a draft as well', async () => {
  const { payload } = await raise(sender.token, line.id);
  const id = payload.trainingRecord.id;
  await call('PATCH', `/training/${id}`, sender.token, RESTATEMENT);
  const { rows } = await pool.query(
    `SELECT operation, changed_by FROM audit_log
      WHERE table_name = 'training_records' AND record_id = $1 AND operation = 'UPDATE'`,
    [id]
  );
  assert.strictEqual(rows.length, 1);
  assert.strictEqual(String(rows[0].changed_by), String(sender.id));
});

test('a correction of a sent record is refused as the raise is: 400 for a bad fact, 404 for an unknown trainer', async () => {
  const { payload } = await raise(sender.token, line.id, { title: 'Sent and fixed' });
  const id = payload.trainingRecord.id;
  await markSent(id);

  for (const bad of [{ ...RESTATEMENT, title: ' ' }, { ...RESTATEMENT, trainedOn: '2026-02-30' },
    { ...RESTATEMENT, durationHours: 0 }, { ...RESTATEMENT, trainerEmployeeId: 'abc' }]) {
    assert.strictEqual((await call('PATCH', `/training/${id}`, sender.token, bad)).response.status, 400);
  }
  assert.strictEqual((await call('PATCH', `/training/${id}`, sender.token, {
    ...RESTATEMENT, trainerEmployeeId: '999999999'
  })).response.status, 404);
  const after = await call('GET', `/training/${id}`, sender.token);
  assert.strictEqual(after.payload.trainingRecord.title, 'Sent and fixed');
});

test('a caller outside the Grants is refused 403 on a sent record, with the canonical message', async () => {
  const { payload } = await raise(sender.token, line.id);
  const id = payload.trainingRecord.id;
  await markSent(id);
  for (const caller of [reader, viewer]) {
    const { response, payload: refusal } = await call('PATCH', `/training/${id}`, caller.token, RESTATEMENT);
    assert.strictEqual(response.status, 403);
    assert.strictEqual(refusal.message, "Outside the caller's granted Org Units");
  }
  assert.strictEqual((await call('PATCH', '/training/999999999', admin.token, RESTATEMENT)).response.status, 404);
});

// ---------------------------------------------------------------------------
// The Trainees on a record (issue #288).
// ---------------------------------------------------------------------------

async function insertNamedEmployee({ active = true } = {}) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO employees (employee_no, first_name, last_name, is_active)
     VALUES ($1, 'Tom', 'Trainee', $2) RETURNING id, employee_no, display_name`,
    [uniqueCode('EMP'), active]
  );
  insertedEmployeeIds.push(row.id);
  return row;
}

async function draftRecord() {
  const { payload } = await raise(sender.token, line.id, { title: 'Trainee probe' });
  return payload.trainingRecord;
}

test('adding a Trainee is a 201 and the record reads with the Employee\'s number and name and a count', async () => {
  const record = await draftRecord();
  const employee = await insertNamedEmployee();

  const added = await call('POST', `/training/${record.id}/trainees`, sender.token, { employeeId: employee.id });
  assert.strictEqual(added.response.status, 201);
  assert.strictEqual(added.payload.trainingRecord.traineeCount, 1);

  const read = await call('GET', `/training/${record.id}`, sender.token);
  assert.strictEqual(read.payload.trainingRecord.traineeCount, 1);
  const [trainee] = read.payload.trainingRecord.trainees;
  assert.strictEqual(trainee.employeeId, employee.id);
  assert.strictEqual(trainee.employeeNo, employee.employee_no);
  assert.strictEqual(trainee.employeeName, employee.display_name);
  assert.ok(trainee.id);
  assert.ok(trainee.addedAt);
});

test('a record with no Trainees reads an empty list and a count of zero', async () => {
  const record = await draftRecord();
  const read = await call('GET', `/training/${record.id}`, sender.token);
  assert.deepStrictEqual(read.payload.trainingRecord.trainees, []);
  assert.strictEqual(read.payload.trainingRecord.traineeCount, 0);
});

test('Trainees read back in the order they were added', async () => {
  const record = await draftRecord();
  const first = await insertNamedEmployee();
  const second = await insertNamedEmployee();
  const third = await insertNamedEmployee();
  for (const employee of [second, third, first]) {
    const { response } = await call('POST', `/training/${record.id}/trainees`, sender.token, { employeeId: employee.id });
    assert.strictEqual(response.status, 201);
  }
  const read = await call('GET', `/training/${record.id}`, sender.token);
  assert.deepStrictEqual(
    read.payload.trainingRecord.trainees.map((t) => t.employeeId),
    [second.id, third.id, first.id]
  );
});

test('the same Employee twice on one record is a 409, and on another record is fine', async () => {
  const record = await draftRecord();
  const other = await draftRecord();
  const employee = await insertNamedEmployee();
  assert.strictEqual((await call('POST', `/training/${record.id}/trainees`, sender.token, { employeeId: employee.id })).response.status, 201);
  const again = await call('POST', `/training/${record.id}/trainees`, sender.token, { employeeId: employee.id });
  assert.strictEqual(again.response.status, 409);
  assert.match(again.payload.message, /already a Trainee/);
  assert.strictEqual((await call('POST', `/training/${other.id}/trainees`, sender.token, { employeeId: employee.id })).response.status, 201);
  const read = await call('GET', `/training/${record.id}`, sender.token);
  assert.strictEqual(read.payload.trainingRecord.traineeCount, 1);
});

test('a departed Employee is refused with a 409', async () => {
  const record = await draftRecord();
  const departed = await insertNamedEmployee({ active: false });
  const { response, payload } = await call('POST', `/training/${record.id}/trainees`, sender.token, { employeeId: departed.id });
  assert.strictEqual(response.status, 409);
  assert.match(payload.message, /departed/);
});

test('an unknown Employee, an unknown record and a bad employeeId are refused 404, 404 and 400', async () => {
  const record = await draftRecord();
  const unknownEmployee = await call('POST', `/training/${record.id}/trainees`, sender.token, { employeeId: '999999999' });
  assert.strictEqual(unknownEmployee.response.status, 404);
  assert.strictEqual(unknownEmployee.payload.message, 'Employee not found');
  const employee = await insertNamedEmployee();
  const unknownRecord = await call('POST', '/training/999999999/trainees', admin.token, { employeeId: employee.id });
  assert.strictEqual(unknownRecord.response.status, 404);
  assert.strictEqual(unknownRecord.payload.message, 'Training record not found');
  assert.strictEqual((await call('POST', `/training/${record.id}/trainees`, sender.token, {})).response.status, 400);
  assert.strictEqual((await call('POST', `/training/${record.id}/trainees`, sender.token, { employeeId: 'abc' })).response.status, 400);
});

test('a caller outside the record\'s Org Unit is refused 403 on add and on remove', async () => {
  const record = await draftRecord();
  const employee = await insertNamedEmployee();
  const seeded = await call('POST', `/training/${record.id}/trainees`, sender.token, { employeeId: employee.id });
  const traineeId = seeded.payload.trainingRecord.trainees[0].id;

  for (const who of [reader, viewer]) {
    const add = await call('POST', `/training/${record.id}/trainees`, who.token, { employeeId: employee.id });
    assert.strictEqual(add.response.status, 403);
    assert.strictEqual(add.payload.message, "Outside the caller's granted Org Units");
    const remove = await call('DELETE', `/training/${record.id}/trainees/${traineeId}`, who.token);
    assert.strictEqual(remove.response.status, 403);
    assert.strictEqual(remove.payload.message, "Outside the caller's granted Org Units");
  }
  const read = await call('GET', `/training/${record.id}`, sender.token);
  assert.strictEqual(read.payload.trainingRecord.traineeCount, 1);
});

test('removing a Trainee is a 200, the Trainee is gone from the read and the count drops', async () => {
  const record = await draftRecord();
  const keep = await insertNamedEmployee();
  const drop = await insertNamedEmployee();
  await call('POST', `/training/${record.id}/trainees`, sender.token, { employeeId: keep.id });
  const added = await call('POST', `/training/${record.id}/trainees`, sender.token, { employeeId: drop.id });
  const dropId = added.payload.trainingRecord.trainees.find((t) => t.employeeId === drop.id).id;

  const removed = await call('DELETE', `/training/${record.id}/trainees/${dropId}`, sender.token);
  assert.strictEqual(removed.response.status, 200);
  assert.strictEqual(removed.payload.trainingRecord.traineeCount, 1);

  const read = await call('GET', `/training/${record.id}`, sender.token);
  assert.deepStrictEqual(read.payload.trainingRecord.trainees.map((t) => t.employeeId), [keep.id]);
  assert.strictEqual(read.payload.trainingRecord.traineeCount, 1);
});

test('removing a Trainee id that is not on that record is a 404, and leaves the other record alone', async () => {
  const record = await draftRecord();
  const other = await draftRecord();
  const employee = await insertNamedEmployee();
  const added = await call('POST', `/training/${other.id}/trainees`, sender.token, { employeeId: employee.id });
  const traineeId = added.payload.trainingRecord.trainees[0].id;

  const wrong = await call('DELETE', `/training/${record.id}/trainees/${traineeId}`, sender.token);
  assert.strictEqual(wrong.response.status, 404);
  assert.strictEqual(wrong.payload.message, 'Trainee not found');
  assert.strictEqual((await call('DELETE', `/training/${record.id}/trainees/abc`, sender.token)).response.status, 404);
  assert.strictEqual((await call('DELETE', '/training/999999999/trainees/1', admin.token)).response.status, 404);
  const read = await call('GET', `/training/${other.id}`, sender.token);
  assert.strictEqual(read.payload.trainingRecord.traineeCount, 1);
});

test('a sent record\'s list takes an added Trainee, who is asked at once, and a removed one', async () => {
  const record = await draftRecord();
  const onList = await insertNamedEmployee();
  const late = await insertNamedEmployee();
  const added = await call('POST', `/training/${record.id}/trainees`, sender.token, { employeeId: onList.id });
  const traineeId = added.payload.trainingRecord.trainees[0].id;
  await markSent(record.id);

  const add = await call('POST', `/training/${record.id}/trainees`, sender.token, { employeeId: late.id });
  assert.strictEqual(add.response.status, 201);
  assert.strictEqual(add.payload.trainingRecord.status, 'sent');
  assert.deepStrictEqual(add.payload.trainingRecord.trainees.map((t) => t.employeeId), [onList.id, late.id]);
  const remove = await call('DELETE', `/training/${record.id}/trainees/${traineeId}`, sender.token);
  assert.strictEqual(remove.response.status, 200);

  const read = await call('GET', `/training/${record.id}`, sender.token);
  assert.deepStrictEqual(read.payload.trainingRecord.trainees.map((t) => t.employeeId), [late.id]);
});

test('adding and removing a Trainee are audited against the acting Account', async () => {
  const record = await draftRecord();
  const employee = await insertNamedEmployee();
  const added = await call('POST', `/training/${record.id}/trainees`, sender.token, { employeeId: employee.id });
  const traineeId = added.payload.trainingRecord.trainees[0].id;
  await call('DELETE', `/training/${record.id}/trainees/${traineeId}`, sender.token);

  const { rows } = await pool.query(
    `SELECT operation, changed_by FROM audit_log
      WHERE table_name = 'training_trainees' AND record_id = $1
      ORDER BY operation`,
    [traineeId]
  );
  assert.deepStrictEqual(rows.map((r) => r.operation), ['DELETE', 'INSERT']);
  for (const row of rows) assert.strictEqual(String(row.changed_by), String(sender.id));
});

// ---------------------------------------------------------------------------
// Sending a record, and a Trainee answering it (issue #289).
// ---------------------------------------------------------------------------

// A draft with a trainer, an objective and the given Employees as Trainees.
async function completeDraft(employees, overrides = {}) {
  const { payload } = await raise(sender.token, line.id, {
    title: 'Send probe',
    trainerEmployeeId: trainer.id,
    objective: 'Everyone can isolate the press',
    ...overrides
  });
  const record = payload.trainingRecord;
  for (const employee of employees) {
    const { response } = await call('POST', `/training/${record.id}/trainees`, sender.token, { employeeId: employee.id });
    assert.strictEqual(response.status, 201);
  }
  return record;
}

// An Account linked to a fresh Employee, who is the Trainee.
async function insertTrainee() {
  const employee = await insertNamedEmployee();
  const account = await insertAccount({ employeeId: employee.id });
  return { employee, account };
}

async function traineeRowId(recordId, employeeId) {
  const read = await call('GET', `/training/${recordId}`, admin.token);
  return read.payload.trainingRecord.trainees.find((t) => t.employeeId === employeeId).id;
}

// A sent record with the given Trainees; returns the record and their row ids.
async function sentRecord(trainees) {
  const record = await completeDraft(trainees.map((t) => t.employee));
  const { response } = await call('POST', `/training/${record.id}/send`, sender.token);
  assert.strictEqual(response.status, 200);
  const ids = [];
  for (const t of trainees) ids.push(await traineeRowId(record.id, t.employee.id));
  return { record, ids };
}

test('sending a complete draft sets the three sent columns and reads back as sent', async () => {
  const { employee } = await insertTrainee();
  const record = await completeDraft([employee]);
  const { response, payload } = await call('POST', `/training/${record.id}/send`, sender.token);
  assert.strictEqual(response.status, 200);
  assert.strictEqual(payload.trainingRecord.status, 'sent');
  assert.ok(payload.trainingRecord.sentAt);
  const { rows: [row] } = await pool.query(
    'SELECT status, sent_at, sent_by_account_id FROM training_records WHERE id = $1', [record.id]
  );
  assert.strictEqual(row.status, 'sent');
  assert.ok(row.sent_at);
  assert.strictEqual(String(row.sent_by_account_id), String(sender.id));
});

test('sending refuses a record with no trainer, no objective or no Trainee, each in its own words', async () => {
  // Title, date and duration are NOT NULL in the schema and a correction that
  // blanks one is a 400, so a draft can never be missing them over HTTP (the
  // check in `incompleteness` is defensive and unreachable through the API);
  // only the optional facts and the list can be.
  const probe = await completeDraft([await insertNamedEmployee()]);
  for (const blank of [{ title: '  ' }, { trainedOn: null }, { durationHours: 0 }]) {
    const { response } = await call('PATCH', `/training/${probe.id}`, sender.token, blank);
    assert.strictEqual(response.status, 400);
  }
  const employee = await insertNamedEmployee();
  const noTrainer = await completeDraft([employee], { trainerEmployeeId: undefined });
  const noObjective = await completeDraft([employee], { objective: undefined });
  const noTrainee = await completeDraft([]);
  const cases = [
    [noTrainer, /trainer/],
    [noObjective, /objective/],
    [noTrainee, /Trainee/]
  ];
  for (const [record, pattern] of cases) {
    const { response, payload } = await call('POST', `/training/${record.id}/send`, sender.token);
    assert.strictEqual(response.status, 409);
    assert.match(payload.message, pattern);
    const read = await call('GET', `/training/${record.id}`, sender.token);
    assert.strictEqual(read.payload.trainingRecord.status, 'draft');
    assert.strictEqual(read.payload.trainingRecord.sentAt, null);
  }
});

test('a second send is a 409 and leaves sent_at as it was', async () => {
  const { employee } = await insertTrainee();
  const record = await completeDraft([employee]);
  const first = await call('POST', `/training/${record.id}/send`, sender.token);
  const again = await call('POST', `/training/${record.id}/send`, sender.token);
  assert.strictEqual(again.response.status, 409);
  assert.match(again.payload.message, /already been sent/);
  const read = await call('GET', `/training/${record.id}`, sender.token);
  assert.strictEqual(read.payload.trainingRecord.sentAt, first.payload.trainingRecord.sentAt);
});

test('sending is refused 403 outside the Grants, and 404 for an unknown record', async () => {
  const { employee } = await insertTrainee();
  const record = await completeDraft([employee]);
  for (const who of [reader, viewer]) {
    const { response, payload } = await call('POST', `/training/${record.id}/send`, who.token);
    assert.strictEqual(response.status, 403);
    assert.strictEqual(payload.message, "Outside the caller's granted Org Units");
  }
  const unknown = await call('POST', '/training/999999999/send', admin.token);
  assert.strictEqual(unknown.response.status, 404);
  assert.strictEqual(unknown.payload.message, 'Training record not found');
  assert.strictEqual((await call('POST', '/training/abc/send', admin.token)).response.status, 404);
  const read = await call('GET', `/training/${record.id}`, sender.token);
  assert.strictEqual(read.payload.trainingRecord.status, 'draft');
});

test('a Trainee answers for themselves; a declined answer persists on the record\'s read', async () => {
  const mine = await insertTrainee();
  const { record, ids } = await sentRecord([mine]);
  const { response, payload } = await call('POST', `/training/trainees/${ids[0]}/answer`, mine.account.token, { answer: 'declined' });
  assert.strictEqual(response.status, 200);
  assert.strictEqual(payload.trainingRecord.id, record.id);

  const read = await call('GET', `/training/${record.id}`, reader.token);
  const [trainee] = read.payload.trainingRecord.trainees;
  assert.strictEqual(trainee.answer, 'declined');
  assert.ok(trainee.answeredAt);
  assert.strictEqual(trainee.answeredVia, 'account');
  const { rows: [row] } = await pool.query(
    'SELECT answered_by_account_id, answered_by_employee_id FROM training_trainees WHERE id = $1', [ids[0]]
  );
  assert.strictEqual(String(row.answered_by_account_id), String(mine.account.id));
  assert.strictEqual(row.answered_by_employee_id, null);
});

test('nobody else can answer for a Trainee: not a colleague with an edit Grant, not an administrator', async () => {
  const mine = await insertTrainee();
  const { record, ids } = await sentRecord([mine]);
  // A colleague: linked to an Employee of their own, holding an edit Grant on the record's Org Unit.
  const colleagueEmployee = await insertNamedEmployee();
  const colleague = await insertAccount({ employeeId: colleagueEmployee.id });
  await insertGrant({ accountId: colleague.id, orgUnitId: line.id, canWrite: true });

  for (const who of [colleague, sender, admin, reader]) {
    const { response, payload } = await call('POST', `/training/trainees/${ids[0]}/answer`, who.token, { answer: 'confirmed' });
    assert.strictEqual(response.status, 403);
    assert.strictEqual(payload.message, 'Only the Trainee can answer for themselves');
  }
  const read = await call('GET', `/training/${record.id}`, admin.token);
  assert.strictEqual(read.payload.trainingRecord.trainees[0].answer, null);
});

test('an unknown answer is 400, an unknown or malformed Trainee is 404, a draft\'s Trainee is 404', async () => {
  const mine = await insertTrainee();
  const { ids } = await sentRecord([mine]);
  const bad = await call('POST', `/training/trainees/${ids[0]}/answer`, mine.account.token, { answer: 'maybe' });
  assert.strictEqual(bad.response.status, 400);
  assert.strictEqual((await call('POST', `/training/trainees/${ids[0]}/answer`, mine.account.token, {})).response.status, 400);
  const unknown = await call('POST', '/training/trainees/999999999/answer', mine.account.token, { answer: 'confirmed' });
  assert.strictEqual(unknown.response.status, 404);
  assert.strictEqual(unknown.payload.message, 'Trainee not found');
  assert.strictEqual((await call('POST', '/training/trainees/abc/answer', mine.account.token, { answer: 'confirmed' })).response.status, 404);

  // Their own row on a record that has not been sent: not an answerable thing yet.
  const draft = await completeDraft([mine.employee]);
  const draftRow = await traineeRowId(draft.id, mine.employee.id);
  const early = await call('POST', `/training/trainees/${draftRow}/answer`, mine.account.token, { answer: 'confirmed' });
  assert.strictEqual(early.response.status, 404);
});

test('an Account linked to no Employee cannot answer, and has an empty queue', async () => {
  const mine = await insertTrainee();
  const { ids } = await sentRecord([mine]);
  const { response } = await call('POST', `/training/trainees/${ids[0]}/answer`, reader.token, { answer: 'confirmed' });
  assert.strictEqual(response.status, 403);
  const queue = await call('GET', '/training/to-confirm', reader.token);
  assert.strictEqual(queue.response.status, 200);
  assert.deepStrictEqual(queue.payload.trainingToConfirm, []);
});

test('a changed answer updates the same row and the update is audited', async () => {
  const mine = await insertTrainee();
  const other = await insertTrainee();
  const { record, ids } = await sentRecord([mine, other]);
  await call('POST', `/training/trainees/${ids[0]}/answer`, mine.account.token, { answer: 'declined' });
  await call('POST', `/training/trainees/${ids[0]}/answer`, mine.account.token, { answer: 'confirmed' });

  const { rows: [count] } = await pool.query(
    'SELECT count(*)::int AS n FROM training_trainees WHERE training_record_id = $1', [record.id]
  );
  assert.strictEqual(count.n, 2);
  const read = await call('GET', `/training/${record.id}`, reader.token);
  assert.strictEqual(read.payload.trainingRecord.trainees[0].answer, 'confirmed');

  const { rows } = await pool.query(
    `SELECT operation, changed_by FROM audit_log
      WHERE table_name = 'training_trainees' AND record_id = $1 AND operation = 'UPDATE'`,
    [ids[0]]
  );
  assert.strictEqual(rows.length, 2);
  for (const row of rows) assert.strictEqual(String(row.changed_by), String(mine.account.id));
});

test('the record reads three different ways: nobody asked, one declined, all confirmed', async () => {
  const first = await insertTrainee();
  const second = await insertTrainee();
  const draft = await completeDraft([first.employee, second.employee]);
  const draftRead = (await call('GET', `/training/${draft.id}`, sender.token)).payload.trainingRecord;
  assert.deepStrictEqual(
    [draftRead.status, draftRead.traineeCount, draftRead.answeredCount, draftRead.fullyConfirmed],
    ['draft', 2, 0, false]
  );

  const { record, ids } = await sentRecord([first, second]);
  const asked = (await call('GET', `/training/${record.id}`, reader.token)).payload.trainingRecord;
  assert.deepStrictEqual(
    [asked.status, asked.traineeCount, asked.answeredCount, asked.declinedCount, asked.fullyConfirmed],
    ['sent', 2, 0, 0, false]
  );

  await call('POST', `/training/trainees/${ids[0]}/answer`, first.account.token, { answer: 'confirmed' });
  await call('POST', `/training/trainees/${ids[1]}/answer`, second.account.token, { answer: 'declined' });
  const declined = (await call('GET', `/training/${record.id}`, reader.token)).payload.trainingRecord;
  assert.deepStrictEqual(
    [declined.answeredCount, declined.confirmedCount, declined.declinedCount, declined.fullyConfirmed],
    [2, 1, 1, false]
  );

  await call('POST', `/training/trainees/${ids[1]}/answer`, second.account.token, { answer: 'confirmed' });
  const confirmed = (await call('GET', `/training/${record.id}`, reader.token)).payload.trainingRecord;
  assert.deepStrictEqual(
    [confirmed.answeredCount, confirmed.confirmedCount, confirmed.declinedCount, confirmed.fullyConfirmed],
    [2, 2, 0, true]
  );

  // The register carries the same reading.
  const register = await call('GET', '/training', reader.token);
  const listed = register.payload.trainingRecords.find((r) => r.id === record.id);
  assert.strictEqual(listed.fullyConfirmed, true);
  assert.strictEqual(listed.confirmedCount, 2);
  assert.ok(listed.sentAt);
});

test('the queue holds only the caller\'s own, sent, unanswered Trainee rows, oldest sent first', async () => {
  const mine = await insertTrainee();
  const colleague = await insertTrainee();
  const older = await completeDraft([mine.employee, colleague.employee], { title: 'Queue older' });
  const newer = await completeDraft([mine.employee], { title: 'Queue newer' });
  const answered = await completeDraft([mine.employee], { title: 'Queue answered' });
  const unsent = await completeDraft([mine.employee], { title: 'Queue draft' });
  // Send out of creation order, so ordering is by when each was sent.
  await call('POST', `/training/${newer.id}/send`, sender.token);
  await new Promise((resolve) => setTimeout(resolve, 20));
  await call('POST', `/training/${older.id}/send`, sender.token);
  await call('POST', `/training/${answered.id}/send`, sender.token);
  const answeredRow = await traineeRowId(answered.id, mine.employee.id);
  await call('POST', `/training/trainees/${answeredRow}/answer`, mine.account.token, { answer: 'confirmed' });

  const queue = await call('GET', '/training/to-confirm', mine.account.token);
  assert.strictEqual(queue.response.status, 200);
  const rows = queue.payload.trainingToConfirm;
  assert.deepStrictEqual(rows.map((r) => r.title), ['Queue newer', 'Queue older']);
  assert.ok(!rows.some((r) => r.id === unsent.id));
  const [first] = rows;
  assert.strictEqual(first.id, newer.id);
  assert.strictEqual(first.number, newer.number);
  assert.strictEqual(first.trainedOn, '2026-03-10');
  assert.strictEqual(first.durationHours, 1.5);
  assert.strictEqual(first.trainerName, trainer.display_name);
  assert.strictEqual(first.objective, 'Everyone can isolate the press');
  assert.strictEqual(first.orgUnitName, 'Training Line');
  assert.strictEqual(first.traineeId, await traineeRowId(newer.id, mine.employee.id));

  const theirs = await call('GET', '/training/to-confirm', colleague.account.token);
  assert.deepStrictEqual(theirs.payload.trainingToConfirm.map((r) => r.title), ['Queue older']);
});

// ---------------------------------------------------------------------------
// What the trainer recorded about each Trainee (issue #290).
// ---------------------------------------------------------------------------

// A draft with one Trainee; returns the record and the Trainee row's id.
async function recordWithTrainee() {
  const employee = await insertNamedEmployee();
  const record = await completeDraft([employee]);
  return { record, traineeId: await traineeRowId(record.id, employee.id) };
}

test('a Trainee reads with no evaluation until the trainer sets one', async () => {
  const { record } = await recordWithTrainee();
  const read = await call('GET', `/training/${record.id}`, sender.token);
  assert.strictEqual(read.payload.trainingRecord.trainees[0].evaluation, null);
});

test('the trainer sets each evaluation, and clears it back to null', async () => {
  const { record, traineeId } = await recordWithTrainee();
  const path = `/training/${record.id}/trainees/${traineeId}`;

  for (const evaluation of ['paper', 'job_training', 'paper']) {
    const { response, payload } = await call('PATCH', path, sender.token, { evaluation });
    assert.strictEqual(response.status, 200);
    assert.strictEqual(payload.trainingRecord.trainees[0].evaluation, evaluation);
    const read = await call('GET', `/training/${record.id}`, sender.token);
    assert.strictEqual(read.payload.trainingRecord.trainees[0].evaluation, evaluation);
  }

  const cleared = await call('PATCH', path, sender.token, { evaluation: null });
  assert.strictEqual(cleared.response.status, 200);
  assert.strictEqual(cleared.payload.trainingRecord.trainees[0].evaluation, null);
  assert.strictEqual(cleared.payload.trainingRecord.traineeCount, 1);
});

test('an unknown evaluation and a missing key are each a 400 in the Module\'s own words', async () => {
  const { record, traineeId } = await recordWithTrainee();
  const path = `/training/${record.id}/trainees/${traineeId}`;
  await call('PATCH', path, sender.token, { evaluation: 'paper' });

  const unknown = await call('PATCH', path, sender.token, { evaluation: 'oral' });
  assert.strictEqual(unknown.response.status, 400);
  assert.match(unknown.payload.message, /evaluation must be one of: paper, job_training/);
  const wrongType = await call('PATCH', path, sender.token, { evaluation: 3 });
  assert.strictEqual(wrongType.response.status, 400);
  const missing = await call('PATCH', path, sender.token, {});
  assert.strictEqual(missing.response.status, 400);
  assert.match(missing.payload.message, /evaluation is required/);

  // None of the refusals touched the value.
  const read = await call('GET', `/training/${record.id}`, sender.token);
  assert.strictEqual(read.payload.trainingRecord.trainees[0].evaluation, 'paper');
});

test('an unknown record is a 404, for an administrator as well', async () => {
  const { response, payload } = await call('PATCH', '/training/999999999/trainees/1', admin.token, { evaluation: 'paper' });
  assert.strictEqual(response.status, 404);
  assert.strictEqual(payload.message, 'Training record not found');
});

test('an unknown Trainee, or one from a different record, is a 404 and changes nothing', async () => {
  const { record } = await recordWithTrainee();
  const other = await recordWithTrainee();

  const unknown = await call('PATCH', `/training/${record.id}/trainees/999999999`, sender.token, { evaluation: 'paper' });
  assert.strictEqual(unknown.response.status, 404);
  assert.strictEqual(unknown.payload.message, 'Trainee not found');
  const malformed = await call('PATCH', `/training/${record.id}/trainees/abc`, sender.token, { evaluation: 'paper' });
  assert.strictEqual(malformed.response.status, 404);
  const foreign = await call('PATCH', `/training/${record.id}/trainees/${other.traineeId}`, sender.token, { evaluation: 'paper' });
  assert.strictEqual(foreign.response.status, 404);
  assert.strictEqual(foreign.payload.message, 'Trainee not found');

  const read = await call('GET', `/training/${other.record.id}`, sender.token);
  assert.strictEqual(read.payload.trainingRecord.trainees[0].evaluation, null);
});

test('a caller outside the record\'s Grants is a 403 with the canonical message, for a read-only Grant too', async () => {
  const { record, traineeId } = await recordWithTrainee();
  const path = `/training/${record.id}/trainees/${traineeId}`;

  for (const caller of [reader, viewer]) {
    const { response, payload } = await call('PATCH', path, caller.token, { evaluation: 'paper' });
    assert.strictEqual(response.status, 403);
    assert.strictEqual(payload.message, "Outside the caller's granted Org Units");
  }
  const read = await call('GET', `/training/${record.id}`, sender.token);
  assert.strictEqual(read.payload.trainingRecord.trainees[0].evaluation, null);
});

test('the evaluation is settable after the record is sent, alongside add and remove', async () => {
  const { record, traineeId } = await recordWithTrainee();
  await markSent(record.id);

  const { response, payload } = await call('PATCH', `/training/${record.id}/trainees/${traineeId}`, sender.token, {
    evaluation: 'job_training'
  });
  assert.strictEqual(response.status, 200);
  assert.strictEqual(payload.trainingRecord.status, 'sent');
  assert.strictEqual(payload.trainingRecord.trainees[0].evaluation, 'job_training');

  const late = await insertNamedEmployee();
  const add = await call('POST', `/training/${record.id}/trainees`, sender.token, { employeeId: late.id });
  assert.strictEqual(add.response.status, 201);
  const remove = await call('DELETE', `/training/${record.id}/trainees/${traineeId}`, sender.token);
  assert.strictEqual(remove.response.status, 200);
});

test('setting the evaluation does not disturb a Trainee\'s answer', async () => {
  const mine = await insertTrainee();
  const { record, ids } = await sentRecord([mine]);
  await call('POST', `/training/trainees/${ids[0]}/answer`, mine.account.token, { answer: 'confirmed' });

  const { response, payload } = await call('PATCH', `/training/${record.id}/trainees/${ids[0]}`, sender.token, {
    evaluation: 'paper'
  });
  assert.strictEqual(response.status, 200);
  assert.strictEqual(payload.trainingRecord.trainees[0].answer, 'confirmed');
  assert.strictEqual(payload.trainingRecord.trainees[0].evaluation, 'paper');
});

test('setting and clearing the evaluation are audited against the acting Account', async () => {
  const { record, traineeId } = await recordWithTrainee();
  const path = `/training/${record.id}/trainees/${traineeId}`;
  await call('PATCH', path, sender.token, { evaluation: 'paper' });
  await call('PATCH', path, sender.token, { evaluation: null });

  const { rows } = await pool.query(
    `SELECT operation, changed_by FROM audit_log
      WHERE table_name = 'training_trainees' AND record_id = $1 AND operation = 'UPDATE'`,
    [traineeId]
  );
  assert.strictEqual(rows.length, 2);
  for (const row of rows) assert.strictEqual(String(row.changed_by), String(sender.id));
});

// ---------------------------------------------------------------------------
// Putting a sent record right (issue #291).
// ---------------------------------------------------------------------------

test('a Trainee added after sending is asked at once: in their queue with no second send', async () => {
  const mine = await insertTrainee();
  const first = await insertTrainee();
  const { record } = await sentRecord([first]);

  const before = await call('GET', '/training/to-confirm', mine.account.token);
  assert.ok(!before.payload.trainingToConfirm.some((r) => r.id === record.id));

  const added = await call('POST', `/training/${record.id}/trainees`, sender.token, { employeeId: mine.employee.id });
  assert.strictEqual(added.response.status, 201);
  const traineeId = added.payload.trainingRecord.trainees.find((t) => t.employeeId === mine.employee.id).id;

  const queue = await call('GET', '/training/to-confirm', mine.account.token);
  const row = queue.payload.trainingToConfirm.find((r) => r.id === record.id);
  assert.ok(row);
  assert.strictEqual(row.traineeId, traineeId);

  const { rows } = await pool.query(
    `SELECT operation, changed_by FROM audit_log
      WHERE table_name = 'training_trainees' AND record_id = $1`,
    [traineeId]
  );
  assert.deepStrictEqual(rows.map((r) => r.operation), ['INSERT']);
  assert.strictEqual(String(rows[0].changed_by), String(sender.id));
});

test('adding to a sent record keeps the refusals: duplicate 409, departed 409, unknown 404, outside the Grants 403', async () => {
  const first = await insertTrainee();
  const { record } = await sentRecord([first]);
  const path = `/training/${record.id}/trainees`;

  assert.strictEqual((await call('POST', path, sender.token, { employeeId: first.employee.id })).response.status, 409);
  const departed = await insertNamedEmployee({ active: false });
  assert.strictEqual((await call('POST', path, sender.token, { employeeId: departed.id })).response.status, 409);
  assert.strictEqual((await call('POST', path, sender.token, { employeeId: '999999999' })).response.status, 404);
  assert.strictEqual((await call('POST', '/training/999999999/trainees', admin.token, { employeeId: first.employee.id })).response.status, 404);
  const outsider = await insertNamedEmployee();
  for (const caller of [reader, viewer]) {
    const { response, payload } = await call('POST', path, caller.token, { employeeId: outsider.id });
    assert.strictEqual(response.status, 403);
    assert.strictEqual(payload.message, "Outside the caller's granted Org Units");
  }
});

test('removing a Trainee who has already answered is allowed; the answer goes with the row and the removal is audited', async () => {
  const wrong = await insertTrainee();
  const right = await insertTrainee();
  const { record, ids } = await sentRecord([wrong, right]);
  await call('POST', `/training/trainees/${ids[0]}/answer`, wrong.account.token, { answer: 'confirmed' });

  const { response, payload } = await call('DELETE', `/training/${record.id}/trainees/${ids[0]}`, sender.token);
  assert.strictEqual(response.status, 200);
  assert.deepStrictEqual(payload.trainingRecord.trainees.map((t) => t.employeeId), [right.employee.id]);
  assert.strictEqual(payload.trainingRecord.confirmedCount, 0);
  const { rows: gone } = await pool.query('SELECT 1 FROM training_trainees WHERE id = $1', [ids[0]]);
  assert.strictEqual(gone.length, 0);

  const { rows } = await pool.query(
    `SELECT operation, changed_by FROM audit_log
      WHERE table_name = 'training_trainees' AND record_id = $1 AND operation = 'DELETE'`,
    [ids[0]]
  );
  assert.strictEqual(rows.length, 1);
  assert.strictEqual(String(rows[0].changed_by), String(sender.id));
});

test('removing from a sent record: unknown record 404, unknown or foreign Trainee 404, outside the Grants 403', async () => {
  const mine = await insertTrainee();
  const { record, ids } = await sentRecord([mine]);
  const other = await sentRecord([await insertTrainee()]);

  assert.strictEqual((await call('DELETE', `/training/999999999/trainees/${ids[0]}`, admin.token)).response.status, 404);
  assert.strictEqual((await call('DELETE', `/training/${record.id}/trainees/999999999`, sender.token)).response.status, 404);
  assert.strictEqual((await call('DELETE', `/training/${record.id}/trainees/${other.ids[0]}`, sender.token)).response.status, 404);
  for (const caller of [reader, viewer]) {
    const { response, payload } = await call('DELETE', `/training/${record.id}/trainees/${ids[0]}`, caller.token);
    assert.strictEqual(response.status, 403);
    assert.strictEqual(payload.message, "Outside the caller's granted Org Units");
  }
  const read = await call('GET', `/training/${record.id}`, sender.token);
  assert.strictEqual(read.payload.trainingRecord.traineeCount, 1);
});

test('a draft is discarded with its Trainees (204), audited; the record is then a 404', async () => {
  const employee = await insertNamedEmployee();
  const record = await completeDraft([employee]);
  const traineeId = await traineeRowId(record.id, employee.id);

  const { response } = await call('DELETE', `/training/${record.id}`, sender.token);
  assert.strictEqual(response.status, 204);
  assert.strictEqual((await call('GET', `/training/${record.id}`, admin.token)).response.status, 404);
  const { rows: left } = await pool.query('SELECT 1 FROM training_trainees WHERE training_record_id = $1', [record.id]);
  assert.strictEqual(left.length, 0);

  const { rows } = await pool.query(
    `SELECT operation, changed_by FROM audit_log
      WHERE table_name = 'training_records' AND record_id = $1 AND operation = 'DELETE'`,
    [record.id]
  );
  assert.strictEqual(rows.length, 1);
  assert.strictEqual(String(rows[0].changed_by), String(sender.id));
  const { rows: traineeRows } = await pool.query(
    `SELECT changed_by FROM audit_log
      WHERE table_name = 'training_trainees' AND record_id = $1 AND operation = 'DELETE'`,
    [traineeId]
  );
  assert.strictEqual(traineeRows.length, 1);
  assert.strictEqual((await call('DELETE', `/training/${record.id}`, sender.token)).response.status, 404);
});

test('a sent record is never deleted: 409 in the Module\'s words, and it and its Trainees are kept', async () => {
  const mine = await insertTrainee();
  const { record } = await sentRecord([mine]);

  const { response, payload } = await call('DELETE', `/training/${record.id}`, sender.token);
  assert.strictEqual(response.status, 409);
  assert.match(payload.message, /sent Training record/);
  const admins = await call('DELETE', `/training/${record.id}`, admin.token);
  assert.strictEqual(admins.response.status, 409);

  const read = await call('GET', `/training/${record.id}`, reader.token);
  assert.strictEqual(read.payload.trainingRecord.traineeCount, 1);
});

test('discarding refuses in order: unknown record 404, outside the Grants 403 (a draft and a sent record alike)', async () => {
  const draft = await draftRecord();
  const { record: sent } = await sentRecord([await insertTrainee()]);

  assert.strictEqual((await call('DELETE', '/training/999999999', admin.token)).response.status, 404);
  assert.strictEqual((await call('DELETE', '/training/abc', admin.token)).response.status, 404);
  for (const id of [draft.id, sent.id]) {
    for (const caller of [reader, viewer]) {
      const { response, payload } = await call('DELETE', `/training/${id}`, caller.token);
      assert.strictEqual(response.status, 403);
      assert.strictEqual(payload.message, "Outside the caller's granted Org Units");
    }
  }
  assert.strictEqual((await call('GET', `/training/${draft.id}`, sender.token)).response.status, 200);
});
