/**
 * Inventory: a parts catalogue, stores, and stock levels derived from
 * movements (issue #80). ADR-0015 decided that a `stores`-sourced parts
 * booking draws from stock; nothing existed to draw from, and this migration
 * builds it.
 *
 * Three tables, and the split between them is the decision:
 *
 *   - `parts` is the shared catalogue, in ADR-0005's sense: a part number
 *     means the same thing at every Site, the same shape `job_roles` and
 *     `skills` already have. Its `uom_code` references the existing
 *     `units_of_measure` table, not a second notion of a unit — a part's
 *     unit is defined once and every movement of it uses that unit.
 *
 *   - `stores` belongs to a Site and sits at an Org Unit. A store is NOT a
 *     shared catalogue: it is one Site's shelf. `site_id` is carried directly
 *     (rather than only derivable through `org_units`) because the whole point
 *     of the table is the per-Site split, and `stores_check_org_unit_site`
 *     below keeps the two columns from disagreeing — the Org Unit the store
 *     sits at must belong to the Site the store belongs to.
 *
 *   - `stock_movements` is the record of truth. A quantity is never stored as
 *     a mutable number: the level of a part in a store is the sum of that
 *     pair's movements, and `stock_movements_non_negative` refuses an INSERT
 *     whose running sum would fall below zero. A stored quantity and a
 *     movement history disagree the first time a write half-fails, and then
 *     nobody trusts either; deriving the level costs a SUM and buys a history
 *     that cannot lie about itself. A materialised total, if it is ever
 *     needed for speed, is a performance decision to make with evidence.
 *
 * ## Refusing a negative level, and doing it soundly
 *
 * The non-negative rule is a cross-row invariant, so it cannot be a table
 * CHECK: it is a BEFORE INSERT trigger that sums the pair's existing movements
 * together with the new one and raises if the result is negative. A trigger
 * that only read the sum would still be racy — two concurrent withdrawals
 * could each read a balance the other had not committed, both pass, and leave
 * the shelf negative. So the trigger first takes
 * `pg_advisory_xact_lock(hashtext(store_id || ':' || part_id))`, which
 * serialises writers for the same pair while leaving every other pair free,
 * exactly the shape `assets.js`'s reparent lock uses for its own
 * cross-row invariant. The raised SQLSTATE is `23514` (check_violation), so
 * the service can map it to a clean, part-naming refusal before it reaches a
 * route — the same treatment `mapAssetWriteError`/`mapWorkOrderWriteError`
 * give their own constraint violations.
 *
 * ## RLS
 *
 * `1756000000002_deny-all-rls.js` enabled RLS on the tables that existed when
 * it ran and explicitly left every later migration its own obligation to do
 * the same. These three tables are created here, so this migration enables
 * RLS on each of them, with no policies — the deny-all floor, so `anon` and
 * `authenticated` read nothing from them, while the API's own owner role is
 * unaffected.
 *
 * ## Forward-only
 *
 * The ticket says this adds a migration, and ADR-0007 governs it: nothing
 * existing is altered, so the outgoing version keeps running untouched against
 * the expanded schema. `down` exists only for local development and
 * node-pg-migrate's own requirement; there is no deployed down path.
 */

exports.shorthands = undefined;

exports.up = (pgm) => {
  // --------------------------------------------------------------------------
  // parts — the shared catalogue (ADR-0005).
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE TABLE parts (
      id            BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      part_no       TEXT        NOT NULL UNIQUE,
      description   TEXT        NOT NULL CHECK (btrim(description) <> ''),
      -- One unit of measure, shared with work_order_parts.uom_code: a part's
      -- unit is defined once here and every movement of it uses that unit.
      uom_code      TEXT        NOT NULL REFERENCES units_of_measure (code),
      is_active     BOOLEAN     NOT NULL DEFAULT TRUE,
      created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by    BIGINT,
      updated_by    BIGINT
    )
  `);

  // --------------------------------------------------------------------------
  // stores — one Site's shelf, at an Org Unit.
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE TABLE stores (
      id            BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      site_id       BIGINT      NOT NULL REFERENCES sites (id),
      org_unit_id   BIGINT      NOT NULL REFERENCES org_units (id),
      code          TEXT        NOT NULL,
      name          TEXT        NOT NULL CHECK (btrim(name) <> ''),
      is_active     BOOLEAN     NOT NULL DEFAULT TRUE,
      created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by    BIGINT,
      updated_by    BIGINT,

      -- A store code is unique within its Site, unlike an Asset's global
      -- code: "STORE-A" at two plants is two different shelves, and the
      -- message the caller gets must name the Site-local clash it can resolve.
      CONSTRAINT stores_site_code_unique UNIQUE (site_id, code)
    )
  `);

  // The two columns above are one fact, not two: a store's Org Unit must
  // belong to the store's Site, or a shelf could report a Site it does not
  // sit in. Enforced at the schema level rather than trusted to the one route
  // that inserts, for the same reason a CHECK is: the next writer might not
  // be that route.
  pgm.sql(`
    CREATE FUNCTION stores_check_org_unit_site() RETURNS TRIGGER AS $$
    DECLARE
      v_site_id BIGINT;
    BEGIN
      SELECT site_id INTO v_site_id FROM org_units WHERE id = NEW.org_unit_id;
      IF v_site_id IS NULL OR v_site_id <> NEW.site_id THEN
        RAISE EXCEPTION 'a store''s Org Unit must belong to the store''s Site'
          USING ERRCODE = '23514';
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql
  `);

  pgm.sql(`
    CREATE TRIGGER stores_org_unit_site
      BEFORE INSERT OR UPDATE OF site_id, org_unit_id ON stores
      FOR EACH ROW EXECUTE FUNCTION stores_check_org_unit_site()
  `);

  pgm.sql('CREATE INDEX stores_site_idx ON stores (site_id)');
  pgm.sql('CREATE INDEX stores_org_unit_idx ON stores (org_unit_id)');

  // --------------------------------------------------------------------------
  // stock_movements — the record of truth. Quantity is derived, never stored.
  // --------------------------------------------------------------------------
  pgm.sql(`
    CREATE TABLE stock_movements (
      id            BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      part_id       BIGINT      NOT NULL REFERENCES parts (id),
      store_id      BIGINT      NOT NULL REFERENCES stores (id),
      -- Signed: positive is into the store, negative is out of it. A receipt
      -- is a positive row, an adjustment may be either sign, and nothing here
      -- rolls a separate direction column that could disagree with the sign.
      quantity      NUMERIC(18,4) NOT NULL CHECK (quantity <> 0),
      movement_type TEXT        NOT NULL
                                CHECK (movement_type IN ('receipt', 'adjustment')),
      -- The "why": a receipt says what it was, an adjustment is required to
      -- name the count it corrects.
      reason        TEXT        NOT NULL CHECK (btrim(reason) <> ''),
      -- The "when": when the movement happened, which a person may record
      -- after the fact; created_at is only when the row was written.
      occurred_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by    BIGINT
    )
  `);

  pgm.sql(`
    CREATE INDEX stock_movements_store_part_idx
      ON stock_movements (store_id, part_id)
  `);
  pgm.sql(`
    CREATE INDEX stock_movements_store_time_idx
      ON stock_movements (store_id, occurred_at DESC)
  `);

  // The refusal, with the pair's writers serialised first — see this file's
  // own header on why the advisory lock is load-bearing rather than
  // decoration. The message the database raises is deliberately generic;
  // `mapInventoryWriteError` in the service turns it into a sentence naming
  // the part and what is on the shelf, after the failed transaction rolls
  // back and the balance can be read honestly.
  pgm.sql(`
    CREATE FUNCTION stock_movements_refuse_negative() RETURNS TRIGGER AS $$
    DECLARE
      v_on_hand NUMERIC(18,4);
    BEGIN
      PERFORM pg_advisory_xact_lock(
        hashtext(NEW.store_id::text || ':' || NEW.part_id::text)
      );

      SELECT COALESCE(SUM(quantity), 0) INTO v_on_hand
        FROM stock_movements
       WHERE store_id = NEW.store_id AND part_id = NEW.part_id;

      IF v_on_hand + NEW.quantity < 0 THEN
        RAISE EXCEPTION 'stock movement would take the shelf below zero'
          USING ERRCODE = '23514';
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql
  `);

  pgm.sql(`
    CREATE TRIGGER stock_movements_non_negative
      BEFORE INSERT ON stock_movements
      FOR EACH ROW EXECUTE FUNCTION stock_movements_refuse_negative()
  `);

  // --------------------------------------------------------------------------
  // Triggers the rest of the App tables already carry.
  // --------------------------------------------------------------------------
  // `parts` and `stores` are ordinary editable records, so both timestamps
  // and actor columns are maintained by the baseline helpers every other
  // App table uses. `stock_movements` is append-only by intent — there is no
  // UPDATE route, and its own history IS the record — so it carries only
  // `created_by`, which the service fills from `app.user_id` on INSERT. It
  // deliberately does NOT get `attach_actor_columns`: that trigger writes
  // both `created_by` and `updated_by`, and an append-only row has no
  // `updated_by` to write, so the helper would fail on every insert.
  pgm.sql(`SELECT attach_updated_at('parts')`);
  pgm.sql(`SELECT attach_actor_columns('parts')`);
  pgm.sql(`SELECT attach_updated_at('stores')`);
  pgm.sql(`SELECT attach_actor_columns('stores')`);

  // The two catalogue tables are audited: who defined a part or a store, and
  // when, is a quality fact. The movement table is not — appending movements
  // is the audit trail, and duplicating every one of them into audit_log
  // would bury the interesting rows for no gain (the baseline's own rule:
  // append-only tables do not need a second copy of themselves).
  pgm.sql(`SELECT attach_audit('parts')`);
  pgm.sql(`SELECT attach_audit('stores')`);

  // --------------------------------------------------------------------------
  // RLS — see this file's own header. Enumerated by name rather than copied
  // wholesale from the deny-all sweep's catalog query because a LATER table
  // does not inherit that sweep; each migration enables it on what it creates.
  // --------------------------------------------------------------------------
  pgm.sql('ALTER TABLE parts ENABLE ROW LEVEL SECURITY');
  pgm.sql('ALTER TABLE stores ENABLE ROW LEVEL SECURITY');
  pgm.sql('ALTER TABLE stock_movements ENABLE ROW LEVEL SECURITY');

  // The two functions above are created by this migration and carry PUBLIC's
  // implicit EXECUTE the moment `CREATE FUNCTION` runs. The deny-all sweep
  // (1756000000002_deny-all-rls.js, step 2a) stripped that from the routines
  // that existed when it ran; a routine added later is the adding migration's
  // obligation, the same way a later table is (that sweep's own header says
  // so for tables). Re-asserting the revocation here is idempotent and keeps
  // `rls.test.js`'s "PUBLIC holds no EXECUTE on any routine in public" true
  // as the schema grows.
  pgm.sql('REVOKE EXECUTE ON ALL ROUTINES IN SCHEMA public FROM PUBLIC');
};

exports.down = (pgm) => {
  // Forward-only in production per ADR-0007 — this exists for local
  // development and node-pg-migrate's own requirement that a migration define
  // both directions. Trigger names are the exact strings the helpers generate
  // (see the baseline's attach_actor_columns/attach_audit/attach_updated_at).
  pgm.sql('DROP TRIGGER IF EXISTS stock_movements_non_negative ON stock_movements');
  pgm.sql('DROP FUNCTION IF EXISTS stock_movements_refuse_negative()');

  pgm.sql('DROP TRIGGER IF EXISTS parts_audit ON parts');
  pgm.sql('DROP TRIGGER IF EXISTS stores_audit ON stores');
  pgm.sql('DROP TRIGGER IF EXISTS zz_parts_set_actor ON parts');
  pgm.sql('DROP TRIGGER IF EXISTS zz_stores_set_actor ON stores');
  pgm.sql('DROP TRIGGER IF EXISTS parts_set_updated_at ON parts');
  pgm.sql('DROP TRIGGER IF EXISTS stores_set_updated_at ON stores');

  pgm.sql('DROP TRIGGER IF EXISTS stores_org_unit_site ON stores');
  pgm.sql('DROP FUNCTION IF EXISTS stores_check_org_unit_site()');

  pgm.sql('DROP TABLE IF EXISTS stock_movements');
  pgm.sql('DROP TABLE IF EXISTS stores');
  pgm.sql('DROP TABLE IF EXISTS parts');
};
