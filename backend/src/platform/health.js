/*
 * Health, in three endpoints, for three different questions.
 *
 * Liveness and readiness are deliberately split. Liveness answers "is this
 * process alive?" and must not touch the database: a liveness check that
 * queries Postgres turns a brief database hiccup into a restart, which is far
 * worse than the hiccup. Readiness answers "can this instance serve traffic
 * right now?", so it does check.
 *
 * `/api/health` is the third: the one a client calls. It is what the Flutter
 * app asks in order to show that the whole path — browser, reverse proxy, API,
 * database — is connected, so it reports what the database actually returned
 * rather than merely that a query succeeded.
 */

const express = require('express');
const { getPool } = require('./db');
const { log } = require('./log');
const { isShuttingDown } = require('./lifecycle');

// Round-trips a value through Postgres. Returning the value rather than a
// boolean is the point: a check that only proves a query did not throw would
// still pass against a database returning nothing useful.
async function askDatabase() {
  const result = await getPool().query('SELECT 1 AS answer');
  return result.rows[0].answer;
}

// Everything health serves, mounted in one call so there is one idiom rather
// than two. The probes sit at the root because they are the deployment's
// business, not the API's; keeping them off /api also keeps probe traffic clear
// of anything mounted there later.
function mount(app) {
  app.get('/healthz', (_req, res) => {
    res.json({ status: 'ok' });
  });

  app.get('/readyz', async (_req, res) => {
    // Reported before the database is consulted. Once SIGTERM has arrived this
    // process is going away, and saying so immediately is what lets the proxy
    // stop routing here before the listener actually closes.
    if (isShuttingDown()) {
      return res.status(503).json({ status: 'error', message: 'shutting down' });
    }

    try {
      await askDatabase();
      return res.json({ status: 'ok', database: 'connected' });
    } catch (error) {
      log('error', 'readiness check failed', { err: error.message });
      return res.status(503).json({ status: 'error', message: 'database unavailable' });
    }
  });

  const api = express.Router();

  api.get('/health', async (_req, res) => {
    try {
      const answer = await askDatabase();
      return res.json({ status: 'ok', database: 'connected', answer });
    } catch (error) {
      log('error', 'api health check failed', { err: error.message });
      return res.status(503).json({ status: 'error', database: 'unavailable' });
    }
  });

  return api;
}

module.exports = { mount };
