/*
 * Safety incidents over HTTP (issue #226), against a real database and a real
 * (locally issued) JWKS — the same seam nonconformances.test.js uses, and
 * this file's own scaffolding mirrors it closely: a Safety incident is the
 * same shape of record as a Non-conformance (recorded at an Org Unit,
 * Site-scoped number, production-day filing, a filtered register, a detail).
 *
 * This file builds its own Sites, Org Units, Assets, Employees, Injury types
 * and Body parts directly against the database, and everything it inserts is
 * deleted again in `test.after()`, in dependency order.
 *
 * **Issue #224's own section is section 9**, and it is the reason this file's
 * `insertAccount` grew an `employeeId` option: ADR-0037 restricts three fields
 * on an incident — the identified Employee, the Injury type and the Body part
 * — to a holder of Safety authority reaching the Org Unit and to the Account
 * whose own `app_users.employee_id` IS the injured Employee, and asserting the
 * second half needs an Account genuinely linked to an Employee. Those tests
 * assert on keys being **absent** from the JSON rather than null, which is the
 * distinction ADR-0037 turns on, so they use `Object.prototype.hasOwnProperty`
 * rather than comparing against undefined — a missing key and a key set to
 * undefined read the same through `===` and do not survive JSON.
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
// Concerns raised through the Action log's own API (issue #228's own "closes
// despite an open Concern" proof) — `action_items.org_unit_id` has no ON
// DELETE CASCADE, so these are cleaned up explicitly, the same way every
// other integration file that raises one does (capas.test.js,
// concern-nonconformances.test.js, and the rest).
const insertedActionIds = [];
// The two catalogues issue #224 classifies against. Both are shared by every
// Site (ADR-0005) and arrive seeded from the baseline, so this file creates its
// own rows with unique codes and removes exactly those — never truncating a
// table the baseline filled.
const insertedInjuryTypeIds = [];
const insertedBodyPartIds = [];

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

// An Account, optionally holding Grants. `grants` are `{ orgUnitId, write,
// safety }` pairs; `write` defaults to true, since most of this file's
// Accounts are recording rather than reading. `safety` (issue #228, ADR-0039)
// defaults to false — most Accounts in this file hold no Safety authority,
// and the tests that need it say so explicitly.
//
// `employeeId` links the Account to an Employee the way Approval does
// (ADR-0022): `app_users.employee_id` is UNIQUE, which is what makes "the
// injured person's own Account" a real identity rather than a guess, and what
// issue #224's read restriction turns on.
async function insertAccount({ role = 'operator', grants = [], employeeId = null } = {}) {
  const subject = uniqueCode('siacct');
  const { rows: [account] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active,
                            approval_status, employee_id)
     VALUES ($1, 'Safety Test Account', $2, $3, TRUE, 'approved', $4) RETURNING id`,
    [`${subject}@example.com`, role, subject, employeeId]
  );
  insertedAccountIds.push(account.id);

  for (const grant of grants) {
    await pool.query(
      `INSERT INTO app_user_org_units (app_user_id, org_unit_id, can_write, safety_authority)
       VALUES ($1, $2, $3, $4)`,
      [account.id, grant.orgUnitId, grant.write ?? true, grant.safety ?? false]
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

async function insertInjuryType({ name = 'Fracture', isActive = true } = {}) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO injury_types (code, name, is_active) VALUES ($1, $2, $3)
     RETURNING id, code, name`,
    [uniqueCode('SIIT'), name, isActive]
  );
  insertedInjuryTypeIds.push(row.id);
  return row;
}

async function insertBodyPart({ name = 'Left hand', region = 'upper_limb' } = {}) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO body_parts (code, name, region) VALUES ($1, $2, $3)
     RETURNING id, code, name, region`,
    [uniqueCode('SIBP'), name, region]
  );
  insertedBodyPartIds.push(row.id);
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

async function overdueIncidents(token, siteId, query = '') {
  const response = await fetch(`${base}/api/safety/sites/${siteId}/incidents/overdue${query}`, {
    headers: token
  });
  return json(response);
}

async function setDueDate(token, id, body) {
  const response = await fetch(`${base}/api/safety/incidents/${id}/investigation-due-date`, {
    method: 'PATCH',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  return json(response);
}

async function moveStatus(token, id, body) {
  const response = await fetch(`${base}/api/safety/incidents/${id}/status`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  return json(response);
}

async function changeSeverity(token, id, body) {
  const response = await fetch(`${base}/api/safety/incidents/${id}/severity`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  return json(response);
}

async function recordDays(token, id, body) {
  const response = await fetch(`${base}/api/safety/incidents/${id}/days`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  return json(response);
}

async function closeIncident(token, id, body) {
  const response = await fetch(`${base}/api/safety/incidents/${id}/close`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  return json(response);
}

async function classify(token, id, body) {
  const response = await fetch(`${base}/api/safety/incidents/${id}/classify`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  return json(response);
}

// Raises an ordinary Concern at an Org Unit through the Action log's own API
// (issue #229 has not built the safety-incident-specific link yet, so this is
// the only way to construct "a Concern is open" at all). `token`'s Account
// need only see the Site — `canSeeSite`, not a write Grant — the same rule
// `action-routes.js`'s own POST /sites/:siteId/actions applies to a Concern.
async function raiseConcern(token, siteId, body) {
  const response = await fetch(`${base}/api/actions/sites/${siteId}/actions`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  const result = await json(response);
  if (result.status === 201) insertedActionIds.push(result.body.action.id);
  return result;
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
  // Concerns raised through the Action log (issue #228's open-Concern proof)
  // — `action_items.org_unit_id` has no ON DELETE CASCADE, so these must go
  // before the Org Units they were raised at.
  await pool.query('DELETE FROM action_items WHERE id = ANY($1)', [insertedActionIds]);
  await pool.query('DELETE FROM assets WHERE id = ANY($1)', [insertedAssetIds]);
  // After the incidents that reference them: a classified incident holds a
  // foreign key into each catalogue (issue #224).
  await pool.query('DELETE FROM injury_types WHERE id = ANY($1)', [insertedInjuryTypeIds]);
  await pool.query('DELETE FROM body_parts WHERE id = ANY($1)', [insertedBodyPartIds]);
  await pool.query('DELETE FROM shift_instances WHERE id = ANY($1)', [insertedShiftInstanceIds]);
  await pool.query('DELETE FROM shift_definitions WHERE id = ANY($1)', [
    insertedShiftDefinitionIds
  ]);
  await pool.query('DELETE FROM app_user_org_units WHERE app_user_id = ANY($1)', [
    insertedAccountIds
  ]);
  // Accounts before Employees, not after: issue #224's own "the injured
  // person's own Account" tests link one to the other through
  // `app_users.employee_id`, so an Employee deleted first would be a foreign
  // key violation rather than a clean teardown.
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

// Issue #224 moved this: naming the Employee involved is part of the injury
// classification, so it now needs Safety authority reaching the Org Unit
// rather than the write Grant recording itself needs, and it is read back only
// by a caller ADR-0037 allows. The recorder here therefore holds Safety
// authority, which is also what lets it read its own answer.
test('the Employee involved is optional, and must exist when named', async () => {
  const site = await insertSite();
  const unit = await insertOrgUnit(site.id, { name: 'Press Line' });
  const recorder = await insertAccount({ grants: [{ orgUnitId: unit.id, safety: true }] });
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

// ---------------------------------------------------------------------------
// 9. The investigation due date (issue #228)
// ---------------------------------------------------------------------------

async function recordedIncident(recorder, site, unit, overrides = {}) {
  const { status, body } = await record(recorder.token, site.id, {
    orgUnitId: unit.id,
    occurredAt: '2026-04-10T08:00:00Z',
    incidentType: 'injury',
    severityLevel: 'first_aid',
    description: 'An incident recorded for issue #228.',
    ...overrides
  });
  assert.strictEqual(status, 201, JSON.stringify(body));
  return body.incident;
}

test('an edit Grant sets and then changes the investigation due date', async () => {
  const { site, unit, recorder } = await makeGround({});
  const incident = await recordedIncident(recorder, site, unit);

  const first = await setDueDate(recorder.token, incident.id, {
    investigationDueAt: '2026-04-20T00:00:00Z'
  });
  assert.strictEqual(first.status, 200, JSON.stringify(first.body));
  assert.strictEqual(
    first.body.incident.investigationDueAt,
    new Date('2026-04-20T00:00:00Z').toISOString()
  );

  const changed = await setDueDate(recorder.token, incident.id, {
    investigationDueAt: '2026-05-01T00:00:00Z'
  });
  assert.strictEqual(changed.status, 200, JSON.stringify(changed.body));
  assert.strictEqual(
    changed.body.incident.investigationDueAt,
    new Date('2026-05-01T00:00:00Z').toISOString()
  );

  const cleared = await setDueDate(recorder.token, incident.id, { investigationDueAt: null });
  assert.strictEqual(cleared.status, 200, JSON.stringify(cleared.body));
  assert.strictEqual(cleared.body.incident.investigationDueAt, null);
});

test('setting the due date is refused with a 403 for an Account whose Grant does not reach the Org Unit', async () => {
  const { site, unit, recorder } = await makeGround({});
  const incident = await recordedIncident(recorder, site, unit);
  const stranger = await insertAccount({});

  const { status, body } = await setDueDate(stranger.token, incident.id, {
    investigationDueAt: '2026-04-20T00:00:00Z'
  });
  assert.strictEqual(status, 403, JSON.stringify(body));
});

test('the due date can still be set while investigating, but not once the incident is closed', async () => {
  const { site, unit, recorder } = await makeGround({});
  const safetyHolder = await insertAccount({ grants: [{ orgUnitId: unit.id, safety: true }] });
  const incident = await recordedIncident(recorder, site, unit);

  const moved = await moveStatus(recorder.token, incident.id, { status: 'investigating' });
  assert.strictEqual(moved.status, 200, JSON.stringify(moved.body));

  const whileInvestigating = await setDueDate(recorder.token, incident.id, {
    investigationDueAt: '2026-04-25T00:00:00Z'
  });
  assert.strictEqual(whileInvestigating.status, 200, JSON.stringify(whileInvestigating.body));

  // Above the no-injury rung, so the days have to be settled before it can
  // close at all — zero is the answer here, and saying it is what settles it.
  const settled = await recordDays(safetyHolder.token, incident.id, {
    lostTimeDays: 0,
    restrictedDays: 0
  });
  assert.strictEqual(settled.status, 200, JSON.stringify(settled.body));

  const closed = await closeIncident(safetyHolder.token, incident.id, { note: 'Dealt with.' });
  assert.strictEqual(closed.status, 200, JSON.stringify(closed.body));

  const afterClose = await setDueDate(recorder.token, incident.id, {
    investigationDueAt: '2026-05-01T00:00:00Z'
  });
  assert.strictEqual(afterClose.status, 409, JSON.stringify(afterClose.body));
});

// ---------------------------------------------------------------------------
// 10. The status ladder (issue #228)
// ---------------------------------------------------------------------------

test('an incident moves open -> investigating -> actions_pending with an edit Grant', async () => {
  const { site, unit, recorder } = await makeGround({});
  const incident = await recordedIncident(recorder, site, unit);

  const toInvestigating = await moveStatus(recorder.token, incident.id, {
    status: 'investigating'
  });
  assert.strictEqual(toInvestigating.status, 200, JSON.stringify(toInvestigating.body));
  assert.strictEqual(toInvestigating.body.incident.status, 'investigating');

  const toActionsPending = await moveStatus(recorder.token, incident.id, {
    status: 'actions_pending'
  });
  assert.strictEqual(toActionsPending.status, 200, JSON.stringify(toActionsPending.body));
  assert.strictEqual(toActionsPending.body.incident.status, 'actions_pending');
});

test('a move that is not on the ladder is refused with a 409', async () => {
  const { site, unit, recorder } = await makeGround({});
  const skipAhead = await recordedIncident(recorder, site, unit);

  // open -> actions_pending skips investigating, which is not on the ladder.
  const skipped = await moveStatus(recorder.token, skipAhead.id, { status: 'actions_pending' });
  assert.strictEqual(skipped.status, 409, JSON.stringify(skipped.body));

  // investigating -> investigating (sideways) and actions_pending ->
  // investigating (backwards) are both refused too.
  const investigating = await recordedIncident(recorder, site, unit);
  const first = await moveStatus(recorder.token, investigating.id, { status: 'investigating' });
  assert.strictEqual(first.status, 200, JSON.stringify(first.body));

  const sideways = await moveStatus(recorder.token, investigating.id, {
    status: 'investigating'
  });
  assert.strictEqual(sideways.status, 409, JSON.stringify(sideways.body));

  const second = await moveStatus(recorder.token, investigating.id, {
    status: 'actions_pending'
  });
  assert.strictEqual(second.status, 200, JSON.stringify(second.body));

  const backwards = await moveStatus(recorder.token, investigating.id, {
    status: 'investigating'
  });
  assert.strictEqual(backwards.status, 409, JSON.stringify(backwards.body));

  // `closed` is never a valid target for the ordinary move — only the
  // dedicated close address reaches it.
  const viaMove = await moveStatus(recorder.token, second.body.incident.id, {
    status: 'closed'
  });
  assert.strictEqual(viaMove.status, 400, JSON.stringify(viaMove.body));
});

test('closing does not require having passed through investigating', async () => {
  const { site, unit, recorder } = await makeGround({});
  const safetyHolder = await insertAccount({ grants: [{ orgUnitId: unit.id, safety: true }] });
  const incident = await recordedIncident(recorder, site, unit, {
    incidentType: 'near_miss',
    severityLevel: 'near_miss',
    description: 'A no-injury event that needed no investigation.'
  });

  assert.strictEqual(incident.status, 'open');

  const closed = await closeIncident(safetyHolder.token, incident.id, {
    note: 'Nothing to investigate; closing directly from open.'
  });
  assert.strictEqual(closed.status, 200, JSON.stringify(closed.body));
  assert.strictEqual(closed.body.incident.status, 'closed');
});

test('moving status is refused with a 403 for an Account whose Grant does not reach the Org Unit', async () => {
  const { site, unit, recorder } = await makeGround({});
  const incident = await recordedIncident(recorder, site, unit);
  const stranger = await insertAccount({});

  const { status, body } = await moveStatus(stranger.token, incident.id, {
    status: 'investigating'
  });
  assert.strictEqual(status, 403, JSON.stringify(body));
});

// ---------------------------------------------------------------------------
// 11. Recording the days the injury cost (issue #228)
// ---------------------------------------------------------------------------

test('recording lost-time and restricted days requires Safety authority', async () => {
  const { site, unit, recorder } = await makeGround({});
  const incident = await recordedIncident(recorder, site, unit, { severityLevel: 'lost_time' });

  const refused = await recordDays(recorder.token, incident.id, {
    lostTimeDays: 3,
    restrictedDays: 0
  });
  assert.strictEqual(refused.status, 403, JSON.stringify(refused.body));

  const safetyHolder = await insertAccount({ grants: [{ orgUnitId: unit.id, safety: true }] });
  const allowed = await recordDays(safetyHolder.token, incident.id, {
    lostTimeDays: 3,
    restrictedDays: 0
  });
  assert.strictEqual(allowed.status, 200, JSON.stringify(allowed.body));
  assert.strictEqual(allowed.body.incident.lostTimeDays, 3);
  assert.strictEqual(allowed.body.incident.restrictedDays, 0);
});

test('ladder consistency still holds when recording days: none on the no-injury rung, lost-time only at lost_time or fatality', async () => {
  const { site, unit, recorder } = await makeGround({});
  const safetyHolder = await insertAccount({ grants: [{ orgUnitId: unit.id, safety: true }] });

  const nearMiss = await recordedIncident(recorder, site, unit, {
    incidentType: 'near_miss',
    severityLevel: 'near_miss'
  });
  const onNearMiss = await recordDays(safetyHolder.token, nearMiss.id, {
    lostTimeDays: 1,
    restrictedDays: 0
  });
  assert.strictEqual(onNearMiss.status, 400, JSON.stringify(onNearMiss.body));
  assert.match(onNearMiss.body.message, /lostTimeDays/);

  const firstAid = await recordedIncident(recorder, site, unit, { severityLevel: 'first_aid' });
  const belowLostTime = await recordDays(safetyHolder.token, firstAid.id, {
    lostTimeDays: 2,
    restrictedDays: 0
  });
  assert.strictEqual(belowLostTime.status, 400, JSON.stringify(belowLostTime.body));
  assert.match(belowLostTime.body.message, /lostTimeDays/);

  const missingFields = await recordDays(safetyHolder.token, firstAid.id, {});
  assert.strictEqual(missingFields.status, 400, JSON.stringify(missingFields.body));
});

// ---------------------------------------------------------------------------
// 12. Correcting the severity level (issue #228, #223 decision 5)
// ---------------------------------------------------------------------------

test('changing the severity level requires Safety authority and a note', async () => {
  const { site, unit, recorder } = await makeGround({});
  const safetyHolder = await insertAccount({ grants: [{ orgUnitId: unit.id, safety: true }] });
  const incident = await recordedIncident(recorder, site, unit, { severityLevel: 'first_aid' });

  const withoutAuthority = await changeSeverity(recorder.token, incident.id, {
    severityLevel: 'lost_time',
    note: 'Turned out to be worse.'
  });
  assert.strictEqual(withoutAuthority.status, 403, JSON.stringify(withoutAuthority.body));

  const withoutNote = await changeSeverity(safetyHolder.token, incident.id, {
    severityLevel: 'lost_time'
  });
  assert.strictEqual(withoutNote.status, 400, JSON.stringify(withoutNote.body));

  const corrected = await changeSeverity(safetyHolder.token, incident.id, {
    severityLevel: 'lost_time',
    note: 'Follow-up with occupational health confirmed lost time.'
  });
  assert.strictEqual(corrected.status, 200, JSON.stringify(corrected.body));
  assert.strictEqual(corrected.body.incident.severityLevel, 'lost_time');
});

test('a severity correction is accepted even on a closed incident, because it restates the period it occurred in', async () => {
  const { site, unit, recorder } = await makeGround({});
  const safetyHolder = await insertAccount({ grants: [{ orgUnitId: unit.id, safety: true }] });
  const incident = await recordedIncident(recorder, site, unit, {
    incidentType: 'near_miss',
    severityLevel: 'near_miss'
  });

  const closed = await closeIncident(safetyHolder.token, incident.id, {
    note: 'Closed as a near miss.'
  });
  assert.strictEqual(closed.status, 200, JSON.stringify(closed.body));

  const corrected = await changeSeverity(safetyHolder.token, incident.id, {
    severityLevel: 'first_aid',
    note: 'A scrape was found after the fact; not a true near miss.'
  });
  assert.strictEqual(corrected.status, 200, JSON.stringify(corrected.body));
  assert.strictEqual(corrected.body.incident.severityLevel, 'first_aid');
  assert.strictEqual(corrected.body.incident.status, 'closed');
});

// ---------------------------------------------------------------------------
// 13. Closing (issue #228, #223 decision 4)
// ---------------------------------------------------------------------------

test('closing requires Safety authority, a note, and (above the no-injury rung) the days settled', async () => {
  const { site, unit, recorder } = await makeGround({});
  const safetyHolder = await insertAccount({ grants: [{ orgUnitId: unit.id, safety: true }] });
  const incident = await recordedIncident(recorder, site, unit, { severityLevel: 'medical_treatment' });

  const withoutAuthority = await closeIncident(recorder.token, incident.id, {
    note: 'Dealt with.'
  });
  assert.strictEqual(withoutAuthority.status, 403, JSON.stringify(withoutAuthority.body));

  const withoutNote = await closeIncident(safetyHolder.token, incident.id, {});
  assert.strictEqual(withoutNote.status, 400, JSON.stringify(withoutNote.body));

  const daysNotSettled = await closeIncident(safetyHolder.token, incident.id, {
    note: 'Ready to close.'
  });
  assert.strictEqual(daysNotSettled.status, 409, JSON.stringify(daysNotSettled.body));

  const settled = await recordDays(safetyHolder.token, incident.id, {
    lostTimeDays: 0,
    restrictedDays: 0
  });
  assert.strictEqual(settled.status, 200, JSON.stringify(settled.body));

  const closed = await closeIncident(safetyHolder.token, incident.id, {
    note: 'Days settled at zero; closing.'
  });
  assert.strictEqual(closed.status, 200, JSON.stringify(closed.body));
  assert.strictEqual(closed.body.incident.status, 'closed');
  assert.ok(closed.body.incident.closedAt, 'closing should set the closed time');
});

test('a no-injury incident closes without the days ever being recorded', async () => {
  const { site, unit, recorder } = await makeGround({});
  const safetyHolder = await insertAccount({ grants: [{ orgUnitId: unit.id, safety: true }] });
  const incident = await recordedIncident(recorder, site, unit, {
    incidentType: 'near_miss',
    severityLevel: 'near_miss'
  });

  const closed = await closeIncident(safetyHolder.token, incident.id, {
    note: 'Nobody was hurt; closing.'
  });
  assert.strictEqual(closed.status, 200, JSON.stringify(closed.body));
  assert.strictEqual(closed.body.incident.status, 'closed');
});

test('an already-closed incident cannot be closed again', async () => {
  const { site, unit, recorder } = await makeGround({});
  const safetyHolder = await insertAccount({ grants: [{ orgUnitId: unit.id, safety: true }] });
  const incident = await recordedIncident(recorder, site, unit, {
    incidentType: 'near_miss',
    severityLevel: 'near_miss'
  });

  const closed = await closeIncident(safetyHolder.token, incident.id, { note: 'Closing.' });
  assert.strictEqual(closed.status, 200, JSON.stringify(closed.body));

  const closedAgain = await closeIncident(safetyHolder.token, incident.id, {
    note: 'Closing again.'
  });
  assert.strictEqual(closedAgain.status, 409, JSON.stringify(closedAgain.body));
});

// This is the test #228 explicitly asks for: closing an incident is never
// refused because a Concern raised from it is open (#223 decision 4, the
// same shape #200 settled for a Non-conformance and its own Concern). #229 is
// what will actually link a Concern to a Safety incident; until then, an
// ordinary Concern raised at the incident's own Org Unit through the Action
// log's existing API is the only way to construct "a Concern is open" to
// prove closing does not wait on it.
test('closing a Safety incident succeeds even while an ordinary Concern raised at its Org Unit is still open', async () => {
  const { site, unit, recorder } = await makeGround({});
  const safetyHolder = await insertAccount({ grants: [{ orgUnitId: unit.id, safety: true }] });
  const incident = await recordedIncident(recorder, site, unit, { severityLevel: 'first_aid' });

  const concern = await raiseConcern(recorder.token, site.id, {
    orgUnitId: unit.id,
    title: 'Investigate the cause of this Safety incident',
    description: 'Raised while the incident itself is still open.'
  });
  assert.strictEqual(concern.status, 201, JSON.stringify(concern.body));
  assert.notStrictEqual(concern.body.action.status, 'closed');

  const settled = await recordDays(safetyHolder.token, incident.id, {
    lostTimeDays: 0,
    restrictedDays: 0
  });
  assert.strictEqual(settled.status, 200, JSON.stringify(settled.body));

  const closed = await closeIncident(safetyHolder.token, incident.id, {
    note: 'The incident itself is dealt with; the Concern keeps working the cause.'
  });
  assert.strictEqual(closed.status, 200, JSON.stringify(closed.body));
  assert.strictEqual(closed.body.incident.status, 'closed');

  // The Concern is still open — closing the incident touched nothing about it.
  const stillOpenConcern = await (async () => {
    const response = await fetch(`${base}/api/actions/${concern.body.action.id}`, {
      headers: safetyHolder.token
    });
    return json(response);
  })();
  assert.strictEqual(stillOpenConcern.status, 200, JSON.stringify(stillOpenConcern.body));
  assert.notStrictEqual(stillOpenConcern.body.action.status, 'closed');
});

// ---------------------------------------------------------------------------
// 14. The event history: kept with who and when, read back with the incident
// ---------------------------------------------------------------------------

test('every severity change, status move, days change and closure is kept in the history, and reads back over HTTP with the incident', async () => {
  const { site, unit, recorder } = await makeGround({});
  const safetyHolder = await insertAccount({ grants: [{ orgUnitId: unit.id, safety: true }] });
  const incident = await recordedIncident(recorder, site, unit, { severityLevel: 'first_aid' });

  // A freshly recorded incident carries no events yet.
  const fresh = await readIncident(recorder.token, incident.id);
  assert.strictEqual(fresh.status, 200, JSON.stringify(fresh.body));
  assert.deepStrictEqual(fresh.body.incident.events, []);

  const moved = await moveStatus(recorder.token, incident.id, { status: 'investigating' });
  assert.strictEqual(moved.status, 200, JSON.stringify(moved.body));

  const corrected = await changeSeverity(safetyHolder.token, incident.id, {
    severityLevel: 'medical_treatment',
    note: 'Required medical treatment after all.'
  });
  assert.strictEqual(corrected.status, 200, JSON.stringify(corrected.body));

  const days = await recordDays(safetyHolder.token, incident.id, {
    lostTimeDays: 0,
    restrictedDays: 2
  });
  assert.strictEqual(days.status, 200, JSON.stringify(days.body));

  const closed = await closeIncident(safetyHolder.token, incident.id, {
    note: 'Restricted duty completed; closing.'
  });
  assert.strictEqual(closed.status, 200, JSON.stringify(closed.body));

  const detail = await readIncident(recorder.token, incident.id);
  assert.strictEqual(detail.status, 200, JSON.stringify(detail.body));

  const events = detail.body.incident.events;
  assert.strictEqual(events.length, 4);
  const kinds = events.map((event) => event.kind);
  assert.deepStrictEqual(kinds, ['status', 'severity', 'days', 'closure']);

  const statusEvent = events.find((event) => event.kind === 'status');
  assert.strictEqual(statusEvent.previousValue, 'open');
  assert.strictEqual(statusEvent.newValue, 'investigating');
  assert.strictEqual(statusEvent.changedByAccountId, String(recorder.id));
  assert.ok(statusEvent.changedAt);

  const severityEvent = events.find((event) => event.kind === 'severity');
  assert.strictEqual(severityEvent.previousValue, 'first_aid');
  assert.strictEqual(severityEvent.newValue, 'medical_treatment');
  assert.strictEqual(severityEvent.note, 'Required medical treatment after all.');
  assert.strictEqual(severityEvent.changedByAccountId, String(safetyHolder.id));

  const daysEvent = events.find((event) => event.kind === 'days');
  assert.match(daysEvent.newValue, /restrictedDays=2/);
  assert.strictEqual(daysEvent.changedByAccountId, String(safetyHolder.id));

  const closureEvent = events.find((event) => event.kind === 'closure');
  assert.strictEqual(closureEvent.newValue, 'closed');
  assert.strictEqual(closureEvent.note, 'Restricted duty completed; closing.');
  assert.strictEqual(closureEvent.changedByAccountId, String(safetyHolder.id));
});

// ---------------------------------------------------------------------------
// 15. The overdue listing (issue #228)
// ---------------------------------------------------------------------------

test('any Account that can see the Site lists incidents whose investigation is overdue, for an Org Unit and everything beneath it', async () => {
  const site = await insertSite();
  const parent = await insertOrgUnit(site.id, { name: 'Overdue parent' });
  const child = await insertOrgUnit(site.id, { parentId: parent.id, name: 'Overdue child' });
  const sibling = await insertOrgUnit(site.id, { name: 'Overdue sibling' });
  const recorder = await insertAccount({
    grants: [{ orgUnitId: parent.id }, { orgUnitId: sibling.id }]
  });

  const overdueAtParent = await recordedIncident(recorder, site, parent, {
    description: 'Overdue at the parent.'
  });
  const overdueAtChild = await recordedIncident(recorder, site, child, {
    description: 'Overdue beneath the parent.'
  });
  const notOverdueYet = await recordedIncident(recorder, site, parent, {
    description: 'Due date is in the future.'
  });
  const overdueButClosed = await recordedIncident(recorder, site, parent, {
    incidentType: 'near_miss',
    severityLevel: 'near_miss',
    description: 'Overdue, but already closed.'
  });
  const overdueAtSibling = await recordedIncident(recorder, site, sibling, {
    incidentType: 'near_miss',
    severityLevel: 'near_miss',
    description: 'Overdue at a sibling Org Unit.'
  });
  const neverGivenADeadline = await recordedIncident(recorder, site, parent, {
    description: 'No due date was ever set.'
  });

  const past = '2020-01-01T00:00:00Z';
  const future = '2099-01-01T00:00:00Z';

  for (const incident of [overdueAtParent, overdueAtChild, overdueButClosed, overdueAtSibling]) {
    const set = await setDueDate(recorder.token, incident.id, { investigationDueAt: past });
    assert.strictEqual(set.status, 200, JSON.stringify(set.body));
  }
  const setFuture = await setDueDate(recorder.token, notOverdueYet.id, {
    investigationDueAt: future
  });
  assert.strictEqual(setFuture.status, 200, JSON.stringify(setFuture.body));

  const safetyHolder = await insertAccount({ grants: [{ orgUnitId: parent.id, safety: true }] });
  const closed = await closeIncident(safetyHolder.token, overdueButClosed.id, {
    note: 'Closed before the overdue listing is read.'
  });
  assert.strictEqual(closed.status, 200, JSON.stringify(closed.body));

  const atParent = await overdueIncidents(recorder.token, site.id, `?orgUnitId=${parent.id}`);
  assert.strictEqual(atParent.status, 200, JSON.stringify(atParent.body));
  assert.deepStrictEqual(
    atParent.body.incidents.map((row) => row.id).sort(),
    [overdueAtParent.id, overdueAtChild.id].sort()
  );

  // No `orgUnitId` narrows to nothing — a Site-wide read includes the sibling
  // Org Unit's own overdue incident too.
  const siteWide = await overdueIncidents(recorder.token, site.id);
  assert.strictEqual(siteWide.status, 200, JSON.stringify(siteWide.body));
  assert.deepStrictEqual(
    siteWide.body.incidents.map((row) => row.id).sort(),
    [overdueAtParent.id, overdueAtChild.id, overdueAtSibling.id].sort()
  );

  // A stranger who cannot see the Site is refused, the same rule the
  // register itself follows.
  const stranger = await insertAccount({});
  const strangerRead = await overdueIncidents(stranger.token, site.id);
  assert.strictEqual(strangerRead.status, 403, JSON.stringify(strangerRead.body));

  // Neither `notOverdueYet` (due date in the future) nor `neverGivenADeadline`
  // (no due date at all) ever appears.
  const ids = siteWide.body.incidents.map((row) => row.id);
  assert.ok(!ids.includes(notOverdueYet.id));
  assert.ok(!ids.includes(neverGivenADeadline.id));
});

// ---------------------------------------------------------------------------
// 16. The injury classification, and who may read it (issue #224, ADR-0037)
//
// The most security-sensitive section in this file. `employeeId`,
// `employeeName`, the Injury type and the Body part are returned ONLY to a
// holder of Safety authority reaching the incident's Org Unit and to the
// Account whose own `app_users.employee_id` is the injured Employee; every
// other caller gets them **absent from the JSON**, not nulled.
//
// Absence is asserted with `hasOwnProperty`, never `=== undefined`: a key that
// is missing and a key set to undefined are indistinguishable through `===`,
// and only one of the two survives `JSON.stringify` — so the weaker assertion
// would pass against a serialiser that nulled the fields instead, which is
// exactly the shape ADR-0037 rejects.
// ---------------------------------------------------------------------------

// The nine keys ADR-0037 withholds together. They carry three facts — who the
// record names as hurt, what the injury was, and where on the body — and the
// display halves are in the list because withholding an id while returning the
// name it belongs to would defend nothing.
const RESTRICTED_KEYS = [
  'employeeId',
  'employeeName',
  'injuryTypeId',
  'injuryTypeCode',
  'injuryTypeName',
  'bodyPartId',
  'bodyPartCode',
  'bodyPartName',
  'bodyPartRegion'
];

// Everything the restriction deliberately does NOT narrow. ADR-0037 states
// that as a limit on what it protects rather than as a caveat on something
// broader, so it is asserted as positively as the absence is.
const ALWAYS_READABLE_KEYS = [
  'incidentNo',
  'status',
  'incidentType',
  'severityLevel',
  'isRecordable',
  'description',
  'immediateAction',
  'lostTimeDays',
  'restrictedDays',
  'orgUnitId',
  'events'
];

function assertInjuryDetailsAbsent(incident, who) {
  for (const key of RESTRICTED_KEYS) {
    assert.ok(
      !Object.prototype.hasOwnProperty.call(incident, key),
      `${who} must not receive ${key} at all — absent, not nulled`
    );
  }
  for (const key of ALWAYS_READABLE_KEYS) {
    assert.ok(
      Object.prototype.hasOwnProperty.call(incident, key),
      `${who} must still read ${key}: the restriction narrows nothing else`
    );
  }
}

function assertInjuryDetailsPresent(incident, { employee, injuryType, bodyPart }, who) {
  for (const key of RESTRICTED_KEYS) {
    assert.ok(
      Object.prototype.hasOwnProperty.call(incident, key),
      `${who} must receive ${key}`
    );
  }
  assert.strictEqual(incident.employeeId, employee.id, who);
  assert.strictEqual(incident.employeeName, employee.display_name, who);
  assert.strictEqual(incident.injuryTypeId, injuryType.id, who);
  assert.strictEqual(incident.injuryTypeName, injuryType.name, who);
  assert.strictEqual(incident.bodyPartId, bodyPart.id, who);
  assert.strictEqual(incident.bodyPartName, bodyPart.name, who);
  assert.strictEqual(incident.bodyPartRegion, bodyPart.region, who);
}

// One classified incident, and every kind of caller that will read it below.
async function classifiedGround() {
  const site = await insertSite();
  const unit = await insertOrgUnit(site.id, { name: 'Press Line' });

  const injured = await insertEmployee();
  const injuryType = await insertInjuryType({ name: 'Fracture' });
  const bodyPart = await insertBodyPart({ name: 'Left hand', region: 'upper_limb' });

  // Holds Safety authority at the incident's own Org Unit: the one caller the
  // ADR lets read by standing rather than by identity.
  const officer = await insertAccount({ grants: [{ orgUnitId: unit.id, safety: true }] });

  const incident = await recordedIncident(officer, site, unit, {
    severityLevel: 'medical_treatment',
    employeeId: injured.id,
    injuryTypeId: injuryType.id,
    bodyPartId: bodyPart.id
  });

  return { site, unit, injured, injuryType, bodyPart, officer, incident };
}

test('one incident read by four callers: the three injury fields are present for two of them and absent for two', async () => {
  const { site, unit, injured, injuryType, bodyPart, officer, incident } =
    await classifiedGround();

  // 1. A Site-wide reader: holds a Grant in the Site, so it sees the incident,
  //    but carries no Safety authority anywhere.
  const siteReader = await insertAccount({ grants: [{ orgUnitId: unit.id, write: false }] });

  // 2. The holder of Safety authority — `officer`, who recorded it.

  // 3. The injured person's own Account. It holds a read Grant so it can see
  //    the Site at all; what lets it read the classification is
  //    `app_users.employee_id`, not the Grant.
  const ownAccount = await insertAccount({
    grants: [{ orgUnitId: unit.id, write: false }],
    employeeId: injured.id
  });

  // 4. An administrator holding no Safety authority anywhere. This is the case
  //    a later "helpful" change is most likely to get wrong: `canAct` answers
  //    true for an administrator before it looks at a Grant, and ADR-0037
  //    restricts this read by the Grant rather than by the role.
  const plainAdmin = await insertAccount({ role: 'admin' });

  const asSiteReader = await readIncident(siteReader.token, incident.id);
  assert.strictEqual(asSiteReader.status, 200, JSON.stringify(asSiteReader.body));
  assertInjuryDetailsAbsent(asSiteReader.body.incident, 'a Site-wide reader');

  const asOfficer = await readIncident(officer.token, incident.id);
  assert.strictEqual(asOfficer.status, 200, JSON.stringify(asOfficer.body));
  assertInjuryDetailsPresent(
    asOfficer.body.incident,
    { employee: injured, injuryType, bodyPart },
    'a holder of Safety authority'
  );

  const asInjured = await readIncident(ownAccount.token, incident.id);
  assert.strictEqual(asInjured.status, 200, JSON.stringify(asInjured.body));
  assertInjuryDetailsPresent(
    asInjured.body.incident,
    { employee: injured, injuryType, bodyPart },
    "the injured person's own Account"
  );

  const asAdmin = await readIncident(plainAdmin.token, incident.id);
  assert.strictEqual(asAdmin.status, 200, JSON.stringify(asAdmin.body));
  assertInjuryDetailsAbsent(
    asAdmin.body.incident,
    'an administrator holding no Safety authority in the chain'
  );

  // The rest of the record is the same record for all four — the restriction
  // narrows three facts and nothing else.
  for (const answer of [asSiteReader, asOfficer, asInjured, asAdmin]) {
    assert.strictEqual(answer.body.incident.id, incident.id);
    assert.strictEqual(answer.body.incident.severityLevel, 'medical_treatment');
    assert.strictEqual(answer.body.incident.isRecordable, true);
    assert.strictEqual(
      answer.body.incident.description,
      'An incident recorded for issue #228.'
    );
    assert.strictEqual(answer.body.incident.siteId, site.id);
  }
});

test('the register applies the restriction too, row by row, where authority reaches one Org Unit and not another', async () => {
  const site = await insertSite();
  const pressLine = await insertOrgUnit(site.id, { name: 'Press Line' });
  const paintLine = await insertOrgUnit(site.id, { name: 'Paint Line' });

  const injuredOnPress = await insertEmployee();
  const injuredOnPaint = await insertEmployee();
  const injuryType = await insertInjuryType({ name: 'Burn' });
  const bodyPart = await insertBodyPart({ name: 'Right arm', region: 'upper_limb' });

  // Safety authority on the Press Line only. Everything this Account can do on
  // the Paint Line it can do because it holds an ordinary Grant there.
  const pressOfficer = await insertAccount({
    grants: [
      { orgUnitId: pressLine.id, safety: true },
      { orgUnitId: paintLine.id, write: true }
    ]
  });
  const paintOfficer = await insertAccount({
    grants: [{ orgUnitId: paintLine.id, safety: true }]
  });

  const pressIncident = await recordedIncident(pressOfficer, site, pressLine, {
    severityLevel: 'medical_treatment',
    employeeId: injuredOnPress.id,
    injuryTypeId: injuryType.id,
    bodyPartId: bodyPart.id
  });
  const paintIncident = await recordedIncident(paintOfficer, site, paintLine, {
    severityLevel: 'medical_treatment',
    employeeId: injuredOnPaint.id,
    injuryTypeId: injuryType.id,
    bodyPartId: bodyPart.id
  });

  // The whole Site, read by the Press Line's officer: one row classified, one
  // row redacted, in the same answer. A restriction decided once per request
  // rather than per row would get exactly this wrong.
  const register = await listIncidents(pressOfficer.token, site.id);
  assert.strictEqual(register.status, 200, JSON.stringify(register.body));

  const press = register.body.incidents.find((row) => row.id === pressIncident.id);
  const paint = register.body.incidents.find((row) => row.id === paintIncident.id);
  assert.ok(press && paint, 'both incidents are on the Site-wide register');

  assertInjuryDetailsPresent(
    press,
    { employee: injuredOnPress, injuryType, bodyPart },
    'the register row for the Org Unit the authority reaches'
  );
  assertInjuryDetailsAbsent(
    paint,
    'the register row for an Org Unit the authority does not reach'
  );

  // And the overdue listing, which is its own address and its own query.
  await setDueDate(pressOfficer.token, pressIncident.id, {
    investigationDueAt: '2020-01-01T00:00:00Z'
  });
  await setDueDate(paintOfficer.token, paintIncident.id, {
    investigationDueAt: '2020-01-01T00:00:00Z'
  });

  const overdue = await overdueIncidents(pressOfficer.token, site.id);
  assert.strictEqual(overdue.status, 200, JSON.stringify(overdue.body));
  assertInjuryDetailsPresent(
    overdue.body.incidents.find((row) => row.id === pressIncident.id),
    { employee: injuredOnPress, injuryType, bodyPart },
    'the overdue listing row the authority reaches'
  );
  assertInjuryDetailsAbsent(
    overdue.body.incidents.find((row) => row.id === paintIncident.id),
    'the overdue listing row the authority does not reach'
  );
});

test('classifying needs Safety authority, and the answer to a write is a read', async () => {
  const site = await insertSite();
  const unit = await insertOrgUnit(site.id, { name: 'Press Line' });
  const injured = await insertEmployee();
  const injuryType = await insertInjuryType({ name: 'Crush' });
  const bodyPart = await insertBodyPart({ name: 'Foot', region: 'lower_limb' });

  const recorder = await insertAccount({ grants: [{ orgUnitId: unit.id }] });
  const incident = await recordedIncident(recorder, site, unit, {
    severityLevel: 'medical_treatment'
  });

  // An edit Grant is what recorded it, and it is not enough to classify it.
  const refused = await classify(recorder.token, incident.id, {
    employeeId: injured.id,
    injuryTypeId: injuryType.id,
    bodyPartId: bodyPart.id
  });
  assert.strictEqual(refused.status, 403, JSON.stringify(refused.body));
  assert.strictEqual(
    refused.body.message,
    "that decision needs Safety authority at this Safety incident's Org Unit"
  );

  const officer = await insertAccount({ grants: [{ orgUnitId: unit.id, safety: true }] });
  const classified = await classify(officer.token, incident.id, {
    employeeId: injured.id,
    injuryTypeId: injuryType.id,
    bodyPartId: bodyPart.id
  });
  assert.strictEqual(classified.status, 200, JSON.stringify(classified.body));
  assertInjuryDetailsPresent(
    classified.body.incident,
    { employee: injured, injuryType, bodyPart },
    'the holder of Safety authority who classified it'
  );

  // An administrator with no Safety Grant anywhere may classify — ADR-0039
  // gives an administrator every authority, and #228's severity, days and
  // close routes already ship on that — but reads the result back with the
  // three fields absent, because ADR-0037 restricts the READ by the Grant. The
  // answer to a write is a read, and there is no second, weaker rule for it.
  const plainAdmin = await insertAccount({ role: 'admin' });
  const byAdmin = await classify(plainAdmin.token, incident.id, { bodyPartId: null });
  assert.strictEqual(byAdmin.status, 200, JSON.stringify(byAdmin.body));
  assertInjuryDetailsAbsent(
    byAdmin.body.incident,
    'an administrator classifying without a Safety Grant'
  );

  // It really did land: the officer, who may read it, sees the body part gone
  // and the other two fields untouched.
  const afterAdmin = await readIncident(officer.token, incident.id);
  assert.strictEqual(afterAdmin.body.incident.bodyPartId, null);
  assert.strictEqual(afterAdmin.body.incident.employeeId, injured.id);
  assert.strictEqual(afterAdmin.body.incident.injuryTypeId, injuryType.id);
});

test('recording an incident that names an injury classification needs Safety authority too', async () => {
  const site = await insertSite();
  const unit = await insertOrgUnit(site.id, { name: 'Press Line' });
  const injured = await insertEmployee();
  const injuryType = await insertInjuryType({ name: 'Strain' });
  const recorder = await insertAccount({ grants: [{ orgUnitId: unit.id }] });

  const base = {
    orgUnitId: unit.id,
    occurredAt: '2026-04-10T08:00:00Z',
    incidentType: 'injury',
    severityLevel: 'first_aid',
    description: 'A classification named at the moment of recording.'
  };

  for (const field of [
    { employeeId: injured.id },
    { injuryTypeId: injuryType.id }
  ]) {
    const refused = await record(recorder.token, site.id, { ...base, ...field });
    assert.strictEqual(refused.status, 403, JSON.stringify(refused.body));
    assert.strictEqual(
      refused.body.message,
      'naming the injured Employee, the Injury type or the Body part needs Safety authority at that Org Unit'
    );
  }

  // An edit Grant still records an unclassified incident exactly as issue #226
  // made it — the gate is on the classification, not on recording.
  const plain = await record(recorder.token, site.id, base);
  assert.strictEqual(plain.status, 201, JSON.stringify(plain.body));

  // And an explicit null is not naming a classification: it says "nobody",
  // which is what the record already holds.
  const explicitlyNobody = await record(recorder.token, site.id, {
    ...base,
    employeeId: null,
    injuryTypeId: null,
    bodyPartId: null
  });
  assert.strictEqual(explicitlyNobody.status, 201, JSON.stringify(explicitlyNobody.body));
});

test('an injury type or a body part on the no-injury rung is a 400 naming the field', async () => {
  const site = await insertSite();
  const unit = await insertOrgUnit(site.id, { name: 'Press Line' });
  const officer = await insertAccount({ grants: [{ orgUnitId: unit.id, safety: true }] });
  const injuryType = await insertInjuryType({ name: 'Laceration' });
  const bodyPart = await insertBodyPart({ name: 'Thumb', region: 'upper_limb' });

  const base = {
    orgUnitId: unit.id,
    occurredAt: '2026-04-10T08:00:00Z',
    incidentType: 'near_miss',
    severityLevel: 'near_miss',
    description: 'Nobody was hurt.'
  };

  const withType = await record(officer.token, site.id, {
    ...base,
    injuryTypeId: injuryType.id
  });
  assert.strictEqual(withType.status, 400, JSON.stringify(withType.body));
  assert.strictEqual(
    withType.body.message,
    'injuryTypeId cannot be set on the near_miss rung: nobody was injured'
  );

  const withPart = await record(officer.token, site.id, { ...base, bodyPartId: bodyPart.id });
  assert.strictEqual(withPart.status, 400, JSON.stringify(withPart.body));
  assert.strictEqual(
    withPart.body.message,
    'bodyPartId cannot be set on the near_miss rung: nobody was injured'
  );

  // The same refusal through the classify address, on an already-recorded
  // near miss — `requireLadderConsistency` is reused rather than copied.
  const nearMiss = await recordedIncident(officer, site, unit, {
    incidentType: 'near_miss',
    severityLevel: 'near_miss'
  });
  const classified = await classify(officer.token, nearMiss.id, {
    injuryTypeId: injuryType.id
  });
  assert.strictEqual(classified.status, 400, JSON.stringify(classified.body));
  assert.strictEqual(
    classified.body.message,
    'injuryTypeId cannot be set on the near_miss rung: nobody was injured'
  );

  // Naming who was involved in a near miss is not classifying an injury: the
  // baseline's own CHECK forbids an injury type and a body part on that rung,
  // not an Employee, and a report that says who was nearly hurt is worth
  // keeping.
  const whoWasThere = await classify(officer.token, nearMiss.id, {
    employeeId: (await insertEmployee()).id
  });
  assert.strictEqual(whoWasThere.status, 200, JSON.stringify(whoWasThere.body));
});

test('classifying names at least one field, and an absent key leaves its own field alone', async () => {
  const { injured, injuryType, bodyPart, officer, incident } = await classifiedGround();

  const nothing = await classify(officer.token, incident.id, {});
  assert.strictEqual(nothing.status, 400, JSON.stringify(nothing.body));
  assert.match(nothing.body.message, /employeeId/);

  // One field sent, two untouched — the contract that lets a classification be
  // completed at three different moments.
  const otherType = await insertInjuryType({ name: 'Amputation' });
  const one = await classify(officer.token, incident.id, { injuryTypeId: otherType.id });
  assert.strictEqual(one.status, 200, JSON.stringify(one.body));
  assert.strictEqual(one.body.incident.injuryTypeId, otherType.id);
  assert.strictEqual(one.body.incident.employeeId, injured.id);
  assert.strictEqual(one.body.incident.bodyPartId, bodyPart.id);

  // An explicit null clears, so a mistaken pick is removable rather than only
  // replaceable.
  const cleared = await classify(officer.token, incident.id, { employeeId: null });
  assert.strictEqual(cleared.status, 200, JSON.stringify(cleared.body));
  assert.strictEqual(cleared.body.incident.employeeId, null);
  assert.strictEqual(cleared.body.incident.employeeName, null);
  assert.strictEqual(cleared.body.incident.injuryTypeId, otherType.id);

  // An unknown catalogue entry is a 404 naming it, never a raw foreign key.
  const unknownType = await classify(officer.token, incident.id, { injuryTypeId: 999999999 });
  assert.strictEqual(unknownType.status, 404);
  assert.strictEqual(unknownType.body.message, 'Injury type not found');

  const unknownPart = await classify(officer.token, incident.id, { bodyPartId: 999999999 });
  assert.strictEqual(unknownPart.status, 404);
  assert.strictEqual(unknownPart.body.message, 'Body part not found');

  assert.ok(injuryType.id, 'the original type still exists for teardown');
});

test('a deactivated catalogue entry stays readable on an incident that already carries it', async () => {
  const site = await insertSite();
  const unit = await insertOrgUnit(site.id, { name: 'Press Line' });
  const officer = await insertAccount({ grants: [{ orgUnitId: unit.id, safety: true }] });
  const injured = await insertEmployee();
  const injuryType = await insertInjuryType({ name: 'Electric shock' });
  const bodyPart = await insertBodyPart({ name: 'Hand', region: 'upper_limb' });

  const incident = await recordedIncident(officer, site, unit, {
    severityLevel: 'lost_time',
    employeeId: injured.id,
    injuryTypeId: injuryType.id,
    bodyPartId: bodyPart.id
  });

  await pool.query('UPDATE injury_types SET is_active = FALSE WHERE id = $1', [injuryType.id]);
  await pool.query('UPDATE body_parts SET is_active = FALSE WHERE id = $1', [bodyPart.id]);

  const read = await readIncident(officer.token, incident.id);
  assert.strictEqual(read.status, 200, JSON.stringify(read.body));
  assert.strictEqual(read.body.incident.injuryTypeName, injuryType.name);
  assert.strictEqual(read.body.incident.bodyPartName, bodyPart.name);

  // And a correction that leaves the retired entry where it is still lands.
  const stillCorrectable = await classify(officer.token, incident.id, {
    employeeId: null
  });
  assert.strictEqual(stillCorrectable.status, 200, JSON.stringify(stillCorrectable.body));
  assert.strictEqual(stillCorrectable.body.incident.injuryTypeId, injuryType.id);
});

// ---------------------------------------------------------------------------
// 17. A classification change is kept in the event history, and who may read
// it (issue #224's own history criterion, migration 1801000000000)
// ---------------------------------------------------------------------------

test('a classification change writes a classification event, readable by the holder of Safety authority and by the injured person', async () => {
  const { unit, injured, injuryType, bodyPart, officer, incident } = await classifiedGround();

  const ownAccount = await insertAccount({
    grants: [{ orgUnitId: unit.id, write: false }],
    employeeId: injured.id
  });

  const otherType = await insertInjuryType({ name: 'Sprain' });
  const classified = await classify(officer.token, incident.id, {
    injuryTypeId: otherType.id
  });
  assert.strictEqual(classified.status, 200, JSON.stringify(classified.body));

  const asOfficer = await readIncident(officer.token, incident.id);
  assert.strictEqual(asOfficer.status, 200, JSON.stringify(asOfficer.body));
  const officerEvents = asOfficer.body.incident.events;
  const classificationEvent = officerEvents.find((event) => event.kind === 'classification');
  assert.ok(classificationEvent, 'the holder of Safety authority sees the classification event');
  assert.strictEqual(
    classificationEvent.previousValue,
    `employeeId=${injured.id},injuryType=${injuryType.code},bodyPart=${bodyPart.code}`
  );
  assert.strictEqual(
    classificationEvent.newValue,
    `employeeId=${injured.id},injuryType=${otherType.code},bodyPart=${bodyPart.code}`
  );
  assert.strictEqual(classificationEvent.changedByAccountId, String(officer.id));
  assert.ok(classificationEvent.changedAt);

  const asInjured = await readIncident(ownAccount.token, incident.id);
  assert.strictEqual(asInjured.status, 200, JSON.stringify(asInjured.body));
  assert.ok(
    asInjured.body.incident.events.some((event) => event.kind === 'classification'),
    "the injured person's own Account sees the classification event too"
  );
});

test('a Site-wide reader and a plain administrator never see a classification event, even though the classification happened', async () => {
  const { unit, officer, incident } = await classifiedGround();

  const siteReader = await insertAccount({ grants: [{ orgUnitId: unit.id, write: false }] });
  const plainAdmin = await insertAccount({ role: 'admin' });

  const otherType = await insertInjuryType({ name: 'Contusion' });
  const classified = await classify(officer.token, incident.id, {
    injuryTypeId: otherType.id
  });
  assert.strictEqual(classified.status, 200, JSON.stringify(classified.body));

  const asSiteReader = await readIncident(siteReader.token, incident.id);
  assert.strictEqual(asSiteReader.status, 200, JSON.stringify(asSiteReader.body));
  assert.ok(Array.isArray(asSiteReader.body.incident.events), 'events is still present, just filtered');
  assert.ok(
    !asSiteReader.body.incident.events.some((event) => event.kind === 'classification'),
    'a Site-wide reader must not see a classification event'
  );

  const asAdmin = await readIncident(plainAdmin.token, incident.id);
  assert.strictEqual(asAdmin.status, 200, JSON.stringify(asAdmin.body));
  assert.ok(
    !asAdmin.body.incident.events.some((event) => event.kind === 'classification'),
    'an administrator holding no Safety Grant must not see a classification event either'
  );

  // The officer, who may read it, confirms the event really is there — the
  // two callers above are filtered, not simply missing it for some other
  // reason.
  const asOfficer = await readIncident(officer.token, incident.id);
  assert.ok(asOfficer.body.incident.events.some((event) => event.kind === 'classification'));
});

test('a no-op classify call — re-sending the values already on the record — writes no event', async () => {
  const { injured, injuryType, bodyPart, officer, incident } = await classifiedGround();

  const before = await readIncident(officer.token, incident.id);
  const eventsBefore = before.body.incident.events.length;

  const noop = await classify(officer.token, incident.id, {
    employeeId: injured.id,
    injuryTypeId: injuryType.id,
    bodyPartId: bodyPart.id
  });
  assert.strictEqual(noop.status, 200, JSON.stringify(noop.body));

  const after = await readIncident(officer.token, incident.id);
  assert.strictEqual(
    after.body.incident.events.length,
    eventsBefore,
    're-sending the values already on the record must not add an event'
  );
  assert.ok(!after.body.incident.events.some((event) => event.kind === 'classification'));
});
