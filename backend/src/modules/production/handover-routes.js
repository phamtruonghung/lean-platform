/*
 * Shift handovers over HTTP (issue #333, ADR-0054). Mounted by index.js under
 * `/api/production`.
 *
 * This is the one file in the Module that talks to People, and only through
 * `modules/people`'s entry point (ADR-0006): `authenticate`, `requireActive`,
 * `canAct` and the shared `OUTSIDE_GRANTED_ORG_UNITS` wording. Everything
 * about the handover itself is handovers.js's business.
 *
 * Who may act: any Account whose edit Grant reaches the Section may open a
 * draft (ADR-0054 — Team Leader is a Job role, not an account role, so scope is
 * the gate), and reading a handover or a Section's day needs a Grant of either
 * level reaching it. `write: true` is spelled out on the open because it
 * defaults to FALSE, and a write that forgot it would be authorised by any read
 * Grant with no error anywhere to notice.
 *
 * Existence before scope, the order AGENTS.md §6 fixes: the Org Unit and the
 * shift instance must be found (404) before `canAct` is asked, because
 * `canAct` answers true for an administrator before it looks at the id. What
 * the two records say about each other — a Section, a shift instance of that
 * Section, no live handover yet — is asked last, by the service.
 */

const express = require('express');
const people = require('../people');
const handovers = require('./handovers');
const { httpError, notFound, parseId, handleError } = require('./errors');

const router = express.Router();

const OUTSIDE_GRANTED_ORG_UNITS_CODE = 'OUTSIDE_GRANTED_ORG_UNITS';

async function requireScope(account, orgUnitId, { write }) {
  const allowed = await people.canAct({ account, orgUnitId, write });
  if (!allowed) {
    throw httpError(403, people.OUTSIDE_GRANTED_ORG_UNITS, OUTSIDE_GRANTED_ORG_UNITS_CODE);
  }
}

// A DATE with no time, strictly — mirrors maintenance/board-routes.js's own
// parseDateOnly. The regex alone would let 2026-13-40 through to Postgres,
// where `::date` raises a SQLSTATE with no `.status` and the caller would see
// a 500 for what is plainly a bad request.
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

// Opening a draft handover for a Section and one of its shift instances.
router.post(
  '/handovers',
  people.authenticate,
  people.requireActive,
  async (req, res, next) => {
    try {
      const body = req.body ?? {};

      const orgUnitId = parseId(body.orgUnitId);
      if (orgUnitId === null) throw httpError(400, 'orgUnitId must be a valid Org Unit id');
      const shiftInstanceId = parseId(body.shiftInstanceId);
      if (shiftInstanceId === null) {
        throw httpError(400, 'shiftInstanceId must be a valid shift instance id');
      }

      const section = await handovers.findOrgUnit(orgUnitId);
      if (!section) throw notFound('Org Unit');
      const shiftInstance = await handovers.findShiftInstance(shiftInstanceId);
      if (!shiftInstance) throw notFound('Shift instance');

      await requireScope(req.account, section.id, { write: true });

      const handover = await handovers.openHandover({ section, shiftInstance });
      res.status(201).json({ handover });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// One handover, with its Section, its shift instance and its lines.
router.get(
  '/handovers/:id',
  people.authenticate,
  people.requireActive,
  async (req, res, next) => {
    try {
      const found = await handovers.findHandover(req.params.id);
      if (!found) throw notFound('Shift handover');

      await requireScope(req.account, found.orgUnitId, { write: false });

      const handover = await handovers.getHandoverDetail(found.id);
      res.json({ handover });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// A Section's production day: every shift instance, each with its live
// handover or `null`. `?date=` is optional and defaults to the Site's today.
router.get(
  '/sections/:orgUnitId/handovers',
  people.authenticate,
  people.requireActive,
  async (req, res, next) => {
    try {
      let date = null;
      if (req.query.date !== undefined) {
        date = parseDateOnly(req.query.date);
        if (date === null) throw httpError(400, 'date must be a valid YYYY-MM-DD date');
      }

      const section = await handovers.findOrgUnit(req.params.orgUnitId);
      if (!section) throw notFound('Org Unit');

      await requireScope(req.account, section.id, { write: false });

      res.json(await handovers.getSectionDay(section, date));
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

module.exports = router;
