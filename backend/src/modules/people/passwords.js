/*
 * Setting an Account's password in our own database (issue #270, part of
 * #267), for deployments running AUTH_PASSWORD_MODE=local (sign-in.js). Two
 * doors, one hashing path (platform/secrets.js, the one the login verifies):
 *
 *   - an administrator resets another Account's password, and
 *   - a person changes their own, proving the current one first.
 *
 * ## Rules
 *
 * Minimum length is MIN_PASSWORD_LENGTH, checked by requireAcceptablePassword,
 * the only place the number lives; both doors call it.
 *
 * A reset stores `must_change_password = TRUE`: the administrator knows the
 * password they just set, so it is temporary. A person's own change stores
 * FALSE. The flag is reported, not enforced by the API: /login and /api/people/me
 * return it as `account.mustChangePassword`, and the client sends the person
 * to change their password before anything else (frontend/lib/platform/
 * router.dart). Enforcing it server-side (refusing other routes until the
 * change) is a named follow-up. A reset leaves `is_enabled` alone, and ends
 * ALL of the target's sessions in the same transaction as the new password:
 * the old password may be known to someone else, and a session minted with it
 * must not outlive the reset.
 *
 * A self-change revokes the Account's OTHER sessions and never the caller's:
 * the usual reason to change a password is that someone else may hold it, and
 * an old device must not outlive the change. A wrong current password is a
 * 400, not a 401 — a 401 would make the client sign the person out — and
 * touches nothing.
 *
 * No function here returns, logs or stores a password in the clear; the
 * response is the Account's own shape (toAccount), which has no password field.
 * `account_credentials` has no audit trigger, so no hash reaches `audit_log`.
 */

const { getPool, withActor } = require('../../platform/db');
const { hashSecret, verifySecret } = require('../../platform/secrets');
const { httpError } = require('./errors');
const {
  ACCOUNT_COLUMNS,
  SELF_PASSWORD_RESET_REFUSED,
  refuseSelfAction,
  notFoundAccount,
  toAccount
} = require('./service');

const MIN_PASSWORD_LENGTH = 8;

function requireAcceptablePassword(value, fieldName) {
  if (typeof value !== 'string') {
    throw httpError(400, `${fieldName} is required`);
  }
  if (value.length < MIN_PASSWORD_LENGTH) {
    throw httpError(400, `${fieldName} must be at least ${MIN_PASSWORD_LENGTH} characters`);
  }
  return value;
}

async function resetPassword(id, password, actingAccountId) {
  refuseSelfAction(id, actingAccountId, SELF_PASSWORD_RESET_REFUSED);
  requireAcceptablePassword(password, 'password');

  const { rows: [row] } = await getPool().query(
    `SELECT ${ACCOUNT_COLUMNS} FROM app_users WHERE id = $1`,
    [id]
  );
  if (!row) throw notFoundAccount();

  const passwordHash = await hashSecret(password);
  await withActor(actingAccountId, async (client) => {
    await client.query(
      `INSERT INTO account_credentials (app_user_id, password_hash, must_change_password)
       VALUES ($1, $2, TRUE)
       ON CONFLICT (app_user_id) DO UPDATE
         SET password_hash = EXCLUDED.password_hash,
             must_change_password = TRUE,
             updated_at = now()`,
      [id, passwordHash]
    );
    await client.query(
      `UPDATE account_sessions
          SET revoked_at = now()
        WHERE app_user_id = $1 AND revoked_at IS NULL`,
      [id]
    );
  });
  return toAccount(row);
}

// Whether the Account must change its password before using the Platform. An
// Account with no credential row (Supabase mode, or none set) has nothing to
// change here, so false.
async function mustChangePassword(accountId) {
  const { rows: [row] } = await getPool().query(
    'SELECT must_change_password FROM account_credentials WHERE app_user_id = $1',
    [accountId]
  );
  return row?.must_change_password === true;
}

async function changeOwnPassword(accountId, { currentPassword, newPassword }, sessionId) {
  if (typeof currentPassword !== 'string') {
    throw httpError(400, 'currentPassword is required');
  }
  requireAcceptablePassword(newPassword, 'newPassword');

  const { rows: [credential] } = await getPool().query(
    'SELECT password_hash FROM account_credentials WHERE app_user_id = $1',
    [accountId]
  );
  if (!credential) {
    throw httpError(409, 'This Account holds no password here, so there is none to change.');
  }
  if (!(await verifySecret(currentPassword, credential.password_hash))) {
    throw httpError(400, 'Current password is not correct.');
  }

  const passwordHash = await hashSecret(newPassword);
  return withActor(accountId, async (client) => {
    await client.query(
      `UPDATE account_credentials
          SET password_hash = $2, must_change_password = FALSE, updated_at = now()
        WHERE app_user_id = $1`,
      [accountId, passwordHash]
    );
    await client.query(
      `UPDATE account_sessions
          SET revoked_at = now()
        WHERE app_user_id = $1 AND revoked_at IS NULL AND id IS DISTINCT FROM $2`,
      [accountId, sessionId]
    );
    const { rows: [row] } = await client.query(
      `SELECT ${ACCOUNT_COLUMNS} FROM app_users WHERE id = $1`,
      [accountId]
    );
    return toAccount(row);
  });
}

module.exports = {
  MIN_PASSWORD_LENGTH,
  requireAcceptablePassword,
  resetPassword,
  changeOwnPassword,
  mustChangePassword
};
