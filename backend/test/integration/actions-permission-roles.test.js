/*
 * The Actions retrofit (ADR-0061, issue #499) keeps the audience every route
 * had before it — measured over HTTP against a real database and a real local
 * session, the same seam actions.test.js and capas.test.js use.
 *
 * Why this file exists. Every fixture in the Actions suite inserts
 * `role: 'supervisor'` (actions.test.js's own `insertAccount` default), and the
 * three codes this retrofit asks — `ACT_LOG_DISPLAY`, `ACT_RAISE` and
 * `ACT_CAPA_DISPLAY` — are seeded on every role. So "the existing suite still
 * passes" cannot on its own show that the retrofit refused nobody: a gate that
 * only admitted supervisors would leave that suite green.
 *
 * Nor can the suite show the other half of the card's claim. Sixteen Actions
 * routes are deliberately left on their Grant check rather than retrofitted
 * (the findings in the handoff), and those must still admit the operator who
 * holds a write Grant on its line — that is the "behaviour changes for nobody"
 * half that a role-narrowing would break.
 *
 * Both questions are asked here as the Account that would notice first: an
 * operator, holding the default group ROLE_STANDARD and nothing else.
 */

const test = require('node:test');
const assert = require('node:assert');
const { tokenFor } = require('../helpers/session');

let server;
let base;
let pool;
let closePool;

const insertedAccountIds = [];
const insertedSiteIds = [];
const insertedOrgUnitIds = [];
const insertedActionIds = [];

let counter = 0;
function uniqueCode(prefix) {
  counter += 1;
  return `${prefix}${process.pid}${counter}`;
}

async function authHeader(subject) {
  const token = await tokenFor(subject);
  return { authorization: `Bearer ${token}` };
}

async function insertAccount({ role }) {
  const subject = uniqueCode('acct');
  const { rows: [row] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status)
     VALUES ($1, 'Actions Permission Test Account', $2, $3, true, 'approved') RETURNING id`,
    [`${subject}@example.com`, role, subject]
  );
  insertedAccountIds.push(row.id);
  return { id: row.id, role, token: await authHeader(subject) };
}

async function insertSite() {
  const { rows: [row] } = await pool.query(
    `INSERT INTO sites (code, name, timezone)
     VALUES ($1, 'Actions Permission Test Site', 'Asia/Ho_Chi_Minh') RETURNING id`,
    [uniqueCode('ST')]
  );
  insertedSiteIds.push(row.id);
  return row.id;
}

async function insertOrgUnit(siteId) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, NULL, $2, 'Actions Permission Unit', 'area') RETURNING id`,
    [siteId, uniqueCode('OU')]
  );
  insertedOrgUnitIds.push(row.id);
  return row.id;
}

async function insertGrant({ accountId, orgUnitId, canWrite = false }) {
  await pool.query(
    `INSERT INTO app_user_org_units (app_user_id, org_unit_id, can_write) VALUES ($1, $2, $3)`,
    [accountId, orgUnitId, canWrite]
  );
}

async function get(path, token) {
  const response = await fetch(`${base}${path}`, { headers: token });
  const payload = await response.json().catch(() => null);
  return { response, payload };
}

async function post(path, token, body) {
  const response = await fetch(`${base}${path}`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body ?? {})
  });
  const payload = await response.json().catch(() => null);
  return { response, payload };
}

let operator; // role operator: the default group only, writing on its line.
let siteId;
let orgUnitId;

test.before(async () => {
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

  operator = await insertAccount({ role: 'operator' });
  siteId = await insertSite();
  orgUnitId = await insertOrgUnit(siteId);

  // A write Grant on its own line: today's Actions writes are governed by the
  // Grant, so this is what makes the operator able to raise, record a measure
  // and move a phase — the acts the findings table says were left alone.
  await insertGrant({ accountId: operator.id, orgUnitId, canWrite: true });
});

test.after(async () => {
  // Children before parents, in FK order — the same order actions.test.js uses:
  // a measure's `parent_action_item_id` means the children go first.
  await pool.query(
    'DELETE FROM action_items WHERE parent_action_item_id = ANY($1)',
    [insertedActionIds]
  );
  await pool.query('DELETE FROM action_items WHERE id = ANY($1)', [insertedActionIds]);
  await pool.query('DELETE FROM app_user_org_units WHERE app_user_id = ANY($1)', [
    insertedAccountIds
  ]);
  await pool.query('DELETE FROM app_users WHERE id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM org_units WHERE id = ANY($1)', [insertedOrgUnitIds]);
  await pool.query('DELETE FROM sites WHERE id = ANY($1)', [insertedSiteIds]);
  await new Promise((resolve) => server.close(resolve));
  await closePool();
});

// ---------------------------------------------------------------------------
// The premise the retrofit rests on, executed rather than asserted: an Account
// holding the default group alone really does hold all three codes.
// ---------------------------------------------------------------------------

test('an operator holds the three codes the retrofit asks', async () => {
  const { response, payload } = await get('/api/people/me', operator.token);
  assert.strictEqual(response.status, 200, JSON.stringify(payload));

  for (const code of ['ACT_LOG_DISPLAY', 'ACT_RAISE', 'ACT_CAPA_DISPLAY']) {
    assert.ok(
      payload.permissions.includes(code),
      `${code} must reach every Account through ROLE_STANDARD — held: ${payload.permissions.join(', ')}`
    );
  }
});

// ---------------------------------------------------------------------------
// The six retrofitted reads: an operator could reach every one before
// ADR-0061 and still does.
// ---------------------------------------------------------------------------

const retrofittedReads = [
  ['the Action register', () => `/api/actions/sites/${siteId}/actions`],
  ['the Pillar catalogue', () => '/api/actions/pillars'],
  ['the CAPA list', () => '/api/actions/capas']
];

for (const [label, path] of retrofittedReads) {
  test(`an operator reads ${label} — the retrofit refused nobody`, async () => {
    const { response, payload } = await get(path(), operator.token);
    assert.strictEqual(response.status, 200, `${label}: ${JSON.stringify(payload)}`);
  });
}

// One Action, one CAPA and an Action's escalation targets all need a record to
// name, and the ids below name none: a 404 is the proof that the permission
// gate admitted the caller and the route's own existence check answered, since
// a refusal here would be a 403 from the code instead.
test('an operator reaches the one-Action, one-CAPA and escalation-target reads', async () => {
  const detail = await get('/api/actions/999999999', operator.token);
  assert.strictEqual(detail.response.status, 404, JSON.stringify(detail.payload));

  const capa = await get('/api/actions/capas/999999999', operator.token);
  assert.strictEqual(capa.response.status, 404, JSON.stringify(capa.payload));

  const targets = await get('/api/actions/999999999/escalation-targets', operator.token);
  assert.strictEqual(targets.response.status, 404, JSON.stringify(targets.payload));
});

// ---------------------------------------------------------------------------
// The write half: raising is retrofitted (ACT_RAISE, held by everyone), and the
// routes left on their Grant check still admit this operator.
// ---------------------------------------------------------------------------

test('an operator raises a Concern, records a measure and moves a phase', async () => {
  const raised = await post(`/api/actions/sites/${siteId}/actions`, operator.token, {
    orgUnitId: String(orgUnitId),
    title: 'Guard keeps working loose'
  });
  assert.strictEqual(raised.response.status, 201, JSON.stringify(raised.payload));
  const concernId = raised.payload.action.id;
  insertedActionIds.push(concernId);

  // `POST /:id/measures` is a finding, not a retrofit (`ACT_MEASURE` is
  // supervisor-and-above). The operator's write Grant is the whole gate there.
  const measure = await post(`/api/actions/${concernId}/measures`, operator.token, {
    actionType: 'containment',
    title: 'Clamp the guard'
  });
  assert.strictEqual(measure.response.status, 201, JSON.stringify(measure.payload));
  insertedActionIds.push(measure.payload.action.id);

  // `POST /:id/phases/:phase/complete` likewise (`ACT_VERIFY` names verifying
  // one phase, and is supervisor-and-above): the write Grant still decides.
  const phase = await post(`/api/actions/${concernId}/phases/plan/complete`, operator.token, {
    note: 'Planned'
  });
  assert.strictEqual(phase.response.status, 200, JSON.stringify(phase.payload));
  assert.strictEqual(phase.payload.action.openPhase.phase, 'do');

  // And the Action it raised is readable back through the retrofitted read.
  const detail = await get(`/api/actions/${concernId}`, operator.token);
  assert.strictEqual(detail.response.status, 200, JSON.stringify(detail.payload));
  assert.strictEqual(detail.payload.action.measures.length, 1);
});
