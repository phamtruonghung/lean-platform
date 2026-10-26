/**
 * The Production Module's first four tables (issue #333, spec #332, ADR-0054):
 * the Shift handover a Section's outgoing Team Leader writes and the incoming
 * one acknowledges, and the three kinds of line it carries.
 *
 * **One live record per Section per shift instance.** `shift_handovers` is
 * keyed by `(org_unit_id, shift_instance_id)`, and the partial unique index
 * `shift_handovers_live_unique` allows at most one row of the pair with
 * `superseded_at IS NULL`. An amendment is a new row with the next `version`
 * that names the one it replaces in `supersedes_id`; the old row is stamped
 * `superseded_at` and kept, so both stay readable (ADR-0054's "a correction is
 * an amendment"). `shift_handovers_version_unique` keeps the version run of a
 * pair from repeating.
 *
 * **The snapshot columns are nullable on purpose.** They are written once, at
 * submit, and never recomputed (ADR-0054's "the record freezes the numbers it
 * showed"); a draft has not been sealed and so carries none of them.
 * `production_date` is copied from the shift instance at open, so the
 * handover's own day never moves under it.
 *
 * `handover_no` reads `HO-<year>-<00001>` from its own sequence, the same shape
 * the baseline's other document numbers take.
 *
 * The three line tables cascade from their handover: a line has no meaning
 * without the handover it belongs to. Every link to another Module's record —
 * an Asset, a downtime event, a quality issue, a Work order, an Action, an
 * Employee — is a plain foreign key by id, never a copy of that record's text
 * (ADR-0054's "linked, not copied").
 *
 * The deny-all RLS floor is switched on for all four in this same migration
 * (ADR-0004), with `attach_updated_at`, `attach_actor_columns` and
 * `attach_audit` as `1802600000000_employee-signatures.js` pairs them.
 *
 * Backward-compatible per ADR-0007: new tables and a new sequence change
 * nothing an older running image reads or writes.
 */

exports.shorthands = undefined;

const TABLES = [
  'shift_handovers',
  'shift_handover_machine_lines',
  'shift_handover_change_points',
  'shift_handover_actions'
];

exports.up = (pgm) => {
  pgm.sql('CREATE SEQUENCE shift_handovers_no_seq');

  pgm.sql(`
    CREATE TABLE shift_handovers (
      id                          BIGINT        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      handover_no                 TEXT          NOT NULL UNIQUE
                                                DEFAULT 'HO-' || to_char(CURRENT_DATE, 'YYYY') || '-' ||
                                                        lpad(nextval('shift_handovers_no_seq')::text, 5, '0'),
      site_id                     BIGINT        NOT NULL REFERENCES sites (id),
      org_unit_id                 BIGINT        NOT NULL REFERENCES org_units (id),
      shift_instance_id           BIGINT        NOT NULL REFERENCES shift_instances (id),
      production_date             DATE          NOT NULL,
      status                      TEXT          NOT NULL DEFAULT 'draft',
      version                     INTEGER       NOT NULL DEFAULT 1,
      supersedes_id               BIGINT        REFERENCES shift_handovers (id),
      superseded_at               TIMESTAMPTZ,
      superseded_by_account_id    BIGINT        REFERENCES app_users (id),
      submitted_at                TIMESTAMPTZ,
      submitted_by_account_id     BIGINT        REFERENCES app_users (id),
      acknowledged_at             TIMESTAMPTZ,
      acknowledged_by_account_id  BIGINT        REFERENCES app_users (id),
      acknowledgement_note        TEXT,
      late                        BOOLEAN       NOT NULL DEFAULT FALSE,
      joint_walk_done             BOOLEAN       NOT NULL DEFAULT FALSE,
      critical_items              TEXT,
      deviation_reason            TEXT          NOT NULL DEFAULT 'none',
      change_points_none          BOOLEAN       NOT NULL DEFAULT FALSE,

      oee                            NUMERIC(7,4),
      availability                   NUMERIC(7,4),
      performance                    NUMERIC(7,4),
      quality                        NUMERIC(7,4),
      planned_production_minutes     NUMERIC(12,2),
      run_minutes                    NUMERIC(12,2),
      unplanned_downtime_minutes     NUMERIC(12,2),
      top_loss_reason_id             BIGINT        REFERENCES downtime_reasons (id),
      top_loss_minutes               NUMERIC(12,2),
      unclassified_downtime_minutes  NUMERIC(12,2),
      unclassified_stop_count        INTEGER,
      good_quantity                  NUMERIC(18,4),
      reject_quantity                NUMERIC(18,4),
      rework_quantity                NUMERIC(18,4),
      planned_quantity               NUMERIC(18,4),
      performance_suspect            BOOLEAN,
      open_stop_count                INTEGER,
      open_quality_issue_count       INTEGER,
      safety_event_count             INTEGER,

      created_at                  TIMESTAMPTZ   NOT NULL DEFAULT now(),
      updated_at                  TIMESTAMPTZ   NOT NULL DEFAULT now(),
      created_by                  BIGINT,
      updated_by                  BIGINT,

      CONSTRAINT shift_handovers_status_check
        CHECK (status IN ('draft', 'submitted', 'acknowledged')),
      CONSTRAINT shift_handovers_version_check CHECK (version >= 1),
      CONSTRAINT shift_handovers_deviation_reason_check
        CHECK (deviation_reason IN ('none', 'late', 'partial', 'no_incoming_team_leader'))
    )
  `);

  pgm.sql(`
    CREATE UNIQUE INDEX shift_handovers_version_unique
      ON shift_handovers (org_unit_id, shift_instance_id, version)
  `);
  pgm.sql(`
    CREATE UNIQUE INDEX shift_handovers_live_unique
      ON shift_handovers (org_unit_id, shift_instance_id)
      WHERE superseded_at IS NULL
  `);

  pgm.sql(`
    CREATE TABLE shift_handover_machine_lines (
      id                 BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      handover_id        BIGINT       NOT NULL REFERENCES shift_handovers (id) ON DELETE CASCADE,
      asset_id           BIGINT       NOT NULL REFERENCES assets (id),
      state              TEXT         NOT NULL,
      abnormality_type   TEXT,
      note               TEXT,
      downtime_event_id  BIGINT       REFERENCES downtime_events (id),
      quality_issue_id   BIGINT       REFERENCES quality_issues (id),
      work_order_id      BIGINT       REFERENCES work_orders (id),
      watch_note         TEXT,
      walked             BOOLEAN      NOT NULL DEFAULT FALSE,
      created_at         TIMESTAMPTZ  NOT NULL DEFAULT now(),
      updated_at         TIMESTAMPTZ  NOT NULL DEFAULT now(),
      created_by         BIGINT,
      updated_by         BIGINT,

      CONSTRAINT shift_handover_machine_lines_state_check
        CHECK (state IN ('running', 'running_manual', 'idle', 'down', 'maintenance',
                         'cleaning', 'changeover', 'isolated')),
      CONSTRAINT shift_handover_machine_lines_abnormality_type_check
        CHECK (abnormality_type IN ('minor_flaw', 'unfulfilled_basic_condition',
                                    'inaccessible_place', 'contamination_source',
                                    'quality_defect_source', 'unnecessary_item',
                                    'unsafe_place')),
      CONSTRAINT shift_handover_machine_lines_asset_unique UNIQUE (handover_id, asset_id)
    )
  `);

  pgm.sql(`
    CREATE TABLE shift_handover_change_points (
      id                            BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      handover_id                   BIGINT       NOT NULL REFERENCES shift_handovers (id) ON DELETE CASCADE,
      dimension                     TEXT         NOT NULL,
      description                   TEXT         NOT NULL,
      watch_note                    TEXT         NOT NULL,
      employee_id                   BIGINT       REFERENCES employees (id),
      watch_result                  TEXT,
      watch_result_note             TEXT,
      watch_answered_by_account_id  BIGINT       REFERENCES app_users (id),
      watch_answered_at             TIMESTAMPTZ,
      created_at                    TIMESTAMPTZ  NOT NULL DEFAULT now(),
      updated_at                    TIMESTAMPTZ  NOT NULL DEFAULT now(),
      created_by                    BIGINT,
      updated_by                    BIGINT,

      CONSTRAINT shift_handover_change_points_dimension_check
        CHECK (dimension IN ('man', 'machine', 'material', 'method')),
      CONSTRAINT shift_handover_change_points_watch_result_check
        CHECK (watch_result IN ('ok', 'concern', 'not_run'))
    )
  `);

  pgm.sql(`
    CREATE TABLE shift_handover_actions (
      id                 BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      handover_id        BIGINT       NOT NULL REFERENCES shift_handovers (id) ON DELETE CASCADE,
      action_id          BIGINT       NOT NULL REFERENCES action_items (id),
      disposition        TEXT         NOT NULL,
      owner_employee_id  BIGINT       REFERENCES employees (id),
      closure_note       TEXT,
      created_at         TIMESTAMPTZ  NOT NULL DEFAULT now(),
      updated_at         TIMESTAMPTZ  NOT NULL DEFAULT now(),
      created_by         BIGINT,
      updated_by         BIGINT,

      CONSTRAINT shift_handover_actions_disposition_check
        CHECK (disposition IN ('carried', 'reassigned', 'closed')),
      CONSTRAINT shift_handover_actions_action_unique UNIQUE (handover_id, action_id)
    )
  `);

  // The foreign keys a Section's day and a handover's lines are read through.
  pgm.sql('CREATE INDEX shift_handovers_shift_instance_idx ON shift_handovers (shift_instance_id)');
  pgm.sql('CREATE INDEX shift_handover_change_points_handover_idx ON shift_handover_change_points (handover_id)');

  for (const table of TABLES) {
    pgm.sql(`SELECT attach_updated_at('${table}')`);
    pgm.sql(`SELECT attach_actor_columns('${table}')`);
    pgm.sql(`SELECT attach_audit('${table}')`);
    pgm.sql(`ALTER TABLE ${table} ENABLE ROW LEVEL SECURITY`);
  }
};

exports.down = (pgm) => {
  // Forward-only in production per ADR-0007 — this exists for local
  // development and for node-pg-migrate's requirement that a migration
  // define both directions.
  for (const table of [...TABLES].reverse()) {
    pgm.sql(`ALTER TABLE ${table} DISABLE ROW LEVEL SECURITY`);
    pgm.sql(`DROP TRIGGER IF EXISTS ${table}_audit ON ${table}`);
    pgm.sql(`DROP TRIGGER IF EXISTS zz_${table}_set_actor ON ${table}`);
    pgm.sql(`DROP TRIGGER IF EXISTS ${table}_set_updated_at ON ${table}`);
    pgm.sql(`DROP TABLE IF EXISTS ${table}`);
  }
  pgm.sql('DROP SEQUENCE IF EXISTS shift_handovers_no_seq');
};
