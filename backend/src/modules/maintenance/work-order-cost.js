/*
 * What a job cost: the hours booked against a work order and the parts fitted
 * to it (issue #75), consuming the baseline's `work_order_labour` and
 * `work_order_parts`. No schema change: both tables already exist, and this
 * file gives them their first write surface and their first read.
 *
 * The schema's own warning above `work_order_labour` is the load-bearing rule
 * here. `v_labour_cost` already costs every hour worked, from
 * `attendance_records`, a maintenance technician's shift included, so the
 * hours booked here are NOT new cost — they are the same money attributed to
 * a job, a SLICE of COST_LABOUR. Parts are the opposite: nothing upstream
 * costs a part, so a parts line is genuinely new money and the one component
 * of maintenance cost that adds. Nothing this file returns ever sums the two
 * into a single "total cost": it returns labour HOURS and a parts COST, and
 * the route hands them back separately so the reader can tell which is which.
 *
 * Two more facts are the database's, not this file's:
 *
 *   - `work_order_labour.hours` is a STORED GENERATED column, computed from
 *     `started_at`/`ended_at`. It is never written here and never read off a
 *     caller — `bookLabour` simply does not name it, so a client that sends
 *     one is ignored and the window is the only input.
 *   - `sourced` decides whether stock moves. Only `stores` draws down
 *     inventory, per ADR-0015; a `purchased`, `refurbished` or `cannibalised`
 *     booking touched no shelf and must not record a movement that never
 *     happened.
 *
 * Like the rest of this Module's domain files, this file never requires
 * '../people': resolving the Employee a caller named, and asking whether they
 * may act at the work order's Asset's Org Unit, both happen one layer up in
 * work-order-routes.js. It does require './inventory' — the same Module, so
 * the Module boundary is not in play — because a `stores` booking and its
 * withdrawal must be ONE transaction, and inventory.js owns the movement and
 * its non-negative refusal.
 */

const { getPool, withActor } = require('../../platform/db');
const { httpError, notFound, parseId } = require('./errors');
const inventory = require('./inventory');

// Mirrors the CHECK on work_order_labour.activity. All five are offered by
// the booking form; nothing defaults everything to 'work'. The schema's own
// comment is why the distinction is worth keeping: "a plant whose technicians
// spend a third of the job waiting for a permit has a scheduling problem, not
// a staffing one."
const LABOUR_ACTIVITIES = ['work', 'travel', 'waiting', 'diagnosis', 'documentation'];

// Mirrors the CHECK on work_order_parts.sourced.
const PART_SOURCES = ['stores', 'purchased', 'refurbished', 'cannibalised'];

const LABOUR_COLUMNS = `
  l.id, l.work_order_id, l.employee_id, l.org_unit_id, l.started_at, l.ended_at,
  l.hours, l.is_overtime, l.activity, l.note, l.created_at,
  e.display_name AS employee_name
`;

const LABOUR_FROM = 'JOIN employees e ON e.id = l.employee_id';

function toLabour(row) {
  return {
    id: row.id,
    workOrderId: row.work_order_id,
    employeeId: row.employee_id,
    employeeName: row.employee_name,
    orgUnitId: row.org_unit_id,
    startedAt: row.started_at,
    endedAt: row.ended_at,
    // GENERATED NUMERIC(18,4). node-postgres hands NUMERIC back as a string
    // (a JS double cannot hold every NUMERIC(18,4)); an hours figure is
    // converted to a number here so the wire carries one, the same choice
    // downtime.js's durationMinutes makes. Null while the window is open,
    // because the generated expression is.
    hours: row.hours === null ? null : Number(row.hours),
    isOvertime: row.is_overtime,
    activity: row.activity,
    note: row.note
  };
}

const PART_COLUMNS = `
  wp.id, wp.work_order_id, wp.part_no, wp.description, wp.quantity, wp.uom_code,
  wp.unit_cost, wp.currency, wp.total_cost, wp.sourced, wp.fitted_at
`;

function toBookedPart(row) {
  return {
    id: row.id,
    workOrderId: row.work_order_id,
    partNo: row.part_no,
    description: row.description,
    quantity: Number(row.quantity),
    uomCode: row.uom_code,
    unitCost: row.unit_cost === null ? null : Number(row.unit_cost),
    currency: row.currency,
    totalCost: row.total_cost === null ? null : Number(row.total_cost),
    sourced: row.sourced,
    fittedAt: row.fitted_at
  };
}

// A backstop, not the primary defence: the route already 404s an unknown Work
// order, Part, Store, Employee or Unit of measure before a write reaches
// here. What is left for this mapping is a foreign key that stopped existing
// between the route's check and this write, and a CHECK a value this file
// did not anticipate tripped. The raw database message is never echoed — it
// names tables and columns, and src/index.js's terminal handler states that
// policy.
function mapBookingWriteError(error) {
  if (error.code === '23503') {
    return httpError(400, 'that references a record that does not exist');
  }
  if (error.code === '23514') {
    return httpError(400, 'that is not a valid booking');
  }
  return error;
}

// `startedAt`/`endedAt` arrive as whatever a client serialized. A timestamp
// the database would reject should be this Module's 400, not a raw
// `invalid input syntax` echoed from Postgres.
function parseTimestamp(field, value) {
  if (typeof value !== 'string' || value.trim() === '') {
    throw httpError(400, `${field} is required`);
  }
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) {
    throw httpError(400, `${field} must be a valid timestamp`);
  }
  return parsed.toISOString();
}

function normaliseUnitCost(value) {
  if (value === undefined || value === null || value === '') return null;
  const amount = Number(value);
  if (!Number.isFinite(amount) || amount < 0) {
    throw httpError(400, 'unitCost must be a number greater than or equal to zero');
  }
  return amount;
}

function normaliseCurrency(value) {
  if (value === undefined || value === null || value === '') return 'USD';
  const currency = String(value).trim().toUpperCase();
  if (currency.length !== 3) {
    throw httpError(400, 'currency must be a three-letter code');
  }
  return currency;
}

function normaliseQuantity(value) {
  const quantity = Number(value);
  if (!Number.isFinite(quantity) || quantity <= 0) {
    throw httpError(400, 'quantity must be greater than zero');
  }
  return quantity;
}

function normaliseFittedAt(value) {
  if (value === undefined || value === null || value === '') return null;
  return parseTimestamp('fittedAt', value);
}

// The refusal an overlapping booking gets, built after the losing transaction
// has rolled back — the same shape downtime.js's assetAlreadyDown and
// inventory.js's insufficientStock use. `work_order_labour_no_overlap` is the
// schema's guard against booking the same technician on two jobs at once, and
// it fires as a 23P01; naming the Employee and the window is what makes it
// actionable rather than a raw constraint name.
async function labourOverlaps(employeeId, startedAt, endedAt) {
  const { rows } = await getPool().query('SELECT display_name FROM employees WHERE id = $1', [
    employeeId
  ]);
  const name = rows[0]?.display_name ?? 'This Employee';
  return httpError(
    409,
    `${name} already has labour booked that overlaps ${startedAt} to ${endedAt}.`,
    'LABOUR_OVERLAP'
  );
}

// Book an Employee's window of time against a work order (issue #75). The
// window is the only input that decides the hours: `hours` is never read off
// `attrs` even if a caller sent one, so the stored generated column and the
// client can never disagree. overtime is its own flag rather than a second
// booking kind, so `is_overtime` distinguishes it from ordinary hours without
// splitting the window.
//
// `org_unit_id` and `shift_instance_id` are likewise never read here:
// `work_order_labour_fill_org` copies the former from the work order and
// `attach_shift_instance('work_order_labour', 'started_at')` derives the
// latter from the window, both BEFORE INSERT.
async function bookLabour(
  workOrderId,
  { employeeId, startedAt, endedAt, activity, isOvertime = false, note } = {},
  accountId
) {
  if (!LABOUR_ACTIVITIES.includes(activity)) {
    throw httpError(400, `activity must be one of: ${LABOUR_ACTIVITIES.join(', ')}`);
  }
  const start = parseTimestamp('startedAt', startedAt);
  const end = parseTimestamp('endedAt', endedAt);
  if (new Date(end) < new Date(start)) {
    throw httpError(400, 'endedAt must not be before startedAt');
  }
  if (typeof isOvertime !== 'boolean') {
    throw httpError(400, 'isOvertime must be a boolean');
  }

  try {
    return await withActor(accountId, async (client) => {
      const { rows: [row] } = await client.query(
        `WITH inserted AS (
           INSERT INTO work_order_labour
             (work_order_id, employee_id, started_at, ended_at, is_overtime, activity, note)
           VALUES ($1, $2, $3, $4, $5, $6, $7)
           RETURNING *
         )
         SELECT ${LABOUR_COLUMNS}
           FROM inserted l
           ${LABOUR_FROM}`,
        [workOrderId, employeeId, start, end, isOvertime, activity, note ?? null]
      );
      return toLabour(row);
    });
  } catch (error) {
    if (error.code === '23P01') {
      throw await labourOverlaps(employeeId, start, end);
    }
    throw mapBookingWriteError(error);
  }
}

// The one INSERT both a catalogue and a free-text booking go through.
// `part_no` is free text on purpose (the schema's own comment: demanding a
// part number the technician does not have means the line is left blank and
// the cost is lost), so a booking from stores names the catalogue's own part
// number and a purchased one may carry none at all.
async function insertBookingPart(client, workOrderId, fields) {
  const { rows: [row] } = await client.query(
    `WITH inserted AS (
       INSERT INTO work_order_parts
         (work_order_id, part_no, description, quantity, uom_code,
          unit_cost, currency, sourced, fitted_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
       RETURNING *
     )
     SELECT ${PART_COLUMNS} FROM inserted wp`,
    [
      workOrderId,
      fields.partNo,
      fields.description,
      fields.quantity,
      fields.uomCode,
      fields.unitCost,
      fields.currency,
      fields.sourced,
      fields.fittedAt
    ]
  );
  return toBookedPart(row);
}

// A `stores` booking: a catalogue part, a shelf to draw it from, and a
// withdrawal recorded in the SAME transaction as the cost line. The
// `work_order_parts` row is written first so the non-negative refusal aborts
// a transaction that has really written something and the ROLLBACK undoes a
// real row — "both or neither" is proven by the database, not asserted by
// this code, the same ordering reportBreakdown uses for its stoppage.
async function bookStockPart(workOrderId, attrs, accountId) {
  const part = await inventory.findPart(attrs.partId);
  if (!part) throw notFound('Part');
  const store = await inventory.findStore(attrs.storeId);
  if (!store) throw notFound('Store');

  const quantity = normaliseQuantity(attrs.quantity);
  const unitCost = normaliseUnitCost(attrs.unitCost);
  const currency = normaliseCurrency(attrs.currency);
  const fittedAt = normaliseFittedAt(attrs.fittedAt);
  const description =
    typeof attrs.description === 'string' && attrs.description.trim() !== ''
      ? attrs.description.trim()
      : part.description;

  try {
    return await withActor(accountId, async (client) => {
      const { rows: [workOrder] } = await client.query(
        'SELECT work_order_no FROM work_orders WHERE id = $1',
        [workOrderId]
      );
      if (!workOrder) throw notFound('Work order');

      const booked = await insertBookingPart(client, workOrderId, {
        partNo: part.partNo,
        description,
        quantity,
        uomCode: part.uomCode,
        unitCost,
        currency,
        sourced: 'stores',
        fittedAt
      });

      await inventory.withdrawStock(client, {
        storeId: store.id,
        partId: part.id,
        quantity,
        reason: `Booked against Work order ${workOrder.work_order_no}`,
        occurredAt: fittedAt
      });

      return booked;
    });
  } catch (error) {
    // `23514` here is the stock trigger's own refusal. Map it outside the
    // rolled-back transaction, where the shelf's real balance can be read.
    if (error.code === '23514') {
      throw await inventory.insufficientStock(part.id, store.id);
    }
    throw mapBookingWriteError(error);
  }
}

// A `purchased`, `refurbished` or `cannibalised` booking: a cost line with
// nothing upstream to check it against. It names its own unit (validated
// against `units_of_measure`, so it shares the one notion of a unit the
// catalogue uses) and touches no stock — ADR-0015 is explicit that only
// `stores` draws down inventory, and a booking that decremented for a part
// bought that morning would invent a movement that never happened.
async function bookOwnPart(workOrderId, attrs, accountId) {
  const quantity = normaliseQuantity(attrs.quantity);
  const unitCost = normaliseUnitCost(attrs.unitCost);
  const currency = normaliseCurrency(attrs.currency);
  const fittedAt = normaliseFittedAt(attrs.fittedAt);

  if (typeof attrs.description !== 'string' || attrs.description.trim() === '') {
    throw httpError(400, 'description is required');
  }
  const unit = await inventory.findUnitOfMeasure(attrs.uomCode);
  if (!unit) throw notFound('Unit of measure');

  const partNo =
    typeof attrs.partNo === 'string' && attrs.partNo.trim() !== '' ? attrs.partNo.trim() : null;

  try {
    return await withActor(accountId, (client) =>
      insertBookingPart(client, workOrderId, {
        partNo,
        description: attrs.description.trim(),
        quantity,
        uomCode: unit.code,
        unitCost,
        currency,
        sourced: attrs.sourced,
        fittedAt
      })
    );
  } catch (error) {
    throw mapBookingWriteError(error);
  }
}

// Book a part against a work order (issue #75). `sourced` decides the path:
// `stores` draws from a named shelf in one transaction, the other three write
// a cost line and nothing else.
async function bookPart(workOrderId, attrs = {}, accountId) {
  const sourced = attrs.sourced ?? 'stores';
  if (!PART_SOURCES.includes(sourced)) {
    throw httpError(400, `sourced must be one of: ${PART_SOURCES.join(', ')}`);
  }
  if (sourced === 'stores') {
    return bookStockPart(workOrderId, attrs, accountId);
  }
  return bookOwnPart(workOrderId, { ...attrs, sourced }, accountId);
}

// What a work order has cost so far (issue #75): hours by activity, and the
// parts fitted with their total. Deliberately NOT a single total cost.
//
// The schema warns why: labour booked here is a slice of COST_LABOUR, already
// costed from attendance_records, while parts are new money. Summing the two
// — or summing labour here with plant labour cost anywhere — double-counts
// every technician. So this read returns `labourHours` and `partsCost` as two
// separate facts, never their sum, and the client labels them so the
// distinction is visible to the reader rather than buried.
//
// `overtimeHours` is split out of each activity's total, so overtime is
// distinguishable from ordinary hours at the point of reading, not only in
// the raw row.
async function workOrderCost(workOrderId, client = getPool()) {
  const { rows: labour } = await client.query(
    `SELECT activity,
            COALESCE(SUM(hours), 0)                              AS hours,
            COALESCE(SUM(hours) FILTER (WHERE is_overtime), 0)   AS overtime_hours
       FROM work_order_labour
      WHERE work_order_id = $1
      GROUP BY activity
      ORDER BY activity`,
    [workOrderId]
  );

  const { rows: parts } = await client.query(
    `SELECT ${PART_COLUMNS}
       FROM work_order_parts wp
      WHERE wp.work_order_id = $1
      ORDER BY wp.id`,
    [workOrderId]
  );

  const labourByActivity = labour.map((row) => ({
    activity: row.activity,
    hours: Number(row.hours),
    overtimeHours: Number(row.overtime_hours)
  }));
  const bookedParts = parts.map(toBookedPart);

  return {
    labourHours: labourByActivity.reduce((sum, row) => sum + row.hours, 0),
    overtimeHours: labourByActivity.reduce((sum, row) => sum + row.overtimeHours, 0),
    labourByActivity,
    parts: bookedParts,
    // Null when no part carries a cost, rather than 0 — an unpriced shelf is
    // a gap in the data, not a measured zero. Only parts add; labour hours
    // are reported above and are never folded in here.
    partsCost: bookedParts.some((part) => part.totalCost !== null)
      ? bookedParts.reduce((sum, part) => sum + (part.totalCost ?? 0), 0)
      : null
  };
}

module.exports = {
  LABOUR_ACTIVITIES,
  PART_SOURCES,
  bookLabour,
  bookPart,
  workOrderCost
};
