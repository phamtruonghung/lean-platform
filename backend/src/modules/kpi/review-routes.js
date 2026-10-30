/*
 * The daily KPI Review over HTTP (ADR-0055). Mounted by index.js under
 * `/api/kpi`, beside catalogue-routes.js, whose header argues the scope rule,
 * the order (existence, then scope, then the catalogue) and the 503 for an
 * unconfigured catalogue; all three apply here unchanged.
 */

const express = require('express');
const people = require('../people');
const review = require('./review');
const {
  requireCatalogueConfigured, requireScope, resolveSiteContext, parseDateOnly
} = require('./site-context');
const { httpError, parseId, handleError } = require('./errors');

const router = express.Router();

// One row per KPI for a day, with its judgement (status null where there is
// none yet) and the Daily Target that day had.
router.get(
  '/review',
  people.authenticate,
  people.requireActive,
  requireCatalogueConfigured,
  async (req, res, next) => {
    try {
      const context = await resolveSiteContext(req.query.site_id);
      let reviewDate = context.siteToday;
      if (req.query.date !== undefined) {
        reviewDate = parseDateOnly(req.query.date);
        if (reviewDate === null) throw httpError(400, 'date must be a valid YYYY-MM-DD date');
      }

      await requireScope(req.account, context.rootOrgUnitId, { write: false });

      const rows = await review.listReview({ reviewDate });
      res.json({ review_date: reviewDate, rows });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// An entry's shape: which fields were sent and whether each is the right kind
// of value. Whether the status is one of its set and whether a missed day owes
// a note is review.js's domain check.
function parseEntry(entry) {
  if (entry === null || typeof entry !== 'object' || Array.isArray(entry)) {
    throw httpError(400, 'Each entry must be an object');
  }
  const kpiId = parseId(entry.kpi_id);
  if (kpiId === null) throw httpError(400, 'kpi_id must be a valid KPI id');
  if (typeof entry.status !== 'string') throw httpError(400, 'status is required');
  return {
    kpiId: Number(kpiId),
    status: entry.status,
    observed: entry.observed ?? null,
    note: entry.note ?? null
  };
}

// Saving a day's Review, all or nothing. A correction — the same KPI and day
// again — appends a second row and the newest wins in the database's view; that
// is append-only working, so it is a 201 and never a conflict.
router.post(
  '/review',
  people.authenticate,
  people.requireActive,
  requireCatalogueConfigured,
  async (req, res, next) => {
    try {
      const body = req.body ?? {};
      const context = await resolveSiteContext(body.site_id);
      const reviewDate = parseDateOnly(body.date);
      if (reviewDate === null) throw httpError(400, 'date must be a valid YYYY-MM-DD date');
      if (!Array.isArray(body.entries) || body.entries.length === 0) {
        throw httpError(400, 'entries must be a non-empty list');
      }
      const entries = body.entries.map(parseEntry);

      await requireScope(req.account, context.rootOrgUnitId, { write: true });

      // `body.app_user` is accepted — the client sends it — and deliberately not
      // trusted: anyone could type another person's name into a request. What is
      // written is the signed-in Account's own display name.
      const saved = await review.saveReview({
        reviewDate,
        entries,
        appUser: req.account.displayName
      });
      res.status(201).json({ saved, review_date: reviewDate });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

module.exports = router;
