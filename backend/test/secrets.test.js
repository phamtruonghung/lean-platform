/*
 * platform/secrets.js: the one scrypt scheme the floor PIN and an Account's
 * password share (issue #268). Pure; needs no database.
 */

const test = require('node:test');
const assert = require('node:assert');
const { hashSecret, verifySecret } = require('../src/platform/secrets');

test('a secret verifies against its own hash', async () => {
  const stored = await hashSecret('correct horse');
  assert.strictEqual(await verifySecret('correct horse', stored), true);
});

test('a different secret does not verify', async () => {
  const stored = await hashSecret('correct horse');
  assert.strictEqual(await verifySecret('battery staple', stored), false);
});

test('the stored form is scrypt$<16-byte hex salt>$<32-byte hex key>', async () => {
  const stored = await hashSecret('1234');
  assert.match(stored, /^scrypt\$[0-9a-f]{32}\$[0-9a-f]{64}$/);
});

test('hashing the same secret twice uses distinct salts', async () => {
  const [a, b] = [await hashSecret('1234'), await hashSecret('1234')];
  assert.notStrictEqual(a, b);
  assert.strictEqual(await verifySecret('1234', a), true);
  assert.strictEqual(await verifySecret('1234', b), true);
});

test('a malformed stored value is false, never a throw', async () => {
  const good = await hashSecret('x');
  const [, salt, key] = good.split('$');
  const malformed = [
    null,
    undefined,
    '',
    42,
    'plaintext',
    'scrypt$',
    `scrypt$${salt}`,
    `bcrypt$${salt}$${key}`,
    `scrypt$${salt}$${key.slice(2)}`,
    `scrypt$${salt}$${'zz'.repeat(32)}`,
    `scrypt$${salt}$${key}$extra`,
    `scrypt$$${key}`
  ];
  for (const stored of malformed) {
    assert.strictEqual(await verifySecret('x', stored), false, `stored: ${String(stored)}`);
  }
});
