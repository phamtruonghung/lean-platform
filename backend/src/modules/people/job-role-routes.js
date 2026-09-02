/*
 * The job role catalogue, over HTTP (issue #10). Mounted by index.js
 * alongside routes.js, plant-routes.js and directory-routes.js, all under
 * `/api/people`.
 *
 * GET /job-roles sits behind `authenticate` + `requireActive` only — no
 * admin, no Org Unit scope. Any approved Account needs this to filter the
 * directory by job role (directory-routes.js's own GET /employees?jobRoleId=),
 * so it follows the read surface's own reasoning in directory-routes.js/
 * ADR-0009 rather than plant-routes.js's scoped reads: a job role is
 * reference data shared by every Site (ADR-0005), not a thing a caller must
 * already hold a grant on to be told about.
 *
 * POST and PATCH /job-roles are administrator only, following plant.js's own
 * UNIT_TYPES/createSite precedent for reference-data writes rather than
 * directory-routes.js's write surface (which is administrator-only for a
 * different reason — see that file's own header). There is no DELETE: a job
 * role that has been held is history (job-roles.js's own header), so PATCH
 * isActive=false is the only way to retire one.
 */

const express = require('express');
const { authenticate, requireActive } = require('./middleware');
const { requireAdmin } = require('./authorization');
const { parseId, handleError } = require('./errors');
const { listJobRoles, createJobRole, updateJobRole } = require('./job-roles');

const router = express.Router();

router.get('/job-roles', authenticate, requireActive, async (req, res, next) => {
  try {
    // Exact string "true" only — same reasoning as directory-routes.js's own
    // includeDeparted: a stray or malformed query value must never silently
    // widen the list past "active only".
    const includeInactive = req.query.includeInactive === 'true';
    const jobRoles = await listJobRoles({ includeInactive });
    res.json({ jobRoles });
  } catch (error) {
    handleError(error, res, next);
  }
});

router.post('/job-roles', authenticate, requireActive, requireAdmin, async (req, res, next) => {
  try {
    const jobRole = await createJobRole(req.body ?? {}, req.account.id);
    res.status(201).json({ jobRole });
  } catch (error) {
    handleError(error, res, next);
  }
});

router.patch('/job-roles/:id', authenticate, requireActive, requireAdmin, async (req, res, next) => {
  try {
    const id = parseId(req.params.id);
    if (id === null) {
      return res.status(400).json({ message: 'id must be a valid job role id' });
    }
    const jobRole = await updateJobRole(id, req.body ?? {}, req.account.id);
    res.json({ jobRole });
  } catch (error) {
    handleError(error, res, next);
  }
});

module.exports = router;
