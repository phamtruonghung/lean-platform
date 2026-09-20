/*
 * The Safety Module's entry point (ADR-0006) — the fifth Module in this
 * backend, after People, Maintenance, Actions and Quality, and the one issue
 * #226 creates.
 *
 * One export: `router`, mounted by src/index.js under `/api/safety`, a
 * prefix of its own beside `/api/people`, `/api/maintenance`, `/api/actions`
 * and `/api/quality`. src/index.js lives outside `modules/` and is not a
 * cross-Module caller the boundary checker looks at, so like every Module's
 * `router` it is a special case of none of ADR-0006's three clauses: it is
 * how the Module becomes reachable over HTTP at all.
 *
 * Nothing else is exported, and the absence is a decision rather than an
 * omission: no lookup about a Safety incident is offered to another Module.
 * Nothing outside Safety asks one today — the Concern a later ticket raises
 * from an incident (issue #229) is exactly the shape `concern_nonconformances`
 * already is for Quality, a cross-Module read done as an ordinary SQL join
 * from the *Actions* side, not a write this Module's entry point would have
 * to expose. A sibling Module that needs Safety's own judgment about an
 * incident adds the question here at that point.
 *
 * No error plumbing and no SQL helpers. errors.js is this Module's own copy
 * (ADR-0006's third clause, "domain, not utility"), and safety-incidents.js
 * keeps its own private helpers rather than sharing them through this file.
 *
 * What this Module requires from outside itself is People's entry point and
 * nothing else (`npm run lint`'s boundary check enforces it): `authenticate`,
 * `requireActive`, `findSite`, `findOrgUnit`, `canAct` and `canSeeSite` for
 * safety-incident-routes.js's Account door, plus `findDeviceByCredential`,
 * `findValidIdentification` and `deviceReachesOrgUnit` for
 * floor-safety-incident-routes.js's floor door (issue #227) — exactly as
 * `quality/floor-routes.js` asks the same three of People for its own floor
 * door — and the shared `OUTSIDE_GRANTED_ORG_UNITS` wording, used by both.
 * `safety` requires neither `maintenance`, `quality` nor `actions`: the Asset
 * a Safety incident may name and the Employee it may name are both read by
 * ordinary SQL join (ADR-0006's "code seams, not data seams"), the same way
 * `nonconformances.js` reads `assets`.
 */

const express = require('express');
const safetyIncidentRoutes = require('./safety-incident-routes');
const floorSafetyIncidentRoutes = require('./floor-safety-incident-routes');

const router = express.Router();
router.use(safetyIncidentRoutes);
router.use(floorSafetyIncidentRoutes);

module.exports = { router };
