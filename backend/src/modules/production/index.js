/*
 * The Production Module's entry point (ADR-0006), created by issue #333 as the
 * first slice of the Shift handover (spec #332, ADR-0054).
 *
 * One export, and it is not a lookup: `router` is here because src/index.js
 * mounts it under `/api/production`. src/index.js lives outside `modules/` and
 * is not a cross-Module caller the boundary checker looks at, so like every
 * Module's `router` it is how the Module becomes reachable over HTTP at all.
 *
 * Nothing else is exported, and each absence is a decision rather than an
 * omission:
 *
 *   - No lookup about a handover is offered to another Module. Nothing outside
 *     Production asks one today; the day a sibling does, the question is added
 *     here, per ADR-0006's "questions, not commands".
 *   - No `kpiRegistry` yet. ADR-0054 names `PRO_HANDOVER_COMPLETION` and
 *     `PRO_HANDOVER_ACK_MINUTES` as this Module's contribution to the tier
 *     board, and they arrive with the slice that has submitted and
 *     acknowledged handovers to count.
 *   - No error plumbing. errors.js is this Module's own copy (see its header).
 *
 * What this Module requires from outside itself is People's entry point and
 * nothing else: handover-routes.js asks `authenticate`, `requireActive` and
 * `canAct`, and reads the Section and the shift instance by ordinary SQL.
 */

const express = require('express');
const handoverRoutes = require('./handover-routes');

const router = express.Router();
router.use(handoverRoutes);

module.exports = { router };
