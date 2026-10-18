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

async function insertAccount({ role = 'supervisor' } = {}) {
  const subject = uniqueCode('trn');
  const { rows: [row] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status)
     VALUES ($1, 'Training Test Account', $2, $3, TRUE, 'approved') RETURNING id`,
    [`${subject}@example.com`, role, subject]
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
  await pool.query(`UPDATE training_records SET status = 'sent' WHERE id = $1`, [id]);

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

test('a draft\'s own facts are corrected, and unnamed facts are left alone', async () => {
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

  const cleared = await call('PATCH', `/training/${id}`, sender.token, { trainerEmployeeId: null });
  assert.strictEqual(cleared.payload.trainingRecord.trainerEmployeeId, null);
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
  assert.strictEqual((await call('PATCH', `/training/${id}`, sender.token, { trainerEmployeeId: '999999999' })).response.status, 404);
});

test('the Org Unit of a record is not correctable', async () => {
  const { payload } = await raise(sender.token, line.id);
  const id = payload.trainingRecord.id;
  const { response } = await call('PATCH', `/training/${id}`, sender.token, { orgUnitId: cell.id });
  assert.strictEqual(response.status, 400);
});

test('a sent record\'s own facts cannot be changed here: 409 saying to correct it instead', async () => {
  const { payload } = await raise(sender.token, line.id, { title: 'Sent and fixed' });
  const id = payload.trainingRecord.id;
  await pool.query(`UPDATE training_records SET status = 'sent' WHERE id = $1`, [id]);

  const { response, payload: refusal } = await call('PATCH', `/training/${id}`, sender.token, { title: 'Changed' });
  assert.strictEqual(response.status, 409);
  assert.match(refusal.message, /correct it instead/);

  const after = await call('GET', `/training/${id}`, sender.token);
  assert.strictEqual(after.payload.trainingRecord.title, 'Sent and fixed');
});

test('a caller outside the Grants is refused 403 on a sent record before the 409', async () => {
  const { payload } = await raise(sender.token, line.id);
  const id = payload.trainingRecord.id;
  await pool.query(`UPDATE training_records SET status = 'sent' WHERE id = $1`, [id]);
  const { response } = await call('PATCH', `/training/${id}`, reader.token, { title: 'x' });
  assert.strictEqual(response.status, 403);
});
