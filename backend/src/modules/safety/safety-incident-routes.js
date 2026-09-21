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
 *
 * **Issue #224 — the injury classification, and who may read it back.** One
 * more address, `POST /incidents/:id/classify`, gated on Safety authority like
 * the three above; and one rule that applies to **every** answer this file
 * sends, which is the more important half.
 *
 * ADR-0037: an incident's severity, type, description, immediate action and
 * the days it cost are readable by anyone who can see the Site — those are the
 * numbers the plant acts on — but the identified Employee, the Injury type and
 * the Body part are health information about one named person, and they are
 * returned only to a holder of Safety authority reaching the incident's Org
 * Unit and to the Account whose own `app_users.employee_id` IS the injured
 * Employee. Every other caller gets them **absent from the JSON**, not nulled.
 *
 * Three things about how that is enforced here:
 *
 *   - **`res.json({ incident })` and `res.json({ incidents })` appear nowhere
 *     in this file.** Every answer goes through `respondWithIncident` or
 *     `respondWithIncidents` below, including the ones a *write* returns. With
 *     ten addresses that serialise an incident, "did whoever added the
 *     eleventh remember" is the real failure mode, and a rule that is greppable
 *     is a rule that survives. A read path that does not call one of those two
 *     is a bug you can find with `grep`.
 *   - **The reader's reach is asked of People, once per request, per Site**
 *     (`people.safetyAuthorityOrgUnitIds`). It is deliberately NOT
 *     `canAct({ safety: true })`: that returns true for role `admin` before it
 *     looks at a Grant, and issue #224 names an administrator holding no
 *     Safety authority in the chain as one of the callers these fields are
 *     withheld from. The register spans many Org Units, and a reader may hold
 *     the authority at one of them and not at another, so the question is
 *     asked per row against the reach — never once per request as a single
 *     boolean.
 *   - **The write gate is still `canAct({ safety: true })`**, administrator
 *     short-circuit included, because ADR-0039 says an administrator holds
 *     that authority everywhere and #228's severity, days and close routes
 *     already ship on it. The visible consequence, which is intended rather
 *     than an oversight: an administrator with no Safety Grant reaching the
 *     Org Unit may classify an incident and gets back a 200 whose three fields
 *     are absent. ADR-0037 restricts a *read*, and the answer to a write is a
 *     read; "you may always read back what you just wrote" would be a second,
 *     weaker rule sitting beside the ADR's one rule, and it is the one a later
 *     change would copy to the eleventh route.
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

// The same refusal, said for the recording route — which has no incident to
// name yet, so it names the Org Unit the caller chose instead (issue #224).
const CLASSIFY_AUTHORITY_REQUIRED =
  'naming the injured Employee, the Injury type or the Body part needs Safety authority at that Org Unit';

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

// ADR-0037's read rule, built once per request and then asked of each row.
//
// Two ways a caller may read an incident's injury classification, and no
// third: a Grant carrying **Safety authority** that reaches the incident's own
// Org Unit, or being the injured person. The second half needs no query at
// all — `app_users.employee_id` is UNIQUE and set at Approval (ADR-0022), so
// "their own" is a real identity rather than a guess, and `req.account`
// already carries it.
//
// Returns a predicate rather than a boolean, because the register's rows span
// many Org Units and a reader may hold the authority at one and not at
// another. A single boolean for the whole request is exactly the bug this
// shape exists to rule out.
async function injuryReadPredicateFor(req, siteId) {
  const reach = new Set(
    await people.safetyAuthorityOrgUnitIds({ account: req.account, siteId })
  );
  const ownEmployeeId = req.account.employeeId ?? null;

  return function mayReadInjuryDetails(incident) {
    if (reach.has(String(incident.orgUnitId))) return true;
    if (ownEmployeeId === null) return false;
    const injured = incident.employeeId ?? null;
    return injured !== null && String(injured) === String(ownEmployeeId);
  };
}

// The only two ways this file answers with an incident. See the header: no
// route below calls `res.json` with one itself.
async function respondWithIncident(req, res, incident, { status = 200 } = {}) {
  const mayRead = await injuryReadPredicateFor(req, incident.siteId);
  res
    .status(status)
    .json({ incident: mayRead(incident) ? incident : safetyIncidents.withoutInjuryDetails(incident) });
}

async function respondWithIncidents(req, res, siteId, { incidents, truncated }) {
  const mayRead = await injuryReadPredicateFor(req, siteId);
  res.json({
    incidents: incidents.map((incident) =>
      mayRead(incident) ? incident : safetyIncidents.withoutInjuryDetails(incident)
    ),
    truncated
  });
}

// Does this request body name any part of an injury classification? Used by
// the recording route to decide whether Safety authority is needed on top of
// the write Grant recording itself needs (issue #224: "Recording or changing
// an incident's identified Employee, injury type or body part requires Safety
// authority reaching the Org Unit"). An explicit null is not naming one — it
// says "nobody", which is what an unclassified incident already holds.
const CLASSIFICATION_FIELDS = ['employeeId', 'injuryTypeId', 'bodyPartId'];

function namesAClassification(body) {
  return CLASSIFICATION_FIELDS.some(
    (field) => body[field] !== undefined && body[field] !== null && body[field] !== ''
  );
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

      const register = await safetyIncidents.listSafetyIncidents(req.site.id, {
        orgUnitPath,
        status,
        incidentType,
        severityLevel,
        isRecordable,
        from,
        to
      });

      await respondWithIncidents(req, res, req.site.id, register);
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

      const overdue = await safetyIncidents.listOverdueSafetyIncidents(req.site.id, {
        orgUnitPath
      });

      await respondWithIncidents(req, res, req.site.id, overdue);
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

      // Naming who was hurt, what the injury was or where on the body is a
      // classification, and issue #224 puts every one of the three behind
      // Safety authority whether it arrives at recording or afterwards — the
      // write Grant above is what lets this Account record an incident here at
      // all, and it is not the same standing. Asked only when the body
      // actually names one, so recording an ordinary near miss stays exactly
      // as open as #226 made it.
      if (namesAClassification(body)) {
        const mayClassify = await people.canAct({
          account: req.account,
          orgUnitId: orgUnit.id,
          safety: true
        });
        if (!mayClassify) {
          return res.status(403).json({ message: CLASSIFY_AUTHORITY_REQUIRED });
        }
      }

      const incident = await safetyIncidents.recordSafetyIncident(
        { ...body, orgUnitId: orgUnit.id },
        { accountId: req.account.id }
      );

      await respondWithIncident(req, res, incident, { status: 201 });
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
      await respondWithIncident(req, res, incident);
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
      await respondWithIncident(req, res, incident);
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
      await respondWithIncident(req, res, incident);
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
      await respondWithIncident(req, res, incident);
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// Classifying the injury (issue #224, ADR-0037): the identified Employee, the
// Injury type and the Body part. Safety authority reaching the incident's Org
// Unit — naming who was hurt and what the injury was is a judgement about a
// person, not a piece of work on the record, so it takes the same standing a
// severity correction does rather than the edit Grant recording itself needs.
//
// Its own address (`/safety/incidents/:id/classify`, the binding design
// comment on #223) rather than a field on some broader correction, because it
// is the one write in this Module whose result most callers are not allowed to
// read back — and the answer here is redacted for an unauthorised writer
// exactly as every other read is. See this file's header.
//
// An absent key leaves its field alone and an explicit null clears it;
// safety-incidents.js owns that contract and the 400s around it.
router.post(
  '/incidents/:id/classify',
  people.authenticate,
  people.requireActive,
  requireSafetyIncidentSafetyAuthority,
  async (req, res, next) => {
    try {
      const incident = await safetyIncidents.classifySafetyIncident(
        req.safetyIncident.id,
        req.body ?? {},
        req.account.id
      );
      await respondWithIncident(req, res, incident);
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
      await respondWithIncident(req, res, incident);
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
      await respondWithIncident(req, res, incident);
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

module.exports = router;
