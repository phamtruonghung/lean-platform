/*
 * The People and KPI write retrofit (ADR-0061, phase 2d, issue #539), over HTTP
 * against a real database and a real local session — the seam
 * people-permission-roles.test.js, floor-training.test.js, kpi.test.js and
 * org-unit-import.test.js already establish.
 *
 * Three claims, and this file is where each is measured against the whole
 * surface the slice touched.
 *
 * **An administrator still reaches every door.** Every route here is a write an
 * administrator could make before the slice and must still make after it: the
 * Site and Org Unit writes, the technician credential, an Employee assignment
 * and an Account write. A retrofit that answered 403 to the administrator would
 * be a regression this test catches before a plant does.
 *
 * **A supervisor is refused what became administrator authority.** The bound-
 * ary writes (`PATCH /org-units/:id`, a child Org Unit, the tree import) and the
 * Employee assignment stood on an edit Grant alone; they now ask
 * `PPL_ORG_UNITS_CHANGE` / `PPL_DIRECTORY_CHANGE` as well, which the seed declares
 * on ROLE_ADMIN alone. So a supervisor holding the same Grant is refused by the
 * code — the delta this slice's PR body and directory-routes.js's own header
 * state — and `POST /sites`, always administrator-only, keeps refusing it.
 *
 * **The floor device's door is not one of them.** `POST
 * /floor/training/trainees/:traineeId/answer` has no Account on its path at all
 * (ADR-0016, slice 5b): `x-floor-device` and `x-technician-identification` are
 * its whole authority. Adding a code there would refuse every tablet in the
 * plant, so this file pins that the answer still lands — with the Employee as
 * actor and no Account — and that the same request without the identification
 * is 401.
 *
 * The gates are also mutated rather than only satisfied: taking a code off every
 * role that holds it and watching exactly its own door start refusing, then
 * putting it back, is what makes "the code is asked" a measurement rather than a
 * decoration. `withoutTheCode` restores the seed in a `finally`.
 *
 * Needs a database with every migration applied, including
 * 1804100000000_kpi-catalogue-write-roles.js. Set DATABASE_URL first — see the
 * README's Tests section.
 */

const test = require('node:test');
const assert = require('node:assert');
const { tokenFor } = require('../helpers/session');
const { temporaryCode } = require('../helpers/permissions');

let server;
let base;
let pool;
let closePool;

const insertedAccountIds = [];
const insertedSiteIds = [];
const insertedOrgUnitIds = [];
const insertedEmployeeIds = [];
const insertedDeviceIds = [];
const insertedRecordIds = [];

let counter = 0;
function uniqueCode(prefix) {
  counter += 1;
  return `${prefix}${process.pid}${counter}`;
}

async function authHeader(subject) {
  const token = await tokenFor(subject);
  return { authorization: 'Bearer ' + token };
}

async function json(response) {
  return { status: response.status, body: await response.json().catch(() => null) };
}

async function request(method, path, headers, body) {
  const response = await fetch(`${base}${path}`, {
    method,
    headers: { ...headers, ...(body === undefined ? {} : { 'content-type': 'application/json' }) },
    body: body === undefined ? undefined : JSON.stringify(body)
  });
  return json(response);
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

async function insertAccount({ role = 'operator', approvalStatus = 'approved', grants = [] } = {}) {
  const subject = uniqueCode('pwacct');
  const { rows: [account] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status)
     VALUES ($1, $2, $3, $4, TRUE, $5) RETURNING id`,
    [`${subject}@example.com`, `People Write Account ${subject}`, role, subject, approvalStatus]
  );
  insertedAccountIds.push(account.id);

  for (const grant of grants) {
    await pool.query(
      `INSERT INTO app_user_org_units (app_user_id, org_unit_id, can_write)
       VALUES ($1, $2, $3)`,
      [account.id, grant.orgUnitId, grant.write !== false]
    );
  }

  return { id: account.id, token: await authHeader(subject) };
}

async function insertSite() {
  const { rows: [site] } = await pool.query(
    `INSERT INTO sites (code, name, timezone)
     VALUES ($1, 'People Write Test Site', 'Asia/Ho_Chi_Minh') RETURNING id, code, name, timezone`,
    [uniqueCode('PWS')]
  );
  insertedSiteIds.push(site.id);
  return site;
}

async function insertOrgUnit(siteId, { parentId = null, unitType = 'area', name = 'People Write Unit' } = {}) {
  const { rows: [orgUnit] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, $2, $3, $4, $5) RETURNING id, code, name`,
    [siteId, parentId, uniqueCode('PWOU'), name, unitType]
  );
  insertedOrgUnitIds.push(orgUnit.id);
  return orgUnit;
}

async function insertEmployee(displayName = 'Pat Person') {
  const [firstName, ...rest] = displayName.split(' ');
  const { rows: [employee] } = await pool.query(
    `INSERT INTO employees (employee_no, first_name, last_name, is_active)
     VALUES ($1, $2, $3, TRUE) RETURNING id, employee_no, display_name`,
    [uniqueCode('PWEMP'), firstName, rest.join(' ') || 'Employee']
  );
  insertedEmployeeIds.push(employee.id);
  return employee;
}

async function insertTraineeRow({ orgUnit, employee, trainer, status = 'sent', title = 'Phase 2d training' }) {
  const { rows: [record] } = await pool.query(
    `INSERT INTO training_records (site_id, org_unit_id, number, title, trained_on, duration_hours,
                                   trainer_employee_id, objective, status, sent_at, sent_by_account_id)
     VALUES ($1, $2, $3, $4, '2026-03-10', 1.5, $5, 'Know the lockout steps', $6,
             CASE WHEN $6 = 'sent' THEN now() END,
             CASE WHEN $6 = 'sent' THEN $7::bigint END)
     RETURNING id`,
    [site.id, orgUnit.id, uniqueCode('TR-PW-'), title, trainer.id, status, admin.id]
  );
  insertedRecordIds.push(record.id);
  const { rows: [trainee] } = await pool.query(
    'INSERT INTO training_trainees (training_record_id, employee_id) VALUES ($1, $2) RETURNING id',
    [record.id, employee.id]
  );
  return trainee.id;
}

// ---------------------------------------------------------------------------
// Codes, taken off every role that holds them and put back.
// ---------------------------------------------------------------------------

async function removeCodeEverywhere(code) {
  const { rows } = await pool.query(
    'SELECT app_role_id FROM app_role_permissions WHERE permission_code = $1',
    [code]
  );
  assert.ok(rows.length > 0, `${code} must be seeded on at least one role`);
  await pool.query('DELETE FROM app_role_permissions WHERE permission_code = $1', [code]);
  return rows.map((row) => row.app_role_id);
}

async function restoreCodeEverywhere(roleIds, code) {
  for (const roleId of roleIds) {
    await pool.query(
      `INSERT INTO app_role_permissions (app_role_id, permission_code) VALUES ($1, $2)
       ON CONFLICT (app_role_id, permission_code) DO NOTHING`,
      [roleId, code]
    );
  }
}

async function withoutTheCode(code, run) {
  const roleIds = await removeCodeEverywhere(code);
  try {
    return await run();
  } finally {
    await restoreCodeEverywhere(roleIds, code);
  }
}

// ---------------------------------------------------------------------------
// Setup
// ---------------------------------------------------------------------------

let admin;
let supervisor; // an edit Grant on the whole area, and no code beyond its role
let site;
let area;
let cell;
let elsewhere;
let employee;
let trainer;
let technician;
let deviceCredential;
let identification;

test.before(async () => {
  process.env.BACKEND_PORT = '0';
  // The KPI claim below is about the code, not the catalogue: leave the MTU
  // catalogue unconfigured so `requireCatalogueConfigured` answers its 503
  // behind the gate, deterministically.
  delete process.env.MTU_DATABASE_URL;

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
  site = await insertSite();
  area = await insertOrgUnit(site.id, { name: 'People Write Area' });
  cell = await insertOrgUnit(site.id, { parentId: area.id, unitType: 'cell', name: 'People Write Cell' });
  elsewhere = await insertOrgUnit(site.id, { unitType: 'area', name: 'People Write Elsewhere' });

  supervisor = await insertAccount({
    role: 'supervisor',
    grants: [{ orgUnitId: area.id, write: true }]
  });

  employee = await insertEmployee('Wes Worker');
  trainer = await insertEmployee('Tina Trainer');
  technician = await insertEmployee('Terry Technician');

  // A device on the area and a PIN for the technician: only an administrator
  // registers a device, and the credential write is one of the routes below.
  const registered = await request('POST', '/api/maintenance/floor-devices', admin.token, {
    orgUnitId: area.id,
    name: 'People Write terminal'
  });
  assert.strictEqual(registered.status, 201, JSON.stringify(registered.body));
  insertedDeviceIds.push(registered.body.device.id);
  deviceCredential = registered.body.credential;

  const pin = await request(
    'PUT',
    `/api/maintenance/floor-technician-credentials/${technician.id}`,
    admin.token,
    { pin: '4321' }
  );
  assert.strictEqual(pin.status, 200, JSON.stringify(pin.body));

  const identified = await request(
    'POST',
    '/api/maintenance/floor/identify',
    { 'x-floor-device': deviceCredential },
    { employeeNo: technician.employee_no, pin: '4321' }
  );
  assert.strictEqual(identified.status, 200, JSON.stringify(identified.body));
  identification = identified.body.identification;
});

test.after(async () => {
  await pool.query('DELETE FROM employee_assignments WHERE employee_id = ANY($1)', [insertedEmployeeIds]);
  await pool.query('DELETE FROM training_trainees WHERE training_record_id = ANY($1)', [insertedRecordIds]);
  await pool.query('DELETE FROM training_records WHERE id = ANY($1)', [insertedRecordIds]);
  await pool.query('DELETE FROM technician_identifications WHERE floor_device_id = ANY($1)', [insertedDeviceIds]);
  await pool.query('DELETE FROM employee_floor_credentials WHERE employee_id = ANY($1)', [insertedEmployeeIds]);
  await pool.query('DELETE FROM floor_devices WHERE id = ANY($1)', [insertedDeviceIds]);
  await pool.query('DELETE FROM app_user_org_units WHERE app_user_id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM app_users WHERE id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM employees WHERE id = ANY($1)', [insertedEmployeeIds]);
  await pool.query('DELETE FROM org_units WHERE id = ANY($1)', [[...insertedOrgUnitIds].reverse()]);
  await pool.query('DELETE FROM sites WHERE id = ANY($1)', [insertedSiteIds]);

  await new Promise((resolve) => server.close(resolve));
  await closePool();
});

// ---------------------------------------------------------------------------
// 1. An administrator reaches every door this slice touched.
// ---------------------------------------------------------------------------

test('an administrator reaches the Site, Org Unit, directory and credential writes', async () => {
  const created = await request('POST', '/api/people/sites', admin.token, {
    code: uniqueCode('NEWSITE'),
    name: 'A Site an administrator created',
    timezone: 'Asia/Ho_Chi_Minh'
  });
  assert.strictEqual(created.status, 201, JSON.stringify(created.body));
  insertedSiteIds.push(created.body.site.id);

  const corrected = await request('PATCH', `/api/people/sites/${created.body.site.id}`, admin.token, {
    code: created.body.site.code,
    name: 'A Site an administrator corrected',
    timezone: 'Asia/Ho_Chi_Minh'
  });
  assert.strictEqual(corrected.status, 200, JSON.stringify(corrected.body));
  assert.strictEqual(corrected.body.site.name, 'A Site an administrator corrected');

  // A root Org Unit, then a child beneath an existing one: the two branches of
  // POST /sites/:siteId/org-units, both behind the same code.
  const root = await request('POST', `/api/people/sites/${created.body.site.id}/org-units`, admin.token, {
    code: uniqueCode('ROOT'),
    name: 'A root an administrator created',
    unitType: 'area'
  });
  assert.strictEqual(root.status, 201, JSON.stringify(root.body));
  insertedOrgUnitIds.push(root.body.orgUnit.id);

  const child = await request('POST', `/api/people/sites/${created.body.site.id}/org-units`, admin.token, {
    code: uniqueCode('CHILD'),
    name: 'A child an administrator created',
    unitType: 'line',
    parentId: root.body.orgUnit.id
  });
  assert.strictEqual(child.status, 201, JSON.stringify(child.body));
  insertedOrgUnitIds.push(child.body.orgUnit.id);

  const imported = await request('POST', `/api/people/sites/${site.id}/org-units/import`, admin.token, {
    orgUnits: [
      { code: uniqueCode('IMP'), name: 'Imported beneath the area', unitType: 'cell', parentCode: area.code }
    ]
  });
  assert.strictEqual(imported.status, 201, JSON.stringify(imported.body));
  for (const row of imported.body.orgUnits) insertedOrgUnitIds.push(row.id);

  const deactivated = await request('PATCH', `/api/people/org-units/${elsewhere.id}`, admin.token, {
    isActive: false
  });
  assert.strictEqual(deactivated.status, 200, JSON.stringify(deactivated.body));
  assert.strictEqual(deactivated.body.orgUnit.isActive, false);

  const assignment = await request('POST', `/api/people/employees/${employee.id}/assignments`, admin.token, {
    orgUnitId: cell.id
  });
  assert.strictEqual(assignment.status, 201, JSON.stringify(assignment.body));
});

// ---------------------------------------------------------------------------
// 2. A supervisor with the same edit Grant is refused, by code.
// ---------------------------------------------------------------------------

test('a supervisor is refused POST /sites and the Org Unit and directory writes by their codes', async () => {
  const rootCreate = await request('POST', '/api/people/sites', supervisor.token, {
    code: uniqueCode('NOPE'),
    name: 'Should not exist',
    timezone: 'Asia/Ho_Chi_Minh'
  });
  assert.strictEqual(rootCreate.status, 403, JSON.stringify(rootCreate.body));
  assert.strictEqual(rootCreate.body.code, 'PERMISSION_REQUIRED');
  assert.strictEqual(rootCreate.body.permission, 'PPL_ORG_UNITS_CHANGE');

  // This one is a narrowing the slice states: the supervisor holds a write
  // Grant on `area`, and before phase 2d that was enough to deactivate it.
  const deactivate = await request('PATCH', `/api/people/org-units/${cell.id}`, supervisor.token, {
    isActive: false
  });
  assert.strictEqual(deactivate.status, 403, JSON.stringify(deactivate.body));
  assert.strictEqual(deactivate.body.permission, 'PPL_ORG_UNITS_CHANGE');

  const childCreate = await request('POST', `/api/people/sites/${site.id}/org-units`, supervisor.token, {
    code: uniqueCode('NOPE2'),
    name: 'Should not exist either',
    unitType: 'cell',
    parentId: area.id
  });
  assert.strictEqual(childCreate.status, 403, JSON.stringify(childCreate.body));
  assert.strictEqual(childCreate.body.permission, 'PPL_ORG_UNITS_CHANGE');

  const imported = await request('POST', `/api/people/sites/${site.id}/org-units/import`, supervisor.token, {
    orgUnits: [{ code: uniqueCode('NOPE3'), name: 'Nope', unitType: 'cell', parentCode: area.code }]
  });
  assert.strictEqual(imported.status, 403, JSON.stringify(imported.body));
  assert.strictEqual(imported.body.permission, 'PPL_ORG_UNITS_CHANGE');

  const corrected = await request('PATCH', `/api/people/sites/${site.id}`, supervisor.token, {
    code: site.code,
    name: 'Should not be corrected',
    timezone: 'Asia/Ho_Chi_Minh'
  });
  assert.strictEqual(corrected.status, 403, JSON.stringify(corrected.body));
  assert.strictEqual(corrected.body.permission, 'PPL_ORG_UNITS_CHANGE');

  // The directory half: the credential and the assignment, both narrowed.
  const pin = await request(
    'PUT',
    `/api/maintenance/floor-technician-credentials/${technician.id}`,
    supervisor.token,
    { pin: '9999' }
  );
  assert.strictEqual(pin.status, 403, JSON.stringify(pin.body));
  assert.strictEqual(pin.body.permission, 'PPL_DIRECTORY_CHANGE');

  const assignment = await request('POST', `/api/people/employees/${employee.id}/assignments`, supervisor.token, {
    orgUnitId: cell.id
  });
  assert.strictEqual(assignment.status, 403, JSON.stringify(assignment.body));
  assert.strictEqual(assignment.body.permission, 'PPL_DIRECTORY_CHANGE');
});

test('a supervisor lent PPL_ORG_UNITS_CHANGE reaches POST /sites, and loses it when every role is stripped of the code', async () => {
  // An administrator answers every code before a role set is read, so only a
  // non-administrator can show the gate refusing: the code is lent to the
  // supervisor's role, then taken off every role for one request.
  const release = await temporaryCode(pool, 'ROLE_SUPERVISOR', 'PPL_ORG_UNITS_CHANGE');
  try {
    const held = await request('POST', '/api/people/sites', supervisor.token, {
      code: uniqueCode('LENT'),
      name: 'A Site the lent code admits',
      timezone: 'Asia/Ho_Chi_Minh'
    });
    assert.strictEqual(held.status, 201, JSON.stringify(held.body));
    insertedSiteIds.push(held.body.site.id);

    const refused = await withoutTheCode('PPL_ORG_UNITS_CHANGE', () =>
      request('POST', '/api/people/sites', supervisor.token, {
        code: uniqueCode('STRIPPED'),
        name: 'Refused while the code is gone',
        timezone: 'Asia/Ho_Chi_Minh'
      })
    );
    assert.strictEqual(refused.status, 403, JSON.stringify(refused.body));
    assert.strictEqual(refused.body.code, 'PERMISSION_REQUIRED');
    assert.strictEqual(refused.body.permission, 'PPL_ORG_UNITS_CHANGE');
  } finally {
    await release();
  }
});

// ---------------------------------------------------------------------------
// 3. The floor device's door carries an identification, not a code.
// ---------------------------------------------------------------------------

test('a supervisor reaches the floor training answer with the technician identification, and no Account is needed', async () => {
  const traineeId = await insertTraineeRow({ orgUnit: area, employee: technician, trainer });
  const headers = {
    'x-floor-device': deviceCredential,
    'x-technician-identification': identification
  };

  const answered = await request(
    'POST',
    `/api/maintenance/floor/training/trainees/${traineeId}/answer`,
    headers,
    { answer: 'confirmed' }
  );
  assert.strictEqual(answered.status, 200, JSON.stringify(answered.body));

  const { rows: [row] } = await pool.query(
    `SELECT answer, answered_by_account_id, answered_by_employee_id
       FROM training_trainees WHERE id = $1`,
    [traineeId]
  );
  assert.strictEqual(row.answer, 'confirmed');
  assert.strictEqual(String(row.answered_by_employee_id), String(technician.id));
  assert.strictEqual(row.answered_by_account_id, null, 'no Account is on this path');

  // The identification is the authority: the same request behind a supervisor's
  // own bearer token, with no device headers, is refused 401 — a code would have
  // read `req.account` and taken the tablet's answer away.
  const withoutIdentification = await request(
    'POST',
    `/api/maintenance/floor/training/trainees/${traineeId}/answer`,
    supervisor.token,
    { answer: 'confirmed' }
  );
  assert.strictEqual(withoutIdentification.status, 401, JSON.stringify(withoutIdentification.body));
});

// ---------------------------------------------------------------------------
// 4. The two Account writes and their codes.
// ---------------------------------------------------------------------------

test('an administrator reaches the Account writes, and a stripped ADM_ACCOUNTS_CHANGE refuses a supervisor lent the code', async () => {
  const target = await insertAccount({ role: 'operator' });

  // The link first: an Account that is already switched off may be refused by
  // its own approval state, and this test is about the code, not that rule.
  const link = await request('PUT', `/api/people/accounts/${target.id}/employee`, admin.token, {
    employeeId: employee.id
  });
  assert.strictEqual(link.status, 200, JSON.stringify(link.body));

  const deactivated = await request('PATCH', `/api/people/accounts/${target.id}`, admin.token, {
    isActive: false
  });
  assert.strictEqual(deactivated.status, 200, JSON.stringify(deactivated.body));

  const release = await temporaryCode(pool, 'ROLE_SUPERVISOR', 'ADM_ACCOUNTS_CHANGE');
  try {
    const held = await request('PATCH', `/api/people/accounts/${target.id}`, supervisor.token, {
      isActive: true
    });
    assert.strictEqual(held.status, 200, JSON.stringify(held.body));

    const refused = await withoutTheCode('ADM_ACCOUNTS_CHANGE', () =>
      request('PATCH', `/api/people/accounts/${target.id}`, supervisor.token, { isActive: false })
    );
    assert.strictEqual(refused.status, 403, JSON.stringify(refused.body));
    assert.strictEqual(refused.body.code, 'PERMISSION_REQUIRED');
    assert.strictEqual(refused.body.permission, 'ADM_ACCOUNTS_CHANGE');
  } finally {
    await release();
  }
});

test('a supervisor lent ADM_APPROVALS_DECIDE decides an Approval, and is refused by its absence', async () => {
  const pending = await insertAccount({ role: 'operator', approvalStatus: 'pending' });

  const release = await temporaryCode(pool, 'ROLE_SUPERVISOR', 'ADM_APPROVALS_DECIDE');
  try {
    const decided = await request('POST', `/api/people/accounts/${pending.id}/approval`, supervisor.token, {
      role: 'operator',
      grants: []
    });
    assert.strictEqual(decided.status, 200, JSON.stringify(decided.body));

    const refused = await withoutTheCode('ADM_APPROVALS_DECIDE', () =>
      request('POST', `/api/people/accounts/${pending.id}/rejection`, supervisor.token, {})
    );
    assert.strictEqual(refused.status, 403, JSON.stringify(refused.body));
    assert.strictEqual(refused.body.permission, 'ADM_APPROVALS_DECIDE');
  } finally {
    await release();
  }
});

// ---------------------------------------------------------------------------
// 5. The KPI catalogue writes: seeded wide enough for the Screen, and asked.
// ---------------------------------------------------------------------------

test('a supervisor holds INS_KPI_CATALOGUE_CHANGE, and a role stripped of it is refused POST /catalogue', async () => {
  // The catalogue is unconfigured in this file, so a caller who holds the code
  // meets requireCatalogueConfigured's 503 — past the gate, which is the point.
  const held = await request('POST', '/api/kpi/catalogue', supervisor.token, {});
  assert.strictEqual(held.status, 503, JSON.stringify(held.body));

  const refused = await withoutTheCode('INS_KPI_CATALOGUE_CHANGE', () =>
    request('POST', '/api/kpi/catalogue', supervisor.token, {})
  );
  assert.strictEqual(refused.status, 403, JSON.stringify(refused.body));
  assert.strictEqual(refused.body.code, 'PERMISSION_REQUIRED');
  assert.strictEqual(refused.body.permission, 'INS_KPI_CATALOGUE_CHANGE');

  const targets = await withoutTheCode('INS_KPI_CATALOGUE_CHANGE', () =>
    request('POST', '/api/kpi/targets', supervisor.token, {})
  );
  assert.strictEqual(targets.status, 403, JSON.stringify(targets.body));
  assert.strictEqual(targets.body.permission, 'INS_KPI_CATALOGUE_CHANGE');
});
