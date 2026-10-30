/*
 * The MTU KPI catalogue and its Targets (ADR-0055): every query against db
 * `mtu`, schema `kpi`, that concerns what a KPI is and what it is measured
 * against. The daily Review is review.js.
 *
 * Only SELECTs and plain INSERTs. The role the Platform connects as in
 * production (`lean_app`) holds column-level INSERT and nothing that can change
 * a row, so there is no upsert anywhere in this Module: a "correction" is
 * another row and the database's views pick the newest. The tables refuse
 * UPDATE and DELETE for every role regardless.
 *
 * Every function takes the second Pool as it finds it (`getMtuPool()`) and
 * requires no other Module. A record's own fields are validated here and raise
 * this Module's own `httpError`; which fields a request sent, and whether a date
 * parses, is the routes' business. Dates are cast to text in SQL and numerics to
 * `float8`, so what leaves this file is plain JSON (node-postgres would hand
 * back a local-midnight Date and a string).
 */

const { getMtuPool } = require('../../platform/mtu-db');
const { httpError, notFound } = require('./errors');

const GRAINS = ['Daily', 'Weekly', 'Monthly'];

// The database also permits '<' and '>', and the seeded KPIs MTTR and MTBF use
// them. The API narrows what a new KPI may be to the two the client offers;
// widening it is one line here, not a schema change.
const DIRECTIONS = ['<=', '>='];

function requireNonEmptyString(value, field) {
  if (typeof value !== 'string' || value.trim() === '') {
    throw httpError(400, `${field} is required`);
  }
  return value.trim();
}

function optionalText(value, field) {
  if (value === undefined || value === null) return null;
  if (typeof value !== 'string') throw httpError(400, `${field} must be a string`);
  return value;
}

function toKpi(row) {
  return {
    kpi_id: row.kpi_id,
    kpi: row.kpi,
    title: row.title,
    unit: row.unit,
    direction: row.direction,
    decimals: row.decimals,
    value_measure: row.value_measure
  };
}

// A grain's Target as the client reads it: null when nothing is in force, and
// also when the entry in force says "no target from that date on" — an object
// with `target: null` would make the client test two things for one fact.
function targetOrNull(row, prefix) {
  if (row[`${prefix}_target`] === null) return null;
  return {
    valid_from: row[`${prefix}_valid_from`],
    target: row[`${prefix}_target`],
    note: row[`${prefix}_note`]
  };
}

// One row per KPI in `kpi_id` order, with the Target in force today per grain
// (`v_target_current`, the plant's own today) and the judgement for
// `reviewDate` (the route defaults it to the Site's today, which is not this
// file's to compute). The `note` of a Target is the note of the entry in force, which
// the view does not carry, so it is read from the effective entry beside it.
async function listCatalogue({ reviewDate }) {
  const { rows } = await getMtuPool().query(
    `WITH eff AS (
       SELECT DISTINCT ON (kpi_id, grain, valid_from) kpi_id, grain, valid_from, target, note
         FROM kpi.kpi_target
        ORDER BY kpi_id, grain, valid_from, entered_at DESC, target_id DESC
     )
     SELECT k.kpi_id, k.kpi, k.title, k.unit, k.direction, k.decimals, k.value_measure,
            d.valid_from::text AS daily_valid_from, d.target::float8 AS daily_target, dn.note AS daily_note,
            w.valid_from::text AS weekly_valid_from, w.target::float8 AS weekly_target, wn.note AS weekly_note,
            m.valid_from::text AS monthly_valid_from, m.target::float8 AS monthly_target, mn.note AS monthly_note,
            r.status, r.observed::float8 AS observed, r.note AS review_note, r.app_user, r.entered_at
       FROM kpi.kpi k
       LEFT JOIN kpi.v_target_current d  ON d.kpi_id = k.kpi_id AND d.grain = 'Daily'
       LEFT JOIN eff dn ON dn.kpi_id = d.kpi_id AND dn.grain = 'Daily' AND dn.valid_from = d.valid_from
       LEFT JOIN kpi.v_target_current w  ON w.kpi_id = k.kpi_id AND w.grain = 'Weekly'
       LEFT JOIN eff wn ON wn.kpi_id = w.kpi_id AND wn.grain = 'Weekly' AND wn.valid_from = w.valid_from
       LEFT JOIN kpi.v_target_current m  ON m.kpi_id = k.kpi_id AND m.grain = 'Monthly'
       LEFT JOIN eff mn ON mn.kpi_id = m.kpi_id AND mn.grain = 'Monthly' AND mn.valid_from = m.valid_from
       LEFT JOIN kpi.v_kpi_review_current r ON r.kpi_id = k.kpi_id AND r.review_date = $1::date
      ORDER BY k.kpi_id`,
    [reviewDate]
  );

  return rows.map((row) => ({
    ...toKpi(row),
    targets: {
      Daily: targetOrNull(row, 'daily'),
      Weekly: targetOrNull(row, 'weekly'),
      Monthly: targetOrNull(row, 'monthly')
    },
    review: row.status === null
      ? null
      : {
        status: row.status,
        observed: row.observed,
        note: row.review_note,
        app_user: row.app_user,
        entered_at: row.entered_at
      }
  }));
}

// Adding a KPI. `kpi_id` comes from the identity, never from the caller.
async function addKpi({ kpi, title, unit, direction, decimals, valueMeasure }) {
  const cleanKpi = requireNonEmptyString(kpi, 'kpi');
  const cleanTitle = requireNonEmptyString(title, 'title');
  if (!DIRECTIONS.includes(direction)) {
    throw httpError(400, `direction must be one of: ${DIRECTIONS.join(', ')}`);
  }
  if (!Number.isInteger(decimals) || decimals < 0 || decimals > 6) {
    throw httpError(400, 'decimals must be a whole number from 0 to 6');
  }
  const cleanUnit = optionalText(unit, 'unit') ?? '';
  const cleanMeasure = optionalText(valueMeasure, 'value_measure');

  try {
    const { rows: [row] } = await getMtuPool().query(
      `INSERT INTO kpi.kpi (kpi, title, unit, direction, decimals, value_measure)
       VALUES ($1, $2, $3, $4, $5, $6)
       RETURNING kpi_id`,
      [cleanKpi, cleanTitle, cleanUnit, direction, decimals, cleanMeasure]
    );
    return row.kpi_id;
  } catch (error) {
    throw mapKpiWriteError(error);
  }
}

// A Postgres error is never echoed to a caller (AGENTS.md section 6's
// mapAssetWriteError is the model): a unique violation can only be the KPI's own
// name, and a CHECK that slipped past the validation above is the caller's
// fault too.
function mapKpiWriteError(error) {
  if (error.code === '23505') return httpError(409, 'A KPI with that name already exists');
  if (error.code === '23514') return httpError(400, 'The KPI was refused by the catalogue');
  return error;
}

// `kpi.kpi.kpi_id` is an int4 column, and parseId accepts any digit string. An
// id beyond the column's range cannot name a KPI, so it is answered as an
// unknown one here, before any SQL sees it (Postgres would raise a range error
// the caller would see as a 500).
const MAX_KPI_ID = 2147483647;

async function findKpi(kpiId) {
  if (!(Number(kpiId) <= MAX_KPI_ID)) return null;
  const { rows: [row] } = await getMtuPool().query(
    `SELECT kpi_id, kpi, title, unit, direction, decimals, value_measure
       FROM kpi.kpi WHERE kpi_id = $1`,
    [kpiId]
  );
  return row ? toKpi(row) : null;
}

// A KPI's Targets: the one in force per grain today, and every entry ever made,
// newest first. Null when the KPI does not exist, so the route can 404.
async function listTargets({ kpiId }) {
  const kpi = await findKpi(kpiId);
  if (!kpi) return null;

  const pool = getMtuPool();
  const { rows: current } = await pool.query(
    `SELECT grain, valid_from::text AS valid_from, target::float8 AS target
       FROM kpi.v_target_current
      WHERE kpi_id = $1
      ORDER BY CASE grain WHEN 'Daily' THEN 1 WHEN 'Weekly' THEN 2 ELSE 3 END`,
    [kpiId]
  );
  const { rows: history } = await pool.query(
    `SELECT target_id::text AS target_id, grain, valid_from::text AS valid_from, target::float8 AS target,
            note, app_user, entered_at, entered_by, is_effective
       FROM kpi.v_target_history
      WHERE kpi_id = $1
      ORDER BY entered_at DESC, target_id DESC`,
    [kpiId]
  );

  return {
    kpi,
    current,
    history: history.map((row) => ({ ...row, target_id: Number(row.target_id) }))
  };
}

// Appending a Target. `target` null means "no target from `validFrom` on".
// An entry for the same (kpi, grain, valid_from) with the same target is a 409;
// a different one is a correction and is a new row by design (the tables are
// append-only and the newest entry wins). The existing entry is read with the
// views' own DISTINCT ON expression. The read and the insert are not atomic,
// but nothing can be lost by that: two concurrent identical inserts produce a
// second row that the views collapse.
async function addTarget({ kpiId, grain, validFrom, target, note, appUser }) {
  if (!GRAINS.includes(grain)) {
    throw httpError(400, `grain must be one of: ${GRAINS.join(', ')}`);
  }
  if (target !== null && !(typeof target === 'number' && Number.isFinite(target))) {
    throw httpError(400, 'target must be a number or null');
  }
  const cleanNote = optionalText(note, 'note');

  const pool = getMtuPool();
  if (!(await findKpi(kpiId))) throw notFound('KPI');

  const { rows: [existing] } = await pool.query(
    `SELECT target IS NOT DISTINCT FROM $4::numeric AS same
       FROM (SELECT DISTINCT ON (kpi_id, grain, valid_from) target
               FROM kpi.kpi_target
              WHERE kpi_id = $1 AND grain = $2 AND valid_from = $3::date
              ORDER BY kpi_id, grain, valid_from, entered_at DESC, target_id DESC) latest`,
    [kpiId, grain, validFrom, target]
  );
  if (existing && existing.same) {
    throw httpError(409, 'That Target is already recorded for this KPI, grain and date');
  }

  try {
    const { rows: [row] } = await pool.query(
      `INSERT INTO kpi.kpi_target (kpi_id, grain, valid_from, target, note, app_user)
       VALUES ($1, $2, $3::date, $4, $5, $6)
       RETURNING target_id::text AS target_id`,
      [kpiId, grain, validFrom, target, cleanNote, appUser]
    );
    return Number(row.target_id);
  } catch (error) {
    if (error.code === '23503') throw notFound('KPI');
    if (error.code === '23514') throw httpError(400, 'The Target was refused by the catalogue');
    throw error;
  }
}

module.exports = { listCatalogue, addKpi, listTargets, addTarget };
