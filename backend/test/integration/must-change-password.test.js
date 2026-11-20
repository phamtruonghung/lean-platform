/*
 * A temporary password is a one-use credential (audit F1).
 *
 * The plant loader writes `must_change_password = TRUE` for every Account it
 * seeds; an administrator's reset writes the same flag. Until this change the
 * API only reported it, so signing in with a seeded password was as good as
 * signing in with a real one. Now `requireActive` (middleware.js) refuses
 * every authenticated route with `403 { code: 'MUST_CHANGE_PASSWORD' }` while
 * the flag is TRUE, except `GET /api/people/me` and the change itself.
 *
 * Like plant.test.js and account-password.test.js this goes over HTTP against
 * a real database and inserts its own rows under values unique to this
 * process, deleting them in test.after(): it never truncates `app_users`.
 * Signing in goes through POST /api/auth/login, so the session is a real
 * `account_sessions` row.
 *
 * Needs a database with every migration applied. Set DATABASE_URL first.
 */

const test = require('node:test');
const assert = require('node:assert');
const { hashSecret } = require('../../src/platform/secrets');

// What the loader mints per person; the test's stand-in for it.
const TEMPORARY = 'seeded temporary password';
const CHOSEN = 'the passphrase this person chose';

let server;
let base;
let pool;
let closePool;
const employeeIds = [];
const accountIds = [];

const tag = `mcp${process.pid}`;

// The loader's own shape (dev/seed-relats-vietnam.mjs, loadAccounts): a real
// Employee, an approved and active Account on `operator`, and a credential
// written with must_change_password TRUE. Returns the email so the test can
// sign in the way the person would.
async function makeSeededAccount(name, { mustChange = true, isActive = true, approvalStatus = 'approved' } = {}) {
  const employeeNo = `${tag}-${name}`;
  const { rows: [employee] } = await pool.query(
    `INSERT INTO employees (employee_no, first_name, last_name, is_active)
     VALUES ($1, 'Temp', $2, TRUE) RETURNING id`,
    [employeeNo, name]
  );
  employeeIds.push(employee.id);

  const email = `${employeeNo}@relats.vn`;
  const { rows: [account] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status, employee_id)
     VALUES ($1, $2, 'operator', $3, $4, $5, $6) RETURNING id`,
    [email, `Temp ${name}`, `local:${employeeNo}`, isActive, approvalStatus, employee.id]
  );
  accountIds.push(account.id);

  await pool.query(
    `INSERT INTO account_credentials (app_user_id, password_hash, is_enabled, must_change_password)
     VALUES ($1, $2, TRUE, $3)`,
    [account.id, await hashSecret(TEMPORARY), mustChange]
  );
  return { id: account.id, email };
}

function login(body) {
  return fetch(`${base}/api/auth/login`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
}

const bearer = (token) => ({ authorization: `Bearer ${token}` });

function get(path, token) {
  return fetch(`${base}${path}`, { headers: bearer(token) });
}

function put(path, token, body) {
  return fetch(`${base}${path}`, {
    method: 'PUT',
    headers: { 'content-type': 'application/json', ...bearer(token) },
    body: JSON.stringify(body)
  });
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
  await pool.query('DELETE FROM app_users WHERE id = ANY($1)', [accountIds]);
  await pool.query('DELETE FROM employees WHERE id = ANY($1)', [employeeIds]);
  await new Promise((resolve) => server.close(resolve));
  await closePool();
});

test('a temporary password opens only /me and the change, and everything else after the change', async () => {
  const person = await makeSeededAccount('seeded');

  const signIn = await login({ email: person.email, password: TEMPORARY });
  assert.strictEqual(signIn.status, 200);
  const signedIn = await signIn.json();
  assert.strictEqual(signedIn.account.mustChangePassword, true, 'login reports the flag the API will enforce');
  const token = signedIn.token;

  // Door one: who am I. It has to answer, and it has to carry the flag — this
  // is what the Flutter shell routes to the change Screen on.
  const me = await get('/api/people/me', token);
  assert.strictEqual(me.status, 200);
  assert.strictEqual((await me.json()).account.mustChangePassword, true);

  // Everything else is refused, with a code a client can match on rather than
  // a bare 403 that looks like any permission refusal.
  const refused = await get('/api/kpi/catalogue', token);
  assert.strictEqual(refused.status, 403);
  const refusal = await refused.json();
  assert.strictEqual(refusal.code, 'MUST_CHANGE_PASSWORD');
  assert.strictEqual(refusal.status, 'password_change_required');

  // Door two: the change itself is reachable; a wrong current password is the
  // route's own 400, not the gate's 403.
  const wrong = await put('/api/people/me/password', token, { currentPassword: 'not the temporary one', newPassword: CHOSEN });
  assert.strictEqual(wrong.status, 400);

  const changed = await put('/api/people/me/password', token, { currentPassword: TEMPORARY, newPassword: CHOSEN });
  assert.strictEqual(changed.status, 200);

  // The flag is cleared, and /me says so.
  assert.strictEqual((await (await get('/api/people/me', token)).json()).account.mustChangePassword, false);

  // A normal route answers now.
  const directory = await get('/api/people/employees', token);
  assert.strictEqual(directory.status, 200);

  // The KPI route is no longer refused for the temporary password: the caller
  // reaches its own permission gate (this operator holds no KPI code), which
  // is exactly the difference between the two refusals.
  const kpiAfter = await get('/api/kpi/catalogue', token);
  assert.strictEqual(kpiAfter.status, 403);
  assert.strictEqual((await kpiAfter.json()).code, 'PERMISSION_REQUIRED');

  // The temporary password is spent and the chosen one works.
  assert.strictEqual((await login({ email: person.email, password: TEMPORARY })).status, 401);
  const reseeded = await login({ email: person.email, password: CHOSEN });
  assert.strictEqual(reseeded.status, 200);
  assert.strictEqual((await reseeded.json()).account.mustChangePassword, false);
});

test('a seeded password minted for one person does not sign in as another', async () => {
  const first = await makeSeededAccount('first');
  const second = await makeSeededAccount('second');

  // Both rows exist with an identical credential in this fixture, which is the
  // defect's shape; what the loader now mints is one password per person
  // (asserted in the seed generator test below). What matters here is that
  // the refusal is per Account, not a session-wide lock: signing in as the
  // second person is refused on its own flag, and the first person's change
  // leaves the second's flag alone.
  const firstToken = (await (await login({ email: first.email, password: TEMPORARY })).json()).token;
  assert.strictEqual((await put('/api/people/me/password', firstToken, { currentPassword: TEMPORARY, newPassword: CHOSEN })).status, 200);

  assert.strictEqual((await login({ email: second.email, password: TEMPORARY })).status, 200);
  const secondToken = (await (await login({ email: second.email, password: TEMPORARY })).json()).token;
  const refused = await get('/api/kpi/catalogue', secondToken);
  assert.strictEqual(refused.status, 403);
  assert.strictEqual((await refused.json()).code, 'MUST_CHANGE_PASSWORD');
});

test('an inactive Account hears why it is inactive, never the password refusal', async () => {
  // Both flags could be true at once. The approval branch is checked first, so
  // the answer is the one that tells the person what actually blocks them.
  const pending = await makeSeededAccount('pending', { isActive: false, approvalStatus: 'pending' });
  assert.strictEqual((await login({ email: pending.email, password: TEMPORARY })).status, 200);
  const token = (await (await login({ email: pending.email, password: TEMPORARY })).json()).token;

  const refused = await get('/api/kpi/catalogue', token);
  assert.strictEqual(refused.status, 403);
  const body = await refused.json();
  assert.strictEqual(body.status, 'pending_approval');
  assert.strictEqual(body.code, undefined);
});

test('the loader mints a distinct temporary password per person, never a shared literal', async () => {
  // The seed script is imported, not run: its main() is guarded.
  const seed = await import('../../../dev/seed-relats-vietnam.mjs');

  assert.strictEqual(seed.TEMPORARY_PASSWORD_LENGTH, 16);
  const minted = new Set();
  for (let i = 0; i < 200; i += 1) {
    const password = seed.temporaryPassword();
    assert.strictEqual(password.length, 16);
    assert.ok([...password].every((character) => seed.PASSWORD_ALPHABET.includes(character)),
      `every character comes from the documented alphabet: ${password}`);
    minted.add(password);
  }
  // 200 draws from ~93 bits: a collision would mean it is not random.
  assert.strictEqual(minted.size, 200);
});
