/*
 * Raising an Action from a Safety observation (issue #231) — over HTTP,
 * against a real database and a real (locally issued) JWKS. The seam and the
 * fixture scaffolding mirror `safety-incident-concern.test.js` closely: the
 * same shape of path, built out of the same Action-log write, with the Safety
 * observation standing where the Safety incident stood.
 *
 * What #231 asks for, and nothing more (#223's own spec, decision 9):
 * `action_items.safety_observation_id` is the source column, already in the
 * schema and already permitted by #221's narrowed `action_items_single_source`
 * (it counts `safety_observation_id` alongside `safety_incident_id` and
 * `quality_issue_id`); no Grant is needed to raise the Action, only Site
 * visibility, the same weak question the observation's own read already asks;
 * the caller chooses the Action's kind from `actions.ACTION_TYPES`, the
 * existing known set, rather than a fixed `'concern'`; the observation's
 * detail lists the Actions raised from it with their status; the Action's
 * detail names the observation's type, category and severity potential; and
 * an observation with no Action against it stays findable through the
 * register's own `hasAction=false` filter, worst-first order intact.
 *
 * No schema migration and no status column on an observation: this file
 * writes nothing new to the database that a migration would be needed for,
 * and section 3 below asserts an observation still carries none of the
 * status-shaped fields safety-observations.test.js already checks for.
 *
 * Needs a database with every migration applied, including
 * 1800400000000_capa-is-not-a-source.js. Set DATABASE_URL first — see the
 * README's Tests section.
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
const insertedObservationIds = [];
const insertedActionIds = [];

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

async function insertAccount({ role = 'operator', grants = [] } = {}) {
  const subject = uniqueCode('soaacct');
  const { rows: [account] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status)
     VALUES ($1, 'Safety Observation Action Account', $2, $3, TRUE, 'approved') RETURNING id`,
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

async function insertSite() {
  const { rows: [site] } = await pool.query(
    `INSERT INTO sites (code, name, timezone) VALUES ($1, $2, $3) RETURNING id, code, name`,
    [uniqueCode('SOA'), 'Safety Observation Action Test Site', 'Asia/Ho_Chi_Minh']
  );
  insertedSiteIds.push(site.id);
  return site;
}

async function insertOrgUnit(siteId, { name = 'Observation Action Unit' } = {}) {
  const { rows: [orgUnit] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, NULL, $2, $3, 'area') RETURNING id, code, name, path`,
    [siteId, uniqueCode('SOAOU'), name]
  );
  insertedOrgUnitIds.push(orgUnit.id);
  return orgUnit;
}

async function recordObservation(token, siteId, body) {
  const response = await fetch(`${base}/api/safety/sites/${siteId}/observations`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  const payload = await json(response);
  if (payload.status === 201) insertedObservationIds.push(payload.body.observation.id);
  return payload;
}

async function readObservation(token, id) {
  const response = await fetch(`${base}/api/safety/observations/${id}`, { headers: token });
  return json(response);
}

async function listObservations(token, siteId, query = '') {
  const response = await fetch(`${base}/api/safety/sites/${siteId}/observations${query}`, {
    headers: token
  });
  return json(response);
}

// `POST /api/actions/safety-observations/:id/action` — raising one from a
// Safety observation (issue #231), the mirror of the Safety incident address.
async function raiseAction(token, observationId, body) {
  const response = await fetch(`${base}/api/actions/safety-observations/${observationId}/action`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  const payload = await json(response);
  if (payload.body && payload.body.action) insertedActionIds.push(payload.body.action.id);
  return payload;
}

async function readAction(token, id) {
  const response = await fetch(`${base}/api/actions/${id}`, { headers: token });
  return json(response);
}

let admin;
let adminToken;

// The ground every test starts from: a Site, the Org Unit the observation was
// made at, an Account that may record there, and the observation itself.
async function makeGround(overrides = {}) {
  const site = await insertSite();
  const unit = await insertOrgUnit(site.id, { name: 'Warehouse Floor' });
  const recorder = await insertAccount({ grants: [{ orgUnitId: unit.id }] });

  const recorded = await recordObservation(recorder.token, site.id, {
    orgUnitId: unit.id,
    observedAt: '2026-08-01T02:00:00Z',
    observationType: 'unsafe_condition',
    category: 'housekeeping',
    severityPotential: 'high',
    description: 'Pallets stacked against a fire exit.',
    ...overrides
  });
  assert.strictEqual(recorded.status, 201, `recording failed: ${JSON.stringify(recorded.body)}`);

  return {
    site,
    unit,
    recorder,
    id: recorded.body.observation.id,
    observation: recorded.body.observation
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
});

test.after(async () => {
  // Children before parents. `action_items.org_unit_id` has no ON DELETE
  // CASCADE, so the Actions go first.
  await pool.query('DELETE FROM action_items WHERE id = ANY($1)', [insertedActionIds]);
  await pool.query('DELETE FROM safety_observations WHERE id = ANY($1)', [
    insertedObservationIds
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
// 1. Raising an Action from a Safety observation
// ---------------------------------------------------------------------------

test('raising an Action from a Safety observation lands it at the observation\'s Org Unit, numbers it for the Site, records where it came from, and lets the caller choose its kind — without a Grant', async () => {
  const ground = await makeGround();

  // The recorder holds a write Grant at the Org Unit, but #231's own
  // permission is "anyone who can see the observation": a read-only Grant at
  // the same Org Unit is enough, proving the write Grant is not what governs
  // this path.
  const reporter = await insertAccount({ grants: [{ orgUnitId: ground.unit.id, write: false }] });

  const { status, body } = await raiseAction(reporter.token, ground.id, {
    actionType: 'containment',
    title: 'Clear the fire exit and re-stack the pallets',
    description: 'Immediate containment while a permanent storage fix is found.'
  });
  assert.strictEqual(status, 201, JSON.stringify(body));

  const action = body.action;
  // The caller's chosen kind, not a fixed 'concern' — #231's own criterion,
  // and the one difference from #229's incident path.
  assert.strictEqual(action.actionType, 'containment');
  assert.strictEqual(action.status, 'open');
  assert.strictEqual(action.title, 'Clear the fire exit and re-stack the pallets');
  // The observation's own Org Unit, which the caller never named.
  assert.strictEqual(String(action.orgUnitId), String(ground.unit.id));
  // The Site's own document number — the same shape every Action gets.
  assert.match(action.actionNo, /^AC-[A-Z0-9]+-\d{4}-\d{5}$/);
  // The Action log's usual rules, unchanged: a cycle-1 Plan of its own.
  assert.strictEqual(action.openPhase.phase, 'plan');
  assert.strictEqual(action.openPhase.cycle, 1);

  // It records the Safety observation it came from — the source column, and
  // the nested facts (type, category, severity potential) a reader needs to
  // recognise what was seen.
  assert.strictEqual(String(action.sourceSafetyObservationId), String(ground.id));
  assert.strictEqual(action.sourceType, 'safety_observation');
  assert.strictEqual(String(action.safetyObservation.id), String(ground.id));
  assert.strictEqual(action.safetyObservation.observationType, 'unsafe_condition');
  assert.strictEqual(action.safetyObservation.category, 'housekeeping');
  assert.strictEqual(action.safetyObservation.severityPotential, 'high');

  // No Safety incident and no Non-conformance link, and no CAPA yet.
  assert.strictEqual(action.sourceSafetyIncidentId, null);
  assert.strictEqual(action.safetyIncident, null);
  assert.strictEqual(action.sourceNonconformanceId, null);
  assert.strictEqual(action.capa, null);

  // And the observation's detail shows the Action the other way round, with
  // its status.
  const read = await readObservation(ground.recorder.token, ground.id);
  assert.strictEqual(read.status, 200);
  assert.strictEqual(read.body.observation.actions.length, 1);
  assert.strictEqual(String(read.body.observation.actions[0].id), String(action.id));
  assert.strictEqual(read.body.observation.actions[0].status, 'open');
  assert.strictEqual(read.body.observation.actions[0].actionNo, action.actionNo);
  assert.strictEqual(read.body.observation.actions[0].actionType, 'containment');
});

test('the caller must choose the Action\'s kind from the known set, and a title is required', async () => {
  const ground = await makeGround();

  const missingType = await raiseAction(ground.recorder.token, ground.id, {
    title: 'No kind chosen'
  });
  assert.strictEqual(missingType.status, 400, JSON.stringify(missingType.body));
  assert.match(missingType.body.message, /actionType/);

  const badType = await raiseAction(ground.recorder.token, ground.id, {
    actionType: 'sabotage',
    title: 'Not a real kind'
  });
  assert.strictEqual(badType.status, 400, JSON.stringify(badType.body));
  assert.match(badType.body.message, /actionType/);

  const missingTitle = await raiseAction(ground.recorder.token, ground.id, {
    actionType: 'improvement'
  });
  assert.strictEqual(missingTitle.status, 400, JSON.stringify(missingTitle.body));
  assert.match(missingTitle.body.message, /title is required/);

  const ok = await raiseAction(ground.recorder.token, ground.id, {
    actionType: 'improvement',
    title: 'Add a marked storage lane away from the exit'
  });
  assert.strictEqual(ok.status, 201, JSON.stringify(ok.body));
});

test('raising an Action from a Safety observation is refused for a caller who cannot see the Site, and an unknown observation id is a 404', async () => {
  const ground = await makeGround();

  const otherSite = await insertSite();
  const otherUnit = await insertOrgUnit(otherSite.id, { name: 'Elsewhere' });
  const stranger = await insertAccount({ grants: [{ orgUnitId: otherUnit.id }] });

  const refused = await raiseAction(stranger.token, ground.id, {
    actionType: 'containment',
    title: 'Not mine to raise'
  });
  assert.strictEqual(refused.status, 403, JSON.stringify(refused.body));
  assert.strictEqual(refused.body.message, "Outside the caller's granted Org Units");

  // The observation itself is invisible to them too — the same rule read the
  // other way.
  const hidden = await readObservation(stranger.token, ground.id);
  assert.strictEqual(hidden.status, 403, JSON.stringify(hidden.body));

  const missing = await raiseAction(adminToken, '99999999', {
    actionType: 'containment',
    title: 'Nothing here'
  });
  assert.strictEqual(missing.status, 404, JSON.stringify(missing.body));
  assert.match(missing.body.message, /Safety observation/);
});

test('an observation\'s detail lists every Action raised from it, oldest first, and an observation with none stays an empty list rather than a missing field', async () => {
  const ground = await makeGround();

  const before = await readObservation(ground.recorder.token, ground.id);
  assert.strictEqual(before.status, 200);
  assert.deepStrictEqual(before.body.observation.actions, []);

  const first = await raiseAction(ground.recorder.token, ground.id, {
    actionType: 'containment',
    title: 'Immediate containment'
  });
  assert.strictEqual(first.status, 201, JSON.stringify(first.body));

  const second = await raiseAction(ground.recorder.token, ground.id, {
    actionType: 'preventive',
    title: 'Preventive fix so it does not recur'
  });
  assert.strictEqual(second.status, 201, JSON.stringify(second.body));

  const after = await readObservation(ground.recorder.token, ground.id);
  assert.strictEqual(after.status, 200);
  assert.deepStrictEqual(
    after.body.observation.actions.map((row) => row.id),
    [first.body.action.id, second.body.action.id]
  );
  assert.strictEqual(after.body.observation.actions[0].actionType, 'containment');
  assert.strictEqual(after.body.observation.actions[1].actionType, 'preventive');
});

// ---------------------------------------------------------------------------
// 2. The register's own "no Action" filter (issue #231)
// ---------------------------------------------------------------------------

test('the register can be filtered to observations with no Action against them, worst-first order intact', async () => {
  const site = await insertSite();
  const unit = await insertOrgUnit(site.id, { name: 'Filter Area' });
  const recorder = await insertAccount({ grants: [{ orgUnitId: unit.id }] });

  const answered = await recordObservation(recorder.token, site.id, {
    orgUnitId: unit.id,
    observedAt: '2026-08-05T08:00:00Z',
    observationType: 'unsafe_act',
    category: 'ppe',
    severityPotential: 'fatal',
    description: 'No harness at height — already answered.'
  });
  assert.strictEqual(answered.status, 201, JSON.stringify(answered.body));

  const unanswered = await recordObservation(recorder.token, site.id, {
    orgUnitId: unit.id,
    observedAt: '2026-08-05T09:00:00Z',
    observationType: 'unsafe_condition',
    category: 'housekeeping',
    severityPotential: 'medium',
    description: 'Loose cabling across a walkway — nobody has followed up.'
  });
  assert.strictEqual(unanswered.status, 201, JSON.stringify(unanswered.body));

  const raised = await raiseAction(recorder.token, answered.body.observation.id, {
    actionType: 'containment',
    title: 'Provide a harness point'
  });
  assert.strictEqual(raised.status, 201, JSON.stringify(raised.body));

  // Unfiltered: both are in the register, worst-first (fatal before medium).
  const all = await listObservations(recorder.token, site.id);
  assert.deepStrictEqual(all.body.observations.map((row) => row.id), [
    answered.body.observation.id,
    unanswered.body.observation.id
  ]);

  // hasAction=false: only the walk's unanswered item, so it does not
  // disappear into the list (#231's own reason this filter exists).
  const unansweredOnly = await listObservations(recorder.token, site.id, '?hasAction=false');
  assert.deepStrictEqual(unansweredOnly.body.observations.map((row) => row.id), [
    unanswered.body.observation.id
  ]);

  // hasAction=true: only the one already answered.
  const answeredOnly = await listObservations(recorder.token, site.id, '?hasAction=true');
  assert.deepStrictEqual(answeredOnly.body.observations.map((row) => row.id), [
    answered.body.observation.id
  ]);

  // A malformed value is a 400 naming the field, the same discipline every
  // other known-set/boolean filter in this register gets.
  const bad = await listObservations(recorder.token, site.id, '?hasAction=maybe');
  assert.strictEqual(bad.status, 400);
  assert.match(bad.body.message, /hasAction/);
});

// ---------------------------------------------------------------------------
// 3. No status on an observation, whatever is raised against it (#223
//    decision 9)
// ---------------------------------------------------------------------------

test('an observation still carries no status, resolution or closure of any kind after an Action is raised from it', async () => {
  const ground = await makeGround();

  const raised = await raiseAction(ground.recorder.token, ground.id, {
    actionType: 'countermeasure',
    title: 'A permanent fix'
  });
  assert.strictEqual(raised.status, 201, JSON.stringify(raised.body));

  const read = await readObservation(ground.recorder.token, ground.id);
  assert.strictEqual(read.status, 200);
  for (const key of ['status', 'resolution', 'closedAt', 'closed_at']) {
    assert.ok(
      !Object.prototype.hasOwnProperty.call(read.body.observation, key),
      `an observation must carry no ${key}`
    );
  }
});
