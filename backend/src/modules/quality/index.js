/*
 * The Quality Module's entry point (ADR-0006) — the fourth Module in this
 * backend, after People, Maintenance and Actions, and the one issue #203
 * creates.
 *
 * Two exports, and neither is a lookup: `router` is here because something
 * outside this Module mounts it, and `kpiRegistry` because something outside
 * this Module publishes it.
 *
 * `router` is this Module's own routes — the Product catalogue, the Defect
 * code tree, the Non-conformance log and the floor device's own door to
 * recording one, the Customer list and the Customer complaints a customer's
 * word becomes (issue #214), and the Supplier list and the supplier NCRs an
 * incoming lot becomes (issue #215), as they stand today — mounted by
 * src/index.js under
 * `/api/quality`, a prefix of this Module's own beside
 * `/api/people`, `/api/maintenance` and `/api/actions`. src/index.js lives
 * outside `modules/` and is not a cross-Module caller the boundary checker
 * looks at, so like every Module's `router` it is a special case of none of
 * ADR-0006's three clauses: it is how the Module becomes reachable over HTTP
 * at all.
 *
 * `kpiRegistry` is this Module's contribution to the tier board (issue #216),
 * read from quality/kpi-registry.js's own header, which argues each entry and
 * each deliberate absence. It is an export rather than a route because that is
 * what issue #202's composition needs: src/index.js spreads every Module's
 * contribution into one registry and hands it to the board's own route, so no
 * Module has to know about another. ADR-0006 allows it — it is read-only data
 * about records this Module owns, a value rather than a command, and domain
 * rather than utility.
 *
 * Nothing else is exported, and each absence is a decision rather than an
 * omission:
 *
 *   - No lookup about a Product or a Defect code is offered to another Module.
 *     Nothing outside Quality asks one today, and as of issue #205 nothing
 *     inside Quality needs one *across a boundary* either: the
 *     Non-conformance slice resolves its Product, its Defect code and its
 *     optional Asset in its own service, by ordinary SQL against rows this
 *     Modules shares a database with (ADR-0006's "code seams, not data
 *     seams"). A sibling Module that needs Quality's own judgment about a
 *     Product or a Non-conformance adds the question here at that point, which
 *     is what ADR-0006's "What a Module's entry point may expose" section
 *     anticipates and what people-entry-point.test.js's own header describes
 *     as cheap on the way in and expensive on the way out.
 *   - No route for the board. The board is Maintenance's address (`GET
 *     /api/maintenance/sites/:siteId/board`) and stays there: this Module
 *     contributes numbers into a registry the board reads, never a second
 *     board of its own. Its own KPIs need no endpoint — they are read through
 *     the one the Platform already has, with no change to that request or
 *     response.
 *   - No error plumbing and no SQL helpers. errors.js is this Module's own
 *     copy (ADR-0006's third clause, "domain, not utility" — see its header),
 *     and products.js/defect-codes.js/nonconformances.js each keep their own
 *     private helpers rather than sharing them through this file.
 *
 * What this Module requires from outside itself is People's entry point and
 * nothing else (issue #203's own acceptance criterion, and what
 * `npm run lint`'s boundary checker enforces): product-routes.js and
 * defect-code-routes.js ask `people.authenticate` and `people.requireActive`
 * and carry their own copy of the administrator check, since People
 * deliberately does not export `requireAdmin`; nonconformance-routes.js asks
 * the same two plus `findSite`, `findOrgUnit`, `canAct` and `canSeeSite`, the
 * Grant questions issue #205 needs (any Grant on any Org Unit of the Site to
 * read one, a write Grant reaching a Non-conformance's own Org Unit to record
 * or change it). customer-routes.js and customer-complaint-routes.js (issue
 * #214) ask the same set as those two — the administrator check for the
 * Customer list's writes, and the Site and Grant questions for a complaint's
 * register and its own record. supplier-routes.js and supplier-ncr-routes.js
 * (issue #215) ask that same set again for the Supplier list's writes and for a
 * supplier NCR's register, its own record and its four writes — which is the
 * whole of what a second outward-facing slice costs this Module in coupling:
 * one more pair of files asking the questions People already answers.
 * `modules/people/authorization.js` already answers the
 * Quality question this Module's later slices need
 * (`canAct({ quality: true })`, issue #204, ADR-0035) — that is People's
 * export, reached through People's entry point, not something re-exported
 * here, and issue #206 is the slice that consults it: the Concession, the
 * lowered severity, the reopen and the cancel are its four gated acts.
 * floor-routes.js (issue #207) asks the same entry point for the three
 * questions a shared device's own door needs — `findDeviceByCredential`,
 * `findValidIdentification` and `deviceReachesOrgUnit`, plus `findOrgUnit` for
 * the Org Unit the record is filed at — exactly as maintenance's floor writes
 * and its floor read already do.
 */

const express = require('express');
const productRoutes = require('./product-routes');
const defectCodeRoutes = require('./defect-code-routes');
const nonconformanceRoutes = require('./nonconformance-routes');
const customerRoutes = require('./customer-routes');
const customerComplaintRoutes = require('./customer-complaint-routes');
const supplierRoutes = require('./supplier-routes');
const supplierNcrRoutes = require('./supplier-ncr-routes');
const floorRoutes = require('./floor-routes');
// This Module's own contribution to the tier board's registry (issue #216),
// beside the routers rather than among them: it is data src/index.js spreads
// into the assembled registry, not a piece of the HTTP surface.
const kpiRegistry = require('./kpi-registry');

const router = express.Router();
router.use(productRoutes);
router.use(defectCodeRoutes);
router.use(nonconformanceRoutes);
router.use(customerRoutes);
router.use(customerComplaintRoutes);
router.use(supplierRoutes);
router.use(supplierNcrRoutes);
router.use(floorRoutes);

module.exports = {
  router,
  kpiRegistry
};
