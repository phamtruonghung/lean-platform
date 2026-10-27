/*
 * The Self-Closing section's machines and shift pattern, loaded by
 * dev/seed-relats-vietnam.mjs (issue #341, part of #332). Plant data is data,
 * so the seed is a script, not a migration; this test drives its exported load
 * functions twice against a SCRATCH database (created, migrated and dropped
 * here, never the shared one) and reads the rows back from Postgres.
 *
 * It does not shell out to the script: importing the module does not run it.
 * The scratch database is named after the process so concurrent runs cannot
 * collide. Needs DATABASE_URL pointing at a Postgres whose role may CREATE
 * DATABASE, as the local compose stack's does.
 */

const test = require('node:test');
const assert = require('node:assert');
const path = require('node:path');
const { Pool } = require('pg');
const { runner } = require('node-pg-migrate');

const scratchName = `platform_seed341_${process.pid}`;
let admin;
let scratch;
let seed;
let scratchUrl;

test.before(async () => {
  const url = new URL(process.env.DATABASE_URL);
  admin = new Pool({ connectionString: url.toString(), max: 1 });
  await admin.query(`CREATE DATABASE ${scratchName}`);
  url.pathname = `/${scratchName}`;
  scratchUrl = url.toString();

  await runner({
    databaseUrl: scratchUrl,
    dir: path.join(__dirname, '..', '..', 'migrations'),
    direction: 'up',
    migrationsTable: 'pgmigrations',
    log: () => {}
  });

  scratch = new Pool({ connectionString: scratchUrl, max: 1 });
  seed = await import('../../../dev/seed-relats-vietnam.mjs');
});

test.after(async () => {
  if (scratch) await scratch.end();
  if (admin) {
    await admin.query(`DROP DATABASE IF EXISTS ${scratchName} WITH (FORCE)`);
    await admin.end();
  }
});

async function runLoad() {
  for (const key of Object.keys(seed.counts)) delete seed.counts[key];
  const client = await scratch.connect();
  try {
    const { siteId } = await seed.loadTree(client, seed.readRows());
    await seed.loadShiftPattern(client, siteId);
    await seed.loadMachines(client, siteId);
    await seed.loadCalendar(client, siteId);
  } finally {
    client.release();
  }
  return JSON.parse(JSON.stringify(seed.counts));
}

async function count(sql) {
  const { rows: [row] } = await scratch.query(sql);
  return Number(row.n);
}

test('the load creates 17 machines and three shifts, and a second run changes nothing', async () => {
  const first = await runLoad();
  assert.strictEqual(first.assets.created, 17);
  assert.strictEqual(first.shift_definitions.created, 3);
  assert.strictEqual(await count('SELECT count(*) AS n FROM assets'), 17);
  assert.strictEqual(await count('SELECT count(*) AS n FROM shift_definitions'), 3);

  const instances = await count('SELECT count(*) AS n FROM shift_instances');
  assert.ok(instances >= 3 * 68, `expected three shifts a day for 68 days, got ${instances}`);
  assert.strictEqual(
    await count(`SELECT count(*) AS n FROM shift_instances si JOIN org_units ou ON ou.id = si.org_unit_id WHERE ou.code <> 'SC'`),
    0
  );

  const second = await runLoad();
  assert.strictEqual(second.assets?.created ?? 0, 0);
  assert.strictEqual(second.assets?.updated ?? 0, 0);
  assert.strictEqual(second.shift_definitions?.created ?? 0, 0);
  assert.strictEqual(second.org_units?.created ?? 0, 0);
  assert.strictEqual(await count('SELECT count(*) AS n FROM assets'), 17);
  assert.strictEqual(await count('SELECT count(*) AS n FROM shift_definitions'), 3);
  assert.strictEqual(await count('SELECT count(*) AS n FROM shift_instances'), instances);
  assert.strictEqual(await count('SELECT count(*) AS n FROM (SELECT code FROM assets GROUP BY code HAVING count(*) > 1) d'), 0);
  assert.strictEqual(
    await count(`SELECT count(*) AS n FROM assets a JOIN org_units ou ON ou.id = a.org_unit_id WHERE ou.code = 'SC-CUTTING-MTU' AND a.is_active`),
    17
  );
});

test('a re-run repairs a drifted machine name and leaves an existing shift pattern alone', async () => {
  await scratch.query(`UPDATE assets SET name = 'drifted' WHERE code = 'MTU40'`);
  await scratch.query(`UPDATE shift_definitions SET start_time = '07:00' WHERE code = 'A'`);

  const counts = await runLoad();
  assert.strictEqual(counts.assets.updated, 1);
  const { rows: [asset] } = await scratch.query(`SELECT name FROM assets WHERE code = 'MTU40'`);
  assert.strictEqual(asset.name, 'MTU40');
  const { rows: [shift] } = await scratch.query(`SELECT to_char(start_time, 'HH24:MI') AS t FROM shift_definitions WHERE code = 'A'`);
  assert.strictEqual(shift.t, '07:00');
});
