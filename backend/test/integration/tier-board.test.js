/*
 * The tier board over HTTP (issue #76), against a real database and a real
 * (locally issued) JWKS — the same seam as work-orders.test.js and
 * downtime.test.js, whose fixture scaffolding this file mirrors closely.
 * Sites, Org Units, Assets, shift definitions, downtime events, work orders
 * and targets are inserted directly against the database rather than through
 * their own endpoints: this file is about the board reading what those tables
 * produce, and each of those surfaces is already covered by its own file.
 *
 * Every test owns a fresh Site and Org Unit because a board is a Site-wide
 * read: a stop another test left behind would otherwise appear in an
 * assertion about this Site's numbers.
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
const insertedShiftDefinitionIds = [];
const insertedShiftInstanceIds = [];
const insertedDowntimeIds = [];
const insertedWorkOrderIds = [];
const insertedKpiTargetIds = [];

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
     VALUES ($1, 'Tier Board Test Account', $2, $3, TRUE, 'approved') RETURNING id`,
    [`${subject}@example.com`, role, subject]
  );
  insertedAccountIds.push(row.id);
  return { id: row.id, token: await authHeader(subject) };
}

async function insertSite({ timezone = 'Asia/Ho_Chi_Minh', name = 'Tier Board Test Site' } = {}) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO sites (code, name, timezone) VALUES ($1, $2, $3) RETURNING id, code, name, timezone`,
    [uniqueCode('ST'), name, timezone]
  );
  insertedSiteIds.push(row.id);
  return row;
}

async function insertOrgUnit(siteId, { parentId = null, unitType = 'area', name = 'Board Unit' } = {}) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, $2, $3, $4, $5) RETURNING id, code, name, path`,
    [siteId, parentId, uniqueCode('OU'), name, unitType]
  );
  insertedOrgUnitIds.push(row.id);
  return row;
}

async function insertAsset(orgUnitId, { name = 'Board Asset' } = {}) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO assets (org_unit_id, code, name, asset_type, criticality)
     VALUES ($1, $2, $3, 'machine', 'high') RETURNING id, org_unit_id`,
    [orgUnitId, uniqueCode('AS'), name]
  );
  insertedAssetIds.push(row.id);
  return row;
}

async function insertShiftDefinition(siteId, {
  code = 'DAY',
  name = 'Day shift',
  startTime = '06:00',
  durationMinutes = 480,
  dayOffset = 0
} = {}) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO shift_definitions (site_id, code, name, start_time, duration_minutes, day_offset)
     VALUES ($1, $2, $3, $4, $5, $6) RETURNING id`,
    [siteId, uniqueCode(code), name, startTime, durationMinutes, dayOffset]
  );
  insertedShiftDefinitionIds.push(row.id);
  return row;
}

// Builds the shift calendar through the database's own machinery, exactly the
// function a real deployment calls — not a hand-written shift_instances row.
async function generateShifts(orgUnitId, from, to) {
  await pool.query('SELECT generate_shift_instances($1, $2::date, $3::date)', [orgUnitId, from, to]);
  const { rows } = await pool.query(
    'SELECT id FROM shift_instances WHERE org_unit_id = $1',
    [orgUnitId]
  );
  for (const row of rows) insertedShiftInstanceIds.push(row.id);
}

// The shift_instance_id is filled by the table's own BEFORE INSERT trigger
// (fill_shift_instance), so the caller supplies only the stop and the reason.
async function insertBreakdown({ assetId, startedAt, endedAt, reasonCode = 'BRK' }) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO downtime_events (asset_id, downtime_reason_id, started_at, ended_at)
     VALUES ($1, (SELECT id FROM downtime_reasons WHERE code = $2), $3, $4)
     RETURNING id, org_unit_id, shift_instance_id`,
    [assetId, reasonCode, startedAt, endedAt]
  );
  insertedDowntimeIds.push(row.id);
  return row;
}

// An open work order with an estimate, for v_maintenance_backlog — no dates
// needed, which keeps the rollup test about the subtree and nothing else.
async function insertOpenWorkOrder(orgUnitId, { estimatedHours = 1, summary = 'Open job' } = {}) {
  const asset = await insertAsset(orgUnitId);
  const { rows: [row] } = await pool.query(
    `INSERT INTO work_orders (work_order_no, asset_id, summary, work_type, priority, status, estimated_hours)
     VALUES ($1, $2, $3, 'corrective', 3, 'approved', $4) RETURNING id`,
    [uniqueCode('WO'), asset.id, summary, estimatedHours]
  );
  insertedWorkOrderIds.push(row.id);
  return row;
}

async function insertKpiTarget({
  kpiCode,
  orgUnitId,
  periodType = 'day',
  targetValue,
  lowerThreshold = null,
  upperThreshold = null,
  effectiveFrom = '2026-01-01'
}) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO kpi_targets
       (kpi_definition_id, org_unit_id, period_type, target_value,
        lower_threshold, upper_threshold, effective_from)
     VALUES ((SELECT id FROM kpi_definitions WHERE code = $1), $2, $3, $4, $5, $6, $7)
     RETURNING id`,
    [kpiCode, orgUnitId, periodType, targetValue, lowerThreshold, upperThreshold, effectiveFrom]
  );
  insertedKpiTargetIds.push(row.id);
  return row;
}

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

let admin;
let noGrantAccount;

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
});

test.after(async () => {
  await pool.query('DELETE FROM kpi_targets WHERE id = ANY($1)', [insertedKpiTargetIds]);
  await pool.query('DELETE FROM work_orders WHERE id = ANY($1)', [insertedWorkOrderIds]);
  await pool.query('DELETE FROM downtime_events WHERE id = ANY($1)', [insertedDowntimeIds]);
  await pool.query('DELETE FROM shift_instances WHERE id = ANY($1)', [insertedShiftInstanceIds]);
  await pool.query('DELETE FROM shift_definitions WHERE id = ANY($1)', [insertedShiftDefinitionIds]);
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
// Shape: every Pillar, always, whether or not it has data.
// ---------------------------------------------------------------------------

test('the board returns all five Pillars in catalogue order, with KPIs listed as having no data', async () => {
  const site = await insertSite();
  const unit = await insertOrgUnit(site.id, { name: 'Quiet Area' });

  const { response, payload } = await getBoard(admin.token, site.id, '?periodType=day&date=2026-03-10');
  assert.strictEqual(response.status, 200);

  assert.strictEqual(payload.site.id, String(site.id));
  assert.strictEqual(payload.site.timezone, 'Asia/Ho_Chi_Minh');
  assert.strictEqual(payload.orgUnit, null);
  assert.deepStrictEqual(payload.period, { type: 'day', start: '2026-03-10', end: '2026-03-10' });

  assert.deepStrictEqual(
    payload.pillars.map((pillar) => pillar.code),
    ['S', 'Q', 'D', 'C', 'P']
  );
  for (const pillar of payload.pillars) {
    assert.ok(pillar.name, `pillar ${pillar.code} should carry its name`);
    assert.strictEqual(typeof pillar.sortOrder, 'number');
    assert.ok(Array.isArray(pillar.kpis));
  }

  // Delivery and Cost are the maintenance Module's own pillars, so they carry
  // its definitions; Safety, Quality and People have none from this Module and
  // are still returned, empty and marked so, rather than dropped.
  const delivery = payload.pillars.find((pillar) => pillar.code === 'D');
  assert.ok(delivery.kpis.some((kpi) => kpi.code === 'MNT_MTBF'));
  assert.strictEqual(delivery.hasData, false);

  // The full KPI shape: its identity, its unit, its direction, its display
  // precision, the plain-language formula, and the measured state.
  const mtbf = findKpi(payload, 'D', 'MNT_MTBF');
  assert.deepStrictEqual(mtbf, {
    code: 'MNT_MTBF',
    name: 'Mean time between failures',
    unit: 'hours',
    direction: 'higher_better',
    decimalPlaces: 1,
    formulaText: 'scheduled uptime / breakdown count',
    value: null,
    status: 'no_data',
    targetValue: null
  });

  // The narrow to a real Org Unit echoes it back rather than the root.
  const narrowed = await getBoard(admin.token, site.id, `?periodType=day&date=2026-03-10&orgUnitId=${unit.id}`);
  assert.deepStrictEqual(narrowed.payload.orgUnit, {
    id: String(unit.id),
    name: unit.name,
    path: unit.path
  });
});

test('a KPI with no data reports value null and status no_data, never zero', async () => {
  const site = await insertSite();
  await insertOrgUnit(site.id, { name: 'Empty Area' });

  const { payload } = await getBoard(admin.token, site.id, '?periodType=day&date=2026-03-10');
  for (const kpiCode of ['MNT_MTBF', 'MNT_MTTR', 'MNT_COST', 'MNT_PARTS_COST', 'MNT_BACKLOG']) {
    const kpi = findKpi(payload, kpiCode === 'MNT_COST' || kpiCode === 'MNT_PARTS_COST' ? 'C' : 'D', kpiCode);
    assert.strictEqual(kpi.value, null, `${kpiCode} should be null`);
    assert.notStrictEqual(kpi.value, 0, `${kpiCode} must never read as a measured zero`);
    assert.strictEqual(kpi.status, 'no_data', `${kpiCode} should be no_data`);
  }
});

// ---------------------------------------------------------------------------
// Period: the Site's production day, not the calendar or UTC day.
// ---------------------------------------------------------------------------

test("a day period buckets a stop by the Site's production day, not the UTC calendar date", async () => {
  // New York: a stop at 02:30 UTC on the 11th is 22:30 local on the 10th. At
  // a Site whose first (only) shift starts at 22:00, that instant belongs to
  // the 10th's production day — the shift that owns it — even though the
  // calendar date in UTC is already the 11th.
  const site = await insertSite({ timezone: 'America/New_York', name: 'Night Site' });
  const line = await insertOrgUnit(site.id, { name: 'Night Line', unitType: 'line' });
  const asset = await insertAsset(line.id);
  await insertShiftDefinition(site.id, { code: 'NIGHT', startTime: '22:00', durationMinutes: 480 });
  await generateShifts(line.id, '2026-03-09', '2026-03-12');

  await insertBreakdown({
    assetId: asset.id,
    startedAt: '2026-03-11T02:30:00Z',
    endedAt: '2026-03-11T03:30:00Z'
  });

  const onProductionDay = await getBoard(
    admin.token,
    site.id,
    `?periodType=day&date=2026-03-10&orgUnitId=${line.id}`
  );
  assert.strictEqual(onProductionDay.response.status, 200);
  const mttr = findKpi(onProductionDay.payload, 'D', 'MNT_MTTR');
  assert.strictEqual(mttr.value, 1, 'the one-hour stop belongs to the 10th');
  assert.strictEqual(mttr.status, 'no_target');

  const onUtcDate = await getBoard(
    admin.token,
    site.id,
    `?periodType=day&date=2026-03-11&orgUnitId=${line.id}`
  );
  assert.strictEqual(findKpi(onUtcDate.payload, 'D', 'MNT_MTTR').value, null);
  assert.strictEqual(findKpi(onUtcDate.payload, 'D', 'MNT_MTTR').status, 'no_data');
});

// ---------------------------------------------------------------------------
// Rollup: the chosen Org Unit and everything beneath it.
// ---------------------------------------------------------------------------

test('the Org-Unit-and-beneath rollup includes a child and its descendants, and excludes a sibling', async () => {
  const site = await insertSite();
  const area = await insertOrgUnit(site.id, { name: 'Rollup Area' });
  const line = await insertOrgUnit(site.id, { parentId: area.id, unitType: 'line', name: 'Line A' });
  const cell = await insertOrgUnit(site.id, { parentId: line.id, unitType: 'cell', name: 'Cell A' });
  const sibling = await insertOrgUnit(site.id, { parentId: area.id, unitType: 'line', name: 'Line B' });

  await insertOpenWorkOrder(line.id, { estimatedHours: 3, summary: 'On Line A' });
  await insertOpenWorkOrder(cell.id, { estimatedHours: 2, summary: 'On Cell A' });
  await insertOpenWorkOrder(sibling.id, { estimatedHours: 5, summary: 'On Line B' });

  const { payload } = await getBoard(
    admin.token,
    site.id,
    `?periodType=day&date=2026-03-10&orgUnitId=${line.id}`
  );
  const backlog = findKpi(payload, 'D', 'MNT_BACKLOG');
  assert.strictEqual(backlog.value, 5, 'Line A (3) + Cell A beneath it (2), never sibling Line B (5)');
});

// ---------------------------------------------------------------------------
// Targets and direction.
// ---------------------------------------------------------------------------

// One day shift for a known production day, with a one-hour breakdown. MTBF is
// (480 planned - 60 stopped) / 1 failure / 60 = 7.0 hours; MTTR is 60 / 1 / 60
// = 1.0 hour. Both feed the direction assertions below.
async function siteWithOneBreakdown() {
  const site = await insertSite();
  const line = await insertOrgUnit(site.id, { name: 'Target Line', unitType: 'line' });
  const asset = await insertAsset(line.id);
  await insertShiftDefinition(site.id, { code: 'DAY', startTime: '06:00', durationMinutes: 480 });
  await generateShifts(line.id, '2026-03-10', '2026-03-10');
  await insertBreakdown({
    assetId: asset.id,
    startedAt: '2026-03-09T23:30:00Z',
    endedAt: '2026-03-10T00:30:00Z'
  });
  return { site, line };
}

test('a higher_better KPI below target is not green, and the amber floor is honoured', async () => {
  const { site, line } = await siteWithOneBreakdown();
  const target = await insertKpiTarget({
    kpiCode: 'MNT_MTBF',
    orgUnitId: line.id,
    targetValue: 10,
    lowerThreshold: 5
  });

  const { payload } = await getBoard(
    admin.token,
    site.id,
    `?periodType=day&date=2026-03-10&orgUnitId=${line.id}`
  );
  const mtbf = findKpi(payload, 'D', 'MNT_MTBF');
  assert.strictEqual(mtbf.value, 7);
  assert.strictEqual(mtbf.targetValue, 10);
  assert.strictEqual(mtbf.status, 'amber');
  assert.notStrictEqual(mtbf.status, 'green');

  // Meeting the target flips it green — the direction is not inverted.
  await pool.query('UPDATE kpi_targets SET target_value = 5, lower_threshold = 3 WHERE id = $1', [target.id]);
  const met = await getBoard(admin.token, site.id, `?periodType=day&date=2026-03-10&orgUnitId=${line.id}`);
  assert.strictEqual(findKpi(met.payload, 'D', 'MNT_MTBF').status, 'green');
});

test('a lower_better KPI above target is not green, and the amber ceiling is honoured', async () => {
  const { site, line } = await siteWithOneBreakdown();
  const target = await insertKpiTarget({
    kpiCode: 'MNT_MTTR',
    orgUnitId: line.id,
    targetValue: 0.5,
    upperThreshold: 2
  });

  const { payload } = await getBoard(
    admin.token,
    site.id,
    `?periodType=day&date=2026-03-10&orgUnitId=${line.id}`
  );
  const mttr = findKpi(payload, 'D', 'MNT_MTTR');
  assert.strictEqual(mttr.value, 1);
  assert.strictEqual(mttr.targetValue, 0.5);
  assert.strictEqual(mttr.status, 'amber');
  assert.notStrictEqual(mttr.status, 'green');

  // At or below target flips it green — the direction is not inverted.
  await pool.query('UPDATE kpi_targets SET target_value = 2, upper_threshold = 3 WHERE id = $1', [target.id]);
  const met = await getBoard(admin.token, site.id, `?periodType=day&date=2026-03-10&orgUnitId=${line.id}`);
  assert.strictEqual(findKpi(met.payload, 'D', 'MNT_MTTR').status, 'green');
});

test('a KPI with data and no target reports no_target, not no_data', async () => {
  const { site, line } = await siteWithOneBreakdown();
  const { payload } = await getBoard(
    admin.token,
    site.id,
    `?periodType=day&date=2026-03-10&orgUnitId=${line.id}`
  );
  const mttr = findKpi(payload, 'D', 'MNT_MTTR');
  assert.strictEqual(mttr.value, 1);
  assert.strictEqual(mttr.targetValue, null);
  assert.strictEqual(mttr.status, 'no_target');
});

test('a target set at an ancestor Org Unit is inherited by one with none of its own', async () => {
  const site = await insertSite();
  const root = await insertOrgUnit(site.id, { name: 'Plant Root' });
  const line = await insertOrgUnit(site.id, { parentId: root.id, unitType: 'line', name: 'Inheriting Line' });
  await insertOpenWorkOrder(line.id, { estimatedHours: 4, summary: 'Inherits the plant target' });
  await insertKpiTarget({
    kpiCode: 'MNT_BACKLOG',
    orgUnitId: root.id,
    targetValue: 10,
    upperThreshold: 20
  });

  const { payload } = await getBoard(
    admin.token,
    site.id,
    `?periodType=day&date=2026-03-10&orgUnitId=${line.id}`
  );
  const backlog = findKpi(payload, 'D', 'MNT_BACKLOG');
  assert.strictEqual(backlog.value, 4);
  assert.strictEqual(backlog.targetValue, 10, "the plant's target reaches the line");
  assert.strictEqual(backlog.status, 'green');
});

// ---------------------------------------------------------------------------
// Reading: Site-wide, ungated by Grants; request shape.
// ---------------------------------------------------------------------------

test('the board is readable by an approved Account holding no Grant anywhere', async () => {
  const site = await insertSite();
  await insertOrgUnit(site.id, { name: 'Ungated Area' });

  const { response } = await getBoard(noGrantAccount.token, site.id, '?periodType=day&date=2026-03-10');
  assert.strictEqual(response.status, 200);
});

test('a request with no bearer token is refused', async () => {
  const site = await insertSite();
  const response = await fetch(`${base}/api/maintenance/sites/${site.id}/board`);
  assert.strictEqual(response.status, 401);
});

test('an unknown Site is a 404, not an empty board', async () => {
  const { response, payload } = await getBoard(admin.token, '999999999', '?periodType=day');
  assert.strictEqual(response.status, 404);
  assert.strictEqual(payload.message, 'Site not found');
});

test('an unknown or cross-Site ?orgUnitId= is a 404', async () => {
  const site = await insertSite();
  const otherSite = await insertSite();
  const otherUnit = await insertOrgUnit(otherSite.id, { name: 'Other Site Unit' });

  const unknown = await getBoard(admin.token, site.id, '?periodType=day&orgUnitId=999999999');
  assert.strictEqual(unknown.response.status, 404);
  assert.strictEqual(unknown.payload.message, 'Org Unit not found');

  const malformed = await getBoard(admin.token, site.id, '?periodType=day&orgUnitId=not-an-id');
  assert.strictEqual(malformed.response.status, 404);

  const crossSite = await getBoard(admin.token, site.id, `?periodType=day&orgUnitId=${otherUnit.id}`);
  assert.strictEqual(crossSite.response.status, 404);
  assert.strictEqual(crossSite.payload.message, 'Org Unit not found');
});

test('a missing or bad periodType, or a malformed date, is a clean 400', async () => {
  const site = await insertSite();

  const missingType = await getBoard(admin.token, site.id, '');
  assert.strictEqual(missingType.response.status, 400);

  const badType = await getBoard(admin.token, site.id, '?periodType=quarter');
  assert.strictEqual(badType.response.status, 400);

  const badDate = await getBoard(admin.token, site.id, '?periodType=day&date=2026-13-40');
  assert.strictEqual(badDate.response.status, 400);
  assert.strictEqual(badDate.payload.message, 'date must be a valid YYYY-MM-DD date');

  const nonsenseDate = await getBoard(admin.token, site.id, '?periodType=day&date=nonsense');
  assert.strictEqual(nonsenseDate.response.status, 400);
});

test('week and month resolve to the production week (Monday-based) and month containing the date', async () => {
  const site = await insertSite();
  await insertOrgUnit(site.id, { name: 'Period Area' });

  const week = await getBoard(admin.token, site.id, '?periodType=week&date=2026-03-11');
  assert.strictEqual(week.response.status, 200);
  assert.deepStrictEqual(week.payload.period, { type: 'week', start: '2026-03-09', end: '2026-03-15' });

  const month = await getBoard(admin.token, site.id, '?periodType=month&date=2026-03-11');
  assert.strictEqual(month.response.status, 200);
  assert.deepStrictEqual(month.payload.period, { type: 'month', start: '2026-03-01', end: '2026-03-31' });
});

test('a shift period requires a real shiftInstanceId belonging to the Site', async () => {
  const site = await insertSite();
  const line = await insertOrgUnit(site.id, { name: 'Shift Line', unitType: 'line' });
  await insertShiftDefinition(site.id, { code: 'DAY' });
  await generateShifts(line.id, '2026-03-10', '2026-03-10');
  const { rows: [shift] } = await pool.query(
    `SELECT id, production_date FROM shift_instances WHERE org_unit_id = $1 LIMIT 1`,
    [line.id]
  );

  const missing = await getBoard(admin.token, site.id, '?periodType=shift');
  assert.strictEqual(missing.response.status, 400);

  const unknown = await getBoard(admin.token, site.id, '?periodType=shift&shiftInstanceId=999999999');
  assert.strictEqual(unknown.response.status, 404);
  assert.strictEqual(unknown.payload.message, 'Shift instance not found');

  const found = await getBoard(admin.token, site.id, `?periodType=shift&shiftInstanceId=${shift.id}`);
  assert.strictEqual(found.response.status, 200);
  assert.strictEqual(found.payload.period.type, 'shift');
  assert.strictEqual(found.payload.period.start, '2026-03-10');
});
