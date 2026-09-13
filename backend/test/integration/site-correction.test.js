/*
 * Correcting a Site (issue #137, ADR-0025) — code, name and country code as
 * labels, and the timezone under the shift-calendar lock — against a real
 * database and a real (locally issued) JWKS, the same seam as plant.test.js
 * and org-unit-search.test.js (see either file's own header).
 *
 * A separate file from plant.test.js because the timezone-lock cases need a
 * Site that has a shift calendar, which means inserting a `shift_definitions`
 * row and a materialised `shift_instances` row directly — setup plant.test.js's
 * own fixtures do not carry. Modeled on org-unit-search.test.js's scaffolding:
 * insertAccount, insertSite, a `process.pid`-unique uniqueCode, and a
 * t.after/test.after cleanup deleting in FK-safe order (shift_instances ->
 * shift_definitions -> app_users -> org_units -> sites).
 *
 * Needs a database with every migration applied. Set DATABASE_URL first — see
 * the README's Tests section.
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
     VALUES ($1, 'Site Correction Test Account', $2, $3, $4, $5) RETURNING id`,
    [`${subject}@example.com`, role, subject, isActive, approvalStatus]
  );
  insertedAccountIds.push(row.id);
  return { id: row.id, token: await authHeader(subject) };
}

async function insertSite({ timezone = 'Asia/Ho_Chi_Minh' } = {}) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO sites (code, name, timezone)
     VALUES ($1, 'Site Correction Test Site', $2) RETURNING id, code`,
    [uniqueCode('ST'), timezone]
  );
  insertedSiteIds.push(row.id);
  return { id: row.id, code: row.code };
}

async function insertOrgUnit(siteId) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO org_units (site_id, code, name, unit_type)
     VALUES ($1, $2, 'Correction OU', 'area') RETURNING id`,
    [siteId, uniqueCode('OU')]
  );
  insertedOrgUnitIds.push(row.id);
  return row.id;
}

// A Site with a shift calendar: one shift definition and one materialised
// instance. ADR-0025's lock is about any `shift_instances` row for the Site, so
// a single instance is enough to prove it.
async function giveShiftCalendar(siteId) {
  const orgUnitId = await insertOrgUnit(siteId);
  const { rows: [definition] } = await pool.query(
    `INSERT INTO shift_definitions (site_id, code, name, start_time, duration_minutes)
     VALUES ($1, $2, 'Day', '06:00', 480) RETURNING id`,
    [siteId, uniqueCode('SHIFT')]
  );
  await pool.query(
    `INSERT INTO shift_instances (
       site_id, org_unit_id, shift_definition_id, production_date,
       starts_at, ends_at, planned_production_minutes
     ) VALUES ($1, $2, $3, '2026-01-05',
               '2026-01-05T06:00:00+07:00', '2026-01-05T14:00:00+07:00', 480)`,
    [siteId, orgUnitId, definition.id]
  );
}

let admin;
let inactive;
let operator;

async function patchSite(siteId, body, token = admin.token) {
  return fetch(`${base}/api/people/sites/${siteId}`, {
    method: 'PATCH',
    headers: { 'content-type': 'application/json', ...token },
    body: JSON.stringify(body)
  });
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

  admin = await insertAccount({ role: 'admin' });
  inactive = await insertAccount({ isActive: false, approvalStatus: 'pending' });
  operator = await insertAccount({ role: 'operator' });
});

test.after(async () => {
  await pool.query('DELETE FROM shift_instances WHERE site_id = ANY($1)', [insertedSiteIds]);
  await pool.query('DELETE FROM shift_definitions WHERE site_id = ANY($1)', [insertedSiteIds]);
  await pool.query('DELETE FROM app_users WHERE id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM org_units WHERE id = ANY($1)', [insertedOrgUnitIds]);
  await pool.query('DELETE FROM sites WHERE id = ANY($1)', [insertedSiteIds]);

  await new Promise((resolve) => server.close(resolve));
  await closePool();
  await jwks.close();
});

// ---------------------------------------------------------------------------
// Authentication / authorisation, existence before scope
// ---------------------------------------------------------------------------

test('an unauthenticated correction is refused (401)', async () => {
  const site = await insertSite();
  const response = await fetch(`${base}/api/people/sites/${site.id}`, {
    method: 'PATCH',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ code: site.code, name: 'X', timezone: 'Asia/Ho_Chi_Minh' })
  });
  assert.strictEqual(response.status, 401);
});

test('an inactive/unapproved Account is refused (403 pending_approval)', async () => {
  const site = await insertSite();
  const response = await patchSite(
    site.id,
    { code: site.code, name: 'X', timezone: 'Asia/Ho_Chi_Minh' },
    inactive.token
  );
  assert.strictEqual(response.status, 403);
  assert.strictEqual((await response.json()).status, 'pending_approval');
});

test('a non-administrator is refused (403) once the Site is known to exist', async () => {
  const site = await insertSite();
  const response = await patchSite(
    site.id,
    { code: site.code, name: 'X', timezone: 'Asia/Ho_Chi_Minh' },
    operator.token
  );
  assert.strictEqual(response.status, 403);
  assert.strictEqual((await response.json()).message, 'This action requires the administrator role.');
});

test('an unknown Site id is a 404', async () => {
  const response = await patchSite(999999999, {
    code: 'X',
    name: 'X',
    timezone: 'Asia/Ho_Chi_Minh'
  });
  assert.strictEqual(response.status, 404);
});

test('a malformed Site id is a 404, not a 500', async () => {
  const response = await patchSite('not-an-id', {
    code: 'X',
    name: 'X',
    timezone: 'Asia/Ho_Chi_Minh'
  });
  assert.strictEqual(response.status, 404);
});

test('an unknown Site id is a 404 for a non-administrator too, never a 403', async () => {
  const response = await patchSite(
    999999999,
    { code: 'X', name: 'X', timezone: 'Asia/Ho_Chi_Minh' },
    operator.token
  );
  assert.strictEqual(response.status, 404);
});

// ---------------------------------------------------------------------------
// Labels: code, name and country code are always correctable
// ---------------------------------------------------------------------------

test('an administrator corrects a Site code, name and country code', async () => {
  const site = await insertSite();
  const response = await patchSite(site.id, {
    code: uniqueCode('NEW'),
    name: 'Corrected Name',
    timezone: 'Asia/Ho_Chi_Minh',
    countryCode: 'VN'
  });
  assert.strictEqual(response.status, 200);
  const { site: updated } = await response.json();
  assert.strictEqual(updated.name, 'Corrected Name');
  assert.strictEqual(updated.countryCode, 'VN');
});

test('correcting a code to one already in use is refused (409)', async () => {
  const first = await insertSite();
  const second = await insertSite();
  const response = await patchSite(second.id, {
    code: first.code,
    name: 'X',
    timezone: 'Asia/Ho_Chi_Minh'
  });
  assert.strictEqual(response.status, 409);
});

test('a correction with no code is refused (400)', async () => {
  const site = await insertSite();
  const response = await patchSite(site.id, {
    code: '',
    name: 'X',
    timezone: 'Asia/Ho_Chi_Minh'
  });
  assert.strictEqual(response.status, 400);
});

// ---------------------------------------------------------------------------
// Timezone: allowed while no shift calendar exists, refused once one does
// ---------------------------------------------------------------------------

test('an administrator corrects the timezone while the Site has no shift calendar', async () => {
  const site = await insertSite({ timezone: 'UTC' });
  const response = await patchSite(site.id, {
    code: site.code,
    name: 'Site Correction Test Site',
    timezone: 'Europe/London'
  });
  assert.strictEqual(response.status, 200);
  assert.strictEqual((await response.json()).site.timezone, 'Europe/London');
});

test('correcting to an unknown timezone is refused (400)', async () => {
  const site = await insertSite();
  const response = await patchSite(site.id, {
    code: site.code,
    name: 'Site Correction Test Site',
    timezone: 'Not/AZone'
  });
  assert.strictEqual(response.status, 400);
});

test('a Site that has a shift calendar cannot have its timezone corrected (409)', async () => {
  const site = await insertSite({ timezone: 'UTC' });
  await giveShiftCalendar(site.id);

  const response = await patchSite(site.id, {
    code: site.code,
    name: 'Site Correction Test Site',
    timezone: 'Europe/London'
  });
  assert.strictEqual(response.status, 409);

  // Nothing was written: the whole correction is refused, zone unchanged.
  const { rows: [row] } = await pool.query('SELECT timezone FROM sites WHERE id = $1', [site.id]);
  assert.strictEqual(row.timezone, 'UTC');
});

test('a Site that has a shift calendar can still have its labels corrected', async () => {
  const site = await insertSite({ timezone: 'UTC' });
  await giveShiftCalendar(site.id);

  const response = await patchSite(site.id, {
    code: site.code,
    name: 'Renamed With Calendar',
    timezone: 'UTC'
  });
  assert.strictEqual(response.status, 200);
  assert.strictEqual((await response.json()).site.name, 'Renamed With Calendar');
});
