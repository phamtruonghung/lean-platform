/*
 * The Employee link (issue #115, ADR-0022): email matching produces a
 * *suggestion* on the Approval queue, an administrator *confirms* it at
 * Approval, and PUT /accounts/:id/employee corrects it afterwards. Over HTTP,
 * against a real database and a real (locally issued) JWKS — the same seam
 * as accounts.test.js, plant.test.js, approval.test.js and directory.test.js
 * (see any of their own headers, and the README's Tests section).
 *
 * This file does not truncate `app_users` or `employees`: both are shared
 * with other integration files, and `npm run test:integration` runs every
 * file in this directory with `--test-concurrency=1` — see approval.test.js's
 * own header for the same reasoning. Every row this file inserts, across
 * `app_users`, `app_user_org_units` and `employees`, is deleted again in
 * `test.after()`.
 *
 * Needs a database with every migration applied. Set DATABASE_URL first —
 * see the README's Tests section.
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
let adminToken;
let adminAccountId;

const insertedAccountIds = [];
const insertedEmployeeIds = [];

let codeCounter = 0;
// Unique across processes (process.pid) and within one run (the counter) —
// the same device approval.test.js's/directory.test.js's own uniqueCode use.
function uniqueCode(prefix) {
  codeCounter += 1;
  return `${prefix}${process.pid}${codeCounter}`;
}

async function signToken(subject, email) {
  return jwks.signToken(
    { sub: subject, email: email ?? `${subject}@example.com` },
    { issuer: ISSUER, audience: AUDIENCE }
  );
}

async function authHeader(subject, email) {
  return { authorization: `Bearer ${await signToken(subject, email)}` };
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

  // The administrator this whole suite acts as — inserted directly, with no
  // grant rows at all, the same fixture approval.test.js's own adminToken is.
  const adminSubject = `employee-link-admin-${process.pid}`;
  const { rows: [admin] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status)
     VALUES ($1, 'Employee Link Test Admin', 'admin', $2, TRUE, 'approved') RETURNING id`,
    [`${adminSubject}@example.com`, adminSubject]
  );
  adminAccountId = admin.id;
  insertedAccountIds.push(admin.id);
  adminToken = await authHeader(adminSubject);
});

test.after(async () => {
  await pool.query('DELETE FROM app_user_org_units WHERE app_user_id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM app_users WHERE id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM employees WHERE id = ANY($1)', [insertedEmployeeIds]);
  await new Promise((resolve) => server.close(resolve));
  await closePool();
  await jwks.close();
});

// A brand-new pending Account, through the real sign-in path, with a chosen
// email — the email is what the suggestion matches against, so tests need to
// pick it deliberately rather than accept the default subject@example.com.
async function createPendingAccount(subjectPrefix, email) {
  const subject = uniqueCode(subjectPrefix);
  const accountEmail = email ?? `${subject}@example.com`;
  const token = await signToken(subject, accountEmail);
  const response = await fetch(`${base}/api/people/me`, {
    headers: { authorization: `Bearer ${token}` }
  });
  const { account } = await response.json();
  insertedAccountIds.push(account.id);
  return { subject, token, account, email: accountEmail };
}

async function insertEmployee({ workEmail = null, isActive = true } = {}) {
  const employeeNo = uniqueCode('EMP');
  const { rows: [row] } = await pool.query(
    `INSERT INTO employees (employee_no, first_name, last_name, work_email, is_active)
     VALUES ($1, 'Link', 'Candidate', $2, $3) RETURNING id, employee_no, display_name, work_email`,
    [employeeNo, workEmail, isActive]
  );
  insertedEmployeeIds.push(row.id);
  return row;
}

async function pendingQueue(token = adminToken) {
  return fetch(`${base}/api/people/accounts/pending`, { headers: token });
}

async function approve(id, body, token = adminToken) {
  return fetch(`${base}/api/people/accounts/${id}/approval`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
}

// Approves a brand-new pending Account with no Employee link and returns its
// (now active) sign-in token — the fixture most of the PUT
// /accounts/:id/employee tests below start from. Mirrors approval.test.js's
// own approveFreshAccount.
async function approveFreshAccount(role = 'operator') {
  const { subject, token, account: pending } = await createPendingAccount('putlink');
  const response = await approve(pending.id, { role, grants: [] });
  const body = await response.json();
  assert.strictEqual(response.status, 200, `approval should succeed: ${JSON.stringify(body)}`);
  return { subject, token: { authorization: `Bearer ${token}` }, account: body.account };
}

// ---------------------------------------------------------------------------
// 1. GET /accounts/pending's own suggestedEmployee.
// ---------------------------------------------------------------------------

test('the Approval queue suggests the Employee whose work_email matches the Account email, case-insensitively', async () => {
  const employee = await insertEmployee({ workEmail: `Suggest.${uniqueCode('match')}@example.com` });
  const { account: pending } = await createPendingAccount('suggest', employee.work_email.toUpperCase());

  const response = await pendingQueue();
  assert.strictEqual(response.status, 200);
  const { accounts } = await response.json();
  const row = accounts.find((a) => a.id === pending.id);
  assert.ok(row, 'the pending Account is in the queue');
  assert.deepStrictEqual(row.suggestedEmployee, {
    id: employee.id,
    employeeNo: employee.employee_no,
    displayName: employee.display_name
  });
});

test('the Approval queue suggests nothing when no Employee\'s work_email matches the Account email', async () => {
  const { account: pending } = await createPendingAccount('nomatch');

  const response = await pendingQueue();
  const { accounts } = await response.json();
  const row = accounts.find((a) => a.id === pending.id);
  assert.strictEqual(row.suggestedEmployee, null);
});

// ---------------------------------------------------------------------------
// 2. A suggestion is null, not an error, when it cannot be acted on.
// ---------------------------------------------------------------------------

test('a suggestion is null, not an error, when the matched Employee has Departed', async () => {
  const employee = await insertEmployee({ workEmail: `Departed.${uniqueCode('m')}@example.com`, isActive: false });
  const { account: pending } = await createPendingAccount('departedmatch', employee.work_email);

  const response = await pendingQueue();
  const { accounts } = await response.json();
  const row = accounts.find((a) => a.id === pending.id);
  assert.strictEqual(row.suggestedEmployee, null);
});

test('a suggestion is null, not an error, when the matched Employee is already linked to another Account', async () => {
  const employee = await insertEmployee({ workEmail: `Linked.${uniqueCode('m')}@example.com` });

  // A separate, already-approved Account holds this Employee's link.
  const otherSubject = uniqueCode('linked-other');
  const { rows: [otherAccount] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status, employee_id)
     VALUES ($1, 'Already Linked', 'operator', $2, TRUE, 'approved', $3) RETURNING id`,
    [`${otherSubject}@example.com`, otherSubject, employee.id]
  );
  insertedAccountIds.push(otherAccount.id);

  const { account: pending } = await createPendingAccount('linkedmatch', employee.work_email);

  const response = await pendingQueue();
  const { accounts } = await response.json();
  const row = accounts.find((a) => a.id === pending.id);
  assert.strictEqual(row.suggestedEmployee, null);
});

// ---------------------------------------------------------------------------
// 3. Approval writes the confirmed Employee link in the same transaction as
//    role and Grants.
// ---------------------------------------------------------------------------

test('approving an Account with an employeeId links it to that Employee', async () => {
  const employee = await insertEmployee({});
  const { account: pending } = await createPendingAccount('confirm');

  const response = await approve(pending.id, { role: 'operator', grants: [], employeeId: employee.id });
  assert.strictEqual(response.status, 200);
  const { account } = await response.json();
  assert.strictEqual(String(account.employeeId), String(employee.id));

  const { rows: [row] } = await pool.query('SELECT employee_id FROM app_users WHERE id = $1', [pending.id]);
  assert.strictEqual(String(row.employee_id), String(employee.id));
});

test('employeeId is optional on Approval — omitting it leaves the Account unlinked', async () => {
  const { account: pending } = await createPendingAccount('noemployeeid');

  const response = await approve(pending.id, { role: 'operator', grants: [] });
  assert.strictEqual(response.status, 200);
  const { account } = await response.json();
  assert.strictEqual(account.employeeId, null);
});

// ---------------------------------------------------------------------------
// 4. Approval refuses each of the three ways employeeId can be wrong, with a
//    distinct, specific message — not one generic failure.
// ---------------------------------------------------------------------------

test('Approval refuses an employeeId that names no Employee at all', async () => {
  const { account: pending } = await createPendingAccount('unknownemployee');

  const response = await approve(pending.id, { role: 'operator', grants: [], employeeId: '999999999' });
  assert.strictEqual(response.status, 404);
  const body = await response.json();
  assert.match(body.message, /does not name an existing Employee/);

  const { rows: [row] } = await pool.query('SELECT approval_status FROM app_users WHERE id = $1', [pending.id]);
  assert.strictEqual(row.approval_status, 'pending');
});

test('Approval refuses an employeeId naming an Employee who has Departed', async () => {
  const departed = await insertEmployee({ isActive: false });
  const { account: pending } = await createPendingAccount('departedemployee');

  const response = await approve(pending.id, { role: 'operator', grants: [], employeeId: departed.id });
  assert.strictEqual(response.status, 409);
  const body = await response.json();
  assert.match(body.message, /Departed/);
  assert.doesNotMatch(body.message, /already linked/);
});

test('Approval refuses an employeeId already linked to a different Account', async () => {
  const employee = await insertEmployee({});
  const holderSubject = uniqueCode('holder');
  const { rows: [holder] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status, employee_id)
     VALUES ($1, 'Employee Holder', 'operator', $2, TRUE, 'approved', $3) RETURNING id`,
    [`${holderSubject}@example.com`, holderSubject, employee.id]
  );
  insertedAccountIds.push(holder.id);

  const { account: pending } = await createPendingAccount('alreadylinked');

  const response = await approve(pending.id, { role: 'operator', grants: [], employeeId: employee.id });
  assert.strictEqual(response.status, 409);
  const body = await response.json();
  assert.match(body.message, /already linked to a different Account/);
});

// ---------------------------------------------------------------------------
// 5. PUT /accounts/:id/employee — administrator only. Sets the link, and
//    clears it when passed null.
// ---------------------------------------------------------------------------

async function putEmployeeLink(accountId, employeeId, token = adminToken) {
  return fetch(`${base}/api/people/accounts/${accountId}/employee`, {
    method: 'PUT',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify({ employeeId })
  });
}

test('PUT /accounts/:id/employee sets the link', async () => {
  const employee = await insertEmployee({});
  const { token, account } = await approveFreshAccount();

  const response = await putEmployeeLink(account.id, employee.id);
  assert.strictEqual(response.status, 200);
  const { account: updated } = await response.json();
  assert.strictEqual(String(updated.employeeId), String(employee.id));

  const meResponse = await fetch(`${base}/api/people/me`, { headers: token });
  const meBody = await meResponse.json();
  assert.strictEqual(String(meBody.account.employeeId), String(employee.id));
});

test('PUT /accounts/:id/employee clears the link when passed null', async () => {
  const employee = await insertEmployee({});
  const { account } = await approveFreshAccount();
  const set = await putEmployeeLink(account.id, employee.id);
  assert.strictEqual(set.status, 200);

  const response = await putEmployeeLink(account.id, null);
  assert.strictEqual(response.status, 200);
  const { account: updated } = await response.json();
  assert.strictEqual(updated.employeeId, null);
});

test('PUT /accounts/:id/employee requires the administrator role', async () => {
  const employee = await insertEmployee({});
  const { token: nonAdminToken } = await approveFreshAccount();
  const { account: target } = await approveFreshAccount();

  const response = await putEmployeeLink(target.id, employee.id, nonAdminToken);
  assert.strictEqual(response.status, 403);
});

test('PUT /accounts/:id/employee refuses each of the same three ways employeeId can be wrong', async () => {
  const { account } = await approveFreshAccount();

  const notFound = await putEmployeeLink(account.id, '999999999');
  assert.strictEqual(notFound.status, 404);

  const departed = await insertEmployee({ isActive: false });
  const departedResponse = await putEmployeeLink(account.id, departed.id);
  assert.strictEqual(departedResponse.status, 409);
  const departedBody = await departedResponse.json();
  assert.match(departedBody.message, /Departed/);

  const employee = await insertEmployee({});
  const holderSubject = uniqueCode('put-holder');
  const { rows: [holder] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status, employee_id)
     VALUES ($1, 'Put Holder', 'operator', $2, TRUE, 'approved', $3) RETURNING id`,
    [`${holderSubject}@example.com`, holderSubject, employee.id]
  );
  insertedAccountIds.push(holder.id);
  const linkedResponse = await putEmployeeLink(account.id, employee.id);
  assert.strictEqual(linkedResponse.status, 409);
  const linkedBody = await linkedResponse.json();
  assert.match(linkedBody.message, /already linked to a different Account/);
});

// ---------------------------------------------------------------------------
// 6. ADR-0013's own rule, applied here: an administrator may not link their
//    own Account, refused as this route's very first statement.
// ---------------------------------------------------------------------------

test('an administrator cannot link their own Account', async () => {
  const employee = await insertEmployee({});

  const response = await putEmployeeLink(adminAccountId, employee.id);
  assert.strictEqual(response.status, 403);
  const body = await response.json();
  assert.match(body.message, /their own Account/);
});

test('a second administrator can still link the first\'s Account — the rule is about identity, not the admin role', async () => {
  const employee = await insertEmployee({});
  const { token: secondAdminToken } = await approveFreshAccount('admin');

  const response = await putEmployeeLink(adminAccountId, employee.id, secondAdminToken);
  assert.strictEqual(response.status, 200);

  // Cleared again so no later test in this file inherits a linked admin.
  const clear = await putEmployeeLink(adminAccountId, null, secondAdminToken);
  assert.strictEqual(clear.status, 200);
});

// Mirrors approval.test.js's own "the self-action refusal happens before
// body validation": the route's own "employeeId is required" check runs
// before setAccountEmployee — and therefore before refuseSelfAction — is
// ever reached, so a self-action with no employeeId key at all is the
// route's ordinary 400, not the service's 403. But once the body shape is
// valid, refuseSelfAction runs ahead of employeeId's own validity — an
// unknown employeeId against the caller's own Account is still the
// self-action 403, not the 404 an unknown employeeId would otherwise get
// against any other Account.
test('the self-action refusal on PUT /accounts/:id/employee happens before employeeId validation, but after body-shape validation', async () => {
  const missingBody = await fetch(`${base}/api/people/accounts/${adminAccountId}/employee`, {
    method: 'PUT',
    headers: { ...adminToken, 'content-type': 'application/json' },
    body: JSON.stringify({})
  });
  assert.strictEqual(missingBody.status, 400);

  const unknownEmployee = await putEmployeeLink(adminAccountId, '999999999');
  assert.strictEqual(unknownEmployee.status, 403);
});

// ---------------------------------------------------------------------------
// 7. POST /employees/:id/departure reports the Account left signed-in-able —
//    administrator-only already, so this does not widen ADR-0009's own
//    administrator-only line around an Account's identity.
// ---------------------------------------------------------------------------

async function departEmployee(employeeId, token = adminToken) {
  return fetch(`${base}/api/people/employees/${employeeId}/departure`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify({})
  });
}

test('departing an Employee reports the linked Account, when one exists', async () => {
  const employee = await insertEmployee({});
  const linkResponse = await approve(
    (await createPendingAccount('departurelinked')).account.id,
    { role: 'operator', grants: [], employeeId: employee.id }
  );
  const { account: linkedAccount } = await linkResponse.json();

  const response = await departEmployee(employee.id);
  assert.strictEqual(response.status, 200);
  const { employee: departed } = await response.json();
  assert.deepStrictEqual(departed.linkedAccount, {
    id: linkedAccount.id,
    email: linkedAccount.email,
    isActive: linkedAccount.isActive
  });
});

test('departing an Employee with no linked Account reports linkedAccount: null', async () => {
  const employee = await insertEmployee({});

  const response = await departEmployee(employee.id);
  assert.strictEqual(response.status, 200);
  const { employee: departed } = await response.json();
  assert.strictEqual(departed.linkedAccount, null);
});

// GET /employees/:id must NOT carry linkedAccount — ADR-0009 keeps an
// Account's own identity administrator-only (GET /accounts), and the
// Directory is readable by any approved Account; leaking the same fact
// through the detail view would widen that without a ticket saying so.
test('GET /employees/:id does not expose linkedAccount — ADR-0009 keeps that administrator-only', async () => {
  const employee = await insertEmployee({});
  const linkResponse = await approve(
    (await createPendingAccount('nolinkleak')).account.id,
    { role: 'operator', grants: [], employeeId: employee.id }
  );
  assert.strictEqual(linkResponse.status, 200);

  const response = await fetch(`${base}/api/people/employees/${employee.id}`, { headers: adminToken });
  assert.strictEqual(response.status, 200);
  const { employee: detail } = await response.json();
  assert.strictEqual(Object.prototype.hasOwnProperty.call(detail, 'linkedAccount'), false);
});

// ---------------------------------------------------------------------------
// 8. GET /employees/me — unreachable before this issue (app_users.employee_id
//    was written nowhere), now reachable end to end: sign in, get suggested
//    and confirmed at Approval, then read back the Employee record.
// ---------------------------------------------------------------------------

test('GET /employees/me returns the caller\'s own record once their Account is linked, via the real write path', async () => {
  const employee = await insertEmployee({ workEmail: `Me.${uniqueCode('m')}@example.com` });
  const { subject, token, account: pending } = await createPendingAccount('meflow', employee.work_email);

  const approved = await approve(pending.id, { role: 'operator', grants: [], employeeId: employee.id });
  assert.strictEqual(approved.status, 200);

  const response = await fetch(`${base}/api/people/employees/me`, {
    headers: { authorization: `Bearer ${token}` }
  });
  assert.strictEqual(response.status, 200);
  const { employee: own } = await response.json();
  assert.strictEqual(own.id, employee.id);
  void subject;
});
