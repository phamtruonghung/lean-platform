/**
 * `assessment_questions` (issue #588, ADR-0068) — the Question bank: one row per
 * Question, filed on one Org Unit, the process. This migration creates that
 * table and nothing else. The Assessments that draw from it, their Attempts and
 * the frozen papers are later slices' tables and are not here.
 *
 * **The fingerprint, and what it costs.** `question_text_fingerprint` is a
 * generated column: the md5 of the stem lower-cased, trimmed, with every run of
 * whitespace collapsed to one space. `UNIQUE (org_unit_id, fingerprint)` is
 * what refuses the same Question being filed twice for one process, however a
 * person re-typed or re-pasted it — a bank pasted from two documents is exactly
 * where the same sentence turns up twice, and a paper that draws it twice
 * measures one fact double. The cost is deliberate: a near-duplicate that is
 * meant (same stem, a different key) is refused too, and the author corrects
 * the existing Question with a PATCH instead of filing a second one. A retired
 * Question still holds its fingerprint, so pasting it again is refused rather
 * than silently making a second copy.
 *
 * **`is_active`, not DELETE.** A Question that has been drawn onto a paper is
 * referenced by it `ON DELETE RESTRICT` (a later slice), so a bank row is
 * never removed; retiring it takes it out of every future draw and leaves the
 * papers that already carry it intact.
 *
 * **`org_unit_id` is the only scope.** A Question belongs to one process and
 * the draw is an exact match on it — no descendants — so a Section paper never
 * scores a Braiding operator on Cutting. A Team Leader who wants a Section-wide
 * paper files the Questions at the Section.
 *
 * **`explanation` is optional.** It says why the key is right and is shown on
 * the result after marking; a bank is usable before anyone has written one, so
 * the column is nullable rather than forcing a placeholder sentence.
 *
 * The deny-all RLS floor is switched on in this same migration (ADR-0004),
 * with `attach_updated_at`, `attach_actor_columns` and `attach_audit` as
 * `1801600000000_training-records.js` pairs them for a table whose rows are
 * edited in place.
 *
 * Backward-compatible per ADR-0007: a new table changes nothing an older
 * running image reads or writes.
 */

exports.shorthands = undefined;

exports.up = (pgm) => {
  pgm.sql(`
    CREATE TABLE assessment_questions (
      id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      org_unit_id BIGINT NOT NULL REFERENCES org_units (id),
      question_text TEXT NOT NULL,
      question_text_fingerprint TEXT GENERATED ALWAYS AS
        (md5(lower(regexp_replace(btrim(question_text), '\\s+', ' ', 'g')))) STORED,
      option_a TEXT NOT NULL,
      option_b TEXT NOT NULL,
      option_c TEXT NOT NULL,
      correct_option CHAR(1) NOT NULL,
      explanation TEXT,
      is_active BOOLEAN NOT NULL DEFAULT TRUE,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by BIGINT,
      updated_by BIGINT,

      CONSTRAINT assessment_questions_org_unit_fingerprint_key
      UNIQUE (org_unit_id, question_text_fingerprint),
      CONSTRAINT assessment_questions_correct_option_check
      CHECK (correct_option IN ('A', 'B', 'C')),
      CONSTRAINT assessment_questions_text_not_blank
      CHECK (length(btrim(question_text)) BETWEEN 5 AND 2000),
      CONSTRAINT assessment_questions_options_not_blank
      CHECK (btrim(option_a) <> '' AND btrim(option_b) <> '' AND btrim(option_c) <> ''),
      CONSTRAINT assessment_questions_options_distinct
      CHECK (option_a <> option_b AND option_a <> option_c AND option_b <> option_c),
      CONSTRAINT assessment_questions_explanation_not_blank
      CHECK (explanation IS NULL OR length(btrim(explanation)) BETWEEN 1 AND 2000)
    )
  `);

  pgm.sql(`
    CREATE INDEX assessment_questions_org_unit_active_idx
      ON assessment_questions (org_unit_id) WHERE is_active
  `);

  pgm.sql(`SELECT attach_updated_at('assessment_questions')`);
  pgm.sql(`SELECT attach_actor_columns('assessment_questions')`);
  pgm.sql(`SELECT attach_audit('assessment_questions')`);

  pgm.sql('ALTER TABLE assessment_questions ENABLE ROW LEVEL SECURITY');
};

exports.down = (pgm) => {
  // Forward-only in production per ADR-0007 — this exists for local
  // development and for node-pg-migrate's requirement that a migration
  // define both directions.
  pgm.sql('ALTER TABLE assessment_questions DISABLE ROW LEVEL SECURITY');
  pgm.sql('DROP TRIGGER IF EXISTS assessment_questions_audit ON assessment_questions');
  pgm.sql('DROP TRIGGER IF EXISTS zz_assessment_questions_set_actor ON assessment_questions');
  pgm.sql('DROP TRIGGER IF EXISTS assessment_questions_set_updated_at ON assessment_questions');
  pgm.sql('DROP TABLE IF EXISTS assessment_questions');
};
