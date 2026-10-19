/**
 * `employee_signatures` (issue #317, ADR-0052) — an Employee's own mark, kept
 * as a small PNG in the row that holds it. This migration creates that table
 * and nothing else.
 *
 * **One narrow exception to "the Platform records text only", one table wide.**
 * `image` is the only `bytea` column in the schema, and `schema.test.js` fails
 * if a second one appears. This is not a file-storage capability.
 *
 * **Append-only.** One row per image ever applied; a row is superseded by
 * setting `superseded_at`, never rewritten and never deleted. The current
 * Signature is the one `kept` row with `superseded_at IS NULL`, which the
 * partial unique index allows at most one of per Employee. A row with
 * `kept = FALSE` (a stroke drawn for one act) is never current.
 *
 * **The size ceiling lives here too.** `image_bytes` must equal
 * `octet_length(image)` and stay within 48 KiB (49152), so a write that
 * skipped the route's own validation still cannot store a large file.
 *
 * `set_by_account_id` is the Account that set the mark; it is NULL for none
 * recorded and differs from the Employee's own Account when an administrator
 * sets one for an Employee who holds no Account.
 *
 * The deny-all RLS floor is switched on in this same migration (ADR-0004),
 * with `attach_updated_at`, `attach_actor_columns` and `attach_audit` as
 * `1801700000000_training-trainees.js` pairs them.
 *
 * Backward-compatible per ADR-0007: a new table changes nothing an older
 * running image reads or writes.
 */

exports.shorthands = undefined;

exports.up = (pgm) => {
  pgm.sql(`
    CREATE TABLE employee_signatures (
      id                 BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      employee_id        BIGINT       NOT NULL REFERENCES employees (id),
      image              BYTEA        NOT NULL,
      image_bytes        INTEGER      NOT NULL,
      origin             TEXT         NOT NULL,
      kept               BOOLEAN      NOT NULL DEFAULT TRUE,
      superseded_at      TIMESTAMPTZ,
      set_by_account_id  BIGINT       REFERENCES app_users (id),
      created_at         TIMESTAMPTZ  NOT NULL DEFAULT now(),
      updated_at         TIMESTAMPTZ  NOT NULL DEFAULT now(),
      created_by         BIGINT,
      updated_by         BIGINT,

      CONSTRAINT employee_signatures_origin_check CHECK (origin IN ('upload', 'on_screen')),
      CONSTRAINT employee_signatures_image_bytes_matches CHECK (image_bytes = octet_length(image)),
      CONSTRAINT employee_signatures_image_bytes_ceiling CHECK (image_bytes <= 49152)
    )
  `);

  pgm.sql(`
    CREATE UNIQUE INDEX employee_signatures_one_current_idx
      ON employee_signatures (employee_id)
      WHERE kept AND superseded_at IS NULL
  `);

  pgm.sql(`SELECT attach_updated_at('employee_signatures')`);
  pgm.sql(`SELECT attach_actor_columns('employee_signatures')`);
  pgm.sql(`SELECT attach_audit('employee_signatures')`);

  pgm.sql('ALTER TABLE employee_signatures ENABLE ROW LEVEL SECURITY');
};

exports.down = (pgm) => {
  // Forward-only in production per ADR-0007 — this exists for local
  // development and for node-pg-migrate's requirement that a migration
  // define both directions.
  pgm.sql('ALTER TABLE employee_signatures DISABLE ROW LEVEL SECURITY');
  pgm.sql('DROP TRIGGER IF EXISTS employee_signatures_audit ON employee_signatures');
  pgm.sql('DROP TRIGGER IF EXISTS zz_employee_signatures_set_actor ON employee_signatures');
  pgm.sql('DROP TRIGGER IF EXISTS employee_signatures_set_updated_at ON employee_signatures');
  pgm.sql('DROP TABLE IF EXISTS employee_signatures');
};
