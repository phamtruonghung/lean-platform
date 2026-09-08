/*
 * Work orders over HTTP (issue #57), against a real database and a real
 * (locally issued) JWKS — the same seam as assets.test.js, whose fixture
 * scaffolding this file mirrors closely. Assets are inserted directly
 * against the database rather than through POST /assets: this file is about
 * work orders, and the Asset register is already covered by assets.test.js.
 */

const test = require('node:test');
const assert = require('node:assert');
const { createTestJwks } = require('../helpers/jwks');
const skillFixtures = require('../helpers/skills');

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
const insertedAssetIds = [];
const insertedWorkOrderIds = [];
const insertedEmployeeIds = [];
const insertedSkillIds = [];
const insertedEmployeeSkillIds = [];

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

async function insertAccount({ role = 'supervisor', isActive = true, approvalStatus = 'approved' } = {}) {
  const subject = uniqueCode('acct');
  const { rows: [row] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status)
     VALUES ($1, 'Work Order Test Account', $2, $3, $4, $5) RETURNING id`,
    [`${subject}@example.com`, role, subject, isActive, approvalStatus]
  );
  insertedAccountIds.push(row.id);
  return { id: row.id, token: await authHeader(subject) };
}

async function insertSite() {
  const { rows: [row] } = await pool.query(
    `INSERT INTO sites (code, name, timezone) VALUES ($1, 'Work Order Test Site', 'Asia/Ho_Chi_Minh') RETURNING id, code`,
    [uniqueCode('ST')]
  );
  insertedSiteIds.push(row.id);
  return row;
}

async function insertOrgUnit(siteId, { parentId = null, unitType = 'area', name = 'Work Order Test Unit' } = {}) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, $2, $3, $4, $5) RETURNING id, code, name`,
    [siteId, parentId, uniqueCode('OU'), name, unitType]
  );
  insertedOrgUnitIds.push(row.id);
  return row;
}

async function insertGrant({ accountId, orgUnitId, canWrite = false }) {
  await pool.query(
    `INSERT INTO app_user_org_units (app_user_id, org_unit_id, can_write) VALUES ($1, $2, $3)`,
    [accountId, orgUnitId, canWrite]
  );
}

async function insertAsset(orgUnitId, { name = 'Press 1' } = {}) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO assets (org_unit_id, code, name, asset_type, criticality)
     VALUES ($1, $2, $3, 'machine', 'high') RETURNING id, org_unit_id`,
    [orgUnitId, uniqueCode('AS'), name]
  );
  insertedAssetIds.push(row.id);
  return row;
}

// displayName is split into first/last name here, not stored directly:
// employees.display_name is GENERATED ALWAYS AS (first_name || ' ' ||
// last_name) STORED (baseline migration), so the round trip through the two
// real columns is what makes the returned display_name match what a test
// passed in.
async function insertEmployee({ isActive = true, displayName = 'Assignee Test' } = {}) {
  const [firstName, ...rest] = displayName.split(' ');
  const lastName = rest.join(' ') || 'Employee';
  const { rows: [row] } = await pool.query(
    `INSERT INTO employees (employee_no, first_name, last_name, is_active)
     VALUES ($1, $2, $3, $4) RETURNING id, display_name`,
    [uniqueCode('EMP'), firstName, lastName, isActive]
  );
  insertedEmployeeIds.push(row.id);
  return row;
}

// Thin wrappers over the shared fixtures in test/helpers/skills.js: this
// file's own tracking (insertedSkillIds/insertedEmployeeSkillIds) and
// skill-name convention live here, the SQL itself lives there, shared with
// directory.test.js.
async function insertSkill({ revalidationMonths = null } = {}) {
  const row = await skillFixtures.insertSkill(pool, uniqueCode, {
    name: 'Work Order Test Skill',
    revalidationMonths
  });
  insertedSkillIds.push(row.id);
  return row;
}

async function insertEmployeeSkill({ employeeId, skillId, assessedOn, expiresOn }) {
  const id = await skillFixtures.insertEmployeeSkill(pool, { employeeId, skillId, assessedOn, expiresOn });
  insertedEmployeeSkillIds.push(id);
  return id;
}

async function putAssignee(token, workOrderId, body) {
  const response = await fetch(`${base}/api/maintenance/work-orders/${workOrderId}/assignee`, {
    method: 'PUT',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  const payload = await response.json().catch(() => null);
  return { response, payload };
}

async function postWorkOrder(token, body) {
  const response = await fetch(`${base}/api/maintenance/work-orders`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  const payload = await response.json().catch(() => null);
  if (payload?.workOrder?.id) insertedWorkOrderIds.push(payload.workOrder.id);
  return { response, payload };
}

function workOrderBody(assetId, overrides = {}) {
  return {
    assetId,
    summary: 'Bearing is making noise',
    workType: 'corrective',
    priority: 3,
    ...overrides
  };
}

async function getWorkOrders(token, siteId, query = '') {
  const response = await fetch(`${base}/api/maintenance/sites/${siteId}/work-orders${query}`, {
    headers: token
  });
  const payload = await response.json().catch(() => null);
  return { response, payload };
}

let admin;
let noGrantAccount;   // approved, no Grant anywhere at all.
let readOnlyAccount;  // read Grant on grantedLine.
let writerAccount;    // write Grant on grantedLine.
let siblingWriter;    // write Grant on otherLine only.

let site;
let otherSite;
let grantedArea;
let grantedLine;
let otherLine;

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
  otherSite = await insertSite();
  grantedArea = await insertOrgUnit(site.id, { name: 'Granted Area' });
  grantedLine = await insertOrgUnit(site.id, { parentId: grantedArea.id, unitType: 'line', name: 'Line 1' });
  otherLine = await insertOrgUnit(site.id, { parentId: grantedArea.id, unitType: 'line', name: 'Line 2' });

  await insertGrant({ accountId: readOnlyAccount.id, orgUnitId: grantedLine.id, canWrite: false });
  await insertGrant({ accountId: writerAccount.id, orgUnitId: grantedLine.id, canWrite: true });
  await insertGrant({ accountId: siblingWriter.id, orgUnitId: otherLine.id, canWrite: true });
});

test.after(async () => {
  await pool.query('DELETE FROM work_orders WHERE id = ANY($1)', [insertedWorkOrderIds]);
  await pool.query('DELETE FROM employee_skills WHERE id = ANY($1)', [insertedEmployeeSkillIds]);
  await pool.query('DELETE FROM employees WHERE id = ANY($1)', [insertedEmployeeIds]);
  await pool.query('DELETE FROM skills WHERE id = ANY($1)', [insertedSkillIds]);
  await pool.query('DELETE FROM assets WHERE id = ANY($1)', [insertedAssetIds]);
  await pool.query('DELETE FROM app_user_org_units WHERE app_user_id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM app_users WHERE id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM org_units WHERE id = ANY($1)', [insertedOrgUnitIds]);
  await pool.query('DELETE FROM sites WHERE id = ANY($1)', [insertedSiteIds]);
  await new Promise((resolve) => server.close(resolve));
  await closePool();
  await jwks.close();
});

// ---------------------------------------------------------------------------
// Raising a work order.
// ---------------------------------------------------------------------------

test('raising a work order returns 201, in status approved, carrying the expected fields', async () => {
  const asset = await insertAsset(grantedLine.id);
  const { response, payload } = await postWorkOrder(admin.token, workOrderBody(asset.id));
  assert.strictEqual(response.status, 201);
  assert.strictEqual(payload.workOrder.status, 'approved');
  assert.strictEqual(payload.workOrder.summary, 'Bearing is making noise');
  assert.strictEqual(payload.workOrder.workType, 'corrective');
  assert.strictEqual(payload.workOrder.priority, 3);
  assert.strictEqual(payload.workOrder.assetId, String(asset.id));
  assert.ok(payload.workOrder.workOrderNo);
});

test("the work order's Org Unit is derived from the Asset, not sent — a different orgUnitId in the body is ignored", async () => {
  const asset = await insertAsset(grantedLine.id);
  const { response, payload } = await postWorkOrder(
    admin.token,
    workOrderBody(asset.id, { orgUnitId: otherLine.id })
  );
  assert.strictEqual(response.status, 201);
  assert.strictEqual(payload.workOrder.orgUnitId, String(grantedLine.id));

  const { rows } = await pool.query('SELECT org_unit_id FROM work_orders WHERE id = $1', [payload.workOrder.id]);
  assert.strictEqual(String(rows[0].org_unit_id), String(grantedLine.id));
});

test('naming an Asset that does not exist is refused, with a message naming the Asset', async () => {
  const { response, payload } = await postWorkOrder(admin.token, workOrderBody('999999999'));
  assert.strictEqual(response.status, 404);
  assert.strictEqual(payload.message, 'Asset not found');
});

test('a malformed assetId is also a clean 404, not a 500', async () => {
  const { response } = await postWorkOrder(admin.token, workOrderBody('not-an-id'));
  assert.strictEqual(response.status, 404);
});

test('the number is issued by the Site\'s own sequence, and two Sites number independently', async () => {
  // Fresh Sites, used nowhere else in this file: the 'WO' sequence is scoped
  // by (prefix, Site code, year), so a Site that has never had a work order
  // raised on it is the only honest way to assert the run starts at 00001.
  const freshSiteA = await insertSite();
  const freshSiteB = await insertSite();
  const areaA = await insertOrgUnit(freshSiteA.id, { name: 'Area A' });
  const areaB = await insertOrgUnit(freshSiteB.id, { name: 'Area B' });
  const assetA = await insertAsset(areaA.id);
  const assetB = await insertAsset(areaB.id);

  const a1 = await postWorkOrder(admin.token, workOrderBody(assetA.id));
  const a2 = await postWorkOrder(admin.token, workOrderBody(assetA.id));
  const b1 = await postWorkOrder(admin.token, workOrderBody(assetB.id));
  assert.strictEqual(a1.response.status, 201);
  assert.strictEqual(a2.response.status, 201);
  assert.strictEqual(b1.response.status, 201);

  const year = new Date().getUTCFullYear();
  assert.strictEqual(a1.payload.workOrder.workOrderNo, `WO-${freshSiteA.code}-${year}-00001`);
  assert.strictEqual(a2.payload.workOrder.workOrderNo, `WO-${freshSiteA.code}-${year}-00002`);
  // Site B's run starts at 00001 too, independently of Site A's own count.
  assert.strictEqual(b1.payload.workOrder.workOrderNo, `WO-${freshSiteB.code}-${year}-00001`);
});

test('validation: bad workType, priority out of range, and an empty summary are each a clean 400', async () => {
  const asset = await insertAsset(grantedLine.id);
  for (const overrides of [
    { workType: 'urgent' },
    { priority: 0 },
    { priority: 6 },
    { priority: 1.5 },
    { summary: '   ' }
  ]) {
    const { response } = await postWorkOrder(admin.token, workOrderBody(asset.id, overrides));
    assert.strictEqual(response.status, 400, JSON.stringify(overrides));
  }
});

// ---------------------------------------------------------------------------
// Who may raise one.
// ---------------------------------------------------------------------------

test('a write Grant reaching the Asset\'s Org Unit may raise a work order', async () => {
  const asset = await insertAsset(grantedLine.id);
  const { response } = await postWorkOrder(writerAccount.token, workOrderBody(asset.id));
  assert.strictEqual(response.status, 201);
});

test('a read-only Grant on the Asset\'s Org Unit is refused', async () => {
  const asset = await insertAsset(grantedLine.id);
  const { response, payload } = await postWorkOrder(readOnlyAccount.token, workOrderBody(asset.id));
  assert.strictEqual(response.status, 403);
  assert.strictEqual(payload.message, "Outside the caller's granted Org Units");
});

test('a write Grant on a sibling branch does not reach across', async () => {
  const asset = await insertAsset(grantedLine.id);
  const { response } = await postWorkOrder(siblingWriter.token, workOrderBody(asset.id));
  assert.strictEqual(response.status, 403);
});

test('an approved Account with no Grant anywhere cannot raise a work order', async () => {
  const asset = await insertAsset(grantedLine.id);
  const { response } = await postWorkOrder(noGrantAccount.token, workOrderBody(asset.id));
  assert.strictEqual(response.status, 403);
});

// ---------------------------------------------------------------------------
// Reading: Site-wide, open work orders, whatever the caller's Grants.
// ---------------------------------------------------------------------------

test('a request with no bearer token is refused', async () => {
  const response = await fetch(`${base}/api/maintenance/sites/${site.id}/work-orders`);
  assert.strictEqual(response.status, 401);
});

test('the Site-wide read returns work orders the caller holds no Grant over', async () => {
  const asset = await insertAsset(otherLine.id);
  const created = await postWorkOrder(admin.token, workOrderBody(asset.id, { summary: 'No grant here' }));
  assert.strictEqual(created.response.status, 201);

  const { response, payload } = await getWorkOrders(noGrantAccount.token, site.id);
  assert.strictEqual(response.status, 200);
  assert.ok(payload.workOrders.some((w) => w.id === created.payload.workOrder.id));
});

test('?orgUnitId= narrows to that Org Unit and everything beneath it', async () => {
  const childOrgUnit = await insertOrgUnit(site.id, {
    parentId: grantedLine.id,
    unitType: 'cell',
    name: 'Cell A'
  });
  const childAsset = await insertAsset(childOrgUnit.id);
  const created = await postWorkOrder(admin.token, workOrderBody(childAsset.id, { summary: 'On the cell' }));
  assert.strictEqual(created.response.status, 201);

  const narrowed = await getWorkOrders(admin.token, site.id, `?orgUnitId=${grantedArea.id}`);
  assert.strictEqual(narrowed.response.status, 200);
  assert.ok(narrowed.payload.workOrders.some((w) => w.id === created.payload.workOrder.id));

  // otherLine is a sibling of grantedLine, not beneath it, so a work order
  // raised there does not show up when narrowing to grantedLine itself.
  const otherAsset = await insertAsset(otherLine.id);
  const otherCreated = await postWorkOrder(admin.token, workOrderBody(otherAsset.id, { summary: 'Elsewhere' }));
  const narrowedToLine = await getWorkOrders(admin.token, site.id, `?orgUnitId=${grantedLine.id}`);
  assert.ok(!narrowedToLine.payload.workOrders.some((w) => w.id === otherCreated.payload.workOrder.id));
});

test('an unknown ?orgUnitId= is a 404', async () => {
  const { response, payload } = await getWorkOrders(admin.token, site.id, '?orgUnitId=999999999');
  assert.strictEqual(response.status, 404);
  assert.strictEqual(payload.message, 'Org Unit not found');
});

test('a malformed ?orgUnitId= is a 404, not a 500', async () => {
  const { response } = await getWorkOrders(admin.token, site.id, '?orgUnitId=not-an-id');
  assert.strictEqual(response.status, 404);
});

test('an ?orgUnitId= that exists but belongs to a different Site than the path is a 404, not an empty 200', async () => {
  // otherSite's own Org Unit is real, so findOrgUnit resolves it — the bug
  // this guards against is the SQL filter (ou.site_id = :siteId AND ou.path
  // <@ ...) silently matching nothing instead of the mismatch being reported.
  const otherSiteArea = await insertOrgUnit(otherSite.id, { name: 'Other Site Area' });
  const { response, payload } = await getWorkOrders(admin.token, site.id, `?orgUnitId=${otherSiteArea.id}`);
  assert.strictEqual(response.status, 404);
  assert.strictEqual(payload.message, 'Org Unit not found');
});

test('an unknown Site is a 404, not an empty list', async () => {
  const { response, payload } = await getWorkOrders(admin.token, '999999999');
  assert.strictEqual(response.status, 404);
  assert.strictEqual(payload.message, 'Site not found');
});

test('a completed work order is out of the default open list', async () => {
  const asset = await insertAsset(grantedLine.id);
  const created = await postWorkOrder(admin.token, workOrderBody(asset.id, { summary: 'Will be closed' }));
  assert.strictEqual(created.response.status, 201);

  await pool.query(
    `UPDATE work_orders SET status = 'completed', actual_end = now() WHERE id = $1`,
    [created.payload.workOrder.id]
  );

  const { payload } = await getWorkOrders(admin.token, site.id);
  assert.ok(!payload.workOrders.some((w) => w.id === created.payload.workOrder.id));
});

test('a cancelled work order is also out of the default open list', async () => {
  const asset = await insertAsset(grantedLine.id);
  const created = await postWorkOrder(admin.token, workOrderBody(asset.id, { summary: 'Will be cancelled' }));
  assert.strictEqual(created.response.status, 201);

  await pool.query(`UPDATE work_orders SET status = 'cancelled' WHERE id = $1`, [created.payload.workOrder.id]);

  const { payload } = await getWorkOrders(admin.token, site.id);
  assert.ok(!payload.workOrders.some((w) => w.id === created.payload.workOrder.id));
});

test('a work order in_progress is included in the open list', async () => {
  const asset = await insertAsset(grantedLine.id);
  const created = await postWorkOrder(admin.token, workOrderBody(asset.id, { summary: 'Underway' }));
  assert.strictEqual(created.response.status, 201);

  await pool.query(`UPDATE work_orders SET status = 'in_progress' WHERE id = $1`, [created.payload.workOrder.id]);

  const { payload } = await getWorkOrders(admin.token, site.id);
  assert.ok(payload.workOrders.some((w) => w.id === created.payload.workOrder.id));
});

// ---------------------------------------------------------------------------
// Assigning a work order (issue #62). No skill is ever consulted on this
// write path — ADR-0018 — and neither this file nor work-orders.js reads one.
// ---------------------------------------------------------------------------

test('assigning a work order sets the assignee, and reading the Site list back shows it', async () => {
  const asset = await insertAsset(grantedLine.id);
  const created = await postWorkOrder(admin.token, workOrderBody(asset.id, { summary: 'Assign me' }));
  assert.strictEqual(created.response.status, 201);

  const employee = await insertEmployee({ displayName: 'Ada Assignee' });
  const { response, payload } = await putAssignee(admin.token, created.payload.workOrder.id, {
    employeeId: employee.id
  });
  assert.strictEqual(response.status, 200);
  assert.strictEqual(payload.workOrder.assignedTo, String(employee.id));
  assert.strictEqual(payload.workOrder.assigneeName, employee.display_name);

  const { payload: listPayload } = await getWorkOrders(admin.token, site.id);
  const row = listPayload.workOrders.find((w) => w.id === created.payload.workOrder.id);
  assert.ok(row, 'the assigned work order should still be on the Site list');
  assert.strictEqual(row.assignedTo, String(employee.id));
  assert.strictEqual(row.assigneeName, employee.display_name);
});

test('reassigning replaces the assignee rather than adding one', async () => {
  const asset = await insertAsset(grantedLine.id);
  const created = await postWorkOrder(admin.token, workOrderBody(asset.id, { summary: 'Reassign me' }));

  const first = await insertEmployee({ displayName: 'First Assignee' });
  const second = await insertEmployee({ displayName: 'Second Assignee' });

  await putAssignee(admin.token, created.payload.workOrder.id, { employeeId: first.id });
  const { response, payload } = await putAssignee(admin.token, created.payload.workOrder.id, {
    employeeId: second.id
  });
  assert.strictEqual(response.status, 200);
  assert.strictEqual(payload.workOrder.assignedTo, String(second.id));

  const { rows } = await pool.query('SELECT assigned_to FROM work_orders WHERE id = $1', [
    created.payload.workOrder.id
  ]);
  assert.strictEqual(String(rows[0].assigned_to), String(second.id));
});

test("a write Grant reaching the Asset's Org Unit may assign; a read-only Grant on the same Org Unit is refused", async () => {
  const asset = await insertAsset(grantedLine.id);
  const created = await postWorkOrder(admin.token, workOrderBody(asset.id, { summary: 'Scope check' }));
  const employee = await insertEmployee();

  const writerResult = await putAssignee(writerAccount.token, created.payload.workOrder.id, {
    employeeId: employee.id
  });
  assert.strictEqual(writerResult.response.status, 200);

  const asset2 = await insertAsset(grantedLine.id);
  const created2 = await postWorkOrder(admin.token, workOrderBody(asset2.id, { summary: 'Scope check 2' }));
  const readOnlyResult = await putAssignee(readOnlyAccount.token, created2.payload.workOrder.id, {
    employeeId: employee.id
  });
  assert.strictEqual(readOnlyResult.response.status, 403);
  assert.strictEqual(readOnlyResult.payload.message, "Outside the caller's granted Org Units");

  const { rows } = await pool.query('SELECT assigned_to FROM work_orders WHERE id = $1', [
    created2.payload.workOrder.id
  ]);
  assert.strictEqual(rows[0].assigned_to, null);
});

test('a write Grant on a sibling branch does not reach across', async () => {
  const asset = await insertAsset(grantedLine.id);
  const created = await postWorkOrder(admin.token, workOrderBody(asset.id, { summary: 'Sibling scope' }));
  const employee = await insertEmployee();

  const { response } = await putAssignee(siblingWriter.token, created.payload.workOrder.id, {
    employeeId: employee.id
  });
  assert.strictEqual(response.status, 403);

  const { rows } = await pool.query('SELECT assigned_to FROM work_orders WHERE id = $1', [
    created.payload.workOrder.id
  ]);
  assert.strictEqual(rows[0].assigned_to, null);
});

test('an approved Account with no Grant anywhere cannot assign', async () => {
  const asset = await insertAsset(grantedLine.id);
  const created = await postWorkOrder(admin.token, workOrderBody(asset.id, { summary: 'No grant' }));
  const employee = await insertEmployee();

  const { response } = await putAssignee(noGrantAccount.token, created.payload.workOrder.id, {
    employeeId: employee.id
  });
  assert.strictEqual(response.status, 403);
});

test('an Employee holding only a lapsed qualification can still be assigned', async () => {
  const asset = await insertAsset(grantedLine.id);
  const created = await postWorkOrder(admin.token, workOrderBody(asset.id, { summary: 'Lapsed qualification' }));

  const employee = await insertEmployee({ displayName: 'Lapsed Holder' });
  const skill = await insertSkill();
  await insertEmployeeSkill({
    employeeId: employee.id,
    skillId: skill.id,
    assessedOn: '2020-01-01',
    expiresOn: '2021-01-01'
  });

  const { response, payload } = await putAssignee(admin.token, created.payload.workOrder.id, {
    employeeId: employee.id
  });
  assert.strictEqual(response.status, 200);
  assert.strictEqual(payload.workOrder.assignedTo, String(employee.id));
});

test('an unknown work order id is a 404 naming the Work order, checked before scope', async () => {
  const employee = await insertEmployee();
  // admin: canAct would pass this caller unconditionally, so a 404 here
  // proves existence is checked before scope, not the other way round.
  const { response, payload } = await putAssignee(admin.token, '999999999', { employeeId: employee.id });
  assert.strictEqual(response.status, 404);
  assert.strictEqual(payload.message, 'Work order not found');
});

test('a malformed work order id is a clean 404, not a 500', async () => {
  const employee = await insertEmployee();
  const { response } = await putAssignee(admin.token, 'not-an-id', { employeeId: employee.id });
  assert.strictEqual(response.status, 404);
});

test('a missing or malformed employeeId is a clean 400', async () => {
  const asset = await insertAsset(grantedLine.id);
  const created = await postWorkOrder(admin.token, workOrderBody(asset.id, { summary: 'Bad employeeId' }));

  for (const body of [{}, { employeeId: null }, { employeeId: 'not-an-id' }]) {
    const { response, payload } = await putAssignee(admin.token, created.payload.workOrder.id, body);
    assert.strictEqual(response.status, 400, JSON.stringify(body));
    assert.strictEqual(payload.message, 'employeeId must be a valid Employee id');
  }
});

test('an unknown Employee is a 404 naming the Employee', async () => {
  const asset = await insertAsset(grantedLine.id);
  const created = await postWorkOrder(admin.token, workOrderBody(asset.id, { summary: 'Unknown employee' }));

  const { response, payload } = await putAssignee(admin.token, created.payload.workOrder.id, {
    employeeId: '999999999'
  });
  assert.strictEqual(response.status, 404);
  assert.strictEqual(payload.message, 'Employee not found');
});

test('a Departed Employee cannot be assigned a work order', async () => {
  const asset = await insertAsset(grantedLine.id);
  const created = await postWorkOrder(admin.token, workOrderBody(asset.id, { summary: 'Departed employee' }));
  const departed = await insertEmployee({ displayName: 'Departed Person', isActive: false });

  const { response, payload } = await putAssignee(admin.token, created.payload.workOrder.id, {
    employeeId: departed.id
  });
  assert.strictEqual(response.status, 409);
  assert.strictEqual(payload.message, 'this Employee has departed and cannot be assigned');
});

test('a request with no bearer token is refused', async () => {
  const asset = await insertAsset(grantedLine.id);
  const created = await postWorkOrder(admin.token, workOrderBody(asset.id, { summary: 'No token' }));
  const employee = await insertEmployee();

  const response = await fetch(`${base}/api/maintenance/work-orders/${created.payload.workOrder.id}/assignee`, {
    method: 'PUT',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ employeeId: employee.id })
  });
  assert.strictEqual(response.status, 401);
});
