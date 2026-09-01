/**
 * Accounts start inactive, and their writes are attributed and audited.
 * See issue #6 and CONTEXT.md's definition of Account/Approval.
 *
 * `app_users` and `app_user_org_units` are inherited from the baseline
 * (`1756000000000_baseline.js`), carried over from `maintenance-management`
 * where Accounts were created by an administrator, by hand, not by
 * self-registration. That premise no longer holds: per issue #1's
 * Implementation Decisions, "Having an identity is not admission. Sign-up is
 * open. On first sign-in the API creates an Account in an inactive state, and
 * every endpoint except the caller's own status refuses an inactive Account."
 * `app_users.is_active` defaults to `TRUE` in the baseline — right for a table
 * an administrator populates deliberately, wrong for one the API now inserts
 * into on an arbitrary stranger's first sign-in. This migration corrects that
 * default, and attaches the two mechanisms every other table the API writes
 * to already carries: actor columns and the audit trail.
 *
 * ## Why the default changes rather than the application always setting it
 *
 * The baseline's own reasoning for `set_updated_at()` applies with more force
 * here: "a column that depends on every INSERT remembering to set it is a
 * column that is right until somebody adds the twentieth route" (see that
 * migration's comments around `set_actor_columns()`). For `is_active` that is
 * not merely a correctness bug waiting to happen, it is a security one — a
 * route that forgets to pass `is_active: false` on self-registration silently
 * admits an unapproved caller. Flipping the column default means an omitted
 * value fails closed, and the one place `TRUE` is ever written explicitly is
 * the bootstrap admin path, exactly where that word should be visible.
 *
 * ## Why actor columns and audit are attached now, not later
 *
 * Issue #6 is "the Platform's first write" in the sense that matters here:
 * the first table an unauthenticated stranger's own action inserts a row
 * into. Its own acceptance criteria requires "every write records the acting
 * Account, set transaction-locally so that concurrent requests sharing a
 * pooled connection never cross-attribute" — an assertion that needs
 * something to assert against. `audit_log.changed_by` and
 * `app_users.created_by`/`updated_by` are that: both are filled from the same
 * `app.user_id` transaction-local setting every other audited table in this
 * schema already reads (`audit_row_change()`, `set_actor_columns()` — both
 * defined in the baseline and unchanged here). Nothing sensitive enters
 * `audit_log.old_values`/`new_values`: `app_users` carries no password column
 * by design (ADR-0002 — identity, including any credential, lives in
 * Supabase Auth, not here).
 *
 * `app_users` and `app_user_org_units` already have Row Level Security
 * enabled — they existed in the baseline before
 * `1756000000002_deny-all-rls.js`'s catalog sweep enabled RLS on every table
 * that existed in `public` at the time it ran — so this migration creates no
 * table and has no RLS obligation of its own.
 *
 * `attach_actor_columns()` and `attach_audit()` are both idempotent-by-name
 * helpers defined in the baseline (`CREATE TRIGGER`, no `IF NOT EXISTS`), so
 * `down()` below drops the four triggers this migration's `up()` adds by the
 * exact names those helpers generate, rather than attempting to reverse the
 * helpers themselves.
 */

exports.shorthands = undefined;

exports.up = (pgm) => {
  // A fresh Account starts inactive — "awaiting Approval" until an
  // administrator activates it. See the file header for why this is a column
  // default rather than something every insert route must remember.
  pgm.sql('ALTER TABLE app_users ALTER COLUMN is_active SET DEFAULT FALSE');

  // created_by/updated_by, filled from app.user_id the same way every
  // maintenance table already is.
  pgm.sql(`SELECT attach_actor_columns('app_users')`);
  pgm.sql(`SELECT attach_actor_columns('app_user_org_units')`);

  // The audit trail: who created/approved/changed an Account, and when.
  pgm.sql(`SELECT attach_audit('app_users')`);
  pgm.sql(`SELECT attach_audit('app_user_org_units')`);
};

exports.down = (pgm) => {
  // Forward-only in production per ADR-0007 — this exists for local
  // development and for node-pg-migrate's own requirement that a migration
  // define both directions.
  //
  // Trigger names are exactly what attach_audit()/attach_actor_columns()
  // generate (baseline: `p_table || '_audit'`, and `zz_<table>_set_actor`) —
  // see those helpers' own definitions. IF EXISTS guards a second run of this
  // down(), and a down() run against a database where up() never completed.
  pgm.sql('DROP TRIGGER IF EXISTS app_user_org_units_audit ON app_user_org_units');
  pgm.sql('DROP TRIGGER IF EXISTS app_users_audit ON app_users');
  pgm.sql('DROP TRIGGER IF EXISTS zz_app_user_org_units_set_actor ON app_user_org_units');
  pgm.sql('DROP TRIGGER IF EXISTS zz_app_users_set_actor ON app_users');

  pgm.sql('ALTER TABLE app_users ALTER COLUMN is_active SET DEFAULT TRUE');
};
