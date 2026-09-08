/*
 * Work orders over HTTP (issue #57, plus assigning one — issue #62 — and
 * starting, completing and cancelling one — issue #63). Mounted by index.js
 * under `/api/maintenance`, alongside asset-routes.js.
 *
 * Like asset-routes.js, this is the one file in this pairing that talks to
 * People, and only through `modules/people`'s entry point (ADR-0006):
 * `authenticate`, `requireActive`, `findSite`, `findOrgUnit`, `findEmployee`,
 * `canAct` and the shared `OUTSIDE_GRANTED_ORG_UNITS` wording. Everything
 * about a work order's own fields, including whether a transition is legal
 * from its current status, is work-orders.js's business.
 *
 * Same two scope rules as Assets (#55), applied to work orders:
 *
 *   - Reads are Site-wide. GET /sites/:siteId/work-orders sits behind
 *     `authenticate` + `requireActive` and a known-Site check only — no role
 *     check, no Grant filter. ADR-0009's addendum for the Asset register
 *     applies here unchanged: Org Unit scope decides where an Account may
 *     act, not what it may know about. `?includeHistory=true` widens the
 *     statuses returned (see work-orders.js's listWorkOrdersAtSite) but does
 *     not change who may ask.
 *   - Writes are branch-scoped. POST /work-orders requires a write Grant
 *     reaching the Org Unit the named Asset already sits at — there is no
 *     orgUnitId in the body at all, since work_orders.org_unit_id is filled
 *     by trigger from asset_id (see work-orders.js's own header), so the
 *     client does not send one and any that is sent is ignored, exactly as
 *     work-orders.js's createWorkOrder does not read it off its own input.
 *     PUT /work-orders/:id/assignee (issue #62) and the three POST
 *     transition routes below (issue #63) all require a write Grant reaching
 *     the Org Unit the Work order's own org_unit_id already names — see
 *     requireWorkOrderWriteScope below. There is no exception for the
 *     assignee acting on their own job without a Grant; #77 is where that
 *     changes.
 *
 * PUT /work-orders/:id/assignee never reads a qualification, and never will
 * from this file: see ADR-0018. What a candidate holds is shown by People's
 * own GET /employees/assignee-candidates (directory-routes.js), not by
 * anything here — this route only resolves the named Employee (existence,
 * and whether they have Departed) and writes the assignee.
 *
 * POST /work-orders/:id/start, /complete and /cancel (issue #63) are three
 * narrow routes rather than one PATCH { status } — see ADR-0019 (D1): each
 * transition has a different precondition and a different body (none /
 * { note } / { reason }), and a client-chosen status string invites a
 * caller to post 'closed' or 'on_hold', which this slice does not offer.
 * All three answer 200 with { workOrder }, the full row, so the caller can
 * patch its own copy in place with no second read — not 201, nothing is
 * created.
 */

const express = require('express');
const people = require('../people');
const assets = require('./assets');
const workOrders = require('./work-orders');
const { httpError, notFound, parseId, handleError } = require('./errors');

const router = express.Router();

// Mirrors asset-routes.js's own requireKnownSite exactly — see that file's
// header for why an unknown Site is a 404, never a silently empty 200.
async function requireKnownSite(req, res, next) {
  try {
    const site = await people.findSite(req.params.siteId);
    if (!site) throw notFound('Site');
    req.site = site;
    return next();
  } catch (error) {
    return handleError(error, res, next);
  }
}

// Write scope on the Org Unit the named ASSET already sits at — the same
// shape asset-routes.js's own requireAssetWriteScope follows for PATCH
// /assets/:id, applied here to an assetId read from the BODY rather than a
// route param, since POST /work-orders has no :id of its own yet.
//
// Existence before scope, same ordering as every other write route in this
// Module: `assets.findAsset` is total (issue #61's own fix), so a malformed
// or unknown assetId resolves to a clean 404 — naming the Asset as the
// problem, the acceptance criterion issue #57 calls out by name — before
// `canAct` is ever asked. `write: true` is passed explicitly and must stay
// that way: canAct's `write` defaults to FALSE, so dropping it would
// silently authorise this write for any read Grant, with no error anywhere
// to notice.
async function requireAssetWriteScope(req, res, next) {
  try {
    const asset = await assets.findAsset(req.body?.assetId);
    if (!asset) throw notFound('Asset');

    const allowed = await people.canAct({ account: req.account, orgUnitId: asset.orgUnitId, write: true });
    if (!allowed) {
      return res.status(403).json({ message: people.OUTSIDE_GRANTED_ORG_UNITS });
    }
    req.asset = asset;
    return next();
  } catch (error) {
    return handleError(error, res, next);
  }
}

router.post(
  '/work-orders',
  people.authenticate,
  people.requireActive,
  requireAssetWriteScope,
  async (req, res, next) => {
    try {
      // orgUnitId is deliberately not read off req.body here even if a
      // caller sent one: work_orders.org_unit_id is filled by the database
      // trigger from asset_id, and the client does not get a say in it.
      const workOrder = await workOrders.createWorkOrder(
        {
          assetId: req.asset.id,
          summary: req.body?.summary,
          workType: req.body?.workType,
          priority: req.body?.priority,
          description: req.body?.description
        },
        req.account.id
      );
      res.status(201).json({ workOrder });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// Write scope on the Org Unit the Work order's ASSET sits at — read off
// work_orders.org_unit_id, which the work_orders_fill_org_unit trigger already
// derived from the Asset. Never from the request body.
//
// Existence before scope, the same ordering every write route in this Module
// follows and for the same reason (AGENTS.md §6): canAct returns true for role
// admin before it even checks whether the Org Unit id is null, so checking
// scope first would turn an administrator's typo into a raw 500 instead of a
// 404 that names the Work order. `write: true` is explicit and must stay that
// way — it defaults to false.
//
// This reads the denormalised column rather than the Asset live, unlike
// requireAssetWriteScope above, because the trigger that keeps it in sync
// (work_orders_fill_org_unit, migrations/1756000000000_baseline.js) fires
// only `BEFORE INSERT OR UPDATE OF asset_id` — it never re-fires if the Asset
// itself is later relocated to a different Org Unit. That is unreachable
// today (nothing in assets.js updates assets.org_unit_id), but whoever adds
// Asset relocation should know this check would then diverge from a live
// read and go stale until the Work order's own asset_id changes again.
async function requireWorkOrderWriteScope(req, res, next) {
  try {
    const workOrder = await workOrders.findWorkOrder(req.params.id);
    if (!workOrder) throw notFound('Work order');
    const allowed = await people.canAct({ account: req.account, orgUnitId: workOrder.orgUnitId, write: true });
    if (!allowed) {
      return res.status(403).json({ message: people.OUTSIDE_GRANTED_ORG_UNITS });
    }
    req.workOrder = workOrder;
    return next();
  } catch (error) {
    return handleError(error, res, next);
  }
}

// Assigning and reassigning a Work order (issue #62) — one PUT, one
// idempotent replacement of a single value. Assigning to somebody for the
// first time and handing it to somebody else afterward are the same write
// from the database's point of view (assigned_to changes either way), so
// there is one route and one service function, not a separate reassign
// path. No qualification is consulted anywhere in this route: see ADR-0018.
//
// Order inside the handler: parse employeeId (400) -> people.findEmployee
// (404) -> isActive (409) -> workOrders.assignWorkOrder. Existence and scope
// on the Work order itself are already handled by requireWorkOrderWriteScope
// above, before this handler ever runs.
router.put(
  '/work-orders/:id/assignee',
  people.authenticate,
  people.requireActive,
  requireWorkOrderWriteScope,
  async (req, res, next) => {
    try {
      const employeeId = parseId(req.body?.employeeId);
      if (employeeId === null) {
        return res.status(400).json({ message: 'employeeId must be a valid Employee id' });
      }

      const employee = await people.findEmployee(employeeId);
      if (!employee) throw notFound('Employee');
      if (!employee.isActive) {
        throw httpError(409, 'this Employee has departed and cannot be assigned');
      }

      const workOrder = await workOrders.assignWorkOrder(req.workOrder.id, employeeId, req.account.id);
      res.json({ workOrder });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// Starting, completing and cancelling a Work order (issue #63). All three
// share requireWorkOrderWriteScope, so existence-before-scope and the write
// Grant check are identical to PUT /assignee above; what's left to each
// handler is calling the matching service function and letting its own
// guard (work-orders.js's transitionGuard) turn an illegal transition into
// the named 409. `req.body?.x` is this file's existing idiom (see PUT
// /assignee) for a request that may have sent no body at all — POST /start
// needs none and must not require one.
router.post(
  '/work-orders/:id/start',
  people.authenticate,
  people.requireActive,
  requireWorkOrderWriteScope,
  async (req, res, next) => {
    try {
      const workOrder = await workOrders.startWorkOrder(req.workOrder.id, req.account.id);
      res.json({ workOrder });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

router.post(
  '/work-orders/:id/complete',
  people.authenticate,
  people.requireActive,
  requireWorkOrderWriteScope,
  async (req, res, next) => {
    try {
      const workOrder = await workOrders.completeWorkOrder(
        req.workOrder.id,
        { note: req.body?.note },
        req.account.id
      );
      res.json({ workOrder });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

router.post(
  '/work-orders/:id/cancel',
  people.authenticate,
  people.requireActive,
  requireWorkOrderWriteScope,
  async (req, res, next) => {
    try {
      const workOrder = await workOrders.cancelWorkOrder(
        req.workOrder.id,
        { reason: req.body?.reason },
        req.account.id
      );
      res.json({ workOrder });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

router.get(
  '/sites/:siteId/work-orders',
  people.authenticate,
  people.requireActive,
  requireKnownSite,
  async (req, res, next) => {
    try {
      let orgUnitPath = null;
      if (req.query.orgUnitId !== undefined) {
        const orgUnit = await people.findOrgUnit(req.query.orgUnitId);
        if (!orgUnit) throw notFound('Org Unit');
        // An Org Unit that exists but sits at a different Site than
        // `:siteId` is, from this endpoint's point of view, no such Org
        // Unit *in this Site* — the same reasoning requireKnownSite above
        // applies to a Site that does not exist at all. Answering 404 here
        // (not 400) keeps that: without this check the query below can
        // never match (`ou.site_id = :siteId AND ou.path <@ ...`), so the
        // filter would silently come back as an empty 200 list instead of
        // surfacing that the filter was never coherent.
        if (orgUnit.siteId !== req.site.id) throw notFound('Org Unit');
        orgUnitPath = orgUnit.path;
      }
      // includeHistory (issue #63) mirrors the Asset register's own
      // includeRetired (asset-routes.js): a string comparison against 'true'
      // rather than a truthy check, since every query parameter arrives as a
      // string and anything else — missing, 'false', '1' — means "no".
      const includeHistory = req.query.includeHistory === 'true';
      res.json({
        workOrders: await workOrders.listWorkOrdersAtSite(req.site.id, { orgUnitPath, includeHistory })
      });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

module.exports = router;
