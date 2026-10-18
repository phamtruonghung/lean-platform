/*
 * Signing in with an email and a password from our own database (issue #268),
 * over HTTP against a real database — the same seam as plant.test.js.
 *
 * The local-mode tests set AUTH_PASSWORD_MODE=local and restore it afterwards;
 * the app reads it per request, so nothing needs reloading. Like plant.test.js
 * this inserts its own rows (Employees, Accounts, credentials), each under a
 * value unique to this process, and deletes them in test.after(): it never
 * truncates `app_users`, which accounts.test.js's bootstrap assertion shares.
 * Sessions go with their Account (ON DELETE CASCADE).
 *
 * Needs a database with every migration applied. Set DATABASE_URL first.
 */

const test = require('node:test');
const assert = require('node:assert');
const { createTestJwks } = require('../helpers/jwks');
const { hashSecret } = require('../../src/platform/secrets');

const REFUSAL = { message: 'Email or password is not recognised.' };
const PASSWORD = 'correct horse battery';

let jwks;
let server;
let base;
let pool;
let closePool;
let previousMode;
const employeeIds = [];
const accountIds = [];

const tag = `al${process.pid}`;
const emailOf = (name) => `${tag}-${name}@example.com`;

async function makeAccount(name, { password = PASSWORD, isActive = true, approvalStatus = 'approved',
  isEnabled = true, employeeActive = true, linkEmployee = true, credential = true, subject = null } = {}) {
  let employeeId = null;
  if (linkEmployee) {
    const { rows: [employee] } = await pool.query(
      `INSERT INTO employees (employee_no, first_name, last_name, is_active)
       VALUES ($1, 'Auth', $2, $3) RETURNING id`,
      [`${tag}-${name}`, name, employeeActive]
    );
    employeeId = employee.id;
    employeeIds.push(employeeId);
  }
  const { rows: [account] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status, employee_id)
     VALUES ($1, $2, 'operator', $3, $4, $5, $6) RETURNING id`,
    [emailOf(name), `Auth ${name}`, subject, isActive, approvalStatus, employeeId]
  );
  accountIds.push(account.id);
  if (credential) {
    await pool.query(
      `INSERT INTO account_credentials (app_user_id, password_hash, is_enabled) VALUES ($1, $2, $3)`,
      [account.id, await hashSecret(password), isEnabled]
    );
  }
  return { id: account.id, employeeId, email: emailOf(name) };
}

function login(body) {
  return fetch(`${base}/api/auth/login`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
}

const bearer = (token) => ({ authorization: `Bearer ${token}` });

test.before(async () => {
  jwks = await createTestJwks();
  process.env.SUPABASE_JWKS_URL = jwks.url;
  process.env.SUPABASE_JWT_ISSUER = 'https://example.supabase.co/auth/v1';
  process.env.SUPABASE_JWT_AUDIENCE = 'authenticated';
  process.env.BACKEND_PORT = '0';
  previousMode = process.env.AUTH_PASSWORD_MODE;

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

test.beforeEach(() => {
  process.env.AUTH_PASSWORD_MODE = 'local';
});

test.after(async () => {
  if (previousMode === undefined) delete process.env.AUTH_PASSWORD_MODE;
  else process.env.AUTH_PASSWORD_MODE = previousMode;
  await pool.query('DELETE FROM app_users WHERE id = ANY($1)', [accountIds]);
  await pool.query('DELETE FROM employees WHERE id = ANY($1)', [employeeIds]);
  await new Promise((resolve) => server.close(resolve));
  await closePool();
  await jwks.close();
});

test('a correct email and password return a token that opens GET /api/people/me', async () => {
  const who = await makeAccount('success');
  const response = await login({ email: who.email, password: PASSWORD });
  assert.strictEqual(response.status, 200);
  const body = await response.json();

  assert.ok(body.token);
  assert.ok(new Date(body.expiresAt) > new Date());
  assert.deepStrictEqual(body.account, {
    id: who.id,
    email: who.email,
    displayName: 'Auth success',
    role: 'operator',
    approvalStatus: 'approved',
    employeeId: who.employeeId
  });

  const me = await fetch(`${base}/api/people/me`, { headers: bearer(body.token) });
  assert.strictEqual(me.status, 200);
  const meBody = await me.json();
  assert.strictEqual(meBody.status, 'active');
  assert.strictEqual(meBody.account.id, who.id);
  // The local Account is identified as local:<employee_no>.
  assert.strictEqual(meBody.account.externalSubject, `local:${tag}-success`);
});

test('every failure answers the identical 401 body', async () => {
  const wrong = await makeAccount('wrongpw');
  const noCred = await makeAccount('nocred', { credential: false });
  const off = await makeAccount('off', { isEnabled: false });
  const inactiveEmployee = await makeAccount('inactiveemp', { employeeActive: false });
  const noEmployee = await makeAccount('noemp', { linkEmployee: false });

  const attempts = [
    { email: emailOf('nobody'), password: PASSWORD },
    { email: wrong.email, password: 'not the password' },
    { email: noCred.email, password: PASSWORD },
    { email: off.email, password: PASSWORD },
    { email: inactiveEmployee.email, password: PASSWORD },
    { email: noEmployee.email, password: PASSWORD },
    {},
    { email: wrong.email },
    { email: 42, password: PASSWORD },
    { email: wrong.email, password: 42 }
  ];
  for (const attempt of attempts) {
    const response = await login(attempt);
    assert.strictEqual(response.status, 401, JSON.stringify(attempt));
    assert.strictEqual(await response.text(), JSON.stringify(REFUSAL), JSON.stringify(attempt));
  }
});

test('the email matches regardless of case', async () => {
  const who = await makeAccount('mixedcase');
  const response = await login({ email: who.email.toUpperCase(), password: PASSWORD });
  assert.strictEqual(response.status, 200);
});

test('the database stores only a hash of the token', async () => {
  const who = await makeAccount('hashed');
  const { token } = await (await login({ email: who.email, password: PASSWORD })).json();
  const { rows } = await pool.query('SELECT token_hash FROM account_sessions WHERE app_user_id = $1', [who.id]);
  assert.strictEqual(rows.length, 1);
  assert.notStrictEqual(rows[0].token_hash, token);
  assert.match(rows[0].token_hash, /^[0-9a-f]{64}$/);
});

test('logout revokes the session, and a second logout still succeeds', async () => {
  const who = await makeAccount('logout');
  const other = await makeAccount('logoutother');
  const { token } = await (await login({ email: who.email, password: PASSWORD })).json();
  const { token: otherToken } = await (await login({ email: other.email, password: PASSWORD })).json();

  const first = await fetch(`${base}/api/auth/logout`, { method: 'POST', headers: bearer(token) });
  assert.strictEqual(first.status, 204);
  const second = await fetch(`${base}/api/auth/logout`, { method: 'POST', headers: bearer(token) });
  assert.strictEqual(second.status, 204);

  const me = await fetch(`${base}/api/people/me`, { headers: bearer(token) });
  assert.strictEqual(me.status, 401);
  assert.deepStrictEqual(await me.json(), { message: 'Invalid or expired token' });

  // Only the caller's own session was ended.
  const otherMe = await fetch(`${base}/api/people/me`, { headers: bearer(otherToken) });
  assert.strictEqual(otherMe.status, 200);

  const unknown = await fetch(`${base}/api/auth/logout`, { method: 'POST', headers: bearer('nonsense') });
  assert.strictEqual(unknown.status, 401);
});

test('an expired session is refused', async () => {
  const who = await makeAccount('expired');
  const { token } = await (await login({ email: who.email, password: PASSWORD })).json();
  await pool.query(`UPDATE account_sessions SET expires_at = now() - interval '1 minute' WHERE app_user_id = $1`, [who.id]);
  const me = await fetch(`${base}/api/people/me`, { headers: bearer(token) });
  assert.strictEqual(me.status, 401);
});

test('a pending Account signs in, then is refused where Approval is required', async () => {
  const who = await makeAccount('pending', { isActive: false, approvalStatus: 'pending' });
  const response = await login({ email: who.email, password: PASSWORD });
  assert.strictEqual(response.status, 200);
  const body = await response.json();
  assert.strictEqual(body.account.approvalStatus, 'pending');

  const refused = await fetch(`${base}/api/people/accounts`, { headers: bearer(body.token) });
  assert.strictEqual(refused.status, 403);
  assert.strictEqual((await refused.json()).status, 'pending_approval');
});

test('GET /api/auth/mode reports the deployment mode, defaulting to supabase', async () => {
  const read = async () => (await (await fetch(`${base}/api/auth/mode`)).json()).password;

  process.env.AUTH_PASSWORD_MODE = 'local';
  assert.strictEqual(await read(), 'local');
  process.env.AUTH_PASSWORD_MODE = 'supabase';
  assert.strictEqual(await read(), 'supabase');
  delete process.env.AUTH_PASSWORD_MODE;
  assert.strictEqual(await read(), 'supabase');
});

test('with the mode unset, a local session token is not accepted', async () => {
  const who = await makeAccount('unset');
  const { token } = await (await login({ email: who.email, password: PASSWORD })).json();

  delete process.env.AUTH_PASSWORD_MODE;
  const me = await fetch(`${base}/api/people/me`, { headers: bearer(token) });
  assert.strictEqual(me.status, 401);
});
