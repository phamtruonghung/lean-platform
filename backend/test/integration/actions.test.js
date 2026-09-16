/*
 * The action log over HTTP (issue #176), against a real database and a real
 * (locally issued) JWKS — the same seam as work-orders.test.js and
 * tier-board.test.js, whose fixture scaffolding this file mirrors closely.
 *
 * The Actions that other tests read are inserted directly against the
 * database rather than through POST /actions, where the point is the ordering
 * and the filtering rather than the raise path — the same split
 * tier-board.test.js makes for its own fixtures.
 *
 * Every test that asserts on a register owns a fresh Site: the register is a
 * Site-wide read, so a row another test left behind would otherwise appear in
 * an assertion about this Site's list.
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

async function insertAccount({ role = 'supervisor', employeeId = null } = {}) {
  const subject = uniqueCode('acct');
  const { rows: [row] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status, employee_id)
     VALUES ($1, 'Actions Test Account', $2, $3, TRUE, 'approved', $4) RETURNING id`,
    [`${subject}@example.com`, role, subject, employeeId]
  );
  insertedAccountIds.push(row.id);
  return { id: row.id, token: await authHeader(subject) };
}

async function insertSite({ name = 'Actions Test Site' } = {}) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO sites (code, name, timezone) VALUES ($1, $2, 'Asia/Ho_Chi_Minh') RETURNING id, code, name`,
    [uniqueCode('ST'), name]
  );
  insertedSiteIds.push(row.id);
  return row;
}

async function insertOrgUnit(siteId, { parentId = null, unitType = 'area', name = 'Actions Unit' } = {}) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, $2, $3, $4, $5) RETURNING id, code, name, path`,
    [siteId, parentId, uniqueCode('OU'), name, unitType]
  );
  insertedOrgUnitIds.push(row.id);
  return row;
}

async function insertEmployee({ isActive = true } = {}) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO employees (employee_no, first_name, last_name, is_active)
     VALUES ($1, 'Ann', 'Fitter', $2) RETURNING id, display_name, is_active`,
    [uniqueCode('EMP'), isActive]
  );
  insertedEmployeeIds.push(row.id);
  return row;
}

async function insertGrant({ accountId, orgUnitId, canWrite = false }) {
  await pool.query(
    `INSERT INTO app_user_org_units (app_user_id, org_unit_id, can_write) VALUES ($1, $2, $3)`,
    [accountId, orgUnitId, canWrite]
  );
}

// Directly inserted, for the ordering and filtering tests: the raise path is
// covered by its own tests below, and these rows need dates and statuses the
// raise path deliberately does not offer.
async function insertAction(orgUnitId, { title = 'A concern', actionType = 'concern', status = 'open', dueDate = null, priority = 3, ownerEmployeeId = null, pillarCode = null, escalated = false } = {}) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO action_items
       (action_no, org_unit_id, title, action_type, status, due_date, priority,
        owner_employee_id, pillar_code, completed_at, escalated_to_org_unit_id, escalated_at)
     VALUES ($1, $2, $3, $4, $5, $6::date, $7, $8, $9,
             CASE WHEN $5 IN ('done', 'cancelled') THEN now() END,
             CASE WHEN $10 THEN (SELECT parent_id FROM org_units WHERE id = $2) END,
             CASE WHEN $10 THEN now() END)
     RETURNING id, action_no, title, status, due_date, priority, action_type`,
    [
      uniqueCode('AC-'),
      orgUnitId,
      title,
      actionType,
      status,
      dueDate,
      priority,
      ownerEmployeeId,
      pillarCode,
      escalated
    ]
  );
  insertedActionIds.push(row.id);
  return row;
}

async function getRegister(token, siteId, query = '') {
  const response = await fetch(`${base}/api/actions/sites/${siteId}/actions${query}`, {
    headers: token
  });
  const payload = await response.json().catch(() => null);
  return { response, payload };
}

async function postAction(token, siteId, body) {
  const response = await fetch(`${base}/api/actions/sites/${siteId}/actions`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  const payload = await response.json().catch(() => null);
  return { response, payload };
}

async function getAction(token, id) {
  const response = await fetch(`${base}/api/actions/${id}`, { headers: token });
  const payload = await response.json().catch(() => null);
  return { response, payload };
}

let admin;
let noGrantAccount; // approved, no Grant anywhere at all.
let readOnlyAccount; // read Grant on grantedLine.
let writerAccount; // write Grant on grantedLine.
let siblingWriter; // write Grant on otherLine only.
let deepReader; // read Grant on subLine only, and no write Grant anywhere.

let site;
let otherSite;
let grantedArea;
let grantedLine;
let otherLine;
let subLine;
let areaWriter;

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
  noGrantAccount = await insertAccount();
  readOnlyAccount = await insertAccount();
  writerAccount = await insertAccount();
  siblingWriter = await insertAccount();

  site = await insertSite();
  otherSite = await insertSite({ name: 'Another Actions Site' });
  grantedArea = await insertOrgUnit(site.id, { name: 'Granted Area' });
  grantedLine = await insertOrgUnit(site.id, {
    parentId: grantedArea.id,
    unitType: 'line',
    name: 'Line 1'
  });
  otherLine = await insertOrgUnit(site.id, {
    parentId: grantedArea.id,
    unitType: 'line',
    name: 'Line 2'
  });

  subLine = await insertOrgUnit(site.id, {
    parentId: grantedLine.id,
    unitType: 'line',
    name: 'Line 1, Bay 2'
  });
  areaWriter = await insertAccount();
  deepReader = await insertAccount();

  await insertGrant({ accountId: readOnlyAccount.id, orgUnitId: grantedLine.id, canWrite: false });
  await insertGrant({ accountId: areaWriter.id, orgUnitId: grantedArea.id, canWrite: true });
  await insertGrant({ accountId: writerAccount.id, orgUnitId: grantedLine.id, canWrite: true });
  await insertGrant({ accountId: siblingWriter.id, orgUnitId: otherLine.id, canWrite: true });
  // Deliberately the deepest unit in the tree and read-only: this Account can
  // see the Site (issue #198's criterion) while holding no write Grant at all,
  // and its one Grant reaches nothing above subLine.
  await insertGrant({ accountId: deepReader.id, orgUnitId: subLine.id, canWrite: false });
});

test.after(async () => {
  // Children before parents, in FK order: the Actions first, then the accounts'
  // Grants, the accounts, the Employees, the Org Units and the Sites.
  // Actions first, and measures before the Concerns they answer: a self-
  // reference means an untracked measure under a tracked parent is a foreign
  // key violation in the wrong order, which leaves the cleanup promise
  // rejected, the server open, and the file hanging rather than failing.
  await pool.query('DELETE FROM action_items WHERE parent_action_item_id = ANY($1)', [insertedActionIds]);
  await pool.query('DELETE FROM action_items WHERE id = ANY($1)', [insertedActionIds]);
  await pool.query('DELETE FROM app_user_org_units WHERE app_user_id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM app_users WHERE id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM employees WHERE id = ANY($1)', [insertedEmployeeIds]);
  await pool.query('DELETE FROM org_units WHERE id = ANY($1)', [insertedOrgUnitIds]);
  await pool.query('DELETE FROM sites WHERE id = ANY($1)', [insertedSiteIds]);
  await new Promise((resolve) => server.close(resolve));
  await closePool();
  await jwks.close();
});

// ---------------------------------------------------------------------------
// Raising a Concern.
// ---------------------------------------------------------------------------

test('raising a concern returns 201, in status open, with the Site own number', async () => {
  const unit = await insertOrgUnit(site.id, { name: 'Raising Unit' });
  const { response, payload } = await postAction(admin.token, site.id, {
    orgUnitId: String(unit.id),
    title: 'Guard keeps working loose on the conveyor'
  });

  assert.strictEqual(response.status, 201);
  const action = payload.action;
  insertedActionIds.push(action.id);
  assert.strictEqual(action.status, 'open');
  assert.strictEqual(action.actionType, 'concern');
  assert.strictEqual(action.title, 'Guard keeps working loose on the conveyor');
  assert.strictEqual(action.priority, 3);
  assert.strictEqual(action.orgUnitId, String(unit.id));
  assert.strictEqual(action.orgUnitName, 'Raising Unit');
  assert.strictEqual(action.siteId, String(site.id));
  assert.match(action.actionNo, new RegExp(`^AC-${site.code}-\\d{4}-\\d{5}$`));
  assert.strictEqual(action.escalatedToOrgUnitId, null);
});

test('the raise body is validated field by field, each refusal naming its field', async () => {
  const unit = await insertOrgUnit(site.id);
  const good = { orgUnitId: String(unit.id), title: 'A concern' };

  for (const [body, message] of [
    [{ ...good, title: undefined }, 'title is required'],
    [{ ...good, title: '   ' }, 'title is required'],
    [{ ...good, orgUnitId: undefined }, 'orgUnitId must be a valid Org Unit id'],
    [{ ...good, orgUnitId: 'abc' }, 'orgUnitId must be a valid Org Unit id'],
    [{ ...good, actionType: 'corrective' }, 'actionType must be one of'],
    [{ ...good, actionType: 'made-up' }, 'actionType must be one of'],
    [{ ...good, dueDate: '2026-13-40' }, 'dueDate must be a valid YYYY-MM-DD date'],
    [{ ...good, dueDate: 'tomorrow' }, 'dueDate must be a valid YYYY-MM-DD date'],
    [{ ...good, priority: 9 }, 'priority must be one of'],
    [{ ...good, pillarCode: 'Z' }, 'pillarCode must be one of']
  ]) {
    const { response, payload } = await postAction(admin.token, site.id, body);
    assert.strictEqual(response.status, 400, `expected 400 for ${JSON.stringify(body)}`);
    assert.ok(payload.message.startsWith(message), `${payload.message} should start ${message}`);
  }
});

test('the six types are accepted, including the value that replaced corrective', async () => {
  const unit = await insertOrgUnit(site.id);
  for (const actionType of [
    'concern',
    'containment',
    'countermeasure',
    'preventive',
    'improvement',
    'routine'
  ]) {
    const { response, payload } = await postAction(admin.token, site.id, {
      orgUnitId: String(unit.id),
      title: `A ${actionType}`,
      actionType
    });
    assert.strictEqual(response.status, 201, `${actionType} should be accepted`);
    insertedActionIds.push(payload.action.id);
    assert.strictEqual(payload.action.actionType, actionType);
  }
});

test('a due date, a priority, a Pillar and a title are all kept', async () => {
  const unit = await insertOrgUnit(site.id);
  const { response, payload } = await postAction(admin.token, site.id, {
    orgUnitId: String(unit.id),
    title: '  A padded summary  ',
    description: 'What was seen',
    actionType: 'containment',
    pillarCode: 'D',
    dueDate: '2026-12-01',
    priority: 1
  });

  assert.strictEqual(response.status, 201);
  insertedActionIds.push(payload.action.id);
  assert.strictEqual(payload.action.title, 'A padded summary');
  assert.strictEqual(payload.action.description, 'What was seen');
  assert.strictEqual(payload.action.pillarCode, 'D');
  assert.strictEqual(payload.action.dueDate, '2026-12-01');
  assert.strictEqual(payload.action.priority, 1);
});

test('an Employee named as owner is resolved through People, and a departed one is refused', async () => {
  const unit = await insertOrgUnit(site.id);
  const here = await insertEmployee();
  const gone = await insertEmployee({ isActive: false });

  const { response, payload } = await postAction(admin.token, site.id, {
    orgUnitId: String(unit.id),
    title: 'Owned by somebody',
    ownerEmployeeId: String(here.id)
  });
  assert.strictEqual(response.status, 201);
  insertedActionIds.push(payload.action.id);
  assert.strictEqual(payload.action.ownerEmployeeId, String(here.id));
  assert.strictEqual(payload.action.ownerName, here.display_name);

  const departed = await postAction(admin.token, site.id, {
    orgUnitId: String(unit.id),
    title: 'Owned by somebody gone',
    ownerEmployeeId: String(gone.id)
  });
  assert.strictEqual(departed.response.status, 409);

  const unknown = await postAction(admin.token, site.id, {
    orgUnitId: String(unit.id),
    title: 'Owned by nobody',
    ownerEmployeeId: '99999999'
  });
  assert.strictEqual(unknown.response.status, 404);
});

test('raised_by is the caller own Employee link, and null for an Account without one', async () => {
  const unit = await insertOrgUnit(site.id);
  const me = await insertEmployee();
  const linked = await insertAccount({ employeeId: me.id });
  // A read Grant is enough to raise (this file's own scope test), and this
  // Account holds exactly that: its own link is the subject here.
  await insertGrant({ accountId: linked.id, orgUnitId: grantedLine.id, canWrite: false });

  const { response, payload } = await postAction(linked.token, site.id, {
    orgUnitId: String(grantedLine.id),
    title: 'Raised by a linked Account'
  });
  assert.strictEqual(response.status, 201);
  insertedActionIds.push(payload.action.id);
  assert.strictEqual(payload.action.raisedByEmployeeId, String(me.id));
  assert.strictEqual(payload.action.raisedByName, me.display_name);

  const unlinked = await postAction(admin.token, site.id, {
    orgUnitId: String(unit.id),
    title: 'Raised by an administrator who is nobody'
  });
  assert.strictEqual(unlinked.response.status, 201);
  insertedActionIds.push(unlinked.payload.action.id);
  assert.strictEqual(unlinked.payload.action.raisedByEmployeeId, null);
});

// ---------------------------------------------------------------------------
// Scope: a Concern may be raised anywhere in a Site the caller can see (#198),
// and every other kind of Action keeps the Grant check it had.
// ---------------------------------------------------------------------------

test('a caller holding only a read Grant at the Org Unit can raise a concern', async () => {
  const { response, payload } = await postAction(readOnlyAccount.token, site.id, {
    orgUnitId: String(grantedLine.id),
    title: 'Seen by somebody who only reads this line'
  });

  assert.strictEqual(response.status, 201);
  insertedActionIds.push(payload.action.id);
  assert.strictEqual(payload.action.orgUnitId, String(grantedLine.id));
});

test('a caller who can see the Site raises a Concern at an Org Unit no Grant of theirs reaches (#198)', async () => {
  // siblingWriter holds a write Grant on Line 2 and nothing at all reaching
  // Line 1: it can see the Site, and a concern is a report rather than a
  // decision, so Line 1 is fair game. This is the ticket's own case — the
  // operator granted on one line who finds a defect that came from another.
  const onAnotherLine = await postAction(siblingWriter.token, site.id, {
    orgUnitId: String(grantedLine.id),
    title: 'Found on a line I hold no Grant on'
  });
  assert.strictEqual(onAnotherLine.response.status, 201);
  insertedActionIds.push(onAnotherLine.payload.action.id);
  assert.strictEqual(onAnotherLine.payload.action.orgUnitId, String(grantedLine.id));
  assert.strictEqual(onAnotherLine.payload.action.actionType, 'concern');

  // ... and upwards, which a Grant can never do: a Grant reaches downward
  // only, so deepReader's Grant on Line 1, Bay 2 does not reach the area
  // above it. "Any Org Unit of that Site" means exactly that.
  const atAncestor = await postAction(deepReader.token, site.id, {
    orgUnitId: String(grantedArea.id),
    title: 'Found in the area above my own line'
  });
  assert.strictEqual(atAncestor.response.status, 201);
  insertedActionIds.push(atAncestor.payload.action.id);
  assert.strictEqual(atAncestor.payload.action.orgUnitId, String(grantedArea.id));

  // The widened door is the raise and nothing else: the same caller cannot
  // advance the phase of the concern it just raised at that Org Unit.
  const refusedPhase = await completePhase(siblingWriter.token, onAnotherLine.payload.action.id, 'plan', {
    note: 'Not mine to advance'
  });
  assert.strictEqual(refusedPhase.response.status, 403);
});

test('an Account holding no Grant anywhere in the Site is still refused, in the shared wording (#198)', async () => {
  const noGrant = await postAction(noGrantAccount.token, site.id, {
    orgUnitId: String(grantedLine.id),
    title: 'Out of reach'
  });
  assert.strictEqual(noGrant.response.status, 403);
  assert.match(noGrant.payload.message, /granted Org Units$/);

  // At an Org Unit of the Site that nobody holds a Grant on at all, so the
  // refusal is about the caller rather than about the Org Unit.
  const ownerless = await insertOrgUnit(site.id, { name: 'Nobody Granted Here' });
  const nowhere = await postAction(noGrantAccount.token, site.id, {
    orgUnitId: String(ownerless.id),
    title: 'Still out of reach'
  });
  assert.strictEqual(nowhere.response.status, 403);
  assert.match(nowhere.payload.message, /granted Org Units$/);
});

test('a Concern is refused at another Site, however visible the caller own Site is (#198)', async () => {
  const elsewhere = await insertOrgUnit(otherSite.id, { name: 'Another Site Unit' });

  const crossSite = await postAction(siblingWriter.token, otherSite.id, {
    orgUnitId: String(elsewhere.id),
    title: 'A concern in a Site I hold no Grant in'
  });
  assert.strictEqual(crossSite.response.status, 403);
  assert.match(crossSite.payload.message, /granted Org Units$/);

  // The same caller, at the same Org Unit, in the Site it can see: the refusal
  // above is the Site, not the kind.
  const ownSite = await postAction(siblingWriter.token, site.id, {
    orgUnitId: String(grantedLine.id),
    title: 'The same concern in the Site I can see'
  });
  assert.strictEqual(ownSite.response.status, 201);
  insertedActionIds.push(ownSite.payload.action.id);
});

test('only raising a Concern is opened up: every other kind keeps its Grant check (#198)', async () => {
  // siblingWriter can see the Site, so its Concerns at grantedLine are
  // accepted (the test above) — but none of the other five kinds is a report,
  // and not one of them gets through without a Grant reaching that Org Unit.
  for (const actionType of [
    'containment',
    'countermeasure',
    'preventive',
    'improvement',
    'routine'
  ]) {
    const refused = await postAction(siblingWriter.token, site.id, {
      orgUnitId: String(grantedLine.id),
      title: `A ${actionType} with no Grant reaching here`,
      actionType
    });
    assert.strictEqual(
      refused.response.status,
      403,
      `${actionType} should still be refused without a Grant reaching its Org Unit`
    );
    assert.match(refused.payload.message, /granted Org Units$/);
  }

  // A Countermeasure raised by an Account with no write Grant anywhere: still
  // refused, because that Account holds no Grant at all reaching the Org Unit
  // named.
  const deepCountermeasure = await postAction(deepReader.token, site.id, {
    orgUnitId: String(grantedArea.id),
    title: 'A countermeasure for the area above my line',
    actionType: 'countermeasure'
  });
  assert.strictEqual(deepCountermeasure.response.status, 403);

  // And the check those kinds keep is the one they had before #198 — a Grant
  // reaching the Org Unit, read or write alike — rather than a write Grant:
  // #198 opened the Concern's door and moved nothing else. Nail it down, so a
  // later tightening is a deliberate decision rather than a silent one.
  const containment = await postAction(readOnlyAccount.token, site.id, {
    orgUnitId: String(grantedLine.id),
    title: 'A containment where I may only read',
    actionType: 'containment'
  });
  assert.strictEqual(containment.response.status, 201);
  insertedActionIds.push(containment.payload.action.id);
});

test('an unknown Org Unit, a malformed one and one in another Site are all refused before scope', async () => {
  const elsewhere = await insertOrgUnit(otherSite.id);

  const unknown = await postAction(admin.token, site.id, {
    orgUnitId: '99999999',
    title: 'No such unit'
  });
  assert.strictEqual(unknown.response.status, 404);

  const crossSite = await postAction(admin.token, site.id, {
    orgUnitId: String(elsewhere.id),
    title: 'Another Site unit'
  });
  assert.strictEqual(crossSite.response.status, 404);

  const unknownSite = await postAction(admin.token, '99999999', {
    orgUnitId: String(grantedLine.id),
    title: 'No such Site'
  });
  assert.strictEqual(unknownSite.response.status, 404);

  const noToken = await fetch(`${base}/api/actions/sites/${site.id}/actions`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ title: 'Anonymous' })
  });
  assert.strictEqual(noToken.status, 401);
});

// ---------------------------------------------------------------------------
// The register: Site-wide, worst first, history on request.
// ---------------------------------------------------------------------------

test('the register orders what is overdue first, then by due date, then priority, then the undated', async () => {
  const fresh = await insertSite({ name: 'Ordering Site' });
  const unit = await insertOrgUnit(fresh.id, { name: 'Ordering Unit' });

  const worstOverdue = await insertAction(unit.id, { title: 'Overdue by three', dueDate: '2020-01-01' });
  const mildOverdue = await insertAction(unit.id, { title: 'Overdue by less', dueDate: '2020-01-03' });
  const dueSoon = await insertAction(unit.id, { title: 'Due soon', dueDate: '2030-01-01', priority: 5 });
  const undated = await insertAction(unit.id, { title: 'No date at all', priority: 1 });
  const sameDayLowPriority = await insertAction(unit.id, { title: 'Due soon, low priority', dueDate: '2030-01-01', priority: 2 });

  const { response, payload } = await getRegister(admin.token, fresh.id);
  assert.strictEqual(response.status, 200);
  assert.strictEqual(payload.truncated, false);
  assert.deepStrictEqual(
    payload.actions.map((action) => action.actionNo),
    [
      worstOverdue.action_no,
      mildOverdue.action_no,
      sameDayLowPriority.action_no,
      dueSoon.action_no,
      undated.action_no
    ]
  );

  // is_overdue is the register's own judgement about today, not a stored flag.
  assert.strictEqual(payload.actions[0].dueDate, '2020-01-01');
  assert.strictEqual(payload.actions[0].isOverdue, true);
  assert.ok(payload.actions[0].daysOverdue > 0);
  assert.strictEqual(payload.actions[3].isOverdue, false);
  assert.strictEqual(payload.actions[3].daysOverdue, null);
  assert.ok(payload.actions.every((action) => action.siteId === String(fresh.id)));
});

test('the register is readable by an Account with no Grant anywhere', async () => {
  const fresh = await insertSite({ name: 'Open Read Site' });
  const unit = await insertOrgUnit(fresh.id);
  await insertAction(unit.id, { title: 'Everybody may read this' });

  const { response, payload } = await getRegister(noGrantAccount.token, fresh.id);
  assert.strictEqual(response.status, 200);
  assert.strictEqual(payload.actions.length, 1);
  assert.strictEqual(payload.actions[0].title, 'Everybody may read this');
});

test('a closed Action is absent by default and present when history is asked for', async () => {
  const fresh = await insertSite({ name: 'History Site' });
  const unit = await insertOrgUnit(fresh.id);
  const open = await insertAction(unit.id, { title: 'Still open' });
  const done = await insertAction(unit.id, { title: 'Finished', status: 'done' });
  const cancelled = await insertAction(unit.id, { title: 'Called off', status: 'cancelled' });

  const plain = await getRegister(admin.token, fresh.id);
  assert.deepStrictEqual(plain.payload.actions.map((action) => action.actionNo), [open.action_no]);

  const history = await getRegister(admin.token, fresh.id, '?includeHistory=true');
  assert.strictEqual(history.payload.actions.length, 3);
  const numbers = history.payload.actions.map((action) => action.actionNo);
  assert.ok(numbers.includes(done.action_no));
  assert.ok(numbers.includes(cancelled.action_no));
});

test('every filter narrows the register, and an Org Unit filter includes its branch', async () => {
  const fresh = await insertSite({ name: 'Filter Site' });
  const area = await insertOrgUnit(fresh.id, { name: 'Filter Area' });
  const line = await insertOrgUnit(fresh.id, { parentId: area.id, name: 'Filter Line' });
  const other = await insertOrgUnit(fresh.id, { name: 'Other Area' });
  const owner = await insertEmployee();

  const onArea = await insertAction(area.id, { title: 'On the area' });
  const onLine = await insertAction(line.id, { title: 'On the line', actionType: 'containment' });
  const onOther = await insertAction(other.id, { title: 'Elsewhere', actionType: 'containment', pillarCode: 'S' });
  const owned = await insertAction(other.id, { title: 'Owned', ownerEmployeeId: owner.id, actionType: 'countermeasure' });
  const blocked = await insertAction(other.id, { title: 'Blocked', status: 'blocked' });

  const byBranch = await getRegister(admin.token, fresh.id, `?orgUnitId=${area.id}`);
  assert.deepStrictEqual(
    byBranch.payload.actions.map((action) => action.actionNo).sort(),
    [onArea.action_no, onLine.action_no].sort()
  );

  const byType = await getRegister(admin.token, fresh.id, '?actionType=containment');
  assert.deepStrictEqual(
    byType.payload.actions.map((action) => action.actionNo).sort(),
    [onLine.action_no, onOther.action_no].sort()
  );

  const byOwner = await getRegister(admin.token, fresh.id, `?ownerEmployeeId=${owner.id}`);
  assert.deepStrictEqual(byOwner.payload.actions.map((action) => action.actionNo), [owned.action_no]);

  const byPillar = await getRegister(admin.token, fresh.id, '?pillarCode=S');
  assert.deepStrictEqual(byPillar.payload.actions.map((action) => action.actionNo), [onOther.action_no]);

  const byStatus = await getRegister(admin.token, fresh.id, '?status=blocked');
  assert.deepStrictEqual(byStatus.payload.actions.map((action) => action.actionNo), [blocked.action_no]);
});

test('a filter value outside its set is a 400, not a quietly empty list', async () => {
  for (const query of [
    '?status=opne',
    '?actionType=corrective',
    '?ownerEmployeeId=abc',
    '?pillarCode=Z'
  ]) {
    const { response, payload } = await getRegister(admin.token, site.id, query);
    assert.strictEqual(response.status, 400, `${query} should be a 400`);
    assert.ok(payload.message.startsWith(query.split('=')[0].slice(1)));
  }
});

test('a malformed or cross-Site Org Unit filter is a 404, and an unknown Site is a 404', async () => {
  const elsewhere = await insertOrgUnit(otherSite.id);

  const crossSite = await getRegister(admin.token, site.id, `?orgUnitId=${elsewhere.id}`);
  assert.strictEqual(crossSite.response.status, 404);

  const malformed = await getRegister(admin.token, site.id, '?orgUnitId=abc');
  assert.strictEqual(malformed.response.status, 404);

  const unknownSite = await getRegister(admin.token, '99999999');
  assert.strictEqual(unknownSite.response.status, 404);

  const noToken = await getRegister({}, site.id);
  assert.strictEqual(noToken.response.status, 401);
});

test('another Site register never carries this Site Actions', async () => {
  const fresh = await insertSite({ name: 'Isolation A' });
  const other = await insertSite({ name: 'Isolation B' });
  const unitA = await insertOrgUnit(fresh.id);
  await insertOrgUnit(other.id);
  const mine = await insertAction(unitA.id, { title: 'Only in A' });

  const { payload } = await getRegister(admin.token, other.id);
  assert.deepStrictEqual(payload.actions, []);
  assert.ok(mine.action_no);
});

// ---------------------------------------------------------------------------
// One Action, and the Pillar catalogue.
// ---------------------------------------------------------------------------

test('one Action reads back by its own id, with the collections the later slices fill', async () => {
  const unit = await insertOrgUnit(site.id, { name: 'Detail Unit' });
  const raised = await postAction(admin.token, site.id, {
    orgUnitId: String(unit.id),
    title: 'Read me back'
  });
  insertedActionIds.push(raised.payload.action.id);

  const { response, payload } = await getAction(admin.token, raised.payload.action.id);
  assert.strictEqual(response.status, 200);
  assert.strictEqual(payload.action.title, 'Read me back');
  assert.strictEqual(payload.action.orgUnitName, 'Detail Unit');
  assert.strictEqual(payload.action.parent, null);
  assert.deepStrictEqual(payload.action.measures, []);
});

test('an unknown Action is a 404 and a malformed id is a 404, not a 500', async () => {
  const unknown = await getAction(admin.token, '99999999');
  assert.strictEqual(unknown.response.status, 404);
  assert.strictEqual(unknown.payload.message, 'Action not found');

  const malformed = await getAction(admin.token, 'not-an-id');
  assert.strictEqual(malformed.response.status, 404);
});

test('the Pillar catalogue is the five Pillars, in the catalogue order', async () => {
  const response = await fetch(`${base}/api/actions/pillars`, { headers: admin.token });
  const payload = await response.json();

  assert.strictEqual(response.status, 200);
  assert.deepStrictEqual(
    payload.pillars.map((pillar) => pillar.code),
    ['S', 'Q', 'D', 'C', 'P']
  );
  assert.strictEqual(payload.pillars[1].name, 'Quality');
});

test('the register caps an unbounded history and says so', async () => {
  const fresh = await insertSite({ name: 'Cap Site' });
  const unit = await insertOrgUnit(fresh.id);
  // One past the Module's own limit, inserted straight into the database: this
  // is about the read's honesty, not about raising 201 Actions.
  const { ACTION_LIST_LIMIT } = require('../../src/modules/actions/actions');
  const values = [];
  const params = [];
  for (let index = 0; index < ACTION_LIST_LIMIT + 1; index += 1) {
    params.push(uniqueCode('AC-'), unit.id, `Bulk ${index}`);
    values.push(`($${params.length - 2}, $${params.length - 1}, $${params.length})`);
  }
  const { rows } = await pool.query(
    `INSERT INTO action_items (action_no, org_unit_id, title) VALUES ${values.join(', ')} RETURNING id`,
    params
  );
  for (const row of rows) insertedActionIds.push(row.id);

  const { response, payload } = await getRegister(admin.token, fresh.id);
  assert.strictEqual(response.status, 200);
  assert.strictEqual(payload.truncated, true);
  assert.strictEqual(payload.actions.length, ACTION_LIST_LIMIT);
});

// ---------------------------------------------------------------------------
// The PDCA cycle (issue #177).
// ---------------------------------------------------------------------------

async function completePhase(token, actionId, phase, body) {
  const response = await fetch(`${base}/api/actions/${actionId}/phases/${phase}/complete`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body ?? {})
  });
  const payload = await response.json().catch(() => null);
  return { response, payload };
}

function phasesOf(action) {
  return action.phases.map((phase) => `${phase.cycle}:${phase.phase}`);
}

test('raising an Action is born with its cycle-1 Plan, owned and dated like the Action', async () => {
  const unit = await insertOrgUnit(site.id, { name: 'Phase Unit' });
  const owner = await insertEmployee();
  const raised = await postAction(admin.token, site.id, {
    orgUnitId: String(unit.id),
    title: 'Born with a Plan',
    ownerEmployeeId: String(owner.id),
    dueDate: '2026-11-30'
  });
  insertedActionIds.push(raised.payload.action.id);

  assert.strictEqual(raised.payload.action.status, 'open');
  assert.deepStrictEqual(raised.payload.action.openPhase, {
    phase: 'plan',
    cycle: 1,
    dueDate: '2026-11-30',
    ownerEmployeeId: String(owner.id),
    ownerName: owner.display_name
  });

  const detail = await getAction(admin.token, raised.payload.action.id);
  assert.deepStrictEqual(phasesOf(detail.payload.action), ['1:plan']);
  assert.strictEqual(detail.payload.action.phases[0].completedAt, null);
  assert.strictEqual(detail.payload.action.phases[0].note, null);
});

test('an effective cycle walks Plan, Do, Check and Act, and the Act closes the Action', async () => {
  const unit = await insertOrgUnit(site.id);
  // A standalone containment rather than a Concern: this test is about the
  // cycle's own machinery, and a Concern's Act is held to the closure rules
  // (issue #179) that have their own tests below.
  const raised = await postAction(admin.token, site.id, {
    orgUnitId: String(unit.id),
    title: 'A full cycle',
    actionType: 'containment'
  });
  const id = raised.payload.action.id;
  insertedActionIds.push(id);

  const plan = await completePhase(admin.token, id, 'plan', { note: 'Clamp the guard and chase the cause' });
  assert.strictEqual(plan.response.status, 200);
  assert.strictEqual(plan.payload.action.status, 'in_progress');
  assert.deepStrictEqual(phasesOf(plan.payload.action), ['1:plan', '1:do']);
  assert.strictEqual(plan.payload.action.openPhase.phase, 'do');

  const hold = await completePhase(admin.token, id, 'do', { note: 'Guard clamped, bearing changed' });
  assert.strictEqual(hold.response.status, 200);
  assert.deepStrictEqual(phasesOf(hold.payload.action), ['1:plan', '1:do', '1:check']);

  const check = await completePhase(admin.token, id, 'check', {
    note: 'Two weeks, no recurrence',
    outcome: 'effective'
  });
  assert.strictEqual(check.response.status, 200);
  assert.strictEqual(check.payload.action.status, 'in_progress');
  assert.deepStrictEqual(phasesOf(check.payload.action), ['1:plan', '1:do', '1:check', '1:act']);

  const act = await completePhase(admin.token, id, 'act', {
    note: 'Torque added to the pre-start check sheet'
  });
  assert.strictEqual(act.response.status, 200);
  assert.strictEqual(act.payload.action.status, 'done');
  assert.ok(act.payload.action.completedAt);
  assert.strictEqual(act.payload.action.openPhase, null);
  assert.strictEqual(act.payload.action.phases.length, 4);

  // A closed Action refuses every further phase.
  const after = await completePhase(admin.token, id, 'plan', { note: 'Round two' });
  assert.strictEqual(after.response.status, 409);
  assert.match(after.payload.message, /closed/);
});

test('a Check that found it did not hold opens the next cycle and keeps the round that failed', async () => {
  const unit = await insertOrgUnit(site.id);
  const raised = await postAction(admin.token, site.id, {
    orgUnitId: String(unit.id),
    title: 'It came back',
    actionType: 'containment'
  });
  const id = raised.payload.action.id;
  insertedActionIds.push(id);

  await completePhase(admin.token, id, 'plan', { note: 'Plan one' });
  await completePhase(admin.token, id, 'do', { note: 'Do one' });
  const failed = await completePhase(admin.token, id, 'check', {
    note: 'Jam returned after four days',
    outcome: 'not_effective'
  });

  assert.strictEqual(failed.response.status, 200);
  assert.strictEqual(failed.payload.action.status, 'in_progress');
  assert.deepStrictEqual(phasesOf(failed.payload.action), [
    '1:plan',
    '1:do',
    '1:check',
    '2:plan'
  ]);
  assert.strictEqual(failed.payload.action.openPhase.cycle, 2);
  assert.strictEqual(failed.payload.action.phases[2].outcome, 'not_effective');
  assert.strictEqual(failed.payload.action.phases[2].note, 'Jam returned after four days');

  // The second round can close it.
  await completePhase(admin.token, id, 'plan', { note: 'Plan two' });
  await completePhase(admin.token, id, 'do', { note: 'Do two' });
  await completePhase(admin.token, id, 'check', { note: 'Held for a month', outcome: 'effective' });
  const closed = await completePhase(admin.token, id, 'act', { note: 'Standard updated' });
  assert.strictEqual(closed.payload.action.status, 'done');
  // Seven rows, not eight: cycle 1 never reached an Act — the failed Check
  // sent it round again, which is the record this test exists for.
  assert.strictEqual(closed.payload.action.phases.length, 7);
});

test('completing a phase that is not the open one is refused, naming the open one', async () => {
  const unit = await insertOrgUnit(site.id);
  const raised = await postAction(admin.token, site.id, { orgUnitId: String(unit.id), title: 'Out of turn' });
  const id = raised.payload.action.id;
  insertedActionIds.push(id);

  const early = await completePhase(admin.token, id, 'check', { note: 'Jumping ahead', outcome: 'effective' });
  assert.strictEqual(early.response.status, 409);
  assert.match(early.payload.message, /waiting on its plan phase/);
});

test('the phase body is validated: a note is required, and an outcome only on a Check', async () => {
  const unit = await insertOrgUnit(site.id);
  const raised = await postAction(admin.token, site.id, { orgUnitId: String(unit.id), title: 'Validation' });
  const id = raised.payload.action.id;
  insertedActionIds.push(id);

  const noNote = await completePhase(admin.token, id, 'plan', {});
  assert.strictEqual(noNote.response.status, 400);
  assert.strictEqual(noNote.payload.message, 'note is required');

  const blankNote = await completePhase(admin.token, id, 'plan', { note: '   ' });
  assert.strictEqual(blankNote.response.status, 400);

  const outcomeTooEarly = await completePhase(admin.token, id, 'plan', {
    note: 'Plan done',
    outcome: 'effective'
  });
  assert.strictEqual(outcomeTooEarly.response.status, 400);
  assert.strictEqual(outcomeTooEarly.payload.message, 'outcome is only recorded on a Check');

  const notAPhase = await completePhase(admin.token, id, 'planning', { note: 'Typo' });
  assert.strictEqual(notAPhase.response.status, 400);
  assert.match(notAPhase.payload.message, /phase must be one of/);

  await completePhase(admin.token, id, 'plan', { note: 'Plan done' });
  await completePhase(admin.token, id, 'do', { note: 'Do done' });
  const noOutcome = await completePhase(admin.token, id, 'check', { note: 'It worked, honest' });
  assert.strictEqual(noOutcome.response.status, 400);
  assert.match(noOutcome.payload.message, /outcome must be one of/);
});

test('advancing a phase needs a write Grant, and an unknown or malformed Action is a 404', async () => {
  const readOnlyRaised = await postAction(readOnlyAccount.token, site.id, {
    orgUnitId: String(grantedLine.id),
    title: 'Raised by a reader'
  });
  insertedActionIds.push(readOnlyRaised.payload.action.id);

  const refused = await completePhase(readOnlyAccount.token, readOnlyRaised.payload.action.id, 'plan', {
    note: 'Not mine to advance'
  });
  assert.strictEqual(refused.response.status, 403);

  const noGrant = await completePhase(noGrantAccount.token, readOnlyRaised.payload.action.id, 'plan', {
    note: 'Reach nowhere'
  });
  assert.strictEqual(noGrant.response.status, 403);

  const advanced = await completePhase(writerAccount.token, readOnlyRaised.payload.action.id, 'plan', {
    note: 'The line leader advances it'
  });
  assert.strictEqual(advanced.response.status, 200);

  const unknown = await completePhase(admin.token, '99999999', 'plan', { note: 'No such Action' });
  assert.strictEqual(unknown.response.status, 404);

  const malformed = await completePhase(admin.token, 'not-an-id', 'plan', { note: 'Malformed' });
  assert.strictEqual(malformed.response.status, 404);
});

test('the register carries the phase each Action is waiting on', async () => {
  const fresh = await insertSite({ name: 'Open Phase Site' });
  const unit = await insertOrgUnit(fresh.id);
  const raised = await postAction(admin.token, fresh.id, { orgUnitId: String(unit.id), title: 'Waiting on a Do' });
  insertedActionIds.push(raised.payload.action.id);
  await completePhase(admin.token, raised.payload.action.id, 'plan', { note: 'Planned' });

  const { payload } = await getRegister(admin.token, fresh.id);
  assert.strictEqual(payload.actions[0].openPhase.phase, 'do');
  assert.strictEqual(payload.actions[0].openPhase.cycle, 1);
});

// ---------------------------------------------------------------------------
// Measures: the containment and the countermeasure that answer a Concern
// (issue #178).
// ---------------------------------------------------------------------------

async function postMeasure(token, concernId, body) {
  const response = await fetch(`${base}/api/actions/${concernId}/measures`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  const payload = await response.json().catch(() => null);
  return { response, payload };
}

async function raiseConcern(title, overrides = {}) {
  const unit = await insertOrgUnit(site.id, { name: 'Measure Unit' });
  const { response, payload } = await postAction(admin.token, site.id, {
    orgUnitId: String(unit.id),
    title,
    ...overrides
  });
  assert.strictEqual(response.status, 201);
  insertedActionIds.push(payload.action.id);
  return { concern: payload.action, unit };
}

test('a containment raised against a concern lands on it, with its own cycle and number', async () => {
  const { concern } = await raiseConcern('Guard keeps working loose');

  const { response, payload } = await postMeasure(admin.token, concern.id, {
    actionType: 'containment',
    title: 'Clamp the guard'
  });

  assert.strictEqual(response.status, 201);
  const measure = payload.action;
  insertedActionIds.push(measure.id);
  assert.strictEqual(measure.parentId, String(concern.id));
  assert.strictEqual(measure.actionType, 'containment');
  assert.strictEqual(measure.status, 'open');
  assert.strictEqual(measure.openPhase.phase, 'plan');
  assert.notStrictEqual(measure.actionNo, concern.actionNo);
  assert.strictEqual(measure.orgUnitId, concern.orgUnitId);

  // The concern carries it, and says how many it has.
  const detail = await getAction(admin.token, concern.id);
  assert.strictEqual(detail.payload.action.measures.length, 1);
  assert.strictEqual(detail.payload.action.measures[0].id, String(measure.id));
  assert.strictEqual(detail.payload.action.measureCount, 1);
  assert.strictEqual(detail.payload.action.countermeasureCount, 0);
});

test('the concern own Screen shows containment first, then countermeasure, then preventive', async () => {
  const { concern } = await raiseConcern('Pallet wrapper jams');
  for (const actionType of ['preventive', 'countermeasure', 'containment']) {
    const { response, payload } = await postMeasure(admin.token, concern.id, {
      actionType,
      title: `${actionType} on the wrapper`
    });
    assert.strictEqual(response.status, 201);
    insertedActionIds.push(payload.action.id);
  }

  const detail = await getAction(admin.token, concern.id);
  assert.deepStrictEqual(
    detail.payload.action.measures.map((measure) => measure.actionType),
    ['containment', 'countermeasure', 'preventive']
  );
  assert.strictEqual(detail.payload.action.measureCount, 3);
  assert.strictEqual(detail.payload.action.countermeasureCount, 1);
});

test('a measure may be raised wherever the work happens, which is where the write Grant must reach', async () => {
  const fresh = await insertSite({ name: 'Measure Scope Site' });
  const line = await insertOrgUnit(fresh.id, { name: 'Line 9' });
  const stores = await insertOrgUnit(fresh.id, { name: 'Stores' });
  // The caller may write at the store and holds nothing at all on the line.
  await insertGrant({ accountId: writerAccount.id, orgUnitId: stores.id, canWrite: true });

  const concern = await insertAction(line.id, { title: 'Supplier keeps sending the wrong seal' });

  // The measure's own Org Unit is what the Grant has to reach — not the
  // Concern's, which this caller cannot even read.
  const elsewhere = await postMeasure(writerAccount.token, concern.id, {
    actionType: 'countermeasure',
    title: 'The store fixes its own racking',
    orgUnitId: String(stores.id)
  });
  assert.strictEqual(elsewhere.response.status, 201);
  insertedActionIds.push(elsewhere.payload.action.id);
  assert.strictEqual(elsewhere.payload.action.orgUnitId, String(stores.id));

  // Defaulting to the Concern's Org Unit is refused for the same reason: that
  // is a place this caller may not write.
  const defaulted = await postMeasure(writerAccount.token, concern.id, {
    actionType: 'containment',
    title: 'Not mine to write'
  });
  assert.strictEqual(defaulted.response.status, 403);

  // And a caller who may write nowhere near the store is refused too.
  const noGrant = await postMeasure(noGrantAccount.token, concern.id, {
    actionType: 'containment',
    title: 'Reach nowhere',
    orgUnitId: String(stores.id)
  });
  assert.strictEqual(noGrant.response.status, 403);
});

test('the one-level rule and the type set are refused with their own messages', async () => {
  const { concern } = await raiseConcern('It came back twice');

  const asConcern = await postMeasure(admin.token, concern.id, {
    actionType: 'concern',
    title: 'A concern answering a concern'
  });
  assert.strictEqual(asConcern.response.status, 400);
  assert.match(asConcern.payload.message, /actionType must be one of/);

  const asRoutine = await postMeasure(admin.token, concern.id, {
    actionType: 'routine',
    title: 'Order more gloves'
  });
  assert.strictEqual(asRoutine.response.status, 400);

  const noTitle = await postMeasure(admin.token, concern.id, {
    actionType: 'containment',
    title: '   '
  });
  assert.strictEqual(noTitle.response.status, 400);
  assert.strictEqual(noTitle.payload.message, 'title is required');

  // A containment cannot be answered by anything: it is itself an answer.
  const { payload: containment } = await postMeasure(admin.token, concern.id, {
    actionType: 'containment',
    title: 'Clamp it'
  });
  insertedActionIds.push(containment.action.id);

  const underAContainment = await postMeasure(admin.token, containment.action.id, {
    actionType: 'countermeasure',
    title: 'A countermeasure answering a containment'
  });
  assert.strictEqual(underAContainment.response.status, 400);
  assert.match(underAContainment.payload.message, /answers a Concern/);

  // A countermeasure cannot be answered either — the one-level rule.
  const { payload: countermeasure } = await postMeasure(admin.token, concern.id, {
    actionType: 'countermeasure',
    title: 'Change the process'
  });
  insertedActionIds.push(countermeasure.action.id);

  const underACountermeasure = await postMeasure(admin.token, countermeasure.action.id, {
    actionType: 'containment',
    title: 'A second level'
  });
  assert.strictEqual(underACountermeasure.response.status, 400);
  // The same refusal as the containment case, and deliberately the same
  // message: a measure of a measure is impossible because only a Concern may
  // be answered, not because a second check caught it.
  assert.match(underACountermeasure.payload.message, /answers a Concern/);

  const unknown = await postMeasure(admin.token, '99999999', {
    actionType: 'containment',
    title: 'No such concern'
  });
  assert.strictEqual(unknown.response.status, 404);
  // The route resolves the id as an Action before the service sees it, so an
  // unknown one is the same 404 `GET /:id` gives: the caller named a record
  // that does not exist, and which kind it would have been is not knowable.
  assert.strictEqual(unknown.payload.message, 'Action not found');
});

test('a standalone measure answers nothing and closes on its own cycle', async () => {
  const unit = await insertOrgUnit(site.id, { name: 'Floor Unit' });
  const { response, payload } = await postAction(admin.token, site.id, {
    orgUnitId: String(unit.id),
    title: 'Guard refitted on the spot',
    actionType: 'containment'
  });
  assert.strictEqual(response.status, 201);
  const standalone = payload.action;
  insertedActionIds.push(standalone.id);

  assert.strictEqual(standalone.parentId, null);
  const detail = await getAction(admin.token, standalone.id);
  assert.strictEqual(detail.payload.action.parent, null);
  assert.deepStrictEqual(detail.payload.action.measures, []);

  await completePhase(admin.token, standalone.id, 'plan', { note: 'Fit the new guard' });
  await completePhase(admin.token, standalone.id, 'do', { note: 'Fitted' });
  await completePhase(admin.token, standalone.id, 'check', { note: 'Held a fortnight', outcome: 'effective' });
  const closed = await completePhase(admin.token, standalone.id, 'act', { note: 'Guard is the standard now' });
  assert.strictEqual(closed.payload.action.status, 'done');
});

test('a measure names the Concern it answers, without repeating that Concern', async () => {
  const { concern } = await raiseConcern('Motor overheats');
  const { payload } = await postMeasure(admin.token, concern.id, {
    actionType: 'countermeasure',
    title: 'Re-rate the motor'
  });
  insertedActionIds.push(payload.action.id);

  const detail = await getAction(admin.token, payload.action.id);
  assert.deepStrictEqual(detail.payload.action.parent, {
    id: String(concern.id),
    actionNo: concern.actionNo,
    title: 'Motor overheats',
    actionType: 'concern',
    status: 'open'
  });
  // A measure's own detail carries no measures: the one-level rule, read back.
  assert.deepStrictEqual(detail.payload.action.measures, []);
});

test('the register counts the measures each Action is answered by', async () => {
  const fresh = await insertSite({ name: 'Counts Site' });
  const unit = await insertOrgUnit(fresh.id);
  const { rows: [concern] } = await pool.query(
    `INSERT INTO action_items (action_no, org_unit_id, title, action_type)
     VALUES ($1, $2, 'Counted concern', 'concern') RETURNING id`,
    [uniqueCode('AC-'), unit.id]
  );
  insertedActionIds.push(concern.id);
  const { rows: [containment, countermeasure] } = await pool.query(
    `INSERT INTO action_items (action_no, org_unit_id, title, action_type, parent_action_item_id)
     VALUES ($1, $2, 'Counted containment', 'containment', $3),
            ($4, $2, 'Counted countermeasure', 'countermeasure', $3)
     RETURNING id`,
    [uniqueCode('AC-'), unit.id, concern.id, uniqueCode('AC-')]
  );
  insertedActionIds.push(containment.id, countermeasure.id);

  const { payload } = await getRegister(admin.token, fresh.id);
  // A measure is an Action too, so it is a row on the register as well as a
  // count on its concern — which is what a supervisor's list is for.
  assert.strictEqual(payload.actions.length, 3);
  const row = payload.actions.find((action) => action.id === String(concern.id));
  assert.strictEqual(row.measureCount, 2);
  assert.strictEqual(row.countermeasureCount, 1);
});

// ---------------------------------------------------------------------------
// Nothing closes a Concern unproven (issue #179).
// ---------------------------------------------------------------------------

async function postCancel(token, actionId, body) {
  const response = await fetch(`${base}/api/actions/${actionId}/cancel`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body ?? {})
  });
  const payload = await response.json().catch(() => null);
  return { response, payload };
}

// Walks one Action through a whole effective cycle, so a test can start from a
// Concern whose Act is the only step left.
async function driveToAct(token, actionId) {
  await completePhase(token, actionId, 'plan', { note: 'Planned' });
  await completePhase(token, actionId, 'do', { note: 'Done' });
  await completePhase(token, actionId, 'check', { note: 'It held', outcome: 'effective' });
}

test('a Concern with no countermeasure cannot be closed', async () => {
  const { concern } = await raiseConcern('Nobody has answered this');
  await driveToAct(admin.token, concern.id);

  const refused = await completePhase(admin.token, concern.id, 'act', { note: 'Closing anyway' });
  assert.strictEqual(refused.response.status, 409);
  assert.match(refused.payload.message, /no countermeasure that held/);

  // A containment alone is not a fix: it was contained, never answered. It is
  // closed properly first, so that what refuses the Concern is the *absence of
  // a countermeasure* rather than the containment still being outstanding.
  const { payload: containment } = await postMeasure(admin.token, concern.id, {
    actionType: 'containment',
    title: 'Clamp it for now'
  });
  insertedActionIds.push(containment.action.id);
  await driveToAct(admin.token, containment.action.id);
  await completePhase(admin.token, containment.action.id, 'act', {
    note: 'Clamp is the working standard for now'
  });

  const stillRefused = await completePhase(admin.token, concern.id, 'act', { note: 'Closing anyway' });
  assert.strictEqual(stillRefused.response.status, 409);
  assert.match(stillRefused.payload.message, /no countermeasure that held/);
});

test('a Concern whose countermeasure is still being worked cannot be closed', async () => {
  const { concern } = await raiseConcern('The fix is half done');
  await driveToAct(admin.token, concern.id);

  const { payload: countermeasure } = await postMeasure(admin.token, concern.id, {
    actionType: 'countermeasure',
    title: 'Re-rate the motor'
  });
  insertedActionIds.push(countermeasure.action.id);

  const refused = await completePhase(admin.token, concern.id, 'act', { note: 'Closing anyway' });
  assert.strictEqual(refused.response.status, 409);
  assert.match(refused.payload.message, /1 open measure/);
  assert.match(refused.payload.message, new RegExp(countermeasure.action.actionNo));
  // The numbers, and then what to do about them (issue #183): a measure is an
  // Action of its own and nothing on the Screen said so.
  assert.match(refused.payload.message, /A measure closes when its own cycle reaches its Act/);

  // Closing the countermeasure properly is what unblocks the Concern.
  await driveToAct(admin.token, countermeasure.action.id);
  await completePhase(admin.token, countermeasure.action.id, 'act', { note: 'Standard updated' });

  const closed = await completePhase(admin.token, concern.id, 'act', {
    note: 'The fix is the standard now'
  });
  assert.strictEqual(closed.response.status, 200);
  assert.strictEqual(closed.payload.action.status, 'done');
  assert.strictEqual(closed.payload.action.measureCount, 1);
  assert.strictEqual(closed.payload.action.countermeasureCount, 1);
});

test('a measure own Act is not held to the Concern rules: a containment closes alone', async () => {
  const { concern } = await raiseConcern('Contained and closed, cause untouched');
  const { payload: containment } = await postMeasure(admin.token, concern.id, {
    actionType: 'containment',
    title: 'Clamp the guard'
  });
  insertedActionIds.push(containment.action.id);

  await driveToAct(admin.token, containment.action.id);
  const closed = await completePhase(admin.token, containment.action.id, 'act', {
    note: 'Clamp is the working standard until the cause is found'
  });
  assert.strictEqual(closed.response.status, 200);
  assert.strictEqual(closed.payload.action.status, 'done');
});

test('cancelling writes the status, the timestamp and an optional reason', async () => {
  const { concern } = await raiseConcern('Raised about the wrong machine');

  const noReason = await postCancel(admin.token, concern.id);
  assert.strictEqual(noReason.response.status, 200);
  assert.strictEqual(noReason.payload.action.status, 'cancelled');
  assert.ok(noReason.payload.action.completedAt);
  assert.strictEqual(noReason.payload.action.closureNote, null);

  const { concern: other } = await raiseConcern('Also wrong');
  const withReason = await postCancel(admin.token, other.id, { reason: 'Duplicate of the other one' });
  assert.strictEqual(withReason.response.status, 200);
  assert.strictEqual(withReason.payload.action.closureNote, 'Duplicate of the other one');

  // A second cancel is refused rather than a no-op, and a cancelled Action
  // refuses every phase afterwards.
  const again = await postCancel(admin.token, other.id);
  assert.strictEqual(again.response.status, 409);
  assert.match(again.payload.message, /already cancelled/);

  const advanced = await completePhase(admin.token, other.id, 'plan', { note: 'Too late' });
  assert.strictEqual(advanced.response.status, 409);
  assert.match(advanced.payload.message, /was cancelled/);

  // A closed Action cannot be cancelled either.
  const { concern: closing } = await raiseConcern('Properly closed');
  const { payload: fix } = await postMeasure(admin.token, closing.id, {
    actionType: 'countermeasure',
    title: 'The real fix'
  });
  insertedActionIds.push(fix.action.id);
  await driveToAct(admin.token, fix.action.id);
  await completePhase(admin.token, fix.action.id, 'act', { note: 'Standard' });
  await driveToAct(admin.token, closing.id);
  await completePhase(admin.token, closing.id, 'act', { note: 'Closed on proof' });

  const cancelClosed = await postCancel(admin.token, closing.id, { reason: 'Too late' });
  assert.strictEqual(cancelClosed.response.status, 409);
  assert.match(cancelClosed.payload.message, /closed/);
});

test('a Concern whose measures are still open cannot be called off', async () => {
  const { concern } = await raiseConcern('Somebody is halfway through this');
  const { payload: containment } = await postMeasure(admin.token, concern.id, {
    actionType: 'containment',
    title: 'Half-fitted clamp'
  });
  insertedActionIds.push(containment.action.id);

  const refused = await postCancel(admin.token, concern.id, { reason: 'Never mind' });
  assert.strictEqual(refused.response.status, 409);
  assert.match(refused.payload.message, /1 open measure/);
  // Calling a Concern off has a different way out, and the message says which.
  assert.match(refused.payload.message, /Run each one to its Act, or cancel it/);

  // Cancelling the measure is what makes the Concern cancellable.
  const cancelled = await postCancel(admin.token, containment.action.id, { reason: 'Overtaken' });
  assert.strictEqual(cancelled.response.status, 200);

  const thenConcern = await postCancel(admin.token, concern.id, { reason: 'Never mind' });
  assert.strictEqual(thenConcern.response.status, 200);
  assert.strictEqual(thenConcern.payload.action.status, 'cancelled');
});

test('cancelling needs a write Grant, and an unknown Action is a 404', async () => {
  const { concern } = await raiseConcern('Raised by a reader and cancelled by the line');
  const { rows: [row] } = await pool.query(
    'SELECT org_unit_id FROM action_items WHERE id = $1',
    [concern.id]
  );
  // The reader's own concern sits at an Org Unit they may read, not write.
  const readOnlyConcern = await insertAction(row.org_unit_id, { title: 'Also out of reach' });

  const refused = await postCancel(readOnlyAccount.token, readOnlyConcern.id);
  assert.strictEqual(refused.response.status, 403);
  assert.strictEqual(refused.payload.message, "Outside the caller's granted Org Units");

  const allowed = await postCancel(admin.token, readOnlyConcern.id);
  assert.strictEqual(allowed.response.status, 200);

  const unknown = await postCancel(admin.token, '99999999');
  assert.strictEqual(unknown.response.status, 404);

  const malformed = await postCancel(admin.token, 'not-an-id');
  assert.strictEqual(malformed.response.status, 404);

  const badReason = await postCancel(admin.token, concern.id, { reason: 42 });
  assert.strictEqual(badReason.response.status, 400);
});

// ---------------------------------------------------------------------------
// Handing a Concern up the tree (issue #180).
// ---------------------------------------------------------------------------

async function getEscalationTargets(token, actionId) {
  const response = await fetch(`${base}/api/actions/${actionId}/escalation-targets`, {
    headers: token
  });
  const payload = await response.json().catch(() => null);
  return { response, payload };
}

async function postEscalate(token, actionId, body) {
  const response = await fetch(`${base}/api/actions/${actionId}/escalate`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body ?? {})
  });
  const payload = await response.json().catch(() => null);
  return { response, payload };
}

// A Concern at the bottom of the fixture's own tree: grantedArea -> grantedLine
// -> subLine, so "above" has two answers and they have an order.
async function raiseDeepConcern(title = 'This needs an area decision') {
  const { response, payload } = await postAction(admin.token, site.id, {
    orgUnitId: String(subLine.id),
    title
  });
  assert.strictEqual(response.status, 201);
  insertedActionIds.push(payload.action.id);
  return payload.action;
}

test('the targets are the Org Units above, nearest first, and never the own one', async () => {
  const concern = await raiseDeepConcern('Who is going to answer this?');

  const { response, payload } = await getEscalationTargets(admin.token, concern.id);
  assert.strictEqual(response.status, 200);
  assert.deepStrictEqual(
    payload.targets.map((target) => target.id),
    [String(grantedLine.id), String(grantedArea.id)]
  );
  // Named well enough to choose between them without a second read.
  assert.strictEqual(payload.targets[0].name, 'Line 1');
  assert.ok(payload.targets[0].code);

  // An Action at the top of the tree has nowhere to go, and that is an empty
  // list rather than an error: there is nothing wrong with the question.
  const { payload: topConcern } = await postAction(admin.token, site.id, {
    orgUnitId: String(grantedArea.id),
    title: 'Already as high as it gets'
  });
  insertedActionIds.push(topConcern.action.id);
  const top = await getEscalationTargets(admin.token, topConcern.action.id);
  assert.deepStrictEqual(top.payload.targets, []);
});

test('escalating records who was told and changes nothing else about the Action', async () => {
  const concern = await raiseDeepConcern('The line cannot decide this one');
  const before = await getAction(admin.token, concern.id);
  assert.strictEqual(before.payload.action.escalatedToOrgUnitId, null);

  const { response, payload } = await postEscalate(admin.token, concern.id, {
    orgUnitId: String(grantedLine.id)
  });
  assert.strictEqual(response.status, 200);
  const action = payload.action;

  assert.strictEqual(action.escalatedToOrgUnitId, String(grantedLine.id));
  assert.strictEqual(action.escalatedToOrgUnitName, 'Line 1');
  assert.ok(action.escalatedAt);

  // Not a handover: the same status, the same open phase, the same owner, the
  // same cycle. Who has been told is a different question from who is doing it.
  assert.strictEqual(action.status, before.payload.action.status);
  assert.strictEqual(action.ownerEmployeeId, before.payload.action.ownerEmployeeId);
  assert.deepStrictEqual(action.openPhase, before.payload.action.openPhase);
  assert.strictEqual(action.phases.length, before.payload.action.phases.length);
  assert.strictEqual(action.closedAt, before.payload.action.closedAt);

  // The detail read agrees, and the Org Unit it is now at is no longer offered.
  const after = await getAction(admin.token, concern.id);
  assert.strictEqual(after.payload.action.escalatedToOrgUnitName, 'Line 1');
  const targets = await getEscalationTargets(admin.token, concern.id);
  assert.deepStrictEqual(
    targets.payload.targets.map((target) => target.id),
    [String(grantedArea.id)]
  );
});

test('escalating again replaces the one before it rather than accumulating', async () => {
  const concern = await raiseDeepConcern('It went up twice');

  await postEscalate(admin.token, concern.id, { orgUnitId: String(grantedLine.id) });
  const { response, payload } = await postEscalate(admin.token, concern.id, {
    orgUnitId: String(grantedArea.id)
  });
  assert.strictEqual(response.status, 200);
  assert.strictEqual(payload.action.escalatedToOrgUnitId, String(grantedArea.id));
  assert.strictEqual(payload.action.escalatedToOrgUnitName, 'Granted Area');

  // One row, one answer: there is no list of places it has been, so the only
  // trace of the first escalation is that its target is no longer offered —
  // what is above the Action is Line 1 and Granted Area, and it now sits at
  // Granted Area.
  const targets = await getEscalationTargets(admin.token, concern.id);
  assert.deepStrictEqual(
    targets.payload.targets.map((target) => target.id),
    [String(grantedLine.id)]
  );
});

test('an escalation needs a write Grant at the Org Unit it is handed up to', async () => {
  // The area holds a write Grant on grantedArea, and the Action sits two levels
  // below it: handing it up to the area is within the caller's own authority.
  const { response: raised, payload: raisedPayload } = await postAction(areaWriter.token, site.id, {
    orgUnitId: String(grantedLine.id),
    title: 'Raised by the area for the area'
  });
  assert.strictEqual(raised.status, 201);
  const concern = raisedPayload.action;
  insertedActionIds.push(concern.id);

  const allowed = await postEscalate(areaWriter.token, concern.id, {
    orgUnitId: String(grantedArea.id)
  });
  assert.strictEqual(allowed.response.status, 200);
  assert.strictEqual(allowed.payload.action.escalatedToOrgUnitId, String(grantedArea.id));

  // The line's own writer holds write on grantedLine and nothing above it: the
  // work may be theirs to do, but handing it to the area is not theirs to say.
  const { response: lineRaised, payload: linePayload } = await postAction(
    writerAccount.token,
    site.id,
    {
      orgUnitId: String(grantedLine.id),
      title: 'The line wants this decided upstairs'
    }
  );
  assert.strictEqual(lineRaised.status, 201);
  const lineConcern = linePayload.action;
  insertedActionIds.push(lineConcern.id);

  const refused = await postEscalate(writerAccount.token, lineConcern.id, {
    orgUnitId: String(grantedArea.id)
  });
  assert.strictEqual(refused.response.status, 403);
  assert.strictEqual(refused.payload.message, "Outside the caller's granted Org Units");
});

test('the four refusals come back in the order the decision fixed', async () => {
  const concern = await raiseDeepConcern('Refused in four ways');

  // An Org Unit below the Action: wrong about the tree, which is a 400 and not
  // a 403 — the caller may well be allowed to act there, that is not the point.
  const below = await postEscalate(admin.token, concern.id, {
    orgUnitId: String(subLine.id)
  });
  assert.strictEqual(below.response.status, 400);
  assert.strictEqual(below.payload.message, "orgUnitId must be an Org Unit above this Action's own");

  const own = await postEscalate(admin.token, concern.id, { orgUnitId: String(concern.orgUnitId) });
  assert.strictEqual(own.response.status, 400);

  const sibling = await postEscalate(admin.token, concern.id, {
    orgUnitId: String(otherLine.id)
  });
  assert.strictEqual(sibling.response.status, 400);

  const malformedBody = await postEscalate(admin.token, concern.id, { orgUnitId: 'abc' });
  assert.strictEqual(malformedBody.response.status, 400);
  assert.strictEqual(malformedBody.payload.message, 'orgUnitId must be a valid Org Unit id');

  const missingBody = await postEscalate(admin.token, concern.id, {});
  assert.strictEqual(missingBody.response.status, 400);

  const unknownOrgUnit = await postEscalate(admin.token, concern.id, { orgUnitId: '99999999' });
  assert.strictEqual(unknownOrgUnit.response.status, 400);

  // An Action that has ended has nothing left to hand up, whatever the target.
  const { concern: endedConcern } = await raiseConcern('Called off before anyone was told');
  const cancelled = await postCancel(admin.token, endedConcern.id, { reason: 'Wrong machine' });
  assert.strictEqual(cancelled.response.status, 200);
  const ended = await postEscalate(admin.token, endedConcern.id, {
    orgUnitId: String(grantedLine.id)
  });
  assert.strictEqual(ended.response.status, 409);
  assert.match(ended.payload.message, /has ended/);

  // Existence beats everything: an id that is not an Action is a 404 whether or
  // not the caller holds anything.
  const unknown = await postEscalate(admin.token, '99999999', {
    orgUnitId: String(grantedLine.id)
  });
  assert.strictEqual(unknown.response.status, 404);
  const garbage = await postEscalate(noGrantAccount.token, 'not-an-id', {
    orgUnitId: String(grantedLine.id)
  });
  assert.strictEqual(garbage.response.status, 404);

  const noGrant = await postEscalate(noGrantAccount.token, concern.id, {
    orgUnitId: String(grantedLine.id)
  });
  assert.strictEqual(noGrant.response.status, 403);

  const readOnly = await postEscalate(readOnlyAccount.token, concern.id, {
    orgUnitId: String(grantedLine.id)
  });
  assert.strictEqual(readOnly.response.status, 403);
});

test('the register can be narrowed to what was handed up to one Org Unit', async () => {
  const escalated = await raiseDeepConcern('Handed up to the line');
  const lonely = await raiseDeepConcern('Nobody has been told about this one');

  await postEscalate(admin.token, escalated.id, { orgUnitId: String(grantedLine.id) });

  const { response, payload } = await getRegister(
    admin.token,
    site.id,
    `?escalatedToOrgUnitId=${grantedLine.id}`
  );
  assert.strictEqual(response.status, 200);
  const ids = payload.actions.map((action) => action.id);
  assert.ok(ids.includes(escalated.id));
  assert.ok(!ids.includes(lonely.id));

  // A target nobody's work sits at is an empty answer, not an error. (An Org
  // Unit of its own: earlier tests in this file have already left Actions
  // escalated to the fixture's areas, and a Site-wide register is a Site-wide
  // register.)
  const quietArea = await insertOrgUnit(site.id, { name: 'Quiet Area' });
  const empty = await getRegister(
    admin.token,
    site.id,
    `?escalatedToOrgUnitId=${quietArea.id}`
  );
  assert.deepStrictEqual(empty.payload.actions, []);

  const garbage = await getRegister(admin.token, site.id, '?escalatedToOrgUnitId=abc');
  assert.strictEqual(garbage.response.status, 400);
  assert.strictEqual(garbage.payload.message, 'escalatedToOrgUnitId must be a valid id');
});
