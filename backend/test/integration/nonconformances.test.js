/*
 * Non-conformances over HTTP (issue #205), against a real database and a real
 * (locally issued) JWKS — the same seam quality-catalogues.test.js uses, and
 * the same fixture scaffolding tier-board.test.js uses for the shift calendar.
 *
 * This file builds its own Sites, Org Units, Assets, shift definitions and
 * shift instances directly against the database, and creates its Products and
 * Defect codes through the API as an administrator, so every row a test names
 * is one the Platform itself would accept. It does not truncate `app_users`,
 * `products` or `defect_codes`: the first is shared with accounts.test.js's
 * own assertion, and the other two arrive seeded (ADR-0005's one shared
 * catalogue), so every assertion here is about rows this file created, looked
 * up by their own unique codes. Everything it inserts is deleted again in
 * `test.after()`, in dependency order.
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
const insertedAssetIds = [];
const insertedShiftDefinitionIds = [];
const insertedShiftInstanceIds = [];
const insertedProductCodes = [];
const insertedDefectCodeCodes = [];

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

async function json(response) {
  return { status: response.status, body: await response.json() };
}

// An Account, optionally holding Grants. `grants` are `{ orgUnitId, write }`
// pairs; `write` defaults to true, since most of this file's Accounts are
// recording rather than reading.
async function insertAccount({ role = 'operator', grants = [] } = {}) {
  const subject = uniqueCode('ncacct');
  const { rows: [account] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status)
     VALUES ($1, 'Non-conformance Test Account', $2, $3, TRUE, 'approved') RETURNING id`,
    [`${subject}@example.com`, role, subject]
  );
  insertedAccountIds.push(account.id);

  for (const grant of grants) {
    await pool.query(
      `INSERT INTO app_user_org_units (app_user_id, org_unit_id, can_write)
       VALUES ($1, $2, $3)`,
      [account.id, grant.orgUnitId, grant.write ?? true]
    );
  }

  return { id: account.id, token: await authHeader(subject) };
}

async function insertSite({ timezone = 'Asia/Ho_Chi_Minh', name = 'Non-conformance Test Site' } = {}) {
  const { rows: [site] } = await pool.query(
    `INSERT INTO sites (code, name, timezone) VALUES ($1, $2, $3) RETURNING id, code, name`,
    [uniqueCode('NCS'), name, timezone]
  );
  insertedSiteIds.push(site.id);
  return site;
}

async function insertOrgUnit(siteId, { parentId = null, unitType = 'area', name = 'NC Unit' } = {}) {
  const { rows: [orgUnit] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, $2, $3, $4, $5) RETURNING id, code, name, path`,
    [siteId, parentId, uniqueCode('NCOU'), name, unitType]
  );
  insertedOrgUnitIds.push(orgUnit.id);
  return orgUnit;
}

async function insertAsset(orgUnitId, { name = 'NC Asset' } = {}) {
  const { rows: [asset] } = await pool.query(
    `INSERT INTO assets (org_unit_id, code, name, asset_type, criticality)
     VALUES ($1, $2, $3, 'machine', 'high') RETURNING id, org_unit_id`,
    [orgUnitId, uniqueCode('NCAS'), name]
  );
  insertedAssetIds.push(asset.id);
  return asset;
}

async function insertShiftDefinition(siteId, {
  code = 'DAY',
  name = 'Day shift',
  startTime = '06:00',
  durationMinutes = 480,
  dayOffset = 0
} = {}) {
  const { rows: [shift] } = await pool.query(
    `INSERT INTO shift_definitions (site_id, code, name, start_time, duration_minutes, day_offset)
     VALUES ($1, $2, $3, $4, $5, $6) RETURNING id`,
    [siteId, uniqueCode(code), name, startTime, durationMinutes, dayOffset]
  );
  insertedShiftDefinitionIds.push(shift.id);
  return shift;
}

// The production-day calendar, built by the database's own
// `generate_shift_instances` — the same function a real deployment calls,
// never a hand-written `shift_instances` row. ADR-0017's whole point is that
// the bucket is the schema's answer, so a fixture that faked it would be
// testing the fixture.
async function generateShifts(orgUnitId, from, to) {
  await pool.query('SELECT generate_shift_instances($1, $2::date, $3::date)', [
    orgUnitId,
    from,
    to
  ]);
  const { rows } = await pool.query('SELECT id FROM shift_instances WHERE org_unit_id = $1', [
    orgUnitId
  ]);
  for (const row of rows) insertedShiftInstanceIds.push(row.id);
}

// A Product and a Defect code, created through the API as the administrator
// (both catalogues are administrator-only writes) and remembered for cleanup.
async function createProduct(adminToken, { uomCode = 'EA' } = {}) {
  const code = uniqueCode('NCP-');
  const response = await fetch(`${base}/api/quality/products`, {
    method: 'POST',
    headers: { ...adminToken, 'content-type': 'application/json' },
    body: JSON.stringify({ code, name: `Product ${code}`, uomCode })
  });
  const { status, body } = await json(response);
  assert.strictEqual(status, 201, `creating ${code} failed: ${JSON.stringify(body)}`);
  insertedProductCodes.push(code);
  return body.product;
}

async function createDefectCode(adminToken, { defaultSeverity = 'minor' } = {}) {
  const code = uniqueCode('NCD-');
  const response = await fetch(`${base}/api/quality/defect-codes`, {
    method: 'POST',
    headers: { ...adminToken, 'content-type': 'application/json' },
    body: JSON.stringify({
      code,
      name: `Defect ${code}`,
      category: 'product',
      defaultSeverity
    })
  });
  const { status, body } = await json(response);
  assert.strictEqual(status, 201, `creating ${code} failed: ${JSON.stringify(body)}`);
  insertedDefectCodeCodes.push(code);
  return body.defectCode;
}

async function record(token, siteId, body) {
  const response = await fetch(`${base}/api/quality/sites/${siteId}/nonconformances`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  return json(response);
}

async function listNonconformances(token, siteId, query = '') {
  const response = await fetch(
    `${base}/api/quality/sites/${siteId}/nonconformances${query}`,
    { headers: token }
  );
  return json(response);
}

async function readNonconformance(token, id) {
  const response = await fetch(`${base}/api/quality/nonconformances/${id}`, { headers: token });
  return json(response);
}

async function changeNonconformance(token, id, body) {
  const response = await fetch(`${base}/api/quality/nonconformances/${id}`, {
    method: 'PATCH',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  return json(response);
}

async function increaseQuantity(token, id, body) {
  const response = await fetch(`${base}/api/quality/nonconformances/${id}/quantity`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  return json(response);
}

// The one shape every recording in this file starts from: a Site, an Org Unit
// with a write Grant for the caller, a Product and a Defect code. Returns
// everything a test needs to vary one thing about it.
let admin;
let adminToken;

async function makeGround({ severity = 'minor', withAsset = false, withShifts = false } = {}) {
  const site = await insertSite();
  const unit = await insertOrgUnit(site.id, { name: 'Foundry Line' });
  const recorder = await insertAccount({ grants: [{ orgUnitId: unit.id }] });
  const product = await createProduct(adminToken);
  const defectCode = await createDefectCode(adminToken, { defaultSeverity: severity });
  const asset = withAsset ? await insertAsset(unit.id) : null;
  if (withShifts) {
    await insertShiftDefinition(site.id, {
      code: 'DAY',
      name: 'Day shift',
      startTime: '06:00',
      durationMinutes: 480
    });
    await generateShifts(unit.id, '2026-04-01', '2026-04-30');
  }
  return { site, unit, recorder, product, defectCode, asset };
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
  adminToken = admin.token;
});

test.after(async () => {
  // Children before parents. A Non-conformance references the Org Unit, the
  // Asset, the Product, the Defect code, the shift instance and the Account,
  // so it goes first; its quantity history is `ON DELETE CASCADE` and needs no
  // statement of its own. `defect_codes` is self-referencing, so this file
  // creates only roots and one plain DELETE is enough.
  await pool.query(
    `DELETE FROM quality_issues
      WHERE org_unit_id IN (SELECT id FROM org_units WHERE site_id = ANY($1))`,
    [insertedSiteIds]
  );
  await pool.query('DELETE FROM products WHERE code = ANY($1)', [insertedProductCodes]);
  await pool.query('DELETE FROM defect_codes WHERE code = ANY($1)', [insertedDefectCodeCodes]);
  await pool.query('DELETE FROM assets WHERE id = ANY($1)', [insertedAssetIds]);
  await pool.query('DELETE FROM shift_instances WHERE id = ANY($1)', [insertedShiftInstanceIds]);
  await pool.query('DELETE FROM shift_definitions WHERE id = ANY($1)', [
    insertedShiftDefinitionIds
  ]);
  await pool.query('DELETE FROM app_user_org_units WHERE app_user_id = ANY($1)', [
    insertedAccountIds
  ]);
  await pool.query('DELETE FROM app_users WHERE id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM org_units WHERE id = ANY($1)', [insertedOrgUnitIds]);
  await pool.query('DELETE FROM sites WHERE id = ANY($1)', [insertedSiteIds]);
  await new Promise((resolve) => server.close(resolve));
  await closePool();
  await jwks.close();
});

// ---------------------------------------------------------------------------
// 1. Recording
// ---------------------------------------------------------------------------

test('an operator with an edit Grant reaching the Org Unit records a Non-conformance and reads it back', async () => {
  const { site, unit, recorder, product, defectCode } = await makeGround({ severity: 'major' });

  const { status, body } = await record(recorder.token, site.id, {
    orgUnitId: unit.id,
    productId: product.id,
    defectCodeId: defectCode.id,
    detectionPoint: 'final_inspection',
    quantity: 12,
    lotRef: 'LOT-77'
  });

  assert.strictEqual(status, 201, JSON.stringify(body));
  const nc = body.nonconformance;
  assert.strictEqual(nc.status, 'open');
  assert.strictEqual(nc.detectionPoint, 'final_inspection');
  assert.strictEqual(nc.quantityAffected, 12);
  assert.strictEqual(nc.quantityDispositioned, 0);
  assert.strictEqual(nc.lotRef, 'LOT-77');
  // The unit of measure is the Product's own, never a caller's choice.
  assert.strictEqual(nc.uomCode, product.uomCode);
  // Severity defaults to the Defect code's own default severity.
  assert.strictEqual(nc.severity, 'major');
  assert.strictEqual(nc.defectCodeDefaultSeverity, 'major');
  // Who recorded it, as an Account.
  assert.strictEqual(nc.recordedByAccountId, String(recorder.id));
  // Names ride on the row so the list and the detail read the same shape.
  assert.strictEqual(nc.orgUnitName, 'Foundry Line');
  assert.strictEqual(nc.siteId, String(site.id));
  assert.strictEqual(nc.productId, product.id);
  assert.strictEqual(nc.productName, product.name);
  assert.strictEqual(nc.defectCodeId, defectCode.id);
  assert.strictEqual(nc.defectCodeName, defectCode.name);
  // A fresh record has no quantity history yet — an empty list, not a missing
  // field.
  assert.deepStrictEqual(nc.quantityChanges, []);

  // It is a number in the NC-year-sequence form, quoted with the Site's own
  // code (the Platform's `next_document_number`).
  assert.match(nc.issueNo, /^NC-[A-Z0-9]+-\d{4}-\d{5}$/);
  assert.ok(
    nc.issueNo.startsWith(`NC-${site.code}-`),
    `the number should quote ${site.code}: ${nc.issueNo}`
  );

  // And anyone who can see the Site finds it in the register and opens it.
  const reader = await insertAccount({ grants: [{ orgUnitId: unit.id, write: false }] });
  const listed = await listNonconformances(reader.token, site.id);
  assert.strictEqual(listed.status, 200);
  assert.deepStrictEqual(
    listed.body.nonconformances.map((row) => row.id),
    [nc.id]
  );

  const detail = await readNonconformance(reader.token, nc.id);
  assert.strictEqual(detail.status, 200);
  assert.deepStrictEqual(detail.body.nonconformance, nc);
});

test('recording is refused with 403 for an Account whose Grant does not reach the Org Unit', async () => {
  const { site, unit, product, defectCode } = await makeGround({});
  const sibling = await insertOrgUnit(site.id, { name: 'Line beside it' });
  // Granted on the sibling, read-write — the target Org Unit is not beneath it.
  const neighbour = await insertAccount({ grants: [{ orgUnitId: sibling.id }] });
  // Granted on the Org Unit itself, but read-only: read and write are
  // grantable separately (#8), and recording is a write.
  const reader = await insertAccount({ grants: [{ orgUnitId: unit.id, write: false }] });
  // Granted nowhere in this Site at all.
  const stranger = await insertAccount({});

  const request = {
    orgUnitId: unit.id,
    productId: product.id,
    defectCodeId: defectCode.id,
    detectionPoint: 'in_process',
    quantity: 3
  };

  for (const token of [neighbour.token, reader.token, stranger.token]) {
    const { status, body } = await record(token, site.id, request);
    assert.strictEqual(status, 403, JSON.stringify(body));
    assert.strictEqual(body.message, 'Outside the caller\'s granted Org Units');
  }

  // Nothing was written.
  const { body } = await listNonconformances(adminToken, site.id);
  assert.deepStrictEqual(body.nonconformances, []);
});

test('an administrator records a Non-conformance in a Site they hold no Grant in', async () => {
  const { site, unit, product, defectCode } = await makeGround({});

  const { status, body } = await record(adminToken, site.id, {
    orgUnitId: unit.id,
    productId: product.id,
    defectCodeId: defectCode.id,
    detectionPoint: 'audit',
    quantity: 5
  });

  assert.strictEqual(status, 201, JSON.stringify(body));
  assert.strictEqual(body.nonconformance.status, 'open');
});

test('an unknown Site or an Org Unit of another Site is a 404 before any Grant is asked about', async () => {
  const { unit, product, defectCode } = await makeGround({});
  const otherSite = await insertSite({ name: 'Another plant' });

  const unknownSite = await record(adminToken, 999999999, {
    orgUnitId: unit.id,
    productId: product.id,
    defectCodeId: defectCode.id,
    detectionPoint: 'audit',
    quantity: 1
  });
  assert.strictEqual(unknownSite.status, 404);
  assert.strictEqual(unknownSite.body.message, 'Site not found');

  // An Org Unit that exists but belongs to a different Site is, from this
  // endpoint's point of view, not an Org Unit of this Site at all.
  const crossSite = await record(adminToken, otherSite.id, {
    orgUnitId: unit.id,
    productId: product.id,
    defectCodeId: defectCode.id,
    detectionPoint: 'audit',
    quantity: 1
  });
  assert.strictEqual(crossSite.status, 404);
  assert.strictEqual(crossSite.body.message, 'Org Unit not found');

  const malformed = await record(adminToken, otherSite.id, {
    orgUnitId: 'not-an-id',
    productId: product.id,
    defectCodeId: defectCode.id,
    detectionPoint: 'audit',
    quantity: 1
  });
  assert.strictEqual(malformed.status, 400);
  assert.strictEqual(malformed.body.message, 'orgUnitId must be a valid Org Unit id');
});

// ---------------------------------------------------------------------------
// 2. Required and known values
// ---------------------------------------------------------------------------

test('the Product, the Defect code and the detection point are required, and the quantity must be positive', async () => {
  const { site, unit, recorder, product, defectCode } = await makeGround({});
  const complete = {
    orgUnitId: unit.id,
    productId: product.id,
    defectCodeId: defectCode.id,
    detectionPoint: 'in_process',
    quantity: 4
  };

  const cases = [
    ['productId', undefined, 400],
    ['defectCodeId', undefined, 400],
    ['detectionPoint', undefined, 400],
    ['detectionPoint', 'somewhere_else', 400],
    ['quantity', undefined, 400],
    ['quantity', 0, 400],
    ['quantity', -1, 400],
    ['quantity', 'twelve', 400]
  ];

  for (const [field, value, expected] of cases) {
    const body = { ...complete };
    if (value === undefined) delete body[field];
    else body[field] = value;

    const answer = await record(recorder.token, site.id, body);
    assert.strictEqual(answer.status, expected, `${field}=${value}: ${JSON.stringify(answer.body)}`);
    assert.ok(
      answer.body.message.includes(field),
      `${field}=${value} should name the field: ${answer.body.message}`
    );
  }

  // A numeric string is accepted — a form sends text — and is stored as a
  // number, not as a word.
  const accepted = await record(recorder.token, site.id, { ...complete, quantity: '4.5' });
  assert.strictEqual(accepted.status, 201);
  assert.strictEqual(accepted.body.nonconformance.quantityAffected, 4.5);

  const { body } = await listNonconformances(adminToken, site.id);
  assert.strictEqual(body.nonconformances.length, 1);
});

test('an unknown or retired Product or Defect code is refused — 404 when it is not there, 409 when it is retired', async () => {
  const { site, unit, recorder, product, defectCode } = await makeGround({});
  const complete = {
    orgUnitId: unit.id,
    productId: product.id,
    defectCodeId: defectCode.id,
    detectionPoint: 'in_process',
    quantity: 1
  };

  const unknownProduct = await record(recorder.token, site.id, {
    ...complete,
    productId: '999999999'
  });
  assert.strictEqual(unknownProduct.status, 404);
  assert.strictEqual(unknownProduct.body.message, 'Product not found');

  const malformedProduct = await record(recorder.token, site.id, {
    ...complete,
    productId: 'not-an-id'
  });
  assert.strictEqual(malformedProduct.status, 400);
  assert.strictEqual(malformedProduct.body.message, 'productId must be a valid Product id');

  const unknownDefect = await record(recorder.token, site.id, {
    ...complete,
    defectCodeId: '999999999'
  });
  assert.strictEqual(unknownDefect.status, 404);
  assert.strictEqual(unknownDefect.body.message, 'Defect code not found');

  // Retiring either one is a 409 naming the state that refused it, the same
  // shape a departed Employee gets on an assignee write.
  await fetch(`${base}/api/quality/products/${product.id}`, {
    method: 'PATCH',
    headers: { ...adminToken, 'content-type': 'application/json' },
    body: JSON.stringify({ isActive: false })
  });
  const retiredProduct = await record(recorder.token, site.id, complete);
  assert.strictEqual(retiredProduct.status, 409);
  assert.match(retiredProduct.body.message, /^that Product has been retired/);

  // Put the Product back so the Defect code's own refusal is the one under
  // test rather than the Product's — the Product is resolved first.
  await fetch(`${base}/api/quality/products/${product.id}`, {
    method: 'PATCH',
    headers: { ...adminToken, 'content-type': 'application/json' },
    body: JSON.stringify({ isActive: true })
  });

  await fetch(`${base}/api/quality/defect-codes/${defectCode.id}`, {
    method: 'PATCH',
    headers: { ...adminToken, 'content-type': 'application/json' },
    body: JSON.stringify({ isActive: false })
  });
  const retiredDefect = await record(recorder.token, site.id, complete);
  assert.strictEqual(retiredDefect.status, 409);
  assert.match(retiredDefect.body.message, /^that Defect code has been retired/);

  const { body } = await listNonconformances(adminToken, site.id);
  assert.deepStrictEqual(body.nonconformances, []);
});

test('an Asset, if given, must sit at that Org Unit or beneath it', async () => {
  const { site, unit, recorder, product, defectCode } = await makeGround({});
  const child = await insertOrgUnit(site.id, { parentId: unit.id, unitType: 'line', name: 'Line 1' });
  const elsewhere = await insertOrgUnit(site.id, { name: 'Packaging' });
  const atUnit = await insertAsset(unit.id);
  const beneath = await insertAsset(child.id);
  const away = await insertAsset(elsewhere.id);

  const complete = {
    orgUnitId: unit.id,
    productId: product.id,
    defectCodeId: defectCode.id,
    detectionPoint: 'in_process',
    quantity: 2
  };

  // At the Org Unit, and beneath it: both belong to "where the product was
  // found, and everything under it".
  for (const asset of [atUnit, beneath]) {
    const answer = await record(recorder.token, site.id, { ...complete, assetId: asset.id });
    assert.strictEqual(answer.status, 201, JSON.stringify(answer.body));
    assert.strictEqual(answer.body.nonconformance.assetId, String(asset.id));
    assert.strictEqual(answer.body.nonconformance.assetName, 'NC Asset');
  }

  // No Asset at all is fine: a Non-conformance about a batch need not name a
  // machine.
  const withNone = await record(recorder.token, site.id, complete);
  assert.strictEqual(withNone.status, 201);
  assert.strictEqual(withNone.body.nonconformance.assetId, null);
  assert.strictEqual(withNone.body.nonconformance.assetName, null);

  // Somewhere else in the Site is refused: the Asset exists, the placement is
  // wrong.
  const refused = await record(recorder.token, site.id, { ...complete, assetId: away.id });
  assert.strictEqual(refused.status, 400);
  assert.strictEqual(
    refused.body.message,
    'the Asset named does not sit at that Org Unit or beneath it'
  );

  const unknown = await record(recorder.token, site.id, { ...complete, assetId: '999999999' });
  assert.strictEqual(unknown.status, 404);
  assert.strictEqual(unknown.body.message, 'Asset not found');

  const malformed = await record(recorder.token, site.id, { ...complete, assetId: 'nope' });
  assert.strictEqual(malformed.status, 400);
  assert.strictEqual(malformed.body.message, 'assetId must be a valid Asset id');
});

// ---------------------------------------------------------------------------
// 3. Numbering
// ---------------------------------------------------------------------------

test("a Non-conformance's number comes from the Site's own NC sequence, in order", async () => {
  const { site, unit, recorder, product, defectCode } = await makeGround({});
  const otherSite = await insertSite({ name: 'The other plant' });
  const otherUnit = await insertOrgUnit(otherSite.id, { name: 'Other line' });

  const numbers = [];
  for (let index = 0; index < 3; index += 1) {
    const answer = await record(recorder.token, site.id, {
      orgUnitId: unit.id,
      productId: product.id,
      defectCodeId: defectCode.id,
      detectionPoint: 'in_process',
      quantity: 1
    });
    assert.strictEqual(answer.status, 201);
    numbers.push(answer.body.nonconformance.issueNo);
  }

  // Unique, and consecutive within the Site's own sequence for the year.
  assert.strictEqual(new Set(numbers).size, 3);
  const sequence = numbers.map((number) => Number(number.split('-').pop()));
  assert.deepStrictEqual(sequence, [sequence[0], sequence[0] + 1, sequence[0] + 2]);
  for (const number of numbers) {
    assert.match(number, new RegExp(`^NC-${site.code}-\\d{4}-\\d{5}$`));
  }

  // The other Site numbers independently: its own code, and its own run.
  const other = await record(adminToken, otherSite.id, {
    orgUnitId: otherUnit.id,
    productId: product.id,
    defectCodeId: defectCode.id,
    detectionPoint: 'in_process',
    quantity: 1
  });
  assert.strictEqual(other.status, 201, JSON.stringify(other.body));
  assert.match(other.body.nonconformance.issueNo, new RegExp(`^NC-${otherSite.code}-\\d{4}-00001$`));
});

// ---------------------------------------------------------------------------
// 4. The production day and the shift (ADR-0017)
// ---------------------------------------------------------------------------

test('a Non-conformance is filed against the production day and shift the moment was in, not the calendar date', async () => {
  const site = await insertSite();
  const unit = await insertOrgUnit(site.id, { name: 'Two-shift line' });
  const recorder = await insertAccount({ grants: [{ orgUnitId: unit.id }] });
  const product = await createProduct(adminToken);
  const defectCode = await createDefectCode(adminToken);

  // A site that runs 06:00-14:00 and 22:00-06:00. The 22:00 night shift belongs
  // to the production day it starts on, which is why 05:30 the next morning is
  // the *previous* day's work.
  await insertShiftDefinition(site.id, {
    code: 'DAY',
    name: 'Day shift',
    startTime: '06:00',
    durationMinutes: 480
  });
  await insertShiftDefinition(site.id, {
    code: 'NIGHT',
    name: 'Night shift',
    startTime: '22:00',
    durationMinutes: 480
  });
  await generateShifts(unit.id, '2026-05-04', '2026-05-08');

  const base = {
    orgUnitId: unit.id,
    productId: product.id,
    defectCodeId: defectCode.id,
    detectionPoint: 'in_process',
    quantity: 1
  };

  // 05:30 on the 5th, at the Site's own +07: the night shift that began 22:00
  // on the 4th is still running, so this belongs to production day 2026-05-04.
  const night = await record(recorder.token, site.id, {
    ...base,
    detectedAt: '2026-05-05T05:30:00+07:00'
  });
  assert.strictEqual(night.status, 201, JSON.stringify(night.body));
  assert.strictEqual(night.body.nonconformance.productionDate, '2026-05-04');
  assert.strictEqual(night.body.nonconformance.shiftName, 'Night shift');

  // 07:00 on the 5th is inside the day shift of the 5th.
  const day = await record(recorder.token, site.id, {
    ...base,
    detectedAt: '2026-05-05T07:00:00+07:00'
  });
  assert.strictEqual(day.body.nonconformance.productionDate, '2026-05-05');
  assert.strictEqual(day.body.nonconformance.shiftName, 'Day shift');

  // And the filing survives the read back — the shift instance is the row's
  // own column, not something the response invented.
  const detail = await readNonconformance(adminToken, night.body.nonconformance.id);
  assert.strictEqual(detail.body.nonconformance.productionDate, '2026-05-04');
  assert.strictEqual(detail.body.nonconformance.shiftInstanceId, night.body.nonconformance.shiftInstanceId);
});

test('a Non-conformance recorded outside every shift instance carries no production day rather than a guessed one', async () => {
  const { site, unit, recorder, product, defectCode } = await makeGround({});

  const { status, body } = await record(recorder.token, site.id, {
    orgUnitId: unit.id,
    productId: product.id,
    defectCodeId: defectCode.id,
    detectionPoint: 'in_process',
    quantity: 1
  });

  assert.strictEqual(status, 201, JSON.stringify(body));
  // A Site with no shift calendar covering that moment is the schema's own
  // documented case: the bucket is null and the caller handles it, rather than
  // falling back to a calendar day the ADR refuses.
  assert.strictEqual(body.nonconformance.shiftInstanceId, null);
  assert.strictEqual(body.nonconformance.productionDate, null);
  assert.strictEqual(body.nonconformance.shiftName, null);
});

// ---------------------------------------------------------------------------
// 5. Severity
// ---------------------------------------------------------------------------

test('the recorder may set a higher severity than the Defect code default, and a lower one is refused with 403', async () => {
  const { site, unit, recorder, product, defectCode } = await makeGround({ severity: 'major' });
  const complete = {
    orgUnitId: unit.id,
    productId: product.id,
    defectCodeId: defectCode.id,
    detectionPoint: 'in_process',
    quantity: 1
  };

  const lower = await record(recorder.token, site.id, { ...complete, severity: 'minor' });
  assert.strictEqual(lower.status, 403, JSON.stringify(lower.body));
  assert.strictEqual(
    lower.body.message,
    "severity cannot be set below this Defect code's own major"
  );

  const same = await record(recorder.token, site.id, { ...complete, severity: 'major' });
  assert.strictEqual(same.status, 201);
  assert.strictEqual(same.body.nonconformance.severity, 'major');

  const higher = await record(recorder.token, site.id, { ...complete, severity: 'critical' });
  assert.strictEqual(higher.status, 201);
  assert.strictEqual(higher.body.nonconformance.severity, 'critical');

  const invented = await record(recorder.token, site.id, { ...complete, severity: 'catastrophic' });
  assert.strictEqual(invented.status, 400);
  assert.match(invented.body.message, /^severity must be one of /);
});

test('severity can be raised afterwards, and lowering it is refused with 403', async () => {
  const { site, unit, recorder, product, defectCode } = await makeGround({ severity: 'minor' });
  const created = await record(recorder.token, site.id, {
    orgUnitId: unit.id,
    productId: product.id,
    defectCodeId: defectCode.id,
    detectionPoint: 'in_process',
    quantity: 1
  });
  const id = created.body.nonconformance.id;

  const raised = await changeNonconformance(recorder.token, id, { severity: 'critical' });
  assert.strictEqual(raised.status, 200, JSON.stringify(raised.body));
  assert.strictEqual(raised.body.nonconformance.severity, 'critical');

  // Which is what the detail read answers from then on.
  assert.strictEqual((await readNonconformance(adminToken, id)).body.nonconformance.severity, 'critical');

  const lowered = await changeNonconformance(recorder.token, id, { severity: 'minor' });
  assert.strictEqual(lowered.status, 403);
  assert.strictEqual(
    lowered.body.message,
    'severity cannot be lowered; only a holder of Quality authority may do that'
  );
  assert.strictEqual((await readNonconformance(adminToken, id)).body.nonconformance.severity, 'critical');

  const invented = await changeNonconformance(recorder.token, id, { severity: 'enormous' });
  assert.strictEqual(invented.status, 400);

  // Changing a Non-conformance is a write at its Org Unit — the read-only
  // Grant that may list it may not raise anything on it.
  const reader = await insertAccount({ grants: [{ orgUnitId: unit.id, write: false }] });
  const refused = await changeNonconformance(reader.token, id, { severity: 'critical' });
  assert.strictEqual(refused.status, 403);
  assert.strictEqual(refused.body.message, 'Outside the caller\'s granted Org Units');
});

// ---------------------------------------------------------------------------
// 6. Immediate containment
// ---------------------------------------------------------------------------

test('recording immediate containment makes the Non-conformance contained, then or afterwards', async () => {
  const { site, unit, recorder, product, defectCode } = await makeGround({});
  const complete = {
    orgUnitId: unit.id,
    productId: product.id,
    defectCodeId: defectCode.id,
    detectionPoint: 'in_process',
    quantity: 8
  };

  const containedAtOnce = await record(recorder.token, site.id, {
    ...complete,
    immediateContainment: 'Quarantined the bin at the line end.'
  });
  assert.strictEqual(containedAtOnce.status, 201, JSON.stringify(containedAtOnce.body));
  assert.strictEqual(containedAtOnce.body.nonconformance.status, 'contained');
  assert.strictEqual(
    containedAtOnce.body.nonconformance.immediateContainment,
    'Quarantined the bin at the line end.'
  );

  const open = await record(recorder.token, site.id, complete);
  assert.strictEqual(open.body.nonconformance.status, 'open');
  assert.strictEqual(open.body.nonconformance.immediateContainment, null);

  const contained = await changeNonconformance(recorder.token, open.body.nonconformance.id, {
    immediateContainment: 'Stopped the line and sorted the last hour of output.'
  });
  assert.strictEqual(contained.status, 200);
  assert.strictEqual(contained.body.nonconformance.status, 'contained');
  assert.strictEqual(
    contained.body.nonconformance.immediateContainment,
    'Stopped the line and sorted the last hour of output.'
  );

  const blank = await changeNonconformance(recorder.token, open.body.nonconformance.id, {
    immediateContainment: '   '
  });
  assert.strictEqual(blank.status, 400);
  assert.strictEqual(blank.body.message, 'immediateContainment is required when it is sent');
});

// ---------------------------------------------------------------------------
// 7. The affected quantity and its history
// ---------------------------------------------------------------------------

test('the affected quantity can be increased, and every change is kept with who made it and when', async () => {
  const { site, unit, recorder, product, defectCode } = await makeGround({});
  const created = await record(recorder.token, site.id, {
    orgUnitId: unit.id,
    productId: product.id,
    defectCodeId: defectCode.id,
    detectionPoint: 'in_process',
    quantity: 12
  });
  const id = created.body.nonconformance.id;

  const first = await increaseQuantity(recorder.token, id, {
    quantity: 20,
    note: 'Sorting the bin found eight more.'
  });
  assert.strictEqual(first.status, 200, JSON.stringify(first.body));
  assert.strictEqual(first.body.nonconformance.quantityAffected, 20);
  // Returned WITH the Non-conformance, which is the ticket's own criterion.
  assert.strictEqual(first.body.nonconformance.quantityChanges.length, 1);
  const [change] = first.body.nonconformance.quantityChanges;
  assert.strictEqual(change.previousQuantity, 12);
  assert.strictEqual(change.newQuantity, 20);
  assert.strictEqual(change.note, 'Sorting the bin found eight more.');
  assert.strictEqual(change.changedByAccountId, String(recorder.id));
  assert.strictEqual(change.changedByAccountName, 'Non-conformance Test Account');
  assert.ok(change.changedAt, 'a change records when it happened');

  const second = await increaseQuantity(recorder.token, id, { quantity: 26 });
  assert.strictEqual(second.status, 200);
  assert.strictEqual(second.body.nonconformance.quantityAffected, 26);
  assert.deepStrictEqual(
    second.body.nonconformance.quantityChanges.map((row) => [row.previousQuantity, row.newQuantity]),
    [[12, 20], [20, 26]]
  );
  assert.strictEqual(second.body.nonconformance.quantityChanges[1].note, null);

  // And the history is part of the record a reader opens, not a second read.
  const detail = await readNonconformance(adminToken, id);
  assert.strictEqual(detail.body.nonconformance.quantityAffected, 26);
  assert.deepStrictEqual(detail.body.nonconformance.quantityChanges, second.body.nonconformance.quantityChanges);
});

test('a decrease, or a change that changes nothing, is refused with 409 and nothing is written', async () => {
  const { site, unit, recorder, product, defectCode } = await makeGround({});
  const created = await record(recorder.token, site.id, {
    orgUnitId: unit.id,
    productId: product.id,
    defectCodeId: defectCode.id,
    detectionPoint: 'in_process',
    quantity: 12
  });
  const id = created.body.nonconformance.id;

  const decreased = await increaseQuantity(recorder.token, id, { quantity: 11 });
  assert.strictEqual(decreased.status, 409, JSON.stringify(decreased.body));
  assert.strictEqual(decreased.body.message, 'the affected quantity can only be increased');

  const unchanged = await increaseQuantity(recorder.token, id, { quantity: 12 });
  assert.strictEqual(unchanged.status, 409);
  assert.strictEqual(
    unchanged.body.message,
    'the affected quantity is already that; a change records a difference'
  );

  const nonsense = await increaseQuantity(recorder.token, id, { quantity: -3 });
  assert.strictEqual(nonsense.status, 400);
  assert.match(nonsense.body.message, /^quantity must be a positive quantity$/);

  // The row is untouched and keeps no history of the refusals.
  const detail = await readNonconformance(adminToken, id);
  assert.strictEqual(detail.body.nonconformance.quantityAffected, 12);
  assert.deepStrictEqual(detail.body.nonconformance.quantityChanges, []);

  // Increasing the quantity is a write at the Org Unit, like every other
  // change to the record.
  const reader = await insertAccount({ grants: [{ orgUnitId: unit.id, write: false }] });
  const refused = await increaseQuantity(reader.token, id, { quantity: 13 });
  assert.strictEqual(refused.status, 403);
});

// ---------------------------------------------------------------------------
// 8. The register's filters
// ---------------------------------------------------------------------------

test('any Account that can see the Site lists Non-conformances filtered by Org Unit (and beneath it), status, Defect code, Product, severity and a date range', async () => {
  const site = await insertSite();
  const line = await insertOrgUnit(site.id, { name: 'Assembly' });
  const cell = await insertOrgUnit(site.id, { parentId: line.id, unitType: 'cell', name: 'Cell 1' });
  const packaging = await insertOrgUnit(site.id, { name: 'Packaging' });
  // Granted on both areas, because this test places rows in both: a Grant
  // reaches downward, and Packaging is not beneath Assembly.
  const recorder = await insertAccount({
    grants: [{ orgUnitId: line.id }, { orgUnitId: packaging.id }]
  });

  // A site whose calendar this test can place rows against.
  await insertShiftDefinition(site.id, {
    code: 'DAY',
    name: 'Day shift',
    startTime: '06:00',
    durationMinutes: 480
  });
  await generateShifts(line.id, '2026-06-01', '2026-06-30');
  await generateShifts(cell.id, '2026-06-01', '2026-06-30');
  await generateShifts(packaging.id, '2026-06-01', '2026-06-30');

  const productA = await createProduct(adminToken);
  const productB = await createProduct(adminToken);
  const defectA = await createDefectCode(adminToken, { defaultSeverity: 'minor' });
  const defectB = await createDefectCode(adminToken, { defaultSeverity: 'major' });

  async function place(orgUnitId, when, extra = {}) {
    const answer = await record(recorder.token, site.id, {
      orgUnitId,
      productId: productA.id,
      defectCodeId: defectA.id,
      detectionPoint: 'in_process',
      quantity: 1,
      detectedAt: when,
      ...extra
    });
    assert.strictEqual(answer.status, 201, JSON.stringify(answer.body));
    return answer.body.nonconformance;
  }

  const onCellSixth = await place(cell.id, '2026-06-06T08:00:00+07:00');
  const onCellSeventh = await place(cell.id, '2026-06-07T08:00:00+07:00', {
    defectCodeId: defectB.id,
    severity: 'critical'
  });
  const onLineEighth = await place(line.id, '2026-06-08T08:00:00+07:00', {
    productId: productB.id
  });
  const onPackagingNinth = await place(packaging.id, '2026-06-09T08:00:00+07:00');

  // A reader with a read-only Grant somewhere in the Site sees all of them —
  // "anyone who can see the Site can find and read it".
  const reader = await insertAccount({ grants: [{ orgUnitId: packaging.id, write: false }] });

  const all = await listNonconformances(reader.token, site.id);
  assert.strictEqual(all.status, 200);
  assert.strictEqual(all.body.truncated, false);
  assert.deepStrictEqual(
    all.body.nonconformances.map((row) => row.id),
    [onPackagingNinth.id, onLineEighth.id, onCellSeventh.id, onCellSixth.id],
    'newest first'
  );

  // Org Unit, including everything beneath it — the ticket's own words.
  const atLine = await listNonconformances(reader.token, site.id, `?orgUnitId=${line.id}`);
  assert.deepStrictEqual(
    atLine.body.nonconformances.map((row) => row.id),
    [onLineEighth.id, onCellSeventh.id, onCellSixth.id]
  );
  const atCell = await listNonconformances(reader.token, site.id, `?orgUnitId=${cell.id}`);
  assert.deepStrictEqual(
    atCell.body.nonconformances.map((row) => row.id),
    [onCellSeventh.id, onCellSixth.id]
  );

  // Status, Defect code, Product and severity.
  const open = await listNonconformances(reader.token, site.id, '?status=open');
  assert.strictEqual(open.body.nonconformances.length, 4);
  const contained = await listNonconformances(reader.token, site.id, '?status=contained');
  assert.deepStrictEqual(contained.body.nonconformances, []);
  assert.strictEqual(
    (await listNonconformances(reader.token, site.id, `?defectCodeId=${defectB.id}`)).body
      .nonconformances.length,
    1
  );
  assert.strictEqual(
    (await listNonconformances(reader.token, site.id, `?productId=${productB.id}`)).body
      .nonconformances.length,
    1
  );
  assert.deepStrictEqual(
    (await listNonconformances(reader.token, site.id, '?severity=critical')).body.nonconformances.map(
      (row) => row.id
    ),
    [onCellSeventh.id]
  );

  // A date range, over production days: one day, one row.
  const oneDay = await listNonconformances(reader.token, site.id, '?from=2026-06-07&to=2026-06-07');
  assert.deepStrictEqual(oneDay.body.nonconformances.map((row) => row.id), [onCellSeventh.id]);
  const twoDays = await listNonconformances(reader.token, site.id, '?from=2026-06-07&to=2026-06-08');
  assert.deepStrictEqual(twoDays.body.nonconformances.map((row) => row.id), [
    onLineEighth.id,
    onCellSeventh.id
  ]);

  // Filters compose.
  const composed = await listNonconformances(
    reader.token,
    site.id,
    `?orgUnitId=${line.id}&severity=critical&from=2026-06-01&to=2026-06-06`
  );
  assert.deepStrictEqual(composed.body.nonconformances, []);

  // A value outside a closed set is a mistake the caller can fix, not a quiet
  // empty list.
  const typo = await listNonconformances(reader.token, site.id, '?status=opne');
  assert.strictEqual(typo.status, 400);
  assert.match(typo.body.message, /^status must be one of: /);
  const badDate = await listNonconformances(reader.token, site.id, '?from=June%201st');
  assert.strictEqual(badDate.status, 400);
  assert.strictEqual(badDate.body.message, 'from must be a date in YYYY-MM-DD form');
  const badId = await listNonconformances(reader.token, site.id, '?productId=not-an-id');
  assert.strictEqual(badId.status, 400);
  assert.strictEqual(badId.body.message, 'productId must be a valid id');
  const unknownOrgUnit = await listNonconformances(reader.token, site.id, '?orgUnitId=999999999');
  assert.strictEqual(unknownOrgUnit.status, 404);
  assert.strictEqual(unknownOrgUnit.body.message, 'Org Unit not found');
});

test('an Account holding no Grant in the Site is refused the register and a Non-conformance detail alike', async () => {
  const { site, unit, recorder, product, defectCode } = await makeGround({});
  const created = await record(recorder.token, site.id, {
    orgUnitId: unit.id,
    productId: product.id,
    defectCodeId: defectCode.id,
    detectionPoint: 'in_process',
    quantity: 1
  });
  const id = created.body.nonconformance.id;

  const outsider = await insertAccount({});
  const otherSite = await insertSite({ name: 'Elsewhere' });
  const otherUnit = await insertOrgUnit(otherSite.id, { name: 'Elsewhere line' });
  const elsewhere = await insertAccount({ grants: [{ orgUnitId: otherUnit.id }] });

  for (const token of [outsider.token, elsewhere.token]) {
    const listed = await listNonconformances(token, site.id);
    assert.strictEqual(listed.status, 403, JSON.stringify(listed.body));
    assert.strictEqual(listed.body.message, 'Outside the caller\'s granted Org Units');

    const detail = await readNonconformance(token, id);
    assert.strictEqual(detail.status, 403);
  }

  // An unknown id is a clean 404, malformed included, and an unauthenticated
  // caller never reaches any of it.
  assert.strictEqual((await readNonconformance(adminToken, 999999999)).status, 404);
  assert.strictEqual((await readNonconformance(adminToken, 'not-an-id')).status, 404);
  assert.strictEqual(
    (await readNonconformance(adminToken, 999999999)).body.message,
    'Non-conformance not found'
  );
  const anonymous = await fetch(`${base}/api/quality/sites/${site.id}/nonconformances`);
  assert.strictEqual(anonymous.status, 401);
  const anonymousDetail = await fetch(`${base}/api/quality/nonconformances/${id}`);
  assert.strictEqual(anonymousDetail.status, 401);
});
