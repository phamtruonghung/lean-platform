/*
 * The Safety retrofit (ADR-0061, issue #507) keeps the audience every route had
 * before it — measured over HTTP against a real database and a real local
 * session, the same seam safety-incidents.test.js and safety-observations.test.js
 * use.
 *
 * Why this file exists. The codes this retrofit asks are seeded on ROLE_STANDARD,
 * the default group every approved Account carries, so "the existing suite still
 * passes" cannot on its own show the retrofit refused nobody: a gate that only
 * admitted supervisors would leave that suite green. And the routes this round
 * left on their standing — the four Safety-authority writes, the two catalogue
 * reads, the two floor-device doors — must still admit who they admitted before,
 * which is the other half of "behaviour changes for nobody".
 *
 * So both questions are asked here as the Account that would notice first: an
 * `operator`, holding the default group and an edit Grant on its own area. The
 * Safety-authority half is measured on a `supervisor` beside it, and the last two
 * tests go the other way and prove the gates are wired at all, by removing one
 * code from every role and watching exactly one address start refusing.
 *
 * Needs a database with every migration applied, including
 * 1803400000000_permissions-and-roles.js. Set DATABASE_URL first.
 */

const test = require('node:test');
const assert = require('node:assert');
const { tokenFor } = require('../helpers/session');

let server;
let base;
let pool;
let closePool;

const insertedAccountIds = [];
const insertedSiteIds = [];
const insertedOrgUnitIds = [];
const insertedIncidentIds = [];
const insertedObservationIds = [];
const insertedInjuryTypeCodes = [];

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

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

// `grants` are `{ orgUnitId, write, safety }` pairs; both flags default to false
// so a test says exactly which standing it is granting.
async function insertAccount({ role = 'operator', grants = [], displayName = null } = {}) {
  const subject = uniqueCode('spacct');
  const name = displayName ?? `Safety Permission Account ${subject}`;
  const { rows: [account] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status)
     VALUES ($1, $2, $3, $4, TRUE, 'approved') RETURNING id`,
    [`${subject}@example.com`, name, role, subject]
  );
  insertedAccountIds.push(account.id);

  for (const grant of grants) {
    await pool.query(
      `INSERT INTO app_user_org_units (app_user_id, org_unit_id, can_write, safety_authority)
       VALUES ($1, $2, $3, $4)`,
      [account.id, grant.orgUnitId, grant.write ?? false, grant.safety ?? false]
    );
  }

  return { id: account.id, role, token: await authHeader(subject) };
}

async function insertSite() {
  const { rows: [site] } = await pool.query(
    `INSERT INTO sites (code, name, timezone) VALUES ($1, $2, $3) RETURNING id, code, name`,
    [uniqueCode('SPS'), 'Safety Permission Test Site', 'Asia/Ho_Chi_Minh']
  );
  insertedSiteIds.push(site.id);
  return site;
}

async function insertOrgUnit(siteId, { parentId = null, unitType = 'area', name = 'Safety Area' } = {}) {
  const { rows: [orgUnit] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, $2, $3, $4, $5) RETURNING id, code, name, path`,
    [siteId, parentId, uniqueCode('SPOU'), name, unitType]
  );
  insertedOrgUnitIds.push(orgUnit.id);
  return orgUnit;
}

async function get(path, token) {
  const response = await fetch(`${base}${path}`, { headers: token });
  return json(response);
}

async function post(path, token, body) {
  const response = await fetch(`${base}${path}`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body ?? {})
  });
  return json(response);
}

async function patch(path, token, body) {
  const response = await fetch(`${base}${path}`, {
    method: 'PATCH',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body ?? {})
  });
  return json(response);
}

let adminToken;
let operator; // role operator: the default group, an edit Grant on its own area.
let supervisor; // role supervisor, holding Safety authority on the same area.
let site;
let area;
let injuryType;
let incidentId;
let observationId;

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

  const admin = await insertAccount({ role: 'admin', displayName: 'Avery Administrator' });
  adminToken = admin.token;

  site = await insertSite();
  area = await insertOrgUnit(site.id, { name: 'Press Line' });

  operator = await insertAccount({
    role: 'operator',
    displayName: 'Ola Operator',
    grants: [{ orgUnitId: area.id, write: true }]
  });

  supervisor = await insertAccount({
    role: 'supervisor',
    displayName: 'Sam Supervisor',
    grants: [{ orgUnitId: area.id, write: true, safety: true }]
  });

  // The catalogue row the classification test names, created through the API as
  // the administrator the code allows — so this file tests the retrofit rather
  // than a hand-made row.
  const injuryTypeCode = uniqueCode('SPIT-');
  const createdType = await post('/api/safety/injury-types', adminToken, {
    code: injuryTypeCode,
    name: `Injury ${injuryTypeCode}`
  });
  assert.strictEqual(createdType.status, 201, JSON.stringify(createdType.body));
  insertedInjuryTypeCodes.push(injuryTypeCode);
  injuryType = createdType.body.injuryType;

  // One record of each kind, recorded by the operator: the reads and the status
  // move below need something to point at.
  const recordedIncident = await post(`/api/safety/sites/${site.id}/incidents`, operator.token, {
    orgUnitId: area.id,
    occurredAt: '2026-04-10T08:00:00Z',
    incidentType: 'injury',
    severityLevel: 'first_aid',
    description: 'Cut a finger on a burr while deburring a part.'
  });
  assert.strictEqual(recordedIncident.status, 201, JSON.stringify(recordedIncident.body));
  incidentId = recordedIncident.body.incident.id;
  insertedIncidentIds.push(incidentId);

  const recordedObservation = await post(`/api/safety/sites/${site.id}/observations`, operator.token, {
    orgUnitId: area.id,
    observationType: 'unsafe_act',
    category: 'ppe',
    severityPotential: 'high',
    description: 'An operator was not wearing safety glasses at the press.'
  });
  assert.strictEqual(recordedObservation.status, 201, JSON.stringify(recordedObservation.body));
  observationId = recordedObservation.body.observation.id;
  insertedObservationIds.push(observationId);
});

test.after(async () => {
  // Children before parents: an incident and an observation both name an Org
  // Unit, and the classification test may have pointed an incident at an Injury
  // type. A rejected `test.after` hangs the file on the framework's timeout and
  // cancels the files behind it, so the order here is the whole cleanup.
  await pool.query('DELETE FROM safety_observations WHERE id = ANY($1)', [insertedObservationIds]);
  await pool.query('DELETE FROM safety_incidents WHERE id = ANY($1)', [insertedIncidentIds]);
  await pool.query('DELETE FROM injury_types WHERE code = ANY($1)', [insertedInjuryTypeCodes]);
  await pool.query('DELETE FROM app_user_org_units WHERE app_user_id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM app_users WHERE id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM org_units WHERE id = ANY($1)', [insertedOrgUnitIds]);
  await pool.query('DELETE FROM sites WHERE id = ANY($1)', [insertedSiteIds]);
  await new Promise((resolve) => server.close(resolve));
  await closePool();
});

// ---------------------------------------------------------------------------
// The premise the retrofit rests on, executed rather than asserted: an Account
// holding the default group alone really does hold every code the gates ask.
// ---------------------------------------------------------------------------

const retrofittedCodes = [
  'SAF_INCIDENTS_DISPLAY',
  'SAF_INCIDENTS_RECORD',
  'SAF_OBSERVATIONS_DISPLAY',
  'SAF_OBSERVATIONS_RECORD'
];

test('an operator holds every code the retrofit asks, and none of the three the findings would ask', async () => {
  const { status, body } = await get('/api/people/me', operator.token);
  assert.strictEqual(status, 200, JSON.stringify(body));

  for (const code of retrofittedCodes) {
    assert.ok(body.permissions.includes(code), `an operator must hold ${code}`);
  }

  // The findings, measured: SAF_CLASSIFY is seeded supervisor-and-above and the
  // two catalogue codes on the administrator alone, which is exactly why those
  // routes were left on the standing they had.
  for (const code of ['SAF_CLASSIFY', 'SAF_INJURY_TYPES_MAINTAIN', 'SAF_BODY_PARTS_MAINTAIN']) {
    assert.ok(!body.permissions.includes(code), `an operator must not hold ${code}`);
  }
  assert.ok(body.roles.includes('ROLE_STANDARD'));
  assert.ok(body.roles.includes('ROLE_OPERATOR'));
});

// ---------------------------------------------------------------------------
// Incidents: the reads, recording, and the ordinary status move.
// ---------------------------------------------------------------------------

test('an operator reads the incident register, the overdue listing and one incident', async () => {
  const register = await get(`/api/safety/sites/${site.id}/incidents`, operator.token);
  assert.strictEqual(register.status, 200, JSON.stringify(register.body));
  assert.ok(
    register.body.incidents.some((incident) => incident.id === incidentId),
    'the incident the operator recorded is in the register'
  );

  const overdue = await get(`/api/safety/sites/${site.id}/incidents/overdue`, operator.token);
  assert.strictEqual(overdue.status, 200, JSON.stringify(overdue.body));

  const detail = await get(`/api/safety/incidents/${incidentId}`, operator.token);
  assert.strictEqual(detail.status, 200, JSON.stringify(detail.body));
  assert.strictEqual(detail.body.incident.id, incidentId);
});

test('an operator records an incident and moves its status one rung', async () => {
  const recorded = await post(`/api/safety/sites/${site.id}/incidents`, operator.token, {
    orgUnitId: area.id,
    occurredAt: '2026-04-11T09:00:00Z',
    incidentType: 'property_damage',
    severityLevel: 'near_miss',
    description: 'A forklift clipped a guard rail on the aisle.'
  });
  assert.strictEqual(recorded.status, 201, JSON.stringify(recorded.body));
  insertedIncidentIds.push(recorded.body.incident.id);

  const moved = await post(`/api/safety/incidents/${recorded.body.incident.id}/status`, operator.token, {
    status: 'investigating'
  });
  assert.strictEqual(moved.status, 200, JSON.stringify(moved.body));
  assert.strictEqual(moved.body.incident.status, 'investigating');
});

// ---------------------------------------------------------------------------
// Observations: register, detail, recording.
// ---------------------------------------------------------------------------

test('an operator reads the observation register and one observation', async () => {
  const register = await get(`/api/safety/sites/${site.id}/observations`, operator.token);
  assert.strictEqual(register.status, 200, JSON.stringify(register.body));
  assert.ok(register.body.observations.some((observation) => observation.id === observationId));

  const detail = await get(`/api/safety/observations/${observationId}`, operator.token);
  assert.strictEqual(detail.status, 200, JSON.stringify(detail.body));
  assert.strictEqual(detail.body.observation.id, observationId);
});

test('an operator records an observation', async () => {
  const recorded = await post(`/api/safety/sites/${site.id}/observations`, operator.token, {
    orgUnitId: area.id,
    observationType: 'unsafe_condition',
    category: 'housekeeping',
    severityPotential: 'medium',
    description: 'Offcuts were stacked beside the walkway.'
  });
  assert.strictEqual(recorded.status, 201, JSON.stringify(recorded.body));
  insertedObservationIds.push(recorded.body.observation.id);
});

// ---------------------------------------------------------------------------
// The catalogue writes, and the catalogue reads the retrofit deliberately left
// open (the findings half).
// ---------------------------------------------------------------------------

test('an operator is refused both catalogue writes naming the code, and still reads both catalogues', async () => {
  const refusedType = await post('/api/safety/injury-types', operator.token, {
    code: uniqueCode('SPIT-'),
    name: 'Anything'
  });
  assert.strictEqual(refusedType.status, 403, JSON.stringify(refusedType.body));
  assert.strictEqual(refusedType.body.code, 'PERMISSION_REQUIRED');
  assert.strictEqual(refusedType.body.permission, 'SAF_INJURY_TYPES_MAINTAIN');

  const refusedCorrection = await patch(`/api/safety/injury-types/${injuryType.id}`, operator.token, {
    name: 'Anything'
  });
  assert.strictEqual(refusedCorrection.status, 403, JSON.stringify(refusedCorrection.body));
  assert.strictEqual(refusedCorrection.body.permission, 'SAF_INJURY_TYPES_MAINTAIN');

  const refusedPart = await post('/api/safety/body-parts', operator.token, {
    code: uniqueCode('SPBP-'),
    name: 'Anything',
    region: 'head'
  });
  assert.strictEqual(refusedPart.status, 403, JSON.stringify(refusedPart.body));
  assert.strictEqual(refusedPart.body.permission, 'SAF_BODY_PARTS_MAINTAIN');

  // The finding, measured from both sides: the reads keep no gate, so the
  // classify dialog's two catalogues still load for a non-administrator.
  const types = await get('/api/safety/injury-types', operator.token);
  assert.strictEqual(types.status, 200, JSON.stringify(types.body));
  assert.ok(types.body.injuryTypes.some((type) => type.id === injuryType.id));

  const parts = await get('/api/safety/body-parts', operator.token);
  assert.strictEqual(parts.status, 200, JSON.stringify(parts.body));
});

// ---------------------------------------------------------------------------
// The four Safety-authority writes keep the standing they had: `SAF_CLASSIFY` is
// seeded supervisor-and-above, while Safety authority is a flag any role's Grant
// may carry — so adding the code would narrow an operator that holds it. The
// finding is measured here rather than argued.
// ---------------------------------------------------------------------------

test('the classification keeps its Safety-authority standing: an operator without it is refused, a supervisor with it is not', async () => {
  const refused = await post(`/api/safety/incidents/${incidentId}/classify`, operator.token, {
    injuryTypeId: injuryType.id
  });
  assert.strictEqual(refused.status, 403, JSON.stringify(refused.body));
  assert.strictEqual(
    refused.body.message,
    "that decision needs Safety authority at this Safety incident's Org Unit"
  );

  const classified = await post(`/api/safety/incidents/${incidentId}/classify`, supervisor.token, {
    injuryTypeId: injuryType.id
  });
  assert.strictEqual(classified.status, 200, JSON.stringify(classified.body));
  assert.strictEqual(classified.body.incident.injuryTypeId, String(injuryType.id));
});

// ---------------------------------------------------------------------------
// And the gates are wired at all. Two mutants, each removing one code from every
// role that holds it and watching exactly its own addresses start refusing.
//
// Every role that holds it, not just the default group: `effectivePermissions`
// unions the default group, the role the Account's own `app_users.role` earns
// (this operator's is ROLE_OPERATOR) and any explicit assignment, so removing a
// code from ROLE_STANDARD alone would leave the operator holding it through
// ROLE_OPERATOR — and then the mutant would prove nothing.
// ---------------------------------------------------------------------------

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

test('removing SAF_INCIDENTS_DISPLAY from every role refuses the incident reads and nothing else', async () => {
  const roleIds = await removeCodeEverywhere('SAF_INCIDENTS_DISPLAY');
  try {
    for (const path of [
      `/api/safety/sites/${site.id}/incidents`,
      `/api/safety/sites/${site.id}/incidents/overdue`,
      `/api/safety/incidents/${incidentId}`
    ]) {
      const refused = await get(path, operator.token);
      assert.strictEqual(refused.status, 403, `${path}: ${JSON.stringify(refused.body)}`);
      assert.strictEqual(refused.body.code, 'PERMISSION_REQUIRED');
      assert.strictEqual(refused.body.permission, 'SAF_INCIDENTS_DISPLAY');
    }

    // A neighbouring gate is untouched: the observation register asks its own
    // code, and recording an incident asks the RECORD code.
    const observations = await get(`/api/safety/sites/${site.id}/observations`, operator.token);
    assert.strictEqual(observations.status, 200, JSON.stringify(observations.body));

    const recorded = await post(`/api/safety/sites/${site.id}/incidents`, operator.token, {
      orgUnitId: area.id,
      occurredAt: '2026-04-12T07:00:00Z',
      incidentType: 'near_miss',
      severityLevel: 'near_miss',
      description: 'Recorded while the DISPLAY code was removed.'
    });
    assert.strictEqual(recorded.status, 201, JSON.stringify(recorded.body));
    insertedIncidentIds.push(recorded.body.incident.id);
  } finally {
    await restoreCodeEverywhere(roleIds, 'SAF_INCIDENTS_DISPLAY');
  }

  // Restored, the same address answers again — the gate reads the tables on
  // every request rather than caching what it saw at sign-in.
  const allowed = await get(`/api/safety/sites/${site.id}/incidents`, operator.token);
  assert.strictEqual(allowed.status, 200, JSON.stringify(allowed.body));
});

test('removing SAF_OBSERVATIONS_RECORD from every role refuses recording an observation and nothing else', async () => {
  const roleIds = await removeCodeEverywhere('SAF_OBSERVATIONS_RECORD');
  try {
    const refused = await post(`/api/safety/sites/${site.id}/observations`, operator.token, {
      orgUnitId: area.id,
      observationType: 'safe_act',
      category: 'ppe',
      severityPotential: 'low',
      description: 'Recorded while the RECORD code was removed.'
    });
    assert.strictEqual(refused.status, 403, JSON.stringify(refused.body));
    assert.strictEqual(refused.body.code, 'PERMISSION_REQUIRED');
    assert.strictEqual(refused.body.permission, 'SAF_OBSERVATIONS_RECORD');

    // The register asks the DISPLAY code, which is still held.
    const register = await get(`/api/safety/sites/${site.id}/observations`, operator.token);
    assert.strictEqual(register.status, 200, JSON.stringify(register.body));
  } finally {
    await restoreCodeEverywhere(roleIds, 'SAF_OBSERVATIONS_RECORD');
  }

  const allowed = await post(`/api/safety/sites/${site.id}/observations`, operator.token, {
    orgUnitId: area.id,
    observationType: 'safe_act',
    category: 'ppe',
    severityPotential: 'low',
    description: 'Recorded after the code was put back.'
  });
  assert.strictEqual(allowed.status, 201, JSON.stringify(allowed.body));
  insertedObservationIds.push(allowed.body.observation.id);
});
