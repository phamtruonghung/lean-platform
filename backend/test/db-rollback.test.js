/*
 * withActor's failure path: when ROLLBACK itself fails (a dead connection),
 * the caller still sees the original error, and the client is released with
 * that failure so the pool discards it rather than reusing it. No database
 * needed — the pool's connect() is replaced with a scripted fake client.
 */

const test = require('node:test');
const assert = require('node:assert');

process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgresql://x:y@127.0.0.1:1/z';

const pg = require('pg');
const db = require('../src/platform/db');

function fakeClient(releases, { failRollback }) {
  return {
    async query(sql) {
      if (sql === 'ROLLBACK' && failRollback) throw new Error('connection terminated');
      return { rows: [] };
    },
    release(arg) {
      releases.push(arg);
    }
  };
}

async function runWith(client) {
  const original = pg.Pool.prototype.connect;
  pg.Pool.prototype.connect = async () => client;
  try {
    return await db.withActor(null, async () => {
      throw new Error('original failure');
    });
  } finally {
    pg.Pool.prototype.connect = original;
  }
}

test('a failed ROLLBACK rethrows the original error and releases the client as broken', async () => {
  const releases = [];
  await assert.rejects(runWith(fakeClient(releases, { failRollback: true })), /original failure/);
  assert.strictEqual(releases.length, 1);
  assert.ok(releases[0] instanceof Error, 'release() must receive the rollback error');
  assert.match(releases[0].message, /connection terminated/);
});

test('a successful ROLLBACK releases the client normally', async () => {
  const releases = [];
  await assert.rejects(runWith(fakeClient(releases, { failRollback: false })), /original failure/);
  assert.deepStrictEqual(releases, [undefined]);
});

test.after(async () => {
  await db.closePool();
});
