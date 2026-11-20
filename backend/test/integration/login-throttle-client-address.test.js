/*
 * Which client the sign-in throttle counts, over HTTP against a real database.
 *
 * Behind the deployed proxy chain the socket peer is the same for every caller,
 * so the throttle's address key has to come from the tunnel header — but only
 * from the proxy hop, or a caller names its own bucket. This file drives both
 * halves: a burst from one address locks that address and leaves another alone,
 * and a header sent by a peer that is not the proxy is ignored.
 *
 * The test's own socket (127.0.0.1) stands in for the proxy hop, so
 * CLIENT_TRUSTED_PROXIES decides for each test whether the header is believed.
 * That is the same switch the deployment uses, not a test-only path.
 *
 * Needs a database with every migration applied. Set DATABASE_URL first.
 */

const test = require('node:test');
const assert = require('node:assert');
const { hashSecret } = require('../../src/platform/secrets');

const PASSWORD = 'correct horse battery';
const tag = `ltca${process.pid}`;
const emailOf = (name) => `${tag}-${name}@example.com`;

let server;
let base;
let pool;
let closePool;
const accountIds = [];
const employeeIds = [];

const THROTTLE_ENV = {
  LOGIN_THROTTLE_EMAIL_MAX: '1000',
  LOGIN_THROTTLE_IP_MAX: '5',
  LOGIN_THROTTLE_BASE_MS: '60000',
  LOGIN_THROTTLE_WINDOW_MS: '60000',
  CLIENT_TRUSTED_PROXIES: '127.0.0.1/8'
};

async function makeAccount(name) {
  const { rows: [employee] } = await pool.query(
    `INSERT INTO employees (employee_no, first_name, last_name, is_active)
     VALUES ($1, 'Client', $2, TRUE) RETURNING id`,
    [`${tag}-${name}`, name]
  );
  employeeIds.push(employee.id);
  const { rows: [account] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, is_active, approval_status, employee_id)
     VALUES ($1, $2, 'operator', TRUE, 'approved', $3) RETURNING id`,
    [emailOf(name), `Client ${name}`, employee.id]
  );
  accountIds.push(account.id);
  await pool.query(
    'INSERT INTO account_credentials (app_user_id, password_hash) VALUES ($1, $2)',
    [account.id, await hashSecret(PASSWORD)]
  );
  return emailOf(name);
}

// `claimed` is what the caller writes in CF-Connecting-IP; the tunnel is the
// only sender whose write is believed, which is what these tests vary.
const login = (email, password, claimed) => fetch(`${base}/api/auth/login`, {
  method: 'POST',
  headers: {
    'content-type': 'application/json',
    ...(claimed ? { 'cf-connecting-ip': claimed } : {})
  },
  body: JSON.stringify({ email, password })
});

function withEnv(values, run) {
  const saved = {};
  for (const [key, value] of Object.entries(values)) {
    saved[key] = process.env[key];
    process.env[key] = value;
  }
  return run().finally(() => {
    for (const [key, value] of Object.entries(saved)) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  });
}

test.before(async () => {
  process.env.BACKEND_PORT = '0';
  for (const [key, value] of Object.entries(THROTTLE_ENV)) {
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
  await pool.query('DELETE FROM app_users WHERE id = ANY($1)', [accountIds]);
  await pool.query('DELETE FROM employees WHERE id = ANY($1)', [employeeIds]);
  await new Promise((resolve) => server.close(resolve));
  await closePool();
});

test('five failures from address A lock A only; address B still signs in', async () => {
  const allowed = await makeAccount('allowed');

  // Five failures, each for a different account, from one address the tunnel
  // names. The per-email limit is out of the way on purpose: A is stopped by
  // the address bucket alone.
  for (let i = 0; i < 5; i += 1) {
    const attempt = await login(`${tag}-nobody${i}@example.com`, 'wrong password', '203.0.113.10');
    assert.strictEqual(attempt.status, 401, `failure ${i + 1} from A is still an attempt`);
  }

  const refused = await login(`${tag}-nobody-next@example.com`, 'wrong password', '203.0.113.10');
  assert.strictEqual(refused.status, 429);
  assert.ok(Number(refused.headers.get('retry-after')) >= 1);

  // B, a different client, is untouched: it signs in with the right password
  // while A is paused.
  const signedIn = await login(allowed, PASSWORD, '203.0.113.11');
  assert.strictEqual(signedIn.status, 200, 'B still signs in while A is locked');
  const session = await signedIn.json();
  assert.ok(session.token, 'B got a session');

  // And the pause is the sign-in bucket's own: a route that is not sign-in is
  // not slowed by it.
  const mode = await fetch(`${base}/api/auth/mode`);
  assert.strictEqual(mode.status, 200);
});

test('a forged CF-Connecting-IP from a peer that is not the proxy chooses no bucket', async () => {
  // The proxy hop moves off this test's socket, so nothing a caller writes is
  // believed: the request is counted as the address it actually came from.
  await withEnv({ CLIENT_TRUSTED_PROXIES: '198.51.100.0/24', LOGIN_THROTTLE_IP_MAX: '3' }, async () => {
    for (let i = 0; i < 3; i += 1) {
      const attempt = await login(`${tag}-forged${i}@example.com`, 'wrong password', `203.0.113.2${i + 1}`);
      assert.strictEqual(attempt.status, 401, `forged attempt ${i + 1} is counted against the real peer`);
    }

    // A fourth, fresh name in the header. If the header were believed this
    // would be a new bucket and a 401; it is the same real address, already
    // spent.
    const refused = await login(`${tag}-forged-next@example.com`, 'wrong password', '203.0.113.24');
    assert.strictEqual(refused.status, 429, 'the forged header did not buy a new bucket');
    assert.ok(Number(refused.headers.get('retry-after')) >= 1);
  });

  // With the hop back in the list, a header IS believed again — the fallback is
  // the peer only while the peer is not the proxy.
  const believed = await login(`${tag}-named@example.com`, 'wrong password', '203.0.113.30');
  assert.strictEqual(believed.status, 401);
});
