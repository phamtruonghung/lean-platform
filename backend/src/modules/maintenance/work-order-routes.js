/*
 * Work orders over HTTP (issue #57). Mounted by index.js under
 * `/api/maintenance`, alongside asset-routes.js.
 *
 * Like asset-routes.js, this is the one file in this pairing that talks to
 * People, and only through `modules/people`'s entry point (ADR-0006):
 * `authenticate`, `requireActive`, `findSite`, `findOrgUnit`, `canAct` and
 * the shared `OUTSIDE_GRANTED_ORG_UNITS` wording. Everything about a work
 * order's own fields is work-orders.js's business.
 *
 * Same two scope rules as Assets (#55), applied to work orders:
 *
 *   - Reads are Site-wide. GET /sites/:siteId/work-orders sits behind
 *     `authenticate` + `requireActive` and a known-Site check only — no role
 *     check, no Grant filter. ADR-0009's addendum for the Asset register
 *     applies here unchanged: Org Unit scope decides where an Account may
 *     act, not what it may know about.
 *   - Writes are branch-scoped, but on the ASSET named in the body, not an
 *     Org Unit: POST /work-orders requires a write Grant reaching the
 *     Org Unit the named Asset already sits at. There is no orgUnitId in the
 *     body at all — work_orders.org_unit_id is filled by trigger from
 *     asset_id (see work-orders.js's own header), so the client does not
 *     send one and any that is sent is ignored, exactly as work-orders.js's
 *     createWorkOrder does not read it off its own input.
 */

const express = require('express');
const people = require('../people');
const assets = require('./assets');
const workOrders = require('./work-orders');
const { notFound, handleError } = require('./errors');

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
      res.json({ workOrders: await workOrders.listOpenWorkOrdersAtSite(req.site.id, { orgUnitPath }) });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

module.exports = router;
