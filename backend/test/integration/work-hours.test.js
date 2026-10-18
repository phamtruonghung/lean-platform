/*
 * The per-Employee worked-hours summary (issue #263), over HTTP: one
 * Employee's confirmed scheduled/worked/overtime minutes across a date
 * window, day by day plus totals, built only from *confirmed* attendance
 * sheets. Same seam as
 * attendance.test.js — a real database and a real (locally issued) JWKS —
 * since it reads the same `attendance_records` / `attendance_sheets` /
 * `shift_instances` rows that file's tests already write, and it uses the
 * exact same shape of setup: a Site, an Org Unit, a shift definition, shift
 * instances, an Employee to be pre-filled onto the roster, and a recording
 * Account holding an edit Grant reaching the Org Unit so it may open and
 * confirm the sheets.
 *
 * This file deliberately does not truncate any shared table (attendance
 * does not truncate either — see that file's own header): every row it
 * inserts, in the same tables, is deleted again in `test.after()` in the
 * same children-before-parents order.
 *
 * Needs a database with every migration applied. Set DATABASE_URL first —
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
let admin;
let adminToken;
const insertedSiteIds = [];
const insertedOrgUnitIds = [];
const insertedCrewIds = [];
const insertedShiftDefinitionIds = [];
const insertedShiftInstanceIds = [];
const insertedEmployeeIds = [];
const insertedAccountIds = [];

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

async function json(response) {
  return { status: response.status, body: await response.json() };
}

async function insertAccount({ role = 'operator', grants = [] } = {}) {
  const subject = uniqueCode('whacct');
  const { rows: [account] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status)
     VALUES ($1, 'Work Hours Test Account', $2, $3, TRUE, 'approved') RETURNING id`,
    [`${subject}@example.com`, role, subject]
  );
  insertedAccountIds.push(account.id);

  for (const grant of grants) {
    await pool.query(
      `INSERT INTO app_user_org_units (app_user_id, org_unit_id, can_write)
       VALUES ($1, $2, $3)`,
      [account.id, grant.orgUnitId, grant.write ?? true]
    );
  }

  return { id: account.id, token: await authHeader(subject) };
}

async function insertSite({ timezone = 'Asia/Ho_Chi_Minh', name = 'Work Hours Test Site' } = {}) {
  const { rows: [site] } = await pool.query(
    `INSERT INTO sites (code, name, timezone) VALUES ($1, $2, $3) RETURNING id, code, name`,
    [uniqueCode('WHS'), name, timezone]
  );
  insertedSiteIds.push(site.id);
  return site;
}

async function insertOrgUnit(siteId, { parentId = null, unitType = 'area', name = 'Work Hours Unit' } = {}) {
  const { rows: [orgUnit] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, $2, $3, $4, $5) RETURNING id, code, name, path`,
    [siteId, parentId, uniqueCode('WHOU'), name, unitType]
  );
  insertedOrgUnitIds.push(orgUnit.id);
  return orgUnit;
}

async function insertShiftDefinition(siteId, {
  durationMinutes = 480,
  breakMinutes = 30,
  startTime = '06:00'
} = {}) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO shift_definitions (site_id, code, name, start_time, duration_minutes, break_minutes)
     VALUES ($1, $2, 'Day shift', $3, $4, $5)
     RETURNING id, duration_minutes, break_minutes`,
    [siteId, uniqueCode('WHSD'), startTime, durationMinutes, breakMinutes]
  );
  insertedShiftDefinitionIds.push(row.id);
  return { id: row.id, durationMinutes: row.duration_minutes, breakMinutes: row.break_minutes };
}

async function insertShiftInstance(site, orgUnit, shiftDefinition, {
  crewId = null,
  productionDate = '2026-05-04',
  startsAt = '2026-05-04T06:00:00Z',
  endsAt = '2026-05-04T14:00:00Z'
} = {}) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO shift_instances
       (site_id, org_unit_id, shift_definition_id, crew_id, production_date,
        starts_at, ends_at, planned_production_minutes)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
     RETURNING id, site_id, org_unit_id, crew_id`,
    [
      site.id, orgUnit.id, shiftDefinition.id, crewId, productionDate, startsAt, endsAt,
      shiftDefinition.durationMinutes - shiftDefinition.breakMinutes
    ]
  );
  insertedShiftInstanceIds.push(row.id);
  return row;
}

// An Employee on the Org Unit roster (default_org_unit_id), so opening a
// sheet for a crew-less shift instance pre-fills them onto it (ADR-0040's
// Org-Unit fallback), the same shape attendance.test.js's own no-crew tests
// rely on.
async function insertEmployee({ isActive = true, defaultOrgUnitId = null } = {}) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO employees (employee_no, first_name, last_name, is_active, default_org_unit_id)
     VALUES ($1, 'WH', 'Employee', $2, $3) RETURNING id, employee_no, display_name`,
    [uniqueCode('WHEMP'), isActive, defaultOrgUnitId]
  );
  insertedEmployeeIds.push(row.id);
  return row;
}

async function getSheet(token, shiftInstanceId) {
  const response = await fetch(`${base}/api/people/shift-instances/${shiftInstanceId}/attendance-sheet`, {
    headers: token
  });
  return json(response);
}

async function confirmSheet(token, shiftInstanceId) {
  const response = await fetch(
    `${base}/api/people/shift-instances/${shiftInstanceId}/attendance-sheet/confirm`,
    { method: 'POST', headers: token }
  );
  return json(response);
}

async function updateRecord(token, shiftInstanceId, recordId, body) {
  const response = await fetch(
    `${base}/api/people/shift-instances/${shiftInstanceId}/attendance-records/${recordId}`,
    {
      method: 'PATCH',
      headers: { ...token, 'content-type': 'application/json' },
      body: JSON.stringify(body)
    }
  );
  return json(response);
}

async function workHours(token, employeeId, { from, to } = {}) {
  const params = new URLSearchParams();
  if (from !== undefined) params.set('from', from);
  if (to !== undefined) params.set('to', to);
  const qs = params.toString();
  const response = await fetch(`${base}/api/people/employees/${employeeId}/work-hours${qs ? `?${qs}` : ''}`, {
    headers: token
  });
  return json(response);
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

  admin = await insertAccount({ role: 'admin' });
  adminToken = admin.token;
});

test.after(async () => {
  // Children before parents, the same order attendance.test.js's own
  // test.after() follows: attendance rows first, then shift instances and
  // definitions, then employees, crews and Org Units, Sites last.
  await pool.query('DELETE FROM attendance_records WHERE shift_instance_id = ANY($1)', [
    insertedShiftInstanceIds
  ]);
  await pool.query('DELETE FROM attendance_sheets WHERE shift_instance_id = ANY($1)', [
    insertedShiftInstanceIds
  ]);
  await pool.query('DELETE FROM shift_instances WHERE id = ANY($1)', [insertedShiftInstanceIds]);
  await pool.query('DELETE FROM shift_definitions WHERE id = ANY($1)', [insertedShiftDefinitionIds]);
  await pool.query('DELETE FROM employees WHERE id = ANY($1)', [insertedEmployeeIds]);
  await pool.query('DELETE FROM app_user_org_units WHERE app_user_id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM app_users WHERE id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM org_units WHERE id = ANY($1)', [insertedOrgUnitIds]);
  await pool.query('DELETE FROM sites WHERE id = ANY($1)', [insertedSiteIds]);
  await new Promise((resolve) => server.close(resolve));
  await closePool();
  await jwks.close();
});

// A day of work, pre-filled and confirmed: returns the ground plus the
// Employee's attendance record id on that sheet's roster so a test may
// correct it.
async function confirmOneDay(site, unit, shiftDefinition, employee, {
  productionDate, startsAt, endsAt, worked = 450
} = {}) {
  const shiftInstance = await insertShiftInstance(site, unit, shiftDefinition, { productionDate, startsAt, endsAt });
  const recorder = await insertAccount({ grants: [{ orgUnitId: unit.id }] });

  const opened = await getSheet(recorder.token, shiftInstance.id);
  assert.equal(opened.status, 200);
  const record = opened.body.records.find((r) => r.employeeId === employee.id);
  assert.ok(record, 'the Employee should be pre-filled onto the roster');

  if (worked !== record.workedMinutes) {
    await updateRecord(recorder.token, shiftInstance.id, record.id, { workedMinutes: worked });
  }

  const confirmed = await confirmSheet(recorder.token, shiftInstance.id);
  assert.equal(confirmed.status, 200);
  return { shiftInstance, recorder, recordId: record.id };
}

test('it sums a single confirmed day of work into that day and the totals', async () => {
  const site = await insertSite();
  const unit = await insertOrgUnit(site.id);
  const shiftDefinition = await insertShiftDefinition(site.id);
  const employee = await insertEmployee({ defaultOrgUnitId: unit.id });

  await confirmOneDay(site, unit, shiftDefinition, employee, {
    productionDate: '2026-05-04',
    startsAt: '2026-05-04T06:00:00Z',
    endsAt: '2026-05-04T14:00:00Z',
    worked: 480
  });

  const { status, body } = await workHours(adminToken, employee.id, { from: '2026-05-01', to: '2026-05-31' });
  assert.equal(status, 200);
  assert.equal(body.days.length, 1);
  assert.deepEqual(body.days[0], {
    date: '2026-05-04',
    scheduledMinutes: 450,
    workedMinutes: 480,
    overtimeMinutes: 0
  });
  assert.deepEqual(body.totals, { scheduledMinutes: 450, workedMinutes: 480, overtimeMinutes: 0 });
});

test('it sums confirmed minutes across every shift in a window, one row per day', async () => {
  const site = await insertSite();
  const unit = await insertOrgUnit(site.id);
  const shiftDefinition = await insertShiftDefinition(site.id);
  const employee = await insertEmployee({ defaultOrgUnitId: unit.id });

  await confirmOneDay(site, unit, shiftDefinition, employee, {
    productionDate: '2026-05-04', startsAt: '2026-05-04T06:00:00Z', endsAt: '2026-05-04T14:00:00Z', worked: 480
  });
  const second = await confirmOneDay(site, unit, shiftDefinition, employee, {
    productionDate: '2026-05-05', startsAt: '2026-05-05T06:00:00Z', endsAt: '2026-05-05T14:00:00Z', worked: 480
  });
  // Add overtime on the second day: 480 -> 540 worked with 60 overtime.
  await updateRecord(second.recorder.token, second.shiftInstance.id, second.recordId, { workedMinutes: 540, overtimeMinutes: 60 });

  const { status, body } = await workHours(adminToken, employee.id, { from: '2026-05-01', to: '2026-05-31' });
  assert.equal(status, 200);
  assert.equal(body.days.length, 2);
  assert.deepEqual(body.days.map((d) => d.date), ['2026-05-04', '2026-05-05']);
  assert.equal(body.days[1].workedMinutes, 540);
  assert.equal(body.days[1].overtimeMinutes, 60);
  assert.deepEqual(body.totals, { scheduledMinutes: 900, workedMinutes: 1020, overtimeMinutes: 60 });
});

test('an unconfirmed sheet is not counted, and a day with no confirmed sheet is absent, never a zero', async () => {
  const site = await insertSite();
  const unit = await insertOrgUnit(site.id);
  const shiftDefinition = await insertShiftDefinition(site.id);
  const employee = await insertEmployee({ defaultOrgUnitId: unit.id });

  // Day 1: opened AND confirmed.
  await confirmOneDay(site, unit, shiftDefinition, employee, {
    productionDate: '2026-05-04', startsAt: '2026-05-04T06:00:00Z', endsAt: '2026-05-04T14:00:00Z', worked: 450
  });
  // Day 2: opened but never confirmed.
  const recorder = await insertAccount({ grants: [{ orgUnitId: unit.id }] });
  const openOnlyShift = await insertShiftInstance(site, unit, shiftDefinition, {
    productionDate: '2026-05-05', startsAt: '2026-05-05T06:00:00Z', endsAt: '2026-05-05T14:00:00Z'
  });
  await getSheet(recorder.token, openOnlyShift.id);

  const { status, body } = await workHours(adminToken, employee.id, { from: '2026-05-01', to: '2026-05-31' });
  assert.equal(status, 200);
  assert.equal(body.days.length, 1);
  assert.equal(body.days[0].date, '2026-05-04');
  assert.deepEqual(body.totals, { scheduledMinutes: 450, workedMinutes: 450, overtimeMinutes: 0 });
});

test('the date window filters which confirmed days are included', async () => {
  const site = await insertSite();
  const unit = await insertOrgUnit(site.id);
  const shiftDefinition = await insertShiftDefinition(site.id);
  const employee = await insertEmployee({ defaultOrgUnitId: unit.id });

  await confirmOneDay(site, unit, shiftDefinition, employee, {
    productionDate: '2026-05-04', startsAt: '2026-05-04T06:00:00Z', endsAt: '2026-05-04T14:00:00Z'
  });
  await confirmOneDay(site, unit, shiftDefinition, employee, {
    productionDate: '2026-05-06', startsAt: '2026-05-06T06:00:00Z', endsAt: '2026-05-06T14:00:00Z'
  });

  const { status, body } = await workHours(adminToken, employee.id, { from: '2026-05-05', to: '2026-05-31' });
  assert.equal(status, 200);
  assert.equal(body.days.length, 1);
  assert.equal(body.days[0].date, '2026-05-06');
});

test('the window is optional: no from/to returns every confirmed day', async () => {
  const site = await insertSite();
  const unit = await insertOrgUnit(site.id);
  const shiftDefinition = await insertShiftDefinition(site.id);
  const employee = await insertEmployee({ defaultOrgUnitId: unit.id });

  await confirmOneDay(site, unit, shiftDefinition, employee, {
    productionDate: '2026-05-04', startsAt: '2026-05-04T06:00:00Z', endsAt: '2026-05-04T14:00:00Z'
  });

  const { status, body } = await workHours(adminToken, employee.id);
  assert.equal(status, 200);
  assert.equal(body.days.length, 1);
  assert.equal(body.days[0].date, '2026-05-04');
});

test('a malformed date in the window is a 400, and an unknown Employee is a 404', async () => {
  const site = await insertSite();
  const unit = await insertOrgUnit(site.id);
  const employee = await insertEmployee({ defaultOrgUnitId: unit.id });

  const badDate = await workHours(adminToken, employee.id, { from: 'not-a-date' });
  assert.equal(badDate.status, 400);

  const unknown = await workHours(adminToken, '999999999');
  assert.equal(unknown.status, 404);
});