/**
 * The action log's type vocabulary, renamed and given the word it was missing
 * (issue #176, ADR-0032).
 *
 * `action_items.action_type` accepted `containment`, `corrective`,
 * `preventive`, `improvement` and `task`, and two of those five named
 * something CONTEXT.md forbids on the row they describe:
 *
 *   - `corrective` is what the CAPA entry tells a reader not to call a CAPA
 *     ("Corrective action (that is one half of it)"). In this table the value
 *     means the action that removes a concern's cause, which the glossary
 *     calls a **Countermeasure** — the plant's own lean vocabulary, and the
 *     word ADR-0033's closure rules are written in.
 *   - `task` is what the Work order entry reserves for *a step inside a work
 *     order*, and `work_order_tasks` is the table that holds one. The value
 *     here means an action that answers nothing — order the gloves, chase the
 *     supplier — so it becomes `routine`.
 *
 * `concern` is the word that was missing entirely. The row this column
 * describes is most often the thing found wrong, and nothing in the schema
 * said so: without the value, a concern would have to borrow `corrective` or
 * `task` and the vocabulary would live in prose rather than in the
 * constraint.
 *
 * Why a rename rather than a label at the edge. The alternative considered
 * was to leave both values alone and render "Countermeasure" and "Routine" in
 * the client — no schema change at all. It was rejected because the mismatch
 * would then live in a mapping instead of in the schema: a query filtering
 * `action_type = 'countermeasure'` would find nothing, a screen would say the
 * word the database does not, and the next session reading `corrective` in
 * psql would write it into its own filter. The constraint is the authority for
 * what the values are.
 *
 * Why this is safe, and why it is written this way. Nothing writes the table
 * yet — `grep -rn action_items backend/src frontend/lib dev scripts` finds no
 * writer — so this is a constraint swap rather than a data migration. The two
 * UPDATEs run *after* the old constraint is dropped and *before* the new one
 * is added, so a row that does exist (a hand-inserted one, or one written
 * between the plan and this deploy) is rewritten while neither constraint is
 * in force and the swap cannot fail on it. `pg_constraint` names the column
 * check `action_items_action_type_check`, which is what is dropped here.
 *
 * The default moves with the vocabulary: a row with no type is the thing found
 * wrong, not the fix for it, and `concern` is now the type the log's own read
 * lists first.
 */

exports.shorthands = undefined;

exports.up = (pgm) => {
  pgm.sql('ALTER TABLE action_items DROP CONSTRAINT action_items_action_type_check');

  pgm.sql(`UPDATE action_items SET action_type = 'countermeasure' WHERE action_type = 'corrective'`);
  pgm.sql(`UPDATE action_items SET action_type = 'routine' WHERE action_type = 'task'`);

  pgm.sql(`
    ALTER TABLE action_items
      ALTER COLUMN action_type SET DEFAULT 'concern'
  `);

  pgm.sql(`
    ALTER TABLE action_items
      ADD CONSTRAINT action_items_action_type_check
        CHECK (action_type IN ('concern', 'containment', 'countermeasure',
                               'preventive', 'improvement', 'routine'))
  `);
};

exports.down = (pgm) => {
  // Forward-only in production per ADR-0007 — this exists for local
  // development and for node-pg-migrate's own requirement that a migration
  // define both directions. The rewriting half is not reversed: which rows
  // came in as `corrective` is not recoverable from the rows themselves, and
  // a `down` that guessed would be worse than one that says so.
  pgm.sql('ALTER TABLE action_items DROP CONSTRAINT action_items_action_type_check');
  pgm.sql(`
    ALTER TABLE action_items
      ALTER COLUMN action_type SET DEFAULT 'corrective'
  `);
  pgm.sql(`
    ALTER TABLE action_items
      ADD CONSTRAINT action_items_action_type_check
        CHECK (action_type IN ('containment', 'corrective', 'preventive',
                               'improvement', 'task'))
  `);
};
