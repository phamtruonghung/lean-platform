/*
 * sqdcp_maintenance() purges expired Account sessions and technician
 * identifications, and only the expired ones. It asserts against Postgres
 * directly: the purge is a nightly database job with no endpoint, the same
 * named exception schema.test.js documents (AGENTS.md section 3).
 *
 * Needs a database with every migration applied. Set DATABASE_URL first.
 */

const test = require('node:test');
const assert = require('node:assert');
const crypto = require('node:crypto');

let pool;
let closePool;
const tag = `purge${process.pid}`;
const hash = (name) => crypto.createHash('sha256').update(`${tag}-${name}`).digest('hex');

let accountId;
let employeeId;
let siteId;
let deviceId;

test.before(async () => {
  ({ closePool } = require('../../src/platform/db'));
  pool = require('../../src/platform/db').getPool();

  const { rows: [account] } = await pool.query(
    `INSERT INTO app_users (email, display_name, role, is_active, approval_status)
     VALUES ($1, 'Purge Test', 'operator', TRUE, 'approved') RETURNING id`,
    [`${tag}@example.com`]
  );
  accountId = account.id;
  const { rows: [employee] } = await pool.query(
    `INSERT INTO employees (employee_no, first_name, last_name, is_active)
     VALUES ($1, 'Purge', 'Test', TRUE) RETURNING id`,
    [tag]
  );
  employeeId = employee.id;
  const { rows: [site] } = await pool.query(
    `INSERT INTO sites (code, name, timezone) VALUES ($1, 'Purge Site', 'UTC') RETURNING id`,
    [tag]
  );
  siteId = site.id;
  const { rows: [orgUnit] } = await pool.query(
    `INSERT INTO org_units (site_id, code, name, unit_type) VALUES ($1, $2, 'Purge Unit', 'area') RETURNING id`,
    [siteId, tag]
  );
  const { rows: [device] } = await pool.query(
    `INSERT INTO floor_devices (org_unit_id, name, credential_hash) VALUES ($1, 'Purge device', $2) RETURNING id`,
    [orgUnit.id, hash('device')]
  );
  deviceId = device.id;
});

test.after(async () => {
  await pool.query('DELETE FROM technician_identifications WHERE floor_device_id = $1', [deviceId]);
  await pool.query('DELETE FROM floor_devices WHERE id = $1', [deviceId]);
  await pool.query('DELETE FROM org_units WHERE site_id = $1', [siteId]);
  await pool.query('DELETE FROM sites WHERE id = $1', [siteId]);
  await pool.query('DELETE FROM employees WHERE id = $1', [employeeId]);
  await pool.query('DELETE FROM app_users WHERE id = $1', [accountId]);
  await closePool();
});

test('sqdcp_maintenance() removes expired sessions and identifications and keeps live ones', async () => {
  for (const [name, offset] of [['sess-old', '-1 hour'], ['sess-live', '1 hour']]) {
    await pool.query(
      `INSERT INTO account_sessions (app_user_id, token_hash, expires_at)
       VALUES ($1, $2, now() + $3::interval)`,
      [accountId, hash(name), offset]
    );
  }
  for (const [name, offset] of [['ident-old', '-1 minute'], ['ident-live', '5 minutes']]) {
    await pool.query(
      `INSERT INTO technician_identifications (floor_device_id, employee_id, token_hash, expires_at)
       VALUES ($1, $2, $3, now() + $4::interval)`,
      [deviceId, employeeId, hash(name), offset]
    );
  }

  await pool.query('SELECT sqdcp_maintenance()');

  const { rows: sessions } = await pool.query(
    'SELECT token_hash FROM account_sessions WHERE app_user_id = $1', [accountId]
  );
  assert.deepStrictEqual(sessions.map((row) => row.token_hash), [hash('sess-live')]);
  const { rows: identifications } = await pool.query(
    'SELECT token_hash FROM technician_identifications WHERE floor_device_id = $1', [deviceId]
  );
  assert.deepStrictEqual(identifications.map((row) => row.token_hash), [hash('ident-live')]);
});
