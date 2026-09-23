/*
 * The Safety KPIs on the tier board (issue #232, parent #223 decisions 3 and
 * 5) — over HTTP, against a real database and a real (locally issued) JWKS,
 * and read through the board's own existing address. The seam, the fixture
 * scaffolding and the dependency-ordered cleanup are the ones
 * `tier-board.test.js`, `quality-kpis.test.js` and `safety-incidents.test.js`
 * already establish.
 *
 * Every record this file asserts on is made **through the API**:
 * `POST /api/safety/sites/:siteId/incidents` and
 * `POST /api/safety/sites/:siteId/observations`. Because both tables are
 * filed by production day (ADR-0017), every test that reads the board back
 * generates a real shift calendar first — `insertShiftDefinition` plus
 * `generateShifts`, exactly as `safety-incidents.test.js`'s own
 * "production-day filing" test and `tier-board.test.js` do — rather than
 * relying on a row whose `fill_shift_instance` trigger left
 * `shift_instance_id` null, which none of these derived tables count (see
 * `safety/kpi-registry.js`'s own header).
 *
 * What is asserted, one test per acceptance criterion: `SAF_INCIDENTS` counts
 * the incidents that caused something (excluding `incident_type =
 * 'near_miss'`) for the chosen Org Unit and everything beneath it,
 * `SAF_NEARMISS` counts `incident_type = 'near_miss'` and not the severity
 * rung, `SAF_OBSERVATIONS` counts the observations logged, each with its own
 * period boundary, `SAF_TRIR`/`SAF_LTIFR` report `no_data` when nothing has
 * ever been confirmed anywhere in the subtree, and (issue #233, ADR-0041) the
 * two rates' own arithmetic, roll-up, rolling window and `no_data`-from-an-
 * unconfirmed-shift rule — the "What stays no_data" section below covers the
 * one case attendance never reaches, and the "SAF_TRIR and SAF_LTIFR" section
 * covers the rest, against a dedicated minimal ground (`makeRateGround`)
 * built one shift instance at a time, so a test never has to confirm more
 * shifts than the scenario it is proving needs.
 *
 * Needs a database with every migration applied. This slice adds no
 * migration of its own: the board computes on read, and every record it reads
 * was already in the baseline. Set DATABASE_URL first — see the README's
 * Tests section.
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
// The injury classification catalogue (issue #224), read by only one test in
// this file — the read-restriction one — and cleaned up by exactly the codes
// it created, never a truncation of a table the baseline seeds.
const insertedEmployeeIds = [];
const insertedInjuryTypeIds = [];
const insertedBodyPartIds = [];

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
  const subject = uniqueCode('safkpi');
  const { rows: [account] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status)
     VALUES ($1, 'Safety KPI Test Account', $2, $3, TRUE, 'approved') RETURNING id`,
    [`${subject}@example.com`, role, subject]
  );
  insertedAccountIds.push(account.id);

  // `safety` (ADR-0037) defaults to false, the same default
  // safety-incidents.test.js's own `insertAccount` uses — most Accounts here
  // hold no Safety authority, and the one test that needs it says so.
  for (const grant of grants) {
    await pool.query(
      `INSERT INTO app_user_org_units (app_user_id, org_unit_id, can_write, safety_authority)
       VALUES ($1, $2, $3, $4)`,
      [account.id, grant.orgUnitId, grant.write ?? true, grant.safety ?? false]
    );
  }

  return { id: account.id, token: await authHeader(subject) };
}

async function insertSite({ timezone = 'Asia/Ho_Chi_Minh', name = 'Safety KPI Test Site' } = {}) {
  const { rows: [site] } = await pool.query(
    `INSERT INTO sites (code, name, timezone) VALUES ($1, $2, $3) RETURNING id, code, name, timezone`,
    [uniqueCode('SKS'), name, timezone]
  );
  insertedSiteIds.push(site.id);
  return site;
}

async function insertOrgUnit(siteId, { parentId = null, unitType = 'area', name = 'KPI Unit' } = {}) {
  const { rows: [orgUnit] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, $2, $3, $4, $5) RETURNING id, code, name, path`,
    [siteId, parentId, uniqueCode('SKOU'), name, unitType]
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
  await pool.query('SELECT generate_shift_instances($1, $2::date, $3::date)', [
    orgUnitId,
    from,
    to
  ]);
  const { rows } = await pool.query('SELECT id FROM shift_instances WHERE org_unit_id = $1', [
    orgUnitId
  ]);
  for (const row of rows) insertedShiftInstanceIds.push(row.id);
}

async function recordIncident(token, siteId, body) {
  const response = await fetch(`${base}/api/safety/sites/${siteId}/incidents`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  return json(response);
}

async function recordObservation(token, siteId, body) {
  const response = await fetch(`${base}/api/safety/sites/${siteId}/observations`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  return json(response);
}

// Issue #224's classification: employee, injury type and body part, gated to
// a holder of Safety authority reaching the incident's Org Unit
// (ADR-0037) — the read-restriction test below is the only one in this file
// that needs any of it.
async function classifyIncident(token, id, body) {
  const response = await fetch(`${base}/api/safety/incidents/${id}/classify`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  return json(response);
}

async function insertEmployee() {
  const { rows: [row] } = await pool.query(
    `INSERT INTO employees (employee_no, first_name, last_name, is_active)
     VALUES ($1, 'Sam', 'Hardhat', TRUE) RETURNING id, display_name`,
    [uniqueCode('SKEMP')]
  );
  insertedEmployeeIds.push(row.id);
  return row;
}

async function insertInjuryType({ name = 'Fracture' } = {}) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO injury_types (code, name, is_active) VALUES ($1, $2, TRUE)
     RETURNING id, code, name`,
    [uniqueCode('SKIT'), name]
  );
  insertedInjuryTypeIds.push(row.id);
  return row;
}

async function insertBodyPart({ name = 'Left hand', region = 'upper_limb' } = {}) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO body_parts (code, name, region) VALUES ($1, $2, $3)
     RETURNING id, code, name, region`,
    [uniqueCode('SKBP'), name, region]
  );
  insertedBodyPartIds.push(row.id);
  return row;
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

function readKpi(board, pillarCode, kpiCode) {
  const kpi = findKpi(board, pillarCode, kpiCode);
  assert.ok(kpi, `${kpiCode} should be on the board`);
  return { value: kpi.value, status: kpi.status };
}

let admin;
let adminToken;

/**
 * The ground: a Site with a day shift running 06:00-14:00 local
 * (Asia/Ho_Chi_Minh, UTC+7) generated for a fixed window, an area with a line
 * beneath it and a sibling area with its own line, and a recorder granted a
 * write Grant on both areas. `occurredAt`/`observedAt` of `...T04:00:00Z` in
 * these tests is 11:00 local on the same calendar date — inside that shift —
 * so every record lands on production day `2026-05-04` with a real
 * `shift_instance_id`, which is what makes it visible to any of the three
 * derived tables in `safety/kpi-registry.js`.
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

  await insertShiftDefinition(site.id, { code: 'DAY', startTime: '06:00', durationMinutes: 480 });
  await generateShifts(area.id, '2026-05-01', '2026-05-08');
  await generateShifts(line.id, '2026-05-01', '2026-05-08');
  await generateShifts(otherArea.id, '2026-05-01', '2026-05-08');
  await generateShifts(otherLine.id, '2026-05-01', '2026-05-08');

  const recorder = await insertAccount({
    grants: [
      { orgUnitId: area.id, write: true },
      { orgUnitId: otherArea.id, write: true }
    ]
  });

  return { site, area, line, otherArea, otherLine, recorder };
}

const PRODUCTION_DAY = '2026-05-04';
const ON_SHIFT_AT = `${PRODUCTION_DAY}T04:00:00Z`;

async function recordCausedIncident(ground, orgUnit, overrides = {}) {
  const recorded = await recordIncident(ground.recorder.token, ground.site.id, {
    orgUnitId: orgUnit.id,
    occurredAt: ON_SHIFT_AT,
    incidentType: 'injury',
    severityLevel: 'first_aid',
    description: 'Recorded for the Safety KPI test.',
    ...overrides
  });
  assert.strictEqual(recorded.status, 201, JSON.stringify(recorded.body));
  return recorded.body.incident;
}

async function recordNearMiss(ground, orgUnit, overrides = {}) {
  const recorded = await recordIncident(ground.recorder.token, ground.site.id, {
    orgUnitId: orgUnit.id,
    occurredAt: ON_SHIFT_AT,
    incidentType: 'near_miss',
    severityLevel: 'near_miss',
    description: 'A near miss recorded for the Safety KPI test.',
    ...overrides
  });
  assert.strictEqual(recorded.status, 201, JSON.stringify(recorded.body));
  return recorded.body.incident;
}

async function recordAnObservation(ground, orgUnit, overrides = {}) {
  const recorded = await recordObservation(ground.recorder.token, ground.site.id, {
    orgUnitId: orgUnit.id,
    observedAt: ON_SHIFT_AT,
    observationType: 'unsafe_condition',
    category: 'housekeeping',
    severityPotential: 'low',
    description: 'Recorded for the Safety KPI test.',
    ...overrides
  });
  assert.strictEqual(recorded.status, 201, JSON.stringify(recorded.body));
  return recorded.body.observation;
}

// ---------------------------------------------------------------------------
// SAF_TRIR / SAF_LTIFR fixtures (issue #233, ADR-0041) — a dedicated,
// minimal ground built one shift instance at a time via
// `generate_shift_instances(orgUnitId, date, date)` rather than `makeGround`'s
// own 8-day, 4-Org-Unit calendar: ADR-0041's own rule makes ANY past shift
// instance in the window and subtree that lacks a confirmed sheet block the
// whole rate, so a test asserting a specific rate value must never leave a
// shift instance lying around it did not mean to create. Building exactly
// the days a test needs, and confirming every one of them (see
// `setUpConfirmedShift`), is what keeps that rule from becoming an accident
// of fixture size.
// ---------------------------------------------------------------------------

async function makeRateGround() {
  const site = await insertSite();
  const area = await insertOrgUnit(site.id, { name: 'Rate Area' });
  const lineA = await insertOrgUnit(site.id, { parentId: area.id, unitType: 'line', name: 'Rate Line A' });
  const lineB = await insertOrgUnit(site.id, { parentId: area.id, unitType: 'line', name: 'Rate Line B' });
  await insertShiftDefinition(site.id, { code: 'DAY', startTime: '06:00', durationMinutes: 480 });
  // One write Grant at the area: `canAct`'s own `target.path <@ granted.path`
  // reaches lineA and lineB too, so this one recorder can confirm anywhere in
  // this ground.
  const recorder = await insertAccount({ grants: [{ orgUnitId: area.id, write: true }] });
  return { site, area, lineA, lineB, recorder };
}

// An active Employee whose `default_org_unit_id` is `orgUnitId` — the
// Org-Unit-fallback branch of the roster pre-fill (no crew in this ground),
// exactly `attendance.js`'s own header describes. `employmentType` defaults
// to `permanent` but every value in the CHECK is a legal roster member
// (#247 decision 2: "whatever their employment_type").
async function insertRosterEmployee(orgUnitId, { employmentType = 'permanent' } = {}) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO employees (employee_no, first_name, last_name, is_active, default_org_unit_id, employment_type)
     VALUES ($1, 'Roster', 'Employee', TRUE, $2, $3) RETURNING id`,
    [uniqueCode('SKROS'), orgUnitId, employmentType]
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

async function confirmSheet(token, shiftInstanceId) {
  const response = await fetch(
    `${base}/api/people/shift-instances/${shiftInstanceId}/attendance-sheet/confirm`,
    { method: 'POST', headers: token }
  );
  return json(response);
}

// Generates exactly one shift instance (`generateShifts(orgUnit, date, date)`
// — never a wider range, see this section's own header), pre-fills it with
// `employeeCount` roster Employees (each an 8-hour shift under this ground's
// own DAY shift definition: 480 duration_minutes, 0 break_minutes), and
// confirms it. Returns the shift instance id, so a test can record an
// incident against the same production day.
async function setUpConfirmedShift(ground, orgUnit, date, { employeeCount = 0, employmentType = 'permanent' } = {}) {
  await generateShifts(orgUnit.id, date, date);
  const shiftInstanceId = await findShiftInstanceId(orgUnit.id, date);
  for (let i = 0; i < employeeCount; i += 1) {
    await insertRosterEmployee(orgUnit.id, { employmentType });
  }
  const confirmed = await confirmSheet(ground.recorder.token, shiftInstanceId);
  assert.strictEqual(confirmed.status, 200, JSON.stringify(confirmed.body));
  return shiftInstanceId;
}

// An incident on a chosen production day (unlike `recordCausedIncident`,
// which is pinned to `PRODUCTION_DAY` for the other three KPIs' own fixture).
// `T04:00:00Z` is 11:00 local (Asia/Ho_Chi_Minh, UTC+7) — inside the DAY
// shift's 06:00-14:00 window, exactly like `ON_SHIFT_AT` above.
async function recordIncidentOn(ground, orgUnit, date, overrides = {}) {
  const recorded = await recordIncident(ground.recorder.token, ground.site.id, {
    orgUnitId: orgUnit.id,
    occurredAt: `${date}T04:00:00Z`,
    incidentType: 'injury',
    severityLevel: 'medical_treatment',
    description: 'Recorded for the injury-rate test.',
    ...overrides
  });
  assert.strictEqual(recorded.status, 201, JSON.stringify(recorded.body));
  return recorded.body.incident;
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
  // Children before parents, exactly the order safety-incidents.test.js and
  // safety-observations.test.js already establish for these tables.
  await pool.query(
    `DELETE FROM safety_incidents
      WHERE org_unit_id IN (SELECT id FROM org_units WHERE site_id = ANY($1))`,
    [insertedSiteIds]
  );
  await pool.query(
    `DELETE FROM safety_observations
      WHERE org_unit_id IN (SELECT id FROM org_units WHERE site_id = ANY($1))`,
    [insertedSiteIds]
  );
  // attendance_records/attendance_sheets (issue #233's own fixtures, for
  // SAF_TRIR/SAF_LTIFR) both reference shift_instances and attendance_records
  // also references employees — both tables must go before either of those,
  // the same order attendance.test.js's own test.after establishes.
  await pool.query('DELETE FROM attendance_records WHERE shift_instance_id = ANY($1)', [
    insertedShiftInstanceIds
  ]);
  await pool.query('DELETE FROM attendance_sheets WHERE shift_instance_id = ANY($1)', [
    insertedShiftInstanceIds
  ]);
  // The classification catalogue (issue #224): only the read-restriction test
  // below creates any of these, and the incidents naming them are already
  // gone by this point.
  await pool.query('DELETE FROM employees WHERE id = ANY($1)', [insertedEmployeeIds]);
  await pool.query('DELETE FROM injury_types WHERE id = ANY($1)', [insertedInjuryTypeIds]);
  await pool.query('DELETE FROM body_parts WHERE id = ANY($1)', [insertedBodyPartIds]);
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
// SAF_INCIDENTS
// ---------------------------------------------------------------------------

test('the board counts incidents that caused something, excluding a near miss, for the chosen Org Unit and everything beneath it', async () => {
  const ground = await makeGround();

  // One at the area itself, one at the line beneath it, one at the sibling
  // area's line — all incidents that caused something — plus a near miss at
  // the line, which must not be counted here at all.
  await recordCausedIncident(ground, ground.area);
  await recordCausedIncident(ground, ground.line);
  await recordCausedIncident(ground, ground.otherLine);
  await recordNearMiss(ground, ground.line);

  const areaBoard = await getBoard(
    adminToken,
    ground.site.id,
    `?periodType=day&date=${PRODUCTION_DAY}&orgUnitId=${ground.area.id}`
  );
  assert.strictEqual(readKpi(areaBoard.payload, 'S', 'SAF_INCIDENTS').value, 2);

  const lineBoard = await getBoard(
    adminToken,
    ground.site.id,
    `?periodType=day&date=${PRODUCTION_DAY}&orgUnitId=${ground.line.id}`
  );
  assert.strictEqual(readKpi(lineBoard.payload, 'S', 'SAF_INCIDENTS').value, 1);

  const siteBoard = await getBoard(
    adminToken,
    ground.site.id,
    `?periodType=day&date=${PRODUCTION_DAY}`
  );
  assert.strictEqual(readKpi(siteBoard.payload, 'S', 'SAF_INCIDENTS').value, 3);
});

test('a damage-only event counts toward SAF_INCIDENTS and never toward SAF_NEARMISS', async () => {
  const ground = await makeGround();

  // A fire with no injury sits on severity_level's no-injury rung
  // (`near_miss`), but incident_type is `fire`: it is not a near miss.
  await recordCausedIncident(ground, ground.line, {
    incidentType: 'fire',
    severityLevel: 'near_miss'
  });

  const board = await getBoard(
    adminToken,
    ground.site.id,
    `?periodType=day&date=${PRODUCTION_DAY}&orgUnitId=${ground.line.id}`
  );
  assert.strictEqual(readKpi(board.payload, 'S', 'SAF_INCIDENTS').value, 1);
  assert.strictEqual(readKpi(board.payload, 'S', 'SAF_NEARMISS').value, null);
  assert.strictEqual(readKpi(board.payload, 'S', 'SAF_NEARMISS').status, 'no_data');
});

test('a period with no incident reports no_data for SAF_INCIDENTS, and the period boundary is respected', async () => {
  const ground = await makeGround();
  await recordCausedIncident(ground, ground.line);

  const quiet = await getBoard(
    adminToken,
    ground.site.id,
    `?periodType=day&date=2026-01-05&orgUnitId=${ground.line.id}`
  );
  const quietKpi = readKpi(quiet.payload, 'S', 'SAF_INCIDENTS');
  assert.strictEqual(quietKpi.value, null);
  assert.strictEqual(quietKpi.status, 'no_data');

  // The whole month it fell in still holds it.
  const month = await getBoard(
    adminToken,
    ground.site.id,
    `?periodType=month&date=${PRODUCTION_DAY}&orgUnitId=${ground.line.id}`
  );
  assert.strictEqual(readKpi(month.payload, 'S', 'SAF_INCIDENTS').value, 1);
});

test('a caller who may not read who was hurt still sees the right SAF_INCIDENTS number, and the board carries no injury detail at all', async () => {
  const ground = await makeGround();
  const employee = await insertEmployee();
  const injuryType = await insertInjuryType();
  const bodyPart = await insertBodyPart();

  // A holder of Safety authority (ADR-0037) at the line: the only Grant that
  // may name the injured Employee, the injury type and the body part.
  const safetyHolder = await insertAccount({
    grants: [{ orgUnitId: ground.line.id, write: true, safety: true }]
  });

  const recorded = await recordIncident(safetyHolder.token, ground.site.id, {
    orgUnitId: ground.line.id,
    occurredAt: ON_SHIFT_AT,
    incidentType: 'injury',
    // Above the no-injury rung, so an injury classification is meaningful on
    // it (`safety_incidents_near_miss_no_injury` forbids it on `near_miss`).
    severityLevel: 'medical_treatment',
    description: 'An injury classified for the Safety KPI read-restriction test.'
  });
  assert.strictEqual(recorded.status, 201, JSON.stringify(recorded.body));

  const classified = await classifyIncident(safetyHolder.token, recorded.body.incident.id, {
    employeeId: employee.id,
    injuryTypeId: injuryType.id,
    bodyPartId: bodyPart.id
  });
  assert.strictEqual(classified.status, 200, JSON.stringify(classified.body));
  assert.strictEqual(classified.body.incident.employeeId, employee.id);

  // A Site-wide reader with no Grant anywhere and no Safety authority — the
  // caller ADR-0037 refuses the three classified fields on the incident's own
  // detail address.
  const reader = await insertAccount({});

  const query = `?periodType=day&date=${PRODUCTION_DAY}&orgUnitId=${ground.line.id}`;
  const holderBoard = await getBoard(safetyHolder.token, ground.site.id, query);
  const readerBoard = await getBoard(reader.token, ground.site.id, query);

  assert.strictEqual(readerBoard.response.status, 200);
  const holderCount = readKpi(holderBoard.payload, 'S', 'SAF_INCIDENTS').value;
  const readerCount = readKpi(readerBoard.payload, 'S', 'SAF_INCIDENTS').value;
  assert.strictEqual(holderCount, 1);
  assert.strictEqual(readerCount, holderCount);

  // The board's own JSON carries none of the classified fields, for either
  // caller: a count is not a place an injury detail could leak through, and
  // this proves it rather than arguing it from the SQL alone.
  const serialisedForReader = JSON.stringify(readerBoard.payload);
  const serialisedForHolder = JSON.stringify(holderBoard.payload);
  for (const key of ['employeeId', 'injuryType', 'bodyPart']) {
    assert.ok(
      !serialisedForReader.includes(key),
      `the board read by a Site-wide reader should not carry ${key}`
    );
    assert.ok(
      !serialisedForHolder.includes(key),
      `the board read by a Safety authority holder should not carry ${key}`
    );
  }
});

// ---------------------------------------------------------------------------
// SAF_NEARMISS
// ---------------------------------------------------------------------------

test('the board counts near misses reported by incident_type, not by the severity rung, and rolls up the subtree', async () => {
  const ground = await makeGround();

  await recordNearMiss(ground, ground.area);
  await recordNearMiss(ground, ground.line);
  await recordNearMiss(ground, ground.otherLine);
  // A caused incident at the line: must not be counted as a near miss.
  await recordCausedIncident(ground, ground.line);

  const areaBoard = await getBoard(
    adminToken,
    ground.site.id,
    `?periodType=day&date=${PRODUCTION_DAY}&orgUnitId=${ground.area.id}`
  );
  assert.strictEqual(readKpi(areaBoard.payload, 'S', 'SAF_NEARMISS').value, 2);

  const siteBoard = await getBoard(
    adminToken,
    ground.site.id,
    `?periodType=day&date=${PRODUCTION_DAY}`
  );
  assert.strictEqual(readKpi(siteBoard.payload, 'S', 'SAF_NEARMISS').value, 3);

  // SAF_INCIDENTS on the same board excludes all three near misses, leaving
  // only the one caused incident at the line.
  assert.strictEqual(readKpi(siteBoard.payload, 'S', 'SAF_INCIDENTS').value, 1);
});

// ---------------------------------------------------------------------------
// SAF_OBSERVATIONS
// ---------------------------------------------------------------------------

test('the board counts the Safety observations logged in the period, for the chosen Org Unit and beneath it', async () => {
  const ground = await makeGround();

  await recordAnObservation(ground, ground.line);
  await recordAnObservation(ground, ground.area);
  await recordAnObservation(ground, ground.otherLine);

  const areaBoard = await getBoard(
    adminToken,
    ground.site.id,
    `?periodType=day&date=${PRODUCTION_DAY}&orgUnitId=${ground.area.id}`
  );
  assert.strictEqual(readKpi(areaBoard.payload, 'S', 'SAF_OBSERVATIONS').value, 2);

  const siteBoard = await getBoard(
    adminToken,
    ground.site.id,
    `?periodType=day&date=${PRODUCTION_DAY}`
  );
  assert.strictEqual(readKpi(siteBoard.payload, 'S', 'SAF_OBSERVATIONS').value, 3);
});

test('a period with no observation reports no_data for SAF_OBSERVATIONS', async () => {
  const ground = await makeGround();
  await recordAnObservation(ground, ground.line);

  const quiet = await getBoard(
    adminToken,
    ground.site.id,
    `?periodType=day&date=2026-01-05&orgUnitId=${ground.line.id}`
  );
  const quietKpi = readKpi(quiet.payload, 'S', 'SAF_OBSERVATIONS');
  assert.strictEqual(quietKpi.value, null);
  assert.strictEqual(quietKpi.status, 'no_data');
});

// ---------------------------------------------------------------------------
// What stays no_data, and why: no confirmed sheet anywhere in the subtree
// ---------------------------------------------------------------------------

test('SAF_TRIR and SAF_LTIFR report no_data when nothing has ever been confirmed in the subtree, and the board response shape is unchanged', async () => {
  const ground = await makeGround();
  await recordCausedIncident(ground, ground.line, { severityLevel: 'lost_time' });
  await recordNearMiss(ground, ground.line);
  await recordAnObservation(ground, ground.line);

  const { payload } = await getBoard(
    adminToken,
    ground.site.id,
    `?periodType=day&date=${PRODUCTION_DAY}`
  );

  // Neither rate has a floor to start from: makeGround's own shift calendar
  // has never had a sheet confirmed against it, so the window has not opened
  // (ADR-0041's own "Why not a no_data rule with no start date").
  for (const code of ['SAF_TRIR', 'SAF_LTIFR']) {
    const kpi = readKpi(payload, 'S', code);
    assert.strictEqual(kpi.value, null, `${code} must not have a value`);
    assert.notStrictEqual(kpi.value, 0, `${code} must never read as a measured zero`);
    assert.strictEqual(kpi.status, 'no_data', `${code} should be no_data`);
  }

  // And the Safety pillar is not empty on that board: the numbers this ticket
  // does claim are there beside them.
  assert.strictEqual(typeof readKpi(payload, 'S', 'SAF_INCIDENTS').value, 'number');
  assert.strictEqual(typeof readKpi(payload, 'S', 'SAF_NEARMISS').value, 'number');
  assert.strictEqual(typeof readKpi(payload, 'S', 'SAF_OBSERVATIONS').value, 'number');

  // The board's request and response shape is unchanged: the same query
  // parameters, the same five pillars, the same KPI fields.
  assert.deepStrictEqual(
    payload.pillars.map((pillar) => pillar.code),
    ['S', 'Q', 'D', 'C', 'P']
  );
  assert.deepStrictEqual(Object.keys(payload.pillars[0].kpis[0]).sort(), [
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

// ---------------------------------------------------------------------------
// SAF_TRIR and SAF_LTIFR (issue #233, ADR-0041)
// ---------------------------------------------------------------------------

test('SAF_TRIR and SAF_LTIFR sum incidents and hours over the window and subtree, then divide once — never averaged across days or Org Units', async () => {
  const ground = await makeRateGround();

  // lineA, 2026-05-01: 2 confirmed Employees (16 hours) plus one recordable
  // (medical_treatment) incident. lineB, 2026-05-04: 3 confirmed Employees
  // (24 hours), no incident. Two distinct Org Units, not two dates on the
  // same one: the roster pre-fill matches every active Employee whose
  // `default_org_unit_id` is the shift's Org Unit, with no date filter of its
  // own (`attendance.js`'s own header), so reusing one Org Unit for two
  // different production days would silently roll each day's earlier
  // Employees onto every later sheet at that same Org Unit too.
  await setUpConfirmedShift(ground, ground.lineA, '2026-05-01', { employeeCount: 2 });
  await recordIncidentOn(ground, ground.lineA, '2026-05-01', { severityLevel: 'medical_treatment' });
  await setUpConfirmedShift(ground, ground.lineB, '2026-05-04', { employeeCount: 3 });

  // Averaging each line's own daily rate would read
  // (200000*1/16 + 0) / 2 = 6250; summing both lines' incidents and hours
  // first and dividing once — at the area, which rolls up both lines — reads
  // 200000*1/40 = 5000. This is the roll-up and the sum-then-divide rule,
  // proved by the same read.
  const areaBoard = await getBoard(
    adminToken,
    ground.site.id,
    `?periodType=day&date=2026-05-04&orgUnitId=${ground.area.id}`
  );
  assert.strictEqual(readKpi(areaBoard.payload, 'S', 'SAF_TRIR').value, 5000);
  // Zero lost-time incidents over positive hours is a real, reportable zero —
  // this file's own header, "A ZERO IS A REAL MEASUREMENT HERE".
  assert.strictEqual(readKpi(areaBoard.payload, 'S', 'SAF_LTIFR').value, 0);

  // Reading lineA alone (excluding lineB from the subtree) shows the
  // un-rolled-up rate for comparison: 200000*1/16 = 12500 — different from
  // the area's 5000, because lineB's hours are excluded from the sum.
  const lineABoard = await getBoard(
    adminToken,
    ground.site.id,
    `?periodType=day&date=2026-05-04&orgUnitId=${ground.lineA.id}`
  );
  assert.strictEqual(readKpi(lineABoard.payload, 'S', 'SAF_TRIR').value, 12500);
});

test('the rolling 12-month window ends at the board period\'s end and ignores the period asked for, but never starts before the subtree\'s first confirmed sheet', async () => {
  const ground = await makeRateGround();

  // Before any confirmation exists anywhere in this ground, a shift instance
  // on 2026-01-01 is created and left with no attendance sheet at all — it
  // must never become a blocker, because it falls before the window's own
  // start point once that start point exists.
  await generateShifts(ground.lineA.id, '2026-01-01', '2026-01-01');

  // The subtree's first-ever confirmed sheet: 2026-03-01, 2 Employees
  // (16 hours), one recordable incident.
  await setUpConfirmedShift(ground, ground.lineA, '2026-03-01', { employeeCount: 2 });
  await recordIncidentOn(ground, ground.lineA, '2026-03-01', { severityLevel: 'medical_treatment' });

  // Asking for a period ending BEFORE the first confirmed sheet still reports
  // no_data: from that period's own end, the window has zero confirmed hours
  // to divide by, and the 2026-01-01 shift is excluded from it entirely
  // (its production_date is before the floor), so it is not what causes the
  // no_data here — there is simply nothing yet.
  const beforeFloor = await getBoard(
    adminToken,
    ground.site.id,
    `?periodType=day&date=2026-01-15&orgUnitId=${ground.lineA.id}`
  );
  assert.strictEqual(readKpi(beforeFloor.payload, 'S', 'SAF_TRIR').status, 'no_data');

  // Asking for a period ending on or after the floor reads the real rate, and
  // the pre-floor 2026-01-01 shift — created above, never confirmed — does
  // not block it: it falls outside the window the floor opened.
  const onFloor = await getBoard(
    adminToken,
    ground.site.id,
    `?periodType=day&date=2026-03-01&orgUnitId=${ground.lineA.id}`
  );
  assert.strictEqual(readKpi(onFloor.payload, 'S', 'SAF_TRIR').value, 12500); // 200000*1/16

  // A week-type board asked for seven weeks later still reads the same
  // 2026-03-01 hours and incident, because the window is the 12 months
  // ending at THAT period's own end, not the seven days the period itself
  // covers — ADR-0041's own "the one board number that ignores the period".
  const laterWeek = await getBoard(
    adminToken,
    ground.site.id,
    `?periodType=week&date=2026-04-20&orgUnitId=${ground.lineA.id}`
  );
  assert.strictEqual(readKpi(laterWeek.payload, 'S', 'SAF_TRIR').value, 12500);
});

test('a past, unconfirmed shift in the window and subtree makes the rate no_data, and confirming it brings the rate back', async () => {
  const ground = await makeRateGround();

  await setUpConfirmedShift(ground, ground.lineA, '2026-05-01', { employeeCount: 2 });
  await recordIncidentOn(ground, ground.lineA, '2026-05-01', { severityLevel: 'medical_treatment' });

  // A second, later shift instance in the same window and subtree, created
  // but never confirmed.
  await generateShifts(ground.lineA.id, '2026-05-04', '2026-05-04');
  const blockingShiftId = await findShiftInstanceId(ground.lineA.id, '2026-05-04');

  const blocked = await getBoard(
    adminToken,
    ground.site.id,
    `?periodType=day&date=2026-05-04&orgUnitId=${ground.lineA.id}`
  );
  assert.strictEqual(readKpi(blocked.payload, 'S', 'SAF_TRIR').value, null);
  assert.strictEqual(readKpi(blocked.payload, 'S', 'SAF_TRIR').status, 'no_data');
  assert.strictEqual(readKpi(blocked.payload, 'S', 'SAF_LTIFR').status, 'no_data');

  // Confirming the blocking shift brings the rate back — no new Employee is
  // added for this call, but the same 2 Employees from 2026-05-01 are still
  // active with `default_org_unit_id` = lineA, so the roster pre-fill (which
  // matches on Org Unit, not on date) adds them to this sheet too, for
  // another 16 hours: 32 hours total, 1 recordable incident,
  // 200000*1/32 = 6250.
  const confirmed = await confirmSheet(ground.recorder.token, blockingShiftId);
  assert.strictEqual(confirmed.status, 200, JSON.stringify(confirmed.body));

  const unblocked = await getBoard(
    adminToken,
    ground.site.id,
    `?periodType=day&date=2026-05-04&orgUnitId=${ground.lineA.id}`
  );
  assert.strictEqual(readKpi(unblocked.payload, 'S', 'SAF_TRIR').value, 6250);
});

test('SAF_TRIR counts medical-treatment-or-worse, SAF_LTIFR counts lost-time-or-worse, and a near miss counts in neither', async () => {
  const ground = await makeRateGround();

  await setUpConfirmedShift(ground, ground.lineA, '2026-05-01', { employeeCount: 4 }); // 32 hours

  // Below the recordable rung: never counted in either rate.
  await recordIncidentOn(ground, ground.lineA, '2026-05-01', { severityLevel: 'first_aid' });
  // Recordable, not lost-time: SAF_TRIR only.
  await recordIncidentOn(ground, ground.lineA, '2026-05-01', { severityLevel: 'medical_treatment' });
  // Recordable AND lost-time: both rates.
  await recordIncidentOn(ground, ground.lineA, '2026-05-01', { severityLevel: 'lost_time' });
  // A near miss has, by definition, no injury — counted in neither rate,
  // exactly as SAF_NEARMISS's own section above already establishes for the
  // period counts.
  await recordIncidentOn(ground, ground.lineA, '2026-05-01', {
    incidentType: 'near_miss',
    severityLevel: 'near_miss'
  });

  const board = await getBoard(
    adminToken,
    ground.site.id,
    `?periodType=day&date=2026-05-01&orgUnitId=${ground.lineA.id}`
  );
  // Recordable: medical_treatment + lost_time = 2, over 32 hours.
  assert.strictEqual(readKpi(board.payload, 'S', 'SAF_TRIR').value, (200000 * 2) / 32);
  // Lost-time: lost_time alone = 1, over 32 hours.
  assert.strictEqual(readKpi(board.payload, 'S', 'SAF_LTIFR').value, (1000000 * 1) / 32);
});

test('an Employee counts toward worked hours whatever their employment type', async () => {
  const ground = await makeRateGround();

  await generateShifts(ground.lineA.id, '2026-05-01', '2026-05-01');
  const shiftInstanceId = await findShiftInstanceId(ground.lineA.id, '2026-05-01');
  // Neither Employee is `permanent` (#247 decision 2: "whatever their
  // employment_type" — every value in the CHECK is a legal roster member).
  await insertRosterEmployee(ground.lineA.id, { employmentType: 'contractor' });
  await insertRosterEmployee(ground.lineA.id, { employmentType: 'apprentice' });
  const confirmed = await confirmSheet(ground.recorder.token, shiftInstanceId);
  assert.strictEqual(confirmed.status, 200, JSON.stringify(confirmed.body));

  await recordIncidentOn(ground, ground.lineA, '2026-05-01', { severityLevel: 'medical_treatment' });

  const board = await getBoard(
    adminToken,
    ground.site.id,
    `?periodType=day&date=2026-05-01&orgUnitId=${ground.lineA.id}`
  );
  // If either Employee's hours had been silently excluded for not being
  // `permanent`, the denominator would be 8 hours (12500 * 2 = 25000), not 16.
  assert.strictEqual(readKpi(board.payload, 'S', 'SAF_TRIR').value, 12500); // 200000*1/16
});
