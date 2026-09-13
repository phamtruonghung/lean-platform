/*
 * Breakdowns and downtime over HTTP (issue #73), against a real database and a
 * real (locally issued) JWKS — the same seam as work-orders.test.js and
 * maintenance-requests.test.js, whose fixture scaffolding this file mirrors
 * closely. Assets, Accounts and Employees are inserted directly against the
 * database rather than through their own endpoints: this file is about
 * downtime, and the Asset register and the Approval flow are already covered
 * by their own files.
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
const insertedEmployeeIds = [];
const insertedSiteIds = [];
const insertedOrgUnitIds = [];
const insertedAssetIds = [];
const insertedDowntimeIds = [];
const insertedWorkOrderIds = [];

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

async function insertAccount({
  role = 'supervisor',
  isActive = true,
  approvalStatus = 'approved',
  employeeId = null
} = {}) {
  const subject = uniqueCode('acct');
  const { rows: [row] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status, employee_id)
     VALUES ($1, 'Downtime Test Account', $2, $3, $4, $5, $6) RETURNING id`,
    [`${subject}@example.com`, role, subject, isActive, approvalStatus, employeeId]
  );
  insertedAccountIds.push(row.id);
  return { id: row.id, token: await authHeader(subject) };
}

// display_name is GENERATED ALWAYS as first_name || ' ' || last_name, so the
// round trip through the two real columns is what makes the returned name
// match what a test passed in.
async function insertEmployee({ isActive = true, displayName = 'Downtime Reporter' } = {}) {
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

async function insertSite() {
  const { rows: [row] } = await pool.query(
    `INSERT INTO sites (code, name, timezone) VALUES ($1, 'Downtime Test Site', 'Asia/Ho_Chi_Minh') RETURNING id, code`,
    [uniqueCode('ST')]
  );
  insertedSiteIds.push(row.id);
  return row;
}

async function insertOrgUnit(siteId, { parentId = null, unitType = 'area', name = 'Downtime Test Unit' } = {}) {
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
     VALUES ($1, $2, $3, 'machine', 'high') RETURNING id, org_unit_id, code, name`,
    [orgUnitId, uniqueCode('AS'), name]
  );
  insertedAssetIds.push(row.id);
  return row;
}

function breakdownBody(assetId, overrides = {}) {
  return { assetId, ...overrides };
}

// Reports a Breakdown. Both rows the one call produces are tracked for
// cleanup from the response, which is the only place a test learns their ids.
async function postDowntime(token, body) {
  const response = await fetch(`${base}/api/maintenance/downtime`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  const payload = await response.json().catch(() => null);
  if (payload?.downtimeEvent?.id) insertedDowntimeIds.push(payload.downtimeEvent.id);
  if (payload?.workOrder?.id) insertedWorkOrderIds.push(payload.workOrder.id);
  return { response, payload };
}

async function getDowntime(token, siteId, query = '') {
  const response = await fetch(`${base}/api/maintenance/sites/${siteId}/downtime${query}`, {
    headers: token
  });
  const payload = await response.json().catch(() => null);
  return { response, payload };
}

async function getDowntimeReasons(token) {
  const response = await fetch(`${base}/api/maintenance/downtime-reasons`, { headers: token });
  const payload = await response.json().catch(() => null);
  return { response, payload };
}

async function closeDowntime(token, id, body) {
  const response = await fetch(`${base}/api/maintenance/downtime/${id}/close`, {
    method: 'POST',
    headers: body === undefined ? token : { ...token, 'content-type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body)
  });
  const payload = await response.json().catch(() => null);
  return { response, payload };
}

async function classifyDowntime(token, id, body) {
  const response = await fetch(`${base}/api/maintenance/downtime/${id}/classify`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  const payload = await response.json().catch(() => null);
  return { response, payload };
}

async function downtimeReasonByCode(code) {
  const { rows: [row] } = await pool.query(
    'SELECT id, code, name, requires_comment FROM downtime_reasons WHERE code = $1',
    [code]
  );
  return row;
}

async function countDowntimeForAsset(assetId) {
  const { rows } = await pool.query('SELECT count(*)::int AS n FROM downtime_events WHERE asset_id = $1', [assetId]);
  return rows[0].n;
}

async function countWorkOrdersForAsset(assetId) {
  const { rows } = await pool.query('SELECT count(*)::int AS n FROM work_orders WHERE asset_id = $1', [assetId]);
  return rows[0].n;
}

let admin;
let noGrantAccount;   // approved, no Grant anywhere at all.
let readOnlyAccount;  // read Grant on grantedLine.
let writerAccount;    // write Grant on grantedLine.
let siblingWriter;    // write Grant on otherLine only.

let reporterEmployee;
let reporterAccount;  // write Grant on grantedLine, linked to reporterEmployee.
let classifierEmployee;
let classifierAccount; // write Grant on grantedLine, linked to classifierEmployee.
let noEmployeeAccount; // write Grant on grantedLine, linked to no Employee at all.

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

  reporterEmployee = await insertEmployee({ displayName: 'Reporting Operator' });
  reporterAccount = await insertAccount({ employeeId: reporterEmployee.id });
  classifierEmployee = await insertEmployee({ displayName: 'Classifying Planner' });
  classifierAccount = await insertAccount({ employeeId: classifierEmployee.id });
  noEmployeeAccount = await insertAccount();

  site = await insertSite();
  otherSite = await insertSite();
  grantedArea = await insertOrgUnit(site.id, { name: 'Granted Area' });
  grantedLine = await insertOrgUnit(site.id, { parentId: grantedArea.id, unitType: 'line', name: 'Line 1' });
  otherLine = await insertOrgUnit(site.id, { parentId: grantedArea.id, unitType: 'line', name: 'Line 2' });

  await insertGrant({ accountId: readOnlyAccount.id, orgUnitId: grantedLine.id, canWrite: false });
  await insertGrant({ accountId: writerAccount.id, orgUnitId: grantedLine.id, canWrite: true });
  await insertGrant({ accountId: siblingWriter.id, orgUnitId: otherLine.id, canWrite: true });
  await insertGrant({ accountId: reporterAccount.id, orgUnitId: grantedLine.id, canWrite: true });
  await insertGrant({ accountId: classifierAccount.id, orgUnitId: grantedLine.id, canWrite: true });
  await insertGrant({ accountId: noEmployeeAccount.id, orgUnitId: grantedLine.id, canWrite: true });
});

test.after(async () => {
  await pool.query(
    'DELETE FROM work_orders WHERE id = ANY($1) OR downtime_event_id = ANY($2)',
    [insertedWorkOrderIds, insertedDowntimeIds]
  );
  await pool.query('DELETE FROM downtime_events WHERE id = ANY($1)', [insertedDowntimeIds]);
  await pool.query('DELETE FROM assets WHERE id = ANY($1)', [insertedAssetIds]);
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
// The classify picker's catalogue.
// ---------------------------------------------------------------------------

test('the downtime reasons listing returns active reasons in the catalogue\'s own order, with every field', async () => {
  const { response, payload } = await getDowntimeReasons(reporterAccount.token);
  assert.strictEqual(response.status, 200);
  assert.ok(Array.isArray(payload.downtimeReasons));
  assert.ok(payload.downtimeReasons.length > 0);

  for (const reason of payload.downtimeReasons) {
    assert.ok(reason.id);
    assert.ok(reason.code);
    assert.ok(reason.name);
    assert.ok(reason.lossCategory);
    assert.strictEqual(typeof reason.isPlanned, 'boolean');
    assert.strictEqual(typeof reason.requiresComment, 'boolean');
  }

  // The endpoint's order is the catalogue's own: sort_order, then name. Read
  // the expected order straight from the table rather than re-deriving it, so
  // this asserts the query, not a second copy of the comparator.
  const { rows } = await pool.query(
    'SELECT code FROM downtime_reasons WHERE is_active ORDER BY sort_order, name'
  );
  assert.deepStrictEqual(
    payload.downtimeReasons.map((reason) => reason.code),
    rows.map((row) => row.code)
  );
});

test('a request with no bearer token is refused on the reasons listing', async () => {
  const response = await fetch(`${base}/api/maintenance/downtime-reasons`);
  assert.strictEqual(response.status, 401);
});

// ---------------------------------------------------------------------------
// Reporting a Breakdown: two records, one call.
// ---------------------------------------------------------------------------

test('reporting creates both a downtime event and a linked corrective work order in one call', async () => {
  const asset = await insertAsset(grantedLine.id, { name: 'Bearing Press' });
  const { response, payload } = await postDowntime(reporterAccount.token, breakdownBody(asset.id, {
    description: 'Bearing seized'
  }));
  assert.strictEqual(response.status, 201);

  const { downtimeEvent, workOrder } = payload;
  assert.strictEqual(downtimeEvent.assetId, String(asset.id));
  assert.strictEqual(downtimeEvent.assetName, 'Bearing Press');
  assert.strictEqual(downtimeEvent.orgUnitId, String(grantedLine.id));
  assert.strictEqual(downtimeEvent.status, 'open');
  assert.strictEqual(downtimeEvent.source, 'manual');
  assert.strictEqual(downtimeEvent.reportedBy, String(reporterEmployee.id));
  assert.strictEqual(downtimeEvent.reporterName, reporterEmployee.display_name);
  assert.ok(downtimeEvent.startedAt);
  assert.strictEqual(downtimeEvent.endedAt, null);
  assert.strictEqual(downtimeEvent.durationMinutes, null);

  assert.strictEqual(workOrder.status, 'approved');
  assert.strictEqual(workOrder.workType, 'corrective');
  assert.strictEqual(workOrder.summary, 'Breakdown: Bearing Press');
  assert.strictEqual(workOrder.description, 'Bearing seized');
  assert.strictEqual(workOrder.assetId, String(asset.id));
  assert.ok(workOrder.workOrderNo);
  assert.strictEqual(workOrder.downtimeEventId, downtimeEvent.id);

  // The link and the breakdown flag are what `v_asset_reliability` counts, and
  // neither is carried on the reduced wire shape beyond the id, so read them
  // back directly — the same "one fact the HTTP row does not carry" pattern
  // work-orders.test.js uses for actual_start.
  const { rows: [row] } = await pool.query(
    `SELECT is_breakdown, work_type, downtime_event_id, actual_start, actual_end
       FROM work_orders WHERE id = $1`,
    [workOrder.id]
  );
  assert.strictEqual(row.is_breakdown, true);
  assert.strictEqual(row.work_type, 'corrective');
  assert.strictEqual(String(row.downtime_event_id), String(downtimeEvent.id));
  assert.strictEqual(row.actual_start, null);
  assert.strictEqual(row.actual_end, null);

  const { rows: [stop] } = await pool.query(
    'SELECT source, reported_by, ended_at FROM downtime_events WHERE id = $1',
    [downtimeEvent.id]
  );
  assert.strictEqual(stop.source, 'manual');
  assert.strictEqual(String(stop.reported_by), String(reporterEmployee.id));
  assert.strictEqual(stop.ended_at, null);
});

test('an explicit startedAt is recorded as given, not replaced with now()', async () => {
  const asset = await insertAsset(grantedLine.id);
  const startedAt = '2026-01-02T03:04:05.000Z';
  const { response, payload } = await postDowntime(reporterAccount.token, breakdownBody(asset.id, { startedAt }));
  assert.strictEqual(response.status, 201);
  assert.strictEqual(new Date(payload.downtimeEvent.startedAt).toISOString(), startedAt);
});

test('an Account with no linked Employee still reports, with no reporter recorded', async () => {
  const asset = await insertAsset(grantedLine.id);
  const { response, payload } = await postDowntime(noEmployeeAccount.token, breakdownBody(asset.id));
  assert.strictEqual(response.status, 201);
  assert.strictEqual(payload.downtimeEvent.reportedBy, null);
  assert.strictEqual(payload.downtimeEvent.reporterName, null);
});

// ---------------------------------------------------------------------------
// The duplicate-report decision: the exclusion constraint is the arbiter.
// ---------------------------------------------------------------------------

test(
  'a second report while the Asset already has an open stop is refused 409, names the Asset and the start, ' +
    'and leaves exactly one work order and one downtime event',
  async () => {
    const asset = await insertAsset(grantedLine.id, { name: 'Duplicate Press' });

    const first = await postDowntime(reporterAccount.token, breakdownBody(asset.id));
    assert.strictEqual(first.response.status, 201);
    assert.strictEqual(await countDowntimeForAsset(asset.id), 1);
    assert.strictEqual(await countWorkOrdersForAsset(asset.id), 1);

    const second = await postDowntime(admin.token, breakdownBody(asset.id, { description: 'Second reporter' }));
    assert.strictEqual(second.response.status, 409);
    assert.strictEqual(second.payload.code, 'ASSET_ALREADY_DOWN');
    assert.ok(
      second.payload.message.includes('Duplicate Press'),
      `message should name the Asset: ${second.payload.message}`
    );
    assert.ok(
      second.payload.message.includes(first.payload.downtimeEvent.startedAt),
      `message should name the open stop's start: ${second.payload.message}`
    );

    // The atomicity proof: the loss happened AFTER the second work order was
    // written, and the rollback took it back out. One of each remains.
    assert.strictEqual(await countDowntimeForAsset(asset.id), 1);
    assert.strictEqual(await countWorkOrdersForAsset(asset.id), 1);

    const { rows: [openStop] } = await pool.query(
      'SELECT id FROM downtime_events WHERE asset_id = $1 AND ended_at IS NULL',
      [asset.id]
    );
    assert.strictEqual(String(openStop.id), String(first.payload.downtimeEvent.id));
  }
);

test('once the open stop is closed, the Asset can be reported down again', async () => {
  const asset = await insertAsset(grantedLine.id, { name: 'Recoverable Press' });
  const first = await postDowntime(reporterAccount.token, breakdownBody(asset.id));
  assert.strictEqual(first.response.status, 201);
  await closeDowntime(reporterAccount.token, first.payload.downtimeEvent.id, {});

  const second = await postDowntime(reporterAccount.token, breakdownBody(asset.id));
  assert.strictEqual(second.response.status, 201);
  assert.strictEqual(await countDowntimeForAsset(asset.id), 2);
  assert.strictEqual(await countWorkOrdersForAsset(asset.id), 2);
});

// ---------------------------------------------------------------------------
// Closing a stop: the generated duration follows from the pair.
// ---------------------------------------------------------------------------

test('closing sets ended_at and the generated duration_minutes follows from the pair', async () => {
  const asset = await insertAsset(grantedLine.id);
  const created = await postDowntime(reporterAccount.token, breakdownBody(asset.id));
  const startedAt = created.payload.downtimeEvent.startedAt;
  const endedAt = new Date(new Date(startedAt).getTime() + 30 * 60 * 1000).toISOString();

  const { response, payload } = await closeDowntime(reporterAccount.token, created.payload.downtimeEvent.id, {
    endedAt
  });
  assert.strictEqual(response.status, 200);
  assert.strictEqual(new Date(payload.downtimeEvent.endedAt).toISOString(), endedAt);
  assert.strictEqual(payload.downtimeEvent.durationMinutes, 30);
  // No reason was set, so a closed stop is 'unclassified' — the generated
  // status column's own middle value.
  assert.strictEqual(payload.downtimeEvent.status, 'unclassified');

  const { rows: [row] } = await pool.query(
    'SELECT ended_at, duration_minutes FROM downtime_events WHERE id = $1',
    [created.payload.downtimeEvent.id]
  );
  assert.ok(row.ended_at);
  assert.strictEqual(Number(row.duration_minutes), 30);
});

test('closing without an endedAt stamps now(), and closing an already-closed stop is a 409', async () => {
  const asset = await insertAsset(grantedLine.id);
  const created = await postDowntime(reporterAccount.token, breakdownBody(asset.id));

  const closed = await closeDowntime(reporterAccount.token, created.payload.downtimeEvent.id);
  assert.strictEqual(closed.response.status, 200);
  assert.ok(closed.payload.downtimeEvent.endedAt);

  const again = await closeDowntime(reporterAccount.token, created.payload.downtimeEvent.id, {});
  assert.strictEqual(again.response.status, 409);
});

// ---------------------------------------------------------------------------
// Classifying a stop.
// ---------------------------------------------------------------------------

test('classifying sets the reason, the classifier and the time — and a stop may be classified by somebody else', async () => {
  const asset = await insertAsset(grantedLine.id);
  const created = await postDowntime(reporterAccount.token, breakdownBody(asset.id));
  const reason = await downtimeReasonByCode('BRK-MECH');

  // reporterAccount raised the stop; classifierAccount is a different Account,
  // linked to a different Employee, holding write scope on the same Org Unit.
  const { response, payload } = await classifyDowntime(classifierAccount.token, created.payload.downtimeEvent.id, {
    downtimeReasonId: reason.id
  });
  assert.strictEqual(response.status, 200);
  assert.strictEqual(payload.downtimeEvent.downtimeReasonId, String(reason.id));
  assert.strictEqual(payload.downtimeEvent.downtimeReasonName, reason.name);
  assert.ok(payload.downtimeEvent.classifiedAt);
  // The reporter is untouched: classifying is its own fact.
  assert.strictEqual(payload.downtimeEvent.reportedBy, String(reporterEmployee.id));

  const { rows: [row] } = await pool.query(
    'SELECT classified_by, classified_at, downtime_reason_id FROM downtime_events WHERE id = $1',
    [created.payload.downtimeEvent.id]
  );
  assert.strictEqual(String(row.classified_by), String(classifierEmployee.id));
  assert.ok(row.classified_at);
  assert.strictEqual(String(row.downtime_reason_id), String(reason.id));
});

test('a requires_comment reason with no description is a 400; with one it is recorded', async () => {
  const asset = await insertAsset(grantedLine.id);
  const created = await postDowntime(reporterAccount.token, breakdownBody(asset.id));
  const reason = await downtimeReasonByCode('BRK-OTH');
  assert.strictEqual(reason.requires_comment, true);

  for (const body of [
    { downtimeReasonId: reason.id },
    { downtimeReasonId: reason.id, description: '' },
    { downtimeReasonId: reason.id, description: '   ' }
  ]) {
    const { response } = await classifyDowntime(reporterAccount.token, created.payload.downtimeEvent.id, body);
    assert.strictEqual(response.status, 400, JSON.stringify(body));
  }

  const { response, payload } = await classifyDowntime(reporterAccount.token, created.payload.downtimeEvent.id, {
    downtimeReasonId: reason.id,
    description: '  Hydraulic hose burst behind the guard  '
  });
  assert.strictEqual(response.status, 200);
  assert.strictEqual(payload.downtimeEvent.description, 'Hydraulic hose burst behind the guard');

  const { rows: [row] } = await pool.query('SELECT description FROM downtime_events WHERE id = $1', [
    created.payload.downtimeEvent.id
  ]);
  assert.strictEqual(row.description, 'Hydraulic hose burst behind the guard');
});

test('an unknown or malformed downtimeReasonId is a clean 404 naming the reason', async () => {
  const asset = await insertAsset(grantedLine.id);
  const created = await postDowntime(reporterAccount.token, breakdownBody(asset.id));

  const unknown = await classifyDowntime(reporterAccount.token, created.payload.downtimeEvent.id, {
    downtimeReasonId: '999999999'
  });
  assert.strictEqual(unknown.response.status, 404);
  assert.strictEqual(unknown.payload.message, 'Downtime reason not found');

  const malformed = await classifyDowntime(reporterAccount.token, created.payload.downtimeEvent.id, {
    downtimeReasonId: 'not-an-id'
  });
  assert.strictEqual(malformed.response.status, 404);
});

// ---------------------------------------------------------------------------
// The downtime's duration and the work order's duration are independent facts.
// ---------------------------------------------------------------------------

test("closing a downtime does not touch the work order's own actual_start/actual_end", async () => {
  const asset = await insertAsset(grantedLine.id);
  const created = await postDowntime(reporterAccount.token, breakdownBody(asset.id));
  const workOrderId = created.payload.workOrder.id;

  const closed = await closeDowntime(reporterAccount.token, created.payload.downtimeEvent.id, {});
  assert.strictEqual(closed.response.status, 200);
  assert.ok(closed.payload.downtimeEvent.endedAt);

  const { rows: [row] } = await pool.query(
    'SELECT actual_start, actual_end FROM work_orders WHERE id = $1',
    [workOrderId]
  );
  assert.strictEqual(row.actual_start, null);
  assert.strictEqual(row.actual_end, null);
});

// ---------------------------------------------------------------------------
// Scope: reporting needs a WRITE Grant reaching the Asset's Org Unit.
// ---------------------------------------------------------------------------

test('a write Grant reaching the Asset\'s Org Unit may report a Breakdown', async () => {
  const asset = await insertAsset(grantedLine.id);
  const { response } = await postDowntime(writerAccount.token, breakdownBody(asset.id));
  assert.strictEqual(response.status, 201);
});

test('a read-only Grant on the Asset\'s Org Unit is refused', async () => {
  const asset = await insertAsset(grantedLine.id);
  const { response, payload } = await postDowntime(readOnlyAccount.token, breakdownBody(asset.id));
  assert.strictEqual(response.status, 403);
  assert.strictEqual(payload.message, "Outside the caller's granted Org Units");
});

test('a write Grant on a sibling branch does not reach across', async () => {
  const asset = await insertAsset(grantedLine.id);
  const { response } = await postDowntime(siblingWriter.token, breakdownBody(asset.id));
  assert.strictEqual(response.status, 403);
});

test('an approved Account with no Grant anywhere cannot report a Breakdown', async () => {
  const asset = await insertAsset(grantedLine.id);
  const { response } = await postDowntime(noGrantAccount.token, breakdownBody(asset.id));
  assert.strictEqual(response.status, 403);
});

test('naming an Asset that does not exist on report is a 404 naming the Asset; malformed is also a clean 404', async () => {
  const missing = await postDowntime(reporterAccount.token, breakdownBody('999999999'));
  assert.strictEqual(missing.response.status, 404);
  assert.strictEqual(missing.payload.message, 'Asset not found');

  const malformed = await postDowntime(reporterAccount.token, breakdownBody('not-an-id'));
  assert.strictEqual(malformed.response.status, 404);
});

test('a request with no bearer token is refused on report', async () => {
  const asset = await insertAsset(grantedLine.id);
  const response = await fetch(`${base}/api/maintenance/downtime`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(breakdownBody(asset.id))
  });
  assert.strictEqual(response.status, 401);
});

// ---------------------------------------------------------------------------
// Scope: closing and classifying need a WRITE Grant reaching the stop.
// ---------------------------------------------------------------------------

test('a read-only Grant on the stop\'s Org Unit is refused on close and classify, and the row is unchanged', async () => {
  const asset = await insertAsset(grantedLine.id);
  const created = await postDowntime(reporterAccount.token, breakdownBody(asset.id));
  const reason = await downtimeReasonByCode('BRK-MECH');
  const stopId = created.payload.downtimeEvent.id;

  const closeResult = await closeDowntime(readOnlyAccount.token, stopId, {});
  assert.strictEqual(closeResult.response.status, 403);
  assert.strictEqual(closeResult.payload.message, "Outside the caller's granted Org Units");

  const classifyResult = await classifyDowntime(readOnlyAccount.token, stopId, { downtimeReasonId: reason.id });
  assert.strictEqual(classifyResult.response.status, 403);

  const { rows: [row] } = await pool.query(
    'SELECT ended_at, downtime_reason_id FROM downtime_events WHERE id = $1',
    [stopId]
  );
  assert.strictEqual(row.ended_at, null);
  assert.strictEqual(row.downtime_reason_id, null);
});

test('a write Grant on a sibling branch does not reach a stop on another branch', async () => {
  const asset = await insertAsset(grantedLine.id);
  const created = await postDowntime(reporterAccount.token, breakdownBody(asset.id));

  const closed = await closeDowntime(siblingWriter.token, created.payload.downtimeEvent.id, {});
  assert.strictEqual(closed.response.status, 403);
});

test('an approved Account with no Grant anywhere cannot close or classify', async () => {
  const asset = await insertAsset(grantedLine.id);
  const created = await postDowntime(reporterAccount.token, breakdownBody(asset.id));
  const reason = await downtimeReasonByCode('BRK-MECH');

  const closed = await closeDowntime(noGrantAccount.token, created.payload.downtimeEvent.id, {});
  assert.strictEqual(closed.response.status, 403);

  const classified = await classifyDowntime(noGrantAccount.token, created.payload.downtimeEvent.id, {
    downtimeReasonId: reason.id
  });
  assert.strictEqual(classified.response.status, 403);
});

test('an unknown or malformed stop id is a clean 404 on close and classify', async () => {
  // admin: canAct would pass unconditionally, so a 404 here proves existence
  // is checked before scope, not the other way round.
  const unknownClose = await closeDowntime(admin.token, '999999999', {});
  assert.strictEqual(unknownClose.response.status, 404);
  assert.strictEqual(unknownClose.payload.message, 'Downtime event not found');

  const malformedClose = await closeDowntime(admin.token, 'not-an-id', {});
  assert.strictEqual(malformedClose.response.status, 404);

  const unknownClassify = await classifyDowntime(admin.token, '999999999', { downtimeReasonId: '1' });
  assert.strictEqual(unknownClassify.response.status, 404);

  const malformedClassify = await classifyDowntime(admin.token, 'not-an-id', { downtimeReasonId: '1' });
  assert.strictEqual(malformedClassify.response.status, 404);
});

// ---------------------------------------------------------------------------
// The Site-wide read: open by default, history on request, nobody filtered out.
// ---------------------------------------------------------------------------

test('the Site-wide read returns stops the caller holds no Grant over', async () => {
  const asset = await insertAsset(otherLine.id);
  const created = await postDowntime(admin.token, breakdownBody(asset.id));
  assert.strictEqual(created.response.status, 201);

  const { response, payload } = await getDowntime(noGrantAccount.token, site.id);
  assert.strictEqual(response.status, 200);
  assert.ok(payload.downtimeEvents.some((stop) => stop.id === created.payload.downtimeEvent.id));
});

test('the default read is open stops only, newest first; ?includeClosed=true widens to history', async () => {
  const asset = await insertAsset(grantedLine.id);
  const open = await postDowntime(reporterAccount.token, breakdownBody(asset.id));
  const asset2 = await insertAsset(grantedLine.id);
  const willClose = await postDowntime(reporterAccount.token, breakdownBody(asset2.id));
  await closeDowntime(reporterAccount.token, willClose.payload.downtimeEvent.id, {});

  const openOnly = await getDowntime(admin.token, site.id);
  const openIds = openOnly.payload.downtimeEvents.map((stop) => stop.id);
  assert.ok(openIds.includes(open.payload.downtimeEvent.id));
  assert.ok(!openIds.includes(willClose.payload.downtimeEvent.id));
  for (const stop of openOnly.payload.downtimeEvents) {
    assert.strictEqual(stop.endedAt, null);
  }

  const withHistory = await getDowntime(admin.token, site.id, '?includeClosed=true');
  assert.ok(withHistory.payload.downtimeEvents.some((stop) => stop.id === willClose.payload.downtimeEvent.id));
});

test('an unknown Site on the read is a 404, not an empty list', async () => {
  const { response, payload } = await getDowntime(admin.token, '999999999');
  assert.strictEqual(response.status, 404);
  assert.strictEqual(payload.message, 'Site not found');
});

test('a request with no bearer token is refused on the Site-wide read', async () => {
  const response = await fetch(`${base}/api/maintenance/sites/${site.id}/downtime`);
  assert.strictEqual(response.status, 401);
});
