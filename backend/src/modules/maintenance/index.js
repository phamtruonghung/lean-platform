/*
 * The Maintenance Module's entry point (ADR-0006) — the second Module in this
 * backend, after People.
 *
 * Exactly one export today, and that is the honest answer rather than a
 * placeholder: ADR-0006's "What a Module's entry point may expose" governs
 * what one Module hands another, and no other Module consumes Maintenance
 * yet. `router` is the special case of none of its three clauses — it is
 * mounted by src/index.js, which lives outside `modules/` and is not a
 * cross-Module caller the boundary checker even looks at.
 *
 * The rest of this Module's chain (#57 work orders, #61 nesting and retiring,
 * #62 assignment, #63 the transitions) are all Maintenance's own files and
 * reach assets.js/work-orders.js directly, the way People's own routes reach
 * plant.js. Nothing about them belongs here.
 *
 * When a consumer does arrive — the Tier Board reading `v_asset_reliability`
 * or the open work order count — the export it gets is a question, not a
 * command, returning a value rather than throwing an HTTP-status-carrying
 * Error, and about a Maintenance record rather than a generic helper. The
 * shape to copy is People's `findOrgUnit`.
 */

const express = require('express');
const assetRoutes = require('./asset-routes');
const workOrderRoutes = require('./work-order-routes');
const requestRoutes = require('./request-routes');

const router = express.Router();
router.use(assetRoutes);
router.use(workOrderRoutes);
router.use(requestRoutes);

module.exports = { router };
