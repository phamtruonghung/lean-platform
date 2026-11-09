/*
 * Sign-in, Account creation and the awaiting-Approval state — issue #6, over
 * HTTP, against a real database and a real local session, per the Platform's
 * one test seam (see README's Tests section and
 * test/integration/health.test.js's own header).
 *
 * A session is a row in `account_sessions` (test/helpers/session.js), so every
 * request below runs the middleware's own `findSessionIdentity` ->
 * `resolveAccountForIdentity` path, the one a signed-in client takes.
 *
 * Account *creation* is the one thing a session cannot trigger: it used to
 * happen when an unknown subject reached the API with a token, and a local
 * session only exists for a row that is already there. The groups below that
 * are about creation therefore drive that step through
 * `resolveAccountForIdentity` — the function the middleware itself calls — and
 * then assert the result over HTTP. What they assert is still the production
 * rule and not a fixture's own INSERT: the first Account on an empty table is
 * an administrator granted every Site's root Org Unit, everyone after starts
 * pending, and the insert is audited with no actor.
 *
 * `app_users`/`app_user_org_units` are truncated in test.before(): unlike
 * schema.test.js's per-test withRollback, these tests each make their own
 * real HTTP requests against the running server's own connection pool, which
 * would not see an uncommitted transaction's rows even if one were open
 * across requests. A clean table is what makes "the first Account created on
 * an empty database becomes administrator" an assertion this suite can
 * actually make, rather than depending on whatever an earlier run or another
 * test file happened to leave behind — sites/org_units are not touched, this
 * file's own root Org Unit grant assertion inserts and cleans up its own.
 *
 * Needs a database with every migration applied. Set DATABASE_URL first —
 * see the README's Tests section.
 */

const test = require('node:test');
const assert = require('node:assert');
const { tokenFor } = require('../helpers/session');
const { resolveAccountForIdentity } = require('../../src/modules/people/service');

let server;
let base;
let pool;
let closePool;

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

  // A clean slate for "the first Account created becomes administrator" to
  // mean what it says — see the file header.
  await pool.query('DELETE FROM app_user_org_units');
  await pool.query('DELETE FROM app_users');
});

test.after(async () => {
  await new Promise((resolve) => server.close(resolve));
  await closePool();
});

// `subject`'s Account, created the way the middleware creates one for a
// subject it has not seen, then visited through `/me` with a session of its
// own. The creation is setup, not the subject of these tests: a local session
// cannot be opened for an Account that does not exist yet, so this drives the
// same `resolveAccountForIdentity` call the middleware makes and leaves every
// assertion below to the HTTP response, unchanged.
async function signIn(subject, { email = `${subject}@example.com`, name } = {}) {
  await resolveAccountForIdentity({ subject, email, name });
  const token = await tokenFor(subject);
  return fetch(`${base}/api/people/me`, { headers: { authorization: `Bearer ${token}` } });
}

async function callAccounts(subject) {
  const token = await tokenFor(subject);
  return fetch(`${base}/api/people/accounts`, { headers: { authorization: `Bearer ${token}` } });
}

// ---------------------------------------------------------------------------
// 1. No session, or a garbage one, is refused before ever reaching an Account.
// ---------------------------------------------------------------------------

test('a request with no bearer token is refused', async () => {
  const response = await fetch(`${base}/api/people/me`);
  assert.strictEqual(response.status, 401);
});

test('a request with a garbage bearer token is refused', async () => {
  const response = await fetch(`${base}/api/people/me`, {
    headers: { authorization: 'Bearer not-a-real-token' }
  });
  assert.strictEqual(response.status, 401);
});

// ---------------------------------------------------------------------------
// 2. The first Account on an empty database: administrator, active
//    immediately, granted every (current) Site's root Org Unit.
// ---------------------------------------------------------------------------

test('the first Account ever created is activated as an administrator and granted every Site', async (t) => {
  // A Site and a root Org Unit beneath it, created directly against
  // Postgres before any Account exists — Sites themselves are issue #7's
  // surface, not #6's, so this reaches straight for the schema the way
  // schema.test.js does for baseline tables with no Module in front of them
  // yet. Created before the creation below so "granted every Site that
  // exists at that moment" has a Site to actually grant. Cleaned up
  // afterwards (org_units before its Site, since sites has no ON DELETE
  // CASCADE onto it) so a second run of this suite starts from the same
  // empty catalogue rather than accumulating a root Org Unit per run — this
  // file runs directly against the pool with no per-test rollback, unlike
  // schema.test.js's withRollback (see the file header).
  const { rows: [site] } = await pool.query(
    `INSERT INTO sites (code, name) VALUES ($1, $2) RETURNING id`,
    [`ACC${process.pid}`, 'Accounts Test Site']
  );
  const { rows: [rootOrgUnit] } = await pool.query(
    `INSERT INTO org_units (site_id, code, name, unit_type)
     VALUES ($1, 'ROOT', 'Whole Site', 'area') RETURNING id`,
    [site.id]
  );
  t.after(async () => {
    await pool.query('DELETE FROM org_units WHERE site_id = $1', [site.id]);
    await pool.query('DELETE FROM sites WHERE id = $1', [site.id]);
  });

  // subject-first is reused by the later tests below as "the" active,
  // administrator Account for this suite — test.before()'s cleanup is what
  // makes this genuinely the first Account against an empty app_users table.
  const response = await signIn('subject-first', { name: 'Ada First' });
  assert.strictEqual(response.status, 200);

  const body = await response.json();
  assert.strictEqual(body.status, 'active');
  assert.strictEqual(body.account.role, 'admin');
  assert.strictEqual(body.account.isActive, true);
  assert.strictEqual(body.account.email, 'subject-first@example.com');
  assert.strictEqual(body.account.displayName, 'Ada First');

  const { rows: grants } = await pool.query(
    'SELECT org_unit_id, can_write FROM app_user_org_units WHERE app_user_id = $1',
    [body.account.id]
  );
  assert.strictEqual(grants.length, 1);
  assert.strictEqual(grants[0].org_unit_id, rootOrgUnit.id);
  assert.strictEqual(grants[0].can_write, true);

  // The one Account in this suite that genuinely holds a real grant row
  // (the bootstrap grant above) and is still an administrator — so this is
  // what actually proves orgUnitScopeFor's isAdmin short-circuit suppresses
  // it, rather than "everywhere implies empty grants" just happening to hold
  // by coincidence everywhere else this is tested.
  assert.strictEqual(body.orgUnitScope.everywhere, true);
  assert.strictEqual(body.orgUnitScope.grants.length, 0);
});

// ---------------------------------------------------------------------------
// 3. Everyone after the first starts inactive, is refused everywhere except
//    their own status, and that refusal is distinguishable from a failure.
// ---------------------------------------------------------------------------

test('the second Account ever created is an inactive operator, not an administrator', async () => {
  // The suite-wide first Account already exists from the tests above — this
  // subject is deliberately a new one, so it is the second Account, not the
  // first.
  const response = await signIn('subject-second');
  assert.strictEqual(response.status, 200);

  const body = await response.json();
  assert.strictEqual(body.status, 'pending_approval');
  assert.strictEqual(body.account.role, 'operator');
  assert.strictEqual(body.account.isActive, false);

  // /me computes orgUnitScope even for a caller requireActive would
  // otherwise block from everything else — a pending Account holds no
  // grants, and is not an administrator either, so both fields say so.
  assert.strictEqual(body.orgUnitScope.everywhere, false);
  assert.strictEqual(body.orgUnitScope.grants.length, 0);
});

test('an inactive Account may still read its own status', async () => {
  const response = await signIn('subject-second');
  assert.strictEqual(response.status, 200);
  const body = await response.json();
  assert.strictEqual(body.status, 'pending_approval');
});

test('an inactive Account is refused everywhere else, with a status the app can distinguish from a failure', async () => {
  const response = await callAccounts('subject-second');
  assert.strictEqual(response.status, 403);

  const body = await response.json();
  assert.strictEqual(body.status, 'pending_approval');
  assert.strictEqual(typeof body.message, 'string');
});

test('an active Account can reach a route that requires one', async () => {
  // subject-first is the suite's activated administrator from test group 2.
  const response = await callAccounts('subject-first');
  assert.strictEqual(response.status, 200);

  const body = await response.json();
  assert.ok(Array.isArray(body.accounts));
  assert.ok(body.accounts.some((a) => a.email === 'subject-first@example.com'));
});

// ---------------------------------------------------------------------------
// 4. The subject identifier is what identifies returning Accounts — a second
//    visit by the same subject resolves to the same Account rather than
//    creating a new one.
// ---------------------------------------------------------------------------

test('signing in twice with the same subject resolves to the same Account', async () => {
  const first = await signIn('subject-returning');
  const firstBody = await first.json();

  const second = await signIn('subject-returning');
  const secondBody = await second.json();

  assert.strictEqual(secondBody.account.id, firstBody.account.id);
});

// ---------------------------------------------------------------------------
// 5. Every write here recorded the acting Account transaction-locally, not
//    session-wide — asserted against the audit trail itself, the same
//    mechanism issue #6's own migration attaches (see
//    migrations/1788279276376_accounts-start-inactive-and-audited.js).
// ---------------------------------------------------------------------------

test('an Account creation is captured in the audit trail with no actor (nobody else authored it)', async () => {
  const response = await signIn('subject-audited');
  const { account } = await response.json();

  const { rows } = await pool.query(
    `SELECT changed_by, operation FROM audit_log
      WHERE table_name = 'app_users' AND record_id = $1 AND operation = 'INSERT'`,
    [account.id]
  );
  assert.strictEqual(rows.length, 1);
  assert.strictEqual(rows[0].changed_by, null);
});
