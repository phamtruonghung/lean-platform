/*
 * "Today" is the Site's local date, not the database's UTC date (ADR-0048).
 *
 * Wall-clock time cannot be frozen over HTTP, so these tests pick two Sites
 * whose local dates are never equal at any instant: Pacific/Kiritimati
 * (UTC+14) and Etc/GMT+12 (UTC-12) are 26 hours apart, so the east Site's date
 * is always one or two days ahead of the west Site's. A row dated at the west
 * Site's "today" is therefore due or late at the east Site and not at the
 * west Site, whatever time of day the suite runs - which is exactly the
 * difference a single database-wide CURRENT_DATE cannot show.
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
let admin;

const accountIds = [];
const siteIds = [];
const orgUnitIds = [];
const assetIds = [];
const actionIds = [];
const jobPlanIds = [];
const pmScheduleIds = [];
const workOrderIds = [];

let counter = 0;
function uniqueCode(prefix) {
  counter += 1;
  return `${prefix}${process.pid}${counter}`;
}

async function insertAdmin() {
  const subject = uniqueCode('acct');
  const { rows: [row] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status)
     VALUES ($1, 'Site Today Admin', 'admin', $2, TRUE, 'approved') RETURNING id`,
    [`${subject}@example.com`, subject]
  );
  accountIds.push(row.id);
  const token = await jwks.signToken(
    { sub: subject, email: `${subject}@example.com` },
    { issuer: ISSUER, audience: AUDIENCE }
  );
  return { id: row.id, token: { authorization: `Bearer ${token}` } };
}

// A Site in the given timezone with one Org Unit and one Asset.
async function insertSiteWithAsset(timezone) {
  const { rows: [site] } = await pool.query(
    `INSERT INTO sites (code, name, timezone) VALUES ($1, 'Site Today Site', $2) RETURNING id`,
    [uniqueCode('ST'), timezone]
  );
  siteIds.push(site.id);
  const { rows: [unit] } = await pool.query(
    `INSERT INTO org_units (site_id, code, name, unit_type) VALUES ($1, $2, 'Site Today Unit', 'area')
     RETURNING id`,
    [site.id, uniqueCode('OU')]
  );
  orgUnitIds.push(unit.id);
  const { rows: [asset] } = await pool.query(
    `INSERT INTO assets (org_unit_id, code, name, asset_type, criticality)
     VALUES ($1, $2, 'Site Today Asset', 'machine', 'high') RETURNING id`,
    [unit.id, uniqueCode('AS')]
  );
  assetIds.push(asset.id);
  return { siteId: site.id, orgUnitId: unit.id, assetId: asset.id };
}

// The local calendar date at a timezone right now, as YYYY-MM-DD.
async function localToday(timezone) {
  const { rows: [row] } = await pool.query(
    `SELECT to_char((now() AT TIME ZONE $1)::date, 'YYYY-MM-DD') AS d`,
    [timezone]
  );
  return row.d;
}

const EAST = 'Pacific/Kiritimati';
const WEST = 'Etc/GMT+12';

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
  admin = await insertAdmin();
});

test.after(async () => {
  await pool.query('DELETE FROM work_orders WHERE id = ANY($1)', [workOrderIds]);
  await pool.query('DELETE FROM work_orders WHERE pm_schedule_id = ANY($1)', [pmScheduleIds]);
  await pool.query('DELETE FROM pm_schedules WHERE id = ANY($1)', [pmScheduleIds]);
  await pool.query('DELETE FROM job_plans WHERE id = ANY($1)', [jobPlanIds]);
  await pool.query('DELETE FROM action_items WHERE id = ANY($1)', [actionIds]);
  await pool.query('DELETE FROM assets WHERE id = ANY($1)', [assetIds]);
  await pool.query('DELETE FROM app_users WHERE id = ANY($1)', [accountIds]);
  await pool.query('DELETE FROM org_units WHERE id = ANY($1)', [orgUnitIds]);
  await pool.query('DELETE FROM sites WHERE id = ANY($1)', [siteIds]);
  await new Promise((resolve) => server.close(resolve));
  await closePool();
  await jwks.close();
});

test('the two fixture timezones never share a local date', async () => {
  assert.notStrictEqual(await localToday(EAST), await localToday(WEST));
});

test('org_unit_today and employee_today answer with the Site local date, and UTC with no Site', async () => {
  const east = await insertSiteWithAsset(EAST);
  const { rows: [viaFunction] } = await pool.query(
    `SELECT to_char(org_unit_today($1), 'YYYY-MM-DD') AS d`,
    [east.orgUnitId]
  );
  assert.strictEqual(viaFunction.d, await localToday(EAST));

  const { rows: [noSite] } = await pool.query(
    `SELECT to_char(org_unit_today(-1), 'YYYY-MM-DD') AS d,
            to_char((now() AT TIME ZONE 'UTC')::date, 'YYYY-MM-DD') AS utc,
            to_char(employee_today(-1), 'YYYY-MM-DD') AS e`
  );
  assert.strictEqual(noSite.d, noSite.utc);
  assert.strictEqual(noSite.e, noSite.utc);
});

test('an Action due on the west Site date is overdue at the east Site and not at the west Site', async () => {
  const dueDate = await localToday(WEST);
  const results = {};
  for (const [label, timezone] of [['east', EAST], ['west', WEST]]) {
    const fixture = await insertSiteWithAsset(timezone);
    const { rows: [action] } = await pool.query(
      `INSERT INTO action_items (action_no, org_unit_id, title, action_type, status, due_date, priority)
       VALUES ($1, $2, 'Due on the west date', 'concern', 'open', $3::date, 3) RETURNING id`,
      [uniqueCode('AC-'), fixture.orgUnitId, dueDate]
    );
    actionIds.push(action.id);
    const response = await fetch(`${base}/api/actions/sites/${fixture.siteId}/actions`, {
      headers: admin.token
    });
    assert.strictEqual(response.status, 200);
    const payload = await response.json();
    assert.strictEqual(payload.actions.length, 1);
    results[label] = payload.actions[0];
  }

  assert.strictEqual(results.east.isOverdue, true);
  assert.ok(results.east.daysOverdue >= 1);
  assert.strictEqual(results.west.isOverdue, false);
  assert.strictEqual(results.west.daysOverdue, null);
});

test('v_open_actions agrees with the register about which Site an Action is late in', async () => {
  const dueDate = await localToday(WEST);
  const east = await insertSiteWithAsset(EAST);
  const west = await insertSiteWithAsset(WEST);
  for (const fixture of [east, west]) {
    const { rows: [action] } = await pool.query(
      `INSERT INTO action_items (action_no, org_unit_id, title, action_type, status, due_date, priority)
       VALUES ($1, $2, 'View agrees', 'concern', 'open', $3::date, 3) RETURNING id`,
      [uniqueCode('AC-'), fixture.orgUnitId, dueDate]
    );
    actionIds.push(action.id);
  }
  const { rows } = await pool.query(
    `SELECT org_unit_id, is_overdue FROM v_open_actions WHERE org_unit_id = ANY($1)`,
    [[east.orgUnitId, west.orgUnitId]]
  );
  const byUnit = new Map(rows.map((row) => [String(row.org_unit_id), row.is_overdue]));
  assert.strictEqual(byUnit.get(String(east.orgUnitId)), true);
  assert.strictEqual(byUnit.get(String(west.orgUnitId)), false);
});

test('a PM due on the east Site date is due at the east Site and not yet at the west Site', async () => {
  const dueOn = await localToday(EAST);
  const { rows: [plan] } = await pool.query(
    `INSERT INTO job_plans (code, name, work_type) VALUES ($1, 'Site Today Plan', 'preventive') RETURNING id`,
    [uniqueCode('JP')]
  );
  jobPlanIds.push(plan.id);

  const results = {};
  for (const [label, timezone] of [['east', EAST], ['west', WEST]]) {
    const fixture = await insertSiteWithAsset(timezone);
    const { rows: [schedule] } = await pool.query(
      `INSERT INTO pm_schedules
         (code, name, asset_id, job_plan_id, interval_days, lead_time_days, next_due_on)
       VALUES ($1, 'Site Today PM', $2, $3, 30, 0, $4::date) RETURNING id`,
      [uniqueCode('PM'), fixture.assetId, plan.id, dueOn]
    );
    pmScheduleIds.push(schedule.id);

    const listed = await fetch(
      `${base}/api/maintenance/sites/${fixture.siteId}/pm-schedules`,
      { headers: admin.token }
    );
    assert.strictEqual(listed.status, 200);
    const listedPayload = await listed.json();
    const daysUntilDue = listedPayload.pmSchedules.find((s) => s.id === String(schedule.id)).daysUntilDue;

    const raised = await fetch(
      `${base}/api/maintenance/sites/${fixture.siteId}/pm-schedules/raise`,
      { method: 'POST', headers: admin.token }
    );
    assert.strictEqual(raised.status, 200);
    const raisedPayload = await raised.json();
    for (const workOrder of raisedPayload.workOrders) workOrderIds.push(workOrder.id);

    const { rows: [view] } = await pool.query(
      `SELECT due_by_date, days_until_due FROM v_pm_due WHERE pm_schedule_id = $1`,
      [schedule.id]
    );
    results[label] = {
      daysUntilDue,
      raised: raisedPayload.workOrders.some((wo) => wo.pmScheduleId === String(schedule.id)),
      viewDue: view.due_by_date,
      viewDays: view.days_until_due
    };
  }

  assert.strictEqual(results.east.daysUntilDue, 0);
  assert.strictEqual(results.east.raised, true);
  assert.strictEqual(results.east.viewDue, true);
  assert.strictEqual(results.east.viewDays, 0);

  assert.ok(results.west.daysUntilDue >= 1);
  assert.strictEqual(results.west.raised, false);
  assert.strictEqual(results.west.viewDue, false);
  assert.ok(results.west.viewDays >= 1);
});

test('a new PM schedule without nextDueOn counts its interval from the Site local date', async () => {
  const east = await insertSiteWithAsset(EAST);
  const { rows: [plan] } = await pool.query(
    `INSERT INTO job_plans (code, name, work_type) VALUES ($1, 'Site Today Plan 2', 'preventive') RETURNING id`,
    [uniqueCode('JP')]
  );
  jobPlanIds.push(plan.id);
  const response = await fetch(`${base}/api/maintenance/pm-schedules`, {
    method: 'POST',
    headers: { ...admin.token, 'content-type': 'application/json' },
    body: JSON.stringify({ assetId: east.assetId, jobPlanId: plan.id, intervalDays: 10 })
  });
  const payload = await response.json();
  assert.strictEqual(response.status, 201, JSON.stringify(payload));
  pmScheduleIds.push(payload.pmSchedule.id);
  assert.strictEqual(payload.pmSchedule.daysUntilDue, 10);
  const { rows: [expected] } = await pool.query(
    `SELECT to_char((now() AT TIME ZONE $1)::date + 10, 'YYYY-MM-DD') AS d`,
    [EAST]
  );
  assert.strictEqual(payload.pmSchedule.nextDueOn, expected.d);
});

test('a qualification expiring on the east default Org Unit date has lapsed there and not at the west Site', async () => {
  const expiresOn = await localToday(WEST);
  const results = {};
  for (const [label, timezone] of [['east', EAST], ['west', WEST]]) {
    const fixture = await insertSiteWithAsset(timezone);
    const { rows: [employee] } = await pool.query(
      `INSERT INTO employees (employee_no, first_name, last_name, default_org_unit_id)
       VALUES ($1, 'Site', 'Today', $2) RETURNING id`,
      [uniqueCode('EMP'), fixture.orgUnitId]
    );
    const { rows: [skill] } = await pool.query(
      `INSERT INTO skills (code, name) VALUES ($1, 'Site Today Skill') RETURNING id`,
      [uniqueCode('SK')]
    );
    await pool.query(
      `INSERT INTO employee_skills (employee_id, skill_id, proficiency_level, assessed_on, expires_on)
       VALUES ($1, $2, 3, $3::date - 30, $3::date)`,
      [employee.id, skill.id, expiresOn]
    );
    const { rows: [row] } = await pool.query(
      `SELECT employee_today($1) = $2::date AS same_day, ($2::date > employee_today($1)) AS still_current`,
      [employee.id, expiresOn]
    );
    results[label] = row;
    await pool.query('DELETE FROM employee_skills WHERE employee_id = $1', [employee.id]);
    await pool.query('DELETE FROM skills WHERE id = $1', [skill.id]);
    await pool.query('DELETE FROM employees WHERE id = $1', [employee.id]);
  }
  // Expires on the west date: that is today at the west Site (expiry is
  // exclusive, so no longer current), and already in the past at the east Site.
  assert.strictEqual(results.west.same_day, true);
  assert.strictEqual(results.east.same_day, false);
  assert.strictEqual(results.east.still_current, false);
});

test('completing a PM Work order stamps last_completed_on and rolls next-due from the Site local date', async () => {
  const { rows: [plan] } = await pool.query(
    `INSERT INTO job_plans (code, name, work_type) VALUES ($1, 'Site Today Plan 3', 'preventive') RETURNING id`,
    [uniqueCode('JP')]
  );
  jobPlanIds.push(plan.id);

  const results = {};
  for (const [label, timezone] of [['east', EAST], ['west', WEST]]) {
    const fixture = await insertSiteWithAsset(timezone);
    const scheduleIds = [];
    for (const anchor of ['completed', 'due']) {
      // No next_due_on: the 'due' anchor falls back to today, the 'completed'
      // anchor rolls from today - both are the Site local date.
      const { rows: [schedule] } = await pool.query(
        `INSERT INTO pm_schedules (code, name, asset_id, job_plan_id, interval_days, lead_time_days, anchor)
         VALUES ($1, 'Site Today PM', $2, $3, 30, 0, $4) RETURNING id`,
        [uniqueCode('PM'), fixture.assetId, plan.id, anchor]
      );
      pmScheduleIds.push(schedule.id);
      scheduleIds.push(schedule.id);

      const { rows: [workOrder] } = await pool.query(
        `INSERT INTO work_orders
           (work_order_no, asset_id, summary, work_type, status, actual_start, pm_schedule_id)
         VALUES ($1, $2, 'Site Today PM job', 'preventive', 'in_progress', now(), $3) RETURNING id`,
        [uniqueCode('WO-'), fixture.assetId, schedule.id]
      );
      workOrderIds.push(workOrder.id);
      const response = await fetch(`${base}/api/maintenance/work-orders/${workOrder.id}/complete`, {
        method: 'POST',
        headers: { ...admin.token, 'content-type': 'application/json' },
        body: JSON.stringify({ note: 'done' })
      });
      assert.strictEqual(response.status, 200, await response.clone().text());
    }
    const { rows } = await pool.query(
      `SELECT anchor,
              to_char(last_completed_on, 'YYYY-MM-DD') AS last_completed_on,
              to_char(next_due_on, 'YYYY-MM-DD') AS next_due_on
         FROM pm_schedules WHERE id = ANY($1)`,
      [scheduleIds]
    );
    const { rows: [plus30] } = await pool.query(
      `SELECT to_char((now() AT TIME ZONE $1)::date + 30, 'YYYY-MM-DD') AS d`,
      [timezone]
    );
    results[label] = { today: await localToday(timezone), rows, plus30: plus30.d };
  }

  for (const label of ['east', 'west']) {
    const { today, rows, plus30 } = results[label];
    assert.strictEqual(rows.length, 2);
    for (const row of rows) {
      assert.strictEqual(row.last_completed_on, today, `${label} ${row.anchor} last_completed_on`);
      assert.strictEqual(row.next_due_on, plus30, `${label} ${row.anchor} next_due_on`);
    }
  }
  // The two Sites are on different calendar dates, so a single UTC "today"
  // could not have served both.
  assert.notStrictEqual(results.east.today, results.west.today);
});
