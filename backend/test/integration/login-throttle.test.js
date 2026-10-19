/*
 * The sign-in throttle (login-throttle.js), over HTTP against a real
 * database. The limits are shrunk through the environment the throttle reads
 * on every call, so the window can elapse inside a test. Each test uses its
 * own email, so the per-email counters never collide; the per-address limit
 * is set high except in the one test about it.
 *
 * Needs a database with every migration applied. Set DATABASE_URL first.
 */

const test = require('node:test');
const assert = require('node:assert');
const { createTestJwks } = require('../helpers/jwks');
const { hashSecret } = require('../../src/platform/secrets');

const PASSWORD = 'correct horse battery';
const tag = `lt${process.pid}`;
const emailOf = (name) => `${tag}-${name}@example.com`;

let jwks;
let server;
let base;
let pool;
let closePool;
let previousMode;
const accountIds = [];
const employeeIds = [];
const saved = {};
const THROTTLE_ENV = {
  LOGIN_THROTTLE_EMAIL_MAX: '3',
  LOGIN_THROTTLE_IP_MAX: '1000',
  LOGIN_THROTTLE_BASE_MS: '1000',
  LOGIN_THROTTLE_WINDOW_MS: '60000'
};

async function makeAccount(name) {
  const { rows: [employee] } = await pool.query(
    `INSERT INTO employees (employee_no, first_name, last_name, is_active)
     VALUES ($1, 'Throttle', $2, TRUE) RETURNING id`,
    [`${tag}-${name}`, name]
  );
  employeeIds.push(employee.id);
  const { rows: [account] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, is_active, approval_status, employee_id)
     VALUES ($1, $2, 'operator', TRUE, 'approved', $3) RETURNING id`,
    [emailOf(name), `Throttle ${name}`, employee.id]
  );
  accountIds.push(account.id);
  await pool.query(
    'INSERT INTO account_credentials (app_user_id, password_hash) VALUES ($1, $2)',
    [account.id, await hashSecret(PASSWORD)]
  );
  return emailOf(name);
}

// `from` stands in for the reverse proxy: with `trust proxy` at 1 the client
// address is the last X-Forwarded-For entry, so a test can act as its own
// address without disturbing the others' counters.
const login = (email, password, from) => fetch(`${base}/api/auth/login`, {
  method: 'POST',
  headers: { 'content-type': 'application/json', ...(from ? { 'x-forwarded-for': from } : {}) },
  body: JSON.stringify({ email, password })
});

const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

test.before(async () => {
  jwks = await createTestJwks();
  process.env.SUPABASE_JWKS_URL = jwks.url;
  process.env.SUPABASE_JWT_ISSUER = 'https://example.supabase.co/auth/v1';
  process.env.SUPABASE_JWT_AUDIENCE = 'authenticated';
  process.env.BACKEND_PORT = '0';
  previousMode = process.env.AUTH_PASSWORD_MODE;
  process.env.AUTH_PASSWORD_MODE = 'local';
  for (const [key, value] of Object.entries(THROTTLE_ENV)) {
    saved[key] = process.env[key];
    process.env[key] = value;
  }

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
  if (previousMode === undefined) delete process.env.AUTH_PASSWORD_MODE;
  else process.env.AUTH_PASSWORD_MODE = previousMode;
  for (const key of Object.keys(THROTTLE_ENV)) {
    if (saved[key] === undefined) delete process.env[key];
    else process.env[key] = saved[key];
  }
  await pool.query('DELETE FROM app_users WHERE id = ANY($1)', [accountIds]);
  await pool.query('DELETE FROM employees WHERE id = ANY($1)', [employeeIds]);
  await new Promise((resolve) => server.close(resolve));
  await closePool();
  await jwks.close();
});

test('repeated failures for one email end in 429 with Retry-After, even for the right password', async () => {
  const email = await makeAccount('burst');
  for (let i = 0; i < 3; i += 1) assert.strictEqual((await login(email, 'wrong password')).status, 401);

  const refused = await login(email, 'wrong password');
  assert.strictEqual(refused.status, 429);
  assert.ok(Number(refused.headers.get('retry-after')) >= 1);

  assert.strictEqual((await login(email, PASSWORD)).status, 429);
});

test('a success resets the email counter', async () => {
  const email = await makeAccount('reset');
  for (let round = 0; round < 3; round += 1) {
    assert.strictEqual((await login(email, 'wrong password')).status, 401);
    assert.strictEqual((await login(email, 'wrong password')).status, 401);
    assert.strictEqual((await login(email, PASSWORD)).status, 200);
  }
});

test('the counter is forgotten once the pause and the window have passed', async () => {
  const email = await makeAccount('window');
  process.env.LOGIN_THROTTLE_WINDOW_MS = '1200';
  try {
    for (let i = 0; i < 3; i += 1) await login(email, 'wrong password');
    assert.strictEqual((await login(email, PASSWORD)).status, 429);
    await wait(1500);
    assert.strictEqual((await login(email, PASSWORD)).status, 200);
  } finally {
    process.env.LOGIN_THROTTLE_WINDOW_MS = THROTTLE_ENV.LOGIN_THROTTLE_WINDOW_MS;
  }
});

test('the pause doubles when the first attempt after it fails', async () => {
  const email = await makeAccount('backoff');
  for (let i = 0; i < 3; i += 1) await login(email, 'wrong password');
  const first = Number((await login(email, 'wrong password')).headers.get('retry-after'));
  await wait(1100);
  assert.strictEqual((await login(email, 'wrong password')).status, 401);
  const second = await login(email, 'wrong password');
  assert.strictEqual(second.status, 429);
  assert.ok(Number(second.headers.get('retry-after')) > first);
});

test('an address that tries many emails is stopped by the per-address limit', async () => {
  process.env.LOGIN_THROTTLE_IP_MAX = '4';
  try {
    for (let i = 0; i < 4; i += 1) {
      assert.strictEqual((await login(`${tag}-nobody${i}@example.com`, 'wrong password', '203.0.113.7')).status, 401);
    }
    const refused = await login(`${tag}-nobody-next@example.com`, 'wrong password', '203.0.113.7');
    assert.strictEqual(refused.status, 429);
    assert.ok(Number(refused.headers.get('retry-after')) >= 1);
    // Another address is untouched.
    assert.strictEqual((await login(`${tag}-nobody-next@example.com`, 'wrong password', '203.0.113.8')).status, 401);
  } finally {
    process.env.LOGIN_THROTTLE_IP_MAX = THROTTLE_ENV.LOGIN_THROTTLE_IP_MAX;
  }
});

test('outside local mode the login route does not exist', async () => {
  process.env.AUTH_PASSWORD_MODE = 'supabase';
  try {
    assert.strictEqual((await login(emailOf('burst'), PASSWORD)).status, 404);
  } finally {
    process.env.AUTH_PASSWORD_MODE = 'local';
  }
});
