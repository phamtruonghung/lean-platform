/*
 * What a job cost over HTTP (issue #75): booking labour and parts against a
 * work order, against a real database and a real (locally issued) JWKS — the
 * same seam as work-orders.test.js and inventory.test.js, whose fixture
 * scaffolding this file mirrors.
 *
 * Every acceptance criterion in issue #75 has a named test below, and the
 * load-bearing one is the atomicity test: a `stores` booking writes the
 * `work_order_parts` line and the `stock_movements` withdrawal as one
 * transaction, so forcing the withdrawal to fail must leave no booking line
 * behind. The failure is provoked honestly by booking more than the shelf
 * holds, which is the stock trigger's own refusal (#80), not a stub.
 *
 * The schema's cost warning is asserted too: the detail read reports labour
 * HOURS and a parts COST separately, and never sums them into one total.
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
const insertedWorkOrderIds = [];
const insertedEmployeeIds = [];
const insertedPartIds = [];
const insertedStoreIds = [];

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
  const subject = uniqueCode('cost');
  const { rows: [row] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status)
     VALUES ($1, 'Work Order Cost Test', $2, $3, $4, $5) RETURNING id`,
    [`${subject}@example.com`, role, subject, isActive, approvalStatus]
  );
  insertedAccountIds.push(row.id);
  return { id: row.id, token: await authHeader(subject) };
}

async function insertSite() {
  const { rows: [row] } = await pool.query(
    `INSERT INTO sites (code, name, timezone)
     VALUES ($1, 'Work Order Cost Test Site', 'Asia/Ho_Chi_Minh') RETURNING id`,
    [uniqueCode('CS')]
  );
  insertedSiteIds.push(row.id);
  return row.id;
}

async function insertOrgUnit(siteId, { parentId = null, unitType = 'area', name = 'Cost Test Unit' } = {}) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, $2, $3, $4, $5) RETURNING id, code, name`,
    [siteId, parentId, uniqueCode('COU'), name, unitType]
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

async function insertAsset(orgUnitId, { name = 'Cost Test Press' } = {}) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO assets (org_unit_id, code, name, asset_type, criticality)
     VALUES ($1, $2, $3, 'machine', 'high') RETURNING id`,
    [orgUnitId, uniqueCode('CAS'), name]
  );
  insertedAssetIds.push(row.id);
  return row;
}

async function insertEmployee({ displayName = 'Cost Test Tech' } = {}) {
  const [firstName, ...rest] = displayName.split(' ');
  const lastName = rest.join(' ') || 'Employee';
  const { rows: [row] } = await pool.query(
    `INSERT INTO employees (employee_no, first_name, last_name, is_active)
     VALUES ($1, $2, $3, TRUE) RETURNING id, display_name`,
    [uniqueCode('CEMP'), firstName, lastName]
  );
  insertedEmployeeIds.push(row.id);
  return row;
}

async function insertPart({ uomCode = 'EA' } = {}) {
  const partNo = uniqueCode('CPN');
  const { rows: [row] } = await pool.query(
    `INSERT INTO parts (part_no, description, uom_code)
     VALUES ($1, 'Cost Test Bearing', $2) RETURNING id, part_no, description, uom_code`,
    [partNo, uomCode]
  );
  insertedPartIds.push(row.id);
  return row;
}

async function insertStore(siteId, orgUnitId) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO stores (site_id, org_unit_id, code, name)
     VALUES ($1, $2, $3, 'Cost Test Store') RETURNING id`,
    [siteId, orgUnitId, uniqueCode('CST')]
  );
  insertedStoreIds.push(row.id);
  return row;
}

async function postWorkOrder(token, body) {
  const response = await fetch(`${base}/api/maintenance/work-orders`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  const payload = await response.json().catch(() => null);
  if (payload?.workOrder?.id) insertedWorkOrderIds.push(payload.workOrder.id);
  return { response, payload };
}

async function raiseWorkOrder(orgUnitId, overrides = {}) {
  const asset = await insertAsset(orgUnitId);
  const { response, payload } = await postWorkOrder(admin.token, {
    assetId: asset.id,
    summary: 'Book cost against me',
    workType: 'corrective',
    priority: 3,
    ...overrides
  });
  assert.strictEqual(response.status, 201);
  return payload.workOrder;
}

async function postLabour(token, workOrderId, body) {
  const response = await fetch(`${base}/api/maintenance/work-orders/${workOrderId}/labour`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  return { response, payload: await response.json().catch(() => null) };
}

async function postPart(token, workOrderId, body) {
  const response = await fetch(`${base}/api/maintenance/work-orders/${workOrderId}/parts`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  return { response, payload: await response.json().catch(() => null) };
}

async function getWorkOrder(token, workOrderId) {
  const response = await fetch(`${base}/api/maintenance/work-orders/${workOrderId}`, {
    headers: token
  });
  return { response, payload: await response.json().catch(() => null) };
}

async function receive(token, storeId, body) {
  const response = await fetch(`${base}/api/maintenance/stores/${storeId}/receipts`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  return { response, payload: await response.json().catch(() => null) };
}

async function stockOnHand(storeId) {
  const { rows: [row] } = await pool.query(
    `SELECT COALESCE(SUM(quantity), 0) AS on_hand FROM stock_movements WHERE store_id = $1`,
    [storeId]
  );
  return Number(row.on_hand);
}

let admin;
let noGrantAccount;
let readOnlyAccount;
let writerAccount;

let site;
let grantedArea;
let grantedLine;

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
  noGrantAccount = await insertAccount();
  readOnlyAccount = await insertAccount();
  writerAccount = await insertAccount();

  site = await insertSite();
  grantedArea = await insertOrgUnit(site, { name: 'Granted Area' });
  grantedLine = await insertOrgUnit(site, { parentId: grantedArea.id, unitType: 'line', name: 'Line 1' });

  await insertGrant({ accountId: readOnlyAccount.id, orgUnitId: grantedLine.id, canWrite: false });
  await insertGrant({ accountId: writerAccount.id, orgUnitId: grantedLine.id, canWrite: true });
});

test.after(async () => {
  await pool.query('DELETE FROM work_orders WHERE id = ANY($1)', [insertedWorkOrderIds]);
  await pool.query('DELETE FROM stock_movements WHERE store_id = ANY($1)', [insertedStoreIds]);
  await pool.query('DELETE FROM stores WHERE id = ANY($1)', [insertedStoreIds]);
  await pool.query('DELETE FROM parts WHERE id = ANY($1)', [insertedPartIds]);
  await pool.query('DELETE FROM employees WHERE id = ANY($1)', [insertedEmployeeIds]);
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
// Labour: the window is the only input, and the hours follow from it.
// ---------------------------------------------------------------------------

test('booking labour returns its hours derived from the window', async () => {
  const workOrder = await raiseWorkOrder(grantedLine.id);
  const employee = await insertEmployee();

  const { response, payload } = await postLabour(admin.token, workOrder.id, {
    employeeId: employee.id,
    startedAt: '2026-02-01T08:00:00.000Z',
    endedAt: '2026-02-01T10:30:00.000Z',
    activity: 'work'
  });

  assert.strictEqual(response.status, 201);
  assert.strictEqual(payload.labour.hours, 2.5);
  assert.strictEqual(payload.labour.activity, 'work');
  assert.strictEqual(payload.labour.isOvertime, false);
  assert.strictEqual(String(payload.labour.employeeId), String(employee.id));
  // The window is echoed back, so the hours can be checked against it.
  assert.strictEqual(payload.labour.startedAt, '2026-02-01T08:00:00.000Z');
  assert.strictEqual(payload.labour.endedAt, '2026-02-01T10:30:00.000Z');
});

test('a client-sent hours figure is ignored, because the column is generated', async () => {
  const workOrder = await raiseWorkOrder(grantedLine.id);
  const employee = await insertEmployee();

  const { response, payload } = await postLabour(admin.token, workOrder.id, {
    employeeId: employee.id,
    startedAt: '2026-02-02T08:00:00.000Z',
    endedAt: '2026-02-02T09:00:00.000Z',
    activity: 'work',
    hours: 99
  });

  assert.strictEqual(response.status, 201);
  assert.strictEqual(payload.labour.hours, 1);

  const { rows: [row] } = await pool.query(
    'SELECT hours FROM work_order_labour WHERE id = $1',
    [payload.labour.id]
  );
  assert.strictEqual(Number(row.hours), 1);
});

test('every activity is offered, and an unknown one is refused', async () => {
  const workOrder = await raiseWorkOrder(grantedLine.id);
  const activities = ['work', 'travel', 'waiting', 'diagnosis', 'documentation'];
  for (const [index, activity] of activities.entries()) {
    const employee = await insertEmployee();
    const day = String(index + 1).padStart(2, '0');
    const { response } = await postLabour(admin.token, workOrder.id, {
      employeeId: employee.id,
      startedAt: `2026-03-${day}T08:00:00.000Z`,
      endedAt: `2026-03-${day}T09:00:00.000Z`,
      activity
    });
    assert.strictEqual(response.status, 201, `${activity} should be accepted`);
  }

  const employee = await insertEmployee();
  const { response, payload } = await postLabour(admin.token, workOrder.id, {
    employeeId: employee.id,
    startedAt: '2026-04-01T08:00:00.000Z',
    endedAt: '2026-04-01T09:00:00.000Z',
    activity: 'smoko'
  });
  assert.strictEqual(response.status, 400);
  assert.match(payload.message, /activity must be one of/);
});

test('overtime is recorded distinguishably from ordinary hours', async () => {
  const workOrder = await raiseWorkOrder(grantedLine.id);
  const ordinary = await insertEmployee({ displayName: 'Ordinary Tech' });
  const overtime = await insertEmployee({ displayName: 'Overtime Tech' });

  assert.strictEqual(
    (
      await postLabour(admin.token, workOrder.id, {
        employeeId: ordinary.id,
        startedAt: '2026-05-01T08:00:00.000Z',
        endedAt: '2026-05-01T10:00:00.000Z',
        activity: 'work',
        isOvertime: false
      })
    ).response.status,
    201
  );
  const booked = await postLabour(admin.token, workOrder.id, {
    employeeId: overtime.id,
    startedAt: '2026-05-02T08:00:00.000Z',
    endedAt: '2026-05-02T09:00:00.000Z',
    activity: 'work',
    isOvertime: true
  });
  assert.strictEqual(booked.response.status, 201);
  assert.strictEqual(booked.payload.labour.isOvertime, true);

  const { payload } = await getWorkOrder(admin.token, workOrder.id);
  const work = payload.workOrder.cost.labourByActivity.find((row) => row.activity === 'work');
  assert.strictEqual(work.hours, 3);
  assert.strictEqual(work.overtimeHours, 1);
  assert.strictEqual(payload.workOrder.cost.overtimeHours, 1);
});

// ---------------------------------------------------------------------------
// Parts: `sourced` decides whether stock moves.
// ---------------------------------------------------------------------------

test('a part from stores decrements the store it came from', async () => {
  const workOrder = await raiseWorkOrder(grantedLine.id);
  const part = await insertPart();
  const store = await insertStore(site, grantedLine.id);
  await receive(admin.token, store.id, { partId: part.id, quantity: 10 });
  assert.strictEqual(await stockOnHand(store.id), 10);

  const { response, payload } = await postPart(admin.token, workOrder.id, {
    sourced: 'stores',
    partId: part.id,
    storeId: store.id,
    quantity: 3,
    unitCost: 12.5
  });

  assert.strictEqual(response.status, 201);
  assert.strictEqual(payload.part.partNo, part.part_no);
  assert.strictEqual(payload.part.quantity, 3);
  assert.strictEqual(payload.part.totalCost, 37.5);
  assert.strictEqual(await stockOnHand(store.id), 7);

  const { rows: [movement] } = await pool.query(
    `SELECT quantity, movement_type, reason FROM stock_movements
      WHERE store_id = $1 AND part_id = $2 AND quantity < 0`,
    [store.id, part.id]
  );
  assert.strictEqual(Number(movement.quantity), -3);
  assert.strictEqual(movement.movement_type, 'adjustment');
  assert.match(movement.reason, /Work order/);
});

test('a purchased part leaves stock untouched', async () => {
  const workOrder = await raiseWorkOrder(grantedLine.id);
  const part = await insertPart();
  const store = await insertStore(site, grantedLine.id);
  await receive(admin.token, store.id, { partId: part.id, quantity: 10 });

  const { response, payload } = await postPart(admin.token, workOrder.id, {
    sourced: 'purchased',
    partNo: 'BOUGHT-1',
    description: 'Bought for this job',
    quantity: 2,
    uomCode: 'EA',
    unitCost: 40
  });

  assert.strictEqual(response.status, 201);
  assert.strictEqual(payload.part.partNo, 'BOUGHT-1');
  assert.strictEqual(payload.part.sourced, 'purchased');
  assert.strictEqual(await stockOnHand(store.id), 10);

  const { rows } = await pool.query(
    `SELECT COUNT(*)::int AS movements FROM stock_movements WHERE store_id = $1 AND quantity < 0`,
    [store.id]
  );
  assert.strictEqual(rows[0].movements, 0);
});

test('a refurbished part with no part number is accepted, because part_no is free text', async () => {
  const workOrder = await raiseWorkOrder(grantedLine.id);
  const { response, payload } = await postPart(admin.token, workOrder.id, {
    sourced: 'refurbished',
    description: 'Reconditioned pump',
    quantity: 1,
    uomCode: 'EA'
  });
  assert.strictEqual(response.status, 201);
  assert.strictEqual(payload.part.partNo, null);
});

// ---------------------------------------------------------------------------
// The atomic booking: a refusal leaves neither row behind.
// ---------------------------------------------------------------------------

test('booking more than the shelf holds is refused, naming the part, and leaves no booking line', async () => {
  const workOrder = await raiseWorkOrder(grantedLine.id);
  const part = await insertPart();
  const store = await insertStore(site, grantedLine.id);
  await receive(admin.token, store.id, { partId: part.id, quantity: 2 });

  const { response, payload } = await postPart(admin.token, workOrder.id, {
    sourced: 'stores',
    partId: part.id,
    storeId: store.id,
    quantity: 5
  });

  assert.strictEqual(response.status, 409);
  assert.match(payload.message, new RegExp(`Part ${part.part_no} has only 2 EA`));
  assert.match(payload.message, /below zero/);

  // The failure aborted the whole transaction: the booking line is gone.
  const { rows: [booked] } = await pool.query(
    'SELECT COUNT(*)::int AS n FROM work_order_parts WHERE work_order_id = $1',
    [workOrder.id]
  );
  assert.strictEqual(booked.n, 0);
  assert.strictEqual(await stockOnHand(store.id), 2);
});

// ---------------------------------------------------------------------------
// The detail read: labour hours and parts cost, never summed.
// ---------------------------------------------------------------------------

test('a work order shows its hours by activity and its parts with their total', async () => {
  const workOrder = await raiseWorkOrder(grantedLine.id);
  const tech = await insertEmployee();
  await postLabour(admin.token, workOrder.id, {
    employeeId: tech.id,
    startedAt: '2026-06-01T08:00:00.000Z',
    endedAt: '2026-06-01T10:00:00.000Z',
    activity: 'diagnosis'
  });
  await postPart(admin.token, workOrder.id, {
    sourced: 'purchased',
    description: 'Seal kit',
    quantity: 4,
    uomCode: 'EA',
    unitCost: 25
  });

  const { response, payload } = await getWorkOrder(admin.token, workOrder.id);
  assert.strictEqual(response.status, 200);
  const cost = payload.workOrder.cost;

  assert.strictEqual(cost.labourHours, 2);
  assert.strictEqual(cost.labourByActivity.length, 1);
  assert.strictEqual(cost.labourByActivity[0].activity, 'diagnosis');
  assert.strictEqual(cost.labourByActivity[0].hours, 2);
  assert.strictEqual(cost.parts.length, 1);
  assert.strictEqual(cost.parts[0].totalCost, 100);
  assert.strictEqual(cost.partsCost, 100);
  // The two are separate facts, and no combined "total cost" is reported:
  // labour here is a slice of COST_LABOUR, not new money, so adding it to
  // the parts total would double-count the technician.
  assert.strictEqual(Object.prototype.hasOwnProperty.call(cost, 'totalCost'), false);
});

// ---------------------------------------------------------------------------
// Scope: a write Grant reaching the Org Unit the work order's Asset sits at.
// ---------------------------------------------------------------------------

test('a caller with no write Grant reaching the Asset is refused the booking', async () => {
  const workOrder = await raiseWorkOrder(grantedLine.id);
  const employee = await insertEmployee();

  const noGrant = await postLabour(noGrantAccount.token, workOrder.id, {
    employeeId: employee.id,
    startedAt: '2026-07-01T08:00:00.000Z',
    endedAt: '2026-07-01T09:00:00.000Z',
    activity: 'work'
  });
  assert.strictEqual(noGrant.response.status, 403);
  assert.strictEqual(noGrant.payload.message, "Outside the caller's granted Org Units");

  const readOnly = await postPart(readOnlyAccount.token, workOrder.id, {
    sourced: 'purchased',
    description: 'Sealed bearing',
    quantity: 1,
    uomCode: 'EA'
  });
  assert.strictEqual(readOnly.response.status, 403);
  assert.strictEqual(readOnly.payload.message, "Outside the caller's granted Org Units");

  const { rows: [counts] } = await pool.query(
    `SELECT
       (SELECT COUNT(*)::int FROM work_order_labour WHERE work_order_id = $1) AS labour,
       (SELECT COUNT(*)::int FROM work_order_parts WHERE work_order_id = $1) AS parts`,
    [workOrder.id]
  );
  assert.strictEqual(counts.labour, 0);
  assert.strictEqual(counts.parts, 0);
});

test('a caller whose write Grant reaches the Asset may book, and an unknown Work order is a 404', async () => {
  const workOrder = await raiseWorkOrder(grantedLine.id);
  const employee = await insertEmployee();

  const allowed = await postLabour(writerAccount.token, workOrder.id, {
    employeeId: employee.id,
    startedAt: '2026-07-02T08:00:00.000Z',
    endedAt: '2026-07-02T09:00:00.000Z',
    activity: 'work'
  });
  assert.strictEqual(allowed.response.status, 201);

  const unknown = await postLabour(admin.token, '999999999', {
    employeeId: employee.id,
    startedAt: '2026-07-03T08:00:00.000Z',
    endedAt: '2026-07-03T09:00:00.000Z',
    activity: 'work'
  });
  assert.strictEqual(unknown.response.status, 404);
  assert.strictEqual(unknown.payload.message, 'Work order not found');
});
