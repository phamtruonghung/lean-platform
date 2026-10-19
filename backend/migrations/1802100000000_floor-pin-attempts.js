/**
 * Failed floor PIN attempts (ADR-0047, ADR-0016): the counter behind the
 * lockout on `POST /floor/identify`. One row per (floor device, Employee
 * number) counts consecutive failures and carries the moment the lock lifts;
 * one extra row per device, with the empty Employee number, counts failures
 * across every Employee on that device inside a window.
 *
 * `employee_no` is the text the caller typed, not a foreign key: a guess at a
 * number that matches nobody is counted and locked exactly like one that
 * does, so the lock never tells a caller whether an Employee exists. The
 * route bounds its length before it gets here.
 *
 * Not audited, on purpose: every failed guess would write an audit row, and
 * this table is operational state, not a record anyone reasons about.
 * Deny-all RLS is on, as for every table (ADR-0004).
 *
 * Backward-compatible per ADR-0007: a new table changes nothing an older
 * running image reads or writes.
 */

exports.shorthands = undefined;

exports.up = (pgm) => {
  pgm.sql(`
    CREATE TABLE floor_pin_attempts (
      floor_device_id   BIGINT       NOT NULL REFERENCES floor_devices (id) ON DELETE CASCADE,
      employee_no       TEXT         NOT NULL,
      failures          INTEGER      NOT NULL DEFAULT 0,
      window_started_at TIMESTAMPTZ  NOT NULL DEFAULT now(),
      locked_until      TIMESTAMPTZ,
      updated_at        TIMESTAMPTZ  NOT NULL DEFAULT now(),

      PRIMARY KEY (floor_device_id, employee_no)
    )
  `);
  pgm.sql('CREATE INDEX floor_pin_attempts_employee_no_idx ON floor_pin_attempts (employee_no)');
  pgm.sql('ALTER TABLE floor_pin_attempts ENABLE ROW LEVEL SECURITY');
};

exports.down = (pgm) => {
  // Forward-only in production per ADR-0007 — this exists for local
  // development and for node-pg-migrate's requirement that a migration
  // define both directions.
  pgm.sql('ALTER TABLE floor_pin_attempts DISABLE ROW LEVEL SECURITY');
  pgm.sql('DROP TABLE IF EXISTS floor_pin_attempts');
};
