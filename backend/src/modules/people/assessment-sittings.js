/*
 * The floor door's credential for one running Attempt (issue #588, ADR-0068,
 * slice 5; spec sections 4.6 and 9.1): `assessment_sittings`, the table the
 * slice 3 migration already created.
 *
 * The floor device identifies a person for 120 seconds; a paper runs 20 or 30
 * minutes. A sitting token bridges that gap and does nothing else: it is minted
 * by `start` behind a live identification, it is stored only as its SHA-256
 * (as `technician_identifications` stores its own), and it names one Attempt on
 * one device. `expires_at` is `deadline_at + 5 minutes`, computed here in SQL
 * from the Attempt's own row so no client or clock in Node decides it.
 *
 * One row per Attempt (`attempt_id` is UNIQUE). A second `start` replaces the
 * row's `token_hash`, `floor_device_id` and `issued_at` and clears
 * `revoked_at`, so the previous token stops matching and a sitting can never
 * mint a second Attempt. `attach_audit` keeps each replacement.
 *
 * Nothing here knows who is calling a route; the routes ask. The paper itself
 * (draw, read, answer, submit, result) stays in assessments.js and
 * assessment-marking.js, so the floor door and the Account door cannot
 * disagree about it.
 */

const crypto = require('node:crypto');
const { getPool, withActor } = require('../../platform/db');
const { notFound } = require('./errors');

function sha256(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}

// The three facts a floor route needs before it may touch an Attempt: that it
// exists (404), whose it is and which Org Unit it sits in. Existence is asked
// before scope, as AGENTS.md section 6 requires.
async function findAttemptScope(attemptId) {
  const { rows: [row] } = await getPool().query(
    'SELECT id, employee_id, org_unit_id, status FROM assessment_attempts WHERE id = $1',
    [attemptId]
  );
  if (!row) return null;
  return { id: row.id, employeeId: row.employee_id, orgUnitId: row.org_unit_id, status: row.status };
}

// Mints (or replaces) the sitting for an Attempt that is `in_progress` and
// returns the token once. `deadline_at` is read from the Attempt in the same
// statement, so the expiry cannot drift from the deadline the paper reports.
async function mintSitting({ attemptId, employeeId, deviceId }) {
  const token = crypto.randomBytes(32).toString('base64url');
  const minted = await withActor(null, async (client) => {
    const { rowCount } = await client.query(
      `INSERT INTO assessment_sittings
         (attempt_id, employee_id, floor_device_id, token_hash, issued_at, expires_at)
       SELECT at.id, $2, $3, $4, now(), at.deadline_at + interval '5 minutes'
         FROM assessment_attempts at
        WHERE at.id = $1 AND at.status = 'in_progress'
       ON CONFLICT (attempt_id) DO UPDATE
          SET employee_id = EXCLUDED.employee_id,
              floor_device_id = EXCLUDED.floor_device_id,
              token_hash = EXCLUDED.token_hash,
              issued_at = EXCLUDED.issued_at,
              expires_at = EXCLUDED.expires_at,
              revoked_at = NULL`,
      [attemptId, employeeId, deviceId, sha256(token)]
    );
    return rowCount === 1;
  });
  if (!minted) throw notFound('Assessment attempt');
  return token;
}

// The sitting a presented token names, or null: the hash must match, for this
// Attempt, on this device, not revoked and not past `expires_at`. Any miss is
// the same null, so the route answers one 401 and says nothing about which.
async function findValidSitting(token, attemptId, deviceId) {
  if (typeof token !== 'string' || token === '') return null;
  const { rows: [row] } = await getPool().query(
    `SELECT employee_id
       FROM assessment_sittings
      WHERE token_hash = $1
        AND attempt_id = $2
        AND floor_device_id = $3
        AND revoked_at IS NULL
        AND now() < expires_at`,
    [sha256(token), attemptId, deviceId]
  );
  return row ? { employeeId: row.employee_id } : null;
}

// A Team Leader's "End sitting": the candidate's next request is a 401 and the
// Attempt keeps running on the server's clock. False when the Attempt has no
// sitting at all.
async function endSitting(accountId, attemptId) {
  return withActor(accountId, async (client) => {
    const { rowCount } = await client.query(
      'UPDATE assessment_sittings SET revoked_at = now() WHERE attempt_id = $1',
      [attemptId]
    );
    return rowCount > 0;
  });
}

module.exports = { findAttemptScope, mintSitting, findValidSitting, endSitting };
