/*
 * The fishbone on a CAPA (issue #213) — candidate causes by 6M category, their
 * verdicts with the evidence behind them, and starting a Why chain from a
 * confirmed one, over HTTP, against a real database and a real (locally issued)
 * JWKS. The seam, the fixture scaffolding and the dependency-ordered cleanup
 * are the ones capa-whys.test.js, capas.test.js and actions.test.js already
 * establish.
 *
 * What this file claims, one test per rule the ticket states: a candidate cause
 * is added under exactly one 6M category, changed and removed while the CAPA is
 * open, and the fishbone reads in the 6M's own order; a cause is a `candidate`
 * until it is decided, `confirmed` and `ruled_out` both require the evidence
 * note in the same request (400 otherwise), and going back to `candidate`
 * clears the evidence; a chain's first Why is started from a confirmed cause
 * and from nothing else — a `candidate` or `ruled_out` one is a 409, as is a
 * chain that has already started; and the fishbone obeys #210's own write rule
 * (403 for a caller with neither edit access at the CAPA's Org Unit nor a place
 * on its team) and #210's own refusal on a closed investigation (409).
 *
 * **No assertion in this file reads Postgres directly.** Every rule the ticket
 * states has an HTTP door, so the two-test-seams rule is kept whole here: the
 * verdict's 400, the refusal to start a chain from an unconfirmed cause, and
 * the 6M set itself are all answered by the API rather than by a query against
 * the table behind it. The one thing this file needs from the schema is
 * arranged by writing it, not by reading it: a closed CAPA, which is #211's own
 * ticket, is inserted the way `plant.test.js` inserts the rows its Module
 * cannot yet create, and removed in `after()`.
 *
 * Needs a database with every migration applied, including
 * 1800200000000_why-chains-on-a-capa.js, which is where the `verdict` and
 * `evidence_note` columns this ticket writes come from. Set DATABASE_URL first
 * — see the README's Tests section.
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
  // Concatenated rather than written as one template literal: an auth header
  // in a file's own content is masked in transit by the tooling that writes
  // it, which would land a syntax error here.
  return { authorization: 'Bearer ' + token };
}

async function json(response) {
  return { status: response.status, body: await response.json() };
}

// An Account, optionally holding Grants and optionally linked to an Employee
// (`app_users.employee_id`). The Employee link is what the team half of
// #210's write rule reads, and the rule this ticket shares.
async function insertAccount({
  role = 'operator',
  displayName = null,
  grants = [],
  employeeId = null
} = {}) {
  const subject = uniqueCode('fbacct');
  const name = displayName ?? `Fishbone Account ${subject}`;
  const { rows: [account] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active,
                            approval_status, employee_id)
     VALUES ($1, $2, $3, $4, TRUE, 'approved', $5) RETURNING id`,
    [`${subject}@example.com`, name, role, subject, employeeId]
  );
  insertedAccountIds.push(account.id);

  for (const grant of grants) {
    await pool.query(
      `INSERT INTO app_user_org_units (app_user_id, org_unit_id, can_write, quality_authority)
       VALUES ($1, $2, $3, $4)`,
      [account.id, grant.orgUnitId, grant.write ?? false, grant.quality ?? false]
    );
  }

  return { id: account.id, displayName: name, token: await authHeader(subject) };
}

async function insertSite() {
  const { rows: [site] } = await pool.query(
    `INSERT INTO sites (code, name, timezone) VALUES ($1, $2, $3) RETURNING id, code, name`,
    [uniqueCode('FBAS'), 'Fishbone Test Site', 'Asia/Ho_Chi_Minh']
  );
  insertedSiteIds.push(site.id);
  return site;
}

async function insertOrgUnit(siteId, { parentId = null, unitType = 'area', name = 'Why Unit' } = {}) {
  const { rows: [orgUnit] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, $2, $3, $4, $5) RETURNING id, code, name, path`,
    [siteId, parentId, uniqueCode('FBAOU'), name, unitType]
  );
  insertedOrgUnitIds.push(orgUnit.id);
  return orgUnit;
}

async function insertEmployee({ first = 'Ann', last = 'Fitter', isActive = true } = {}) {
  const { rows: [employee] } = await pool.query(
    `INSERT INTO employees (employee_no, first_name, last_name, is_active)
     VALUES ($1, $2, $3, $4) RETURNING id, display_name, is_active`,
    [uniqueCode('FBAEMP'), first, last, isActive]
  );
  insertedEmployeeIds.push(employee.id);
  return employee;
}

async function raiseConcern(token, siteId, body) {
  const response = await fetch(`${base}/api/actions/sites/${siteId}/actions`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify({ actionType: 'concern', ...body })
  });
  const { status, body: payload } = await json(response);
  if (status === 201) insertedActionIds.push(payload.action.id);
  return { status, body: payload };
}

async function openCapa(token, concernId, body = {}) {
  const response = await fetch(`${base}/api/actions/${concernId}/capa`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  const { status, body: payload } = await json(response);
  if (status === 201) insertedCapaIds.push(payload.capa.id);
  return { status, body: payload };
}

async function readCapa(token, capaId) {
  const response = await fetch(`${base}/api/actions/capas/${capaId}`, { headers: token });
  return json(response);
}

/**
 * A CAPA that is already over, written straight into `capas` (see this file's
 * header): #211 owns closing one, so nothing on this branch can produce this
 * row through the API.
 *
 * `effectiveness_verified_at` is set because the baseline will not have it any
 * other way — `capas_eightd_needs_verification` refuses a closed 8D that was
 * never verified. A closed CAPA that never had that check is not a row this
 * schema admits, so the fixture is a *real* closed investigation.
 */
async function insertClosedCapa(orgUnitId, status = 'closed') {
  const { rows: [capa] } = await pool.query(
    `INSERT INTO capas (capa_no, title, problem_statement, method, org_unit_id,
                        status, closed_at, effectiveness_verified_at)
     VALUES ($1, $2, $3, '8d', $4, $5, now(), now()) RETURNING id, capa_no`,
    [
      uniqueCode('FBAC'),
      'An investigation that is already over',
      'Closed before this test started.',
      orgUnitId,
      status
    ]
  );
  insertedCapaIds.push(capa.id);
  return capa;
}

async function addCause(token, capaId, body) {
  const response = await fetch(`${base}/api/actions/capas/${capaId}/causes`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  return json(response);
}

async function changeCause(token, capaId, causeId, body) {
  const response = await fetch(`${base}/api/actions/capas/${capaId}/causes/${causeId}`, {
    method: 'PATCH',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  return json(response);
}

async function removeCause(token, capaId, causeId) {
  const response = await fetch(`${base}/api/actions/capas/${capaId}/causes/${causeId}`, {
    method: 'DELETE',
    headers: token
  });
  return json(response);
}

async function startWhyFromCause(token, capaId, causeId, body) {
  const response = await fetch(`${base}/api/actions/capas/${capaId}/causes/${causeId}/whys`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  return json(response);
}

async function addWhy(token, capaId, body) {
  const response = await fetch(`${base}/api/actions/capas/${capaId}/whys`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  return json(response);
}

/**
 * A CAPA's causes as `{ id, category, sequence, statement, verdict,
 * evidenceNote }` — the shape every assertion here reads, so a test names what
 * it expects rather than counting rows.
 */
function causesOf(capa) {
  return capa.causes.map((cause) => ({
    id: cause.id,
    category: cause.category,
    sequence: cause.sequence,
    statement: cause.statement,
    verdict: cause.verdict,
    evidenceNote: cause.evidenceNote
  }));
}

function categoriesOf(capa) {
  return capa.causes.map((cause) => cause.category);
}

function causeWith(capa, statement) {
  return capa.causes.find((cause) => cause.statement === statement);
}

/**
 * Confirms a cause through the API — the way a team does it, and the only way
 * to reach the state a chain may be started from.
 */
async function confirmCause(token, capaId, causeId, note = 'The evidence backs it.') {
  const confirmed = await changeCause(token, capaId, causeId, {
    verdict: 'confirmed',
    evidenceNote: note
  });
  assert.strictEqual(confirmed.status, 200, JSON.stringify(confirmed.body));
  return confirmed;
}

/**
 * The ground every test starts from: a Site with an area and a line beneath it,
 * an engineer who may write at the line (the caller every permitted write is
 * made by), two Employees of the directory, and one Concern raised on the line
 * with a CAPA opened on it.
 */
async function makeGround({ teamLead = null, teamMembers = [] } = {}) {
  const site = await insertSite();
  const area = await insertOrgUnit(site.id, { name: 'Foundry' });
  const line = await insertOrgUnit(site.id, {
    parentId: area.id,
    unitType: 'line',
    name: 'Line 1'
  });

  const engineer = await insertAccount({
    displayName: 'Quality Engineer',
    grants: [{ orgUnitId: line.id, write: true, quality: true }]
  });
  const lead = await insertEmployee({ first: 'Ada', last: 'Lead' });
  const member = await insertEmployee({ first: 'Bo', last: 'Member' });

  const raised = await raiseConcern(engineer.token, site.id, {
    orgUnitId: line.id,
    title: 'The guard keeps working loose'
  });
  assert.strictEqual(raised.status, 201, `raising failed: ${JSON.stringify(raised.body)}`);

  const opened = await openCapa(engineer.token, raised.body.action.id, {
    teamLeadEmployeeId: teamLead === 'lead' ? lead.id : null,
    teamMemberEmployeeIds: teamMembers.includes('member') ? [member.id] : []
  });
  assert.strictEqual(opened.status, 201, `opening failed: ${JSON.stringify(opened.body)}`);

  return {
    site,
    area,
    line,
    engineer,
    lead,
    member,
    concern: raised.body.action,
    capa: opened.body.capa
  };
}

let admin;

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
});

test.after(async () => {
  // Children before parents, and the CAPA's own links first. Both halves of
  // `capa_root_causes` cascade from their CAPA, and so does the team — but the
  // Concern's `capa_id` does not: it is a plain foreign key, so the Actions
  // have to stop pointing at the CAPA *before* the CAPA row goes. Deleting in
  // the wrong order here does not fail fast: it rejects inside `test.after` and
  // hangs the whole run.
  if (insertedCapaIds.length > 0) {
    await pool.query('DELETE FROM capa_root_causes WHERE capa_id = ANY($1)', [insertedCapaIds]);
    await pool.query('DELETE FROM capa_team_members WHERE capa_id = ANY($1)', [insertedCapaIds]);
  }
  await pool.query('DELETE FROM action_items WHERE id = ANY($1)', [insertedActionIds]);
  if (insertedCapaIds.length > 0) {
    await pool.query('DELETE FROM capas WHERE id = ANY($1)', [insertedCapaIds]);
  }
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
// 1. Recording candidate causes, and the order the fishbone reads in
// ---------------------------------------------------------------------------

test('a candidate cause is added under one 6M category, changed and removed while the CAPA is open', async () => {
  const ground = await makeGround();
  const capaId = ground.capa.id;

  // A new CAPA has a fishbone and nothing on it, and its chains are untouched
  // by any of this: the fishbone sits beside them.
  assert.deepStrictEqual(ground.capa.causes, []);
  assert.deepStrictEqual(ground.capa.whys, []);

  const added = await addCause(ground.engineer.token, capaId, {
    category: 'machine',
    statement: 'The guard works loose after about 400 cycles.'
  });
  assert.strictEqual(added.status, 201, JSON.stringify(added.body));
  // A cause is recorded as a candidate: nobody has looked at it yet.
  assert.deepStrictEqual(causesOf(added.body.capa), [
    {
      id: causesOf(added.body.capa)[0].id,
      category: 'machine',
      sequence: 1,
      statement: 'The guard works loose after about 400 cycles.',
      verdict: 'candidate',
      evidenceNote: null
    }
  ]);
  const guardCauseId = added.body.capa.causes[0].id;

  // A second cause under the same category is the next branch of *that*
  // category, and a cause under another category starts its own list.
  const second = await addCause(ground.engineer.token, capaId, {
    category: 'machine',
    statement: 'Nothing checks the torque after a tool change.'
  });
  assert.strictEqual(second.status, 201, JSON.stringify(second.body));
  const method = await addCause(ground.engineer.token, capaId, {
    category: 'method',
    statement: 'The check sheet has no torque step on it.'
  });
  assert.strictEqual(method.status, 201, JSON.stringify(method.body));

  const machine = causesOf(method.body.capa).filter((cause) => cause.category === 'machine');
  const methods = causesOf(method.body.capa).filter((cause) => cause.category === 'method');
  assert.deepStrictEqual(
    machine.map((cause) => cause.sequence),
    [1, 2]
  );
  assert.deepStrictEqual(
    methods.map((cause) => cause.sequence),
    [1]
  );

  // The fishbone reads in the 6M's own order, not the order the causes were
  // written in: `environment` before `man` before `machine` before `method`.
  await addCause(ground.engineer.token, capaId, {
    category: 'environment',
    statement: 'The line runs hot in the afternoon.'
  });
  const man = await addCause(ground.engineer.token, capaId, {
    category: 'man',
    statement: 'Nobody on the afternoon shift has been shown the check.'
  });
  assert.strictEqual(man.status, 201, JSON.stringify(man.body));
  assert.deepStrictEqual(categoriesOf(man.body.capa), [
    'man',
    'machine',
    'machine',
    'method',
    'environment'
  ]);

  // Changing one: what it says, and which of the six it is filed under. A cause
  // may be re-filed — the team argues about whether a worn jig is Machine or
  // Method — where a Why never moves between chains.
  const revised = await changeCause(ground.engineer.token, capaId, guardCauseId, {
    statement: 'The guard works loose because the retaining bolt is not torqued.'
  });
  assert.strictEqual(revised.status, 200, JSON.stringify(revised.body));
  assert.strictEqual(
    causeWith(revised.body.capa, 'The guard works loose because the retaining bolt is not torqued.')
      .category,
    'machine'
  );

  const refiled = await changeCause(ground.engineer.token, capaId, guardCauseId, {
    category: 'method'
  });
  assert.strictEqual(refiled.status, 200, JSON.stringify(refiled.body));
  assert.deepStrictEqual(categoriesOf(refiled.body.capa), [
    'man',
    'machine',
    'method',
    'method',
    'environment'
  ]);

  // A body that names nothing is a 400 rather than a silent no-op, the shape
  // every other write in this slice takes.
  const nothing = await changeCause(ground.engineer.token, capaId, guardCauseId, {});
  assert.strictEqual(nothing.status, 400, JSON.stringify(nothing.body));

  // Removing one leaves the rest of the fishbone as it was.
  const removed = await removeCause(ground.engineer.token, capaId, guardCauseId);
  assert.strictEqual(removed.status, 200, JSON.stringify(removed.body));
  assert.strictEqual(removed.body.capa.causes.length, 4);
  assert.ok(!causesOf(removed.body.capa).some((cause) => cause.id === guardCauseId));

  // Nothing any of that did reached the chains, and the read agrees.
  const read = await readCapa(ground.engineer.token, capaId);
  assert.strictEqual(read.status, 200, JSON.stringify(read.body));
  assert.strictEqual(read.body.capa.causes.length, 4);
  assert.deepStrictEqual(read.body.capa.whys, []);

  // An unknown or malformed cause id, and an unknown CAPA, are 404s.
  const unknown = await changeCause(ground.engineer.token, capaId, 999999999, {
    statement: 'Nowhere.'
  });
  assert.strictEqual(unknown.status, 404, JSON.stringify(unknown.body));
  const malformed = await removeCause(ground.engineer.token, capaId, 'not-an-id');
  assert.strictEqual(malformed.status, 404, JSON.stringify(malformed.body));
  const missingCapa = await addCause(ground.engineer.token, 999999999, {
    category: 'machine',
    statement: 'Nowhere.'
  });
  assert.strictEqual(missingCapa.status, 404, JSON.stringify(missingCapa.body));
});

// ---------------------------------------------------------------------------
// 2. The 6M set, and what a cause must say
// ---------------------------------------------------------------------------

test('a cause is filed under one of the 6M categories, and each of the two fields is checked', async () => {
  const ground = await makeGround();
  const capaId = ground.capa.id;

  // The set is the CHECK's own six, and the 400 names them rather than letting
  // a raw 23514 out of the database.
  const wrongCategory = await addCause(ground.engineer.token, capaId, {
    category: 'people',
    statement: 'Not one of the six.'
  });
  assert.strictEqual(wrongCategory.status, 400, JSON.stringify(wrongCategory.body));
  assert.match(
    wrongCategory.body.message,
    /category must be one of: man, machine, method, material, measurement, environment/
  );

  const missingCategory = await addCause(ground.engineer.token, capaId, {
    statement: 'Filed under nothing.'
  });
  assert.strictEqual(missingCategory.status, 400, JSON.stringify(missingCategory.body));

  // A cause has to say something: an empty branch is worse than no branch.
  const empty = await addCause(ground.engineer.token, capaId, {
    category: 'machine',
    statement: '   '
  });
  assert.strictEqual(empty.status, 400, JSON.stringify(empty.body));
  assert.match(empty.body.message, /statement/);
  const typed = await addCause(ground.engineer.token, capaId, {
    category: 'machine',
    statement: 42
  });
  assert.strictEqual(typed.status, 400, JSON.stringify(typed.body));

  const added = await addCause(ground.engineer.token, capaId, {
    category: 'machine',
    statement: 'The guard works loose.'
  });
  assert.strictEqual(added.status, 201, JSON.stringify(added.body));
  const causeId = added.body.capa.causes[0].id;

  // The same two rules apply to a change.
  const badMove = await changeCause(ground.engineer.token, capaId, causeId, {
    category: 'environment'
  });
  assert.strictEqual(badMove.status, 200, JSON.stringify(badMove.body));
  const notAValue = await changeCause(ground.engineer.token, capaId, causeId, {
    category: 'environmental'
  });
  assert.strictEqual(notAValue.status, 400, JSON.stringify(notAValue.body));
  assert.match(notAValue.body.message, /category must be one of:/);
  const blanked = await changeCause(ground.engineer.token, capaId, causeId, { statement: '' });
  assert.strictEqual(blanked.status, 400, JSON.stringify(blanked.body));

  // Nothing was written by any of the refusals.
  const read = await readCapa(ground.engineer.token, capaId);
  assert.deepStrictEqual(causesOf(read.body.capa), [
    {
      id: causeId,
      category: 'environment',
      sequence: 1,
      statement: 'The guard works loose.',
      verdict: 'candidate',
      evidenceNote: null
    }
  ]);
});

// ---------------------------------------------------------------------------
// 3. The verdict, and the evidence it takes
// ---------------------------------------------------------------------------

test('a cause is a candidate until it is decided, and deciding it needs the evidence', async () => {
  const ground = await makeGround();
  const capaId = ground.capa.id;

  const added = await addCause(ground.engineer.token, capaId, {
    category: 'measurement',
    statement: 'The gauge reads 0.2mm under.'
  });
  const causeId = added.body.capa.causes[0].id;

  // Confirming without the evidence is a 400 — the ticket's own rule, and the
  // reason the note is required in the same request rather than remembered from
  // an earlier one.
  const noNote = await changeCause(ground.engineer.token, capaId, causeId, {
    verdict: 'confirmed'
  });
  assert.strictEqual(noNote.status, 400, JSON.stringify(noNote.body));
  assert.match(noNote.body.message, /evidence/);
  const blankNote = await changeCause(ground.engineer.token, capaId, causeId, {
    verdict: 'confirmed',
    evidenceNote: '   '
  });
  assert.strictEqual(blankNote.status, 400, JSON.stringify(blankNote.body));
  const ruledOutNoNote = await changeCause(ground.engineer.token, capaId, causeId, {
    verdict: 'ruled_out'
  });
  assert.strictEqual(ruledOutNoNote.status, 400, JSON.stringify(ruledOutNoNote.body));

  // A verdict outside the three is a 400 naming them.
  const nonsense = await changeCause(ground.engineer.token, capaId, causeId, {
    verdict: 'maybe',
    evidenceNote: 'Something.'
  });
  assert.strictEqual(nonsense.status, 400, JSON.stringify(nonsense.body));
  assert.match(nonsense.body.message, /verdict must be one of: candidate, confirmed, ruled_out/);

  // The refusals wrote nothing: the cause is still a candidate with no note.
  const still = await readCapa(ground.engineer.token, capaId);
  assert.strictEqual(causeWith(still.body.capa, 'The gauge reads 0.2mm under.').verdict, 'candidate');
  assert.strictEqual(still.body.capa.causes[0].evidenceNote, null);

  // Confirmed, with the evidence: the verdict and the note land together.
  const confirmed = await changeCause(ground.engineer.token, capaId, causeId, {
    verdict: 'confirmed',
    evidenceNote: 'The calibration tag expired in March and the reference block measures true.'
  });
  assert.strictEqual(confirmed.status, 200, JSON.stringify(confirmed.body));
  const decided = confirmed.body.capa.causes[0];
  assert.strictEqual(decided.verdict, 'confirmed');
  assert.strictEqual(
    decided.evidenceNote,
    'The calibration tag expired in March and the reference block measures true.'
  );

  // Changing the verdict takes its own evidence: the note belongs to the
  // verdict it was written for.
  const flipped = await changeCause(ground.engineer.token, capaId, causeId, {
    verdict: 'ruled_out'
  });
  assert.strictEqual(flipped.status, 400, JSON.stringify(flipped.body));
  const flippedWithNote = await changeCause(ground.engineer.token, capaId, causeId, {
    verdict: 'ruled_out',
    evidenceNote: 'The second gauge reads the same, so the block is fine.'
  });
  assert.strictEqual(flippedWithNote.status, 200, JSON.stringify(flippedWithNote.body));
  assert.strictEqual(flippedWithNote.body.capa.causes[0].verdict, 'ruled_out');

  // The evidence of a decision already made can be edited without deciding
  // again — and only a decided cause has evidence to edit.
  const edited = await changeCause(ground.engineer.token, capaId, causeId, {
    evidenceNote: 'Both gauges read the same against the reference block, so neither drifted.'
  });
  assert.strictEqual(edited.status, 200, JSON.stringify(edited.body));
  assert.strictEqual(
    edited.body.capa.causes[0].evidenceNote,
    'Both gauges read the same against the reference block, so neither drifted.'
  );

  // Back to a candidate: the cause is under review again, and the evidence of
  // the decision that was unmade goes with it.
  const reopened = await changeCause(ground.engineer.token, capaId, causeId, {
    verdict: 'candidate'
  });
  assert.strictEqual(reopened.status, 200, JSON.stringify(reopened.body));
  assert.strictEqual(reopened.body.capa.causes[0].verdict, 'candidate');
  assert.strictEqual(reopened.body.capa.causes[0].evidenceNote, null);

  // A note on something that is (or is being made) a candidate is a 400: there
  // is no verdict for the evidence to be the evidence of.
  const noteAlone = await changeCause(ground.engineer.token, capaId, causeId, {
    evidenceNote: 'Evidence for nothing.'
  });
  assert.strictEqual(noteAlone.status, 400, JSON.stringify(noteAlone.body));
  const noteWithCandidate = await changeCause(ground.engineer.token, capaId, causeId, {
    verdict: 'candidate',
    evidenceNote: 'Evidence for nothing.'
  });
  assert.strictEqual(noteWithCandidate.status, 400, JSON.stringify(noteWithCandidate.body));

  // A second cause decided `ruled_out` from the start, which is how most of a
  // fishbone ends up: the causes that were not it.
  const other = await addCause(ground.engineer.token, capaId, {
    category: 'man',
    statement: 'The operator skipped the torque step.'
  });
  const otherId = other.body.capa.causes.find((cause) => cause.category === 'man').id;
  const ruledOut = await changeCause(ground.engineer.token, capaId, otherId, {
    verdict: 'ruled_out',
    evidenceNote: 'The torque log shows every cycle signed off that shift.'
  });
  assert.strictEqual(ruledOut.status, 200, JSON.stringify(ruledOut.body));

  // The two verdicts live side by side on the read, each with its own evidence.
  const read = await readCapa(ground.engineer.token, capaId);
  assert.deepStrictEqual(
    causesOf(read.body.capa).map((cause) => [cause.category, cause.verdict]),
    [
      ['man', 'ruled_out'],
      ['measurement', 'candidate']
    ]
  );
});

// ---------------------------------------------------------------------------
// 4. Starting a chain from a confirmed cause
// ---------------------------------------------------------------------------

test("a chain's first Why is started from a confirmed cause, and from no other", async () => {
  const ground = await makeGround();
  const capaId = ground.capa.id;

  const added = await addCause(ground.engineer.token, capaId, {
    category: 'machine',
    statement: 'The retaining bolt is not torqued after a tool change.'
  });
  const causeId = added.body.capa.causes[0].id;

  // A candidate is a suspicion: a chain cannot start from one.
  const fromCandidate = await startWhyFromCause(ground.engineer.token, capaId, causeId, {
    chain: 'occurrence'
  });
  assert.strictEqual(fromCandidate.status, 409, JSON.stringify(fromCandidate.body));
  assert.match(fromCandidate.body.message, /only a confirmed cause/);

  // Nor from one the evidence killed.
  const ruledOut = await changeCause(ground.engineer.token, capaId, causeId, {
    verdict: 'ruled_out',
    evidenceNote: 'The bolt is thread-locked and the log is complete.'
  });
  assert.strictEqual(ruledOut.status, 200, JSON.stringify(ruledOut.body));
  const fromRuledOut = await startWhyFromCause(ground.engineer.token, capaId, causeId, {
    chain: 'occurrence'
  });
  assert.strictEqual(fromRuledOut.status, 409, JSON.stringify(fromRuledOut.body));
  assert.match(fromRuledOut.body.message, /ruled_out/);

  // Confirmed, and the chain starts: the first Why is the cause's own sentence.
  await confirmCause(ground.engineer.token, capaId, causeId, 'The log is missing that cycle.');
  const started = await startWhyFromCause(ground.engineer.token, capaId, causeId, {
    chain: 'occurrence'
  });
  assert.strictEqual(started.status, 201, JSON.stringify(started.body));
  const firstWhy = started.body.capa.whys[0];
  assert.strictEqual(firstWhy.chain, 'occurrence');
  assert.strictEqual(firstWhy.sequence, 1);
  assert.strictEqual(firstWhy.statement, 'The retaining bolt is not torqued after a tool change.');
  assert.strictEqual(firstWhy.isRoot, false);
  // And the fishbone is still there, beside it, with its verdict.
  assert.strictEqual(started.body.capa.causes.length, 1);
  assert.strictEqual(started.body.capa.causes[0].verdict, 'confirmed');

  // A chain begins once: its first Why is already written, and the honest way
  // to add the next one is #210's own address.
  const again = await startWhyFromCause(ground.engineer.token, capaId, causeId, {
    chain: 'occurrence'
  });
  assert.strictEqual(again.status, 409, JSON.stringify(again.body));
  assert.match(again.body.message, /already been started/);

  // The second chain starts from its own confirmed cause, with a Why phrased
  // by the team rather than copied from the cause.
  const escapeCause = await addCause(ground.engineer.token, capaId, {
    category: 'measurement',
    statement: 'Nothing measures the torque on the line.'
  });
  const escapeCauseId = escapeCause.body.capa.causes.find(
    (cause) => cause.category === 'measurement'
  ).id;
  await confirmCause(ground.engineer.token, capaId, escapeCauseId, 'No gauge on the line.');
  const escapeStarted = await startWhyFromCause(
    ground.engineer.token,
    capaId,
    escapeCauseId,
    { chain: 'escape', statement: 'Why did nobody measure the torque at the end of the line?' }
  );
  assert.strictEqual(escapeStarted.status, 201, JSON.stringify(escapeStarted.body));
  assert.deepStrictEqual(
    escapeStarted.body.capa.whys.map((why) => [why.chain, why.sequence, why.statement]),
    [
      ['occurrence', 1, 'The retaining bolt is not torqued after a tool change.'],
      ['escape', 1, 'Why did nobody measure the torque at the end of the line?']
    ]
  );

  // A chain that has started refuses every cause, confirmed or not: which cause
  // it began from is decided once.
  const thirdCause = await addCause(ground.engineer.token, capaId, {
    category: 'method',
    statement: 'The checklist has no torque step.'
  });
  const thirdCauseId = thirdCause.body.capa.causes.find((cause) => cause.category === 'method').id;
  await confirmCause(ground.engineer.token, capaId, thirdCauseId, 'The sheet was pulled.');
  const occupied = await startWhyFromCause(ground.engineer.token, capaId, thirdCauseId, {
    chain: 'occurrence'
  });
  assert.strictEqual(occupied.status, 409, JSON.stringify(occupied.body));
  assert.match(occupied.body.message, /already been started/);

  // The chain it started is a chain #210 can go on with: a second Why lands at
  // position 2 of the chain the cause began.
  const next = await addWhy(ground.engineer.token, capaId, {
    chain: 'occurrence',
    statement: 'Because the tool change happens between shifts.'
  });
  assert.strictEqual(next.status, 201, JSON.stringify(next.body));
  assert.deepStrictEqual(
    next.body.capa.whys
      .filter((why) => why.chain === 'occurrence')
      .map((why) => [why.sequence, why.statement]),
    [
      [1, 'The retaining bolt is not torqued after a tool change.'],
      [2, 'Because the tool change happens between shifts.']
    ]
  );

  // The chain must be one of the two, the cause must be one of this CAPA's, and
  // a Why is not a cause — the fishbone half is not a second way to write a
  // chain.
  const wrongChain = await startWhyFromCause(ground.engineer.token, capaId, causeId, {
    chain: 'detection'
  });
  assert.strictEqual(wrongChain.status, 400, JSON.stringify(wrongChain.body));
  assert.match(wrongChain.body.message, /chain must be one of: occurrence, escape/);
  const unknownCause = await startWhyFromCause(ground.engineer.token, capaId, 999999999, {
    chain: 'escape'
  });
  assert.strictEqual(unknownCause.status, 404, JSON.stringify(unknownCause.body));
  const aWhyIsNotACause = await startWhyFromCause(
    ground.engineer.token,
    capaId,
    firstWhy.id,
    { chain: 'escape' }
  );
  assert.strictEqual(aWhyIsNotACause.status, 404, JSON.stringify(aWhyIsNotACause.body));
});

// ---------------------------------------------------------------------------
// 5. The access rule the fishbone shares with the chains, and a closed CAPA
// ---------------------------------------------------------------------------

test('writing the fishbone needs edit access at the CAPA Org Unit or a place on its team', async () => {
  const ground = await makeGround({ teamLead: 'lead', teamMembers: ['member'] });
  const capaId = ground.capa.id;

  const added = await addCause(ground.engineer.token, capaId, {
    category: 'machine',
    statement: 'The guard works loose.'
  });
  assert.strictEqual(added.status, 201, JSON.stringify(added.body));
  const causeId = added.body.capa.causes[0].id;

  // Nobody: an Account with no Grant anywhere and no place on the team. All
  // four writes are refused, and the refusal says what would have been needed —
  // the same words the chains use, because it is the same rule.
  const stranger = await insertAccount({ displayName: 'Nobody In Particular' });
  const refusedAdd = await addCause(stranger.token, capaId, {
    category: 'method',
    statement: 'Not this caller to write.'
  });
  assert.strictEqual(refusedAdd.status, 403, JSON.stringify(refusedAdd.body));
  assert.match(refusedAdd.body.message, /edit access|place on its team/);
  const refusedChange = await changeCause(stranger.token, capaId, causeId, {
    verdict: 'confirmed',
    evidenceNote: 'Not this caller to write.'
  });
  assert.strictEqual(refusedChange.status, 403, JSON.stringify(refusedChange.body));
  const refusedRemove = await removeCause(stranger.token, capaId, causeId);
  assert.strictEqual(refusedRemove.status, 403, JSON.stringify(refusedRemove.body));
  const refusedStart = await startWhyFromCause(stranger.token, capaId, causeId, {
    chain: 'occurrence'
  });
  assert.strictEqual(refusedStart.status, 403, JSON.stringify(refusedStart.body));

  // A read Grant is not edit access: reading a CAPA is Site-wide, writing one
  // is not.
  const reader = await insertAccount({
    displayName: 'Line Reader',
    grants: [{ orgUnitId: ground.line.id, write: false }]
  });
  const alsoRefused = await addCause(reader.token, capaId, {
    category: 'method',
    statement: 'Read, and nothing more.'
  });
  assert.strictEqual(alsoRefused.status, 403, JSON.stringify(alsoRefused.body));

  // Nothing any of them sent landed.
  const unchanged = await readCapa(ground.engineer.token, capaId);
  assert.deepStrictEqual(
    causesOf(unchanged.body.capa).map((cause) => cause.statement),
    ['The guard works loose.']
  );

  // A place on the team is enough on its own: an Account with no Grant at all
  // whose Employee is a member of this CAPA's team writes the fishbone, decides
  // a cause, and starts a chain from it. This is the whole "or".
  const memberAccount = await insertAccount({
    displayName: 'Bo Member',
    employeeId: ground.member.id
  });
  const byTeam = await addCause(memberAccount.token, capaId, {
    category: 'method',
    statement: 'The check sheet has no torque step.'
  });
  assert.strictEqual(byTeam.status, 201, JSON.stringify(byTeam.body));
  const byTeamCauseId = byTeam.body.capa.causes.find(
    (cause) => cause.category === 'method'
  ).id;
  const decidedByTeam = await changeCause(memberAccount.token, capaId, byTeamCauseId, {
    verdict: 'confirmed',
    evidenceNote: 'The sheet is pinned to the bench and has no torque step.'
  });
  assert.strictEqual(decidedByTeam.status, 200, JSON.stringify(decidedByTeam.body));
  const startedByTeam = await startWhyFromCause(memberAccount.token, capaId, byTeamCauseId, {
    chain: 'escape'
  });
  assert.strictEqual(startedByTeam.status, 201, JSON.stringify(startedByTeam.body));

  // The lead is on the team as much as the members are.
  const leadAccount = await insertAccount({
    displayName: 'Ada Lead',
    employeeId: ground.lead.id
  });
  const removedByLead = await removeCause(leadAccount.token, capaId, causeId);
  assert.strictEqual(removedByLead.status, 200, JSON.stringify(removedByLead.body));

  // Reading the fishbone is Site-wide, the same as reading any Action: scope
  // decides where somebody may act, not what they may read. The stranger reads
  // the fishbone with its verdict — the machine cause the lead removed is gone,
  // and the confirmed one is what is left.
  const readable = await readCapa(stranger.token, capaId);
  assert.strictEqual(readable.status, 200, JSON.stringify(readable.body));
  assert.deepStrictEqual(
    causesOf(readable.body.capa).map((cause) => [cause.category, cause.verdict]),
    [['method', 'confirmed']]
  );

  // An Employee of the directory who holds no Grant and is on no team is still
  // nobody, even though their Account is linked to a real person.
  const bystander = await insertAccount({
    displayName: 'Cyd Bystander',
    employeeId: (await insertEmployee({ first: 'Cyd', last: 'Bystander' })).id
  });
  const bystanderRefused = await addCause(bystander.token, capaId, {
    category: 'environment',
    statement: 'A real person, and still not on the team.'
  });
  assert.strictEqual(bystanderRefused.status, 403, JSON.stringify(bystanderRefused.body));
});

test('a closed CAPA refuses every write to its fishbone', async () => {
  const site = await insertSite();
  const line = await insertOrgUnit(site.id, { unitType: 'line', name: 'Line 2' });
  const engineer = await insertAccount({
    displayName: 'Quality Engineer',
    grants: [{ orgUnitId: line.id, write: true, quality: true }]
  });

  for (const status of ['closed', 'cancelled']) {
    // Written straight into the table (see this file's header): closing a CAPA
    // is #211's own ticket and no request on this branch produces this row.
    const closed = await insertClosedCapa(line.id, status);

    const added = await addCause(engineer.token, closed.id, {
      category: 'machine',
      statement: 'Nothing may be recorded here any more.'
    });
    assert.strictEqual(added.status, 409, JSON.stringify(added.body));
    assert.match(added.body.message, new RegExp(`this CAPA is ${status}`));

    // The other three writes are refused the same way, and the ids in their
    // addresses are never reached: the CAPA is the record that is frozen.
    const changed = await changeCause(engineer.token, closed.id, 1, {
      verdict: 'confirmed',
      evidenceNote: 'Anything.'
    });
    assert.strictEqual(changed.status, 409, JSON.stringify(changed.body));
    const removed = await removeCause(engineer.token, closed.id, 1);
    assert.strictEqual(removed.status, 409, JSON.stringify(removed.body));
    const started = await startWhyFromCause(engineer.token, closed.id, 1, {
      chain: 'occurrence'
    });
    assert.strictEqual(started.status, 409, JSON.stringify(started.body));

    // Nothing was written, and the refusal is not the row's fault: it reads
    // back with the status it was given and an empty fishbone.
    const read = await readCapa(engineer.token, closed.id);
    assert.strictEqual(read.status, 200, JSON.stringify(read.body));
    assert.strictEqual(read.body.capa.status, status);
    assert.deepStrictEqual(read.body.capa.causes, []);
  }

  // Scope is asked before status, and deliberately: a caller with neither edit
  // access nor a place on the team gets the 403 the route can answer without
  // reading the row's own state, and only somebody who may write at all learns
  // whether the investigation is over. An unknown CAPA is a 404 before both.
  const stranger = await insertAccount({ displayName: 'Nobody In Particular' });
  const closed = await insertClosedCapa(line.id, 'closed');
  const refused = await addCause(stranger.token, closed.id, {
    category: 'machine',
    statement: 'Not this caller, on a closed CAPA.'
  });
  assert.strictEqual(refused.status, 403, JSON.stringify(refused.body));

  // An administrator passes the scope half everywhere, through `canAct`, and
  // still meets the same 409 on a closed record.
  const asAdmin = await addCause(admin.token, closed.id, {
    category: 'machine',
    statement: 'An administrator writes, and the record is still frozen.'
  });
  assert.strictEqual(asAdmin.status, 409, JSON.stringify(asAdmin.body));
});
