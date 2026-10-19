/*
 * Signing in with an email and a password held in our own database (issue
 * #268, part of #267), owned by the people Module because `app_users` is: a
 * session is the answer to "which Account is this", and the credential row is
 * keyed to the Account. `auth-routes.js` owns the HTTP surface.
 *
 * `AUTH_PASSWORD_MODE` says which door a deployment uses: `local` (this file,
 * `account_credentials` and `account_sessions`) or `supabase` (platform/
 * tokens.js, ADR-0002), the default. It is read on every call, never at load,
 * so a test or an operator flipping it needs no restart of the module graph.
 *
 * ## One refusal
 *
 * Every way a login can fail answers the same 401 with the same body — an
 * unknown email, a wrong password, an Account with no credential, a switched
 * -off credential, an Employee who is inactive or not linked at all — so the
 * login screen cannot be used to enumerate staff. An unknown email still pays
 * for one scrypt verification against a dummy hash, so response time does not
 * tell the two apart either.
 *
 * ## Who needs an Employee (ADR-0045)
 *
 * An Account is how a person on the floor signs in, and a person is an
 * Employee, so a non-admin Account signs in only while linked to an active
 * Employee. An Account whose role is 'admin' is the exception, by decision
 * and not by accident: the deployment's administrator is not necessarily a
 * plant employee, and without this exception nobody could administer the
 * site (issue #284). An admin still needs an enabled credential and a
 * matching password. An admin who IS linked keeps the Employee rule (a
 * Departed Employee's Account is still refused). An unlinked admin is
 * identified as `local-account:<app_users.id>`, not `local:<employee_no>`.
 *
 * ## Secrets
 *
 * The session token is 32 random bytes, base64url, returned once. Only its
 * SHA-256 is stored, as with the floor device credential and identification
 * token (floor-devices.js), so a database copy yields no live session.
 */

const crypto = require('node:crypto');
const { getPool, withActor } = require('../../platform/db');
const { hashSecret, verifySecret } = require('../../platform/secrets');
const { httpError } = require('./errors');

const SESSION_TTL_HOURS = 12;
const NOT_RECOGNISED = 'Email or password is not recognised.';

function passwordMode() {
  return process.env.AUTH_PASSWORD_MODE === 'local' ? 'local' : 'supabase';
}

function sha256(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}

function notRecognised() {
  return httpError(401, NOT_RECOGNISED);
}

// What an unknown email is verified against, so it costs what a real attempt
// costs. Built on first use and kept, not computed at load.
let dummyHash = null;
async function spendVerificationTime(password) {
  dummyHash ??= await hashSecret(crypto.randomBytes(16).toString('hex'));
  await verifySecret(password, dummyHash);
}

// The sign-in rule about Employees, stated once (ADR-0045). A linked Account
// needs its Employee to be active, whatever its role. An unlinked Account is
// allowed only if it is an administrator; every other role is refused.
function mayHoldLocalSession(row) {
  if (row.employee_id) return row.employee_is_active === true;
  return row.role === 'admin';
}

// The identity a local Account is known by, assigned on its first sign-in.
// `local:<employee_no>` for an Account with an Employee. An unlinked
// administrator has no employee number, so it is `local-account:<id>`: the
// primary key never changes or repeats, and the prefix differs from `local:`
// so it cannot equal any `local:<employee_no>` whatever an employee_no holds.
function localSubjectFor(row) {
  return row.employee_id ? `local:${row.employee_no}` : `local-account:${row.id}`;
}

// Verifies the email and password and mints a session. Deliberately does NOT
// filter on `app_users.is_active`: a pending Account must be able to sign in,
// so the app can show its awaiting-Approval screen, and it is requireActive
// (middleware.js) that then refuses it everywhere else.
async function signIn({ email, password }) {
  if (typeof email !== 'string' || typeof password !== 'string' || email.trim() === '' || password === '') {
    throw notRecognised();
  }

  // `app_users.email` is CITEXT, so this match ignores case.
  const { rows: [row] } = await getPool().query(
    `SELECT u.id, u.email, u.display_name, u.role, u.approval_status, u.employee_id,
            u.external_subject, e.employee_no, e.is_active AS employee_is_active,
            c.password_hash, c.is_enabled
       FROM app_users u
       LEFT JOIN employees e ON e.id = u.employee_id
       LEFT JOIN account_credentials c ON c.app_user_id = u.id
      WHERE u.email = $1`,
    [email.trim()]
  );

  if (!row || !row.password_hash) {
    await spendVerificationTime(password);
    throw notRecognised();
  }

  const passwordMatches = await verifySecret(password, row.password_hash);
  if (!passwordMatches || !row.is_enabled || !mayHoldLocalSession(row)) {
    throw notRecognised();
  }

  const token = crypto.randomBytes(32).toString('base64url');
  const expiresAt = await withActor(row.id, async (client) => {
    // A local Account's subject is given by localSubjectFor; one created
    // without a subject gets it on its first sign-in, and keeps it after.
    await client.query(
      `UPDATE app_users
          SET external_subject = COALESCE(external_subject, $2),
              last_login_at = now()
        WHERE id = $1`,
      [row.id, localSubjectFor(row)]
    );
    const { rows: [session] } = await client.query(
      `INSERT INTO account_sessions (app_user_id, token_hash, expires_at)
       VALUES ($1, $2, now() + make_interval(hours => $3))
       RETURNING expires_at`,
      [row.id, sha256(token), SESSION_TTL_HOURS]
    );
    return session.expires_at;
  });

  return {
    token,
    expiresAt,
    account: {
      id: row.id,
      email: row.email,
      displayName: row.display_name,
      role: row.role,
      approvalStatus: row.approval_status,
      employeeId: row.employee_id
    }
  };
}

// Resolves a presented session token to the identity `verifyToken` would have
// produced, plus the session's id, or null. `authenticate` feeds the identity
// to resolveAccountForIdentity unchanged.
//
// Deliberately does NOT require `app_users.is_active`: a pending Account has
// is_active = FALSE and is meant to hold a working session that requireActive
// then refuses with 403 pending_approval. Filtering here would turn that into
// a 401 and bypass Approval's own status reporting.
async function findSessionIdentity(token) {
  const { rows: [row] } = await getPool().query(
    `SELECT s.id, u.external_subject, u.email, u.display_name
       FROM account_sessions s
       JOIN app_users u ON u.id = s.app_user_id
      WHERE s.token_hash = $1
        AND s.revoked_at IS NULL
        AND s.expires_at > now()
        AND u.external_subject IS NOT NULL`,
    [sha256(token)]
  );
  if (!row) return null;
  return {
    sessionId: row.id,
    identity: { subject: row.external_subject, email: row.email, name: row.display_name }
  };
}

// Ends the session a token belongs to. Idempotent: revoking an already
// revoked (or expired) session succeeds and keeps its original revoked_at.
// Returns false only for a token that names no session at all.
async function revokeSessionByToken(token) {
  const { rowCount } = await getPool().query(
    `UPDATE account_sessions
        SET revoked_at = COALESCE(revoked_at, now())
      WHERE token_hash = $1`,
    [sha256(token)]
  );
  return rowCount > 0;
}

module.exports = { passwordMode, signIn, findSessionIdentity, revokeSessionByToken };
