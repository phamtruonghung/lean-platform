/**
 * The Safety incident event history table (issue #228) — the record of what
 * changed on an already-recorded incident, who changed it, and when.
 *
 * #226 (migration 1756000000000, the baseline) gave `safety_incidents` its
 * own state: the severity ladder, the status ladder, `lost_time_days` and
 * `restricted_days`, `investigation_due_at`, `closed_at`. This migration adds
 * nothing to that row. What it adds is the table that answers "what happened
 * to this record after it was written down" — the same question
 * `quality_issue_corrections` (migration 1799950000000) answers for a
 * Non-conformance, and the closest prior art this table follows.
 *
 * **One table, not four.** `quality_issue_corrections` chose a small event
 * table over generalising `quality_issue_quantity_changes`, because that
 * table's own CHECK (`new_quantity > previous_quantity`) is a statement about
 * a *quantity* that a status or a severity change has no counterpart for.
 * Here there is no such table to protect: a Safety incident's four kinds of
 * change — a severity correction, a status move, a days record, a closure —
 * share the same shape (something changed from one value to another, someone
 * changed it, and some of them need a reason), so one table with a `kind`
 * column is the honest fit, not four single-purpose ones. `kind` is
 * `severity | status | days | closure`, matching #228's own list, one row
 * per change, oldest first.
 *
 * **`previous_value`/`new_value` are TEXT, not one typed pair per kind.**
 * `quality_issue_corrections` gave itself two typed pairs
 * (`previous_severity`/`new_severity`, `previous_status`/`new_status`)
 * because it only ever had two kinds of value to hold. This table's `days`
 * kind carries two numbers at once — lost-time and restricted — which no
 * single typed column pair represents without inventing a second pair just
 * for it, and a fifth column pair here would leave three of every row's four
 * kinds carrying nothing in it, the exact "meaningless columns filled in"
 * `quality_issue_corrections`' own header rejects for a different table. A
 * `days` row's TEXT is `lostTimeDays=<n>,restrictedDays=<n>` for both the
 * value before and the value after; `severity` and `status` rows hold the
 * enum word itself; a `closure` row holds the status the incident was in
 * before (`previous_value`) and the literal `closed` (`new_value`). This is
 * an audit trail read back as a list on a Screen, never joined or grouped by
 * its value — nothing here needs the value typed to be queried.
 *
 * **The note is required only where #228 requires one.** Changing the
 * severity and closing the incident each need a note (#228's own acceptance
 * criteria: 400 without one); an ordinary status move and a days record do
 * not. `safety_incident_events_note_required` states that per `kind`, the
 * same shape `quality_issue_corrections_severity`/`_status` state which kind
 * must fill which value pair.
 *
 * **Why "the days were settled" needs no new column on `safety_incidents`.**
 * #228 requires that closing an incident above the no-injury rung refuse
 * (409) until "the days settled — zero being an answer". `lost_time_days` and
 * `restricted_days` already default to zero on every row, so a column read
 * alone can never distinguish "recorded as zero on purpose" from "never
 * looked at" — the exact distinction that refusal exists to enforce. Rather
 * than adding a column to `safety_incidents` this ticket does not otherwise
 * ask for, the API (`safety-incidents.js`) answers the question by asking
 * this table instead: an incident's days count as settled once a `days`
 * event has been written for it, whatever numbers that event recorded. This
 * is the same kind of decision `nonconformances.js`'s `settleDispositionStatus`
 * makes — state derived from a history table's own rows rather than a second
 * place to keep it — chosen here to keep this migration to the one table
 * issue #228 names, and nothing else.
 *
 * **Who: an Account or an identified Employee, both nullable.** Every write
 * this ticket adds reaches this table through a signed-in Account — setting a
 * due date, moving status, changing severity, recording days and closing are
 * all gated on an edit Grant or Safety authority, and neither exists without
 * an Account. `changed_by_employee_id` is added beside
 * `changed_by_account_id` anyway, unused by anything in this slice, for the
 * same reason `safety_incidents.reported_by` sits beside
 * `recorded_by_account_id`: a floor device is the Platform's other door onto
 * a Safety incident (ADR-0016, issue #227), and a later ticket that lets a
 * device correct or close what it reported should find the column already
 * here rather than a second migration to add it. Neither column is NOT NULL
 * and no CHECK requires one of the two to be set — `safety_incidents` itself
 * makes the same choice for its own two actor columns and trusts the two
 * doors (`safety-incident-routes.js`, `floor-safety-incident-routes.js`) to
 * never call in with neither, rather than a database constraint restating
 * it.
 *
 * The deny-all RLS floor is switched on in this same migration (ADR-0004):
 * the one-time sweep in 1756000000002_deny-all-rls.js enumerated the catalog
 * as it stood then, so a table created afterwards does not inherit it and
 * every migration that creates one carries its own `ENABLE ROW LEVEL
 * SECURITY`, the same line every table since has carried. `attach_updated_at`
 * is installed so the table carries the same two timestamps every other table
 * does; the audit trigger is not attached, since this table is itself an
 * audit trail and a second copy of every row in `audit_log` would double the
 * write for no reader — exactly `quality_issue_corrections`' own reasoning.
 *
 * Backward-compatible per ADR-0007 (expand now, contract later): a new table
 * changes nothing an older running image reads or writes, and no existing row
 * anywhere is touched. No data migration: no Safety incident has a change to
 * its state that predates this table.
 */

exports.shorthands = undefined;

exports.up = (pgm) => {
  pgm.sql(`
    CREATE TABLE safety_incident_events (
      id                     BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      safety_incident_id     BIGINT      NOT NULL
                                         REFERENCES safety_incidents (id) ON DELETE CASCADE,

      -- The four kinds #228 names, and only those — repeated in
      -- safety-incidents.js so a caller never meets a raw constraint
      -- violation for a fifth kind that does not exist.
      kind                   TEXT        NOT NULL
                                         CHECK (kind IN ('severity', 'status', 'days', 'closure')),

      -- What the record was and what it became. TEXT for every kind — see
      -- this migration's own header for why one generic pair fits all four
      -- kinds better than a typed pair per kind.
      previous_value         TEXT,
      new_value              TEXT,

      -- The note the change is taken with. NOT NULL only for the two kinds
      -- #228 requires one on.
      note                   TEXT,

      -- Who changed it — an Account or an identified Employee, both
      -- nullable. See this migration's own header for why neither is
      -- NOT NULL and no CHECK forces one of the two.
      changed_by_account_id  BIGINT      REFERENCES app_users (id),
      changed_by_employee_id BIGINT      REFERENCES employees (id),
      changed_at             TIMESTAMPTZ NOT NULL DEFAULT now(),

      created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by             BIGINT,
      updated_by             BIGINT,

      CONSTRAINT safety_incident_events_values_present
        CHECK (previous_value IS NOT NULL AND new_value IS NOT NULL),
      CONSTRAINT safety_incident_events_note_required
        CHECK (kind NOT IN ('severity', 'closure')
               OR (note IS NOT NULL AND btrim(note) <> ''))
    )
  `);

  pgm.sql(`
    CREATE INDEX safety_incident_events_incident_idx
      ON safety_incident_events (safety_incident_id, changed_at, id)
  `);

  pgm.sql(`SELECT attach_updated_at('safety_incident_events')`);

  // The deny-all floor, on the table this migration creates (ADR-0004, and
  // `rls.test.js` asserts it on every base table). No policies are added:
  // deny-all with zero policies is the whole rule, and the API's own
  // connection is the table's owner, which ignores RLS regardless.
  pgm.sql('ALTER TABLE safety_incident_events ENABLE ROW LEVEL SECURITY');
};

exports.down = (pgm) => {
  // Forward-only in production per ADR-0007 — this exists for local
  // development and for node-pg-migrate's own requirement that a migration
  // define both directions. The history is dropped with the table and is not
  // recoverable from the record, which holds only its current state.
  pgm.sql('ALTER TABLE safety_incident_events DISABLE ROW LEVEL SECURITY');
  pgm.sql('DROP TABLE safety_incident_events');
};
