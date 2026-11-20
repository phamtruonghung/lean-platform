/*
 * The security headers the API sets on its own responses, over HTTP.
 *
 * `/api/...` never passes through the frontend container, so everything
 * frontend/nginx.conf declares — HSTS, a CSP, nosniff, X-Frame-Options, a
 * Referrer-Policy — would be absent from an API response if the API did not set
 * it itself. This drives the real application (the same `require` the other
 * integration files use) rather than a rebuilt middleware stack, so a wiring
 * mistake in src/index.js fails here.
 *
 * The three requests are the three shapes a response can take: a JSON 404 from
 * the `/api` fallback, Express's own HTML 404 for a path no Module claimed, and
 * the health probe.
 *
 * One measured difference, and it is not a bug to "fix": Express's default
 * 404 is written by `finalhandler`, which sets its own
 * `Content-Security-Policy: default-src 'none'` on the page it generates. That
 * replaces the API's policy for that one response — it is strictly narrower
 * than ours (nothing at all may load), and the other four headers are ours.
 * The assertion below is written to say exactly that, rather than to pretend
 * one string is set everywhere.
 *
 * Needs a database with every migration applied. Set DATABASE_URL first — see
 * the README's Tests section.
 */

const test = require('node:test');
const assert = require('node:assert');

const {
  CONTENT_SECURITY_POLICY,
  STRICT_TRANSPORT_SECURITY
} = require('../../src/platform/security-headers');

let server;
let base;
let closePool;

test.before(async () => {
  ({ server } = require('../../src/index'));
  ({ closePool } = require('../../src/platform/db'));

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

/// What every response from this process must carry, whatever its status and
/// whoever wrote its body. The CSP is checked for its floor — `default-src
/// 'none'` — because Express's own 404 page ships a narrower policy of its own;
/// the tests that expect this process's exact string say so separately.
function assertSecurityHeaders(response, where) {
  assert.strictEqual(response.headers.get('strict-transport-security'), STRICT_TRANSPORT_SECURITY,
    `${where} does not carry HSTS`);
  const csp = response.headers.get('content-security-policy');
  assert.ok(csp, `${where} carries no Content-Security-Policy`);
  assert.ok(csp.startsWith("default-src 'none'"),
    `${where} carries a CSP that does not start closed: ${csp}`);
  assert.strictEqual(response.headers.get('x-content-type-options'), 'nosniff',
    `${where} does not carry nosniff`);
  assert.strictEqual(response.headers.get('x-frame-options'), 'DENY',
    `${where} does not refuse to be framed`);
  assert.strictEqual(response.headers.get('referrer-policy'), 'strict-origin-when-cross-origin',
    `${where} does not carry the Referrer-Policy`);
}

test('a JSON 404 under /api carries the security headers', async () => {
  const response = await fetch(`${base}/api/no-such-endpoint`, { headers: { accept: 'application/json' } });
  assert.strictEqual(response.status, 404);
  assert.deepStrictEqual(await response.json(), { message: 'No such endpoint' });
  assertSecurityHeaders(response, 'the /api 404');
  assert.strictEqual(response.headers.get('content-security-policy'), CONTENT_SECURITY_POLICY,
    'the /api 404 does not carry this process\'s own CSP');
});

test('Express\'s own 404, outside /api, carries them too', async () => {
  const response = await fetch(`${base}/no-such-path`);
  assert.strictEqual(response.status, 404);
  assertSecurityHeaders(response, 'the non-/api 404');
});

test('the health probe carries them', async () => {
  const response = await fetch(`${base}/healthz`);
  assert.strictEqual(response.status, 200);
  assertSecurityHeaders(response, '/healthz');
  assert.strictEqual(response.headers.get('content-security-policy'), CONTENT_SECURITY_POLICY,
    '/healthz does not carry this process\'s own CSP');
});

test('the API\'s CSP allows nothing a JSON response could execute', () => {
  // Not a header assertion but the argument for the policy: a document served
  // under it can load no script, no style, no image and no frame, and cannot be
  // framed, submit a form or rewrite its base.
  for (const directive of ['default-src \'none\'', 'frame-ancestors \'none\'', 'base-uri \'none\'', 'form-action \'none\'']) {
    assert.ok(CONTENT_SECURITY_POLICY.includes(directive), `the API's CSP has no ${directive}`);
  }
  assert.ok(!/unsafe-inline|unsafe-eval/.test(CONTENT_SECURITY_POLICY),
    'the API renders no markup, so its CSP must not need an unsafe allowance');
});
