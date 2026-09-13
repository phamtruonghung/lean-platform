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

async function reject(id, token = adminToken, body) {
  return fetch(`${base}/api/people/accounts/${id}/rejection`, {
    method: 'POST',
    headers: body ? { ...token, 'content-type': 'application/json' } : token,
    body: body ? JSON.stringify(body) : undefined
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

// ---------------------------------------------------------------------------
// 9. Root-level GET .../org-units returns a non-administrator's own entry
//    points into the Site's tree, not the Site's root Org Units — issue #24,
//    ADR-0008. A grant reaches downward only, so an Account granted a single
//    deep Org Unit would otherwise have every root filtered out by canAct
//    and see an empty list: their own branch, unreachable by navigating down
//    from the top even though it is real and reachable directly by id.
// ---------------------------------------------------------------------------

test('an Account granted only a deep Org Unit gets it back as an entry point at root level, and can navigate downward from it', async () => {
  const { site, grandchild } = await createSiteWithTree();

  const leafResponse = await fetch(`${base}/api/people/sites/${site.id}/org-units`, {
    method: 'POST',
    headers: { ...adminToken, 'content-type': 'application/json' },
    body: JSON.stringify({ code: uniqueCode('LEAF'), name: 'Leaf', unitType: 'work_center', parentId: grandchild.id })
  });
  const { orgUnit: leaf } = await leafResponse.json();

  const { token } = await approveFreshAccount('operator', [{ orgUnitId: grandchild.id, canWrite: false }]);

  const rootLevel = await fetch(`${base}/api/people/sites/${site.id}/org-units`, { headers: token });
  assert.strictEqual(rootLevel.status, 200);
  const rootLevelBody = await rootLevel.json();
  assert.deepStrictEqual(rootLevelBody.orgUnits.map((ou) => ou.id), [grandchild.id]);

  // Navigating downward from the entry point works exactly like navigating
  // down from any other Org Unit's id.
  const children = await fetch(
    `${base}/api/people/sites/${site.id}/org-units?parentId=${grandchild.id}`,
    { headers: token }
  );
  assert.strictEqual(children.status, 200);
  const childrenBody = await children.json();
  assert.deepStrictEqual(childrenBody.orgUnits.map((ou) => ou.id), [leaf.id]);
});

// Neither `child` nor `grandchild` is the Site's own root, so this pins the
// dedup logic itself rather than something the old root-Org-Units filter
// would happen to get right anyway: granted only `root`, the old behaviour
// (Site roots filtered by canAct) would already answer `[root]` by
// coincidence, telling nothing apart from a correct entry-points
// implementation. Granted `child` and its own descendant `grandchild`
// instead, the old behaviour returns an empty list (neither is a Site
// root), and a naive entry-points implementation with no dedup would return
// both — only the fixed, topmost-only behaviour answers `[child]` alone.
test('overlapping grants — a unit and one of its own descendants both granted directly — return only the topmost entry point', async () => {
  const { site, child, grandchild } = await createSiteWithTree();
  const { token } = await approveFreshAccount('operator', [
    { orgUnitId: child.id, canWrite: false },
    { orgUnitId: grandchild.id, canWrite: true }
  ]);

  const response = await fetch(`${base}/api/people/sites/${site.id}/org-units`, { headers: token });
  assert.strictEqual(response.status, 200);
  const { orgUnits } = await response.json();
  assert.deepStrictEqual(orgUnits.map((ou) => ou.id), [child.id]);
});

test("an administrator's root-level view is unchanged: the Site's root Org Units, regardless of any grant", async () => {
  const { site, root, grandchild } = await createSiteWithTree();
  // Irrelevant to an administrator's own view — present only to prove the
  // administrator branch never even asks about it.
  await approveFreshAccount('operator', [{ orgUnitId: grandchild.id, canWrite: false }]);

  const response = await fetch(`${base}/api/people/sites/${site.id}/org-units`, { headers: adminToken });
  assert.strictEqual(response.status, 200);
  const { orgUnits } = await response.json();
  assert.deepStrictEqual(orgUnits.map((ou) => ou.id), [root.id]);
});

test("an Account granted a Site's root Org Unit still gets that root back at root level (no regression)", async () => {
  const { site, root } = await createSiteWithTree();
  const { token } = await approveFreshAccount('operator', [{ orgUnitId: root.id, canWrite: false }]);

  const response = await fetch(`${base}/api/people/sites/${site.id}/org-units`, { headers: token });
  assert.strictEqual(response.status, 200);
  const { orgUnits } = await response.json();
  assert.deepStrictEqual(orgUnits.map((ou) => ou.id), [root.id]);
});

// This pins that the new entry-points branch sits *behind* requireSiteScope
// and does not bypass its gate: an Account with no grant anywhere in this
// Site is refused there before ever reaching authorization.
// grantedEntryPointIds, not handed an empty 200 list by it. The broader
// 403-vs-empty-200 rule itself is already pinned earlier in this file ("a
// non-admin granted scope only in Site A gets 403 listing Site B's Org
// Units, not an empty 200 list") — this test is a guard on the new
// root-level branch specifically, not a restatement of that one.
test('an Account with no grant anywhere in the Site still gets 403 at root level, not an empty 200 (requireSiteScope unaffected)', async () => {
  const { site } = await createSiteWithTree();
  const { token } = await approveFreshAccount('operator', []); // no grants at all.

  const response = await fetch(`${base}/api/people/sites/${site.id}/org-units`, { headers: token });
  assert.strictEqual(response.status, 403);
});

// ADR-0008's own worked example: the one case where this generalisation
// actually changes output, not merely restates the old behaviour or lands on
// an empty list either way. Granted rootA (already a Site root — unaffected
// on its own, per the no-regression test above) plus a deep unit under a
// second, ungranted root B in the same Site, the old code answered [rootA]
// only: rootB was never granted so never passed canAct, and the deep grant
// beneath it was invisible for the same downward-only reason issue #24
// raises in the first place. Both are genuine entry points now — the deep
// grant under the ungranted root B is exactly the branch that used to be a
// dead end — while rootB itself, never granted, still is not returned.
test('an Account granted a Site root plus a deep unit under a second, ungranted root sees both entry points', async () => {
  const { site, root: rootA } = await createSiteWithTree();

  const rootBResponse = await fetch(`${base}/api/people/sites/${site.id}/org-units`, {
    method: 'POST',
    headers: { ...adminToken, 'content-type': 'application/json' },
    body: JSON.stringify({ code: uniqueCode('ROOTB'), name: 'Root B', unitType: 'area' })
  });
  const { orgUnit: rootB } = await rootBResponse.json();

  const deepUnderBResponse = await fetch(`${base}/api/people/sites/${site.id}/org-units`, {
    method: 'POST',
    headers: { ...adminToken, 'content-type': 'application/json' },
    body: JSON.stringify({
      code: uniqueCode('DEEPB'),
      name: 'Deep Under Root B',
      unitType: 'department',
      parentId: rootB.id
    })
  });
  const { orgUnit: deepUnderB } = await deepUnderBResponse.json();

  const { token } = await approveFreshAccount('operator', [
    { orgUnitId: rootA.id, canWrite: false },
    { orgUnitId: deepUnderB.id, canWrite: false }
  ]);

  const response = await fetch(`${base}/api/people/sites/${site.id}/org-units`, { headers: token });
  assert.strictEqual(response.status, 200);
  const { orgUnits } = await response.json();
  const ids = orgUnits.map((ou) => ou.id);
  assert.ok(ids.includes(rootA.id));
  assert.ok(ids.includes(deepUnderB.id));
  assert.ok(!ids.includes(rootB.id));
  assert.strictEqual(ids.length, 2);
});


// ---------------------------------------------------------------------------
// 10. The Approval queue Screen's own needs (issue #40): a wait that can be
//     shown, and a rejection that refuses to overwrite another
//     administrator's decision.
// ---------------------------------------------------------------------------

test('a queued Account carries when it started waiting, so a client can show how long', async () => {
  const before = new Date();
  const { account: pending } = await createPendingAccount('waiting');

  const response = await fetch(`${base}/api/people/accounts/pending`, { headers: adminToken });
  const { accounts } = await response.json();
  const queued = accounts.find((a) => a.id === pending.id);

  assert.ok(queued.createdAt, 'a queued Account carries createdAt');
  const createdAt = new Date(queued.createdAt);
  assert.ok(!Number.isNaN(createdAt.getTime()), 'createdAt parses as a date');
  // Within a sane window of this test's own clock — enough to prove it is
  // this Account's own creation time and not a constant.
  assert.ok(createdAt >= new Date(before.getTime() - 60_000));
  assert.ok(createdAt <= new Date(Date.now() + 60_000));
});

test('rejecting with a precondition that still holds succeeds', async () => {
  const { account: pending } = await createPendingAccount('precond-ok');

  const response = await reject(pending.id, adminToken, { expectedApprovalStatus: 'pending' });
  assert.strictEqual(response.status, 200);
  const { account } = await response.json();
  assert.strictEqual(account.approvalStatus, 'rejected');
});

test('rejecting an Account another administrator already dealt with is a 409, and changes nothing', async () => {
  const { account: pending } = await createPendingAccount('precond-race');

  // The other administrator gets there first.
  const approved = await approve(pending.id, { role: 'operator', grants: [] });
  assert.strictEqual(approved.status, 200);

  const response = await reject(pending.id, adminToken, { expectedApprovalStatus: 'pending' });
  assert.strictEqual(response.status, 409);
  const body = await response.json();
  assert.match(body.message, /already dealt with/);
  // Issue #119: distinct from the three Employee-link refusal codes
  // (employee-link.test.js), so a client can tell "someone else already
  // decided this row" apart from "the Employee link was refused" without
  // matching on either message's own wording.
  assert.strictEqual(body.code, 'APPROVAL_STATUS_CHANGED');

  // Not a partial write: the Approval the other administrator made stands.
  const { rows: [row] } = await pool.query(
    'SELECT approval_status, is_active FROM app_users WHERE id = $1',
    [pending.id]
  );
  assert.strictEqual(row.approval_status, 'approved');
  assert.strictEqual(row.is_active, true);
});

test('the precondition is optional — an unconditional rejection is unchanged', async () => {
  const { account } = await approveFreshAccount('operator', []);

  const response = await reject(account.id);
  assert.strictEqual(response.status, 200);
  const body = await response.json();
  assert.strictEqual(body.account.approvalStatus, 'rejected');
});

test('an unknown expectedApprovalStatus is a 400, not a silent unconditional rejection', async () => {
  const { account: pending } = await createPendingAccount('precond-bad');

  const response = await reject(pending.id, adminToken, { expectedApprovalStatus: 'maybe' });
  assert.strictEqual(response.status, 400);

  const { rows: [row] } = await pool.query(
    'SELECT approval_status FROM app_users WHERE id = $1',
    [pending.id]
  );
  assert.strictEqual(row.approval_status, 'pending');
});

// The same precondition, on the *approval* side (issue #41): admitting an
// Account is the other half of the queue's race, and a stale row must not let
// one administrator's Approval silently overwrite another's decision.
test('approving with a precondition that still holds succeeds', async () => {
  const { account: pending } = await createPendingAccount('appr-precond-ok');

  const response = await approve(pending.id, {
    role: 'admin',
    grants: [],
    expectedApprovalStatus: 'pending'
  });
  assert.strictEqual(response.status, 200);
  const { account } = await response.json();
  assert.strictEqual(account.approvalStatus, 'approved');
  assert.strictEqual(account.role, 'admin');
  assert.strictEqual(account.isActive, true);

  const { rows } = await pool.query(
    'SELECT 1 FROM app_user_org_units WHERE app_user_id = $1',
    [pending.id]
  );
  assert.strictEqual(rows.length, 0, 'an administrator is admitted with no Grants at all');
});

test('approving an Account another administrator already dealt with is a 409, and changes nothing', async () => {
  const { account: pending } = await createPendingAccount('appr-precond-race');

  const rejected = await reject(pending.id);
  assert.strictEqual(rejected.status, 200);

  const response = await approve(pending.id, {
    role: 'manager',
    grants: [],
    expectedApprovalStatus: 'pending'
  });
  assert.strictEqual(response.status, 409);
  const body = await response.json();
  assert.match(body.message, /already dealt with/);
  assert.strictEqual(body.code, 'APPROVAL_STATUS_CHANGED');

  const { rows: [row] } = await pool.query(
    'SELECT approval_status, is_active, role FROM app_users WHERE id = $1',
    [pending.id]
  );
  assert.strictEqual(row.approval_status, 'rejected');
  assert.strictEqual(row.is_active, false);
  assert.strictEqual(row.role, 'operator');
});

test('the approval precondition is optional — an unconditional Approval is unchanged', async () => {
  const { account: pending } = await createPendingAccount('appr-precond-absent');

  const response = await approve(pending.id, { role: 'engineer', grants: [] });
  assert.strictEqual(response.status, 200);
  const { account } = await response.json();
  assert.strictEqual(account.approvalStatus, 'approved');
  assert.strictEqual(account.role, 'engineer');
});

test('an unknown expectedApprovalStatus on an Approval is a 400, not a silent unconditional Approval', async () => {
  const { account: pending } = await createPendingAccount('appr-precond-bad');

  const response = await approve(pending.id, {
    role: 'manager',
    grants: [],
    expectedApprovalStatus: 'maybe'
  });
  assert.strictEqual(response.status, 400);

  const { rows: [row] } = await pool.query(
    'SELECT approval_status, role FROM app_users WHERE id = $1',
    [pending.id]
  );
  assert.strictEqual(row.approval_status, 'pending');
  assert.strictEqual(row.role, 'operator');
});

// Issue #36: the accounts listing is where an administrator sees what an
// admitted Account currently holds, and where a correction starts from —
// which needs the whole existing Grant set on the row, not just its role.
test('the accounts listing carries each Account\'s current Grants, named, with the Site each sits in', async () => {
  const { site, root, child } = await createSiteWithTree();
  const { account } = await approveFreshAccount('supervisor', [
    { orgUnitId: root.id, canWrite: true },
    { orgUnitId: child.id, canWrite: false }
  ]);

  const response = await fetch(`${base}/api/people/accounts`, { headers: adminToken });
  assert.strictEqual(response.status, 200);
  const { accounts } = await response.json();

  const row = accounts.find((a) => a.id === account.id);
  assert.ok(row, 'the admitted Account is in the listing');
  assert.strictEqual(row.role, 'supervisor');
  assert.strictEqual(row.approvalStatus, 'approved');
  assert.strictEqual(row.isActive, true);
  assert.strictEqual(row.grants.length, 2);

  const rootGrant = row.grants.find((g) => String(g.orgUnitId) === String(root.id));
  assert.strictEqual(rootGrant.name, 'Root');
  assert.strictEqual(rootGrant.code, root.code);
  assert.strictEqual(rootGrant.unitType, 'area');
  assert.strictEqual(String(rootGrant.siteId), String(site.id));
  assert.strictEqual(rootGrant.siteName, 'Approval Test Site');
  assert.strictEqual(rootGrant.parentId, null);
  assert.strictEqual(rootGrant.canWrite, true);

  const childGrant = row.grants.find((g) => String(g.orgUnitId) === String(child.id));
  assert.strictEqual(childGrant.canWrite, false);
  assert.strictEqual(String(childGrant.parentId), String(root.id));
});

// An administrator holds no grant rows at all, so its own listing row must say
// so with an empty array rather than a missing field a client has to guess at.
test('an Account with no Grants comes back with an empty grants array, never undefined', async () => {
  const { account } = await approveFreshAccount('operator', []);

  const response = await fetch(`${base}/api/people/accounts`, { headers: adminToken });
  const { accounts } = await response.json();
  const row = accounts.find((a) => a.id === account.id);
  assert.deepStrictEqual(row.grants, []);
});

// The correction the Screen actually performs: re-running the admission act on
// an already-approved Account with the standing it was read with as the
// precondition, replacing the whole Grant set rather than adding to it.
test('correcting an admitted Account replaces its whole Grant set, and the listing shows the new one', async () => {
  const { root, child, grandchild } = await createSiteWithTree();
  const { account } = await approveFreshAccount('supervisor', [
    { orgUnitId: root.id, canWrite: true },
    { orgUnitId: child.id, canWrite: true }
  ]);

  const corrected = await approve(account.id, {
    role: 'engineer',
    grants: [{ orgUnitId: grandchild.id, canWrite: false }],
    expectedApprovalStatus: 'approved'
  });
  assert.strictEqual(corrected.status, 200);

  const response = await fetch(`${base}/api/people/accounts`, { headers: adminToken });
  const { accounts } = await response.json();
  const row = accounts.find((a) => a.id === account.id);
  assert.strictEqual(row.role, 'engineer');
  assert.strictEqual(row.grants.length, 1);
  assert.strictEqual(String(row.grants[0].orgUnitId), String(grandchild.id));
});

// The precondition the Screen sends is what turns "another administrator got
// there first" into a 409 the Screen can report and re-read from.
test('a correction whose precondition no longer holds is a 409, and writes nothing', async () => {
  const { account } = await approveFreshAccount('operator', []);
  const stale = await approve(account.id, {
    role: 'manager',
    grants: [],
    expectedApprovalStatus: 'pending'
  });
  assert.strictEqual(stale.status, 409);

  const { rows: [row] } = await pool.query('SELECT role FROM app_users WHERE id = $1', [account.id]);
  assert.strictEqual(row.role, 'operator');
});

test('re-approving an already-approved Account still works when no precondition is sent', async () => {
  const { account } = await approveFreshAccount('operator', []);

  const response = await approve(account.id, { role: 'manager', grants: [] });
  assert.strictEqual(response.status, 200);
  const body = await response.json();
  assert.strictEqual(body.account.role, 'manager');
});

// ---------------------------------------------------------------------------
// 11. GET /me's own orgUnitScope (issue #43) — where the caller may work,
//     distinct from status/account. "everywhere" for an administrator, raw
//     Grant rows for everyone else, and an empty grant list must never be
//     mistaken for "everywhere" the other way around.
// ---------------------------------------------------------------------------

test('an administrator\'s /me says everywhere: true, with no grants', async () => {
  const response = await me(adminToken);
  assert.strictEqual(response.status, 200);
  const body = await response.json();
  assert.deepStrictEqual(body.orgUnitScope, { everywhere: true, grants: [] });
});

test('a non-administrator with one Grant gets everywhere: false and that one Grant back, raw', async () => {
  const { root } = await createSiteWithTree();
  const { token } = await approveFreshAccount('supervisor', [{ orgUnitId: root.id, canWrite: true }]);

  const response = await me(token);
  assert.strictEqual(response.status, 200);
  const { orgUnitScope } = await response.json();
  assert.strictEqual(orgUnitScope.everywhere, false);
  assert.strictEqual(orgUnitScope.grants.length, 1);
  const [grant] = orgUnitScope.grants;
  assert.strictEqual(String(grant.orgUnitId), String(root.id));
  assert.strictEqual(String(grant.siteId), String(root.siteId));
  assert.strictEqual(grant.canWrite, true);
});

// The pair to the administrator test above: the same empty grants list, but
// distinguishable by everywhere alone — this is exactly the ambiguity issue
// #43 exists to rule out.
test('a non-administrator with no Grants at all gets everywhere: false and an empty grants list — distinguishable from an administrator only by everywhere', async () => {
  const { token } = await approveFreshAccount('operator', []);

  const response = await me(token);
  assert.strictEqual(response.status, 200);
  const { orgUnitScope } = await response.json();
  assert.strictEqual(orgUnitScope.everywhere, false);
  assert.deepStrictEqual(orgUnitScope.grants, []);
});

test('a root Org Unit and a descendant beneath it, both granted directly, both come back — raw rows, not collapsed entry points', async () => {
  const { root, child } = await createSiteWithTree();
  const { token } = await approveFreshAccount('operator', [
    { orgUnitId: root.id, canWrite: false },
    { orgUnitId: child.id, canWrite: true }
  ]);

  const response = await me(token);
  assert.strictEqual(response.status, 200);
  const { orgUnitScope } = await response.json();
  assert.strictEqual(orgUnitScope.everywhere, false);
  assert.strictEqual(orgUnitScope.grants.length, 2);
  const grantedIds = orgUnitScope.grants.map((g) => String(g.orgUnitId)).sort();
  assert.deepStrictEqual(grantedIds, [String(root.id), String(child.id)].sort());
});

// Issue #110: a Grant alone says which Org Unit was granted, not which Org
// Units that Grant *reaches* — a Grant reaches downward (CONTEXT.md's Grant,
// ADR-0008), so a client counting work "on my Org Units" cannot tell from the
// raw rows alone that a descendant sits inside a Grant. /me therefore carries
// each Grant's own reach, the granted unit plus every descendant, so the
// client matches ids instead of walking the tree.
test('a Grant reports the Org Units it reaches — the granted unit and every descendant beneath it', async () => {
  const { root, child, grandchild } = await createSiteWithTree();
  const { token } = await approveFreshAccount('supervisor', [
    { orgUnitId: root.id, canWrite: true }
  ]);

  const response = await me(token);
  assert.strictEqual(response.status, 200);
  const { orgUnitScope } = await response.json();
  const [grant] = orgUnitScope.grants;
  assert.strictEqual(grant.canWrite, true);
  assert.deepStrictEqual(
    grant.orgUnitIds.map(String).sort(),
    [String(root.id), String(child.id), String(grandchild.id)].sort()
  );
});

// The other half of the same rule, pinned deliberately: a Grant reaches
// downward only, so a Grant on the child names the child and its descendants
// but never the root above it. Without this, a bug that returned the whole
// Site's Org Units would pass the test above.
test('a deep Grant reaches downward only — its reach never names an ancestor above it', async () => {
  const { root, child, grandchild } = await createSiteWithTree();
  const { token } = await approveFreshAccount('supervisor', [
    { orgUnitId: child.id, canWrite: true }
  ]);

  const response = await me(token);
  assert.strictEqual(response.status, 200);
  const { orgUnitScope } = await response.json();
  const [grant] = orgUnitScope.grants;
  assert.deepStrictEqual(
    grant.orgUnitIds.map(String).sort(),
    [String(child.id), String(grandchild.id)].sort()
  );
  assert.ok(!grant.orgUnitIds.map(String).includes(String(root.id)));
});

// ---------------------------------------------------------------------------
// Issue #53: an administrator cannot act on their own Account.
// ---------------------------------------------------------------------------

test('an administrator cannot deactivate their own Account', async () => {
  const response = await patchAccount(adminAccountId, { isActive: false });
  assert.strictEqual(response.status, 403);
  const body = await response.json();
  assert.match(body.message, /their own Account/);

  const { rows: [row] } = await pool.query('SELECT is_active FROM app_users WHERE id = $1', [adminAccountId]);
  assert.strictEqual(row.is_active, true);
});

test('an administrator cannot demote their own Account away from admin', async () => {
  const response = await approve(adminAccountId, { role: 'operator', grants: [] });
  assert.strictEqual(response.status, 403);

  const { rows: [row] } = await pool.query('SELECT role FROM app_users WHERE id = $1', [adminAccountId]);
  assert.strictEqual(row.role, 'admin');

  const { rows: grants } = await pool.query(
    'SELECT 1 FROM app_user_org_units WHERE app_user_id = $1',
    [adminAccountId]
  );
  assert.strictEqual(grants.length, 0);
});

test('an administrator cannot re-approve their own Account even as admin — the rule is unconditional, not just demotions', async () => {
  const response = await approve(adminAccountId, { role: 'admin', grants: [] });
  assert.strictEqual(response.status, 403);
});

test('an administrator cannot reject their own Account', async () => {
  const response = await reject(adminAccountId);
  assert.strictEqual(response.status, 403);

  const { rows: [row] } = await pool.query(
    'SELECT approval_status, is_active FROM app_users WHERE id = $1',
    [adminAccountId]
  );
  assert.strictEqual(row.approval_status, 'approved');
  assert.strictEqual(row.is_active, true);
});

test('the self-action refusal happens before body validation', async () => {
  // The route's own "isActive (boolean) is required" check runs before the
  // service function — and therefore before refuseSelfAction — is ever
  // reached, so a self-action with no isActive at all is the route's
  // ordinary 400, not the service's 403.
  const missingBody = await patchAccount(adminAccountId, {});
  assert.strictEqual(missingBody.status, 400);

  // approveAccount, by contrast, runs refuseSelfAction as its own first
  // statement, ahead of its own role-validity check — so an unknown role
  // against the caller's own Account is still the self-action 403, not the
  // 400 an unknown role would otherwise get against any other Account.
  const badRole = await approve(adminAccountId, { role: 'nonsense', grants: [] });
  assert.strictEqual(badRole.status, 403);
});

test('a second administrator can still deactivate the first — the rule is about identity, not the admin role', async () => {
  const { token: secondAdminToken } = await approveFreshAccount('admin', []);

  const deactivate = await patchAccount(adminAccountId, { isActive: false }, secondAdminToken);
  assert.strictEqual(deactivate.status, 200);

  // Reactivated in the same test: adminAccountId/adminToken are shared by
  // the whole file, and leaving it deactivated would break every later test
  // that relies on adminToken passing requireActive.
  const reactivate = await patchAccount(adminAccountId, { isActive: true }, secondAdminToken);
  assert.strictEqual(reactivate.status, 200);
});
