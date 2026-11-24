/*
 * Create, assign, sit, submit — issue #588, ADR-0068, slice 3 — measured over
 * HTTP against a real database and a real local session, the seam
 * plant.test.js and people-assessments.test.js use.
 *
 * Every case builds its own Site and Org Units, so a number range, a bank and a
 * group are private to the case, and `test.after` deletes exactly what this file
 * inserted: Assessments (their Attempts and drawn papers cascade), then the
 * Question bank, the Grants, Accounts, Employees, Org Units and Site.
 *
 * The score is read from `assessment_attempts.score`, not from a route: nothing
 * about a score is shown before marking (spec section 3.12) and marking is slice
 * 4, so a route that returned one here would be the defect this case would be
 * pinning. Where the score is proved, it is proved in the database; what the
 * API says about the paper ("7 answered, 1 of them an Other answer") is asserted
 * over HTTP.
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
     VALUES ($1, 'Assessment Attempt Test Account', $2, $3, $4, true, 'approved') RETURNING id`,
    [`${subject}@example.com`, role, subject, employeeId]
  );
  insertedAccountIds.push(row.id);
  return { id: row.id, role, employeeId, token: { authorization: `Bearer ${await tokenFor(subject)}` } };
}

async function insertGrant({ accountId, orgUnitId, canWrite }) {
  await pool.query(
    'INSERT INTO app_user_org_units (app_user_id, org_unit_id, can_write) VALUES ($1, $2, $3)',
    [accountId, orgUnitId, canWrite]
  );
}

async function insertEmployee({ orgUnitId = null, crewId = null, firstName = 'Assessment' }) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO employees (employee_no, first_name, last_name, default_org_unit_id, default_crew_id)
     VALUES ($1, $2, 'Sitter', $3, $4) RETURNING id`,
    [unique('E'), firstName, orgUnitId, crewId]
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

// A Question written straight into the bank. The paste route is slice 2's and
// is proved there; this file builds the bank it draws from.
async function insertQuestions(orgUnitId, count, prefix = 'Câu') {
  const rows = [];
  for (let i = 1; i <= count; i += 1) {
    const { rows: [row] } = await pool.query(
      `INSERT INTO assessment_questions
         (org_unit_id, question_text, option_a, option_b, option_c, correct_option, explanation)
       VALUES ($1, $2, $3, $4, $5, 'C', $6) RETURNING id`,
      [orgUnitId, `${prefix} ${i} của quy trình này là gì?`, `Phương án A ${i}`, `Phương án B ${i}`, `Phương án C ${i}`, `Lý do ${i}.`]
    );
    rows.push(row.id);
  }
  return rows;
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

function assessmentFacts(overrides = {}) {
  return {
    title: 'Kiểm tra quy trình Cutting MTU',
    questionCount: 10,
    ...overrides
  };
}

let siteId;
let supervisor;   // CHANGE + a write Grant on each case's process.
let candidateA;   // operator with SIT, linked to an Employee.
let candidateB;   // the same, a different person.

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
     VALUES ($1, 'Assessment Attempt Test Site', 'Asia/Ho_Chi_Minh') RETURNING id`,
    [unique('ST')]
  );
  siteId = site.id;
  insertedSiteIds.push(siteId);

  supervisor = await insertAccount({ role: 'supervisor' });
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

// A process with a bank of `count` Questions, a team Org Unit holding one
// Employee, and two Employees who sit elsewhere. The supervisor may write at the
// process; the group is never the draw's scope (spec section 3.3).
async function stage({ bank = 10, prefix = 'Câu' } = {}) {
  const processUnitId = await insertOrgUnit({ siteId, name: `Cutting MTU ${unique('P')}` });
  const teamUnitId = await insertOrgUnit({ siteId, name: `Team ${unique('T')}` });
  const otherUnitId = await insertOrgUnit({ siteId, name: `Elsewhere ${unique('E')}` });
  await insertGrant({ accountId: supervisor.id, orgUnitId: processUnitId, canWrite: true });
  await insertQuestions(processUnitId, bank, prefix);

  const teamWorkerId = await insertEmployee({ orgUnitId: teamUnitId, firstName: 'Team' });
  const namedAId = await insertEmployee({ orgUnitId: otherUnitId, firstName: 'Named' });
  const namedBId = await insertEmployee({ orgUnitId: otherUnitId, firstName: 'Other' });

  const candidateAEmployeeId = await insertEmployee({ orgUnitId: teamUnitId, firstName: 'Sitter' });
  const candidateBEmployeeId = await insertEmployee({ orgUnitId: teamUnitId, firstName: 'Second' });
  candidateA = await insertAccount({ role: 'operator', employeeId: candidateAEmployeeId });
  candidateB = await insertAccount({ role: 'operator', employeeId: candidateBEmployeeId });

  return { processUnitId, teamUnitId, otherUnitId, teamWorkerId, namedAId, namedBId, candidateAEmployeeId, candidateBEmployeeId };
}

async function createAssessment(orgUnitId, overrides = {}) {
  const created = await call(supervisor, '/api/people/assessments', {
    method: 'POST',
    body: { orgUnitId, ...assessmentFacts(overrides) }
  });
  assert.strictEqual(created.status, 201, JSON.stringify(created.payload));
  return created.payload.assessment;
}

// ---------------------------------------------------------------------------
// 1. Create: the six facts, their defaults, and the number
// ---------------------------------------------------------------------------

test('a 10-Question Assessment defaults to 20 minutes and an 80 % pass mark, and gets a Site-scoped number', async () => {
  const { processUnitId } = await stage();
  const assessment = await createAssessment(processUnitId);

  assert.match(assessment.number, /^AS-[A-Z0-9]+-\d{4}-\d{5}$/, `number was ${assessment.number}`);
  assert.strictEqual(assessment.title, 'Kiểm tra quy trình Cutting MTU');
  assert.strictEqual(assessment.questionCount, 10);
  assert.strictEqual(assessment.minutes, 20);
  assert.strictEqual(assessment.passMark, 8);
  assert.strictEqual(assessment.attemptsAllowed, 1);
  assert.strictEqual(assessment.status, 'draft');
  assert.strictEqual(assessment.dueOn, null);
  assert.strictEqual(assessment.orgUnitId, String(processUnitId));
});

test('a 15-Question Assessment defaults to 30 minutes, and attemptsAllowed is stored between 1 and 3', async () => {
  const { processUnitId } = await stage({ bank: 15 });
  const fifteen = await createAssessment(processUnitId, { questionCount: 15 });
  assert.strictEqual(fifteen.minutes, 30);
  assert.strictEqual(fifteen.passMark, 12);

  const three = await createAssessment(processUnitId, { attemptsAllowed: 3, minutesOverride: undefined });
  assert.strictEqual(three.attemptsAllowed, 3);

  const refused = await call(supervisor, '/api/people/assessments', {
    method: 'POST',
    body: { orgUnitId: processUnitId, ...assessmentFacts({ attemptsAllowed: 4 }) }
  });
  assert.strictEqual(refused.status, 400, JSON.stringify(refused.payload));
});

test('an Assessment below the size, or with a bad pass mark, is refused naming the field', async () => {
  const { processUnitId } = await stage();
  const cases = [
    { body: { questionCount: 12 }, message: /questionCount/ },
    { body: { passMark: 11 }, message: /passMark/ },
    { body: { minutes: 4 }, message: /minutes/ },
    { body: { dueOn: '2026-13-40' }, message: /dueOn/ },
    { body: { title: 'x' }, message: /title/ }
  ];
  for (const { body, message } of cases) {
    const refused = await call(supervisor, '/api/people/assessments', {
      method: 'POST',
      body: { orgUnitId: processUnitId, ...assessmentFacts(), ...body }
    });
    assert.strictEqual(refused.status, 400, `${JSON.stringify(body)}: ${JSON.stringify(refused.payload)}`);
    assert.match(refused.payload.message, message, JSON.stringify(body));
  }
});

// ---------------------------------------------------------------------------
// 2. The whole path: create, assign, start, answer (one Other), submit
// ---------------------------------------------------------------------------

test('create, assign to an Org Unit and two named Employees, start, answer 7 with one Other, submit — score 6 and the Other flagged', async () => {
  const stage3 = await stage({ bank: 10 });
  const assessment = await createAssessment(stage3.processUnitId);

  const assigned = await call(supervisor, `/api/people/assessments/${assessment.id}/assign`, {
    method: 'POST',
    body: { orgUnitIds: [stage3.teamUnitId], employeeIds: [stage3.namedAId, stage3.namedBId] }
  });
  assert.strictEqual(assigned.status, 201, JSON.stringify(assigned.payload));
  // The Team Org Unit reaches the two candidate Employees who default to it as
  // well as the worker, and the two named Employees sit elsewhere: five people,
  // each with their own Attempt.
  assert.strictEqual(assigned.payload.assigned, 5);
  assert.strictEqual(assigned.payload.assessment.status, 'assigned');
  assert.strictEqual(assigned.payload.assessment.attempts.length, 5);

  // The candidate's own Attempt, found on their own door, not by guessing an id.
  const mine = await call(candidateA, '/api/people/assessment-attempts/mine');
  assert.strictEqual(mine.status, 200, JSON.stringify(mine.payload));
  const own = mine.payload.attempts.filter((row) => row.assessmentId === String(assessment.id));
  assert.strictEqual(own.length, 1);
  const attemptId = own[0].id;
  assert.strictEqual(own[0].status, 'assigned');

  const started = await call(candidateA, `/api/people/assessment-attempts/${attemptId}/start`, { method: 'POST' });
  assert.strictEqual(started.status, 200, JSON.stringify(started.payload));
  assert.strictEqual(started.payload.paper.length, 10);
  assert.strictEqual(started.payload.attempt.status, 'in_progress');
  const startedAt = new Date(started.payload.attempt.startedAt).getTime();
  const deadlineAt = new Date(started.payload.attempt.deadlineAt).getTime();
  assert.strictEqual(deadlineAt - startedAt, 20 * 60 * 1000, 'the deadline is exactly the stored 20 minutes after the start');

  // The key never leaves the server before marking.
  const raw = JSON.stringify(started.payload);
  assert.ok(!raw.includes('correctOption'), 'the paper payload must not carry the key');
  assert.ok(!raw.includes('explanation'), 'the paper payload must not carry the explanation');
  for (const question of started.payload.paper) {
    assert.deepStrictEqual(Object.keys(question).sort(), [
      'chosenOption', 'optionA', 'optionB', 'optionC', 'otherText', 'position', 'questionText'
    ]);
  }

  // A second start returns the same paper and the same deadline.
  const again = await call(candidateA, `/api/people/assessment-attempts/${attemptId}/start`, { method: 'POST' });
  assert.strictEqual(again.status, 200);
  assert.strictEqual(again.payload.attempt.deadlineAt, started.payload.attempt.deadlineAt);
  assert.deepStrictEqual(
    again.payload.paper.map((row) => row.questionText),
    started.payload.paper.map((row) => row.questionText),
    'the same paper, in the same order'
  );
  const { rows: drawnRows } = await pool.query(
    'SELECT question_id, position FROM assessment_attempt_questions WHERE attempt_id = $1 ORDER BY position',
    [attemptId]
  );
  assert.strictEqual(drawnRows.length, 10, 'one paper, drawn once');
  assert.strictEqual(new Set(drawnRows.map((row) => String(row.question_id))).size, 10, 'without replacement');

  // Answer seven: six as the key, the seventh as "Khác".
  const keyed = await pool.query(
    'SELECT position, correct_option FROM assessment_attempt_questions WHERE attempt_id = $1 ORDER BY position',
    [attemptId]
  );
  for (let i = 0; i < 7; i += 1) {
    const row = keyed.rows[i];
    const body = i === 6
      ? { otherText: 'E. Dừng máy rồi báo Team Leader bằng bộ đàm' }
      : { chosenOption: row.correct_option };
    const saved = await call(candidateA, `/api/people/assessment-attempts/${attemptId}/answers/${row.position}`, {
      method: 'PATCH',
      body
    });
    assert.strictEqual(saved.status, 200, JSON.stringify(saved.payload));
  }

  // An autosave is idempotent, and a blank Answer is legal.
  const resaved = await call(candidateA, `/api/people/assessment-attempts/${attemptId}/answers/1`, {
    method: 'PATCH',
    body: { chosenOption: keyed.rows[0].correct_option }
  });
  assert.strictEqual(resaved.status, 200);

  const submitted = await call(candidateA, `/api/people/assessment-attempts/${attemptId}/submit`, { method: 'POST' });
  assert.strictEqual(submitted.status, 200, JSON.stringify(submitted.payload));
  assert.strictEqual(submitted.payload.attempt.status, 'submitted');
  assert.strictEqual(submitted.payload.attempt.submittedLate, false);

  const { rows: [stored] } = await pool.query(
    `SELECT score, status, submitted_late,
            (SELECT count(*)::int FROM assessment_attempt_questions q WHERE q.attempt_id = $1 AND q.other_text IS NOT NULL) AS other_count
       FROM assessment_attempts WHERE id = $1`,
    [attemptId]
  );
  assert.strictEqual(stored.score, 6, 'six keyed answers out of seven, the Other always 0');
  assert.strictEqual(stored.other_count, 1);
  assert.strictEqual(stored.status, 'submitted');

  // The register counts, over HTTP, and the Other is flagged on the Attempt.
  const detail = await call(supervisor, `/api/people/assessments/${assessment.id}`);
  assert.strictEqual(detail.status, 200);
  const row = detail.payload.assessment.attempts.find((attempt) => String(attempt.id) === String(attemptId));
  assert.strictEqual(row.status, 'submitted');
  assert.strictEqual(row.otherAnswerCount, 1);
  assert.strictEqual(row.blankCount, 3);

  const register = await call(supervisor, '/api/people/assessments');
  assert.strictEqual(register.status, 200);
  const listed = register.payload.assessments.find((entry) => String(entry.id) === String(assessment.id));
  assert.strictEqual(listed.awaitingMarkingCount, 1);
  assert.strictEqual(listed.assignedCount, 4, 'four of the five have not started');

  // A second submit is idempotent, not a 409: the candidate's own submit was
  // accepted, so a retried request reads the same record.
  const resubmitted = await call(candidateA, `/api/people/assessment-attempts/${attemptId}/submit`, { method: 'POST' });
  assert.strictEqual(resubmitted.status, 200);
});

// ---------------------------------------------------------------------------
// 3. The deadline: the server refuses past it, and finalises the Attempt itself
// ---------------------------------------------------------------------------

test('an answer past the deadline is 409, and the Attempt is finalised by the server with submitted_late', async () => {
  const stage3 = await stage({ bank: 10 });
  const assessment = await createAssessment(stage3.processUnitId);
  await call(supervisor, `/api/people/assessments/${assessment.id}/assign`, {
    method: 'POST',
    body: { employeeIds: [stage3.candidateBEmployeeId] }
  });

  const mine = await call(candidateB, '/api/people/assessment-attempts/mine');
  const attemptId = mine.payload.attempts
    .filter((row) => row.assessmentId === String(assessment.id))
    .map((row) => row.id)[0];

  const started = await call(candidateB, `/api/people/assessment-attempts/${attemptId}/start`, { method: 'POST' });
  assert.strictEqual(started.status, 200);
  await call(candidateB, `/api/people/assessment-attempts/${attemptId}/answers/1`, {
    method: 'PATCH',
    body: { chosenOption: 'C' }
  });

  // Move the clock, not the rule: the deadline is the server's, so the test
  // moves the stored one into the past rather than waiting 20 minutes.
  const { rows: [late] } = await pool.query(
    `UPDATE assessment_attempts
        SET started_at = now() - interval '21 minutes',
            deadline_at = now() - interval '1 minute'
      WHERE id = $1 RETURNING deadline_at`,
    [attemptId]
  );
  assert.ok(late.deadline_at);

  const refused = await call(candidateB, `/api/people/assessment-attempts/${attemptId}/answers/2`, {
    method: 'PATCH',
    body: { chosenOption: 'A' }
  });
  assert.strictEqual(refused.status, 409, JSON.stringify(refused.payload));

  const { rows: [finalised] } = await pool.query(
    'SELECT status, submitted_late, submitted_at = deadline_at AS closed_at_deadline FROM assessment_attempts WHERE id = $1',
    [attemptId]
  );
  assert.strictEqual(finalised.status, 'submitted');
  assert.strictEqual(finalised.submitted_late, true);
  assert.strictEqual(finalised.closed_at_deadline, true);

  const submit = await call(candidateB, `/api/people/assessment-attempts/${attemptId}/submit`, { method: 'POST' });
  assert.strictEqual(submit.status, 409, 'a candidate submit after the deadline is refused, the server already finalised');
});

// ---------------------------------------------------------------------------
// 4. A thin bank is a 409 at assign and at start, naming the count
// ---------------------------------------------------------------------------

test('a bank of 8 for a 10-Question Assessment is a 409 at assign and at start, naming 8', async () => {
  const stage3 = await stage({ bank: 8, prefix: 'Thin' });
  const assessment = await createAssessment(stage3.processUnitId);

  const refused = await call(supervisor, `/api/people/assessments/${assessment.id}/assign`, {
    method: 'POST',
    body: { employeeIds: [stage3.candidateAEmployeeId] }
  });
  assert.strictEqual(refused.status, 409, JSON.stringify(refused.payload));
  assert.match(refused.payload.message, /holds 8 active questions/);
  assert.match(refused.payload.message, /a paper needs 10/);
  assert.strictEqual(refused.payload.available, 8);
  assert.strictEqual(refused.payload.required, 10);

  const { rows: [{ n }] } = await pool.query(
    'SELECT count(*)::int AS n FROM assessment_attempts WHERE assessment_id = $1',
    [assessment.id]
  );
  assert.strictEqual(n, 0, 'a refused assign writes nothing');

  // The same refusal at start: the Attempt exists from an earlier, valid
  // assignment, and the bank shrank under it.
  const healthy = await stage({ bank: 10, prefix: 'Shrink' });
  const shrinking = await createAssessment(healthy.processUnitId);
  const assigned = await call(supervisor, `/api/people/assessments/${shrinking.id}/assign`, {
    method: 'POST',
    body: { employeeIds: [healthy.candidateAEmployeeId] }
  });
  assert.strictEqual(assigned.status, 201, JSON.stringify(assigned.payload));
  await pool.query(
    `UPDATE assessment_questions SET is_active = false
      WHERE id IN (SELECT id FROM assessment_questions WHERE org_unit_id = $1 ORDER BY id LIMIT 2)`,
    [healthy.processUnitId]
  );

  const mine = await call(candidateA, '/api/people/assessment-attempts/mine');
  const attemptId = mine.payload.attempts
    .filter((row) => row.assessmentId === String(shrinking.id))
    .map((row) => row.id)[0];
  const refusedStart = await call(candidateA, `/api/people/assessment-attempts/${attemptId}/start`, { method: 'POST' });
  assert.strictEqual(refusedStart.status, 409, JSON.stringify(refusedStart.payload));
  assert.match(refusedStart.payload.message, /holds 8 active questions/);
  assert.strictEqual(refusedStart.payload.available, 8);

  const { rows: [{ n: drawn }] } = await pool.query(
    'SELECT count(*)::int AS n FROM assessment_attempt_questions WHERE attempt_id = $1',
    [attemptId]
  );
  assert.strictEqual(drawn, 0, 'a refused start draws nothing');
});

test('a Section with no bank of its own is refused naming where the bank actually is', async () => {
  const sectionId = await insertOrgUnit({ siteId, name: `Section ${unique('S')}`, unitType: 'section' });
  const childId = await insertOrgUnit({ siteId, parentId: sectionId, name: `Cutting MTU ${unique('C')}` });
  await insertGrant({ accountId: supervisor.id, orgUnitId: sectionId, canWrite: true });
  await insertQuestions(childId, 10, 'Section');
  const employeeId = await insertEmployee({ orgUnitId: sectionId });

  const assessment = await createAssessment(sectionId);
  const refused = await call(supervisor, `/api/people/assessments/${assessment.id}/assign`, {
    method: 'POST',
    body: { employeeIds: [employeeId] }
  });
  assert.strictEqual(refused.status, 409, JSON.stringify(refused.payload));
  assert.match(refused.payload.message, /this process holds 0 active questions/);
  const named = refused.payload.elsewhere.find((row) => row.count === 10);
  assert.ok(named, `the refusal should name the node holding 10: ${JSON.stringify(refused.payload.elsewhere)}`);
  assert.ok(refused.payload.message.includes(named.name), 'the message names the node that holds the bank');
});

// ---------------------------------------------------------------------------
// 5. An Employee with no place to answer to fails the whole assignment, by name
// ---------------------------------------------------------------------------

test('an Employee with no current assignment and no default Org Unit is a 400 naming them, and nothing is written', async () => {
  const stage3 = await stage({ bank: 10 });
  const assessment = await createAssessment(stage3.processUnitId);
  const homelessId = await insertEmployee({ orgUnitId: null, firstName: 'Homeless' });

  const refused = await call(supervisor, `/api/people/assessments/${assessment.id}/assign`, {
    method: 'POST',
    body: { employeeIds: [stage3.namedAId, homelessId] }
  });
  assert.strictEqual(refused.status, 400, JSON.stringify(refused.payload));
  assert.ok(refused.payload.message.includes(String(homelessId)), refused.payload.message);
  assert.ok(refused.payload.message.includes('Homeless Sitter'), refused.payload.message);

  const { rows: [{ n }] } = await pool.query(
    'SELECT count(*)::int AS n FROM assessment_attempts WHERE assessment_id = $1',
    [assessment.id]
  );
  assert.strictEqual(n, 0, 'all-or-nothing: the Employee who could be assigned was not');
});

// ---------------------------------------------------------------------------
// 6. Somebody else's Attempt is a 403, and the candidate's own door is the only one
// ---------------------------------------------------------------------------

test('a candidate cannot start or answer somebody else\'s Attempt', async () => {
  const stage3 = await stage({ bank: 10 });
  const assessment = await createAssessment(stage3.processUnitId);
  await call(supervisor, `/api/people/assessments/${assessment.id}/assign`, {
    method: 'POST',
    body: { employeeIds: [stage3.candidateAEmployeeId, stage3.candidateBEmployeeId] }
  });

  const mine = await call(candidateA, '/api/people/assessment-attempts/mine');
  const attemptId = mine.payload.attempts
    .filter((row) => row.assessmentId === String(assessment.id))
    .map((row) => row.id)[0];

  const stolenStart = await call(candidateB, `/api/people/assessment-attempts/${attemptId}/start`, { method: 'POST' });
  assert.strictEqual(stolenStart.status, 403, JSON.stringify(stolenStart.payload));
  assert.strictEqual(stolenStart.payload.message, 'Only the Employee can sit their own Assessment');

  await call(candidateA, `/api/people/assessment-attempts/${attemptId}/start`, { method: 'POST' });
  const stolenAnswer = await call(candidateB, `/api/people/assessment-attempts/${attemptId}/answers/1`, {
    method: 'PATCH',
    body: { chosenOption: 'A' }
  });
  assert.strictEqual(stolenAnswer.status, 403);

  const stolenRead = await call(candidateB, `/api/people/assessment-attempts/${attemptId}`);
  assert.strictEqual(stolenRead.status, 403);
});

// ---------------------------------------------------------------------------
// 7. Assign refuses twice, and an assigned Assessment cannot be corrected or discarded
// ---------------------------------------------------------------------------

test('assigning the same Employee twice is a 409, and an assigned Assessment is frozen', async () => {
  const stage3 = await stage({ bank: 10 });
  const assessment = await createAssessment(stage3.processUnitId);

  const first = await call(supervisor, `/api/people/assessments/${assessment.id}/assign`, {
    method: 'POST',
    body: { employeeIds: [stage3.namedAId] }
  });
  assert.strictEqual(first.status, 201);

  const twice = await call(supervisor, `/api/people/assessments/${assessment.id}/assign`, {
    method: 'POST',
    body: { employeeIds: [stage3.namedAId] }
  });
  assert.strictEqual(twice.status, 409, JSON.stringify(twice.payload));
  assert.match(twice.payload.message, /already hold an Attempt/);

  const patch = await call(supervisor, `/api/people/assessments/${assessment.id}`, {
    method: 'PATCH',
    body: assessmentFacts({ title: 'Sửa tiêu đề sau khi giao' })
  });
  assert.strictEqual(patch.status, 409, JSON.stringify(patch.payload));

  const discard = await call(supervisor, `/api/people/assessments/${assessment.id}`, { method: 'DELETE' });
  assert.strictEqual(discard.status, 409, JSON.stringify(discard.payload));

  const closed = await call(supervisor, `/api/people/assessments/${assessment.id}/close`, { method: 'POST' });
  assert.strictEqual(closed.status, 200);
  assert.strictEqual(closed.payload.assessment.status, 'closed');
  assert.strictEqual(closed.payload.assessment.attempts.length, 1);
});

test('a draft is corrected and discarded, and an empty group is a 400', async () => {
  const { processUnitId } = await stage();
  const assessment = await createAssessment(processUnitId);

  const corrected = await call(supervisor, `/api/people/assessments/${assessment.id}`, {
    method: 'PATCH',
    body: assessmentFacts({ title: 'Kiểm tra Cutting MTU (sửa)', minutes: 25 })
  });
  assert.strictEqual(corrected.status, 200, JSON.stringify(corrected.payload));
  assert.strictEqual(corrected.payload.assessment.title, 'Kiểm tra Cutting MTU (sửa)');
  assert.strictEqual(corrected.payload.assessment.minutes, 25);
  assert.strictEqual(corrected.payload.assessment.number, assessment.number, 'the number never changes');

  const emptyGroup = await call(supervisor, `/api/people/assessments/${assessment.id}/assign`, {
    method: 'POST',
    body: { orgUnitIds: [], crewIds: [], employeeIds: [] }
  });
  assert.strictEqual(emptyGroup.status, 400, JSON.stringify(emptyGroup.payload));

  const discarded = await call(supervisor, `/api/people/assessments/${assessment.id}`, { method: 'DELETE' });
  assert.strictEqual(discarded.status, 204);

  const gone = await call(supervisor, `/api/people/assessments/${assessment.id}`);
  assert.strictEqual(gone.status, 404);
});

// ---------------------------------------------------------------------------
// 9. The create form's live reach
// ---------------------------------------------------------------------------

test('assign-preview answers how many Employees a group reaches, and how many have no Org Unit', async () => {
  const stage3 = await stage({ bank: 10 });
  const homelessId = await insertEmployee({ orgUnitId: null, firstName: 'Previewless' });

  const empty = await call(supervisor, '/api/people/assessments/assign-preview');
  assert.strictEqual(empty.status, 200, JSON.stringify(empty.payload));
  assert.strictEqual(empty.payload.count, 0);

  const group = await call(
    supervisor,
    `/api/people/assessments/assign-preview?orgUnitIds=${stage3.teamUnitId}&employeeIds=${stage3.namedAId},${homelessId}`
  );
  assert.strictEqual(group.status, 200, JSON.stringify(group.payload));
  assert.strictEqual(group.payload.count, 5, 'three at the Team Org Unit, two named, one of whom has no Org Unit');
  assert.strictEqual(group.payload.unresolvedCount, 1);
  assert.strictEqual(String(group.payload.unresolved[0].employeeId), String(homelessId));

  const bad = await call(supervisor, '/api/people/assessments/assign-preview?orgUnitIds=abc');
  assert.strictEqual(bad.status, 400, JSON.stringify(bad.payload));
});

// ---------------------------------------------------------------------------
// 8. Who may do any of this
// ---------------------------------------------------------------------------

test('an operator with SIT cannot create or assign, and a supervisor outside the Grant is a 403', async () => {
  const stage3 = await stage({ bank: 10 });
  const outsider = await insertAccount({ role: 'supervisor' });

  const byOperator = await call(candidateA, '/api/people/assessments', {
    method: 'POST',
    body: { orgUnitId: stage3.processUnitId, ...assessmentFacts() }
  });
  assert.strictEqual(byOperator.status, 403, JSON.stringify(byOperator.payload));
  assert.strictEqual(byOperator.payload.code, 'PERMISSION_REQUIRED');

  const byOutsider = await call(outsider, '/api/people/assessments', {
    method: 'POST',
    body: { orgUnitId: stage3.processUnitId, ...assessmentFacts() }
  });
  assert.strictEqual(byOutsider.status, 403, JSON.stringify(byOutsider.payload));
  assert.strictEqual(byOutsider.payload.message, "Outside the caller's granted Org Units");

  const assessment = await createAssessment(stage3.processUnitId);
  const outsiderAssign = await call(outsider, `/api/people/assessments/${assessment.id}/assign`, {
    method: 'POST',
    body: { employeeIds: [stage3.namedAId] }
  });
  assert.strictEqual(outsiderAssign.status, 403);
  assert.strictEqual(outsiderAssign.payload.message, "Outside the caller's granted Org Units");

  const unknown = await call(supervisor, '/api/people/assessments/99999999');
  assert.strictEqual(unknown.status, 404);
});
