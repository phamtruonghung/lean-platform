/*
 * The register's filters, cancel and retake — issue #588, ADR-0068, slice 6 —
 * measured over HTTP against a real database and a real local session, the seam
 * people-assessment-marking.test.js uses (the fixtures are the same shape).
 *
 * What this file proves: a late assignment leaves every existing Attempt and
 * the Assessment's facts alone; a closed Assessment refuses a start and a
 * retake; a cancelled Attempt is in none of the four counts and cannot be
 * cancelled twice; a reason is required; a retake makes Attempt 2, the latest
 * marked Attempt is the counting one, and `failed=true` follows it; a retake of
 * an unfinished or superseded Attempt is a 409; a refused assignment writes
 * nothing; the register filters by date; and a caller who may not read a score
 * does not learn who failed from the filter.
 *
 * Every case builds its own Org Units, and `test.after` deletes exactly what
 * this file inserted.
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
     VALUES ($1, 'Assessment Register Test Account', $2, $3, $4, true, 'approved') RETURNING id`,
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
let admin;

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
     VALUES ($1, 'Assessment Register Test Site', 'Asia/Ho_Chi_Minh') RETURNING id`,
    [unique('ST')]
  );
  siteId = site.id;
  insertedSiteIds.push(siteId);

  marker = await insertAccount({ role: 'supervisor' });
  colleague = await insertAccount({ role: 'supervisor' });
  admin = await insertAccount({ role: 'admin' });
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

const api = '/api/people';

// A process with a bank of 10 and a team Org Unit under it; `marker` writes at
// the process.
async function stage() {
  const processUnitId = await insertOrgUnit({ siteId, name: `Cutting MTU ${unique('P')}` });
  const teamUnitId = await insertOrgUnit({ siteId, parentId: processUnitId, name: `Team ${unique('T')}` });
  await insertGrant({ accountId: marker.id, orgUnitId: processUnitId, canWrite: true });
  await insertQuestions(processUnitId, 10);
  return { processUnitId, teamUnitId };
}

// An Employee in the team, with an Account that may sit its own Attempts.
async function person(teamUnitId, firstName) {
  const employeeId = await insertEmployee({ orgUnitId: teamUnitId, firstName });
  const account = await insertAccount({ role: 'operator', employeeId });
  return { employeeId, account };
}

async function create(processUnitId, extra = {}) {
  const created = await call(marker, `${api}/assessments`, {
    method: 'POST',
    body: { orgUnitId: processUnitId, title: 'Kiểm tra quy trình Cutting MTU', questionCount: 10, ...extra }
  });
  assert.strictEqual(created.status, 201, JSON.stringify(created.payload));
  return created.payload.assessment;
}

async function assign(assessmentId, employeeIds, who = marker) {
  return call(who, `${api}/assessments/${assessmentId}/assign`, {
    method: 'POST',
    body: { employeeIds: employeeIds.map(String) }
  });
}

async function attemptsOf(assessmentId, employeeId) {
  const { rows } = await pool.query(
    `SELECT id, attempt_no, status, retake_reason, org_unit_id, org_unit_resolved_on::text AS resolved_on
       FROM assessment_attempts WHERE assessment_id = $1 AND employee_id = $2 ORDER BY attempt_no`,
    [assessmentId, employeeId]
  );
  return rows;
}

// Start, answer `correct` Questions with the key, submit, then mark. Blank
// Answers score 0, so the final score is `correct`.
async function sitAndMark(sitter, attemptId, correct) {
  const started = await call(sitter, `${api}/assessment-attempts/${attemptId}/start`, { method: 'POST' });
  assert.strictEqual(started.status, 200, JSON.stringify(started.payload));
  const { rows: keyed } = await pool.query(
    'SELECT position, correct_option FROM assessment_attempt_questions WHERE attempt_id = $1 ORDER BY position',
    [attemptId]
  );
  for (const row of keyed.slice(0, correct)) {
    const saved = await call(sitter, `${api}/assessment-attempts/${attemptId}/answers/${row.position}`, {
      method: 'PATCH',
      body: { chosenOption: row.correct_option }
    });
    assert.strictEqual(saved.status, 200, JSON.stringify(saved.payload));
  }
  const submitted = await call(sitter, `${api}/assessment-attempts/${attemptId}/submit`, { method: 'POST' });
  assert.strictEqual(submitted.status, 200, JSON.stringify(submitted.payload));
  const marked = await call(marker, `${api}/assessment-attempts/${attemptId}/mark`, { method: 'POST', body: {} });
  assert.strictEqual(marked.status, 200, JSON.stringify(marked.payload));
  assert.strictEqual(marked.payload.attempt.finalScore, correct);
}

function assertOutsideScope(result, what) {
  assert.strictEqual(result.status, 403, `${what}: ${JSON.stringify(result.payload)}`);
  assert.strictEqual(result.payload.message, "Outside the caller's granted Org Units", what);
}

// ---------------------------------------------------------------------------

test("five more people assigned to a live Assessment leave every existing Attempt and the Assessment's facts untouched", async () => {
  const { processUnitId, teamUnitId } = await stage();
  const first = await person(teamUnitId, 'First');
  const assessment = await create(processUnitId, { dueOn: '2031-06-30' });
  assert.strictEqual((await assign(assessment.id, [first.employeeId])).status, 201);

  const snapshot = async () => {
    const { rows } = await pool.query(
      `SELECT id, attempt_no, status, org_unit_id, updated_at FROM assessment_attempts
        WHERE assessment_id = $1 ORDER BY id`,
      [assessment.id]
    );
    const { rows: [facts] } = await pool.query(
      `SELECT title, question_count, minutes, pass_mark, attempts_allowed, due_on::text AS due_on
         FROM assessments WHERE id = $1`,
      [assessment.id]
    );
    return { rows, facts };
  };
  const before = await snapshot();

  const more = [];
  for (let i = 0; i < 5; i += 1) more.push((await person(teamUnitId, `More${i}`)).employeeId);
  const result = await assign(assessment.id, more);
  assert.strictEqual(result.status, 201, JSON.stringify(result.payload));
  assert.strictEqual(result.payload.assigned, 5);

  const after = await snapshot();
  assert.deepStrictEqual(after.facts, before.facts);
  assert.deepStrictEqual(after.rows.slice(0, before.rows.length), before.rows, 'the existing Attempt is untouched');
  assert.strictEqual(after.rows.length, 6);
});

test('assign including one already-assigned Employee writes nothing', async () => {
  const { processUnitId, teamUnitId } = await stage();
  const first = await person(teamUnitId, 'Holder');
  const fresh = await person(teamUnitId, 'Fresh');
  const assessment = await create(processUnitId);
  assert.strictEqual((await assign(assessment.id, [first.employeeId])).status, 201);

  const count = async () => (await pool.query(
    'SELECT count(*)::int AS n FROM assessment_attempts WHERE assessment_id = $1', [assessment.id]
  )).rows[0].n;
  const before = await count();
  const refused = await assign(assessment.id, [fresh.employeeId, first.employeeId]);
  assert.strictEqual(refused.status, 409, JSON.stringify(refused.payload));
  assert.strictEqual(await count(), before, 'the fresh Employee was not assigned either');
});

test('closing an Assessment makes a start a 409 and a retake a 409', async () => {
  const { processUnitId, teamUnitId } = await stage();
  const sitter = await person(teamUnitId, 'Closer');
  const other = await person(teamUnitId, 'Finisher');
  const assessment = await create(processUnitId, { attemptsAllowed: 2 });
  assert.strictEqual((await assign(assessment.id, [sitter.employeeId, other.employeeId])).status, 201);

  const [sitting] = await attemptsOf(assessment.id, sitter.employeeId);
  const [done] = await attemptsOf(assessment.id, other.employeeId);
  await sitAndMark(other.account, done.id, 5);

  const closed = await call(marker, `${api}/assessments/${assessment.id}/close`, { method: 'POST' });
  assert.strictEqual(closed.status, 200, JSON.stringify(closed.payload));

  const start = await call(sitter.account, `${api}/assessment-attempts/${sitting.id}/start`, { method: 'POST' });
  assert.strictEqual(start.status, 409, JSON.stringify(start.payload));
  const retake = await call(marker, `${api}/assessment-attempts/${done.id}/retake`, {
    method: 'POST', body: { reason: 'Máy tính bảng hỏng' }
  });
  assert.strictEqual(retake.status, 409, JSON.stringify(retake.payload));
  assert.match(retake.payload.message, /closed/);
});

test('a cancelled Attempt is in none of the four counts and a second cancel is 409', async () => {
  const { processUnitId, teamUnitId } = await stage();
  const left = await person(teamUnitId, 'Leaver');
  const stays = await person(teamUnitId, 'Stayer');
  const assessment = await create(processUnitId);
  assert.strictEqual((await assign(assessment.id, [left.employeeId, stays.employeeId])).status, 201);
  const [leaving] = await attemptsOf(assessment.id, left.employeeId);

  const cancelled = await call(marker, `${api}/assessment-attempts/${leaving.id}/cancel`, {
    method: 'POST', body: { reason: '  Đã nghỉ việc  ' }
  });
  assert.strictEqual(cancelled.status, 200, JSON.stringify(cancelled.payload));
  assert.strictEqual(cancelled.payload.attempt.status, 'cancelled');
  assert.strictEqual(cancelled.payload.attempt.markingNote, 'Đã nghỉ việc', 'the reason is stored trimmed');

  const register = await call(marker, `${api}/assessments?orgUnitId=${processUnitId}`);
  const row = register.payload.assessments.find((entry) => String(entry.id) === String(assessment.id));
  assert.strictEqual(row.assignedCount, 1, 'only the person who stays');
  assert.strictEqual(row.runningCount + row.awaitingMarkingCount + row.markedCount, 0);

  const again = await call(marker, `${api}/assessment-attempts/${leaving.id}/cancel`, {
    method: 'POST', body: { reason: 'Một lần nữa' }
  });
  assert.strictEqual(again.status, 409, JSON.stringify(again.payload));
});

test('cancel and retake without a reason are 400', async () => {
  const { processUnitId, teamUnitId } = await stage();
  const sitter = await person(teamUnitId, 'Reasoned');
  const assessment = await create(processUnitId, { attemptsAllowed: 2 });
  assert.strictEqual((await assign(assessment.id, [sitter.employeeId])).status, 201);
  const [attempt] = await attemptsOf(assessment.id, sitter.employeeId);
  await sitAndMark(sitter.account, attempt.id, 4);

  for (const door of ['cancel', 'retake']) {
    for (const body of [undefined, {}, { reason: 5 }, { reason: '   ' }, { reason: 'ab' }, { reason: 'x'.repeat(2001) }]) {
      const result = await call(marker, `${api}/assessment-attempts/${attempt.id}/${door}`, { method: 'POST', body });
      assert.strictEqual(result.status, 400, `${door} ${JSON.stringify(body)}: ${JSON.stringify(result.payload)}`);
    }
  }
  assert.strictEqual((await attemptsOf(assessment.id, sitter.employeeId)).length, 1, 'no retake was written');
});

test('cancel and retake outside write reach are 403 after the 404', async () => {
  const { processUnitId, teamUnitId } = await stage();
  const sitter = await person(teamUnitId, 'Fenced');
  const assessment = await create(processUnitId, { attemptsAllowed: 2 });
  assert.strictEqual((await assign(assessment.id, [sitter.employeeId])).status, 201);
  const [attempt] = await attemptsOf(assessment.id, sitter.employeeId);

  for (const door of ['cancel', 'retake']) {
    assertOutsideScope(
      await call(colleague, `${api}/assessment-attempts/${attempt.id}/${door}`, { method: 'POST', body: { reason: 'Không có quyền' } }),
      door
    );
    const unknown = await call(colleague, `${api}/assessment-attempts/999999999/${door}`, { method: 'POST', body: {} });
    assert.strictEqual(unknown.status, 404, `${door} on an unknown Attempt is 404 before scope`);
  }
});

test('with attemptsAllowed 2 a marked Attempt is retaken as Attempt 2, a third retake is 409, and a lower marked Attempt 2 is the counting score', async () => {
  const { processUnitId, teamUnitId } = await stage();
  const sitter = await person(teamUnitId, 'Retaker');
  const assessment = await create(processUnitId, { attemptsAllowed: 2 }); // pass mark 8
  assert.strictEqual((await assign(assessment.id, [sitter.employeeId])).status, 201);
  const [first] = await attemptsOf(assessment.id, sitter.employeeId);
  await sitAndMark(sitter.account, first.id, 9); // above the pass mark

  // Attempt 1 passed, so the Assessment is not in the failed list yet.
  const passing = await call(marker, `${api}/assessments?failed=true&orgUnitId=${processUnitId}`);
  assert.strictEqual(passing.status, 200, JSON.stringify(passing.payload));
  assert.strictEqual(passing.payload.assessments.length, 0);

  const retake = await call(marker, `${api}/assessment-attempts/${first.id}/retake`, {
    method: 'POST', body: { reason: '  Muốn thi lại để cải thiện  ' }
  });
  assert.strictEqual(retake.status, 201, JSON.stringify(retake.payload));
  assert.strictEqual(retake.payload.attempt.attemptNo, 2);
  assert.strictEqual(retake.payload.attempt.status, 'assigned');
  const rows = await attemptsOf(assessment.id, sitter.employeeId);
  assert.strictEqual(rows[1].retake_reason, 'Muốn thi lại để cải thiện');
  assert.strictEqual(rows[1].org_unit_id, rows[0].org_unit_id, 'the node is copied from Attempt 1');
  assert.strictEqual(rows[1].resolved_on, rows[0].resolved_on);
  const { rows: [paper] } = await pool.query(
    'SELECT count(*)::int AS n FROM assessment_attempt_questions WHERE attempt_id = $1', [rows[1].id]
  );
  assert.strictEqual(paper.n, 0, 'no paper until it starts');

  // The earlier Attempt is no longer the latest; the new one is not final.
  const second = rows[1];
  const stale = await call(marker, `${api}/assessment-attempts/${first.id}/retake`, {
    method: 'POST', body: { reason: 'Một lần nữa' }
  });
  assert.strictEqual(stale.status, 409);
  assert.match(stale.payload.message, /not the latest/);
  const early = await call(marker, `${api}/assessment-attempts/${second.id}/retake`, {
    method: 'POST', body: { reason: 'Chưa thi xong' }
  });
  assert.strictEqual(early.status, 409);
  assert.match(early.payload.message, /not final/);

  // While Attempt 2 is unfinished Attempt 1 is the counting one.
  const midway = await call(marker, `${api}/assessments/${assessment.id}`);
  const midwayRows = midway.payload.assessment.attempts;
  assert.deepStrictEqual(midwayRows.map((a) => [a.attemptNo, a.isCounting, a.isLatest]), [[1, true, false], [2, false, true]]);

  await sitAndMark(sitter.account, second.id, 3); // lower, and below the pass mark

  const third = await call(marker, `${api}/assessment-attempts/${second.id}/retake`, {
    method: 'POST', body: { reason: 'Lần thứ ba' }
  });
  assert.strictEqual(third.status, 409, JSON.stringify(third.payload));
  assert.match(third.payload.message, /allows 2/);

  const detail = await call(marker, `${api}/assessments/${assessment.id}`);
  const { attempts, viewerMayChange, viewerMayMark } = detail.payload.assessment;
  assert.strictEqual(viewerMayChange, true);
  assert.strictEqual(viewerMayMark, true);
  assert.deepStrictEqual(
    attempts.map((a) => [a.attemptNo, a.isCounting, a.isLatest, a.finalScore, a.viewerMayChange]),
    [[1, false, false, 9, true], [2, true, true, 3, true]]
  );
  assert.strictEqual(attempts[0].retakeReason, null);
  assert.strictEqual(attempts[1].retakeReason, 'Muốn thi lại để cải thiện');

  // The counting score is 3, so the Assessment is now in the failed list.
  const failed = await call(marker, `${api}/assessments?failed=true&orgUnitId=${processUnitId}`);
  assert.deepStrictEqual(failed.payload.assessments.map((a) => String(a.id)), [String(assessment.id)]);
  assert.strictEqual(failed.payload.total, 1);
  // Counts are per Attempt row: two marked rows for one person.
  assert.strictEqual(failed.payload.assessments[0].markedCount, 2);

  // The candidate's own list shows both numbers.
  const mine = await call(sitter.account, `${api}/assessment-attempts/mine`);
  assert.deepStrictEqual(
    mine.payload.attempts.filter((a) => a.assessmentId === String(assessment.id)).map((a) => a.attemptNo),
    [1, 2]
  );
});

test('retaking an Attempt that is not final or not the latest is 409', async () => {
  const { processUnitId, teamUnitId } = await stage();
  const sitter = await person(teamUnitId, 'Unfinished');
  const assessment = await create(processUnitId, { attemptsAllowed: 3 });
  assert.strictEqual((await assign(assessment.id, [sitter.employeeId])).status, 201);
  const [first] = await attemptsOf(assessment.id, sitter.employeeId);

  const unstarted = await call(marker, `${api}/assessment-attempts/${first.id}/retake`, {
    method: 'POST', body: { reason: 'Chưa bắt đầu' }
  });
  assert.strictEqual(unstarted.status, 409, JSON.stringify(unstarted.payload));
  assert.match(unstarted.payload.message, /not final/);

  await sitAndMark(sitter.account, first.id, 6);
  const ok = await call(marker, `${api}/assessment-attempts/${first.id}/retake`, {
    method: 'POST', body: { reason: 'Lần hai' }
  });
  assert.strictEqual(ok.status, 201, JSON.stringify(ok.payload));
  const repeat = await call(marker, `${api}/assessment-attempts/${first.id}/retake`, {
    method: 'POST', body: { reason: 'Lần hai nữa' }
  });
  assert.strictEqual(repeat.status, 409, JSON.stringify(repeat.payload));
  assert.match(repeat.payload.message, /not the latest/);
  assert.strictEqual((await attemptsOf(assessment.id, sitter.employeeId)).length, 2);
});

test('the register filters by date range and rejects a malformed date with 400', async () => {
  const { processUnitId } = await stage();
  const march = await create(processUnitId, { dueOn: '2031-03-15' });
  const april = await create(processUnitId, { dueOn: '2031-04-20' });
  const undated = await create(processUnitId);
  const ids = async (query) => {
    const result = await call(marker, `${api}/assessments?orgUnitId=${processUnitId}&${query}`);
    assert.strictEqual(result.status, 200, JSON.stringify(result.payload));
    assert.strictEqual(result.payload.total, result.payload.assessments.length);
    return result.payload.assessments.map((a) => String(a.id)).sort();
  };
  const sorted = (...list) => list.map((a) => String(a.id)).sort();

  assert.deepStrictEqual(await ids('from=2031-03-15&to=2031-03-15'), sorted(march), 'both ends are inclusive');
  assert.deepStrictEqual(await ids('from=2031-03-16&to=2031-12-31'), sorted(april));
  assert.deepStrictEqual(
    await ids('to=2031-04-20'),
    sorted(march, april, undated),
    'an undated Assessment sits on the day it was created, which is before 2031'
  );

  // The undated one sits on its creation day at the Site.
  const { rows: [day] } = await pool.query(
    `SELECT plant_date($1, created_at)::text AS day FROM assessments WHERE id = $2`,
    [processUnitId, undated.id]
  );
  assert.deepStrictEqual(await ids(`from=${day.day}&to=${day.day}`), sorted(undated));

  for (const query of ['from=2026-13-40', 'to=31-12-2031', 'from=abc', 'from=2031-05-01&to=2031-04-01', 'failed=yes']) {
    const bad = await call(marker, `${api}/assessments?${query}`);
    assert.strictEqual(bad.status, 400, `${query}: ${JSON.stringify(bad.payload)}`);
  }
});

test('failed=true hides an Assessment from a caller who may not read the score', async () => {
  const { processUnitId, teamUnitId } = await stage();
  const sitter = await person(teamUnitId, 'Failing');
  const assessment = await create(processUnitId);
  assert.strictEqual((await assign(assessment.id, [sitter.employeeId])).status, 201);
  const [attempt] = await attemptsOf(assessment.id, sitter.employeeId);
  await sitAndMark(sitter.account, attempt.id, 2);

  const listed = async (who) => (await call(who, `${api}/assessments?failed=true&orgUnitId=${processUnitId}`)).payload.assessments.length;
  assert.strictEqual(await listed(marker), 1);
  assert.strictEqual(await listed(admin), 1);
  assert.strictEqual(await listed(colleague), 0, 'no reach means the filter cannot reveal the failure');
  assert.strictEqual(await listed(sitter.account), 1, 'the person reads their own score');

  // The colleague still sees the Assessment and its counts without the filter.
  const plain = await call(colleague, `${api}/assessments?orgUnitId=${processUnitId}`);
  assert.strictEqual(plain.payload.assessments[0].markedCount, 1);

  // And the detail names which sitting counts, though not its score; the
  // buttons' reasons say the colleague may neither change nor mark here.
  const detail = await call(colleague, `${api}/assessments/${assessment.id}`);
  const row = detail.payload.assessment;
  assert.strictEqual(row.attempts[0].isCounting, true);
  assert.strictEqual(row.attempts[0].scoreHidden, true);
  assert.strictEqual(row.attempts[0].finalScore, null);
  assert.strictEqual(row.attempts[0].viewerMayChange, false);
  assert.strictEqual(row.viewerMayChange, false);
  assert.strictEqual(row.viewerMayMark, false);
});
