/*
 * Maintenance review fixes, over HTTP against a real database: a task's meter
 * reading refuses a closed Work order, the PM sweep reports a failed raise
 * beside the raised ones instead of a 500, the three unbounded lists say
 * `truncated` (ADR-0026), and a desktop start or complete records the
 * signed-in Account's Employee. Fixtures are inserted directly, as the sibling
 * maintenance files do.
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

const accountIds = [];
const employeeIds = [];
const siteIds = [];
const orgUnitIds = [];
const assetIds = [];
const storeIds = [];
const partIds = [];
const jobPlanIds = [];
const pmScheduleIds = [];
const triggerNames = [];

let counter = 0;
function uniqueCode(prefix) {
  counter += 1;
  return `${prefix}${process.pid}${counter}`;
}

async function authHeader(subject) {
  const token = await jwks.signToken(
    { sub: subject, email: `${subject}@example.com` },
    { issuer: ISSUER, audience: AUDIENCE }
  );
  return { authorization: `Bearer ${token}` };
}

async function insertEmployee() {
  const { rows: [row] } = await pool.query(
    `INSERT INTO employees (employee_no, first_name, last_name, is_active)
     VALUES ($1, 'Ann', 'Fitter', TRUE) RETURNING id`,
    [uniqueCode('EMP')]
  );
  employeeIds.push(row.id);
  return row;
}

async function insertAccount({ role = 'supervisor', employeeId = null } = {}) {
  const subject = uniqueCode('acct');
  const { rows: [row] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status, employee_id)
     VALUES ($1, 'Review Fix Account', $2, $3, TRUE, 'approved', $4) RETURNING id`,
    [`${subject}@example.com`, role, subject, employeeId]
  );
  accountIds.push(row.id);
  return { id: row.id, token: await authHeader(subject) };
}

async function insertAsset(orgUnitId, name = 'Review Asset') {
  const { rows: [asset] } = await pool.query(
    `INSERT INTO assets (org_unit_id, code, name, asset_type, criticality)
     VALUES ($1, $2, $3, 'machine', 'high') RETURNING id, org_unit_id`,
    [orgUnitId, uniqueCode('AS'), name]
  );
  assetIds.push(asset.id);
  return asset;
}

async function insertSiteUnitAsset(name = 'Review Asset') {
  const { rows: [site] } = await pool.query(
    `INSERT INTO sites (code, name, timezone) VALUES ($1, 'Review Site', 'Asia/Ho_Chi_Minh') RETURNING id, code`,
    [uniqueCode('ST')]
  );
  siteIds.push(site.id);
  const { rows: [unit] } = await pool.query(
    `INSERT INTO org_units (site_id, code, name, unit_type) VALUES ($1, $2, 'Review Area', 'area') RETURNING id`,
    [site.id, uniqueCode('OU')]
  );
  orgUnitIds.push(unit.id);
  const asset = await insertAsset(unit.id, name);
  return { site, unit, asset };
}

async function api(method, path, token, body) {
  const response = await fetch(`${base}/api/maintenance${path}`, {
    method,
    headers: { ...token, ...(body ? { 'content-type': 'application/json' } : {}) },
    body: body ? JSON.stringify(body) : undefined
  });
  return { response, payload: await response.json().catch(() => null) };
}

async function raiseWorkOrder(token, assetId, summary = 'Review job') {
  const { response, payload } = await api('POST', '/work-orders', token, {
    assetId,
    summary,
    workType: 'inspection',
    priority: 3
  });
  assert.strictEqual(response.status, 201, JSON.stringify(payload));
  return payload.workOrder;
}

async function dbDate(offsetDays) {
  const { rows: [row] } = await pool.query(
    `SELECT to_char(CURRENT_DATE + $1::int, 'YYYY-MM-DD') AS d`,
    [offsetDays]
  );
  return row.d;
}

let admin;

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
});

test.after(async () => {
  for (const name of triggerNames) {
    await pool.query(`DROP TRIGGER IF EXISTS ${name} ON work_orders`);
    await pool.query(`DROP FUNCTION IF EXISTS ${name}()`);
  }
  await pool.query('DELETE FROM work_orders WHERE asset_id = ANY($1)', [assetIds]);
  await pool.query('DELETE FROM pm_schedules WHERE id = ANY($1)', [pmScheduleIds]);
  await pool.query('DELETE FROM job_plans WHERE id = ANY($1)', [jobPlanIds]);
  await pool.query(
    `DELETE FROM meter_readings WHERE asset_meter_id IN (SELECT id FROM asset_meters WHERE asset_id = ANY($1))`,
    [assetIds]
  );
  await pool.query('DELETE FROM asset_meters WHERE asset_id = ANY($1)', [assetIds]);
  await pool.query('DELETE FROM downtime_events WHERE asset_id = ANY($1)', [assetIds]);
  await pool.query('DELETE FROM stock_movements WHERE store_id = ANY($1)', [storeIds]);
  await pool.query('DELETE FROM stores WHERE id = ANY($1)', [storeIds]);
  await pool.query('DELETE FROM parts WHERE id = ANY($1)', [partIds]);
  await pool.query('DELETE FROM assets WHERE id = ANY($1)', [assetIds]);
  await pool.query('DELETE FROM app_user_org_units WHERE app_user_id = ANY($1)', [accountIds]);
  await pool.query('DELETE FROM app_users WHERE id = ANY($1)', [accountIds]);
  await pool.query('DELETE FROM employees WHERE id = ANY($1)', [employeeIds]);
  await pool.query('DELETE FROM org_units WHERE id = ANY($1)', [orgUnitIds]);
  await pool.query('DELETE FROM sites WHERE id = ANY($1)', [siteIds]);
  await new Promise((resolve) => server.close(resolve));
  await closePool();
  await jwks.close();
});

// ---------------------------------------------------------------------------
// Finding 9: a task reading needs a live Work order, and is one transaction.
// ---------------------------------------------------------------------------

async function meterWorkOrder() {
  const { asset } = await insertSiteUnitAsset('Reading Press');
  const created = await api('POST', '/meters', admin.token, {
    assetId: asset.id,
    code: 'VIB',
    name: 'Vibration',
    uomCode: 'EA',
    meterType: 'gauge'
  });
  assert.strictEqual(created.response.status, 201, JSON.stringify(created.payload));
  const meter = created.payload.meter;
  const workOrder = await raiseWorkOrder(admin.token, asset.id);
  const { rows: [task] } = await pool.query(
    `INSERT INTO work_order_tasks (work_order_id, step_no, instruction, asset_meter_id)
     VALUES ($1, 1, 'Record vibration', $2) RETURNING id`,
    [workOrder.id, meter.id]
  );
  return { asset, meter, workOrder, task };
}

async function readingCount(meterId) {
  const { rows: [row] } = await pool.query(
    'SELECT count(*)::int AS n FROM meter_readings WHERE asset_meter_id = $1',
    [meterId]
  );
  return row.n;
}

test('a task reading is refused with 409 once the Work order is completed, and nothing is written', async () => {
  const { meter, workOrder, task } = await meterWorkOrder();
  const path = `/work-orders/${workOrder.id}/tasks/${task.id}/reading`;

  const approved = await api('POST', path, admin.token, { reading: 3 });
  assert.strictEqual(approved.response.status, 201, JSON.stringify(approved.payload));
  assert.strictEqual(approved.payload.task.reading, 3);

  assert.strictEqual((await api('POST', `/work-orders/${workOrder.id}/start`, admin.token)).response.status, 200);
  const live = await api('POST', path, admin.token, { reading: 4 });
  assert.strictEqual(live.response.status, 201, 'an in-progress Work order still takes a reading');

  const done = await api('POST', `/work-orders/${workOrder.id}/complete`, admin.token, { note: 'Done' });
  assert.strictEqual(done.response.status, 200, JSON.stringify(done.payload));

  const before = await readingCount(meter.id);
  const refused = await api('POST', path, admin.token, { reading: 5 });
  assert.strictEqual(refused.response.status, 409, JSON.stringify(refused.payload));
  assert.match(refused.payload.message, /completed/);
  assert.strictEqual(await readingCount(meter.id), before, 'a refused reading writes no meter reading');
});

test('a task reading is refused with 409 on a cancelled Work order', async () => {
  const { workOrder, task } = await meterWorkOrder();
  const cancelled = await api('POST', `/work-orders/${workOrder.id}/cancel`, admin.token, { reason: 'Raised in error' });
  assert.strictEqual(cancelled.response.status, 200, JSON.stringify(cancelled.payload));
  const refused = await api('POST', `/work-orders/${workOrder.id}/tasks/${task.id}/reading`, admin.token, { reading: 1 });
  assert.strictEqual(refused.response.status, 409);
});

test('a task reading and its stamp commit together: a failed stamp leaves no meter reading', async () => {
  const { meter, workOrder, task } = await meterWorkOrder();
  // Make the task stamp fail after the meter reading has been inserted.
  const name = uniqueCode('tf_task').toLowerCase();
  await pool.query(`
    CREATE FUNCTION ${name}() RETURNS trigger AS $$
    BEGIN RAISE EXCEPTION 'stamp refused'; END $$ LANGUAGE plpgsql`);
  await pool.query(
    `CREATE TRIGGER ${name} BEFORE UPDATE ON work_order_tasks FOR EACH ROW
       WHEN (NEW.id = ${Number(task.id)}) EXECUTE FUNCTION ${name}()`
  );
  try {
    const before = await readingCount(meter.id);
    const result = await api('POST', `/work-orders/${workOrder.id}/tasks/${task.id}/reading`, admin.token, { reading: 2 });
    assert.ok(result.response.status >= 400);
    assert.strictEqual(await readingCount(meter.id), before);
  } finally {
    await pool.query(`DROP TRIGGER ${name} ON work_order_tasks`);
    await pool.query(`DROP FUNCTION ${name}()`);
  }
});

// ---------------------------------------------------------------------------
// Finding 10: the PM sweep reports a failed raise beside the raised ones.
// ---------------------------------------------------------------------------

async function insertPlan() {
  const { rows: [plan] } = await pool.query(
    `INSERT INTO job_plans (code, name, work_type) VALUES ($1, 'Sweep plan', 'preventive') RETURNING id`,
    [uniqueCode('JP')]
  );
  jobPlanIds.push(plan.id);
  return plan;
}

async function createDueSchedule(assetId, planId) {
  const created = await api('POST', '/pm-schedules', admin.token, {
    assetId,
    jobPlanId: planId,
    intervalDays: 30,
    nextDueOn: await dbDate(-2)
  });
  assert.strictEqual(created.response.status, 201, JSON.stringify(created.payload));
  pmScheduleIds.push(created.payload.pmSchedule.id);
  return created.payload.pmSchedule.id;
}

test('the PM sweep reports a schedule that failed to raise, beside the ones that did', async () => {
  const { site, unit, asset: assetA } = await insertSiteUnitAsset('Sweep A');
  const assetB = await insertAsset(unit.id, 'Sweep B');
  const plan = await insertPlan();
  const scheduleA = await createDueSchedule(assetA.id, plan.id);
  const scheduleB = await createDueSchedule(assetB.id, plan.id);

  // The second Asset's Work order insert blows up, as a bug or a deadlock would.
  const name = uniqueCode('tf_sweep').toLowerCase();
  triggerNames.push(name);
  await pool.query(`
    CREATE FUNCTION ${name}() RETURNS trigger AS $$
    BEGIN
      IF NEW.asset_id = ${Number(assetB.id)} THEN RAISE EXCEPTION 'boom'; END IF;
      RETURN NEW;
    END $$ LANGUAGE plpgsql`);
  await pool.query(`CREATE TRIGGER ${name} BEFORE INSERT ON work_orders FOR EACH ROW EXECUTE FUNCTION ${name}()`);

  const { response, payload } = await api('POST', `/sites/${site.id}/pm-schedules/raise`, admin.token);
  assert.strictEqual(response.status, 200, JSON.stringify(payload));
  assert.deepStrictEqual(payload.workOrders.map((wo) => wo.pmScheduleId), [scheduleA]);
  assert.strictEqual(payload.failures.length, 1);
  assert.strictEqual(payload.failures[0].pmScheduleId, String(scheduleB));
  assert.ok(payload.failures[0].message);
  assert.doesNotMatch(payload.failures[0].message, /boom/, 'a raw database message is never echoed');
});

test('the PM sweep skips, without failing, schedules outside the caller\'s Grants', async () => {
  const { site, asset } = await insertSiteUnitAsset('Sweep scope');
  const plan = await insertPlan();
  await createDueSchedule(asset.id, plan.id);

  const stranger = await insertAccount();
  const { response, payload } = await api('POST', `/sites/${site.id}/pm-schedules/raise`, stranger.token);
  assert.strictEqual(response.status, 200);
  assert.deepStrictEqual(payload, { workOrders: [], failures: [] });
});

test('the PM sweep raises the schedules a write Grant reaches', async () => {
  const { site, unit, asset } = await insertSiteUnitAsset('Sweep granted');
  const plan = await insertPlan();
  const schedule = await createDueSchedule(asset.id, plan.id);

  const writer = await insertAccount();
  await pool.query(
    'INSERT INTO app_user_org_units (app_user_id, org_unit_id, can_write) VALUES ($1, $2, TRUE)',
    [writer.id, unit.id]
  );
  const { response, payload } = await api('POST', `/sites/${site.id}/pm-schedules/raise`, writer.token);
  assert.strictEqual(response.status, 200, JSON.stringify(payload));
  assert.deepStrictEqual(payload.workOrders.map((wo) => wo.pmScheduleId), [schedule]);
  assert.deepStrictEqual(payload.failures, []);
});

// ---------------------------------------------------------------------------
// Finding 8: the three lists are capped, and say so.
// ---------------------------------------------------------------------------

test('the Work order history list is capped at 200 and says truncated', async () => {
  const { site, unit, asset } = await insertSiteUnitAsset('History press');
  const tag = uniqueCode('HX');
  await pool.query(
    `INSERT INTO work_orders (work_order_no, asset_id, org_unit_id, summary, work_type, priority, status, actual_end)
     SELECT $1 || '-' || g, $2, $3, 'old job', 'corrective', 3, 'completed', now()
       FROM generate_series(1, 201) g`,
    [tag, asset.id, unit.id]
  );

  const history = await api('GET', `/sites/${site.id}/work-orders?includeHistory=true`, admin.token);
  assert.strictEqual(history.response.status, 200);
  assert.strictEqual(history.payload.workOrders.length, 200);
  assert.strictEqual(history.payload.truncated, true);

  const open = await api('GET', `/sites/${site.id}/work-orders`, admin.token);
  assert.deepStrictEqual(open.payload, { workOrders: [], truncated: false });
});

test('the Downtime list with closed events is capped at 200 and says truncated', async () => {
  const { site, unit, asset } = await insertSiteUnitAsset('Downtime press');
  await pool.query(
    `INSERT INTO downtime_events (asset_id, org_unit_id, started_at, ended_at)
     SELECT $1, $2, now() - (g || ' hours')::interval - interval '30 minutes',
            now() - (g || ' hours')::interval
       FROM generate_series(1, 201) g`,
    [asset.id, unit.id]
  );

  const all = await api('GET', `/sites/${site.id}/downtime?includeClosed=true`, admin.token);
  assert.strictEqual(all.response.status, 200);
  assert.strictEqual(all.payload.downtimeEvents.length, 200);
  assert.strictEqual(all.payload.truncated, true);

  const openOnly = await api('GET', `/sites/${site.id}/downtime`, admin.token);
  assert.deepStrictEqual(openOnly.payload, { downtimeEvents: [], truncated: false });
});

test('the stock movements list is capped at 200 and says truncated', async () => {
  const { site, unit } = await insertSiteUnitAsset('Store site');
  const { rows: [store] } = await pool.query(
    `INSERT INTO stores (site_id, org_unit_id, code, name) VALUES ($1, $2, $3, 'Review store') RETURNING id`,
    [site.id, unit.id, uniqueCode('S')]
  );
  storeIds.push(store.id);
  const { rows: [part] } = await pool.query(
    `INSERT INTO parts (part_no, description, uom_code) VALUES ($1, 'Review part', 'EA') RETURNING id`,
    [uniqueCode('P')]
  );
  partIds.push(part.id);

  const small = await api('GET', `/stores/${store.id}/movements`, admin.token);
  assert.deepStrictEqual(small.payload, { movements: [], truncated: false });

  await pool.query(
    `INSERT INTO stock_movements (part_id, store_id, quantity, movement_type, reason)
     SELECT $1, $2, 1, 'receipt', 'bulk ' || g FROM generate_series(1, 201) g`,
    [part.id, store.id]
  );
  const full = await api('GET', `/stores/${store.id}/movements`, admin.token);
  assert.strictEqual(full.response.status, 200);
  assert.strictEqual(full.payload.movements.length, 200);
  assert.strictEqual(full.payload.truncated, true);
});

// ---------------------------------------------------------------------------
// Low: a desktop start or complete records the Account's Employee.
// ---------------------------------------------------------------------------

test('a desktop start and complete record the signed-in Account\'s Employee', async () => {
  const { unit, asset } = await insertSiteUnitAsset('Employee press');
  const employee = await insertEmployee();
  const worker = await insertAccount({ employeeId: employee.id });
  await pool.query(
    'INSERT INTO app_user_org_units (app_user_id, org_unit_id, can_write) VALUES ($1, $2, TRUE)',
    [worker.id, unit.id]
  );
  const workOrder = await raiseWorkOrder(admin.token, asset.id);

  const started = await api('POST', `/work-orders/${workOrder.id}/start`, worker.token);
  assert.strictEqual(started.response.status, 200, JSON.stringify(started.payload));
  const completed = await api('POST', `/work-orders/${workOrder.id}/complete`, worker.token, { note: 'Fixed' });
  assert.strictEqual(completed.response.status, 200, JSON.stringify(completed.payload));

  const { rows: [row] } = await pool.query(
    'SELECT started_by, completed_by FROM work_orders WHERE id = $1',
    [workOrder.id]
  );
  assert.strictEqual(String(row.started_by), String(employee.id));
  assert.strictEqual(String(row.completed_by), String(employee.id));
});

test('a desktop start by an Account with no Employee leaves started_by empty', async () => {
  const { asset } = await insertSiteUnitAsset('No employee press');
  const workOrder = await raiseWorkOrder(admin.token, asset.id);
  const started = await api('POST', `/work-orders/${workOrder.id}/start`, admin.token);
  assert.strictEqual(started.response.status, 200);
  const { rows: [row] } = await pool.query('SELECT started_by FROM work_orders WHERE id = $1', [workOrder.id]);
  assert.strictEqual(row.started_by, null);
});
