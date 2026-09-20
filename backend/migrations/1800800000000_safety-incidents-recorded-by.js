/**
 * A Safety incident records who wrote it down, and can never be anonymous
 * (issue #226, ADR-0036 — "A safety report names its reporter").
 *
 * Two things, and nothing else.
 *
 * First, **who recorded it as an Account**: `safety_incidents.recorded_by_account_id`.
 * The baseline's `reported_by` is an Employee, the right shape for the shared
 * floor device (ADR-0016, issue #227) where an identified Employee is who did
 * the reporting — but an administrator recording an incident on someone
 * else's behalf need not be an Employee at all, and a signed-in Account
 * reporting its own incident is a different fact than the Employee column
 * carries. `quality_issues.recorded_by_account_id` (migration 1799900000000)
 * is the exact precedent: nullable, because a row that ever arrives by another
 * path has no Account behind it, and named separately from `created_by`
 * because `created_by` is the audit trigger's own column, filled from
 * `app.user_id`, and not part of the record a client reads back — "who
 * recorded this" is a field of the incident itself.
 *
 * Second, **a CHECK forcing `is_anonymous` false**. ADR-0036 decided against
 * anonymous reporting — every incident names its reporter, an Account or an
 * Employee identified at the floor device, never neither — and the baseline's
 * own `is_anonymous` column cannot be dropped under ADR-0007's expand-now,
 * contract-later rule: a column an older running image might still read or
 * write is never removed by a forward-only migration, only added around. So
 * the column stays, unused, and an unused boolean spelled `is_anonymous`
 * sitting in the schema is exactly the kind of invitation ADR-0036's own text
 * warns a later reader against taking up. The CHECK is what turns "the
 * decision is documented" into "the decision cannot be quietly reversed by
 * one write": reintroducing anonymous reporting means dropping a named
 * constraint and writing an ADR that answers ADR-0036, not flipping a flag
 * that was merely left waiting for the purpose.
 *
 * `safety_incidents` is otherwise used exactly as the baseline defines it —
 * the severity ladder, the four CHECK constraints, the GENERATED
 * `is_recordable` and the `attach_shift_instance` trigger are all untouched;
 * this migration adds nothing to any of them.
 *
 * Backward-compatible per ADR-0007 (expand now, contract later): a nullable
 * column changes nothing an older image reads or writes, and the CHECK is
 * satisfiable by every row an older image can still produce, since
 * `is_anonymous` already defaults FALSE in the baseline and no code path in
 * this repository has ever set it TRUE. No data migration, because there is
 * nothing to backfill: every existing row (there are none outside tests) is
 * already `is_anonymous = FALSE` by the column's own default.
 */

exports.shorthands = undefined;

exports.up = (pgm) => {
  pgm.sql(`
    ALTER TABLE safety_incidents
      ADD COLUMN recorded_by_account_id BIGINT REFERENCES app_users (id)
  `);

  pgm.sql(`
    ALTER TABLE safety_incidents
      ADD CONSTRAINT safety_incidents_not_anonymous CHECK (NOT is_anonymous)
  `);
};

exports.down = (pgm) => {
  // Forward-only in production per ADR-0007 — this exists for local
  // development and for node-pg-migrate's own requirement that a migration
  // define both directions.
  pgm.sql('ALTER TABLE safety_incidents DROP CONSTRAINT safety_incidents_not_anonymous');
  pgm.sql('ALTER TABLE safety_incidents DROP COLUMN recorded_by_account_id');
};
