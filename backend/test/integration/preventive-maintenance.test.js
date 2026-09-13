/*
 * Preventive maintenance: job plans and calendar-driven PM schedules over
 * HTTP (issue #74), against a real database and a real (locally issued) JWKS —
 * the same seam as work-orders.test.js and downtime.test.js, whose fixture
 * scaffolding this file mirrors closely. Assets, Accounts and Skills are
 * inserted directly against the database rather than through their own
 * endpoints: this file is about job plans and PM schedules, and the register
 * and directory are already covered by their own files.
 *
 * The raise sweep is Site-wide, so every test that raises uses its own fresh
 * Site. That is not ceremony: a sweep would otherwise pick up a due schedule
 * another test left behind and make an assertion about what was raised
 * depend on test order.
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
     VALUES ($1, 'PM Test Account', $2, $3, TRUE, 'approved') RETURNING id`,
    [`${subject}@example.com`, role, subject]
  );
  insertedAccountIds.push(row.id);
  return { id: row.id, token: await authHeader(subject) };
}

async function insertSite() {
  const { rows: [row] } = await pool.query(
    `INSERT INTO sites (code, name, timezone) VALUES ($1, 'PM Test Site', 'Asia/Ho_Chi_Minh') RETURNING id, code`,
    [uniqueCode('ST')]
  );
  insertedSiteIds.push(row.id);
  return row;
}

async function insertOrgUnit(siteId, { parentId = null, unitType = 'area', name = 'PM Test Unit' } = {}) {
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

async function insertAsset(orgUnitId, { name = 'PM Asset' } = {}) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO assets (org_unit_id, code, name, asset_type, criticality)
     VALUES ($1, $2, $3, 'machine', 'high') RETURNING id, org_unit_id, code, name`,
    [orgUnitId, uniqueCode('AS'), name]
  );
  insertedAssetIds.push(row.id);
  return row;
}

async function insertSkill({ name = 'PM Test Skill' } = {}) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO skills (code, name) VALUES ($1, $2) RETURNING id, name`,
    [uniqueCode('SK'), name]
  );
  insertedSkillIds.push(row.id);
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

async function getJobPlans(token, query = '') {
  const response = await fetch(`${base}/api/maintenance/job-plans${query}`, { headers: token });
  const payload = await response.json().catch(() => null);
  return { response, payload };
}

async function getJobPlan(token, id) {
  const response = await fetch(`${base}/api/maintenance/job-plans/${id}`, { headers: token });
  const payload = await response.json().catch(() => null);
  return { response, payload };
}

async function patchJobPlan(token, id, body) {
  const response = await fetch(`${base}/api/maintenance/job-plans/${id}`, {
    method: 'PATCH',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
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

async function getPmSchedules(token, siteId, query = '') {
  const response = await fetch(`${base}/api/maintenance/sites/${siteId}/pm-schedules${query}`, {
    headers: token
  });
  const payload = await response.json().catch(() => null);
  return { response, payload };
}

async function patchPmSchedule(token, id, body) {
  const response = await fetch(`${base}/api/maintenance/pm-schedules/${id}`, {
    method: 'PATCH',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
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

async function postStart(token, workOrderId) {
  const response = await fetch(`${base}/api/maintenance/work-orders/${workOrderId}/start`, {
    method: 'POST',
    headers: token
  });
  const payload = await response.json().catch(() => null);
  return { response, payload };
}

async function postComplete(token, workOrderId, body) {
  const response = await fetch(`${base}/api/maintenance/work-orders/${workOrderId}/complete`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body)
  });
  const payload = await response.json().catch(() => null);
  return { response, payload };
}

// --- Fixture helpers -------------------------------------------------------

// The DB's own CURRENT_DATE, offset by whole days and formatted as the
// service formats it. Using the database's date rather than a JS one keeps
// these tests honest wherever the API process's timezone differs from
// Postgres's.
async function dbDate(offsetDays = 0) {
  const { rows: [row] } = await pool.query(
    `SELECT to_char(CURRENT_DATE + $1::int, 'YYYY-MM-DD') AS d`,
    [offsetDays]
  );
  return row.d;
}

function planBody(overrides = {}) {
  return {
    code: uniqueCode('JP'),
    name: 'PM Test Plan',
    workType: 'preventive',
    ...overrides
  };
}

async function createPlan(overrides = {}) {
  const { response, payload } = await postJobPlan(admin.token, planBody(overrides));
  assert.strictEqual(response.status, 201, JSON.stringify(payload));
  return payload.jobPlan;
}

// A Site with one Org Unit and one Asset, exactly what a raise test needs.
async function insertIsolatedSite({ assetName = 'PM Asset' } = {}) {
  const site = await insertSite();
  const unit = await insertOrgUnit(site.id, { name: 'PM Area' });
  const asset = await insertAsset(unit.id, { name: assetName });
  return { site, unit, asset };
}

async function openWorkOrdersForSchedule(pmScheduleId) {
  const { rows: [row] } = await pool.query(
    `SELECT count(*)::int AS n FROM work_orders
      WHERE pm_schedule_id = $1
        AND status IN ('draft', 'approved', 'scheduled', 'in_progress', 'on_hold')`,
    [pmScheduleId]
  );
  return row.n;
}

let admin;
let noGrantAccount;   // approved, no Grant anywhere at all.
let readOnlyAccount;  // read Grant on grantedLine.
let writerAccount;    // write Grant on grantedLine.
let siblingWriter;    // write Grant on otherLine only.

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
  await pool.query('DELETE FROM work_orders WHERE id = ANY($1)', [insertedWorkOrderIds]);
  await pool.query('DELETE FROM pm_schedules WHERE id = ANY($1)', [insertedPmScheduleIds]);
  await pool.query('DELETE FROM job_plans WHERE id = ANY($1)', [insertedJobPlanIds]);
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
// Job plans: the shared catalogue.
// ---------------------------------------------------------------------------

test('creating a job plan returns its ordered tasks with skill names, and the detail reads it back', async () => {
  const skill = await insertSkill({ name: 'Vibration Analysis' });

  const { response, payload } = await postJobPlan(admin.token, {
    ...planBody({ name: 'Quarterly Pump Service' }),
    description: 'Lubricate and inspect',
    estimatedHours: 2.5,
    requiresShutdown: true,
    safetyNote: 'Isolate before opening',
    // Deliberately out of order: the wire must come back step-ordered.
    tasks: [
      { stepNo: 2, instruction: 'Inspect seals', skillId: skill.id, estimatedHours: 1 },
      { stepNo: 1, instruction: 'Lock out and tag out' }
    ]
  });

  assert.strictEqual(response.status, 201);
  const jobPlan = payload.jobPlan;
  assert.ok(jobPlan.id);
  assert.strictEqual(jobPlan.workType, 'preventive');
  assert.strictEqual(jobPlan.estimatedHours, 2.5);
  assert.strictEqual(jobPlan.requiresShutdown, true);
  assert.strictEqual(jobPlan.safetyNote, 'Isolate before opening');
  assert.strictEqual(jobPlan.isActive, true);
  assert.deepStrictEqual(jobPlan.tasks.map((task) => task.stepNo), [1, 2]);
  assert.strictEqual(jobPlan.tasks[1].instruction, 'Inspect seals');
  assert.strictEqual(jobPlan.tasks[1].skillName, 'Vibration Analysis');
  assert.strictEqual(jobPlan.tasks[1].estimatedHours, 1);
  assert.strictEqual(jobPlan.tasks[0].skillId, null);
  assert.strictEqual(jobPlan.tasks[0].skillName, null);

  const detail = await getJobPlan(admin.token, jobPlan.id);
  assert.strictEqual(detail.response.status, 200);
  assert.deepStrictEqual(detail.payload.jobPlan.tasks.map((task) => task.stepNo), [1, 2]);

  const list = await getJobPlans(admin.token);
  const listed = list.payload.jobPlans.find((plan) => plan.id === jobPlan.id);
  assert.ok(listed, 'the new plan should appear in the catalogue listing');
  assert.strictEqual(listed.tasks.length, 2);
});

test('an unknown or malformed job plan id is a clean 404', async () => {
  const unknown = await getJobPlan(admin.token, '999999999');
  assert.strictEqual(unknown.response.status, 404);
  assert.strictEqual(unknown.payload.message, 'Job plan not found');

  const malformed = await getJobPlan(admin.token, 'not-an-id');
  assert.strictEqual(malformed.response.status, 404);
});

test('job plan validation refuses a bad workType, a missing name, and duplicate stepNos', async () => {
  const badType = await postJobPlan(admin.token, planBody({ workType: 'corrective' }));
  assert.strictEqual(badType.response.status, 400);

  const noName = await postJobPlan(admin.token, { code: uniqueCode('JP'), workType: 'preventive' });
  assert.strictEqual(noName.response.status, 400);

  const duplicateStep = await postJobPlan(admin.token, planBody({
    tasks: [
      { stepNo: 1, instruction: 'One' },
      { stepNo: 1, instruction: 'Again' }
    ]
  }));
  assert.strictEqual(duplicateStep.response.status, 400);

  const noInstruction = await postJobPlan(admin.token, planBody({
    tasks: [{ stepNo: 1, instruction: '   ' }]
  }));
  assert.strictEqual(noInstruction.response.status, 400);
});

test('creating or deactivating a job plan is administrator-only', async () => {
  const created = await postJobPlan(writerAccount.token, planBody());
  assert.strictEqual(created.response.status, 403);
  assert.strictEqual(created.payload.message, 'This action requires the administrator role.');

  const plan = await createPlan();
  const patched = await patchJobPlan(writerAccount.token, plan.id, { isActive: false });
  assert.strictEqual(patched.response.status, 403);
});

test('a non-administrator may still read the job plan catalogue', async () => {
  const plan = await createPlan();
  const detail = await getJobPlan(noGrantAccount.token, plan.id);
  assert.strictEqual(detail.response.status, 200);
  assert.strictEqual(detail.payload.jobPlan.id, plan.id);
});

test('deactivating a plan hides it from the active-only listing but keeps its work orders readable', async () => {
  const { site: isolatedSite, asset } = await insertIsolatedSite({ assetName: 'Plan Lifetime Press' });
  const plan = await createPlan({ name: 'Plan Lifetime' });

  const created = await postPmSchedule(admin.token, {
    assetId: asset.id,
    jobPlanId: plan.id,
    intervalDays: 30,
    nextDueOn: await dbDate(-2)
  });
  assert.strictEqual(created.response.status, 201);

  const raised = await postRaise(admin.token, isolatedSite.id);
  assert.strictEqual(raised.response.status, 200);
  const workOrder = raised.payload.workOrders.find((wo) => wo.pmScheduleId === created.payload.pmSchedule.id);
  assert.ok(workOrder, 'the schedule should have raised a work order');

  const deactivated = await patchJobPlan(admin.token, plan.id, { isActive: false });
  assert.strictEqual(deactivated.response.status, 200);
  assert.strictEqual(deactivated.payload.jobPlan.isActive, false);

  const activeOnly = await getJobPlans(admin.token, '?includeInactive=false');
  assert.ok(!activeOnly.payload.jobPlans.some((candidate) => candidate.id === plan.id));

  const all = await getJobPlans(admin.token);
  assert.ok(all.payload.jobPlans.some((candidate) => candidate.id === plan.id));

  // The work order raised from the now-inactive plan is untouched: its copied
  // tasks are its own, and the plan's state does not reach back into it.
  const detail = await getWorkOrderDetail(admin.token, workOrder.id);
  assert.strictEqual(detail.response.status, 200);
  assert.strictEqual(detail.payload.workOrder.id, workOrder.id);
});

// ---------------------------------------------------------------------------
// PM schedules: creation, listing, deactivation.
// ---------------------------------------------------------------------------

test('creating a schedule applies the documented defaults and computes daysUntilDue', async () => {
  const { site: isolatedSite, asset } = await insertIsolatedSite();
  const plan = await createPlan({ name: 'Defaults Plan' });

  const { response, payload } = await postPmSchedule(admin.token, {
    assetId: asset.id,
    jobPlanId: plan.id,
    intervalDays: 90
  });

  assert.strictEqual(response.status, 201);
  const pmSchedule = payload.pmSchedule;
  assert.strictEqual(pmSchedule.assetId, String(asset.id));
  assert.strictEqual(pmSchedule.assetName, asset.name);
  assert.strictEqual(pmSchedule.orgUnitId, String(asset.org_unit_id));
  assert.strictEqual(pmSchedule.jobPlanId, String(plan.id));
  assert.strictEqual(pmSchedule.jobPlanName, plan.name);
  assert.strictEqual(pmSchedule.intervalDays, 90);
  assert.strictEqual(pmSchedule.anchor, 'completed');
  assert.strictEqual(pmSchedule.leadTimeDays, 7);
  assert.strictEqual(pmSchedule.priority, 3);
  assert.strictEqual(pmSchedule.isActive, true);
  assert.strictEqual(pmSchedule.lastCompletedOn, null);
  assert.strictEqual(pmSchedule.nextDueOn, await dbDate(90));
  assert.strictEqual(pmSchedule.daysUntilDue, 90);

  const listed = await getPmSchedules(admin.token, isolatedSite.id);
  assert.strictEqual(listed.response.status, 200);
  assert.ok(listed.payload.pmSchedules.some((candidate) => candidate.id === pmSchedule.id));
});

test('an explicit nextDueOn is honoured, and the schedule carries its Asset beside its Site', async () => {
  const { site: isolatedSite, asset } = await insertIsolatedSite();
  const plan = await createPlan();
  const explicit = await dbDate(12);

  const { response, payload } = await postPmSchedule(admin.token, {
    assetId: asset.id,
    jobPlanId: plan.id,
    intervalDays: 30,
    anchor: 'due',
    leadTimeDays: 5,
    priority: 1,
    nextDueOn: explicit
  });

  assert.strictEqual(response.status, 201);
  assert.strictEqual(payload.pmSchedule.nextDueOn, explicit);
  assert.strictEqual(payload.pmSchedule.daysUntilDue, 12);
  assert.strictEqual(payload.pmSchedule.anchor, 'due');
  assert.strictEqual(payload.pmSchedule.leadTimeDays, 5);
  assert.strictEqual(payload.pmSchedule.priority, 1);
  assert.strictEqual(payload.pmSchedule.assetCode, asset.code);
});

test('schedule validation refuses a missing interval, a bad anchor, and an unknown Job plan', async () => {
  const { asset } = await insertIsolatedSite();
  const plan = await createPlan();

  const noInterval = await postPmSchedule(admin.token, { assetId: asset.id, jobPlanId: plan.id });
  assert.strictEqual(noInterval.response.status, 400);

  const badAnchor = await postPmSchedule(admin.token, {
    assetId: asset.id,
    jobPlanId: plan.id,
    intervalDays: 30,
    anchor: 'whenever'
  });
  assert.strictEqual(badAnchor.response.status, 400);

  const unknownPlan = await postPmSchedule(admin.token, {
    assetId: asset.id,
    jobPlanId: '999999999',
    intervalDays: 30
  });
  assert.strictEqual(unknownPlan.response.status, 404);
  assert.strictEqual(unknownPlan.payload.message, 'Job plan not found');
});

test('an inactive Job plan cannot be scheduled', async () => {
  const { asset } = await insertIsolatedSite();
  const plan = await createPlan();
  await patchJobPlan(admin.token, plan.id, { isActive: false });

  const { response, payload } = await postPmSchedule(admin.token, {
    assetId: asset.id,
    jobPlanId: plan.id,
    intervalDays: 30
  });
  assert.strictEqual(response.status, 400);
  assert.ok(payload.message.includes('not active'));
});

test('an unknown Site on the schedule read is a 404, not an empty list', async () => {
  const { response, payload } = await getPmSchedules(admin.token, '999999999');
  assert.strictEqual(response.status, 404);
  assert.strictEqual(payload.message, 'Site not found');
});

test('a schedule can be deactivated, and it then stops raising', async () => {
  const { site: isolatedSite, asset } = await insertIsolatedSite();
  const plan = await createPlan();
  const created = await postPmSchedule(admin.token, {
    assetId: asset.id,
    jobPlanId: plan.id,
    intervalDays: 30,
    nextDueOn: await dbDate(-1)
  });

  const deactivated = await patchPmSchedule(admin.token, created.payload.pmSchedule.id, { isActive: false });
  assert.strictEqual(deactivated.response.status, 200);
  assert.strictEqual(deactivated.payload.pmSchedule.isActive, false);

  const raised = await postRaise(admin.token, isolatedSite.id);
  assert.strictEqual(raised.response.status, 200);
  assert.strictEqual(raised.payload.workOrders.length, 0);
  assert.strictEqual(await openWorkOrdersForSchedule(created.payload.pmSchedule.id), 0);

  // Deactivated schedules are out of the default listing and only returned on
  // request, the same includeInactive shape the register uses.
  const activeOnly = await getPmSchedules(admin.token, isolatedSite.id);
  assert.ok(!activeOnly.payload.pmSchedules.some((candidate) => candidate.id === created.payload.pmSchedule.id));
  const all = await getPmSchedules(admin.token, isolatedSite.id, '?includeInactive=true');
  assert.ok(all.payload.pmSchedules.some((candidate) => candidate.id === created.payload.pmSchedule.id));
});

// ---------------------------------------------------------------------------
// The raise sweep: lead time, copies, and never raising twice.
// ---------------------------------------------------------------------------

test('the raise honours lead_time_days: a schedule outside its window is left alone', async () => {
  const { site: isolatedSite, asset: soonAsset } = await insertIsolatedSite({ assetName: 'Soon Asset' });
  const laterAsset = await insertAsset(soonAsset.org_unit_id, { name: 'Later Asset' });
  const plan = await createPlan({ name: 'Lead Time Plan' });

  const soon = await postPmSchedule(admin.token, {
    assetId: soonAsset.id,
    jobPlanId: plan.id,
    intervalDays: 30,
    leadTimeDays: 3,
    nextDueOn: await dbDate(2)
  });
  const later = await postPmSchedule(admin.token, {
    assetId: laterAsset.id,
    jobPlanId: plan.id,
    intervalDays: 30,
    leadTimeDays: 3,
    nextDueOn: await dbDate(10)
  });

  const raised = await postRaise(admin.token, isolatedSite.id);
  assert.strictEqual(raised.response.status, 200);
  const raisedScheduleIds = raised.payload.workOrders.map((wo) => wo.pmScheduleId);
  assert.ok(raisedScheduleIds.includes(soon.payload.pmSchedule.id));
  assert.ok(!raisedScheduleIds.includes(later.payload.pmSchedule.id));
  assert.strictEqual(await openWorkOrdersForSchedule(later.payload.pmSchedule.id), 0);
});

test('a raised work order copies the plan tasks, carries the plan work_type and its pm_schedule_id', async () => {
  const { site: isolatedSite, asset } = await insertIsolatedSite({ assetName: 'Inspection Press' });
  const skill = await insertSkill({ name: 'Optical Alignment' });
  const plan = await createPlan({
    name: 'Inspection Plan',
    workType: 'inspection',
    tasks: [
      { stepNo: 1, instruction: 'Check belt tension', skillId: skill.id },
      { stepNo: 2, instruction: 'Record vibration reading' }
    ]
  });
  const created = await postPmSchedule(admin.token, {
    assetId: asset.id,
    jobPlanId: plan.id,
    intervalDays: 30,
    nextDueOn: await dbDate(-1)
  });

  const raised = await postRaise(admin.token, isolatedSite.id);
  assert.strictEqual(raised.response.status, 200);
  const workOrder = raised.payload.workOrders.find((wo) => wo.pmScheduleId === created.payload.pmSchedule.id);
  assert.ok(workOrder);

  assert.strictEqual(workOrder.status, 'approved');
  assert.strictEqual(workOrder.workType, 'inspection');
  assert.strictEqual(workOrder.pmScheduleId, created.payload.pmSchedule.id);
  assert.strictEqual(workOrder.tasks.length, 2);
  assert.deepStrictEqual(workOrder.tasks.map((task) => task.stepNo), [1, 2]);
  assert.strictEqual(workOrder.tasks[0].instruction, 'Check belt tension');
  assert.strictEqual(workOrder.tasks[0].skillName, 'Optical Alignment');
  assert.strictEqual(workOrder.tasks[0].status, 'pending');

  // They are COPIES, not references: the work_order_tasks rows really exist,
  // and revising the plan afterwards does not rewrite what the technician was
  // told to do.
  const { rows: copied } = await pool.query(
    `SELECT step_no, instruction, skill_id FROM work_order_tasks WHERE work_order_id = $1 ORDER BY step_no`,
    [workOrder.id]
  );
  assert.strictEqual(copied.length, 2);
  assert.strictEqual(copied[0].instruction, 'Check belt tension');
  assert.strictEqual(String(copied[0].skill_id), String(skill.id));

  await pool.query(
    `UPDATE job_plan_tasks SET instruction = 'Changed after the raise' WHERE job_plan_id = $1 AND step_no = 1`,
    [plan.id]
  );
  const reread = await getWorkOrderDetail(admin.token, workOrder.id);
  assert.strictEqual(reread.payload.workOrder.tasks[0].instruction, 'Check belt tension');
});

test('a schedule that already has an open work order is not raised again', async () => {
  const { site: isolatedSite, asset } = await insertIsolatedSite();
  const plan = await createPlan();
  const created = await postPmSchedule(admin.token, {
    assetId: asset.id,
    jobPlanId: plan.id,
    intervalDays: 30,
    nextDueOn: await dbDate(-3)
  });

  const first = await postRaise(admin.token, isolatedSite.id);
  assert.strictEqual(first.response.status, 200);
  assert.ok(first.payload.workOrders.some((wo) => wo.pmScheduleId === created.payload.pmSchedule.id));
  assert.strictEqual(await openWorkOrdersForSchedule(created.payload.pmSchedule.id), 1);

  const second = await postRaise(admin.token, isolatedSite.id);
  assert.strictEqual(second.response.status, 200);
  assert.strictEqual(second.payload.workOrders.length, 0);
  assert.strictEqual(await openWorkOrdersForSchedule(created.payload.pmSchedule.id), 1);
});

// ---------------------------------------------------------------------------
// Completing a PM work order advances the schedule, one anchor at a time.
// ---------------------------------------------------------------------------

test('completing a PM work order advances the schedule and stamps last_completed_on', async () => {
  const { site: isolatedSite, asset } = await insertIsolatedSite();
  const plan = await createPlan();
  const created = await postPmSchedule(admin.token, {
    assetId: asset.id,
    jobPlanId: plan.id,
    intervalDays: 30,
    anchor: 'completed',
    nextDueOn: await dbDate(-5)
  });

  const raised = await postRaise(admin.token, isolatedSite.id);
  const workOrder = raised.payload.workOrders.find((wo) => wo.pmScheduleId === created.payload.pmSchedule.id);

  await postStart(admin.token, workOrder.id);
  const completed = await postComplete(admin.token, workOrder.id, { note: 'Serviced late' });
  assert.strictEqual(completed.response.status, 200);

  const listed = await getPmSchedules(admin.token, isolatedSite.id);
  const schedule = listed.payload.pmSchedules.find((candidate) => candidate.id === created.payload.pmSchedule.id);
  // anchor='completed': the clock starts when the work was actually done, so
  // the late start does not matter — it rolls from today.
  assert.strictEqual(schedule.lastCompletedOn, await dbDate(0));
  assert.strictEqual(schedule.nextDueOn, await dbDate(30));
});

test("anchor='due' does not drift when the work ran late — the next date rolls from the original due date", async () => {
  const { site: isolatedSite, asset } = await insertIsolatedSite();
  const plan = await createPlan();
  const originalDue = await dbDate(-5);
  const created = await postPmSchedule(admin.token, {
    assetId: asset.id,
    jobPlanId: plan.id,
    intervalDays: 30,
    anchor: 'due',
    nextDueOn: originalDue
  });

  const raised = await postRaise(admin.token, isolatedSite.id);
  const workOrder = raised.payload.workOrders.find((wo) => wo.pmScheduleId === created.payload.pmSchedule.id);

  await postStart(admin.token, workOrder.id);
  const completed = await postComplete(admin.token, workOrder.id, { note: 'Statutory inspection, late' });
  assert.strictEqual(completed.response.status, 200);

  const listed = await getPmSchedules(admin.token, isolatedSite.id);
  const schedule = listed.payload.pmSchedules.find((candidate) => candidate.id === created.payload.pmSchedule.id);
  // anchor='due': the fixed cadence rolls from the ORIGINAL due date, so a job
  // done five days late is next due in 25 days, not 30 — it does not drift.
  assert.strictEqual(schedule.lastCompletedOn, await dbDate(0));
  assert.strictEqual(schedule.nextDueOn, await dbDate(25));
});

test('completing a work order with no PM schedule leaves every schedule alone', async () => {
  const { site: isolatedSite, asset } = await insertIsolatedSite();
  const plan = await createPlan();
  const created = await postPmSchedule(admin.token, {
    assetId: asset.id,
    jobPlanId: plan.id,
    intervalDays: 30,
    nextDueOn: await dbDate(20)
  });

  // A manually raised work order on the same Asset must not touch the
  // schedule when it completes.
  const manual = await fetch(`${base}/api/maintenance/work-orders`, {
    method: 'POST',
    headers: { ...admin.token, 'content-type': 'application/json' },
    body: JSON.stringify({ assetId: asset.id, summary: 'Manual job', workType: 'corrective', priority: 3 })
  });
  const manualPayload = await manual.json();
  insertedWorkOrderIds.push(manualPayload.workOrder.id);

  await postStart(admin.token, manualPayload.workOrder.id);
  const completed = await postComplete(admin.token, manualPayload.workOrder.id, { note: 'Done' });
  assert.strictEqual(completed.response.status, 200);

  const listed = await getPmSchedules(admin.token, isolatedSite.id);
  const schedule = listed.payload.pmSchedules.find((candidate) => candidate.id === created.payload.pmSchedule.id);
  assert.strictEqual(schedule.lastCompletedOn, null);
  assert.strictEqual(schedule.nextDueOn, await dbDate(20));
});

// ---------------------------------------------------------------------------
// Work order detail: tasks and their required Skill names.
// ---------------------------------------------------------------------------

test('the work order detail exposes a task required skillName, and an unknown id is a clean 404', async () => {
  const { site: isolatedSite, asset } = await insertIsolatedSite();
  const skill = await insertSkill({ name: 'Hydraulic Systems' });
  const plan = await createPlan({
    name: 'Detail Plan',
    tasks: [{ stepNo: 1, instruction: 'Change the filter', skillId: skill.id }]
  });
  await postPmSchedule(admin.token, {
    assetId: asset.id,
    jobPlanId: plan.id,
    intervalDays: 30,
    nextDueOn: await dbDate(-1)
  });
  const raised = await postRaise(admin.token, isolatedSite.id);
  const workOrder = raised.payload.workOrders[0];

  const detail = await getWorkOrderDetail(noGrantAccount.token, workOrder.id);
  assert.strictEqual(detail.response.status, 200);
  assert.strictEqual(detail.payload.workOrder.tasks[0].instruction, 'Change the filter');
  assert.strictEqual(detail.payload.workOrder.tasks[0].skillName, 'Hydraulic Systems');

  const unknown = await getWorkOrderDetail(admin.token, '999999999');
  assert.strictEqual(unknown.response.status, 404);
  assert.strictEqual(unknown.payload.message, 'Work order not found');

  const malformed = await getWorkOrderDetail(admin.token, 'not-an-id');
  assert.strictEqual(malformed.response.status, 404);
});

// ---------------------------------------------------------------------------
// Scope: writes need a WRITE Grant reaching the schedule's Asset.
// ---------------------------------------------------------------------------

test('a caller without write scope cannot create a schedule', async () => {
  const grantedAsset = await insertAsset(grantedLine.id, { name: 'Granted Asset' });
  const outsideAsset = await insertAsset(otherLine.id, { name: 'Outside Asset' });
  const plan = await createPlan();

  const readOnly = await postPmSchedule(readOnlyAccount.token, {
    assetId: grantedAsset.id,
    jobPlanId: plan.id,
    intervalDays: 30
  });
  assert.strictEqual(readOnly.response.status, 403);
  assert.strictEqual(readOnly.payload.message, "Outside the caller's granted Org Units");

  const sibling = await postPmSchedule(siblingWriter.token, {
    assetId: grantedAsset.id,
    jobPlanId: plan.id,
    intervalDays: 30
  });
  assert.strictEqual(sibling.response.status, 403);

  const noGrant = await postPmSchedule(noGrantAccount.token, {
    assetId: grantedAsset.id,
    jobPlanId: plan.id,
    intervalDays: 30
  });
  assert.strictEqual(noGrant.response.status, 403);

  // A malformed Asset is a 404 before scope is even asked.
  const missingAsset = await postPmSchedule(writerAccount.token, {
    assetId: 'not-an-id',
    jobPlanId: plan.id,
    intervalDays: 30
  });
  assert.strictEqual(missingAsset.response.status, 404);

  // The asset outside the caller's branch is visible to the read, but not
  // writable through it.
  const outside = await postPmSchedule(writerAccount.token, {
    assetId: outsideAsset.id,
    jobPlanId: plan.id,
    intervalDays: 30
  });
  assert.strictEqual(outside.response.status, 403);
});

test('a raise only raises schedules inside the caller Grants; admin reaches the rest', async () => {
  const isolatedSite = await insertSite();
  const unitA = await insertOrgUnit(isolatedSite.id, { name: 'Granted Line' });
  const unitB = await insertOrgUnit(isolatedSite.id, { name: 'Ungranted Line' });
  const assetB = await insertAsset(unitB.id, { name: 'Ungranted Asset' });

  const scopedWriter = await insertAccount();
  await insertGrant({ accountId: scopedWriter.id, orgUnitId: unitA.id, canWrite: true });

  const plan = await createPlan();
  const created = await postPmSchedule(admin.token, {
    assetId: assetB.id,
    jobPlanId: plan.id,
    intervalDays: 30,
    nextDueOn: await dbDate(-1)
  });

  // The caller's write Grant does not reach the schedule's Asset Org Unit, so
  // the sweep silently raises nothing for it rather than refusing.
  const refused = await postRaise(scopedWriter.token, isolatedSite.id);
  assert.strictEqual(refused.response.status, 200);
  assert.strictEqual(refused.payload.workOrders.length, 0);
  assert.strictEqual(await openWorkOrdersForSchedule(created.payload.pmSchedule.id), 0);

  // Admin holds a Grant reaching everywhere, so the same sweep raises it.
  const allowed = await postRaise(admin.token, isolatedSite.id);
  assert.strictEqual(allowed.response.status, 200);
  assert.ok(allowed.payload.workOrders.some((wo) => wo.pmScheduleId === created.payload.pmSchedule.id));
  assert.strictEqual(await openWorkOrdersForSchedule(created.payload.pmSchedule.id), 1);
});

test('a request with no bearer token is refused on the new surfaces', async () => {
  const plans = await fetch(`${base}/api/maintenance/job-plans`);
  assert.strictEqual(plans.status, 401);

  const schedules = await fetch(`${base}/api/maintenance/sites/${site.id}/pm-schedules`);
  assert.strictEqual(schedules.status, 401);

  const raise = await fetch(`${base}/api/maintenance/sites/${site.id}/pm-schedules/raise`, { method: 'POST' });
  assert.strictEqual(raise.status, 401);
});
