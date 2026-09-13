/*
 * PM schedules (issue #74), the fifth table this Module owns after Assets
 * (#56), Work orders (#57), Requests (#72) and Downtime (#73). Same shape as
 * work-orders.js, and the same rule holds: this file never requires
 * '../people' and never resolves or writes a People record. Resolving the
 * Asset a caller named, and asking whether they may act at its Org Unit, both
 * happen one layer up in pm-schedule-routes.js through modules/people's entry
 * point.
 *
 * A PM schedule is scoped from the Asset, exactly like a work order
 * (CONTEXT.md's PM schedule): what raises a work order before something
 * breaks rather than in response to one. It carries no `org_unit_id` of its
 * own — placement is whatever Org Unit its Asset sits at, resolved by the
 * join below. This slice builds the calendar mechanism only (elapsed time, as
 * distinct from meter-driven accumulation); the meter columns are written
 * NULL on purpose.
 *
 * Cross-Module reads are ordinary joins here, exactly as assets.js and
 * work-orders.js already do (ADR-0006): `assets`/`org_units` for placement
 * and the Site, `sites` for the code that numbers a schedule, and `job_plans`
 * for the plan's name and work_type.
 *
 * `code` and `name` are required NOT NULL columns on the table but are not in
 * the request body — a schedule is described by its Asset and Job plan, not
 * typed by the caller. The number comes from the Site's own sequence
 * (`next_document_number('PM', siteCode, year)`), so two Sites number
 * independently, and the name is derived from the plan and the Asset. That is
 * a decision recorded here: a client naming its own code would be a second
 * source of truth the Site sequence already owns.
 */

const { getPool, withActor } = require('../../platform/db');
const { httpError, notFound, parseId } = require('./errors');
const workOrders = require('./work-orders');

// The schedule's own statuses that count as open, consumed from work-orders.js
// so the raise's `NOT EXISTS` guard and the partial unique index's predicate
// stay in lockstep — see that file's own OPEN_STATUSES comment.
const OPEN_STATUSES = workOrders.OPEN_STATUSES;

// Postgres DATE has no time zone, but node-postgres parses it into a JS Date
// at LOCAL midnight, which JSON.stringify then renders as a UTC instant. A
// calendar date must cross the wire as one — see directory.js's own
// toDateString for the full reasoning this duplicates rather than imports,
// following the same small-helper-per-file idiom this Module already uses.
function toDateString(value) {
  if (value == null) return null;
  if (!(value instanceof Date)) return String(value);
  const y = value.getFullYear();
  const m = String(value.getMonth() + 1).padStart(2, '0');
  const d = String(value.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

// A calendar date, not just a string shaped like one — mirrors skills.js's own
// requireDateString, including the UTC round-trip that catches a day/month Date
// would silently roll over (2026-02-30 -> March 2nd).
function requireDateString(field, value) {
  if (typeof value !== 'string' || !DATE_RE.test(value)) {
    throw httpError(400, `${field} must be a YYYY-MM-DD date`);
  }
  const [year, month, day] = value.split('-').map(Number);
  const parsed = new Date(Date.UTC(year, month - 1, day));
  if (parsed.getUTCFullYear() !== year || parsed.getUTCMonth() !== month - 1 || parsed.getUTCDate() !== day) {
    throw httpError(400, `${field} must be a valid calendar date`);
  }
}

// Every field the wire shape carries, plus `days_until_due` computed by
// Postgres (date - date -> integer, so it needs no JS date arithmetic and
// cannot drift with the process's own clock).
const PM_SCHEDULE_COLUMNS = `
  s.id, s.code, s.name, s.asset_id, s.job_plan_id, s.interval_days, s.anchor,
  s.lead_time_days, s.priority, s.last_completed_on, s.next_due_on, s.is_active,
  a.code AS asset_code, a.name AS asset_name,
  ou.id AS org_unit_id, ou.name AS org_unit_name,
  jp.name AS job_plan_name,
  (s.next_due_on - CURRENT_DATE) AS days_until_due
`;

// The join chain PM_SCHEDULE_COLUMNS depends on, factored out because every
// function below attaches it after its own FROM clause — whether that FROM
// names the bare `pm_schedules` table or a CTE (`inserted`/`updated`) built
// off it, `s` is always the alias the join chain expects.
const PM_SCHEDULE_FROM = `
  JOIN assets a ON a.id = s.asset_id
  JOIN org_units ou ON ou.id = a.org_unit_id
  JOIN job_plans jp ON jp.id = s.job_plan_id
`;

function toPmSchedule(row) {
  return {
    id: row.id,
    code: row.code,
    name: row.name,
    assetId: row.asset_id,
    assetCode: row.asset_code,
    assetName: row.asset_name,
    orgUnitId: row.org_unit_id,
    orgUnitName: row.org_unit_name,
    jobPlanId: row.job_plan_id,
    jobPlanName: row.job_plan_name,
    intervalDays: row.interval_days,
    anchor: row.anchor,
    leadTimeDays: row.lead_time_days,
    priority: row.priority,
    lastCompletedOn: toDateString(row.last_completed_on),
    nextDueOn: toDateString(row.next_due_on),
    isActive: row.is_active,
    daysUntilDue: row.days_until_due
  };
}

// Domain validation of the schedule's own fields, all before any query. The
// calendar interval is required and positive; `anchor` defaults to
// 'completed' (the clock starts when the work was actually done), matching the
// column's own default; `leadTimeDays` defaults 7 and `priority` 3, matching
// the table's.
function resolveIntervalDays(value) {
  if (!Number.isInteger(value) || value <= 0) {
    throw httpError(400, 'intervalDays must be an integer greater than 0');
  }
  return value;
}

function resolveAnchor(value) {
  if (value === undefined || value === null) return 'completed';
  if (value !== 'due' && value !== 'completed') {
    throw httpError(400, 'anchor must be one of: due, completed');
  }
  return value;
}

function resolveLeadTimeDays(value) {
  if (value === undefined || value === null) return 7;
  if (!Number.isInteger(value) || value < 0) {
    throw httpError(400, 'leadTimeDays must be a non-negative integer');
  }
  return value;
}

function resolvePriority(value) {
  if (value === undefined || value === null) return 3;
  if (!Number.isInteger(value) || value < 1 || value > 5) {
    throw httpError(400, 'priority must be an integer between 1 and 5');
  }
  return value;
}

// Optional. Absent means "the interval from today", computed in the INSERT so
// the database's own CURRENT_DATE is the source of truth rather than the
// process's clock; present, it must be a real calendar date.
function resolveNextDueOn(value) {
  if (value === undefined || value === null) return null;
  requireDateString('nextDueOn', value);
  return value;
}

// A backstop, not the primary defence. `pm_schedules.code` is UNIQUE globally;
// the code is generated from the Site sequence so a clash is close to
// unreachable, but it is mapped to a clean 409 rather than a raw unique
// violation. The meter-pair and has-an-interval CHECKs surface as 23514.
function mapPmScheduleWriteError(error) {
  if (error.code === '23505') {
    return httpError(409, 'a PM schedule with this code already exists');
  }
  if (error.code === '23503') {
    return notFound('Asset');
  }
  if (error.code === '23514') {
    return httpError(400, 'that is not a valid PM schedule');
  }
  return error;
}

// The Site-wide listing: active schedules by default (the register everyone
// sees), inactive ones only when a caller asks for them by name. Site-wide
// and carrying no Grant filter (ADR-0009) — scope decides where an Account may
// act, not what it may know about — the same rule listAssetsAtSite and
// listWorkOrdersAtSite follow. Soonest due first, with undated (meter-only)
// schedules last.
async function listPmSchedulesAtSite(siteId, { includeInactive = false } = {}) {
  const activeClause = includeInactive ? '' : 'AND s.is_active';
  const { rows } = await getPool().query(
    `SELECT ${PM_SCHEDULE_COLUMNS}
       FROM pm_schedules s
       ${PM_SCHEDULE_FROM}
      WHERE ou.site_id = $1 ${activeClause}
      ORDER BY s.next_due_on NULLS LAST, s.id`,
    [siteId]
  );
  return rows.map(toPmSchedule);
}

// The null-returning lookup this Module's own routes use before a write, the
// same shape assets.js's findAsset has: total, so a malformed id answers null
// rather than handing Postgres a non-numeric BIGINT and turning a 404 into a
// 500.
async function findPmSchedule(id) {
  if (parseId(id) === null) return null;
  const { rows } = await getPool().query(
    `SELECT ${PM_SCHEDULE_COLUMNS}
       FROM pm_schedules s
       ${PM_SCHEDULE_FROM}
      WHERE s.id = $1`,
    [id]
  );
  return rows[0] ? toPmSchedule(rows[0]) : null;
}

// One schedule + its Asset's Site code, on whichever connection is handed in.
// Only the columns the INSERT needs.
async function readAssetAndPlanContext(db, assetId, jobPlanId) {
  const { rows: [row] } = await db.query(
    `SELECT a.name AS asset_name, jp.name AS job_plan_name, sit.code AS site_code
       FROM assets a
       JOIN org_units ou ON ou.id = a.org_unit_id
       JOIN sites sit ON sit.id = ou.site_id
       CROSS JOIN job_plans jp
      WHERE a.id = $1 AND jp.id = $2`,
    [assetId, jobPlanId]
  );
  return row ?? null;
}

// Creates a calendar PM schedule: an Asset and a Job plan, an interval, and
// either an explicit first due date or "the interval from today". The meter
// columns are deliberately NULL — this slice is the calendar mechanism, and a
// schedule carrying both clocks is a later ticket's concern. The Asset's
// existence and the caller's write scope, and the Job plan's existence and
// active state, are all proved by pm-schedule-routes.js before this runs.
async function createPmSchedule(
  { assetId, jobPlanId, intervalDays, anchor, leadTimeDays, priority, nextDueOn },
  accountId
) {
  const resolvedIntervalDays = resolveIntervalDays(intervalDays);
  const resolvedAnchor = resolveAnchor(anchor);
  const resolvedLeadTimeDays = resolveLeadTimeDays(leadTimeDays);
  const resolvedPriority = resolvePriority(priority);
  const resolvedNextDueOn = resolveNextDueOn(nextDueOn);

  const context = await readAssetAndPlanContext(getPool(), assetId, jobPlanId);
  if (!context) throw notFound('Asset');

  try {
    return await withActor(accountId, async (client) => {
      const { rows: [numberRow] } = await client.query(
        `SELECT next_document_number('PM', $1, EXTRACT(YEAR FROM now())::int) AS code`,
        [context.site_code]
      );

      const { rows: [row] } = await client.query(
        `WITH inserted AS (
           INSERT INTO pm_schedules
             (code, name, asset_id, job_plan_id, interval_days, anchor, lead_time_days, priority, next_due_on)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, COALESCE($9::date, CURRENT_DATE + $5::int))
           RETURNING *
         )
         SELECT ${PM_SCHEDULE_COLUMNS}
           FROM inserted s
           ${PM_SCHEDULE_FROM}`,
        [
          numberRow.code,
          `${context.job_plan_name} — ${context.asset_name}`,
          assetId,
          jobPlanId,
          resolvedIntervalDays,
          resolvedAnchor,
          resolvedLeadTimeDays,
          resolvedPriority,
          resolvedNextDueOn
        ]
      );
      return toPmSchedule(row);
    });
  } catch (error) {
    throw mapPmScheduleWriteError(error);
  }
}

// Deactivation, never deletion. A schedule that is switched off stops raising
// work orders (raiseWorkOrdersAtSite filters on is_active) but stays readable.
// The route resolves existence and write scope first; this re-checks only the
// boolean and the row.
async function setPmScheduleActive(id, isActive, accountId) {
  if (typeof isActive !== 'boolean') {
    throw httpError(400, 'isActive (boolean) is required');
  }
  const schedule = await findPmSchedule(id);
  if (!schedule) throw notFound('PM schedule');

  try {
    return await withActor(accountId, async (client) => {
      const { rows: [row] } = await client.query(
        `WITH updated AS (
           UPDATE pm_schedules SET is_active = $1 WHERE id = $2 RETURNING *
         )
         SELECT ${PM_SCHEDULE_COLUMNS}
           FROM updated s
           ${PM_SCHEDULE_FROM}`,
        [isActive, id]
      );
      return toPmSchedule(row);
    });
  } catch (error) {
    throw mapPmScheduleWriteError(error);
  }
}

// The candidates for a raise sweep: every ACTIVE calendar schedule at the Site
// whose due date is inside its lead time and which has no open work order
// already. The `NOT EXISTS` guard is one half of "never twice for the same
// cycle"; the `work_orders_one_open_per_pm_schedule` partial unique index is
// the other, authoritative half (raiseWorkOrderFromPmSchedule catches its
// 23505 and skips). The two are kept in lockstep through OPEN_STATUSES.
//
// Only `id` and `org_unit_id` are needed by the route, which asks canAct per
// candidate before calling the raise — the service never knows about an
// Account.
async function listDuePmSchedules(siteId) {
  const { rows } = await getPool().query(
    `SELECT s.id, a.org_unit_id
       FROM pm_schedules s
       JOIN assets a ON a.id = s.asset_id
       JOIN org_units ou ON ou.id = a.org_unit_id
      WHERE ou.site_id = $1
        AND s.is_active
        AND s.interval_days IS NOT NULL
        AND s.next_due_on IS NOT NULL
        AND s.next_due_on - s.lead_time_days <= CURRENT_DATE
        AND NOT EXISTS (
          SELECT 1 FROM work_orders wo
           WHERE wo.pm_schedule_id = s.id
             AND wo.status IN (${OPEN_STATUSES.map((_, i) => `$${i + 2}`).join(', ')})
        )
      ORDER BY s.next_due_on, s.id`,
    [siteId, ...OPEN_STATUSES]
  );
  return rows;
}

// Raises one work order for one due schedule, and copies the plan's tasks onto
// it, in ONE transaction: either both the work order and every task exist, or
// neither. The caller (pm-schedule-routes.js) has already proved the schedule
// is at the caller's Site and that the caller holds a write Grant reaching its
// Asset's Org Unit.
//
// The schedule is re-locked and re-checked inside the transaction, so a
// deactivation or a concurrent raise between the listing and this call cannot
// produce a work order for a schedule that is no longer eligible. Returns
// `null` (skip) when the schedule is no longer active, no longer due, or
// already has an open work order — including when the partial unique index is
// what refuses the INSERT, which is the authoritative guard against two
// concurrent sweeps both raising.
//
// `work_type` is the JOB PLAN's, so the work is planned (`is_planned` is a
// generated column). `priority` is the schedule's. `due_date` records which
// occurrence this is, which is what v_pm_compliance reads; the work order's
// own actual_start/actual_end are never derived from the schedule and stay
// null until the work is actually started and completed.
async function raiseWorkOrderFromPmSchedule(scheduleId, accountId) {
  try {
    return await withActor(accountId, async (client) => {
      const { rows: [schedule] } = await client.query(
        `SELECT s.id, s.asset_id, s.job_plan_id, s.priority, s.interval_days,
                s.next_due_on, s.lead_time_days, s.is_active,
                (s.next_due_on - s.lead_time_days <= CURRENT_DATE) AS is_due,
                a.name AS asset_name,
                jp.name AS job_plan_name, jp.work_type,
                sit.code AS site_code
           FROM pm_schedules s
           JOIN assets a ON a.id = s.asset_id
           JOIN org_units ou ON ou.id = a.org_unit_id
           JOIN sites sit ON sit.id = ou.site_id
           JOIN job_plans jp ON jp.id = s.job_plan_id
          WHERE s.id = $1
          FOR UPDATE OF s`,
        [scheduleId]
      );

      if (!schedule) return null;
      if (!schedule.is_active) return null;
      if (schedule.interval_days === null || schedule.next_due_on === null) return null;
      if (!schedule.is_due) return null;

      const { rows: open } = await client.query(
        `SELECT 1 FROM work_orders
          WHERE pm_schedule_id = $1
            AND status IN (${OPEN_STATUSES.map((_, i) => `$${i + 2}`).join(', ')})
          LIMIT 1`,
        [scheduleId, ...OPEN_STATUSES]
      );
      if (open.length > 0) return null;

      const { rows: [numberRow] } = await client.query(
        `SELECT next_document_number('WO', $1, EXTRACT(YEAR FROM now())::int) AS work_order_no`,
        [schedule.site_code]
      );

      const { rows: [inserted] } = await client.query(
        `INSERT INTO work_orders
           (work_order_no, asset_id, pm_schedule_id, summary, work_type, priority, status, due_date)
         VALUES ($1, $2, $3, $4, $5, $6, 'approved', $7)
         RETURNING id`,
        [
          numberRow.work_order_no,
          schedule.asset_id,
          schedule.id,
          `PM: ${schedule.job_plan_name} — ${schedule.asset_name}`,
          schedule.work_type,
          schedule.priority,
          schedule.next_due_on
        ]
      );

      await client.query(
        `INSERT INTO work_order_tasks (work_order_id, step_no, instruction, skill_id)
         SELECT $1, step_no, instruction, skill_id
           FROM job_plan_tasks
          WHERE job_plan_id = $2
          ORDER BY step_no`,
        [inserted.id, schedule.job_plan_id]
      );

      return workOrders.findWorkOrderWithTasks(inserted.id, client);
    });
  } catch (error) {
    // 23505 here is the `work_orders_one_open_per_pm_schedule` partial unique
    // index refusing a second open work order for this schedule — a skip, not
    // an error. The losing transaction has already rolled back; there is
    // nothing to clean up.
    if (error.code === '23505') return null;
    throw mapPmScheduleWriteError(error);
  }
}

module.exports = {
  listPmSchedulesAtSite,
  findPmSchedule,
  createPmSchedule,
  setPmScheduleActive,
  listDuePmSchedules,
  raiseWorkOrderFromPmSchedule
};
