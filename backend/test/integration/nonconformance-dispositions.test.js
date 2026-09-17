/*
 * Dispositions, Concessions, closing and the corrections to a Non-conformance
 * over HTTP (issue #206), against a real database and a real (locally issued)
 * JWKS — the same seam nonconformances.test.js uses, and the same fixture
 * scaffolding, with the one addition this slice needs: an Account may hold a
 * Grant carrying Quality authority (`app_user_org_units.quality_authority`,
 * issue #204, ADR-0035) independently of its level.
 *
 * What is exercised here, and why each one needs the wire rather than a unit
 * test: a Disposition's own access is the write Grant recording needs, a
 * Concession's is Quality authority at the Org Unit, an over-disposition is a
 * 409, a record closes itself when its whole quantity has a Disposition (with
 * a Concern linked to it and still open, proving nothing about the cause is
 * consulted), and each of the three corrections is answered for a holder of
 * the authority and refused with a 403 for everyone else — with every one of
 * them readable back with who made it, when, and the note.
 *
 * This file builds its own Sites, Org Units, Products and Defect codes the way
 * its sibling does (Products and Defect codes through the API as an
 * administrator, so every row a test names is one the Platform itself would
 * accept), and deletes everything it inserted in `test.after()`, in dependency
 * order: the Concern it inserts directly, then the Non-conformances (whose
 * Dispositions and corrections are `ON DELETE CASCADE`), then the catalogues,
 * the Grants, the Accounts, the Org Units and the Sites.
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
const insertedProductCodes = [];
const insertedDefectCodeCodes = [];
const insertedActionIds = [];

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

// An Account, optionally holding Grants. A Grant is `{ orgUnitId, write,
// quality }` — `write` defaults to true, since most of these Accounts are
// recording, and `quality` defaults to false exactly as the database column
// does. The two are independent on purpose (ADR-0035), which is why the
// quality holder below is given `write: false`.
async function insertAccount({ role = 'operator', displayName = null, grants = [] } = {}) {
  const subject = uniqueCode('dcacct');
  const name = displayName ?? `Disposition Account ${subject}`;
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
    [uniqueCode('DCS'), 'Disposition Test Site', 'Asia/Ho_Chi_Minh']
  );
  insertedSiteIds.push(site.id);
  return site;
}

async function insertOrgUnit(siteId, { name = 'Disposition Unit' } = {}) {
  const { rows: [orgUnit] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, NULL, $2, $3, 'area') RETURNING id, code, name, path`,
    [siteId, uniqueCode('DCOU'), name]
  );
  insertedOrgUnitIds.push(orgUnit.id);
  return orgUnit;
}

async function createProduct(adminToken) {
  const code = uniqueCode('DCP-');
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
  const code = uniqueCode('DCD-');
  const response = await fetch(`${base}/api/quality/defect-codes`, {
    method: 'POST',
    headers: { ...adminToken, 'content-type': 'application/json' },
    body: JSON.stringify({
      code,
      name: `Defect ${code}`,
      category: 'product',
      defaultSeverity
    })
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

async function listNonconformances(token, siteId, query = '') {
  const response = await fetch(
    `${base}/api/quality/sites/${siteId}/nonconformances${query}`,
    { headers: token }
  );
  return json(response);
}

async function postTo(token, id, address, body) {
  const response = await fetch(`${base}/api/quality/nonconformances/${id}/${address}`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  return json(response);
}

const postDisposition = (token, id, body) => postTo(token, id, 'dispositions', body);
const postConcession = (token, id, body) => postTo(token, id, 'concession', body);
const postLowerSeverity = (token, id, body) => postTo(token, id, 'lower-severity', body);
const postReopen = (token, id, body) => postTo(token, id, 'reopen', body);
const postCancel = (token, id, body) => postTo(token, id, 'cancel', body);

// The floor a test starts from: a Site, an Org Unit, an Account that may record
// there, an Account that holds Quality authority there without any write Grant
// (ADR-0035 keeps the two flags independent), a Product and a Defect code.
let admin;
let adminToken;

async function makeGround({ severity = 'minor' } = {}) {
  const site = await insertSite();
  const unit = await insertOrgUnit(site.id, { name: 'Foundry Line' });
  const recorder = await insertAccount({
    displayName: 'Recorder One',
    grants: [{ orgUnitId: unit.id }]
  });
  const inspector = await insertAccount({
    displayName: 'Inspector Quai',
    grants: [{ orgUnitId: unit.id, write: false, quality: true }]
  });
  const product = await createProduct(adminToken);
  const defectCode = await createDefectCode(adminToken, { defaultSeverity: severity });

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
    inspector,
    product,
    defectCode,
    id: recorded.body.nonconformance.id,
    nonconformance: recorded.body.nonconformance
  };
}

// A Concern about the cause, linked to the Non-conformance. Issue #208 owns
// raising one from the record over HTTP; this file inserts the row directly
// because it is the *link* the closure rule must ignore, and no endpoint
// produces one yet. `action_items` is the action log's single table and its
// `source_type` is generated from which of the source columns is set.
async function insertOpenConcern(orgUnitId, qualityIssueId, title = 'Sorting keeps finding these') {
  const { rows: [action] } = await pool.query(
    `INSERT INTO action_items (title, org_unit_id, action_type, quality_issue_id, status)
     VALUES ($1, $2, 'concern', $3, 'open') RETURNING id, status`,
    [title, orgUnitId, qualityIssueId]
  );
  insertedActionIds.push(action.id);
  return action;
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
  // Children before parents. The Concern references the Org Unit and the
  // Non-conformance; a Non-conformance references the Org Unit, the Product,
  // the Defect code and the Account, and its Dispositions and corrections are
  // `ON DELETE CASCADE`, so one DELETE clears all three.
  await pool.query('DELETE FROM action_items WHERE id = ANY($1)', [insertedActionIds]);
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
// 1. The three Dispositions a recorder writes down
// ---------------------------------------------------------------------------

test('a scrap Disposition needs the same access as recording, and records who decided it and when', async () => {
  const ground = await makeGround();

  const { status, body } = await postDisposition(ground.recorder.token, ground.id, {
    dispositionType: 'scrap',
    quantity: 5,
    note: 'Crushed and weighed in at the scrap bin.'
  });
  assert.strictEqual(status, 201, JSON.stringify(body));

  const record = body.nonconformance;
  assert.strictEqual(record.dispositions.length, 1);
  const [disposition] = record.dispositions;
  assert.strictEqual(disposition.dispositionType, 'scrap');
  assert.strictEqual(disposition.isConcession, false);
  assert.strictEqual(disposition.quantity, 5);
  // The unit is the record's own, read off the Product — never an input.
  assert.strictEqual(disposition.uomCode, 'EA');
  assert.strictEqual(disposition.reworkMinutes, 0);
  assert.strictEqual(disposition.note, 'Crushed and weighed in at the scrap bin.');
  assert.ok(disposition.decidedAt, 'a Disposition records when it was decided');
  assert.strictEqual(disposition.decidedByAccountId, String(ground.recorder.id));
  assert.strictEqual(disposition.decidedByAccountName, 'Recorder One');

  // Part of the quantity has been dealt with, so the record is partly
  // dispositioned rather than closed.
  assert.strictEqual(record.quantityDispositioned, 5);
  assert.strictEqual(record.status, 'dispositioned');
  assert.strictEqual(record.closedAt, null);

  // Readable back through the record's own address, which is the door a client
  // reads it through.
  const read = await readNonconformance(ground.recorder.token, ground.id);
  assert.strictEqual(read.status, 200);
  assert.strictEqual(read.body.nonconformance.dispositions.length, 1);
  assert.strictEqual(read.body.nonconformance.dispositions[0].dispositionType, 'scrap');
  assert.strictEqual(read.body.nonconformance.dispositions[0].decidedByAccountName, 'Recorder One');
});

test('rework carries rework minutes, and minutes on anything that is not a rework are refused', async () => {
  const ground = await makeGround();

  const rework = await postDisposition(ground.recorder.token, ground.id, {
    dispositionType: 'rework',
    quantity: 4,
    reworkMinutes: 45
  });
  assert.strictEqual(rework.status, 201, JSON.stringify(rework.body));
  assert.strictEqual(rework.body.nonconformance.dispositions[0].reworkMinutes, 45);
  assert.strictEqual(rework.body.nonconformance.dispositions[0].dispositionType, 'rework');

  // A rework with no minutes is a number nobody decided, so it is refused.
  const missing = await postDisposition(ground.recorder.token, ground.id, {
    dispositionType: 'rework',
    quantity: 2
  });
  assert.strictEqual(missing.status, 400);
  assert.match(missing.body.message, /reworkMinutes/);

  // And minutes on a scrap are not a field of that Disposition at all.
  const wrongKind = await postDisposition(ground.recorder.token, ground.id, {
    dispositionType: 'scrap',
    quantity: 2,
    reworkMinutes: 10
  });
  assert.strictEqual(wrongKind.status, 400);
  assert.match(wrongKind.body.message, /rework/);

  // A kind outside the three this slice names is a mistake a caller can fix.
  const unknown = await postDisposition(ground.recorder.token, ground.id, {
    dispositionType: 'regrade',
    quantity: 2
  });
  assert.strictEqual(unknown.status, 400);
  assert.match(unknown.body.message, /dispositionType/);

  // Nothing the three refusals carried reached the record.
  const read = await readNonconformance(ground.recorder.token, ground.id);
  assert.strictEqual(read.body.nonconformance.dispositions.length, 1);
  assert.strictEqual(read.body.nonconformance.quantityDispositioned, 4);
});

test('a return-to-supplier Disposition is recorded the same way, with its own note', async () => {
  const ground = await makeGround();

  const { status, body } = await postDisposition(ground.recorder.token, ground.id, {
    dispositionType: 'return_to_supplier',
    quantity: 7,
    note: 'Pallet wrapped and labelled for the next collection.'
  });
  assert.strictEqual(status, 201, JSON.stringify(body));

  const [disposition] = body.nonconformance.dispositions;
  assert.strictEqual(disposition.dispositionType, 'return_to_supplier');
  assert.strictEqual(disposition.quantity, 7);
  assert.strictEqual(disposition.note, 'Pallet wrapped and labelled for the next collection.');
  assert.strictEqual(disposition.decidedByAccountName, 'Recorder One');
  assert.ok(disposition.decidedAt);
  assert.strictEqual(body.nonconformance.quantityDispositioned, 7);
});

test('a Disposition is refused with 403 for an Account whose Grant does not reach the Org Unit', async () => {
  const ground = await makeGround();
  // A Grant that reaches the Org Unit but only to read: recording and
  // dispositioning both need the write half of it.
  const reader = await insertAccount({
    displayName: 'Reader Two',
    grants: [{ orgUnitId: ground.unit.id, write: false }]
  });
  const elsewhere = await insertOrgUnit(ground.site.id, { name: 'Other Area' });
  const stranger = await insertAccount({
    displayName: 'Stranger Three',
    grants: [{ orgUnitId: elsewhere.id }]
  });

  for (const caller of [reader, stranger]) {
    const refused = await postDisposition(caller.token, ground.id, {
      dispositionType: 'scrap',
      quantity: 1
    });
    assert.strictEqual(refused.status, 403, `expected 403 for ${caller.displayName}`);
    assert.ok(refused.body.message);
  }

  // Nothing was written by either refusal.
  const read = await readNonconformance(ground.recorder.token, ground.id);
  assert.strictEqual(read.body.nonconformance.dispositions.length, 0);
  assert.strictEqual(read.body.nonconformance.quantityDispositioned, 0);
  assert.strictEqual(read.body.nonconformance.status, 'open');
});

test('a Disposition larger than what is still undecided is refused with 409, and nothing is written', async () => {
  const ground = await makeGround();

  const first = await postDisposition(ground.recorder.token, ground.id, {
    dispositionType: 'scrap',
    quantity: 12
  });
  assert.strictEqual(first.status, 201, JSON.stringify(first.body));

  // Eight of the twenty are left, and nine is one more than that.
  const tooMany = await postDisposition(ground.recorder.token, ground.id, {
    dispositionType: 'rework',
    quantity: 9,
    reworkMinutes: 15
  });
  assert.strictEqual(tooMany.status, 409);
  assert.match(tooMany.body.message, /still undecided/);

  const read = await readNonconformance(ground.recorder.token, ground.id);
  assert.strictEqual(read.body.nonconformance.dispositions.length, 1);
  assert.strictEqual(read.body.nonconformance.quantityDispositioned, 12);

  // Exactly what is left is allowed, and it closes the record.
  const exactly = await postDisposition(ground.recorder.token, ground.id, {
    dispositionType: 'rework',
    quantity: 8,
    reworkMinutes: 30
  });
  assert.strictEqual(exactly.status, 201, JSON.stringify(exactly.body));
  assert.strictEqual(exactly.body.nonconformance.quantityDispositioned, 20);
  assert.strictEqual(exactly.body.nonconformance.status, 'closed');
});

// ---------------------------------------------------------------------------
// 2. The Concession — using the product as it is, on Quality authority
// ---------------------------------------------------------------------------

test('a Concession needs Quality authority at the Org Unit, and records the granting Account, a reference and a note', async () => {
  const ground = await makeGround();

  const { status, body } = await postConcession(ground.inspector.token, ground.id, {
    quantity: 6,
    reference: 'DEV-2026-0014',
    note: 'Customer engineering accepts the cosmetic marks on this lot.'
  });
  assert.strictEqual(status, 201, JSON.stringify(body));

  const record = body.nonconformance;
  const [concession] = record.dispositions;
  assert.strictEqual(concession.dispositionType, 'use_as_is');
  assert.strictEqual(concession.isConcession, true);
  assert.strictEqual(concession.quantity, 6);
  assert.strictEqual(concession.reference, 'DEV-2026-0014');
  assert.strictEqual(concession.note, 'Customer engineering accepts the cosmetic marks on this lot.');
  // The granting Account stays on the record — the inspector holds Quality
  // authority with no write Grant at all, which ADR-0035 keeps independent.
  assert.strictEqual(concession.decidedByAccountId, String(ground.inspector.id));
  assert.strictEqual(concession.decidedByAccountName, 'Inspector Quai');
  assert.ok(concession.decidedAt);
  assert.strictEqual(record.quantityDispositioned, 6);

  // Re-read, so the Account that granted it is proven to be on the record
  // rather than only in the answer to the write.
  const read = await readNonconformance(ground.recorder.token, ground.id);
  assert.strictEqual(read.body.nonconformance.dispositions[0].decidedByAccountName, 'Inspector Quai');
  assert.strictEqual(read.body.nonconformance.dispositions[0].reference, 'DEV-2026-0014');
});

test('a Concession is refused with 403 for an Account holding a write Grant without Quality authority', async () => {
  const ground = await makeGround();

  const refused = await postConcession(ground.recorder.token, ground.id, {
    quantity: 6,
    reference: 'DEV-2026-0015',
    note: 'The recorder may not accept product.'
  });
  assert.strictEqual(refused.status, 403);
  // The refusal says which authority is missing rather than that the caller is
  // outside their Org Units — they are not.
  assert.match(refused.body.message, /Quality authority/);

  const read = await readNonconformance(ground.recorder.token, ground.id);
  assert.strictEqual(read.body.nonconformance.dispositions.length, 0);
  assert.strictEqual(read.body.nonconformance.status, 'open');
});

test('a Concession without its reference or its note is refused with 400', async () => {
  const ground = await makeGround();

  const noReference = await postConcession(ground.inspector.token, ground.id, {
    quantity: 2,
    note: 'Accepted.'
  });
  assert.strictEqual(noReference.status, 400);
  assert.match(noReference.body.message, /reference/);

  const noNote = await postConcession(ground.inspector.token, ground.id, {
    quantity: 2,
    reference: 'DEV-2026-0016'
  });
  assert.strictEqual(noNote.status, 400);
  assert.match(noNote.body.message, /note/);

  const read = await readNonconformance(ground.recorder.token, ground.id);
  assert.strictEqual(read.body.nonconformance.dispositions.length, 0);
});

test('an over-large Concession is refused with 409 exactly as a scrap is', async () => {
  const ground = await makeGround();

  const first = await postConcession(ground.inspector.token, ground.id, {
    quantity: 15,
    reference: 'DEV-2026-0017',
    note: 'Most of the lot is acceptable.'
  });
  assert.strictEqual(first.status, 201, JSON.stringify(first.body));

  const tooMany = await postConcession(ground.inspector.token, ground.id, {
    quantity: 6,
    reference: 'DEV-2026-0018',
    note: 'And the rest as well.'
  });
  assert.strictEqual(tooMany.status, 409);
  assert.match(tooMany.body.message, /still undecided/);

  const read = await readNonconformance(ground.recorder.token, ground.id);
  assert.strictEqual(read.body.nonconformance.dispositions.length, 1);
  assert.strictEqual(read.body.nonconformance.quantityDispositioned, 15);
});

// ---------------------------------------------------------------------------
// 3. Closing
// ---------------------------------------------------------------------------

test('a Non-conformance closes itself once its whole quantity has a Disposition, regardless of any Concern about its cause', async () => {
  const ground = await makeGround();
  // A Concern about the cause, linked to this Non-conformance and still open —
  // the state the closure rule must not wait on. Its cause is still being
  // answered while the product itself is dealt with (CONTEXT.md's own
  // Non-conformance entry).
  const concern = await insertOpenConcern(ground.unit.id, ground.id);
  assert.strictEqual(concern.status, 'open');

  const part = await postDisposition(ground.recorder.token, ground.id, {
    dispositionType: 'scrap',
    quantity: 4
  });
  assert.strictEqual(part.status, 201, JSON.stringify(part.body));
  assert.strictEqual(part.body.nonconformance.status, 'dispositioned');
  assert.strictEqual(part.body.nonconformance.closedAt, null);

  const rest = await postDisposition(ground.recorder.token, ground.id, {
    dispositionType: 'rework',
    quantity: 16,
    reworkMinutes: 120
  });
  assert.strictEqual(rest.status, 201, JSON.stringify(rest.body));
  assert.strictEqual(rest.body.nonconformance.status, 'closed');
  assert.ok(rest.body.nonconformance.closedAt, 'closing sets the closing time');

  // The Concern is untouched: closing a Non-conformance is not closing the
  // problem behind it.
  const { rows: [stillOpen] } = await pool.query(
    'SELECT status FROM action_items WHERE id = $1',
    [concern.id]
  );
  assert.strictEqual(stillOpen.status, 'open');

  // And the register's own status filter finds it as closed.
  const closed = await listNonconformances(ground.recorder.token, ground.site.id, '?status=closed');
  const row = closed.body.nonconformances.find((it) => String(it.id) === String(ground.id));
  assert.ok(row, 'the closed record is in the register');
  assert.strictEqual(row.status, 'closed');
  assert.ok(row.closedAt);

  // A closed record is fully dispositioned, so nothing further fits on it.
  const further = await postDisposition(ground.recorder.token, ground.id, {
    dispositionType: 'scrap',
    quantity: 1
  });
  assert.strictEqual(further.status, 409);
});

// ---------------------------------------------------------------------------
// 4. The three corrections, each behind Quality authority
// ---------------------------------------------------------------------------

test('a holder of Quality authority may lower a severity below the Defect code default, with a note', async () => {
  const ground = await makeGround({ severity: 'critical' });
  assert.strictEqual(ground.nonconformance.severity, 'critical');

  const { status, body } = await postLowerSeverity(ground.inspector.token, ground.id, {
    severity: 'minor',
    note: 'Only the label was misprinted; the product conforms.'
  });
  assert.strictEqual(status, 200, JSON.stringify(body));

  const record = body.nonconformance;
  assert.strictEqual(record.severity, 'minor');
  assert.strictEqual(record.severity, 'minor');
  // The correction is part of the record, with who, when and the note.
  assert.strictEqual(record.corrections.length, 1);
  const [correction] = record.corrections;
  assert.strictEqual(correction.kind, 'severity_lowered');
  assert.strictEqual(correction.previousSeverity, 'critical');
  assert.strictEqual(correction.newSeverity, 'minor');
  assert.strictEqual(correction.note, 'Only the label was misprinted; the product conforms.');
  assert.strictEqual(correction.correctedByAccountId, String(ground.inspector.id));
  assert.strictEqual(correction.correctedByAccountName, 'Inspector Quai');
  assert.ok(correction.correctedAt);

  // Readable back through the record's own address.
  const read = await readNonconformance(ground.recorder.token, ground.id);
  assert.strictEqual(read.body.nonconformance.severity, 'minor');
  assert.strictEqual(read.body.nonconformance.corrections[0].correctedByAccountName, 'Inspector Quai');
  assert.strictEqual(read.body.nonconformance.corrections[0].note, correction.note);

  // A note is required: a correction with no reason on it is the row an
  // auditor cannot use.
  const noNote = await postLowerSeverity(ground.inspector.token, ground.id, { severity: 'minor' });
  assert.strictEqual(noNote.status, 400);
  assert.match(noNote.body.message, /note/);

  // And a "lowering" that lowers nothing is a 409 rather than a silent no-op.
  const ground2 = await makeGround({ severity: 'critical' });
  const notLower = await postLowerSeverity(ground2.inspector.token, ground2.id, {
    severity: 'critical',
    note: 'Still critical.'
  });
  assert.strictEqual(notLower.status, 409);
});

test('lowering a severity is refused with 403 without Quality authority, and the severity does not move', async () => {
  const ground = await makeGround({ severity: 'critical' });

  const refused = await postLowerSeverity(ground.recorder.token, ground.id, {
    severity: 'minor',
    note: 'The recorder would like this to be minor.'
  });
  assert.strictEqual(refused.status, 403);
  assert.match(refused.body.message, /Quality authority/);

  const read = await readNonconformance(ground.recorder.token, ground.id);
  assert.strictEqual(read.body.nonconformance.severity, 'critical');
  assert.strictEqual(read.body.nonconformance.corrections.length, 0);
});

test('a closed Non-conformance can be reopened by a holder of Quality authority, with a note', async () => {
  const ground = await makeGround();

  const closed = await postDisposition(ground.recorder.token, ground.id, {
    dispositionType: 'scrap',
    quantity: 20
  });
  assert.strictEqual(closed.body.nonconformance.status, 'closed');
  assert.ok(closed.body.nonconformance.closedAt);

  const { status, body } = await postReopen(ground.inspector.token, ground.id, {
    note: 'Two more pallets of the same lot turned up in the warehouse.'
  });
  assert.strictEqual(status, 200, JSON.stringify(body));

  const record = body.nonconformance;
  assert.strictEqual(record.status, 'dispositioned');
  assert.strictEqual(record.closedAt, null);
  const [correction] = record.corrections;
  assert.strictEqual(correction.kind, 'reopened');
  assert.strictEqual(correction.previousStatus, 'closed');
  assert.strictEqual(correction.newStatus, 'dispositioned');
  assert.strictEqual(correction.note, 'Two more pallets of the same lot turned up in the warehouse.');
  assert.strictEqual(correction.correctedByAccountName, 'Inspector Quai');
  assert.ok(correction.correctedAt);

  // Only a closed record can be reopened.
  const again = await postReopen(ground.inspector.token, ground.id, { note: 'Again.' });
  assert.strictEqual(again.status, 409);
  assert.match(again.body.message, /closed/);

  // And a reopen with no note is refused before it is attempted.
  const noNote = await postReopen(ground.inspector.token, ground.id, {});
  assert.strictEqual(noNote.status, 400);
  assert.match(noNote.body.message, /note/);
});

test('reopening a Non-conformance is refused with 403 without Quality authority', async () => {
  const ground = await makeGround();
  await postDisposition(ground.recorder.token, ground.id, {
    dispositionType: 'scrap',
    quantity: 20
  });

  const refused = await postReopen(ground.recorder.token, ground.id, {
    note: 'I would like this back.'
  });
  assert.strictEqual(refused.status, 403);
  assert.match(refused.body.message, /Quality authority/);

  const read = await readNonconformance(ground.recorder.token, ground.id);
  assert.strictEqual(read.body.nonconformance.status, 'closed');
  assert.strictEqual(read.body.nonconformance.corrections.length, 0);
});

test('a Non-conformance recorded in error can be cancelled by a holder of Quality authority, with a note', async () => {
  const ground = await makeGround();

  const { status, body } = await postCancel(ground.inspector.token, ground.id, {
    note: 'Recorded against the wrong Product; the right one is already on the log.'
  });
  assert.strictEqual(status, 200, JSON.stringify(body));

  const record = body.nonconformance;
  assert.strictEqual(record.status, 'cancelled');
  assert.ok(record.closedAt, 'a cancelled record is finished with, and carries the time');
  const [correction] = record.corrections;
  assert.strictEqual(correction.kind, 'cancelled');
  assert.strictEqual(correction.previousStatus, 'open');
  assert.strictEqual(correction.newStatus, 'cancelled');
  assert.strictEqual(correction.note, 'Recorded against the wrong Product; the right one is already on the log.');
  assert.strictEqual(correction.correctedByAccountName, 'Inspector Quai');
  assert.ok(correction.correctedAt);

  // A second cancellation is a 409: the note on the first one is the record of
  // why it went.
  const again = await postCancel(ground.inspector.token, ground.id, { note: 'Again.' });
  assert.strictEqual(again.status, 409);
});

test('cancelling a Non-conformance is refused with 403 without Quality authority', async () => {
  const ground = await makeGround();

  const refused = await postCancel(ground.recorder.token, ground.id, {
    note: 'I would like this record gone.'
  });
  assert.strictEqual(refused.status, 403);
  assert.match(refused.body.message, /Quality authority/);

  const read = await readNonconformance(ground.recorder.token, ground.id);
  assert.strictEqual(read.body.nonconformance.status, 'open');
  assert.strictEqual(read.body.nonconformance.corrections.length, 0);
});

test('a cancelled Non-conformance accepts no further Dispositions or quantity changes', async () => {
  const ground = await makeGround();
  const cancelled = await postCancel(ground.inspector.token, ground.id, {
    note: 'Cancelled in error — a duplicate of NC-HCM-2026-00001.'
  });
  assert.strictEqual(cancelled.status, 200, JSON.stringify(cancelled.body));

  const disposition = await postDisposition(ground.recorder.token, ground.id, {
    dispositionType: 'scrap',
    quantity: 2
  });
  assert.strictEqual(disposition.status, 409);
  assert.match(disposition.body.message, /cancelled/);

  const quantity = await postTo(ground.recorder.token, ground.id, 'quantity', { quantity: 25 });
  assert.strictEqual(quantity.status, 409);
  assert.match(quantity.body.message, /cancelled/);

  // A Concession is a Disposition too, and the record's own state refuses it
  // whatever authority the caller holds.
  const concession = await postConcession(ground.inspector.token, ground.id, {
    quantity: 2,
    reference: 'DEV-2026-0019',
    note: 'Accepted as it is.'
  });
  assert.strictEqual(concession.status, 409);

  // The record went nowhere: no dispositions, the quantity it was recorded
  // with, and only the cancellation among its corrections.
  const read = await readNonconformance(ground.recorder.token, ground.id);
  assert.strictEqual(read.body.nonconformance.dispositions.length, 0);
  assert.strictEqual(read.body.nonconformance.quantityAffected, 20);
  assert.strictEqual(read.body.nonconformance.quantityDispositioned, 0);
  assert.strictEqual(read.body.nonconformance.corrections.length, 1);
});
