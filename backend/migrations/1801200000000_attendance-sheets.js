/**
 * `attendance_sheets` (issue #249, ADR-0040) — one row per shift instance,
 * confirming who worked it and for how long. The baseline (#226) already
 * carries `attendance_records` — the per-Employee rows — and the four views
 * that read them (`v_attendance_rate`, `v_safety_rates`, `v_labour_cost`),
 * but nothing writes either table today, and nothing records confirmation at
 * all. This migration adds the one table ADR-0040 names: "A new
 * `attendance_sheets` table has one row per shift instance, carrying
 * `confirmed_at` and `confirmed_by_account_id`."
 *
 * **Why confirmation is its own table, never inferred from `attendance_records`
 * rows.** ADR-0040's own words: "'everyone on the roster was absent' and
 * 'nobody has filled this in' must stay different states" — both are a shift
 * with rows recording no presence, and only an explicit confirmation record
 * can tell them apart. `shift_instance_id` is `UNIQUE`, so a shift instance
 * has at most one sheet, and `attendance_sheets_confirmed_together` keeps
 * `confirmed_at`/`confirmed_by_account_id` set or cleared as a pair — a sheet
 * that has been opened but not confirmed carries neither, and there is no
 * state where one is set without the other for a caller to have to guess
 * about.
 *
 * **All three of the baseline's per-row triggers, not just `attach_audit`.**
 * The ticket's own acceptance criterion names only "the deny-all RLS floor
 * and `attach_audit`" for this table, but that is describing what #249's
 * criteria test, not the full set of triggers a brand new table gets — the
 * two most recent tables added after the baseline
 * (`1788279276376_accounts-start-inactive-and-audited.js`'s `app_users`/
 * `app_user_org_units`, `1789300000000_inventory-parts-stores-and-stock.js`'s
 * `parts`/`stores`) both pair `attach_updated_at` + `attach_actor_columns` +
 * `attach_audit` for a table whose rows are edited in place, which
 * `attendance_sheets` is: it is inserted once (when a sheet is first opened)
 * and updated once more (when it is confirmed). Leaving `attach_actor_columns`
 * off would mean `created_by`/`updated_by` stay NULL forever despite every
 * write to this table going through `withActor`, the same gap this ticket is
 * explicitly not trying to reproduce on a new table just because an older one
 * (`attendance_records`, below) still has it.
 *
 * **`attendance_records` gets `attach_audit` only — "nothing else in the
 * schema changes".** The baseline gave `attendance_records`
 * `attach_updated_at` (line ~1415) but never `attach_audit`; this ticket's own
 * acceptance criterion says to attach it now, "if the baseline has not
 * already", and stops there in so many words: "Nothing else in the schema
 * changes." `attach_actor_columns` is deliberately NOT added to
 * `attendance_records` here — that would be a second, uninstructed change to
 * a table this migration is told to touch minimally.
 *
 * **No new `attendance_status` value, no CHECK change, anywhere.** ADR-0040's
 * own "Consequences" section left open how "left early" and a stand-in are
 * expressed against `attendance_records.attendance_status`'s existing six
 * values (`present, late, absent_planned, absent_unplanned, training,
 * not_scheduled`) — settled in `attendance.js`, not here: "left early" is
 * `present` with `worked_minutes` below `scheduled_minutes`, and a stand-in is
 * simply an added `attendance_records` row (the table's own
 * `attendance_records_unique (employee_id, shift_instance_id)` already
 * refuses a second row for the same Employee on the same shift with a clean
 * 409). Neither needs a schema change.
 *
 * The deny-all RLS floor is switched on in this same migration (ADR-0004):
 * the one-time sweep in `1756000000002_deny-all-rls.js` enumerated the
 * catalog as it stood then, so a table created afterwards does not inherit
 * it, and every migration since that has created a table carries its own
 * `ENABLE ROW LEVEL SECURITY` — see `1800900000000_safety-incident-events.js`
 * for the identical pattern this migration follows.
 *
 * Backward-compatible per ADR-0007 (expand now, contract later): a new table
 * and one new trigger on an existing table change nothing an older running
 * image reads or writes, and no existing row anywhere is touched. No data
 * migration: no shift instance has ever had attendance recorded against it
 * before this ticket.
 */

exports.shorthands = undefined;

exports.up = (pgm) => {
  pgm.sql(`
    CREATE TABLE attendance_sheets (
      id                      BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      shift_instance_id       BIGINT      NOT NULL UNIQUE REFERENCES shift_instances (id),
      confirmed_at            TIMESTAMPTZ,
      confirmed_by_account_id BIGINT      REFERENCES app_users (id),
      created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
      created_by              BIGINT,
      updated_by              BIGINT,

      -- Confirmation is a pair, or neither — see this migration's own header
      -- for why a sheet is never left with one set and not the other.
      CONSTRAINT attendance_sheets_confirmed_together
        CHECK ((confirmed_at IS NULL) = (confirmed_by_account_id IS NULL))
    )
  `);

  pgm.sql(`SELECT attach_updated_at('attendance_sheets')`);
  pgm.sql(`SELECT attach_actor_columns('attendance_sheets')`);
  pgm.sql(`SELECT attach_audit('attendance_sheets')`);

  pgm.sql('ALTER TABLE attendance_sheets ENABLE ROW LEVEL SECURITY');

  // `attendance_records` never got this in the baseline (it has
  // `attach_updated_at` only) — the ticket's own instruction, and nothing
  // else about that table changes here.
  pgm.sql(`SELECT attach_audit('attendance_records')`);
};

exports.down = (pgm) => {
  // Forward-only in production per ADR-0007 — this exists for local
  // development and for node-pg-migrate's own requirement that a migration
  // define both directions. Trigger names are exactly what
  // attach_audit()/attach_actor_columns()/attach_updated_at() generate (the
  // baseline: `p_table || '_audit'`, `zz_<table>_set_actor`,
  // `p_table || '_set_updated_at'`).
  pgm.sql('DROP TRIGGER IF EXISTS attendance_records_audit ON attendance_records');

  pgm.sql('ALTER TABLE attendance_sheets DISABLE ROW LEVEL SECURITY');
  pgm.sql('DROP TRIGGER IF EXISTS attendance_sheets_audit ON attendance_sheets');
  pgm.sql('DROP TRIGGER IF EXISTS zz_attendance_sheets_set_actor ON attendance_sheets');
  pgm.sql('DROP TRIGGER IF EXISTS attendance_sheets_set_updated_at ON attendance_sheets');
  pgm.sql('DROP TABLE IF EXISTS attendance_sheets');
};
