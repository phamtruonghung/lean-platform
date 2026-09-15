/**
 * An Action's PDCA cycle becomes a phase log (issue #177, ADR-0033).
 *
 * `action_items.status` says whether an Action is finished and never which
 * phase of the cycle it is in, who owns that phase or when it is due. This
 * migration adds the child table that does, and nothing else: the `status`
 * column keeps its five values, and the API writes them from the phase
 * transitions rather than from a caller's choice.
 *
 * Why a table of rows rather than four column groups on the Action. The
 * baseline already made this argument when it kept `capa_steps` as rows rather
 * than eight columns — "so each step carries its own owner and due date — an
 * 8D where only the whole thing has an owner is an 8D nobody progresses" — and
 * a phase needs exactly that: its own owner, its own due date, its own note,
 * and for a Check its own recorded outcome. The rejected alternative, ADR-0033
 * records in full, was the four PDCA names as `status` values: a status cannot
 * carry an owner or a date per phase, cannot remember a cycle that was re-run,
 * and both `v_open_actions` and `v_sqcp_board` already predicate on the five
 * values the column has.
 *
 * Why `cycle` and the uniqueness. PDCA is a circle: a Check that recorded
 * `not_effective` opens the *next* cycle's Plan rather than the Act, and the
 * round that failed is kept — it is the evidence that the second round was
 * needed, and the thing every "we thought it was fixed and it came back"
 * investigation is missing. `(action_item_id, cycle, phase)` unique makes one
 * phase of one round a single row, so a retried or double-clicked completion
 * cannot open two Acts.
 *
 * Why the two CHECKs on `outcome`. An outcome means something on a Check and
 * nowhere else, so the column is refused on the other three phases rather than
 * left as a field that silently means nothing; and a completion must record one
 * for a Check, because a Check completed without a verdict is exactly the
 * "we implemented it" that a PDCA log exists to tell apart from "it worked".
 * Both are backstops: the service refuses the same two shapes with a message
 * that names the phase, the way ADR-0019 argues for the Work order's own
 * transitions.
 *
 * `ON DELETE CASCADE` rather than a soft delete: a phase has no meaning
 * without the Action it belongs to, and nothing in this Platform deletes an
 * Action anyway (cancelling is a status).
 *
 * ## RLS
 *
 * `1756000000002_deny-all-rls.js` enabled RLS on the tables that existed when
 * it ran and left every later migration its own obligation to do the same, so
 * this table enables RLS with no policies — the deny-all floor (ADR-0004).
 * `test/integration/rls.test.js` enumerates every table in `public` and fails
 * without it, which is how a table that ships open is caught rather than
 * assumed.
 *
 * `action_phases` is an ordinary editable record and gets the baseline's
 * `attach_updated_at` treatment, like `capa_steps` before it.
 */

exports.shorthands = undefined;

exports.up = (pgm) => {
  pgm.sql(`
    CREATE TABLE action_phases (
      id                BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      action_item_id    BIGINT      NOT NULL REFERENCES action_items (id) ON DELETE CASCADE,

      -- Which turn of the circle this phase belongs to. 1 for the first.
      cycle             SMALLINT    NOT NULL DEFAULT 1 CHECK (cycle >= 1),
      phase             TEXT        NOT NULL
                                    CHECK (phase IN ('plan', 'do', 'check', 'act')),

      -- The phase's own owner and due date, copied from the Action when the
      -- phase is created: a phase nobody owns and nothing is due on is not a
      -- phase, it is a heading.
      owner_employee_id BIGINT      REFERENCES employees (id),
      due_date          DATE,

      completed_at      TIMESTAMPTZ,
      -- Only a Check carries one — see this file's header.
      outcome           TEXT        CHECK (outcome IS NULL OR outcome IN ('effective', 'not_effective')),
      note              TEXT,

      created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by        BIGINT,
      updated_by        BIGINT,

      CONSTRAINT action_phases_unique UNIQUE (action_item_id, cycle, phase),
      CONSTRAINT action_phases_outcome_only_on_check
        CHECK (phase = 'check' OR outcome IS NULL),
      CONSTRAINT action_phases_outcome_needs_completion
        CHECK (outcome IS NULL OR completed_at IS NOT NULL)
    )
  `);

  pgm.sql(`
    CREATE INDEX action_phases_action_idx
      ON action_phases (action_item_id, cycle, phase)
  `);

  // The index behind "what is this Action waiting on": at most one open phase
  // per Action is the invariant the service keeps, and this is the read that
  // finds it — the register's own next-phase column, and the guard every
  // transition takes.
  pgm.sql(`
    CREATE INDEX action_phases_open_idx
      ON action_phases (action_item_id)
      WHERE completed_at IS NULL
  `);

  // The deny-all floor, on the table this migration creates — see this file's
  // own header.
  pgm.sql('ALTER TABLE action_phases ENABLE ROW LEVEL SECURITY');

  pgm.sql(`SELECT attach_updated_at('action_phases')`);
};

exports.down = (pgm) => {
  // Forward-only in production per ADR-0007 — this exists for local
  // development and for node-pg-migrate's own requirement that a migration
  // define both directions.
  pgm.sql('DROP TABLE action_phases');
};
