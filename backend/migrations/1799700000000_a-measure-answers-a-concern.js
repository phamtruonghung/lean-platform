/**
 * A measure names the Concern it answers (issue #178, ADR-0032).
 *
 * A Concern is answered by a Containment that stops its effect now, a
 * Countermeasure that removes its cause, or a Preventive action that stops the
 * same failure appearing somewhere else. Each of those is an Action of its own
 * — its own cycle, its own owner, its own number — and until now nothing could
 * say which Concern one was about: `action_items` has ten source columns and
 * not one of them can point at another Action.
 *
 * The link is a self-reference, and there was no alternative. The schema's own
 * source columns all point at records of other kinds (`quality_issue_id`,
 * `capa_id`, `kpi_actual_id`, …), which is the right shape for "which record
 * raised this" and the wrong shape for "which problem does this answer". A
 * `(source_type, source_id)` pair would have covered it and thrown referential
 * integrity away — the same argument the baseline's own `capas` and
 * `action_items` headers make for preferring a mostly-null foreign key to a
 * pair pointing into space.
 *
 * `source_type` deliberately does NOT change. It answers "which record of
 * another kind raised this" — the generated CASE still reports whatever the ten
 * source columns say, and `standalone` for a measure raised against a concern
 * that was itself raised standalone. A parent is not a source.
 *
 * Nullable, and a measure without one is complete: a Containment fitted on the
 * spot answers nothing, runs its own cycle and closes on its own Act. Forcing
 * every measure to name a Concern would turn a quick fix into two records, the
 * second of which is a fabricated problem.
 *
 * ## The one-level rule is not a constraint
 *
 * "A measure answers a Concern, and a measure is never answered by another
 * measure" cannot be a CHECK: a constraint sees one row and cannot read the
 * parent's own `action_type` or its `parent_action_item_id`. It is enforced in
 * `actions.js`, over a `SELECT … FOR UPDATE` of the parent inside the same
 * transaction that inserts the measure — the shape ADR-0019 argues for the
 * Work order's own transitions (the service owns what a legal move is; the
 * database owns what a row may be). A trigger could hold it in the database,
 * and would be the first trigger this Module owns; the guard is taken in the
 * service instead because it needs three different refusals with three
 * different messages, which a constraint cannot produce anyway.
 *
 * No RLS obligation accompanies this migration: it adds no table, and
 * `1756000000002_deny-all-rls.js` enabled the floor on `action_items` when it
 * swept the tables that existed then.
 */

exports.shorthands = undefined;

exports.up = (pgm) => {
  pgm.sql(`
    ALTER TABLE action_items
      ADD COLUMN parent_action_item_id BIGINT REFERENCES action_items (id)
  `);

  // The read behind a Concern's own Screen — "what answers this" — and behind
  // the register's measure count. Partial, because every Action raised
  // standalone (which is most of them, and every Concern) has no parent and
  // does not belong in this index.
  pgm.sql(`
    CREATE INDEX action_items_parent_idx
      ON action_items (parent_action_item_id)
      WHERE parent_action_item_id IS NOT NULL
  `);
};

exports.down = (pgm) => {
  // Forward-only in production per ADR-0007 — this exists for local
  // development and for node-pg-migrate's own requirement that a migration
  // define both directions.
  pgm.sql('DROP INDEX action_items_parent_idx');
  pgm.sql('ALTER TABLE action_items DROP COLUMN parent_action_item_id');
};
