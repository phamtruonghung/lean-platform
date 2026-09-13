/*
 * Maintenance requests (issue #72), the third table this Module owns after
 * Assets (#56) and Work orders (#57). Same shape as work-orders.js, and the
 * same rule holds: this file never requires '../people' and never resolves or
 * writes a People record. Resolving the Asset a caller named, and asking
 * whether they may act at its Org Unit, both happen one layer up in
 * request-routes.js through modules/people's entry point.
 *
 * Cross-Module reads are ordinary joins here, exactly as assets.js and
 * work-orders.js already do (ADR-0006): `org_units` for the Org Unit's name
 * and Site, `employees` to resolve `reported_by`/`triaged_by` to a name, and
 * `work_orders` for the job an accepted request produced.
 *
 * Two things this file deliberately does NOT do, because the database already
 * does them:
 *
 *   - Fill org_unit_id. `maintenance_requests_fill_org_unit` (baseline
 *     migration) runs BEFORE INSERT and copies it from the named Asset, the
 *     same trigger work_orders uses. A caller's `orgUnitId`, if one is even
 *     sent, is ignored.
 *   - Issue the request number. `next_document_number('MR', siteCode, year)`
 *     is the Site's own sequence, keyed on `prefix-siteCode-year`, so two
 *     Sites number independently for free.
 *
 * CONTEXT.md's own distinction is load-bearing throughout: a Request is what
 * anyone on the floor asks maintenance for, before there is a work order.
 * Accepting one produces a Work order that still points back to it (ADR-0014,
 * `work_orders.maintenance_request_id`); `urgency` is the reporter's
 * judgement and is never copied onto the work order's own `priority`, which
 * is maintenance's.
 */

const { getPool, withActor } = require('../../platform/db');
const { httpError, notFound, parseId } = require('./errors');
// The work order field catalogue is validated identically to work-orders.js's
// own createWorkOrder — imported rather than copied so the two write paths
// cannot drift onto different membership the day the CHECK constraint moves.
const { WORK_TYPES } = require('./work-orders');

// Mirrors the CHECK constraint on maintenance_requests.urgency in the
// baseline, so a bad value is a 400 with a clear message rather than a raw
// constraint violation.
const URGENCIES = ['low', 'normal', 'high', 'immediate'];

// The statuses that count as still awaiting a decision, listed positively so
// the intent is legible next to the baseline's partial index,
// `maintenance_requests_open_idx` (`WHERE status IN ('new', 'triaged')`).
const OPEN_STATUSES = ['new', 'triaged'];

// The one transition message every triage action shares. Accepting,
// declining and marking duplicate are three different ends, but all three
// start from the same two statuses, and the refusal a caller sees is the same
// sentence whichever one they tried.
const ALREADY_TRIAGED = 'this Request has already been triaged';

// asset_code/asset_name/org_unit_name/reporter_name and the work order's own
// number/status all come from joins, so every request this Module hands back
// carries enough for a list row — and to answer "what became of it" — without
// a second round trip. Mirrors WORK_ORDER_COLUMNS/toWorkOrder's own shape.
const REQUEST_COLUMNS = `
  r.id, r.request_no, r.asset_id, r.org_unit_id, r.summary, r.description,
  r.urgency, r.production_stopped, r.reported_by, r.reported_at,
  r.status, r.triaged_at, r.rejection_reason, r.duplicate_of_id,
  a.code AS asset_code, a.name AS asset_name,
  ou.name AS org_unit_name,
  e.display_name AS reporter_name,
  wo.id AS work_order_id, wo.work_order_no AS work_order_no, wo.status AS work_order_status
`;

// The join chain REQUEST_COLUMNS depends on, factored out because every
// function below attaches it after its own FROM clause — whether that FROM
// names the bare `maintenance_requests` table or a CTE (`inserted`/`updated`)
// built off it, `r` is always the alias the join chain expects. The
// work_orders join is LEFT because a request may not have produced one yet:
// only acceptance inserts the row this finds (ADR-0014).
const REQUEST_FROM = `
  JOIN assets a ON a.id = r.asset_id
  JOIN org_units ou ON ou.id = r.org_unit_id
  LEFT JOIN employees e ON e.id = r.reported_by
  LEFT JOIN work_orders wo ON wo.maintenance_request_id = r.id
`;

function toRequest(row) {
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
    reportedBy: row.reported_by,
    reporterName: row.reporter_name ?? null,
    reportedAt: row.reported_at,
    status: row.status,
    triagedAt: row.triaged_at,
    rejectionReason: row.rejection_reason,
    duplicateOfId: row.duplicate_of_id,
    workOrder: row.work_order_id === null
      ? null
      : { id: row.work_order_id, workOrderNo: row.work_order_no, status: row.work_order_status }
  };
}

function requireNonEmptyString(field, value) {
  if (typeof value !== 'string' || value.trim() === '') {
    throw httpError(400, `${field} is required`);
  }
}

// `urgency` is the reporter's own judgement and defaults to 'normal'. A value
// that is present but not one of the four the column admits is a 400 up front
// rather than a 23514 at the INSERT.
function resolveUrgency(value) {
  if (value === undefined || value === null) return 'normal';
  if (!URGENCIES.includes(value)) {
    throw httpError(400, `urgency must be one of: ${URGENCIES.join(', ')}`);
  }
  return value;
}

// `productionStopped` defaults false. Anything present that is not a JSON
// boolean is a 400 — a string 'false' is truthy and would silently record the
// opposite of what was meant.
function resolveProductionStopped(value) {
  if (value === undefined || value === null) return false;
  if (typeof value !== 'boolean') {
    throw httpError(400, 'productionStopped must be a boolean');
  }
  return value;
}

// A backstop, not the primary defence — request-routes.js already 404s an
// unknown Asset before a write ever reaches here, with a message naming the
// Asset (the acceptance criterion). This maps the trigger's own
// `foreign_key_violation` (raised by fill_org_unit_from_asset, baseline
// migration) if an Asset vanished between that check and this INSERT. The
// raw database message is NOT echoed: it names tables and columns.
function mapRequestWriteError(error) {
  if (error.code === '23503') {
    return notFound('Asset');
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

// Raises a Request in status 'new' (the column default). `orgUnitId` is never
// read off `attrs` even if a caller sent one: `maintenance_requests.org_unit_id`
// is filled by the `maintenance_requests_fill_org_unit` trigger from
// `asset_id`, and the database — not this file — decides it. `reported_at` is
// the column default `now()`; `reported_by` is the caller's linked Employee
// id, decided by the route (which owns the Account) and passed in.
async function createRequest(
  { assetId, summary, description, urgency, productionStopped, reportedBy },
  accountId
) {
  requireNonEmptyString('summary', summary);
  const resolvedUrgency = resolveUrgency(urgency);
  const resolvedStopped = resolveProductionStopped(productionStopped);

  const siteCode = await findSiteCodeForAsset(assetId);
  if (!siteCode) throw notFound('Asset');

  try {
    return await withActor(accountId, async (client) => {
      const { rows: [numberRow] } = await client.query(
        `SELECT next_document_number('MR', $1, EXTRACT(YEAR FROM now())::int) AS request_no`,
        [siteCode]
      );

      const { rows: [row] } = await client.query(
        `WITH inserted AS (
           INSERT INTO maintenance_requests
             (request_no, asset_id, summary, description, urgency, production_stopped, reported_by)
           VALUES ($1, $2, $3, $4, $5, $6, $7)
           RETURNING *
         )
         SELECT ${REQUEST_COLUMNS}
           FROM inserted r
           ${REQUEST_FROM}`,
        [
          numberRow.request_no,
          assetId,
          summary.trim(),
          description ?? null,
          resolvedUrgency,
          resolvedStopped,
          reportedBy ?? null
        ]
      );
      return toRequest(row);
    });
  } catch (error) {
    throw mapRequestWriteError(error);
  }
}

// The triage queue: every Request at a Site still awaiting a decision,
// oldest first so it reads as a queue. Site-wide and carrying no Grant filter
// (ADR-0009): Org Unit scope decides where an Account may act, not what it
// may know about. The route proves the Site exists before this runs.
async function listTriageQueueAtSite(siteId) {
  const { rows } = await getPool().query(
    `SELECT ${REQUEST_COLUMNS}
       FROM maintenance_requests r
       ${REQUEST_FROM}
      WHERE ou.site_id = $1
        AND r.status IN (${OPEN_STATUSES.map((_, i) => `$${i + 2}`).join(', ')})
      ORDER BY r.reported_at ASC, r.id ASC`,
    [siteId, ...OPEN_STATUSES]
  );
  return rows.map(toRequest);
}

// The requester's own Requests at a Site, all statuses, so the person who
// raised one can follow it through to whatever became of it (ADR-0014).
// Site-wide like the queue above; the filter is "raised by me", not a Grant.
// A caller with no linked Employee raised nothing under this identity, so the
// honest answer is an empty list rather than an error.
async function listRequestsForReporterAtSite(siteId, reporterId) {
  if (reporterId === null || reporterId === undefined) return [];
  const { rows } = await getPool().query(
    `SELECT ${REQUEST_COLUMNS}
       FROM maintenance_requests r
       ${REQUEST_FROM}
      WHERE ou.site_id = $1
        AND r.reported_by = $2
      ORDER BY r.reported_at DESC, r.id DESC`,
    [siteId, reporterId]
  );
  return rows.map(toRequest);
}

// The null-returning lookup this Module's own routes use before a write, the
// same shape work-orders.js's findWorkOrder has: total, so a malformed id
// answers null rather than handing Postgres a non-numeric BIGINT and turning
// a 404 into a 500.
async function findRequest(id) {
  if (parseId(id) === null) return null;
  const { rows } = await getPool().query(
    `SELECT ${REQUEST_COLUMNS}
       FROM maintenance_requests r
       ${REQUEST_FROM}
      WHERE r.id = $1`,
    [id]
  );
  return rows[0] ? toRequest(rows[0]) : null;
}

// Locks the Request for the length of the caller's transaction and refuses to
// proceed unless it is still awaiting a decision — the same
// lock-then-check shape work-orders.js's transitions use (and People's own
// approveAccount, per AGENTS.md §6). Two clients racing to triage the same
// Request serialize, and the loser reads the now-current status and gets the
// 409. Reads the Site code through a scalar subquery so the lock stays on the
// request row alone.
async function lockOpenRequest(client, requestId) {
  const { rows: [current] } = await client.query(
    `SELECT r.id, r.status, r.asset_id, r.summary,
            (SELECT s.code
               FROM org_units ou
               JOIN sites s ON s.id = ou.site_id
              WHERE ou.id = r.org_unit_id) AS site_code
       FROM maintenance_requests r
      WHERE r.id = $1
      FOR UPDATE`,
    [requestId]
  );
  if (!current) throw notFound('Request');
  if (!OPEN_STATUSES.includes(current.status)) throw httpError(409, ALREADY_TRIAGED);
  return current;
}

// Accepting: issues a Work order number for the Request's Site, inserts the
// Work order that points back at the Request (ADR-0014), and moves the
// Request to 'accepted' — all in one transaction, so either both records
// change or neither. The `urgency` is deliberately NOT copied onto the work
// order's `priority`: they are different judgements by different people, and
// the gap between them is a signal the schema keeps on purpose. The work
// order carries no `org_unit_id`; its own trigger fills it from the Asset.
async function acceptRequest(requestId, { priority, workType } = {}, accountId, triagedBy) {
  const resolvedPriority = priority === undefined || priority === null ? 3 : priority;
  if (!Number.isInteger(resolvedPriority) || resolvedPriority < 1 || resolvedPriority > 5) {
    throw httpError(400, 'priority must be an integer between 1 and 5');
  }
  const resolvedWorkType = workType === undefined || workType === null ? 'corrective' : workType;
  if (!WORK_TYPES.includes(resolvedWorkType)) {
    throw httpError(400, `workType must be one of: ${WORK_TYPES.join(', ')}`);
  }

  try {
    return await withActor(accountId, async (client) => {
      const current = await lockOpenRequest(client, requestId);

      const { rows: [numberRow] } = await client.query(
        `SELECT next_document_number('WO', $1, EXTRACT(YEAR FROM now())::int) AS work_order_no`,
        [current.site_code]
      );

      const { rows: [workOrderRow] } = await client.query(
        `INSERT INTO work_orders
           (work_order_no, asset_id, maintenance_request_id, summary, work_type, priority, status)
         VALUES ($1, $2, $3, $4, $5, $6, 'approved')
         RETURNING id, work_order_no, status, maintenance_request_id`,
        [
          numberRow.work_order_no,
          current.asset_id,
          requestId,
          current.summary,
          resolvedWorkType,
          resolvedPriority
        ]
      );

      await client.query(
        `UPDATE maintenance_requests
            SET status = 'accepted', triaged_by = $2, triaged_at = now()
          WHERE id = $1`,
        [requestId, triagedBy ?? null]
      );

      const { rows: [row] } = await client.query(
        `SELECT ${REQUEST_COLUMNS}
           FROM maintenance_requests r
           ${REQUEST_FROM}
          WHERE r.id = $1`,
        [requestId]
      );

      return {
        request: toRequest(row),
        workOrder: {
          id: workOrderRow.id,
          workOrderNo: workOrderRow.work_order_no,
          status: workOrderRow.status,
          maintenanceRequestId: workOrderRow.maintenance_request_id
        }
      };
    });
  } catch (error) {
    throw mapRequestWriteError(error);
  }
}

// Declining: requires a reason, because the DB CHECK does
// (`maintenance_requests_rejected_has_reason`) and because "why was my ask
// refused" is a fair question. Same lock-then-check, same one transaction.
async function declineRequest(requestId, { reason } = {}, accountId, triagedBy) {
  requireNonEmptyString('reason', reason);
  try {
    return await withActor(accountId, async (client) => {
      await lockOpenRequest(client, requestId);

      const { rows: [row] } = await client.query(
        `WITH updated AS (
           UPDATE maintenance_requests
              SET status = 'rejected', rejection_reason = $2, triaged_by = $3, triaged_at = now()
            WHERE id = $1
           RETURNING *
         )
         SELECT ${REQUEST_COLUMNS}
           FROM updated r
           ${REQUEST_FROM}`,
        [requestId, reason.trim(), triagedBy ?? null]
      );
      return toRequest(row);
    });
  } catch (error) {
    throw mapRequestWriteError(error);
  }
}

// Marking duplicate: another Request already asked the same thing, and the
// named one is the row that survives. It must exist and be a different row —
// the second is also a DB CHECK (`maintenance_requests_not_own_duplicate`),
// but this answers it with a sentence rather than a raw constraint violation.
// Same lock-then-check, same one transaction.
async function duplicateRequest(requestId, duplicateOfId, accountId, triagedBy) {
  const targetId = parseId(duplicateOfId);
  if (targetId === null) {
    throw httpError(400, 'duplicateOfId must be a valid Request id');
  }
  if (String(targetId) === String(requestId)) {
    throw httpError(400, 'a Request cannot be a duplicate of itself');
  }

  try {
    return await withActor(accountId, async (client) => {
      await lockOpenRequest(client, requestId);

      const { rows: [target] } = await client.query(
        'SELECT id FROM maintenance_requests WHERE id = $1',
        [targetId]
      );
      if (!target) throw notFound('Request');

      const { rows: [row] } = await client.query(
        `WITH updated AS (
           UPDATE maintenance_requests
              SET status = 'duplicate', duplicate_of_id = $2, triaged_by = $3, triaged_at = now()
            WHERE id = $1
           RETURNING *
         )
         SELECT ${REQUEST_COLUMNS}
           FROM updated r
           ${REQUEST_FROM}`,
        [requestId, targetId, triagedBy ?? null]
      );
      return toRequest(row);
    });
  } catch (error) {
    throw mapRequestWriteError(error);
  }
}

module.exports = {
  URGENCIES,
  createRequest,
  listTriageQueueAtSite,
  listRequestsForReporterAtSite,
  findRequest,
  acceptRequest,
  declineRequest,
  duplicateRequest
};
