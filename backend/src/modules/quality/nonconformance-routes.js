/*
 * Non-conformances over HTTP (issue #205). Mounted by index.js under
 * `/api/quality`, beside product-routes.js and defect-code-routes.js.
 *
 * This is the second file in the Module that talks to People, and it does so
 * only through `modules/people`'s entry point (ADR-0006): `authenticate`,
 * `requireActive`, `findSite`, `findOrgUnit`, `canAct`, `canSeeSite` and the
 * shared `OUTSIDE_GRANTED_ORG_UNITS` wording. Everything else about a
 * Non-conformance is nonconformances.js's own business.
 *
 * Two scope rules, and they are deliberately different — the same asymmetry
 * the action log records (ADR-0032), and the one issue #205's own acceptance
 * criteria spell out:
 *
 *   - Reading is Site-wide. `GET /sites/:siteId/nonconformances` sits behind
 *     `authenticate` + `requireActive`, a known-Site check and
 *     `people.canSeeSite` — any Grant, read or write, on any Org Unit within
 *     the Site — and nothing else. "Anyone who can see the Site can find and
 *     read it" is the ticket's own sentence, and the detail route below asks
 *     the same question about the record's own Site. Org Unit scope decides
 *     where an Account may act, not what it may know about (#55, ADR-0009).
 *     `?orgUnitId=` narrows the list by *area* — one Org Unit and everything
 *     beneath it — never by entitlement.
 *   - Recording is a write at the Org Unit the product was found at:
 *     `people.canAct({ …, write: true })` at that Org Unit, or an
 *     administrator's role. `write: true` is spelled out because it defaults
 *     to FALSE, and a recording route that forgot it would be authorised by
 *     any read Grant with no error anywhere to notice.
 *   - A Disposition (issue #206) is the same write as recording — a recorder
 *     dealing with bad product in parts is doing the same work as one writing
 *     it down.
 *   - A Concession, a lowered severity, a reopen and a cancel are decisions
 *     rather than work, and each is gated on `people.canAct({ …,
 *     quality: true })` — the Quality authority ADR-0035 carries on a Grant
 *     beside its level, reaching downward like the Grant does. None of the
 *     four asks for `write: true` as well, because the authority is the
 *     permission for the decision and ADR-0035 keeps the two flags
 *     independent.
 *
 * Four refusals, and each says which one it is: a 404 when the record or the
 * Org Unit is not there, a 403 when the Grant question is answered no (with
 * People's `OUTSIDE_GRANTED_ORG_UNITS` for a scope refusal and this Module's
 * own sentence for a Quality-authority one — a caller may be well inside their
 * granted Org Units and simply not hold the authority), a 409 when the record's
 * own state refuses (a Disposition larger than what is still undecided, a
 * change to a cancelled record, a reopen of something that is not closed), and
 * a 400 when a field of the request is wrong.
 *
 * Existence before scope, the order AGENTS.md §6 fixes: the Site, then the Org
 * Unit, then whether that Org Unit belongs to this Site (a cross-Site Org Unit
 * is a 404 here — from this endpoint's point of view there is no such Org Unit
 * in this Site), and only then `canAct`. `canAct` returns true for role
 * `admin` before it even looks at the Org Unit id, so asking scope first would
 * turn an administrator's typo into a raw 500 rather than a clean 404.
 *
 * A query value that names a closed set is checked, not forwarded (ADR-0023's
 * rule read the other way round): `?status=opne` is a mistake the caller can
 * fix, and answering it with an empty list would hide the typo behind what
 * looks like a quiet Site. A date range is checked the same way, and is
 * interpreted as *production days* — see nonconformances.js's own note on
 * `listNonconformances`.
 */

const express = require('express');
const people = require('../people');
const nonconformances = require('./nonconformances');
const { httpError, notFound, parseId, handleError } = require('./errors');

const router = express.Router();

// Mirrors asset-routes.js's and action-routes.js's own requireKnownSite
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

// The Site's Non-conformances are readable by anyone who can see the Site at
// all, so this is the weaker of People's two questions about a place — the
// same predicate GET /sites filters by, and the same one raising a Concern
// asks (#198). An Account holding no Grant anywhere in the Site is refused.
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

// The Non-conformance named in the URL must exist before anything else is
// asked about it — a clean 404, even for an administrator — and only then is
// its Site's visibility checked, because "can you see this record" is a
// question you can only ask about a record that is there.
async function requireKnownNonconformance(req, res, next) {
  try {
    const nonconformance = await nonconformances.findNonconformance(req.params.id);
    if (!nonconformance) throw notFound('Non-conformance');
    req.nonconformance = nonconformance;
    return next();
  } catch (error) {
    return handleError(error, res, next);
  }
}

async function requireNonconformanceVisible(req, res, next) {
  return requireKnownNonconformance(req, res, async () => {
    const allowed = await people.canSeeSite({
      account: req.account,
      siteId: req.nonconformance.siteId
    });
    if (!allowed) {
      return res.status(403).json({ message: people.OUTSIDE_GRANTED_ORG_UNITS });
    }
    return next();
  });
}

// The write-scope half, for the routes that change a Non-conformance after it
// is recorded: a write Grant reaching the Org Unit it sits at, never a read
// one. Existence and visibility first, so `canAct` is never asked about a null
// id.
async function requireNonconformanceWriteScope(req, res, next) {
  return requireNonconformanceVisible(req, res, async () => {
    const allowed = await people.canAct({
      account: req.account,
      orgUnitId: req.nonconformance.orgUnitId,
      write: true
    });
    if (!allowed) {
      return res.status(403).json({ message: people.OUTSIDE_GRANTED_ORG_UNITS });
    }
    return next();
  });
}

// Quality authority (issue #206, ADR-0035): the standing to decide about
// nonconforming product, carried on a Grant independently of its level and
// reaching downward like the Grant does. Four acts need it — granting a
// Concession, lowering a severity, reopening a closed record and cancelling one
// recorded in error — and each of them is a judgement about the product or the
// record rather than a piece of work on it, which is why none of them asks
// for `write: true` as well: ADR-0035's own sentence is that Quality authority
// does not imply write and write does not imply Quality authority, and the
// authority IS this decision's permission. An administrator holds it
// everywhere, which `canAct` answers for.
//
// Existence and visibility come first for the same reason as everywhere else,
// and the refusal is a sentence of this Module's own rather than People's
// `OUTSIDE_GRANTED_ORG_UNITS`: the caller may well be inside their granted Org
// Units and simply not hold this authority, and telling them the wrong thing
// sends them to the wrong person to ask.
const QUALITY_AUTHORITY_REQUIRED =
  "that decision needs Quality authority at this Non-conformance's Org Unit";

async function requireNonconformanceQualityAuthority(req, res, next) {
  return requireNonconformanceVisible(req, res, async () => {
    const allowed = await people.canAct({
      account: req.account,
      orgUnitId: req.nonconformance.orgUnitId,
      quality: true
    });
    if (!allowed) {
      return res.status(403).json({ message: QUALITY_AUTHORITY_REQUIRED });
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

// A date range is two `YYYY-MM-DD` days — never a timestamp, because the range
// a quality log is read over is production days (ADR-0017), and a partial
// timestamp would silently mean something different at each Site.
const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;

function requireQueryDate(field, value) {
  if (value === undefined) return null;
  if (typeof value !== 'string' || !DATE_PATTERN.test(value)) {
    throw httpError(400, `${field} must be a date in YYYY-MM-DD form`);
  }
  return value;
}

// The register: a Site's Non-conformances, newest first, narrowed by any of
// the filters the ticket names. Every filter is a read filter over an
// already-visible register — the Site is the only entitlement question asked,
// and `orgUnitId` narrows by area rather than by scope.
router.get(
  '/sites/:siteId/nonconformances',
  people.authenticate,
  people.requireActive,
  requireKnownSite,
  requireSiteVisible,
  async (req, res, next) => {
    try {
      const status = requireQueryMemberOf(
        'status',
        req.query.status,
        nonconformances.NONCONFORMANCE_STATUSES
      );
      const severity = requireQueryMemberOf(
        'severity',
        req.query.severity,
        nonconformances.SEVERITIES
      );
      const defectCodeId = requireQueryId('defectCodeId', req.query.defectCodeId);
      const productId = requireQueryId('productId', req.query.productId);
      const from = requireQueryDate('from', req.query.from);
      const to = requireQueryDate('to', req.query.to);

      let orgUnitPath = null;
      if (req.query.orgUnitId !== undefined) {
        const orgUnit = await people.findOrgUnit(req.query.orgUnitId);
        if (!orgUnit) throw notFound('Org Unit');
        if (orgUnit.siteId !== req.site.id) throw notFound('Org Unit');
        orgUnitPath = orgUnit.path;
      }

      const { nonconformances: rows, truncated } = await nonconformances.listNonconformances(
        req.site.id,
        { orgUnitPath, status, defectCodeId, productId, severity, from, to }
      );

      res.json({ nonconformances: rows, truncated });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// Recording a Non-conformance (issue #205).
//
// The Org Unit is resolved here rather than in the service because it is
// another Module's record, and it is resolved *before* the Grant is asked
// about — AGENTS.md §6's ordering, so an Org Unit that is not there is a 404
// for the administrator as well as for everyone else. The Asset id is parsed
// here for the same reason: whether it names a real Asset and whether that
// Asset sits at this Org Unit is a fact about an Asset, and the service
// answers both (it reads Maintenance's table by join, which ADR-0006 allows).
router.post(
  '/sites/:siteId/nonconformances',
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

      const nonconformance = await nonconformances.recordNonconformance(
        { ...body, orgUnitId: orgUnit.id },
        req.account.id
      );

      res.status(201).json({ nonconformance });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// One Non-conformance, with its quantity history — what the detail Screen
// reads. Visible to anyone who can see its Site, the same rule the register
// follows.
router.get(
  '/nonconformances/:id',
  people.authenticate,
  people.requireActive,
  requireNonconformanceVisible,
  async (req, res, next) => {
    try {
      const nonconformance = await nonconformances.getNonconformanceDetail(req.params.id);
      if (!nonconformance) throw notFound('Non-conformance');
      res.json({ nonconformance });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// Changing a Non-conformance after it was recorded: raising its severity, and
// recording the immediate containment that makes it `contained`. Both are
// writes at the Org Unit it sits at.
router.patch(
  '/nonconformances/:id',
  people.authenticate,
  people.requireActive,
  requireNonconformanceWriteScope,
  async (req, res, next) => {
    try {
      const nonconformance = await nonconformances.updateNonconformance(
        req.nonconformance.id,
        req.body ?? {},
        req.account.id
      );
      res.json({ nonconformance });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// The affected quantity, increased (issue #205). A separate address rather
// than a field on the PATCH above, because it is a different kind of act: it
// appends to the record's history rather than correcting a field, and the
// refusal a decrease gets (409) is not the refusal a severity lowering gets
// (403).
router.post(
  '/nonconformances/:id/quantity',
  people.authenticate,
  people.requireActive,
  requireNonconformanceWriteScope,
  async (req, res, next) => {
    try {
      const nonconformance = await nonconformances.increaseQuantity(
        req.nonconformance.id,
        req.body ?? {},
        req.account.id
      );
      res.json({ nonconformance });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// A Disposition: scrap, rework with its minutes, or return to the supplier
// (issue #206). Bad product is dealt with in parts as it is sorted, and this
// is where a part of it is dealt with. The access is the same as recording —
// a write Grant reaching the Org Unit the record sits at — because a recorder
// dealing with product is the same act as a recorder writing it down; only a
// Concession, below, is a decision rather than a piece of work.
router.post(
  '/nonconformances/:id/dispositions',
  people.authenticate,
  people.requireActive,
  requireNonconformanceWriteScope,
  async (req, res, next) => {
    try {
      const nonconformance = await nonconformances.recordDisposition(
        req.nonconformance.id,
        req.body ?? {},
        req.account.id
      );
      res.status(201).json({ nonconformance });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// The Concession (issue #206): a Disposition to use the product as it is,
// which accepts it rather than dealing with it. It is the first act in this
// Module that needs Quality authority, and the Account that granted it stays
// on the record — `grantConcession` writes it into the Disposition's own
// deciding-Account column, which is read back as `decidedByAccountName`.
//
// A third address rather than a kind on the one above, because the two have
// different permissions, a different required body (a reference and a note)
// and a different meaning: this is the decision ADR-0035 exists for, and it
// should be impossible to reach it through a route that only checked a write
// Grant.
router.post(
  '/nonconformances/:id/concession',
  people.authenticate,
  people.requireActive,
  requireNonconformanceQualityAuthority,
  async (req, res, next) => {
    try {
      const nonconformance = await nonconformances.grantConcession(
        req.nonconformance.id,
        req.body ?? {},
        req.account.id
      );
      res.status(201).json({ nonconformance });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// Lowering the severity (issue #206) — the correction issue #205 refused a
// recorder, now allowed to a holder of Quality authority with a note. Its own
// address rather than a lowering through PATCH, because the two are gated
// differently: a raising needs a write Grant and a lowering needs the
// authority, and one route cannot ask both questions honestly. The change is
// kept with who made it, when, and the note, and the whole record comes back.
router.post(
  '/nonconformances/:id/lower-severity',
  people.authenticate,
  people.requireActive,
  requireNonconformanceQualityAuthority,
  async (req, res, next) => {
    try {
      const nonconformance = await nonconformances.lowerSeverity(
        req.nonconformance.id,
        req.body ?? {},
        req.account.id
      );
      res.json({ nonconformance });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// Reopening a closed Non-conformance (issue #206). Quality authority and a
// note, like the other two corrections.
router.post(
  '/nonconformances/:id/reopen',
  people.authenticate,
  people.requireActive,
  requireNonconformanceQualityAuthority,
  async (req, res, next) => {
    try {
      const nonconformance = await nonconformances.reopenNonconformance(
        req.nonconformance.id,
        req.body ?? {},
        req.account.id
      );
      res.json({ nonconformance });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// Cancelling a Non-conformance recorded in error (issue #206).
router.post(
  '/nonconformances/:id/cancel',
  people.authenticate,
  people.requireActive,
  requireNonconformanceQualityAuthority,
  async (req, res, next) => {
    try {
      const nonconformance = await nonconformances.cancelNonconformance(
        req.nonconformance.id,
        req.body ?? {},
        req.account.id
      );
      res.json({ nonconformance });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

module.exports = router;
