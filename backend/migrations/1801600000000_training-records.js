/**
 * `training_records` (issue #287, ADR-0043) — one row per Training record: one
 * occasion of training delivered at an Org Unit. This migration creates that
 * table and nothing else. The Trainees listed on a record belong to #288, and
 * the columns that say a record was sent or corrected belong to #289 and #291,
 * so none of them is here: `status` alone is carried now, defaulting to
 * `draft`, because the register's draft-visibility rule needs it from the
 * first slice.
 *
 * **`trainer_employee_id` and `objective` are nullable.** Raising asks only
 * for the title, the day and the duration; sending (#289) is what refuses a
 * record with no trainer or no objective, so the columns cannot be NOT NULL
 * while a draft is still being filled in.
 *
 * **`site_id` is stored beside `org_unit_id`.** The number is the Site's own
 * (`next_document_number('TR', <site code>, <year>)`), and the register reads
 * by Site without a join; the route derives it from the Org Unit, never from
 * the caller.
 *
 * The deny-all RLS floor is switched on in this same migration (ADR-0004),
 * with `attach_updated_at`, `attach_actor_columns` and `attach_audit` as
 * `1801200000000_attendance-sheets.js` pairs them for a table whose rows are
 * edited in place.
 *
 * Backward-compatible per ADR-0007: a new table changes nothing an older
 * running image reads or writes.
 */

exports.shorthands = undefined;

exports.up = (pgm) => {
  pgm.sql(`
    CREATE TABLE training_records (
      id                  BIGINT        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      site_id             BIGINT        NOT NULL REFERENCES sites (id),
      org_unit_id         BIGINT        NOT NULL REFERENCES org_units (id),
      number              TEXT          NOT NULL UNIQUE,
      title               TEXT          NOT NULL,
      trained_on          DATE          NOT NULL,
      duration_hours      NUMERIC(6,2)  NOT NULL,
      trainer_employee_id BIGINT        REFERENCES employees (id),
      objective           TEXT,
      status              TEXT          NOT NULL DEFAULT 'draft',
      created_at          TIMESTAMPTZ   NOT NULL DEFAULT now(),
      updated_at          TIMESTAMPTZ   NOT NULL DEFAULT now(),
      created_by          BIGINT,
      updated_by          BIGINT,

      CONSTRAINT training_records_status_check CHECK (status IN ('draft', 'sent')),
      CONSTRAINT training_records_duration_positive CHECK (duration_hours > 0)
    )
  `);

  pgm.sql('CREATE INDEX training_records_org_unit_idx ON training_records (org_unit_id)');
  pgm.sql('CREATE INDEX training_records_trained_on_idx ON training_records (trained_on)');

  pgm.sql(`SELECT attach_updated_at('training_records')`);
  pgm.sql(`SELECT attach_actor_columns('training_records')`);
  pgm.sql(`SELECT attach_audit('training_records')`);

  pgm.sql('ALTER TABLE training_records ENABLE ROW LEVEL SECURITY');
};

exports.down = (pgm) => {
  // Forward-only in production per ADR-0007 — this exists for local
  // development and for node-pg-migrate's requirement that a migration
  // define both directions.
  pgm.sql('ALTER TABLE training_records DISABLE ROW LEVEL SECURITY');
  pgm.sql('DROP TRIGGER IF EXISTS training_records_audit ON training_records');
  pgm.sql('DROP TRIGGER IF EXISTS zz_training_records_set_actor ON training_records');
  pgm.sql('DROP TRIGGER IF EXISTS training_records_set_updated_at ON training_records');
  pgm.sql('DROP TABLE IF EXISTS training_records');
};
