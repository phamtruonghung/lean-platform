/*
 * Suppliers and supplier NCRs (issue #215) — over HTTP, against a real
 * database and a real (locally issued) JWKS. The seam, the fixture scaffolding
 * and the dependency-ordered cleanup are the ones
 * `customer-complaints.test.js` — the mirror slice this one follows — already
 * establishes.
 *
 * Everything the ticket's acceptance criteria name is exercised here, one test
 * per criterion and each refusal proved rather than assumed: the Supplier list
 * read and searched by any active Account with its writes the administrator's
 * alone (403), a duplicate Supplier code (409), recording a supplier NCR behind
 * an edit Grant reaching its Org Unit (403 without one, 404 for an Org Unit
 * that is not there or belongs to another Site), the Supplier required (400)
 * and the Defect code chosen from the catalogue rather than typed (404 for one
 * that is not there, 409 for a retired one), a Non-conformance recorded from an
 * NCR with `detection_point = 'incoming'`, an existing one linked instead (with
 * the link's own refusals), the Supplier's disposition and cost recovered
 * recorded and the NCR closed (400 for a disposition outside the baseline's own
 * five, 409 for a second close), and the register narrowed by Supplier and by
 * status with the past-due rows marked.
 *
 * **"Each shows the other" is asserted from both ends**, which is the only way
 * that criterion can be honoured: the NCR's own read returns the Non-conformance
 * that controls the received lot, and the Non-conformance's own read — the
 * Quality Module's existing detail address, not a new one — returns the
 * supplier NCRs that name it.
 *
 * Needs a database with every migration applied. This slice adds no migration
 * of its own: `supplier_ncrs` already carries the disposition, the cost
 * recovered and the closure, which is the difference between it and the
 * customer complaint slice that had to add `response_note`. Set DATABASE_URL
 * first — see the README's Tests section.
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
const insertedProductCodes = [];
const insertedDefectCodeCodes = [];
const insertedSupplierCodes = [];

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
  // Concatenated rather than written as one template literal: an auth header
  // in a file's own content is masked in transit by the tooling that writes
  // it, which would land a syntax error here.
  return { authorization: 'Bearer ' + token };
}

async function json(response) {
  return { status: response.status, body: await response.json() };
}

// An Account, optionally holding Grants. `write` defaults to true, since most
// of these Accounts record; `quality` is the independent flag ADR-0035 keeps
// beside it and is not needed by this slice at all — nothing here is a decision
// about nonconforming product.
async function insertAccount({ role = 'operator', displayName = null, grants = [] } = {}) {
  const subject = uniqueCode('snacct');
  const name = displayName ?? `Supplier NCR Account ${subject}`;
  const { rows: [account] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status)
     VALUES ($1, $2, $3, $4, TRUE, 'approved') RETURNING id`,
    [`${subject}@example.com`, name, role, subject]
  );
  insertedAccountIds.push(account.id);

  for (const grant of grants) {
    await pool.query(
      `INSERT INTO app_user_org_units (app_user_id, org_unit_id, can_write, quality_authority)
       VALUES ($1, $2, $3, $4)`,
      [account.id, grant.orgUnitId, grant.write ?? true, grant.quality ?? false]
    );
  }

  return { id: account.id, displayName: name, token: await authHeader(subject) };
}

async function insertSite({ name = 'Supplier Test Site' } = {}) {
  const { rows: [site] } = await pool.query(
    `INSERT INTO sites (code, name, timezone) VALUES ($1, $2, $3) RETURNING id, code, name`,
    [uniqueCode('SNS'), name, 'Asia/Ho_Chi_Minh']
  );
  insertedSiteIds.push(site.id);
  return site;
}

async function insertOrgUnit(siteId, { parentId = null, unitType = 'area', name = 'Supplier Unit' } = {}) {
  const { rows: [orgUnit] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, $2, $3, $4, $5) RETURNING id, code, name, path`,
    [siteId, parentId, uniqueCode('SNOU'), name, unitType]
  );
  insertedOrgUnitIds.push(orgUnit.id);
  return orgUnit;
}

async function createProduct(adminToken, { name = null } = {}) {
  const code = uniqueCode('SNP-');
  const response = await fetch(`${base}/api/quality/products`, {
    method: 'POST',
    headers: { ...adminToken, 'content-type': 'application/json' },
    body: JSON.stringify({ code, name: name ?? `Product ${code}`, uomCode: 'EA' })
  });
  const { status, body } = await json(response);
  assert.strictEqual(status, 201, `creating ${code} failed: ${JSON.stringify(body)}`);
  insertedProductCodes.push(code);
  return body.product;
}

async function createDefectCode(adminToken) {
  const code = uniqueCode('SND-');
  const response = await fetch(`${base}/api/quality/defect-codes`, {
    method: 'POST',
    headers: { ...adminToken, 'content-type': 'application/json' },
    body: JSON.stringify({ code, name: `Defect ${code}`, category: 'material', defaultSeverity: 'major' })
  });
  const { status, body } = await json(response);
  assert.strictEqual(status, 201, `creating ${code} failed: ${JSON.stringify(body)}`);
  insertedDefectCodeCodes.push(code);
  return body.defectCode;
}

// ---------------------------------------------------------------------------
// The addresses this file drives
// ---------------------------------------------------------------------------

async function listSuppliers(token, query = '') {
  const response = await fetch(`${base}/api/quality/suppliers${query}`, { headers: token });
  return json(response);
}

async function createSupplier(token, body) {
  const response = await fetch(`${base}/api/quality/suppliers`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  const payload = await json(response);
  if (payload.status === 201) insertedSupplierCodes.push(payload.body.supplier.code);
  return payload;
}

async function correctSupplier(token, id, body) {
  const response = await fetch(`${base}/api/quality/suppliers/${id}`, {
    method: 'PATCH',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  return json(response);
}

async function listSupplierNcrs(token, siteId, query = '') {
  const response = await fetch(`${base}/api/quality/sites/${siteId}/supplier-ncrs${query}`, {
    headers: token
  });
  return json(response);
}

async function recordSupplierNcr(token, siteId, body) {
  const response = await fetch(`${base}/api/quality/sites/${siteId}/supplier-ncrs`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  return json(response);
}

async function readSupplierNcr(token, id) {
  const response = await fetch(`${base}/api/quality/supplier-ncrs/${id}`, { headers: token });
  return json(response);
}

async function recordDisposition(token, id, body) {
  const response = await fetch(`${base}/api/quality/supplier-ncrs/${id}/disposition`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  return json(response);
}

async function closeSupplierNcr(token, id) {
  const response = await fetch(`${base}/api/quality/supplier-ncrs/${id}/close`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify({})
  });
  return json(response);
}

async function recordNonconformanceFromSupplierNcr(token, id, body = {}) {
  const response = await fetch(`${base}/api/quality/supplier-ncrs/${id}/nonconformance`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  return json(response);
}

async function linkNonconformance(token, id, body) {
  const response = await fetch(`${base}/api/quality/supplier-ncrs/${id}/link`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  return json(response);
}

// A Non-conformance recorded the ordinary way — the address issue #205
// publishes — so that the link road has an existing record to point at.
async function recordNonconformance(token, siteId, body) {
  const response = await fetch(`${base}/api/quality/sites/${siteId}/nonconformances`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  return json(response);
}

async function readNonconformance(token, id) {
  const response = await fetch(`${base}/api/quality/nonconformances/${id}`, { headers: token });
  return json(response);
}

let admin;
let adminToken;

// The ground most tests start from: a Site with an area and a line beneath it,
// a quality engineer granted on the area (so the line's subtree is theirs), a
// Supplier, a Product and a Defect code — each created through the API, so the
// fixtures are records the Platform itself would have made.
async function makeGround() {
  const site = await insertSite();
  const area = await insertOrgUnit(site.id, { name: 'Goods In' });
  const line = await insertOrgUnit(site.id, {
    parentId: area.id,
    unitType: 'line',
    name: 'Incoming Inspection'
  });
  const otherArea = await insertOrgUnit(site.id, { name: 'Stores' });

  const engineer = await insertAccount({
    displayName: 'Quality Engineer',
    grants: [{ orgUnitId: area.id, write: true }]
  });

  const supplier = (
    await createSupplier(adminToken, {
      code: uniqueCode('SUP-'),
      name: `Northwind Fasteners ${uniqueCode('')}`,
      contactEmail: 'quality@northwind.example.com'
    })
  ).body.supplier;
  const product = await createProduct(adminToken);
  const defectCode = await createDefectCode(adminToken);

  return { site, area, line, otherArea, engineer, supplier, product, defectCode };
}

function ncrBody(ground, overrides = {}) {
  return {
    orgUnitId: ground.line.id,
    supplierId: ground.supplier.id,
    productId: ground.product.id,
    defectCodeId: ground.defectCode.id,
    quantity: 250,
    incomingLotRef: 'LOT-4771',
    description: 'The thread on the M8 bolts is undersized and the nuts will not run up.',
    ...overrides
  };
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

  admin = await insertAccount({ role: 'admin', displayName: 'Avery Administrator' });
  adminToken = admin.token;
});

test.after(async () => {
  // Children before parents, hardest descendant first. A supplier NCR names its
  // Non-conformance through a plain foreign key, so the NCRs have to go before
  // the Non-conformances; the Non-conformances before the Org Units they sit
  // at; and the Supplier before nothing, since only an NCR points at one. A
  // rejected `test.after` does not fail fast: it hangs the file on the
  // framework's timeout and cancels every file behind it.
  await pool.query(
    `DELETE FROM supplier_ncrs
      WHERE org_unit_id IN (SELECT id FROM org_units WHERE site_id = ANY($1))`,
    [insertedSiteIds]
  );
  await pool.query(
    `DELETE FROM quality_issues
      WHERE org_unit_id IN (SELECT id FROM org_units WHERE site_id = ANY($1))`,
    [insertedSiteIds]
  );
  await pool.query('DELETE FROM products WHERE code = ANY($1)', [insertedProductCodes]);
  await pool.query('DELETE FROM defect_codes WHERE code = ANY($1)', [insertedDefectCodeCodes]);
  await pool.query('DELETE FROM suppliers WHERE code = ANY($1)', [insertedSupplierCodes]);
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
// 1. The Supplier list
// ---------------------------------------------------------------------------

test('an administrator defines a Supplier, and any active Account can read and search the list', async () => {
  const ground = await makeGround();

  // A second Supplier, so a search has something to leave out.
  const other = await createSupplier(adminToken, {
    code: uniqueCode('SUP-'),
    name: 'Zenith Castings'
  });
  assert.strictEqual(other.status, 201, JSON.stringify(other.body));

  // The row the administrator gets back is the row the catalogue reads: code,
  // name, the contact address, and that it is in use.
  const supplier = ground.supplier;
  assert.strictEqual(supplier.contactEmail, 'quality@northwind.example.com');
  assert.strictEqual(supplier.isActive, true);

  // A caller with no Grant anywhere reads and searches it: the ticket's own
  // criterion, and the reason this read carries no role check at all.
  const outsider = await insertAccount({ displayName: 'Stores Operator' });
  const all = await listSuppliers(outsider.token);
  assert.strictEqual(all.status, 200, JSON.stringify(all.body));
  assert.ok(all.body.suppliers.some((row) => row.id === supplier.id));

  // Search matches the code and the name — the two things a caller has to hand
  // when they are recording a supplier NCR.
  const byName = await listSuppliers(outsider.token, '?search=Northwind');
  assert.deepStrictEqual(
    byName.body.suppliers.map((row) => row.id),
    [supplier.id]
  );
  const byCode = await listSuppliers(outsider.token, `?search=${supplier.code}`);
  assert.deepStrictEqual(
    byCode.body.suppliers.map((row) => row.code),
    [supplier.code]
  );

  // Deactivating is a correction, not a deletion, and the row is reachable
  // afterwards only when the caller asks for the retired ones.
  const retired = await correctSupplier(adminToken, supplier.id, { isActive: false });
  assert.strictEqual(retired.status, 200, JSON.stringify(retired.body));
  assert.strictEqual(retired.body.supplier.isActive, false);

  const active = await listSuppliers(outsider.token, `?search=${supplier.code}`);
  assert.deepStrictEqual(active.body.suppliers, []);
  const withInactive = await listSuppliers(
    outsider.token,
    `?search=${supplier.code}&includeInactive=true`
  );
  assert.deepStrictEqual(
    withInactive.body.suppliers.map((row) => row.code),
    [supplier.code]
  );
});

test("Supplier writes are the administrator's, and a code already taken is refused", async () => {
  const ground = await makeGround();

  // Three callers who may read the list and may not write it: an operator with
  // no Grant anywhere, an engineer holding an edit Grant on the area, and an
  // operator holding one on the line.
  const outsider = await insertAccount({ displayName: 'Stores Operator' });
  const engineer = ground.engineer;
  const lineInspector = await insertAccount({
    displayName: 'Line Inspector',
    grants: [{ orgUnitId: ground.line.id, write: true }]
  });

  for (const caller of [outsider, engineer, lineInspector]) {
    const created = await createSupplier(caller.token, {
      code: uniqueCode('SUP-'),
      name: 'Not this caller to define'
    });
    assert.strictEqual(created.status, 403, JSON.stringify(created.body));
    assert.match(created.body.message, /administrator/);

    const corrected = await correctSupplier(caller.token, ground.supplier.id, {
      name: 'Not this caller to correct'
    });
    assert.strictEqual(corrected.status, 403, JSON.stringify(corrected.body));
  }

  // The administrator may, and a duplicate code is a 409 from the database's
  // own unique index rather than a check the API races.
  const duplicate = await createSupplier(adminToken, {
    code: ground.supplier.code,
    name: 'A second Northwind'
  });
  assert.strictEqual(duplicate.status, 409, JSON.stringify(duplicate.body));
  assert.match(duplicate.body.message, /already exists/);

  // Its code is what a supplier NCR quotes, so a correction may not rewrite it,
  // and an unknown Supplier is a 404 for the administrator too.
  const rewritten = await correctSupplier(adminToken, ground.supplier.id, {
    code: uniqueCode('SUP-')
  });
  assert.strictEqual(rewritten.status, 400, JSON.stringify(rewritten.body));
  const missing = await correctSupplier(adminToken, 999999999, { name: 'Nobody' });
  assert.strictEqual(missing.status, 404, JSON.stringify(missing.body));
  const malformed = await correctSupplier(adminToken, 'not-an-id', { name: 'Nobody' });
  assert.strictEqual(malformed.status, 404, JSON.stringify(malformed.body));
});

// ---------------------------------------------------------------------------
// 2. Recording a supplier NCR
// ---------------------------------------------------------------------------

test('a supplier NCR records the Supplier, the incoming lot, the Defect code, the quantity and the response due day', async () => {
  const ground = await makeGround();

  const recorded = await recordSupplierNcr(
    ground.engineer.token,
    ground.site.id,
    ncrBody(ground, {
      responseDueDate: '2099-01-01',
      purchaseRef: 'PO-88213'
    })
  );
  assert.strictEqual(recorded.status, 201, JSON.stringify(recorded.body));

  const ncr = recorded.body.supplierNcr;
  // Its own number, from the baseline's own sequence: the prefix a person
  // quotes, the year and a zero-padded sequence.
  assert.match(ncr.ncrNo, /^SN-\d{4}-\d{5}$/);
  assert.strictEqual(ncr.status, 'open');
  // The records it names, read back with the names a reader needs rather than
  // only their ids.
  assert.strictEqual(ncr.supplierId, String(ground.supplier.id));
  assert.strictEqual(ncr.supplierCode, ground.supplier.code);
  assert.strictEqual(ncr.supplierName, ground.supplier.name);
  assert.strictEqual(ncr.productId, String(ground.product.id));
  assert.strictEqual(ncr.productCode, ground.product.code);
  assert.strictEqual(ncr.defectCodeId, String(ground.defectCode.id));
  assert.strictEqual(ncr.defectCodeCode, ground.defectCode.code);
  // Filed where it is worked, and read with its Site.
  assert.strictEqual(ncr.orgUnitId, String(ground.line.id));
  assert.strictEqual(ncr.orgUnitName, 'Incoming Inspection');
  assert.strictEqual(ncr.siteId, String(ground.site.id));
  // What came in, in the unit the Product is measured in — the quantity's unit
  // is the Product's own unless the caller names another.
  assert.strictEqual(ncr.quantityAffected, 250);
  assert.strictEqual(ncr.uomCode, 'EA');
  assert.strictEqual(ncr.incomingLotRef, 'LOT-4771');
  assert.strictEqual(ncr.purchaseRef, 'PO-88213');
  assert.strictEqual(
    ncr.description,
    'The thread on the M8 bolts is undersized and the nuts will not run up.'
  );
  // The day the caller chose, in the Site's own calendar, and the instant that
  // day ends at — not a date that has not fallen due and not one already past.
  assert.strictEqual(ncr.responseDueDate, '2099-01-01');
  assert.notStrictEqual(ncr.responseDueAt, null);
  assert.strictEqual(ncr.isOverdue, false);
  assert.strictEqual(ncr.daysOverdue, null);
  // The baseline's own default stands until the quality engineer records the
  // Supplier's disposition — the recording write does not decide it.
  assert.strictEqual(ncr.disposition, 'return_to_supplier');
  assert.strictEqual(ncr.costRecovered, null);
  assert.strictEqual(ncr.currency, 'USD');
  // Nothing has been controlled or closed yet.
  assert.strictEqual(ncr.closedAt, null);
  assert.strictEqual(ncr.nonconformance, null);

  // And the same row is what its own address reads.
  const read = await readSupplierNcr(ground.engineer.token, ncr.id);
  assert.strictEqual(read.status, 200, JSON.stringify(read.body));
  assert.deepStrictEqual(read.body.supplierNcr, ncr);
});

test('recording a supplier NCR needs an edit Grant reaching its Org Unit, the Supplier, and a Defect code from the catalogue', async () => {
  const ground = await makeGround();

  // A caller who can see the Site but holds no edit Grant at the Org Unit the
  // NCR would be filed at. The read grant reaches the line; the write does not.
  const reader = await insertAccount({
    displayName: 'Read Only',
    grants: [{ orgUnitId: ground.line.id, write: false }]
  });
  const refused = await recordSupplierNcr(reader.token, ground.site.id, ncrBody(ground));
  assert.strictEqual(refused.status, 403, JSON.stringify(refused.body));
  assert.match(refused.body.message, /granted Org Units/);

  // A caller with no Grant anywhere in the Site at all.
  const outsider = await insertAccount({ displayName: 'Stores Operator' });
  const invisible = await recordSupplierNcr(outsider.token, ground.site.id, ncrBody(ground));
  assert.strictEqual(invisible.status, 403, JSON.stringify(invisible.body));

  // Existence before scope, and the Org Unit named must belong to this Site.
  const unknownUnit = await recordSupplierNcr(ground.engineer.token, ground.site.id, {
    ...ncrBody(ground),
    orgUnitId: 999999999
  });
  assert.strictEqual(unknownUnit.status, 404, JSON.stringify(unknownUnit.body));
  const nonsenseUnit = await recordSupplierNcr(ground.engineer.token, ground.site.id, {
    ...ncrBody(ground),
    orgUnitId: 'not-an-id'
  });
  assert.strictEqual(nonsenseUnit.status, 400, JSON.stringify(nonsenseUnit.body));

  const otherSite = await insertSite({ name: 'Another Plant' });
  const otherUnit = await insertOrgUnit(otherSite.id, { name: 'Their Goods In' });
  const crossSite = await recordSupplierNcr(ground.engineer.token, ground.site.id, {
    ...ncrBody(ground),
    orgUnitId: otherUnit.id
  });
  assert.strictEqual(crossSite.status, 404, JSON.stringify(crossSite.body));

  // The Supplier is required: a request that names none is refused field by
  // field, a malformed one is a 400 and one that names no Supplier is a 404
  // rather than a raw foreign key failure.
  const noSupplier = await recordSupplierNcr(ground.engineer.token, ground.site.id, {
    ...ncrBody(ground),
    supplierId: undefined
  });
  assert.strictEqual(noSupplier.status, 400, JSON.stringify(noSupplier.body));
  assert.match(noSupplier.body.message, /supplierId/);
  const malformedSupplier = await recordSupplierNcr(ground.engineer.token, ground.site.id, {
    ...ncrBody(ground),
    supplierId: 'northwind'
  });
  assert.strictEqual(malformedSupplier.status, 400, JSON.stringify(malformedSupplier.body));
  const unknownSupplier = await recordSupplierNcr(ground.engineer.token, ground.site.id, {
    ...ncrBody(ground),
    supplierId: 999999999
  });
  assert.strictEqual(unknownSupplier.status, 404, JSON.stringify(unknownSupplier.body));

  // A quantity is required and must be more than nothing — the baseline's own
  // two columns say so, and the refusal names the field.
  const noQuantity = await recordSupplierNcr(ground.engineer.token, ground.site.id, {
    ...ncrBody(ground),
    quantity: undefined
  });
  assert.strictEqual(noQuantity.status, 400, JSON.stringify(noQuantity.body));
  assert.match(noQuantity.body.message, /quantity/);
  const zeroQuantity = await recordSupplierNcr(ground.engineer.token, ground.site.id, {
    ...ncrBody(ground),
    quantity: 0
  });
  assert.strictEqual(zeroQuantity.status, 400, JSON.stringify(zeroQuantity.body));

  // The Defect code is chosen from the catalogue, never typed: one that is not
  // there is a 404, a malformed one a 400, and one the plant has retired a 409
  // naming its state.
  const unknownDefect = await recordSupplierNcr(ground.engineer.token, ground.site.id, {
    ...ncrBody(ground),
    defectCodeId: 999999999
  });
  assert.strictEqual(unknownDefect.status, 404, JSON.stringify(unknownDefect.body));
  const typedDefect = await recordSupplierNcr(ground.engineer.token, ground.site.id, {
    ...ncrBody(ground),
    defectCodeId: 'undersized-thread'
  });
  assert.strictEqual(typedDefect.status, 400, JSON.stringify(typedDefect.body));

  const retiredCode = await createDefectCode(adminToken);
  const retiredProduct = await createProduct(adminToken);
  await fetch(`${base}/api/quality/defect-codes/${retiredCode.id}`, {
    method: 'PATCH',
    headers: { ...adminToken, 'content-type': 'application/json' },
    body: JSON.stringify({ isActive: false })
  });
  await fetch(`${base}/api/quality/products/${retiredProduct.id}`, {
    method: 'PATCH',
    headers: { ...adminToken, 'content-type': 'application/json' },
    body: JSON.stringify({ isActive: false })
  });

  const retired = await recordSupplierNcr(ground.engineer.token, ground.site.id, {
    ...ncrBody(ground),
    defectCodeId: retiredCode.id
  });
  assert.strictEqual(retired.status, 409, JSON.stringify(retired.body));
  const retiredAgainst = await recordSupplierNcr(ground.engineer.token, ground.site.id, {
    ...ncrBody(ground),
    productId: retiredProduct.id
  });
  assert.strictEqual(retiredAgainst.status, 409, JSON.stringify(retiredAgainst.body));

  // A unit of measure is never free text (ADR-0023): one the plant does not use
  // is a 400.
  const wrongUnit = await recordSupplierNcr(ground.engineer.token, ground.site.id, {
    ...ncrBody(ground),
    uomCode: 'squillions'
  });
  assert.strictEqual(wrongUnit.status, 400, JSON.stringify(wrongUnit.body));

  // A retired Supplier is not refused, unlike a retired Product: an incoming lot
  // from somebody the plant no longer buys from is still worth recording, and
  // the NCR's own read carries the Supplier's own state.
  const former = await createSupplier(adminToken, {
    code: uniqueCode('SUP-'),
    name: 'Former Supplier'
  });
  await correctSupplier(adminToken, former.body.supplier.id, { isActive: false });
  const fromFormer = await recordSupplierNcr(ground.engineer.token, ground.site.id, {
    ...ncrBody(ground),
    supplierId: former.body.supplier.id
  });
  assert.strictEqual(fromFormer.status, 201, JSON.stringify(fromFormer.body));

  // Nothing was written by any refusal but the one permitted write.
  const register = await listSupplierNcrs(ground.engineer.token, ground.site.id);
  assert.strictEqual(register.body.supplierNcrs.length, 1);
});

// The lot can be received with no Product named at all: an inspector has a
// pallet in front of them, and what it is destined for may not be known. The
// quantity's unit then has to be named, because there is no Product to take it
// from.
test('a supplier NCR may name no Product, and then its unit of measure is required', async () => {
  const ground = await makeGround();

  const noUnit = await recordSupplierNcr(ground.engineer.token, ground.site.id, {
    orgUnitId: ground.line.id,
    supplierId: ground.supplier.id,
    quantity: 40
  });
  assert.strictEqual(noUnit.status, 400, JSON.stringify(noUnit.body));
  assert.match(noUnit.body.message, /uomCode is required/);

  const withUnit = await recordSupplierNcr(ground.engineer.token, ground.site.id, {
    orgUnitId: ground.line.id,
    supplierId: ground.supplier.id,
    quantity: 40,
    uomCode: 'EA',
    incomingLotRef: 'LOT-9001'
  });
  assert.strictEqual(withUnit.status, 201, JSON.stringify(withUnit.body));
  assert.strictEqual(withUnit.body.supplierNcr.productId, null);
  assert.strictEqual(withUnit.body.supplierNcr.uomCode, 'EA');
  assert.strictEqual(withUnit.body.supplierNcr.quantityAffected, 40);
});

// ---------------------------------------------------------------------------
// 3. Controlling the received product
// ---------------------------------------------------------------------------

test('a Non-conformance recorded from a supplier NCR carries detection point incoming and the NCR own Product and Defect code, and each record names the other', async () => {
  const ground = await makeGround();

  const recorded = await recordSupplierNcr(
    ground.engineer.token,
    ground.site.id,
    ncrBody(ground, { responseDueDate: '2099-01-01' })
  );
  assert.strictEqual(recorded.status, 201, JSON.stringify(recorded.body));
  const ncr = recorded.body.supplierNcr;

  // Recorded from the NCR, with nothing named in the body: the Product, the
  // Defect code, the quantity, the lot and the description come from the NCR,
  // because that is the record the inspector's eyes produced.
  const created = await recordNonconformanceFromSupplierNcr(ground.engineer.token, ncr.id, {});
  assert.strictEqual(created.status, 201, JSON.stringify(created.body));

  const nonconformance = created.body.nonconformance;
  assert.match(nonconformance.issueNo, /^NC-/);
  // Detection point incoming: the goods-in gate is where the plant found out.
  assert.strictEqual(nonconformance.detectionPoint, 'incoming');
  assert.strictEqual(nonconformance.productId, ncr.productId);
  assert.strictEqual(nonconformance.productCode, ncr.productCode);
  assert.strictEqual(nonconformance.defectCodeId, ncr.defectCodeId);
  assert.strictEqual(nonconformance.defectCodeCode, ncr.defectCodeCode);
  assert.strictEqual(nonconformance.quantityAffected, 250);
  assert.strictEqual(nonconformance.orgUnitId, ncr.orgUnitId);
  assert.strictEqual(nonconformance.lotRef, 'LOT-4771');
  // The record is open, controlled by nothing else yet.
  assert.strictEqual(nonconformance.status, 'open');

  // The NCR now names it, from the write's own answer...
  assert.strictEqual(created.body.supplierNcr.nonconformance.id, nonconformance.id);
  assert.strictEqual(created.body.supplierNcr.nonconformance.issueNo, nonconformance.issueNo);

  // ... from its detail read...
  const readNcr = await readSupplierNcr(ground.engineer.token, ncr.id);
  assert.strictEqual(readNcr.status, 200, JSON.stringify(readNcr.body));
  assert.strictEqual(readNcr.body.supplierNcr.nonconformance.id, nonconformance.id);
  assert.strictEqual(
    readNcr.body.supplierNcr.nonconformance.detectionPoint,
    'incoming'
  );

  // ... and from the Non-conformance's own read, which is the other end of the
  // same link: the supplier NCRs that name it, with the Supplier behind each.
  const readRecord = await readNonconformance(ground.engineer.token, nonconformance.id);
  assert.strictEqual(readRecord.status, 200, JSON.stringify(readRecord.body));
  const named = readRecord.body.nonconformance.supplierNcrs;
  assert.strictEqual(named.length, 1);
  assert.strictEqual(named[0].id, ncr.id);
  assert.strictEqual(named[0].ncrNo, ncr.ncrNo);
  assert.strictEqual(named[0].supplierId, ncr.supplierId);
  assert.strictEqual(named[0].supplierName, ncr.supplierName);
  assert.strictEqual(named[0].incomingLotRef, 'LOT-4771');
  assert.strictEqual(named[0].quantityAffected, 250);
  assert.strictEqual(named[0].status, 'open');
  assert.strictEqual(named[0].responseDueDate, '2099-01-01');

  // A second Non-conformance cannot be recorded from the same NCR, and neither
  // can a link replace the one it has.
  const again = await recordNonconformanceFromSupplierNcr(ground.engineer.token, ncr.id, {
    quantity: 5
  });
  assert.strictEqual(again.status, 409, JSON.stringify(again.body));
  assert.match(again.body.message, /already names a Non-conformance/);

  // The write is the same Grant question as recording a Non-conformance at all:
  // a caller who can see the Site but holds no edit Grant there is refused.
  const other = await recordSupplierNcr(ground.engineer.token, ground.site.id, ncrBody(ground));
  const reader = await insertAccount({
    displayName: 'Read Only',
    grants: [{ orgUnitId: ground.line.id, write: false }]
  });
  const refused = await recordNonconformanceFromSupplierNcr(reader.token, other.body.supplierNcr.id, {});
  assert.strictEqual(refused.status, 403, JSON.stringify(refused.body));

  // An NCR with neither a Product nor a Defect code of its own, and a body
  // naming neither, is refused with a sentence rather than a 500 from the NOT
  // NULL column underneath.
  const bare = await recordSupplierNcr(ground.engineer.token, ground.site.id, {
    orgUnitId: ground.line.id,
    supplierId: ground.supplier.id,
    quantity: 12,
    uomCode: 'EA'
  });
  assert.strictEqual(bare.status, 201, JSON.stringify(bare.body));
  const noProduct = await recordNonconformanceFromSupplierNcr(
    ground.engineer.token,
    bare.body.supplierNcr.id,
    { defectCodeId: ground.defectCode.id }
  );
  assert.strictEqual(noProduct.status, 400, JSON.stringify(noProduct.body));
  assert.match(noProduct.body.message, /productId is required/);
  const noDefect = await recordNonconformanceFromSupplierNcr(
    ground.engineer.token,
    bare.body.supplierNcr.id,
    { productId: ground.product.id }
  );
  assert.strictEqual(noDefect.status, 400, JSON.stringify(noDefect.body));
  assert.match(noDefect.body.message, /defectCodeId is required/);

  // Naming both in the body is enough: the caller supplies what the NCR does
  // not carry.
  const supplied = await recordNonconformanceFromSupplierNcr(
    ground.engineer.token,
    bare.body.supplierNcr.id,
    {
      productId: ground.product.id,
      defectCodeId: ground.defectCode.id,
      immediateContainment: 'The pallet is quarantined until the bolts are gauged.'
    }
  );
  assert.strictEqual(supplied.status, 201, JSON.stringify(supplied.body));
  assert.strictEqual(supplied.body.nonconformance.detectionPoint, 'incoming');
  assert.strictEqual(supplied.body.nonconformance.productId, String(ground.product.id));
  assert.strictEqual(supplied.body.nonconformance.quantityAffected, 12);
});

test('an existing Non-conformance can be linked to a supplier NCR, with the same refusals the link has elsewhere', async () => {
  const ground = await makeGround();

  const recorded = await recordSupplierNcr(ground.engineer.token, ground.site.id, ncrBody(ground));
  assert.strictEqual(recorded.status, 201, JSON.stringify(recorded.body));
  const ncr = recorded.body.supplierNcr;

  // A Non-conformance about the same Product, recorded the ordinary way.
  const existing = await recordNonconformance(ground.engineer.token, ground.site.id, {
    orgUnitId: ground.line.id,
    productId: ground.product.id,
    defectCodeId: ground.defectCode.id,
    detectionPoint: 'incoming',
    quantity: 60
  });
  assert.strictEqual(existing.status, 201, JSON.stringify(existing.body));
  const nonconformanceId = existing.body.nonconformance.id;

  const linked = await linkNonconformance(ground.engineer.token, ncr.id, { nonconformanceId });
  assert.strictEqual(linked.status, 200, JSON.stringify(linked.body));
  assert.strictEqual(linked.body.supplierNcr.nonconformance.id, String(nonconformanceId));
  assert.strictEqual(linked.body.supplierNcr.nonconformance.detectionPoint, 'incoming');

  // The other end of the same link, and the last write never replaced the first:
  // two NCRs may name one Non-conformance, which is the same material being
  // controlled for two arrivals.
  const readRecord = await readNonconformance(ground.engineer.token, nonconformanceId);
  assert.deepStrictEqual(
    readRecord.body.nonconformance.supplierNcrs.map((row) => row.id),
    [ncr.id]
  );

  // A second link on the same NCR is a 409 rather than a silent replacement.
  const second = await recordSupplierNcr(ground.engineer.token, ground.site.id, ncrBody(ground));
  const already = await linkNonconformance(ground.engineer.token, ncr.id, {
    nonconformanceId: second.body.supplierNcr.id
  });
  assert.strictEqual(already.status, 409, JSON.stringify(already.body));
  assert.match(already.body.message, /already names a Non-conformance/);

  // An unknown record is a 404 and a malformed id a 400.
  const other = await recordSupplierNcr(ground.engineer.token, ground.site.id, ncrBody(ground));
  const unknown = await linkNonconformance(ground.engineer.token, other.body.supplierNcr.id, {
    nonconformanceId: 999999999
  });
  assert.strictEqual(unknown.status, 404, JSON.stringify(unknown.body));
  const malformed = await linkNonconformance(ground.engineer.token, other.body.supplierNcr.id, {
    nonconformanceId: 'NC-1'
  });
  assert.strictEqual(malformed.status, 400, JSON.stringify(malformed.body));

  // A Non-conformance about another Product does not control this NCR's
  // Product — 409 naming the mismatch.
  const otherProduct = await createProduct(adminToken);
  const mismatched = await recordNonconformance(ground.engineer.token, ground.site.id, {
    orgUnitId: ground.line.id,
    productId: otherProduct.id,
    defectCodeId: ground.defectCode.id,
    detectionPoint: 'in_process',
    quantity: 5
  });
  const wrongProduct = await linkNonconformance(ground.engineer.token, other.body.supplierNcr.id, {
    nonconformanceId: mismatched.body.nonconformance.id
  });
  assert.strictEqual(wrongProduct.status, 409, JSON.stringify(wrongProduct.body));
  assert.match(wrongProduct.body.message, /another Product/);

  // An NCR that names no Product of its own accepts one about any Product: the
  // rule is a fact about two rows, and only one of them is present here.
  const bare = await recordSupplierNcr(ground.engineer.token, ground.site.id, {
    orgUnitId: ground.line.id,
    supplierId: ground.supplier.id,
    quantity: 7,
    uomCode: 'EA'
  });
  const linkedBare = await linkNonconformance(
    ground.engineer.token,
    bare.body.supplierNcr.id,
    { nonconformanceId: mismatched.body.nonconformance.id }
  );
  assert.strictEqual(linkedBare.status, 200, JSON.stringify(linkedBare.body));

  // A cancelled Non-conformance controls nothing. Cancelling is a decision about
  // the record, so it needs Quality authority at the Org Unit (ADR-0035) rather
  // than the write Grant this slice asks for.
  const cancellable = await recordNonconformance(ground.engineer.token, ground.site.id, {
    orgUnitId: ground.line.id,
    productId: ground.product.id,
    defectCodeId: ground.defectCode.id,
    detectionPoint: 'incoming',
    quantity: 9
  });
  const qualityEngineer = await insertAccount({
    displayName: 'Quality Authority',
    grants: [{ orgUnitId: ground.area.id, write: true, quality: true }]
  });
  const cancelled = await fetch(
    `${base}/api/quality/nonconformances/${cancellable.body.nonconformance.id}/cancel`,
    {
      method: 'POST',
      headers: { ...qualityEngineer.token, 'content-type': 'application/json' },
      body: JSON.stringify({ note: 'Recorded against the wrong lot number.' })
    }
  );
  assert.strictEqual(cancelled.status, 200, await cancelled.text());
  const third = await recordSupplierNcr(ground.engineer.token, ground.site.id, ncrBody(ground));
  const refused = await linkNonconformance(ground.engineer.token, third.body.supplierNcr.id, {
    nonconformanceId: cancellable.body.nonconformance.id
  });
  assert.strictEqual(refused.status, 409, JSON.stringify(refused.body));
  assert.match(refused.body.message, /cancelled/);
});

// ---------------------------------------------------------------------------
// 4. The disposition, the cost recovered, and the closure
// ---------------------------------------------------------------------------

test("the Supplier's disposition and cost recovered are recorded, and the NCR closed", async () => {
  const ground = await makeGround();

  const recorded = await recordSupplierNcr(
    ground.engineer.token,
    ground.site.id,
    ncrBody(ground, { responseDueDate: '2020-01-01' })
  );
  assert.strictEqual(recorded.status, 201, JSON.stringify(recorded.body));
  const ncr = recorded.body.supplierNcr;

  // An NCR past the day the Supplier was given is marked late — the register's
  // own fact, and the same one a complaint carries.
  assert.strictEqual(ncr.isOverdue, true);
  assert.ok(ncr.daysOverdue > 0, `${ncr.daysOverdue} should be a count of days`);

  // A disposition outside the baseline's own five is a 400 naming them, and a
  // missing one is a 400 rather than a silent default.
  const wrong = await recordDisposition(ground.engineer.token, ncr.id, {
    disposition: 'sell_it_on'
  });
  assert.strictEqual(wrong.status, 400, JSON.stringify(wrong.body));
  assert.match(wrong.body.message, /disposition/);
  const missing = await recordDisposition(ground.engineer.token, ncr.id, {});
  assert.strictEqual(missing.status, 400, JSON.stringify(missing.body));

  // The quality engineer's answer for the material, and what was clawed back —
  // the one place incoming quality reaches the Cost pillar.
  const decision = await recordDisposition(ground.engineer.token, ncr.id, {
    disposition: 'rework_at_cost',
    costRecovered: 1875.5,
    currency: 'EUR'
  });
  assert.strictEqual(decision.status, 200, JSON.stringify(decision.body));
  assert.strictEqual(decision.body.supplierNcr.disposition, 'rework_at_cost');
  assert.strictEqual(decision.body.supplierNcr.costRecovered, 1875.5);
  assert.strictEqual(decision.body.supplierNcr.currency, 'EUR');
  // Recording the decision is a field on the record, not a state change: the
  // one transition this slice has is the closure.
  assert.strictEqual(decision.body.supplierNcr.status, 'open');

  // A negative recovery is refused, and the currency is three letters.
  const negative = await recordDisposition(ground.engineer.token, ncr.id, {
    disposition: 'scrap',
    costRecovered: -1
  });
  assert.strictEqual(negative.status, 400, JSON.stringify(negative.body));
  const badCurrency = await recordDisposition(ground.engineer.token, ncr.id, {
    disposition: 'scrap',
    currency: 'euros'
  });
  assert.strictEqual(badCurrency.status, 400, JSON.stringify(badCurrency.body));

  // Zero recovered is a real answer — a lot scrapped at the plant's own cost —
  // and it is not the same as never having recorded one.
  const none = await recordDisposition(ground.engineer.token, ncr.id, {
    disposition: 'scrap',
    costRecovered: 0
  });
  assert.strictEqual(none.status, 200, JSON.stringify(none.body));
  assert.strictEqual(none.body.supplierNcr.costRecovered, 0);

  // Closing it, and the closure keeps what was decided.
  const closed = await closeSupplierNcr(ground.engineer.token, ncr.id);
  assert.strictEqual(closed.status, 200, JSON.stringify(closed.body));
  assert.strictEqual(closed.body.supplierNcr.status, 'closed');
  assert.strictEqual(closed.body.supplierNcr.disposition, 'scrap');
  assert.strictEqual(closed.body.supplierNcr.costRecovered, 0);
  assert.notStrictEqual(closed.body.supplierNcr.closedAt, null);
  // And a closed NCR is never marked late: the deadline no longer belongs to
  // anybody's worklist.
  assert.strictEqual(closed.body.supplierNcr.isOverdue, false);

  // A second close, and a disposition recorded after the closure, are both 409
  // rather than quiet rewrites of a finished record.
  const again = await closeSupplierNcr(ground.engineer.token, ncr.id);
  assert.strictEqual(again.status, 409, JSON.stringify(again.body));
  const afterClose = await recordDisposition(ground.engineer.token, ncr.id, {
    disposition: 'sort',
    costRecovered: 10
  });
  assert.strictEqual(afterClose.status, 409, JSON.stringify(afterClose.body));

  // The write is the same Grant question as recording: a caller who can see the
  // Site but holds no edit Grant at the NCR's Org Unit is refused.
  const other = await recordSupplierNcr(ground.engineer.token, ground.site.id, ncrBody(ground));
  const reader = await insertAccount({
    displayName: 'Read Only',
    grants: [{ orgUnitId: ground.line.id, write: false }]
  });
  const refused = await recordDisposition(reader.token, other.body.supplierNcr.id, {
    disposition: 'scrap'
  });
  assert.strictEqual(refused.status, 403, JSON.stringify(refused.body));
  const refusedClose = await closeSupplierNcr(reader.token, other.body.supplierNcr.id);
  assert.strictEqual(refusedClose.status, 403, JSON.stringify(refusedClose.body));
});

// ---------------------------------------------------------------------------
// 5. The register
// ---------------------------------------------------------------------------

test('supplier NCRs are listed by Supplier and status, with the past-due ones marked', async () => {
  const ground = await makeGround();

  const otherSupplier = (
    await createSupplier(adminToken, { code: uniqueCode('SUP-'), name: 'Baltic Steels' })
  ).body.supplier;

  const late = await recordSupplierNcr(
    ground.engineer.token,
    ground.site.id,
    ncrBody(ground, { responseDueDate: '2020-01-01' })
  );
  const open = await recordSupplierNcr(ground.engineer.token, ground.site.id, ncrBody(ground));
  const fromOther = await recordSupplierNcr(ground.engineer.token, ground.site.id, {
    ...ncrBody(ground),
    supplierId: otherSupplier.id
  });
  const closed = await recordSupplierNcr(ground.engineer.token, ground.site.id, ncrBody(ground));
  await closeSupplierNcr(ground.engineer.token, closed.body.supplierNcr.id);

  // The whole register, newest first.
  const all = await listSupplierNcrs(ground.engineer.token, ground.site.id);
  assert.strictEqual(all.status, 200, JSON.stringify(all.body));
  assert.strictEqual(all.body.supplierNcrs.length, 4);
  assert.strictEqual(all.body.truncated, false);

  // Narrowed by Supplier — the ticket's first filter.
  const bySupplier = await listSupplierNcrs(
    ground.engineer.token,
    ground.site.id,
    `?supplierId=${otherSupplier.id}`
  );
  assert.deepStrictEqual(
    bySupplier.body.supplierNcrs.map((row) => row.id),
    [fromOther.body.supplierNcr.id]
  );

  // Narrowed by status — the ticket's second — and the past-due rows are the
  // ones still being worked.
  const openOnly = await listSupplierNcrs(ground.engineer.token, ground.site.id, '?status=open');
  assert.strictEqual(openOnly.body.supplierNcrs.length, 3);
  assert.ok(openOnly.body.supplierNcrs.every((row) => row.status === 'open'));
  assert.deepStrictEqual(
    openOnly.body.supplierNcrs.map((row) => row.isOverdue).sort(),
    [false, false, true]
  );

  const closedOnly = await listSupplierNcrs(ground.engineer.token, ground.site.id, '?status=closed');
  assert.deepStrictEqual(
    closedOnly.body.supplierNcrs.map((row) => row.id),
    [closed.body.supplierNcr.id]
  );
  assert.strictEqual(closedOnly.body.supplierNcrs[0].isOverdue, false);

  // Narrowed by Org Unit, the area filter the Non-conformance register keeps.
  const byArea = await listSupplierNcrs(
    ground.engineer.token,
    ground.site.id,
    `?orgUnitId=${ground.area.id}`
  );
  assert.strictEqual(byArea.body.supplierNcrs.length, 4);
  const bySibling = await listSupplierNcrs(
    ground.engineer.token,
    ground.site.id,
    `?orgUnitId=${ground.otherArea.id}`
  );
  assert.deepStrictEqual(bySibling.body.supplierNcrs, []);

  // A closed set in the query is checked, not forwarded: a typo is a 400 rather
  // than a quietly empty list.
  const typo = await listSupplierNcrs(ground.engineer.token, ground.site.id, '?status=oppen');
  assert.strictEqual(typo.status, 400, JSON.stringify(typo.body));
  assert.match(typo.body.message, /status/);

  // A Supplier filter that names nothing is a 404, and a malformed one a 400 —
  // a filter that can never match is never answered with an empty list.
  const unknownSupplier = await listSupplierNcrs(
    ground.engineer.token,
    ground.site.id,
    '?supplierId=999999999'
  );
  assert.strictEqual(unknownSupplier.status, 404, JSON.stringify(unknownSupplier.body));
  const malformedSupplier = await listSupplierNcrs(
    ground.engineer.token,
    ground.site.id,
    '?supplierId=baltic'
  );
  assert.strictEqual(malformedSupplier.status, 400, JSON.stringify(malformedSupplier.body));

  // An Org Unit of another Site is no Org Unit here.
  const otherSite = await insertSite({ name: 'Another Plant' });
  const otherUnit = await insertOrgUnit(otherSite.id, { name: 'Their Goods In' });
  const crossSite = await listSupplierNcrs(
    ground.engineer.token,
    ground.site.id,
    `?orgUnitId=${otherUnit.id}`
  );
  assert.strictEqual(crossSite.status, 404, JSON.stringify(crossSite.body));

  // The register is a Site-wide read: anyone who can see the Site reads it, and
  // a caller with no Grant anywhere in it is refused.
  const reader = await insertAccount({
    displayName: 'Read Only',
    grants: [{ orgUnitId: ground.otherArea.id, write: false }]
  });
  const visible = await listSupplierNcrs(reader.token, ground.site.id);
  assert.strictEqual(visible.status, 200, JSON.stringify(visible.body));

  const outsider = await insertAccount({ displayName: 'Stores Operator' });
  const invisible = await listSupplierNcrs(outsider.token, ground.site.id);
  assert.strictEqual(invisible.status, 403, JSON.stringify(invisible.body));

  // And one NCR's own read asks the same question about its own Site.
  const readByOutsider = await readSupplierNcr(outsider.token, late.body.supplierNcr.id);
  assert.strictEqual(readByOutsider.status, 403, JSON.stringify(readByOutsider.body));
});
