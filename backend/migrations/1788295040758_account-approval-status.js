/**
 * Approval gets a state of its own, distinct from `is_active` (issue #8,
 * CONTEXT.md's Approval definition).
 *
 * `app_users.is_active` (added inactive-by-default in
 * `1788279276376_accounts-start-inactive-and-audited.js`, issue #6) is a
 * single boolean, and issue #8 needs four states, not two: an Account
 * awaiting Approval, one admitted and active, one admitted and later
 * deactivated (issue #8's own criterion — deactivation is not deletion), and
 * one an administrator has rejected outright. `is_active` alone cannot tell
 * "never yet decided" apart from "decided against, or decided-then-turned-
 * off" — all three would otherwise read as `is_active = FALSE`.
 *
 * A rejected Account has to be a state, not the absence of a row, because
 * `resolveAccountForIdentity` (service.js, issue #6) creates an Account on
 * first sign-in with no sign-up step of its own: if rejection meant deleting
 * the row, the same person's next sign-in would recreate it and put them
 * straight back in the Approval queue an administrator just cleared them out
 * of.
 *
 * `approval_status` therefore carries the decision itself and `is_active`
 * keeps carrying "may this Account act right now" — the two together are
 * what express all four states:
 *
 *   pending                    -> ('pending',  is_active = FALSE)
 *   approved                   -> ('approved', is_active = TRUE)
 *   approved, then deactivated -> ('approved', is_active = FALSE)
 *   rejected                   -> ('rejected', is_active = FALSE)
 *
 * Keeping that mapping true is application logic (authorization.js /
 * service.js), the same way `is_active`'s own meaning was never a database
 * constraint either — a CHECK here could only constrain the column's own
 * three values, not the relationship between two columns across a
 * transition, so that is not attempted.
 *
 * Backfill is honest about what the existing rows can and cannot say: only
 * `is_active = TRUE` is evidence a row was ever actually admitted (the
 * bootstrap administrator from issue #6, or a row inserted by hand before
 * this issue existed), so those become `approved`; every other row —
 * including any inactive row, since `is_active = FALSE` on its own does not
 * distinguish "never decided" from "rejected" — stays at the column's own
 * default, `pending`, rather than this migration guessing which.
 */

exports.shorthands = undefined;

exports.up = (pgm) => {
  pgm.sql(`
    ALTER TABLE app_users
      ADD COLUMN approval_status TEXT NOT NULL DEFAULT 'pending'
        CHECK (approval_status IN ('pending', 'approved', 'rejected'))
  `);

  // Backfill per the file header: an active row is the only honest signal
  // that a decision to admit was ever made, so only those become 'approved'.
  // Everything else keeps the column's own default.
  pgm.sql(`
    UPDATE app_users SET approval_status = 'approved' WHERE is_active = TRUE
  `);
};

exports.down = (pgm) => {
  // Forward-only in production per ADR-0007 — this exists for local
  // development and for node-pg-migrate's own requirement that a migration
  // define both directions.
  pgm.sql('ALTER TABLE app_users DROP COLUMN approval_status');
};
