/*
 * The People Module's entry point (ADR-0006). Everything another Module or
 * `src/index.js` needs from People comes through here — `router` to mount,
 * `authenticate`/`requireActive` for a future Module's own protected routes —
 * never through `./service`, `./plant`, `./middleware`, `./directory`, or
 * `./job-roles` directly.
 *
 * `router` combines five route files under the one `/api/people` mount:
 * routes.js (Accounts, issue #6), plant-routes.js (Sites and the Org Unit
 * tree, issue #7), directory-routes.js (the Employee directory, issue #9,
 * plus Org Unit assignments, issue #10), job-role-routes.js (the job role
 * catalogue, issue #10), and skill-routes.js (the skills matrix — the skill
 * catalogue, an Employee holding a skill, and skill coverage, issue #11).
 * All five belong to this Module per CONTEXT.md — see plant.js's own header
 * for why Sites/Org Units live here rather than in a Module of their own,
 * ADR-0009 for why the Employee directory is readable platform-wide rather
 * than Org-Unit-scoped the way Sites and Org Units are, and ADR-0010 for why
 * Org Unit assignments (kept in directory-routes.js, not a separate file —
 * see that file's own header) are scoped differently again from the rest of
 * the directory's write surface, and why ADR-0010's own Consequences section
 * pre-decides that an Employee holding a skill (skill-routes.js's PUT
 * /employees/:id/skills/:skillId) is administrator-only rather than
 * Org-Unit-scoped the same way.
 */

const express = require('express');
const accountRoutes = require('./routes');
const plantRoutes = require('./plant-routes');
const directoryRoutes = require('./directory-routes');
const jobRoleRoutes = require('./job-role-routes');
const skillRoutes = require('./skill-routes');
const { authenticate, requireActive } = require('./middleware');

const router = express.Router();
router.use(accountRoutes);
router.use(plantRoutes);
router.use(directoryRoutes);
router.use(jobRoleRoutes);
router.use(skillRoutes);

module.exports = { router, authenticate, requireActive };
