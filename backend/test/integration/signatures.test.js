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
  await pool.query('DELETE FROM employee_signatures WHERE employee_id = ANY($1)', [insertedEmployeeIds]);
  await pool.query('DELETE FROM app_users WHERE id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM employees WHERE id = ANY($1)', [insertedEmployeeIds]);
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
