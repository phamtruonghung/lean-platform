/*
 * The attendance sheet (issue #249, CONTEXT.md's Attendance section, ADR-0040
 * and ADR-0041). One sheet per shift instance, pre-filled from the roster and
 * corrected by exception, confirmed once. Like plant.js and skills.js, this
 * file stays unaware of who is calling or why — no role check, no Org Unit
 * scope, nothing about HTTP. attendance-routes.js owns every authorization
 * decision: `canAct({ write: true })` for recording, confirming and
 * correcting, `canSeeSite` for reading — issue #249's own acceptance
 * criteria, and ADR-0040's "Recording needs an edit Grant, and nothing more".
 *
 * Also `listAttendanceToConfirm` (issue #250): the worklist of past shift
 * instances whose sheet is missing or unconfirmed, restricted to whichever
 * Org Units the caller can actually act on. Unlike everything else in this
 * file, its scope IS baked into its own arguments
 * (`writeGrantOrgUnitIds`) rather than resolved against a single shift
 * instance the way `canAct`/`canSeeSite` are — see that function's own
 * header for why the shape still keeps policy in attendance-routes.js
 * and stays this file's job only to filter and order.
 *

 * **Opening a sheet pre-fills it, once — and only for a caller who could
 * have recorded on it anyway.** ADR-0040's own words: "everyone on the
 * roster was absent" and "nobody has filled this in" must stay different
 * states, so pre-filling has to be keyed on the `attendance_sheets` row
 * existing, never on whether `attendance_records` has rows yet — removing
 * every row (see removeAttendanceRecord below) must never re-trigger a
 * pre-fill the next time the sheet is opened. `getOrCreateAttendanceSheet`
 * below is the one place this is decided: `INSERT ... ON CONFLICT
 * (shift_instance_id) DO NOTHING RETURNING id` inside one transaction, and
 * the roster is only ever inserted when a row actually comes back from that
 * INSERT — i.e. the sheet did not already exist. The UNIQUE constraint on
 * `attendance_sheets.shift_instance_id` is what makes this race-safe: two
 * concurrent opens of the same sheet can both run this statement, but only
 * one of them gets a returned row and therefore only one of them pre-fills.
 * `getOrCreateAttendanceSheet` is only ever called for a caller
 * `getAttendanceSheet`'s own `canRecord` parameter says may — see that
 * function's own header for why a bare read Grant must never trigger it.
 *
 * **The roster.** Every active Employee whose `default_crew_id` is the shift
 * instance's crew; when the instance has no crew, every active Employee whose
 * `default_org_unit_id` is the instance's Org Unit (ADR-0040's own fallback
 * rule, issue #249's own criterion). Each pre-filled row is `present`, with
 * `scheduled_minutes = worked_minutes = duration_minutes − break_minutes`
 * read off the shift DEFINITION, never `shift_instances.planned_production_minutes`
 * — ADR-0040 says so in so many words: "`planned_production_minutes` is
 * machine time and plays no part here, exactly as it plays no part in
 * `v_shift_oee`'s own reading of the same row." Every pre-filled and every
 * stand-in row's `org_unit_id` is the shift instance's own Org Unit — the
 * unit the hours were worked in, not wherever the Employee is normally
 * assigned — matching the column's NOT NULL baseline definition and
 * `v_labour_cost`/`v_safety_rates`'s own grouping by `shift_instances.org_unit_id`.
 *
 * **Exceptions, against the existing six-value `attendance_status` CHECK.**
 * No new status value and no CHECK change anywhere in this ticket (see the
 * migration's own header for the full reasoning) — the vocabulary ADR-0040
 * left open is settled here instead:
 *   - A late arrival is `attendance_status = 'late'` — already its own value,
 *     distinct from `present`, and what `v_attendance_rate`'s own
 *     `late_headcount` column reads.
 *   - An early finish is `present`, with `worked_minutes` corrected below
 *     `scheduled_minutes` — CONTEXT.md's own Worked hours entry already
 *     describes an early finish this way, as a correction to worked minutes,
 *     not a status.
 *   - Overtime is `overtime_minutes`, and it is a **subset** of
 *     `worked_minutes`, never additional to it — `v_labour_cost` charges
 *     `(worked_minutes - overtime_minutes)` at the base rate and
 *     `overtime_minutes` at the premium rate, so `overtime_minutes` above
 *     `worked_minutes` would make the base-rate portion negative. This file
 *     refuses that combination with a 400 rather than letting the arithmetic
 *     go wrong silently.
 *   - An absence (`absent_planned`/`absent_unplanned`) requires an
 *     `absence_reason_id` (the baseline's own `attendance_records_absence_has_reason`
 *     CHECK) and forces `worked_minutes`/`overtime_minutes` to zero (the
 *     baseline's own `attendance_records_absent_no_hours` CHECK, which also
 *     covers `not_scheduled` — zeroed here for the same reason whenever that
 *     status is set). Every field this file validates before ever reaching
 *     Postgres, so a violation of either CHECK is reported as a 400 naming
 *     the field (issue #249's own criterion), never a raw constraint error;
 *     `mapAttendanceRecordWriteError` below is the last-resort net for
 *     anything this validation missed.
 *   - A stand-in is simply a new `attendance_records` row for an Employee not
 *     already on the sheet (ADR-0040: "adding a stand-in drawn from the
 *     Directory"). `attendance_records_unique (employee_id, shift_instance_id)`
 *     already refuses a second row for the same Employee on the same shift,
 *     which is exactly the 409 issue #249 asks for, and a departed Employee is
 *     refused before the INSERT is even attempted (`isActive` is checked, not
 *     merely that the row exists).
 *   - Removing a row is a hard DELETE — there is no soft-delete convention
 *     anywhere in this schema (deactivation via `is_active` is for catalogue
 *     rows like `skills`/`job_roles`, which `attendance_records` is not), and
 *     `attach_audit` (added to this table by this same ticket's migration)
 *     covers DELETE: its trigger writes the row's `old_values` into
 *     `audit_log` before the row is gone, so a removal is not a silent loss
 *     of history.
 *
 * **Confirming and correcting.** `confirmAttendanceSheet` sets `confirmed_at`
 * and `confirmed_by_account_id` explicitly — no trigger fills either, unlike
 * `created_at`/`updated_at`. A correction after confirming
 * (`updateAttendanceRecord`, `removeAttendanceRecord`, `addStandIn`) never
 * touches `attendance_sheets` at all, so the confirmation stays exactly as it
 * was (ADR-0040: "A confirmed sheet can still be corrected... leaves the
 * confirmation in place"); every write here goes through `withActor`, so each
 * correction is audited under the correcting Account, per that same decision.
 */

const { getPool, withActor } = require('../../platform/db');
const { httpError, notFound, parseId } = require('./errors');
const { getEmployee } = require('./directory');

// Mirrors attendance_records.attendance_status's CHECK exactly (baseline,
// migrations/1756000000000_baseline.js).
const ATTENDANCE_STATUSES = [
  'present', 'late', 'absent_planned', 'absent_unplanned', 'training', 'not_scheduled'
];

// attendance_records_absence_has_reason: only these two require a reason.
const ABSENCE_REASON_REQUIRED_STATUSES = ['absent_planned', 'absent_unplanned'];

// attendance_records_absent_no_hours: these three may never carry hours.
const NO_HOURS_STATUSES = ['absent_planned', 'absent_unplanned', 'not_scheduled'];

function requireInteger(field, value) {
  if (!Number.isInteger(value) || value < 0) {
    throw httpError(400, `${field} must be a non-negative integer`);
  }
}

// ---------------------------------------------------------------------------
// The shift instance a sheet hangs off. Read-only here — shift_instances and
// shift_definitions are both the baseline's own tables, and nothing in this
// ticket writes either.
// ---------------------------------------------------------------------------

function toShiftInstance(row) {
  return {
    id: row.id,
    siteId: row.site_id,
    orgUnitId: row.org_unit_id,
    crewId: row.crew_id,
    shiftDefinitionId: row.shift_definition_id,
    productionDate: row.production_date,
    status: row.status,
    // duration_minutes/break_minutes come from the shift DEFINITION, not
    // shift_instances.planned_production_minutes — see this file's own
    // header for why.
    durationMinutes: row.duration_minutes,
    breakMinutes: row.break_minutes
  };
}

async function findShiftInstance(id) {
  if (parseId(id) === null) return null;
  const { rows } = await getPool().query(
    `SELECT si.id, si.site_id, si.org_unit_id, si.crew_id, si.shift_definition_id,
            si.production_date, si.status,
            sd.duration_minutes, sd.break_minutes
       FROM shift_instances si
       JOIN shift_definitions sd ON sd.id = si.shift_definition_id
      WHERE si.id = $1`,
    [id]
  );
  return rows[0] ? toShiftInstance(rows[0]) : null;
}

async function getShiftInstance(id) {
  const shiftInstance = await findShiftInstance(id);
  if (!shiftInstance) throw notFound('Shift instance');
  return shiftInstance;
}

// A day's shift instances at one Org Unit — what the frontend's Attendance
// picker (there being no shift calendar Screen yet to link from instead)
// lists so a supervisor can find the sheet they mean to open. `hasSheet`/
// `confirmedAt` let it show which shifts still need attention without a
// second round trip per row.
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

function toShiftInstanceSummary(row) {
  return {
    id: row.id,
    orgUnitId: row.org_unit_id,
    crewId: row.crew_id,
    shiftDefinitionCode: row.shift_definition_code,
    shiftDefinitionName: row.shift_definition_name,
    productionDate: row.production_date,
    startsAt: row.starts_at,
    endsAt: row.ends_at,
    status: row.status,
    hasSheet: row.has_sheet,
    confirmedAt: row.confirmed_at
  };
}

async function listShiftInstances(orgUnitId, { date } = {}) {
  if (typeof date !== 'string' || !DATE_RE.test(date)) {
    throw httpError(400, 'date must be a YYYY-MM-DD date');
  }
  const { rows } = await getPool().query(
    `SELECT si.id, si.org_unit_id, si.crew_id,
            sd.code AS shift_definition_code, sd.name AS shift_definition_name,
            si.production_date, si.starts_at, si.ends_at, si.status,
            (sh.id IS NOT NULL) AS has_sheet, sh.confirmed_at
       FROM shift_instances si
       JOIN shift_definitions sd ON sd.id = si.shift_definition_id
       LEFT JOIN attendance_sheets sh ON sh.shift_instance_id = si.id
      WHERE si.org_unit_id = $1 AND si.production_date = $2::date
      ORDER BY si.starts_at`,
    [orgUnitId, date]
  );
  return rows.map(toShiftInstanceSummary);
}

// ---------------------------------------------------------------------------
// The attendance-to-confirm worklist (issue #250) — the past shift instances
// whose sheet is missing or unconfirmed, oldest first. Under #247 decision 9,
// a single unconfirmed shift makes the injury rates `no_data`, so this is
// what keeps that from becoming a permanent blank: it is where the sheet
// that is blocking a rate gets found and opened.
//
// `writeGrantOrgUnitIds` is `null` for an administrator (issue #250's own
// "an administrator sees every Site's list" — no restriction at all, the
// same `everywhere` shape `authorization.orgUnitScopeFor` already answers
// with) or the array of Org Unit ids the caller's own edit Grants reach
// (attendance-routes.js resolves this from that same function, flattening
// only the `canWrite` grants' own `orgUnitIds` — ADR-0040's "recording needs
// an edit Grant" is exactly "could confirm this sheet", so a read-only Grant
// contributes nothing here). An empty array is a legitimate answer — a
// caller with no write Grant anywhere sees an empty list, not a refusal,
// the same self-scoped shape `GET /people/me` already has.
//
// `orgUnitPath` narrows further to one Org Unit and everything beneath it
// (the `?orgUnitId=` filter, resolved by the route), intersected with the
// reach above rather than replacing it.
//
// **The "first confirmed sheet" floor is Site-wide, not per Org Unit —
// deliberately, per issue #250's own amended wording.** #233's rate window
// starts at the first confirmed sheet anywhere in the *chosen subtree*, not
// at each Org Unit's own history, so a line that has never confirmed a
// single sheet still holds its Site's rate at `no_data` for as long as it
// stays unconfirmed — decision 9's window has already opened at that Site,
// via whichever other line confirmed first, and this line's unconfirmed
// shifts are exactly what is keeping the rate blank. A per-Org-Unit floor
// (this function's own earlier shape) would hide precisely those shifts:
// a line with zero confirmations would show zero floor and therefore zero
// worklist entries, which reads as "nothing to confirm here" when the truth
// is "everything here is unconfirmed and it is silently costing the Site's
// rate." Anchoring the floor to the Site instead means: once *any* Org Unit
// in the Site has confirmed a sheet, every other Org Unit's past, ended,
// unconfirmed shifts from that point on are listed too — whatever that
// other Org Unit's own confirmation history — because those are precisely
// the shifts a rate computation is being forced to call `no_data` over.
// `orgUnitPath` still narrows *which* of those entries are shown (the
// `?orgUnitId=` filter); it does not change where the floor itself sits.
//
// **A Site with no confirmed sheet EVER has no floor, and lists nothing for
// it.** `first_confirmed` below is an INNER JOIN, not a LEFT JOIN, on
// purpose: with no confirmed shift anywhere in the Site to anchor on,
// #233's rate window has not opened yet either, so there is no "everything
// after the floor" to show — the same reasoning ADR-0041 gives for not
// reaching back a full calendar year before any confirmation exists. A
// brand new Site's very first sheet is opened and confirmed from the
// `/attendance` picker directly (there is nothing to have missed yet);
// only once that first confirmation exists anywhere in the Site does this
// worklist have a floor to start listing every other unconfirmed shift
// from.
const ATTENDANCE_TO_CONFIRM_LIMIT = 200;

function toAttendanceToConfirmEntry(row) {
  return {
    shiftInstanceId: row.id,
    siteId: row.site_id,
    siteName: row.site_name,
    orgUnitId: row.org_unit_id,
    orgUnitName: row.org_unit_name,
    shiftDefinitionCode: row.shift_definition_code,
    shiftDefinitionName: row.shift_definition_name,
    productionDate: row.production_date,
    startsAt: row.starts_at,
    endsAt: row.ends_at,
    // "missing" — no attendance_sheets row at all; "unconfirmed" — the sheet
    // was opened (and therefore pre-filled) but confirmed_at is still null.
    sheetState: row.has_sheet ? 'unconfirmed' : 'missing'
  };
}

async function listAttendanceToConfirm({
  writeGrantOrgUnitIds = null,
  orgUnitPath = null,
  from = null,
  to = null,
  limit = ATTENDANCE_TO_CONFIRM_LIMIT
} = {}) {
  const conditions = [
    'si.ends_at <= now()', // "has ended" (issue #250's own criterion)
    'si.starts_at >= fc.first_confirmed_starts_at', // the Site-wide floor, see this function's own header
    '(sh.id IS NULL OR sh.confirmed_at IS NULL)' // missing or unconfirmed
  ];
  const params = [];

  if (writeGrantOrgUnitIds !== null) {
    params.push(writeGrantOrgUnitIds);
    conditions.push(`si.org_unit_id = ANY($${params.length}::bigint[])`);
  }
  if (orgUnitPath !== null) {
    params.push(orgUnitPath);
    conditions.push(`ou.path <@ $${params.length}::ltree`);
  }
  if (from !== null) {
    params.push(from);
    conditions.push(`si.production_date >= $${params.length}::date`);
  }
  if (to !== null) {
    params.push(to);
    conditions.push(`si.production_date <= $${params.length}::date`);
  }

  const { rows } = await getPool().query(
    `WITH first_confirmed AS (
       SELECT si2.site_id, MIN(si2.starts_at) AS first_confirmed_starts_at
         FROM shift_instances si2
         JOIN attendance_sheets sh2 ON sh2.shift_instance_id = si2.id
        WHERE sh2.confirmed_at IS NOT NULL
        GROUP BY si2.site_id
     )
     SELECT si.id, si.site_id, s.name AS site_name, si.org_unit_id, ou.name AS org_unit_name,
            sd.code AS shift_definition_code, sd.name AS shift_definition_name,
            si.production_date, si.starts_at, si.ends_at,
            (sh.id IS NOT NULL) AS has_sheet
       FROM shift_instances si
       JOIN shift_definitions sd ON sd.id = si.shift_definition_id
       JOIN org_units ou ON ou.id = si.org_unit_id
       JOIN sites s ON s.id = si.site_id
       JOIN first_confirmed fc ON fc.site_id = si.site_id
       LEFT JOIN attendance_sheets sh ON sh.shift_instance_id = si.id
      WHERE ${conditions.join(' AND ')}
      ORDER BY si.starts_at ASC, si.id ASC
      LIMIT ${limit + 1}`,
    params
  );

  const truncated = rows.length > limit;
  return {
    entries: rows.slice(0, limit).map(toAttendanceToConfirmEntry),
    truncated
  };
}

// ---------------------------------------------------------------------------
// absence_reasons — shared reference data, mirrors skills.js's own
// listSkills/getSkill exactly: open read, no Org Unit scope, no site_id
// column on the table at all.
// ---------------------------------------------------------------------------

function toAbsenceReason(row) {
  return {
    id: row.id,
    code: row.code,
    name: row.name,
    isPlanned: row.is_planned,
    countsAsAbsenteeism: row.counts_as_absenteeism,
    isActive: row.is_active
  };
}

async function listAbsenceReasons({ includeInactive } = {}) {
  const whereClause = includeInactive ? '' : 'WHERE is_active = TRUE';
  const { rows } = await getPool().query(
    `SELECT id, code, name, is_planned, counts_as_absenteeism, is_active
       FROM absence_reasons ${whereClause} ORDER BY name`
  );
  return rows.map(toAbsenceReason);
}

async function getAbsenceReason(id) {
  if (id === null) throw notFound('Absence reason');
  const { rows } = await getPool().query(
    `SELECT id, code, name, is_planned, counts_as_absenteeism, is_active
       FROM absence_reasons WHERE id = $1`,
    [id]
  );
  if (!rows[0]) throw notFound('Absence reason');
  return toAbsenceReason(rows[0]);
}

// ---------------------------------------------------------------------------
// attendance_sheets / attendance_records
// ---------------------------------------------------------------------------

function toAttendanceSheet(row) {
  return {
    id: row.id,
    shiftInstanceId: row.shift_instance_id,
    confirmedAt: row.confirmed_at,
    confirmedByAccountId: row.confirmed_by_account_id
  };
}

function toAttendanceRecord(row) {
  return {
    id: row.id,
    employeeId: row.employee_id,
    employeeNo: row.employee_no,
    displayName: row.display_name,
    attendanceStatus: row.attendance_status,
    absenceReasonId: row.absence_reason_id,
    absenceReason: row.absence_reason_id
      ? { id: row.absence_reason_id, code: row.absence_reason_code, name: row.absence_reason_name }
      : null,
    scheduledMinutes: row.scheduled_minutes,
    workedMinutes: row.worked_minutes,
    overtimeMinutes: row.overtime_minutes,
    note: row.note
  };
}

// A write against attendance_records can fail for two reasons this file
// turns into a clean 4xx rather than a 500: the same-Employee-twice UNIQUE
// (issue #249's own criterion: "409, which attendance_records_unique already
// enforces") and, as a last resort net, either of the baseline's two CHECKs
// this file otherwise validates ahead of every write. Anything else is
// rethrown as-is.
function mapAttendanceRecordWriteError(error) {
  if (error.code === '23505' && error.constraint === 'attendance_records_unique') {
    return httpError(409, 'this Employee is already on the sheet');
  }
  if (error.code === '23514' && error.constraint === 'attendance_records_absence_has_reason') {
    return httpError(400, 'absenceReasonId is required when attendanceStatus is absent_planned or absent_unplanned');
  }
  if (error.code === '23514' && error.constraint === 'attendance_records_absent_no_hours') {
    return httpError(400, 'workedMinutes and overtimeMinutes must be 0 for this attendanceStatus');
  }
  return error;
}

async function fetchAttendanceRecords(client, shiftInstanceId) {
  const { rows } = await client.query(
    `SELECT ar.id, ar.employee_id, e.employee_no, e.display_name,
            ar.attendance_status, ar.absence_reason_id,
            ab.code AS absence_reason_code, ab.name AS absence_reason_name,
            ar.scheduled_minutes, ar.worked_minutes, ar.overtime_minutes, ar.note
       FROM attendance_records ar
       JOIN employees e ON e.id = ar.employee_id
       LEFT JOIN absence_reasons ab ON ab.id = ar.absence_reason_id
      WHERE ar.shift_instance_id = $1
      ORDER BY e.display_name, e.id`,
    [shiftInstanceId]
  );
  return rows.map(toAttendanceRecord);
}

// The roster pre-fill (ADR-0040) — one INSERT per fallback branch, both
// guarded by ON CONFLICT DO NOTHING so this is safe to call even if it were
// ever invoked twice (it is not, in practice — getOrCreateAttendanceSheet
// below only calls this the one time the sheet row is first created).
async function prefillAttendanceRecords(client, shiftInstance) {
  const minutes = shiftInstance.durationMinutes - shiftInstance.breakMinutes;

  if (shiftInstance.crewId !== null && shiftInstance.crewId !== undefined) {
    await client.query(
      `INSERT INTO attendance_records
         (employee_id, shift_instance_id, org_unit_id, attendance_status,
          scheduled_minutes, worked_minutes, overtime_minutes)
       SELECT e.id, $1, $2, 'present', $3, $3, 0
         FROM employees e
        WHERE e.is_active = TRUE AND e.default_crew_id = $4
       ON CONFLICT (employee_id, shift_instance_id) DO NOTHING`,
      [shiftInstance.id, shiftInstance.orgUnitId, minutes, shiftInstance.crewId]
    );
    return;
  }

  await client.query(
    `INSERT INTO attendance_records
       (employee_id, shift_instance_id, org_unit_id, attendance_status,
        scheduled_minutes, worked_minutes, overtime_minutes)
     SELECT e.id, $1, $2, 'present', $3, $3, 0
       FROM employees e
      WHERE e.is_active = TRUE AND e.default_org_unit_id = $2
     ON CONFLICT (employee_id, shift_instance_id) DO NOTHING`,
    [shiftInstance.id, shiftInstance.orgUnitId, minutes]
  );
}

// Get-or-create the sheet row, pre-filling exactly once — see this file's
// own header for the full race-safety reasoning. Always runs inside the
// caller's own transaction (every caller below wraps this in withActor), so
// the INSERT-or-fetch and any pre-fill are one atomic unit.
async function getOrCreateAttendanceSheet(client, shiftInstance) {
  const { rows: [created] } = await client.query(
    `INSERT INTO attendance_sheets (shift_instance_id)
     VALUES ($1)
     ON CONFLICT (shift_instance_id) DO NOTHING
     RETURNING id, shift_instance_id, confirmed_at, confirmed_by_account_id`,
    [shiftInstance.id]
  );

  if (created) {
    await prefillAttendanceRecords(client, shiftInstance);
    return created;
  }

  const { rows: [existing] } = await client.query(
    `SELECT id, shift_instance_id, confirmed_at, confirmed_by_account_id
       FROM attendance_sheets WHERE shift_instance_id = $1`,
    [shiftInstance.id]
  );
  return existing;
}

// Opening the sheet (issue #249's own criterion): pre-fills it the first
// time it is opened by a caller who MAY record — `canRecord`, resolved by
// attendance-routes.js as `canAct({ write: true })` at the shift instance's
// own Org Unit, never by this file. Opening an unstarted sheet is itself the
// write ADR-0040 gates on an edit Grant ("Recording needs an edit Grant, and
// nothing more") — a bare GET from a caller holding only a read Grant, or
// none, must never create the `attendance_sheets` row or pre-fill
// `attendance_records`, or it would (a) let a reader author rows nobody with
// authority asked for, (b) make that reader the audited actor for a write
// they never made, and (c) put the sheet into the "exists but unconfirmed"
// state #250's worklist reads, started by nobody who could have.
//
// So: a caller who cannot record, asking about a shift instance with no
// sheet yet, gets `{ started: false, sheet: null, records: [] }` and this
// function issues no write of any kind — not even the `ON CONFLICT DO
// NOTHING` INSERT `getOrCreateAttendanceSheet` uses elsewhere, since an
// INSERT with nothing to conflict against would still insert. A caller who
// CAN record gets the sheet created and pre-filled exactly as before
// (`getOrCreateAttendanceSheet`'s own race-safety reasoning, unchanged).
// Once a sheet DOES exist — started by someone who could — any caller who
// can see the Site reads it back in full, `started: true`, regardless of
// their own write scope: reading an already-started sheet is not
// "recording", and issue #249's own criterion is explicit that reading needs
// only visibility of the Site.
async function getAttendanceSheet(shiftInstanceId, accountId, canRecord) {
  const shiftInstance = await getShiftInstance(shiftInstanceId); // 404s if it does not exist.

  return withActor(accountId, async (client) => {
    if (!canRecord) {
      const { rows: [existing] } = await client.query(
        `SELECT id, shift_instance_id, confirmed_at, confirmed_by_account_id
           FROM attendance_sheets WHERE shift_instance_id = $1`,
        [shiftInstance.id]
      );
      if (!existing) {
        return { started: false, sheet: null, records: [] };
      }
      const records = await fetchAttendanceRecords(client, shiftInstance.id);
      return { started: true, sheet: toAttendanceSheet(existing), records };
    }

    const sheetRow = await getOrCreateAttendanceSheet(client, shiftInstance);
    const records = await fetchAttendanceRecords(client, shiftInstance.id);
    return { started: true, sheet: toAttendanceSheet(sheetRow), records };
  });
}

async function getAttendanceRecordRow(client, shiftInstanceId, recordId) {
  const id = parseId(recordId);
  if (id === null) throw notFound('Attendance record');
  const { rows } = await client.query(
    `SELECT id, employee_id, attendance_status, absence_reason_id,
            scheduled_minutes, worked_minutes, overtime_minutes, note
       FROM attendance_records WHERE id = $1 AND shift_instance_id = $2`,
    [id, shiftInstanceId]
  );
  if (!rows[0]) throw notFound('Attendance record');
  const row = rows[0];
  return {
    id: row.id,
    employeeId: row.employee_id,
    attendanceStatus: row.attendance_status,
    absenceReasonId: row.absence_reason_id,
    scheduledMinutes: row.scheduled_minutes,
    workedMinutes: row.worked_minutes,
    overtimeMinutes: row.overtime_minutes,
    note: row.note
  };
}

// Marking an exception, changing minutes, recording overtime, or correcting
// any of it after confirmation (issue #249's own criteria) — one PATCH, every
// field independently settable via the hasOwnProperty idiom skills.js's own
// updateSkill already follows, so a one-field correction never blanks the
// rest.
async function updateAttendanceRecord(shiftInstanceId, recordId, input, accountId) {
  const shiftInstance = await getShiftInstance(shiftInstanceId); // 404s if it does not exist.
  const body = input ?? {};

  return withActor(accountId, async (client) => {
    const existing = await getAttendanceRecordRow(client, shiftInstance.id, recordId); // 404s if it does not exist.

    const hasStatus = Object.prototype.hasOwnProperty.call(body, 'attendanceStatus');
    const hasReason = Object.prototype.hasOwnProperty.call(body, 'absenceReasonId');
    const hasWorked = Object.prototype.hasOwnProperty.call(body, 'workedMinutes');
    const hasOvertime = Object.prototype.hasOwnProperty.call(body, 'overtimeMinutes');
    const hasNote = Object.prototype.hasOwnProperty.call(body, 'note');

    let status = existing.attendanceStatus;
    if (hasStatus) {
      if (!ATTENDANCE_STATUSES.includes(body.attendanceStatus)) {
        throw httpError(400, `attendanceStatus must be one of: ${ATTENDANCE_STATUSES.join(', ')}`);
      }
      status = body.attendanceStatus;
    }

    let workedMinutes = hasWorked ? body.workedMinutes : existing.workedMinutes;
    let overtimeMinutes = hasOvertime ? body.overtimeMinutes : existing.overtimeMinutes;
    let absenceReasonId = hasReason ? parseId(body.absenceReasonId) : existing.absenceReasonId;
    if (hasReason && body.absenceReasonId !== null && absenceReasonId === null) {
      throw httpError(400, 'absenceReasonId must be a valid absence reason id');
    }

    if (NO_HOURS_STATUSES.includes(status)) {
      // attendance_records_absent_no_hours: absent_planned, absent_unplanned
      // and not_scheduled may never carry hours — refused as a 400 naming
      // the field rather than left to hit the CHECK.
      if (hasWorked && Number(body.workedMinutes) !== 0) {
        throw httpError(400, `workedMinutes must be 0 when attendanceStatus is ${status}`);
      }
      if (hasOvertime && Number(body.overtimeMinutes) !== 0) {
        throw httpError(400, `overtimeMinutes must be 0 when attendanceStatus is ${status}`);
      }
      workedMinutes = 0;
      overtimeMinutes = 0;
    } else {
      requireInteger('workedMinutes', workedMinutes);
      requireInteger('overtimeMinutes', overtimeMinutes);
      // v_labour_cost charges (worked_minutes - overtime_minutes) at the base
      // rate and overtime_minutes at the premium rate — overtime above
      // worked minutes would make the base-rate portion negative. See this
      // file's own header.
      if (overtimeMinutes > workedMinutes) {
        throw httpError(400, 'overtimeMinutes must not exceed workedMinutes');
      }
    }

    if (ABSENCE_REASON_REQUIRED_STATUSES.includes(status)) {
      // attendance_records_absence_has_reason: an absence needs a reason.
      if (absenceReasonId === null || absenceReasonId === undefined) {
        throw httpError(400, 'absenceReasonId is required when attendanceStatus is absent_planned or absent_unplanned');
      }
      await getAbsenceReason(absenceReasonId); // 404s if it does not exist.
    } else {
      // A reason belongs to an absence — never left lingering on a row that
      // no longer names one.
      absenceReasonId = null;
    }

    const note = hasNote ? (body.note ?? null) : existing.note;

    try {
      const { rows: [row] } = await client.query(
        `UPDATE attendance_records
            SET attendance_status = $1, absence_reason_id = $2,
                worked_minutes = $3, overtime_minutes = $4, note = $5
          WHERE id = $6
          RETURNING id`,
        [status, absenceReasonId, workedMinutes, overtimeMinutes, note, existing.id]
      );
      return fetchOneAttendanceRecord(client, row.id);
    } catch (error) {
      throw mapAttendanceRecordWriteError(error);
    }
  });
}

async function fetchOneAttendanceRecord(client, id) {
  const { rows } = await client.query(
    `SELECT ar.id, ar.employee_id, e.employee_no, e.display_name,
            ar.attendance_status, ar.absence_reason_id,
            ab.code AS absence_reason_code, ab.name AS absence_reason_name,
            ar.scheduled_minutes, ar.worked_minutes, ar.overtime_minutes, ar.note
       FROM attendance_records ar
       JOIN employees e ON e.id = ar.employee_id
       LEFT JOIN absence_reasons ab ON ab.id = ar.absence_reason_id
      WHERE ar.id = $1`,
    [id]
  );
  return toAttendanceRecord(rows[0]);
}

// Adding a stand-in (ADR-0040, issue #249's own criterion): any active
// Employee from the Directory, not already on the sheet. Ensures the sheet
// exists (and pre-fills it) first, so a stand-in can be added even by a
// caller who never separately opened the sheet.
async function addStandIn(shiftInstanceId, input, accountId) {
  const shiftInstance = await getShiftInstance(shiftInstanceId); // 404s if it does not exist.

  const employeeId = parseId(input?.employeeId);
  if (employeeId === null) {
    throw httpError(400, 'employeeId must be a valid Employee id');
  }
  const employee = await getEmployee(employeeId); // 404s if it does not exist.
  if (!employee.isActive) {
    // "A departed Employee cannot be added" — issue #249's own criterion.
    throw httpError(400, 'employeeId must name an active Employee');
  }

  const minutes = shiftInstance.durationMinutes - shiftInstance.breakMinutes;

  return withActor(accountId, async (client) => {
    await getOrCreateAttendanceSheet(client, shiftInstance);

    try {
      const { rows: [row] } = await client.query(
        `INSERT INTO attendance_records
           (employee_id, shift_instance_id, org_unit_id, attendance_status,
            scheduled_minutes, worked_minutes, overtime_minutes)
         VALUES ($1, $2, $3, 'present', $4, $4, 0)
         RETURNING id`,
        [employee.id, shiftInstance.id, shiftInstance.orgUnitId, minutes]
      );
      return fetchOneAttendanceRecord(client, row.id);
    } catch (error) {
      throw mapAttendanceRecordWriteError(error);
    }
  });
}

// Removing a row (ADR-0040, issue #249's own criterion) — a hard DELETE, see
// this file's own header for why. Scoped to this shift instance so a record
// id from a different sheet 404s rather than deleting across sheets.
async function removeAttendanceRecord(shiftInstanceId, recordId, accountId) {
  const shiftInstance = await getShiftInstance(shiftInstanceId); // 404s if it does not exist.
  const id = parseId(recordId);
  if (id === null) throw notFound('Attendance record');

  return withActor(accountId, async (client) => {
    const { rowCount } = await client.query(
      'DELETE FROM attendance_records WHERE id = $1 AND shift_instance_id = $2',
      [id, shiftInstance.id]
    );
    if (rowCount === 0) throw notFound('Attendance record');
  });
}

// Confirming (ADR-0040, issue #249's own criterion): sets confirmed_at and
// the confirming Account explicitly — no trigger fills either. Ensures the
// sheet exists first, so a caller who never opened the sheet can still
// confirm it directly (pre-filling it as part of the same call).
async function confirmAttendanceSheet(shiftInstanceId, accountId) {
  const shiftInstance = await getShiftInstance(shiftInstanceId); // 404s if it does not exist.

  return withActor(accountId, async (client) => {
    await getOrCreateAttendanceSheet(client, shiftInstance);

    const { rows: [row] } = await client.query(
      `UPDATE attendance_sheets
          SET confirmed_at = now(), confirmed_by_account_id = $1
        WHERE shift_instance_id = $2
        RETURNING id, shift_instance_id, confirmed_at, confirmed_by_account_id`,
      [accountId, shiftInstance.id]
    );
    return toAttendanceSheet(row);
  });
}

module.exports = {
  findShiftInstance,
  getShiftInstance,
  listShiftInstances,
  listAttendanceToConfirm,
  listAbsenceReasons,
  getAttendanceSheet,
  updateAttendanceRecord,
  addStandIn,
  removeAttendanceRecord,
  confirmAttendanceSheet,
  ATTENDANCE_STATUSES
};
