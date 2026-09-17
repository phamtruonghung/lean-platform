/*
 * The Product and Defect code catalogues, over HTTP (issue #203) — the first
 * slice of the Quality Module, exercised through the same seam as
 * plant.test.js/approval.test.js: the real app on a real socket, a real
 * database, and a real (locally issued) JWKS standing behind
 * `src/platform/tokens.js`'s actual verification.
 *
 * Like plant.test.js, this file does not truncate `app_users` — that table is
 * shared with accounts.test.js's own "the first Account becomes administrator"
 * assertion — and it does not truncate `products`/`defect_codes` either: the
 * Defect code tree arrives seeded from the baseline migration (ADR-0005's one
 * shared catalogue), so a test here asserts about the rows IT created by
 * looking them up by their own unique code rather than by counting a whole
 * table. Every row this file inserts, in `app_users`, `products` and
 * `defect_codes`, is deleted again in `test.after()`.
 *
 * Both Accounts are inserted directly: the administrator with the role alone
 * and no Grants, and the ordinary Account as an approved, active `operator`.
 * Neither catalogue is Org-Unit scoped (a Product and a Defect code are shared
 * reference data, not records placed in the tree), so the only scope question
 * either route asks is the administrator's role — which is exactly what the
 * refusal tests below pin down.
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
const insertedProductCodes = [];
const insertedDefectCodeCodes = [];

let codeCounter = 0;
// Unique across processes (process.pid) and within one run (the counter), so
// two runs against one database never collide on `products.code` or
// `defect_codes.code`, which are UNIQUE plant-wide (ADR-0005) rather than
// per-Site — the same device plant.test.js's own uniqueCode uses.
function uniqueCode(prefix) {
  codeCounter += 1;
  return `${prefix}${process.pid}${codeCounter}`;
}

async function signToken(subject) {
  return jwks.signToken(
    { sub: subject, email: `${subject}@example.com` },
    { issuer: ISSUER, audience: AUDIENCE }
  );
}

async function authHeader(subject) {
  return { authorization: `Bearer ${await signToken(subject)}` };
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

  const adminSubject = `quality-admin-${process.pid}`;
  const memberSubject = `quality-member-${process.pid}`;

  const { rows: [admin] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status)
     VALUES ($1, 'Quality Test Admin', 'admin', $2, TRUE, 'approved') RETURNING id`,
    [`${adminSubject}@example.com`, adminSubject]
  );
  const { rows: [member] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status)
     VALUES ($1, 'Quality Test Member', 'operator', $2, TRUE, 'approved') RETURNING id`,
    [`${memberSubject}@example.com`, memberSubject]
  );
  insertedAccountIds.push(admin.id, member.id);

  adminToken = await authHeader(adminSubject);
  memberToken = await authHeader(memberSubject);
});

test.after(async () => {
  // Children before parents, and only the rows this file created: `defect_codes`
  // is self-referencing, so a code created beneath another one must go first.
  await pool.query(
    `DELETE FROM defect_codes
      WHERE code = ANY($1)
        AND NOT EXISTS (SELECT 1 FROM defect_codes child WHERE child.parent_id = defect_codes.id)`,
    [insertedDefectCodeCodes]
  );
  await pool.query('DELETE FROM defect_codes WHERE code = ANY($1)', [insertedDefectCodeCodes]);
  await pool.query('DELETE FROM products WHERE code = ANY($1)', [insertedProductCodes]);
  await pool.query('DELETE FROM app_users WHERE id = ANY($1)', [insertedAccountIds]);
  await new Promise((resolve) => server.close(resolve));
  await closePool();
  await jwks.close();
});

// Creates a Product through the API as the administrator and remembers its
// code for cleanup. Every test that needs a row starts here rather than
// inserting one directly, so the row is one the API itself would accept.
async function createProduct({ code, name, uomCode = 'EA' } = {}) {
  const productCode = code ?? uniqueCode('QP-');
  const response = await fetch(`${base}/api/quality/products`, {
    method: 'POST',
    headers: { ...adminToken, 'content-type': 'application/json' },
    body: JSON.stringify({ code: productCode, name: name ?? `Product ${productCode}`, uomCode })
  });
  const { status, body } = await json(response);
  assert.strictEqual(status, 201, `creating ${productCode} failed: ${JSON.stringify(body)}`);
  insertedProductCodes.push(productCode);
  return body.product;
}

async function createDefectCode({ code, name, category, defaultSeverity, parentId } = {}) {
  const defectCode = code ?? uniqueCode('QD-');
  const response = await fetch(`${base}/api/quality/defect-codes`, {
    method: 'POST',
    headers: { ...adminToken, 'content-type': 'application/json' },
    body: JSON.stringify({
      code: defectCode,
      name: name ?? `Defect ${defectCode}`,
      category,
      defaultSeverity,
      parentId
    })
  });
  const { status, body } = await json(response);
  assert.strictEqual(status, 201, `creating ${defectCode} failed: ${JSON.stringify(body)}`);
  insertedDefectCodeCodes.push(defectCode);
  return body.defectCode;
}

async function listProducts({ token = memberToken, query = '' } = {}) {
  const response = await fetch(`${base}/api/quality/products${query}`, { headers: token });
  const { status, body } = await json(response);
  assert.strictEqual(status, 200);
  return body.products;
}

async function listDefectCodes({ token = memberToken, query = '' } = {}) {
  const response = await fetch(`${base}/api/quality/defect-codes${query}`, { headers: token });
  const { status, body } = await json(response);
  assert.strictEqual(status, 200);
  return body.defectCodes;
}

// ---------------------------------------------------------------------------
// 1. The Product catalogue: an administrator maintains it
// ---------------------------------------------------------------------------

test('an administrator creates a Product with a code, a name and a unit of measure, and reads it back', async () => {
  const code = uniqueCode('QP-');
  const created = await createProduct({ code, name: 'Hydraulic hose', uomCode: 'EA' });

  assert.strictEqual(created.code, code);
  assert.strictEqual(created.name, 'Hydraulic hose');
  assert.strictEqual(created.uomCode, 'EA');
  // The unit's own name rides on the row, so a catalogue can say what the
  // Product is measured in without a second read.
  assert.strictEqual(created.uomName, 'Each');
  assert.strictEqual(created.isActive, true);

  // Any active Account reads the catalogue, and the row it read is the row
  // that was created — not a second shape.
  const listed = await listProducts();
  const row = listed.find((product) => product.code === code);
  assert.deepStrictEqual(row, created);
});

test('a Product whose code is already taken is refused with 409', async () => {
  const code = uniqueCode('QP-');
  await createProduct({ code, name: 'First' });

  const response = await fetch(`${base}/api/quality/products`, {
    method: 'POST',
    headers: { ...adminToken, 'content-type': 'application/json' },
    body: JSON.stringify({ code, name: 'Second', uomCode: 'EA' })
  });
  const { status, body } = await json(response);

  assert.strictEqual(status, 409);
  assert.strictEqual(body.message, 'a Product with this code already exists');
});

test('a Product whose unit of measure is not one the plant uses is refused with 400', async () => {
  const response = await fetch(`${base}/api/quality/products`, {
    method: 'POST',
    headers: { ...adminToken, 'content-type': 'application/json' },
    body: JSON.stringify({ code: uniqueCode('QP-'), name: 'Invented unit', uomCode: 'NOT-A-UNIT' })
  });
  const { status, body } = await json(response);

  assert.strictEqual(status, 400);
  assert.strictEqual(body.message, 'uomCode must be a unit of measure the plant uses');
});

test('an administrator corrects a Product name, and its code and unit of measure are refused rather than rewritten', async () => {
  const created = await createProduct({ name: 'Before' });

  const renamed = await fetch(`${base}/api/quality/products/${created.id}`, {
    method: 'PATCH',
    headers: { ...adminToken, 'content-type': 'application/json' },
    body: JSON.stringify({ name: 'After' })
  });
  const { status, body } = await json(renamed);
  assert.strictEqual(status, 200);
  assert.strictEqual(body.product.name, 'After');
  // The rest of the row is untouched — a one-field PATCH cannot blank another.
  assert.strictEqual(body.product.code, created.code);
  assert.strictEqual(body.product.uomCode, created.uomCode);

  for (const [field, value] of [['code', uniqueCode('QP-')], ['uomCode', 'H']]) {
    const refused = await fetch(`${base}/api/quality/products/${created.id}`, {
      method: 'PATCH',
      headers: { ...adminToken, 'content-type': 'application/json' },
      body: JSON.stringify({ [field]: value })
    });
    const answer = await json(refused);
    assert.strictEqual(answer.status, 400, `${field} should be refused`);
    assert.strictEqual(answer.body.message, `${field} cannot be corrected on a Product`);
  }

  // And the row still reads as the correction left it.
  const listed = await listProducts();
  assert.strictEqual(listed.find((product) => product.id === created.id).name, 'After');
});

test('an administrator deactivates a Product and reactivates it', async () => {
  const created = await createProduct({});

  const deactivated = await fetch(`${base}/api/quality/products/${created.id}`, {
    method: 'PATCH',
    headers: { ...adminToken, 'content-type': 'application/json' },
    body: JSON.stringify({ isActive: false })
  });
  assert.strictEqual(deactivated.status, 200);
  assert.strictEqual((await json(deactivated)).body.product.isActive, false);

  // Excluded by default, present when the caller asks for the retired ones by
  // name — the whole point of the flag being reachable at all.
  const active = await listProducts();
  assert.strictEqual(active.find((product) => product.id === created.id), undefined);
  const all = await listProducts({ query: '?includeInactive=true' });
  assert.strictEqual(all.find((product) => product.id === created.id).isActive, false);

  const reactivated = await fetch(`${base}/api/quality/products/${created.id}`, {
    method: 'PATCH',
    headers: { ...adminToken, 'content-type': 'application/json' },
    body: JSON.stringify({ isActive: true })
  });
  assert.strictEqual((await json(reactivated)).body.product.isActive, true);
  const backIn = await listProducts();
  assert.strictEqual(backIn.find((product) => product.id === created.id).isActive, true);
});

// ---------------------------------------------------------------------------
// 2. The Product catalogue: any active Account reads and searches it
// ---------------------------------------------------------------------------

test('any active Account lists and searches Products by code or name, deactivated ones excluded by default', async () => {
  const code = uniqueCode('QP-');
  const byName = await createProduct({ code, name: `Blue widget ${code}` });
  const retired = await createProduct({ name: 'Retired widget' });
  await fetch(`${base}/api/quality/products/${retired.id}`, {
    method: 'PATCH',
    headers: { ...adminToken, 'content-type': 'application/json' },
    body: JSON.stringify({ isActive: false })
  });

  // Read by an ordinary approved Account: this catalogue carries no admin and
  // no Org Unit scope on its read side.
  const all = await listProducts();
  assert.ok(all.some((product) => product.id === byName.id));
  assert.strictEqual(all.find((product) => product.id === retired.id), undefined);

  const byCode = await listProducts({ query: `?search=${encodeURIComponent(code)}` });
  assert.deepStrictEqual(byCode.map((product) => product.id), [byName.id]);

  const byNameSearch = await listProducts({ query: '?search=Blue%20widget' });
  assert.ok(byNameSearch.some((product) => product.id === byName.id));

  // A term that matches nothing is an empty list, not a widened one.
  assert.deepStrictEqual(await listProducts({ query: '?search=zzz-nothing-matches' }), []);

  // A search does not resurrect a deactivated row, and `includeInactive` on
  // its own does not filter.
  const retiredSearch = await listProducts({ query: '?search=Retired%20widget' });
  assert.deepStrictEqual(retiredSearch, []);
  const retiredIncluded = await listProducts({ query: '?search=Retired%20widget&includeInactive=true' });
  assert.deepStrictEqual(retiredIncluded.map((product) => product.id), [retired.id]);
});

// ---------------------------------------------------------------------------
// 3. The Defect code tree: an administrator maintains it
// ---------------------------------------------------------------------------

test('an administrator creates a Defect code with a category, a default severity and a parent, and reads the tree back', async () => {
  const parent = await createDefectCode({ category: 'process', defaultSeverity: 'major' });
  assert.strictEqual(parent.parentId, null);
  assert.strictEqual(parent.category, 'process');
  assert.strictEqual(parent.defaultSeverity, 'major');
  assert.strictEqual(parent.isActive, true);

  const child = await createDefectCode({
    category: 'material',
    defaultSeverity: 'critical',
    parentId: parent.id
  });
  assert.strictEqual(child.parentId, parent.id);

  // Both are choices for any approved Account, each row naming its own parent,
  // category and default severity — the tree the client assembles.
  const tree = await listDefectCodes();
  assert.deepStrictEqual(tree.find((code) => code.id === child.id), child);
  assert.strictEqual(tree.find((code) => code.id === parent.id).parentId, null);
});

test('a Defect code defaults to the category and severity the baseline gives a code that names neither', async () => {
  const created = await createDefectCode({});

  assert.strictEqual(created.category, 'product');
  assert.strictEqual(created.defaultSeverity, 'minor');
});

test('a Defect code value outside the set the database accepts is refused with 400, not a raw constraint violation', async () => {
  for (const [field, value] of [
    ['category', 'weather'],
    ['defaultSeverity', 'catastrophic']
  ]) {
    const response = await fetch(`${base}/api/quality/defect-codes`, {
      method: 'POST',
      headers: { ...adminToken, 'content-type': 'application/json' },
      body: JSON.stringify({ code: uniqueCode('QD-'), name: 'Outside the set', [field]: value })
    });
    const { status, body } = await json(response);
    assert.strictEqual(status, 400);
    assert.match(body.message, new RegExp(`^${field} must be one of `));
  }
});

test('a Defect code whose code is already taken is refused with 409', async () => {
  const code = uniqueCode('QD-');
  await createDefectCode({ code });

  const response = await fetch(`${base}/api/quality/defect-codes`, {
    method: 'POST',
    headers: { ...adminToken, 'content-type': 'application/json' },
    body: JSON.stringify({ code, name: 'Second' })
  });
  const { status, body } = await json(response);

  assert.strictEqual(status, 409);
  assert.strictEqual(body.message, 'a Defect code with this code already exists');
});

test('a Defect code placed under a parent that does not exist is refused with 404, and a malformed one with 400', async () => {
  const unknown = await fetch(`${base}/api/quality/defect-codes`, {
    method: 'POST',
    headers: { ...adminToken, 'content-type': 'application/json' },
    body: JSON.stringify({ code: uniqueCode('QD-'), name: 'Orphan', parentId: '999999999' })
  });
  const unknownAnswer = await json(unknown);
  assert.strictEqual(unknownAnswer.status, 404);
  assert.strictEqual(unknownAnswer.body.message, 'Parent Defect code not found');

  const malformed = await fetch(`${base}/api/quality/defect-codes`, {
    method: 'POST',
    headers: { ...adminToken, 'content-type': 'application/json' },
    body: JSON.stringify({ code: uniqueCode('QD-'), name: 'Orphan', parentId: 'not-an-id' })
  });
  assert.strictEqual(malformed.status, 400);
});

test('a Defect code cannot be moved beneath one of its own codes', async () => {
  const parent = await createDefectCode({});
  const child = await createDefectCode({ parentId: parent.id });
  const grandchild = await createDefectCode({ parentId: child.id });

  // Itself: refused before the tree is even consulted.
  const self = await fetch(`${base}/api/quality/defect-codes/${parent.id}`, {
    method: 'PATCH',
    headers: { ...adminToken, 'content-type': 'application/json' },
    body: JSON.stringify({ parentId: parent.id })
  });
  assert.strictEqual(self.status, 400);
  assert.strictEqual((await json(self)).body.message, 'a Defect code cannot be its own parent');

  // A descendant, one level down and two, each refused — a cycle either way.
  for (const descendant of [child, grandchild]) {
    const response = await fetch(`${base}/api/quality/defect-codes/${parent.id}`, {
      method: 'PATCH',
      headers: { ...adminToken, 'content-type': 'application/json' },
      body: JSON.stringify({ parentId: descendant.id })
    });
    assert.strictEqual(response.status, 400);
    assert.strictEqual(
      (await json(response)).body.message,
      'a Defect code cannot be moved beneath one of its own codes'
    );
  }

  // And the tree is unchanged by the refusals.
  const tree = await listDefectCodes();
  assert.strictEqual(tree.find((code) => code.id === parent.id).parentId, null);
  assert.strictEqual(tree.find((code) => code.id === grandchild.id).parentId, child.id);
});

test('an administrator corrects a Defect code and deactivates it', async () => {
  const parent = await createDefectCode({});
  const created = await createDefectCode({ parentId: parent.id });

  const corrected = await fetch(`${base}/api/quality/defect-codes/${created.id}`, {
    method: 'PATCH',
    headers: { ...adminToken, 'content-type': 'application/json' },
    body: JSON.stringify({
      name: 'Corrected name',
      category: 'packaging',
      defaultSeverity: 'critical',
      parentId: null
    })
  });
  const { status, body } = await json(corrected);
  assert.strictEqual(status, 200);
  assert.strictEqual(body.defectCode.name, 'Corrected name');
  assert.strictEqual(body.defectCode.category, 'packaging');
  assert.strictEqual(body.defectCode.defaultSeverity, 'critical');
  assert.strictEqual(body.defectCode.parentId, null);
  assert.strictEqual(body.defectCode.code, created.code);

  // Its code is refused rather than rewritten, for the reason products.js
  // gives its own: a code is what a report quotes.
  const codeChange = await fetch(`${base}/api/quality/defect-codes/${created.id}`, {
    method: 'PATCH',
    headers: { ...adminToken, 'content-type': 'application/json' },
    body: JSON.stringify({ code: uniqueCode('QD-') })
  });
  assert.strictEqual(codeChange.status, 400);
  assert.strictEqual((await json(codeChange)).body.message, 'code cannot be corrected on a Defect code');

  const deactivated = await fetch(`${base}/api/quality/defect-codes/${created.id}`, {
    method: 'PATCH',
    headers: { ...adminToken, 'content-type': 'application/json' },
    body: JSON.stringify({ isActive: false })
  });
  assert.strictEqual((await json(deactivated)).body.defectCode.isActive, false);

  const active = await listDefectCodes();
  assert.strictEqual(active.find((code) => code.id === created.id), undefined);
  const all = await listDefectCodes({ query: '?includeInactive=true' });
  assert.strictEqual(all.find((code) => code.id === created.id).isActive, false);
  // Deactivating one code does not hide another, and deactivating a child
  // leaves its parent exactly where it was.
  assert.ok(active.some((code) => code.id === parent.id));
});

// ---------------------------------------------------------------------------
// 4. Writes are the administrator's, and the address refuses in order
// ---------------------------------------------------------------------------

test('an administrator creates a Product and a Defect code, and an ordinary Account is refused 403 on every write to either', async () => {
  const product = await createProduct({});
  const defectCode = await createDefectCode({});

  const writes = [
    ['POST', '/api/quality/products', { code: uniqueCode('QP-'), name: 'Refused', uomCode: 'EA' }],
    ['PATCH', `/api/quality/products/${product.id}`, { name: 'Refused' }],
    ['POST', '/api/quality/defect-codes', { code: uniqueCode('QD-'), name: 'Refused' }],
    ['PATCH', `/api/quality/defect-codes/${defectCode.id}`, { name: 'Refused' }]
  ];

  for (const [method, path, body] of writes) {
    const response = await fetch(`${base}${path}`, {
      method,
      headers: { ...memberToken, 'content-type': 'application/json' },
      body: JSON.stringify(body)
    });
    const answer = await json(response);
    assert.strictEqual(answer.status, 403, `${method} ${path} should be refused`);
    assert.strictEqual(answer.body.message, 'This action requires the administrator role.');
  }

  // Nothing was written: both rows still read as they were.
  const products = await listProducts();
  assert.strictEqual(products.find((row) => row.id === product.id).name, product.name);
  const defectCodes = await listDefectCodes();
  assert.strictEqual(
    defectCodes.find((row) => row.id === defectCode.id).name,
    defectCode.name
  );
});

test('a write names existence before it asks about the role, so an unknown id is a 404 whoever is asking', async () => {
  // AGENTS.md §6's ordering, kept here for the role check the way
  // inventory-routes.js keeps it for `canAct`: a Product that is not there is
  // a 404 for the ordinary Account as well as for the administrator, rather
  // than a 403 that hides which of the two went wrong.
  for (const token of [adminToken, memberToken]) {
    const product = await fetch(`${base}/api/quality/products/999999999`, {
      method: 'PATCH',
      headers: { ...token, 'content-type': 'application/json' },
      body: JSON.stringify({ name: 'Nobody' })
    });
    assert.strictEqual(product.status, 404);
    assert.strictEqual((await json(product)).body.message, 'Product not found');

    const defectCode = await fetch(`${base}/api/quality/defect-codes/999999999`, {
      method: 'PATCH',
      headers: { ...token, 'content-type': 'application/json' },
      body: JSON.stringify({ name: 'Nobody' })
    });
    assert.strictEqual(defectCode.status, 404);
    assert.strictEqual((await json(defectCode)).body.message, 'Defect code not found');

    // A malformed id is the same clean 404, never a 500.
    const malformed = await fetch(`${base}/api/quality/products/not-an-id`, {
      method: 'PATCH',
      headers: { ...token, 'content-type': 'application/json' },
      body: JSON.stringify({ name: 'Nobody' })
    });
    assert.strictEqual(malformed.status, 404);
  }
});

test('both catalogues refuse an unauthenticated caller', async () => {
  for (const path of ['/api/quality/products', '/api/quality/defect-codes']) {
    const response = await fetch(`${base}${path}`);
    assert.strictEqual(response.status, 401, `${path} should refuse a caller with no token`);
  }
});
