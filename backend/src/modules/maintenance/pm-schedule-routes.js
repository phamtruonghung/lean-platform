/*
 * PM schedules over HTTP (issue #74). Mounted by index.js under
 * `/api/maintenance`, alongside the Asset, Work order and Job plan routers.
 *
 * Like work-order-routes.js, this is the one file in this pairing that talks
 * to People, and only through `modules/people`'s entry point (ADR-0006):
 * `authenticate`, `requireActive`, `findSite`, `canAct` and the shared
 * `OUTSIDE_GRANTED_ORG_UNITS` wording. Everything about a schedule's own
 * fields, including whether it is due and what a raise writes, is
 * pm-schedules.js's business. The Asset is resolved through Maintenance's own
 * `assets.findAsset`; the Job plan through this Module's own
 * `job-plans.findJobPlan`.
 *
 * Same two scope rules as Work orders (#57), applied to schedules:
 *
 *   - Reads are Site-wide. GET /sites/:siteId/pm-schedules sits behind
 *     `authenticate` + `requireActive` and a known-Site check only — no role
 *     check, no Grant filter (ADR-0009: scope decides where an Account may
 *     act, not what it may know about). `?includeInactive=true` widens what
 *     is returned (active-only by default), not who may ask.
 *   - Writes are branch-scoped. A schedule is scoped from its Asset, so both
 *     creating one and raising work from one need a WRITE Grant reaching the
 *     Org Unit the Asset sits at; deactivating one needs a WRITE Grant
 *     reaching the Org Unit the schedule's own Asset sits at.
 *
 * Existence before scope on every write (AGENTS.md §6): the Asset is found (a
 * 404 naming it) before `canAct` is asked (a 403), and only then is the Job
 * plan resolved. It is load-bearing here for the same reason it is elsewhere:
 * `canAct` returns true for role `admin` before it checks whether the Org Unit
 * id is null, so checking scope first would turn an administrator's typo into
 * a raw 500 rather than a clean 404. `write: true` is passed explicitly and
 * must stay that way — it defaults to false, so dropping it silently
 * authorises the write for a read-only Grant.
 */

const express = require('express');
const people = require('../people');
const assets = require('./assets');
const jobPlans = require('./job-plans');
const pmSchedules = require('./pm-schedules');
const { httpError, notFound, handleError } = require('./errors');

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

// Write scope on the Org Unit the named ASSET already sits at — the same shape
// work-order-routes.js's own requireAssetWriteScope follows, applied here to
// an assetId read from the BODY (a schedule is created against an Asset, not
// against an Org Unit or a Site named in the path).
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

// Write scope on the Org Unit a schedule's own Asset sits at, read off the
// schedule's resolved `orgUnitId` rather than the request body. Existence
// before scope, and `write: true` explicit, for the reasons in this file's
// header.
async function requirePmScheduleWriteScope(req, res, next) {
  try {
    const pmSchedule = await pmSchedules.findPmSchedule(req.params.id);
    if (!pmSchedule) throw notFound('PM schedule');

    const allowed = await people.canAct({
      account: req.account,
      orgUnitId: pmSchedule.orgUnitId,
      write: true
    });
    if (!allowed) {
      return res.status(403).json({ message: people.OUTSIDE_GRANTED_ORG_UNITS });
    }
    req.pmSchedule = pmSchedule;
    return next();
  } catch (error) {
    return handleError(error, res, next);
  }
}

// The Site-wide read: active schedules by default ("what comes round next"),
// inactive ones too when the caller asks for them by name. Only the exact
// string 'true' widens the list, mirroring the rest of this Module's
// include* filters.
router.get(
  '/sites/:siteId/pm-schedules',
  people.authenticate,
  people.requireActive,
  requireKnownSite,
  async (req, res, next) => {
    try {
      const includeInactive = req.query.includeInactive === 'true';
      res.json({
        pmSchedules: await pmSchedules.listPmSchedulesAtSite(req.site.id, { includeInactive })
      });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// Create a calendar schedule. `orgUnitId` is deliberately not read off the
// body even if a caller sent one: a schedule's placement is its Asset's, and
// the join decides it. The Asset (existence, then write scope) is resolved by
// requireAssetWriteScope above; the Job plan is resolved here, after scope, so
// an unknown one is a 404 naming the Job plan and an inactive one is refused
// with a 400 rather than silently attached.
router.post(
  '/pm-schedules',
  people.authenticate,
  people.requireActive,
  requireAssetWriteScope,
  async (req, res, next) => {
    try {
      const jobPlan = await jobPlans.findJobPlan(req.body?.jobPlanId);
      if (!jobPlan) throw notFound('Job plan');
      if (!jobPlan.isActive) {
        throw httpError(400, 'this Job plan is not active, so it cannot be scheduled');
      }

      const pmSchedule = await pmSchedules.createPmSchedule(
        {
          assetId: req.asset.id,
          jobPlanId: jobPlan.id,
          intervalDays: req.body?.intervalDays,
          anchor: req.body?.anchor,
          leadTimeDays: req.body?.leadTimeDays,
          priority: req.body?.priority,
          nextDueOn: req.body?.nextDueOn
        },
        req.account.id
      );
      res.status(201).json({ pmSchedule });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// Deactivate or reactivate a schedule. The scope middleware resolves the
// schedule and its Asset's Org Unit; setPmScheduleActive owns the boolean
// check and the update. Answering 200 (not 201) because the schedule is the
// resource being moved, not a new one.
router.patch(
  '/pm-schedules/:id',
  people.authenticate,
  people.requireActive,
  requirePmScheduleWriteScope,
  async (req, res, next) => {
    try {
      const pmSchedule = await pmSchedules.setPmScheduleActive(
        req.pmSchedule.id,
        req.body?.isActive,
        req.account.id
      );
      res.json({ pmSchedule });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// The sweep: raise a work order for every active, calendar schedule at the
// Site that has come inside its lead time and has no open work order yet.
//
// Scope decides which of those the caller actually raises. The candidate list
// is resolved first (a read), then, before each raise, the caller's WRITE
// Grant reaching that schedule's Asset Org Unit is checked; a schedule outside
// the caller's Grants is silently skipped, not refused, the same way a list is
// filtered down rather than 403'd. `{ workOrders }` carries the raised ones,
// each with its copied tasks; an empty list is the honest answer when nothing
// was due or nothing was in scope.
router.post(
  '/sites/:siteId/pm-schedules/raise',
  people.authenticate,
  people.requireActive,
  requireKnownSite,
  async (req, res, next) => {
    try {
      const candidates = await pmSchedules.listDuePmSchedules(req.site.id);

      const workOrders = [];
      for (const candidate of candidates) {
        const allowed = await people.canAct({
          account: req.account,
          orgUnitId: candidate.org_unit_id,
          write: true
        });
        if (!allowed) continue;

        const raised = await pmSchedules.raiseWorkOrderFromPmSchedule(candidate.id, req.account.id);
        if (raised) workOrders.push(raised);
      }

      res.json({ workOrders });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

module.exports = router;
