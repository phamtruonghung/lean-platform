/**
 * Sending a Training record and a Trainee's answer (issue #289, ADR-0043).
 * Two ALTER TABLEs and no new table, so no new RLS: both tables already carry
 * the deny-all floor from their own migrations.
 *
 * `training_records` gains `sent_at` and `sent_by_account_id`. `status` is
 * already there (1801600000000, #287's amendment to the spec) and is not
 * re-added. A CHECK ties the three together: a draft carries neither sent
 * column and a sent record carries both, so "sent" can never be a status
 * with no moment and no sender behind it.
 *
 * `training_trainees` gains `answer` (`confirmed`/`declined`), `answered_at`,
 * `answered_by_account_id` and `answered_by_employee_id`. Pending is
 * `answer IS NULL` and nothing else. One CHECK holds the whole shape: either
 * nothing has been answered (answer, timestamp and both actors null), or an
 * answer arrives with its timestamp and EXACTLY ONE actor — the Account that
 * answered, or the Employee identified at the shared floor device, never both
 * and never neither (the shape safety_incidents' recorder takes, migration
 * 1800800000000). `answered_by_employee_id` is written by the floor-device
 * door (#293); this slice writes only the Account door.
 *
 * Backward-compatible per ADR-0007: every column is nullable, and every row
 * an older image can still produce (a draft, an unanswered Trainee) satisfies
 * both CHECKs.
 */

exports.shorthands = undefined;

exports.up = (pgm) => {
  pgm.sql(`
    ALTER TABLE training_records
      ADD COLUMN sent_at            TIMESTAMPTZ,
      ADD COLUMN sent_by_account_id BIGINT REFERENCES app_users (id)
  `);
  pgm.sql(`
    ALTER TABLE training_records
      ADD CONSTRAINT training_records_sent_columns CHECK (
        (status = 'draft' AND sent_at IS NULL AND sent_by_account_id IS NULL)
        OR (status = 'sent' AND sent_at IS NOT NULL AND sent_by_account_id IS NOT NULL)
      )
  `);

  pgm.sql(`
    ALTER TABLE training_trainees
      ADD COLUMN answer                  TEXT,
      ADD COLUMN answered_at             TIMESTAMPTZ,
      ADD COLUMN answered_by_account_id  BIGINT REFERENCES app_users (id),
      ADD COLUMN answered_by_employee_id BIGINT REFERENCES employees (id)
  `);
  pgm.sql(`
    ALTER TABLE training_trainees
      ADD CONSTRAINT training_trainees_answer_values CHECK (answer IN ('confirmed', 'declined'))
  `);
  pgm.sql(`
    ALTER TABLE training_trainees
      ADD CONSTRAINT training_trainees_answer_shape CHECK (
        (answer IS NULL AND answered_at IS NULL
          AND answered_by_account_id IS NULL AND answered_by_employee_id IS NULL)
        OR (answer IS NOT NULL AND answered_at IS NOT NULL
          AND ((answered_by_account_id IS NOT NULL) <> (answered_by_employee_id IS NOT NULL)))
      )
  `);
  pgm.sql(`
    CREATE INDEX training_trainees_outstanding_idx
      ON training_trainees (employee_id) WHERE answer IS NULL
  `);
};

exports.down = (pgm) => {
  // Forward-only in production per ADR-0007 — this exists for local
  // development and for node-pg-migrate's requirement that a migration
  // define both directions.
  pgm.sql('DROP INDEX IF EXISTS training_trainees_outstanding_idx');
  pgm.sql('ALTER TABLE training_trainees DROP CONSTRAINT training_trainees_answer_shape');
  pgm.sql('ALTER TABLE training_trainees DROP CONSTRAINT training_trainees_answer_values');
  pgm.sql(`
    ALTER TABLE training_trainees
      DROP COLUMN answered_by_employee_id,
      DROP COLUMN answered_by_account_id,
      DROP COLUMN answered_at,
      DROP COLUMN answer
  `);
  pgm.sql('ALTER TABLE training_records DROP CONSTRAINT training_records_sent_columns');
  pgm.sql(`
    ALTER TABLE training_records
      DROP COLUMN sent_by_account_id,
      DROP COLUMN sent_at
  `);
};
