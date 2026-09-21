/**
 * A Safety observation records who wrote it down, exactly the same fact
 * migration 1800800000000 added to `safety_incidents` for the same reason
 * (issue #230, which mirrors #226's own recording story for the leading
 * indicator rather than the lagging one).
 *
 * One thing, and nothing else: **who recorded it as an Account**,
 * `safety_observations.recorded_by_account_id`. The baseline's own
 * `observer_employee_id` is an Employee, the right shape for the shared floor
 * device (ADR-0016) where an identified Employee is who made the observation
 * — but an Account recording an observation from a safety walk need not be an
 * Employee at all, the same reasoning `quality_issues.recorded_by_account_id`
 * and `safety_incidents.recorded_by_account_id` both already carry. The two
 * doors this Module gives an observation are exactly the two `safety-incidents.js`
 * already has: the Account door writes `recorded_by_account_id` and leaves
 * `observer_employee_id` null; the floor door writes `observer_employee_id`
 * (the identified Employee IS the recorder there — ADR-0016, most of a plant
 * holds no Account) and leaves `recorded_by_account_id` null. Application code
 * is what keeps exactly one of the two set on every row; unlike
 * `safety_incidents`, the baseline never gave `safety_observations` an
 * `is_anonymous` column to constrain, so there is no CHECK to add here — #230's
 * own instruction is that this migration adds only the recording Account
 * column, and nothing else about the baseline's table changes: not the type,
 * category and severity-potential CHECK sets, not the stop-work flag, not the
 * `observer_employee_id` column, no status of any kind.
 *
 * Backward-compatible per ADR-0007 (expand now, contract later): a nullable
 * column changes nothing an older running image reads or writes. No data
 * migration, because there is nothing to backfill — every existing row (there
 * are none outside tests) already has `recorded_by_account_id` implicitly
 * null, the same state the column's own absence left it in.
 */

exports.shorthands = undefined;

exports.up = (pgm) => {
  pgm.sql(`
    ALTER TABLE safety_observations
      ADD COLUMN recorded_by_account_id BIGINT REFERENCES app_users (id)
  `);
};

exports.down = (pgm) => {
  // Forward-only in production per ADR-0007 — this exists for local
  // development and for node-pg-migrate's own requirement that a migration
  // define both directions.
  pgm.sql('ALTER TABLE safety_observations DROP COLUMN recorded_by_account_id');
};
