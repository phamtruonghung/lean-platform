/*
 * Customers and customer complaints (issue #214) — over HTTP, against a real
 * database and a real (locally issued) JWKS. The seam, the fixture scaffolding
 * and the dependency-ordered cleanup are the ones
 * `concern-nonconformances.test.js` and `capas.test.js` already establish.
 *
 * Everything the ticket's acceptance criteria name is exercised here, one test
 * per criterion and each refusal proved rather than assumed: the Customer list
 * read and searched by any active Account with its writes the administrator's
 * alone (403), a duplicate Customer code (409), recording a complaint behind an
 * edit Grant reaching its Org Unit (403 without one, 404 for an Org Unit that
 * is not there or belongs to another Site), the Customer and the Product
 * required (400/404), the Defect code chosen from the catalogue rather than
 * typed (404 for one that is not there, 409 for a retired one), a
 * Non-conformance recorded from a complaint with `detection_point = 'customer'`
 * and the complaint's own Product and Defect code, an existing one linked
 * instead (with the link's own three refusals), the register narrowed by status
 * and by Org Unit with the past-due rows marked, and a complaint closed with
 * its response (400 without one, 409 a second time).
 *
 * **"Each shows the other" is asserted from both ends**, which is the only way
 * that criterion can be honoured: the complaint's own read returns the
 * Non-conformance it is controlled by, and the Non-conformance's own read — the
 * Quality Module's existing detail address, not a new one — returns the
 * complaints that name it.
 *
 * Needs a database with every migration applied, including
 * 1800500000000_customer-complaint-response-note.js. Set DATABASE_URL first —
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
const insertedProductCodes = [];
const insertedDefectCodeCodes = [];
const insertedCustomerCodes = [];

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
  const subject = uniqueCode('ccacct');
  const name = displayName ?? `Complaint Account ${subject}`;
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

async function insertSite({ name = 'Complaint Test Site' } = {}) {
  const { rows: [site] } = await pool.query(
    `INSERT INTO sites (code, name, timezone) VALUES ($1, $2, $3) RETURNING id, code, name`,
    [uniqueCode('CCS'), name, 'Asia/Ho_Chi_Minh']
  );
  insertedSiteIds.push(site.id);
  return site;
}

async function insertOrgUnit(siteId, { parentId = null, unitType = 'area', name = 'Complaint Unit' } = {}) {
  const { rows: [orgUnit] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, $2, $3, $4, $5) RETURNING id, code, name, path`,
    [siteId, parentId, uniqueCode('CCOU'), name, unitType]
  );
  insertedOrgUnitIds.push(orgUnit.id);
  return orgUnit;
}

async function createProduct(adminToken, { name = null } = {}) {
  const code = uniqueCode('CCP-');
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
  const code = uniqueCode('CCD-');
  const response = await fetch(`${base}/api/quality/defect-codes`, {
    method: 'POST',
    headers: { ...adminToken, 'content-type': 'application/json' },
    body: JSON.stringify({ code, name: `Defect ${code}`, category: 'product', defaultSeverity: 'major' })
  });
  const { status, body } = await json(response);
  assert.strictEqual(status, 201, `creating ${code} failed: ${JSON.stringify(body)}`);
  insertedDefectCodeCodes.push(code);
  return body.defectCode;
}

// ---------------------------------------------------------------------------
// The addresses this file drives
// ---------------------------------------------------------------------------

async function listCustomers(token, query = '') {
  const response = await fetch(`${base}/api/quality/customers${query}`, { headers: token });
  return json(response);
}

async function createCustomer(token, body) {
  const response = await fetch(`${base}/api/quality/customers`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  const payload = await json(response);
  if (payload.status === 201) insertedCustomerCodes.push(payload.body.customer.code);
  return payload;
}

async function correctCustomer(token, id, body) {
  const response = await fetch(`${base}/api/quality/customers/${id}`, {
    method: 'PATCH',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  return json(response);
}

async function listComplaints(token, siteId, query = '') {
  const response = await fetch(`${base}/api/quality/sites/${siteId}/complaints${query}`, {
    headers: token
  });
  return json(response);
}

async function recordComplaint(token, siteId, body) {
  const response = await fetch(`${base}/api/quality/sites/${siteId}/complaints`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  return json(response);
}

async function readComplaint(token, id) {
  const response = await fetch(`${base}/api/quality/complaints/${id}`, { headers: token });
  return json(response);
}

async function respondToComplaint(token, id, body) {
  const response = await fetch(`${base}/api/quality/complaints/${id}/respond`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  return json(response);
}

async function recordNonconformanceFromComplaint(token, id, body = {}) {
  const response = await fetch(`${base}/api/quality/complaints/${id}/nonconformance`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  return json(response);
}

async function linkNonconformance(token, id, body) {
  const response = await fetch(`${base}/api/quality/complaints/${id}/link`, {
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
// Customer, a Product and a Defect code — each created through the API, so the
// fixtures are records the Platform itself would have made.
async function makeGround() {
  const site = await insertSite();
  const area = await insertOrgUnit(site.id, { name: 'Foundry' });
  const line = await insertOrgUnit(site.id, {
    parentId: area.id,
    unitType: 'line',
    name: 'Line 1'
  });
  const otherLine = await insertOrgUnit(site.id, {
    parentId: area.id,
    unitType: 'line',
    name: 'Line 5'
  });

  const engineer = await insertAccount({
    displayName: 'Quality Engineer',
    grants: [{ orgUnitId: area.id, write: true }]
  });

  const customer = (
    await createCustomer(adminToken, {
      code: uniqueCode('CUST-'),
      name: `Acme Bearings ${uniqueCode('')}`,
      contactEmail: 'quality@acme.example.com'
    })
  ).body.customer;
  const product = await createProduct(adminToken);
  const defectCode = await createDefectCode(adminToken);

  return { site, area, line, otherLine, engineer, customer, product, defectCode };
}

function complaintBody(ground, overrides = {}) {
  return {
    orgUnitId: ground.line.id,
    customerId: ground.customer.id,
    productId: ground.product.id,
    defectCodeId: ground.defectCode.id,
    quantity: 20,
    description: 'Twenty of the last delivery will not seat on the shaft.',
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
  // Children before parents, hardest descendant first. A complaint names its
  // Non-conformance through a plain foreign key, so the complaints have to go
  // before the Non-conformances; the Non-conformances before the Org Units they
  // sit at; and the Customer before nothing, since only a complaint points at
  // one. A rejected `test.after` does not fail fast: it hangs the file on the
  // framework's timeout and cancels every file behind it.
  await pool.query(
    `DELETE FROM customer_complaints
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
  await pool.query('DELETE FROM customers WHERE code = ANY($1)', [insertedCustomerCodes]);
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
// 1. The Customer list
// ---------------------------------------------------------------------------

test('an administrator defines a Customer, and any active Account can read and search the list', async () => {
  const ground = await makeGround();

  // A second Customer, so a search has something to leave out.
  const other = await createCustomer(adminToken, {
    code: uniqueCode('CUST-'),
    name: 'Zenith Castings'
  });
  assert.strictEqual(other.status, 201, JSON.stringify(other.body));

  // The row the administrator gets back is the row the catalogue reads: code,
  // name, the contact address, and that it is in use.
  const customer = ground.customer;
  assert.strictEqual(customer.contactEmail, 'quality@acme.example.com');
  assert.strictEqual(customer.isActive, true);

  // A caller with no Grant anywhere reads and searches it: the ticket's own
  // criterion, and the reason this read carries no role check at all.
  const outsider = await insertAccount({ displayName: 'Stores Operator' });
  const all = await listCustomers(outsider.token);
  assert.strictEqual(all.status, 200, JSON.stringify(all.body));
  assert.ok(all.body.customers.some((row) => row.id === customer.id));

  // Search matches the code and the name — the two things a caller has to hand
  // when they are recording a complaint (products.js's own `?search=` shape).
  const byName = await listCustomers(outsider.token, '?search=Acme');
  assert.deepStrictEqual(
    byName.body.customers.map((row) => row.id),
    [customer.id]
  );
  const byCode = await listCustomers(outsider.token, `?search=${customer.code}`);
  assert.deepStrictEqual(
    byCode.body.customers.map((row) => row.code),
    [customer.code]
  );

  // Deactivating is a correction, not a deletion, and the row is reachable
  // afterwards only when the caller asks for the retired ones.
  const retired = await correctCustomer(adminToken, customer.id, { isActive: false });
  assert.strictEqual(retired.status, 200, JSON.stringify(retired.body));
  assert.strictEqual(retired.body.customer.isActive, false);

  const active = await listCustomers(outsider.token, `?search=${customer.code}`);
  assert.deepStrictEqual(active.body.customers, []);
  const withInactive = await listCustomers(outsider.token, `?search=${customer.code}&includeInactive=true`);
  assert.deepStrictEqual(
    withInactive.body.customers.map((row) => row.code),
    [customer.code]
  );
});

test('Customer writes are the administrator\'s, and a code already taken is refused', async () => {
  const ground = await makeGround();

  // Three callers who may read the list and may not write it: an operator with
  // no Grant anywhere, an engineer holding an edit Grant on the area, and an
  // operator holding one on the line.
  const outsider = await insertAccount({ displayName: 'Stores Operator' });
  const engineer = ground.engineer;
  const lineSupervisor = await insertAccount({
    displayName: 'Line Supervisor',
    grants: [{ orgUnitId: ground.line.id, write: true }]
  });

  for (const caller of [outsider, engineer, lineSupervisor]) {
    const created = await createCustomer(caller.token, {
      code: uniqueCode('CUST-'),
      name: 'Not this caller to define'
    });
    assert.strictEqual(created.status, 403, JSON.stringify(created.body));
    assert.match(created.body.message, /administrator/);

    const corrected = await correctCustomer(caller.token, ground.customer.id, {
      name: 'Not this caller to correct'
    });
    assert.strictEqual(corrected.status, 403, JSON.stringify(corrected.body));
  }

  // The administrator may, and a duplicate code is a 409 from the database's
  // own unique index rather than a check the API races.
  const duplicate = await createCustomer(adminToken, {
    code: ground.customer.code,
    name: 'A second Acme'
  });
  assert.strictEqual(duplicate.status, 409, JSON.stringify(duplicate.body));
  assert.match(duplicate.body.message, /already exists/);

  // Its code is what a complaint quotes, so a correction may not rewrite it,
  // and an unknown Customer is a 404 for the administrator too.
  const rewritten = await correctCustomer(adminToken, ground.customer.id, {
    code: uniqueCode('CUST-')
  });
  assert.strictEqual(rewritten.status, 400, JSON.stringify(rewritten.body));
  const missing = await correctCustomer(adminToken, 999999999, { name: 'Nobody' });
  assert.strictEqual(missing.status, 404, JSON.stringify(missing.body));
  const malformed = await correctCustomer(adminToken, 'not-an-id', { name: 'Nobody' });
  assert.strictEqual(malformed.status, 404, JSON.stringify(malformed.body));
});

// ---------------------------------------------------------------------------
// 2. Recording a complaint
// ---------------------------------------------------------------------------

test('a complaint records the Customer, the Product, the Defect code, the quantity, the response due day and the warranty claim', async () => {
  const ground = await makeGround();

  const recorded = await recordComplaint(
    ground.engineer.token,
    ground.site.id,
    complaintBody(ground, {
      responseDueDate: '2099-01-01',
      isWarranty: true,
      customerRef: 'PO-88213',
      lotRef: 'LOT-4471'
    })
  );
  assert.strictEqual(recorded.status, 201, JSON.stringify(recorded.body));

  const complaint = recorded.body.complaint;
  // Its own number, from the baseline's own sequence: the prefix a person
  // quotes, the year and a zero-padded sequence.
  assert.match(complaint.complaintNo, /^CC-\d{4}-\d{5}$/);
  assert.strictEqual(complaint.status, 'open');
  // The records it names, read back with the names a reader needs rather than
  // only their ids.
  assert.strictEqual(complaint.customerId, String(ground.customer.id));
  assert.strictEqual(complaint.customerCode, ground.customer.code);
  assert.strictEqual(complaint.customerName, ground.customer.name);
  assert.strictEqual(complaint.productId, String(ground.product.id));
  assert.strictEqual(complaint.productCode, ground.product.code);
  assert.strictEqual(complaint.defectCodeId, String(ground.defectCode.id));
  assert.strictEqual(complaint.defectCodeCode, ground.defectCode.code);
  // Filed where it is worked, and read with its Site.
  assert.strictEqual(complaint.orgUnitId, String(ground.line.id));
  assert.strictEqual(complaint.orgUnitName, 'Line 1');
  assert.strictEqual(complaint.siteId, String(ground.site.id));
  // What the customer said, in the unit the Product is measured in — the
  // quantity's unit is the Product's own unless the caller names another.
  assert.strictEqual(complaint.quantityAffected, 20);
  assert.strictEqual(complaint.uomCode, 'EA');
  assert.strictEqual(complaint.severity, 'major');
  assert.strictEqual(complaint.complaintType, 'quality');
  assert.strictEqual(complaint.description, 'Twenty of the last delivery will not seat on the shaft.');
  assert.strictEqual(complaint.customerRef, 'PO-88213');
  assert.strictEqual(complaint.lotRef, 'LOT-4471');
  assert.strictEqual(complaint.isWarranty, true);
  // The day the caller chose, in the Site's own calendar, and the instant that
  // day ends at — not a date that has not fallen due and not one already past.
  assert.strictEqual(complaint.responseDueDate, '2099-01-01');
  assert.notStrictEqual(complaint.responseDueAt, null);
  assert.strictEqual(complaint.isOverdue, false);
  assert.strictEqual(complaint.daysOverdue, null);
  // Nothing has been responded to or controlled yet.
  assert.strictEqual(complaint.firstResponseAt, null);
  assert.strictEqual(complaint.closedAt, null);
  assert.strictEqual(complaint.responseNote, null);
  assert.strictEqual(complaint.nonconformance, null);

  // And the same row is what its own address reads.
  const read = await readComplaint(ground.engineer.token, complaint.id);
  assert.strictEqual(read.status, 200, JSON.stringify(read.body));
  assert.deepStrictEqual(read.body.complaint, complaint);
});

test('recording a complaint needs an edit Grant reaching its Org Unit, the Customer and the Product, and a Defect code from the catalogue', async () => {
  const ground = await makeGround();

  // A caller who can see the Site but holds no edit Grant at the Org Unit the
  // complaint would be filed at. The read grant reaches the line; the write
  // does not.
  const reader = await insertAccount({
    displayName: 'Read Only',
    grants: [{ orgUnitId: ground.line.id, write: false }]
  });
  const refused = await recordComplaint(reader.token, ground.site.id, complaintBody(ground));
  assert.strictEqual(refused.status, 403, JSON.stringify(refused.body));
  assert.match(refused.body.message, /granted Org Units/);

  // A caller with no Grant anywhere in the Site at all.
  const outsider = await insertAccount({ displayName: 'Stores Operator' });
  const invisible = await recordComplaint(outsider.token, ground.site.id, complaintBody(ground));
  assert.strictEqual(invisible.status, 403, JSON.stringify(invisible.body));

  // Existence before scope, and the Org Unit named must belong to this Site.
  const unknownUnit = await recordComplaint(ground.engineer.token, ground.site.id, {
    ...complaintBody(ground),
    orgUnitId: 999999999
  });
  assert.strictEqual(unknownUnit.status, 404, JSON.stringify(unknownUnit.body));
  const nonsenseUnit = await recordComplaint(ground.engineer.token, ground.site.id, {
    ...complaintBody(ground),
    orgUnitId: 'not-an-id'
  });
  assert.strictEqual(nonsenseUnit.status, 400, JSON.stringify(nonsenseUnit.body));

  const otherSite = await insertSite({ name: 'Another Plant' });
  const otherUnit = await insertOrgUnit(otherSite.id, { name: 'Their Line' });
  const crossSite = await recordComplaint(ground.engineer.token, ground.site.id, {
    ...complaintBody(ground),
    orgUnitId: otherUnit.id
  });
  assert.strictEqual(crossSite.status, 404, JSON.stringify(crossSite.body));

  // The Customer and the Product are required: a request that names neither is
  // refused field by field, and one that names a record that is not there is a
  // 404 rather than a raw foreign key failure.
  const noCustomer = await recordComplaint(ground.engineer.token, ground.site.id, {
    ...complaintBody(ground),
    customerId: undefined
  });
  assert.strictEqual(noCustomer.status, 400, JSON.stringify(noCustomer.body));
  assert.match(noCustomer.body.message, /customerId/);
  const unknownCustomer = await recordComplaint(ground.engineer.token, ground.site.id, {
    ...complaintBody(ground),
    customerId: 999999999
  });
  assert.strictEqual(unknownCustomer.status, 404, JSON.stringify(unknownCustomer.body));

  const noProduct = await recordComplaint(ground.engineer.token, ground.site.id, {
    ...complaintBody(ground),
    productId: undefined
  });
  assert.strictEqual(noProduct.status, 400, JSON.stringify(noProduct.body));
  assert.match(noProduct.body.message, /productId/);
  const unknownProduct = await recordComplaint(ground.engineer.token, ground.site.id, {
    ...complaintBody(ground),
    productId: 999999999
  });
  assert.strictEqual(unknownProduct.status, 404, JSON.stringify(unknownProduct.body));

  // A description is the complaint: the baseline's own column is NOT NULL, and
  // the refusal names the field.
  const noDescription = await recordComplaint(ground.engineer.token, ground.site.id, {
    ...complaintBody(ground),
    description: '   '
  });
  assert.strictEqual(noDescription.status, 400, JSON.stringify(noDescription.body));
  assert.match(noDescription.body.message, /description is required/);

  // The Defect code is chosen from the catalogue, never typed: one that is not
  // there is a 404, and one the plant has retired is a 409 naming its state.
  const unknownDefect = await recordComplaint(ground.engineer.token, ground.site.id, {
    ...complaintBody(ground),
    defectCodeId: 999999999
  });
  assert.strictEqual(unknownDefect.status, 404, JSON.stringify(unknownDefect.body));
  const typedDefect = await recordComplaint(ground.engineer.token, ground.site.id, {
    ...complaintBody(ground),
    defectCodeId: 'broken-seal'
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

  const retired = await recordComplaint(ground.engineer.token, ground.site.id, {
    ...complaintBody(ground),
    defectCodeId: retiredCode.id
  });
  assert.strictEqual(retired.status, 409, JSON.stringify(retired.body));
  const retiredAgainst = await recordComplaint(ground.engineer.token, ground.site.id, {
    ...complaintBody(ground),
    productId: retiredProduct.id
  });
  assert.strictEqual(retiredAgainst.status, 409, JSON.stringify(retiredAgainst.body));

  // A retired Customer is not refused: a complaint from somebody the plant no
  // longer trades with is still a complaint worth recording, and the baseline
  // leaves the column's own `is_active` to the catalogue read rather than to
  // this write.
  const stillTrading = await createCustomer(adminToken, {
    code: uniqueCode('CUST-'),
    name: 'Former Customer'
  });
  await correctCustomer(adminToken, stillTrading.body.customer.id, { isActive: false });
  const fromFormer = await recordComplaint(ground.engineer.token, ground.site.id, {
    ...complaintBody(ground),
    customerId: stillTrading.body.customer.id
  });
  assert.strictEqual(fromFormer.status, 201, JSON.stringify(fromFormer.body));

  // Nothing was written by any refusal.
  const register = await listComplaints(ground.engineer.token, ground.site.id);
  assert.strictEqual(register.body.complaints.length, 1);
});

// ---------------------------------------------------------------------------
// 3. Controlling the complained-of product
// ---------------------------------------------------------------------------

test('a Non-conformance recorded from a complaint carries detection point customer and the complaint own Product and Defect code, and each record names the other', async () => {
  const ground = await makeGround();

  const recorded = await recordComplaint(
    ground.engineer.token,
    ground.site.id,
    complaintBody(ground, { responseDueDate: '2099-01-01', isWarranty: true })
  );
  assert.strictEqual(recorded.status, 201, JSON.stringify(recorded.body));
  const complaint = recorded.body.complaint;

  // Recorded from the complaint, with no Defect code and no quantity of its own:
  // both come from the complaint, because that is the record the customer's
  // words produced.
  const created = await recordNonconformanceFromComplaint(
    ground.engineer.token,
    complaint.id,
    {}
  );
  assert.strictEqual(created.status, 201, JSON.stringify(created.body));

  const nonconformance = created.body.nonconformance;
  assert.match(nonconformance.issueNo, /^NC-/);
  // Detection point customer, and the complaint's own Product and Defect code.
  assert.strictEqual(nonconformance.detectionPoint, 'customer');
  assert.strictEqual(nonconformance.productId, complaint.productId);
  assert.strictEqual(nonconformance.productCode, complaint.productCode);
  assert.strictEqual(nonconformance.defectCodeId, complaint.defectCodeId);
  assert.strictEqual(nonconformance.defectCodeCode, complaint.defectCodeCode);
  assert.strictEqual(nonconformance.quantityAffected, 20);
  assert.strictEqual(nonconformance.orgUnitId, complaint.orgUnitId);
  // The record is open, controlled by nothing else yet.
  assert.strictEqual(nonconformance.status, 'open');

  // The complaint now names it, from the write's own answer...
  assert.strictEqual(created.body.complaint.nonconformance.id, nonconformance.id);
  assert.strictEqual(created.body.complaint.nonconformance.issueNo, nonconformance.issueNo);

  // ... from its detail read...
  const readComplaintBody = await readComplaint(ground.engineer.token, complaint.id);
  assert.strictEqual(readComplaintBody.status, 200, JSON.stringify(readComplaintBody.body));
  assert.strictEqual(readComplaintBody.body.complaint.nonconformance.id, nonconformance.id);
  assert.strictEqual(
    readComplaintBody.body.complaint.nonconformance.detectionPoint,
    'customer'
  );

  // ... and from the Non-conformance's own read, which is the other end of the
  // same link: the complaints that name it, with the Customer waiting on it.
  const readRecord = await readNonconformance(ground.engineer.token, nonconformance.id);
  assert.strictEqual(readRecord.status, 200, JSON.stringify(readRecord.body));
  const named = readRecord.body.nonconformance.customerComplaints;
  assert.strictEqual(named.length, 1);
  assert.strictEqual(named[0].id, complaint.id);
  assert.strictEqual(named[0].complaintNo, complaint.complaintNo);
  assert.strictEqual(named[0].customerId, complaint.customerId);
  assert.strictEqual(named[0].customerName, complaint.customerName);
  assert.strictEqual(named[0].status, 'open');
  assert.strictEqual(named[0].isWarranty, true);
  assert.strictEqual(named[0].responseDueDate, '2099-01-01');

  // A second Non-conformance cannot be recorded from the same complaint, and
  // neither can a link replace the one it has.
  const again = await recordNonconformanceFromComplaint(ground.engineer.token, complaint.id, {
    quantity: 5
  });
  assert.strictEqual(again.status, 409, JSON.stringify(again.body));
  assert.match(again.body.message, /already names a Non-conformance/);

  // The write is the same Grant question as recording a Non-conformance at all:
  // a caller who can see the Site but holds no edit Grant there is refused.
  const other = await recordComplaint(ground.engineer.token, ground.site.id, complaintBody(ground));
  assert.strictEqual(other.status, 201, JSON.stringify(other.body));
  const reader = await insertAccount({
    displayName: 'Read Only',
    grants: [{ orgUnitId: ground.line.id, write: false }]
  });
  const refused = await recordNonconformanceFromComplaint(reader.token, other.body.complaint.id, {});
  assert.strictEqual(refused.status, 403, JSON.stringify(refused.body));

  // A complaint with neither a Defect code nor a quantity of its own, and a
  // body naming neither, is refused with a sentence rather than a 500 from the
  // NOT NULL column underneath.
  const bare = await recordComplaint(ground.engineer.token, ground.site.id, {
    orgUnitId: ground.line.id,
    customerId: ground.customer.id,
    productId: ground.product.id,
    description: 'They rang the switchboard about it and nothing was written down.'
  });
  assert.strictEqual(bare.status, 201, JSON.stringify(bare.body));
  const noDefect = await recordNonconformanceFromComplaint(
    ground.engineer.token,
    bare.body.complaint.id,
    { quantity: 3 }
  );
  assert.strictEqual(noDefect.status, 400, JSON.stringify(noDefect.body));
  assert.match(noDefect.body.message, /defectCodeId is required/);
  const noQuantity = await recordNonconformanceFromComplaint(
    ground.engineer.token,
    bare.body.complaint.id,
    { defectCodeId: ground.defectCode.id }
  );
  assert.strictEqual(noQuantity.status, 400, JSON.stringify(noQuantity.body));
  assert.match(noQuantity.body.message, /quantity is required/);

  // Naming one in the body is enough: the caller supplies what the complaint
  // does not carry.
  const supplied = await recordNonconformanceFromComplaint(ground.engineer.token, bare.body.complaint.id, {
    defectCodeId: ground.defectCode.id,
    quantity: 3,
    immediateContainment: 'The line is stopped until the fixture is checked.'
  });
  assert.strictEqual(supplied.status, 201, JSON.stringify(supplied.body));
  assert.strictEqual(supplied.body.nonconformance.detectionPoint, 'customer');
  assert.strictEqual(supplied.body.nonconformance.defectCodeId, String(ground.defectCode.id));
  assert.strictEqual(supplied.body.nonconformance.quantityAffected, 3);
  // The containment is a Non-conformance's own field, so recording one with it
  // is what makes the record `contained`.
  assert.strictEqual(supplied.body.nonconformance.status, 'contained');
});

test('an existing Non-conformance can be linked to a complaint instead, and the link has three refusals of its own', async () => {
  const ground = await makeGround();

  const complaint = (
    await recordComplaint(ground.engineer.token, ground.site.id, complaintBody(ground, { lotRef: 'LOT-9001' }))
  ).body.complaint;

  // The record already exists: somebody recorded the Non-conformance when the
  // lot was quarantined, and the customer's complaint about the same lot is the
  // same problem.
  const existing = await recordNonconformance(ground.engineer.token, ground.site.id, {
    orgUnitId: ground.line.id,
    productId: ground.product.id,
    defectCodeId: ground.defectCode.id,
    detectionPoint: 'in_process',
    quantity: 20,
    lotRef: 'LOT-9001'
  });
  assert.strictEqual(existing.status, 201, JSON.stringify(existing.body));
  const nonconformance = existing.body.nonconformance;

  const linked = await linkNonconformance(ground.engineer.token, complaint.id, {
    nonconformanceId: nonconformance.id
  });
  assert.strictEqual(linked.status, 200, JSON.stringify(linked.body));
  assert.strictEqual(linked.body.complaint.nonconformance.id, nonconformance.id);
  // The linked record keeps its own detection point — it was found in process,
  // not by the customer — and the complaint is what points at it.
  assert.strictEqual(linked.body.complaint.nonconformance.detectionPoint, 'in_process');

  const readRecord = await readNonconformance(ground.engineer.token, nonconformance.id);
  assert.deepStrictEqual(
    readRecord.body.nonconformance.customerComplaints.map((row) => row.complaintNo),
    [complaint.complaintNo]
  );

  // A second link on the same complaint is refused rather than replacing the
  // record that was linked first.
  const second = await recordNonconformance(ground.engineer.token, ground.site.id, {
    orgUnitId: ground.line.id,
    productId: ground.product.id,
    defectCodeId: ground.defectCode.id,
    detectionPoint: 'audit',
    quantity: 4
  });
  assert.strictEqual(second.status, 201, JSON.stringify(second.body));
  const again = await linkNonconformance(ground.engineer.token, complaint.id, {
    nonconformanceId: second.body.nonconformance.id
  });
  assert.strictEqual(again.status, 409, JSON.stringify(again.body));
  assert.match(again.body.message, /already names a Non-conformance/);

  // A Non-conformance about another Product does not control this complaint's
  // Product, so it is refused with a sentence naming the mismatch.
  const otherProduct = await createProduct(adminToken);
  const otherRecord = await recordNonconformance(ground.engineer.token, ground.site.id, {
    orgUnitId: ground.line.id,
    productId: otherProduct.id,
    defectCodeId: ground.defectCode.id,
    detectionPoint: 'in_process',
    quantity: 6
  });
  const onAnotherComplaint = (
    await recordComplaint(ground.engineer.token, ground.site.id, complaintBody(ground))
  ).body.complaint;
  const mismatched = await linkNonconformance(ground.engineer.token, onAnotherComplaint.id, {
    nonconformanceId: otherRecord.body.nonconformance.id
  });
  assert.strictEqual(mismatched.status, 409, JSON.stringify(mismatched.body));
  assert.match(mismatched.body.message, /another Product/);

  // A cancelled record controls nothing, and a record that is not there is a
  // 404, and a value that is not an id at all is a 400.
  const holder = await insertAccount({
    displayName: 'Quality Holder',
    grants: [{ orgUnitId: ground.line.id, write: false, quality: true }]
  });
  const cancelled = await recordNonconformance(ground.engineer.token, ground.site.id, {
    orgUnitId: ground.line.id,
    productId: ground.product.id,
    defectCodeId: ground.defectCode.id,
    detectionPoint: 'in_process',
    quantity: 2
  });
  const cancel = await fetch(
    `${base}/api/quality/nonconformances/${cancelled.body.nonconformance.id}/cancel`,
    {
      method: 'POST',
      headers: { ...holder.token, 'content-type': 'application/json' },
      body: JSON.stringify({ note: 'Recorded against the wrong lot.' })
    }
  );
  assert.strictEqual(cancel.status, 200);

  const third = (
    await recordComplaint(ground.engineer.token, ground.site.id, complaintBody(ground))
  ).body.complaint;
  const onCancelled = await linkNonconformance(ground.engineer.token, third.id, {
    nonconformanceId: cancelled.body.nonconformance.id
  });
  assert.strictEqual(onCancelled.status, 409, JSON.stringify(onCancelled.body));
  assert.match(onCancelled.body.message, /cancelled/);

  const missing = await linkNonconformance(ground.engineer.token, third.id, {
    nonconformanceId: 999999999
  });
  assert.strictEqual(missing.status, 404, JSON.stringify(missing.body));
  const nonsense = await linkNonconformance(ground.engineer.token, third.id, {
    nonconformanceId: 'the-one-from-tuesday'
  });
  assert.strictEqual(nonsense.status, 400, JSON.stringify(nonsense.body));

  // Linking needs the same edit Grant: this caller can see the Site and may not
  // change the complaint.
  const reader = await insertAccount({
    displayName: 'Read Only',
    grants: [{ orgUnitId: ground.line.id, write: false }]
  });
  const refused = await linkNonconformance(reader.token, third.id, {
    nonconformanceId: nonconformance.id
  });
  assert.strictEqual(refused.status, 403, JSON.stringify(refused.body));

  // Nothing was linked by any of the refusals.
  const readThird = await readComplaint(ground.engineer.token, third.id);
  assert.strictEqual(readThird.body.complaint.nonconformance, null);
});

// ---------------------------------------------------------------------------
// 4. The register
// ---------------------------------------------------------------------------

test('the register lists a Site complaints by status and Org Unit, newest first, marking the one past its response due day', async () => {
  const ground = await makeGround();

  // Three complaints: one long past its due day and still open, one due far in
  // the future, and one filed at the other line.
  const overdue = (
    await recordComplaint(
      ground.engineer.token,
      ground.site.id,
      complaintBody(ground, { responseDueDate: '2020-06-01' })
    )
  ).body.complaint;
  const notDue = (
    await recordComplaint(
      ground.engineer.token,
      ground.site.id,
      complaintBody(ground, { responseDueDate: '2099-01-01' })
    )
  ).body.complaint;
  const elsewhere = (
    await recordComplaint(
      ground.engineer.token,
      ground.site.id,
      complaintBody(ground, { orgUnitId: ground.otherLine.id })
    )
  ).body.complaint;

  const all = await listComplaints(ground.engineer.token, ground.site.id);
  assert.strictEqual(all.status, 200, JSON.stringify(all.body));
  assert.strictEqual(all.body.truncated, false);
  // Newest first, by the moment each was received.
  assert.deepStrictEqual(
    all.body.complaints.map((row) => row.id),
    [elsewhere.id, notDue.id, overdue.id]
  );

  // The marking: past its due instant and not yet finished with. A complaint
  // with no due day at all is neither late nor on time — it is unmeasured.
  const byId = Object.fromEntries(all.body.complaints.map((row) => [row.id, row]));
  assert.strictEqual(byId[overdue.id].isOverdue, true);
  assert.ok(byId[overdue.id].daysOverdue >= 1, 'a complaint due in 2020 is not a day late');
  assert.strictEqual(byId[notDue.id].isOverdue, false);
  assert.strictEqual(byId[notDue.id].daysOverdue, null);
  assert.strictEqual(byId[elsewhere.id].responseDueDate, null);
  assert.strictEqual(byId[elsewhere.id].isOverdue, false);

  // By status, and a status outside the set is a mistake the caller can fix
  // rather than a silently empty register.
  const open = await listComplaints(ground.engineer.token, ground.site.id, '?status=open');
  assert.strictEqual(open.status, 200);
  assert.strictEqual(open.body.complaints.length, 3);
  const closed = await listComplaints(ground.engineer.token, ground.site.id, '?status=closed');
  assert.deepStrictEqual(closed.body.complaints, []);
  const typo = await listComplaints(ground.engineer.token, ground.site.id, '?status=opne');
  assert.strictEqual(typo.status, 400, JSON.stringify(typo.body));

  // By Org Unit, and everything beneath it — the area filter, not an
  // entitlement.
  const byArea = await listComplaints(
    ground.engineer.token,
    ground.site.id,
    `?orgUnitId=${ground.area.id}`
  );
  assert.strictEqual(byArea.body.complaints.length, 3);
  const byLine = await listComplaints(
    ground.engineer.token,
    ground.site.id,
    `?orgUnitId=${ground.line.id}`
  );
  assert.deepStrictEqual(
    byLine.body.complaints.map((row) => row.id),
    [notDue.id, overdue.id]
  );
  const unknownFilter = await listComplaints(
    ground.engineer.token,
    ground.site.id,
    '?orgUnitId=999999999'
  );
  assert.strictEqual(unknownFilter.status, 404, JSON.stringify(unknownFilter.body));

  // A Site that is not there is a 404, and a caller who cannot see this Site's
  // Org Units cannot read its register at all.
  const unknownSite = await listComplaints(ground.engineer.token, 999999999);
  assert.strictEqual(unknownSite.status, 404, JSON.stringify(unknownSite.body));
  const outsider = await insertAccount({ displayName: 'Stores Operator' });
  const refused = await listComplaints(outsider.token, ground.site.id);
  assert.strictEqual(refused.status, 403, JSON.stringify(refused.body));
  const refusedDetail = await readComplaint(outsider.token, overdue.id);
  assert.strictEqual(refusedDetail.status, 403, JSON.stringify(refusedDetail.body));

  // Reading one complaint is the same question as reading the register: any
  // Grant in the Site, read or write, and nothing else.
  const reader = await insertAccount({
    displayName: 'Read Only',
    grants: [{ orgUnitId: ground.line.id, write: false }]
  });
  const readable = await readComplaint(reader.token, overdue.id);
  assert.strictEqual(readable.status, 200, JSON.stringify(readable.body));
  const missingComplaint = await readComplaint(reader.token, 999999999);
  assert.strictEqual(missingComplaint.status, 404, JSON.stringify(missingComplaint.body));
  const malformed = await readComplaint(reader.token, 'not-an-id');
  assert.strictEqual(malformed.status, 404, JSON.stringify(malformed.body));
});

// ---------------------------------------------------------------------------
// 5. Closing a complaint with its response
// ---------------------------------------------------------------------------

test('a complaint closes with its response note, and closing it without one is refused', async () => {
  const ground = await makeGround();

  const complaint = (
    await recordComplaint(
      ground.engineer.token,
      ground.site.id,
      complaintBody(ground, { responseDueDate: '2020-06-01' })
    )
  ).body.complaint;
  assert.strictEqual(complaint.isOverdue, true);

  // With nothing said back, twice: an omitted note and a blank one are the same
  // refusal, and both name the field rather than the constraint underneath it.
  const omitted = await respondToComplaint(ground.engineer.token, complaint.id, {});
  assert.strictEqual(omitted.status, 400, JSON.stringify(omitted.body));
  assert.match(omitted.body.message, /responseNote is required/);
  const blank = await respondToComplaint(ground.engineer.token, complaint.id, {
    responseNote: '   '
  });
  assert.strictEqual(blank.status, 400, JSON.stringify(blank.body));

  // Neither wrote anything: the complaint is still open, and still late.
  const untouched = await readComplaint(ground.engineer.token, complaint.id);
  assert.strictEqual(untouched.body.complaint.status, 'open');
  assert.strictEqual(untouched.body.complaint.closedAt, null);
  assert.strictEqual(untouched.body.complaint.firstResponseAt, null);

  // Closing needs the same edit Grant: a caller who can see the Site but may
  // not change the record is refused.
  const reader = await insertAccount({
    displayName: 'Read Only',
    grants: [{ orgUnitId: ground.line.id, write: false }]
  });
  const refused = await respondToComplaint(reader.token, complaint.id, {
    responseNote: 'Not this caller to answer.'
  });
  assert.strictEqual(refused.status, 403, JSON.stringify(refused.body));

  const note =
    'Acknowledged on the day and re-sorted the lot: 20 replaced from stock, the rest screened clean.';
  const closed = await respondToComplaint(ground.engineer.token, complaint.id, {
    responseNote: note
  });
  assert.strictEqual(closed.status, 200, JSON.stringify(closed.body));
  assert.strictEqual(closed.body.complaint.status, 'closed');
  assert.strictEqual(closed.body.complaint.responseNote, note);
  assert.notStrictEqual(closed.body.complaint.closedAt, null);
  // The first reply is the one the customer waited for, set when it was not
  // already recorded.
  assert.notStrictEqual(closed.body.complaint.firstResponseAt, null);
  // A complaint that is finished with is never marked late, whatever its due
  // day was; how late the reply was is still readable.
  assert.strictEqual(closed.body.complaint.isOverdue, false);
  assert.ok(closed.body.complaint.daysOverdue >= 1);

  // And it is out of the open register and in the closed one.
  const open = await listComplaints(ground.engineer.token, ground.site.id, '?status=open');
  assert.deepStrictEqual(open.body.complaints, []);
  const closedList = await listComplaints(ground.engineer.token, ground.site.id, '?status=closed');
  assert.deepStrictEqual(
    closedList.body.complaints.map((row) => row.id),
    [complaint.id]
  );

  // Closing it a second time is a 409 rather than a rewritten response, and the
  // response it already has is not replaced.
  const again = await respondToComplaint(ground.engineer.token, complaint.id, {
    responseNote: 'A second answer.'
  });
  assert.strictEqual(again.status, 409, JSON.stringify(again.body));
  assert.match(again.body.message, /closed/);
  const after = await readComplaint(ground.engineer.token, complaint.id);
  assert.strictEqual(after.body.complaint.responseNote, note);

  // A closed complaint is finished with: no Non-conformance may be recorded from
  // it or linked to it afterwards.
  const recordAfter = await recordNonconformanceFromComplaint(ground.engineer.token, complaint.id, {
    quantity: 4,
    defectCodeId: ground.defectCode.id
  });
  assert.strictEqual(recordAfter.status, 409, JSON.stringify(recordAfter.body));
  const linkAfter = await linkNonconformance(ground.engineer.token, complaint.id, {
    nonconformanceId: 999999999
  });
  assert.strictEqual(linkAfter.status, 409, JSON.stringify(linkAfter.body));
});
