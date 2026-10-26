/**
 * The Production Module's two tier-board numbers (issue #340, spec #332,
 * ADR-0054): how many of a Section's shifts were handed over and accepted,
 * and how long the acceptance took. Both sit under Delivery, beside the
 * maintenance KPIs, for the reason those do: a handover is done so the next
 * shift runs, and a red Delivery day should be traceable to the handover that
 * did not happen.
 *
 * **These two are read live, not frozen.** A handover's own snapshot numbers
 * are written once at submit and never recomputed (ADR-0054); these are the
 * opposite kind — counts over handovers that the board computes on read
 * (maintenance/board.js's header), so a late acknowledgement moves them the
 * moment it is recorded.
 *
 * **`source_view` names the table, not a view.** The arithmetic lives in
 * `production/kpi-registry.js`, whose two entries carry `compute`, so nothing
 * reads this column for them. It cannot be NULL all the same: the baseline's
 * `kpi_definitions_derived_has_view` CHECK requires one on every `derived`
 * row, and the board only computes `derived` rows. `shift_handovers` is the
 * table the numbers come from, the same reading `QUA_OPEN_NC`'s
 * `quality_issues` already takes. For the same reason `aggregation` is
 * descriptive only — `avg` is the nearest the CHECK allows to the median
 * `PRO_HANDOVER_ACK_MINUTES` actually takes, and `formula_text` says so where
 * the reader of the number sees it.
 *
 * Idempotent by code (`ON CONFLICT (code) DO NOTHING`), as the baseline's own
 * catalogue inserts are. Backward-compatible per ADR-0007: two new catalogue
 * rows an older running image reports as `no_data`, because no registry it
 * carries names them.
 */

exports.shorthands = undefined;

const CODES = ['PRO_HANDOVER_COMPLETION', 'PRO_HANDOVER_ACK_MINUTES'];

exports.up = (pgm) => {
  pgm.sql(`
    INSERT INTO kpi_definitions
      (code, name, pillar_code, unit, aggregation, direction, calculation_type,
       source_view, decimal_places, formula_text, description, sort_order)
    VALUES
      ('PRO_HANDOVER_COMPLETION', 'Shift handover completion', 'D', '%', 'ratio', 'higher_better',
       'derived', 'shift_handovers', 1,
       'shift handovers acknowledged by the incoming Team Leader / section shifts that have ended',
       'A shift counts once it has ended; a shift still running is not held against the section yet. A handover counts once the incoming Team Leader has acknowledged it — a submitted handover nobody has accepted is not a handover done. An amendment needs acknowledging again before it counts.',
       20),
      ('PRO_HANDOVER_ACK_MINUTES', 'Shift handover acknowledgement time', 'D', 'minutes', 'avg', 'lower_better',
       'derived', 'shift_handovers', 0,
       'median minutes from the start of the shift to the acknowledgement of its handover',
       'The median, not the mean: one handover acknowledged the next morning would otherwise outweigh a week of prompt ones. Measured from the shift''s own start, the plant''s calendar, not from when the handover was submitted. Only acknowledged handovers are measured.',
       21)
    ON CONFLICT (code) DO NOTHING
  `);
};

exports.down = (pgm) => {
  // Forward-only in production per ADR-0007 — this exists for local
  // development.
  pgm.sql(`DELETE FROM kpi_definitions WHERE code IN (${CODES.map((code) => `'${code}'`).join(', ')})`);
};
