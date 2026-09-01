/*
 * Sites and the Org Unit tree, over HTTP (issue #7), against a real database
 * and a real (locally issued) JWKS — the same seam as accounts.test.js (see
 * that file's own header, and the README's Tests section).
 *
 * Unlike accounts.test.js, this file does not truncate `app_users`: that
 * table is shared with accounts.test.js's own "the first Account becomes
 * administrator" assertion, and `node --test` runs test files concurrently
 * by default, so two files truncating the same table would race each other.
 * Instead this file inserts its own `app_users` rows directly — an active
 * one and an inactive one, each under a subject unique to this process
 * (`process.pid`) — and signs tokens whose `sub` matches. `authenticate()`
 * resolves an existing `external_subject` straight to that row (see
 * service.js's `findAccountBySubject`), so this reaches the same code path
 * a real sign-in would without depending on being first through an empty
 * table. Every row this file inserts, in `app_users`, `sites` and
 * `org_units`, is deleted again in `test.after()`/`t.after()`.
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
let inactiveToken;
const insertedAccountIds = [];

let codeCounter = 0;
// Unique across processes (process.pid) and within one run (the counter),
// so tests that create several Sites/Org Units never collide on the
// `(site_id, code)` / `sites.code` UNIQUE constraints.
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

  const adminSubject = `plant-admin-${process.pid}`;
  const inactiveSubject = `plant-inactive-${process.pid}`;

  const { rows: [admin] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active)
     VALUES ($1, 'Plant Test Admin', 'admin', $2, TRUE) RETURNING id`,
    [`${adminSubject}@example.com`, adminSubject]
  );
  const { rows: [inactive] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active)
     VALUES ($1, 'Plant Test Inactive', 'operator', $2, FALSE) RETURNING id`,
    [`${inactiveSubject}@example.com`, inactiveSubject]
  );
  insertedAccountIds.push(admin.id, inactive.id);

  adminToken = await authHeader(adminSubject);
  inactiveToken = await authHeader(inactiveSubject);
});

test.after(async () => {
  await pool.query('DELETE FROM app_users WHERE id = ANY($1)', [insertedAccountIds]);
  await new Promise((resolve) => server.close(resolve));
  await closePool();
  await jwks.close();
});

async function createSite(overrides = {}) {
  const response = await fetch(`${base}/api/people/sites`, {
    method: 'POST',
    headers: { ...adminToken, 'content-type': 'application/json' },
    body: JSON.stringify({
      code: uniqueCode('ST'),
      name: 'Plant Test Site',
      timezone: 'Asia/Ho_Chi_Minh',
      ...overrides
    })
  });
  return response;
}

async function createOrgUnit(siteId, overrides = {}) {
  const response = await fetch(`${base}/api/people/sites/${siteId}/org-units`, {
    method: 'POST',
    headers: { ...adminToken, 'content-type': 'application/json' },
    body: JSON.stringify({
      code: uniqueCode('OU'),
      name: 'Plant Test Org Unit',
      unitType: 'area',
      ...overrides
    })
  });
  return response;
}

// ---------------------------------------------------------------------------
// 1. Every route here sits behind authenticate + requireActive.
// ---------------------------------------------------------------------------

test('a request with no bearer token is refused', async () => {
  const response = await fetch(`${base}/api/people/sites`);
  assert.strictEqual(response.status, 401);
});

test('an inactive Account is refused, with a status the app can distinguish from a failure', async () => {
  const response = await fetch(`${base}/api/people/sites`, { headers: inactiveToken });
  assert.strictEqual(response.status, 403);
  const body = await response.json();
  assert.strictEqual(body.status, 'pending_approval');
});

// ---------------------------------------------------------------------------
// 2. An administrator creates a Site with a code, a name and a time zone —
//    and it round-trips, since nothing that resolves a shift or a
//    production day exists yet to consume the timezone directly.
// ---------------------------------------------------------------------------

test('an administrator creates a Site, and its time zone round-trips', async (t) => {
  const code = uniqueCode('ST');
  const response = await createSite({ code, name: 'Plant Test Site', timezone: 'Asia/Ho_Chi_Minh', countryCode: 'VN' });
  assert.strictEqual(response.status, 201);

  const { site } = await response.json();
  t.after(() => pool.query('DELETE FROM sites WHERE id = $1', [site.id]));

  assert.strictEqual(site.code, code);
  assert.strictEqual(site.name, 'Plant Test Site');
  assert.strictEqual(site.timezone, 'Asia/Ho_Chi_Minh');
  assert.strictEqual(site.countryCode, 'VN');
  assert.strictEqual(site.isActive, true);

  const fetched = await fetch(`${base}/api/people/sites/${site.id}`, { headers: adminToken });
  assert.strictEqual(fetched.status, 200);
  const fetchedBody = await fetched.json();
  assert.strictEqual(fetchedBody.site.timezone, 'Asia/Ho_Chi_Minh');

  const list = await fetch(`${base}/api/people/sites`, { headers: adminToken });
  const listBody = await list.json();
  assert.ok(listBody.sites.some((s) => s.id === site.id && s.timezone === 'Asia/Ho_Chi_Minh'));
});

test('creating a Site with an unknown time zone is rejected', async () => {
  const response = await createSite({ timezone: 'Not/AZone' });
  assert.strictEqual(response.status, 400);
});

test('creating a Site with no code is rejected', async () => {
  const response = await createSite({ code: '' });
  assert.strictEqual(response.status, 400);
});

test('creating a Site with a code that already exists is rejected', async (t) => {
  const code = uniqueCode('ST');
  const first = await createSite({ code });
  const { site } = await first.json();
  t.after(() => pool.query('DELETE FROM sites WHERE id = $1', [site.id]));

  const second = await createSite({ code });
  assert.strictEqual(second.status, 409);
});

test('a non-existent Site is a 404, not a 500', async () => {
  const response = await fetch(`${base}/api/people/sites/999999999`, { headers: adminToken });
  assert.strictEqual(response.status, 404);
});

// ---------------------------------------------------------------------------
// 3. An administrator builds a Site's Org Unit tree across every unit type,
//    the tree can be browsed from the Site down to a work centre, and
//    everything beneath a given Org Unit is retrievable in one request.
// ---------------------------------------------------------------------------

test('a Site\'s Org Unit tree spans every unit type, is browsable one level at a time, and is retrievable whole from any point', async (t) => {
  const siteResponse = await createSite();
  const { site } = await siteResponse.json();
  // One combined hook, org_units before its Site (no ON DELETE CASCADE onto
  // sites) — t.after() hooks run in registration order, not reverse, so
  // registering the Site's own delete separately and later would still run
  // it first.
  t.after(async () => {
    await pool.query('DELETE FROM org_units WHERE site_id = $1', [site.id]);
    await pool.query('DELETE FROM sites WHERE id = $1', [site.id]);
  });

  const chain = [
    { unitType: 'area', name: 'Area 1' },
    { unitType: 'department', name: 'Department 1' },
    { unitType: 'line', name: 'Line 1' },
    { unitType: 'cell', name: 'Cell 1' },
    { unitType: 'work_center', name: 'Work Centre 1' }
  ];

  const created = [];
  let parentId;
  for (const step of chain) {
    // eslint-disable-next-line no-await-in-loop
    const response = await createOrgUnit(site.id, { ...step, parentId });
    assert.strictEqual(response.status, 201, `creating a ${step.unitType} should succeed`);
    // eslint-disable-next-line no-await-in-loop
    const { orgUnit } = await response.json();
    assert.strictEqual(orgUnit.unitType, step.unitType);
    assert.strictEqual(orgUnit.parentId, parentId ?? null);
    created.push(orgUnit);
    parentId = orgUnit.id;
  }

  const [area, department, line, cell, workCenter] = created;

  // Browsed one level at a time, from the Site down to the work centre.
  const rootResponse = await fetch(`${base}/api/people/sites/${site.id}/org-units`, { headers: adminToken });
  const rootBody = await rootResponse.json();
  assert.deepStrictEqual(rootBody.orgUnits.map((ou) => ou.id), [area.id]);

  const departmentResponse = await fetch(
    `${base}/api/people/sites/${site.id}/org-units?parentId=${area.id}`,
    { headers: adminToken }
  );
  const departmentBody = await departmentResponse.json();
  assert.deepStrictEqual(departmentBody.orgUnits.map((ou) => ou.id), [department.id]);

  const workCenterChildren = await fetch(
    `${base}/api/people/sites/${site.id}/org-units?parentId=${workCenter.id}`,
    { headers: adminToken }
  );
  const workCenterChildrenBody = await workCenterChildren.json();
  assert.deepStrictEqual(workCenterChildrenBody.orgUnits, []);

  // Everything beneath the Area, in a single request.
  const subtreeResponse = await fetch(`${base}/api/people/org-units/${area.id}/subtree`, { headers: adminToken });
  assert.strictEqual(subtreeResponse.status, 200);
  const subtreeBody = await subtreeResponse.json();
  assert.deepStrictEqual(
    subtreeBody.orgUnits.map((ou) => ({ id: ou.id, depth: ou.depth })),
    [area, department, line, cell, workCenter].map((ou, i) => ({ id: ou.id, depth: i }))
  );

  // And from the cell down: only the cell and the work centre beneath it,
  // not their ancestors and not any sibling of an ancestor.
  const cellSubtree = await fetch(`${base}/api/people/org-units/${cell.id}/subtree`, { headers: adminToken });
  const cellSubtreeBody = await cellSubtree.json();
  assert.deepStrictEqual(cellSubtreeBody.orgUnits.map((ou) => ou.id), [cell.id, workCenter.id]);
});

test('creating an Org Unit under a non-existent Site is a 404', async () => {
  const response = await createOrgUnit(999999999);
  assert.strictEqual(response.status, 404);
});

test('creating an Org Unit with an unknown unit type is rejected', async (t) => {
  const siteResponse = await createSite();
  const { site } = await siteResponse.json();
  t.after(() => pool.query('DELETE FROM sites WHERE id = $1', [site.id]));

  const response = await createOrgUnit(site.id, { unitType: 'planet' });
  assert.strictEqual(response.status, 400);
});

test('an Org Unit cannot be parented to an Org Unit from a different Site', async (t) => {
  const site1 = (await (await createSite()).json()).site;
  const site2 = (await (await createSite()).json()).site;
  t.after(async () => {
    await pool.query('DELETE FROM org_units WHERE site_id = ANY($1)', [[site1.id, site2.id]]);
    await pool.query('DELETE FROM sites WHERE id = ANY($1)', [[site1.id, site2.id]]);
  });

  const areaInSite1 = (await (await createOrgUnit(site1.id)).json()).orgUnit;
  const response = await createOrgUnit(site2.id, { parentId: areaInSite1.id });
  assert.strictEqual(response.status, 400);
});

test('an Org Unit code must be unique within its Site, not globally', async (t) => {
  const site1 = (await (await createSite()).json()).site;
  const site2 = (await (await createSite()).json()).site;
  t.after(async () => {
    await pool.query('DELETE FROM org_units WHERE site_id = ANY($1)', [[site1.id, site2.id]]);
    await pool.query('DELETE FROM sites WHERE id = ANY($1)', [[site1.id, site2.id]]);
  });

  const code = uniqueCode('OU');
  const first = await createOrgUnit(site1.id, { code });
  assert.strictEqual(first.status, 201);

  // Same code, different Site: allowed.
  const second = await createOrgUnit(site2.id, { code });
  assert.strictEqual(second.status, 201);

  // Same code, same Site: rejected.
  const third = await createOrgUnit(site1.id, { code });
  assert.strictEqual(third.status, 409);
});

// ---------------------------------------------------------------------------
// 4. An Org Unit can be deactivated without being deleted, and stays
//    readable afterwards.
// ---------------------------------------------------------------------------

test('an Org Unit can be deactivated without being deleted, and stays readable', async (t) => {
  const site = (await (await createSite()).json()).site;
  const orgUnit = (await (await createOrgUnit(site.id)).json()).orgUnit;
  t.after(async () => {
    await pool.query('DELETE FROM org_units WHERE id = $1', [orgUnit.id]);
    await pool.query('DELETE FROM sites WHERE id = $1', [site.id]);
  });

  const deactivate = await fetch(`${base}/api/people/org-units/${orgUnit.id}`, {
    method: 'PATCH',
    headers: { ...adminToken, 'content-type': 'application/json' },
    body: JSON.stringify({ isActive: false })
  });
  assert.strictEqual(deactivate.status, 200);
  const deactivateBody = await deactivate.json();
  assert.strictEqual(deactivateBody.orgUnit.isActive, false);

  // Still readable — deactivation is a flag, not a delete.
  const fetched = await fetch(`${base}/api/people/org-units/${orgUnit.id}`, { headers: adminToken });
  assert.strictEqual(fetched.status, 200);
  const fetchedBody = await fetched.json();
  assert.strictEqual(fetchedBody.orgUnit.id, orgUnit.id);
  assert.strictEqual(fetchedBody.orgUnit.isActive, false);

  const stillInRow = await pool.query('SELECT is_active FROM org_units WHERE id = $1', [orgUnit.id]);
  assert.strictEqual(stillInRow.rows.length, 1);
  assert.strictEqual(stillInRow.rows[0].is_active, false);
});

test('PATCHing an Org Unit without a boolean isActive is rejected', async (t) => {
  const site = (await (await createSite()).json()).site;
  const orgUnit = (await (await createOrgUnit(site.id)).json()).orgUnit;
  t.after(async () => {
    await pool.query('DELETE FROM org_units WHERE id = $1', [orgUnit.id]);
    await pool.query('DELETE FROM sites WHERE id = $1', [site.id]);
  });

  const response = await fetch(`${base}/api/people/org-units/${orgUnit.id}`, {
    method: 'PATCH',
    headers: { ...adminToken, 'content-type': 'application/json' },
    body: JSON.stringify({})
  });
  assert.strictEqual(response.status, 400);
});
