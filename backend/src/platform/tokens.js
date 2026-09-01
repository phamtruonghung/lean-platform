/*
 * Verifying a Supabase Auth JWT, and nothing past that.
 *
 * Supabase Auth is the identity provider (ADR-0002): the Flutter client signs
 * in against it directly and sends the session's JWT as a bearer token. This
 * module answers exactly one question — "is this token genuine, and who does
 * it say signed in?" — and stops there. Resolving that subject to an Account,
 * deciding whether the Account may act, is the People Module's business, not
 * this one's: `check-module-boundaries.js` forbids platform code from
 * depending on a Module, so the reverse dependency has to be this narrow by
 * construction, not just by convention.
 *
 * Verification is asymmetric only. Supabase Auth signs with a JWKS-published
 * key (RS256/ES256, project-specific) and publishes the public half at
 * `${SUPABASE_URL}/auth/v1/.well-known/jwks.json` — `jose`'s
 * `createRemoteJWKSet` fetches and caches that set, verifying against the
 * current key and re-fetching on a `kid` it does not recognise (a rotation).
 * The legacy HS256 shared-secret scheme is deliberately not supported here:
 * that secret can *mint* tokens as well as verify them, and holding it in
 * this API is a materially bigger secret to protect than a public key ever
 * is. A project still on the legacy scheme needs migrating in the Supabase
 * dashboard before this Platform can authenticate against it.
 *
 * `issuer` and `audience` are both required and both checked explicitly on
 * every verification — a JWKS proves a token was signed by *a* key this
 * project trusts, not that it was issued for this project's users
 * specifically (`aud`) by this project's own Auth server (`iss`). `alg` is
 * never read from the token itself: `jwtVerify`'s `algorithms` option pins
 * verification to what the configured JWKS is allowed to produce, so a token
 * cannot talk its way into a different algorithm.
 */

const { createRemoteJWKSet, jwtVerify } = require('jose');

let jwks = null;
let jwksUrl = null;

// Lazily created and cached across calls, the same reasoning as
// `db.js`'s pool: `createRemoteJWKSet` keeps its own fetch/cache state
// keyed to the URL, and building a fresh one per request would throw that
// caching away and hit the JWKS endpoint on every single request.
//
// There is no test-only branch here. `SUPABASE_JWKS_URL` is ordinary
// configuration — in production it is Supabase's own endpoint, and in the
// integration tests it points at a plain `node:http` server the test itself
// serves a locally-generated JWKS document from (see
// `test/integration/accounts.test.js`), so verification always runs through
// this exact `createRemoteJWKSet` + `jwtVerify` path, over real HTTP, against
// a real signature.
function getJwks() {
  const configuredUrl = process.env.SUPABASE_JWKS_URL;

  if (!configuredUrl) {
    throw new Error('SUPABASE_JWKS_URL is not set. See .env.example.');
  }

  if (!jwks || jwksUrl !== configuredUrl) {
    jwks = createRemoteJWKSet(new URL(configuredUrl));
    jwksUrl = configuredUrl;
  }

  return jwks;
}

// Verifies a bearer token and returns the identity it asserts. Throws
// (via jwtVerify) on a bad signature, an expired token, or a mismatched
// issuer/audience — the caller decides what HTTP status that becomes.
async function verifyToken(token) {
  const issuer = process.env.SUPABASE_JWT_ISSUER;
  const audience = process.env.SUPABASE_JWT_AUDIENCE || 'authenticated';

  if (!issuer) {
    throw new Error('SUPABASE_JWT_ISSUER is not set. See .env.example.');
  }

  const { payload } = await jwtVerify(token, getJwks(), {
    issuer,
    audience,
    algorithms: ['RS256', 'ES256']
  });

  if (!payload.sub) {
    throw new Error('token has no subject');
  }

  return {
    subject: payload.sub,
    email: typeof payload.email === 'string' ? payload.email : undefined,
    // Supabase's session token carries provider profile data under
    // user_metadata (google's `full_name`/`name`, email/password sign-up's
    // own `full_name` if supplied at sign-up) — not a fixed shape.
    name: extractName(payload.user_metadata)
  };
}

function extractName(userMetadata) {
  if (!userMetadata || typeof userMetadata !== 'object') return undefined;
  const { full_name: fullName, name } = userMetadata;
  if (typeof fullName === 'string' && fullName.trim()) return fullName;
  if (typeof name === 'string' && name.trim()) return name;
  return undefined;
}

module.exports = { verifyToken };
