/*
 * The People Module's entry point (ADR-0006). Everything another Module or
 * `src/index.js` needs from People comes through here — `router` to mount,
 * `authenticate`/`requireActive` for a future Module's own protected routes —
 * never through `./service`, `./plant`, or `./middleware` directly.
 *
 * `router` combines two route files under the one `/api/people` mount:
 * routes.js (Accounts, issue #6) and plant-routes.js (Sites and the Org
 * Unit tree, issue #7). Both belong to this Module per CONTEXT.md — see
 * plant.js's own header for why Sites/Org Units live here rather than in a
 * Module of their own.
 */

const express = require('express');
const accountRoutes = require('./routes');
const plantRoutes = require('./plant-routes');
const { authenticate, requireActive } = require('./middleware');

const router = express.Router();
router.use(accountRoutes);
router.use(plantRoutes);

module.exports = { router, authenticate, requireActive };
