/*
 * The Platform's connection to Postgres.
 *
 * The database is Supabase Cloud (ADR-0002) and the API reaches it as
 * `postgres`, the role that ran the baseline and every migration since — it
 * owns every table in this schema and holds `rolbypassrls = true`, which is
 * what actually lets it keep reading and writing under the deny-all RLS
 * floor (ADR-0004), not any "service role": Supabase's `service_role` is
 * `NOLOGIN` and exists as a PostgREST-level JWT claim, not a Postgres login
 * role a connection string could ever authenticate as. See
 * migrations/1756000000002_deny-all-rls.js's own file header for the same
 * fact, stated where the RLS floor itself is defined. Nothing here creates
 * schema: the schema is owned by migrations and applied as a deploy step
 * before a new version takes traffic, so that a failed migration fails the
 * deploy instead of leaving a running API in front of a database it does not
 * understand.
 *
 * There is deliberately no type parser here yet. How BIGINT and NUMERIC come
 * back across the wire is a real decision — a JavaScript Number cannot hold
 * every int64, and NUMERIC(18,4) does not fit a double at all — but it is a
 * decision about a schema that does not exist until the baseline lands. Making
 * it now would mean choosing on behalf of tables nobody has seen.
 */

const { Pool } = require('pg');
const { log } = require('./log');

// Created lazily rather than at import time. Throwing while the module is being
// required produces a stack trace with no useful context, and it also stops
// tooling from importing anything else in this file.
let pool = null;

function getPool() {
  if (!pool) {
    if (!process.env.DATABASE_URL) {
      throw new Error('DATABASE_URL is not set. See .env.example.');
    }

    pool = new Pool({
      connectionString: process.env.DATABASE_URL,
      max: 10,
      idleTimeoutMillis: 30000,
      // Fail a stuck connection attempt rather than hanging a request forever.
      connectionTimeoutMillis: 5000
    });

    // A pool error with no listener would crash the process.
    pool.on('error', (error) => {
      log('error', 'idle database client error', { err: error.message });
    });
  }

  return pool;
}

async function closePool() {
  if (pool) {
    await pool.end();
    pool = null;
  }
}

// Runs `fn` inside one transaction, with the audit actor set transaction
// -locally first — `SET LOCAL`, not a plain session `SET`, because this pool
// (and Supabase's own transaction-mode pooler in production, per ADR-0002's
// Consequences) hands the same physical connection to different requests
// between transactions. A session-level setting would leak into whichever
// request happens to reuse the connection next and misattribute its writes;
// `SET LOCAL` is scoped to this transaction alone and is cleared automatically
// at COMMIT/ROLLBACK. The schema's audit triggers (`audit_row_change()`,
// `set_actor_columns()`, both in the baseline) read exactly this setting —
// `current_setting('app.user_id', true)` — to fill `audit_log.changed_by` and
// each table's `created_by`/`updated_by`.
//
// `SET LOCAL app.user_id = $1` is not itself parameterizable — `SET` does not
// accept a bind parameter — so this goes through `set_config()`, the
// documented function form: `set_config('app.user_id', value, true)` is
// exactly `SET LOCAL app.user_id = value` with `true` meaning "local to this
// transaction", but as an ordinary function call any driver can parameterize
// safely.
//
// `accountId` may be null — a caller with no acting Account yet (the request
// that creates its own Account has no one to record as its author) simply
// runs the transaction without ever calling `set_config`, and the audit
// triggers' own `NULLIF(current_setting(...), '')::BIGINT` reads that as
// "no actor", which is the honest answer, not a guess.
async function withActor(accountId, fn) {
  const client = await getPool().connect();
  try {
    await client.query('BEGIN');
    if (accountId != null) {
      await client.query("SELECT set_config('app.user_id', $1, true)", [String(accountId)]);
    }
    const result = await fn(client);
    await client.query('COMMIT');
    return result;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

module.exports = { getPool, closePool, withActor };
