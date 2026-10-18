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
 * The Trainees on a record (#288) are here too: a record's own read carries
 * them in the order they were added, each naming the Employee's number and
 * name, and a count. Adding and removing one are draft-only writes — the
 * status is carried in the statement's WHERE clause, so a record sent between
 * the route's check and the write is refused, never changed. Whether the
 * Employee exists or has departed is the route's question.
 *
 * Sending (#289) is here: `sendTrainingRecord` is the only writer of status
 * 'sent', and a Trainee's answer (`answerTrainee`) and the Trainee's own queue
 * (`listTrainingToConfirm`) with it. Whether the caller may send is the
 * route's question; whether the answerer IS the Trainee is the route's too.
 * Correcting a sent record (#291) is not here.
 */

const { getPool, withActor } = require('../../platform/db');
const { httpError, notFound, parseId } = require('./errors');

const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;
const MAX_DURATION_HOURS = 9999.99;

const SELECT_RECORD = `
  SELECT tr.id, tr.site_id, tr.org_unit_id, tr.number, tr.title,
         tr.trained_on::text AS trained_on, tr.duration_hours::float8 AS duration_hours,
         tr.trainer_employee_id, tr.objective, tr.status,
         tr.sent_at, tr.sent_by_account_id,
         tr.created_at, tr.updated_at,
         ou.name AS org_unit_name, ou.path AS org_unit_path,
         e.display_name AS trainer_name,
         counts.trainee_count, counts.answered_count, counts.confirmed_count
    FROM training_records tr
    JOIN org_units ou ON ou.id = tr.org_unit_id
    LEFT JOIN employees e ON e.id = tr.trainer_employee_id
    CROSS JOIN LATERAL (
      SELECT count(*)::int AS trainee_count,
             count(tt.answer)::int AS answered_count,
             (count(*) FILTER (WHERE tt.answer = 'confirmed'))::int AS confirmed_count
        FROM training_trainees tt
       WHERE tt.training_record_id = tr.id
    ) counts`;

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
    sentAt: row.sent_at,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    ...toReading(row)
  };
}

// The record's reading of its Trainees' answers, computed from the rows on
// every read and never stored (ADR-0040's rule for an attendance sheet, for the
// same reason: "nobody has been asked yet" and "everybody declined" must stay
// different states). `fullyConfirmed` means EVERY Trainee answered `confirmed`:
// one declined answer keeps a record from reading as fully confirmed, even
// though every Trainee has answered it. The counts let a caller tell the three
// readings apart: nobody asked (a draft, or sent with answeredCount 0), partly
// or wholly answered with a decline (answeredCount - confirmedCount > 0), and
// fully confirmed. A record with no Trainee is never fully confirmed.
function toReading(row) {
  const traineeCount = row.trainee_count;
  const answeredCount = row.answered_count;
  const confirmedCount = row.confirmed_count;
  return {
    traineeCount,
    answeredCount,
    confirmedCount,
    declinedCount: answeredCount - confirmedCount,
    fullyConfirmed: traineeCount > 0 && confirmedCount === traineeCount
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

// A record's Trainees in the order they were added.
async function listTrainees(recordId) {
  const { rows } = await getPool().query(
    `SELECT tt.id, tt.employee_id, tt.created_at, e.employee_no, e.display_name,
            tt.answer, tt.answered_at, tt.answered_by_account_id, tt.answered_by_employee_id
       FROM training_trainees tt
       JOIN employees e ON e.id = tt.employee_id
      WHERE tt.training_record_id = $1
      ORDER BY tt.created_at, tt.id`,
    [recordId]
  );
  return rows.map((row) => ({
    id: row.id,
    employeeId: row.employee_id,
    employeeNo: row.employee_no,
    employeeName: row.display_name,
    addedAt: row.created_at,
    answer: row.answer,
    answeredAt: row.answered_at,
    // The door the answer came through, read from which actor column is set.
    answeredVia: row.answered_by_account_id !== null
      ? 'account'
      : (row.answered_by_employee_id !== null ? 'device' : null)
  }));
}

async function getTrainingRecord(id) {
  const record = await findTrainingRecord(id);
  if (!record) throw notFound('Training record');
  const trainees = await listTrainees(record.id);
  return { ...record, trainees };
}

const SENT_TRAINEES_MESSAGE = "A sent Training record's Trainees cannot be changed here; correct it instead";

// Adds one Employee to a draft. A second add of the same Employee is the
// UNIQUE constraint's refusal, mapped to a 409 here.
async function addTrainee(accountId, recordId, employeeId) {
  try {
    const inserted = await withActor(accountId, async (client) => {
      const { rowCount } = await client.query(
        `INSERT INTO training_trainees (training_record_id, employee_id)
         SELECT id, $2 FROM training_records WHERE id = $1 AND status = 'draft'`,
        [recordId, employeeId]
      );
      return rowCount;
    });
    if (inserted === 0) throw httpError(409, SENT_TRAINEES_MESSAGE);
  } catch (error) {
    if (error.code === '23505') {
      throw httpError(409, 'this Employee is already a Trainee on this Training record');
    }
    throw error;
  }
  return getTrainingRecord(recordId);
}

// Takes one Trainee off a draft. The row must belong to that record.
async function removeTrainee(accountId, recordId, traineeId) {
  const removed = await withActor(accountId, async (client) => {
    const { rowCount } = await client.query(
      `DELETE FROM training_trainees tt
        USING training_records tr
        WHERE tt.id = $2 AND tt.training_record_id = $1
          AND tr.id = tt.training_record_id AND tr.status = 'draft'`,
      [recordId, traineeId]
    );
    return rowCount;
  });
  if (removed === 0) {
    const { rows } = await getPool().query(
      'SELECT 1 FROM training_trainees WHERE id = $1 AND training_record_id = $2',
      [traineeId, recordId]
    );
    if (rows.length > 0) throw httpError(409, SENT_TRAINEES_MESSAGE);
    throw notFound('Trainee');
  }
  return getTrainingRecord(recordId);
}

async function findTrainee(recordId, traineeId) {
  if (parseId(traineeId) === null) return null;
  const { rows } = await getPool().query(
    'SELECT id FROM training_trainees WHERE id = $1 AND training_record_id = $2',
    [traineeId, recordId]
  );
  return rows[0] ?? null;
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

// What a record still lacks before it can be sent, in the Module's own words,
// or null when it is complete. A refusal here is a 409: the request is well
// formed, it is the record's current state that cannot take it (the same code
// a second send gets), as opposed to the 400 a malformed body gets.
function incompleteness(record) {
  if (!record.title) return 'A Training record needs a title before it is sent';
  if (!record.trainedOn) return 'A Training record needs a date of training before it is sent';
  if (!record.durationHours) return 'A Training record needs a duration before it is sent';
  if (record.trainerEmployeeId === null) return 'A Training record needs a trainer before it is sent';
  if (!record.objective) return 'A Training record needs an objective before it is sent';
  if (record.traineeCount === 0) return 'A Training record needs at least one Trainee before it is sent';
  return null;
}

const ALREADY_SENT_MESSAGE = 'This Training record has already been sent';

// Sends a draft: the three sent columns in one statement. `status = 'draft'`
// is in the WHERE clause so two sends racing, or a Trainee removed between
// the route's check and this write, cannot both win; the loser gets a 409.
// The trainer, objective and Trainee guards are in the statement too, so a
// record corrected or emptied between the check and the write is not sent.
async function sendTrainingRecord(accountId, id) {
  const sent = await withActor(accountId, async (client) => {
    const { rowCount } = await client.query(
      `UPDATE training_records
          SET status = 'sent', sent_at = now(), sent_by_account_id = $2
        WHERE id = $1 AND status = 'draft'
          AND trainer_employee_id IS NOT NULL AND objective IS NOT NULL
          AND EXISTS (SELECT 1 FROM training_trainees WHERE training_record_id = $1)`,
      [id, accountId]
    );
    return rowCount;
  });
  if (sent === 0) {
    const record = await getTrainingRecord(id); // 404s if it was discarded meanwhile.
    if (record.status === 'sent') throw httpError(409, ALREADY_SENT_MESSAGE);
    throw httpError(409, incompleteness(record) ?? 'This Training record cannot be sent');
  }
  return getTrainingRecord(id);
}

const ANSWERS = ['confirmed', 'declined'];

function requireAnswer(value) {
  if (!ANSWERS.includes(value)) {
    throw httpError(400, `answer must be one of: ${ANSWERS.join(', ')}`);
  }
  return value;
}

// One Trainee row with its record's status, for the answer's door.
async function findTraineeForAnswer(traineeId) {
  if (parseId(traineeId) === null) return null;
  const { rows } = await getPool().query(
    `SELECT tt.id, tt.employee_id, tt.training_record_id, tr.status
       FROM training_trainees tt
       JOIN training_records tr ON tr.id = tt.training_record_id
      WHERE tt.id = $1`,
    [traineeId]
  );
  if (!rows[0]) return null;
  return {
    id: rows[0].id,
    employeeId: rows[0].employee_id,
    recordId: rows[0].training_record_id,
    recordStatus: rows[0].status
  };
}

// Writes (or changes) a Trainee's answer through the Account door: an UPDATE
// of the same row, so a changed answer is audited and never a second row. The
// Employee-actor column is cleared, so the CHECK's "exactly one actor" holds
// even when a floor device answered earlier. Only ever a sent record.
async function answerTrainee(accountId, traineeId, answer) {
  const row = await withActor(accountId, async (client) => {
    const { rows } = await client.query(
      `UPDATE training_trainees tt
          SET answer = $2, answered_at = now(),
              answered_by_account_id = $3, answered_by_employee_id = NULL
         FROM training_records tr
        WHERE tt.id = $1 AND tr.id = tt.training_record_id AND tr.status = 'sent'
        RETURNING tt.training_record_id`,
      [traineeId, answer, accountId]
    );
    return rows[0];
  });
  if (!row) throw notFound('Trainee');
  return getTrainingRecord(row.training_record_id);
}

// The Employee's own outstanding answers: sent records they are a Trainee on
// and have not yet answered. Oldest first by when the record was sent (the one
// that has waited longest leads), then by the day of training, then by row.
async function listTrainingToConfirm(employeeId) {
  if (employeeId === null || employeeId === undefined) return [];
  const { rows } = await getPool().query(
    `SELECT tt.id AS trainee_id, tr.id, tr.number, tr.title,
            tr.trained_on::text AS trained_on, tr.duration_hours::float8 AS duration_hours,
            tr.objective, tr.sent_at, ou.name AS org_unit_name,
            e.display_name AS trainer_name
       FROM training_trainees tt
       JOIN training_records tr ON tr.id = tt.training_record_id
       JOIN org_units ou ON ou.id = tr.org_unit_id
       LEFT JOIN employees e ON e.id = tr.trainer_employee_id
      WHERE tt.employee_id = $1 AND tt.answer IS NULL AND tr.status = 'sent'
      ORDER BY tr.sent_at, tr.trained_on, tt.id`,
    [employeeId]
  );
  return rows.map((row) => ({
    traineeId: row.trainee_id,
    id: row.id,
    number: row.number,
    title: row.title,
    trainedOn: row.trained_on,
    durationHours: row.duration_hours,
    trainerName: row.trainer_name,
    objective: row.objective,
    orgUnitName: row.org_unit_name,
    sentAt: row.sent_at
  }));
}

module.exports = {
  incompleteness,
  sendTrainingRecord,
  requireAnswer,
  findTraineeForAnswer,
  answerTrainee,
  listTrainingToConfirm,
  validateRaise,
  validateCorrection,
  findTrainingRecord,
  getTrainingRecord,
  raiseTrainingRecord,
  addTrainee,
  removeTrainee,
  findTrainee,
  correctTrainingRecord,
  listTrainingRecords
};
