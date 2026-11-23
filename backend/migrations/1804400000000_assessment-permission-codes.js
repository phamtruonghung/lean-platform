/**
 * Four Assessment codes, so the routes that read, maintain, sit and mark an
 * Assessment have something to ask (issue #588, slice 1).
 *
 * **What this seed changes, and why it comes before the routes do.** The
 * Assessment routes are about to ask `PPL_ASSESSMENT_DISPLAY`,
 * `PPL_ASSESSMENT_CHANGE`, `PPL_ASSESSMENT_SIT` and `PPL_ASSESSMENT_MARK`. A
 * code the catalogue does not hold cannot be put on a Role, so the rows must
 * exist, and be on the Roles that should hold them, before any route refuses a
 * caller for lacking one. Reading and sitting are open to every seeded Role,
 * the default group included, because most of a plant sits its own Assessment
 * and a shop-floor Account must not be locked out of it. Maintaining the
 * Question bank and marking an Attempt are Team Leader and above: the
 * supervisor, engineer, manager and admin Roles, the shape
 * `1803500000000_supervisor-holds-maintenance-writes.js` used. "Team Leader and
 * above" is therefore a Role holding the code, never a rank test in code; an
 * operator with a write Grant cannot add Questions until an administrator puts
 * `PPL_ASSESSMENT_CHANGE` on `ROLE_OPERATOR` from the Roles Screen.
 *
 * **Position, not reordering.** The four rows take the catalogue's next
 * positions (84-87) rather than a place inside the People group: `sort_order`
 * is what the roles editor learned, a released list is never renumbered, and
 * this migration is insert-only so it can only append. The Roles Screen groups
 * by `module`, so all four render inside the People group. `permissions.js`
 * carries the identical four entries in the identical order; `roles.test.js`
 * asserts the seeded rows and the source file agree.
 *
 * **Idempotent on purpose.** `ON CONFLICT DO NOTHING` on the inserts and on the
 * grants, so re-running this migration is a no-op: a database where an
 * administrator has already moved a code between Roles is left exactly as it
 * is. The deploy step (ADR-0007) applies it to a copy of the current schema
 * before the new image starts, and must be able to say that twice.
 *
 * Forward-only per ADR-0007, and this one defines no `down`: the four rows are
 * the catalogue's own vocabulary, and removing them would break every route
 * that asks the codes while an older image is still running. Backward-
 * compatible: rows in two join tables change nothing an older running image
 * reads or writes, because an older image never asks these codes at all.
 */

exports.shorthands = undefined;

// The codes, narrowly stated here rather than imported from `permissions.js`,
// so this migration says exactly what it did to a database.
const ASSESSMENT_CODES = [
  {
    code: 'PPL_ASSESSMENT_DISPLAY',
    module: 'People',
    label: 'Assessments',
    description: 'Read an Assessment, its Attempts, and the Question bank behind it.',
    sortOrder: 84
  },
  {
    code: 'PPL_ASSESSMENT_CHANGE',
    module: 'People',
    label: 'Maintain Assessments',
    description: 'Correct a Question bank, create an Assessment, assign it, allow a retake, or close one.',
    sortOrder: 85
  },
  {
    code: 'PPL_ASSESSMENT_SIT',
    module: 'People',
    label: 'Sit my Assessment',
    description: "Start, answer and submit the caller's own Attempt.",
    sortOrder: 86
  },
  {
    code: 'PPL_ASSESSMENT_MARK',
    module: 'People',
    label: 'Mark an Assessment',
    description: 'Mark a submitted Attempt: award or refuse a point, fix the final score, write the note.',
    sortOrder: 87
  }
];

const EVERY_ROLE = [
  'ROLE_STANDARD',
  'ROLE_OPERATOR',
  'ROLE_SUPERVISOR',
  'ROLE_ENGINEER',
  'ROLE_MANAGER',
  'ROLE_ADMIN'
];

const TEAM_LEADER_AND_ABOVE = ['ROLE_SUPERVISOR', 'ROLE_ENGINEER', 'ROLE_MANAGER', 'ROLE_ADMIN'];

// Which Roles hold which code, as (code, role) pairs so one statement says it.
const GRANTS = [
  ...['PPL_ASSESSMENT_DISPLAY', 'PPL_ASSESSMENT_SIT'].flatMap((code) =>
    EVERY_ROLE.map((role) => [code, role])
  ),
  ...['PPL_ASSESSMENT_CHANGE', 'PPL_ASSESSMENT_MARK'].flatMap((code) =>
    TEAM_LEADER_AND_ABOVE.map((role) => [code, role])
  )
];

exports.up = (pgm) => {
  for (const entry of ASSESSMENT_CODES) {
    pgm.sql(`
      INSERT INTO permissions (code, module, label, description, sort_order)
      VALUES (${quote(entry.code)}, ${quote(entry.module)}, ${quote(entry.label)}, ${quote(entry.description)}, ${entry.sortOrder})
      ON CONFLICT (code) DO NOTHING
    `);
  }

  pgm.sql(`
    INSERT INTO app_role_permissions (app_role_id, permission_code)
    SELECT r.id, granted.permission_code
    FROM (VALUES ${GRANTS.map(([code, role]) => `(${quote(code)}, ${quote(role)})`).join(', ')})
      AS granted (permission_code, role_code)
    JOIN app_roles r ON r.code = granted.role_code
    ON CONFLICT (app_role_id, permission_code) DO NOTHING
  `);
};

// SQL string literal for a value this file holds itself: single quotes doubled,
// so the apostrophes in the descriptions need no hand-escaping and cannot drift
// from the plain strings above.
function quote(value) {
  return `'${String(value).replace(/'/g, "''")}'`;
}
