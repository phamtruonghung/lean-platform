/*
 * The People Module's entry point (ADR-0006). Everything another Module or
 * `src/index.js` needs from People comes through here — `router` to mount,
 * `authenticate`/`requireActive` for a future Module's own protected routes —
 * never through `./service`, `./plant`, `./middleware`, or `./directory`
 * directly.
 *
 * `router` combines three route files under the one `/api/people` mount:
 * routes.js (Accounts, issue #6), plant-routes.js (Sites and the Org Unit
 * tree, issue #7), and directory-routes.js (the Employee directory,
 * issue #9). All three belong to this Module per CONTEXT.md — see
 * plant.js's own header for why Sites/Org Units live here rather than in a
 * Module of their own, and ADR-0009 for why the Employee directory is
 * readable platform-wide rather than Org-Unit-scoped the way Sites and Org
 * Units are.
 */

const express = require('express');
const accountRoutes = require('./routes');
const plantRoutes = require('./plant-routes');
const directoryRoutes = require('./directory-routes');
const { authenticate, requireActive } = require('./middleware');

const router = express.Router();
router.use(accountRoutes);
router.use(plantRoutes);
router.use(directoryRoutes);

module.exports = { router, authenticate, requireActive };
