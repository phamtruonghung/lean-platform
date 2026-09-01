/**
 * Deny-all Row Level Security, and a read-only reporting role. See issue #5
 * and ADR-0004 (docs/adr/0004-deny-all-rls-with-two-database-clients.md),
 * which this migration implements verbatim.
 *
 * Today RLS is off on every table. Supabase publishes an `anon` key to every
 * browser and PostgREST is reachable from the internet, so that key alone —
 * not a bug, not a misconfiguration, just the key doing what a public key
 * does — currently reads and writes all 68 tables. That is the live exposure
 * this migration closes.
 *
 * The fix is not per-table policies. Per ADR-0004, real row-visibility rules
 * would duplicate in SQL the invariants the API already owns (the PM
 * generation guard, document numbering, "a second breakdown report joins the
 * open Downtime Event rather than starting another") and those are not
 * row-visibility rules to begin with. Instead this is a floor: RLS enabled
 * everywhere, with zero policies, so every role except one reads nothing at
 * all from a base table — and the one exception is granted access
 * deliberately and narrowly, through ordinary GRANTs, not through a policy.
 *
 * Three things happen here, in order:
 *
 *   1. RLS is enabled, with no policies, on every base table that exists in
 *      `public` at the moment this migration runs — enumerated from the
 *      catalog rather than hardcoded, so this covers the 68 tables that
 *      exist today without naming them one by one. That enumeration is a
 *      one-time sweep, not a standing guarantee: the `DO $$ ... $$` block
 *      below runs once, against the tables that exist when this migration
 *      is applied, and does not run again for a table a *later* migration
 *      creates. A table added by a future migration is NOT born with RLS
 *      enabled automatically — unlike the `ALTER DEFAULT PRIVILEGES` grants
 *      in steps 2 and 3 below, which genuinely do apply to future objects,
 *      because Postgres evaluates default privileges at object-creation
 *      time and does not need this migration's own DO block to run again to
 *      take effect. So every future migration that creates a table in
 *      `public` carries its own obligation: enable RLS on that table
 *      itself, in that migration, or it ships open. Nothing here enforces
 *      that automatically — an event trigger on `ddl_command_end` for
 *      `CREATE TABLE` could, in principle, close this gap for good, but
 *      that is a design decision left for later, not something this
 *      migration takes on.
 *   2. `anon` and `authenticated` — the two Supabase roles a browser can act
 *      as — are stripped of every table, sequence, and role-specific
 *      routine privilege they hold in `public`: current grants revoked, and
 *      future ones headed off with ALTER DEFAULT PRIVILEGES. Routines also
 *      get a second, separate step right after (2a) that closes a different
 *      gap those two REVOKEs alone do not touch: the EXECUTE every function
 *      carries for the PUBLIC pseudo-role from the moment it is created,
 *      regardless of `anon` or `authenticated` specifically.
 *   3. `powerbi_reader` is created: a dedicated, read-only role for the one
 *      legitimate second client this database has, per ADR-0004.
 *
 * None of this touches how the API itself connects. Production's API
 * connects as `postgres`, which owns every table in this schema (it ran the
 * baseline and every migration since) and holds `rolbypassrls = true`. A
 * table's owner, and any role with BYPASSRLS, ignores RLS entirely — RLS
 * exists to restrict everyone else, not the role that already owns the data.
 * So enabling RLS here needs no API code change, and this migration makes no
 * change to `src/platform/db.js` or anywhere else the API reads from — see
 * `test/integration/rls.test.js` for the assertion that the owner path still
 * reads and writes exactly as before.
 *
 * ## Idempotency
 *
 * Every statement below is safe to run a second time against a database that
 * already has this migration's effects: `ENABLE ROW LEVEL SECURITY` is a
 * no-op on a table that already has it enabled, `REVOKE` on a privilege
 * already absent is a no-op rather than an error, `ALTER DEFAULT PRIVILEGES`
 * re-asserting the same default is a no-op, and `GRANT` re-asserting a
 * privilege the grantee already holds is a no-op. `CREATE ROLE` is the one
 * exception — it errors outright on a duplicate — so it is the one statement
 * here guarded with an explicit existence check first.
 */

exports.shorthands = undefined;

exports.up = (pgm) => {
  // ============================================================================
  // 1. RLS, enabled with no policies, on every base table in `public`.
  //
  // Enumerated from the catalog — pg_class joined to pg_namespace, filtered to
  // `public` — rather than a hardcoded list, both because there are 68 tables
  // to name and because the whole point is that a table added by a future
  // migration is covered automatically rather than depending on whoever wrote
  // that migration remembering to also edit this one.
  //
  // The filter is `relkind IN ('r', 'p')`: ordinary tables AND partitioned
  // parent tables, not views or materialized views ('v', 'm' — RLS does not
  // apply to those at all, see the note in section 2 below on why the grant
  // -stripping step matters independently) and not indexes or sequences
  // either.
  //
  // Both relkinds are required, not just 'r', and this was verified by
  // experiment against this project's local Postgres 16 rather than assumed:
  // a partitioned parent table — `measurements` and `audit_log` here — is
  // catalogued as relkind 'p', a *distinct* relkind from its partitions,
  // which are ordinary relkind 'r' relations. Enabling RLS on the parent
  // alone does NOT protect a partition queried directly by its own name: a
  // role granted SELECT on `measurements_202609` directly still read rows
  // from it with RLS enabled only on `measurements`, the parent, in a local
  // reproduction. The reverse is equally true: enabling RLS on every
  // partition while leaving the parent's own RLS flag off does not protect a
  // query that goes through the parent — `SELECT * FROM measurements`
  // consults the *parent's* `relrowsecurity` flag, not each partition's, to
  // decide whether to enforce anything at all, and returned every row in the
  // same reproduction. Only enabling RLS on both the parent (relkind 'p') and
  // every partition (relkind 'r') closes both paths, and that is exactly what
  // a catalog query for `relkind IN ('r', 'p')` picks up: it enumerates
  // partitions as ordinary relations the same way it enumerates any other
  // table, and separately picks up the two partitioned parents by their own,
  // different relkind.
  //
  // The table owner is unaffected either way. RLS restricts every role
  // *except* the table's owner (and any role holding BYPASSRLS) regardless of
  // how many policies exist — a table with RLS enabled and zero policies
  // still lets its owner read and write it, which is what makes this
  // migration safe for the API's own connection: see the file header.
  // `FORCE ROW LEVEL SECURITY` is deliberately not used anywhere here — that
  // clause exists to make RLS apply to the owner too, and the owner here is
  // the API's own connecting role, which needs unrestricted access, not a
  // second gate.
  // ============================================================================
  pgm.sql(`
    DO $$
    DECLARE
      v_rel RECORD;
    BEGIN
      FOR v_rel IN
        SELECT c.relname
          FROM pg_class c
          JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname = 'public'
           AND c.relkind IN ('r', 'p')
      LOOP
        EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', v_rel.relname);
      END LOOP;
    END;
    $$;
  `);

  // ============================================================================
  // 1a. Redefine ensure_time_partitions() so every partition it creates from
  // now on is born with RLS already enabled.
  //
  // This is not in the acceptance criteria for issue #5 in so many words, but
  // it is a direct, load-bearing consequence of step 1's own finding, and
  // skipping it would silently reopen the exposure this migration exists to
  // close, once a month, forever. The evidence: `ensure_time_partitions()` —
  // defined in the baseline, called both there (twelve months ahead, once)
  // and nightly by `sqdcp_maintenance()` via pg_cron — creates a new
  // partition with a bare `CREATE TABLE ... PARTITION OF`, and a partition
  // created that way does NOT inherit its parent's `relrowsecurity` flag.
  // Reproduced directly against this repository's own test suite while
  // writing this migration: `measurements` and `audit_log` at Sept 2026's
  // baseline apply already carry RLS on every partition step 1 enabled it
  // on, but `test/integration/schema.test.js`'s own
  // "sqdcp_maintenance() creates next month's partition" test drops next
  // month's partition and calls `sqdcp_maintenance()` to recreate it — and
  // the partition that comes back has RLS off, because nothing before this
  // section ever told `ensure_time_partitions()` to turn it on for a
  // partition it creates after this migration has already run once.
  //
  // Left unpatched, that gap matters specifically for `measurements` and
  // `audit_log`: they are the only two partitioned tables in this schema,
  // pg_cron runs `sqdcp_maintenance()` — and therefore
  // `ensure_time_partitions()` — every night per
  // `migrations/1756000000001_schedule-maintenance.js`, and a partition with
  // RLS off is readable in full by anything with a bare SELECT grant on it
  // when queried directly by name (see step 1's comment on why a query
  // through the parent alone is not the whole story: the parent's own RLS
  // flag governs queries that go through it, but a direct query against an
  // individual partition consults that partition's own flag, not the
  // parent's). `anon`/`authenticated` no longer hold that grant after step 2
  // below, but `powerbi_reader` deliberately does — a monthly partition of
  // `audit_log` or `measurements` created after tonight would otherwise be
  // the one object in this schema `powerbi_reader` reads without BYPASSRLS
  // even mattering, purely because RLS on it was never turned on to begin
  // with, which defeats the point of enabling RLS everywhere in the first
  // place.
  //
  // The fix is the smallest change that closes it: `CREATE OR REPLACE
  // FUNCTION` over the exact body the baseline defines, with one additional
  // statement — `ALTER TABLE ... ENABLE ROW LEVEL SECURITY` — run
  // immediately after each `CREATE TABLE ... PARTITION OF`, inside the same
  // `IF to_regclass(...) IS NULL THEN` branch, so it only ever runs for a
  // partition actually being created, never for one already there. This
  // redefines a function the baseline owns rather than editing the baseline
  // itself, which stays untouched per ADR-0007 — migrations are forward-only,
  // and `CREATE OR REPLACE FUNCTION` against an existing function is exactly
  // the tool forward-only migrations have for changing behaviour a table
  // definition can't express. `sqdcp_maintenance()` and the baseline's own
  // twelve-months-ahead call both go through this same function, so both
  // pick up the fix without needing their own change.
  // ============================================================================
  pgm.sql(`
    CREATE OR REPLACE FUNCTION ensure_time_partitions(
      p_parent      TEXT,
      p_from_month  DATE,
      p_to_month    DATE
    )
    RETURNS INTEGER
    LANGUAGE plpgsql
    AS $$
    DECLARE
      v_month   DATE := date_trunc('month', p_from_month)::date;
      v_end     DATE := date_trunc('month', p_to_month)::date;
      v_name    TEXT;
      v_created INTEGER := 0;
    BEGIN
      WHILE v_month <= v_end LOOP
        v_name := p_parent || '_' || to_char(v_month, 'YYYYMM');

        IF to_regclass(quote_ident(v_name)) IS NULL THEN
          EXECUTE format(
            'CREATE TABLE %I PARTITION OF %I FOR VALUES FROM (%L) TO (%L)',
            v_name, p_parent, v_month, (v_month + INTERVAL '1 month')::date
          );

          -- The one line this migration adds over the baseline's own
          -- definition — see the section comment above for why a freshly
          -- created partition needs this told to it explicitly rather than
          -- inheriting it from the parent.
          EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', v_name);

          v_created := v_created + 1;
        END IF;

        v_month := (v_month + INTERVAL '1 month')::date;
      END LOOP;

      RETURN v_created;
    END;
    $$
  `);

  // ============================================================================
  // 2. Strip `anon` and `authenticated` of every privilege in `public`.
  //
  // RLS alone does not close the exposure ADR-0004 describes, because RLS
  // does not apply to views or materialized views at all: a view runs with
  // the privileges of its *owner*, not its caller (this schema does not set
  // `security_invoker`, per ADR-0004's Consequences section), so a view reads
  // straight through RLS on the tables underneath it regardless of how many
  // policies those tables carry. `anon` holding SELECT on a view is exactly
  // as exposed after step 1 as it was before it. What actually closes that
  // gap is this step: taking the grant away so there is nothing for the view
  // -owner's privileges to be read *through* on `anon`'s or `authenticated`'s
  // behalf.
  //
  // Scoped to exactly these two roles. `service_role` (what the API's
  // service-role key authenticates as at the PostgREST layer), `authenticator`
  // (the role PostgREST itself connects as, before switching into `anon`,
  // `authenticated`, or `service_role`), `supabase_admin`, and `postgres`
  // (what this migration itself runs as, per the file header) are never
  // touched here — revoking from any of those breaks the platform, so each
  // REVOKE below names `anon` or `authenticated` explicitly rather than
  // reaching for a broader `PUBLIC` or wildcard target.
  //
  // Guarded on the role existing at all: `anon` and `authenticated` are
  // Supabase-provided roles, created when a Supabase project is provisioned.
  // They exist in every real Supabase Cloud project (production included),
  // but not on the stock `postgres:16`/`postgres:17-alpine` images this
  // repository's CI and local `docker compose` run against — the same gap
  // `1756000000001_schedule-maintenance.js` documents for `pg_cron`. A bare
  // `REVOKE ... FROM anon` on a database with no `anon` role fails outright,
  // which would break every migration run in CI and local development for a
  // condition production never hits. `RAISE NOTICE` and move on, the same
  // pattern the previous migration established.
  //
  // `ALL TABLES IN SCHEMA public` reaches ordinary tables, views, AND
  // materialized views — verified locally by inspecting `pg_class.relacl`
  // before and after, because `information_schema.role_table_grants` quietly
  // omits materialized views from its listing (a matview is not a standard
  // SQL object) and would have made this look like it were not working. It
  // does not reach sequences or routines, which is why those get their own
  // statements below.
  //
  // `ALTER DEFAULT PRIVILEGES` only changes what *future* objects created by
  // the role running it are granted — it is not retroactive and does not
  // touch anything created already, which is exactly why both the immediate
  // REVOKE and this are needed: the REVOKE closes today's exposure, this one
  // stops a migration six months from now that adds a table from silently
  // reopening it for `anon`/`authenticated` by default.
  // ============================================================================
  pgm.sql(`
    DO $$
    BEGIN
      IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
        REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public FROM anon;
        REVOKE ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public FROM anon;
        REVOKE ALL PRIVILEGES ON ALL ROUTINES IN SCHEMA public FROM anon;
        ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES FROM anon;
        ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON SEQUENCES FROM anon;
        ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON ROUTINES FROM anon;
      ELSE
        RAISE NOTICE
          'Role "anon" does not exist on this database — expected on stock '
          'postgres images (CI, local docker compose), and NOT expected on '
          'the Supabase Cloud project this Platform deploys to. Nothing to '
          'revoke here; if this NOTICE appears anywhere other than CI or '
          'local development, that is worth investigating.';
      END IF;

      IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
        REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public FROM authenticated;
        REVOKE ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public FROM authenticated;
        REVOKE ALL PRIVILEGES ON ALL ROUTINES IN SCHEMA public FROM authenticated;
        ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES FROM authenticated;
        ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON SEQUENCES FROM authenticated;
        ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON ROUTINES FROM authenticated;
      ELSE
        RAISE NOTICE
          'Role "authenticated" does not exist on this database — expected '
          'on stock postgres images (CI, local docker compose), and NOT '
          'expected on the Supabase Cloud project this Platform deploys to. '
          'Nothing to revoke here; if this NOTICE appears anywhere other '
          'than CI or local development, that is worth investigating.';
      END IF;
    END;
    $$;
  `);

  // ============================================================================
  // 2a. Strip PUBLIC's implicit EXECUTE on every routine in `public`.
  //
  // The REVOKEs in step 2 above target `anon` and `authenticated` by name,
  // and that is deliberate — see that step's own comment on why each REVOKE
  // names a role explicitly rather than reaching for PUBLIC. But those
  // REVOKEs do not actually close the routine exposure they look like they
  // close: Postgres grants EXECUTE on every function to the PUBLIC
  // pseudo-role implicitly, at `CREATE FUNCTION` time, independent of any
  // role-specific ACL entry. `anon` and `authenticated` hold EXECUTE on
  // every function in `public` through that implicit PUBLIC grant, not
  // through any `anon`-specific or `authenticated`-specific grant of their
  // own — so `REVOKE ... ON ALL ROUTINES ... FROM anon` (and the
  // `authenticated` twin, and the matching `ALTER DEFAULT PRIVILEGES`
  // lines) revoke a privilege neither role ever actually held by name, and
  // are no-ops against the real exposure. Confirmed against this
  // migration's own target production database: 342 functions in `public`
  // still carried EXECUTE for PUBLIC with the rest of this migration
  // applied and step 2's routine REVOKEs run. They stay in step 2 anyway,
  // harmlessly, as insurance against some future migration granting one of
  // those two roles a routine privilege by name — but the statements below
  // are what actually closes the gap.
  //
  // Unlike step 2, this runs once, unconditionally, and is not guarded on
  // any role's existence: PUBLIC is a pseudo-role, not a row in `pg_roles`,
  // so there is nothing to check for and nothing environment-specific about
  // whether it exists.
  //
  // Three roles legitimately keep EXECUTE after this and are unaffected by
  // it, each for a different reason:
  //
  //   - The function's owner (`postgres` in production, `platform` in local
  //     development — whichever role ran the baseline and every migration
  //     since) always retains EXECUTE regardless of this REVOKE. Postgres
  //     grants an object's owner implicit rights over it independent of its
  //     ACL, the same way a table's owner ignores RLS regardless of policy
  //     — see step 1's comment. REVOKE EXECUTE FROM PUBLIC changes what
  //     PUBLIC (and therefore everyone not otherwise granted EXECUTE by
  //     name) can do; it does not and cannot touch what the owner can do.
  //   - pg_cron's nightly `sqdcp_maintenance()` job, scheduled by
  //     `1756000000001_schedule-maintenance.js`. `cron.schedule()` records
  //     a job to run as whichever role called it — that migration's own
  //     comment on why its grants target `CURRENT_USER` rather than a
  //     literal `postgres` says as much: "`sqdcp_maintenance()` needs to
  //     run as a role that already owns the tables it partitions, which is
  //     exactly the role that ran the baseline and this migration." That
  //     role is the function owner, so the point above already covers it —
  //     called out separately here because it is the one case where losing
  //     EXECUTE would be a production incident discovered at 3:17 UTC
  //     rather than at review time. This was verified locally, not merely
  //     reasoned about: `sqdcp_maintenance()` was invoked as the owning
  //     role after this REVOKE, and it still succeeds — see
  //     `test/integration/schema.test.js`'s "sqdcp_maintenance() creates
  //     next month's partition..." test, which already runs against the
  //     connecting (owner) role on every `npm run test:integration` run
  //     and therefore already exercises this path; no new test was needed
  //     for the owner side of this specifically, only for the PUBLIC side,
  //     covered below in `test/integration/rls.test.js`. pg_cron itself is
  //     not installed on the stock Postgres image this repository's local
  //     development and CI run against (see that migration's own header
  //     for why), so this is the closest local reproduction of the actual
  //     nightly invocation path available without a Supabase-like image —
  //     it exercises "does the owning role keep EXECUTE", which is exactly
  //     the mechanism `cron.schedule()`'s current-user semantics rely on,
  //     but it is not pg_cron's own scheduler actually firing the job.
  //   - `powerbi_reader` needs no EXECUTE on anything: it is a pure
  //     data-reading role, granted SELECT on tables and views only (step 3
  //     below), never EXECUTE on a routine.
  //
  // None of this schema's functions are `SECURITY DEFINER` today — every
  // one of them runs with the privileges of its *caller*, not its owner —
  // so the exploitability of leaving PUBLIC's implicit EXECUTE in place was,
  // in practice, limited even before this step: a caller holding only
  // EXECUTE, with no privileges on the underlying tables, cannot read or
  // write anything through a `SECURITY INVOKER` function it could not
  // already read or write directly. That is precisely why this gap survived
  // the rest of this migration undetected on first review. It is fixed here
  // anyway, because that limitation is a fact about today's functions, not
  // a property this migration enforces — the next `SECURITY DEFINER`
  // function this schema ever gains would instantly turn this from an inert
  // gap into a real one, and closing it now means that future function does
  // not depend on whoever adds it also remembering to lock down EXECUTE by
  // hand.
  // ============================================================================
  pgm.sql('REVOKE EXECUTE ON ALL ROUTINES IN SCHEMA public FROM PUBLIC');
  pgm.sql('ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON ROUTINES FROM PUBLIC');

  // ============================================================================
  // 3. `powerbi_reader`: the one legitimate second client, per ADR-0004.
  //
  // `CREATE ROLE` has no `IF NOT EXISTS` form, so the existence check is
  // explicit — a second run of this migration's body must not error trying
  // to create a role that is already there.
  //
  // No password is set here, anywhere, or ever will be: a password baked into
  // a migration is a password checked into git history permanently, readable
  // by anyone who ever gets read access to this repository, forever, even
  // after it is rotated. An operator sets one out of band, directly against
  // the production database, once this migration has created the role:
  //
  //     ALTER ROLE powerbi_reader WITH PASSWORD '...';
  //
  // `BYPASSRLS` looks wrong on a read-only role at first glance — the whole
  // point of this migration is RLS — but it is required, not a shortcut,
  // given step 1 above enables RLS with *zero* policies. A role with no
  // policies defined for it and without BYPASSRLS does not get "restricted"
  // rows back from a base table it is granted SELECT on: it gets NONE, every
  // time, because deny-all with no policies means exactly that — deny all.
  // `powerbi_reader` exists to read every table for reporting, so it has to
  // bypass RLS to read anything at all, and what actually constrains it
  // instead is the GRANT below: SELECT only, nothing else, on exactly the
  // objects a schema-wide GRANT names. That SELECT grant — not RLS — is the
  // deliberate, broad "every table is a reporting contract" boundary
  // ADR-0004's Consequences section describes, and it is a boundary this role
  // cannot cross in the write direction: nothing below grants INSERT, UPDATE,
  // or DELETE anywhere, and this role is not made a member of any role that
  // has one.
  //
  // Creating a role WITH BYPASSRLS is itself gated by Postgres: only a role
  // that already holds BYPASSRLS may create another role with it (verified
  // directly against this project's local Postgres 16 — a CREATEROLE role
  // without BYPASSRLS was refused with "permission denied to create role:
  // Only roles with the BYPASSRLS attribute may create roles with the
  // BYPASSRLS attribute", the exact error Postgres raises for this case).
  // Production's connecting role, `postgres`, holds both BYPASSRLS and
  // CREATEROLE (already verified against production), so this statement is
  // expected to succeed there for the same reason it succeeds against this
  // project's local, superuser `platform` role — a superuser trivially holds
  // every attribute including BYPASSRLS, so this repository's local
  // verification exercises the *statement*, not the *gate*: the gate itself
  // was verified separately, against a non-superuser role created for that
  // purpose, before this migration was written. See this issue's PR
  // description for that reproduction.
  //
  // The existence check above only stops `CREATE ROLE` from erroring on a
  // duplicate — it does not stop this migration from silently leaving a
  // *wrong* role in place. If `powerbi_reader` already exists for any
  // reason — an operator pre-created it by hand, an earlier draft of this
  // migration ran without `BYPASSRLS`, a manual `CREATE ROLE` typo'd an
  // attribute — the `IF NOT EXISTS` branch above skips creation entirely,
  // and the `GRANT SELECT` statements below still run regardless of what
  // the existing role's actual attributes are. Under deny-all RLS with zero
  // policies (step 1), a role with SELECT on every table but *without*
  // BYPASSRLS does not error and does not get a restricted view of
  // anything — it gets an empty result set from every query, silently,
  // which defeats the entire reason this role exists (see the BYPASSRLS
  // paragraph above), with no signal anywhere that anything is wrong. The
  // `ELSE` branch below closes that: it corrects an existing-but-wrong
  // role's attributes on every migration run, matching the same
  // idempotent-and-corrective intent as the rest of this file, rather than
  // "create if missing, otherwise trust whatever is already there."
  //
  // `GRANT SELECT ON ALL TABLES IN SCHEMA public` includes views and
  // materialized views along with ordinary tables (see the note in step 2
  // above) — a view executes as its owner and reads straight through RLS
  // regardless of the caller's own grants, so `powerbi_reader` reading a view
  // needs nothing beyond this one grant on the view itself, not BYPASSRLS on
  // whatever base tables that view happens to join underneath.
  //
  // `ALTER DEFAULT PRIVILEGES` here mirrors step 2's: without it, a table
  // added by a future migration is invisible to Power BI until someone
  // remembers to grant it by hand, which is a silent gap rather than a loud
  // one — the opposite of what step 2 aims for with `anon`/`authenticated`,
  // but the same mechanism.
  // ============================================================================
  pgm.sql(`
    DO $$
    BEGIN
      IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'powerbi_reader') THEN
        CREATE ROLE powerbi_reader WITH LOGIN BYPASSRLS;
      ELSE
        ALTER ROLE powerbi_reader WITH LOGIN BYPASSRLS;
      END IF;
    END;
    $$;
  `);

  pgm.sql('GRANT USAGE ON SCHEMA public TO powerbi_reader');
  pgm.sql('GRANT SELECT ON ALL TABLES IN SCHEMA public TO powerbi_reader');
  pgm.sql('ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO powerbi_reader');
};

exports.down = (pgm) => {
  // Forward-only in production per ADR-0007 — this exists for local
  // development and for node-pg-migrate's own requirement that a migration
  // define both directions, not because a deploy ever calls it.
  //
  // This is not a full inverse of up(), and deliberately so. `anon` and
  // `authenticated` had *some* set of privileges before this migration ran —
  // this file never recorded what they were, because recording an exposure
  // in order to be able to put it back is not a thing a security fix should
  // do. So this down() disables RLS and removes `powerbi_reader`, but does
  // not attempt to re-grant `anon`/`authenticated` anything: doing that would
  // silently reopen the exact hole issue #5 exists to close, at the exact
  // moment someone is running a migration down without necessarily meaning to
  // undo the security posture along with the schema. Whoever runs this down
  // and wants the old grants back has to decide that on purpose and write it
  // by hand.
  // All of powerbi_reader's teardown is gated on a single existence check
  // below, covering the ALTER DEFAULT PRIVILEGES / REVOKE statements as well
  // as the DROP OWNED BY / DROP ROLE pair, not just the drop. Previously
  // only the DROP statements were guarded and the three REVOKE-family
  // statements above them ran unconditionally — running this down() a
  // second time, or running it after an up() that failed partway through
  // before section 3 ever created the role, hit
  // `ERROR: role "powerbi_reader" does not exist` on the very first
  // statement and aborted before ever reaching the (correctly guarded)
  // DROP. up() guards every role-dependent statement the same way
  // throughout this file — see its own existence checks in sections 2 and
  // 3 — so down() now matches that discipline instead of assuming its own
  // statements always run against a role that is there.
  //
  // Deliberately NOT reversed here: the `REVOKE EXECUTE ... FROM PUBLIC`
  // and `ALTER DEFAULT PRIVILEGES ... REVOKE EXECUTE ... FROM PUBLIC`
  // statements up() adds in step 2a. This mirrors the reasoning in the
  // paragraph above this one, about not restoring anon/authenticated's
  // original grants: this file never recorded what PUBLIC's implicit
  // EXECUTE looked like on whatever functions existed before this migration
  // first ran, because recording an exposure in order to be able to put it
  // back is not something a security fix should do. Re-granting EXECUTE to
  // PUBLIC blindly here would silently reopen exactly the gap step 2a
  // exists to close, at the exact moment someone runs a migration down
  // without necessarily meaning to undo its security posture along with its
  // schema. As with anon/authenticated, whoever wants that back has to
  // decide that on purpose and grant it back by hand.
  pgm.sql(`
    DO $$
    BEGIN
      IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'powerbi_reader') THEN
        ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE SELECT ON TABLES FROM powerbi_reader;
        REVOKE SELECT ON ALL TABLES IN SCHEMA public FROM powerbi_reader;
        REVOKE USAGE ON SCHEMA public FROM powerbi_reader;

        -- DROP ROLE refuses a role that still owns privileges anywhere in
        -- the database ("cannot be dropped because some objects depend on
        -- it") — the three REVOKEs above clear the ones this migration
        -- itself granted, but DROP OWNED BY is the belt-and-braces version
        -- in case anything else in a local development database ever
        -- granted this role something by hand.
        DROP OWNED BY powerbi_reader;
        DROP ROLE powerbi_reader;
      END IF;
    END;
    $$;
  `);

  // Disables RLS on the same catalog-driven enumeration up() used to enable
  // it — see that step's own comment for why both relkinds are needed.
  pgm.sql(`
    DO $$
    DECLARE
      v_rel RECORD;
    BEGIN
      FOR v_rel IN
        SELECT c.relname
          FROM pg_class c
          JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname = 'public'
           AND c.relkind IN ('r', 'p')
      LOOP
        EXECUTE format('ALTER TABLE %I DISABLE ROW LEVEL SECURITY', v_rel.relname);
      END LOOP;
    END;
    $$;
  `);

  // Restores ensure_time_partitions() to exactly the baseline's own
  // definition — this one IS a full, exact inverse, unlike the grants above:
  // there is nothing sensitive being reverted, just the one statement step
  // 1a added.
  pgm.sql(`
    CREATE OR REPLACE FUNCTION ensure_time_partitions(
      p_parent      TEXT,
      p_from_month  DATE,
      p_to_month    DATE
    )
    RETURNS INTEGER
    LANGUAGE plpgsql
    AS $$
    DECLARE
      v_month   DATE := date_trunc('month', p_from_month)::date;
      v_end     DATE := date_trunc('month', p_to_month)::date;
      v_name    TEXT;
      v_created INTEGER := 0;
    BEGIN
      WHILE v_month <= v_end LOOP
        v_name := p_parent || '_' || to_char(v_month, 'YYYYMM');

        IF to_regclass(quote_ident(v_name)) IS NULL THEN
          EXECUTE format(
            'CREATE TABLE %I PARTITION OF %I FOR VALUES FROM (%L) TO (%L)',
            v_name, p_parent, v_month, (v_month + INTERVAL '1 month')::date
          );
          v_created := v_created + 1;
        END IF;

        v_month := (v_month + INTERVAL '1 month')::date;
      END LOOP;

      RETURN v_created;
    END;
    $$
  `);
};
