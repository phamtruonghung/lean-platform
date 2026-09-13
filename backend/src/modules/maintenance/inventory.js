/*
 * Inventory: the shared parts catalogue, the stores that hold parts, and the
 * stock levels derived from movements (issue #80). This implements ADR-0015's
 * decision that a `stores`-sourced parts booking draws from stock, by giving
 * the booking something to draw from.
 *
 * ## Why this lives in Maintenance rather than a Module of its own
 *
 * ADR-0015 left the question open and both shapes were considered. The
 * deciding fact is the write this exists to serve: booking a part against a
 * work order (#75) writes a `work_order_parts` row (Maintenance's record) and
 * a `stock_movements` row (this file's record) as one fact — a shelf that
 * decremented while the cost line vanished, or the reverse, is exactly the
 * disagreement that makes a stock level untrustworthy. ADR-0006's first
 * clause says an entry point never exposes a write: "a second Module changes
 * its own records, never another Module's." So if Inventory were its own
 * Module, neither Maintenance could record the withdrawal nor Inventory the
 * booking line, and the atomic write #75 needs would be impossible without
 * breaking the boundary. Keeping both tables under Maintenance makes the
 * booking one same-Module transaction, the same shape `downtime.js`'s
 * reportBreakdown already has for the stoppage and the Work order it raises.
 * ADR-0006 also makes a Module boundary cheap to move — no data moves with it
 * — so nothing here forecloses extracting Inventory later, once a consumer
 * that does not also write a Maintenance record appears.
 *
 * ## The model
 *
 * `parts` is a shared catalogue in ADR-0005's sense: a part number means the
 * same thing at every Site, and its unit is `units_of_measure` — the same
 * table `work_order_parts.uom_code` references. `stores` belongs to a Site
 * and sits at an Org Unit; it is deliberately not shared. A quantity is never
 * a stored number: `listStockForStore` and `stockOnHand` derive it from
 * `stock_movements`, and `stock_movements_non_negative` (the migration)
 * refuses a movement that would take a pair below zero.
 *
 * Like assets.js, this file is unaware of who is calling: a `storeId` or
 * `orgUnitId` reaching it is one the caller was already entitled to name, and
 * resolving an Org Unit, checking a Grant, and 404ing an unknown Site all
 * happen one layer up in inventory-routes.js.
 */

const { getPool, withActor } = require('../../platform/db');
const { httpError, notFound, parseId } = require('./errors');

const MOVEMENT_TYPES = ['receipt', 'adjustment'];

// Mirrors the CHECK on stock_movements.movement_type, so a bad value is a 400
// this Module wrote rather than a raw constraint violation.
function requireMovementType(value) {
  if (!MOVEMENT_TYPES.includes(value)) {
    throw httpError(400, `movement_type must be one of: ${MOVEMENT_TYPES.join(', ')}`);
  }
}

function requireNonEmptyString(field, value) {
  if (typeof value !== 'string' || value.trim() === '') {
    throw httpError(400, `${field} is required`);
  }
}

function mapInventoryWriteError(error) {
  // `parts_part_no_key` is the UNIQUE on parts.part_no — global, like an
  // Asset's code, because a part number means the same thing at every Site
  // (ADR-0005's shared catalogue).
  if (error.code === '23505' && error.constraint === 'parts_part_no_key') {
    return httpError(409, 'a Part with this part number already exists');
  }
  // `stores_site_code_unique` is UNIQUE (site_id, code) — a store code is
  // Site-local, so the message names the clash the caller can resolve.
  if (error.code === '23505' && error.constraint === 'stores_site_code_unique') {
    return httpError(409, 'a Store with this code already exists at this Site');
  }
  // A foreign key with no more specific meaning left: a Unit of measure, Part
  // or Store that stopped existing between the route's own check and this
  // write. The raw message is never echoed — src/index.js's terminal handler
  // states the policy, and a database string names tables and columns.
  if (error.code === '23503') {
    return httpError(400, 'that references a record that does not exist');
  }
  if (error.code === '23514') {
    return httpError(400, 'that is not a valid Inventory record');
  }
  return error;
}

// ---------------------------------------------------------------------------
// Units of measure — the existing baseline catalogue, read-only here.
// ---------------------------------------------------------------------------

// The picker's own list: a part's unit is chosen, never typed (ADR-0023), and
// it must be one of the same units `work_order_parts.uom_code` already uses.
// Ordered by dimension then name so the list reads the way the seed wrote it.
async function listUnitsOfMeasure() {
  const { rows } = await getPool().query(
    `SELECT code, name, dimension
       FROM units_of_measure
      WHERE is_active
      ORDER BY dimension, name`
  );
  return rows.map((row) => ({ code: row.code, name: row.name, dimension: row.dimension }));
}

// ---------------------------------------------------------------------------
// Parts — the shared catalogue.
// ---------------------------------------------------------------------------

const PART_COLUMNS = `
  p.id, p.part_no, p.description, p.uom_code, p.is_active, p.created_at, p.updated_at
`;

function toPart(row) {
  return {
    id: row.id,
    partNo: row.part_no,
    description: row.description,
    uomCode: row.uom_code,
    isActive: row.is_active,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

// Active-only by default, the same narrowing job-roles.js applies to its own
// catalogue; `includeInactive` is the deliberate way to reach a retired one.
async function listParts({ includeInactive = false } = {}) {
  const { rows } = await getPool().query(
    `SELECT ${PART_COLUMNS}
       FROM parts p
      WHERE ($1 OR p.is_active)
      ORDER BY p.part_no`,
    [includeInactive]
  );
  return rows.map(toPart);
}

// Total, like assets.js's findAsset: a malformed id and an unknown one both
// answer null rather than handing Postgres a non-numeric BIGINT.
async function findPart(id) {
  if (parseId(id) === null) return null;
  const { rows } = await getPool().query(`SELECT ${PART_COLUMNS} FROM parts p WHERE p.id = $1`, [id]);
  return rows[0] ? toPart(rows[0]) : null;
}

// The unit is validated against the existing `units_of_measure` table before
// the INSERT — the catalogue must use the same notion of a unit as
// work_order_parts.uom_code, never a second one — so an unknown or retired
// unit is a clean 404 rather than a raw foreign-key violation.
async function createPart({ partNo, description, uomCode }, accountId) {
  requireNonEmptyString('partNo', partNo);
  requireNonEmptyString('description', description);
  requireNonEmptyString('uomCode', uomCode);

  const { rows: [uom] } = await getPool().query(
    'SELECT code FROM units_of_measure WHERE code = $1 AND is_active',
    [uomCode]
  );
  if (!uom) throw notFound('Unit of measure');

  try {
    return await withActor(accountId, async (client) => {
      const { rows: [row] } = await client.query(
        `INSERT INTO parts (part_no, description, uom_code)
         VALUES ($1, $2, $3)
         RETURNING *`,
        [partNo.trim(), description.trim(), uomCode]
      );
      return toPart(row);
    });
  } catch (error) {
    throw mapInventoryWriteError(error);
  }
}

// ---------------------------------------------------------------------------
// Stores — one Site's shelf, at an Org Unit.
// ---------------------------------------------------------------------------

// org_unit_code/org_unit_name/site_id come from the join, so every store this
// file hands back carries where it sits.
const STORE_COLUMNS = `
  s.id, s.site_id, s.org_unit_id, s.code, s.name, s.is_active,
  s.created_at, s.updated_at,
  ou.code AS org_unit_code, ou.name AS org_unit_name
`;

function toStore(row) {
  return {
    id: row.id,
    siteId: row.site_id,
    orgUnitId: row.org_unit_id,
    orgUnitCode: row.org_unit_code,
    orgUnitName: row.org_unit_name,
    code: row.code,
    name: row.name,
    isActive: row.is_active,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

// Site-wide, never filtered by the caller's Grants (ADR-0009's reasoning
// extended to Inventory): scope decides where an Account may act, not what it
// may know about. Active stores only by default; a retired one is reached by
// naming it, never mixed silently into the default list.
async function listStoresAtSite(siteId, { includeInactive = false } = {}) {
  const { rows } = await getPool().query(
    `SELECT ${STORE_COLUMNS}
       FROM stores s
       JOIN org_units ou ON ou.id = s.org_unit_id
      WHERE s.site_id = $1 AND ($2 OR s.is_active)
      ORDER BY ou.name, s.code`,
    [siteId, includeInactive]
  );
  return rows.map(toStore);
}

async function findStore(id) {
  if (parseId(id) === null) return null;
  const { rows } = await getPool().query(
    `SELECT ${STORE_COLUMNS}
       FROM stores s
       JOIN org_units ou ON ou.id = s.org_unit_id
      WHERE s.id = $1`,
    [id]
  );
  return rows[0] ? toStore(rows[0]) : null;
}

// `siteId` is handed in by the route from the Org Unit it already resolved:
// the store's Site is its Org Unit's Site, and the migration's own
// stores_check_org_unit_site trigger refuses the two columns disagreeing.
async function createStore({ siteId, orgUnitId, code, name }, accountId) {
  requireNonEmptyString('code', code);
  requireNonEmptyString('name', name);

  try {
    return await withActor(accountId, async (client) => {
      const { rows: [row] } = await client.query(
        `WITH inserted AS (
           INSERT INTO stores (site_id, org_unit_id, code, name)
           VALUES ($1, $2, $3, $4)
           RETURNING *
         )
         SELECT ${STORE_COLUMNS}
           FROM inserted s
           JOIN org_units ou ON ou.id = s.org_unit_id`,
        [siteId, orgUnitId, code.trim(), name.trim()]
      );
      return toStore(row);
    });
  } catch (error) {
    throw mapInventoryWriteError(error);
  }
}

// ---------------------------------------------------------------------------
// Stock — always derived, never stored.
// ---------------------------------------------------------------------------

function toStockLevel(row) {
  return {
    partId: row.part_id,
    partNo: row.part_no,
    description: row.description,
    uomCode: row.uom_code,
    // node-postgres hands NUMERIC back as a string (a JS double cannot hold
    // every NUMERIC(18,4)); a stock quantity is converted to a number here so
    // the wire carries one.
    quantity: Number(row.quantity)
  };
}

// Every part with at least one movement in this store, with its derived
// level. A part that has never moved is not stock held here, so it is not
// listed — the receive dialog offers the whole catalogue separately.
async function listStockForStore(storeId) {
  const { rows } = await getPool().query(
    `SELECT p.id AS part_id, p.part_no, p.description, p.uom_code,
            SUM(m.quantity) AS quantity
       FROM stock_movements m
       JOIN parts p ON p.id = m.part_id
      WHERE m.store_id = $1
      GROUP BY p.id, p.part_no, p.description, p.uom_code
      ORDER BY p.part_no`,
    [storeId]
  );
  return rows.map(toStockLevel);
}

// The derived level of one part in one store, as a number, read after the
// failing transaction has rolled back when the refusal is built.
async function stockOnHand(storeId, partId) {
  const { rows: [row] } = await getPool().query(
    `SELECT COALESCE(SUM(quantity), 0) AS on_hand
       FROM stock_movements
      WHERE store_id = $1 AND part_id = $2`,
    [storeId, partId]
  );
  return Number(row.on_hand);
}

const MOVEMENT_COLUMNS = `
  m.id, m.part_id, m.store_id, m.quantity, m.movement_type, m.reason,
  m.occurred_at, m.created_at, m.created_by,
  p.part_no, p.description, p.uom_code
`;

const MOVEMENT_FROM = 'JOIN parts p ON p.id = m.part_id';

function toMovement(row) {
  return {
    id: row.id,
    partId: row.part_id,
    partNo: row.part_no,
    description: row.description,
    uomCode: row.uom_code,
    storeId: row.store_id,
    quantity: Number(row.quantity),
    movementType: row.movement_type,
    reason: row.reason,
    occurredAt: row.occurred_at,
    createdAt: row.created_at
  };
}

// Newest first, because the most recent movement is the one somebody is
// chasing; the tie-break on id keeps a batch written in one instant stable.
async function listMovementsForStore(storeId) {
  const { rows } = await getPool().query(
    `SELECT ${MOVEMENT_COLUMNS}
       FROM stock_movements m
       ${MOVEMENT_FROM}
      WHERE m.store_id = $1
      ORDER BY m.occurred_at DESC, m.id DESC`,
    [storeId]
  );
  return rows.map(toMovement);
}

// The refusal, built after the failing transaction has rolled back — the same
// shape downtime.js's assetAlreadyDown uses. It names the part and what is
// actually on the shelf, because "below zero" alone tells a storekeeper
// nothing they can act on.
async function insufficientStock(partId, storeId) {
  const part = await findPart(partId);
  const onHand = await stockOnHand(storeId, partId);
  const partNo = part?.partNo ?? 'that Part';
  const uom = part?.uomCode ?? '';
  return httpError(
    409,
    `Part ${partNo} has only ${onHand} ${uom} on the shelf; this movement would take it below zero.`
  );
}

// The one INSERT both a receipt and an adjustment go through. The
// non-negative guard is the migration's own BEFORE INSERT trigger, which
// takes a per-(store, part) advisory lock before summing — so two concurrent
// withdrawals cannot each pass a balance the other has not committed. When it
// refuses, the raised 23514 arrives here after withActor's ROLLBACK, and is
// turned into the part-naming sentence above rather than leaked as a raw
// database error.
async function insertMovement({ storeId, partId, quantity, movementType, reason, occurredAt }, accountId) {
  requireMovementType(movementType);
  try {
    return await withActor(accountId, async (client) => {
      const { rows: [row] } = await client.query(
        `WITH inserted AS (
           INSERT INTO stock_movements
             (part_id, store_id, quantity, movement_type, reason, occurred_at, created_by)
           VALUES ($1, $2, $3, $4, $5, COALESCE($6::timestamptz, now()),
                   NULLIF(current_setting('app.user_id', true), '')::BIGINT)
           RETURNING *
         )
         SELECT ${MOVEMENT_COLUMNS}
           FROM inserted m
           ${MOVEMENT_FROM}`,
        [partId, storeId, quantity, movementType, reason, occurredAt ?? null]
      );

      // Derived inside the same transaction, so the level returned is the one
      // this movement actually produced.
      const { rows: [balance] } = await client.query(
        `SELECT COALESCE(SUM(quantity), 0) AS on_hand
           FROM stock_movements
          WHERE store_id = $1 AND part_id = $2`,
        [storeId, partId]
      );

      return { movement: toMovement(row), onHand: Number(balance.on_hand) };
    });
  } catch (error) {
    if (error.code === '23514') {
      throw await insufficientStock(partId, storeId);
    }
    throw mapInventoryWriteError(error);
  }
}

// Receive stock: a positive movement. `reason` is optional — "received" is
// the honest default when nobody wrote a line about it.
async function receiveStock(storeId, { partId, quantity, reason, occurredAt }, accountId) {
  const part = await findPart(partId);
  if (!part) throw notFound('Part');

  const amount = Number(quantity);
  if (!Number.isFinite(amount) || amount <= 0) {
    throw httpError(400, 'quantity must be greater than zero');
  }
  const trimmedReason = typeof reason === 'string' && reason.trim() !== '' ? reason.trim() : 'received';

  return insertMovement(
    { storeId, partId: part.id, quantity: amount, movementType: 'receipt', reason: trimmedReason, occurredAt },
    accountId
  );
}

// Adjust stock: a count disagreed with the record, so record the difference.
// A signed, non-zero delta and a reason are both required — an adjustment
// takes stock up as readily as down, and "why" is the whole point of
// recording one rather than silently overwriting a number.
async function adjustStock(storeId, { partId, quantityDelta, reason, occurredAt }, accountId) {
  const part = await findPart(partId);
  if (!part) throw notFound('Part');

  const delta = Number(quantityDelta);
  if (!Number.isFinite(delta) || delta === 0) {
    throw httpError(400, 'quantityDelta must be a non-zero number');
  }
  requireNonEmptyString('reason', reason);

  return insertMovement(
    { storeId, partId: part.id, quantity: delta, movementType: 'adjustment', reason: reason.trim(), occurredAt },
    accountId
  );
}

module.exports = {
  MOVEMENT_TYPES,
  listUnitsOfMeasure,
  listParts,
  findPart,
  createPart,
  listStoresAtSite,
  findStore,
  createStore,
  listStockForStore,
  stockOnHand,
  listMovementsForStore,
  receiveStock,
  adjustStock
};
