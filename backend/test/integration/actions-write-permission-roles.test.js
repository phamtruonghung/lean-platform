/*
 * The Actions write retrofit (ADR-0061, issue #533), over HTTP against a real
 * database and a real local session — the seam actions.test.js, capas.test.js
 * and capa-whys.test.js already establish.
 *
 * Two claims, and this file is the only place either is measured.
 *
 * **The retrofit narrows nobody.** Every one of the sixteen write routes was
 * reachable by any Account holding the right Grant (edit, or Quality authority)
 * or a place on a CAPA team, whatever its role, because `canAct` is role-blind.
 * The six codes those routes now ask are therefore seeded on every role, and the
 * first tests below read that back: an operator — the lowest role, and the one
 * whose fixtures in capas.test.js/capa-whys.test.js assert exactly this reach —
 * carries all six and can still open a CAPA, record a measure, move a phase and
 * write a Why.
 *
 * **The code is what the route asks, not decoration.** A gate that admits
 * everyone is easy to write and easy to get wrong: a route with no middleware at
 * all passes every "the seeded role gets 2xx" test. So each code is also proven
 * to refuse, by doing what an administrator would do — taking the code off every
 * role for the length of one request, and putting it back. The refusal is then
 * 403 `PERMISSION_REQUIRED` naming that exact code, before any row is read.
 * `withoutTheCode` captures the rows it removes and restores them in a `finally`,
 * so the seed is left exactly as it was found.
 *
 * Needs a database with every migration applied, including
 * 1803800000000_actions-write-codes.js. Set DATABASE_URL first — see the
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
const insertedActionIds = [];
const insertedCapaIds = [];
const insertedQualityIssueIds = [];
const insertedProductCodes = [];
const insertedDefectCodeCodes = [];

// The six codes the sixteen write routes ask. Written once here so a route
// added without a code cannot slip through the "narrows nobody" test below.
const WRITE_CODES = [
  'ACT_CHANGE',
  'ACT_MEASURE',
  'ACT_VERIFY',
  'ACT_CAPA_OPEN',
  'ACT_CAPA_VERIFY',
  'ACT_CAPA_EFFECTIVENESS'
];

let counter = 0;
function uniqueCode(prefix) {
  counter += 1;
  return `${prefix}${process.pid}${counter}`;
}

async function authHeader(subject) {
  const token = await tokenFor(subject);
  // Concatenated rather than written as one template literal: an auth header in
  // a file's own content is masked in transit by the tooling that writes it,
  // which would land a syntax error here (capas.test.js's own note).
  return { authorization: 'Bearer ' + token };
}

// An Account, optionally holding Grants. `write` and `quality` are the two
// independent flags ADR-0035 keeps apart.
async function insertAccount({ role = 'operator', displayName = null, grants = [] } = {}) {
  const subject = uniqueCode('actwacct');
  const name = displayName ?? `Actions Write Account ${subject}`;
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

  return { id: account.id, role, token: await authHeader(subject) };
}

async function insertSite() {
  const { rows: [site] } = await pool.query(
    `INSERT INTO sites (code, name, timezone) VALUES ($1, $2, $3) RETURNING id, code, name`,
    [uniqueCode('AWPS'), 'Actions Write Test Site', 'Asia/Ho_Chi_Minh']
  );
  insertedSiteIds.push(site.id);
  return site;
}

async function insertOrgUnit(siteId, { parentId = null, unitType = 'area', name = 'Actions Unit' } = {}) {
  const { rows: [orgUnit] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, $2, $3, $4, $5) RETURNING id, name`,
    [siteId, parentId, uniqueCode('AWPOU'), name, unitType]
  );
  insertedOrgUnitIds.push(orgUnit.id);
  return orgUnit;
}

async function json(response) {
  return { status: response.status, body: await response.json().catch(() => null) };
}

async function get(path, token) {
  return json(await fetch(`${base}${path}`, { headers: token }));
}

async function post(path, token, body) {
  const response = await fetch(`${base}${path}`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body ?? {})
  });
  const payload = await json(response);
  if (payload.status === 201 && payload.body && payload.body.action) {
    insertedActionIds.push(payload.body.action.id);
  }
  if (payload.status === 201 && payload.body && payload.body.capa) {
    insertedCapaIds.push(payload.body.capa.id);
  }
  if (payload.status === 201 && payload.body && payload.body.nonconformance) {
    insertedQualityIssueIds.push(payload.body.nonconformance.id);
  }
  return payload;
}

async function patch(path, token, body) {
  const response = await fetch(`${base}${path}`, {
    method: 'PATCH',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body ?? {})
  });
  return json(response);
}

/**
 * The administrator's own edit, for the length of one assertion: take `code`
 * off every role it sits on, run `fn`, then put back exactly the rows that were
 * there. This is the reversal the Roles Screen offers (`PUT
 * /roles/:id/permissions`), done at its narrowest, and it is the only way to
 * show the code — rather than the Grant, which every caller here holds — is what
 * refuses. The restore is in a `finally` so a failing assertion cannot leave the
 * seed changed.
 */
async function withoutTheCode(code, fn) {
  const { rows } = await pool.query(
    'SELECT app_role_id FROM app_role_permissions WHERE permission_code = $1',
    [code]
  );
  const roleIds = rows.map((row) => row.app_role_id);
  assert.ok(roleIds.length > 0, `expected ${code} to be seeded on at least one role`);

  await pool.query('DELETE FROM app_role_permissions WHERE permission_code = $1', [code]);
  try {
    return await fn();
  } finally {
    for (const roleId of roleIds) {
      await pool.query(
        `INSERT INTO app_role_permissions (app_role_id, permission_code) VALUES ($1, $2)
         ON CONFLICT (app_role_id, permission_code) DO NOTHING`,
        [roleId, code]
      );
    }
  }
}

// The refusal the retrofit promises: 403, the code's own name, and none of the
// scope helpers' wording — a Grant refusal here would mean the legacy helper
// answered, which is exactly what the test is trying to rule out.
function assertRefusedByCode(answer, code) {
  assert.strictEqual(answer.status, 403, JSON.stringify(answer.body));
  assert.strictEqual(answer.body.code, 'PERMISSION_REQUIRED', JSON.stringify(answer.body));
  assert.strictEqual(answer.body.permission, code, JSON.stringify(answer.body));
}

let site;
let area;
let line;
let supervisor;
let operator;
let engineer;
let admin;
let product;
let defectCode;

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

  site = await insertSite();
  area = await insertOrgUnit(site.id, { name: 'Line area' });
  line = await insertOrgUnit(site.id, { parentId: area.id, unitType: 'line', name: 'Line 1' });

  // The same two Grants for every role: edit access on the line, and the area
  // above it for the escalation target. Whatever the codes say, the Grants are
  // never what is being tested for a refusal.
  const grants = [
    { orgUnitId: line.id, write: true, quality: true },
    { orgUnitId: area.id, write: true, quality: true }
  ];
  supervisor = await insertAccount({ role: 'supervisor', displayName: 'Line Supervisor', grants });
  operator = await insertAccount({ role: 'operator', displayName: 'Line Operator', grants });
  engineer = await insertAccount({ role: 'engineer', displayName: 'Quality Engineer', grants });
  admin = await insertAccount({ role: 'admin', displayName: 'Administrator' });

  // The catalogue a Non-conformance needs: one product, one defect code,
  // recorded by the administrator, whose codes do not gate this card's routes.
  const productCode = uniqueCode('AWP-');
  const created = await post('/api/quality/products', admin.token, {
    code: productCode,
    name: 'Recorded product',
    uomCode: 'EA'
  });
  assert.strictEqual(created.status, 201, JSON.stringify(created.body));
  insertedProductCodes.push(productCode);
  product = created.body.product;

  const defectCodeCode = uniqueCode('AWD-');
  const defect = await post('/api/quality/defect-codes', admin.token, {
    code: defectCodeCode,
    name: 'Recorded defect'
  });
  assert.strictEqual(defect.status, 201, JSON.stringify(defect.body));
  insertedDefectCodeCodes.push(defectCodeCode);
  defectCode = defect.body.defectCode;
});

test.after(async () => {
  // Children before parents, in the order concern-nonconformances.test.js and
  // capas.test.js establish: the link rows cascade from both sides, the CAPA's
  // team cascades from its CAPA, and `action_items.capa_id` must stop pointing
  // at the CAPA before the CAPA row goes.
  await pool.query('DELETE FROM action_items WHERE id = ANY($1)', [insertedActionIds]);
  if (insertedCapaIds.length > 0) {
    await pool.query('DELETE FROM capa_team_members WHERE capa_id = ANY($1)', [insertedCapaIds]);
    await pool.query('DELETE FROM capas WHERE id = ANY($1)', [insertedCapaIds]);
  }
  await pool.query('DELETE FROM quality_issues WHERE id = ANY($1)', [insertedQualityIssueIds]);
  await pool.query('DELETE FROM products WHERE code = ANY($1)', [insertedProductCodes]);
  await pool.query('DELETE FROM defect_codes WHERE code = ANY($1)', [insertedDefectCodeCodes]);
  await pool.query('DELETE FROM app_user_org_units WHERE app_user_id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM app_users WHERE id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM org_units WHERE id = ANY($1)', [insertedOrgUnitIds]);
  await pool.query('DELETE FROM sites WHERE id = ANY($1)', [insertedSiteIds]);
  await new Promise((resolve) => server.close(resolve));
  await closePool();
});

async function raiseConcern(account, { orgUnitId = line.id, title = 'The guard keeps working loose' } = {}) {
  const raised = await post(`/api/actions/sites/${site.id}/actions`, account.token, {
    actionType: 'concern',
    orgUnitId,
    title
  });
  assert.strictEqual(raised.status, 201, `raising failed: ${JSON.stringify(raised.body)}`);
  return raised.body.action;
}

async function openCapa(account, concernId) {
  const opened = await post(`/api/actions/${concernId}/capa`, account.token, {
    problemStatement: 'Two shifts running, on the same fixture.'
  });
  assert.strictEqual(opened.status, 201, `opening the CAPA failed: ${JSON.stringify(opened.body)}`);
  return opened.body.capa;
}

// ---------------------------------------------------------------------------
// 1. The retrofit narrows nobody.
// ---------------------------------------------------------------------------

test('an operator carries all six write codes, and still does the acts the suites guard', async () => {
  const me = await get('/api/people/me', operator.token);
  assert.strictEqual(me.status, 200, JSON.stringify(me.body));
  for (const code of WRITE_CODES) {
    assert.ok(me.body.permissions.includes(code), `the operator should carry ${code}`);
  }

  // The three acts capas.test.js and capa-whys.test.js assert for an
  // operator-role Account holding Quality authority, unchanged by this slice.
  const concern = await raiseConcern(operator);
  const capa = await openCapa(operator, concern.id);

  const why = await post(`/api/actions/capas/${capa.id}/whys`, operator.token, {
    chain: 'occurrence',
    statement: 'The fixture had not been re-torqued.'
  });
  assert.strictEqual(why.status, 201, JSON.stringify(why.body));

  const measure = await post(`/api/actions/${concern.id}/measures`, operator.token, {
    actionType: 'containment',
    title: 'Clamp the guard'
  });
  assert.strictEqual(measure.status, 201, JSON.stringify(measure.body));

  const phase = await post(`/api/actions/${concern.id}/phases/plan/complete`, operator.token, {
    note: 'Planned'
  });
  assert.strictEqual(phase.status, 200, JSON.stringify(phase.body));
});

// ---------------------------------------------------------------------------
// 2. ACT_MEASURE — recording an immediate measure against a Concern.
// ---------------------------------------------------------------------------

test('recording a measure asks ACT_MEASURE: a supervisor reaches it, and no role holding the code does not', async () => {
  const concern = await raiseConcern(supervisor);

  const recorded = await post(`/api/actions/${concern.id}/measures`, supervisor.token, {
    actionType: 'containment',
    title: 'Clamp the guard'
  });
  assert.strictEqual(recorded.status, 201, JSON.stringify(recorded.body));

  const refused = await withoutTheCode('ACT_MEASURE', () =>
    post(`/api/actions/${concern.id}/measures`, supervisor.token, {
      actionType: 'containment',
      title: 'Clamp the guard'
    })
  );
  assertRefusedByCode(refused, 'ACT_MEASURE');
});

// ---------------------------------------------------------------------------
// 3. ACT_VERIFY — completing the Action's open phase.
// ---------------------------------------------------------------------------

test('completing a phase asks ACT_VERIFY: a supervisor reaches it, and is refused once no role carries the code', async () => {
  const concern = await raiseConcern(supervisor);

  const completed = await post(`/api/actions/${concern.id}/phases/plan/complete`, supervisor.token, {
    note: 'Planned'
  });
  assert.strictEqual(completed.status, 200, JSON.stringify(completed.body));
  assert.strictEqual(completed.body.action.openPhase.phase, 'do');

  const refused = await withoutTheCode('ACT_VERIFY', () =>
    post(`/api/actions/${concern.id}/phases/do/complete`, supervisor.token, { note: 'Done' })
  );
  assertRefusedByCode(refused, 'ACT_VERIFY');
});

// ---------------------------------------------------------------------------
// 4. ACT_CAPA_OPEN — opening an investigation, and filling in its paperwork.
// ---------------------------------------------------------------------------

test('opening and changing a CAPA asks ACT_CAPA_OPEN: a supervisor reaches it, and is refused once no role carries the code', async () => {
  const concern = await raiseConcern(supervisor);
  const capa = await openCapa(supervisor, concern.id);

  const changed = await patch(`/api/actions/capas/${capa.id}`, supervisor.token, {
    problemStatement: 'The fixture was not re-torqued between shifts.'
  });
  assert.strictEqual(changed.status, 200, JSON.stringify(changed.body));

  const secondConcern = await raiseConcern(supervisor);
  const refusedOpen = await withoutTheCode('ACT_CAPA_OPEN', () =>
    post(`/api/actions/${secondConcern.id}/capa`, supervisor.token, { problemStatement: 'Refused' })
  );
  assertRefusedByCode(refusedOpen, 'ACT_CAPA_OPEN');

  const refusedChange = await withoutTheCode('ACT_CAPA_OPEN', () =>
    patch(`/api/actions/capas/${capa.id}`, supervisor.token, { problemStatement: 'Refused' })
  );
  assertRefusedByCode(refusedChange, 'ACT_CAPA_OPEN');
});

// ---------------------------------------------------------------------------
// 5. ACT_CAPA_VERIFY — the investigation's own reasoning: its Why chains and
// its fishbone.
// ---------------------------------------------------------------------------

test('writing a Why or a cause asks ACT_CAPA_VERIFY: an engineer reaches it, and is refused once no role carries the code', async () => {
  const concern = await raiseConcern(supervisor);
  const capa = await openCapa(supervisor, concern.id);

  const written = await post(`/api/actions/capas/${capa.id}/whys`, engineer.token, {
    chain: 'occurrence',
    statement: 'The fixture had not been re-torqued.'
  });
  assert.strictEqual(written.status, 201, JSON.stringify(written.body));

  const cause = await post(`/api/actions/capas/${capa.id}/causes`, engineer.token, {
    category: 'machine',
    statement: 'The fixture works loose over a shift.'
  });
  assert.strictEqual(cause.status, 201, JSON.stringify(cause.body));

  const refusedWhy = await withoutTheCode('ACT_CAPA_VERIFY', () =>
    post(`/api/actions/capas/${capa.id}/whys`, engineer.token, {
      chain: 'escape',
      statement: 'Refused'
    })
  );
  assertRefusedByCode(refusedWhy, 'ACT_CAPA_VERIFY');

  const refusedCause = await withoutTheCode('ACT_CAPA_VERIFY', () =>
    post(`/api/actions/capas/${capa.id}/causes`, engineer.token, {
      category: 'method',
      statement: 'Refused'
    })
  );
  assertRefusedByCode(refusedCause, 'ACT_CAPA_VERIFY');
});

// ---------------------------------------------------------------------------
// 6. ACT_CAPA_EFFECTIVENESS — whether the measures held.
// ---------------------------------------------------------------------------

test('the effectiveness check asks ACT_CAPA_EFFECTIVENESS: an engineer reaches it, and is refused once no role carries the code', async () => {
  const concern = await raiseConcern(supervisor);
  const capa = await openCapa(supervisor, concern.id);

  // The gate admits this engineer: the answer is the service's own 409 about
  // the Concern not being closed, never a refusal by the code.
  const reached = await post(`/api/actions/capas/${capa.id}/effectiveness`, engineer.token, {
    outcome: 'effective',
    note: 'Held for two shifts.'
  });
  assert.strictEqual(reached.status, 409, JSON.stringify(reached.body));
  assert.notStrictEqual(reached.body.code, 'PERMISSION_REQUIRED', JSON.stringify(reached.body));

  const refused = await withoutTheCode('ACT_CAPA_EFFECTIVENESS', () =>
    post(`/api/actions/capas/${capa.id}/effectiveness`, engineer.token, {
      outcome: 'effective',
      note: 'Held for two shifts.'
    })
  );
  assertRefusedByCode(refused, 'ACT_CAPA_EFFECTIVENESS');
});

// ---------------------------------------------------------------------------
// 7. ACT_CHANGE — the four acts the catalogue had no code for.
// ---------------------------------------------------------------------------

test('escalating and calling an Action off ask ACT_CHANGE: a supervisor reaches them, and is refused once no role carries the code', async () => {
  const escalated = await raiseConcern(supervisor);
  const handedUp = await post(`/api/actions/${escalated.id}/escalate`, supervisor.token, {
    orgUnitId: area.id
  });
  assert.strictEqual(handedUp.status, 200, JSON.stringify(handedUp.body));

  const calledOff = await raiseConcern(supervisor);
  const cancelled = await post(`/api/actions/${calledOff.id}/cancel`, supervisor.token, {
    reason: 'Raised against the wrong line'
  });
  assert.strictEqual(cancelled.status, 200, JSON.stringify(cancelled.body));

  const refusedEscalate = await withoutTheCode('ACT_CHANGE', () =>
    post(`/api/actions/${escalated.id}/escalate`, supervisor.token, { orgUnitId: area.id })
  );
  assertRefusedByCode(refusedEscalate, 'ACT_CHANGE');

  const anotherConcern = await raiseConcern(supervisor);
  const refusedCancel = await withoutTheCode('ACT_CHANGE', () =>
    post(`/api/actions/${anotherConcern.id}/cancel`, supervisor.token, { reason: 'Refused' })
  );
  assertRefusedByCode(refusedCancel, 'ACT_CHANGE');
});

test('linking and unlinking a Non-conformance ask ACT_CHANGE: a supervisor reaches it, and is refused once no role carries the code', async () => {
  const recorded = await post(`/api/quality/sites/${site.id}/nonconformances`, admin.token, {
    orgUnitId: line.id,
    productId: product.id,
    defectCodeId: defectCode.id,
    detectionPoint: 'in_process',
    quantity: 5
  });
  assert.strictEqual(recorded.status, 201, JSON.stringify(recorded.body));
  const nonconformanceId = recorded.body.nonconformance.id;
  insertedQualityIssueIds.push(nonconformanceId);

  const concern = await raiseConcern(supervisor);

  const linked = await post(`/api/actions/${concern.id}/nonconformances`, supervisor.token, {
    nonconformanceId
  });
  assert.strictEqual(linked.status, 201, JSON.stringify(linked.body));

  const unlinked = await post(
    `/api/actions/${concern.id}/nonconformances/${nonconformanceId}/unlink`,
    supervisor.token,
    {}
  );
  assert.strictEqual(unlinked.status, 200, JSON.stringify(unlinked.body));

  // Refused before the id is even looked up: the code runs in front of the
  // route's own existence check, deliberately.
  const refusedLink = await withoutTheCode('ACT_CHANGE', () =>
    post(`/api/actions/${concern.id}/nonconformances`, supervisor.token, { nonconformanceId })
  );
  assertRefusedByCode(refusedLink, 'ACT_CHANGE');

  const refusedUnlink = await withoutTheCode('ACT_CHANGE', () =>
    post(`/api/actions/${concern.id}/nonconformances/${nonconformanceId}/unlink`, supervisor.token, {})
  );
  assertRefusedByCode(refusedUnlink, 'ACT_CHANGE');
});

// ---------------------------------------------------------------------------
// 8. The administrator's short-circuit: no Grant at all, every write answers.
// ---------------------------------------------------------------------------

test('an administrator with no Grants reaches the writes through the code short-circuit', async () => {
  const measured = await raiseConcern(admin);
  const measure = await post(`/api/actions/${measured.id}/measures`, admin.token, {
    actionType: 'containment',
    title: 'Adjusted the guard'
  });
  assert.strictEqual(measure.status, 201, JSON.stringify(measure.body));

  const phase = await post(`/api/actions/${measured.id}/phases/plan/complete`, admin.token, {
    note: 'Planned'
  });
  assert.strictEqual(phase.status, 200, JSON.stringify(phase.body));

  // A second Concern, because a Concern with an open measure cannot be called
  // off (409) — this is the service's own rule, and it is not what is under test.
  const calledOff = await raiseConcern(admin);
  const cancelled = await post(`/api/actions/${calledOff.id}/cancel`, admin.token, {
    reason: 'Raised by mistake'
  });
  assert.strictEqual(cancelled.status, 200, JSON.stringify(cancelled.body));
});
