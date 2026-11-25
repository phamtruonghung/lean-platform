/*
 * Marking a submitted Assessment (issue #588, ADR-0068, slice 4): the marking
 * queue, the paper with its key, the point award and the result.
 *
 * This file owns three things and one rule:
 *
 *   - **The queue** — the `submitted` Attempts whose process is inside the
 *     caller's write reach, oldest first, each with its count of "Khác" answers.
 *     An Other answer is scored 0 by the machine and flagged (spec section 10,
 *     option A); the count is what puts it in front of the Marker.
 *   - **The paper with the key** — `readMarkingPaper` is the only read in the
 *     Module that selects `correct_option`, `points` and `explanation` of a
 *     drawn paper. It is behind `PPL_ASSESSMENT_MARK` and the reach check, in
 *     the same file, so there is one place to read rather than a rule each
 *     route re-states.
 *   - **The award** — `markAttempt` writes the per-Answer points, the final
 *     score (`final_score = sum(points)`), the Marker and the moment, and moves
 *     the Attempt to `marked`. `score` is the machine's number and is never
 *     rewritten; the award is a second number (`final_score`), which is what
 *     makes "6 before the award, 7 after" a record rather than a lost fact.
 *     Every changed Answer row is a real `UPDATE`, so `attach_audit` writes one
 *     `audit_log` row per changed point with `old_values`/`new_values`.
 *   - **The result** — `readResult` answers the score, the final score, the
 *     verdict derived at read (`final_score >= pass_mark`, never stored) and
 *     every Question with the candidate's Answer, the key and the explanation.
 *
 * **The score-field rule (spec section 3.14) is a SQL predicate**
 * (`scoreVisibleSql`), evaluated by the database in the statement that selects
 * the row: the person themselves, an administrator, or a `MARK`/`CHANGE` holder
 * whose write Grant covers the Attempt's own Org Unit. `assessments.js`
 * requires it from here (one-way: nothing here requires `assessments.js`), so
 * the register, the detail read and the result answer the question the same way
 * and a score the caller may not read is never fetched into the process.
 *
 * Nothing here asks who is calling for a write: the routes do that
 * (AGENTS.md section 6 — existence first, then scope, then the body), and this
 * file is handed an Account it can ask a reach question about and ids it may
 * assume are real.
 */

const { withActor } = require('../../platform/db');
const { httpError, notFound, OUTSIDE_GRANTED_ORG_UNITS } = require('./errors');
const authorization = require('./authorization');
const roles = require('./roles');
const timing = require('./assessment-sweep');

// The register's bound, as every register in this repo is bounded (ADR-0026).
const LIST_LIMIT = 200;
const NOTE_MAX = 2000;

// The two codes whose holder may see a score, per section 3.14.
const MARK_CODES = ['PPL_ASSESSMENT_MARK', 'PPL_ASSESSMENT_CHANGE'];

const ALREADY_MARKED = 'this Assessment has already been marked';

// ---------------------------------------------------------------------------
// Section 3.14: who may read a score
// ---------------------------------------------------------------------------

// What the score question needs to know about the caller, asked once per read:
// who they are, whether they are an administrator and whether they hold MARK or
// CHANGE. The Org Unit half of the rule is answered by the database.
async function scoreViewer(account) {
  const held = new Set((await roles.effectivePermissions(account)).map((row) => row.code));
  return {
    accountId: account.id,
    employeeId: account.employeeId === undefined ? null : account.employeeId,
    isAdmin: authorization.isAdmin(account),
    holdsMarkCodes: MARK_CODES.some((code) => held.has(code)),
    // The two codes apart, for the detail's `viewerMayChange` / `viewerMayMark`.
    holdsChange: held.has('PPL_ASSESSMENT_CHANGE'),
    holdsMark: held.has('PPL_ASSESSMENT_MARK')
  };
}

const NO_VIEWER = { accountId: null, employeeId: null, isAdmin: false, holdsMarkCodes: false };

// Spec section 7.1's predicate as a SQL boolean over the alias `at`
// (assessment_attempts). Pushes its four parameters onto `params` and returns
// the expression.
function scoreVisibleSql(viewer, params) {
  const who = viewer ?? NO_VIEWER;
  const first = params.length;
  params.push(who.employeeId, who.isAdmin === true, who.holdsMarkCodes === true, who.accountId);
  const employee = `$${first + 1}`;
  const admin = `$${first + 2}`;
  const codes = `$${first + 3}`;
  const account = `$${first + 4}`;
  return `(COALESCE(at.employee_id = ${employee}::bigint, FALSE)
      OR ${admin}::boolean
      OR (${codes}::boolean AND EXISTS (
            SELECT 1
              FROM app_user_org_units auo
              JOIN org_units granted ON granted.id = auo.org_unit_id
              JOIN org_units attempt_ou ON attempt_ou.id = at.org_unit_id
             WHERE auo.app_user_id = ${account}::bigint
               AND auo.can_write
               AND attempt_ou.path <@ granted.path)))`;
}

// The Marker's three doors are bounded by the PROCESS the paper was drawn from
// (spec section 7.1), not by where the candidate works: a Team Leader who set
// the Assessment at a process marks everyone assigned to it. `reach` is
// `writeReachOrgUnitIds`: null for an administrator, else a Set of ids as text
// that already includes every descendant of each granted Org Unit.
function reachAllows(reach, row) {
  return reach === null || reach.has(String(row.process_org_unit_id));
}

// ---------------------------------------------------------------------------
// Reading one Attempt's marking context
// ---------------------------------------------------------------------------

const CONTEXT_COLUMNS = `at.id, at.assessment_id, at.employee_id, at.attempt_no,
  at.org_unit_id, at.org_unit_resolved_on, at.status, at.started_at, at.deadline_at,
  at.submitted_at, at.submitted_late, at.score, at.final_score, at.marked_at,
  at.marked_by_account_id, at.marking_note, at.created_at, at.updated_at`;

const contextSql = (extra) => `
  SELECT ${CONTEXT_COLUMNS}${extra},
         a.number, a.title, a.question_count, a.pass_mark,
         a.org_unit_id AS process_org_unit_id,
         proc.name AS process_name,
         ou.name AS org_unit_name,
         e.display_name AS employee_name,
         marker.display_name AS marked_by_name
    FROM assessment_attempts at
    JOIN assessments a ON a.id = at.assessment_id
    JOIN org_units proc ON proc.id = a.org_unit_id
    JOIN org_units ou ON ou.id = at.org_unit_id
    JOIN employees e ON e.id = at.employee_id
    LEFT JOIN app_users marker ON marker.id = at.marked_by_account_id
   WHERE at.id = $1`;

// `viewer`, when given, adds `score_visible`: section 3.14's predicate for this
// Attempt, evaluated by the database.
async function attemptContext(client, attemptId, { lock = false, viewer } = {}) {
  const params = [attemptId];
  const extra = viewer === undefined ? '' : `, ${scoreVisibleSql(viewer, params)} AS score_visible`;
  const { rows: [row] } = await client.query(
    `${contextSql(extra)}${lock ? ' FOR UPDATE OF at' : ''}`,
    params
  );
  return row ?? null;
}

// The Attempt block every marking read answers with. `score` is the machine's
// number and `finalScore` the Marker's; both are null until the Attempt is
// marked unless the caller is the Marker's own paper (`readMarkingPaper`).
function toMarkedAttempt(row) {
  return {
    id: row.id,
    assessmentId: row.assessment_id,
    employeeId: row.employee_id,
    employeeName: row.employee_name,
    attemptNo: row.attempt_no,
    orgUnitId: row.org_unit_id,
    orgUnitName: row.org_unit_name,
    status: row.status,
    startedAt: row.started_at ?? null,
    deadlineAt: row.deadline_at ?? null,
    submittedAt: row.submitted_at ?? null,
    submittedLate: row.submitted_late === true,
    markedAt: row.marked_at ?? null,
    markedByName: row.marked_by_name ?? null,
    markingNote: row.marking_note ?? null,
    score: row.status === 'marked' ? (row.score ?? null) : null,
    finalScore: row.status === 'marked' ? (row.final_score ?? null) : null,
    assessmentNumber: row.number,
    assessmentTitle: row.title,
    questionCount: row.question_count,
    passMark: row.pass_mark,
    processName: row.process_name
  };
}

// The paper as the Marker sees it: the stem, three Options, the key, the
// explanation, the candidate's Answer and the point on it.
async function paperWithKey(client, attemptId) {
  const { rows } = await client.query(
    `SELECT position, question_text, option_a, option_b, option_c,
            correct_option, explanation, chosen_option, other_text, points
       FROM assessment_attempt_questions
      WHERE attempt_id = $1
      ORDER BY position`,
    [attemptId]
  );
  return rows.map((row) => ({
    position: row.position,
    questionText: row.question_text,
    optionA: row.option_a,
    optionB: row.option_b,
    optionC: row.option_c,
    correctOption: row.correct_option,
    explanation: row.explanation ?? null,
    chosenOption: row.chosen_option ?? null,
    otherText: row.other_text ?? null,
    points: row.points
  }));
}

// ---------------------------------------------------------------------------
// The queue
// ---------------------------------------------------------------------------

// `submitted` Attempts whose process is in the caller's write reach, oldest
// first. Two counts are not scores and are never hidden: how many "Khác"
// answers the paper holds (what the Marker is here for) and whether the server
// finalised it late.
async function markingQueue(account, { orgUnitId = null } = {}) {
  const reach = await authorization.writeReachOrgUnitIds({ account });
  const params = [];
  const conditions = ["at.status = 'submitted'"];
  // `orgUnitId` narrows to one process; the reach is the process too.
  if (orgUnitId !== null) {
    params.push(orgUnitId);
    conditions.push(`a.org_unit_id = $${params.length}`);
  }
  if (reach !== null) {
    params.push([...reach]);
    conditions.push(`a.org_unit_id = ANY($${params.length}::bigint[])`);
  }
  const where = conditions.join(' AND ');

  // Papers past their deadline are finalised before the queue is read, or an
  // abandoned paper would never reach it: the Assessments in scope that hold
  // one, swept by id (never the table).
  const { rows: overdue } = await withActor(null, (client) => client.query(
    `SELECT DISTINCT at.assessment_id
       FROM assessment_attempts at
       JOIN assessments a ON a.id = at.assessment_id
      WHERE at.status = 'in_progress' AND now() >= at.deadline_at
        AND ${conditions.slice(1).join(' AND ') || 'TRUE'}`,
    params
  ));
  await timing.sweepAssessments(overdue.map((row) => row.assessment_id));

  const { rows } = await withActor(null, (client) => client.query(
    `SELECT ${CONTEXT_COLUMNS}, a.number, a.title, a.question_count, a.pass_mark,
            a.org_unit_id AS process_org_unit_id,
            proc.name AS process_name, ou.name AS org_unit_name,
            e.display_name AS employee_name,
            (SELECT count(*)::int FROM assessment_attempt_questions q
              WHERE q.attempt_id = at.id AND q.other_text IS NOT NULL) AS other_answer_count
       FROM assessment_attempts at
       JOIN assessments a ON a.id = at.assessment_id
       JOIN org_units proc ON proc.id = a.org_unit_id
       JOIN org_units ou ON ou.id = at.org_unit_id
       JOIN employees e ON e.id = at.employee_id
      WHERE ${where}
      ORDER BY at.submitted_at, at.id
      LIMIT ${LIST_LIMIT}`,
    params
  ));

  const { rows: [total] } = await withActor(null, (client) => client.query(
    `SELECT count(*)::int AS n
       FROM assessment_attempts at
       JOIN assessments a ON a.id = at.assessment_id
      WHERE ${where}`,
    params
  ));

  return {
    attempts: rows.map((row) => ({
      id: row.id,
      assessmentId: row.assessment_id,
      assessmentNumber: row.number,
      assessmentTitle: row.title,
      employeeId: row.employee_id,
      employeeName: row.employee_name,
      attemptNo: row.attempt_no,
      orgUnitId: row.org_unit_id,
      orgUnitName: row.org_unit_name,
      processName: row.process_name,
      questionCount: row.question_count,
      passMark: row.pass_mark,
      submittedAt: row.submitted_at,
      submittedLate: row.submitted_late === true,
      otherAnswerCount: row.other_answer_count
    })),
    total: total.n,
    truncated: total.n > rows.length
  };
}

// ---------------------------------------------------------------------------
// Marking one paper
// ---------------------------------------------------------------------------

// One 404-or-403 answer for the Marker's three routes: existence first, then
// the write reach, and nothing about the body until both hold.

async function readMarkingPaper(account, attemptId) {
  await timing.sweepAttempt(attemptId);
  // The reach is asked outside the transaction: it is a question about the
  // caller's Grants, and a second pool connection inside an open transaction
  // buys nothing.
  const reach = await authorization.writeReachOrgUnitIds({ account });
  return withActor(null, async (client) => {
    const row = await attemptContext(client, attemptId);
    if (!row) throw notFound('Assessment attempt');
    if (!reachAllows(reach, row)) throw httpError(403, OUTSIDE_GRANTED_ORG_UNITS);
    const questions = await paperWithKey(client, attemptId);
    return {
      attempt: {
        ...toMarkedAttempt(row),
        // The Marker reads both numbers, including the machine's before the award.
        score: row.score ?? null,
        finalScore: row.final_score ?? null,
        passed: row.final_score === null || row.final_score === undefined
          ? null
          : row.final_score >= row.pass_mark
      },
      questions
    };
  });
}

function requireNoteText(value, field) {
  if (typeof value !== 'string') throw httpError(400, `${field} must be text`);
  const trimmed = value.trim();
  if ([...trimmed].length > NOTE_MAX) {
    throw httpError(400, `${field} must be at most ${NOTE_MAX} characters`);
  }
  return trimmed === '' ? null : trimmed;
}

// `{ answers: [{ position, points, note? }], note }`. A partial list is what a
// Marker actually sends — the answers they changed — so an unnamed position
// keeps the machine's point. `note` at the top is optional: marking a paper
// whose Answers are all correct needs no sentence, and requiring one turns a
// record into a form. Spec section 10 lets the Marker change ANY Answer's
// point (a keyed answer on a wrong key is the other case), so a point on a
// non-Other answer is not refused.
function validateMarking(body) {
  const source = body ?? {};
  const note = source.note === undefined || source.note === null
    ? null
    : requireNoteText(source.note, 'note');

  const raw = source.answers === undefined || source.answers === null ? [] : source.answers;
  if (!Array.isArray(raw)) throw httpError(400, 'answers must be an array');

  const answers = raw.map((entry, index) => {
    if (entry === null || typeof entry !== 'object' || Array.isArray(entry)) {
      throw httpError(400, `answers[${index}] must be an object`);
    }
    const position = entry.position;
    if (!Number.isInteger(position) || position < 1 || position > 15) {
      throw httpError(400, `answers[${index}].position must be a whole number between 1 and 15`);
    }
    const points = entry.points;
    if (points !== 0 && points !== 1) {
      throw httpError(400, `answers[${index}].points must be 0 or 1`);
    }
    const answerNote = entry.note === undefined || entry.note === null
      ? null
      : requireNoteText(entry.note, `answers[${index}].note`);
    return { position, points, note: answerNote };
  });

  const seen = new Set();
  for (const answer of answers) {
    if (seen.has(answer.position)) {
      throw httpError(400, `position ${answer.position} is named twice`);
    }
    seen.add(answer.position);
  }

  // There is no column for a per-Answer note (and a migration is not this
  // slice's to add), so the Marker's sentences are kept in the Attempt's one
  // `marking_note`, the top-level note first, so an award's reason survives.
  const lines = [];
  if (note !== null) lines.push(note);
  for (const answer of answers) {
    if (answer.note !== null) lines.push(`#${answer.position}: ${answer.note}`);
  }
  const markingNote = lines.length === 0 ? null : lines.join('\n');
  if (markingNote !== null && [...markingNote].length > NOTE_MAX) {
    throw httpError(400, `the marking note must be at most ${NOTE_MAX} characters`);
  }
  return { answers, markingNote };
}

// The award. One transaction: lock the Attempt, prove the reach and the state,
// move the points that differ, then write the final score, the Marker, the
// moment and the note.
async function markAttempt(account, attemptId, body) {
  await timing.sweepAttempt(attemptId);
  const reach = await authorization.writeReachOrgUnitIds({ account });
  const result = await withActor(account.id, async (client) => {
    const row = await attemptContext(client, attemptId, { lock: true });
    if (!row) throw notFound('Assessment attempt');
    if (!reachAllows(reach, row)) throw httpError(403, OUTSIDE_GRANTED_ORG_UNITS);
    if (row.status === 'marked') throw httpError(409, ALREADY_MARKED);
    if (row.status !== 'submitted') {
      throw httpError(409, 'this Assessment is not awaiting marking');
    }

    const { answers, markingNote } = validateMarking(body);

    // A position the paper does not hold is a 400 naming it rather than a
    // silent no-op: the Marker's award would otherwise vanish.
    const { rows: onPaper } = await client.query(
      'SELECT position, points FROM assessment_attempt_questions WHERE attempt_id = $1',
      [attemptId]
    );
    const known = new Map(onPaper.map((entry) => [entry.position, entry.points]));
    for (const answer of answers) {
      if (!known.has(answer.position)) {
        throw httpError(400, `no Question at position ${answer.position} on this paper`);
      }
    }

    for (const answer of answers) {
      if (known.get(answer.position) === answer.points) continue;
      await client.query(
        `UPDATE assessment_attempt_questions
            SET points = $3, marked_by_account_id = $4, marked_at = now()
          WHERE attempt_id = $1 AND position = $2`,
        [attemptId, answer.position, answer.points, account.id]
      );
    }

    const { rows: [marked] } = await client.query(
      `UPDATE assessment_attempts at
          SET status = 'marked',
              marked_at = now(),
              marked_by_account_id = $2,
              marking_note = $3,
              final_score = (SELECT COALESCE(sum(points), 0)::int
                               FROM assessment_attempt_questions q
                              WHERE q.attempt_id = at.id)
        WHERE at.id = $1 AND at.status = 'submitted'
        RETURNING at.id`,
      [attemptId, account.id, markingNote]
    );
    // The row lock makes this unreachable in practice; the guard is what keeps
    // a second call a 409 rather than a second award if the lock is dropped.
    if (!marked) throw httpError(409, ALREADY_MARKED);

    return { id: marked.id };
  });

  return readMarkingPaper(account, result.id);
}

// ---------------------------------------------------------------------------
// The result
// ---------------------------------------------------------------------------

// Before `marked` there is nothing to show and the summary would be a lie, so
// this refuses with the one sentence a Screen can print (spec section 3.12).
const NOT_MARKED_YET = 'this Assessment has not been marked yet';

// The result is a score, so it follows section 3.14 exactly: the person, an
// administrator, or a MARK/CHANGE holder whose write Grant covers the Attempt's
// node. The database answers (`score_visible`); anyone else is a 403.
async function readResult(account, attemptId) {
  return readResultFor(await scoreViewer(account), attemptId);
}

// The same read for a viewer already described: the floor door has no Account,
// so its viewer is the Employee alone (the first line of the section 3.14
// predicate) and nobody else's Attempt is ever visible through it.
async function readResultFor(viewer, attemptId) {
  await timing.sweepAttempt(attemptId);
  return withActor(null, async (client) => {
    const row = await attemptContext(client, attemptId, { viewer });
    if (!row) throw notFound('Assessment attempt');
    if (row.score_visible !== true) throw httpError(403, OUTSIDE_GRANTED_ORG_UNITS);
    if (row.status !== 'marked') throw httpError(409, NOT_MARKED_YET);

    const questions = await paperWithKey(client, attemptId);
    const finalScore = row.final_score;
    return {
      attempt: toMarkedAttempt(row),
      // Pass or fail is derived here, never stored (spec section 3.13): moving
      // a pass mark later must move what the record says about an old paper.
      verdict: {
        score: row.score ?? null,
        finalScore,
        passMark: row.pass_mark,
        questionCount: row.question_count,
        passed: finalScore !== null && finalScore >= row.pass_mark
      },
      questions
    };
  });
}

module.exports = {
  scoreViewer,
  scoreVisibleSql,
  markingQueue,
  readMarkingPaper,
  markAttempt,
  readResult,
  readResultFor,
  validateMarking,
  NOT_MARKED_YET,
  ALREADY_MARKED
};
