/*
 * The Quality retrofit (ADR-0061, issue #503) keeps the audience every route
 * had before it — measured over HTTP against a real database and a real local
 * session, the same seam nonconformances.test.js and customer-complaints.test.js
 * use.
 *
 * Why this file exists. The codes this retrofit asks are seeded on ROLE_STANDARD,
 * the default group every approved Account carries, so "the existing suite still
 * passes" cannot on its own show that the retrofit refused nobody: a gate that
 * only admitted supervisors would leave that suite green. And the sixteen routes
 * left on their Grant check (the findings in the handoff) must still admit an
 * operator who holds a write Grant on its line — that is the "behaviour changes
 * for nobody" half a role-narrowing would break.
 *
 * Both questions are asked here as the Account that would notice first: an
 * operator, holding the default group and nothing else. The last two tests go
 * the other way and prove the gates are wired at all, by removing one code from
 * ROLE_STANDARD and watching exactly one address start refusing.
 *
 * Needs a database with every migration applied, including
 * 1803400000000_permissions-and-roles.js. Set DATABASE_URL first.
 */

const test = require('node:test');
const assert = require('node:assert');
const { tokenFor } = require('../helpers/session');

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
const insertedSupplierCodes = [];
const insertedNonconformanceIds = [];
const insertedComplaintIds = [];
const insertedSupplierNcrIds = [];

let counter = 0;
function uniqueCode(prefix) {
  counter += 1;
  return `${prefix}${process.pid}${counter}`;
}

async function authHeader(subject) {
  const token = await tokenFor(subject);
  return { authorization: 'Bearer ' + token };
}

async function json(response) {
  return { status: response.status, body: await response.json().catch(() => null) };
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

async function insertAccount({ role = 'operator', displayName = null } = {}) {
  const subject = uniqueCode('qpacct');
  const name = displayName ?? `Quality Permission Account ${subject}`;
  const { rows: [account] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status)
     VALUES ($1, $2, $3, $4, TRUE, 'approved') RETURNING id`,
    [`${subject}@example.com`, name, role, subject]
  );
  insertedAccountIds.push(account.id);
  return { id: account.id, role, token: await authHeader(subject) };
}

async function insertGrant({ accountId, orgUnitId, canWrite = true }) {
  await pool.query(
    `INSERT INTO app_user_org_units (app_user_id, org_unit_id, can_write) VALUES ($1, $2, $3)`,
    [accountId, orgUnitId, canWrite]
  );
}

async function insertSite() {
  const { rows: [site] } = await pool.query(
    `INSERT INTO sites (code, name, timezone) VALUES ($1, $2, $3) RETURNING id`,
    [uniqueCode('QPS'), 'Quality Permission Test Site', 'Asia/Ho_Chi_Minh']
  );
  insertedSiteIds.push(site.id);
  return site.id;
}

async function insertOrgUnit(siteId, { parentId = null, unitType = 'area', name = 'Quality Area' } = {}) {
  const { rows: [orgUnit] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, $2, $3, $4, $5) RETURNING id, path`,
    [siteId, parentId, uniqueCode('QPOU'), name, unitType]
  );
  insertedOrgUnitIds.push(orgUnit.id);
  return orgUnit.id;
}

async function post(path, token, body) {
  const response = await fetch(`${base}${path}`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body ?? {})
  });
  return json(response);
}

async function patch(path, token, body) {
  const response = await fetch(`${base}${path}`, {
    method: 'PATCH',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body ?? {})
  });
  return json(response);
}

async function get(path, token) {
  const response = await fetch(`${base}${path}`, { headers: token });
  return json(response);
}

// A 33-byte PNG header is enough: the route reads the header, and the existing
// picture tests establish that a synthetic one states its size exactly.
function pngBuffer(width = 10, height = 10) {
  const buffer = Buffer.alloc(33);
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]).copy(buffer, 0);
  buffer.writeUInt32BE(13, 8);
  buffer.write('IHDR', 12, 'ascii');
  buffer.writeUInt32BE(width, 16);
  buffer.writeUInt32BE(height, 20);
  return buffer;
}

let adminToken;
let operator; // role operator: the default group only, writing on its line.
let siteId;
let areaId;
let lineId;
let product;
let defectCode;
let customer;
let supplier;

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

  const admin = await insertAccount({ role: 'admin', displayName: 'Avery Administrator' });
  adminToken = admin.token;

  siteId = await insertSite();
  areaId = await insertOrgUnit(siteId, { name: 'Assembly' });
  lineId = await insertOrgUnit(siteId, { parentId: areaId, unitType: 'line', name: 'Line 2' });

  operator = await insertAccount({ role: 'operator', displayName: 'Ola Operator' });
  await insertGrant({ accountId: operator.id, orgUnitId: areaId, canWrite: true });

  // The catalogues the records name, created through the API as the
  // administrator the codes allow — the same fixtures the other Quality suites
  // build, so this file tests the retrofit rather than a hand-made row.
  const productCode = uniqueCode('QPP-');
  const createdProduct = await post('/api/quality/products', adminToken, {
    code: productCode,
    name: `Product ${productCode}`,
    uomCode: 'EA'
  });
  assert.strictEqual(createdProduct.status, 201, JSON.stringify(createdProduct.body));
  insertedProductCodes.push(productCode);
  product = createdProduct.body.product;

  const defectCodeCode = uniqueCode('QPD-');
  const createdDefectCode = await post('/api/quality/defect-codes', adminToken, {
    code: defectCodeCode,
    name: `Defect ${defectCodeCode}`,
    category: 'product',
    defaultSeverity: 'major'
  });
  assert.strictEqual(createdDefectCode.status, 201, JSON.stringify(createdDefectCode.body));
  insertedDefectCodeCodes.push(defectCodeCode);
  defectCode = createdDefectCode.body.defectCode;

  const customerCode = uniqueCode('QPC-');
  const createdCustomer = await post('/api/quality/customers', adminToken, {
    code: customerCode,
    name: `Customer ${customerCode}`
  });
  assert.strictEqual(createdCustomer.status, 201, JSON.stringify(createdCustomer.body));
  insertedCustomerCodes.push(customerCode);
  customer = createdCustomer.body.customer;

  const supplierCode = uniqueCode('QPSUP-');
  const createdSupplier = await post('/api/quality/suppliers', adminToken, {
    code: supplierCode,
    name: `Supplier ${supplierCode}`
  });
  assert.strictEqual(createdSupplier.status, 201, JSON.stringify(createdSupplier.body));
  insertedSupplierCodes.push(supplierCode);
  supplier = createdSupplier.body.supplier;
});

test.after(async () => {
  // Children before parents, hardest descendant first: a picture points at its
  // record with a plain foreign key (no cascade), a complaint and a supplier NCR
  // name a Non-conformance, and every record names an Org Unit. A rejected
  // `test.after` hangs the file on the framework's timeout and cancels the files
  // behind it, so the order here is the whole cleanup.
  await pool.query(
    `DELETE FROM quality_issue_images
      WHERE quality_issue_id = ANY($1) OR customer_complaint_id = ANY($2)`,
    [insertedNonconformanceIds, insertedComplaintIds]
  );
  await pool.query('DELETE FROM customer_complaints WHERE id = ANY($1)', [insertedComplaintIds]);
  await pool.query('DELETE FROM supplier_ncrs WHERE id = ANY($1)', [insertedSupplierNcrIds]);
  await pool.query('DELETE FROM quality_issues WHERE id = ANY($1)', [insertedNonconformanceIds]);
  await pool.query('DELETE FROM products WHERE code = ANY($1)', [insertedProductCodes]);
  await pool.query('DELETE FROM defect_codes WHERE code = ANY($1)', [insertedDefectCodeCodes]);
  await pool.query('DELETE FROM customers WHERE code = ANY($1)', [insertedCustomerCodes]);
  await pool.query('DELETE FROM suppliers WHERE code = ANY($1)', [insertedSupplierCodes]);
  await pool.query('DELETE FROM app_user_org_units WHERE app_user_id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM app_users WHERE id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM org_units WHERE id = ANY($1)', [insertedOrgUnitIds]);
  await pool.query('DELETE FROM sites WHERE id = ANY($1)', [insertedSiteIds]);
  await new Promise((resolve) => server.close(resolve));
  await closePool();
});

// ---------------------------------------------------------------------------
// The premise the retrofit rests on, executed rather than asserted: an Account
// holding the default group alone really does hold every code the gates ask.
// ---------------------------------------------------------------------------

const retrofittedCodes = [
  'QLT_PRODUCTS_DISPLAY',
  'QLT_DEFECT_CODES_DISPLAY',
  'QLT_NONCONFORMANCES_DISPLAY',
  'QLT_NONCONFORMANCES_RECORD',
  'QLT_CUSTOMERS_DISPLAY',
  'QLT_COMPLAINTS_DISPLAY',
  'QLT_COMPLAINTS_RECORD',
  'QLT_SLIDESHOW_DISPLAY',
  'QLT_SUPPLIERS_DISPLAY',
  'QLT_SUPPLIER_NCRS_DISPLAY'
];

test('an operator holds every code the retrofit asks, and none of the four the catalogue-write swap asks', async () => {
  const { status, body } = await get('/api/people/me', operator.token);
  assert.strictEqual(status, 200, JSON.stringify(body));

  for (const code of retrofittedCodes) {
    assert.ok(
      body.permissions.includes(code),
      `${code} must reach every Account through ROLE_STANDARD — held: ${body.permissions.join(', ')}`
    );
  }

  // The four catalogue writes swapped `requireAdmin` for these codes, which the
  // seed gives to ROLE_ADMIN alone: this operator must not hold them, which is
  // what makes that swap the same audience rather than a widening.
  for (const code of [
    'QLT_PRODUCTS_CHANGE',
    'QLT_DEFECT_CODES_CHANGE',
    'QLT_CUSTOMERS_CHANGE',
    'QLT_SUPPLIERS_CHANGE'
  ]) {
    assert.ok(
      !body.permissions.includes(code),
      `${code} is administrator-only and must not reach an operator`
    );
  }
});

// ---------------------------------------------------------------------------
// The retrofitted reads: the operator could reach every one before ADR-0061 and
// still does.
// ---------------------------------------------------------------------------

for (const [label, path] of [
  ['the Product catalogue', () => '/api/quality/products'],
  ['the Defect code catalogue', () => '/api/quality/defect-codes'],
  ['the Customer catalogue', () => '/api/quality/customers'],
  ['the Supplier catalogue', () => '/api/quality/suppliers'],
  ['the Non-conformance register', () => `/api/quality/sites/${siteId}/nonconformances`],
  ['the complaint register', () => `/api/quality/sites/${siteId}/complaints`],
  ['the supplier NCR register', () => `/api/quality/sites/${siteId}/supplier-ncrs`],
  ['the slide show', () => `/api/quality/sites/${siteId}/slide-show`]
]) {
  test(`an operator reads ${label} — the retrofit refused nobody`, async () => {
    const { status, body } = await get(path(), operator.token);
    assert.strictEqual(status, 200, `${label}: ${JSON.stringify(body)}`);
  });
}

// The detail reads need a record to name, and the ids below name none: a 404 is
// the proof that the permission gate admitted the caller and the route's own
// existence check answered, since a refusal would be a 403 from the code.
test('an operator reaches the one-record reads and the picture list', async () => {
  for (const path of [
    '/api/quality/nonconformances/999999999',
    '/api/quality/complaints/999999999',
    '/api/quality/supplier-ncrs/999999999',
    '/api/quality/nonconformances/999999999/images',
    '/api/quality/complaints/999999999/images'
  ]) {
    const { status, body } = await get(path, operator.token);
    assert.strictEqual(status, 404, `${path}: ${JSON.stringify(body)}`);
  }
});

// ---------------------------------------------------------------------------
// The retrofitted writes: recording, the containment PATCH, the quantity
// increase and a picture, all as an operator with a write Grant on its line.
// ---------------------------------------------------------------------------

test('an operator records a Non-conformance, contains it, raises its quantity and attaches a picture', async () => {
  const recorded = await post(`/api/quality/sites/${siteId}/nonconformances`, operator.token, {
    orgUnitId: String(lineId),
    productId: String(product.id),
    defectCodeId: String(defectCode.id),
    quantity: 12,
    detectionPoint: 'in_process',
    description: 'Flash on the mating face.'
  });
  assert.strictEqual(recorded.status, 201, JSON.stringify(recorded.body));
  const nonconformance = recorded.body.nonconformance;
  insertedNonconformanceIds.push(nonconformance.id);

  // PATCH asks QLT_NONCONFORMANCES_RECORD: the containment a recorder writes.
  const contained = await patch(`/api/quality/nonconformances/${nonconformance.id}`, operator.token, {
    containment: 'Quarantined the bin and told the line leader.'
  });
  assert.strictEqual(contained.status, 200, JSON.stringify(contained.body));

  // The quantity increase asks the same code — it appends history rather than
  // correcting a field, but it is the recorder's act. It takes the new total,
  // not a delta: anything not above the current 12 is a 409.
  const increased = await post(
    `/api/quality/nonconformances/${nonconformance.id}/quantity`,
    operator.token,
    { quantity: 16, note: 'Four more found at the next inspection.' }
  );
  assert.strictEqual(increased.status, 200, JSON.stringify(increased.body));

  // A picture is part of the record: the upload and the removal ask the same
  // code, and the read asks its DISPLAY half.
  const upload = await fetch(
    `${base}/api/quality/nonconformances/${nonconformance.id}/images`,
    { method: 'POST', headers: { ...operator.token, 'content-type': 'image/png' }, body: pngBuffer() }
  );
  const uploaded = await json(upload);
  assert.strictEqual(uploaded.status, 201, JSON.stringify(uploaded.body));

  const pictures = await get(
    `/api/quality/nonconformances/${nonconformance.id}/images`,
    operator.token
  );
  assert.strictEqual(pictures.status, 200, JSON.stringify(pictures.body));
  assert.strictEqual(pictures.body.images.length, 1);

  const remove = await fetch(
    `${base}/api/quality/nonconformances/${nonconformance.id}/images/${uploaded.body.image.id}`,
    { method: 'DELETE', headers: operator.token }
  );
  assert.strictEqual(remove.status, 204);
});

test('an operator records a complaint and records a Non-conformance from it', async () => {
  const recorded = await post(`/api/quality/sites/${siteId}/complaints`, operator.token, {
    orgUnitId: String(lineId),
    customerId: String(customer.id),
    productId: String(product.id),
    defectCodeId: String(defectCode.id),
    quantity: 4,
    description: 'The customer reports four parts that will not seat.'
  });
  assert.strictEqual(recorded.status, 201, JSON.stringify(recorded.body));
  const complaint = recorded.body.complaint;
  insertedComplaintIds.push(complaint.id);

  // QLT_NONCONFORMANCES_RECORD: the act is recording a Non-conformance, whatever
  // door it came through.
  const controlled = await post(`/api/quality/complaints/${complaint.id}/nonconformance`, operator.token, {
    quantity: 4
  });
  assert.strictEqual(controlled.status, 201, JSON.stringify(controlled.body));
  insertedNonconformanceIds.push(controlled.body.nonconformance.id);
});

// ---------------------------------------------------------------------------
// The findings: the routes left on their Grant check must still admit this
// operator, or the retrofit narrowed by accident.
// ---------------------------------------------------------------------------

test('the finding routes still admit an operator: an NCR, its disposition, and a complaint response', async () => {
  // Recording a supplier NCR is a finding (QLT_SUPPLIER_NCRS_RECORD is
  // administrator-only), so the write Grant is the whole gate — and the operator
  // must still get through it.
  const recorded = await post(`/api/quality/sites/${siteId}/supplier-ncrs`, operator.token, {
    orgUnitId: String(lineId),
    supplierId: String(supplier.id),
    productId: String(product.id),
    defectCodeId: String(defectCode.id),
    quantity: 250,
    incomingLotRef: 'LOT-4771',
    description: 'The thread on the M8 bolts is undersized.'
  });
  assert.strictEqual(recorded.status, 201, JSON.stringify(recorded.body));
  const supplierNcr = recorded.body.supplierNcr;
  insertedSupplierNcrIds.push(supplierNcr.id);

  // A Disposition is a finding too (QLT_NONCONFORMANCES_DISPOSE is
  // engineer-and-above), so the write Grant decides, exactly as before.
  const nonconformanceId = insertedNonconformanceIds[0];
  const disposition = await post(
    `/api/quality/nonconformances/${nonconformanceId}/dispositions`,
    operator.token,
    { dispositionType: 'scrap', quantity: 5 }
  );
  assert.strictEqual(disposition.status, 201, JSON.stringify(disposition.body));

  // Responding to a complaint names no code in the catalogue, so it is the
  // Grant's: closing one must still work for this operator.
  const complaintId = insertedComplaintIds[0];
  const responded = await post(`/api/quality/complaints/${complaintId}/respond`, operator.token, {
    responseNote: 'Replacement parts shipped and the line re-checked.'
  });
  assert.strictEqual(responded.status, 200, JSON.stringify(responded.body));
});

// ---------------------------------------------------------------------------
// And the gates are wired at all. Two mutants, each removing one code from every
// role that holds it and watching exactly its own address start refusing — the
// check that no gate was left in place by accident.
//
// Every role that holds it, not just the default group: `effectivePermissions`
// unions the default group, the role the Account's own `app_users.role` earns
// (this operator's is ROLE_OPERATOR) and any explicit assignment, so removing a
// code from ROLE_STANDARD alone would leave the operator holding it through
// ROLE_OPERATOR — and then the mutant would prove nothing.
// ---------------------------------------------------------------------------

async function removeCodeEverywhere(code) {
  const { rows } = await pool.query(
    'SELECT app_role_id FROM app_role_permissions WHERE permission_code = $1',
    [code]
  );
  assert.ok(rows.length > 0, `${code} must be seeded on at least one role`);
  await pool.query('DELETE FROM app_role_permissions WHERE permission_code = $1', [code]);
  return rows.map((row) => row.app_role_id);
}

async function restoreCodeEverywhere(roleIds, code) {
  for (const roleId of roleIds) {
    await pool.query(
      'INSERT INTO app_role_permissions (app_role_id, permission_code) VALUES ($1, $2)',
      [roleId, code]
    );
  }
}

test('removing QLT_PRODUCTS_DISPLAY from every role refuses the Product list and nothing else', async () => {
  const roleIds = await removeCodeEverywhere('QLT_PRODUCTS_DISPLAY');
  try {
    const refused = await get('/api/quality/products', operator.token);
    assert.strictEqual(refused.status, 403, JSON.stringify(refused.body));
    assert.strictEqual(refused.body.code, 'PERMISSION_REQUIRED');
    assert.strictEqual(refused.body.permission, 'QLT_PRODUCTS_DISPLAY');

    // A neighbouring gate is untouched: the read it does not name still answers.
    const others = await get('/api/quality/defect-codes', operator.token);
    assert.strictEqual(others.status, 200, JSON.stringify(others.body));
  } finally {
    await restoreCodeEverywhere(roleIds, 'QLT_PRODUCTS_DISPLAY');
  }

  // Restored, the same address answers again — the gate reads the tables on
  // every request rather than caching what it saw at sign-in.
  const allowed = await get('/api/quality/products', operator.token);
  assert.strictEqual(allowed.status, 200, JSON.stringify(allowed.body));
});

test('removing QLT_NONCONFORMANCES_RECORD from every role refuses the containment PATCH and nothing else', async () => {
  const nonconformanceId = insertedNonconformanceIds[0];
  const roleIds = await removeCodeEverywhere('QLT_NONCONFORMANCES_RECORD');
  try {
    const refused = await patch(`/api/quality/nonconformances/${nonconformanceId}`, operator.token, {
      containment: 'Written by the mutant test.'
    });
    assert.strictEqual(refused.status, 403, JSON.stringify(refused.body));
    assert.strictEqual(refused.body.code, 'PERMISSION_REQUIRED');
    assert.strictEqual(refused.body.permission, 'QLT_NONCONFORMANCES_RECORD');

    // The Non-conformance register asks the DISPLAY code, which is still held.
    const register = await get(`/api/quality/sites/${siteId}/nonconformances`, operator.token);
    assert.strictEqual(register.status, 200, JSON.stringify(register.body));
  } finally {
    await restoreCodeEverywhere(roleIds, 'QLT_NONCONFORMANCES_RECORD');
  }

  const allowed = await patch(`/api/quality/nonconformances/${nonconformanceId}`, operator.token, {
    containment: 'Quarantined the bin a second time.'
  });
  assert.strictEqual(allowed.status, 200, JSON.stringify(allowed.body));
});
