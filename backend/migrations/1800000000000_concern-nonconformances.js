/**
 * The Non-conformances one Concern answers (issue #208).
 *
 * One problem that shows up as several occurrences is one Concern, not one per
 * occurrence. The schema already has half of that link: `action_items` carries
 * ten source columns and `quality_issue_id` is the one that records **which
 * Non-conformance a Concern was raised from** — it is what makes
 * `source_type`'s generated `quality_issue` and it is read by everything that
 * asks "what raised this Action". What it cannot do is hold *more than one*:
 * a column holds one value, and a Concern that answers four occurrences of the
 * same failure has to name four.
 *
 * So this migration adds the join table the spec names — (Concern,
 * Non-conformance) — and it is `concern_nonconformances` rather than anything
 * more generic, because only a Concern may be linked (issue #208's own
 * criterion, refused in the service for the reason the measure rule is: a
 * constraint cannot read another row's `action_type`) and because the
 * glossary's words are the ones the table, its columns, its tests and the
 * commit are written in. `quality_issue_id` keeps the baseline's own column
 * name for the Non-conformance side; renaming it would be a second word for a
 * record that already has one.
 *
 * **The table is Actions' own, and that is a decision rather than an
 * accident.** Two Modules touch this link and neither may require the other:
 * `quality` may require only `people`'s entry point (its own acceptance
 * criterion) and the Action log's entry point is read-only by ADR-0006's
 * clause, so `quality` cannot ask `actions` to write and cannot write here
 * itself without re-implementing the Action log's own rules — the number from
 * `next_document_number`, the cycle-1 Plan, the title, `raised_by`. The write
 * that creates a Concern therefore lives in `actions` (see
 * `backend/src/modules/actions/actions.js`'s own header for the full
 * argument), and the row this migration creates is written by that same
 * service. `quality` reads it by ordinary SQL join to answer "which Concerns
 * is this Non-conformance linked to", which ADR-0006 allows in as many words:
 * a Module is a code seam, not a data seam.
 *
 * **Every link is one row here, including the one the source column records.**
 * Raising a Concern from a Non-conformance writes both — the source column, as
 * provenance, and a row in this table — in one transaction, so a reader asks
 * one question of one table and gets every occurrence, the one it was raised
 * from first. The source column is not derived from the table or the table
 * from the column: they are two facts about the same link, written together,
 * and the service refuses to unlink the one the source column names because
 * doing so would leave a Concern whose provenance points at a Non-conformance
 * it no longer answers.
 *
 * `UNIQUE (action_item_id, quality_issue_id)` is what makes linking the same
 * Non-conformance to the same Concern twice a 409 rather than a duplicate row
 * — the same shape `quality_issue_corrections`' own uniqueness rules take, and
 * the reason the service maps SQLSTATE 23505 rather than checking first and
 * racing.
 *
 * **Nothing here changes what already exists.** The table is new, and
 * `action_items.quality_issue_id` keeps its meaning, its index and its
 * generated `source_type`. No existing row is back-filled: a Concern raised
 * before this migration has its source column and no join row, which is
 * exactly the state the reads describe — an older image running against this
 * schema behaves as it did before (ADR-0007, expand now, contract later).
 *
 * The deny-all RLS floor is switched on in this same migration, because
 * ADR-0004's sweep ran once against the catalog as it stood then and a table
 * added afterwards does not inherit it. `attach_updated_at` is installed so
 * the table carries the same timestamp discipline every other one does; the
 * audit trigger is deliberately not attached, since this table is a link
 * between two records that are themselves audited.
 */

exports.shorthands = undefined;

exports.up = (pgm) => {
  pgm.sql(`
    CREATE TABLE concern_nonconformances (
      id                 BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

      -- The Concern. Only a Concern may be named here — quality_issues is
      -- deliberately not the only constraint the service keeps, and the
      -- service refuses any other action_type with a 400, because a
      -- constraint sees one row and cannot read the Action's own type.
      action_item_id     BIGINT      NOT NULL
                                     REFERENCES action_items (id) ON DELETE CASCADE,

      -- The Non-conformance the Concern answers, whether it is the one the
      -- Concern was raised from or a further occurrence of the same problem.
      quality_issue_id   BIGINT      NOT NULL
                                     REFERENCES quality_issues (id) ON DELETE CASCADE,

      -- When the link was made, which a reader of either record shows beside
      -- the row: "linked on the 14th" is how a reader tells the occurrence a
      -- Concern was raised from apart from the ones gathered later.
      linked_at          TIMESTAMPTZ NOT NULL DEFAULT now(),

      created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by         BIGINT,
      updated_by         BIGINT,

      -- Linking the same Non-conformance to the same Concern twice is a
      -- mistake the caller can see; the service maps this constraint's own
      -- SQLSTATE to a 409 rather than checking first and racing.
      CONSTRAINT concern_nonconformances_once
        UNIQUE (action_item_id, quality_issue_id)
    )
  `);

  // The index behind the read a Non-conformance's own Screen makes — "which
  // Concerns is this occurrence part of" — which walks the table from the
  // Non-conformance end; the unique constraint above already serves the
  // Concern end (it is (action_item_id, quality_issue_id) in that order).
  pgm.sql(`
    CREATE INDEX concern_nonconformances_issue_idx
      ON concern_nonconformances (quality_issue_id, action_item_id)
  `);

  pgm.sql(`SELECT attach_updated_at('concern_nonconformances')`);

  // The deny-all floor, on the table this migration creates (ADR-0004, and
  // `rls.test.js` asserts it on every base table). No policies are added,
  // here or anywhere: deny-all with zero policies is the whole rule, and the
  // API's own connection is the table's owner, which ignores RLS regardless.
  // `powerbi_reader`'s SELECT already reaches this table through the
  // `ALTER DEFAULT PRIVILEGES` that migration set, since Postgres evaluates
  // default privileges at object-creation time — so there is nothing to grant
  // here.
  pgm.sql('ALTER TABLE concern_nonconformances ENABLE ROW LEVEL SECURITY');
};

exports.down = (pgm) => {
  // Forward-only in production per ADR-0007 — this exists for local
  // development and for node-pg-migrate's own requirement that a migration
  // define both directions. The links are dropped with the table and are not
  // recoverable from the records themselves, which is why the `up` is a
  // one-way door.
  pgm.sql('ALTER TABLE concern_nonconformances DISABLE ROW LEVEL SECURITY');
  pgm.sql('DROP TABLE concern_nonconformances');
};
