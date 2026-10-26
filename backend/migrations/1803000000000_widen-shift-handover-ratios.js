/**
 * Widens the four ratio columns of a Shift handover's snapshot — `oee`,
 * `availability`, `performance`, `quality` — from NUMERIC(7,4) to
 * NUMERIC(12,6) (issue #334, ADR-0054).
 *
 * NUMERIC(7,4) stops at 999.9999. Performance is theoretical minutes over run
 * minutes, and `v_shift_oee` does not clamp it: a cycle time that is wrong in
 * the master data can put it far above 1 — which is what `performance_suspect`
 * exists to flag — and a value past the column's bound made submit fail with
 * a numeric overflow instead of sealing the handover. The snapshot records
 * what the view said, suspect or not, so the column is widened rather than the
 * number clamped. OEE is A × P × Q and inherits the same range; availability
 * and quality are widened alongside so the four read at one precision.
 *
 * Backward-compatible per ADR-0007: a widening type change keeps every value
 * an older running image wrote, and an older image reads the wider column the
 * same way (pg returns NUMERIC as a string either way).
 */

exports.shorthands = undefined;

const COLUMNS = ['oee', 'availability', 'performance', 'quality'];

exports.up = (pgm) => {
  pgm.sql(`
    ALTER TABLE shift_handovers
      ${COLUMNS.map((column) => `ALTER COLUMN ${column} TYPE NUMERIC(12,6)`).join(',\n      ')}
  `);
};

exports.down = (pgm) => {
  // Forward-only in production per ADR-0007 — this exists for local
  // development. Narrowing rounds to four places and fails on any row whose
  // ratio is 1000 or more, which is the point of the widening.
  pgm.sql(`
    ALTER TABLE shift_handovers
      ${COLUMNS.map((column) => `ALTER COLUMN ${column} TYPE NUMERIC(7,4)`).join(',\n      ')}
  `);
};
