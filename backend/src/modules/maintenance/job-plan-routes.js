/*
 * Job plans over HTTP (issue #74). Mounted by index.js under
 * `/api/maintenance`, alongside the Asset, Work order and PM schedule
 * routers.
 *
 * Like asset-routes.js, this is the one file in this pairing that talks to
 * People, and only through `modules/people`'s entry point (ADR-0006):
 * `authenticate` and `requireActive`. Everything about a plan's own fields —
 * a required string, the work_type enum, the task list — is job-plans.js's
 * business.
 *
 * Scope rules, and why they differ from every other write in this Module:
 * a job plan is an administrator-managed shared catalogue (ADR-0005), NOT
 * Org-Unit scoped. There is no Asset and no Org Unit in play, so there is no
 * Grant to check — the write is gated on the administrator role alone
 * (`requireAdmin` below), the same gate People's own Site creation uses.
 * Reads are open to any approved Account, exactly like the downtime reason
 * catalogue, because the plan feeds pickers and work orders every role may
 * need to see.
 *
 * `requireAdmin` is defined here rather than imported from People: People's
 * entry point deliberately does not export `requireAdmin`/`isAdmin` (see
 * people/index.js's own "deliberately NOT exported" list — no Maintenance
 * route was path-param-keyed on an Org Unit, so `canAct` was the only
 * authorization export needed). This Module may not reach past that entry
 * point (ADR-0006), so it carries its own copy of the role check, matching
 * People's own refusal sentence word for word so the same refusal reads the
 * same wherever it is produced.
 */

const express = require('express');
const people = require('../people');
const jobPlans = require('./job-plans');
const { notFound, handleError } = require('./errors');

const router = express.Router();

function requireAdmin(req, res, next) {
  if (req.account.role !== 'admin') {
    return res.status(403).json({ message: 'This action requires the administrator role.' });
  }
  return next();
}

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
router.post('/job-plans', people.authenticate, people.requireActive, requireAdmin, async (req, res, next) => {
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
router.patch('/job-plans/:id', people.authenticate, people.requireActive, requireAdmin, async (req, res, next) => {
  try {
    const jobPlan = await jobPlans.setJobPlanActive(req.params.id, req.body?.isActive, req.account.id);
    res.json({ jobPlan });
  } catch (error) {
    handleError(error, res, next);
  }
});

module.exports = router;
