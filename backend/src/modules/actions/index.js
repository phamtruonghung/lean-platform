/*
 * The Actions Module's entry point (ADR-0006). Everything another Module — or
 * `src/index.js`, which lives outside `modules/` and so is not a cross-Module
 * caller the boundary checker even looks at — needs from Actions comes through
 * here, never through `./actions`, `./action-routes` or `./errors` directly.
 *
 * Today that is `router` and nothing else. Unlike People's entry point, which
 * exports the identity middleware a second Module cannot reimplement, Actions
 * answers no question another Module currently asks: nothing reads the action
 * log except its own Screens, and the tier board's `open_action_count` is
 * still waiting on the decision ADR-0032 records (board.js computes every
 * number on read and materialises no `kpi_actuals` rows, so there is nothing
 * for an Action to point at yet). What a second Module would want — "which
 * open Actions does this Org Unit own" — is a question, and it can be exported
 * here the day a caller exists, per ADR-0006's own "questions, not commands"
 * rule. Adding it now would be a seam built for nobody.
 *
 * ADR-0032 records why this Module exists at all, and whether an Action should
 * ever be raisable from a red KPI or link to a Work order — the two links the
 * baseline's own columns leave waiting.
 */

const express = require('express');
const actionRoutes = require('./action-routes');

const router = express.Router();
router.use(actionRoutes);

module.exports = { router };
