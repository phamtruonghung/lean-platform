/*
 * Deny-all Row Level Security and the read-only `powerbi_reader` role,
 * asserted directly against Postgres. See issue #5, ADR-0004
 * (docs/adr/0004-deny-all-rls-with-two-database-clients.md), and
 * migrations/1756000000002_deny-all-rls.js, which this file covers.
 *
 * This is a *named exception* to the Platform's one test seam, on the same
 * grounds test/integration/schema.test.js already claims one: per issue #1's
 * Testing Decisions, the seam is HTTP against the running API — but there is
 * no HTTP surface over role privileges or RLS at all, and there never will
 * be, so there is no future Module test this can be superseded by the way
 * schema.test.js expects to be. This stays below HTTP permanently.
 *
 * `withRollback` and `assertRejected` are carried over from schema.test.js
 * verbatim — see that file's header for why each exists.
 *
 * Needs a database with every migration applied, including
 * 1756000000002_deny-all-rls.js — `npm run migrate` against the same
 * DATABASE_URL first. See the README's Tests section.
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
// runs — see schema.test.js.
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
// 1. Every base table has RLS enabled with zero policies — the deny-all
//    floor itself. Catalog-driven: relkind IN ('r', 'p') is exactly the
//    enumeration the migration uses to decide what to enable RLS on (see its
//    own comment for why both relkinds are needed — 'p' catches the two
//    partitioned parents, measurements and audit_log, which 'r' alone would
//    miss), so this test walks the same list the migration wrote to, rather
//    than a second, independently-hardcoded one that could drift from it.
// ---------------------------------------------------------------------------

test('every base table in public has RLS enabled with no policies defined', async () => {
  const { rows: tables } = await pool.query(`
    SELECT c.relname
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public'
       AND c.relkind IN ('r', 'p')
     ORDER BY c.relname
  `);

  // If this enumeration ever came back empty, the loop below would pass
  // vacuously and the test would prove nothing. The baseline defines well
  // over a hundred tables and partitions, so an empty result here means the
  // query itself is broken, not that the schema has none.
  assert.ok(tables.length > 0, 'expected the catalog query to list at least one base table');

  for (const { relname } of tables) {
    // Namespace-filtered, and the missing-row case handled explicitly
    // rather than destructured straight off `rows[0]`. `node --test` runs
    // test *files* in parallel by default (see `package.json`'s
    // `test:integration` script), and schema.test.js's own
    // "sqdcp_maintenance() creates next month's partition for measurements
    // and audit_log" test drops and recreates a `measurements_<next-month>`
    // / `audit_log_<next-month>` partition outside a transaction. If that
    // drop lands between this test's enumeration query above and this
    // per-table lookup, an unfiltered, unguarded
    // `rows: [{ relrowsecurity }]` throws "Cannot destructure property
    // 'relrowsecurity' of 'undefined'" — a real flake, not a schema bug.
    // Filtering by namespace also just makes this query correct on its own
    // terms: `relname` alone is not unique across schemas, and this test
    // means the `public` table specifically.
    const { rows } = await pool.query(
      `SELECT c.relrowsecurity
         FROM pg_class c
         JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND c.relname = $1`,
      [relname]
    );
    assert.strictEqual(
      rows.length, 1,
      `expected exactly one public.${relname} to still exist — it disappeared between the ` +
        `enumeration above and this lookup, which is informative (a concurrent test dropped ` +
        `it) rather than something to paper over with a vacuous pass`
    );
    assert.strictEqual(rows[0].relrowsecurity, true, `expected ${relname} to have RLS enabled`);

    const { rows: policies } = await pool.query(
      'SELECT 1 FROM pg_policies WHERE schemaname = $1 AND tablename = $2', ['public', relname]
    );
    assert.deepStrictEqual(policies, [], `expected ${relname} to carry no policies (deny-all floor)`);
  }
});

// ---------------------------------------------------------------------------
// 1a. A partition created AFTER this migration has already run — the way
//     every monthly measurements/audit_log partition from here on is
//     created, by ensure_time_partitions() via the nightly pg_cron job — is
//     born with RLS already enabled too. This is not automatic: a partition
//     does not inherit its parent's relrowsecurity flag merely by being
//     attached to it (see migrations/1756000000002_deny-all-rls.js's own
//     comment on step 1a for the reproduction that found this). What makes
//     it true here is that migration's step 1a redefining
//     ensure_time_partitions() itself, so this test calls that function
//     directly rather than re-deriving the same fact test 1 above already
//     covers for tables that existed when the migration ran.
//
//     ensure_time_partitions() takes ACCESS EXCLUSIVE on the parent table
//     (audit_log here) for as long as this transaction holds it open — the
//     whole test, since it runs inside withRollback and the lock is not
//     released until ROLLBACK. `node --test` runs test *files* in parallel
//     by default (package.json's test:integration script), and
//     schema.test.js's "sqdcp_maintenance() creates next month's partition
//     for measurements and audit_log" test takes the same lock on the same
//     parent table — via DROP TABLE and, inside sqdcp_maintenance(),
//     CREATE TABLE ... PARTITION OF — as plain non-transactional pool.query
//     calls, not wrapped in BEGIN/COMMIT. Investigated rather than assumed
//     safe: backend/src/platform/db.js's Pool config sets max, idleTimeoutMillis
//     and connectionTimeoutMillis only — no statement_timeout, no
//     query_timeout, no idle_in_transaction_session_timeout — and
//     package.json's test:integration script passes no --test-timeout to
//     `node --test`, which has no default per-test timeout of its own
//     absent that flag. With no timeout configured anywhere in this stack,
//     lock contention between these two tests causes at most serialization
//     (whichever runs second waits for the first's transaction to end), not
//     a failure or a deadlock: this test only ever takes the lock and then
//     issues read-only SELECTs afterward, and schema.test.js's statements
//     are separate, single, non-transactional statements with no reciprocal
//     lock of their own to create a circular wait. So this is left as-is —
//     restructuring to minimize what runs inside the lock was considered
//     and set aside as unnecessary given that finding, not overlooked.
// ---------------------------------------------------------------------------

test('a partition created after this migration by ensure_time_partitions() is born with RLS enabled', async () => {
  await withRollback(async (client) => {
    // Far enough in the future that no earlier test run or seed data could
    // have created this partition already — collisions here would make the
    // "IS NULL" branch inside ensure_time_partitions() skip creation
    // entirely and this test would pass vacuously against an old partition.
    const futureMonth = `2099-0${(process.pid % 9) + 1}-01`;

    const { rows: [{ created }] } = await client.query(
      'SELECT ensure_time_partitions($1, $2::date, $2::date) AS created',
      ['audit_log', futureMonth]
    );
    assert.strictEqual(created, 1, 'expected ensure_time_partitions() to create exactly one new partition');

    const { rows: [{ partition_name }] } = await client.query(
      `SELECT 'audit_log_' || to_char($1::date, 'YYYYMM') AS partition_name`,
      [futureMonth]
    );

    // Namespace-filtered and the missing-row case handled explicitly, for
    // consistency with the same fix in the test above — the risk that
    // motivates it there (a concurrent drop landing between enumeration and
    // lookup) does not really apply to a partition this test just created
    // inside its own not-yet-committed transaction, but the query should
    // still say what it means: this table, in `public`, not a same-named
    // relation anywhere else.
    const { rows } = await client.query(
      `SELECT c.relrowsecurity
         FROM pg_class c
         JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND c.relname = $1`,
      [partition_name]
    );
    assert.strictEqual(rows.length, 1, `expected public.${partition_name} to exist right after creating it`);
    assert.strictEqual(rows[0].relrowsecurity, true, `expected ${partition_name} to have RLS enabled at creation`);
  });
});

// ---------------------------------------------------------------------------
// 2. `anon` and `authenticated` hold no privileges in public, and genuinely
//    cannot read a table — checked two ways, per the header comment on why:
//    a catalog check proves the grants are gone, and an attempted SELECT
//    under SET ROLE proves that absence actually stops a read, not just that
//    the bookkeeping looks right.
//
//    Both roles are Supabase-provisioned and do not exist on the stock
//    postgres image this repository's CI and local docker compose run
//    against — see migrations/1756000000002_deny-all-rls.js's own guard for
//    the same gap. Where a role does not exist, the privilege-count half of
//    this test still holds (there is nothing to hold a grant, so the count
//    is trivially zero), but the SET ROLE half cannot run at all — SET ROLE
//    to a role that does not exist is itself an error, not a permission
//    failure — so that half is skipped explicitly, with the reason logged,
//    rather than silently reporting a pass it never checked.
// ---------------------------------------------------------------------------

for (const role of ['anon', 'authenticated']) {
  test(`${role} holds no privileges in public`, async () => {
    // information_schema.role_table_grants quietly omits materialized views
    // (not a standard SQL object), which would let a lingering grant on
    // mv_daily_oee pass unnoticed — pg_class.relacl is checked directly as
    // well so that gap does not exist here.
    // Scoped to table_schema = 'public': on production, `anon` holds 1002
    // grants total, 973 of them in `public` and the remaining 29 in
    // `realtime`/`storage` — Supabase-owned schemas this migration must
    // never touch (see the migration's own comment on why every REVOKE
    // below names `anon`/`authenticated` explicitly rather than reaching
    // for a broader target). An unscoped count here would fail this test
    // against production even though the actual claim it makes — no
    // privileges in `public` — genuinely holds.
    const { rows: [{ n }] } = await pool.query(
      `SELECT count(*)::int AS n FROM information_schema.role_table_grants
        WHERE grantee = $1 AND table_schema = 'public'`,
      [role]
    );
    assert.strictEqual(n, 0, `expected ${role} to hold no information_schema-visible grants in public`);

    // aclexplode(), not a bare unnest(): relacl is an array of aclitem, an
    // opaque type with no dot-accessible fields of its own — aclexplode() is
    // the documented way to turn it into rows with a real grantee column.
    const { rows: [{ n: relacl_n }] } = await pool.query(
      `SELECT count(*)::int AS n
         FROM pg_class c
         JOIN pg_namespace ns ON ns.oid = c.relnamespace, aclexplode(c.relacl) acl
        WHERE ns.nspname = 'public'
          AND acl.grantee = (SELECT oid FROM pg_roles WHERE rolname = $1)`,
      [role]
    );
    assert.strictEqual(relacl_n, 0, `expected ${role} to appear in no table's relacl, including matviews`);
  });

  test(`${role} cannot SELECT from a base table, where the role exists to test this`, async (t) => {
    const { rows: [{ exists: roleExists }] } = await pool.query(
      'SELECT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = $1) AS exists', [role]
    );

    if (!roleExists) {
      t.skip(
        `role "${role}" does not exist on this Postgres — expected on the stock image ` +
        `CI and local docker compose run; only a Supabase-provisioned project has it, ` +
        `and that is where this assertion actually exercises anything.`
      );
      return;
    }

    await withRollback(async (client) => {
      await client.query(`SET ROLE ${role}`);
      await assertRejected(
        client,
        'SELECT * FROM sites',
        [],
        /permission denied for table sites/
      );
      await client.query('RESET ROLE');
    });
  });
}

// ---------------------------------------------------------------------------
// 2a. Nothing holds EXECUTE on any routine in `public` — PUBLIC itself
//     included, per migrations/1756000000002_deny-all-rls.js's step 2a.
//     This is a distinct claim from "anon/authenticated hold no privileges"
//     above: Postgres grants EXECUTE on every function to the PUBLIC
//     pseudo-role implicitly, at CREATE FUNCTION time, independent of any
//     anon- or authenticated-specific ACL entry, so the per-role checks
//     above do not exercise this at all — a database that never ran step 2a
//     would still pass every assertion above while leaving all 342
//     functions this migration found on production wide open. Enumerated
//     from pg_proc rather than hardcoded to a function count, for the same
//     reason the base-table enumeration above walks the catalog instead of
//     a fixed list.
// ---------------------------------------------------------------------------

test('PUBLIC holds no EXECUTE on any routine in public', async () => {
  const { rows: routines } = await pool.query(`
    SELECT p.oid::text AS oid, p.proname
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
  `);

  // Same reasoning as the base-table enumeration's own guard: an empty
  // result here would make the loop below pass vacuously. The baseline
  // defines well over a hundred functions (342, on production), so an
  // empty result means this query is broken, not that the schema has none.
  assert.ok(routines.length > 0, 'expected the catalog query to list at least one routine in public');

  for (const { oid, proname } of routines) {
    // has_function_privilege() treats the literal string 'public' as the
    // PUBLIC pseudo-role — the documented way to check a privilege granted
    // to PUBLIC specifically, since PUBLIC has no row in pg_roles to join
    // against the way the anon/authenticated checks below do.
    const { rows: [{ has_exec }] } = await pool.query(
      `SELECT has_function_privilege('public', $1::oid, 'EXECUTE') AS has_exec`,
      [oid]
    );
    assert.strictEqual(has_exec, false, `expected PUBLIC to hold no EXECUTE on ${proname}`);
  }
});

for (const role of ['anon', 'authenticated']) {
  test(`${role} holds no EXECUTE on any routine in public, where the role exists to test this`, async (t) => {
    const { rows: [{ exists: roleExists }] } = await pool.query(
      'SELECT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = $1) AS exists', [role]
    );

    if (!roleExists) {
      t.skip(
        `role "${role}" does not exist on this Postgres — expected on the stock image ` +
        `CI and local docker compose run; only a Supabase-provisioned project has it, ` +
        `and that is where this assertion actually exercises anything.`
      );
      return;
    }

    const { rows: [{ n }] } = await pool.query(
      `SELECT count(*)::int AS n
         FROM pg_proc p
         JOIN pg_namespace ns ON ns.oid = p.pronamespace
        WHERE ns.nspname = 'public'
          AND has_function_privilege($1, p.oid, 'EXECUTE')`,
      [role]
    );
    assert.strictEqual(n, 0, `expected ${role} to hold EXECUTE on no routine in public`);
  });
}

// ---------------------------------------------------------------------------
// 3. powerbi_reader can read a base table and a view, cannot write anywhere,
//    and does so via SET ROLE within this same connection/transaction — not
//    a fresh connection logging in as powerbi_reader directly. Postgres role
//    attributes (BYPASSRLS among them) apply to whichever role is currently
//    active, regardless of how the session came to be that role, so this is
//    expected to work and its success is itself the proof that BYPASSRLS
//    applies under SET ROLE, not only under a direct login.
// ---------------------------------------------------------------------------

// powerbi_reader existing is not the same claim as powerbi_reader having
// the right attributes. migrations/1756000000002_deny-all-rls.js's
// existence guard only stops CREATE ROLE erroring on a duplicate — an
// operator-precreated or earlier-draft role that exists but lacks
// BYPASSRLS would previously have passed this migration silently and then
// read nothing from anything (see that migration's own comment on its ELSE
// branch). This checks the actual attributes in pg_roles, not merely that
// a row with this name is there.
test('powerbi_reader has LOGIN and BYPASSRLS, not merely exists', async () => {
  const { rows: [role] } = await pool.query(
    'SELECT rolcanlogin, rolbypassrls FROM pg_roles WHERE rolname = $1', ['powerbi_reader']
  );
  assert.ok(role, 'expected a powerbi_reader row in pg_roles');
  assert.strictEqual(role.rolcanlogin, true, 'expected powerbi_reader to have LOGIN');
  assert.strictEqual(role.rolbypassrls, true, 'expected powerbi_reader to have BYPASSRLS');
});

test('powerbi_reader reads a base table and a view under SET ROLE, proving BYPASSRLS applies there', async () => {
  await withRollback(async (client) => {
    await client.query('SET ROLE powerbi_reader');

    // sites is a base table under deny-all RLS with zero policies — reading
    // it at all, as a non-owner role with no policy granting it anything,
    // only succeeds because powerbi_reader holds BYPASSRLS.
    await assert.doesNotReject(
      () => client.query('SELECT * FROM sites'),
      'expected powerbi_reader to read the sites table'
    );

    // A view, picked from the catalog rather than hardcoded, for the same
    // reason views.test.js in this directory picks its views dynamically:
    // this should hold for any view the baseline defines, not one name in
    // particular. A view executes as its owner and reads straight through
    // RLS regardless of the caller (ADR-0004's Consequences section), so
    // this exercises the GRANT SELECT ON ALL TABLES IN SCHEMA public
    // covering views, not BYPASSRLS a second time.
    const { rows: [{ viewname }] } = await client.query(
      `SELECT viewname FROM pg_views WHERE schemaname = 'public' ORDER BY viewname LIMIT 1`
    );
    assert.ok(viewname, 'expected at least one view to exist in public');
    await assert.doesNotReject(
      () => client.query(`SELECT * FROM ${viewname} WHERE false`),
      `expected powerbi_reader to read ${viewname}`
    );

    await client.query('RESET ROLE');
  });
});

test('powerbi_reader cannot INSERT, UPDATE, or DELETE anywhere', async () => {
  await withRollback(async (client) => {
    await client.query('SET ROLE powerbi_reader');

    // WHERE false / a SELECT ... WHERE false source means each statement
    // would affect zero rows even if it were allowed — the point of each
    // assertion is that the privilege check refuses the statement outright,
    // not that it would have changed data.
    await assertRejected(
      client,
      `INSERT INTO sites (code, name) SELECT 'RLSTEST', 'RLS Test' WHERE false`,
      [],
      /permission denied for table sites/
    );
    await assertRejected(
      client,
      'UPDATE sites SET name = name WHERE false',
      [],
      /permission denied for table sites/
    );
    await assertRejected(
      client,
      'DELETE FROM sites WHERE false',
      [],
      /permission denied for table sites/
    );

    await client.query('RESET ROLE');
  });
});

// ---------------------------------------------------------------------------
// 4. The owner path — the role DATABASE_URL actually connects as, `platform`
//    locally and `postgres` in production — still reads and writes fine with
//    RLS enabled everywhere and no policies anywhere. This is what makes the
//    whole migration safe for the API: see its file header.
//
//    Locally this is close to trivial: `platform` is a local superuser, and
//    a superuser bypasses RLS unconditionally, the same way BYPASSRLS does,
//    so this test cannot distinguish "RLS correctly lets the owner through"
//    from "this role would have ignored RLS no matter what". Production's
//    `postgres` is not a superuser — it is a table owner with BYPASSRLS, per
//    this issue's own verified production facts — so the mechanism this test
//    exercises locally (owner/BYPASSRLS access surviving RLS being turned
//    on) is the right one, even though the local role happens to have a
//    second, unrelated reason to pass it too.
// ---------------------------------------------------------------------------

test('the connecting role (table owner) still reads and writes under RLS unchanged', async () => {
  await withRollback(async (client) => {
    const code = `OWN${process.pid}`;
    const { rows: [inserted] } = await client.query(
      'INSERT INTO sites (code, name) VALUES ($1, $2) RETURNING id, code',
      [code, 'Owner Path Test']
    );
    assert.strictEqual(inserted.code, code);

    const { rows: [read] } = await client.query('SELECT code FROM sites WHERE id = $1', [inserted.id]);
    assert.strictEqual(read.code, code);

    await client.query('UPDATE sites SET name = $1 WHERE id = $2', ['Renamed', inserted.id]);
    await client.query('DELETE FROM sites WHERE id = $1', [inserted.id]);
  });
});
