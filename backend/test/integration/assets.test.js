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
// Issue #171's own test raises a Work order to prove that recorded work keeps
// the Org Unit it was raised at, so this file now inserts rows that point at
// its Assets and must be deleted before them.
const insertedWorkOrderIds = [];

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

async function patchAsset(token, id, body) {
  const response = await fetch(`${base}/api/maintenance/assets/${id}`, {
    method: 'PATCH',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  const payload = await response.json().catch(() => null);
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
  // Children before parents: a Work order holds a foreign key to its Asset, so
  // deleting the Assets first would fail the constraint (and, before Node 20's
  // own unhandled-rejection behaviour, hang the file rather than report it).
  await pool.query('DELETE FROM work_orders WHERE id = ANY($1)', [insertedWorkOrderIds]);
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

// ---------------------------------------------------------------------------
// Nesting and retiring (issue #61).
// ---------------------------------------------------------------------------

test('an Asset can be recorded as part of another Asset, and the parent comes back on the row', async () => {
  const parent = await postAsset(admin.token, assetBody(grantedLine.id, { name: 'Machine' }));
  const child = await postAsset(admin.token, assetBody(grantedLine.id, { name: 'Gearbox' }));

  const { response, payload } = await patchAsset(admin.token, child.payload.asset.id, {
    parentId: parent.payload.asset.id
  });
  assert.strictEqual(response.status, 200);
  assert.strictEqual(payload.asset.parentId, String(parent.payload.asset.id));
});

test('detaching with parentId: null works', async () => {
  const parent = await postAsset(admin.token, assetBody(grantedLine.id));
  const child = await postAsset(admin.token, assetBody(grantedLine.id));
  const nested = await patchAsset(admin.token, child.payload.asset.id, { parentId: parent.payload.asset.id });
  assert.strictEqual(nested.response.status, 200);

  const { response, payload } = await patchAsset(admin.token, child.payload.asset.id, { parentId: null });
  assert.strictEqual(response.status, 200);
  assert.strictEqual(payload.asset.parentId, null);
});

test('retiring succeeds, and the Asset is out of the default register but present with includeRetired=true', async () => {
  const created = await postAsset(admin.token, assetBody(grantedLine.id));
  const { response, payload } = await patchAsset(admin.token, created.payload.asset.id, { isActive: false });
  assert.strictEqual(response.status, 200);
  assert.strictEqual(payload.asset.isActive, false);

  const defaultList = await fetch(`${base}/api/maintenance/sites/${site}/assets`, { headers: admin.token });
  const { assets: defaultAssets } = await defaultList.json();
  assert.ok(!defaultAssets.some((a) => a.code === created.payload.asset.code));

  const withRetired = await fetch(`${base}/api/maintenance/sites/${site}/assets?includeRetired=true`, {
    headers: admin.token
  });
  const { assets: retiredAssets } = await withRetired.json();
  assert.ok(retiredAssets.some((a) => a.code === created.payload.asset.code));
});

test('reinstating brings a retired Asset back into the default register', async () => {
  const created = await postAsset(admin.token, assetBody(grantedLine.id));
  await patchAsset(admin.token, created.payload.asset.id, { isActive: false });

  const { response, payload } = await patchAsset(admin.token, created.payload.asset.id, { isActive: true });
  assert.strictEqual(response.status, 200);
  assert.strictEqual(payload.asset.isActive, true);

  const defaultList = await fetch(`${base}/api/maintenance/sites/${site}/assets`, { headers: admin.token });
  const { assets: defaultAssets } = await defaultList.json();
  assert.ok(defaultAssets.some((a) => a.code === created.payload.asset.code));
});

test('retiring an Asset that still has active children is refused — parts are still fitted to it', async () => {
  const parent = await postAsset(admin.token, assetBody(grantedLine.id));
  const child = await postAsset(admin.token, assetBody(grantedLine.id));
  const nested = await patchAsset(admin.token, child.payload.asset.id, { parentId: parent.payload.asset.id });
  assert.strictEqual(nested.response.status, 200);

  const { response, payload } = await patchAsset(admin.token, parent.payload.asset.id, { isActive: false });
  assert.strictEqual(response.status, 409);
  assert.strictEqual(payload.message, 'this Asset still has parts fitted to it');
});

test("an Account without a write Grant reaching the Asset's Org Unit is refused", async () => {
  const created = await postAsset(admin.token, assetBody(grantedLine.id));
  const { response, payload } = await patchAsset(readOnlyAccount.token, created.payload.asset.id, {
    isActive: false
  });
  assert.strictEqual(response.status, 403);
  assert.strictEqual(payload.message, "Outside the caller's granted Org Units");
});

test('write scope on the child is not enough to nest it under a parent outside that scope', async () => {
  // writerAccount's only Grant is on grantedArea (an ancestor of grantedLine),
  // so it reaches the child but has never been granted anything at
  // otherSiteArea, where the proposed parent sits.
  const parent = await postAsset(admin.token, assetBody(otherSiteArea.id));
  const child = await postAsset(admin.token, assetBody(grantedLine.id));

  const { response, payload } = await patchAsset(writerAccount.token, child.payload.asset.id, {
    parentId: parent.payload.asset.id
  });
  assert.strictEqual(response.status, 403);
  assert.strictEqual(payload.message, "Outside the caller's granted Org Units");
});

test('an Asset cannot be made part of itself', async () => {
  const created = await postAsset(admin.token, assetBody(grantedLine.id));
  const { response, payload } = await patchAsset(admin.token, created.payload.asset.id, {
    parentId: created.payload.asset.id
  });
  assert.strictEqual(response.status, 400);
  assert.strictEqual(payload.message, 'an Asset cannot be part of itself');
});

test('a cycle is refused: A -> B -> C, then A cannot be made part of C', async () => {
  const a = await postAsset(admin.token, assetBody(grantedLine.id, { name: 'A' }));
  const b = await postAsset(admin.token, assetBody(grantedLine.id, { name: 'B' }));
  const c = await postAsset(admin.token, assetBody(grantedLine.id, { name: 'C' }));

  const ab = await patchAsset(admin.token, b.payload.asset.id, { parentId: a.payload.asset.id });
  assert.strictEqual(ab.response.status, 200);
  const bc = await patchAsset(admin.token, c.payload.asset.id, { parentId: b.payload.asset.id });
  assert.strictEqual(bc.response.status, 200);

  const { response, payload } = await patchAsset(admin.token, a.payload.asset.id, {
    parentId: c.payload.asset.id
  });
  assert.strictEqual(response.status, 400);
  assert.strictEqual(payload.message, 'an Asset cannot be part of one of its own parts');
});

test('PATCH /assets/abc (malformed id) is a clean 404, not a 500', async () => {
  const { response } = await patchAsset(admin.token, 'abc', { isActive: false });
  assert.strictEqual(response.status, 404);
});

// Issue #171 widened this route to a third field, so the empty-body message
// names all three — a message that still said "isActive and/or parentId"
// would be telling a caller that an orgUnitId-only request is impossible.
test('an empty body is refused', async () => {
  const created = await postAsset(admin.token, assetBody(grantedLine.id));
  const { response, payload } = await patchAsset(admin.token, created.payload.asset.id, {});
  assert.strictEqual(response.status, 400);
  assert.strictEqual(payload.message, 'isActive, parentId and/or orgUnitId is required');
});

// ---------------------------------------------------------------------------
// Review fixes for issue #61.
// ---------------------------------------------------------------------------

// Fix A: a combined PATCH can half-commit — setAssetParent and setAssetActive
// are separate transactions, so refuse the combination outright rather than
// let a caller see only a 409/500 while the parent has already changed.
// Issue #171 keeps this rule and widens it to the third field it adds; the
// orgUnitId half of that is the test below it.
test('a PATCH naming both isActive and parentId is refused, and the Asset is unchanged', async () => {
  const parent = await postAsset(admin.token, assetBody(grantedLine.id));
  const created = await postAsset(admin.token, assetBody(grantedLine.id));

  const { response, payload } = await patchAsset(admin.token, created.payload.asset.id, {
    parentId: parent.payload.asset.id,
    isActive: false
  });
  assert.strictEqual(response.status, 400);
  assert.strictEqual(
    payload.message,
    'only one of isActive, parentId and orgUnitId can be changed per request; send them as separate requests'
  );

  const { rows: [row] } = await pool.query(
    'SELECT parent_id, is_active FROM assets WHERE id = $1',
    [created.payload.asset.id]
  );
  assert.strictEqual(row.parent_id, null);
  assert.strictEqual(row.is_active, true);
});

// Fix C: nesting under a retired parent, and reinstating a child whose parent
// is retired, are both refused — the invariant is that an active Asset never
// has a retired parent, and a retired Asset never has active parts.
test('nesting under a retired parent is refused', async () => {
  const parent = await postAsset(admin.token, assetBody(grantedLine.id));
  const retire = await patchAsset(admin.token, parent.payload.asset.id, { isActive: false });
  assert.strictEqual(retire.response.status, 200);

  const child = await postAsset(admin.token, assetBody(grantedLine.id));
  const { response, payload } = await patchAsset(admin.token, child.payload.asset.id, {
    parentId: parent.payload.asset.id
  });
  assert.strictEqual(response.status, 409);
  assert.strictEqual(payload.message, 'that Asset has been retired');
});

test('reinstating an Asset whose parent is retired is refused', async () => {
  const parent = await postAsset(admin.token, assetBody(grantedLine.id));
  const child = await postAsset(admin.token, assetBody(grantedLine.id));

  const nested = await patchAsset(admin.token, child.payload.asset.id, { parentId: parent.payload.asset.id });
  assert.strictEqual(nested.response.status, 200);

  // Retire the child first (it has no children of its own, so this succeeds),
  // then retire the parent — leaving both retired and nested.
  const retireChild = await patchAsset(admin.token, child.payload.asset.id, { isActive: false });
  assert.strictEqual(retireChild.response.status, 200);
  const retireParent = await patchAsset(admin.token, parent.payload.asset.id, { isActive: false });
  assert.strictEqual(retireParent.response.status, 200);

  const { response, payload } = await patchAsset(admin.token, child.payload.asset.id, { isActive: true });
  assert.strictEqual(response.status, 409);
  assert.strictEqual(payload.message, "this Asset's parent has been retired");
});

// Fix E: the parent-scope rule now guards the CURRENT parent too, not just
// the proposed one — detaching or moving a part off a machine alters that
// machine's composition just as attaching does.
test('detaching with write scope on the child but not on its current parent is refused', async () => {
  // writerAccount's only Grant is on grantedArea; otherSiteArea is outside it.
  const parent = await postAsset(admin.token, assetBody(otherSiteArea.id));
  const child = await postAsset(admin.token, assetBody(grantedLine.id));

  const nested = await patchAsset(admin.token, child.payload.asset.id, { parentId: parent.payload.asset.id });
  assert.strictEqual(nested.response.status, 200);

  const { response, payload } = await patchAsset(writerAccount.token, child.payload.asset.id, { parentId: null });
  assert.strictEqual(response.status, 403);
  assert.strictEqual(payload.message, "Outside the caller's granted Org Units");
});

test('moving an Asset from X to Y without scope on X is refused', async () => {
  // siblingWriter's only Grant is on otherLine. X sits at grantedLine, where
  // siblingWriter has never been granted anything.
  const x = await postAsset(admin.token, assetBody(grantedLine.id, { name: 'X' }));
  const y = await postAsset(admin.token, assetBody(otherLine.id, { name: 'Y' }));
  const child = await postAsset(admin.token, assetBody(otherLine.id));

  const nested = await patchAsset(admin.token, child.payload.asset.id, { parentId: x.payload.asset.id });
  assert.strictEqual(nested.response.status, 200);

  const { response, payload } = await patchAsset(siblingWriter.token, child.payload.asset.id, {
    parentId: y.payload.asset.id
  });
  assert.strictEqual(response.status, 403);
  assert.strictEqual(payload.message, "Outside the caller's granted Org Units");
});

// Fix F: nesting promotes a default 'machine' to 'component', and detaching
// restores 'machine' — 'assembly' or an already-nested 'component' is left
// alone, but no test above needs that branch to make the point.
test('nesting promotes a default machine to component, and detaching restores machine', async () => {
  const parent = await postAsset(admin.token, assetBody(grantedLine.id));
  const child = await postAsset(admin.token, assetBody(grantedLine.id));
  assert.strictEqual(child.payload.asset.assetLevel, 'machine');

  const nested = await patchAsset(admin.token, child.payload.asset.id, { parentId: parent.payload.asset.id });
  assert.strictEqual(nested.response.status, 200);
  assert.strictEqual(nested.payload.asset.assetLevel, 'component');

  const detached = await patchAsset(admin.token, child.payload.asset.id, { parentId: null });
  assert.strictEqual(detached.response.status, 200);
  assert.strictEqual(detached.payload.asset.assetLevel, 'machine');
});

// ---------------------------------------------------------------------------
// Changing where an Asset sits (issue #171).
//
// `orgUnit_id` is the one column the register's creation path sets and nothing
// could correct afterwards: POST /assets takes an orgUnitId, and PATCH
// /assets/:id took only isActive and parentId. These are the acceptance
// criteria of the ticket that closes that hole.
// ---------------------------------------------------------------------------

test('an Asset moves to another Org Unit, and the row comes back carrying the new one', async () => {
  const created = await postAsset(admin.token, assetBody(grantedLine.id));
  const id = created.payload.asset.id;

  const { response, payload } = await patchAsset(admin.token, id, { orgUnitId: otherLine.id });
  assert.strictEqual(response.status, 200);
  assert.strictEqual(payload.asset.orgUnitId, String(otherLine.id));
  assert.strictEqual(payload.asset.orgUnitName, 'Line 2');

  // A move is only a move: it is not quietly a retirement, and it neither
  // detaches the machine nor re-nests it.
  assert.strictEqual(payload.asset.isActive, true);
  assert.strictEqual(payload.asset.parentId, null);
  assert.strictEqual(payload.asset.assetLevel, 'machine');
  assert.strictEqual(payload.asset.code, created.payload.asset.code);

  // The row itself carries it, and the register reads the machine at the Org
  // Unit it arrived at rather than the one it left.
  const { rows: [row] } = await pool.query(
    'SELECT org_unit_id, is_active, parent_id FROM assets WHERE id = $1',
    [id]
  );
  assert.strictEqual(String(row.org_unit_id), String(otherLine.id));
  assert.strictEqual(row.is_active, true);
  assert.strictEqual(row.parent_id, null);

  const listing = await fetch(`${base}/api/maintenance/sites/${site}/assets`, { headers: admin.token });
  const { assets } = await listing.json();
  const moved = assets.find((candidate) => candidate.id === id);
  assert.strictEqual(moved.orgUnitId, String(otherLine.id));
});

// The source half of the scope rule is requireAssetWriteScope's, which asks
// about the Org Unit the Asset sits at NOW. It needs its own test because the
// destination half below could otherwise be mistaken for the whole rule: a
// caller with a write Grant on where the machine is going still cannot take it
// out of an Org Unit their Grants never reached.
test('write scope on the destination but not on the source is refused', async () => {
  // The Asset sits at otherSiteArea, where writerAccount holds nothing;
  // writerAccount's own Grant is on grantedArea, which does reach grantedLine
  // — the destination.
  const created = await postAsset(admin.token, assetBody(otherSiteArea.id));

  const { response, payload } = await patchAsset(writerAccount.token, created.payload.asset.id, {
    orgUnitId: grantedLine.id
  });
  assert.strictEqual(response.status, 403);
  assert.strictEqual(payload.message, "Outside the caller's granted Org Units");

  const { rows: [row] } = await pool.query('SELECT org_unit_id FROM assets WHERE id = $1', [
    created.payload.asset.id
  ]);
  assert.strictEqual(String(row.org_unit_id), String(otherSiteArea.id));
});

// And the destination half: writerAccount may act on the machine (it sits
// inside grantedArea) but cannot hand it to an Org Unit outside its Grants.
// This is the half that makes "there is a second record whose composition
// changes" true for a move — the destination's own register gains a machine.
test('write scope on the source but not on the destination is refused', async () => {
  const created = await postAsset(admin.token, assetBody(grantedLine.id));

  const { response, payload } = await patchAsset(writerAccount.token, created.payload.asset.id, {
    orgUnitId: otherSiteArea.id
  });
  assert.strictEqual(response.status, 403);
  assert.strictEqual(payload.message, "Outside the caller's granted Org Units");

  const { rows: [row] } = await pool.query('SELECT org_unit_id FROM assets WHERE id = $1', [
    created.payload.asset.id
  ]);
  assert.strictEqual(String(row.org_unit_id), String(grantedLine.id));
});

test('a malformed orgUnitId is a 400 and an unknown one is a 404 — even for an administrator', async () => {
  const created = await postAsset(admin.token, assetBody(grantedLine.id));
  const id = created.payload.asset.id;

  // Existence before scope, and a typo is never a 500: the administrator's
  // own `canAct` short-circuit is why the Org Unit is resolved first (see
  // requireOrgUnitWriteScope's own comment for the same ordering on POST).
  const malformed = await patchAsset(admin.token, id, { orgUnitId: 'abc' });
  assert.strictEqual(malformed.response.status, 400);
  assert.strictEqual(malformed.payload.message, 'orgUnitId must be a valid Org Unit id');

  const unknown = await patchAsset(admin.token, id, { orgUnitId: 2147483000 });
  assert.strictEqual(unknown.response.status, 404);

  const { rows: [row] } = await pool.query('SELECT org_unit_id FROM assets WHERE id = $1', [id]);
  assert.strictEqual(String(row.org_unit_id), String(grantedLine.id));
});

test('naming orgUnitId alongside another field is refused, and the Asset is unchanged', async () => {
  const parent = await postAsset(admin.token, assetBody(grantedLine.id));
  const created = await postAsset(admin.token, assetBody(grantedLine.id));

  const { response, payload } = await patchAsset(admin.token, created.payload.asset.id, {
    orgUnitId: otherLine.id,
    parentId: parent.payload.asset.id
  });
  assert.strictEqual(response.status, 400);
  assert.strictEqual(
    payload.message,
    'only one of isActive, parentId and orgUnitId can be changed per request; send them as separate requests'
  );

  const { rows: [row] } = await pool.query(
    'SELECT org_unit_id, parent_id FROM assets WHERE id = $1',
    [created.payload.asset.id]
  );
  assert.strictEqual(String(row.org_unit_id), String(grantedLine.id));
  assert.strictEqual(row.parent_id, null);
});

// ---------------------------------------------------------------------------
// Correcting an Asset's own details (issue #173): a full replacement of
// code, name, assetType and criticality — its placement, its nesting and
// its retirement are untouched, each with its own action and its own rule.
// ---------------------------------------------------------------------------

function correctionBody(overrides = {}) {
  return {
    code: uniqueCode('CORRECTED'),
    name: 'Corrected Press',
    assetType: 'cell',
    criticality: 'critical',
    ...overrides
  };
}

test('a correction changes all four fields and answers with the row, and a re-read agrees',
  async () => {
    const created = await postAsset(admin.token, assetBody(grantedLine.id));
    const id = created.payload.asset.id;
    const body = correctionBody();

    const { response, payload } = await patchAsset(admin.token, id, body);
    assert.strictEqual(response.status, 200);
    assert.strictEqual(payload.asset.code, body.code);
    assert.strictEqual(payload.asset.name, body.name);
    assert.strictEqual(payload.asset.assetType, body.assetType);
    assert.strictEqual(payload.asset.criticality, body.criticality);

    const listing = await fetch(`${base}/api/maintenance/sites/${site}/assets`, {
      headers: admin.token
    });
    const { assets: registerAssets } = await listing.json();
    const reread = registerAssets.find((candidate) => candidate.id === id);
    assert.strictEqual(reread.code, body.code);
    assert.strictEqual(reread.name, body.name);
    assert.strictEqual(reread.assetType, body.assetType);
    assert.strictEqual(reread.criticality, body.criticality);
  });

test('a correction leaves the Asset\'s placement, nesting and retirement exactly as they were',
  async () => {
    const parent = await postAsset(admin.token, assetBody(grantedLine.id));
    const created = await postAsset(admin.token, assetBody(grantedLine.id));
    const id = created.payload.asset.id;
    await patchAsset(admin.token, id, { parentId: parent.payload.asset.id });

    const { response, payload } = await patchAsset(admin.token, id, correctionBody());
    assert.strictEqual(response.status, 200);
    assert.strictEqual(payload.asset.orgUnitId, String(grantedLine.id));
    assert.strictEqual(payload.asset.parentId, String(parent.payload.asset.id));
    assert.strictEqual(payload.asset.isActive, true);
    assert.strictEqual(payload.asset.assetLevel, 'component');

    const { rows: [row] } = await pool.query(
      'SELECT org_unit_id, parent_id, is_active, asset_level FROM assets WHERE id = $1',
      [id]
    );
    assert.strictEqual(String(row.org_unit_id), String(grantedLine.id));
    assert.strictEqual(String(row.parent_id), String(parent.payload.asset.id));
    assert.strictEqual(row.is_active, true);
    assert.strictEqual(row.asset_level, 'component');
  });

test('a duplicate code is refused with the create path\'s own message, and the row is unchanged',
  async () => {
    const first = await postAsset(admin.token, assetBody(grantedLine.id));
    const second = await postAsset(admin.token, assetBody(grantedLine.id));

    const { response, payload } = await patchAsset(
      admin.token,
      second.payload.asset.id,
      correctionBody({ code: first.payload.asset.code })
    );
    assert.strictEqual(response.status, 409);
    assert.strictEqual(payload.message, 'an Asset with this code already exists');

    const { rows: [row] } = await pool.query('SELECT code FROM assets WHERE id = $1', [
      second.payload.asset.id
    ]);
    assert.strictEqual(row.code, second.payload.asset.code);
  });

test('a missing or blank code/name and a bad assetType/criticality are clean 400s', async () => {
  const created = await postAsset(admin.token, assetBody(grantedLine.id));
  const id = created.payload.asset.id;

  for (const overrides of [
    { code: undefined },
    { code: '   ' },
    { name: undefined },
    { name: '' },
    { assetType: 'spaceship' },
    { criticality: 'urgent' }
  ]) {
    const body = correctionBody(overrides);
    if (overrides.code === undefined) delete body.code;
    if (overrides.name === undefined) delete body.name;
    // eslint-disable-next-line no-await-in-loop
    const { response } = await patchAsset(admin.token, id, body);
    assert.strictEqual(response.status, 400, JSON.stringify(overrides));
  }
});

test('a body mixing a correction with each of the three operations is a 400, and nothing is written',
  async () => {
    const created = await postAsset(admin.token, assetBody(grantedLine.id));
    const id = created.payload.asset.id;

    for (const mixedWith of [{ isActive: false }, { parentId: null }, { orgUnitId: otherLine.id }]) {
      // eslint-disable-next-line no-await-in-loop
      const { response, payload } = await patchAsset(admin.token, id, {
        ...correctionBody(),
        ...mixedWith
      });
      assert.strictEqual(response.status, 400, JSON.stringify(mixedWith));
      assert.strictEqual(
        payload.message,
        'only one of isActive, parentId and orgUnitId can be changed per request; send them as separate requests'
      );
    }

    const { rows: [row] } = await pool.query(
      'SELECT code, name, asset_type, criticality FROM assets WHERE id = $1',
      [id]
    );
    assert.strictEqual(row.code, created.payload.asset.code);
    assert.strictEqual(row.name, created.payload.asset.name);
  });

test("a read-only Grant on the Asset's Org Unit is refused", async () => {
  const created = await postAsset(admin.token, assetBody(grantedLine.id));
  const { response, payload } = await patchAsset(
    readOnlyAccount.token,
    created.payload.asset.id,
    correctionBody()
  );
  assert.strictEqual(response.status, 403);
  assert.strictEqual(payload.message, "Outside the caller's granted Org Units");
});

// Issue #173, user story 18: a write Grant reaching the Asset's own Org Unit
// is the whole rule — writerAccount holds nothing anywhere else (its only
// Grant is on grantedArea, an ancestor of grantedLine), and no second Org
// Unit is involved the way a move or a re-parent would need one.
test("a write Grant reaching only the Asset's own Org Unit succeeds, with no Grant needed anywhere else",
  async () => {
    const created = await postAsset(admin.token, assetBody(grantedLine.id));
    const body = correctionBody();

    const { response, payload } = await patchAsset(writerAccount.token, created.payload.asset.id, body);
    assert.strictEqual(response.status, 200);
    assert.strictEqual(payload.asset.code, body.code);
  });

test('an unknown or malformed Asset id is a clean 404', async () => {
  const unknown = await patchAsset(admin.token, 999999999, correctionBody());
  assert.strictEqual(unknown.response.status, 404);

  const malformed = await patchAsset(admin.token, 'not-an-id', correctionBody());
  assert.strictEqual(malformed.response.status, 404);
});

test('a retired Asset can still be corrected', async () => {
  const created = await postAsset(admin.token, assetBody(grantedLine.id));
  const id = created.payload.asset.id;
  const retired = await patchAsset(admin.token, id, { isActive: false });
  assert.strictEqual(retired.response.status, 200);

  const { response, payload } = await patchAsset(admin.token, id, correctionBody());
  assert.strictEqual(response.status, 200);
  assert.strictEqual(payload.asset.isActive, false);
  assert.strictEqual(payload.asset.code, payload.asset.code);
});

test('a Work order raised before a correction reads the corrected code and name afterwards',
  async () => {
    const created = await postAsset(admin.token, assetBody(grantedLine.id));
    const assetId = created.payload.asset.id;

    const raised = await fetch(`${base}/api/maintenance/work-orders`, {
      method: 'POST',
      headers: { ...admin.token, 'content-type': 'application/json' },
      body: JSON.stringify({
        assetId,
        summary: 'Raised before the machine was corrected',
        workType: 'corrective',
        priority: 3
      })
    });
    assert.strictEqual(raised.status, 201);
    const { workOrder } = await raised.json();
    insertedWorkOrderIds.push(workOrder.id);

    const body = correctionBody();
    const corrected = await patchAsset(admin.token, assetId, body);
    assert.strictEqual(corrected.response.status, 200);

    const workOrderRead = await fetch(`${base}/api/maintenance/work-orders/${workOrder.id}`, {
      headers: admin.token
    });
    assert.strictEqual(workOrderRead.status, 200);
    const { workOrder: reread } = await workOrderRead.json();
    assert.strictEqual(reread.assetCode, body.code);
    assert.strictEqual(reread.assetName, body.name);
  });

// The reading this ticket asserts rather than codes: `work_orders`,
// `maintenance_requests` and `downtime_events` denormalise `org_unit_id`
// through a trigger that fires on INSERT or on a change to `asset_id` only, so
// a move leaves the work recorded against the machine where it happened. A
// machine that walks to another Line does not rewrite last month's history,
// and a Work order is the cheapest way to prove it over HTTP.
test('work already recorded against a moved Asset keeps the Org Unit it was raised at', async () => {
  const created = await postAsset(admin.token, assetBody(grantedLine.id));
  const assetId = created.payload.asset.id;

  const raised = await fetch(`${base}/api/maintenance/work-orders`, {
    method: 'POST',
    headers: { ...admin.token, 'content-type': 'application/json' },
    body: JSON.stringify({
      assetId,
      summary: 'Raised before the machine moved',
      workType: 'corrective',
      priority: 3
    })
  });
  assert.strictEqual(raised.status, 201);
  const { workOrder } = await raised.json();
  insertedWorkOrderIds.push(workOrder.id);
  assert.strictEqual(workOrder.orgUnitId, String(grantedLine.id));

  const moved = await patchAsset(admin.token, assetId, { orgUnitId: otherLine.id });
  assert.strictEqual(moved.response.status, 200);

  const atSource = await fetch(
    `${base}/api/maintenance/sites/${site}/work-orders?orgUnitId=${grantedLine.id}`,
    { headers: admin.token }
  );
  const sourceBody = await atSource.json();
  assert.ok(
    sourceBody.workOrders.some((candidate) => candidate.id === workOrder.id),
    'the Work order still reads at the Org Unit it was raised at'
  );

  const atDestination = await fetch(
    `${base}/api/maintenance/sites/${site}/work-orders?orgUnitId=${otherLine.id}`,
    { headers: admin.token }
  );
  const destinationBody = await atDestination.json();
  assert.ok(
    !destinationBody.workOrders.some((candidate) => candidate.id === workOrder.id),
    'the Work order did not follow the machine to its new Org Unit'
  );
});
