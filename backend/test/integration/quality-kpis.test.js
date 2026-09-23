/*
 * The Quality KPIs on the tier board (issue #216) — over HTTP, against a real
 * database and a real (locally issued) JWKS, and read through the board's own
 * existing address. The seam, the fixture scaffolding and the dependency-ordered
 * cleanup are the ones `tier-board.test.js` and `customer-complaints.test.js`
 * already establish.
 *
 * Every record this file asserts on is made **through the API**: Non-conformances
 * recorded at an Org Unit, their Dispositions, the CAPAs opened on a Concern with
 * a due date, and the customer complaints received. Two things are arranged by a
 * statement of their own, and each says why where it stands: the standard cost
 * and the labour rate the Cost figures are valued at (`product_costs` and
 * `cost_rates` are reference data no Module exposes a write for yet, and a KPI
 * whose arithmetic is unresolved would be asserted against nothing), and the two
 * states no route in this slice can reach — a CAPA waiting on an effectiveness
 * check, and a complaint rejected as unfounded — because reaching them means
 * driving a whole Concern closure or a decision this slice's own register does
 * not make.
 *
 * What is asserted, one test per acceptance criterion: `QUA_OPEN_NC` counts the
 * open and contained, non-cancelled Non-conformances for the chosen Org Unit and
 * everything beneath it, `QUA_OVERDUE_CAPA` counts the CAPAs past their due date
 * or with an overdue effectiveness check, `QUA_COMPLAINTS` counts the complaints
 * received in the period, and the Cost pillar's two cost-of-poor-quality KPIs
 * report the scrap and the rework from recorded Dispositions — each of them with
 * its Org Unit reach and its period boundaries.
 *
 * Issue #258 adds the other half of those two Cost figures: what they say when
 * the Platform cannot price what was recorded. Nothing here writes
 * `product_costs` or `cost_rates` for those tests on purpose — that is the
 * state every Site is in today — and the claim is that a recorded scrap or
 * rework nobody has a price for reports `no_data` rather than a currency zero,
 * that a partially priced period reports `no_data` for the whole period rather
 * than the low figure it could total, and that a period with nothing to price
 * is left exactly as it was. `QUA_FPY`, `QUA_INT_PPM`,
 * `QUA_CUST_PPM` and `DEL_QUALITY_RATE` keep reporting `no_data`, because every
 * one of them is a ratio against quantity produced and no Production Module
 * writes a production count.
 *
 * Needs a database with every migration applied. This slice adds no migration of
 * its own: the board computes on read, and every record it reads was already in
 * the baseline. Set DATABASE_URL first — see the README's Tests section.
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
const insertedActionIds = [];
const insertedCapaIds = [];
const insertedCostRateIds = [];

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

async function insertAccount({ role = 'operator', displayName = null, grants = [] } = {}) {
  const subject = uniqueCode('kpiacct');
  const name = displayName ?? `KPI Account ${subject}`;
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

async function insertSite({ timezone = 'Asia/Ho_Chi_Minh', name = 'KPI Test Site' } = {}) {
  const { rows: [site] } = await pool.query(
    `INSERT INTO sites (code, name, timezone) VALUES ($1, $2, $3) RETURNING id, code, name, timezone`,
    [uniqueCode('KPIS'), name, timezone]
  );
  insertedSiteIds.push(site.id);
  return site;
}

async function insertOrgUnit(siteId, { parentId = null, unitType = 'area', name = 'KPI Unit' } = {}) {
  const { rows: [orgUnit] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, $2, $3, $4, $5) RETURNING id, code, name, path`,
    [siteId, parentId, uniqueCode('KPIOU'), name, unitType]
  );
  insertedOrgUnitIds.push(orgUnit.id);
  return orgUnit;
}

// ---------------------------------------------------------------------------
// The records this file reads, each one made through the API
// ---------------------------------------------------------------------------

async function createProduct(adminToken) {
  const code = uniqueCode('KPIP-');
  const response = await fetch(`${base}/api/quality/products`, {
    method: 'POST',
    headers: { ...adminToken, 'content-type': 'application/json' },
    body: JSON.stringify({ code, name: `Product ${code}`, uomCode: 'EA' })
  });
  const { status, body } = await json(response);
  assert.strictEqual(status, 201, `creating ${code} failed: ${JSON.stringify(body)}`);
  insertedProductCodes.push(code);
  return body.product;
}

async function createDefectCode(adminToken) {
  const code = uniqueCode('KPID-');
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

async function createCustomer(adminToken) {
  const code = uniqueCode('KPIC-');
  const response = await fetch(`${base}/api/quality/customers`, {
    method: 'POST',
    headers: { ...adminToken, 'content-type': 'application/json' },
    body: JSON.stringify({ code, name: `Customer ${code}` })
  });
  const { status, body } = await json(response);
  assert.strictEqual(status, 201, `creating ${code} failed: ${JSON.stringify(body)}`);
  insertedCustomerCodes.push(code);
  return body.customer;
}

async function recordNonconformance(token, siteId, body) {
  const response = await fetch(`${base}/api/quality/sites/${siteId}/nonconformances`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  return json(response);
}

async function recordDisposition(token, nonconformanceId, body) {
  const response = await fetch(
    `${base}/api/quality/nonconformances/${nonconformanceId}/dispositions`,
    {
      method: 'POST',
      headers: { ...token, 'content-type': 'application/json' },
      body: JSON.stringify(body)
    }
  );
  return json(response);
}

async function cancelNonconformance(token, nonconformanceId, note) {
  const response = await fetch(
    `${base}/api/quality/nonconformances/${nonconformanceId}/cancel`,
    {
      method: 'POST',
      headers: { ...token, 'content-type': 'application/json' },
      body: JSON.stringify({ note })
    }
  );
  return json(response);
}

async function raiseConcern(token, siteId, body) {
  const response = await fetch(`${base}/api/actions/sites/${siteId}/actions`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify({ actionType: 'concern', ...body })
  });
  const payload = await json(response);
  if (payload.status === 201) insertedActionIds.push(payload.body.action.id);
  return payload;
}

async function openCapa(token, concernId, body = {}) {
  const response = await fetch(`${base}/api/actions/${concernId}/capa`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  const payload = await json(response);
  if (payload.status === 201) insertedCapaIds.push(payload.body.capa.id);
  return payload;
}

async function recordComplaint(token, siteId, body) {
  const response = await fetch(`${base}/api/quality/sites/${siteId}/complaints`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  return json(response);
}

// The board's own address (issue #76), unchanged by this ticket.
async function getBoard(token, siteId, query = '') {
  const response = await fetch(`${base}/api/maintenance/sites/${siteId}/board${query}`, {
    headers: token
  });
  const payload = await response.json().catch(() => null);
  return { response, payload };
}

function findKpi(board, pillarCode, kpiCode) {
  const pillar = board.pillars.find((candidate) => candidate.code === pillarCode);
  return pillar?.kpis.find((candidate) => candidate.code === kpiCode);
}

// A value read off the board, with the two facts a test has to see at once:
// what it says and whether it is a measurement at all.
function readKpi(board, pillarCode, kpiCode) {
  const kpi = findKpi(board, pillarCode, kpiCode);
  assert.ok(kpi, `${kpiCode} should be on the board`);
  return { value: kpi.value, status: kpi.status };
}

let admin;
let adminToken;

/**
 * The ground: a Site with two areas, each with a line beneath it, a quality
 * engineer granted (write and Quality authority) on both areas, a Product, a
 * Defect code and a Customer — every one of them a record the Platform itself
 * would have made.
 */
async function makeGround() {
  const site = await insertSite();
  const area = await insertOrgUnit(site.id, { name: 'Assembly' });
  const line = await insertOrgUnit(site.id, {
    parentId: area.id,
    unitType: 'line',
    name: 'Line 1'
  });
  const otherArea = await insertOrgUnit(site.id, { name: 'Packaging' });
  const otherLine = await insertOrgUnit(site.id, {
    parentId: otherArea.id,
    unitType: 'line',
    name: 'Packaging Line 1'
  });

  const engineer = await insertAccount({
    displayName: 'Quality Engineer',
    grants: [
      { orgUnitId: area.id, write: true, quality: true },
      { orgUnitId: otherArea.id, write: true, quality: true }
    ]
  });

  const product = await createProduct(adminToken);
  const defectCode = await createDefectCode(adminToken);
  const customer = await createCustomer(adminToken);

  return { site, area, line, otherArea, otherLine, engineer, product, defectCode, customer };
}

// A Non-conformance of the ordinary kind, at the Org Unit the caller names.
async function openNonconformance(
  ground,
  orgUnit,
  { quantity = 10, token = null, product = null } = {}
) {
  const recorded = await recordNonconformance(
    token ?? ground.engineer.token,
    ground.site.id,
    {
      orgUnitId: orgUnit.id,
      productId: (product ?? ground.product).id,
      defectCodeId: ground.defectCode.id,
      detectionPoint: 'in_process',
      quantity,
      description: 'Found on the line.'
    }
  );
  assert.strictEqual(recorded.status, 201, JSON.stringify(recorded.body));
  return recorded.body.nonconformance;
}

// A CAPA opened on a Concern of its own, at the Org Unit the caller names.
async function openInvestigation(ground, orgUnit, { dueDate = null } = {}) {
  const raised = await raiseConcern(ground.engineer.token, ground.site.id, {
    orgUnitId: orgUnit.id,
    title: `A problem at ${orgUnit.name}`
  });
  assert.strictEqual(raised.status, 201, JSON.stringify(raised.body));

  const opened = await openCapa(ground.engineer.token, raised.body.action.id, { dueDate });
  assert.strictEqual(opened.status, 201, JSON.stringify(opened.body));
  return opened.body.capa;
}

async function receiveComplaint(ground, orgUnit, overrides = {}) {
  const recorded = await recordComplaint(ground.engineer.token, ground.site.id, {
    orgUnitId: orgUnit.id,
    customerId: ground.customer.id,
    productId: ground.product.id,
    defectCodeId: ground.defectCode.id,
    quantity: 2,
    description: 'They rang the switchboard about it.',
    ...overrides
  });
  assert.strictEqual(recorded.status, 201, JSON.stringify(recorded.body));
  return recorded.body.complaint;
}

// `product_costs` and `cost_rates` are reference data with no write surface on
// this branch — nothing owns them yet — so the two figures the Cost KPIs are
// valued at are inserted here, the same way tier-board.test.js inserts its own
// `kpi_targets`. Without them the arithmetic would resolve to zero and the
// assertions below would be asserting nothing.
async function insertStandardCost(productId, standardCost, effectiveFrom) {
  await pool.query(
    `INSERT INTO product_costs (product_id, standard_cost, effective_from, note)
     VALUES ($1, $2, $3::date, 'KPI test standard cost')`,
    [productId, standardCost, effectiveFrom]
  );
}

async function insertLabourRate(orgUnitId, rateType, amount, effectiveFrom) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO cost_rates (scope_type, scope_id, rate_type, amount, effective_from, note)
     VALUES ('org_unit', $1, $2, $3, $4::date, 'KPI test rate') RETURNING id`,
    [orgUnitId, rateType, amount, effectiveFrom]
  );
  insertedCostRateIds.push(row.id);
}

// The production day the Site is in right now, resolved through the board's own
// period: a Site with no shift calendar falls back to its local calendar date.
async function currentProductionDay(siteId) {
  const { payload } = await getBoard(adminToken, siteId, '?periodType=day');
  return payload.period.start;
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
  // Children before parents, hardest descendant first, and the CAPA's link
  // before the CAPA itself: `action_items.capa_id` is a foreign key and
  // Postgres checks it on DELETE. A rejected `test.after` does not fail fast —
  // it hangs the file on the framework's timeout and cancels every file behind
  // it.
  await pool.query(
    `DELETE FROM customer_complaints
      WHERE org_unit_id IN (SELECT id FROM org_units WHERE site_id = ANY($1))`,
    [insertedSiteIds]
  );
  await pool.query('DELETE FROM action_items WHERE id = ANY($1)', [insertedActionIds]);
  if (insertedCapaIds.length > 0) {
    await pool.query('DELETE FROM capas WHERE id = ANY($1)', [insertedCapaIds]);
  }
  await pool.query(
    `DELETE FROM quality_issues
      WHERE org_unit_id IN (SELECT id FROM org_units WHERE site_id = ANY($1))`,
    [insertedSiteIds]
  );
  if (insertedCostRateIds.length > 0) {
    await pool.query('DELETE FROM cost_rates WHERE id = ANY($1)', [insertedCostRateIds]);
  }
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
// QUA_OPEN_NC
// ---------------------------------------------------------------------------

test('the board counts the open and contained, non-cancelled Non-conformances for the chosen Org Unit and everything beneath it', async () => {
  const ground = await makeGround();

  // One at the area itself, one at the line beneath it, one at the sibling
  // area's line, and two more at the line that are no longer open: one
  // dispositioned in full, one cancelled in error.
  await openNonconformance(ground, ground.area, { quantity: 3 });
  await openNonconformance(ground, ground.line, { quantity: 10 });
  await openNonconformance(ground, ground.otherLine, { quantity: 5 });

  const settled = await openNonconformance(ground, ground.line, { quantity: 4 });
  const closed = await recordDisposition(ground.engineer.token, settled.id, {
    dispositionType: 'scrap',
    quantity: 4
  });
  assert.strictEqual(closed.status, 201, JSON.stringify(closed.body));
  // Settling the whole quantity closes the record — the Non-conformance
  // slice's own rule, and one of the two states this KPI leaves out.
  assert.strictEqual(closed.body.nonconformance.status, 'closed');

  const mistaken = await openNonconformance(ground, ground.line, { quantity: 2 });
  const cancelled = await cancelNonconformance(
    ground.engineer.token,
    mistaken.id,
    'Recorded against the wrong lot number.'
  );
  assert.strictEqual(cancelled.status, 200, JSON.stringify(cancelled.body));

  // The area and everything beneath it: the area's own (3) and the line's (10).
  const areaBoard = await getBoard(
    ground.engineer.token,
    ground.site.id,
    `?periodType=day&orgUnitId=${ground.area.id}`
  );
  assert.strictEqual(readKpi(areaBoard.payload, 'Q', 'QUA_OPEN_NC').value, 2);

  // The line alone: its own one open record, never the sibling's or the area's.
  const lineBoard = await getBoard(
    ground.engineer.token,
    ground.site.id,
    `?periodType=day&orgUnitId=${ground.line.id}`
  );
  assert.strictEqual(readKpi(lineBoard.payload, 'Q', 'QUA_OPEN_NC').value, 1);

  // The whole Site: all three live records, sibling included.
  const siteBoard = await getBoard(ground.engineer.token, ground.site.id, '?periodType=day');
  assert.strictEqual(readKpi(siteBoard.payload, 'Q', 'QUA_OPEN_NC').value, 3);

  // A KPI with a value and no target is `no_target`: distinct from `no_data`,
  // which is what this same KPI reports for a period it cannot speak about.
  assert.strictEqual(readKpi(siteBoard.payload, 'Q', 'QUA_OPEN_NC').status, 'no_target');
});

test('a Site with nothing open reports a measured zero for the open Non-conformances', async () => {
  // Nothing recorded at all: a quiet plant's board says nought open, which is a
  // real answer rather than a missing one. A Site with no Org Unit at all would
  // have no row to carry it, which is why the ground has one.
  const site = await insertSite({ name: 'Quiet Site' });
  await insertOrgUnit(site.id, { name: 'Quiet Area' });

  const { payload } = await getBoard(adminToken, site.id, '?periodType=day');
  assert.strictEqual(readKpi(payload, 'Q', 'QUA_OPEN_NC').value, 0);
  assert.strictEqual(readKpi(payload, 'Q', 'QUA_OVERDUE_CAPA').value, 0);
});

test('a snapshot is reported for every period, because there is no "open Non-conformances for last Tuesday"', async () => {
  const ground = await makeGround();
  await openNonconformance(ground, ground.line, { quantity: 7 });

  const today = await currentProductionDay(ground.site.id);

  // The state is dated nowhere, so every period answers with it — the way
  // Maintenance's own snapshot KPI (`MNT_BACKLOG`) behaves, and the opposite of
  // what a period measure does with a period that holds nothing.
  for (const query of [
    `?periodType=day&date=${today}&orgUnitId=${ground.area.id}`,
    `?periodType=week&date=${today}&orgUnitId=${ground.area.id}`,
    `?periodType=month&date=2026-01-15&orgUnitId=${ground.area.id}`,
    `?periodType=day&date=2026-01-05&orgUnitId=${ground.area.id}`
  ]) {
    const { payload } = await getBoard(adminToken, ground.site.id, query);
    assert.strictEqual(
      readKpi(payload, 'Q', 'QUA_OPEN_NC').value,
      1,
      `${query} should report the state as it stands`
    );
  }

  // And the periods that hold nothing are still periods a period measure
  // answers `no_data` for: the two readings are not the same thing, which is
  // what makes the snapshot's behaviour a choice rather than an accident.
  const clean = await getBoard(
    adminToken,
    ground.site.id,
    `?periodType=day&date=${today}&orgUnitId=${ground.area.id}`
  );
  const complaints = readKpi(clean.payload, 'Q', 'QUA_COMPLAINTS');
  assert.strictEqual(complaints.value, null);
  assert.strictEqual(complaints.status, 'no_data');
});

// ---------------------------------------------------------------------------
// QUA_OVERDUE_CAPA
// ---------------------------------------------------------------------------

test('the board counts the CAPAs past their due date, or with an overdue effectiveness check, for the chosen Org Unit and beneath it', async () => {
  const ground = await makeGround();

  // One investigation overdue at the line beneath the area, one due in a
  // fortnight at the sibling line, and one at the area itself with no due date
  // at all — which is not the same thing as being late.
  await openInvestigation(ground, ground.line, { dueDate: '2020-06-01' });
  await openInvestigation(ground, ground.otherLine, { dueDate: '2099-01-01' });
  await openInvestigation(ground, ground.area, { dueDate: null });

  const areaBoard = await getBoard(
    adminToken,
    ground.site.id,
    `?periodType=day&orgUnitId=${ground.area.id}`
  );
  assert.strictEqual(readKpi(areaBoard.payload, 'Q', 'QUA_OVERDUE_CAPA').value, 1);

  // The whole Site, where the sibling's investigation is still not late.
  const siteBoard = await getBoard(adminToken, ground.site.id, '?periodType=day');
  assert.strictEqual(readKpi(siteBoard.payload, 'Q', 'QUA_OVERDUE_CAPA').value, 1);
});

test('a CAPA waiting on an effectiveness check that has fallen due is counted, and one that is closed is not', async () => {
  const ground = await makeGround();

  // Three investigations: one whose effectiveness check has fallen due, one
  // long past its own due date and still open, and one closed — which is not a
  // worklist whatever its dates say.
  const waiting = await openInvestigation(ground, ground.line, { dueDate: '2099-01-01' });
  await openInvestigation(ground, ground.area, { dueDate: '2020-06-01' });
  const finished = await openInvestigation(ground, ground.otherLine, { dueDate: '2020-06-01' });

  // Two states no route reaches in one statement: a CAPA waiting on its check
  // (a CAPA moves there when the Concern it answers is closed, which is a whole
  // closure to drive) and a closed one. Arranged directly, in this file's own
  // setup, the way `plant.test.js` arranges its own Accounts — the KPI's rule
  // is what is under test, and both rows began as API records.
  await pool.query(
    `UPDATE capas
        SET status = 'verifying', effectiveness_check_due_at = CURRENT_DATE - 1
      WHERE id = $1`,
    [waiting.id]
  );
  // A closed 8D has to carry its verification in the same statement
  // (`capas_eightd_needs_verification`), which is how the closure route writes
  // it too: one statement, every field the constraint names.
  await pool.query(
    `UPDATE capas
        SET status = 'closed', closed_at = now(),
            effectiveness_verified_at = now(),
            effectiveness_verified_by_account_id = $2,
            effectiveness_note = 'Verified on the line.'
      WHERE id = $1`,
    [finished.id, admin.id]
  );

  // The one whose check has fallen due, and the one past its own due date —
  // both inside the area and everything beneath it.
  const board = await getBoard(adminToken, ground.site.id, `?periodType=day&orgUnitId=${ground.area.id}`);
  assert.strictEqual(readKpi(board.payload, 'Q', 'QUA_OVERDUE_CAPA').value, 2);

  // The closed investigation is excluded even though it is just as late: the
  // whole Site sees the same two, never three.
  const siteBoard = await getBoard(adminToken, ground.site.id, '?periodType=day');
  assert.strictEqual(readKpi(siteBoard.payload, 'Q', 'QUA_OVERDUE_CAPA').value, 2);
});

// ---------------------------------------------------------------------------
// QUA_COMPLAINTS
// ---------------------------------------------------------------------------

test('the board counts the customer complaints received in the period for the chosen Org Unit and beneath it', async () => {
  const ground = await makeGround();

  await receiveComplaint(ground, ground.line);
  await receiveComplaint(ground, ground.area);
  await receiveComplaint(ground, ground.otherLine);

  const areaBoard = await getBoard(
    adminToken,
    ground.site.id,
    `?periodType=day&orgUnitId=${ground.area.id}`
  );
  assert.strictEqual(readKpi(areaBoard.payload, 'Q', 'QUA_COMPLAINTS').value, 2);

  const siteBoard = await getBoard(adminToken, ground.site.id, '?periodType=day');
  assert.strictEqual(readKpi(siteBoard.payload, 'Q', 'QUA_COMPLAINTS').value, 3);

  // The period's own boundaries: a complaint received ten days ago belongs to
  // that production day and to the month, not to today. `received_at` has no
  // field on the recording address — it is when the plant heard — so the day it
  // arrived on is moved by a statement of its own, the same licence the states
  // above take.
  const { rows: [received] } = await pool.query(
    `SELECT id FROM customer_complaints WHERE org_unit_id = $1 ORDER BY id LIMIT 1`,
    [ground.line.id]
  );
  await pool.query(
    `UPDATE customer_complaints SET received_at = now() - interval '10 days' WHERE id = $1`,
    [received.id]
  );

  const today = await currentProductionDay(ground.site.id);
  const todayBoard = await getBoard(
    adminToken,
    ground.site.id,
    `?periodType=day&orgUnitId=${ground.area.id}`
  );
  assert.strictEqual(readKpi(todayBoard.payload, 'Q', 'QUA_COMPLAINTS').value, 1);

  const earlier = await getBoard(
    adminToken,
    ground.site.id,
    `?periodType=day&date=${today}&orgUnitId=${ground.area.id}`
  );
  assert.strictEqual(readKpi(earlier.payload, 'Q', 'QUA_COMPLAINTS').value, 1);

  const month = await getBoard(
    adminToken,
    ground.site.id,
    `?periodType=month&date=${today}&orgUnitId=${ground.area.id}`
  );
  assert.strictEqual(
    readKpi(month.payload, 'Q', 'QUA_COMPLAINTS').value,
    2,
    'the whole month holds both complaints, whenever in it they arrived'
  );
});

test('a complaint rejected as unfounded is not counted, and a period with none reports no_data', async () => {
  const ground = await makeGround();

  await receiveComplaint(ground, ground.line);
  const rejected = await receiveComplaint(ground, ground.area);

  // Rejection is a decision with a reason and a closure, which is why the row
  // needs all three columns at once (`customer_complaints_closed_has_time` and
  // issue #214's own `customer_complaints_closed_has_response`). No route in
  // this slice rejects a complaint, so the state is arranged here.
  await pool.query(
    `UPDATE customer_complaints
        SET status = 'rejected', closed_at = now(), response_note = 'The parts were ours, not theirs.'
      WHERE id = $1`,
    [rejected.id]
  );

  const board = await getBoard(adminToken, ground.site.id, '?periodType=day');
  assert.strictEqual(readKpi(board.payload, 'Q', 'QUA_COMPLAINTS').value, 1);

  // A day with no complaint at all: `no_data`, the same answer every period
  // measure on this board gives for a period with no events.
  const quiet = await getBoard(adminToken, ground.site.id, '?periodType=day&date=2026-01-05');
  const quietKpi = readKpi(quiet.payload, 'Q', 'QUA_COMPLAINTS');
  assert.strictEqual(quietKpi.value, null);
  assert.strictEqual(quietKpi.status, 'no_data');
});

// ---------------------------------------------------------------------------
// The Cost pillar: the cost of poor quality
// ---------------------------------------------------------------------------

test('the Cost pillar reports the scrap and the rework of recorded Dispositions for the period, for the Org Unit and beneath it', async () => {
  const ground = await makeGround();
  await insertStandardCost(ground.product.id, 8.5, '2025-01-01');
  await insertLabourRate(ground.area.id, 'labor_per_hour', 32.0, '2025-01-01');

  // Ten units of bad product at the line: six scrapped at the standard cost in
  // force on the day it was found, four reworked at half an hour's labour.
  const record = await openNonconformance(ground, ground.line, { quantity: 10 });
  const scrap = await recordDisposition(ground.engineer.token, record.id, {
    dispositionType: 'scrap',
    quantity: 6
  });
  assert.strictEqual(scrap.status, 201, JSON.stringify(scrap.body));
  const rework = await recordDisposition(ground.engineer.token, record.id, {
    dispositionType: 'rework',
    quantity: 4,
    reworkMinutes: 30
  });
  assert.strictEqual(rework.status, 201, JSON.stringify(rework.body));

  // The sibling area's own scrap, which the narrowed board must leave out:
  // two units at the same standard cost.
  const sibling = await openNonconformance(ground, ground.otherLine, { quantity: 2 });
  const siblingScrap = await recordDisposition(ground.engineer.token, sibling.id, {
    dispositionType: 'scrap',
    quantity: 2
  });
  assert.strictEqual(siblingScrap.status, 201, JSON.stringify(siblingScrap.body));

  const areaBoard = await getBoard(
    adminToken,
    ground.site.id,
    `?periodType=month&orgUnitId=${ground.area.id}`
  );
  // 6 x 8.50 = 51.00 of scrap, and 30 minutes at 32.00/hour = 16.00 of rework
  // inside the cost of poor quality, which is the whole rather than a slice.
  assert.strictEqual(readKpi(areaBoard.payload, 'C', 'COST_SCRAP').value, 51);
  assert.strictEqual(readKpi(areaBoard.payload, 'C', 'COST_COPQ').value, 67);

  // The whole Site adds the sibling's 17.00 of scrap.
  const siteBoard = await getBoard(adminToken, ground.site.id, '?periodType=month');
  assert.strictEqual(readKpi(siteBoard.payload, 'C', 'COST_SCRAP').value, 68);
  assert.strictEqual(readKpi(siteBoard.payload, 'C', 'COST_COPQ').value, 84);

  // A period that finished before any of it: no rows, hence no number — the
  // same answer `MNT_COST` gives for a month with no work.
  const past = await getBoard(
    adminToken,
    ground.site.id,
    '?periodType=month&date=2026-01-15&orgUnitId=' + ground.area.id
  );
  const pastKpi = readKpi(past.payload, 'C', 'COST_SCRAP');
  assert.strictEqual(pastKpi.value, null);
  assert.strictEqual(pastKpi.status, 'no_data');
});

// ---------------------------------------------------------------------------
// The Cost pillar: a cost nobody can price is not a cost of zero (issue #258)
// ---------------------------------------------------------------------------

test('recorded scrap and rework with no standard cost and no labour rate report no_data, not zero, at every Org Unit in the subtree', async () => {
  // Deliberately no insertStandardCost and no insertLabourRate: this is the
  // state every Site is in today, since nothing in the Platform writes
  // `product_costs` or `cost_rates` (issue #252 is where that would come
  // from, and this ticket does not wait for it). The view's own
  // `COALESCE(..., 0)` would value all of the below at zero.
  const ground = await makeGround();

  const record = await openNonconformance(ground, ground.line, { quantity: 10 });
  const scrap = await recordDisposition(ground.engineer.token, record.id, {
    dispositionType: 'scrap',
    quantity: 6
  });
  assert.strictEqual(scrap.status, 201, JSON.stringify(scrap.body));
  const rework = await recordDisposition(ground.engineer.token, record.id, {
    dispositionType: 'rework',
    quantity: 4,
    reworkMinutes: 30
  });
  assert.strictEqual(rework.status, 201, JSON.stringify(rework.body));

  // The Org Unit the Dispositions were recorded at, the area above it, and the
  // whole Site: the answer is the same everywhere the rows roll up to.
  for (const query of [
    `?periodType=month&orgUnitId=${ground.line.id}`,
    `?periodType=month&orgUnitId=${ground.area.id}`,
    '?periodType=month'
  ]) {
    const { payload } = await getBoard(adminToken, ground.site.id, query);
    for (const code of ['COST_COPQ', 'COST_SCRAP']) {
      const kpi = readKpi(payload, 'C', code);
      assert.strictEqual(kpi.value, null, `${code} must not have a value for ${query}`);
      assert.notStrictEqual(kpi.value, 0, `${code} must never read as a measured zero`);
      assert.strictEqual(kpi.status, 'no_data', `${code} should be no_data for ${query}`);
    }
  }
});

test('a period with nothing to price is not a period that could not be priced', async () => {
  // The distinction issue #258 insists on. A complaint with no claim cost
  // recorded puts a row in the view whose every column is a real, measured
  // zero — nothing was scrapped, nothing was reworked, nothing was claimed —
  // and that zero is the answer it was before this ticket. Nothing here is
  // priced through a rate, so nothing here is blocked.
  const ground = await makeGround();
  await receiveComplaint(ground, ground.line);

  const { payload } = await getBoard(ground.engineer.token, ground.site.id, '?periodType=month');
  for (const code of ['COST_COPQ', 'COST_SCRAP']) {
    const kpi = readKpi(payload, 'C', code);
    assert.strictEqual(kpi.value, 0, `${code} should still read as a measured zero`);
    assert.notStrictEqual(kpi.status, 'no_data', `${code} is a measurement, not a blank`);
  }

  // And a period with no record of any kind is `no_data` from an absence of
  // rows, exactly as it was — never widened into the blocked state above.
  const quiet = await getBoard(
    ground.engineer.token,
    ground.site.id,
    '?periodType=month&date=2026-01-15'
  );
  for (const code of ['COST_COPQ', 'COST_SCRAP']) {
    const kpi = readKpi(quiet.payload, 'C', code);
    assert.strictEqual(kpi.value, null, `${code} has nothing to report`);
    assert.strictEqual(kpi.status, 'no_data', `${code} should be no_data`);
  }
});

test('a partially priced period reports no_data for the whole period rather than a confidently low figure', async () => {
  // The choice this ticket left to the registry, argued in
  // quality/kpi-registry.js's own header on ADR-0041's precedent: a cost
  // summed over only the rows that happened to price is always low and never
  // recognisable as wrong, so the whole period is `no_data`.
  const ground = await makeGround();
  const unpricedProduct = await createProduct(adminToken);
  await insertStandardCost(ground.product.id, 8.5, '2025-01-01');
  await insertLabourRate(ground.area.id, 'labor_per_hour', 32.0, '2025-01-01');

  // At the line: six units of a Product that has a standard cost, scrapped —
  // 51.00 that would resolve on its own — and two units of one that has none.
  const priced = await openNonconformance(ground, ground.line, { quantity: 6 });
  const pricedScrap = await recordDisposition(ground.engineer.token, priced.id, {
    dispositionType: 'scrap',
    quantity: 6
  });
  assert.strictEqual(pricedScrap.status, 201, JSON.stringify(pricedScrap.body));

  const unpriced = await openNonconformance(ground, ground.line, {
    quantity: 2,
    product: unpricedProduct
  });
  const unpricedScrap = await recordDisposition(ground.engineer.token, unpriced.id, {
    dispositionType: 'scrap',
    quantity: 2
  });
  assert.strictEqual(unpricedScrap.status, 201, JSON.stringify(unpricedScrap.body));

  const { payload } = await getBoard(
    adminToken,
    ground.site.id,
    `?periodType=month&orgUnitId=${ground.area.id}`
  );
  for (const code of ['COST_COPQ', 'COST_SCRAP']) {
    const kpi = readKpi(payload, 'C', code);
    assert.strictEqual(kpi.value, null, `${code} must not report the half it could price`);
    assert.notStrictEqual(kpi.value, 51, `${code} must never report the priced rows alone`);
    assert.strictEqual(kpi.status, 'no_data', `${code} should be no_data`);
  }

  // The block reaches exactly as far as the unpriced row does. The sibling
  // area, whose own scrap is on the priced Product, still reports its number.
  const sibling = await openNonconformance(ground, ground.otherLine, { quantity: 4 });
  const siblingScrap = await recordDisposition(ground.engineer.token, sibling.id, {
    dispositionType: 'scrap',
    quantity: 4
  });
  assert.strictEqual(siblingScrap.status, 201, JSON.stringify(siblingScrap.body));

  const siblingBoard = await getBoard(
    adminToken,
    ground.site.id,
    `?periodType=month&orgUnitId=${ground.otherArea.id}`
  );
  assert.strictEqual(readKpi(siblingBoard.payload, 'C', 'COST_SCRAP').value, 34);
  assert.strictEqual(readKpi(siblingBoard.payload, 'C', 'COST_COPQ').value, 34);
});

test('an unpriceable rework blocks the cost of poor quality without blocking the scrap cost it is no part of', async () => {
  // Each code is blocked only by what its own value is made of: `COST_SCRAP`
  // is the scrap slice, which no labour rate enters, while `COST_COPQ` is the
  // whole. The Site here has a standard cost and no labour rate of any kind.
  const ground = await makeGround();
  await insertStandardCost(ground.product.id, 8.5, '2025-01-01');

  const record = await openNonconformance(ground, ground.line, { quantity: 10 });
  const scrap = await recordDisposition(ground.engineer.token, record.id, {
    dispositionType: 'scrap',
    quantity: 6
  });
  assert.strictEqual(scrap.status, 201, JSON.stringify(scrap.body));
  const rework = await recordDisposition(ground.engineer.token, record.id, {
    dispositionType: 'rework',
    quantity: 4,
    reworkMinutes: 30
  });
  assert.strictEqual(rework.status, 201, JSON.stringify(rework.body));

  const { payload } = await getBoard(
    adminToken,
    ground.site.id,
    `?periodType=month&orgUnitId=${ground.area.id}`
  );

  // 6 x 8.50, a slice the Platform can price in full.
  assert.strictEqual(readKpi(payload, 'C', 'COST_SCRAP').value, 51);
  // The whole cannot be: half an hour of rework nobody has a rate for.
  const copq = readKpi(payload, 'C', 'COST_COPQ');
  assert.strictEqual(copq.value, null);
  assert.notStrictEqual(copq.value, 51, 'COST_COPQ must not silently drop the rework');
  assert.strictEqual(copq.status, 'no_data');
});

test('a rework of no minutes needs no labour rate, because there is nothing to price', async () => {
  // `0 minutes x whatever the rate turns out to be` is zero either way, so a
  // missing rate is not a missing price here — the rule
  // quality/kpi-registry.js's header states under "NOTHING RECORDED IS NOT THE
  // SAME AS NOTHING PRICEABLE".
  const ground = await makeGround();
  await insertStandardCost(ground.product.id, 8.5, '2025-01-01');

  const record = await openNonconformance(ground, ground.line, { quantity: 10 });
  const scrap = await recordDisposition(ground.engineer.token, record.id, {
    dispositionType: 'scrap',
    quantity: 6
  });
  assert.strictEqual(scrap.status, 201, JSON.stringify(scrap.body));
  const rework = await recordDisposition(ground.engineer.token, record.id, {
    dispositionType: 'rework',
    quantity: 4,
    reworkMinutes: 0
  });
  assert.strictEqual(rework.status, 201, JSON.stringify(rework.body));

  const { payload } = await getBoard(
    adminToken,
    ground.site.id,
    `?periodType=month&orgUnitId=${ground.area.id}`
  );
  assert.strictEqual(readKpi(payload, 'C', 'COST_SCRAP').value, 51);
  assert.strictEqual(readKpi(payload, 'C', 'COST_COPQ').value, 51);
});

// ---------------------------------------------------------------------------
// What stays no_data, and why
// ---------------------------------------------------------------------------

test('the KPIs that need quantity produced keep reporting no_data, on a Site that does have quality records', async () => {
  const ground = await makeGround();
  await openNonconformance(ground, ground.line, { quantity: 5 });
  await receiveComplaint(ground, ground.line);

  const { payload } = await getBoard(adminToken, ground.site.id, '?periodType=month');

  // All four are ratios against quantity produced, and no Production Module
  // writes a production count: a number here would be invented, so the board
  // keeps saying what it said before this slice.
  for (const [pillar, code] of [
    ['Q', 'QUA_FPY'],
    ['Q', 'QUA_INT_PPM'],
    ['Q', 'QUA_CUST_PPM'],
    ['D', 'DEL_QUALITY_RATE']
  ]) {
    const kpi = readKpi(payload, pillar, code);
    assert.strictEqual(kpi.value, null, `${code} must not have a value`);
    assert.notStrictEqual(kpi.value, 0, `${code} must never read as a measured zero`);
    assert.strictEqual(kpi.status, 'no_data', `${code} should be no_data`);
  }

  // And the Quality pillar is not empty on that board: the numbers this ticket
  // does claim are there beside them.
  assert.strictEqual(typeof readKpi(payload, 'Q', 'QUA_OPEN_NC').value, 'number');
  assert.strictEqual(typeof readKpi(payload, 'Q', 'QUA_COMPLAINTS').value, 'number');

  // The board's request and response shape is unchanged: the same query
  // parameters, the same five pillars, the same KPI fields.
  assert.deepStrictEqual(
    payload.pillars.map((pillar) => pillar.code),
    ['S', 'Q', 'D', 'C', 'P']
  );
  assert.deepStrictEqual(Object.keys(payload.pillars[1].kpis[0]).sort(), [
    'code',
    'decimalPlaces',
    'direction',
    'formulaText',
    'name',
    'status',
    'targetValue',
    'unit',
    'value'
  ]);
});
