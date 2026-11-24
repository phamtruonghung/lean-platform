/**
 * The Assessments, their Attempts, the frozen papers and the floor sitting row
 * (issue #588, ADR-0068, slice 3). One migration, four tables, because they
 * only make sense together: an Assessment is what a team leader defines, an
 * Attempt is one Employee's sitting of it, `assessment_attempt_questions` is
 * the paper drawn at that sitting, and `assessment_sittings` is the credential
 * a floor device holds while one paper runs.
 *
 * **Why one file for four tables.** node-pg-migrate runs a migration in one
 * transaction, so a partial apply is impossible; four files would give four
 * separate tails to renumber every time a sibling slice merges, and slice 2
 * already had to do that once. Nothing in this file removes or narrows what an
 * older running image reads or writes (ADR-0007) — every table is new.
 *
 * **`assessment_attempt_questions.id` is a surrogate key, and that is
 * load-bearing.** `attach_audit` writes `NEW.id` into `audit_log.record_id`,
 * which is `BIGINT NOT NULL`; a composite primary key on
 * `(attempt_id, position)` would leave the trigger no single id and would break
 * the audit trail on the one table whose changes matter most (a Marker
 * correcting a point). The natural key stays as a `UNIQUE` beside the id.
 *
 * **The paper is a snapshot, not a view over the bank.** Text, Options, key and
 * explanation are copied at the draw and never re-read from
 * `assessment_questions`, so correcting a Question changes how quoting from the
 * bank reads in future and leaves every paper already sat exactly as it was
 * answered. See section 3.9 and 11 of the spec.
 *
 * **`assessment_attempts.attempt_no` lands now, the retake route lands later**
 * (slice 6). The column and `UNIQUE (assessment_id, employee_id, attempt_no)`
 * are here so nothing has to migrate a table that already carries production
 * sittings; the per-Assessment cap (`attempt_no < attempts_allowed`) is held by
 * the route, not the database, because a CHECK cannot read another table.
 *
 * **`assessment_sittings` is a running paper's credential.** The floor device
 * identifies a person for 120 seconds (`floor-devices.js`); a paper runs 20 or
 * 30 minutes. Widening the identification would widen every other floor write,
 * so one paper gets one token, `token_hash` only, surviving until
 * `deadline_at + 5 minutes` or until a Team Leader ends the sitting. It is
 * created here rather than in slice 5 so the table has one home and slice 5
 * writes no migration of its own.
 *
 * Every table carries `created_at`/`updated_at`/`created_by`/`updated_by`,
 * calls `attach_updated_at`, `attach_actor_columns` and `attach_audit`, and
 * turns on deny-all RLS — the four statements `1801600000000_training-records.js`
 * pairs for a table edited in place (ADR-0004). `down` exists for
 * node-pg-migrate and local development only: it drops the triggers by name
 * before the tables, children before parents.
 */

exports.shorthands = undefined;

exports.up = (pgm) => {
  // -------------------------------------------------------------------------
  // assessments — the check's own definition
  // -------------------------------------------------------------------------
  pgm.sql(`
    CREATE TABLE assessments (
      id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      site_id BIGINT NOT NULL REFERENCES sites (id),
      org_unit_id BIGINT NOT NULL REFERENCES org_units (id),
      number TEXT NOT NULL UNIQUE,
      title TEXT NOT NULL,
      question_count SMALLINT NOT NULL,
      minutes SMALLINT NOT NULL,
      pass_mark SMALLINT NOT NULL,
      attempts_allowed SMALLINT NOT NULL DEFAULT 1,
      due_on DATE,
      status TEXT NOT NULL DEFAULT 'draft',
      created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by BIGINT,
      updated_by BIGINT,

      CONSTRAINT assessments_status_check
        CHECK (status IN ('draft', 'assigned', 'closed')),
      CONSTRAINT assessments_question_count_check CHECK (question_count IN (10, 15)),
      CONSTRAINT assessments_minutes_check CHECK (minutes BETWEEN 5 AND 120),
      CONSTRAINT assessments_pass_mark_check CHECK (pass_mark BETWEEN 1 AND question_count),
      CONSTRAINT assessments_attempts_allowed_check CHECK (attempts_allowed BETWEEN 1 AND 3),
      CONSTRAINT assessments_title_not_blank CHECK (length(btrim(title)) BETWEEN 3 AND 200)
    )
  `);

  pgm.sql('CREATE INDEX assessments_org_unit_idx ON assessments (org_unit_id)');
  pgm.sql('CREATE INDEX assessments_status_due_idx ON assessments (status, due_on)');

  // -------------------------------------------------------------------------
  // assessment_attempts — one Employee's sitting
  // -------------------------------------------------------------------------
  pgm.sql(`
    CREATE TABLE assessment_attempts (
      id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      assessment_id BIGINT NOT NULL REFERENCES assessments (id) ON DELETE CASCADE,
      employee_id BIGINT NOT NULL REFERENCES employees (id),
      attempt_no SMALLINT NOT NULL DEFAULT 1,
      org_unit_id BIGINT NOT NULL REFERENCES org_units (id),
      org_unit_resolved_on DATE NOT NULL,
      status TEXT NOT NULL DEFAULT 'assigned',
      started_at TIMESTAMPTZ,
      deadline_at TIMESTAMPTZ,
      submitted_at TIMESTAMPTZ,
      submitted_late BOOLEAN NOT NULL DEFAULT FALSE,
      score SMALLINT,
      final_score SMALLINT,
      marked_by_account_id BIGINT REFERENCES app_users (id),
      marked_at TIMESTAMPTZ,
      marking_note TEXT,
      retake_reason TEXT,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by BIGINT,
      updated_by BIGINT,

      CONSTRAINT assessment_attempts_status_check
        CHECK (status IN ('assigned', 'in_progress', 'submitted', 'marked',
                          'expired', 'cancelled')),
      CONSTRAINT assessment_attempts_assessment_employee_no_key
        UNIQUE (assessment_id, employee_id, attempt_no),
      CONSTRAINT assessment_attempts_attempt_no_check CHECK (attempt_no BETWEEN 1 AND 3),
      CONSTRAINT assessment_attempts_retake_needs_reason
        CHECK (attempt_no = 1 OR length(btrim(retake_reason)) BETWEEN 3 AND 2000),
      CONSTRAINT assessment_attempts_deadline_needs_start
        CHECK (deadline_at IS NULL OR started_at IS NOT NULL),
      CONSTRAINT assessment_attempts_deadline_after_start
        CHECK (started_at IS NULL OR deadline_at > started_at),
      CONSTRAINT assessment_attempts_final_score_needs_marking
        CHECK (final_score IS NULL OR (marked_at IS NOT NULL AND marked_by_account_id IS NOT NULL)),
      CONSTRAINT assessment_attempts_score_range CHECK (score IS NULL OR score >= 0),
      CONSTRAINT assessment_attempts_final_score_range
        CHECK (final_score IS NULL OR final_score >= 0)
    )
  `);

  pgm.sql(`CREATE INDEX assessment_attempts_assessment_status_idx
             ON assessment_attempts (assessment_id, status)`);
  pgm.sql(`CREATE INDEX assessment_attempts_employee_status_idx
             ON assessment_attempts (employee_id, status)`);
  pgm.sql(`CREATE INDEX assessment_attempts_running_idx
             ON assessment_attempts (deadline_at) WHERE status = 'in_progress'`);
  pgm.sql(`CREATE INDEX assessment_attempts_marking_idx
             ON assessment_attempts (submitted_at) WHERE status = 'submitted'`);

  // -------------------------------------------------------------------------
  // assessment_attempt_questions — the drawn paper, frozen, one row per Question
  // -------------------------------------------------------------------------
  pgm.sql(`
    CREATE TABLE assessment_attempt_questions (
      id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      attempt_id BIGINT NOT NULL REFERENCES assessment_attempts (id) ON DELETE CASCADE,
      question_id BIGINT NOT NULL REFERENCES assessment_questions (id),
      position SMALLINT NOT NULL,
      question_text TEXT NOT NULL,
      option_a TEXT NOT NULL,
      option_b TEXT NOT NULL,
      option_c TEXT NOT NULL,
      correct_option CHAR(1) NOT NULL,
      explanation TEXT,
      chosen_option CHAR(1),
      other_text TEXT,
      answered_at TIMESTAMPTZ,
      points SMALLINT NOT NULL DEFAULT 0,
      marked_by_account_id BIGINT REFERENCES app_users (id),
      marked_at TIMESTAMPTZ,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by BIGINT,
      updated_by BIGINT,

      CONSTRAINT assessment_attempt_questions_attempt_position_key
        UNIQUE (attempt_id, position),
      CONSTRAINT assessment_attempt_questions_attempt_question_key
        UNIQUE (attempt_id, question_id),
      CONSTRAINT assessment_attempt_questions_correct_option_check
        CHECK (correct_option IN ('A', 'B', 'C')),
      CONSTRAINT assessment_attempt_questions_chosen_option_check
        CHECK (chosen_option IS NULL OR chosen_option IN ('A', 'B', 'C')),
      CONSTRAINT assessment_attempt_questions_position_check CHECK (position BETWEEN 1 AND 15),
      CONSTRAINT assessment_attempt_questions_points_check CHECK (points IN (0, 1)),
      CONSTRAINT assessment_attempt_questions_one_answer_shape
        CHECK (chosen_option IS NULL OR other_text IS NULL),
      CONSTRAINT assessment_attempt_questions_other_not_blank
        CHECK (other_text IS NULL OR length(btrim(other_text)) BETWEEN 1 AND 2000)
    )
  `);

  pgm.sql(`CREATE INDEX assessment_attempt_questions_attempt_idx
             ON assessment_attempt_questions (attempt_id, position)`);
  // The marking queue counts Other answers per paper (slice 4); the read is
  // "rows on one paper whose other_text is set", so a partial index is the
  // shape that serves it without indexing every row's null.
  pgm.sql(`CREATE INDEX assessment_attempt_questions_other_idx
             ON assessment_attempt_questions (attempt_id) WHERE other_text IS NOT NULL`);

  // -------------------------------------------------------------------------
  // assessment_sittings — the floor door's credential for one running Attempt
  // -------------------------------------------------------------------------
  pgm.sql(`
    CREATE TABLE assessment_sittings (
      id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      attempt_id BIGINT NOT NULL UNIQUE REFERENCES assessment_attempts (id) ON DELETE CASCADE,
      employee_id BIGINT NOT NULL REFERENCES employees (id),
      floor_device_id BIGINT NOT NULL REFERENCES floor_devices (id),
      token_hash TEXT NOT NULL,
      issued_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      expires_at TIMESTAMPTZ NOT NULL,
      revoked_at TIMESTAMPTZ,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by BIGINT,
      updated_by BIGINT,

      CONSTRAINT assessment_sittings_expires_after_issue CHECK (expires_at > issued_at)
    )
  `);

  // -------------------------------------------------------------------------
  // Triggers and the RLS floor, the same four statements per table
  // -------------------------------------------------------------------------
  for (const table of [
    'assessments',
    'assessment_attempts',
    'assessment_attempt_questions',
    'assessment_sittings'
  ]) {
    pgm.sql(`SELECT attach_updated_at('${table}')`);
    pgm.sql(`SELECT attach_actor_columns('${table}')`);
    pgm.sql(`SELECT attach_audit('${table}')`);
    pgm.sql(`ALTER TABLE ${table} ENABLE ROW LEVEL SECURITY`);
  }
};

exports.down = (pgm) => {
  // Forward-only in production per ADR-0007 — this exists for local
  // development and for node-pg-migrate's requirement that a migration
  // define both directions. Children before parents.
  const tables = [
    'assessment_sittings',
    'assessment_attempt_questions',
    'assessment_attempts',
    'assessments'
  ];
  for (const table of tables) {
    pgm.sql(`ALTER TABLE ${table} DISABLE ROW LEVEL SECURITY`);
    pgm.sql(`DROP TRIGGER IF EXISTS ${table}_audit ON ${table}`);
    pgm.sql(`DROP TRIGGER IF EXISTS zz_${table}_set_actor ON ${table}`);
    pgm.sql(`DROP TRIGGER IF EXISTS ${table}_set_updated_at ON ${table}`);
  }
  pgm.sql('DROP TABLE IF EXISTS assessment_sittings');
  pgm.sql('DROP TABLE IF EXISTS assessment_attempt_questions');
  pgm.sql('DROP TABLE IF EXISTS assessment_attempts');
  pgm.sql('DROP TABLE IF EXISTS assessments');
};
