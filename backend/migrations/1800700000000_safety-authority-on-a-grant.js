/**
 * Safety authority on a Grant (issue #225, ADR-0035 applied a second time).
 *
 * The Safety Module (#223) has decisions only some people may take: classify
 * an injury — who was hurt, the injury type, the body part — set or correct
 * an incident's severity, record the days it cost, and close it. ADR-0035
 * already decided, for Quality, that a standing like this belongs on the
 * Grant rather than on a role: a role is plant-wide and an Account holds
 * exactly one, so a `safety_officer` role would mean a safety officer on
 * Line 2 could close an incident on Line 5, and would collide with whatever
 * else that Account already is (a line supervisor who is also the safety
 * contact for their own line could not be both). Safety authority applies
 * the same pattern a second time, deliberately and without inventing
 * anything new: it belongs to a place, it reaches downward like the Grant
 * itself, and Approval sets it along with the rest of the Grant set.
 *
 * So: a second boolean on `app_user_org_units`, defaulting FALSE,
 * deliberately independent of both `can_write` and `quality_authority`. None
 * of the three implies either of the others — a view-only Grant may carry
 * Safety authority (a safety officer who reads a line and classifies its
 * injuries but does not record work against it), an edit Grant need not, and
 * a Grant may carry Safety authority, Quality authority, both or neither, in
 * any combination with its level. `canAct` (modules/people/authorization.js)
 * reads it with its own `safety` option, beside `write` and `quality`.
 *
 * Why a stored column rather than a second Grant row, a `safety_officer` role
 * or a derived fact: see ADR-0035's own "Considered options" — the reasoning
 * is unchanged by which Module is asking. Why not generalise the two
 * booleans into an authority set now that there are two of them: see #223
 * decision 7 and this ticket's own ADR (docs/adr/0039) — two is not yet a
 * pattern, and generalising would rewrite a Module that shipped last week for
 * no change in behaviour. The **third** authority is the trigger to revisit,
 * and the ADR says so.
 *
 * Backward-compatible, per ADR-0007's expand-now-contract-later rule: a NOT
 * NULL column with a constant default is safe for the version this migration
 * replaces to keep running against, because every existing reader and writer
 * of `app_user_org_units` simply does not name it. Nothing is backfilled — a
 * Grant nobody has given Safety authority to does not hold it, which is the
 * only reading that does not silently hand the authority out on deploy: a
 * backfilled TRUE would grant Safety authority, unasked, to whoever already
 * held some other Grant, at the exact moment the column exists to be read.
 * `approveAccount` (modules/people/service.js) is the one writer: Approval
 * sets the flag along with the rest of the Grant set and replaces it with it,
 * so a later Approval that omits it removes it.
 *
 * There is no data migration and no index, for the same reason
 * `quality_authority`'s own migration has neither: the flag is read only by
 * `canAct`, which already joins this table by `app_user_id` (the existing
 * `app_user_org_units_user_idx`), and a boolean filter on a handful of rows
 * per caller is not something an index would serve.
 */

exports.shorthands = undefined;

exports.up = (pgm) => {
  pgm.sql(`
    ALTER TABLE app_user_org_units
      ADD COLUMN safety_authority BOOLEAN NOT NULL DEFAULT FALSE
  `);
};

exports.down = (pgm) => {
  // Forward-only in production per ADR-0007 — this exists for local
  // development and for node-pg-migrate's own requirement that a migration
  // define both directions. Dropping the column drops every Grant's Safety
  // authority, which is why it is a `down` and not a routine step: the rows
  // that carried it are not recoverable from anything else.
  pgm.sql('ALTER TABLE app_user_org_units DROP COLUMN safety_authority');
};
