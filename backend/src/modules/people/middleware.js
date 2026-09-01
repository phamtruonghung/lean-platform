/*
 * Two gates every authenticated route in this Platform sits behind:
 * "does this token belong to an Account at all" (authenticate), and "is that
 * Account allowed to do anything yet" (requireActive). Kept as two
 * middlewares, not one, because exactly one route — an Account checking its
 * own status — needs the first without the second: an inactive Account must
 * still be able to see that it is inactive, per issue #6's acceptance
 * criteria.
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

// The refusal every endpoint except "my own status" needs: a distinct 403
// shape (`status: 'pending_approval'`), not a generic error, so the Flutter
// app can show its awaiting-Approval screen rather than an error screen. Must
// run after authenticate(), which is what populates req.account.
function requireActive(req, res, next) {
  if (!req.account.isActive) {
    return res.status(403).json({
      status: 'pending_approval',
      message: 'This Account is awaiting Approval from an administrator.'
    });
  }
  return next();
}

module.exports = { authenticate, requireActive };
