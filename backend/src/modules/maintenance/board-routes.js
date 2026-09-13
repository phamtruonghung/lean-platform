/*
 * The tier board over HTTP (issue #76). Mounted by index.js under
 * `/api/maintenance`, alongside the rest of the Module's routes.
 *
 * This is the one file in the board pairing that talks to People, and only
 * through `modules/people`'s entry point (ADR-0006): `authenticate`,
 * `requireActive`, `findSite` and `findOrgUnit`. board.js owns everything
 * about the numbers and the period; resolving the Site named in the path and
 * the Org Unit named in the query is this file's job.
 *
 * The read is Site-wide and carries no Grant filter (ADR-0009): a tier board a
 * supervisor can only half-see is not a tier board. `?orgUnitId=` narrows the
 * rollup to that Org Unit and everything beneath it — never to what the caller
 * is granted — and an unknown or cross-Site one is a clean 404, the same
 * existence-before-scope shape work-order-routes.js follows on its own
 * Site-wide read.
 */

const express = require('express');
const people = require('../people');
const board = require('./board');
const { httpError, notFound, parseId, handleError } = require('./errors');

const router = express.Router();

// Mirrors work-order-routes.js's own requireKnownSite exactly: an unknown Site
// is a 404, never a silently empty 200.
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

// A DATE with no time, strictly. The regex alone would let 2026-13-40 through
// to Postgres, where `::date` raises a SQLSTATE with no `.status` and the
// caller would see a 500 for what is plainly a bad request.
function parseDateOnly(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return null;
  const [year, month, day] = value.split('-').map(Number);
  const parsed = new Date(Date.UTC(year, month - 1, day));
  if (
    parsed.getUTCFullYear() !== year ||
    parsed.getUTCMonth() !== month - 1 ||
    parsed.getUTCDate() !== day
  ) {
    return null;
  }
  return value;
}

const PERIOD_TYPES = ['shift', 'day', 'week', 'month'];

router.get(
  '/sites/:siteId/board',
  people.authenticate,
  people.requireActive,
  requireKnownSite,
  async (req, res, next) => {
    try {
      const periodType = req.query.periodType;
      if (!PERIOD_TYPES.includes(periodType)) {
        throw httpError(400, `periodType must be one of: ${PERIOD_TYPES.join(', ')}`);
      }

      let date = null;
      if (req.query.date !== undefined) {
        date = parseDateOnly(req.query.date);
        if (date === null) throw httpError(400, 'date must be a valid YYYY-MM-DD date');
      }

      let shiftInstanceId = null;
      if (periodType === 'shift') {
        shiftInstanceId = parseId(req.query.shiftInstanceId);
        if (shiftInstanceId === null) {
          throw httpError(400, 'shiftInstanceId must be a valid shift instance id');
        }
      }

      let orgUnit = null;
      if (req.query.orgUnitId !== undefined) {
        orgUnit = await people.findOrgUnit(req.query.orgUnitId);
        if (!orgUnit) throw notFound('Org Unit');
        // An Org Unit that exists but sits at another Site than the path is,
        // from this endpoint's point of view, no such Org Unit in this Site —
        // a 404 rather than a filter that can never match.
        if (orgUnit.siteId !== req.site.id) throw notFound('Org Unit');
      }

      res.json(await board.getBoard(req.site, { orgUnit, periodType, date, shiftInstanceId }));
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

module.exports = router;
