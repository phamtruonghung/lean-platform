/*
 * The Quality write retrofit (ADR-0061, issue #535), over HTTP against a real
 * database and a real local session — the seam quality-permission-roles.test.js,
 * nonconformance-dispositions.test.js, customer-complaints.test.js,
 * quality-slide-show.test.js and supplier-ncrs.test.js already establish.
 *
 * Two claims, and this file is the only place either is measured.
 *
 * **The retrofit narrows nobody.** Every one of the thirteen write routes this
 * slice gates was reachable by any Account holding the right Grant — a write
 * Grant for a Disposition, a complaint's response or a supplier NCR, and a Grant
 * carrying Quality authority for a Concession — whatever its role, because
 * `canAct` is role-blind. Three of the codes those routes now ask were seeded
 * narrower than that (`QLT_NONCONFORMANCES_DISPOSE` engineer-and-above,
 * `QLT_SLIDESHOW_CHOOSE` and `QLT_SUPPLIER_NCRS_RECORD` administrator-only), so
 * `1803900000000_quality-write-codes.js` widens all three onto every role. The
 * tests below read that back: an operator, holding the default group and a write
 * Grant on its line, still dispositions, chooses a slide-show issue and works a
 * supplier NCR; an operator holding Quality authority without any write Grant
 * still grants the Concession it always could (ADR-0035 keeps the two flags
 * independent).
 *
 * **The code is what the route asks, not decoration.** A gate that admits
 * everyone is easy to write and easy to get wrong: a route with no middleware at
 * all passes every "the seeded role gets 2xx" test. So each code is also proven
 * to refuse, by doing what an administrator would do — taking the code off every
 * role for the length of one request, and putting it back. The refusal is then
 * 403 `PERMISSION_REQUIRED` naming that exact code, before any row is read.
 * `withoutTheCode` captures the rows it removes and restores them in a `finally`,
 * so the seed is left exactly as it was found.
 *
 * Needs a database with every migration applied, including
 * 1803900000000_quality-write-codes.js. Set DATABASE_URL first — see the
 * README's Tests section.
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

async function insertAccount({ role = 'operator', displayName = null, grants = [] } = {}) {
  const subject = uniqueCode('qwacct');
  const name = displayName ?? `Quality Write Account ${subject}`;
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

  return { id: account.id, role, token: await authHeader(subject) };
}

async function insertSite() {
  const { rows: [site] } = await pool.query(
    `INSERT INTO sites (code, name, timezone) VALUES ($1, $2, $3) RETURNING id`,
    [uniqueCode('QWPS'), 'Quality Write Test Site', 'Asia/Ho_Chi_Minh']
  );
  insertedSiteIds.push(site.id);
  return site.id;
}

async function insertOrgUnit(siteId, { parentId = null, unitType = 'area', name = 'Quality Area' } = {}) {
  const { rows: [orgUnit] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, $2, $3, $4, $5) RETURNING id`,
    [siteId, parentId, uniqueCode('QWOU'), name, unitType]
  );
  insertedOrgUnitIds.push(orgUnit.id);
  return orgUnit.id;
}

async function get(path, token) {
  return json(await fetch(`${base}${path}`, { headers: token }));
}

async function post(path, token, body) {
  const response = await fetch(`${base}${path}`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body ?? {})
  });
  return json(response);
}

async function put(path, token, body) {
  const response = await fetch(`${base}${path}`, {
    method: 'PUT',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body ?? {})
  });
  return json(response);
}

// A 33-byte PNG header is enough: the upload reads the header, and the existing
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
let siteId;
let areaId;
let lineId;
let product;
let defectCode;
let customer;
let supplier;

// An operator: the default group plus ROLE_OPERATOR, and a write Grant on the
// line — the lowest role that can reach these writes today.
let operator;
// An operator with Quality authority and no write Grant at all: ADR-0035 keeps
// the two flags independent, and this is the Account the Concession widening is
// for.
let inspector;
// A manager, for the day the card describes.
let manager;
// An operator with no Grant anywhere: the scope helper still answers this.
let outsider;

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
  lineId = await insertOrgUnit(siteId, { parentId: areaId, unitType: 'line', name: 'Line 4' });

  operator = await insertAccount({
    role: 'operator',
    displayName: 'Ola Operator',
    grants: [{ orgUnitId: lineId, write: true }]
  });
  inspector = await insertAccount({
    role: 'operator',
    displayName: 'Ines Inspector',
    grants: [{ orgUnitId: areaId, write: false, quality: true }]
  });
  manager = await insertAccount({
    role: 'manager',
    displayName: 'Mai Manager',
    grants: [{ orgUnitId: areaId, write: true, quality: true }]
  });
  outsider = await insertAccount({ role: 'operator', displayName: 'Otto Outsider' });

  // The catalogues the records name, created through the API as the
  // administrator the codes allow — the same fixtures the other Quality suites
  // build, so this file tests the retrofit rather than a hand-made row.
  const productCode = uniqueCode('QWP-');
  const createdProduct = await post('/api/quality/products', adminToken, {
    code: productCode,
    name: `Product ${productCode}`,
    uomCode: 'EA'
  });
  assert.strictEqual(createdProduct.status, 201, JSON.stringify(createdProduct.body));
  insertedProductCodes.push(productCode);
  product = createdProduct.body.product;

  const defectCodeCode = uniqueCode('QWD-');
  const createdDefectCode = await post('/api/quality/defect-codes', adminToken, {
    code: defectCodeCode,
    name: `Defect ${defectCodeCode}`,
    category: 'product',
    defaultSeverity: 'major'
  });
  assert.strictEqual(createdDefectCode.status, 201, JSON.stringify(createdDefectCode.body));
  insertedDefectCodeCodes.push(defectCodeCode);
  defectCode = createdDefectCode.body.defectCode;

  const customerCode = uniqueCode('QWC-');
  const createdCustomer = await post('/api/quality/customers', adminToken, {
    code: customerCode,
    name: `Customer ${customerCode}`
  });
  assert.strictEqual(createdCustomer.status, 201, JSON.stringify(createdCustomer.body));
  insertedCustomerCodes.push(customerCode);
  customer = createdCustomer.body.customer;

  const supplierCode = uniqueCode('QWSUP-');
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
// Records, all recorded as the administrator so a fixture never depends on the
// code under test.
// ---------------------------------------------------------------------------

async function makeNonconformance(quantity = 12) {
  const recorded = await post(`/api/quality/sites/${siteId}/nonconformances`, adminToken, {
    orgUnitId: String(lineId),
    productId: String(product.id),
    defectCodeId: String(defectCode.id),
    quantity,
    detectionPoint: 'in_process',
    description: 'Weld spatter on the bracket face.'
  });
  assert.strictEqual(recorded.status, 201, JSON.stringify(recorded.body));
  insertedNonconformanceIds.push(recorded.body.nonconformance.id);
  return recorded.body.nonconformance;
}

async function makeComplaint(quantity = 4) {
  const recorded = await post(`/api/quality/sites/${siteId}/complaints`, adminToken, {
    orgUnitId: String(lineId),
    customerId: String(customer.id),
    productId: String(product.id),
    defectCodeId: String(defectCode.id),
    quantity,
    description: 'The customer reports four brackets that will not seat.'
  });
  assert.strictEqual(recorded.status, 201, JSON.stringify(recorded.body));
  insertedComplaintIds.push(recorded.body.complaint.id);
  return recorded.body.complaint;
}

async function makeSupplierNcr(quantity = 250) {
  const recorded = await post(`/api/quality/sites/${siteId}/supplier-ncrs`, adminToken, {
    orgUnitId: String(lineId),
    supplierId: String(supplier.id),
    productId: String(product.id),
    defectCodeId: String(defectCode.id),
    quantity,
    incomingLotRef: 'LOT-8802',
    description: 'The thread on the M8 bolts is undersized.'
  });
  assert.strictEqual(recorded.status, 201, JSON.stringify(recorded.body));
  insertedSupplierNcrIds.push(recorded.body.supplierNcr.id);
  return recorded.body.supplierNcr;
}

// ---------------------------------------------------------------------------
// An administrator's edit: take a code off every role that holds it, for the
// length of one request, and put it back exactly as it was.
//
// Every role, not just the default group: `effectivePermissions` unions the
// default group, the role the Account's own `app_users.role` earns and any
// explicit assignment, so removing a code from ROLE_STANDARD alone would leave
// the caller holding it through its own role — and then the mutant would prove
// nothing.
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

async function withoutTheCode(code, request) {
  const roleIds = await removeCodeEverywhere(code);
  try {
    return await request();
  } finally {
    await restoreCodeEverywhere(roleIds, code);
  }
}

// ---------------------------------------------------------------------------
// The premise the retrofit rests on, executed rather than asserted: an operator
// really does hold every code the writes ask — which is what the widening bought.
// ---------------------------------------------------------------------------

const WRITE_CODES = [
  'QLT_COMPLAINTS_RECORD',
  'QLT_NONCONFORMANCES_RECORD',
  'QLT_NONCONFORMANCES_DISPOSE',
  'QLT_SLIDESHOW_CHOOSE',
  'QLT_SUPPLIER_NCRS_RECORD'
];

test('an operator holds every code the Quality writes ask, and the catalogue will not tell the roles apart', async () => {
  for (const account of [operator, inspector, manager]) {
    const { status, body } = await get('/api/people/me', account.token);
    assert.strictEqual(status, 200, JSON.stringify(body));
    for (const code of WRITE_CODES) {
      assert.ok(
        body.permissions.includes(code),
        `${account.role} account must hold ${code} — held: ${body.permissions.join(', ')}`
      );
    }
  }

  // The seed really does carry all six roles for the three codes this slice
  // widened, which is the fact no caller's answer changed rests on.
  const { rows } = await pool.query(
    `SELECT permission_code, count(*)::int AS roles
       FROM app_role_permissions
      WHERE permission_code = ANY($1)
      GROUP BY permission_code`,
    [WRITE_CODES]
  );
  assert.strictEqual(rows.length, WRITE_CODES.length, JSON.stringify(rows));
  for (const row of rows) {
    assert.strictEqual(row.roles, 6, `${row.permission_code} must be seeded on all six roles`);
  }
});

// ---------------------------------------------------------------------------
// QLT_COMPLAINTS_RECORD — responding to a complaint.
// ---------------------------------------------------------------------------

test('QLT_COMPLAINTS_RECORD: an operator answers a complaint, and the code is what admits it', async () => {
  const complaint = await makeComplaint();

  const refused = await withoutTheCode('QLT_COMPLAINTS_RECORD', () =>
    post(`/api/quality/complaints/${complaint.id}/respond`, operator.token, {
      responseNote: 'Written while the code was off every role.'
    })
  );
  assert.strictEqual(refused.status, 403, JSON.stringify(refused.body));
  assert.strictEqual(refused.body.code, 'PERMISSION_REQUIRED');
  assert.strictEqual(refused.body.permission, 'QLT_COMPLAINTS_RECORD');

  const answered = await post(`/api/quality/complaints/${complaint.id}/respond`, operator.token, {
    responseNote: 'Replacement brackets shipped and the line re-checked.'
  });
  assert.strictEqual(answered.status, 200, JSON.stringify(answered.body));
  assert.strictEqual(answered.body.complaint.status, 'closed');
});

// ---------------------------------------------------------------------------
// QLT_NONCONFORMANCES_RECORD — a Disposition is the work, not the decision.
// ---------------------------------------------------------------------------

test('QLT_NONCONFORMANCES_RECORD: an operator records a Disposition, and the code is what admits it', async () => {
  const nonconformance = await makeNonconformance();

  const refused = await withoutTheCode('QLT_NONCONFORMANCES_RECORD', () =>
    post(`/api/quality/nonconformances/${nonconformance.id}/dispositions`, operator.token, {
      dispositionType: 'scrap',
      quantity: 5
    })
  );
  assert.strictEqual(refused.status, 403, JSON.stringify(refused.body));
  assert.strictEqual(refused.body.code, 'PERMISSION_REQUIRED');
  assert.strictEqual(refused.body.permission, 'QLT_NONCONFORMANCES_RECORD');

  const recorded = await post(`/api/quality/nonconformances/${nonconformance.id}/dispositions`, operator.token, {
    dispositionType: 'scrap',
    quantity: 5
  });
  assert.strictEqual(recorded.status, 201, JSON.stringify(recorded.body));
  assert.strictEqual(recorded.body.nonconformance.dispositions[0].dispositionType, 'scrap');
});

// ---------------------------------------------------------------------------
// QLT_NONCONFORMANCES_DISPOSE — a Concession is the decision, and the widening
// is what lets the Quality authority without a write Grant still make it.
// ---------------------------------------------------------------------------

test('QLT_NONCONFORMANCES_DISPOSE: a Quality inspector with no write Grant still grants a Concession, and the code is what admits it', async () => {
  const nonconformance = await makeNonconformance(15);

  const refused = await withoutTheCode('QLT_NONCONFORMANCES_DISPOSE', () =>
    post(`/api/quality/nonconformances/${nonconformance.id}/concession`, inspector.token, {
      dispositionType: 'use_as_is',
      quantity: 6,
      reference: 'DEV-2026-0031',
      note: 'Customer engineering accepts the cosmetic marks on this lot.'
    })
  );
  assert.strictEqual(refused.status, 403, JSON.stringify(refused.body));
  assert.strictEqual(refused.body.code, 'PERMISSION_REQUIRED');
  assert.strictEqual(refused.body.permission, 'QLT_NONCONFORMANCES_DISPOSE');

  const granted = await post(`/api/quality/nonconformances/${nonconformance.id}/concession`, inspector.token, {
    dispositionType: 'use_as_is',
    quantity: 6,
    reference: 'DEV-2026-0031',
    note: 'Customer engineering accepts the cosmetic marks on this lot.'
  });
  assert.strictEqual(granted.status, 201, JSON.stringify(granted.body));
  assert.strictEqual(granted.body.nonconformance.dispositions[0].isConcession, true);
  assert.strictEqual(granted.body.nonconformance.dispositions[0].decidedByAccountId, String(inspector.id));
});

test('the other three decisions a Non-conformance moves through ask the same disposal code', async () => {
  // Lowering a severity, reopening after a close and calling a record off are
  // the same Quality authority as a Concession, so each is refused before its
  // own state is even read when the code is gone.
  const lowering = await makeNonconformance();
  const refusedLower = await withoutTheCode('QLT_NONCONFORMANCES_DISPOSE', () =>
    post(`/api/quality/nonconformances/${lowering.id}/lower-severity`, inspector.token, {
      severity: 'minor',
      note: 'Only the label was misprinted.'
    })
  );
  assert.strictEqual(refusedLower.status, 403, JSON.stringify(refusedLower.body));
  assert.strictEqual(refusedLower.body.permission, 'QLT_NONCONFORMANCES_DISPOSE');

  const allowed = await post(`/api/quality/nonconformances/${lowering.id}/lower-severity`, inspector.token, {
    severity: 'minor',
    note: 'Only the label was misprinted.'
  });
  assert.strictEqual(allowed.status, 200, JSON.stringify(allowed.body));

  const cancelled = await makeNonconformance();
  const refusedCancel = await withoutTheCode('QLT_NONCONFORMANCES_DISPOSE', () =>
    post(`/api/quality/nonconformances/${cancelled.id}/cancel`, inspector.token, {
      note: 'Recorded against the wrong Product.'
    })
  );
  assert.strictEqual(refusedCancel.status, 403, JSON.stringify(refusedCancel.body));
  assert.strictEqual(refusedCancel.body.permission, 'QLT_NONCONFORMANCES_DISPOSE');
});

// ---------------------------------------------------------------------------
// QLT_SLIDESHOW_CHOOSE — choosing an issue and ordering the wall.
// ---------------------------------------------------------------------------

test('QLT_SLIDESHOW_CHOOSE: an operator puts an issue on the wall, and the code is what admits it', async () => {
  const nonconformance = await makeNonconformance();

  // The choice needs a picture to show (409 without one), so the fixture gets
  // one through the same door a recorder uses.
  const upload = await fetch(`${base}/api/quality/nonconformances/${nonconformance.id}/images`, {
    method: 'POST',
    headers: { ...adminToken, 'content-type': 'image/png' },
    body: pngBuffer()
  });
  assert.strictEqual(upload.status, 201);

  const refused = await withoutTheCode('QLT_SLIDESHOW_CHOOSE', () =>
    put(`/api/quality/slide-show/nonconformance/${nonconformance.id}`, operator.token, { chosen: true })
  );
  assert.strictEqual(refused.status, 403, JSON.stringify(refused.body));
  assert.strictEqual(refused.body.code, 'PERMISSION_REQUIRED');
  assert.strictEqual(refused.body.permission, 'QLT_SLIDESHOW_CHOOSE');

  const chosen = await put(`/api/quality/slide-show/nonconformance/${nonconformance.id}`, operator.token, {
    chosen: true
  });
  assert.strictEqual(chosen.status, 200, JSON.stringify(chosen.body));
  assert.strictEqual(chosen.body.inSlideShow, true);
});

// ---------------------------------------------------------------------------
// QLT_SUPPLIER_NCRS_RECORD — recording an NCR and working it are one code.
// ---------------------------------------------------------------------------

test('QLT_SUPPLIER_NCRS_RECORD: an operator disposes of a supplier NCR, and the code is what admits it', async () => {
  const ncr = await makeSupplierNcr();

  const refused = await withoutTheCode('QLT_SUPPLIER_NCRS_RECORD', () =>
    post(`/api/quality/supplier-ncrs/${ncr.id}/disposition`, operator.token, {
      disposition: 'rework_at_cost',
      costRecovered: 1875.5,
      currency: 'EUR'
    })
  );
  assert.strictEqual(refused.status, 403, JSON.stringify(refused.body));
  assert.strictEqual(refused.body.code, 'PERMISSION_REQUIRED');
  assert.strictEqual(refused.body.permission, 'QLT_SUPPLIER_NCRS_RECORD');

  const decided = await post(`/api/quality/supplier-ncrs/${ncr.id}/disposition`, operator.token, {
    disposition: 'rework_at_cost',
    costRecovered: 1875.5,
    currency: 'EUR'
  });
  assert.strictEqual(decided.status, 200, JSON.stringify(decided.body));
  assert.strictEqual(decided.body.supplierNcr.disposition, 'rework_at_cost');
});

// ---------------------------------------------------------------------------
// The quality manager's day: the four acts the card names, still 2xx, in one
// Account that could do all four yesterday.
// ---------------------------------------------------------------------------

test("the quality manager's day still works: a disposition, a Concession, a slide-show choice and a supplier NCR", async () => {
  const forDisposition = await makeNonconformance();
  const disposition = await post(
    `/api/quality/nonconformances/${forDisposition.id}/dispositions`,
    manager.token,
    { dispositionType: 'rework', quantity: 4, reworkMinutes: 30 }
  );
  assert.strictEqual(disposition.status, 201, JSON.stringify(disposition.body));

  const forConcession = await makeNonconformance(20);
  const concession = await post(
    `/api/quality/nonconformances/${forConcession.id}/concession`,
    manager.token,
    {
      dispositionType: 'use_as_is',
      quantity: 5,
      reference: 'DEV-2026-0032',
      note: 'Accepted for the service-parts order only.'
    }
  );
  assert.strictEqual(concession.status, 201, JSON.stringify(concession.body));
  assert.strictEqual(concession.body.nonconformance.dispositions[0].isConcession, true);

  const forWall = await makeNonconformance();
  const upload = await fetch(`${base}/api/quality/nonconformances/${forWall.id}/images`, {
    method: 'POST',
    headers: { ...manager.token, 'content-type': 'image/png' },
    body: pngBuffer(320, 240)
  });
  assert.strictEqual(upload.status, 201);
  const chosen = await put(`/api/quality/slide-show/nonconformance/${forWall.id}`, manager.token, {
    chosen: true
  });
  assert.strictEqual(chosen.status, 200, JSON.stringify(chosen.body));
  const ordered = await put(`/api/quality/sites/${siteId}/slide-show/order`, manager.token, {
    slides: [{ kind: 'nonconformance', id: String(forWall.id) }]
  });
  assert.strictEqual(ordered.status, 200, JSON.stringify(ordered.body));

  const ncr = await makeSupplierNcr();
  const recorded = await post(`/api/quality/sites/${siteId}/supplier-ncrs`, manager.token, {
    orgUnitId: String(lineId),
    supplierId: String(supplier.id),
    productId: String(product.id),
    defectCodeId: String(defectCode.id),
    quantity: 40,
    incomingLotRef: 'LOT-8803',
    description: 'Two cartons arrived with the seal broken.'
  });
  assert.strictEqual(recorded.status, 201, JSON.stringify(recorded.body));
  insertedSupplierNcrIds.push(recorded.body.supplierNcr.id);

  const closed = await post(`/api/quality/supplier-ncrs/${ncr.id}/close`, manager.token, {});
  assert.strictEqual(closed.status, 200, JSON.stringify(closed.body));
});

// ---------------------------------------------------------------------------
// The Grant still answers behind the code: an Account with the code and no Grant
// anywhere is refused by the scope helper, not by the permission.
// ---------------------------------------------------------------------------

test('the scope helper still answers behind the code: no Grant is OUTSIDE_GRANTED_ORG_UNITS, not PERMISSION_REQUIRED', async () => {
  const nonconformance = await makeNonconformance();

  const refused = await post(`/api/quality/nonconformances/${nonconformance.id}/dispositions`, outsider.token, {
    dispositionType: 'scrap',
    quantity: 5
  });
  assert.strictEqual(refused.status, 403, JSON.stringify(refused.body));
  assert.strictEqual(refused.body.code, undefined, JSON.stringify(refused.body));
  assert.match(refused.body.message, /Org Unit/);
});

// ---------------------------------------------------------------------------
// And the same three decisions keep the Concession's authority question: an
// Account holding a write Grant WITHOUT Quality authority is still refused by
// `requireNonconformanceQualityAuthority` — the code did not replace it.
// ---------------------------------------------------------------------------

test('the Quality-authority helper still answers behind the code for a Concession', async () => {
  const nonconformance = await makeNonconformance(15);

  const refused = await post(`/api/quality/nonconformances/${nonconformance.id}/concession`, operator.token, {
    dispositionType: 'use_as_is',
    quantity: 6,
    reference: 'DEV-2026-0033',
    note: 'The recorder would like this accepted.'
  });
  assert.strictEqual(refused.status, 403, JSON.stringify(refused.body));
  assert.match(refused.body.message, /Quality authority/);
});
