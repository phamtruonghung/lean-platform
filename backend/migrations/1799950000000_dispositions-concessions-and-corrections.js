/**
 * Dispositions, Concessions and the corrections to a Non-conformance (issue
 * #206, the Quality Module's second behaviour beyond its catalogues).
 *
 * The baseline's `quality_dispositions` table already carries almost everything
 * dealing with bad product in parts needs: the kind of Disposition, the
 * quantity it covers, the unit, `rework_minutes` for the rework half of cost
 * of poor quality, the moment it was decided, `approval_ref` for the deviation
 * number an auditor asks for and `notes`. It also carries
 * `quantity_dispositioned` on `quality_issues`, kept by the baseline's own
 * `quality_dispositions_sync` trigger, so "how much is still sitting in the
 * quarantine cage undecided" is already an indexed question.
 *
 * Two things are added, and they are the two issue #200's spec names.
 *
 * First, **who decided it as an Account**: `quality_dispositions.decided_by_account_id`.
 * The baseline's `decided_by` references `employees`, which is the right shape
 * for the floor-device path (ADR-0016, issue #207) where a shared terminal
 * identifies the person standing at it, and the wrong shape for a signed-in
 * operator or an administrator — an administrator need not be an Employee at
 * all, and a Concession's whole point is that the name of whoever granted it
 * stays on the record. So the Account gets its own column beside the Employee
 * one, exactly as `quality_issues.recorded_by_account_id` sits beside
 * `detected_by` after issue #205, and nullable for the same reason: a row that
 * arrived from the floor device, an import or the API has no Account behind it.
 * **For a Concession this column IS the granting Account** — there is no second
 * column for it, because a Concession is a Disposition like the others and a
 * second column saying the same thing twice would be a value two writers could
 * disagree about.
 *
 * Second, **the note and the actor for a correction**: `quality_issue_corrections`.
 * Issue #200's spec deliberately left this open — "either columns on a small
 * Non-conformance event table or the quantity-history table generalised to
 * Non-conformance events; the implementer picks one, but every such change must
 * be readable back over HTTP with who and when". This migration picks the small
 * event table, and the argument is the history table's own invariant:
 * `quality_issue_quantity_changes` carries `new_quantity > previous_quantity` as
 * a CHECK, which is a statement about a *quantity* — the table's name, its
 * columns and its constraint all say so. Lowering a severity, reopening a
 * record and cancelling one have no quantity to compare; generalising that
 * table would mean either weakening the CHECK that makes a decrease
 * unrepresentable (the belt-and-braces issue #205's own header argues for) or
 * filling a table named for quantities with rows whose quantities are
 * meaningless. The two histories also answer different questions and are read
 * at different places on the Screen: how much product there is, against which
 * state the record is in. So: one row per correction, carrying what changed,
 * the note a holder of Quality authority wrote, and the Account that made the
 * decision and the moment it was made — which is the "who and when" the
 * criterion asks to be readable back.
 *
 * **Nothing here changes what already exists.** No column is renamed or
 * dropped, no constraint is loosened, the baseline's `quality_dispositions_sync`
 * trigger is left exactly as it is, and the automatic closing of a
 * Non-conformance whose whole quantity has a Disposition is decided in
 * `nonconformances.js` at the moment a Disposition is recorded rather than in a
 * replaced trigger — so an older image running against this schema behaves
 * exactly as it did before (ADR-0007, expand now, contract later).
 *
 * The new table gets the deny-all RLS floor switched on in this same
 * migration, because ADR-0004's sweep ran once against the catalog as it stood
 * then and a table added afterwards does not inherit it — see the statement's
 * own comment where it sits. `attach_updated_at` is installed on it so it
 * carries the same two timestamps every other table does; the audit trigger is
 * deliberately not attached, since this table is itself an audit trail and a
 * second copy of every row in `audit_log` would double the write for no reader.
 * No data migration: no existing row has a deciding Account, and no existing
 * row has a correction to reconstruct.
 */

exports.shorthands = undefined;

exports.up = (pgm) => {
  pgm.sql(`
    ALTER TABLE quality_dispositions
      ADD COLUMN decided_by_account_id BIGINT REFERENCES app_users (id)
  `);

  pgm.sql(`
    CREATE TABLE quality_issue_corrections (
      id                 BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      quality_issue_id   BIGINT      NOT NULL
                                     REFERENCES quality_issues (id) ON DELETE CASCADE,
      -- The three corrections issue #206 names, and only those: the set is
      -- repeated in nonconformances.js so a caller gets a sentence naming the
      -- field rather than a raw constraint violation.
      kind               TEXT        NOT NULL
                                     CHECK (kind IN ('severity_lowered', 'reopened',
                                                     'cancelled')),

      -- What the record was and what it became. Which pair carries values
      -- depends on the kind, so both pairs are nullable and the CHECK below
      -- says which kind must fill which.
      previous_severity  TEXT,
      new_severity       TEXT,
      previous_status    TEXT,
      new_status         TEXT,

      -- The note the decision is taken with. NOT NULL: a correction with no
      -- reason on it is exactly the row an auditor cannot use, and issue #206
      -- requires a note for each of them.
      note               TEXT        NOT NULL CHECK (btrim(note) <> ''),

      -- Who decided, and when. The Account is required — every correction in
      -- this slice is made by a signed-in holder of Quality authority, and an
      -- unattributed correction to a record quoted in an audit finding is
      -- worse than no record of it.
      corrected_by_account_id BIGINT NOT NULL REFERENCES app_users (id),
      corrected_at       TIMESTAMPTZ NOT NULL DEFAULT now(),

      created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by         BIGINT,
      updated_by         BIGINT,

      CONSTRAINT quality_issue_corrections_severity
        CHECK (kind <> 'severity_lowered'
               OR (previous_severity IS NOT NULL AND new_severity IS NOT NULL)),
      CONSTRAINT quality_issue_corrections_status
        CHECK (kind NOT IN ('reopened', 'cancelled')
               OR (previous_status IS NOT NULL AND new_status IS NOT NULL))
    )
  `);

  pgm.sql(`
    CREATE INDEX quality_issue_corrections_issue_idx
      ON quality_issue_corrections (quality_issue_id, corrected_at, id)
  `);

  pgm.sql(`SELECT attach_updated_at('quality_issue_corrections')`);

  // The deny-all floor, on the table this migration creates (ADR-0004, and
  // `rls.test.js` asserts it on every base table). The sweep in
  // 1756000000002_deny-all-rls.js enumerated the catalog **once**, against the
  // tables that existed when it ran, so a table a later migration adds does
  // not inherit it — every migration that creates one enables it itself, the
  // same line action-phases.js and inventory-parts-stores-and-stock.js carry.
  // No policies are added, here or anywhere: deny-all with zero policies is
  // the whole rule, and the API's own connection is the table's owner, which
  // ignores RLS regardless. `powerbi_reader`'s SELECT already reaches this
  // table through the `ALTER DEFAULT PRIVILEGES` that migration set, since
  // Postgres evaluates default privileges at object-creation time — so there
  // is nothing to grant here.
  pgm.sql('ALTER TABLE quality_issue_corrections ENABLE ROW LEVEL SECURITY');
};

exports.down = (pgm) => {
  // Forward-only in production per ADR-0007 — this exists for local
  // development and for node-pg-migrate's own requirement that a migration
  // define both directions. The corrections are dropped with the table and are
  // not recoverable from the record, which holds only its current state: that
  // is why the `up` is a one-way door.
  pgm.sql('ALTER TABLE quality_issue_corrections DISABLE ROW LEVEL SECURITY');
  pgm.sql('DROP TABLE quality_issue_corrections');
  pgm.sql('ALTER TABLE quality_dispositions DROP COLUMN decided_by_account_id');
};
