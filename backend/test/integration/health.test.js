/*
 * Health, over HTTP, against a real database.
 *
 * This is the Platform's only test seam: a request travels the whole stack, the
 * way a client's does. Asserting on the handler function instead would prove
 * that a function returns an object, which is not the thing that breaks — what
 * breaks is a route that never got mounted, or a pool that cannot reach
 * Postgres, and neither of those is visible from below HTTP.
 *
 * Needs a database. Set DATABASE_URL before running.
 */

const test = require('node:test');
const assert = require('node:assert');

// Port 0 asks the OS for any free port, so a test run never collides with a
// development server or with a second run on the same machine.
process.env.BACKEND_PORT = '0';

const { server } = require('../../src/index');
const { closePool } = require('../../src/platform/db');

let base;

test.before(async () => {
  // listen() is asynchronous, so the port is not assigned the moment the module
  // finishes loading. Waiting for the event is what makes this deterministic
  // rather than a race that happens to pass on a fast machine.
  if (!server.listening) {
    await new Promise((resolve, reject) => {
      server.once('listening', resolve);
      server.once('error', reject);
    });
  }
  base = `http://127.0.0.1:${server.address().port}`;
});

test.after(async () => {
  await new Promise((resolve) => server.close(resolve));
  await closePool();
});

test('liveness reports the process is up without touching the database', async () => {
  const response = await fetch(`${base}/healthz`);
  assert.strictEqual(response.status, 200);
  assert.deepStrictEqual(await response.json(), { status: 'ok' });
});

test('readiness reports the database answered', async () => {
  const response = await fetch(`${base}/readyz`);
  assert.strictEqual(response.status, 200);

  const body = await response.json();
  assert.strictEqual(body.status, 'ok');
  assert.strictEqual(body.database, 'connected');
});

test('the API health endpoint reports what the database returned', async () => {
  const response = await fetch(`${base}/api/health`);
  assert.strictEqual(response.status, 200);

  const body = await response.json();
  assert.strictEqual(body.status, 'ok');
  assert.strictEqual(body.database, 'connected');
  // The point of the skeleton: this number came back from Postgres, so a green
  // test here means the whole path is connected rather than merely mounted.
  assert.strictEqual(body.answer, 1);
});

test('an unknown path under /api answers in JSON, not HTML', async () => {
  const response = await fetch(`${base}/api/no-such-thing`);
  assert.strictEqual(response.status, 404);
  // Express's default 404 is an HTML page. A client that asked for JSON cannot
  // parse it, so a mistyped URL would surface as a parse error rather than as
  // the 404 it actually is.
  assert.match(response.headers.get('content-type') ?? '', /application\/json/);

  const body = await response.json();
  assert.strictEqual(typeof body.message, 'string');
});
