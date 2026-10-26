/*
 * Shift handovers over HTTP (issue #333, ADR-0054): opening a draft for a
 * Section and one of its shift instances, reading it back, and reading the
 * Section's production day — against a real database and a real (locally
 * issued) JWKS, the same seam as plant.test.js (see that file's own header).
 *
 * This file builds its own plant and never assumes a shared table is empty: a
 * Site, a department with a section beneath it and an area with two Assets
 * beneath that, a second section for a shift instance that is not this one's,
 * two shift definitions and the shift instances of one production day, and
 * `app_users` rows under subjects unique to this process with their
 * `app_user_org_units` Grants. Every row it inserts is deleted again in
 * `test.after()`, in foreign-key order.
 *
 * Needs a database with every migration applied. Set DATABASE_URL first —
 * see the README's Tests section.
 */

const test = require('node:test');
const assert = require('node:assert');
const { createTestJwks } = require('../helpers/jwks');

const ISSUER = 'https://example.supabase.co/auth/v1';
const AUDIENCE = 'authenticated';
const TIMEZONE = 'Asia/Ho_Chi_Minh';
const PRODUCTION_DATE = '2026-05-04';

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
const insertedDowntimeReasonIds = [];
const insertedProductIds = [];
const insertedDefectCodeIds = [];

// The plant this file builds, filled in by test.before().
let site;
let department;
let section;
let otherSection;
let dayShift;
let nightShift;
let otherSectionShift;
let teamLeader; // edit Grant on the department, so it reaches the section beneath
let outsider; // edit Grant on the other section only
let assetA; // the section's two Assets, both in its Cutting area
let assetB;
let otherSectionAsset;

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

async function insertAccount({ grants = [] } = {}) {
  const subject = uniqueCode('hoacct');
  const { rows: [account] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status)
     VALUES ($1, 'Handover Test Account', 'operator', $2, TRUE, 'approved') RETURNING id`,
    [`${subject}@example.com`, subject]
  );
  insertedAccountIds.push(account.id);
  for (const grant of grants) {
    await pool.query(
      `INSERT INTO app_user_org_units (app_user_id, org_unit_id, can_write) VALUES ($1, $2, $3)`,
      [account.id, grant.orgUnitId, grant.write ?? true]
    );
  }
  return { id: account.id, token: await authHeader(subject) };
}

async function insertOrgUnit(parentId, unitType, name) {
  const { rows: [orgUnit] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, $2, $3, $4, $5) RETURNING id, code, name`,
    [site.id, parentId, uniqueCode('HOOU'), name, unitType]
  );
  insertedOrgUnitIds.push(orgUnit.id);
  return orgUnit;
}

async function insertAsset(orgUnitId) {
  const { rows: [asset] } = await pool.query(
    `INSERT INTO assets (org_unit_id, code, name) VALUES ($1, $2, 'Handover Test Machine') RETURNING id`,
    [orgUnitId, uniqueCode('HOAS')]
  );
  insertedAssetIds.push(asset.id);
  return asset;
}

async function insertShiftDefinition(startTime, name) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO shift_definitions (site_id, code, name, start_time, duration_minutes, break_minutes)
     VALUES ($1, $2, $3, $4, 480, 30) RETURNING id`,
    [site.id, uniqueCode('HOSD'), name, startTime]
  );
  insertedShiftDefinitionIds.push(row.id);
  return row;
}

async function insertShiftInstance(
  orgUnitId, shiftDefinitionId, startsAt, endsAt, productionDate = PRODUCTION_DATE
) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO shift_instances
       (site_id, org_unit_id, shift_definition_id, production_date, starts_at, ends_at,
        planned_production_minutes)
     VALUES ($1, $2, $3, $4, $5, $6, 450)
     RETURNING id`,
    [site.id, orgUnitId, shiftDefinitionId, productionDate, startsAt, endsAt]
  );
  insertedShiftInstanceIds.push(row.id);
  return row;
}

async function json(response) {
  return { status: response.status, body: await response.json() };
}

async function openHandover(token, body) {
  return json(
    await fetch(`${base}/api/production/handovers`, {
      method: 'POST',
      headers: { ...token, 'content-type': 'application/json' },
      body: JSON.stringify(body)
    })
  );
}

async function get(token, path) {
  return json(await fetch(`${base}/api/production${path}`, { headers: token }));
}

async function submit(token, id) {
  return fetch(`${base}/api/production/handovers/${id}/submit`, { method: 'POST', headers: token });
}

// The fixtures a snapshot reads. Each records its id for test.after().
async function insertDowntimeReason(parentCode, lossCategory) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO downtime_reasons (parent_id, code, name, loss_category)
     VALUES ((SELECT id FROM downtime_reasons WHERE code = $1), $2, 'Handover Test Reason', $3)
     RETURNING id`,
    [parentCode, uniqueCode('HODR'), lossCategory]
  );
  insertedDowntimeReasonIds.push(row.id);
  return row;
}

// `org_unit_id` is filled from the Asset by the baseline's own trigger.
async function insertDowntimeEvent(assetId, reasonId, startedAt, endedAt) {
  await pool.query(
    `INSERT INTO downtime_events (asset_id, downtime_reason_id, started_at, ended_at)
     VALUES ($1, $2, $3, $4)`,
    [assetId, reasonId, startedAt, endedAt]
  );
}

// A product with a default ideal cycle time, and optionally a faster or
// slower one on one Asset.
async function insertProduct(cycleSeconds, assetCycle = null) {
  const { rows: [product] } = await pool.query(
    `INSERT INTO products (code, name, uom_code) VALUES ($1, 'Handover Test Product', 'EA') RETURNING id`,
    [uniqueCode('HOPR')]
  );
  insertedProductIds.push(product.id);
  await pool.query(
    `INSERT INTO product_cycle_times (product_id, asset_id, ideal_cycle_seconds, effective_from)
     VALUES ($1, NULL, $2, '2026-01-01')`,
    [product.id, cycleSeconds]
  );
  if (assetCycle) {
    await pool.query(
      `INSERT INTO product_cycle_times (product_id, asset_id, ideal_cycle_seconds, effective_from)
       VALUES ($1, $2, $3, '2026-01-01')`,
      [product.id, assetCycle.assetId, assetCycle.seconds]
    );
  }
  return product;
}

// One production run on an Asset for a shift instance, with one count over it.
// `total_quantity` is the baseline's generated sum of the three.
async function insertRunWithCount({ shiftInstanceId, assetId, productId, plannedQuantity, startedAt, endedAt, count }) {
  const { rows: [run] } = await pool.query(
    `INSERT INTO production_runs
       (product_id, org_unit_id, asset_id, shift_instance_id, planned_quantity, uom_code, started_at)
     SELECT $1, a.org_unit_id, a.id, $3, $4, 'EA', $5 FROM assets a WHERE a.id = $2
     RETURNING id, org_unit_id`,
    [productId, assetId, shiftInstanceId, plannedQuantity, startedAt]
  );
  await pool.query(
    `INSERT INTO production_counts
       (production_run_id, org_unit_id, asset_id, shift_instance_id, period_start, period_end,
        good_quantity, reject_quantity, rework_quantity, uom_code)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, 'EA')`,
    [run.id, run.org_unit_id, assetId, shiftInstanceId, startedAt, endedAt,
      count.good, count.reject, count.rework]
  );
}

async function openDraft(shiftInstanceId) {
  const opened = await openHandover(teamLeader.token, { orgUnitId: section.id, shiftInstanceId });
  assert.strictEqual(opened.status, 201, JSON.stringify(opened.body));
  return opened.body.handover;
}

function round4(value) {
  return Math.round(value * 10000) / 10000;
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

  ({ rows: [site] } = await pool.query(
    `INSERT INTO sites (code, name, timezone) VALUES ($1, 'Handover Test Site', $2) RETURNING id`,
    [uniqueCode('HOS'), TIMEZONE]
  ));
  insertedSiteIds.push(site.id);

  department = await insertOrgUnit(null, 'department', 'Handover Department');
  section = await insertOrgUnit(department.id, 'section', 'Self-Closing');
  const area = await insertOrgUnit(section.id, 'area', 'Cutting');
  assetA = await insertAsset(area.id);
  assetB = await insertAsset(area.id);
  otherSection = await insertOrgUnit(department.id, 'section', 'TX');
  otherSectionAsset = await insertAsset(otherSection.id);

  const dayDefinition = await insertShiftDefinition('06:00', 'Day shift');
  const nightDefinition = await insertShiftDefinition('14:00', 'Late shift');
  // Inserted late-first, so the list's own ordering by starts_at is what puts
  // the day shift first.
  nightShift = await insertShiftInstance(
    section.id, nightDefinition.id, '2026-05-04T07:00:00Z', '2026-05-04T15:00:00Z'
  );
  dayShift = await insertShiftInstance(
    section.id, dayDefinition.id, '2026-05-03T23:00:00Z', '2026-05-04T07:00:00Z'
  );
  otherSectionShift = await insertShiftInstance(
    otherSection.id, dayDefinition.id, '2026-05-03T23:00:00Z', '2026-05-04T07:00:00Z'
  );

  teamLeader = await insertAccount({ grants: [{ orgUnitId: department.id }] });
  outsider = await insertAccount({ grants: [{ orgUnitId: otherSection.id }] });
});

test.after(async () => {
  await pool.query('DELETE FROM downtime_events WHERE asset_id = ANY($1)', [insertedAssetIds]);
  await pool.query('DELETE FROM quality_issues WHERE shift_instance_id = ANY($1)', [insertedShiftInstanceIds]);
  await pool.query('DELETE FROM safety_incidents WHERE shift_instance_id = ANY($1)', [insertedShiftInstanceIds]);
  await pool.query('DELETE FROM safety_observations WHERE shift_instance_id = ANY($1)', [insertedShiftInstanceIds]);
  await pool.query('DELETE FROM production_counts WHERE asset_id = ANY($1)', [insertedAssetIds]);
  await pool.query('DELETE FROM production_runs WHERE product_id = ANY($1)', [insertedProductIds]);
  await pool.query('DELETE FROM shift_handovers WHERE org_unit_id = ANY($1)', [insertedOrgUnitIds]);
  await pool.query('DELETE FROM product_cycle_times WHERE product_id = ANY($1)', [insertedProductIds]);
  await pool.query('DELETE FROM products WHERE id = ANY($1)', [insertedProductIds]);
  await pool.query('DELETE FROM defect_codes WHERE id = ANY($1)', [insertedDefectCodeIds]);
  await pool.query('DELETE FROM downtime_reasons WHERE id = ANY($1)', [insertedDowntimeReasonIds]);
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

test('a Team Leader opens a draft handover and reads it back with its number and production day', async () => {
  const opened = await openHandover(teamLeader.token, {
    orgUnitId: section.id,
    shiftInstanceId: dayShift.id
  });
  assert.strictEqual(opened.status, 201, JSON.stringify(opened.body));
  const draft = opened.body.handover;
  assert.match(draft.handoverNo, /^HO-\d{4}-\d{5}$/);
  assert.strictEqual(draft.status, 'draft');
  assert.strictEqual(draft.version, 1);
  assert.strictEqual(draft.productionDate, PRODUCTION_DATE);

  const read = await get(teamLeader.token, `/handovers/${draft.id}`);
  assert.strictEqual(read.status, 200, JSON.stringify(read.body));
  const handover = read.body.handover;
  assert.strictEqual(handover.id, draft.id);
  assert.strictEqual(handover.handoverNo, draft.handoverNo);
  assert.strictEqual(handover.productionDate, PRODUCTION_DATE);
  assert.deepStrictEqual(handover.section, { id: section.id, code: section.code, name: 'Self-Closing' });
  assert.strictEqual(handover.shiftInstance.id, dayShift.id);
  assert.strictEqual(handover.shiftInstance.productionDate, PRODUCTION_DATE);
  assert.strictEqual(handover.shiftInstance.status, 'planned');
  assert.strictEqual(new Date(handover.shiftInstance.startsAt).toISOString(), '2026-05-03T23:00:00.000Z');
  assert.strictEqual(new Date(handover.shiftInstance.endsAt).toISOString(), '2026-05-04T07:00:00.000Z');
  assert.deepStrictEqual(handover.machineLines, []);
  assert.deepStrictEqual(handover.changePoints, []);
  assert.deepStrictEqual(handover.actions, []);
  // A draft has no author yet and no frozen numbers.
  assert.strictEqual(handover.authorDisplayName, null);
  assert.strictEqual(handover.snapshot.oee, null);
});

test('a second open for the same Section and shift instance is refused with 409', async () => {
  const body = { orgUnitId: section.id, shiftInstanceId: nightShift.id };
  const first = await openHandover(teamLeader.token, body);
  assert.strictEqual(first.status, 201, JSON.stringify(first.body));

  const second = await openHandover(teamLeader.token, body);
  assert.strictEqual(second.status, 409);
  assert.strictEqual(second.body.code, 'HANDOVER_EXISTS');
});

test('a shift instance of another Org Unit is refused with 400', async () => {
  const response = await openHandover(teamLeader.token, {
    orgUnitId: section.id,
    shiftInstanceId: otherSectionShift.id
  });
  assert.strictEqual(response.status, 400);
  assert.strictEqual(response.body.code, 'SHIFT_INSTANCE_NOT_IN_SECTION');
});

test('an Org Unit that is not a section is refused with 400 naming its type', async () => {
  const response = await openHandover(teamLeader.token, {
    orgUnitId: department.id,
    shiftInstanceId: dayShift.id
  });
  assert.strictEqual(response.status, 400);
  assert.strictEqual(response.body.code, 'NOT_A_SECTION');
  assert.match(response.body.message, /department/);
});

test('an Account with no Grant on the section is refused with 403', async () => {
  const response = await openHandover(outsider.token, {
    orgUnitId: section.id,
    shiftInstanceId: dayShift.id
  });
  assert.strictEqual(response.status, 403);
  assert.strictEqual(response.body.code, 'OUTSIDE_GRANTED_ORG_UNITS');
});

test('an unknown Org Unit is a 404 before any scope check', async () => {
  // The outsider holds no Grant that could reach a missing Org Unit, so a
  // scope check asked first would answer 403; existence is asked first.
  const response = await openHandover(outsider.token, {
    orgUnitId: '999999999999',
    shiftInstanceId: dayShift.id
  });
  assert.strictEqual(response.status, 404);
});

test('a handover outside the caller\'s Grants is a 403 to read, and an unknown one a 404', async () => {
  const { body: { shifts } } = await get(teamLeader.token, `/sections/${section.id}/handovers?date=${PRODUCTION_DATE}`);
  const handoverId = shifts.find((shift) => shift.handover !== null).handover.id;

  const outside = await get(outsider.token, `/handovers/${handoverId}`);
  assert.strictEqual(outside.status, 403);
  assert.strictEqual(outside.body.code, 'OUTSIDE_GRANTED_ORG_UNITS');

  const unknown = await get(teamLeader.token, '/handovers/999999999999');
  assert.strictEqual(unknown.status, 404);
});

test('the Section\'s day lists every shift instance in start order, with null where no handover exists', async () => {
  // A day of its own, so this test controls which shifts have a handover.
  const definition = await insertShiftDefinition('22:00', 'Night shift');
  const { rows: [quiet] } = await pool.query(
    `INSERT INTO shift_instances
       (site_id, org_unit_id, shift_definition_id, production_date, starts_at, ends_at,
        planned_production_minutes)
     VALUES ($1, $2, $3, '2026-05-05', '2026-05-05T15:00:00Z', '2026-05-05T23:00:00Z', 450)
     RETURNING id`,
    [site.id, section.id, definition.id]
  );
  insertedShiftInstanceIds.push(quiet.id);

  const quietDay = await get(teamLeader.token, `/sections/${section.id}/handovers?date=2026-05-05`);
  assert.strictEqual(quietDay.status, 200, JSON.stringify(quietDay.body));
  assert.strictEqual(quietDay.body.productionDate, '2026-05-05');
  assert.deepStrictEqual(quietDay.body.shifts.map((shift) => shift.shiftInstanceId), [quiet.id]);
  assert.strictEqual(quietDay.body.shifts[0].handover, null);

  // The day the earlier tests opened handovers on: two shift instances, the
  // day shift first even though it was inserted second, each with its draft.
  const day = await get(teamLeader.token, `/sections/${section.id}/handovers?date=${PRODUCTION_DATE}`);
  assert.strictEqual(day.status, 200, JSON.stringify(day.body));
  assert.deepStrictEqual(day.body.section, { id: section.id, code: section.code, name: 'Self-Closing' });
  assert.strictEqual(day.body.productionDate, PRODUCTION_DATE);
  assert.deepStrictEqual(
    day.body.shifts.map((shift) => shift.shiftInstanceId),
    [dayShift.id, nightShift.id]
  );
  for (const shift of day.body.shifts) {
    assert.strictEqual(shift.status, 'planned');
    assert.ok(shift.handover, `expected a live handover for shift instance ${shift.shiftInstanceId}`);
    assert.strictEqual(shift.handover.shiftInstanceId, shift.shiftInstanceId);
    assert.strictEqual(shift.handover.status, 'draft');
  }
});

test('the Section\'s day defaults to the Site\'s own calendar day', async () => {
  const today = new Intl.DateTimeFormat('en-CA', { timeZone: TIMEZONE }).format(new Date());
  const response = await get(teamLeader.token, `/sections/${section.id}/handovers`);
  assert.strictEqual(response.status, 200, JSON.stringify(response.body));
  assert.strictEqual(response.body.productionDate, today);
  assert.ok(Array.isArray(response.body.shifts));
});

test('the Section\'s day refuses a malformed date, a non-section and an outsider', async () => {
  const malformed = await get(teamLeader.token, `/sections/${section.id}/handovers?date=2026-13-40`);
  assert.strictEqual(malformed.status, 400);

  const notSection = await get(teamLeader.token, `/sections/${department.id}/handovers`);
  assert.strictEqual(notSection.status, 400);
  assert.strictEqual(notSection.body.code, 'NOT_A_SECTION');

  const outside = await get(outsider.token, `/sections/${section.id}/handovers`);
  assert.strictEqual(outside.status, 403);

  const unknown = await get(outsider.token, '/sections/999999999999/handovers');
  assert.strictEqual(unknown.status, 404);
});

// ---------------------------------------------------------------------------
// Submit and the frozen snapshot (issue #334).
//
// The snapshot shift is 2026-05-05T23:00Z–2026-05-06T07:00Z, 450 planned
// minutes on each of the section's two Assets. Its downtime, in minutes from
// the shift's start:
//
//   Asset A  reason R1  60–100            40
//   Asset A  reason R2  200–230           30
//   Asset A  reason R1  460–(still open)  20, clipped at the shift's end
//   Asset B  reason R2  300–315           15
//   Asset B  no reason  400–410           10
//   Asset B  reason R2  -30–10            10, clipped at the shift's start
//   TX       reason R2  100–200           not the section's — never counted
//
// so R1 = 60 and R2 = 55; unplanned 90 on A and 35 on B; run 360 + 415 = 775
// of 900 planned. Counts: A 900 good / 30 reject / 0 rework at 20 s, B 800
// good at the Asset's own 30 s — 710 theoretical minutes. The two Assets'
// cycle times differ on purpose: with one rate, an average of the per-Asset
// OEEs happens to equal the roll-up, and the test could not tell them apart.
// ---------------------------------------------------------------------------

const SNAPSHOT_START = Date.parse('2026-05-05T23:00:00Z');
function minute(offset) {
  return new Date(SNAPSHOT_START + offset * 60000).toISOString();
}

let snapshotShift;
let reasonR1;
let reasonR2;
let snapshotHandover;

test('submit seals the handover with every snapshot number, OEE rolled up from summed minutes', async () => {
  const definition = await insertShiftDefinition('06:00', 'Snapshot shift');
  snapshotShift = await insertShiftInstance(section.id, definition.id, minute(0), minute(480), '2026-05-06');
  reasonR1 = await insertDowntimeReason('BRK', 'breakdown');
  reasonR2 = await insertDowntimeReason('SET', 'setup_and_adjustment');

  await insertDowntimeEvent(assetA.id, reasonR1.id, minute(60), minute(100));
  await insertDowntimeEvent(assetA.id, reasonR2.id, minute(200), minute(230));
  await insertDowntimeEvent(assetA.id, reasonR1.id, minute(460), null);
  await insertDowntimeEvent(assetB.id, reasonR2.id, minute(300), minute(315));
  await insertDowntimeEvent(assetB.id, null, minute(400), minute(410));
  await insertDowntimeEvent(assetB.id, reasonR2.id, minute(-30), minute(10));
  await insertDowntimeEvent(otherSectionAsset.id, reasonR2.id, minute(100), minute(200));

  const product = await insertProduct(20, { assetId: assetB.id, seconds: 30 });
  await insertRunWithCount({
    shiftInstanceId: snapshotShift.id, assetId: assetA.id, productId: product.id, plannedQuantity: 1000,
    startedAt: minute(0), endedAt: minute(480), count: { good: 900, reject: 30, rework: 0 }
  });
  await insertRunWithCount({
    shiftInstanceId: snapshotShift.id, assetId: assetB.id, productId: product.id, plannedQuantity: 500,
    startedAt: minute(0), endedAt: minute(480), count: { good: 800, reject: 0, rework: 0 }
  });

  const { rows: [defectCode] } = await pool.query(
    `INSERT INTO defect_codes (code, name) VALUES ($1, 'Handover Test Defect') RETURNING id`,
    [uniqueCode('HODC')]
  );
  insertedDefectCodeIds.push(defectCode.id);
  for (const status of ['open', 'contained', 'closed']) {
    await pool.query(
      `INSERT INTO quality_issues
         (org_unit_id, asset_id, product_id, defect_code_id, detection_point, quantity_affected,
          uom_code, shift_instance_id, status, closed_at)
       VALUES ($1, $2, $3, $4, 'in_process', 5, 'EA', $5, $6, CASE WHEN $6 = 'closed' THEN now() END)`,
      [section.id, assetA.id, product.id, defectCode.id, snapshotShift.id, status]
    );
  }
  await pool.query(
    `INSERT INTO safety_incidents
       (org_unit_id, shift_instance_id, occurred_at, incident_type, severity_level, description)
     VALUES ($1, $2, $3, 'near_miss', 'near_miss', 'Handover test near miss')`,
    [section.id, snapshotShift.id, minute(120)]
  );
  await pool.query(
    `INSERT INTO safety_observations (org_unit_id, shift_instance_id, observation_type, description)
     VALUES ($1, $2, 'unsafe_condition', 'Handover test observation')`,
    [section.id, snapshotShift.id]
  );

  const draft = await openDraft(snapshotShift.id);
  const response = await submit(teamLeader.token, draft.id);
  const submitted = await json(response);
  assert.strictEqual(submitted.status, 200, JSON.stringify(submitted.body));
  snapshotHandover = submitted.body.handover;

  assert.strictEqual(snapshotHandover.status, 'submitted');
  assert.ok(snapshotHandover.submittedAt);
  assert.strictEqual(snapshotHandover.submittedByAccountId, teamLeader.id);
  assert.strictEqual(snapshotHandover.authorDisplayName, 'Handover Test Account');
  // 2026-05-06 is long past on the database's clock.
  assert.strictEqual(snapshotHandover.late, true);

  const plannedMinutes = 450 + 450;
  const runMinutes = (450 - 90) + (450 - 35);
  const theoreticalMinutes = (930 * 20) / 60 + (800 * 30) / 60;
  const good = 900 + 800;
  const total = 930 + 800;
  const availability = runMinutes / plannedMinutes;
  const performance = theoreticalMinutes / runMinutes;
  const quality = good / total;

  // Read back through GET: the stored record, not the submit's own echo.
  const read = await get(teamLeader.token, `/handovers/${draft.id}`);
  assert.strictEqual(read.status, 200, JSON.stringify(read.body));
  assert.deepStrictEqual(read.body.handover.snapshot, snapshotHandover.snapshot);
  assert.deepStrictEqual(read.body.handover.snapshot, {
    oee: round4(availability * performance * quality),
    availability: round4(availability),
    performance: round4(performance),
    quality: round4(quality),
    plannedProductionMinutes: plannedMinutes,
    runMinutes,
    unplannedDowntimeMinutes: 125,
    topLossReasonId: reasonR1.id,
    topLossMinutes: 60,
    unclassifiedDowntimeMinutes: 10,
    unclassifiedStopCount: 1,
    goodQuantity: good,
    rejectQuantity: 30,
    // Counted, and none reworked: a measured zero, not a gap.
    reworkQuantity: 0,
    plannedQuantity: 1500,
    performanceSuspect: false,
    openStopCount: 1,
    openQualityIssueCount: 2,
    safetyEventCount: 2
  });
  assert.deepStrictEqual(read.body.handover.snapshotGaps, []);

  // The roll-up is not the average of the Assets' own OEEs from the same view.
  const { rows: perAsset } = await pool.query(
    'SELECT oee FROM v_shift_oee WHERE shift_instance_id = $1',
    [snapshotShift.id]
  );
  assert.strictEqual(perAsset.length, 2);
  const averageOfRatios = perAsset.reduce((sum, row) => sum + Number(row.oee), 0) / perAsset.length;
  assert.notStrictEqual(round4(averageOfRatios), read.body.handover.snapshot.oee);
});

test('the snapshot does not move when the shift\'s downtime and counts change after submit', async () => {
  // Fifty more minutes of R2 on Asset B — enough to make R2 the top loss and
  // to cut run minutes — and a run of 100 rejects on Asset B. Downtime alone
  // cannot move OEE while the counts stand still (availability × performance
  // is theoretical over planned minutes, run minutes cancel), so the rejects
  // are what would move OEE were anything to recompute.
  await insertDowntimeEvent(assetB.id, reasonR2.id, minute(420), minute(470));
  const { rows: [{ product_id: productId }] } = await pool.query(
    'SELECT product_id FROM production_runs WHERE shift_instance_id = $1 LIMIT 1',
    [snapshotShift.id]
  );
  await insertRunWithCount({
    shiftInstanceId: snapshotShift.id, assetId: assetB.id, productId, plannedQuantity: 100,
    startedAt: minute(0), endedAt: minute(480), count: { good: 0, reject: 100, rework: 0 }
  });

  const read = await get(teamLeader.token, `/handovers/${snapshotHandover.id}`);
  assert.strictEqual(read.status, 200, JSON.stringify(read.body));
  assert.deepStrictEqual(read.body.handover.snapshot, snapshotHandover.snapshot);
  const snapshot = read.body.handover.snapshot;
  assert.strictEqual(snapshot.runMinutes, 775);
  assert.strictEqual(snapshot.topLossReasonId, reasonR1.id);
  assert.strictEqual(snapshot.topLossMinutes, 60);
  assert.strictEqual(snapshot.rejectQuantity, 30);
  assert.strictEqual(snapshot.plannedQuantity, 1500);

  // The live view does see both — so the unchanged numbers above are the
  // stored record holding, not the changes going unnoticed.
  const { rows: [live] } = await pool.query(
    `SELECT sum(run_minutes) AS run_minutes, sum(planned_production_minutes) AS planned,
            sum(theoretical_minutes) AS theoretical, sum(good_quantity) AS good,
            sum(total_quantity) AS total
       FROM v_shift_oee WHERE shift_instance_id = $1`,
    [snapshotShift.id]
  );
  assert.strictEqual(Number(live.run_minutes), 725);
  const liveOee = (Number(live.run_minutes) / Number(live.planned))
    * (Number(live.theoretical) / Number(live.run_minutes))
    * (Number(live.good) / Number(live.total));
  assert.strictEqual(round4(liveOee), round4((760 / 900) * (1700 / 1830)));
  assert.notStrictEqual(round4(liveOee), snapshot.oee);
});

test('a shift with no production counts stores null quantities and OEE, and says why', async () => {
  // Earlier than the snapshot shift, whose Asset A stop is still open and so
  // runs into every shift after it.
  const definition = await insertShiftDefinition('06:00', 'Uncounted shift');
  const uncounted = await insertShiftInstance(
    section.id, definition.id, '2026-05-01T23:00:00Z', '2026-05-02T07:00:00Z', '2026-05-02'
  );
  const draft = await openDraft(uncounted.id);

  const submitted = await json(await submit(teamLeader.token, draft.id));
  assert.strictEqual(submitted.status, 200, JSON.stringify(submitted.body));
  const { snapshot, snapshotGaps } = submitted.body.handover;

  assert.strictEqual(snapshot.goodQuantity, null);
  assert.strictEqual(snapshot.rejectQuantity, null);
  assert.strictEqual(snapshot.reworkQuantity, null);
  assert.strictEqual(snapshot.quality, null);
  assert.strictEqual(snapshot.performance, null);
  assert.strictEqual(snapshot.oee, null);
  assert.strictEqual(snapshot.plannedQuantity, null);
  // No downtime: no top loss, and the minutes the shift did measure stand.
  assert.strictEqual(snapshot.topLossReasonId, null);
  assert.strictEqual(snapshot.topLossMinutes, null);
  assert.strictEqual(snapshot.availability, 1);
  assert.strictEqual(snapshot.runMinutes, 900);
  assert.strictEqual(snapshot.unclassifiedDowntimeMinutes, 0);
  assert.strictEqual(snapshot.openStopCount, 0);

  for (const field of ['goodQuantity', 'rejectQuantity', 'reworkQuantity', 'quality', 'oee']) {
    assert.ok(
      snapshotGaps.some((gap) => gap.field === field && gap.reason === 'no production counts'),
      `expected a "no production counts" gap for ${field}: ${JSON.stringify(snapshotGaps)}`
    );
  }

  const read = await get(teamLeader.token, `/handovers/${draft.id}`);
  assert.deepStrictEqual(read.body.handover.snapshotGaps, snapshotGaps);
});

test('submit records late after 30 minutes without refusing, and refuses a second submit, an outsider and an unknown id', async () => {
  // Timed against the database's own clock, which is the one `late` reads.
  const { rows: [clock] } = await pool.query(
    `SELECT now() - interval '90 minutes' AS late_start, now() - interval '31 minutes' AS late_end,
            now() - interval '30 minutes' AS on_time_start, now() - interval '20 minutes' AS on_time_end`
  );
  const lateDefinition = await insertShiftDefinition('06:00', 'Late shift');
  const lateShift = await insertShiftInstance(
    section.id, lateDefinition.id, clock.late_start, clock.late_end, '2026-05-08'
  );
  const onTimeDefinition = await insertShiftDefinition('07:00', 'On-time shift');
  const onTimeShift = await insertShiftInstance(
    section.id, onTimeDefinition.id, clock.on_time_start, clock.on_time_end, '2026-05-08'
  );

  const lateDraft = await openDraft(lateShift.id);
  const late = await json(await submit(teamLeader.token, lateDraft.id));
  assert.strictEqual(late.status, 200, JSON.stringify(late.body));
  assert.strictEqual(late.body.handover.status, 'submitted');
  assert.strictEqual(late.body.handover.late, true);

  const again = await json(await submit(teamLeader.token, lateDraft.id));
  assert.strictEqual(again.status, 409);
  assert.strictEqual(again.body.code, 'HANDOVER_NOT_DRAFT');

  const onTimeDraft = await openDraft(onTimeShift.id);

  const outside = await json(await submit(outsider.token, onTimeDraft.id));
  assert.strictEqual(outside.status, 403);
  assert.strictEqual(outside.body.code, 'OUTSIDE_GRANTED_ORG_UNITS');

  // A read Grant reaches the section but is not enough to submit.
  const reader = await insertAccount({ grants: [{ orgUnitId: section.id, write: false }] });
  const readOnly = await json(await submit(reader.token, onTimeDraft.id));
  assert.strictEqual(readOnly.status, 403);
  assert.strictEqual(readOnly.body.code, 'OUTSIDE_GRANTED_ORG_UNITS');

  const onTime = await json(await submit(teamLeader.token, onTimeDraft.id));
  assert.strictEqual(onTime.status, 200, JSON.stringify(onTime.body));
  assert.strictEqual(onTime.body.handover.late, false);

  const unknown = await submit(teamLeader.token, '999999999999');
  assert.strictEqual(unknown.status, 404);
});

test('a submit that fails leaves the draft exactly as it was', async () => {
  // A cycle time of a million seconds a piece makes performance about 3,700 —
  // more than the snapshot's NUMERIC(7,4) can hold — so the UPDATE that seals
  // the handover fails in the database after the status check has passed.
  const definition = await insertShiftDefinition('06:00', 'Failing shift');
  const failing = await insertShiftInstance(
    section.id, definition.id, '2026-05-08T23:00:00Z', '2026-05-09T07:00:00Z', '2026-05-09'
  );
  const product = await insertProduct(1000000);
  await insertRunWithCount({
    shiftInstanceId: failing.id, assetId: assetA.id, productId: product.id, plannedQuantity: 100,
    startedAt: '2026-05-08T23:00:00Z', endedAt: '2026-05-09T07:00:00Z',
    count: { good: 100, reject: 0, rework: 0 }
  });
  const draft = await openDraft(failing.id);

  const response = await submit(teamLeader.token, draft.id);
  assert.notStrictEqual(response.status, 200);
  await response.text();

  const read = await get(teamLeader.token, `/handovers/${draft.id}`);
  assert.strictEqual(read.status, 200, JSON.stringify(read.body));
  const handover = read.body.handover;
  assert.strictEqual(handover.status, 'draft');
  assert.strictEqual(handover.submittedAt, null);
  assert.strictEqual(handover.submittedByAccountId, null);
  assert.strictEqual(handover.late, false);
  for (const [field, value] of Object.entries(handover.snapshot)) {
    assert.strictEqual(value, null, `${field} should still be null on the draft`);
  }
});
