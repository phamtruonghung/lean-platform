/*
 * The Asset register over HTTP (issue #56). Mounted by index.js under
 * `/api/maintenance`.
 *
 * This is the one file in the Module that talks to People, and it does so
 * only through `modules/people`'s entry point (ADR-0006): `authenticate`,
 * `requireActive`, `findSite`, `findOrgUnit`, `canAct` and the shared
 * `OUTSIDE_GRANTED_ORG_UNITS` wording. Everything else about an Asset is
 * assets.js's own business.
 *
 * Two scope rules, and they are deliberately different (#55):
 *
 *   - Reads are Site-wide. GET /sites/:siteId/assets sits behind
 *     `authenticate` + `requireActive` and nothing else — no role check, no
 *     Grant filter, no per-row canAct. ADR-0009 already settled the
 *     reasoning for the Employee directory: Org Unit scope decides where an
 *     Account may act, not who it may know about, and a supervisor who
 *     cannot see the line beside theirs cannot plan around it. Note this is
 *     NOT how People's own GET /sites/:siteId/org-units behaves, which is
 *     requireSiteScope'd — the difference is the point, not an oversight.
 *   - Writes are branch-scoped. POST /assets requires a write Grant reaching
 *     the Org Unit the Asset is placed at.
 *
 * `requireKnownSite` and `requireOrgUnitWriteScope` below are the two
 * middlewares that carry those rules. Both resolve existence BEFORE asking
 * about scope, which is issue #8's own 403-vs-404 ordering, and here it is
 * load-bearing for a second reason People's own call sites never faced:
 * `canAct` returns true for role `admin` before it checks whether the Org
 * Unit id is null at all, so asking it first would turn an administrator's
 * typo into a 500 on a NOT NULL foreign key rather than a clean 404.
 */

const express = require('express');
const people = require('../people');
const assets = require('./assets');
const { parseId, notFound, handleError } = require('./errors');

const router = express.Router();

// The Site a listing names must exist, whoever is asking — a 404, never a
// silently empty 200. Two reasons, both about consistency rather than
// secrecy: People's own GET /sites/:siteId/org-units already 404s an unknown
// Site (authorization.requireSiteScope -> plant.getSite), and an empty list
// for a Site that does not exist is indistinguishable from a real Site with
// no Assets, which is a lie a client cannot recover from. Nothing leaks by
// answering honestly here: this Module's reads are Site-wide by decision, so
// a caller who reaches this route is already entitled to every Asset in
// every Site, and the existence of a Site id is strictly less than that.
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

// Write scope on the Org Unit named in the body — the same rule People's own
// requireOrgUnitCreateScope applies to a parentId, applied to an Asset's
// placement. `write: true` is passed explicitly and must stay that way:
// canAct's `write` defaults to FALSE, so dropping it would silently authorise
// this write for any read Grant, with no error anywhere to notice.
async function requireOrgUnitWriteScope(req, res, next) {
  try {
    const orgUnitId = parseId(req.body?.orgUnitId);
    if (orgUnitId === null) {
      return res.status(400).json({ message: 'orgUnitId must be a valid Org Unit id' });
    }
    const orgUnit = await people.findOrgUnit(orgUnitId);
    if (!orgUnit) throw notFound('Org Unit');

    const allowed = await people.canAct({ account: req.account, orgUnitId: orgUnit.id, write: true });
    if (!allowed) {
      return res.status(403).json({ message: people.OUTSIDE_GRANTED_ORG_UNITS });
    }
    req.orgUnit = orgUnit;
    return next();
  } catch (error) {
    return handleError(error, res, next);
  }
}

router.get(
  '/sites/:siteId/assets',
  people.authenticate,
  people.requireActive,
  requireKnownSite,
  async (req, res, next) => {
    try {
      res.json({ assets: await assets.listAssetsAtSite(req.site.id) });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// No `:siteId` in this path, unlike People's POST /sites/:siteId/org-units:
// `assets` has no site_id column at all. An Asset's Site is whichever Site
// its Org Unit belongs to, so naming one in the URL would be a second source
// of truth to keep agreeing with the first. Issue #57's work orders are the
// same shape for the same reason (work_orders.org_unit_id is filled by
// trigger from the Asset), so POST /work-orders will match this.
router.post(
  '/assets',
  people.authenticate,
  people.requireActive,
  requireOrgUnitWriteScope,
  async (req, res, next) => {
    try {
      const asset = await assets.createAsset(
        { ...(req.body ?? {}), orgUnitId: req.orgUnit.id },
        req.account.id
      );
      res.status(201).json({ asset });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

module.exports = router;
