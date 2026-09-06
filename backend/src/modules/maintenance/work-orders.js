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

// asset_code/asset_name/org_unit_name/assignee_name all come from joins, so
// every work order this Module hands back carries enough for a list row
// without a second round trip. Mirrors ASSET_COLUMNS/toAsset's own shape.
const WORK_ORDER_COLUMNS = `
  wo.id, wo.work_order_no, wo.asset_id, wo.org_unit_id, wo.summary, wo.description,
  wo.work_type, wo.priority, wo.status, wo.assigned_to,
  wo.actual_start, wo.actual_end, wo.completion_note,
  wo.created_at, wo.updated_at,
  a.code AS asset_code, a.name AS asset_name,
  ou.name AS org_unit_name,
  e.display_name AS assignee_name
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
    summary: row.summary,
    description: row.description,
    workType: row.work_type,
    priority: row.priority,
    status: row.status,
    assignedTo: row.assigned_to,
    assigneeName: row.assignee_name ?? null,
    actualStart: row.actual_start,
    actualEnd: row.actual_end,
    completionNote: row.completion_note,
    createdAt: row.created_at,
    updatedAt: row.updated_at
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
           JOIN assets a ON a.id = wo.asset_id
           JOIN org_units ou ON ou.id = wo.org_unit_id
           LEFT JOIN employees e ON e.id = wo.assigned_to`,
        [numberRow.work_order_no, assetId, summary.trim(), description ?? null, workType, priority]
      );
      return toWorkOrder(row);
    });
  } catch (error) {
    throw mapWorkOrderWriteError(error);
  }
}

// Site-wide, open work orders only (issue #57) — the same Site-wide-read
// rule listAssetsAtSite follows (#55/ADR-0009): scope decides where an
// Account may act, not what it may know about, so this carries no Grant
// filter. `orgUnitPath`, when given, narrows to that Org Unit and everything
// beneath it via ltree containment — the same `path <@ $1::ltree` idiom
// plant.js's own getOrgUnitSubtree uses, resolved by the caller (the route)
// through people.findOrgUnit so an unknown/malformed one is a 404 before
// this function is ever called.
//
// Ordered priority (ascending, so 1 — the most urgent — sorts first) then
// work_order_no: a morning meeting reads worst-first, and the number is a
// stable, human-readable tiebreaker for two jobs at the same priority.
async function listOpenWorkOrdersAtSite(siteId, { orgUnitPath = null } = {}) {
  const scopeClause = orgUnitPath ? 'AND ou.path <@ $2::ltree' : '';
  const params = orgUnitPath ? [siteId, orgUnitPath] : [siteId];
  const { rows } = await getPool().query(
    `SELECT ${WORK_ORDER_COLUMNS}
       FROM work_orders wo
       JOIN assets a ON a.id = wo.asset_id
       JOIN org_units ou ON ou.id = wo.org_unit_id
       LEFT JOIN employees e ON e.id = wo.assigned_to
      WHERE ou.site_id = $1
        AND wo.status IN (${OPEN_STATUSES.map((_, i) => `$${params.length + i + 1}`).join(', ')})
        ${scopeClause}
      ORDER BY wo.priority, wo.work_order_no`,
    [...params, ...OPEN_STATUSES]
  );
  return rows.map(toWorkOrder);
}

// The total form of getWorkOrder below — returns null for a malformed or
// absent id rather than throwing, the same shape assets.findAsset (and
// People's findOrgUnit/findSite) take. It is what a route's existence-before-
// scope check calls (asset-routes.js's requireAssetWriteScope is the prior
// art); the route resolves the row first so an unknown or malformed :id is
// a clean 404 before `canAct` is ever asked about scope.
async function findWorkOrder(id) {
  if (parseId(id) === null) return null;
  const { rows } = await getPool().query(
    `SELECT ${WORK_ORDER_COLUMNS}
       FROM work_orders wo
       JOIN assets a ON a.id = wo.asset_id
       JOIN org_units ou ON ou.id = wo.org_unit_id
       LEFT JOIN employees e ON e.id = wo.assigned_to
      WHERE wo.id = $1`,
    [id]
  );
  return rows[0] ? toWorkOrder(rows[0]) : null;
}

// Mirrors assets.findAsset -> getAsset's throw on null: the route middleware
// resolve-plus-404 uses findWorkOrder; any service-function path that needs a
// work order to exist and reads it again calls getWorkOrder. Returns the row.
async function getWorkOrder(id) {
  const workOrder = await findWorkOrder(id);
  if (!workOrder) throw notFound('Work order');
  return workOrder;
}

// Issues the assignment (issue #62): sets `assigned_to` to the Employee a
// supervisor has chosen. Reassigning is calling this again with a different
// id — there is deliberately no "unassign" state being invented here; a job
// is either given to somebody or (still) unassigned, and taking it back off
// somebody without replacing them is not a workflow this slice offers (the
// open list shows "Unassigned" for a null assignee, and #63's transitions are
// a separate ticket).
//
// `isActive = FALSE` on the target Employee is refused here, not only left
// out of the client's candidate picker: the server is the arbiter of "this
// person still works here", so a stale client offering a departed assignee
// cannot strand work in the hands of somebody the plant no longer employs.
// This is a deliberate 400, not 404 — the Employee exists, it is just not an
// assignable one.
async function setAssignee(workOrderId, employeeId, accountId) {
  const workOrder = await getWorkOrder(workOrderId); // throws the 404.

  const { rows } = await getPool().query(
    'SELECT is_active FROM employees WHERE id = $1',
    [employeeId]
  );
  if (rows.length === 0) throw notFound('Employee');
  if (!rows[0].is_active) {
    throw httpError(400, 'that Employee has departed and cannot be assigned');
  }

  try {
    return await withActor(accountId, async (client) => {
      const { rows: [row] } = await client.query(
        `WITH updated AS (
           UPDATE work_orders SET assigned_to = $1 WHERE id = $2 RETURNING *
         )
         SELECT ${WORK_ORDER_COLUMNS}
           FROM updated wo
           JOIN assets a ON a.id = wo.asset_id
           JOIN org_units ou ON ou.id = wo.org_unit_id
           LEFT JOIN employees e ON e.id = wo.assigned_to`,
        [employeeId, workOrder.id]
      );
      return toWorkOrder(row);
    });
  } catch (error) {
    throw mapWorkOrderWriteError(error);
  }
}

// The four states this slice (issue #63) offers and no more: agreed
// (`approved`), in progress, completed, cancelled. The database allows eight;
// these three transitions below never introduce the other four (`draft`,
// `scheduled`, `on_hold`, `closed`) — every status a caller can reach through
// this Module is one the interface already explains. Each transition's source
// statuses are listed positively, so a new transition cannot silently reach a
// status nobody has a word for.
//
// Each transition rides `withActor` (audit + `updated_by`), and each refuses
// a row whose status is not a legal source — the server is the arbiter of the
// lifecycle, never the client. The database backstops the *shape* of a cycle
// (a completed row must carry `actual_end` — `work_orders_completed_has_end`;
// a completed one can't start before it ended — `work_orders_actual_window`),
// but the legality of a *source* status is this Module's wording, because the
// database's own answer to an illegal UPDATE would be a bare CHECK violation.
const STARTABLE_STATUSES = ['approved']; // agreed -> in progress.
const COMPLETABLE_STATUSES = ['in_progress']; // -> completed.
const CANCELLABLE_STATUSES = ['approved', 'in_progress']; // -> cancelled.

// Runs one work order transition: checks the source status is one this
// transition may start from, applies the UPDATE, and returns the row with its
// joins — the same shape setAssignee returns. The transition's SQL sets
// `status` and whichever timestamp columns it owns; it never touches the
// others (starting leaves `actual_end` null, completing fills it).
async function transitionWorkOrder(
  workOrderId,
  statuses,
  nextStatus,
  columnUpdates,
  accountId
) {
  const workOrder = await getWorkOrder(workOrderId); // throws the 404.
  if (!statuses.includes(workOrder.status)) {
    throw httpError(400, `cannot ${columnUpdates.action} a Work order in status '${workOrder.status}'`);
  }

  try {
    return await withActor(accountId, async (client) => {
      const { rows: [row] } = await client.query(
        columnUpdates.query,
        [nextStatus, workOrder.id, ...(columnUpdates.params ?? [])]
      );
      return toWorkOrder(row);
    });
  } catch (error) {
    throw mapWorkOrderWriteError(error);
  }
}

// Starting (issue #63): records when work began and moves the Work order to
// in-progress. Only `approved` — "agreed, not yet started" — may be started;
// a job that has already begun, finished or been cancelled has no business
// being "started" again.
const START_COLUMNS = {
  query: `WITH updated AS (
           UPDATE work_orders SET status = $1, actual_start = now()
           WHERE id = $2 AND status = 'approved'
           RETURNING *
         )
         SELECT ${WORK_ORDER_COLUMNS}
           FROM updated wo
           JOIN assets a ON a.id = wo.asset_id
           JOIN org_units ou ON ou.id = wo.org_unit_id
           LEFT JOIN employees e ON e.id = wo.assigned_to`,
  params: [],
  action: 'start'
};

function startWorkOrder(workOrderId, accountId) {
  return transitionWorkOrder(
    workOrderId,
    STARTABLE_STATUSES,
    'in_progress',
    START_COLUMNS,
    accountId
  );
}

// Completing (issue #63): records when work ended, and takes a note of what
// was found. Refuses a Work order that was never started — a duration is never
// invented, so completing requires `in_progress`, which only starting (which
// sets `actual_start = now()`) can have produced (the acceptance criterion).
// `completion_note` is optional; an empty-string is normalised away so a
// caller cannot park a whitespace string meaning "nothing to say".
const COMPLETE_COLUMNS = {
  query: `WITH updated AS (
           UPDATE work_orders
             SET status = $1, actual_end = now(), completion_note = $3
           WHERE id = $2 AND status = 'in_progress'
           RETURNING *
         )
         SELECT ${WORK_ORDER_COLUMNS}
           FROM updated wo
           JOIN assets a ON a.id = wo.asset_id
           JOIN org_units ou ON ou.id = wo.org_unit_id
           LEFT JOIN employees e ON e.id = wo.assigned_to`,
  params: [],
  action: 'complete'
};

function completeWorkOrder(workOrderId, { completionNote = null } = {}, accountId) {
  return transitionWorkOrder(
    workOrderId,
    COMPLETABLE_STATUSES,
    'completed',
    {
      ...COMPLETE_COLUMNS,
      params: [
        typeof completionNote === 'string' && completionNote.trim() !== ''
          ? completionNote.trim()
          : null
      ]
    },
    accountId
  );
}

// Cancelling (issue #63): a Work order raised in error is cancelled rather
// than left open pretending to be work. Either of the two states this slice
// renders as live — agreed or in progress — may be cancelled; a completed job
// stays readable as history, and a cancelled one is never cancelled twice.
const CANCEL_COLUMNS = {
  query: `WITH updated AS (
           UPDATE work_orders
             SET status = $1
           WHERE id = $2 AND status IN ('approved', 'in_progress')
           RETURNING *
         )
         SELECT ${WORK_ORDER_COLUMNS}
           FROM updated wo
           JOIN assets a ON a.id = wo.asset_id
           JOIN org_units ou ON ou.id = wo.org_unit_id
           LEFT JOIN employees e ON e.id = wo.assigned_to`,
  params: [],
  action: 'cancel'
};

function cancelWorkOrder(workOrderId, accountId) {
  return transitionWorkOrder(
    workOrderId,
    CANCELLABLE_STATUSES,
    'cancelled',
    CANCEL_COLUMNS,
    accountId
  );
}

// The assignee picker's data (issue #62): every active Employee at the Site
// the work order's Asset sits at, each carrying what they currently hold —
// their `employee_skills` rows joined against `skills`, with a lapsed
// qualification shown as lapsed (expires_on in the past) rather than simply
// dropped, so "never trained" and "needs revalidating" stay distinguishable
// (the distinction #11 built; #55's assignment decision says the Platform
// *shows* qualifications, it does not enforce them).
//
// Site-scoped to the work order's Site via the Employee's current Org Unit —
// the same "current or default" resolution listEmployees (People) uses —
// because "any active Employee" (#55) is bounded by the plant the work order
// lives in: a supervisor on Site A is not offered Site B's workforce. A
// departed Employee has no row here at all (is_active = TRUE filters them
// out), which is what "a departed Employee is not offered as an assignee"
// means.
//
// One query, never a query-per-employee: employees LEFT JOIN their current
// assignment resolution (a LATERAL, same as People's listEmployees) LEFT
// JOIN org_units for the Site test, LEFT JOIN employee_skills and skills for
// the qualifications. An Employee with no current skills comes back with an
// empty `qualifications` array — the "holds nothing" case, which is
// deliberately distinct from the "holds a lapsed one" case.
async function listAssigneeCandidates(workOrderId) {
  const workOrder = await getWorkOrder(workOrderId); // throws the 404.

  const { rows } = await getPool().query(
    `SELECT e.id, e.employee_no, e.first_name, e.last_name, e.display_name,
            s.id AS skill_id, s.code AS skill_code, s.name AS skill_name,
            es.proficiency_level, es.assessed_on, es.expires_on
       FROM employees e
       LEFT JOIN LATERAL (
         SELECT ea.org_unit_id
           FROM employee_assignments ea
          WHERE ea.employee_id = e.id
            AND ea.effective_from <= CURRENT_DATE
            AND (ea.effective_to IS NULL OR ea.effective_to > CURRENT_DATE)
          LIMIT 1
       ) current_assignment ON TRUE
       JOIN org_units ou
         ON ou.id = COALESCE(current_assignment.org_unit_id, e.default_org_unit_id)
       LEFT JOIN employee_skills es ON es.employee_id = e.id
       LEFT JOIN skills s ON s.id = es.skill_id
      WHERE e.is_active = TRUE
        AND ou.site_id = $1
      ORDER BY e.display_name, s.name`,
    [workOrder.orgUnitId === null ? null : await siteIdForOrgUnit(workOrder.orgUnitId)]
  );
  return groupCandidateRows(rows);
}

// An Employee's Org Unit is by definition inside one Site (ADR-0005: "Every
// part of the plant hierarchy belongs to exactly one Site"), so the work
// order's own Org Unit resolves to exactly one Site. Kept as its own small
// helper rather than joined into the candidates query so the two questions —
// "which Site is this work order in" and "which Employees are there" — stay
// readable as themselves. `path` is an ltree but this only needs the Site id,
// which the column carries flat.
async function siteIdForOrgUnit(orgUnitId) {
  const { rows } = await getPool().query(
    'SELECT site_id FROM org_units WHERE id = $1',
    [orgUnitId]
  );
  return rows[0] ? rows[0].site_id : null;
}

// Group the flat (employee x skill) rows from listAssigneeCandidates into one
// Employee per entry with a `qualifications` array. A row with NULL skill
// columns (the LEFT JOIN found no skill) still yields the Employee, with an
// empty array — the row exists because the employee_at left-join produced it.
// `isLapsed` is computed in JS from `expires_on`: a qualification in the past
// is shown as lapsed, a NULL (never-expiring) or future one is current, and
// an absent skill is a different row shape entirely (no skill columns).
function toDateString(value) {
  if (value === null || value === undefined) return null;
  if (value instanceof Date) {
    const y = value.getUTCFullYear();
    const m = String(value.getUTCMonth() + 1).padStart(2, '0');
    const d = String(value.getUTCDate()).padStart(2, '0');
    return `${y}-${m}-${d}`;
  }
  return String(value);
}

function groupCandidateRows(rows) {
  const byEmployee = new Map();
  for (const row of rows) {
    let candidate = byEmployee.get(row.id);
    if (!candidate) {
      candidate = {
        id: row.id,
        employeeNo: row.employee_no,
        firstName: row.first_name,
        lastName: row.last_name,
        displayName: row.display_name,
        qualifications: []
      };
      byEmployee.set(row.id, candidate);
    }
    if (row.skill_id !== null && row.skill_id !== undefined) {
      const expiresOn = row.expires_on;
      candidate.qualifications.push({
        skillId: row.skill_id,
        skillCode: row.skill_code,
        skillName: row.skill_name,
        proficiencyLevel: row.proficiency_level,
        assessedOn: toDateString(row.assessed_on),
        expiresOn: toDateString(expiresOn),
        isLapsed: expiresOn instanceof Date
          ? expiresOn.getTime() < Date.now()
          : expiresOn !== null && expiresOn !== undefined
            ? new Date(expiresOn).getTime() < Date.now()
            : false
      });
    }
  }
  return [...byEmployee.values()];
}

module.exports = {
  WORK_TYPES,
  OPEN_STATUSES,
  createWorkOrder,
  listOpenWorkOrdersAtSite,
  findWorkOrder,
  getWorkOrder,
  setAssignee,
  startWorkOrder,
  completeWorkOrder,
  cancelWorkOrder,
  listAssigneeCandidates
};
