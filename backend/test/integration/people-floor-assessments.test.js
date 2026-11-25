/*
 * An Employee with no Account sitting an Assessment at the shared floor device
 * (issue #588, ADR-0068, slice 5), measured over HTTP against a real database -
 * the seam floor-training.test.js and people-assessment-attempts.test.js use.
 *
 * Every case builds its own Assessment over a shared bank, and `test.after`
 * deletes exactly what this file inserted (Assessments take their Attempts,
 * papers and sittings with them, then devices, Accounts, Employees, Org Units
 * and the Site). Scores are read from the database where they are proved: no
 * route shows one before marking (spec section 3.12).
 */

const test = require('node:test');
const assert = require('node:assert');
const { tokenFor } = require('../helpers/session');

let server;
let base;
let pool;
let closePool;

const insertedAccountIds = [];
const insertedSiteIds = [];
const insertedOrgUnitIds = [];
const insertedEmployeeIds = [];
const insertedDeviceIds = [];

let counter = 0;
function unique(prefix) {
  counter += 1;
  return `${prefix}${process.pid}${counter}`;
}

async function insertAccount({ role }) {
  const subject = unique('fasacct');
  const { rows: [row] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status)
     VALUES ($1, 'Floor Assessment Test Account', $2, $3, TRUE, 'approved') RETURNING id`,
    [`${subject}@example.com`, role, subject]
  );
  insertedAccountIds.push(row.id);
  return { id: row.id, token: { authorization: `Bearer ${await tokenFor(subject)}` } };
}

async function insertGrant(account, orgUnitId) {
  await pool.query(
    'INSERT INTO app_user_org_units (app_user_id, org_unit_id, can_write) VALUES ($1, $2, TRUE)',
    [account.id, orgUnitId]
  );
}

async function insertOrgUnit(siteId, { parentId = null, unitType = 'area', name }) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, $2, $3, $4, $5) RETURNING id`,
    [siteId, parentId, unique('FAOU'), name, unitType]
  );
  insertedOrgUnitIds.push(row.id);
  return row.id;
}

async function insertEmployee(orgUnitId, firstName) {
  const { rows: [row] } = await pool.query(
    `INSERT INTO employees (employee_no, first_name, last_name, default_org_unit_id, is_active)
     VALUES ($1, $2, 'Sitter', $3, TRUE) RETURNING id, employee_no`,
    [unique('FAE'), firstName, orgUnitId]
  );
  insertedEmployeeIds.push(row.id);
  return row;
}

async function request(method, path, headers, body) {
  const response = await fetch(`${base}${path}`, {
    method,
    headers: { ...headers, ...(body === undefined ? {} : { 'content-type': 'application/json' }) },
    body: body === undefined ? undefined : JSON.stringify(body)
  });
  return { status: response.status, body: await response.json().catch(() => null) };
}

async function registerDevice(orgUnitId, name) {
  const { status, body } = await request('POST', '/api/maintenance/floor-devices', admin.token, { orgUnitId, name });
  assert.strictEqual(status, 201, JSON.stringify(body));
  insertedDeviceIds.push(body.device.id);
  return { id: body.device.id, credential: body.credential };
}

async function newSitter(firstName, orgUnitId = cellId) {
  const employee = await insertEmployee(orgUnitId, firstName);
  const { status, body } = await request(
    'PUT',
    `/api/maintenance/floor-technician-credentials/${employee.id}`,
    admin.token,
    { pin: '4321' }
  );
  assert.strictEqual(status, 200, JSON.stringify(body));
  return employee;
}

async function identify(device, employee) {
  const { status, body } = await request(
    'POST',
    '/api/maintenance/floor/identify',
    { 'x-floor-device': device.credential },
    { employeeNo: employee.employee_no, pin: '4321' }
  );
  assert.strictEqual(status, 200, JSON.stringify(body));
  return body.identification;
}

const withIdentification = (device, identification) => ({
  'x-floor-device': device.credential,
  'x-technician-identification': identification
});
const withSitting = (device, sittingToken) => ({
  'x-floor-device': device.credential,
  'x-assessment-sitting': sittingToken
});

const FLOOR = '/api/maintenance/floor/assessments';
const mine = (headers) => request('GET', `${FLOOR}/mine`, headers);
const start = (headers, attemptId) => request('POST', `${FLOOR}/${attemptId}/start`, headers, {});
const read = (headers, attemptId) => request('GET', `${FLOOR}/${attemptId}`, headers);
const answer = (headers, attemptId, position, body) =>
  request('PATCH', `${FLOOR}/${attemptId}/answers/${position}`, headers, body);
const submit = (headers, attemptId) => request('POST', `${FLOOR}/${attemptId}/submit`, headers, {});
const result = (headers, attemptId) => request('GET', `${FLOOR}/${attemptId}/result`, headers);

let admin;
let siteId;
let processId;
let lineId;
let cellId;
let otherLineId;
let device;      // at the line: reaches the cell
let otherDevice; // at the other line: reaches neither

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

  admin = await insertAccount({ role: 'admin' });
  const { rows: [site] } = await pool.query(
    `INSERT INTO sites (code, name, timezone)
     VALUES ($1, 'Floor Assessment Test Site', 'Asia/Ho_Chi_Minh') RETURNING id`,
    [unique('FAS')]
  );
  siteId = site.id;
  insertedSiteIds.push(siteId);

  const areaId = await insertOrgUnit(siteId, { name: 'FA Area' });
  lineId = await insertOrgUnit(siteId, { parentId: areaId, unitType: 'line', name: 'FA Line' });
  cellId = await insertOrgUnit(siteId, { parentId: lineId, unitType: 'cell', name: 'FA Cell' });
  otherLineId = await insertOrgUnit(siteId, { parentId: areaId, unitType: 'line', name: 'FA Other Line' });
  processId = await insertOrgUnit(siteId, { name: 'FA Process' });

  for (let i = 1; i <= 12; i += 1) {
    await pool.query(
      `INSERT INTO assessment_questions
         (org_unit_id, question_text, option_a, option_b, option_c, correct_option, explanation)
       VALUES ($1, $2, $3, $4, $5, 'C', $6)`,
      [processId, `Câu ${i} của quy trình sàn là gì?`, `A ${i}`, `B ${i}`, `C ${i}`, `Lý do ${i}.`]
    );
  }

  device = await registerDevice(lineId, 'FA Line terminal');
  otherDevice = await registerDevice(otherLineId, 'FA Other Line terminal');
});

test.after(async () => {
  await pool.query('DELETE FROM assessments WHERE site_id = ANY($1)', [insertedSiteIds]);
  await pool.query('DELETE FROM assessment_questions WHERE org_unit_id = ANY($1)', [insertedOrgUnitIds]);
  await pool.query('DELETE FROM technician_identifications WHERE floor_device_id = ANY($1)', [insertedDeviceIds]);
  await pool.query('DELETE FROM employee_floor_credentials WHERE employee_id = ANY($1)', [insertedEmployeeIds]);
  await pool.query('DELETE FROM floor_devices WHERE id = ANY($1)', [insertedDeviceIds]);
  await pool.query('DELETE FROM app_user_org_units WHERE app_user_id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM app_users WHERE id = ANY($1)', [insertedAccountIds]);
  await pool.query('DELETE FROM employees WHERE id = ANY($1)', [insertedEmployeeIds]);
  await pool.query('DELETE FROM org_units WHERE id = ANY($1)', [[...insertedOrgUnitIds].reverse()]);
  await pool.query('DELETE FROM sites WHERE id = ANY($1)', [insertedSiteIds]);
  await new Promise((resolve) => server.close(resolve));
  await closePool();
});

// An Assessment over the shared bank, assigned to the named Employees; returns
// each one's Attempt id by Employee id.
async function assignTo(...employees) {
  const created = await request('POST', '/api/people/assessments', admin.token, {
    orgUnitId: processId,
    title: 'Kiểm tra sàn',
    questionCount: 10
  });
  assert.strictEqual(created.status, 201, JSON.stringify(created.body));
  const assessmentId = created.body.assessment.id;
  const assigned = await request('POST', `/api/people/assessments/${assessmentId}/assign`, admin.token, {
    employeeIds: employees.map((employee) => employee.id)
  });
  assert.strictEqual(assigned.status, 201, JSON.stringify(assigned.body));
  const attempts = {};
  for (const attempt of assigned.body.assessment.attempts) attempts[attempt.employeeId] = attempt.id;
  return attempts;
}

// A sitter with an Assessment assigned and started at `device`.
async function startedSitter(firstName) {
  const employee = await newSitter(firstName);
  const attempts = await assignTo(employee);
  const attemptId = attempts[employee.id];
  const identification = await identify(device, employee);
  const started = await start(withIdentification(device, identification), attemptId);
  assert.strictEqual(started.status, 200, JSON.stringify(started.body));
  return { employee, attemptId, started: started.body, sitting: withSitting(device, started.body.sittingToken) };
}

const attemptRow = async (attemptId) =>
  (await pool.query('SELECT status, submitted_late, score FROM assessment_attempts WHERE id = $1', [attemptId])).rows[0];

test('an Employee with no Account identifies at the device, sees one open Attempt, starts, answers and submits', async () => {
  const employee = await newSitter('Alone');
  const attempts = await assignTo(employee);
  const attemptId = attempts[employee.id];

  const { rows: [accounts] } = await pool.query(
    'SELECT count(*)::int AS n FROM app_users WHERE employee_id = $1',
    [employee.id]
  );
  assert.strictEqual(accounts.n, 0, 'the Employee holds no Account');

  const identification = await identify(device, employee);
  const listed = await mine(withIdentification(device, identification));
  assert.strictEqual(listed.status, 200, JSON.stringify(listed.body));
  assert.strictEqual(listed.body.attempts.length, 1);
  assert.strictEqual(String(listed.body.attempts[0].id), String(attemptId));
  assert.strictEqual(listed.body.attempts[0].status, 'assigned');

  const started = await start(withIdentification(device, identification), attemptId);
  assert.strictEqual(started.status, 200, JSON.stringify(started.body));
  assert.strictEqual(started.body.paper.length, 10);
  assert.ok(started.body.deadlineAt);
  assert.ok(started.body.serverNow);
  assert.strictEqual(typeof started.body.sittingToken, 'string');

  const sitting = withSitting(device, started.body.sittingToken);
  for (let position = 1; position <= 9; position += 1) {
    const saved = await answer(sitting, attemptId, position, { chosenOption: 'C' });
    assert.strictEqual(saved.status, 200, JSON.stringify(saved.body));
  }
  const other = await answer(sitting, attemptId, 10, { otherText: 'Dừng máy và gọi Team Leader' });
  assert.strictEqual(other.status, 200, JSON.stringify(other.body));

  const reread = await read(sitting, attemptId);
  assert.strictEqual(reread.status, 200);
  assert.strictEqual(reread.body.paper.filter((q) => q.chosenOption === 'C').length, 9);

  const submitted = await submit(sitting, attemptId);
  assert.strictEqual(submitted.status, 200, JSON.stringify(submitted.body));
  assert.strictEqual(submitted.body.attempt.status, 'submitted');
  const row = await attemptRow(attemptId);
  assert.strictEqual(row.status, 'submitted');
  assert.strictEqual(row.score, 9);

  const notMarked = await result(sitting, attemptId);
  assert.strictEqual(notMarked.status, 409, JSON.stringify(notMarked.body));

  // Once submitted, it is no longer an open Attempt.
  const after = await mine(withIdentification(device, await identify(device, employee)));
  assert.strictEqual(after.body.attempts.length, 0);
});

test('a second Employee identifying on the same device mid-paper cannot touch the first Attempt, and does not stop the first sitting', async () => {
  const first = await startedSitter('First');
  const second = await newSitter('Second');
  const secondIdentification = await identify(device, second);
  const secondHeaders = withIdentification(device, secondIdentification);

  const intruding = await start(secondHeaders, first.attemptId);
  assert.strictEqual(intruding.status, 403, JSON.stringify(intruding.body));
  assert.strictEqual(intruding.body.message, 'Only the Employee can sit their own Assessment');

  // The second person's identification is not a sitting credential.
  const reading = await read(secondHeaders, first.attemptId);
  assert.strictEqual(reading.status, 401);
  const writing = await answer(secondHeaders, first.attemptId, 1, { chosenOption: 'A' });
  assert.strictEqual(writing.status, 401);

  const stillGoing = await answer(first.sitting, first.attemptId, 1, { chosenOption: 'B' });
  assert.strictEqual(stillGoing.status, 200, JSON.stringify(stillGoing.body));
});

test('a device outside the reach lists nothing and is refused a start with 403', async () => {
  const employee = await newSitter('Reach');
  const attempts = await assignTo(employee);
  const attemptId = attempts[employee.id];

  const inside = await mine(withIdentification(device, await identify(device, employee)));
  assert.strictEqual(inside.body.attempts.length, 1);

  const outsideHeaders = withIdentification(otherDevice, await identify(otherDevice, employee));
  const listed = await mine(outsideHeaders);
  assert.strictEqual(listed.status, 200, JSON.stringify(listed.body));
  assert.deepStrictEqual(listed.body.attempts, []);

  const refused = await start(outsideHeaders, attemptId);
  assert.strictEqual(refused.status, 403, JSON.stringify(refused.body));
  assert.strictEqual((await attemptRow(attemptId)).status, 'assigned');

  const missing = await start(withIdentification(device, await identify(device, employee)), '999999999');
  assert.strictEqual(missing.status, 404, 'existence is answered before scope');
});

test('an expired sitting token is 401 on an answer, while the Attempt still finalises at its own deadline', async () => {
  const sitter = await startedSitter('Expired');

  await pool.query(
    `UPDATE assessment_sittings
        SET issued_at = now() - interval '2 hours', expires_at = now() - interval '1 hour'
      WHERE attempt_id = $1`,
    [sitter.attemptId]
  );
  const refused = await answer(sitter.sitting, sitter.attemptId, 1, { chosenOption: 'C' });
  assert.strictEqual(refused.status, 401, JSON.stringify(refused.body));
  assert.strictEqual((await attemptRow(sitter.attemptId)).status, 'in_progress');

  await pool.query(
    `UPDATE assessment_attempts
        SET started_at = now() - interval '2 hours', deadline_at = now() - interval '1 minute'
      WHERE id = $1`,
    [sitter.attemptId]
  );
  // The Employee identifies again; the sweep runs ahead of the start's own
  // refusal and stays committed.
  const again = await start(withIdentification(device, await identify(device, sitter.employee)), sitter.attemptId);
  assert.strictEqual(again.status, 409, JSON.stringify(again.body));
  const row = await attemptRow(sitter.attemptId);
  assert.strictEqual(row.status, 'submitted');
  assert.strictEqual(row.submitted_late, true);
});

test('End sitting by a Team Leader makes the candidate\'s next request 401; an operator without CHANGE and a Team Leader out of reach are 403', async () => {
  const sitter = await startedSitter('Ended');
  const teamLeader = await insertAccount({ role: 'supervisor' });
  await insertGrant(teamLeader, lineId);
  const operator = await insertAccount({ role: 'operator' });
  await insertGrant(operator, lineId);
  const outsider = await insertAccount({ role: 'supervisor' });
  await insertGrant(outsider, otherLineId);
  const endPath = `/api/people/assessment-attempts/${sitter.attemptId}/end-sitting`;

  assert.strictEqual((await request('POST', endPath, operator.token)).status, 403);
  assert.strictEqual((await request('POST', endPath, outsider.token)).status, 403);
  assert.strictEqual((await request('POST', '/api/people/assessment-attempts/999999999/end-sitting', outsider.token)).status, 404);
  assert.strictEqual((await answer(sitter.sitting, sitter.attemptId, 1, { chosenOption: 'C' })).status, 200);

  const ended = await request('POST', endPath, teamLeader.token);
  assert.strictEqual(ended.status, 200, JSON.stringify(ended.body));
  assert.strictEqual((await answer(sitter.sitting, sitter.attemptId, 1, { chosenOption: 'C' })).status, 401);
  assert.strictEqual((await read(sitter.sitting, sitter.attemptId)).status, 401);
  assert.strictEqual((await attemptRow(sitter.attemptId)).status, 'in_progress', 'the Attempt keeps running');

  // They continue only by identifying again: same paper, a new token.
  const restarted = await start(withIdentification(device, await identify(device, sitter.employee)), sitter.attemptId);
  assert.strictEqual(restarted.status, 200, JSON.stringify(restarted.body));
  const resumed = await answer(withSitting(device, restarted.body.sittingToken), sitter.attemptId, 1, { chosenOption: 'C' });
  assert.strictEqual(resumed.status, 200);

  // An Attempt that was never started has no sitting to end.
  const unstarted = await newSitter('Unstarted');
  const attemptId = (await assignTo(unstarted))[unstarted.id];
  const none = await request('POST', `/api/people/assessment-attempts/${attemptId}/end-sitting`, teamLeader.token);
  assert.strictEqual(none.status, 404);
});

test('start twice returns the same paper and deadline with a different token, and the first token is then 401', async () => {
  const sitter = await startedSitter('Twice');
  const again = await start(withIdentification(device, await identify(device, sitter.employee)), sitter.attemptId);
  assert.strictEqual(again.status, 200, JSON.stringify(again.body));

  assert.deepStrictEqual(
    again.body.paper.map((q) => q.questionText),
    sitter.started.paper.map((q) => q.questionText)
  );
  assert.strictEqual(new Date(again.body.deadlineAt).getTime(), new Date(sitter.started.deadlineAt).getTime());
  assert.notStrictEqual(again.body.sittingToken, sitter.started.sittingToken);

  assert.strictEqual((await answer(sitter.sitting, sitter.attemptId, 1, { chosenOption: 'C' })).status, 401);
  assert.strictEqual(
    (await answer(withSitting(device, again.body.sittingToken), sitter.attemptId, 1, { chosenOption: 'C' })).status,
    200
  );
  const { rows } = await pool.query('SELECT count(*)::int AS n FROM assessment_sittings WHERE attempt_id = $1', [sitter.attemptId]);
  assert.strictEqual(rows[0].n, 1, 'one sitting row per Attempt');
});

test('the 120-second identification is refused on the sitting routes and required on start', async () => {
  const sitter = await startedSitter('Credentials');
  const identification = await identify(device, sitter.employee);
  const identified = withIdentification(device, identification);

  assert.strictEqual((await read(identified, sitter.attemptId)).status, 401);
  assert.strictEqual((await answer(identified, sitter.attemptId, 1, { chosenOption: 'C' })).status, 401);
  assert.strictEqual((await submit(identified, sitter.attemptId)).status, 401);

  assert.strictEqual((await start(sitter.sitting, sitter.attemptId)).status, 401);
  assert.strictEqual((await mine(sitter.sitting)).status, 401);
  assert.strictEqual((await start({ 'x-floor-device': device.credential }, sitter.attemptId)).status, 401);

  // A sitting minted for one Attempt opens no other, and nothing on another device.
  const other = await startedSitter('Neighbour');
  assert.strictEqual((await read(sitter.sitting, other.attemptId)).status, 401);
  assert.strictEqual((await read(withSitting(otherDevice, other.started.sittingToken), other.attemptId)).status, 401);
});

test('the paper read carries exactly the key-less set of fields on every Question', async () => {
  const sitter = await startedSitter('Keyless');
  const expected = ['chosenOption', 'optionA', 'optionB', 'optionC', 'otherText', 'position', 'questionText'];

  const sources = [
    sitter.started.paper,
    (await read(sitter.sitting, sitter.attemptId)).body.paper,
    (await answer(sitter.sitting, sitter.attemptId, 1, { chosenOption: 'A' })).body.paper
  ];
  for (const paper of sources) {
    assert.strictEqual(paper.length, 10);
    for (const question of paper) assert.deepStrictEqual(Object.keys(question).sort(), expected);
  }
  assert.ok(!JSON.stringify(sitter.started).includes('correctOption'));
  assert.ok(!JSON.stringify(sitter.started).includes('explanation'));
});

test('the result is read with the sitting or with a fresh identification once marked, and only by its own Employee', async () => {
  const sitter = await startedSitter('Marked');
  await answer(sitter.sitting, sitter.attemptId, 1, { chosenOption: 'C' });
  assert.strictEqual((await submit(sitter.sitting, sitter.attemptId)).status, 200);

  const marked = await request('POST', `/api/people/assessment-attempts/${sitter.attemptId}/mark`, admin.token, {
    answers: [],
    note: 'Đã chấm'
  });
  assert.strictEqual(marked.status, 200, JSON.stringify(marked.body));

  const bySitting = await result(sitter.sitting, sitter.attemptId);
  assert.strictEqual(bySitting.status, 200, JSON.stringify(bySitting.body));
  assert.strictEqual(bySitting.body.questions.length, 10);

  const fresh = withIdentification(device, await identify(device, sitter.employee));
  assert.strictEqual((await result(fresh, sitter.attemptId)).status, 200);

  const stranger = await newSitter('Stranger');
  const strangerHeaders = withIdentification(device, await identify(device, stranger));
  assert.strictEqual((await result(strangerHeaders, sitter.attemptId)).status, 403);
  assert.strictEqual((await result({ 'x-floor-device': device.credential }, sitter.attemptId)).status, 401);
});
