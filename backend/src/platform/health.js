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

// Set once SIGTERM has arrived. Readiness reports it before consulting the
// database, so the proxy can stop routing here while in-flight requests finish.
let shuttingDown = false;

function beginShutdown() {
  shuttingDown = true;
}

function isShuttingDown() {
  return shuttingDown;
}

// Liveness and readiness are mounted at the root rather than under /api,
// because they are the deployment's business and not the API's. Keeping them
// off /api also keeps probe traffic clear of anything mounted there later.
function mountProbes(app) {
  app.get('/healthz', (_req, res) => {
    res.json({ status: 'ok' });
  });

  app.get('/readyz', async (_req, res) => {
    if (shuttingDown) {
      return res.status(503).json({ status: 'error', message: 'shutting down' });
    }

    try {
      await getPool().query('SELECT 1');
      return res.json({ status: 'ok', database: 'connected' });
    } catch (error) {
      log('error', 'readiness check failed', { err: error.message });
      return res.status(503).json({ status: 'error', message: 'database unavailable' });
    }
  });
}

const router = express.Router();

router.get('/health', async (_req, res) => {
  try {
    // The value is round-tripped through Postgres on purpose. A health check
    // that only proves a query did not throw would still pass against a
    // database returning nothing useful; carrying a value back proves the
    // whole path end to end, which is the one thing this endpoint is for.
    const result = await getPool().query('SELECT 1 AS answer');
    return res.json({
      status: 'ok',
      database: 'connected',
      answer: result.rows[0].answer
    });
  } catch (error) {
    log('error', 'api health check failed', { err: error.message });
    return res.status(503).json({ status: 'error', database: 'unavailable' });
  }
});

module.exports = { router, mountProbes, beginShutdown, isShuttingDown };
