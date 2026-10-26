/**
 * The reason an amendment gives (issue #338, spec #332, ADR-0054).
 *
 * A sealed Shift handover is never edited in place: a correction is a new
 * version that names the one it replaces in `supersedes_id`. Both versions
 * stay readable, and the newer one carries why it was written —
 * `amendment_reason`, NULL on a version 1, which replaces nothing.
 *
 * Backward-compatible per ADR-0007: a new nullable column with no default is
 * one an older running image neither reads nor writes.
 */

exports.shorthands = undefined;

exports.up = (pgm) => {
  pgm.sql('ALTER TABLE shift_handovers ADD COLUMN amendment_reason TEXT');
};

exports.down = (pgm) => {
  // Forward-only in production per ADR-0007 — this exists for local
  // development.
  pgm.sql('ALTER TABLE shift_handovers DROP COLUMN IF EXISTS amendment_reason');
};
