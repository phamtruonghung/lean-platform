/*
 * The two 5 Why chains on a CAPA (issue #210) — adding, revising, moving,
 * removing and concluding a Why, over HTTP, against a real database and a real
 * (locally issued) JWKS. The seam, the fixture scaffolding and the
 * dependency-ordered cleanup are the ones capas.test.js and actions.test.js
 * already establish.
 *
 * What this file claims, one test per rule the ticket states: a Why is added at
 * the next position of its chain and each chain reads in order; a Why can be
 * revised and moved while the CAPA is open; removing one leaves the chain
 * contiguous; at most one Why per chain is the confirmed root cause, marking a
 * second replaces the first, and marking can be undone; every write needs edit
 * access at the CAPA's Org Unit or a place on its team (403), and a closed CAPA
 * refuses all three (409).
 *
 * **Three assertions in this file read Postgres directly rather than over
 * HTTP, and each says why where it stands.** `schema.test.js` and
 * `views.test.js` are the suite's named exception to the two-test-seams rule
 * and this file takes the same licence for the same reason: a rule with no HTTP
 * door has no other way to be stated. They are the partial unique index that
 * makes "one root cause per chain" true for a writer that does not use the
 * service, and the two CHECKs that say only a Why is in a chain and only a Why
 * is a chain's root.
 *
 * **A closed CAPA is arranged directly, and that is deliberate.** Closing one
 * is #211's own ticket, so no sequence of requests on this branch can produce a
 * closed investigation; `insertClosedCapa` below writes the row the way
 * `plant.test.js` writes the rows its own Module cannot yet create, and removes
 * it in `after()`. There is no route that exists only for this test.
 *
 * Needs a database with every migration applied, including
 * 1800200000000_why-chains-on-a-capa.js. Set DATABASE_URL first — see the
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

// An Account, optionally holding Grants and optionally linked to an Employee
// (`app_users.employee_id`). The Employee link is what the team half of this
// ticket's write rule reads: an Account with no Grants anywhere still writes a
// CAPA's chains if its Employee has a place on the team.
async function insertAccount({
  role = 'operator',
  displayName = null,
  grants = [],
  employeeId = null
} = {}) {
  const subject = uniqueCode('whacct');
  const name = displayName ?? `Why Account ${subject}`;
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
    [uniqueCode('WHAS'), 'Why Test Site', 'Asia/Ho_Chi_Minh']
  );
  insertedSiteIds.push(site.id);
  return site;
}

async function insertOrgUnit(siteId, { parentId = null, unitType = 'area', name = 'Why Unit' } = {}) {
  const { rows: [orgUnit] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, $2, $3, $4, $5) RETURNING id, code, name, path`,
    [siteId, parentId, uniqueCode('WHAOU'), name, unitType]
  );
  insertedOrgUnitIds.push(orgUnit.id);
  return orgUnit;
}

async function insertEmployee({ first = 'Ann', last = 'Fitter', isActive = true } = {}) {
  const { rows: [employee] } = await pool.query(
    `INSERT INTO employees (employee_no, first_name, last_name, is_active)
     VALUES ($1, $2, $3, $4) RETURNING id, display_name, is_active`,
    [uniqueCode('WHAEMP'), first, last, isActive]
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
 * never verified ("an 8D that was never verified is a 7D"). A closed CAPA that
 * never had that check is not a row this schema admits, so the fixture is a
 * *real* closed investigation: verified, then closed, in that order.
 */
async function insertClosedCapa(orgUnitId, status = 'closed') {
  const { rows: [capa] } = await pool.query(
    `INSERT INTO capas (capa_no, title, problem_statement, method, org_unit_id,
                        status, closed_at, effectiveness_verified_at)
     VALUES ($1, $2, $3, '8d', $4, $5, now(), now()) RETURNING id, capa_no`,
    [
      uniqueCode('WHAC'),
      'An investigation that is already over',
      'Closed before this test started.',
      orgUnitId,
      status
    ]
  );
  insertedCapaIds.push(capa.id);
  return capa;
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

async function removeWhy(token, capaId, whyId) {
  const response = await fetch(`${base}/api/actions/capas/${capaId}/whys/${whyId}`, {
    method: 'DELETE',
    headers: token
  });
  return json(response);
}

/**
 * A chain off a CAPA read, as `{ id, sequence, statement, isRoot }` — the shape
 * every assertion here reads, so a test names the order it expects rather than
 * counting rows.
 */
function chainOf(capa, chain) {
  return capa.whys
    .filter((why) => why.chain === chain)
    .map((why) => ({
      id: why.id,
      sequence: why.sequence,
      statement: why.statement,
      isRoot: why.isRoot
    }));
}

function statementsOf(capa, chain) {
  return chainOf(capa, chain).map((why) => why.statement);
}

function rootsOf(capa, chain) {
  return chainOf(capa, chain).filter((why) => why.isRoot).map((why) => why.statement);
}

/**
 * The ground every test starts from: a Site with an area and a line beneath it,
 * an engineer who may write at the line (the caller every permitted write is
 * made by), two Employees of the directory, and one Concern raised on the line
 * with a CAPA opened on it.
 *
 * The CAPA is opened through the API, which is how it is opened in life: the
 * investigation's own read — its id, its team, its Concern — is what every Why
 * written below hangs off.
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

  return { site, area, line, engineer, lead, member, concern: raised.body.action, capa: opened.body.capa };
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
  // Children before parents, and the CAPA's own links first. The Whys cascade
  // from their CAPA (`capa_root_causes_capa_id_fkey` is ON DELETE CASCADE), and
  // so does the team — but the Concern's `capa_id` does not: it is a plain
  // foreign key, so the Actions have to stop pointing at the CAPA *before* the
  // CAPA row goes. Deleting in the wrong order here does not fail fast: it
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
// 1. Adding Whys, and the order a chain reads in
// ---------------------------------------------------------------------------

test('a Why is added to either chain at the next position, and each chain is returned in order', async () => {
  const ground = await makeGround();

  // Nothing yet: both chains read as empty rather than as absent, so a Screen
  // renders "no Whys yet" from a list it already has.
  const empty = await readCapa(ground.engineer.token, ground.capa.id);
  assert.strictEqual(empty.status, 200, JSON.stringify(empty.body));
  assert.deepStrictEqual(empty.body.capa.whys, []);

  const occurrence = [
    'The guard works loose after about 400 cycles.',
    'The fastener was not torqued to the standard.',
    'The torque step is not on the check sheet.'
  ];
  const escape = [
    'The guard is behind the machine, so nobody looks at it.',
    'The start-up check stops at the operator panel.'
  ];

  for (const statement of occurrence) {
    const added = await addWhy(ground.engineer.token, ground.capa.id, {
      chain: 'occurrence',
      statement
    });
    assert.strictEqual(added.status, 201, JSON.stringify(added.body));
  }
  for (const statement of escape) {
    const added = await addWhy(ground.engineer.token, ground.capa.id, {
      chain: 'escape',
      statement
    });
    assert.strictEqual(added.status, 201, JSON.stringify(added.body));
  }

  // The answer to the last add is the whole CAPA, and it carries both chains:
  // `occurrence` first — you work out what went wrong before you ask why nobody
  // caught it — and each chain in the order its Whys were reasoned.
  const read = await readCapa(ground.engineer.token, ground.capa.id);
  assert.strictEqual(read.status, 200, JSON.stringify(read.body));
  const capa = read.body.capa;

  assert.deepStrictEqual(
    capa.whys.map((why) => why.chain),
    ['occurrence', 'occurrence', 'occurrence', 'escape', 'escape']
  );
  assert.deepStrictEqual(statementsOf(capa, 'occurrence'), occurrence);
  assert.deepStrictEqual(statementsOf(capa, 'escape'), escape);

  // Positions are the chain's own, counting from 1: adding to the escape chain
  // does not continue the occurrence chain's numbering.
  assert.deepStrictEqual(chainOf(capa, 'occurrence').map((why) => why.sequence), [1, 2, 3]);
  assert.deepStrictEqual(chainOf(capa, 'escape').map((why) => why.sequence), [1, 2]);

  // A fresh Why is nobody's root cause yet: the chain has not concluded.
  assert.deepStrictEqual(
    capa.whys.filter((why) => why.isRoot),
    []
  );

  // A chain that is neither of the two is a 400 naming them, and nothing is
  // written — the value is checked where the set of chains is known rather than
  // left to the column's CHECK constraint.
  const wrongChain = await addWhy(ground.engineer.token, ground.capa.id, {
    chain: 'detection',
    statement: 'Why it was not detected, said the wrong way.'
  });
  assert.strictEqual(wrongChain.status, 400, JSON.stringify(wrongChain.body));
  assert.match(wrongChain.body.message, /occurrence, escape/);

  // A Why has to say something: an empty statement is a step that is not there.
  const emptyStatement = await addWhy(ground.engineer.token, ground.capa.id, {
    chain: 'occurrence',
    statement: '   '
  });
  assert.strictEqual(emptyStatement.status, 400, JSON.stringify(emptyStatement.body));
  const missingStatement = await addWhy(ground.engineer.token, ground.capa.id, {
    chain: 'occurrence'
  });
  assert.strictEqual(missingStatement.status, 400, JSON.stringify(missingStatement.body));

  // None of the three refusals wrote anything.
  const afterRefusals = await readCapa(ground.engineer.token, ground.capa.id);
  assert.deepStrictEqual(statementsOf(afterRefusals.body.capa, 'occurrence'), occurrence);
});

// ---------------------------------------------------------------------------
// 2. Revising, moving and removing
// ---------------------------------------------------------------------------

test('a Why can be revised and moved while the CAPA is open', async () => {
  const ground = await makeGround();
  for (const statement of ['First', 'Second', 'Third']) {
    const added = await addWhy(ground.engineer.token, ground.capa.id, {
      chain: 'occurrence',
      statement
    });
    assert.strictEqual(added.status, 201, JSON.stringify(added.body));
  }
  const opened = await readCapa(ground.engineer.token, ground.capa.id);
  const [first, second, third] = chainOf(opened.body.capa, 'occurrence');

  // Revised: what it says changes, and nothing about where it sits or whether
  // it is the root does.
  const revised = await changeWhy(ground.engineer.token, ground.capa.id, second.id, {
    statement: 'Second, revised'
  });
  assert.strictEqual(revised.status, 200, JSON.stringify(revised.body));
  const revisedChain = chainOf(revised.body.capa, 'occurrence');
  assert.deepStrictEqual(
    revisedChain.map((why) => `${why.sequence}:${why.statement}`),
    ['1:First', '2:Second, revised', '3:Third']
  );
  assert.deepStrictEqual(revisedChain.map((why) => why.id), [first.id, second.id, third.id]);
  assert.deepStrictEqual(revisedChain.map((why) => why.isRoot), [false, false, false]);

  // Moved: the third Why becomes the first, and the chain is renumbered around
  // it — the positions stay 1..n, so "the second Why" still means one row.
  const moved = await changeWhy(ground.engineer.token, ground.capa.id, third.id, {
    sequence: 1
  });
  assert.strictEqual(moved.status, 200, JSON.stringify(moved.body));
  assert.deepStrictEqual(
    chainOf(moved.body.capa, 'occurrence').map((why) => `${why.sequence}:${why.statement}`),
    ['1:Third', '2:First', '3:Second, revised']
  );

  // And back again, so a move is a position rather than a direction.
  const movedBack = await changeWhy(ground.engineer.token, ground.capa.id, third.id, {
    sequence: 3
  });
  assert.strictEqual(movedBack.status, 200, JSON.stringify(movedBack.body));
  assert.deepStrictEqual(
    chainOf(movedBack.body.capa, 'occurrence').map((why) => why.statement),
    ['First', 'Second, revised', 'Third']
  );

  // Two fields at once are one change: the Why is reworded and moved together,
  // which is what a form holding both is.
  const both = await changeWhy(ground.engineer.token, ground.capa.id, first.id, {
    statement: 'First, said again',
    sequence: 3
  });
  assert.strictEqual(both.status, 200, JSON.stringify(both.body));
  assert.deepStrictEqual(
    chainOf(both.body.capa, 'occurrence').map((why) => `${why.sequence}:${why.statement}`),
    ['1:Second, revised', '2:Third', '3:First, said again']
  );

  // The refusals, one per field: an empty statement, a position outside the
  // chain, an `isRoot` that is not a boolean, a body naming nothing at all.
  const blanks = [
    await changeWhy(ground.engineer.token, ground.capa.id, first.id, { statement: '  ' }),
    await changeWhy(ground.engineer.token, ground.capa.id, first.id, { statement: 12 }),
    await changeWhy(ground.engineer.token, ground.capa.id, first.id, { sequence: 0 }),
    await changeWhy(ground.engineer.token, ground.capa.id, first.id, { sequence: 4 }),
    await changeWhy(ground.engineer.token, ground.capa.id, first.id, { sequence: 1.5 }),
    await changeWhy(ground.engineer.token, ground.capa.id, first.id, { isRoot: 'yes' }),
    await changeWhy(ground.engineer.token, ground.capa.id, first.id, {})
  ];
  for (const refused of blanks) {
    assert.strictEqual(refused.status, 400, JSON.stringify(refused.body));
  }

  // And an id that is nobody's: a number not in this CAPA, a number not in any
  // CAPA, and a value that is not an id at all — all three are a clean 404
  // rather than a database error about a BIGINT parameter.
  const unknown = await changeWhy(ground.engineer.token, ground.capa.id, 999999999, {
    statement: 'Nobody wrote this.'
  });
  assert.strictEqual(unknown.status, 404, JSON.stringify(unknown.body));
  const gone = await changeWhy(ground.engineer.token, ground.capa.id, 'not-an-id', {
    statement: 'Nobody wrote this either.'
  });
  assert.strictEqual(gone.status, 404, JSON.stringify(gone.body));

  // None of the refusals changed the chain.
  const settled = await readCapa(ground.engineer.token, ground.capa.id);
  assert.deepStrictEqual(
    chainOf(settled.body.capa, 'occurrence').map((why) => why.statement),
    ['Second, revised', 'Third', 'First, said again']
  );
});

test('removing a Why from the middle leaves its chain contiguous', async () => {
  const ground = await makeGround();
  for (const statement of ['First', 'Second', 'Third', 'Fourth']) {
    const added = await addWhy(ground.engineer.token, ground.capa.id, {
      chain: 'occurrence',
      statement
    });
    assert.strictEqual(added.status, 201, JSON.stringify(added.body));
  }
  // A second chain, so the removal is proved to renumber only its own.
  const escape = await addWhy(ground.engineer.token, ground.capa.id, {
    chain: 'escape',
    statement: 'Nobody re-checked the fixture between shifts.'
  });
  assert.strictEqual(escape.status, 201, JSON.stringify(escape.body));

  const opened = await readCapa(ground.engineer.token, ground.capa.id);
  const [, second, , fourth] = chainOf(opened.body.capa, 'occurrence');

  const removed = await removeWhy(ground.engineer.token, ground.capa.id, second.id);
  assert.strictEqual(removed.status, 200, JSON.stringify(removed.body));
  assert.deepStrictEqual(chainOf(removed.body.capa, 'occurrence'), [
    { id: chainOf(opened.body.capa, 'occurrence')[0].id, sequence: 1, statement: 'First', isRoot: false },
    { id: chainOf(opened.body.capa, 'occurrence')[2].id, sequence: 2, statement: 'Third', isRoot: false },
    { id: fourth.id, sequence: 3, statement: 'Fourth', isRoot: false }
  ]);
  // The other chain is untouched: a position belongs to a chain, not to the
  // CAPA.
  assert.deepStrictEqual(chainOf(removed.body.capa, 'escape').map((why) => why.sequence), [1]);

  // The removed Why is really gone: reading it back is a 404 on the same
  // address that wrote it a moment ago.
  const again = await removeWhy(ground.engineer.token, ground.capa.id, second.id);
  assert.strictEqual(again.status, 404, JSON.stringify(again.body));

  // Removing the whole chain leaves it empty rather than leaving a hole, and
  // the next Why added to it starts at 1 again.
  for (const why of chainOf(removed.body.capa, 'occurrence')) {
    const each = await removeWhy(ground.engineer.token, ground.capa.id, why.id);
    assert.strictEqual(each.status, 200, JSON.stringify(each.body));
  }
  const emptied = await readCapa(ground.engineer.token, ground.capa.id);
  assert.deepStrictEqual(chainOf(emptied.body.capa, 'occurrence'), []);
  const restarted = await addWhy(ground.engineer.token, ground.capa.id, {
    chain: 'occurrence',
    statement: 'Asked again from the start.'
  });
  assert.strictEqual(restarted.status, 201, JSON.stringify(restarted.body));
  assert.deepStrictEqual(chainOf(restarted.body.capa, 'occurrence').map((why) => why.sequence), [1]);
});

// ---------------------------------------------------------------------------
// 3. The confirmed root cause of a chain
// ---------------------------------------------------------------------------

test('at most one Why per chain is the confirmed root cause, and marking a second replaces the first', async () => {
  const ground = await makeGround();
  const occurrences = ['First', 'Second', 'Third'];
  for (const statement of occurrences) {
    await addWhy(ground.engineer.token, ground.capa.id, { chain: 'occurrence', statement });
  }
  for (const statement of ['The escape', 'The deeper escape']) {
    await addWhy(ground.engineer.token, ground.capa.id, { chain: 'escape', statement });
  }

  const opened = await readCapa(ground.engineer.token, ground.capa.id);
  const [first, second, third] = chainOf(opened.body.capa, 'occurrence');
  const [escapeOne, escapeTwo] = chainOf(opened.body.capa, 'escape');

  const marked = await changeWhy(ground.engineer.token, ground.capa.id, second.id, {
    isRoot: true
  });
  assert.strictEqual(marked.status, 200, JSON.stringify(marked.body));
  assert.deepStrictEqual(rootsOf(marked.body.capa, 'occurrence'), ['Second']);

  // Marking a second replaces the first — one statement that unmarks and one
  // that marks, in one transaction. It is not a refusal: the team changed its
  // mind about where the chain stopped.
  const replaced = await changeWhy(ground.engineer.token, ground.capa.id, third.id, {
    isRoot: true
  });
  assert.strictEqual(replaced.status, 200, JSON.stringify(replaced.body));
  assert.deepStrictEqual(rootsOf(replaced.body.capa, 'occurrence'), ['Third']);
  assert.strictEqual(chainOf(replaced.body.capa, 'occurrence')[1].isRoot, false);

  // Each chain has its own root cause, and marking one in the escape chain
  // leaves the occurrence chain's where it was: the rule is per chain.
  const escaped = await changeWhy(ground.engineer.token, ground.capa.id, escapeTwo.id, {
    isRoot: true
  });
  assert.strictEqual(escaped.status, 200, JSON.stringify(escaped.body));
  assert.deepStrictEqual(rootsOf(escaped.body.capa, 'occurrence'), ['Third']);
  assert.deepStrictEqual(rootsOf(escaped.body.capa, 'escape'), ['The deeper escape']);

  // And it can be undone while the CAPA is open: a chain with no root is a
  // chain still being reasoned, which is exactly the state #211 refuses to
  // close on.
  const undone = await changeWhy(ground.engineer.token, ground.capa.id, escapeTwo.id, {
    isRoot: false
  });
  assert.strictEqual(undone.status, 200, JSON.stringify(undone.body));
  assert.deepStrictEqual(rootsOf(undone.body.capa, 'escape'), []);
  assert.deepStrictEqual(rootsOf(undone.body.capa, 'occurrence'), ['Third']);

  // Unmarking one that was never marked is not an error — it leaves the chain
  // where it is, which is what "undo" means when there is nothing to undo.
  const noop = await changeWhy(ground.engineer.token, ground.capa.id, escapeOne.id, {
    isRoot: false
  });
  assert.strictEqual(noop.status, 200, JSON.stringify(noop.body));
  assert.deepStrictEqual(rootsOf(noop.body.capa, 'occurrence'), ['Third']);

  // Removing the root cause leaves the chain without one: which remaining Why
  // is the root is a decision the team makes again, not a promotion.
  const removed = await removeWhy(ground.engineer.token, ground.capa.id, third.id);
  assert.strictEqual(removed.status, 200, JSON.stringify(removed.body));
  assert.deepStrictEqual(rootsOf(removed.body.capa, 'occurrence'), []);
  assert.deepStrictEqual(
    chainOf(removed.body.capa, 'occurrence').map((why) => why.statement),
    ['First', 'Second']
  );

  // The root travels with the Why it is on: moving it does not move the answer,
  // and a blank Why is still the chain's conclusion after a reorder.
  const markedFirst = await changeWhy(ground.engineer.token, ground.capa.id, first.id, {
    isRoot: true
  });
  assert.strictEqual(markedFirst.status, 200, JSON.stringify(markedFirst.body));
  const reordered = await changeWhy(ground.engineer.token, ground.capa.id, first.id, {
    sequence: 2
  });
  assert.strictEqual(reordered.status, 200, JSON.stringify(reordered.body));
  assert.deepStrictEqual(
    chainOf(reordered.body.capa, 'occurrence').map((why) => `${why.sequence}:${why.statement}`),
    ['1:Second', '2:First']
  );
  assert.deepStrictEqual(rootsOf(reordered.body.capa, 'occurrence'), ['First']);
});

test('the database keeps one confirmed root cause per chain', async () => {
  // Read directly (see this file's header): `capa_root_causes_one_root_per_chain`
  // is the constraint that makes the rule true for a writer that does not go
  // through the service, so the honest way to test it is to be that writer for
  // one statement.
  const ground = await makeGround();
  for (const statement of ['First', 'Second']) {
    await addWhy(ground.engineer.token, ground.capa.id, { chain: 'occurrence', statement });
  }
  const opened = await readCapa(ground.engineer.token, ground.capa.id);
  const [first, second] = chainOf(opened.body.capa, 'occurrence');
  await changeWhy(ground.engineer.token, ground.capa.id, first.id, { isRoot: true });

  // A second root in the same chain is refused by the index, whatever wrote it.
  await assert.rejects(
    () =>
      pool.query('UPDATE capa_root_causes SET is_root = TRUE WHERE id = $1', [second.id]),
    (error) =>
      error.code === '23505' && error.constraint === 'capa_root_causes_one_root_per_chain',
    'a chain ended up with two root causes'
  );

  // A chain that is not this one is a different key, so the same row may be the
  // root of its own chain — the rule is one per chain, not one per CAPA.
  const escape = await addWhy(ground.engineer.token, ground.capa.id, {
    chain: 'escape',
    statement: 'The escape'
  });
  assert.strictEqual(escape.status, 201, JSON.stringify(escape.body));
  const escapeWhy = chainOf(escape.body.capa, 'escape')[0];
  await pool.query('UPDATE capa_root_causes SET is_root = TRUE WHERE id = $1', [escapeWhy.id]);
  const after = await readCapa(ground.engineer.token, ground.capa.id);
  assert.deepStrictEqual(rootsOf(after.body.capa, 'occurrence'), ['First']);
  assert.deepStrictEqual(rootsOf(after.body.capa, 'escape'), ['The escape']);

  // The other two rules this migration adds, in the same direct-reading
  // spirit: a Why is in a chain, and only a Why is a chain's root.
  await assert.rejects(
    () =>
      pool.query(
        `INSERT INTO capa_root_causes (capa_id, cause_type, sequence, statement)
         VALUES ($1, 'why', 9, 'A Why in no chain')`,
        [ground.capa.id]
      ),
    (error) =>
      error.code === '23514' && error.constraint === 'capa_root_causes_chain_is_a_why',
    'a Why belonged to no chain'
  );

  await assert.rejects(
    () =>
      pool.query(
        `INSERT INTO capa_root_causes (capa_id, cause_type, category, sequence, statement, is_root)
         VALUES ($1, 'fishbone', 'man', 1, 'The operator was not trained', TRUE)`,
        [ground.capa.id]
      ),
    (error) =>
      error.code === '23514' && error.constraint === 'capa_root_causes_root_is_a_why',
    'a fishbone candidate was the root cause of a chain'
  );
});

// ---------------------------------------------------------------------------
// 4. Who may write a chain, and when
// ---------------------------------------------------------------------------

test('writing a chain needs edit access at the CAPA Org Unit or a place on its team', async () => {
  const ground = await makeGround({ teamLead: 'lead', teamMembers: ['member'] });

  const added = await addWhy(ground.engineer.token, ground.capa.id, {
    chain: 'occurrence',
    statement: 'The guard works loose.'
  });
  assert.strictEqual(added.status, 201, JSON.stringify(added.body));
  const whyId = chainOf(added.body.capa, 'occurrence')[0].id;

  // Nobody: an Account with no Grant anywhere and no place on the team. All
  // three writes are refused, and the refusal says what would be needed.
  const stranger = await insertAccount({ displayName: 'Nobody In Particular' });
  const refusedAdd = await addWhy(stranger.token, ground.capa.id, {
    chain: 'occurrence',
    statement: 'Not this caller to write.'
  });
  assert.strictEqual(refusedAdd.status, 403, JSON.stringify(refusedAdd.body));
  assert.match(refusedAdd.body.message, /edit access|place on its team/);
  const refusedChange = await changeWhy(stranger.token, ground.capa.id, whyId, {
    statement: 'Not this caller to write.'
  });
  assert.strictEqual(refusedChange.status, 403, JSON.stringify(refusedChange.body));
  const refusedRemove = await removeWhy(stranger.token, ground.capa.id, whyId);
  assert.strictEqual(refusedRemove.status, 403, JSON.stringify(refusedRemove.body));

  // A read Grant is not edit access: reading a CAPA is Site-wide, writing one
  // is not.
  const reader = await insertAccount({
    displayName: 'Line Reader',
    grants: [{ orgUnitId: ground.line.id, write: false }]
  });
  const alsoRefused = await addWhy(reader.token, ground.capa.id, {
    chain: 'occurrence',
    statement: 'Read, and nothing more.'
  });
  assert.strictEqual(alsoRefused.status, 403, JSON.stringify(alsoRefused.body));

  // Nothing any of them sent landed.
  const unchanged = await readCapa(ground.engineer.token, ground.capa.id);
  assert.deepStrictEqual(statementsOf(unchanged.body.capa, 'occurrence'), ['The guard works loose.']);

  // A write Grant at the CAPA's Org Unit is enough on its own — the supervisor
  // who is on nobody's team but works the line.
  const supervisor = await insertAccount({
    displayName: 'Line Supervisor',
    grants: [{ orgUnitId: ground.line.id, write: true, quality: false }]
  });
  const byGrant = await addWhy(supervisor.token, ground.capa.id, {
    chain: 'escape',
    statement: 'The fixing was not checked between shifts.'
  });
  assert.strictEqual(byGrant.status, 201, JSON.stringify(byGrant.body));

  // And a place on the team is enough on its own: an Account with no Grant at
  // all whose Employee is a member of this CAPA's team writes the chain. This
  // is the whole "or" — an engineer on the investigation is not necessarily a
  // Grant-holder.
  const memberAccount = await insertAccount({
    displayName: 'Bo Member',
    employeeId: ground.member.id
  });
  const byTeam = await addWhy(memberAccount.token, ground.capa.id, {
    chain: 'occurrence',
    statement: 'The check sheet has no torque step.'
  });
  assert.strictEqual(byTeam.status, 201, JSON.stringify(byTeam.body));

  // The lead is on the team as much as the members are.
  const leadAccount = await insertAccount({
    displayName: 'Ada Lead',
    employeeId: ground.lead.id
  });
  const byLead = await changeWhy(leadAccount.token, ground.capa.id, whyId, {
    statement: 'The guard works loose after about 400 cycles.'
  });
  assert.strictEqual(byLead.status, 200, JSON.stringify(byLead.body));
  const leadRemoves = await removeWhy(leadAccount.token, ground.capa.id, whyId);
  assert.strictEqual(leadRemoves.status, 200, JSON.stringify(leadRemoves.body));

  // An Employee of the directory who holds no Grant and is on no team is still
  // nobody, even though their Account is linked to a real person.
  const bystander = await insertAccount({
    displayName: 'Cyd Bystander',
    employeeId: (await insertEmployee({ first: 'Cyd', last: 'Bystander' })).id
  });
  const bystanderRefused = await addWhy(bystander.token, ground.capa.id, {
    chain: 'occurrence',
    statement: 'A real person, and still not on the team.'
  });
  assert.strictEqual(bystanderRefused.status, 403, JSON.stringify(bystanderRefused.body));

  // Reading a CAPA with its chains is Site-wide, the same as reading an Action:
  // scope decides where somebody may act, not what they may read. The stranger
  // still reads both chains.
  const readable = await readCapa(stranger.token, ground.capa.id);
  assert.strictEqual(readable.status, 200, JSON.stringify(readable.body));
  assert.deepStrictEqual(
    readable.body.capa.whys.map((why) => why.chain).sort(),
    ['escape', 'occurrence']
  );

  // And an unknown CAPA is a 404 before any of it — the address does not name
  // anything, whoever is asking.
  const missing = await addWhy(ground.engineer.token, 999999999, {
    chain: 'occurrence',
    statement: 'Nowhere.'
  });
  assert.strictEqual(missing.status, 404, JSON.stringify(missing.body));
  const malformed = await addWhy(ground.engineer.token, 'not-an-id', {
    chain: 'occurrence',
    statement: 'Nowhere.'
  });
  assert.strictEqual(malformed.status, 404, JSON.stringify(malformed.body));
});

test('a closed CAPA refuses every write to its chains', async () => {
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

    const added = await addWhy(engineer.token, closed.id, {
      chain: 'occurrence',
      statement: 'Nothing may be written here any more.'
    });
    assert.strictEqual(added.status, 409, JSON.stringify(added.body));
    assert.match(added.body.message, new RegExp(`this CAPA is ${status}`));

    // The other two writes are refused the same way, and the Why id in the
    // address is never reached: the CAPA is the record that is frozen.
    const changed = await changeWhy(engineer.token, closed.id, 1, { statement: 'Anything.' });
    assert.strictEqual(changed.status, 409, JSON.stringify(changed.body));
    const removed = await removeWhy(engineer.token, closed.id, 1);
    assert.strictEqual(removed.status, 409, JSON.stringify(removed.body));

    // Nothing was written, and the refusal is not the row's fault: it reads
    // back with the status it was given.
    const read = await readCapa(engineer.token, closed.id);
    assert.strictEqual(read.status, 200, JSON.stringify(read.body));
    assert.strictEqual(read.body.capa.status, status);
    assert.deepStrictEqual(read.body.capa.whys, []);
  }

  // Scope is asked before status, and deliberately: a caller with neither edit
  // access nor a place on the team gets the 403 the route can answer without
  // reading the row's own state, and only somebody who may write at all learns
  // whether the investigation is over. An unknown CAPA is a 404 before both.
  const stranger = await insertAccount({ displayName: 'Nobody In Particular' });
  const closed = await insertClosedCapa(line.id, 'closed');
  const refused = await addWhy(stranger.token, closed.id, {
    chain: 'occurrence',
    statement: 'Not this caller, on a closed CAPA.'
  });
  assert.strictEqual(refused.status, 403, JSON.stringify(refused.body));
});
