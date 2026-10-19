/*
 * A throttle on password sign-in (review finding: POST /api/auth/login had no
 * limit). Every attempt costs one scrypt verification, so unlimited attempts
 * allow online guessing and can saturate the libuv thread pool that scrypt
 * runs on. Two keys are counted, per client address and per email, because
 * each covers what the other cannot: the address limit stops one machine
 * trying many emails, the email limit stops many machines trying one Account.
 *
 * ## Shape
 *
 * An attempt is counted when it STARTS (`begin`), not when it fails, so a
 * burst of parallel requests cannot all pass a check made before any of them
 * has finished. A success gives the attempt back (`succeeded`): the email's
 * counter is cleared, and the address's is lowered by one, so a person who
 * mistyped twice and then got in is not penalised, while an attacker holding
 * one valid Account cannot keep wiping the address counter between guesses.
 *
 * Once a key has counted its maximum, further attempts are refused with 429
 * and Retry-After WITHOUT running scrypt. When the pause ends the next
 * attempt is counted again, and if it fails the pause doubles (BASE_MS * 2^n,
 * capped at WINDOW_MS). A key with no activity for WINDOW_MS is forgotten.
 *
 * ## Limits of this design
 *
 * State is in this process: right for the single backend instance this is
 * deployed as, wrong the day a second one runs (each would count alone). A
 * lockout per email lets someone who knows an address keep that person out for
 * the length of the pause; that is the price of an email limit without a
 * second factor, and the pause is capped. The client address is `req.ip`,
 * which `trust proxy` (src/index.js) resolves to the address Caddy saw.
 *
 * Tunable by environment, read on every call like AUTH_PASSWORD_MODE:
 * LOGIN_THROTTLE_WINDOW_MS, LOGIN_THROTTLE_EMAIL_MAX, LOGIN_THROTTLE_IP_MAX,
 * LOGIN_THROTTLE_BASE_MS.
 */

const { httpError } = require('./errors');

const MAX_TRACKED_KEYS = 10000;
const entries = new Map();

function number(name, fallback) {
  const value = Number(process.env[name]);
  return Number.isFinite(value) && value > 0 ? value : fallback;
}

function settings() {
  return {
    windowMs: number('LOGIN_THROTTLE_WINDOW_MS', 15 * 60 * 1000),
    emailMax: number('LOGIN_THROTTLE_EMAIL_MAX', 5),
    ipMax: number('LOGIN_THROTTLE_IP_MAX', 20),
    baseMs: number('LOGIN_THROTTLE_BASE_MS', 30 * 1000)
  };
}

function sweep(now, windowMs) {
  for (const [key, entry] of entries) {
    if (entry.blockedUntil <= now && now - entry.lastAt > windowMs) entries.delete(key);
  }
}

function liveEntry(key, now, windowMs) {
  const entry = entries.get(key);
  if (!entry) return null;
  if (entry.blockedUntil <= now && now - entry.lastAt > windowMs) {
    entries.delete(key);
    return null;
  }
  return entry;
}

function count(key, max, now, { windowMs, baseMs }) {
  let entry = liveEntry(key, now, windowMs);
  if (!entry) {
    if (entries.size >= MAX_TRACKED_KEYS) sweep(now, windowMs);
    entry = { failures: 0, lastAt: now, blockedUntil: 0 };
    entries.set(key, entry);
  }
  entry.failures += 1;
  entry.lastAt = now;
  if (entry.failures >= max) {
    const pause = Math.min(windowMs, baseMs * 2 ** (entry.failures - max));
    entry.blockedUntil = now + pause;
  }
}

function keysFor(ip, email) {
  const normalised = typeof email === 'string' && email.trim() !== '' ? email.trim().toLowerCase() : null;
  return {
    ipKey: `ip:${ip ?? 'unknown'}`,
    emailKey: normalised ? `email:${normalised}` : null
  };
}

// Throws a 429 carrying `retryAfterSeconds` if either key is paused; otherwise
// counts this attempt against both.
function begin({ ip, email }, now = Date.now()) {
  const config = settings();
  const { ipKey, emailKey } = keysFor(ip, email);

  let until = 0;
  for (const key of [ipKey, emailKey]) {
    const entry = key && liveEntry(key, now, config.windowMs);
    if (entry && entry.blockedUntil > now) until = Math.max(until, entry.blockedUntil);
  }
  if (until > now) {
    const error = httpError(429, 'Too many sign-in attempts. Try again later.');
    error.retryAfterSeconds = Math.max(1, Math.ceil((until - now) / 1000));
    throw error;
  }

  count(ipKey, config.ipMax, now, config);
  if (emailKey) count(emailKey, config.emailMax, now, config);
}

function succeeded({ ip, email }) {
  const { ipKey, emailKey } = keysFor(ip, email);
  if (emailKey) entries.delete(emailKey);
  const entry = entries.get(ipKey);
  if (entry) {
    entry.failures = Math.max(0, entry.failures - 1);
    if (entry.failures === 0) entries.delete(ipKey);
  }
}

module.exports = { begin, succeeded };
