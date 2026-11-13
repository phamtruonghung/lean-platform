/**
 * The Quality write codes on every role (ADR-0061, the Quality write retrofit).
 *
 * **What this seed changes, and why it comes before the routes do.** The
 * thirteen Quality write routes that this slice gates are reachable today by any
 * Account holding the right Grant at the Org Unit — `canAct({ write: true })` is
 * role-blind, and the four decisions a Non-conformance's status moves through
 * ask `canAct({ quality: true })`, which is a flag on the same Grant. The seed,
 * by contrast, is narrower: `QLT_NONCONFORMANCES_DISPOSE` was engineer-and-above,
 * and `QLT_SLIDESHOW_CHOOSE` and `QLT_SUPPLIER_NCRS_RECORD` were administrator-
 * only. Putting the routes behind those codes without this migration would have
 * taken the writes away from the people who do them — an operator holding Quality
 * authority granting a Concession on its own line, a Team Leader curating the
 * shop-floor wall, an operator recording the supplier NCR it found at goods-in.
 * So every code the routes ask is seeded on **every** role, and the retrofit
 * takes nobody's act away.
 *
 * **The seed, before and after.** Plain SQL this file holds itself, so it says
 * exactly what it did:
 *
 *   - `QLT_NONCONFORMANCES_DISPOSE` — engineer, manager, administrator
 *     → the default group, operator, supervisor, engineer, manager,
 *     administrator (three rows added).
 *   - `QLT_SLIDESHOW_CHOOSE` — administrator
 *     → the same six (five rows added).
 *   - `QLT_SUPPLIER_NCRS_RECORD` — administrator
 *     → the same six (five rows added).
 *   - `QLT_NONCONFORMANCES_RECORD` and `QLT_COMPLAINTS_RECORD` — already on the
 *     same six (migration 1803400000000's ROLE_STANDARD/ROLE_OPERATOR arrays),
 *     so no row is written for them.
 *
 * Thirteen rows, every one a widening, all in the same direction: towards
 * today's reach, which is the Grant, not the role.
 *
 * **No narrowing, and what it costs.** Nothing changes for any caller today: an
 * Account that could disposition, dispose, choose a slide-show issue or record a
 * supplier NCR yesterday can do it today, because every role it can hold carries
 * the code. What changes is that the door is now **visible and removable** — an
 * administrator who decides that granting a Concession is an engineer's act
 * takes `QLT_NONCONFORMANCES_DISPOSE` off `ROLE_OPERATOR` in the Roles Screen and
 * every operator loses it at once, which a Grant cannot express. This retrofit
 * does **not** enforce the seed's narrower declaration on its own: that would
 * take live capabilities off a plant to satisfy a list, and it is the owner's
 * decision rather than this migration's.
 *
 * **`ROLE_ADMIN` is named even though the short-circuit makes it moot.** An
 * administrator passes every `requirePermission` before a role set is read, so
 * the row changes no answer; without it the Roles Screen would show the code on
 * no administrator role, and an administrator reading what `ROLE_ADMIN` means
 * would take the omission for a decision. It is left out of the two codes it
 * already held, because `ON CONFLICT DO NOTHING` would write nothing there
 * anyway and the list is the statement of what this file adds.
 *
 * **Idempotent on purpose.** `ON CONFLICT DO NOTHING`, so the seed only ever
 * fills the gap: a database where an administrator has already put a code on a
 * role, or taken one off, is left exactly as it is, and re-running this migration
 * is a no-op — the deploy step (ADR-0007) applies it to a copy of the current
 * schema before the new image starts, and must be able to say that twice.
 *
 * **`down()` reverses only the rows this file adds** and names them one by one,
 * so a local `migrate:down` does not take `QLT_NONCONFORMANCES_DISPOSE` off
 * engineer, manager or administrator — rows 1803400000000 seeded and this slice
 * relies on. Forward-only in production per ADR-0007; the down exists for a
 * developer's own database.
 *
 * Backward-compatible per ADR-0007: thirteen rows in a join table change nothing
 * an older running image reads or writes, because an older image never asks
 * these codes at all.
 */

exports.shorthands = undefined;

// The rows this file adds, named as (role, code) pairs. A plain list rather than
// a cross join of two arrays, because that is the only way `down()` can remove
// exactly what `up()` wrote: the codes it touches already sat on some of these
// roles before this file ran.
const WIDENED = [
  // Conceding, reworking or scrapping nonconforming product: today any Grant
  // carrying Quality authority at the Org Unit, whatever the Account's role.
  ['ROLE_STANDARD', 'QLT_NONCONFORMANCES_DISPOSE'],
  ['ROLE_OPERATOR', 'QLT_NONCONFORMANCES_DISPOSE'],
  ['ROLE_SUPERVISOR', 'QLT_NONCONFORMANCES_DISPOSE'],
  // Choosing an issue for the shop-floor wall: today any write Grant reaching
  // the issue's Org Unit, whatever the Account's role.
  ['ROLE_STANDARD', 'QLT_SLIDESHOW_CHOOSE'],
  ['ROLE_OPERATOR', 'QLT_SLIDESHOW_CHOOSE'],
  ['ROLE_SUPERVISOR', 'QLT_SLIDESHOW_CHOOSE'],
  ['ROLE_ENGINEER', 'QLT_SLIDESHOW_CHOOSE'],
  ['ROLE_MANAGER', 'QLT_SLIDESHOW_CHOOSE'],
  // Recording a supplier NCR, and working it (disposition, close, link): today
  // any write Grant reaching the Org Unit, whatever the Account's role.
  ['ROLE_STANDARD', 'QLT_SUPPLIER_NCRS_RECORD'],
  ['ROLE_OPERATOR', 'QLT_SUPPLIER_NCRS_RECORD'],
  ['ROLE_SUPERVISOR', 'QLT_SUPPLIER_NCRS_RECORD'],
  ['ROLE_ENGINEER', 'QLT_SUPPLIER_NCRS_RECORD'],
  ['ROLE_MANAGER', 'QLT_SUPPLIER_NCRS_RECORD']
];

// `ROLE_ADMIN` already carries all three codes (migration 1803400000000 seeds
// the whole catalogue onto it), and `QLT_NONCONFORMANCES_RECORD` /
// `QLT_COMPLAINTS_RECORD` already sit on every role — so this file writes
// thirteen rows, not eighteen.
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
  // development, and it removes exactly the thirteen rows `up()` writes; the
  // rows the same codes already sat on before this file ran are left alone.
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
