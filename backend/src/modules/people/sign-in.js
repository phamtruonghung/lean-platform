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
  if (!passwordMatches || !row.is_enabled || !row.employee_id || !row.employee_is_active) {
    throw notRecognised();
  }

  const token = crypto.randomBytes(32).toString('base64url');
  const expiresAt = await withActor(row.id, async (client) => {
    // A local Account is identified as `local:<employee_no>`; one created
    // without a subject gets it on its first sign-in.
    await client.query(
      `UPDATE app_users
          SET external_subject = COALESCE(external_subject, $2),
              last_login_at = now()
        WHERE id = $1`,
      [row.id, `local:${row.employee_no}`]
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
