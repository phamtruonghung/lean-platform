/*
 * Marking, the point award and the result — issue #588, ADR-0068, slice 4 —
 * measured over HTTP against a real database and a real local session, the seam
 * plant.test.js and people-assessment-attempts.test.js use.
 *
 * What this file proves, in the order the card asks for it:
 *
 *   - the "Khác" answer is flagged in the queue and on the paper, scored 0 by
 *     the machine, and the Marker awards it 1;
 *   - `final_score` becomes 7 while `score` stays 6 — the award is a second
 *     number, not an overwrite;
 *   - `audit_log` holds exactly one UPDATE row on the awarded Answer, with the
 *     old and the new value and the Marker's Account id;
 *   - the result answers the key, the explanation and the verdict derived from
 *     the pass mark ("7/10 — not passed" against 8), and a read before marking
 *     is a 409;
 *   - a second `mark` is a 409;
 *   - a colleague who holds DISPLAY, CHANGE and MARK but whose Grants do not
 *     reach the Attempt reads the counts and `—`, never a score.
 *
 * Every case builds its own Site and Org Units, so a number range, a bank and a
 * group are private to the case, and `test.after` deletes exactly what this file
 * inserted: the Assessments (Attempts and drawn papers cascade), the Question
 * bank, the Grants, the Accounts, the Employees, the Org Units and the Site.
 */

const test = require('node:test');
const assert = require('node:assert');
const { tokenFor } = require('../helpers/session');

let server;
let base;
let pool;
let closePool;

const insertedAccountIds = [];
const insertedEmployeeIds = [];
const insertedSiteIds = [];
const insertedOrgUnitIds = [];

let counter = 0;
function unique(prefix) {
  counter += 1;
  return `${prefix}${process.pid}${counter}`;
}

async function insertAccount({ role, employeeId = null }) {
  const subject = unique('acct');
  const { rows: [row] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, employee_id, is_active, approval_status)
     VALUES ($1, 'Assessment Marking Test Account', $2, $3, $4, true, 'approved') RETURNING id`,
    [`${subject}@example.com`, role, subject, employeeId]
  );
  insertedAccountIds.push(row.id);
  return {
    id: row.id,
    role,
    employeeId,
    token: { authorization: `Bearer ${await tokenFor(subject)}` }
  };
}

async function insertGrant({ accountId, orgUnitId, canWrite }) {
  await pool.query(
    'INSERT INTO app_user_org_units (app_user_id, org_unit_id, can_write) VALUES ($1, $2, $3)',
    [accountId, orgUnitId, canWrite]
  );
}

async function insertEmployee({ orgUnitId = null, firstName = 'Marker' }) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO employees (employee_no, first_name, last_name, default_org_unit_id)
     VALUES ($1, $2, 'Sitter', $3) RETURNING id`,
    [unique('E'), firstName, orgUnitId]
  );
  insertedEmployeeIds.push(row.id);
  return row.id;
}

async function insertOrgUnit({ siteId, parentId = null, name, unitType = 'area' }) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, $2, $3, $4, $5) RETURNING id`,
    [siteId, parentId, unique('OU'), name, unitType]
  );
  insertedOrgUnitIds.push(row.id);
  return row.id;
}

async function insertQuestions(orgUnitId, count) {
  for (let i = 1; i <= count; i += 1) {
    await pool.query(
      `INSERT INTO assessment_questions
         (org_unit_id, question_text, option_a, option_b, option_c, correct_option, explanation)
       VALUES ($1, $2, $3, $4, $5, 'C', $6)`,
      [orgUnitId, `Câu ${i} của quy trình này là gì?`, `Phương án A ${i}`, `Phương án B ${i}`,
        `Phương án C ${i}`, `Lý do ${i}.`]
    );
  }
}

async function call(account, path, { method = 'GET', body } = {}) {
  const response = await fetch(`${base}${path}`, {
    method,
    headers: {
      ...account.token,
      ...(body === undefined ? {} : { 'content-type': 'application/json' })
    },
    body: body === undefined ? undefined : JSON.stringify(body)
  });
  const payload = await response.json().catch(() => null);
  return { response, payload, status: response.status };
}

let siteId;
let marker;      // supervisor: DISPLAY + CHANGE + MARK, a write Grant on each case's process.
let colleague;   // supervisor, no Grant anywhere: holds the codes, reaches no Org Unit.
let candidate;   // operator, SIT + DISPLAY, linked to an Employee.

test.before(async () => {
  process.env.BACKEND_PORT = '0';

  ({ server } = require('../../src/index'));
  ({ closePool } = require('../../src/platform/db'));
  pool = require('../../src/platform/db').getPool();

  if (!server.listening) {
    await new Promise((resolve, reject) => {
      server.once('listening', resolve);
      server.once('error', reject);
    });
  }
  base = `http://127.0.0.1:${server.address().port}`;

  const { rows: [site] } = await pool.query(
    `INSERT INTO sites (code, name, timezone)
     VALUES ($1, 'Assessment Marking Test Site', 'Asia/Ho_Chi_Minh') RETURNING id`,
    [unique('ST')]
  );
  siteId = site.id;
  insertedSiteIds.push(siteId);

  marker = await insertAccount({ role: 'supervisor' });
  colleague = await insertAccount({ role: 'supervisor' });
});

test.after(async () => {
  await pool.query('DELETE FROM assessments WHERE site_id = ANY($1)', [insertedSiteIds]);
  await pool.query('DELETE FROM assessment_questions WHERE org_unit_id = ANY($1)', [insertedOrgUnitIds]);
  await pool.query('DELETE FROM app_user_org_units WHERE app_user_id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM app_users WHERE id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM employees WHERE id = ANY($1)', [insertedEmployeeIds]);
  await pool.query('DELETE FROM org_units WHERE id = ANY($1)', [insertedOrgUnitIds]);
  await pool.query('DELETE FROM sites WHERE id = ANY($1)', [insertedSiteIds]);
  await new Promise((resolve) => server.close(resolve));
  await closePool();
});

// A process with a bank of 10, a team Org Unit holding the candidate, and a
// second process nobody in this test may write at.
async function stage() {
  const processUnitId = await insertOrgUnit({ siteId, name: `Cutting MTU ${unique('P')}` });
  const teamUnitId = await insertOrgUnit({ siteId, parentId: processUnitId, name: `Team ${unique('T')}` });
  const foreignUnitId = await insertOrgUnit({ siteId, name: `Winding ${unique('F')}` });
  await insertGrant({ accountId: marker.id, orgUnitId: processUnitId, canWrite: true });
  await insertQuestions(processUnitId, 10);

  const candidateEmployeeId = await insertEmployee({ orgUnitId: teamUnitId, firstName: 'Candidate' });
  candidate = await insertAccount({ role: 'operator', employeeId: candidateEmployeeId });

  return { processUnitId, teamUnitId, foreignUnitId, candidateEmployeeId };
}

async function createAssessment(orgUnitId) {
  const created = await call(marker, '/api/people/assessments', {
    method: 'POST',
    body: { orgUnitId, title: 'Kiểm tra quy trình Cutting MTU', questionCount: 10 }
  });
  assert.strictEqual(created.status, 201, JSON.stringify(created.payload));
  return created.payload.assessment;
}

// Create, assign to the candidate, start, answer 7 (six as the key, the seventh
// as "Khác"), submit. Returns the ids the marking cases need.
async function sitAndSubmit({ answerCount = 7 } = {}) {
  const staged = await stage();
  const assessment = await createAssessment(staged.processUnitId);

  const assigned = await call(marker, `/api/people/assessments/${assessment.id}/assign`, {
    method: 'POST',
    body: { employeeIds: [staged.candidateEmployeeId] }
  });
  assert.strictEqual(assigned.status, 201, JSON.stringify(assigned.payload));

  const mine = await call(candidate, '/api/people/assessment-attempts/mine');
  const attemptId = mine.payload.attempts
    .filter((row) => row.assessmentId === String(assessment.id))
    .map((row) => row.id)[0];
  assert.ok(attemptId, 'the candidate holds one Attempt');

  const started = await call(candidate, `/api/people/assessment-attempts/${attemptId}/start`, { method: 'POST' });
  assert.strictEqual(started.status, 200, JSON.stringify(started.payload));

  const { rows: keyed } = await pool.query(
    'SELECT position, correct_option FROM assessment_attempt_questions WHERE attempt_id = $1 ORDER BY position',
    [attemptId]
  );
  let otherPosition = null;
  for (let index = 0; index < answerCount; index += 1) {
    const row = keyed[index];
    const isOther = index === answerCount - 1;
    if (isOther) otherPosition = row.position;
    const saved = await call(candidate, `/api/people/assessment-attempts/${attemptId}/answers/${row.position}`, {
      method: 'PATCH',
      body: isOther
        ? { otherText: 'E. Dừng máy rồi báo Team Leader bằng bộ đàm' }
        : { chosenOption: row.correct_option }
    });
    assert.strictEqual(saved.status, 200, JSON.stringify(saved.payload));
  }

  const submitted = await call(candidate, `/api/people/assessment-attempts/${attemptId}/submit`, { method: 'POST' });
  assert.strictEqual(submitted.status, 200, JSON.stringify(submitted.payload));

  return { ...staged, assessment, attemptId, otherPosition };
}

// ---------------------------------------------------------------------------
// 1. The queue, the award, the audit row and the result
// ---------------------------------------------------------------------------

test('the queue lists the submitted Attempt with its Other answer, and the award turns 6 into 7 as a record', async () => {
  const staged = await sitAndSubmit();

  // The machine's number, before anyone touches it.
  const { rows: [before] } = await pool.query(
    'SELECT score, final_score, status FROM assessment_attempts WHERE id = $1',
    [staged.attemptId]
  );
  assert.strictEqual(before.score, 6, 'six keyed answers out of seven, the Other always 0');
  assert.strictEqual(before.final_score, null);
  assert.strictEqual(before.status, 'submitted');

  // The queue: the Attempt, oldest first, with the flag count the Marker marks by.
  const queue = await call(marker, '/api/people/assessment-marking');
  assert.strictEqual(queue.status, 200, JSON.stringify(queue.payload));
  const row = queue.payload.attempts.find((entry) => String(entry.id) === String(staged.attemptId));
  assert.ok(row, 'the submitted Attempt is in the queue');
  assert.strictEqual(row.otherAnswerCount, 1);
  assert.strictEqual(row.submittedLate, false);
  assert.strictEqual(row.employeeName, 'Candidate Sitter');
  assert.strictEqual(row.assessmentTitle, 'Kiểm tra quy trình Cutting MTU');
  assert.strictEqual(row.questionCount, 10);
  const submittedTimes = queue.payload.attempts.map((entry) => new Date(entry.submittedAt).getTime());
  assert.deepStrictEqual(submittedTimes, submittedTimes.slice().sort((a, b) => a - b), 'oldest first');

  // The paper with the key.
  const paper = await call(marker, `/api/people/assessment-attempts/${staged.attemptId}/marking`);
  assert.strictEqual(paper.status, 200, JSON.stringify(paper.payload));
  assert.strictEqual(paper.payload.questions.length, 10);
  assert.strictEqual(paper.payload.attempt.score, 6, 'the Marker reads the machine number before the award');
  assert.strictEqual(paper.payload.attempt.finalScore, null);
  const other = paper.payload.questions.find((entry) => entry.position === staged.otherPosition);
  assert.ok(other.otherText, 'the Other answer is on the paper');
  assert.strictEqual(other.points, 0, 'an Other answer scores 0 until the Marker decides');
  for (const question of paper.payload.questions) {
    assert.ok(['A', 'B', 'C'].includes(question.correctOption), 'the key is on the marking paper');
    assert.strictEqual(typeof question.explanation, 'string');
  }

  // The award.
  const marked = await call(marker, `/api/people/assessment-attempts/${staged.attemptId}/mark`, {
    method: 'POST',
    body: {
      answers: [{ position: staged.otherPosition, points: 1, note: 'Câu trả lời hay hơn đáp án' }],
      note: 'Đã xem câu Khác'
    }
  });
  assert.strictEqual(marked.status, 200, JSON.stringify(marked.payload));
  assert.strictEqual(marked.payload.attempt.status, 'marked');
  assert.strictEqual(marked.payload.attempt.score, 6, 'score is the machine\'s number and stays 6');
  assert.strictEqual(marked.payload.attempt.finalScore, 7, 'final_score is the Marker\'s number');
  assert.strictEqual(marked.payload.attempt.markedByName, 'Assessment Marking Test Account');
  assert.match(marked.payload.attempt.markingNote, /Đã xem câu Khác/);
  assert.match(marked.payload.attempt.markingNote, new RegExp(`#${staged.otherPosition}: Câu trả lời hay hơn đáp án`));

  // The audit trail of the award itself: one UPDATE by the Marker. The row has
  // its own earlier history (the draw's INSERT, the autosave and the submit that
  // wrote the machine's 0), so the assertion is on the Marker's own write.
  const { rows: [answerRow] } = await pool.query(
    'SELECT id FROM assessment_attempt_questions WHERE attempt_id = $1 AND position = $2',
    [staged.attemptId, staged.otherPosition]
  );
  const { rows: auditRows } = await pool.query(
    `SELECT operation, changed_by, old_values, new_values
       FROM audit_log
      WHERE table_name = 'assessment_attempt_questions' AND record_id = $1
      ORDER BY changed_at`,
    [answerRow.id]
  );
  const byMarker = auditRows.filter((row) => String(row.changed_by) === String(marker.id));
  assert.strictEqual(
    byMarker.length,
    1,
    `one audit row for the award: ${JSON.stringify(auditRows.map((r) => [r.operation, r.changed_by]))}`
  );
  assert.strictEqual(byMarker[0].operation, 'UPDATE');
  assert.strictEqual(byMarker[0].old_values.points, 0);
  assert.strictEqual(byMarker[0].new_values.points, 1);
  console.log('AUDIT_ROW old_values=%s new_values=%s',
    JSON.stringify(byMarker[0].old_values), JSON.stringify(byMarker[0].new_values));
  assert.strictEqual(
    auditRows.filter((row) => row.operation === 'UPDATE').at(-1).changed_by.toString(),
    String(marker.id),
    'the newest UPDATE on the row is the award'
  );

  // A second mark is a 409, and it changes nothing.
  const twice = await call(marker, `/api/people/assessment-attempts/${staged.attemptId}/mark`, {
    method: 'POST',
    body: { answers: [{ position: 1, points: 0 }] }
  });
  assert.strictEqual(twice.status, 409, JSON.stringify(twice.payload));
  const { rows: [after] } = await pool.query(
    'SELECT final_score, status FROM assessment_attempts WHERE id = $1',
    [staged.attemptId]
  );
  assert.strictEqual(after.final_score, 7);
  assert.strictEqual(after.status, 'marked');

  // The result: the key, the explanations, the derived verdict.
  const result = await call(candidate, `/api/people/assessment-attempts/${staged.attemptId}/result`);
  assert.strictEqual(result.status, 200, JSON.stringify(result.payload));
  assert.strictEqual(result.payload.verdict.score, 6);
  assert.strictEqual(result.payload.verdict.finalScore, 7);
  assert.strictEqual(result.payload.verdict.passMark, 8);
  assert.strictEqual(result.payload.verdict.passed, false, '7 of 10 against a pass mark of 8 is not passed');
  assert.strictEqual(result.payload.questions.length, 10);
  for (const question of result.payload.questions) {
    assert.ok(['A', 'B', 'C'].includes(question.correctOption));
    assert.strictEqual(typeof question.explanation, 'string');
  }
  const awarded = result.payload.questions.find((entry) => entry.position === staged.otherPosition);
  assert.strictEqual(awarded.points, 1, 'the awarded point is the record the result reads');
});

test('a result read before marking is a 409, and the candidate\'s own list shows no score until marked', async () => {
  const staged = await sitAndSubmit();

  const early = await call(candidate, `/api/people/assessment-attempts/${staged.attemptId}/result`);
  assert.strictEqual(early.status, 409, JSON.stringify(early.payload));
  assert.match(early.payload.message, /not been marked yet/);

  const mine = await call(candidate, '/api/people/assessment-attempts/mine');
  const own = mine.payload.attempts.find((row) => String(row.id) === String(staged.attemptId));
  assert.strictEqual(own.status, 'submitted');
  assert.strictEqual(own.score, null, 'the machine number is not shown before the Marker releases it');
  assert.strictEqual(own.finalScore, null);
  assert.strictEqual(own.scoreHidden, true);

  // After the award the same list carries the two numbers, to its own owner.
  const marked = await call(marker, `/api/people/assessment-attempts/${staged.attemptId}/mark`, {
    method: 'POST',
    body: { answers: [{ position: staged.otherPosition, points: 1 }] }
  });
  assert.strictEqual(marked.status, 200, JSON.stringify(marked.payload));

  const mineAgain = await call(candidate, '/api/people/assessment-attempts/mine');
  const ownAgain = mineAgain.payload.attempts.find((row) => String(row.id) === String(staged.attemptId));
  assert.strictEqual(ownAgain.score, 6);
  assert.strictEqual(ownAgain.finalScore, 7);
  assert.strictEqual(ownAgain.passed, false);
  assert.strictEqual(ownAgain.scoreHidden, false);
});

test('a marking paper of a marked Attempt still reads, and the result stays the person\'s own', async () => {
  const staged = await sitAndSubmit();
  const marked = await call(marker, `/api/people/assessment-attempts/${staged.attemptId}/mark`, {
    method: 'POST',
    body: { answers: [{ position: staged.otherPosition, points: 1 }] }
  });
  assert.strictEqual(marked.status, 200, JSON.stringify(marked.payload));

  const paper = await call(marker, `/api/people/assessment-attempts/${staged.attemptId}/marking`);
  assert.strictEqual(paper.status, 200);
  assert.strictEqual(paper.payload.attempt.status, 'marked');
  assert.strictEqual(paper.payload.attempt.finalScore, 7);

  // Another person's result is a 403 to somebody who is neither the candidate
  // nor a reach-holder of the Attempt's Org Unit — the colleague reaches nothing.
  const stolen = await call(colleague, `/api/people/assessment-attempts/${staged.attemptId}/result`);
  assert.strictEqual(stolen.status, 403, JSON.stringify(stolen.payload));
});

// ---------------------------------------------------------------------------
// 2. Section 3.14 — the score is a field-level read
// ---------------------------------------------------------------------------

test('a colleague holding DISPLAY, CHANGE and MARK but reaching no Org Unit reads the counts and never a score', async () => {
  const staged = await sitAndSubmit();
  const marked = await call(marker, `/api/people/assessment-attempts/${staged.attemptId}/mark`, {
    method: 'POST',
    body: { answers: [{ position: staged.otherPosition, points: 1 }], note: 'Đã chấm' }
  });
  assert.strictEqual(marked.status, 200, JSON.stringify(marked.payload));

  // The colleague reaches nothing: counted, never scored.
  const hidden = await call(colleague, `/api/people/assessments/${staged.assessment.id}`);
  assert.strictEqual(hidden.status, 200, JSON.stringify(hidden.payload));
  const hiddenRow = hidden.payload.assessment.attempts
    .find((entry) => String(entry.id) === String(staged.attemptId));
  assert.strictEqual(hiddenRow.status, 'marked');
  assert.strictEqual(hiddenRow.score, null, 'a score is a field-level read, not a count');
  assert.strictEqual(hiddenRow.finalScore, null);
  assert.strictEqual(hiddenRow.passed, null);
  assert.strictEqual(hiddenRow.scoreHidden, true);
  assert.strictEqual(hiddenRow.otherAnswerCount, 1, 'the count stays visible to everyone');
  assert.strictEqual(hiddenRow.employeeName, 'Candidate Sitter');

  // The Marker, whose write Grant reaches the Attempt's Org Unit, reads both.
  const shown = await call(marker, `/api/people/assessments/${staged.assessment.id}`);
  const shownRow = shown.payload.assessment.attempts
    .find((entry) => String(entry.id) === String(staged.attemptId));
  assert.strictEqual(shownRow.score, 6);
  assert.strictEqual(shownRow.finalScore, 7);
  assert.strictEqual(shownRow.passed, false);
  assert.strictEqual(shownRow.scoreHidden, false);
  assert.strictEqual(shownRow.markedByName, 'Assessment Marking Test Account');

  // The candidate reads their own through the person's own door.
  const own = await call(candidate, '/api/people/assessment-attempts/mine');
  const ownRow = own.payload.attempts.find((entry) => String(entry.id) === String(staged.attemptId));
  assert.strictEqual(ownRow.finalScore, 7);
});

// ---------------------------------------------------------------------------
// 3. Reach: the queue, the paper and the award are the caller's own Org Units
// ---------------------------------------------------------------------------

test('a Marker outside the Attempt\'s reach gets a 403 on the paper and the queue omits it', async () => {
  const staged = await sitAndSubmit();

  const paper = await call(colleague, `/api/people/assessment-attempts/${staged.attemptId}/marking`);
  assert.strictEqual(paper.status, 403, JSON.stringify(paper.payload));
  assert.strictEqual(paper.payload.message, "Outside the caller's granted Org Units");

  const award = await call(colleague, `/api/people/assessment-attempts/${staged.attemptId}/mark`, {
    method: 'POST',
    body: { answers: [{ position: staged.otherPosition, points: 1 }] }
  });
  assert.strictEqual(award.status, 403, JSON.stringify(award.payload));

  const { rows: [untouched] } = await pool.query(
    'SELECT status, final_score, marked_at FROM assessment_attempts WHERE id = $1',
    [staged.attemptId]
  );
  assert.strictEqual(untouched.status, 'submitted', 'a refused award writes nothing');
  assert.strictEqual(untouched.final_score, null);
  assert.strictEqual(untouched.marked_at, null);

  const queue = await call(colleague, '/api/people/assessment-marking');
  assert.strictEqual(queue.status, 200);
  assert.strictEqual(
    queue.payload.attempts.some((entry) => String(entry.id) === String(staged.attemptId)),
    false,
    'the queue is the caller\'s write reach, not the plant'
  );

  // And the queue narrows by Org Unit for the Marker who may write there.
  const filtered = await call(marker, `/api/people/assessment-marking?orgUnitId=${staged.processUnitId}`);
  assert.strictEqual(filtered.status, 200);
  assert.ok(filtered.payload.attempts.some((entry) => String(entry.id) === String(staged.attemptId)));

  // A process the caller's write Grants do not reach is a 403, not an empty list.
  const foreign = await call(marker, `/api/people/assessment-marking?orgUnitId=${staged.foreignUnitId}`);
  assert.strictEqual(foreign.status, 403, JSON.stringify(foreign.payload));
  const noReach = await call(colleague, `/api/people/assessment-marking?orgUnitId=${staged.processUnitId}`);
  assert.strictEqual(noReach.status, 403, JSON.stringify(noReach.payload));

  const unknown = await call(marker, '/api/people/assessment-marking?orgUnitId=99999999');
  assert.strictEqual(unknown.status, 404);
});

// ---------------------------------------------------------------------------
// 4. Who may mark at all
// ---------------------------------------------------------------------------

test('an operator with SIT cannot read the queue, the paper or award a point', async () => {
  const staged = await sitAndSubmit();

  const queue = await call(candidate, '/api/people/assessment-marking');
  assert.strictEqual(queue.status, 403, JSON.stringify(queue.payload));
  assert.strictEqual(queue.payload.code, 'PERMISSION_REQUIRED');
  assert.strictEqual(queue.payload.permission, 'PPL_ASSESSMENT_MARK');

  const paper = await call(candidate, `/api/people/assessment-attempts/${staged.attemptId}/marking`);
  assert.strictEqual(paper.status, 403);

  const award = await call(candidate, `/api/people/assessment-attempts/${staged.attemptId}/mark`, {
    method: 'POST',
    body: { answers: [{ position: staged.otherPosition, points: 1 }] }
  });
  assert.strictEqual(award.status, 403);

  const unknown = await call(marker, '/api/people/assessment-attempts/99999999/marking');
  assert.strictEqual(unknown.status, 404);
});

test('a body naming a position the paper does not hold, or a point that is not 0 or 1, is a 400', async () => {
  const staged = await sitAndSubmit();

  const offPaper = await call(marker, `/api/people/assessment-attempts/${staged.attemptId}/mark`, {
    method: 'POST',
    body: { answers: [{ position: 14, points: 1 }] }
  });
  assert.strictEqual(offPaper.status, 400, JSON.stringify(offPaper.payload));
  assert.match(offPaper.payload.message, /position 14/);

  const badPoint = await call(marker, `/api/people/assessment-attempts/${staged.attemptId}/mark`, {
    method: 'POST',
    body: { answers: [{ position: 1, points: 2 }] }
  });
  assert.strictEqual(badPoint.status, 400, JSON.stringify(badPoint.payload));

  const twice = await call(marker, `/api/people/assessment-attempts/${staged.attemptId}/mark`, {
    method: 'POST',
    body: { answers: [{ position: 1, points: 1 }, { position: 1, points: 0 }] }
  });
  assert.strictEqual(twice.status, 400, JSON.stringify(twice.payload));

  const { rows: [untouched] } = await pool.query(
    'SELECT status FROM assessment_attempts WHERE id = $1',
    [staged.attemptId]
  );
  assert.strictEqual(untouched.status, 'submitted', 'a refused body marks nothing');
});

test('two marks at once: exactly one wins and the other is a 409', async () => {
  const staged = await sitAndSubmit();
  const send = () => call(marker, `/api/people/assessment-attempts/${staged.attemptId}/mark`, {
    method: 'POST',
    body: { answers: [{ position: staged.otherPosition, points: 1 }] }
  });
  const results = await Promise.all([send(), send()]);
  assert.deepStrictEqual(results.map((entry) => entry.status).sort(), [200, 409]);
  const { rows } = await pool.query(
    `SELECT count(*)::int AS n FROM audit_log al
       JOIN assessment_attempt_questions q ON q.id = al.record_id
      WHERE al.table_name = 'assessment_attempt_questions' AND al.operation = 'UPDATE'
        AND q.attempt_id = $1 AND al.changed_by = $2
        AND (al.new_values->>'points')::int = 1 AND (al.old_values->>'points')::int = 0`,
    [staged.attemptId, marker.id]
  );
  assert.strictEqual(rows[0].n, 1, 'one award, one audit row');
});

test('a point on a keyed (non-Other) answer is accepted: the Marker may change any Answer (spec section 10)', async () => {
  const staged = await sitAndSubmit();
  const keyed = staged.otherPosition === 1 ? 2 : 1;
  const marked = await call(marker, `/api/people/assessment-attempts/${staged.attemptId}/mark`, {
    method: 'POST',
    body: { answers: [{ position: keyed, points: 0 }] }
  });
  assert.strictEqual(marked.status, 200, JSON.stringify(marked.payload));
});
