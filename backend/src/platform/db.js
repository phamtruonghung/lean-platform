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

module.exports = { getPool, closePool };
