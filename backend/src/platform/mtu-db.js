/*
 * The Platform's connection to its second database: `mtu`, schema `kpi`, the
 * MTU KPI catalogue (ADR-0055).
 *
 * The Platform is one application over one database (ADR-0001, ADR-0006), and
 * this file is the one deliberate exception to that sentence. The catalogue it
 * reaches — the KPIs the MTU line is reviewed against, their Targets and the
 * daily Review — is shared with Power BI, which reads the same tables from
 * another host on the plant LAN; keeping a copy of it inside the Platform's own
 * database would be a second list Power BI never sees (ADR-0055 rejects exactly
 * that). So the data stays where it is and the Platform reads and appends to it
 * in place, as `lean_app`: SELECT everywhere, and three column-level INSERTs,
 * no UPDATE and no DELETE.
 *
 * It is a Pool of its own, not a second schema on `db.js`'s, because
 * everything that makes a Pool one thing differs: the credentials (a different
 * role on a different server), the host (a different machine, reached over the
 * plant LAN) and the failure mode (that machine can be down while the Platform's
 * own database is fine, and the other way round). Sharing a Pool would let a
 * slow catalogue query use up connections the rest of the API needs. Modules are
 * code seams, not data seams (ADR-0006); this is a data seam, and it earns the
 * one extra file by being drawn here, in the foundation, and nowhere else.
 *
 * It is optional. `MTU_DATABASE_URL` unset means the catalogue is not set up on
 * this deployment, and every `/api/kpi/*` route then answers 503 (the Module's
 * own guard) instead of the process refusing to boot: an API that will not start
 * because an optional catalogue is missing would take People and Maintenance
 * down with it. For the same reason creation is lazy — requiring this file
 * never connects and never throws — and `isMtuConfigured()` is how the health
 * endpoint and the Module ask the question without creating a Pool.
 *
 * `statement_timeout` is set here, and not on `db.js`'s Pool, because this
 * server is a second host on the plant LAN. It is enforced by the server, so it
 * ends a query that runs too long (a slow plan, a lock held elsewhere) and
 * a request is not held open behind it. It does not cover the host or the
 * network dying mid-query — a switch port flapping, the machine losing power:
 * the server is then not there to enforce anything, and the client waits on
 * the TCP connection until the operating system gives up. That is a known
 * limit, not handled here. `connectionTimeoutMillis` covers a host that will
 * not answer a new connection at all. Ten seconds is generous for a catalogue
 * of nineteen rows.
 */

const { Pool } = require('pg');
const { log } = require('./log');

// Created lazily, for the same reason db.js's is: requiring this file must
// never throw or connect.
let pool = null;

function isMtuConfigured() {
  return Boolean(process.env.MTU_DATABASE_URL);
}

function getMtuPool() {
  if (!pool) {
    if (!isMtuConfigured()) {
      throw new Error('MTU_DATABASE_URL is not set. See .env.example.');
    }

    pool = new Pool({
      connectionString: process.env.MTU_DATABASE_URL,
      max: 5,
      idleTimeoutMillis: 30000,
      // Fail a stuck connection attempt rather than hanging a request forever.
      connectionTimeoutMillis: 5000,
      // A hung query on the second host must not hold a request open.
      statement_timeout: 10000
    });

    // A pool error with no listener would crash the process.
    pool.on('error', (error) => {
      log('error', 'idle mtu database client error', { err: error.message });
    });
  }

  return pool;
}

async function closeMtuPool() {
  if (pool) {
    await pool.end();
    pool = null;
  }
}

module.exports = { isMtuConfigured, getMtuPool, closeMtuPool };
