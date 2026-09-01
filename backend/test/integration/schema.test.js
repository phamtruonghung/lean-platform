/*
 * The baseline schema, the seeded catalogue, and the three baseline
 * corrections — asserted directly against Postgres.
 *
 * This is a *named exception* to the Platform's one test seam. Per issue #1's
 * Testing Decisions, the seam is HTTP against the running API with a real
 * database — testing below HTTP is explicitly rejected there, because ADR-0006
 * makes the Module boundary a code convention and a service-level test would
 * assert the convention rather than the behaviour a client can observe. This
 * file goes below that seam anyway, and is allowed to, only because there are
 * no endpoints over this schema yet: the People Module and the rest arrive in
 * issues #6-#12. Once a table has a Module and routes in front of it, its
 * behaviour belongs in an HTTP-level test, not here. Do not treat this file as
 * licence to reach for `getPool()` from a Module test later — it exists to
 * cover the gap before there is any HTTP surface to drive.
 *
 * Every test runs inside a transaction rolled back at the end (withRollback),
 * so the suite is repeatable against the same database with no truncate step
 * in between, and an expected-rejection statement runs inside a SAVEPOINT
 * (assertRejected) so a refused INSERT does not poison the rest of the
 * transaction. Both patterns are carried over from
 * maintenance-management's test/integration/schema.test.js.
 *
 * What this file deliberately does NOT assert: it does not enumerate every
 * column of every table — that is a change-detector that fails on every
 * future migration and proves nothing about behaviour. It does not check
 * every seeded row, only a handful of well-known ones by value, which is
 * enough to catch a seed silently truncating or dropping data without
 * pinning the whole catalogue. It does not test performance, indexes, or
 * anything about the tables the Maintenance and Tier Board Modules will own
 * beyond the corrections issue #4 calls out by name. View arithmetic (MTBF,
 * OEE, and so on) is out of scope here too — see test/integration/views.test.js
 * for the one thing asserted about views, which is that they resolve at all.
 *
 * Needs a database with the baseline migration applied — `npm run migrate`
 * against the same DATABASE_URL first. See the README's Tests section.
 */

const test = require('node:test');
const assert = require('node:assert');
const { getPool, closePool } = require('../../src/platform/db');

const pool = getPool();

test.after(async () => {
  await closePool();
});

// Every test runs inside a transaction that is rolled back, so the suite can
// be run repeatedly against the same database without a truncate between
// runs — see the file header.
async function withRollback(fn) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await fn(client);
  } finally {
    await client.query('ROLLBACK');
    client.release();
  }
}

// Asserting that a statement is refused needs a savepoint around it. A failed
// statement aborts the whole transaction, so without one the first expected
// rejection poisons every query after it in the same test.
async function assertRejected(client, sql, params, expected) {
  await client.query('SAVEPOINT expect_failure');
  await assert.rejects(() => client.query(sql, params), expected);
  await client.query('ROLLBACK TO SAVEPOINT expect_failure');
}

// ---------------------------------------------------------------------------
// 1. The schema applied: core tables a Module will build on exist and work.
// ---------------------------------------------------------------------------

test('a Site, an Org Unit beneath it, and an Employee round-trip', async () => {
  await withRollback(async (client) => {
    const { rows: [site] } = await client.query(
      `INSERT INTO sites (code, name, timezone)
       VALUES ('BUC', 'Bucharest', 'Europe/Bucharest') RETURNING id`
    );
    const { rows: [orgUnit] } = await client.query(
      `INSERT INTO org_units (site_id, code, name, unit_type)
       VALUES ($1, 'L1', 'Line 1', 'line') RETURNING id`,
      [site.id]
    );
    const { rows: [employee] } = await client.query(
      `INSERT INTO employees (employee_no, first_name, last_name, default_org_unit_id)
       VALUES ('SCH-E1', 'Ada', 'Fitter', $1) RETURNING id`,
      [orgUnit.id]
    );

    // Read back through the relationships rather than by primary key alone,
    // so a foreign key pointed at the wrong table would show up here rather
    // than passing silently.
    const { rows: [readBack] } = await client.query(
      `SELECT s.code AS site_code, ou.code AS org_unit_code, e.display_name
       FROM employees e
       JOIN org_units ou ON ou.id = e.default_org_unit_id
       JOIN sites s ON s.id = ou.site_id
       WHERE e.id = $1`,
      [employee.id]
    );

    assert.strictEqual(readBack.site_code, 'BUC');
    assert.strictEqual(readBack.org_unit_code, 'L1');
    // display_name is a generated column, so this also proves the schema's
    // generated columns are computing rather than merely present.
    assert.strictEqual(readBack.display_name, 'Ada Fitter');
  });
});

// ---------------------------------------------------------------------------
// 2. The seeded catalogue is present, by value, and global rather than
//    per-Site — per ADR-0005: KPI definitions, downtime reasons, defect
//    codes, injury types, units of measure and absence reasons.
// ---------------------------------------------------------------------------

const GLOBAL_CATALOGUE = [
  { table: 'units_of_measure', code: 'EA', name: 'Each' },
  { table: 'kpi_definitions', code: 'SAF_TRIR', name: 'Recordable injury rate (TRIR)' },
  { table: 'downtime_reasons', code: 'BRK-MECH', name: 'Mechanical failure' },
  { table: 'defect_codes', code: 'DIM-OOT', name: 'Out of tolerance' },
  { table: 'injury_types', code: 'CUT', name: 'Cut or laceration' },
  { table: 'absence_reasons', code: 'SICK', name: 'Sickness' }
];

test('the global reference catalogue is seeded, checked by value, and carries no per-Site scope', async () => {
  await withRollback(async (client) => {
    for (const { table, code, name } of GLOBAL_CATALOGUE) {
      // A well-known row by value, not just count > 0, so a seed that silently
      // truncates or renames a row is caught rather than passing on row count.
      const { rows } = await client.query(`SELECT name FROM ${table} WHERE code = $1`, [code]);
      assert.strictEqual(rows.length, 1, `expected ${table} to carry a seeded row for '${code}'`);
      assert.strictEqual(rows[0].name, name);

      // "Global" is a structural claim as much as a data one: a catalogue
      // shared by every Site cannot have a column to scope it by Site in the
      // first place.
      const { rows: siteScoped } = await client.query(
        `SELECT 1 FROM information_schema.columns
         WHERE table_schema = 'public' AND table_name = $1 AND column_name = 'site_id'`,
        [table]
      );
      assert.strictEqual(siteScoped.length, 0, `${table} must not be scoped to a Site`);
    }
  });
});

// ---------------------------------------------------------------------------
// 3. Job roles, skills and failure codes are NOT seeded — per ADR-0005 (and
//    the baseline's own reference-data comment) they are entered per
//    deployment, because what a title or a skill means differs by plant in a
//    way a downtime reason or a defect code does not.
// ---------------------------------------------------------------------------

test('job roles, skills and failure codes start empty: they are entered per deployment, not seeded', async () => {
  await withRollback(async (client) => {
    for (const table of ['job_roles', 'skills', 'failure_codes']) {
      const { rows: [{ n }] } = await client.query(`SELECT count(*)::int AS n FROM ${table}`);
      assert.strictEqual(n, 0, `expected ${table} to start empty per ADR-0005`);
    }
  });
});

// ---------------------------------------------------------------------------
// 4. The three baseline corrections.
// ---------------------------------------------------------------------------

test('no attachments table exists anywhere in the schema', async () => {
  const { rows } = await pool.query(
    `SELECT table_schema, table_name FROM information_schema.tables WHERE table_name = 'attachments'`
  );
  assert.deepStrictEqual(rows, []);
});

test('no view references an attachments relation', async () => {
  const { rows } = await pool.query(
    `SELECT viewname FROM pg_views WHERE schemaname = 'public' AND definition ILIKE '%attachments%'`
  );
  assert.deepStrictEqual(rows, []);
});

test('no directory_user_id column exists anywhere in the schema', async () => {
  const { rows } = await pool.query(
    `SELECT table_name FROM information_schema.columns WHERE column_name = 'directory_user_id'`
  );
  assert.deepStrictEqual(rows, []);
});

test('employees.work_email is case-insensitively unique', async () => {
  await withRollback(async (client) => {
    await client.query(
      `INSERT INTO employees (employee_no, first_name, last_name, work_email)
       VALUES ('SCH-CI1', 'Foo', 'One', 'Foo@Example.com')`
    );

    // Differs only in case from the row above. Two employees entered this way
    // are one person entered twice, which is exactly what the index exists to
    // refuse.
    await assertRejected(
      client,
      `INSERT INTO employees (employee_no, first_name, last_name, work_email)
       VALUES ('SCH-CI2', 'Foo', 'Two', 'foo@example.com')`,
      [],
      /employees_work_email_key/
    );
  });
});

// ---------------------------------------------------------------------------
// 5. Document numbers are Site-scoped (ADR-0005). Two Sites each get their
//    own independent run, and the number returned identifies the Site that
//    issued it.
// ---------------------------------------------------------------------------

test('document numbers are scoped by Site: two Sites issue independent, non-interleaved runs', async () => {
  await withRollback(async (client) => {
    // Tagged with this process's pid rather than a fixed code like 'BUC'.
    // The assertions below name exact numbers, so they need a counter that has
    // never been drawn from. This transaction rolls back, so the run it makes
    // leaves nothing behind — but a Site code somebody else has already issued
    // numbers under, from a psql prompt or an earlier committed run against a
    // shared development database, would start this test from wherever that
    // history left the counter rather than from 1. A per-process code cannot
    // collide with that.
    const codeA = `Z${process.pid}A`;
    const codeB = `Z${process.pid}B`;

    const { rows: [siteA] } = await client.query(
      'INSERT INTO sites (code, name) VALUES ($1, $2) RETURNING code',
      [codeA, 'Bucharest']
    );
    const { rows: [siteB] } = await client.query(
      'INSERT INTO sites (code, name) VALUES ($1, $2) RETURNING code',
      [codeB, 'Cluj-Napoca']
    );

    // Interleaved on purpose — A, B, A, B — so a shared counter would show up
    // as a skipped or duplicated number rather than as a coincidence of
    // calling one Site twice in a row.
    const a1 = await client.query('SELECT next_document_number($1, $2, $3) AS n', ['WO', siteA.code, 2026]);
    const b1 = await client.query('SELECT next_document_number($1, $2, $3) AS n', ['WO', siteB.code, 2026]);
    const a2 = await client.query('SELECT next_document_number($1, $2, $3) AS n', ['WO', siteA.code, 2026]);
    const b2 = await client.query('SELECT next_document_number($1, $2, $3) AS n', ['WO', siteB.code, 2026]);

    // Format is <prefix>-<site code>-<year>-<sequence>, e.g. WO-BUC-2026-00001.
    assert.strictEqual(a1.rows[0].n, `WO-${codeA}-2026-00001`);
    assert.strictEqual(b1.rows[0].n, `WO-${codeB}-2026-00001`);
    assert.strictEqual(a2.rows[0].n, `WO-${codeA}-2026-00002`);
    assert.strictEqual(b2.rows[0].n, `WO-${codeB}-2026-00002`);
  });
});

// ---------------------------------------------------------------------------
// 6. refresh_sqdcp_rollups() runs nightly in production. PostgreSQL 17 forces
//    search_path to pg_catalog, pg_temp for the duration of REFRESH
//    MATERIALIZED VIEW, which re-parses every LANGUAGE sql function the
//    matview's definition inlines — so an unqualified table or ltree function
//    reference inside one of those functions can pass `npm run migrate` and
//    still fail here, every night, in production. This is not view
//    arithmetic (out of scope per the file header above): it asserts that the
//    refresh executes at all, not what numbers it produces. No withRollback
//    here — REFRESH MATERIALIZED VIEW CONCURRENTLY cannot run inside a
//    transaction block.
// ---------------------------------------------------------------------------

test('refresh_sqdcp_rollups() succeeds against the schema as migrated', async () => {
  await pool.query('SELECT refresh_sqdcp_rollups()');
});

// ---------------------------------------------------------------------------
// 7. sqdcp_maintenance() is what pg_cron runs nightly in production — see
//    migrations/1756000000001_schedule-maintenance.js and issue #19. It calls
//    refresh_sqdcp_rollups() (asserted above) and then ensure_time_partitions()
//    for measurements and audit_log. This is the assertion issue #19 asked
//    for: that calling it actually produces the next month's partition for
//    both tables, not merely that the call returns.
//
//    Right after a fresh migration, both tables already have partitions for
//    months well beyond next month — the baseline creates twelve months
//    ahead on its own — so asserting existence alone would pass whether or
//    not sqdcp_maintenance() does anything. This drops next month's
//    partition first, which is exactly the state the issue describes months
//    from now once nobody has been running the maintenance job: a real gap
//    that only sqdcp_maintenance() (never the baseline, which only runs
//    once) can fill back in.
//
//    No withRollback here, for the same reason as the test above: it calls
//    refresh_sqdcp_rollups(), and REFRESH MATERIALIZED VIEW CONCURRENTLY
//    cannot run inside a transaction block.
//
//    Forcing the gap means dropping next month's partition, and measurements
//    and audit_log are the two tables in this schema actually built to carry
//    volume. Nothing in *this suite* puts rows there, but DATABASE_URL is
//    just a connection string — nothing stops it pointing at a database that
//    does, and the README leaves that choice to whoever runs the integration
//    tier. So this counts the partition's own rows (not the parent table's —
//    that would count rows a drop of this one partition would not touch)
//    before going anywhere near DROP TABLE, and refuses to drop anything
//    that is not empty. On a database with real data here, the failure this
//    produces is a named table and a row count, not silently discarded
//    measurements.
// ---------------------------------------------------------------------------

test('sqdcp_maintenance() creates next month\'s partition for measurements and audit_log', async () => {
  const { rows: [{ month_label }] } = await pool.query(
    `SELECT to_char(date_trunc('month', now()) + INTERVAL '1 month', 'YYYYMM') AS month_label`
  );

  const tables = ['measurements', 'audit_log'];

  // Force the gap: drop next month's partition if the baseline (or an
  // earlier run of this suite) already created it — but only once its own
  // row count is confirmed to be zero. See the section header above for why
  // this check exists rather than dropping unconditionally.
  for (const table of tables) {
    const partition = `${table}_${month_label}`;
    const { rows: [{ r }] } = await pool.query('SELECT to_regclass($1) AS r', [partition]);
    if (r === null) {
      continue;
    }

    const { rows: [{ n }] } = await pool.query(`SELECT count(*)::int AS n FROM ${partition}`);
    assert.strictEqual(
      n,
      0,
      `refusing to drop ${partition}: it holds ${n} row(s). This test only forces a ` +
        `partition gap on an empty partition, and declines to touch one that is not.`
    );

    await pool.query(`DROP TABLE ${partition}`);
  }
  for (const table of tables) {
    const { rows: [{ r }] } = await pool.query('SELECT to_regclass($1) AS r', [`${table}_${month_label}`]);
    assert.strictEqual(r, null, `expected ${table}_${month_label} to be gone before sqdcp_maintenance() runs`);
  }

  await pool.query('SELECT sqdcp_maintenance()');

  for (const table of tables) {
    const { rows: [{ r }] } = await pool.query('SELECT to_regclass($1) AS r', [`${table}_${month_label}`]);
    assert.strictEqual(r, `${table}_${month_label}`, `expected sqdcp_maintenance() to recreate ${table}_${month_label}`);
  }
});
