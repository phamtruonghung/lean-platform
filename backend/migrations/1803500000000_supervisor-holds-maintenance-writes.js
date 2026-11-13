/**
 * The four Maintenance write codes on the Supervisor role (ADR-0061, slice 2b).
 *
 * **What this seed changes, and why it comes before the routes do.** The codes
 * `MTN_ASSETS_CHANGE`, `MTN_WORK_ORDERS_CHANGE`, `MTN_STORES_CHANGE` and
 * `MTN_PM_SCHEDULES_CHANGE` were seeded on engineer, manager and administrator
 * only. A supervisor runs the shop floor: it creates, assigns, completes and
 * cancels Work orders, receives stock and corrects counts, adds an Asset and
 * raises a preventive schedule. Every one of those writes was reachable by any
 * Account holding a write Grant, whatever its role, because
 * `canAct({ write: true })` is role-blind. Putting the sixteen write routes
 * behind their codes without this row would therefore have refused the
 * supervisor across the whole shop floor. The code is seeded here first, so a
 * supervisor keeps exactly the reach it has today and the authority becomes
 * something an administrator can see and change in the Roles Screen.
 *
 * **The narrowing, stated rather than discovered.** An Account whose
 * `app_users.role` is `operator` — or whose only role is the default group —
 * but which holds an edit Grant on one of those Screens' Org Units loses these
 * writes until an administrator adds the code to a role it holds. That is
 * ADR-0061's point: the code is the visible authority, not a side effect of an
 * old Grant. It is a deliberate, named behaviour change, not an accident of
 * this seed, and it is repeated in the retrofit's PR body.
 *
 * **Idempotent on purpose.** `ON CONFLICT DO NOTHING` on the pair, so the seed
 * only ever fills the gap: a database where an administrator has already put
 * the code on the role is left exactly as it is, and re-running this migration
 * is a no-op — the deploy step (ADR-0007) applies it to a copy of the current
 * schema before the new image starts, and must be able to say that twice.
 *
 * Backward-compatible per ADR-0007: four rows in a join table change nothing an
 * older running image reads or writes, because an older image never asks these
 * codes at all.
 */

exports.shorthands = undefined;

// The codes the sixteen Maintenance write routes ask, narrowly stated here so
// the migration says exactly what it did rather than importing a moving list.
const SUPERVISOR_WRITE_CODES = [
  'MTN_ASSETS_CHANGE',
  'MTN_WORK_ORDERS_CHANGE',
  'MTN_STORES_CHANGE',
  'MTN_PM_SCHEDULES_CHANGE'
];

exports.up = (pgm) => {
  pgm.sql(`
    INSERT INTO app_role_permissions (app_role_id, permission_code)
    SELECT r.id, seeded.permission_code
    FROM app_roles r
    CROSS JOIN unnest(ARRAY[${SUPERVISOR_WRITE_CODES.map((code) => `'${code}'`).join(', ')}]::TEXT[])
      AS seeded (permission_code)
    WHERE r.code = 'ROLE_SUPERVISOR'
    ON CONFLICT (app_role_id, permission_code) DO NOTHING
  `);
};

exports.down = (pgm) => {
  // Forward-only in production per ADR-0007 — this exists for local
  // development and for node-pg-migrate's requirement that a migration define
  // both directions. It removes only the four rows this migration's own `up`
  // is written to add.
  pgm.sql(`
    DELETE FROM app_role_permissions p
    USING app_roles r
    WHERE p.app_role_id = r.id
      AND r.code = 'ROLE_SUPERVISOR'
      AND p.permission_code IN (${SUPERVISOR_WRITE_CODES.map((code) => `'${code}'`).join(', ')})
  `);
};
