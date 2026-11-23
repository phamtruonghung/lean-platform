/**
 * Who assigned a role, and who changed what a role carries (ADR-0061).
 *
 * **The gap this closes.** `1803400000000_permissions-and-roles.js` created
 * `app_user_roles` and `app_role_permissions` with a `created_by` column and
 * nothing that ever filled it, and attached the audit trail to `app_roles`
 * only. So the two acts an administrator performs on another person's access —
 * the "Assign" button (`PUT /api/people/accounts/:id/roles`) and the editing of
 * a role's permission set (`PUT /api/people/roles/:id/permissions`) — recorded
 * neither who did them nor that they happened:
 * `withActor`'s `app.user_id` was set on the session and read by nobody.
 *
 * The Grants assignment is the precedent, and it is the opposite one:
 * `1788279276376_accounts-start-inactive-and-audited.js` gave
 * `app_user_org_units` both `attach_actor_columns` and `attach_audit`. A row in
 * `app_user_roles` is the same kind of act — a name attached to an authority —
 * and is kept in SAP's user master change documents for the same reason.
 *
 * **Why `updated_by` is added here.** `set_actor_columns()` writes both
 * `created_by` and `updated_by` on every INSERT, and PL/pgSQL raises
 * `record "new" has no field "updated_by"` on a table that lacks the second
 * one. Adding the column is the honest reading of the SQDCP convention every
 * other attributed table in this schema follows (`app_user_org_units` carries
 * all four timestamp/actor columns, not two). There is no UPDATE write path on
 * either join table today — a row is written once and deleted — so the column
 * holds the inserting administrator's id and no more.
 *
 * **Why not `attach_audit`.** Its function reads `NEW.id`
 * (`1756000000000_baseline.js`), and both these tables are composite-key:
 * `app_user_roles` is `(app_user_id, app_role_id)`, `app_role_permissions` is
 * `(app_role_id, permission_code)`. There is no `id` to record, and inventing
 * a surrogate one would leave `audit_log.record_id` pointing at a number that
 * means nothing and is gone with the row. This migration writes its own AFTER
 * trigger instead, one that takes the meaningful key as a trigger argument, so
 * `audit_log.record_id` is the id the act is *about*:
 *
 *   `app_user_roles`        → `record_id` is the **Account** whose access changed
 *   `app_role_permissions`  → `record_id` is the **role** whose set changed
 *
 * That is the axis `audit_log_record_idx (table_name, record_id, changed_at
 * DESC)` is queried along: "what has happened to this Account's access", "what
 * has happened to this role's permission set". The pair itself is in
 * `old_values`/`new_values`, which is where the rest of a change is recorded
 * anyway.
 *
 * **Why INSERT *and* DELETE.** `created_by` can only ever carry the moment of
 * assignment; losing an assignment has no row left to carry anything. The
 * DELETE half of a permission-set replace is the same problem, and it is the
 * half that removes authority. UPDATE is included for the same reason every
 * other audited table includes it — a repair to a NULL `created_by` should be
 * visible — even though no route issues one today; a no-op UPDATE writes
 * nothing, as `audit_row_change()` already does.
 *
 * Nothing is backfilled. Rows written before this migration keep a NULL
 * `created_by`, which is the truthful answer: nobody recorded an author.
 *
 * Backward-compatible per ADR-0007: two nullable columns and two triggers
 * change nothing an older running image reads or writes — it inserts the same
 * two columns and leaves the rest to the database.
 */

exports.shorthands = undefined;

exports.up = (pgm) => {
  // Required by set_actor_columns(), which assigns both actor columns on every
  // INSERT. See the header.
  pgm.sql('ALTER TABLE app_user_roles ADD COLUMN updated_by BIGINT');
  pgm.sql('ALTER TABLE app_role_permissions ADD COLUMN updated_by BIGINT');

  // created_by/updated_by, filled from app.user_id the same way every other
  // attributed table in this schema is — so the route does not have to
  // remember, and a call made outside a request honestly records NULL.
  pgm.sql(`SELECT attach_actor_columns('app_user_roles')`);
  pgm.sql(`SELECT attach_actor_columns('app_role_permissions')`);

  pgm.sql(`
    CREATE OR REPLACE FUNCTION audit_join_row_change()
    RETURNS TRIGGER
    LANGUAGE plpgsql
    AS $$
    DECLARE
      v_user     BIGINT := NULLIF(current_setting('app.user_id', true), '')::BIGINT;
      v_previous JSONB;
      v_row      JSONB;
      v_id       BIGINT;
    BEGIN
      IF TG_OP IN ('UPDATE', 'DELETE') THEN
        v_previous := to_jsonb(OLD);
      END IF;
      v_row := CASE WHEN TG_OP = 'DELETE' THEN v_previous ELSE to_jsonb(NEW) END;

      -- The trigger's argument names the column that is this row's meaningful
      -- key — the parent the act is about, not the join pair.
      v_id := (v_row ->> TG_ARGV[0])::BIGINT;

      -- A row that did not actually change is not worth a history entry, the
      -- same rule audit_row_change() applies.
      IF TG_OP = 'UPDATE' AND v_previous = v_row THEN
        RETURN NEW;
      END IF;

      IF TG_OP = 'DELETE' THEN
        INSERT INTO audit_log (table_name, record_id, operation, changed_by, old_values)
        VALUES (TG_TABLE_NAME, v_id, TG_OP, v_user, v_row);
        RETURN OLD;
      END IF;

      INSERT INTO audit_log (table_name, record_id, operation, changed_by, old_values, new_values)
      VALUES (TG_TABLE_NAME, v_id, TG_OP, v_user,
              CASE WHEN TG_OP = 'UPDATE' THEN v_previous END, v_row);
      RETURN NEW;
    END;
    $$
  `);

  // Postgres grants EXECUTE on a new function to PUBLIC implicitly, and the
  // suite asserts (rls.test.js) that no routine in `public` answers to the
  // PUBLIC pseudo-role — the same explicit revoke every other migration that
  // creates a function carries.
  pgm.sql('REVOKE EXECUTE ON FUNCTION audit_join_row_change() FROM PUBLIC');

  pgm.sql(`
    CREATE TRIGGER app_user_roles_audit
      AFTER INSERT OR UPDATE OR DELETE ON app_user_roles
      FOR EACH ROW EXECUTE FUNCTION audit_join_row_change('app_user_id')
  `);

  pgm.sql(`
    CREATE TRIGGER app_role_permissions_audit
      AFTER INSERT OR UPDATE OR DELETE ON app_role_permissions
      FOR EACH ROW EXECUTE FUNCTION audit_join_row_change('app_role_id')
  `);
};

exports.down = (pgm) => {
  // Forward-only in production per ADR-0007 — this exists for local
  // development and for node-pg-migrate's own requirement that a migration
  // define both directions. Trigger names are exactly the ones up() creates,
  // and the helper-generated actor trigger is the one
  // attach_actor_columns() names (`zz_<table>_set_actor`).
  pgm.sql('DROP TRIGGER IF EXISTS app_role_permissions_audit ON app_role_permissions');
  pgm.sql('DROP TRIGGER IF EXISTS app_user_roles_audit ON app_user_roles');
  pgm.sql('DROP FUNCTION IF EXISTS audit_join_row_change()');
  pgm.sql('DROP TRIGGER IF EXISTS zz_app_role_permissions_set_actor ON app_role_permissions');
  pgm.sql('DROP TRIGGER IF EXISTS zz_app_user_roles_set_actor ON app_user_roles');
  pgm.sql('ALTER TABLE app_role_permissions DROP COLUMN IF EXISTS updated_by');
  pgm.sql('ALTER TABLE app_user_roles DROP COLUMN IF EXISTS updated_by');
};
