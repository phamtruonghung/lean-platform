/*
 * The Production Module's entry point (ADR-0006), created by issue #333 as the
 * first slice of the Shift handover (spec #332, ADR-0054).
 *
 * Two exports, neither of them a lookup:
 *
 *   - `router` is here because src/index.js mounts it under `/api/production`.
 *     src/index.js lives outside `modules/` and is not a cross-Module caller
 *     the boundary checker looks at, so like every Module's `router` it is how
 *     the Module becomes reachable over HTTP at all.
 *   - `kpiRegistry` (issue #340) is this Module's contribution to the tier
 *     board — `PRO_HANDOVER_COMPLETION` and `PRO_HANDOVER_ACK_MINUTES`, as
 *     ADR-0054 names them — spread into the one registry at src/index.js the
 *     way every other Module's is. It is a read-only value about records this
 *     Module owns, which ADR-0006 allows an entry point to expose;
 *     kpi-registry.js argues both entries.
 *
 * Nothing else is exported, and each absence is a decision rather than an
 * omission:
 *
 *   - No lookup about a handover is offered to another Module. Nothing outside
 *     Production asks one today; the day a sibling does, the question is added
 *     here, per ADR-0006's "questions, not commands".
 *   - No error plumbing. errors.js is this Module's own copy (see its header).
 *
 * What this Module requires from outside itself is People's entry point and
 * nothing else: handover-routes.js asks `authenticate`, `requireActive` and
 * `canAct`, and reads the Section and the shift instance by ordinary SQL.
 */

const express = require('express');
const handoverRoutes = require('./handover-routes');
const kpiRegistry = require('./kpi-registry');

const router = express.Router();
router.use(handoverRoutes);

module.exports = { router, kpiRegistry };
