/**
 * What the trainer recorded about each Trainee (issue #290, ADR-0043). One
 * ALTER TABLE and no new table, so no new RLS: `training_trainees` already
 * carries the deny-all floor from its own migration.
 *
 * `training_trainees` gains `evaluation`: how that Trainee was evaluated, as
 * the trainer records it - `paper` or `job_training`, the two methods the
 * form's own Evaluation header names. Nullable, because nobody has evaluated a
 * Trainee until the trainer says so, and clearing it returns the row to that
 * state. The named CHECK is the known set; the Module's own validation says
 * the same in words before a write reaches it.
 *
 * Backward-compatible per ADR-0007: the column is nullable and every row an
 * older image can still produce satisfies the CHECK.
 */

exports.shorthands = undefined;

exports.up = (pgm) => {
  pgm.sql('ALTER TABLE training_trainees ADD COLUMN evaluation TEXT');
  pgm.sql(`
    ALTER TABLE training_trainees
      ADD CONSTRAINT training_trainees_evaluation_values CHECK (evaluation IN ('paper', 'job_training'))
  `);
};

exports.down = (pgm) => {
  // Forward-only in production per ADR-0007 - this exists for local
  // development and for node-pg-migrate's requirement that a migration
  // define both directions.
  pgm.sql('ALTER TABLE training_trainees DROP CONSTRAINT training_trainees_evaluation_values');
  pgm.sql('ALTER TABLE training_trainees DROP COLUMN evaluation');
};
