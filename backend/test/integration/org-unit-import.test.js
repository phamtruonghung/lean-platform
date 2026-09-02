/*
 * Bulk Org Unit import (issue #12, CONTEXT.md's Site/Org Unit definitions and
 * the Import vocabulary entry), against a real database and a real (locally
 * issued) JWKS — the same seam as plant.test.js and assignments.test.js (see
 * either file's own header, and the README's Tests section).
 *
 * Like assignments.test.js, this file needs `app_user_org_units` rows: one of
 * the import route's own acceptance criteria (issue #12, criterion 5) is that
 * an import is refused wholesale when any row falls outside the caller's
 * granted Org Unit scope, which needs a caller with a write grant on one Org
 * Unit and none on another to exercise both sides of that refusal.
 *
 * This file does not truncate `app_users`, `sites` or `org_units`: all are
 * shared with the other integration files, and `npm run test:integration`
 * runs every file with `--test-concurrency=1`, so a truncate here would still
 * corrupt whichever file ran first. Instead this file inserts its own rows
 * under a `process.pid`-unique `uniqueCode`, the same device the other
 * integration files use, for every UNIQUE constraint value it touches
 * (`sites.code`, `(site_id, code)` on `org_units`, `external_subject` on
 * `app_users`). Every row inserted — across `app_users`, `app_user_org_units`,
 * `sites` and `org_units` — is deleted again in `test.after()`/`t.after()`.
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
     VALUES ($1, 'Import Test Account', $2, $3, $4, $5) RETURNING id`,
    [`${subject}@example.com`, role, subject, isActive, approvalStatus]
  );
  insertedAccountIds.push(row.id);
  return { id: row.id, token: await authHeader(subject) };
}

async function insertSite() {
  const { rows: [row] } = await pool.query(
    `INSERT INTO sites (code, name, timezone) VALUES ($1, 'Import Test Site', 'Asia/Ho_Chi_Minh') RETURNING id`,
    [uniqueCode('ST')]
  );
  insertedSiteIds.push(row.id);
  return row.id;
}

async function insertOrgUnit(siteId, { parentId = null, unitType = 'area', name = 'Import Test Org Unit', code } = {}) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, $2, $3, $4, $5) RETURNING id, code`,
    [siteId, parentId, code ?? uniqueCode('OU'), name, unitType]
  );
  insertedOrgUnitIds.push(row.id);
  return row;
}

async function insertGrant({ accountId, orgUnitId, canWrite }) {
  await pool.query(
    `INSERT INTO app_user_org_units (app_user_id, org_unit_id, can_write) VALUES ($1, $2, $3)`,
    [accountId, orgUnitId, canWrite]
  );
}

let adminAccount; // administrator, no grants — canAct short-circuits true.
let inactiveAccount;

let scopeSite;
let scopeUnit; // an existing Org Unit the scoped non-admin can write under.
let elsewhereUnit; // an existing Org Unit at the same Site the scoped non-admin cannot write under.
let scopedAccount; // can_write = TRUE on scopeUnit only.

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

  scopeSite = await insertSite();
  scopeUnit = await insertOrgUnit(scopeSite, { name: 'Scope Unit' });
  elsewhereUnit = await insertOrgUnit(scopeSite, { name: 'Elsewhere Unit' });

  scopedAccount = await insertAccount();
  await insertGrant({ accountId: scopedAccount.id, orgUnitId: scopeUnit.id, canWrite: true });
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

async function importRequest(siteId, body, token = adminAccount.token) {
  return fetch(`${base}/api/people/sites/${siteId}/org-units/import`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
}

async function createOrgUnitRequest(siteId, body, token = adminAccount.token) {
  return fetch(`${base}/api/people/sites/${siteId}/org-units`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
}

async function orgUnitCountAtSite(siteId, codes) {
  const { rows } = await pool.query(
    'SELECT count(*)::int AS n FROM org_units WHERE site_id = $1 AND code = ANY($2)',
    [siteId, codes]
  );
  return rows[0].n;
}

// ---------------------------------------------------------------------------
// 1. Every route here sits behind authenticate + requireActive.
// ---------------------------------------------------------------------------

test('an unauthenticated import request is refused (401)', async (t) => {
  const site = await insertSite();
  t.after(() => pool.query('DELETE FROM sites WHERE id = $1', [site]));

  const response = await fetch(`${base}/api/people/sites/${site}/org-units/import`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ orgUnits: [] })
  });
  assert.strictEqual(response.status, 401);
});

test('an inactive/unapproved Account is refused (403)', async (t) => {
  const site = await insertSite();
  t.after(() => pool.query('DELETE FROM sites WHERE id = $1', [site]));

  const response = await importRequest(site, { orgUnits: [] }, inactiveAccount.token);
  assert.strictEqual(response.status, 403);
});

test('importing into a non-existent Site is a 404', async () => {
  const response = await importRequest(999999999, { orgUnits: [{ code: 'X', name: 'X', unitType: 'area' }] });
  assert.strictEqual(response.status, 404);
});

// ---------------------------------------------------------------------------
// 2 & 3. A valid import creates the whole hierarchy, in one call.
// ---------------------------------------------------------------------------

test('an administrator imports a 3-level hierarchy in one call, and the subtree proves the whole tree exists with correct parentage', async (t) => {
  const site = await insertSite();
  t.after(async () => {
    await pool.query('DELETE FROM org_units WHERE site_id = $1', [site]);
    await pool.query('DELETE FROM sites WHERE id = $1', [site]);
  });

  const areaCode = uniqueCode('AREA');
  const lineCode = uniqueCode('LINE');
  const cellCode = uniqueCode('CELL');

  const response = await importRequest(site, {
    orgUnits: [
      { code: areaCode, name: 'Assembly', unitType: 'area', parentCode: null, sortOrder: 0 },
      { code: lineCode, name: 'Line 1', unitType: 'line', parentCode: areaCode },
      { code: cellCode, name: 'Cell 1', unitType: 'cell', parentCode: lineCode }
    ]
  });
  assert.strictEqual(response.status, 201);
  const { orgUnits } = await response.json();
  assert.strictEqual(orgUnits.length, 3);

  const area = orgUnits.find((ou) => ou.code === areaCode);
  const line = orgUnits.find((ou) => ou.code === lineCode);
  const cell = orgUnits.find((ou) => ou.code === cellCode);
  assert.ok(area && line && cell);
  assert.strictEqual(area.parentId, null);
  assert.strictEqual(line.parentId, area.id);
  assert.strictEqual(cell.parentId, line.id);

  const subtreeResponse = await fetch(`${base}/api/people/org-units/${area.id}/subtree`, { headers: adminAccount.token });
  assert.strictEqual(subtreeResponse.status, 200);
  const subtreeBody = await subtreeResponse.json();
  assert.deepStrictEqual(
    subtreeBody.orgUnits.map((ou) => ({ id: ou.id, depth: ou.depth })),
    [
      { id: area.id, depth: 0 },
      { id: line.id, depth: 1 },
      { id: cell.id, depth: 2 }
    ]
  );
});

test('an import whose rows hang off an existing Org Unit succeeds', async (t) => {
  const site = await insertSite();
  const existing = await insertOrgUnit(site, { name: 'Existing Root' });
  t.after(async () => {
    await pool.query('DELETE FROM org_units WHERE site_id = $1', [site]);
    await pool.query('DELETE FROM sites WHERE id = $1', [site]);
  });

  const childCode = uniqueCode('CHILD');
  const response = await importRequest(site, {
    orgUnits: [{ code: childCode, name: 'New Child', unitType: 'line', parentCode: existing.code }]
  });
  assert.strictEqual(response.status, 201);
  const { orgUnits } = await response.json();
  assert.strictEqual(orgUnits.length, 1);
  assert.strictEqual(orgUnits[0].parentId, existing.id);
});

// ---------------------------------------------------------------------------
// 3 & 4. A failed import applies none of it, and reports which rows were
// invalid and why, row by row.
// ---------------------------------------------------------------------------

test('one invalid row among several is a 422 naming the right row, and none of the valid rows were created', async (t) => {
  const site = await insertSite();
  t.after(async () => {
    await pool.query('DELETE FROM org_units WHERE site_id = $1', [site]);
    await pool.query('DELETE FROM sites WHERE id = $1', [site]);
  });

  const goodCode1 = uniqueCode('GOOD');
  const goodCode2 = uniqueCode('GOOD');

  const response = await importRequest(site, {
    orgUnits: [
      { code: goodCode1, name: 'Good One', unitType: 'area' },
      { code: goodCode2, name: 'Missing Type', unitType: 'not-a-real-type' }
    ]
  });
  assert.strictEqual(response.status, 422);
  const body = await response.json();
  assert.ok(Array.isArray(body.errors));
  assert.strictEqual(body.errors.length, 1);
  assert.strictEqual(body.errors[0].row, 1);
  assert.strictEqual(body.errors[0].field, 'unitType');

  const count = await orgUnitCountAtSite(site, [goodCode1, goodCode2]);
  assert.strictEqual(count, 0, 'nothing should have been created — not even the valid row');
});

test('multiple different invalid rows are all reported in one response, row by row', async (t) => {
  const site = await insertSite();
  t.after(async () => {
    await pool.query('DELETE FROM org_units WHERE site_id = $1', [site]);
    await pool.query('DELETE FROM sites WHERE id = $1', [site]);
  });

  const response = await importRequest(site, {
    orgUnits: [
      { code: '', name: 'No Code', unitType: 'area' },
      { code: uniqueCode('BAD'), name: '', unitType: 'area' },
      { code: uniqueCode('BAD'), name: 'Bad Sort', unitType: 'area', sortOrder: 'not-a-number' }
    ]
  });
  assert.strictEqual(response.status, 422);
  const body = await response.json();
  const rows = body.errors.map((e) => e.row).sort();
  assert.deepStrictEqual(rows, [0, 1, 2]);
  assert.ok(body.errors.some((e) => e.row === 0 && e.field === 'code'));
  assert.ok(body.errors.some((e) => e.row === 1 && e.field === 'name'));
  assert.ok(body.errors.some((e) => e.row === 2 && e.field === 'sortOrder'));
});

test('a duplicate code within the payload is a 422 naming both rows', async (t) => {
  const site = await insertSite();
  t.after(async () => {
    await pool.query('DELETE FROM org_units WHERE site_id = $1', [site]);
    await pool.query('DELETE FROM sites WHERE id = $1', [site]);
  });

  const dupCode = uniqueCode('DUP');
  const response = await importRequest(site, {
    orgUnits: [
      { code: dupCode, name: 'First', unitType: 'area' },
      { code: dupCode, name: 'Second', unitType: 'area' }
    ]
  });
  assert.strictEqual(response.status, 422);
  const body = await response.json();
  const rows = body.errors.filter((e) => e.field === 'code').map((e) => e.row).sort();
  assert.deepStrictEqual(rows, [0, 1]);

  const count = await orgUnitCountAtSite(site, [dupCode]);
  assert.strictEqual(count, 0);
});

test('a code colliding with an existing Org Unit at this Site is a 422', async (t) => {
  const site = await insertSite();
  const existing = await insertOrgUnit(site, { name: 'Already There' });
  t.after(async () => {
    await pool.query('DELETE FROM org_units WHERE site_id = $1', [site]);
    await pool.query('DELETE FROM sites WHERE id = $1', [site]);
  });

  const response = await importRequest(site, {
    orgUnits: [{ code: existing.code, name: 'Collides', unitType: 'area' }]
  });
  assert.strictEqual(response.status, 422);
  const body = await response.json();
  assert.strictEqual(body.errors.length, 1);
  assert.strictEqual(body.errors[0].row, 0);
  assert.strictEqual(body.errors[0].field, 'code');
});

test('an unknown parentCode is a 422', async (t) => {
  const site = await insertSite();
  t.after(async () => {
    await pool.query('DELETE FROM org_units WHERE site_id = $1', [site]);
    await pool.query('DELETE FROM sites WHERE id = $1', [site]);
  });

  const response = await importRequest(site, {
    orgUnits: [{ code: uniqueCode('X'), name: 'Orphan', unitType: 'area', parentCode: 'NOPE-DOES-NOT-EXIST' }]
  });
  assert.strictEqual(response.status, 422);
  const body = await response.json();
  assert.strictEqual(body.errors.length, 1);
  assert.strictEqual(body.errors[0].row, 0);
  assert.strictEqual(body.errors[0].field, 'parentCode');
});

test('a cycle among payload rows (A parent B, B parent A) is a 422', async (t) => {
  const site = await insertSite();
  t.after(async () => {
    await pool.query('DELETE FROM org_units WHERE site_id = $1', [site]);
    await pool.query('DELETE FROM sites WHERE id = $1', [site]);
  });

  const codeA = uniqueCode('A');
  const codeB = uniqueCode('B');
  const response = await importRequest(site, {
    orgUnits: [
      { code: codeA, name: 'A', unitType: 'area', parentCode: codeB },
      { code: codeB, name: 'B', unitType: 'area', parentCode: codeA }
    ]
  });
  assert.strictEqual(response.status, 422);
  const body = await response.json();
  const rows = body.errors.map((e) => e.row).sort();
  assert.deepStrictEqual(rows, [0, 1]);
});

test('a row that parents itself is a 422', async (t) => {
  const site = await insertSite();
  t.after(async () => {
    await pool.query('DELETE FROM org_units WHERE site_id = $1', [site]);
    await pool.query('DELETE FROM sites WHERE id = $1', [site]);
  });

  const code = uniqueCode('SELF');
  const response = await importRequest(site, {
    orgUnits: [{ code, name: 'Self Parent', unitType: 'area', parentCode: code }]
  });
  assert.strictEqual(response.status, 422);
  const body = await response.json();
  assert.strictEqual(body.errors.length, 1);
  assert.strictEqual(body.errors[0].row, 0);
});

// ---------------------------------------------------------------------------
// 5. Scope: refused outside the caller's granted Org Units, and nothing
// applied.
// ---------------------------------------------------------------------------

test('a non-admin with write scope on one Org Unit can import under it (201)', async () => {
  const code = uniqueCode('UNDER');
  const response = await importRequest(
    scopeSite,
    { orgUnits: [{ code, name: 'Scoped Child', unitType: 'line', parentCode: scopeUnit.code }] },
    scopedAccount.token
  );
  assert.strictEqual(response.status, 201);
  const { orgUnits } = await response.json();
  insertedOrgUnitIds.push(orgUnits[0].id);
});

test('an import containing a row under an out-of-scope Org Unit is refused (403), and nothing is created', async () => {
  const inScopeCode = uniqueCode('INSCOPE');
  const outOfScopeCode = uniqueCode('OUTSCOPE');

  const response = await importRequest(
    scopeSite,
    {
      orgUnits: [
        { code: inScopeCode, name: 'In Scope', unitType: 'line', parentCode: scopeUnit.code },
        { code: outOfScopeCode, name: 'Out Of Scope', unitType: 'line', parentCode: elsewhereUnit.code }
      ]
    },
    scopedAccount.token
  );
  assert.strictEqual(response.status, 403);
  const body = await response.json();
  assert.match(body.message, /granted Org Unit/i);

  const count = await orgUnitCountAtSite(scopeSite, [inScopeCode, outOfScopeCode]);
  assert.strictEqual(count, 0, 'neither row should have been created');
});

test('a non-admin importing a root row (no parentCode) is refused (403)', async () => {
  const code = uniqueCode('ROOT');
  const response = await importRequest(
    scopeSite,
    { orgUnits: [{ code, name: 'New Root', unitType: 'area' }] },
    scopedAccount.token
  );
  assert.strictEqual(response.status, 403);

  const count = await orgUnitCountAtSite(scopeSite, [code]);
  assert.strictEqual(count, 0);
});

// ---------------------------------------------------------------------------
// Malformed envelope.
// ---------------------------------------------------------------------------

test('a malformed envelope (missing orgUnits) is a 400', async (t) => {
  const site = await insertSite();
  t.after(() => pool.query('DELETE FROM sites WHERE id = $1', [site]));

  const response = await importRequest(site, {});
  assert.strictEqual(response.status, 400);
});

test('a malformed envelope (orgUnits not an array) is a 400', async (t) => {
  const site = await insertSite();
  t.after(() => pool.query('DELETE FROM sites WHERE id = $1', [site]));

  const response = await importRequest(site, { orgUnits: 'not-an-array' });
  assert.strictEqual(response.status, 400);
});

test('a malformed envelope (empty orgUnits array) is a 400', async (t) => {
  const site = await insertSite();
  t.after(() => pool.query('DELETE FROM sites WHERE id = $1', [site]));

  const response = await importRequest(site, { orgUnits: [] });
  assert.strictEqual(response.status, 400);
});

// ---------------------------------------------------------------------------
// Regression: the plain create route still works alongside /import.
// ---------------------------------------------------------------------------

test('POST /sites/:siteId/org-units (the plain create route) still works', async (t) => {
  const site = await insertSite();
  t.after(async () => {
    await pool.query('DELETE FROM org_units WHERE site_id = $1', [site]);
    await pool.query('DELETE FROM sites WHERE id = $1', [site]);
  });

  const response = await createOrgUnitRequest(site, { code: uniqueCode('PLAIN'), name: 'Plain Create', unitType: 'area' });
  assert.strictEqual(response.status, 201);
  const { orgUnit } = await response.json();
  assert.strictEqual(orgUnit.parentId, null);
});
