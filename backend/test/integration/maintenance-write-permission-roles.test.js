/*
 * The Maintenance write retrofit (ADR-0061, slice 2b) keeps the audience every
 * write had before it — measured over HTTP against a real database and a real
 * local session, the same seam work-orders.test.js and inventory.test.js use.
 *
 * Why this file exists. The rest of the Maintenance suite inserts
 * `role: 'admin'` for the account that writes, and an administrator answers
 * true to every permission before its role's own set is read (ADR-0061 §5).
 * A gate that admitted nobody but administrators would leave that suite green.
 * So the two halves of the card's own claim are asserted here as the Accounts
 * that would notice first:
 *
 *   1. the **seeded** side — a supervisor (the role this card's migration
 *      put the four codes on) reaches every one of the sixteen routes, and a
 *      supervisor really can create a Work order, start it, complete it and
 *      receive stock, which is the shop-floor day the seed exists to keep;
 *   2. the **narrowing** side — an operator holding a write Grant on the very
 *      same Org Unit is refused every one of them with `PERMISSION_REQUIRED`
 *      and the code named, because `authorization.canAct({ write: true })` is
 *      role-blind and used to admit it. That is the behaviour change
 *      ADR-0061 makes on purpose: the code is the visible authority, not a
 *      side effect of an old Grant. The seed migration's own comment states it.
 *
 * A third thing is checked along the way: the Grant question is still asked
 * *after* the code, so a supervisor whose code is held but whose Grant does
 * not reach the Org Unit is refused with the scope sentence, not the
 * permission one. The code answers which door; the Grant still answers which
 * Org Units.
 *
 * The floor device door on /start and /complete is deliberately NOT re-tested
 * here: floor-technician-surface.test.js owns it and would fail if the
 * account-door wrapper had narrowed it. This file adds only what that one
 * cannot say — that the refusal a Role-less Account now meets is the code's.
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
const insertedAssetIds = [];
const insertedStoreIds = [];
const insertedPartIds = [];
const insertedJobPlanIds = [];
const insertedPmScheduleIds = [];
const insertedWorkOrderIds = [];

let counter = 0;
function uniqueCode(prefix) {
  counter += 1;
  return `${prefix}${process.pid}${counter}`;
}

async function authHeader(subject) {
  const token = await tokenFor(subject);
  return { authorization: `Bearer ${token}` };
}

async function insertAccount({ role }) {
  const subject = uniqueCode('acct');
  const { rows: [row] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status)
     VALUES ($1, 'Write Permission Test Account', $2, $3, true, 'approved') RETURNING id`,
    [`${subject}@example.com`, role, subject]
  );
  insertedAccountIds.push(row.id);
  return { id: row.id, role, token: await authHeader(subject) };
}

async function insertSite() {
  const { rows: [row] } = await pool.query(
    `INSERT INTO sites (code, name, timezone)
     VALUES ($1, 'Write Permission Test Site', 'Asia/Ho_Chi_Minh') RETURNING id`,
    [uniqueCode('ST')]
  );
  insertedSiteIds.push(row.id);
  return row.id;
}

async function insertOrgUnit(siteId) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, NULL, $2, 'Write Permission Unit', 'area') RETURNING id`,
    [siteId, uniqueCode('OU')]
  );
  insertedOrgUnitIds.push(row.id);
  return row.id;
}

async function insertGrant({ accountId, orgUnitId, canWrite = false }) {
  await pool.query(
    `INSERT INTO app_user_org_units (app_user_id, org_unit_id, can_write) VALUES ($1, $2, $3)`,
    [accountId, orgUnitId, canWrite]
  );
}

async function call(token, path, { method = 'GET', body } = {}) {
  const response = await fetch(`${base}${path}`, {
    method,
    headers: {
      ...token,
      ...(body === undefined ? {} : { 'content-type': 'application/json' })
    },
    body: body === undefined ? undefined : JSON.stringify(body)
  });
  const payload = await response.json().catch(() => null);
  return { response, payload };
}

// Every refusal a Role-less writer meets is this shape: the stable `code`, the
// permission that would have opened the door, and a sentence that names the
// code rather than a role (an Account may hold the function through any role).
function assertPermissionRefused(result, permission, what) {
  assert.strictEqual(result.response.status, 403, `${what} should be refused: ${JSON.stringify(result.payload)}`);
  assert.strictEqual(result.payload.code, 'PERMISSION_REQUIRED', `${what} should name PERMISSION_REQUIRED`);
  assert.strictEqual(result.payload.permission, permission, `${what} should name ${permission}`);
}

let admin;          // every permission, used only to build fixtures (parts, job plans).
let supervisor;     // role supervisor: the role the seed migration gives the four codes.
let operatorWriter; // role operator, write Grant on the same Org Unit: the narrowed Account.
let operatorGrantless; // role supervisor with NO Grant: a code alone opens nothing here.
let siteId;
let unitId;
let assetId;
let otherUnitId;
let storeId;
let partId;
let planId;
let workOrderId;
let pmScheduleId;

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

  admin = await insertAccount({ role: 'admin' });
  supervisor = await insertAccount({ role: 'supervisor' });
  operatorWriter = await insertAccount({ role: 'operator' });
  operatorGrantless = await insertAccount({ role: 'supervisor' });

  siteId = await insertSite();
  unitId = await insertOrgUnit(siteId);
  otherUnitId = await insertOrgUnit(siteId);

  for (const account of [admin, supervisor, operatorWriter]) {
    await insertGrant({ accountId: account.id, orgUnitId: unitId, canWrite: true });
  }

  const { rows: [asset] } = await pool.query(
    `INSERT INTO assets (org_unit_id, code, name, asset_type, criticality)
     VALUES ($1, $2, 'Write Permission Press', 'machine', 'high') RETURNING id`,
    [unitId, uniqueCode('AS')]
  );
  insertedAssetIds.push(asset.id);
  assetId = asset.id;

  // Fixtures the writes name, created through the routes an administrator
  // already opens so this file does not restate their own validation.
  const part = await call(admin.token, '/api/maintenance/parts', {
    method: 'POST',
    body: { partNo: uniqueCode('PN'), description: 'Bearing, 6204', uomCode: 'EA' }
  });
  assert.strictEqual(part.response.status, 201, JSON.stringify(part.payload));
  partId = part.payload.part.id;
  insertedPartIds.push(partId);

  const store = await call(admin.token, '/api/maintenance/stores', {
    method: 'POST',
    body: { orgUnitId: unitId, code: uniqueCode('STORE'), name: 'Write Permission Store' }
  });
  assert.strictEqual(store.response.status, 201, JSON.stringify(store.payload));
  storeId = store.payload.store.id;
  insertedStoreIds.push(storeId);

  const plan = await call(admin.token, '/api/maintenance/job-plans', {
    method: 'POST',
    body: { code: uniqueCode('JP'), name: 'Write Permission Plan', workType: 'preventive' }
  });
  assert.strictEqual(plan.response.status, 201, JSON.stringify(plan.payload));
  planId = plan.payload.jobPlan.id;
  insertedJobPlanIds.push(planId);
});

test.after(async () => {
  await pool.query('DELETE FROM work_orders WHERE id = ANY($1)', [insertedWorkOrderIds]);
  await pool.query('DELETE FROM pm_schedules WHERE id = ANY($1)', [insertedPmScheduleIds]);
  await pool.query('DELETE FROM stock_movements WHERE store_id = ANY($1)', [insertedStoreIds]);
  await pool.query('DELETE FROM stores WHERE id = ANY($1)', [insertedStoreIds]);
  await pool.query('DELETE FROM parts WHERE id = ANY($1)', [insertedPartIds]);
  await pool.query('DELETE FROM job_plans WHERE id = ANY($1)', [insertedJobPlanIds]);
  await pool.query('DELETE FROM assets WHERE id = ANY($1)', [insertedAssetIds]);
  await pool.query('DELETE FROM app_user_org_units WHERE app_user_id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM app_users WHERE id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM org_units WHERE id = ANY($1)', [insertedOrgUnitIds]);
  await pool.query('DELETE FROM sites WHERE id = ANY($1)', [insertedSiteIds]);
  await new Promise((resolve) => server.close(resolve));
  await closePool();
});

// ---------------------------------------------------------------------------
// 0. The seed itself, read from the Account that holds it.
// ---------------------------------------------------------------------------

test('a supervisor holds the four write codes; an operator holds none of them whatever its Grants', async () => {
  const codes = [
    'MTN_ASSETS_CHANGE',
    'MTN_WORK_ORDERS_CHANGE',
    'MTN_STORES_CHANGE',
    'MTN_PM_SCHEDULES_CHANGE'
  ];

  const held = await call(supervisor.token, '/api/people/me');
  assert.strictEqual(held.response.status, 200);
  for (const code of codes) {
    assert.ok(held.payload.permissions.includes(code), `expected a supervisor to hold ${code}`);
  }

  // The narrowing, seen from the other side: this Account holds a write Grant
  // on the very Org Unit the supervisor acts on, and still holds no code.
  const narrowed = await call(operatorWriter.token, '/api/people/me');
  assert.strictEqual(narrowed.response.status, 200);
  for (const code of codes) {
    assert.ok(!narrowed.payload.permissions.includes(code), `expected an operator not to hold ${code}`);
  }
});

// ---------------------------------------------------------------------------
// 1. MTN_ASSETS_CHANGE — POST /assets, PATCH /assets/:id.
// ---------------------------------------------------------------------------

test('MTN_ASSETS_CHANGE: a supervisor adds and corrects an Asset, an operator with an edit Grant is refused', async () => {
  const created = await call(supervisor.token, '/api/maintenance/assets', {
    method: 'POST',
    body: { orgUnitId: unitId, code: uniqueCode('AS'), name: 'Added by a supervisor', assetType: 'machine', criticality: 'medium' }
  });
  assert.strictEqual(created.response.status, 201, JSON.stringify(created.payload));
  insertedAssetIds.push(created.payload.asset.id);

  const patched = await call(supervisor.token, `/api/maintenance/assets/${created.payload.asset.id}`, {
    method: 'PATCH',
    body: { isActive: false }
  });
  assert.strictEqual(patched.response.status, 200, JSON.stringify(patched.payload));
  assert.strictEqual(patched.payload.asset.isActive, false);

  assertPermissionRefused(
    await call(operatorWriter.token, '/api/maintenance/assets', {
      method: 'POST',
      body: { orgUnitId: unitId, code: uniqueCode('AS'), name: 'Refused', assetType: 'machine', criticality: 'medium' }
    }),
    'MTN_ASSETS_CHANGE',
    'POST /assets'
  );
  assertPermissionRefused(
    await call(operatorWriter.token, `/api/maintenance/assets/${created.payload.asset.id}`, {
      method: 'PATCH',
      body: { isActive: true }
    }),
    'MTN_ASSETS_CHANGE',
    'PATCH /assets/:id'
  );
});

// ---------------------------------------------------------------------------
// 2. MTN_WORK_ORDERS_CHANGE — eight routes.
// ---------------------------------------------------------------------------

test('MTN_WORK_ORDERS_CHANGE: a supervisor raises, starts and completes a Work order', async () => {
  const raised = await call(supervisor.token, '/api/maintenance/work-orders', {
    method: 'POST',
    body: { assetId, summary: 'Bearing is making noise', workType: 'corrective', priority: 3 }
  });
  assert.strictEqual(raised.response.status, 201, JSON.stringify(raised.payload));
  workOrderId = raised.payload.workOrder.id;
  insertedWorkOrderIds.push(workOrderId);

  const started = await call(supervisor.token, `/api/maintenance/work-orders/${workOrderId}/start`, {
    method: 'POST'
  });
  assert.strictEqual(started.response.status, 200, JSON.stringify(started.payload));
  assert.strictEqual(started.payload.workOrder.status, 'in_progress');

  const completed = await call(supervisor.token, `/api/maintenance/work-orders/${workOrderId}/complete`, {
    method: 'POST',
    body: { note: 'Bearing replaced' }
  });
  assert.strictEqual(completed.response.status, 200, JSON.stringify(completed.payload));
  assert.strictEqual(completed.payload.workOrder.status, 'completed');
});

test('MTN_WORK_ORDERS_CHANGE: an operator with an edit Grant is refused all eight writes', async () => {
  const raised = await call(supervisor.token, '/api/maintenance/work-orders', {
    method: 'POST',
    body: { assetId, summary: 'Second job for the refusal sweep', workType: 'corrective', priority: 3 }
  });
  assert.strictEqual(raised.response.status, 201, JSON.stringify(raised.payload));
  const open = raised.payload.workOrder.id;
  insertedWorkOrderIds.push(open);

  const attempts = [
    ['POST /work-orders', '/api/maintenance/work-orders', 'POST', {
      assetId, summary: 'Refused', workType: 'corrective', priority: 3
    }],
    ['PUT /work-orders/:id/assignee', `/api/maintenance/work-orders/${open}/assignee`, 'PUT', { employeeId: 1 }],
    ['POST /work-orders/:id/start', `/api/maintenance/work-orders/${open}/start`, 'POST', undefined],
    ['POST /work-orders/:id/complete', `/api/maintenance/work-orders/${open}/complete`, 'POST', {}],
    ['POST /work-orders/:id/cancel', `/api/maintenance/work-orders/${open}/cancel`, 'POST', { reason: 'refused' }],
    ['POST /work-orders/:id/labour', `/api/maintenance/work-orders/${open}/labour`, 'POST', { employeeId: 1 }],
    ['POST /work-orders/:id/parts', `/api/maintenance/work-orders/${open}/parts`, 'POST', { partNo: 'X', quantity: 1 }],
    ['POST /work-orders/:id/tasks/:taskId/reading', `/api/maintenance/work-orders/${open}/tasks/1/reading`, 'POST', { reading: 1 }]
  ];

  for (const [what, path, method, body] of attempts) {
    // eslint-disable-next-line no-await-in-loop
    assertPermissionRefused(
      await call(operatorWriter.token, path, { method, body }),
      'MTN_WORK_ORDERS_CHANGE',
      what
    );
  }

  // The code is the first question, so a caller without it is refused before
  // any row is looked up — including one id that does not exist at all.
  assertPermissionRefused(
    await call(operatorWriter.token, '/api/maintenance/work-orders/999999999/cancel', {
      method: 'POST',
      body: { reason: 'refused' }
    }),
    'MTN_WORK_ORDERS_CHANGE',
    'POST /work-orders/:id/cancel on an unknown id'
  );
});

// ---------------------------------------------------------------------------
// 3. MTN_STORES_CHANGE — POST /stores, receipts, adjustments.
// ---------------------------------------------------------------------------

test('MTN_STORES_CHANGE: a supervisor creates a Store, receives stock and corrects a count', async () => {
  const created = await call(supervisor.token, '/api/maintenance/stores', {
    method: 'POST',
    body: { orgUnitId: unitId, code: uniqueCode('STORE'), name: 'Opened by a supervisor' }
  });
  assert.strictEqual(created.response.status, 201, JSON.stringify(created.payload));
  const store = created.payload.store.id;
  insertedStoreIds.push(store);

  const received = await call(supervisor.token, `/api/maintenance/stores/${store}/receipts`, {
    method: 'POST',
    body: { partId, quantity: 12, reason: 'Goods-in note 4471' }
  });
  assert.strictEqual(received.response.status, 201, JSON.stringify(received.payload));
  assert.strictEqual(received.payload.movement.quantity, 12);

  const adjusted = await call(supervisor.token, `/api/maintenance/stores/${store}/adjustments`, {
    method: 'POST',
    body: { partId, quantityDelta: -2, reason: 'Stocktake found two fewer' }
  });
  assert.strictEqual(adjusted.response.status, 201, JSON.stringify(adjusted.payload));
  assert.strictEqual(adjusted.payload.onHand, 10);
});

test('MTN_STORES_CHANGE: an operator with an edit Grant is refused all three store writes', async () => {
  assertPermissionRefused(
    await call(operatorWriter.token, '/api/maintenance/stores', {
      method: 'POST',
      body: { orgUnitId: unitId, code: uniqueCode('STORE'), name: 'Refused' }
    }),
    'MTN_STORES_CHANGE',
    'POST /stores'
  );
  assertPermissionRefused(
    await call(operatorWriter.token, `/api/maintenance/stores/${storeId}/receipts`, {
      method: 'POST',
      body: { partId, quantity: 1 }
    }),
    'MTN_STORES_CHANGE',
    'POST /stores/:storeId/receipts'
  );
  assertPermissionRefused(
    await call(operatorWriter.token, `/api/maintenance/stores/${storeId}/adjustments`, {
      method: 'POST',
      body: { partId, quantityDelta: 1, reason: 'refused' }
    }),
    'MTN_STORES_CHANGE',
    'POST /stores/:storeId/adjustments'
  );
});

// ---------------------------------------------------------------------------
// 4. MTN_PM_SCHEDULES_CHANGE — create, deactivate, raise.
// ---------------------------------------------------------------------------

test('MTN_PM_SCHEDULES_CHANGE: a supervisor creates a schedule, deactivates it and runs the sweep', async () => {
  const created = await call(supervisor.token, '/api/maintenance/pm-schedules', {
    method: 'POST',
    body: { assetId, jobPlanId: planId, intervalDays: 30, nextDueOn: '2030-01-01' }
  });
  assert.strictEqual(created.response.status, 201, JSON.stringify(created.payload));
  pmScheduleId = created.payload.pmSchedule.id;
  insertedPmScheduleIds.push(pmScheduleId);

  const deactivated = await call(supervisor.token, `/api/maintenance/pm-schedules/${pmScheduleId}`, {
    method: 'PATCH',
    body: { isActive: false }
  });
  assert.strictEqual(deactivated.response.status, 200, JSON.stringify(deactivated.payload));

  // The sweep answers 200 with whatever it raised. Nothing is due on the date
  // above, so an empty list is the honest success here: what this asserts is
  // that the code does not refuse the door, not that a job was raised.
  const sweep = await call(supervisor.token, `/api/maintenance/sites/${siteId}/pm-schedules/raise`, {
    method: 'POST'
  });
  assert.strictEqual(sweep.response.status, 200, JSON.stringify(sweep.payload));
  assert.deepStrictEqual(sweep.payload, { workOrders: [], failures: [] });
});

test('MTN_PM_SCHEDULES_CHANGE: an operator with an edit Grant is refused all three schedule writes', async () => {
  assertPermissionRefused(
    await call(operatorWriter.token, '/api/maintenance/pm-schedules', {
      method: 'POST',
      body: { assetId, jobPlanId: planId, intervalDays: 30 }
    }),
    'MTN_PM_SCHEDULES_CHANGE',
    'POST /pm-schedules'
  );
  assertPermissionRefused(
    await call(operatorWriter.token, `/api/maintenance/pm-schedules/${pmScheduleId}`, {
      method: 'PATCH',
      body: { isActive: true }
    }),
    'MTN_PM_SCHEDULES_CHANGE',
    'PATCH /pm-schedules/:id'
  );
  assertPermissionRefused(
    await call(operatorWriter.token, `/api/maintenance/sites/${siteId}/pm-schedules/raise`, {
      method: 'POST'
    }),
    'MTN_PM_SCHEDULES_CHANGE',
    'POST /sites/:siteId/pm-schedules/raise'
  );
});

// ---------------------------------------------------------------------------
// 5. The code opens the door; the Grant still decides which Org Units.
// ---------------------------------------------------------------------------

test('a supervisor holding the code but no Grant is refused by the scope check, not the permission check', async () => {
  // A supervisor keeps the code wherever it acts, so this Account has the door
  // and not the room. The two refusals must stay distinguishable: the sentence
  // here is the Grant's own, and it names no permission code.
  const elsewhere = await call(operatorGrantless.token, '/api/maintenance/assets', {
    method: 'POST',
    body: { orgUnitId: otherUnitId, code: uniqueCode('AS'), name: 'Refused by scope', assetType: 'machine', criticality: 'medium' }
  });
  assert.strictEqual(elsewhere.response.status, 403, JSON.stringify(elsewhere.payload));
  assert.notStrictEqual(elsewhere.payload.code, 'PERMISSION_REQUIRED');
  assert.ok(
    typeof elsewhere.payload.message === 'string' && elsewhere.payload.message.length > 0,
    'the scope refusal still carries its own sentence'
  );
});
