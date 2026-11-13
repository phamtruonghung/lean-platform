/**
 * The one write code this phase of the retrofit has to widen (ADR-0061, phase
 * 2d, issue #539).
 *
 * **What this seed changes, and why it comes before the routes do.** The two
 * MTU KPI catalogue writes — `POST /api/kpi/catalogue` and
 * `POST /api/kpi/targets` — ask only `canAct({ write: true })` on the Site's
 * root Org Unit today, and the catalogue Screen enables its "Add KPI"
 * affordance for any Account whose `/me` says `orgUnitScope.canWriteSomewhere`.
 * The seed declared `INS_KPI_CATALOGUE_CHANGE` on `ROLE_ADMIN` alone, while
 * `ModuleRoles.kpi` offers that Screen to supervisor, engineer, manager and
 * administrator. Gating the writes without this migration would therefore take
 * the act away from a supervisor, engineer or manager holding a root write
 * Grant — a user-visible narrowing of a button their Screen shows them — which
 * is exactly the silent narrowing this retrofit must not do.
 *
 * **The seed, before and after.** Plain SQL this file holds itself, so it says
 * exactly what it did:
 *
 *   - `INS_KPI_CATALOGUE_CHANGE` — administrator
 *     → supervisor, engineer, manager, administrator (three rows added).
 *
 * The direction is towards today's reach, which is the Grant, not the role.
 *
 * **What it still narrows, stated rather than discovered.** An Account whose
 * `app_users.role` is `operator` (or Standard-only) but which holds a write
 * Grant on the Site's root Org Unit can add a KPI **today** and will not after
 * this slice, until an administrator adds the code to a role it holds. That is
 * the same declared narrowing `1803500000000_supervisor-holds-maintenance-writes.js`
 * and the rest of the retrofit accepted: a code is the visible authority, and
 * the Roles Screen is where it is given back. No Screen offers an operator the
 * KPI catalogue, so the button is not one the UI shows them — the API was the
 * only way there.
 *
 * **No code is added to the catalogue.** `INS_KPI_CATALOGUE_CHANGE` already
 * exists and already names these acts — "add a KPI or change its Targets" — so
 * this file writes rows, never a `permissions` row, and the catalogue's length
 * is unchanged.
 *
 * **`ROLE_ADMIN` is not named.** It already holds the code, and an administrator
 * passes every `requirePermission` before a role set is read, so the row would
 * change no answer either way; the list is the statement of what this file
 * adds, and this file adds nothing to it.
 *
 * **Idempotent on purpose.** `ON CONFLICT DO NOTHING`, so the seed only ever
 * fills the gap: a database where an administrator has already put the code on a
 * role, or taken it off, is left exactly as it is, and re-running this migration
 * is a no-op — the deploy step (ADR-0007) applies it to a copy of the current
 * schema before the new image starts, and must be able to say that twice.
 *
 * **`down()` reverses only the rows this file adds**, so a local `migrate:down`
 * does not take `INS_KPI_CATALOGUE_CHANGE` off `ROLE_ADMIN` — the row
 * 1803400000000 seeded and this slice relies on. Forward-only in production per
 * ADR-0007; the down exists for a developer's own database.
 *
 * Backward-compatible per ADR-0007: three rows in a join table change nothing an
 * older running image reads or writes, because an older image never asks
 * `INS_KPI_CATALOGUE_CHANGE` at all.
 */

exports.shorthands = undefined;

// The rows this file adds, named as (role, code) pairs. A plain list rather than
// an array of role codes, because that is the only way `down()` can remove
// exactly what `up()` wrote: the code already sits on `ROLE_ADMIN`.
const WIDENED = [
  // The catalogue Screen's own three non-administrator roles
  // (`frontend/lib/platform/destinations.dart`, `ModuleRoles.kpi`).
  ['ROLE_SUPERVISOR', 'INS_KPI_CATALOGUE_CHANGE'],
  ['ROLE_ENGINEER', 'INS_KPI_CATALOGUE_CHANGE'],
  ['ROLE_MANAGER', 'INS_KPI_CATALOGUE_CHANGE']
];

exports.up = (pgm) => {
  pgm.sql(`
    INSERT INTO app_role_permissions (app_role_id, permission_code)
    SELECT r.id, seeded.permission_code
    FROM app_roles r
    JOIN (VALUES ${WIDENED.map(
      ([role, code]) => `(${quote(role)}, ${quote(code)})`
    ).join(', ')}) AS seeded (role_code, permission_code)
      ON seeded.role_code = r.code
    ON CONFLICT (app_role_id, permission_code) DO NOTHING
  `);
};

exports.down = (pgm) => {
  // Forward-only in production per ADR-0007 — this exists for local development,
  // and it removes exactly the three rows `up()` writes; the row
  // `ROLE_ADMIN` already carried before this file ran is left alone.
  pgm.sql(`
    DELETE FROM app_role_permissions
    WHERE (app_role_id, permission_code) IN (
      SELECT r.id, seeded.permission_code
      FROM app_roles r
      JOIN (VALUES ${WIDENED.map(
        ([role, code]) => `(${quote(role)}, ${quote(code)})`
      ).join(', ')}) AS seeded (role_code, permission_code)
        ON seeded.role_code = r.code
    )
  `);
};

// SQL string literal for a value this file holds itself: single quotes doubled,
// so a value needs no hand-escaping and cannot drift from the plain strings.
function quote(value) {
  return `'${String(value).replace(/'/g, "''")}'`;
}
