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
 */

const { verifyToken } = require('../../platform/tokens');
const { resolveAccountForIdentity } = require('./service');

// Verifies the bearer token and resolves it to an Account, creating one on a
// subject's first sign-in (see service.js). Attaches the result as
// `req.account`. Does NOT check `isActive` — see requireActive below.
async function authenticate(req, res, next) {
  const header = req.headers.authorization ?? '';
  const [scheme, token] = header.split(' ');

  if (scheme !== 'Bearer' || !token) {
    return res.status(401).json({ message: 'Missing bearer token' });
  }

  let identity;
  try {
    identity = await verifyToken(token);
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
function requireActive(req, res, next) {
  if (req.account.isActive) return next();

  const status = statusFor(req.account);
  const message = {
    pending_approval: 'This Account is awaiting Approval from an administrator.',
    rejected: "This Account's request to join the Platform was rejected.",
    deactivated: 'This Account has been deactivated by an administrator.'
  }[status];

  return res.status(403).json({ status, message });
}

module.exports = { authenticate, requireActive, statusFor };
