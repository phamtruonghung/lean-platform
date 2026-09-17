/*
 * Customer complaints over HTTP (issue #214), mounted by index.js under
 * `/api/quality` beside customer-routes.js.
 *
 * This file is nonconformance-routes.js's shape applied to a second record, and
 * the access rules are deliberately the same ones, because the two records are
 * read and written by the same people:
 *
 *   - Reading is Site-wide: `GET /sites/:siteId/complaints` sits behind
 *     `authenticate` + `requireActive`, a known-Site check and
 *     `people.canSeeSite` — any Grant, read or write, on any Org Unit within
 *     the Site — and nothing else. One complaint's own read asks the same
 *     question about its own Site. Org Unit scope decides where an Account may
 *     act, not what it may know about (ADR-0009).
 *   - Recording a complaint is an edit Grant reaching its Org Unit, which is
 *     the ticket's own sentence: `people.canAct({ …, write: true })` at the Org
 *     Unit the complaint is filed at, or an administrator's role. `write: true`
 *     is spelled out because it defaults to FALSE, and a recording route that
 *     forgot it would be authorised by any read Grant with no error anywhere to
 *     notice.
 *   - Closing one with its response, linking an existing Non-conformance and
 *     recording one from the complaint are the same write, gated on the same
 *     Grant: they are work on the record, not decisions about the product. The
 *     decision that product may be used as it is stays a Non-conformance's own
 *     Concession, with its own Quality-authority gate (ADR-0035).
 *
 * Four refusals, and each says which one it is: a 404 when the complaint, the
 * Customer, the Product, the Defect code, the Org Unit or the Non-conformance
 * is not there, a 403 when the Grant question is answered no, a 409 when the
 * record's own state refuses (already closed, already names a Non-conformance,
 * a Non-conformance about another Product, a retired Product), and a 400 when a
 * field of the request is wrong.
 *
 * Existence before scope, the order AGENTS.md §6 fixes: the Site, then the Org
 * Unit, then whether that Org Unit belongs to this Site, and only then
 * `canAct`. On the routes that act on one complaint the record is resolved
 * before the Grant question for the same reason.
 *
 * A query value that names a closed set is checked, not forwarded (ADR-0023's
 * rule read the other way round): `?status=opne` is a mistake the caller can
 * fix, and answering it with an empty list would hide the typo behind what looks
 * like a quiet fortnight.
 */

const express = require('express');
const people = require('../people');
const customerComplaints = require('./customer-complaints');
const { httpError, notFound, parseId, handleError } = require('./errors');

const router = express.Router();

// Mirrors asset-routes.js's, action-routes.js's and
// nonconformance-routes.js's own requireKnownSite exactly: an unknown Site is a
// 404, never a silently empty 200.
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

async function requireKnownComplaint(req, res, next) {
  try {
    const complaint = await customerComplaints.findComplaint(req.params.id);
    if (!complaint) throw notFound('Customer complaint');
    req.complaint = complaint;
    return next();
  } catch (error) {
    return handleError(error, res, next);
  }
}

// One complaint is visible to anyone who can see the Site it was filed at — the
// same rule its register follows.
async function requireComplaintVisible(req, res, next) {
  return requireKnownComplaint(req, res, async () => {
    const allowed = await people.canSeeSite({
      account: req.account,
      siteId: req.complaint.siteId
    });
    if (!allowed) {
      return res.status(403).json({ message: people.OUTSIDE_GRANTED_ORG_UNITS });
    }
    return next();
  });
}

// The write-scope half, for the routes that change a complaint after it is
// recorded: an edit Grant reaching the Org Unit it is filed at, never a read
// one.
async function requireComplaintWriteScope(req, res, next) {
  return requireComplaintVisible(req, res, async () => {
    const allowed = await people.canAct({
      account: req.account,
      orgUnitId: req.complaint.orgUnitId,
      write: true
    });
    if (!allowed) {
      return res.status(403).json({ message: people.OUTSIDE_GRANTED_ORG_UNITS });
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

// The register: one Site's complaints, newest first, narrowed by status and by
// Org Unit. Both filters are read filters over an already-visible register — the
// Site is the only entitlement question asked, and `orgUnitId` narrows by area
// rather than by scope.
router.get(
  '/sites/:siteId/complaints',
  people.authenticate,
  people.requireActive,
  requireKnownSite,
  requireSiteVisible,
  async (req, res, next) => {
    try {
      const status = requireQueryMemberOf(
        'status',
        req.query.status,
        customerComplaints.COMPLAINT_STATUSES
      );

      let orgUnitPath = null;
      if (req.query.orgUnitId !== undefined) {
        const orgUnit = await people.findOrgUnit(req.query.orgUnitId);
        if (!orgUnit) throw notFound('Org Unit');
        if (orgUnit.siteId !== req.site.id) throw notFound('Org Unit');
        orgUnitPath = orgUnit.path;
      }

      const { complaints, truncated } = await customerComplaints.listComplaints(req.site.id, {
        orgUnitPath,
        status
      });

      res.json({ complaints, truncated });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// Recording a complaint. The Org Unit is resolved here rather than in the
// service because it is another Module's record and the scope question is asked
// about it — AGENTS.md §6's ordering, so an Org Unit that is not there is a 404
// for the administrator as well as for everyone else. The Customer, the Product
// and the Defect code are resolved in the service, which is where this Module's
// own records are validated (nonconformances.js does the same for a
// Non-conformance's Product and Defect code).
router.post(
  '/sites/:siteId/complaints',
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

      const complaint = await customerComplaints.recordComplaint(
        { ...body, orgUnitId: orgUnit.id },
        req.account.id
      );

      res.status(201).json({ complaint });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// One complaint, with the Customer, the Product, the Defect code and the
// Non-conformance that controls the complained-of product — what the detail
// Screen reads, and what every write below answers with.
router.get(
  '/complaints/:id',
  people.authenticate,
  people.requireActive,
  requireComplaintVisible,
  (req, res) => res.json({ complaint: req.complaint })
);

// Closing a complaint with the response the customer was given. A refusal for
// a missing note is a 400 from the service — a field of the request is wrong —
// and a complaint that is already closed is a 409.
router.post(
  '/complaints/:id/respond',
  people.authenticate,
  people.requireActive,
  requireComplaintWriteScope,
  async (req, res, next) => {
    try {
      const complaint = await customerComplaints.closeComplaint(
        req.complaint.id,
        req.body ?? {},
        req.account.id
      );
      res.json({ complaint });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// Controlling the complained-of product, the first road: record a
// Non-conformance from the complaint, with `detection_point = 'customer'` and
// the complaint's own Product and Defect code. Answers with both records,
// because the caller is looking at the complaint and reading the record it just
// created at the same time.
router.post(
  '/complaints/:id/nonconformance',
  people.authenticate,
  people.requireActive,
  requireComplaintWriteScope,
  async (req, res, next) => {
    try {
      const { nonconformance, complaint } =
        await customerComplaints.recordNonconformanceFromComplaint(
          req.complaint.id,
          req.body ?? {},
          req.account.id
        );
      res.status(201).json({ nonconformance, complaint });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// The second road: link one that already exists, which is what a complaint
// about a lot somebody has already recorded a Non-conformance for needs — the
// same record controls the product for both.
router.post(
  '/complaints/:id/link',
  people.authenticate,
  people.requireActive,
  requireComplaintWriteScope,
  async (req, res, next) => {
    try {
      const complaint = await customerComplaints.linkNonconformance(
        req.complaint.id,
        req.body ?? {},
        req.account.id
      );
      res.json({ complaint });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

module.exports = router;
