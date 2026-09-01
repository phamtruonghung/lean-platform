/*
 * The Platform's connection to Postgres.
 *
 * The database is Supabase Cloud (ADR-0002) and the API reaches it with the
 * service role, because the API owns every write and the database itself is a
 * deny-all floor (ADR-0004). Nothing here creates schema: the schema is owned
 * by migrations and applied as a deploy step before a new version takes
 * traffic, so that a failed migration fails the deploy instead of leaving a
 * running API in front of a database it does not understand.
 */

const { Pool, types } = require('pg');
const { log } = require('./log');

// BIGINT columns (OID 20) come back from node-postgres as strings, because a
// JavaScript Number cannot hold every int64 value safely. The inherited schema
// uses `BIGINT GENERATED ALWAYS AS IDENTITY` for every primary key, so without
// this every id in an API response would be a string. Parsing int8 keeps one
// shape across every table.
types.setTypeParser(20, (value) => parseInt(value, 10));

// NUMERIC (OID 1700) is deliberately left alone. It is also returned as a
// string, and with better cause: NUMERIC(18,4) does not fit a double. Rounding
// money through a float to save the caller a parse is not a trade worth making.

// Accept either a single connection string or the discrete variables. Supabase
// hands out a connection string; Compose finds the discrete ones easier to pass.
function buildPoolConfig() {
  if (process.env.DATABASE_URL) {
    return { connectionString: process.env.DATABASE_URL };
  }

  if (!process.env.POSTGRES_PASSWORD) {
    throw new Error(
      'Database configuration missing: set DATABASE_URL, or POSTGRES_PASSWORD ' +
        'together with POSTGRES_HOST, POSTGRES_USER and POSTGRES_DB.'
    );
  }

  return {
    user: process.env.POSTGRES_USER || 'platform',
    password: process.env.POSTGRES_PASSWORD,
    host: process.env.POSTGRES_HOST || 'localhost',
    port: Number(process.env.POSTGRES_PORT || 5432),
    database: process.env.POSTGRES_DB || 'platform'
  };
}

// Created lazily rather than at import time. Throwing while the module is being
// required produces a stack trace with no useful context, and it also stops
// tooling from importing anything else in this file.
let pool = null;

function getPool() {
  if (!pool) {
    pool = new Pool({
      ...buildPoolConfig(),
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
