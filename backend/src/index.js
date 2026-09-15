/*
 * The Platform API.
 *
 * One application over one database, serving several plants. Modules — People,
 * and later Maintenance and the Tier Board — are folders under src/modules,
 * each owning its own routes and services. A Module never reaches into another
 * Module's internals; it calls that Module's service (ADR-0006). The rule is a
 * convention, so `npm run lint` enforces it rather than leaving it to review.
 *
 * Everything shared sits under src/platform: it is infrastructure the Modules
 * stand on, not a Module of its own.
 */

require('dotenv').config();

const express = require('express');
const { closePool } = require('./platform/db');
const { log } = require('./platform/log');
const health = require('./platform/health');
const lifecycle = require('./platform/lifecycle');
const people = require('./modules/people');
const maintenance = require('./modules/maintenance');
const actions = require('./modules/actions');

const app = express();
const port = Number(process.env.BACKEND_PORT || process.env.PORT || 8000);

// Requests arrive through a reverse proxy, which sets X-Forwarded-For. Without
// this, Express reports the proxy's address as the client's.
app.set('trust proxy', 1);

app.use(express.json({ limit: '100kb' }));

// Probes are mounted first, so nothing added later can intercept them. The same
// call returns the API's own health router.
const healthRoutes = health.mount(app);

// ---------------------------------------------------------------------------
// API
// ---------------------------------------------------------------------------
// The frontend and the API are served from one hostname by the reverse proxy,
// so the browser calls /api/... relatively and there is no CORS to configure.
// That is why no CORS middleware appears here: its absence is the design, not
// an omission (ADR-0002).
app.use('/api', healthRoutes);
app.use('/api/people', people.router);
app.use('/api/maintenance', maintenance.router);
app.use('/api/actions', actions.router);

// An unknown path under /api answers in JSON. Express's default 404 is an HTML
// page, which a client that asked for JSON cannot parse — so a typo in a URL
// would surface to the caller as a parse error rather than as a 404.
app.use('/api', (_req, res) => {
  res.status(404).json({ message: 'No such endpoint' });
});

// A single terminal handler, so a thrown error becomes a 500 with a logged
// cause rather than a hung request. The message is never echoed to the client:
// a database error string names tables and columns.
// eslint-disable-next-line no-unused-vars
app.use((error, _req, res, _next) => {
  log('error', 'unhandled request error', { err: error.message, stack: error.stack });
  res.status(500).json({ message: 'Internal server error' });
});

const server = app.listen(port, '0.0.0.0', () => {
  log('info', 'listening', { port: server.address().port });
});

// ---------------------------------------------------------------------------
// Shutdown
// ---------------------------------------------------------------------------
// A deploy replaces this container. Handling SIGTERM is what makes that
// invisible to whoever is using the app: in-flight requests finish instead of
// being cut off mid-response.
function shutdown(signal) {
  if (lifecycle.isShuttingDown()) return;
  lifecycle.beginShutdown();
  log('info', 'shutting down', { signal });

  // fetch() and most clients hold the connection open. Without this, close()
  // waits for every idle keep-alive socket to time out on its own, and the
  // process sits there long after it has stopped being useful.
  server.closeIdleConnections?.();

  server.close(async () => {
    try {
      await closePool();
    } catch (error) {
      log('error', 'failed to close cleanly', { err: error.message });
    }
    process.exit(0);
  });

  // If connections are still open after 25 seconds, stop waiting and exit on
  // our own terms rather than being killed halfway through closing the pool.
  setTimeout(() => {
    log('error', 'shutdown timed out, exiting');
    process.exit(1);
  }, 25000).unref();
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

module.exports = { app, server };
