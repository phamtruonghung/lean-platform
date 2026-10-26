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
const insertedEmployeeIds = [];
const insertedActionIds = [];

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
let cuttingArea; // the section's area the two Assets sit in

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

async function insertAsset(orgUnitId, { code = uniqueCode('HOAS'), isActive = true } = {}) {
  const { rows: [asset] } = await pool.query(
    `INSERT INTO assets (org_unit_id, code, name, is_active)
     VALUES ($1, $2, 'Handover Test Machine', $3) RETURNING id, code, name`,
    [orgUnitId, code, isActive]
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

async function putLine(token, handoverId, assetId, body) {
  return json(
    await fetch(`${base}/api/production/handovers/${handoverId}/machine-lines/${assetId}`, {
      method: 'PUT',
      headers: { ...token, 'content-type': 'application/json' },
      body: JSON.stringify(body)
    })
  );
}

async function deleteLine(token, handoverId, assetId) {
  return json(
    await fetch(`${base}/api/production/handovers/${handoverId}/machine-lines/${assetId}`, {
      method: 'DELETE',
      headers: token
    })
  );
}

async function patchHandover(token, handoverId, body) {
  return json(
    await fetch(`${base}/api/production/handovers/${handoverId}`, {
      method: 'PATCH',
      headers: { ...token, 'content-type': 'application/json' },
      body: JSON.stringify(body)
    })
  );
}

async function addChangePoint(token, handoverId, body) {
  return json(
    await fetch(`${base}/api/production/handovers/${handoverId}/change-points`, {
      method: 'POST',
      headers: { ...token, 'content-type': 'application/json' },
      body: JSON.stringify(body)
    })
  );
}

async function deleteChangePoint(token, handoverId, changePointId) {
  return json(
    await fetch(`${base}/api/production/handovers/${handoverId}/change-points/${changePointId}`, {
      method: 'DELETE',
      headers: token
    })
  );
}

// Every active Asset the Section lists gets a normal-running line, and the
// change point block is declared none this shift, so submit's completeness
// rules (issues #335 and #336) are met and a test can reach what it is about.
async function fillRunningLines(handoverId, { declareNoChangePoints = true } = {}) {
  const listed = await get(teamLeader.token, `/sections/${section.id}/assets`);
  assert.strictEqual(listed.status, 200, JSON.stringify(listed.body));
  for (const asset of listed.body.assets) {
    const written = await putLine(teamLeader.token, handoverId, asset.id, { state: 'running' });
    assert.strictEqual(written.status, 200, JSON.stringify(written.body));
  }
  if (declareNoChangePoints) {
    const declared = await patchHandover(teamLeader.token, handoverId, { changePointsNone: true });
    assert.strictEqual(declared.status, 200, JSON.stringify(declared.body));
  }
}

async function insertEmployee() {
  const { rows: [row] } = await pool.query(
    `INSERT INTO employees (employee_no, first_name, last_name, is_active)
     VALUES ($1, 'Lan', 'Nguyen', TRUE) RETURNING id, display_name`,
    [uniqueCode('HOEMP')]
  );
  insertedEmployeeIds.push(row.id);
  return row;
}

// The snapshot's ratios are stored at six places (NUMERIC(12,6)).
function round6(value) {
  return Math.round(value * 1e6) / 1e6;
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
  cuttingArea = await insertOrgUnit(section.id, 'area', 'Cutting');
  assetA = await insertAsset(cuttingArea.id);
  assetB = await insertAsset(cuttingArea.id);
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
  // Lines reference downtime events and quality issues, so they go first.
  await pool.query(
    `DELETE FROM shift_handover_machine_lines
      WHERE handover_id IN (SELECT id FROM shift_handovers WHERE org_unit_id = ANY($1))`,
    [insertedOrgUnitIds]
  );
  await pool.query('DELETE FROM downtime_events WHERE asset_id = ANY($1)', [insertedAssetIds]);
  await pool.query('DELETE FROM quality_issues WHERE shift_instance_id = ANY($1)', [insertedShiftInstanceIds]);
  await pool.query('DELETE FROM safety_incidents WHERE shift_instance_id = ANY($1)', [insertedShiftInstanceIds]);
  await pool.query('DELETE FROM safety_observations WHERE shift_instance_id = ANY($1)', [insertedShiftInstanceIds]);
  await pool.query('DELETE FROM production_counts WHERE asset_id = ANY($1)', [insertedAssetIds]);
  await pool.query('DELETE FROM production_runs WHERE product_id = ANY($1)', [insertedProductIds]);
  // Change points cascade with their handover, and name Employees.
  await pool.query('DELETE FROM shift_handovers WHERE org_unit_id = ANY($1)', [insertedOrgUnitIds]);
  // Action links cascaded with their handover; phases cascade with their Action.
  await pool.query('DELETE FROM action_items WHERE id = ANY($1)', [insertedActionIds]);
  await pool.query('DELETE FROM employees WHERE id = ANY($1)', [insertedEmployeeIds]);
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
  assert.deepStrictEqual(handover.changePoints, { man: [], machine: [], material: [], method: [] });
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
  await fillRunningLines(draft.id);
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
    oee: round6(availability * performance * quality),
    availability: round6(availability),
    performance: round6(performance),
    quality: round6(quality),
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
  assert.notStrictEqual(round6(averageOfRatios), read.body.handover.snapshot.oee);
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
  assert.strictEqual(round6(liveOee), round6((760 / 900) * (1700 / 1830)));
  assert.notStrictEqual(round6(liveOee), snapshot.oee);
});

test('a shift with no production counts stores null quantities and OEE, and says why', async () => {
  // Earlier than the snapshot shift, whose Asset A stop is still open and so
  // runs into every shift after it.
  const definition = await insertShiftDefinition('06:00', 'Uncounted shift');
  const uncounted = await insertShiftInstance(
    section.id, definition.id, '2026-05-01T23:00:00Z', '2026-05-02T07:00:00Z', '2026-05-02'
  );
  const draft = await openDraft(uncounted.id);
  await fillRunningLines(draft.id);

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
  await fillRunningLines(lateDraft.id);
  const late = await json(await submit(teamLeader.token, lateDraft.id));
  assert.strictEqual(late.status, 200, JSON.stringify(late.body));
  assert.strictEqual(late.body.handover.status, 'submitted');
  assert.strictEqual(late.body.handover.late, true);

  const again = await json(await submit(teamLeader.token, lateDraft.id));
  assert.strictEqual(again.status, 409);
  assert.strictEqual(again.body.code, 'HANDOVER_NOT_DRAFT');

  const onTimeDraft = await openDraft(onTimeShift.id);
  await fillRunningLines(onTimeDraft.id);

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

test('a performance far above 1 is sealed as the view reports it, neither refused nor clamped', async () => {
  // Before the snapshot shift, so its still-open stop does not reach in: no
  // downtime, 900 run minutes over the two Assets. 100 pieces at 810,000 s is
  // 1,350,000 theoretical minutes — performance 1500, past the 999.9999 the
  // ratio columns held before they were widened.
  const definition = await insertShiftDefinition('06:00', 'Suspect shift');
  const suspect = await insertShiftInstance(
    section.id, definition.id, '2026-04-29T23:00:00Z', '2026-04-30T07:00:00Z', '2026-04-30'
  );
  const product = await insertProduct(810000);
  await insertRunWithCount({
    shiftInstanceId: suspect.id, assetId: assetA.id, productId: product.id, plannedQuantity: 100,
    startedAt: '2026-04-29T23:00:00Z', endedAt: '2026-04-30T07:00:00Z',
    count: { good: 100, reject: 0, rework: 0 }
  });
  const draft = await openDraft(suspect.id);
  await fillRunningLines(draft.id);

  const submitted = await json(await submit(teamLeader.token, draft.id));
  assert.strictEqual(submitted.status, 200, JSON.stringify(submitted.body));

  const read = await get(teamLeader.token, `/handovers/${draft.id}`);
  assert.strictEqual(read.status, 200, JSON.stringify(read.body));
  const { snapshot } = read.body.handover;
  assert.strictEqual(snapshot.runMinutes, 900);
  assert.strictEqual(snapshot.availability, 1);
  assert.strictEqual(snapshot.performance, 1500);
  assert.strictEqual(snapshot.quality, 1);
  assert.strictEqual(snapshot.oee, 1500);
  assert.strictEqual(snapshot.performanceSuspect, true);
});

test('a submit that fails leaves the draft exactly as it was', async () => {
  // A cycle time of a thousand million seconds a piece makes performance
  // millions — more than even the widened NUMERIC(12,6) can hold — so the
  // UPDATE that seals the handover fails in the database after the status
  // check has passed.
  const definition = await insertShiftDefinition('06:00', 'Failing shift');
  const failing = await insertShiftInstance(
    section.id, definition.id, '2026-05-08T23:00:00Z', '2026-05-09T07:00:00Z', '2026-05-09'
  );
  const product = await insertProduct(1000000000);
  await insertRunWithCount({
    shiftInstanceId: failing.id, assetId: assetA.id, productId: product.id, plannedQuantity: 100,
    startedAt: '2026-05-08T23:00:00Z', endedAt: '2026-05-09T07:00:00Z',
    count: { good: 100, reject: 0, rework: 0 }
  });
  const draft = await openDraft(failing.id);
  await fillRunningLines(draft.id);

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

// ---------------------------------------------------------------------------
// Machine status lines and submit's completeness rule (issue #335).
//
// Each test opens its own draft on a shift instance in April 2026, before
// every stop the snapshot tests wrote: downtime events on one Asset may not
// overlap, and Asset A's last snapshot stop is still open.
// ---------------------------------------------------------------------------

// The nth April shift runs 23:00Z on the (9 + n)th to 07:00Z the next day,
// which is its production date.
let aprilDay = 9;
function april(day, time) {
  return `2026-04-${String(day).padStart(2, '0')}T${time}:00Z`;
}
async function aprilShift(name) {
  aprilDay += 1;
  const definition = await insertShiftDefinition('06:00', name);
  return insertShiftInstance(
    section.id, definition.id, april(aprilDay, '23:00'), april(aprilDay + 1, '07:00'),
    april(aprilDay + 1, '00:00').slice(0, 10)
  );
}

// A stop at a time of the test's choosing, stamped with the shift instance the
// test names rather than the one the baseline's trigger would infer.
async function insertStop(assetId, shiftInstanceId, startedAt, endedAt) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO downtime_events (asset_id, shift_instance_id, started_at, ended_at)
     VALUES ($1, $2, $3, $4) RETURNING id`,
    [assetId, shiftInstanceId, startedAt, endedAt]
  );
  return row;
}

async function insertQualityIssue(assetId, shiftInstanceId) {
  const product = await insertProduct(20);
  const { rows: [defectCode] } = await pool.query(
    `INSERT INTO defect_codes (code, name) VALUES ($1, 'Handover Test Defect') RETURNING id`,
    [uniqueCode('HODC')]
  );
  insertedDefectCodeIds.push(defectCode.id);
  const { rows: [row] } = await pool.query(
    `INSERT INTO quality_issues
       (org_unit_id, asset_id, product_id, defect_code_id, detection_point, quantity_affected,
        uom_code, shift_instance_id)
     VALUES ($1, $2, $3, $4, 'in_process', 5, 'EA', $5)
     RETURNING id`,
    [section.id, assetId, product.id, defectCode.id, shiftInstanceId]
  );
  return row;
}

test('a draft gains, replaces and loses a machine status line, and once submitted every line write is 409', async () => {
  const shift = await aprilShift('Lines shift');
  const draft = await openDraft(shift.id);

  const written = await putLine(teamLeader.token, draft.id, assetA.id, {
    state: 'running', watchNote: 'Watch the guide rail', walked: true
  });
  assert.strictEqual(written.status, 200, JSON.stringify(written.body));
  assert.strictEqual(written.body.handover.id, draft.id);
  assert.strictEqual(written.body.handover.machineLines.length, 1);
  const line = written.body.handover.machineLines[0];
  assert.strictEqual(line.assetId, assetA.id);
  assert.strictEqual(line.assetCode, assetA.code);
  assert.strictEqual(line.orgUnitId, cuttingArea.id);
  assert.strictEqual(line.orgUnitName, 'Cutting');
  assert.strictEqual(line.state, 'running');
  assert.strictEqual(line.watchNote, 'Watch the guide rail');
  assert.strictEqual(line.walked, true);
  assert.strictEqual(line.note, null);

  // The same Asset again replaces its line whole: one line, walked back to its
  // default, the watch note cleared.
  const replaced = await putLine(teamLeader.token, draft.id, assetA.id, {
    state: 'idle', note: 'No material from the slitter'
  });
  assert.strictEqual(replaced.status, 200, JSON.stringify(replaced.body));
  assert.strictEqual(replaced.body.handover.machineLines.length, 1);
  assert.strictEqual(replaced.body.handover.machineLines[0].id, line.id);
  assert.strictEqual(replaced.body.handover.machineLines[0].state, 'idle');
  assert.strictEqual(replaced.body.handover.machineLines[0].note, 'No material from the slitter');
  assert.strictEqual(replaced.body.handover.machineLines[0].walked, false);
  assert.strictEqual(replaced.body.handover.machineLines[0].watchNote, null);

  const read = await get(teamLeader.token, `/handovers/${draft.id}`);
  assert.strictEqual(read.status, 200, JSON.stringify(read.body));
  assert.deepStrictEqual(read.body.handover.machineLines, replaced.body.handover.machineLines);

  const removed = await deleteLine(teamLeader.token, draft.id, assetA.id);
  assert.strictEqual(removed.status, 200, JSON.stringify(removed.body));
  assert.deepStrictEqual(removed.body.handover.machineLines, []);
  const removedAgain = await deleteLine(teamLeader.token, draft.id, assetA.id);
  assert.strictEqual(removedAgain.status, 404);

  // Scope before the draft check: an outsider is 403, a read Grant too.
  const outside = await putLine(outsider.token, draft.id, assetA.id, { state: 'running' });
  assert.strictEqual(outside.status, 403);
  const reader = await insertAccount({ grants: [{ orgUnitId: section.id, write: false }] });
  const readOnly = await putLine(reader.token, draft.id, assetA.id, { state: 'running' });
  assert.strictEqual(readOnly.status, 403);
  const unknownHandover = await putLine(teamLeader.token, '999999999999', assetA.id, { state: 'running' });
  assert.strictEqual(unknownHandover.status, 404);

  await fillRunningLines(draft.id);
  const submitted = await json(await submit(teamLeader.token, draft.id));
  assert.strictEqual(submitted.status, 200, JSON.stringify(submitted.body));
  assert.strictEqual(submitted.body.handover.machineLines.length, 2);

  const afterPut = await putLine(teamLeader.token, draft.id, assetA.id, { state: 'running' });
  assert.strictEqual(afterPut.status, 409);
  assert.strictEqual(afterPut.body.code, 'HANDOVER_NOT_DRAFT');
  const afterNewAsset = await putLine(teamLeader.token, draft.id, assetB.id, { state: 'down', note: 'Late stop' });
  assert.strictEqual(afterNewAsset.status, 409);
  const afterDelete = await deleteLine(teamLeader.token, draft.id, assetA.id);
  assert.strictEqual(afterDelete.status, 409);
  assert.strictEqual(afterDelete.body.code, 'HANDOVER_NOT_DRAFT');
});

test('a machine not running normally needs a note when written and a reference before submit', async () => {
  const shift = await aprilShift('Down shift');
  const draft = await openDraft(shift.id);
  await fillRunningLines(draft.id);

  const noNote = await putLine(teamLeader.token, draft.id, assetA.id, { state: 'down' });
  assert.strictEqual(noNote.status, 400);
  assert.strictEqual(noNote.body.code, 'NOTE_REQUIRED');
  assert.match(noNote.body.message, new RegExp(assetA.code));
  const blankNote = await putLine(teamLeader.token, draft.id, assetA.id, { state: 'maintenance', note: '   ' });
  assert.strictEqual(blankNote.status, 400);
  assert.strictEqual(blankNote.body.code, 'NOTE_REQUIRED');
  const abnormalNoNote = await putLine(teamLeader.token, draft.id, assetA.id, {
    state: 'running', abnormalityType: 'minor_flaw'
  });
  assert.strictEqual(abnormalNoNote.status, 400);
  assert.strictEqual(abnormalNoNote.body.code, 'NOTE_REQUIRED');

  const badState = await putLine(teamLeader.token, draft.id, assetA.id, { state: 'broken', note: 'x' });
  assert.strictEqual(badState.status, 400);
  assert.match(badState.body.message, /state must be one of/);
  const badType = await putLine(teamLeader.token, draft.id, assetA.id, {
    state: 'running', abnormalityType: 'rust', note: 'Rust on the frame'
  });
  assert.strictEqual(badType.status, 400);
  assert.match(badType.body.message, /abnormalityType must be one of/);

  // A note and no reference is a fine draft, and not yet a submittable one.
  const down = await putLine(teamLeader.token, draft.id, assetA.id, {
    state: 'down', note: 'Spindle bearing running hot', abnormalityType: 'minor_flaw'
  });
  assert.strictEqual(down.status, 200, JSON.stringify(down.body));

  const refused = await json(await submit(teamLeader.token, draft.id));
  assert.strictEqual(refused.status, 409);
  assert.strictEqual(refused.body.code, 'INCOMPLETE_HANDOVER');
  assert.match(refused.body.message, new RegExp(assetA.code));
  assert.deepStrictEqual(refused.body.missingAssets, []);
  assert.deepStrictEqual(refused.body.incompleteLines, [
    { id: assetA.id, code: assetA.code, name: assetA.name, missing: ['reference'] }
  ]);
  const stillDraft = await get(teamLeader.token, `/handovers/${draft.id}`);
  assert.strictEqual(stillDraft.body.handover.status, 'draft');

  const stop = await insertStop(assetA.id, shift.id, april(aprilDay + 1, '00:00'), april(aprilDay + 1, '01:00'));
  const referenced = await putLine(teamLeader.token, draft.id, assetA.id, {
    state: 'down', note: 'Spindle bearing running hot', downtimeEventId: stop.id
  });
  assert.strictEqual(referenced.status, 200, JSON.stringify(referenced.body));
  const lineA = referenced.body.handover.machineLines.find((line) => line.assetId === assetA.id);
  assert.strictEqual(lineA.downtimeEventId, stop.id);

  const submitted = await json(await submit(teamLeader.token, draft.id));
  assert.strictEqual(submitted.status, 200, JSON.stringify(submitted.body));
  assert.strictEqual(submitted.body.handover.status, 'submitted');
});

test('submit is refused while an active Asset has no line, naming it, and succeeds once it has one', async () => {
  // A retired machine in the section owes no line.
  await insertAsset(cuttingArea.id, { isActive: false });

  const shift = await aprilShift('Missing shift');
  const draft = await openDraft(shift.id);
  await fillRunningLines(draft.id);
  const removed = await deleteLine(teamLeader.token, draft.id, assetB.id);
  assert.strictEqual(removed.status, 200, JSON.stringify(removed.body));

  const refused = await json(await submit(teamLeader.token, draft.id));
  assert.strictEqual(refused.status, 409);
  assert.strictEqual(refused.body.code, 'INCOMPLETE_HANDOVER');
  assert.deepStrictEqual(refused.body.missingAssets, [
    { id: assetB.id, code: assetB.code, name: assetB.name }
  ]);
  assert.deepStrictEqual(refused.body.incompleteLines, []);
  assert.match(refused.body.message, new RegExp(assetB.code));

  const added = await putLine(teamLeader.token, draft.id, assetB.id, { state: 'running_manual', walked: true });
  assert.strictEqual(added.status, 200, JSON.stringify(added.body));

  const submitted = await json(await submit(teamLeader.token, draft.id));
  assert.strictEqual(submitted.status, 200, JSON.stringify(submitted.body));
});

test('an Asset outside the Section, an unknown Asset and a reference from elsewhere are refused', async () => {
  const shift = await aprilShift('Refusal shift');
  const draft = await openDraft(shift.id);

  const outsideSection = await putLine(teamLeader.token, draft.id, otherSectionAsset.id, { state: 'running' });
  assert.strictEqual(outsideSection.status, 400);
  assert.strictEqual(outsideSection.body.code, 'ASSET_NOT_IN_SECTION');
  const unknownAsset = await putLine(teamLeader.token, draft.id, '999999999999', { state: 'running' });
  assert.strictEqual(unknownAsset.status, 404);
  const unknownLine = await deleteLine(teamLeader.token, draft.id, assetB.id);
  assert.strictEqual(unknownLine.status, 404);

  const down = { state: 'down', note: 'Jammed feeder' };

  // A stop of Asset A, but stamped with another shift instance.
  const otherShiftStop = await insertStop(assetA.id, dayShift.id, april(aprilDay + 1, '00:00'), april(aprilDay + 1, '00:30'));
  const otherShift = await putLine(teamLeader.token, draft.id, assetA.id, { ...down, downtimeEventId: otherShiftStop.id });
  assert.strictEqual(otherShift.status, 400);
  assert.strictEqual(otherShift.body.code, 'REFERENCE_OUTSIDE_HANDOVER');

  // This shift's stop, but on Asset B.
  const otherAssetStop = await insertStop(assetB.id, shift.id, april(aprilDay + 1, '00:00'), april(aprilDay + 1, '00:30'));
  const otherAsset = await putLine(teamLeader.token, draft.id, assetA.id, { ...down, downtimeEventId: otherAssetStop.id });
  assert.strictEqual(otherAsset.status, 400);
  assert.strictEqual(otherAsset.body.code, 'REFERENCE_OUTSIDE_HANDOVER');

  const noAssetIssue = await insertQualityIssue(null, shift.id);
  const noAsset = await putLine(teamLeader.token, draft.id, assetA.id, { ...down, qualityIssueId: noAssetIssue.id });
  assert.strictEqual(noAsset.status, 400);
  assert.strictEqual(noAsset.body.code, 'REFERENCE_OUTSIDE_HANDOVER');
  const assetBIssue = await insertQualityIssue(assetB.id, shift.id);
  const wrongIssue = await putLine(teamLeader.token, draft.id, assetA.id, { ...down, qualityIssueId: assetBIssue.id });
  assert.strictEqual(wrongIssue.status, 400);

  for (const field of ['downtimeEventId', 'qualityIssueId', 'workOrderId']) {
    const missing = await putLine(teamLeader.token, draft.id, assetA.id, { ...down, [field]: '999999999999' });
    assert.strictEqual(missing.status, 404, `${field}: ${JSON.stringify(missing.body)}`);
  }
  const malformed = await putLine(teamLeader.token, draft.id, assetA.id, { ...down, workOrderId: 'WO-1' });
  assert.strictEqual(malformed.status, 400);

  // Nothing refused was written.
  const read = await get(teamLeader.token, `/handovers/${draft.id}`);
  assert.deepStrictEqual(read.body.handover.machineLines, []);

  const assetAIssue = await insertQualityIssue(assetA.id, shift.id);
  const right = await putLine(teamLeader.token, draft.id, assetA.id, { ...down, qualityIssueId: assetAIssue.id });
  assert.strictEqual(right.status, 200, JSON.stringify(right.body));
  assert.strictEqual(right.body.handover.machineLines[0].qualityIssueId, assetAIssue.id);
});

test('the Section\'s Assets are its active subtree only, ordered by code', async () => {
  // One at the section itself and one in a second area, coded to sort first
  // and last; a retired one and the other section's never appear.
  const packing = await insertOrgUnit(section.id, 'area', 'Packing');
  const first = await insertAsset(section.id, { code: `AAA${process.pid}` });
  const last = await insertAsset(packing.id, { code: `ZZZ${process.pid}` });
  const retired = await insertAsset(packing.id, { isActive: false });

  const listed = await get(teamLeader.token, `/sections/${section.id}/assets`);
  assert.strictEqual(listed.status, 200, JSON.stringify(listed.body));
  assert.deepStrictEqual(listed.body.section, { id: section.id, code: section.code, name: 'Self-Closing' });
  const { assets } = listed.body;
  const middle = [assetA, assetB].sort((x, y) => (x.code < y.code ? -1 : 1));
  assert.deepStrictEqual(assets.map((asset) => asset.id), [first.id, ...middle.map((a) => a.id), last.id]);
  assert.deepStrictEqual(assets[0], {
    id: first.id, code: first.code, name: 'Handover Test Machine', orgUnitId: section.id, orgUnitName: 'Self-Closing'
  });
  assert.strictEqual(assets.at(-1).orgUnitName, 'Packing');
  assert.ok(!assets.some((asset) => asset.id === retired.id || asset.id === otherSectionAsset.id));

  // A read Grant on the section is enough; no Grant, a non-section and an
  // unknown Org Unit are refused.
  const reader = await insertAccount({ grants: [{ orgUnitId: section.id, write: false }] });
  assert.strictEqual((await get(reader.token, `/sections/${section.id}/assets`)).status, 200);
  const outside = await get(outsider.token, `/sections/${section.id}/assets`);
  assert.strictEqual(outside.status, 403);
  const notSection = await get(teamLeader.token, `/sections/${department.id}/assets`);
  assert.strictEqual(notSection.status, 400);
  assert.strictEqual(notSection.body.code, 'NOT_A_SECTION');
  const unknown = await get(teamLeader.token, '/sections/999999999999/assets');
  assert.strictEqual(unknown.status, 404);
});

// ---------------------------------------------------------------------------
// Change points and the 4M block's answer (issue #336).
//
// Each test opens its own draft on an April shift instance of its own.
// ---------------------------------------------------------------------------

const NO_CHANGE_POINTS = { man: [], machine: [], material: [], method: [] };

test('a draft gains change points grouped man, machine, material, method, two of one dimension in insertion order', async () => {
  const shift = await aprilShift('Change point shift');
  const draft = await openDraft(shift.id);
  const operator = await insertEmployee();

  // Written out of 4M order, and two material lots in one shift.
  const firstLot = await addChangePoint(teamLeader.token, draft.id, {
    dimension: 'material', description: 'Fabric lot 2611-A on the cutter', watchNote: 'Check the first ten for shade'
  });
  assert.strictEqual(firstLot.status, 201, JSON.stringify(firstLot.body));
  assert.strictEqual(firstLot.body.handover.id, draft.id);

  const person = await addChangePoint(teamLeader.token, draft.id, {
    dimension: 'man',
    description: 'Relief operator on the cutter',
    watchNote: 'Watch the first changeover',
    employeeId: operator.id
  });
  assert.strictEqual(person.status, 201, JSON.stringify(person.body));
  const secondLot = await addChangePoint(teamLeader.token, draft.id, {
    dimension: 'material', description: 'Fabric lot 2611-B from 10:00', watchNote: 'Shade again at the lot change'
  });
  assert.strictEqual(secondLot.status, 201, JSON.stringify(secondLot.body));
  const method = await addChangePoint(teamLeader.token, draft.id, {
    dimension: 'method', description: '  New stacking sheet, rev C  ', watchNote: '  Stack height under 40  '
  });
  assert.strictEqual(method.status, 201, JSON.stringify(method.body));

  const read = await get(teamLeader.token, `/handovers/${draft.id}`);
  assert.strictEqual(read.status, 200, JSON.stringify(read.body));
  const { changePoints } = read.body.handover;
  assert.deepStrictEqual(Object.keys(changePoints), ['man', 'machine', 'material', 'method']);
  assert.deepStrictEqual(changePoints.machine, []);

  // A man change point reads back the Employee as the Directory names them.
  assert.strictEqual(changePoints.man.length, 1);
  const [man] = changePoints.man;
  assert.deepStrictEqual(Object.keys(man).sort(), [
    'description', 'dimension', 'employeeId', 'employeeName', 'id',
    'watchAnsweredAt', 'watchAnsweredByAccountId', 'watchNote', 'watchResult', 'watchResultNote'
  ]);
  assert.strictEqual(man.dimension, 'man');
  assert.strictEqual(man.description, 'Relief operator on the cutter');
  assert.strictEqual(man.watchNote, 'Watch the first changeover');
  assert.strictEqual(man.employeeId, operator.id);
  assert.strictEqual(man.employeeName, operator.display_name);
  // The watch's result is the incoming shift's to record, not the writer's.
  assert.strictEqual(man.watchResult, null);
  assert.strictEqual(man.watchResultNote, null);

  assert.deepStrictEqual(
    changePoints.material.map((point) => point.description),
    ['Fabric lot 2611-A on the cutter', 'Fabric lot 2611-B from 10:00']
  );
  assert.strictEqual(changePoints.material[0].employeeId, null);
  assert.strictEqual(changePoints.material[0].employeeName, null);
  assert.strictEqual(changePoints.method[0].description, 'New stacking sheet, rev C');
  assert.strictEqual(changePoints.method[0].watchNote, 'Stack height under 40');

  // The 201 carries the same handover the read does.
  assert.deepStrictEqual(method.body.handover.changePoints, changePoints);
});

test('a change point is refused without a watch, outside the 4M, without a description, or naming an unknown Employee', async () => {
  const shift = await aprilShift('Refused change point shift');
  const draft = await openDraft(shift.id);
  const valid = { dimension: 'machine', description: 'New blade fitted on the cutter', watchNote: 'Edge fray' };

  for (const watchNote of [undefined, '', '   ']) {
    const noWatch = await addChangePoint(teamLeader.token, draft.id, { ...valid, watchNote });
    assert.strictEqual(noWatch.status, 400, JSON.stringify(noWatch.body));
    assert.strictEqual(noWatch.body.code, 'WATCH_REQUIRED');
    assert.match(noWatch.body.message, /watchNote is required/);
    assert.match(noWatch.body.message, /watch for/);
  }

  const badDimension = await addChangePoint(teamLeader.token, draft.id, { ...valid, dimension: 'measurement' });
  assert.strictEqual(badDimension.status, 400);
  assert.match(badDimension.body.message, /dimension must be one of: man, machine, material, method/);
  const noDimension = await addChangePoint(teamLeader.token, draft.id, { ...valid, dimension: undefined });
  assert.strictEqual(noDimension.status, 400);

  for (const description of [undefined, '  ']) {
    const noDescription = await addChangePoint(teamLeader.token, draft.id, { ...valid, description });
    assert.strictEqual(noDescription.status, 400, JSON.stringify(noDescription.body));
    assert.match(noDescription.body.message, /description is required/);
  }

  const unknownEmployee = await addChangePoint(teamLeader.token, draft.id, {
    ...valid, dimension: 'man', employeeId: '999999999999'
  });
  assert.strictEqual(unknownEmployee.status, 404, JSON.stringify(unknownEmployee.body));
  const malformedEmployee = await addChangePoint(teamLeader.token, draft.id, { ...valid, employeeId: 'Lan' });
  assert.strictEqual(malformedEmployee.status, 400);

  // Existence, then scope: unknown handover 404, outsider and read Grant 403.
  const unknownHandover = await addChangePoint(teamLeader.token, '999999999999', valid);
  assert.strictEqual(unknownHandover.status, 404);
  const outside = await addChangePoint(outsider.token, draft.id, valid);
  assert.strictEqual(outside.status, 403);
  assert.strictEqual(outside.body.code, 'OUTSIDE_GRANTED_ORG_UNITS');
  const reader = await insertAccount({ grants: [{ orgUnitId: section.id, write: false }] });
  const readOnly = await addChangePoint(reader.token, draft.id, valid);
  assert.strictEqual(readOnly.status, 403);
  assert.strictEqual((await patchHandover(reader.token, draft.id, { changePointsNone: true })).status, 403);

  // Nothing refused was written.
  const read = await get(teamLeader.token, `/handovers/${draft.id}`);
  assert.deepStrictEqual(read.body.handover.changePoints, NO_CHANGE_POINTS);
});

test('a change point is removed from its own draft, and another handover\'s is a 404', async () => {
  const draft = await openDraft((await aprilShift('Own change point shift')).id);
  const other = await openDraft((await aprilShift('Other change point shift')).id);

  const added = await addChangePoint(teamLeader.token, draft.id, {
    dimension: 'machine', description: 'Feed speed raised to 14 m/min', watchNote: 'Seam wander'
  });
  assert.strictEqual(added.status, 201, JSON.stringify(added.body));
  const [point] = added.body.handover.changePoints.machine;

  const fromElsewhere = await deleteChangePoint(teamLeader.token, other.id, point.id);
  assert.strictEqual(fromElsewhere.status, 404, JSON.stringify(fromElsewhere.body));
  const malformed = await deleteChangePoint(teamLeader.token, draft.id, 'abc');
  assert.strictEqual(malformed.status, 404);
  const outside = await deleteChangePoint(outsider.token, draft.id, point.id);
  assert.strictEqual(outside.status, 403);

  const removed = await deleteChangePoint(teamLeader.token, draft.id, point.id);
  assert.strictEqual(removed.status, 200, JSON.stringify(removed.body));
  assert.deepStrictEqual(removed.body.handover.changePoints, NO_CHANGE_POINTS);
  const removedAgain = await deleteChangePoint(teamLeader.token, draft.id, point.id);
  assert.strictEqual(removedAgain.status, 404);
});

test('submit is refused while the change point block is unanswered, naming it; declaring none or adding one lets it through', async () => {
  const draft = await openDraft((await aprilShift('Unanswered shift')).id);
  await fillRunningLines(draft.id, { declareNoChangePoints: false });
  assert.strictEqual(draft.changePointsNone, false);

  const refused = await json(await submit(teamLeader.token, draft.id));
  assert.strictEqual(refused.status, 409, JSON.stringify(refused.body));
  assert.strictEqual(refused.body.code, 'INCOMPLETE_HANDOVER');
  assert.deepStrictEqual(refused.body.unansweredBlocks, ['changePoints']);
  assert.deepStrictEqual(refused.body.missingAssets, []);
  assert.deepStrictEqual(refused.body.incompleteLines, []);
  assert.match(refused.body.message, /changePoints is unanswered/);
  assert.match(refused.body.message, /add a change point, or declare none/);

  // The header's one field this slice owns: a boolean, and only a boolean.
  for (const changePointsNone of ['yes', 1, null]) {
    const bad = await patchHandover(teamLeader.token, draft.id, { changePointsNone });
    assert.strictEqual(bad.status, 400, JSON.stringify(bad.body));
  }
  assert.strictEqual((await patchHandover(teamLeader.token, draft.id, {})).status, 400);

  // Declared, then withdrawn: unanswered again.
  const declared = await patchHandover(teamLeader.token, draft.id, { changePointsNone: true });
  assert.strictEqual(declared.status, 200, JSON.stringify(declared.body));
  assert.strictEqual(declared.body.handover.changePointsNone, true);
  const withdrawn = await patchHandover(teamLeader.token, draft.id, { changePointsNone: false });
  assert.strictEqual(withdrawn.body.handover.changePointsNone, false);
  assert.strictEqual((await submit(teamLeader.token, draft.id)).status, 409);

  await patchHandover(teamLeader.token, draft.id, { changePointsNone: true });
  const submitted = await json(await submit(teamLeader.token, draft.id));
  assert.strictEqual(submitted.status, 200, JSON.stringify(submitted.body));
  assert.strictEqual(submitted.body.handover.changePointsNone, true);
  assert.deepStrictEqual(submitted.body.handover.changePoints, NO_CHANGE_POINTS);

  // One change point answers the block without declaring anything.
  const answered = await openDraft((await aprilShift('Answered shift')).id);
  await fillRunningLines(answered.id, { declareNoChangePoints: false });
  const added = await addChangePoint(teamLeader.token, answered.id, {
    dimension: 'man', description: 'New starter on packing', watchNote: 'Carton count every hour'
  });
  assert.strictEqual(added.status, 201, JSON.stringify(added.body));
  const answeredSubmit = await json(await submit(teamLeader.token, answered.id));
  assert.strictEqual(answeredSubmit.status, 200, JSON.stringify(answeredSubmit.body));
  assert.strictEqual(answeredSubmit.body.handover.changePointsNone, false);
  assert.strictEqual(answeredSubmit.body.handover.changePoints.man.length, 1);
});

test('once submitted, adding a change point, removing one and patching the header are 409', async () => {
  const draft = await openDraft((await aprilShift('Sealed change point shift')).id);
  await fillRunningLines(draft.id, { declareNoChangePoints: false });
  const added = await addChangePoint(teamLeader.token, draft.id, {
    dimension: 'material', description: 'Thread cone from a new supplier', watchNote: 'Thread breaks'
  });
  assert.strictEqual(added.status, 201, JSON.stringify(added.body));
  const [point] = added.body.handover.changePoints.material;
  const submitted = await json(await submit(teamLeader.token, draft.id));
  assert.strictEqual(submitted.status, 200, JSON.stringify(submitted.body));

  const afterAdd = await addChangePoint(teamLeader.token, draft.id, {
    dimension: 'method', description: 'Late method change', watchNote: 'Anything'
  });
  assert.strictEqual(afterAdd.status, 409);
  assert.strictEqual(afterAdd.body.code, 'HANDOVER_NOT_DRAFT');
  const afterDelete = await deleteChangePoint(teamLeader.token, draft.id, point.id);
  assert.strictEqual(afterDelete.status, 409);
  assert.strictEqual(afterDelete.body.code, 'HANDOVER_NOT_DRAFT');
  const afterPatch = await patchHandover(teamLeader.token, draft.id, { changePointsNone: true });
  assert.strictEqual(afterPatch.status, 409);
  assert.strictEqual(afterPatch.body.code, 'HANDOVER_NOT_DRAFT');

  const read = await get(teamLeader.token, `/handovers/${draft.id}`);
  assert.strictEqual(read.body.handover.changePointsNone, false);
  assert.deepStrictEqual(read.body.handover.changePoints.material, [point]);
});

// --- Carried actions (issue #337) -------------------------------------------
//
// Each test below opens its handovers on a Section of its own, with no Assets
// (so no machine line is owed) and its own Actions: an open Action left in a
// shared Section would hold every other test's submit at 409.

const NOT_OPEN_ACTION_STATUSES = ['done', 'cancelled', 'blocked'];

let actionShiftCounter = 0;

async function actionSection(name) {
  return insertOrgUnit(department.id, 'section', name);
}

// One shift instance after another, eight hours apart, on the Section named.
async function actionShift(sectionId) {
  const startsAt = new Date(Date.parse('2026-06-01T23:00:00Z') + actionShiftCounter * 8 * 3600 * 1000);
  actionShiftCounter += 1;
  const endsAt = new Date(startsAt.getTime() + 8 * 3600 * 1000);
  const definition = await insertShiftDefinition('06:00', 'Action shift');
  return insertShiftInstance(
    sectionId, definition.id, startsAt.toISOString(), endsAt.toISOString(),
    endsAt.toISOString().slice(0, 10)
  );
}

async function openActionDraft(sectionId) {
  const shift = await actionShift(sectionId);
  const opened = await openHandover(teamLeader.token, { orgUnitId: sectionId, shiftInstanceId: shift.id });
  assert.strictEqual(opened.status, 201, JSON.stringify(opened.body));
  return opened.body.handover;
}

// Directly inserted: the raise path is the Actions Module's own, tested there.
async function insertAction(orgUnitId, {
  title = 'Seam wander on line 2', actionType = 'countermeasure', status = 'open',
  ownerEmployeeId = null, dueDate = null
} = {}) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO action_items
       (action_no, org_unit_id, title, action_type, status, owner_employee_id, due_date, completed_at)
     VALUES ($1, $2, $3, $4, $5, $6, $7::date, CASE WHEN $5 IN ('done', 'cancelled') THEN now() END)
     RETURNING id, action_no, title, status`,
    [uniqueCode('AC-HO'), orgUnitId, title, actionType, status, ownerEmployeeId, dueDate]
  );
  insertedActionIds.push(row.id);
  return row;
}

async function insertPhase(actionId, cycle, phase, { completed = false, outcome = null } = {}) {
  await pool.query(
    `INSERT INTO action_phases (action_item_id, cycle, phase, completed_at, outcome)
     VALUES ($1, $2, $3, CASE WHEN $4 THEN now() END, $5)`,
    [actionId, cycle, phase, completed, outcome]
  );
}

async function linkAction(token, handoverId, body) {
  return json(
    await fetch(`${base}/api/production/handovers/${handoverId}/actions`, {
      method: 'POST',
      headers: { ...token, 'content-type': 'application/json' },
      body: JSON.stringify(body)
    })
  );
}

async function unlinkAction(token, handoverId, linkId) {
  return json(
    await fetch(`${base}/api/production/handovers/${handoverId}/actions/${linkId}`, {
      method: 'DELETE',
      headers: token
    })
  );
}

// The 4M block declared none, then submitted: an asset-less Section owes
// nothing else but its Actions.
async function submitActionDraft(handoverId) {
  const declared = await patchHandover(teamLeader.token, handoverId, { changePointsNone: true });
  assert.strictEqual(declared.status, 200, JSON.stringify(declared.body));
  return json(await submit(teamLeader.token, handoverId));
}

test('a draft links one of the Section\'s open Actions and reads it back beside the Action\'s live fields', async () => {
  const actions = await actionSection('Actions read');
  const area = await insertOrgUnit(actions.id, 'area', 'Sewing');
  const owner = await insertEmployee();
  const action = await insertAction(area.id, {
    title: 'Guide rail worn', status: 'in_progress', ownerEmployeeId: owner.id, dueDate: '2026-06-10'
  });
  // Round one's Check found it effective; the Act is what it waits on.
  await insertPhase(action.id, 1, 'plan', { completed: true });
  await insertPhase(action.id, 1, 'do', { completed: true });
  await insertPhase(action.id, 1, 'check', { completed: true, outcome: 'effective' });
  await insertPhase(action.id, 1, 'act');
  const other = await insertAction(actions.id, { title: 'Label printer jams' });
  await insertAction(actions.id, { title: 'Blocked on a spare', status: 'blocked' });

  const draft = await openActionDraft(actions.id);
  assert.deepStrictEqual(draft.actions, []);
  assert.deepStrictEqual(
    draft.openActions.map((candidate) => candidate.id),
    [action.id, other.id],
    'open and in-progress Actions of the subtree, due first; a blocked one is not owed'
  );

  const linked = await linkAction(teamLeader.token, draft.id, { actionId: action.id, disposition: 'carried' });
  assert.strictEqual(linked.status, 201, JSON.stringify(linked.body));
  const [link] = linked.body.handover.actions;
  assert.deepStrictEqual(link, {
    id: link.id,
    disposition: 'carried',
    ownerEmployeeId: null,
    ownerName: null,
    closureNote: null,
    ageShifts: 1,
    action: {
      id: action.id,
      actionNo: action.action_no,
      title: 'Guide rail worn',
      status: 'in_progress',
      type: 'countermeasure',
      ownerEmployeeId: owner.id,
      ownerName: owner.display_name,
      dueDate: '2026-06-10',
      pdcaPhase: 'act',
      lastCheckOutcome: 'effective'
    }
  });
  assert.deepStrictEqual(linked.body.handover.openActions.map((candidate) => candidate.id), [other.id]);

  const read = await get(teamLeader.token, `/handovers/${draft.id}`);
  assert.deepStrictEqual(read.body.handover.actions, [link]);

  const duplicate = await linkAction(teamLeader.token, draft.id, { actionId: action.id, disposition: 'carried' });
  assert.strictEqual(duplicate.status, 409, JSON.stringify(duplicate.body));
  assert.strictEqual(duplicate.body.code, 'ACTION_ALREADY_LINKED');

  const unknown = await linkAction(teamLeader.token, draft.id, { actionId: '999999999999', disposition: 'carried' });
  assert.strictEqual(unknown.status, 404, JSON.stringify(unknown.body));
  const malformed = await linkAction(teamLeader.token, draft.id, { actionId: 'AC-1', disposition: 'carried' });
  assert.strictEqual(malformed.status, 400);

  const elsewhere = await insertAction(otherSection.id, { title: 'Another section\'s action' });
  const outside = await linkAction(teamLeader.token, draft.id, { actionId: elsewhere.id, disposition: 'carried' });
  assert.strictEqual(outside.status, 400, JSON.stringify(outside.body));
  assert.strictEqual(outside.body.code, 'ACTION_NOT_IN_SECTION');

  for (const status of NOT_OPEN_ACTION_STATUSES) {
    const finished = await insertAction(actions.id, { title: `A ${status} action`, status });
    const refused = await linkAction(teamLeader.token, draft.id, { actionId: finished.id, disposition: 'carried' });
    assert.strictEqual(refused.status, 400, `${status}: ${JSON.stringify(refused.body)}`);
    assert.strictEqual(refused.body.code, 'ACTION_NOT_OPEN');
  }

  for (const disposition of [undefined, 'parked', 'CARRIED']) {
    const bad = await linkAction(teamLeader.token, draft.id, { actionId: other.id, disposition });
    assert.strictEqual(bad.status, 400, JSON.stringify(bad.body));
    assert.match(bad.body.message, /disposition must be one of: carried, reassigned, closed/);
  }

  const outsiderLink = await linkAction(outsider.token, draft.id, { actionId: other.id, disposition: 'carried' });
  assert.strictEqual(outsiderLink.status, 403);
  const reader = await insertAccount({ grants: [{ orgUnitId: actions.id, write: false }] });
  assert.strictEqual(
    (await linkAction(reader.token, draft.id, { actionId: other.id, disposition: 'carried' })).status, 403
  );

  const after = await get(teamLeader.token, `/handovers/${draft.id}`);
  assert.deepStrictEqual(after.body.handover.actions, [link], 'nothing refused was linked');
});

test('a reassignment names a known owner and a closure carries its evidence, and neither touches the Action', async () => {
  const actions = await actionSection('Actions dispositions');
  const firstOwner = await insertEmployee();
  const newOwner = await insertEmployee();
  const toReassign = await insertAction(actions.id, { title: 'Reassign me', ownerEmployeeId: firstOwner.id });
  const toClose = await insertAction(actions.id, { title: 'Close me', ownerEmployeeId: firstOwner.id });
  const draft = await openActionDraft(actions.id);

  const noOwner = await linkAction(teamLeader.token, draft.id, { actionId: toReassign.id, disposition: 'reassigned' });
  assert.strictEqual(noOwner.status, 400, JSON.stringify(noOwner.body));
  assert.strictEqual(noOwner.body.code, 'OWNER_REQUIRED');
  const unknownOwner = await linkAction(teamLeader.token, draft.id, {
    actionId: toReassign.id, disposition: 'reassigned', ownerEmployeeId: '999999999999'
  });
  assert.strictEqual(unknownOwner.status, 404, JSON.stringify(unknownOwner.body));
  const ownerOnCarry = await linkAction(teamLeader.token, draft.id, {
    actionId: toReassign.id, disposition: 'carried', ownerEmployeeId: newOwner.id
  });
  assert.strictEqual(ownerOnCarry.status, 400, JSON.stringify(ownerOnCarry.body));

  for (const closureNote of [undefined, '   ']) {
    const noEvidence = await linkAction(teamLeader.token, draft.id, {
      actionId: toClose.id, disposition: 'closed', closureNote
    });
    assert.strictEqual(noEvidence.status, 400, JSON.stringify(noEvidence.body));
    assert.strictEqual(noEvidence.body.code, 'CLOSURE_NOTE_REQUIRED');
  }
  const noteOnCarry = await linkAction(teamLeader.token, draft.id, {
    actionId: toClose.id, disposition: 'carried', closureNote: 'Not closed'
  });
  assert.strictEqual(noteOnCarry.status, 400, JSON.stringify(noteOnCarry.body));

  const reassigned = await linkAction(teamLeader.token, draft.id, {
    actionId: toReassign.id, disposition: 'reassigned', ownerEmployeeId: newOwner.id
  });
  assert.strictEqual(reassigned.status, 201, JSON.stringify(reassigned.body));
  const closed = await linkAction(teamLeader.token, draft.id, {
    actionId: toClose.id, disposition: 'closed', closureNote: '  Rail replaced, 50 seams checked straight  '
  });
  assert.strictEqual(closed.status, 201, JSON.stringify(closed.body));

  const [reassignLink, closeLink] = closed.body.handover.actions;
  assert.strictEqual(reassignLink.disposition, 'reassigned');
  assert.strictEqual(reassignLink.ownerEmployeeId, newOwner.id);
  assert.strictEqual(reassignLink.ownerName, newOwner.display_name);
  assert.strictEqual(reassignLink.ageShifts, 1);
  // The Action's own owner is still the log's: only the Actions Module moves it.
  assert.strictEqual(reassignLink.action.ownerEmployeeId, firstOwner.id);
  assert.strictEqual(closeLink.disposition, 'closed');
  assert.strictEqual(closeLink.closureNote, 'Rail replaced, 50 seams checked straight');
  assert.strictEqual(closeLink.ageShifts, 0);
  assert.strictEqual(closeLink.action.status, 'open', 'the read shows the Action\'s live status');
  assert.deepStrictEqual(closed.body.handover.openActions, []);

  const { rows } = await pool.query(
    'SELECT id, status, owner_employee_id, closure_note FROM action_items WHERE id = ANY($1) ORDER BY id',
    [[toReassign.id, toClose.id]]
  );
  assert.deepStrictEqual(rows, [
    { id: toReassign.id, status: 'open', owner_employee_id: firstOwner.id, closure_note: null },
    { id: toClose.id, status: 'open', owner_employee_id: firstOwner.id, closure_note: null }
  ]);
});

test('submit is refused while an open Action of the Section has no disposition, one raised mid-shift included', async () => {
  const actions = await actionSection('Actions submit');
  const early = await insertAction(actions.id, { title: 'There when the draft opened' });
  const draft = await openActionDraft(actions.id);
  assert.deepStrictEqual(draft.openActions.map((candidate) => candidate.id), [early.id]);

  const linked = await linkAction(teamLeader.token, draft.id, { actionId: early.id, disposition: 'carried' });
  assert.strictEqual(linked.status, 201, JSON.stringify(linked.body));
  // Raised after the draft opened, in the Section's subtree.
  const area = await insertOrgUnit(actions.id, 'area', 'Packing');
  const late = await insertAction(area.id, { title: 'Raised mid-shift' });

  const refused = await submitActionDraft(draft.id);
  assert.strictEqual(refused.status, 409, JSON.stringify(refused.body));
  assert.strictEqual(refused.body.code, 'INCOMPLETE_HANDOVER');
  assert.deepStrictEqual(refused.body.undispositionedActions, [
    { id: late.id, actionNo: late.action_no, title: 'Raised mid-shift' }
  ]);
  assert.deepStrictEqual(refused.body.missingAssets, []);
  assert.deepStrictEqual(refused.body.unansweredBlocks, []);
  assert.match(refused.body.message, new RegExp(`no disposition for open action ${late.action_no}`));

  const dispositioned = await linkAction(teamLeader.token, draft.id, { actionId: late.id, disposition: 'carried' });
  assert.strictEqual(dispositioned.status, 201, JSON.stringify(dispositioned.body));
  const submitted = await json(await submit(teamLeader.token, draft.id));
  assert.strictEqual(submitted.status, 200, JSON.stringify(submitted.body));
  assert.strictEqual(submitted.body.handover.status, 'submitted');
  assert.deepStrictEqual(
    submitted.body.handover.actions.map((link) => link.action.id),
    [early.id, late.id]
  );
  assert.deepStrictEqual(submitted.body.handover.openActions, [], 'a sealed handover offers no candidates');
});

test('age in shifts counts the unbroken run of handovers that carried the Action, and a reassignment restarts it', async () => {
  const actions = await actionSection('Actions age');
  const newOwner = await insertEmployee();
  const action = await insertAction(actions.id, { title: 'Thread breaks on head 3' });

  const ages = [];
  async function handOver(body) {
    const draft = await openActionDraft(actions.id);
    const linked = await linkAction(teamLeader.token, draft.id, { actionId: action.id, ...body });
    assert.strictEqual(linked.status, 201, JSON.stringify(linked.body));
    const draftAge = linked.body.handover.actions[0].ageShifts;
    const submitted = await submitActionDraft(draft.id);
    assert.strictEqual(submitted.status, 200, JSON.stringify(submitted.body));
    assert.strictEqual(submitted.body.handover.actions[0].ageShifts, draftAge, 'sealing does not move the age');
    ages.push(draftAge);
    return submitted.body.handover;
  }

  await handOver({ disposition: 'carried' });
  await handOver({ disposition: 'carried' });
  const third = await handOver({ disposition: 'carried' });
  await handOver({ disposition: 'reassigned', ownerEmployeeId: newOwner.id });
  await handOver({ disposition: 'carried' });
  assert.deepStrictEqual(ages, [1, 2, 3, 1, 2]);

  // Read again later, the third still counts 3: the run behind it is fixed.
  const reread = await get(teamLeader.token, `/handovers/${third.id}`);
  assert.strictEqual(reread.body.handover.actions[0].ageShifts, 3);

  // A closed link breaks the run: the next handover that carries it counts afresh.
  const gap = await openActionDraft(actions.id);
  const closed = await linkAction(teamLeader.token, gap.id, {
    actionId: action.id, disposition: 'closed', closureNote: 'Tension spring replaced'
  });
  assert.strictEqual(closed.body.handover.actions[0].ageShifts, 0);
  assert.strictEqual((await submitActionDraft(gap.id)).status, 200);
  const afterClose = await openActionDraft(actions.id);
  const carriedAgain = await linkAction(teamLeader.token, afterClose.id, { actionId: action.id, disposition: 'carried' });
  assert.strictEqual(carriedAgain.body.handover.actions[0].ageShifts, 1);
});

test('a link is removed from its own draft only, and once submitted linking and removing are 409', async () => {
  const actions = await actionSection('Actions sealed');
  const action = await insertAction(actions.id, { title: 'Oil leak under head 1' });
  const draft = await openActionDraft(actions.id);
  const other = await openActionDraft(actions.id);

  const linked = await linkAction(teamLeader.token, draft.id, { actionId: action.id, disposition: 'carried' });
  assert.strictEqual(linked.status, 201, JSON.stringify(linked.body));
  const [link] = linked.body.handover.actions;

  const fromElsewhere = await unlinkAction(teamLeader.token, other.id, link.id);
  assert.strictEqual(fromElsewhere.status, 404, JSON.stringify(fromElsewhere.body));
  assert.strictEqual((await unlinkAction(teamLeader.token, draft.id, 'abc')).status, 404);
  assert.strictEqual((await unlinkAction(outsider.token, draft.id, link.id)).status, 403);

  const removed = await unlinkAction(teamLeader.token, draft.id, link.id);
  assert.strictEqual(removed.status, 200, JSON.stringify(removed.body));
  assert.deepStrictEqual(removed.body.handover.actions, []);
  assert.deepStrictEqual(removed.body.handover.openActions.map((candidate) => candidate.id), [action.id]);
  assert.strictEqual((await unlinkAction(teamLeader.token, draft.id, link.id)).status, 404);

  const relinked = await linkAction(teamLeader.token, draft.id, { actionId: action.id, disposition: 'carried' });
  assert.strictEqual(relinked.status, 201, JSON.stringify(relinked.body));
  const [sealedLink] = relinked.body.handover.actions;
  assert.strictEqual((await submitActionDraft(draft.id)).status, 200);

  const afterLink = await linkAction(teamLeader.token, draft.id, { actionId: action.id, disposition: 'carried' });
  assert.strictEqual(afterLink.status, 409, JSON.stringify(afterLink.body));
  assert.strictEqual(afterLink.body.code, 'HANDOVER_NOT_DRAFT');
  const afterUnlink = await unlinkAction(teamLeader.token, draft.id, sealedLink.id);
  assert.strictEqual(afterUnlink.status, 409, JSON.stringify(afterUnlink.body));
  assert.strictEqual(afterUnlink.body.code, 'HANDOVER_NOT_DRAFT');

  const read = await get(teamLeader.token, `/handovers/${draft.id}`);
  assert.deepStrictEqual(read.body.handover.actions, [sealedLink]);
});

// --- Acknowledgement, amendment and the Section's exceptions (issue #338) ---
//
// Each test builds a Section of its own, timed against the database's clock:
// the exceptions and the acknowledgement latency are read against `now()`.

async function postJson(token, path, body) {
  return json(
    await fetch(`${base}/api/production${path}`, {
      method: 'POST',
      headers: { ...token, 'content-type': 'application/json' },
      body: JSON.stringify(body ?? {})
    })
  );
}

async function acknowledge(token, handoverId, body) {
  return postJson(token, `/handovers/${handoverId}/acknowledge`, body);
}

async function amend(token, handoverId, body) {
  return postJson(token, `/handovers/${handoverId}/amendments`, body);
}

// An Account with an edit Grant on the department, named so a read can tell
// it from the author.
async function insertNamedAccount(displayName) {
  const account = await insertAccount({ grants: [{ orgUnitId: department.id }] });
  await pool.query('UPDATE app_users SET display_name = $2 WHERE id = $1', [account.id, displayName]);
  return account;
}

// A shift instance on the Section, its start and end given as offsets in
// minutes from the database's now.
async function clockShift(sectionId, startOffset, endOffset, productionDate) {
  const { rows: [clock] } = await pool.query(
    `SELECT now() + make_interval(mins => $1) AS starts_at, now() + make_interval(mins => $2) AS ends_at`,
    [startOffset, endOffset]
  );
  const definition = await insertShiftDefinition('06:00', 'Clock shift');
  const shift = await insertShiftInstance(sectionId, definition.id, clock.starts_at, clock.ends_at, productionDate);
  return { ...shift, startsAt: clock.starts_at, endsAt: clock.ends_at };
}

async function sectionDay(sectionId, date) {
  const day = await get(teamLeader.token, `/sections/${sectionId}/handovers?date=${date}`);
  assert.strictEqual(day.status, 200, JSON.stringify(day.body));
  return day.body.shifts;
}

// A sealed handover with one of everything an amendment copies: a machine line
// on the Section's one Asset, a change point, a carried Action, and a snapshot
// of real numbers. The shift ran from ten hours ago to two hours ago; one
// 30-minute breakdown, 400 good and 20 rejects at 30 s against 500 planned.
async function sealedHandover(name, productionDate) {
  const ownSection = await insertOrgUnit(department.id, 'section', name);
  const asset = await insertAsset(ownSection.id);
  const shift = await clockShift(ownSection.id, -600, -120, productionDate);
  const startsAt = new Date(shift.startsAt).getTime();
  const at = (offset) => new Date(startsAt + offset * 60000).toISOString();

  const reason = await insertDowntimeReason('BRK', 'breakdown');
  await insertDowntimeEvent(asset.id, reason.id, at(60), at(90));
  const product = await insertProduct(30);
  await insertRunWithCount({
    shiftInstanceId: shift.id, assetId: asset.id, productId: product.id, plannedQuantity: 500,
    startedAt: at(0), endedAt: at(480), count: { good: 400, reject: 20, rework: 0 }
  });
  const action = await insertAction(ownSection.id, { title: 'Blade guard loose' });

  const opened = await openHandover(teamLeader.token, { orgUnitId: ownSection.id, shiftInstanceId: shift.id });
  assert.strictEqual(opened.status, 201, JSON.stringify(opened.body));
  const draftId = opened.body.handover.id;
  assert.strictEqual((await putLine(teamLeader.token, draftId, asset.id, {
    state: 'running', watchNote: 'Blade guard', walked: true
  })).status, 200);
  assert.strictEqual((await addChangePoint(teamLeader.token, draftId, {
    dimension: 'man', description: 'Relief operator on the cutter', watchNote: 'First changeover'
  })).status, 201);
  assert.strictEqual((await linkAction(teamLeader.token, draftId, {
    actionId: action.id, disposition: 'carried'
  })).status, 201);
  assert.strictEqual((await patchHandover(teamLeader.token, draftId, {
    jointWalkDone: true, criticalItems: 'Guard on C1 is taped', deviationReason: 'none'
  })).status, 200);

  const submitted = await json(await submit(teamLeader.token, draftId));
  assert.strictEqual(submitted.status, 200, JSON.stringify(submitted.body));
  return { section: ownSection, asset, shift, action, reason, handover: submitted.body.handover };
}

test('a draft takes the evidence fields, and a wrong type, an unknown reason or an over-long text is 400', async () => {
  const draft = await openDraft((await aprilShift('Evidence shift')).id);

  const written = await patchHandover(teamLeader.token, draft.id, {
    jointWalkDone: true, criticalItems: '  Guard on C1 is taped  ', deviationReason: 'partial', colour: 'blue'
  });
  assert.strictEqual(written.status, 200, JSON.stringify(written.body));
  assert.strictEqual(written.body.handover.jointWalkDone, true);
  assert.strictEqual(written.body.handover.criticalItems, 'Guard on C1 is taped');
  assert.strictEqual(written.body.handover.deviationReason, 'partial');
  assert.strictEqual(written.body.handover.changePointsNone, false, 'a field left out is left as it is');

  const atCap = await patchHandover(teamLeader.token, draft.id, { criticalItems: 'x'.repeat(2000) });
  assert.strictEqual(atCap.status, 200, JSON.stringify(atCap.body));
  const overCap = await patchHandover(teamLeader.token, draft.id, { criticalItems: 'x'.repeat(2001) });
  assert.strictEqual(overCap.status, 400, JSON.stringify(overCap.body));
  assert.match(overCap.body.message, /2000/);

  for (const body of [
    { jointWalkDone: 'yes' }, { criticalItems: 42 }, { deviationReason: 3 },
    { deviationReason: 'tired' }, { colour: 'blue' }
  ]) {
    const bad = await patchHandover(teamLeader.token, draft.id, body);
    assert.strictEqual(bad.status, 400, `${JSON.stringify(body)}: ${JSON.stringify(bad.body)}`);
  }
  const badReason = await patchHandover(teamLeader.token, draft.id, { deviationReason: 'tired' });
  assert.match(badReason.body.message, /deviationReason must be one of: none, late, partial, no_incoming_team_leader/);

  const cleared = await patchHandover(teamLeader.token, draft.id, { criticalItems: null, deviationReason: 'no_incoming_team_leader' });
  assert.strictEqual(cleared.status, 200, JSON.stringify(cleared.body));
  assert.strictEqual(cleared.body.handover.criticalItems, null);
  assert.strictEqual(cleared.body.handover.deviationReason, 'no_incoming_team_leader');
});

test('acknowledgement refuses a draft, the author, an outsider, a read Grant and a second acknowledgement', async () => {
  const ownSection = await insertOrgUnit(department.id, 'section', 'Ack refusals');
  const incoming = await insertNamedAccount('Incoming Team Leader');
  const shift = await clockShift(ownSection.id, -600, -120, '2026-07-01');
  const opened = await openHandover(teamLeader.token, { orgUnitId: ownSection.id, shiftInstanceId: shift.id });
  assert.strictEqual(opened.status, 201, JSON.stringify(opened.body));
  const id = opened.body.handover.id;

  const draft = await acknowledge(incoming.token, id);
  assert.strictEqual(draft.status, 409, JSON.stringify(draft.body));
  assert.strictEqual(draft.body.code, 'HANDOVER_NOT_SUBMITTED');

  await patchHandover(teamLeader.token, id, { changePointsNone: true });
  assert.strictEqual((await submit(teamLeader.token, id)).status, 200);

  const own = await acknowledge(teamLeader.token, id);
  assert.strictEqual(own.status, 409, JSON.stringify(own.body));
  assert.strictEqual(own.body.code, 'AUTHOR_CANNOT_ACKNOWLEDGE');

  const outside = await acknowledge(outsider.token, id);
  assert.strictEqual(outside.status, 403);
  assert.strictEqual(outside.body.code, 'OUTSIDE_GRANTED_ORG_UNITS');
  const reader = await insertAccount({ grants: [{ orgUnitId: ownSection.id, write: false }] });
  assert.strictEqual((await acknowledge(reader.token, id)).status, 403);
  assert.strictEqual((await acknowledge(incoming.token, '999999999999')).status, 404);

  const first = await acknowledge(incoming.token, id, { note: 'Walked it with the outgoing TL' });
  assert.strictEqual(first.status, 200, JSON.stringify(first.body));
  const twice = await acknowledge(incoming.token, id);
  assert.strictEqual(twice.status, 409, JSON.stringify(twice.body));
  assert.strictEqual(twice.body.code, 'HANDOVER_ALREADY_ACKNOWLEDGED');
});

test('acknowledgement records who and when and each watch result, and the shift leaves the exception list', async () => {
  const sealed = await sealedHandover('Ack records', '2026-07-02');
  const incoming = await insertNamedAccount('Incoming Team Leader');
  const id = sealed.handover.id;
  const [point] = sealed.handover.changePoints.man;

  let [shift] = await sectionDay(sealed.section.id, '2026-07-02');
  assert.deepStrictEqual(shift.exceptions, ['unacknowledged'], 'submitted, and the shift ended two hours ago');
  assert.strictEqual(shift.acknowledgementLatencyMinutes, null);
  assert.strictEqual(shift.late, true);

  // Refusals inside the body: a result outside the set, another handover's
  // change point, a malformed id. None of them writes anything.
  const other = await sealedHandover('Ack records other', '2026-07-02');
  const [otherPoint] = other.handover.changePoints.man;
  const badResult = await acknowledge(incoming.token, id, { changePointResults: [{ changePointId: point.id, result: 'fine' }] });
  assert.strictEqual(badResult.status, 400, JSON.stringify(badResult.body));
  assert.match(badResult.body.message, /result must be one of: ok, concern, not_run/);
  const elsewhere = await acknowledge(incoming.token, id, { changePointResults: [{ changePointId: otherPoint.id, result: 'ok' }] });
  assert.strictEqual(elsewhere.status, 404, JSON.stringify(elsewhere.body));
  const malformed = await acknowledge(incoming.token, id, { changePointResults: [{ changePointId: 'CP-1', result: 'ok' }] });
  assert.strictEqual(malformed.status, 400);
  assert.strictEqual((await acknowledge(incoming.token, id, { changePointResults: 'ok' })).status, 400);
  const unchanged = await get(teamLeader.token, `/handovers/${id}`);
  assert.strictEqual(unchanged.body.handover.status, 'submitted');
  assert.strictEqual(unchanged.body.handover.changePoints.man[0].watchResult, null);

  const acknowledged = await acknowledge(incoming.token, id, {
    note: '  Walked C1 together  ',
    changePointResults: [{ changePointId: point.id, result: 'concern', note: 'Changeover took 40 minutes' }]
  });
  assert.strictEqual(acknowledged.status, 200, JSON.stringify(acknowledged.body));
  const handover = acknowledged.body.handover;
  assert.strictEqual(handover.status, 'acknowledged');
  assert.strictEqual(handover.acknowledgedByAccountId, incoming.id);
  assert.ok(handover.acknowledgedAt);
  assert.strictEqual(handover.acknowledgementNote, 'Walked C1 together');
  const [answered] = handover.changePoints.man;
  assert.strictEqual(answered.watchResult, 'concern');
  assert.strictEqual(answered.watchResultNote, 'Changeover took 40 minutes');
  assert.strictEqual(answered.watchAnsweredByAccountId, incoming.id);
  assert.strictEqual(answered.watchAnsweredAt, handover.acknowledgedAt, 'one transaction, one clock');

  const read = await get(teamLeader.token, `/handovers/${id}`);
  assert.deepStrictEqual(read.body.handover.changePoints, handover.changePoints);

  [shift] = await sectionDay(sealed.section.id, '2026-07-02');
  assert.deepStrictEqual(shift.exceptions, []);
  // Measured from the shift instance's start, not from the submit.
  const fromStart = (Date.parse(handover.acknowledgedAt) - new Date(sealed.shift.startsAt).getTime()) / 60000;
  const fromSubmit = (Date.parse(handover.acknowledgedAt) - Date.parse(handover.submittedAt)) / 60000;
  assert.ok(Math.abs(shift.acknowledgementLatencyMinutes - fromStart) < 0.01,
    `${shift.acknowledgementLatencyMinutes} vs ${fromStart}`);
  assert.ok(shift.acknowledgementLatencyMinutes > 595, 'ten hours after the shift started');
  assert.ok(Math.abs(shift.acknowledgementLatencyMinutes - fromSubmit) > 500);
});

test('an amendment is version 2 with the snapshot, lines and links copied, and version 1 stays readable', async () => {
  const sealed = await sealedHandover('Amendment', '2026-07-03');
  const incoming = await insertNamedAccount('Incoming Team Leader');
  const amender = await insertNamedAccount('Amending Team Leader');
  const v1 = sealed.handover;

  // The snapshot as submit sealed it: one Asset, 450 planned minutes, a
  // 30-minute breakdown, 420 good-or-reject pieces at 30 s.
  const availability = 420 / 450;
  const performance = (420 * 30 / 60) / 420;
  const quality = 400 / 420;
  const expectedSnapshot = {
    oee: round6(availability * performance * quality),
    availability: round6(availability),
    performance: round6(performance),
    quality: round6(quality),
    plannedProductionMinutes: 450,
    runMinutes: 420,
    unplannedDowntimeMinutes: 30,
    topLossReasonId: sealed.reason.id,
    topLossMinutes: 30,
    unclassifiedDowntimeMinutes: 0,
    unclassifiedStopCount: 0,
    goodQuantity: 400,
    rejectQuantity: 20,
    reworkQuantity: 0,
    plannedQuantity: 500,
    performanceSuspect: false,
    openStopCount: 0,
    openQualityIssueCount: 0,
    safetyEventCount: 0
  };
  assert.deepStrictEqual(v1.snapshot, expectedSnapshot);

  const acknowledged = await acknowledge(incoming.token, v1.id, {
    changePointResults: [{ changePointId: v1.changePoints.man[0].id, result: 'ok' }]
  });
  assert.strictEqual(acknowledged.status, 200, JSON.stringify(acknowledged.body));

  // More counts after the fact: an amendment copies the sealed numbers, it
  // does not recompute them.
  const product = await insertProduct(30);
  const startsAt = new Date(sealed.shift.startsAt).toISOString();
  await insertRunWithCount({
    shiftInstanceId: sealed.shift.id, assetId: sealed.asset.id, productId: product.id, plannedQuantity: 100,
    startedAt: startsAt, endedAt: new Date(sealed.shift.endsAt).toISOString(), count: { good: 0, reject: 90, rework: 0 }
  });

  const amended = await amend(amender.token, v1.id, {
    reason: '  Critical items missed the taped guard on C2  ',
    criticalItems: 'Guards on C1 and C2 are taped',
    deviationReason: 'partial'
  });
  assert.strictEqual(amended.status, 201, JSON.stringify(amended.body));
  const v2 = amended.body.handover;
  assert.notStrictEqual(v2.id, v1.id);
  assert.strictEqual(v2.version, 2);
  assert.strictEqual(v2.supersedesId, v1.id);
  assert.strictEqual(v2.amendmentReason, 'Critical items missed the taped guard on C2');
  assert.strictEqual(v2.status, 'submitted');
  assert.strictEqual(v2.submittedByAccountId, amender.id);
  assert.strictEqual(v2.authorDisplayName, 'Amending Team Leader');
  assert.strictEqual(v2.acknowledgedAt, null, 'a new version is acknowledged afresh');
  assert.strictEqual(v2.criticalItems, 'Guards on C1 and C2 are taped');
  assert.strictEqual(v2.deviationReason, 'partial');
  assert.strictEqual(v2.jointWalkDone, true, 'a field the amendment did not send is copied');
  assert.strictEqual(v2.late, v1.late);
  assert.strictEqual(v2.productionDate, v1.productionDate);
  assert.strictEqual(v2.shiftInstanceId, v1.shiftInstanceId);
  assert.deepStrictEqual(v2.snapshot, expectedSnapshot);
  assert.deepStrictEqual(v2.snapshotGaps, v1.snapshotGaps);

  const lineFields = ({ id, createdAt, updatedAt, ...rest }) => rest;
  assert.deepStrictEqual(v2.machineLines.map(lineFields), v1.machineLines.map(lineFields));
  assert.notStrictEqual(v2.machineLines[0].id, v1.machineLines[0].id);
  assert.deepStrictEqual(
    v2.changePoints.man.map(({ dimension, description, watchNote, employeeId }) => ({ dimension, description, watchNote, employeeId })),
    v1.changePoints.man.map(({ dimension, description, watchNote, employeeId }) => ({ dimension, description, watchNote, employeeId }))
  );
  assert.strictEqual(v2.changePoints.man[0].watchResult, null, 'the watch is answered by the next acknowledgement');
  assert.deepStrictEqual(
    v2.actions.map((link) => [link.action.id, link.disposition]),
    [[sealed.action.id, 'carried']]
  );

  // Version 1, at its own address, as it was acknowledged — now superseded.
  const old = await get(teamLeader.token, `/handovers/${v1.id}`);
  assert.strictEqual(old.status, 200, JSON.stringify(old.body));
  assert.strictEqual(old.body.handover.version, 1);
  assert.strictEqual(old.body.handover.status, 'acknowledged');
  assert.strictEqual(old.body.handover.criticalItems, 'Guard on C1 is taped');
  assert.ok(old.body.handover.supersededAt);
  assert.strictEqual(old.body.handover.supersededByAccountId, amender.id);
  assert.strictEqual(old.body.handover.changePoints.man[0].watchResult, 'ok');
  assert.deepStrictEqual(old.body.handover.snapshot, expectedSnapshot);

  const [shift] = await sectionDay(sealed.section.id, '2026-07-03');
  assert.strictEqual(shift.handover.id, v2.id, 'the day reads the live version');
  assert.deepStrictEqual(shift.exceptions, ['unacknowledged', 'amended_after_acknowledgement']);
  assert.strictEqual(shift.acknowledgementLatencyMinutes, null);

  // A superseded version is neither acknowledged nor amended again.
  const ackOld = await acknowledge(incoming.token, v1.id);
  assert.strictEqual(ackOld.status, 409, JSON.stringify(ackOld.body));
  assert.strictEqual(ackOld.body.code, 'HANDOVER_SUPERSEDED');
  const amendOld = await amend(amender.token, v1.id, { reason: 'Again' });
  assert.strictEqual(amendOld.status, 409, JSON.stringify(amendOld.body));
  assert.strictEqual(amendOld.body.code, 'HANDOVER_SUPERSEDED');

  // Versions, newest first, from either version's address.
  for (const address of [v1.id, v2.id]) {
    const versions = await get(teamLeader.token, `/handovers/${address}/versions`);
    assert.strictEqual(versions.status, 200, JSON.stringify(versions.body));
    assert.deepStrictEqual(versions.body.versions.map((version) => ({
      id: version.id, version: version.version, status: version.status,
      authorName: version.authorName, amendmentReason: version.amendmentReason
    })), [
      { id: v2.id, version: 2, status: 'submitted', authorName: 'Amending Team Leader',
        amendmentReason: 'Critical items missed the taped guard on C2' },
      { id: v1.id, version: 1, status: 'acknowledged', authorName: 'Handover Test Account', amendmentReason: null }
    ]);
    assert.ok(versions.body.versions[0].submittedAt);
    assert.strictEqual(versions.body.versions[0].acknowledgedAt, null);
    assert.ok(versions.body.versions[1].acknowledgedAt);
  }
  assert.strictEqual((await get(outsider.token, `/handovers/${v1.id}/versions`)).status, 403);
  assert.strictEqual((await get(teamLeader.token, '/handovers/999999999999/versions')).status, 404);

  // The amender wrote version 2, so the amender cannot acknowledge it; the
  // incoming Team Leader can, and the day's exceptions narrow to the amendment.
  const ownAmendment = await acknowledge(amender.token, v2.id);
  assert.strictEqual(ownAmendment.body.code, 'AUTHOR_CANNOT_ACKNOWLEDGE');
  assert.strictEqual((await acknowledge(incoming.token, v2.id)).status, 200);
  const [after] = await sectionDay(sealed.section.id, '2026-07-03');
  assert.deepStrictEqual(after.exceptions, ['amended_after_acknowledgement']);
});

test('an amendment is refused for a draft, without a reason, and for an outsider', async () => {
  const ownSection = await insertOrgUnit(department.id, 'section', 'Amendment refusals');
  const shift = await clockShift(ownSection.id, -600, -120, '2026-07-04');
  const opened = await openHandover(teamLeader.token, { orgUnitId: ownSection.id, shiftInstanceId: shift.id });
  const id = opened.body.handover.id;

  const draft = await amend(teamLeader.token, id, { reason: 'Too early' });
  assert.strictEqual(draft.status, 409, JSON.stringify(draft.body));
  assert.strictEqual(draft.body.code, 'HANDOVER_NOT_SUBMITTED');
  assert.match(draft.body.message, /submit it first/);

  await patchHandover(teamLeader.token, id, { changePointsNone: true });
  assert.strictEqual((await submit(teamLeader.token, id)).status, 200);

  for (const body of [{}, { reason: '   ' }, { reason: 7 }]) {
    const blank = await amend(teamLeader.token, id, body);
    assert.strictEqual(blank.status, 400, `${JSON.stringify(body)}: ${JSON.stringify(blank.body)}`);
    assert.strictEqual(blank.body.code, 'REASON_REQUIRED');
  }
  const badField = await amend(teamLeader.token, id, { reason: 'Fix', deviationReason: 'tired' });
  assert.strictEqual(badField.status, 400);
  const outside = await amend(outsider.token, id, { reason: 'Not mine' });
  assert.strictEqual(outside.status, 403);
  assert.strictEqual(outside.body.code, 'OUTSIDE_GRANTED_ORG_UNITS');
  assert.strictEqual((await amend(teamLeader.token, '999999999999', { reason: 'x' })).status, 404);

  const versions = await get(teamLeader.token, `/handovers/${id}/versions`);
  assert.strictEqual(versions.body.versions.length, 1, 'nothing refused wrote a version');
});

test('the Section\'s day shows no_handover for an ended shift and unacknowledged only past 30 minutes', async () => {
  const ownSection = await insertOrgUnit(department.id, 'section', 'Exceptions');
  const date = '2026-07-05';
  // A Section's shift instances may not overlap, so these four run one after
  // another.
  const ended = await clockShift(ownSection.id, -200, -120, date);
  const overdue = await clockShift(ownSection.id, -100, -31, date);
  const recent = await clockShift(ownSection.id, -30, -10, date);
  const future = await clockShift(ownSection.id, 60, 540, date);

  for (const shift of [overdue, recent]) {
    const opened = await openHandover(teamLeader.token, { orgUnitId: ownSection.id, shiftInstanceId: shift.id });
    assert.strictEqual(opened.status, 201, JSON.stringify(opened.body));
    await patchHandover(teamLeader.token, opened.body.handover.id, { changePointsNone: true });
    assert.strictEqual((await submit(teamLeader.token, opened.body.handover.id)).status, 200);
  }

  const shifts = await sectionDay(ownSection.id, date);
  assert.deepStrictEqual(shifts.map((shift) => shift.shiftInstanceId), [ended.id, overdue.id, recent.id, future.id]);
  const byId = Object.fromEntries(shifts.map((shift) => [shift.shiftInstanceId, shift]));

  assert.deepStrictEqual(byId[ended.id].exceptions, ['no_handover']);
  assert.strictEqual(byId[ended.id].handover, null);
  assert.strictEqual(byId[ended.id].late, null);
  assert.strictEqual(byId[ended.id].acknowledgementLatencyMinutes, null);

  assert.deepStrictEqual(byId[overdue.id].exceptions, ['unacknowledged']);
  assert.strictEqual(byId[overdue.id].late, true);
  assert.deepStrictEqual(byId[recent.id].exceptions, [], 'ten minutes after the shift is not yet overdue');
  assert.strictEqual(byId[recent.id].late, false);
  assert.deepStrictEqual(byId[future.id].exceptions, [], 'a shift that has not ended owes nothing yet');

  // Nothing resolves itself: read again, the exceptions are the same.
  const again = await sectionDay(ownSection.id, date);
  assert.deepStrictEqual(again.map((shift) => shift.exceptions), shifts.map((shift) => shift.exceptions));
});
