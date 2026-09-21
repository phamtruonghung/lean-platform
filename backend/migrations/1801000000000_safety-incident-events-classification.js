/**
 * Widens `safety_incident_events.kind` to add `classification` (issue #224's
 * last unmet acceptance criterion: "Classification changes are kept in the
 * incident event history with who and when, like severity and status
 * changes").
 *
 * #224's own "no migration" line was about the injury classification's three
 * structured fields — `injury_types`, `body_parts`, and `safety_incidents`'s
 * own `employee_id`/`injury_type_id`/`body_part_id` columns, all already
 * present on the baseline row before this ticket touched anything. It said
 * nothing about `safety_incident_events`, a table #228 (migration
 * 1800900000000) created afterwards with a `kind` CHECK enumerating exactly
 * the four kinds *that ticket* named — `severity`, `status`, `days`,
 * `closure` — and no opinion, one way or the other, about a fifth. Leaving
 * `classifySafetyIncident` (`safety-incidents.js`) writing nothing to that
 * table was a gap against #224's own criterion, not a decision this
 * migration reverses; closing it is squarely inside #224's stated scope even
 * though #224 predates the table it now writes to.
 *
 * Per ADR-0007 (expand now, contract later): this only widens an existing
 * CHECK to accept one more value a running older image never writes — no
 * column changes, no data migration, nothing an already-deployed image reads
 * or writes differently. `safety_incident_events_kind_check` is the name
 * Postgres gave the table's original inline, unnamed column CHECK
 * (confirmed against a live database with `pg_get_constraintdef`, not
 * assumed); dropping and recreating it under the same name means nothing
 * else — no other migration, no application code — has to know its name
 * changed.
 *
 * `safety_incident_events_values_present` (both `previous_value` and
 * `new_value` NOT NULL) and `safety_incident_events_note_required` (a note
 * required only for `severity`/`closure`) are both untouched: a
 * `classification` row needs no note, the same standing `days` and `status`
 * rows already have, and it carries a previous/new value pair the same as
 * every other kind — see `classifySafetyIncident`'s own doc comment in
 * `safety-incidents.js` for the TEXT encoding chosen.
 */

exports.shorthands = undefined;

const CONSTRAINT_NAME = 'safety_incident_events_kind_check';

exports.up = (pgm) => {
  pgm.sql(`ALTER TABLE safety_incident_events DROP CONSTRAINT ${CONSTRAINT_NAME}`);
  pgm.sql(`
    ALTER TABLE safety_incident_events
      ADD CONSTRAINT ${CONSTRAINT_NAME}
      CHECK (kind IN ('severity', 'status', 'days', 'closure', 'classification'))
  `);
};

exports.down = (pgm) => {
  // Forward-only in production per ADR-0007 — this exists for local
  // development and node-pg-migrate's own requirement that a migration
  // define both directions. A `classification` row cannot satisfy the
  // narrower four-value CHECK this restores, so any such row is deleted
  // first: the same trade-off 1800900000000's own `down` makes for the whole
  // table (dropping it loses the history outright), scoped here to only the
  // rows this migration's `up` made possible.
  pgm.sql(`DELETE FROM safety_incident_events WHERE kind = 'classification'`);
  pgm.sql(`ALTER TABLE safety_incident_events DROP CONSTRAINT ${CONSTRAINT_NAME}`);
  pgm.sql(`
    ALTER TABLE safety_incident_events
      ADD CONSTRAINT ${CONSTRAINT_NAME}
      CHECK (kind IN ('severity', 'status', 'days', 'closure'))
  `);
};
