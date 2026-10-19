/*
 * Leave requests (issue #265, ADR-0042, CONTEXT.md's Attendance section): an
 * Employee asks for a run of calendar days off, naming an absence reason, and
 * someone who supervises where they work approves or rejects it. Like
 * attendance.js, this file stays unaware of who is calling or why — no role
 * check, no Org Unit scope, nothing about HTTP. leave-requests-routes.js owns
 * every authorization decision and hands this file the ids it has already
 * checked.
 *
 * **The leave type is an absence reason.** There is no leave-types table:
 * `absence_reasons` is what `attendance_records` names for an absence, so an
 * approved request names the same reason an attendance row later would, and
 * `absence_reasons.is_requestable` (migration 1801300000000) says which of
 * its rows an Employee may ask for. A reason that is inactive or not
 * requestable is refused with a 400 naming the field.
 *
 * **DATE columns travel as text.** `starts_on`/`ends_on` are selected with
 * `::text`, exactly as `summariseEmployeeWorkedHours` does for
 * `production_date`: node-postgres would otherwise build a JS Date at local
 * midnight and a process in another timezone would serialise the previous
 * day. Ids are BIGINT and come back as strings (db.js leaves them unparsed),
 * so every id in the JSON is a string, as everywhere else in this Module.
 *
 * **`days` is inclusive calendar days** (`ends_on - starts_on + 1`). The
 * Platform has no holiday calendar and no working-week definition, so a
 * weekend inside the range counts; a follow-up that adds either would change
 * this one expression, not the schema.
 *
 * **Snapshot of the Org Unit.** `resolveEmployeeOrgUnitId` answers where the
 * Employee works *now* (current Assignment, else `default_org_unit_id`, the
 * same COALESCE directory.js reads) and the request keeps that answer: the
 * decision is scoped to where the person worked when they asked.
 *
 * Every write goes through `withActor`, so `created_by`/`updated_by` and the
 * `attach_audit` trail carry the acting Account — the audit trail of who
 * decided what, and when, is the table's own.
 */

const { getPool, withActor } = require('../../platform/db');
const { httpError, parseId } = require('./errors');

const STATUSES = ['pending', 'approved', 'rejected', 'cancelled'];
const VIEWS = ['mine', 'to-decide'];
const LIST_LIMIT = 200;
const NOTE_MAX_LENGTH = 2000;

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

// A YYYY-MM-DD string that is also a real calendar date: the regex alone
// would let 2026-02-31 through to Postgres as a raw 22008.
function requireDate(field, value) {
  if (typeof value !== 'string' || !DATE_RE.test(value)) {
    throw httpError(400, `${field} must be a date in YYYY-MM-DD form`);
  }
  const parsed = new Date(`${value}T00:00:00Z`);
  if (Number.isNaN(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== value) {
    throw httpError(400, `${field} must be a real calendar date`);
  }
  return value;
}

// Optional free text: absent, null or blank all mean "no note".
function optionalNote(field, value) {
  if (value === undefined || value === null) return null;
  if (typeof value !== 'string') throw httpError(400, `${field} must be a string`);
  const trimmed = value.trim();
  if (trimmed === '') return null;
  if (trimmed.length > NOTE_MAX_LENGTH) {
    throw httpError(400, `${field} must be at most ${NOTE_MAX_LENGTH} characters`);
  }
  return trimmed;
}

function requireStatus(value) {
  if (value === undefined) return null;
  if (!STATUSES.includes(value)) {
    throw httpError(400, `status must be one of ${STATUSES.join(', ')}`);
  }
  return value;
}

function requireView(value) {
  if (value === undefined) return 'mine';
  if (!VIEWS.includes(value)) {
    throw httpError(400, `view must be one of ${VIEWS.join(', ')}`);
  }
  return value;
}

// 23P01 (exclusion_violation), leave_requests_no_overlap: another pending or
// approved request of the same Employee covers one of these days. 23514 and
// 23503 are the last-resort net for anything the validation above missed; a
// raw database message is never echoed — it names tables and columns.
function mapLeaveRequestWriteError(error) {
  if (error.code === '23P01' && error.constraint === 'leave_requests_no_overlap') {
    return httpError(409, 'this overlaps another pending or approved leave request for this Employee');
  }
  if (error.code === '23514') {
    return httpError(400, 'the leave request breaks a rule on its dates or status');
  }
  if (error.code === '23503') {
    return httpError(400, 'the leave request names an Employee, absence reason or Account that does not exist');
  }
  return error;
}

// ---------------------------------------------------------------------------
// Reading
// ---------------------------------------------------------------------------

const LEAVE_REQUEST_SELECT = `
  SELECT lr.id, lr.employee_id, e.employee_no, e.display_name AS employee_display_name,
         lr.absence_reason_id, ar.code AS absence_reason_code, ar.name AS absence_reason_name,
         lr.org_unit_id, ou.name AS org_unit_name,
         lr.starts_on::text AS starts_on, lr.ends_on::text AS ends_on,
         (lr.ends_on - lr.starts_on + 1) AS days,
         lr.note, lr.status,
         lr.requested_by_account_id, requester.display_name AS requested_by_name,
         lr.created_at,
         lr.decided_by_account_id, decider.display_name AS decided_by_name,
         lr.decided_at, lr.decision_note,
         lr.cancelled_by_account_id, canceller.display_name AS cancelled_by_name,
         lr.cancelled_at
    FROM leave_requests lr
    JOIN employees e ON e.id = lr.employee_id
    JOIN absence_reasons ar ON ar.id = lr.absence_reason_id
    LEFT JOIN org_units ou ON ou.id = lr.org_unit_id
    JOIN app_users requester ON requester.id = lr.requested_by_account_id
    LEFT JOIN app_users decider ON decider.id = lr.decided_by_account_id
    LEFT JOIN app_users canceller ON canceller.id = lr.cancelled_by_account_id`;

// `canDecide`/`canCancel` are filled in by the route, which knows the caller;
// this file only maps the row. Both default to false here so a row mapped
// without a caller can never read as actionable.
function toLeaveRequest(row) {
  return {
    id: row.id,
    employee: { id: row.employee_id, employeeNo: row.employee_no, displayName: row.employee_display_name },
    absenceReason: { id: row.absence_reason_id, code: row.absence_reason_code, name: row.absence_reason_name },
    orgUnit: row.org_unit_id ? { id: row.org_unit_id, name: row.org_unit_name } : null,
    startsOn: row.starts_on,
    endsOn: row.ends_on,
    days: row.days,
    note: row.note,
    status: row.status,
    requestedBy: { id: row.requested_by_account_id, displayName: row.requested_by_name },
    requestedAt: row.created_at,
    decidedBy: row.decided_by_account_id
      ? { id: row.decided_by_account_id, displayName: row.decided_by_name }
      : null,
    decidedAt: row.decided_at,
    decisionNote: row.decision_note,
    cancelledBy: row.cancelled_by_account_id
      ? { id: row.cancelled_by_account_id, displayName: row.cancelled_by_name }
      : null,
    cancelledAt: row.cancelled_at,
    canDecide: false,
    canCancel: false
  };
}

// The null-returning form: a malformed id answers null rather than handing
// Postgres a non-numeric BIGINT, so the route's 404 stays a 404.
async function findLeaveRequest(id, client = getPool()) {
  if (parseId(id) === null) return null;
  const { rows } = await client.query(`${LEAVE_REQUEST_SELECT} WHERE lr.id = $1`, [id]);
  return rows[0] ? toLeaveRequest(rows[0]) : null;
}

// `view` 'mine': requests for the caller's own linked Employee, or that the
// caller submitted on someone's behalf. 'to-decide': requests at Org Units the
// caller's edit Grants reach (`reachOrgUnitIds` null = everywhere, an
// administrator, null Org Unit included), never the caller's own Employee's —
// nobody decides their own leave. An empty reach is an honest empty list.
async function listLeaveRequests({ view, status, accountId, employeeId, reachOrgUnitIds }) {
  const params = [];
  const conditions = [];
  const param = (value) => { params.push(value); return `$${params.length}`; };

  if (view === 'mine') {
    conditions.push(
      `(lr.employee_id = ${param(employeeId)}::bigint OR lr.requested_by_account_id = ${param(accountId)}::bigint)`
    );
  } else {
    if (reachOrgUnitIds !== null) {
      conditions.push(`lr.org_unit_id = ANY(${param(reachOrgUnitIds)}::bigint[])`);
    }
    conditions.push(`lr.employee_id IS DISTINCT FROM ${param(employeeId)}::bigint`);
  }
  if (status) conditions.push(`lr.status = ${param(status)}`);

  const { rows } = await getPool().query(
    `${LEAVE_REQUEST_SELECT}
      WHERE ${conditions.join(' AND ')}
      ORDER BY lr.created_at DESC, lr.id DESC
      LIMIT ${LIST_LIMIT}`,
    params
  );
  return rows.map(toLeaveRequest);
}

// Where an Employee works today: the same COALESCE directory.js resolves.
// Null when they have neither a current Assignment nor a default Org Unit.
async function resolveEmployeeOrgUnitId(employeeId) {
  const { rows } = await getPool().query(
    `SELECT COALESCE(current_assignment.org_unit_id, e.default_org_unit_id) AS org_unit_id
       FROM employees e
       LEFT JOIN LATERAL (
         SELECT ea.org_unit_id
           FROM employee_assignments ea
          WHERE ea.employee_id = e.id
            AND ea.effective_from <= employee_today(ea.employee_id)
            AND (ea.effective_to IS NULL OR ea.effective_to > employee_today(ea.employee_id))
          LIMIT 1
       ) current_assignment ON TRUE
      WHERE e.id = $1`,
    [employeeId]
  );
  return rows[0]?.org_unit_id ?? null;
}

// ---------------------------------------------------------------------------
// Writing
// ---------------------------------------------------------------------------

// `employee` is the directory row the route already resolved (so its
// `isActive` is read, not re-queried); `orgUnitId` is the snapshot above.
// Order, after the route's own body-shape and authority checks: the reason
// must be requestable (400), the Employee must not have departed (409), the
// range must not run backwards (400), and only then does the INSERT meet the
// overlap constraint (409).
async function createLeaveRequest({ employee, orgUnitId, absenceReasonId, startsOn, endsOn, note }, accountId) {
  const { rows: [reason] } = await getPool().query(
    'SELECT id, is_active, is_requestable FROM absence_reasons WHERE id = $1',
    [absenceReasonId]
  );
  if (!reason) throw httpError(400, 'absenceReasonId does not name an existing absence reason');
  if (!reason.is_active || !reason.is_requestable) {
    throw httpError(400, 'absenceReasonId is not an absence reason that can be requested');
  }
  if (!employee.isActive) {
    throw httpError(409, 'this Employee has departed and cannot take leave');
  }
  if (endsOn < startsOn) {
    throw httpError(400, 'endsOn cannot be before startsOn');
  }

  try {
    const id = await withActor(accountId, async (client) => {
      const { rows: [row] } = await client.query(
        `INSERT INTO leave_requests
           (employee_id, absence_reason_id, org_unit_id, starts_on, ends_on, note, requested_by_account_id)
         VALUES ($1, $2, $3, $4::date, $5::date, $6, $7)
         RETURNING id`,
        [employee.id, reason.id, orgUnitId, startsOn, endsOn, note, accountId]
      );
      return row.id;
    });
    return await findLeaveRequest(id);
  } catch (error) {
    throw mapLeaveRequestWriteError(error);
  }
}

// One function for both transitions out of `pending` that a decider makes.
// The `WHERE status = 'pending'` is the race-safe check: two deciders
// clicking at once cannot both win, and the loser gets the same 409 a stale
// page would.
async function decideLeaveRequest(id, decision, note, accountId) {
  const verb = decision === 'approved' ? 'approved' : 'rejected';
  await withActor(accountId, async (client) => {
    const { rows } = await client.query(
      `UPDATE leave_requests
          SET status = $2, decided_at = now(), decided_by_account_id = $3, decision_note = $4
        WHERE id = $1 AND status = 'pending'
        RETURNING id`,
      [id, decision, accountId, note]
    );
    if (rows.length === 0) throw httpError(409, `only a pending leave request can be ${verb}`);
  });
  return findLeaveRequest(id);
}

async function cancelLeaveRequest(id, accountId) {
  await withActor(accountId, async (client) => {
    const { rows } = await client.query(
      `UPDATE leave_requests
          SET status = 'cancelled', cancelled_at = now(), cancelled_by_account_id = $2
        WHERE id = $1 AND status = 'pending'
        RETURNING id`,
      [id, accountId]
    );
    if (rows.length === 0) throw httpError(409, 'only a pending leave request can be cancelled');
  });
  return findLeaveRequest(id);
}

module.exports = {
  requireDate,
  optionalNote,
  requireStatus,
  requireView,
  findLeaveRequest,
  listLeaveRequests,
  resolveEmployeeOrgUnitId,
  createLeaveRequest,
  decideLeaveRequest,
  cancelLeaveRequest
};
