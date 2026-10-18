/*
 * The Training record (issue #287, CONTEXT.md's Training record, ADR-0043).
 * One occasion of training delivered at an Org Unit, raised as a draft with
 * its own Site-scoped number. Like attendance.js, this file is unaware of who
 * is calling: no role check and no Org Unit scope for a write — training-
 * routes.js owns `canAct({ write: true })`. The one exception is the
 * register's draft visibility, which is baked into the query's arguments
 * (`viewer`) for the same reason attendance.js's worklist bakes in its scope:
 * a register spans many Org Units, so the question cannot be asked per row.
 * The predicate is canAct({ write: true })'s own, spelled in SQL — a Grant
 * with `can_write` whose Org Unit is the record's or an ancestor of it — and
 * an administrator sees every draft.
 *
 * Trainees (#288), sending (#289) and correcting a sent record (#291) are not
 * here; nothing in this file writes status 'sent'.
 */

const { getPool, withActor } = require('../../platform/db');
const { httpError, notFound, parseId } = require('./errors');

const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;
const MAX_DURATION_HOURS = 9999.99;

const SELECT_RECORD = `
  SELECT tr.id, tr.site_id, tr.org_unit_id, tr.number, tr.title,
         tr.trained_on::text AS trained_on, tr.duration_hours::float8 AS duration_hours,
         tr.trainer_employee_id, tr.objective, tr.status,
         tr.created_at, tr.updated_at,
         ou.name AS org_unit_name, ou.path AS org_unit_path,
         e.display_name AS trainer_name
    FROM training_records tr
    JOIN org_units ou ON ou.id = tr.org_unit_id
    LEFT JOIN employees e ON e.id = tr.trainer_employee_id`;

function toTrainingRecord(row) {
  return {
    id: row.id,
    siteId: row.site_id,
    orgUnitId: row.org_unit_id,
    orgUnitName: row.org_unit_name,
    number: row.number,
    title: row.title,
    trainedOn: row.trained_on,
    durationHours: row.duration_hours,
    trainerEmployeeId: row.trainer_employee_id,
    trainerName: row.trainer_name,
    objective: row.objective,
    status: row.status,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

function requireTitle(value) {
  if (typeof value !== 'string' || value.trim() === '') {
    throw httpError(400, 'title is required');
  }
  return value.trim();
}

function requireTrainedOn(value) {
  if (typeof value !== 'string' || !DATE_PATTERN.test(value) || Number.isNaN(Date.parse(value))
      || new Date(value).toISOString().slice(0, 10) !== value) {
    throw httpError(400, 'trainedOn must be a date in YYYY-MM-DD form');
  }
  return value;
}

function requireDurationHours(value) {
  if (typeof value !== 'number' || !Number.isFinite(value) || value <= 0 || value > MAX_DURATION_HOURS) {
    throw httpError(400, `durationHours must be a number greater than 0 and at most ${MAX_DURATION_HOURS}`);
  }
  return value;
}

function optionalObjective(value) {
  if (value === undefined || value === null) return null;
  if (typeof value !== 'string') throw httpError(400, 'objective must be text');
  const trimmed = value.trim();
  return trimmed === '' ? null : trimmed;
}

// Validates the record's own facts in the shape a caller sends them. `trainerEmployeeId`
// is returned as an id string or null; whether that Employee exists is the route's
// question (it is another record's existence), not this file's.
function validateRaise(body) {
  const trainerRaw = body.trainerEmployeeId;
  let trainerEmployeeId = null;
  if (trainerRaw !== undefined && trainerRaw !== null) {
    trainerEmployeeId = parseId(trainerRaw);
    if (trainerEmployeeId === null) throw httpError(400, 'trainerEmployeeId must be a valid Employee id');
  }
  return {
    title: requireTitle(body.title),
    trainedOn: requireTrainedOn(body.trainedOn),
    durationHours: requireDurationHours(body.durationHours),
    trainerEmployeeId,
    objective: optionalObjective(body.objective)
  };
}

// A correction names only the facts it changes. Returns the validated subset.
const CORRECTABLE = ['title', 'trainedOn', 'durationHours', 'trainerEmployeeId', 'objective'];

function validateCorrection(body) {
  const changes = {};
  if (body.title !== undefined) changes.title = requireTitle(body.title);
  if (body.trainedOn !== undefined) changes.trainedOn = requireTrainedOn(body.trainedOn);
  if (body.durationHours !== undefined) changes.durationHours = requireDurationHours(body.durationHours);
  if (body.objective !== undefined) changes.objective = optionalObjective(body.objective);
  if (body.trainerEmployeeId !== undefined) {
    if (body.trainerEmployeeId === null) {
      changes.trainerEmployeeId = null;
    } else {
      const id = parseId(body.trainerEmployeeId);
      if (id === null) throw httpError(400, 'trainerEmployeeId must be a valid Employee id');
      changes.trainerEmployeeId = id;
    }
  }
  if (Object.keys(changes).length === 0) {
    throw httpError(400, `Name at least one of: ${CORRECTABLE.join(', ')}`);
  }
  return changes;
}

async function findTrainingRecord(id) {
  if (parseId(id) === null) return null;
  const { rows } = await getPool().query(`${SELECT_RECORD} WHERE tr.id = $1`, [id]);
  return rows[0] ? toTrainingRecord(rows[0]) : null;
}

async function getTrainingRecord(id) {
  const record = await findTrainingRecord(id);
  if (!record) throw notFound('Training record');
  return record;
}

// Issues the number and inserts, in one transaction. The Site is the Org Unit's
// own, read here so a number can never be issued against a Site the record
// does not sit in. The year is the creation year, as every other record's
// number is (`next_document_number(..., EXTRACT(YEAR FROM now()))`).
async function raiseTrainingRecord(accountId, orgUnitId, facts) {
  const id = await withActor(accountId, async (client) => {
    const { rows: [site] } = await client.query(
      `SELECT s.id, s.code
         FROM org_units ou
         JOIN sites s ON s.id = ou.site_id
        WHERE ou.id = $1`,
      [orgUnitId]
    );
    if (!site) throw notFound('Org Unit');

    const { rows: [numberRow] } = await client.query(
      `SELECT next_document_number('TR', $1, EXTRACT(YEAR FROM now())::int) AS number`,
      [site.code]
    );

    const { rows: [row] } = await client.query(
      `INSERT INTO training_records
         (site_id, org_unit_id, number, title, trained_on, duration_hours,
          trainer_employee_id, objective)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
       RETURNING id`,
      [site.id, orgUnitId, numberRow.number, facts.title, facts.trainedOn,
        facts.durationHours, facts.trainerEmployeeId, facts.objective]
    );
    return row.id;
  });
  return getTrainingRecord(id);
}

const COLUMN_FOR = {
  title: 'title',
  trainedOn: 'trained_on',
  durationHours: 'duration_hours',
  trainerEmployeeId: 'trainer_employee_id',
  objective: 'objective'
};

// Only ever a draft: the WHERE clause carries the status, so a record sent
// between the route's check and this write is refused here too, never changed.
async function correctTrainingRecord(accountId, id, changes) {
  const sets = [];
  const params = [id];
  for (const [field, value] of Object.entries(changes)) {
    params.push(value);
    sets.push(`${COLUMN_FOR[field]} = $${params.length}`);
  }
  const updated = await withActor(accountId, async (client) => {
    const { rowCount } = await client.query(
      `UPDATE training_records SET ${sets.join(', ')}
        WHERE id = $1 AND status = 'draft'`,
      params
    );
    return rowCount;
  });
  if (updated === 0) {
    throw httpError(409, 'A sent Training record cannot be changed here; correct it instead');
  }
  return getTrainingRecord(id);
}

// The register, newest training first. `viewer` is { accountId, isAdmin };
// `orgUnitPath` (an ltree path, resolved by the route) narrows to that Org
// Unit and everything beneath it; `from`/`to` are inclusive YYYY-MM-DD days
// on trained_on.
async function listTrainingRecords({ viewer, orgUnitPath = null, from = null, to = null }) {
  const params = [viewer.isAdmin, viewer.accountId];
  const conditions = [
    `(tr.status = 'sent'
      OR $1::boolean
      OR EXISTS (
           SELECT 1
             FROM app_user_org_units auo
             JOIN org_units granted ON granted.id = auo.org_unit_id
            WHERE auo.app_user_id = $2
              AND auo.can_write = TRUE
              AND ou.path <@ granted.path))`
  ];
  if (orgUnitPath !== null) {
    params.push(orgUnitPath);
    conditions.push(`ou.path <@ $${params.length}::ltree`);
  }
  if (from !== null) {
    params.push(from);
    conditions.push(`tr.trained_on >= $${params.length}::date`);
  }
  if (to !== null) {
    params.push(to);
    conditions.push(`tr.trained_on <= $${params.length}::date`);
  }
  const { rows } = await getPool().query(
    `${SELECT_RECORD}
      WHERE ${conditions.join(' AND ')}
      ORDER BY tr.trained_on DESC, tr.id DESC`,
    params
  );
  return rows.map(toTrainingRecord);
}

module.exports = {
  validateRaise,
  validateCorrection,
  findTrainingRecord,
  getTrainingRecord,
  raiseTrainingRecord,
  correctTrainingRecord,
  listTrainingRecords
};
