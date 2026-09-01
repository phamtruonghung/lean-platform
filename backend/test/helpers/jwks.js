/*
 * A locally-issued JWKS, for tests that need a genuine Supabase-shaped token
 * without reaching Supabase itself.
 *
 * `src/platform/tokens.js` verifies over real HTTP, via `jose`'s
 * `createRemoteJWKSet` — there is no test-only code path in that module (see
 * its own file header for why). So the only way to exercise it without a live
 * Supabase project is to stand up something that answers like one: a real
 * `node:http` server serving a real JWKS document for a real, locally
 * generated RSA key pair, and sign test tokens with the private half. Every
 * assertion that uses this therefore runs `verifyToken()`'s actual signature
 * -verification and HTTP-fetch code, not a stub of it.
 */

const http = require('node:http');
const { generateKeyPair, exportJWK, SignJWT } = require('jose');

const KID = 'test-key';

async function createTestJwks() {
  const { publicKey, privateKey } = await generateKeyPair('RS256');
  const jwk = await exportJWK(publicKey);
  jwk.kid = KID;
  jwk.alg = 'RS256';
  jwk.use = 'sig';

  const server = http.createServer((_req, res) => {
    res.setHeader('content-type', 'application/json');
    res.end(JSON.stringify({ keys: [jwk] }));
  });

  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const { port } = server.address();

  // signToken defaults to a token that verifyToken() should accept outright;
  // callers override individual fields to build the rejection cases (wrong
  // issuer, expired, ...).
  async function signToken(claims = {}, { issuer, audience, expiresIn = '1h', kid = KID } = {}) {
    let builder = new SignJWT(claims)
      .setProtectedHeader({ alg: 'RS256', kid })
      .setIssuedAt();
    if (issuer !== undefined) builder = builder.setIssuer(issuer);
    if (audience !== undefined) builder = builder.setAudience(audience);
    builder = builder.setExpirationTime(expiresIn);
    return builder.sign(privateKey);
  }

  function close() {
    return new Promise((resolve) => server.close(resolve));
  }

  return { url: `http://127.0.0.1:${port}/jwks.json`, signToken, close };
}

module.exports = { createTestJwks };
