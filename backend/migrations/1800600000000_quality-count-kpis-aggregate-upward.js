/**
 * How the board rolls the two Quality count KPIs up the Org Unit tree
 * (issue #216).
 *
 * `kpi_definitions.aggregation` is what `maintenance/board.js` reads to decide
 * how a KPI's source rows combine when a caller asks for an Org Unit and
 * everything beneath it. The baseline seeds `QUA_OPEN_NC` and
 * `QUA_OVERDUE_CAPA` with `'last'`, which board.js implements as "the value on
 * the newest dated row in the period" — the shape a *materialised* daily
 * snapshot has, one row per Org Unit per production day, which is what this
 * schema's own `kpi_actuals` world was built around. This Platform computes on
 * read, and its registry entries name a source that carries one row per Org
 * Unit for the state right now. Read as `'last'`, that source answers with ONE
 * Org Unit's count — whichever row the database happened to return first among
 * rows that all carry the same date — rather than with the count for the
 * subtree the caller asked about. That is a wrong number, not a missing one,
 * and `QUA_OPEN_NC`'s own criterion is "for the chosen Org Unit and beneath
 * it".
 *
 * `'sum'` is the aggregation that reads it correctly: the source rows are
 * per-Org-Unit counts, so adding the matching ones IS the subtree total. It is
 * also the choice the baseline already made for Maintenance's own snapshot KPI,
 * `MNT_BACKLOG` — a `'sum'` over a per-Org-Unit value with no date column at
 * all, because there is no "backlog for last Tuesday" either.
 *
 * **Nothing else changes, and the change is deliberately the smallest one that
 * could work.** No table, no column and no constraint is touched: two seeded
 * rows have one metadata value corrected, the unit, the direction, the formula,
 * the sort order and the code all staying exactly as they were. `aggregation` is
 * read by the board service and by nothing else — no view, no function and no
 * other service in this backend selects it — so a version of the code that
 * predates this migration is unaffected by it: that image has no Quality
 * registry entries at all, and answers `no_data` for both codes whatever the
 * column says.
 *
 * **Expand-safe (ADR-0007).** The `up` is a data update, so the schema the
 * previous image expects is still there; the only thing an older image can see
 * differently is a column value it does not read.
 */

exports.shorthands = undefined;

exports.up = (pgm) => {
  pgm.sql(`
    UPDATE kpi_definitions
       SET aggregation = 'sum'
     WHERE code IN ('QUA_OPEN_NC', 'QUA_OVERDUE_CAPA')
       AND aggregation = 'last'
  `);
};

exports.down = (pgm) => {
  // Forward-only in production per ADR-0007 — this exists for local
  // development and for node-pg-migrate's own requirement that a migration
  // define both directions. It restores what the baseline seeded, which is the
  // reading that cannot roll a per-Org-Unit source up the tree.
  pgm.sql(`
    UPDATE kpi_definitions
       SET aggregation = 'last'
     WHERE code IN ('QUA_OPEN_NC', 'QUA_OVERDUE_CAPA')
       AND aggregation = 'sum'
  `);
};
