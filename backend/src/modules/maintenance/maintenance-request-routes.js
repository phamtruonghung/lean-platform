/*
 * Requests over HTTP (issue #72). Mounted by index.js under `/api/maintenance`,
 * alongside asset-routes.js and work-order-routes.js.
 *
 * Like its siblings, this is the file in the pairing that talks to People,
 * and only through `modules/people`'s entry point (ADR-0006): `authenticate`,
 * `requireActive`, `findSite`, `findOrgUnit`, `canAct` and the shared
 * `OUTSIDE_GRANTED_ORG_UNITS` wording. Everything about a Request's own fields
 * is maintenance-requests.js's business.
 *
 * Scope splits at the verb, as the ticket calls for:
 *
 *   - Raising a Request is ASKING, so it needs only a Grant reaching the
 *     Asset's Org Unit — `canAct({ ..., write: false })`. Anyone with any
 *     Grant there may say "please look at this"; that is the operator's whole
 *     job, and it commits maintenance to nothing.
 *   - Triaging (accept / decline / mark duplicate) is COMMITTING maintenance
 *     to work, so it needs a write Grant — `canAct({ ..., write: true })`,
 *     refusing a read-only caller with the shared 403 wording.
 *   - Reads are Site-wide per ADR-0009. The triage queue and the requester's
 *     own history carry no Grant filter; what the caller may do is decided by
 *     the verb above, never by what it may know about.
 *
 * `write` is passed explicitly in every canAct call: it defaults to FALSE, so
 * dropping it would silently downgrade a triage write to a read grant.
 */

const express = require('express');
const people = require('../people');
const assets = require('./assets');
const requests = require('./maintenance-requests');
const { notFound, handleError } = require('./errors');

const router = express.Router();

// Same known-Site guard asset-routes and work-order-routes share: an unknown
// Site is a 404, never a silently empty 200.
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

// Scope for RAISING a Request: a Grant — read or write — reaching the Org Unit
// the named ASSET sits at. Existence before scope, the same ordering
// requireAssetWriteScope follows: `assets.findAsset` is total, so a malformed
// or unknown assetId is a clean 404 naming the Asset before `canAct` is ever
// asked. `write: false` is passed explicitly and deliberately — raising is
// asking, not committing, so a read Grant earns it (this is the one write
// path in the Module that a read-only caller may use, by design).
async function requireAssetReadOrWriteScope(req, res, next) {
  try {
    const asset = await assets.findAsset(req.body?.assetId);
    if (!asset) throw notFound('Asset');

    const allowed = await people.canAct({ account: req.account, orgUnitId: asset.orgUnitId, write: false });
    if (!allowed) {
      return res.status(403).json({ message: people.OUTSIDE_GRANTED_ORG_UNITS });
    }
    req.asset = asset;
    return next();
  } catch (error) {
    return handleError(error, res, next);
  }
}

// Write scope for TRIAGING a Request: a write Grant reaching the Org Unit the
// Request's Asset sits at. Existence before scope (a bad :id is a 404 naming
// the Request), then `write: true` — triaging commits maintenance to work, so
// a read-only Grant is refused. The resolved Request is parked on
// `req.request` for the route's own use.
async function requireRequestWriteScope(req, res, next) {
  try {
    const request = await requests.getRequest(req.params.id); // throws the 404.
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

router.post(
  '/requests',
  people.authenticate,
  people.requireActive,
  requireAssetReadOrWriteScope,
  async (req, res, next) => {
    try {
      const created = await requests.createRequest(
        {
          assetId: req.asset.id,
          summary: req.body?.summary,
          description: req.body?.description,
          urgency: req.body?.urgency,
          productionStopped: req.body?.productionStopped
        },
        req.account.id
      );
      res.status(201).json({ request: created });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// The triage queue: Site-wide, open (new/triaged) Requests. A read, so behind
// authenticate + requireActive and a known-Site check only — no role check, no
// Grant filter (ADR-0009). The same org unit filter work-order-routes offers.
router.get(
  '/sites/:siteId/requests',
  people.authenticate,
  people.requireActive,
  requireKnownSite,
  async (req, res, next) => {
    try {
      let orgUnitPath = null;
      if (req.query.orgUnitId !== undefined) {
        const orgUnit = await people.findOrgUnit(req.query.orgUnitId);
        if (!orgUnit) throw notFound('Org Unit');
        if (orgUnit.siteId !== req.site.id) throw notFound('Org Unit');
        orgUnitPath = orgUnit.path;
      }
      res.json({ requests: await requests.listOpenRequestsAtSite(req.site.id, { orgUnitPath }) });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// The requester's own history: every Request this Account raised, and what
// became of each. A read, inherently scoped to the caller (it can only return
// rows that Account created), so authenticate + requireActive suffices.
router.get(
  '/requests/mine',
  people.authenticate,
  people.requireActive,
  async (req, res, next) => {
    try {
      res.json({ requests: await requests.listRequestsByRequester(req.account.id) });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// Accepting a Request: maintenance commits to it by raising a Work order that
// points back (ADR-0014). Write-scoped to the Request's Asset Org Unit. The
// Work order's own `workType` and `priority` are decided here — urgency is the
// operator's judgement and is not copied across, so accepting asks for them.
router.post(
  '/requests/:id/accept',
  people.authenticate,
  people.requireActive,
  requireRequestWriteScope,
  async (req, res, next) => {
    try {
      const result = await requests.acceptRequest(
        {
          requestId: req.request.id,
          workType: req.body?.workType,
          priority: req.body?.priority,
          description: req.body?.description
        },
        req.account.id
      );
      res.json(result);
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

router.post(
  '/requests/:id/decline',
  people.authenticate,
  people.requireActive,
  requireRequestWriteScope,
  async (req, res, next) => {
    try {
      res.json({
        request: await requests.declineRequest(
          { requestId: req.request.id, reason: req.body?.reason },
          req.account.id
        )
      });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

router.post(
  '/requests/:id/duplicate',
  people.authenticate,
  people.requireActive,
  requireRequestWriteScope,
  async (req, res, next) => {
    try {
      res.json({
        request: await requests.markRequestDuplicate(
          { requestId: req.request.id, duplicateOfId: req.body?.duplicateOfId },
          req.account.id
        )
      });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

module.exports = router;