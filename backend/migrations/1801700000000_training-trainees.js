/**
 * `training_trainees` (issue #288, ADR-0043) — one row per Trainee on a
 * Training record: the Employees who were trained on it, added one at a time.
 * This migration creates that table and nothing else. A Trainee's answer
 * (`answer`, `answered_*`) belongs to #289 and the trainer's `evaluation` to
 * #290, so neither is here: a column arrives in the slice that writes it, and
 * this slice writes only who is on the list.
 *
 * **`ON DELETE CASCADE` on the record, none on the Employee.** Discarding a
 * draft takes its list with it; an Employee who is on a record is never
 * silently removed from it by deleting the Employee.
 *
 * **`UNIQUE (training_record_id, employee_id)`.** The same Employee twice on
 * one record would make a count of Trainees a count of rows rather than of
 * people, so the database refuses it; the route maps the violation to a 409.
 *
 * The deny-all RLS floor is switched on in this same migration (ADR-0004),
 * with `attach_updated_at`, `attach_actor_columns` and `attach_audit` as
 * `1801600000000_training-records.js` pairs them.
 *
 * Backward-compatible per ADR-0007: a new table changes nothing an older
 * running image reads or writes.
 */

exports.shorthands = undefined;

exports.up = (pgm) => {
  pgm.sql(`
    CREATE TABLE training_trainees (
      id                 BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      training_record_id BIGINT       NOT NULL REFERENCES training_records (id) ON DELETE CASCADE,
      employee_id        BIGINT       NOT NULL REFERENCES employees (id),
      created_at         TIMESTAMPTZ  NOT NULL DEFAULT now(),
      updated_at         TIMESTAMPTZ  NOT NULL DEFAULT now(),
      created_by         BIGINT,
      updated_by         BIGINT,

      CONSTRAINT training_trainees_record_employee_key UNIQUE (training_record_id, employee_id)
    )
  `);

  pgm.sql('CREATE INDEX training_trainees_employee_idx ON training_trainees (employee_id)');

  pgm.sql(`SELECT attach_updated_at('training_trainees')`);
  pgm.sql(`SELECT attach_actor_columns('training_trainees')`);
  pgm.sql(`SELECT attach_audit('training_trainees')`);

  pgm.sql('ALTER TABLE training_trainees ENABLE ROW LEVEL SECURITY');
};

exports.down = (pgm) => {
  // Forward-only in production per ADR-0007 — this exists for local
  // development and for node-pg-migrate's requirement that a migration
  // define both directions.
  pgm.sql('ALTER TABLE training_trainees DISABLE ROW LEVEL SECURITY');
  pgm.sql('DROP TRIGGER IF EXISTS training_trainees_audit ON training_trainees');
  pgm.sql('DROP TRIGGER IF EXISTS zz_training_trainees_set_actor ON training_trainees');
  pgm.sql('DROP TRIGGER IF EXISTS training_trainees_set_updated_at ON training_trainees');
  pgm.sql('DROP TABLE IF EXISTS training_trainees');
};
