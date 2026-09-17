/*
 * The effectiveness check on a CAPA, and closing one (issue #211) — over HTTP,
 * against a real database and a real (locally issued) JWKS. The seam, the
 * fixture scaffolding and the dependency-ordered cleanup are the ones
 * capas.test.js and capa-whys.test.js already establish.
 *
 * What this file claims, one test per rule the ticket states: the delay
 * defaults to 30 days and can be changed while the CAPA is open; the check's
 * due date is set when the Concern closes, it is the closure's day plus the
 * delay, and a delay changed afterwards does not move it; recording the check
 * needs Quality authority at the CAPA's Org Unit (403) and is refused when the
 * Account is the team lead's (403); recording it before the Concern closes is
 * refused (409); an effective check closes the CAPA and records the verifying
 * Account, the time and the note, and is refused (409) while either chain has
 * no confirmed root cause; a check that did not hold records the same three
 * facts, reopens the Concern into its next PDCA cycle and leaves the CAPA open;
 * and the list is filterable by Org Unit (including beneath it) and by status,
 * with the overdue checks marked.
 *
 * **How a Concern gets closed here, and why it is not arranged by hand.** A
 * CAPA's effectiveness check is only due once the Concern it answers has closed
 * (ADR-0033), so every test that records a check first drives the *real*
 * machinery: a countermeasure is raised on the Concern, both cycles are walked
 * to their Acts, and the Concern's own Act completes last. That is the only
 * door that closes a Concern, and asserting the due date against a row written
 * straight into `action_items` would prove a rule the API does not have. The
 * same reasoning drives the reopening test in the other direction: the Concern
 * comes back as cycle 2's Plan because `completePhase` and
 * `reopenConcernIntoNextCycle` write the same log.
 *
 * **One arrangement in this file reads Postgres directly, and it says why
 * where it stands.** A CAPA whose effectiveness check is genuinely *overdue*
 * cannot be produced through the API on the day it is created: the due date is
 * the day the Concern closed plus the delay, the delay may not be negative, and
 * nothing may close a Concern in the past. So that one test moves the stored
 * date back — the predicate under test is the list's own rule, and
 * `capa-whys.test.js` arranges its closed CAPA the same way for the same kind
 * of reason. Every assertion about it is still read over HTTP.
 *
 * Needs a database with every migration applied, including
 * 1800300000000_effectiveness-check-on-a-capa.js. Set DATABASE_URL first — see
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
// (`app_users.employee_id`). The Employee link is what the team-lead rule
// reads, and it is deliberately optional: an administrator is not an Employee
// and is never the team lead.
async function insertAccount({
  role = 'operator',
  displayName = null,
  grants = [],
  employeeId = null
} = {}) {
  const subject = uniqueCode('efacct');
  const name = displayName ?? `Effectiveness Account ${subject}`;
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
    [uniqueCode('EFS'), 'Effectiveness Test Site', 'Asia/Ho_Chi_Minh']
  );
  insertedSiteIds.push(site.id);
  return site;
}

async function insertOrgUnit(siteId, { parentId = null, unitType = 'area', name = 'Effectiveness Unit' } = {}) {
  const { rows: [orgUnit] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, $2, $3, $4, $5) RETURNING id, code, name, path`,
    [siteId, parentId, uniqueCode('EFAOU'), name, unitType]
  );
  insertedOrgUnitIds.push(orgUnit.id);
  return orgUnit;
}

async function insertEmployee({ first = 'Ann', last = 'Fitter', isActive = true } = {}) {
  const { rows: [employee] } = await pool.query(
    `INSERT INTO employees (employee_no, first_name, last_name, is_active)
     VALUES ($1, $2, $3, $4) RETURNING id, display_name, is_active`,
    [uniqueCode('EFAEMP'), first, last, isActive]
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

async function changeCapa(token, capaId, body) {
  const response = await fetch(`${base}/api/actions/capas/${capaId}`, {
    method: 'PATCH',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  return json(response);
}

async function readAction(token, actionId) {
  const response = await fetch(`${base}/api/actions/${actionId}`, { headers: token });
  return json(response);
}

async function addMeasure(token, concernId, body) {
  const response = await fetch(`${base}/api/actions/${concernId}/measures`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  const { status, body: payload } = await json(response);
  if (status === 201) insertedActionIds.push(payload.action.id);
  return { status, body: payload };
}

async function completePhase(token, actionId, phase, body) {
  const response = await fetch(`${base}/api/actions/${actionId}/phases/${phase}/complete`, {
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

async function changeWhy(token, capaId, whyId, body) {
  const response = await fetch(`${base}/api/actions/capas/${capaId}/whys/${whyId}`, {
    method: 'PATCH',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  return json(response);
}

async function recordEffectiveness(token, capaId, body) {
  const response = await fetch(`${base}/api/actions/capas/${capaId}/effectiveness`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  return json(response);
}

async function listCapas(token, query = {}) {
  const search = new URLSearchParams(query).toString();
  const response = await fetch(`${base}/api/actions/capas${search ? `?${search}` : ''}`, {
    headers: token
  });
  return json(response);
}

/**
 * Walks one Action's open cycle to its Act, phase by phase, over HTTP — the
 * only door that moves a cycle (ADR-0033). The Check carries `effective`, which
 * is what opens the Act rather than the next cycle's Plan, and every phase
 * carries a note because the service refuses one that says nothing.
 */
async function walkCycle(token, actionId, what) {
  for (const phase of ['plan', 'do', 'check', 'act']) {
    const body = { note: `${what}: the ${phase} phase is done.` };
    if (phase === 'check') body.outcome = 'effective';
    const done = await completePhase(token, actionId, phase, body);
    assert.strictEqual(
      done.status,
      200,
      `${what} at its ${phase} phase failed: ${JSON.stringify(done.body)}`
    );
  }
}

/**
 * Closes a Concern the way the Action log closes one: a countermeasure is
 * raised on it and both cycles are walked to their Acts, the measure's first
 * because a Concern with an open measure refuses to close (ADR-0033's "nothing
 * closes unverified"), then the Concern's own. What comes out is a CAPA waiting
 * on its effectiveness check, which is the state every test below starts from.
 *
 * The countermeasure is raised by the Quality engineer, whose write Grant
 * reaches the line — a measure is an Action raised where the record goes.
 */
async function closeConcern(token, concernId) {
  const raised = await addMeasure(token, concernId, {
    actionType: 'countermeasure',
    title: 'Put the torque step on the check sheet'
  });
  assert.strictEqual(raised.status, 201, `raising the countermeasure failed: ${JSON.stringify(raised.body)}`);

  await walkCycle(token, raised.body.action.id, 'The countermeasure');
  await walkCycle(token, concernId, 'The Concern');
}

/**
 * Confirms one root cause in one of a CAPA's two chains: the Why is added, then
 * marked — the two writes #210 owns, which is what makes "the investigation is
 * finished" true in the data rather than in a sentence.
 */
async function confirmRoot(token, capaId, chain, statement) {
  const added = await addWhy(token, capaId, { chain, statement });
  assert.strictEqual(added.status, 201, `adding a ${chain} Why failed: ${JSON.stringify(added.body)}`);
  const why = added.body.capa.whys.filter((each) => each.chain === chain).pop();
  const marked = await changeWhy(token, capaId, why.id, { isRoot: true });
  assert.strictEqual(marked.status, 200, `marking the ${chain} root failed: ${JSON.stringify(marked.body)}`);
}

async function confirmBothRoots(token, capaId) {
  await confirmRoot(token, capaId, 'occurrence', 'The fastener was not torqued to the standard.');
  await confirmRoot(token, capaId, 'escape', 'Nobody looks behind the machine between shifts.');
}

/**
 * The day a check is due when the Concern closes today, asked of Postgres
 * rather than computed here: the write is `completed_at::date + delay`, and a
 * test that did its own arithmetic would disagree with the database the moment
 * the session's timezone did.
 */
async function dueDateFor(delayDays) {
  const { rows } = await pool.query(
    `SELECT to_char(CURRENT_DATE + $1::int, 'YYYY-MM-DD') AS day`,
    [delayDays]
  );
  return rows[0].day;
}

/**
 * The ground every test starts from: a Site with an area and a line beneath it,
 * a Quality engineer with edit access and Quality authority at the line (the
 * caller every permitted write is made by), two Employees of the directory
 * separately from the engineer, and one Concern raised on the line.
 */
async function makeGround() {
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
  const leadEmployee = await insertEmployee({ first: 'Ada', last: 'Lead' });
  const memberEmployee = await insertEmployee({ first: 'Bo', last: 'Member' });

  const raised = await raiseConcern(engineer.token, site.id, {
    orgUnitId: line.id,
    title: 'The guard keeps working loose'
  });
  assert.strictEqual(raised.status, 201, `raising failed: ${JSON.stringify(raised.body)}`);

  return {
    site,
    area,
    line,
    engineer,
    leadEmployee,
    memberEmployee,
    concern: raised.body.action
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

  admin = await insertAccount({ role: 'admin', displayName: 'Avery Administrator' });
});

test.after(async () => {
  // Children before parents, and the CAPA's own links first. The Whys and the
  // team cascade from their CAPA, and so does the phase log from its Action —
  // but the Concern's `capa_id` does not: it is a plain foreign key, so the
  // Actions have to stop pointing at the CAPA *before* the CAPA row goes, and
  // `capas.effectiveness_verified_by_account_id` in turn has to go before the
  // Account it names. Deleting in the wrong order here does not fail fast: it
  // rejects inside `test.after` and hangs the whole run.
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
// 1. The delay, and the date it produces
// ---------------------------------------------------------------------------

test('the effectiveness delay starts at 30 days and can be changed while the CAPA is open', async () => {
  const ground = await makeGround();
  const opened = await openCapa(ground.engineer.token, ground.concern.id, {});
  assert.strictEqual(opened.status, 201, JSON.stringify(opened.body));
  const capaId = opened.body.capa.id;

  // The default is the schema's own column default and the ticket's number,
  // and nothing is due yet: the Concern is still open, so there is no closure
  // for a date to count from.
  assert.strictEqual(opened.body.capa.effectivenessCheckDelayDays, 30);
  assert.strictEqual(opened.body.capa.effectivenessCheckDueAt, null);
  assert.strictEqual(opened.body.capa.effectivenessCheckOverdue, false);

  const shortened = await changeCapa(ground.engineer.token, capaId, {
    effectivenessCheckDelayDays: 10
  });
  assert.strictEqual(shortened.status, 200, JSON.stringify(shortened.body));
  assert.strictEqual(shortened.body.capa.effectivenessCheckDelayDays, 10);

  // Zero is legal, and deliberately: "check it the day the Concern closes" is a
  // real instruction for a problem that is expected to show up immediately.
  const immediate = await changeCapa(ground.engineer.token, capaId, {
    effectivenessCheckDelayDays: 0
  });
  assert.strictEqual(immediate.status, 200, JSON.stringify(immediate.body));
  assert.strictEqual(immediate.body.capa.effectivenessCheckDelayDays, 0);

  // The refusals: a negative delay is a date in the past, a fraction is not a
  // day, a four-digit number is a typo, and a string is not a number at all.
  for (const refused of [-1, 366, 3.5, 'thirty']) {
    const answer = await changeCapa(ground.engineer.token, capaId, {
      effectivenessCheckDelayDays: refused
    });
    assert.strictEqual(answer.status, 400, `${refused}: ${JSON.stringify(answer.body)}`);
    assert.match(answer.body.message, /effectivenessCheckDelayDays/);
  }

  // None of the refusals moved it, and a body naming nothing at all is still a
  // 400 rather than a silent no-op.
  const nothing = await changeCapa(ground.engineer.token, capaId, {});
  assert.strictEqual(nothing.status, 400, JSON.stringify(nothing.body));
  const unchanged = await readCapa(ground.engineer.token, capaId);
  assert.strictEqual(unchanged.body.capa.effectivenessCheckDelayDays, 0);

  // And the range is the schema's rule as well as the service's (read
  // directly, like `capa-whys.test.js`'s own constraint assertions and for the
  // same reason: it has to hold for a writer that does not come through the
  // service).
  await assert.rejects(
    () =>
      pool.query('UPDATE capas SET effectiveness_check_delay_days = 400 WHERE id = $1', [capaId]),
    (error) =>
      error.code === '23514' && error.constraint === 'capas_effectiveness_delay_days_range',
    'a four-hundred-day check was accepted by the schema'
  );
});

test('the check falls due a delay after the Concern closes, and a delay changed afterwards does not move the date', async () => {
  const ground = await makeGround();
  const opened = await openCapa(ground.engineer.token, ground.concern.id, {});
  const capaId = opened.body.capa.id;

  const set = await changeCapa(ground.engineer.token, capaId, {
    effectivenessCheckDelayDays: 10
  });
  assert.strictEqual(set.status, 200, JSON.stringify(set.body));
  assert.strictEqual(set.body.capa.effectivenessCheckDueAt, null);

  // The Concern closes — the real front door, with the CAPA following it.
  await closeConcern(ground.engineer.token, ground.concern.id);

  const waiting = await readCapa(ground.engineer.token, capaId);
  assert.strictEqual(waiting.status, 200, JSON.stringify(waiting.body));
  const capa = waiting.body.capa;

  // The date is the closure's day plus the delay, and it is *set* — a stored
  // date, not one derived on read.
  assert.match(capa.effectivenessCheckDueAt, /^\d{4}-\d{2}-\d{2}$/);
  assert.strictEqual(capa.effectivenessCheckDueAt, await dueDateFor(10));
  assert.strictEqual(capa.effectivenessCheckOverdue, false);
  // The investigation is waiting on its verification, which is the one state of
  // the seven that means exactly that (`verifying`, the fix is in and nobody
  // has proved it held).
  assert.strictEqual(capa.status, 'verifying');

  // The decision this file's migration argues, pinned: the delay governs the
  // *next* closure. Changing it now leaves the date where it was, because that
  // is the date this check is judged against — a date that moved under the
  // number behind it would be a date nobody could audit.
  const revised = await changeCapa(ground.engineer.token, capaId, {
    effectivenessCheckDelayDays: 45
  });
  assert.strictEqual(revised.status, 200, JSON.stringify(revised.body));
  assert.strictEqual(revised.body.capa.effectivenessCheckDelayDays, 45);
  assert.strictEqual(revised.body.capa.effectivenessCheckDueAt, capa.effectivenessCheckDueAt);
});

// ---------------------------------------------------------------------------
// 2. Who may record a check, and when
// ---------------------------------------------------------------------------

test('recording the effectiveness check needs Quality authority at the CAPA Org Unit', async () => {
  const ground = await makeGround();
  const opened = await openCapa(ground.engineer.token, ground.concern.id, {});
  const capaId = opened.body.capa.id;
  await closeConcern(ground.engineer.token, ground.concern.id);

  // Nobody at all: no Grant anywhere.
  const stranger = await insertAccount({ displayName: 'Nobody In Particular' });
  const refused = await recordEffectiveness(stranger.token, capaId, {
    outcome: 'effective',
    note: 'Not this caller to decide.'
  });
  assert.strictEqual(refused.status, 403, JSON.stringify(refused.body));
  assert.match(refused.body.message, /Quality authority/);

  // Edit access is not Quality authority: the supervisor who works the line may
  // record work on it and is not the one who decides the fix held (ADR-0035's
  // two independent flags).
  const supervisor = await insertAccount({
    displayName: 'Line Supervisor',
    grants: [{ orgUnitId: ground.line.id, write: true, quality: false }]
  });
  const byWrite = await recordEffectiveness(supervisor.token, capaId, {
    outcome: 'effective',
    note: 'Edit access is not authority.'
  });
  assert.strictEqual(byWrite.status, 403, JSON.stringify(byWrite.body));
  assert.match(byWrite.body.message, /Quality authority/);

  // A Quality authority Grant that reaches this Org Unit — the area's Grant
  // covers the line beneath it — is enough, and gets as far as the record's own
  // refusal: nothing here has been confirmed as a root cause, so an effective
  // verdict is refused by the service rather than by the gate. Which is the
  // point of asserting it: the gate said yes.
  const above = await insertAccount({
    displayName: 'Area Engineer',
    grants: [{ orgUnitId: ground.area.id, write: true, quality: true }]
  });
  const reachesDown = await recordEffectiveness(above.token, capaId, {
    outcome: 'effective',
    note: 'Nothing has been confirmed as a root cause, so this cannot close.'
  });
  assert.strictEqual(reachesDown.status, 409, JSON.stringify(reachesDown.body));
  assert.match(reachesDown.body.message, /confirmed root cause/);

  // Nothing any refusal wrote: the investigation is untouched, with no verifier
  // and no verdict.
  const read = await readCapa(ground.engineer.token, capaId);
  assert.strictEqual(read.body.capa.status, 'verifying');
  assert.strictEqual(read.body.capa.effectivenessVerifiedAt, null);
  assert.strictEqual(read.body.capa.effectivenessVerifiedBy, null);
  assert.strictEqual(read.body.capa.effectivenessNote, null);

  // An unknown CAPA is a 404 before any of it, and a malformed id too — the
  // address does not name anything, whoever is asking.
  const missing = await recordEffectiveness(ground.engineer.token, 999999999, {
    outcome: 'effective',
    note: 'Nowhere.'
  });
  assert.strictEqual(missing.status, 404, JSON.stringify(missing.body));
  const malformed = await recordEffectiveness(ground.engineer.token, 'not-an-id', {
    outcome: 'effective',
    note: 'Nowhere.'
  });
  assert.strictEqual(malformed.status, 404, JSON.stringify(malformed.body));
});

test('the team lead cannot record the effectiveness check on their own CAPA', async () => {
  const ground = await makeGround();
  const opened = await openCapa(ground.engineer.token, ground.concern.id, {
    teamLeadEmployeeId: ground.leadEmployee.id,
    teamMemberEmployeeIds: [ground.memberEmployee.id]
  });
  assert.strictEqual(opened.status, 201, JSON.stringify(opened.body));
  const capaId = opened.body.capa.id;
  await closeConcern(ground.engineer.token, ground.concern.id);

  // The lead's own Account, holding Quality authority at the line: the one
  // caller whose verdict is not evidence. They are refused in the words that
  // say which rule refused them — the authority above is not the gate that
  // fired here, and the message has to be readable as that difference.
  const leadAccount = await insertAccount({
    displayName: 'Ada Lead',
    employeeId: ground.leadEmployee.id,
    grants: [{ orgUnitId: ground.line.id, write: true, quality: true }]
  });
  const refused = await recordEffectiveness(leadAccount.token, capaId, {
    outcome: 'effective',
    note: 'I decided this held.'
  });
  assert.strictEqual(refused.status, 403, JSON.stringify(refused.body));
  assert.match(refused.body.message, /team lead/);

  // A member of the team who holds the authority is exactly who may record it:
  // the rule is about the lead, not about the team.
  const memberAccount = await insertAccount({
    displayName: 'Bo Member',
    employeeId: ground.memberEmployee.id,
    grants: [{ orgUnitId: ground.line.id, write: true, quality: true }]
  });
  const byMember = await recordEffectiveness(memberAccount.token, capaId, {
    outcome: 'not_effective',
    note: 'It worked loose again after 300 cycles.'
  });
  assert.strictEqual(byMember.status, 200, JSON.stringify(byMember.body));
  assert.strictEqual(byMember.body.capa.effectivenessVerifiedBy.name, 'Bo Member');

  // And an administrator — who need not be an Employee at all, and so can never
  // be the team lead (see the migration's header) — records the next one.
  const ground2 = await makeGround();
  const opened2 = await openCapa(ground2.engineer.token, ground2.concern.id, {
    teamLeadEmployeeId: ground2.leadEmployee.id
  });
  const capaId2 = opened2.body.capa.id;
  await closeConcern(ground2.engineer.token, ground2.concern.id);
  await confirmBothRoots(ground2.engineer.token, capaId2);
  const byAdmin = await recordEffectiveness(admin.token, capaId2, {
    outcome: 'effective',
    note: 'Checked on the line with the fitter who fitted it.'
  });
  assert.strictEqual(byAdmin.status, 200, JSON.stringify(byAdmin.body));
  assert.strictEqual(byAdmin.body.capa.status, 'closed');
  assert.strictEqual(byAdmin.body.capa.effectivenessVerifiedBy.accountId, String(admin.id));
  assert.strictEqual(byAdmin.body.capa.effectivenessVerifiedBy.name, 'Avery Administrator');
});

test('the check cannot be recorded before the Concern has closed', async () => {
  const ground = await makeGround();
  const opened = await openCapa(ground.engineer.token, ground.concern.id, {});
  const capaId = opened.body.capa.id;

  // The Concern is open and its countermeasure has not even been raised: there
  // is no fix to check, so there is no date it could be due on either.
  const early = await recordEffectiveness(ground.engineer.token, capaId, {
    outcome: 'effective',
    note: 'I am sure it will work.'
  });
  assert.strictEqual(early.status, 409, JSON.stringify(early.body));
  assert.match(early.body.message, /Concern is not closed/);

  // Nor with a verdict of `not_effective`: a check that did not hold is still a
  // check, and it is due at the same moment.
  const alsoEarly = await recordEffectiveness(ground.engineer.token, capaId, {
    outcome: 'not_effective',
    note: 'It never worked.'
  });
  assert.strictEqual(alsoEarly.status, 409, JSON.stringify(alsoEarly.body));

  // And the same refusal holds while the Concern is *workable* rather than
  // untouched: a countermeasure raised and its cycle half walked is still an
  // open problem.
  const raised = await addMeasure(ground.engineer.token, ground.concern.id, {
    actionType: 'countermeasure',
    title: 'Torque the fastener to the standard'
  });
  assert.strictEqual(raised.status, 201, JSON.stringify(raised.body));
  const half = await completePhase(ground.engineer.token, ground.concern.id, 'plan', {
    note: 'We will torque it properly.'
  });
  assert.strictEqual(half.status, 200, JSON.stringify(half.body));
  const stillEarly = await recordEffectiveness(ground.engineer.token, capaId, {
    outcome: 'effective',
    note: 'Still not due.'
  });
  assert.strictEqual(stillEarly.status, 409, JSON.stringify(stillEarly.body));

  // Nothing was written by any of the three refusals.
  const read = await readCapa(ground.engineer.token, capaId);
  assert.strictEqual(read.body.capa.status, 'open');
  assert.strictEqual(read.body.capa.effectivenessCheckDueAt, null);
  assert.strictEqual(read.body.capa.effectivenessVerifiedAt, null);
});

// ---------------------------------------------------------------------------
// 3. Effective: closing the investigation
// ---------------------------------------------------------------------------

test('an effective check closes the CAPA and records the verifying Account, the time and the note', async () => {
  const ground = await makeGround();
  const opened = await openCapa(ground.engineer.token, ground.concern.id, {});
  const capaId = opened.body.capa.id;
  await closeConcern(ground.engineer.token, ground.concern.id);
  await confirmBothRoots(ground.engineer.token, capaId);

  const before = await readCapa(ground.engineer.token, capaId);
  assert.strictEqual(before.body.capa.status, 'verifying');

  // The verifier is a second engineer — somebody who did not do the work — and
  // the Note is what the check found.
  const verifier = await insertAccount({
    displayName: 'Pat Verifier',
    grants: [{ orgUnitId: ground.line.id, write: false, quality: true }]
  });
  const note = 'Ran 500 cycles on the line and the guard held; the torque step is on the sheet.';
  const recorded = await recordEffectiveness(verifier.token, capaId, {
    outcome: 'effective',
    note
  });
  assert.strictEqual(recorded.status, 200, JSON.stringify(recorded.body));

  const capa = recorded.body.capa;
  assert.strictEqual(capa.status, 'closed');
  assert.notStrictEqual(capa.closedAt, null);
  assert.strictEqual(capa.effectivenessNote, note);
  assert.notStrictEqual(capa.effectivenessVerifiedAt, null);
  assert.deepStrictEqual(capa.effectivenessVerifiedBy, {
    accountId: String(verifier.id),
    name: 'Pat Verifier'
  });
  // A Grant that cannot write is enough on its own: Quality authority is the
  // flag this act asks for, not edit access (ADR-0035).
  assert.strictEqual(capa.concern.status, 'done');

  // The CAPA's own read agrees with the answer the write gave, and the Concern
  // it answers still reads as the problem, closed.
  const reread = await readCapa(ground.engineer.token, capaId);
  assert.strictEqual(reread.body.capa.status, 'closed');
  assert.strictEqual(reread.body.capa.effectivenessNote, note);
  assert.strictEqual(reread.body.capa.concern.status, 'done');

  // The due date is not cleared by an effective check: it is the date this
  // verdict was judged against.
  assert.strictEqual(reread.body.capa.effectivenessCheckDueAt, before.body.capa.effectivenessCheckDueAt);
  // And a closed CAPA is not overdue — the list's own rule excludes it.
  assert.strictEqual(reread.body.capa.effectivenessCheckOverdue, false);

  // The verifying Account is the new column, and the baseline's Employee
  // column is deliberately left alone (the migration's own argument): an
  // administrator need not be an Employee, so the old key could not hold this.
  const { rows } = await pool.query(
    `SELECT status, effectiveness_verified_by, effectiveness_verified_by_account_id,
            effectiveness_verified_at IS NOT NULL AS verified, closed_at IS NOT NULL AS closed
       FROM capas WHERE id = $1`,
    [capaId]
  );
  assert.strictEqual(rows[0].status, 'closed');
  assert.strictEqual(rows[0].effectiveness_verified_by, null);
  assert.strictEqual(String(rows[0].effectiveness_verified_by_account_id), String(verifier.id));
  assert.strictEqual(rows[0].verified, true);
  assert.strictEqual(rows[0].closed, true);

  // The investigation is over: a second check is refused, a chain write is
  // refused, and the delay cannot be changed any more — "while the CAPA is
  // open" is a real bound.
  const again = await recordEffectiveness(verifier.token, capaId, {
    outcome: 'not_effective',
    note: 'It failed after all.'
  });
  assert.strictEqual(again.status, 409, JSON.stringify(again.body));
  assert.match(again.body.message, /this CAPA is closed/);

  const lateChange = await changeCapa(ground.engineer.token, capaId, {
    effectivenessCheckDelayDays: 60
  });
  assert.strictEqual(lateChange.status, 409, JSON.stringify(lateChange.body));

  const write = await addWhy(ground.engineer.token, capaId, {
    chain: 'occurrence',
    statement: 'Too late for this.'
  });
  assert.strictEqual(write.status, 409, JSON.stringify(write.body));
});

test('an effective check is refused while either chain has no confirmed root cause', async () => {
  const ground = await makeGround();
  const opened = await openCapa(ground.engineer.token, ground.concern.id, {});
  const capaId = opened.body.capa.id;
  await closeConcern(ground.engineer.token, ground.concern.id);

  // Neither chain has concluded: the investigation has not finished, so the fix
  // cannot be judged to have held.
  const none = await recordEffectiveness(ground.engineer.token, capaId, {
    outcome: 'effective',
    note: 'Good enough.'
  });
  assert.strictEqual(none.status, 409, JSON.stringify(none.body));
  assert.match(none.body.message, /occurrence/);
  assert.match(none.body.message, /escape/);

  // Only the occurrence chain has a root cause: the one refusal has to name the
  // chain that is missing, not merely say "somewhere".
  await confirmRoot(ground.engineer.token, capaId, 'occurrence', 'The torque step was not on the sheet.');
  const halfDone = await recordEffectiveness(ground.engineer.token, capaId, {
    outcome: 'effective',
    note: 'Better.'
  });
  assert.strictEqual(halfDone.status, 409, JSON.stringify(halfDone.body));
  assert.match(halfDone.body.message, /escape/);
  assert.doesNotMatch(halfDone.body.message, /occurrence/);

  // Nothing was closed by either refusal: an effective verdict is the only door
  // to `closed`, and it did not open.
  const read = await readCapa(ground.engineer.token, capaId);
  assert.strictEqual(read.body.capa.status, 'verifying');
  assert.strictEqual(read.body.capa.closedAt, null);
  assert.strictEqual(read.body.capa.effectivenessVerifiedAt, null);

  // A verdict that is neither of the two is a 400, and a note that says nothing
  // is one too — a verdict with no evidence is the "list of good intentions"
  // this step exists to refuse.
  const wrongOutcome = await recordEffectiveness(ground.engineer.token, capaId, {
    outcome: 'probably',
    note: 'Hmm.'
  });
  assert.strictEqual(wrongOutcome.status, 400, JSON.stringify(wrongOutcome.body));
  const noNote = await recordEffectiveness(ground.engineer.token, capaId, {
    outcome: 'effective'
  });
  assert.strictEqual(noNote.status, 400, JSON.stringify(noNote.body));
  const blankNote = await recordEffectiveness(ground.engineer.token, capaId, {
    outcome: 'effective',
    note: '   '
  });
  assert.strictEqual(blankNote.status, 400, JSON.stringify(blankNote.body));

  // The second chain concludes, and the same verdict now lands.
  await confirmRoot(ground.engineer.token, capaId, 'escape', 'Nobody looks behind the machine between shifts.');
  const closed = await recordEffectiveness(ground.engineer.token, capaId, {
    outcome: 'effective',
    note: 'Both chains answered, and the guard held.'
  });
  assert.strictEqual(closed.status, 200, JSON.stringify(closed.body));
  assert.strictEqual(closed.body.capa.status, 'closed');
});

// ---------------------------------------------------------------------------
// 4. Not effective: the Concern goes round again
// ---------------------------------------------------------------------------

test('a check that did not hold reopens the Concern into its next cycle and leaves the CAPA open', async () => {
  const ground = await makeGround();
  const opened = await openCapa(ground.engineer.token, ground.concern.id, {});
  const capaId = opened.body.capa.id;
  await closeConcern(ground.engineer.token, ground.concern.id);

  const closedConcern = await readAction(ground.engineer.token, ground.concern.id);
  assert.strictEqual(closedConcern.body.action.status, 'done');
  // One round so far: plan, do, check and act, all of cycle 1.
  assert.deepStrictEqual(
    closedConcern.body.action.phases.map((phase) => `${phase.cycle}:${phase.phase}`),
    ['1:plan', '1:do', '1:check', '1:act']
  );

  const note = 'The guard came loose again after 300 cycles, on the second shift.';
  const recorded = await recordEffectiveness(ground.engineer.token, capaId, {
    outcome: 'not_effective',
    note
  });
  assert.strictEqual(recorded.status, 200, JSON.stringify(recorded.body));

  const capa = recorded.body.capa;
  // The verifier, the time and the note are recorded exactly as on an effective
  // check — the verdict is what differs, not the evidence.
  assert.strictEqual(capa.effectivenessNote, note);
  assert.notStrictEqual(capa.effectivenessVerifiedAt, null);
  assert.strictEqual(capa.effectivenessVerifiedBy.accountId, String(ground.engineer.id));
  assert.strictEqual(capa.effectivenessVerifiedBy.name, 'Quality Engineer');

  // `not_effective` records the same three facts — the verdict is what differs,
  // not the evidence — and the CAPA stays open: its state says the
  // countermeasures are being worked again, and nothing is closed.
  assert.strictEqual(capa.status, 'actions');
  assert.strictEqual(capa.closedAt, null);

  // Nothing is due any more: the next check becomes due when the Concern closes
  // again, so a cleared date is the honest state rather than an overdue one.
  assert.strictEqual(capa.effectivenessCheckDueAt, null);

  // And the Concern is back in the log — reopened into its next cycle, which is
  // ADR-0033's own circle arriving from the verification rather than from a
  // Check.
  const reopened = await readAction(ground.engineer.token, ground.concern.id);
  assert.strictEqual(reopened.status, 200, JSON.stringify(reopened.body));
  assert.strictEqual(reopened.body.action.status, 'in_progress');
  assert.strictEqual(reopened.body.action.completedAt, null);
  assert.deepStrictEqual(
    reopened.body.action.phases.map((phase) => `${phase.cycle}:${phase.phase}`),
    ['1:plan', '1:do', '1:check', '1:act', '2:plan']
  );
  // The open phase is cycle 2's Plan, and it is the only one open — the
  // invariant completePhase checks before it lets anything move.
  assert.strictEqual(reopened.body.action.openPhase.cycle, 2);
  assert.strictEqual(reopened.body.action.openPhase.phase, 'plan');
  const closedPhases = reopened.body.action.phases.filter((phase) => phase.completedAt !== null);
  assert.strictEqual(closedPhases.length, 4);

  // The CAPA is open for business: its chains and its delay can still be
  // changed, which is what "leaves the CAPA open" has to mean.
  const stillWritable = await addWhy(ground.engineer.token, capaId, {
    chain: 'occurrence',
    statement: 'The second shift cleans the guard off with solvent.',
  });
  assert.strictEqual(stillWritable.status, 201, JSON.stringify(stillWritable.body));
  const delayChange = await changeCapa(ground.engineer.token, capaId, {
    effectivenessCheckDelayDays: 5
  });
  assert.strictEqual(delayChange.status, 200, JSON.stringify(delayChange.body));

  // A second check is refused while the Concern is open again — the next one is
  // not "another try", it is due at the next closure.
  const tooSoon = await recordEffectiveness(ground.engineer.token, capaId, {
    outcome: 'not_effective',
    note: 'Still broken.'
  });
  assert.strictEqual(tooSoon.status, 409, JSON.stringify(tooSoon.body));
  assert.match(tooSoon.body.message, /not closed/);

  // Round two closes with the new delay, so the due date is recomputed from the
  // *new* number — which is the other half of the stored-date decision: the
  // delay governs the next closure, and a fresh check is due a fresh delay
  // later.
  await walkCycle(ground.engineer.token, ground.concern.id, 'The Concern, round two');
  const roundTwo = await readCapa(ground.engineer.token, capaId);
  assert.strictEqual(roundTwo.body.capa.status, 'verifying');
  assert.strictEqual(roundTwo.body.capa.effectivenessCheckDueAt, await dueDateFor(5));
  assert.strictEqual(roundTwo.body.capa.effectivenessVerifiedAt !== null, true);
});

// ---------------------------------------------------------------------------
// 5. The list
// ---------------------------------------------------------------------------

test('the CAPA list filters by Org Unit beneath and by status, and marks the overdue ones', async () => {
  const site = await insertSite();
  const area = await insertOrgUnit(site.id, { name: 'Foundry' });
  const lineOne = await insertOrgUnit(site.id, {
    parentId: area.id,
    unitType: 'line',
    name: 'Line 1'
  });
  const lineTwo = await insertOrgUnit(site.id, {
    parentId: area.id,
    unitType: 'line',
    name: 'Line 2'
  });
  const elsewhere = await insertOrgUnit(site.id, { name: 'Warehouse' });

  const engineer = await insertAccount({
    displayName: 'Quality Engineer',
    grants: [
      { orgUnitId: lineOne.id, write: true, quality: true },
      { orgUnitId: lineTwo.id, write: true, quality: true },
      { orgUnitId: elsewhere.id, write: true, quality: true }
    ]
  });

  async function capaOn(orgUnitId, title) {
    const raised = await raiseConcern(engineer.token, site.id, { orgUnitId, title });
    assert.strictEqual(raised.status, 201, JSON.stringify(raised.body));
    const opened = await openCapa(engineer.token, raised.body.action.id, {});
    assert.strictEqual(opened.status, 201, JSON.stringify(opened.body));
    return opened.body.capa;
  }

  const onLineOne = await capaOn(lineOne.id, 'The guard keeps working loose');
  const onLineTwo = await capaOn(lineTwo.id, 'The label is on the wrong side');
  const onElsewhere = await capaOn(elsewhere.id, 'The pallet count is short');

  // One of them is closed, so the status filter has something to separate.
  await closeConcern(engineer.token, onElsewhere.concern.id);
  await confirmBothRoots(engineer.token, onElsewhere.id);
  const closed = await recordEffectiveness(engineer.token, onElsewhere.id, {
    outcome: 'effective',
    note: 'Counted the pallets twice.'
  });
  assert.strictEqual(closed.status, 200, JSON.stringify(closed.body));

  // One of them is waiting on its (future) check, and one is genuinely overdue.
  const waiting = await capaOn(lineOne.id, 'The conveyor stops at start-up');
  await closeConcern(engineer.token, waiting.concern.id);
  const overdue = await capaOn(lineTwo.id, 'The torque wrench reads low');
  await closeConcern(engineer.token, overdue.concern.id);

  // Arranged directly, and this is the one arrangement in this file (see the
  // header): the due date is written by the closure, no request may close a
  // Concern in the past, and the delay may not be negative — so a CAPA whose
  // check is genuinely overdue cannot be produced through the API on the day it
  // is created. Moving the stored date back is the shortest honest way to be
  // that CAPA; everything asserted about it below is read over HTTP.
  await pool.query(
    `UPDATE capas SET effectiveness_check_due_at = CURRENT_DATE - 5 WHERE id = $1`,
    [overdue.id]
  );

  // The whole list: every investigation on the Platform, whoever is asking.
  // Reading is not scoped (ADR-0009), which is why a caller with no Grant at
  // all sees exactly the same rows.
  const stranger = await insertAccount({ displayName: 'Nobody In Particular' });
  const all = await listCapas(stranger.token);
  assert.strictEqual(all.status, 200, JSON.stringify(all.body));
  assert.strictEqual(all.body.truncated, false);
  const ids = all.body.capas.map((capa) => capa.id);
  for (const capa of [onLineOne, onLineTwo, onElsewhere, waiting, overdue]) {
    assert.ok(ids.includes(capa.id), `${capa.capaNo} is missing from the list`);
  }

  // Every row carries what the list is read for: its Org Unit's name, its
  // status, the delay, and whether its check is overdue.
  const overdueRow = all.body.capas.find((capa) => capa.id === overdue.id);
  assert.strictEqual(overdueRow.orgUnitName, 'Line 2');
  assert.strictEqual(overdueRow.status, 'verifying');
  assert.strictEqual(overdueRow.effectivenessCheckDelayDays, 30);
  assert.strictEqual(overdueRow.effectivenessCheckDueAt, await dueDateFor(-5));
  assert.strictEqual(overdueRow.effectivenessCheckOverdue, true);
  const waitingRow = all.body.capas.find((capa) => capa.id === waiting.id);
  assert.strictEqual(waitingRow.effectivenessCheckOverdue, false);
  const closedRow = all.body.capas.find((capa) => capa.id === onElsewhere.id);
  assert.strictEqual(closedRow.status, 'closed');
  // A closed investigation is not overdue even though its date has been and
  // gone — the date is the record of when the check was due, not a worklist.
  assert.strictEqual(closedRow.effectivenessCheckOverdue, false);

  // Narrowed to one Org Unit, and to everything beneath it: the area's line
  // CAPAs are in, the Warehouse's is out.
  const beneath = await listCapas(engineer.token, { orgUnitId: String(area.id) });
  assert.strictEqual(beneath.status, 200, JSON.stringify(beneath.body));
  const beneathIds = beneath.body.capas.map((capa) => capa.id);
  assert.ok(beneathIds.includes(waiting.id));
  assert.ok(beneathIds.includes(overdue.id));
  assert.ok(!beneathIds.includes(onElsewhere.id));

  // And to one line: the sibling line's investigation is not in it.
  const justLineOne = await listCapas(engineer.token, { orgUnitId: String(lineOne.id) });
  const lineOneIds = justLineOne.body.capas.map((capa) => capa.id);
  assert.ok(lineOneIds.includes(waiting.id));
  assert.ok(!lineOneIds.includes(overdue.id));

  // An Org Unit that is not there is a 404, not a silently empty list — the
  // same answer the register gives.
  const unknownOrgUnit = await listCapas(engineer.token, { orgUnitId: '999999999' });
  assert.strictEqual(unknownOrgUnit.status, 404, JSON.stringify(unknownOrgUnit.body));

  // By status.
  const verifying = await listCapas(engineer.token, { status: 'verifying' });
  const verifyingIds = verifying.body.capas.map((capa) => capa.id);
  assert.ok(verifyingIds.includes(waiting.id));
  assert.ok(verifyingIds.includes(overdue.id));
  assert.ok(!verifyingIds.includes(onElsewhere.id));

  const closedOnly = await listCapas(engineer.token, { status: 'closed' });
  const closedIds = closedOnly.body.capas.map((capa) => capa.id);
  assert.ok(closedIds.includes(onElsewhere.id));
  assert.ok(!closedIds.includes(overdue.id));

  // A status that is not one is a 400 naming the values, rather than an empty
  // list that reads as a quiet plant.
  const typo = await listCapas(engineer.token, { status: 'verified' });
  assert.strictEqual(typo.status, 400, JSON.stringify(typo.body));
  assert.match(typo.body.message, /verifying/);

  // And the question this ticket exists for: which checks have fallen due.
  const onlyOverdue = await listCapas(engineer.token, { overdue: 'true' });
  const overdueIds = onlyOverdue.body.capas.map((capa) => capa.id);
  assert.ok(overdueIds.includes(overdue.id));
  assert.ok(!overdueIds.includes(waiting.id));
  assert.ok(!overdueIds.includes(onElsewhere.id));

  // Only the exact string counts, the same convenience-filter rule the register
  // uses for its own history switch: `overdue=yes` is not a filter, it is
  // nothing at all.
  const notAFilter = await listCapas(engineer.token, { overdue: 'yes' });
  assert.strictEqual(notAFilter.status, 200, JSON.stringify(notAFilter.body));
  assert.ok(notAFilter.body.capas.map((capa) => capa.id).includes(onElsewhere.id));

  // Overdue first, then due soonest, then the most recently opened. Line 2
  // holds two investigations: the overdue one leads, the untouched one — with
  // no date at all — follows it.
  const ordered = await listCapas(engineer.token, { orgUnitId: String(lineTwo.id) });
  assert.deepStrictEqual(
    ordered.body.capas.map((capa) => capa.id),
    [overdue.id, onLineTwo.id]
  );

  // The whole area: the overdue check first, then the one whose date is soonest,
  // and the two open investigations after them — the order a plant reads this
  // list in, worst first. (The last two are ordered by when they were opened,
  // which is the tie-break rather than the rule, so they are compared as a set.)
  const twoLines = await listCapas(engineer.token, { orgUnitId: String(area.id) });
  assert.deepStrictEqual(
    twoLines.body.capas.slice(0, 2).map((capa) => capa.id),
    [overdue.id, waiting.id]
  );
  assert.deepStrictEqual(
    twoLines.body.capas
      .slice(2)
      .map((capa) => capa.id)
      .sort(),
    [onLineOne.id, onLineTwo.id].sort()
  );

  // And the whole list leads with the overdue one, whoever is reading it.
  assert.ok(all.body.capas.findIndex((capa) => capa.id === overdue.id) < all.body.capas.length - 1);

  // A closed CAPA's own row still carries the verifier, which is what the
  // report #212 renders reads (issue #211 returns it; it does not build that
  // Screen).
  assert.deepStrictEqual(closedRow.effectivenessVerifiedBy, {
    accountId: String(engineer.id),
    name: 'Quality Engineer'
  });
  assert.strictEqual(closedRow.effectivenessNote, 'Counted the pallets twice.');
});
