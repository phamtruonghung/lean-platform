/*
 * Breakdowns and downtime over HTTP (issue #73). Mounted by index.js under
 * `/api/maintenance`, alongside the Asset, Work order and Request routers.
 *
 * Like work-order-routes.js and request-routes.js, this is the one file in
 * this pairing that talks to People, and only through `modules/people`'s
 * entry point (ADR-0006): `authenticate`, `requireActive`, `requirePermission`,
 * `findSite`, `canAct` and the shared `OUTSIDE_GRANTED_ORG_UNITS` wording.
 * Everything
 * about a stop's own fields, including whether it is still open and what
 * `requires_comment` means, is downtime.js's business. The Asset is resolved
 * through Maintenance's own `assets.findAsset`, not through People.
 *
 * Three rules, following the same split as Assets (#55), Work orders (#57) and
 * Requests (#72), plus the permission code that names each function (ADR-0061):
 *
 *   - The reason catalogue asks only the Downtime Screen's own code
 *     (`MTN_DOWNTIME_DISPLAY`). It is a shared global catalogue (ADR-0005),
 *     not an Org-Unit-scoped record, and it feeds the classify picker, which
 *     every role that can reach that Screen holds the code for.
 *   - Reads are Site-wide and gated by `MTN_DOWNTIME_DISPLAY`, with no Grant
 *     filter. GET /sites/:siteId/downtime sits behind `authenticate` +
 *     `requireActive`, a known-Site check and the code (ADR-0009: scope decides
 *     where an Account may act, not what it may know about).
 *     `?includeClosed=true` widens what is
 *     returned, not who may ask.
 *   - Writes are branch-scoped, need a WRITE Grant because both reporting
 *     and classifying commit maintenance to something, **and** need
 *     `MTN_DOWNTIME_CHANGE`: a Grant says where, a code says what, and neither
 *     implies the other. Reporting a Breakdown
 *     needs one reaching the Org Unit the named Asset already sits at;
 *     closing and classifying need one reaching the stop's own
 *     `org_unit_id`, which the `downtime_events_fill_org` trigger derived
 *     from the Asset when it was reported.
 *
 * Existence before scope on every write, the ordering AGENTS.md §6 requires
 * and the rest of this Module follows: the Asset or the stop must be found (a
 * 404) before `canAct` is asked (a 403). It is load-bearing here for the same
 * reason it is elsewhere: `canAct` returns true for role `admin` before it
 * checks whether the Org Unit id is null, so checking scope first would turn
 * an administrator's typo into a raw 500 rather than a clean 404. `write:
 * true` is passed explicitly and must stay that way — it defaults to false, so
 * dropping it silently authorises the write for a read-only Grant.
 */

const express = require('express');
const people = require('../people');
const assets = require('./assets');
const downtime = require('./downtime');
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
// shape work-order-routes.js's own requireAssetWriteScope follows, applied
// here because reporting a Breakdown names an assetId in the body rather than
// a stop id in the path. A Breakdown is maintenance committing to work
// (CONTEXT.md's Breakdown), so this is a WRITE check, not the read check
// request-routes.js's raise uses.
//
// Existence before scope: `assets.findAsset` is total, so a malformed or
// unknown assetId resolves to a clean 404 naming the Asset before `canAct` is
// ever asked. `write: true` is explicit and must stay that way.
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

// Write scope on the Org Unit the stop's own `org_unit_id` already names —
// derived by the `downtime_events_fill_org` trigger from the Asset at report
// time and never read from the request body. Existence before scope, and
// `write: true` explicit, for the reasons in this file's header. This is the
// only scope check closing and classifying need: a stop may be closed or
// classified by somebody other than whoever reported it, so reporter is never
// consulted.
async function requireDowntimeWriteScope(req, res, next) {
  try {
    const downtimeEvent = await downtime.findDowntimeEvent(req.params.id);
    if (!downtimeEvent) throw notFound('Downtime event');

    const allowed = await people.canAct({
      account: req.account,
      orgUnitId: downtimeEvent.orgUnitId,
      write: true
    });
    if (!allowed) {
      return res.status(403).json({ message: people.OUTSIDE_GRANTED_ORG_UNITS });
    }
    req.downtimeEvent = downtimeEvent;
    return next();
  } catch (error) {
    return handleError(error, res, next);
  }
}

// The two permission codes this file asks (ADR-0061). `MTN_DOWNTIME_CHANGE` is
// seeded on supervisor/engineer/manager/administrator and `MTN_DOWNTIME_DISPLAY`
// on the same four — exactly the roles the sidebar offers the Downtime Screen
// to (ModuleRoles.maintenance) — so the pair refuses nobody who could reach
// these routes through that Screen before the retrofit. The Grant question each
// write already asked stays where it is: a code says what, a Grant says where.
const mayReadDowntime = people.requirePermission('MTN_DOWNTIME_DISPLAY');
const mayRecordDowntime = people.requirePermission('MTN_DOWNTIME_CHANGE');

// The classify picker's catalogue. A global catalogue, not a scoped record, so
// it asks only the Downtime Screen's own code — no Grant filter, and every role
// that can reach the Screen holds `MTN_DOWNTIME_DISPLAY`, which the picker
// needs in order to render for a writer. Mounted before the
// `/sites/:siteId/downtime` read because it has no Site in its path at all.
router.get('/downtime-reasons', people.authenticate, people.requireActive, mayReadDowntime, async (req, res, next) => {
  try {
    res.json({ downtimeReasons: await downtime.listDowntimeReasons() });
  } catch (error) {
    handleError(error, res, next);
  }
});

// Report a Breakdown. `orgUnitId` is never read off the body even if a caller
// sent one: downtime_events.org_unit_id is filled by trigger from asset_id.
// `reportedBy` is the caller's linked Employee, or null when the Account names
// no Employee. The response carries both records the one call produced, so the
// client can show the stop and follow the job without a second round trip.
router.post(
  '/downtime',
  people.authenticate,
  people.requireActive,
  requireAssetWriteScope,
  mayRecordDowntime,
  async (req, res, next) => {
    try {
      const result = await downtime.reportBreakdown(
        {
          assetId: req.asset.id,
          startedAt: req.body?.startedAt,
          description: req.body?.description,
          reportedBy: req.account.employeeId ?? null
        },
        req.account.id
      );
      res.status(201).json(result);
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// The Site-wide downtime read: open stops by default ("what is down right
// now"), everything when the caller asks for history by name. Only the exact
// string 'true' counts, mirroring asset-routes.js's own includeRetired — any
// other value means "no", because this is a convenience filter over an
// already-visible surface, not a value a caller could be wrong about in a way
// worth a 400 for.
router.get(
  '/sites/:siteId/downtime',
  people.authenticate,
  people.requireActive,
  requireKnownSite,
  mayReadDowntime,
  async (req, res, next) => {
    try {
      const includeClosed = req.query.includeClosed === 'true';
      res.json({
        ...(await downtime.listDowntimeAtSite(req.site.id, { includeClosed }))
      });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// Close a stop. `endedAt` is optional — omitted means now(). Answering 200
// (not 201) because the stop is the resource being moved, not a new one;
// closing an already-closed stop is the 409 downtime.js's lock-then-check
// produces.
router.post(
  '/downtime/:id/close',
  people.authenticate,
  people.requireActive,
  requireDowntimeWriteScope,
  mayRecordDowntime,
  async (req, res, next) => {
    try {
      const downtimeEvent = await downtime.closeDowntimeEvent(
        req.downtimeEvent.id,
        { endedAt: req.body?.endedAt },
        req.account.id
      );
      res.json({ downtimeEvent });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// Classify a stop against the reason tree. `classifiedBy` is the caller's own
// linked Employee, distinct from `reportedBy` — a stop may be classified by
// somebody other than whoever raised it. The reason's existence, the
// `requires_comment` rule and the update itself are downtime.js's business.
router.post(
  '/downtime/:id/classify',
  people.authenticate,
  people.requireActive,
  requireDowntimeWriteScope,
  mayRecordDowntime,
  async (req, res, next) => {
    try {
      const downtimeEvent = await downtime.classifyDowntimeEvent(
        req.downtimeEvent.id,
        { downtimeReasonId: req.body?.downtimeReasonId, description: req.body?.description },
        req.account.id,
        req.account.employeeId ?? null
      );
      res.json({ downtimeEvent });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

module.exports = router;
