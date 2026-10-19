/**
 * A Trainee's answer carries their Signature (issue #318, ADR-0052). Adds two
 * nullable columns to `training_trainees` and nothing else:
 *
 *   - `signature_id`         the `employee_signatures` row the answer was
 *                            signed with. The table is append-only, so the row
 *                            a record names can never change under it.
 *   - `signature_applied_as` `stored` (the Signature the person keeps) or
 *                            `drawn` (a stroke made as they answered). Written
 *                            explicitly beside the id, never derived from the
 *                            row's `kept` flag.
 *
 * Two CHECKs hold the shape: the columns arrive together or not at all, and a
 * decline never carries a Signature. Every row an older image can still
 * produce has both columns NULL and satisfies both, so the image this replaces
 * keeps working against the new schema (ADR-0007). The table already carries
 * its `updated_at`, actor and audit triggers and its RLS floor
 * (`1801700000000_training-trainees.js`), so none is attached again.
 */

exports.shorthands = undefined;

exports.up = (pgm) => {
  pgm.sql(`
    ALTER TABLE training_trainees
      ADD COLUMN signature_id BIGINT REFERENCES employee_signatures (id),
      ADD COLUMN signature_applied_as TEXT,
      ADD CONSTRAINT training_trainees_signature_applied_as_check
        CHECK (signature_applied_as IN ('stored', 'drawn')),
      ADD CONSTRAINT training_trainees_signature_together
        CHECK ((signature_id IS NULL) = (signature_applied_as IS NULL)),
      ADD CONSTRAINT training_trainees_declined_unsigned
        CHECK (answer <> 'declined' OR signature_id IS NULL)
  `);
};

exports.down = (pgm) => {
  // Forward-only in production per ADR-0007 — this exists for local
  // development and for node-pg-migrate's requirement that a migration
  // define both directions.
  pgm.sql(`
    ALTER TABLE training_trainees
      DROP CONSTRAINT IF EXISTS training_trainees_declined_unsigned,
      DROP CONSTRAINT IF EXISTS training_trainees_signature_together,
      DROP CONSTRAINT IF EXISTS training_trainees_signature_applied_as_check,
      DROP COLUMN IF EXISTS signature_applied_as,
      DROP COLUMN IF EXISTS signature_id
  `);
};
