/*
 * The skills matrix, over HTTP (issue #11). Mounted by index.js alongside
 * routes.js, plant-routes.js, directory-routes.js and job-role-routes.js, all
 * under `/api/people`. This file owns every authorization decision for the
 * skills surface — skills.js stays unaware of who is calling, the same split
 * job-role-routes.js/job-roles.js and plant-routes.js/plant.js already draw.
 *
 * GET /skills sits behind `authenticate` + `requireActive` only — no admin,
 * no Org Unit scope — following job-role-routes.js's own reasoning for GET
 * /job-roles exactly: `skills` is reference data shared by every Site (this
 * file's own header, and job-roles.js's for the same structural point about
 * job_roles), not a thing a caller must already hold a grant on to be told
 * about.
 *
 * POST and PATCH /skills are administrator only, the same reference-data
 * write precedent job-role-routes.js follows for POST/PATCH /job-roles.
 * There is no DELETE — deactivation only (PATCH isActive=false) — see
 * skills.js's own header on why.
 *
 * PUT /employees/:id/skills/:skillId is administrator only too, but for a
 * different reason than the catalogue writes above: ADR-0010's own
 * Consequences section names this issue directly — "Skills (issue #11) are
 * the test case: a skill names an Employee and a competency, not an Org
 * Unit, so ADR-0009's original reasoning is expected to hold there
 * unchanged" — so this does NOT follow POST /employees/:id/assignments'
 * Org-Unit-write-scope pattern (directory-routes.js, also ADR-0010). This
 * route's path starts with `/employees/`, but it is declared here rather
 * than in directory-routes.js since it belongs to the write surface
 * directory.js's own header says issue #11 owns; Express does not care which
 * router file registers which path segment.
 *
 * GET /skills/:id/qualified-employees is an open read (authenticate +
 * requireActive only), extending ADR-0009's own reasoning: Employee identity
 * information reachable via the directory is not secret, only the ability to
 * *act* is scope-gated. orgUnitId is required on this route — skills.js's
 * own listQualifiedEmployees enforces that with a 400, this file just parses
 * the query string into the shape that function expects.
 *
 * GET /sites/:siteId/skill-coverage is deliberately narrower than every
 * other Site-shaped read in this Module: `authorization.requireSiteScope`
 * (plant-routes.js's own GET /sites/:siteId) is satisfied by any grant at
 * all, but a coverage-and-shortfall report is a workforce-planning fact, not
 * general directory browsing — closer in kind to `GET /accounts`
 * (routes.js), which ADR-0009 keeps administrator-only for the same reason:
 * some facts about the plant are not "who works here", they are "how the
 * plant is being run", and those stay narrower even than an ordinary Org
 * Unit grant reaches. requireAdmin needs no existence check up front — a
 * non-admin gets 403 regardless of whether the Site id is real, so there is
 * no 403-vs-404 leak the way authorization.js's own header warns about for
 * scope checks — so the Site is resolved via plant.getSite (404) only after
 * the admin gate, inside the handler itself.
 */

const express = require('express');
const { authenticate, requireActive } = require('./middleware');
const { requireAdmin } = require('./authorization');
const plant = require('./plant');
const { parseId, handleError } = require('./errors');
const {
  listSkills,
  createSkill,
  updateSkill,
  recordEmployeeSkill,
  listQualifiedEmployees,
  getSiteSkillCoverage
} = require('./skills');

const router = express.Router();

router.get('/skills', authenticate, requireActive, async (req, res, next) => {
  try {
    // Exact string "true" only — same reasoning as every other boolean query
    // flag in this Module (job-role-routes.js's own includeInactive, e.g.).
    const includeInactive = req.query.includeInactive === 'true';
    const skillCategory = typeof req.query.skillCategory === 'string' ? req.query.skillCategory : undefined;
    const skills = await listSkills({ includeInactive, skillCategory });
    res.json({ skills });
  } catch (error) {
    handleError(error, res, next);
  }
});

router.post('/skills', authenticate, requireActive, requireAdmin, async (req, res, next) => {
  try {
    const skill = await createSkill(req.body ?? {}, req.account.id);
    res.status(201).json({ skill });
  } catch (error) {
    handleError(error, res, next);
  }
});

router.patch('/skills/:id', authenticate, requireActive, requireAdmin, async (req, res, next) => {
  try {
    const id = parseId(req.params.id);
    if (id === null) {
      return res.status(400).json({ message: 'id must be a valid skill id' });
    }
    const skill = await updateSkill(id, req.body ?? {}, req.account.id);
    res.json({ skill });
  } catch (error) {
    handleError(error, res, next);
  }
});

// Recording (or re-assessing) an Employee holding a skill — see this file's
// own header for why this sits behind requireAdmin rather than the
// destination-Org-Unit write scope POST /employees/:id/assignments uses.
// Both ids are validated here (400 on malformed) before skills.js's own
// getEmployee/getSkill ever run — the same "route parses, service resolves
// existence" split directory-routes.js's own requireEmployeeId follows.
router.put(
  '/employees/:id/skills/:skillId',
  authenticate,
  requireActive,
  requireAdmin,
  async (req, res, next) => {
    try {
      const employeeId = parseId(req.params.id);
      if (employeeId === null) {
        return res.status(400).json({ message: 'id must be a valid Employee id' });
      }
      const skillId = parseId(req.params.skillId);
      if (skillId === null) {
        return res.status(400).json({ message: 'skillId must be a valid skill id' });
      }

      const employeeSkill = await recordEmployeeSkill(employeeId, skillId, req.body ?? {}, req.account.id);
      // Always 200: this is an upsert (skills.js's own recordEmployeeSkill
      // comment), and PUT's own semantics ("the resource at this URI is now
      // this representation") do not distinguish first-write from
      // re-assessment the way POST's 201 would.
      res.status(200).json({ employeeSkill });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// `minimumLevel` mirrors the CHECK on employee_skills.proficiency_level's own
// usable range for "qualified" (1-4; a bare 0 means "none" on the ILUO scale,
// so skills.js's own listQualifiedEmployees never treats 0 as a real minimum
// either — see that function's own validateMinimumLevel).
function parseMinimumLevel(value) {
  const str = String(value).trim();
  return /^[1-4]$/.test(str) ? Number(str) : null;
}

router.get('/skills/:id/qualified-employees', authenticate, requireActive, async (req, res, next) => {
  try {
    const id = parseId(req.params.id);
    if (id === null) {
      return res.status(400).json({ message: 'id must be a valid skill id' });
    }

    // Required here, not merely optional — the criterion is explicitly
    // "scoped to an Org Unit" (skills.js's own header).
    const orgUnitId = parseId(req.query.orgUnitId);
    if (orgUnitId === null) {
      return res.status(400).json({ message: 'orgUnitId is required and must be a valid Org Unit id' });
    }

    let minimumLevel;
    if (req.query.minimumLevel !== undefined) {
      minimumLevel = parseMinimumLevel(req.query.minimumLevel);
      if (minimumLevel === null) {
        return res.status(400).json({ message: 'minimumLevel must be an integer between 1 and 4' });
      }
    }

    const employees = await listQualifiedEmployees(id, { orgUnitId, minimumLevel });
    res.json({ employees });
  } catch (error) {
    handleError(error, res, next);
  }
});

router.get('/sites/:siteId/skill-coverage', authenticate, requireActive, requireAdmin, async (req, res, next) => {
  try {
    const siteId = parseId(req.params.siteId);
    const site = await plant.getSite(siteId); // throws the 404 (also covers a malformed id, same as GET /sites/:siteId).
    const coverage = await getSiteSkillCoverage(site.id);
    res.json({ coverage });
  } catch (error) {
    handleError(error, res, next);
  }
});

module.exports = router;
