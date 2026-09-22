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
 * period boundary, and `SAF_TRIR`/`SAF_LTIFR` keep reporting `no_data` on a
 * Site that does have Safety records.
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
// What stays no_data, and why: SAF_TRIR and SAF_LTIFR
// ---------------------------------------------------------------------------

test('SAF_TRIR and SAF_LTIFR keep reporting no_data, on a Site that does have Safety records', async () => {
  const ground = await makeGround();
  await recordCausedIncident(ground, ground.line, { severityLevel: 'lost_time' });
  await recordNearMiss(ground, ground.line);
  await recordAnObservation(ground, ground.line);

  const { payload } = await getBoard(
    adminToken,
    ground.site.id,
    `?periodType=day&date=${PRODUCTION_DAY}`
  );

  // Both are rates per worked hour, and nothing writes attendance_records:
  // a number here would be invented, so the board keeps saying what it said
  // before this ticket.
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
