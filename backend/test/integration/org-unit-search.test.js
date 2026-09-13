/*
 * Searching a Site's Org Units by partial, case-insensitive name (issue #35,
 * CONTEXT.md's Site/Org Unit definitions), against a real database and a
 * real (locally issued) JWKS — the same seam as plant.test.js and
 * org-unit-import.test.js (see either file's own header, and the README's
 * Tests section).
 *
 * A separate file from plant.test.js, not an addition to it: this ticket's
 * own scope-leak criterion needs a non-administrator account and a direct
 * way to insert a Grant row (`app_user_org_units`), neither of which
 * plant.test.js's own fixtures set up. Modeled on org-unit-import.test.js's
 * fixture scaffolding instead — insertAccount, insertSite, insertOrgUnit,
 * insertGrant, a `process.pid`-unique uniqueCode, and a t.after/test.after
 * cleanup deleting in FK-safe order (app_user_org_units -> app_users ->
 * org_units -> sites).
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

const insertedAccountIds = [];
const insertedSiteIds = [];
const insertedOrgUnitIds = [];

let codeCounter = 0;
function uniqueCode(prefix) {
  codeCounter += 1;
  return `${prefix}${process.pid}${codeCounter}`;
}

async function authHeader(subject) {
  const token = await jwks.signToken(
    { sub: subject, email: `${subject}@example.com` },
    { issuer: ISSUER, audience: AUDIENCE }
  );
  return { authorization: `Bearer ${token}` };
}

async function insertAccount({ role = 'operator', isActive = true, approvalStatus = 'approved' } = {}) {
  const subject = uniqueCode('acct');
  const { rows: [row] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status)
     VALUES ($1, 'Org Unit Search Test Account', $2, $3, $4, $5) RETURNING id`,
    [`${subject}@example.com`, role, subject, isActive, approvalStatus]
  );
  insertedAccountIds.push(row.id);
  return { id: row.id, token: await authHeader(subject) };
}

async function insertSite() {
  const { rows: [row] } = await pool.query(
    `INSERT INTO sites (code, name, timezone) VALUES ($1, 'Org Unit Search Test Site', 'Asia/Ho_Chi_Minh') RETURNING id`,
    [uniqueCode('ST')]
  );
  insertedSiteIds.push(row.id);
  return row.id;
}

async function insertOrgUnit(siteId, { parentId = null, unitType = 'area', name = 'Org Unit Search Test Unit', code } = {}) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, $2, $3, $4, $5) RETURNING id, code, name`,
    [siteId, parentId, code ?? uniqueCode('OU'), name, unitType]
  );
  insertedOrgUnitIds.push(row.id);
  return row;
}

async function insertGrant({ accountId, orgUnitId, canWrite = false }) {
  await pool.query(
    `INSERT INTO app_user_org_units (app_user_id, org_unit_id, can_write) VALUES ($1, $2, $3)`,
    [accountId, orgUnitId, canWrite]
  );
}

let adminAccount; // administrator, no grants — orgUnitScopeFor short-circuits everywhere: true.
let inactiveAccount;

let site;
let area; // root
let grantedDept; // child of area — the non-administrator's one grant.
let otherDept; // sibling of grantedDept, same Site, ungranted.
let grantedLine; // 'Assembly Line 3' under grantedDept.
let otherLine; // identically-named 'Assembly Line 3' under otherDept.
let grantedCell; // two levels below grantedDept, under grantedLine.
let scopedAccount; // granted read access to grantedDept only.

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

  adminAccount = await insertAccount({ role: 'admin' });
  inactiveAccount = await insertAccount({ isActive: false, approvalStatus: 'pending' });

  site = await insertSite();
  area = await insertOrgUnit(site, { name: 'Area' });
  grantedDept = await insertOrgUnit(site, { parentId: area.id, name: 'Granted Dept' });
  otherDept = await insertOrgUnit(site, { parentId: area.id, name: 'Other Dept' });
  grantedLine = await insertOrgUnit(site, { parentId: grantedDept.id, unitType: 'line', name: 'Assembly Line 3' });
  otherLine = await insertOrgUnit(site, { parentId: otherDept.id, unitType: 'line', name: 'Assembly Line 3' });
  grantedCell = await insertOrgUnit(site, { parentId: grantedLine.id, unitType: 'cell', name: 'Assembly Cell 3A' });

  scopedAccount = await insertAccount();
  await insertGrant({ accountId: scopedAccount.id, orgUnitId: grantedDept.id, canWrite: false });
});

test.after(async () => {
  await pool.query('DELETE FROM app_user_org_units WHERE app_user_id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM app_users WHERE id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM org_units WHERE id = ANY($1)', [insertedOrgUnitIds]);
  await pool.query('DELETE FROM sites WHERE id = ANY($1)', [insertedSiteIds]);

  await new Promise((resolve) => server.close(resolve));
  await closePool();
  await jwks.close();
});

// ---------------------------------------------------------------------------
// Requests
// ---------------------------------------------------------------------------

async function searchRequest(siteId, query, token = adminAccount.token) {
  const qs = query === undefined ? '' : `?${query}`;
  return fetch(`${base}/api/people/sites/${siteId}/org-units/search${qs}`, { headers: token });
}

// ---------------------------------------------------------------------------
// 1. Every route here sits behind authenticate + requireActive.
// ---------------------------------------------------------------------------

test('an unauthenticated search request is refused (401)', async () => {
  const response = await fetch(`${base}/api/people/sites/${site}/org-units/search?search=x`);
  assert.strictEqual(response.status, 401);
});

test('an inactive/unapproved Account is refused (403 pending_approval)', async () => {
  const response = await searchRequest(site, 'search=x', inactiveAccount.token);
  assert.strictEqual(response.status, 403);
  const body = await response.json();
  assert.strictEqual(body.status, 'pending_approval');
});

// ---------------------------------------------------------------------------
// 4. Existence-before-scope: 404 for a Site that does not exist, 403 for one
// the caller holds no Grant within at all.
// ---------------------------------------------------------------------------

test('searching a non-existent Site is a 404', async () => {
  const response = await searchRequest(999999999, 'search=x');
  assert.strictEqual(response.status, 404);
});

test('a non-administrator searching a Site they hold no Grant in at all is a 403', async () => {
  const elsewhereSite = await insertSite();
  const response = await searchRequest(elsewhereSite, 'search=x', scopedAccount.token);
  assert.strictEqual(response.status, 403);
  const body = await response.json();
  assert.strictEqual(body.message, "Outside the caller's granted Org Units");
});

// ---------------------------------------------------------------------------
// Administrator search: exact, partial/lower-case, and several levels deep
// in one call.
// ---------------------------------------------------------------------------

test('an administrator finds an Org Unit by its exact name', async () => {
  const response = await searchRequest(site, `search=${encodeURIComponent('Area')}`);
  assert.strictEqual(response.status, 200);
  const body = await response.json();
  assert.ok(body.orgUnits.some((ou) => ou.id === area.id));
  assert.strictEqual(body.truncated, false);
});

test('an administrator finds Org Units by a partial, lower-case query', async () => {
  const response = await searchRequest(site, `search=${encodeURIComponent('assembly line')}`);
  assert.strictEqual(response.status, 200);
  const body = await response.json();
  const ids = body.orgUnits.map((ou) => ou.id).sort();
  assert.deepStrictEqual(ids.sort(), [grantedLine.id, otherLine.id].sort());
});

test('an administrator finds a cell three levels deep, in one call', async () => {
  const response = await searchRequest(site, `search=${encodeURIComponent('Assembly Cell 3A')}`);
  assert.strictEqual(response.status, 200);
  const body = await response.json();
  assert.strictEqual(body.orgUnits.length, 1);
  assert.strictEqual(body.orgUnits[0].id, grantedCell.id);
});

// ---------------------------------------------------------------------------
// 2 & 3. The scope-leak test: a non-administrator's results are limited to
// what is at or beneath one of their own Grants, and a Grant reaches its own
// Org Unit, not only descendants.
// ---------------------------------------------------------------------------

test('a non-administrator searching a name shared by a granted and an ungranted branch sees only the granted one', async () => {
  const response = await searchRequest(site, `search=${encodeURIComponent('Assembly Line 3')}`, scopedAccount.token);
  assert.strictEqual(response.status, 200);
  const body = await response.json();
  assert.strictEqual(body.orgUnits.length, 1);
  assert.strictEqual(body.orgUnits[0].id, grantedLine.id);
});

test("a non-administrator searching their own granted Org Unit's own name finds it", async () => {
  const response = await searchRequest(site, `search=${encodeURIComponent('Granted Dept')}`, scopedAccount.token);
  assert.strictEqual(response.status, 200);
  const body = await response.json();
  assert.strictEqual(body.orgUnits.length, 1);
  assert.strictEqual(body.orgUnits[0].id, grantedDept.id);
});

test('a non-administrator searching a name two levels below their Grant finds it', async () => {
  const response = await searchRequest(site, `search=${encodeURIComponent('Assembly Cell 3A')}`, scopedAccount.token);
  assert.strictEqual(response.status, 200);
  const body = await response.json();
  assert.strictEqual(body.orgUnits.length, 1);
  assert.strictEqual(body.orgUnits[0].id, grantedCell.id);
});

// ---------------------------------------------------------------------------
// 2b. Each hit carries its own ancestor names, root-first, scoped to the
// caller's Grants (issue #145, ADR-0024) — the breadcrumb #130's remaining
// criterion needs.
// ---------------------------------------------------------------------------

test('an administrator sees every ancestor name of a hit, root-first', async () => {
  const response = await searchRequest(site, `search=${encodeURIComponent('Assembly Line 3')}`);
  assert.strictEqual(response.status, 200);
  const body = await response.json();
  const byId = Object.fromEntries(body.orgUnits.map((ou) => [ou.id, ou]));
  assert.deepStrictEqual(byId[grantedLine.id].ancestors, [
    { id: String(area.id), name: 'Area' },
    { id: String(grantedDept.id), name: 'Granted Dept' }
  ]);
  assert.deepStrictEqual(byId[otherLine.id].ancestors, [
    { id: String(area.id), name: 'Area' },
    { id: String(otherDept.id), name: 'Other Dept' }
  ]);
});

test('a root-level hit carries no ancestors', async () => {
  const response = await searchRequest(site, `search=${encodeURIComponent('Area')}`);
  assert.strictEqual(response.status, 200);
  const body = await response.json();
  const rootHit = body.orgUnits.find((ou) => ou.id === area.id);
  assert.deepStrictEqual(rootHit.ancestors, []);
});

test("a non-administrator's breadcrumb never names an ancestor outside their Grants", async () => {
  const response = await searchRequest(site, `search=${encodeURIComponent('Assembly Cell 3A')}`, scopedAccount.token);
  assert.strictEqual(response.status, 200);
  const body = await response.json();
  assert.strictEqual(body.orgUnits.length, 1);
  // 'Area' sits above the caller's Grant; the chain starts at the granted
  // ancestor itself, not at the Site root.
  assert.deepStrictEqual(body.orgUnits[0].ancestors, [
    { id: String(grantedDept.id), name: 'Granted Dept' },
    { id: String(grantedLine.id), name: 'Assembly Line 3' }
  ]);
  assert.ok(!body.orgUnits[0].ancestors.some((ancestor) => ancestor.name === 'Area'));
});

// ---------------------------------------------------------------------------
// 5. Missing/empty/whitespace-only query, and a no-match query — all 200 with
// an empty result, never an error.
// ---------------------------------------------------------------------------

test('an absent search param returns 200 with an empty result', async () => {
  const response = await searchRequest(site, undefined);
  assert.strictEqual(response.status, 200);
  assert.deepStrictEqual(await response.json(), { orgUnits: [], truncated: false });
});

test('an empty search param returns 200 with an empty result', async () => {
  const response = await searchRequest(site, 'search=');
  assert.strictEqual(response.status, 200);
  assert.deepStrictEqual(await response.json(), { orgUnits: [], truncated: false });
});

test('a whitespace-only search param returns 200 with an empty result', async () => {
  const response = await searchRequest(site, `search=${encodeURIComponent('   ')}`);
  assert.strictEqual(response.status, 200);
  assert.deepStrictEqual(await response.json(), { orgUnits: [], truncated: false });
});

test('a search matching nothing returns 200 with an empty result', async () => {
  const response = await searchRequest(site, `search=${encodeURIComponent('no-such-org-unit-name-anywhere')}`);
  assert.strictEqual(response.status, 200);
  assert.deepStrictEqual(await response.json(), { orgUnits: [], truncated: false });
});

// ---------------------------------------------------------------------------
// 6. The 50-row cap, and truncated only when there really is more.
// ---------------------------------------------------------------------------

test('results are capped at 50 rows, with truncated: true when more matched', async (t) => {
  const cappedSite = await insertSite();
  t.after(async () => {
    await pool.query('DELETE FROM org_units WHERE site_id = $1', [cappedSite]);
    await pool.query('DELETE FROM sites WHERE id = $1', [cappedSite]);
  });

  for (let n = 1; n <= 55; n += 1) {
    // eslint-disable-next-line no-await-in-loop
    await insertOrgUnit(cappedSite, { name: `Capped Unit ${n}` });
  }

  const fullResponse = await searchRequest(cappedSite, `search=${encodeURIComponent('Capped Unit')}`);
  assert.strictEqual(fullResponse.status, 200);
  const fullBody = await fullResponse.json();
  assert.strictEqual(fullBody.orgUnits.length, 50);
  assert.strictEqual(fullBody.truncated, true);

  const narrowResponse = await searchRequest(cappedSite, `search=${encodeURIComponent('Capped Unit 1')}`);
  assert.strictEqual(narrowResponse.status, 200);
  const narrowBody = await narrowResponse.json();
  // "Capped Unit 1" itself, plus "Capped Unit 10".."Capped Unit 19" -> 11
  // matches (substring "Capped Unit 1", not a prefix-anchored one).
  assert.strictEqual(narrowBody.orgUnits.length, 11);
  assert.strictEqual(narrowBody.truncated, false);
});

// ---------------------------------------------------------------------------
// 7. % and _ (and \) match literally, not as SQL wildcards.
// ---------------------------------------------------------------------------

test('a literal % in the query matches literally, not as a SQL wildcard', async (t) => {
  const percentUnit = await insertOrgUnit(site, { name: '50% Line' });
  t.after(() => pool.query('DELETE FROM org_units WHERE id = $1', [percentUnit.id]));

  const response = await searchRequest(site, `search=${encodeURIComponent('50%')}`);
  assert.strictEqual(response.status, 200);
  const body = await response.json();
  assert.strictEqual(body.orgUnits.length, 1);
  assert.strictEqual(body.orgUnits[0].id, percentUnit.id);
});

// ---------------------------------------------------------------------------
// 8. Result rows have exactly toOrgUnit's existing shape.
// ---------------------------------------------------------------------------

test('a result row has exactly the existing Org Unit shape', async () => {
  const response = await searchRequest(site, `search=${encodeURIComponent('Granted Dept')}`);
  assert.strictEqual(response.status, 200);
  const body = await response.json();
  const row = body.orgUnits[0];
  assert.deepStrictEqual(Object.keys(row).sort(), [
    'ancestors', 'code', 'createdAt', 'id', 'isActive', 'name', 'parentId',
    'path', 'siteId', 'sortOrder', 'unitType', 'updatedAt'
  ].sort());
});
