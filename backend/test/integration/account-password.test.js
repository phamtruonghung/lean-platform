/*
 * Resetting and changing a password (issue #270), over HTTP against a real
 * database — the same seam as plant.test.js. Signing in goes through
 * POST /api/auth/login, so every Account here holds a real local session.
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

const PASSWORD = 'correct horse battery';

let jwks;
let server;
let base;
let pool;
let closePool;
let previousMode;
const employeeIds = [];
const accountIds = [];

const tag = `ap${process.pid}`;
const emailOf = (name) => `${tag}-${name}@example.com`;

async function makeAccount(name, { password = PASSWORD, isActive = true, approvalStatus = 'approved', role = 'operator',
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
     VALUES ($1, $2, $7, $3, $4, $5, $6) RETURNING id`,
    [emailOf(name), `Auth ${name}`, subject, isActive, approvalStatus, employeeId, role]
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

const NEW_PASSWORD = 'a brand new passphrase';
const SHORT = 'x'.repeat(7);

async function signIn(who, password = PASSWORD) {
  const response = await login({ email: who.email, password });
  assert.strictEqual(response.status, 200);
  return (await response.json()).token;
}

function send(method, path, token, body) {
  return fetch(`${base}/api/people${path}`, {
    method,
    headers: { 'content-type': 'application/json', ...bearer(token) },
    body: JSON.stringify(body)
  });
}

const reset = (id, token, password) => send('POST', `/accounts/${id}/password`, token, { password });
const change = (token, currentPassword, newPassword) => send('PUT', '/me/password', token, { currentPassword, newPassword });
const meStatus = async (token) => (await fetch(`${base}/api/people/me`, { headers: bearer(token) })).status;
const loginStatus = async (who, password) => (await login({ email: who.email, password })).status;

test('an administrator reset lets the new password sign in and stops the old one', async () => {
  const admin = await makeAccount('rsadmin', { role: 'admin' });
  const target = await makeAccount('rstarget');
  const token = await signIn(admin);

  const response = await reset(target.id, token, NEW_PASSWORD);
  assert.strictEqual(response.status, 200);
  const text = await response.text();
  assert.ok(!text.includes(NEW_PASSWORD));
  assert.ok(!text.includes('scrypt$'));
  const body = JSON.parse(text);
  assert.deepStrictEqual(Object.keys(body), ['account']);
  assert.deepStrictEqual(Object.keys(body.account).sort(), [
    'approvalStatus', 'createdAt', 'displayName', 'email', 'employeeId', 'externalSubject', 'id', 'isActive', 'role'
  ]);
  assert.strictEqual(body.account.id, target.id);

  assert.strictEqual(await loginStatus(target, NEW_PASSWORD), 200);
  assert.strictEqual(await loginStatus(target, PASSWORD), 401);

  // No endpoint exposes must_change_password yet, so this one column is read directly.
  const { rows: [credential] } = await pool.query(
    'SELECT must_change_password, is_enabled FROM account_credentials WHERE app_user_id = $1', [target.id]);
  assert.strictEqual(credential.must_change_password, true);
  assert.strictEqual(credential.is_enabled, true);
});

test('an administrator reset creates a credential for an Account that had none', async () => {
  const admin = await makeAccount('crtadmin', { role: 'admin' });
  const target = await makeAccount('crttarget', { credential: false });
  const token = await signIn(admin);

  assert.strictEqual((await reset(target.id, token, NEW_PASSWORD)).status, 200);
  assert.strictEqual(await loginStatus(target, NEW_PASSWORD), 200);
});

test('an administrator cannot reset their own password', async () => {
  const admin = await makeAccount('selfadmin', { role: 'admin' });
  const token = await signIn(admin);
  const response = await reset(admin.id, token, NEW_PASSWORD);
  assert.strictEqual(response.status, 403);
  assert.strictEqual(await loginStatus(admin, PASSWORD), 200);
  assert.strictEqual(await loginStatus(admin, NEW_PASSWORD), 401);
});

test('a non-administrator is refused at the reset door', async () => {
  const member = await makeAccount('plainmember');
  const target = await makeAccount('plaintarget');
  const token = await signIn(member);
  assert.strictEqual((await reset(target.id, token, NEW_PASSWORD)).status, 403);
  assert.strictEqual(await loginStatus(target, PASSWORD), 200);
});

test('a reset refuses a 7-character password, and accepts 8', async () => {
  const admin = await makeAccount('lenadmin', { role: 'admin' });
  const target = await makeAccount('lentarget');
  const token = await signIn(admin);

  const tooShort = await reset(target.id, token, SHORT);
  assert.strictEqual(tooShort.status, 400);
  assert.match((await tooShort.json()).message, /at least 8/);
  assert.strictEqual(await loginStatus(target, PASSWORD), 200);

  assert.strictEqual((await reset(target.id, token, 'x'.repeat(8))).status, 200);
  assert.strictEqual(await loginStatus(target, 'x'.repeat(8)), 200);
});

test('a reset with no password, an unknown Account or a bad id is refused', async () => {
  const admin = await makeAccount('badadmin', { role: 'admin' });
  const target = await makeAccount('badtarget');
  const token = await signIn(admin);

  assert.strictEqual((await send('POST', `/accounts/${target.id}/password`, token, {})).status, 400);
  assert.strictEqual((await send('POST', `/accounts/${target.id}/password`, token, { password: 12345678 })).status, 400);
  const unknown = await reset('999999999999', token, NEW_PASSWORD);
  assert.strictEqual(unknown.status, 404);
  assert.deepStrictEqual(await unknown.json(), { message: 'Account not found' });
  assert.strictEqual((await reset('not-an-id', token, NEW_PASSWORD)).status, 400);
});

test('a wrong current password is a 400 that leaves the session and the password alone', async () => {
  const who = await makeAccount('wrongcur');
  const token = await signIn(who);

  const response = await change(token, 'not my password', NEW_PASSWORD);
  assert.strictEqual(response.status, 400);
  assert.deepStrictEqual(await response.json(), { message: 'Current password is not correct.' });
  assert.strictEqual(await meStatus(token), 200);
  assert.strictEqual(await loginStatus(who, PASSWORD), 200);
  assert.strictEqual(await loginStatus(who, NEW_PASSWORD), 401);
});

test('a self-change refuses a too-short or missing field with 400', async () => {
  const who = await makeAccount('selfbad');
  const token = await signIn(who);

  const tooShort = await change(token, PASSWORD, SHORT);
  assert.strictEqual(tooShort.status, 400);
  assert.match((await tooShort.json()).message, /at least 8/);
  assert.strictEqual((await send('PUT', '/me/password', token, { newPassword: NEW_PASSWORD })).status, 400);
  assert.strictEqual((await send('PUT', '/me/password', token, { currentPassword: PASSWORD })).status, 400);
  assert.strictEqual((await send('PUT', '/me/password', token, {})).status, 400);
  assert.strictEqual((await change(token, 42, NEW_PASSWORD)).status, 400);
  assert.strictEqual(await meStatus(token), 200);
  assert.strictEqual(await loginStatus(who, PASSWORD), 200);
});

test('a self-change takes the new password, keeps the caller signed in and ends their other sessions', async () => {
  const admin = await makeAccount('chgadmin', { role: 'admin' });
  const who = await makeAccount('chgself');
  const bystander = await makeAccount('chgother');
  const adminToken = await signIn(admin);
  const token = await signIn(who);
  const otherDevice = await signIn(who);
  const bystanderToken = await signIn(bystander);

  // An administrator's reset marks the password temporary.
  assert.strictEqual((await reset(who.id, adminToken, 'temporary pass')).status, 200);
  // No endpoint exposes must_change_password yet, so it is read directly.
  const flag = async () => (await pool.query(
    'SELECT must_change_password FROM account_credentials WHERE app_user_id = $1', [who.id])).rows[0].must_change_password;
  assert.strictEqual(await flag(), true);

  const response = await change(token, 'temporary pass', NEW_PASSWORD);
  assert.strictEqual(response.status, 200);
  const text = await response.text();
  assert.ok(!text.includes(NEW_PASSWORD));
  assert.ok(!text.includes('temporary pass'));
  assert.ok(!text.includes('scrypt$'));
  assert.strictEqual(JSON.parse(text).account.id, who.id);

  assert.strictEqual(await flag(), false);
  assert.strictEqual(await meStatus(token), 200);
  assert.strictEqual(await meStatus(otherDevice), 401);
  assert.strictEqual(await meStatus(bystanderToken), 200);
  assert.strictEqual(await loginStatus(who, NEW_PASSWORD), 200);
  assert.strictEqual(await loginStatus(who, 'temporary pass'), 401);
});

test('a self-change for an Account holding no credential is a 409', async () => {
  const who = await makeAccount('nocredself', { credential: false });
  // Sign in needs a credential, so give the Account a session directly.
  const crypto = require('node:crypto');
  const token = crypto.randomBytes(32).toString('base64url');
  await pool.query(
    `UPDATE app_users SET external_subject = $2 WHERE id = $1`, [who.id, `local:${tag}-nocredself`]);
  await pool.query(
    `INSERT INTO account_sessions (app_user_id, token_hash, expires_at)
     VALUES ($1, $2, now() + interval '1 hour')`,
    [who.id, crypto.createHash('sha256').update(token).digest('hex')]
  );
  const response = await change(token, PASSWORD, NEW_PASSWORD);
  assert.strictEqual(response.status, 409);
});
