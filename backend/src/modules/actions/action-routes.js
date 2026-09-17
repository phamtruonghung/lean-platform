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
