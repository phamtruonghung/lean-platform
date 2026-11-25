/*
 * The assessment Question bank (issue #588, ADR-0068, slice 2), measured over
 * HTTP against a real database and a real local session — the seam
 * plant.test.js and maintenance-write-permission-roles.test.js use. Later
 * slices of #588 (Assessments, Attempts, marking) add their cases to this file.
 *
 * Every case builds its own Org Unit, so a Question's fingerprint clashes only
 * with what the case itself filed, and `test.after` deletes exactly the rows
 * this file inserted — Questions first, then the Grants, Accounts, Org Units
 * and Site they hang from.
 *
 * Accounts: a supervisor (holds PPL_ASSESSMENT_CHANGE by the slice-1 seed) with
 * a write Grant on every case's Org Unit; an operator with the same Grant, who
 * does not hold the code; a supervisor whose only Grant is on some other Org
 * Unit; and a supervisor with a read-only Grant. The code answers which door,
 * the Grant answers where.
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
function uniqueCode(prefix) {
  counter += 1;
  return `${prefix}${process.pid}${counter}`;
}

async function insertAccount({ role }) {
  const subject = uniqueCode('acct');
  const { rows: [row] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, is_active, approval_status)
     VALUES ($1, 'Assessment Bank Test Account', $2, $3, true, 'approved') RETURNING id`,
    [`${subject}@example.com`, role, subject]
  );
  insertedAccountIds.push(row.id);
  return { id: row.id, role, token: { authorization: `Bearer ${await tokenFor(subject)}` } };
}

async function insertGrant({ accountId, orgUnitId, canWrite }) {
  await pool.query(
    'INSERT INTO app_user_org_units (app_user_id, org_unit_id, can_write) VALUES ($1, $2, $3)',
    [accountId, orgUnitId, canWrite]
  );
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
let admin;
let supervisor;       // CHANGE + a write Grant on every case's Org Unit.
let operatorWriter;   // a write Grant, no CHANGE code.
let elsewhere;        // CHANGE, but its only write Grant is on another Org Unit.
let readOnly;         // CHANGE, a read-only Grant on every case's Org Unit.
let elsewhereUnitId;

// A fresh process, with the Accounts that reach it granted onto it.
async function freshUnit() {
  const { rows: [row] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, NULL, $2, 'Assessment Bank Process', 'area') RETURNING id`,
    [siteId, uniqueCode('OU')]
  );
  insertedOrgUnitIds.push(row.id);
  await insertGrant({ accountId: supervisor.id, orgUnitId: row.id, canWrite: true });
  await insertGrant({ accountId: operatorWriter.id, orgUnitId: row.id, canWrite: true });
  await insertGrant({ accountId: readOnly.id, orgUnitId: row.id, canWrite: false });
  return row.id;
}

function question(overrides = {}) {
  return {
    questionText: 'Khi máy braiding dừng đột ngột, bước đầu tiên là gì?',
    optionA: 'Mở cửa bảo vệ và kiểm tra bobbin',
    optionB: 'Dừng máy và gọi Team Leader',
    optionC: 'Nhấn nút dừng khẩn cấp',
    correctOption: 'C',
    explanation: 'Dừng khẩn cấp trước, rồi mới gọi người.',
    ...overrides
  };
}

function pasteBlock(n, { explanation = true } = {}) {
  return [
    `Câu hỏi: Câu số ${n} về quy trình braiding là gì?`,
    `A. Phương án A của câu ${n}`,
    `B. Phương án B của câu ${n}`,
    `*C. Phương án C của câu ${n}`,
    ...(explanation ? [`Giải thích: Lý do của câu ${n}.`] : [])
  ].join('\n');
}

function pasteOf(count) {
  return Array.from({ length: count }, (_, i) => pasteBlock(i + 1, { explanation: i % 2 === 0 })).join('\n\n');
}

async function countRows(orgUnitId) {
  const { rows: [row] } = await pool.query(
    'SELECT count(*)::int AS n FROM assessment_questions WHERE org_unit_id = $1',
    [orgUnitId]
  );
  return row.n;
}

function assertPermissionRefused(result, permission, what) {
  assert.strictEqual(result.status, 403, `${what} should be refused: ${JSON.stringify(result.payload)}`);
  assert.strictEqual(result.payload.code, 'PERMISSION_REQUIRED', `${what} should name PERMISSION_REQUIRED`);
  assert.strictEqual(result.payload.permission, permission, `${what} should name ${permission}`);
}

function assertOutsideScope(result, what) {
  assert.strictEqual(result.status, 403, `${what} should be refused: ${JSON.stringify(result.payload)}`);
  assert.strictEqual(result.payload.message, "Outside the caller's granted Org Units", what);
  assert.strictEqual(result.payload.code, undefined, `${what} must not be PERMISSION_REQUIRED`);
}

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
     VALUES ($1, 'Assessment Bank Test Site', 'Asia/Ho_Chi_Minh') RETURNING id`,
    [uniqueCode('ST')]
  );
  siteId = site.id;
  insertedSiteIds.push(siteId);

  admin = await insertAccount({ role: 'admin' });
  supervisor = await insertAccount({ role: 'supervisor' });
  operatorWriter = await insertAccount({ role: 'operator' });
  elsewhere = await insertAccount({ role: 'supervisor' });
  readOnly = await insertAccount({ role: 'supervisor' });

  const { rows: [other] } = await pool.query(
    `INSERT INTO org_units (site_id, parent_id, code, name, unit_type)
     VALUES ($1, NULL, $2, 'Assessment Bank Elsewhere', 'area') RETURNING id`,
    [siteId, uniqueCode('OU')]
  );
  elsewhereUnitId = other.id;
  insertedOrgUnitIds.push(elsewhereUnitId);
  await insertGrant({ accountId: elsewhere.id, orgUnitId: elsewhereUnitId, canWrite: true });
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

// ---------------------------------------------------------------------------
// 1. The paste
// ---------------------------------------------------------------------------

test('a paste of 10 Questions for one Org Unit reads back, key and explanation shown to a supervisor with write reach', async () => {
  const unitId = await freshUnit();

  const pasted = await call(supervisor, '/api/people/assessment-questions/bulk', {
    method: 'POST',
    body: { orgUnitId: unitId, text: `${pasteOf(10)}\n\n` }
  });
  assert.strictEqual(pasted.status, 201, JSON.stringify(pasted.payload));
  assert.strictEqual(pasted.payload.created, 10);
  assert.strictEqual(pasted.payload.questions.length, 10);

  const listed = await call(supervisor, `/api/people/assessment-questions?orgUnitId=${unitId}`);
  assert.strictEqual(listed.status, 200);
  assert.strictEqual(listed.payload.questions.length, 10);
  assert.strictEqual(listed.payload.total, 10);
  assert.strictEqual(listed.payload.activeCount, 10);

  const first = listed.payload.questions[0];
  assert.strictEqual(first.questionText, 'Câu số 1 về quy trình braiding là gì?');
  assert.strictEqual(first.optionC, 'Phương án C của câu 1');
  assert.strictEqual(first.correctOption, 'C');
  assert.strictEqual(first.explanation, 'Lý do của câu 1.');
  assert.strictEqual(first.isActive, true);
  assert.strictEqual(listed.payload.questions[1].explanation, null);
});

test('a CRLF paste with leading space and lower-case English labels is read', async () => {
  const unitId = await freshUnit();
  const text = [
    '  question:   What stops the line first?  ',
    ' a.  Call the Team Leader',
    'B. Open the guard',
    ' *c. Press the emergency stop',
    '  EXPLANATION: Stop first, then call.',
    '',
    ''
  ].join('\r\n');

  const pasted = await call(supervisor, '/api/people/assessment-questions/bulk', {
    method: 'POST',
    body: { orgUnitId: unitId, text }
  });
  assert.strictEqual(pasted.status, 201, JSON.stringify(pasted.payload));
  const [stored] = pasted.payload.questions;
  assert.strictEqual(stored.questionText, 'What stops the line first?');
  assert.strictEqual(stored.optionA, 'Call the Team Leader');
  assert.strictEqual(stored.correctOption, 'C');
  assert.strictEqual(stored.explanation, 'Stop first, then call.');
});

// ---------------------------------------------------------------------------
// 2. A malformed paste names the line and writes nothing
// ---------------------------------------------------------------------------

test('a malformed paste is refused naming the line, with nothing written', async () => {
  const unitId = await freshUnit();
  const cases = [
    {
      what: 'two options',
      text: `${pasteBlock(1)}\n\nCâu hỏi: Chỉ có hai phương án?\nA. Một\n*B. Hai`,
      line: 7,
      message: /question 2: expected three options A, B, C, found 2/
    },
    {
      what: 'no key',
      text: 'Câu hỏi: Không đánh dấu đáp án nào?\nA. Một\nB. Hai\nC. Ba',
      line: 4,
      message: /line 4: no option is marked \*/
    },
    {
      what: 'two keys',
      text: 'Câu hỏi: Đánh dấu hai đáp án?\n*A. Một\n*B. Hai\nC. Ba',
      line: 3,
      message: /line 3: two options are marked \*/
    },
    {
      what: 'no stem label',
      text: '\n\nA. Một\nB. Hai\n*C. Ba',
      line: 3,
      message: /line 3: a block must start with 'Câu hỏi:' or 'Question:'/
    },
    {
      what: 'options out of order',
      text: 'Câu hỏi: Sai thứ tự phương án?\nB. Hai\nA. Một\n*C. Ba',
      line: 2,
      message: /line 2: expected option A, found B/
    },
    {
      what: 'a fourth option',
      text: 'Câu hỏi: Có bốn phương án?\nA. Một\nB. Hai\n*C. Ba\nD. Bốn',
      line: 5,
      message: /line 5: a Question has exactly three options/
    },
    {
      what: 'a stem too short',
      text: 'Câu hỏi: Ngắn\nA. Một\nB. Hai\n*C. Ba',
      line: 1,
      message: /line 1: questionText must be at least 5 characters/
    },
    {
      what: 'two identical options',
      text: 'Câu hỏi: Hai phương án giống nhau?\nA. Một\nB. Một\n*C. Ba',
      line: 1,
      message: /line 1: the three options must be different/
    }
  ];

  for (const { what, text, line, message } of cases) {
    const result = await call(supervisor, '/api/people/assessment-questions/bulk', {
      method: 'POST',
      body: { orgUnitId: unitId, text }
    });
    assert.strictEqual(result.status, 400, `${what}: ${JSON.stringify(result.payload)}`);
    assert.strictEqual(result.payload.line, line, `${what}: ${JSON.stringify(result.payload)}`);
    assert.match(result.payload.message, message, what);
  }

  const before = await countRows(unitId);
  const mixed = await call(supervisor, '/api/people/assessment-questions/bulk', {
    method: 'POST',
    body: { orgUnitId: unitId, text: `${pasteOf(3)}\n\nCâu hỏi: Khối cuối thiếu đáp án?\nA. Một\nB. Hai\nC. Ba` }
  });
  assert.strictEqual(mixed.status, 400);
  assert.strictEqual(mixed.payload.line, 21);
  assert.strictEqual(await countRows(unitId), before, 'a malformed paste must write nothing');
  assert.strictEqual(before, 0);

  const empty = await call(supervisor, '/api/people/assessment-questions/bulk', {
    method: 'POST',
    body: { orgUnitId: unitId, text: ' \n\r\n  ' }
  });
  assert.strictEqual(empty.status, 400);
  assert.strictEqual(empty.payload.message, 'nothing to import');
});

// ---------------------------------------------------------------------------
// 3, 4. Duplicates
// ---------------------------------------------------------------------------

test('a repeated question text in the bank is refused with a 409 naming the existing stem', async () => {
  const unitId = await freshUnit();
  const raised = await call(supervisor, '/api/people/assessment-questions', {
    method: 'POST',
    body: { orgUnitId: unitId, ...question() }
  });
  assert.strictEqual(raised.status, 201, JSON.stringify(raised.payload));
  const existingId = raised.payload.question.id;

  const again = await call(supervisor, '/api/people/assessment-questions', {
    method: 'POST',
    body: { orgUnitId: unitId, ...question({ questionText: '  KHI MÁY BRAIDING   dừng đột ngột, bước đầu tiên là gì?  ', correctOption: 'A' }) }
  });
  assert.strictEqual(again.status, 409, JSON.stringify(again.payload));
  assert.match(again.payload.message, /Khi máy braiding dừng đột ngột, bước đầu tiên là gì\?/);
  assert.strictEqual(again.payload.questionId, existingId);

  // A paste meeting the same Question names the pasted line and the existing one.
  const pasted = await call(supervisor, '/api/people/assessment-questions/bulk', {
    method: 'POST',
    body: {
      orgUnitId: unitId,
      text: `${pasteBlock(1)}\n\nCâu hỏi: khi máy braiding dừng đột ngột,  bước đầu tiên là gì?\nA. Một\nB. Hai\n*C. Ba`
    }
  });
  assert.strictEqual(pasted.status, 409, JSON.stringify(pasted.payload));
  assert.strictEqual(pasted.payload.line, 7);
  assert.strictEqual(pasted.payload.questionId, existingId);
  assert.match(pasted.payload.questionText, /^Khi máy braiding/);
  assert.match(pasted.payload.message, /line 7/);
  assert.strictEqual(await countRows(unitId), 1, 'the paste is all-or-nothing: block 1 was rolled back');

  // The same text in a different process is not a clash.
  const otherUnit = await freshUnit();
  const elsewhereRaise = await call(supervisor, '/api/people/assessment-questions', {
    method: 'POST',
    body: { orgUnitId: otherUnit, ...question() }
  });
  assert.strictEqual(elsewhereRaise.status, 201);
});

test('a paste that repeats itself is refused naming both lines, matching the column\'s own fingerprint', async () => {
  const unitId = await freshUnit();
  // Doubled spaces, a tab and different case: the column's fingerprint folds all three.
  const text = [
    'Câu hỏi: Khi  máy dừng,\tbước đầu tiên là gì?',
    'A. Một',
    'B. Hai',
    '*C. Ba',
    '',
    pasteBlock(2),
    '',
    'Question: KHI MÁY DỪNG, bước đầu    tiên là gì?',
    'A. Bốn',
    'B. Năm',
    '*C. Sáu'
  ].join('\n');

  const result = await call(supervisor, '/api/people/assessment-questions/bulk', {
    method: 'POST',
    body: { orgUnitId: unitId, text }
  });
  assert.strictEqual(result.status, 400, JSON.stringify(result.payload));
  assert.strictEqual(result.payload.line, 12);
  assert.strictEqual(result.payload.firstLine, 1);
  assert.match(result.payload.message, /line 12/);
  assert.match(result.payload.message, /line 1\b/);
  assert.strictEqual(await countRows(unitId), 0);
});

test('the parser and the column fingerprint a stem the same way', async () => {
  const unitId = await freshUnit();
  const pasted = await call(supervisor, '/api/people/assessment-questions/bulk', {
    method: 'POST',
    body: { orgUnitId: unitId, text: 'Câu hỏi: Đèn   BÁO   đỏ nghĩa là gì?\nA. Một\nB. Hai\n*C. Ba' }
  });
  assert.strictEqual(pasted.status, 201, JSON.stringify(pasted.payload));

  // What the parser considers the same, the stored column agrees is the same:
  // the clash is raised by the unique key over the stored fingerprint.
  const { rows: [stored] } = await pool.query(
    `SELECT question_text_fingerprint AS fingerprint,
            md5(lower(regexp_replace(btrim(question_text), '\\s+', ' ', 'g'))) AS expected
       FROM assessment_questions WHERE org_unit_id = $1`,
    [unitId]
  );
  assert.strictEqual(stored.fingerprint, stored.expected);

  const clash = await call(supervisor, '/api/people/assessment-questions/bulk', {
    method: 'POST',
    body: { orgUnitId: unitId, text: 'Question: đèn báo ĐỎ   nghĩa là gì?\nA. Bốn\nB. Năm\n*C. Sáu' }
  });
  assert.strictEqual(clash.status, 409, JSON.stringify(clash.payload));
  assert.strictEqual(clash.payload.line, 1);
});

// ---------------------------------------------------------------------------
// 5. Retire
// ---------------------------------------------------------------------------

test('retiring a Question answers 204, hides it by default, keeps the row and is idempotent', async () => {
  const unitId = await freshUnit();
  const raised = await call(supervisor, '/api/people/assessment-questions', {
    method: 'POST',
    body: { orgUnitId: unitId, ...question() }
  });
  const { id } = raised.payload.question;

  const retired = await call(supervisor, `/api/people/assessment-questions/${id}`, { method: 'DELETE' });
  assert.strictEqual(retired.status, 204);
  const again = await call(supervisor, `/api/people/assessment-questions/${id}`, { method: 'DELETE' });
  assert.strictEqual(again.status, 204);

  const hidden = await call(supervisor, `/api/people/assessment-questions?orgUnitId=${unitId}`);
  assert.strictEqual(hidden.payload.questions.length, 0);
  assert.strictEqual(hidden.payload.total, 0);
  assert.strictEqual(hidden.payload.activeCount, 0);

  const shown = await call(supervisor, `/api/people/assessment-questions?orgUnitId=${unitId}&includeInactive=true`);
  assert.strictEqual(shown.payload.questions.length, 1);
  assert.strictEqual(shown.payload.questions[0].isActive, false);
  assert.strictEqual(shown.payload.total, 1);
  assert.strictEqual(shown.payload.activeCount, 0);

  // includeInactive needs DISPLAY alone.
  const plain = await call(operatorWriter, `/api/people/assessment-questions?orgUnitId=${unitId}&includeInactive=true`);
  assert.strictEqual(plain.status, 200);
  assert.strictEqual(plain.payload.questions.length, 1);

  assert.strictEqual(await countRows(unitId), 1, 'the row is still in the table');

  const missing = await call(supervisor, '/api/people/assessment-questions/999999999', { method: 'DELETE' });
  assert.strictEqual(missing.status, 404);
});

// ---------------------------------------------------------------------------
// 6, 7. The code and the Grant
// ---------------------------------------------------------------------------

test('an Account without PPL_ASSESSMENT_CHANGE is refused every write with PERMISSION_REQUIRED naming it', async () => {
  const unitId = await freshUnit();
  const raised = await call(supervisor, '/api/people/assessment-questions', {
    method: 'POST',
    body: { orgUnitId: unitId, ...question() }
  });
  const { id } = raised.payload.question;

  const writes = [
    ['create', '/api/people/assessment-questions', 'POST', { orgUnitId: unitId, ...question({ questionText: 'Một câu hỏi khác hẳn?' }) }],
    ['bulk', '/api/people/assessment-questions/bulk', 'POST', { orgUnitId: unitId, text: pasteOf(1) }],
    ['correct', `/api/people/assessment-questions/${id}`, 'PATCH', question()],
    ['retire', `/api/people/assessment-questions/${id}`, 'DELETE', undefined]
  ];
  for (const [what, path, method, body] of writes) {
    const result = await call(operatorWriter, path, { method, body });
    assertPermissionRefused(result, 'PPL_ASSESSMENT_CHANGE', what);
  }

  // The seed: DISPLAY for an operator, CHANGE only from supervisor up.
  const operatorMe = await call(operatorWriter, '/api/people/me');
  assert.ok(operatorMe.payload.permissions.includes('PPL_ASSESSMENT_DISPLAY'));
  assert.ok(!operatorMe.payload.permissions.includes('PPL_ASSESSMENT_CHANGE'));
  assert.strictEqual(await countRows(unitId), 1);
});

test('a supervisor whose write Grant does not reach the Org Unit is refused on every write with the scope sentence, and can still read', async () => {
  const unitId = await freshUnit();
  const raised = await call(supervisor, '/api/people/assessment-questions', {
    method: 'POST',
    body: { orgUnitId: unitId, ...question() }
  });
  const { id } = raised.payload.question;

  const writes = [
    ['create', '/api/people/assessment-questions', 'POST', { orgUnitId: unitId, ...question({ questionText: 'Một câu hỏi khác hẳn?' }) }],
    ['bulk', '/api/people/assessment-questions/bulk', 'POST', { orgUnitId: unitId, text: pasteOf(1) }],
    ['correct', `/api/people/assessment-questions/${id}`, 'PATCH', question()],
    ['retire', `/api/people/assessment-questions/${id}`, 'DELETE', undefined]
  ];
  for (const [what, path, method, body] of writes) {
    assertOutsideScope(await call(elsewhere, path, { method, body }), what);
    assertOutsideScope(await call(readOnly, path, { method, body }), `${what} (read-only Grant)`);
  }

  const read = await call(elsewhere, `/api/people/assessment-questions?orgUnitId=${unitId}`);
  assert.strictEqual(read.status, 200);
  assert.strictEqual(read.payload.questions.length, 1);
  assert.strictEqual(await countRows(unitId), 1);
  const [still] = (await call(supervisor, `/api/people/assessment-questions?orgUnitId=${unitId}`)).payload.questions;
  assert.strictEqual(still.isActive, true);
});

// ---------------------------------------------------------------------------
// 8. The key is a field-level read
// ---------------------------------------------------------------------------

test('a read without write reach hides the key and explanation as null and still shows the count', async () => {
  const unitId = await freshUnit();
  await call(supervisor, '/api/people/assessment-questions/bulk', {
    method: 'POST',
    body: { orgUnitId: unitId, text: pasteOf(4) }
  });

  for (const [who, account] of [['elsewhere', elsewhere], ['read-only', readOnly], ['operator', operatorWriter]]) {
    const result = await call(account, `/api/people/assessment-questions?orgUnitId=${unitId}`);
    assert.strictEqual(result.status, 200, who);
    assert.strictEqual(result.payload.questions.length, 4, who);
    assert.strictEqual(result.payload.total, 4, who);
    assert.strictEqual(result.payload.activeCount, 4, who);
    for (const row of result.payload.questions) {
      assert.ok('correctOption' in row && row.correctOption === null, `${who}: correctOption is null, never absent`);
      assert.ok('explanation' in row && row.explanation === null, `${who}: explanation is null, never absent`);
      assert.ok(row.optionA && row.optionB && row.optionC, `${who}: the Options are shown`);
    }
  }

  const administrator = await call(admin, `/api/people/assessment-questions?orgUnitId=${unitId}`);
  assert.strictEqual(administrator.payload.questions[0].correctOption, 'C');
});

// ---------------------------------------------------------------------------
// 9. Correcting
// ---------------------------------------------------------------------------

test('a PATCH on a retired Question is 409, and a PATCH colliding on the fingerprint is 409', async () => {
  const unitId = await freshUnit();
  const one = (await call(supervisor, '/api/people/assessment-questions', {
    method: 'POST', body: { orgUnitId: unitId, ...question() }
  })).payload.question;
  const two = (await call(supervisor, '/api/people/assessment-questions', {
    method: 'POST', body: { orgUnitId: unitId, ...question({ questionText: 'Câu hỏi thứ hai về an toàn?', correctOption: 'B' }) }
  })).payload.question;

  const corrected = await call(supervisor, `/api/people/assessment-questions/${two.id}`, {
    method: 'PATCH',
    body: question({ questionText: 'Câu hỏi thứ hai, đã sửa lại?', correctOption: 'A', explanation: '' })
  });
  assert.strictEqual(corrected.status, 200, JSON.stringify(corrected.payload));
  assert.strictEqual(corrected.payload.question.questionText, 'Câu hỏi thứ hai, đã sửa lại?');
  assert.strictEqual(corrected.payload.question.correctOption, 'A');
  assert.strictEqual(corrected.payload.question.explanation, null);

  const collide = await call(supervisor, `/api/people/assessment-questions/${two.id}`, {
    method: 'PATCH', body: question({ questionText: 'khi máy braiding DỪNG đột ngột, bước đầu tiên là gì?' })
  });
  assert.strictEqual(collide.status, 409, JSON.stringify(collide.payload));
  assert.strictEqual(collide.payload.questionId, one.id);

  await call(supervisor, `/api/people/assessment-questions/${one.id}`, { method: 'DELETE' });
  const retired = await call(supervisor, `/api/people/assessment-questions/${one.id}`, {
    method: 'PATCH', body: question()
  });
  assert.strictEqual(retired.status, 409, JSON.stringify(retired.payload));
  assert.match(retired.payload.message, /retired/);
  assert.doesNotMatch(retired.payload.message, /reinstate/i);

  // A retired Question still holds its fingerprint.
  const reraise = await call(supervisor, '/api/people/assessment-questions', {
    method: 'POST', body: { orgUnitId: unitId, ...question() }
  });
  assert.strictEqual(reraise.status, 409);

  const missing = await call(supervisor, '/api/people/assessment-questions/999999999', {
    method: 'PATCH', body: question()
  });
  assert.strictEqual(missing.status, 404);
});

// ---------------------------------------------------------------------------
// 10. Search and paging
// ---------------------------------------------------------------------------

test('q filters the stem and limit/offset page the list, with the total unchanged by the page', async () => {
  const unitId = await freshUnit();
  for (const text of ['Bobbin nào cần thay trước?', 'Bobbin nào quá mức cho phép?', 'Đèn báo màu gì là dừng?']) {
    const raised = await call(supervisor, '/api/people/assessment-questions', {
      method: 'POST', body: { orgUnitId: unitId, ...question({ questionText: text }) }
    });
    assert.strictEqual(raised.status, 201);
  }

  const pageOne = await call(supervisor, `/api/people/assessment-questions?orgUnitId=${unitId}&limit=2&offset=0`);
  assert.strictEqual(pageOne.payload.questions.length, 2);
  assert.strictEqual(pageOne.payload.total, 3);
  const pageTwo = await call(supervisor, `/api/people/assessment-questions?orgUnitId=${unitId}&limit=2&offset=2`);
  assert.strictEqual(pageTwo.payload.questions.length, 1);
  assert.strictEqual(pageTwo.payload.total, 3);
  assert.notStrictEqual(pageOne.payload.questions[0].id, pageTwo.payload.questions[0].id);

  const filtered = await call(supervisor, `/api/people/assessment-questions?orgUnitId=${unitId}&q=${encodeURIComponent('bobbin')}`);
  assert.strictEqual(filtered.payload.questions.length, 2);
  assert.strictEqual(filtered.payload.total, 2);
  assert.strictEqual(filtered.payload.activeCount, 3);

  const wildcard = await call(supervisor, `/api/people/assessment-questions?orgUnitId=${unitId}&q=${encodeURIComponent('%')}`);
  assert.strictEqual(wildcard.payload.total, 0, 'a % in q is a literal');

  // Exact match on the process: another Org Unit's bank is empty.
  const other = await call(supervisor, `/api/people/assessment-questions?orgUnitId=${elsewhereUnitId}`);
  assert.strictEqual(other.payload.total, 0);
});

// ---------------------------------------------------------------------------
// 11. Validation and existence
// ---------------------------------------------------------------------------

test('a body is validated with a 400 naming the field, and an unknown Org Unit is a 404 before scope', async () => {
  const unitId = await freshUnit();
  const bad = [
    ['correctOption', question({ correctOption: 'D' })],
    ['correctOption', question({ correctOption: 'a' })],
    ['optionB', question({ optionB: '   ' })],
    ['the three options', question({ optionA: 'Giống', optionB: 'Giống' })],
    ['questionText', question({ questionText: 'Ngắn' })],
    ['questionText', question({ questionText: 'x'.repeat(2001) })],
    ['explanation', question({ explanation: 'x'.repeat(2001) })]
  ];
  for (const [field, body] of bad) {
    const result = await call(supervisor, '/api/people/assessment-questions', {
      method: 'POST', body: { orgUnitId: unitId, ...body }
    });
    assert.strictEqual(result.status, 400, `${field}: ${JSON.stringify(result.payload)}`);
    assert.ok(result.payload.message.includes(field), `${field}: ${result.payload.message}`);
  }
  assert.strictEqual(await countRows(unitId), 0);

  const noUnit = await call(supervisor, '/api/people/assessment-questions', { method: 'POST', body: question() });
  assert.strictEqual(noUnit.status, 400);
  assert.match(noUnit.payload.message, /orgUnitId/);

  // 404 before scope, for the Account with no Grant anywhere near it and for an administrator.
  for (const account of [elsewhere, admin]) {
    const unknownCreate = await call(account, '/api/people/assessment-questions', {
      method: 'POST', body: { orgUnitId: '999999999', ...question() }
    });
    assert.strictEqual(unknownCreate.status, 404, JSON.stringify(unknownCreate.payload));
    const unknownBulk = await call(account, '/api/people/assessment-questions/bulk', {
      method: 'POST', body: { orgUnitId: '999999999', text: pasteOf(1) }
    });
    assert.strictEqual(unknownBulk.status, 404);
  }
  const unknownRead = await call(supervisor, '/api/people/assessment-questions?orgUnitId=999999999');
  assert.strictEqual(unknownRead.status, 404);
  const noRead = await call(supervisor, '/api/people/assessment-questions');
  assert.strictEqual(noRead.status, 400);
});

// ---------------------------------------------------------------------------
// 7. Timing (slice 7): the lazy sweep, at the boundaries
//
// Time is moved only by UPDATE-ing `started_at`, `deadline_at` and `due_on`;
// "today at the Site" is computed in SQL with `plant_date`, never from the
// runner's own timezone. Each read below is the ONLY thing that could have
// applied the transition, because every case checks the row before it reads.
// ---------------------------------------------------------------------------

const ATTEMPTS = '/api/people/assessment-attempts';

// A process with a bank of ten, a supervisor's write Grant on it, and one
// candidate (an operator linked to an Employee) holding an assigned Attempt.
async function timingStage({ dueOnOffsetDays = null } = {}) {
  const processUnitId = await freshUnit();
  for (let i = 1; i <= 10; i += 1) {
    await pool.query(
      `INSERT INTO assessment_questions
         (org_unit_id, question_text, option_a, option_b, option_c, correct_option, explanation)
       VALUES ($1, $2, 'A', 'B', 'C', 'C', 'because')`,
      [processUnitId, `Timing ${uniqueCode('Q')} ${i}`]
    );
  }
  const { rows: [employee] } = await pool.query(
    `INSERT INTO employees (employee_no, first_name, last_name, default_org_unit_id)
     VALUES ($1, 'Timing', 'Sitter', $2) RETURNING id`,
    [uniqueCode('E'), processUnitId]
  );
  insertedEmployeeIds.push(employee.id);
  const subject = uniqueCode('acct');
  const { rows: [account] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, external_subject, employee_id, is_active, approval_status)
     VALUES ($1, 'Assessment Timing Candidate', 'operator', $2, $3, true, 'approved') RETURNING id`,
    [`${subject}@example.com`, subject, employee.id]
  );
  insertedAccountIds.push(account.id);
  const candidate = { id: account.id, token: { authorization: `Bearer ${await tokenFor(subject)}` } };

  const created = await call(supervisor, '/api/people/assessments', {
    method: 'POST',
    body: { orgUnitId: String(processUnitId), title: 'Timing paper', questionCount: 10 }
  });
  assert.strictEqual(created.status, 201, JSON.stringify(created.payload));
  const assessmentId = created.payload.assessment.id;
  const assigned = await call(supervisor, `/api/people/assessments/${assessmentId}/assign`, {
    method: 'POST',
    body: { employeeIds: [String(employee.id)] }
  });
  assert.strictEqual(assigned.status, 201, JSON.stringify(assigned.payload));
  const { rows: [attempt] } = await pool.query(
    'SELECT id FROM assessment_attempts WHERE assessment_id = $1', [assessmentId]
  );
  if (dueOnOffsetDays !== null) await setDueOffset(assessmentId, dueOnOffsetDays);
  return { processUnitId, assessmentId, attemptId: attempt.id, candidate };
}

// `due_on` as a number of Site-local days from today at the Site, in SQL.
async function setDueOffset(assessmentId, days) {
  await pool.query(
    'UPDATE assessments SET due_on = plant_date(org_unit_id, now()) + $2::int WHERE id = $1',
    [assessmentId, days]
  );
}

async function attemptRow(attemptId) {
  const { rows: [row] } = await pool.query(
    `SELECT status, submitted_late, score, submitted_at, deadline_at,
            submitted_at = deadline_at AS closed_at_deadline
       FROM assessment_attempts WHERE id = $1`,
    [attemptId]
  );
  return row;
}

async function startPaper(staged) {
  const started = await call(staged.candidate, `${ATTEMPTS}/${staged.attemptId}/start`, { method: 'POST' });
  assert.strictEqual(started.status, 200, JSON.stringify(started.payload));
  return started;
}

async function answer(staged, position, body, headers = {}) {
  const response = await fetch(`${base}${ATTEMPTS}/${staged.attemptId}/answers/${position}`, {
    method: 'PATCH',
    headers: { ...staged.candidate.token, 'content-type': 'application/json', ...headers },
    body: JSON.stringify(body)
  });
  return { status: response.status, payload: await response.json().catch(() => null) };
}

// The paper ran out `minutes` ago: stored times only, never a wait.
async function runOut(attemptId) {
  await pool.query(
    `UPDATE assessment_attempts
        SET started_at = now() - interval '21 minutes',
            deadline_at = now() - interval '1 minute'
      WHERE id = $1`,
    [attemptId]
  );
}

test('a paper started at 23:50 on the due date runs to its own deadline', async () => {
  const staged = await timingStage({ dueOnOffsetDays: 0 });
  await startPaper(staged);
  await answer(staged, 1, { chosenOption: 'C' });

  // It was started on the due date at 23:50 Site time; the Site's date has
  // since rolled, so `due_on` is now yesterday, and the deadline is ten minutes
  // away, past midnight.
  await pool.query(
    `UPDATE assessment_attempts
        SET started_at = now() - interval '10 minutes',
            deadline_at = now() + interval '10 minutes'
      WHERE id = $1`,
    [staged.attemptId]
  );
  await setDueOffset(staged.assessmentId, -1);

  const saved = await answer(staged, 2, { chosenOption: 'C' });
  assert.strictEqual(saved.status, 200, JSON.stringify(saved.payload));
  const read = await call(staged.candidate, `${ATTEMPTS}/${staged.attemptId}`);
  assert.strictEqual(read.status, 200);
  assert.strictEqual(read.payload.attempt.status, 'in_progress', 'the due date bounds starting, not running');

  const submitted = await call(staged.candidate, `${ATTEMPTS}/${staged.attemptId}/submit`, { method: 'POST' });
  assert.strictEqual(submitted.status, 200, JSON.stringify(submitted.payload));
  const row = await attemptRow(staged.attemptId);
  assert.strictEqual(row.status, 'submitted');
  assert.strictEqual(row.submitted_late, false);
  assert.strictEqual(row.score, 2);
});

test("a start one tick after the Site's date rolls is 409 and the Attempt is expired", async () => {
  const staged = await timingStage({ dueOnOffsetDays: -1 });

  const refused = await call(staged.candidate, `${ATTEMPTS}/${staged.attemptId}/start`, { method: 'POST' });
  assert.strictEqual(refused.status, 409, JSON.stringify(refused.payload));
  // A fresh read, not the response: the 409 must not have rolled the expiry back.
  assert.strictEqual((await attemptRow(staged.attemptId)).status, 'expired');
  const { rows: [paper] } = await pool.query(
    'SELECT count(*)::int AS n FROM assessment_attempt_questions WHERE attempt_id = $1', [staged.attemptId]
  );
  assert.strictEqual(paper.n, 0, 'no paper is drawn for an expired Attempt');

  const again = await call(staged.candidate, `${ATTEMPTS}/${staged.attemptId}/start`, { method: 'POST' });
  assert.strictEqual(again.status, 409);
});

test('an unstarted Attempt reads expired on the register, the detail and mine once the Site date rolls', async () => {
  // Each read is the only thing that could expire its own Attempt.
  const viaRegister = await timingStage({ dueOnOffsetDays: -1 });
  const list = await call(supervisor, `/api/people/assessments?orgUnitId=${viaRegister.processUnitId}`);
  assert.strictEqual(list.status, 200, JSON.stringify(list.payload));
  const entry = list.payload.assessments.find((row) => String(row.id) === String(viaRegister.assessmentId));
  assert.strictEqual(entry.assignedCount, 0, 'an expired Attempt is not "assigned" any more');
  assert.strictEqual((await attemptRow(viaRegister.attemptId)).status, 'expired');

  const viaDetail = await timingStage({ dueOnOffsetDays: -1 });
  const detail = await call(supervisor, `/api/people/assessments/${viaDetail.assessmentId}`);
  assert.strictEqual(detail.status, 200, JSON.stringify(detail.payload));
  assert.deepStrictEqual(detail.payload.assessment.attempts.map((a) => a.status), ['expired']);

  const viaMine = await timingStage({ dueOnOffsetDays: -1 });
  const mine = await call(viaMine.candidate, `${ATTEMPTS}/mine`);
  assert.strictEqual(mine.status, 200, JSON.stringify(mine.payload));
  assert.deepStrictEqual(mine.payload.attempts.map((a) => a.status), ['expired']);

  // A due date that has not passed, and no due date at all, never expire.
  const today = await timingStage({ dueOnOffsetDays: 0 });
  const open = await timingStage();
  for (const staged of [today, open]) {
    const read = await call(supervisor, `/api/people/assessments/${staged.assessmentId}`);
    assert.deepStrictEqual(read.payload.assessment.attempts.map((a) => a.status), ['assigned']);
  }
});

test('an Attempt abandoned mid-paper finalises with submitted_late and the register and marking paper show it', async () => {
  const staged = await timingStage();
  await startPaper(staged);
  for (let position = 1; position <= 7; position += 1) {
    await answer(staged, position, { chosenOption: position <= 6 ? 'C' : 'A' });
  }
  await runOut(staged.attemptId);
  assert.strictEqual((await attemptRow(staged.attemptId)).status, 'in_progress', 'nobody has looked yet');

  // The Marker's queue is the first look: an abandoned paper must reach it.
  const queue = await call(supervisor, '/api/people/assessment-marking');
  assert.strictEqual(queue.status, 200, JSON.stringify(queue.payload));
  const queued = queue.payload.attempts.find((row) => String(row.id) === String(staged.attemptId));
  assert.ok(queued, 'the abandoned paper is in the queue');
  assert.strictEqual(queued.submittedLate, true);

  const row = await attemptRow(staged.attemptId);
  assert.strictEqual(row.status, 'submitted');
  assert.strictEqual(row.submitted_late, true);
  assert.strictEqual(row.closed_at_deadline, true, 'submitted_at is the deadline, not the moment somebody looked');
  assert.strictEqual(row.score, 6, 'six right, one wrong, three blank');

  const detail = await call(supervisor, `/api/people/assessments/${staged.assessmentId}`);
  const [shown] = detail.payload.assessment.attempts;
  assert.strictEqual(shown.status, 'submitted');
  assert.strictEqual(shown.submittedLate, true);

  const paper = await call(supervisor, `${ATTEMPTS}/${staged.attemptId}/marking`);
  assert.strictEqual(paper.status, 200, JSON.stringify(paper.payload));
  assert.strictEqual(paper.payload.attempt.submittedLate, true);
  assert.strictEqual(paper.payload.attempt.status, 'submitted');
});

test('two reads racing past the deadline finalise once', async () => {
  const staged = await timingStage();
  await startPaper(staged);
  for (let position = 1; position <= 5; position += 1) {
    await answer(staged, position, { chosenOption: position <= 4 ? 'C' : 'B' });
  }
  await runOut(staged.attemptId);

  const reads = await Promise.all([
    call(staged.candidate, `${ATTEMPTS}/${staged.attemptId}`),
    call(staged.candidate, `${ATTEMPTS}/${staged.attemptId}`),
    call(supervisor, `/api/people/assessments/${staged.assessmentId}`),
    call(staged.candidate, `${ATTEMPTS}/mine`)
  ]);
  for (const read of reads) assert.strictEqual(read.status, 200, JSON.stringify(read.payload));

  const row = await attemptRow(staged.attemptId);
  assert.strictEqual(row.status, 'submitted');
  assert.strictEqual(row.submitted_late, true);
  assert.strictEqual(row.closed_at_deadline, true);
  assert.strictEqual(row.score, 4, 'the score is the sum of the points once, never doubled');

  const { rows: [audit] } = await pool.query(
    `SELECT count(*)::int AS n FROM audit_log
      WHERE table_name = 'assessment_attempts' AND record_id = $1
        AND new_values->>'status' = 'submitted'`,
    [staged.attemptId]
  );
  assert.strictEqual(audit.n, 1, 'one finalise, one audit row');
});

test("a client claiming a late time still gets the server's answer", async () => {
  // Time the client claims is never read: a body field and headers carrying
  // timestamps change nothing in either direction.
  const inTime = await timingStage();
  await startPaper(inTime);
  const claimedLate = await answer(
    inTime, 1, { chosenOption: 'C', answeredAt: '2099-01-01T00:00:00Z', submittedAt: '2099-01-01T00:00:00Z', clientNow: '2099-01-01T00:00:00Z' },
    { 'x-client-time': '2099-01-01T00:00:00Z', date: 'Fri, 01 Jan 2100 00:00:00 GMT' }
  );
  assert.strictEqual(claimedLate.status, 200, 'the server sees it in time, whatever the client says');
  assert.strictEqual((await attemptRow(inTime.attemptId)).status, 'in_progress');
  const { rows: [kept] } = await pool.query(
    'SELECT chosen_option, answered_at < now() + interval \'1 minute\' AS server_time FROM assessment_attempt_questions WHERE attempt_id = $1 AND position = 1',
    [inTime.attemptId]
  );
  assert.strictEqual(kept.chosen_option, 'C');
  assert.strictEqual(kept.server_time, true, 'answered_at is the database clock, not the claimed one');

  const tooLate = await timingStage();
  await startPaper(tooLate);
  await runOut(tooLate.attemptId);
  const claimedInTime = await answer(
    tooLate, 1, { chosenOption: 'C', answeredAt: '2000-01-01T00:00:00Z', clientNow: '2000-01-01T00:00:00Z' },
    { 'x-client-time': '2000-01-01T00:00:00Z', date: 'Sat, 01 Jan 2000 00:00:00 GMT' }
  );
  assert.strictEqual(claimedInTime.status, 409, JSON.stringify(claimedInTime.payload));
  const row = await attemptRow(tooLate.attemptId);
  assert.strictEqual(row.status, 'submitted');
  assert.strictEqual(row.submitted_late, true);
  const { rows: [unsaved] } = await pool.query(
    'SELECT chosen_option FROM assessment_attempt_questions WHERE attempt_id = $1 AND position = 1',
    [tooLate.attemptId]
  );
  assert.strictEqual(unsaved.chosen_option, null, 'the refused Answer was never written');
});

// ---------------------------------------------------------------------------
// Doors per role (issue #612)
//
// The slice-1 seed (1804400000000) already puts the four assessment codes on
// the Roles, so no grant migration exists to measure; these cases measure the
// doors themselves, through the Role an Account's `role` column names, over
// real HTTP. The Grant answers where, the code answers which door.
// ---------------------------------------------------------------------------

// A write Grant, a Question added, an Assessment created and assigned, one
// Attempt sat and submitted by a candidate, and that Attempt marked: the three
// doors CHANGE, CHANGE and MARK, walked by one Account.
async function walkTheThreeDoors(account) {
  const unitId = await freshUnit();
  await insertGrant({ accountId: account.id, orgUnitId: unitId, canWrite: true });

  const added = await call(account, '/api/people/assessment-questions', {
    method: 'POST',
    body: { orgUnitId: unitId, ...question({ questionText: `Câu hỏi của ${account.role} ${uniqueCode('Q')}?` }) }
  });
  assert.strictEqual(added.status, 201, JSON.stringify(added.payload));

  for (let i = 1; i <= 10; i += 1) {
    await pool.query(
      `INSERT INTO assessment_questions
         (org_unit_id, question_text, option_a, option_b, option_c, correct_option, explanation)
       VALUES ($1, $2, 'A', 'B', 'C', 'C', 'because')`,
      [unitId, `Doors ${uniqueCode('Q')} ${i}`]
    );
  }
  const { rows: [employee] } = await pool.query(
    `INSERT INTO employees (employee_no, first_name, last_name, default_org_unit_id)
     VALUES ($1, 'Doors', 'Sitter', $2) RETURNING id`,
    [uniqueCode('E'), unitId]
  );
  insertedEmployeeIds.push(employee.id);
  const sitter = await insertAccount({ role: 'operator' });
  await pool.query('UPDATE app_users SET employee_id = $1 WHERE id = $2', [employee.id, sitter.id]);

  const created = await call(account, '/api/people/assessments', {
    method: 'POST',
    body: { orgUnitId: String(unitId), title: `Doors paper ${account.role}`, questionCount: 10 }
  });
  assert.strictEqual(created.status, 201, JSON.stringify(created.payload));
  const assigned = await call(account, `/api/people/assessments/${created.payload.assessment.id}/assign`, {
    method: 'POST',
    body: { employeeIds: [String(employee.id)] }
  });
  assert.strictEqual(assigned.status, 201, JSON.stringify(assigned.payload));

  const { rows: [attempt] } = await pool.query(
    'SELECT id FROM assessment_attempts WHERE assessment_id = $1', [created.payload.assessment.id]
  );
  const started = await call(sitter, `/api/people/assessment-attempts/${attempt.id}/start`, { method: 'POST' });
  assert.strictEqual(started.status, 200, JSON.stringify(started.payload));
  const submitted = await call(sitter, `/api/people/assessment-attempts/${attempt.id}/submit`, { method: 'POST' });
  assert.strictEqual(submitted.status, 200, JSON.stringify(submitted.payload));

  const marked = await call(account, `/api/people/assessment-attempts/${attempt.id}/mark`, {
    method: 'POST',
    body: { answers: [], note: 'Đã xem bài' }
  });
  assert.strictEqual(marked.status, 200, JSON.stringify(marked.payload));
  assert.strictEqual(marked.payload.attempt.status, 'marked');
}

test('an operator reads the Question bank and is refused a new Question with PPL_ASSESSMENT_CHANGE, even holding a write Grant', async () => {
  const unitId = await freshUnit();
  const read = await call(operatorWriter, `/api/people/assessment-questions?orgUnitId=${unitId}`);
  assert.strictEqual(read.status, 200, JSON.stringify(read.payload));

  const refused = await call(operatorWriter, '/api/people/assessment-questions', {
    method: 'POST',
    body: { orgUnitId: unitId, ...question() }
  });
  assertPermissionRefused(refused, 'PPL_ASSESSMENT_CHANGE', 'an operator adding a Question');
  assert.strictEqual(await countRows(unitId), 0);
});

test('a supervisor with a write Grant adds a Question, creates an Assessment and marks a submitted Attempt', async () => {
  const account = await insertAccount({ role: 'supervisor' });
  await walkTheThreeDoors(account);
});

test('an engineer with a write Grant adds a Question, creates an Assessment and marks a submitted Attempt', async () => {
  const account = await insertAccount({ role: 'engineer' });
  await walkTheThreeDoors(account);
});

test('the default group alone, ROLE_STANDARD, opens the Question bank for an operator whose own Role holds no assessment code', async () => {
  const removed = await pool.query(
    `DELETE FROM app_role_permissions rp
      USING app_roles r
      WHERE r.id = rp.app_role_id AND r.code = 'ROLE_OPERATOR'
        AND rp.permission_code IN ('PPL_ASSESSMENT_DISPLAY', 'PPL_ASSESSMENT_SIT')
      RETURNING rp.permission_code`
  );
  try {
    assert.strictEqual(removed.rowCount, 2, 'ROLE_OPERATOR held the two seeded assessment codes');

    const { rows: operatorCodes } = await pool.query(
      `SELECT rp.permission_code FROM app_role_permissions rp
         JOIN app_roles r ON r.id = rp.app_role_id
        WHERE r.code = 'ROLE_OPERATOR' AND rp.permission_code LIKE 'PPL\\_ASSESSMENT\\_%'`
    );
    assert.deepStrictEqual(operatorCodes, [], 'ROLE_OPERATOR holds no assessment code now');
    const { rows: [standard] } = await pool.query(
      `SELECT r.is_default,
              EXISTS (SELECT 1 FROM app_role_permissions rp
                       WHERE rp.app_role_id = r.id AND rp.permission_code = 'PPL_ASSESSMENT_DISPLAY') AS holds_display
         FROM app_roles r WHERE r.code = 'ROLE_STANDARD'`
    );
    assert.strictEqual(standard.is_default, true, 'ROLE_STANDARD is the default group');
    assert.strictEqual(standard.holds_display, true, 'ROLE_STANDARD holds PPL_ASSESSMENT_DISPLAY');

    const unitId = await freshUnit();
    const read = await call(operatorWriter, `/api/people/assessment-questions?orgUnitId=${unitId}`);
    assert.strictEqual(read.status, 200, JSON.stringify(read.payload));
    const me = await call(operatorWriter, '/api/people/me');
    assert.ok(me.payload.permissions.includes('PPL_ASSESSMENT_DISPLAY'));
  } finally {
    await pool.query(
      `INSERT INTO app_role_permissions (app_role_id, permission_code)
       SELECT r.id, c.code FROM app_roles r
         CROSS JOIN (VALUES ('PPL_ASSESSMENT_DISPLAY'), ('PPL_ASSESSMENT_SIT')) AS c (code)
        WHERE r.code = 'ROLE_OPERATOR'
       ON CONFLICT DO NOTHING`
    );
  }
});
