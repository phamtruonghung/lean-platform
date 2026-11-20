/*
 * Which client the sign-in throttle counts, over HTTP against a real database.
 *
 * Behind the deployed proxy chain the socket peer is the same for every caller,
 * so the throttle's address key has to be the address the edge vouched for —
 * and the chain that matters is the one production has: `platform-edge` is
 * published on the plant LAN, so a caller can reach it without Cloudflare and
 * write every header it likes. The tests below drive that arrangement, not a
 * convenient one:
 *
 *   1. one caller, a FRESH CF-Connecting-IP on every attempt, is still one
 *      bucket — five failures and the sixth is refused (round 1's missing case);
 *   2. two callers through the tunnel are two buckets, not one plant-wide one;
 *   3. the edge as it runs today (no X-Client-IP, X-Forwarded-For appended)
 *      counts coarsely but never as a bucket the caller chose;
 *   4. a header from a peer that is not the proxy is ignored entirely.
 *
 * The test's own socket (127.0.0.1) stands in for the edge, so
 * CLIENT_TRUSTED_PROXIES decides for each test whether the edge is believed.
 * The headers sent are the ones dev/edge.nginx.conf produces — proven against a
 * real nginx 1.27-alpine separately; here they are simply what arrives.
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

/*
 * A sign-in as the edge forwards it. `client` is the address the edge
 * classified — it writes it into X-Client-IP and replaces X-Forwarded-For with
 * it. `cf` is what the caller wrote in CF-Connecting-IP, which the edge does not
 * touch and the API must not believe on its own; `forwarded` is a raw
 * X-Forwarded-For, for the edge as it runs today.
 */
const login = (email, password, { client, cf, forwarded } = {}) => fetch(`${base}/api/auth/login`, {
  method: 'POST',
  headers: {
    'content-type': 'application/json',
    ...(client ? { 'x-client-ip': client, 'x-forwarded-for': client } : {}),
    ...(forwarded ? { 'x-forwarded-for': forwarded } : {}),
    ...(cf ? { 'cf-connecting-ip': cf } : {})
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

test('a caller cannot choose its bucket by writing CF-Connecting-IP at the edge', async () => {
  // The arrangement that exists in production: the socket peer is the edge, and
  // the caller supplies CF-Connecting-IP itself. A fresh one on every attempt is
  // what a password spray looks like, and on the round-1 fix it bought a fresh
  // bucket each time (nine attempts, nine 401s, never a 429).
  const allowed = await makeAccount('direct-caller');
  const client = '203.0.113.10';

  for (let i = 0; i < 5; i += 1) {
    const attempt = await login(`${tag}-spray${i}@example.com`, 'wrong password', {
      client,
      cf: `198.51.100.${i + 1}`
    });
    assert.strictEqual(attempt.status, 401, `failure ${i + 1} is a counted attempt`);
  }

  // A fresh claim in the tunnel header. If it were the key this would be a new
  // bucket and another 401; the caller is the same one the edge named.
  const refused = await login(`${tag}-spray-next@example.com`, 'wrong password', {
    client,
    cf: '198.51.100.99'
  });
  assert.strictEqual(refused.status, 429, 'a fresh CF-Connecting-IP did not buy a bucket');
  assert.ok(Number(refused.headers.get('retry-after')) >= 1);

  // A second caller is untouched: it signs in with the right password while the
  // first is paused.
  const signedIn = await login(allowed, PASSWORD, { client: '203.0.113.11', cf: '198.51.100.77' });
  assert.strictEqual(signedIn.status, 200, 'the second caller still signs in');
  const session = await signedIn.json();
  assert.ok(session.token, 'the second caller got a session');

  // And the pause is the sign-in bucket's own: a route that is not sign-in is
  // not slowed by it.
  const mode = await fetch(`${base}/api/auth/mode`);
  assert.strictEqual(mode.status, 200);
});

test('two callers through the tunnel are two buckets, not one for the plant', async () => {
  const allowed = await makeAccount('tunnel-second');
  const first = '203.0.113.20';

  for (let i = 0; i < 5; i += 1) {
    const attempt = await login(`${tag}-tunnel${i}@example.com`, 'wrong password', { client: first, cf: first });
    assert.strictEqual(attempt.status, 401, `tunnel failure ${i + 1}`);
  }
  const refused = await login(`${tag}-tunnel-next@example.com`, 'wrong password', { client: first, cf: first });
  assert.strictEqual(refused.status, 429, 'the first tunnel client is paused');

  // This is the half F3 was about: twenty-one requests from anywhere used to
  // pause sign-in for the whole plant. A second tunnel client is a second
  // bucket, so it signs in while the first is paused.
  const signedIn = await login(allowed, PASSWORD, { client: '203.0.113.21', cf: '203.0.113.21' });
  assert.strictEqual(signedIn.status, 200, 'a second tunnel client is not the first one');
});

test('the edge as it runs today counts coarsely, and never as a bucket the caller chose', async () => {
  // Today's platform-edge sets no X-Client-IP and appends to X-Forwarded-For, so
  // the last entry is what it appended: the connector (Docker's published port
  // shows it as the gateway). Until the edge is reloaded the count is coarse —
  // that is the plant-wide bucket, not per client — but a caller cannot escape
  // it by writing CF-Connecting-IP or by prepending to the forwarded list.
  await withEnv({ CLIENT_TRUSTED_PROXIES: '127.0.0.1/8,172.16.0.0/12' }, async () => {
    for (let i = 0; i < 5; i += 1) {
      const attempt = await login(`${tag}-legacy${i}@example.com`, 'wrong password', {
        forwarded: `198.51.100.${i + 1}, 172.18.0.9`,
        cf: `198.51.100.${i + 1}`
      });
      assert.strictEqual(attempt.status, 401, `legacy edge failure ${i + 1}`);
    }

    const refused = await login(`${tag}-legacy-next@example.com`, 'wrong password', {
      forwarded: '198.51.100.100, 172.18.0.9',
      cf: '198.51.100.100'
    });
    assert.strictEqual(refused.status, 429, 'the caller-written headers bought no bucket');
  });
});

test('a header from a peer that is not the proxy is ignored', async () => {
  // The edge moves off this test's socket, so nothing a caller writes is
  // believed: the request is counted as the address it came from.
  await withEnv({ CLIENT_TRUSTED_PROXIES: '198.51.100.0/24', LOGIN_THROTTLE_IP_MAX: '3' }, async () => {
    for (let i = 0; i < 3; i += 1) {
      const attempt = await login(`${tag}-forged${i}@example.com`, 'wrong password', {
        client: `203.0.113.${i + 40}`,
        cf: `203.0.113.${i + 40}`
      });
      assert.strictEqual(attempt.status, 401, `forged attempt ${i + 1} counts against the real peer`);
    }

    const refused = await login(`${tag}-forged-next@example.com`, 'wrong password', {
      client: '203.0.113.50',
      cf: '203.0.113.50'
    });
    assert.strictEqual(refused.status, 429, 'the forged headers did not buy a new bucket');
    assert.ok(Number(refused.headers.get('retry-after')) >= 1);
  });
});
