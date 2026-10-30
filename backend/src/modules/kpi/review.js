/*
 * The daily KPI Review (ADR-0055): the human judgement of one KPI on one day —
 * met, missed or not measured — kept in db `mtu`, schema `kpi`, beside the
 * catalogue catalogue.js reads.
 *
 * Append-only, like the Targets. A correction is a second row for the same KPI
 * and day, the newest wins in `kpi.v_kpi_review_current`, and that is the
 * database working as designed, not a conflict to refuse. So `saveReview` is a
 * plain INSERT per entry and never an upsert (the production role holds no
 * UPDATE).
 *
 * Validation of an entry's own fields lives here and raises this Module's own
 * `httpError`; the routes own the request's shape. The database's CHECK
 * `kpi_review_miss_needs_note` is the authority on a missed day's note — it
 * wants ten non-blank characters — and the same rule is mirrored here only so
 * the caller gets a 400 that names the KPI instead of a constraint violation.
 */

const { getMtuPool } = require('../../platform/mtu-db');
const { httpError } = require('./errors');

const STATUSES = ['met', 'missed', 'not_measured'];
const MISSED_NOTE_MIN_LENGTH = 10;

// The titles of the named KPIs in one query, keyed by id. An id the catalogue
// does not hold is simply absent from the map.
// `kpi_id` is an int4 column: an id beyond its range cannot exist, so it is
// left out here (and so reads as unknown) rather than raising a range error in
// the `::int[]` cast.
async function findKpisByIds(ids) {
  const { rows } = await getMtuPool().query(
    'SELECT kpi_id, title FROM kpi.kpi WHERE kpi_id = ANY($1::int[])',
    [ids.filter((id) => id <= 2147483647)]
  );
  return new Map(rows.map((row) => [row.kpi_id, row.title]));
}

// One row per KPI in the catalogue: that day's judgement (null `status` where
// there is none) and the Daily Target in force ON that date. Not
// `v_target_current`, which answers for today: a Review of a past day is judged
// against the Target that day had, which is the whole reason Targets are
// append-only. The lateral expression is the one `kpi.v_kpi_review_missed` uses —
// the latest entry per KPI, grain and date, then the greatest `valid_from` on or
// before the day, and no `target IS NOT NULL` filter, so a later "no target"
// entry yields null rather than an older number.
async function listReview({ reviewDate }) {
  const { rows } = await getMtuPool().query(
    `WITH eff AS (
       SELECT DISTINCT ON (kpi_id, grain, valid_from) kpi_id, grain, valid_from, target
         FROM kpi.kpi_target
        ORDER BY kpi_id, grain, valid_from, entered_at DESC, target_id DESC
     )
     SELECT k.kpi_id, k.title, k.unit, k.direction, t.target::float8 AS target,
            r.status, r.observed::float8 AS observed, r.note, r.app_user, r.entered_at
       FROM kpi.kpi k
       LEFT JOIN kpi.v_kpi_review_current r ON r.kpi_id = k.kpi_id AND r.review_date = $1::date
       LEFT JOIN LATERAL (
         SELECT e.target
           FROM eff e
          WHERE e.kpi_id = k.kpi_id AND e.grain = 'Daily' AND e.valid_from <= $1::date
          ORDER BY e.valid_from DESC
          LIMIT 1
       ) t ON TRUE
      ORDER BY k.kpi_id`,
    [reviewDate]
  );
  return rows;
}

// All or nothing: every entry is checked, then every entry is inserted in one
// transaction, so a Review that is half-saved cannot exist. The named KPIs are
// resolved in one query before the transaction opens — an unknown id is a 409
// (the request is well-formed and names something the catalogue lacks), and the
// title is what a 400 names. `appUser` is the signed-in person's name, passed
// by the route from the Account, never from the request body.
async function saveReview({ reviewDate, entries, appUser }) {
  for (const entry of entries) {
    if (!STATUSES.includes(entry.status)) {
      throw httpError(400, `status must be one of: ${STATUSES.join(', ')}`);
    }
    if (entry.observed !== null && !(typeof entry.observed === 'number' && Number.isFinite(entry.observed))) {
      throw httpError(400, 'observed must be a number');
    }
    if (entry.note !== null && typeof entry.note !== 'string') {
      throw httpError(400, 'note must be a string');
    }
  }

  const titles = await findKpisByIds(entries.map((entry) => entry.kpiId));
  for (const entry of entries) {
    if (!titles.has(entry.kpiId)) {
      throw httpError(409, `KPI ${entry.kpiId} is not in the catalogue`);
    }
  }
  for (const entry of entries) {
    if (entry.status === 'missed' && (entry.note ?? '').trim().length < MISSED_NOTE_MIN_LENGTH) {
      throw httpError(
        400,
        `${titles.get(entry.kpiId)} was missed: say why in a note of at least ${MISSED_NOTE_MIN_LENGTH} characters`
      );
    }
  }

  const client = await getMtuPool().connect();
  let releaseError;
  try {
    await client.query('BEGIN');
    for (const entry of entries) {
      await client.query(
        `INSERT INTO kpi.kpi_review (kpi_id, review_date, status, observed, note, app_user)
         VALUES ($1, $2::date, $3, $4, $5, $6)`,
        [entry.kpiId, reviewDate, entry.status, entry.observed, entry.note, appUser]
      );
    }
    await client.query('COMMIT');
    return entries.length;
  } catch (error) {
    try {
      await client.query('ROLLBACK');
    } catch (rollbackError) {
      // The connection is unusable; releasing it with the error makes the pool
      // discard it rather than hand it to the next caller.
      releaseError = rollbackError;
    }
    if (error.code === '23503') throw httpError(409, 'A KPI in the Review is not in the catalogue');
    if (error.code === '23514') throw httpError(400, 'The Review was refused by the catalogue');
    // `observed` is numeric(18,4): a number too large for it is the caller's.
    if (error.code === '22003') throw httpError(400, 'observed is too large to record');
    throw error;
  } finally {
    client.release(releaseError);
  }
}

module.exports = { findKpisByIds, listReview, saveReview };
