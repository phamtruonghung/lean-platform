/*
 * Safety incidents over HTTP (issue #226), against a real database and a real
 * (locally issued) JWKS — the same seam nonconformances.test.js uses, and
 * this file's own scaffolding mirrors it closely: a Safety incident is the
 * same shape of record as a Non-conformance (recorded at an Org Unit,
 * Site-scoped number, production-day filing, a filtered register, a detail).
 *
 * This file builds its own Sites, Org Units, Assets and Employees directly
 * against the database, and everything it inserts is deleted again in
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
const insertedAssetIds = [];
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

// An Account, optionally holding Grants. `grants` are `{ orgUnitId, write }`
// pairs; `write` defaults to true, since most of this file's Accounts are
// recording rather than reading.
async function insertAccount({ role = 'operator', grants = [] } = {}) {
  const subject = uniqueCode('siacct');
  const { rows: [account] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status)
     VALUES ($1, 'Safety Test Account', $2, $3, TRUE, 'approved') RETURNING id`,
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

async function insertSite({ timezone = 'Asia/Ho_Chi_Minh', name = 'Safety Test Site' } = {}) {
  const { rows: [site] } = await pool.query(
    `INSERT INTO sites (code, name, timezone) VALUES ($1, $2, $3) RETURNING id, code, name`,
    [uniqueCode('SIS'), name, timezone]
  );
  insertedSiteIds.push(site.id);
  return site;
}

async function insertOrgUnit(siteId, { parentId = null, unitType = 'area', name = 'Safety Unit' } = {}) {
  const { rows: [orgUnit] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, $2, $3, $4, $5) RETURNING id, code, name, path`,
    [siteId, parentId, uniqueCode('SIOU'), name, unitType]
  );
  insertedOrgUnitIds.push(orgUnit.id);
  return orgUnit;
}

async function insertAsset(orgUnitId, { name = 'Safety Asset' } = {}) {
  const { rows: [asset] } = await pool.query(
    `INSERT INTO assets (org_unit_id, code, name, asset_type, criticality)
     VALUES ($1, $2, $3, 'machine', 'high') RETURNING id, org_unit_id`,
    [orgUnitId, uniqueCode('SIAS'), name]
  );
  insertedAssetIds.push(asset.id);
  return asset;
}

async function insertEmployee({ isActive = true } = {}) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO employees (employee_no, first_name, last_name, is_active)
     VALUES ($1, 'Sam', 'Hardhat', $2) RETURNING id, display_name`,
    [uniqueCode('SIEMP'), isActive]
  );
  insertedEmployeeIds.push(row.id);
  return row;
}

async function insertShiftDefinition(siteId, {
  code = 'DAY',
  name = 'Day shift',
  startTime = '06:00',
  durationMinutes = 480,
  dayOffset = 0
} = {}) {
  const { rows: [shift] } = await pool.query(
    `INSERT INTO shift_definitions (site_id, code, name, start_time, duration_minutes, day_offset)
     VALUES ($1, $2, $3, $4, $5, $6) RETURNING id`,
    [siteId, uniqueCode(code), name, startTime, durationMinutes, dayOffset]
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
  const response = await fetch(`${base}/api/safety/sites/${siteId}/incidents`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  return json(response);
}

async function listIncidents(token, siteId, query = '') {
  const response = await fetch(`${base}/api/safety/sites/${siteId}/incidents${query}`, {
    headers: token
  });
  return json(response);
}

async function readIncident(token, id) {
  const response = await fetch(`${base}/api/safety/incidents/${id}`, { headers: token });
  return json(response);
}

// The one shape every recording in this file starts from: a Site, an Org
// Unit with a write Grant for the caller. Returns everything a test needs to
// vary one thing about it.
let admin;
let adminToken;

async function makeGround({ withAsset = false, withShifts = false } = {}) {
  const site = await insertSite();
  const unit = await insertOrgUnit(site.id, { name: 'Press Line' });
  const recorder = await insertAccount({ grants: [{ orgUnitId: unit.id }] });
  const asset = withAsset ? await insertAsset(unit.id) : null;
  if (withShifts) {
    await insertShiftDefinition(site.id, {
      code: 'DAY',
      name: 'Day shift',
      startTime: '06:00',
      durationMinutes: 480
    });
    await generateShifts(unit.id, '2026-04-01', '2026-04-30');
  }
  return { site, unit, recorder, asset };
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
  // Children before parents. A Safety incident references the Org Unit, the
  // Asset, the Employee, the shift instance and the Account.
  await pool.query(
    `DELETE FROM safety_incidents
      WHERE org_unit_id IN (SELECT id FROM org_units WHERE site_id = ANY($1))`,
    [insertedSiteIds]
  );
  await pool.query('DELETE FROM assets WHERE id = ANY($1)', [insertedAssetIds]);
  await pool.query('DELETE FROM employees WHERE id = ANY($1)', [insertedEmployeeIds]);
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
// 1. Recording
// ---------------------------------------------------------------------------

test('an operator with an edit Grant reaching the Org Unit records a Safety incident and reads it back', async () => {
  const { site, unit, recorder } = await makeGround({});

  const { status, body } = await record(recorder.token, site.id, {
    orgUnitId: unit.id,
    occurredAt: '2026-04-10T08:00:00Z',
    incidentType: 'injury',
    severityLevel: 'first_aid',
    description: 'Cut a finger on a burr while deburring a part.'
  });

  assert.strictEqual(status, 201, JSON.stringify(body));
  const incident = body.incident;
  assert.strictEqual(incident.status, 'open');
  assert.strictEqual(incident.incidentType, 'injury');
  assert.strictEqual(incident.severityLevel, 'first_aid');
  assert.strictEqual(incident.description, 'Cut a finger on a burr while deburring a part.');
  // first_aid sits below the recordable line.
  assert.strictEqual(incident.isRecordable, false);
  // Who recorded it, as an Account.
  assert.strictEqual(incident.recordedByAccountId, String(recorder.id));
  assert.strictEqual(incident.reportedBy, null);
  assert.strictEqual(incident.orgUnitName, 'Press Line');
  assert.strictEqual(incident.siteId, String(site.id));

  // It is a number in the SI-year-sequence form, quoted with the Site's own
  // code (the Platform's `next_document_number`).
  assert.match(incident.incidentNo, /^SI-[A-Z0-9]+-\d{4}-\d{5}$/);
  assert.ok(
    incident.incidentNo.startsWith(`SI-${site.code}-`),
    `the number should quote ${site.code}: ${incident.incidentNo}`
  );

  // And anyone who can see the Site finds it in the register and opens it.
  const reader = await insertAccount({ grants: [{ orgUnitId: unit.id, write: false }] });
  const listed = await listIncidents(reader.token, site.id);
  assert.strictEqual(listed.status, 200);
  assert.deepStrictEqual(
    listed.body.incidents.map((row) => row.id),
    [incident.id]
  );

  const detail = await readIncident(reader.token, incident.id);
  assert.strictEqual(detail.status, 200);
  assert.deepStrictEqual(detail.body.incident, incident);
});

test('recording is refused with 403 for an Account whose Grant does not reach the Org Unit', async () => {
  const { site, unit } = await makeGround({});
  const sibling = await insertOrgUnit(site.id, { name: 'Line beside it' });
  const neighbour = await insertAccount({ grants: [{ orgUnitId: sibling.id }] });
  const reader = await insertAccount({ grants: [{ orgUnitId: unit.id, write: false }] });
  const stranger = await insertAccount({});

  const request = {
    orgUnitId: unit.id,
    occurredAt: '2026-04-10T08:00:00Z',
    incidentType: 'near_miss',
    severityLevel: 'near_miss',
    description: 'A pallet nearly fell from a rack.'
  };

  for (const token of [neighbour.token, reader.token, stranger.token]) {
    const { status, body } = await record(token, site.id, request);
    assert.strictEqual(status, 403, JSON.stringify(body));
    assert.strictEqual(body.message, 'Outside the caller\'s granted Org Units');
  }

  const { body } = await listIncidents(adminToken, site.id);
  assert.deepStrictEqual(body.incidents, []);
});

test('an administrator records a Safety incident in a Site they hold no Grant in', async () => {
  const { site, unit } = await makeGround({});

  const { status, body } = await record(adminToken, site.id, {
    orgUnitId: unit.id,
    occurredAt: '2026-04-10T08:00:00Z',
    incidentType: 'fire',
    severityLevel: 'near_miss',
    description: 'A rag caught fire near a welding station and was put out immediately.'
  });

  assert.strictEqual(status, 201, JSON.stringify(body));
  assert.strictEqual(body.incident.status, 'open');
  // Incident type and severity are independent: a fire that hurt nobody sits
  // on the no-injury rung, exactly where a genuine near miss also sits.
  assert.strictEqual(body.incident.incidentType, 'fire');
  assert.strictEqual(body.incident.severityLevel, 'near_miss');
});

test('an unknown Site or an Org Unit of another Site is a 404 before any Grant is asked about', async () => {
  const { unit } = await makeGround({});
  const otherSite = await insertSite({ name: 'Another plant' });

  const unknownSite = await record(adminToken, 999999999, {
    orgUnitId: unit.id,
    occurredAt: '2026-04-10T08:00:00Z',
    incidentType: 'injury',
    severityLevel: 'first_aid',
    description: 'x'
  });
  assert.strictEqual(unknownSite.status, 404);
  assert.strictEqual(unknownSite.body.message, 'Site not found');

  const crossSite = await record(adminToken, otherSite.id, {
    orgUnitId: unit.id,
    occurredAt: '2026-04-10T08:00:00Z',
    incidentType: 'injury',
    severityLevel: 'first_aid',
    description: 'x'
  });
  assert.strictEqual(crossSite.status, 404);
  assert.strictEqual(crossSite.body.message, 'Org Unit not found');

  const malformed = await record(adminToken, otherSite.id, {
    orgUnitId: 'not-an-id',
    occurredAt: '2026-04-10T08:00:00Z',
    incidentType: 'injury',
    severityLevel: 'first_aid',
    description: 'x'
  });
  assert.strictEqual(malformed.status, 400);
  assert.strictEqual(malformed.body.message, 'orgUnitId must be a valid Org Unit id');
});

// ---------------------------------------------------------------------------
// 2. Required fields and known sets
// ---------------------------------------------------------------------------

test('occurredAt, incident type, severity level and description are required', async () => {
  const { site, unit, recorder } = await makeGround({});
  const complete = {
    orgUnitId: unit.id,
    occurredAt: '2026-04-10T08:00:00Z',
    incidentType: 'injury',
    severityLevel: 'first_aid',
    description: 'A pinch point caught a glove.'
  };

  const missingOccurredAt = await record(recorder.token, site.id, {
    ...complete,
    occurredAt: undefined
  });
  assert.strictEqual(missingOccurredAt.status, 400);
  assert.match(missingOccurredAt.body.message, /occurredAt/);

  const badOccurredAt = await record(recorder.token, site.id, {
    ...complete,
    occurredAt: 'not-a-date'
  });
  assert.strictEqual(badOccurredAt.status, 400);
  assert.match(badOccurredAt.body.message, /occurredAt/);

  const missingType = await record(recorder.token, site.id, {
    ...complete,
    incidentType: undefined
  });
  assert.strictEqual(missingType.status, 400);
  assert.match(missingType.body.message, /incidentType/);

  const badType = await record(recorder.token, site.id, {
    ...complete,
    incidentType: 'sabotage'
  });
  assert.strictEqual(badType.status, 400);
  assert.match(badType.body.message, /incidentType/);

  const missingSeverity = await record(recorder.token, site.id, {
    ...complete,
    severityLevel: undefined
  });
  assert.strictEqual(missingSeverity.status, 400);
  assert.match(missingSeverity.body.message, /severityLevel/);

  const badSeverity = await record(recorder.token, site.id, {
    ...complete,
    severityLevel: 'catastrophic'
  });
  assert.strictEqual(badSeverity.status, 400);
  assert.match(badSeverity.body.message, /severityLevel/);

  const missingDescription = await record(recorder.token, site.id, {
    ...complete,
    description: undefined
  });
  assert.strictEqual(missingDescription.status, 400);
  assert.match(missingDescription.body.message, /description/);

  const blankDescription = await record(recorder.token, site.id, {
    ...complete,
    description: '   '
  });
  assert.strictEqual(blankDescription.status, 400);
  assert.match(blankDescription.body.message, /description/);

  const ok = await record(recorder.token, site.id, complete);
  assert.strictEqual(ok.status, 201, JSON.stringify(ok.body));
});

// ---------------------------------------------------------------------------
// 3. The Asset and the Employee involved
// ---------------------------------------------------------------------------

test('an Asset named on the incident must sit at the Org Unit or beneath it', async () => {
  const { site, unit, recorder, asset } = await makeGround({ withAsset: true });
  const sibling = await insertOrgUnit(site.id, { name: 'Elsewhere' });
  const elsewhereAsset = await insertAsset(sibling.id, { name: 'Elsewhere Asset' });
  const child = await insertOrgUnit(site.id, { parentId: unit.id, name: 'Press Line Cell' });
  const childAsset = await insertAsset(child.id, { name: 'Child Asset' });

  const base = {
    orgUnitId: unit.id,
    occurredAt: '2026-04-10T08:00:00Z',
    incidentType: 'injury',
    severityLevel: 'first_aid',
    description: 'Caught a hand at the press.'
  };

  const atUnit = await record(recorder.token, site.id, { ...base, assetId: asset.id });
  assert.strictEqual(atUnit.status, 201, JSON.stringify(atUnit.body));
  assert.strictEqual(atUnit.body.incident.assetId, asset.id);

  const beneathUnit = await record(recorder.token, site.id, { ...base, assetId: childAsset.id });
  assert.strictEqual(beneathUnit.status, 201, JSON.stringify(beneathUnit.body));
  assert.strictEqual(beneathUnit.body.incident.assetId, childAsset.id);

  const elsewhere = await record(recorder.token, site.id, { ...base, assetId: elsewhereAsset.id });
  assert.strictEqual(elsewhere.status, 400);
  assert.match(elsewhere.body.message, /Asset/);

  const unknownAsset = await record(recorder.token, site.id, { ...base, assetId: 999999999 });
  assert.strictEqual(unknownAsset.status, 404);
  assert.strictEqual(unknownAsset.body.message, 'Asset not found');
});

test('the Employee involved is optional, and must exist when named', async () => {
  const { site, unit, recorder } = await makeGround({});
  const employee = await insertEmployee();

  const base = {
    orgUnitId: unit.id,
    occurredAt: '2026-04-10T08:00:00Z',
    incidentType: 'injury',
    severityLevel: 'medical_treatment',
    description: 'Struck by a falling tool.'
  };

  const withEmployee = await record(recorder.token, site.id, { ...base, employeeId: employee.id });
  assert.strictEqual(withEmployee.status, 201, JSON.stringify(withEmployee.body));
  assert.strictEqual(withEmployee.body.incident.employeeId, employee.id);
  assert.strictEqual(withEmployee.body.incident.employeeName, employee.display_name);

  const unknownEmployee = await record(recorder.token, site.id, { ...base, employeeId: 999999999 });
  assert.strictEqual(unknownEmployee.status, 404);
  assert.strictEqual(unknownEmployee.body.message, 'Employee not found');

  const noEmployee = await record(recorder.token, site.id, base);
  assert.strictEqual(noEmployee.status, 201, JSON.stringify(noEmployee.body));
  assert.strictEqual(noEmployee.body.incident.employeeId, null);
});

// ---------------------------------------------------------------------------
// 4. Recordability, derived and never accepted from the caller
// ---------------------------------------------------------------------------

test('recordability is derived from the severity level, exactly where the rung crosses the recordable line', async () => {
  const { site, unit, recorder } = await makeGround({});
  const base = {
    orgUnitId: unit.id,
    occurredAt: '2026-04-10T08:00:00Z',
    incidentType: 'injury',
    description: 'A recordability probe.'
  };

  const expectations = {
    near_miss: false,
    first_aid: false,
    medical_treatment: true,
    restricted_work: true,
    lost_time: true,
    fatality: true
  };

  for (const [severityLevel, expected] of Object.entries(expectations)) {
    const lostTimeDays = severityLevel === 'lost_time' || severityLevel === 'fatality' ? 1 : 0;
    const { status, body } = await record(recorder.token, site.id, {
      ...base,
      severityLevel,
      lostTimeDays
    });
    assert.strictEqual(status, 201, JSON.stringify(body));
    assert.strictEqual(
      body.incident.isRecordable,
      expected,
      `${severityLevel} should be recordable=${expected}`
    );
  }
});

test('recordability cannot be set by the caller; it is always the derived value', async () => {
  const { site, unit, recorder } = await makeGround({});

  const { status, body } = await record(recorder.token, site.id, {
    orgUnitId: unit.id,
    occurredAt: '2026-04-10T08:00:00Z',
    incidentType: 'near_miss',
    severityLevel: 'near_miss',
    description: 'Claiming recordable on a near miss.',
    isRecordable: true
  });

  assert.strictEqual(status, 201, JSON.stringify(body));
  assert.strictEqual(body.incident.isRecordable, false);
});

// ---------------------------------------------------------------------------
// 5. Ladder consistency, checked before the database sees it
// ---------------------------------------------------------------------------

test('lost-time and restricted days are refused with a 400 on the no-injury rung', async () => {
  const { site, unit, recorder } = await makeGround({});
  const base = {
    orgUnitId: unit.id,
    occurredAt: '2026-04-10T08:00:00Z',
    incidentType: 'near_miss',
    severityLevel: 'near_miss',
    description: 'Nobody was hurt.'
  };

  const withLostTime = await record(recorder.token, site.id, { ...base, lostTimeDays: 1 });
  assert.strictEqual(withLostTime.status, 400);
  assert.match(withLostTime.body.message, /lostTimeDays/);

  const withRestricted = await record(recorder.token, site.id, { ...base, restrictedDays: 2 });
  assert.strictEqual(withRestricted.status, 400);
  assert.match(withRestricted.body.message, /restrictedDays/);
});

test('lost-time days are refused with a 400 below the lost_time rung', async () => {
  const { site, unit, recorder } = await makeGround({});

  for (const severityLevel of ['first_aid', 'medical_treatment', 'restricted_work']) {
    const { status, body } = await record(recorder.token, site.id, {
      orgUnitId: unit.id,
      occurredAt: '2026-04-10T08:00:00Z',
      incidentType: 'injury',
      severityLevel,
      description: 'Below the lost-time rung.',
      lostTimeDays: 1
    });
    assert.strictEqual(status, 400, `${severityLevel}: ${JSON.stringify(body)}`);
    assert.match(body.message, /lostTimeDays/);
  }

  const okAtLostTime = await record(recorder.token, site.id, {
    orgUnitId: unit.id,
    occurredAt: '2026-04-10T08:00:00Z',
    incidentType: 'injury',
    severityLevel: 'lost_time',
    description: 'At the lost-time rung.',
    lostTimeDays: 3
  });
  assert.strictEqual(okAtLostTime.status, 201, JSON.stringify(okAtLostTime.body));
  assert.strictEqual(okAtLostTime.body.incident.lostTimeDays, 3);

  const okAtFatality = await record(recorder.token, site.id, {
    orgUnitId: unit.id,
    occurredAt: '2026-04-10T08:00:00Z',
    incidentType: 'injury',
    severityLevel: 'fatality',
    description: 'At the fatality rung.',
    lostTimeDays: 5
  });
  assert.strictEqual(okAtFatality.status, 201, JSON.stringify(okAtFatality.body));
});

test('reportedAt cannot be earlier than occurredAt', async () => {
  const { site, unit, recorder } = await makeGround({});

  const { status, body } = await record(recorder.token, site.id, {
    orgUnitId: unit.id,
    occurredAt: '2026-04-10T08:00:00Z',
    reportedAt: '2026-04-09T08:00:00Z',
    incidentType: 'injury',
    severityLevel: 'first_aid',
    description: 'Reported before it happened.'
  });

  assert.strictEqual(status, 400);
  assert.match(body.message, /reportedAt/);
});

test('reportedAt at or after occurredAt is accepted, and defaults to now when absent', async () => {
  const { site, unit, recorder } = await makeGround({});

  const { status, body } = await record(recorder.token, site.id, {
    orgUnitId: unit.id,
    occurredAt: '2026-04-10T08:00:00Z',
    reportedAt: '2026-04-10T09:00:00Z',
    incidentType: 'injury',
    severityLevel: 'first_aid',
    description: 'Reported an hour later.'
  });

  assert.strictEqual(status, 201, JSON.stringify(body));
  assert.strictEqual(body.incident.reportedAt, new Date('2026-04-10T09:00:00Z').toISOString());

  const defaulted = await record(recorder.token, site.id, {
    orgUnitId: unit.id,
    occurredAt: '2026-04-10T08:00:00Z',
    incidentType: 'injury',
    severityLevel: 'first_aid',
    description: 'No reportedAt named.'
  });
  assert.strictEqual(defaulted.status, 201, JSON.stringify(defaulted.body));
  assert.ok(defaulted.body.incident.reportedAt, 'reportedAt should default to now()');
});

// ---------------------------------------------------------------------------
// 6. The number's per-Site scoping
// ---------------------------------------------------------------------------

test('the incident number is scoped per Site, not shared across Sites', async () => {
  const groundA = await makeGround({});
  const groundB = await makeGround({});

  const bodyRequest = {
    occurredAt: '2026-04-10T08:00:00Z',
    incidentType: 'near_miss',
    severityLevel: 'near_miss',
    description: 'A per-Site numbering probe.'
  };

  const first = await record(groundA.recorder.token, groundA.site.id, {
    ...bodyRequest,
    orgUnitId: groundA.unit.id
  });
  const second = await record(groundB.recorder.token, groundB.site.id, {
    ...bodyRequest,
    orgUnitId: groundB.unit.id
  });

  assert.strictEqual(first.status, 201, JSON.stringify(first.body));
  assert.strictEqual(second.status, 201, JSON.stringify(second.body));
  assert.ok(first.body.incident.incidentNo.startsWith(`SI-${groundA.site.code}-`));
  assert.ok(second.body.incident.incidentNo.startsWith(`SI-${groundB.site.code}-`));
  assert.notStrictEqual(first.body.incident.incidentNo, second.body.incident.incidentNo);

  // Recording a second incident at the same Site advances that Site's own
  // sequence rather than the other one's.
  const third = await record(groundA.recorder.token, groundA.site.id, {
    ...bodyRequest,
    orgUnitId: groundA.unit.id
  });
  assert.strictEqual(third.status, 201, JSON.stringify(third.body));
  assert.notStrictEqual(third.body.incident.incidentNo, first.body.incident.incidentNo);
  assert.ok(third.body.incident.incidentNo.startsWith(`SI-${groundA.site.code}-`));
});

// ---------------------------------------------------------------------------
// 7. Production-day filing
// ---------------------------------------------------------------------------

test('a Safety incident is filed against the production day and shift it occurred in', async () => {
  const { site, unit, recorder } = await makeGround({ withShifts: true });

  // 04:00 UTC is 11:00 local (Asia/Ho_Chi_Minh, UTC+7), within the day shift
  // that runs 06:00-14:00 local on 2026-04-15.
  const { status, body } = await record(recorder.token, site.id, {
    orgUnitId: unit.id,
    occurredAt: '2026-04-15T04:00:00Z',
    incidentType: 'injury',
    severityLevel: 'first_aid',
    description: 'Filed against a shift.'
  });

  assert.strictEqual(status, 201, JSON.stringify(body));
  assert.strictEqual(body.incident.productionDate, '2026-04-15');
  assert.ok(body.incident.shiftInstanceId, 'a shift instance should be filled in by the trigger');
  assert.ok(body.incident.shiftCode);
});

// ---------------------------------------------------------------------------
// 8. Reading: visibility and filters
// ---------------------------------------------------------------------------

test('any Account that can see the Site reads the register and a detail; a stranger cannot', async () => {
  const { site, unit, recorder } = await makeGround({});
  const recorded = await record(recorder.token, site.id, {
    orgUnitId: unit.id,
    occurredAt: '2026-04-10T08:00:00Z',
    incidentType: 'injury',
    severityLevel: 'first_aid',
    description: 'Visible to anyone who can see the Site.'
  });
  assert.strictEqual(recorded.status, 201);

  const reader = await insertAccount({ grants: [{ orgUnitId: unit.id, write: false }] });
  const listed = await listIncidents(reader.token, site.id);
  assert.strictEqual(listed.status, 200);
  assert.ok(listed.body.incidents.some((row) => row.id === recorded.body.incident.id));

  const stranger = await insertAccount({});
  const strangerList = await listIncidents(stranger.token, site.id);
  assert.strictEqual(strangerList.status, 403);

  const strangerDetail = await readIncident(stranger.token, recorded.body.incident.id);
  assert.strictEqual(strangerDetail.status, 403);

  const unknown = await readIncident(adminToken, 999999999);
  assert.strictEqual(unknown.status, 404);
  assert.strictEqual(unknown.body.message, 'Safety incident not found');
});

test('the register is filtered by Org Unit (including beneath it), status, incident type, severity level, recordability and date range', async () => {
  const site = await insertSite();
  const parent = await insertOrgUnit(site.id, { name: 'Plant floor' });
  const child = await insertOrgUnit(site.id, { parentId: parent.id, name: 'Weld cell' });
  const sibling = await insertOrgUnit(site.id, { name: 'Warehouse' });
  const recorder = await insertAccount({
    grants: [{ orgUnitId: parent.id }, { orgUnitId: sibling.id }]
  });

  const atParent = await record(recorder.token, site.id, {
    orgUnitId: parent.id,
    occurredAt: '2026-05-01T08:00:00Z',
    incidentType: 'injury',
    severityLevel: 'medical_treatment',
    description: 'At the parent Org Unit.',
    lostTimeDays: 0
  });
  const atChild = await record(recorder.token, site.id, {
    orgUnitId: child.id,
    occurredAt: '2026-05-05T08:00:00Z',
    incidentType: 'near_miss',
    severityLevel: 'near_miss',
    description: 'Beneath the parent Org Unit.'
  });
  const atSibling = await record(recorder.token, site.id, {
    orgUnitId: sibling.id,
    occurredAt: '2026-05-10T08:00:00Z',
    incidentType: 'fire',
    severityLevel: 'first_aid',
    description: 'At a sibling Org Unit.'
  });
  for (const r of [atParent, atChild, atSibling]) {
    assert.strictEqual(r.status, 201, JSON.stringify(r.body));
  }

  const byOrgUnit = await listIncidents(recorder.token, site.id, `?orgUnitId=${parent.id}`);
  assert.strictEqual(byOrgUnit.status, 200);
  assert.deepStrictEqual(
    byOrgUnit.body.incidents.map((row) => row.id).sort(),
    [atParent.body.incident.id, atChild.body.incident.id].sort()
  );

  const byStatus = await listIncidents(recorder.token, site.id, '?status=open');
  assert.strictEqual(byStatus.status, 200);
  assert.strictEqual(byStatus.body.incidents.length, 3);

  const byIncidentType = await listIncidents(recorder.token, site.id, '?incidentType=fire');
  assert.strictEqual(byIncidentType.status, 200);
  assert.deepStrictEqual(
    byIncidentType.body.incidents.map((row) => row.id),
    [atSibling.body.incident.id]
  );

  const bySeverity = await listIncidents(recorder.token, site.id, '?severityLevel=near_miss');
  assert.strictEqual(bySeverity.status, 200);
  assert.deepStrictEqual(
    bySeverity.body.incidents.map((row) => row.id),
    [atChild.body.incident.id]
  );

  const recordableOnly = await listIncidents(recorder.token, site.id, '?isRecordable=true');
  assert.strictEqual(recordableOnly.status, 200);
  assert.deepStrictEqual(
    recordableOnly.body.incidents.map((row) => row.id),
    [atParent.body.incident.id]
  );

  const byDateRange = await listIncidents(
    recorder.token,
    site.id,
    '?from=2026-05-04&to=2026-05-08'
  );
  assert.strictEqual(byDateRange.status, 200);
  assert.deepStrictEqual(
    byDateRange.body.incidents.map((row) => row.id),
    [atChild.body.incident.id]
  );

  const badStatus = await listIncidents(recorder.token, site.id, '?status=opne');
  assert.strictEqual(badStatus.status, 400);
  assert.match(badStatus.body.message, /status/);

  const badDate = await listIncidents(recorder.token, site.id, '?from=05-04-2026');
  assert.strictEqual(badDate.status, 400);
  assert.match(badDate.body.message, /from/);
});
