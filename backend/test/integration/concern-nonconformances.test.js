/*
 * Raising a Concern from a Non-conformance, linking further occurrences and
 * unlinking them — over HTTP, against a real database and a real (locally
 * issued) JWKS (issue #208). The seam, the fixture scaffolding and the
 * dependency-ordered cleanup are the ones
 * `nonconformance-dispositions.test.js` and `actions.test.js` already
 * establish.
 *
 * What is exercised here is the whole of the ticket's backend surface, and it
 * is one file rather than two because every one of these tests needs both
 * Modules at once: a Non-conformance to raise from, an Action log to raise
 * into, the link between them, and the two detail reads that show each record
 * the other. The three writes all live in the Actions Module — its
 * `actions.js` header argues why the Quality Module could not own them — and
 * the two reads are each Module's own, by ordinary SQL join.
 *
 * Every refusal the ticket names has a test proving it is refused, not only
 * the permitted path: linking the same occurrence twice (409), linking
 * something that is not a Concern (400), a caller who cannot see the Site
 * (403), a caller with no write Grant at the Concern's Org Unit (403), the
 * occurrence a Concern was raised from being unlinked (409), and a link that
 * is not there (404).
 *
 * **Section 5 is issue #221's, and one of its two tests reads Postgres
 * directly.** The gap that issue found was in the baseline's
 * `action_items_single_source` CHECK, and a constraint is what makes a rule
 * true for a writer that does not use the service — so the honest way to prove
 * the narrowed rule still refuses a genuinely double-sourced Action is to be
 * that writer for one statement, the same licence `capas.test.js` takes for
 * the two constraints beside it. The permitted path is tested over HTTP.
 *
 * Needs a database with every migration applied, including
 * 1800000000000_concern-nonconformances.js and 1800400000000_capa-is-not-a-source.js.
 * Set DATABASE_URL first — see the README's Tests section.
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
const insertedProductCodes = [];
const insertedDefectCodeCodes = [];
const insertedActionIds = [];
const insertedCapaIds = [];
const insertedCustomerCodes = [];

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

// An Account, optionally holding Grants — the shape
// `nonconformance-dispositions.test.js` uses. `write` defaults to true, since
// most of these Accounts record; `quality` is the independent flag ADR-0035
// keeps beside it, and section 5 is the one place it is needed: opening a CAPA
// on a Concern is an act of Quality authority rather than of a write Grant.
async function insertAccount({ role = 'operator', displayName = null, grants = [] } = {}) {
  const subject = uniqueCode('ccacct');
  const name = displayName ?? `Concern Account ${subject}`;
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
    [uniqueCode('CCS'), 'Concern Test Site', 'Asia/Ho_Chi_Minh']
  );
  insertedSiteIds.push(site.id);
  return site;
}

async function insertOrgUnit(siteId, { name = 'Concern Unit' } = {}) {
  const { rows: [orgUnit] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, NULL, $2, $3, 'area') RETURNING id, code, name, path`,
    [siteId, uniqueCode('CCOU'), name]
  );
  insertedOrgUnitIds.push(orgUnit.id);
  return orgUnit;
}

// An Action of a kind that is not a Concern, inserted directly: the point of
// the test that uses it is what the link route refuses, not how an Improvement
// is raised.
async function insertNonConcernAction(orgUnitId, actionType = 'containment') {
  const { rows: [action] } = await pool.query(
    `INSERT INTO action_items (action_no, title, org_unit_id, action_type, status)
     VALUES ($1, 'A measure standing on its own', $2, $3, 'open') RETURNING id, action_type`,
    [uniqueCode('AC-'), orgUnitId, actionType]
  );
  insertedActionIds.push(action.id);
  return action;
}

async function createProduct(adminToken) {
  const code = uniqueCode('CCP-');
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

async function createDefectCode(adminToken, { defaultSeverity = 'minor' } = {}) {
  const code = uniqueCode('CCD-');
  const response = await fetch(`${base}/api/quality/defect-codes`, {
    method: 'POST',
    headers: { ...adminToken, 'content-type': 'application/json' },
    body: JSON.stringify({ code, name: `Defect ${code}`, category: 'product', defaultSeverity })
  });
  const { status, body } = await json(response);
  assert.strictEqual(status, 201, `creating ${code} failed: ${JSON.stringify(body)}`);
  insertedDefectCodeCodes.push(code);
  return body.defectCode;
}

async function record(token, siteId, body) {
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

async function readAction(token, id) {
  const response = await fetch(`${base}/api/actions/${id}`, { headers: token });
  return json(response);
}

// `POST /api/actions/nonconformances/:id/concern` — raising one from a record.
async function raiseConcern(token, nonconformanceId, body) {
  const response = await fetch(`${base}/api/actions/nonconformances/${nonconformanceId}/concern`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  const payload = await json(response);
  if (payload.body && payload.body.action) insertedActionIds.push(payload.body.action.id);
  return payload;
}

// `POST /api/actions/:id/capa` — opening an investigation on a Concern, the
// act of Quality authority issue #209 built and issue #221 made reachable for
// the Concern this file is about.
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

// The investigation's own read, which is the 8D report issue #212 renders:
// evidence travels on it as `concern.nonconformances`.
async function readCapa(token, capaId) {
  const response = await fetch(`${base}/api/actions/capas/${capaId}`, { headers: token });
  return json(response);
}

// A customer complaint standing on its own, which is the second *source* a
// genuinely double-sourced Action names in section 5. Written directly rather
// than over HTTP on purpose: the Module's own routes for Customers and
// complaints belong to issue #214, and all this fixture needs is a foreign key
// the narrowed CHECK can count.
async function insertComplaint() {
  const code = uniqueCode('CNC-');
  const { rows: [customer] } = await pool.query(
    `INSERT INTO customers (code, name) VALUES ($1, $2) RETURNING id`,
    [code, `Customer ${code}`]
  );
  insertedCustomerCodes.push(code);
  const { rows: [complaint] } = await pool.query(
    `INSERT INTO customer_complaints (customer_id, description)
     VALUES ($1, 'Short-shipped on the last delivery.') RETURNING id`,
    [customer.id]
  );
  return complaint.id;
}

async function link(token, concernId, nonconformanceId) {
  const response = await fetch(`${base}/api/actions/${concernId}/nonconformances`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify({ nonconformanceId })
  });
  return json(response);
}

async function unlink(token, concernId, nonconformanceId) {
  const response = await fetch(
    `${base}/api/actions/${concernId}/nonconformances/${nonconformanceId}/unlink`,
    { method: 'POST', headers: { ...token, 'content-type': 'application/json' } }
  );
  return json(response);
}

async function completePhase(token, concernId, phase, note) {
  const response = await fetch(`${base}/api/actions/${concernId}/phases/${phase}/complete`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify({ note })
  });
  return json(response);
}

let admin;
let adminToken;

// The ground every test starts from: a Site, the Org Unit bad product is found
// at, and an Account that may record there. A Product and a Defect code are
// created per ground rather than shared, so a test that names one names its
// own.
async function makeGround() {
  const site = await insertSite();
  const unit = await insertOrgUnit(site.id, { name: 'Foundry Line' });
  const recorder = await insertAccount({
    displayName: 'Recorder One',
    grants: [{ orgUnitId: unit.id }]
  });
  const product = await createProduct(adminToken);
  const defectCode = await createDefectCode(adminToken);

  const recorded = await record(recorder.token, site.id, {
    orgUnitId: unit.id,
    productId: product.id,
    defectCodeId: defectCode.id,
    detectionPoint: 'in_process',
    quantity: 20
  });
  assert.strictEqual(recorded.status, 201, `recording failed: ${JSON.stringify(recorded.body)}`);

  return {
    site,
    unit,
    recorder,
    product,
    defectCode,
    id: recorded.body.nonconformance.id,
    nonconformance: recorded.body.nonconformance
  };
}

// A second occurrence of the same failure, at the same Org Unit — what "one
// problem answering several occurrences" is about.
async function recordAgain(ground, quantity = 8, orgUnitId = null) {
  const recorded = await record(ground.recorder.token, ground.site.id, {
    orgUnitId: orgUnitId ?? ground.unit.id,
    productId: ground.product.id,
    defectCodeId: ground.defectCode.id,
    detectionPoint: 'final_inspection',
    quantity
  });
  assert.strictEqual(recorded.status, 201, `recording failed: ${JSON.stringify(recorded.body)}`);
  return recorded.body.nonconformance;
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
  // Children before parents. The link rows are `ON DELETE CASCADE` from both
  // ends, so deleting the Actions and then the Non-conformances clears them.
  // The CAPAs go after the Actions, because `action_items.capa_id` is a plain
  // foreign key and Postgres checks it on DELETE.
  await pool.query('DELETE FROM action_items WHERE id = ANY($1)', [insertedActionIds]);
  if (insertedCapaIds.length > 0) {
    await pool.query('DELETE FROM capa_team_members WHERE capa_id = ANY($1)', [insertedCapaIds]);
    await pool.query('DELETE FROM capas WHERE id = ANY($1)', [insertedCapaIds]);
  }
  await pool.query(
    `DELETE FROM customer_complaints
      WHERE customer_id IN (SELECT id FROM customers WHERE code = ANY($1))`,
    [insertedCustomerCodes]
  );
  await pool.query('DELETE FROM customers WHERE code = ANY($1)', [insertedCustomerCodes]);
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
  await pool.query('DELETE FROM org_units WHERE id = ANY($1)', [insertedOrgUnitIds]);
  await pool.query('DELETE FROM sites WHERE id = ANY($1)', [insertedSiteIds]);
  await new Promise((resolve) => server.close(resolve));
  await closePool();
  await jwks.close();
});

// ---------------------------------------------------------------------------
// 1. Raising a Concern from a Non-conformance
// ---------------------------------------------------------------------------

test('raising a Concern from a Non-conformance lands it at the record\'s Org Unit, numbers it for the Site, and records where it came from', async () => {
  const ground = await makeGround();

  const { status, body } = await raiseConcern(ground.recorder.token, ground.id, {
    title: 'Sorting keeps finding these on Line 1',
    description: 'The same dimensional failure three shifts running.'
  });
  assert.strictEqual(status, 201, JSON.stringify(body));

  const concern = body.action;
  // A Concern, and nothing else: this address raises a Concern and has no
  // actionType to send.
  assert.strictEqual(concern.actionType, 'concern');
  assert.strictEqual(concern.status, 'open');
  assert.strictEqual(concern.title, 'Sorting keeps finding these on Line 1');
  // The record's own Org Unit, which the caller never named.
  assert.strictEqual(String(concern.orgUnitId), String(ground.unit.id));
  // The Site's own document number, the shape every Action gets: raised
  // through the register or through this address, an `AC-` number is the
  // same number.
  assert.match(concern.actionNo, /^AC-[A-Z0-9]+-\d{4}-\d{5}$/);
  // The Action log's usual rules, unchanged: it starts with a cycle-1 Plan of
  // its own.
  assert.strictEqual(concern.openPhase.phase, 'plan');
  assert.strictEqual(concern.openPhase.cycle, 1);

  // It records the Non-conformance it came from, twice over and deliberately:
  // the source column says where the Concern was raised from, and the link
  // list says which occurrence it answers.
  assert.strictEqual(String(concern.sourceNonconformanceId), String(ground.id));
  assert.strictEqual(concern.sourceType, 'quality_issue');
  assert.strictEqual(concern.nonconformances.length, 1);
  assert.strictEqual(String(concern.nonconformances[0].id), String(ground.id));
  assert.strictEqual(concern.nonconformances[0].issueNo, ground.nonconformance.issueNo);
  assert.strictEqual(concern.nonconformances[0].isSource, true);

  // And the record shows the Concern the other way round, through its own
  // address.
  const read = await readNonconformance(ground.recorder.token, ground.id);
  assert.strictEqual(read.status, 200);
  assert.strictEqual(read.body.nonconformance.concerns.length, 1);
  assert.strictEqual(String(read.body.nonconformance.concerns[0].id), String(concern.id));
  assert.strictEqual(read.body.nonconformance.concerns[0].status, 'open');
  assert.strictEqual(read.body.nonconformance.concerns[0].isSource, true);
});

test('a Concern raised from a Non-conformance follows the Concern rule: a title is required, and a caller who cannot see the Site is refused', async () => {
  const ground = await makeGround();

  // The Action log's own rule for a raise, unchanged by this address.
  const untitled = await raiseConcern(ground.recorder.token, ground.id, { description: 'no title' });
  assert.strictEqual(untitled.status, 400, JSON.stringify(untitled.body));
  assert.match(untitled.body.message, /title is required/);

  // A Concern is raiseable by anyone who can see the Site (issue #198), and
  // nobody else — an Account granted on another Site's Org Unit cannot see
  // this one.
  const otherSite = await insertSite();
  const otherUnit = await insertOrgUnit(otherSite.id, { name: 'Elsewhere' });
  const stranger = await insertAccount({ grants: [{ orgUnitId: otherUnit.id }] });

  const refused = await raiseConcern(stranger.token, ground.id, {
    title: 'Not mine to raise'
  });
  assert.strictEqual(refused.status, 403, JSON.stringify(refused.body));

  // The record itself is invisible to them too, which is the same rule read
  // the other way.
  const hidden = await readNonconformance(stranger.token, ground.id);
  assert.strictEqual(hidden.status, 403, JSON.stringify(hidden.body));

  // And an id that names nothing is a 404 rather than anything else — for an
  // administrator as well.
  const missing = await raiseConcern(adminToken, '99999999', { title: 'Nothing here' });
  assert.strictEqual(missing.status, 404, JSON.stringify(missing.body));
});

test('the Non-conformance\'s detail returns the Concerns it is linked to, with their status', async () => {
  const ground = await makeGround();

  // Nothing is being done about the cause yet, which is a real state and an
  // empty list rather than a missing field.
  const before = await readNonconformance(ground.recorder.token, ground.id);
  assert.deepStrictEqual(before.body.nonconformance.concerns, []);

  const raised = await raiseConcern(ground.recorder.token, ground.id, {
    title: 'The press keeps drifting'
  });
  assert.strictEqual(raised.status, 201, JSON.stringify(raised.body));
  const concernId = raised.body.action.id;

  // The status travels with the Concern rather than being a client's guess:
  // completing the Concern's Plan is what puts it in progress.
  const planned = await completePhase(ground.recorder.token, concernId, 'plan', 'Started it.');
  assert.strictEqual(planned.status, 200, JSON.stringify(planned.body));
  assert.strictEqual(planned.body.action.status, 'in_progress');

  const read = await readNonconformance(ground.recorder.token, ground.id);
  assert.strictEqual(read.status, 200);
  const [concern] = read.body.nonconformance.concerns;
  assert.strictEqual(String(concern.id), String(concernId));
  assert.strictEqual(concern.status, 'in_progress');
  assert.strictEqual(concern.actionNo, raised.body.action.actionNo);
  assert.strictEqual(concern.title, 'The press keeps drifting');
  assert.strictEqual(concern.actionType, 'concern');
  assert.strictEqual(String(concern.orgUnitId), String(ground.unit.id));
  assert.strictEqual(concern.isSource, true);
});

// ---------------------------------------------------------------------------
// 2. Linking further Non-conformances to one Concern
// ---------------------------------------------------------------------------

test('a further Non-conformance can be linked to the Concern, and the Concern\'s detail returns every occurrence with number, Product, Defect code and quantity', async () => {
  const ground = await makeGround();
  const second = await recordAgain(ground, 8);

  const raised = await raiseConcern(ground.recorder.token, ground.id, {
    title: 'One problem, two occurrences'
  });
  assert.strictEqual(raised.status, 201, JSON.stringify(raised.body));
  const concernId = raised.body.action.id;
  const concernNo = raised.body.action.actionNo;

  const linked = await link(ground.recorder.token, concernId, second.id);
  assert.strictEqual(linked.status, 201, JSON.stringify(linked.body));
  assert.strictEqual(linked.body.action.nonconformances.length, 2);

  // The occurrence it was raised from reads first, in the answer and in a
  // fresh read of the same address.
  const read = await readAction(ground.recorder.token, concernId);
  assert.strictEqual(read.status, 200);
  const occurrences = read.body.action.nonconformances;
  assert.strictEqual(occurrences.length, 2);
  assert.strictEqual(String(occurrences[0].id), String(ground.id));
  assert.strictEqual(occurrences[0].isSource, true);
  assert.strictEqual(String(occurrences[1].id), String(second.id));
  assert.strictEqual(occurrences[1].isSource, false);

  // The number, the Product, the Defect code and the quantity — what the
  // ticket asks a reader of a Concern to be able to see.
  const secondRow = occurrences[1];
  assert.strictEqual(secondRow.issueNo, second.issueNo);
  assert.strictEqual(String(secondRow.productId), String(ground.product.id));
  assert.strictEqual(secondRow.productCode, ground.product.code);
  assert.strictEqual(secondRow.productName, ground.product.name);
  assert.strictEqual(String(secondRow.defectCodeId), String(ground.defectCode.id));
  assert.strictEqual(secondRow.defectCodeCode, ground.defectCode.code);
  assert.strictEqual(secondRow.defectCodeName, ground.defectCode.name);
  assert.strictEqual(secondRow.quantityAffected, 8);
  assert.strictEqual(secondRow.uomCode, 'EA');
  assert.strictEqual(secondRow.status, 'open');

  // The link is visible from the Non-conformance's own address too, and it
  // names the Concern rather than a copy of it.
  const occurrence = await readNonconformance(ground.recorder.token, second.id);
  assert.strictEqual(occurrence.status, 200);
  assert.strictEqual(occurrence.body.nonconformance.concerns.length, 1);
  assert.strictEqual(String(occurrence.body.nonconformance.concerns[0].id), String(concernId));
  assert.strictEqual(occurrence.body.nonconformance.concerns[0].actionNo, concernNo);
  assert.strictEqual(occurrence.body.nonconformance.concerns[0].isSource, false);
});

test('linking the same Non-conformance to the same Concern twice is refused with a 409', async () => {
  const ground = await makeGround();
  const second = await recordAgain(ground);

  const raised = await raiseConcern(ground.recorder.token, ground.id, {
    title: 'Linked once'
  });
  const concernId = raised.body.action.id;

  const first = await link(ground.recorder.token, concernId, second.id);
  assert.strictEqual(first.status, 201, JSON.stringify(first.body));

  const again = await link(ground.recorder.token, concernId, second.id);
  assert.strictEqual(again.status, 409, JSON.stringify(again.body));
  assert.match(again.body.message, /already linked/);

  // Still one link rather than two, read back through the Concern.
  const read = await readAction(ground.recorder.token, concernId);
  assert.strictEqual(read.body.action.nonconformances.length, 2);
});

test('only a Concern can be linked; another kind of Action is refused', async () => {
  const ground = await makeGround();
  const second = await recordAgain(ground);
  const containment = await insertNonConcernAction(ground.unit.id);

  const refused = await link(ground.recorder.token, containment.id, second.id);
  assert.strictEqual(refused.status, 400, JSON.stringify(refused.body));
  assert.match(refused.body.message, /only a Concern answers Non-conformances/);

  // And nothing was written: the Non-conformance names no Concern.
  const read = await readNonconformance(ground.recorder.token, second.id);
  assert.deepStrictEqual(read.body.nonconformance.concerns, []);

  // An id that names no Action at all is a 404, before any of that.
  const missing = await link(ground.recorder.token, '99999999', second.id);
  assert.strictEqual(missing.status, 404, JSON.stringify(missing.body));
});

test('linking needs a write Grant at the Concern\'s Org Unit and sight of the Non-conformance\'s Site', async () => {
  const ground = await makeGround();
  const second = await recordAgain(ground);

  const raised = await raiseConcern(ground.recorder.token, ground.id, {
    title: 'Only the line may change this'
  });
  const concernId = raised.body.action.id;

  // A reader with a read Grant at the Org Unit but no write Grant: the Action
  // log's own rule for everything that changes an Action after it is raised.
  const reader = await insertAccount({
    displayName: 'Reader Only',
    grants: [{ orgUnitId: ground.unit.id, write: false }]
  });
  const refusedForScope = await link(reader.token, concernId, second.id);
  assert.strictEqual(refusedForScope.status, 403, JSON.stringify(refusedForScope.body));

  // A writer at the Concern's Org Unit who cannot see the Non-conformance's
  // Site: the occurrence must be one the caller may look at.
  const otherSite = await insertSite();
  const otherUnit = await insertOrgUnit(otherSite.id, { name: 'Elsewhere' });
  const elsewhere = await insertAccount({ grants: [{ orgUnitId: otherUnit.id }] });
  const refusedForSite = await link(elsewhere.token, concernId, second.id);
  assert.strictEqual(refusedForSite.status, 403, JSON.stringify(refusedForSite.body));

  // A malformed id is the caller's mistake and says so.
  const malformed = await link(ground.recorder.token, concernId, 'not-an-id');
  assert.strictEqual(malformed.status, 400, JSON.stringify(malformed.body));
});

// ---------------------------------------------------------------------------
// 3. Unlinking
// ---------------------------------------------------------------------------

test('a Non-conformance can be unlinked from a Concern, and the record stops naming it', async () => {
  const ground = await makeGround();
  const second = await recordAgain(ground);

  const raised = await raiseConcern(ground.recorder.token, ground.id, {
    title: 'Two unrelated problems, at first glance'
  });
  const concernId = raised.body.action.id;
  await link(ground.recorder.token, concernId, second.id);

  const unlinked = await unlink(ground.recorder.token, concernId, second.id);
  assert.strictEqual(unlinked.status, 200, JSON.stringify(unlinked.body));
  assert.strictEqual(unlinked.body.action.nonconformances.length, 1);
  assert.strictEqual(String(unlinked.body.action.nonconformances[0].id), String(ground.id));

  // Both records agree about it afterwards.
  const occurrence = await readNonconformance(ground.recorder.token, second.id);
  assert.deepStrictEqual(occurrence.body.nonconformance.concerns, []);

  // The Non-conformance itself is untouched: unlinking a link is not deleting
  // a record.
  assert.strictEqual(occurrence.body.nonconformance.issueNo, second.issueNo);
  assert.strictEqual(occurrence.body.nonconformance.quantityAffected, 8);
});

test('the Non-conformance a Concern was raised from cannot be unlinked', async () => {
  const ground = await makeGround();

  const raised = await raiseConcern(ground.recorder.token, ground.id, {
    title: 'Raised from this one'
  });
  const concernId = raised.body.action.id;

  const refused = await unlink(ground.recorder.token, concernId, ground.id);
  assert.strictEqual(refused.status, 409, JSON.stringify(refused.body));
  assert.match(refused.body.message, /cannot be unlinked/);

  // Still linked, read back.
  const read = await readAction(ground.recorder.token, concernId);
  assert.strictEqual(read.body.action.nonconformances.length, 1);
});

test('unlinking a Non-conformance that is not linked to the Concern is a 404', async () => {
  const ground = await makeGround();
  const second = await recordAgain(ground);

  const raised = await raiseConcern(ground.recorder.token, ground.id, {
    title: 'Never linked'
  });
  const concernId = raised.body.action.id;

  const refused = await unlink(ground.recorder.token, concernId, second.id);
  assert.strictEqual(refused.status, 404, JSON.stringify(refused.body));
  assert.match(refused.body.message, /not linked/);
});

// ---------------------------------------------------------------------------
// 4. A withdrawn Non-conformance
// ---------------------------------------------------------------------------

test('a cancelled Non-conformance can neither have a Concern raised from it nor be linked to one', async () => {
  const ground = await makeGround();
  const second = await recordAgain(ground);

  // Cancelling needs Quality authority at the record's Org Unit (issue #206).
  const holder = await insertAccount({
    displayName: 'Quality Holder',
    grants: [{ orgUnitId: ground.unit.id, write: false, quality: true }]
  });
  const cancelled = await fetch(`${base}/api/quality/nonconformances/${second.id}/cancel`, {
    method: 'POST',
    headers: { ...holder.token, 'content-type': 'application/json' },
    body: JSON.stringify({ note: 'Recorded against the wrong Product.' })
  });
  assert.strictEqual(cancelled.status, 200);

  const raised = await raiseConcern(ground.recorder.token, second.id, {
    title: 'Nothing to solve'
  });
  assert.strictEqual(raised.status, 409, JSON.stringify(raised.body));
  assert.match(raised.body.message, /was cancelled/);

  const concern = await raiseConcern(ground.recorder.token, ground.id, {
    title: 'A real one'
  });
  assert.strictEqual(concern.status, 201, JSON.stringify(concern.body));

  const linked = await link(ground.recorder.token, concern.body.action.id, second.id);
  assert.strictEqual(linked.status, 409, JSON.stringify(linked.body));
  assert.match(linked.body.message, /was cancelled/);
});

// ---------------------------------------------------------------------------
// 5. The investigation a Concern can carry (issue #221)
// ---------------------------------------------------------------------------

test("a Concern raised from a Non-conformance can have a CAPA opened on it, and the investigation's own read returns that Non-conformance as evidence", async () => {
  const ground = await makeGround();

  // #208's road, and the one the Quality Module exists for: the Concern carries
  // its provenance in `action_items.quality_issue_id`.
  const raised = await raiseConcern(ground.recorder.token, ground.id, {
    title: 'The guard keeps working loose'
  });
  assert.strictEqual(raised.status, 201, JSON.stringify(raised.body));
  assert.strictEqual(String(raised.body.action.sourceNonconformanceId), String(ground.id));

  // The act of Quality authority, by an Account that holds none of this Org
  // Unit's write Grant — the two flags are independent (ADR-0035).
  const holder = await insertAccount({
    displayName: 'Quality Engineer',
    grants: [{ orgUnitId: ground.unit.id, write: false, quality: true }]
  });

  // Before issue #221 this was a 500: the insert set `capa_id` beside the
  // `quality_issue_id` the row already carried, the baseline's single-source
  // CHECK counted both as *sources*, and Postgres answered 23514 with no
  // mapping for it in the service.
  const opened = await openCapa(holder.token, raised.body.action.id, {});
  assert.strictEqual(opened.status, 201, JSON.stringify(opened.body));

  // A source and a result on one row, from the Action's own read: where the
  // Concern came from, and what it became.
  const concern = await readAction(ground.recorder.token, raised.body.action.id);
  assert.strictEqual(concern.status, 200, JSON.stringify(concern.body));
  assert.strictEqual(String(concern.body.action.sourceNonconformanceId), String(ground.id));
  assert.strictEqual(concern.body.action.sourceType, 'quality_issue');
  assert.strictEqual(concern.body.action.capa.id, opened.body.capa.id);

  // And the report's evidence section (#212's read) carries the occurrence the
  // Concern was raised from, named as the source rather than as a later one.
  const read = await readCapa(holder.token, opened.body.capa.id);
  assert.strictEqual(read.status, 200, JSON.stringify(read.body));
  const evidence = read.body.capa.concern.nonconformances;
  assert.strictEqual(evidence.length, 1);
  assert.strictEqual(String(evidence[0].id), String(ground.id));
  assert.strictEqual(evidence[0].issueNo, ground.nonconformance.issueNo);
  assert.strictEqual(evidence[0].isSource, true);
  assert.strictEqual(String(evidence[0].productId), String(ground.product.id));
  assert.strictEqual(evidence[0].defectCodeCode, ground.defectCode.code);
  assert.strictEqual(evidence[0].quantityAffected, 20);
});

test('the single-source rule still refuses an Action raised from two records at once, and now permits a source beside the investigation it became', async () => {
  // Read directly (see this file's header): the claim is about a CHECK, and a
  // constraint is what makes a rule true for a writer that does not go through
  // the service. The permitted half of the same rule is exercised over HTTP.
  const ground = await makeGround();
  const complaintId = await insertComplaint();

  const raised = await raiseConcern(ground.recorder.token, ground.id, {
    title: 'The same failure, and a customer on the phone about it'
  });
  assert.strictEqual(raised.status, 201, JSON.stringify(raised.body));

  // Two genuine sources is exactly what the rule still forbids. The Concern
  // already carries `quality_issue_id`; naming a customer complaint as well is
  // refused under the constraint's own name, which is deliberately unchanged —
  // a later reader greps for it.
  await assert.rejects(
    () =>
      pool.query('UPDATE action_items SET customer_complaint_id = $2 WHERE id = $1', [
        raised.body.action.id,
        complaintId
      ]),
    (error) => error.code === '23514' && error.constraint === 'action_items_single_source',
    'an Action was raised from two records at once'
  );

  // The refused statement wrote nothing, and the provenance the Concern
  // legitimately carries is untouched.
  const refused = await readAction(ground.recorder.token, raised.body.action.id);
  assert.strictEqual(refused.body.action.sourceNonconformanceId, String(ground.id));
  assert.strictEqual(refused.body.action.sourceType, 'quality_issue');

  // `capa_id` is no longer counted among the sources, so the same row takes an
  // investigation: what it became is not a second thing it came from.
  const holder = await insertAccount({
    displayName: 'Quality Engineer',
    grants: [{ orgUnitId: ground.unit.id, write: false, quality: true }]
  });
  const opened = await openCapa(holder.token, raised.body.action.id, {});
  assert.strictEqual(opened.status, 201, JSON.stringify(opened.body));

  const concern = await readAction(ground.recorder.token, raised.body.action.id);
  assert.strictEqual(String(concern.body.action.sourceNonconformanceId), String(ground.id));
  assert.strictEqual(concern.body.action.capa.id, opened.body.capa.id);
});

