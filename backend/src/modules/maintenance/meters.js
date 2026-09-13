/*
 * Asset meters and the readings taken against them (issue #79), the sixth
 * body of records this Module owns after Assets (#56), Work orders (#57),
 * Requests (#72), Downtime (#73) and PM schedules (#74). Same shape as
 * assets.js and work-orders.js, and the same rule holds: this file never
 * requires '../people' and never resolves or writes a People record. The
 * Asset a meter sits on, and whether the caller may act at its Org Unit, are
 * both proved one layer up in meter-routes.js through modules/people's entry
 * point.
 *
 * Cross-Module reads are ordinary joins here (ADR-0006): `assets`,
 * `org_units`, `sites` and the baseline `units_of_measure` catalogue are all
 * joined directly, the same way assets.js joins org_units.
 *
 * ## What a reading is, and what accumulated use is
 *
 * `meter_readings.reading` stores what is physically on the counter. A
 * replaced hour counter restarts near zero, so "accumulated use" cannot be
 * the reading alone — it is `reading + asset_meters.rollover_offset`, and
 * every PM due-ness calculation reads that sum, never the raw reading. This
 * is the decision ADR-0029 records. A rollover or replacement is an explicit
 * act (`rolloverMeter`): it adds the accumulated use as of the last reading
 * to `rollover_offset` and records the new counter's own starting value as a
 * reading, so the counter's next reading compares against the new epoch
 * rather than the old one. A reading that simply went down, with no such act,
 * is refused (ADR-0029).
 *
 * ## Sources
 *
 * `meter_readings.source` allows manual/plc/scada/import/api. This ticket
 * accepts `manual` only — a reading a person typed. Ingesting a machine feed
 * brings the replay and de-duplication problems #73 faces with downtime and
 * belongs in a ticket of its own; ADR-0030 records that boundary.
 */

const { getPool, withActor } = require('../../platform/db');
const { httpError, notFound, parseId } = require('./errors');

// Mirrors the CHECK constraint on asset_meters.meter_type. Only a cumulative
// meter may drive an interval-based PM; a gauge may go either way and is
// recorded but never scheduled against.
const METER_TYPES = ['cumulative', 'gauge'];

// The one source this ticket accepts. The column allows more; see the header
// and ADR-0030.
const ACCEPTED_READING_SOURCES = ['manual'];

// The named refusal a backward reading on a cumulative meter carries, so a
// caller can tell "the counter went down" apart from a generic 409. Kept in
// one place; meter-routes.js's handleError copies error.code onto the body.
const READING_REGRESSED_CODE = 'METER_READING_REGRESSED';

// Every field a meter row carries, with its Asset, its Org Unit, its unit of
// measure's name, its latest reading and the accumulated use the PM machinery
// compares against. The LATERAL keeps "latest reading, per meter" one index
// lookup (`meter_readings_meter_idx`), the same shape `v_pm_due` uses.
const METER_COLUMNS = `
  m.id, m.asset_id, m.code, m.name, m.uom_code, m.meter_type,
  m.rollover_offset, m.is_active,
  a.code AS asset_code, a.name AS asset_name,
  ou.id AS org_unit_id, ou.name AS org_unit_name, ou.site_id,
  u.name AS uom_name,
  lr.reading AS latest_reading, lr.read_at AS latest_read_at,
  COALESCE(lr.reading, 0) + m.rollover_offset AS accumulated_use
`;

// The join chain METER_COLUMNS depends on, factored out because every
// function below attaches it after its own FROM clause — whether that FROM
// names the bare `asset_meters` table or a CTE (`inserted`) built off it,
// `m` is always the alias the join chain expects.
const METER_FROM = `
  JOIN assets a ON a.id = m.asset_id
  JOIN org_units ou ON ou.id = a.org_unit_id
  JOIN units_of_measure u ON u.code = m.uom_code
  LEFT JOIN LATERAL (
    SELECT mr.reading, mr.read_at
      FROM meter_readings mr
     WHERE mr.asset_meter_id = m.id
     ORDER BY mr.read_at DESC, mr.id DESC
     LIMIT 1
  ) lr ON TRUE
`;

function toMeter(row) {
  return {
    id: row.id,
    assetId: row.asset_id,
    assetCode: row.asset_code,
    assetName: row.asset_name,
    orgUnitId: row.org_unit_id,
    orgUnitName: row.org_unit_name,
    siteId: row.site_id,
    code: row.code,
    name: row.name,
    uomCode: row.uom_code,
    uomName: row.uom_name,
    meterType: row.meter_type,
    rolloverOffset: Number(row.rollover_offset),
    isActive: row.is_active,
    latestReading: row.latest_reading === null ? null : Number(row.latest_reading),
    latestReadAt: row.latest_read_at,
    // The one number PM due-ness reads; never the raw reading (ADR-0029).
    accumulatedUse: Number(row.accumulated_use)
  };
}

function toReading(row) {
  return {
    id: row.id,
    assetMeterId: row.asset_meter_id,
    orgUnitId: row.org_unit_id,
    shiftInstanceId: row.shift_instance_id,
    reading: Number(row.reading),
    readAt: row.read_at,
    source: row.source,
    note: row.note
  };
}

function requireNonEmptyString(field, value) {
  if (typeof value !== 'string' || value.trim() === '') {
    throw httpError(400, `${field} is required`);
  }
}

// A reading is a finite number, never a string a caller hoped would parse.
// JSON booleans are refused too, since `Number(true)` is 1 and would silently
// record a value nobody meant — the same reasoning job-plans.js gives its own
// estimatedHours.
function resolveReading(value) {
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    throw httpError(400, 'reading must be a number');
  }
  return value;
}

function resolveMeterType(value) {
  if (!METER_TYPES.includes(value)) {
    throw httpError(400, `meterType must be one of: ${METER_TYPES.join(', ')}`);
  }
  return value;
}

function resolveReadAt(value) {
  if (value === undefined || value === null) return null;
  if (typeof value !== 'string') {
    throw httpError(400, 'readAt must be an ISO timestamp');
  }
  return value;
}

// The `asset_meters_code_unique` constraint is UNIQUE (asset_id, code) — per
// Asset, not global — so the message says so rather than implying a Platform-
// wide clash the caller could resolve by renaming the machine. A 23503 here
// can only be the unit of measure: the route has already proved the Asset.
function mapMeterWriteError(error) {
  if (error.code === '23505') {
    return httpError(409, 'this Asset already has a meter with that code');
  }
  if (error.code === '23503') {
    return notFound('Unit of measure');
  }
  if (error.code === '23514') {
    return httpError(400, 'that is not a valid meter');
  }
  return error;
}

// Site-wide and carrying no Grant filter (ADR-0009): scope decides where an
// Account may act, not what it may know about. Active meters by default;
// retired ones only when a caller asks by name. Optionally narrowed to one
// Asset's meters — the picker on the PM schedule form reads exactly that.
async function listMetersAtSite(siteId, { assetId = null, includeInactive = false } = {}) {
  const activeClause = includeInactive ? '' : 'AND m.is_active';
  const params = [siteId];
  let assetClause = '';
  if (assetId !== null) {
    params.push(assetId);
    assetClause = `AND m.asset_id = $${params.length}`;
  }
  const { rows } = await getPool().query(
    `SELECT ${METER_COLUMNS}
       FROM asset_meters m
       ${METER_FROM}
      WHERE ou.site_id = $1 ${activeClause} ${assetClause}
      ORDER BY a.name, m.code`,
    params
  );
  return rows.map(toMeter);
}

// The null-returning lookup this Module's own routes use before a write, the
// same total shape assets.js's findAsset has: a malformed id answers null
// rather than handing Postgres a non-numeric BIGINT and turning a 404 into a
// 500.
async function findMeter(id) {
  if (parseId(id) === null) return null;
  const { rows } = await getPool().query(
    `SELECT ${METER_COLUMNS}
       FROM asset_meters m
       ${METER_FROM}
      WHERE m.id = $1`,
    [id]
  );
  return rows[0] ? toMeter(rows[0]) : null;
}

// The shared unit-of-measure catalogue the meter form chooses from (ADR-0023:
// a value with a known set is chosen, never typed). `units_of_measure` is a
// baseline reference table owned by no Module; this is a read, so joining it
// here is the same ordinary cross-record read assets.js makes onto org_units.
async function listUnitsOfMeasure() {
  const { rows } = await getPool().query(
    `SELECT code, name, dimension
       FROM units_of_measure
      WHERE is_active
      ORDER BY name, code`
  );
  return rows.map((row) => ({ code: row.code, name: row.name, dimension: row.dimension }));
}

// Defines a meter on an Asset. The Asset's existence and the caller's write
// scope are proved by meter-routes.js before this runs; the unit of measure's
// existence is proved by the foreign key.
async function createMeter({ assetId, code, name, uomCode, meterType }, accountId) {
  requireNonEmptyString('code', code);
  requireNonEmptyString('name', name);
  requireNonEmptyString('uomCode', uomCode);
  const resolvedMeterType = resolveMeterType(meterType);

  try {
    return await withActor(accountId, async (client) => {
      const { rows: [inserted] } = await client.query(
        `INSERT INTO asset_meters (asset_id, code, name, uom_code, meter_type)
         VALUES ($1, $2, $3, $4, $5)
         RETURNING id`,
        [assetId, code.trim(), name.trim(), uomCode, resolvedMeterType]
      );
      const { rows: [row] } = await client.query(
        `SELECT ${METER_COLUMNS}
           FROM asset_meters m
           ${METER_FROM}
          WHERE m.id = $1`,
        [inserted.id]
      );
      return toMeter(row);
    });
  } catch (error) {
    throw mapMeterWriteError(error);
  }
}

// The accumulated use as of a meter's latest reading, on whichever connection
// is handed in. Null when the id names no meter. A meter with no readings at
// all reports its offset — which is exactly the accumulated use at the moment
// its current counter was installed (ADR-0029).
async function accumulatedUse(db, meterId) {
  const { rows: [row] } = await db.query(
    `SELECT COALESCE(lr.reading, 0) + m.rollover_offset AS accumulated
       FROM asset_meters m
       LEFT JOIN LATERAL (
         SELECT mr.reading
           FROM meter_readings mr
          WHERE mr.asset_meter_id = m.id
          ORDER BY mr.read_at DESC, mr.id DESC
          LIMIT 1
       ) lr ON TRUE
      WHERE m.id = $1`,
    [meterId]
  );
  return row ? Number(row.accumulated) : null;
}

// Reads one meter row inside a transaction, locked, for the two writes that
// must serialise against each other: a reading's backward check and a
// rollover's offset bump. Returns the raw row (not the wire shape) because
// both callers need `meter_type` and `rollover_offset` specifically.
async function lockMeter(client, meterId) {
  const { rows: [meter] } = await client.query(
    `SELECT m.id, m.asset_id, m.meter_type, m.rollover_offset,
            a.org_unit_id,
            (SELECT mr.reading
               FROM meter_readings mr
              WHERE mr.asset_meter_id = m.id
              ORDER BY mr.read_at DESC, mr.id DESC
              LIMIT 1) AS latest_reading
       FROM asset_meters m
       JOIN assets a ON a.id = m.asset_id
      WHERE m.id = $1
      FOR UPDATE OF m`,
    [meterId]
  );
  return meter ?? null;
}

async function insertReading(client, { meterId, orgUnitId, reading, readAt, note }) {
  const { rows: [row] } = await client.query(
    `INSERT INTO meter_readings
       (asset_meter_id, org_unit_id, reading, read_at, source, note)
     VALUES ($1, $2, $3, COALESCE($4::timestamptz, now()), 'manual', $5)
     RETURNING id, asset_meter_id, org_unit_id, shift_instance_id, reading, read_at, source, note`,
    [meterId, orgUnitId, reading, readAt, note ?? null]
  );
  return toReading(row);
}

async function readMeterById(client, meterId) {
  const { rows: [row] } = await client.query(
    `SELECT ${METER_COLUMNS}
       FROM asset_meters m
       ${METER_FROM}
      WHERE m.id = $1`,
    [meterId]
  );
  return toMeter(row);
}

// Records a manual reading against a meter. `source` is validated against the
// one value this ticket accepts (ADR-0030); a caller sending `plc` is refused
// rather than silently relabelled. For a cumulative meter, a reading lower
// than the last one is refused with READING_REGRESSED_CODE — a counter that
// went down is either a mistake or a rollover, and a rollover must be said out
// loud (ADR-0029), never inferred. A gauge may go either way.
//
// The row is locked and the check is made inside the same transaction as the
// insert, so two concurrent readings cannot both pass the backward check.
async function recordReading(meterId, { reading, note, readAt, source }, accountId) {
  const resolvedReading = resolveReading(reading);
  const resolvedReadAt = resolveReadAt(readAt);
  const resolvedSource = source === undefined || source === null ? 'manual' : source;
  if (!ACCEPTED_READING_SOURCES.includes(resolvedSource)) {
    throw httpError(400, `readings from '${resolvedSource}' are not accepted yet`);
  }

  try {
    return await withActor(accountId, async (client) => {
      const meter = await lockMeter(client, meterId);
      if (!meter) throw notFound('Meter');

      if (
        meter.meter_type === 'cumulative' &&
        meter.latest_reading !== null &&
        resolvedReading < Number(meter.latest_reading)
      ) {
        throw httpError(
          409,
          'a cumulative meter cannot read lower than its last reading; record a rollover if the counter was reset',
          READING_REGRESSED_CODE
        );
      }

      const readingRow = await insertReading(client, {
        meterId,
        orgUnitId: meter.org_unit_id,
        reading: resolvedReading,
        readAt: resolvedReadAt,
        note
      });
      return { reading: readingRow, meter: await readMeterById(client, meterId) };
    });
  } catch (error) {
    throw mapMeterWriteError(error);
  }
}

// Records an explicit rollover or replacement. The act carries the accumulated
// use as of the last reading into `rollover_offset`, then records the new
// counter's own starting value (default 0) as a reading, so accumulated use is
// continuous across the reset and the next reading compares against the new
// epoch rather than the old one (ADR-0029). `reading` is what is physically on
// the new counter at the moment it is installed — usually zero, but a
// partially-used replacement can start higher.
async function rolloverMeter(meterId, { reading, note, readAt }, accountId) {
  const resolvedReading = reading === undefined || reading === null ? 0 : resolveReading(reading);
  const resolvedReadAt = resolveReadAt(readAt);

  try {
    return await withActor(accountId, async (client) => {
      const meter = await lockMeter(client, meterId);
      if (!meter) throw notFound('Meter');

      const carried = (meter.latest_reading === null ? 0 : Number(meter.latest_reading)) +
        Number(meter.rollover_offset);

      await client.query('UPDATE asset_meters SET rollover_offset = $1 WHERE id = $2', [
        carried,
        meterId
      ]);

      const readingRow = await insertReading(client, {
        meterId,
        orgUnitId: meter.org_unit_id,
        reading: resolvedReading,
        readAt: resolvedReadAt,
        note: note ?? 'Counter reset or replaced'
      });
      return { reading: readingRow, meter: await readMeterById(client, meterId) };
    });
  } catch (error) {
    throw mapMeterWriteError(error);
  }
}

module.exports = {
  METER_TYPES,
  ACCEPTED_READING_SOURCES,
  READING_REGRESSED_CODE,
  listMetersAtSite,
  findMeter,
  listUnitsOfMeasure,
  createMeter,
  accumulatedUse,
  recordReading,
  rolloverMeter
};
