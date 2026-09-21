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
 * Issue #224 adds two catalogue route files under the same mount —
 * injury-type-routes.js and body-part-routes.js, the Injury type and Body part
 * catalogues an injury classification draws on. They are the Quality Module's
 * product-routes.js/defect-code-routes.js shape exactly: an open read for any
 * active Account, an administrator's write, no Site and no Org Unit. They
 * arrive with the classification they serve rather than ahead of it (#223's
 * revised build order), which is why this Module's first two slices needed
 * neither.
 *
 * Issue #230 adds the leading indicator's own two doors —
 * safety-observation-routes.js (the Account door) and
 * floor-safety-observation-routes.js (the floor door) — the same shape
 * #226/#227 already gave the lagging one, mounted under this same prefix.
 * Neither needs a new capability from People: recording an observation asks
 * only for a write Grant or a device's reach, and reading one asks only
 * `canSeeSite`, so this Module's requirement list below is unchanged by their
 * arrival.
 *
 * No error plumbing and no SQL helpers. errors.js is this Module's own copy
 * (ADR-0006's third clause, "domain, not utility"), and safety-incidents.js /
 * safety-observations.js each keep their own private helpers rather than
 * sharing them through this file.
 *
 * What this Module requires from outside itself is People's entry point and
 * nothing else (`npm run lint`'s boundary check enforces it): `authenticate`,
 * `requireActive`, `findSite`, `findOrgUnit`, `canAct` and `canSeeSite` for
 * safety-incident-routes.js's and safety-observation-routes.js's Account
 * doors, plus `findDeviceByCredential`, `findValidIdentification` and
 * `deviceReachesOrgUnit` for floor-safety-incident-routes.js's and
 * floor-safety-observation-routes.js's floor doors (issues #227, #230) —
 * exactly as `quality/floor-routes.js` asks the same three of People for its
 * own floor door — and the shared `OUTSIDE_GRANTED_ORG_UNITS` wording, used by
 * all four. `safety` requires neither `maintenance`, `quality` nor `actions`:
 * the Asset a Safety incident may name and the Employee either record may name
 * are both read by ordinary SQL join (ADR-0006's "code seams, not data
 * seams"), the same way `nonconformances.js` reads `assets`.
 */

const express = require('express');
const safetyIncidentRoutes = require('./safety-incident-routes');
const floorSafetyIncidentRoutes = require('./floor-safety-incident-routes');
const safetyObservationRoutes = require('./safety-observation-routes');
const floorSafetyObservationRoutes = require('./floor-safety-observation-routes');
const injuryTypeRoutes = require('./injury-type-routes');
const bodyPartRoutes = require('./body-part-routes');

const router = express.Router();
router.use(safetyIncidentRoutes);
router.use(floorSafetyIncidentRoutes);
router.use(safetyObservationRoutes);
router.use(floorSafetyObservationRoutes);
router.use(injuryTypeRoutes);
router.use(bodyPartRoutes);

module.exports = { router };
