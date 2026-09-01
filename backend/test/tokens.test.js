/*
 * verifyToken(), against a real signature over real HTTP.
 *
 * Per issue #6: this environment has no live Supabase project to verify a
 * real token against, but the resolve-subject logic still needs a real test
 * rather than being skipped outright. test/helpers/jwks.js stands up a
 * `node:http` server publishing a locally generated RSA JWKS and signs tokens
 * with its private half, so every test below drives verifyToken()'s actual
 * `createRemoteJWKSet` + `jwtVerify` path — the same code that runs against
 * Supabase's real JWKS endpoint in production — rather than a stub of it.
 *
 * Needs no database: this is a unit test of one platform module, run via
 * `npm test`.
 */

const test = require('node:test');
const assert = require('node:assert');
const { createTestJwks } = require('./helpers/jwks');

const ISSUER = 'https://example.supabase.co/auth/v1';
const AUDIENCE = 'authenticated';

// tokens.js reads SUPABASE_JWKS_URL/SUPABASE_JWT_ISSUER/SUPABASE_JWT_AUDIENCE
// lazily, per call, and caches its JWKS keyed by URL — so each test gets its
// own JWKS server on its own URL, which is what forces a fresh fetch instead
// of silently reusing a previous test's cached key set.
async function withEnv(jwks, overrides, fn) {
  const previous = {
    SUPABASE_JWKS_URL: process.env.SUPABASE_JWKS_URL,
    SUPABASE_JWT_ISSUER: process.env.SUPABASE_JWT_ISSUER,
    SUPABASE_JWT_AUDIENCE: process.env.SUPABASE_JWT_AUDIENCE
  };
  process.env.SUPABASE_JWKS_URL = jwks.url;
  process.env.SUPABASE_JWT_ISSUER = ISSUER;
  process.env.SUPABASE_JWT_AUDIENCE = AUDIENCE;
  Object.assign(process.env, overrides);
  try {
    await fn();
  } finally {
    for (const [key, value] of Object.entries(previous)) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  }
}

test('verifyToken resolves a genuine token to its subject, email and display name', async () => {
  const jwks = await createTestJwks();
  const { verifyToken } = require('../src/platform/tokens');
  try {
    await withEnv(jwks, {}, async () => {
      const token = await jwks.signToken(
        { sub: 'user-abc-123', email: 'ada@example.com', user_metadata: { full_name: 'Ada Example' } },
        { issuer: ISSUER, audience: AUDIENCE }
      );

      const identity = await verifyToken(token);
      assert.deepStrictEqual(identity, {
        subject: 'user-abc-123',
        email: 'ada@example.com',
        name: 'Ada Example'
      });
    });
  } finally {
    await jwks.close();
  }
});

test('verifyToken falls back to user_metadata.name when full_name is absent', async () => {
  const jwks = await createTestJwks();
  const { verifyToken } = require('../src/platform/tokens');
  try {
    await withEnv(jwks, {}, async () => {
      const token = await jwks.signToken(
        { sub: 'user-google-1', email: 'g@example.com', user_metadata: { name: 'Googled Person' } },
        { issuer: ISSUER, audience: AUDIENCE }
      );

      const identity = await verifyToken(token);
      assert.strictEqual(identity.name, 'Googled Person');
    });
  } finally {
    await jwks.close();
  }
});

test('verifyToken rejects a token with no subject', async () => {
  const jwks = await createTestJwks();
  const { verifyToken } = require('../src/platform/tokens');
  try {
    await withEnv(jwks, {}, async () => {
      const token = await jwks.signToken({ email: 'no-sub@example.com' }, { issuer: ISSUER, audience: AUDIENCE });
      await assert.rejects(() => verifyToken(token), /no subject/);
    });
  } finally {
    await jwks.close();
  }
});

test('verifyToken rejects a token from the wrong issuer', async () => {
  const jwks = await createTestJwks();
  const { verifyToken } = require('../src/platform/tokens');
  try {
    await withEnv(jwks, {}, async () => {
      const token = await jwks.signToken(
        { sub: 'user-1' },
        { issuer: 'https://not-this-project.supabase.co/auth/v1', audience: AUDIENCE }
      );
      await assert.rejects(() => verifyToken(token));
    });
  } finally {
    await jwks.close();
  }
});

test('verifyToken rejects a token for the wrong audience', async () => {
  const jwks = await createTestJwks();
  const { verifyToken } = require('../src/platform/tokens');
  try {
    await withEnv(jwks, {}, async () => {
      const token = await jwks.signToken({ sub: 'user-1' }, { issuer: ISSUER, audience: 'some-other-audience' });
      await assert.rejects(() => verifyToken(token));
    });
  } finally {
    await jwks.close();
  }
});

test('verifyToken rejects an expired token', async () => {
  const jwks = await createTestJwks();
  const { verifyToken } = require('../src/platform/tokens');
  try {
    await withEnv(jwks, {}, async () => {
      const token = await jwks.signToken(
        { sub: 'user-1' },
        { issuer: ISSUER, audience: AUDIENCE, expiresIn: Math.floor(Date.now() / 1000) - 60 }
      );
      await assert.rejects(() => verifyToken(token), /exp/i);
    });
  } finally {
    await jwks.close();
  }
});

test('verifyToken rejects a token signed by a key the JWKS does not publish', async () => {
  const jwks = await createTestJwks();
  const impostor = await createTestJwks();
  const { verifyToken } = require('../src/platform/tokens');
  try {
    // Signed by the impostor's private key, but verified against jwks' JWKS
    // (a different key entirely, same kid) — this is what a forged token
    // looks like: correct shape, wrong signature.
    await withEnv(jwks, {}, async () => {
      const token = await impostor.signToken({ sub: 'user-1' }, { issuer: ISSUER, audience: AUDIENCE });
      await assert.rejects(() => verifyToken(token));
    });
  } finally {
    await jwks.close();
    await impostor.close();
  }
});

test('verifyToken throws a clear error when SUPABASE_JWKS_URL is not configured', async () => {
  const previousUrl = process.env.SUPABASE_JWKS_URL;
  const previousIssuer = process.env.SUPABASE_JWT_ISSUER;
  delete process.env.SUPABASE_JWKS_URL;
  // The issuer is set explicitly so the missing-JWKS-URL check is the one
  // that actually fires — verifyToken checks the issuer first, and an unset
  // issuer would throw its own, different error before ever reaching it.
  process.env.SUPABASE_JWT_ISSUER = ISSUER;
  const { verifyToken } = require('../src/platform/tokens');
  try {
    await assert.rejects(() => verifyToken('irrelevant'), /SUPABASE_JWKS_URL is not set/);
  } finally {
    if (previousUrl === undefined) delete process.env.SUPABASE_JWKS_URL;
    else process.env.SUPABASE_JWKS_URL = previousUrl;
    if (previousIssuer === undefined) delete process.env.SUPABASE_JWT_ISSUER;
    else process.env.SUPABASE_JWT_ISSUER = previousIssuer;
  }
});
