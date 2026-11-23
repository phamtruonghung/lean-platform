/*
 * Two gates every authenticated route in this Platform sits behind:
 * "does this token belong to an Account at all" (authenticate), and "is that
 * Account allowed to do anything yet" (requireActive). Kept as two
 * middlewares, not one, because exactly one route — an Account checking its
 * own status — needs the first without the second: an inactive Account must
 * still be able to see that it is inactive, per issue #6's acceptance
 * criteria.
 *
 * Issue #8 adds two more ways "not allowed to do anything yet" can be true —
 * rejected outright, or admitted and later deactivated — on top of #6's
 * original "never yet decided" (pending). `statusFor` is the one place that
 * three-way read of an Account happens, shared by requireActive's refusal
 * body below and routes.js's own `/me`, so the two can never drift apart on
 * what a given Account's status is called.
 *
 * The fourth way is a temporary password (audit F1): `account_credentials.
 * must_change_password` TRUE means the password the caller signed in with is
 * one somebody else chose — an administrator's reset, or the plant loader's
 * seeded credential. It allows exactly two doors, "who am I" and "choose a new
 * password", and nothing else. That check also lives in requireActive, for the
 * same reason the other three do: it is a fact about the Account, not about an
 * endpoint, so a route added later cannot forget it.
 */

const { resolveAccountForIdentity } = require('./service');
const { findSessionIdentity } = require('./sign-in');
const { mustChangePassword } = require('./passwords');

// Verifies the bearer token and resolves it to the Account its session names,
// through `resolveAccountForIdentity`. That function's create branch exists
// for a subject no row carries, not for a first sign-in: sign-in.js only
// mints a session for an Account that already exists, so nothing here creates
// one for a person arriving for the first time (service.js carries the
// detail). Attaches the result as `req.account`. Does NOT check `isActive` —
// see requireActive below.
async function authenticate(req, res, next) {
  const header = req.headers.authorization ?? '';
  const [scheme, token] = header.split(' ');

  if (scheme !== 'Bearer' || !token) {
    return res.status(401).json({ message: 'Missing bearer token' });
  }

  // The token is an opaque session token minted by sign-in.js: resolve it out
  // of `account_sessions` to the identity shape everything below shares.
  let identity;
  try {
    const found = await findSessionIdentity(token);
    if (!found) throw new Error('no such session');
    identity = found.identity;
    req.sessionId = found.sessionId;
  } catch (error) {
    return res.status(401).json({ message: 'Invalid or expired token' });
  }

  try {
    req.account = await resolveAccountForIdentity(identity);
    return next();
  } catch (error) {
    return next(error);
  }
}

// `is_active` alone says whether an Account may act right now; it does not
// say *why* not, and issue #8 needs the Flutter app to tell those reasons
// apart (a rejected Account should never be shown the same awaiting
// -Approval screen as one still genuinely pending). `approval_status`
// (migrations/1788295040758_account-approval-status.js) is what carries
// that reason — see that migration's own header for the full state mapping.
// 'pending_approval' is the one string that must never change: the Flutter
// app's existing awaiting-Approval screen already keys off it (issue #6).
function statusFor(account) {
  if (account.isActive) return 'active';
  if (account.approvalStatus === 'rejected') return 'rejected';
  if (account.approvalStatus === 'approved') return 'deactivated';
  return 'pending_approval';
}

// The refusal every endpoint except "my own status" needs: a distinct 403
// shape, not a generic error, so the Flutter app can show the right screen
// rather than a generic error screen — pending, rejected and deactivated
// are three different screens, per issue #8. Must run after authenticate(),
// which is what populates req.account.
//
// The temporary-password branch refuses with a `code` of its own
// (MUST_CHANGE_PASSWORD) beside a `status` of `password_change_required`, so
// a client matches the code rather than the sentence. `code` is what the
// audit asked for: a bare 403 cannot be told apart from a permission refusal.
const MUST_CHANGE_PASSWORD = 'MUST_CHANGE_PASSWORD';

// The one authenticated write a temporary password must leave open, or the
// Account could never leave that state. A route opts out explicitly by naming
// this middleware in front of requireActive — PUT /api/people/me/password
// (routes.js) and nothing else — rather than requireActive matching on a path
// string, which a route rename would silently break.
function allowWhilePasswordChangeRequired(req, _res, next) {
  req.passwordChangeExempt = true;
  return next();
}

async function requireActive(req, res, next) {
  if (!req.account.isActive) {
    const status = statusFor(req.account);
    const message = {
      pending_approval: 'This Account is awaiting Approval from an administrator.',
      rejected: "This Account's request to join the Platform was rejected.",
      deactivated: 'This Account has been deactivated by an administrator.'
    }[status];

    return res.status(403).json({ status, message });
  }

  // Checked after the isActive branch on purpose: an inactive Account hears
  // why it is inactive, never that it should change a password it may not use.
  if (req.passwordChangeExempt) return next();

  // One extra row read per authenticated request: `account_credentials` is
  // keyed by app_user_id, so this is a primary-key lookup beside the role and
  // scope reads every guarded route already does. The flag is read fresh
  // rather than cached on the session, for the same reason roles are: an
  // administrator's reset must take effect on the caller's very next request.
  let mustChange;
  try {
    mustChange = await mustChangePassword(req.account.id);
  } catch (error) {
    return next(error);
  }
  if (!mustChange) return next();

  return res.status(403).json({
    status: 'password_change_required',
    code: MUST_CHANGE_PASSWORD,
    message: 'This Account holds a temporary password. Change it before using anything else.'
  });
}

module.exports = { authenticate, requireActive, allowWhilePasswordChangeRequired, statusFor };
