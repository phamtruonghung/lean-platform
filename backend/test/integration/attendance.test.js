/*
 * The attendance sheet over HTTP (issue #249), against a real database and a
 * real (locally issued) JWKS — the same seam safety-incidents.test.js uses,
 * and this file's own scaffolding mirrors it closely.
 *
 * `generate_shift_instances` (the baseline's own calendar generator) never
 * sets `crew_id` — see migrations/1756000000000_baseline.js's own function
 * body — so testing the crew-pre-fill branch needs a shift instance built by
 * hand, the same way this file builds every shift instance it uses: directly
 * against `shift_instances`, never through the generator, for full control
 * over `crew_id`, `org_unit_id` and the shift's own timing.
 *
 * This file builds its own Sites, Org Units, Crews, Employees, shift
 * definitions and shift instances directly against the database, and
 * everything it inserts is deleted again in `test.after()`, in dependency
 * order.
 *
 * Needs a database with every migration applied. Set DATABASE_URL first —
 * see AGENTS.md §3.
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
const insertedCrewIds = [];
const insertedEmployeeIds = [];
const insertedShiftDefinitionIds = [];
const insertedShiftInstanceIds = [];

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

// `grants` are `{ orgUnitId, write }` pairs; `write` defaults to true, since
// most of this file's Accounts are recording rather than merely reading.
async function insertAccount({ role = 'operator', grants = [] } = {}) {
  const subject = uniqueCode('atacct');
  const { rows: [account] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status)
     VALUES ($1, 'Attendance Test Account', $2, $3, TRUE, 'approved') RETURNING id`,
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

async function insertSite({ timezone = 'Asia/Ho_Chi_Minh', name = 'Attendance Test Site' } = {}) {
  const { rows: [site] } = await pool.query(
    `INSERT INTO sites (code, name, timezone) VALUES ($1, $2, $3) RETURNING id, code, name`,
    [uniqueCode('ATS'), name, timezone]
  );
  insertedSiteIds.push(site.id);
  return site;
}

async function insertOrgUnit(siteId, { parentId = null, unitType = 'area', name = 'Attendance Unit' } = {}) {
  const { rows: [orgUnit] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, $2, $3, $4, $5) RETURNING id, code, name, path`,
    [siteId, parentId, uniqueCode('ATOU'), name, unitType]
  );
  insertedOrgUnitIds.push(orgUnit.id);
  return orgUnit;
}

async function insertCrew(siteId, { name = 'Crew A' } = {}) {
  const { rows: [crew] } = await pool.query(
    `INSERT INTO crews (site_id, code, name) VALUES ($1, $2, $3) RETURNING id`,
    [siteId, uniqueCode('ATCR'), name]
  );
  insertedCrewIds.push(crew.id);
  return crew;
}

async function insertEmployee({ isActive = true, defaultCrewId = null, defaultOrgUnitId = null } = {}) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO employees (employee_no, first_name, last_name, is_active, default_crew_id, default_org_unit_id)
     VALUES ($1, 'Att', 'Employee', $2, $3, $4) RETURNING id, display_name, is_active`,
    [uniqueCode('ATEMP'), isActive, defaultCrewId, defaultOrgUnitId]
  );
  insertedEmployeeIds.push(row.id);
  return row;
}

// duration_minutes 480, break_minutes 30 by default — every "minutes
// defaulting to the duration minus breaks" assertion in this file expects
// 450 unless a test overrides these.
async function insertShiftDefinition(siteId, {
  durationMinutes = 480,
  breakMinutes = 30,
  startTime = '06:00'
} = {}) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO shift_definitions (site_id, code, name, start_time, duration_minutes, break_minutes)
     VALUES ($1, $2, 'Day shift', $3, $4, $5)
     RETURNING id, duration_minutes, break_minutes`,
    [siteId, uniqueCode('ATSD'), startTime, durationMinutes, breakMinutes]
  );
  insertedShiftDefinitionIds.push(row.id);
  return { id: row.id, durationMinutes: row.duration_minutes, breakMinutes: row.break_minutes };
}

// Built by hand rather than through `generate_shift_instances` — see this
// file's own header for why: the generator never sets crew_id.
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

async function addStandIn(token, shiftInstanceId, body) {
  const response = await fetch(`${base}/api/people/shift-instances/${shiftInstanceId}/attendance-records`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
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

async function removeRecord(token, shiftInstanceId, recordId) {
  const response = await fetch(
    `${base}/api/people/shift-instances/${shiftInstanceId}/attendance-records/${recordId}`,
    { method: 'DELETE', headers: token }
  );
  return response.status;
}

async function listAbsenceReasons(token) {
  const response = await fetch(`${base}/api/people/absence-reasons`, { headers: token });
  return json(response);
}

async function listShiftInstances(token, orgUnitId, date) {
  const response = await fetch(
    `${base}/api/people/org-units/${orgUnitId}/shift-instances?date=${date}`,
    { headers: token }
  );
  return json(response);
}

async function listAttendanceToConfirm(token, { orgUnitId, from, to } = {}) {
  const params = new URLSearchParams();
  if (orgUnitId !== undefined) params.set('orgUnitId', orgUnitId);
  if (from !== undefined) params.set('from', from);
  if (to !== undefined) params.set('to', to);
  const qs = params.toString();
  const response = await fetch(`${base}/api/people/attendance-to-confirm${qs ? `?${qs}` : ''}`, {
    headers: token
  });
  return json(response);
}

// A whole scenario's ground: a Site, one Org Unit, a shift definition and a
// shift instance at it, plus a recording Account holding an edit Grant
// reaching the Org Unit. `crewId` is passed straight through to the shift
// instance, so the caller decides which pre-fill branch it exercises.
async function makeGround({ crewId = null } = {}) {
  const site = await insertSite();
  const unit = await insertOrgUnit(site.id);
  const shiftDefinition = await insertShiftDefinition(site.id);
  const shiftInstance = await insertShiftInstance(site, unit, shiftDefinition, { crewId });
  const recorder = await insertAccount({ grants: [{ orgUnitId: unit.id }] });
  return { site, unit, shiftDefinition, shiftInstance, recorder };
}

let admin;
let adminToken;

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
  // Children before parents. attendance_records/attendance_sheets both
  // reference shift_instances, which references org_units and
  // shift_definitions, which reference sites; employees reference crews and
  // org_units.
  await pool.query('DELETE FROM attendance_records WHERE shift_instance_id = ANY($1)', [
    insertedShiftInstanceIds
  ]);
  await pool.query('DELETE FROM attendance_sheets WHERE shift_instance_id = ANY($1)', [
    insertedShiftInstanceIds
  ]);
  await pool.query('DELETE FROM shift_instances WHERE id = ANY($1)', [insertedShiftInstanceIds]);
  await pool.query('DELETE FROM shift_definitions WHERE id = ANY($1)', [insertedShiftDefinitionIds]);
  await pool.query('DELETE FROM employees WHERE id = ANY($1)', [insertedEmployeeIds]);
  await pool.query('DELETE FROM crews WHERE id = ANY($1)', [insertedCrewIds]);
  await pool.query('DELETE FROM app_user_org_units WHERE app_user_id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM app_users WHERE id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM org_units WHERE id = ANY($1)', [insertedOrgUnitIds]);
  await pool.query('DELETE FROM sites WHERE id = ANY($1)', [insertedSiteIds]);
  await new Promise((resolve) => server.close(resolve));
  await closePool();
  await jwks.close();
});

// ---------------------------------------------------------------------------
// 1. Pre-fill: crew, the Org-Unit fallback, and running once
// ---------------------------------------------------------------------------

test('opening a sheet pre-fills it from the crew roster, with minutes defaulting to duration minus breaks', async () => {
  const site = await insertSite();
  const unit = await insertOrgUnit(site.id);
  const shiftDefinition = await insertShiftDefinition(site.id);
  const crew = await insertCrew(site.id);
  const shiftInstance = await insertShiftInstance(site, unit, shiftDefinition, { crewId: crew.id });
  const recorder = await insertAccount({ grants: [{ orgUnitId: unit.id }] });

  const inCrew = await insertEmployee({ defaultCrewId: crew.id });
  // Same Org Unit, but not in the crew — must NOT be pre-filled once a crew
  // is set on the shift instance (ADR-0040's fallback only applies when
  // there is no crew at all).
  await insertEmployee({ defaultOrgUnitId: unit.id });

  const { status, body } = await getSheet(recorder.token, shiftInstance.id);
  assert.strictEqual(status, 200, JSON.stringify(body));
  assert.strictEqual(body.records.length, 1, JSON.stringify(body.records));
  const [row] = body.records;
  assert.strictEqual(row.employeeId, inCrew.id);
  assert.strictEqual(row.attendanceStatus, 'present');
  assert.strictEqual(row.scheduledMinutes, 450); // 480 - 30
  assert.strictEqual(row.workedMinutes, 450);
  assert.strictEqual(row.overtimeMinutes, 0);
});

test('when the shift instance has no crew, opening the sheet falls back to the Org Unit roster', async () => {
  const { unit, shiftInstance, recorder } = await makeGround({ crewId: null });

  const inUnit = await insertEmployee({ defaultOrgUnitId: unit.id });
  const otherCrew = await insertCrew((await insertSite()).id);
  await insertEmployee({ defaultCrewId: otherCrew.id }); // must not appear: no crew on the shift, and not in this Org Unit

  const { status, body } = await getSheet(recorder.token, shiftInstance.id);
  assert.strictEqual(status, 200, JSON.stringify(body));
  assert.strictEqual(body.records.length, 1, JSON.stringify(body.records));
  assert.strictEqual(body.records[0].employeeId, inUnit.id);
});

test('a departed Employee is never pre-filled', async () => {
  const { unit, shiftInstance, recorder } = await makeGround({});
  await insertEmployee({ defaultOrgUnitId: unit.id, isActive: false });

  const { body } = await getSheet(recorder.token, shiftInstance.id);
  assert.strictEqual(body.records.length, 0, JSON.stringify(body.records));
});

test('opening the sheet a second time does not pre-fill it again, even after every row is removed', async () => {
  const { unit, shiftInstance, recorder } = await makeGround({});
  await insertEmployee({ defaultOrgUnitId: unit.id });

  const first = await getSheet(recorder.token, shiftInstance.id);
  assert.strictEqual(first.body.records.length, 1);

  await removeRecord(recorder.token, shiftInstance.id, first.body.records[0].id);

  const second = await getSheet(recorder.token, shiftInstance.id);
  assert.strictEqual(second.status, 200);
  assert.strictEqual(second.body.records.length, 0, 'removing the only row and reopening must not re-pre-fill it');
  assert.strictEqual(second.body.sheet.id, first.body.sheet.id, 'the same sheet row, not a second one');
});

// ---------------------------------------------------------------------------
// 2. Each kind of exception, stand-ins, and removal
// ---------------------------------------------------------------------------

test('a supervisor marks a row absent with a reason, which forces worked and overtime minutes to zero', async () => {
  const { unit, shiftInstance, recorder } = await makeGround({});
  await insertEmployee({ defaultOrgUnitId: unit.id });
  const { body: opened } = await getSheet(recorder.token, shiftInstance.id);
  const recordId = opened.records[0].id;

  const { rows: [reason] } = await pool.query("SELECT id FROM absence_reasons WHERE code = 'SICK'");

  const { status, body } = await updateRecord(recorder.token, shiftInstance.id, recordId, {
    attendanceStatus: 'absent_unplanned',
    absenceReasonId: reason.id
  });
  assert.strictEqual(status, 200, JSON.stringify(body));
  assert.strictEqual(body.record.attendanceStatus, 'absent_unplanned');
  assert.strictEqual(body.record.absenceReasonId, reason.id);
  assert.strictEqual(body.record.workedMinutes, 0);
  assert.strictEqual(body.record.overtimeMinutes, 0);
});

test('the baseline CHECK for an absence with no reason is reported as a 400 naming the field, never a raw constraint error', async () => {
  const { unit, shiftInstance, recorder } = await makeGround({});
  await insertEmployee({ defaultOrgUnitId: unit.id });
  const { body: opened } = await getSheet(recorder.token, shiftInstance.id);
  const recordId = opened.records[0].id;

  const { status, body } = await updateRecord(recorder.token, shiftInstance.id, recordId, {
    attendanceStatus: 'absent_planned'
  });
  assert.strictEqual(status, 400, JSON.stringify(body));
  assert.match(body.message, /absenceReasonId/);
});

test('a supervisor marks a row late', async () => {
  const { unit, shiftInstance, recorder } = await makeGround({});
  await insertEmployee({ defaultOrgUnitId: unit.id });
  const { body: opened } = await getSheet(recorder.token, shiftInstance.id);
  const recordId = opened.records[0].id;

  const { status, body } = await updateRecord(recorder.token, shiftInstance.id, recordId, {
    attendanceStatus: 'late',
    workedMinutes: 420
  });
  assert.strictEqual(status, 200, JSON.stringify(body));
  assert.strictEqual(body.record.attendanceStatus, 'late');
  assert.strictEqual(body.record.workedMinutes, 420);
});

test('an early finish is present with worked minutes reduced below scheduled minutes', async () => {
  const { unit, shiftInstance, recorder } = await makeGround({});
  await insertEmployee({ defaultOrgUnitId: unit.id });
  const { body: opened } = await getSheet(recorder.token, shiftInstance.id);
  const recordId = opened.records[0].id;

  const { status, body } = await updateRecord(recorder.token, shiftInstance.id, recordId, {
    workedMinutes: 300
  });
  assert.strictEqual(status, 200, JSON.stringify(body));
  assert.strictEqual(body.record.attendanceStatus, 'present');
  assert.strictEqual(body.record.scheduledMinutes, 450);
  assert.strictEqual(body.record.workedMinutes, 300);
});

test('overtime minutes are recorded, and refused when they exceed worked minutes', async () => {
  const { unit, shiftInstance, recorder } = await makeGround({});
  await insertEmployee({ defaultOrgUnitId: unit.id });
  const { body: opened } = await getSheet(recorder.token, shiftInstance.id);
  const recordId = opened.records[0].id;

  const ok = await updateRecord(recorder.token, shiftInstance.id, recordId, {
    workedMinutes: 510,
    overtimeMinutes: 60
  });
  assert.strictEqual(ok.status, 200, JSON.stringify(ok.body));
  assert.strictEqual(ok.body.record.overtimeMinutes, 60);

  const refused = await updateRecord(recorder.token, shiftInstance.id, recordId, {
    workedMinutes: 450,
    overtimeMinutes: 500
  });
  assert.strictEqual(refused.status, 400, JSON.stringify(refused.body));
  assert.match(refused.body.message, /overtimeMinutes/);
});

test('a stand-in is added from the Directory, defaulting to the duration minus breaks', async () => {
  const { shiftInstance, recorder } = await makeGround({});
  const standIn = await insertEmployee({ defaultOrgUnitId: null, defaultCrewId: null });

  const { status, body } = await addStandIn(recorder.token, shiftInstance.id, { employeeId: standIn.id });
  assert.strictEqual(status, 201, JSON.stringify(body));
  assert.strictEqual(body.record.employeeId, standIn.id);
  assert.strictEqual(body.record.scheduledMinutes, 450);
  assert.strictEqual(body.record.workedMinutes, 450);
});

test('an Employee already on the sheet cannot be added twice', async () => {
  const { unit, shiftInstance, recorder } = await makeGround({});
  const employee = await insertEmployee({ defaultOrgUnitId: unit.id });
  await getSheet(recorder.token, shiftInstance.id); // pre-fills, putting `employee` on the sheet

  const { status, body } = await addStandIn(recorder.token, shiftInstance.id, { employeeId: employee.id });
  assert.strictEqual(status, 409, JSON.stringify(body));
});

test('a departed Employee cannot be added as a stand-in', async () => {
  const { shiftInstance, recorder } = await makeGround({});
  const departed = await insertEmployee({ isActive: false });

  const { status, body } = await addStandIn(recorder.token, shiftInstance.id, { employeeId: departed.id });
  assert.strictEqual(status, 400, JSON.stringify(body));
});

test('a row is removed from the sheet', async () => {
  const { unit, shiftInstance, recorder } = await makeGround({});
  await insertEmployee({ defaultOrgUnitId: unit.id });
  const { body: opened } = await getSheet(recorder.token, shiftInstance.id);
  const recordId = opened.records[0].id;

  const status = await removeRecord(recorder.token, shiftInstance.id, recordId);
  assert.strictEqual(status, 204);

  const { body: after } = await getSheet(recorder.token, shiftInstance.id);
  assert.strictEqual(after.records.length, 0);
});

// ---------------------------------------------------------------------------
// 3. Confirm, and correcting a confirmed sheet
// ---------------------------------------------------------------------------

test('confirming sets confirmed_at and the confirming Account', async () => {
  const { unit, shiftInstance, recorder } = await makeGround({});
  await insertEmployee({ defaultOrgUnitId: unit.id });
  await getSheet(recorder.token, shiftInstance.id);

  const { status, body } = await confirmSheet(recorder.token, shiftInstance.id);
  assert.strictEqual(status, 200, JSON.stringify(body));
  assert.ok(body.sheet.confirmedAt);
  assert.strictEqual(body.sheet.confirmedByAccountId, recorder.id);
});

test('a confirmed sheet can still be corrected, and the correction leaves the confirmation in place', async () => {
  const { unit, shiftInstance, recorder } = await makeGround({});
  await insertEmployee({ defaultOrgUnitId: unit.id });
  const { body: opened } = await getSheet(recorder.token, shiftInstance.id);
  const recordId = opened.records[0].id;

  const { body: confirmed } = await confirmSheet(recorder.token, shiftInstance.id);
  assert.ok(confirmed.sheet.confirmedAt);

  const { status, body: corrected } = await updateRecord(recorder.token, shiftInstance.id, recordId, {
    workedMinutes: 200
  });
  assert.strictEqual(status, 200, JSON.stringify(corrected));
  assert.strictEqual(corrected.record.workedMinutes, 200);

  const { body: after } = await getSheet(recorder.token, shiftInstance.id);
  assert.strictEqual(after.sheet.confirmedAt, confirmed.sheet.confirmedAt, 'confirmation must be unchanged by a correction');
});

// ---------------------------------------------------------------------------
// 4. Grants: recording needs an edit Grant reaching the Org Unit; reading
//    needs only visibility of the Site.
// ---------------------------------------------------------------------------

test('an Account holding only a read Grant is refused when it tries to record, confirm or correct', async () => {
  const { unit, shiftInstance, recorder } = await makeGround({});
  await insertEmployee({ defaultOrgUnitId: unit.id });
  const readOnly = await insertAccount({ grants: [{ orgUnitId: unit.id, write: false }] });

  // The sheet must already be started by someone who could — a read Grant
  // is never enough to start one on its own (see the "writes nothing" and
  // "pre-fills exactly once" tests below).
  const opened = await getSheet(recorder.token, shiftInstance.id);
  const recordId = opened.body.records[0].id;

  // Reading an already-started sheet still works — a read Grant is enough
  // to see the Site.
  const read = await getSheet(readOnly.token, shiftInstance.id);
  assert.strictEqual(read.status, 200, JSON.stringify(read.body));
  assert.strictEqual(read.body.started, true);
  assert.strictEqual(read.body.records.length, 1);

  const confirm = await confirmSheet(readOnly.token, shiftInstance.id);
  assert.strictEqual(confirm.status, 403, JSON.stringify(confirm.body));

  const update = await updateRecord(readOnly.token, shiftInstance.id, recordId, { workedMinutes: 10 });
  assert.strictEqual(update.status, 403, JSON.stringify(update.body));

  const standIn = await insertEmployee();
  const add = await addStandIn(readOnly.token, shiftInstance.id, { employeeId: standIn.id });
  assert.strictEqual(add.status, 403, JSON.stringify(add.body));

  const removeStatus = await removeRecord(readOnly.token, shiftInstance.id, recordId);
  assert.strictEqual(removeStatus, 403);
});

test('a read-only Account opening an unstarted sheet writes nothing, and the response says not started', async () => {
  const { unit, shiftInstance } = await makeGround({});
  await insertEmployee({ defaultOrgUnitId: unit.id });
  const readOnly = await insertAccount({ grants: [{ orgUnitId: unit.id, write: false }] });

  const { status, body } = await getSheet(readOnly.token, shiftInstance.id);
  assert.strictEqual(status, 200, JSON.stringify(body));
  assert.strictEqual(body.started, false);
  assert.strictEqual(body.sheet, null);
  assert.deepStrictEqual(body.records, []);

  const { rows: sheetRows } = await pool.query(
    'SELECT id FROM attendance_sheets WHERE shift_instance_id = $1',
    [shiftInstance.id]
  );
  assert.strictEqual(sheetRows.length, 0, 'a read-only GET must create no attendance_sheets row');

  const { rows: recordRows } = await pool.query(
    'SELECT id FROM attendance_records WHERE shift_instance_id = $1',
    [shiftInstance.id]
  );
  assert.strictEqual(recordRows.length, 0, 'a read-only GET must pre-fill no attendance_records rows');
});

test('a write-scoped Account opening a sheet twice still pre-fills exactly once', async () => {
  const { unit, shiftInstance, recorder } = await makeGround({});
  await insertEmployee({ defaultOrgUnitId: unit.id });

  const first = await getSheet(recorder.token, shiftInstance.id);
  assert.strictEqual(first.status, 200, JSON.stringify(first.body));
  assert.strictEqual(first.body.started, true);
  assert.strictEqual(first.body.records.length, 1);

  const second = await getSheet(recorder.token, shiftInstance.id);
  assert.strictEqual(second.status, 200, JSON.stringify(second.body));
  assert.strictEqual(second.body.started, true);
  assert.strictEqual(second.body.sheet.id, first.body.sheet.id, 'the same sheet row, not a second one');
  assert.strictEqual(second.body.records.length, 1);

  const { rows: sheetRows } = await pool.query(
    'SELECT id FROM attendance_sheets WHERE shift_instance_id = $1',
    [shiftInstance.id]
  );
  assert.strictEqual(sheetRows.length, 1);

  const { rows: recordRows } = await pool.query(
    'SELECT id FROM attendance_records WHERE shift_instance_id = $1',
    [shiftInstance.id]
  );
  assert.strictEqual(recordRows.length, 1);
});

test('an Account holding no Grant anywhere in the Site cannot even read the sheet', async () => {
  const { shiftInstance } = await makeGround({});
  const outsider = await insertAccount({ grants: [] });

  const { status, body } = await getSheet(outsider.token, shiftInstance.id);
  assert.strictEqual(status, 403, JSON.stringify(body));
});

test('an administrator may record, confirm and correct with no Grant of their own', async () => {
  const { unit, shiftInstance } = await makeGround({});
  await insertEmployee({ defaultOrgUnitId: unit.id });

  const { status, body } = await getSheet(adminToken, shiftInstance.id);
  assert.strictEqual(status, 200, JSON.stringify(body));
  const { status: confirmStatus } = await confirmSheet(adminToken, shiftInstance.id);
  assert.strictEqual(confirmStatus, 200);
});

// ---------------------------------------------------------------------------
// 5. The absence reason catalogue
// ---------------------------------------------------------------------------

test('GET /absence-reasons lists the seeded catalogue, open to any active Account', async () => {
  const someone = await insertAccount({ grants: [] }); // no Grant anywhere — still an open read
  const { status, body } = await listAbsenceReasons(someone.token);
  assert.strictEqual(status, 200, JSON.stringify(body));
  assert.ok(body.absenceReasons.some((reason) => reason.code === 'SICK'));
});

// ---------------------------------------------------------------------------
// 6. The Attendance Screen's own shift-instance picker
// ---------------------------------------------------------------------------

test('the shift instance picker lists a production day\'s shifts at an Org Unit, and marks which are confirmed', async () => {
  const { unit, shiftInstance, recorder } = await makeGround({});
  await insertEmployee({ defaultOrgUnitId: unit.id });
  await getSheet(recorder.token, shiftInstance.id);
  await confirmSheet(recorder.token, shiftInstance.id);

  const { status, body } = await listShiftInstances(recorder.token, unit.id, '2026-05-04');
  assert.strictEqual(status, 200, JSON.stringify(body));
  assert.strictEqual(body.shiftInstances.length, 1);
  assert.strictEqual(body.shiftInstances[0].id, shiftInstance.id);
  assert.strictEqual(body.shiftInstances[0].hasSheet, true);
  assert.ok(body.shiftInstances[0].confirmedAt);
});

test('the shift instance picker refuses an Account that cannot see the Site', async () => {
  const { unit } = await makeGround({});
  const outsider = await insertAccount({ grants: [] });

  const { status, body } = await listShiftInstances(outsider.token, unit.id, '2026-05-04');
  assert.strictEqual(status, 403, JSON.stringify(body));
});

// ---------------------------------------------------------------------------
// 7. The attendance-to-confirm worklist (issue #250)
// ---------------------------------------------------------------------------

test('the worklist lists a missing sheet and an unconfirmed sheet, oldest first, and a confirmed sheet does not appear', async () => {
  const site = await insertSite();
  const unit = await insertOrgUnit(site.id);
  const shiftDefinition = await insertShiftDefinition(site.id);
  const recorder = await insertAccount({ grants: [{ orgUnitId: unit.id }] });

  // Establishes the Org Unit's own floor.
  const floorInstance = await insertShiftInstance(site, unit, shiftDefinition, {
    productionDate: '2026-01-01',
    startsAt: '2026-01-01T06:00:00Z',
    endsAt: '2026-01-01T14:00:00Z'
  });
  await getSheet(recorder.token, floorInstance.id);
  await confirmSheet(recorder.token, floorInstance.id);

  // No sheet at all — "missing".
  const missingInstance = await insertShiftInstance(site, unit, shiftDefinition, {
    productionDate: '2026-01-10',
    startsAt: '2026-01-10T06:00:00Z',
    endsAt: '2026-01-10T14:00:00Z'
  });

  // Opened, never confirmed — "unconfirmed".
  const unconfirmedInstance = await insertShiftInstance(site, unit, shiftDefinition, {
    productionDate: '2026-01-15',
    startsAt: '2026-01-15T06:00:00Z',
    endsAt: '2026-01-15T14:00:00Z'
  });
  await getSheet(recorder.token, unconfirmedInstance.id);

  // Opened AND confirmed, after the other two — must not appear.
  const confirmedInstance = await insertShiftInstance(site, unit, shiftDefinition, {
    productionDate: '2026-01-20',
    startsAt: '2026-01-20T06:00:00Z',
    endsAt: '2026-01-20T14:00:00Z'
  });
  await getSheet(recorder.token, confirmedInstance.id);
  await confirmSheet(recorder.token, confirmedInstance.id);

  const { status, body } = await listAttendanceToConfirm(recorder.token, { orgUnitId: unit.id });
  assert.strictEqual(status, 200, JSON.stringify(body));
  const ids = body.entries.map((entry) => entry.shiftInstanceId);
  assert.deepStrictEqual(ids, [missingInstance.id, unconfirmedInstance.id], 'oldest first, missing then unconfirmed');
  assert.strictEqual(body.entries[0].sheetState, 'missing');
  assert.strictEqual(body.entries[1].sheetState, 'unconfirmed');
  assert.ok(!ids.includes(floorInstance.id), 'the confirmed floor shift must not appear');
  assert.ok(!ids.includes(confirmedInstance.id), 'a confirmed sheet must not appear');
});

test('a shift instance before the Site\'s first confirmed sheet is not listed, even though it is unconfirmed', async () => {
  const site = await insertSite();
  const unit = await insertOrgUnit(site.id);
  const shiftDefinition = await insertShiftDefinition(site.id);
  const recorder = await insertAccount({ grants: [{ orgUnitId: unit.id }] });

  // Before the floor — never touched, ended, unconfirmed, but must not
  // appear: the floor for this Site has not opened yet.
  const beforeFloor = await insertShiftInstance(site, unit, shiftDefinition, {
    productionDate: '2026-02-01',
    startsAt: '2026-02-01T06:00:00Z',
    endsAt: '2026-02-01T14:00:00Z'
  });

  const floorInstance = await insertShiftInstance(site, unit, shiftDefinition, {
    productionDate: '2026-02-10',
    startsAt: '2026-02-10T06:00:00Z',
    endsAt: '2026-02-10T14:00:00Z'
  });
  await getSheet(recorder.token, floorInstance.id);
  await confirmSheet(recorder.token, floorInstance.id);

  const afterFloor = await insertShiftInstance(site, unit, shiftDefinition, {
    productionDate: '2026-02-15',
    startsAt: '2026-02-15T06:00:00Z',
    endsAt: '2026-02-15T14:00:00Z'
  });

  const { status, body } = await listAttendanceToConfirm(recorder.token, { orgUnitId: unit.id });
  assert.strictEqual(status, 200, JSON.stringify(body));
  const ids = body.entries.map((entry) => entry.shiftInstanceId);
  assert.ok(!ids.includes(beforeFloor.id), 'a shift instance before the first confirmed sheet must not be listed');
  assert.ok(ids.includes(afterFloor.id), 'a shift instance after the floor must still be listed');
});

test('a Site with no confirmed sheet ever has no floor, and lists nothing for it', async () => {
  const site = await insertSite();
  const unitA = await insertOrgUnit(site.id, { name: 'Line A' });
  const unitB = await insertOrgUnit(site.id, { name: 'Line B' });
  const shiftDefinitionA = await insertShiftDefinition(site.id);
  const shiftDefinitionB = await insertShiftDefinition(site.id);
  const recorder = await insertAccount({ grants: [{ orgUnitId: unitA.id }, { orgUnitId: unitB.id }] });

  // Ended, unconfirmed, and the caller holds a write Grant at both Org
  // Units — but nobody, anywhere in this Site, has ever confirmed a single
  // sheet, so the Site has no floor at all.
  await insertShiftInstance(site, unitA, shiftDefinitionA, {
    productionDate: '2026-03-01',
    startsAt: '2026-03-01T06:00:00Z',
    endsAt: '2026-03-01T14:00:00Z'
  });
  await insertShiftInstance(site, unitB, shiftDefinitionB, {
    productionDate: '2026-03-01',
    startsAt: '2026-03-01T07:00:00Z',
    endsAt: '2026-03-01T15:00:00Z'
  });

  const { status, body } = await listAttendanceToConfirm(recorder.token, {});
  assert.strictEqual(status, 200, JSON.stringify(body));
  assert.deepStrictEqual(body.entries, []);
});

test('the Site-wide floor: Line A confirms a sheet, Line B never does, and Line B\'s later unconfirmed '
    + "shifts are listed anyway — because they are exactly what is keeping the Site's rate at no_data",
async () => {
  const site = await insertSite();
  const lineA = await insertOrgUnit(site.id, { name: 'Line A' });
  const lineB = await insertOrgUnit(site.id, { name: 'Line B' });
  const shiftDefinitionA = await insertShiftDefinition(site.id);
  const shiftDefinitionB = await insertShiftDefinition(site.id);
  const recorder = await insertAccount({ grants: [{ orgUnitId: lineA.id }, { orgUnitId: lineB.id }] });

  // Line A confirms a sheet — this alone opens the Site's floor.
  const lineAFloor = await insertShiftInstance(site, lineA, shiftDefinitionA, {
    productionDate: '2026-07-01',
    startsAt: '2026-07-01T06:00:00Z',
    endsAt: '2026-07-01T14:00:00Z'
  });
  await getSheet(recorder.token, lineAFloor.id);
  await confirmSheet(recorder.token, lineAFloor.id);

  // Line B, before the Site's floor opened — must not be listed.
  const lineBBefore = await insertShiftInstance(site, lineB, shiftDefinitionB, {
    productionDate: '2026-06-20',
    startsAt: '2026-06-20T06:00:00Z',
    endsAt: '2026-06-20T14:00:00Z'
  });

  // Line B, after Line A's confirmation — Line B itself has never confirmed
  // anything, but this must still be listed: it is exactly the shift
  // keeping the Site's rate at no_data (issue #250's own amended wording).
  const lineBAfter = await insertShiftInstance(site, lineB, shiftDefinitionB, {
    productionDate: '2026-07-05',
    startsAt: '2026-07-05T06:00:00Z',
    endsAt: '2026-07-05T14:00:00Z'
  });

  const { status, body } = await listAttendanceToConfirm(recorder.token, { orgUnitId: lineB.id });
  assert.strictEqual(status, 200, JSON.stringify(body));
  const ids = body.entries.map((entry) => entry.shiftInstanceId);
  assert.ok(!ids.includes(lineBBefore.id), 'before the Site\'s floor, even on the never-confirmed line');
  assert.ok(ids.includes(lineBAfter.id), 'after the Site\'s floor, even though Line B itself never confirmed');
});

test('a shift instance that has not yet ended is not listed, even though it would otherwise be unconfirmed', async () => {
  const site = await insertSite();
  const unit = await insertOrgUnit(site.id);
  const shiftDefinition = await insertShiftDefinition(site.id);
  const recorder = await insertAccount({ grants: [{ orgUnitId: unit.id }] });

  const floorInstance = await insertShiftInstance(site, unit, shiftDefinition, {
    productionDate: '2026-04-01',
    startsAt: '2026-04-01T06:00:00Z',
    endsAt: '2026-04-01T14:00:00Z'
  });
  await getSheet(recorder.token, floorInstance.id);
  await confirmSheet(recorder.token, floorInstance.id);

  // Ends long in the future — has not happened yet.
  const notEnded = await insertShiftInstance(site, unit, shiftDefinition, {
    productionDate: '2030-01-01',
    startsAt: '2030-01-01T06:00:00Z',
    endsAt: '2030-01-01T14:00:00Z'
  });

  const { status, body } = await listAttendanceToConfirm(recorder.token, { orgUnitId: unit.id });
  assert.strictEqual(status, 200, JSON.stringify(body));
  const ids = body.entries.map((entry) => entry.shiftInstanceId);
  assert.ok(!ids.includes(notEnded.id));
});

test('the worklist is scoped to the caller\'s own edit Grants: a read-only Grant contributes nothing, and an administrator sees every Site\'s list', async () => {
  const siteA = await insertSite();
  const unitA = await insertOrgUnit(siteA.id);
  const shiftDefinitionA = await insertShiftDefinition(siteA.id);
  const writer = await insertAccount({ grants: [{ orgUnitId: unitA.id, write: true }] });
  const readOnly = await insertAccount({ grants: [{ orgUnitId: unitA.id, write: false }] });

  const floorA = await insertShiftInstance(siteA, unitA, shiftDefinitionA, {
    productionDate: '2026-05-01',
    startsAt: '2026-05-01T06:00:00Z',
    endsAt: '2026-05-01T14:00:00Z'
  });
  await getSheet(writer.token, floorA.id);
  await confirmSheet(writer.token, floorA.id);
  const unconfirmedA = await insertShiftInstance(siteA, unitA, shiftDefinitionA, {
    productionDate: '2026-05-05',
    startsAt: '2026-05-05T06:00:00Z',
    endsAt: '2026-05-05T14:00:00Z'
  });

  // A second Site the writer holds no Grant on at all.
  const siteB = await insertSite();
  const unitB = await insertOrgUnit(siteB.id);
  const shiftDefinitionB = await insertShiftDefinition(siteB.id);
  const writerB = await insertAccount({ grants: [{ orgUnitId: unitB.id, write: true }] });
  const floorB = await insertShiftInstance(siteB, unitB, shiftDefinitionB, {
    productionDate: '2026-05-01',
    startsAt: '2026-05-01T06:00:00Z',
    endsAt: '2026-05-01T14:00:00Z'
  });
  await getSheet(writerB.token, floorB.id);
  await confirmSheet(writerB.token, floorB.id);
  const unconfirmedB = await insertShiftInstance(siteB, unitB, shiftDefinitionB, {
    productionDate: '2026-05-05',
    startsAt: '2026-05-05T06:00:00Z',
    endsAt: '2026-05-05T14:00:00Z'
  });

  const writerResult = await listAttendanceToConfirm(writer.token);
  assert.strictEqual(writerResult.status, 200, JSON.stringify(writerResult.body));
  const writerIds = writerResult.body.entries.map((entry) => entry.shiftInstanceId);
  assert.ok(writerIds.includes(unconfirmedA.id), 'the writer sees the unconfirmed shift it holds an edit Grant on');
  assert.ok(!writerIds.includes(unconfirmedB.id), 'the writer does not see a Site it holds no Grant on at all');

  const readOnlyResult = await listAttendanceToConfirm(readOnly.token);
  assert.strictEqual(readOnlyResult.status, 200, JSON.stringify(readOnlyResult.body));
  const readOnlyIds = readOnlyResult.body.entries.map((entry) => entry.shiftInstanceId);
  assert.ok(!readOnlyIds.includes(unconfirmedA.id), 'a read-only Grant contributes nothing to the worklist');

  const adminResult = await listAttendanceToConfirm(adminToken);
  assert.strictEqual(adminResult.status, 200, JSON.stringify(adminResult.body));
  const adminIds = adminResult.body.entries.map((entry) => entry.shiftInstanceId);
  assert.ok(adminIds.includes(unconfirmedA.id), 'an administrator sees every Site\'s list (Site A)');
  assert.ok(adminIds.includes(unconfirmedB.id), 'an administrator sees every Site\'s list (Site B)');
});

test('the worklist filters by Org Unit, including beneath it, and by date range', async () => {
  const site = await insertSite();
  const parent = await insertOrgUnit(site.id, { name: 'Parent' });
  const child = await insertOrgUnit(site.id, { parentId: parent.id, name: 'Child' });
  const shiftDefinitionParent = await insertShiftDefinition(site.id);
  const shiftDefinitionChild = await insertShiftDefinition(site.id);
  // A single Grant on the parent reaches the child too (ADR-0027), so one
  // recorder Account can establish and read both floors.
  const recorder = await insertAccount({ grants: [{ orgUnitId: parent.id }] });

  const floorParent = await insertShiftInstance(site, parent, shiftDefinitionParent, {
    productionDate: '2026-06-01',
    startsAt: '2026-06-01T06:00:00Z',
    endsAt: '2026-06-01T14:00:00Z'
  });
  await getSheet(recorder.token, floorParent.id);
  await confirmSheet(recorder.token, floorParent.id);
  const unconfirmedParent = await insertShiftInstance(site, parent, shiftDefinitionParent, {
    productionDate: '2026-06-05',
    startsAt: '2026-06-05T06:00:00Z',
    endsAt: '2026-06-05T14:00:00Z'
  });
  // A second, later unconfirmed shift at the parent, for the date-range filter.
  const laterUnconfirmedParent = await insertShiftInstance(site, parent, shiftDefinitionParent, {
    productionDate: '2026-06-25',
    startsAt: '2026-06-25T06:00:00Z',
    endsAt: '2026-06-25T14:00:00Z'
  });

  const floorChild = await insertShiftInstance(site, child, shiftDefinitionChild, {
    productionDate: '2026-06-01',
    startsAt: '2026-06-01T07:00:00Z',
    endsAt: '2026-06-01T15:00:00Z'
  });
  await getSheet(recorder.token, floorChild.id);
  await confirmSheet(recorder.token, floorChild.id);
  const unconfirmedChild = await insertShiftInstance(site, child, shiftDefinitionChild, {
    productionDate: '2026-06-05',
    startsAt: '2026-06-05T07:00:00Z',
    endsAt: '2026-06-05T15:00:00Z'
  });

  // Filtered to the child alone: only the child's own unconfirmed shift.
  const childOnly = await listAttendanceToConfirm(recorder.token, { orgUnitId: child.id });
  assert.strictEqual(childOnly.status, 200, JSON.stringify(childOnly.body));
  const childOnlyIds = childOnly.body.entries.map((entry) => entry.shiftInstanceId);
  assert.deepStrictEqual(childOnlyIds.sort(), [unconfirmedChild.id].sort());

  // Filtered to the parent: both the parent's own and the child's, beneath it.
  const parentAndBeneath = await listAttendanceToConfirm(recorder.token, { orgUnitId: parent.id });
  assert.strictEqual(parentAndBeneath.status, 200, JSON.stringify(parentAndBeneath.body));
  const parentIds = parentAndBeneath.body.entries.map((entry) => entry.shiftInstanceId);
  assert.ok(parentIds.includes(unconfirmedParent.id));
  assert.ok(parentIds.includes(laterUnconfirmedParent.id));
  assert.ok(parentIds.includes(unconfirmedChild.id));

  // Date range: only the earlier of the parent's two unconfirmed shifts.
  const ranged = await listAttendanceToConfirm(recorder.token, {
    orgUnitId: parent.id,
    from: '2026-06-04',
    to: '2026-06-10'
  });
  assert.strictEqual(ranged.status, 200, JSON.stringify(ranged.body));
  const rangedIds = ranged.body.entries.map((entry) => entry.shiftInstanceId);
  assert.ok(rangedIds.includes(unconfirmedParent.id));
  assert.ok(!rangedIds.includes(laterUnconfirmedParent.id), 'outside the date range');
});

test('the worklist refuses an unauthenticated caller and 404s an unknown orgUnitId filter', async () => {
  const noAuth = await listAttendanceToConfirm({});
  assert.strictEqual(noAuth.status, 401, JSON.stringify(noAuth.body));

  const { status, body } = await listAttendanceToConfirm(adminToken, { orgUnitId: '999999999' });
  assert.strictEqual(status, 404, JSON.stringify(body));
});
