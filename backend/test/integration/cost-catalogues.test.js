/*
 * The cost rate and product standard cost catalogues, over HTTP (issue #252) —
 * the two catalogues that maintain the prices the baseline's cost views already
 * resolve through `resolve_cost_rate` and `product_standard_cost`.
 *
 * The same seam safety-catalogues.test.js and quality-catalogues.test.js use,
 * and the same shape: the real app on a real socket, a real database, and a
 * real (locally issued) JWKS standing behind `src/platform/tokens.js`'s actual
 * verification. Nothing is truncated — every row this file inserts is deleted
 * again in `test.after()`, keyed by the ids and codes it created.
 *
 * Two Accounts, inserted directly: the administrator with the role alone and no
 * Grants, and an ordinary approved, active `operator`. Neither catalogue is
 * Org-Unit scoped — a rate is shared reference data placed against a scope, not
 * a record the caller acts at — so the only question either write route asks is
 * the administrator's role, which is what the refusal test pins down.
 *
 * One Site with a two-level Org Unit tree and an Asset on the leaf, so the
 * resolution test can actually exercise `resolve_cost_rate`'s fallback —
 * asset, then nearest ancestor Org Unit, then Site — rather than asserting a
 * single answer with nothing to fall back from. The rule itself is the
 * database's; this file asserts what it answers, not how it is spelled.
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
const insertedSiteIds = [];
const insertedOrgUnitIds = [];
const insertedAssetIds = [];
const insertedProductIds = [];
const insertedCostRateIds = [];
const insertedProductCostIds = [];

// The fixture tree, built once in `before` and shared: one Site, an area, a
// line beneath it, and a press on the line.
let site;
let area;
let line;
let press;
let product;

let codeCounter = 0;
// Unique across processes (process.pid) and within one run (the counter), so
// two runs against one database never collide on a UNIQUE code.
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

  const adminSubject = `cost-cat-admin-${process.pid}`;
  const memberSubject = `cost-cat-member-${process.pid}`;

  const { rows: [admin] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status)
     VALUES ($1, 'Cost Catalogue Admin', 'admin', $2, TRUE, 'approved') RETURNING id`,
    [`${adminSubject}@example.com`, adminSubject]
  );
  const { rows: [member] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status)
     VALUES ($1, 'Cost Catalogue Member', 'operator', $2, TRUE, 'approved') RETURNING id`,
    [`${memberSubject}@example.com`, memberSubject]
  );
  insertedAccountIds.push(admin.id, member.id);

  adminToken = await authHeader(adminSubject);
  memberToken = await authHeader(memberSubject);

  ({ rows: [site] } = await pool.query(
    `INSERT INTO sites (code, name, timezone) VALUES ($1, 'Cost Catalogue Site', 'UTC')
     RETURNING id, code, name`,
    [uniqueCode('CCS')]
  ));
  insertedSiteIds.push(site.id);

  ({ rows: [area] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, NULL, $2, 'Cost Area', 'area') RETURNING id, name`,
    [site.id, uniqueCode('CCOU')]
  ));
  insertedOrgUnitIds.push(area.id);

  ({ rows: [line] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, $2, $3, 'Cost Line', 'line') RETURNING id, name`,
    [site.id, area.id, uniqueCode('CCOU')]
  ));
  insertedOrgUnitIds.push(line.id);

  ({ rows: [press] } = await pool.query(
    `INSERT INTO assets (org_unit_id, code, name, asset_type, criticality)
     VALUES ($1, $2, 'Cost Press', 'machine', 'high') RETURNING id, name`,
    [line.id, uniqueCode('CCAS')]
  ));
  insertedAssetIds.push(press.id);

  ({ rows: [product] } = await pool.query(
    `INSERT INTO products (code, name, uom_code) VALUES ($1, 'Cost Product', 'EA')
     RETURNING id, code, name`,
    [uniqueCode('CCPR')]
  ));
  insertedProductIds.push(product.id);
});

test.after(async () => {
  await pool.query('DELETE FROM cost_rates WHERE id = ANY($1)', [insertedCostRateIds]);
  await pool.query('DELETE FROM product_costs WHERE id = ANY($1)', [insertedProductCostIds]);
  await pool.query('DELETE FROM products WHERE id = ANY($1)', [insertedProductIds]);
  await pool.query('DELETE FROM assets WHERE id = ANY($1)', [insertedAssetIds]);
  await pool.query('DELETE FROM app_users WHERE id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM org_units WHERE id = ANY($1)', [insertedOrgUnitIds]);
  await pool.query('DELETE FROM sites WHERE id = ANY($1)', [insertedSiteIds]);
  await new Promise((resolve) => server.close(resolve));
  await closePool();
  await jwks.close();
});

// ---------------------------------------------------------------------------
// Helpers over the two catalogues' own HTTP surface.
// ---------------------------------------------------------------------------

async function createCostRate(token, body) {
  const result = await json(
    await fetch(`${base}/api/people/cost-rates`, {
      method: 'POST',
      headers: { ...token, 'content-type': 'application/json' },
      body: JSON.stringify(body)
    })
  );
  if (result.status === 201) insertedCostRateIds.push(result.body.costRate.id);
  return result;
}

async function correctCostRate(token, id, body) {
  return json(
    await fetch(`${base}/api/people/cost-rates/${id}`, {
      method: 'PATCH',
      headers: { ...token, 'content-type': 'application/json' },
      body: JSON.stringify(body)
    })
  );
}

async function reviseCostRate(token, id, body) {
  const result = await json(
    await fetch(`${base}/api/people/cost-rates/${id}/revision`, {
      method: 'POST',
      headers: { ...token, 'content-type': 'application/json' },
      body: JSON.stringify(body)
    })
  );
  if (result.status === 201) insertedCostRateIds.push(result.body.opened.id);
  return result;
}

async function listCostRates(token) {
  return json(await fetch(`${base}/api/people/cost-rates`, { headers: token }));
}

async function resolveCostRate(token, query) {
  const search = new URLSearchParams(query).toString();
  return json(await fetch(`${base}/api/people/cost-rates/resolution?${search}`, { headers: token }));
}

async function createProductCost(token, body) {
  const result = await json(
    await fetch(`${base}/api/people/product-costs`, {
      method: 'POST',
      headers: { ...token, 'content-type': 'application/json' },
      body: JSON.stringify(body)
    })
  );
  if (result.status === 201) insertedProductCostIds.push(result.body.productCost.id);
  return result;
}

async function correctProductCost(token, id, body) {
  return json(
    await fetch(`${base}/api/people/product-costs/${id}`, {
      method: 'PATCH',
      headers: { ...token, 'content-type': 'application/json' },
      body: JSON.stringify(body)
    })
  );
}

async function reviseProductCost(token, id, body) {
  const result = await json(
    await fetch(`${base}/api/people/product-costs/${id}/revision`, {
      method: 'POST',
      headers: { ...token, 'content-type': 'application/json' },
      body: JSON.stringify(body)
    })
  );
  if (result.status === 201) insertedProductCostIds.push(result.body.opened.id);
  return result;
}

async function listProductCosts(token) {
  return json(await fetch(`${base}/api/people/product-costs`, { headers: token }));
}

// ---------------------------------------------------------------------------
// The cost rate catalogue
// ---------------------------------------------------------------------------

test('an administrator creates a cost rate, and any active Account reads it back', async () => {
  const created = await createCostRate(adminToken, {
    scopeType: 'site',
    scopeId: site.id,
    rateType: 'labor_per_hour',
    amount: 22.5,
    currency: 'usd',
    effectiveFrom: '2026-01-01',
    note: 'Opening rate'
  });

  assert.strictEqual(created.status, 201, JSON.stringify(created.body));
  assert.strictEqual(created.body.costRate.scopeType, 'site');
  assert.strictEqual(created.body.costRate.scopeId, site.id);
  assert.strictEqual(created.body.costRate.scopeName, site.name);
  assert.strictEqual(created.body.costRate.rateType, 'labor_per_hour');
  assert.strictEqual(created.body.costRate.amount, 22.5);
  // Normalised, not echoed: the column is a three-letter code.
  assert.strictEqual(created.body.costRate.currency, 'USD');
  assert.strictEqual(created.body.costRate.effectiveFrom, '2026-01-01');
  assert.strictEqual(created.body.costRate.effectiveTo, null);

  // The ordinary operator may read the catalogue — no Grant, no admin role.
  const read = await listCostRates(memberToken);
  assert.strictEqual(read.status, 200);
  const mine = read.body.costRates.find((rate) => rate.id === created.body.costRate.id);
  assert.ok(mine, 'the created rate is missing from the catalogue');
  assert.strictEqual(mine.amount, 22.5);
  assert.strictEqual(mine.effectiveFrom, '2026-01-01');
});

test('a scope type and a rate type outside the schema\'s own sets are refused', async () => {
  const badScope = await createCostRate(adminToken, {
    scopeType: 'department',
    scopeId: site.id,
    rateType: 'labor_per_hour',
    amount: 10,
    effectiveFrom: '2026-01-01'
  });
  assert.strictEqual(badScope.status, 400);
  assert.match(badScope.body.message, /scopeType must be one of: site, org_unit, asset, cost_center/);

  const badRate = await createCostRate(adminToken, {
    scopeType: 'site',
    scopeId: site.id,
    rateType: 'coffee_per_hour',
    amount: 10,
    effectiveFrom: '2026-01-01'
  });
  assert.strictEqual(badRate.status, 400);
  assert.match(badRate.body.message, /rateType must be one of: labor_per_hour/);
});

test('a cost rate scoped to something that does not exist is refused', async () => {
  const refused = await createCostRate(adminToken, {
    scopeType: 'org_unit',
    scopeId: '99999999',
    rateType: 'labor_per_hour',
    amount: 10,
    effectiveFrom: '2026-01-01'
  });
  assert.strictEqual(refused.status, 404);
  assert.strictEqual(refused.body.message, 'scopeId does not name an existing Org Unit');
});

test('overlapping effective periods for one scope and rate type are refused with a 400 naming the conflict', async () => {
  const first = await createCostRate(adminToken, {
    scopeType: 'org_unit',
    scopeId: area.id,
    rateType: 'overhead_per_hour',
    amount: 12,
    effectiveFrom: '2026-01-01',
    effectiveTo: '2026-07-01'
  });
  assert.strictEqual(first.status, 201, JSON.stringify(first.body));

  const clash = await createCostRate(adminToken, {
    scopeType: 'org_unit',
    scopeId: area.id,
    rateType: 'overhead_per_hour',
    amount: 15,
    effectiveFrom: '2026-06-01'
  });

  assert.strictEqual(clash.status, 400, JSON.stringify(clash.body));
  assert.strictEqual(clash.body.code, 'COST_RATE_PERIOD_OVERLAP');
  // Names the conflict — the rate type, the kind of scope, and the period asked
  // for — rather than echoing a constraint name, a table or a column.
  assert.match(clash.body.message, /overhead_per_hour rate for this Org Unit/);
  assert.match(clash.body.message, /2026-06-01 onward/);
  assert.doesNotMatch(clash.body.message, /cost_rates_no_overlap|daterange|EXCLUDE/);

  // A period that ends exactly where the next begins is not an overlap: the
  // range is half-open, which is what makes a closed row and its successor sit
  // side by side.
  const adjacent = await createCostRate(adminToken, {
    scopeType: 'org_unit',
    scopeId: area.id,
    rateType: 'overhead_per_hour',
    amount: 15,
    effectiveFrom: '2026-07-01'
  });
  assert.strictEqual(adjacent.status, 201, JSON.stringify(adjacent.body));
});

test("correcting a rate's amount for a new period closes the old row and leaves the earlier date resolvable", async () => {
  const original = await createCostRate(adminToken, {
    scopeType: 'org_unit',
    scopeId: line.id,
    rateType: 'labor_per_hour',
    amount: 30,
    effectiveFrom: '2026-01-01'
  });
  assert.strictEqual(original.status, 201, JSON.stringify(original.body));

  const revised = await reviseCostRate(adminToken, original.body.costRate.id, {
    amount: 36,
    effectiveFrom: '2026-04-01',
    note: 'Pay award'
  });

  assert.strictEqual(revised.status, 201, JSON.stringify(revised.body));
  // The old row keeps its id, its amount and its own effective_from — it only
  // gains an effective_to.
  assert.strictEqual(revised.body.closed.id, original.body.costRate.id);
  assert.strictEqual(revised.body.closed.amount, 30);
  assert.strictEqual(revised.body.closed.effectiveFrom, '2026-01-01');
  assert.strictEqual(revised.body.closed.effectiveTo, '2026-04-01');
  assert.strictEqual(revised.body.opened.amount, 36);
  assert.strictEqual(revised.body.opened.effectiveFrom, '2026-04-01');
  assert.strictEqual(revised.body.opened.effectiveTo, null);

  // The old row stays readable in the catalogue.
  const listed = await listCostRates(memberToken);
  assert.ok(
    listed.body.costRates.some(
      (rate) => rate.id === original.body.costRate.id && rate.amount === 30
    ),
    'the closed period is no longer readable'
  );

  // And a cost view asked for an earlier date still resolves the old amount.
  const before = await resolveCostRate(memberToken, {
    orgUnitId: line.id,
    rateType: 'labor_per_hour',
    at: '2026-02-01'
  });
  assert.strictEqual(before.status, 200, JSON.stringify(before.body));
  assert.strictEqual(before.body.resolution.amount, 30);

  const after = await resolveCostRate(memberToken, {
    orgUnitId: line.id,
    rateType: 'labor_per_hour',
    at: '2026-05-01'
  });
  assert.strictEqual(after.body.resolution.amount, 36);
});

test('a rate is closed by a correction, and its scope and rate type are refused', async () => {
  const created = await createCostRate(adminToken, {
    scopeType: 'org_unit',
    scopeId: area.id,
    rateType: 'machine_downtime_per_hour',
    amount: 90,
    effectiveFrom: '2026-01-01'
  });
  assert.strictEqual(created.status, 201, JSON.stringify(created.body));

  // Correcting the amount in place — a mistyped figure for the same period.
  const corrected = await correctCostRate(adminToken, created.body.costRate.id, { amount: 95 });
  assert.strictEqual(corrected.status, 200, JSON.stringify(corrected.body));
  assert.strictEqual(corrected.body.costRate.amount, 95);
  assert.strictEqual(corrected.body.costRate.effectiveFrom, '2026-01-01');

  // Closing it is the same correction, setting the day it stops applying.
  const closed = await correctCostRate(adminToken, created.body.costRate.id, {
    effectiveTo: '2026-09-01'
  });
  assert.strictEqual(closed.status, 200, JSON.stringify(closed.body));
  assert.strictEqual(closed.body.costRate.effectiveTo, '2026-09-01');
  assert.strictEqual(closed.body.costRate.amount, 95);

  // The two fields resolve_cost_rate finds a rate by are not correctable:
  // rewriting either would move a whole history somewhere else in the tree.
  const refusedScope = await correctCostRate(adminToken, created.body.costRate.id, {
    scopeId: site.id
  });
  assert.strictEqual(refusedScope.status, 400);
  assert.match(refusedScope.body.message, /scopeId cannot be corrected on a cost rate/);

  const refusedRateType = await correctCostRate(adminToken, created.body.costRate.id, {
    rateType: 'labor_per_hour'
  });
  assert.strictEqual(refusedRateType.status, 400);
  assert.match(refusedRateType.body.message, /rateType cannot be corrected on a cost rate/);

  // A period that ends before it begins is a clean 400, not a raw CHECK.
  const backwards = await correctCostRate(adminToken, created.body.costRate.id, {
    effectiveTo: '2025-01-01'
  });
  assert.strictEqual(backwards.status, 400);
  assert.strictEqual(backwards.body.message, 'effectiveTo must be after effectiveFrom');
});

test('the resolution read falls back from the Asset to its Org Unit to the Site', async () => {
  // One rate at each level of the fixture tree, all the same rate type, so the
  // only thing that decides the answer is resolve_cost_rate's own ordering.
  const atSite = await createCostRate(adminToken, {
    scopeType: 'site',
    scopeId: site.id,
    rateType: 'rework_labor_per_hour',
    amount: 10,
    effectiveFrom: '2026-01-01'
  });
  assert.strictEqual(atSite.status, 201, JSON.stringify(atSite.body));

  // Nothing at the line or on the press yet: the Site is the last resort.
  const siteOnly = await resolveCostRate(memberToken, {
    orgUnitId: line.id,
    rateType: 'rework_labor_per_hour',
    at: '2026-03-01'
  });
  assert.strictEqual(siteOnly.status, 200, JSON.stringify(siteOnly.body));
  assert.strictEqual(siteOnly.body.resolution.amount, 10);

  // An ancestor Org Unit beats the Site.
  const atArea = await createCostRate(adminToken, {
    scopeType: 'org_unit',
    scopeId: area.id,
    rateType: 'rework_labor_per_hour',
    amount: 20,
    effectiveFrom: '2026-01-01'
  });
  assert.strictEqual(atArea.status, 201, JSON.stringify(atArea.body));

  const viaArea = await resolveCostRate(memberToken, {
    orgUnitId: line.id,
    rateType: 'rework_labor_per_hour',
    at: '2026-03-01'
  });
  assert.strictEqual(viaArea.body.resolution.amount, 20);

  // The nearer ancestor beats the further one.
  const atLine = await createCostRate(adminToken, {
    scopeType: 'org_unit',
    scopeId: line.id,
    rateType: 'rework_labor_per_hour',
    amount: 30,
    effectiveFrom: '2026-01-01'
  });
  assert.strictEqual(atLine.status, 201, JSON.stringify(atLine.body));

  const viaLine = await resolveCostRate(memberToken, {
    orgUnitId: line.id,
    rateType: 'rework_labor_per_hour',
    at: '2026-03-01'
  });
  assert.strictEqual(viaLine.body.resolution.amount, 30);

  // And the Asset's own rate beats every Org Unit above it.
  const atAsset = await createCostRate(adminToken, {
    scopeType: 'asset',
    scopeId: press.id,
    rateType: 'rework_labor_per_hour',
    amount: 40,
    effectiveFrom: '2026-01-01'
  });
  assert.strictEqual(atAsset.status, 201, JSON.stringify(atAsset.body));

  const viaAsset = await resolveCostRate(memberToken, {
    orgUnitId: line.id,
    assetId: press.id,
    rateType: 'rework_labor_per_hour',
    at: '2026-03-01'
  });
  assert.strictEqual(viaAsset.body.resolution.amount, 40);
  assert.strictEqual(viaAsset.body.resolution.assetId, press.id);
  assert.strictEqual(viaAsset.body.resolution.at, '2026-03-01');

  // A day before any of them is an honest null, not a zero.
  const beforeAnything = await resolveCostRate(memberToken, {
    orgUnitId: line.id,
    assetId: press.id,
    rateType: 'rework_labor_per_hour',
    at: '2025-01-01'
  });
  assert.strictEqual(beforeAnything.body.resolution.amount, null);

  // An Org Unit that does not exist is a 404, not a null amount that reads as
  // "no rate is set".
  const unknown = await resolveCostRate(memberToken, {
    orgUnitId: '99999999',
    rateType: 'rework_labor_per_hour',
    at: '2026-03-01'
  });
  assert.strictEqual(unknown.status, 404);
  assert.strictEqual(unknown.body.message, 'Org Unit not found');
});

test('the scope list offers every kind of scope a rate can be attached to, each carrying its own type', async () => {
  const answer = await json(
    await fetch(`${base}/api/people/cost-rates/scopes`, { headers: memberToken })
  );
  assert.strictEqual(answer.status, 200);

  const mine = answer.body.scopes.filter(
    (scope) =>
      (scope.scopeType === 'site' && scope.id === site.id) ||
      (scope.scopeType === 'org_unit' && (scope.id === area.id || scope.id === line.id)) ||
      (scope.scopeType === 'asset' && scope.id === press.id)
  );
  assert.strictEqual(mine.length, 4, JSON.stringify(mine));

  const asset = mine.find((scope) => scope.scopeType === 'asset');
  assert.strictEqual(asset.name, 'Cost Press');
  assert.strictEqual(asset.siteName, site.name);

  // Every entry names a scope type the schema accepts — the set a scope is
  // chosen from, never typed (ADR-0023).
  for (const scope of answer.body.scopes) {
    assert.ok(
      ['site', 'org_unit', 'asset', 'cost_center'].includes(scope.scopeType),
      `unexpected scope type ${scope.scopeType}`
    );
  }
});

// ---------------------------------------------------------------------------
// The product standard cost catalogue
// ---------------------------------------------------------------------------

test('the Product list offers the Products a standard cost can be recorded against', async () => {
  const answer = await json(
    await fetch(`${base}/api/people/product-costs/products`, { headers: memberToken })
  );
  assert.strictEqual(answer.status, 200);
  const mine = answer.body.products.find((row) => row.id === product.id);
  assert.ok(mine, 'the fixture Product is missing from the list');
  assert.strictEqual(mine.code, product.code);
  assert.strictEqual(mine.name, 'Cost Product');
});

test('an administrator creates, corrects and closes a product standard cost, and any active Account reads it', async () => {
  const created = await createProductCost(adminToken, {
    productId: product.id,
    standardCost: 4.25,
    currency: 'eur',
    effectiveFrom: '2026-01-01'
  });

  assert.strictEqual(created.status, 201, JSON.stringify(created.body));
  assert.strictEqual(created.body.productCost.productId, product.id);
  assert.strictEqual(created.body.productCost.productCode, product.code);
  assert.strictEqual(created.body.productCost.standardCost, 4.25);
  assert.strictEqual(created.body.productCost.currency, 'EUR');
  assert.strictEqual(created.body.productCost.effectiveFrom, '2026-01-01');
  assert.strictEqual(created.body.productCost.effectiveTo, null);

  const corrected = await correctProductCost(adminToken, created.body.productCost.id, {
    standardCost: 4.5
  });
  assert.strictEqual(corrected.status, 200, JSON.stringify(corrected.body));
  assert.strictEqual(corrected.body.productCost.standardCost, 4.5);

  const closed = await correctProductCost(adminToken, created.body.productCost.id, {
    effectiveTo: '2026-12-01'
  });
  assert.strictEqual(closed.status, 200, JSON.stringify(closed.body));
  assert.strictEqual(closed.body.productCost.effectiveTo, '2026-12-01');

  // The Product a cost belongs to is not correctable — the same rule a rate's
  // scope keeps.
  const refused = await correctProductCost(adminToken, created.body.productCost.id, {
    productId: product.id
  });
  assert.strictEqual(refused.status, 400);
  assert.match(refused.body.message, /productId cannot be corrected on a standard cost/);

  const read = await listProductCosts(memberToken);
  assert.strictEqual(read.status, 200);
  assert.ok(
    read.body.productCosts.some((cost) => cost.id === created.body.productCost.id),
    'the created standard cost is missing from the catalogue'
  );
});

test('overlapping effective periods for one Product are refused with a 400 naming the conflict', async () => {
  const other = await pool.query(
    `INSERT INTO products (code, name, uom_code) VALUES ($1, 'Cost Product 2', 'EA') RETURNING id`,
    [uniqueCode('CCPR')]
  );
  insertedProductIds.push(other.rows[0].id);

  const first = await createProductCost(adminToken, {
    productId: other.rows[0].id,
    standardCost: 8,
    effectiveFrom: '2026-01-01',
    effectiveTo: '2026-07-01'
  });
  assert.strictEqual(first.status, 201, JSON.stringify(first.body));

  const clash = await createProductCost(adminToken, {
    productId: other.rows[0].id,
    standardCost: 9,
    effectiveFrom: '2026-03-01',
    effectiveTo: '2026-09-01'
  });

  assert.strictEqual(clash.status, 400, JSON.stringify(clash.body));
  assert.strictEqual(clash.body.code, 'PRODUCT_COST_PERIOD_OVERLAP');
  assert.match(clash.body.message, /standard cost for this Product already covers part of 2026-03-01 to 2026-09-01/);
  assert.doesNotMatch(clash.body.message, /product_costs_no_overlap|daterange|EXCLUDE/);
});

test('revising a standard cost closes the old period, and the earlier date still prices at the old cost', async () => {
  const other = await pool.query(
    `INSERT INTO products (code, name, uom_code) VALUES ($1, 'Cost Product 3', 'EA') RETURNING id`,
    [uniqueCode('CCPR')]
  );
  const productId = other.rows[0].id;
  insertedProductIds.push(productId);

  const original = await createProductCost(adminToken, {
    productId,
    standardCost: 5,
    effectiveFrom: '2026-01-01'
  });
  assert.strictEqual(original.status, 201, JSON.stringify(original.body));

  const revised = await reviseProductCost(adminToken, original.body.productCost.id, {
    standardCost: 6,
    effectiveFrom: '2026-06-01'
  });
  assert.strictEqual(revised.status, 201, JSON.stringify(revised.body));
  assert.strictEqual(revised.body.closed.standardCost, 5);
  assert.strictEqual(revised.body.closed.effectiveTo, '2026-06-01');
  assert.strictEqual(revised.body.opened.standardCost, 6);
  assert.strictEqual(revised.body.opened.effectiveFrom, '2026-06-01');

  // The baseline's own lookup — the one the cost-of-poor-quality view prices
  // scrap with — still answers the old cost for a date inside the old period.
  const { rows: [before] } = await pool.query(
    'SELECT product_standard_cost($1, $2::date) AS cost',
    [productId, '2026-03-01']
  );
  assert.strictEqual(Number(before.cost), 5);

  const { rows: [after] } = await pool.query(
    'SELECT product_standard_cost($1, $2::date) AS cost',
    [productId, '2026-08-01']
  );
  assert.strictEqual(Number(after.cost), 6);
});

test('a standard cost against a Product that does not exist is refused', async () => {
  const refused = await createProductCost(adminToken, {
    productId: '99999999',
    standardCost: 1,
    effectiveFrom: '2026-01-01'
  });
  assert.strictEqual(refused.status, 404);
  assert.strictEqual(refused.body.message, 'productId does not name an existing Product');
});

// ---------------------------------------------------------------------------
// Who may write
// ---------------------------------------------------------------------------

test('a non-administrator is refused 403 with a stable code on every write, and still reads both catalogues', async () => {
  const seedRate = await createCostRate(adminToken, {
    scopeType: 'site',
    scopeId: site.id,
    rateType: 'overtime_premium_multiplier',
    amount: 1.5,
    effectiveFrom: '2026-01-01'
  });
  assert.strictEqual(seedRate.status, 201, JSON.stringify(seedRate.body));

  const seedCost = await createProductCost(adminToken, {
    productId: product.id,
    standardCost: 3,
    effectiveFrom: '2027-01-01'
  });
  assert.strictEqual(seedCost.status, 201, JSON.stringify(seedCost.body));

  const refusals = [
    await createCostRate(memberToken, {
      scopeType: 'site',
      scopeId: site.id,
      rateType: 'labor_per_hour',
      amount: 1,
      effectiveFrom: '2030-01-01'
    }),
    await correctCostRate(memberToken, seedRate.body.costRate.id, { amount: 2 }),
    await reviseCostRate(memberToken, seedRate.body.costRate.id, {
      amount: 2,
      effectiveFrom: '2026-06-01'
    }),
    await createProductCost(memberToken, {
      productId: product.id,
      standardCost: 1,
      effectiveFrom: '2030-01-01'
    }),
    await correctProductCost(memberToken, seedCost.body.productCost.id, { standardCost: 2 }),
    await reviseProductCost(memberToken, seedCost.body.productCost.id, {
      standardCost: 2,
      effectiveFrom: '2027-06-01'
    })
  ];

  for (const refusal of refusals) {
    assert.strictEqual(refusal.status, 403, JSON.stringify(refusal.body));
    assert.strictEqual(refusal.body.message, 'This action requires the administrator role.');
    assert.strictEqual(refusal.body.code, 'ADMIN_ROLE_REQUIRED');
  }

  // Nothing the operator tried actually landed.
  const rates = await listCostRates(memberToken);
  const seeded = rates.body.costRates.find((rate) => rate.id === seedRate.body.costRate.id);
  assert.strictEqual(seeded.amount, 1.5);
  assert.strictEqual(seeded.effectiveTo, null);

  const costs = await listProductCosts(memberToken);
  const seededCost = costs.body.productCosts.find(
    (cost) => cost.id === seedCost.body.productCost.id
  );
  assert.strictEqual(seededCost.standardCost, 3);
});

test('a cost rate that does not exist is a 404, before the role is ever asked about', async () => {
  const missingForAdmin = await correctCostRate(adminToken, '99999999', { amount: 1 });
  assert.strictEqual(missingForAdmin.status, 404);
  assert.strictEqual(missingForAdmin.body.message, 'Cost rate not found');

  // Existence before scope: a non-administrator gets the same 404 for a rate
  // that is not there, rather than a 403 that would tell them it exists.
  const missingForMember = await correctCostRate(memberToken, '99999999', { amount: 1 });
  assert.strictEqual(missingForMember.status, 404);

  const malformed = await correctCostRate(adminToken, 'not-an-id', { amount: 1 });
  assert.strictEqual(malformed.status, 404);

  const missingCost = await correctProductCost(adminToken, '99999999', { standardCost: 1 });
  assert.strictEqual(missingCost.status, 404);
  assert.strictEqual(missingCost.body.message, 'Product standard cost not found');
});
