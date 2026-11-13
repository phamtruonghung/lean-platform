/**
 * The one Safety write code the retrofit has to widen (ADR-0061, the Safety
 * write retrofit, issue #537).
 *
 * **What this seed changes, and why it comes before the routes do.** The four
 * Safety write routes this slice gates — a severity correction, a
 * classification, the days and the close — stood on
 * `requireSafetyIncidentSafetyAuthority`, which asks `canAct({ safety: true })`:
 * Safety authority on a Grant at the incident's Org Unit, a flag **any** role may
 * carry (ADR-0035, ADR-0039). Two of them now also ask `SAF_CLASSIFY`, and the
 * seed declared that code on supervisor-and-above — `ROLE_SUPERVISOR`,
 * `ROLE_ENGINEER`, `ROLE_MANAGER`, `ROLE_ADMIN`. Gating without this migration
 * would therefore take the act away from an operator (or a Standard-only
 * Account) holding Safety authority on its own line, which is exactly the silent
 * narrowing this retrofit must not do. So `SAF_CLASSIFY` is seeded on every
 * role, and the retrofit takes nobody's act away.
 *
 * **The seed, before and after.** Plain SQL this file holds itself, so it says
 * exactly what it did:
 *
 *   - `SAF_CLASSIFY` — supervisor, engineer, manager, administrator
 *     → the default group, operator, supervisor, engineer, manager,
 *     administrator (two rows added).
 *   - `SAF_INCIDENTS_RECORD` — the other code the four routes ask — already sits
 *     on all six roles (migration 1803400000000's ROLE_STANDARD and
 *     ROLE_OPERATOR arrays), so no row is written for it, and the days and the
 *     close narrow nobody.
 *
 * Two rows, both a widening, both in the same direction: towards today's reach,
 * which is the Grant, not the role.
 *
 * **No code is added to the catalogue.** `SAF_CLASSIFY` and
 * `SAF_INCIDENTS_RECORD` already exist and already name these acts — "record or
 * read an injured person's diagnosis" and "record a Safety incident" — so this
 * file writes rows, never a `permissions` row, and the catalogue stays at 83.
 *
 * **`ROLE_ADMIN` is not named.** It already holds `SAF_CLASSIFY`, and an
 * administrator passes every `requirePermission` before a role set is read, so
 * the row would change no answer either way; the list is the statement of what
 * this file adds, and this file adds nothing to it.
 *
 * **Idempotent on purpose.** `ON CONFLICT DO NOTHING`, so the seed only ever
 * fills the gap: a database where an administrator has already put the code on a
 * role, or taken it off, is left exactly as it is, and re-running this migration
 * is a no-op — the deploy step (ADR-0007) applies it to a copy of the current
 * schema before the new image starts, and must be able to say that twice.
 *
 * **`down()` reverses only the rows this file adds** and names them one by one,
 * so a local `migrate:down` does not take `SAF_CLASSIFY` off supervisor,
 * engineer, manager or administrator — rows 1803400000000 seeded and this slice
 * relies on. Forward-only in production per ADR-0007; the down exists for a
 * developer's own database.
 *
 * Backward-compatible per ADR-0007: two rows in a join table change nothing an
 * older running image reads or writes, because an older image never asks
 * `SAF_CLASSIFY` at all.
 */

exports.shorthands = undefined;

// The rows this file adds, named as (role, code) pairs. A plain list rather than
// an array of role codes, because that is the only way `down()` can remove
// exactly what `up()` wrote: the code already sits on four of the six roles.
const WIDENED = [
  // Classifying an injury, which the seed declared supervisor-and-above: today
  // any Account holding Safety authority at the Org Unit, whatever its role.
  ['ROLE_STANDARD', 'SAF_CLASSIFY'],
  // The same act, for an Account whose own `app_users.role` is operator: the
  // legacy_role's set is unioned with the default group, and without this row an
  // operator would hold the code only through ROLE_STANDARD — the two are
  // named so an administrator reading either role sees it.
  ['ROLE_OPERATOR', 'SAF_CLASSIFY']
];

// `ROLE_ADMIN`, `ROLE_SUPERVISOR`, `ROLE_ENGINEER` and `ROLE_MANAGER` already
// carry `SAF_CLASSIFY`, so this file writes two rows, not six.
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
  // Forward-only in production per ADR-0007 — this exists for local
  // development, and it removes exactly the two rows `up()` writes; the rows the
  // same code already sat on before this file ran are left alone.
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
