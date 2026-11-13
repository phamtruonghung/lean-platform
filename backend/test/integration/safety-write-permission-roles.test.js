/*
 * The Safety write retrofit (ADR-0061, issue #537), over HTTP against a real
 * database and a real local session — the seam safety-permission-roles.test.js,
 * safety-incidents.test.js and safety-incident-concern.test.js already
 * establish.
 *
 * Two claims, and this file is the only place either is measured.
 *
 * **The retrofit narrows nobody.** The four routes this slice gates — a
 * severity correction, a classification, the days and the close — stood on
 * `requireSafetyIncidentSafetyAuthority`, which asks `canAct({ safety: true })`:
 * Safety authority on a Grant at the incident's Org Unit, a flag any role may
 * carry. Two of them now also ask `SAF_CLASSIFY`, which the seed declared
 * supervisor-and-above, so `1804000000000_safety-write-codes.js` widens it onto
 * the default group and ROLE_OPERATOR. The officer below is exactly the caller
 * that widening protects: `app_users.role = operator`, no supervisor role, and
 * Safety authority on its own line. Its whole day — record, correct the
 * severity, classify, record the days, close — is 2xx.
 *
 * **The code is what the route asks, not decoration.** A gate that admits
 * everyone is easy to write and easy to get wrong: a route with no middleware at
 * all passes every "the seeded role gets 2xx" test. So each code is also proven
 * to refuse, by doing what an administrator would do — taking the code off every
 * role for the length of one request, and putting it back. The refusal is then
 * 403 `PERMISSION_REQUIRED` naming that exact code, before any row is read.
 * `withoutTheCode` captures the rows it removes and restores them in a
 * `finally`, so the seed is left exactly as it was found.
 *
 * **And the code does not replace the standing behind it.** `SAF_CLASSIFY` is
 * seeded on every role after this slice's migration, so a caller can hold the
 * door and still not hold the authority: an operator with an edit Grant and no
 * Safety authority is refused on all four routes by the helper — the helper's
 * own message, not `PERMISSION_REQUIRED` — which is the half a code-only gate
 * would silently have dropped.
 *
 * Needs a database with every migration applied, including
 * 1804000000000_safety-write-codes.js. Set DATABASE_URL first — see the
 * README's Tests section.
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
const insertedIncidentIds = [];
const insertedInjuryTypeCodes = [];

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

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

// `grants` are `{ orgUnitId, write, safety }` pairs; `write` defaults to true,
// since every Account in this file records, and `safety` defaults to false —
// the one Account that holds Safety authority says so.
async function insertAccount({ role = 'operator', displayName = null, grants = [] } = {}) {
  const subject = uniqueCode('swacct');
  const name = displayName ?? `Safety Write Account ${subject}`;
  const { rows: [account] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status)
     VALUES ($1, $2, $3, $4, TRUE, 'approved') RETURNING id`,
    [`${subject}@example.com`, name, role, subject]
  );
  insertedAccountIds.push(account.id);

  for (const grant of grants) {
    await pool.query(
      `INSERT INTO app_user_org_units (app_user_id, org_unit_id, can_write, safety_authority)
       VALUES ($1, $2, $3, $4)`,
      [account.id, grant.orgUnitId, grant.write ?? true, grant.safety ?? false]
    );
  }

  return { id: account.id, role, token: await authHeader(subject) };
}

async function insertSite() {
  const { rows: [site] } = await pool.query(
    `INSERT INTO sites (code, name, timezone) VALUES ($1, $2, $3) RETURNING id`,
    [uniqueCode('SWPS'), 'Safety Write Test Site', 'Asia/Ho_Chi_Minh']
  );
  insertedSiteIds.push(site.id);
  return site;
}

async function insertOrgUnit(siteId, { parentId = null, unitType = 'area', name = 'Safety Write Area' } = {}) {
  const { rows: [orgUnit] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, $2, $3, $4, $5) RETURNING id`,
    [siteId, parentId, uniqueCode('SWOU'), name, unitType]
  );
  insertedOrgUnitIds.push(orgUnit.id);
  return orgUnit;
}

async function get(path, token) {
  return json(await fetch(`${base}${path}`, { headers: token }));
}

async function post(path, token, body) {
  return json(
    await fetch(`${base}${path}`, {
      method: 'POST',
      headers: { ...token, 'content-type': 'application/json' },
      body: JSON.stringify(body ?? {})
    })
  );
}

let adminToken;
let officer; // role operator, Safety authority on its own line: the widening's caller.
let operator; // role operator, an edit Grant and no Safety authority.
let site;
let area;
let injuryType;

// A fresh incident recorded by the officer, for a test that needs its own row.
async function recordIncident(description) {
  const recorded = await post(`/api/safety/sites/${site.id}/incidents`, officer.token, {
    orgUnitId: area.id,
    occurredAt: '2026-05-04T07:30:00Z',
    incidentType: 'injury',
    severityLevel: 'first_aid',
    description
  });
  assert.strictEqual(recorded.status, 201, JSON.stringify(recorded.body));
  insertedIncidentIds.push(recorded.body.incident.id);
  return recorded.body.incident.id;
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

  const admin = await insertAccount({ role: 'admin', displayName: 'Avery Administrator' });
  adminToken = admin.token;

  site = await insertSite();
  area = await insertOrgUnit(site.id, { name: 'Press Line' });

  officer = await insertAccount({
    role: 'operator',
    displayName: 'Ola Safety Officer',
    grants: [{ orgUnitId: area.id, write: true, safety: true }]
  });

  operator = await insertAccount({
    role: 'operator',
    displayName: 'Ola Operator',
    grants: [{ orgUnitId: area.id, write: true }]
  });

  // The catalogue row the classification names, created through the API as the
  // administrator the code allows — so this file tests the retrofit rather than
  // a hand-made row.
  const injuryTypeCode = uniqueCode('SWIT-');
  const createdType = await post('/api/safety/injury-types', adminToken, {
    code: injuryTypeCode,
    name: `Injury ${injuryTypeCode}`
  });
  assert.strictEqual(createdType.status, 201, JSON.stringify(createdType.body));
  insertedInjuryTypeCodes.push(injuryTypeCode);
  injuryType = createdType.body.injuryType;
});

test.after(async () => {
  // Children before parents: an incident names an Org Unit, and the
  // classification points at an Injury type. A rejected `test.after` hangs the
  // file on the framework's timeout and cancels the files behind it, so the
  // order here is the whole cleanup. `safety_incident_events` cascades off the
  // incidents, so the events these tests wrote need no line of their own.
  await pool.query('DELETE FROM safety_incidents WHERE id = ANY($1)', [insertedIncidentIds]);
  await pool.query('DELETE FROM injury_types WHERE code = ANY($1)', [insertedInjuryTypeCodes]);
  await pool.query('DELETE FROM app_user_org_units WHERE app_user_id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM app_users WHERE id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM org_units WHERE id = ANY($1)', [insertedOrgUnitIds]);
  await pool.query('DELETE FROM sites WHERE id = ANY($1)', [insertedSiteIds]);
  await new Promise((resolve) => server.close(resolve));
  await closePool();
});

// ---------------------------------------------------------------------------
// The premise the retrofit rests on: the officer holds both codes the gates ask
// without being a supervisor, and the migration put SAF_CLASSIFY on every role.
// ---------------------------------------------------------------------------

test('an operator with Safety authority holds both codes the four gates ask', async () => {
  const { status, body } = await get('/api/people/me', officer.token);
  assert.strictEqual(status, 200, JSON.stringify(body));
  assert.strictEqual(officer.role, 'operator', 'the officer holds no supervisor role');

  for (const code of ['SAF_INCIDENTS_RECORD', 'SAF_CLASSIFY']) {
    assert.ok(body.permissions.includes(code), `the officer must hold ${code}`);
  }

  const { rows } = await pool.query(
    `SELECT r.code
     FROM app_role_permissions arp
     JOIN app_roles r ON r.id = arp.app_role_id
     WHERE arp.permission_code = 'SAF_CLASSIFY'
     ORDER BY r.code`
  );
  assert.deepStrictEqual(
    rows.map((row) => row.code),
    [
      'ROLE_ADMIN',
      'ROLE_ENGINEER',
      'ROLE_MANAGER',
      'ROLE_OPERATOR',
      'ROLE_STANDARD',
      'ROLE_SUPERVISOR'
    ],
    'SAF_CLASSIFY sits on every seeded role after 1804000000000'
  );
});

// ---------------------------------------------------------------------------
// The officer's day: the whole reach of the four routes, as the Account the
// widening exists for. Record -> severity -> classify -> days -> close.
// ---------------------------------------------------------------------------

test('the safety officer records an incident and takes it through severity, classification, days and close', async () => {
  const incidentId = await recordIncident('Fell from the mezzanine ladder.');

  const severity = await post(`/api/safety/incidents/${incidentId}/severity`, officer.token, {
    severityLevel: 'medical_treatment',
    note: 'The clinic stitched the cut; recording it as medical treatment.'
  });
  assert.strictEqual(severity.status, 200, JSON.stringify(severity.body));
  assert.strictEqual(severity.body.incident.severityLevel, 'medical_treatment');

  const classification = await post(`/api/safety/incidents/${incidentId}/classify`, officer.token, {
    injuryTypeId: injuryType.id
  });
  assert.strictEqual(classification.status, 200, JSON.stringify(classification.body));
  assert.strictEqual(classification.body.incident.injuryTypeId, String(injuryType.id));

  const days = await post(`/api/safety/incidents/${incidentId}/days`, officer.token, {
    lostTimeDays: 0,
    restrictedDays: 0
  });
  assert.strictEqual(days.status, 200, JSON.stringify(days.body));

  const closed = await post(`/api/safety/incidents/${incidentId}/close`, officer.token, {
    note: 'Treated at the clinic, back on the line the same day.'
  });
  assert.strictEqual(closed.status, 200, JSON.stringify(closed.body));
  assert.strictEqual(closed.body.incident.status, 'closed');
});

// ---------------------------------------------------------------------------
// And the gates are wired at all. Two mutants, each removing one code from every
// role that holds it and watching exactly its own addresses start refusing.
//
// Every role that holds it, not just the default group: `effectivePermissions`
// unions the default group, the role the Account's own `app_users.role` earns
// (this officer's is ROLE_OPERATOR) and any explicit assignment, so removing a
// code from ROLE_STANDARD alone would leave the officer holding it through
// ROLE_OPERATOR — and then the mutant would prove nothing.
// ---------------------------------------------------------------------------

async function withoutTheCode(code, run) {
  const { rows } = await pool.query(
    'SELECT app_role_id FROM app_role_permissions WHERE permission_code = $1',
    [code]
  );
  assert.ok(rows.length > 0, `${code} must be seeded on at least one role`);
  await pool.query('DELETE FROM app_role_permissions WHERE permission_code = $1', [code]);
  try {
    await run();
  } finally {
    for (const row of rows) {
      await pool.query(
        'INSERT INTO app_role_permissions (app_role_id, permission_code) VALUES ($1, $2)',
        [row.app_role_id, code]
      );
    }
  }
}

test('removing SAF_CLASSIFY from every role refuses the severity and the classification, and nothing else', async () => {
  const incidentId = await recordIncident('Caught a hand between two rollers.');

  await withoutTheCode('SAF_CLASSIFY', async () => {
    for (const [path, body] of [
      [
        `/api/safety/incidents/${incidentId}/severity`,
        { severityLevel: 'medical_treatment', note: 'Recording the clinic visit.' }
      ],
      [`/api/safety/incidents/${incidentId}/classify`, { injuryTypeId: injuryType.id }]
    ]) {
      const refused = await post(path, officer.token, body);
      assert.strictEqual(refused.status, 403, `${path}: ${JSON.stringify(refused.body)}`);
      assert.strictEqual(refused.body.code, 'PERMISSION_REQUIRED');
      assert.strictEqual(refused.body.permission, 'SAF_CLASSIFY');
    }

    // A neighbouring gate is untouched: the days ask SAF_INCIDENTS_RECORD,
    // which this mutant did not remove.
    const days = await post(`/api/safety/incidents/${incidentId}/days`, officer.token, {
      lostTimeDays: 0,
      restrictedDays: 0
    });
    assert.strictEqual(days.status, 200, JSON.stringify(days.body));
  });

  // Restored, the same address answers again — the gate reads the tables on
  // every request rather than caching what it saw at sign-in.
  const allowed = await post(`/api/safety/incidents/${incidentId}/severity`, officer.token, {
    severityLevel: 'medical_treatment',
    note: 'Recorded after the code was put back.'
  });
  assert.strictEqual(allowed.status, 200, JSON.stringify(allowed.body));
});

test('removing SAF_INCIDENTS_RECORD from every role refuses the days and the close, and nothing else', async () => {
  // Recorded before the mutant: recording asks the same code, so the row has to
  // exist first.
  const incidentId = await recordIncident('Slipped on an oil patch by the press.');

  await withoutTheCode('SAF_INCIDENTS_RECORD', async () => {
    const days = await post(`/api/safety/incidents/${incidentId}/days`, officer.token, {
      lostTimeDays: 0,
      restrictedDays: 0
    });
    assert.strictEqual(days.status, 403, JSON.stringify(days.body));
    assert.strictEqual(days.body.code, 'PERMISSION_REQUIRED');
    assert.strictEqual(days.body.permission, 'SAF_INCIDENTS_RECORD');

    const closed = await post(`/api/safety/incidents/${incidentId}/close`, officer.token, {
      note: 'No time lost; closing the record.'
    });
    assert.strictEqual(closed.status, 403, JSON.stringify(closed.body));
    assert.strictEqual(closed.body.code, 'PERMISSION_REQUIRED');
    assert.strictEqual(closed.body.permission, 'SAF_INCIDENTS_RECORD');

    // A neighbouring gate is untouched: the classification asks SAF_CLASSIFY.
    const classification = await post(`/api/safety/incidents/${incidentId}/classify`, officer.token, {
      injuryTypeId: injuryType.id
    });
    assert.strictEqual(classification.status, 200, JSON.stringify(classification.body));
  });
});

// ---------------------------------------------------------------------------
// The code answers which door; the standing still answers whose Site. With both
// codes held by every role after this slice's migration, a caller can hold the
// door and not the authority — and that caller is refused by the helper, with
// the helper's own message, on all four routes.
// ---------------------------------------------------------------------------

test('the code does not replace the standing: an operator without Safety authority is refused by the helper on all four routes', async () => {
  const incidentId = await recordIncident('Twisted an ankle stepping off the platform.');

  for (const [path, body] of [
    [
      `/api/safety/incidents/${incidentId}/severity`,
      { severityLevel: 'medical_treatment', note: 'Recording the clinic visit.' }
    ],
    [`/api/safety/incidents/${incidentId}/classify`, { injuryTypeId: injuryType.id }],
    [`/api/safety/incidents/${incidentId}/days`, { lostTimeDays: 0, restrictedDays: 0 }],
    [`/api/safety/incidents/${incidentId}/close`, { note: 'Closing the record.' }]
  ]) {
    const refused = await post(path, operator.token, body);
    assert.strictEqual(refused.status, 403, `${path}: ${JSON.stringify(refused.body)}`);
    assert.notStrictEqual(
      refused.body.code,
      'PERMISSION_REQUIRED',
      `${path} must be refused by the standing, not by a code it holds`
    );
    assert.strictEqual(
      refused.body.message,
      "that decision needs Safety authority at this Safety incident's Org Unit"
    );
  }
});
