/*
 * Supplier NCRs over HTTP (issue #215), mounted by index.js under
 * `/api/quality` beside supplier-routes.js.
 *
 * This file is customer-complaint-routes.js's shape applied to a second record,
 * and the access rules are deliberately the same ones, because the two records
 * are read and written by the same people:
 *
 *   - Reading is Site-wide: `GET /sites/:siteId/supplier-ncrs` sits behind
 *     `authenticate` + `requireActive`, a known-Site check and
 *     `people.canSeeSite` — any Grant, read or write, on any Org Unit within
 *     the Site — and nothing else. One NCR's own read asks the same question
 *     about its own Site. Org Unit scope decides where an Account may act, not
 *     what it may know about (ADR-0009).
 *   - Recording an NCR is an edit Grant reaching its Org Unit, which is the
 *     ticket's own sentence: `people.canAct({ …, write: true })` at the Org
 *     Unit the NCR is filed at, or an administrator's role. `write: true` is
 *     spelled out because it defaults to FALSE, and a recording route that
 *     forgot it would be authorised by any read Grant with no error anywhere to
 *     notice.
 *   - Recording the disposition and the cost recovered, closing, linking an
 *     existing Non-conformance and recording one from the NCR are the same
 *     write, gated on the same Grant: they are work on the record. Nothing here
 *     is a decision that product may be used as it is — that stays a
 *     Non-conformance's own Concession, with its own Quality-authority gate
 *     (ADR-0035) — and nothing here is the commercial answer either, which is a
 *     figure somebody negotiates rather than a judgment about the material.
 *
 * Four refusals, and each says which one it is: a 404 when the NCR, the
 * Supplier, the Product, the Defect code, the Org Unit or the Non-conformance
 * is not there, a 403 when the Grant question is answered no, a 409 when the
 * record's own state refuses (already closed, already names a Non-conformance,
 * a Non-conformance about another Product, a retired Product), and a 400 when a
 * field of the request is wrong.
 *
 * Existence before scope, the order AGENTS.md §6 fixes: the Site, then the Org
 * Unit, then whether that Org Unit belongs to this Site, and only then
 * `canAct`. On the routes that act on one NCR the record is resolved before the
 * Grant question for the same reason.
 *
 * A query value that names a closed set is checked, not forwarded (ADR-0023's
 * rule read the other way round): `?status=oppen` is a mistake the caller can
 * fix, and answering it with an empty list would hide the typo behind what looks
 * like a quiet fortnight.
 *
 * **The ADR-0061 retrofit (issues #503 and #535).** Every route asks
 * `people.requirePermission` beside the Grant question it already asked: the
 * register and one NCR's read (`QLT_SUPPLIER_NCRS_DISPLAY`), and every write on
 * an NCR — recording one, recording its disposition, closing it, linking a
 * Non-conformance to it (`QLT_SUPPLIER_NCRS_RECORD`), and recording a
 * Non-conformance from it (`QLT_NONCONFORMANCES_RECORD` — the act is recording a
 * Non-conformance, and that is the code that names it).
 *
 * A disposition, a close and a link are the NCR's own lifecycle, which is what
 * `QLT_SUPPLIER_NCRS_RECORD` names: the code covers the report from being taken
 * in to being closed, the way `MTN_WORK_ORDERS_CHANGE` covers raising, assigning,
 * completing and cancelling one Work order. That code was seeded on ROLE_ADMIN
 * alone, where today any edit Grant reaching the Org Unit may record an NCR and
 * work it — so `1803900000000_quality-write-codes.js` widens it onto every role,
 * and the retrofit narrows nobody. The Grant half of every route is untouched.
 */

const express = require('express');
const people = require('../people');
const supplierNcrs = require('./supplier-ncrs');
const suppliers = require('./suppliers');
const { httpError, notFound, parseId, handleError } = require('./errors');

const router = express.Router();

// The three codes this Module's routes ask (ADR-0061, issues #503 and #535).
// `QLT_SUPPLIER_NCRS_DISPLAY` is seeded on ROLE_STANDARD, so the register's gate
// refuses nobody who could reach it before; `QLT_SUPPLIER_NCRS_RECORD` is
// widened onto every role by `1803900000000_quality-write-codes.js` because
// today's reach is the edit Grant, not the role; and
// `QLT_NONCONFORMANCES_RECORD` is the code that names recording a
// Non-conformance, which is what the one Non-conformance write below performs.
const mayReadSupplierNcrs = people.requirePermission('QLT_SUPPLIER_NCRS_DISPLAY');
const mayRecordSupplierNcr = people.requirePermission('QLT_SUPPLIER_NCRS_RECORD');
const mayRecordNonconformance = people.requirePermission('QLT_NONCONFORMANCES_RECORD');

// Mirrors customer-complaint-routes.js's own requireKnownSite exactly: an
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

async function requireKnownSupplierNcr(req, res, next) {
  try {
    const supplierNcr = await supplierNcrs.findSupplierNcr(req.params.id);
    if (!supplierNcr) throw notFound('Supplier NCR');
    req.supplierNcr = supplierNcr;
    return next();
  } catch (error) {
    return handleError(error, res, next);
  }
}

// One NCR is visible to anyone who can see the Site it was filed at — the same
// rule its register follows.
async function requireSupplierNcrVisible(req, res, next) {
  return requireKnownSupplierNcr(req, res, async () => {
    const allowed = await people.canSeeSite({
      account: req.account,
      siteId: req.supplierNcr.siteId
    });
    if (!allowed) {
      return res.status(403).json({ message: people.OUTSIDE_GRANTED_ORG_UNITS });
    }
    return next();
  });
}

// The write-scope half, for the routes that change an NCR after it is recorded:
// an edit Grant reaching the Org Unit it is filed at, never a read one.
async function requireSupplierNcrWriteScope(req, res, next) {
  return requireSupplierNcrVisible(req, res, async () => {
    const allowed = await people.canAct({
      account: req.account,
      orgUnitId: req.supplierNcr.orgUnitId,
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

// The register: one Site's supplier NCRs, newest first, narrowed by Supplier,
// by status and by Org Unit — the two the ticket names and the area filter the
// Non-conformance register established. All three are read filters over an
// already-visible register; the Site is the only entitlement question asked.
router.get(
  '/sites/:siteId/supplier-ncrs',
  people.authenticate,
  people.requireActive,
  requireKnownSite,
  requireSiteVisible,
  mayReadSupplierNcrs,
  async (req, res, next) => {
    try {
      const status = requireQueryMemberOf(
        'status',
        req.query.status,
        supplierNcrs.SUPPLIER_NCR_STATUSES
      );

      let orgUnitPath = null;
      if (req.query.orgUnitId !== undefined) {
        const orgUnit = await people.findOrgUnit(req.query.orgUnitId);
        if (!orgUnit) throw notFound('Org Unit');
        if (orgUnit.siteId !== req.site.id) throw notFound('Org Unit');
        orgUnitPath = orgUnit.path;
      }

      // A Supplier the caller names is resolved rather than forwarded: an id
      // that names no Supplier is a 404 and a malformed one a 400, so a filter
      // that can never match is never answered with an empty list.
      let supplierId = null;
      if (req.query.supplierId !== undefined) {
        supplierId = parseId(req.query.supplierId);
        if (supplierId === null) {
          throw httpError(400, 'supplierId must be a valid Supplier id');
        }
        const supplier = await suppliers.findSupplier(supplierId);
        supplierId = supplier.id;
      }

      const { supplierNcrs: rows, truncated } = await supplierNcrs.listSupplierNcrs(req.site.id, {
        orgUnitPath,
        status,
        supplierId
      });

      res.json({ supplierNcrs: rows, truncated });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// Recording an NCR. The Org Unit is resolved here rather than in the service
// because it is another Module's record and the scope question is asked about
// it — AGENTS.md §6's ordering, so an Org Unit that is not there is a 404 for
// the administrator as well as for everyone else. The Supplier, the Product and
// the Defect code are resolved in the service, which is where this Module's own
// records are validated.
router.post(
  '/sites/:siteId/supplier-ncrs',
  people.authenticate,
  people.requireActive,
  requireKnownSite,
  mayRecordSupplierNcr,
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

      const supplierNcr = await supplierNcrs.recordSupplierNcr(
        { ...body, orgUnitId: orgUnit.id },
        req.account.id
      );

      res.status(201).json({ supplierNcr });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// One NCR, with the Supplier, the Product, the Defect code and the
// Non-conformance that controls the received lot — what the detail Screen
// reads, and what every write below answers with.
router.get(
  '/supplier-ncrs/:id',
  people.authenticate,
  people.requireActive,
  requireSupplierNcrVisible,
  mayReadSupplierNcrs,
  (req, res) => res.json({ supplierNcr: req.supplierNcr })
);

// The Supplier's disposition and what was recovered: the commercial answer to
// the incoming lot. A disposition outside the baseline's own five is a 400, and
// an NCR that is already closed is a 409.
router.post(
  '/supplier-ncrs/:id/disposition',
  people.authenticate,
  people.requireActive,
  mayRecordSupplierNcr,
  requireSupplierNcrWriteScope,
  async (req, res, next) => {
    try {
      const supplierNcr = await supplierNcrs.recordDisposition(
        req.supplierNcr.id,
        req.body ?? {},
        req.account.id
      );
      res.json({ supplierNcr });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// Closing it. The one transition this slice has; a second close is a 409 rather
// than a quiet rewrite of `closed_at`.
router.post(
  '/supplier-ncrs/:id/close',
  people.authenticate,
  people.requireActive,
  mayRecordSupplierNcr,
  requireSupplierNcrWriteScope,
  async (req, res, next) => {
    try {
      const supplierNcr = await supplierNcrs.closeSupplierNcr(
        req.supplierNcr.id,
        req.account.id
      );
      res.json({ supplierNcr });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// Controlling the received product, the first road: record a Non-conformance
// from the NCR, with `detection_point = 'incoming'` and the NCR's own Product
// and Defect code. Answers with both records, because the caller is looking at
// the NCR and reading the record it just created at the same time.
router.post(
  '/supplier-ncrs/:id/nonconformance',
  people.authenticate,
  people.requireActive,
  requireSupplierNcrWriteScope,
  mayRecordNonconformance,
  async (req, res, next) => {
    try {
      const { nonconformance, supplierNcr } =
        await supplierNcrs.recordNonconformanceFromSupplierNcr(
          req.supplierNcr.id,
          req.body ?? {},
          req.account.id
        );
      res.status(201).json({ nonconformance, supplierNcr });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// The second road: link one that already exists, which is what a bad lot
// somebody has already recorded a Non-conformance for needs — the same record
// controls the material for both.
router.post(
  '/supplier-ncrs/:id/link',
  people.authenticate,
  people.requireActive,
  mayRecordSupplierNcr,
  requireSupplierNcrWriteScope,
  async (req, res, next) => {
    try {
      const supplierNcr = await supplierNcrs.linkNonconformance(
        req.supplierNcr.id,
        req.body ?? {},
        req.account.id
      );
      res.json({ supplierNcr });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

module.exports = router;
