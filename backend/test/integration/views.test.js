/*
 * Every view in the baseline schema resolves.
 *
 * Like schema.test.js in this directory, this is a named exception to the
 * Platform's one test seam (HTTP against the running API — see issue #1's
 * Testing Decisions). It is allowed here only because there are no endpoints
 * over this schema yet; see schema.test.js's header for the full reasoning,
 * which applies equally to this file.
 *
 * What this asserts is deliberately shallow: that every view named in
 * `pg_views` can be selected from without erroring. It does not check any
 * view's arithmetic — no MTBF, no OEE, no cost roll-up — because none of that
 * is what issue #4 asks for ("every view resolves against the created
 * schema"), and pinning numbers against a hand-built plant is exactly the kind
 * of test that belongs with the Module that owns the view once it has routes
 * in front of it (there is prior art for that in
 * maintenance-management/backend/test/integration/views.test.js).
 *
 * View names are read from `pg_views` rather than hardcoded, so this test
 * does not go stale the moment a view is added, renamed or dropped — see
 * schema.test.js for the same reasoning applied to the catalogue.
 *
 * Needs a database with the baseline migration applied. Set DATABASE_URL
 * before running.
 */

const test = require('node:test');
const assert = require('node:assert');
const { getPool, closePool } = require('../../src/platform/db');

const pool = getPool();

test.after(async () => {
  await closePool();
});

// Rolled back at the end so this leaves nothing behind — see schema.test.js.
// Nothing in this file writes, but SELECT * FROM <view> still needs to run
// against a real connection, and a shared transaction keeps this file
// consistent with the rest of the suite rather than for any correctness
// reason of its own.
async function withRollback(fn) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await fn(client);
  } finally {
    await client.query('ROLLBACK');
    client.release();
  }
}

test('every view resolves against the created schema', async () => {
  await withRollback(async (client) => {
    const { rows: views } = await client.query(
      `SELECT viewname FROM pg_views WHERE schemaname = 'public' ORDER BY viewname`
    );

    // If this enumeration ever came back empty, the loop below would pass
    // vacuously and the test would prove nothing. The baseline defines over
    // twenty views, so an empty result here means the query is broken, not
    // that the schema has none.
    assert.ok(views.length > 0, 'expected pg_views to list at least one view');

    for (const { viewname } of views) {
      await assert.doesNotReject(
        () => client.query(`SELECT * FROM ${viewname} WHERE false`),
        `expected ${viewname} to resolve`
      );
    }
  });
});
