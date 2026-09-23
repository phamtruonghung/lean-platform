/*
 * The People KPIs on the tier board (issue #251, parent #247, ADR-0040) —
 * over HTTP, against a real database and a real (locally issued) JWKS, and
 * read through the board's own existing address, which this ticket does not
 * change. The seam, the fixture scaffolding and the dependency-ordered
 * cleanup are the ones `tier-board.test.js`, `safety-kpis.test.js` and
 * `attendance.test.js` already establish.
 *
 * Every attendance record these tests assert on is written **through the
 * API** — `GET /api/people/shift-instances/:id/attendance-sheet` to open and
 * pre-fill the sheet, `PATCH .../attendance-records/:id` to mark the
 * exceptions, `POST .../attendance-sheet/confirm` to confirm it — and read
 * back through `GET /api/maintenance/sites/:siteId/board`. Nothing here
 * inserts an `attendance_records` or `attendance_sheets` row directly: the
 * point of the ticket is that what a supervisor confirms on the sheet is what
 * the board reports, so the test has to travel the same road.
 *
 * Shift instances come from the database's own `generate_shift_instances`,
 * one day at a time (`generateShifts(orgUnit, date, date)` — never a wider
 * range), so a test never leaves a shift instance lying around that it did
 * not mean to create. Unlike `SAF_TRIR`/`SAF_LTIFR`, an unconfirmed shift
 * does not blank a People number — see "an unconfirmed sheet contributes
 * nothing" below, which asserts that difference directly — but building
 * exactly the days a scenario needs still keeps every expected value
 * readable.
 *
 * What is asserted, against #251's own acceptance criteria: `PPL_ABSENTEEISM`
 * sums its numerator and denominator across the period and subtree before
 * dividing once (never an average of per-Org-Unit rates); `PPL_HEADCOUNT` is
 * the average headcount present per confirmed shift instance, counting
 * `present`, `late` and `training` as present; annual leave and training are
 * out of absenteeism's numerator and still in its denominator; an unconfirmed
 * sheet contributes nothing and a period with no confirmed sheet reports
 * `no_data`; the subtree roll-up; the period filter; and filing by production
 * day rather than by the calendar date a night shift ends on (ADR-0017).
 *
 * Needs a database with every migration applied. This slice adds no migration
 * of its own: the board computes on read, and both tables it reads already
 * exist. Set DATABASE_URL first — see the README's Tests section.
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
const insertedShiftDefinitionIds = [];
const insertedShiftInstanceIds = [];
const insertedEmployeeIds = [];

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

async function insertAccount({ role = 'operator', grants = [] } = {}) {
  const subject = uniqueCode('pplkpi');
  const { rows: [account] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status)
     VALUES ($1, 'People KPI Test Account', $2, $3, TRUE, 'approved') RETURNING id`,
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

async function insertSite({ timezone = 'Asia/Ho_Chi_Minh', name = 'People KPI Test Site' } = {}) {
  const { rows: [site] } = await pool.query(
    `INSERT INTO sites (code, name, timezone) VALUES ($1, $2, $3) RETURNING id, code, name, timezone`,
    [uniqueCode('PKS'), name, timezone]
  );
  insertedSiteIds.push(site.id);
  return site;
}

async function insertOrgUnit(siteId, { parentId = null, unitType = 'area', name = 'KPI Unit' } = {}) {
  const { rows: [orgUnit] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, $2, $3, $4, $5) RETURNING id, code, name, path`,
    [siteId, parentId, uniqueCode('PKOU'), name, unitType]
  );
  insertedOrgUnitIds.push(orgUnit.id);
  return orgUnit;
}

async function insertShiftDefinition(siteId, {
  code = 'DAY',
  name = 'Day shift',
  startTime = '06:00',
  durationMinutes = 480
} = {}) {
  const { rows: [shift] } = await pool.query(
    `INSERT INTO shift_definitions (site_id, code, name, start_time, duration_minutes, day_offset)
     VALUES ($1, $2, $3, $4, $5, 0) RETURNING id`,
    [siteId, uniqueCode(code), name, startTime, durationMinutes]
  );
  insertedShiftDefinitionIds.push(shift.id);
  return shift;
}

// The production-day calendar, built by the database's own
// `generate_shift_instances` — never a hand-written `shift_instances` row.
async function generateShifts(orgUnitId, from, to) {
  await pool.query('SELECT generate_shift_instances($1, $2::date, $3::date)', [orgUnitId, from, to]);
  const { rows } = await pool.query('SELECT id FROM shift_instances WHERE org_unit_id = $1', [
    orgUnitId
  ]);
  for (const row of rows) insertedShiftInstanceIds.push(row.id);
}

// An active Employee whose `default_org_unit_id` is `orgUnitId` — the
// Org-Unit-fallback branch of the roster pre-fill (no crew in this ground),
// exactly as `attendance.js`'s own header describes it.
async function insertRosterEmployee(orgUnitId, { lastName = 'Operator' } = {}) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO employees (employee_no, first_name, last_name, is_active, default_org_unit_id)
     VALUES ($1, 'Roster', $2, TRUE, $3) RETURNING id`,
    [uniqueCode('PKEMP'), lastName, orgUnitId]
  );
  insertedEmployeeIds.push(row.id);
  return row;
}

async function findShiftInstanceId(orgUnitId, productionDate) {
  const { rows: [row] } = await pool.query(
    'SELECT id FROM shift_instances WHERE org_unit_id = $1 AND production_date = $2::date',
    [orgUnitId, productionDate]
  );
  assert.ok(row, `expected a shift instance at org unit ${orgUnitId} on ${productionDate}`);
  return row.id;
}

// Opening the sheet is what pre-fills it from the roster (attendance.js), so
// this is both the read and the act of authoring the sheet.
async function openSheet(token, shiftInstanceId) {
  const response = await fetch(
    `${base}/api/people/shift-instances/${shiftInstanceId}/attendance-sheet`,
    { headers: token }
  );
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

async function listAbsenceReasons(token) {
  const response = await fetch(`${base}/api/people/absence-reasons`, { headers: token });
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

function readKpi(board, pillarCode, kpiCode) {
  const pillar = board.pillars.find((candidate) => candidate.code === pillarCode);
  const kpi = pillar?.kpis.find((candidate) => candidate.code === kpiCode);
  assert.ok(kpi, `${kpiCode} should be on the board`);
  return { value: kpi.value, status: kpi.status };
}

let admin;
let adminToken;
// The baseline's own seeded `absence_reasons`, read once through the API: the
// flag that decides absenteeism is `counts_as_absenteeism`, and these three
// are the seed's own worked examples of it — SICK true, HOL (annual leave)
// and TRAIN (training) false.
let reasonByCode;

/**
 * The ground: a Site on Asia/Ho_Chi_Minh running one DAY shift (06:00-14:00
 * local), an area with two lines beneath it, and a recorder holding one edit
 * Grant at the area — `canAct`'s own `target.path <@ granted.path` reaches
 * both lines, so this one Account can record and confirm anywhere in it.
 * No shift instance is generated here: each test asks for exactly the days
 * it needs.
 */
async function makeGround({ startTime = '06:00', durationMinutes = 480 } = {}) {
  const site = await insertSite();
  const area = await insertOrgUnit(site.id, { name: 'Assembly' });
  const lineA = await insertOrgUnit(site.id, { parentId: area.id, unitType: 'line', name: 'Line A' });
  const lineB = await insertOrgUnit(site.id, { parentId: area.id, unitType: 'line', name: 'Line B' });
  await insertShiftDefinition(site.id, { startTime, durationMinutes });
  const recorder = await insertAccount({ grants: [{ orgUnitId: area.id, write: true }] });
  return { site, area, lineA, lineB, recorder };
}

/**
 * One shift instance at `orgUnit` on `date`, its sheet opened (which is what
 * pre-fills it from the roster), the exceptions `mark` asks for applied, and
 * — unless `confirm` says otherwise — confirmed.
 *
 * `mark` is keyed by Employee id rather than by position in the sheet: the
 * sheet orders its rows by the Employee's display name, which is not a fact
 * this test wants to depend on.
 */
async function recordShift(ground, orgUnit, date, { mark = {}, confirm = true } = {}) {
  await generateShifts(orgUnit.id, date, date);
  const shiftInstanceId = await findShiftInstanceId(orgUnit.id, date);

  const opened = await openSheet(ground.recorder.token, shiftInstanceId);
  assert.strictEqual(opened.status, 200, JSON.stringify(opened.body));

  for (const record of opened.body.records) {
    const exception = mark[record.employeeId];
    if (!exception) continue;
    const patched = await updateRecord(
      ground.recorder.token,
      shiftInstanceId,
      record.id,
      exception
    );
    assert.strictEqual(patched.status, 200, JSON.stringify(patched.body));
  }

  if (confirm) {
    const confirmed = await confirmSheet(ground.recorder.token, shiftInstanceId);
    assert.strictEqual(confirmed.status, 200, JSON.stringify(confirmed.body));
  }

  return { shiftInstanceId, records: opened.body.records };
}

// The two exception shapes these tests mark, spelled once. An absence carries
// its reason (the baseline's own `attendance_records_absence_has_reason`
// CHECK), and which reason it is decides whether it reaches absenteeism's
// numerator at all.
function absentFor(code) {
  return {
    attendanceStatus: code === 'SICK' ? 'absent_unplanned' : 'absent_planned',
    absenceReasonId: reasonByCode.get(code).id
  };
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

  const reasons = await listAbsenceReasons(adminToken);
  assert.strictEqual(reasons.status, 200, JSON.stringify(reasons.body));
  reasonByCode = new Map(reasons.body.absenceReasons.map((reason) => [reason.code, reason]));
  for (const code of ['SICK', 'HOL', 'TRAIN']) {
    assert.ok(reasonByCode.has(code), `the baseline seeds the ${code} absence reason`);
  }
  // The flag these KPIs turn on, asserted here rather than assumed: the seed's
  // own comment says training and annual leave are both planned and only one
  // kind of absence belongs in the rate.
  assert.strictEqual(reasonByCode.get('SICK').countsAsAbsenteeism, true);
  assert.strictEqual(reasonByCode.get('HOL').countsAsAbsenteeism, false);
  assert.strictEqual(reasonByCode.get('TRAIN').countsAsAbsenteeism, false);
});

test.after(async () => {
  // Children before parents: attendance_records and attendance_sheets both
  // reference shift_instances, and attendance_records also references
  // employees — the same order attendance.test.js's own test.after establishes.
  await pool.query('DELETE FROM attendance_records WHERE shift_instance_id = ANY($1)', [
    insertedShiftInstanceIds
  ]);
  await pool.query('DELETE FROM attendance_sheets WHERE shift_instance_id = ANY($1)', [
    insertedShiftInstanceIds
  ]);
  await pool.query('DELETE FROM employees WHERE id = ANY($1)', [insertedEmployeeIds]);
  await pool.query('DELETE FROM shift_instances WHERE id = ANY($1)', [insertedShiftInstanceIds]);
  await pool.query('DELETE FROM shift_definitions WHERE id = ANY($1)', [
    insertedShiftDefinitionIds
  ]);
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
// PPL_ABSENTEEISM
// ---------------------------------------------------------------------------

test('PPL_ABSENTEEISM sums the absences and the scheduled headcount across the subtree before dividing once, and rolls up the Org Unit tree', async () => {
  const ground = await makeGround();
  const date = '2026-05-04';

  // Line A: four scheduled, nobody absent. Line B: one scheduled, that one
  // absent sick. The two lines have deliberately different headcounts, which
  // is what makes the two readings of "the absenteeism for this area"
  // distinguishable at all.
  for (let i = 0; i < 4; i += 1) await insertRosterEmployee(ground.lineA.id);
  const onlyOnLineB = await insertRosterEmployee(ground.lineB.id);

  await recordShift(ground, ground.lineA, date);
  await recordShift(ground, ground.lineB, date, {
    mark: { [onlyOnLineB.id]: absentFor('SICK') }
  });

  const areaBoard = await getBoard(
    adminToken,
    ground.site.id,
    `?periodType=day&date=${date}&orgUnitId=${ground.area.id}`
  );
  const area = readKpi(areaBoard.payload, 'P', 'PPL_ABSENTEEISM');
  // One absence over five scheduled, summed across both lines and divided
  // once: 20%. The average of the two lines' own rates — 0% and 100% — would
  // be 50%, which is the reading ADR-0041's "sum first, divide once" rejects
  // and the one this assertion exists to rule out.
  assert.strictEqual(Number(area.value), 20);
  assert.notStrictEqual(Number(area.value), 50);

  // Each line on its own still reads its own number, and Line A's is a real,
  // measured zero rather than `no_data`: a shift on which nobody was absent
  // is a clean shift, not a missing one.
  const lineA = await getBoard(
    adminToken,
    ground.site.id,
    `?periodType=day&date=${date}&orgUnitId=${ground.lineA.id}`
  );
  assert.strictEqual(Number(readKpi(lineA.payload, 'P', 'PPL_ABSENTEEISM').value), 0);
  assert.notStrictEqual(readKpi(lineA.payload, 'P', 'PPL_ABSENTEEISM').status, 'no_data');

  const lineB = await getBoard(
    adminToken,
    ground.site.id,
    `?periodType=day&date=${date}&orgUnitId=${ground.lineB.id}`
  );
  assert.strictEqual(Number(readKpi(lineB.payload, 'P', 'PPL_ABSENTEEISM').value), 100);

  // The whole Site, with no Org Unit chosen, is the same subtree one level up.
  const site = await getBoard(adminToken, ground.site.id, `?periodType=day&date=${date}`);
  assert.strictEqual(Number(readKpi(site.payload, 'P', 'PPL_ABSENTEEISM').value), 20);
});

test('annual leave and training are excluded from the absenteeism numerator and still counted in its denominator', async () => {
  const ground = await makeGround();
  const date = '2026-05-04';

  const onLeave = await insertRosterEmployee(ground.lineA.id, { lastName: 'Leave' });
  const atTraining = await insertRosterEmployee(ground.lineA.id, { lastName: 'Training' });
  const offSick = await insertRosterEmployee(ground.lineA.id, { lastName: 'Sick' });
  await insertRosterEmployee(ground.lineA.id, { lastName: 'Present' });

  await recordShift(ground, ground.lineA, date, {
    mark: {
      [onLeave.id]: absentFor('HOL'),
      [atTraining.id]: absentFor('TRAIN'),
      [offSick.id]: absentFor('SICK')
    }
  });

  const board = await getBoard(
    adminToken,
    ground.site.id,
    `?periodType=day&date=${date}&orgUnitId=${ground.lineA.id}`
  );

  // One absence counts — the sickness. Four were scheduled, the two away on
  // annual leave and at training among them: 1/4 = 25%. Dropping them from
  // the denominator as well as the numerator would read 50%, and counting
  // them in the numerator would read 75%; neither is the number the
  // catalogue's own `counts_as_absenteeism` flag asks for.
  assert.strictEqual(Number(readKpi(board.payload, 'P', 'PPL_ABSENTEEISM').value), 25);

  // The same sheet's headcount present: only the one Employee who was neither
  // away nor sick. Annual leave and training were both recorded as absences
  // here, so neither is present — the `training` attendance STATUS, which is,
  // is what the next test covers.
  assert.strictEqual(Number(readKpi(board.payload, 'P', 'PPL_HEADCOUNT').value), 1);
});

// ---------------------------------------------------------------------------
// PPL_HEADCOUNT
// ---------------------------------------------------------------------------

test('PPL_HEADCOUNT is the average headcount present per confirmed shift instance, counting present, late and training', async () => {
  const ground = await makeGround();

  const late = await insertRosterEmployee(ground.lineA.id, { lastName: 'Late' });
  const training = await insertRosterEmployee(ground.lineA.id, { lastName: 'Training' });
  const sick = await insertRosterEmployee(ground.lineA.id, { lastName: 'Sick' });
  await insertRosterEmployee(ground.lineA.id, { lastName: 'Present' });

  // Monday: the roster of four, untouched — all four present.
  await recordShift(ground, ground.lineA, '2026-05-04');
  // Tuesday: one late, one at training, one off sick. `late` and `training`
  // are both present by `v_attendance_rate`'s own definition, so three of the
  // four were present.
  await recordShift(ground, ground.lineA, '2026-05-05', {
    mark: {
      [late.id]: { attendanceStatus: 'late' },
      [training.id]: { attendanceStatus: 'training' },
      [sick.id]: absentFor('SICK')
    }
  });

  const board = await getBoard(
    adminToken,
    ground.site.id,
    `?periodType=month&date=2026-05-04&orgUnitId=${ground.lineA.id}`
  );

  // Two confirmed shift instances, four present on one and three on the
  // other: the average per shift instance is 3.5. A per-production-day
  // average would be the same here only because this ground runs one shift a
  // day; the grain the registry groups on is the shift instance, which is
  // what the definition's own "Average headcount present per shift" asks for.
  assert.strictEqual(Number(readKpi(board.payload, 'P', 'PPL_HEADCOUNT').value), 3.5);

  // One absence over eight scheduled across the two shifts, summed before
  // dividing: 12.5%. Neither the late arrival nor the training counts as an
  // absence — only a recorded absence with a reason carrying
  // `counts_as_absenteeism` does.
  assert.strictEqual(Number(readKpi(board.payload, 'P', 'PPL_ABSENTEEISM').value), 12.5);
});

// ---------------------------------------------------------------------------
// Only confirmed sheets count
// ---------------------------------------------------------------------------

test('an unconfirmed sheet contributes nothing, a period with no confirmed sheet reports no_data, and confirming it makes both numbers real', async () => {
  const ground = await makeGround();
  const date = '2026-05-04';
  const sick = await insertRosterEmployee(ground.lineA.id, { lastName: 'Sick' });
  await insertRosterEmployee(ground.lineA.id, { lastName: 'Present' });

  // The sheet is opened and marked, but nobody has confirmed it.
  const { shiftInstanceId } = await recordShift(ground, ground.lineA, date, {
    mark: { [sick.id]: absentFor('SICK') },
    confirm: false
  });

  const query = `?periodType=day&date=${date}&orgUnitId=${ground.lineA.id}`;
  const before = await getBoard(adminToken, ground.site.id, query);
  for (const code of ['PPL_ABSENTEEISM', 'PPL_HEADCOUNT']) {
    const kpi = readKpi(before.payload, 'P', code);
    assert.strictEqual(kpi.value, null, `${code} reads nothing off an unconfirmed sheet`);
    assert.strictEqual(kpi.status, 'no_data', `${code} says so as no_data, never as a zero`);
  }

  const confirmed = await confirmSheet(ground.recorder.token, shiftInstanceId);
  assert.strictEqual(confirmed.status, 200, JSON.stringify(confirmed.body));

  const after = await getBoard(adminToken, ground.site.id, query);
  // The same rows, now confirmed: one absent of two scheduled, one present.
  assert.strictEqual(Number(readKpi(after.payload, 'P', 'PPL_ABSENTEEISM').value), 50);
  assert.strictEqual(Number(readKpi(after.payload, 'P', 'PPL_HEADCOUNT').value), 1);
});

test('one unconfirmed shift does not blank the People numbers the confirmed shifts answer — unlike the injury rates it blanks outright', async () => {
  const ground = await makeGround();
  await insertRosterEmployee(ground.lineA.id);
  await insertRosterEmployee(ground.lineA.id);

  // Monday is confirmed. Tuesday's shift instance exists and is in the past,
  // and nobody has confirmed it.
  await recordShift(ground, ground.lineA, '2026-05-04');
  await generateShifts(ground.lineA.id, '2026-05-05', '2026-05-05');

  const board = await getBoard(
    adminToken,
    ground.site.id,
    `?periodType=month&date=2026-05-04&orgUnitId=${ground.lineA.id}`
  );

  // Absenteeism is a ratio of what was recorded, so it reports on the shift
  // that was confirmed and stays silent about the one that was not: two
  // present on Monday, nobody absent.
  assert.strictEqual(Number(readKpi(board.payload, 'P', 'PPL_HEADCOUNT').value), 2);
  assert.strictEqual(Number(readKpi(board.payload, 'P', 'PPL_ABSENTEEISM').value), 0);

  // The same board, same subtree, same unconfirmed Tuesday: an injury rate's
  // denominator has to be complete or the number lies, so ADR-0041 blanks it
  // outright. The two rules are different on purpose, and this is the
  // assertion that says so (people/kpi-registry.js's own header).
  assert.strictEqual(readKpi(board.payload, 'S', 'SAF_TRIR').status, 'no_data');
  assert.strictEqual(readKpi(board.payload, 'S', 'SAF_TRIR').value, null);
});

// ---------------------------------------------------------------------------
// The period, and the production day it is measured in
// ---------------------------------------------------------------------------

test('the period filter narrows both People KPIs to the production days inside it', async () => {
  const ground = await makeGround();
  const sick = await insertRosterEmployee(ground.lineA.id, { lastName: 'Sick' });
  await insertRosterEmployee(ground.lineA.id, { lastName: 'Present' });
  await insertRosterEmployee(ground.lineA.id, { lastName: 'AlsoPresent' });

  await recordShift(ground, ground.lineA, '2026-05-04', {
    mark: { [sick.id]: absentFor('SICK') }
  });

  // The day it was worked: one absent of three, two present.
  const onTheDay = await getBoard(
    adminToken,
    ground.site.id,
    `?periodType=day&date=2026-05-04&orgUnitId=${ground.lineA.id}`
  );
  assert.strictEqual(
    Number(readKpi(onTheDay.payload, 'P', 'PPL_ABSENTEEISM').value).toFixed(2),
    '33.33'
  );
  assert.strictEqual(Number(readKpi(onTheDay.payload, 'P', 'PPL_HEADCOUNT').value), 2);

  // The next day, and a month away: nothing confirmed falls in either period.
  for (const query of [
    `?periodType=day&date=2026-05-05&orgUnitId=${ground.lineA.id}`,
    `?periodType=month&date=2026-01-05&orgUnitId=${ground.lineA.id}`
  ]) {
    const quiet = await getBoard(adminToken, ground.site.id, query);
    for (const code of ['PPL_ABSENTEEISM', 'PPL_HEADCOUNT']) {
      assert.strictEqual(readKpi(quiet.payload, 'P', code).status, 'no_data', `${code} ${query}`);
    }
  }

  // The month the shift fell in still holds it.
  const month = await getBoard(
    adminToken,
    ground.site.id,
    `?periodType=month&date=2026-05-20&orgUnitId=${ground.lineA.id}`
  );
  assert.strictEqual(Number(readKpi(month.payload, 'P', 'PPL_HEADCOUNT').value), 2);
});

test('a night shift is filed on the production day it belongs to, not on the calendar date it ends on (ADR-0017)', async () => {
  // 22:00-06:00 local: the shift instance for production day 2026-05-04
  // starts on the evening of the 4th and ends on the morning of the 5th.
  const ground = await makeGround({ startTime: '22:00', durationMinutes: 480 });
  await insertRosterEmployee(ground.lineA.id);
  await insertRosterEmployee(ground.lineA.id);
  await insertRosterEmployee(ground.lineA.id);

  await recordShift(ground, ground.lineA, '2026-05-04');

  const worked = await getBoard(
    adminToken,
    ground.site.id,
    `?periodType=day&date=2026-05-04&orgUnitId=${ground.lineA.id}`
  );
  assert.strictEqual(Number(readKpi(worked.payload, 'P', 'PPL_HEADCOUNT').value), 3);
  assert.strictEqual(Number(readKpi(worked.payload, 'P', 'PPL_ABSENTEEISM').value), 0);

  // The morning the crew went home is a different production day, and nothing
  // was confirmed for it: the night's headcount does not leak into it.
  const nextMorning = await getBoard(
    adminToken,
    ground.site.id,
    `?periodType=day&date=2026-05-05&orgUnitId=${ground.lineA.id}`
  );
  for (const code of ['PPL_ABSENTEEISM', 'PPL_HEADCOUNT']) {
    assert.strictEqual(readKpi(nextMorning.payload, 'P', code).status, 'no_data', code);
  }
});

// ---------------------------------------------------------------------------
// The board's own shape
// ---------------------------------------------------------------------------

test('the People Pillar carries both KPIs with the board response shape unchanged', async () => {
  const ground = await makeGround();
  await insertRosterEmployee(ground.lineA.id);
  await recordShift(ground, ground.lineA, '2026-05-04');

  const board = await getBoard(
    adminToken,
    ground.site.id,
    `?periodType=day&date=2026-05-04&orgUnitId=${ground.lineA.id}`
  );
  assert.strictEqual(board.response.status, 200);

  const people = board.payload.pillars.find((pillar) => pillar.code === 'P');
  assert.ok(people, 'the People Pillar is on the board');
  assert.strictEqual(people.hasData, true);

  // Exactly the fields the board has always sent for a KPI — this ticket adds
  // none and removes none (#251's own criterion, and why tier-board.test.js
  // needs no change).
  for (const code of ['PPL_ABSENTEEISM', 'PPL_HEADCOUNT']) {
    const kpi = people.kpis.find((candidate) => candidate.code === code);
    assert.ok(kpi, `${code} is on the People Pillar`);
    assert.deepStrictEqual(Object.keys(kpi).sort(), [
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
    assert.strictEqual(typeof kpi.value, 'number', `${code} is measured`);
  }

  // The catalogue's own metadata, unchanged by this ticket: absenteeism is a
  // percentage that should fall and the headcount is a count that should not.
  const absenteeism = people.kpis.find((candidate) => candidate.code === 'PPL_ABSENTEEISM');
  assert.strictEqual(absenteeism.unit, '%');
  assert.strictEqual(absenteeism.direction, 'lower_better');
  const headcount = people.kpis.find((candidate) => candidate.code === 'PPL_HEADCOUNT');
  assert.strictEqual(headcount.unit, 'count');
  assert.strictEqual(headcount.direction, 'higher_better');

  // The codes this Module deliberately leaves unclaimed still report nothing
  // (people/kpi-registry.js's own header): the board did not quietly gain
  // numbers for them alongside these two.
  for (const code of ['PPL_SKILL_COVERAGE', 'PPL_OVERDUE_ACTIONS']) {
    assert.strictEqual(readKpi(board.payload, 'P', code).status, 'no_data', code);
  }
});
