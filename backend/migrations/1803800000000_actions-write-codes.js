/**
 * `ACT_CHANGE` in the catalogue, and the six Actions write codes on every role
 * (ADR-0061, the Actions write retrofit).
 *
 * **What this seed changes, and why it comes before the routes do.** Every one
 * of the sixteen Actions write routes is reachable today by any Account holding
 * the right Grant at the Org Unit — `canAct({ write: true })` and
 * `canAct({ quality: true })` are role-blind, and `requireCapaWhyWrite` admits a
 * place on the CAPA's team without a Grant at all. The seed, by contrast, is
 * narrower: `ACT_MEASURE` and `ACT_VERIFY` were supervisor-and-above, and
 * `ACT_CAPA_OPEN`, `ACT_CAPA_VERIFY` and `ACT_CAPA_EFFECTIVENESS` were
 * engineer-and-above. Putting the routes behind those codes without this
 * migration would therefore have taken the writes away from the very people who
 * do them — an operator recording the containment it just fitted, an operator
 * holding Quality authority opening the investigation on its own line, a
 * technician with a place on a CAPA team writing the Why chain. So the six codes
 * are seeded on **every** role, and the retrofit takes nobody's act away.
 *
 * **A new code, because four of the sixteen acts have none.** The catalogue
 * named raising a Concern, measuring one, verifying one, and opening, verifying
 * and checking a CAPA. Nothing named linking or unlinking a Non-conformance,
 * handing an Action up, or calling one off — and a route gated by a code that
 * names a different act makes the Roles Screen lie, which is the one thing a
 * code buys over a Grant. `ACT_CHANGE` is those four acts, in the catalogue's
 * own `<MODULE>_<THING>_CHANGE` shape (`MTN_WORK_ORDERS_CHANGE` already covers
 * raising, assigning, completing and cancelling one Work order, and
 * `PRD_HANDOVER_WRITE` covers ten Production writes). It takes the catalogue's
 * next position (83) rather than a place inside the Actions group: `sort_order`
 * is what the roles editor learned, a released list is never renumbered, and
 * this migration is insert-only so it can only append. The Roles Screen groups
 * by `module`, so it renders inside the Actions group.
 * `src/modules/people/permissions.js` carries the identical entry in the
 * identical position — `test/integration/roles.test.js` asserts the frozen copy
 * and the source file agree.
 *
 * **The seed, before and after.** `ACT_CAPA_OPEN`, `ACT_CAPA_VERIFY` and
 * `ACT_CAPA_EFFECTIVENESS`: engineer, manager, administrator → the default
 * group, operator, supervisor, engineer, manager, administrator.
 * `ACT_MEASURE` and `ACT_VERIFY`: supervisor, engineer, manager,
 * administrator → the same six. `ACT_CHANGE`: new, seeded on the same six. Every
 * row is a widening in the same direction — towards today's reach, which is the
 * Grant, not the role.
 *
 * **No narrowing, and what that costs.** Nothing changes for any caller today:
 * an Account that could write an Action yesterday can write it today, because
 * every role it can hold carries the code. What changes is that the door is now
 * **visible and removable** — an administrator who decides that verifying an
 * Action is a supervisor's act, or that opening a CAPA is an engineer's, takes
 * the code off `ROLE_OPERATOR` in the Roles Screen and every operator loses it
 * at once. That is the whole of ADR-0061's value over a Grant, and it is the
 * same trade `1803700000000_seed-handover-acknowledge.js` made for the
 * Production handover's acknowledgement. This retrofit does **not** enforce the
 * seed's narrower declaration on its own: that would take live capabilities off
 * a plant to satisfy a list, and it is the owner's decision rather than this
 * migration's — the PR body says so in those words.
 *
 * **`ROLE_ADMIN` is named even though the short-circuit makes it moot.** An
 * administrator passes every `requirePermission` before a role set is read, so
 * the row changes no answer; without it the Roles Screen would show the
 * catalogue's newest code on no administrator role, and an administrator
 * reading what `ROLE_ADMIN` means would take the omission for a decision.
 *
 * **Idempotent on purpose.** `ON CONFLICT DO NOTHING` on both inserts, so the
 * seed only ever fills the gap: a database where an administrator has already
 * put a code on a role, or taken one off, is left exactly as it is, and
 * re-running this migration is a no-op — the deploy step (ADR-0007) applies it
 * to a copy of the current schema before the new image starts, and must be able
 * to say that twice.
 *
 * Backward-compatible per ADR-0007: thirty-six rows in a join table and one
 * catalogue row change nothing an older running image reads or writes, because
 * an older image never asks these codes at all.
 */

exports.shorthands = undefined;

// The one code this migration adds to the catalogue, frozen here rather than
// required from src/modules/people/permissions.js: a migration is a one-way
// door, and an edit to that file must never change what this one does to a
// database that has already run it (ADR-0007, and permissions.js's own header).
const NEW_CODE = {
  code: 'ACT_CHANGE',
  module: 'Actions',
  label: 'Change an Action',
  description: 'Link or unlink a Non-conformance, hand an Action up, or call one off.',
  sortOrder: 83
};

// Every write code the sixteen routes ask, stated as a plain list here so this
// file says exactly what it did rather than importing a moving one.
const WRITE_CODES = [
  NEW_CODE.code,
  'ACT_MEASURE',
  'ACT_VERIFY',
  'ACT_CAPA_OPEN',
  'ACT_CAPA_VERIFY',
  'ACT_CAPA_EFFECTIVENESS'
];

// Every seeded role, because every role reaches these writes today through a
// Grant (or a place on a CAPA team, which needs no Grant at all). The default
// group is named first: it is the one every approved Account carries.
const WRITE_ROLES = [
  'ROLE_STANDARD',
  'ROLE_OPERATOR',
  'ROLE_SUPERVISOR',
  'ROLE_ENGINEER',
  'ROLE_MANAGER',
  'ROLE_ADMIN'
];

exports.up = (pgm) => {
  pgm.sql(`
    INSERT INTO permissions (code, module, label, description, sort_order)
    VALUES (
      ${quote(NEW_CODE.code)},
      ${quote(NEW_CODE.module)},
      ${quote(NEW_CODE.label)},
      ${quote(NEW_CODE.description)},
      ${NEW_CODE.sortOrder}
    )
    ON CONFLICT (code) DO NOTHING
  `);

  pgm.sql(`
    INSERT INTO app_role_permissions (app_role_id, permission_code)
    SELECT r.id, seeded.permission_code
    FROM app_roles r
    CROSS JOIN unnest(ARRAY[${WRITE_CODES.map(quote).join(', ')}]::TEXT[]) AS seeded (permission_code)
    WHERE r.code IN (${WRITE_ROLES.map(quote).join(', ')})
    ON CONFLICT (app_role_id, permission_code) DO NOTHING
  `);
};

exports.down = (pgm) => {
  // Forward-only in production per ADR-0007 — this exists for local
  // development, and it reverses only what this file wrote.
  pgm.sql(`
    DELETE FROM app_role_permissions
    WHERE permission_code IN (${WRITE_CODES.map(quote).join(', ')})
      AND app_role_id IN (SELECT id FROM app_roles WHERE code IN (${WRITE_ROLES.map(quote).join(', ')}))
  `);
  pgm.sql(`DELETE FROM permissions WHERE code = ${quote(NEW_CODE.code)}`);
};

// SQL string literal for a value this file holds itself: single quotes doubled,
// so the apostrophe-free descriptions above need no hand-escaping and cannot
// drift from the plain strings.
function quote(value) {
  return `'${String(value).replace(/'/g, "''")}'`;
}
