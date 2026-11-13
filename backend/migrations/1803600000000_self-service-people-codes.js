/**
 * Two self-service codes, so gating the People writes takes nobody's own act
 * away from them (ADR-0061, slice 5b).
 *
 * **What this seed changes, and why it comes before the routes do.** The
 * People Module's writes are about to ask their naming codes —
 * `PPL_TRAINING_CHANGE`, `PPL_ATTENDANCE_CHANGE`, `PPL_LEAVE_REQUESTS_DECIDE` —
 * which are seeded on supervisor-and-above only. Three of those writes are a
 * person's own act, not authority over somebody else's record: a Trainee
 * answers the question a Training record asks them, and an Employee raises a
 * leave request and cancels it before anyone decides. Every seeded role holds
 * no code for that act today (`PPL_SIGNATURE_OWN` is the catalogue's only
 * self-service code), so gating them with the managing codes alone would have
 * refused a trainee their own training answer and an operator their own leave
 * request. The two codes are seeded here on **every** role — including the
 * default group every approved Account carries — so the retrofit never locks a
 * shop-floor account out of its own record.
 *
 * **The narrowing, stated rather than discovered.** The managing codes stay
 * supervisor-and-above, and become the door for everything done to someone
 * else's record. An operator who holds an edit Grant on the People Screens
 * therefore loses the managing writes — raising a Training record, confirming
 * an Attendance sheet, approving a leave request — until an administrator adds
 * the code to `ROLE_OPERATOR` from the Roles Screen. That is ADR-0061's point:
 * the code is the visible authority, not a side effect of an old Grant. It is a
 * deliberate, named behaviour change, not an accident of this seed, and it is
 * repeated in the retrofit's PR body and in `docs/authorization-model.md`.
 *
 * **Position, not reordering.** The two rows take the catalogue's next
 * positions (81, 82) rather than a place inside the People group: `sort_order`
 * is what the roles editor learned, a released list is never renumbered, and
 * this migration is insert-only so it can only append. The Roles Screen groups
 * by `module`, so both render inside the People group. `permissions.js` carries
 * the identical two entries in the identical order — `roles.test.js` asserts
 * the frozen copy and the source file agree.
 *
 * **Idempotent on purpose.** `ON CONFLICT DO NOTHING` on both inserts, so
 * re-running this migration is a no-op: a database where an administrator has
 * already put a code on a role is left exactly as it is. The deploy step
 * (ADR-0007) applies it to a copy of the current schema before the new image
 * starts, and must be able to say that twice.
 *
 * Forward-only per ADR-0007, and this one defines no `down`: the two rows are
 * the catalogue's own vocabulary, and removing them would break every route
 * that asks the codes while an older image is still running. Backward-
 * compatible: rows in two join tables change nothing an older running image
 * reads or writes, because an older image never asks these codes at all.
 */

exports.shorthands = undefined;

// The codes, narrowly stated here rather than imported from `permissions.js`,
// so this migration says exactly what it did to a database.
const SELF_SERVICE_CODES = [
  {
    code: 'PPL_TRAINING_ANSWER_OWN',
    module: 'People',
    label: 'Answer my Training',
    description: "Answer the caller's own training question as its Trainee.",
    sortOrder: 81
  },
  {
    code: 'PPL_LEAVE_REQUESTS_RAISE',
    module: 'People',
    label: 'Raise my Leave',
    description: "Raise the caller's own leave request, and cancel it before a decision.",
    sortOrder: 82
  }
];

// Every seeded role, so no Account loses its own act. An administrator can
// still take a code away from a role in the Roles Screen; this seed only fills
// the gap that the retrofit would otherwise open.
const SELF_SERVICE_ROLES = [
  'ROLE_STANDARD',
  'ROLE_OPERATOR',
  'ROLE_SUPERVISOR',
  'ROLE_ENGINEER',
  'ROLE_MANAGER',
  'ROLE_ADMIN'
];

exports.up = (pgm) => {
  for (const entry of SELF_SERVICE_CODES) {
    pgm.sql(`
      INSERT INTO permissions (code, module, label, description, sort_order)
      VALUES (${quote(entry.code)}, ${quote(entry.module)}, ${quote(entry.label)}, ${quote(entry.description)}, ${entry.sortOrder})
      ON CONFLICT (code) DO NOTHING
    `);
  }

  pgm.sql(`
    INSERT INTO app_role_permissions (app_role_id, permission_code)
    SELECT r.id, seeded.permission_code
    FROM app_roles r
    CROSS JOIN unnest(ARRAY[${SELF_SERVICE_CODES.map((entry) => quote(entry.code)).join(', ')}]::TEXT[])
      AS seeded (permission_code)
    WHERE r.code IN (${SELF_SERVICE_ROLES.map(quote).join(', ')})
    ON CONFLICT (app_role_id, permission_code) DO NOTHING
  `);
};

// SQL string literal for a value this file holds itself: single quotes doubled,
// so the apostrophes in the descriptions need no hand-escaping and cannot drift
// from the plain strings above.
function quote(value) {
  return `'${String(value).replace(/'/g, "''")}'`;
}
