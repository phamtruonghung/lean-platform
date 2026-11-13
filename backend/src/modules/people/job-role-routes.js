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
 *
 * **The ADR-0061 retrofit (issue #509).** The read asks
 * `PPL_JOB_ROLES_DISPLAY` and the two writes ask `PPL_JOB_ROLES_CHANGE`. Both
 * are seeded on exactly the callers the rules above admitted — the display code
 * on ROLE_STANDARD, the default group every approved Account carries, and the
 * change code on ROLE_ADMIN alone — so no Account gained or lost access; the
 * write refusal now names the permission instead of the role.
 */

const express = require('express');
const { authenticate, requireActive } = require('./middleware');
const { requirePermission } = require('./authorization');
const { parseId, handleError } = require('./errors');
const { listJobRoles, createJobRole, updateJobRole } = require('./job-roles');

const router = express.Router();

// The catalogue's two codes (ADR-0061, issue #509), each seeded on the same set
// of roles its old rule admitted: display on ROLE_STANDARD (the default group),
// change on ROLE_ADMIN alone.
const mayReadJobRoles = requirePermission('PPL_JOB_ROLES_DISPLAY');
const mayMaintainJobRoles = requirePermission('PPL_JOB_ROLES_CHANGE');

router.get('/job-roles', authenticate, requireActive, mayReadJobRoles, async (req, res, next) => {
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

router.post('/job-roles', authenticate, requireActive, mayMaintainJobRoles, async (req, res, next) => {
  try {
    const jobRole = await createJobRole(req.body ?? {}, req.account.id);
    res.status(201).json({ jobRole });
  } catch (error) {
    handleError(error, res, next);
  }
});

router.patch('/job-roles/:id', authenticate, requireActive, mayMaintainJobRoles, async (req, res, next) => {
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
