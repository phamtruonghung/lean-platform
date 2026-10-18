/*
 * The sign-in HTTP surface (issue #268), mounted at `/api/auth` by
 * src/index.js rather than under `/api/people`: it is the door every other
 * route's bearer token comes through, not a People resource. sign-in.js owns
 * the logic; see its header for the single-refusal rule.
 *
 *   - POST /login  — {email, password} -> {token, expiresAt, account}.
 *   - POST /logout — ends the caller's own session. Idempotent.
 *   - GET  /mode   — {"password":"local"|"supabase"}, unauthenticated, so a
 *     client knows which sign-in form to show before it has any token.
 */

const express = require('express');
const { authenticate } = require('./middleware');
const { handleError } = require('./errors');
const { passwordMode, signIn, revokeSessionByToken } = require('./sign-in');

const router = express.Router();

router.get('/mode', (_req, res) => {
  res.json({ password: passwordMode() });
});

router.post('/login', async (req, res, next) => {
  try {
    const { email, password } = req.body ?? {};
    res.json(await signIn({ email, password }));
  } catch (error) {
    handleError(error, res, next);
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
