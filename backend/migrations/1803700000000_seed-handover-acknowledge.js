/**
 * `PRD_HANDOVER_ACKNOWLEDGE` on the roles that can already acknowledge
 * (ADR-0061, slice 7).
 *
 * **What this seed changes, and why it comes before the route does.** The code
 * exists in the catalogue and was seeded on `ROLE_ADMIN` alone. Acknowledging a
 * submitted Shift handover was reachable by any Account holding a write Grant
 * on the Section, whatever its role, because `canAct({ write: true })` is
 * role-blind — and every role holds `PRD_HANDOVER_WRITE`. Putting
 * `POST /handovers/:id/acknowledge` behind its own code without this row would
 * therefore have taken acknowledging away from the incoming shift that does it
 * today. The five rows below keep every role's reach exactly as it is, and the
 * authority becomes a line an administrator can see and change in the Roles
 * Screen — which is the whole point of naming the act with its own code instead
 * of leaving it to a Grant.
 *
 * **The narrowing is deliberate and small.** Once this lands, an Account that
 * holds a write Grant on the Section but whose role has had
 * `PRD_HANDOVER_ACKNOWLEDGE` removed is refused the acknowledgement with
 * `PERMISSION_REQUIRED` — before any row is looked up — while it still opens,
 * writes and submits a handover under `PRD_HANDOVER_WRITE`. That is the
 * separation this card asks for: a distinct act behind a distinct code, so an
 * administrator can later restrict acknowledging to supervisors without
 * touching who may write the handover. Nothing else about the Module changes;
 * the four reads and the eleven writes are gated by codes already seeded on
 * every role.
 *
 * **`ROLE_ADMIN` is not named here.** It already holds the code from
 * `1803400000000_permissions-and-roles.js`, and the article below is
 * `ON CONFLICT DO NOTHING`, so naming it would write nothing and only suggest
 * the two migrations disagree.
 *
 * **Idempotent on purpose.** `ON CONFLICT DO NOTHING` on the pair, so the seed
 * only fills the gap: a database where an administrator has already taken the
 * code off a role is not silently re-granted it, and re-running this migration
 * is a no-op — the deploy step (ADR-0007) applies it to a copy of the current
 * schema before the new image starts, and must be able to say that twice.
 *
 * Backward-compatible per ADR-0007: five rows in a join table change nothing an
 * older running image reads or writes, because an older image never asks this
 * code at all.
 */

exports.shorthands = undefined;

// The roles that could already acknowledge: every role except administrator,
// which already holds the code. Stated here so the migration says exactly what
// it did rather than importing a moving list.
const ACKNOWLEDGING_ROLES = [
  'ROLE_STANDARD',
  'ROLE_OPERATOR',
  'ROLE_SUPERVISOR',
  'ROLE_ENGINEER',
  'ROLE_MANAGER'
];

exports.up = (pgm) => {
  pgm.sql(`
    INSERT INTO app_role_permissions (app_role_id, permission_code)
    SELECT r.id, 'PRD_HANDOVER_ACKNOWLEDGE'
    FROM app_roles r
    WHERE r.code IN (${ACKNOWLEDGING_ROLES.map((code) => `'${code}'`).join(', ')})
    ON CONFLICT (app_role_id, permission_code) DO NOTHING
  `);
};
