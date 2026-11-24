/*
 * Assessments, Attempts and the frozen paper (issue #588, ADR-0068, slice 3).
 *
 * This file owns the SQL, the row shapes, the validation of an Assessment's own
 * six facts and every rule about time. `assessment-routes.js` owns Express, the
 * permission codes and the Org Unit scope question; it hands this file ids it
 * has already checked and never a request. Nothing here asks who is calling
 * (AGENTS.md section 6) and no other Module is required (ADR-0006).
 *
 * **The server owns the clock, to the letter.** `started_at` and
 * `deadline_at` are written once, in the transaction that sets them, from the
 * database's own `now()`: `deadline_at = started_at + minutes * interval '1
 * minute'`. An answer past the deadline is refused; the server finalises the
 * Attempt itself and marks it `submitted_late`. No route anywhere accepts a
 * timestamp from a client.
 *
 * **No cron (spec section 5.2).** Time-caused transitions happen lazily, in an
 * `UPDATE ... WHERE` at the top of every Attempt read and every Answer write,
 * in the same transaction as the read or the write: idempotent, correct after a
 * restart, and the paper closes when somebody looks at it, which is when it
 * matters. `finalisePastDeadline` is that sweep, scoped to the Attempt being
 * looked at; `finaliseMine` is the same rule for a list of the caller's own.
 *
 * **The draw happens at Attempt start, not at creation (spec section 11).**
 * `ORDER BY random() LIMIT $n` inside the transaction that sets `started_at`,
 * without replacement (`UNIQUE (attempt_id, question_id)`), frozen onto
 * `assessment_attempt_questions` as a snapshot: the stem, three Options, the key
 * and the explanation are copied, so correcting the bank changes future draws
 * only.
 *
 * **The key never leaves this file before marking.** `toPaper` projects the
 * drawn rows and simply does not select `correct_option`, `explanation` or
 * `points`; a route cannot leak what it is never handed.
 *
 * **One paper per Attempt, and `start` is idempotent on a refresh.** The
 * Attempt row is locked `FOR UPDATE` first, so two concurrent starts cannot
 * draw two papers: the second reads `in_progress` and returns the first one.
 *
 * **A thin bank is a hard refusal, never a short paper.** A 7-question paper
 * marked out of 10 is a silent lie about a person's score, so both `/assign`
 * and `/start` refuse with the count and, where the bank actually sits, the
 * neighbouring node's count (spec section 5.1).
 *
 * **Assign is all-or-nothing.** The group is expanded, every Employee's own Org
 * Unit resolved, a short bank and an already-assigned Employee both refused
 * with a 409 naming the row, and every refusal rolls the transaction back: a
 * half-assigned Assessment is a hole in the record its creator cannot see.
 */

const { getPool, withActor } = require('../../platform/db');
const { httpError, notFound } = require('./errors');

const QUESTION_COUNTS = [10, 15];
const MIN_MINUTES = 5;
const MAX_MINUTES = 120;
const DEFAULT_MINUTES_PER_QUESTION = 2;
const PASS_RATIO = 0.8;
const MIN_ATTEMPTS = 1;
const MAX_ATTEMPTS = 3;
const TITLE_MIN = 3;
const TITLE_MAX = 200;
const OTHER_MAX = 2000;

const OPTIONS = ['A', 'B', 'C'];

// The register is bounded, as every other register in this repo is (ADR-0026):
// past this many rows the answer says `truncated` and the caller narrows.
const LIST_LIMIT = 200;

const ASSESSMENT_COLUMNS = `a.id, a.site_id, a.org_unit_id, a.number, a.title,
  a.question_count, a.minutes, a.pass_mark, a.attempts_allowed, a.due_on,
  a.status, a.created_at, a.updated_at`;

const ATTEMPT_COLUMNS = `at.id, at.assessment_id, at.employee_id, at.attempt_no,
  at.org_unit_id, at.org_unit_resolved_on, at.status, at.started_at,
  at.deadline_at, at.submitted_at, at.submitted_late, at.marked_at,
  at.marked_by_account_id, at.marking_note, at.created_at, at.updated_at`;

function lengthOf(value) {
  return [...value].length;
}

function toAssessment(row) {
  return {
    id: row.id,
    siteId: row.site_id,
    orgUnitId: row.org_unit_id,
    number: row.number,
    title: row.title,
    questionCount: row.question_count,
    minutes: row.minutes,
    passMark: row.pass_mark,
    attemptsAllowed: row.attempts_allowed,
    dueOn: row.due_on === null || row.due_on === undefined ? null : toIsoDate(row.due_on),
    status: row.status,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

// A DATE comes back from `pg` as a local-midnight Date; a calendar day is what
// the caller sent and what it gets back, never a timestamp with a zone.
function toIsoDate(value) {
  if (typeof value === 'string') return value.slice(0, 10);
  const year = value.getFullYear();
  const month = String(value.getMonth() + 1).padStart(2, '0');
  const day = String(value.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function toAttempt(row) {
  return {
    id: row.id,
    assessmentId: row.assessment_id,
    employeeId: row.employee_id,
    attemptNo: row.attempt_no,
    orgUnitId: row.org_unit_id,
    orgUnitResolvedOn: toIsoDate(row.org_unit_resolved_on),
    status: row.status,
    startedAt: row.started_at ?? null,
    deadlineAt: row.deadline_at ?? null,
    submittedAt: row.submitted_at ?? null,
    submittedLate: row.submitted_late === true,
    markedAt: row.marked_at ?? null,
    markingNote: row.marking_note ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

// ---------------------------------------------------------------------------
// An Assessment's six facts
// ---------------------------------------------------------------------------

function requireText(body, field, { min = 1, max }) {
  const value = body[field];
  if (typeof value !== 'string') throw httpError(400, `${field} is required`);
  const trimmed = value.trim();
  if (lengthOf(trimmed) < min) {
    throw httpError(400, min > 1 ? `${field} must be at least ${min} characters` : `${field} is required`);
  }
  if (lengthOf(trimmed) > max) throw httpError(400, `${field} must be at most ${max} characters`);
  return trimmed;
}

function requireInteger(body, field, { min, max }) {
  const value = body[field];
  if (typeof value !== 'number' || !Number.isInteger(value)) {
    throw httpError(400, `${field} must be a whole number`);
  }
  if (value < min || value > max) throw httpError(400, `${field} must be between ${min} and ${max}`);
  return value;
}

function optionalInteger(body, field, fallback, { min, max }) {
  if (body[field] === undefined || body[field] === null) return fallback;
  return requireInteger(body, field, { min, max });
}

// A calendar day, `YYYY-MM-DD`, or null. Anything else is a 400 rather than a
// database error: `due_on` is compared against the Site's own date (ADR-0048)
// and a timestamp here would silently mean a different day.
function optionalDate(body, field) {
  const value = body[field];
  if (value === undefined || value === null) return null;
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value.trim())) {
    throw httpError(400, `${field} must be a calendar day, YYYY-MM-DD`);
  }
  const day = value.trim();
  // A shape check is not a date: `2026-13-40` matches the regex and would be a
  // 500 from Postgres. Round-trip through `Date` so the refusal names the field.
  const parsed = new Date(`${day}T00:00:00Z`);
  if (Number.isNaN(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== day) {
    throw httpError(400, `${field} must be a calendar day, YYYY-MM-DD`);
  }
  return day;
}

// The six facts, as created and as a draft is corrected: full replacement, one
// validator. `minutes` defaults to 2 per Question (20 for 10, 30 for 15) and
// `passMark` to 80 % rounded up — both stored, so moving the default later
// cannot move a deadline or a pass mark that already exists.
function validateAssessmentFacts(body) {
  const source = body ?? {};
  const title = requireText(source, 'title', { min: TITLE_MIN, max: TITLE_MAX });

  const questionCount = requireInteger(source, 'questionCount', { min: 10, max: 15 });
  if (!QUESTION_COUNTS.includes(questionCount)) {
    throw httpError(400, `questionCount must be one of ${QUESTION_COUNTS.join(', ')}`);
  }

  const minutes = optionalInteger(source, 'minutes', questionCount * DEFAULT_MINUTES_PER_QUESTION, {
    min: MIN_MINUTES,
    max: MAX_MINUTES
  });
  const passMark = optionalInteger(source, 'passMark', Math.ceil(questionCount * PASS_RATIO), {
    min: 1,
    max: questionCount
  });
  const attemptsAllowed = optionalInteger(source, 'attemptsAllowed', 1, {
    min: MIN_ATTEMPTS,
    max: MAX_ATTEMPTS
  });
  const dueOn = optionalDate(source, 'dueOn');

  return { title, questionCount, minutes, passMark, attemptsAllowed, dueOn };
}

// ---------------------------------------------------------------------------
// Reading
// ---------------------------------------------------------------------------

async function findAssessment(id) {
  const { rows } = await getPool().query(
    `SELECT ${ASSESSMENT_COLUMNS}, ou.name AS org_unit_name, s.code AS site_code
       FROM assessments a
       JOIN org_units ou ON ou.id = a.org_unit_id
       JOIN sites s ON s.id = a.site_id
      WHERE a.id = $1`,
    [id]
  );
  if (!rows[0]) return null;
  return {
    ...toAssessment(rows[0]),
    orgUnitName: rows[0].org_unit_name,
    siteCode: rows[0].site_code
  };
}

async function getAssessment(id) {
  const assessment = await findAssessment(id);
  if (!assessment) throw notFound('Assessment');
  const attempts = await listAttempts(id);
  return { ...assessment, attempts };
}

// The Attempts of one Assessment, with the person and the node each answers
// to. `otherAnswerCount` is a count, never a score, so it is not hidden; the
// score fields are not selected at all in this slice (spec section 3.12 — a
// score is not shown before marking, and marking is slice 4).
async function listAttempts(assessmentId) {
  const { rows } = await getPool().query(
    `SELECT ${ATTEMPT_COLUMNS}, e.display_name AS employee_name,
            ou.name AS org_unit_name,
            (SELECT count(*)::int FROM assessment_attempt_questions q
              WHERE q.attempt_id = at.id AND q.other_text IS NOT NULL) AS other_answer_count,
            (SELECT count(*)::int FROM assessment_attempt_questions q
              WHERE q.attempt_id = at.id AND q.chosen_option IS NULL AND q.other_text IS NULL) AS blank_count
       FROM assessment_attempts at
       JOIN employees e ON e.id = at.employee_id
       JOIN org_units ou ON ou.id = at.org_unit_id
      WHERE at.assessment_id = $1
      ORDER BY e.display_name, at.attempt_no`,
    [assessmentId]
  );
  return rows.map((row) => ({
    ...toAttempt(row),
    employeeName: row.employee_name,
    orgUnitName: row.org_unit_name,
    otherAnswerCount: row.other_answer_count,
    blankCount: row.blank_count
  }));
}

// The register: number, title, process, size, due date, status and the sitting
// counts as separate fields — `assigned` (nobody has started), `running`,
// `awaitingMarking` (submitted, not yet marked), `marked`. Counts are never
// hidden, whatever the caller's reach.
async function listAssessments({ orgUnitId = null, status = null, mine = null, accountId = null }) {
  const params = [];
  const conditions = [];
  if (orgUnitId !== null) {
    params.push(orgUnitId);
    conditions.push(`a.org_unit_id = $${params.length}`);
  }
  if (status !== null) {
    params.push(status);
    conditions.push(`a.status = $${params.length}`);
  }
  if (mine === true && accountId !== null) {
    params.push(accountId);
    conditions.push(`a.created_by = $${params.length}`);
  }
  const where = conditions.length === 0 ? 'TRUE' : conditions.join(' AND ');

  const { rows } = await getPool().query(
    `SELECT ${ASSESSMENT_COLUMNS}, ou.name AS org_unit_name,
            counts.assigned_count, counts.running_count,
            counts.awaiting_marking_count, counts.marked_count
       FROM assessments a
       JOIN org_units ou ON ou.id = a.org_unit_id
       LEFT JOIN LATERAL (
         SELECT count(*) FILTER (WHERE x.status = 'assigned')::int AS assigned_count,
                count(*) FILTER (WHERE x.status = 'in_progress')::int AS running_count,
                count(*) FILTER (WHERE x.status = 'submitted')::int AS awaiting_marking_count,
                count(*) FILTER (WHERE x.status = 'marked')::int AS marked_count
           FROM assessment_attempts x
          WHERE x.assessment_id = a.id
       ) counts ON TRUE
      WHERE ${where}
      ORDER BY a.created_at DESC, a.id DESC
      LIMIT ${LIST_LIMIT}`,
    params
  );

  const assessments = rows.map((row) => ({
    ...toAssessment(row),
    orgUnitName: row.org_unit_name,
    assignedCount: row.assigned_count,
    runningCount: row.running_count,
    awaitingMarkingCount: row.awaiting_marking_count,
    markedCount: row.marked_count
  }));

  const { rows: [total] } = await getPool().query(
    `SELECT count(*)::int AS n FROM assessments a WHERE ${where}`,
    params
  );
  return { assessments, total: total.n, truncated: total.n > assessments.length };
}

// The sweep of section 5.2, committed before the operation that triggered it.
// A read that finds the Attempt already past its deadline must leave the
// finalise in place even though it then refuses — a refusal that rolled the
// finalise back would leave the Attempt running forever. The transition itself
// is idempotent (`WHERE status = 'in_progress'`), so committing it first is
// safe for concurrent callers; what happens next is a fresh transaction.
async function sweep(attemptId) {
  await withActor(null, async (client) => {
    await finalisePastDeadline(client, attemptId);
  });
}

// The caller's own Attempts, every `attempt_no`, open and done. The score is
// not among the fields until marking exists (slice 4): the candidate sees
// status and the deadline, and what a score says about them is the Marker's to
// release.
async function listMyAttempts(employeeId) {
  await withActor(null, async (client) => {
    await scoreAndFinaliseMine(client, employeeId);
  });
  const { rows } = await getPool().query(
    `SELECT ${ATTEMPT_COLUMNS}, a.number, a.title, a.question_count, a.pass_mark,
            a.due_on, a.org_unit_id AS process_org_unit_id, ou.name AS process_name
       FROM assessment_attempts at
       JOIN assessments a ON a.id = at.assessment_id
       JOIN org_units ou ON ou.id = a.org_unit_id
      WHERE at.employee_id = $1
      ORDER BY a.due_on NULLS LAST, at.assessment_id DESC, at.attempt_no`,
    [employeeId]
  );
  return rows.map((row) => ({
    ...toAttempt(row),
    assessmentNumber: row.number,
    assessmentTitle: row.title,
    questionCount: row.question_count,
    passMark: row.pass_mark,
    dueOn: row.due_on === null ? null : toIsoDate(row.due_on),
    processName: row.process_name
  }));
}

// ---------------------------------------------------------------------------
// Writing an Assessment
// ---------------------------------------------------------------------------

// The number is Site-scoped (`AS-HCM-2026-00001`), and the Site comes from the
// process Org Unit's own row — never from the caller — so a number can never be
// issued against a Site the Assessment does not sit in. Training's `TR` is the
// shape.
async function createAssessment(accountId, orgUnitId, facts) {
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
      `SELECT next_document_number('AS', $1, EXTRACT(YEAR FROM now())::int) AS number`,
      [site.code]
    );

    const { rows: [row] } = await client.query(
      `INSERT INTO assessments
         (site_id, org_unit_id, number, title, question_count, minutes, pass_mark,
          attempts_allowed, due_on)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
       RETURNING id`,
      [site.id, orgUnitId, numberRow.number, facts.title, facts.questionCount,
        facts.minutes, facts.passMark, facts.attemptsAllowed, facts.dueOn]
    );
    return row.id;
  });
  return findAssessment(id);
}

const ASSIGNED_CORRECTION_MESSAGE =
  'this Assessment has been assigned and its facts are frozen; close it and create a new one';

// A draft is corrected by full replacement of the six facts. Once assigned they
// are frozen: a person's deadline and pass mark cannot move under them.
async function correctAssessment(accountId, id, facts) {
  await withActor(accountId, async (client) => {
    const { rows: [locked] } = await client.query(
      'SELECT status FROM assessments WHERE id = $1 FOR UPDATE',
      [id]
    );
    if (!locked) throw notFound('Assessment');
    if (locked.status !== 'draft') throw httpError(409, ASSIGNED_CORRECTION_MESSAGE);
    await client.query(
      `UPDATE assessments
          SET title = $2, question_count = $3, minutes = $4, pass_mark = $5,
              attempts_allowed = $6, due_on = $7
        WHERE id = $1`,
      [id, facts.title, facts.questionCount, facts.minutes, facts.passMark,
        facts.attemptsAllowed, facts.dueOn]
    );
  });
  return findAssessment(id);
}

// A draft and its Attempts go together (`ON DELETE CASCADE`); an assigned one
// is a record and is closed, never deleted.
async function discardAssessment(accountId, id) {
  await withActor(accountId, async (client) => {
    const { rows: [locked] } = await client.query(
      'SELECT status FROM assessments WHERE id = $1 FOR UPDATE',
      [id]
    );
    if (!locked) throw notFound('Assessment');
    if (locked.status !== 'draft') {
      throw httpError(409, 'this Assessment has been assigned and cannot be discarded; close it instead');
    }
    await client.query('DELETE FROM assessments WHERE id = $1', [id]);
  });
}

async function closeAssessment(accountId, id) {
  await withActor(accountId, async (client) => {
    const { rows: [locked] } = await client.query(
      'SELECT status FROM assessments WHERE id = $1 FOR UPDATE',
      [id]
    );
    if (!locked) throw notFound('Assessment');
    if (locked.status === 'closed') return;
    if (locked.status === 'draft') {
      throw httpError(409, 'a draft has nobody to close it for; assign it or discard it');
    }
    await client.query("UPDATE assessments SET status = 'closed' WHERE id = $1", [id]);
  });
  return findAssessment(id);
}

// ---------------------------------------------------------------------------
// The bank, and the message a thin one produces
// ---------------------------------------------------------------------------

// The process's own active count — the number the draw is bounded by — and,
// separately, the subtree's counts. The subtree is never drawn from (spec
// section 3.1): it exists only so the refusal can say where the bank actually
// is, because a Team Leader who has just pasted 500 rows at the wrong node has
// nothing else to go on.
async function bankState(client, orgUnitId) {
  const runner = client ?? getPool();
  const { rows: [own] } = await runner.query(
    'SELECT count(*)::int AS n FROM assessment_questions WHERE org_unit_id = $1 AND is_active',
    [orgUnitId]
  );
  const { rows: elsewhere } = await runner.query(
    `SELECT ou.name, count(*)::int AS n
       FROM assessment_questions q
       JOIN org_units ou ON ou.id = q.org_unit_id
      WHERE q.is_active
        AND ou.path <@ (SELECT path FROM org_units WHERE id = $1)
      GROUP BY ou.id, ou.name
      ORDER BY n DESC, ou.name`,
    [orgUnitId]
  );
  return { available: own.n, elsewhere: elsewhere.map((row) => ({ name: row.name, count: row.n })) };
}

function bankRefusal(state, required) {
  const noun = state.available === 1 ? 'active question' : 'active questions';
  let message = `this process holds ${state.available} ${noun}; a paper needs ${required}`;
  const outside = state.elsewhere.filter((row) => row.count > 0 && row.count !== state.available);
  if (outside.length > 0) {
    const first = outside[0];
    message += ` — ${first.name} holds ${first.count}; create the Assessment at ${first.name} and assign this group`;
  }
  const refusal = httpError(409, message);
  refusal.extra = { available: state.available, required, elsewhere: state.elsewhere };
  return refusal;
}

// ---------------------------------------------------------------------------
// Assign: expand a group, resolve each person's own Org Unit, insert Attempt 1
// ---------------------------------------------------------------------------

function idArray(value, field) {
  if (value === undefined || value === null) return [];
  if (!Array.isArray(value)) throw httpError(400, `${field} must be an array of ids`);
  const ids = [];
  for (const entry of value) {
    const text = typeof entry === 'number' ? String(entry) : entry;
    if (typeof text !== 'string' || !/^[1-9][0-9]*$/.test(text.trim())) {
      throw httpError(400, `${field} must be an array of ids`);
    }
    ids.push(text.trim());
  }
  return ids;
}

function validateGroup(body) {
  const source = body ?? {};
  const orgUnitIds = idArray(source.orgUnitIds, 'orgUnitIds');
  const crewIds = idArray(source.crewIds, 'crewIds');
  const employeeIds = idArray(source.employeeIds, 'employeeIds');
  if (orgUnitIds.length === 0 && crewIds.length === 0 && employeeIds.length === 0) {
    throw httpError(400, 'name at least one Org Unit, crew or Employee to assign this Assessment to');
  }
  return { orgUnitIds, crewIds, employeeIds };
}

// "Current" is provably single (`employee_assignments_no_overlap` is an
// `EXCLUDE USING gist`), so the lateral's `LIMIT 1` never picks between two
// rows. The resolver is the repo's own (`directory.js`, `leave-requests.js`):
// the current assignment's Org Unit, else the Employee's default.
const RESOLVED_EMPLOYEES_SQL = `
  SELECT e.id AS employee_id, e.display_name, e.is_active,
         COALESCE(ca.org_unit_id, e.default_org_unit_id) AS org_unit_id,
         CASE WHEN ca.employee_id IS NOT NULL THEN ca.crew_id ELSE e.default_crew_id END AS crew_id
    FROM employees e
    LEFT JOIN LATERAL (
      SELECT ea.employee_id, ea.org_unit_id, ea.crew_id
        FROM employee_assignments ea
       WHERE ea.employee_id = e.id
         AND ea.effective_from <= employee_today(ea.employee_id)
         AND (ea.effective_to IS NULL OR ea.effective_to > employee_today(ea.employee_id))
       LIMIT 1
    ) ca ON TRUE
`;

async function expandGroup(client, group) {
  const { rows } = await client.query(
    `WITH resolved AS (${RESOLVED_EMPLOYEES_SQL})
     SELECT solved.employee_id, solved.display_name, solved.org_unit_id
       FROM resolved solved
      WHERE (solved.is_active AND EXISTS (
               SELECT 1 FROM org_units ou
                 JOIN org_units granted ON granted.id = ANY($1::bigint[])
                WHERE ou.id = solved.org_unit_id
                  AND ou.path <@ granted.path))
         OR (solved.is_active AND solved.crew_id = ANY($2::bigint[]))
         OR solved.employee_id = ANY($3::bigint[])
      ORDER BY solved.display_name, solved.employee_id`,
    [group.orgUnitIds, group.crewIds, group.employeeIds]
  );
  return rows;
}

// What the create form's "will reach N Employees" needs, and nothing else: the
// group expanded by the same rule `/assign` uses, without writing anything. A
// client cannot compute this for itself — the current-assignment lookup uses the
// Employee's own Site-local date (`employee_today`) and the crew falls back to
// the default only when there is no current row at all — and a number in front
// of a Team Leader that disagrees with what the server then does is worse than
// no number.
async function previewAssign(group) {
  return withActor(null, async (client) => {
    const wanted = await expandGroup(client, group);
    const unresolved = wanted.filter((row) => row.org_unit_id === null);
    return {
      count: wanted.length,
      employees: wanted.map((row) => ({
        employeeId: row.employee_id,
        displayName: row.display_name
      })),
      unresolvedCount: unresolved.length,
      unresolved: unresolved.map((row) => ({
        employeeId: row.employee_id,
        displayName: row.display_name
      }))
    };
  });
}

// One Attempt per Employee, all-or-nothing. Every refusal inside the
// transaction rolls the whole assignment back: nothing is written until the
// group has been proved complete.
async function assignAssessment(accountId, assessment, group) {
  return withActor(accountId, async (client) => {
    const { rows: [locked] } = await client.query(
      'SELECT id, status FROM assessments WHERE id = $1 FOR UPDATE',
      [assessment.id]
    );
    if (!locked) throw notFound('Assessment');
    if (locked.status === 'closed') throw httpError(409, 'this Assessment is closed and cannot take more people');

    // Named Employees must exist: a typo in an id is a 400 naming it, not a
    // person silently missing from the record.
    if (group.employeeIds.length > 0) {
      const { rows: known } = await client.query(
        'SELECT id FROM employees WHERE id = ANY($1::bigint[])',
        [group.employeeIds]
      );
      const knownIds = new Set(known.map((row) => String(row.id)));
      const unknown = group.employeeIds.filter((id) => !knownIds.has(id));
      if (unknown.length > 0) {
        throw httpError(400, `no Employee with id ${unknown.join(', ')}`);
      }
    }

    const wanted = await expandGroup(client, group);
    if (wanted.length === 0) {
      throw httpError(400, 'that group reaches nobody — no Employee resolves to it');
    }

    const unresolved = wanted.filter((row) => row.org_unit_id === null);
    if (unresolved.length > 0) {
      const names = unresolved.map((row) => `Employee ${row.employee_id} (${row.display_name})`).join(', ');
      throw httpError(
        400,
        `${names} has no current assignment and no default Org Unit, so the sitting has no place to answer to; set one first`
      );
    }

    const state = await bankState(client, assessment.orgUnitId);
    if (state.available < assessment.questionCount) {
      throw bankRefusal(state, assessment.questionCount);
    }

    const employeeIds = wanted.map((row) => String(row.employee_id));
    const { rows: already } = await client.query(
      `SELECT e.display_name
         FROM assessment_attempts at
         JOIN employees e ON e.id = at.employee_id
        WHERE at.assessment_id = $1 AND at.employee_id = ANY($2::bigint[])
        ORDER BY e.display_name`,
      [assessment.id, employeeIds]
    );
    if (already.length > 0) {
      throw httpError(
        409,
        `${already.map((row) => row.display_name).join(', ')} already hold an Attempt on this Assessment; nothing was assigned`
      );
    }

    // One row per person, in the same statement, so the attempt and the node it
    // answers to come from one resolution rather than two that could disagree.
    const orgUnitIds = wanted.map((row) => String(row.org_unit_id));
    await client.query(
      `INSERT INTO assessment_attempts
         (assessment_id, employee_id, attempt_no, org_unit_id, org_unit_resolved_on)
       SELECT $1, u.employee_id, 1, u.org_unit_id, employee_today(u.employee_id)
         FROM unnest($2::bigint[], $3::bigint[]) AS u(employee_id, org_unit_id)`,
      [assessment.id, employeeIds, orgUnitIds]
    );

    if (locked.status === 'draft') {
      await client.query("UPDATE assessments SET status = 'assigned' WHERE id = $1", [assessment.id]);
    }
    return { assigned: employeeIds.length };
  });
}

// ---------------------------------------------------------------------------
// The Attempt: start, answer, submit — all of it server-timed
// ---------------------------------------------------------------------------

// The lazy sweep (spec section 5.2): at the top of every Attempt read and every
// Answer write, in the same transaction. Scoped to one Attempt, so it is an
// indexed row update and cannot turn a read into a table-wide write.
async function finalisePastDeadline(client, attemptId) {
  const { rows: [row] } = await client.query(
    `SELECT id, status, deadline_at, now() >= deadline_at AS past
       FROM assessment_attempts WHERE id = $1 FOR UPDATE`,
    [attemptId]
  );
  if (!row) return false;
  if (row.status !== 'in_progress' || row.past !== true) return false;
  await scoreAnswers(client, attemptId);
  await client.query(
    `UPDATE assessment_attempts
        SET status = 'submitted',
            submitted_at = deadline_at,
            submitted_late = TRUE,
            score = (SELECT COALESCE(sum(points), 0)::int
                       FROM assessment_attempt_questions WHERE attempt_id = $1)
      WHERE id = $1`,
    [attemptId]
  );
  return true;
}

// The same rule for a caller's own list, in two statements rather than one per
// Attempt.
async function scoreAndFinaliseMine(client, employeeId) {
  await client.query(
    `UPDATE assessment_attempt_questions q
        SET points = CASE WHEN q.chosen_option IS NOT NULL
                           AND q.other_text IS NULL
                           AND q.chosen_option = q.correct_option THEN 1 ELSE 0 END
       FROM assessment_attempts at
      WHERE q.attempt_id = at.id
        AND at.employee_id = $1
        AND at.status = 'in_progress'
        AND now() >= at.deadline_at`,
    [employeeId]
  );
  await client.query(
    `UPDATE assessment_attempts at
        SET status = 'submitted',
            submitted_at = at.deadline_at,
            submitted_late = TRUE,
            score = (SELECT COALESCE(sum(points), 0)::int
                       FROM assessment_attempt_questions q WHERE q.attempt_id = at.id)
      WHERE at.employee_id = $1
        AND at.status = 'in_progress'
        AND now() >= at.deadline_at`,
    [employeeId]
  );
}

// A chosen Option scores 1 when it is the key; a blank and an Other answer both
// score 0 (spec section 10). No percentage is stored and correctness is never a
// column: `points` is the record.
async function scoreAnswers(client, attemptId) {
  await client.query(
    `UPDATE assessment_attempt_questions
        SET points = CASE WHEN chosen_option IS NOT NULL
                           AND other_text IS NULL
                           AND chosen_option = correct_option THEN 1 ELSE 0 END
      WHERE attempt_id = $1`,
    [attemptId]
  );
}

// The paper as the candidate sees it: no key, no explanation, no points. The
// columns are simply not selected, so no route can leak them.
async function readPaper(client, attemptId) {
  const { rows } = await client.query(
    `SELECT position, question_text, option_a, option_b, option_c,
            chosen_option, other_text
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
    chosenOption: row.chosen_option ?? null,
    otherText: row.other_text ?? null
  }));
}

async function attemptContext(client, attemptId) {
  const { rows: [row] } = await client.query(
    `SELECT ${ATTEMPT_COLUMNS}, a.number, a.title, a.question_count, a.minutes,
            a.pass_mark, a.status AS assessment_status, a.due_on,
            a.org_unit_id AS process_org_unit_id,
            ou.name AS process_name,
            now() >= at.deadline_at AS past
       FROM assessment_attempts at
       JOIN assessments a ON a.id = at.assessment_id
       JOIN org_units ou ON ou.id = a.org_unit_id
      WHERE at.id = $1`,
    [attemptId]
  );
  return row ?? null;
}

function attemptPayload(row, paper) {
  return {
    attempt: {
      ...toAttempt(row),
      assessmentNumber: row.number,
      assessmentTitle: row.title,
      questionCount: row.question_count,
      passMark: row.pass_mark,
      processName: row.process_name
    },
    paper
  };
}

const NOT_YOURS = 'Only the Employee can sit their own Assessment';

// `mine` is the caller's own Employee id, already resolved by the route from
// the Account (ADR-0045); `null` is an Account with no Employee, which no route
// on this door can serve.
async function startAttempt(accountId, attemptId, mine) {
  await sweep(attemptId);
  return withActor(accountId, async (client) => {
    const row = await attemptContext(client, attemptId);
    if (!row) throw notFound('Assessment attempt');
    if (String(row.employee_id) !== String(mine)) throw httpError(403, NOT_YOURS);

    if (row.status === 'in_progress') {
      // Idempotent on a refresh: the same paper, the same deadline.
      return { ...attemptPayload(row, await readPaper(client, attemptId)), serverNow: await serverNow(client) };
    }
    if (row.status === 'submitted') {
      throw httpError(409, row.submitted_late
        ? 'the deadline passed and this Assessment was submitted automatically'
        : 'this Assessment has already been submitted');
    }
    if (row.status === 'marked') throw httpError(409, 'this Assessment has already been marked');
    if (row.status === 'expired') throw httpError(409, 'the due date passed before this Assessment was started');
    if (row.status === 'cancelled') throw httpError(409, 'this Assessment was cancelled');
    if (row.assessment_status === 'closed') {
      throw httpError(409, 'this Assessment is closed');
    }

    if (row.due_on !== null) {
      const { rows: [due] } = await client.query(
        'SELECT plant_date($1, now()) > $2::date AS late',
        [row.process_org_unit_id, row.due_on]
      );
      if (due.late) {
        await client.query("UPDATE assessment_attempts SET status = 'expired' WHERE id = $1", [attemptId]);
        throw httpError(409, 'the due date passed before this Assessment was started');
      }
    }

    const state = await bankState(client, row.process_org_unit_id);
    if (state.available < row.question_count) {
      throw bankRefusal(state, row.question_count);
    }

    // Draw and freeze in the transaction that starts the clock (spec section
    // 11): `ORDER BY random()` for the draw, a second random order for the
    // positions, so the paper's order is not the bank's.
    const { rowCount } = await client.query(
      `WITH drawn AS (
         SELECT q.id, q.question_text, q.option_a, q.option_b, q.option_c,
                q.correct_option, q.explanation
           FROM assessment_questions q
          WHERE q.org_unit_id = $1 AND q.is_active
          ORDER BY random()
          LIMIT $2
       ), shuffled AS (
         SELECT d.*, row_number() OVER (ORDER BY random())::smallint AS position FROM drawn d
       )
       INSERT INTO assessment_attempt_questions
         (attempt_id, question_id, position, question_text,
          option_a, option_b, option_c, correct_option, explanation)
       SELECT $3, id, position, question_text, option_a, option_b, option_c,
              correct_option, explanation
         FROM shuffled`,
      [row.process_org_unit_id, row.question_count, attemptId]
    );
    if (rowCount !== row.question_count) {
      // The bank changed between the count and the draw; nothing is written
      // and the caller is told the honest number.
      const fresh = await bankState(client, row.process_org_unit_id);
      throw bankRefusal(fresh, row.question_count);
    }

    await client.query(
      `UPDATE assessment_attempts
          SET status = 'in_progress',
              started_at = now(),
              deadline_at = now() + (
                SELECT minutes * interval '1 minute' FROM assessments WHERE id = $2
              )
        WHERE id = $1`,
      [attemptId, row.assessment_id]
    );

    const started = await attemptContext(client, attemptId);
    return { ...attemptPayload(started, await readPaper(client, attemptId)), serverNow: await serverNow(client) };
  });
}

async function serverNow(client) {
  const { rows: [row] } = await client.query('SELECT now() AS now');
  return row.now;
}

// A refresh of the paper: no clock is set, no paper is drawn. The lazy sweep
// still runs first, so a paper refreshed after its deadline reads `submitted`.
async function getAttempt(attemptId, mine) {
  await sweep(attemptId);
  return withActor(null, async (client) => {
    const row = await attemptContext(client, attemptId);
    if (!row) throw notFound('Assessment attempt');
    if (String(row.employee_id) !== String(mine)) throw httpError(403, NOT_YOURS);
    return { ...attemptPayload(row, await readPaper(client, attemptId)), serverNow: await serverNow(client) };
  });
}

function validateAnswer(body) {
  const source = body ?? {};
  const hasChosen = source.chosenOption !== undefined && source.chosenOption !== null;
  const hasOther = source.otherText !== undefined && source.otherText !== null;
  if (hasChosen && hasOther) {
    throw httpError(400, 'an Answer is either a chosen Option or an Other answer, never both');
  }
  if (hasChosen) {
    if (!OPTIONS.includes(source.chosenOption)) {
      throw httpError(400, `chosenOption must be one of ${OPTIONS.join(', ')}`);
    }
    return { chosenOption: source.chosenOption, otherText: null };
  }
  if (hasOther) {
    if (typeof source.otherText !== 'string') throw httpError(400, 'otherText must be text');
    const trimmed = source.otherText.trim();
    if (trimmed === '') throw httpError(400, 'otherText must not be blank; send an empty body for a blank Answer');
    if (lengthOf(trimmed) > OTHER_MAX) {
      throw httpError(400, `otherText must be at most ${OTHER_MAX} characters`);
    }
    return { chosenOption: null, otherText: trimmed };
  }
  // `{}` is a blank Answer: it is legal, it scores 0, and it is not an Other.
  return { chosenOption: null, otherText: null };
}

// Autosave. Idempotent, and refused past the deadline — the sweep has already
// finalised the Attempt by the time this runs, so the refusal is about a closed
// paper, not about this Answer.
async function saveAnswer(accountId, attemptId, mine, position, answer) {
  await sweep(attemptId);
  return withActor(accountId, async (client) => {
    const row = await attemptContext(client, attemptId);
    if (!row) throw notFound('Assessment attempt');
    if (String(row.employee_id) !== String(mine)) throw httpError(403, NOT_YOURS);
    if (row.status !== 'in_progress') {
      throw httpError(409, row.submitted_late
        ? 'the deadline passed and this Assessment was submitted automatically'
        : 'this Assessment is not running');
    }

    const { rowCount } = await client.query(
      `UPDATE assessment_attempt_questions
          SET chosen_option = $3, other_text = $4, answered_at = now()
        WHERE attempt_id = $1 AND position = $2`,
      [attemptId, position, answer.chosenOption, answer.otherText]
    );
    if (rowCount === 0) throw notFound('Question');

    const updated = await attemptContext(client, attemptId);
    return { ...attemptPayload(updated, await readPaper(client, attemptId)), serverNow: await serverNow(client) };
  });
}

// The candidate's own submit. Scored here, from the saved Answers; missing ones
// are blank and score 0. Idempotent while the submit was the candidate's own; a
// submit after the deadline is a 409, because the server has already finalised.
async function submitAttempt(accountId, attemptId, mine) {
  await sweep(attemptId);
  return withActor(accountId, async (client) => {
    const row = await attemptContext(client, attemptId);
    if (!row) throw notFound('Assessment attempt');
    if (String(row.employee_id) !== String(mine)) throw httpError(403, NOT_YOURS);

    if (row.status === 'submitted') {
      if (row.submitted_late) {
        throw httpError(409, 'the deadline passed and this Assessment was submitted automatically');
      }
      return { ...attemptPayload(row, await readPaper(client, attemptId)), serverNow: await serverNow(client) };
    }
    if (row.status !== 'in_progress') {
      throw httpError(409, 'this Assessment is not running');
    }
    if (row.past === true) {
      throw httpError(409, 'the deadline passed and this Assessment was submitted automatically');
    }

    await scoreAnswers(client, attemptId);
    await client.query(
      `UPDATE assessment_attempts
          SET status = 'submitted',
              submitted_at = now(),
              score = (SELECT COALESCE(sum(points), 0)::int
                         FROM assessment_attempt_questions WHERE attempt_id = $1)
        WHERE id = $1`,
      [attemptId]
    );

    const submitted = await attemptContext(client, attemptId);
    return { ...attemptPayload(submitted, await readPaper(client, attemptId)), serverNow: await serverNow(client) };
  });
}

// The Attempt's stored score, for a test and for slice 4's queue. Not a route:
// nothing may show a score before marking (spec section 3.12).
async function storedScore(attemptId) {
  const { rows: [row] } = await getPool().query(
    'SELECT score, (SELECT count(*)::int FROM assessment_attempt_questions q WHERE q.attempt_id = $1 AND q.other_text IS NOT NULL) AS other_count FROM assessment_attempts WHERE id = $1',
    [attemptId]
  );
  return row ?? null;
}

module.exports = {
  validateAssessmentFacts,
  validateGroup,
  validateAnswer,
  findAssessment,
  getAssessment,
  listAssessments,
  listMyAttempts,
  createAssessment,
  correctAssessment,
  discardAssessment,
  closeAssessment,
  assignAssessment,
  previewAssign,
  bankState,
  startAttempt,
  getAttempt,
  saveAnswer,
  submitAttempt,
  storedScore,
  NOT_YOURS
};
