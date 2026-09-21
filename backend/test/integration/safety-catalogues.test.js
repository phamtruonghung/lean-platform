/*
 * The Injury type and Body part catalogues, over HTTP (issue #224) — the two
 * shared catalogues an injury classification draws on, exercised through the
 * same seam as quality-catalogues.test.js, whose shape this file follows
 * closely: the real app on a real socket, a real database, and a real (locally
 * issued) JWKS standing behind `src/platform/tokens.js`'s actual verification.
 *
 * Like that file, this one does not truncate `app_users`, and it does not
 * truncate `injury_types`/`body_parts` either: both arrive seeded from the
 * baseline migration (ADR-0005's one shared catalogue), so a test here asserts
 * about the rows IT created by looking them up by their own unique code rather
 * than by counting a whole table. Every row this file inserts is deleted again
 * in `test.after()`.
 *
 * Two Accounts, inserted directly: the administrator with the role alone and
 * no Grants, and an ordinary approved, active `operator`. Neither catalogue is
 * Org-Unit scoped — an Injury type and a Body part are shared reference data,
 * not records placed in the tree — so the only scope question either route
 * asks is the administrator's role, which is what the refusal tests pin down.
 *
 * Nothing here is restricted. ADR-0037 restricts three structured fields on a
 * Safety *incident*, because together they are one person's diagnosis; a list
 * of the words a plant classifies injuries with names nobody. The restriction
 * itself is exercised in safety-incidents.test.js.
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
let memberToken;

const insertedAccountIds = [];
const insertedInjuryTypeCodes = [];
const insertedBodyPartCodes = [];

let codeCounter = 0;
// Unique across processes (process.pid) and within one run (the counter), so
// two runs against one database never collide on `injury_types.code` or
// `body_parts.code`, both UNIQUE plant-wide (ADR-0005) rather than per-Site.
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

  const adminSubject = `safety-cat-admin-${process.pid}`;
  const memberSubject = `safety-cat-member-${process.pid}`;

  const { rows: [admin] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status)
     VALUES ($1, 'Safety Catalogue Admin', 'admin', $2, TRUE, 'approved') RETURNING id`,
    [`${adminSubject}@example.com`, adminSubject]
  );
  const { rows: [member] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status)
     VALUES ($1, 'Safety Catalogue Member', 'operator', $2, TRUE, 'approved') RETURNING id`,
    [`${memberSubject}@example.com`, memberSubject]
  );
  insertedAccountIds.push(admin.id, member.id);

  adminToken = await authHeader(adminSubject);
  memberToken = await authHeader(memberSubject);
});

test.after(async () => {
  await pool.query('DELETE FROM injury_types WHERE code = ANY($1)', [insertedInjuryTypeCodes]);
  await pool.query('DELETE FROM body_parts WHERE code = ANY($1)', [insertedBodyPartCodes]);
  await pool.query('DELETE FROM app_users WHERE id = ANY($1)', [insertedAccountIds]);
  await new Promise((resolve) => server.close(resolve));
  await closePool();
  await jwks.close();
});

async function createInjuryType(token, body) {
  const response = await fetch(`${base}/api/safety/injury-types`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  const result = await json(response);
  if (result.status === 201) insertedInjuryTypeCodes.push(result.body.injuryType.code);
  return result;
}

async function correctInjuryType(token, id, body) {
  const response = await fetch(`${base}/api/safety/injury-types/${id}`, {
    method: 'PATCH',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  return json(response);
}

async function listInjuryTypes(token, query = '') {
  return json(await fetch(`${base}/api/safety/injury-types${query}`, { headers: token }));
}

async function createBodyPart(token, body) {
  const response = await fetch(`${base}/api/safety/body-parts`, {
    method: 'POST',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  const result = await json(response);
  if (result.status === 201) insertedBodyPartCodes.push(result.body.bodyPart.code);
  return result;
}

async function correctBodyPart(token, id, body) {
  const response = await fetch(`${base}/api/safety/body-parts/${id}`, {
    method: 'PATCH',
    headers: { ...token, 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });
  return json(response);
}

async function listBodyParts(token, query = '') {
  return json(await fetch(`${base}/api/safety/body-parts${query}`, { headers: token }));
}

// ---------------------------------------------------------------------------
// 1. Injury types — the administrator's write surface
// ---------------------------------------------------------------------------

test('an administrator creates, corrects and deactivates an Injury type', async () => {
  const code = uniqueCode('IT');

  const created = await createInjuryType(adminToken, { code, name: 'Laceration' });
  assert.strictEqual(created.status, 201, JSON.stringify(created.body));
  assert.strictEqual(created.body.injuryType.code, code);
  assert.strictEqual(created.body.injuryType.name, 'Laceration');
  assert.strictEqual(created.body.injuryType.isActive, true);

  const id = created.body.injuryType.id;

  const corrected = await correctInjuryType(adminToken, id, { name: 'Laceration or cut' });
  assert.strictEqual(corrected.status, 200, JSON.stringify(corrected.body));
  assert.strictEqual(corrected.body.injuryType.name, 'Laceration or cut');
  assert.strictEqual(corrected.body.injuryType.code, code, 'the code is untouched');

  const deactivated = await correctInjuryType(adminToken, id, { isActive: false });
  assert.strictEqual(deactivated.status, 200, JSON.stringify(deactivated.body));
  assert.strictEqual(deactivated.body.injuryType.isActive, false);

  const reactivated = await correctInjuryType(adminToken, id, { isActive: true });
  assert.strictEqual(reactivated.status, 200);
  assert.strictEqual(reactivated.body.injuryType.isActive, true);
});

test('an Injury type code is unique across the catalogue, which every Site shares', async () => {
  const code = uniqueCode('IT');

  const first = await createInjuryType(adminToken, { code, name: 'Fracture' });
  assert.strictEqual(first.status, 201, JSON.stringify(first.body));

  const second = await createInjuryType(adminToken, { code, name: 'Broken bone' });
  assert.strictEqual(second.status, 409);
  assert.strictEqual(second.body.message, 'an Injury type with this code already exists');
});

test("an Injury type's code cannot be corrected, and its name cannot be blanked", async () => {
  const created = await createInjuryType(adminToken, { code: uniqueCode('IT'), name: 'Burn' });
  assert.strictEqual(created.status, 201, JSON.stringify(created.body));
  const id = created.body.injuryType.id;

  const renamedCode = await correctInjuryType(adminToken, id, { code: uniqueCode('IT') });
  assert.strictEqual(renamedCode.status, 400);
  assert.strictEqual(renamedCode.body.message, 'code cannot be corrected on an Injury type');

  const blanked = await correctInjuryType(adminToken, id, { name: '   ' });
  assert.strictEqual(blanked.status, 400);
  assert.strictEqual(blanked.body.message, 'name is required');
});

test('a non-administrator is refused every Injury type write, and may still read them', async () => {
  const created = await createInjuryType(adminToken, { code: uniqueCode('IT'), name: 'Sprain' });
  assert.strictEqual(created.status, 201, JSON.stringify(created.body));
  const id = created.body.injuryType.id;

  const refusedCreate = await createInjuryType(memberToken, {
    code: uniqueCode('IT'),
    name: 'Anything'
  });
  assert.strictEqual(refusedCreate.status, 403);
  assert.strictEqual(refusedCreate.body.message, 'This action requires the administrator role.');

  const refusedCorrect = await correctInjuryType(memberToken, id, { name: 'Anything' });
  assert.strictEqual(refusedCorrect.status, 403);
  assert.strictEqual(refusedCorrect.body.message, 'This action requires the administrator role.');

  const read = await listInjuryTypes(memberToken);
  assert.strictEqual(read.status, 200);
  assert.ok(
    read.body.injuryTypes.some((type) => type.id === id),
    'any active Account reads the catalogue'
  );
});

test('a deactivated Injury type leaves the default list and comes back with includeInactive', async () => {
  const created = await createInjuryType(adminToken, { code: uniqueCode('IT'), name: 'Retired' });
  assert.strictEqual(created.status, 201, JSON.stringify(created.body));
  const id = created.body.injuryType.id;

  await correctInjuryType(adminToken, id, { isActive: false });

  const active = await listInjuryTypes(memberToken);
  assert.strictEqual(active.status, 200);
  assert.ok(
    !active.body.injuryTypes.some((type) => type.id === id),
    'a deactivated entry is not offered as a choice'
  );

  const all = await listInjuryTypes(memberToken, '?includeInactive=true');
  assert.strictEqual(all.status, 200);
  assert.ok(
    all.body.injuryTypes.some((type) => type.id === id),
    'the catalogue Screen can still reach it to reactivate it'
  );
});

test('an unknown Injury type is a 404 for the administrator too, before the role is asked', async () => {
  const missing = await correctInjuryType(adminToken, 999999999, { name: 'Nothing' });
  assert.strictEqual(missing.status, 404);
  assert.strictEqual(missing.body.message, 'Injury type not found');

  const malformed = await correctInjuryType(adminToken, 'not-an-id', { name: 'Nothing' });
  assert.strictEqual(malformed.status, 404);
  assert.strictEqual(malformed.body.message, 'Injury type not found');
});

// ---------------------------------------------------------------------------
// 2. Body parts — the same catalogue with a region
// ---------------------------------------------------------------------------

test('an administrator creates, corrects and deactivates a Body part with its region', async () => {
  const code = uniqueCode('BP');

  const created = await createBodyPart(adminToken, {
    code,
    name: 'Left forearm',
    region: 'upper_limb'
  });
  assert.strictEqual(created.status, 201, JSON.stringify(created.body));
  assert.strictEqual(created.body.bodyPart.code, code);
  assert.strictEqual(created.body.bodyPart.region, 'upper_limb');
  assert.strictEqual(created.body.bodyPart.isActive, true);

  const id = created.body.bodyPart.id;

  const corrected = await correctBodyPart(adminToken, id, {
    name: 'Forearm',
    region: 'multiple'
  });
  assert.strictEqual(corrected.status, 200, JSON.stringify(corrected.body));
  assert.strictEqual(corrected.body.bodyPart.name, 'Forearm');
  assert.strictEqual(corrected.body.bodyPart.region, 'multiple');

  const deactivated = await correctBodyPart(adminToken, id, { isActive: false });
  assert.strictEqual(deactivated.status, 200);
  assert.strictEqual(deactivated.body.bodyPart.isActive, false);
});

test("a Body part's region must be one of the known set, and defaults to other", async () => {
  const refused = await createBodyPart(adminToken, {
    code: uniqueCode('BP'),
    name: 'Somewhere',
    region: 'elbow-ish'
  });
  assert.strictEqual(refused.status, 400);
  assert.strictEqual(
    refused.body.message,
    'region must be one of head, trunk, upper_limb, lower_limb, multiple, other'
  );

  const defaulted = await createBodyPart(adminToken, {
    code: uniqueCode('BP'),
    name: 'Unspecified'
  });
  assert.strictEqual(defaulted.status, 201, JSON.stringify(defaulted.body));
  assert.strictEqual(defaulted.body.bodyPart.region, 'other');
});

test('a Body part code is unique across the catalogue every Site shares', async () => {
  const code = uniqueCode('BP');

  const first = await createBodyPart(adminToken, { code, name: 'Thumb', region: 'upper_limb' });
  assert.strictEqual(first.status, 201, JSON.stringify(first.body));

  const second = await createBodyPart(adminToken, { code, name: 'Thumb again' });
  assert.strictEqual(second.status, 409);
  assert.strictEqual(second.body.message, 'a Body part with this code already exists');
});

test('a non-administrator is refused every Body part write, and may still read them', async () => {
  const created = await createBodyPart(adminToken, {
    code: uniqueCode('BP'),
    name: 'Shin',
    region: 'lower_limb'
  });
  assert.strictEqual(created.status, 201, JSON.stringify(created.body));
  const id = created.body.bodyPart.id;

  const refusedCreate = await createBodyPart(memberToken, {
    code: uniqueCode('BP'),
    name: 'Anything'
  });
  assert.strictEqual(refusedCreate.status, 403);
  assert.strictEqual(refusedCreate.body.message, 'This action requires the administrator role.');

  const refusedCorrect = await correctBodyPart(memberToken, id, { name: 'Anything' });
  assert.strictEqual(refusedCorrect.status, 403);
  assert.strictEqual(refusedCorrect.body.message, 'This action requires the administrator role.');

  const read = await listBodyParts(memberToken);
  assert.strictEqual(read.status, 200);
  assert.ok(read.body.bodyParts.some((part) => part.id === id));
  assert.deepStrictEqual(read.body.regions, [
    'head',
    'trunk',
    'upper_limb',
    'lower_limb',
    'multiple',
    'other'
  ]);
});

test('a deactivated Body part leaves the default list and comes back with includeInactive', async () => {
  const created = await createBodyPart(adminToken, { code: uniqueCode('BP'), name: 'Retired' });
  assert.strictEqual(created.status, 201, JSON.stringify(created.body));
  const id = created.body.bodyPart.id;

  await correctBodyPart(adminToken, id, { isActive: false });

  const active = await listBodyParts(memberToken);
  assert.ok(!active.body.bodyParts.some((part) => part.id === id));

  const all = await listBodyParts(memberToken, '?includeInactive=true');
  assert.ok(all.body.bodyParts.some((part) => part.id === id));
});

test('an unknown Body part is a 404 for the administrator too, before the role is asked', async () => {
  const missing = await correctBodyPart(adminToken, 999999999, { name: 'Nothing' });
  assert.strictEqual(missing.status, 404);
  assert.strictEqual(missing.body.message, 'Body part not found');
});
