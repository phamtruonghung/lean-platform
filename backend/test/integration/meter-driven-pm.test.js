/*
 * Meter-driven PM schedules: meters, manual readings, rollover and a schedule
 * that comes due on accumulated use (issue #79), over HTTP against a real
 * database and a real (locally issued) JWKS — the same seam as
 * preventive-maintenance.test.js, whose fixture scaffolding this file mirrors
 * closely. Assets, Accounts, Skills and shift patterns are inserted directly
 * against the database rather than through their own endpoints: this file is
 * about meters and readings, and the register, directory and calendar are
 * already covered by their own files.
 *
 * The raise sweep is Site-wide, so every test that raises uses its own fresh
 * Site — the same reason preventive-maintenance.test.js gives.
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
const insertedSkillIds = [];
const insertedJobPlanIds = [];
const insertedPmScheduleIds = [];
const insertedWorkOrderIds = [];
const insertedShiftDefinitionIds = [];

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

async function insertAccount({ role = 'supervisor' } = {}) {
  const subject = uniqueCode('acct');
  const { rows: [row] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status)
     VALUES ($1, 'Meter Test Account', $2, $3, TRUE, 'approved') RETURNING id`,
    [`${subject}@example.com`, role, subject]
  );
  insertedAccountIds.push(row.id);
  return { id: row.id, token: await authHeader(subject) };
}

async function insertSite({ timezone = 'Asia/Ho_Chi_Minh' } = {}) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO sites (code, name, timezone) VALUES ($1, 'Meter Test Site', $2) RETURNING id, code, timezone`,
    [uniqueCode('ST'), timezone]
  );
  insertedSiteIds.push(row.id);
  return row;
}

async function insertOrgUnit(siteId, { parentId = null, unitType = 'area', name = 'Meter Test Unit' } = {}) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, $2, $3, $4, $5) RETURNING id, code, name`,
    [siteId, parentId, uniqueCode('OU'), name, unitType]
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

async function insertAsset(orgUnitId, { name = 'Meter Asset' } = {}) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO assets (org_unit_id, code, name, asset_type, criticality)
     VALUES ($1, $2, $3, 'machine', 'high') RETURNING id, org_unit_id, code, name`,
    [orgUnitId, uniqueCode('AS'), name]
  );
  insertedAssetIds.push(row.id);
  return row;
}

async function insertShiftDefinition(siteId, { code = 'NIGHT', startTime = '22:00', durationMinutes = 480 } = {}) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO shift_definitions (site_id, code, name, start_time, duration_minutes, break_minutes, day_offset)
     VALUES ($1, $2, $2, $3, $4, 0, 0) RETURNING id`,
    [siteId, uniqueCode(code), startTime, durationMinutes]
  );
  insertedShiftDefinitionIds.push(row.id);
  return row;
}

// --- HTTP wrappers ---------------------------------------------------------

async function postJobPlan(token, body) {
  const response = await fetch(`${base}/api/maintenance/job-plans`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  const payload = await response.json().catch(() => null);
  if (payload?.jobPlan?.id) insertedJobPlanIds.push(payload.jobPlan.id);
  return { response, payload };
}

async function postMeter(token, body) {
  const response = await fetch(`${base}/api/maintenance/meters`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  const payload = await response.json().catch(() => null);
  return { response, payload };
}

async function getMeters(token, siteId, query = '') {
  const response = await fetch(`${base}/api/maintenance/sites/${siteId}/meters${query}`, {
    headers: token
  });
  const payload = await response.json().catch(() => null);
  return { response, payload };
}

async function postReading(token, meterId, body) {
  const response = await fetch(`${base}/api/maintenance/meters/${meterId}/readings`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  const payload = await response.json().catch(() => null);
  return { response, payload };
}

async function postRollover(token, meterId, body) {
  const response = await fetch(`${base}/api/maintenance/meters/${meterId}/rollover`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  const payload = await response.json().catch(() => null);
  return { response, payload };
}

async function getUnitsOfMeasure(token) {
  const response = await fetch(`${base}/api/maintenance/units-of-measure`, { headers: token });
  const payload = await response.json().catch(() => null);
  return { response, payload };
}

async function postPmSchedule(token, body) {
  const response = await fetch(`${base}/api/maintenance/pm-schedules`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  const payload = await response.json().catch(() => null);
  if (payload?.pmSchedule?.id) insertedPmScheduleIds.push(payload.pmSchedule.id);
  return { response, payload };
}

async function getPmSchedules(token, siteId) {
  const response = await fetch(`${base}/api/maintenance/sites/${siteId}/pm-schedules`, {
    headers: token
  });
  const payload = await response.json().catch(() => null);
  return { response, payload };
}

async function postRaise(token, siteId) {
  const response = await fetch(`${base}/api/maintenance/sites/${siteId}/pm-schedules/raise`, {
    method: 'POST',
    headers: token
  });
  const payload = await response.json().catch(() => null);
  for (const workOrder of payload?.workOrders ?? []) {
    if (workOrder.id) insertedWorkOrderIds.push(workOrder.id);
  }
  return { response, payload };
}

async function getWorkOrderDetail(token, id) {
  const response = await fetch(`${base}/api/maintenance/work-orders/${id}`, { headers: token });
  const payload = await response.json().catch(() => null);
  return { response, payload };
}

async function postTaskReading(token, workOrderId, taskId, body) {
  const response = await fetch(`${base}/api/maintenance/work-orders/${workOrderId}/tasks/${taskId}/reading`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  const payload = await response.json().catch(() => null);
  return { response, payload };
}

async function postStart(token, workOrderId) {
  const response = await fetch(`${base}/api/maintenance/work-orders/${workOrderId}/start`, {
    method: 'POST',
    headers: token
  });
  return { response, payload: await response.json().catch(() => null) };
}

async function postComplete(token, workOrderId, body) {
  const response = await fetch(`${base}/api/maintenance/work-orders/${workOrderId}/complete`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  return { response, payload: await response.json().catch(() => null) };
}

// --- Fixture helpers -------------------------------------------------------

function planBody(overrides = {}) {
  return {
    code: uniqueCode('JP'),
    name: 'Meter PM Plan',
    workType: 'preventive',
    ...overrides
  };
}

async function createPlan(overrides = {}) {
  const { response, payload } = await postJobPlan(admin.token, planBody(overrides));
  assert.strictEqual(response.status, 201, JSON.stringify(payload));
  return payload.jobPlan;
}

// A Site with one Org Unit and one Asset — what a meter test needs.
async function insertIsolatedSite({ assetName = 'Meter Asset' } = {}) {
  const site = await insertSite();
  const unit = await insertOrgUnit(site.id, { name: 'Meter Area' });
  const asset = await insertAsset(unit.id, { name: assetName });
  return { site, unit, asset };
}

let admin;
let noGrantAccount;
let readOnlyAccount;
let writerAccount;
let siblingWriter;

let site;
let grantedLine;
let otherLine;

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
  siblingWriter = await insertAccount();

  site = await insertSite();
  const grantedArea = await insertOrgUnit(site.id, { name: 'Granted Area' });
  grantedLine = await insertOrgUnit(site.id, { parentId: grantedArea.id, unitType: 'line', name: 'Line 1' });
  otherLine = await insertOrgUnit(site.id, { parentId: grantedArea.id, unitType: 'line', name: 'Line 2' });

  await insertGrant({ accountId: readOnlyAccount.id, orgUnitId: grantedLine.id, canWrite: false });
  await insertGrant({ accountId: writerAccount.id, orgUnitId: grantedLine.id, canWrite: true });
  await insertGrant({ accountId: siblingWriter.id, orgUnitId: otherLine.id, canWrite: true });
});

test.after(async () => {
  // Work orders are cleaned by Asset rather than by tracked id: every Work
  // order this file raises is on one of its own isolated Assets, and the
  // cascade takes their tasks with them.
  await pool.query('DELETE FROM work_orders WHERE asset_id = ANY($1)', [insertedAssetIds]);
  await pool.query('DELETE FROM pm_schedules WHERE id = ANY($1)', [insertedPmScheduleIds]);
  await pool.query('DELETE FROM job_plans WHERE id = ANY($1)', [insertedJobPlanIds]);
  await pool.query(
    `DELETE FROM meter_readings
      WHERE asset_meter_id IN (SELECT id FROM asset_meters WHERE asset_id = ANY($1))`,
    [insertedAssetIds]
  );
  await pool.query('DELETE FROM asset_meters WHERE asset_id = ANY($1)', [insertedAssetIds]);
  await pool.query('DELETE FROM shift_instances WHERE site_id = ANY($1)', [insertedSiteIds]);
  await pool.query('DELETE FROM shift_definitions WHERE id = ANY($1)', [insertedShiftDefinitionIds]);
  await pool.query('DELETE FROM skills WHERE id = ANY($1)', [insertedSkillIds]);
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
// Meters on an Asset.
// ---------------------------------------------------------------------------

test('a meter is defined on an Asset and reads back with its unit and accumulated use', async () => {
  const { site: isolatedSite, asset } = await insertIsolatedSite();

  const { response, payload } = await postMeter(admin.token, {
    assetId: asset.id,
    code: 'RUN-HRS',
    name: 'Running hours',
    uomCode: 'H',
    meterType: 'cumulative'
  });

  assert.strictEqual(response.status, 201, JSON.stringify(payload));
  const meter = payload.meter;
  assert.ok(meter.id);
  assert.strictEqual(meter.assetId, String(asset.id));
  assert.strictEqual(meter.assetName, asset.name);
  assert.strictEqual(meter.orgUnitId, String(asset.org_unit_id));
  assert.strictEqual(meter.code, 'RUN-HRS');
  assert.strictEqual(meter.uomCode, 'H');
  assert.strictEqual(meter.uomName, 'Hour');
  assert.strictEqual(meter.meterType, 'cumulative');
  assert.strictEqual(meter.rolloverOffset, 0);
  assert.strictEqual(meter.latestReading, null);
  assert.strictEqual(meter.accumulatedUse, 0);

  const listed = await getMeters(admin.token, isolatedSite.id);
  assert.strictEqual(listed.response.status, 200);
  assert.ok(listed.payload.meters.some((candidate) => candidate.id === meter.id));

  // The Asset-narrowed read the PM form uses.
  const narrowed = await getMeters(admin.token, isolatedSite.id, `?assetId=${asset.id}`);
  assert.strictEqual(narrowed.response.status, 200);
  assert.ok(narrowed.payload.meters.some((candidate) => candidate.id === meter.id));
});

test('a meter validation refuses a bad type, a missing code, and an unknown unit', async () => {
  const { asset } = await insertIsolatedSite();

  const badType = await postMeter(admin.token, {
    assetId: asset.id,
    code: 'X',
    name: 'X',
    uomCode: 'H',
    meterType: 'counter'
  });
  assert.strictEqual(badType.response.status, 400);

  const noCode = await postMeter(admin.token, {
    assetId: asset.id,
    name: 'X',
    uomCode: 'H',
    meterType: 'cumulative'
  });
  assert.strictEqual(noCode.response.status, 400);

  const unknownUnit = await postMeter(admin.token, {
    assetId: asset.id,
    code: 'X',
    name: 'X',
    uomCode: 'NOPE',
    meterType: 'cumulative'
  });
  assert.strictEqual(unknownUnit.response.status, 404);
  assert.strictEqual(unknownUnit.payload.message, 'Unit of measure not found');

  const duplicate = await postMeter(admin.token, {
    assetId: asset.id,
    code: 'DUP',
    name: 'First',
    uomCode: 'H',
    meterType: 'cumulative'
  });
  assert.strictEqual(duplicate.response.status, 201);
  const second = await postMeter(admin.token, {
    assetId: asset.id,
    code: 'DUP',
    name: 'Second',
    uomCode: 'H',
    meterType: 'cumulative'
  });
  assert.strictEqual(second.response.status, 409);
});

test('the unit-of-measure catalogue is readable by any approved Account', async () => {
  const { response, payload } = await getUnitsOfMeasure(noGrantAccount.token);
  assert.strictEqual(response.status, 200);
  assert.ok(payload.unitsOfMeasure.some((unit) => unit.code === 'H'));
});

// ---------------------------------------------------------------------------
// Readings.
// ---------------------------------------------------------------------------

test('a manual reading is recorded and its shift instance is resolved by the trigger', async () => {
  // A Site in UTC+7 with a night shift 22:00–06:00. A reading at 05:55 on the
  // 2nd belongs to the shift whose production day is the 1st — the whole point
  // of the baseline trigger, and the boundary the ticket names.
  const isolatedSite = await insertSite({ timezone: 'Asia/Ho_Chi_Minh' });
  const unit = await insertOrgUnit(isolatedSite.id, { name: 'Night Line' });
  const asset = await insertAsset(unit.id, { name: 'Night Asset' });
  await insertShiftDefinition(isolatedSite.id, { code: 'NIGHT' });

  const generated = await pool.query(
    `SELECT generate_shift_instances($1, DATE '2026-03-01', DATE '2026-03-02') AS created`,
    [unit.id]
  );
  assert.ok(generated.rows[0].created > 0, 'the night shift should have generated instances');

  const { rows: [night] } = await pool.query(
    `SELECT id, production_date FROM shift_instances
      WHERE org_unit_id = $1 AND production_date = DATE '2026-03-01'`,
    [unit.id]
  );
  assert.ok(night, 'the night instance for March 1 should exist');

  const meter = (await postMeter(admin.token, {
    assetId: asset.id,
    code: 'NIGHT-HRS',
    name: 'Night hours',
    uomCode: 'H',
    meterType: 'cumulative'
  })).payload.meter;

  const { response, payload } = await postReading(admin.token, meter.id, {
    reading: 12,
    readAt: '2026-03-02T05:55:00+07:00'
  });

  assert.strictEqual(response.status, 201, JSON.stringify(payload));
  assert.strictEqual(payload.reading.reading, 12);
  assert.strictEqual(payload.reading.source, 'manual');
  assert.strictEqual(payload.reading.shiftInstanceId, String(night.id));
  assert.strictEqual(payload.meter.latestReading, 12);
  assert.strictEqual(payload.meter.accumulatedUse, 12);
});

test('a backwards reading on a cumulative meter is refused with a named code', async () => {
  const { asset } = await insertIsolatedSite();
  const meter = (await postMeter(admin.token, {
    assetId: asset.id,
    code: 'RUN',
    name: 'Run',
    uomCode: 'H',
    meterType: 'cumulative'
  })).payload.meter;

  const first = await postReading(admin.token, meter.id, { reading: 100 });
  assert.strictEqual(first.response.status, 201);

  const backwards = await postReading(admin.token, meter.id, { reading: 40 });
  assert.strictEqual(backwards.response.status, 409);
  assert.strictEqual(backwards.payload.code, 'METER_READING_REGRESSED');
  assert.match(backwards.payload.message, /cannot read lower/);
});

test('a gauge may read up or down', async () => {
  const { asset } = await insertIsolatedSite();
  const meter = (await postMeter(admin.token, {
    assetId: asset.id,
    code: 'TEMP',
    name: 'Temperature',
    uomCode: 'EA',
    meterType: 'gauge'
  })).payload.meter;

  const up = await postReading(admin.token, meter.id, { reading: 100 });
  assert.strictEqual(up.response.status, 201);
  const down = await postReading(admin.token, meter.id, { reading: 40 });
  assert.strictEqual(down.response.status, 201);
  assert.strictEqual(down.payload.meter.accumulatedUse, 40);
});

test('a non-manual source is refused — this ticket accepts a typed reading only', async () => {
  const { asset } = await insertIsolatedSite();
  const meter = (await postMeter(admin.token, {
    assetId: asset.id,
    code: 'PLC',
    name: 'PLC feed',
    uomCode: 'H',
    meterType: 'cumulative'
  })).payload.meter;

  const { response, payload } = await postReading(admin.token, meter.id, { reading: 5, source: 'plc' });
  assert.strictEqual(response.status, 400);
  assert.match(payload.message, /not accepted yet/);
});

// ---------------------------------------------------------------------------
// Rollover and replacement.
// ---------------------------------------------------------------------------

test('a rollover carries accumulated use into the offset and lets the counter continue', async () => {
  const { asset } = await insertIsolatedSite();
  const meter = (await postMeter(admin.token, {
    assetId: asset.id,
    code: 'ROLL',
    name: 'Rollover',
    uomCode: 'H',
    meterType: 'cumulative'
  })).payload.meter;

  await postReading(admin.token, meter.id, { reading: 100 });
  await postReading(admin.token, meter.id, { reading: 900 });

  // The counter is replaced; the new one reads 0. Accumulated use must not
  // drop, and the next reading must be allowed even though it is lower than
  // the old counter's 900.
  const rollover = await postRollover(admin.token, meter.id, { reading: 0, note: 'Hour counter replaced' });
  assert.strictEqual(rollover.response.status, 201, JSON.stringify(rollover.payload));
  assert.strictEqual(rollover.payload.meter.rolloverOffset, 900);
  assert.strictEqual(rollover.payload.meter.latestReading, 0);
  assert.strictEqual(rollover.payload.meter.accumulatedUse, 900);

  const after = await postReading(admin.token, meter.id, { reading: 50 });
  assert.strictEqual(after.response.status, 201);
  assert.strictEqual(after.payload.meter.accumulatedUse, 950);

  // And a reading below the new counter's own last reading is still refused.
  const backwards = await postReading(admin.token, meter.id, { reading: 10 });
  assert.strictEqual(backwards.response.status, 409);
  assert.strictEqual(backwards.payload.code, 'METER_READING_REGRESSED');
});

test('a reading that goes down without an explicit rollover is refused, never inferred', async () => {
  const { asset } = await insertIsolatedSite();
  const meter = (await postMeter(admin.token, {
    assetId: asset.id,
    code: 'INFER',
    name: 'Infer',
    uomCode: 'H',
    meterType: 'cumulative'
  })).payload.meter;

  await postReading(admin.token, meter.id, { reading: 500 });
  const reset = await postReading(admin.token, meter.id, { reading: 0 });
  assert.strictEqual(reset.response.status, 409);
  assert.strictEqual(reset.payload.code, 'METER_READING_REGRESSED');
});

// ---------------------------------------------------------------------------
// A meter-driven PM schedule.
// ---------------------------------------------------------------------------

test('a meter-driven schedule is created, comes due on accumulated use, and raises a work order', async () => {
  const { site: isolatedSite, asset } = await insertIsolatedSite({ assetName: 'Compressor' });
  const plan = await createPlan({ name: '500-hour service' });
  const meter = (await postMeter(admin.token, {
    assetId: asset.id,
    code: 'RUN-HRS',
    name: 'Running hours',
    uomCode: 'H',
    meterType: 'cumulative'
  })).payload.meter;

  const created = await postPmSchedule(admin.token, {
    assetId: asset.id,
    jobPlanId: plan.id,
    assetMeterId: meter.id,
    intervalMeter: 500,
    anchor: 'completed'
  });
  assert.strictEqual(created.response.status, 201, JSON.stringify(created.payload));
  const schedule = created.payload.pmSchedule;
  assert.strictEqual(schedule.intervalDays, null);
  assert.strictEqual(schedule.assetMeterId, String(meter.id));
  assert.strictEqual(schedule.intervalMeter, 500);
  assert.strictEqual(schedule.nextDueMeter, 500);
  assert.strictEqual(schedule.currentMeter, 0);
  assert.strictEqual(schedule.nextDueOn, null);

  // Not yet due at 400.
  await postReading(admin.token, meter.id, { reading: 400 });
  const early = await postRaise(admin.token, isolatedSite.id);
  assert.strictEqual(early.response.status, 200);
  assert.strictEqual(early.payload.workOrders.length, 0);

  // At 600 the accumulated use has passed the target.
  await postReading(admin.token, meter.id, { reading: 600 });
  const raised = await postRaise(admin.token, isolatedSite.id);
  assert.strictEqual(raised.response.status, 200);
  const workOrder = raised.payload.workOrders.find((wo) => wo.pmScheduleId === schedule.id);
  assert.ok(workOrder, 'the meter schedule should have raised a work order');

  // A meter-driven occurrence carries no calendar due date — it came round on
  // usage, not on the calendar.
  const { rows: [raisedRow] } = await pool.query('SELECT due_date FROM work_orders WHERE id = $1', [
    workOrder.id
  ]);
  assert.strictEqual(raisedRow.due_date, null);

  // Completing it advances the meter target one interval past where it stands.
  await postStart(admin.token, workOrder.id);
  const completed = await postComplete(admin.token, workOrder.id, { note: 'Serviced at 600 hours' });
  assert.strictEqual(completed.response.status, 200);

  const listed = await getPmSchedules(admin.token, isolatedSite.id);
  const advanced = listed.payload.pmSchedules.find((candidate) => candidate.id === schedule.id);
  assert.strictEqual(advanced.lastCompletedMeter, 600);
  assert.strictEqual(advanced.nextDueMeter, 1100);
});

test('only a cumulative meter may drive a schedule, and only one on the same Asset', async () => {
  const { asset } = await insertIsolatedSite();
  const otherAsset = await insertAsset(asset.org_unit_id, { name: 'Other Asset' });
  const plan = await createPlan();
  const gauge = (await postMeter(admin.token, {
    assetId: asset.id,
    code: 'GAUGE',
    name: 'Gauge',
    uomCode: 'EA',
    meterType: 'gauge'
  })).payload.meter;
  const foreign = (await postMeter(admin.token, {
    assetId: otherAsset.id,
    code: 'FOREIGN',
    name: 'Foreign',
    uomCode: 'H',
    meterType: 'cumulative'
  })).payload.meter;

  const gaugeSchedule = await postPmSchedule(admin.token, {
    assetId: asset.id,
    jobPlanId: plan.id,
    assetMeterId: gauge.id,
    intervalMeter: 500
  });
  assert.strictEqual(gaugeSchedule.response.status, 400);
  assert.match(gaugeSchedule.payload.message, /cumulative/);

  const foreignSchedule = await postPmSchedule(admin.token, {
    assetId: asset.id,
    jobPlanId: plan.id,
    assetMeterId: foreign.id,
    intervalMeter: 500
  });
  assert.strictEqual(foreignSchedule.response.status, 400);
  assert.match(foreignSchedule.payload.message, /same Asset/);

  const unknownMeter = await postPmSchedule(admin.token, {
    assetId: asset.id,
    jobPlanId: plan.id,
    assetMeterId: '999999999',
    intervalMeter: 500
  });
  assert.strictEqual(unknownMeter.response.status, 404);
  assert.strictEqual(unknownMeter.payload.message, 'Meter not found');

  const noInterval = await postPmSchedule(admin.token, {
    assetId: asset.id,
    jobPlanId: plan.id,
    assetMeterId: foreign.id
  });
  assert.strictEqual(noInterval.response.status, 400);
});

// ---------------------------------------------------------------------------
// A reading recorded while working a Work order task.
// ---------------------------------------------------------------------------

test('a reading can be recorded while working a Work order task that names a meter', async () => {
  const { site: isolatedSite, asset } = await insertIsolatedSite({ assetName: 'Task Press' });
  const meter = (await postMeter(admin.token, {
    assetId: asset.id,
    code: 'VIB',
    name: 'Vibration',
    uomCode: 'EA',
    meterType: 'gauge'
  })).payload.meter;

  // The plan's own task names the meter; it is copied onto a raised Work
  // order task by the sweep. This test drives the reading route directly, so
  // it raises a Work order by hand and copies the task the same way the sweep
  // would — the sweep itself is covered above.
  const plan = await createPlan({
    name: 'Record a vibration reading',
    tasks: [{ stepNo: 1, instruction: 'Record vibration', recordsMeterId: meter.id }]
  });
  assert.ok(plan.tasks[0].recordsMeterId, 'the plan task should carry its meter');

  const manual = await fetch(`${base}/api/maintenance/work-orders`, {
    method: 'POST',
    headers: { ...admin.token, 'content-type': 'application/json' },
    body: JSON.stringify({ assetId: asset.id, summary: 'Manual job with a reading', workType: 'inspection', priority: 3 })
  });
  const manualPayload = await manual.json();
  assert.strictEqual(manual.status, 201, JSON.stringify(manualPayload));
  insertedWorkOrderIds.push(manualPayload.workOrder.id);

  // A manually raised Work order has no tasks; copy one by hand the way the
  // raise sweep would, so this test is about the reading route, not the sweep.
  const { rows: [task] } = await pool.query(
    `INSERT INTO work_order_tasks (work_order_id, step_no, instruction, asset_meter_id)
     VALUES ($1, 1, 'Record vibration', $2) RETURNING id`,
    [manualPayload.workOrder.id, meter.id]
  );

  const detailBefore = await getWorkOrderDetail(admin.token, manualPayload.workOrder.id);
  assert.strictEqual(detailBefore.payload.workOrder.tasks[0].assetMeterId, String(meter.id));

  const { response, payload } = await postTaskReading(
    admin.token,
    manualPayload.workOrder.id,
    task.id,
    { reading: 4.2, note: 'Slightly high' }
  );
  assert.strictEqual(response.status, 201, JSON.stringify(payload));
  assert.strictEqual(payload.task.reading, 4.2);
  assert.strictEqual(payload.reading.source, 'manual');

  const detailAfter = await getWorkOrderDetail(admin.token, manualPayload.workOrder.id);
  assert.strictEqual(detailAfter.payload.workOrder.tasks[0].reading, 4.2);

  // The reading really landed on the meter, with the shift resolved.
  const meters = await getMeters(admin.token, isolatedSite.id, `?assetId=${asset.id}`);
  const updated = meters.payload.meters.find((candidate) => candidate.id === meter.id);
  assert.strictEqual(updated.latestReading, 4.2);

  // A task that records no meter refuses the write with a clear message.
  const { rows: [plainTask] } = await pool.query(
    `INSERT INTO work_order_tasks (work_order_id, step_no, instruction)
     VALUES ($1, 2, 'Just a tick') RETURNING id`,
    [manualPayload.workOrder.id]
  );
  const refused = await postTaskReading(admin.token, manualPayload.workOrder.id, plainTask.id, { reading: 1 });
  assert.strictEqual(refused.response.status, 400);
  assert.match(refused.payload.message, /does not record a meter/);
});

test('a job plan task naming an unknown meter is a clean 404', async () => {
  const { response, payload } = await postJobPlan(admin.token, planBody({
    tasks: [{ stepNo: 1, instruction: 'Record', recordsMeterId: '999999999' }]
  }));
  assert.strictEqual(response.status, 404);
  assert.strictEqual(payload.message, 'Meter not found');
});

// ---------------------------------------------------------------------------
// Scope: writes need a WRITE Grant; reads are Site-wide.
// ---------------------------------------------------------------------------

test('a caller without write scope cannot define a meter or record a reading', async () => {
  const grantedAsset = await insertAsset(grantedLine.id, { name: 'Granted Asset' });
  const outsideAsset = await insertAsset(otherLine.id, { name: 'Outside Asset' });

  const readOnly = await postMeter(readOnlyAccount.token, {
    assetId: grantedAsset.id,
    code: 'RO',
    name: 'Read only',
    uomCode: 'H',
    meterType: 'cumulative'
  });
  assert.strictEqual(readOnly.response.status, 403);
  assert.strictEqual(readOnly.payload.message, "Outside the caller's granted Org Units");

  const sibling = await postMeter(siblingWriter.token, {
    assetId: grantedAsset.id,
    code: 'SIB',
    name: 'Sibling',
    uomCode: 'H',
    meterType: 'cumulative'
  });
  assert.strictEqual(sibling.response.status, 403);

  // A malformed Asset is a 404 before scope is even asked.
  const missing = await postMeter(writerAccount.token, {
    assetId: 'not-an-id',
    code: 'MISS',
    name: 'Missing',
    uomCode: 'H',
    meterType: 'cumulative'
  });
  assert.strictEqual(missing.response.status, 404);

  // The Asset outside the caller's branch is visible to the read, but not
  // writable through it.
  const outside = await postMeter(writerAccount.token, {
    assetId: outsideAsset.id,
    code: 'OUT',
    name: 'Outside',
    uomCode: 'H',
    meterType: 'cumulative'
  });
  assert.strictEqual(outside.response.status, 403);

  // A meter inside the caller's Grant can be defined, and a reading written.
  const allowed = await postMeter(writerAccount.token, {
    assetId: grantedAsset.id,
    code: 'ALLOWED',
    name: 'Allowed',
    uomCode: 'H',
    meterType: 'cumulative'
  });
  assert.strictEqual(allowed.response.status, 201);

  const reading = await postReading(writerAccount.token, allowed.payload.meter.id, { reading: 3 });
  assert.strictEqual(reading.response.status, 201);

  // The read is Site-wide whatever the caller's Grants.
  const read = await getMeters(noGrantAccount.token, site.id);
  assert.strictEqual(read.response.status, 200);
  assert.ok(read.payload.meters.some((candidate) => candidate.id === allowed.payload.meter.id));
});

test('an unknown Site on the meter read is a 404, not an empty list', async () => {
  const { response, payload } = await getMeters(admin.token, '999999999');
  assert.strictEqual(response.status, 404);
  assert.strictEqual(payload.message, 'Site not found');
});

test('a request with no bearer token is refused on the new surfaces', async () => {
  const meters = await fetch(`${base}/api/maintenance/sites/${site.id}/meters`);
  assert.strictEqual(meters.status, 401);

  const units = await fetch(`${base}/api/maintenance/units-of-measure`);
  assert.strictEqual(units.status, 401);

  const create = await fetch(`${base}/api/maintenance/meters`, { method: 'POST' });
  assert.strictEqual(create.status, 401);

  const reading = await fetch(`${base}/api/maintenance/meters/1/readings`, { method: 'POST' });
  assert.strictEqual(reading.status, 401);
});
