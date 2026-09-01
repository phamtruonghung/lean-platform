/*
 * Approval, roles and Org Unit scope enforcement (issue #8), over HTTP,
 * against a real database and a real (locally issued) JWKS — the same seam
 * as accounts.test.js and plant.test.js (see either file's own header, and
 * the README's Tests section).
 *
 * Like plant.test.js, this file does not truncate `app_users`: that table
 * is shared with accounts.test.js's own "the first Account becomes
 * administrator" assertion, and `node --test` would otherwise race two
 * files' cleanup against each other (see plant.test.js's header — the same
 * reasoning applies here unchanged). Instead this file inserts its own
 * administrator directly (bypassing the bootstrap sign-in path entirely,
 * the same way plant.test.js's own fixtures do), and creates every other
 * Account through a real sign-in (`/api/people/me`) so that
 * `createAccountForSubject`'s ordinary, non-bootstrap path — `pending`,
 * inactive, role `operator` — is what this suite's "Accounts awaiting
 * Approval" actually are. Every row this file inserts, in `app_users`,
 * `app_user_org_units`, `sites` and `org_units`, is deleted again in
 * `test.after()`/`t.after()`.
 *
 * Needs a database with every migration applied. Set DATABASE_URL first —
 * see the README's Tests section.
 */

const test = require('node:test');
const assert = require('node:assert');
const { createTestJwks } = require('../helpers/jwks');

const ISSUER = 'https://example.supabase.co/auth/v1';
const AUDIENCE = 'authenticated';

let jwks;
let server;
let base;
let pool;
let closePool;
let adminToken;
let adminAccountId;

const insertedAccountIds = [];
const insertedSiteIds = [];

let codeCounter = 0;
// Unique across processes (process.pid) and within one run (the counter),
// so tests that create several Sites/Org Units/Accounts never collide on a
// UNIQUE constraint — the same device plant.test.js's own uniqueCode uses.
function uniqueCode(prefix) {
  codeCounter += 1;
  return `${prefix}${process.pid}${codeCounter}`;
}

async function signToken(subject) {
  return jwks.signToken(
    { sub: subject, email: `${subject}@example.com` },
    { issuer: ISSUER, audience: AUDIENCE }
  );
}

async function authHeader(subject) {
  return { authorization: `Bearer ${await signToken(subject)}` };
}

test.before(async () => {
  jwks = await createTestJwks();
  process.env.SUPABASE_JWKS_URL = jwks.url;
  process.env.SUPABASE_JWT_ISSUER = ISSUER;
  process.env.SUPABASE_JWT_AUDIENCE = AUDIENCE;
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

  // The administrator this whole suite acts as — inserted directly, with no
  // grant rows at all, so criterion 8 ("an administrator can act across
  // every Site") is proven by the role alone and not by an accident of the
  // bootstrap path also granting every Site's root (issue #6).
  const adminSubject = `approval-admin-${process.pid}`;
  const { rows: [admin] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status)
     VALUES ($1, 'Approval Test Admin', 'admin', $2, TRUE, 'approved') RETURNING id`,
    [`${adminSubject}@example.com`, adminSubject]
  );
  adminAccountId = admin.id;
  insertedAccountIds.push(admin.id);
  adminToken = await authHeader(adminSubject);
});

test.after(async () => {
  await pool.query('DELETE FROM app_user_org_units WHERE app_user_id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM app_users WHERE id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM org_units WHERE site_id = ANY($1)', [insertedSiteIds]);
  await pool.query('DELETE FROM sites WHERE id = ANY($1)', [insertedSiteIds]);
  await new Promise((resolve) => server.close(resolve));
  await closePool();
  await jwks.close();
});

// A brand-new Account, through the real sign-in path — createAccountForSubject
// sees app_users already non-empty (the suite's own admin, inserted above),
// so this always takes the ordinary path: pending, inactive, role operator.
// Never the bootstrap path, which this suite is deliberately not exercising
// here (issue #6's own tests already cover it).
async function createPendingAccount(subjectPrefix) {
  const subject = uniqueCode(subjectPrefix);
  const token = await signToken(subject);
  const response = await fetch(`${base}/api/people/me`, {
    headers: { authorization: `Bearer ${token}` }
  });
  const { account } = await response.json();
  insertedAccountIds.push(account.id);
  return { subject, token, account };
}

async function approve(id, body, token = adminToken) {
  return fetch(`${base}/api/people/accounts/${id}/approval`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
}

async function reject(id, token = adminToken) {
  return fetch(`${base}/api/people/accounts/${id}/rejection`, {
    method: 'POST',
    headers: token
  });
}

async function patchAccount(id, body, token = adminToken) {
  return fetch(`${base}/api/people/accounts/${id}`, {
    method: 'PATCH',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
}

async function me(token) {
  return fetch(`${base}/api/people/me`, { headers: token });
}

// A Site with a root Org Unit and a child beneath it, created by the suite's
// own administrator — the fixture most of the scope-enforcement tests below
// build on. Cleaned up via insertedSiteIds in test.after() (org_units
// cascade with their Site's own cleanup there — no ON DELETE CASCADE onto
// sites, so org_units is deleted first, the same ordering plant.test.js
// uses).
async function createSiteWithTree() {
  const siteResponse = await fetch(`${base}/api/people/sites`, {
    method: 'POST',
    headers: { ...adminToken, 'content-type': 'application/json' },
    body: JSON.stringify({ code: uniqueCode('AS'), name: 'Approval Test Site', timezone: 'UTC' })
  });
  const { site } = await siteResponse.json();
  insertedSiteIds.push(site.id);

  const rootResponse = await fetch(`${base}/api/people/sites/${site.id}/org-units`, {
    method: 'POST',
    headers: { ...adminToken, 'content-type': 'application/json' },
    body: JSON.stringify({ code: uniqueCode('ROOT'), name: 'Root', unitType: 'area' })
  });
  const { orgUnit: root } = await rootResponse.json();

  const childResponse = await fetch(`${base}/api/people/sites/${site.id}/org-units`, {
    method: 'POST',
    headers: { ...adminToken, 'content-type': 'application/json' },
    body: JSON.stringify({ code: uniqueCode('CHILD'), name: 'Child', unitType: 'department', parentId: root.id })
  });
  const { orgUnit: child } = await childResponse.json();

  const grandchildResponse = await fetch(`${base}/api/people/sites/${site.id}/org-units`, {
    method: 'POST',
    headers: { ...adminToken, 'content-type': 'application/json' },
    body: JSON.stringify({ code: uniqueCode('GRAND'), name: 'Grandchild', unitType: 'line', parentId: child.id })
  });
  const { orgUnit: grandchild } = await grandchildResponse.json();

  return { site, root, child, grandchild };
}

// ---------------------------------------------------------------------------
// 1. An administrator sees the queue of Accounts awaiting Approval.
// ---------------------------------------------------------------------------

test('an administrator sees the queue of Accounts awaiting Approval, and only an administrator may see it', async () => {
  const { account: pending } = await createPendingAccount('queue');

  const asAdmin = await fetch(`${base}/api/people/accounts/pending`, { headers: adminToken });
  assert.strictEqual(asAdmin.status, 200);
  const { accounts } = await asAdmin.json();
  assert.ok(accounts.some((a) => a.id === pending.id));
  assert.ok(accounts.every((a) => a.approvalStatus === 'pending'));

  // An approved, non-admin Account may not see the queue — requireAdmin, not
  // requireActive, is what refuses this (it is active, just not an admin).
  const { account: approvedAccount, token: approvedToken } = await approveFreshAccount('operator', []);
  const asNonAdmin = await fetch(`${base}/api/people/accounts/pending`, { headers: approvedToken });
  assert.strictEqual(asNonAdmin.status, 403);
  void approvedAccount;
});

// Approves a brand-new pending Account with the given role/grants and
// returns its (now active) sign-in token — the fixture most of the
// scope-enforcement tests below start from.
async function approveFreshAccount(role, grants) {
  const { subject, token, account: pending } = await createPendingAccount('scoped');
  const response = await approve(pending.id, { role, grants });
  const body = await response.json();
  assert.strictEqual(response.status, 200, `approval should succeed: ${JSON.stringify(body)}`);
  return { subject, token: { authorization: `Bearer ${token}` }, account: body.account };
}

// ---------------------------------------------------------------------------
// 2. Approving an Account sets its role and grants its Org Units in the
//    same act — one transaction, so a partial Approval is never observable.
// ---------------------------------------------------------------------------

test('approving an Account sets its role and grants its Org Units in the same act', async () => {
  const { root } = await createSiteWithTree();
  const { subject: _subject, account: pending } = await createPendingAccount('approve');

  const response = await approve(pending.id, {
    role: 'supervisor',
    grants: [{ orgUnitId: root.id, canWrite: true }]
  });
  assert.strictEqual(response.status, 200);
  const { account } = await response.json();
  assert.strictEqual(account.role, 'supervisor');
  assert.strictEqual(account.approvalStatus, 'approved');
  assert.strictEqual(account.isActive, true);

  const { rows: grants } = await pool.query(
    'SELECT org_unit_id, can_write FROM app_user_org_units WHERE app_user_id = $1',
    [pending.id]
  );
  assert.strictEqual(grants.length, 1);
  assert.strictEqual(grants[0].org_unit_id, root.id);
  assert.strictEqual(grants[0].can_write, true);
});

test('approving with an unknown role is rejected, and the Account stays untouched', async () => {
  const { account: pending } = await createPendingAccount('badrole');

  const response = await approve(pending.id, { role: 'astronaut', grants: [] });
  assert.strictEqual(response.status, 400);

  const { rows: [row] } = await pool.query(
    'SELECT approval_status, role FROM app_users WHERE id = $1',
    [pending.id]
  );
  assert.strictEqual(row.approval_status, 'pending');
  assert.strictEqual(row.role, 'operator');
});

test('approving with an unknown Org Unit id rejects the whole request — no partial grants', async () => {
  const { root } = await createSiteWithTree();
  const { account: pending } = await createPendingAccount('badgrant');

  const response = await approve(pending.id, {
    role: 'operator',
    grants: [
      { orgUnitId: root.id, canWrite: true },
      { orgUnitId: '999999999', canWrite: false }
    ]
  });
  assert.ok([400, 404].includes(response.status), `expected 400 or 404, got ${response.status}`);

  const { rows: [row] } = await pool.query(
    'SELECT approval_status FROM app_users WHERE id = $1',
    [pending.id]
  );
  assert.strictEqual(row.approval_status, 'pending');

  const { rows: grants } = await pool.query(
    'SELECT 1 FROM app_user_org_units WHERE app_user_id = $1',
    [pending.id]
  );
  assert.strictEqual(grants.length, 0);
});

test('approving requires the administrator role', async () => {
  const { token: nonAdminToken } = await approveFreshAccount('operator', []);
  const { account: pending } = await createPendingAccount('unauth');

  const response = await approve(pending.id, { role: 'operator', grants: [] }, nonAdminToken);
  assert.strictEqual(response.status, 403);
});

// ---------------------------------------------------------------------------
// 3. An Account can be rejected, and an admitted Account can later be
//    deactivated without being deleted.
// ---------------------------------------------------------------------------

test('a rejected Account stays rejected — a later sign-in does not put it back in the queue', async () => {
  const { subject, token, account: pending } = await createPendingAccount('reject');

  const response = await reject(pending.id);
  assert.strictEqual(response.status, 200);
  const { account } = await response.json();
  assert.strictEqual(account.approvalStatus, 'rejected');
  assert.strictEqual(account.isActive, false);

  // Same subject, signing in again: resolves to the same (still rejected)
  // Account rather than recreating a fresh pending one — see the migration's
  // own header on exactly this.
  const secondSignIn = await me({ authorization: `Bearer ${token}` });
  const secondBody = await secondSignIn.json();
  assert.strictEqual(secondBody.account.id, pending.id);
  assert.strictEqual(secondBody.status, 'rejected');
  void subject;

  const queue = await fetch(`${base}/api/people/accounts/pending`, { headers: adminToken });
  const { accounts } = await queue.json();
  assert.ok(!accounts.some((a) => a.id === pending.id));
});

test('rejecting an already-approved Account is allowed, and is distinguishable from a plain deactivation', async () => {
  const { token, account } = await approveFreshAccount('operator', []);

  const response = await reject(account.id);
  assert.strictEqual(response.status, 200);

  const meResponse = await me(token);
  const meBody = await meResponse.json();
  assert.strictEqual(meBody.status, 'rejected');
  assert.notStrictEqual(meBody.status, 'deactivated');
});

// The real consequence of rejection is not merely a changed /me status — it
// is that the Account can no longer act at all. Same pattern as
// accounts.test.js's "an inactive Account is refused everywhere else" (there,
// for a pending Account); here for a rejected one, whose refusal must carry
// its own distinguishable status rather than the generic pending one.
test('a rejected Account is refused a protected route with 403 and its own distinguishable status', async () => {
  const { token, account } = await approveFreshAccount('operator', []);

  const rejection = await reject(account.id);
  assert.strictEqual(rejection.status, 200);

  const response = await fetch(`${base}/api/people/accounts/pending`, { headers: token });
  assert.strictEqual(response.status, 403);
  const body = await response.json();
  assert.strictEqual(body.status, 'rejected');
  assert.notStrictEqual(body.status, 'pending_approval');
});

test('an admitted Account can be deactivated without being deleted, and reactivated', async () => {
  const { token, account } = await approveFreshAccount('operator', []);

  const deactivate = await patchAccount(account.id, { isActive: false });
  assert.strictEqual(deactivate.status, 200);
  const { account: deactivated } = await deactivate.json();
  assert.strictEqual(deactivated.isActive, false);
  assert.strictEqual(deactivated.approvalStatus, 'approved');

  // Not deleted — the row is still there, and still 'approved'.
  const { rows: [row] } = await pool.query('SELECT id, approval_status FROM app_users WHERE id = $1', [account.id]);
  assert.strictEqual(row.approval_status, 'approved');

  const meResponse = await me(token);
  const meBody = await meResponse.json();
  assert.strictEqual(meBody.status, 'deactivated');

  const reactivate = await patchAccount(account.id, { isActive: true });
  assert.strictEqual(reactivate.status, 200);
  const meAfterReactivation = await (await me(token)).json();
  assert.strictEqual(meAfterReactivation.status, 'active');
});

// As above, for deactivation: the real consequence is that the Account can no
// longer act, not merely that /me reports a different status.
test('a deactivated Account is refused a protected route with 403 and its own distinguishable status', async () => {
  const { token, account } = await approveFreshAccount('operator', []);

  const deactivate = await patchAccount(account.id, { isActive: false });
  assert.strictEqual(deactivate.status, 200);

  const response = await fetch(`${base}/api/people/accounts/pending`, { headers: token });
  assert.strictEqual(response.status, 403);
  const body = await response.json();
  assert.strictEqual(body.status, 'deactivated');
  assert.notStrictEqual(body.status, 'pending_approval');
});

test('an Account not yet approved cannot be activated or deactivated through PATCH /accounts/:id', async () => {
  const { account: pending } = await createPendingAccount('patchpending');
  const response = await patchAccount(pending.id, { isActive: true });
  assert.strictEqual(response.status, 400);
});

// ---------------------------------------------------------------------------
// 4. An action outside the caller's granted Org Units is refused with 403,
//    distinguishable from 404.
// ---------------------------------------------------------------------------

test('an Org Unit that does not exist is a 404; one that exists but is outside the caller\'s scope is a distinguishable 403', async () => {
  const { child } = await createSiteWithTree();
  const { token } = await approveFreshAccount('operator', []); // no grants at all.

  const notFound = await fetch(`${base}/api/people/org-units/999999999`, { headers: token });
  assert.strictEqual(notFound.status, 404);
  const notFoundBody = await notFound.json();

  const outOfScope = await fetch(`${base}/api/people/org-units/${child.id}`, { headers: token });
  assert.strictEqual(outOfScope.status, 403);
  const outOfScopeBody = await outOfScope.json();

  assert.notDeepStrictEqual(notFoundBody, outOfScopeBody);
});

// GET /sites/:siteId is a single fetch by id, not a list — "filter it out"
// does not apply, so it is gated (403/404) the same way a single Org Unit
// is, rather than silently omitted the way GET /sites filters its list.
test('a non-admin granted scope in Site A gets 403 fetching Site B, a Site they hold no grant within', async () => {
  const siteA = await createSiteWithTree();
  const siteB = await createSiteWithTree();
  const { token } = await approveFreshAccount('operator', [{ orgUnitId: siteA.root.id, canWrite: false }]);

  const outOfScope = await fetch(`${base}/api/people/sites/${siteB.site.id}`, { headers: token });
  assert.strictEqual(outOfScope.status, 403);

  // The caller's own Site is still reachable directly, unaffected by the
  // refusal above.
  const inScope = await fetch(`${base}/api/people/sites/${siteA.site.id}`, { headers: token });
  assert.strictEqual(inScope.status, 200);
});

test('a request for a Site id that does not exist at all gets 404, distinguishable from the 403 above', async () => {
  const siteA = await createSiteWithTree();
  const { token } = await approveFreshAccount('operator', [{ orgUnitId: siteA.root.id, canWrite: false }]);

  const notFound = await fetch(`${base}/api/people/sites/999999999`, { headers: token });
  assert.strictEqual(notFound.status, 404);
  const notFoundBody = await notFound.json();

  const outOfScope = await fetch(`${base}/api/people/sites/${(await createSiteWithTree()).site.id}`, { headers: token });
  assert.strictEqual(outOfScope.status, 403);
  const outOfScopeBody = await outOfScope.json();

  assert.notDeepStrictEqual(notFoundBody, outOfScopeBody);
});

// GET /sites/:siteId/org-units names one particular Site too, the same way
// GET /sites/:siteId does — gated the same way, rather than silently
// returning an empty 200 list that would let a caller tell "no grant in this
// Site" apart from "no grant in this Site, which does not even exist" only
// by status code.
test('a non-admin granted scope only in Site A gets 403 listing Site B\'s Org Units, not an empty 200 list', async () => {
  const siteA = await createSiteWithTree();
  const siteB = await createSiteWithTree();
  const { token } = await approveFreshAccount('operator', [{ orgUnitId: siteA.root.id, canWrite: false }]);

  const outOfScope = await fetch(`${base}/api/people/sites/${siteB.site.id}/org-units`, { headers: token });
  assert.strictEqual(outOfScope.status, 403);
});

// ---------------------------------------------------------------------------
// 5. A grant on a Site's root Org Unit reaches every unit beneath it.
// ---------------------------------------------------------------------------

test('a grant on a Site\'s root Org Unit reaches every unit beneath it', async () => {
  const { root, grandchild } = await createSiteWithTree();
  const { token } = await approveFreshAccount('operator', [{ orgUnitId: root.id, canWrite: false }]);

  const response = await fetch(`${base}/api/people/org-units/${grandchild.id}`, { headers: token });
  assert.strictEqual(response.status, 200);

  const subtree = await fetch(`${base}/api/people/org-units/${grandchild.id}/subtree`, { headers: token });
  assert.strictEqual(subtree.status, 200);
});

// ---------------------------------------------------------------------------
// 6. Read and write access are grantable separately on an Org Unit.
// ---------------------------------------------------------------------------

test('read and write access are grantable separately on an Org Unit', async () => {
  const { child } = await createSiteWithTree();
  const { token, account } = await approveFreshAccount('operator', [{ orgUnitId: child.id, canWrite: false }]);

  const read = await fetch(`${base}/api/people/org-units/${child.id}`, { headers: token });
  assert.strictEqual(read.status, 200);

  const writeDenied = await fetch(`${base}/api/people/org-units/${child.id}`, {
    method: 'PATCH',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify({ isActive: false })
  });
  assert.strictEqual(writeDenied.status, 403);

  // Re-approving replaces the grant set (service.js's own documented
  // decision) — the same Account, now with can_write true on the same unit.
  const reapprove = await approve(account.id, {
    role: 'operator',
    grants: [{ orgUnitId: child.id, canWrite: true }]
  });
  assert.strictEqual(reapprove.status, 200);

  const writeAllowed = await fetch(`${base}/api/people/org-units/${child.id}`, {
    method: 'PATCH',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify({ isActive: false })
  });
  assert.strictEqual(writeAllowed.status, 200);
});

// ---------------------------------------------------------------------------
// 7. Role and grants are read from the database on each request — a change
//    takes effect on the very next request, reusing the same token.
// ---------------------------------------------------------------------------

test('a grant change in the database takes effect on the next request, with no caching against the same token', async () => {
  const { child } = await createSiteWithTree();
  const { token, account } = await approveFreshAccount('operator', [{ orgUnitId: child.id, canWrite: false }]);

  const before = await fetch(`${base}/api/people/org-units/${child.id}`, {
    method: 'PATCH',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify({ isActive: false })
  });
  assert.strictEqual(before.status, 403);

  // Mutated directly against Postgres, bypassing every route this Module
  // exposes — proving the *server* re-reads the grant, not merely that its
  // own approval endpoint would produce a fresh read.
  await pool.query(
    'UPDATE app_user_org_units SET can_write = TRUE WHERE app_user_id = $1',
    [account.id]
  );

  const after = await fetch(`${base}/api/people/org-units/${child.id}`, {
    method: 'PATCH',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify({ isActive: false })
  });
  assert.strictEqual(after.status, 200);
});

test('a role change in the database takes effect on the next request, with no caching against the same token', async () => {
  const { token, account } = await approveFreshAccount('operator', []);

  const before = await fetch(`${base}/api/people/accounts/pending`, { headers: token });
  assert.strictEqual(before.status, 403);

  await pool.query("UPDATE app_users SET role = 'admin' WHERE id = $1", [account.id]);

  const after = await fetch(`${base}/api/people/accounts/pending`, { headers: token });
  assert.strictEqual(after.status, 200);

  // Restore, so this Account does not accidentally act as an administrator
  // in any test that runs after this one.
  await pool.query("UPDATE app_users SET role = 'operator' WHERE id = $1", [account.id]);
});

// GET /accounts exposes every Account's email, role and external_subject —
// narrowed to administrator-only by this issue's review (it predates issue
// #8, from issue #6, back when role was not yet a first-class concept).
test('listing every Account (GET /accounts) requires the administrator role', async () => {
  const { token } = await approveFreshAccount('operator', []);

  const response = await fetch(`${base}/api/people/accounts`, { headers: token });
  assert.strictEqual(response.status, 403);
});

// ---------------------------------------------------------------------------
// 8. An administrator can act across every Site.
// ---------------------------------------------------------------------------

test('an administrator can act across every Site, holding no Org Unit grant at all', async () => {
  const { rows: [{ n }] } = await pool.query(
    'SELECT count(*)::int AS n FROM app_user_org_units WHERE app_user_id = $1',
    [adminAccountId]
  );
  assert.strictEqual(n, 0);

  const { child, grandchild } = await createSiteWithTree();

  const read = await fetch(`${base}/api/people/org-units/${grandchild.id}`, { headers: adminToken });
  assert.strictEqual(read.status, 200);

  const write = await fetch(`${base}/api/people/org-units/${child.id}`, {
    method: 'PATCH',
    headers: { ...adminToken, 'content-type': 'application/json' },
    body: JSON.stringify({ isActive: false })
  });
  assert.strictEqual(write.status, 200);
});

// ---------------------------------------------------------------------------
// Enforcement on the Site/Org Unit routes issue #7 deferred to this issue.
// ---------------------------------------------------------------------------

test('creating a Site is administrator-only', async () => {
  const { token } = await approveFreshAccount('manager', []);
  const response = await fetch(`${base}/api/people/sites`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify({ code: uniqueCode('DENY'), name: 'Should not be created', timezone: 'UTC' })
  });
  assert.strictEqual(response.status, 403);
});

test('creating a root Org Unit (no parentId) is administrator-only, even for a caller with other grants', async () => {
  const { site, root } = await createSiteWithTree();
  // Granted write on the existing root, but a *root* creation names no
  // parent at all — still administrator-only.
  const { token } = await approveFreshAccount('manager', [{ orgUnitId: root.id, canWrite: true }]);

  const response = await fetch(`${base}/api/people/sites/${site.id}/org-units`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify({ code: uniqueCode('ROOT2'), name: 'Second Root', unitType: 'area' })
  });
  assert.strictEqual(response.status, 403);
});

test('creating an Org Unit under a parent requires write scope on that parent (or an ancestor)', async () => {
  const { site, root, child } = await createSiteWithTree();

  const { token: writeToken } = await approveFreshAccount('manager', [{ orgUnitId: root.id, canWrite: true }]);
  const allowed = await fetch(`${base}/api/people/sites/${site.id}/org-units`, {
    method: 'POST',
    headers: { ...writeToken, 'content-type': 'application/json' },
    body: JSON.stringify({ code: uniqueCode('OK'), name: 'Allowed Child', unitType: 'department', parentId: child.id })
  });
  assert.strictEqual(allowed.status, 201);

  const { token: readOnlyToken } = await approveFreshAccount('manager', [{ orgUnitId: root.id, canWrite: false }]);
  const denied = await fetch(`${base}/api/people/sites/${site.id}/org-units`, {
    method: 'POST',
    headers: { ...readOnlyToken, 'content-type': 'application/json' },
    body: JSON.stringify({ code: uniqueCode('DENIED'), name: 'Denied Child', unitType: 'department', parentId: child.id })
  });
  assert.strictEqual(denied.status, 403);

  const notFound = await fetch(`${base}/api/people/sites/${site.id}/org-units`, {
    method: 'POST',
    headers: { ...writeToken, 'content-type': 'application/json' },
    body: JSON.stringify({ code: uniqueCode('NF'), name: 'No Parent', unitType: 'department', parentId: '999999999' })
  });
  assert.strictEqual(notFound.status, 404);
});

test('GET /sites filters to what the caller can see; an administrator sees everything', async () => {
  const siteA = await createSiteWithTree();
  const siteB = await createSiteWithTree();
  const { token } = await approveFreshAccount('operator', [{ orgUnitId: siteA.root.id, canWrite: false }]);

  const sitesResponse = await fetch(`${base}/api/people/sites`, { headers: token });
  const { sites } = await sitesResponse.json();
  assert.ok(sites.some((s) => s.id === siteA.site.id));
  assert.ok(!sites.some((s) => s.id === siteB.site.id));

  const adminSitesResponse = await fetch(`${base}/api/people/sites`, { headers: adminToken });
  const { sites: adminSites } = await adminSitesResponse.json();
  assert.ok(adminSites.some((s) => s.id === siteA.site.id));
  assert.ok(adminSites.some((s) => s.id === siteB.site.id));
});

// Unlike the Site-level test above, this pins the per-row filter for real:
// the caller is granted one child of `root` and nothing on its sibling, and
// both are in the list this request returns (root's own children) — so the
// filter has actual work to do here, unlike granting siteA.root and then
// listing beneath siteA.root, where every returned row is beneath the grant
// regardless of whether the per-row filter runs at all. Deliberately checked
// by neutralizing plant-routes.js's per-row authorization.canAt filter and
// re-running this test to confirm it fails, then restoring it.
test("GET .../org-units filters to what the caller can see, not merely to what is beneath their grant", async () => {
  const { site, root, child } = await createSiteWithTree();

  const siblingResponse = await fetch(`${base}/api/people/sites/${site.id}/org-units`, {
    method: 'POST',
    headers: { ...adminToken, 'content-type': 'application/json' },
    body: JSON.stringify({ code: uniqueCode('SIB'), name: 'Sibling', unitType: 'department', parentId: root.id })
  });
  const { orgUnit: sibling } = await siblingResponse.json();

  // Granted on `child` only — not on `root`, and not on `sibling`.
  const { token } = await approveFreshAccount('operator', [{ orgUnitId: child.id, canWrite: false }]);

  const orgUnitsResponse = await fetch(
    `${base}/api/people/sites/${site.id}/org-units?parentId=${root.id}`,
    { headers: token }
  );
  const { orgUnits } = await orgUnitsResponse.json();
  assert.ok(orgUnits.some((ou) => ou.id === child.id));
  assert.ok(!orgUnits.some((ou) => ou.id === sibling.id));

  const adminOrgUnitsResponse = await fetch(
    `${base}/api/people/sites/${site.id}/org-units?parentId=${root.id}`,
    { headers: adminToken }
  );
  const { orgUnits: adminOrgUnits } = await adminOrgUnitsResponse.json();
  assert.ok(adminOrgUnits.some((ou) => ou.id === child.id));
  assert.ok(adminOrgUnits.some((ou) => ou.id === sibling.id));
});
