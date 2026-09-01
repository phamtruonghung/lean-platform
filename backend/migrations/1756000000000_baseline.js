/**
 * The baseline schema.
 *
 * This carries the 68-table SQDCP schema forward from `maintenance-management`
 * as one clean migration rather than the 33 that produced it there. No
 * production data exists anywhere in the estate, so squashing is free exactly
 * once, and this is that once — see ADR-0003. `node-pg-migrate` remains the
 * migration tool; the Supabase CLI is used for local development only.
 *
 * Three corrections are made here, in the baseline, rather than as later
 * migrations, because each becomes impossible or expensive once data exists:
 *
 *   1. `employees` is the rich table. `work_email` is an ordinary column on
 *      it, carried over from the bridge migration that used to link it to a
 *      separate directory app. `directory_user_id` does not exist anywhere in
 *      this schema — that directory app is not part of the Platform.
 *   2. Document numbers are scoped by Site. `next_document_number` takes a
 *      Site's code alongside its prefix and year, and `document_sequences`
 *      scopes its counter the same way, so two Sites issue independent runs.
 *      See ADR-0005.
 *   3. There is no `attachments` table. The Platform records text only; see
 *      ADR-0003.
 *
 * Everything else is the inherited schema, unchanged in substance. Section
 * comments below are adapted from the migrations they came from: comments
 * describing a world this repository does not have — the vendored/shared
 * split, the k3s platform, the directory app — are trimmed; comments
 * explaining a live design decision are kept.
 */

exports.shorthands = undefined;

exports.up = (pgm) => {
  // ============================================================================
  // Foundation
  //
  // Everything in this section is used by every table that follows: the
  // extensions, the `updated_at` trigger, the audit trail, and the helper that
  // creates monthly partitions.
  //
  // On the extensions: btree_gist, ltree and citext are all "trusted"
  // extensions in PostgreSQL 13 and later, which means the owner of the
  // database can create them without being superuser — and Supabase Cloud
  // gives the API an ordinary role, not a superuser.
  //
  //   btree_gist  lets an EXCLUDE constraint mix equality (asset_id) with range
  //               overlap (tstzrange). Used to make overlapping downtime
  //               impossible to record.
  //   ltree       stores the org hierarchy path so a plant-level rollup is one
  //               indexed lookup rather than a recursive CTE inside every KPI.
  //   citext      case-insensitive email, so Bob@... and bob@... are one user.
  //
  // All three are pinned to the `public` schema explicitly rather than left to
  // land wherever `search_path` happens to put them. This matters because
  // PostgreSQL 17 runs maintenance operations — CREATE/REFRESH MATERIALIZED
  // VIEW, CREATE INDEX, REINDEX, CLUSTER, VACUUM FULL — with `search_path`
  // forced to `pg_catalog, pg_temp`. A `LANGUAGE sql` function is stored as
  // text and re-parsed at plan time whenever the planner inlines it, so an
  // unqualified call to `nlevel()` (below, in `shift_instance_at` and
  // `resolve_cost_rate`) resolves fine at CREATE FUNCTION time and fails at
  // inline time unless it is written as `public.nlevel()` and `public` really
  // is where `ltree` lives. No production data exists yet, so this is the one
  // point where we get to settle that rather than discover it later.
  // ============================================================================
  pgm.sql('CREATE EXTENSION IF NOT EXISTS btree_gist WITH SCHEMA public');
  pgm.sql('CREATE EXTENSION IF NOT EXISTS ltree WITH SCHEMA public');
  pgm.sql('CREATE EXTENSION IF NOT EXISTS citext WITH SCHEMA public');

  // --------------------------------------------------------------------------
  // Guard: the schema-qualified calls below (public.nlevel, and anything a
  // later migration adds) are only correct while these three extensions
  // really live in `public`. `CREATE EXTENSION IF NOT EXISTS` silently does
  // nothing if the extension is already installed somewhere else — Supabase
  // Cloud, for instance, has been known to preinstall trusted extensions into
  // its own `extensions` schema — which would leave `public.nlevel` calling a
  // function that does not exist there, with no error until the first nightly
  // `refresh_sqdcp_rollups()` run. Failing the migration immediately turns
  // that silent, delayed failure into a loud, immediate one.
  // --------------------------------------------------------------------------
  pgm.sql(`
    DO $$
    DECLARE
      v_bad_extension TEXT;
    BEGIN
      SELECT e.extname INTO v_bad_extension
        FROM pg_extension e
        JOIN pg_namespace n ON n.oid = e.extnamespace
       WHERE e.extname IN ('btree_gist', 'ltree', 'citext')
         AND n.nspname <> 'public'
       LIMIT 1;

      IF v_bad_extension IS NOT NULL THEN
        RAISE EXCEPTION
          'Extension "%" is installed outside the public schema. This baseline schema-qualifies calls into btree_gist/ltree/citext as public.<fn>() so that they survive planner inlining under PostgreSQL 17''s restricted search_path during maintenance operations; that assumption must hold for every one of the three, or those calls break silently.',
          v_bad_extension;
      END IF;
    END;
    $$;
  `);

  // --------------------------------------------------------------------------
  // updated_at
  //
  // Maintained by the database rather than by application code. Application
  // code forgets, and a background job or a psql session fixing bad data by
  // hand never sets it at all — which is exactly when you most want to know
  // that a row changed.
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE OR REPLACE FUNCTION set_updated_at()
    RETURNS TRIGGER
    LANGUAGE plpgsql
    AS $$
    BEGIN
      NEW.updated_at := now();
      RETURN NEW;
    END;
    $$
  `);

  // Attaching the trigger is three lines of boilerplate per table and there are
  // roughly fifty tables, so it gets a helper.
  pgm.sql(`
    CREATE OR REPLACE FUNCTION attach_updated_at(p_table TEXT)
    RETURNS VOID
    LANGUAGE plpgsql
    AS $$
    BEGIN
      EXECUTE format(
        'CREATE TRIGGER %I BEFORE UPDATE ON %I
           FOR EACH ROW EXECUTE FUNCTION set_updated_at()',
        p_table || '_set_updated_at', p_table
      );
    END;
    $$
  `);

  // --------------------------------------------------------------------------
  // Monthly range partitions
  //
  // Two tables in this schema are partitioned by time from the start
  // (measurements and audit_log) because converting a large table to a
  // partitioned one later needs an exclusive lock and a full rewrite.
  //
  // Every partitioned parent also gets a DEFAULT partition. Without one, an
  // insert whose timestamp falls outside every defined range simply fails —
  // which would mean the day someone forgets to run the maintenance job, the
  // shop floor cannot record a measurement. The default partition catches those
  // rows instead. It is a safety net, not a plan: `ensure_time_partitions`
  // should be run ahead of time, and a non-empty default partition is a signal
  // that it has not been.
  // --------------------------------------------------------------------------
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

  // --------------------------------------------------------------------------
  // Audit trail
  //
  // ISO 9001 and IATF 16949 both want to know who changed a quality record and
  // when. This table answers that.
  //
  // It is attached selectively (see the end of this migration), not to every
  // table: production counts and SPC measurements would bury it, and those
  // rows are already append-only, so their own history is the audit trail.
  //
  // `changed_by` is read from a session variable the API sets per request:
  //
  //     SET LOCAL app.user_id = '42';
  //
  // The `true` argument to current_setting means "return NULL if unset" rather
  // than raising — a migration or a psql session has no app user, and that must
  // not stop the write.
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE TABLE audit_log (
      id          BIGINT      GENERATED ALWAYS AS IDENTITY,
      table_name  TEXT        NOT NULL,
      record_id   BIGINT      NOT NULL,
      operation   TEXT        NOT NULL
                              CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE')),
      changed_by  BIGINT,
      changed_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
      old_values  JSONB,
      new_values  JSONB,
      PRIMARY KEY (id, changed_at)
    ) PARTITION BY RANGE (changed_at)
  `);

  pgm.sql('CREATE TABLE audit_log_default PARTITION OF audit_log DEFAULT');

  // Twelve months back and forward. Backwards as well as forwards because a
  // data import can legitimately carry historical timestamps.
  pgm.sql(`
    SELECT ensure_time_partitions(
      'audit_log',
      (date_trunc('month', now()) - INTERVAL '12 months')::date,
      (date_trunc('month', now()) + INTERVAL '12 months')::date
    )
  `);

  pgm.sql(`
    CREATE INDEX audit_log_record_idx
      ON audit_log (table_name, record_id, changed_at DESC)
  `);
  pgm.sql(`
    CREATE INDEX audit_log_changed_by_idx
      ON audit_log (changed_by, changed_at DESC)
  `);

  pgm.sql(`
    CREATE OR REPLACE FUNCTION audit_row_change()
    RETURNS TRIGGER
    LANGUAGE plpgsql
    AS $$
    DECLARE
      v_user BIGINT := NULLIF(current_setting('app.user_id', true), '')::BIGINT;
      v_id   BIGINT;
    BEGIN
      IF TG_OP = 'DELETE' THEN
        v_id := OLD.id;
        INSERT INTO audit_log (table_name, record_id, operation, changed_by, old_values)
        VALUES (TG_TABLE_NAME, v_id, TG_OP, v_user, to_jsonb(OLD));
        RETURN OLD;
      END IF;

      v_id := NEW.id;

      IF TG_OP = 'UPDATE' THEN
        -- A row that did not actually change is not worth a history entry.
        -- Triggers fire on any UPDATE statement, including no-op writes from
        -- an ORM that saves an unmodified form.
        IF to_jsonb(OLD) = to_jsonb(NEW) THEN
          RETURN NEW;
        END IF;

        INSERT INTO audit_log (table_name, record_id, operation, changed_by, old_values, new_values)
        VALUES (TG_TABLE_NAME, v_id, TG_OP, v_user, to_jsonb(OLD), to_jsonb(NEW));
      ELSE
        INSERT INTO audit_log (table_name, record_id, operation, changed_by, new_values)
        VALUES (TG_TABLE_NAME, v_id, TG_OP, v_user, to_jsonb(NEW));
      END IF;

      RETURN NEW;
    END;
    $$
  `);

  pgm.sql(`
    CREATE OR REPLACE FUNCTION attach_audit(p_table TEXT)
    RETURNS VOID
    LANGUAGE plpgsql
    AS $$
    BEGIN
      EXECUTE format(
        'CREATE TRIGGER %I AFTER INSERT OR UPDATE OR DELETE ON %I
           FOR EACH ROW EXECUTE FUNCTION audit_row_change()',
        p_table || '_audit', p_table
      );
    END;
    $$
  `);

  // ============================================================================
  // The physical hierarchy: sites, org units, assets, cost centres.
  //
  // `org_units` is the spine of the whole schema. Almost every event table
  // carries an org_unit_id, and every KPI rolls up along the hierarchy, so the
  // cost of walking it shows up everywhere.
  //
  // It is stored as an adjacency list (parent_id) with a materialised ltree
  // `path` alongside. The adjacency list is the truth and is what people edit;
  // the path is derived by trigger and is what queries use. "Everything under
  // Line 3" then becomes:
  //
  //     WHERE path <@ 'n1.n4.n9'
  //
  // which is a single GiST index lookup, instead of a recursive CTE repeated
  // inside every one of the twenty-odd KPI views.
  // ============================================================================

  // --------------------------------------------------------------------------
  // sites
  //
  // `timezone` exists because shift instances are generated in local plant
  // time and stored as UTC, and getting that wrong shifts every night shift by
  // an hour twice a year. `code` is also what a document number carries — see
  // next_document_number below.
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE TABLE sites (
      id            BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      code          TEXT        NOT NULL UNIQUE,
      name          TEXT        NOT NULL,
      timezone      TEXT        NOT NULL DEFAULT 'UTC',
      country_code  TEXT,
      is_active     BOOLEAN     NOT NULL DEFAULT TRUE,
      created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by    BIGINT,
      updated_by    BIGINT
    )
  `);

  // Rejects a typo like 'Europe/Bucarest' at write time rather than at 02:00 on
  // the night a shift calendar is generated. This is a trigger and not a CHECK
  // constraint because validating a timezone name means reading
  // pg_timezone_names, and a CHECK constraint may not contain a subquery.
  pgm.sql(`
    CREATE OR REPLACE FUNCTION sites_validate_timezone()
    RETURNS TRIGGER
    LANGUAGE plpgsql
    AS $$
    BEGIN
      IF NOT EXISTS (SELECT 1 FROM pg_timezone_names WHERE name = NEW.timezone) THEN
        RAISE EXCEPTION 'unknown timezone: %', NEW.timezone
          USING HINT = 'Use an IANA name such as Europe/London or Asia/Ho_Chi_Minh';
      END IF;
      RETURN NEW;
    END;
    $$
  `);

  pgm.sql(`
    CREATE TRIGGER sites_validate_timezone
      BEFORE INSERT OR UPDATE OF timezone ON sites
      FOR EACH ROW EXECUTE FUNCTION sites_validate_timezone()
  `);

  // --------------------------------------------------------------------------
  // org_units
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE TABLE org_units (
      id          BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      site_id     BIGINT      NOT NULL REFERENCES sites (id),
      parent_id   BIGINT      REFERENCES org_units (id),
      code        TEXT        NOT NULL,
      name        TEXT        NOT NULL,
      unit_type   TEXT        NOT NULL
                              CHECK (unit_type IN ('area', 'department', 'line',
                                                   'cell', 'work_center')),
      path        LTREE,
      sort_order  INTEGER     NOT NULL DEFAULT 0,
      is_active   BOOLEAN     NOT NULL DEFAULT TRUE,
      created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by  BIGINT,
      updated_by  BIGINT,

      CONSTRAINT org_units_code_unique UNIQUE (site_id, code)
    )
  `);

  // --------------------------------------------------------------------------
  // Path maintenance.
  //
  // ltree labels may not begin with a digit, so each label is the row id with
  // an 'n' prefix: the third child of unit 4 at site 1 is 'n1.n4.n9'.
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE OR REPLACE FUNCTION org_units_compute_path()
    RETURNS TRIGGER
    LANGUAGE plpgsql
    AS $$
    DECLARE
      v_parent_path LTREE;
    BEGIN
      IF TG_OP = 'UPDATE' AND NEW.parent_id IS NOT DISTINCT FROM OLD.parent_id THEN
        -- Nothing that affects the path changed; leave it alone so an ordinary
        -- rename does not cascade a subtree rewrite.
        NEW.path := OLD.path;
        RETURN NEW;
      END IF;

      IF NEW.parent_id IS NULL THEN
        NEW.path := text2ltree('n' || NEW.id);
        RETURN NEW;
      END IF;

      SELECT path INTO v_parent_path FROM org_units WHERE id = NEW.parent_id;

      IF v_parent_path IS NULL THEN
        RAISE EXCEPTION 'parent org unit % has no path', NEW.parent_id;
      END IF;

      -- A unit cannot be moved underneath its own descendant. Without this an
      -- accidental drag in the UI detaches an entire branch of the plant from
      -- every rollup, silently and irreversibly.
      IF TG_OP = 'UPDATE' AND v_parent_path <@ OLD.path THEN
        RAISE EXCEPTION
          'org unit % cannot be moved under its own descendant %',
          NEW.id, NEW.parent_id;
      END IF;

      IF NEW.parent_id = NEW.id THEN
        RAISE EXCEPTION 'org unit % cannot be its own parent', NEW.id;
      END IF;

      NEW.path := v_parent_path || text2ltree('n' || NEW.id);
      RETURN NEW;
    END;
    $$
  `);

  pgm.sql(`
    CREATE TRIGGER org_units_compute_path
      BEFORE INSERT OR UPDATE ON org_units
      FOR EACH ROW EXECUTE FUNCTION org_units_compute_path()
  `);

  // When a unit moves, its whole subtree moves with it. One statement fixes
  // every descendant; the WHEN clause below stops the cascade from recursing
  // once the paths have stopped changing.
  pgm.sql(`
    CREATE OR REPLACE FUNCTION org_units_move_subtree()
    RETURNS TRIGGER
    LANGUAGE plpgsql
    AS $$
    BEGIN
      UPDATE org_units
         SET path = NEW.path || subpath(path, nlevel(OLD.path))
       WHERE path <@ OLD.path
         AND id <> NEW.id;
      RETURN NULL;
    END;
    $$
  `);

  pgm.sql(`
    CREATE TRIGGER org_units_move_subtree
      AFTER UPDATE ON org_units
      FOR EACH ROW
      WHEN (OLD.path IS DISTINCT FROM NEW.path)
      EXECUTE FUNCTION org_units_move_subtree()
  `);

  pgm.sql('CREATE INDEX org_units_path_idx ON org_units USING GIST (path)');
  pgm.sql('CREATE INDEX org_units_parent_idx ON org_units (parent_id)');
  pgm.sql('CREATE INDEX org_units_site_idx ON org_units (site_id)');
  pgm.sql(`
    CREATE INDEX org_units_active_idx ON org_units (site_id, unit_type)
      WHERE is_active
  `);

  // --------------------------------------------------------------------------
  // cost_centers
  //
  // The accounting axis, kept separate from the physical one. A cost centre
  // often spans two lines, or one line is split across two cost centres, and
  // forcing them into the same tree makes both wrong.
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE TABLE cost_centers (
      id          BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      site_id     BIGINT      NOT NULL REFERENCES sites (id),
      code        TEXT        NOT NULL,
      name        TEXT        NOT NULL,
      is_active   BOOLEAN     NOT NULL DEFAULT TRUE,
      created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by  BIGINT,
      updated_by  BIGINT,

      CONSTRAINT cost_centers_code_unique UNIQUE (site_id, code)
    )
  `);

  // --------------------------------------------------------------------------
  // assets
  //
  // Machines and equipment. Downtime and OEE attach here rather than to the
  // org unit, because a line's availability is not meaningful until you know
  // which machine on it stopped.
  //
  // `parent_id` and `asset_level` let an asset be a component of another asset
  // rather than only a flat machine list: a failure history worth computing
  // MTBF from needs to say "the gearbox on the infeed conveyor failed", not
  // just "the line stopped". There is deliberately no materialised ltree path
  // here as there is on org_units — an asset tree is a handful of levels deep
  // and is queried per-machine, not swept in aggregate across a plant, so the
  // trigger and GiST index that pay for themselves on the org tree would not
  // here.
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE TABLE assets (
      id              BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      org_unit_id     BIGINT      NOT NULL REFERENCES org_units (id),
      code            TEXT        NOT NULL,
      name            TEXT        NOT NULL,
      asset_type      TEXT        NOT NULL DEFAULT 'machine'
                                  CHECK (asset_type IN ('machine', 'cell', 'tool',
                                                        'utility', 'vehicle', 'other')),
      -- Drives which stops get escalated and which spares are held.
      criticality     TEXT        NOT NULL DEFAULT 'medium'
                                  CHECK (criticality IN ('low', 'medium', 'high', 'critical')),
      manufacturer    TEXT,
      model           TEXT,
      serial_no       TEXT,
      commissioned_on DATE,
      -- True for the machine that sets the pace of the line. OEE on a
      -- non-constraint machine is a number; OEE on the constraint is the plant.
      is_constraint   BOOLEAN     NOT NULL DEFAULT FALSE,
      is_active       BOOLEAN     NOT NULL DEFAULT TRUE,
      created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by      BIGINT,
      updated_by      BIGINT,
      -- Where this sits in the tree. A component's failures roll up to the
      -- machine it is part of; a machine's roll up to nothing.
      parent_id       BIGINT      REFERENCES assets (id),
      asset_level     TEXT        NOT NULL DEFAULT 'machine'
                                  CHECK (asset_level IN ('machine', 'assembly', 'component')),

      CONSTRAINT assets_code_unique UNIQUE (code),
      -- An asset cannot be its own parent. This does not prevent a longer
      -- cycle — Postgres has no declarative way to say that — but it catches
      -- the mistake that actually happens, which is a row edited to point at
      -- itself.
      CONSTRAINT assets_parent_not_self CHECK (parent_id IS DISTINCT FROM id)
    )
  `);

  pgm.sql('CREATE INDEX assets_org_unit_idx ON assets (org_unit_id)');
  pgm.sql('CREATE INDEX assets_active_idx ON assets (org_unit_id) WHERE is_active');
  pgm.sql('CREATE INDEX assets_parent_idx ON assets (parent_id) WHERE parent_id IS NOT NULL');

  pgm.sql(`SELECT attach_updated_at('sites')`);
  pgm.sql(`SELECT attach_updated_at('org_units')`);
  pgm.sql(`SELECT attach_updated_at('cost_centers')`);
  pgm.sql(`SELECT attach_updated_at('assets')`);

  // ============================================================================
  // The shift calendar.
  //
  // This is the least obvious and most important table in the schema.
  //
  // A night shift running 22:00 to 06:00 spans two calendar dates. If events are
  // grouped by `date(occurred_at)` — the obvious thing to do — that shift is cut
  // in half, its output lands on two days, its downtime lands on two days, and
  // every OEE, scrap and attendance number derived from it is wrong. Worse, it is
  // wrong quietly: the totals still add up across the month, so nobody notices
  // until someone asks why Tuesday nights look bad.
  //
  // So a `shift_instance` is created up front for every shift that will be
  // worked, carrying an explicit `production_date`. Every event table then stores
  // two things: its real TIMESTAMPTZ, which is the truth, and a
  // shift_instance_id, which is the reporting bucket. The night shift beginning
  // 22:00 on the 30th has production_date = 2026-08-30 for its whole length,
  // including the hours that fall on the 31st.
  //
  // The instance is also where planned production time lives, which makes it the
  // denominator of both OEE availability and the attendance rate.
  // ============================================================================

  // --------------------------------------------------------------------------
  // shift_definitions
  //
  // `day_offset` is what lets a shift belong to a production date it does not
  // start on. A shift starting 00:30 that belongs to the *previous* production
  // day has day_offset = 1: for production_date D it starts at D+1 00:30.
  // A 22:00 night shift belonging to D has day_offset = 0.
  //
  // Between the two, one, two, three and rotating shift patterns are all just
  // data — no schema change to add a shift.
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE TABLE shift_definitions (
      id               BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      site_id          BIGINT      NOT NULL REFERENCES sites (id),
      code             TEXT        NOT NULL,
      name             TEXT        NOT NULL,
      start_time       TIME        NOT NULL,
      duration_minutes INTEGER     NOT NULL CHECK (duration_minutes BETWEEN 1 AND 1440),
      -- Scheduled breaks are subtracted from planned production time rather
      -- than logged as planned downtime. Both conventions exist; this one is
      -- the more common and keeps the downtime log to unscheduled events plus
      -- changeovers. Whichever you pick, picking it once is what matters.
      break_minutes    INTEGER     NOT NULL DEFAULT 0 CHECK (break_minutes >= 0),
      day_offset       INTEGER     NOT NULL DEFAULT 0 CHECK (day_offset BETWEEN 0 AND 1),
      sort_order       INTEGER     NOT NULL DEFAULT 0,
      is_active        BOOLEAN     NOT NULL DEFAULT TRUE,
      created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by       BIGINT,
      updated_by       BIGINT,

      CONSTRAINT shift_definitions_code_unique UNIQUE (site_id, code),
      CONSTRAINT shift_definitions_breaks_fit CHECK (break_minutes < duration_minutes)
    )
  `);

  // --------------------------------------------------------------------------
  // crews
  //
  // The rotating team (A/B/C/D), as distinct from the shift slot they happen to
  // be working this week. Keeping them separate is what lets you ask whether
  // nights are worse than days *and* whether crew C is struggling — two
  // different questions that a single "shift" column cannot answer.
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE TABLE crews (
      id          BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      site_id     BIGINT      NOT NULL REFERENCES sites (id),
      code        TEXT        NOT NULL,
      name        TEXT        NOT NULL,
      is_active   BOOLEAN     NOT NULL DEFAULT TRUE,
      created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by  BIGINT,
      updated_by  BIGINT,

      CONSTRAINT crews_code_unique UNIQUE (site_id, code)
    )
  `);

  // --------------------------------------------------------------------------
  // calendar_exceptions
  //
  // Days no shift instance should be generated for, or should be generated
  // differently: public holidays, planned shutdowns, maintenance weeks.
  // org_unit_id NULL means the whole site.
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE TABLE calendar_exceptions (
      id              BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      site_id         BIGINT      NOT NULL REFERENCES sites (id),
      org_unit_id     BIGINT      REFERENCES org_units (id),
      exception_date  DATE        NOT NULL,
      exception_type  TEXT        NOT NULL
                                  CHECK (exception_type IN ('holiday', 'shutdown',
                                                            'maintenance', 'non_working')),
      description     TEXT,
      created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by      BIGINT,
      updated_by      BIGINT
    )
  `);

  pgm.sql(`
    CREATE INDEX calendar_exceptions_date_idx
      ON calendar_exceptions (site_id, exception_date)
  `);

  // --------------------------------------------------------------------------
  // shift_instances
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE TABLE shift_instances (
      id                        BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      site_id                   BIGINT      NOT NULL REFERENCES sites (id),
      org_unit_id               BIGINT      NOT NULL REFERENCES org_units (id),
      shift_definition_id       BIGINT      NOT NULL REFERENCES shift_definitions (id),
      crew_id                   BIGINT      REFERENCES crews (id),
      production_date           DATE        NOT NULL,
      starts_at                 TIMESTAMPTZ NOT NULL,
      ends_at                   TIMESTAMPTZ NOT NULL,
      -- Duration minus breaks. The OEE availability denominator and the
      -- attendance denominator both read this, so an unplanned change to the
      -- schedule is recorded by editing this one number.
      planned_production_minutes INTEGER    NOT NULL CHECK (planned_production_minutes >= 0),
      status                    TEXT        NOT NULL DEFAULT 'planned'
                                            CHECK (status IN ('planned', 'active',
                                                              'closed', 'cancelled')),
      notes                     TEXT,
      created_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by                BIGINT,
      updated_by                BIGINT,

      CONSTRAINT shift_instances_unique
        UNIQUE (org_unit_id, production_date, shift_definition_id),
      CONSTRAINT shift_instances_ends_after_start CHECK (ends_at > starts_at),

      -- Two shift instances covering the same org unit at the same moment would
      -- double the planned production time and halve the reported OEE. There is
      -- no legitimate case for it, so it is not merely discouraged.
      CONSTRAINT shift_instances_no_overlap
        EXCLUDE USING gist (
          org_unit_id WITH =,
          tstzrange(starts_at, ends_at, '[)') WITH &&
        )
    )
  `);

  pgm.sql(`
    CREATE INDEX shift_instances_date_idx
      ON shift_instances (org_unit_id, production_date DESC)
  `);
  pgm.sql(`
    CREATE INDEX shift_instances_window_idx
      ON shift_instances USING gist (org_unit_id, tstzrange(starts_at, ends_at, '[)'))
  `);
  pgm.sql('CREATE INDEX shift_instances_crew_idx ON shift_instances (crew_id)');

  // --------------------------------------------------------------------------
  // generate_shift_instances
  //
  // Builds the calendar ahead of time for one org unit. Run it for a year at a
  // time; it is idempotent, so re-running it to extend the horizon is safe.
  //
  // Note the timestamp arithmetic. The start is computed in the *site's* local
  // time and converted, so 06:00 means 06:00 to the people on the floor across
  // a daylight-saving change. The end is start + duration as an absolute
  // interval, because an eight-hour shift is eight hours of running time for
  // OEE purposes even on the night the clocks move.
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE OR REPLACE FUNCTION generate_shift_instances(
      p_org_unit_id BIGINT,
      p_from        DATE,
      p_to          DATE
    )
    RETURNS INTEGER
    LANGUAGE plpgsql
    AS $$
    DECLARE
      v_site_id  BIGINT;
      v_timezone TEXT;
      v_created  INTEGER := 0;
      v_rows     INTEGER;
    BEGIN
      SELECT ou.site_id, s.timezone
        INTO v_site_id, v_timezone
        FROM org_units ou
        JOIN sites s ON s.id = ou.site_id
       WHERE ou.id = p_org_unit_id;

      IF v_site_id IS NULL THEN
        RAISE EXCEPTION 'unknown org unit %', p_org_unit_id;
      END IF;

      INSERT INTO shift_instances (
        site_id, org_unit_id, shift_definition_id, production_date,
        starts_at, ends_at, planned_production_minutes
      )
      SELECT
        v_site_id,
        p_org_unit_id,
        sd.id,
        d.production_date,
        ((d.production_date + sd.day_offset) + sd.start_time) AT TIME ZONE v_timezone,
        (((d.production_date + sd.day_offset) + sd.start_time) AT TIME ZONE v_timezone)
          + make_interval(mins => sd.duration_minutes),
        sd.duration_minutes - sd.break_minutes
      FROM (
        SELECT generate_series(p_from, p_to, INTERVAL '1 day')::date AS production_date
      ) d
      CROSS JOIN shift_definitions sd
      WHERE sd.site_id = v_site_id
        AND sd.is_active
        AND NOT EXISTS (
          SELECT 1
            FROM calendar_exceptions ce
           WHERE ce.site_id = v_site_id
             AND ce.exception_date = d.production_date
             AND ce.exception_type IN ('holiday', 'shutdown', 'non_working')
             AND (ce.org_unit_id IS NULL OR ce.org_unit_id = p_org_unit_id)
        )
      ON CONFLICT ON CONSTRAINT shift_instances_unique DO NOTHING;

      GET DIAGNOSTICS v_rows = ROW_COUNT;
      v_created := v_rows;

      RETURN v_created;
    END;
    $$
  `);

  // --------------------------------------------------------------------------
  // extend_shift_calendar
  //
  // Gives the nightly maintenance job something to call so the calendar keeps
  // rolling forward. `generate_shift_instances` only builds instances for one
  // org unit at a time; this extends every org unit that is already on the
  // calendar, which is what keeps `fill_shift_instance` from silently writing
  // NULL into every new event once the existing horizon runs out. It touches
  // only org units that already have shift instances — a unit nobody has
  // generated shifts for does not run to a shift pattern, and inventing one
  // for it would put scheduled minutes against a machine that was never
  // scheduled.
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE OR REPLACE FUNCTION extend_shift_calendar(p_days INTEGER DEFAULT 90)
    RETURNS TABLE (org_unit_id BIGINT, generated INTEGER)
    LANGUAGE plpgsql
    AS $$
    DECLARE
      v_unit RECORD;
      v_count INTEGER;
    BEGIN
      FOR v_unit IN
        SELECT si.org_unit_id AS id, MAX(si.production_date) AS last_day
        FROM shift_instances si
        JOIN org_units ou ON ou.id = si.org_unit_id AND ou.is_active
        GROUP BY si.org_unit_id
      LOOP
        -- generate_shift_instances skips days it has already made, so starting
        -- from the day after the last one is belt and braces rather than a
        -- correctness requirement.
        IF v_unit.last_day < CURRENT_DATE + p_days THEN
          v_count := generate_shift_instances(
            v_unit.id,
            GREATEST(v_unit.last_day + 1, CURRENT_DATE),
            CURRENT_DATE + p_days
          );
        ELSE
          v_count := 0;
        END IF;

        org_unit_id := v_unit.id;
        generated := v_count;
        RETURN NEXT;
      END LOOP;
    END;
    $$
  `);

  pgm.sql(`
    COMMENT ON FUNCTION extend_shift_calendar(INTEGER) IS
      'Rolls the shift calendar forward for every org unit already on it. '
      'Run nightly; without it the calendar expires and every reliability '
      'number silently goes blank.'
  `);

  // --------------------------------------------------------------------------
  // shift_instance_at
  //
  // Resolves the shift instance an event belongs to. The API calls this when a
  // record is written, so that operators never pick a shift from a dropdown —
  // they get it wrong at 23:55, and at 06:05, which are precisely the moments
  // that matter.
  //
  // Returns NULL when nothing covers that moment (an unplanned Saturday, say),
  // which the caller must handle rather than guessing.
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE OR REPLACE FUNCTION shift_instance_at(
      p_org_unit_id BIGINT,
      p_at          TIMESTAMPTZ
    )
    RETURNS BIGINT
    LANGUAGE sql
    STABLE
    AS $$
      -- Walks up the hierarchy: an event on a work centre resolves to the shift
      -- instance generated for its line.
      SELECT si.id
        FROM public.shift_instances si
        JOIN public.org_units target ON target.id = p_org_unit_id
        JOIN public.org_units owner  ON owner.id = si.org_unit_id
       WHERE target.path <@ owner.path
         AND si.starts_at <= p_at
         AND si.ends_at   >  p_at
         AND si.status <> 'cancelled'
       ORDER BY public.nlevel(owner.path) DESC
       LIMIT 1;
    $$
  `);

  // --------------------------------------------------------------------------
  // plant_date
  //
  // Converts a moment to the calendar date it fell on *at the plant*.
  //
  // This exists because `some_timestamptz::date` is a trap. The cast is
  // evaluated in the session's TimeZone setting, which in a container is UTC —
  // so an order completed at 06:00 on the 31st in a UTC+7 plant reports as
  // having completed on the 30th, and nobody can work out why the on-time
  // delivery number disagrees with the shop floor.
  //
  // Anywhere an event already has a shift instance, that instance's
  // production_date is better still and should be preferred: it is the shift's
  // own bucket rather than a midnight boundary. This function is for the
  // records that have no shift — orders, complaints, supplier issues.
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE OR REPLACE FUNCTION plant_date(
      p_org_unit_id BIGINT,
      p_at          TIMESTAMPTZ
    )
    RETURNS DATE
    LANGUAGE sql
    STABLE
    AS $$
      SELECT (p_at AT TIME ZONE COALESCE(s.timezone, 'UTC'))::date
        FROM public.org_units ou
        JOIN public.sites s ON s.id = ou.site_id
       WHERE ou.id = p_org_unit_id;
    $$
  `);

  // --------------------------------------------------------------------------
  // fill_shift_instance
  //
  // Attached to every event table, so a caller that supplies only a timestamp
  // and an org unit still lands in the right production day. The API could do
  // this itself, but the whole schema's reporting rests on the bucket being
  // right, and "the one place that cannot forget" is the database.
  //
  // The timestamp column differs per table (detected_at, started_at,
  // occurred_at), so it is passed as a trigger argument and read through JSONB
  // rather than named statically.
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE OR REPLACE FUNCTION fill_shift_instance()
    RETURNS TRIGGER
    LANGUAGE plpgsql
    AS $$
    DECLARE
      v_row jsonb;
      v_at  TIMESTAMPTZ;
      v_org BIGINT;
    BEGIN
      IF NEW.shift_instance_id IS NOT NULL THEN
        RETURN NEW;
      END IF;

      v_row := to_jsonb(NEW);
      v_at  := (v_row ->> TG_ARGV[0])::timestamptz;
      v_org := (v_row ->> 'org_unit_id')::bigint;

      IF v_at IS NULL OR v_org IS NULL THEN
        RETURN NEW;
      END IF;

      NEW.shift_instance_id := shift_instance_at(v_org, v_at);
      RETURN NEW;
    END;
    $$
  `);

  pgm.sql(`
    CREATE OR REPLACE FUNCTION attach_shift_instance(p_table TEXT, p_time_column TEXT)
    RETURNS VOID
    LANGUAGE plpgsql
    AS $$
    BEGIN
      EXECUTE format(
        'CREATE TRIGGER %I BEFORE INSERT ON %I
           FOR EACH ROW EXECUTE FUNCTION fill_shift_instance(%L)',
        p_table || '_fill_shift', p_table, p_time_column
      );
    END;
    $$
  `);

  pgm.sql(`SELECT attach_updated_at('shift_definitions')`);
  pgm.sql(`SELECT attach_updated_at('crews')`);
  pgm.sql(`SELECT attach_updated_at('calendar_exceptions')`);
  pgm.sql(`SELECT attach_updated_at('shift_instances')`);

  // ============================================================================
  // Products, units of measure, and the two things that must be versioned:
  // standard cost and ideal cycle time.
  //
  // The unit-of-measure table is what makes one schema serve discrete, batch and
  // repetitive lines at once. Every quantity column in this schema is
  // NUMERIC(18,4) with a companion uom_code, never an INTEGER: a piece-count line
  // stores 1200.0000 EA and a batch line stores 847.5000 KG in the same column,
  // and neither has to pretend to be the other.
  //
  // Standard cost and cycle time are tables rather than columns because both
  // change, and both are inputs to KPIs that must stay reproducible. Overwrite a
  // standard cost and last quarter's scrap-cost number silently changes; the
  // board loses its credibility the first time someone notices history moving.
  // ============================================================================

  // --------------------------------------------------------------------------
  // units_of_measure
  //
  // Conversion is expressed against a base unit per dimension, so kg/g/tonne
  // and EA/box/pallet each convert within their own family and never across.
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE TABLE units_of_measure (
      code            TEXT        PRIMARY KEY,
      name            TEXT        NOT NULL,
      dimension       TEXT        NOT NULL
                                  CHECK (dimension IN ('count', 'mass', 'length',
                                                       'volume', 'area', 'time')),
      base_uom_code   TEXT        NOT NULL REFERENCES units_of_measure (code),
      factor_to_base  NUMERIC(18,8) NOT NULL DEFAULT 1
                                  CHECK (factor_to_base > 0),
      is_active       BOOLEAN     NOT NULL DEFAULT TRUE,
      created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by      BIGINT,
      updated_by      BIGINT
    )
  `);

  // --------------------------------------------------------------------------
  // customers and suppliers
  //
  // Deliberately minimal. This is not a CRM — they exist so a complaint has
  // someone to belong to and an incoming non-conformance has someone to charge.
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE TABLE customers (
      id            BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      code          TEXT        NOT NULL UNIQUE,
      name          TEXT        NOT NULL,
      contact_email TEXT,
      is_active     BOOLEAN     NOT NULL DEFAULT TRUE,
      created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by    BIGINT,
      updated_by    BIGINT
    )
  `);

  pgm.sql(`
    CREATE TABLE suppliers (
      id            BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      code          TEXT        NOT NULL UNIQUE,
      name          TEXT        NOT NULL,
      contact_email TEXT,
      is_active     BOOLEAN     NOT NULL DEFAULT TRUE,
      created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by    BIGINT,
      updated_by    BIGINT
    )
  `);

  // --------------------------------------------------------------------------
  // products
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE TABLE products (
      id            BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      code          TEXT        NOT NULL UNIQUE,
      name          TEXT        NOT NULL,
      description   TEXT,
      product_type  TEXT        NOT NULL DEFAULT 'finished'
                                CHECK (product_type IN ('finished', 'semi_finished',
                                                        'raw', 'packaging', 'consumable')),
      uom_code      TEXT        NOT NULL REFERENCES units_of_measure (code),
      supplier_id   BIGINT      REFERENCES suppliers (id),
      is_active     BOOLEAN     NOT NULL DEFAULT TRUE,
      created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by    BIGINT,
      updated_by    BIGINT
    )
  `);

  pgm.sql('CREATE INDEX products_active_idx ON products (product_type) WHERE is_active');

  // --------------------------------------------------------------------------
  // product_costs
  //
  // effective_to NULL means "still current". The EXCLUDE constraint makes two
  // overlapping cost records for one product impossible, so the lookup below
  // can never return two rows and quietly pick one.
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE TABLE product_costs (
      id             BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      product_id     BIGINT      NOT NULL REFERENCES products (id) ON DELETE CASCADE,
      standard_cost  NUMERIC(18,4) NOT NULL CHECK (standard_cost >= 0),
      currency       TEXT        NOT NULL DEFAULT 'USD'
                                 CHECK (char_length(currency) = 3),
      effective_from DATE        NOT NULL,
      effective_to   DATE,
      note           TEXT,
      created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by     BIGINT,
      updated_by     BIGINT,

      CONSTRAINT product_costs_range_valid
        CHECK (effective_to IS NULL OR effective_to > effective_from),
      CONSTRAINT product_costs_no_overlap
        EXCLUDE USING gist (
          product_id WITH =,
          daterange(effective_from, effective_to, '[)') WITH &&
        )
    )
  `);

  pgm.sql('CREATE INDEX product_costs_product_idx ON product_costs (product_id, effective_from DESC)');

  // --------------------------------------------------------------------------
  // product_cycle_times
  //
  // The denominator of the OEE performance factor. A row with asset_id NULL is
  // the product's default; a row naming an asset overrides it for that machine,
  // which is how you model the old press being slower than the new one.
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE TABLE product_cycle_times (
      id                   BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      product_id           BIGINT      NOT NULL REFERENCES products (id) ON DELETE CASCADE,
      asset_id             BIGINT      REFERENCES assets (id),
      -- Seconds of running time per one unit of the product's own UoM. For a
      -- batch line that is seconds per kg, which is unusual to read but keeps
      -- the performance formula identical for every kind of line.
      ideal_cycle_seconds  NUMERIC(18,6) NOT NULL CHECK (ideal_cycle_seconds > 0),
      effective_from       DATE        NOT NULL,
      effective_to         DATE,
      source               TEXT        NOT NULL DEFAULT 'engineering'
                                       CHECK (source IN ('engineering', 'time_study',
                                                         'best_observed', 'nameplate')),
      note                 TEXT,
      created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by           BIGINT,
      updated_by           BIGINT,

      CONSTRAINT product_cycle_times_range_valid
        CHECK (effective_to IS NULL OR effective_to > effective_from),
      CONSTRAINT product_cycle_times_no_overlap
        EXCLUDE USING gist (
          product_id WITH =,
          (COALESCE(asset_id, 0)) WITH =,
          daterange(effective_from, effective_to, '[)') WITH &&
        )
    )
  `);

  pgm.sql(`
    CREATE INDEX product_cycle_times_lookup_idx
      ON product_cycle_times (product_id, asset_id, effective_from DESC)
  `);

  // --------------------------------------------------------------------------
  // Point-in-time lookups.
  //
  // Every cost and OEE view goes through these two functions rather than
  // joining the versioned tables by hand. One place to be right, and the
  // "effective at the time of the event, not the time of the report" rule is
  // enforced by construction.
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE OR REPLACE FUNCTION product_standard_cost(
      p_product_id BIGINT,
      p_at         DATE
    )
    RETURNS NUMERIC
    LANGUAGE sql
    STABLE
    AS $$
      SELECT pc.standard_cost
        FROM public.product_costs pc
       WHERE pc.product_id = p_product_id
         AND pc.effective_from <= p_at
         AND (pc.effective_to IS NULL OR pc.effective_to > p_at)
       LIMIT 1;
    $$
  `);

  pgm.sql(`
    CREATE OR REPLACE FUNCTION ideal_cycle_seconds(
      p_product_id BIGINT,
      p_asset_id   BIGINT,
      p_at         DATE
    )
    RETURNS NUMERIC
    LANGUAGE sql
    STABLE
    AS $$
      SELECT ct.ideal_cycle_seconds
        FROM public.product_cycle_times ct
       WHERE ct.product_id = p_product_id
         AND (ct.asset_id = p_asset_id OR ct.asset_id IS NULL)
         AND ct.effective_from <= p_at
         AND (ct.effective_to IS NULL OR ct.effective_to > p_at)
       -- An asset-specific rate beats the product default.
       ORDER BY ct.asset_id NULLS LAST
       LIMIT 1;
    $$
  `);

  pgm.sql(`SELECT attach_updated_at('units_of_measure')`);
  pgm.sql(`SELECT attach_updated_at('customers')`);
  pgm.sql(`SELECT attach_updated_at('suppliers')`);
  pgm.sql(`SELECT attach_updated_at('products')`);
  pgm.sql(`SELECT attach_updated_at('product_costs')`);
  pgm.sql(`SELECT attach_updated_at('product_cycle_times')`);

  // ============================================================================
  // The People pillar: employees, assignments, attendance.
  //
  // A deliberate note on what is *not* here, because the omissions are the
  // design rather than an oversight:
  //
  //   - No date of birth, national identifier, home address, or salary. The
  //     shop floor does not need them, so holding them would be risk without
  //     benefit.
  //   - No table anywhere in this schema accumulates output, scrap or downtime
  //     against a named operator. Events record who entered or reported them,
  //     which ISO 9001 requires and which is a different thing from a
  //     performance metric — there is simply nowhere to add one up. That is the
  //     point. Beyond the data-protection exposure, per-operator scoreboards
  //     reliably teach people to stop reporting the small stops and the near
  //     misses, which are exactly the records the rest of this schema depends
  //     on.
  //
  // `employees` is the rich table — the Platform has no separate directory app,
  // so there is nothing else for a person's record to live in. `work_email` is
  // an ordinary column here, with a case-insensitive unique index: an email is
  // case-insensitive, and two employees differing only in the case of their
  // address are one person entered twice.
  //
  // `attendance_records` does three jobs at once, which is why it hangs off a
  // shift instance rather than a date: it is the absenteeism KPI, the labour
  // hours behind derived cost, and the exposure-hours denominator for the safety
  // injury rates.
  // ============================================================================
  pgm.sql(`
    CREATE TABLE job_roles (
      id          BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      code        TEXT        NOT NULL UNIQUE,
      name        TEXT        NOT NULL,
      is_active   BOOLEAN     NOT NULL DEFAULT TRUE,
      created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by  BIGINT,
      updated_by  BIGINT
    )
  `);

  pgm.sql(`
    CREATE TABLE employees (
      id                  BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      employee_no         TEXT        NOT NULL UNIQUE,
      first_name          TEXT        NOT NULL,
      last_name           TEXT        NOT NULL,
      display_name        TEXT        GENERATED ALWAYS AS (first_name || ' ' || last_name) STORED,
      hired_on            DATE,
      terminated_on       DATE,
      employment_type     TEXT        NOT NULL DEFAULT 'permanent'
                                      CHECK (employment_type IN ('permanent', 'temporary',
                                                                 'agency', 'contractor',
                                                                 'apprentice')),
      default_org_unit_id BIGINT      REFERENCES org_units (id),
      default_crew_id     BIGINT      REFERENCES crews (id),
      cost_center_id      BIGINT      REFERENCES cost_centers (id),
      is_active           BOOLEAN     NOT NULL DEFAULT TRUE,
      created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by          BIGINT,
      updated_by          BIGINT,
      -- The work email a person recognises themselves by. Nullable: not every
      -- employee has one, since most of a plant cannot sign in at all.
      work_email          TEXT,

      CONSTRAINT employees_dates_valid
        CHECK (terminated_on IS NULL OR hired_on IS NULL OR terminated_on >= hired_on)
    )
  `);

  pgm.sql('CREATE INDEX employees_org_unit_idx ON employees (default_org_unit_id) WHERE is_active');
  pgm.sql('CREATE INDEX employees_crew_idx ON employees (default_crew_id) WHERE is_active');
  pgm.sql(`
    CREATE UNIQUE INDEX employees_work_email_key
      ON employees (lower(work_email))
      WHERE work_email IS NOT NULL
  `);

  // --------------------------------------------------------------------------
  // employee_assignments
  //
  // Where someone worked, and as what, over time. Kept as history rather than
  // as columns on `employees` because a skills-coverage or staffing question
  // asked about last month has to be answered with last month's org chart.
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE TABLE employee_assignments (
      id             BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      employee_id    BIGINT      NOT NULL REFERENCES employees (id) ON DELETE CASCADE,
      org_unit_id    BIGINT      NOT NULL REFERENCES org_units (id),
      job_role_id    BIGINT      REFERENCES job_roles (id),
      crew_id        BIGINT      REFERENCES crews (id),
      effective_from DATE        NOT NULL,
      effective_to   DATE,
      created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by     BIGINT,
      updated_by     BIGINT,

      CONSTRAINT employee_assignments_range_valid
        CHECK (effective_to IS NULL OR effective_to > effective_from),
      -- One person, one place at a time. Overlapping assignments double-count
      -- headcount in every staffing view.
      CONSTRAINT employee_assignments_no_overlap
        EXCLUDE USING gist (
          employee_id WITH =,
          daterange(effective_from, effective_to, '[)') WITH &&
        )
    )
  `);

  pgm.sql(`
    CREATE INDEX employee_assignments_org_unit_idx
      ON employee_assignments (org_unit_id, effective_from DESC)
  `);

  // --------------------------------------------------------------------------
  // absence_reasons
  //
  // `counts_as_absenteeism` is separate from `is_planned` on purpose. Training
  // and annual leave are both planned, but only one of them belongs in the
  // absenteeism rate — conflating them is the usual reason a P-pillar number
  // gets argued about instead of acted on.
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE TABLE absence_reasons (
      id                    BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      code                  TEXT        NOT NULL UNIQUE,
      name                  TEXT        NOT NULL,
      is_planned            BOOLEAN     NOT NULL DEFAULT FALSE,
      counts_as_absenteeism BOOLEAN     NOT NULL DEFAULT TRUE,
      is_active             BOOLEAN     NOT NULL DEFAULT TRUE,
      created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by            BIGINT,
      updated_by            BIGINT
    )
  `);

  // --------------------------------------------------------------------------
  // attendance_records
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE TABLE attendance_records (
      id                BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      employee_id       BIGINT      NOT NULL REFERENCES employees (id),
      shift_instance_id BIGINT      NOT NULL REFERENCES shift_instances (id),
      org_unit_id       BIGINT      NOT NULL REFERENCES org_units (id),
      attendance_status TEXT        NOT NULL
                                    CHECK (attendance_status IN ('present', 'late',
                                                                 'absent_planned',
                                                                 'absent_unplanned',
                                                                 'training', 'not_scheduled')),
      absence_reason_id BIGINT      REFERENCES absence_reasons (id),
      scheduled_minutes INTEGER     NOT NULL DEFAULT 0 CHECK (scheduled_minutes >= 0),
      worked_minutes    INTEGER     NOT NULL DEFAULT 0 CHECK (worked_minutes >= 0),
      overtime_minutes  INTEGER     NOT NULL DEFAULT 0 CHECK (overtime_minutes >= 0),
      recorded_by       BIGINT      REFERENCES employees (id),
      note              TEXT,
      created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by        BIGINT,
      updated_by        BIGINT,

      CONSTRAINT attendance_records_unique UNIQUE (employee_id, shift_instance_id),

      -- An absence with no reason is a data-entry hole that shows up later as an
      -- unexplained gap in the P pillar, so the database refuses it.
      CONSTRAINT attendance_records_absence_has_reason
        CHECK (
          attendance_status NOT IN ('absent_planned', 'absent_unplanned')
          OR absence_reason_id IS NOT NULL
        ),
      -- Equally, someone recorded as absent cannot have worked hours.
      CONSTRAINT attendance_records_absent_no_hours
        CHECK (
          attendance_status NOT IN ('absent_planned', 'absent_unplanned', 'not_scheduled')
          OR worked_minutes = 0
        )
    )
  `);

  pgm.sql(`
    CREATE INDEX attendance_records_shift_idx
      ON attendance_records (shift_instance_id)
  `);
  pgm.sql(`
    CREATE INDEX attendance_records_employee_idx
      ON attendance_records (employee_id, created_at DESC)
  `);
  pgm.sql(`
    CREATE INDEX attendance_records_org_unit_idx
      ON attendance_records (org_unit_id, shift_instance_id)
  `);

  pgm.sql(`SELECT attach_updated_at('job_roles')`);
  pgm.sql(`SELECT attach_updated_at('employees')`);
  pgm.sql(`SELECT attach_updated_at('employee_assignments')`);
  pgm.sql(`SELECT attach_updated_at('absence_reasons')`);
  pgm.sql(`SELECT attach_updated_at('attendance_records')`);

  // ============================================================================
  // The skills matrix.
  //
  // Proficiency uses the ILUO scale, which is the one most lean plants already
  // have drawn on a wall chart:
  //
  //   0  none          cannot perform the operation
  //   1  I  (in train) can perform under supervision
  //   2  L  (learned)  can perform unaided to standard
  //   3  U  (upskilled) can perform to standard at rate, and troubleshoot
  //   4  O  (owner)    can train and assess others
  //
  // `skill_requirements` is what turns the wall chart into something a computer
  // can act on. Storing what each line *needs* alongside what its people *have*
  // makes the gap a query rather than a judgement, so "we are one qualified
  // welder away from not being able to run nights" is visible before the person
  // books their holiday, not after.
  // ============================================================================
  pgm.sql(`
    CREATE TABLE skills (
      id                     BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      code                   TEXT        NOT NULL UNIQUE,
      name                   TEXT        NOT NULL,
      skill_category         TEXT        NOT NULL DEFAULT 'operation'
                                         CHECK (skill_category IN ('operation', 'quality',
                                                                   'safety', 'maintenance',
                                                                   'logistics', 'leadership')),
      -- Scopes a skill to part of the plant. NULL means site-wide.
      org_unit_id            BIGINT      REFERENCES org_units (id),
      requires_certification BOOLEAN     NOT NULL DEFAULT FALSE,
      -- NULL means the qualification does not expire. Anything with a number
      -- here generates an expiry date automatically on assessment.
      revalidation_months    INTEGER     CHECK (revalidation_months IS NULL
                                                OR revalidation_months > 0),
      is_active              BOOLEAN     NOT NULL DEFAULT TRUE,
      created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by             BIGINT,
      updated_by             BIGINT
    )
  `);

  pgm.sql(`
    CREATE TABLE employee_skills (
      id                BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      employee_id       BIGINT      NOT NULL REFERENCES employees (id) ON DELETE CASCADE,
      skill_id          BIGINT      NOT NULL REFERENCES skills (id) ON DELETE CASCADE,
      proficiency_level SMALLINT    NOT NULL CHECK (proficiency_level BETWEEN 0 AND 4),
      assessed_on       DATE        NOT NULL DEFAULT CURRENT_DATE,
      assessed_by       BIGINT      REFERENCES employees (id),
      expires_on        DATE,
      evidence_ref      TEXT,
      note              TEXT,
      created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by        BIGINT,
      updated_by        BIGINT,

      CONSTRAINT employee_skills_unique UNIQUE (employee_id, skill_id),
      CONSTRAINT employee_skills_expiry_valid
        CHECK (expires_on IS NULL OR expires_on > assessed_on)
    )
  `);

  pgm.sql('CREATE INDEX employee_skills_skill_idx ON employee_skills (skill_id, proficiency_level)');
  pgm.sql(`
    CREATE INDEX employee_skills_expiring_idx
      ON employee_skills (expires_on)
      WHERE expires_on IS NOT NULL
  `);

  // Derives the expiry from the skill's revalidation period when the assessor
  // did not set one. A certification that silently never expires is the failure
  // mode this prevents — it looks identical to a valid one right up until an
  // auditor asks.
  pgm.sql(`
    CREATE OR REPLACE FUNCTION employee_skills_set_expiry()
    RETURNS TRIGGER
    LANGUAGE plpgsql
    AS $$
    DECLARE
      v_months INTEGER;
    BEGIN
      IF NEW.expires_on IS NOT NULL THEN
        RETURN NEW;
      END IF;

      SELECT revalidation_months INTO v_months FROM skills WHERE id = NEW.skill_id;

      IF v_months IS NOT NULL THEN
        NEW.expires_on := (NEW.assessed_on + make_interval(months => v_months))::date;
      END IF;

      RETURN NEW;
    END;
    $$
  `);

  pgm.sql(`
    CREATE TRIGGER employee_skills_set_expiry
      BEFORE INSERT OR UPDATE OF assessed_on, skill_id ON employee_skills
      FOR EACH ROW EXECUTE FUNCTION employee_skills_set_expiry()
  `);

  // --------------------------------------------------------------------------
  // skill_requirements
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE TABLE skill_requirements (
      id                         BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      org_unit_id                BIGINT      NOT NULL REFERENCES org_units (id) ON DELETE CASCADE,
      skill_id                   BIGINT      NOT NULL REFERENCES skills (id) ON DELETE CASCADE,
      minimum_level              SMALLINT    NOT NULL DEFAULT 2
                                             CHECK (minimum_level BETWEEN 1 AND 4),
      -- How many people at or above that level the unit needs to run. This is
      -- the number that makes cross-training a plan instead of a wish.
      minimum_qualified_headcount INTEGER    NOT NULL DEFAULT 1
                                             CHECK (minimum_qualified_headcount >= 1),
      created_at                 TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at                 TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by                 BIGINT,
      updated_by                 BIGINT,

      CONSTRAINT skill_requirements_unique UNIQUE (org_unit_id, skill_id)
    )
  `);

  pgm.sql(`SELECT attach_updated_at('skills')`);
  pgm.sql(`SELECT attach_updated_at('employee_skills')`);
  pgm.sql(`SELECT attach_updated_at('skill_requirements')`);

  // ============================================================================
  // The Delivery pillar: orders, runs, and output counts.
  //
  // Three levels, because three different kinds of plant need three different
  // entry points:
  //
  //   production_orders  what was promised. Discrete and make-to-order work
  //                      starts here. On-time delivery is measured from here.
  //   production_runs    what was actually set up and run, on which machine,
  //                      during which shift. An order can span several runs and
  //                      a run can span several shifts.
  //   production_counts  what came off the line, in time buckets.
  //
  // `production_runs.production_order_id` is nullable, and that single decision is
  // what lets a repetitive line — which runs the same part all week against no
  // order at all — share a schema with a job shop where every piece traces to a
  // customer order.
  //
  // ----------------------------------------------------------------------------
  // The three count columns are mutually exclusive. This matters enough to spell
  // out, because getting it wrong is the most common way an OEE number ends up
  // overstated:
  //
  //   good_quantity    passed first time, no intervention
  //   reject_quantity  scrapped
  //   rework_quantity  produced, but needed rework before it could be accepted
  //
  //   total = good + reject + rework
  //
  // The OEE quality factor is good / total, which makes it first-pass yield.
  // Reworked units are a loss even though they are eventually shipped: they cost
  // labour, they cost time, and a plant that counts them as good has no number
  // that tells it rework is happening.
  // ============================================================================

  // --------------------------------------------------------------------------
  // production_orders
  //
  // `due_date` is when it is needed internally; `promised_date` is what the
  // customer was told. They are usually different and OTD is measured against
  // the promise, so both are kept.
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE TABLE production_orders (
      id               BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      order_no         TEXT        NOT NULL UNIQUE,
      product_id       BIGINT      NOT NULL REFERENCES products (id),
      org_unit_id      BIGINT      NOT NULL REFERENCES org_units (id),
      customer_id      BIGINT      REFERENCES customers (id),
      quantity_ordered NUMERIC(18,4) NOT NULL CHECK (quantity_ordered > 0),
      uom_code         TEXT        NOT NULL REFERENCES units_of_measure (code),
      due_date         DATE,
      promised_date    DATE,
      priority         SMALLINT    NOT NULL DEFAULT 3 CHECK (priority BETWEEN 1 AND 5),
      status           TEXT        NOT NULL DEFAULT 'planned'
                                   CHECK (status IN ('planned', 'released', 'in_progress',
                                                     'on_hold', 'completed', 'cancelled')),
      released_at      TIMESTAMPTZ,
      started_at       TIMESTAMPTZ,
      completed_at     TIMESTAMPTZ,
      -- Where the order came from. An ERP-fed order carries the ERP's own key
      -- in external_ref so a re-import updates rather than duplicates.
      source           TEXT        NOT NULL DEFAULT 'manual'
                                   CHECK (source IN ('manual', 'erp', 'import', 'api')),
      external_ref     TEXT,
      notes            TEXT,
      created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by       BIGINT,
      updated_by       BIGINT,

      CONSTRAINT production_orders_completed_has_time
        CHECK (status <> 'completed' OR completed_at IS NOT NULL)
    )
  `);

  pgm.sql(`
    CREATE INDEX production_orders_org_unit_idx
      ON production_orders (org_unit_id, promised_date)
  `);
  pgm.sql(`
    CREATE INDEX production_orders_open_idx
      ON production_orders (org_unit_id, priority, due_date)
      WHERE status IN ('planned', 'released', 'in_progress', 'on_hold')
  `);
  pgm.sql(`
    CREATE UNIQUE INDEX production_orders_external_ref_idx
      ON production_orders (source, external_ref)
      WHERE external_ref IS NOT NULL
  `);

  // --------------------------------------------------------------------------
  // production_runs
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE TABLE production_runs (
      id                  BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      production_order_id BIGINT      REFERENCES production_orders (id),
      product_id          BIGINT      NOT NULL REFERENCES products (id),
      org_unit_id         BIGINT      NOT NULL REFERENCES org_units (id),
      asset_id            BIGINT      REFERENCES assets (id),
      shift_instance_id   BIGINT      REFERENCES shift_instances (id),
      planned_quantity    NUMERIC(18,4) CHECK (planned_quantity IS NULL OR planned_quantity > 0),
      uom_code            TEXT        NOT NULL REFERENCES units_of_measure (code),
      started_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
      ended_at            TIMESTAMPTZ,
      status              TEXT        NOT NULL DEFAULT 'running'
                                      CHECK (status IN ('running', 'paused',
                                                        'completed', 'abandoned')),
      notes               TEXT,
      created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by          BIGINT,
      updated_by          BIGINT,

      CONSTRAINT production_runs_ends_after_start
        CHECK (ended_at IS NULL OR ended_at > started_at)
    )
  `);

  pgm.sql('CREATE INDEX production_runs_order_idx ON production_runs (production_order_id)');
  pgm.sql('CREATE INDEX production_runs_shift_idx ON production_runs (shift_instance_id)');
  pgm.sql(`
    CREATE INDEX production_runs_asset_idx
      ON production_runs (asset_id, started_at DESC)
  `);
  pgm.sql(`
    CREATE INDEX production_runs_open_idx
      ON production_runs (org_unit_id)
      WHERE status IN ('running', 'paused')
  `);

  // --------------------------------------------------------------------------
  // production_counts
  //
  // Hourly or per-shift while entry is manual; per-cycle once a PLC writes it.
  // `source` and `external_ref` exist from day one precisely so that change is
  // a new writer against the same table rather than a migration.
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE TABLE production_counts (
      id                BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      production_run_id BIGINT      NOT NULL REFERENCES production_runs (id) ON DELETE CASCADE,
      org_unit_id       BIGINT      NOT NULL REFERENCES org_units (id),
      asset_id          BIGINT      REFERENCES assets (id),
      shift_instance_id BIGINT      REFERENCES shift_instances (id),
      period_start      TIMESTAMPTZ NOT NULL,
      period_end        TIMESTAMPTZ NOT NULL,
      good_quantity     NUMERIC(18,4) NOT NULL DEFAULT 0 CHECK (good_quantity   >= 0),
      reject_quantity   NUMERIC(18,4) NOT NULL DEFAULT 0 CHECK (reject_quantity >= 0),
      rework_quantity   NUMERIC(18,4) NOT NULL DEFAULT 0 CHECK (rework_quantity >= 0),
      total_quantity    NUMERIC(18,4) GENERATED ALWAYS AS
                          (good_quantity + reject_quantity + rework_quantity) STORED,
      uom_code          TEXT        NOT NULL REFERENCES units_of_measure (code),
      source            TEXT        NOT NULL DEFAULT 'manual'
                                    CHECK (source IN ('manual', 'plc', 'scada', 'import', 'api')),
      external_ref      TEXT,
      recorded_by       BIGINT      REFERENCES employees (id),
      note              TEXT,
      created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by        BIGINT,
      updated_by        BIGINT,

      CONSTRAINT production_counts_period_valid CHECK (period_end > period_start),

      -- Overlapping count periods on one run mean the same pieces counted
      -- twice, which inflates both output and OEE performance. A double-tap on
      -- a tablet or a replayed machine message is enough to cause it, so the
      -- constraint is not optional.
      CONSTRAINT production_counts_no_overlap
        EXCLUDE USING gist (
          production_run_id WITH =,
          tstzrange(period_start, period_end, '[)') WITH &&
        )
    )
  `);

  pgm.sql(`
    CREATE INDEX production_counts_shift_idx
      ON production_counts (shift_instance_id, period_start)
  `);
  pgm.sql(`
    CREATE INDEX production_counts_org_unit_idx
      ON production_counts (org_unit_id, period_start DESC)
  `);
  pgm.sql(`
    CREATE INDEX production_counts_asset_idx
      ON production_counts (asset_id, period_start DESC)
  `);

  pgm.sql(`SELECT attach_shift_instance('production_runs', 'started_at')`);
  pgm.sql(`SELECT attach_shift_instance('production_counts', 'period_start')`);

  pgm.sql(`SELECT attach_updated_at('production_orders')`);
  pgm.sql(`SELECT attach_updated_at('production_runs')`);
  pgm.sql(`SELECT attach_updated_at('production_counts')`);

  // ============================================================================
  // Downtime, classified against the six big losses.
  //
  // A flat list of downtime reasons produces a Pareto chart nobody can act on,
  // because "machine fault" and "waiting for material" sit at the same level as
  // "hydraulic hose burst". The reason tree here is hierarchical — category,
  // reason, sub-reason — and every leaf rolls up to one of the six big losses,
  // which is what turns the log into an improvement backlog: breakdowns go to
  // maintenance, setup goes to SMED, minor stops go to the line team.
  //
  // The planned/unplanned split is the OEE-versus-TEEP boundary and is derived
  // from the loss category rather than set by hand, so the two can never
  // disagree. `is_planned` true means the time is removed from planned production
  // time entirely and does not hurt availability: breaks, no demand, a scheduled
  // shutdown. Changeover is deliberately *not* in that group — setup is one of
  // the six losses and should show up as an availability loss, or SMED work never
  // gets prioritised.
  // ============================================================================
  pgm.sql(`
    CREATE TABLE downtime_reasons (
      id               BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      parent_id        BIGINT      REFERENCES downtime_reasons (id),
      code             TEXT        NOT NULL UNIQUE,
      name             TEXT        NOT NULL,
      loss_category    TEXT        NOT NULL
                                   CHECK (loss_category IN (
                                     'breakdown',
                                     'setup_and_adjustment',
                                     'idling_and_minor_stops',
                                     'reduced_speed',
                                     'defects_in_process',
                                     'reduced_yield_startup',
                                     'planned_stop',
                                     'not_scheduled'
                                   )),
      -- Derived, never entered. Two columns that must agree will eventually
      -- disagree, and the day they do, availability changes for reasons nobody
      -- can explain.
      is_planned       BOOLEAN     GENERATED ALWAYS AS
                                   (loss_category IN ('planned_stop', 'not_scheduled')) STORED,
      -- Forces a free-text note on catch-all reasons, so "Other — 340 minutes"
      -- at the top of the Pareto is at least investigable.
      requires_comment BOOLEAN     NOT NULL DEFAULT FALSE,
      sort_order       INTEGER     NOT NULL DEFAULT 0,
      is_active        BOOLEAN     NOT NULL DEFAULT TRUE,
      created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by       BIGINT,
      updated_by       BIGINT
    )
  `);

  pgm.sql('CREATE INDEX downtime_reasons_parent_idx ON downtime_reasons (parent_id)');
  pgm.sql(`
    CREATE INDEX downtime_reasons_active_idx
      ON downtime_reasons (loss_category) WHERE is_active
  `);

  // --------------------------------------------------------------------------
  // downtime_events
  //
  // `asset_id` is required. A line that does not want machine-level granularity
  // creates one asset of type 'cell' standing for the whole line — which keeps
  // availability well defined, where a nullable asset would leave stops that
  // belong to nothing in particular and cannot be summed against any denominator.
  //
  // `downtime_reason_id` is nullable, because an automatically detected stop
  // exists before anybody has classified it. That is the normal state of a
  // machine feed and the reason `status` has an 'unclassified' value.
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE TABLE downtime_events (
      id                 BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      asset_id           BIGINT      NOT NULL REFERENCES assets (id),
      org_unit_id        BIGINT      NOT NULL REFERENCES org_units (id),
      production_run_id  BIGINT      REFERENCES production_runs (id),
      shift_instance_id  BIGINT      REFERENCES shift_instances (id),
      downtime_reason_id BIGINT      REFERENCES downtime_reasons (id),
      started_at         TIMESTAMPTZ NOT NULL,
      ended_at           TIMESTAMPTZ,
      duration_minutes   NUMERIC(12,2) GENERATED ALWAYS AS
                           (EXTRACT(EPOCH FROM (ended_at - started_at)) / 60.0) STORED,
      status             TEXT        GENERATED ALWAYS AS (
                           CASE
                             WHEN ended_at IS NULL           THEN 'open'
                             WHEN downtime_reason_id IS NULL THEN 'unclassified'
                             ELSE 'closed'
                           END
                         ) STORED,
      description        TEXT,
      reported_by        BIGINT      REFERENCES employees (id),
      classified_by      BIGINT      REFERENCES employees (id),
      classified_at      TIMESTAMPTZ,
      source             TEXT        NOT NULL DEFAULT 'manual'
                                     CHECK (source IN ('manual', 'plc', 'scada', 'import', 'api')),
      external_ref       TEXT,
      created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by         BIGINT,
      updated_by         BIGINT,

      CONSTRAINT downtime_events_ends_after_start
        CHECK (ended_at IS NULL OR ended_at > started_at),

      -- The constraint that makes OEE believable.
      --
      -- Two overlapping stops on one asset means the same lost minutes counted
      -- twice, and availability below zero on a bad day. It happens constantly
      -- in practice: an operator logs a stop the supervisor has already logged,
      -- or a machine feed replays a message. Overlapping downtime is the single
      -- most common reason a plant stops trusting its own OEE number, so it is
      -- rejected outright rather than cleaned up later.
      --
      -- An open stop (ended_at NULL) is treated as running to infinity, which
      -- also means an asset can only have one open stop at a time.
      CONSTRAINT downtime_events_no_overlap
        EXCLUDE USING gist (
          asset_id WITH =,
          tstzrange(started_at, COALESCE(ended_at, 'infinity'::timestamptz), '[)') WITH &&
        )
    )
  `);

  pgm.sql(`
    CREATE INDEX downtime_events_shift_idx
      ON downtime_events (shift_instance_id, started_at)
  `);
  pgm.sql(`
    CREATE INDEX downtime_events_org_unit_idx
      ON downtime_events (org_unit_id, started_at DESC)
  `);
  pgm.sql(`
    CREATE INDEX downtime_events_reason_idx
      ON downtime_events (downtime_reason_id, started_at DESC)
  `);
  // Drives the "what is down right now" screen and the "classify these" queue.
  pgm.sql(`
    CREATE INDEX downtime_events_open_idx
      ON downtime_events (org_unit_id, started_at DESC)
      WHERE ended_at IS NULL
  `);
  pgm.sql(`
    CREATE INDEX downtime_events_unclassified_idx
      ON downtime_events (org_unit_id, started_at DESC)
      WHERE downtime_reason_id IS NULL
  `);

  // --------------------------------------------------------------------------
  // org_unit_id is denormalised from the asset so that hierarchy rollups do not
  // need an extra join on the largest event table. A trigger keeps it honest
  // rather than trusting the caller to pass a matching pair.
  //
  // Note that BEFORE triggers fire in alphabetical order by trigger name, so
  // `downtime_events_fill_org` runs before `downtime_events_fill_shift` — which
  // matters, because resolving the shift instance needs the org unit.
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE OR REPLACE FUNCTION downtime_events_fill_org()
    RETURNS TRIGGER
    LANGUAGE plpgsql
    AS $$
    BEGIN
      SELECT org_unit_id INTO NEW.org_unit_id FROM assets WHERE id = NEW.asset_id;
      IF NEW.org_unit_id IS NULL THEN
        RAISE EXCEPTION 'unknown asset %', NEW.asset_id;
      END IF;
      RETURN NEW;
    END;
    $$
  `);

  pgm.sql(`
    CREATE TRIGGER downtime_events_fill_org
      BEFORE INSERT OR UPDATE OF asset_id ON downtime_events
      FOR EACH ROW EXECUTE FUNCTION downtime_events_fill_org()
  `);

  pgm.sql(`SELECT attach_shift_instance('downtime_events', 'started_at')`);
  pgm.sql(`SELECT attach_updated_at('downtime_reasons')`);
  pgm.sql(`SELECT attach_updated_at('downtime_events')`);

  // ============================================================================
  // The Quality pillar, core: defect catalogue, non-conformance log, disposition.
  //
  // Two design points carry most of the weight.
  //
  // First, `defect_codes` is a tree and `quality_issues.defect_code_id` points at
  // a leaf. Free-text defect descriptions are the reason so many plants have a
  // quality log they cannot Pareto — "scratch", "scratched", "surface mark" and
  // "cosmetic" are one problem stored four ways, and no amount of reporting
  // recovers from that.
  //
  // Second, disposition is a separate table rather than a column, because one
  // non-conformance routinely splits: of 400 suspect pieces, 120 are scrapped,
  // 260 reworked and 20 accepted on concession. Modelled as a column you must
  // either invent three records for one event or lose the split, and the cost of
  // poor quality is then unrecoverable.
  //
  // Issue numbers are generated in the database — NC-2026-00431 — because they
  // end up quoted in emails, on containment labels and in audit findings, and a
  // row id is no use for any of that.
  // ============================================================================
  pgm.sql(`
    CREATE TABLE defect_codes (
      id               BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      parent_id        BIGINT      REFERENCES defect_codes (id),
      code             TEXT        NOT NULL UNIQUE,
      name             TEXT        NOT NULL,
      defect_category  TEXT        NOT NULL DEFAULT 'product'
                                   CHECK (defect_category IN ('product', 'process',
                                                              'material', 'documentation',
                                                              'packaging')),
      default_severity TEXT        NOT NULL DEFAULT 'minor'
                                   CHECK (default_severity IN ('minor', 'major', 'critical')),
      sort_order       INTEGER     NOT NULL DEFAULT 0,
      is_active        BOOLEAN     NOT NULL DEFAULT TRUE,
      created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by       BIGINT,
      updated_by       BIGINT
    )
  `);

  pgm.sql('CREATE INDEX defect_codes_parent_idx ON defect_codes (parent_id)');

  pgm.sql('CREATE SEQUENCE quality_issues_no_seq');

  // --------------------------------------------------------------------------
  // quality_issues
  //
  // `detection_point` is the column that makes the difference between a defect
  // log and an escape analysis. The same defect found in-process, at final
  // inspection, and by the customer are three very different failures of the
  // control plan, and the cost differs by an order of magnitude each step.
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE TABLE quality_issues (
      id                     BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      issue_no               TEXT        NOT NULL UNIQUE
                                         DEFAULT 'NC-' || to_char(CURRENT_DATE, 'YYYY') || '-'
                                                 || lpad(nextval('quality_issues_no_seq')::text, 5, '0'),
      org_unit_id            BIGINT      NOT NULL REFERENCES org_units (id),
      asset_id               BIGINT      REFERENCES assets (id),
      production_run_id      BIGINT      REFERENCES production_runs (id),
      production_order_id    BIGINT      REFERENCES production_orders (id),
      product_id             BIGINT      NOT NULL REFERENCES products (id),
      -- Free text on purpose. Without a material-genealogy module there is
      -- nothing to point a foreign key at, and a batch number written down is
      -- still far better than nothing when a customer asks what else is affected.
      lot_ref                TEXT,
      defect_code_id         BIGINT      NOT NULL REFERENCES defect_codes (id),
      detection_point        TEXT        NOT NULL
                                         CHECK (detection_point IN ('incoming', 'in_process',
                                                                    'final_inspection', 'audit',
                                                                    'customer')),
      severity               TEXT        NOT NULL DEFAULT 'minor'
                                         CHECK (severity IN ('minor', 'major', 'critical')),
      quantity_affected      NUMERIC(18,4) NOT NULL CHECK (quantity_affected > 0),
      -- Maintained by trigger from the disposition rows. Cached so that "what is
      -- still sitting in the quarantine cage undecided" is an indexed query.
      quantity_dispositioned NUMERIC(18,4) NOT NULL DEFAULT 0
                                         CHECK (quantity_dispositioned >= 0),
      uom_code               TEXT        NOT NULL REFERENCES units_of_measure (code),
      detected_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
      shift_instance_id      BIGINT      REFERENCES shift_instances (id),
      detected_by            BIGINT      REFERENCES employees (id),
      description            TEXT,
      immediate_containment  TEXT,
      status                 TEXT        NOT NULL DEFAULT 'open'
                                         CHECK (status IN ('open', 'contained',
                                                           'dispositioned', 'closed',
                                                           'cancelled')),
      closed_at              TIMESTAMPTZ,
      source                 TEXT        NOT NULL DEFAULT 'manual'
                                         CHECK (source IN ('manual', 'import', 'api')),
      external_ref           TEXT,
      created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by             BIGINT,
      updated_by             BIGINT,

      CONSTRAINT quality_issues_closed_has_time
        CHECK (status NOT IN ('closed', 'cancelled') OR closed_at IS NOT NULL),
      CONSTRAINT quality_issues_disposition_fits
        CHECK (quantity_dispositioned <= quantity_affected)
    )
  `);

  pgm.sql(`
    CREATE INDEX quality_issues_org_unit_idx
      ON quality_issues (org_unit_id, detected_at DESC)
  `);
  pgm.sql(`
    CREATE INDEX quality_issues_shift_idx
      ON quality_issues (shift_instance_id)
  `);
  pgm.sql(`
    CREATE INDEX quality_issues_defect_idx
      ON quality_issues (defect_code_id, detected_at DESC)
  `);
  pgm.sql(`
    CREATE INDEX quality_issues_product_idx
      ON quality_issues (product_id, detected_at DESC)
  `);
  pgm.sql(`
    CREATE INDEX quality_issues_open_idx
      ON quality_issues (org_unit_id, severity, detected_at DESC)
      WHERE status IN ('open', 'contained')
  `);
  pgm.sql('CREATE INDEX quality_issues_run_idx ON quality_issues (production_run_id)');

  // --------------------------------------------------------------------------
  // quality_dispositions
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE TABLE quality_dispositions (
      id               BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      quality_issue_id BIGINT      NOT NULL REFERENCES quality_issues (id) ON DELETE CASCADE,
      disposition_type TEXT        NOT NULL
                                   CHECK (disposition_type IN ('scrap', 'rework', 'use_as_is',
                                                               'return_to_supplier', 'regrade',
                                                               'sort')),
      quantity         NUMERIC(18,4) NOT NULL CHECK (quantity > 0),
      uom_code         TEXT        NOT NULL REFERENCES units_of_measure (code),
      -- Feeds the rework half of cost of poor quality. Zero for scrap.
      rework_minutes   NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (rework_minutes >= 0),
      decided_by       BIGINT      REFERENCES employees (id),
      decided_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
      -- 'use_as_is' and 'regrade' are concessions and normally need a named
      -- approver or a customer deviation number; this is where that reference
      -- goes, and an auditor will ask for it.
      approval_ref     TEXT,
      notes            TEXT,
      created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by       BIGINT,
      updated_by       BIGINT,

      CONSTRAINT quality_dispositions_rework_only
        CHECK (disposition_type = 'rework' OR rework_minutes = 0)
    )
  `);

  pgm.sql(`
    CREATE INDEX quality_dispositions_issue_idx
      ON quality_dispositions (quality_issue_id)
  `);
  pgm.sql(`
    CREATE INDEX quality_dispositions_type_idx
      ON quality_dispositions (disposition_type, decided_at DESC)
  `);

  // Recomputes the cached total and lets the CHECK on quality_issues reject the
  // write. Recomputing from scratch rather than adding a delta means a corrected
  // or deleted disposition self-heals, which an incremental counter would not.
  pgm.sql(`
    CREATE OR REPLACE FUNCTION quality_dispositions_sync()
    RETURNS TRIGGER
    LANGUAGE plpgsql
    AS $$
    DECLARE
      v_issue_id BIGINT := COALESCE(NEW.quality_issue_id, OLD.quality_issue_id);
    BEGIN
      UPDATE quality_issues qi
         SET quantity_dispositioned = (
               SELECT COALESCE(SUM(qd.quantity), 0)
                 FROM quality_dispositions qd
                WHERE qd.quality_issue_id = v_issue_id
             )
       WHERE qi.id = v_issue_id;

      RETURN NULL;
    END;
    $$
  `);

  pgm.sql(`
    CREATE CONSTRAINT TRIGGER quality_dispositions_sync
      AFTER INSERT OR UPDATE OR DELETE ON quality_dispositions
      DEFERRABLE INITIALLY DEFERRED
      FOR EACH ROW EXECUTE FUNCTION quality_dispositions_sync()
  `);

  pgm.sql(`SELECT attach_shift_instance('quality_issues', 'detected_at')`);
  pgm.sql(`SELECT attach_updated_at('defect_codes')`);
  pgm.sql(`SELECT attach_updated_at('quality_issues')`);
  pgm.sql(`SELECT attach_updated_at('quality_dispositions')`);

  // ============================================================================
  // Quality facing outward: customer complaints and supplier non-conformances.
  //
  // A note on customer PPM. The honest denominator is quantity shipped, and this
  // schema has no shipping module — so the views compute it against quantity
  // produced instead. For a plant that ships what it makes within the month the
  // two are close enough to trend on, and the KPI definition says so in its
  // formula text rather than leaving someone to discover it. If exact PPM is ever
  // needed, a shipments table is the honest fix, not a fudge factor.
  // ============================================================================
  pgm.sql('CREATE SEQUENCE customer_complaints_no_seq');
  pgm.sql('CREATE SEQUENCE supplier_ncrs_no_seq');

  // --------------------------------------------------------------------------
  // customer_complaints
  //
  // `first_response_at` is separate from `closed_at` because customers judge
  // you on both, and they are different failures. A complaint closed in three
  // weeks with an acknowledgement on day one is a normal investigation; the
  // same complaint with silence until week three is a lost customer.
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE TABLE customer_complaints (
      id                BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      complaint_no      TEXT        NOT NULL UNIQUE
                                    DEFAULT 'CC-' || to_char(CURRENT_DATE, 'YYYY') || '-'
                                            || lpad(nextval('customer_complaints_no_seq')::text, 5, '0'),
      customer_id       BIGINT      NOT NULL REFERENCES customers (id),
      product_id        BIGINT      REFERENCES products (id),
      -- Which part of the plant owns it. Nullable until the investigation says.
      org_unit_id       BIGINT      REFERENCES org_units (id),
      defect_code_id    BIGINT      REFERENCES defect_codes (id),
      -- Set once an internal non-conformance is raised for the same problem.
      quality_issue_id  BIGINT      REFERENCES quality_issues (id),
      complaint_type    TEXT        NOT NULL DEFAULT 'quality'
                                    CHECK (complaint_type IN ('quality', 'delivery',
                                                              'quantity', 'documentation',
                                                              'packaging', 'service')),
      severity          TEXT        NOT NULL DEFAULT 'major'
                                    CHECK (severity IN ('minor', 'major', 'critical')),
      quantity_affected NUMERIC(18,4) CHECK (quantity_affected IS NULL OR quantity_affected > 0),
      uom_code          TEXT        REFERENCES units_of_measure (code),
      customer_ref      TEXT,
      lot_ref           TEXT,
      description       TEXT        NOT NULL,
      received_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
      response_due_at   TIMESTAMPTZ,
      first_response_at TIMESTAMPTZ,
      is_warranty       BOOLEAN     NOT NULL DEFAULT FALSE,
      claim_cost        NUMERIC(18,4) CHECK (claim_cost IS NULL OR claim_cost >= 0),
      currency          TEXT        NOT NULL DEFAULT 'USD' CHECK (char_length(currency) = 3),
      status            TEXT        NOT NULL DEFAULT 'open'
                                    CHECK (status IN ('open', 'investigating', 'responded',
                                                      'closed', 'rejected')),
      closed_at         TIMESTAMPTZ,
      created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by        BIGINT,
      updated_by        BIGINT,

      CONSTRAINT customer_complaints_closed_has_time
        CHECK (status NOT IN ('closed', 'rejected') OR closed_at IS NOT NULL),
      CONSTRAINT customer_complaints_quantity_has_uom
        CHECK (quantity_affected IS NULL OR uom_code IS NOT NULL)
    )
  `);

  pgm.sql(`
    CREATE INDEX customer_complaints_customer_idx
      ON customer_complaints (customer_id, received_at DESC)
  `);
  pgm.sql(`
    CREATE INDEX customer_complaints_product_idx
      ON customer_complaints (product_id, received_at DESC)
  `);
  pgm.sql(`
    CREATE INDEX customer_complaints_open_idx
      ON customer_complaints (response_due_at)
      WHERE status IN ('open', 'investigating')
  `);

  // --------------------------------------------------------------------------
  // supplier_ncrs
  //
  // `cost_recovered` is the column that changes behaviour. A supplier problem
  // logged without a recovery figure is an inconvenience; the same problem with
  // the cost attached is a conversation with the supplier, and it is the only
  // way incoming quality ever appears in the C pillar.
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE TABLE supplier_ncrs (
      id                BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      ncr_no            TEXT        NOT NULL UNIQUE
                                    DEFAULT 'SN-' || to_char(CURRENT_DATE, 'YYYY') || '-'
                                            || lpad(nextval('supplier_ncrs_no_seq')::text, 5, '0'),
      supplier_id       BIGINT      NOT NULL REFERENCES suppliers (id),
      product_id        BIGINT      REFERENCES products (id),
      org_unit_id       BIGINT      REFERENCES org_units (id),
      defect_code_id    BIGINT      REFERENCES defect_codes (id),
      quality_issue_id  BIGINT      REFERENCES quality_issues (id),
      incoming_lot_ref  TEXT,
      purchase_ref      TEXT,
      quantity_affected NUMERIC(18,4) NOT NULL CHECK (quantity_affected > 0),
      uom_code          TEXT        NOT NULL REFERENCES units_of_measure (code),
      disposition       TEXT        NOT NULL DEFAULT 'return_to_supplier'
                                    CHECK (disposition IN ('return_to_supplier', 'scrap',
                                                           'rework_at_cost', 'sort',
                                                           'use_as_is')),
      detected_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
      response_due_at   TIMESTAMPTZ,
      cost_recovered    NUMERIC(18,4) CHECK (cost_recovered IS NULL OR cost_recovered >= 0),
      currency          TEXT        NOT NULL DEFAULT 'USD' CHECK (char_length(currency) = 3),
      description       TEXT,
      status            TEXT        NOT NULL DEFAULT 'open'
                                    CHECK (status IN ('open', 'issued', 'responded',
                                                      'closed', 'rejected')),
      closed_at         TIMESTAMPTZ,
      created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by        BIGINT,
      updated_by        BIGINT,

      CONSTRAINT supplier_ncrs_closed_has_time
        CHECK (status NOT IN ('closed', 'rejected') OR closed_at IS NOT NULL)
    )
  `);

  pgm.sql(`
    CREATE INDEX supplier_ncrs_supplier_idx
      ON supplier_ncrs (supplier_id, detected_at DESC)
  `);
  pgm.sql(`
    CREATE INDEX supplier_ncrs_open_idx
      ON supplier_ncrs (response_due_at)
      WHERE status IN ('open', 'issued')
  `);

  pgm.sql(`SELECT attach_updated_at('customer_complaints')`);
  pgm.sql(`SELECT attach_updated_at('supplier_ncrs')`);

  // ============================================================================
  // The Safety pillar.
  //
  // Two tables, one lagging and one leading, and the leading one is the point.
  //
  // `safety_incidents` records what went wrong, on the full severity ladder from
  // near miss to fatality. `safety_observations` records what was seen before
  // anything went wrong — a safe act, an unsafe act, an unsafe condition. A board
  // carrying only the incident count can do nothing but react to a number that is
  // mostly zero and occasionally catastrophic; observation rate is the number a
  // team can actually move this week, and it is the one that predicts the other.
  //
  // `employee_id` on an incident is nullable, and `is_anonymous` exists, because
  // near-miss reporting has to be possible without naming anyone. A plant that
  // requires a name on a near-miss report stops receiving near-miss reports
  // within about a month, and then loses the only warning it had.
  //
  // `is_recordable` is derived from the severity level rather than ticked by
  // hand. Recordability follows a fixed rule — medical treatment and worse — and
  // a hand-maintained flag is how injury rates end up understated without anyone
  // intending it.
  // ============================================================================
  pgm.sql(`
    CREATE TABLE injury_types (
      id          BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      code        TEXT        NOT NULL UNIQUE,
      name        TEXT        NOT NULL,
      is_active   BOOLEAN     NOT NULL DEFAULT TRUE,
      created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by  BIGINT,
      updated_by  BIGINT
    )
  `);

  pgm.sql(`
    CREATE TABLE body_parts (
      id          BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      code        TEXT        NOT NULL UNIQUE,
      name        TEXT        NOT NULL,
      region      TEXT        NOT NULL DEFAULT 'other'
                              CHECK (region IN ('head', 'trunk', 'upper_limb',
                                                'lower_limb', 'multiple', 'other')),
      is_active   BOOLEAN     NOT NULL DEFAULT TRUE,
      created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by  BIGINT,
      updated_by  BIGINT
    )
  `);

  pgm.sql('CREATE SEQUENCE safety_incidents_no_seq');

  pgm.sql(`
    CREATE TABLE safety_incidents (
      id                   BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      incident_no          TEXT        NOT NULL UNIQUE
                                       DEFAULT 'SI-' || to_char(CURRENT_DATE, 'YYYY') || '-'
                                               || lpad(nextval('safety_incidents_no_seq')::text, 5, '0'),
      org_unit_id          BIGINT      NOT NULL REFERENCES org_units (id),
      asset_id             BIGINT      REFERENCES assets (id),
      shift_instance_id    BIGINT      REFERENCES shift_instances (id),
      occurred_at          TIMESTAMPTZ NOT NULL,
      reported_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
      incident_type        TEXT        NOT NULL
                                       CHECK (incident_type IN ('injury', 'near_miss',
                                                                'property_damage',
                                                                'environmental', 'fire',
                                                                'ergonomic', 'security')),
      severity_level       TEXT        NOT NULL
                                       CHECK (severity_level IN ('near_miss', 'first_aid',
                                                                 'medical_treatment',
                                                                 'restricted_work',
                                                                 'lost_time', 'fatality')),
      -- Derived. The recordability rule is fixed, so it is not a judgement call
      -- that gets made differently by whoever is on shift.
      is_recordable        BOOLEAN     GENERATED ALWAYS AS (
                             severity_level IN ('medical_treatment', 'restricted_work',
                                                'lost_time', 'fatality')
                           ) STORED,
      injury_type_id       BIGINT      REFERENCES injury_types (id),
      body_part_id         BIGINT      REFERENCES body_parts (id),
      employee_id          BIGINT      REFERENCES employees (id),
      is_anonymous         BOOLEAN     NOT NULL DEFAULT FALSE,
      lost_time_days       INTEGER     NOT NULL DEFAULT 0 CHECK (lost_time_days >= 0),
      restricted_days      INTEGER     NOT NULL DEFAULT 0 CHECK (restricted_days >= 0),
      description          TEXT        NOT NULL,
      immediate_action     TEXT,
      reported_by          BIGINT      REFERENCES employees (id),
      investigation_due_at TIMESTAMPTZ,
      status               TEXT        NOT NULL DEFAULT 'open'
                                       CHECK (status IN ('open', 'investigating',
                                                         'actions_pending', 'closed')),
      closed_at            TIMESTAMPTZ,
      created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by           BIGINT,
      updated_by           BIGINT,

      -- A near miss has, by definition, no injury. Recording one against a body
      -- part means it was not a near miss, and the severity ladder is the whole
      -- basis of the injury-rate numbers.
      CONSTRAINT safety_incidents_near_miss_no_injury
        CHECK (severity_level <> 'near_miss'
               OR (injury_type_id IS NULL AND body_part_id IS NULL
                   AND lost_time_days = 0 AND restricted_days = 0)),
      CONSTRAINT safety_incidents_lost_time_consistent
        CHECK (lost_time_days = 0 OR severity_level IN ('lost_time', 'fatality')),
      CONSTRAINT safety_incidents_anonymous_has_no_person
        CHECK (NOT is_anonymous OR employee_id IS NULL),
      CONSTRAINT safety_incidents_closed_has_time
        CHECK (status <> 'closed' OR closed_at IS NOT NULL),
      CONSTRAINT safety_incidents_reported_after_occurred
        CHECK (reported_at >= occurred_at)
    )
  `);

  pgm.sql(`
    CREATE INDEX safety_incidents_org_unit_idx
      ON safety_incidents (org_unit_id, occurred_at DESC)
  `);
  pgm.sql(`
    CREATE INDEX safety_incidents_shift_idx
      ON safety_incidents (shift_instance_id)
  `);
  pgm.sql(`
    CREATE INDEX safety_incidents_recordable_idx
      ON safety_incidents (occurred_at DESC)
      WHERE is_recordable
  `);
  pgm.sql(`
    CREATE INDEX safety_incidents_open_idx
      ON safety_incidents (org_unit_id, investigation_due_at)
      WHERE status <> 'closed'
  `);

  // --------------------------------------------------------------------------
  // safety_observations
  //
  // `severity_potential` is what stops a safety walk becoming a tally of
  // trip hazards. It asks what the *worst credible outcome* was, so an unsafe
  // act with fatal potential outranks fifty pieces of loose housekeeping in the
  // queue for attention.
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE TABLE safety_observations (
      id                   BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      org_unit_id          BIGINT      NOT NULL REFERENCES org_units (id),
      shift_instance_id    BIGINT      REFERENCES shift_instances (id),
      observed_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
      observation_type     TEXT        NOT NULL
                                       CHECK (observation_type IN ('safe_act', 'unsafe_act',
                                                                   'unsafe_condition')),
      category             TEXT        NOT NULL DEFAULT 'other'
                                       CHECK (category IN ('ppe', 'machine_guarding',
                                                           'housekeeping', 'ergonomics',
                                                           'chemical', 'working_at_height',
                                                           'traffic', 'energy_isolation',
                                                           'procedure', 'other')),
      severity_potential   TEXT        NOT NULL DEFAULT 'low'
                                       CHECK (severity_potential IN ('low', 'medium',
                                                                     'high', 'fatal')),
      description          TEXT        NOT NULL,
      observer_employee_id BIGINT      REFERENCES employees (id),
      action_taken         TEXT,
      -- Someone exercised stop-work authority. Rare, and the single strongest
      -- signal that the safety culture is real, so it is worth counting.
      is_stop_work         BOOLEAN     NOT NULL DEFAULT FALSE,
      created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by           BIGINT,
      updated_by           BIGINT
    )
  `);

  pgm.sql(`
    CREATE INDEX safety_observations_org_unit_idx
      ON safety_observations (org_unit_id, observed_at DESC)
  `);
  pgm.sql(`
    CREATE INDEX safety_observations_shift_idx
      ON safety_observations (shift_instance_id)
  `);
  pgm.sql(`
    CREATE INDEX safety_observations_priority_idx
      ON safety_observations (severity_potential, observed_at DESC)
      WHERE observation_type <> 'safe_act'
  `);

  pgm.sql(`SELECT attach_shift_instance('safety_incidents', 'occurred_at')`);
  pgm.sql(`SELECT attach_shift_instance('safety_observations', 'observed_at')`);
  pgm.sql(`SELECT attach_updated_at('injury_types')`);
  pgm.sql(`SELECT attach_updated_at('body_parts')`);
  pgm.sql(`SELECT attach_updated_at('safety_incidents')`);
  pgm.sql(`SELECT attach_updated_at('safety_observations')`);

  // ============================================================================
  // Structured problem solving: CAPA, 8D, 5-why, A3.
  //
  // One table serves all of them, because they are the same shape underneath — a
  // problem statement, an ordered set of steps, a causal chain, some actions, and
  // a verification that it stayed fixed. `method` says which discipline is being
  // followed and therefore which steps the UI should scaffold.
  //
  // Corrective and preventive actions are deliberately *not* here. They are rows
  // in `action_items`, the single action log shared by all five pillars, so that
  // a supervisor's open-actions list contains their CAPA actions alongside
  // everything else rather than hiding them one screen deeper.
  //
  // The source of a CAPA is expressed as one nullable foreign key per source type
  // with a check that at most one is set, rather than a (source_type, source_id)
  // pair. The pair is tidier to look at and throws away referential integrity
  // entirely: nothing stops it pointing at a row that never existed or was
  // deleted, and no amount of application discipline fixes that afterwards. Four
  // mostly-null bigint columns are cheap.
  //
  // `effectiveness_verified_at` is the field that separates a CAPA system from a
  // list of good intentions. It is the step every plant skips, and skipping it is
  // why the same problem comes back nine months later with a new number on it —
  // so an 8D here cannot be closed without it.
  // ============================================================================
  pgm.sql('CREATE SEQUENCE capas_no_seq');

  pgm.sql(`
    CREATE TABLE capas (
      id                        BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      capa_no                   TEXT        NOT NULL UNIQUE
                                            DEFAULT 'CA-' || to_char(CURRENT_DATE, 'YYYY') || '-'
                                                    || lpad(nextval('capas_no_seq')::text, 5, '0'),
      title                     TEXT        NOT NULL,
      problem_statement         TEXT,
      method                    TEXT        NOT NULL DEFAULT '8d'
                                            CHECK (method IN ('8d', '5why', 'a3', 'simple')),
      org_unit_id               BIGINT      REFERENCES org_units (id),

      quality_issue_id          BIGINT      REFERENCES quality_issues (id),
      customer_complaint_id     BIGINT      REFERENCES customer_complaints (id),
      supplier_ncr_id           BIGINT      REFERENCES supplier_ncrs (id),
      safety_incident_id        BIGINT      REFERENCES safety_incidents (id),

      -- Derived from whichever link is set, so filtering by source needs no
      -- four-way OR and cannot fall out of step with the columns it describes.
      source_type               TEXT        GENERATED ALWAYS AS (
                                  CASE
                                    WHEN quality_issue_id      IS NOT NULL THEN 'quality_issue'
                                    WHEN customer_complaint_id IS NOT NULL THEN 'customer_complaint'
                                    WHEN supplier_ncr_id       IS NOT NULL THEN 'supplier_ncr'
                                    WHEN safety_incident_id    IS NOT NULL THEN 'safety_incident'
                                    ELSE 'standalone'
                                  END
                                ) STORED,

      team_lead_employee_id     BIGINT      REFERENCES employees (id),
      opened_at                 TIMESTAMPTZ NOT NULL DEFAULT now(),
      due_date                  DATE,
      status                    TEXT        NOT NULL DEFAULT 'open'
                                            CHECK (status IN ('open', 'containment',
                                                              'root_cause', 'actions',
                                                              'verifying', 'closed',
                                                              'cancelled')),
      closed_at                 TIMESTAMPTZ,
      effectiveness_check_due_at DATE,
      effectiveness_verified_at TIMESTAMPTZ,
      effectiveness_verified_by BIGINT      REFERENCES employees (id),
      effectiveness_note        TEXT,
      created_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by                BIGINT,
      updated_by                BIGINT,

      CONSTRAINT capas_single_source CHECK (
        (quality_issue_id      IS NOT NULL)::int +
        (customer_complaint_id IS NOT NULL)::int +
        (supplier_ncr_id       IS NOT NULL)::int +
        (safety_incident_id    IS NOT NULL)::int <= 1
      ),
      CONSTRAINT capas_closed_has_time
        CHECK (status NOT IN ('closed', 'cancelled') OR closed_at IS NOT NULL),
      -- An 8D that was never verified is a 7D. The other methods are lighter
      -- weight by design and are not held to it.
      CONSTRAINT capas_eightd_needs_verification
        CHECK (status <> 'closed' OR method <> '8d' OR effectiveness_verified_at IS NOT NULL)
    )
  `);

  pgm.sql('CREATE INDEX capas_quality_issue_idx ON capas (quality_issue_id)');
  pgm.sql('CREATE INDEX capas_complaint_idx ON capas (customer_complaint_id)');
  pgm.sql('CREATE INDEX capas_supplier_ncr_idx ON capas (supplier_ncr_id)');
  pgm.sql('CREATE INDEX capas_safety_incident_idx ON capas (safety_incident_id)');
  pgm.sql(`
    CREATE INDEX capas_open_idx
      ON capas (org_unit_id, due_date)
      WHERE status NOT IN ('closed', 'cancelled')
  `);
  pgm.sql(`
    CREATE INDEX capas_verification_due_idx
      ON capas (effectiveness_check_due_at)
      WHERE status = 'verifying'
  `);

  // --------------------------------------------------------------------------
  // capa_steps
  //
  // The D1-D8 sequence for an 8D, or the equivalent stages of an A3. Kept as
  // rows rather than eight columns so the discipline can change without a
  // migration and so each step carries its own owner and due date — an 8D where
  // only the whole thing has an owner is an 8D nobody progresses.
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE TABLE capa_steps (
      id                BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      capa_id           BIGINT      NOT NULL REFERENCES capas (id) ON DELETE CASCADE,
      step_no           SMALLINT    NOT NULL CHECK (step_no BETWEEN 1 AND 12),
      code              TEXT,
      title             TEXT        NOT NULL,
      content           TEXT,
      owner_employee_id BIGINT      REFERENCES employees (id),
      due_date          DATE,
      completed_at      TIMESTAMPTZ,
      status            TEXT        NOT NULL DEFAULT 'pending'
                                    CHECK (status IN ('pending', 'in_progress',
                                                      'complete', 'skipped')),
      created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by        BIGINT,
      updated_by        BIGINT,

      CONSTRAINT capa_steps_unique UNIQUE (capa_id, step_no),
      CONSTRAINT capa_steps_complete_has_time
        CHECK (status <> 'complete' OR completed_at IS NOT NULL)
    )
  `);

  pgm.sql('CREATE INDEX capa_steps_capa_idx ON capa_steps (capa_id, step_no)');
  pgm.sql(`
    CREATE INDEX capa_steps_owner_idx
      ON capa_steps (owner_employee_id, due_date)
      WHERE status IN ('pending', 'in_progress')
  `);

  // --------------------------------------------------------------------------
  // capa_root_causes
  //
  // Holds both shapes of causal analysis:
  //
  //   cause_type 'why'      an ordered 5-why chain; `sequence` is the why
  //                         number and `is_root` marks where it stopped
  //   cause_type 'fishbone' Ishikawa branches; `category` is the 6M
  //
  // Storing the chain rather than a single "root cause" text field is what lets
  // you audit the reasoning later, which is usually where a weak 8D shows —
  // the chain stops at "operator error", three whys short of anything fixable.
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE TABLE capa_root_causes (
      id          BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      capa_id     BIGINT      NOT NULL REFERENCES capas (id) ON DELETE CASCADE,
      cause_type  TEXT        NOT NULL DEFAULT 'why'
                              CHECK (cause_type IN ('why', 'fishbone')),
      category    TEXT        CHECK (category IS NULL OR category IN
                              ('man', 'machine', 'method', 'material',
                               'measurement', 'environment')),
      sequence    SMALLINT    NOT NULL DEFAULT 1 CHECK (sequence >= 1),
      statement   TEXT        NOT NULL,
      is_root     BOOLEAN     NOT NULL DEFAULT FALSE,
      created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by  BIGINT,
      updated_by  BIGINT,

      CONSTRAINT capa_root_causes_fishbone_has_category
        CHECK (cause_type <> 'fishbone' OR category IS NOT NULL)
    )
  `);

  pgm.sql(`
    CREATE INDEX capa_root_causes_capa_idx
      ON capa_root_causes (capa_id, cause_type, sequence)
  `);

  pgm.sql(`SELECT attach_updated_at('capas')`);
  pgm.sql(`SELECT attach_updated_at('capa_steps')`);
  pgm.sql(`SELECT attach_updated_at('capa_root_causes')`);

  // ============================================================================
  // Statistical process control: characteristics, gauges, measurements.
  //
  // `measurements` is by a wide margin the highest-volume table in this schema —
  // a single line taking five features every half hour on two shifts produces
  // more rows in a month than the entire quality log produces in a decade. It is
  // therefore range-partitioned by month from the very first migration, because
  // converting a large table to a partitioned one afterwards needs an exclusive
  // lock and a full rewrite, which on a production database means a planned
  // outage nobody wants to schedule.
  //
  // `gauges` looks like a trivial lookup table and is not. A measurement taken
  // with an out-of-calibration gauge is not evidence, and being able to ask
  // "which readings came from the gauge that just failed calibration" is the
  // difference between quarantining a shift's worth of product and quarantining a
  // month's.
  //
  // `is_within_spec` is filled by trigger from the limits in force at the moment
  // of measurement rather than computed on read. Spec limits get tightened, and a
  // reading that passed in March should still read as a pass in March.
  // ============================================================================
  pgm.sql(`
    CREATE TABLE gauges (
      id                  BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      code                TEXT        NOT NULL UNIQUE,
      name                TEXT        NOT NULL,
      gauge_type          TEXT,
      resolution          NUMERIC(18,6),
      calibration_due_on  DATE,
      is_active           BOOLEAN     NOT NULL DEFAULT TRUE,
      created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by          BIGINT,
      updated_by          BIGINT
    )
  `);

  pgm.sql(`
    CREATE INDEX gauges_calibration_idx
      ON gauges (calibration_due_on) WHERE is_active
  `);

  // --------------------------------------------------------------------------
  // characteristics
  //
  // Limits are nullable so one-sided tolerances work: a minimum weld strength
  // has an LSL and no USL, and forcing a fake upper limit makes every
  // capability number nonsense.
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE TABLE characteristics (
      id                 BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      product_id         BIGINT      NOT NULL REFERENCES products (id) ON DELETE CASCADE,
      code               TEXT        NOT NULL,
      name               TEXT        NOT NULL,
      uom_code           TEXT        REFERENCES units_of_measure (code),
      nominal            NUMERIC(18,6),
      usl                NUMERIC(18,6),
      lsl                NUMERIC(18,6),
      -- A "critical to quality" or safety characteristic. Drives which chart
      -- goes on the board and which out-of-spec reading stops the line.
      is_critical        BOOLEAN     NOT NULL DEFAULT FALSE,
      measurement_method TEXT,
      sample_size        SMALLINT    NOT NULL DEFAULT 1 CHECK (sample_size >= 1),
      sample_frequency   TEXT,
      is_active          BOOLEAN     NOT NULL DEFAULT TRUE,
      created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by         BIGINT,
      updated_by         BIGINT,

      CONSTRAINT characteristics_code_unique UNIQUE (product_id, code),
      CONSTRAINT characteristics_limits_ordered
        CHECK (usl IS NULL OR lsl IS NULL OR usl > lsl),
      CONSTRAINT characteristics_has_a_limit
        CHECK (usl IS NOT NULL OR lsl IS NOT NULL)
    )
  `);

  pgm.sql('CREATE INDEX characteristics_product_idx ON characteristics (product_id)');

  // --------------------------------------------------------------------------
  // measurements
  //
  // The primary key carries measured_at because PostgreSQL requires the
  // partition key to be part of any unique constraint on a partitioned table.
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE TABLE measurements (
      id                BIGINT      GENERATED ALWAYS AS IDENTITY,
      characteristic_id BIGINT      NOT NULL REFERENCES characteristics (id),
      production_run_id BIGINT      REFERENCES production_runs (id),
      org_unit_id       BIGINT      NOT NULL REFERENCES org_units (id),
      asset_id          BIGINT      REFERENCES assets (id),
      shift_instance_id BIGINT      REFERENCES shift_instances (id),
      gauge_id          BIGINT      REFERENCES gauges (id),
      -- Subgroups are what make an X-bar/R chart possible; without them you can
      -- only chart individuals, which is far less sensitive to a drift.
      subgroup_no       INTEGER,
      sample_no         SMALLINT    NOT NULL DEFAULT 1,
      measured_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
      value             NUMERIC(18,6) NOT NULL,
      is_within_spec    BOOLEAN,
      measured_by       BIGINT      REFERENCES employees (id),
      source            TEXT        NOT NULL DEFAULT 'manual'
                                    CHECK (source IN ('manual', 'gauge', 'cmm',
                                                      'plc', 'import', 'api')),
      note              TEXT,
      created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by        BIGINT,

      PRIMARY KEY (id, measured_at)
    ) PARTITION BY RANGE (measured_at)
  `);

  pgm.sql('CREATE TABLE measurements_default PARTITION OF measurements DEFAULT');

  pgm.sql(`
    SELECT ensure_time_partitions(
      'measurements',
      (date_trunc('month', now()) - INTERVAL '12 months')::date,
      (date_trunc('month', now()) + INTERVAL '12 months')::date
    )
  `);

  pgm.sql(`
    CREATE INDEX measurements_characteristic_idx
      ON measurements (characteristic_id, measured_at DESC)
  `);
  pgm.sql(`
    CREATE INDEX measurements_run_idx
      ON measurements (production_run_id, measured_at)
  `);
  pgm.sql(`
    CREATE INDEX measurements_shift_idx
      ON measurements (shift_instance_id)
  `);
  pgm.sql(`
    CREATE INDEX measurements_out_of_spec_idx
      ON measurements (org_unit_id, measured_at DESC)
      WHERE is_within_spec = FALSE
  `);

  // Snapshots the pass/fail judgement against the limits in force right now.
  pgm.sql(`
    CREATE OR REPLACE FUNCTION measurements_evaluate_spec()
    RETURNS TRIGGER
    LANGUAGE plpgsql
    AS $$
    DECLARE
      v_usl NUMERIC;
      v_lsl NUMERIC;
    BEGIN
      IF NEW.is_within_spec IS NOT NULL THEN
        RETURN NEW;
      END IF;

      SELECT usl, lsl INTO v_usl, v_lsl
        FROM characteristics WHERE id = NEW.characteristic_id;

      NEW.is_within_spec :=
        (v_usl IS NULL OR NEW.value <= v_usl) AND
        (v_lsl IS NULL OR NEW.value >= v_lsl);

      RETURN NEW;
    END;
    $$
  `);

  pgm.sql(`
    CREATE TRIGGER measurements_evaluate_spec
      BEFORE INSERT ON measurements
      FOR EACH ROW EXECUTE FUNCTION measurements_evaluate_spec()
  `);

  pgm.sql(`SELECT attach_shift_instance('measurements', 'measured_at')`);
  pgm.sql(`SELECT attach_updated_at('gauges')`);
  pgm.sql(`SELECT attach_updated_at('characteristics')`);

  // ============================================================================
  // The Cost pillar: rates, and nothing else.
  //
  // There is no cost transaction table anywhere in this schema, and that is the
  // design rather than an omission. Every cost figure on the board is computed
  // from events that were already captured for another reason — scrap quantities
  // from the disposition log, rework minutes from the same place, lost hours from
  // the downtime log, labour hours from attendance. The C pillar therefore cannot
  // disagree with the floor data, because it *is* the floor data multiplied by a
  // rate. A separately entered cost number drifts from the events within a month,
  // and then two people arrive at the meeting with different figures and the
  // conversation is about the numbers instead of the problem.
  //
  // Rates are versioned with effective dates for the same reason product costs
  // are. A labour rate revised in October must not silently rewrite September's
  // cost of poor quality.
  //
  // Rates resolve from the most specific scope outwards — this asset, then its
  // line, then the area, then the site — so a plant can set one site-wide labour
  // rate on day one and refine it later without touching a single query.
  // ============================================================================
  pgm.sql(`
    CREATE TABLE cost_rates (
      id             BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      scope_type     TEXT        NOT NULL
                                 CHECK (scope_type IN ('site', 'org_unit', 'asset',
                                                       'cost_center')),
      scope_id       BIGINT      NOT NULL,
      rate_type      TEXT        NOT NULL
                                 CHECK (rate_type IN ('labor_per_hour',
                                                      'overtime_premium_multiplier',
                                                      'machine_downtime_per_hour',
                                                      'overhead_per_hour',
                                                      'rework_labor_per_hour')),
      -- A currency amount for every rate type except the overtime multiplier,
      -- which is dimensionless (1.5 for time-and-a-half). Sharing one column
      -- keeps the resolver simple; the KPI formulas know which is which.
      amount         NUMERIC(18,4) NOT NULL CHECK (amount >= 0),
      currency       TEXT        NOT NULL DEFAULT 'USD' CHECK (char_length(currency) = 3),
      effective_from DATE        NOT NULL,
      effective_to   DATE,
      note           TEXT,
      created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by     BIGINT,
      updated_by     BIGINT,

      CONSTRAINT cost_rates_range_valid
        CHECK (effective_to IS NULL OR effective_to > effective_from),
      -- Two overlapping rates for one scope would make the resolver's answer
      -- depend on row order, which is exactly the kind of bug that produces a
      -- cost report nobody can reproduce.
      CONSTRAINT cost_rates_no_overlap
        EXCLUDE USING gist (
          scope_type WITH =,
          scope_id   WITH =,
          rate_type  WITH =,
          daterange(effective_from, effective_to, '[)') WITH &&
        )
    )
  `);

  pgm.sql(`
    CREATE INDEX cost_rates_lookup_idx
      ON cost_rates (rate_type, scope_type, scope_id, effective_from DESC)
  `);

  // --------------------------------------------------------------------------
  // resolve_cost_rate
  //
  // Most specific wins: the asset's own rate, then the nearest ancestor org
  // unit that has one, then the site. Every cost view goes through here, so the
  // fallback rule exists in exactly one place.
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE OR REPLACE FUNCTION resolve_cost_rate(
      p_org_unit_id BIGINT,
      p_asset_id    BIGINT,
      p_rate_type   TEXT,
      p_at          DATE
    )
    RETURNS NUMERIC
    LANGUAGE sql
    STABLE
    AS $$
      WITH target AS (
        SELECT ou.id, ou.path, ou.site_id
          FROM public.org_units ou
         WHERE ou.id = p_org_unit_id
      ),
      candidates AS (
        -- The asset itself: rank 0, the most specific scope there is.
        SELECT cr.amount, 0 AS rank
          FROM public.cost_rates cr
         WHERE p_asset_id IS NOT NULL
           AND cr.scope_type = 'asset'
           AND cr.scope_id = p_asset_id
           AND cr.rate_type = p_rate_type
           AND cr.effective_from <= p_at
           AND (cr.effective_to IS NULL OR cr.effective_to > p_at)

        UNION ALL

        -- Any ancestor org unit, deepest first. nlevel gives the depth, and
        -- negating it keeps "more specific = lower rank".
        SELECT cr.amount, 1000 - public.nlevel(ancestor.path) AS rank
          FROM public.cost_rates cr
          JOIN public.org_units ancestor ON ancestor.id = cr.scope_id
          JOIN target t ON t.path <@ ancestor.path
         WHERE cr.scope_type = 'org_unit'
           AND cr.rate_type = p_rate_type
           AND cr.effective_from <= p_at
           AND (cr.effective_to IS NULL OR cr.effective_to > p_at)

        UNION ALL

        -- The site: the last resort.
        SELECT cr.amount, 2000 AS rank
          FROM public.cost_rates cr
          JOIN target t ON t.site_id = cr.scope_id
         WHERE cr.scope_type = 'site'
           AND cr.rate_type = p_rate_type
           AND cr.effective_from <= p_at
           AND (cr.effective_to IS NULL OR cr.effective_to > p_at)
      )
      SELECT amount FROM candidates ORDER BY rank LIMIT 1;
    $$
  `);

  pgm.sql(`SELECT attach_updated_at('cost_rates')`);

  // ============================================================================
  // The SQDCP board itself: pillars, KPI definitions, targets, actuals, actions
  // and tier meetings.
  //
  // This is the layer that makes the rest one framework rather than five
  // unrelated logs sharing a database.
  //
  // Three decisions here are worth reading before changing anything.
  //
  // 1. `direction` on a KPI definition is not cosmetic. Scrap PPM is red when it
  //    is high and OEE is red when it is low; without the definition saying which
  //    way is good, every consumer reimplements the comparison and one of them
  //    gets it backwards.
  //
  // 2. `kpi_actuals` snapshots the target it was judged against. Change next
  //    quarter's target and last quarter must not silently turn green. A board
  //    whose history moves is a board nobody believes twice.
  //
  // 3. `action_items` is one table for all five pillars, and for both Modules
  //    this repository ships — the source columns include `work_order_id`
  //    alongside the five-pillar sources, so a Maintenance job's follow-up is
  //    visible on the same "everything open on my line" screen as a quality
  //    non-conformance. The foreign key to `work_orders` is added once that
  //    table exists later in this migration; the column and the generated
  //    `source_type` are correct from the start.
  // ============================================================================

  // --------------------------------------------------------------------------
  // sqdcp_pillars
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE TABLE sqdcp_pillars (
      code        TEXT        PRIMARY KEY CHECK (code IN ('S', 'Q', 'D', 'C', 'P')),
      name        TEXT        NOT NULL,
      description TEXT,
      sort_order  INTEGER     NOT NULL DEFAULT 0,
      color       TEXT,
      created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by  BIGINT,
      updated_by  BIGINT
    )
  `);

  // --------------------------------------------------------------------------
  // kpi_definitions
  //
  // `calculation_type` splits KPIs the system computes from events
  // ('derived', with `source_view` naming the view that produces it) from ones
  // a human types in ('manual'). Everything in the seeded catalogue is derived
  // except where no event data can exist; manual is the escape hatch, not the
  // norm, because a manually entered KPI cannot be drilled into.
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE TABLE kpi_definitions (
      id               BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      code             TEXT        NOT NULL UNIQUE,
      name             TEXT        NOT NULL,
      pillar_code      TEXT        NOT NULL REFERENCES sqdcp_pillars (code),
      unit             TEXT,
      aggregation      TEXT        NOT NULL DEFAULT 'sum'
                                   CHECK (aggregation IN ('sum', 'avg', 'rate',
                                                          'ratio', 'last', 'count')),
      direction        TEXT        NOT NULL
                                   CHECK (direction IN ('higher_better', 'lower_better')),
      calculation_type TEXT        NOT NULL DEFAULT 'derived'
                                   CHECK (calculation_type IN ('derived', 'manual')),
      source_view      TEXT,
      decimal_places   SMALLINT    NOT NULL DEFAULT 1 CHECK (decimal_places BETWEEN 0 AND 6),
      -- Plain-language formula shown next to the number on the board. Anything
      -- with a caveat in it — customer PPM using produced rather than shipped
      -- quantity, say — says so here, where the person reading the number is.
      formula_text     TEXT,
      description      TEXT,
      sort_order       INTEGER     NOT NULL DEFAULT 0,
      is_active        BOOLEAN     NOT NULL DEFAULT TRUE,
      created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by       BIGINT,
      updated_by       BIGINT,

      CONSTRAINT kpi_definitions_derived_has_view
        CHECK (calculation_type <> 'derived' OR source_view IS NOT NULL)
    )
  `);

  pgm.sql(`
    CREATE INDEX kpi_definitions_pillar_idx
      ON kpi_definitions (pillar_code, sort_order) WHERE is_active
  `);

  // --------------------------------------------------------------------------
  // kpi_targets
  //
  // Targets are scoped to an org unit and inherited down the hierarchy, so a
  // plant-wide OEE target of 75% applies to every line until a line sets its
  // own. The thresholds define the amber band; leaving them NULL gives a plain
  // green/red target.
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE TABLE kpi_targets (
      id                 BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      kpi_definition_id  BIGINT      NOT NULL REFERENCES kpi_definitions (id) ON DELETE CASCADE,
      org_unit_id        BIGINT      NOT NULL REFERENCES org_units (id),
      period_type        TEXT        NOT NULL
                                     CHECK (period_type IN ('shift', 'day', 'week',
                                                            'month', 'quarter', 'year')),
      target_value       NUMERIC(18,4) NOT NULL,
      -- For a higher-is-better KPI, lower_threshold is the amber floor.
      -- For a lower-is-better KPI, upper_threshold is the amber ceiling.
      lower_threshold    NUMERIC(18,4),
      upper_threshold    NUMERIC(18,4),
      effective_from     DATE        NOT NULL,
      effective_to       DATE,
      note               TEXT,
      created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by         BIGINT,
      updated_by         BIGINT,

      CONSTRAINT kpi_targets_range_valid
        CHECK (effective_to IS NULL OR effective_to > effective_from),
      CONSTRAINT kpi_targets_no_overlap
        EXCLUDE USING gist (
          kpi_definition_id WITH =,
          org_unit_id       WITH =,
          period_type       WITH =,
          daterange(effective_from, effective_to, '[)') WITH &&
        )
    )
  `);

  pgm.sql(`
    CREATE INDEX kpi_targets_lookup_idx
      ON kpi_targets (kpi_definition_id, org_unit_id, period_type, effective_from DESC)
  `);

  // --------------------------------------------------------------------------
  // tier_meetings
  //
  // Created before kpi_actuals and action_items because both point at it.
  // Tier 1 is the line team at the board, tier 4 is the plant manager; the
  // level is what makes escalation meaningful rather than just a flag.
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE TABLE tier_meetings (
      id                      BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      org_unit_id             BIGINT      NOT NULL REFERENCES org_units (id),
      tier_level              SMALLINT    NOT NULL CHECK (tier_level BETWEEN 1 AND 4),
      meeting_date            DATE        NOT NULL,
      shift_instance_id       BIGINT      REFERENCES shift_instances (id),
      held_at                 TIMESTAMPTZ,
      facilitator_employee_id BIGINT      REFERENCES employees (id),
      attendee_count          SMALLINT    CHECK (attendee_count IS NULL OR attendee_count >= 0),
      notes                   TEXT,
      created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by              BIGINT,
      updated_by              BIGINT,

      CONSTRAINT tier_meetings_unique
        UNIQUE NULLS NOT DISTINCT (org_unit_id, meeting_date, tier_level, shift_instance_id)
    )
  `);

  pgm.sql(`
    CREATE INDEX tier_meetings_org_unit_idx
      ON tier_meetings (org_unit_id, meeting_date DESC)
  `);

  // --------------------------------------------------------------------------
  // kpi_actuals
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE TABLE kpi_actuals (
      id                      BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      kpi_definition_id       BIGINT      NOT NULL REFERENCES kpi_definitions (id) ON DELETE CASCADE,
      org_unit_id             BIGINT      NOT NULL REFERENCES org_units (id),
      period_type             TEXT        NOT NULL
                                          CHECK (period_type IN ('shift', 'day', 'week',
                                                                 'month', 'quarter', 'year')),
      period_start            DATE        NOT NULL,
      period_end              DATE        NOT NULL,
      shift_instance_id       BIGINT      REFERENCES shift_instances (id),
      actual_value            NUMERIC(18,4),
      -- Snapshotted from kpi_targets when the row is written. See the header.
      target_value_snapshot   NUMERIC(18,4),
      lower_threshold_snapshot NUMERIC(18,4),
      upper_threshold_snapshot NUMERIC(18,4),
      status                  TEXT        NOT NULL DEFAULT 'no_target'
                                          CHECK (status IN ('green', 'amber', 'red',
                                                            'no_target', 'no_data')),
      computed_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
      source                  TEXT        NOT NULL DEFAULT 'derived'
                                          CHECK (source IN ('derived', 'manual')),
      entered_by              BIGINT      REFERENCES employees (id),
      comment                 TEXT,
      created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by              BIGINT,
      updated_by              BIGINT,

      CONSTRAINT kpi_actuals_period_valid CHECK (period_end >= period_start),
      CONSTRAINT kpi_actuals_unique
        UNIQUE NULLS NOT DISTINCT
          (kpi_definition_id, org_unit_id, period_type, period_start, shift_instance_id)
    )
  `);

  pgm.sql(`
    CREATE INDEX kpi_actuals_board_idx
      ON kpi_actuals (org_unit_id, period_type, period_start DESC)
  `);
  pgm.sql(`
    CREATE INDEX kpi_actuals_kpi_idx
      ON kpi_actuals (kpi_definition_id, period_start DESC)
  `);
  pgm.sql(`
    CREATE INDEX kpi_actuals_red_idx
      ON kpi_actuals (org_unit_id, period_start DESC)
      WHERE status = 'red'
  `);

  // --------------------------------------------------------------------------
  // Target resolution and red/amber/green.
  //
  // Runs on write, so the snapshot and the status are decided once, against the
  // target that was in force for that period, and never recomputed afterwards.
  // The target is inherited up the hierarchy: a line without its own target
  // uses its area's, then the plant's.
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE OR REPLACE FUNCTION kpi_actuals_evaluate()
    RETURNS TRIGGER
    LANGUAGE plpgsql
    AS $$
    DECLARE
      v_direction TEXT;
    BEGIN
      IF NEW.target_value_snapshot IS NULL THEN
        SELECT kt.target_value, kt.lower_threshold, kt.upper_threshold
          INTO NEW.target_value_snapshot,
               NEW.lower_threshold_snapshot,
               NEW.upper_threshold_snapshot
          FROM kpi_targets kt
          JOIN org_units scope  ON scope.id = kt.org_unit_id
          JOIN org_units target ON target.id = NEW.org_unit_id
         WHERE kt.kpi_definition_id = NEW.kpi_definition_id
           AND kt.period_type = NEW.period_type
           AND target.path <@ scope.path
           AND kt.effective_from <= NEW.period_start
           AND (kt.effective_to IS NULL OR kt.effective_to > NEW.period_start)
         ORDER BY nlevel(scope.path) DESC
         LIMIT 1;
      END IF;

      IF NEW.actual_value IS NULL THEN
        NEW.status := 'no_data';
        RETURN NEW;
      END IF;

      IF NEW.target_value_snapshot IS NULL THEN
        NEW.status := 'no_target';
        RETURN NEW;
      END IF;

      SELECT direction INTO v_direction
        FROM kpi_definitions WHERE id = NEW.kpi_definition_id;

      IF v_direction = 'higher_better' THEN
        IF NEW.actual_value >= NEW.target_value_snapshot THEN
          NEW.status := 'green';
        ELSIF NEW.lower_threshold_snapshot IS NOT NULL
              AND NEW.actual_value >= NEW.lower_threshold_snapshot THEN
          NEW.status := 'amber';
        ELSE
          NEW.status := 'red';
        END IF;
      ELSE
        IF NEW.actual_value <= NEW.target_value_snapshot THEN
          NEW.status := 'green';
        ELSIF NEW.upper_threshold_snapshot IS NOT NULL
              AND NEW.actual_value <= NEW.upper_threshold_snapshot THEN
          NEW.status := 'amber';
        ELSE
          NEW.status := 'red';
        END IF;
      END IF;

      RETURN NEW;
    END;
    $$
  `);

  pgm.sql(`
    CREATE TRIGGER kpi_actuals_evaluate
      BEFORE INSERT OR UPDATE OF actual_value, target_value_snapshot ON kpi_actuals
      FOR EACH ROW EXECUTE FUNCTION kpi_actuals_evaluate()
  `);

  // --------------------------------------------------------------------------
  // action_items
  //
  // One nullable foreign key per source type, with a check that at most one is
  // set. The alternative — a (source_type, source_id) pair — reads better and
  // gives up referential integrity completely: nothing stops it pointing at a
  // row that never existed. Ten mostly-null bigints are cheap; a countermeasure
  // log pointing into space is not.
  //
  // `work_order_id` is a plain column here, with no inline foreign key: the
  // `work_orders` table it points at is created later in this migration, once
  // the Maintenance section of the schema exists. The constraint that ties it
  // to `work_orders` is added there. Every other column on this table,
  // including the generated `source_type`, is correct from the start.
  // --------------------------------------------------------------------------
  pgm.sql('CREATE SEQUENCE action_items_no_seq');

  pgm.sql(`
    CREATE TABLE action_items (
      id                     BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      action_no              TEXT        NOT NULL UNIQUE
                                         DEFAULT 'AC-' || to_char(CURRENT_DATE, 'YYYY') || '-'
                                                 || lpad(nextval('action_items_no_seq')::text, 5, '0'),
      title                  TEXT        NOT NULL,
      description            TEXT,
      pillar_code            TEXT        REFERENCES sqdcp_pillars (code),
      org_unit_id            BIGINT      NOT NULL REFERENCES org_units (id),
      action_type            TEXT        NOT NULL DEFAULT 'corrective'
                                         CHECK (action_type IN ('containment', 'corrective',
                                                                'preventive', 'improvement',
                                                                'task')),

      quality_issue_id       BIGINT      REFERENCES quality_issues (id),
      safety_incident_id     BIGINT      REFERENCES safety_incidents (id),
      safety_observation_id  BIGINT      REFERENCES safety_observations (id),
      downtime_event_id      BIGINT      REFERENCES downtime_events (id),
      capa_id                BIGINT      REFERENCES capas (id),
      customer_complaint_id  BIGINT      REFERENCES customer_complaints (id),
      supplier_ncr_id        BIGINT      REFERENCES supplier_ncrs (id),
      kpi_actual_id          BIGINT      REFERENCES kpi_actuals (id),
      tier_meeting_id        BIGINT      REFERENCES tier_meetings (id),

      owner_employee_id      BIGINT      REFERENCES employees (id),
      raised_by              BIGINT      REFERENCES employees (id),
      raised_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
      due_date               DATE,
      priority               SMALLINT    NOT NULL DEFAULT 3 CHECK (priority BETWEEN 1 AND 5),
      status                 TEXT        NOT NULL DEFAULT 'open'
                                         CHECK (status IN ('open', 'in_progress', 'blocked',
                                                           'done', 'cancelled')),
      completed_at           TIMESTAMPTZ,
      closure_note           TEXT,
      -- Escalation is a pointer up the hierarchy rather than a boolean, so the
      -- tier that now owns it is unambiguous.
      escalated_to_org_unit_id BIGINT    REFERENCES org_units (id),
      escalated_at           TIMESTAMPTZ,
      created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by             BIGINT,
      updated_by             BIGINT,

      -- See the header: the FK to work_orders is added once that table exists.
      work_order_id          BIGINT,

      source_type            TEXT        GENERATED ALWAYS AS (
                               CASE
                                 WHEN quality_issue_id      IS NOT NULL THEN 'quality_issue'
                                 WHEN safety_incident_id    IS NOT NULL THEN 'safety_incident'
                                 WHEN safety_observation_id IS NOT NULL THEN 'safety_observation'
                                 WHEN downtime_event_id     IS NOT NULL THEN 'downtime_event'
                                 WHEN capa_id               IS NOT NULL THEN 'capa'
                                 WHEN customer_complaint_id IS NOT NULL THEN 'customer_complaint'
                                 WHEN supplier_ncr_id       IS NOT NULL THEN 'supplier_ncr'
                                 WHEN kpi_actual_id         IS NOT NULL THEN 'kpi_actual'
                                 WHEN tier_meeting_id       IS NOT NULL THEN 'tier_meeting'
                                 WHEN work_order_id         IS NOT NULL THEN 'work_order'
                                 ELSE 'standalone'
                               END
                             ) STORED,

      CONSTRAINT action_items_single_source CHECK (
        (quality_issue_id      IS NOT NULL)::int +
        (safety_incident_id    IS NOT NULL)::int +
        (safety_observation_id IS NOT NULL)::int +
        (downtime_event_id     IS NOT NULL)::int +
        (capa_id               IS NOT NULL)::int +
        (customer_complaint_id IS NOT NULL)::int +
        (supplier_ncr_id       IS NOT NULL)::int +
        (kpi_actual_id         IS NOT NULL)::int +
        (tier_meeting_id       IS NOT NULL)::int +
        (work_order_id         IS NOT NULL)::int <= 1
      ),
      CONSTRAINT action_items_done_has_time
        CHECK (status NOT IN ('done', 'cancelled') OR completed_at IS NOT NULL),
      CONSTRAINT action_items_escalation_consistent
        CHECK ((escalated_to_org_unit_id IS NULL) = (escalated_at IS NULL))
    )
  `);

  // The index behind the screen this table exists for: everything still open on
  // my line, worst first.
  pgm.sql(`
    CREATE INDEX action_items_open_idx
      ON action_items (org_unit_id, due_date, priority)
      WHERE status IN ('open', 'in_progress', 'blocked')
  `);
  pgm.sql(`
    CREATE INDEX action_items_owner_idx
      ON action_items (owner_employee_id, due_date)
      WHERE status IN ('open', 'in_progress', 'blocked')
  `);
  pgm.sql('CREATE INDEX action_items_pillar_idx ON action_items (pillar_code, raised_at DESC)');
  pgm.sql('CREATE INDEX action_items_capa_idx ON action_items (capa_id)');
  pgm.sql('CREATE INDEX action_items_quality_issue_idx ON action_items (quality_issue_id)');
  pgm.sql('CREATE INDEX action_items_safety_incident_idx ON action_items (safety_incident_id)');
  pgm.sql('CREATE INDEX action_items_downtime_idx ON action_items (downtime_event_id)');
  pgm.sql('CREATE INDEX action_items_kpi_actual_idx ON action_items (kpi_actual_id)');
  pgm.sql('CREATE INDEX action_items_tier_meeting_idx ON action_items (tier_meeting_id)');
  pgm.sql(`
    CREATE INDEX action_items_work_order_idx
      ON action_items (work_order_id)
      WHERE work_order_id IS NOT NULL
  `);

  pgm.sql(`SELECT attach_updated_at('sqdcp_pillars')`);
  pgm.sql(`SELECT attach_updated_at('kpi_definitions')`);
  pgm.sql(`SELECT attach_updated_at('kpi_targets')`);
  pgm.sql(`SELECT attach_updated_at('tier_meetings')`);
  pgm.sql(`SELECT attach_updated_at('kpi_actuals')`);
  pgm.sql(`SELECT attach_updated_at('action_items')`);

  // ============================================================================
  // Application users and their scope.
  //
  // `app_users` is separate from `employees` because they answer different
  // questions. Every person who logs in is a user; not every employee has a
  // login, and some users — a corporate quality manager, an integration account —
  // are not employees of this site at all. The optional link between them is what
  // lets an action assigned to an employee show up in that person's own list.
  //
  // Authentication itself is deliberately not designed here. There is no
  // password column: `external_subject` is the hook for the identity provider,
  // per ADR-0002.
  //
  // `app_user_org_units` scopes what a user sees and what they may write. A
  // grant on an org unit covers everything beneath it, so giving a line leader
  // their line is one row, not one row per work centre.
  // ============================================================================
  pgm.sql(`
    CREATE TABLE app_users (
      id               BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      email            CITEXT      NOT NULL UNIQUE,
      display_name     TEXT        NOT NULL,
      employee_id      BIGINT      UNIQUE REFERENCES employees (id),
      role             TEXT        NOT NULL DEFAULT 'operator'
                                   CHECK (role IN ('operator', 'supervisor', 'engineer',
                                                   'manager', 'admin')),
      external_subject TEXT        UNIQUE,
      is_active        BOOLEAN     NOT NULL DEFAULT TRUE,
      last_login_at    TIMESTAMPTZ,
      created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by       BIGINT,
      updated_by       BIGINT
    )
  `);

  pgm.sql(`
    CREATE TABLE app_user_org_units (
      id          BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      app_user_id BIGINT      NOT NULL REFERENCES app_users (id) ON DELETE CASCADE,
      org_unit_id BIGINT      NOT NULL REFERENCES org_units (id) ON DELETE CASCADE,
      can_write   BOOLEAN     NOT NULL DEFAULT FALSE,
      created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by  BIGINT,
      updated_by  BIGINT,

      CONSTRAINT app_user_org_units_unique UNIQUE (app_user_id, org_unit_id)
    )
  `);

  pgm.sql(`
    CREATE INDEX app_user_org_units_user_idx
      ON app_user_org_units (app_user_id)
  `);

  pgm.sql(`SELECT attach_updated_at('app_users')`);
  pgm.sql(`SELECT attach_updated_at('app_user_org_units')`);

  // ============================================================================
  // Views: the reporting layer for the board.
  //
  // Every formula lives here and only here. The alternative — computing OEE in
  // the API, again in a report, and a third time in a spreadsheet somebody keeps
  // on their desktop — is how a plant ends up with three different OEE numbers
  // and an argument about which is right.
  //
  // ----------------------------------------------------------------------------
  // A note on how downtime is attributed.
  //
  // A stop that begins at 05:50 and ends at 06:30 belongs partly to the night
  // shift and partly to the day shift. These views therefore join downtime to
  // shift instances by *time overlap* and clip the interval to the shift window,
  // rather than by the stored shift_instance_id — which records where the stop
  // began and would hand all forty minutes to whichever shift was unlucky enough
  // to be running when it started.
  //
  // Production counts are attributed by their shift_instance_id instead, on the
  // assumption that a count period does not straddle a shift boundary. It is the
  // API's job to close the bucket at the end of a shift; a count period that
  // spans two shifts cannot be split honestly without assuming an even rate.
  // ============================================================================

  // ==========================================================================
  // Building blocks
  // ==========================================================================

  // Downtime minutes per shift instance and asset, clipped to the shift window
  // and split into the planned part (which is removed from planned production
  // time) and the unplanned part (which costs availability).
  pgm.sql(`
    CREATE VIEW v_shift_downtime AS
    SELECT
      si.id                                       AS shift_instance_id,
      de.asset_id,
      SUM(
        CASE WHEN dr.is_planned THEN
          EXTRACT(EPOCH FROM (
            LEAST(COALESCE(de.ended_at, si.ends_at), si.ends_at)
            - GREATEST(de.started_at, si.starts_at)
          )) / 60.0
        ELSE 0 END
      )                                           AS planned_downtime_minutes,
      SUM(
        CASE WHEN dr.is_planned IS NOT TRUE THEN
          EXTRACT(EPOCH FROM (
            LEAST(COALESCE(de.ended_at, si.ends_at), si.ends_at)
            - GREATEST(de.started_at, si.starts_at)
          )) / 60.0
        ELSE 0 END
      )                                           AS unplanned_downtime_minutes,
      COUNT(*) FILTER (WHERE dr.is_planned IS NOT TRUE) AS unplanned_stop_count,
      COUNT(*) FILTER (WHERE de.downtime_reason_id IS NULL) AS unclassified_stop_count
    FROM shift_instances si
    JOIN org_units line ON line.id = si.org_unit_id
    JOIN downtime_events de ON TRUE
    JOIN org_units deu ON deu.id = de.org_unit_id AND deu.path <@ line.path
    LEFT JOIN downtime_reasons dr ON dr.id = de.downtime_reason_id
    WHERE si.status <> 'cancelled'
      AND tstzrange(de.started_at, COALESCE(de.ended_at, now()), '[)')
          && tstzrange(si.starts_at, si.ends_at, '[)')
    GROUP BY si.id, de.asset_id
  `);

  // Output per shift instance and asset, with the theoretical running time the
  // same output would have taken at ideal cycle. That second number is the
  // numerator of the OEE performance factor and is why cycle times have to be
  // versioned: it is evaluated at the production date, not today.
  pgm.sql(`
    CREATE VIEW v_shift_output AS
    SELECT
      pc.shift_instance_id,
      pc.asset_id,
      SUM(pc.good_quantity)   AS good_quantity,
      SUM(pc.reject_quantity) AS reject_quantity,
      SUM(pc.rework_quantity) AS rework_quantity,
      SUM(pc.total_quantity)  AS total_quantity,
      SUM(
        ideal_cycle_seconds(pr.product_id, pc.asset_id, si.production_date)
        * pc.total_quantity
      ) / 60.0               AS theoretical_minutes
    FROM production_counts pc
    JOIN production_runs pr ON pr.id = pc.production_run_id
    JOIN shift_instances si ON si.id = pc.shift_instance_id
    WHERE pc.shift_instance_id IS NOT NULL
    GROUP BY pc.shift_instance_id, pc.asset_id
  `);

  // ==========================================================================
  // OEE
  //
  //   Planned Production Time = shift planned minutes - planned downtime
  //   Run Time                = Planned Production Time - unplanned downtime
  //   Availability            = Run Time / Planned Production Time
  //   Performance             = theoretical minutes for the output / Run Time
  //   Quality                 = good / total          (i.e. first pass yield)
  //   OEE                     = A x P x Q
  //
  // Performance is NOT capped at 1.0. A value above 100% is not a good day: it
  // means the cycle time on record is wrong, or output was counted twice, and
  // capping it silently would hide a data problem behind a flattering number.
  // `performance_suspect` surfaces it instead.
  // ==========================================================================
  pgm.sql(`
    CREATE VIEW v_shift_oee AS
    WITH base AS (
      SELECT
        si.id                AS shift_instance_id,
        si.org_unit_id,
        si.production_date,
        si.shift_definition_id,
        si.crew_id,
        a.id                 AS asset_id,
        a.code               AS asset_code,
        a.name               AS asset_name,
        si.planned_production_minutes::numeric AS shift_planned_minutes,
        COALESCE(d.planned_downtime_minutes, 0)   AS planned_downtime_minutes,
        COALESCE(d.unplanned_downtime_minutes, 0) AS unplanned_downtime_minutes,
        COALESCE(d.unplanned_stop_count, 0)       AS unplanned_stop_count,
        COALESCE(o.good_quantity, 0)              AS good_quantity,
        COALESCE(o.reject_quantity, 0)            AS reject_quantity,
        COALESCE(o.rework_quantity, 0)            AS rework_quantity,
        COALESCE(o.total_quantity, 0)             AS total_quantity,
        COALESCE(o.theoretical_minutes, 0)        AS theoretical_minutes
      FROM shift_instances si
      JOIN org_units line ON line.id = si.org_unit_id
      JOIN org_units au   ON au.path <@ line.path
      JOIN assets a       ON a.org_unit_id = au.id
      LEFT JOIN v_shift_downtime d ON d.shift_instance_id = si.id AND d.asset_id = a.id
      LEFT JOIN v_shift_output   o ON o.shift_instance_id = si.id AND o.asset_id = a.id
      WHERE si.status <> 'cancelled'
    ),
    timed AS (
      SELECT
        base.*,
        GREATEST(shift_planned_minutes - planned_downtime_minutes, 0) AS planned_production_minutes,
        GREATEST(shift_planned_minutes - planned_downtime_minutes
                 - unplanned_downtime_minutes, 0)                     AS run_minutes
      FROM base
    )
    SELECT
      timed.*,
      CASE WHEN planned_production_minutes > 0
           THEN run_minutes / planned_production_minutes END AS availability,
      CASE WHEN run_minutes > 0
           THEN theoretical_minutes / run_minutes       END AS performance,
      CASE WHEN total_quantity > 0
           THEN good_quantity / total_quantity          END AS quality,
      CASE WHEN planned_production_minutes > 0 AND run_minutes > 0 AND total_quantity > 0
           THEN (run_minutes / planned_production_minutes)
              * (theoretical_minutes / run_minutes)
              * (good_quantity / total_quantity)        END AS oee,
      (run_minutes > 0 AND theoretical_minutes > run_minutes) AS performance_suspect
    FROM timed
  `);

  // ==========================================================================
  // Delivery
  // ==========================================================================

  pgm.sql(`
    CREATE VIEW v_downtime_pareto AS
    SELECT
      de.org_unit_id,
      si.production_date,
      dr.id                                AS downtime_reason_id,
      dr.code                              AS reason_code,
      dr.name                              AS reason_name,
      dr.loss_category,
      dr.is_planned,
      COUNT(*)                             AS stop_count,
      SUM(de.duration_minutes)             AS downtime_minutes
    FROM downtime_events de
    LEFT JOIN downtime_reasons dr ON dr.id = de.downtime_reason_id
    LEFT JOIN shift_instances si  ON si.id = de.shift_instance_id
    WHERE de.ended_at IS NOT NULL
    GROUP BY de.org_unit_id, si.production_date, dr.id, dr.code, dr.name,
             dr.loss_category, dr.is_planned
  `);

  // On-time delivery, measured against the promise made to the customer rather
  // than the internal due date. An order with no promised date is excluded
  // rather than counted as on time — an unmeasurable order should not flatter
  // the number.
  pgm.sql(`
    CREATE VIEW v_otd AS
    WITH completed AS (
      SELECT
        po.org_unit_id,
        po.customer_id,
        po.promised_date,
        -- Plant-local, not session-local. See plant_date().
        plant_date(po.org_unit_id, po.completed_at) AS completion_date
      FROM production_orders po
      WHERE po.status = 'completed'
        AND po.completed_at IS NOT NULL
        AND po.promised_date IS NOT NULL
    )
    SELECT
      org_unit_id,
      completion_date,
      customer_id,
      COUNT(*)                                                      AS orders_completed,
      COUNT(*) FILTER (WHERE completion_date <= promised_date)       AS orders_on_time,
      COUNT(*) FILTER (WHERE completion_date >  promised_date)       AS orders_late,
      AVG(GREATEST(completion_date - promised_date, 0))              AS avg_days_late,
      100.0 * COUNT(*) FILTER (WHERE completion_date <= promised_date)
            / NULLIF(COUNT(*), 0)                                    AS otd_percent
    FROM completed
    GROUP BY org_unit_id, completion_date, customer_id
  `);

  // ==========================================================================
  // Quality
  // ==========================================================================

  // Internal PPM against units produced, and customer PPM against the same
  // denominator. The customer figure should properly use quantity shipped;
  // there is no shipping module, so this is stated plainly in the KPI's
  // formula_text rather than hidden.
  pgm.sql(`
    CREATE VIEW v_quality_ppm AS
    WITH produced AS (
      SELECT si.org_unit_id, si.production_date, SUM(pc.total_quantity) AS total_quantity
      FROM production_counts pc
      JOIN shift_instances si ON si.id = pc.shift_instance_id
      GROUP BY si.org_unit_id, si.production_date
    ),
    internal AS (
      SELECT si.org_unit_id, si.production_date,
             SUM(pc.reject_quantity + pc.rework_quantity) AS defective_quantity
      FROM production_counts pc
      JOIN shift_instances si ON si.id = pc.shift_instance_id
      GROUP BY si.org_unit_id, si.production_date
    ),
    complaints AS (
      SELECT cc.org_unit_id,
             plant_date(cc.org_unit_id, cc.received_at) AS production_date,
             SUM(COALESCE(cc.quantity_affected, 0))     AS complaint_quantity,
             COUNT(*)                                   AS complaint_count
      FROM customer_complaints cc
      WHERE cc.status <> 'rejected'
        AND cc.org_unit_id IS NOT NULL
      GROUP BY cc.org_unit_id, plant_date(cc.org_unit_id, cc.received_at)
    )
    SELECT
      p.org_unit_id,
      p.production_date,
      p.total_quantity,
      COALESCE(i.defective_quantity, 0)  AS defective_quantity,
      COALESCE(c.complaint_quantity, 0)  AS complaint_quantity,
      COALESCE(c.complaint_count, 0)     AS complaint_count,
      1000000.0 * COALESCE(i.defective_quantity, 0) / NULLIF(p.total_quantity, 0) AS internal_ppm,
      1000000.0 * COALESCE(c.complaint_quantity, 0) / NULLIF(p.total_quantity, 0) AS customer_ppm,
      100.0 * (p.total_quantity - COALESCE(i.defective_quantity, 0))
            / NULLIF(p.total_quantity, 0)                                          AS first_pass_yield_percent
    FROM produced p
    LEFT JOIN internal   i ON i.org_unit_id = p.org_unit_id AND i.production_date = p.production_date
    LEFT JOIN complaints c ON c.org_unit_id = p.org_unit_id AND c.production_date = p.production_date
  `);

  // ==========================================================================
  // Cost — derived entirely from events and versioned rates
  // ==========================================================================

  pgm.sql(`
    CREATE VIEW v_cost_of_poor_quality AS
    WITH issues AS (
      -- The shift instance's production_date is the right bucket when there is
      -- one; plant_date is the fallback for an issue raised outside a shift.
      SELECT
        qi.id, qi.org_unit_id, qi.asset_id, qi.product_id,
        COALESCE(si.production_date, plant_date(qi.org_unit_id, qi.detected_at)) AS cost_date
      FROM quality_issues qi
      LEFT JOIN shift_instances si ON si.id = qi.shift_instance_id
    ),
    scrap AS (
      SELECT
        i.org_unit_id,
        i.cost_date,
        SUM(qd.quantity * COALESCE(product_standard_cost(i.product_id, i.cost_date), 0))
          AS scrap_cost
      FROM quality_dispositions qd
      JOIN issues i ON i.id = qd.quality_issue_id
      WHERE qd.disposition_type = 'scrap'
      GROUP BY i.org_unit_id, i.cost_date
    ),
    rework AS (
      SELECT
        i.org_unit_id,
        i.cost_date,
        SUM(
          qd.rework_minutes / 60.0
          * COALESCE(
              resolve_cost_rate(i.org_unit_id, i.asset_id, 'rework_labor_per_hour', i.cost_date),
              resolve_cost_rate(i.org_unit_id, i.asset_id, 'labor_per_hour', i.cost_date),
              0)
        ) AS rework_cost
      FROM quality_dispositions qd
      JOIN issues i ON i.id = qd.quality_issue_id
      WHERE qd.disposition_type = 'rework'
      GROUP BY i.org_unit_id, i.cost_date
    ),
    claims AS (
      SELECT cc.org_unit_id,
             plant_date(cc.org_unit_id, cc.received_at) AS cost_date,
             SUM(COALESCE(cc.claim_cost, 0))            AS claim_cost
      FROM customer_complaints cc
      WHERE cc.org_unit_id IS NOT NULL
      GROUP BY cc.org_unit_id, plant_date(cc.org_unit_id, cc.received_at)
    ),
    recovered AS (
      SELECT sn.org_unit_id,
             plant_date(sn.org_unit_id, sn.detected_at) AS cost_date,
             SUM(COALESCE(sn.cost_recovered, 0))        AS supplier_recovery
      FROM supplier_ncrs sn
      WHERE sn.org_unit_id IS NOT NULL
      GROUP BY sn.org_unit_id, plant_date(sn.org_unit_id, sn.detected_at)
    ),
    dates AS (
      SELECT org_unit_id, cost_date FROM scrap
      UNION SELECT org_unit_id, cost_date FROM rework
      UNION SELECT org_unit_id, cost_date FROM claims
      UNION SELECT org_unit_id, cost_date FROM recovered
    )
    SELECT
      d.org_unit_id,
      d.cost_date,
      COALESCE(s.scrap_cost, 0)          AS scrap_cost,
      COALESCE(r.rework_cost, 0)         AS rework_cost,
      COALESCE(c.claim_cost, 0)          AS claim_cost,
      COALESCE(v.supplier_recovery, 0)   AS supplier_recovery,
      COALESCE(s.scrap_cost, 0) + COALESCE(r.rework_cost, 0) + COALESCE(c.claim_cost, 0)
        - COALESCE(v.supplier_recovery, 0) AS total_copq
    FROM dates d
    LEFT JOIN scrap     s ON s.org_unit_id = d.org_unit_id AND s.cost_date = d.cost_date
    LEFT JOIN rework    r ON r.org_unit_id = d.org_unit_id AND r.cost_date = d.cost_date
    LEFT JOIN claims    c ON c.org_unit_id = d.org_unit_id AND c.cost_date = d.cost_date
    LEFT JOIN recovered v ON v.org_unit_id = d.org_unit_id AND v.cost_date = d.cost_date
  `);

  pgm.sql(`
    CREATE VIEW v_downtime_cost AS
    SELECT
      de.org_unit_id,
      si.production_date,
      SUM(de.duration_minutes) / 60.0 AS unplanned_downtime_hours,
      SUM(
        de.duration_minutes / 60.0
        * COALESCE(resolve_cost_rate(de.org_unit_id, de.asset_id,
                                     'machine_downtime_per_hour', si.production_date), 0)
      ) AS downtime_cost
    FROM downtime_events de
    JOIN shift_instances si ON si.id = de.shift_instance_id
    LEFT JOIN downtime_reasons dr ON dr.id = de.downtime_reason_id
    WHERE de.ended_at IS NOT NULL
      AND dr.is_planned IS NOT TRUE
    GROUP BY de.org_unit_id, si.production_date
  `);

  pgm.sql(`
    CREATE VIEW v_labour_cost AS
    SELECT
      si.org_unit_id,
      si.production_date,
      SUM(ar.worked_minutes) / 60.0    AS worked_hours,
      SUM(ar.overtime_minutes) / 60.0  AS overtime_hours,
      SUM(
        (ar.worked_minutes - ar.overtime_minutes) / 60.0
        * COALESCE(resolve_cost_rate(si.org_unit_id, NULL, 'labor_per_hour', si.production_date), 0)
        + ar.overtime_minutes / 60.0
        * COALESCE(resolve_cost_rate(si.org_unit_id, NULL, 'labor_per_hour', si.production_date), 0)
        * COALESCE(resolve_cost_rate(si.org_unit_id, NULL,
                                     'overtime_premium_multiplier', si.production_date), 1)
      ) AS labour_cost
    FROM attendance_records ar
    JOIN shift_instances si ON si.id = ar.shift_instance_id
    GROUP BY si.org_unit_id, si.production_date
  `);

  // ==========================================================================
  // Safety
  //
  // TRIR is per 200,000 hours (100 full-time equivalents for a year, the OSHA
  // convention); LTIFR is per 1,000,000 hours (the ILO convention). Both are
  // included because which one a plant reports depends on where it is, and
  // reporting one as the other is a factor-of-five error.
  // ==========================================================================
  pgm.sql(`
    CREATE VIEW v_safety_rates AS
    WITH hours AS (
      SELECT si.org_unit_id, si.production_date, SUM(ar.worked_minutes) / 60.0 AS worked_hours
      FROM attendance_records ar
      JOIN shift_instances si ON si.id = ar.shift_instance_id
      GROUP BY si.org_unit_id, si.production_date
    ),
    incidents AS (
      SELECT
        sn.org_unit_id,
        si.production_date,
        COUNT(*)                                                        AS incident_count,
        COUNT(*) FILTER (WHERE sn.is_recordable)                        AS recordable_count,
        COUNT(*) FILTER (WHERE sn.severity_level IN ('lost_time','fatality')) AS lost_time_count,
        COUNT(*) FILTER (WHERE sn.severity_level = 'near_miss')         AS near_miss_count,
        SUM(sn.lost_time_days)                                          AS lost_days
      FROM safety_incidents sn
      JOIN shift_instances si ON si.id = sn.shift_instance_id
      GROUP BY sn.org_unit_id, si.production_date
    ),
    observations AS (
      SELECT so.org_unit_id, si.production_date,
             COUNT(*) AS observation_count,
             COUNT(*) FILTER (WHERE so.is_stop_work) AS stop_work_count
      FROM safety_observations so
      JOIN shift_instances si ON si.id = so.shift_instance_id
      GROUP BY so.org_unit_id, si.production_date
    )
    SELECT
      h.org_unit_id,
      h.production_date,
      h.worked_hours,
      COALESCE(i.incident_count, 0)     AS incident_count,
      COALESCE(i.recordable_count, 0)   AS recordable_count,
      COALESCE(i.lost_time_count, 0)    AS lost_time_count,
      COALESCE(i.near_miss_count, 0)    AS near_miss_count,
      COALESCE(i.lost_days, 0)          AS lost_days,
      COALESCE(o.observation_count, 0)  AS observation_count,
      COALESCE(o.stop_work_count, 0)    AS stop_work_count,
      200000.0  * COALESCE(i.recordable_count, 0) / NULLIF(h.worked_hours, 0) AS trir,
      1000000.0 * COALESCE(i.lost_time_count, 0)  / NULLIF(h.worked_hours, 0) AS ltifr
    FROM hours h
    LEFT JOIN incidents    i ON i.org_unit_id = h.org_unit_id AND i.production_date = h.production_date
    LEFT JOIN observations o ON o.org_unit_id = h.org_unit_id AND o.production_date = h.production_date
  `);

  // ==========================================================================
  // People
  // ==========================================================================

  pgm.sql(`
    CREATE VIEW v_attendance_rate AS
    SELECT
      si.org_unit_id,
      si.production_date,
      COUNT(*)                                                       AS scheduled_headcount,
      COUNT(*) FILTER (WHERE ar.attendance_status IN ('present','late','training'))
                                                                     AS present_headcount,
      COUNT(*) FILTER (WHERE ar.attendance_status = 'late')           AS late_headcount,
      COUNT(*) FILTER (WHERE ab.counts_as_absenteeism)                AS absent_headcount,
      SUM(ar.worked_minutes) / 60.0                                   AS worked_hours,
      SUM(ar.overtime_minutes) / 60.0                                 AS overtime_hours,
      100.0 * COUNT(*) FILTER (WHERE ab.counts_as_absenteeism)
            / NULLIF(COUNT(*), 0)                                     AS absenteeism_percent
    FROM attendance_records ar
    JOIN shift_instances si ON si.id = ar.shift_instance_id
    LEFT JOIN absence_reasons ab ON ab.id = ar.absence_reason_id
    WHERE ar.attendance_status <> 'not_scheduled'
    GROUP BY si.org_unit_id, si.production_date
  `);

  // Qualified headcount against requirement, per unit and skill. An expired
  // certification does not count as qualified, which is the whole reason the
  // expiry date is maintained.
  pgm.sql(`
    CREATE VIEW v_skill_coverage AS
    SELECT
      sr.org_unit_id,
      sr.skill_id,
      sk.code                              AS skill_code,
      sk.name                              AS skill_name,
      sr.minimum_level,
      sr.minimum_qualified_headcount,
      COUNT(es.id) FILTER (
        WHERE es.proficiency_level >= sr.minimum_level
          AND (es.expires_on IS NULL OR es.expires_on > CURRENT_DATE)
      )                                    AS qualified_headcount,
      COUNT(es.id) FILTER (
        WHERE es.proficiency_level >= sr.minimum_level
          AND es.expires_on IS NOT NULL
          AND es.expires_on <= CURRENT_DATE
      )                                    AS expired_headcount,
      GREATEST(
        sr.minimum_qualified_headcount - COUNT(es.id) FILTER (
          WHERE es.proficiency_level >= sr.minimum_level
            AND (es.expires_on IS NULL OR es.expires_on > CURRENT_DATE)
        ), 0
      )                                    AS shortfall
    FROM skill_requirements sr
    JOIN skills sk ON sk.id = sr.skill_id
    JOIN org_units req ON req.id = sr.org_unit_id
    LEFT JOIN employees e
      ON e.is_active
     AND EXISTS (
           SELECT 1
             FROM employee_assignments ea
             JOIN org_units eau ON eau.id = ea.org_unit_id
            WHERE ea.employee_id = e.id
              AND eau.path <@ req.path
              AND ea.effective_from <= CURRENT_DATE
              AND (ea.effective_to IS NULL OR ea.effective_to > CURRENT_DATE)
         )
    LEFT JOIN employee_skills es ON es.employee_id = e.id AND es.skill_id = sr.skill_id
    GROUP BY sr.org_unit_id, sr.skill_id, sk.code, sk.name,
             sr.minimum_level, sr.minimum_qualified_headcount
  `);

  // ==========================================================================
  // The board
  // ==========================================================================

  pgm.sql(`
    CREATE VIEW v_sqdcp_board AS
    SELECT
      ka.id                     AS kpi_actual_id,
      ka.org_unit_id,
      ou.code                   AS org_unit_code,
      ou.name                   AS org_unit_name,
      p.code                    AS pillar_code,
      p.name                    AS pillar_name,
      p.sort_order              AS pillar_sort_order,
      kd.id                     AS kpi_definition_id,
      kd.code                   AS kpi_code,
      kd.name                   AS kpi_name,
      kd.unit,
      kd.direction,
      kd.decimal_places,
      kd.formula_text,
      ka.period_type,
      ka.period_start,
      ka.period_end,
      ka.actual_value,
      ka.target_value_snapshot  AS target_value,
      ka.status,
      ka.comment,
      (
        SELECT COUNT(*)
          FROM action_items ai
         WHERE ai.kpi_actual_id = ka.id
           AND ai.status IN ('open', 'in_progress', 'blocked')
      )                         AS open_action_count
    FROM kpi_actuals ka
    JOIN kpi_definitions kd ON kd.id = ka.kpi_definition_id
    JOIN sqdcp_pillars   p  ON p.code = kd.pillar_code
    JOIN org_units       ou ON ou.id = ka.org_unit_id
  `);

  // Every open action on a unit and everything beneath it, whatever raised it.
  // This is the screen the action_items table exists for.
  pgm.sql(`
    CREATE VIEW v_open_actions AS
    SELECT
      ai.id,
      ai.action_no,
      ai.title,
      ai.pillar_code,
      ai.source_type,
      ai.org_unit_id,
      ou.code                   AS org_unit_code,
      ou.path                   AS org_unit_path,
      ai.action_type,
      ai.priority,
      ai.status,
      ai.due_date,
      (ai.due_date IS NOT NULL AND ai.due_date < CURRENT_DATE) AS is_overdue,
      CURRENT_DATE - ai.due_date AS days_overdue,
      ai.owner_employee_id,
      e.display_name            AS owner_name,
      ai.raised_at,
      ai.escalated_to_org_unit_id
    FROM action_items ai
    JOIN org_units ou ON ou.id = ai.org_unit_id
    LEFT JOIN employees e ON e.id = ai.owner_employee_id
    WHERE ai.status IN ('open', 'in_progress', 'blocked')
  `);

  // ==========================================================================
  // Materialised rollups
  //
  // v_shift_oee walks the asset tree and clips every downtime interval, which
  // is fine for one day and slow for a year of trend charts. These are
  // refreshed nightly by refresh_sqdcp_rollups().
  // ==========================================================================
  pgm.sql(`
    CREATE MATERIALIZED VIEW mv_daily_oee AS
    SELECT
      org_unit_id,
      production_date,
      SUM(planned_production_minutes)  AS planned_production_minutes,
      SUM(run_minutes)                 AS run_minutes,
      SUM(planned_downtime_minutes)    AS planned_downtime_minutes,
      SUM(unplanned_downtime_minutes)  AS unplanned_downtime_minutes,
      SUM(unplanned_stop_count)        AS unplanned_stop_count,
      SUM(good_quantity)               AS good_quantity,
      SUM(reject_quantity)             AS reject_quantity,
      SUM(rework_quantity)             AS rework_quantity,
      SUM(total_quantity)              AS total_quantity,
      SUM(theoretical_minutes)         AS theoretical_minutes,
      CASE WHEN SUM(planned_production_minutes) > 0
           THEN SUM(run_minutes) / SUM(planned_production_minutes) END AS availability,
      CASE WHEN SUM(run_minutes) > 0
           THEN SUM(theoretical_minutes) / SUM(run_minutes)         END AS performance,
      CASE WHEN SUM(total_quantity) > 0
           THEN SUM(good_quantity) / SUM(total_quantity)            END AS quality,
      CASE WHEN SUM(planned_production_minutes) > 0
                AND SUM(run_minutes) > 0
                AND SUM(total_quantity) > 0
           THEN (SUM(run_minutes) / SUM(planned_production_minutes))
              * (SUM(theoretical_minutes) / SUM(run_minutes))
              * (SUM(good_quantity) / SUM(total_quantity))          END AS oee
    FROM v_shift_oee
    GROUP BY org_unit_id, production_date
  `);

  // REFRESH ... CONCURRENTLY needs a unique index, and without it the refresh
  // takes an exclusive lock that blocks every board query while it runs.
  pgm.sql(`
    CREATE UNIQUE INDEX mv_daily_oee_pk
      ON mv_daily_oee (org_unit_id, production_date)
  `);

  pgm.sql(`
    CREATE OR REPLACE FUNCTION refresh_sqdcp_rollups()
    RETURNS VOID
    LANGUAGE plpgsql
    AS $$
    BEGIN
      REFRESH MATERIALIZED VIEW CONCURRENTLY mv_daily_oee;
    END;
    $$
  `);

  // ============================================================================
  // Reference data.
  //
  // Every insert is ON CONFLICT DO NOTHING, so re-running migrations is safe and
  // a plant that has renamed or deactivated a seeded row keeps its change.
  //
  // This is the global catalogue per ADR-0005: KPI definitions, downtime
  // reasons, defect codes, injury types, units of measure and absence reasons,
  // identical at every Site. Job roles, skills and failure codes are NOT seeded
  // here — they are entered per deployment, because "technician" and a plant's
  // skill vocabulary mean different things at different Sites in a way a shared
  // downtime reason or defect code does not.
  //
  // The downtime reason tree and the defect code tree are the two structures
  // that decide whether the Pareto charts are ever actionable, and both are
  // painful to restructure once a year of events points at them. They are
  // starting points, not doctrine: every one of these is expected to be edited
  // to match the plant — the codes and the loss categories are what the queries
  // depend on, not the names.
  // ============================================================================

  // --------------------------------------------------------------------------
  // Units of measure. Base units reference themselves, which a self-referencing
  // foreign key permits within a single row insert.
  // --------------------------------------------------------------------------
  pgm.sql(`
    INSERT INTO units_of_measure (code, name, dimension, base_uom_code, factor_to_base) VALUES
      ('EA',  'Each',        'count',  'EA', 1),
      ('KG',  'Kilogram',    'mass',   'KG', 1),
      ('M',   'Metre',       'length', 'M',  1),
      ('L',   'Litre',       'volume', 'L',  1),
      ('M2',  'Square metre','area',   'M2', 1),
      ('MIN', 'Minute',      'time',   'MIN',1)
    ON CONFLICT (code) DO NOTHING
  `);

  pgm.sql(`
    INSERT INTO units_of_measure (code, name, dimension, base_uom_code, factor_to_base) VALUES
      ('BOX', 'Box',        'count',  'EA',  1),
      ('PLT', 'Pallet',     'count',  'EA',  1),
      ('G',   'Gram',       'mass',   'KG',  0.001),
      ('T',   'Tonne',      'mass',   'KG',  1000),
      ('MM',  'Millimetre', 'length', 'M',   0.001),
      ('CM',  'Centimetre', 'length', 'M',   0.01),
      ('ML',  'Millilitre', 'volume', 'L',   0.001),
      ('H',   'Hour',       'time',   'MIN', 60)
    ON CONFLICT (code) DO NOTHING
  `);

  // --------------------------------------------------------------------------
  // SQDCP pillars
  // --------------------------------------------------------------------------
  pgm.sql(`
    INSERT INTO sqdcp_pillars (code, name, description, sort_order, color) VALUES
      ('S', 'Safety',   'Injuries, near misses and the observations that precede them', 1, '#c0392b'),
      ('Q', 'Quality',  'Defects, non-conformances and the cost of getting it wrong',   2, '#8e44ad'),
      ('D', 'Delivery', 'Output, equipment effectiveness and on-time delivery',         3, '#2980b9'),
      ('C', 'Cost',     'Cost of poor quality, downtime and labour',                    4, '#27ae60'),
      ('P', 'People',   'Attendance, skills coverage and improvement engagement',       5, '#d35400')
    ON CONFLICT (code) DO NOTHING
  `);

  // --------------------------------------------------------------------------
  // Downtime reasons: the six big losses, plus the two categories that sit
  // outside OEE. Level 1 first, then the leaves that point at them.
  // --------------------------------------------------------------------------
  pgm.sql(`
    INSERT INTO downtime_reasons (code, name, loss_category, sort_order) VALUES
      ('BRK', 'Breakdown',              'breakdown',              1),
      ('SET', 'Setup and changeover',   'setup_and_adjustment',   2),
      ('MIN', 'Minor stops and idling', 'idling_and_minor_stops', 3),
      ('SPD', 'Reduced speed',          'reduced_speed',          4),
      ('QIP', 'Process defects',        'defects_in_process',     5),
      ('STU', 'Startup and yield loss', 'reduced_yield_startup',  6),
      ('PLN', 'Planned stop',           'planned_stop',           7),
      ('NSC', 'Not scheduled',          'not_scheduled',          8)
    ON CONFLICT (code) DO NOTHING
  `);

  pgm.sql(`
    INSERT INTO downtime_reasons (parent_id, code, name, loss_category, requires_comment, sort_order)
    SELECT p.id, v.code, v.name, v.loss_category, v.requires_comment, v.sort_order
    FROM (VALUES
      ('BRK', 'BRK-MECH',  'Mechanical failure',            'breakdown',              FALSE, 1),
      ('BRK', 'BRK-ELEC',  'Electrical failure',            'breakdown',              FALSE, 2),
      ('BRK', 'BRK-HYD',   'Hydraulic or pneumatic failure','breakdown',              FALSE, 3),
      ('BRK', 'BRK-TOOL',  'Tool or die breakage',          'breakdown',              FALSE, 4),
      ('BRK', 'BRK-CTRL',  'Control system fault',          'breakdown',              FALSE, 5),
      ('BRK', 'BRK-OTH',   'Other breakdown',               'breakdown',              TRUE,  99),

      ('SET', 'SET-CO',    'Product changeover',            'setup_and_adjustment',   FALSE, 1),
      ('SET', 'SET-ADJ',   'Adjustment and first-off check','setup_and_adjustment',   FALSE, 2),
      ('SET', 'SET-CLEAN', 'Cleaning between products',     'setup_and_adjustment',   FALSE, 3),
      ('SET', 'SET-TOOL',  'Tool change',                   'setup_and_adjustment',   FALSE, 4),
      ('SET', 'SET-OTH',   'Other setup',                   'setup_and_adjustment',   TRUE,  99),

      ('MIN', 'MIN-JAM',   'Material jam',                  'idling_and_minor_stops', FALSE, 1),
      ('MIN', 'MIN-SENS',  'Sensor fault or false trip',    'idling_and_minor_stops', FALSE, 2),
      ('MIN', 'MIN-FEED',  'Feed or discharge blockage',    'idling_and_minor_stops', FALSE, 3),
      ('MIN', 'MIN-WAIT',  'Waiting for material',          'idling_and_minor_stops', FALSE, 4),
      ('MIN', 'MIN-OPER',  'No operator available',         'idling_and_minor_stops', FALSE, 5),
      ('MIN', 'MIN-UPSTR', 'Blocked or starved by adjacent process', 'idling_and_minor_stops', FALSE, 6),
      ('MIN', 'MIN-OTH',   'Other minor stop',              'idling_and_minor_stops', TRUE,  99),

      ('SPD', 'SPD-DERATE','Running below rated speed',     'reduced_speed',          TRUE,  1),
      ('SPD', 'SPD-WEAR',  'Tooling wear',                  'reduced_speed',          FALSE, 2),
      ('SPD', 'SPD-MAT',   'Material out of specification', 'reduced_speed',          FALSE, 3),

      ('QIP', 'QIP-REJ',   'In-process rejects',            'defects_in_process',     FALSE, 1),
      ('QIP', 'QIP-RWK',   'In-line rework',                'defects_in_process',     FALSE, 2),
      ('QIP', 'QIP-INSP',  'Additional inspection or sorting','defects_in_process',   FALSE, 3),

      ('STU', 'STU-WARM',  'Warm-up to temperature',        'reduced_yield_startup',  FALSE, 1),
      ('STU', 'STU-TRIAL', 'Trial run and settling',        'reduced_yield_startup',  FALSE, 2),

      ('PLN', 'PLN-BREAK', 'Scheduled break',               'planned_stop',           FALSE, 1),
      ('PLN', 'PLN-PM',    'Planned maintenance',           'planned_stop',           FALSE, 2),
      ('PLN', 'PLN-MEET',  'Meeting or training',           'planned_stop',           FALSE, 3),
      ('PLN', 'PLN-NODEM', 'No demand',                     'planned_stop',           FALSE, 4),
      ('PLN', 'PLN-TRIAL', 'Planned trial or development',  'planned_stop',           FALSE, 5),

      ('NSC', 'NSC-SHIFT', 'No shift scheduled',            'not_scheduled',          FALSE, 1),
      ('NSC', 'NSC-HOL',   'Holiday or shutdown',           'not_scheduled',          FALSE, 2)
    ) AS v (parent_code, code, name, loss_category, requires_comment, sort_order)
    JOIN downtime_reasons p ON p.code = v.parent_code
    ON CONFLICT (code) DO NOTHING
  `);

  // --------------------------------------------------------------------------
  // Defect codes
  // --------------------------------------------------------------------------
  pgm.sql(`
    INSERT INTO defect_codes (code, name, defect_category, default_severity, sort_order) VALUES
      ('DIM', 'Dimensional',   'product',       'major', 1),
      ('SUR', 'Surface',       'product',       'minor', 2),
      ('ASM', 'Assembly',      'product',       'major', 3),
      ('MAT', 'Material',      'material',      'major', 4),
      ('FUN', 'Functional',    'product',       'critical', 5),
      ('PRC', 'Process',       'process',       'major', 6),
      ('DOC', 'Documentation', 'documentation', 'minor', 7),
      ('PKG', 'Packaging',     'packaging',     'minor', 8)
    ON CONFLICT (code) DO NOTHING
  `);

  pgm.sql(`
    INSERT INTO defect_codes (parent_id, code, name, defect_category, default_severity, sort_order)
    SELECT p.id, v.code, v.name, v.defect_category, v.default_severity, v.sort_order
    FROM (VALUES
      ('DIM', 'DIM-OOT',   'Out of tolerance',            'product',       'major',    1),
      ('DIM', 'DIM-WARP',  'Warped or distorted',         'product',       'major',    2),
      ('DIM', 'DIM-FLAT',  'Flatness or straightness',    'product',       'major',    3),
      ('DIM', 'DIM-HOLE',  'Hole position or size',       'product',       'major',    4),

      ('SUR', 'SUR-SCR',   'Scratch',                     'product',       'minor',    1),
      ('SUR', 'SUR-DENT',  'Dent or impact mark',         'product',       'minor',    2),
      ('SUR', 'SUR-CONT',  'Contamination',               'product',       'major',    3),
      ('SUR', 'SUR-COL',   'Colour or finish variation',  'product',       'minor',    4),
      ('SUR', 'SUR-CORR',  'Corrosion',                   'product',       'major',    5),

      ('ASM', 'ASM-MISS',  'Missing component',           'product',       'critical', 1),
      ('ASM', 'ASM-WRONG', 'Wrong component fitted',      'product',       'critical', 2),
      ('ASM', 'ASM-LOOSE', 'Loose or under-torqued',      'product',       'critical', 3),
      ('ASM', 'ASM-ORIENT','Incorrect orientation',       'product',       'major',    4),

      ('MAT', 'MAT-POR',   'Porosity',                    'material',      'major',    1),
      ('MAT', 'MAT-CRACK', 'Crack',                       'material',      'critical', 2),
      ('MAT', 'MAT-INCL',  'Inclusion or foreign body',   'material',      'major',    3),
      ('MAT', 'MAT-SPEC',  'Material off specification',  'material',      'major',    4),

      ('FUN', 'FUN-LEAK',  'Leak',                        'product',       'critical', 1),
      ('FUN', 'FUN-ELEC',  'Electrical test failure',     'product',       'critical', 2),
      ('FUN', 'FUN-NOOP',  'Does not operate',            'product',       'critical', 3),
      ('FUN', 'FUN-PERF',  'Performance below specification','product',    'major',    4),

      ('PRC', 'PRC-PARAM', 'Process parameter out of range','process',     'major',    1),
      ('PRC', 'PRC-SETUP', 'Incorrect setup',             'process',       'major',    2),
      ('PRC', 'PRC-METHOD','Method not followed',         'process',       'major',    3),

      ('DOC', 'DOC-MISS',  'Missing record or certificate','documentation','minor',    1),
      ('DOC', 'DOC-ERR',   'Incorrect record',            'documentation', 'minor',    2),

      ('PKG', 'PKG-DAM',   'Damaged packaging',           'packaging',     'minor',    1),
      ('PKG', 'PKG-LABEL', 'Label incorrect or missing',  'packaging',     'major',    2),
      ('PKG', 'PKG-COUNT', 'Incorrect pack quantity',     'packaging',     'major',    3)
    ) AS v (parent_code, code, name, defect_category, default_severity, sort_order)
    JOIN defect_codes p ON p.code = v.parent_code
    ON CONFLICT (code) DO NOTHING
  `);

  // --------------------------------------------------------------------------
  // Absence reasons.
  //
  // Note where counts_as_absenteeism is FALSE: annual leave, training and
  // parental leave are planned absences that a supervisor arranged, and folding
  // them into the absenteeism rate makes a well-run holiday season look like a
  // problem.
  // --------------------------------------------------------------------------
  pgm.sql(`
    INSERT INTO absence_reasons (code, name, is_planned, counts_as_absenteeism) VALUES
      ('SICK',   'Sickness',                 FALSE, TRUE),
      ('UNEX',   'Unexcused absence',        FALSE, TRUE),
      ('FAM',    'Family or carer leave',    FALSE, TRUE),
      ('MED',    'Medical appointment',      TRUE,  TRUE),
      ('LATE',   'Late arrival',             FALSE, TRUE),
      ('HOL',    'Annual leave',             TRUE,  FALSE),
      ('TRAIN',  'Training',                 TRUE,  FALSE),
      ('PAR',    'Parental leave',           TRUE,  FALSE),
      ('JURY',   'Jury or public duty',      TRUE,  FALSE),
      ('LAYOFF', 'Lay-off or short time',    TRUE,  FALSE)
    ON CONFLICT (code) DO NOTHING
  `);

  // --------------------------------------------------------------------------
  // Injury types and body parts
  // --------------------------------------------------------------------------
  pgm.sql(`
    INSERT INTO injury_types (code, name) VALUES
      ('CUT',  'Cut or laceration'),
      ('BRU',  'Bruise or contusion'),
      ('FRA',  'Fracture'),
      ('BUR',  'Burn'),
      ('STR',  'Strain or sprain'),
      ('EYE',  'Eye injury'),
      ('CRU',  'Crush injury'),
      ('AMP',  'Amputation'),
      ('CHEM', 'Chemical exposure'),
      ('INH',  'Inhalation'),
      ('RSI',  'Repetitive strain'),
      ('ELEC', 'Electric shock'),
      ('OTH',  'Other')
    ON CONFLICT (code) DO NOTHING
  `);

  pgm.sql(`
    INSERT INTO body_parts (code, name, region) VALUES
      ('HEAD',     'Head',              'head'),
      ('EYE',      'Eye',               'head'),
      ('FACE',     'Face',              'head'),
      ('NECK',     'Neck',              'head'),
      ('BACK',     'Back',              'trunk'),
      ('CHEST',    'Chest',             'trunk'),
      ('ABDOMEN',  'Abdomen',           'trunk'),
      ('SHOULDER', 'Shoulder',          'upper_limb'),
      ('ARM',      'Arm',               'upper_limb'),
      ('ELBOW',    'Elbow',             'upper_limb'),
      ('WRIST',    'Wrist',             'upper_limb'),
      ('HAND',     'Hand',              'upper_limb'),
      ('FINGER',   'Finger or thumb',   'upper_limb'),
      ('HIP',      'Hip',               'lower_limb'),
      ('LEG',      'Leg',               'lower_limb'),
      ('KNEE',     'Knee',              'lower_limb'),
      ('ANKLE',    'Ankle',             'lower_limb'),
      ('FOOT',     'Foot',              'lower_limb'),
      ('TOE',      'Toe',               'lower_limb'),
      ('MULTIPLE', 'Multiple parts',    'multiple'),
      ('INTERNAL', 'Internal or systemic', 'other')
    ON CONFLICT (code) DO NOTHING
  `);

  // --------------------------------------------------------------------------
  // The KPI catalogue.
  //
  // `formula_text` is shown on the board next to the number. Where a metric has
  // a caveat — customer PPM computed against quantity produced rather than
  // quantity shipped — it says so there, in front of the person reading it,
  // rather than in a document nobody opens.
  // --------------------------------------------------------------------------
  pgm.sql(`
    INSERT INTO kpi_definitions
      (code, name, pillar_code, unit, aggregation, direction, calculation_type,
       source_view, decimal_places, formula_text, sort_order)
    VALUES
      -- Safety
      ('SAF_TRIR', 'Recordable injury rate (TRIR)', 'S', 'per 200k hrs', 'rate', 'lower_better',
       'derived', 'v_safety_rates', 2,
       'Recordable incidents x 200,000 / hours worked. Recordable means medical treatment or worse.', 1),
      ('SAF_LTIFR', 'Lost time injury frequency (LTIFR)', 'S', 'per 1M hrs', 'rate', 'lower_better',
       'derived', 'v_safety_rates', 2,
       'Lost-time incidents x 1,000,000 / hours worked.', 2),
      ('SAF_INCIDENTS', 'Safety incidents', 'S', 'count', 'sum', 'lower_better',
       'derived', 'v_safety_rates', 0,
       'All incidents recorded, at any severity.', 3),
      ('SAF_NEARMISS', 'Near misses reported', 'S', 'count', 'sum', 'higher_better',
       'derived', 'v_safety_rates', 0,
       'Higher is better: a plant reporting no near misses is not a safe plant, it is a silent one.', 4),
      ('SAF_OBSERVATIONS', 'Safety observations', 'S', 'count', 'sum', 'higher_better',
       'derived', 'v_safety_rates', 0,
       'Proactive observations logged. The leading indicator for the two rates above.', 5),

      -- Quality
      ('QUA_FPY', 'First pass yield', 'Q', '%', 'ratio', 'higher_better',
       'derived', 'v_quality_ppm', 1,
       'Good quantity / total quantity. Reworked units count as a loss, not as good.', 1),
      ('QUA_INT_PPM', 'Internal defect PPM', 'Q', 'ppm', 'rate', 'lower_better',
       'derived', 'v_quality_ppm', 0,
       '(Rejects + rework) x 1,000,000 / total produced.', 2),
      ('QUA_CUST_PPM', 'Customer PPM', 'Q', 'ppm', 'rate', 'lower_better',
       'derived', 'v_quality_ppm', 0,
       'Complaint quantity x 1,000,000 / quantity produced. Note: the correct denominator is quantity shipped; there is no shipping data, so produced is used as a proxy.', 3),
      ('QUA_COMPLAINTS', 'Customer complaints', 'Q', 'count', 'sum', 'lower_better',
       'derived', 'v_quality_ppm', 0,
       'Complaints received, excluding those rejected as unfounded.', 4),
      ('QUA_OPEN_NC', 'Open non-conformances', 'Q', 'count', 'last', 'lower_better',
       'derived', 'quality_issues', 0,
       'Non-conformances not yet dispositioned or closed.', 5),
      ('QUA_OVERDUE_CAPA', 'Overdue CAPAs', 'Q', 'count', 'last', 'lower_better',
       'derived', 'capas', 0,
       'Open CAPAs past their due date.', 6),

      -- Delivery
      ('DEL_OEE', 'Overall equipment effectiveness', 'D', '%', 'ratio', 'higher_better',
       'derived', 'mv_daily_oee', 1,
       'Availability x Performance x Quality.', 1),
      ('DEL_AVAILABILITY', 'Availability', 'D', '%', 'ratio', 'higher_better',
       'derived', 'mv_daily_oee', 1,
       'Run time / planned production time, where planned production time excludes planned stops.', 2),
      ('DEL_PERFORMANCE', 'Performance', 'D', '%', 'ratio', 'higher_better',
       'derived', 'mv_daily_oee', 1,
       'Theoretical minutes for the output at ideal cycle / run time. Above 100% means the cycle time or the count is wrong.', 3),
      ('DEL_QUALITY_RATE', 'Quality rate', 'D', '%', 'ratio', 'higher_better',
       'derived', 'mv_daily_oee', 1,
       'Good quantity / total quantity, the quality factor of OEE.', 4),
      ('DEL_OUTPUT', 'Output', 'D', 'units', 'sum', 'higher_better',
       'derived', 'mv_daily_oee', 0,
       'Total quantity produced, in the product unit of measure.', 5),
      ('DEL_OTD', 'On-time delivery', 'D', '%', 'ratio', 'higher_better',
       'derived', 'v_otd', 1,
       'Orders completed on or before the promised date / orders completed. Orders with no promised date are excluded.', 6),
      ('DEL_DOWNTIME', 'Unplanned downtime', 'D', 'minutes', 'sum', 'lower_better',
       'derived', 'v_downtime_pareto', 0,
       'Minutes lost to unplanned stops, clipped to the shift they fall in.', 7),

      -- Cost
      ('COST_COPQ', 'Cost of poor quality', 'C', 'currency', 'sum', 'lower_better',
       'derived', 'v_cost_of_poor_quality', 2,
       'Scrap at standard cost + rework labour + customer claims - supplier recovery.', 1),
      ('COST_SCRAP', 'Scrap cost', 'C', 'currency', 'sum', 'lower_better',
       'derived', 'v_cost_of_poor_quality', 2,
       'Scrapped quantity x the standard cost in force on the date the defect was found.', 2),
      ('COST_DOWNTIME', 'Downtime cost', 'C', 'currency', 'sum', 'lower_better',
       'derived', 'v_downtime_cost', 2,
       'Unplanned downtime hours x the machine downtime rate for that asset.', 3),
      ('COST_LABOUR', 'Labour cost', 'C', 'currency', 'sum', 'lower_better',
       'derived', 'v_labour_cost', 2,
       'Worked hours x labour rate, with overtime at the premium multiplier.', 4),
      ('COST_OVERTIME', 'Overtime hours', 'C', 'hours', 'sum', 'lower_better',
       'derived', 'v_attendance_rate', 1,
       'Overtime hours worked.', 5),

      -- People
      ('PPL_ABSENTEEISM', 'Absenteeism', 'P', '%', 'ratio', 'lower_better',
       'derived', 'v_attendance_rate', 1,
       'Absences flagged as counting toward absenteeism / scheduled headcount. Annual leave and training are excluded.', 1),
      ('PPL_SKILL_COVERAGE', 'Skill coverage', 'P', '%', 'ratio', 'higher_better',
       'derived', 'v_skill_coverage', 0,
       'Requirements met / requirements defined. An expired certification does not count as qualified.', 2),
      ('PPL_OVERDUE_ACTIONS', 'Overdue actions', 'P', 'count', 'last', 'lower_better',
       'derived', 'v_open_actions', 0,
       'Open actions past their due date, across all five pillars.', 3),
      ('PPL_HEADCOUNT', 'Headcount present', 'P', 'count', 'avg', 'higher_better',
       'derived', 'v_attendance_rate', 0,
       'Average headcount present per shift.', 4)
    ON CONFLICT (code) DO NOTHING
  `);

  // ============================================================================
  // Attaches the audit trail, and adds the nightly maintenance entry point.
  //
  // The audit trigger is attached selectively, not to everything. Two reasons:
  //
  //   Volume.    production_counts and measurements produce more rows than the
  //              rest of the schema combined. Auditing them would roughly double
  //              the database for no benefit, because those rows are already
  //              append-only — their own history is the audit trail.
  //
  //   Meaning.   What an ISO 9001 or IATF 16949 auditor asks about is who changed
  //              a disposition, who closed a CAPA, who moved a target. Those are
  //              the records where an edit changes a conclusion, and those are the
  //              ones covered here.
  //
  // `kpi_targets` and `kpi_actuals` are in the list for a reason worth stating:
  // a target quietly moved after the fact, or an actual edited to clear a red
  // day, is the failure mode that destroys trust in a board. This makes it
  // visible rather than preventing it — people sometimes have to correct data,
  // and a system that forbids it just gets worked around outside the system.
  // ============================================================================
  pgm.sql(`SELECT attach_audit('quality_issues')`);
  pgm.sql(`SELECT attach_audit('quality_dispositions')`);
  pgm.sql(`SELECT attach_audit('capas')`);
  pgm.sql(`SELECT attach_audit('capa_steps')`);
  pgm.sql(`SELECT attach_audit('capa_root_causes')`);
  pgm.sql(`SELECT attach_audit('customer_complaints')`);
  pgm.sql(`SELECT attach_audit('supplier_ncrs')`);
  pgm.sql(`SELECT attach_audit('characteristics')`);
  pgm.sql(`SELECT attach_audit('safety_incidents')`);
  pgm.sql(`SELECT attach_audit('downtime_events')`);
  pgm.sql(`SELECT attach_audit('production_orders')`);
  pgm.sql(`SELECT attach_audit('cost_rates')`);
  pgm.sql(`SELECT attach_audit('product_costs')`);
  pgm.sql(`SELECT attach_audit('product_cycle_times')`);
  pgm.sql(`SELECT attach_audit('kpi_targets')`);
  pgm.sql(`SELECT attach_audit('kpi_actuals')`);
  pgm.sql(`SELECT attach_audit('action_items')`);
  pgm.sql(`SELECT attach_audit('employee_skills')`);
  pgm.sql(`SELECT attach_audit('skill_requirements')`);

  // --------------------------------------------------------------------------
  // Nightly maintenance.
  //
  // One entry point, so the scheduled job is a single call and adding future
  // work to it does not mean editing a cron entry on a server somewhere.
  //
  //     SELECT sqdcp_maintenance();
  //
  // Partitions are created three months ahead. The default partitions exist so
  // that forgetting this does not stop the shop floor recording anything, but a
  // non-empty default partition is a signal that it has not run.
  //
  // This does not call `extend_shift_calendar`: the two were never wired
  // together upstream, and the shift calendar is rolled forward by calling
  // that function separately. Fixing that gap is a job for the deploy-step
  // work, not for this baseline.
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE OR REPLACE FUNCTION sqdcp_maintenance()
    RETURNS TEXT
    LANGUAGE plpgsql
    AS $$
    DECLARE
      v_measurements INTEGER;
      v_audit        INTEGER;
    BEGIN
      v_measurements := ensure_time_partitions(
        'measurements',
        date_trunc('month', now())::date,
        (date_trunc('month', now()) + INTERVAL '3 months')::date
      );

      v_audit := ensure_time_partitions(
        'audit_log',
        date_trunc('month', now())::date,
        (date_trunc('month', now()) + INTERVAL '3 months')::date
      );

      PERFORM refresh_sqdcp_rollups();

      RETURN format(
        'partitions created: measurements=%s audit_log=%s; rollups refreshed',
        v_measurements, v_audit
      );
    END;
    $$
  `);

  // ============================================================================
  // Maintenance foundation: failure taxonomy and meters.
  //
  // Two additions the shared SQDCP schema does not carry, each of which the
  // tables in later sections depend on. `assets.parent_id` and
  // `assets.asset_level`, above, are the third — folded directly into the
  // `assets` table since this baseline has no upstream history to stay
  // compatible with.
  // ============================================================================

  // --------------------------------------------------------------------------
  // Failure codes
  //
  // Not the same thing as `downtime_reasons`. A downtime reason answers "why
  // was the line not producing?" and is shared with production — 'PLN-PM',
  // 'BRK-MECH'. A failure code answers "what was wrong with the equipment?" — a
  // bearing seized, a sensor drifted. One stop has one reason; the job that
  // clears it may find several failures, and a machine that is never the
  // reason for a stop can still accumulate a failure history worth acting on.
  //
  // Hierarchical, and shaped like downtime_reasons on purpose: same two-level
  // parent/child pattern, so the Pareto queries read the same way. Not
  // seeded — failure codes are entered per deployment, per ADR-0005.
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE TABLE failure_codes (
      id          BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      parent_id   BIGINT      REFERENCES failure_codes (id),
      code        TEXT        NOT NULL UNIQUE,
      name        TEXT        NOT NULL,
      description TEXT,
      -- The three-part vocabulary maintenance engineering actually uses:
      -- what was observed, what failed underneath it, what put it there.
      code_type   TEXT        NOT NULL DEFAULT 'failure_mode'
                              CHECK (code_type IN ('symptom', 'failure_mode', 'cause')),
      is_active   BOOLEAN     NOT NULL DEFAULT TRUE,
      created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by  BIGINT,
      updated_by  BIGINT,

      CONSTRAINT failure_codes_parent_not_self CHECK (parent_id IS DISTINCT FROM id)
    )
  `);

  pgm.sql('CREATE INDEX failure_codes_parent_idx ON failure_codes (parent_id)');
  pgm.sql(`SELECT attach_updated_at('failure_codes')`);

  // --------------------------------------------------------------------------
  // Meters
  //
  // Usage-based preventive maintenance needs a running count per asset: hours
  // run, cycles, kilometres. `measurements` cannot hold these — its
  // `characteristic_id` is NOT NULL and references a product characteristic, so
  // it models "this part measured 4.02mm", not "this machine has run 9,140
  // hours". A separate pair of tables is the honest answer.
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE TABLE asset_meters (
      id            BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      asset_id      BIGINT      NOT NULL REFERENCES assets (id),
      code          TEXT        NOT NULL,
      name          TEXT        NOT NULL,
      uom_code      TEXT        NOT NULL REFERENCES units_of_measure (code),
      -- A cumulative meter only goes up (an hour counter). A gauge may go
      -- either way (a temperature, an oil level). Only cumulative meters can
      -- drive an interval-based PM, which is why the distinction is stored
      -- rather than inferred from the readings.
      meter_type    TEXT        NOT NULL DEFAULT 'cumulative'
                                CHECK (meter_type IN ('cumulative', 'gauge')),
      -- A replaced hour counter restarts at zero. Without somewhere to record
      -- the offset, the reading history goes backwards and every interval
      -- calculation built on it silently breaks.
      rollover_offset NUMERIC(18,4) NOT NULL DEFAULT 0,
      is_active     BOOLEAN     NOT NULL DEFAULT TRUE,
      created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by    BIGINT,
      updated_by    BIGINT,

      CONSTRAINT asset_meters_code_unique UNIQUE (asset_id, code)
    )
  `);

  pgm.sql(`SELECT attach_updated_at('asset_meters')`);

  pgm.sql(`
    CREATE TABLE meter_readings (
      id                BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      asset_meter_id    BIGINT      NOT NULL REFERENCES asset_meters (id),
      org_unit_id       BIGINT      NOT NULL REFERENCES org_units (id),
      shift_instance_id BIGINT      REFERENCES shift_instances (id),
      reading           NUMERIC(18,4) NOT NULL,
      read_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
      read_by           BIGINT      REFERENCES employees (id),
      source            TEXT        NOT NULL DEFAULT 'manual'
                                    CHECK (source IN ('manual', 'plc', 'scada', 'import', 'api')),
      note              TEXT,
      created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by        BIGINT,
      updated_by        BIGINT
    )
  `);

  // Readings are read "latest first, per meter" everywhere they are used.
  pgm.sql('CREATE INDEX meter_readings_meter_idx ON meter_readings (asset_meter_id, read_at DESC)');

  pgm.sql(`SELECT attach_updated_at('meter_readings')`);
  // A reading taken at 05:55 belongs to the night shift, not to whatever the
  // calendar date says. The trigger resolves that from the org unit and the
  // timestamp, so nobody has to pick a shift from a dropdown.
  pgm.sql(`SELECT attach_shift_instance('meter_readings', 'read_at')`);

  // ============================================================================
  // Maintenance requests and work orders.
  //
  // A request is what anyone on the floor raises: "this machine is making a
  // noise". A work order is what maintenance commits to doing about it. They are
  // separate tables because most requests are not work: some are duplicates, some
  // are wrong, some are answered by walking over and looking. Folding them into
  // one table means either losing the ones that were rejected — and with them the
  // evidence of what operators actually report — or carrying work orders that
  // were never work.
  //
  // A work order is NOT an `action_items` row. That table has no asset, no
  // scheduled window and no labour, and its five statuses do not describe a job
  // that gets planned, scheduled, worked and closed. The schema's own precedent
  // is `capas`: its own table, whose individual actions are action_items rows.
  // Work orders follow it — `action_items.work_order_id`, defined earlier in
  // this migration, is that link.
  // ============================================================================

  // --------------------------------------------------------------------------
  // Maintenance requests
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE TABLE maintenance_requests (
      id                BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      request_no        TEXT        NOT NULL UNIQUE,
      asset_id          BIGINT      NOT NULL REFERENCES assets (id),
      -- Denormalised from the asset by trigger, because every board query
      -- filters by hierarchy and joining through assets on each one is a cost
      -- the rest of the schema already decided not to pay on downtime_events.
      org_unit_id       BIGINT      NOT NULL REFERENCES org_units (id),
      shift_instance_id BIGINT      REFERENCES shift_instances (id),

      summary           TEXT        NOT NULL,
      description       TEXT,
      -- What the reporter noticed. The diagnosis belongs on the work order.
      symptom_code_id   BIGINT      REFERENCES failure_codes (id),

      -- Does it stop production right now? This is the operator's judgement and
      -- is worth keeping separate from the priority maintenance later assigns:
      -- the gap between the two is a real signal about how the plant is run.
      urgency           TEXT        NOT NULL DEFAULT 'normal'
                                    CHECK (urgency IN ('low', 'normal', 'high', 'immediate')),
      production_stopped BOOLEAN    NOT NULL DEFAULT FALSE,

      reported_by       BIGINT      REFERENCES employees (id),
      reported_at       TIMESTAMPTZ NOT NULL DEFAULT now(),

      status            TEXT        NOT NULL DEFAULT 'new'
                                    CHECK (status IN ('new', 'triaged', 'accepted',
                                                      'rejected', 'duplicate')),
      triaged_by        BIGINT      REFERENCES employees (id),
      triaged_at        TIMESTAMPTZ,
      rejection_reason  TEXT,
      -- Set when this request is a duplicate of one already raised. Points at
      -- the request that survives.
      duplicate_of_id   BIGINT      REFERENCES maintenance_requests (id),

      -- The stop this request is about, when there is one. Filled in by hand:
      -- a request is raised by an operator and a downtime event is often
      -- classified later by someone else, so no trigger can honestly join them.
      downtime_event_id BIGINT      REFERENCES downtime_events (id),

      created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by        BIGINT,
      updated_by        BIGINT,

      CONSTRAINT maintenance_requests_rejected_has_reason
        CHECK (status <> 'rejected' OR rejection_reason IS NOT NULL),
      CONSTRAINT maintenance_requests_duplicate_has_target
        CHECK ((status = 'duplicate') = (duplicate_of_id IS NOT NULL)),
      CONSTRAINT maintenance_requests_not_own_duplicate
        CHECK (duplicate_of_id IS DISTINCT FROM id)
    )
  `);

  pgm.sql(`
    CREATE INDEX maintenance_requests_open_idx
      ON maintenance_requests (org_unit_id, reported_at DESC)
      WHERE status IN ('new', 'triaged')
  `);
  pgm.sql('CREATE INDEX maintenance_requests_asset_idx ON maintenance_requests (asset_id, reported_at DESC)');

  // --------------------------------------------------------------------------
  // Work orders
  //
  // `pm_schedule_id` carries no inline foreign key: `pm_schedules` is created
  // later in this migration, once job plans exist. The constraint is added
  // there, the same forward-reference pattern used for `action_items.work_order_id`
  // above.
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE TABLE work_orders (
      id                BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      work_order_no     TEXT        NOT NULL UNIQUE,
      asset_id          BIGINT      NOT NULL REFERENCES assets (id),
      org_unit_id       BIGINT      NOT NULL REFERENCES org_units (id),

      -- Which request, if any, asked for this. A PM work order has none.
      maintenance_request_id BIGINT REFERENCES maintenance_requests (id),

      summary           TEXT        NOT NULL,
      description       TEXT,

      -- The single most reported number in maintenance: what proportion of work
      -- was planned rather than reactive. It is derived from work_type below
      -- rather than being its own flag, so the two can never disagree.
      work_type         TEXT        NOT NULL
                                    CHECK (work_type IN ('corrective', 'preventive',
                                                         'predictive', 'inspection',
                                                         'improvement', 'calibration')),
      is_planned        BOOLEAN     GENERATED ALWAYS AS (
                                      work_type <> 'corrective'
                                    ) STORED,
      -- Corrective work split by whether the machine had already stopped.
      -- Breakdown work is what MTBF counts; a corrective job done before
      -- failure is not a breakdown and must not be counted as one.
      is_breakdown      BOOLEAN     NOT NULL DEFAULT FALSE,

      priority          SMALLINT    NOT NULL DEFAULT 3 CHECK (priority BETWEEN 1 AND 5),

      status            TEXT        NOT NULL DEFAULT 'draft'
                                    CHECK (status IN ('draft', 'approved', 'scheduled',
                                                      'in_progress', 'on_hold', 'completed',
                                                      'closed', 'cancelled')),

      -- Planning
      scheduled_start   TIMESTAMPTZ,
      scheduled_end     TIMESTAMPTZ,
      estimated_hours   NUMERIC(18,4),
      -- Does the machine have to be stopped for this? Drives what can be
      -- packed into a planned shutdown window.
      requires_shutdown BOOLEAN     NOT NULL DEFAULT FALSE,

      -- Execution
      actual_start      TIMESTAMPTZ,
      actual_end        TIMESTAMPTZ,
      shift_instance_id BIGINT      REFERENCES shift_instances (id),

      -- Ownership. Who leads it; everyone who worked on it is in
      -- work_order_labour.
      assigned_to       BIGINT      REFERENCES employees (id),
      assigned_crew_id  BIGINT      REFERENCES crews (id),

      -- Diagnosis, recorded on completion.
      failure_code_id   BIGINT      REFERENCES failure_codes (id),
      cause_code_id     BIGINT      REFERENCES failure_codes (id),
      completion_note   TEXT,
      completed_by      BIGINT      REFERENCES employees (id),

      -- The stop this job cleared, when there was one. This is the link that
      -- makes a red Delivery day one click from the job that fixed it.
      downtime_event_id BIGINT      REFERENCES downtime_events (id),

      -- Which PM occurrence produced this, when it was generated rather than
      -- raised. See the header: the FK to pm_schedules is added once that
      -- table exists.
      pm_schedule_id    BIGINT,
      due_date          DATE,

      created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by        BIGINT,
      updated_by        BIGINT,

      -- A job cannot finish before it starts, and cannot be scheduled to.
      CONSTRAINT work_orders_actual_window
        CHECK (actual_end IS NULL OR actual_start IS NULL OR actual_end >= actual_start),
      CONSTRAINT work_orders_scheduled_window
        CHECK (scheduled_end IS NULL OR scheduled_start IS NULL OR scheduled_end >= scheduled_start),
      -- Completing a work order without saying when it finished makes every
      -- MTTR built on it wrong, so the database refuses it.
      CONSTRAINT work_orders_completed_has_end
        CHECK (status NOT IN ('completed', 'closed') OR actual_end IS NOT NULL),
      -- A breakdown is by definition corrective.
      CONSTRAINT work_orders_breakdown_is_corrective
        CHECK (NOT is_breakdown OR work_type = 'corrective')
    )
  `);

  pgm.sql(`
    CREATE INDEX work_orders_open_idx
      ON work_orders (org_unit_id, due_date, priority)
      WHERE status IN ('draft', 'approved', 'scheduled', 'in_progress', 'on_hold')
  `);
  pgm.sql('CREATE INDEX work_orders_asset_idx ON work_orders (asset_id, actual_end DESC)');
  pgm.sql('CREATE INDEX work_orders_assignee_idx ON work_orders (assigned_to, status)');
  pgm.sql(`
    CREATE INDEX work_orders_schedule_idx
      ON work_orders (scheduled_start)
      WHERE status IN ('approved', 'scheduled')
  `);

  // One open work order per PM schedule, enforced by the database rather than
  // by application logic. A generator that checks "does an open job already
  // exist for this schedule" before inserting is a check-then-act race: two
  // concurrent runs, a retried job, or a supervisor double-clicking can both
  // pass the check and both insert. A partial unique index makes the database
  // the arbiter instead — the loser gets a unique violation and skips, which is
  // the same answer downtime_events already relies on for one open stop per
  // asset.
  pgm.sql(`
    CREATE UNIQUE INDEX work_orders_one_open_per_pm_schedule
      ON work_orders (pm_schedule_id)
      WHERE pm_schedule_id IS NOT NULL
        AND status IN ('draft', 'approved', 'scheduled', 'in_progress', 'on_hold')
  `);

  // --------------------------------------------------------------------------
  // Shared behaviour
  // --------------------------------------------------------------------------
  pgm.sql(`SELECT attach_updated_at('maintenance_requests')`);
  pgm.sql(`SELECT attach_updated_at('work_orders')`);

  pgm.sql(`SELECT attach_shift_instance('maintenance_requests', 'reported_at')`);
  // Resolved from when the work actually started, not when the row was made.
  pgm.sql(`SELECT attach_shift_instance('work_orders', 'actual_start')`);

  // attach_shift_instance only builds a BEFORE INSERT trigger, which is right
  // for an event that arrives complete. A work order does not: it is inserted
  // as a draft with no actual_start and starts hours or days later, so on
  // insert there is nothing to resolve and the column would stay null forever.
  // This second trigger catches the update that sets it.
  pgm.sql(`
    CREATE TRIGGER work_orders_fill_shift_on_start
      BEFORE UPDATE OF actual_start ON work_orders
      FOR EACH ROW EXECUTE FUNCTION fill_shift_instance('actual_start')
  `);

  // --------------------------------------------------------------------------
  // org_unit_id follows the asset
  //
  // The same denormalisation downtime_events applies, for the same reason:
  // every hierarchy query would otherwise join through assets. Maintained by
  // trigger so it cannot be set inconsistently.
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE FUNCTION fill_org_unit_from_asset() RETURNS TRIGGER AS $$
    BEGIN
      IF NEW.asset_id IS NOT NULL THEN
        SELECT org_unit_id INTO NEW.org_unit_id FROM assets WHERE id = NEW.asset_id;

        -- Raised explicitly, because this trigger runs BEFORE the foreign key
        -- on asset_id is checked. Without it, naming an asset that does not
        -- exist surfaces as a NOT NULL violation on org_unit_id — a column the
        -- caller never supplied and cannot act on — instead of saying that the
        -- asset is the problem.
        IF NEW.org_unit_id IS NULL THEN
          RAISE EXCEPTION 'asset % does not exist', NEW.asset_id
            USING ERRCODE = 'foreign_key_violation';
        END IF;
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql
  `);

  for (const table of ['maintenance_requests', 'work_orders']) {
    pgm.sql(`
      CREATE TRIGGER ${table}_fill_org_unit
        BEFORE INSERT OR UPDATE OF asset_id ON ${table}
        FOR EACH ROW EXECUTE FUNCTION fill_org_unit_from_asset()
    `);
  }

  // work_orders now exists, so action_items.work_order_id can finally point at
  // it. See the comment on that column, above.
  pgm.sql(`
    ALTER TABLE action_items
      ADD CONSTRAINT action_items_work_order_id_fkey
        FOREIGN KEY (work_order_id) REFERENCES work_orders (id)
  `);

  // ============================================================================
  // Preventive maintenance: job plans and the schedules that raise them.
  //
  // A job plan is the reusable content of a job — "500-hour service on a
  // compressor", with its task list. A PM schedule attaches a job plan to a
  // specific asset and says when it comes round. Keeping them apart is what lets
  // eleven identical machines share one plan: fixing a step in the procedure then
  // fixes it everywhere, rather than in ten places and not the eleventh.
  //
  // Two kinds of interval, because plants genuinely use both. A calendar PM comes
  // round every 90 days whether the machine ran or not — statutory inspections
  // and anything with a shelf life. A meter PM comes round every 500 running
  // hours regardless of how long that takes. A schedule may carry both, in which
  // case whichever falls first wins: that is what "every 6 months or 500 hours"
  // means on a manufacturer's service sheet.
  // ============================================================================

  // --------------------------------------------------------------------------
  // Job plans
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE TABLE job_plans (
      id              BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      code            TEXT        NOT NULL UNIQUE,
      name            TEXT        NOT NULL,
      description     TEXT,
      work_type       TEXT        NOT NULL DEFAULT 'preventive'
                                  CHECK (work_type IN ('preventive', 'predictive',
                                                       'inspection', 'calibration')),
      estimated_hours NUMERIC(18,4),
      requires_shutdown BOOLEAN   NOT NULL DEFAULT FALSE,
      -- Free text rather than a permit subsystem. Naming the isolation a job
      -- needs on the plan is most of the value; a permit-to-work module is a
      -- separate thing this app does not claim to be.
      safety_note     TEXT,
      is_active       BOOLEAN     NOT NULL DEFAULT TRUE,
      created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by      BIGINT,
      updated_by      BIGINT
    )
  `);

  pgm.sql(`
    CREATE TABLE job_plan_tasks (
      id            BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      job_plan_id   BIGINT      NOT NULL REFERENCES job_plans (id) ON DELETE CASCADE,
      step_no       INTEGER     NOT NULL,
      instruction   TEXT        NOT NULL,
      -- The qualification this step needs. Checked against employee_skills, so
      -- "who may do this job" is answerable from the plan rather than from
      -- somebody's memory.
      skill_id      BIGINT      REFERENCES skills (id),
      estimated_hours NUMERIC(18,4),
      -- A step that records a number rather than a tick — a vibration reading,
      -- a torque figure. The meter it writes to, when it does.
      records_meter_id BIGINT   REFERENCES asset_meters (id),
      created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by    BIGINT,
      updated_by    BIGINT,

      CONSTRAINT job_plan_tasks_step_unique UNIQUE (job_plan_id, step_no)
    )
  `);

  // --------------------------------------------------------------------------
  // PM schedules
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE TABLE pm_schedules (
      id              BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      code            TEXT        NOT NULL UNIQUE,
      name            TEXT        NOT NULL,
      asset_id        BIGINT      NOT NULL REFERENCES assets (id),
      job_plan_id     BIGINT      NOT NULL REFERENCES job_plans (id),

      -- Calendar interval. Null means this schedule is meter-driven only.
      interval_days   INTEGER     CHECK (interval_days IS NULL OR interval_days > 0),

      -- Meter interval. Both columns or neither.
      asset_meter_id  BIGINT      REFERENCES asset_meters (id),
      interval_meter  NUMERIC(18,4) CHECK (interval_meter IS NULL OR interval_meter > 0),

      -- Whether the next due point is measured from when the last one was DUE
      -- or from when it was actually DONE. A statutory annual inspection is
      -- fixed: doing it three weeks late does not move next year's date, so it
      -- is 'due'. A 500-hour service is 'completed': the clock starts when the
      -- oil was actually changed. Getting this wrong either drifts a fixed
      -- obligation later every cycle, or demands a service that was just done.
      anchor          TEXT        NOT NULL DEFAULT 'completed'
                                  CHECK (anchor IN ('due', 'completed')),

      -- How far ahead the work order is raised, so the job can be planned into
      -- a shift rather than discovered on the day it is due.
      lead_time_days  INTEGER     NOT NULL DEFAULT 7 CHECK (lead_time_days >= 0),

      priority        SMALLINT    NOT NULL DEFAULT 3 CHECK (priority BETWEEN 1 AND 5),
      assigned_crew_id BIGINT     REFERENCES crews (id),

      -- Where the schedule has got to. Maintained when a generated work order
      -- is completed.
      last_completed_on DATE,
      last_completed_meter NUMERIC(18,4),
      next_due_on     DATE,
      next_due_meter  NUMERIC(18,4),

      is_active       BOOLEAN     NOT NULL DEFAULT TRUE,
      created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by      BIGINT,
      updated_by      BIGINT,

      -- A meter interval without a meter is not a schedule, it is a number
      -- nobody can act on.
      CONSTRAINT pm_schedules_meter_pair
        CHECK ((asset_meter_id IS NULL) = (interval_meter IS NULL)),
      -- A schedule that comes round on neither time nor usage never comes
      -- round at all.
      CONSTRAINT pm_schedules_has_an_interval
        CHECK (interval_days IS NOT NULL OR interval_meter IS NOT NULL)
    )
  `);

  pgm.sql(`
    CREATE INDEX pm_schedules_due_idx
      ON pm_schedules (next_due_on)
      WHERE is_active
  `);
  pgm.sql('CREATE INDEX pm_schedules_asset_idx ON pm_schedules (asset_id)');

  // work_orders was created before this table, so its pointer back to the
  // schedule could not carry a foreign key at the time. Add it now — the same
  // forward-reference pattern used above for action_items.work_order_id.
  pgm.sql(`
    ALTER TABLE work_orders
      ADD CONSTRAINT work_orders_pm_schedule_fkey
        FOREIGN KEY (pm_schedule_id) REFERENCES pm_schedules (id)
  `);
  pgm.sql(`
    CREATE INDEX work_orders_pm_schedule_idx
      ON work_orders (pm_schedule_id)
      WHERE pm_schedule_id IS NOT NULL
  `);

  // --------------------------------------------------------------------------
  // Work order tasks
  //
  // Copied from the job plan when a work order is raised, rather than read
  // through it. A plan revised next year must not rewrite what a technician
  // was told to do — and signed off — last year.
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE TABLE work_order_tasks (
      id              BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      work_order_id   BIGINT      NOT NULL REFERENCES work_orders (id) ON DELETE CASCADE,
      step_no         INTEGER     NOT NULL,
      instruction     TEXT        NOT NULL,
      skill_id        BIGINT      REFERENCES skills (id),
      status          TEXT        NOT NULL DEFAULT 'pending'
                                  CHECK (status IN ('pending', 'done', 'skipped', 'failed')),
      -- A skipped or failed step without a note is the one a reviewer most
      -- needs to read about.
      note            TEXT,
      -- The number this step recorded, when it records one.
      reading         NUMERIC(18,4),
      asset_meter_id  BIGINT      REFERENCES asset_meters (id),
      completed_by    BIGINT      REFERENCES employees (id),
      completed_at    TIMESTAMPTZ,
      created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by      BIGINT,
      updated_by      BIGINT,

      CONSTRAINT work_order_tasks_step_unique UNIQUE (work_order_id, step_no),
      CONSTRAINT work_order_tasks_settled_has_note
        CHECK (status NOT IN ('skipped', 'failed') OR note IS NOT NULL),
      CONSTRAINT work_order_tasks_done_has_time
        CHECK (status = 'pending' OR completed_at IS NOT NULL)
    )
  `);

  pgm.sql('CREATE INDEX work_order_tasks_wo_idx ON work_order_tasks (work_order_id, step_no)');

  for (const table of ['job_plans', 'job_plan_tasks', 'pm_schedules', 'work_order_tasks']) {
    pgm.sql(`SELECT attach_updated_at('${table}')`);
  }

  // ============================================================================
  // What a job cost: the hours people spent on it and the parts they fitted.
  //
  // ---------------------------------------------------------------------------
  // A warning about labour, because it is the easiest number here to get wrong.
  // ---------------------------------------------------------------------------
  // `v_labour_cost`, above, already costs every hour worked, from
  // `attendance_records` — and a maintenance technician's shift is in there like
  // anyone else's. So the hours booked here are NOT new cost. They are the same
  // money, attributed to a job.
  //
  // Maintenance labour cost is therefore a SLICE of COST_LABOUR, never an
  // addition to it. Any view that adds the two together double-counts every
  // technician in the plant. `v_maintenance_cost`, below, is built to be read
  // that way, and says so.
  //
  // Parts are the opposite: nothing upstream costs them, because there is no
  // inventory in the SQDCP schema at all. A parts line here is genuinely new
  // money and is the one component of maintenance cost that adds.
  // ============================================================================

  // --------------------------------------------------------------------------
  // Labour
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE TABLE work_order_labour (
      id                BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      work_order_id     BIGINT      NOT NULL REFERENCES work_orders (id) ON DELETE CASCADE,
      employee_id       BIGINT      NOT NULL REFERENCES employees (id),
      org_unit_id       BIGINT      NOT NULL REFERENCES org_units (id),
      shift_instance_id BIGINT      REFERENCES shift_instances (id),

      started_at        TIMESTAMPTZ NOT NULL,
      ended_at          TIMESTAMPTZ,
      -- Generated rather than typed, so the hours can never disagree with the
      -- window they were booked against.
      hours             NUMERIC(18,4) GENERATED ALWAYS AS (
                          CASE
                            WHEN ended_at IS NULL THEN NULL
                            ELSE ROUND(EXTRACT(EPOCH FROM (ended_at - started_at))::numeric / 3600, 4)
                          END
                        ) STORED,
      is_overtime       BOOLEAN     NOT NULL DEFAULT FALSE,

      -- What the technician was doing. Travel and waiting are worth separating
      -- from wrench time: a plant whose technicians spend a third of the job
      -- waiting for a permit has a scheduling problem, not a staffing one.
      activity          TEXT        NOT NULL DEFAULT 'work'
                                    CHECK (activity IN ('work', 'travel', 'waiting',
                                                        'diagnosis', 'documentation')),
      note              TEXT,

      created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by        BIGINT,
      updated_by        BIGINT,

      CONSTRAINT work_order_labour_window
        CHECK (ended_at IS NULL OR ended_at >= started_at)
    )
  `);

  pgm.sql('CREATE INDEX work_order_labour_wo_idx ON work_order_labour (work_order_id)');
  pgm.sql('CREATE INDEX work_order_labour_employee_idx ON work_order_labour (employee_id, started_at DESC)');

  // One technician cannot be on two jobs at the same moment. This is the same
  // shape of guard the schema puts on downtime_events, and it catches the
  // booking mistake that inflates maintenance hours without anyone noticing: a
  // job left running while the next one is started.
  pgm.sql(`
    ALTER TABLE work_order_labour
      ADD CONSTRAINT work_order_labour_no_overlap
      EXCLUDE USING gist (
        employee_id WITH =,
        tstzrange(started_at, COALESCE(ended_at, 'infinity'::timestamptz)) WITH &&
      )
  `);

  // --------------------------------------------------------------------------
  // Parts
  //
  // Deliberately not an inventory. There is no stock on hand, no reorder point
  // and no storeroom: a part here is what was fitted and what it cost. That is
  // enough to make maintenance cost real, and it stops short of a subsystem
  // that would roughly double this schema.
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE TABLE work_order_parts (
      id            BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      work_order_id BIGINT      NOT NULL REFERENCES work_orders (id) ON DELETE CASCADE,

      -- Free text on purpose. Without a catalogue there is nothing to
      -- reference, and demanding a part number the technician does not have
      -- means the line is left blank and the cost is lost.
      part_no       TEXT,
      description   TEXT        NOT NULL,

      quantity      NUMERIC(18,4) NOT NULL CHECK (quantity > 0),
      uom_code      TEXT        NOT NULL REFERENCES units_of_measure (code),

      unit_cost     NUMERIC(18,4) CHECK (unit_cost IS NULL OR unit_cost >= 0),
      currency      TEXT        NOT NULL DEFAULT 'USD' CHECK (char_length(currency) = 3),
      total_cost    NUMERIC(18,4) GENERATED ALWAYS AS (
                      CASE WHEN unit_cost IS NULL THEN NULL ELSE quantity * unit_cost END
                    ) STORED,

      -- Was this bought for the job, or taken off a shelf? Without stock
      -- levels this is the only distinction available, and it is the one that
      -- matters for a purchase order.
      sourced       TEXT        NOT NULL DEFAULT 'stores'
                                CHECK (sourced IN ('stores', 'purchased', 'refurbished',
                                                   'cannibalised')),
      supplier_id   BIGINT      REFERENCES suppliers (id),
      fitted_at     TIMESTAMPTZ,

      created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by    BIGINT,
      updated_by    BIGINT
    )
  `);

  pgm.sql('CREATE INDEX work_order_parts_wo_idx ON work_order_parts (work_order_id)');

  for (const table of ['work_order_labour', 'work_order_parts']) {
    pgm.sql(`SELECT attach_updated_at('${table}')`);
  }

  pgm.sql(`SELECT attach_shift_instance('work_order_labour', 'started_at')`);

  // org_unit_id follows the work order, so labour rolls up the hierarchy
  // without a join through work_orders and assets on every cost query.
  pgm.sql(`
    CREATE FUNCTION fill_org_unit_from_work_order() RETURNS TRIGGER AS $$
    BEGIN
      SELECT org_unit_id INTO NEW.org_unit_id FROM work_orders WHERE id = NEW.work_order_id;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql
  `);

  // Named to sort before work_order_labour_fill_shift: BEFORE triggers fire in
  // name order, and the shift lookup needs org_unit_id already set.
  pgm.sql(`
    CREATE TRIGGER work_order_labour_fill_org
      BEFORE INSERT OR UPDATE OF work_order_id ON work_order_labour
      FOR EACH ROW EXECUTE FUNCTION fill_org_unit_from_work_order()
  `);

  // ============================================================================
  // The views the maintenance board reads from.
  //
  // Every one of these is derived from records captured for another reason —
  // stops that were classified, jobs that were closed, hours that were booked.
  // None of them can disagree with the floor data, because they are the floor
  // data aggregated, which is the same bargain the SQDCP KPI catalogue makes.
  //
  // `v_downtime_mtbf_mttr` is computed from `downtime_events` alone, so a plant
  // that has been classifying stops for a year gets a year of reliability
  // history on day one, before this app has a single work order in it.
  // ============================================================================

  // --------------------------------------------------------------------------
  // Reliability, from downtime alone
  //
  // MTBF is uptime between failures, not wall-clock time between them. The
  // difference matters on a machine that is only scheduled four days a week:
  // counting the weekend as time between failures flatters the number by half.
  // Time is therefore accumulated from the shift instances the asset's org unit
  // was actually scheduled for, and stop minutes are subtracted from it.
  //
  // Only 'breakdown' stops count as failures. A changeover is a stop and is not
  // a failure; counting it would make MTBF a measure of how often the plant
  // changes product.
  //
  // Shifts may be generated for a line and again for a work centre beneath it,
  // so `owners` picks the shift-owning unit CLOSEST to each asset per day —
  // summing every level a shift exists at would double an asset's scheduled
  // minutes. Stops and failures are attributed by the stop's own shift where it
  // has one, and by the plant's calendar date otherwise, so a stop outside the
  // shift calendar — or on any day after the calendar's horizon — is still
  // counted rather than silently dropped. `uptime_minutes` and `mtbf_hours` are
  // NULL, not zero, whenever there is no schedule to measure against or stops
  // exceed it: a machine that never ran has no mean time between failures, and
  // reporting zero would drag every average that touches it to the floor.
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE VIEW v_downtime_mtbf_mttr AS
    WITH owners AS (
      SELECT DISTINCT ON (a.id, si.production_date)
             a.id            AS asset_id,
             si.production_date,
             si.org_unit_id  AS owner_id
      FROM shift_instances si
      JOIN org_units owner ON owner.id = si.org_unit_id
      JOIN org_units au    ON au.path <@ owner.path
      JOIN assets a        ON a.org_unit_id = au.id AND a.is_active
      WHERE si.status <> 'cancelled'
      ORDER BY a.id, si.production_date, nlevel(owner.path) DESC
    ),
    scheduled AS (
      SELECT o.asset_id,
             o.production_date,
             SUM(si.planned_production_minutes)::numeric AS planned_minutes
      FROM owners o
      JOIN shift_instances si
        ON si.org_unit_id = o.owner_id
       AND si.production_date = o.production_date
       AND si.status <> 'cancelled'
      GROUP BY o.asset_id, o.production_date
    ),
    stopped AS (
      SELECT de.asset_id,
             COALESCE(si.production_date, plant_date(de.org_unit_id, de.started_at))
               AS production_date,
             SUM(de.duration_minutes) AS stop_minutes
      FROM downtime_events de
      LEFT JOIN shift_instances si ON si.id = de.shift_instance_id
      WHERE de.ended_at IS NOT NULL
      GROUP BY 1, 2
    ),
    breakdowns AS (
      SELECT de.asset_id,
             COALESCE(si.production_date, plant_date(de.org_unit_id, de.started_at))
               AS production_date,
             COUNT(*)                 AS failure_count,
             SUM(de.duration_minutes) AS breakdown_minutes
      FROM downtime_events de
      JOIN downtime_reasons dr ON dr.id = de.downtime_reason_id
      LEFT JOIN shift_instances si ON si.id = de.shift_instance_id
      WHERE dr.loss_category = 'breakdown'
        AND de.ended_at IS NOT NULL
      GROUP BY 1, 2
    ),
    days AS (
      SELECT asset_id, production_date FROM scheduled
      UNION
      SELECT asset_id, production_date FROM stopped
    )
    SELECT d.asset_id,
           a.org_unit_id,
           d.production_date,
           COALESCE(b.failure_count, 0)     AS failure_count,
           COALESCE(b.breakdown_minutes, 0) AS breakdown_minutes,
           s.planned_minutes,
           CASE
             WHEN s.planned_minutes IS NULL THEN NULL
             WHEN s.planned_minutes - COALESCE(st.stop_minutes, 0) < 0 THEN NULL
             ELSE s.planned_minutes - COALESCE(st.stop_minutes, 0)
           END AS uptime_minutes,
           CASE
             WHEN COALESCE(b.failure_count, 0) > 0
              AND s.planned_minutes IS NOT NULL
              AND s.planned_minutes - COALESCE(st.stop_minutes, 0) >= 0
             THEN ROUND((s.planned_minutes - COALESCE(st.stop_minutes, 0))
                        / b.failure_count / 60.0, 4)
           END AS mtbf_hours,
           CASE WHEN COALESCE(b.failure_count, 0) > 0
                THEN ROUND(b.breakdown_minutes / b.failure_count / 60.0, 4)
           END AS mttr_hours
    FROM days d
    JOIN assets a ON a.id = d.asset_id AND a.is_active
    LEFT JOIN scheduled s
      ON s.asset_id = d.asset_id AND s.production_date = d.production_date
    LEFT JOIN stopped st
      ON st.asset_id = d.asset_id AND st.production_date = d.production_date
    LEFT JOIN breakdowns b
      ON b.asset_id = d.asset_id AND b.production_date = d.production_date
  `);

  // --------------------------------------------------------------------------
  // Reliability including the work-order view of a repair
  //
  // MTTR from downtime is how long the machine was stopped. MTTR from work
  // orders is how long the repair took. They are different numbers and the gap
  // between them is response time — how long the machine sat broken before
  // anyone started. That gap is usually the larger half, and is invisible
  // unless both are reported.
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE VIEW v_asset_reliability AS
    SELECT wo.asset_id,
           wo.org_unit_id,
           plant_date(wo.org_unit_id, wo.actual_end) AS production_date,
           COUNT(*)                                  AS breakdown_jobs,
           ROUND(AVG(EXTRACT(EPOCH FROM (wo.actual_end - wo.actual_start))::numeric / 3600), 4)
                                                     AS mean_repair_hours,
           ROUND(AVG(EXTRACT(EPOCH FROM (wo.actual_start - de.started_at))::numeric / 3600), 4)
                                                     AS mean_response_hours
    FROM work_orders wo
    LEFT JOIN downtime_events de ON de.id = wo.downtime_event_id
    WHERE wo.is_breakdown
      AND wo.status IN ('completed', 'closed')
      AND wo.actual_start IS NOT NULL
      AND wo.actual_end IS NOT NULL
    GROUP BY wo.asset_id, wo.org_unit_id, plant_date(wo.org_unit_id, wo.actual_end)
  `);

  // --------------------------------------------------------------------------
  // PM compliance
  //
  // Of the preventive work that came due, how much was actually done, and how
  // much was done on time. Late-but-done and never-done are different failures
  // and are counted separately: a plant at 100% completion and 40% on-time has
  // a scheduling problem, not a discipline problem.
  //
  // A meter-driven PM carries no calendar due date, because it came round on
  // usage rather than the calendar; it is dated by when it was done rather than
  // dropped, so running-hours services are not invisible to this KPI. Work not
  // yet due is excluded — counting it made the current month read red on the
  // 2nd and climb all month as the plant caught up with a target that had not
  // arrived yet.
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE VIEW v_pm_compliance AS
    WITH pm AS (
      SELECT wo.org_unit_id,
             wo.status,
             wo.actual_end,
             COALESCE(wo.due_date, plant_date(wo.org_unit_id, wo.actual_end)) AS due_on
      FROM work_orders wo
      WHERE wo.pm_schedule_id IS NOT NULL
        AND wo.status <> 'cancelled'
    )
    SELECT org_unit_id,
           date_trunc('month', due_on)::date AS period_start,
           COUNT(*)                                                    AS pm_due,
           COUNT(*) FILTER (WHERE status IN ('completed', 'closed'))   AS pm_completed,
           COUNT(*) FILTER (
             WHERE status IN ('completed', 'closed')
               AND plant_date(org_unit_id, actual_end) <= due_on
           )                                                           AS pm_on_time,
           ROUND(
             100.0 * COUNT(*) FILTER (
               WHERE status IN ('completed', 'closed')
                 AND plant_date(org_unit_id, actual_end) <= due_on
             ) / NULLIF(COUNT(*), 0), 2
           )                                                           AS compliance_pct
    FROM pm
    WHERE due_on IS NOT NULL
      AND due_on <= CURRENT_DATE
    GROUP BY org_unit_id, date_trunc('month', due_on)::date
  `);

  // --------------------------------------------------------------------------
  // Schedule compliance: was the work done in the window it was planned for?
  // Bounded on both sides — a job done a week early is not compliant with the
  // schedule, it is a different plan — and a window that has not opened yet
  // cannot have been missed.
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE VIEW v_maintenance_schedule_compliance AS
    SELECT wo.org_unit_id,
           plant_date(wo.org_unit_id, wo.scheduled_start) AS production_date,
           COUNT(*)                                       AS scheduled_jobs,
           COUNT(*) FILTER (
             WHERE wo.actual_start IS NOT NULL
               AND wo.actual_start >= wo.scheduled_start
               AND wo.actual_start <= wo.scheduled_end
           )                                              AS started_in_window,
           ROUND(
             100.0 * COUNT(*) FILTER (
               WHERE wo.actual_start IS NOT NULL
                 AND wo.actual_start >= wo.scheduled_start
                 AND wo.actual_start <= wo.scheduled_end
             ) / NULLIF(COUNT(*), 0), 2
           )                                              AS schedule_compliance_pct
    FROM work_orders wo
    WHERE wo.scheduled_start IS NOT NULL
      AND wo.scheduled_end IS NOT NULL
      AND wo.status <> 'cancelled'
      AND wo.scheduled_start <= now()
    GROUP BY wo.org_unit_id, plant_date(wo.org_unit_id, wo.scheduled_start)
  `);

  // --------------------------------------------------------------------------
  // Planned versus reactive
  //
  // The headline maintenance-maturity number. Measured in hours rather than job
  // count, because one three-day breakdown and one ten-minute inspection are
  // not one-all — labour is pre-aggregated per work order below before it is
  // counted, so COUNT(*) counts jobs rather than labour bookings.
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE VIEW v_maintenance_planned_ratio AS
    WITH labour AS (
      SELECT work_order_id, SUM(hours) AS hours
      FROM work_order_labour
      WHERE hours IS NOT NULL
      GROUP BY work_order_id
    )
    SELECT wo.org_unit_id,
           plant_date(wo.org_unit_id, wo.actual_end) AS production_date,
           COUNT(*)                                                     AS jobs,
           COUNT(*) FILTER (WHERE wo.is_planned)                        AS planned_jobs,
           COALESCE(SUM(l.hours), 0)                                    AS total_hours,
           COALESCE(SUM(l.hours) FILTER (WHERE wo.is_planned), 0)       AS planned_hours,
           ROUND(
             100.0 * COALESCE(SUM(l.hours) FILTER (WHERE wo.is_planned), 0)
             / NULLIF(SUM(l.hours), 0), 2
           )                                                            AS planned_pct
    FROM work_orders wo
    LEFT JOIN labour l ON l.work_order_id = wo.id
    WHERE wo.status IN ('completed', 'closed')
      AND wo.actual_end IS NOT NULL
    GROUP BY wo.org_unit_id, plant_date(wo.org_unit_id, wo.actual_end)
  `);

  // --------------------------------------------------------------------------
  // Backlog
  //
  // Open work, in hours, with what is already overdue called out. Deliberately
  // not expressed in weeks: turning hours into weeks needs a crew capacity
  // figure that nothing in this schema holds, and inventing one would make the
  // most quoted number on the board the least trustworthy. Hours are honest —
  // and `unestimated_jobs` is counted separately, so a queue of unestimated
  // work reads as a gap in the data rather than as zero backlog.
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE VIEW v_maintenance_backlog AS
    SELECT wo.org_unit_id,
           COUNT(*)                                                    AS open_jobs,
           COUNT(*) FILTER (
             WHERE wo.due_date < plant_date(wo.org_unit_id, now())
           )                                                           AS overdue_jobs,
           COALESCE(SUM(wo.estimated_hours), 0)                        AS backlog_hours,
           COALESCE(SUM(wo.estimated_hours) FILTER (
             WHERE wo.due_date < plant_date(wo.org_unit_id, now())
           ), 0)                                                       AS overdue_hours,
           COUNT(*) FILTER (WHERE wo.estimated_hours IS NULL)          AS unestimated_jobs,
           COUNT(*) FILTER (WHERE wo.is_breakdown)                     AS breakdown_jobs,
           MIN(wo.due_date)                                            AS earliest_due
    FROM work_orders wo
    WHERE wo.status IN ('draft', 'approved', 'scheduled', 'in_progress', 'on_hold')
    GROUP BY wo.org_unit_id
  `);

  // --------------------------------------------------------------------------
  // Maintenance cost
  //
  // READ THIS BEFORE ADDING IT TO ANYTHING.
  //
  // `labour_cost` here is a SLICE of COST_LABOUR, not an addition to it. Those
  // hours are already costed by `v_labour_cost`, out of `attendance_records`,
  // because a technician's shift is attendance like anyone else's. Adding this
  // column to COST_LABOUR double-counts every maintenance technician in the
  // plant.
  //
  // `parts_cost` is the opposite: nothing upstream costs a part, because the
  // SQDCP schema has no inventory at all. It is genuinely additive.
  //
  // So: total_cost below is what maintenance costs. Only parts_cost is new
  // money against the plant's C pillar.
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE VIEW v_maintenance_cost AS
    WITH labour AS (
      SELECT l.work_order_id,
             SUM(l.hours) AS hours,
             SUM(
               l.hours
               * COALESCE(
                   resolve_cost_rate(l.org_unit_id, wo.asset_id, 'labor_per_hour',
                                     plant_date(l.org_unit_id, l.started_at)),
                   0
                 )
               * CASE
                   WHEN l.is_overtime THEN COALESCE(
                     resolve_cost_rate(l.org_unit_id, wo.asset_id,
                                       'overtime_premium_multiplier',
                                       plant_date(l.org_unit_id, l.started_at)),
                     1
                   )
                   ELSE 1
                 END
             ) AS cost
      FROM work_order_labour l
      JOIN work_orders wo ON wo.id = l.work_order_id
      WHERE l.hours IS NOT NULL
      GROUP BY l.work_order_id
    ),
    parts AS (
      SELECT work_order_id, SUM(total_cost) AS cost
      FROM work_order_parts
      WHERE total_cost IS NOT NULL
      GROUP BY work_order_id
    )
    SELECT wo.id            AS work_order_id,
           wo.work_order_no,
           wo.org_unit_id,
           wo.asset_id,
           wo.work_type,
           wo.is_planned,
           wo.is_breakdown,
           plant_date(wo.org_unit_id, wo.actual_end) AS production_date,
           COALESCE(lab.hours, 0)                    AS labour_hours,
           COALESCE(lab.cost, 0)                     AS labour_cost,
           COALESCE(prt.cost, 0)                     AS parts_cost,
           COALESCE(lab.cost, 0) + COALESCE(prt.cost, 0) AS total_cost
    FROM work_orders wo
    LEFT JOIN labour lab ON lab.work_order_id = wo.id
    LEFT JOIN parts  prt ON prt.work_order_id = wo.id
    WHERE wo.status IN ('completed', 'closed')
  `);

  // --------------------------------------------------------------------------
  // PM due
  //
  // What is coming, on either clock. A meter-driven schedule is due when the
  // latest reading has passed the target; a calendar one when the date has.
  // A schedule carrying both is due when EITHER falls, which is what "every 6
  // months or 500 hours" means on a service sheet. `due_by_date`, `due_by_meter`
  // and `within_lead_time` are all COALESCEd to false rather than left NULL —
  // a meter with no readings yet still yields a plain two-valued flag, not a
  // third "unknown" state every caller would otherwise have to handle.
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE VIEW v_pm_due AS
    WITH latest_reading AS (
      SELECT DISTINCT ON (mr.asset_meter_id)
             mr.asset_meter_id, mr.reading, mr.read_at
      FROM meter_readings mr
      ORDER BY mr.asset_meter_id, mr.read_at DESC
    )
    SELECT s.id AS pm_schedule_id, s.code, s.name, s.asset_id, a.org_unit_id, s.job_plan_id,
           s.next_due_on, s.next_due_meter, lr.reading AS current_meter,
           COALESCE(s.next_due_on IS NOT NULL AND s.next_due_on <= CURRENT_DATE, false)
             AS due_by_date,
           COALESCE(s.next_due_meter IS NOT NULL AND lr.reading >= s.next_due_meter, false)
             AS due_by_meter,
           COALESCE(s.next_due_on IS NOT NULL
                    AND s.next_due_on - s.lead_time_days <= CURRENT_DATE, false)
             AS within_lead_time,
           s.next_due_on - CURRENT_DATE AS days_until_due
    FROM pm_schedules s
    JOIN assets a ON a.id = s.asset_id
    LEFT JOIN latest_reading lr ON lr.asset_meter_id = s.asset_meter_id
    WHERE s.is_active
  `);

  // ============================================================================
  // The maintenance KPIs, added to the shared board catalogue.
  //
  // This needs no change to the board itself: insert a row into
  // `kpi_definitions` pointing `source_view` at a view, then add a
  // `kpi_targets` row for each org unit that should be measured against it.
  // `v_sqdcp_board` picks them up from there.
  //
  // Every one is `calculation_type = 'derived'`, so none of them can disagree
  // with the records underneath — they are those records, aggregated.
  //
  // Pillar choice: maintenance KPIs sit under Delivery rather than under a
  // pillar of their own, because that is what they are for. A machine is
  // maintained so it runs; MTBF and PM compliance are leading indicators for the
  // availability term of OEE, and putting them beside it is what makes a red
  // Delivery day traceable to the reliability that caused it. Only the money
  // goes to Cost.
  //
  // `formula_text` is shown on the board next to the number, so each one states
  // its own caveat where a reader will actually see it rather than in a document
  // nobody opens.
  // ============================================================================
  pgm.sql(`
    INSERT INTO kpi_definitions
      (code, name, pillar_code, unit, aggregation, direction, calculation_type,
       source_view, decimal_places, formula_text, description, sort_order)
    VALUES
      ('MNT_PM_COMPLIANCE', 'PM compliance', 'D', '%', 'ratio', 'higher_better',
       'derived', 'v_pm_compliance', 1,
       'preventive work orders completed on or before their due date / preventive work orders due',
       'Counts only work orders raised from a PM schedule. Completed-but-late is excluded from the numerator and kept in the denominator, so a plant that does all of its preventive work a month late scores zero rather than 100%.',
       10),
      ('MNT_SCHEDULE_COMPLIANCE', 'Schedule compliance', 'D', '%', 'ratio', 'higher_better',
       'derived', 'v_maintenance_schedule_compliance', 1,
       'work orders started within their scheduled window / work orders scheduled',
       'How much of the plan survived contact with the week. Distinct from PM compliance: this measures the schedule, that one measures the obligation.',
       11),
      ('MNT_MTBF', 'Mean time between failures', 'D', 'hours', 'avg', 'higher_better',
       'derived', 'v_downtime_mtbf_mttr', 1,
       'scheduled uptime / breakdown count',
       'Uptime, not wall-clock time: a machine scheduled four days a week is not accumulating time between failures over the weekend. Only stops whose reason falls under the breakdown loss category count as failures, so a changeover does not make the number worse. Null for an asset that has not failed, rather than zero.',
       12),
      ('MNT_MTTR', 'Mean time to repair', 'D', 'hours', 'avg', 'lower_better',
       'derived', 'v_downtime_mtbf_mttr', 2,
       'breakdown downtime minutes / breakdown count',
       'Measured from the stop, so it includes the wait before anyone arrived. v_asset_reliability splits the same period into response time and wrench time for anyone asking which half to attack.',
       13),
      ('MNT_PLANNED_RATIO', 'Planned maintenance ratio', 'D', '%', 'ratio', 'higher_better',
       'derived', 'v_maintenance_planned_ratio', 1,
       'labour hours on planned work / total maintenance labour hours',
       'In hours rather than job count: one three-day breakdown against one ten-minute inspection is not an even split. Planned means any work type other than corrective.',
       14),
      ('MNT_BACKLOG', 'Maintenance backlog', 'D', 'hours', 'sum', 'lower_better',
       'derived', 'v_maintenance_backlog', 1,
       'estimated hours on all open work orders',
       'Hours, not weeks. Converting to weeks needs a crew capacity figure this schema does not hold, and a made-up denominator would make the most quoted number on the board the least trustworthy.',
       15),
      ('MNT_COST', 'Maintenance cost', 'C', 'currency', 'sum', 'lower_better',
       'derived', 'v_maintenance_cost', 2,
       'maintenance labour cost + parts cost (labour is a SLICE of COST_LABOUR, not an addition)',
       'The labour half is already inside COST_LABOUR, which costs every hour worked from attendance — a technician included. Adding this to COST_LABOUR double-counts the whole maintenance department. Only the parts half is new money against the plant, because the SQDCP schema has no inventory and costs no part anywhere else.',
       10),
      ('MNT_PARTS_COST', 'Spare parts cost', 'C', 'currency', 'sum', 'lower_better',
       'derived', 'v_maintenance_cost', 2,
       'sum of quantity x unit cost over parts fitted',
       'The one component of maintenance cost that is additive to the C pillar. Costed at what was entered on the job, not from a standard cost, because there is no parts catalogue to hold one.',
       11)
    ON CONFLICT (code) DO NOTHING
  `);

  // ============================================================================
  // Atomic allocation of document numbers, scoped by Site.
  //
  // A counter row per prefix, Site and year, incremented and read in one
  // statement, is atomic: the row lock serialises the allocation without a
  // transaction-level lock on anything else. Numbers may still be skipped — a
  // rolled-back transaction does not give its number back — which is the right
  // trade: a gap in a work order number is harmless, two jobs sharing one
  // number is not.
  //
  // Per ADR-0005, the counter is scoped by Site as well as prefix and year.
  // With several plants sharing one database, a counter scoped only to
  // prefix-and-year gives one global run of numbers shared between every Site:
  // the numbers interleave, and WO-2026-000123 does not say which plant issued
  // it. `p_site_code` — the Site's short code, not its numeric id — is folded
  // into both the scope key and the printed number, because a code is what a
  // technician reads off a printed work order: WO-BUC-2026-00001 says which
  // plant issued it, WO-4-2026-00001 does not. This has to be right before the
  // first document is issued: numbers get printed, emailed and quoted on the
  // floor, and a work order already issued cannot be renumbered.
  // ============================================================================
  pgm.sql(`
    CREATE TABLE document_sequences (
      scope      TEXT   PRIMARY KEY,
      next_value BIGINT NOT NULL
    )
  `);

  pgm.sql(`
    CREATE FUNCTION next_document_number(p_prefix TEXT, p_site_code TEXT, p_year INTEGER)
    RETURNS TEXT
    LANGUAGE sql
    AS $$
      INSERT INTO public.document_sequences (scope, next_value)
      VALUES (p_prefix || '-' || p_site_code || '-' || p_year, 2)
      ON CONFLICT (scope)
        DO UPDATE SET next_value = public.document_sequences.next_value + 1
      RETURNING p_prefix || '-' || p_site_code || '-' || p_year || '-' ||
                lpad((next_value - 1)::text, 5, '0');
    $$
  `);

  // ============================================================================
  // Fill created_by and updated_by from the signed-in person.
  //
  // The SQDCP conventions put `created_at`/`updated_at`/`created_by`/`updated_by`
  // on every table, and the shared `set_updated_at()` trigger maintains only the
  // two timestamps — the two actor columns are left for the application to fill.
  //
  // They are filled by trigger rather than by each route, for the same reason
  // `updated_at` is: a column that depends on every INSERT remembering to set it
  // is a column that is right until somebody adds the twentieth route.
  //
  // The value comes from `app.user_id`, the session setting the API sets per
  // transaction and that the shared schema's audit triggers already read. A
  // write made outside a request — a migration, a seed, someone at a psql
  // prompt — has no setting and records null, which is the honest answer
  // rather than a guess.
  //
  // On UPDATE, `created_by` is filled in if it was NULL but never overwritten
  // otherwise — the author does not change, but a NULL one from a row written
  // before this trigger existed can still be repaired through ordinary SQL.
  // `updated_by` is set to whoever is making THIS change and nobody else:
  // falling back to the previous editor when no session is set would attribute
  // an anonymous write — a migration, a psql session — to the last person who
  // happened to touch the row, which is a lie the audit trail must not tell.
  //
  // Only this app's own tables are attached. The SQDCP tables are left as the
  // rest of this migration defines them.
  // ============================================================================
  pgm.sql(`
    CREATE FUNCTION set_actor_columns() RETURNS TRIGGER AS $$
    DECLARE
      v_actor BIGINT := NULLIF(current_setting('app.user_id', true), '')::BIGINT;
    BEGIN
      IF TG_OP = 'INSERT' THEN
        -- COALESCE so an explicit value survives: a backfill or an import that
        -- knows who the author was should not have it overwritten.
        NEW.created_by := COALESCE(NEW.created_by, v_actor);
        NEW.updated_by := COALESCE(NEW.updated_by, v_actor);
      ELSE
        -- The author does not change, but a NULL one may still be filled in.
        -- Pinning it unconditionally made repairing the rows written before
        -- this trigger existed impossible through SQL.
        NEW.created_by := COALESCE(OLD.created_by, NEW.created_by);
        -- Whoever is making THIS change, and nobody else. Falling back to the
        -- previous editor attributes an anonymous write to the last person who
        -- touched the row.
        NEW.updated_by := v_actor;
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql
  `);

  pgm.sql(`
    CREATE FUNCTION attach_actor_columns(p_table TEXT) RETURNS void AS $$
    BEGIN
      -- Named to sort after the org-unit and shift triggers, which must have
      -- run first; BEFORE triggers fire in name order.
      EXECUTE format(
        'CREATE TRIGGER zz_%I_set_actor
           BEFORE INSERT OR UPDATE ON %I
           FOR EACH ROW EXECUTE FUNCTION set_actor_columns()',
        p_table, p_table
      );
    END;
    $$ LANGUAGE plpgsql
  `);

  const ACTOR_COLUMN_TABLES = [
    'maintenance_requests',
    'work_orders',
    'work_order_tasks',
    'work_order_labour',
    'work_order_parts',
    'job_plans',
    'job_plan_tasks',
    'pm_schedules',
    'asset_meters',
    'meter_readings',
    'failure_codes'
  ];

  for (const table of ACTOR_COLUMN_TABLES) {
    pgm.sql(`SELECT attach_actor_columns('${table}')`);
  }
};

exports.down = (pgm) => {
  // A squashed baseline has nothing before it to return to, so its down() does
  // not reverse itself statement by statement — it drops everything this
  // migration created and starts the schema over.
  pgm.sql('DROP SCHEMA public CASCADE');
  pgm.sql('CREATE SCHEMA public');
};
