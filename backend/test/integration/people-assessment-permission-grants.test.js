/*
 * The assessment permission grants (issue #612), measured against a migrated
 * database. Migration 1804400000000 already seeds the matrix with
 * `INSERT ... ON CONFLICT DO NOTHING`, so no further grant migration exists;
 * this file proves what that seed leaves behind, that migrating again changes
 * nothing, and that a code an administrator removed is not put back.
 *
 * A named exception to the HTTP seam, like schema.test.js: the subject is the
 * migrated database itself. The doors those grants open are measured over HTTP
 * in people-assessments.test.js.
 */

const test = require('node:test');
const assert = require('node:assert');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const BACKEND_DIR = path.join(__dirname, '..', '..');

const EXPECTED_GRANTS = [
  ['ROLE_ENGINEER', 'PPL_ASSESSMENT_CHANGE'],
  ['ROLE_ENGINEER', 'PPL_ASSESSMENT_DISPLAY'],
  ['ROLE_ENGINEER', 'PPL_ASSESSMENT_MARK'],
  ['ROLE_ENGINEER', 'PPL_ASSESSMENT_SIT'],
  ['ROLE_MANAGER', 'PPL_ASSESSMENT_CHANGE'],
  ['ROLE_MANAGER', 'PPL_ASSESSMENT_DISPLAY'],
  ['ROLE_MANAGER', 'PPL_ASSESSMENT_MARK'],
  ['ROLE_MANAGER', 'PPL_ASSESSMENT_SIT'],
  ['ROLE_OPERATOR', 'PPL_ASSESSMENT_DISPLAY'],
  ['ROLE_OPERATOR', 'PPL_ASSESSMENT_SIT'],
  ['ROLE_STANDARD', 'PPL_ASSESSMENT_DISPLAY'],
  ['ROLE_STANDARD', 'PPL_ASSESSMENT_SIT'],
  ['ROLE_SUPERVISOR', 'PPL_ASSESSMENT_CHANGE'],
  ['ROLE_SUPERVISOR', 'PPL_ASSESSMENT_DISPLAY'],
  ['ROLE_SUPERVISOR', 'PPL_ASSESSMENT_MARK'],
  ['ROLE_SUPERVISOR', 'PPL_ASSESSMENT_SIT']
].sort();

let pool;
let closePool;

test.before(() => {
  ({ closePool } = require('../../src/platform/db'));
  pool = require('../../src/platform/db').getPool();
});

test.after(async () => {
  await closePool();
});

async function nonAdminGrants() {
  const { rows } = await pool.query(
    `SELECT r.code AS role_code, rp.permission_code
       FROM app_role_permissions rp
       JOIN app_roles r ON r.id = rp.app_role_id
      WHERE rp.permission_code LIKE 'PPL\\_ASSESSMENT\\_%' AND r.code <> 'ROLE_ADMIN'
      ORDER BY r.code, rp.permission_code`
  );
  return rows.map((row) => [row.role_code, row.permission_code]).sort();
}

async function totalGrants() {
  const { rows: [row] } = await pool.query('SELECT count(*)::int AS n FROM app_role_permissions');
  return row.n;
}

function migrate() {
  return execFileSync('npm', ['run', 'migrate'], {
    cwd: BACKEND_DIR,
    env: process.env,
    encoding: 'utf8'
  });
}

test('a migrated database holds the sixteen assessment grants on the five non-admin roles', async () => {
  assert.strictEqual(EXPECTED_GRANTS.length, 16, 'two on each of two roles, four on each of three');
  assert.deepStrictEqual(await nonAdminGrants(), EXPECTED_GRANTS);
});

test('running the migrations again changes nothing', async () => {
  const before = await totalGrants();
  const output = migrate();
  assert.match(output, /No migrations to run/i, 'no migration is pending');
  assert.deepStrictEqual(await nonAdminGrants(), EXPECTED_GRANTS);
  assert.strictEqual(await totalGrants(), before);
});

test('a code an administrator removed stays removed after the next migrate', async () => {
  try {
    const removed = await pool.query(
      `DELETE FROM app_role_permissions rp
        USING app_roles r
        WHERE r.id = rp.app_role_id AND r.code = 'ROLE_OPERATOR'
          AND rp.permission_code = 'PPL_ASSESSMENT_SIT'`
    );
    assert.strictEqual(removed.rowCount, 1);

    migrate();

    const { rows } = await pool.query(
      `SELECT 1 FROM app_role_permissions rp
         JOIN app_roles r ON r.id = rp.app_role_id
        WHERE r.code = 'ROLE_OPERATOR' AND rp.permission_code = 'PPL_ASSESSMENT_SIT'`
    );
    assert.strictEqual(rows.length, 0, 'the removed grant was not put back');
  } finally {
    await pool.query(
      `INSERT INTO app_role_permissions (app_role_id, permission_code)
       SELECT id, 'PPL_ASSESSMENT_SIT' FROM app_roles WHERE code = 'ROLE_OPERATOR'
       ON CONFLICT DO NOTHING`
    );
  }
});

test('the permissions catalogue still holds exactly the four assessment codes, unchanged', async () => {
  const { rows } = await pool.query(
    `SELECT code, module, label, description, sort_order
       FROM permissions WHERE code LIKE 'PPL\\_ASSESSMENT\\_%' ORDER BY sort_order`
  );
  assert.deepStrictEqual(rows, [
    {
      code: 'PPL_ASSESSMENT_DISPLAY',
      module: 'People',
      label: 'Assessments',
      description: 'Read an Assessment, its Attempts, and the Question bank behind it.',
      sort_order: 84
    },
    {
      code: 'PPL_ASSESSMENT_CHANGE',
      module: 'People',
      label: 'Maintain Assessments',
      description: 'Correct a Question bank, create an Assessment, assign it, allow a retake, or close one.',
      sort_order: 85
    },
    {
      code: 'PPL_ASSESSMENT_SIT',
      module: 'People',
      label: 'Sit my Assessment',
      description: "Start, answer and submit the caller's own Attempt.",
      sort_order: 86
    },
    {
      code: 'PPL_ASSESSMENT_MARK',
      module: 'People',
      label: 'Mark an Assessment',
      description: 'Mark a submitted Attempt: award or refuse a point, fix the final score, write the note.',
      sort_order: 87
    }
  ]);
});
