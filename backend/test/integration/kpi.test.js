/*
 * The MTU KPI catalogue over HTTP (ADR-0055): the catalogue, its Targets and the
 * daily Review, against a real database and a real (locally issued) JWKS, the
 * same seam as plant.test.js and handovers.test.js (see those files' headers).
 *
 * In production the catalogue is another database on another host. Here
 * MTU_DATABASE_URL points at the same dev database as DATABASE_URL, and
 * `test.before()` stands schema `kpi` up in it from test/fixtures/kpi-schema.sql
 * (a mirror of the source of truth — that file's header says whose).
 *
 * The tables are append-only for every role, so a test cannot tidy its own rows
 * away: the KPIs, Targets and Reviews added here stay until the next run drops
 * the schema and re-seeds it. What this file does clean up, in foreign-key
 * order in `test.after()`, are the Platform's own rows it inserted: its
 * `app_users` with their Grants, its Org Unit and its Site, all under subjects
 * unique to this process.
 *
 * Needs a database with every migration applied. Set DATABASE_URL first — see
 * the README's Tests section.
 */

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const { createTestJwks } = require('../helpers/jwks');

const ISSUER = 'https://example.supabase.co/auth/v1';
const AUDIENCE = 'authenticated';
const TIMEZONE = 'Asia/Ho_Chi_Minh';
const REVIEW_DATE = '2026-03-02';

let jwks;
let server;
let base;
let pool;
let closePool;
let mtuPool;
let closeMtuPool;

const insertedAccountIds = [];
const insertedSiteIds = [];
const insertedOrgUnitIds = [];

let site;
let rootOrgUnit;
let writer; // edit Grant on the Site's root Org Unit
let reader; // read-only Grant on the root Org Unit
let administrator; // role admin, no Grant at all

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

async function insertAccount({ role = 'operator', displayName = 'KPI Test Account', grants = [] } = {}) {
  const subject = uniqueCode('kpiacct');
  const { rows: [account] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status)
     VALUES ($1, $2, $3, $4, TRUE, 'approved') RETURNING id`,
    [`${subject}@example.com`, displayName, role, subject]
  );
  insertedAccountIds.push(account.id);
  for (const grant of grants) {
    await pool.query(
      `INSERT INTO app_user_org_units (app_user_id, org_unit_id, can_write) VALUES ($1, $2, $3)`,
      [account.id, grant.orgUnitId, grant.write]
    );
  }
  return { id: account.id, token: await authHeader(subject) };
}

async function send(method, token, urlPath, body) {
  const response = await fetch(`${base}/api/kpi${urlPath}`, {
    method,
    headers: { ...token, 'content-type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body)
  });
  return { status: response.status, body: await response.json() };
}

const get = (token, urlPath) => send('GET', token, urlPath);
const post = (token, urlPath, body) => send('POST', token, urlPath, body);

test.before(async () => {
  jwks = await createTestJwks();
  process.env.SUPABASE_JWKS_URL = jwks.url;
  process.env.SUPABASE_JWT_ISSUER = ISSUER;
  process.env.SUPABASE_JWT_AUDIENCE = AUDIENCE;
  process.env.BACKEND_PORT = '0';
  // The 503 case asserts the unconfigured state first, so the variable must not
  // leak in from the environment or a .env file.
  delete process.env.MTU_DATABASE_URL;

  ({ server } = require('../../src/index'));
  ({ closePool } = require('../../src/platform/db'));
  ({ closeMtuPool } = require('../../src/platform/mtu-db'));
  pool = require('../../src/platform/db').getPool();

  if (!server.listening) {
    await new Promise((resolve, reject) => {
      server.once('listening', resolve);
      server.once('error', reject);
    });
  }
  base = `http://127.0.0.1:${server.address().port}`;

  // The tables are append-only for every role, so a test cannot tidy its own
  // rows away; dropping the schema and re-seeding it is the only way back to
  // the seeded 19 KPIs and 48 targets on every run. It touches only schema
  // `kpi`, which the Platform's own database does not otherwise have.
  await pool.query('DROP SCHEMA IF EXISTS kpi CASCADE');
  await pool.query(fs.readFileSync(path.join(__dirname, '..', 'fixtures', 'kpi-schema.sql'), 'utf8'));

  ({ rows: [site] } = await pool.query(
    `INSERT INTO sites (code, name, timezone) VALUES ($1, 'KPI Test Site', $2) RETURNING id, timezone`,
    [uniqueCode('KPS'), TIMEZONE]
  ));
  insertedSiteIds.push(site.id);
  ({ rows: [rootOrgUnit] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, NULL, $2, 'KPI Test Department', 'department') RETURNING id`,
    [site.id, uniqueCode('KPOU')]
  ));
  insertedOrgUnitIds.push(rootOrgUnit.id);

  writer = await insertAccount({
    displayName: 'Kim Writer',
    grants: [{ orgUnitId: rootOrgUnit.id, write: true }]
  });
  reader = await insertAccount({ grants: [{ orgUnitId: rootOrgUnit.id, write: false }] });
  administrator = await insertAccount({ role: 'admin' });
});

test.after(async () => {
  await pool.query('DELETE FROM app_user_org_units WHERE app_user_id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM app_users WHERE id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM org_units WHERE id = ANY($1)', [insertedOrgUnitIds]);
  await pool.query('DELETE FROM sites WHERE id = ANY($1)', [insertedSiteIds]);
  await new Promise((resolve) => server.close(resolve));
  await closePool();
  await closeMtuPool();
  await jwks.close();
});

// This case must run first. The second Pool is created lazily and cached, so the
// unconfigured state has to be asserted before the first configured call; once
// the variable is restored below, the rest of the file runs against the catalogue.
test('with no MTU_DATABASE_URL every KPI route answers 503, after authentication', async () => {
  assert.strictEqual(process.env.MTU_DATABASE_URL, undefined);

  const siteId = site.id;
  const calls = [
    ['GET', `/catalogue?site_id=${siteId}`],
    ['POST', '/catalogue', { site_id: siteId }],
    ['GET', `/targets?site_id=${siteId}&kpi_id=1`],
    ['POST', '/targets', { site_id: siteId }],
    ['GET', `/review?site_id=${siteId}`],
    ['POST', '/review', { site_id: siteId }]
  ];
  for (const [method, urlPath, body] of calls) {
    const answered = await send(method, writer.token, urlPath, body);
    assert.strictEqual(answered.status, 503, `${method} ${urlPath}: ${JSON.stringify(answered.body)}`);
    assert.strictEqual(answered.body.error, 'kpi_catalogue_unavailable');
  }

  // Not signed in is still a 401, not a 503.
  const anonymous = await get({}, `/catalogue?site_id=${siteId}`);
  assert.strictEqual(anonymous.status, 401);

  const health = await (await fetch(`${base}/api/health`)).json();
  assert.strictEqual(health.kpi_catalogue, 'unconfigured');

  process.env.MTU_DATABASE_URL = process.env.DATABASE_URL;
  mtuPool = require('../../src/platform/mtu-db').getMtuPool();
  const configured = await (await fetch(`${base}/api/health`)).json();
  assert.strictEqual(configured.kpi_catalogue, 'configured');
});

test('the catalogue lists the 19 seeded KPIs, 16 with all three Targets and three with none', async () => {
  const { rows: [{ today }] } = await pool.query(
    'SELECT (now() AT TIME ZONE $1)::date::text AS today', [TIMEZONE]
  );

  const read = await get(writer.token, `/catalogue?site_id=${site.id}`);
  assert.strictEqual(read.status, 200, JSON.stringify(read.body));
  assert.strictEqual(read.body.site_id, Number(site.id));
  assert.strictEqual(read.body.review_date, today);
  assert.deepStrictEqual(read.body.kpis.map((k) => k.kpi_id), Array.from({ length: 19 }, (_, i) => i + 1));

  const byId = new Map(read.body.kpis.map((k) => [k.kpi_id, k]));
  for (const id of [3, 9, 10]) {
    assert.deepStrictEqual(byId.get(id).targets, { Daily: null, Weekly: null, Monthly: null }, `KPI ${id}`);
  }
  const withTargets = read.body.kpis.filter((k) => k.targets.Daily && k.targets.Weekly && k.targets.Monthly);
  assert.strictEqual(withTargets.length, 16);
  assert.strictEqual(byId.get(1).targets.Daily.target, 2.4);
  assert.strictEqual(byId.get(1).targets.Daily.valid_from, '2020-01-01');
  assert.strictEqual(byId.get(1).review, null);

  const bad = await get(writer.token, `/catalogue?site_id=${site.id}&date=2026-13-40`);
  assert.strictEqual(bad.status, 400);
});

test('adding a KPI answers 201, the same name again answers 409, and the new KPI is listed', async () => {
  const name = `Test KPI ${process.pid}`;
  const body = {
    site_id: site.id, kpi: name, title: `${name} (%)`, unit: '%', direction: '>=', decimals: 1
  };
  const added = await post(writer.token, '/catalogue', body);
  assert.strictEqual(added.status, 201, JSON.stringify(added.body));
  assert.strictEqual(typeof added.body.kpi_id, 'number');

  const again = await post(writer.token, '/catalogue', body);
  assert.strictEqual(again.status, 409, JSON.stringify(again.body));

  const invalid = await post(writer.token, '/catalogue', { ...body, kpi: 'Other', direction: '<' });
  assert.strictEqual(invalid.status, 400);

  const read = await get(writer.token, `/catalogue?site_id=${site.id}`);
  const listed = read.body.kpis.find((k) => k.kpi_id === added.body.kpi_id);
  assert.strictEqual(listed.kpi, name);
  assert.strictEqual(listed.value_measure, null);
  assert.deepStrictEqual(listed.targets, { Daily: null, Weekly: null, Monthly: null });
});

test('a Daily Target for a KPI without one is in force, a repeat is refused, and a correction is appended', async () => {
  const added = await post(writer.token, '/targets', {
    site_id: site.id, kpi_id: 3, grain: 'Daily', valid_from: '2020-01-02', target: 2.5, note: 'first'
  });
  assert.strictEqual(added.status, 201, JSON.stringify(added.body));
  assert.strictEqual(typeof added.body.target_id, 'number');

  const { rows: current } = await mtuPool.query(
    "SELECT target FROM kpi.v_target_current WHERE kpi_id = 3 AND grain = 'Daily'"
  );
  assert.strictEqual(Number(current[0].target), 2.5);

  const read = await get(writer.token, `/targets?site_id=${site.id}&kpi_id=3`);
  assert.strictEqual(read.status, 200, JSON.stringify(read.body));
  assert.deepStrictEqual(read.body.current.map((row) => row.grain), ['Daily', 'Weekly', 'Monthly']);
  assert.deepStrictEqual(read.body.current[0], { grain: 'Daily', valid_from: '2020-01-02', target: 2.5 });
  assert.strictEqual(read.body.current[1].target, null);

  const same = await post(writer.token, '/targets', {
    site_id: site.id, kpi_id: 3, grain: 'Daily', valid_from: '2020-01-02', target: 2.5
  });
  assert.strictEqual(same.status, 409, JSON.stringify(same.body));

  const corrected = await post(writer.token, '/targets', {
    site_id: site.id, kpi_id: 3, grain: 'Daily', valid_from: '2020-01-02', target: 3, note: 'typo'
  });
  assert.strictEqual(corrected.status, 201, JSON.stringify(corrected.body));

  const history = (await get(writer.token, `/targets?site_id=${site.id}&kpi_id=3`)).body.history;
  assert.deepStrictEqual(history.map((row) => row.target), [3, 2.5]);
  assert.deepStrictEqual(history.map((row) => row.is_effective), [true, false]);
  assert.strictEqual(history[0].target_id, corrected.body.target_id);
  assert.strictEqual(history[0].app_user, 'Kim Writer');

  const badGrain = await post(writer.token, '/targets', {
    site_id: site.id, kpi_id: 3, grain: 'Hourly', valid_from: '2020-01-02', target: 1
  });
  assert.strictEqual(badGrain.status, 400);
});

test('a missed Review with a five-character note is refused by name and writes nothing; a real note is saved', async () => {
  const entry = { kpi_id: 1, status: 'missed', observed: 3.1 };
  const refused = await post(writer.token, '/review', {
    site_id: site.id, date: REVIEW_DATE, app_user: 'Mallory', entries: [{ ...entry, note: 'short' }]
  });
  assert.strictEqual(refused.status, 400, JSON.stringify(refused.body));
  assert.ok(refused.body.message.includes('Scrap Ratio MTU (%)'), refused.body.message);

  const { rows: none } = await mtuPool.query(
    'SELECT 1 FROM kpi.kpi_review WHERE review_date = $1', [REVIEW_DATE]
  );
  assert.strictEqual(none.length, 0);

  const saved = await post(writer.token, '/review', {
    site_id: site.id,
    date: REVIEW_DATE,
    app_user: 'Mallory',
    entries: [{ ...entry, note: 'Blade worn out, replaced at 10:00' }]
  });
  assert.strictEqual(saved.status, 201, JSON.stringify(saved.body));
  assert.deepStrictEqual(saved.body, { saved: 1, review_date: REVIEW_DATE });

  const { rows: current } = await mtuPool.query(
    'SELECT status, app_user FROM kpi.v_kpi_review_current WHERE kpi_id = 1 AND review_date = $1', [REVIEW_DATE]
  );
  assert.strictEqual(current.length, 1);
  assert.strictEqual(current[0].status, 'missed');
  // The body's app_user is not trusted: the Account's own name is written.
  assert.strictEqual(current[0].app_user, 'Kim Writer');
});

test('a correction for the same KPI and day appends a second row and the newest decides', async () => {
  const corrected = await post(writer.token, '/review', {
    site_id: site.id, date: REVIEW_DATE, entries: [{ kpi_id: 1, status: 'met', observed: 2.2 }]
  });
  assert.strictEqual(corrected.status, 201, JSON.stringify(corrected.body));

  const { rows: all } = await mtuPool.query(
    'SELECT status FROM kpi.kpi_review WHERE kpi_id = 1 AND review_date = $1', [REVIEW_DATE]
  );
  assert.strictEqual(all.length, 2);
  const { rows: current } = await mtuPool.query(
    'SELECT status FROM kpi.v_kpi_review_current WHERE kpi_id = 1 AND review_date = $1', [REVIEW_DATE]
  );
  assert.strictEqual(current[0].status, 'met');

  const read = await get(writer.token, `/review?site_id=${site.id}&date=${REVIEW_DATE}`);
  assert.strictEqual(read.status, 200, JSON.stringify(read.body));
  assert.strictEqual(read.body.review_date, REVIEW_DATE);
  const row = read.body.rows.find((r) => r.kpi_id === 1);
  assert.strictEqual(row.status, 'met');
  assert.strictEqual(row.observed, 2.2);
  assert.strictEqual(row.target, 2.4);
  const unreviewed = read.body.rows.find((r) => r.kpi_id === 2);
  assert.strictEqual(unreviewed.status, null);
  assert.ok(read.body.rows.length >= 19);

  // The Daily Target in force on the day, not today's: KPI 3's Target starts
  // 2020-01-02, so it is absent the day before and corrected after.
  const before = await get(writer.token, `/review?site_id=${site.id}&date=2020-01-01`);
  assert.strictEqual(before.body.rows.find((r) => r.kpi_id === 3).target, null);
  const after = await get(writer.token, `/review?site_id=${site.id}&date=2020-01-02`);
  assert.strictEqual(after.body.rows.find((r) => r.kpi_id === 3).target, 3);
});

test('a read-only Grant reads all three, writes none, and an administrator needs no Grant', async () => {
  const { rows: [{ before }] } = await mtuPool.query(
    `SELECT (SELECT count(*) FROM kpi.kpi)::int + (SELECT count(*) FROM kpi.kpi_target)::int
          + (SELECT count(*) FROM kpi.kpi_review)::int AS before`
  );

  for (const urlPath of [
    `/catalogue?site_id=${site.id}`, `/targets?site_id=${site.id}&kpi_id=1`, `/review?site_id=${site.id}`
  ]) {
    const read = await get(reader.token, urlPath);
    assert.strictEqual(read.status, 200, `${urlPath}: ${JSON.stringify(read.body)}`);
  }

  const posts = [
    ['/catalogue', { site_id: site.id, kpi: 'Reader KPI', title: 'Reader KPI', direction: '<=', decimals: 0 }],
    ['/targets', { site_id: site.id, kpi_id: 1, grain: 'Daily', valid_from: '2026-06-01', target: 1 }],
    ['/review', { site_id: site.id, date: REVIEW_DATE, entries: [{ kpi_id: 2, status: 'met' }] }]
  ];
  for (const [urlPath, body] of posts) {
    const refused = await post(reader.token, urlPath, body);
    assert.strictEqual(refused.status, 403, `${urlPath}: ${JSON.stringify(refused.body)}`);
    assert.strictEqual(refused.body.code, 'OUTSIDE_GRANTED_ORG_UNITS');
  }

  const { rows: [{ after }] } = await mtuPool.query(
    `SELECT (SELECT count(*) FROM kpi.kpi)::int + (SELECT count(*) FROM kpi.kpi_target)::int
          + (SELECT count(*) FROM kpi.kpi_review)::int AS after`
  );
  assert.strictEqual(after, before);

  const allowed = await post(administrator.token, '/review', {
    site_id: site.id, date: REVIEW_DATE, entries: [{ kpi_id: 2, status: 'not_measured' }]
  });
  assert.strictEqual(allowed.status, 201, JSON.stringify(allowed.body));
});

test('an unknown KPI is a 409 on a Review and a 404 on a KPI\'s Targets', async () => {
  const review = await post(writer.token, '/review', {
    site_id: site.id, date: REVIEW_DATE, entries: [{ kpi_id: 999999, status: 'met' }]
  });
  assert.strictEqual(review.status, 409, JSON.stringify(review.body));

  const targets = await get(writer.token, `/targets?site_id=${site.id}&kpi_id=999999`);
  assert.strictEqual(targets.status, 404, JSON.stringify(targets.body));

  const noSite = await get(writer.token, '/catalogue?site_id=999999999');
  assert.strictEqual(noSite.status, 404);
});

test('a KPI id beyond the column\'s range is an unknown KPI, not a 500', async () => {
  const tooBig = 99999999999;

  const targets = await get(writer.token, `/targets?site_id=${site.id}&kpi_id=${tooBig}`);
  assert.strictEqual(targets.status, 404, JSON.stringify(targets.body));

  const target = await post(writer.token, '/targets', {
    site_id: site.id, kpi_id: tooBig, grain: 'Daily', valid_from: '2026-06-01', target: 1
  });
  assert.strictEqual(target.status, 404, JSON.stringify(target.body));

  const review = await post(writer.token, '/review', {
    site_id: site.id, date: REVIEW_DATE, entries: [{ kpi_id: tooBig, status: 'met' }]
  });
  assert.strictEqual(review.status, 409, JSON.stringify(review.body));
});

test('an observed number too large for the column is a 400 and writes nothing', async () => {
  const date = '2026-03-03';
  const refused = await post(writer.token, '/review', {
    site_id: site.id, date, entries: [{ kpi_id: 1, status: 'met', observed: 1e15 }]
  });
  assert.strictEqual(refused.status, 400, JSON.stringify(refused.body));

  const { rows } = await mtuPool.query('SELECT 1 FROM kpi.kpi_review WHERE review_date = $1', [date]);
  assert.strictEqual(rows.length, 0);
});
