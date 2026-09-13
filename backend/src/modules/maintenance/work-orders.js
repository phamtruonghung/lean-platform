/*
 * Work orders (issue #57), the second table this Module owns after Assets
 * (issue #56). Same shape as assets.js, and the same rule holds: this file
 * never requires '../people' and never resolves or writes a People record.
 * Resolving the Asset a caller named, and asking whether they may act at its
 * Org Unit, both happen one layer up in work-order-routes.js through
 * modules/people's entry point.
 *
 * This file DOES join `org_units` (for the Org Unit's name on a listing row)
 * and `employees` (to resolve `assigned_to` to a name) — both ordinary
 * cross-Module reads, the same as assets.js's own join onto org_units.
 * ADR-0006 makes a Module a code seam, not a data seam.
 *
 * Two things this file deliberately does NOT do, because the database
 * already does them:
 *
 *   - Fill org_unit_id. `work_orders_fill_org_unit` (baseline migration) runs
 *     BEFORE INSERT and copies it from the named Asset. A caller's
 *     `orgUnitId`, if one is even sent, is ignored — see createWorkOrder's
 *     own comment.
 *   - Issue the work order number. `next_document_number('WO', siteCode,
 *     year)` (baseline migration) is the Site's own sequence, keyed on
 *     `prefix-siteCode-year`, so two Sites number independently for free.
 */

const { getPool, withActor } = require('../../platform/db');
const { httpError, notFound, parseId } = require('./errors');

// Mirrors the CHECK constraint on work_orders.work_type in the baseline, so a
// bad value is a 400 with a clear message rather than a raw constraint
// violation.
const WORK_TYPES = ['corrective', 'preventive', 'predictive', 'inspection', 'improvement', 'calibration'];

// Statuses that count as "open" for the Site-wide list, listed positively
// (rather than as NOT IN the three closed ones) so Postgres's
// predicate-implication check can prove this query is covered by the
// baseline migration's partial index, `work_orders_open_idx`
// (`WHERE status IN ('draft', 'approved', 'scheduled', 'in_progress',
// 'on_hold')`). This list is deliberately kept identical to that
// predicate — if the two drift apart, the index silently stops applying to
// this query and Postgres falls back to a full scan with no error anywhere
// to notice.
const OPEN_STATUSES = ['draft', 'approved', 'scheduled', 'in_progress', 'on_hold'];

// The two terminal states this slice (issue #63) offers, added to
// listWorkOrdersAtSite only when a caller asks for history by name.
// Deliberately NOT the whole of the non-open set: 'closed' stays unoffered,
// so a row in it is not silently surfaced by a filter that was asked for
// something else.
const HISTORY_STATUSES = ['completed', 'cancelled'];

// asset_code/asset_name/org_unit_name/assignee_name all come from joins, so
// every work order this Module hands back carries enough for a list row
// without a second round trip. Mirrors ASSET_COLUMNS/toAsset's own shape.
const WORK_ORDER_COLUMNS = `
  wo.id, wo.work_order_no, wo.asset_id, wo.org_unit_id, wo.summary, wo.description,
  wo.work_type, wo.priority, wo.status, wo.assigned_to,
  wo.created_at, wo.updated_at,
  a.code AS asset_code, a.name AS asset_name,
  ou.name AS org_unit_name,
  ou.site_id AS site_id,
  e.display_name AS assignee_name
`;

// The join chain WORK_ORDER_COLUMNS depends on, factored out because every
// function below attaches it after its own FROM clause — whether that FROM
// names the bare `work_orders` table or a CTE (`inserted`/`updated`) built
// off it, `wo` is always the alias the join chain expects.
const WORK_ORDER_FROM = `
  JOIN assets a ON a.id = wo.asset_id
  JOIN org_units ou ON ou.id = wo.org_unit_id
  LEFT JOIN employees e ON e.id = wo.assigned_to
`;

function toWorkOrder(row) {
  return {
    id: row.id,
    workOrderNo: row.work_order_no,
    assetId: row.asset_id,
    assetCode: row.asset_code,
    assetName: row.asset_name,
    orgUnitId: row.org_unit_id,
    orgUnitName: row.org_unit_name,
    siteId: row.site_id,
    summary: row.summary,
    description: row.description,
    workType: row.work_type,
    priority: row.priority,
    status: row.status,
    assignedTo: row.assigned_to,
    assigneeName: row.assignee_name ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

// A work order task (issue #74, consuming the baseline's `work_order_tasks`),
// with the required Skill's NAME from the join. Mirrors the job plan task
// shape job-plans.js hands back, plus the three execution fields a task
// carries once it has been worked.
const WORK_ORDER_TASK_COLUMNS = `
  wot.id, wot.work_order_id, wot.step_no, wot.instruction, wot.skill_id,
  wot.status, wot.note, wot.reading,
  s.name AS skill_name
`;

function toWorkOrderTask(row) {
  return {
    id: row.id,
    stepNo: row.step_no,
    instruction: row.instruction,
    skillId: row.skill_id,
    skillName: row.skill_name ?? null,
    status: row.status,
    note: row.note,
    // NUMERIC(18,4) crosses the wire as a string by default; a reading that
    // fits this column comfortably is converted to a Number, the same choice
    // downtime.js's durationMinutes makes.
    reading: row.reading === null ? null : Number(row.reading)
  };
}

// The tasks copied onto a work order, ordered step_no, on whichever
// connection is handed in. Kept separate from the list read on purpose: the
// Site-wide work order LIST must not carry tasks (it would be an N+1), so only
// the detail read and the raise sweep below attach them.
async function listWorkOrderTasks(workOrderId, client = getPool()) {
  const { rows } = await client.query(
    `SELECT ${WORK_ORDER_TASK_COLUMNS}
       FROM work_order_tasks wot
       LEFT JOIN skills s ON s.id = wot.skill_id
      WHERE wot.work_order_id = $1
      ORDER BY wot.step_no`,
    [workOrderId]
  );
  return rows.map(toWorkOrderTask);
}

// One work order plus its copied tasks and the PM schedule it came from — the
// detail read behind GET /work-orders/:id and the shape the raise sweep
// returns. `client` is the pool by default and a transaction client when the
// caller is inside the raise's own transaction, so a just-inserted,
// not-yet-committed work order can be re-read. Null when the id names nothing.
async function findWorkOrderWithTasks(id, client = getPool()) {
  if (parseId(id) === null) return null;
  const { rows } = await client.query(
    `SELECT ${WORK_ORDER_COLUMNS}, wo.pm_schedule_id
       FROM work_orders wo
       ${WORK_ORDER_FROM}
      WHERE wo.id = $1`,
    [id]
  );
  if (!rows[0]) return null;

  return {
    ...toWorkOrder(rows[0]),
    pmScheduleId: rows[0].pm_schedule_id ?? null,
    tasks: await listWorkOrderTasks(id, client)
  };
}

function requireNonEmptyString(field, value) {
  if (typeof value !== 'string' || value.trim() === '') {
    throw httpError(400, `${field} is required`);
  }
}

// A backstop, not the primary defence — work-order-routes.js's
// requireAssetWriteScope already 404s an unknown Asset before this ever runs,
// with a message naming the Asset (the acceptance criterion). This mapping
// only fires if a write reaches the database with an Asset id that stopped
// existing between that check and this INSERT (a concurrent delete — assets
// are never actually deleted, only retired, so this is close to unreachable
// in practice, but the trigger's own error is not this Module's wording, so
// it is mapped rather than left to leak through).
//
// `error.message` is NOT echoed for 23514/P0001 — src/index.js's stated
// policy is that a database error string names tables and columns, and that
// is Postgres's own text, not a message this Module wrote.
function mapWorkOrderWriteError(error) {
  if (error.code === '23503') {
    return notFound('Asset');
  }
  if (error.code === '23514') {
    return httpError(400, 'that is not a valid work order');
  }
  return error;
}

// The exact wording for every illegal transition this slice (issue #63)
// refuses, kept in one table so startWorkOrder/completeWorkOrder/
// cancelWorkOrder (and assignWorkOrder's own D4 guard below) cannot drift
// apart on phrasing. Messages name the problem ("already been completed"),
// not the state machine.
const TRANSITION_MESSAGES = {
  start: {
    in_progress: 'this Work order has already been started',
    completed: 'this Work order has already been completed',
    cancelled: 'this Work order has been cancelled'
  },
  complete: {
    approved: 'this Work order has not been started, so it cannot be completed',
    completed: 'this Work order has already been completed',
    cancelled: 'this Work order has been cancelled'
  },
  cancel: {
    completed: 'this Work order has already been completed',
    cancelled: 'this Work order has already been cancelled'
  }
};

const TRANSITION_VERB = { start: 'started', complete: 'completed', cancel: 'cancelled' };

// Turns "attempted transition + current status" into a 409 naming the
// problem, or `undefined` if the current status has no message on file for
// that action (callers only reach this once they already know the status is
// not the one legal starting point, so this always resolves to a message in
// practice — the template fallback exists only so a status this slice does
// not expect still gets a sentence rather than `undefined`).
function transitionGuard(action, status) {
  const message = TRANSITION_MESSAGES[action][status]
    ?? `this Work order cannot be ${TRANSITION_VERB[action]} from ${status}`;
  return httpError(409, message);
}

async function findSiteCodeForAsset(assetId) {
  const { rows } = await getPool().query(
    `SELECT s.code
       FROM assets a
       JOIN org_units ou ON ou.id = a.org_unit_id
       JOIN sites s ON s.id = ou.site_id
      WHERE a.id = $1`,
    [assetId]
  );
  return rows[0] ? rows[0].code : null;
}

// Raised in status 'approved' — "agreed, not yet started" (issue #57).
// 'draft' is not yet agreed and 'scheduled' implies a date nobody has set
// yet, so this is inserted explicitly rather than left to the column's own
// 'draft' default.
//
// `orgUnitId` is never read off `attrs` here, even if a caller sent one:
// `work_orders.org_unit_id` is filled by the `work_orders_fill_org_unit`
// trigger from `asset_id`, and the database — not this file — decides it.
async function createWorkOrder({ assetId, summary, workType, priority, description }, accountId) {
  requireNonEmptyString('summary', summary);
  if (!WORK_TYPES.includes(workType)) {
    throw httpError(400, `workType must be one of: ${WORK_TYPES.join(', ')}`);
  }
  if (!Number.isInteger(priority) || priority < 1 || priority > 5) {
    throw httpError(400, 'priority must be an integer between 1 and 5');
  }

  const siteCode = await findSiteCodeForAsset(assetId);
  if (!siteCode) throw notFound('Asset');

  try {
    return await withActor(accountId, async (client) => {
      const { rows: [numberRow] } = await client.query(
        `SELECT next_document_number('WO', $1, EXTRACT(YEAR FROM now())::int) AS work_order_no`,
        [siteCode]
      );

      const { rows: [row] } = await client.query(
        `WITH inserted AS (
           INSERT INTO work_orders (work_order_no, asset_id, summary, description, work_type, priority, status)
           VALUES ($1, $2, $3, $4, $5, $6, 'approved')
           RETURNING *
         )
         SELECT ${WORK_ORDER_COLUMNS}
           FROM inserted wo
           ${WORK_ORDER_FROM}`,
        [numberRow.work_order_no, assetId, summary.trim(), description ?? null, workType, priority]
      );
      return toWorkOrder(row);
    });
  } catch (error) {
    throw mapWorkOrderWriteError(error);
  }
}

// Site-wide, open work orders by default (issue #57), history-inclusive on
// request (issue #63, AC6) — the same Site-wide-read rule listAssetsAtSite
// follows (#55/ADR-0009): scope decides where an Account may act, not what
// it may know about, so this carries no Grant filter. `orgUnitPath`, when
// given, narrows to that Org Unit and everything beneath it via ltree
// containment — the same `path <@ $1::ltree` idiom plant.js's own
// getOrgUnitSubtree uses, resolved by the caller (the route) through
// people.findOrgUnit so an unknown/malformed one is a 404 before this
// function is ever called.
//
// `includeHistory` mirrors listAssetsAtSite's own `includeRetired`
// (assets.js): OPEN_STATUSES stays untouched (its comment explains why —
// Postgres's predicate-implication check needs it identical to
// work_orders_open_idx's own predicate) and HISTORY_STATUSES is unioned in
// only when asked for, as an explicit list rather than "drop the status
// filter" — 'closed' stays unoffered even with history on, so a row in it is
// not silently surfaced by a filter that was asked for something else. This
// widened query cannot use work_orders_open_idx; that is expected and fine.
//
// Ordered priority (ascending, so 1 — the most urgent — sorts first) then
// work_order_no: a morning meeting reads worst-first, and the number is a
// stable, human-readable tiebreaker for two jobs at the same priority.
async function listWorkOrdersAtSite(siteId, { orgUnitPath = null, includeHistory = false } = {}) {
  const statuses = includeHistory ? [...OPEN_STATUSES, ...HISTORY_STATUSES] : OPEN_STATUSES;
  const scopeClause = orgUnitPath ? 'AND ou.path <@ $2::ltree' : '';
  const params = orgUnitPath ? [siteId, orgUnitPath] : [siteId];
  const { rows } = await getPool().query(
    `SELECT ${WORK_ORDER_COLUMNS}
       FROM work_orders wo
       ${WORK_ORDER_FROM}
      WHERE ou.site_id = $1
        AND wo.status IN (${statuses.map((_, i) => `$${params.length + i + 1}`).join(', ')})
        ${scopeClause}
      ORDER BY wo.priority, wo.work_order_no`,
    [...params, ...statuses]
  );
  return rows.map(toWorkOrder);
}

// The null-returning lookup this Module's own routes use before a write, the
// same shape assets.js's findAsset has: total, so a malformed id answers null
// rather than handing Postgres a non-numeric BIGINT and turning a 404 into a
// 500.
async function findWorkOrder(id) {
  if (parseId(id) === null) return null;
  const { rows } = await getPool().query(
    `SELECT ${WORK_ORDER_COLUMNS}
       FROM work_orders wo
       ${WORK_ORDER_FROM}
      WHERE wo.id = $1`,
    [id]
  );
  return rows[0] ? toWorkOrder(rows[0]) : null;
}

// Assigning and reassigning are one act: an idempotent replacement of a single
// value, so there is no separate reassign path and nothing here reads the
// previous assignee. No qualification is consulted — see ADR-0018: the schema
// puts a job's skill requirement on its tasks, tasks come from Job plans
// (#74), so nothing yet states what this job needs and the Platform must not
// enforce a requirement it cannot see.
//
// The caller (work-order-routes.js) has already proved the Work order exists,
// proved the Employee exists and is not Departed, and asked canAct about
// scope. This function assumes all three, exactly as createWorkOrder does.
// #63 hardening (D4, flagged in that ticket's own PR as an extension to this
// one): before #63 there was no terminal state a Work order could be handed
// out in, so this never read status at all. After #63 a completed or
// cancelled Work order can still be reassigned over HTTP — invisible in the
// UI (the row has left the open list) but real: it overwrites updated_by,
// the one record of who closed the job (see completeWorkOrder's own
// comment), and hands somebody a job that is not actually open. Locked the
// same way the three transitions below are, and reuses their 'cancel'
// wording — "already been completed" / "already been cancelled" is the same
// sentence whether the write that was refused was a cancel or an assign.
async function assignWorkOrder(workOrderId, employeeId, accountId) {
  try {
    return await withActor(accountId, async (client) => {
      const { rows: [current] } = await client.query(
        'SELECT status FROM work_orders WHERE id = $1 FOR UPDATE',
        [workOrderId]
      );
      if (!current) throw notFound('Work order');
      if (current.status === 'completed' || current.status === 'cancelled') {
        throw transitionGuard('cancel', current.status);
      }

      const { rows: [row] } = await client.query(
        `WITH updated AS (
           UPDATE work_orders SET assigned_to = $1 WHERE id = $2 RETURNING *
         )
         SELECT ${WORK_ORDER_COLUMNS}
           FROM updated wo
           ${WORK_ORDER_FROM}`,
        [employeeId, workOrderId]
      );
      return toWorkOrder(row);
    });
  } catch (error) {
    throw mapWorkOrderWriteError(error);
  }
}

// Moves a Work order from approved to in_progress and stamps when work began
// (issue #63, AC1). Guarded inside the transaction over a locked row — the
// same lock-then-check shape approveAccount uses
// (people/service.js:290-353, the lock at 312-315) — so two clients racing
// start() on the same row serialize instead of racing, and the loser reads
// the now-current status and gets the 409 below.
//
// assigned_to is never read here: the issue is explicit that an unassigned
// Work order can still be started ("Deliberately not blocked by #62").
async function startWorkOrder(workOrderId, accountId) {
  try {
    return await withActor(accountId, async (client) => {
      const { rows: [current] } = await client.query(
        'SELECT status FROM work_orders WHERE id = $1 FOR UPDATE',
        [workOrderId]
      );
      // Unreachable in ordinary use — requireWorkOrderWriteScope already
      // proved the row exists — but handled anyway for the same reason
      // createWorkOrder handles its own unreachable 23503: a concurrent
      // delete is not this Module's business to surface as a 500.
      if (!current) throw notFound('Work order');
      if (current.status !== 'approved') throw transitionGuard('start', current.status);

      // status and actual_start are set in the SAME UPDATE statement:
      // work_orders_fill_shift_on_start (baseline migration) is a
      // `BEFORE UPDATE OF actual_start` trigger, which fires only on an
      // UPDATE that touches that column. Setting status first and the
      // timestamp in a second statement would leave shift_instance_id null
      // forever, with nothing anywhere to say so.
      const { rows: [row] } = await client.query(
        `WITH updated AS (
           UPDATE work_orders
              SET status = 'in_progress', actual_start = now()
            WHERE id = $1
           RETURNING *
         )
         SELECT ${WORK_ORDER_COLUMNS}
           FROM updated wo
           ${WORK_ORDER_FROM}`,
        [workOrderId]
      );
      return toWorkOrder(row);
    });
  } catch (error) {
    throw mapWorkOrderWriteError(error);
  }
}

// Moves a Work order from in_progress to completed, stamping when work ended
// and recording what was found (issue #63, AC2). `note` is required — see
// PLAN.md §1.1: this slice exists to produce data, and an optional note
// would be empty on most rows within a week.
//
// Who and when a completion is recorded, decided rather than forgotten:
//   - When: actual_end, stamped by the server with now(). Never accepted
//     from the client — a client-supplied duration is an invented duration.
//   - Who: as an Account, through work_orders.updated_by, filled by the
//     zz_work_orders_set_actor trigger from the app.user_id withActor sets.
//     work_orders.completed_by is deliberately NOT filled: it references
//     employees(id), not app_users(id), and an Account need not be an
//     Employee at all (CONTEXT.md, Account). Filling it would need a new
//     People entry-point export for a nullable column no view reads. Note
//     work_orders is not in the attach_audit list, so updated_by is the only
//     record of who completed the job.
async function completeWorkOrder(workOrderId, { note } = {}, accountId) {
  requireNonEmptyString('note', note);
  try {
    return await withActor(accountId, async (client) => {
      const { rows: [current] } = await client.query(
        'SELECT status FROM work_orders WHERE id = $1 FOR UPDATE',
        [workOrderId]
      );
      if (!current) throw notFound('Work order');
      if (current.status !== 'in_progress') throw transitionGuard('complete', current.status);

      // `wo.pm_schedule_id` is selected only so the PM advance below can run;
      // toWorkOrder ignores the extra column, so the wire shape is unchanged.
      const { rows: [row] } = await client.query(
        `WITH updated AS (
           UPDATE work_orders
              SET status = 'completed', actual_end = now(), completion_note = $2
            WHERE id = $1
           RETURNING *
         )
         SELECT ${WORK_ORDER_COLUMNS}, wo.pm_schedule_id
           FROM updated wo
           ${WORK_ORDER_FROM}`,
        [workOrderId, note.trim()]
      );

      // A PM work order completing advances its schedule (issue #74), in the
      // same transaction as the completion — either the work order is
      // completed and the schedule moved on, or neither. Only a work order
      // that came from a schedule does this; a manually raised one leaves
      // every schedule alone.
      //
      // `last_completed_on` records when the work was actually done. The next
      // due date depends on the schedule's own `anchor`:
      //   - 'completed': the clock starts when the work was done, so it rolls
      //     from today — a service done late simply slides.
      //   - 'due': the obligation is fixed, so it rolls from the ORIGINAL due
      //     date (or today, if there was none) — doing a statutory inspection
      //     three weeks late does not push next year's date back.
      // `interval_days` is NULL only for a meter-only schedule, which this
      // slice does not create; the arithmetic then yields NULL, which is the
      // honest answer rather than an invented date.
      if (row.pm_schedule_id !== null) {
        await client.query(
          `UPDATE pm_schedules
              SET last_completed_on = CURRENT_DATE,
                  next_due_on = CASE
                    WHEN anchor = 'completed' THEN CURRENT_DATE + interval_days
                    ELSE COALESCE(next_due_on, CURRENT_DATE) + interval_days
                  END
            WHERE id = $1`,
          [row.pm_schedule_id]
        );
      }

      return toWorkOrder(row);
    });
  } catch (error) {
    throw mapWorkOrderWriteError(error);
  }
}

// Moves an approved or in_progress Work order to cancelled (issue #63, AC4)
// — a job raised in error, not a job that finished. `reason` is optional,
// unlike completeWorkOrder's `note`: undoing a mistake should not demand
// prose. When given it is persisted to completion_note (ADR-0019: there is
// no cancellation_reason column, and `status` already disambiguates which
// kind of closing note this is) — COALESCE keeps a reason-less cancellation
// from wiping a note that was already on the row.
//
// Does NOT stamp actual_end: a cancelled job was never finished, and
// work_orders_completed_has_end (baseline migration) does not apply to
// 'cancelled'. Stamping it would put a fabricated duration on a row that
// never did the work.
async function cancelWorkOrder(workOrderId, { reason } = {}, accountId) {
  try {
    return await withActor(accountId, async (client) => {
      const { rows: [current] } = await client.query(
        'SELECT status FROM work_orders WHERE id = $1 FOR UPDATE',
        [workOrderId]
      );
      if (!current) throw notFound('Work order');
      if (current.status !== 'approved' && current.status !== 'in_progress') {
        throw transitionGuard('cancel', current.status);
      }

      const { rows: [row] } = await client.query(
        `WITH updated AS (
           UPDATE work_orders
              SET status = 'cancelled', completion_note = COALESCE($2, completion_note)
            WHERE id = $1
           RETURNING *
         )
         SELECT ${WORK_ORDER_COLUMNS}
           FROM updated wo
           ${WORK_ORDER_FROM}`,
        [workOrderId, reason?.trim() || null]
      );
      return toWorkOrder(row);
    });
  } catch (error) {
    throw mapWorkOrderWriteError(error);
  }
}

module.exports = {
  WORK_TYPES,
  OPEN_STATUSES,
  createWorkOrder,
  listWorkOrdersAtSite,
  findWorkOrder,
  findWorkOrderWithTasks,
  listWorkOrderTasks,
  assignWorkOrder,
  startWorkOrder,
  completeWorkOrder,
  cancelWorkOrder
};
