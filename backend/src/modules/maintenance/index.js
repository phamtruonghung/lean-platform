/*
 * The Maintenance Module's entry point (ADR-0006) — the second Module in this
 * backend, after People.
 *
 * Three exports, and each is here because something outside this Module
 * mounts it or asks for it.
 *
 * `router` is this Module's own routes, mounted by src/index.js, which lives
 * outside `modules/` and is not a cross-Module caller the boundary checker
 * even looks at. Like every Module's `router` it is a special case of none of
 * ADR-0006's three clauses — it is how the Module becomes reachable over HTTP
 * at all. What it deliberately does NOT carry is the tier board's route.
 *
 * `createBoardRouter(kpiRegistry)` is that route, as a factory rather than a
 * file inside `router`, and issue #202 is why: the tier board's registry of
 * computable KPIs is no longer this Module's private constant. Each Module
 * contributes its own registry entries through its entry point, the
 * application assembles them where it composes its Modules (src/index.js), and
 * the board route is the one thing that must be handed the assembled result.
 * It is the same mount-target special case `router` is — nothing calls it but
 * src/index.js — it simply takes the registry as an argument, so `router`
 * keeps working for every other route without a registry threaded through it.
 * src/index.js mounts both at `/api/maintenance`; see that file's own comment
 * and board-routes.js's header.
 *
 * `kpiRegistry` is this Module's contribution to that registry (issue #202):
 * the eight maintenance KPIs, each KPI code mapped to how its number is read
 * out of the baseline's own reporting view. See kpi-registry.js's header for
 * the entry shape and why it is an explicit mapping rather than a general SQL
 * engine. It is the one export that is neither a mount target nor a lookup,
 * and it is worth saying plainly why it belongs here anyway: it is read-only
 * data describing how to compute numbers from records this Module owns, so
 * nothing throws across the boundary and no caller controls any flow through
 * it — the intent behind ADR-0006's first two clauses — and it is domain
 * (Maintenance's own measurements, not a generic helper), which is the third.
 * A second Module's contribution is its own file exported the same way;
 * src/index.js spreads them together, so no Module ever requires another to
 * put a number on the board.
 *
 * floor-routes.js is the one file here whose subject another Module owns part
 * of: since issue #201 the shared floor device and the identification an
 * Employee presents on it are People's records, so this Module keeps only its
 * own floor READ (`GET /floor/work-orders`, which is about Work orders) and
 * asks People who the device is through that Module's entry point. The
 * device's other three addresses are People's routes, mounted at this same
 * `/api/maintenance` prefix by src/index.js because that is the frozen address
 * deployed devices call — the prefix is kept, not claimed.
 *
 * Everything else — #57 work orders, #61 nesting and retiring, #62 assignment,
 * #63 the transitions, #75 cost, #79 meter readings — is this Module's own
 * files reaching assets.js/work-orders.js directly, the way People's own
 * routes reach plant.js. Nothing about them belongs here.
 */

const express = require('express');
const assetRoutes = require('./asset-routes');
const workOrderRoutes = require('./work-order-routes');
const requestRoutes = require('./request-routes');
const downtimeRoutes = require('./downtime-routes');
const jobPlanRoutes = require('./job-plan-routes');
const pmScheduleRoutes = require('./pm-schedule-routes');
const meterRoutes = require('./meter-routes');
const inventoryRoutes = require('./inventory-routes');
const createBoardRouter = require('./board-routes');
const kpiRegistry = require('./kpi-registry');
const floorRoutes = require('./floor-routes');

const router = express.Router();
router.use(assetRoutes);
router.use(workOrderRoutes);
router.use(requestRoutes);
router.use(downtimeRoutes);
router.use(jobPlanRoutes);
router.use(pmScheduleRoutes);
router.use(meterRoutes);
router.use(inventoryRoutes);
router.use(floorRoutes);

module.exports = {
  router,
  createBoardRouter,
  kpiRegistry
};
