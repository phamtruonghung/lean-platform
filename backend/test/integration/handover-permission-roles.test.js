/*
 * The Production retrofit (ADR-0061, slice 7, issue #523) keeps the audience
 * every handover route had before it — measured over HTTP against a real
 * database and a real local session, the same seam handovers.test.js uses.
 *
 * Why this file exists. `PRD_HANDOVER_DISPLAY` and `PRD_HANDOVER_WRITE` are
 * seeded on every role, so handovers.test.js staying green cannot on its own
 * show the gates refused nobody: a read gate that only admitted supervisors
 * would leave that suite green too. And `PRD_HANDOVER_ACKNOWLEDGE` was seeded on
 * `ROLE_ADMIN` alone, so the interesting question is the other way round —
 * whether the incoming shift that acknowledges today still can after the route
 * started asking a code.
 *
 * So it asks both questions as the Accounts that would notice first: an
 * `operator` holding a read Grant on the Section for the reads, a `supervisor`
 * holding a write Grant for the acknowledgement, and — in the mutant tests —
 * every role stripped of one code, watching exactly its own addresses start
 * refusing while its neighbours keep answering. That is the same shape
 * people-permission-roles.test.js and maintenance-write-permission-roles.test.js
 * use, and the reason the removal takes the code off *every* role:
 * `effectivePermissions` unions the default group, the role the Account's own
 * `app_users.role` earns and any explicit assignment, so removing it from
 * ROLE_STANDARD alone would leave an operator holding it through ROLE_OPERATOR
 * and the mutant would prove nothing.
 *
 * Needs a database with every migration applied, including
 * 1803700000000_seed-handover-acknowledge.js. Set DATABASE_URL first — see the
 * README's Tests section.
 */

const test = require('node:test');
const assert = require('node:assert');
const { tokenFor } = require('../helpers/session');

const TIMEZONE = 'Asia/Ho_Chi_Minh';

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

let site;
let department;
let section;

let counter = 0;
function uniqueCode(prefix) {
  counter += 1;
  return `${prefix}${process.pid}${counter}`;
}

async function authHeader(subject) {
  const token = await tokenFor(subject);
  return { authorization: 'Bearer ' + token };
}

async function json(response) {
  return { status: response.status, body: await response.json().catch(() => null) };
}

async function insertAccount({ role = 'operator', grants = [] } = {}) {
  const subject = uniqueCode('hppacct');
  const { rows: [account] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status)
     VALUES ($1, 'Handover Permission Test Account', $2, $3, TRUE, 'approved') RETURNING id`,
    [`${subject}@example.com`, role, subject]
  );
  insertedAccountIds.push(account.id);
  for (const grant of grants) {
    await pool.query(
      'INSERT INTO app_user_org_units (app_user_id, org_unit_id, can_write) VALUES ($1, $2, $3)',
      [account.id, grant.orgUnitId, grant.write ?? true]
    );
  }
  return { id: account.id, role, token: await authHeader(subject) };
}

async function insertOrgUnit(parentId, unitType, name) {
  const { rows: [orgUnit] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, $2, $3, $4, $5) RETURNING id, code, name`,
    [site.id, parentId, uniqueCode('HPOU'), name, unitType]
  );
  insertedOrgUnitIds.push(orgUnit.id);
  return orgUnit;
}

async function insertAsset(orgUnitId) {
  const { rows: [asset] } = await pool.query(
    `INSERT INTO assets (org_unit_id, code, name, is_active)
     VALUES ($1, $2, 'Handover Permission Test Machine', TRUE) RETURNING id, code, name`,
    [orgUnitId, uniqueCode('HPAS')]
  );
  insertedAssetIds.push(asset.id);
  return asset;
}

async function insertShiftDefinition() {
  const { rows: [row] } = await pool.query(
    `INSERT INTO shift_definitions (site_id, code, name, start_time, duration_minutes, break_minutes)
     VALUES ($1, $2, 'Permission shift', '06:00', 480, 30) RETURNING id`,
    [site.id, uniqueCode('HPSD')]
  );
  insertedShiftDefinitionIds.push(row.id);
  return row;
}

// A shift instance on the Section. Explicit timestamps rather than offsets from
// now: `shift_instances_no_overlap` refuses two shift instances of one Section
// whose ranges intersect, so each test's shift sits on its own day.
async function insertShift(sectionId, startsAt, endsAt, productionDate) {
  const definition = await insertShiftDefinition();
  const { rows: [shift] } = await pool.query(
    `INSERT INTO shift_instances
       (site_id, org_unit_id, shift_definition_id, production_date, starts_at, ends_at,
        planned_production_minutes)
     VALUES ($1, $2, $3, $4, $5, $6, 450) RETURNING id`,
    [site.id, sectionId, definition.id, productionDate, startsAt, endsAt]
  );
  insertedShiftInstanceIds.push(shift.id);
  return shift;
}

async function get(path, token) {
  return json(await fetch(`${base}/api/production${path}`, { headers: token }));
}

async function post(path, token, body) {
  return json(
    await fetch(`${base}/api/production${path}`, {
      method: 'POST',
      headers: { ...token, ...(body === undefined ? {} : { 'content-type': 'application/json' }) },
      body: body === undefined ? undefined : JSON.stringify(body)
    })
  );
}

async function patch(path, token, body) {
  return json(
    await fetch(`${base}/api/production${path}`, {
      method: 'PATCH',
      headers: { ...token, 'content-type': 'application/json' },
      body: JSON.stringify(body)
    })
  );
}

async function put(path, token, body) {
  return json(
    await fetch(`${base}/api/production${path}`, {
      method: 'PUT',
      headers: { ...token, 'content-type': 'application/json' },
      body: JSON.stringify(body)
    })
  );
}

async function openHandover(token, shiftInstanceId, orgUnitId = section.id) {
  const opened = await post('/handovers', token, { orgUnitId, shiftInstanceId });
  assert.strictEqual(opened.status, 201, JSON.stringify(opened.body));
  return opened.body.handover;
}

// Every active Asset the Section lists gets a normal-running line and the
// change point block is declared none, so submit's completeness rules are met
// and a test can reach the sealed state it is about. The list is read through
// the API rather than passed in, because submit counts every active Asset the
// Section has — including ones an earlier test's area added.
async function fillAndSubmit(token, handover) {
  const listed = await get(`/sections/${section.id}/assets`, token);
  assert.strictEqual(listed.status, 200, JSON.stringify(listed.body));
  for (const asset of listed.body.assets) {
    const written = await put(`/handovers/${handover.id}/machine-lines/${asset.id}`, token, { state: 'running' });
    assert.strictEqual(written.status, 200, JSON.stringify(written.body));
  }
  const declared = await patch(`/handovers/${handover.id}`, token, { changePointsNone: true });
  assert.strictEqual(declared.status, 200, JSON.stringify(declared.body));
  const submitted = await post(`/handovers/${handover.id}/submit`, token);
  assert.strictEqual(submitted.status, 200, JSON.stringify(submitted.body));
  return submitted.body.handover;
}

// `effectivePermissions` unions every source, so a mutant takes the code off
// every role that holds it and puts those same rows back afterwards.
async function removeCodeEverywhere(code) {
  const { rows } = await pool.query(
    'SELECT app_role_id FROM app_role_permissions WHERE permission_code = $1',
    [code]
  );
  assert.ok(rows.length > 0, `${code} must be seeded on at least one role`);
  await pool.query('DELETE FROM app_role_permissions WHERE permission_code = $1', [code]);
  return rows.map((row) => row.app_role_id);
}

async function restoreCodeEverywhere(roleIds, code) {
  for (const roleId of roleIds) {
    await pool.query(
      'INSERT INTO app_role_permissions (app_role_id, permission_code) VALUES ($1, $2)',
      [roleId, code]
    );
  }
}

test.before(async () => {
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
    `INSERT INTO sites (code, name, timezone) VALUES ($1, 'Handover Permission Test Site', $2) RETURNING id`,
    [uniqueCode('HPS'), TIMEZONE]
  ));
  insertedSiteIds.push(site.id);

  department = await insertOrgUnit(null, 'department', 'Handover Permission Department');
  section = await insertOrgUnit(department.id, 'section', 'Permission Section');
});

test.after(async () => {
  await pool.query(
    `DELETE FROM shift_handover_machine_lines
      WHERE handover_id IN (SELECT id FROM shift_handovers WHERE org_unit_id = ANY($1))`,
    [insertedOrgUnitIds]
  );
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
});

// ---------------------------------------------------------------------------
// The seed that makes the acknowledgement gate a no-op for the shift doing it.
// ---------------------------------------------------------------------------

test('every role that could acknowledge before the gate holds PRD_HANDOVER_ACKNOWLEDGE', async () => {
  const { rows } = await pool.query(
    `SELECT r.code
       FROM app_roles r
       JOIN app_role_permissions p ON p.app_role_id = r.id
      WHERE p.permission_code = 'PRD_HANDOVER_ACKNOWLEDGE'
      ORDER BY r.code`
  );
  assert.deepStrictEqual(rows.map((row) => row.code), [
    'ROLE_ADMIN',
    'ROLE_ENGINEER',
    'ROLE_MANAGER',
    'ROLE_OPERATOR',
    'ROLE_STANDARD',
    'ROLE_SUPERVISOR'
  ]);
});

// ---------------------------------------------------------------------------
// The reads: a Grant holder is admitted, and the four addresses are wired.
// ---------------------------------------------------------------------------

test('a read-Grant holder reads the handover, its versions, the Section\'s Assets and its day', async () => {
  const area = await insertOrgUnit(section.id, 'area', 'Permission area');
  await insertAsset(area.id);
  const shift = await insertShift(section.id, '2026-08-01T06:00:00Z', '2026-08-01T14:00:00Z', '2026-08-01');

  const author = await insertAccount({ role: 'supervisor', grants: [{ orgUnitId: department.id }] });
  const reader = await insertAccount({ role: 'operator', grants: [{ orgUnitId: section.id, write: false }] });
  const handover = await openHandover(author.token, shift.id);

  const one = await get(`/handovers/${handover.id}`, reader.token);
  assert.strictEqual(one.status, 200, JSON.stringify(one.body));
  assert.strictEqual(one.body.handover.id, handover.id);

  const versions = await get(`/handovers/${handover.id}/versions`, reader.token);
  assert.strictEqual(versions.status, 200, JSON.stringify(versions.body));
  assert.deepStrictEqual(versions.body.versions.map((version) => version.version), [1]);

  const assets = await get(`/sections/${section.id}/assets`, reader.token);
  assert.strictEqual(assets.status, 200, JSON.stringify(assets.body));
  assert.ok(assets.body.assets.length >= 1);

  const day = await get(`/sections/${section.id}/handovers?date=2026-08-01`, reader.token);
  assert.strictEqual(day.status, 200, JSON.stringify(day.body));
  assert.ok(day.body.shifts.some((entry) => entry.handover && entry.handover.id === handover.id));
});

test('removing PRD_HANDOVER_DISPLAY from every role refuses exactly the four reads', async () => {
  const shift = await insertShift(section.id, '2026-08-02T06:00:00Z', '2026-08-02T14:00:00Z', '2026-08-02');
  const author = await insertAccount({ role: 'supervisor', grants: [{ orgUnitId: department.id }] });
  const reader = await insertAccount({ role: 'operator', grants: [{ orgUnitId: section.id, write: false }] });
  const handover = await openHandover(author.token, shift.id);

  const roleIds = await removeCodeEverywhere('PRD_HANDOVER_DISPLAY');
  try {
    for (const path of [
      `/handovers/${handover.id}`,
      `/handovers/${handover.id}/versions`,
      `/sections/${section.id}/assets`,
      `/sections/${section.id}/handovers?date=2026-08-02`
    ]) {
      const refused = await get(path, reader.token);
      assert.strictEqual(refused.status, 403, `${path}: ${JSON.stringify(refused.body)}`);
      assert.strictEqual(refused.body.code, 'PERMISSION_REQUIRED');
      assert.strictEqual(refused.body.permission, 'PRD_HANDOVER_DISPLAY');
    }

    // Neighbouring gates are untouched: the write code still admits a write,
    // so the refusal above is the read's code and nothing else.
    const written = await patch(`/handovers/${handover.id}`, author.token, { changePointsNone: true });
    assert.strictEqual(written.status, 200, JSON.stringify(written.body));
  } finally {
    await restoreCodeEverywhere(roleIds, 'PRD_HANDOVER_DISPLAY');
  }

  const again = await get(`/handovers/${handover.id}`, reader.token);
  assert.strictEqual(again.status, 200, JSON.stringify(again.body));
});

// ---------------------------------------------------------------------------
// The writes: eleven addresses, one code.
// ---------------------------------------------------------------------------

test('removing PRD_HANDOVER_WRITE refuses the writes and leaves the reads answering', async () => {
  const shift = await insertShift(section.id, '2026-08-03T06:00:00Z', '2026-08-03T14:00:00Z', '2026-08-03');
  const supervisor = await insertAccount({ role: 'supervisor', grants: [{ orgUnitId: department.id }] });
  const draft = await openHandover(supervisor.token, shift.id);

  const roleIds = await removeCodeEverywhere('PRD_HANDOVER_WRITE');
  try {
    const open = await post('/handovers', supervisor.token, { orgUnitId: section.id, shiftInstanceId: shift.id });
    assert.strictEqual(open.status, 403, JSON.stringify(open.body));
    assert.strictEqual(open.body.code, 'PERMISSION_REQUIRED');
    assert.strictEqual(open.body.permission, 'PRD_HANDOVER_WRITE');

    const amend = await patch(`/handovers/${draft.id}`, supervisor.token, { changePointsNone: true });
    assert.strictEqual(amend.status, 403, JSON.stringify(amend.body));
    assert.strictEqual(amend.body.permission, 'PRD_HANDOVER_WRITE');

    const submit = await post(`/handovers/${draft.id}/submit`, supervisor.token);
    assert.strictEqual(submit.status, 403, JSON.stringify(submit.body));
    assert.strictEqual(submit.body.permission, 'PRD_HANDOVER_WRITE');

    // The read code is a different door and still answers.
    const read = await get(`/handovers/${draft.id}`, supervisor.token);
    assert.strictEqual(read.status, 200, JSON.stringify(read.body));
  } finally {
    await restoreCodeEverywhere(roleIds, 'PRD_HANDOVER_WRITE');
  }
});

// ---------------------------------------------------------------------------
// The acknowledgement: its own code, and the author's refusal still the
// service's.
// ---------------------------------------------------------------------------

test('a supervisor who did not author the handover acknowledges it, and the author still cannot', async () => {
  const area = await insertOrgUnit(section.id, 'area', 'Acknowledge area');
  await insertAsset(area.id);

  const author = await insertAccount({ role: 'operator', grants: [{ orgUnitId: department.id }] });
  const incoming = await insertAccount({ role: 'supervisor', grants: [{ orgUnitId: department.id }] });

  const shift = await insertShift(section.id, '2026-08-04T06:00:00Z', '2026-08-04T14:00:00Z', '2026-08-04');
  const sealed = await fillAndSubmit(author.token, await openHandover(author.token, shift.id));

  const acknowledged = await post(`/handovers/${sealed.id}/acknowledge`, incoming.token, { note: 'Walked the shift' });
  assert.strictEqual(acknowledged.status, 200, JSON.stringify(acknowledged.body));
  assert.strictEqual(acknowledged.body.handover.status, 'acknowledged');
  assert.strictEqual(acknowledged.body.handover.acknowledgedByAccountId, incoming.id);

  // The author-does-not-acknowledge-their-own rule (ADR-0054) is still the
  // service's answer, not the code's: the author holds the code and is refused
  // with the service's own 409 on a handover of their own.
  const ownShift = await insertShift(section.id, '2026-08-04T14:00:00Z', '2026-08-04T22:00:00Z', '2026-08-04');
  const own = await fillAndSubmit(author.token, await openHandover(author.token, ownShift.id));
  const refused = await post(`/handovers/${own.id}/acknowledge`, author.token);
  assert.strictEqual(refused.status, 409, JSON.stringify(refused.body));
  assert.strictEqual(refused.body.code, 'AUTHOR_CANNOT_ACKNOWLEDGE');
});

test('removing PRD_HANDOVER_ACKNOWLEDGE refuses the acknowledgement and leaves submit alone', async () => {
  const area = await insertOrgUnit(section.id, 'area', 'Acknowledge gate area');
  await insertAsset(area.id);

  const author = await insertAccount({ role: 'operator', grants: [{ orgUnitId: department.id }] });
  const incoming = await insertAccount({ role: 'supervisor', grants: [{ orgUnitId: department.id }] });
  const shift = await insertShift(section.id, '2026-08-05T06:00:00Z', '2026-08-05T14:00:00Z', '2026-08-05');
  const sealed = await fillAndSubmit(author.token, await openHandover(author.token, shift.id));

  const roleIds = await removeCodeEverywhere('PRD_HANDOVER_ACKNOWLEDGE');
  try {
    const refused = await post(`/handovers/${sealed.id}/acknowledge`, incoming.token);
    assert.strictEqual(refused.status, 403, JSON.stringify(refused.body));
    assert.strictEqual(refused.body.code, 'PERMISSION_REQUIRED');
    assert.strictEqual(refused.body.permission, 'PRD_HANDOVER_ACKNOWLEDGE');

    // The write code is a different door: the author still reads a sealed
    // handover, so the acknowledgement's refusal is its own code's doing.
    const read = await get(`/handovers/${sealed.id}`, author.token);
    assert.strictEqual(read.status, 200, JSON.stringify(read.body));
  } finally {
    await restoreCodeEverywhere(roleIds, 'PRD_HANDOVER_ACKNOWLEDGE');
  }

  const admitted = await post(`/handovers/${sealed.id}/acknowledge`, incoming.token);
  assert.strictEqual(admitted.status, 200, JSON.stringify(admitted.body));
});
