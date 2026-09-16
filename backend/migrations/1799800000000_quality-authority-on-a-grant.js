/**
 * Quality authority on a Grant (issue #204, ADR-0035).
 *
 * The Quality Module has decisions only some people may take: granting a
 * Concession, reopening a Non-conformance, opening a CAPA and verifying one
 * held. Until now a Grant carried one flag, `can_write`, and a role is
 * plant-wide — so an `engineer` on Line 2 could accept bad product on Line 5,
 * which is exactly the separation ISO 9001's auditors look for. ADR-0035
 * decides the authority belongs on the Grant, where it reaches downward like
 * the Grant itself and belongs to a place rather than to a job title.
 *
 * So: one boolean on `app_user_org_units`, defaulting FALSE, deliberately
 * independent of `can_write`. Quality authority does not imply write and write
 * does not imply Quality authority — a view-only Grant may carry it (a quality
 * engineer who reads a line and decides about its bad product), and an edit
 * Grant need not (a line supervisor who records work but may not release
 * nonconforming product). `canAct` (modules/people/authorization.js) reads it
 * with its own `quality` option, beside `write`.
 *
 * Why a stored column rather than a second Grant row, a `quality_engineer`
 * role or a derived fact: see ADR-0035's own "Considered options". The short
 * version is that a role is plant-wide and an Account holds exactly one, and
 * that "whoever may record work on a line" must not become "whoever may accept
 * its bad product".
 *
 * Backward-compatible, per ADR-0007's expand-now-contract-later rule: a NOT
 * NULL column with a constant default is safe for the version this migration
 * replaces to keep running against, because every existing reader and writer
 * of `app_user_org_units` simply does not name it. Nothing is backfilled — a
 * Grant nobody has given Quality authority to does not hold it, which is the
 * only reading that does not silently hand the authority out on deploy.
 * `approveAccount` (modules/people/service.js) is the one writer: Approval
 * sets the flag along with the rest of the Grant set and replaces it with it,
 * so a later Approval that omits it removes it.
 *
 * There is no data migration and no index. The flag is read only by `canAct`,
 * which already joins this table by `app_user_id` (the existing
 * `app_user_org_units_user_idx`), and a boolean filter on a handful of rows
 * per caller is not something an index would serve.
 */

exports.shorthands = undefined;

exports.up = (pgm) => {
  pgm.sql(`
    ALTER TABLE app_user_org_units
      ADD COLUMN quality_authority BOOLEAN NOT NULL DEFAULT FALSE
  `);
};

exports.down = (pgm) => {
  // Forward-only in production per ADR-0007 — this exists for local
  // development and for node-pg-migrate's own requirement that a migration
  // define both directions. Dropping the column drops every Grant's Quality
  // authority, which is why it is a `down` and not a routine step: the rows
  // that carried it are not recoverable from anything else.
  pgm.sql('ALTER TABLE app_user_org_units DROP COLUMN quality_authority');
};
