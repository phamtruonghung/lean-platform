/*
 * Maintenance requests over HTTP (issue #72). Mounted by index.js under
 * `/api/maintenance`, alongside the Asset and Work order routers.
 *
 * This is the one file in this pairing that talks to People, and only through
 * `modules/people`'s entry point (ADR-0006): `authenticate`, `requireActive`,
 * `findSite`, `canAct` and the shared `OUTSIDE_GRANTED_ORG_UNITS` wording.
 * Everything about a Request's own fields, including whether it is still
 * awaiting a decision, is requests.js's business. The Asset is resolved
 * through Maintenance's own `assets.findAsset`, not through People.
 *
 * Same two scope rules as Assets (#55) and Work orders (#57), applied to
 * Requests:
 *
 *   - Reads are Site-wide. The triage queue and the requester's own list sit
 *     behind `authenticate` + `requireActive` and a known-Site check only —
 *     no role check, no Grant filter (ADR-0009: scope decides where an
 *     Account may act, not what it may know about).
 *   - Writes are branch-scoped. Raising asks a question, so it needs only a
 *     READ Grant reaching the Asset's Org Unit (`write: false`); triaging
 *     commits maintenance to something, so accepting, declining and marking
 *     duplicate each need a WRITE Grant reaching the Request's own
 *     `org_unit_id` (`write: true`).
 *
 * Existence before scope, the ordering every write route in this Module
 * follows (AGENTS.md §6). It is load-bearing here for the same reason it is
 * there: `canAct` returns true for role `admin` before it checks whether the
 * Org Unit id is null, so asking scope first would turn an administrator's
 * typo into a raw 500 rather than a clean 404. `write` is passed explicitly
 * in both directions and must stay that way — it defaults to false, so a
 * route that drops it silently authorises the write for a read-only Grant
 * with no error anywhere to notice.
 */

const express = require('express');
const people = require('../people');
const assets = require('./assets');
const requests = require('./requests');
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

// Read scope on the Org Unit the named ASSET already sits at. Raising a
// Request is an ask, not a commitment (CONTEXT.md's Request), so this is the
// one write-shaped route in the Module that needs only a read Grant —
// `write: false`, passed explicitly. Existence before scope, same as
// work-order-routes.js's requireAssetWriteScope, with the Asset resolved
// through `assets.findAsset` so a malformed or unknown `assetId` is a clean
// 404 naming the Asset.
async function requireAssetReadScope(req, res, next) {
  try {
    const asset = await assets.findAsset(req.body?.assetId);
    if (!asset) throw notFound('Asset');

    const allowed = await people.canAct({
      account: req.account,
      orgUnitId: asset.orgUnitId,
      write: false
    });
    if (!allowed) {
      return res.status(403).json({ message: people.OUTSIDE_GRANTED_ORG_UNITS });
    }
    req.asset = asset;
    return next();
  } catch (error) {
    return handleError(error, res, next);
  }
}

// Write scope on the Org Unit the Request's own `org_unit_id` already names —
// derived by trigger from the Asset at raise time and never read from the
// request body. Existence before scope, and `write: true` explicit, for the
// reasons in this file's header.
async function requireRequestWriteScope(req, res, next) {
  try {
    const request = await requests.findRequest(req.params.id);
    if (!request) throw notFound('Request');

    const allowed = await people.canAct({
      account: req.account,
      orgUnitId: request.orgUnitId,
      write: true
    });
    if (!allowed) {
      return res.status(403).json({ message: people.OUTSIDE_GRANTED_ORG_UNITS });
    }
    req.request = request;
    return next();
  } catch (error) {
    return handleError(error, res, next);
  }
}

// Raise. `orgUnitId` is never read off the body even if a caller sent one:
// maintenance_requests.org_unit_id is filled by trigger from asset_id.
// `reportedBy` is the caller's linked Employee, or null when the Account
// names no Employee — an operator who raised it from the floor is the row's
// author even though most of a plant cannot sign in as one.
router.post(
  '/requests',
  people.authenticate,
  people.requireActive,
  requireAssetReadScope,
  async (req, res, next) => {
    try {
      const request = await requests.createRequest(
        {
          assetId: req.asset.id,
          summary: req.body?.summary,
          description: req.body?.description,
          urgency: req.body?.urgency,
          productionStopped: req.body?.productionStopped,
          reportedBy: req.account.employeeId ?? null
        },
        req.account.id
      );
      res.status(201).json({ request });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// The triage queue: Requests still awaiting a decision, oldest first.
router.get(
  '/sites/:siteId/requests',
  people.authenticate,
  people.requireActive,
  requireKnownSite,
  async (req, res, next) => {
    try {
      res.json({ requests: await requests.listTriageQueueAtSite(req.site.id) });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// The requester's own Requests, all statuses, keyed on the Account that
// raised them rather than any Employee link: an Account need not name an
// Employee, and one that does not still owns every Request it raised. The
// account id is always present on an authenticated request.
router.get(
  '/sites/:siteId/requests/mine',
  people.authenticate,
  people.requireActive,
  requireKnownSite,
  async (req, res, next) => {
    try {
      res.json({
        requests: await requests.listRequestsRaisedByAtSite(req.site.id, req.account.id)
      });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// Accept: raises a linked Work order and moves the Request to 'accepted' in
// one transaction. The Work order is always `corrective` — accepting a
// Request is maintenance reacting to a problem — and the only body field read
// is the optional `priority` (default 3). Answering 200 (not 201) because
// from the Request's point of view nothing new was created — the Request is
// the resource being moved — and the body carries the Work order alongside it
// so the caller has both.
router.post(
  '/requests/:id/accept',
  people.authenticate,
  people.requireActive,
  requireRequestWriteScope,
  async (req, res, next) => {
    try {
      const { request, workOrder } = await requests.acceptRequest(
        req.request.id,
        { priority: req.body?.priority },
        req.account.id,
        req.account.employeeId ?? null
      );
      res.json({ request, workOrder });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// Decline: requires a reason.
router.post(
  '/requests/:id/decline',
  people.authenticate,
  people.requireActive,
  requireRequestWriteScope,
  async (req, res, next) => {
    try {
      const request = await requests.declineRequest(
        req.request.id,
        { reason: req.body?.reason },
        req.account.id,
        req.account.employeeId ?? null
      );
      res.json({ request });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// Mark duplicate: names the Request that survives.
router.post(
  '/requests/:id/duplicate',
  people.authenticate,
  people.requireActive,
  requireRequestWriteScope,
  async (req, res, next) => {
    try {
      const request = await requests.duplicateRequest(
        req.request.id,
        req.body?.duplicateOfId,
        req.account.id,
        req.account.employeeId ?? null
      );
      res.json({ request });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

module.exports = router;
