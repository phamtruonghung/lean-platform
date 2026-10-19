/*
 * An Employee keeps a Signature, over HTTP (issue #317, ADR-0052), against a
 * real database and a real (locally issued) JWKS - the same seam as
 * plant.test.js (see that file's own header, and the README's Tests section).
 *
 * This file does not truncate any table another file shares: it inserts its
 * own `employees` and `app_users` rows and deletes them again, with the
 * `employee_signatures` rows beneath them, in `test.after()` in foreign-key
 * order. The audit rows its writes leave behind are left in `audit_log`, as
 * every other integration file leaves its own.
 *
 * The images are built by hand in this file (PNG signature, IHDR, IDAT, IEND,
 * CRCs from node:zlib) so the test needs no image dependency, as the server
 * has none.
 *
 * Needs a database with every migration applied. Set DATABASE_URL first.
 */

const test = require('node:test');
const assert = require('node:assert');
const zlib = require('node:zlib');
const { createTestJwks } = require('../helpers/jwks');

const ISSUER = 'https://example.supabase.co/auth/v1';
const AUDIENCE = 'authenticated';

let jwks;
let server;
let base;
let pool;
let closePool;
let ownerToken;
let ownerAccountId;
let ownerEmployeeId;
let unlinkedToken;

const insertedAccountIds = [];
const insertedEmployeeIds = [];
const insertedRecordIds = [];
const insertedOrgUnitIds = [];
const insertedSiteIds = [];
const insertedDeviceIds = [];

function crc32(bytes) {
  return zlib.crc32(bytes);
}

function chunk(type, data) {
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type, 'latin1'), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body));
  return Buffer.concat([length, body, crc]);
}

// A real, decodable RGBA PNG of the given size: fully transparent, except for
// `marker` written into the first pixel so two images differ byte for byte.
function makePng(width, height, marker = 0) {
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width, 0);
  header.writeUInt32BE(height, 4);
  header[8] = 8; // bit depth
  header[9] = 6; // RGBA
  const rowLength = 1 + width * 4;
  const raw = Buffer.alloc(rowLength * height);
  raw[1] = marker;
  raw[4] = marker === 0 ? 0 : 255;
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', header),
    chunk('IDAT', zlib.deflateSync(raw)),
    chunk('IEND', Buffer.alloc(0))
  ]);
}

// A PNG padded with an ancillary chunk of random bytes to reach `size`.
function makePngOfSize(size) {
  const plain = makePng(60, 20, 1);
  const padding = chunk('tEXt', require('node:crypto').randomBytes(size - plain.length - 12));
  const iend = plain.subarray(plain.length - 12);
  return Buffer.concat([plain.subarray(0, plain.length - 12), padding, iend]);
}

async function signToken(subject) {
  return jwks.signToken(
    { sub: subject, email: `${subject}@example.com` },
    { issuer: ISSUER, audience: AUDIENCE }
  );
}

async function authHeader(subject) {
  return { authorization: `Bearer ${await signToken(subject)}` };
}

async function putSignature(headers, body) {
  return fetch(`${base}/api/people/me/signature`, {
    method: 'PUT',
    headers: { ...headers, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
}

async function getSignature(headers) {
  return fetch(`${base}/api/people/me/signature`, { headers });
}

async function deleteSignature(headers) {
  return fetch(`${base}/api/people/me/signature`, { method: 'DELETE', headers });
}

async function insertAccount(subject, employeeId) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, employee_id)
     VALUES ($1, 'Signature Test', 'operator', $2, TRUE, $3) RETURNING id`,
    [`${subject}@example.com`, subject, employeeId]
  );
  insertedAccountIds.push(row.id);
  return row.id;
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

  const { rows: [employee] } = await pool.query(
    `INSERT INTO employees (employee_no, first_name, last_name, is_active)
     VALUES ($1, 'Sig', 'Owner', TRUE) RETURNING id`,
    [`SIG${process.pid}`]
  );
  ownerEmployeeId = employee.id;
  insertedEmployeeIds.push(employee.id);

  const ownerSubject = `sig-owner-${process.pid}`;
  const unlinkedSubject = `sig-unlinked-${process.pid}`;
  ownerAccountId = await insertAccount(ownerSubject, employee.id);
  await insertAccount(unlinkedSubject, null);
  ownerToken = await authHeader(ownerSubject);
  unlinkedToken = await authHeader(unlinkedSubject);
});

test.after(async () => {
  await pool.query('DELETE FROM training_trainees WHERE training_record_id = ANY($1)', [insertedRecordIds]);
  await pool.query('DELETE FROM training_records WHERE id = ANY($1)', [insertedRecordIds]);
  await pool.query('DELETE FROM app_user_org_units WHERE app_user_id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM employee_signatures WHERE employee_id = ANY($1)', [insertedEmployeeIds]);
  await pool.query('DELETE FROM technician_identifications WHERE floor_device_id = ANY($1)', [insertedDeviceIds]);
  await pool.query('DELETE FROM employee_floor_credentials WHERE employee_id = ANY($1)', [insertedEmployeeIds]);
  await pool.query('DELETE FROM floor_devices WHERE id = ANY($1)', [insertedDeviceIds]);
  await pool.query('DELETE FROM app_users WHERE id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM employees WHERE id = ANY($1)', [insertedEmployeeIds]);
  await pool.query('DELETE FROM org_units WHERE id = ANY($1)', [insertedOrgUnitIds]);
  await pool.query('DELETE FROM sites WHERE id = ANY($1)', [insertedSiteIds]);
  await new Promise((resolve) => server.close(resolve));
  await closePool();
  await jwks.close();
});

async function rowsFor(employeeId) {
  const { rows } = await pool.query(
    `SELECT id, image, origin, kept, superseded_at, set_by_account_id
       FROM employee_signatures WHERE employee_id = $1 ORDER BY id`,
    [employeeId]
  );
  return rows;
}

test.beforeEach(async () => {
  await pool.query('DELETE FROM training_trainees WHERE training_record_id = ANY($1)', [insertedRecordIds]);
  await pool.query('DELETE FROM employee_signatures WHERE employee_id = ANY($1)', [insertedEmployeeIds]);
});

test('PUT /me/signature refuses a body with no image', async () => {
  const response = await putSignature(ownerToken, {});
  assert.strictEqual(response.status, 400);
  assert.match((await response.json()).message, /image is required/);
});

test('PUT /me/signature refuses bytes that are not a PNG', async () => {
  const response = await putSignature(ownerToken, { image: Buffer.from('this is not a png at all, just text').toString('base64') });
  assert.strictEqual(response.status, 400);
  assert.match((await response.json()).message, /must be a PNG/);
});

test('PUT /me/signature refuses a PNG over 48 KiB', async () => {
  const big = makePngOfSize(48 * 1024 + 1);
  const response = await putSignature(ownerToken, { image: big.toString('base64') });
  assert.strictEqual(response.status, 400);
  assert.match((await response.json()).message, /too large/);
  assert.strictEqual((await rowsFor(ownerEmployeeId)).length, 0);
});

test('PUT /me/signature accepts a PNG of exactly 48 KiB', async () => {
  const exact = makePngOfSize(48 * 1024);
  const response = await putSignature(ownerToken, { image: exact.toString('base64') });
  assert.strictEqual(response.status, 200);
});

test('PUT /me/signature refuses a PNG outside the normalised box', async () => {
  for (const [width, height] of [[601, 100], [100, 301], [0, 0]]) {
    const png = makePng(Math.max(width, 1), Math.max(height, 1));
    if (width === 0) {
      png.writeUInt32BE(0, 16); // a declared width of zero, CRC aside
    }
    const response = await putSignature(ownerToken, { image: png.toString('base64') });
    assert.strictEqual(response.status, 400, `${width} x ${height}`);
    assert.match((await response.json()).message, /fits inside 600 x 300/);
  }
  assert.strictEqual((await rowsFor(ownerEmployeeId)).length, 0);
});

test('PUT /me/signature refuses an origin that is not upload or on_screen', async () => {
  const response = await putSignature(ownerToken, { image: makePng(60, 20).toString('base64'), origin: 'scan' });
  assert.strictEqual(response.status, 400);
});

test('GET /me/signature answers the exact bytes that were kept, as image/png', async () => {
  const png = makePng(120, 40, 9);
  const put = await putSignature(ownerToken, { image: png.toString('base64') });
  assert.strictEqual(put.status, 200);

  const response = await getSignature(ownerToken);
  assert.strictEqual(response.status, 200);
  assert.strictEqual(response.headers.get('content-type'), 'image/png');
  assert.ok(Buffer.from(await response.arrayBuffer()).equals(png));

  const [row] = await rowsFor(ownerEmployeeId);
  assert.strictEqual(row.origin, 'upload');
  assert.strictEqual(String(row.set_by_account_id), String(ownerAccountId));
});

test('a drawn Signature is kept with origin on_screen', async () => {
  const response = await putSignature(ownerToken, { image: makePng(80, 30, 3).toString('base64'), origin: 'on_screen' });
  assert.strictEqual(response.status, 200);
  const [row] = await rowsFor(ownerEmployeeId);
  assert.strictEqual(row.origin, 'on_screen');
});

test('a second PUT supersedes the first: GET answers the second and the first row is unchanged', async () => {
  const first = makePng(100, 30, 1);
  const second = makePng(100, 30, 2);
  assert.strictEqual((await putSignature(ownerToken, { image: first.toString('base64') })).status, 200);
  assert.strictEqual((await putSignature(ownerToken, { image: second.toString('base64') })).status, 200);

  const response = await getSignature(ownerToken);
  assert.ok(Buffer.from(await response.arrayBuffer()).equals(second));

  const rows = await rowsFor(ownerEmployeeId);
  assert.strictEqual(rows.length, 2);
  assert.ok(rows[0].image.equals(first), 'the superseded row still holds its own image');
  assert.notStrictEqual(rows[0].superseded_at, null);
  assert.ok(rows[1].image.equals(second));
  assert.strictEqual(rows[1].superseded_at, null);
});

test('DELETE /me/signature supersedes rather than deletes, and the audit trail shows it', async () => {
  // Row ids can repeat across runs against a re-migrated database while the
  // audit trail is never truncated, so only entries written from here on count.
  const { rows: [{ mark }] } = await pool.query('SELECT coalesce(max(id), 0) AS mark FROM audit_log');
  const png = makePng(100, 30, 5);
  await putSignature(ownerToken, { image: png.toString('base64') });
  const [kept] = await rowsFor(ownerEmployeeId);

  const response = await deleteSignature(ownerToken);
  assert.strictEqual(response.status, 204);
  assert.strictEqual((await getSignature(ownerToken)).status, 404);

  const rows = await rowsFor(ownerEmployeeId);
  assert.strictEqual(rows.length, 1);
  assert.ok(rows[0].image.equals(png));
  assert.notStrictEqual(rows[0].superseded_at, null);

  const { rows: audit } = await pool.query(
    `SELECT operation, changed_by FROM audit_log
      WHERE table_name = 'employee_signatures' AND record_id = $1 AND id > $2 ORDER BY id`,
    [kept.id, mark]
  );
  assert.deepStrictEqual(audit.map((r) => r.operation), ['INSERT', 'UPDATE']);
  assert.strictEqual(String(audit[1].changed_by), String(ownerAccountId));
});

test('with no current Signature, GET and DELETE answer 404', async () => {
  const get = await getSignature(ownerToken);
  assert.strictEqual(get.status, 404);
  assert.match((await get.json()).message, /Signature not found/);
  assert.strictEqual((await deleteSignature(ownerToken)).status, 404);
});

test('an Account linked to no Employee has no Signature: GET, PUT and DELETE answer 404', async () => {
  const get = await getSignature(unlinkedToken);
  assert.strictEqual(get.status, 404);
  assert.match((await get.json()).message, /Employee/);
  const put = await putSignature(unlinkedToken, { image: makePng(60, 20).toString('base64') });
  assert.strictEqual(put.status, 404);
  assert.strictEqual((await deleteSignature(unlinkedToken)).status, 404);
});

test('the Signature routes need a signed-in Account', async () => {
  assert.strictEqual((await getSignature({})).status, 401);
});


// ---------------------------------------------------------------------------
// A Trainee's answer carries their Signature (issue #318, ADR-0052).
// ---------------------------------------------------------------------------

let answerSeq = 0;

// A sent Training record at a fresh Site with the owner as its Trainee; the
// fixtures go in by SQL because the behaviour under test is the answer.
async function sentRecordWithOwner() {
  answerSeq += 1;
  const code = `SG${process.pid}${answerSeq}`;
  const { rows: [site] } = await pool.query(
    `INSERT INTO sites (code, name, timezone) VALUES ($1, 'Signature Site', 'Asia/Ho_Chi_Minh') RETURNING id`,
    [code]
  );
  insertedSiteIds.push(site.id);
  const { rows: [unit] } = await pool.query(
    `INSERT INTO org_units (site_id, code, name, unit_type) VALUES ($1, $2, 'Signature Line', 'area') RETURNING id`,
    [site.id, code]
  );
  insertedOrgUnitIds.push(unit.id);
  const { rows: [record] } = await pool.query(
    `INSERT INTO training_records (site_id, org_unit_id, number, title, trained_on, duration_hours,
                                   status, sent_at, sent_by_account_id)
     VALUES ($1, $2, $3, 'Signature refresher', '2026-03-10', 1, 'sent', now(), $4) RETURNING id`,
    [site.id, unit.id, code, ownerAccountId]
  );
  insertedRecordIds.push(record.id);
  const { rows: [trainee] } = await pool.query(
    `INSERT INTO training_trainees (training_record_id, employee_id) VALUES ($1, $2) RETURNING id`,
    [record.id, ownerEmployeeId]
  );
  return { recordId: record.id, traineeId: trainee.id, orgUnitId: unit.id };
}

async function answer(traineeId, headers, body) {
  return fetch(`${base}/api/people/training/trainees/${traineeId}/answer`, {
    method: 'POST',
    headers: { ...headers, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
}

async function readTrainee(recordId, traineeId, headers = ownerToken) {
  const response = await fetch(`${base}/api/people/training/${recordId}`, { headers });
  const { trainingRecord } = await response.json();
  return trainingRecord.trainees.find((t) => t.id === traineeId);
}

async function traineeImage(traineeId, headers = ownerToken) {
  return fetch(`${base}/api/people/training/trainees/${traineeId}/signature`, { headers });
}

async function insertOtherAccount(prefix, { role = 'operator', employeeId = null } = {}) {
  const subject = `${prefix}-${process.pid}`;
  const { rows: [row] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status, employee_id)
     VALUES ($1, 'Signature Other', $2, $3, TRUE, 'approved', $4) RETURNING id`,
    [`${subject}@example.com`, role, subject, employeeId]
  );
  insertedAccountIds.push(row.id);
  return { id: row.id, headers: await authHeader(subject) };
}

test('an answer carries the three forms of Signature and the record reads back which', async () => {
  const stored = makePng(100, 30, 11);
  const drawn = makePng(100, 30, 22);
  await putSignature(ownerToken, { image: stored.toString('base64') });

  const a = await sentRecordWithOwner();
  assert.strictEqual((await answer(a.traineeId, ownerToken, { answer: 'confirmed' })).status, 200);
  let t = await readTrainee(a.recordId, a.traineeId);
  assert.strictEqual(t.signatureAppliedAs, null);
  assert.strictEqual(t.hasSignature, false);
  assert.strictEqual((await traineeImage(a.traineeId)).status, 404);

  assert.strictEqual(
    (await answer(a.traineeId, ownerToken, { answer: 'confirmed', signature: { use: 'stored' } })).status,
    200
  );
  t = await readTrainee(a.recordId, a.traineeId);
  assert.strictEqual(t.signatureAppliedAs, 'stored');
  assert.strictEqual(t.hasSignature, true);
  assert.ok(!('image' in t) && !('signatureId' in t));

  const b = await sentRecordWithOwner();
  const res = await answer(b.traineeId, ownerToken, {
    answer: 'confirmed',
    signature: { image: drawn.toString('base64') }
  });
  assert.strictEqual(res.status, 200);
  t = await readTrainee(b.recordId, b.traineeId);
  assert.strictEqual(t.signatureAppliedAs, 'drawn');
  assert.strictEqual(t.hasSignature, true);
});

test('stored with no kept Signature is a 400 in the Module\'s own words and records nothing', async () => {
  const a = await sentRecordWithOwner();
  const res = await answer(a.traineeId, ownerToken, { answer: 'confirmed', signature: { use: 'stored' } });
  assert.strictEqual(res.status, 400);
  assert.match((await res.json()).message, /no Signature kept/);
  const t = await readTrainee(a.recordId, a.traineeId);
  assert.strictEqual(t.answer, null);
});

test('a declined answer carrying a signature is a 400', async () => {
  await putSignature(ownerToken, { image: makePng(100, 30, 3).toString('base64') });
  const a = await sentRecordWithOwner();
  for (const signature of [{ use: 'stored' }, { image: makePng(60, 20).toString('base64') }]) {
    const res = await answer(a.traineeId, ownerToken, { answer: 'declined', signature });
    assert.strictEqual(res.status, 400);
  }
  assert.strictEqual((await readTrainee(a.recordId, a.traineeId)).answer, null);
});

test('an inline image gets the same four refusals as keeping a Signature', async () => {
  const a = await sentRecordWithOwner();
  const send = (image) => answer(a.traineeId, ownerToken, { answer: 'confirmed', signature: { image } });
  assert.strictEqual((await send('')).status, 400);
  assert.strictEqual((await send(Buffer.from('not a png at all, just text bytes').toString('base64'))).status, 400);
  assert.strictEqual((await send(makePngOfSize(48 * 1024 + 1).toString('base64'))).status, 400);
  assert.strictEqual((await send(makePng(601, 20).toString('base64'))).status, 400);
  assert.strictEqual((await answer(a.traineeId, ownerToken, { answer: 'confirmed', signature: { use: 'other' } })).status, 400);
  assert.strictEqual((await rowsFor(ownerEmployeeId)).length, 0);
});

test('a second answer replaces the applied Signature, and answering without one clears it', async () => {
  const first = makePng(100, 30, 31);
  const second = makePng(100, 30, 32);
  const a = await sentRecordWithOwner();
  await answer(a.traineeId, ownerToken, { answer: 'confirmed', signature: { image: first.toString('base64') } });
  assert.ok(Buffer.from(await (await traineeImage(a.traineeId)).arrayBuffer()).equals(first));

  await answer(a.traineeId, ownerToken, { answer: 'confirmed', signature: { image: second.toString('base64') } });
  assert.ok(Buffer.from(await (await traineeImage(a.traineeId)).arrayBuffer()).equals(second));

  await answer(a.traineeId, ownerToken, { answer: 'confirmed' });
  let t = await readTrainee(a.recordId, a.traineeId);
  assert.strictEqual(t.signatureAppliedAs, null);
  assert.strictEqual(t.hasSignature, false);

  await answer(a.traineeId, ownerToken, { answer: 'confirmed', signature: { image: first.toString('base64') } });
  await answer(a.traineeId, ownerToken, { answer: 'declined' });
  t = await readTrainee(a.recordId, a.traineeId);
  assert.strictEqual(t.answer, 'declined');
  assert.strictEqual(t.signatureAppliedAs, null);
  assert.strictEqual((await traineeImage(a.traineeId)).status, 404);
});

test('an inline image makes a one-off row, kept = FALSE, that supersedes nothing', async () => {
  const stored = makePng(100, 30, 41);
  await putSignature(ownerToken, { image: stored.toString('base64') });
  const a = await sentRecordWithOwner();
  await answer(a.traineeId, ownerToken, {
    answer: 'confirmed',
    signature: { image: makePng(100, 30, 42).toString('base64') }
  });
  const rows = await rowsFor(ownerEmployeeId);
  assert.strictEqual(rows.length, 2);
  assert.strictEqual(rows[0].kept, true);
  assert.strictEqual(rows[0].superseded_at, null);
  assert.strictEqual(rows[1].kept, false);
  assert.strictEqual(rows[1].origin, 'on_screen');
  assert.strictEqual(rows[1].superseded_at, null);
  // The kept Signature is still the one GET /me/signature answers.
  assert.ok(Buffer.from(await (await getSignature(ownerToken)).arrayBuffer()).equals(stored));
});

test('the image address answers image/png to any approved Account, and 404 where none was applied', async () => {
  const png = makePng(100, 30, 51);
  const a = await sentRecordWithOwner();
  await answer(a.traineeId, ownerToken, { answer: 'confirmed', signature: { image: png.toString('base64') } });

  const stranger = await insertOtherAccount('sig-stranger');
  const res = await traineeImage(a.traineeId, stranger.headers);
  assert.strictEqual(res.status, 200);
  assert.match(res.headers.get('content-type'), /^image\/png/);
  assert.ok(Buffer.from(await res.arrayBuffer()).equals(png));

  const b = await sentRecordWithOwner();
  const none = await traineeImage(b.traineeId, stranger.headers);
  assert.strictEqual(none.status, 404);
  assert.match((await none.json()).message, /Signature not found/);
  assert.strictEqual((await traineeImage('999999999', stranger.headers)).status, 404);
  assert.strictEqual((await traineeImage(a.traineeId, {})).status, 401);
});

test('nobody signs for a Trainee: an administrator and an edit-Grant colleague are refused', async () => {
  const png = makePng(100, 30, 61).toString('base64');
  const a = await sentRecordWithOwner();
  const admin = await insertOtherAccount('sig-admin', { role: 'admin' });
  const colleague = await insertOtherAccount('sig-colleague', { role: 'supervisor' });
  await pool.query(
    `INSERT INTO app_user_org_units (app_user_id, org_unit_id, can_write) VALUES ($1, $2, TRUE)`,
    [colleague.id, a.orgUnitId]
  );
  for (const who of [admin, colleague]) {
    const res = await answer(a.traineeId, who.headers, { answer: 'confirmed', signature: { image: png } });
    assert.strictEqual(res.status, 403);
  }
  assert.strictEqual((await rowsFor(ownerEmployeeId)).length, 0);
  assert.strictEqual((await readTrainee(a.recordId, a.traineeId)).answer, null);
});

test('a record keeps the row it was signed with after the Signature is replaced', async () => {
  const original = makePng(100, 30, 71);
  await putSignature(ownerToken, { image: original.toString('base64') });
  const a = await sentRecordWithOwner();
  await answer(a.traineeId, ownerToken, { answer: 'confirmed', signature: { use: 'stored' } });

  await putSignature(ownerToken, { image: makePng(100, 30, 72).toString('base64') });
  const rows = await rowsFor(ownerEmployeeId);
  assert.strictEqual(rows.length, 2);

  const res = await traineeImage(a.traineeId);
  assert.ok(Buffer.from(await res.arrayBuffer()).equals(original));
  const { rows: [named] } = await pool.query(
    'SELECT signature_id FROM training_trainees WHERE id = $1',
    [a.traineeId]
  );
  assert.strictEqual(String(named.signature_id), String(rows[0].id));
  assert.strictEqual((await readTrainee(a.recordId, a.traineeId)).signatureAppliedAs, 'stored');
});

test('the record reads each answer\'s Site-local day: 18:00 UTC at a UTC+7 Site is the next day', async () => {
  const a = await sentRecordWithOwner();
  await pool.query(
    `UPDATE sites SET timezone = 'Asia/Ho_Chi_Minh'
      WHERE id = (SELECT site_id FROM training_records WHERE id = $1)`,
    [a.recordId]
  );
  await answer(a.traineeId, ownerToken, { answer: 'confirmed' });
  await pool.query(
    `UPDATE training_trainees SET answered_at = '2026-05-06T18:00:00Z' WHERE id = $1`,
    [a.traineeId]
  );
  const t = await readTrainee(a.recordId, a.traineeId);
  assert.strictEqual(t.answeredOn, '2026-05-07');
  assert.strictEqual(new Date(t.answeredAt).toISOString(), '2026-05-06T18:00:00.000Z');

  const pending = await sentRecordWithOwner();
  assert.strictEqual((await readTrainee(pending.recordId, pending.traineeId)).answeredOn, null);
});


// ---------------------------------------------------------------------------
// The floor device signs the same way (issue #319, ADR-0052).
// ---------------------------------------------------------------------------

async function jsonRequest(method, path, headers, body) {
  const response = await fetch(`${base}${path}`, {
    method,
    headers: { ...headers, ...(body === undefined ? {} : { 'content-type': 'application/json' }) },
    body: body === undefined ? undefined : JSON.stringify(body)
  });
  return { status: response.status, body: await response.json().catch(() => null) };
}

let floorAdmin;

// A device registered at `orgUnitId`, and the owner identified at it. The
// owner's PIN is set through the real admin route.
async function deviceAt(orgUnitId) {
  floorAdmin ??= await insertOtherAccount('sig-floor-admin', { role: 'admin' });
  const registered = await jsonRequest('POST', '/api/maintenance/floor-devices', floorAdmin.headers, {
    orgUnitId,
    name: 'Signature terminal'
  });
  assert.strictEqual(registered.status, 201, JSON.stringify(registered.body));
  insertedDeviceIds.push(registered.body.device.id);
  const pin = await jsonRequest(
    'PUT',
    `/api/maintenance/floor-technician-credentials/${ownerEmployeeId}`,
    floorAdmin.headers,
    { pin: '4321' }
  );
  assert.strictEqual(pin.status, 200, JSON.stringify(pin.body));
  const device = { 'x-floor-device': registered.body.credential };
  const identified = await jsonRequest('POST', '/api/maintenance/floor/identify', device, {
    employeeNo: `SIG${process.pid}`,
    pin: '4321'
  });
  assert.strictEqual(identified.status, 200, JSON.stringify(identified.body));
  return { device, headers: { ...device, 'x-technician-identification': identified.body.identification } };
}

const answerAtFloor = (headers, traineeId, body) =>
  jsonRequest('POST', `/api/maintenance/floor/training/trainees/${traineeId}/answer`, headers, body);

async function floorTrainee(recordId, traineeId) {
  const { rows: [row] } = await pool.query(
    `SELECT answer, answered_by_account_id, answered_by_employee_id, signature_id, signature_applied_as
       FROM training_trainees WHERE id = $1`,
    [traineeId]
  );
  return row;
}

async function keptCount() {
  const { rows: [row] } = await pool.query(
    `SELECT count(*)::int AS n FROM employee_signatures
      WHERE employee_id = $1 AND kept AND superseded_at IS NULL`,
    [ownerEmployeeId]
  );
  return row.n;
}

test('at the device, stored reads back as stored for the acting Employee, and a stroke as drawn', async () => {
  const kept = makePng(100, 30, 81);
  await putSignature(ownerToken, { image: kept.toString('base64') });
  const a = await sentRecordWithOwner();
  const floor = await deviceAt(a.orgUnitId);

  const stored = await answerAtFloor(floor.headers, a.traineeId, { answer: 'confirmed', signature: { use: 'stored' } });
  assert.strictEqual(stored.status, 200, JSON.stringify(stored.body));
  const [shown] = stored.body.trainingRecord.trainees;
  assert.strictEqual(shown.signatureAppliedAs, 'stored');
  assert.strictEqual(shown.hasSignature, true);
  assert.strictEqual(shown.answeredVia, 'device');
  let row = await floorTrainee(a.recordId, a.traineeId);
  assert.strictEqual(String(row.answered_by_employee_id), String(ownerEmployeeId));
  assert.strictEqual(row.answered_by_account_id, null);
  const kept0 = (await rowsFor(ownerEmployeeId))[0];
  assert.strictEqual(String(row.signature_id), String(kept0.id));
  assert.ok(Buffer.from(await (await traineeImage(a.traineeId)).arrayBuffer()).equals(kept));

  const b = await sentRecordWithOwner();
  const floorB = await deviceAt(b.orgUnitId);
  const drawn = await answerAtFloor(floorB.headers, b.traineeId, {
    answer: 'confirmed',
    signature: { image: makePng(100, 30, 82).toString('base64') }
  });
  assert.strictEqual(drawn.status, 200, JSON.stringify(drawn.body));
  assert.strictEqual(drawn.body.trainingRecord.trainees[0].signatureAppliedAs, 'drawn');
  assert.strictEqual(drawn.body.trainingRecord.trainees[0].answeredVia, 'device');
  row = await floorTrainee(b.recordId, b.traineeId);
  assert.strictEqual(row.signature_applied_as, 'drawn');
  assert.strictEqual(String((await readTrainee(b.recordId, b.traineeId)).hasSignature), 'true');
});

test('at the device, an answer with no signature part carries none', async () => {
  const a = await sentRecordWithOwner();
  const floor = await deviceAt(a.orgUnitId);
  const res = await answerAtFloor(floor.headers, a.traineeId, { answer: 'confirmed' });
  assert.strictEqual(res.status, 200, JSON.stringify(res.body));
  const row = await floorTrainee(a.recordId, a.traineeId);
  assert.strictEqual(row.signature_id, null);
  assert.strictEqual(row.signature_applied_as, null);
});

test('a stroke drawn at the device supersedes nothing and leaves no kept Signature behind', async () => {
  const a = await sentRecordWithOwner();
  const floor = await deviceAt(a.orgUnitId);
  const res = await answerAtFloor(floor.headers, a.traineeId, {
    answer: 'confirmed',
    signature: { image: makePng(100, 30, 91).toString('base64') }
  });
  assert.strictEqual(res.status, 200);
  assert.strictEqual(await keptCount(), 0);
  assert.strictEqual((await jsonRequest('GET', '/api/maintenance/floor/signature', floor.headers)).status, 404);
  const [row] = await rowsFor(ownerEmployeeId);
  assert.strictEqual(row.kept, false);
  assert.strictEqual(row.origin, 'on_screen');
  assert.strictEqual(row.set_by_account_id, null);

  // With a kept Signature already there, a stroke at the device leaves it current.
  const keptImage = makePng(100, 30, 92);
  await putSignature(ownerToken, { image: keptImage.toString('base64') });
  const b = await sentRecordWithOwner();
  const floorB = await deviceAt(b.orgUnitId);
  await answerAtFloor(floorB.headers, b.traineeId, {
    answer: 'confirmed',
    signature: { image: makePng(100, 30, 93).toString('base64') }
  });
  assert.strictEqual(await keptCount(), 1);
  assert.ok(Buffer.from(await (await getSignature(ownerToken)).arrayBuffer()).equals(keptImage));
  assert.ok((await rowsFor(ownerEmployeeId)).filter((r) => r.kept).every((r) => r.superseded_at === null));
});

test('stored at the device with no kept Signature is a 400 and records nothing', async () => {
  const a = await sentRecordWithOwner();
  const floor = await deviceAt(a.orgUnitId);
  const res = await answerAtFloor(floor.headers, a.traineeId, { answer: 'confirmed', signature: { use: 'stored' } });
  assert.strictEqual(res.status, 400);
  assert.match(res.body.message, /no Signature kept/);
  assert.strictEqual((await floorTrainee(a.recordId, a.traineeId)).answer, null);
});

test('at the device, a decline carrying a signature is a 400, and an image gets the four refusals', async () => {
  await putSignature(ownerToken, { image: makePng(100, 30, 94).toString('base64') });
  const a = await sentRecordWithOwner();
  const floor = await deviceAt(a.orgUnitId);
  for (const signature of [{ use: 'stored' }, { image: makePng(60, 20).toString('base64') }]) {
    const res = await answerAtFloor(floor.headers, a.traineeId, { answer: 'declined', signature });
    assert.strictEqual(res.status, 400);
  }
  const send = (image) => answerAtFloor(floor.headers, a.traineeId, { answer: 'confirmed', signature: { image } });
  assert.strictEqual((await send('')).status, 400);
  assert.strictEqual((await send(Buffer.from('not a png at all, just text bytes').toString('base64'))).status, 400);
  assert.strictEqual((await send(makePngOfSize(48 * 1024 + 1).toString('base64'))).status, 400);
  assert.strictEqual((await send(makePng(601, 20).toString('base64'))).status, 400);
  assert.strictEqual((await floorTrainee(a.recordId, a.traineeId)).answer, null);
  assert.strictEqual((await rowsFor(ownerEmployeeId)).length, 1);
});

test('device scoping is unchanged with a signature part present', async () => {
  await putSignature(ownerToken, { image: makePng(100, 30, 95).toString('base64') });
  const body = { answer: 'confirmed', signature: { use: 'stored' } };
  const a = await sentRecordWithOwner();
  const floor = await deviceAt(a.orgUnitId);

  // Another device's identification.
  const elsewhere = await sentRecordWithOwner();
  const other = await deviceAt(elsewhere.orgUnitId);
  const crossed = { ...floor.device, 'x-technician-identification': other.headers['x-technician-identification'] };
  assert.strictEqual((await answerAtFloor(crossed, a.traineeId, body)).status, 401);

  // No identification at all.
  assert.strictEqual((await answerAtFloor(floor.device, a.traineeId, body)).status, 401);

  // An expired identification.
  await pool.query(
    `UPDATE technician_identifications SET expires_at = now() - interval '1 minute'
      WHERE floor_device_id = ANY($1)`,
    [insertedDeviceIds.slice(-2, -1)]
  );
  const expired = await answerAtFloor(floor.headers, a.traineeId, body);
  assert.strictEqual(expired.status, 401);

  // An Org Unit outside the device's reach.
  const reaching = await deviceAt(elsewhere.orgUnitId);
  assert.strictEqual((await answerAtFloor(reaching.headers, a.traineeId, body)).status, 403);

  assert.strictEqual((await floorTrainee(a.recordId, a.traineeId)).answer, null);
  assert.strictEqual((await floorTrainee(elsewhere.recordId, elsewhere.traineeId)).answer, null);
});

test('the device reads the identified Employee\'s Signature, behind its door', async () => {
  const a = await sentRecordWithOwner();
  const floor = await deviceAt(a.orgUnitId);
  assert.strictEqual((await jsonRequest('GET', '/api/maintenance/floor/signature', floor.headers)).status, 404);

  const kept = makePng(100, 30, 96);
  await putSignature(ownerToken, { image: kept.toString('base64') });
  const res = await fetch(`${base}/api/maintenance/floor/signature`, { headers: floor.headers });
  assert.strictEqual(res.status, 200);
  assert.match(res.headers.get('content-type'), /image\/png/);
  assert.ok(Buffer.from(await res.arrayBuffer()).equals(kept));

  assert.strictEqual((await jsonRequest('GET', '/api/maintenance/floor/signature', floor.device)).status, 401);
  assert.strictEqual((await jsonRequest('GET', '/api/maintenance/floor/signature', {})).status, 401);
});

test('no device route can create or supersede a kept Signature', async () => {
  const keptImage = makePng(100, 30, 97);
  await putSignature(ownerToken, { image: keptImage.toString('base64') });
  const before = await rowsFor(ownerEmployeeId);
  const a = await sentRecordWithOwner();
  const floor = await deviceAt(a.orgUnitId);
  const image = makePng(100, 30, 98).toString('base64');

  for (const path of ['/api/maintenance/floor/signature', '/api/maintenance/floor/me/signature', '/api/maintenance/floor/training/signature']) {
    for (const method of ['PUT', 'POST', 'DELETE', 'PATCH']) {
      const res = await jsonRequest(method, path, floor.headers, method === 'DELETE' ? undefined : { image });
      assert.ok(res.status === 404, `${method} ${path} answered ${res.status}`);
    }
  }

  const after = await rowsFor(ownerEmployeeId);
  assert.strictEqual(after.length, before.length);
  assert.strictEqual(await keptCount(), 1);
  assert.ok(after.every((r, i) => r.superseded_at === before[i].superseded_at));
  assert.ok(Buffer.from(await (await getSignature(ownerToken)).arrayBuffer()).equals(keptImage));
});


// ---------------------------------------------------------------------------
// An administrator sets a Signature for an Employee who cannot (issue #320).
// ---------------------------------------------------------------------------

let adminToken;
let adminAccountId;

async function insertAdmin() {
  const subject = `sig-setter-${process.pid}`;
  const { rows: [row] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active)
     VALUES ($1, 'Signature Admin', 'admin', $2, TRUE) RETURNING id`,
    [`${subject}@example.com`, subject]
  );
  insertedAccountIds.push(row.id);
  adminAccountId = row.id;
  adminToken = await authHeader(subject);
}

async function accountlessEmployee(active = true) {
  const { rows: [employee] } = await pool.query(
    `INSERT INTO employees (employee_no, first_name, last_name, is_active, terminated_on)
     VALUES ($1, 'No', 'Account', $2, $3) RETURNING id`,
    [`NA${process.pid}${insertedEmployeeIds.length}`, active, active ? null : '2024-01-01']
  );
  insertedEmployeeIds.push(employee.id);
  return employee.id;
}

function forEmployee(id, suffix = '') {
  return `${base}/api/people/employees/${id}/signature${suffix}`;
}

async function adminPut(headers, id, body) {
  return fetch(forEmployee(id), {
    method: 'PUT',
    headers: { ...headers, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
}

test('an administrator sets a Signature for an Employee with no Account and reads it back', async () => {
  if (!adminToken) await insertAdmin();
  const employeeId = await accountlessEmployee();
  const png = makePng(100, 30, 7);

  const put = await adminPut(adminToken, employeeId, { image: png.toString('base64'), origin: 'upload' });
  assert.strictEqual(put.status, 200);

  const get = await fetch(forEmployee(employeeId), { headers: adminToken });
  assert.strictEqual(get.status, 200);
  assert.strictEqual(get.headers.get('content-type'), 'image/png');
  assert.ok(Buffer.from(await get.arrayBuffer()).equals(png));

  const [row] = await rowsFor(employeeId);
  assert.strictEqual(row.kept, true);
  assert.strictEqual(String(row.set_by_account_id), String(adminAccountId));

  const details = await (await fetch(forEmployee(employeeId, '/details'), { headers: adminToken })).json();
  assert.strictEqual(details.signature.setForEmployee, true);
  assert.strictEqual(details.signature.setByName, 'Signature Admin');
  assert.strictEqual(details.signature.origin, 'upload');

  const second = makePng(100, 30, 8);
  assert.strictEqual((await adminPut(adminToken, employeeId, { image: second.toString('base64') })).status, 200);
  const rows = await rowsFor(employeeId);
  assert.strictEqual(rows.length, 2);
  assert.notStrictEqual(rows[0].superseded_at, null);
  assert.strictEqual(rows[1].superseded_at, null);
});

test('an administrator\'s write is refused the same four ways as the Employee\'s own', async () => {
  if (!adminToken) await insertAdmin();
  const employeeId = await accountlessEmployee();
  const cases = [
    [{}, /image is required/],
    [{ image: Buffer.from('this is not a png at all, just text').toString('base64') }, /must be a PNG/],
    [{ image: makePngOfSize(48 * 1024 + 1).toString('base64') }, /too large/],
    [{ image: makePng(601, 100).toString('base64') }, /fits inside 600 x 300/]
  ];
  for (const [body, message] of cases) {
    const response = await adminPut(adminToken, employeeId, body);
    assert.strictEqual(response.status, 400);
    assert.match((await response.json()).message, message);
  }
  assert.strictEqual((await rowsFor(employeeId)).length, 0);
});

test('an administrator is answered 409 once the Employee holds an Account, for PUT and DELETE', async () => {
  if (!adminToken) await insertAdmin();
  const png = makePng(100, 30, 4).toString('base64');
  const put = await adminPut(adminToken, ownerEmployeeId, { image: png });
  assert.strictEqual(put.status, 409);
  assert.match((await put.json()).message, /holds an Account of their own/);
  assert.strictEqual((await rowsFor(ownerEmployeeId)).length, 0);
  const del = await fetch(forEmployee(ownerEmployeeId), { method: 'DELETE', headers: adminToken });
  assert.strictEqual(del.status, 409);
});

test('the Employee\'s own Signature supersedes the administrator\'s, and reads as set by them', async () => {
  if (!adminToken) await insertAdmin();
  // An Employee set for first, who is then given an Account of their own.
  const employeeId = await accountlessEmployee();
  assert.strictEqual((await adminPut(adminToken, employeeId, { image: makePng(100, 30, 1).toString('base64') })).status, 200);
  const subject = `sig-later-${process.pid}`;
  await insertAccount(subject, employeeId);
  const laterToken = await authHeader(subject);

  const own = makePng(100, 30, 2);
  assert.strictEqual((await putSignature(laterToken, { image: own.toString('base64') })).status, 200);

  const rows = await rowsFor(employeeId);
  assert.strictEqual(rows.length, 2);
  assert.notStrictEqual(rows[0].superseded_at, null);
  assert.strictEqual(rows[1].superseded_at, null);
  assert.ok(Buffer.from(await (await getSignature(laterToken)).arrayBuffer()).equals(own));

  const details = await (await fetch(forEmployee(employeeId, '/details'), { headers: adminToken })).json();
  assert.strictEqual(details.signature.setForEmployee, false);
});

test('an administrator removes the Signature of an Employee with no Account, audited with the acting Account', async () => {
  if (!adminToken) await insertAdmin();
  const employeeId = await accountlessEmployee();
  const { rows: [{ mark }] } = await pool.query('SELECT coalesce(max(id), 0) AS mark FROM audit_log');
  await adminPut(adminToken, employeeId, { image: makePng(100, 30, 6).toString('base64') });
  const [kept] = await rowsFor(employeeId);

  const del = await fetch(forEmployee(employeeId), { method: 'DELETE', headers: adminToken });
  assert.strictEqual(del.status, 204);
  assert.strictEqual((await fetch(forEmployee(employeeId), { headers: adminToken })).status, 404);
  assert.strictEqual((await fetch(forEmployee(employeeId), { method: 'DELETE', headers: adminToken })).status, 404);

  const { rows: audit } = await pool.query(
    `SELECT operation, changed_by FROM audit_log
      WHERE table_name = 'employee_signatures' AND record_id = $1 AND id > $2 ORDER BY id`,
    [kept.id, mark]
  );
  assert.deepStrictEqual(audit.map((r) => r.operation), ['INSERT', 'UPDATE']);
  for (const entry of audit) assert.strictEqual(String(entry.changed_by), String(adminAccountId));
});

test('an unknown or Departed Employee is a 404 for an administrator', async () => {
  if (!adminToken) await insertAdmin();
  const png = makePng(60, 20).toString('base64');
  assert.strictEqual((await adminPut(adminToken, 2147483000, { image: png })).status, 404);
  const departed = await accountlessEmployee(false);
  assert.strictEqual((await adminPut(adminToken, departed, { image: png })).status, 404);
  assert.strictEqual((await fetch(forEmployee(departed), { method: 'DELETE', headers: adminToken })).status, 404);
  assert.strictEqual((await fetch(forEmployee(departed), { headers: adminToken })).status, 404);
});

test('a non-administrator is refused every Employee Signature route', async () => {
  if (!adminToken) await insertAdmin();
  const employeeId = await accountlessEmployee();
  const png = makePng(60, 20).toString('base64');
  assert.strictEqual((await adminPut(ownerToken, employeeId, { image: png })).status, 403);
  assert.strictEqual((await fetch(forEmployee(employeeId), { headers: ownerToken })).status, 403);
  assert.strictEqual((await fetch(forEmployee(employeeId, '/details'), { headers: ownerToken })).status, 403);
  assert.strictEqual((await fetch(forEmployee(employeeId), { method: 'DELETE', headers: ownerToken })).status, 403);
  assert.strictEqual((await rowsFor(employeeId)).length, 0);
});


// ---------------------------------------------------------------------------
// The rule holds in the database (issue #326, ADR-0053).
// ---------------------------------------------------------------------------

// Waits until some backend other than `exceptPid` is blocked on a lock inside
// a statement that touches employee_signatures. Polls pg_stat_activity rather
// than sleeping: the test proceeds only once the write is really waiting.
async function waitForBlockedSignatureWrite(exceptPid) {
  const deadline = Date.now() + 10000;
  while (Date.now() < deadline) {
    const { rows } = await pool.query(
      `SELECT 1 FROM pg_stat_activity
        WHERE wait_event_type = 'Lock' AND pid <> $1 AND pid <> pg_backend_pid()
          AND query ILIKE '%employee_signatures%'`,
      [exceptPid]
    );
    if (rows.length > 0) return;
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
  throw new Error('the administrator\'s write never blocked on the Employee row lock');
}

test('an Account linked while the administrator\'s write waits on the Employee row refuses the write with 409', async () => {
  if (!adminToken) await insertAdmin();
  const employeeId = await accountlessEmployee();
  const subject = `sig-race-${process.pid}`;

  // B holds the Employee row lock, as requireLinkableEmployee does before it
  // links an Account. A's route checks "no Account" (true: B has not linked
  // yet), then its INSERT waits on B's lock.
  const b = await pool.connect();
  try {
    await b.query('BEGIN');
    await b.query('SELECT id FROM employees WHERE id = $1 FOR UPDATE', [employeeId]);
    const { rows: [{ pid }] } = await b.query('SELECT pg_backend_pid() AS pid');

    const pending = adminPut(adminToken, employeeId, { image: makePng(100, 30, 11).toString('base64') });
    await waitForBlockedSignatureWrite(pid);

    const { rows: [account] } = await b.query(
      `INSERT INTO app_users (email, display_name, role, external_subject, is_active, employee_id)
       VALUES ($1, 'Signature Race', 'operator', $2, TRUE, $3) RETURNING id`,
      [`${subject}@example.com`, subject, employeeId]
    );
    insertedAccountIds.push(account.id);
    await b.query('COMMIT');

    const response = await pending;
    assert.strictEqual(response.status, 409);
    assert.match((await response.json()).message, /holds an Account of their own/);
  } finally {
    await b.query('ROLLBACK').catch(() => {});
    b.release();
  }
  assert.strictEqual((await rowsFor(employeeId)).length, 0);
});

test('the database refuses a kept mark with no setter or another setter for an Employee with an Account, and nothing else', async () => {
  const insert = (employeeId, kept, setBy) => pool.query(
    `INSERT INTO employee_signatures (employee_id, image, image_bytes, origin, kept, set_by_account_id)
     VALUES ($1, $2, $3, 'upload', $4, $5)`,
    [employeeId, makePng(60, 20, 3), makePng(60, 20, 3).length, kept, setBy]
  );
  if (!adminToken) await insertAdmin();
  await assert.rejects(insert(ownerEmployeeId, true, null), { code: '23514' });
  await assert.rejects(insert(ownerEmployeeId, true, adminAccountId), { code: '23514' });
  // A stroke drawn for one act is never refused, whoever (or nobody) set it.
  await insert(ownerEmployeeId, false, null);
  // The Employee's own Account may keep one; a person with no Account may be set for.
  await insert(ownerEmployeeId, true, ownerAccountId);
  await insert(await accountlessEmployee(), true, adminAccountId);
  // Superseding the current mark is not refused.
  await pool.query('UPDATE employee_signatures SET superseded_at = now() WHERE employee_id = $1 AND kept', [ownerEmployeeId]);
});

test('an Employee with an Account keeps, replaces and removes their own Signature', async () => {
  assert.strictEqual((await putSignature(ownerToken, { image: makePng(100, 30, 12).toString('base64') })).status, 200);
  assert.strictEqual((await putSignature(ownerToken, { image: makePng(100, 30, 13).toString('base64') })).status, 200);
  assert.strictEqual(await keptCount(), 1);
  assert.strictEqual((await deleteSignature(ownerToken)).status, 204);
});

test('a stroke drawn at the device for an Employee who holds an Account is still recorded as a one-off, never kept', async () => {
  const a = await sentRecordWithOwner();
  const floor = await deviceAt(a.orgUnitId);
  const res = await answerAtFloor(floor.headers, a.traineeId, {
    answer: 'confirmed',
    signature: { image: makePng(100, 30, 14).toString('base64') }
  });
  assert.strictEqual(res.status, 200);
  const rows = await rowsFor(ownerEmployeeId);
  assert.strictEqual(rows.length, 1);
  assert.strictEqual(rows[0].kept, false);
  assert.strictEqual(rows[0].set_by_account_id, null);
  assert.strictEqual((await floorTrainee(a.recordId, a.traineeId)).signature_applied_as, 'drawn');
});
