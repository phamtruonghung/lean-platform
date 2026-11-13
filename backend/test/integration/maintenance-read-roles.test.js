/*
 * Maintenance reads keep the audience they had before the ADR-0061 retrofit,
 * over HTTP against a real database — the same seam as the sibling
 * maintenance files, whose fixture scaffolding this one follows.
 *
 * Why this file exists. Every fixture in the rest of the Maintenance suite
 * inserts `role: 'supervisor'`, and the seeded Supervisor role carries all
 * four `…_DISPLAY` codes. So "the existing suite still passes" cannot, on its
 * own, prove that the retrofit refused nobody: a read narrowed to supervisor
 * and above would leave that suite green. This file asks the question as the
 * Account that would notice first — an operator, who holds the default group
 * (ROLE_STANDARD) and nothing else.
 *
 * The reads asserted here are shared reference data rather than a Screen's own
 * private list, so gating them with the Screen's code narrows Screens that are
 * not asking the question. The user-visible consequence the review measured is
 * the last test: raising a Maintenance Request requires naming an Asset, so an
 * operator who cannot read the Asset register cannot raise one at all.
 */

const test = require('node:test');
const assert = require('node:assert');
const { tokenFor } = require('../helpers/session');

let server;
let base;
let pool;
let closePool;

const accountIds = [];
const siteIds = [];
const orgUnitIds = [];
const assetIds = [];
const storeIds = [];
const requestIds = [];

let counter = 0;
function uniqueCode(prefix) {
  counter += 1;
  return `${prefix}${process.pid}${counter}`;
}

async function authHeader(subject) {
  const token = await tokenFor(subject);
  return { authorization: `Bearer ${token}` };
}

async function insertAccount({ role }) {
  const subject = uniqueCode('acct');
  const { rows: [row] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status)
     VALUES ($1, 'Read Roles Test Account', $2, $3, true, 'approved') RETURNING id`,
    [`${subject}@example.com`, role, subject]
  );
  accountIds.push(row.id);
  return { id: row.id, role, token: await authHeader(subject) };
}

async function insertGrant({ accountId, orgUnitId, canWrite = false }) {
  await pool.query(
    `INSERT INTO app_user_org_units (app_user_id, org_unit_id, can_write) VALUES ($1, $2, $3)`,
    [accountId, orgUnitId, canWrite]
  );
}

async function insertSite() {
  const { rows: [row] } = await pool.query(
    `INSERT INTO sites (code, name, timezone) VALUES ($1, 'Read Roles Test Site', 'Asia/Ho_Chi_Minh') RETURNING id`,
    [uniqueCode('ST')]
  );
  siteIds.push(row.id);
  return row.id;
}

async function insertOrgUnit(siteId) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, NULL, $2, 'Read Roles Test Unit', 'area') RETURNING id`,
    [siteId, uniqueCode('OU')]
  );
  orgUnitIds.push(row.id);
  return row.id;
}

async function insertAsset(orgUnitId) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO assets (org_unit_id, code, name, asset_type, criticality)
     VALUES ($1, $2, 'Read Roles Press', 'machine', 'high') RETURNING id`,
    [orgUnitId, uniqueCode('AS')]
  );
  assetIds.push(row.id);
  return row.id;
}

async function insertStore({ siteId, orgUnitId }) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO stores (site_id, org_unit_id, code, name)
     VALUES ($1, $2, $3, 'Read Roles Store') RETURNING id`,
    [siteId, orgUnitId, uniqueCode('SR')]
  );
  storeIds.push(row.id);
  return row.id;
}

async function get(path, token) {
  const response = await fetch(`${base}${path}`, { headers: token });
  const payload = await response.json().catch(() => null);
  return { response, payload };
}

let operator;   // role operator: the default group only.
let supervisor; // role supervisor: carries the Maintenance …_DISPLAY codes.
let siteId;
let orgUnitId;
let assetId;
let storeId;

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

  operator = await insertAccount({ role: 'operator' });
  supervisor = await insertAccount({ role: 'supervisor' });

  siteId = await insertSite();
  orgUnitId = await insertOrgUnit(siteId);
  assetId = await insertAsset(orgUnitId);
  storeId = await insertStore({ siteId, orgUnitId });

  // The supervisor can write at this Org Unit — not needed by the reads
  // below, but it keeps the fixture honest for the gated meters read: that
  // route is refused on the code, not on scope, so a Grant cannot mask it.
  await insertGrant({ accountId: supervisor.id, orgUnitId, canWrite: true });
  // An operator works the line it is granted: a READ Grant is what lets it
  // raise a Request against an Asset there (raising asks a question, so it
  // needs `write: false`), and it plays no part in any read above — those are
  // Site-wide by decision, not scope'd.
  await insertGrant({ accountId: operator.id, orgUnitId, canWrite: false });
});

test.after(async () => {
  await pool.query('DELETE FROM maintenance_requests WHERE id = ANY($1)', [requestIds]);
  await pool.query('DELETE FROM stock_movements WHERE store_id = ANY($1)', [storeIds]);
  await pool.query('DELETE FROM stores WHERE id = ANY($1)', [storeIds]);
  await pool.query('DELETE FROM assets WHERE id = ANY($1)', [assetIds]);
  await pool.query('DELETE FROM app_user_org_units WHERE app_user_id = ANY($1)', [accountIds]);
  await pool.query('DELETE FROM app_users WHERE id = ANY($1)', [accountIds]);
  await pool.query('DELETE FROM org_units WHERE id = ANY($1)', [orgUnitIds]);
  await pool.query('DELETE FROM sites WHERE id = ANY($1)', [siteIds]);
  await new Promise((resolve) => server.close(resolve));
  await closePool();
});

// ---------------------------------------------------------------------------
// The shared reads the retrofit must not narrow: an operator could reach all
// of them before ADR-0061 and still does.
// ---------------------------------------------------------------------------

const sharedReads = [
  ['the Asset register', () => `/api/maintenance/sites/${siteId}/assets`],
  ['the unit-of-measure catalogue', () => '/api/maintenance/units-of-measure'],
  ['the parts catalogue', () => '/api/maintenance/parts'],
  ['the Site’s stores', () => `/api/maintenance/sites/${siteId}/stores`],
  ['one store', () => `/api/maintenance/stores/${storeId}`],
  ['a store’s stock', () => `/api/maintenance/stores/${storeId}/stock`],
  ['a store’s movements', () => `/api/maintenance/stores/${storeId}/movements`]
];

for (const [label, path] of sharedReads) {
  test(`an operator reads ${label} — the retrofit refused nobody`, async () => {
    const { response, payload } = await get(path(), operator.token);
    assert.strictEqual(response.status, 200, `${label}: ${JSON.stringify(payload)}`);
  });

  test(`a supervisor reads ${label}`, async () => {
    const { response, payload } = await get(path(), supervisor.token);
    assert.strictEqual(response.status, 200, `${label}: ${JSON.stringify(payload)}`);
  });
}

// ---------------------------------------------------------------------------
// A Screen's own read is still gated by that Screen's code. This is the other
// half of "permission = what": removing the shared reads must not remove the
// retrofit itself, and the difference between the two is exactly the point.
// ---------------------------------------------------------------------------

test('the Meters Screen’s own read still asks MTN_METERS_DISPLAY', async () => {
  const asSupervisor = await get(`/api/maintenance/sites/${siteId}/meters`, supervisor.token);
  assert.strictEqual(asSupervisor.response.status, 200, JSON.stringify(asSupervisor.payload));

  const asOperator = await get(`/api/maintenance/sites/${siteId}/meters`, operator.token);
  assert.strictEqual(asOperator.response.status, 403, JSON.stringify(asOperator.payload));
  assert.strictEqual(asOperator.payload.code, 'PERMISSION_REQUIRED');
});

// ---------------------------------------------------------------------------
// The consequence the review measured: raising a Request names an Asset, so a
// register an operator cannot read is a Request an operator cannot raise.
// ---------------------------------------------------------------------------

test('an operator raises a Maintenance Request against an Asset it can read', async () => {
  const listed = await get(`/api/maintenance/sites/${siteId}/assets`, operator.token);
  assert.strictEqual(listed.response.status, 200);
  assert.ok(
    listed.payload.assets.some((asset) => asset.id === assetId),
    'the Asset the Request names must be on the list the form draws from'
  );

  const response = await fetch(`${base}/api/maintenance/requests`, {
    method: 'POST',
    headers: { ...operator.token, 'content-type': 'application/json' },
    body: JSON.stringify({ assetId, summary: 'Guard is loose on the press' })
  });
  const payload = await response.json().catch(() => null);
  if (payload?.request?.id) requestIds.push(payload.request.id);

  assert.strictEqual(response.status, 201, JSON.stringify(payload));
  assert.strictEqual(payload.request.assetId, assetId);
});
