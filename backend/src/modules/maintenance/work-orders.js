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
const { httpError, notFound } = require('./errors');

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

module.exports = {
  WORK_TYPES,
  createWorkOrder,
  listOpenWorkOrdersAtSite
};
