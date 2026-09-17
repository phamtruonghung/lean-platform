/**
 * A CAPA is an investigation opened on a Concern (issue #209, ADR-0034).
 *
 * The baseline already carries the CAPA — `capas`, `capa_steps`,
 * `capa_root_causes` — and ADR-0034 decides what to do with it: a CAPA stands
 * on an existing Concern rather than beside one, so the Concern stays the
 * problem and its Containments, Countermeasures and Preventive actions are the
 * CAPA's actions, recorded in the Action log exactly as any other Concern's
 * are. What this migration adds is the three things that decision needs and the
 * baseline does not carry.
 *
 * **1. `action_items.capa_id` becomes a real link, with the uniqueness rule.**
 * The column has been on `action_items` since the baseline — one nullable
 * foreign key per source type, `capa_id` among them — and nothing has ever
 * written it. ADR-0034's shape puts the link on the *Concern*, and the
 * baseline's own header for `capas` says why that is the right side: the CAPA
 * "belongs to no one Module and is owned by none", while a Concern is a row in
 * the one action log every pillar shares. Two rules, and the partial unique
 * index below is both of them at once:
 *
 *   - *a Concern points at at most one CAPA* — a column holds one value, so a
 *     Concern cannot name two. That half needs no index and no constraint; it
 *     is what a scalar column means;
 *   - *at most one Concern points at a given CAPA* — the partial unique index
 *     `action_items_capa_id_once`, over the rows where `capa_id` is not null.
 *     Partial because most rows are null, and a unique index over a nullable
 *     column treats every null as distinct, so a plain unique index would be
 *     both larger and wrong-in-intent.
 *
 * Together those are "a Concern has at most one CAPA and a CAPA answers exactly
 * one Concern". The *exactly* is the service's: a `capas` row and the link that
 * points at it are written in one transaction (`openCapa`,
 * `backend/src/modules/actions/actions.js`), so there is no moment at which a
 * CAPA exists with no Concern behind it. A constraint cannot say that — "some
 * row in another table references me" is not a check Postgres can evaluate on
 * this row — and a trigger would be a second implementation of the rule the
 * service already keeps, in the one place nobody reads.
 *
 * **2. Only a Concern may carry `capa_id`.** A `CHECK` on the row's own
 * `action_type`, which is exactly the information needed and exactly what a
 * check constraint can see: a Containment, a Countermeasure, a Preventive
 * action, an Improvement or a Routine action answers a problem, and none of
 * them is one. This is a second line behind the service's own 400 for the same
 * reason every other constraint in this schema is: the service is the door
 * everybody uses, and the constraint is what makes the rule true for a writer
 * that does not use it. The baseline's `action_items_single_source` already
 * says a row carries at most one source; this says which kind of row may carry
 * *this* one.
 *
 * **3. `capa_team_members` — the team, which the baseline cannot hold.**
 * `capas` carries one `team_lead_employee_id` and no way to name anybody else;
 * #200's story 51 and ADR-0034's D1 want a team, and D1 is not one person. So
 * one row per (CAPA, Employee), `ON DELETE CASCADE` from the CAPA and
 * `UNIQUE (capa_id, employee_id)` so naming the same person twice is one row
 * rather than two — the same shape `concern_nonconformances` took for the
 * Non-conformance link, and the same reason: it is a join between two records
 * that are both real rows, not a text field holding names.
 *
 * The team lead stays where the baseline put it, on `capas`. That is a
 * deliberate asymmetry rather than an oversight: the lead is a role on the
 * investigation (they are the one who cannot verify their own fix, #211) and
 * the members are a set, so the lead is a column and the members are rows —
 * which is also what makes `capas.team_lead_employee_id`'s existing index and
 * its existing meaning keep working.
 *
 * **What is deliberately not here.** `capa_steps` is untouched and stays
 * unused, per ADR-0034 in as many words: the Concern's own actions *are* the
 * CAPA's steps, and a second place to record the same fix is the drift the ADR
 * rejected. Nothing writes that table and this migration does not start: the
 * CAPA's own `status` vocabulary (`containment`, `root_cause`, `actions`,
 * `verifying`) belongs to the *investigation* and is #211's business, and
 * nothing here backfills a row or rewrites an existing one. Every change is
 * additive, so the image this migration replaces keeps running against it
 * (ADR-0007, expand now, contract later).
 *
 * `action_items_capa_idx` (the baseline's plain index on `capa_id`) is left
 * alone rather than replaced by the unique one. It is now redundant, and
 * dropping an index is a contract step for the release after this one — the
 * expand/contract discipline this repo runs on means a migration removes what
 * the version it replaces no longer needs, not what this one has just made
 * unnecessary.
 *
 * The deny-all RLS floor is switched on for `capa_team_members` in this same
 * migration, because ADR-0004's sweep ran once against the catalog as it stood
 * then and a table added afterwards does not inherit it (`rls.test.js` asserts
 * it on every base table). No policies are added, here or anywhere: deny-all
 * with zero policies is the whole rule, and the API's own connection is the
 * table's owner, which ignores RLS regardless. Nothing is granted to
 * `powerbi_reader` here either — the `ALTER DEFAULT PRIVILEGES` that migration
 * set applies at object-creation time, so the SELECT is already there. The
 * baseline's own CAPA tables are not re-declared: they exist, they were covered
 * by that sweep, and a second `ENABLE ROW LEVEL SECURITY` on them would say
 * nothing.
 */

exports.shorthands = undefined;

exports.up = (pgm) => {
  pgm.sql(`
    CREATE TABLE capa_team_members (
      id          BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

      -- The investigation. Cascade, because a team member of a CAPA that no
      -- longer exists is not a record of anything.
      capa_id     BIGINT      NOT NULL REFERENCES capas (id) ON DELETE CASCADE,

      -- The Employee on the team, from the directory. Deliberately no
      -- "is_active" snapshot: the service refuses a departed Employee at the
      -- moment somebody is added (409, the same rule every other Action
      -- follows), and a person who departs afterwards stays on the team they
      -- were on — that is a fact about the investigation, not a permission.
      employee_id BIGINT      NOT NULL REFERENCES employees (id) ON DELETE CASCADE,

      created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by  BIGINT,
      updated_by  BIGINT,

      -- Naming the same Employee twice on one CAPA is one team, so it is one
      -- row: the service dedupes before it writes, and this is what makes the
      -- guarantee true rather than merely likely.
      CONSTRAINT capa_team_members_once UNIQUE (capa_id, employee_id)
    )
  `);

  // The read from the Employee's own end — "which CAPAs is this person on" —
  // which the unique constraint above does not serve: it is (capa_id,
  // employee_id) in that order, so it answers "who is on this CAPA" and not
  // the reverse.
  pgm.sql('CREATE INDEX capa_team_members_employee_idx ON capa_team_members (employee_id, capa_id)');

  pgm.sql(`SELECT attach_updated_at('capa_team_members')`);

  pgm.sql('ALTER TABLE capa_team_members ENABLE ROW LEVEL SECURITY');

  // A CAPA answers exactly one Concern: the index is partial on the non-null
  // rows, which are the only ones the rule is about (see the header).
  pgm.sql(`
    CREATE UNIQUE INDEX action_items_capa_id_once
      ON action_items (capa_id)
      WHERE capa_id IS NOT NULL
  `);

  // ...and only a Concern may carry one.
  pgm.sql(`
    ALTER TABLE action_items
      ADD CONSTRAINT action_items_capa_is_a_concern
        CHECK (capa_id IS NULL OR action_type = 'concern')
  `);
};

exports.down = (pgm) => {
  // Forward-only in production per ADR-0007 — this exists for local
  // development and for node-pg-migrate's own requirement that a migration
  // define both directions. Dropping the table takes the teams with it, which
  // is why the `up` is a one-way door rather than a step that can be walked
  // back in a live database.
  pgm.sql('ALTER TABLE action_items DROP CONSTRAINT action_items_capa_is_a_concern');
  pgm.sql('DROP INDEX action_items_capa_id_once');
  pgm.sql('ALTER TABLE capa_team_members DISABLE ROW LEVEL SECURITY');
  pgm.sql('DROP TABLE capa_team_members');
};
