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

async function insertShiftInstance(orgUnitId, shiftDefinitionId, startsAt, endsAt) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO shift_instances
       (site_id, org_unit_id, shift_definition_id, production_date, starts_at, ends_at,
        planned_production_minutes)
     VALUES ($1, $2, $3, $4, $5, $6, 450)
     RETURNING id`,
    [site.id, orgUnitId, shiftDefinitionId, PRODUCTION_DATE, startsAt, endsAt]
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
  await insertAsset(area.id);
  await insertAsset(area.id);
  otherSection = await insertOrgUnit(department.id, 'section', 'TX');

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
  await pool.query('DELETE FROM shift_handovers WHERE org_unit_id = ANY($1)', [insertedOrgUnitIds]);
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
