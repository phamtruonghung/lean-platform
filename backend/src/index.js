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
const quality = require('./modules/quality');
const safety = require('./modules/safety');

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
// The tier board's KPI registry (issue #202)
// ---------------------------------------------------------------------------
// Assembled here, where the application composes its Modules, so that no
// Module has to know about another to put a number on the board. Each Module's
// entry point contributes its own entries — a KPI code mapped to how that
// number is read out of the Module's own records (the entry shape is in
// maintenance/kpi-registry.js's header) — and this is the one place they meet.
// The board's own code knows no KPI by name: it computes whatever this registry
// names and reports `no_data` for everything else, which is still most of the
// catalogue: Safety and People record no work yet, and the Quality and Delivery
// KPIs that would need quantity produced have no Production Module to count it.
//
// Adding a Module's KPIs is one spread below and nothing else: no file in
// another Module changes, and no Module requires another (ADR-0006). A KPI
// code belongs to exactly one Module; the spread order is the tie-break if two
// ever collide, and a collision is a mistake in the contributions rather than
// something this file can resolve meaningfully.
const kpiRegistry = {
  ...maintenance.kpiRegistry,
  // Quality's own (issue #216): open Non-conformances, overdue CAPAs, the
  // complaints received in the period and the cost of poor quality, each read
  // from this Module's records — quality/kpi-registry.js argues the entries and
  // what it deliberately leaves reporting `no_data`.
  ...quality.kpiRegistry,
  // Safety's own (issue #232, parent #223 decisions 3 and 5): incidents that
  // caused something, near misses reported and observations logged, each read
  // from this Module's records — safety/kpi-registry.js argues the entries,
  // the departure from a seeded formula, and why SAF_TRIR/SAF_LTIFR stay
  // reporting `no_data`.
  ...safety.kpiRegistry
};

// ---------------------------------------------------------------------------
// API
// ---------------------------------------------------------------------------
// The frontend and the API are served from one hostname by the reverse proxy,
// so the browser calls /api/... relatively and there is no CORS to configure.
// That is why no CORS middleware appears here: its absence is the design, not
// an omission (ADR-0002).
app.use('/api', healthRoutes);
app.use('/api/people', people.router);
// The shared floor device's own addresses — register it, set an Employee's
// floor PIN, exchange them for an identification — are People's routes since
// issue #201, but they stay mounted under `/api/maintenance`, which is where a
// deployed device has always called them and where the frontend still calls
// them. The prefix is an address kept, not a claim about which Module owns the
// route: people/floor-routes.js's own header says so, and folding the router
// into `people.router` instead would have moved every device's URL for no gain
// a device can see. This file is where the application composes its Modules,
// so the mount is written here rather than hidden inside maintenance's router.
app.use('/api/maintenance', people.floorRouter);
app.use('/api/maintenance', maintenance.router);
// Mounted beside the Module's other routes, but created with the assembled
// registry above: the board route is the one thing that has to be handed it,
// which is why it is a factory rather than a file inside `maintenance.router`
// (see maintenance/index.js and board-routes.js). Its address is unchanged.
app.use('/api/maintenance', maintenance.createBoardRouter(kpiRegistry));
app.use('/api/actions', actions.router);
// The Quality Module's own prefix (issue #203): the Product catalogue and the
// Defect code tree today, and whatever else this Module owns as its slices
// land. A prefix of its own rather than a corner of another Module's — the two
// catalogues are shared by every Site (ADR-0005) and belong to no Org Unit, so
// neither `/api/people` nor `/api/maintenance` is their address. Its router is
// mounted here, where the application composes its Modules, and it carries its
// own copy of the administrator check (quality/index.js's own header).
app.use('/api/quality', quality.router);
// The Safety Module's own prefix (issue #226): the first Safety incidents,
// today, and whatever else this Module owns as its later slices land — the
// same reasoning `/api/quality`'s own comment gives, and it is mounted here,
// where the application composes its Modules, for the same reason.
app.use('/api/safety', safety.router);

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
