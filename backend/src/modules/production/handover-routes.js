/*
 * Shift handovers over HTTP (issue #333, ADR-0054). Mounted by index.js under
 * `/api/production`.
 *
 * This is the one file in the Module that talks to People, and only through
 * `modules/people`'s entry point (ADR-0006): `authenticate`, `requireActive`,
 * `canAct` and the shared `OUTSIDE_GRANTED_ORG_UNITS` wording. Everything
 * about the handover itself is handovers.js's business.
 *
 * Who may act: any Account whose edit Grant reaches the Section may open,
 * write the lines and header of, or submit a draft (ADR-0054 — Team Leader is
 * a Job role, not an account role, so scope is the gate), and reading a handover, a
 * Section's day or its Assets needs a Grant of either level reaching it.
 * `write: true` is spelled out on every write because it
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

// Submitting a draft: seals it and writes its snapshot once (issue #334).
// Existence, then scope with `write: true`, then the service's own refusals —
// not a draft (409), lines missing or incomplete (409, issue #335), the change
// point block unanswered (409, issue #336), an open Action of the Section with
// no disposition (409, issue #337), a shift instance that no longer resolves
// (404).
router.post(
  '/handovers/:id/submit',
  people.authenticate,
  people.requireActive,
  async (req, res, next) => {
    try {
      const found = await handovers.findHandover(req.params.id);
      if (!found) throw notFound('Shift handover');

      await requireScope(req.account, found.orgUnitId, { write: true });

      const handover = await handovers.submitHandover({ id: found.id, account: req.account });
      res.json({ handover });
    } catch (error) {
      handleHandoverError(error, res, next);
    }
  }
);

// A Machine status line body's shape: which fields were sent and whether each
// is the right kind of value. Whether the state and the abnormality type are
// in their sets, and whether a note is owed, is handovers.js's domain check.
function optionalString(body, field) {
  const value = body[field];
  if (value === undefined || value === null) return null;
  if (typeof value !== 'string') throw httpError(400, `${field} must be a string`);
  return value;
}

function optionalId(body, field) {
  const value = body[field];
  if (value === undefined || value === null) return null;
  const id = parseId(value);
  if (id === null) throw httpError(400, `${field} must be a valid id`);
  return id;
}

function parseMachineLine(body) {
  if (typeof body.state !== 'string') throw httpError(400, 'state is required');
  if (body.walked !== undefined && typeof body.walked !== 'boolean') {
    throw httpError(400, 'walked must be true or false');
  }
  return {
    state: body.state,
    abnormalityType: optionalString(body, 'abnormalityType'),
    note: optionalString(body, 'note'),
    downtimeEventId: optionalId(body, 'downtimeEventId'),
    qualityIssueId: optionalId(body, 'qualityIssueId'),
    workOrderId: optionalId(body, 'workOrderId'),
    watchNote: optionalString(body, 'watchNote'),
    walked: body.walked ?? false
  };
}

// Submit's completeness refusal carries the assets it is missing beside the
// message. Answered here rather than by handleError so this Module's errors.js
// stays byte-similar to its siblings (ADR-0006's seam).
function handleHandoverError(error, res, next) {
  if (error.code === 'INCOMPLETE_HANDOVER' && error.details) {
    return res.status(error.status).json({ message: error.message, code: error.code, ...error.details });
  }
  return handleError(error, res, next);
}

// One Asset's Machine status line on a draft (issue #335): written whole, and
// answered with the whole handover. Existence of the handover, then scope with
// `write: true`; the line's own refusals — not a draft, an unknown or
// out-of-section Asset, a missing note, a reference from elsewhere — are the
// service's.
router.put(
  '/handovers/:id/machine-lines/:assetId',
  people.authenticate,
  people.requireActive,
  async (req, res, next) => {
    try {
      const found = await handovers.findHandover(req.params.id);
      if (!found) throw notFound('Shift handover');

      await requireScope(req.account, found.orgUnitId, { write: true });

      const assetId = parseId(req.params.assetId);
      if (assetId === null) throw notFound('Asset');
      const line = parseMachineLine(req.body ?? {});

      const handover = await handovers.putMachineLine({ id: found.id, assetId, line, account: req.account });
      res.json({ handover });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

router.delete(
  '/handovers/:id/machine-lines/:assetId',
  people.authenticate,
  people.requireActive,
  async (req, res, next) => {
    try {
      const found = await handovers.findHandover(req.params.id);
      if (!found) throw notFound('Shift handover');

      await requireScope(req.account, found.orgUnitId, { write: true });

      const assetId = parseId(req.params.assetId);
      if (assetId === null) throw notFound('Machine status line');

      const handover = await handovers.deleteMachineLine({ id: found.id, assetId, account: req.account });
      res.json({ handover });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// The header fields a draft's PATCH may carry, each with its shape check.
// This slice (issue #336) owns `changePointsNone`; the acknowledgement's
// evidence fields join this list on their own ticket.
const HEADER_FIELDS = {
  changePointsNone: (value) => {
    if (typeof value !== 'boolean') throw httpError(400, 'changePointsNone must be true or false');
    return value;
  }
};

function parseHeaderFields(body) {
  const fields = {};
  for (const [field, parse] of Object.entries(HEADER_FIELDS)) {
    if (body[field] !== undefined) fields[field] = parse(body[field]);
  }
  if (Object.keys(fields).length === 0) {
    throw httpError(400, `Send at least one of: ${Object.keys(HEADER_FIELDS).join(', ')}`);
  }
  return fields;
}

// A draft's header fields (issue #336): existence, scope with `write: true`,
// the body's shape, then the service's not-a-draft refusal.
router.patch(
  '/handovers/:id',
  people.authenticate,
  people.requireActive,
  async (req, res, next) => {
    try {
      const found = await handovers.findHandover(req.params.id);
      if (!found) throw notFound('Shift handover');

      await requireScope(req.account, found.orgUnitId, { write: true });

      const fields = parseHeaderFields(req.body ?? {});

      const handover = await handovers.updateHandover({ id: found.id, fields, account: req.account });
      res.json({ handover });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// A change point body's shape. Whether the dimension is one of the 4M, and
// whether the description and the watch are blank, is handovers.js's check.
function parseChangePoint(body) {
  return {
    dimension: optionalString(body, 'dimension'),
    description: optionalString(body, 'description'),
    watchNote: optionalString(body, 'watchNote'),
    employeeId: optionalId(body, 'employeeId')
  };
}

// One change point added to a draft (issue #336), answered 201 with the whole
// handover. Existence of the handover, then scope with `write: true`; the
// change point's own refusals — not a draft, a dimension outside the 4M, a
// blank description or watch, an unknown Employee — are the service's.
router.post(
  '/handovers/:id/change-points',
  people.authenticate,
  people.requireActive,
  async (req, res, next) => {
    try {
      const found = await handovers.findHandover(req.params.id);
      if (!found) throw notFound('Shift handover');

      await requireScope(req.account, found.orgUnitId, { write: true });

      const changePoint = parseChangePoint(req.body ?? {});

      const handover = await handovers.addChangePoint({ id: found.id, changePoint, account: req.account });
      res.status(201).json({ handover });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

router.delete(
  '/handovers/:id/change-points/:changePointId',
  people.authenticate,
  people.requireActive,
  async (req, res, next) => {
    try {
      const found = await handovers.findHandover(req.params.id);
      if (!found) throw notFound('Shift handover');

      await requireScope(req.account, found.orgUnitId, { write: true });

      const changePointId = parseId(req.params.changePointId);
      if (changePointId === null) throw notFound('Change point');

      const handover = await handovers.deleteChangePoint({ id: found.id, changePointId, account: req.account });
      res.json({ handover });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// A Carried action body's shape. Whether the disposition is one of the three,
// and whether it carries the owner or the closure note it owes, is
// handovers.js's check.
function parseActionLink(body) {
  const actionId = parseId(body.actionId);
  if (actionId === null) throw httpError(400, 'actionId must be a valid Action id');
  return {
    actionId,
    disposition: optionalString(body, 'disposition'),
    ownerEmployeeId: optionalId(body, 'ownerEmployeeId'),
    closureNote: optionalString(body, 'closureNote')
  };
}

// One of the Section's open Actions linked to a draft with its disposition
// (issue #337), answered 201 with the whole handover. Existence of the
// handover, then scope with `write: true`; the link's own refusals — not a
// draft, a disposition outside the three, a missing owner or closure note, an
// unknown or out-of-section or finished Action, an unknown owner, the same
// Action twice — are the service's.
router.post(
  '/handovers/:id/actions',
  people.authenticate,
  people.requireActive,
  async (req, res, next) => {
    try {
      const found = await handovers.findHandover(req.params.id);
      if (!found) throw notFound('Shift handover');

      await requireScope(req.account, found.orgUnitId, { write: true });

      const link = parseActionLink(req.body ?? {});

      const handover = await handovers.linkAction({ id: found.id, link, account: req.account });
      res.status(201).json({ handover });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

router.delete(
  '/handovers/:id/actions/:linkId',
  people.authenticate,
  people.requireActive,
  async (req, res, next) => {
    try {
      const found = await handovers.findHandover(req.params.id);
      if (!found) throw notFound('Shift handover');

      await requireScope(req.account, found.orgUnitId, { write: true });

      const linkId = parseId(req.params.linkId);
      if (linkId === null) throw notFound('Handover action');

      const handover = await handovers.unlinkAction({ id: found.id, linkId, account: req.account });
      res.json({ handover });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// The Section's active Assets — the machines a handover owes a line for. The
// same Grant rule as the Section's day.
router.get(
  '/sections/:orgUnitId/assets',
  people.authenticate,
  people.requireActive,
  async (req, res, next) => {
    try {
      const section = await handovers.findOrgUnit(req.params.orgUnitId);
      if (!section) throw notFound('Org Unit');

      await requireScope(req.account, section.id, { write: false });

      res.json(await handovers.listSectionAssets(section));
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
