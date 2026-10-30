/*
 * The KPI catalogue Module's entry point (ADR-0006, ADR-0055): the MTU line's
 * KPIs, their Targets and the daily Review, kept in a second database (`mtu`,
 * schema `kpi`) that the Platform reaches through platform/mtu-db.js.
 *
 * One export: `router`, because src/index.js mounts it under `/api/kpi`.
 *
 * Nothing else is exported, and each absence is a decision:
 *
 *   - No `kpiRegistry`. Every other Module that reports a number to the tier
 *     board contributes one, so its absence here is the point. The board's
 *     registry holds the Platform's own numbers — Pillar-based, derived from
 *     records People, Maintenance, Quality, Safety and Production write, in the
 *     Platform's own database. The MTU catalogue is a different list of
 *     numbers with no Platform records behind it (its values are computed in
 *     Power BI), and merging the two is the mistake ADR-0055 exists to prevent.
 *     The Platform's own `kpi_definitions`, `kpi_targets` and `kpi_actuals` are
 *     not touched by this Module.
 *   - No lookup about a KPI is offered to another Module. Nothing outside this
 *     Module asks one; the day a sibling does, the question is added here, per
 *     ADR-0006's "questions, not commands".
 *   - No error plumbing. errors.js is this Module's own copy (see its header).
 *
 * What this Module requires from outside itself is People's entry point and
 * nothing else: the routes ask `authenticate`, `requireActive`, `canAct` and
 * `findSite`, and site-context.js reads the Site's root Org Unit by ordinary
 * SQL. The catalogue itself is read and written only through the second Pool.
 */

const express = require('express');
const catalogueRoutes = require('./catalogue-routes');
const reviewRoutes = require('./review-routes');

const router = express.Router();
router.use(catalogueRoutes);
router.use(reviewRoutes);

module.exports = { router };
