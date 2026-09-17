/**
 * A Non-conformance records who wrote it down, and every quantity correction
 * it has had (issue #205, the Quality Module's first behaviour beyond its
 * catalogues).
 *
 * The baseline's `quality_issues` table already carries most of what recording
 * a Non-conformance needs — the Product, the Defect code, the detection point,
 * the severity, `quantity_affected`, the trigger-maintained
 * `quantity_dispositioned`, `lot_ref`, `asset_id`, `shift_instance_id`,
 * `detected_by` and `immediate_containment` — and this migration adds only the
 * two things issue #200's spec says are missing.
 *
 * First, **who recorded it as an Account**: `quality_issues.recorded_by_account_id`.
 * `detected_by` is an Employee, which is the right shape for the floor device
 * path (ADR-0016) where a shared terminal identifies the person standing at
 * it; a Non-conformance recorded by a signed-in operator or inspector is a
 * different fact and needs the Account, not the Employee row. It is nullable
 * on purpose: a row that arrived from the floor device, an import or the API
 * has no Account behind it, and a NOT NULL column would force every future
 * writer to invent one. When it is set it names the Account the audit trail
 * already names in `created_by` — this column exists because `created_by` is
 * filled by the shared audit trigger from the transaction's `app.user_id` and
 * is not part of the record a client reads back, while "who recorded this" is
 * a field of the Non-conformance itself.
 *
 * Second, **a quantity-change history**: `quality_issue_quantity_changes`.
 * Sorting a suspect lot finds more pieces than were first counted, and the
 * number on a containment label changes as it does. The baseline's
 * `quantity_affected` is a single mutable number with no memory, so this table
 * is the memory: one row per change, carrying the previous quantity, the new
 * one, who made the change and when, and the note that says why. The who is
 * deliberately either an Account or an identified Employee — the same two
 * shapes the recording itself has — and the CHECK on the table refuses a row
 * that names neither, since an unattributed change to a number quoted in an
 * audit finding is worse than no history at all.
 *
 * **A decrease cannot be written at all.** `quality_issue_quantity_changes`
 * carries `new_quantity > previous_quantity` as a CHECK, so the
 * forward-only rule this slice's route enforces with a 409 is also the only
 * shape the table can hold. That is deliberate belt-and-braces rather than a
 * second implementation: the route produces the sentence a caller reads, and
 * the constraint makes the invariant true of the data whatever a later writer
 * does. Issue #206, which gives a lowering of the affected quantity to a
 * holder of Quality authority, adds its own shape when it arrives; this one
 * contorts nothing to anticipate it.
 *
 * Backward-compatible per ADR-0007 (expand now, contract later): a nullable
 * column and a new table change nothing an older image reads or writes. The
 * new table also gets the deny-all RLS floor switched on in this same
 * migration, because ADR-0004's sweep ran once against the catalog as it stood
 * then and a table added afterwards does not inherit it — see the statement's
 * own comment where it sits. No
 * data migration, because there is nothing to backfill — no existing row has a
 * recorded-by Account, and no existing row has a history to reconstruct from
 * the single number it carries, which is the honest answer rather than a
 * synthesised one. `attach_updated_at` is installed on the new table so it
 * carries the same two timestamps every other table does; the audit trigger
 * is deliberately not attached, since this table is itself an audit trail and
 * a second copy of every row in `audit_log` would double the write for no
 * reader.
 */

exports.shorthands = undefined;

exports.up = (pgm) => {
  pgm.sql(`
    ALTER TABLE quality_issues
      ADD COLUMN recorded_by_account_id BIGINT REFERENCES app_users (id)
  `);

  pgm.sql(`
    CREATE TABLE quality_issue_quantity_changes (
      id                     BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      quality_issue_id       BIGINT      NOT NULL
                                         REFERENCES quality_issues (id) ON DELETE CASCADE,
      previous_quantity      NUMERIC(18,4) NOT NULL CHECK (previous_quantity > 0),
      new_quantity           NUMERIC(18,4) NOT NULL CHECK (new_quantity > 0),
      changed_by_account_id  BIGINT      REFERENCES app_users (id),
      changed_by_employee_id BIGINT      REFERENCES employees (id),
      changed_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
      note                   TEXT,
      created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by             BIGINT,
      updated_by             BIGINT,

      -- A change is an INCREASE, and nothing else can be stored — see this
      -- migration's own header for why the rule lives here as well as in the
      -- route that produces the 409.
      CONSTRAINT quality_issue_quantity_changes_increases
        CHECK (new_quantity > previous_quantity),

      -- Every change is attributed: an Account, or an Employee identified at
      -- a floor device. Naming neither is not a permitted row.
      CONSTRAINT quality_issue_quantity_changes_attributed
        CHECK (changed_by_account_id IS NOT NULL OR changed_by_employee_id IS NOT NULL)
    )
  `);

  pgm.sql(`
    CREATE INDEX quality_issue_quantity_changes_issue_idx
      ON quality_issue_quantity_changes (quality_issue_id, changed_at, id)
  `);

  pgm.sql(`SELECT attach_updated_at('quality_issue_quantity_changes')`);

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
  pgm.sql('ALTER TABLE quality_issue_quantity_changes ENABLE ROW LEVEL SECURITY');

  // The register's own read: a Site's Non-conformances narrowed by Org Unit,
  // status, Defect code, Product, severity and a date range, newest first. The
  // baseline already indexes `(org_unit_id, detected_at DESC)`,
  // `(defect_code_id, detected_at DESC)`, `(product_id, detected_at DESC)` and
  // a partial `(org_unit_id, severity, detected_at DESC)` for open rows; what
  // none of them serves is the recorded-by Account, which a later slice's own
  // "what did this person record" question will ask.
  pgm.sql(`
    CREATE INDEX quality_issues_recorded_by_idx
      ON quality_issues (recorded_by_account_id, detected_at DESC)
      WHERE recorded_by_account_id IS NOT NULL
  `);
};

exports.down = (pgm) => {
  // Forward-only in production per ADR-0007 — this exists for local
  // development and for node-pg-migrate's own requirement that a migration
  // define both directions. The quantity history is dropped with the table,
  // and it is not recoverable from `quantity_affected`, which holds only the
  // latest number: that is why the `up` is a one-way door.
  pgm.sql('ALTER TABLE quality_issue_quantity_changes DISABLE ROW LEVEL SECURITY');
  pgm.sql('DROP INDEX quality_issues_recorded_by_idx');
  pgm.sql('DROP TABLE quality_issue_quantity_changes');
  pgm.sql('ALTER TABLE quality_issues DROP COLUMN recorded_by_account_id');
};
