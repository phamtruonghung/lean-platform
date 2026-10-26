/*
 * The Production KPIs on the tier board (issue #340, spec #332, ADR-0054) —
 * over HTTP, against a real database and a real (locally issued) JWKS, read
 * through the board's own existing address, which this ticket does not change.
 * The seam and the dependency-ordered cleanup are the ones handovers.test.js
 * and people-kpis.test.js already establish.
 *
 * Every handover these tests count is written **through the API** — opened,
 * its change-point block declared none, submitted by one Account and
 * acknowledged by another — and read back through `GET
 * /api/maintenance/sites/:siteId/board`. The shift instances are inserted
 * directly, as handovers.test.js inserts them, timed against the database's
 * own `now()` so "ended" and "still running" are facts the test controls. For
 * the median, each shift instance's clock is then set back from its
 * handover's recorded `acknowledged_at` by an exact number of minutes: the
 * acknowledgement itself still travels the API, and only the calendar the
 * latency is measured from is fixture.
 *
 * What is asserted, against #340's own acceptance criteria: a section with
 * four ended shift instances and three acknowledged handovers reports 75, and
 * a shift still running is not held against it; a section with no ended shift
 * instance reports `no_data`; the acknowledgement time is a median (4, 6,
 * 400 -> 6); a department reads its sections' handovers and not another
 * department's; and the two catalogue rows exist once however many times
 * their migration runs.
 *
 * Needs a database with every migration applied. Set DATABASE_URL first —
 * see AGENTS.md §3.
 */

const test = require('node:test');
const assert = require('node:assert');
const { createTestJwks } = require('../helpers/jwks');
const migration = require('../../migrations/1803200000000_production-handover-kpis');

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

let site;
let author; // edit Grant at the Site's root, so it reaches every section
let incoming; // the same reach: the incoming Team Leader who acknowledges

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
  return { authorization: 'Bearer ' + token };
}

async function json(response) {
  return { status: response.status, body: await response.json() };
}

async function insertAccount({ grants = [] } = {}) {
  const subject = uniqueCode('hokpi');
  const { rows: [account] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status)
     VALUES ($1, 'Handover KPI Test Account', 'operator', $2, TRUE, 'approved') RETURNING id`,
    [`${subject}@example.com`, subject]
  );
  insertedAccountIds.push(account.id);
  for (const grant of grants) {
    await pool.query(
      `INSERT INTO app_user_org_units (app_user_id, org_unit_id, can_write) VALUES ($1, $2, TRUE)`,
      [account.id, grant.orgUnitId]
    );
  }
  return { id: account.id, token: await authHeader(subject) };
}

async function insertOrgUnit(parentId, unitType, name) {
  const { rows: [orgUnit] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, $2, $3, $4, $5) RETURNING id, code, name`,
    [site.id, parentId, uniqueCode('HKOU'), name, unitType]
  );
  insertedOrgUnitIds.push(orgUnit.id);
  return orgUnit;
}

// A shift instance on `sectionId`, filed under `productionDate`, running from
// `startOffset` to `endOffset` minutes from the database's now. Each gets its
// own shift definition, so several can share a section and a day.
async function shift(sectionId, productionDate, startOffset, endOffset) {
  const { rows: [definition] } = await pool.query(
    `INSERT INTO shift_definitions (site_id, code, name, start_time, duration_minutes, break_minutes)
     VALUES ($1, $2, 'KPI shift', '06:00', 480, 30) RETURNING id`,
    [site.id, uniqueCode('HKSD')]
  );
  insertedShiftDefinitionIds.push(definition.id);
  const { rows: [row] } = await pool.query(
    `INSERT INTO shift_instances
       (site_id, org_unit_id, shift_definition_id, production_date, starts_at, ends_at,
        planned_production_minutes)
     VALUES ($1, $2, $3, $4::date, now() + make_interval(mins => $5), now() + make_interval(mins => $6), 450)
     RETURNING id`,
    [site.id, sectionId, definition.id, productionDate, startOffset, endOffset]
  );
  insertedShiftInstanceIds.push(row.id);
  return row.id;
}

async function post(token, path, body) {
  return json(
    await fetch(`${base}/api/production${path}`, {
      method: 'POST',
      headers: { ...token, 'content-type': 'application/json' },
      body: JSON.stringify(body ?? {})
    })
  );
}

// A handover for the shift, written and submitted by `author` through the
// API — the section has no Asset and no open Action, so declaring the change
// point block none is all submit asks — and, unless told otherwise,
// acknowledged by `incoming`. Returns the handover's id.
async function handOver(sectionId, shiftInstanceId, { acknowledge = true } = {}) {
  const opened = await post(author.token, '/handovers', { orgUnitId: sectionId, shiftInstanceId });
  assert.strictEqual(opened.status, 201, JSON.stringify(opened.body));
  const id = opened.body.handover.id;

  const declared = await json(
    await fetch(`${base}/api/production/handovers/${id}`, {
      method: 'PATCH',
      headers: { ...author.token, 'content-type': 'application/json' },
      body: JSON.stringify({ changePointsNone: true })
    })
  );
  assert.strictEqual(declared.status, 200, JSON.stringify(declared.body));

  const submitted = await post(author.token, `/handovers/${id}/submit`);
  assert.strictEqual(submitted.status, 200, JSON.stringify(submitted.body));

  if (acknowledge) {
    const acknowledged = await post(incoming.token, `/handovers/${id}/acknowledge`);
    assert.strictEqual(acknowledged.status, 200, JSON.stringify(acknowledged.body));
  }
  return id;
}

// Sets the shift instance's clock so it started exactly `minutes` before its
// handover's recorded acknowledgement. The window is one minute long so that
// several such shifts in one section never overlap (`shift_instances_no_overlap`).
async function acknowledgedAfter(shiftInstanceId, handoverId, minutes) {
  await pool.query(
    `UPDATE shift_instances si
        SET starts_at = h.acknowledged_at - make_interval(mins => $3),
            ends_at   = h.acknowledged_at - make_interval(mins => $3) + interval '1 minute'
       FROM shift_handovers h
      WHERE si.id = $1 AND h.id = $2`,
    [shiftInstanceId, handoverId, minutes]
  );
}

async function board(date, orgUnitId = null) {
  const query = new URLSearchParams({ periodType: 'day', date });
  if (orgUnitId !== null) query.set('orgUnitId', String(orgUnitId));
  const response = await fetch(`${base}/api/maintenance/sites/${site.id}/board?${query}`, {
    headers: author.token
  });
  const body = await response.json();
  assert.strictEqual(response.status, 200, JSON.stringify(body));
  return body;
}

function readKpi(payload, code) {
  const delivery = payload.pillars.find((pillar) => pillar.code === 'D');
  const kpi = delivery?.kpis.find((candidate) => candidate.code === code);
  assert.ok(kpi, `${code} should be on the board under Delivery`);
  return kpi;
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

  const { rows: [row] } = await pool.query(
    `INSERT INTO sites (code, name, timezone) VALUES ($1, 'Handover KPI Test Site', 'Asia/Ho_Chi_Minh')
     RETURNING id`,
    [uniqueCode('HKS')]
  );
  site = row;
  insertedSiteIds.push(site.id);

  const plant = await insertOrgUnit(null, 'department', 'Plant');
  author = await insertAccount({ grants: [{ orgUnitId: plant.id }] });
  incoming = await insertAccount({ grants: [{ orgUnitId: plant.id }] });
  site.plant = plant;
});

test.after(async () => {
  // Handovers first: they cascade to their lines and reference the shift
  // instances, the sections and both Accounts.
  await pool.query('DELETE FROM shift_handovers WHERE org_unit_id = ANY($1)', [insertedOrgUnitIds]);
  await pool.query('DELETE FROM shift_instances WHERE id = ANY($1)', [insertedShiftInstanceIds]);
  await pool.query('DELETE FROM shift_definitions WHERE id = ANY($1)', [insertedShiftDefinitionIds]);
  await pool.query('DELETE FROM app_user_org_units WHERE app_user_id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM app_users WHERE id = ANY($1)', [insertedAccountIds]);
  // Children before parents.
  for (const id of [...insertedOrgUnitIds].reverse()) {
    await pool.query('DELETE FROM org_units WHERE id = $1', [id]);
  }
  await pool.query('DELETE FROM sites WHERE id = ANY($1)', [insertedSiteIds]);
  await new Promise((resolve) => server.close(resolve));
  await closePool();
  await jwks.close();
});

test('four ended shifts and three acknowledged handovers read 75, and a running shift is not counted', async () => {
  const date = '2026-03-02';
  const department = await insertOrgUnit(site.plant.id, 'department', 'Completion department');
  const section = await insertOrgUnit(department.id, 'section', 'Completion section');

  await handOver(section.id, await shift(section.id, date, -1920, -1440));
  await handOver(section.id, await shift(section.id, date, -1440, -960));
  await handOver(section.id, await shift(section.id, date, -960, -480));
  // Submitted, never acknowledged: in the denominator, not the numerator.
  await handOver(section.id, await shift(section.id, date, -480, -30), { acknowledge: false });
  // Still running and nobody has handed it over: not held against the section.
  await shift(section.id, date, -30, 450);

  const payload = await board(date, section.id);
  const completion = readKpi(payload, 'PRO_HANDOVER_COMPLETION');
  assert.strictEqual(completion.value, 75);
  assert.strictEqual(completion.status, 'no_target');
  assert.strictEqual(completion.unit, '%');
  assert.strictEqual(completion.direction, 'higher_better');

  const minutes = readKpi(payload, 'PRO_HANDOVER_ACK_MINUTES');
  assert.strictEqual(typeof minutes.value, 'number', 'three acknowledged handovers have a median');
  assert.strictEqual(minutes.unit, 'minutes');
  assert.strictEqual(minutes.direction, 'lower_better');
});

test('a section with no ended shift instance reports no_data for both, never 0', async () => {
  const date = '2026-03-03';
  const department = await insertOrgUnit(site.plant.id, 'department', 'Quiet department');
  const section = await insertOrgUnit(department.id, 'section', 'Quiet section');
  await shift(section.id, date, -60, 420);

  const payload = await board(date, section.id);
  for (const code of ['PRO_HANDOVER_COMPLETION', 'PRO_HANDOVER_ACK_MINUTES']) {
    const kpi = readKpi(payload, code);
    assert.strictEqual(kpi.value, null, code);
    assert.strictEqual(kpi.status, 'no_data', code);
  }
});

test('the acknowledgement time is the median, not the mean: 4, 6 and 400 minutes read 6', async () => {
  const date = '2026-03-04';
  const department = await insertOrgUnit(site.plant.id, 'department', 'Median department');
  const section = await insertOrgUnit(department.id, 'section', 'Median section');

  for (const [index, minutes] of [4, 6, 400].entries()) {
    const shiftInstanceId = await shift(section.id, date, -3000 + index * 500, -2900 + index * 500);
    const handoverId = await handOver(section.id, shiftInstanceId);
    await acknowledgedAfter(shiftInstanceId, handoverId, minutes);
  }

  const payload = await board(date, section.id);
  assert.strictEqual(readKpi(payload, 'PRO_HANDOVER_ACK_MINUTES').value, 6, 'the mean would be 136.7');
  assert.strictEqual(readKpi(payload, 'PRO_HANDOVER_COMPLETION').value, 100);
});

test("a department reads its own sections' handovers and not another department's", async () => {
  const date = '2026-03-05';
  const department = await insertOrgUnit(site.plant.id, 'department', 'Rolled-up department');
  const sectionA = await insertOrgUnit(department.id, 'section', 'Section A');
  const sectionB = await insertOrgUnit(department.id, 'section', 'Section B');
  const elsewhere = await insertOrgUnit(site.plant.id, 'department', 'Other department');
  const sectionC = await insertOrgUnit(elsewhere.id, 'section', 'Section C');

  // A: two ended, both acknowledged. B: two ended, one acknowledged.
  await handOver(sectionA.id, await shift(sectionA.id, date, -900, -480));
  await handOver(sectionA.id, await shift(sectionA.id, date, -480, -60));
  await handOver(sectionB.id, await shift(sectionB.id, date, -900, -480));
  await shift(sectionB.id, date, -480, -60);
  // C, in the other department: two ended, neither handed over.
  await shift(sectionC.id, date, -900, -480);
  await shift(sectionC.id, date, -480, -60);

  assert.strictEqual(readKpi(await board(date, department.id), 'PRO_HANDOVER_COMPLETION').value, 75);
  assert.strictEqual(readKpi(await board(date, sectionB.id), 'PRO_HANDOVER_COMPLETION').value, 50);
  assert.strictEqual(readKpi(await board(date, elsewhere.id), 'PRO_HANDOVER_COMPLETION').value, 0);
  assert.strictEqual(
    readKpi(await board(date, elsewhere.id), 'PRO_HANDOVER_ACK_MINUTES').status,
    'no_data',
    'nothing acknowledged in the other department'
  );
  // The whole Site: three of six.
  assert.strictEqual(readKpi(await board(date), 'PRO_HANDOVER_COMPLETION').value, 50);
});

test('the two catalogue rows exist once however many times their migration runs', async () => {
  const shim = { statements: [], sql(statement) { this.statements.push(statement); } };
  migration.up(shim);
  migration.up(shim);
  for (const statement of shim.statements) await pool.query(statement);

  const { rows } = await pool.query(
    `SELECT code, pillar_code, unit, direction, calculation_type, COUNT(*) OVER (PARTITION BY code)::int AS copies
       FROM kpi_definitions
      WHERE code IN ('PRO_HANDOVER_COMPLETION', 'PRO_HANDOVER_ACK_MINUTES')
      ORDER BY code`
  );
  assert.deepStrictEqual(rows, [
    {
      code: 'PRO_HANDOVER_ACK_MINUTES', pillar_code: 'D', unit: 'minutes',
      direction: 'lower_better', calculation_type: 'derived', copies: 1
    },
    {
      code: 'PRO_HANDOVER_COMPLETION', pillar_code: 'D', unit: '%',
      direction: 'higher_better', calculation_type: 'derived', copies: 1
    }
  ]);
});
