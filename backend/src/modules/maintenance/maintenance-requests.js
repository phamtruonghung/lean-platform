/*
 * Requests (issue #72), the ask half of the Maintenance Module — what anyone
 * on the floor asks maintenance for before there is a Work order. Same shape
 * as work-orders.js: this file never requires '../people' and never resolves
 * or writes a People record; the Asset a caller names, and whether they may
 * act at its Org Unit, are both answered one layer up in
 * maintenance-request-routes.js through modules/people's entry point.
 *
 * This file DOES join `org_units` (the Org Unit's name on a listing row),
 * `assets` (the flattening the row carries), `app_users` (the requester's
 * display name — the audit `created_by` column records WHO raised it, and
 * that is an Account, not an Employee) and, for an accepted Request, the Work
 * order it produced (`work_orders` on `maintenance_request_id`). The last is
 * the reference ADR-0014 restores: a Work order carries a backward pointer to
 * the Request that produced it, so the person who raised it can follow it
 * through to the job.
 *
 * Two things this file deliberately does NOT do, because the database already
 * does them:
 *
 *   - Fill org_unit_id. `maintenance_requests_fill_org_unit` (baseline
 *     migration) is the same `fill_org_unit_from_asset` trigger work_orders
 *     uses, running BEFORE INSERT and copying the named Asset's Org Unit. A
 *     caller's `orgUnitId`, if one is even sent, is ignored.
 *   - Issue the Request number. `next_document_number('RQT', siteCode, year)`
 *     is the Site's own sequence, keyed on `prefix-siteCode-year`, so two
 *     Sites number independently for free — exactly how Work orders are
 *     numbered (`next_document_number('WO', ...)`, work-orders.js).
 */

const { getPool, withActor } = require('../../platform/db');
const { httpError, notFound, parseId } = require('./errors');

// Mirrors the CHECK constraint on maintenance_requests.urgency in the
// baseline, so a bad value is a 400 with a clear message rather than a raw
// constraint violation.
const URGENCIES = ['low', 'normal', 'high', 'immediate'];

// Statuses that count as "in the triage queue" for the Site-wide list, listed
// positively (rather than as NOT IN the three decided ones) so Postgres's
// predicate-implication check can prove this query is covered by the baseline
// migration's partial index, `maintenance_requests_open_idx`
// (`WHERE status IN ('new', 'triaged')`). This list is deliberately kept
// identical to that predicate — if the two drift apart, the index silently
// stops applying to this query and Postgres falls back to a full scan with no
// error anywhere to notice.
const OPEN_REQUEST_STATUSES = ['new', 'triaged'];

// Statuses a triage decision may act on. Accepting, declining and marking a
// duplicate are all decisions about a Request that is still awaiting one; a
// decided Request — accepted, rejected, duplicate — has already been answered
// and triaging it again is the double-click/race the FOR UPDATE guard below
// exists to refuse, not a second chance. Listed positively, and 'new' and
// 'triaged' are both in the queue (a maintenance worker may park a Request as
// 'triaged' and come back; that is still awaiting a decision).
const TRIAGEABLE_STATUSES = ['new', 'triaged'];

const REQUEST_COLUMNS = `
  rq.id, rq.request_no, rq.asset_id, rq.org_unit_id, rq.summary, rq.description,
  rq.urgency, rq.production_stopped, rq.status,
  rq.rejection_reason, rq.duplicate_of_id, rq.reported_at,
  a.code AS asset_code, a.name AS asset_name,
  ou.name AS org_unit_name,
  au.display_name AS requested_by_name,
  du.request_no AS duplicate_of_no,
  wo.id AS work_order_id, wo.work_order_no, wo.status AS work_order_status,
  wo.assigned_to AS work_order_assigned_to,
  wo.actual_end AS work_order_actual_end
`;

function toRequest(row) {
  const hasWorkOrder = row.work_order_id !== null && row.work_order_id !== undefined;
  return {
    id: row.id,
    requestNo: row.request_no,
    assetId: row.asset_id,
    assetCode: row.asset_code,
    assetName: row.asset_name,
    orgUnitId: row.org_unit_id,
    orgUnitName: row.org_unit_name,
    summary: row.summary,
    description: row.description,
    urgency: row.urgency,
    productionStopped: row.production_stopped,
    status: row.status,
    rejectionReason: row.rejection_reason,
    duplicateOfId: row.duplicate_of_id,
    duplicateOfNo: row.duplicate_of_no ?? null,
    requestedByName: row.requested_by_name ?? null,
    reportedAt: row.reported_at,
    // ADR-0014: a Request does not own its Work order. When one exists this
    // carries enough to name it and say how far it has got; the Request stays
    // alive whatever the Work order's own lifecycle does.
    workOrder: hasWorkOrder
      ? {
          id: row.work_order_id.toString(),
          workOrderNo: row.work_order_no,
          status: row.work_order_status,
          assignedTo: row.work_order_assigned_to?.toString() ?? null,
          actualEnd: row.work_order_actual_end
        }
      : null
  };
}

function requireNonEmptyString(field, value) {
  if (typeof value !== 'string' || value.trim() === '') {
    throw httpError(400, `${field} is required`);
  }
}

// Maps a Postgres write failure to a clean 4xx before it reaches a route —
// the same job mapWorkOrderWriteError does for Work orders. An unknown Asset
// surfaces as a foreign-key violation (23503) and becomes a 404 naming the
// Asset; the `fill_org_unit_from_asset` trigger raises the same code for an
// Asset id that stopped existing between the route's existence check and this
// INSERT (assets are retired, not deleted, so this is close to unreachable in
// practice, but the trigger's own error is not this Module's wording, so it
// is mapped rather than left to leak through). `duplicate_of_id` pointing at
// a Request that does not exist is likewise a 23503, mapped to a 404 naming
// the Request a duplicate of.
function mapRequestWriteError(error) {
  if (error.code === '23503') {
    // The Asset the row names, or the Request named as a duplicate's target —
    // indistinguishable from the code alone, so the message is chosen from
    // whichever direction the failing operation took. The route layers below
    // validate both targets before writing, so this only fires on a
    // check-then-act race.
    return notFound('Asset or Request');
  }
  if (error.code === '23514') {
    return httpError(400, 'that is not a valid Request');
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

// Raises a Request (issue #72): what anyone on the floor asks maintenance for,
// against a named Asset. Raised in status 'new' — "an ask and no more", the
// state that commits maintenance to nothing. `orgUnitId` is never read off
// `attrs` here: `maintenance_requests.org_unit_id` is filled by the
// `maintenance_requests_fill_org_unit` trigger from `asset_id`, and the
// database — not this file — decides it.
async function createRequest(
  { assetId, summary, description, urgency = 'normal', productionStopped = false },
  accountId
) {
  requireNonEmptyString('summary', summary);
  if (!URGENCIES.includes(urgency)) {
    throw httpError(400, `urgency must be one of: ${URGENCIES.join(', ')}`);
  }

  const siteCode = await findSiteCodeForAsset(assetId);
  if (!siteCode) throw notFound('Asset');

  try {
    return await withActor(accountId, async (client) => {
      const { rows: [numberRow] } = await client.query(
        `SELECT next_document_number('RQT', $1, EXTRACT(YEAR FROM now())::int) AS request_no`,
        [siteCode]
      );

      const { rows: [row] } = await client.query(
        `WITH inserted AS (
           INSERT INTO maintenance_requests
             (request_no, asset_id, summary, description, urgency, production_stopped, status)
           VALUES ($1, $2, $3, $4, $5, $6, 'new')
           RETURNING *
         )
         SELECT ${REQUEST_COLUMNS}
           FROM inserted rq
           JOIN assets a ON a.id = rq.asset_id
           JOIN org_units ou ON ou.id = rq.org_unit_id
           LEFT JOIN app_users au ON au.id = rq.created_by
           LEFT JOIN work_orders wo ON wo.maintenance_request_id = rq.id
           LEFT JOIN maintenance_requests du ON du.id = rq.duplicate_of_id`,
        [numberRow.request_no, assetId, summary.trim(), description ?? null, urgency, productionStopped]
      );
      return toRequest(row);
    });
  } catch (error) {
    throw mapRequestWriteError(error);
  }
}

// Site-wide, open Requests — the triage queue (issue #72). The same
// Site-wide-read rule listOpenWorkOrdersAtSite follows (ADR-0009): scope
// decides where an Account may act, not what it may know about, so this
// carries no Grant filter, and maintenance answers the floor's asks whatever
// the caller's own Grants happen to be. `orgUnitPath`, when given, narrows to
// that Org Unit and everything beneath it via ltree containment — the same
// `path <@ $1::ltree` idiom the Work order list uses, resolved by the route
// through people.findOrgUnit so an unknown/malformed one is a 404 before this
// is ever called.
async function listOpenRequestsAtSite(siteId, { orgUnitPath = null } = {}) {
  const scopeClause = orgUnitPath ? 'AND ou.path <@ $2::ltree' : '';
  const params = orgUnitPath ? [siteId, orgUnitPath] : [siteId];
  const { rows } = await getPool().query(
    `SELECT ${REQUEST_COLUMNS}
       FROM maintenance_requests rq
       JOIN assets a ON a.id = rq.asset_id
       JOIN org_units ou ON ou.id = rq.org_unit_id
       LEFT JOIN app_users au ON au.id = rq.created_by
       LEFT JOIN work_orders wo ON wo.maintenance_request_id = rq.id
       LEFT JOIN maintenance_requests du ON du.id = rq.duplicate_of_id
      WHERE ou.site_id = $1
        AND rq.status IN (${OPEN_REQUEST_STATUSES.map((_, i) => `$${params.length + i + 1}`).join(', ')})
        ${scopeClause}
      ORDER BY rq.reported_at DESC`,
    [...params, ...OPEN_REQUEST_STATUSES]
  );
  return rows.map(toRequest);
}

// The total form of getRequest below — returns null for a malformed or absent
// id rather than throwing, the same shape assets.findAsset / work-orders'
// findWorkOrder take. It is what a route's existence-before-scope check calls.
async function findRequest(id) {
  if (parseId(id) === null) return null;
  const { rows } = await getPool().query(
    `SELECT ${REQUEST_COLUMNS}
       FROM maintenance_requests rq
       JOIN assets a ON a.id = rq.asset_id
       JOIN org_units ou ON ou.id = rq.org_unit_id
       LEFT JOIN app_users au ON au.id = rq.created_by
       LEFT JOIN work_orders wo ON wo.maintenance_request_id = rq.id
       LEFT JOIN maintenance_requests du ON du.id = rq.duplicate_of_id
      WHERE rq.id = $1`,
    [id]
  );
  return rows[0] ? toRequest(rows[0]) : null;
}

async function getRequest(id) {
  const request = await findRequest(id);
  if (!request) throw notFound('Request');
  return request;
}

// The Requests a caller raised (issue #72): what became of each, including —
// for an accepted one — the Work order it became (ADR-0014). Filtered by the
// audit `created_by` column, which withActor fills from the acting Account, so
// "the requests I raised" is answered by the Account that raised them rather
// than by any grant the caller happens to hold. A read, so it is Site-wide in
// the ADR-0009 sense — but it is also inherently scoped to the caller, since
// it can only ever return rows that Account itself created.
async function listRequestsByRequester(accountId) {
  const { rows } = await getPool().query(
    `SELECT ${REQUEST_COLUMNS}
       FROM maintenance_requests rq
       JOIN assets a ON a.id = rq.asset_id
       JOIN org_units ou ON ou.id = rq.org_unit_id
       LEFT JOIN app_users au ON au.id = rq.created_by
       LEFT JOIN work_orders wo ON wo.maintenance_request_id = rq.id
       LEFT JOIN maintenance_requests du ON du.id = rq.duplicate_of_id
      WHERE rq.created_by = $1
      ORDER BY rq.reported_at DESC`,
    [accountId]
  );
  return rows.map(toRequest);
}

// Accepting a Request (issue #72): raises a Work order for it, and that Work
// order points back at the Request that produced it (ADR-0014). This is one
// transaction — the Work order, the backward reference, and the Request moving
// to 'accepted' either all happen or none do. The Request is locked with
// SELECT ... FOR UPDATE so two maintenance workers triaging the same Request
// at once serialize: the loser re-reads the row, sees it is no longer
// triageable, and is refused with a 409 rather than racing the winner's write.
//
// `maintenanceRequestId` must stay null on the Work order unless this slice
// produced it — a Work order raised directly by maintenance has no Request
// behind it at all, and ADR-0014's whole point is that only the reference, not
// the Request's continuing existence, is ever a live concern.
//
// `urgency` is deliberately NOT copied into the Work order's `priority`: the
// schema keeps the operator's judgement and maintenance's plan separate ("the
// gap between the two is a real signal about how the plant is run"), so the
// caller decides the Work order's `workType` (corrective/preventive/...) and
// `priority` (1-5) when accepting — never copies the Request's urgency over.
async function acceptRequest({ requestId, workType, priority, description }, accountId) {
  const WORK_TYPES = ['corrective', 'preventive', 'predictive', 'inspection', 'improvement', 'calibration'];
  if (!WORK_TYPES.includes(workType)) {
    throw httpError(400, `workType must be one of: ${WORK_TYPES.join(', ')}`);
  }
  if (!Number.isInteger(priority) || priority < 1 || priority > 5) {
    throw httpError(400, 'priority must be an integer between 1 and 5');
  }

  return withActor(accountId, async (client) => {
    const { rows: [locked] } = await client.query(
      `SELECT status FROM maintenance_requests WHERE id = $1 FOR UPDATE`,
      [requestId]
    );
    if (!locked) throw notFound('Request');
    if (!TRIAGEABLE_STATUSES.includes(locked.status)) {
      throw httpError(409, 'that Request has already been triaged');
    }

    // Find the Request's description and summary to seed the Work order, and
    // its Asset so the trigger can fill org_unit_id.
    const { rows: [request] } = await client.query(
      'SELECT id, asset_id, summary, description FROM maintenance_requests WHERE id = $1 FOR UPDATE',
      [requestId]
    );
    const summary = request.summary;
    const workOrderDescription = description ?? request.description;

    const siteCode = await findSiteCodeForAsset(request.asset_id);
    if (siteCode === null || siteCode === undefined) throw notFound('Asset');
    const { rows: [numberRow] } = await client.query(
      `SELECT next_document_number('WO', $1, EXTRACT(YEAR FROM now())::int) AS work_order_no`,
      [siteCode]
    );

    // Create the Work order with the backward reference, then accept the
    // Request — same transaction, so the reference and the decision cannot
    // diverge.
    const { rows: [created] } = await client.query(
      `WITH inserted AS (
           INSERT INTO work_orders
             (work_order_no, asset_id, summary, description, work_type, priority, status,
              maintenance_request_id)
           VALUES ($1, $2, $3, $4, $5, $6, 'approved', $7)
           RETURNING id, work_order_no, status
         )
         SELECT wo.id, wo.work_order_no, wo.status
           FROM inserted wo`,
      [numberRow.work_order_no, request.asset_id, summary, workOrderDescription, workType, priority, requestId]
    );

    await client.query(
      `UPDATE maintenance_requests
          SET status = 'accepted', triaged_at = now()
        WHERE id = $1`,
      [requestId]
    );

    return {
      workOrder: { id: created.id.toString(), workOrderNo: created.work_order_no, status: created.status },
      request: await getRequestInside(client, requestId)
    };
  }).catch((error) => {
    throw mapRequestWriteError(error);
  });
}

// Declining a Request (issue #72): maintenance declines it, and declining
// requires a reason — the schema's own CHECK
// `maintenance_requests_rejected_has_reason` backstops it, and this refused a
// reason-less decline is this Module's clearer wording. Same FOR UPDATE
// guard as accepting: a Request already decided cannot be re-triaged.
async function declineRequest({ requestId, reason }, accountId) {
  if (typeof reason !== 'string' || reason.trim() === '') {
    throw httpError(400, 'a reason is required to decline a Request');
  }
  return withActor(accountId, async (client) => {
    const { rows: [locked] } = await client.query(
      'SELECT status FROM maintenance_requests WHERE id = $1 FOR UPDATE',
      [requestId]
    );
    if (!locked) throw notFound('Request');
    if (!TRIAGEABLE_STATUSES.includes(locked.status)) {
      throw httpError(409, 'that Request has already been triaged');
    }
    await client.query(
      `UPDATE maintenance_requests
          SET status = 'rejected', rejection_reason = $2, triaged_at = now()
        WHERE id = $1`,
      [requestId, reason.trim()]
    );
    return getRequestInside(client, requestId);
  }).catch((error) => {
    throw mapRequestWriteError(error);
  });
}

// Marking a Request as a duplicate (issue #72): a duplicate of one already
// raised, and the surviving Request is named (`duplicate_of_id` + its number).
// The schema's `maintenance_requests_duplicate_has_target` CHECK enforces that
// a duplicate always names its survivor, and `not_own_duplicate` that it never
// names itself; both are backstopped here with this Module's own wording. Same
// FOR UPDATE guard: an already-decided Request can't be re-triaged.
async function markRequestDuplicate({ requestId, duplicateOfId }, accountId) {
  if (parseId(duplicateOfId) === null) {
    throw httpError(400, 'duplicate of which Request?');
  }
  return withActor(accountId, async (client) => {
    const { rows: [locked] } = await client.query(
      'SELECT status FROM maintenance_requests WHERE id = $1 FOR UPDATE',
      [requestId]
    );
    if (!locked) throw notFound('Request');
    if (!TRIAGEABLE_STATUSES.includes(locked.status)) {
      throw httpError(409, 'that Request has already been triaged');
    }
    // The duplicate's target must itself exist and be a different Request.
    const { rows: [target] } = await client.query(
      'SELECT request_no FROM maintenance_requests WHERE id = $1',
      [duplicateOfId]
    );
    if (!target) throw notFound('Request');
    await client.query(
      `UPDATE maintenance_requests
          SET status = 'duplicate', duplicate_of_id = $2, triaged_at = now()
        WHERE id = $1`,
      [requestId, duplicateOfId]
    );
    return getRequestInside(client, requestId);
  }).catch((error) => {
    throw mapRequestWriteError(error);
  });
}

// The read-half helper the three triage transactions share, run on the same
// transaction client so the returned row reflects the write that just ran.
async function getRequestInside(client, requestId) {
  const { rows } = await client.query(
    `SELECT ${REQUEST_COLUMNS}
       FROM maintenance_requests rq
       JOIN assets a ON a.id = rq.asset_id
       JOIN org_units ou ON ou.id = rq.org_unit_id
       LEFT JOIN app_users au ON au.id = rq.created_by
       LEFT JOIN work_orders wo ON wo.maintenance_request_id = rq.id
       LEFT JOIN maintenance_requests du ON du.id = rq.duplicate_of_id
      WHERE rq.id = $1`,
    [requestId]
  );
  return toRequest(rows[0]);
}

module.exports = {
  URGENCIES,
  createRequest,
  listOpenRequestsAtSite,
  findRequest,
  getRequest,
  listRequestsByRequester,
  acceptRequest,
  declineRequest,
  markRequestDuplicate
};