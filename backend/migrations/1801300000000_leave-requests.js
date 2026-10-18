/**
 * `leave_requests` (issue #265, ADR-0042) — an Employee asks for time off for
 * a run of calendar days, and someone who supervises where they work decides.
 * Modelled on Frappe HRMS's Leave Application: a from/to range, a reason
 * (its Leave Type), a status of Open/Approved/Rejected/Cancelled, a refusal to
 * overlap another live application of the same employee, and a department
 * snapshotted onto the application so the decision is scoped to where the
 * person worked when they asked.
 *
 * **No `leave_types` table: the leave type is an `absence_reasons` row.** The
 * baseline's `absence_reasons` already holds Annual leave, Sickness, Parental
 * leave and the rest, and it is what `attendance_records` names for an absence
 * — so an approved leave request names the very same reason an attendance row
 * will later record for those days, and no second catalogue has to be kept in
 * step with it. What the catalogue lacks is a way to say which of its rows an
 * Employee may *ask* for: Late arrival, Unexcused absence, Training and
 * Lay-off are things that happen to or are arranged for an Employee, not
 * things they request. `is_requestable` says so, `DEFAULT FALSE` so that a
 * reason added later is not offered until someone decides it should be. Unpaid
 * leave is the one reason a request needs that the baseline does not have, so
 * `UNPAID` is seeded with the baseline's own `ON CONFLICT (code) DO NOTHING`
 * idiom (planned, and not absenteeism: like Annual leave it is arranged
 * ahead). Whether a reason is paid is deliberately not modelled (Frappe's
 * `is_lwp`): CONTEXT.md says paid hours is a payroll question this Platform
 * does not answer.
 *
 * **`org_unit_id` is a snapshot, and nullable.** It is the Employee's Org Unit
 * as `directory.js` resolves it (current Assignment, else
 * `default_org_unit_id`) at the moment of submission, kept on the row so the
 * decision stays scoped to where the Employee worked when they asked even if
 * they are later reassigned — the way an Asset's work keeps its Org Unit. It
 * is NULL when the Employee had neither; only an administrator can then
 * decide it (ADR-0042).
 *
 * **Status and its two pairs of facts.** `status` is one of `pending`,
 * `approved`, `rejected`, `cancelled`. `decided_at`/`decided_by_account_id`
 * are set together exactly when the status is approved or rejected, and
 * `cancelled_at`/`cancelled_by_account_id` exactly when it is cancelled
 * (`leave_requests_decided_together`, `leave_requests_cancelled_together`),
 * the same set-or-cleared-as-a-pair discipline `attendance_sheets` uses for
 * its confirmation: no state exists where a decision has a time and no
 * decider, or a pending request already carries one. `decision_note` is the
 * decider's optional reason; `note` is the requester's.
 *
 * **Overlap is refused by the database, not by a read-then-write in the
 * application.** `leave_requests_no_overlap` is an EXCLUDE constraint over the
 * Employee and the inclusive date range, applying only while a request is
 * `pending` or `approved` — Frappe's `validate_leave_overlap`, which refuses
 * overlap with Open or Approved applications. A rejected or cancelled request
 * frees its days, so the Employee may ask again. The constraint is the only
 * version that survives two concurrent submissions. It follows the baseline's
 * own `employee_assignments_no_overlap` spelling exactly (unqualified
 * `WITH =` on a bigint, `btree_gist` already installed by the baseline); the
 * range is `'[]'` because `ends_on` is the last day away, not the day after.
 * `leave_requests_dates_valid` keeps `ends_on` from preceding `starts_on`.
 *
 * **All three of the per-row triggers.** `attach_updated_at` +
 * `attach_actor_columns` + `attach_audit`, as `attendance_sheets` has: a
 * request is inserted once and updated in place when it is decided or
 * cancelled, every write goes through `withActor`, and `attach_audit` is the
 * audit trail of who decided what and when.
 *
 * The two list reads ("mine" and "to decide") filter on the Employee and on
 * the Org Unit respectively and newest first, so each gets an index.
 *
 * The deny-all RLS floor is switched on in this same migration (ADR-0004): the
 * one-time sweep in `1756000000002_deny-all-rls.js` enumerated the catalog as
 * it stood then, so a table created afterwards does not inherit it — see
 * `1801200000000_attendance-sheets.js` for the identical pattern.
 *
 * Backward-compatible per ADR-0007 (expand now, contract later): a new table,
 * one new NOT NULL column with a default on `absence_reasons` and one new
 * row. The previous image's `INSERT`s and `SELECT`s of `absence_reasons` name
 * their columns explicitly and are unaffected; no existing row is changed
 * except the `is_requestable` flag on the seven reasons named below.
 */

exports.shorthands = undefined;

exports.up = (pgm) => {
  pgm.sql('ALTER TABLE absence_reasons ADD COLUMN is_requestable BOOLEAN NOT NULL DEFAULT FALSE');

  pgm.sql(`
    INSERT INTO absence_reasons (code, name, is_planned, counts_as_absenteeism) VALUES
      ('UNPAID', 'Unpaid leave', TRUE, FALSE)
    ON CONFLICT (code) DO NOTHING
  `);

  pgm.sql(`
    UPDATE absence_reasons SET is_requestable = TRUE
     WHERE code IN ('HOL', 'SICK', 'UNPAID', 'PAR', 'FAM', 'MED', 'JURY')
  `);

  pgm.sql(`
    CREATE TABLE leave_requests (
      id                       BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      employee_id              BIGINT      NOT NULL REFERENCES employees (id),
      absence_reason_id        BIGINT      NOT NULL REFERENCES absence_reasons (id),
      org_unit_id              BIGINT      REFERENCES org_units (id),
      starts_on                DATE        NOT NULL,
      ends_on                  DATE        NOT NULL,
      note                     TEXT,
      status                   TEXT        NOT NULL DEFAULT 'pending'
                                           CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled')),
      requested_by_account_id  BIGINT      NOT NULL REFERENCES app_users (id),
      decided_at               TIMESTAMPTZ,
      decided_by_account_id    BIGINT      REFERENCES app_users (id),
      decision_note            TEXT,
      cancelled_at             TIMESTAMPTZ,
      cancelled_by_account_id  BIGINT      REFERENCES app_users (id),
      created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by               BIGINT,
      updated_by               BIGINT,

      CONSTRAINT leave_requests_dates_valid
        CHECK (ends_on >= starts_on),
      -- A decision is a pair, present exactly when the request was approved
      -- or rejected — see this migration's own header.
      CONSTRAINT leave_requests_decided_together
        CHECK ((decided_at IS NOT NULL) = (decided_by_account_id IS NOT NULL)
               AND (decided_at IS NOT NULL) = (status IN ('approved', 'rejected'))),
      CONSTRAINT leave_requests_cancelled_together
        CHECK ((cancelled_at IS NOT NULL) = (cancelled_by_account_id IS NOT NULL)
               AND (cancelled_at IS NOT NULL) = (status = 'cancelled')),
      -- One Employee, one live request for a given day. Rejected and
      -- cancelled requests free their days.
      CONSTRAINT leave_requests_no_overlap
        EXCLUDE USING gist (
          employee_id WITH =,
          daterange(starts_on, ends_on, '[]') WITH &&
        ) WHERE (status IN ('pending', 'approved'))
    )
  `);

  pgm.sql('CREATE INDEX leave_requests_employee_idx ON leave_requests (employee_id, starts_on DESC)');
  pgm.sql('CREATE INDEX leave_requests_requested_by_idx ON leave_requests (requested_by_account_id, created_at DESC)');
  pgm.sql('CREATE INDEX leave_requests_org_unit_idx ON leave_requests (org_unit_id, created_at DESC)');

  pgm.sql(`SELECT attach_updated_at('leave_requests')`);
  pgm.sql(`SELECT attach_actor_columns('leave_requests')`);
  pgm.sql(`SELECT attach_audit('leave_requests')`);

  pgm.sql('ALTER TABLE leave_requests ENABLE ROW LEVEL SECURITY');
};

exports.down = (pgm) => {
  // Forward-only in production per ADR-0007 — this exists for local
  // development and for node-pg-migrate's own requirement that a migration
  // define both directions. Trigger names are exactly what
  // attach_audit()/attach_actor_columns()/attach_updated_at() generate (the
  // baseline: `p_table || '_audit'`, `zz_<table>_set_actor`,
  // `p_table || '_set_updated_at'`).
  pgm.sql('ALTER TABLE leave_requests DISABLE ROW LEVEL SECURITY');
  pgm.sql('DROP TRIGGER IF EXISTS leave_requests_audit ON leave_requests');
  pgm.sql('DROP TRIGGER IF EXISTS zz_leave_requests_set_actor ON leave_requests');
  pgm.sql('DROP TRIGGER IF EXISTS leave_requests_set_updated_at ON leave_requests');
  pgm.sql('DROP TABLE IF EXISTS leave_requests');
  // The UNPAID row is left in place: an attendance row may name it by now.
  pgm.sql('ALTER TABLE absence_reasons DROP COLUMN IF EXISTS is_requestable');
};
