/*
 * The action log over HTTP (issue #176). Mounted by index.js under
 * `/api/actions`.
 *
 * This is the one file in the Module that talks to People, and it does so only
 * through `modules/people`'s entry point (ADR-0006): `authenticate`,
 * `requireActive`, `findSite`, `findOrgUnit`, `findEmployee`, `canAct`,
 * `canSeeSite` and the shared `OUTSIDE_GRANTED_ORG_UNITS` wording. Everything
 * else about an Action is actions.js's own business.
 *
 * Two scope rules, and they are deliberately different (ADR-0032):
 *
 *   - The register is Site-wide. GET /sites/:siteId/actions sits behind
 *     `authenticate` + `requireActive` and a known-Site check and nothing else
 *     — no role check, no Grant filter, no per-row canAct. That is the rule the
 *     Work order list, the Asset register and the tier board already follow
 *     (#55, ADR-0009): Org Unit scope decides where an Account may act, not
 *     what it may know about. `?orgUnitId=` narrows the list by *area*, never
 *     by entitlement.
 *   - Raising is split by kind, because a Concern is a report and everything
 *     else is a decision (#198, CONTEXT.md's Concern entry). A Concern may be
 *     raised at any Org Unit of a Site the caller can see — `people.canSeeSite`,
 *     the same predicate GET /sites filters by (any Grant, read or write, on
 *     any Org Unit within the Site) — whether or not a Grant reaches the Org
 *     Unit it names: the operator granted on Line 2 who finds a defect that
 *     came from Line 1 raises it at Line 1. Every other kind of Action
 *     (containment, countermeasure, preventive, improvement, routine) keeps
 *     exactly the Grant check it had before #198: `people.canAct({ …,
 *     write: false })` at the Org Unit it is raised at, so it still needs a
 *     Grant reaching that Org Unit. Nothing that changes an Action *after* it
 *     is raised moved either — that is all still `write: true` at the Org Unit
 *     in question, which is why `write: false` below is spelled out rather
 *     than left implicit.
 *
 * Existence before scope, in both cases, which is issue #8's 403-vs-404
 * ordering and AGENTS.md §6's fixed order: the Site, then the Org Unit, then
 * whether it belongs to this Site (a cross-Site Org Unit is a 404 here, the
 * same answer board-routes.js gives — from this endpoint's point of view there
 * is no such Org Unit in this Site), and only then canAct.
 */

const express = require('express');
const people = require('../people');
const actions = require('./actions');
const { httpError, notFound, parseId, handleError } = require('./errors');

const router = express.Router();

// Mirrors asset-routes.js's and board-routes.js's own requireKnownSite
// exactly: an unknown Site is a 404, never a silently empty 200.
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

// A query value that names a closed set is checked, not forwarded (ADR-0023's
// rule read the other way round): `status=opne` is a mistake the caller can
// fix, and answering it with an empty list would hide the typo behind what
// looks like a quiet Site.
function requireQueryMemberOf(field, value, allowed) {
  if (value === undefined) return null;
  if (!allowed.includes(value)) {
    throw httpError(400, `${field} must be one of: ${allowed.join(', ')}`);
  }
  return value;
}

// Write scope on the Action named in the URL (issue #177) — the counterpart of
// the raise route's own scope check, and the rule everything that changes an
// Action *after* it is raised follows. Stricter than raising a Concern is on
// purpose: a write Grant reaching the Org Unit, never a read one (see the raise
// route below and this file's header).
//
// Existence before scope, the order AGENTS.md §6 fixes: an unknown or malformed
// id is a clean 404 (findAction is total, so a raw :id never reaches Postgres
// as a BIGINT parameter), and only then is `canAct` asked — with `write: true`
// spelled out, since it defaults to FALSE and a write handler that forgets it
// would be authorised by any read Grant with no error anywhere.
async function requireKnownAction(req, res, next) {
  try {
    const action = await actions.findAction(req.params.id);
    if (!action) throw notFound('Action');
    req.action = action;
    return next();
  } catch (error) {
    return handleError(error, res, next);
  }
}

// The write-scope half, for the routes that change the Action itself: a write
// Grant reaching the Org Unit it sits at. `requireKnownAction` above resolves
// existence first, so `canAct` is never asked about a null id (which it would
// answer `true` for an administrator).
//
// The measures route deliberately does NOT use this — see its own comment: a
// measure is a NEW record somewhere else, and the Grant it needs is the one
// covering where that record goes.
async function requireActionWriteScope(req, res, next) {
  return requireKnownAction(req, res, async () => {
    const allowed = await people.canAct({
      account: req.account,
      orgUnitId: req.action.orgUnitId,
      write: true
    });
    if (!allowed) {
      return res.status(403).json({ message: people.OUTSIDE_GRANTED_ORG_UNITS });
    }
    return next();
  });
}

function requireQueryId(field, value) {
  if (value === undefined) return null;
  const parsed = parseId(value);
  if (parsed === null) throw httpError(400, `${field} must be a valid id`);
  return parsed;
}

// The CAPA (issue #209, ADR-0034) — opening one on a Concern, reading one and
// changing its team and its problem description.
//
// The authority is Quality authority at the CAPA's Org Unit (ADR-0035), asked
// through People's entry point exactly as the quality Module's four gated acts
// ask it (`canAct({ …, quality: true })`, issue #206) — a CAPA is a judgement
// about a problem rather than a piece of work on it, and ADR-0035's own list of
// the decisions it guards names "opening a CAPA" first. It is deliberately NOT
// `write: true`: the two flags are independent, and a caller who may record
// work on a line is not therefore the one who decides the line needs an 8D.
//
// Opening asks it at the **Concern's** Org Unit and the two changes ask it at
// the **CAPA's**, which are the same Org Unit until somebody escalates the
// Concern — and identical again afterwards, because the investigation follows
// the problem (actions.js's escalateAction). Asking about the row being changed
// is what makes the question answerable at all: "may you do this here" needs a
// here.
const OPEN_CAPA_AUTHORITY_REQUIRED =
  "opening a CAPA needs Quality authority at this Concern's Org Unit";
const CHANGE_CAPA_AUTHORITY_REQUIRED =
  "changing a CAPA needs Quality authority at its Org Unit";

// The Employee named for a CAPA's team — the lead or one of the members —
// resolved in the order every other Action's owner is: parseId (400) ->
// findEmployee (404) -> isActive (409). People's directory is the record of who
// works here, so a departed Employee is refused here rather than by a database
// constraint nobody reads, and the refusal says what the person would
// otherwise have been given.
async function requireActiveCapaTeamEmployee(value, field) {
  const employeeId = parseId(value);
  if (employeeId === null) {
    throw httpError(400, `${field} must be a valid Employee id`);
  }
  const employee = await people.findEmployee(employeeId);
  if (!employee) throw notFound('Employee');
  if (!employee.isActive) {
    throw httpError(
      409,
      'this Employee has departed and cannot be given a place on a CAPA team'
    );
  }
  return employeeId;
}

// A CAPA named in the URL, for the two addresses that change or read one. Like
// requireKnownAction: existence first, so `canAct` is never asked about a null
// id (which it answers `true` for an administrator), and a malformed or unknown
// id is a clean 404 — findCapa is total, so a raw :id never reaches Postgres as
// a BIGINT parameter.
async function requireKnownCapa(req, res, next) {
  try {
    const capa = await actions.findCapa(req.params.id);
    if (!capa) throw notFound('CAPA');
    req.capa = capa;
    return next();
  } catch (error) {
    return handleError(error, res, next);
  }
}

async function requireCapaQualityAuthority(req, res, next) {
  return requireKnownCapa(req, res, async () => {
    const allowed = await people.canAct({
      account: req.account,
      orgUnitId: req.capa.orgUnitId,
      quality: true
    });
    if (!allowed) {
      return res.status(403).json({ message: CHANGE_CAPA_AUTHORITY_REQUIRED });
    }
    return next();
  });
}

// Who may write a CAPA's 5 Why chains (issue #210): somebody with **edit access
// at the CAPA's Org Unit**, or **a place on the CAPA's team** — and that "or" is
// the whole rule.
//
// It is not the authority above, and deliberately so. Opening or changing an
// investigation is a Quality authority decision (ADR-0035: "opening a CAPA,
// verify one held"), but the chain is not a decision about the plant — it is
// the team's own reasoning, written by the people doing it. The team lead who
// is not a Grant-holder is exactly who the ticket means: an engineer with a
// place on the team writes the chain, and one with neither a Grant reaching the
// Org Unit nor a place on the team gets a 403 rather than a quiet read-only
// chain.
//
// `write: true`, spelled out, because the default is false and a read Grant is
// not edit access. The team half reads the Employee link on the caller's own
// Account (`app_users.employee_id`, which an Account need not have — an
// administrator is not necessarily an Employee) against the team ids
// `findCapa` already resolved. An administrator passes the first half
// everywhere, through `canAct`, like every other gate in this Platform.
//
// Existence before scope, and scope before status: an unknown CAPA is a 404
// here, and the CAPA's own status is the service's 409 under its own lock
// (actions.js's `lockOpenCapa`), so a closed investigation is refused in the
// same words whether the caller may write it or not — the read a route would
// do to answer that would be a second read racing the write.
const CAPA_WHY_WRITE_REQUIRED =
  "writing a CAPA's root causes needs edit access at its Org Unit, or a place on its team";

async function requireCapaWhyWrite(req, res, next) {
  return requireKnownCapa(req, res, async () => {
    const allowed = await people.canAct({
      account: req.account,
      orgUnitId: req.capa.orgUnitId,
      write: true
    });
    if (allowed) return next();

    const employeeId = req.account.employeeId;
    if (
      employeeId !== null &&
      employeeId !== undefined &&
      req.capa.teamEmployeeIds.includes(String(employeeId))
    ) {
      return next();
    }

    return res.status(403).json({ message: CAPA_WHY_WRITE_REQUIRED });
  });
}

// Who may record a CAPA's effectiveness check (issue #211, ADR-0034): a holder
// of **Quality authority at the CAPA's Org Unit**, who is **not the team
// lead**.
//
// The first half needs no new question — ADR-0035's own list of the decisions
// Quality authority guards names "opening a CAPA" and "verify one held", and
// this is the second of them, asked through People's entry point exactly as the
// open route asks the first (`canAct({ …, quality: true })`, deliberately not
// `write: true`: the two flags are independent, and whoever may record work on
// a line is not therefore the one who decides the fix held). An administrator
// passes through `canAct` like every other gate in this Platform.
//
// The second half is why this is not simply `requireCapaQualityAuthority`. The
// team lead is the one person whose judgement about this fix is not evidence:
// they led the investigation, they decided the countermeasure, and asking them
// whether it held is the plant marking its own homework — which is the failure
// ADR-0034's shape exists to avoid, since the whole point of the check is that
// it is somebody else's. It is a rule about an Account's *Employee link*
// (`app_users.employee_id`, which an Account need not have at all): the
// administrator with no Employee is never the team lead, and neither is the
// engineer who holds the authority and sits on the team as a member. A member
// is exactly who may record the check.
//
// Existence before scope, the order AGENTS.md §6 fixes: an unknown or malformed
// CAPA is a clean 404 first, and only then are the two authorities asked.
// Nothing here reads the CAPA's status — that is the service's 409, under its
// own lock, for the same reason `requireCapaWhyWrite` leaves it there.
const CAPA_EFFECTIVENESS_AUTHORITY_REQUIRED =
  "recording a CAPA's effectiveness check needs Quality authority at its Org Unit";
const CAPA_TEAM_LEAD_CANNOT_VERIFY =
  'the team lead cannot record the effectiveness check on their own CAPA';

async function requireCapaEffectivenessAuthority(req, res, next) {
  return requireKnownCapa(req, res, async () => {
    const allowed = await people.canAct({
      account: req.account,
      orgUnitId: req.capa.orgUnitId,
      quality: true
    });
    if (!allowed) {
      return res.status(403).json({ message: CAPA_EFFECTIVENESS_AUTHORITY_REQUIRED });
    }

    const employeeId = req.account.employeeId;
    if (
      employeeId !== null &&
      employeeId !== undefined &&
      req.capa.teamLeadEmployeeId !== null &&
      String(employeeId) === req.capa.teamLeadEmployeeId
    ) {
      return res.status(403).json({ message: CAPA_TEAM_LEAD_CANNOT_VERIFY });
    }

    return next();
  });
}

// The register: a Site's open Actions, worst first, history on request.
router.get(
  '/sites/:siteId/actions',
  people.authenticate,
  people.requireActive,
  requireKnownSite,
  async (req, res, next) => {
    try {
      const status = requireQueryMemberOf('status', req.query.status, actions.ACTION_STATUSES);
      const actionType = requireQueryMemberOf(
        'actionType',
        req.query.actionType,
        actions.ACTION_TYPES
      );
      const ownerEmployeeId = requireQueryId('ownerEmployeeId', req.query.ownerEmployeeId);
      const escalatedToOrgUnitId = requireQueryId(
        'escalatedToOrgUnitId',
        req.query.escalatedToOrgUnitId
      );
      // Only the exact string 'true' counts — absent, 'false' or garbage all
      // mean "no", the same convenience-filter rule assets.js's own
      // `includeRetired` follows. It is a filter over an already-visible
      // register, not a value a caller could be wrong about in a way worth a
      // 400 for.
      const includeHistory = req.query.includeHistory === 'true';

      let pillarCode = null;
      if (req.query.pillarCode !== undefined) {
        const pillars = await actions.listPillars();
        pillarCode = requireQueryMemberOf(
          'pillarCode',
          req.query.pillarCode,
          pillars.map((pillar) => pillar.code)
        );
      }

      let orgUnitPath = null;
      if (req.query.orgUnitId !== undefined) {
        const orgUnit = await people.findOrgUnit(req.query.orgUnitId);
        if (!orgUnit) throw notFound('Org Unit');
        if (orgUnit.siteId !== req.site.id) throw notFound('Org Unit');
        orgUnitPath = orgUnit.path;
      }

      const { actions: rows, truncated } = await actions.listActionsAtSite(req.site.id, {
        orgUnitPath,
        status,
        actionType,
        ownerEmployeeId,
        pillarCode,
        escalatedToOrgUnitId,
        includeHistory
      });

      res.json({ actions: rows, truncated });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// Raising an Action (issue #176, #198).
//
// Two scope questions, one per kind, and which one is asked turns on whether
// the caller is raising a Concern:
//
//   - `concern` (the default, and what a POST without an `actionType` raises):
//     `people.canSeeSite` — any Grant, read or write, on any Org Unit within
//     the Site in the path. Nothing is asked about the Org Unit the Concern is
//     raised at, because CONTEXT.md's Concern entry is explicit that anyone on
//     the floor may raise one where they found it "whether or not they hold a
//     Grant reaching that Org Unit: a concern is a report, not a decision"
//     (#198). The operator granted on Line 2 whose defect came from Line 1 is
//     the case this exists for, and an Account holding no Grant anywhere in
//     the Site is still refused.
//   - every other kind, and every unrecognised value: `people.canAct({ …,
//     write: false })` at the Org Unit named in the body — unchanged by #198.
//     A Containment, Countermeasure, Preventive, Improvement or Routine action
//     is a decision rather than a report, and still needs a Grant reaching the
//     Org Unit it is raised at. `write: false` is spelled out so that a reader
//     can see which check each kind gets: the default is already false, so
//     this is a read Grant by intent rather than by omission, and a future
//     `write: true` here would be a deliberate tightening of these five kinds
//     rather than a silent fix.
//
// An unrecognised `actionType` deliberately takes the second path rather than a
// 400 raised here: which types exist is actions.js's knowledge (ACTION_TYPES,
// mirroring the schema's CHECK), and naming a bad one is still a 400 from
// there, exactly as it was before #198. Deciding scope first would otherwise
// have to invent an answer for a type the Module does not know.
//
// The Employee named as owner is resolved here rather than in actions.js,
// because it is another Module's record: parseId (400) -> findEmployee (404) ->
// isActive (409), the exact order PUT /work-orders/:id/assignee already uses,
// so a departed Employee is refused in the same words in both Modules.
router.post(
  '/sites/:siteId/actions',
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

      const actionType = body.actionType ?? 'concern';

      const allowed = actionType === 'concern'
        ? await people.canSeeSite({ account: req.account, siteId: req.site.id })
        : await people.canAct({ account: req.account, orgUnitId: orgUnit.id, write: false });
      if (!allowed) {
        return res.status(403).json({ message: people.OUTSIDE_GRANTED_ORG_UNITS });
      }

      let ownerEmployeeId = null;
      if (body.ownerEmployeeId !== undefined && body.ownerEmployeeId !== null) {
        ownerEmployeeId = parseId(body.ownerEmployeeId);
        if (ownerEmployeeId === null) {
          return res.status(400).json({ message: 'ownerEmployeeId must be a valid Employee id' });
        }
        const employee = await people.findEmployee(ownerEmployeeId);
        if (!employee) throw notFound('Employee');
        if (!employee.isActive) {
          throw httpError(409, 'this Employee has departed and cannot be given an Action');
        }
      }

      const action = await actions.createAction(
        {
          orgUnitId: orgUnit.id,
          title: body.title,
          description: body.description ?? null,
          actionType,
          pillarCode: body.pillarCode ?? null,
          ownerEmployeeId,
          dueDate: body.dueDate ?? null,
          priority: body.priority ?? 3
        },
        req.account.id,
        { raisedBy: req.account.employeeId ?? null }
      );

      res.status(201).json({ action });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// Raising a Concern from a Non-conformance (issue #208).
//
// Three addresses in this file belong to that link, and they are `actions`'
// own for the reason actions.js's header argues at length: a Concern is this
// Module's record, its creation rules (number, title, cycle-1 Plan,
// `raised_by`) are this Module's knowledge, and ADR-0006's clause on entry
// points means the Quality Module could not be given a write to perform here
// even if it could reach this Module. So the Quality Module's own routes read
// the link by SQL join and never write it, and the writes live here.
//
// This one is deliberately NOT the register's own raise route with a
// Non-conformance in the body. The Org Unit is not the caller's choice — the
// Concern lands at the Non-conformance's own Org Unit, because a problem is
// solved where it happened — so an address that took an `orgUnitId` would be
// offering a field whose only correct value is one the server already knows.
// The scope question is #198's rule for a Concern and not a new one:
// `people.canSeeSite` about the Non-conformance's Site, since a Concern is a
// report rather than a decision. Everything else about the request — the
// title, the optional fields, the Employee named as owner — is the register's
// own shape, resolved the same way and in the same order.
router.post(
  '/nonconformances/:id/concern',
  people.authenticate,
  people.requireActive,
  async (req, res, next) => {
    try {
      const body = req.body ?? {};

      const nonconformance = await actions.findNonconformanceForConcern(req.params.id);
      if (!nonconformance) throw notFound('Non-conformance');

      const allowed = await people.canSeeSite({
        account: req.account,
        siteId: nonconformance.siteId
      });
      if (!allowed) {
        return res.status(403).json({ message: people.OUTSIDE_GRANTED_ORG_UNITS });
      }

      let ownerEmployeeId = null;
      if (body.ownerEmployeeId !== undefined && body.ownerEmployeeId !== null) {
        ownerEmployeeId = parseId(body.ownerEmployeeId);
        if (ownerEmployeeId === null) {
          return res.status(400).json({ message: 'ownerEmployeeId must be a valid Employee id' });
        }
        const employee = await people.findEmployee(ownerEmployeeId);
        if (!employee) throw notFound('Employee');
        if (!employee.isActive) {
          throw httpError(409, 'this Employee has departed and cannot be given an Action');
        }
      }

      const action = await actions.raiseConcernFromNonconformance(
        nonconformance.id,
        {
          title: body.title,
          description: body.description ?? null,
          pillarCode: body.pillarCode ?? null,
          ownerEmployeeId,
          dueDate: body.dueDate ?? null,
          priority: body.priority ?? 3
        },
        req.account.id,
        { raisedBy: req.account.employeeId ?? null }
      );

      res.status(201).json({ action });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// Raising a Concern from a Safety incident (issue #229).
//
// Mirrors the Non-conformance route immediately above, field for field, for
// the reason actions.js's own header gives at length: `safety` requires only
// `people`'s entry point and cannot write the Action log itself, and a
// Concern's own creation rules (number, title, `raised_by`, cycle-1 Plan) are
// this Module's knowledge. The one difference is the source column set on the
// write — `safetyIncidentId` rather than `qualityIssueId` — and there is no
// link-table half to this act: #229's own acceptance criteria ask for the
// source column and nothing more, unlike a Non-conformance's Concern, which
// may gather further occurrences after the first.
//
// The Org Unit is not the caller's choice, for the same reason: the Concern
// lands at the incident's own Org Unit, because a problem is solved where it
// happened. The scope question is #198's Concern rule, read about the
// incident's Site rather than a Non-conformance's: `people.canSeeSite`, never
// a Grant — a concern is a report, not a decision.
router.post(
  '/safety-incidents/:id/concern',
  people.authenticate,
  people.requireActive,
  async (req, res, next) => {
    try {
      const body = req.body ?? {};

      const incident = await actions.findSafetyIncidentForConcern(req.params.id);
      if (!incident) throw notFound('Safety incident');

      const allowed = await people.canSeeSite({
        account: req.account,
        siteId: incident.siteId
      });
      if (!allowed) {
        return res.status(403).json({ message: people.OUTSIDE_GRANTED_ORG_UNITS });
      }

      let ownerEmployeeId = null;
      if (body.ownerEmployeeId !== undefined && body.ownerEmployeeId !== null) {
        ownerEmployeeId = parseId(body.ownerEmployeeId);
        if (ownerEmployeeId === null) {
          return res.status(400).json({ message: 'ownerEmployeeId must be a valid Employee id' });
        }
        const employee = await people.findEmployee(ownerEmployeeId);
        if (!employee) throw notFound('Employee');
        if (!employee.isActive) {
          throw httpError(409, 'this Employee has departed and cannot be given an Action');
        }
      }

      const action = await actions.raiseConcernFromSafetyIncident(
        incident.id,
        {
          title: body.title,
          description: body.description ?? null,
          pillarCode: body.pillarCode ?? null,
          ownerEmployeeId,
          dueDate: body.dueDate ?? null,
          priority: body.priority ?? 3
        },
        req.account.id,
        { raisedBy: req.account.employeeId ?? null }
      );

      res.status(201).json({ action });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// Linking a further Non-conformance to an existing Concern (issue #208).
//
// Two permissions, and they are the two the act actually needs. The Concern
// is being changed, so the caller needs the Action log's own rule for that —
// a write Grant reaching its Org Unit, which `requireActionWriteScope`
// already asks and which is the same question completing a phase or calling a
// Concern off asks. The Non-conformance is only *read*, and read is Site-wide
// in the Quality Module, so what is asked of it is `people.canSeeSite` about
// its Site: linking an occurrence nobody may look at would be a link a reader
// cannot follow. That pair, rather than a write Grant at both Org Units: the
// Asset move needs a Grant at both ends because both records change, and
// nothing about the Non-conformance changes here.
router.post(
  '/:id/nonconformances',
  people.authenticate,
  people.requireActive,
  requireActionWriteScope,
  async (req, res, next) => {
    try {
      const body = req.body ?? {};
      const nonconformanceId = parseId(body.nonconformanceId);
      if (nonconformanceId === null) {
        return res.status(400).json({ message: 'nonconformanceId must be a valid Non-conformance id' });
      }

      const nonconformance = await actions.findNonconformanceForConcern(nonconformanceId);
      if (!nonconformance) throw notFound('Non-conformance');

      const visible = await people.canSeeSite({
        account: req.account,
        siteId: nonconformance.siteId
      });
      if (!visible) {
        return res.status(403).json({ message: people.OUTSIDE_GRANTED_ORG_UNITS });
      }

      const action = await actions.linkNonconformance(
        req.action.id,
        nonconformance.id,
        req.account.id
      );
      res.status(201).json({ action });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// Unlinking a Non-conformance from a Concern (issue #208). Its own address
// rather than a DELETE, following the shape every other change to an Action
// takes (`/cancel`, `/escalate`, `/reopen`): what this does is state a
// decision about the record — "these two are not the same problem after all" —
// and the caller gets the Concern back, as every other write in this Module
// answers.
//
// The refusals are actions.js's own, over a locked row: the Non-conformance
// this Concern was raised from cannot be unlinked (409), and one that is not
// linked at all is a 404 rather than a silent no-op.
router.post(
  '/:id/nonconformances/:nonconformanceId/unlink',
  people.authenticate,
  people.requireActive,
  requireActionWriteScope,
  async (req, res, next) => {
    try {
      const nonconformanceId = parseId(req.params.nonconformanceId);
      if (nonconformanceId === null) {
        return res.status(400).json({ message: 'nonconformanceId must be a valid Non-conformance id' });
      }

      const action = await actions.unlinkNonconformance(
        req.action.id,
        nonconformanceId,
        req.account.id
      );
      res.json({ action });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// Raise a measure against the Concern it answers (issue #178).
//
// Scope is the MEASURE's own Org Unit — defaulting to the Concern's, which is
// where a countermeasure on a line normally sits — and only that. That is a
// deliberate asymmetry against the Asset-move precedent (issue #171, where a
// move needs a write Grant reaching both Org Units): a measure writes no
// existing record, the Concern it answers is read and never written, and
// requiring the caller to reach it would stop a store recording the fix it made
// for a line it holds no Grant on.
//
// The three refusals about the parent (missing, not a Concern, itself a
// measure) live in actions.js over a locked read, not here: this route resolves
// the parent for existence and scope, and the rest is a fact about the row.
router.post(
  '/:id/measures',
  people.authenticate,
  people.requireActive,
  requireKnownAction,
  async (req, res, next) => {
    try {
      const body = req.body ?? {};

      // The measure's own Org Unit is what the write Grant has to reach —
      // whether the caller named one or let it default to the Concern's, which
      // is why the default is resolved HERE rather than silently inside the
      // service. Existence before scope: a malformed id is a 400, an unknown
      // Org Unit a 404, and only then the Grant.
      const namedOrgUnitId = body.orgUnitId === undefined || body.orgUnitId === null
        ? null
        : parseId(body.orgUnitId);
      if (body.orgUnitId !== undefined && body.orgUnitId !== null && namedOrgUnitId === null) {
        return res.status(400).json({ message: 'orgUnitId must be a valid Org Unit id' });
      }

      let orgUnitId = namedOrgUnitId;
      const target = await people.findOrgUnit(namedOrgUnitId ?? req.action.orgUnitId);
      if (!target) throw notFound('Org Unit');
      const allowed = await people.canAct({
        account: req.account,
        orgUnitId: target.id,
        write: true
      });
      if (!allowed) {
        return res.status(403).json({ message: people.OUTSIDE_GRANTED_ORG_UNITS });
      }
      orgUnitId = target.id;

      let ownerEmployeeId = null;
      if (body.ownerEmployeeId !== undefined && body.ownerEmployeeId !== null) {
        ownerEmployeeId = parseId(body.ownerEmployeeId);
        if (ownerEmployeeId === null) {
          return res.status(400).json({ message: 'ownerEmployeeId must be a valid Employee id' });
        }
        const employee = await people.findEmployee(ownerEmployeeId);
        if (!employee) throw notFound('Employee');
        if (!employee.isActive) {
          throw httpError(409, 'this Employee has departed and cannot be given an Action');
        }
      }

      const measure = await actions.createMeasure(
        req.action.id,
        {
          actionType: body.actionType,
          title: body.title,
          description: body.description ?? null,
          orgUnitId,
          ownerEmployeeId,
          dueDate: body.dueDate ?? null,
          priority: body.priority ?? 3
        },
        req.account.id,
        { raisedBy: req.account.employeeId ?? null }
      );

      res.status(201).json({ action: measure });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// The Pillar catalogue, for the raise form's own chooser (ADR-0023: a value
// with a known set is chosen, never typed). Declared BEFORE `/:id` on purpose:
// Express matches in declaration order, so a `/:id` route declared first would
// swallow `/pillars` and answer 400 from parseId for a route that should never
// have been reached.
router.get('/pillars', people.authenticate, people.requireActive, async (req, res, next) => {
  try {
    res.json({ pillars: await actions.listPillars() });
  } catch (error) {
    handleError(error, res, next);
  }
});

// The CAPA list (issue #211) — every investigation, worst first: the ones whose
// effectiveness check has fallen due, then the ones due soonest, then the most
// recently opened.
//
// **Declared before `/:id` on purpose, and this one really is load-bearing.**
// Express matches in declaration order and a path segment at a time, so
// `/api/actions/capas` is one segment and `GET /:id` below would take it for an
// Action whose id is `capas` — answering 400 from parseId for a route that
// should never have been reached. `/pillars` above is declared before `/:id`
// for exactly this reason; `/capas/:id` needs no such care, because a
// two-segment path can never be shadowed by a one-segment one.
//
// The three filters are read filters over an already-visible list, the same
// rule the Action register's are: `orgUnitId` narrows by *area* (one Org Unit
// and everything beneath it, the ltree walk), `status` by the investigation's
// own state, and `overdue=true` to the checks that have fallen due and not been
// recorded. Nothing here is a Grant question — reading a CAPA is platform-wide
// for every approved Account, exactly as reading one by id is (ADR-0009).
//
// A value with a known set is checked rather than forwarded (ADR-0023's rule
// read the way the register reads its own enums): `status=verified` is a
// mistake the caller can fix, and answering it with an empty list would hide
// the typo behind what looks like an investigated plant. Only the exact string
// 'true' counts as overdue, the same convenience-filter rule `includeHistory`
// on the register and `includeRetired` on Assets follow.
router.get('/capas', people.authenticate, people.requireActive, async (req, res, next) => {
  try {
    const status = requireQueryMemberOf('status', req.query.status, actions.CAPA_STATUSES);
    const overdue = req.query.overdue === 'true';

    let orgUnitPath = null;
    if (req.query.orgUnitId !== undefined) {
      const orgUnit = await people.findOrgUnit(req.query.orgUnitId);
      if (!orgUnit) throw notFound('Org Unit');
      orgUnitPath = orgUnit.path;
    }

    const { capas, truncated } = await actions.listCapas({ orgUnitPath, status, overdue });
    res.json({ capas, truncated });
  } catch (error) {
    handleError(error, res, next);
  }
});

// One CAPA, by its own id (issue #209) — the read the CAPA's Screen makes, and
// a Site-wide read for the same reason an Action's is: which Org Unit a record
// sits at decides where somebody may act on it, not who may read it.
//
// Declared here rather than beside the Action routes because `/capas/:id` and
// `/:id` are different patterns: Express matches a path segment by segment, so
// a two-segment path can never be shadowed by a one-segment one and the order
// of the two declarations is a matter of where a reader looks first. What *is*
// load-bearing is that it is declared before nothing — this route has no
// sibling that could swallow it, unlike `/pillars` above, whose shorter name it
// does not share.
router.get('/capas/:id', people.authenticate, people.requireActive, async (req, res, next) => {
  try {
    const capa = await actions.getCapaDetail(req.params.id);
    if (!capa) throw notFound('CAPA');
    res.json({ capa });
  } catch (error) {
    handleError(error, res, next);
  }
});

// Opening a CAPA on a Concern (issue #209, ADR-0034).
//
// The order of the two refusals is deliberate and matches the escalate route's
// own 400-before-403 argument: the row is checked for *what it is* before the
// caller is checked for what they may do, because telling somebody they lack
// Quality authority to open an investigation on a Containment would send them
// to ask for a right that could never let the act succeed. A caller wrong about
// the record is told so; a caller wrong about their own authority is told that.
//
// The Concern's existing CAPA is a 409 from actions.js rather than from here,
// because it is a fact about the row and it is read under a lock — a route that
// checked it would be a second read racing the first.
//
// The team is resolved here, through People's entry point, because it is
// People's record: every id is parsed (400), found (404) and checked as active
// (409) before anything is written.
router.post(
  '/:id/capa',
  people.authenticate,
  people.requireActive,
  requireKnownAction,
  async (req, res, next) => {
    try {
      const body = req.body ?? {};

      if (req.action.actionType !== 'concern') {
        throw httpError(400, 'a CAPA is opened on a Concern, and that Action is not one');
      }

      const allowed = await people.canAct({
        account: req.account,
        orgUnitId: req.action.orgUnitId,
        quality: true
      });
      if (!allowed) {
        return res.status(403).json({ message: OPEN_CAPA_AUTHORITY_REQUIRED });
      }

      let teamLeadEmployeeId = null;
      if (body.teamLeadEmployeeId !== undefined && body.teamLeadEmployeeId !== null) {
        teamLeadEmployeeId = await requireActiveCapaTeamEmployee(
          body.teamLeadEmployeeId,
          'teamLeadEmployeeId'
        );
      }

      let teamMemberEmployeeIds = [];
      if (body.teamMemberEmployeeIds !== undefined && body.teamMemberEmployeeIds !== null) {
        if (!Array.isArray(body.teamMemberEmployeeIds)) {
          return res
            .status(400)
            .json({ message: 'teamMemberEmployeeIds must be a list of Employee ids' });
        }
        teamMemberEmployeeIds = [];
        for (const memberId of body.teamMemberEmployeeIds) {
          teamMemberEmployeeIds.push(
            await requireActiveCapaTeamEmployee(memberId, 'teamMemberEmployeeIds')
          );
        }
      }

      const capa = await actions.openCapa(
        req.action.id,
        {
          teamLeadEmployeeId,
          teamMemberEmployeeIds,
          problemStatement: body.problemStatement ?? null,
          dueDate: body.dueDate ?? null
        },
        req.account.id
      );

      res.status(201).json({ capa });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// Changing what an open CAPA carries about itself (issue #209): its problem
// description, its team lead and its team.
//
// PATCH rather than a `/team` or a `/problem` address of its own, and that is a
// deliberate departure from the Action log's own shape: everything that changes
// an Action *after* it is raised is an event with a name (`/cancel`,
// `/escalate`, `/phases/:phase/complete`) because each one is a decision with a
// state transition behind it. Setting a team or writing a description is not an
// event — it is the record being filled in, possibly twice, possibly a field at
// a time — and giving each field its own verb would invent a state machine for
// an investigation's paperwork.
//
// What arrives is a partial update: a field the caller did not send is left
// alone, a `null` lead clears it (the team lead departed, which is a real
// state), a member list replaces the team it was sent with. A body naming
// nothing is a 400 rather than a silent no-op, so a caller's mistake is visible.
router.patch(
  '/capas/:id',
  people.authenticate,
  people.requireActive,
  requireCapaQualityAuthority,
  async (req, res, next) => {
    try {
      const body = req.body ?? {};
      const input = {};

      if (body.problemStatement !== undefined) {
        input.problemStatement = body.problemStatement;
      }

      if (body.teamLeadEmployeeId !== undefined) {
        input.teamLeadEmployeeId =
          body.teamLeadEmployeeId === null
            ? null
            : await requireActiveCapaTeamEmployee(body.teamLeadEmployeeId, 'teamLeadEmployeeId');
      }

      if (body.teamMemberEmployeeIds !== undefined) {
        if (!Array.isArray(body.teamMemberEmployeeIds)) {
          return res
            .status(400)
            .json({ message: 'teamMemberEmployeeIds must be a list of Employee ids' });
        }
        input.teamMemberEmployeeIds = [];
        for (const memberId of body.teamMemberEmployeeIds) {
          input.teamMemberEmployeeIds.push(
            await requireActiveCapaTeamEmployee(memberId, 'teamMemberEmployeeIds')
          );
        }
      }

      // How long after the Concern closes the effectiveness check falls due
      // (issue #211). A number, so it passes through unvalidated here — the
      // range and the whole-number rule are facts about the record's own field
      // and live in actions.js, where `updateCapa` refuses a delay the schema's
      // own CHECK would only catch as a 500 (AGENTS.md §6's division).
      if (body.effectivenessCheckDelayDays !== undefined) {
        input.effectivenessCheckDelayDays = body.effectivenessCheckDelayDays;
      }

      if (Object.keys(input).length === 0) {
        throw httpError(
          400,
          'send a problem description, a team lead, a team or the effectiveness delay — ' +
            'there is nothing to change otherwise'
        );
      }

      const capa = await actions.updateCapa(req.capa.id, input, req.account.id);
      res.json({ capa });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// Recording a CAPA's effectiveness check (issue #211, ADR-0034) — the act that
// closes an investigation, or sends its Concern round again.
//
// It is a POST with a name of its own rather than a field on the PATCH above,
// and the difference is the whole point: everything the PATCH changes is the
// record being filled in — a team, a description, a number — while this is a
// decision with a state transition behind it, the shape `/cancel`, `/escalate`
// and `/phases/:phase/complete` already take. `outcome` is what makes it one:
// `effective` closes the CAPA, `not_effective` reopens the Concern into its
// next PDCA cycle (ADR-0033) and leaves the CAPA open, and neither is a field
// a form is filling in.
//
// The body is exactly the two fields the record keeps: the verdict and the
// note. The verifier and the time are the server's — the Account is the
// caller's own and the time is `now()`, because a check recorded on somebody
// else's behalf is not a check — and the due date, the status and the Concern's
// own reopening are consequences of the verdict rather than fields a caller
// gets to send.
//
// The gate is `requireCapaEffectivenessAuthority` above: Quality authority at
// the CAPA's Org Unit, held by somebody who is not the team lead's Account.
// Everything else the act refuses — the CAPA's status, the Concern not being
// closed, and an `effective` verdict on an investigation whose chains have no
// confirmed root cause — is an actions.js 409 read under the CAPA's own locks.
router.post(
  '/capas/:id/effectiveness',
  people.authenticate,
  people.requireActive,
  requireCapaEffectivenessAuthority,
  async (req, res, next) => {
    try {
      const body = req.body ?? {};
      const capa = await actions.recordEffectivenessCheck(
        req.capa.id,
        { outcome: body.outcome, note: body.note },
        req.account.id
      );
      res.json({ capa });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// ---------------------------------------------------------------------------
// A CAPA's two 5 Why chains (issue #210)
//
// Three addresses, one per thing a team does to its reasoning: add a Why to a
// chain, change one, remove one. Each answers with the whole CAPA, the shape
// every other write in this slice takes — the caller's Screen is already
// showing the investigation, and a chain only means anything beside its own
// team, problem and Concern.
//
// **The chain is in the body rather than in the address.** `/capas/:id/whys`
// is the collection of a CAPA's Whys; *which* chain one is added to is a field
// of the row being written, exactly as `actionType` is on a measure. An address
// per chain (`/capas/:id/chains/:chain/whys`) would say the chain is a resource
// of its own, and it is not one: it is a column, and a Why may not move between
// chains (see `updateCapaWhy`).
//
// **Removing is a DELETE, and it is this Platform's first.** Everything else
// that changes a record here is a named POST (`/cancel`, `/escalate`,
// `/phases/:phase/complete`) because each of those is a transition with a state
// machine behind it. A Why has no state to transition through: it is a line in
// a chain that turned out to be wrong (#200's own words), and the honest thing
// to do with it is take it out. It is not soft-deleted, because a withdrawn Why
// left in place would put every reader of the chain in the position of deciding
// which rows count — and the audit log records the removal and who made it.
//
// The write scope is `requireCapaWhyWrite` above: edit access at the CAPA's Org
// Unit, or a place on its team. The refusals that belong to the row — the
// CAPA's status (409) and the Why's own existence (404) — are actions.js's,
// read under the CAPA's own lock.
// ---------------------------------------------------------------------------

// Adding a Why to one of the CAPA's chains, at the next position of that chain.
router.post(
  '/capas/:id/whys',
  people.authenticate,
  people.requireActive,
  requireCapaWhyWrite,
  async (req, res, next) => {
    try {
      const body = req.body ?? {};
      const capa = await actions.addCapaWhy(
        req.capa.id,
        { chain: body.chain, statement: body.statement },
        req.account.id
      );
      res.status(201).json({ capa });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// Changing one Why: what it says, where it sits in its chain, and whether it is
// the chain's confirmed root cause.
//
// A body naming none of the three is a 400 from actions.js rather than a silent
// no-op, and each of the three has its own refusal there (an empty statement, a
// position outside the chain, an `isRoot` that is not a boolean). The route
// copies the three fields and nothing else: a body may not smuggle a `chain` or
// a `capaId` in, which would be a second way to say what the address and the
// row already say.
router.patch(
  '/capas/:id/whys/:whyId',
  people.authenticate,
  people.requireActive,
  requireCapaWhyWrite,
  async (req, res, next) => {
    try {
      const body = req.body ?? {};
      const input = {};

      if (body.statement !== undefined) input.statement = body.statement;
      if (body.sequence !== undefined) input.sequence = body.sequence;
      if (body.isRoot !== undefined) input.isRoot = body.isRoot;

      const capa = await actions.updateCapaWhy(
        req.capa.id,
        req.params.whyId,
        input,
        req.account.id
      );
      res.json({ capa });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// Removing a Why, and closing the gap it leaves in its chain.
router.delete(
  '/capas/:id/whys/:whyId',
  people.authenticate,
  people.requireActive,
  requireCapaWhyWrite,
  async (req, res, next) => {
    try {
      const capa = await actions.removeCapaWhy(
        req.capa.id,
        req.params.whyId,
        req.account.id
      );
      res.json({ capa });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// ---------------------------------------------------------------------------
// A CAPA's fishbone — candidate causes by 6M category (issue #213)
//
// Four addresses, one per thing a team does to the list before it decides: add
// a candidate cause under one of the six categories, change one (its category,
// what it says, and the verdict with the evidence for it), remove one, and
// **start a chain from a cause the evidence confirmed**. Each answers with the
// whole CAPA as it now reads, the shape every other write in this slice takes —
// the fishbone sits on the same record the chains do.
//
// **The write scope is #210's `requireCapaWhyWrite`, deliberately shared rather
// than written a second time.** The rule is one rule — edit access at the
// CAPA's Org Unit, or a place on its team — and two gates for one rule would be
// two places to change the day a third thing on a CAPA gets written. Its
// message already says "writing a CAPA's root causes", which is what a
// candidate cause is, and its ordering (existence, then scope, then the
// service's own status under its own lock) is the one these addresses need for
// the same reasons: an unknown CAPA is a 404 before any authority is asked, and
// a closed investigation is a 409 in exactly the words the chains give.
//
// **The verdict is a body field, not an address.** `/causes/:causeId/verdict`
// would say deciding a cause is a transition with a record of its own, and it
// is not: `verdict` and `evidenceNote` are two columns of the row, and the
// evidence note is required in the same request that decides it (see
// `updateCapaCause`). One address per row, the shape a Why's PATCH takes.
//
// **Starting a chain is a POST under the cause**, and the one thing here that
// is not a plain edit: `/capas/:id/causes/:causeId/whys` writes a row of the
// *other* half of `capa_root_causes` — the chain's first Why — which is why it
// reads as "a Why, from this cause" rather than as a field of the cause. The
// chain is in the body rather than in the address, for the reason #210's own
// `/whys` gives: a chain is a column, and a Why never moves between chains.
// ---------------------------------------------------------------------------

// Adding a candidate cause under one 6M category.
router.post(
  '/capas/:id/causes',
  people.authenticate,
  people.requireActive,
  requireCapaWhyWrite,
  async (req, res, next) => {
    try {
      const body = req.body ?? {};
      const capa = await actions.addCapaCause(
        req.capa.id,
        { category: body.category, statement: body.statement },
        req.account.id
      );
      res.status(201).json({ capa });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// Changing one candidate cause: its category, what it says, and the verdict
// with the evidence for it — a partial update, so a body naming none of the
// four is a 400 from actions.js rather than a silent no-op. The route copies
// the four fields and nothing else: a body may not smuggle a `capaId` or a
// `causeType` in, which would be a second way to say what the address and the
// row already say.
router.patch(
  '/capas/:id/causes/:causeId',
  people.authenticate,
  people.requireActive,
  requireCapaWhyWrite,
  async (req, res, next) => {
    try {
      const body = req.body ?? {};
      const input = {};

      if (body.category !== undefined) input.category = body.category;
      if (body.statement !== undefined) input.statement = body.statement;
      if (body.verdict !== undefined) input.verdict = body.verdict;
      if (body.evidenceNote !== undefined) input.evidenceNote = body.evidenceNote;

      const capa = await actions.updateCapaCause(
        req.capa.id,
        req.params.causeId,
        input,
        req.account.id
      );
      res.json({ capa });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// Removing a candidate cause from the fishbone.
router.delete(
  '/capas/:id/causes/:causeId',
  people.authenticate,
  people.requireActive,
  requireCapaWhyWrite,
  async (req, res, next) => {
    try {
      const capa = await actions.removeCapaCause(
        req.capa.id,
        req.params.causeId,
        req.account.id
      );
      res.json({ capa });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// Starting one of the CAPA's two chains from a confirmed candidate cause: the
// chain's first Why, at the head of the chain the body names. The cause must be
// confirmed (409 otherwise) and the chain must not have started (409) — both
// are actions.js's own refusals, read under the CAPA's lock.
router.post(
  '/capas/:id/causes/:causeId/whys',
  people.authenticate,
  people.requireActive,
  requireCapaWhyWrite,
  async (req, res, next) => {
    try {
      const body = req.body ?? {};
      const capa = await actions.startCapaWhyFromCause(
        req.capa.id,
        req.params.causeId,
        { chain: body.chain, statement: body.statement },
        req.account.id
      );
      res.status(201).json({ capa });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// One Action, by its own id. A Site-wide read for the same reason the register
// is: an Action's Org Unit decides where somebody may act on it, not who may
// read it.
router.get('/:id', people.authenticate, people.requireActive, async (req, res, next) => {
  try {
    const action = await actions.getActionDetail(req.params.id);
    if (!action) throw notFound('Action');
    res.json({ action });
  } catch (error) {
    handleError(error, res, next);
  }
});

// Complete the Action's open phase (issue #177) — the one door the cycle moves
// through. ADR-0019's shape, unchanged: the route reads no `status` off the
// body, the named phase must be the open one, and whether the move is legal is
// actions.js's business over a locked row rather than a rule invented here.
//
// The phase in the path is validated against the four the schema accepts, so
// `/phases/planning/complete` is a 400 naming them rather than a 409 about
// which phase is actually open — a typo is the caller's mistake, and saying so
// is more useful than telling them what the Action is waiting on.
router.post(
  '/:id/phases/:phase/complete',
  people.authenticate,
  people.requireActive,
  requireActionWriteScope,
  async (req, res, next) => {
    try {
      const body = req.body ?? {};
      if (!actions.PHASES.includes(req.params.phase)) {
        throw httpError(400, `phase must be one of: ${actions.PHASES.join(', ')}`);
      }
      const action = await actions.completePhase(
        req.action.id,
        req.params.phase,
        { note: body.note, outcome: body.outcome ?? null },
        req.account.id
      );
      res.json({ action });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// Where this Action may be handed up to (issue #180): the Org Units above its
// own, nearest first.
//
// No `canAct` here, and that is the register's rule rather than an oversight:
// who may *know* the list of Org Units above a concern they can already read is
// not a question Org Unit scope answers. The write it feeds is guarded
// separately, below.
router.get(
  '/:id/escalation-targets',
  people.authenticate,
  people.requireActive,
  requireKnownAction,
  async (req, res, next) => {
    try {
      res.json({ targets: await actions.escalationTargets(req.action.id) });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// Handing one Action up the tree (issue #180).
//
// Four refusals, in this order and for this reason: the id must be real (404,
// from requireKnownAction), the Action must not have ended (409 — the row it
// would hand up is a closed decision), the target must be an Org Unit *above*
// this Action's own (400, asked of the same ltree walk the read above serves,
// so there is one implementation of "above" and it is not re-spelled here), and
// only then the Grant (403, `write: true` at the **target** — not at the Org
// Unit the Action sits at: what this route changes is who has been told, and
// the caller is asking somebody else's Org Unit to take it, which is a right
// over the target and nowhere else).
//
// The 400 before the 403 matters: a caller who names an Org Unit below the
// Action is wrong about the tree, and telling them so beats telling them they
// are not allowed to do something that would not have worked anyway.
router.post(
  '/:id/escalate',
  people.authenticate,
  people.requireActive,
  requireKnownAction,
  async (req, res, next) => {
    try {
      const body = req.body ?? {};
      const orgUnitId = parseId(body.orgUnitId);
      if (orgUnitId === null) {
        return res.status(400).json({ message: 'orgUnitId must be a valid Org Unit id' });
      }

      if (req.action.status === 'done' || req.action.status === 'cancelled') {
        throw httpError(409, 'this Action has ended, so there is nothing to hand up');
      }

      const targets = await actions.escalationTargets(req.action.id);
      if (!targets.some((target) => target.id === String(orgUnitId))) {
        throw httpError(400, "orgUnitId must be an Org Unit above this Action's own");
      }

      const allowed = await people.canAct({
        account: req.account,
        orgUnitId,
        write: true
      });
      if (!allowed) {
        return res.status(403).json({ message: people.OUTSIDE_GRANTED_ORG_UNITS });
      }

      const action = await actions.escalateAction(req.action.id, orgUnitId, req.account.id);
      res.json({ action });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// Call one Action off (issue #179). ADR-0019's shape once more: no status read
// off the body, an optional `reason` (undoing a mistake should not demand
// prose), the write guarded in actions.js over a locked row, and a second
// cancel a 409 rather than a no-op.
router.post(
  '/:id/cancel',
  people.authenticate,
  people.requireActive,
  requireActionWriteScope,
  async (req, res, next) => {
    try {
      const body = req.body ?? {};
      if (body.reason !== undefined && body.reason !== null && typeof body.reason !== 'string') {
        return res.status(400).json({ message: 'reason must be text' });
      }
      const action = await actions.cancelAction(req.action.id, { reason: body.reason ?? null }, req.account.id);
      res.json({ action });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

module.exports = router;
