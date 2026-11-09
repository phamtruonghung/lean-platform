/*
 * A real local session, for tests that need a signed-in Account.
 *
 * `src/modules/people/middleware.js` picks the door from `AUTH_PASSWORD_MODE`
 * (issue #268): `local` resolves an opaque token out of `account_sessions`,
 * anything else verifies a hosted-provider JWT. The integration suite
 * authenticates through the local door, so a test's token is a real
 * `account_sessions` row and no part of the hosted provider is involved.
 *
 * `tokenFor(subject)` opens a session for the Account whose
 * `app_users.external_subject` is `subject` — the identity the token's own
 * `sub` claim used to carry, and the one thing either door uses to resolve an
 * Account. `findSessionIdentity` reads the row's own email and display name,
 * so a caller only names the subject; role, approval status and whether the
 * Account is switched on all live on the row, never in the token.
 *
 * The Account itself stays the test's own setup, inserted against Postgres
 * the way every other fixture in this directory is (see
 * test/integration/plant.test.js): this helper deliberately does not create
 * one, because an Account created as a side effect of asking for a token
 * hides which suite depends on which row. A missing row throws with the
 * subject in the message rather than 401-ing later as a confusing failure.
 */

const crypto = require('node:crypto');

// The door every importing file authenticates through. Read per request by
// passwordMode(), never at load, so setting it here is enough for the whole
// run; a file that flips the mode itself (auth-login.test.js, to prove the
// mode decides the door) still can, in its own test hooks.
process.env.AUTH_PASSWORD_MODE = 'local';

// The same lifetime a real sign-in gives a session (sign-in.js's
// SESSION_TTL_HOURS). Any future instant would do; matching the real one
// keeps this helper from disagreeing with the door about what a session is.
const SESSION_TTL_HOURS = 12;

function sha256(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}

// The Pool the API itself is using. Required inside the call rather than at
// the top of this file so the module is loaded after a test's own
// test.before() has set DATABASE_URL and required src/index.js — the ordering
// every integration file already relies on — and so this is the one instance
// (module cache) the test's own requests go through.
function pool() {
  return require('../../src/platform/db').getPool();
}

// Returns a fresh opaque token for `subject`'s Account, having stored only
// its SHA-256 — the same shape sign-in.js mints, so nothing about the
// session door is stubbed.
async function tokenFor(subject) {
  const { rows: [account] } = await pool().query(
    'SELECT id FROM app_users WHERE external_subject = $1',
    [subject]
  );
  if (!account) {
    throw new Error(
      `no Account has external_subject ${JSON.stringify(subject)} — insert its app_users row before asking for a session`
    );
  }

  const token = crypto.randomBytes(32).toString('base64url');
  await pool().query(
    `INSERT INTO account_sessions (app_user_id, token_hash, expires_at)
     VALUES ($1, $2, now() + make_interval(hours => $3))`,
    [account.id, sha256(token), SESSION_TTL_HOURS]
  );
  return token;
}

module.exports = { tokenFor };
