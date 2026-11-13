/*
 * ADR-0061 slice 8 (issue #528): the last three doors outside Production that
 * answered with the legacy `requireAdmin` role comparison now ask a permission
 * code — `MTN_PARTS_CHANGE` on `POST /api/maintenance/parts`, and
 * `ADM_ACCOUNTS_DISPLAY` on `GET /api/people/accounts` and
 * `/accounts/pending`.
 *
 * Why this file exists. Two of the three are a pure rename: the code is seeded
 * on `ROLE_ADMIN` alone, so every Accounts suite that inserts `role: 'admin'`
 * would stay green whether the gate asked the code or the role, and nothing in
 * the suite would notice the swap not happening. The third is the opposite
 * problem: gating `POST /parts` with `MTN_PARTS_CHANGE` *widens* the write to
 * engineer and manager, so inventory.test.js — which posts parts as an
 * administrator — cannot tell a swapped gate from an unswapped one either.
 *
 * So the three claims are measured here over HTTP against a real database and a
 * real local session, one Account per role that would notice:
 *
 *   1. the seed itself: `ADM_ACCOUNTS_DISPLAY` on `ROLE_ADMIN` alone (the
 *      rename is exact), `MTN_PARTS_CHANGE` on engineer, manager and
 *      administrator (the widening, stated);
 *   2. an administrator reaches all three — the door did not close on the role
 *      that used to be the only one through it;
 *   3. an engineer defines a Part (201 — the widening, proved) and is refused
 *      both Accounts reads with `PERMISSION_REQUIRED` naming
 *      `ADM_ACCOUNTS_DISPLAY` (the rename, proved not to have widened the
 *      read);
 *   4. a supervisor is refused all three, and the refusal names the code rather
 *      than the role.
 *
 * Set DATABASE_URL first — see the README's Tests section. Needs every
 * migration applied, including 1803400000000_permissions-and-roles.js.
 */

const test = require('node:test');
const assert = require('node:assert');
const { tokenFor } = require('../helpers/session');

let server;
let base;
let pool;
let closePool;

const insertedAccountIds = [];
const insertedPartIds = [];

let counter = 0;
function uniqueCode(prefix) {
  counter += 1;
  return `${prefix}${process.pid}${counter}`;
}

async function authHeader(subject) {
  const token = await tokenFor(subject);
  return { authorization: 'Bearer ' + token };
}

async function insertAccount({ role }) {
  const subject = uniqueCode('s8acct');
  const { rows: [account] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status)
     VALUES ($1, 'Slice Eight Permission Test Account', $2, $3, TRUE, 'approved') RETURNING id`,
    [`${subject}@example.com`, role, subject]
  );
  insertedAccountIds.push(account.id);
  return { id: account.id, role, token: await authHeader(subject) };
}

async function call(token, path, { method = 'GET', body } = {}) {
  const response = await fetch(`${base}${path}`, {
    method,
    headers: {
      ...token,
      ...(body === undefined ? {} : { 'content-type': 'application/json' })
    },
    body: body === undefined ? undefined : JSON.stringify(body)
  });
  return { status: response.status, body: await response.json().catch(() => null) };
}

// A Part the catalogue accepts: the unit of measure has to exist and be active,
// and `EA` is seeded by the first inventory migration.
async function definePart(token) {
  const result = await call(token, '/api/maintenance/parts', {
    method: 'POST',
    body: {
      partNo: uniqueCode('S8-P'),
      description: 'Slice eight permission test part',
      uomCode: 'EA'
    }
  });
  if (result.body?.part?.id) insertedPartIds.push(result.body.part.id);
  return result;
}

// Every refusal this slice can produce is this shape: the stable `code`, the
// permission that would have opened the door, and a sentence that names the
// code rather than a role.
function assertPermissionRefused(result, permission, what) {
  assert.strictEqual(result.status, 403, `${what}: expected 403, got ${result.status} ${JSON.stringify(result.body)}`);
  assert.strictEqual(result.body?.code, 'PERMISSION_REQUIRED', `${what}: ${JSON.stringify(result.body)}`);
  assert.strictEqual(result.body?.permission, permission, `${what}: ${JSON.stringify(result.body)}`);
}

test.before(async () => {
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
});

test.after(async () => {
  await pool.query('DELETE FROM parts WHERE id = ANY($1)', [insertedPartIds]);
  await pool.query('DELETE FROM account_sessions WHERE app_user_id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM app_users WHERE id = ANY($1)', [insertedAccountIds]);
  await new Promise((resolve) => server.close(resolve));
  await closePool();
});

// ---------------------------------------------------------------------------
// The seed: one pure rename, one widening.
// ---------------------------------------------------------------------------

test('the seed carries ADM_ACCOUNTS_DISPLAY on administrators alone and MTN_PARTS_CHANGE on three roles', async () => {
  const { rows } = await pool.query(
    `SELECT r.code, p.permission_code
       FROM app_roles r
       JOIN app_role_permissions p ON p.app_role_id = r.id
      WHERE p.permission_code IN ('ADM_ACCOUNTS_DISPLAY', 'MTN_PARTS_CHANGE')
      ORDER BY p.permission_code, r.code`
  );

  const accountsDisplay = rows
    .filter((row) => row.permission_code === 'ADM_ACCOUNTS_DISPLAY')
    .map((row) => row.code);
  const partsChange = rows
    .filter((row) => row.permission_code === 'MTN_PARTS_CHANGE')
    .map((row) => row.code);

  // The rename is exact: `requireAdmin` admitted administrators only, and the
  // code admits exactly that set, so no caller's answer changes.
  assert.deepStrictEqual(accountsDisplay, ['ROLE_ADMIN']);
  // The widening is real, and it is the seed's declaration that an engineer
  // maintains Part master data — not a decision this slice invented.
  assert.deepStrictEqual(partsChange, ['ROLE_ADMIN', 'ROLE_ENGINEER', 'ROLE_MANAGER']);
});

// ---------------------------------------------------------------------------
// The administrator: the role that used to be the only one through all three.
// ---------------------------------------------------------------------------

test('an administrator reads both Accounts lists and defines a Part', async () => {
  const admin = await insertAccount({ role: 'admin' });

  const accounts = await call(admin.token, '/api/people/accounts');
  assert.strictEqual(accounts.status, 200, JSON.stringify(accounts.body));
  assert.ok(Array.isArray(accounts.body.accounts));

  const pending = await call(admin.token, '/api/people/accounts/pending');
  assert.strictEqual(pending.status, 200, JSON.stringify(pending.body));
  assert.ok(Array.isArray(pending.body.accounts));

  const part = await definePart(admin.token);
  assert.strictEqual(part.status, 201, JSON.stringify(part.body));
  assert.ok(part.body.part.id);
});

// ---------------------------------------------------------------------------
// The engineer: widened on the write, still refused the reads.
// ---------------------------------------------------------------------------

test('an engineer defines a Part and is refused both Accounts reads', async () => {
  const engineer = await insertAccount({ role: 'engineer' });

  // The widening, proved: `requireAdmin` answered this route 403 for an
  // engineer, and the seed says an engineer maintains Part master data.
  const part = await definePart(engineer.token);
  assert.strictEqual(part.status, 201, JSON.stringify(part.body));

  const accounts = await call(engineer.token, '/api/people/accounts');
  assertPermissionRefused(accounts, 'ADM_ACCOUNTS_DISPLAY', 'engineer GET /api/people/accounts');

  const pending = await call(engineer.token, '/api/people/accounts/pending');
  assertPermissionRefused(pending, 'ADM_ACCOUNTS_DISPLAY', 'engineer GET /api/people/accounts/pending');
});

// ---------------------------------------------------------------------------
// The supervisor: the role the widening did NOT reach.
// ---------------------------------------------------------------------------

test('a supervisor is refused all three doors, each refusal naming its code', async () => {
  const supervisor = await insertAccount({ role: 'supervisor' });

  const part = await definePart(supervisor.token);
  assertPermissionRefused(part, 'MTN_PARTS_CHANGE', 'supervisor POST /api/maintenance/parts');

  const accounts = await call(supervisor.token, '/api/people/accounts');
  assertPermissionRefused(accounts, 'ADM_ACCOUNTS_DISPLAY', 'supervisor GET /api/people/accounts');

  const pending = await call(supervisor.token, '/api/people/accounts/pending');
  assertPermissionRefused(pending, 'ADM_ACCOUNTS_DISPLAY', 'supervisor GET /api/people/accounts/pending');
});
