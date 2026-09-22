/*
 * Safety observations over HTTP (issue #230) — the Account door. Mounted by
 * index.js under `/api/safety`, beside safety-incident-routes.js, and beside
 * floor-safety-observation-routes.js — the shared floor device's own door to
 * the same `recordSafetyObservation` service function, mounted under the same
 * prefix at `/floor/observations`.
 *
 * This Module talks to People only through `modules/people`'s entry point
 * (ADR-0006): `authenticate`, `requireActive`, `findSite`, `findOrgUnit`,
 * `canAct` and `canSeeSite` — exactly the set safety-incident-routes.js asks
 * for, and no more. There is no Safety-authority gate anywhere in this file:
 * #230's own acceptance criteria asks only for an edit Grant to record and
 * Site visibility to read, unlike an incident's classify/severity/close
 * addresses.
 *
 * The same asymmetry the Safety incident register keeps (ADR-0009, ADR-0032):
 *
 *   - Reading is Site-wide. `GET /sites/:siteId/observations` sits behind
 *     `authenticate` + `requireActive`, a known-Site check and
 *     `people.canSeeSite` — any Grant, read or write, on any Org Unit within
 *     the Site — and nothing else. `?orgUnitId=` narrows the list by *area*,
 *     one Org Unit and everything beneath it, never by entitlement.
 *   - Recording is a write at the Org Unit the observation was made at:
 *     `people.canAct({ …, write: true })`, true unconditionally for role
 *     `admin` — #230's own "an edit Grant reaching the Org Unit" criterion.
 *     `write: true` is spelled out because it defaults to FALSE.
 *
 * Existence before scope (AGENTS.md §6): the Site, then the Org Unit, then
 * whether that Org Unit belongs to this Site (a cross-Site Org Unit is a 404
 * here), and only then `canAct`.
 *
 * A query value that names a closed set is checked, not forwarded (ADR-0023's
 * rule read the other way round): `?observationType=oops` is a mistake the
 * caller can fix, and answering it with an empty list would hide the typo
 * behind what looks like a quiet Site. A date range is checked the same way,
 * and is interpreted as *production days* — see safety-observations.js's own
 * note on `listSafetyObservations`.
 *
 * There is no read restriction here of any kind — unlike an incident's injury
 * classification (ADR-0037), nothing about an observation is health
 * information about a named person, so `res.json` is used directly rather
 * than routed through a redacting helper the way safety-incident-routes.js's
 * `respondWithIncident`/`respondWithIncidents` are.
 */

const express = require('express');
const people = require('../people');
const safetyObservations = require('./safety-observations');
const { httpError, notFound, parseId, handleError } = require('./errors');

const router = express.Router();

// Mirrors safety-incident-routes.js's own requireKnownSite exactly: an
// unknown Site is a 404, never a silently empty 200.
async function requireKnownSite(req, res, next) {
  try {
    const site = await people.findSite(req.params.siteId);
    if (!site) throw notFound('Site');
    req.site = site;
    return next();
  } catch (error) {
    return handleError(error, res, next);
  }
}

// The Site's observations are readable by anyone who can see the Site at all
// — the same weaker of People's two questions the Safety incident register
// asks. An Account holding no Grant anywhere in the Site is refused.
async function requireSiteVisible(req, res, next) {
  try {
    const allowed = await people.canSeeSite({ account: req.account, siteId: req.site.id });
    if (!allowed) {
      return res.status(403).json({ message: people.OUTSIDE_GRANTED_ORG_UNITS });
    }
    return next();
  } catch (error) {
    return handleError(error, res, next);
  }
}

// The observation named in the URL must exist before anything else is asked
// about it — a clean 404, even for an administrator — and only then is its
// Site's visibility checked.
async function requireSafetyObservationVisible(req, res, next) {
  try {
    const observation = await safetyObservations.findSafetyObservation(req.params.id);
    if (!observation) throw notFound('Safety observation');
    const allowed = await people.canSeeSite({
      account: req.account,
      siteId: observation.siteId
    });
    if (!allowed) {
      return res.status(403).json({ message: people.OUTSIDE_GRANTED_ORG_UNITS });
    }
    req.safetyObservation = observation;
    return next();
  } catch (error) {
    return handleError(error, res, next);
  }
}

function requireQueryMemberOf(field, value, allowed) {
  if (value === undefined) return null;
  if (!allowed.includes(value)) {
    throw httpError(400, `${field} must be one of: ${allowed.join(', ')}`);
  }
  return value;
}

function requireQueryBoolean(field, value) {
  if (value === undefined) return null;
  if (value === 'true') return true;
  if (value === 'false') return false;
  throw httpError(400, `${field} must be true or false`);
}

// A date range is two `YYYY-MM-DD` days — never a timestamp, because the
// range a Safety register is read over is production days (ADR-0017), the
// same rule safety-incident-routes.js's own range follows.
const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;

function requireQueryDate(field, value) {
  if (value === undefined) return null;
  if (typeof value !== 'string' || !DATE_PATTERN.test(value)) {
    throw httpError(400, `${field} must be a date in YYYY-MM-DD form`);
  }
  return value;
}

// The register: a Site's observations, worst-first by severity potential,
// narrowed by any of the filters the ticket names. The Site is the only
// entitlement question asked; `orgUnitId` narrows by area rather than by
// scope.
router.get(
  '/sites/:siteId/observations',
  people.authenticate,
  people.requireActive,
  requireKnownSite,
  requireSiteVisible,
  async (req, res, next) => {
    try {
      const observationType = requireQueryMemberOf(
        'observationType',
        req.query.observationType,
        safetyObservations.OBSERVATION_TYPES
      );
      const category = requireQueryMemberOf('category', req.query.category, safetyObservations.CATEGORIES);
      const severityPotential = requireQueryMemberOf(
        'severityPotential',
        req.query.severityPotential,
        safetyObservations.SEVERITY_POTENTIALS
      );
      const isStopWork = requireQueryBoolean('isStopWork', req.query.isStopWork);
      const hasAction = requireQueryBoolean('hasAction', req.query.hasAction);
      const from = requireQueryDate('from', req.query.from);
      const to = requireQueryDate('to', req.query.to);

      let orgUnitPath = null;
      if (req.query.orgUnitId !== undefined) {
        const orgUnit = await people.findOrgUnit(req.query.orgUnitId);
        if (!orgUnit) throw notFound('Org Unit');
        if (orgUnit.siteId !== req.site.id) throw notFound('Org Unit');
        orgUnitPath = orgUnit.path;
      }

      const register = await safetyObservations.listSafetyObservations(req.site.id, {
        orgUnitPath,
        observationType,
        category,
        severityPotential,
        isStopWork,
        hasAction,
        from,
        to
      });

      res.json({ observations: register.observations, truncated: register.truncated });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// Recording a Safety observation (issue #230).
//
// The Org Unit is resolved here rather than in the service because it is
// another Module's record, and it is resolved *before* the Grant is asked
// about — AGENTS.md §6's ordering, so an Org Unit that is not there is a 404
// for the administrator as well as for everyone else.
router.post(
  '/sites/:siteId/observations',
  people.authenticate,
  people.requireActive,
  requireKnownSite,
  async (req, res, next) => {
    try {
      const body = req.body ?? {};

      const orgUnitId = parseId(body.orgUnitId);
      if (orgUnitId === null) {
        return res.status(400).json({ message: 'orgUnitId must be a valid Org Unit id' });
      }
      const orgUnit = await people.findOrgUnit(orgUnitId);
      if (!orgUnit) throw notFound('Org Unit');
      if (orgUnit.siteId !== req.site.id) throw notFound('Org Unit');

      const allowed = await people.canAct({
        account: req.account,
        orgUnitId: orgUnit.id,
        write: true
      });
      if (!allowed) {
        return res.status(403).json({ message: people.OUTSIDE_GRANTED_ORG_UNITS });
      }

      const observation = await safetyObservations.recordSafetyObservation(
        { ...body, orgUnitId: orgUnit.id },
        { accountId: req.account.id }
      );

      res.status(201).json({ observation });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// One Safety observation — what the detail Screen reads, together with the
// Actions raised from it (issue #231), since an observation carries no
// status of its own to say whether it was dealt with (#223 decision 9).
// Visible to anyone who can see its Site, the same rule the register follows.
router.get(
  '/observations/:id',
  people.authenticate,
  people.requireActive,
  requireSafetyObservationVisible,
  async (req, res, next) => {
    try {
      const observation = await safetyObservations.getSafetyObservationDetail(req.params.id);
      if (!observation) throw notFound('Safety observation');
      res.json({ observation });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

module.exports = router;
