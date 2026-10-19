/*
 * The sign-in HTTP surface (issue #268), mounted at `/api/auth` by
 * src/index.js rather than under `/api/people`: it is the door every other
 * route's bearer token comes through, not a People resource. sign-in.js owns
 * the logic; see its header for the single-refusal rule.
 *
 *   - POST /login  — {email, password} -> {token, expiresAt, account}. Exists
 *     only when passwordMode() is 'local' (404 otherwise, checked per request
 *     like the mode itself), and is throttled per client address and per email
 *     (login-throttle.js): 429 with Retry-After once a limit is reached.
 *   - POST /logout — ends the caller's own session. Idempotent.
 *   - GET  /mode   — {"password":"local"|"supabase"}, unauthenticated, so a
 *     client knows which sign-in form to show before it has any token.
 */

const express = require('express');
const { authenticate } = require('./middleware');
const { handleError } = require('./errors');
const { passwordMode, signIn, revokeSessionByToken } = require('./sign-in');
const loginThrottle = require('./login-throttle');

const router = express.Router();

router.get('/mode', (_req, res) => {
  res.json({ password: passwordMode() });
});

router.post('/login', async (req, res, next) => {
  if (passwordMode() !== 'local') {
    return res.status(404).json({ message: 'Not found' });
  }

  try {
    const { email, password } = req.body ?? {};
    const caller = { ip: req.ip, email };
    loginThrottle.begin(caller);
    const session = await signIn({ email, password });
    loginThrottle.succeeded(caller);
    return res.json(session);
  } catch (error) {
    if (error.retryAfterSeconds) res.set('Retry-After', String(error.retryAfterSeconds));
    return handleError(error, res, next);
  }
});

// In local mode the token is looked up directly rather than through
// `authenticate`, which refuses a revoked session: a second logout with the
// same token must still succeed, and only a token naming no session is a 401.
// In supabase mode there is no session of ours to end — the JWT is stateless
// and the client signs out of Supabase itself — so an authenticated caller
// gets the same success and nothing is written.
router.post('/logout', async (req, res, next) => {
  if (passwordMode() !== 'local') {
    return authenticate(req, res, () => res.status(204).end());
  }

  try {
    const [scheme, token] = (req.headers.authorization ?? '').split(' ');
    if (scheme !== 'Bearer' || !token) {
      return res.status(401).json({ message: 'Missing bearer token' });
    }
    if (!(await revokeSessionByToken(token))) {
      return res.status(401).json({ message: 'Invalid or expired token' });
    }
    return res.status(204).end();
  } catch (error) {
    return handleError(error, res, next);
  }
});

module.exports = router;
