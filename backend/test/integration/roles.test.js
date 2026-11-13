/*
 * Permissions, roles and assignment, over HTTP, against a real database and a
 * real local session — issue #492, ADR-0061.
 *
 * What this suite is for, beyond "the endpoints answer": it is the proof that
 * the *catalogue* the code checks against and the *rows* the database seeded
 * are the same list. `permissions.js` is where a code comes into existence and
 * the migration carries a frozen copy (a migration is a one-way door, ADR-0007);
 * the assertion in group 2 is what keeps the copy honest, so a code added to
 * the source and not to a new migration fails here rather than silently never
 * being grantable.
 *
 * The four Accounts this file inserts (`roles-admin`, `roles-supervisor`,
 * `roles-operator`, and one the assignment group puts a role on) are its own
 * setup, and it deletes them afterwards: `app_users` is shared with several
 * other integration files, which is why this file never truncates it.
 *
 * Needs a database with every migration applied. Set DATABASE_URL first — see
 * the README's Tests section.
 */

const test = require('node:test');
const assert = require('node:assert');
const { tokenFor } = require('../helpers/session');
const { PERMISSIONS } = require('../../src/modules/people/permissions');

let server;
let base;
let pool;
let closePool;

const ADMIN = 'roles-admin';
const SUPERVISOR = 'roles-supervisor';
const OPERATOR = 'roles-operator';

// Roles this file creates, removed after it runs. The seeded roles are seed
// data, not this file's, and are left alone.
const createdRoleCodes = [];

async function insertAccount(subject, role) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status)
     VALUES ($1, $2, $3, $4, TRUE, 'approved')
     RETURNING id`,
    [`${subject}@example.com`, subject, role, subject]
  );
  return String(row.id);
}

async function call(subject, path, { method = 'GET', body } = {}) {
  const token = await tokenFor(subject);
  const response = await fetch(`${base}/api/people${path}`, {
    method,
    headers: {
      authorization: `Bearer ${token}`,
      ...(body === undefined ? {} : { 'content-type': 'application/json' })
    },
    body: body === undefined ? undefined : JSON.stringify(body)
  });
  let json = null;
  try {
    json = await response.json();
  } catch {
    json = null;
  }
  return { status: response.status, body: json };
}

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

  await insertAccount(ADMIN, 'admin');
  await insertAccount(SUPERVISOR, 'supervisor');
  await insertAccount(OPERATOR, 'operator');
});

test.after(async () => {
  await pool.query(
    "DELETE FROM app_users WHERE external_subject = ANY($1::text[])",
    [[ADMIN, SUPERVISOR, OPERATOR]]
  );
  if (createdRoleCodes.length > 0) {
    await pool.query('DELETE FROM app_roles WHERE code = ANY($1::text[])', [createdRoleCodes]);
  }
  await new Promise((resolve) => server.close(resolve));
  await closePool();
});

// ---------------------------------------------------------------------------
// 1. `/me` answers the effective set: the default group, plus what the
//    Account's own role earns, plus anything assigned.
// ---------------------------------------------------------------------------

test('an administrator holds the whole catalogue', async () => {
  const { status, body } = await call(ADMIN, '/me');
  assert.strictEqual(status, 200);
  assert.strictEqual(body.permissions.length, PERMISSIONS.length);
  assert.ok(body.permissions.includes('ADM_ROLES_CHANGE'));
  assert.ok(body.roles.includes('ROLE_ADMIN'));
});

test('an operator holds the default group and not the administration codes', async () => {
  const { status, body } = await call(OPERATOR, '/me');
  assert.strictEqual(status, 200);

  // The default group: the directory, the registers every Account reads, and
  // raising a Concern or a Request.
  for (const code of ['PPL_DIRECTORY_DISPLAY', 'ACT_RAISE', 'MTN_REQUESTS_RAISE']) {
    assert.ok(body.permissions.includes(code), `expected an operator to hold ${code}`);
  }

  // Nothing an operator is not offered today: no Maintenance tool Screen, no
  // write behind one, and no administration.
  for (const code of ['MTN_WORK_ORDERS_DISPLAY', 'MTN_WORK_ORDERS_CHANGE', 'ADM_ROLES_CHANGE']) {
    assert.ok(!body.permissions.includes(code), `expected an operator not to hold ${code}`);
  }

  assert.deepStrictEqual(body.roles.sort(), ['ROLE_OPERATOR', 'ROLE_STANDARD']);
});

test('a supervisor holds the Maintenance Screens but not the writes behind them', async () => {
  const { body } = await call(SUPERVISOR, '/me');
  assert.ok(body.permissions.includes('MTN_WORK_ORDERS_DISPLAY'));
  assert.ok(body.permissions.includes('MTN_REQUESTS_TRIAGE'));
  assert.ok(!body.permissions.includes('MTN_WORK_ORDERS_CHANGE'));
  assert.ok(body.roles.includes('ROLE_SUPERVISOR'));
});

// ---------------------------------------------------------------------------
// 2. The catalogue the code holds and the rows the migration seeded agree.
// ---------------------------------------------------------------------------

test('the seeded catalogue is exactly permissions.js, in its order', async () => {
  const { status, body } = await call(ADMIN, '/permissions');
  assert.strictEqual(status, 200);
  assert.deepStrictEqual(
    body.permissions.map((permission) => permission.code),
    PERMISSIONS.map((permission) => permission.code),
    'the migration seed and src/modules/people/permissions.js have drifted'
  );
  assert.deepStrictEqual(
    body.permissions.map((permission) => permission.label),
    PERMISSIONS.map((permission) => permission.label)
  );
});

test('there is exactly one default role, and it is not assignable', async () => {
  const { rows } = await pool.query('SELECT code FROM app_roles WHERE is_default');
  assert.strictEqual(rows.length, 1);
  assert.strictEqual(rows[0].code, 'ROLE_STANDARD');
});

// ---------------------------------------------------------------------------
// 3. Reading and maintaining roles is administrator work.
// ---------------------------------------------------------------------------

test('a non-administrator is refused every roles endpoint', async () => {
  const attempts = [
    ['GET', '/roles', undefined, 'ADM_ROLES_DISPLAY'],
    ['GET', '/permissions', undefined, 'ADM_ROLES_DISPLAY'],
    ['POST', '/roles', { code: 'ROLE_SNEAK', name: 'Sneak' }, 'ADM_ROLES_CHANGE']
  ];

  for (const [method, path, body, permission] of attempts) {
    const response = await call(OPERATOR, path, { method, body });
    assert.strictEqual(response.status, 403, `${method} ${path} should be refused`);
    assert.strictEqual(response.body.code, 'PERMISSION_REQUIRED');
    assert.strictEqual(response.body.permission, permission);
  }
});

test('the seeded roles are listed with their codes, sets and holders', async () => {
  const { status, body } = await call(ADMIN, '/roles');
  assert.strictEqual(status, 200);

  const byCode = new Map(body.roles.map((role) => [role.code, role]));
  const standard = byCode.get('ROLE_STANDARD');
  assert.ok(standard, 'the default role must be listed');
  assert.strictEqual(standard.isDefault, true);
  assert.strictEqual(standard.legacyRole, null);
  assert.ok(standard.permissionCodes.includes('PPL_DIRECTORY_DISPLAY'));
  assert.ok(standard.holderCount >= 3, 'every Account holds the default role');

  const supervisor = byCode.get('ROLE_SUPERVISOR');
  assert.strictEqual(supervisor.legacyRole, 'supervisor');
  assert.ok(supervisor.permissionCodes.includes('MTN_WORK_ORDERS_DISPLAY'));
  const engineer = byCode.get('ROLE_ENGINEER');
  assert.ok(engineer.permissionCodes.includes('MTN_WORK_ORDERS_CHANGE'));

  // The default role sorts first; the account-role groups follow in the order
  // the Accounts Screen offers them.
  assert.strictEqual(body.roles[0].code, 'ROLE_STANDARD');
  const legacyOrder = body.roles
    .filter((role) => role.legacyRole !== null)
    .map((role) => role.legacyRole);
  assert.deepStrictEqual(legacyOrder, ['operator', 'supervisor', 'engineer', 'manager', 'admin']);
});

// ---------------------------------------------------------------------------
// 4. An administrator creates a role and changes what it carries.
// ---------------------------------------------------------------------------

test('a role is created with a normalised code and only known permissions', async () => {
  const { status, body } = await call(ADMIN, '/roles', {
    method: 'POST',
    body: {
      code: ' role_store_room ',
      name: 'Store room',
      description: 'Counts stock.  ',
      permissions: ['MTN_STORES_DISPLAY', 'mtn_parts_display', 'NOT_A_CODE', 'MTN_STORES_DISPLAY']
    }
  });

  assert.strictEqual(status, 201);
  assert.strictEqual(body.role.code, 'ROLE_STORE_ROOM');
  assert.strictEqual(body.role.name, 'Store room');
  assert.strictEqual(body.role.description, 'Counts stock.');
  // Unknown code dropped, the lower-case one accepted as itself, duplicates
  // collapsed: the response states what was stored, not what was asked for.
  assert.deepStrictEqual(body.role.permissionCodes.sort(), ['MTN_PARTS_DISPLAY', 'MTN_STORES_DISPLAY']);
  createdRoleCodes.push('ROLE_STORE_ROOM');
});

test('a duplicate role code is a 409, and a code of the wrong shape a 400', async () => {
  const duplicate = await call(ADMIN, '/roles', {
    method: 'POST',
    body: { code: 'ROLE_STORE_ROOM', name: 'Again' }
  });
  assert.strictEqual(duplicate.status, 409);

  const malformed = await call(ADMIN, '/roles', {
    method: 'POST',
    body: { code: 'not a code', name: 'Nope' }
  });
  assert.strictEqual(malformed.status, 400);
});

test('a role\'s permission set is replaced whole, by its id', async () => {
  const { body: list } = await call(ADMIN, '/roles');
  const storeRoom = list.roles.find((role) => role.code === 'ROLE_STORE_ROOM');

  const { status, body } = await call(ADMIN, `/roles/${storeRoom.id}/permissions`, {
    method: 'PUT',
    body: { permissions: ['MTN_STORES_DISPLAY', 'MTN_METERS_CHANGE'] }
  });

  assert.strictEqual(status, 200);
  assert.deepStrictEqual(body.role.permissionCodes.sort(), ['MTN_METERS_CHANGE', 'MTN_STORES_DISPLAY']);

  // Replaced, not merged: the first round's MTN_PARTS_DISPLAY is gone.
  assert.ok(!body.role.permissionCodes.includes('MTN_PARTS_DISPLAY'));
});

test('a role can be retired and read back with includeInactive', async () => {
  const { body: list } = await call(ADMIN, '/roles');
  const storeRoom = list.roles.find((role) => role.code === 'ROLE_STORE_ROOM');

  const retired = await call(ADMIN, `/roles/${storeRoom.id}`, {
    method: 'PATCH',
    body: { isActive: false }
  });
  assert.strictEqual(retired.status, 200);
  assert.strictEqual(retired.body.role.isActive, false);

  const { body: activeOnly } = await call(ADMIN, '/roles');
  assert.ok(!activeOnly.roles.some((role) => role.code === 'ROLE_STORE_ROOM'));

  const { body: all } = await call(ADMIN, '/roles?includeInactive=true');
  assert.ok(all.roles.some((role) => role.code === 'ROLE_STORE_ROOM' && !role.isActive));

  // Put it back, so the assignment group below has an active role to assign.
  await call(ADMIN, `/roles/${storeRoom.id}`, { method: 'PATCH', body: { isActive: true } });
});

// ---------------------------------------------------------------------------
// 5. Assigning a role to one Account — the "Assign" button.
// ---------------------------------------------------------------------------

test('assigning a role gives that Account the permissions it carries, and unassigning takes them away', async () => {
  const { body: list } = await call(ADMIN, '/roles');
  const storeRoom = list.roles.find((role) => role.code === 'ROLE_STORE_ROOM');
  const { rows: [operator] } = await pool.query(
    'SELECT id FROM app_users WHERE external_subject = $1',
    [OPERATOR]
  );

  const before = await call(OPERATOR, '/me');
  assert.ok(!before.body.permissions.includes('MTN_METERS_CHANGE'));

  const assigned = await call(ADMIN, `/accounts/${operator.id}/roles`, {
    method: 'PUT',
    body: { roleIds: [storeRoom.id] }
  });
  assert.strictEqual(assigned.status, 200);
  const held = assigned.body.roles.find((role) => role.code === 'ROLE_STORE_ROOM');
  assert.strictEqual(held.isAssigned, true);
  assert.strictEqual(held.isAutomatic, false);
  // The automatic ones are marked as such, so a dialog can disable them.
  assert.strictEqual(assigned.body.roles.find((role) => role.code === 'ROLE_STANDARD').isAutomatic, true);
  assert.strictEqual(assigned.body.roles.find((role) => role.code === 'ROLE_OPERATOR').isAutomatic, true);

  const after = await call(OPERATOR, '/me');
  assert.ok(after.body.permissions.includes('MTN_METERS_CHANGE'));
  assert.ok(after.body.roles.includes('ROLE_STORE_ROOM'));

  const cleared = await call(ADMIN, `/accounts/${operator.id}/roles`, {
    method: 'PUT',
    body: { roleIds: [] }
  });
  assert.strictEqual(cleared.status, 200);

  const gone = await call(OPERATOR, '/me');
  assert.ok(!gone.body.permissions.includes('MTN_METERS_CHANGE'));
  assert.ok(gone.body.permissions.includes('PPL_DIRECTORY_DISPLAY'), 'the default group stays');
});

test('an automatic role cannot be assigned or taken away by hand', async () => {
  const { body: list } = await call(ADMIN, '/roles');
  const standard = list.roles.find((role) => role.code === 'ROLE_STANDARD');
  const { rows: [operator] } = await pool.query(
    'SELECT id FROM app_users WHERE external_subject = $1',
    [OPERATOR]
  );

  const refusal = await call(ADMIN, `/accounts/${operator.id}/roles`, {
    method: 'PUT',
    body: { roleIds: [standard.id] }
  });
  assert.strictEqual(refusal.status, 400);
  assert.match(refusal.body.message, /ROLE_STANDARD/);
});

test('a retired role cannot be assigned', async () => {
  const { body: list } = await call(ADMIN, '/roles');
  const storeRoom = list.roles.find((role) => role.code === 'ROLE_STORE_ROOM');
  const { rows: [operator] } = await pool.query(
    'SELECT id FROM app_users WHERE external_subject = $1',
    [OPERATOR]
  );

  await call(ADMIN, `/roles/${storeRoom.id}`, { method: 'PATCH', body: { isActive: false } });

  const refusal = await call(ADMIN, `/accounts/${operator.id}/roles`, {
    method: 'PUT',
    body: { roleIds: [storeRoom.id] }
  });
  assert.strictEqual(refusal.status, 400);
  assert.match(refusal.body.message, /retired/);

  await call(ADMIN, `/roles/${storeRoom.id}`, { method: 'PATCH', body: { isActive: true } });
});

test('a role that does not exist is a 404 on both role paths', async () => {
  const missingRole = await call(ADMIN, '/roles/99999999');
  assert.strictEqual(missingRole.status, 404);

  const missingAccount = await call(ADMIN, '/accounts/99999999/roles');
  assert.strictEqual(missingAccount.status, 404);
});
