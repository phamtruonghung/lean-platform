/*
 * Safety observations over HTTP (issue #230) — the Account door, against a
 * real database and a real (locally issued) JWKS. This file's scaffolding
 * mirrors safety-incidents.test.js closely: a Safety observation is recorded
 * at an Org Unit, filed by production day, and read back through a filtered,
 * Site-wide register — the same shape, minus the injury classification, the
 * status ladder and the event history none of which an observation has
 * (#223 decision 9).
 *
 * This file builds its own Sites, Org Units and Employees directly against
 * the database, and everything it inserts is deleted again in
 * `test.after()`, in dependency order.
 *
 * Needs a database with every migration applied. Set DATABASE_URL first — see
 * the README's Tests section.
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

async function insertAccount({ role = 'operator', grants = [] } = {}) {
  const subject = uniqueCode('soacct');
  const { rows: [account] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status)
     VALUES ($1, 'Safety Observation Test Account', $2, $3, TRUE, 'approved') RETURNING id`,
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

async function insertSite({ timezone = 'Asia/Ho_Chi_Minh', name = 'Safety Observation Test Site' } = {}) {
  const { rows: [site] } = await pool.query(
    `INSERT INTO sites (code, name, timezone) VALUES ($1, $2, $3) RETURNING id, code, name`,
    [uniqueCode('SOS'), name, timezone]
  );
  insertedSiteIds.push(site.id);
  return site;
}

async function insertOrgUnit(siteId, { parentId = null, unitType = 'area', name = 'Observation Unit' } = {}) {
  const { rows: [orgUnit] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, $2, $3, $4, $5) RETURNING id, code, name, path`,
    [siteId, parentId, uniqueCode('SOOU'), name, unitType]
  );
  insertedOrgUnitIds.push(orgUnit.id);
  return orgUnit;
}

async function insertEmployee() {
  const { rows: [row] } = await pool.query(
    `INSERT INTO employees (employee_no, first_name, last_name, is_active)
     VALUES ($1, 'Ola', 'Observer', TRUE) RETURNING id, display_name`,
    [uniqueCode('SOEMP')]
  );
  insertedEmployeeIds.push(row.id);
  return row;
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

async function record(token, siteId, body) {
  const response = await fetch(`${base}/api/safety/sites/${siteId}/observations`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  return json(response);
}

async function listObservations(token, siteId, query = '') {
  const response = await fetch(`${base}/api/safety/sites/${siteId}/observations${query}`, {
    headers: token
  });
  return json(response);
}

async function readObservation(token, id) {
  const response = await fetch(`${base}/api/safety/observations/${id}`, { headers: token });
  return json(response);
}

let admin;
let adminToken;

async function makeGround() {
  const site = await insertSite();
  const unit = await insertOrgUnit(site.id, { name: 'Press Line' });
  const recorder = await insertAccount({ grants: [{ orgUnitId: unit.id }] });
  return { site, unit, recorder };
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
  // Children before parents. A Safety observation references the Org Unit,
  // the Employee, the shift instance and the Account.
  await pool.query(
    `DELETE FROM safety_observations
      WHERE org_unit_id IN (SELECT id FROM org_units WHERE site_id = ANY($1))`,
    [insertedSiteIds]
  );
  await pool.query('DELETE FROM shift_instances WHERE id = ANY($1)', [insertedShiftInstanceIds]);
  await pool.query('DELETE FROM shift_definitions WHERE id = ANY($1)', [
    insertedShiftDefinitionIds
  ]);
  await pool.query('DELETE FROM app_user_org_units WHERE app_user_id = ANY($1)', [
    insertedAccountIds
  ]);
  await pool.query('DELETE FROM app_users WHERE id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM employees WHERE id = ANY($1)', [insertedEmployeeIds]);
  await pool.query('DELETE FROM org_units WHERE id = ANY($1)', [insertedOrgUnitIds]);
  await pool.query('DELETE FROM sites WHERE id = ANY($1)', [insertedSiteIds]);
  await new Promise((resolve) => server.close(resolve));
  await closePool();
  await jwks.close();
});

// ---------------------------------------------------------------------------
// 1. Recording
// ---------------------------------------------------------------------------

test('an operator with an edit Grant reaching the Org Unit records a Safety observation and reads it back', async () => {
  const { site, unit, recorder } = await makeGround();

  const { status, body } = await record(recorder.token, site.id, {
    orgUnitId: unit.id,
    observationType: 'unsafe_act',
    category: 'ppe',
    severityPotential: 'high',
    description: 'An operator was not wearing safety glasses at the press.',
    actionTaken: 'Reminded the operator and supplied glasses on the spot.'
  });

  assert.strictEqual(status, 201, JSON.stringify(body));
  const observation = body.observation;
  assert.strictEqual(observation.observationType, 'unsafe_act');
  assert.strictEqual(observation.category, 'ppe');
  assert.strictEqual(observation.severityPotential, 'high');
  assert.strictEqual(
    observation.description,
    'An operator was not wearing safety glasses at the press.'
  );
  assert.strictEqual(
    observation.actionTaken,
    'Reminded the operator and supplied glasses on the spot.'
  );
  assert.strictEqual(observation.isStopWork, false);
  assert.strictEqual(observation.recordedByAccountId, String(recorder.id));
  assert.strictEqual(observation.observerEmployeeId, null);
  assert.strictEqual(observation.orgUnitName, 'Press Line');
  assert.strictEqual(observation.siteId, String(site.id));

  // An observation has no status, resolution or closure of any kind
  // (#223 decision 9) — asserted as absence from the wire, the same way
  // ADR-0037 asks "restricted" incident fields be asserted absent.
  for (const key of ['status', 'resolution', 'closedAt', 'closed_at']) {
    assert.ok(
      !Object.prototype.hasOwnProperty.call(observation, key),
      `an observation must carry no ${key}`
    );
  }

  // And anyone who can see the Site finds it in the register and opens it.
  const reader = await insertAccount({ grants: [{ orgUnitId: unit.id, write: false }] });
  const listed = await listObservations(reader.token, site.id);
  assert.strictEqual(listed.status, 200);
  assert.deepStrictEqual(
    listed.body.observations.map((row) => row.id),
    [observation.id]
  );

  const detail = await readObservation(reader.token, observation.id);
  assert.strictEqual(detail.status, 200);
  assert.deepStrictEqual(detail.body.observation, observation);
});

test('stop-work is recorded as its own flag, not folded into a category or a potential', async () => {
  const { site, unit, recorder } = await makeGround();

  const { status, body } = await record(recorder.token, site.id, {
    orgUnitId: unit.id,
    observationType: 'unsafe_condition',
    category: 'energy_isolation',
    severityPotential: 'fatal',
    description: 'A technician stopped work on a machine with a failed lockout.',
    isStopWork: true
  });

  assert.strictEqual(status, 201, JSON.stringify(body));
  assert.strictEqual(body.observation.isStopWork, true);
  assert.strictEqual(body.observation.category, 'energy_isolation');
  assert.strictEqual(body.observation.severityPotential, 'fatal');
});

test('recording is refused with 403 for an Account whose Grant does not reach the Org Unit', async () => {
  const { site, unit } = await makeGround();
  const sibling = await insertOrgUnit(site.id, { name: 'Line beside it' });
  const neighbour = await insertAccount({ grants: [{ orgUnitId: sibling.id }] });
  const reader = await insertAccount({ grants: [{ orgUnitId: unit.id, write: false }] });
  const stranger = await insertAccount({});

  const request = {
    orgUnitId: unit.id,
    observationType: 'safe_act',
    category: 'housekeeping',
    severityPotential: 'low',
    description: 'A walkway was kept clear.'
  };

  for (const token of [neighbour.token, reader.token, stranger.token]) {
    const { status, body } = await record(token, site.id, request);
    assert.strictEqual(status, 403, JSON.stringify(body));
    assert.strictEqual(body.message, "Outside the caller's granted Org Units");
  }

  const { body } = await listObservations(adminToken, site.id);
  assert.deepStrictEqual(body.observations, []);
});

test('an administrator records a Safety observation in a Site they hold no Grant in', async () => {
  const { site, unit } = await makeGround();

  const { status, body } = await record(adminToken, site.id, {
    orgUnitId: unit.id,
    observationType: 'unsafe_act',
    category: 'traffic',
    severityPotential: 'medium',
    description: 'A forklift took a corner too fast.'
  });

  assert.strictEqual(status, 201, JSON.stringify(body));
  assert.strictEqual(body.observation.recordedByAccountId, String(admin.id));
});

test('an unknown Site or an Org Unit of another Site is a 404 before any Grant is asked about', async () => {
  const { unit } = await makeGround();
  const otherSite = await insertSite({ name: 'Another plant' });

  const complete = {
    orgUnitId: unit.id,
    observationType: 'safe_act',
    category: 'other',
    severityPotential: 'low',
    description: 'x'
  };

  const unknownSite = await record(adminToken, 999999999, complete);
  assert.strictEqual(unknownSite.status, 404);
  assert.strictEqual(unknownSite.body.message, 'Site not found');

  const crossSite = await record(adminToken, otherSite.id, complete);
  assert.strictEqual(crossSite.status, 404);
  assert.strictEqual(crossSite.body.message, 'Org Unit not found');

  const malformed = await record(adminToken, otherSite.id, { ...complete, orgUnitId: 'not-an-id' });
  assert.strictEqual(malformed.status, 400);
  assert.strictEqual(malformed.body.message, 'orgUnitId must be a valid Org Unit id');
});

// ---------------------------------------------------------------------------
// 2. Required fields and known sets — chosen, never typed (ADR-0023)
// ---------------------------------------------------------------------------

test('observation type, category, severity potential and description are required and must come from the known sets', async () => {
  const { site, unit, recorder } = await makeGround();
  const complete = {
    orgUnitId: unit.id,
    observationType: 'unsafe_condition',
    category: 'chemical',
    severityPotential: 'medium',
    description: 'A drum of solvent was left uncapped.'
  };

  const missingType = await record(recorder.token, site.id, { ...complete, observationType: undefined });
  assert.strictEqual(missingType.status, 400);
  assert.match(missingType.body.message, /observationType/);

  const badType = await record(recorder.token, site.id, { ...complete, observationType: 'sabotage' });
  assert.strictEqual(badType.status, 400);
  assert.match(badType.body.message, /observationType/);

  const missingCategory = await record(recorder.token, site.id, { ...complete, category: undefined });
  assert.strictEqual(missingCategory.status, 400);
  assert.match(missingCategory.body.message, /category/);

  const badCategory = await record(recorder.token, site.id, { ...complete, category: 'made-up' });
  assert.strictEqual(badCategory.status, 400);
  assert.match(badCategory.body.message, /category/);

  const missingPotential = await record(recorder.token, site.id, {
    ...complete,
    severityPotential: undefined
  });
  assert.strictEqual(missingPotential.status, 400);
  assert.match(missingPotential.body.message, /severityPotential/);

  const badPotential = await record(recorder.token, site.id, {
    ...complete,
    severityPotential: 'catastrophic'
  });
  assert.strictEqual(badPotential.status, 400);
  assert.match(badPotential.body.message, /severityPotential/);

  const missingDescription = await record(recorder.token, site.id, { ...complete, description: undefined });
  assert.strictEqual(missingDescription.status, 400);
  assert.match(missingDescription.body.message, /description/);

  const blankDescription = await record(recorder.token, site.id, { ...complete, description: '   ' });
  assert.strictEqual(blankDescription.status, 400);
  assert.match(blankDescription.body.message, /description/);

  const badStopWork = await record(recorder.token, site.id, { ...complete, isStopWork: 'maybe' });
  assert.strictEqual(badStopWork.status, 400);
  assert.match(badStopWork.body.message, /isStopWork/);

  const ok = await record(recorder.token, site.id, complete);
  assert.strictEqual(ok.status, 201, JSON.stringify(ok.body));
});

// ---------------------------------------------------------------------------
// 3. Production day and shift filing (ADR-0017)
// ---------------------------------------------------------------------------

test('an observation is filed against the production day and shift it was observed in', async () => {
  const site = await insertSite();
  const unit = await insertOrgUnit(site.id, { name: 'Shift Line' });
  const recorder = await insertAccount({ grants: [{ orgUnitId: unit.id }] });
  await insertShiftDefinition(site.id, {
    code: 'DAY',
    name: 'Day shift',
    startTime: '06:00',
    durationMinutes: 480
  });
  await generateShifts(unit.id, '2026-05-01', '2026-05-31');

  const { status, body } = await record(recorder.token, site.id, {
    orgUnitId: unit.id,
    observedAt: '2026-05-10T02:00:00Z', // 09:00 local time, inside the day shift
    observationType: 'safe_act',
    category: 'procedure',
    severityPotential: 'low',
    description: 'A lockout was performed correctly before maintenance.'
  });

  assert.strictEqual(status, 201, JSON.stringify(body));
  assert.strictEqual(body.observation.productionDate, '2026-05-10');
  assert.ok(body.observation.shiftInstanceId, 'a shift instance should have been filled in');
  assert.ok(body.observation.shiftCode, 'a shift code should have been read back');
});

// ---------------------------------------------------------------------------
// 4. The register: filters and worst-first ordering
// ---------------------------------------------------------------------------

test('the register orders worst-first by severity potential, newest first within a tie', async () => {
  const { site, unit, recorder } = await makeGround();

  const low = await record(recorder.token, site.id, {
    orgUnitId: unit.id,
    observedAt: '2026-06-01T08:00:00Z',
    observationType: 'unsafe_condition',
    category: 'housekeeping',
    severityPotential: 'low',
    description: 'A trip hazard on the floor.'
  });
  const fatalOlder = await record(recorder.token, site.id, {
    orgUnitId: unit.id,
    observedAt: '2026-06-01T09:00:00Z',
    observationType: 'unsafe_act',
    category: 'working_at_height',
    severityPotential: 'fatal',
    description: 'Working at height with no harness — reported first.'
  });
  const fatalNewer = await record(recorder.token, site.id, {
    orgUnitId: unit.id,
    observedAt: '2026-06-01T10:00:00Z',
    observationType: 'unsafe_act',
    category: 'working_at_height',
    severityPotential: 'fatal',
    description: 'Working at height with no harness — reported second.'
  });
  const medium = await record(recorder.token, site.id, {
    orgUnitId: unit.id,
    observedAt: '2026-06-01T11:00:00Z',
    observationType: 'unsafe_act',
    category: 'machine_guarding',
    severityPotential: 'medium',
    description: 'A guard was left open briefly.'
  });

  for (const r of [low, fatalOlder, fatalNewer, medium]) {
    assert.strictEqual(r.status, 201, JSON.stringify(r.body));
  }

  const { status, body } = await listObservations(recorder.token, site.id);
  assert.strictEqual(status, 200);
  assert.deepStrictEqual(
    body.observations.map((row) => row.id),
    [fatalNewer.body.observation.id, fatalOlder.body.observation.id, medium.body.observation.id, low.body.observation.id]
  );
});

test('the register is filtered by Org Unit (including beneath it), type, category, severity potential, stop-work and date range', async () => {
  const site = await insertSite();
  const parent = await insertOrgUnit(site.id, { name: 'Filter Area' });
  const child = await insertOrgUnit(site.id, { parentId: parent.id, name: 'Filter Cell' });
  const sibling = await insertOrgUnit(site.id, { name: 'Filter Sibling' });
  const recorder = await insertAccount({
    grants: [
      { orgUnitId: parent.id },
      { orgUnitId: child.id },
      { orgUnitId: sibling.id }
    ]
  });

  const inParent = await record(recorder.token, site.id, {
    orgUnitId: parent.id,
    observedAt: '2026-07-01T08:00:00Z',
    observationType: 'unsafe_act',
    category: 'ppe',
    severityPotential: 'high',
    description: 'No gloves worn while handling sheet metal.'
  });
  const inChild = await record(recorder.token, site.id, {
    orgUnitId: child.id,
    observedAt: '2026-07-05T08:00:00Z',
    observationType: 'safe_act',
    category: 'housekeeping',
    severityPotential: 'low',
    description: 'A spill was cleaned up promptly.',
    isStopWork: true
  });
  const inSibling = await record(recorder.token, site.id, {
    orgUnitId: sibling.id,
    observedAt: '2026-07-10T08:00:00Z',
    observationType: 'unsafe_condition',
    category: 'chemical',
    severityPotential: 'fatal',
    description: 'A chemical label was missing.'
  });

  for (const r of [inParent, inChild, inSibling]) {
    assert.strictEqual(r.status, 201, JSON.stringify(r.body));
  }

  // Org Unit scope reaches the parent and everything beneath it, not the sibling.
  const byOrgUnit = await listObservations(recorder.token, site.id, `?orgUnitId=${parent.id}`);
  assert.deepStrictEqual(
    new Set(byOrgUnit.body.observations.map((row) => row.id)),
    new Set([inParent.body.observation.id, inChild.body.observation.id])
  );

  const byType = await listObservations(recorder.token, site.id, '?observationType=safe_act');
  assert.deepStrictEqual(byType.body.observations.map((row) => row.id), [inChild.body.observation.id]);

  const byCategory = await listObservations(recorder.token, site.id, '?category=chemical');
  assert.deepStrictEqual(byCategory.body.observations.map((row) => row.id), [inSibling.body.observation.id]);

  const byPotential = await listObservations(recorder.token, site.id, '?severityPotential=fatal');
  assert.deepStrictEqual(byPotential.body.observations.map((row) => row.id), [inSibling.body.observation.id]);

  const byStopWork = await listObservations(recorder.token, site.id, '?isStopWork=true');
  assert.deepStrictEqual(byStopWork.body.observations.map((row) => row.id), [inChild.body.observation.id]);

  const byRange = await listObservations(recorder.token, site.id, '?from=2026-07-04&to=2026-07-09');
  assert.deepStrictEqual(byRange.body.observations.map((row) => row.id), [inChild.body.observation.id]);

  // A malformed filter value is a 400 naming the field, not an empty list
  // that hides the caller's own typo.
  const badFilter = await listObservations(recorder.token, site.id, '?observationType=oops');
  assert.strictEqual(badFilter.status, 400);
  assert.match(badFilter.body.message, /observationType/);

  const badDate = await listObservations(recorder.token, site.id, '?from=not-a-date');
  assert.strictEqual(badDate.status, 400);
  assert.match(badDate.body.message, /from/);
});

// ---------------------------------------------------------------------------
// 5. Reading: any Account that can see the Site
// ---------------------------------------------------------------------------

test('reading the register or a detail is refused for an Account that cannot see the Site at all', async () => {
  const { site, unit, recorder } = await makeGround();
  const { status: recordStatus, body: recordBody } = await record(recorder.token, site.id, {
    orgUnitId: unit.id,
    observationType: 'safe_act',
    category: 'other',
    severityPotential: 'low',
    description: 'Nothing unusual.'
  });
  assert.strictEqual(recordStatus, 201);

  const stranger = await insertAccount({});
  const listRefused = await listObservations(stranger.token, site.id);
  assert.strictEqual(listRefused.status, 403);
  assert.strictEqual(listRefused.body.message, "Outside the caller's granted Org Units");

  const detailRefused = await readObservation(stranger.token, recordBody.observation.id);
  assert.strictEqual(detailRefused.status, 403);
  assert.strictEqual(detailRefused.body.message, "Outside the caller's granted Org Units");

  // A read-only Grant anywhere in the Site is enough — reading is Site-wide
  // (ADR-0009, ADR-0032), unlike recording.
  const reader = await insertAccount({ grants: [{ orgUnitId: unit.id, write: false }] });
  const listAllowed = await listObservations(reader.token, site.id);
  assert.strictEqual(listAllowed.status, 200);
  const detailAllowed = await readObservation(reader.token, recordBody.observation.id);
  assert.strictEqual(detailAllowed.status, 200);
});

test('an unknown observation id is a 404', async () => {
  const missing = await readObservation(adminToken, 999999999);
  assert.strictEqual(missing.status, 404);
  assert.strictEqual(missing.body.message, 'Safety observation not found');
});
