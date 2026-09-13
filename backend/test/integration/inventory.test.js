/*
 * Inventory over HTTP (issue #80): the parts catalogue, stores, and derived
 * stock levels, against a real database and a real (locally issued) JWKS —
 * the same seam as assets.test.js and plant.test.js. Fixture scaffolding is
 * modelled on assets.test.js, which needs the same non-administrator with a
 * real Grant row.
 *
 * Every acceptance criterion in issue #80 has a named test below. The
 * movement and store routes live under `/api/maintenance` because inventory
 * is part of the Maintenance Module — see inventory.js's own header for why
 * the atomic booking #75 needs forces that.
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
const insertedStoreIds = [];
const insertedPartIds = [];

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
  const subject = uniqueCode('inv');
  const { rows: [row] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status)
     VALUES ($1, 'Inventory Test Account', $2, $3, $4, $5) RETURNING id`,
    [`${subject}@example.com`, role, subject, isActive, approvalStatus]
  );
  insertedAccountIds.push(row.id);
  return { id: row.id, token: await authHeader(subject) };
}

async function insertSite() {
  const { rows: [row] } = await pool.query(
    `INSERT INTO sites (code, name, timezone) VALUES ($1, 'Inventory Test Site', 'Asia/Ho_Chi_Minh') RETURNING id`,
    [uniqueCode('IS')]
  );
  insertedSiteIds.push(row.id);
  return row.id;
}

async function insertOrgUnit(siteId, { parentId = null, unitType = 'area', name = 'Inventory Test Unit' } = {}) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, $2, $3, $4, $5) RETURNING id, code, name`,
    [siteId, parentId, uniqueCode('IOU'), name, unitType]
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

function partBody(overrides = {}) {
  return {
    partNo: uniqueCode('PN'),
    description: 'Bearing, 6204',
    uomCode: 'EA',
    ...overrides
  };
}

async function postPart(token, body) {
  const response = await fetch(`${base}/api/maintenance/parts`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  const payload = await response.json().catch(() => null);
  if (payload?.part?.id) insertedPartIds.push(payload.part.id);
  return { response, payload };
}

async function postStore(token, body) {
  const response = await fetch(`${base}/api/maintenance/stores`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  const payload = await response.json().catch(() => null);
  if (payload?.store?.id) insertedStoreIds.push(payload.store.id);
  return { response, payload };
}

async function getStores(token, siteId, query = '') {
  const response = await fetch(`${base}/api/maintenance/sites/${siteId}/stores${query}`, { headers: token });
  return { response, payload: await response.json().catch(() => null) };
}

async function getStock(token, storeId) {
  const response = await fetch(`${base}/api/maintenance/stores/${storeId}/stock`, { headers: token });
  return { response, payload: await response.json().catch(() => null) };
}

async function getMovements(token, storeId) {
  const response = await fetch(`${base}/api/maintenance/stores/${storeId}/movements`, { headers: token });
  return { response, payload: await response.json().catch(() => null) };
}

async function postReceipt(token, storeId, body) {
  const response = await fetch(`${base}/api/maintenance/stores/${storeId}/receipts`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  return { response, payload: await response.json().catch(() => null) };
}

async function postAdjustment(token, storeId, body) {
  const response = await fetch(`${base}/api/maintenance/stores/${storeId}/adjustments`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  return { response, payload: await response.json().catch(() => null) };
}

let admin;
let inactive;
let noGrantAccount;   // approved, no Grant anywhere at all.
let readOnlyAccount;  // read Grant on grantedLine.
let writerAccount;    // write Grant on grantedArea (an ancestor of grantedLine).
let siblingWriter;    // write Grant on otherLine only.

let site;
let otherSite;
let grantedArea;
let grantedLine;
let otherLine;
let otherSiteArea;
let otherSiteLine;

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

  site = await insertSite();
  otherSite = await insertSite();
  grantedArea = await insertOrgUnit(site, { name: 'Granted Area' });
  grantedLine = await insertOrgUnit(site, { parentId: grantedArea.id, unitType: 'line', name: 'Line 1' });
  otherLine = await insertOrgUnit(site, { parentId: grantedArea.id, unitType: 'line', name: 'Line 2' });
  otherSiteArea = await insertOrgUnit(otherSite, { name: 'Elsewhere' });
  otherSiteLine = await insertOrgUnit(otherSite, { parentId: otherSiteArea.id, unitType: 'line', name: 'Elsewhere Line' });

  await insertGrant({ accountId: readOnlyAccount.id, orgUnitId: grantedLine.id, canWrite: false });
  await insertGrant({ accountId: writerAccount.id, orgUnitId: grantedArea.id, canWrite: true });
  await insertGrant({ accountId: siblingWriter.id, orgUnitId: otherLine.id, canWrite: true });
});

test.after(async () => {
  await pool.query('DELETE FROM stock_movements WHERE store_id = ANY($1)', [insertedStoreIds]);
  await pool.query('DELETE FROM stores WHERE id = ANY($1)', [insertedStoreIds]);
  await pool.query('DELETE FROM parts WHERE id = ANY($1)', [insertedPartIds]);
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
  const response = await fetch(`${base}/api/maintenance/parts`);
  assert.strictEqual(response.status, 401);
});

test('an inactive Account is refused', async () => {
  const response = await fetch(`${base}/api/maintenance/parts`, { headers: inactive.token });
  assert.strictEqual(response.status, 403);
});

// ---------------------------------------------------------------------------
// Defining a part once (AC: "a part can be defined once ... and reused").
// ---------------------------------------------------------------------------

test('a part can be defined once with a part number, a description and a unit of measure', async () => {
  const body = partBody();
  const { response, payload } = await postPart(admin.token, body);
  assert.strictEqual(response.status, 201);
  assert.strictEqual(payload.part.partNo, body.partNo);
  assert.strictEqual(payload.part.description, body.description);
  // The unit is units_of_measure's own 'EA', not a second notion of a unit.
  assert.strictEqual(payload.part.uomCode, 'EA');
  assert.strictEqual(payload.part.isActive, true);
});

test('a duplicate part number is refused with a message naming the problem', async () => {
  const body = partBody();
  const first = await postPart(admin.token, body);
  assert.strictEqual(first.response.status, 201);
  const second = await postPart(admin.token, { ...partBody(), partNo: body.partNo });
  assert.strictEqual(second.response.status, 409);
  assert.strictEqual(second.payload.message, 'a Part with this part number already exists');
});

test('a part with an unknown unit of measure is a 404, not a raw foreign-key error', async () => {
  const { response, payload } = await postPart(admin.token, partBody({ uomCode: 'NOPE' }));
  assert.strictEqual(response.status, 404);
  assert.strictEqual(payload.message, 'Unit of measure not found');
});

test('the unit picker lists the existing units of measure, so a Part chooses one', async () => {
  const response = await fetch(`${base}/api/maintenance/units-of-measure`, { headers: admin.token });
  assert.strictEqual(response.status, 200);
  const { unitsOfMeasure } = await response.json();
  assert.ok(unitsOfMeasure.some((unit) => unit.code === 'EA' && unit.name === 'Each'));
});

test('only an administrator may define a part — a shared catalogue has no Org Unit to scope', async () => {
  const { response } = await postPart(writerAccount.token, partBody());
  assert.strictEqual(response.status, 403);
});

// ---------------------------------------------------------------------------
// Stores belong to a Site and sit at an Org Unit.
// ---------------------------------------------------------------------------

test('a store belongs to a Site and comes back carrying the Org Unit it sits at', async () => {
  const { response, payload } = await postStore(admin.token, {
    orgUnitId: grantedLine.id,
    code: uniqueCode('STORE'),
    name: 'Line 1 store'
  });
  assert.strictEqual(response.status, 201);
  assert.strictEqual(payload.store.orgUnitId, String(grantedLine.id));
  assert.strictEqual(payload.store.orgUnitName, 'Line 1');
  assert.strictEqual(payload.store.siteId, String(site));
});

test('two Sites do not share a shelf: each Site lists only its own stores', async () => {
  const mine = await postStore(admin.token, {
    orgUnitId: grantedLine.id,
    code: uniqueCode('STORE'),
    name: 'Mine'
  });
  const theirs = await postStore(admin.token, {
    orgUnitId: otherSiteLine.id,
    code: uniqueCode('STORE'),
    name: 'Theirs'
  });
  assert.strictEqual(mine.response.status, 201);
  assert.strictEqual(theirs.response.status, 201);

  const list = await getStores(admin.token, site);
  const ids = list.payload.stores.map((s) => String(s.id));
  assert.ok(ids.includes(String(mine.payload.store.id)));
  assert.ok(!ids.includes(String(theirs.payload.store.id)));

  const otherList = await getStores(admin.token, otherSite);
  const otherIds = otherList.payload.stores.map((s) => String(s.id));
  assert.ok(otherIds.includes(String(theirs.payload.store.id)));
  assert.ok(!otherIds.includes(String(mine.payload.store.id)));
});

test('a store code is unique within its Site, and the clash is named as Site-local', async () => {
  const code = uniqueCode('STORE');
  const first = await postStore(admin.token, { orgUnitId: grantedLine.id, code, name: 'One' });
  assert.strictEqual(first.response.status, 201);
  const second = await postStore(admin.token, { orgUnitId: otherLine.id, code, name: 'Two' });
  assert.strictEqual(second.response.status, 409);
  assert.strictEqual(second.payload.message, 'a Store with this code already exists at this Site');
});

test('an unknown Site is a 404, not an empty list', async () => {
  const unknown = await getStores(admin.token, '999999999');
  assert.strictEqual(unknown.response.status, 404);
  assert.strictEqual(unknown.payload.message, 'Site not found');
});

test('an unknown Org Unit at store creation is a clean 404 — even for an administrator', async () => {
  const missing = await postStore(admin.token, { orgUnitId: '999999999', code: uniqueCode('STORE'), name: 'X' });
  assert.strictEqual(missing.response.status, 404);
  assert.strictEqual(missing.payload.message, 'Org Unit not found');

  const malformed = await postStore(admin.token, { orgUnitId: 'not-an-id', code: uniqueCode('STORE'), name: 'X' });
  assert.strictEqual(malformed.response.status, 400);
});

// ---------------------------------------------------------------------------
// Receiving, adjusting, and the derived level.
// ---------------------------------------------------------------------------

test('stock can be received into a store, and the movement records what moved, where, how much, when and why', async () => {
  const part = (await postPart(admin.token, partBody())).payload.part;
  const store = (await postStore(admin.token, {
    orgUnitId: grantedLine.id,
    code: uniqueCode('STORE'),
    name: 'Receiving'
  })).payload.store;

  const occurredAt = '2026-09-10T08:00:00.000Z';
  const { response, payload } = await postReceipt(admin.token, store.id, {
    partId: part.id,
    quantity: 12,
    reason: 'Goods-in note 4471',
    occurredAt
  });
  assert.strictEqual(response.status, 201);
  assert.strictEqual(payload.movement.partId, part.id);
  assert.strictEqual(payload.movement.partNo, part.partNo);
  assert.strictEqual(payload.movement.storeId, store.id);
  assert.strictEqual(payload.movement.quantity, 12);
  assert.strictEqual(payload.movement.uomCode, 'EA');
  assert.strictEqual(payload.movement.movementType, 'receipt');
  assert.strictEqual(payload.movement.reason, 'Goods-in note 4471');
  assert.strictEqual(new Date(payload.movement.occurredAt).toISOString(), occurredAt);
  assert.strictEqual(payload.onHand, 12);
});

test('a receipt with no reason records the honest default', async () => {
  const part = (await postPart(admin.token, partBody())).payload.part;
  const store = (await postStore(admin.token, {
    orgUnitId: grantedLine.id,
    code: uniqueCode('STORE'),
    name: 'Default reason'
  })).payload.store;

  const { response, payload } = await postReceipt(admin.token, store.id, { partId: part.id, quantity: 1 });
  assert.strictEqual(response.status, 201);
  assert.strictEqual(payload.movement.reason, 'received');
});

test('a zero or negative receipt is refused', async () => {
  const part = (await postPart(admin.token, partBody())).payload.part;
  const store = (await postStore(admin.token, {
    orgUnitId: grantedLine.id,
    code: uniqueCode('STORE'),
    name: 'Bad receipt'
  })).payload.store;

  const zero = await postReceipt(admin.token, store.id, { partId: part.id, quantity: 0 });
  assert.strictEqual(zero.response.status, 400);
  const negative = await postReceipt(admin.token, store.id, { partId: part.id, quantity: -5 });
  assert.strictEqual(negative.response.status, 400);
});

test('stock can be adjusted with a reason when a count disagrees with the record', async () => {
  const part = (await postPart(admin.token, partBody())).payload.part;
  const store = (await postStore(admin.token, {
    orgUnitId: grantedLine.id,
    code: uniqueCode('STORE'),
    name: 'Adjusting'
  })).payload.store;
  await postReceipt(admin.token, store.id, { partId: part.id, quantity: 10 });

  const { response, payload } = await postAdjustment(admin.token, store.id, {
    partId: part.id,
    quantityDelta: -2,
    reason: 'Stocktake found two fewer'
  });
  assert.strictEqual(response.status, 201);
  assert.strictEqual(payload.movement.movementType, 'adjustment');
  assert.strictEqual(payload.movement.quantity, -2);
  assert.strictEqual(payload.movement.reason, 'Stocktake found two fewer');
  assert.strictEqual(payload.onHand, 8);
});

test('an adjustment without a reason is refused — the why is the point', async () => {
  const part = (await postPart(admin.token, partBody())).payload.part;
  const store = (await postStore(admin.token, {
    orgUnitId: grantedLine.id,
    code: uniqueCode('STORE'),
    name: 'No reason'
  })).payload.store;
  await postReceipt(admin.token, store.id, { partId: part.id, quantity: 5 });

  const { response } = await postAdjustment(admin.token, store.id, {
    partId: part.id,
    quantityDelta: -1,
    reason: '   '
  });
  assert.strictEqual(response.status, 400);
});

test('the quantity is derived from the movements: a sequence leaves the running sum, and the history is readable', async () => {
  const part = (await postPart(admin.token, partBody())).payload.part;
  const store = (await postStore(admin.token, {
    orgUnitId: grantedLine.id,
    code: uniqueCode('STORE'),
    name: 'Sequence'
  })).payload.store;

  await postReceipt(admin.token, store.id, { partId: part.id, quantity: 10 });
  await postReceipt(admin.token, store.id, { partId: part.id, quantity: 5 });
  await postAdjustment(admin.token, store.id, { partId: part.id, quantityDelta: -3, reason: 'Damaged' });
  await postAdjustment(admin.token, store.id, { partId: part.id, quantityDelta: 2, reason: 'Found in a bin' });

  const { response, payload } = await getStock(admin.token, store.id);
  assert.strictEqual(response.status, 200);
  const row = payload.stock.find((s) => String(s.partId) === String(part.id));
  assert.strictEqual(row.quantity, 14);
  assert.strictEqual(row.uomCode, 'EA');

  const movements = await getMovements(admin.token, store.id);
  assert.strictEqual(movements.payload.movements.length, 4);
  assert.strictEqual(movements.payload.movements[0].movementType, 'adjustment');
});

test('the same part is reused across two stores, and each store keeps its own level', async () => {
  const part = (await postPart(admin.token, partBody())).payload.part;
  const storeA = (await postStore(admin.token, {
    orgUnitId: grantedLine.id,
    code: uniqueCode('STORE'),
    name: 'Reuse A'
  })).payload.store;
  const storeB = (await postStore(admin.token, {
    orgUnitId: otherLine.id,
    code: uniqueCode('STORE'),
    name: 'Reuse B'
  })).payload.store;

  await postReceipt(admin.token, storeA.id, { partId: part.id, quantity: 7 });
  await postReceipt(admin.token, storeB.id, { partId: part.id, quantity: 2 });

  const a = await getStock(admin.token, storeA.id);
  const b = await getStock(admin.token, storeB.id);
  assert.strictEqual(a.payload.stock.find((s) => String(s.partId) === String(part.id)).quantity, 7);
  assert.strictEqual(b.payload.stock.find((s) => String(s.partId) === String(part.id)).quantity, 2);
});

test('a part that has never moved is not stock in the store', async () => {
  const part = (await postPart(admin.token, partBody())).payload.part;
  const store = (await postStore(admin.token, {
    orgUnitId: grantedLine.id,
    code: uniqueCode('STORE'),
    name: 'Empty'
  })).payload.store;

  const { payload } = await getStock(admin.token, store.id);
  assert.ok(!payload.stock.some((s) => String(s.partId) === String(part.id)));
});

// ---------------------------------------------------------------------------
// Refusing to go below zero, with a message naming the part and the shelf.
// ---------------------------------------------------------------------------

test('a movement that would take a store below zero is refused, naming the part and what is on the shelf', async () => {
  const part = (await postPart(admin.token, partBody())).payload.part;
  const store = (await postStore(admin.token, {
    orgUnitId: grantedLine.id,
    code: uniqueCode('STORE'),
    name: 'Refusal'
  })).payload.store;
  await postReceipt(admin.token, store.id, { partId: part.id, quantity: 3 });

  const { response, payload } = await postAdjustment(admin.token, store.id, {
    partId: part.id,
    quantityDelta: -5,
    reason: 'Stocktake shows none'
  });
  assert.strictEqual(response.status, 409);
  assert.ok(payload.message.includes(part.partNo), payload.message);
  assert.ok(payload.message.includes('3 EA'), payload.message);
  assert.match(payload.message, /on the shelf/);

  // Nothing half-written: the refused movement left the shelf exactly as it
  // was.
  const stock = await getStock(admin.token, store.id);
  assert.strictEqual(stock.payload.stock.find((s) => String(s.partId) === String(part.id)).quantity, 3);
});

test('a receipt cannot go below zero either, and an unknown part is a 404', async () => {
  const store = (await postStore(admin.token, {
    orgUnitId: grantedLine.id,
    code: uniqueCode('STORE'),
    name: 'Unknown part'
  })).payload.store;

  const missing = await postReceipt(admin.token, store.id, { partId: '999999999', quantity: 1 });
  assert.strictEqual(missing.response.status, 404);
  assert.strictEqual(missing.payload.message, 'Part not found');
});

// ---------------------------------------------------------------------------
// Site-wide reads; writes need a write Grant reaching the store's Org Unit.
// ---------------------------------------------------------------------------

test('stock is readable Site-wide by an Account whose Grants reach none of it', async () => {
  const part = (await postPart(admin.token, partBody())).payload.part;
  const store = (await postStore(admin.token, {
    orgUnitId: grantedLine.id,
    code: uniqueCode('STORE'),
    name: 'Readable'
  })).payload.store;
  await postReceipt(admin.token, store.id, { partId: part.id, quantity: 4 });

  for (const account of [readOnlyAccount, noGrantAccount]) {
    // eslint-disable-next-line no-await-in-loop
    const { response, payload } = await getStock(account.token, store.id);
    assert.strictEqual(response.status, 200);
    assert.strictEqual(payload.stock.find((s) => String(s.partId) === String(part.id)).quantity, 4);
  }
});

test('a write Grant on an ancestor reaches the store beneath it', async () => {
  const store = (await postStore(admin.token, {
    orgUnitId: grantedLine.id,
    code: uniqueCode('STORE'),
    name: 'Ancestor write'
  })).payload.store;
  const part = (await postPart(admin.token, partBody())).payload.part;

  const { response } = await postReceipt(writerAccount.token, store.id, { partId: part.id, quantity: 1 });
  assert.strictEqual(response.status, 201);
});

test('a read-only Grant on the very Org Unit is refused — the write check is a write check', async () => {
  const store = (await postStore(admin.token, {
    orgUnitId: grantedLine.id,
    code: uniqueCode('STORE'),
    name: 'Read-only'
  })).payload.store;
  const part = (await postPart(admin.token, partBody())).payload.part;

  const { response, payload } = await postReceipt(readOnlyAccount.token, store.id, { partId: part.id, quantity: 1 });
  assert.strictEqual(response.status, 403);
  assert.strictEqual(payload.message, "Outside the caller's granted Org Units");
});

test('a write Grant on a sibling branch does not reach across', async () => {
  const store = (await postStore(admin.token, {
    orgUnitId: grantedLine.id,
    code: uniqueCode('STORE'),
    name: 'Sibling'
  })).payload.store;
  const part = (await postPart(admin.token, partBody())).payload.part;

  const { response } = await postReceipt(siblingWriter.token, store.id, { partId: part.id, quantity: 1 });
  assert.strictEqual(response.status, 403);
});

test('an approved Account with no Grant anywhere cannot receive', async () => {
  const store = (await postStore(admin.token, {
    orgUnitId: grantedLine.id,
    code: uniqueCode('STORE'),
    name: 'No grant'
  })).payload.store;
  const part = (await postPart(admin.token, partBody())).payload.part;

  const { response } = await postReceipt(noGrantAccount.token, store.id, { partId: part.id, quantity: 1 });
  assert.strictEqual(response.status, 403);
});

test('an unknown store is a clean 404 before scope is ever asked, even for an administrator', async () => {
  const missing = await postReceipt(admin.token, '999999999', { partId: '1', quantity: 1 });
  assert.strictEqual(missing.response.status, 404);
  assert.strictEqual(missing.payload.message, 'Store not found');

  const malformed = await postReceipt(admin.token, 'not-an-id', { partId: '1', quantity: 1 });
  assert.strictEqual(malformed.response.status, 404);
});

test('a write Grant is needed to create a store at an Org Unit', async () => {
  const refused = await postStore(readOnlyAccount.token, {
    orgUnitId: grantedLine.id,
    code: uniqueCode('STORE'),
    name: 'Refused'
  });
  assert.strictEqual(refused.response.status, 403);
  assert.strictEqual(refused.payload.message, "Outside the caller's granted Org Units");

  const allowed = await postStore(writerAccount.token, {
    orgUnitId: grantedLine.id,
    code: uniqueCode('STORE'),
    name: 'Allowed'
  });
  assert.strictEqual(allowed.response.status, 201);
});

test('an inactive store drops out of the default listing but is reachable by name', async () => {
  const created = await postStore(admin.token, {
    orgUnitId: grantedLine.id,
    code: uniqueCode('STORE'),
    name: 'Retired'
  });
  await pool.query('UPDATE stores SET is_active = FALSE WHERE id = $1', [created.payload.store.id]);

  const list = await getStores(admin.token, site);
  assert.ok(!list.payload.stores.some((s) => String(s.id) === String(created.payload.store.id)));

  const widened = await getStores(admin.token, site, '?includeInactive=true');
  assert.ok(widened.payload.stores.some((s) => String(s.id) === String(created.payload.store.id)));
});
