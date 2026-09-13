/*
 * Breakdowns and downtime (issue #73), the fourth table this Module owns after
 * Assets (#56), Work orders (#57) and Requests (#72). Same shape as
 * work-orders.js and requests.js, and the same rule holds: this file never
 * requires '../people' and never resolves or writes a People record.
 * Resolving the Asset a caller named, and asking whether they may act at its
 * Org Unit, both happen one layer up in downtime-routes.js through
 * modules/people's entry point.
 *
 * Cross-Module reads are ordinary joins here, exactly as assets.js,
 * work-orders.js and requests.js already do (ADR-0006): `assets`, `org_units`
 * and `sites` to derive the stop's placement and number, `employees` to
 * resolve `reported_by` to a name, and `downtime_reasons` for the classify
 * picker's own fields. The only table this file writes besides its own
 * `downtime_events` is `work_orders` — the same cross-domain, same-Module
 * write requests.js's acceptRequest already makes, because a Breakdown
 * produces both records together (CONTEXT.md's Breakdown) and a Module is a
 * code seam, not a data seam.
 *
 * Three things this file deliberately does NOT do, because the database
 * already does them:
 *
 *   - Fill `org_unit_id`. `downtime_events_fill_org` (baseline migration) runs
 *     BEFORE INSERT and copies it from the named Asset, the same shape the
 *     work order and maintenance request triggers use. A caller's
 *     `orgUnitId`, if one is even sent, is ignored.
 *   - Issue the Work order number. `next_document_number('WO', siteCode,
 *     year)` is the Site's own sequence, keyed on `prefix-siteCode-year`, so
 *     two Sites number independently for free.
 *   - Decide `status` and `duration_minutes`. Both are GENERATED columns on
 *     `downtime_events`; `status` is 'open' while `ended_at` is null,
 *     'unclassified' once closed with no reason, and 'closed' otherwise.
 *
 * CONTEXT.md's own distinction is load-bearing throughout: a Breakdown is a
 * machine stopping unplanned, so it bypasses the request-and-decline path and
 * produces a downtime record and the corrective work order that fixes it
 * together, in one transaction. The downtime's own duration and the work
 * order's own duration are different facts (Downtime's `_Avoid_` note), so
 * neither is ever derived from the other here.
 */

const { getPool, withActor } = require('../../platform/db');
const { httpError, notFound, parseId } = require('./errors');

// asset_code/asset_name/org_unit_name/reporter_name/reason_name all come from
// joins, so every downtime event this Module hands back carries enough for a
// list row without a second round trip. Mirrors WORK_ORDER_COLUMNS/toWorkOrder
// and REQUEST_COLUMNS/toRequest's own shape.
const DOWNTIME_COLUMNS = `
  de.id, de.asset_id, de.org_unit_id, de.started_at, de.ended_at,
  de.duration_minutes, de.status, de.downtime_reason_id, de.description,
  de.reported_by, de.classified_by, de.classified_at, de.source,
  a.code AS asset_code, a.name AS asset_name,
  ou.name AS org_unit_name,
  e.display_name AS reporter_name,
  dr.name AS downtime_reason_name
`;

// The join chain DOWNTIME_COLUMNS depends on, factored out because every
// function below attaches it after its own FROM clause — whether that FROM
// names the bare `downtime_events` table or a CTE (`inserted`/`updated`) built
// off it, `de` is always the alias the join chain expects. `employees` and
// `downtime_reasons` are LEFT joins: an Account need not name an Employee
// (reported_by is nullable) and a stop exists before anybody classifies it
// (downtime_reason_id is nullable — see the baseline's own comment).
const DOWNTIME_FROM = `
  JOIN assets a ON a.id = de.asset_id
  JOIN org_units ou ON ou.id = de.org_unit_id
  LEFT JOIN employees e ON e.id = de.reported_by
  LEFT JOIN downtime_reasons dr ON dr.id = de.downtime_reason_id
`;

function toDowntimeEvent(row) {
  return {
    id: row.id,
    assetId: row.asset_id,
    assetCode: row.asset_code,
    assetName: row.asset_name,
    orgUnitId: row.org_unit_id,
    orgUnitName: row.org_unit_name,
    startedAt: row.started_at,
    endedAt: row.ended_at,
    // GENERATED NUMERIC(12,2). node-postgres hands NUMERIC back as a string
    // (it cannot hold every NUMERIC(18,4) in a JS double); a duration that
    // fits comfortably in 12,2 is converted to a number here so the wire
    // carries one, the same choice skills.js's headcount figures make. Null
    // while the stop is open, because the generated expression is.
    durationMinutes: row.duration_minutes === null ? null : Number(row.duration_minutes),
    status: row.status,
    downtimeReasonId: row.downtime_reason_id,
    downtimeReasonName: row.downtime_reason_name ?? null,
    description: row.description,
    reportedBy: row.reported_by,
    reporterName: row.reporter_name ?? null,
    classifiedAt: row.classified_at,
    source: row.source
  };
}

// A backstop, not the primary defence — downtime-routes.js already 404s an
// unknown Asset before a write ever reaches here. This maps the triggers'
// own errors if an Asset vanished between that check and this INSERT. The raw
// database message is NOT echoed: it names tables and columns.
function mapDowntimeWriteError(error) {
  if (error.code === '23503') {
    return notFound('Asset');
  }
  if (error.code === '23514') {
    return httpError(400, 'that is not a valid Downtime event');
  }
  return error;
}

// The Asset's own name (for the work order summary) and the Site's code (for
// the Work order number), in one read. Mirrors findSiteCodeForAsset in
// work-orders.js/requests.js, widened by the one extra column this domain
// needs.
async function findAssetContext(assetId) {
  const { rows } = await getPool().query(
    `SELECT a.name, s.code AS site_code
       FROM assets a
       JOIN org_units ou ON ou.id = a.org_unit_id
       JOIN sites s ON s.id = ou.site_id
      WHERE a.id = $1`,
    [assetId]
  );
  return rows[0] ?? null;
}

// The classify picker's own catalogue: every active reason, ordered by
// sort_order then name so the tree reads the way the seed wrote it. Readable
// by any approved Account — this is a shared global catalogue (ADR-0005), not
// an Org-Unit-scoped record.
async function listDowntimeReasons() {
  const { rows } = await getPool().query(
    `SELECT id, code, name, loss_category, is_planned, requires_comment
       FROM downtime_reasons
      WHERE is_active
      ORDER BY sort_order, name`
  );
  return rows.map((row) => ({
    id: row.id,
    code: row.code,
    name: row.name,
    lossCategory: row.loss_category,
    isPlanned: row.is_planned,
    requiresComment: row.requires_comment
  }));
}

// Site-wide, open stops by default (issue #73) — the same Site-wide-read rule
// listAssetsAtSite/listWorkOrdersAtSite follow (#55/ADR-0009): scope decides
// where an Account may act, not what it may know about, so this carries no
// Grant filter. `includeClosed` is the deliberate way to widen to the history
// of every stop; without it a closed stop is out, never mixed silently into
// the "what is down right now" list. Newest first, because the most recent
// stop is the one somebody is chasing.
async function listDowntimeAtSite(siteId, { includeClosed = false } = {}) {
  const openClause = includeClosed ? '' : 'AND de.ended_at IS NULL';
  const { rows } = await getPool().query(
    `SELECT ${DOWNTIME_COLUMNS}
       FROM downtime_events de
       ${DOWNTIME_FROM}
      WHERE ou.site_id = $1
        ${openClause}
      ORDER BY de.started_at DESC, de.id DESC`,
    [siteId]
  );
  return rows.map(toDowntimeEvent);
}

// The null-returning lookup this Module's own routes use before a write, the
// same shape work-orders.js's findWorkOrder has: total, so a malformed id
// answers null rather than handing Postgres a non-numeric BIGINT and turning
// a 404 into a 500.
async function findDowntimeEvent(id) {
  if (parseId(id) === null) return null;
  const { rows } = await getPool().query(
    `SELECT ${DOWNTIME_COLUMNS}
       FROM downtime_events de
       ${DOWNTIME_FROM}
      WHERE de.id = $1`,
    [id]
  );
  return rows[0] ? toDowntimeEvent(rows[0]) : null;
}

// The actionable refusal a duplicate report gets, built after the losing
// transaction has already rolled back. `downtime_events_no_overlap` treats an
// open stop as running to infinity, so when Postgres refuses the second
// INSERT it is always because this Asset already has an open row; the row is
// looked up rather than guessed so the message names the real start. The
// `ASSET_ALREADY_DOWN` code is what lets the client offer "close that stop"
// rather than parse the sentence.
async function assetAlreadyDown(assetId, assetName) {
  const { rows } = await getPool().query(
    `SELECT started_at
       FROM downtime_events
      WHERE asset_id = $1 AND ended_at IS NULL
      ORDER BY started_at DESC
      LIMIT 1`,
    [assetId]
  );
  const since = rows[0]?.started_at;
  const message = since
    ? `${assetName} is already recorded as down since ${since.toISOString()}. Close that stop before reporting another.`
    : `${assetName} is already recorded as down. Close that stop before reporting another.`;
  return httpError(409, message, 'ASSET_ALREADY_DOWN');
}

// Report a Breakdown: two records, one transaction (CONTEXT.md's Breakdown —
// the stoppage and the job that fixes it are one fact, and recording half of
// it is worse than recording none).
//
// `org_unit_id` is never read off `attrs`: `downtime_events_fill_org` fills
// it from `asset_id`, and the database decides it. `reported_by` is the
// caller's linked Employee id, or null when the Account names no Employee —
// decided by the route (which owns the Account) and passed in, exactly as
// requests.js's createRequest does.
//
// The work order is always `corrective`, `approved` and `is_breakdown = TRUE`
// (the baseline's `work_orders_breakdown_is_corrective` CHECK requires the
// first of those, and `v_asset_reliability` counts the third). Its summary is
// derived from the Asset; `description`, when the reporter gave one, seeds the
// work order's own description too. Its `actual_start`/`actual_end` are
// deliberately left null: the work order's own duration is a different fact
// from the stoppage's, and nothing here derives one from the other.
//
// Ordering inside the transaction is deliberate. `downtime_events_no_overlap`
// is the arbiter of two people reporting the same stoppage, and it fires only
// on the downtime INSERT. That INSERT is deliberately the LAST write: by then
// the Work order is already on the books, so the constraint violation aborts a
// transaction that has really written something and the ROLLBACK undoes a real
// row — "both rows or neither" is proven by the database, not asserted by this
// code. A consumed-but-rolled-back Work order number would be an acceptable
// gap, the same as any rollback; `next_document_number` is a table write, so
// it is rolled back with everything else.
async function reportBreakdown({ assetId, startedAt, description, reportedBy }, accountId) {
  const context = await findAssetContext(assetId);
  if (!context) throw notFound('Asset');

  try {
    return await withActor(accountId, async (client) => {
      const { rows: [numberRow] } = await client.query(
        `SELECT next_document_number('WO', $1, EXTRACT(YEAR FROM now())::int) AS work_order_no`,
        [context.site_code]
      );

      // The Work order first — see this function's own header for why the
      // order is load-bearing, not incidental.
      const { rows: [insertedWorkOrder] } = await client.query(
        `INSERT INTO work_orders
           (work_order_no, asset_id, summary, description, work_type, is_breakdown, status)
         VALUES ($1, $2, $3, $4, 'corrective', TRUE, 'approved')
         RETURNING id, work_order_no`,
        [numberRow.work_order_no, assetId, `Breakdown: ${context.name}`, description ?? null]
      );

      // The stop second, so the exclusion constraint can refuse it. A
      // duplicate report throws SQLSTATE 23P01 here and rolls the Work order
      // above (and the number) back with it.
      const { rows: [downtimeRow] } = await client.query(
        `WITH inserted AS (
           INSERT INTO downtime_events
             (asset_id, started_at, description, reported_by, source)
           VALUES ($1, COALESCE($2::timestamptz, now()), $3, $4, 'manual')
           RETURNING *
         )
         SELECT ${DOWNTIME_COLUMNS}
           FROM inserted de
           ${DOWNTIME_FROM}`,
        [assetId, startedAt ?? null, description ?? null, reportedBy ?? null]
      );

      // The link back from the job to the stop it cleared (the baseline's
      // `work_orders.downtime_event_id`), set only now that the row it points
      // at exists. This is what `v_asset_reliability` joins to compute
      // response time.
      const { rows: [workOrderRow] } = await client.query(
        `UPDATE work_orders
            SET downtime_event_id = $1
          WHERE id = $2
          RETURNING id, work_order_no, asset_id, org_unit_id, summary, description,
                    work_type, priority, status, downtime_event_id`,
        [downtimeRow.id, insertedWorkOrder.id]
      );

      return {
        downtimeEvent: toDowntimeEvent(downtimeRow),
        // A reduced Work order row, the same choice requests.js's
        // acceptRequest makes: the canonical full listing shape belongs to
        // work-orders.js, and the caller has the id and number it needs to
        // follow the job there.
        workOrder: {
          id: workOrderRow.id,
          workOrderNo: workOrderRow.work_order_no,
          assetId: workOrderRow.asset_id,
          orgUnitId: workOrderRow.org_unit_id,
          summary: workOrderRow.summary,
          description: workOrderRow.description,
          workType: workOrderRow.work_type,
          priority: workOrderRow.priority,
          status: workOrderRow.status,
          downtimeEventId: workOrderRow.downtime_event_id
        }
      };
    });
  } catch (error) {
    // `23P01` is exclusion_violation: `downtime_events_no_overlap` refused
    // the second open stop on this Asset. Mapped here, inside the service,
    // so the route never sees a raw constraint name and the caller gets a
    // sentence naming the Asset and when it went down.
    if (error.code === '23P01') {
      throw await assetAlreadyDown(assetId, context.name);
    }
    throw mapDowntimeWriteError(error);
  }
}

// Close a stop: stamp `ended_at`, which makes the generated columns resolve —
// `duration_minutes` springs from the pair and `status` becomes 'closed' (or
// 'unclassified' if nobody classified it). `endedAt` is optional; now() is the
// honest default when the caller is closing a stop as it ends. Nothing here
// touches the Work order: the job finishing and the machine running again are
// independent facts (CONTEXT.md's Downtime).
//
// Lock-then-check over the row, the same shape work-orders.js's transitions
// use: two clients racing to close the same stop serialize, and the loser
// reads the now-current `ended_at` and gets the 409.
async function closeDowntimeEvent(id, { endedAt } = {}, accountId) {
  try {
    return await withActor(accountId, async (client) => {
      const { rows: [current] } = await client.query(
        'SELECT id, ended_at FROM downtime_events WHERE id = $1 FOR UPDATE',
        [id]
      );
      // Unreachable in ordinary use — the route already proved the stop
      // exists — but handled anyway for the same reason work-orders.js
      // handles its own unreachable cases: a concurrent delete is not this
      // Module's business to surface as a 500.
      if (!current) throw notFound('Downtime event');
      if (current.ended_at !== null) {
        throw httpError(409, 'this Downtime event has already been closed');
      }

      const { rows: [row] } = await client.query(
        `WITH updated AS (
           UPDATE downtime_events
              SET ended_at = COALESCE($2::timestamptz, now())
            WHERE id = $1
           RETURNING *
         )
         SELECT ${DOWNTIME_COLUMNS}
           FROM updated de
           ${DOWNTIME_FROM}`,
        [id, endedAt ?? null]
      );
      return toDowntimeEvent(row);
    });
  } catch (error) {
    throw mapDowntimeWriteError(error);
  }
}

// Classify a stop against the reason tree. A stop may be classified by
// somebody other than whoever reported it — triage is maintenance's own act,
// and the route only requires a write Grant reaching the stop's Org Unit, so
// `classifiedBy` is a separate Employee link from `reportedBy`. That is why
// `classified_at` exists as its own fact rather than being folded into
// `reported_by`.
//
// The reason is resolved (existence) before the transaction opens: an unknown
// one is a 404 naming `Downtime reason`, never a raw foreign-key violation. A
// reason with `requires_comment` forces a free-text note — the baseline's
// comment says why ("so 'Other — 340 minutes' at the top of the Pareto is at
// least investigable") — and a blank or missing description is a 400 rather
// than a silent empty string. When the reason does not require one and none
// was given, the existing description (if any) is left alone.
async function classifyDowntimeEvent(id, { downtimeReasonId, description } = {}, accountId, classifiedBy) {
  const reasonId = parseId(downtimeReasonId);
  if (reasonId === null) throw notFound('Downtime reason');

  const { rows: [reason] } = await getPool().query(
    'SELECT id, requires_comment FROM downtime_reasons WHERE id = $1',
    [reasonId]
  );
  if (!reason) throw notFound('Downtime reason');

  const trimmedDescription = typeof description === 'string' ? description.trim() : '';
  if (reason.requires_comment && trimmedDescription === '') {
    throw httpError(400, 'a description is required for this downtime reason');
  }

  try {
    return await withActor(accountId, async (client) => {
      const { rows: [current] } = await client.query(
        'SELECT id FROM downtime_events WHERE id = $1 FOR UPDATE',
        [id]
      );
      if (!current) throw notFound('Downtime event');

      const { rows: [row] } = await client.query(
        `WITH updated AS (
           UPDATE downtime_events
              SET downtime_reason_id = $2,
                  classified_by = $3,
                  classified_at = now(),
                  description = COALESCE($4, description)
            WHERE id = $1
           RETURNING *
         )
         SELECT ${DOWNTIME_COLUMNS}
           FROM updated de
           ${DOWNTIME_FROM}`,
        [id, reasonId, classifiedBy ?? null, trimmedDescription === '' ? null : trimmedDescription]
      );
      return toDowntimeEvent(row);
    });
  } catch (error) {
    throw mapDowntimeWriteError(error);
  }
}

module.exports = {
  listDowntimeReasons,
  listDowntimeAtSite,
  findDowntimeEvent,
  reportBreakdown,
  closeDowntimeEvent,
  classifyDowntimeEvent
};
