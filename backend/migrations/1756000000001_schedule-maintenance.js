/**
 * Schedules `sqdcp_maintenance()` to run nightly. See issue #19.
 *
 * The baseline defines `sqdcp_maintenance()` — three months of partitions
 * ahead for `measurements` and `audit_log`, then a rollup refresh — and
 * leaves it uncalled. Nothing replaced the k3s CronJob that used to invoke
 * it, so partitions stop being created and the tier board's numbers go stale,
 * both silently: inserts keep succeeding into the DEFAULT partition, and a
 * board showing a wrong number looks the same as one showing a slightly old
 * one. `pg_cron` closes that gap from inside the database that owns the
 * work, per the issue's own reasoning for preferring it over a new scheduler
 * on the LXC.
 *
 * This is the first migration written after the baseline, so it sets the
 * pattern ADR-0007 asks for: forward-only, and safe for the version it
 * replaces to keep running against it while a deploy is in flight. Nothing
 * here changes a table a running query depends on, so that constraint is
 * satisfied trivially — the risk in this migration is entirely about
 * environment, not compatibility.
 *
 * ## Why this is conditional on `pg_cron` being available
 *
 * `pg_cron` ships as a shared_preload_libraries extension: Supabase Cloud
 * preloads it (verified against the production project — available, not yet
 * installed), but stock `postgres:17-alpine`, which is what CI and local
 * `docker compose` run, does not carry it at all. An unconditional
 * `CREATE EXTENSION pg_cron` would fail every CI run and every local
 * `npm run migrate`, so installing and scheduling only happens when
 * `pg_available_extensions` says the extension is there. Where it is not,
 * this migration still has to succeed — the baseline path for a fresh
 * database must not depend on infrastructure only production has — so it
 * emits a `RAISE NOTICE` instead of failing, and instead of silently doing
 * nothing: a silent skip here is exactly the class of bug that took this
 * project down twice on the day this migration was written (CI green,
 * production on a different path, nobody finds out until it matters).
 *
 * Where `pg_cron` *is* available, every step after the availability check
 * runs unguarded by any exception handler. If `CREATE EXTENSION`, the grants,
 * or `cron.schedule` fail on a database that could have had this scheduled,
 * the migration fails loudly, the same way any other migration failure does.
 * That is deliberate: a database that could have been scheduled and was not
 * is a bug, not a configuration, and must not be swallowed into the same
 * path as "this Postgres genuinely does not have the extension."
 *
 * There is a second, narrower way a database "could not have been
 * scheduled": `pg_cron` schedules jobs from exactly one database, named by
 * `cron.database_name`, and refuses `CREATE EXTENSION pg_cron` anywhere
 * else — verified by reproducing it directly against
 * `supabase/postgres:17.6.1.167`, pointed at a scratch database rather than
 * `postgres`. That is a configuration fact about which database this
 * connection happens to be, not a bug, so it gets its own NOTICE-and-skip
 * branch rather than failing — but it needs a message distinct from the
 * "pg_cron is not available" one above, because that message would be
 * actively wrong here: `pg_cron` *is* available, it just cannot be scheduled
 * from this particular database. The production path is unaffected: this
 * Platform's `DATABASE_URL` connects to `postgres`, which is both Supabase
 * Cloud's default database and its `cron.database_name`. The branch exists
 * for the natural way to test this migration locally — pointing
 * `DATABASE_URL` at a scratch database on a Supabase-like image instead of
 * its `postgres` database — which failed hard with `ERROR: can only create
 * extension in database postgres` before this guard existed.
 *
 * ## Idempotency
 *
 * `cron.schedule(jobname, schedule, command)` upserts by job name — verified
 * directly against `supabase/postgres:17.6.1.167` (pg_cron 1.6.4, the same
 * major version and image family as the production project), which is one
 * row in `cron.job` before and after scheduling the same name twice with a
 * different schedule string. So the call at the bottom of this migration is
 * safe to run again on a database that already has the job.
 *
 * `CREATE EXTENSION` and the two grants are gated on `pg_extension` rather
 * than run unconditionally behind `IF NOT EXISTS`, and that gating is load
 * -bearing, not defensive dressing: Supabase's own extension image runs a
 * post-install hook for `pg_cron` (`.../extension-custom-scripts/pg_cron/
 * after-create.sql`) that re-grants and partially re-revokes privileges on
 * the `cron` schema every time `CREATE EXTENSION ... pg_cron` is executed,
 * including the no-op case where the extension already exists. Running this
 * migration's own `GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA cron` a
 * second time collides with that hook's later `REVOKE`, and the second
 * migration run fails with "dependent privileges exist" — verified by
 * reproducing it against the same image. Skipping the extension creation and
 * the grants once `pg_extension` shows `pg_cron` already installed avoids
 * that collision entirely, and does not cost anything: the hook already
 * grants the connecting role what it needs the first time through.
 *
 * This is the one place this migration departs from the exact statements
 * Supabase's public docs give for enabling `pg_cron` — those three
 * statements still run, verbatim, on first install; they are just gated to
 * run once rather than on every migration apply.
 *
 * The grants target `CURRENT_USER` rather than the literal role name
 * `postgres` that Supabase's docs use, because that role is what you get in
 * the Supabase Studio SQL editor, not necessarily what `DATABASE_URL`
 * connects as when `deploy.sh` runs migrations. Granting to whichever role
 * is actually running this migration is correct regardless of what that role
 * is named, and `sqdcp_maintenance()` needs to run as a role that already
 * owns the tables it partitions, which is exactly the role that ran the
 * baseline and this migration.
 *
 * ## Schema-qualification
 *
 * The scheduled command is `SELECT public.sqdcp_maintenance();`, not the
 * bare function name. A `pg_cron` job runs as a background worker with its
 * own `search_path`, not the session's, so an unqualified call resolves only
 * by accident of whatever `search_path` that worker happens to have. This
 * repository has already paid once, in the baseline, for the general version
 * of this mistake — see the baseline's own comment on `public.nlevel()` and
 * PostgreSQL 17's restricted `search_path` during maintenance operations —
 * and a cron job's `search_path` is a second, independent way to hit the same
 * class of bug.
 *
 * ## Failure visibility
 *
 * `pg_cron` records every run in `cron.job_run_details` (status, return
 * message, start/end time), keyed by `jobid`. The lightest way to satisfy
 * "a failed run is visible" is to document the query rather than build a
 * view or an alerting path around it — this Platform has no monitoring
 * system yet, and a failed nightly maintenance run is something a person
 * checks for, not something that pages anyone tonight:
 *
 *     SELECT status, return_message, start_time, end_time
 *       FROM cron.job_run_details
 *      WHERE jobid = (SELECT jobid FROM cron.job WHERE jobname = 'sqdcp-maintenance')
 *      ORDER BY start_time DESC
 *      LIMIT 20;
 *
 * A `status <> 'succeeded'` row there, or no row at all for last night, means
 * the board is running on stale rollups and partitions may be running out —
 * see the README's Deployment section for what breaks and what to check.
 *
 * ## Schedule
 *
 * 03:17 UTC, daily. Off the hour and off the half-hour on purpose: this is a
 * single self-hosted Supabase project, not a shared cluster where a
 * thundering herd of every tenant's `0 * * * *` job actually matters, but
 * there is no reason to opt into that pattern when avoiding it costs
 * nothing. A fixed UTC time is correct here (rather than resolving a Site's
 * local time zone the way shift and production-day attribution do) because
 * neither partition creation nor rollup refresh is Site-specific — see
 * issue #19.
 */

exports.shorthands = undefined;

const JOB_NAME = 'sqdcp-maintenance';

exports.up = (pgm) => {
  pgm.sql(`
    DO $$
    DECLARE
      v_pg_cron_available BOOLEAN;
      v_pg_cron_installed BOOLEAN;
      v_cron_database     TEXT;
      v_current_database  TEXT := current_database();
    BEGIN
      SELECT EXISTS (
        SELECT 1 FROM pg_available_extensions WHERE name = 'pg_cron'
      ) INTO v_pg_cron_available;

      IF NOT v_pg_cron_available THEN
        RAISE NOTICE
          'pg_cron is not available on this Postgres (no matching row in '
          'pg_available_extensions) — this is expected on stock '
          'postgres:17-alpine, which is what CI and local docker compose '
          'run, and NOT expected on the Supabase Cloud project this '
          'Platform deploys to. sqdcp_maintenance() will NOT run '
          'automatically on this database: partitions will stop being '
          'created three months out and mv_daily_oee will go stale. If '
          'this NOTICE appears anywhere other than CI or local development, '
          'that is the bug issue #19 exists to prevent — pg_cron must be '
          'installed there for this migration to schedule anything.';
        RETURN;
      END IF;

      -- pg_cron only ever schedules from the one database named by
      -- cron.database_name — its background worker reads job descriptions
      -- from that database alone, and CREATE EXTENSION pg_cron fails outright
      -- anywhere else. current_setting(..., true) returns NULL rather than
      -- erroring if the GUC does not exist (pg_cron available but never
      -- preloaded, which is not this Platform's case but costs nothing to
      -- handle); IS DISTINCT FROM treats that NULL as a mismatch rather than
      -- as equal to nothing, which is the outcome we want either way. This is
      -- a configuration fact about which database this connection happens to
      -- be, not a bug: a database that genuinely cannot be scheduled from
      -- gets the same NOTICE-and-skip treatment as one with no pg_cron at
      -- all, just with its own message, because "pg_cron is not available"
      -- would be actively wrong here.
      v_cron_database := current_setting('cron.database_name', true);

      IF v_cron_database IS DISTINCT FROM v_current_database THEN
        RAISE NOTICE
          'pg_cron is available, but this connection is to database "%" and '
          'pg_cron only schedules jobs from database "%" (cron.database_name). '
          'Nothing was scheduled here. On the Supabase Cloud project this '
          'Platform deploys to, the migration''s DATABASE_URL connects to '
          '"postgres", which is both Supabase''s default database and its '
          'cron.database_name, so production is unaffected — this branch is '
          'for whoever points DATABASE_URL at a scratch database on a '
          'Supabase-like image instead.',
          v_current_database, v_cron_database;
        RETURN;
      END IF;

      -- Gated on whether pg_cron was already installed, not on
      -- CREATE EXTENSION IF NOT EXISTS's own no-op behaviour, because
      -- Supabase's post-install hook for pg_cron re-runs its grants (and a
      -- REVOKE) every time CREATE EXTENSION ... pg_cron executes, even when
      -- it does nothing else. Re-running this migration's own GRANT ALL a
      -- second time collides with that hook's later REVOKE and fails with
      -- "dependent privileges exist" — see the file header for how this was
      -- verified. Skipping straight to cron.schedule below on a database
      -- that already has the extension avoids that collision, and loses
      -- nothing: the hook already granted the connecting role what it needs
      -- the first time through.
      SELECT EXISTS (
        SELECT 1 FROM pg_extension WHERE extname = 'pg_cron'
      ) INTO v_pg_cron_installed;

      IF NOT v_pg_cron_installed THEN
        -- Supabase's documented enablement steps, run verbatim once. Nothing
        -- past this point is wrapped in a handler: a failure here means a
        -- database that could have been scheduled was not, which must fail
        -- the migration rather than fall back to the NOTICE-and-skip path
        -- above.
        CREATE EXTENSION pg_cron WITH SCHEMA pg_catalog;
        EXECUTE format('GRANT USAGE ON SCHEMA cron TO %I', CURRENT_USER);
        EXECUTE format('GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA cron TO %I', CURRENT_USER);
      END IF;

      -- Schema-qualified: a cron job runs with its own search_path, not this
      -- session's, so the bare function name is not safe here even though it
      -- would resolve fine typed into psql by hand. Upserts by job name, so
      -- this is safe to run again against a database that already has it.
      PERFORM cron.schedule(
        '${JOB_NAME}',
        '17 3 * * *',
        'SELECT public.sqdcp_maintenance();'
      );
    END;
    $$;
  `);
};

exports.down = (pgm) => {
  // Forward-only in production per ADR-0007 — this exists for local
  // development and for node-pg-migrate's own requirement that a migration
  // define both directions, not because a deploy ever calls it.
  //
  // cron.unschedule() raises rather than returning false for a job name it
  // does not recognise, so this checks cron.job first: a database that took
  // the "pg_cron unavailable" branch in up() never scheduled anything, and a
  // database that had this migration's up() run twice still has exactly one
  // job to remove.
  //
  // The two checks are nested rather than joined with AND in one IF: a
  // database that never installed pg_cron has no `cron` schema at all, and a
  // single combined boolean expression is one SQL statement, planned as a
  // whole — referencing cron.job there fails at parse time even though the
  // pg_extension check alone would have been false. Nesting means the inner
  // EXISTS is its own statement, only planned once the outer one is true.
  pgm.sql(`
    DO $$
    BEGIN
      IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = '${JOB_NAME}') THEN
          PERFORM cron.unschedule('${JOB_NAME}');
        END IF;
      END IF;
    END;
    $$;
  `);
};
