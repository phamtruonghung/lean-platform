/*
 * Job plans over HTTP (issue #74). Mounted by index.js under
 * `/api/maintenance`, alongside the Asset, Work order and PM schedule
 * routers.
 *
 * Like asset-routes.js, this is the one file in this pairing that talks to
 * People, and only through `modules/people`'s entry point (ADR-0006):
 * `authenticate`, `requireActive` and `requirePermission`. Everything about a
 * plan's own fields —
 * a required string, the work_type enum, the task list — is job-plans.js's
 * business.
 *
 * Scope rules, and why they differ from every other write in this Module:
 * a job plan is an administrator-managed shared catalogue (ADR-0005), NOT
 * Org-Unit scoped. There is no Asset and no Org Unit in play, so there is no
 * Grant to check — the write is gated on `MTN_JOB_PLANS_MAINTAIN` alone
 * (ADR-0061), the code that names maintaining this catalogue. The seed gives
 * that code to ROLE_ADMIN only, which is exactly the pass/fail set the
 * administrator-role comparison it replaced produced, so the retrofit refuses
 * nobody it used to admit; what changes is the refusal's own body, which is now
 * the catalogue code's (`code: 'PERMISSION_REQUIRED'`) rather than the role
 * sentence — the same change People's roles surface already made.
 * Reads are open to any approved Account, exactly like the downtime reason
 * catalogue, because the plan feeds pickers and work orders every role may
 * need to see; the catalogue has no `MTN_JOB_PLANS_DISPLAY` code to ask, which
 * is recorded on the retrofit card (t_3271c590) rather than papered over with
 * the maintain code.
 */

const express = require('express');
const people = require('../people');
const jobPlans = require('./job-plans');
const { notFound, handleError } = require('./errors');

const router = express.Router();

// "May this Account maintain the Job plan catalogue at all?" — the role half of
// the model (ADR-0061), replacing the `req.account.role !== 'admin'` copy this
// Module used to carry in ./admin. The seed gives `MTN_JOB_PLANS_MAINTAIN` to
// ROLE_ADMIN only, so the set of Accounts that pass is unchanged.
const mayMaintainJobPlans = people.requirePermission('MTN_JOB_PLANS_MAINTAIN');

// The shared catalogue: every plan by default, active-only when a caller asks
// for that by name (`?includeInactive=false`). Only the exact string 'false'
// narrows the list; anything else — absent, 'true', garbage — means "all", the
// same string-comparison idiom asset-routes.js's includeRetired follows.
router.get('/job-plans', people.authenticate, people.requireActive, async (req, res, next) => {
  try {
    const includeInactive = req.query.includeInactive !== 'false';
    res.json({ jobPlans: await jobPlans.listJobPlans({ includeInactive }) });
  } catch (error) {
    handleError(error, res, next);
  }
});

// One plan with its ordered tasks, readable by any approved Account.
// job-plans.js's findJobPlan is total, so a malformed or unknown id is a clean
// 404 naming the Job plan rather than a 500.
router.get('/job-plans/:id', people.authenticate, people.requireActive, async (req, res, next) => {
  try {
    const jobPlan = await jobPlans.findJobPlan(req.params.id);
    if (!jobPlan) throw notFound('Job plan');
    res.json({ jobPlan });
  } catch (error) {
    handleError(error, res, next);
  }
});

// Creating a plan is administrator-only. The body's shape and the plan's own
// validation (code/name required, workType in the catalogue's four, each task
// instruction required with a unique stepNo) live in job-plans.js; the plan
// and its tasks are inserted in one transaction there.
router.post('/job-plans', people.authenticate, people.requireActive, mayMaintainJobPlans, async (req, res, next) => {
  try {
    const jobPlan = await jobPlans.createJobPlan(
      {
        code: req.body?.code,
        name: req.body?.name,
        description: req.body?.description,
        workType: req.body?.workType,
        estimatedHours: req.body?.estimatedHours,
        requiresShutdown: req.body?.requiresShutdown,
        safetyNote: req.body?.safetyNote,
        tasks: req.body?.tasks
      },
      req.account.id
    );
    res.status(201).json({ jobPlan });
  } catch (error) {
    handleError(error, res, next);
  }
});

// Deactivate or reactivate a plan — administrator-only, deactivation never
// deletion. A single field, so no PATCH-versus-put ceremony beyond requiring
// the boolean; setJobPlanActive owns that check.
router.patch('/job-plans/:id', people.authenticate, people.requireActive, mayMaintainJobPlans, async (req, res, next) => {
  try {
    const jobPlan = await jobPlans.setJobPlanActive(req.params.id, req.body?.isActive, req.account.id);
    res.json({ jobPlan });
  } catch (error) {
    handleError(error, res, next);
  }
});

module.exports = router;
