/*
 * Raising a Concern from a Safety incident, and a CAPA on that Concern (issue
 * #229) — over HTTP, against a real database and a real (locally issued)
 * JWKS. The seam and the fixture scaffolding mirror
 * `concern-nonconformances.test.js` closely: this is the same shape of path,
 * built out of the same three writes in the Actions Module, with the Safety
 * incident standing where the Non-conformance stood.
 *
 * What #229 asks for, and nothing more (#223's own spec, decision 8 and
 * ADR-0038): `action_items.safety_incident_id` is the source column, already
 * in the schema and already permitted alongside `capa_id` by #221's narrowed
 * `action_items_single_source`; no Grant is needed to raise the Concern, only
 * Site visibility (#198's rule); the incident and the Concern each name the
 * other; closing the incident never waits on the Concern (#223 decision 4);
 * and a CAPA is opened on that Concern through the existing `actions` CAPA
 * routes, unchanged. `capas.safety_incident_id` is written by nothing, which
 * section 4 asserts directly against the database — the one place this file
 * reads Postgres rather than the HTTP seam, for the same reason
 * `concern-nonconformances.test.js`'s own section 5 does: the claim is a fact
 * about a column nothing writes, and a raw SELECT is the only way to state
 * that with no service function standing between the assertion and the row.
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
const insertedIncidentIds = [];
const insertedActionIds = [];
const insertedCapaIds = [];

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

// An Account, optionally holding Grants — `write` defaults to true (most of
// this file's Accounts record an incident first), `quality` and `safety` are
// the two independent authority flags ADR-0035/ADR-0039 keep beside it.
async function insertAccount({ role = 'operator', grants = [] } = {}) {
  const subject = uniqueCode('sicacct');
  const { rows: [account] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status)
     VALUES ($1, 'Safety Concern Account', $2, $3, TRUE, 'approved') RETURNING id`,
    [`${subject}@example.com`, role, subject]
  );
  insertedAccountIds.push(account.id);

  for (const grant of grants) {
    await pool.query(
      `INSERT INTO app_user_org_units (app_user_id, org_unit_id, can_write, quality_authority, safety_authority)
       VALUES ($1, $2, $3, $4, $5)`,
      [account.id, grant.orgUnitId, grant.write ?? true, grant.quality ?? false, grant.safety ?? false]
    );
  }

  return { id: account.id, token: await authHeader(subject) };
}

async function insertSite() {
  const { rows: [site] } = await pool.query(
    `INSERT INTO sites (code, name, timezone) VALUES ($1, $2, $3) RETURNING id, code, name`,
    [uniqueCode('SCS'), 'Safety Concern Test Site', 'Asia/Ho_Chi_Minh']
  );
  insertedSiteIds.push(site.id);
  return site;
}

async function insertOrgUnit(siteId, { name = 'Safety Concern Unit' } = {}) {
  const { rows: [orgUnit] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, NULL, $2, $3, 'area') RETURNING id, code, name, path`,
    [siteId, uniqueCode('SCOU'), name]
  );
  insertedOrgUnitIds.push(orgUnit.id);
  return orgUnit;
}

async function recordIncident(token, siteId, body) {
  const response = await fetch(`${base}/api/safety/sites/${siteId}/incidents`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  const payload = await json(response);
  if (payload.status === 201) insertedIncidentIds.push(payload.body.incident.id);
  return payload;
}

async function readIncident(token, id) {
  const response = await fetch(`${base}/api/safety/incidents/${id}`, { headers: token });
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

// `POST /api/actions/safety-incidents/:id/concern` — raising one from a
// Safety incident (issue #229), the mirror of the Non-conformance address.
async function raiseConcern(token, incidentId, body) {
  const response = await fetch(`${base}/api/actions/safety-incidents/${incidentId}/concern`, {
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

// `POST /api/actions/:id/capa` — the existing CAPA route, unchanged (issue
// #229's own "no new mechanism" criterion).
async function openCapa(token, concernId, body = {}) {
  const response = await fetch(`${base}/api/actions/${concernId}/capa`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  const payload = await json(response);
  if (payload.body && payload.body.capa) insertedCapaIds.push(payload.body.capa.id);
  return payload;
}

async function readCapa(token, capaId) {
  const response = await fetch(`${base}/api/actions/capas/${capaId}`, { headers: token });
  return json(response);
}

let admin;
let adminToken;

// The ground every test starts from: a Site, the Org Unit the incident
// happened at, an Account that may record there, and the incident itself.
async function makeGround(overrides = {}) {
  const site = await insertSite();
  const unit = await insertOrgUnit(site.id, { name: 'Foundry Floor' });
  const recorder = await insertAccount({ grants: [{ orgUnitId: unit.id }] });

  const recorded = await recordIncident(recorder.token, site.id, {
    orgUnitId: unit.id,
    occurredAt: '2026-04-10T08:00:00Z',
    incidentType: 'injury',
    severityLevel: 'medical_treatment',
    description: 'Caught a hand in the press guard.',
    ...overrides
  });
  assert.strictEqual(recorded.status, 201, `recording failed: ${JSON.stringify(recorded.body)}`);

  return { site, unit, recorder, id: recorded.body.incident.id, incident: recorded.body.incident };
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
  // CASCADE, so the Concerns go first; the CAPAs go after them, because
  // `action_items.capa_id` is a plain foreign key Postgres checks on DELETE.
  await pool.query('DELETE FROM action_items WHERE id = ANY($1)', [insertedActionIds]);
  if (insertedCapaIds.length > 0) {
    await pool.query('DELETE FROM capa_team_members WHERE capa_id = ANY($1)', [insertedCapaIds]);
    await pool.query('DELETE FROM capas WHERE id = ANY($1)', [insertedCapaIds]);
  }
  await pool.query('DELETE FROM safety_incident_events WHERE safety_incident_id = ANY($1)', [
    insertedIncidentIds
  ]);
  await pool.query('DELETE FROM safety_incidents WHERE id = ANY($1)', [insertedIncidentIds]);
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
// 1. Raising a Concern from a Safety incident
// ---------------------------------------------------------------------------

test('raising a Concern from a Safety incident lands it at the incident\'s Org Unit, numbers it for the Site, and records where it came from — without a Grant', async () => {
  const ground = await makeGround();

  // The recorder holds a write Grant at the Org Unit, but raising a Concern
  // is a report rather than a decision (#198): anyone who can see the Site
  // may raise one, Grant or none. A second Account with no Grant anywhere
  // but one that CAN see the Site (a read Grant at the same Org Unit) proves
  // the point the recorder's own write Grant would not.
  const reporter = await insertAccount({ grants: [{ orgUnitId: ground.unit.id, write: false }] });

  const { status, body } = await raiseConcern(reporter.token, ground.id, {
    title: 'The press guard keeps working loose',
    description: 'Third time this shift the interlock has been bypassed.'
  });
  assert.strictEqual(status, 201, JSON.stringify(body));

  const concern = body.action;
  assert.strictEqual(concern.actionType, 'concern');
  assert.strictEqual(concern.status, 'open');
  assert.strictEqual(concern.title, 'The press guard keeps working loose');
  // The incident's own Org Unit, which the caller never named.
  assert.strictEqual(String(concern.orgUnitId), String(ground.unit.id));
  // The Site's own document number — the same shape every Action gets.
  assert.match(concern.actionNo, /^AC-[A-Z0-9]+-\d{4}-\d{5}$/);
  // The Action log's usual rules, unchanged: a cycle-1 Plan of its own.
  assert.strictEqual(concern.openPhase.phase, 'plan');
  assert.strictEqual(concern.openPhase.cycle, 1);

  // It records the Safety incident it came from — the source column, and the
  // nested fact a reader needs to recognise it and go there.
  assert.strictEqual(String(concern.sourceSafetyIncidentId), String(ground.id));
  assert.strictEqual(concern.sourceType, 'safety_incident');
  assert.strictEqual(String(concern.safetyIncident.id), String(ground.id));
  assert.strictEqual(concern.safetyIncident.incidentNo, ground.incident.incidentNo);
  assert.strictEqual(concern.safetyIncident.severityLevel, 'medical_treatment');
  // Never the injury details ADR-0037 restricts — this Module reads none of
  // them, so there is no key here to leak.
  assert.strictEqual(Object.prototype.hasOwnProperty.call(concern.safetyIncident, 'employeeId'), false);
  assert.strictEqual(Object.prototype.hasOwnProperty.call(concern.safetyIncident, 'injuryTypeId'), false);
  assert.strictEqual(Object.prototype.hasOwnProperty.call(concern.safetyIncident, 'bodyPartId'), false);

  // No Non-conformance link, and no CAPA yet.
  assert.strictEqual(concern.sourceNonconformanceId, null);
  assert.deepStrictEqual(concern.nonconformances, []);
  assert.strictEqual(concern.capa, null);

  // And the incident shows the Concern the other way round, with its status.
  const read = await readIncident(ground.recorder.token, ground.id);
  assert.strictEqual(read.status, 200);
  assert.strictEqual(read.body.incident.concerns.length, 1);
  assert.strictEqual(String(read.body.incident.concerns[0].id), String(concern.id));
  assert.strictEqual(read.body.incident.concerns[0].status, 'open');
  assert.strictEqual(read.body.incident.concerns[0].actionNo, concern.actionNo);
});

test('a Concern raised from a Safety incident follows the Concern rule: a title is required, and a caller who cannot see the Site is refused', async () => {
  const ground = await makeGround();

  const untitled = await raiseConcern(ground.recorder.token, ground.id, {
    description: 'no title'
  });
  assert.strictEqual(untitled.status, 400, JSON.stringify(untitled.body));
  assert.match(untitled.body.message, /title is required/);

  // Nobody outside the Site at all — an Account granted only on another Site's
  // Org Unit cannot see this one, so the Concern rule refuses them too.
  const otherSite = await insertSite();
  const otherUnit = await insertOrgUnit(otherSite.id, { name: 'Elsewhere' });
  const stranger = await insertAccount({ grants: [{ orgUnitId: otherUnit.id }] });

  const refused = await raiseConcern(stranger.token, ground.id, {
    title: 'Not mine to raise'
  });
  assert.strictEqual(refused.status, 403, JSON.stringify(refused.body));

  // The incident itself is invisible to them too — the same rule read the
  // other way.
  const hidden = await readIncident(stranger.token, ground.id);
  assert.strictEqual(hidden.status, 403, JSON.stringify(hidden.body));

  // An id that names no incident at all is a 404, for an administrator too.
  const missing = await raiseConcern(adminToken, '99999999', { title: 'Nothing here' });
  assert.strictEqual(missing.status, 404, JSON.stringify(missing.body));
  assert.match(missing.body.message, /Safety incident/);
});

test('the Safety incident\'s detail returns the Concern raised from it, and the Concern\'s detail names the incident\'s number and severity — never its injury details', async () => {
  const ground = await makeGround({ severityLevel: 'lost_time', lostTimeDays: 3 });

  // Nothing is being done about the cause yet — a real state, not a missing
  // field.
  const before = await readIncident(ground.recorder.token, ground.id);
  assert.deepStrictEqual(before.body.incident.concerns, []);

  const raised = await raiseConcern(ground.recorder.token, ground.id, {
    title: 'The interlock needs a real fix'
  });
  assert.strictEqual(raised.status, 201, JSON.stringify(raised.body));
  const concernId = raised.body.action.id;

  const read = await readIncident(ground.recorder.token, ground.id);
  assert.strictEqual(read.status, 200);
  const [concern] = read.body.incident.concerns;
  assert.strictEqual(String(concern.id), String(concernId));
  assert.strictEqual(concern.status, 'open');
  assert.strictEqual(concern.actionNo, raised.body.action.actionNo);
  assert.strictEqual(concern.title, 'The interlock needs a real fix');
  assert.strictEqual(concern.actionType, 'concern');
  assert.strictEqual(String(concern.orgUnitId), String(ground.unit.id));

  // The Concern's own read, on its own address, names the incident with its
  // number and severity — the evidence a reader needs — and nothing about who
  // was hurt: this Module never selected those columns, so there is no gate
  // to bypass and no key to leak.
  const concernRead = await readAction(ground.recorder.token, concernId);
  assert.strictEqual(concernRead.status, 200);
  assert.strictEqual(concernRead.body.action.safetyIncident.incidentNo, ground.incident.incidentNo);
  assert.strictEqual(concernRead.body.action.safetyIncident.severityLevel, 'lost_time');
  assert.strictEqual(
    Object.prototype.hasOwnProperty.call(concernRead.body.action.safetyIncident, 'employeeId'),
    false
  );
});

// ---------------------------------------------------------------------------
// 2. Closing the incident never waits on its Concern (#223 decision 4)
// ---------------------------------------------------------------------------

test('closing a Safety incident succeeds while the Concern raised from it is still open', async () => {
  const ground = await makeGround({ severityLevel: 'near_miss' });

  const raised = await raiseConcern(ground.recorder.token, ground.id, {
    title: 'Worth solving even though nobody was hurt this time'
  });
  assert.strictEqual(raised.status, 201, JSON.stringify(raised.body));
  assert.notStrictEqual(raised.body.action.status, 'closed');

  // Closing needs Safety authority (issue #228, ADR-0039) — independent of
  // the recorder's own write Grant.
  const holder = await insertAccount({
    grants: [{ orgUnitId: ground.unit.id, write: false, safety: true }]
  });

  const closed = await closeIncident(holder.token, ground.id, {
    note: 'The incident itself is dealt with; the Concern keeps working the cause.'
  });
  assert.strictEqual(closed.status, 200, JSON.stringify(closed.body));
  assert.strictEqual(closed.body.incident.status, 'closed');

  // The Concern is untouched by the closure, and the closed incident still
  // names it.
  const stillOpen = await readAction(ground.recorder.token, raised.body.action.id);
  assert.strictEqual(stillOpen.status, 200);
  assert.notStrictEqual(stillOpen.body.action.status, 'closed');

  const read = await readIncident(ground.recorder.token, ground.id);
  assert.strictEqual(read.body.incident.concerns.length, 1);
  assert.strictEqual(read.body.incident.concerns[0].status, 'open');
});

// ---------------------------------------------------------------------------
// 3. A CAPA on a Concern raised from a Safety incident — the existing routes,
//    unchanged (issue #229, ADR-0034, ADR-0038)
// ---------------------------------------------------------------------------

test('a CAPA can be opened on a Concern raised from a Safety incident through the existing actions CAPA routes, and the report names the incident', async () => {
  const ground = await makeGround();

  const raised = await raiseConcern(ground.recorder.token, ground.id, {
    title: 'The guard keeps working loose'
  });
  assert.strictEqual(raised.status, 201, JSON.stringify(raised.body));
  assert.strictEqual(String(raised.body.action.sourceSafetyIncidentId), String(ground.id));

  // The act of Quality authority, exactly as ADR-0034/ADR-0038 say: a CAPA on
  // a safety-sourced Concern is opened by a holder of Quality authority on the
  // Concern's own Org Unit, through no new mechanism.
  const holder = await insertAccount({
    grants: [{ orgUnitId: ground.unit.id, write: false, quality: true }]
  });

  const opened = await openCapa(holder.token, raised.body.action.id, {});
  assert.strictEqual(opened.status, 201, JSON.stringify(opened.body));

  const concern = await readAction(ground.recorder.token, raised.body.action.id);
  assert.strictEqual(concern.status, 200, JSON.stringify(concern.body));
  assert.strictEqual(String(concern.body.action.sourceSafetyIncidentId), String(ground.id));
  assert.strictEqual(concern.body.action.sourceType, 'safety_incident');
  assert.strictEqual(concern.body.action.capa.id, opened.body.capa.id);

  // The investigation's own read carries the Concern, and the Concern names
  // the Safety incident behind it — what the CAPA report names where it names
  // a Non-conformance today.
  const read = await readCapa(holder.token, opened.body.capa.id);
  assert.strictEqual(read.status, 200, JSON.stringify(read.body));
  assert.strictEqual(String(read.body.capa.concern.safetyIncident.id), String(ground.id));
  assert.strictEqual(read.body.capa.concern.safetyIncident.incidentNo, ground.incident.incidentNo);
  assert.deepStrictEqual(read.body.capa.concern.nonconformances, []);

  // `capas.safety_incident_id` is written by nothing (issue #229, ADR-0038) —
  // asserted directly against the row, since no service function anywhere
  // sets it and there is no HTTP response field standing between this
  // assertion and the column.
  const { rows } = await pool.query('SELECT safety_incident_id FROM capas WHERE id = $1', [
    opened.body.capa.id
  ]);
  assert.strictEqual(rows[0].safety_incident_id, null);
});

test('opening and closing a CAPA on a safety-sourced Concern follows the same rules as any other CAPA', async () => {
  const ground = await makeGround();

  const raised = await raiseConcern(ground.recorder.token, ground.id, {
    title: 'A formal investigation is warranted'
  });
  const concernId = raised.body.action.id;

  // Refused without Quality authority, exactly as for a Concern raised from a
  // Non-conformance — the CAPA rules are unchanged by this ticket.
  const noAuthority = await openCapa(ground.recorder.token, concernId, {});
  assert.strictEqual(noAuthority.status, 403, JSON.stringify(noAuthority.body));

  const holder = await insertAccount({
    grants: [{ orgUnitId: ground.unit.id, write: false, quality: true }]
  });
  const opened = await openCapa(holder.token, concernId, {
    problemStatement: 'The press guard interlock does not hold under load.'
  });
  assert.strictEqual(opened.status, 201, JSON.stringify(opened.body));
  assert.strictEqual(opened.body.capa.problemStatement, 'The press guard interlock does not hold under load.');

  // A second CAPA on the same Concern is refused, the rule ADR-0034's own
  // uniqueness index enforces regardless of what the Concern was raised from.
  const again = await openCapa(holder.token, concernId, {});
  assert.strictEqual(again.status, 409, JSON.stringify(again.body));
  assert.match(again.body.message, /already has a CAPA/);
});
