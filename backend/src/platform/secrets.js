/*
 * Hashing and verifying a low-entropy secret — a floor PIN, an Account's
 * password — and nothing past that.
 *
 * One scheme, shared by every caller (issue #268): a per-secret random salt
 * and scrypt, stored as `scrypt$<16-byte hex salt>$<32-byte hex key>`. Higher
 * -entropy tokens (a device credential, a session token) are not hashed here;
 * their SHA-256 is enough and is looked up directly.
 *
 * Like tokens.js this knows nothing of what the secret protects, so any Module
 * may use it without `check-module-boundaries.js` objecting.
 */

const crypto = require('node:crypto');
const { promisify } = require('node:util');

const scrypt = promisify(crypto.scrypt);
const SCRYPT_KEY_LENGTH = 32;

async function hashSecret(secret) {
  const salt = crypto.randomBytes(16).toString('hex');
  const derived = await scrypt(String(secret), salt, SCRYPT_KEY_LENGTH);
  return `scrypt$${salt}$${derived.toString('hex')}`;
}

// Never throws on a bad `stored` value: a malformed, missing or truncated hash
// is simply "does not match", so a caller can treat it like a wrong secret.
async function verifySecret(secret, stored) {
  if (typeof stored !== 'string') return false;
  const [scheme, salt, expectedHex, ...rest] = stored.split('$');
  if (scheme !== 'scrypt' || !salt || !expectedHex || rest.length > 0) return false;
  if (!/^[0-9a-f]+$/i.test(expectedHex) || expectedHex.length !== SCRYPT_KEY_LENGTH * 2) return false;
  try {
    const derived = await scrypt(String(secret), salt, SCRYPT_KEY_LENGTH);
    const expected = Buffer.from(expectedHex, 'hex');
    return derived.length === expected.length && crypto.timingSafeEqual(derived, expected);
  } catch {
    return false;
  }
}

module.exports = { hashSecret, verifySecret };
