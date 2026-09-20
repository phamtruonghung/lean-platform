/*
 * Safety incidents over HTTP (issue #226) — the Account door. Mounted by
 * index.js under `/api/safety`, beside floor-safety-incident-routes.js (issue
 * #227), the shared floor device's own door to the same
 * `recordSafetyIncident` service function, mounted under the same prefix at
 * `/floor/incidents`.
 *
 * This Module talks to People only through `modules/people`'s entry point
 * (ADR-0006): `authenticate`, `requireActive`, `findSite`, `findOrgUnit`,
 * `canAct` and `canSeeSite`, plus the shared `OUTSIDE_GRANTED_ORG_UNITS`
 * wording — exactly the set `nonconformance-routes.js` asks for, and no more.
 *
 * Two scope rules, the same asymmetry the Non-conformance register keeps
 * (ADR-0009, ADR-0032):
 *
 *   - Reading is Site-wide. `GET /sites/:siteId/incidents` sits behind
 *     `authenticate` + `requireActive`, a known-Site check and
 *     `people.canSeeSite` — any Grant, read or write, on any Org Unit within
 *     the Site — and nothing else. `?orgUnitId=` narrows the list by *area*,
 *     one Org Unit and everything beneath it, never by entitlement.
 *   - Recording is a write at the Org Unit the incident occurred at:
 *     `people.canAct({ …, write: true })`, true unconditionally for role
 *     `admin` — issue #226's own "an edit Grant reaching the Org Unit, or
 *     administrator" criterion. `write: true` is spelled out because it
 *     defaults to FALSE, and a recording route that forgot it would be
 *     authorised by any read Grant with no error anywhere to notice.
 *
 * Existence before scope, the order AGENTS.md §6 fixes: the Site, then the
 * Org Unit, then whether that Org Unit belongs to this Site (a cross-Site Org
 * Unit is a 404 here), and only then `canAct` — `canAct` returns true for
 * role `admin` before it even looks at the Org Unit id, so asking scope first
 * would turn an administrator's typo into a raw 500 rather than a clean 404.
 *
 * A query value that names a closed set is checked, not forwarded (ADR-0023's
 * rule read the other way round): `?status=cloesd` is a mistake the caller
 * can fix, and answering it with an empty list would hide the typo behind
 * what looks like a quiet Site. A date range is checked the same way, and is
 * interpreted as *production days* — see safety-incidents.js's own note on
 * `listSafetyIncidents`.
 *
 * **Issue #228 — making a recorded incident answerable.** Six more addresses
 * live here, gated on one of two standings, the same asymmetry
 * `nonconformance-routes.js` draws between a write Grant and Quality
 * authority (ADR-0035):
 *
 *   - The investigation due date and an ordinary status move need only a
 *     write Grant reaching the incident's Org Unit — the same standing
 *     recording itself needs, because neither is the judgement Safety
 *     authority exists for.
 *   - Correcting the severity, recording the days and closing each need
 *     Safety authority reaching the incident's Org Unit
 *     (`people.canAct({ …, safety: true })`, ADR-0039) — a decision about the
 *     record rather than a piece of work on it, gated with this Module's own
 *     sentence rather than People's `OUTSIDE_GRANTED_ORG_UNITS`: a caller may
 *     be well inside their granted Org Units and simply not hold the
 *     authority, and telling them the wrong thing sends them to the wrong
 *     person to ask.
 *
 * Every one of the six resolves existence and visibility first
 * (`requireKnownSafetyIncident` → `requireSafetyIncidentVisible`) and only
 * then asks the standing it needs, the same order the register's own detail
 * route follows and AGENTS.md §6 fixes.
 */

const express = require('express');
const people = require('../people');
const safetyIncidents = require('./safety-incidents');
const { httpError, notFound, parseId, handleError } = require('./errors');

const router = express.Router();

// Mirrors nonconformance-routes.js's own requireKnownSite exactly: an unknown
// Site is a 404, never a silently empty 200.
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

// The Site's incidents are readable by anyone who can see the Site at all —
// the same weaker of People's two questions the Non-conformance register
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

// The incident named in the URL must exist before anything else is asked
// about it — a clean 404, even for an administrator — and only then is its
// Site's visibility checked.
async function requireKnownSafetyIncident(req, res, next) {
  try {
    const incident = await safetyIncidents.findSafetyIncident(req.params.id);
    if (!incident) throw notFound('Safety incident');
    req.safetyIncident = incident;
    return next();
  } catch (error) {
    return handleError(error, res, next);
  }
}

async function requireSafetyIncidentVisible(req, res, next) {
  return requireKnownSafetyIncident(req, res, async () => {
    const allowed = await people.canSeeSite({
      account: req.account,
      siteId: req.safetyIncident.siteId
    });
    if (!allowed) {
      return res.status(403).json({ message: people.OUTSIDE_GRANTED_ORG_UNITS });
    }
    return next();
  });
}

// The write-scope half (issue #228): a write Grant reaching the Org Unit the
// incident sits at, never a read one — the same standing recording itself
// needs. Existence and visibility first, so `canAct` is never asked about a
// null id.
async function requireSafetyIncidentWriteScope(req, res, next) {
  return requireSafetyIncidentVisible(req, res, async () => {
    const allowed = await people.canAct({
      account: req.account,
      orgUnitId: req.safetyIncident.orgUnitId,
      write: true
    });
    if (!allowed) {
      return res.status(403).json({ message: people.OUTSIDE_GRANTED_ORG_UNITS });
    }
    return next();
  });
}

// Safety authority (issue #228, ADR-0039): the standing to classify, correct
// and close, carried on a Grant independently of its level and reaching
// downward like the Grant does. Existence and visibility come first for the
// same reason as everywhere else, and the refusal is a sentence of this
// Module's own rather than People's `OUTSIDE_GRANTED_ORG_UNITS`: the caller
// may well be inside their granted Org Units and simply not hold this
// authority.
const SAFETY_AUTHORITY_REQUIRED =
  "that decision needs Safety authority at this Safety incident's Org Unit";

async function requireSafetyIncidentSafetyAuthority(req, res, next) {
  return requireSafetyIncidentVisible(req, res, async () => {
    const allowed = await people.canAct({
      account: req.account,
      orgUnitId: req.safetyIncident.orgUnitId,
      safety: true
    });
    if (!allowed) {
      return res.status(403).json({ message: SAFETY_AUTHORITY_REQUIRED });
    }
    return next();
  });
}

function requireQueryMemberOf(field, value, allowed) {
  if (value === undefined) return null;
  if (!allowed.includes(value)) {
    throw httpError(400, `${field} must be one of: ${allowed.join(', ')}`);
  }
  return value;
}

function requireQueryId(field, value) {
  if (value === undefined) return null;
  const parsed = parseId(value);
  if (parsed === null) throw httpError(400, `${field} must be a valid id`);
  return parsed;
}

function requireQueryBoolean(field, value) {
  if (value === undefined) return null;
  if (value === 'true') return true;
  if (value === 'false') return false;
  throw httpError(400, `${field} must be true or false`);
}

// A date range is two `YYYY-MM-DD` days — never a timestamp, because the
// range a Safety register is read over is production days (ADR-0017), the
// same rule nonconformance-routes.js's own range follows.
const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;

function requireQueryDate(field, value) {
  if (value === undefined) return null;
  if (typeof value !== 'string' || !DATE_PATTERN.test(value)) {
    throw httpError(400, `${field} must be a date in YYYY-MM-DD form`);
  }
  return value;
}

// The register: a Site's incidents, newest first, narrowed by any of the
// filters the ticket names. The Site is the only entitlement question asked;
// `orgUnitId` narrows by area rather than by scope.
router.get(
  '/sites/:siteId/incidents',
  people.authenticate,
  people.requireActive,
  requireKnownSite,
  requireSiteVisible,
  async (req, res, next) => {
    try {
      const status = requireQueryMemberOf('status', req.query.status, [
        'open',
        'investigating',
        'actions_pending',
        'closed'
      ]);
      const incidentType = requireQueryMemberOf(
        'incidentType',
        req.query.incidentType,
        safetyIncidents.INCIDENT_TYPES
      );
      const severityLevel = requireQueryMemberOf(
        'severityLevel',
        req.query.severityLevel,
        safetyIncidents.SEVERITY_LEVELS
      );
      const isRecordable = requireQueryBoolean('isRecordable', req.query.isRecordable);
      const from = requireQueryDate('from', req.query.from);
      const to = requireQueryDate('to', req.query.to);

      let orgUnitPath = null;
      if (req.query.orgUnitId !== undefined) {
        const orgUnit = await people.findOrgUnit(req.query.orgUnitId);
        if (!orgUnit) throw notFound('Org Unit');
        if (orgUnit.siteId !== req.site.id) throw notFound('Org Unit');
        orgUnitPath = orgUnit.path;
      }

      const { incidents, truncated } = await safetyIncidents.listSafetyIncidents(req.site.id, {
        orgUnitPath,
        status,
        incidentType,
        severityLevel,
        isRecordable,
        from,
        to
      });

      res.json({ incidents, truncated });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// The overdue listing (issue #228): incidents past `investigation_due_at`
// and not `closed`, for an Org Unit and everything beneath it. A distinct
// address rather than a `?overdue=true` filter on the register above, because
// it answers a different question — a worklist of what has stalled, not a
// narrowed read of everything — and `/sites/:siteId/incidents/overdue` is a
// literal path segment Express matches before it ever tries the register's
// own handler, so the two never compete. Visibility is the same weaker
// question the register itself asks: anyone who can see the Site.
router.get(
  '/sites/:siteId/incidents/overdue',
  people.authenticate,
  people.requireActive,
  requireKnownSite,
  requireSiteVisible,
  async (req, res, next) => {
    try {
      let orgUnitPath = null;
      if (req.query.orgUnitId !== undefined) {
        const orgUnit = await people.findOrgUnit(req.query.orgUnitId);
        if (!orgUnit) throw notFound('Org Unit');
        if (orgUnit.siteId !== req.site.id) throw notFound('Org Unit');
        orgUnitPath = orgUnit.path;
      }

      const { incidents, truncated } = await safetyIncidents.listOverdueSafetyIncidents(
        req.site.id,
        { orgUnitPath }
      );

      res.json({ incidents, truncated });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// Recording a Safety incident (issue #226).
//
// The Org Unit is resolved here rather than in the service because it is
// another Module's record, and it is resolved *before* the Grant is asked
// about — AGENTS.md §6's ordering, so an Org Unit that is not there is a 404
// for the administrator as well as for everyone else.
router.post(
  '/sites/:siteId/incidents',
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

      const incident = await safetyIncidents.recordSafetyIncident(
        { ...body, orgUnitId: orgUnit.id },
        { accountId: req.account.id }
      );

      res.status(201).json({ incident });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// One Safety incident — what the detail Screen reads. Visible to anyone who
// can see its Site, the same rule the register follows.
router.get(
  '/incidents/:id',
  people.authenticate,
  people.requireActive,
  requireSafetyIncidentVisible,
  async (req, res, next) => {
    try {
      const incident = await safetyIncidents.getSafetyIncidentDetail(req.params.id);
      if (!incident) throw notFound('Safety incident');
      res.json({ incident });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// The investigation due date, set or changed (issue #228). A write Grant
// reaching the Org Unit — the same standing recording itself needs — because
// setting a deadline is not the judgement Safety authority exists for.
router.patch(
  '/incidents/:id/investigation-due-date',
  people.authenticate,
  people.requireActive,
  requireSafetyIncidentWriteScope,
  async (req, res, next) => {
    try {
      const incident = await safetyIncidents.setInvestigationDueDate(
        req.safetyIncident.id,
        req.body ?? {},
        req.account.id
      );
      res.json({ incident });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// An ordinary status move (issue #228): open -> investigating ->
// actions_pending. Closing is its own address below, gated on Safety
// authority rather than a write Grant, because closing is a decision this
// one is not.
router.post(
  '/incidents/:id/status',
  people.authenticate,
  people.requireActive,
  requireSafetyIncidentWriteScope,
  async (req, res, next) => {
    try {
      const incident = await safetyIncidents.moveSafetyIncidentStatus(
        req.safetyIncident.id,
        req.body ?? {},
        req.account.id
      );
      res.json({ incident });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// Correcting the severity level (issue #228, #223 decision 5). Safety
// authority and a note.
router.post(
  '/incidents/:id/severity',
  people.authenticate,
  people.requireActive,
  requireSafetyIncidentSafetyAuthority,
  async (req, res, next) => {
    try {
      const incident = await safetyIncidents.changeSafetyIncidentSeverity(
        req.safetyIncident.id,
        req.body ?? {},
        req.account.id
      );
      res.json({ incident });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// Recording what the injury cost (issue #228): the lost-time and restricted
// days. Safety authority — the same standing that classifies an injury and
// closes the record.
router.post(
  '/incidents/:id/days',
  people.authenticate,
  people.requireActive,
  requireSafetyIncidentSafetyAuthority,
  async (req, res, next) => {
    try {
      const incident = await safetyIncidents.recordSafetyIncidentDays(
        req.safetyIncident.id,
        req.body ?? {},
        req.account.id
      );
      res.json({ incident });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// Closing (issue #228, #223 decision 4) — the judgement of someone
// accountable for the place. Safety authority, a note, and the days settled
// for any rung above the no-injury one; never refused for an open Concern.
router.post(
  '/incidents/:id/close',
  people.authenticate,
  people.requireActive,
  requireSafetyIncidentSafetyAuthority,
  async (req, res, next) => {
    try {
      const incident = await safetyIncidents.closeSafetyIncident(
        req.safetyIncident.id,
        req.body ?? {},
        req.account.id
      );
      res.json({ incident });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

module.exports = router;
