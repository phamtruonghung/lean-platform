/**
 * The two 5 Why chains on a CAPA (issue #210, ADR-0034).
 *
 * A CAPA's team reasons its way to root causes with two chains: why the problem
 * happened, and why it was not detected. The baseline already carries
 * `capa_root_causes` — an ordered `sequence`, a `statement`, an `is_root` flag —
 * and the Module spec (#200) is explicit about what it is missing: the **chain**
 * a `why` row belongs to, and, for the fishbone shape, a **verdict** and an
 * **evidence note**. This migration adds exactly those, so that #213 needs no
 * schema step of its own.
 *
 * **1. `chain` — which of the two chains a Why is in.** Nullable, because the
 * column is about `why` rows only: a fishbone candidate is a category's branch,
 * not a step in a chain. The CHECK mirrors a Module constant the way every
 * other enum in this schema does (`action_items.action_type`, `capas.status`),
 * and the ticket's own vocabulary is the two values: `occurrence` and `escape`.
 * They are deliberately not `problem` and `detection`: ADR-0034's words are
 * "why it happened" and "why it was not detected", and the 8D vocabulary for
 * those two is occurrence and escape.
 *
 * **2. The fishbone's own columns — added here, written by nobody.** `verdict`
 * is `candidate` → `confirmed` / `ruled_out`, and `evidence_note` is what the
 * evidence for that verdict was. #213 owns every behaviour behind them: nothing
 * in this migration, and nothing in the service beside it, reads or writes
 * either column. They are here because the spec puts the table's whole shape in
 * one place, and a second migration adding two columns two tickets later is a
 * second one-way door for something decided once.
 *
 * **3. A Why is in a chain, and only a Why is.** The biconditional rather than
 * two constraints, because the two halves say one thing: `cause_type = 'why'`
 * exactly when `chain IS NOT NULL`. A Why without a chain is a row nothing can
 * order — the chain *is* the sequence's scope — and a fishbone candidate with
 * one would be counted twice by a reader that renders "the two chains". This is
 * a CHECK where the service's own 400 is the door everybody uses, for the same
 * reason every other constraint in this schema exists: it is what makes the
 * rule true for a writer that does not go through the service.
 *
 * **4. At most one confirmed root cause per chain — the database's own
 * guarantee, and how.** `capa_root_causes_one_root_per_chain` is a **partial
 * unique index** on `(capa_id, chain) WHERE is_root`, which is the same shape
 * `action_items_capa_id_once` takes for "a CAPA answers at most one Concern"
 * (migration 1800100000000) and the shape this Platform reaches for whenever a
 * rule is about a subset of rows. Partial because `is_root` is false on nearly
 * every row: a plain unique index over `(capa_id, chain, is_root)` would be
 * larger and would say something different — that two rows may not be marked
 * root *twice*, which is not the rule. Postgres enforces a unique index on
 * every write, including one made by a script or a console nobody reviewed, so
 * "marking a second Why as the root replaces the first" is a fact about the
 * schema and not only a sequence of statements in `actions.js`.
 *
 * The index's own predicate is enough without naming `cause_type`, and the two
 * CHECKs above are why: `is_root` implies `cause_type = 'why'`
 * (`capa_root_causes_root_is_a_why` below), which implies a non-null `chain`.
 * A row the index admits therefore always has the `chain` the index is keyed
 * on. `capa_root_causes_root_is_a_why` is there for the fishbone's sake rather
 * than the chain's: a candidate cause's answer is its own `verdict` (#213), so
 * marking one `is_root` would be a second way of saying "this is the answer"
 * that the fishbone's own columns already say.
 *
 * **What is deliberately not here.** No `UNIQUE (capa_id, chain, sequence)`:
 * two Whys may not share a position, but contiguity has to survive a *move* —
 * `actions.js` renumbers a whole chain in one statement, and a unique index
 * cannot be deferred (Postgres has no partial unique *constraint*), so the
 * index would fail a legitimate reorder rather than protect anything. The order
 * is the service's, and the ticket asks for the *root* rule to be the
 * database's; that is the one it gets. Nothing is backfilled either: no version
 * of this codebase has ever written `capa_root_causes`, so there are no
 * existing rows for the new CHECKs to fail on, and every change here is
 * additive — the image this migration replaces keeps running against it
 * unchanged (ADR-0007, expand now, contract later).
 *
 * No RLS obligation accompanies this migration: it creates no table, and
 * `1756000000002_deny-all-rls.js` enabled the floor on `capa_root_causes` when
 * it swept the tables that existed then.
 */

exports.shorthands = undefined;

exports.up = (pgm) => {
  // Which of the two chains a Why is in (1).
  pgm.sql('ALTER TABLE capa_root_causes ADD COLUMN chain TEXT');
  pgm.sql(`
    ALTER TABLE capa_root_causes
      ADD CONSTRAINT capa_root_causes_chain_check
        CHECK (chain IS NULL OR chain IN ('occurrence', 'escape'))
  `);

  // The fishbone's own two columns (2) — #213's to write, nobody's to read yet.
  pgm.sql('ALTER TABLE capa_root_causes ADD COLUMN verdict TEXT');
  pgm.sql(`
    ALTER TABLE capa_root_causes
      ADD CONSTRAINT capa_root_causes_verdict_check
        CHECK (verdict IS NULL OR verdict IN ('candidate', 'confirmed', 'ruled_out'))
  `);
  pgm.sql('ALTER TABLE capa_root_causes ADD COLUMN evidence_note TEXT');

  // A Why is in a chain, and only a Why is (3).
  pgm.sql(`
    ALTER TABLE capa_root_causes
      ADD CONSTRAINT capa_root_causes_chain_is_a_why
        CHECK ((cause_type = 'why') = (chain IS NOT NULL))
  `);

  // The root cause of a chain is a Why's to be (4).
  pgm.sql(`
    ALTER TABLE capa_root_causes
      ADD CONSTRAINT capa_root_causes_root_is_a_why
        CHECK (NOT is_root OR cause_type = 'why')
  `);

  // At most one confirmed root cause per chain, enforced by Postgres rather
  // than only by the statement that marks it (4).
  pgm.sql(`
    CREATE UNIQUE INDEX capa_root_causes_one_root_per_chain
      ON capa_root_causes (capa_id, chain)
      WHERE is_root
  `);
};

exports.down = (pgm) => {
  // Forward-only in production per ADR-0007 — this exists for local
  // development and for node-pg-migrate's own requirement that a migration
  // define both directions. Dropping `chain` takes the index keyed on it with
  // it, and the CHECKs are dropped before the columns they name.
  pgm.sql('DROP INDEX capa_root_causes_one_root_per_chain');
  pgm.sql('ALTER TABLE capa_root_causes DROP CONSTRAINT capa_root_causes_root_is_a_why');
  pgm.sql('ALTER TABLE capa_root_causes DROP CONSTRAINT capa_root_causes_chain_is_a_why');
  pgm.sql('ALTER TABLE capa_root_causes DROP CONSTRAINT capa_root_causes_verdict_check');
  pgm.sql('ALTER TABLE capa_root_causes DROP CONSTRAINT capa_root_causes_chain_check');
  pgm.sql('ALTER TABLE capa_root_causes DROP COLUMN evidence_note');
  pgm.sql('ALTER TABLE capa_root_causes DROP COLUMN verdict');
  pgm.sql('ALTER TABLE capa_root_causes DROP COLUMN chain');
};
