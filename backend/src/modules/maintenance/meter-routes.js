/*
 * Meters and readings over HTTP (issue #79). Mounted by index.js under
 * `/api/maintenance`, alongside the Asset, Work order, Job plan and PM
 * schedule routers.
 *
 * Like asset-routes.js, this is the one file in this pairing that talks to
 * People, and only through `modules/people`'s entry point (ADR-0006):
 * `authenticate`, `requireActive`, `findSite`, `canAct` and the shared
 * `OUTSIDE_GRANTED_ORG_UNITS` wording. Everything about a meter's or a
 * reading's own fields — the enum membership, the numeric range, the
 * backward-reading refusal — is meters.js's business.
 *
 * Same two scope rules as Assets (#55) and PM schedules (#74):
 *
 *   - Reads are Site-wide. GET /sites/:siteId/meters sits behind
 *     `authenticate` + `requireActive` and a known-Site check only — no role
 *     check, no Grant filter (ADR-0009: scope decides where an Account may
 *     act, not what it may know about). GET /units-of-measure is a shared
 *     reference catalogue, readable by any approved Account, the same
 *     openness the downtime-reason catalogue already has (ADR-0005).
 *   - Writes are branch-scoped. A meter is placed on an Asset, so creating
 *     one needs a WRITE Grant reaching the Org Unit that Asset sits at;
 *     recording a reading or a rollover needs a WRITE Grant reaching the Org
 *     Unit the meter's own Asset sits at.
 *
 * Existence before scope on every write (AGENTS.md §6): the Asset or the
 * meter is found (a 404 naming it) before `canAct` is asked (a 403).
 * `write: true` is passed explicitly and must stay that way — it defaults to
 * false, so dropping it silently authorises the write for a read-only Grant.
 */

const express = require('express');
const people = require('../people');
const assets = require('./assets');
const meters = require('./meters');
const { notFound, parseId, handleError } = require('./errors');

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

// Write scope on the Org Unit the named ASSET already sits at, read from the
// BODY — the same shape pm-schedule-routes.js's own requireAssetWriteScope
// follows, since a meter is created against an Asset rather than an Org Unit
// or a Site named in the path.
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

// Write scope on the Org Unit a meter's own Asset sits at, read off the
// meter's resolved `orgUnitId`. Existence before scope, and `write: true`
// explicit, for the reasons in this file's header.
async function requireMeterWriteScope(req, res, next) {
  try {
    const meter = await meters.findMeter(req.params.id);
    if (!meter) throw notFound('Meter');

    const allowed = await people.canAct({ account: req.account, orgUnitId: meter.orgUnitId, write: true });
    if (!allowed) {
      return res.status(403).json({ message: people.OUTSIDE_GRANTED_ORG_UNITS });
    }
    req.meter = meter;
    return next();
  } catch (error) {
    return handleError(error, res, next);
  }
}

// The unit-of-measure catalogue the meter form chooses from (ADR-0023).
// Readable by any approved Account — it is a shared reference table, not an
// Org-Unit-scoped record.
router.get('/units-of-measure', people.authenticate, people.requireActive, async (req, res, next) => {
  try {
    res.json({ unitsOfMeasure: await meters.listUnitsOfMeasure() });
  } catch (error) {
    handleError(error, res, next);
  }
});

// The Site-wide read: active meters by default, retired ones too when the
// caller asks for them by name. `?assetId=` narrows to one Asset's meters —
// the PM schedule form reads exactly that. Only the exact string 'true'
// widens the list, mirroring the rest of this Module's include* filters.
router.get(
  '/sites/:siteId/meters',
  people.authenticate,
  people.requireActive,
  requireKnownSite,
  async (req, res, next) => {
    try {
      const includeInactive = req.query.includeInactive === 'true';
      // A malformed Asset id is a clean 404 rather than a raw BIGINT cast
      // error, the same total-read property every filter in this Module keeps.
      let assetId = null;
      if (req.query.assetId !== undefined) {
        assetId = parseId(req.query.assetId);
        if (assetId === null) throw notFound('Asset');
      }
      res.json({
        meters: await meters.listMetersAtSite(req.site.id, { assetId, includeInactive })
      });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// Define a meter on an Asset. `orgUnitId` is deliberately not read off the
// body even if a caller sent one: a meter's placement is its Asset's, and the
// join decides it. The Asset (existence, then write scope) is resolved by
// requireAssetWriteScope above.
router.post(
  '/meters',
  people.authenticate,
  people.requireActive,
  requireAssetWriteScope,
  async (req, res, next) => {
    try {
      const meter = await meters.createMeter(
        {
          assetId: req.asset.id,
          code: req.body?.code,
          name: req.body?.name,
          uomCode: req.body?.uomCode,
          meterType: req.body?.meterType
        },
        req.account.id
      );
      res.status(201).json({ meter });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// Record a manual reading against a meter. The meter's write scope is resolved
// by requireMeterWriteScope above. A reading lower than the last on a
// cumulative meter is refused with the named code meters.js carries; a
// non-manual source is refused there too (ADR-0030).
router.post(
  '/meters/:id/readings',
  people.authenticate,
  people.requireActive,
  requireMeterWriteScope,
  async (req, res, next) => {
    try {
      const result = await meters.recordReading(
        req.meter.id,
        {
          reading: req.body?.reading,
          note: req.body?.note,
          readAt: req.body?.readAt,
          source: req.body?.source
        },
        req.account.id
      );
      res.status(201).json(result);
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// Record an explicit rollover or replacement. Same scope and shape as a
// reading; `reading` is the new counter's own starting value and defaults to
// zero.
router.post(
  '/meters/:id/rollover',
  people.authenticate,
  people.requireActive,
  requireMeterWriteScope,
  async (req, res, next) => {
    try {
      const result = await meters.rolloverMeter(
        req.meter.id,
        {
          reading: req.body?.reading,
          note: req.body?.note,
          readAt: req.body?.readAt
        },
        req.account.id
      );
      res.status(201).json(result);
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

module.exports = router;
