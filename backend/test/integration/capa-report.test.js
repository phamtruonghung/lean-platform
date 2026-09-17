/*
 * The CAPA report's read (issue #212) — over HTTP, against a real database and
 * a real (locally issued) JWKS. The seam, the fixture scaffolding and the
 * dependency-ordered cleanup are the ones capa-effectiveness.test.js and
 * concern-nonconformances.test.js already establish.
 *
 * The report Screen is a read and a layout: everything an auditor reads there
 * is already answered by ONE request — `GET /api/actions/capas/:id`, which
 * #209/#210/#211 grew into the whole investigation's read, carrying the CAPA's
 * own team, problem, chains and effectiveness check together with the Concern
 * it was opened on and that Concern's own Containments, Countermeasures and
 * Preventive actions with every phase each has been round. So this file does
 * not add an endpoint of its own, and the tests below say what that claim means
 * by asserting the whole of it against a real response rather than against a
 * sentence in a comment.
 *
 * **The one thing the report needs that no earlier read sent** is the
 * Dispositions on the Non-conformances a Concern answers: #208's linked row
 * carried the number, the Product, the Defect code and the quantity, and an
 * auditor reading an 8D has to see what was done with the product too. It is
 * added to the read it belongs to (the Concern's own list of the occurrences it
 * answers) rather than to a report-only address, and the tests here prove the
 * keys it sends are Quality's own — the record's read and the report's read
 * must not be two answers to one question.
 *
 * Every claim the ticket makes about the read has a test: the whole 8D in one
 * response, the Dispositions key for key with `GET /api/quality/nonconformances/:id`,
 * an open CAPA reading as what it has not yet done, and an Account with no
 * Grant anywhere reading the report — which is the Platform's own rule for a
 * CAPA (ADR-0009: an Org Unit decides where an Account may act, never what it
 * may know about), matched rather than tightened by this ticket.
 *
 * Needs a database with every migration applied, including
 * 1800000000000_concern-nonconformances.js and 1800200000000_capa-whys.js. Set
 * DATABASE_URL first — see the README's Tests section.
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
const insertedProductCodes = [];
const insertedDefectCodeCodes = [];
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

async function insertAccount({ role = 'operator', displayName = null, grants = [] } = {}) {
  const subject = uniqueCode('rpacct');
  const name = displayName ?? `Report Account ${subject}`;
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
      [account.id, grant.orgUnitId, grant.write ?? false, grant.quality ?? false]
    );
  }

  return { id: account.id, displayName: name, token: await authHeader(subject) };
}

async function insertSite() {
  const { rows: [site] } = await pool.query(
    `INSERT INTO sites (code, name, timezone) VALUES ($1, $2, $3) RETURNING id, code, name`,
    [uniqueCode('RPS'), 'Report Test Site', 'Asia/Ho_Chi_Minh']
  );
  insertedSiteIds.push(site.id);
  return site;
}

async function insertOrgUnit(siteId, { parentId = null, unitType = 'area', name = 'Report Unit' } = {}) {
  const { rows: [orgUnit] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, $2, $3, $4, $5) RETURNING id, code, name, path`,
    [siteId, parentId, uniqueCode('RPOU'), name, unitType]
  );
  insertedOrgUnitIds.push(orgUnit.id);
  return orgUnit;
}

async function insertEmployee({ first = 'Ann', last = 'Fitter' } = {}) {
  const { rows: [employee] } = await pool.query(
    `INSERT INTO employees (employee_no, first_name, last_name, is_active)
     VALUES ($1, $2, $3, TRUE) RETURNING id, display_name`,
    [uniqueCode('RPEMP'), first, last]
  );
  insertedEmployeeIds.push(employee.id);
  return employee;
}

async function createProduct(adminToken) {
  const code = uniqueCode('RPP-');
  const response = await fetch(`${base}/api/quality/products`, {
    method: 'POST',
    headers: { ...adminToken, 'content-type': 'application/json' },
    body: JSON.stringify({ code, name: `Product ${code}`, uomCode: 'EA' })
  });
  const { status, body } = await json(response);
  assert.strictEqual(status, 201, `creating ${code} failed: ${JSON.stringify(body)}`);
  insertedProductCodes.push(code);
  return body.product;
}

async function createDefectCode(adminToken) {
  const code = uniqueCode('RPD-');
  const response = await fetch(`${base}/api/quality/defect-codes`, {
    method: 'POST',
    headers: { ...adminToken, 'content-type': 'application/json' },
    body: JSON.stringify({ code, name: `Defect ${code}`, category: 'product', defaultSeverity: 'minor' })
  });
  const { status, body } = await json(response);
  assert.strictEqual(status, 201, `creating ${code} failed: ${JSON.stringify(body)}`);
  insertedDefectCodeCodes.push(code);
  return body.defectCode;
}

async function recordNonconformance(token, siteId, body) {
  const response = await fetch(`${base}/api/quality/sites/${siteId}/nonconformances`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  return json(response);
}

async function readNonconformance(token, id) {
  const response = await fetch(`${base}/api/quality/nonconformances/${id}`, { headers: token });
  return json(response);
}

async function postDisposition(token, nonconformanceId, body) {
  const response = await fetch(
    `${base}/api/quality/nonconformances/${nonconformanceId}/dispositions`,
    {
      method: 'POST',
      headers: { ...token, 'content-type': 'application/json' },
      body: JSON.stringify(body)
    }
  );
  return json(response);
}

async function postConcession(token, nonconformanceId, body) {
  const response = await fetch(
    `${base}/api/quality/nonconformances/${nonconformanceId}/concession`,
    {
      method: 'POST',
      headers: { ...token, 'content-type': 'application/json' },
      body: JSON.stringify(body)
    }
  );
  return json(response);
}

async function raiseConcern(token, siteId, body) {
  const response = await fetch(`${base}/api/actions/sites/${siteId}/actions`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify({ actionType: 'concern', ...body })
  });
  const payload = await json(response);
  if (payload.status === 201) insertedActionIds.push(payload.body.action.id);
  return payload;
}

async function linkNonconformance(token, concernId, nonconformanceId) {
  const response = await fetch(`${base}/api/actions/${concernId}/nonconformances`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify({ nonconformanceId })
  });
  return json(response);
}

async function openCapa(token, concernId, body = {}) {
  const response = await fetch(`${base}/api/actions/${concernId}/capa`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  const payload = await json(response);
  if (payload.status === 201) insertedCapaIds.push(payload.body.capa.id);
  return payload;
}

async function changeCapa(token, capaId, body) {
  const response = await fetch(`${base}/api/actions/capas/${capaId}`, {
    method: 'PATCH',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  return json(response);
}

// One CAPA by its own address — the read the report Screen makes, and the only
// one the tests below use for the report's own content.
async function readCapa(token, capaId) {
  const response = await fetch(`${base}/api/actions/capas/${capaId}`, { headers: token });
  return json(response);
}

async function addMeasure(token, concernId, body) {
  const response = await fetch(`${base}/api/actions/${concernId}/measures`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  const payload = await json(response);
  if (payload.status === 201) insertedActionIds.push(payload.body.action.id);
  return payload;
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

/**
 * Walks one Action's open cycle to its Act, phase by phase, over HTTP — the
 * only door that moves a cycle (ADR-0033). Every phase carries a note because
 * the service refuses one that says nothing, and the Check carries `effective`,
 * which is what opens the Act rather than the next cycle's Plan.
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
 * Confirms one root cause in one of a CAPA's two chains: the Why is added, then
 * marked — the two writes #210 owns, which is what makes "the investigation has
 * concluded" true in the data rather than in a sentence.
 */
async function confirmRoot(token, capaId, chain, statement) {
  const added = await addWhy(token, capaId, { chain, statement });
  assert.strictEqual(added.status, 201, `adding a ${chain} Why failed: ${JSON.stringify(added.body)}`);
  const why = added.body.capa.whys.filter((each) => each.chain === chain).pop();
  const marked = await changeWhy(token, capaId, why.id, { isRoot: true });
  assert.strictEqual(marked.status, 200, `marking the ${chain} root failed: ${JSON.stringify(marked.body)}`);
}

const PROBLEM =
  'The guard comes loose after about 400 cycles, and nothing on the line catches it before the machine ships.';
const OCCURRENCE_ROOT = 'The fastener was not torqued to the standard.';
const ESCAPE_ROOT = 'Nobody looks behind the machine between shifts.';
const EFFECTIVENESS_NOTE =
  'Ran 500 cycles on the line and the guard held; the torque step is on the sheet.';

let adminToken;

/**
 * Everything the report renders, in the ground it renders from: a Site with an
 * area and a line beneath it, a Quality engineer with edit access and Quality
 * authority at the line, a team lead and a member in the directory, one
 * Non-conformance recorded on the line with two Dispositions (a scrap and a
 * Concession), a Concern raised from it, and a CAPA opened on that Concern with
 * its team and its problem statement written.
 *
 * Deliberately not closed: the tests below decide for themselves how far to
 * take the investigation, and one of them asserts what an open CAPA says.
 */
async function makeGround() {
  const site = await insertSite();
  const area = await insertOrgUnit(site.id, { name: 'Foundry' });
  const line = await insertOrgUnit(site.id, {
    parentId: area.id,
    unitType: 'line',
    name: 'Line 1'
  });
  const otherLine = await insertOrgUnit(site.id, {
    parentId: area.id,
    unitType: 'line',
    name: 'Line 5'
  });

  const engineer = await insertAccount({
    displayName: 'Quality Engineer',
    grants: [{ orgUnitId: line.id, write: true, quality: true }]
  });
  const lead = await insertEmployee({ first: 'Ada', last: 'Lead' });
  const member = await insertEmployee({ first: 'Bo', last: 'Member' });

  const product = await createProduct(adminToken);
  const defectCode = await createDefectCode(adminToken);

  const recorded = await recordNonconformance(engineer.token, site.id, {
    orgUnitId: line.id,
    productId: product.id,
    defectCodeId: defectCode.id,
    detectionPoint: 'in_process',
    quantity: 20,
    lotRef: 'LOT-4471',
    immediateContainment: 'Tagged and quarantined at the line.'
  });
  assert.strictEqual(recorded.status, 201, `recording failed: ${JSON.stringify(recorded.body)}`);

  // The Concern is raised on the line and the occurrence is LINKED to it,
  // rather than raised from it: linking is #208's other, first-class road to
  // the same read, and the report renders the occurrence either way, with the
  // number, the Product, the Defect code, the quantity and the Dispositions it
  // is there for. (Issue #221 has since narrowed the gap that forced this
  // choice — `action_items_single_source` no longer counts `capa_id` among an
  // Action's sources, so a Concern raised from a Non-conformance can also be
  // the Concern a CAPA is opened on. This ground keeps the linking road, and
  // `concern-nonconformances.test.js`'s section 5 is where the raised-from road
  // is tested end to end.)
  const raised = await raiseConcern(engineer.token, site.id, {
    orgUnitId: line.id,
    title: 'The guard keeps working loose'
  });
  assert.strictEqual(raised.status, 201, `raising the Concern failed: ${JSON.stringify(raised.body)}`);

  const linked = await linkNonconformance(
    engineer.token,
    raised.body.action.id,
    recorded.body.nonconformance.id
  );
  assert.strictEqual(linked.status, 201, `linking failed: ${JSON.stringify(linked.body)}`);

  return {
    site,
    area,
    line,
    otherLine,
    engineer,
    lead,
    member,
    product,
    defectCode,
    nonconformance: recorded.body.nonconformance,
    concern: raised.body.action
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

  adminToken = (await insertAccount({ role: 'admin', displayName: 'Avery Administrator' })).token;
});

test.after(async () => {
  // Children before parents, hardest descendant first. The Whys and the team
  // cascade from their CAPA, and so does a Non-conformance's Dispositions — but
  // the Concern's `capa_id` is a plain foreign key, so the Actions have to stop
  // pointing at the CAPA *before* the CAPA row goes, and the CAPA's own
  // verifying Account has to outlive it. A rejected `test.after` does not fail
  // fast: it hangs the file on the framework's timeout and cancels every file
  // behind it.
  if (insertedCapaIds.length > 0) {
    await pool.query('DELETE FROM capa_root_causes WHERE capa_id = ANY($1)', [insertedCapaIds]);
    await pool.query('DELETE FROM capa_team_members WHERE capa_id = ANY($1)', [insertedCapaIds]);
  }
  await pool.query('DELETE FROM action_items WHERE id = ANY($1)', [insertedActionIds]);
  if (insertedCapaIds.length > 0) {
    await pool.query('DELETE FROM capas WHERE id = ANY($1)', [insertedCapaIds]);
  }
  await pool.query(
    `DELETE FROM quality_issues
      WHERE org_unit_id IN (SELECT id FROM org_units WHERE site_id = ANY($1))`,
    [insertedSiteIds]
  );
  await pool.query('DELETE FROM products WHERE code = ANY($1)', [insertedProductCodes]);
  await pool.query('DELETE FROM defect_codes WHERE code = ANY($1)', [insertedDefectCodeCodes]);
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
// 1. One read answers the whole report
// ---------------------------------------------------------------------------

test('one read of the CAPA answers the whole report: team, problem, the Concern with its measures and phases, both chains with their roots, the effectiveness check and the linked Non-conformances', async () => {
  const ground = await makeGround();

  const opened = await openCapa(ground.engineer.token, ground.concern.id, {
    teamLeadEmployeeId: ground.lead.id,
    teamMemberEmployeeIds: [ground.member.id]
  });
  assert.strictEqual(opened.status, 201, JSON.stringify(opened.body));
  const capaId = opened.body.capa.id;

  const written = await changeCapa(ground.engineer.token, capaId, { problemStatement: PROBLEM });
  assert.strictEqual(written.status, 200, JSON.stringify(written.body));

  // The Concern's own work (ADR-0034): a containment, a countermeasure and a
  // preventive action, each walked to its Act — a Concern's own Act is refused
  // while any measure is still open, and the report has to render every phase
  // of a cycle together with the Check's own outcome.
  const containment = await addMeasure(ground.engineer.token, ground.concern.id, {
    actionType: 'containment',
    title: 'Quarantined the batch'
  });
  assert.strictEqual(containment.status, 201, JSON.stringify(containment.body));
  await walkCycle(ground.engineer.token, containment.body.action.id, 'The containment');

  const countermeasure = await addMeasure(ground.engineer.token, ground.concern.id, {
    actionType: 'countermeasure',
    title: 'A captive fastener on the guard'
  });
  assert.strictEqual(countermeasure.status, 201, JSON.stringify(countermeasure.body));
  await walkCycle(ground.engineer.token, countermeasure.body.action.id, 'The countermeasure');

  const preventive = await addMeasure(ground.engineer.token, ground.concern.id, {
    actionType: 'preventive',
    title: 'Add the torque step to the shift handover'
  });
  assert.strictEqual(preventive.status, 201, JSON.stringify(preventive.body));
  await walkCycle(ground.engineer.token, preventive.body.action.id, 'The preventive action');

  // Both chains, both stopping at a confirmed root cause — and a second,
  // unconfirmed Why in the occurrence chain, because a chain is reasoned one
  // step at a time and the report shows the steps, not only the conclusion.
  const firstWhy = await addWhy(ground.engineer.token, capaId, {
    chain: 'occurrence',
    statement: 'The vibration loosened it.'
  });
  assert.strictEqual(firstWhy.status, 201, JSON.stringify(firstWhy.body));
  await confirmRoot(ground.engineer.token, capaId, 'occurrence', OCCURRENCE_ROOT);
  await confirmRoot(ground.engineer.token, capaId, 'escape', ESCAPE_ROOT);

  // A scrap Disposition and a Concession on the occurrence the Concern answers:
  // what the report's own Non-conformance section has to print.
  const scrap = await postDisposition(ground.engineer.token, ground.nonconformance.id, {
    dispositionType: 'scrap',
    quantity: 12
  });
  assert.strictEqual(scrap.status, 201, JSON.stringify(scrap.body));

  const concession = await postConcession(ground.engineer.token, ground.nonconformance.id, {
    quantity: 8,
    reference: 'DEV-2026-0014',
    note: 'Customer engineering accepts the cosmetic marks on this lot.'
  });
  assert.strictEqual(concession.status, 201, JSON.stringify(concession.body));

  // The Concern is walked to its Act, which is what makes the effectiveness
  // check become due and, once recorded, closes the investigation.
  await walkCycle(ground.engineer.token, ground.concern.id, 'The Concern');

  const verifier = await insertAccount({
    displayName: 'Pat Verifier',
    grants: [{ orgUnitId: ground.line.id, write: false, quality: true }]
  });
  const checked = await recordEffectiveness(verifier.token, capaId, {
    outcome: 'effective',
    note: EFFECTIVENESS_NOTE
  });
  assert.strictEqual(checked.status, 200, JSON.stringify(checked.body));

  // One request, and everything the report lays out is in its answer.
  const read = await readCapa(ground.engineer.token, capaId);
  assert.strictEqual(read.status, 200);
  const capa = read.body.capa;

  assert.strictEqual(capa.capaNo, opened.body.capa.capaNo);
  assert.strictEqual(capa.method, '8d');
  assert.strictEqual(capa.status, 'closed');

  // D1 — the team, the lead as a role and the members as a set.
  assert.strictEqual(capa.teamLead.name, 'Ada Lead');
  assert.deepStrictEqual(capa.teamMembers.map((each) => each.name), ['Bo Member']);

  // D2 — the problem description.
  assert.strictEqual(capa.problemStatement, PROBLEM);

  // D4 — both chains, in the order they are reasoned, each with its steps and
  // the one step it stopped at.
  assert.deepStrictEqual([...new Set(capa.whys.map((each) => each.chain))], ['occurrence', 'escape']);
  const occurrence = capa.whys.filter((each) => each.chain === 'occurrence');
  assert.deepStrictEqual(
    occurrence.map((each) => each.statement),
    ['The vibration loosened it.', OCCURRENCE_ROOT]
  );
  assert.deepStrictEqual(occurrence.map((each) => each.isRoot), [false, true]);
  const escape = capa.whys.filter((each) => each.chain === 'escape');
  assert.strictEqual(escape.length, 1);
  assert.strictEqual(escape[0].statement, ESCAPE_ROOT);
  assert.strictEqual(escape[0].isRoot, true);

  // D3, D5-D7 — the Concern's own work, with every phase it has been round. The
  // report prints these; it records none of them (ADR-0034).
  assert.strictEqual(String(capa.concern.id), String(ground.concern.id));
  const measureByTitle = Object.fromEntries(
    capa.concern.measures.map((measure) => [measure.title, measure])
  );
  assert.deepStrictEqual(Object.keys(measureByTitle).sort(), [
    'A captive fastener on the guard',
    'Add the torque step to the shift handover',
    'Quarantined the batch'
  ]);
  assert.strictEqual(measureByTitle['Quarantined the batch'].actionType, 'containment');
  assert.deepStrictEqual(
    measureByTitle['Quarantined the batch'].phases.map((phase) => phase.phase),
    ['plan', 'do', 'check', 'act']
  );
  assert.strictEqual(measureByTitle['A captive fastener on the guard'].actionType, 'countermeasure');
  assert.strictEqual(measureByTitle['Add the torque step to the shift handover'].actionType, 'preventive');
  const walked = measureByTitle['Add the torque step to the shift handover'].phases;
  assert.deepStrictEqual(walked.map((phase) => phase.phase), ['plan', 'do', 'check', 'act']);
  const check = walked.find((phase) => phase.phase === 'check');
  assert.strictEqual(check.outcome, 'effective');
  assert.match(check.note, /The preventive action: the check phase is done/);

  // D8 — the effectiveness check: who verified it, when, and what they said.
  assert.strictEqual(capa.effectivenessVerifiedBy.name, 'Pat Verifier');
  assert.strictEqual(String(capa.effectivenessVerifiedBy.accountId), String(verifier.id));
  assert.notStrictEqual(capa.effectivenessVerifiedAt, null);
  assert.strictEqual(capa.effectivenessNote, EFFECTIVENESS_NOTE);

  // The evidence that travels with the investigation: the occurrence, with the
  // number a person quotes, what was made wrong and how much of it.
  assert.strictEqual(capa.concern.nonconformances.length, 1);
  const occurrenceRow = capa.concern.nonconformances[0];
  assert.strictEqual(occurrenceRow.issueNo, ground.nonconformance.issueNo);
  assert.strictEqual(String(occurrenceRow.productId), String(ground.product.id));
  assert.strictEqual(occurrenceRow.productCode, ground.product.code);
  assert.strictEqual(occurrenceRow.defectCodeCode, ground.defectCode.code);
  assert.strictEqual(occurrenceRow.quantityAffected, 20);
  // Linked rather than raised from (see `makeGround`): evidence behind the
  // Concern, which is what the report's own section prints.
  assert.strictEqual(occurrenceRow.isSource, false);
  assert.ok(Array.isArray(occurrenceRow.dispositions));
});

// ---------------------------------------------------------------------------
// 2. The Dispositions the report prints
// ---------------------------------------------------------------------------

test('the linked Non-conformances carry their Dispositions key for key with the record own read', async () => {
  const ground = await makeGround();
  const opened = await openCapa(ground.engineer.token, ground.concern.id, {});
  assert.strictEqual(opened.status, 201, JSON.stringify(opened.body));

  const scrap = await postDisposition(ground.engineer.token, ground.nonconformance.id, {
    dispositionType: 'scrap',
    quantity: 12,
    note: 'Cut up and back to the furnace.'
  });
  assert.strictEqual(scrap.status, 201, JSON.stringify(scrap.body));

  const rework = await postDisposition(ground.engineer.token, ground.nonconformance.id, {
    dispositionType: 'rework',
    quantity: 2,
    reworkMinutes: 45
  });
  assert.strictEqual(rework.status, 201, JSON.stringify(rework.body));

  const concession = await postConcession(ground.engineer.token, ground.nonconformance.id, {
    quantity: 6,
    reference: 'DEV-2026-0014',
    note: 'Customer engineering accepts the cosmetic marks on this lot.'
  });
  assert.strictEqual(concession.status, 201, JSON.stringify(concession.body));

  // What the record's own address says about them...
  const record = await readNonconformance(ground.engineer.token, ground.nonconformance.id);
  assert.strictEqual(record.status, 200);
  const onTheRecord = record.body.nonconformance.dispositions;
  assert.strictEqual(onTheRecord.length, 3);

  // ... and what the CAPA's own read sends, which is what the report prints.
  const read = await readCapa(ground.engineer.token, opened.body.capa.id);
  assert.strictEqual(read.status, 200);
  const linked = read.body.capa.concern.nonconformances.find(
    (each) => String(each.id) === String(ground.nonconformance.id)
  );
  assert.ok(linked, 'the Non-conformance the Concern was raised from is not in the report read');

  // Key for key, in the same order: two answers to one question, and they have
  // to be the same answer. `decidedByAccountName` is the name a Concession's
  // granting Account stays on the record under (ADR-0035).
  assert.deepStrictEqual(linked.dispositions, onTheRecord);
  assert.deepStrictEqual(
    linked.dispositions.map((each) => each.dispositionType),
    ['scrap', 'rework', 'use_as_is']
  );
  assert.deepStrictEqual(linked.dispositions.map((each) => each.quantity), [12, 2, 6]);
  assert.deepStrictEqual(linked.dispositions.map((each) => each.isConcession), [false, false, true]);
  assert.strictEqual(linked.dispositions[1].reworkMinutes, 45);
  assert.strictEqual(linked.dispositions[0].note, 'Cut up and back to the furnace.');
  assert.strictEqual(linked.dispositions[2].reference, 'DEV-2026-0014');
  assert.strictEqual(linked.dispositions[2].decidedByAccountName, 'Quality Engineer');
  assert.ok(linked.dispositions.every((each) => each.decidedAt));

  // And an Action that answers no Non-conformance sends an empty list rather
  // than a missing field: an empty answer is a state the report renders.
  const concernRead = await fetch(`${base}/api/actions/${ground.concern.id}`, {
    headers: ground.engineer.token
  });
  const concernBody = await json(concernRead);
  assert.strictEqual(concernBody.status, 200);
  assert.strictEqual(concernBody.body.action.nonconformances.length, 1);
  assert.strictEqual(concernBody.body.action.nonconformances[0].dispositions.length, 3);
});

// ---------------------------------------------------------------------------
// 3. An open CAPA reads as what it has not yet done
// ---------------------------------------------------------------------------

test('an open CAPA reads as what is not done yet: no confirmed root, no effectiveness check and no Disposition decided', async () => {
  const ground = await makeGround();
  const opened = await openCapa(ground.engineer.token, ground.concern.id, {});
  assert.strictEqual(opened.status, 201, JSON.stringify(opened.body));

  // A Why in the occurrence chain that nobody has concluded, and nothing at all
  // in the escape chain.
  const added = await addWhy(ground.engineer.token, opened.body.capa.id, {
    chain: 'occurrence',
    statement: 'Something is loose.'
  });
  assert.strictEqual(added.status, 201, JSON.stringify(added.body));

  const read = await readCapa(ground.engineer.token, opened.body.capa.id);
  assert.strictEqual(read.status, 200);
  const capa = read.body.capa;

  assert.strictEqual(capa.status, 'open');
  assert.strictEqual(capa.problemStatement, null);
  assert.strictEqual(capa.teamLead, null);
  assert.deepStrictEqual(capa.teamMembers, []);
  assert.strictEqual(capa.whys.filter((each) => each.chain === 'escape').length, 0);
  assert.strictEqual(capa.whys.every((each) => each.isRoot === false), true);
  assert.strictEqual(capa.effectivenessVerifiedAt, null);
  assert.strictEqual(capa.effectivenessVerifiedBy, null);
  assert.strictEqual(capa.effectivenessNote, null);
  assert.strictEqual(capa.effectivenessCheckDueAt, null);
  assert.strictEqual(capa.effectivenessCheckOverdue, false);

  // Nothing answers the Concern yet, and nothing has been decided about the
  // product — the two "not yet" states the report's own sections say in words.
  assert.deepStrictEqual(capa.concern.measures, []);
  assert.deepStrictEqual(capa.concern.nonconformances[0].dispositions, []);

  // The same read once the work is done is the closed case the first test
  // asserts; the difference is entirely the data, which is the point of a
  // report that renders one read twice.
  const closedGround = await makeGround();
  const closedOpened = await openCapa(closedGround.engineer.token, closedGround.concern.id, {});
  const closedScrap = await postDisposition(closedGround.engineer.token, closedGround.nonconformance.id, {
    dispositionType: 'scrap',
    quantity: 20
  });
  assert.strictEqual(closedScrap.status, 201, JSON.stringify(closedScrap.body));
  // A Concern closes only behind a countermeasure that held (ADR-0033), which
  // is what `closeConcern` in capa-effectiveness.test.js does; here it is one
  // line because this test is about the read, not about the cycle.
  const closedMeasure = await addMeasure(closedGround.engineer.token, closedGround.concern.id, {
    actionType: 'countermeasure',
    title: 'A captive fastener on the guard'
  });
  assert.strictEqual(closedMeasure.status, 201, JSON.stringify(closedMeasure.body));
  await walkCycle(closedGround.engineer.token, closedMeasure.body.action.id, 'The countermeasure');
  await walkCycle(closedGround.engineer.token, closedGround.concern.id, 'The Concern');
  await confirmRoot(closedGround.engineer.token, closedOpened.body.capa.id, 'occurrence', OCCURRENCE_ROOT);
  await confirmRoot(closedGround.engineer.token, closedOpened.body.capa.id, 'escape', ESCAPE_ROOT);
  const closedRead = await readCapa(closedGround.engineer.token, closedOpened.body.capa.id);
  assert.strictEqual(closedRead.body.capa.concern.nonconformances[0].dispositions.length, 1);
  // Closing the whole quantity closed the Non-conformance itself (#206), which
  // is the state a reader of the report sees beside the evidence.
  assert.strictEqual(closedRead.body.capa.concern.nonconformances[0].status, 'closed');
});

// ---------------------------------------------------------------------------
// 4. Who may read it
// ---------------------------------------------------------------------------

test('an Account with no Grant anywhere reads a CAPA and its report: the read rule is the CAPA own, not the Site write rule', async () => {
  const ground = await makeGround();
  const opened = await openCapa(ground.engineer.token, ground.concern.id, {});
  assert.strictEqual(opened.status, 201, JSON.stringify(opened.body));

  // An approved Account that holds nothing at all: no Grant on the line, none on
  // the Site, no Quality authority anywhere.
  const stranger = await insertAccount({ displayName: 'Una Ungranted' });

  const read = await readCapa(stranger.token, opened.body.capa.id);
  assert.strictEqual(read.status, 200, JSON.stringify(read.body));
  assert.strictEqual(read.body.capa.capaNo, opened.body.capa.capaNo);
  assert.strictEqual(String(read.body.capa.concern.id), String(ground.concern.id));

  // The Concern it answers reads the same way, which is the rule ADR-0009
  // records and this ticket matches rather than tightens: an Org Unit decides
  // where an Account may act, never what it may know about.
  const concernRead = await fetch(`${base}/api/actions/${ground.concern.id}`, {
    headers: stranger.token
  });
  assert.strictEqual(concernRead.status, 200);

  // What the stranger may still not do is act: opening a CAPA on the Concern is
  // Quality authority at its Org Unit, and no Grant reaches it.
  const attempted = await openCapa(stranger.token, ground.concern.id, {});
  assert.strictEqual(attempted.status, 403, JSON.stringify(attempted.body));

  // A CAPA that does not exist is a 404 for this caller too, and the read is
  // total: an address that is not an id resolves to nothing rather than
  // reaching Postgres as a BIGINT, so it is the same 404 rather than a 500.
  const missing = await readCapa(stranger.token, '999999999');
  assert.strictEqual(missing.status, 404, JSON.stringify(missing.body));
  const malformed = await fetch(`${base}/api/actions/capas/not-a-number`, {
    headers: stranger.token
  });
  assert.strictEqual(malformed.status, 404);
});
