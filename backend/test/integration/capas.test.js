/*
 * Opening a CAPA on a Concern, changing its team and its problem description,
 * and reading it back (issue #209) — over HTTP, against a real database and a
 * real (locally issued) JWKS. The seam, the fixture scaffolding and the
 * dependency-ordered cleanup are the ones concern-nonconformances.test.js and
 * actions.test.js already establish.
 *
 * ADR-0034 is the decision this file exercises: a CAPA is an investigation
 * opened on an existing Concern, in the actions Module, and the Concern's own
 * Containments, Countermeasures and Preventive actions ARE its actions — so
 * what the CAPA's detail read returns is the Concern with its measures and
 * their phases, not a second list of the same work.
 *
 * Every refusal the ticket names has a test proving it is refused, not only the
 * permitted path: a caller without Quality authority (403), a caller who holds
 * a write Grant but not the authority (403), an Action that is not a Concern
 * (400), a second CAPA on one Concern (409), a departed Employee on the team
 * (409), an Employee who is not in the directory (404), a malformed id (400),
 * a CAPA that does not exist (404) and a change that names nothing (400).
 *
 * **Three assertions in this file read Postgres directly rather than over
 * HTTP, and each says why where it stands.** `schema.test.js` and
 * `views.test.js` are the suite's named exception to the two-test-seams rule
 * and this file takes the same licence for the same reason: a rule with no HTTP
 * door has no other way to be stated. The three are the partial unique index and
 * the check constraint (a constraint is what makes a rule true for a writer that
 * does not use the service, so the only honest way to test it is to be that
 * writer for one statement) and `capa_steps` staying empty (ADR-0034's "the
 * table is not used" is a claim about a table nothing reads, so there is no
 * response that could show it).
 *
 * Needs a database with every migration applied, including
 * 1800100000000_capas-on-a-concern.js. Set DATABASE_URL first — see the
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

// An Account, optionally holding Grants. `write` and `quality` are the two
// independent flags ADR-0035 keeps apart, and every test that asserts a
// refusal turns on exactly one of them.
async function insertAccount({ role = 'operator', displayName = null, grants = [] } = {}) {
  const subject = uniqueCode('capaacct');
  const name = displayName ?? `Capa Account ${subject}`;
  const { rows: [account] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status)
     VALUES ($1, $2, $3, $4, TRUE, 'approved') RETURNING id`,
    [`${subject}@example.com`, name, role, subject]
  );
  insertedAccountIds.push(account.id);

  for (const grant of grants) {
    await pool.query(
      `INSERT INTO app_user_org_units (app_user_id, org_unit_id, can_write, quality_authority)
       VALUES ($1, $2, $3, $4)`,
      [account.id, grant.orgUnitId, grant.write ?? true, grant.quality ?? false]
    );
  }

  return { id: account.id, displayName: name, token: await authHeader(subject) };
}

async function insertSite() {
  const { rows: [site] } = await pool.query(
    `INSERT INTO sites (code, name, timezone) VALUES ($1, $2, $3) RETURNING id, code, name`,
    [uniqueCode('CAPAS'), 'Capa Test Site', 'Asia/Ho_Chi_Minh']
  );
  insertedSiteIds.push(site.id);
  return site;
}

async function insertOrgUnit(siteId, { parentId = null, unitType = 'area', name = 'Capa Unit' } = {}) {
  const { rows: [orgUnit] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, $2, $3, $4, $5) RETURNING id, code, name, path`,
    [siteId, parentId, uniqueCode('CAPAOU'), name, unitType]
  );
  insertedOrgUnitIds.push(orgUnit.id);
  return orgUnit;
}

// One Employee of the directory. The display name is derived by the baseline
// from the two name columns, so two Employees are told apart by their first
// name here.
async function insertEmployee({ first = 'Ann', last = 'Fitter', isActive = true } = {}) {
  const { rows: [employee] } = await pool.query(
    `INSERT INTO employees (employee_no, first_name, last_name, is_active)
     VALUES ($1, $2, $3, $4) RETURNING id, display_name, is_active`,
    [uniqueCode('CAPAEMP'), first, last, isActive]
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

async function escalate(token, actionId, orgUnitId) {
  const response = await fetch(`${base}/api/actions/${actionId}/escalate`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify({ orgUnitId })
  });
  return json(response);
}

/**
 * The ground every test starts from: a Site with an area and a line beneath it,
 * a quality engineer granted on the line (and, where a test escalates, on the
 * area as well), two Employees who are not the lead, and one Concern raised on
 * the line.
 *
 * The Concern is raised through the API rather than inserted, because a CAPA's
 * whole subject is a real problem: its title, its number and its cycle-1 Plan
 * are what the CAPA's own read has to carry.
 */
async function makeGround({ write = true, quality = true, areaGrant = false } = {}) {
  const site = await insertSite();
  const area = await insertOrgUnit(site.id, { name: 'Foundry' });
  const line = await insertOrgUnit(site.id, {
    parentId: area.id,
    unitType: 'line',
    name: 'Line 1'
  });

  const grants = [{ orgUnitId: line.id, write, quality }];
  if (areaGrant) grants.push({ orgUnitId: area.id, write: true, quality: true });

  const engineer = await insertAccount({
    displayName: 'Quality Engineer',
    grants
  });
  const lead = await insertEmployee({ first: 'Ada', last: 'Lead' });
  const member = await insertEmployee({ first: 'Bo', last: 'Member' });

  const raised = await raiseConcern(engineer.token, site.id, {
    orgUnitId: line.id,
    title: 'The guard keeps working loose'
  });
  assert.strictEqual(raised.status, 201, `raising failed: ${JSON.stringify(raised.body)}`);

  return { site, area, line, engineer, lead, member, concern: raised.body.action };
}

let admin;
let adminToken;

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
  // Children before parents, and the CAPA's own link first: the team cascades
  // from its CAPA, and the Concern's `capa_id` must stop pointing at the CAPA
  // *before* the CAPA row goes, because `action_items.capa_id` is a foreign key
  // and Postgres checks it on DELETE. The Actions go next, and their
  // `action_phases` cascade with them.
  if (insertedCapaIds.length > 0) {
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
// 1. Opening a CAPA
// ---------------------------------------------------------------------------

test('opening a CAPA gives it its own number, opens it as an 8d at the Concern Org Unit, and names the team', async () => {
  const ground = await makeGround();

  const { status, body } = await openCapa(ground.engineer.token, ground.concern.id, {
    teamLeadEmployeeId: ground.lead.id,
    teamMemberEmployeeIds: [ground.member.id],
    problemStatement: 'Two shifts running, on the same fixture.'
  });
  assert.strictEqual(status, 201, JSON.stringify(body));

  const capa = body.capa;
  // Its own number, from the baseline's own Site-scoped sequence: the prefix a
  // person quotes, the Site's code, the year and a zero-padded sequence.
  assert.match(capa.capaNo, new RegExp(`^CA-${ground.site.code}-\\d{4}-00001$`));
  // The method and status ADR-0034 fixes for a CAPA opened here.
  assert.strictEqual(capa.method, '8d');
  assert.strictEqual(capa.status, 'open');
  // The Concern's own Org Unit, which the caller never named.
  assert.strictEqual(capa.orgUnitId, String(ground.line.id));
  assert.strictEqual(capa.orgUnitName, 'Line 1');
  assert.strictEqual(capa.siteId, String(ground.site.id));
  // The Concern is the problem, so the investigation's own title is its title.
  assert.strictEqual(capa.title, ground.concern.title);
  assert.strictEqual(capa.problemStatement, 'Two shifts running, on the same fixture.');
  assert.deepStrictEqual(capa.teamLead, {
    employeeId: String(ground.lead.id),
    name: 'Ada Lead'
  });
  assert.deepStrictEqual(
    capa.teamMembers.map((member) => member.name),
    ['Bo Member']
  );

  // The Concern comes with it, as its own detail read gives it.
  assert.strictEqual(capa.concern.id, String(ground.concern.id));
  assert.strictEqual(capa.concern.actionType, 'concern');
  assert.strictEqual(capa.concern.capa.capaNo, capa.capaNo);

  // And the other direction: the Concern now names the investigation, which is
  // what its own Screen reads to offer "open one" or a link to the one it has.
  const concern = await readAction(ground.engineer.token, ground.concern.id);
  assert.strictEqual(concern.status, 200, JSON.stringify(concern.body));
  assert.strictEqual(concern.body.action.capa.id, capa.id);
  assert.strictEqual(concern.body.action.capa.capaNo, capa.capaNo);
  assert.strictEqual(concern.body.action.capa.status, 'open');

  // The CAPA is readable at its own address, and reads the same.
  const read = await readCapa(ground.engineer.token, capa.id);
  assert.strictEqual(read.status, 200, JSON.stringify(read.body));
  assert.strictEqual(read.body.capa.capaNo, capa.capaNo);
});

test('opening a CAPA needs Quality authority at the Concern Org Unit, and a write Grant is not enough', async () => {
  const ground = await makeGround({ write: true, quality: false });

  const refused = await openCapa(ground.engineer.token, ground.concern.id, {
    problemStatement: 'Nobody should be able to open this.'
  });
  assert.strictEqual(refused.status, 403, JSON.stringify(refused.body));
  assert.match(refused.body.message, /Quality authority/);

  // Nothing was written: the Concern still carries no CAPA (and a refusal that
  // left a `capas` row behind would leave one nothing points at).
  const concern = await readAction(ground.engineer.token, ground.concern.id);
  assert.strictEqual(concern.body.action.capa, null);
  const { rows } = await pool.query('SELECT COUNT(*)::int AS count FROM capas WHERE org_unit_id = $1', [
    ground.line.id
  ]);
  assert.strictEqual(rows[0].count, 0);
});

test('Quality authority alone is enough — opening a CAPA does not need a write Grant', async () => {
  // ADR-0035's two flags are independent: the quality engineer who reads a line
  // and decides its problem needs an investigation is exactly the reader a
  // view-only Grant is for.
  const ground = await makeGround({ write: false, quality: true });

  const { status, body } = await openCapa(ground.engineer.token, ground.concern.id, {});
  assert.strictEqual(status, 201, JSON.stringify(body));
  assert.strictEqual(body.capa.status, 'open');
  // Opened with no team and no description at all, which is a real state: the
  // judgement is that this problem needs an investigation.
  assert.strictEqual(body.capa.teamLead, null);
  assert.deepStrictEqual(body.capa.teamMembers, []);
  assert.strictEqual(body.capa.problemStatement, null);
});

test('a CAPA is opened on a Concern, not on another kind of Action', async () => {
  const ground = await makeGround();

  const measure = await addMeasure(ground.engineer.token, ground.concern.id, {
    actionType: 'containment',
    title: 'Quarantined the batch'
  });
  assert.strictEqual(measure.status, 201, JSON.stringify(measure.body));

  const refused = await openCapa(ground.engineer.token, measure.body.action.id, {});
  assert.strictEqual(refused.status, 400, JSON.stringify(refused.body));
  assert.match(refused.body.message, /not one|not a Concern/);

  // And the kind is refused before the authority is asked: an Account with no
  // Quality authority here gets the same 400, not a 403, because the act could
  // not have worked on that row whatever their rights were.
  const outsider = await insertAccount({ displayName: 'No Authority' });
  const alsoRefused = await openCapa(outsider.token, measure.body.action.id, {});
  assert.strictEqual(alsoRefused.status, 400, JSON.stringify(alsoRefused.body));
});

test('a second CAPA on a Concern that already has one is refused', async () => {
  const ground = await makeGround();

  const first = await openCapa(ground.engineer.token, ground.concern.id, {});
  assert.strictEqual(first.status, 201, JSON.stringify(first.body));

  const second = await openCapa(ground.engineer.token, ground.concern.id, {
    problemStatement: 'A second investigation nobody asked for.'
  });
  assert.strictEqual(second.status, 409, JSON.stringify(second.body));
  assert.match(second.body.message, /already has a CAPA/);

  // The first one still stands, and no second row was written: a refusal that
  // created a `capas` row first would leave an investigation pointing at
  // nothing.
  const concern = await readAction(ground.engineer.token, ground.concern.id);
  assert.strictEqual(concern.body.action.capa.id, first.body.capa.id);
  const { rows } = await pool.query('SELECT COUNT(*)::int AS count FROM capas WHERE org_unit_id = $1', [
    ground.line.id
  ]);
  assert.strictEqual(rows[0].count, 1);
});

test('the database keeps a CAPA to one Concern, and a Concern to a CAPA', async () => {
  // Read directly (see this file's header): `action_items_capa_id_once` and
  // `action_items_capa_is_a_concern` are the constraints that make the rule
  // true for a writer that does not go through the service, so the honest way
  // to test them is to be that writer for one statement.
  const ground = await makeGround();

  const opened = await openCapa(ground.engineer.token, ground.concern.id, {});
  assert.strictEqual(opened.status, 201, JSON.stringify(opened.body));

  const other = await raiseConcern(ground.engineer.token, ground.site.id, {
    orgUnitId: ground.line.id,
    title: 'A different problem on the same line'
  });
  assert.strictEqual(other.status, 201, JSON.stringify(other.body));

  // A second Concern cannot point at the CAPA another one answers.
  await assert.rejects(
    () =>
      pool.query('UPDATE action_items SET capa_id = $2 WHERE id = $1', [
        other.body.action.id,
        opened.body.capa.id
      ]),
    (error) => error.code === '23505' && error.constraint === 'action_items_capa_id_once',
    'a CAPA answered two Concerns'
  );

  // And a row that is not a Concern cannot carry one at all.
  await assert.rejects(
    () =>
      pool.query("UPDATE action_items SET action_type = 'containment' WHERE id = $1", [
        ground.concern.id
      ]),
    (error) => error.code === '23514' && error.constraint === 'action_items_capa_is_a_concern',
    'a Containment carried a CAPA'
  );

  // Neither failed statement changed anything.
  const after = await readCapa(ground.engineer.token, opened.body.capa.id);
  assert.strictEqual(after.body.capa.concern.id, String(ground.concern.id));
});

test('capa_steps is not written (ADR-0034)', async () => {
  // Read directly (see this file's header): the claim is about a table nothing
  // reads, so there is no response that could show it. The baseline's
  // `capa_steps` is what an 8D *would* be recorded in, and ADR-0034 decides
  // against it in as many words — the Concern's own actions are the CAPA's
  // steps, recorded once in the Action log.
  const ground = await makeGround();
  const opened = await openCapa(ground.engineer.token, ground.concern.id, {
    teamLeadEmployeeId: ground.lead.id,
    problemStatement: 'Opened to prove the steps table stays empty.'
  });
  assert.strictEqual(opened.status, 201, JSON.stringify(opened.body));

  const { rows } = await pool.query('SELECT COUNT(*)::int AS count FROM capa_steps WHERE capa_id = $1', [
    opened.body.capa.id
  ]);
  assert.strictEqual(rows[0].count, 0);
});

// ---------------------------------------------------------------------------
// 2. The team and the problem description
// ---------------------------------------------------------------------------

test('a CAPA team lead and team members can be set and changed while the investigation is open', async () => {
  const ground = await makeGround();
  const third = await insertEmployee({ first: 'Cyd', last: 'Third' });

  const opened = await openCapa(ground.engineer.token, ground.concern.id, {
    teamLeadEmployeeId: ground.lead.id,
    teamMemberEmployeeIds: [ground.member.id]
  });
  assert.strictEqual(opened.status, 201, JSON.stringify(opened.body));
  const capaId = opened.body.capa.id;

  // Changed: a different lead, and a member list that replaces the team.
  const changed = await changeCapa(ground.engineer.token, capaId, {
    teamLeadEmployeeId: third.id,
    teamMemberEmployeeIds: [ground.member.id, ground.lead.id]
  });
  assert.strictEqual(changed.status, 200, JSON.stringify(changed.body));
  assert.deepStrictEqual(changed.body.capa.teamLead, {
    employeeId: String(third.id),
    name: 'Cyd Third'
  });
  assert.deepStrictEqual(
    changed.body.capa.teamMembers.map((member) => member.name),
    ['Ada Lead', 'Bo Member']
  );

  // And it stuck: a fresh read answers the same thing.
  const read = await readCapa(ground.engineer.token, capaId);
  assert.deepStrictEqual(
    read.body.capa.teamMembers.map((member) => member.employeeId),
    [String(ground.lead.id), String(ground.member.id)]
  );

  // A team may be emptied and a lead cleared, which is what a form holding the
  // whole team means when it is saved with nothing on it.
  const cleared = await changeCapa(ground.engineer.token, capaId, {
    teamLeadEmployeeId: null,
    teamMemberEmployeeIds: []
  });
  assert.strictEqual(cleared.status, 200, JSON.stringify(cleared.body));
  assert.strictEqual(cleared.body.capa.teamLead, null);
  assert.deepStrictEqual(cleared.body.capa.teamMembers, []);

  // A field nobody sent is left alone: the lead stays cleared while the
  // description is written.
  const described = await changeCapa(ground.engineer.token, capaId, {
    problemStatement: 'Rewritten with the team decided later.'
  });
  assert.strictEqual(described.status, 200, JSON.stringify(described.body));
  assert.strictEqual(described.body.capa.problemStatement, 'Rewritten with the team decided later.');
  assert.strictEqual(described.body.capa.teamLead, null);
});

test('an Employee who has departed cannot be given a place on a CAPA team, and one who is not there is a 404', async () => {
  const ground = await makeGround();
  const departed = await insertEmployee({ first: 'Dan', last: 'Departed', isActive: false });

  // At open (409) — the same words every other Action refuses a departed
  // owner with, since it is the same fact about the same directory.
  const refusedLead = await openCapa(ground.engineer.token, ground.concern.id, {
    teamLeadEmployeeId: departed.id
  });
  assert.strictEqual(refusedLead.status, 409, JSON.stringify(refusedLead.body));
  assert.match(refusedLead.body.message, /departed/);

  const refusedMember = await openCapa(ground.engineer.token, ground.concern.id, {
    teamMemberEmployeeIds: [departed.id]
  });
  assert.strictEqual(refusedMember.status, 409, JSON.stringify(refusedMember.body));

  // A number nobody holds is a 404, and a value that is not an id at all is a
  // 400 — the order parseId (400) -> findEmployee (404) -> isActive (409) that
  // every other route in this Module keeps.
  const missing = await openCapa(ground.engineer.token, ground.concern.id, {
    teamMemberEmployeeIds: [999999999]
  });
  assert.strictEqual(missing.status, 404, JSON.stringify(missing.body));
  const nonsense = await openCapa(ground.engineer.token, ground.concern.id, {
    teamMemberEmployeeIds: ['not-an-id']
  });
  assert.strictEqual(nonsense.status, 400, JSON.stringify(nonsense.body));
  const notAList = await openCapa(ground.engineer.token, ground.concern.id, {
    teamMemberEmployeeIds: '7'
  });
  assert.strictEqual(notAList.status, 400, JSON.stringify(notAList.body));

  // Nothing was written by any of them.
  const concern = await readAction(ground.engineer.token, ground.concern.id);
  assert.strictEqual(concern.body.action.capa, null);

  // And the same refusals hold for a change to a team that already exists.
  const opened = await openCapa(ground.engineer.token, ground.concern.id, {});
  assert.strictEqual(opened.status, 201, JSON.stringify(opened.body));
  const changed = await changeCapa(ground.engineer.token, opened.body.capa.id, {
    teamList: 'nonsense',
    teamMemberEmployeeIds: [departed.id]
  });
  assert.strictEqual(changed.status, 409, JSON.stringify(changed.body));
});

test('the problem description can be written and edited while the investigation is open', async () => {
  const ground = await makeGround();

  const opened = await openCapa(ground.engineer.token, ground.concern.id, {
    problemStatement: 'The guard comes loose after about 400 cycles.'
  });
  assert.strictEqual(opened.status, 201, JSON.stringify(opened.body));
  assert.strictEqual(
    opened.body.capa.problemStatement,
    'The guard comes loose after about 400 cycles.'
  );

  const edited = await changeCapa(ground.engineer.token, opened.body.capa.id, {
    problemStatement: 'The guard comes loose after about 400 cycles, on the left fixture only.'
  });
  assert.strictEqual(edited.status, 200, JSON.stringify(edited.body));

  const read = await readCapa(ground.engineer.token, opened.body.capa.id);
  assert.strictEqual(
    read.body.capa.problemStatement,
    'The guard comes loose after about 400 cycles, on the left fixture only.'
  );

  // A description that is not text is a 400, and a change naming nothing at
  // all is one too rather than a silent no-op.
  const wrongType = await changeCapa(ground.engineer.token, opened.body.capa.id, {
    problemStatement: 12
  });
  assert.strictEqual(wrongType.status, 400, JSON.stringify(wrongType.body));
  const empty = await changeCapa(ground.engineer.token, opened.body.capa.id, {});
  assert.strictEqual(empty.status, 400, JSON.stringify(empty.body));
});

test('changing a CAPA needs Quality authority at its Org Unit, and an unknown CAPA is a 404', async () => {
  const ground = await makeGround();
  const opened = await openCapa(ground.engineer.token, ground.concern.id, {});
  assert.strictEqual(opened.status, 201, JSON.stringify(opened.body));

  // A write Grant reaching the CAPA's Org Unit is not the authority ADR-0035
  // describes, so the change is refused.
  const writer = await insertAccount({
    displayName: 'Line Supervisor',
    grants: [{ orgUnitId: ground.line.id, write: true, quality: false }]
  });
  const refused = await changeCapa(writer.token, opened.body.capa.id, {
    problemStatement: 'Not this caller to write.'
  });
  assert.strictEqual(refused.status, 403, JSON.stringify(refused.body));
  assert.match(refused.body.message, /Quality authority/);

  // Reading one is Site-wide, the same as reading an Action.
  const readable = await readCapa(writer.token, opened.body.capa.id);
  assert.strictEqual(readable.status, 200, JSON.stringify(readable.body));

  const missing = await readCapa(ground.engineer.token, 999999999);
  assert.strictEqual(missing.status, 404, JSON.stringify(missing.body));
  const malformed = await readCapa(ground.engineer.token, 'not-an-id');
  assert.strictEqual(malformed.status, 404, JSON.stringify(malformed.body));
});

// ---------------------------------------------------------------------------
// 3. The Concern's own actions, with their phases
// ---------------------------------------------------------------------------

test('the CAPA detail returns its Concern with the Containments, Countermeasures and Preventive actions and their current phases', async () => {
  const ground = await makeGround();

  const containment = await addMeasure(ground.engineer.token, ground.concern.id, {
    actionType: 'containment',
    title: 'Quarantined the batch and re-checked the fixture'
  });
  assert.strictEqual(containment.status, 201, JSON.stringify(containment.body));

  const countermeasure = await addMeasure(ground.engineer.token, ground.concern.id, {
    actionType: 'countermeasure',
    title: 'A captive fastener on the guard'
  });
  assert.strictEqual(countermeasure.status, 201, JSON.stringify(countermeasure.body));

  const preventive = await addMeasure(ground.engineer.token, ground.concern.id, {
    actionType: 'preventive',
    title: 'The same fixing checked on every other line'
  });
  assert.strictEqual(preventive.status, 201, JSON.stringify(preventive.body));

  // The countermeasure is worked: its Plan is complete, so the phase it is
  // waiting on is its Do — the state ADR-0033 calls `in_progress`.
  const planned = await completePhase(
    ground.engineer.token,
    countermeasure.body.action.id,
    'plan',
    { note: 'Fitted and torqued to the standard.' }
  );
  assert.strictEqual(planned.status, 200, JSON.stringify(planned.body));

  const opened = await openCapa(ground.engineer.token, ground.concern.id, {
    teamLeadEmployeeId: ground.lead.id,
    problemStatement: 'Three occurrences in a week.'
  });
  assert.strictEqual(opened.status, 201, JSON.stringify(opened.body));

  const concern = opened.body.capa.concern;
  // The Concern's own cycle comes with it: it was raised with its Plan open.
  assert.deepStrictEqual(
    concern.phases.map((phase) => `${phase.cycle}:${phase.phase}`),
    ['1:plan']
  );
  assert.strictEqual(concern.openPhase.phase, 'plan');

  // And its three measures, in the order a person reads them: the containment
  // first because it is what stops the bleeding.
  assert.deepStrictEqual(
    concern.measures.map((measure) => measure.actionType),
    ['containment', 'countermeasure', 'preventive']
  );

  const byType = Object.fromEntries(
    concern.measures.map((measure) => [measure.actionType, measure])
  );
  // The containment and the preventive action are still on their own Plan.
  for (const type of ['containment', 'preventive']) {
    assert.strictEqual(byType[type].openPhase.phase, 'plan', `${type} is not on its plan`);
    assert.deepStrictEqual(
      byType[type].phases.map((phase) => `${phase.cycle}:${phase.phase}:${phase.completedAt ? 'done' : 'open'}`),
      ['1:plan:open']
    );
  }
  // The countermeasure has been worked, and kept the round it was worked in.
  assert.strictEqual(byType.countermeasure.openPhase.phase, 'do');
  assert.deepStrictEqual(
    byType.countermeasure.phases.map(
      (phase) => `${phase.cycle}:${phase.phase}:${phase.completedAt ? 'done' : 'open'}`
    ),
    ['1:plan:done', '1:do:open']
  );
  assert.strictEqual(
    byType.countermeasure.phases[0].note,
    'Fitted and torqued to the standard.'
  );

  // Each measure is an Action of its own, so each names its own number — which
  // is what a reader follows to go and work on it.
  for (const measure of concern.measures) {
    assert.match(measure.actionNo, /^AC-/);
  }
});

// ---------------------------------------------------------------------------
// 4. Following the Concern
// ---------------------------------------------------------------------------

test('a CAPA follows its Concern when the Concern is escalated', async () => {
  const ground = await makeGround({ areaGrant: true });

  const opened = await openCapa(ground.engineer.token, ground.concern.id, {});
  assert.strictEqual(opened.status, 201, JSON.stringify(opened.body));
  assert.strictEqual(opened.body.capa.orgUnitId, String(ground.line.id));

  const handed = await escalate(ground.engineer.token, ground.concern.id, ground.area.id);
  assert.strictEqual(handed.status, 200, JSON.stringify(handed.body));

  // The investigation is now filed where the problem now belongs, so the tier
  // that owns the problem owns the investigation.
  const read = await readCapa(ground.engineer.token, opened.body.capa.id);
  assert.strictEqual(read.body.capa.orgUnitId, String(ground.area.id));
  assert.strictEqual(read.body.capa.orgUnitName, 'Foundry');

  // Nothing else about the CAPA moved: this is an escalation of the Concern,
  // not of the investigation, and the CAPA's own status, team and dates are
  // untouched by it.
  assert.strictEqual(read.body.capa.status, 'open');
  assert.strictEqual(read.body.capa.teamLead, null);
  assert.strictEqual(read.body.capa.concern.id, String(ground.concern.id));
  // The Concern's own Org Unit is where the problem happened, and stays there.
  assert.strictEqual(read.body.capa.concern.orgUnitId, String(ground.line.id));
  assert.strictEqual(read.body.capa.concern.escalatedToOrgUnitName, 'Foundry');
});
