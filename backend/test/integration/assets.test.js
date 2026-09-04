/*
 * The Asset register over HTTP (issue #56), against a real database and a
 * real (locally issued) JWKS — the same seam as plant.test.js and
 * org-unit-search.test.js. Fixture scaffolding is modelled on
 * org-unit-search.test.js: this ticket needs a non-administrator with a real
 * Grant row, which plant.test.js's own fixtures do not set up.
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
const insertedAssetIds = [];

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

async function insertAccount({ role = 'supervisor', isActive = true, approvalStatus = 'approved' } = {}) {
  const subject = uniqueCode('acct');
  const { rows: [row] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status)
     VALUES ($1, 'Asset Test Account', $2, $3, $4, $5) RETURNING id`,
    [`${subject}@example.com`, role, subject, isActive, approvalStatus]
  );
  insertedAccountIds.push(row.id);
  return { id: row.id, token: await authHeader(subject) };
}

async function insertSite() {
  const { rows: [row] } = await pool.query(
    `INSERT INTO sites (code, name, timezone) VALUES ($1, 'Asset Test Site', 'Asia/Ho_Chi_Minh') RETURNING id`,
    [uniqueCode('ST')]
  );
  insertedSiteIds.push(row.id);
  return row.id;
}

async function insertOrgUnit(siteId, { parentId = null, unitType = 'area', name = 'Asset Test Unit' } = {}) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, $2, $3, $4, $5) RETURNING id, code, name`,
    [siteId, parentId, uniqueCode('OU'), name, unitType]
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

async function postAsset(token, body) {
  const response = await fetch(`${base}/api/maintenance/assets`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  const payload = await response.json().catch(() => null);
  if (payload?.asset?.id) insertedAssetIds.push(payload.asset.id);
  return { response, payload };
}

function assetBody(orgUnitId, overrides = {}) {
  return {
    orgUnitId,
    code: uniqueCode('AS'),
    name: 'Press 1',
    assetType: 'machine',
    criticality: 'high',
    ...overrides
  };
}

let admin;
let inactive;
let noGrantAccount;   // approved, no Grant anywhere at all.
let readOnlyAccount;  // read Grant on grantedLine.
let writerAccount;    // write Grant on grantedArea (an ancestor of grantedLine).
let siblingWriter;    // write Grant on otherLine only.
let operatorWriter;   // role operator, write Grant on grantedLine — role gates Screens, not this route.

let site;
let otherSite;
let grantedArea;
let grantedLine;
let otherLine;
let otherSiteArea;

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
  noGrantAccount = await insertAccount();
  readOnlyAccount = await insertAccount();
  writerAccount = await insertAccount();
  siblingWriter = await insertAccount();
  operatorWriter = await insertAccount({ role: 'operator' });

  site = await insertSite();
  otherSite = await insertSite();
  grantedArea = await insertOrgUnit(site, { name: 'Granted Area' });
  grantedLine = await insertOrgUnit(site, { parentId: grantedArea.id, unitType: 'line', name: 'Line 1' });
  otherLine = await insertOrgUnit(site, { parentId: grantedArea.id, unitType: 'line', name: 'Line 2' });
  otherSiteArea = await insertOrgUnit(otherSite, { name: 'Elsewhere' });

  await insertGrant({ accountId: readOnlyAccount.id, orgUnitId: grantedLine.id, canWrite: false });
  await insertGrant({ accountId: writerAccount.id, orgUnitId: grantedArea.id, canWrite: true });
  await insertGrant({ accountId: siblingWriter.id, orgUnitId: otherLine.id, canWrite: true });
  await insertGrant({ accountId: operatorWriter.id, orgUnitId: grantedLine.id, canWrite: true });
});

test.after(async () => {
  await pool.query('DELETE FROM assets WHERE id = ANY($1)', [insertedAssetIds]);
  await pool.query('DELETE FROM app_user_org_units WHERE app_user_id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM app_users WHERE id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM org_units WHERE id = ANY($1)', [insertedOrgUnitIds]);
  await pool.query('DELETE FROM sites WHERE id = ANY($1)', [insertedSiteIds]);
  await new Promise((resolve) => server.close(resolve));
  await closePool();
  await jwks.close();
});

// ---------------------------------------------------------------------------
// The session gate every route sits behind.
// ---------------------------------------------------------------------------

test('a request with no bearer token is refused', async () => {
  const response = await fetch(`${base}/api/maintenance/sites/${site}/assets`);
  assert.strictEqual(response.status, 401);
});

test('an inactive Account is refused', async () => {
  const response = await fetch(`${base}/api/maintenance/sites/${site}/assets`, { headers: inactive.token });
  assert.strictEqual(response.status, 403);
});

// ---------------------------------------------------------------------------
// Adding.
// ---------------------------------------------------------------------------

test('an administrator adds an Asset, and it comes back carrying where it sits', async () => {
  const body = assetBody(grantedLine.id);
  const { response, payload } = await postAsset(admin.token, body);
  assert.strictEqual(response.status, 201);
  assert.strictEqual(payload.asset.code, body.code);
  assert.strictEqual(payload.asset.name, 'Press 1');
  assert.strictEqual(payload.asset.assetType, 'machine');
  assert.strictEqual(payload.asset.criticality, 'high');
  assert.strictEqual(payload.asset.orgUnitId, String(grantedLine.id));
  assert.strictEqual(payload.asset.orgUnitName, 'Line 1');
  assert.strictEqual(payload.asset.isActive, true);

  // Nothing half-written: the row itself carries the Org Unit the response
  // claims. `created_by` is deliberately NOT asserted — `assets` is one of the
  // hierarchy tables the baseline leaves without an actor-columns trigger
  // (sites, org_units, cost_centers and assets alike), so it stays NULL here
  // exactly as it does for an Org Unit created through People.
  const { rows } = await pool.query('SELECT org_unit_id, is_active FROM assets WHERE id = $1', [payload.asset.id]);
  assert.strictEqual(String(rows[0].org_unit_id), String(grantedLine.id));
  assert.strictEqual(rows[0].is_active, true);
});

test('a duplicate code is refused with a message naming the problem, not a database error', async () => {
  const body = assetBody(grantedLine.id);
  const first = await postAsset(admin.token, body);
  assert.strictEqual(first.response.status, 201);

  const second = await postAsset(admin.token, { ...assetBody(grantedLine.id), code: body.code });
  assert.strictEqual(second.response.status, 409);
  assert.strictEqual(second.payload.message, 'an Asset with this code already exists');

  // assets_code_unique is UNIQUE (code) — global, not per Site. The same code
  // at another Site clashes too, which is why the message does not say "at
  // this Site" the way the Org Unit one does.
  const elsewhere = await postAsset(admin.token, { ...assetBody(otherSiteArea.id), code: body.code });
  assert.strictEqual(elsewhere.response.status, 409);
});

test('a malformed orgUnitId is a 400 and an unknown one is a 404 — even for an administrator', async () => {
  const malformed = await postAsset(admin.token, assetBody('not-an-id'));
  assert.strictEqual(malformed.response.status, 400);

  const missing = await postAsset(admin.token, assetBody('999999999'));
  // canAct short-circuits role admin BEFORE its own null-Org-Unit guard, so
  // an administrator would sail past a scope check into a NOT NULL foreign
  // key violation. Existence is resolved first, which is what makes this a
  // clean 404 rather than a 500.
  assert.strictEqual(missing.response.status, 404);
  assert.strictEqual(missing.payload.message, 'Org Unit not found');
});

test('a bad assetType, criticality, code or name is a clean 400', async () => {
  for (const overrides of [
    { assetType: 'spaceship' },
    { criticality: 'urgent' },
    { code: '   ' },
    { name: '' }
  ]) {
    // eslint-disable-next-line no-await-in-loop
    const { response } = await postAsset(admin.token, assetBody(grantedLine.id, overrides));
    assert.strictEqual(response.status, 400, JSON.stringify(overrides));
  }
});

// ---------------------------------------------------------------------------
// Who may add.
// ---------------------------------------------------------------------------

test('a write Grant on an ancestor reaches the Org Unit beneath it', async () => {
  const { response } = await postAsset(writerAccount.token, assetBody(grantedLine.id));
  assert.strictEqual(response.status, 201);
});

test('a read-only Grant on the very Org Unit is refused — the write check is a write check', async () => {
  const { response, payload } = await postAsset(readOnlyAccount.token, assetBody(grantedLine.id));
  assert.strictEqual(response.status, 403);
  assert.strictEqual(payload.message, "Outside the caller's granted Org Units");
});

test('a write Grant on a sibling branch does not reach across', async () => {
  const { response } = await postAsset(siblingWriter.token, assetBody(grantedLine.id));
  assert.strictEqual(response.status, 403);
});

test('an approved Account with no Grant anywhere cannot add', async () => {
  const { response } = await postAsset(noGrantAccount.token, assetBody(grantedLine.id));
  assert.strictEqual(response.status, 403);
});

// This is deliberate, not a hole: ADR-0009's addendum for the Asset register
// documents both halves of it. Role decides which Screens are offered (the
// Shell never offers operator the Maintenance destination); Grants decide
// where an Account may act, and that check does not care what role holds the
// Grant. Pinned here so a future reader who takes the missing role check for
// a bug finds this test saying otherwise.
test('an operator holding a write Grant may add an Asset — role gates Screens, Grants gate acts', async () => {
  const { response } = await postAsset(operatorWriter.token, assetBody(grantedLine.id));
  assert.strictEqual(response.status, 201);
});

// ---------------------------------------------------------------------------
// Listing: Site-wide, whatever the caller's Grants.
// ---------------------------------------------------------------------------

test('the register is readable Site-wide by an Account whose Grants reach none of it', async () => {
  const mine = await postAsset(admin.token, assetBody(grantedLine.id, { name: 'On my line' }));
  const theirs = await postAsset(admin.token, assetBody(otherLine.id, { name: 'On the next line' }));
  assert.strictEqual(mine.response.status, 201);
  assert.strictEqual(theirs.response.status, 201);

  for (const account of [readOnlyAccount, noGrantAccount]) {
    // eslint-disable-next-line no-await-in-loop
    const response = await fetch(`${base}/api/maintenance/sites/${site}/assets`, { headers: account.token });
    assert.strictEqual(response.status, 200);
    // eslint-disable-next-line no-await-in-loop
    const { assets } = await response.json();
    const codes = assets.map((a) => a.code);
    assert.ok(codes.includes(mine.payload.asset.code));
    assert.ok(codes.includes(theirs.payload.asset.code));
  }
});

test('the register does not reach into another Site', async () => {
  const elsewhere = await postAsset(admin.token, assetBody(otherSiteArea.id));
  assert.strictEqual(elsewhere.response.status, 201);

  const response = await fetch(`${base}/api/maintenance/sites/${site}/assets`, { headers: admin.token });
  const { assets } = await response.json();
  assert.ok(!assets.some((a) => a.code === elsewhere.payload.asset.code));
});

test('a deactivated Asset is out of the default listing', async () => {
  const created = await postAsset(admin.token, assetBody(grantedLine.id));
  await pool.query('UPDATE assets SET is_active = FALSE WHERE id = $1', [created.payload.asset.id]);

  const response = await fetch(`${base}/api/maintenance/sites/${site}/assets`, { headers: admin.token });
  const { assets } = await response.json();
  assert.ok(!assets.some((a) => a.code === created.payload.asset.code));
});

test('an unknown Site is a 404, not an empty list — the same answer People gives for its own Org Units', async () => {
  const unknown = await fetch(`${base}/api/maintenance/sites/999999999/assets`, { headers: admin.token });
  assert.strictEqual(unknown.status, 404);
  assert.strictEqual((await unknown.json()).message, 'Site not found');

  const nonsense = await fetch(`${base}/api/maintenance/sites/not-an-id/assets`, { headers: admin.token });
  assert.strictEqual(nonsense.status, 404);

  // The sibling endpoint this consistency claim rests on.
  const peers = await fetch(`${base}/api/people/sites/999999999/org-units`, { headers: admin.token });
  assert.strictEqual(peers.status, 404);
});
