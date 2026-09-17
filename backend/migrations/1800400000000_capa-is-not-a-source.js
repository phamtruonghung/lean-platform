/**
 * `capa_id` is not a source (issue #221).
 *
 * The baseline's `action_items_single_source` CHECK counts ten columns and
 * requires at most one of them to be set, which is the right rule for nine of
 * the ten: `quality_issue_id`, `safety_incident_id`, `safety_observation_id`,
 * `downtime_event_id`, `customer_complaint_id`, `supplier_ncr_id`,
 * `kpi_actual_id`, `tier_meeting_id` and `work_order_id` each answer the same
 * question — *what raised this Action* — and an Action raised from two records
 * at once is a caller who has not decided which problem they are reporting. The
 * tenth, `capa_id`, answers a different one: *what did this Concern become*. A
 * source and a result are not alternatives; they are a fact and its
 * consequence, and a Concern that has an investigation opened on it is the
 * Concern that was raised from something.
 *
 * Counting them together made the Quality Module's central path unreachable.
 * `POST /api/actions/:id/capa` (issue #209) opens an investigation on a
 * Concern by setting `action_items.capa_id`, and issue #208's route raises a
 * Concern from a Non-conformance by setting `action_items.quality_issue_id`.
 * The two together violate the constraint, the insert fails with SQLSTATE
 * `23514`, `actions.js`'s `mapCapaWriteError` has no mapping for that
 * constraint name, and the caller is answered a 500 rather than a refusal
 * naming anything. That is the path ADR-0034 and issue #200 describe as the
 * Module's whole reason for existing: "someone raises a Concern from the
 * Non-conformance in the Action log. When a Concern needs a formal
 * investigation, someone holding Quality authority opens a CAPA on it."
 *
 * So this migration **narrows** the constraint rather than dropping it or
 * relaxing it: the nine genuine source columns still sum to at most one, and
 * the constraint keeps its own name, because a later reader greps for
 * `action_items_single_source` to find the rule and a renamed constraint is a
 * rule that has gone missing. Allowing the pair generally — dropping the
 * constraint, or making the sum `<= 2` — would let an Action be raised from two
 * different records at once, which is the mistake the rule exists to catch and
 * has nothing to do with this bug.
 *
 * `capa_id`'s own rules are untouched and are stated elsewhere in the schema
 * exactly as issue #209 left them: `action_items_capa_id_once` (a partial
 * unique index) keeps one CAPA to one Concern, and `action_items_capa_is_a_concern`
 * keeps `capa_id` on a Concern and on nothing else. Dropping the column from
 * this sum takes nothing away from either of them.
 *
 * The baseline's generated `source_type` column is deliberately left exactly as
 * it was written. It is a read-side label, it names `capa` among its cases and
 * it is not consulted by the constraint, so no row's meaning changes here: the
 * combination this migration newly permits resolves to `quality_issue` (that
 * case is tested first), which is the provenance a reader is asking for. A
 * later ticket that wants the label to say something different about a Concern
 * that became a CAPA is changing that column's own contract, which is a
 * separate decision with its own migration, not a side effect of narrowing this
 * one.
 *
 * **Expand-safe (ADR-0007).** No column is added, dropped, renamed or
 * re-typed, no row is back-filled and no data is touched; only a row-level
 * CHECK is replaced, and the replacement is strictly more permissive than the
 * rule it replaces. An image from before this migration keeps running against
 * the migrated schema unchanged: every Action it could write it can still
 * write, and the only rows it could not write are rows it never wrote either.
 * The widening is visible to it as nothing at all, which is the whole point of
 * expand-now: contract-later. Nothing is contracted here and there is no later
 * form of this constraint to land.
 *
 * `action_items` is not a table this migration creates, so there is no RLS
 * obligation of its own here — the baseline carries the deny-all floor
 * (ADR-0004) and the column set is not being widened.
 */

exports.shorthands = undefined;

exports.up = (pgm) => {
  // The baseline's rule first, then its narrowed replacement — a drop followed
  // by an add in one step, so there is no window in which the table carries no
  // rule at all. The name is the baseline's own, on purpose: see the header.
  pgm.sql('ALTER TABLE action_items DROP CONSTRAINT action_items_single_source');
  pgm.sql(`
    ALTER TABLE action_items
      ADD CONSTRAINT action_items_single_source
      CHECK (
        (quality_issue_id      IS NOT NULL)::int +
        (safety_incident_id    IS NOT NULL)::int +
        (safety_observation_id IS NOT NULL)::int +
        (downtime_event_id     IS NOT NULL)::int +
        (customer_complaint_id IS NOT NULL)::int +
        (supplier_ncr_id       IS NOT NULL)::int +
        (kpi_actual_id         IS NOT NULL)::int +
        (tier_meeting_id       IS NOT NULL)::int +
        (work_order_id         IS NOT NULL)::int <= 1
      )
  `);
};

exports.down = (pgm) => {
  // Forward-only in production per ADR-0007 — this exists for local
  // development and for node-pg-migrate's own requirement that a migration
  // define both directions. It restores the baseline's rule verbatim, including
  // the counting of `capa_id`, which is only safe against a database whose
  // Concerns have no investigations open: the `capa_id` term is what makes the
  // Quality Module's own path a 500, and that is the bug this file fixes.
  pgm.sql('ALTER TABLE action_items DROP CONSTRAINT action_items_single_source');
  pgm.sql(`
    ALTER TABLE action_items
      ADD CONSTRAINT action_items_single_source
      CHECK (
        (quality_issue_id      IS NOT NULL)::int +
        (safety_incident_id    IS NOT NULL)::int +
        (safety_observation_id IS NOT NULL)::int +
        (downtime_event_id     IS NOT NULL)::int +
        (capa_id               IS NOT NULL)::int +
        (customer_complaint_id IS NOT NULL)::int +
        (supplier_ncr_id       IS NOT NULL)::int +
        (kpi_actual_id         IS NOT NULL)::int +
        (tier_meeting_id       IS NOT NULL)::int +
        (work_order_id         IS NOT NULL)::int <= 1
      )
  `);
};
