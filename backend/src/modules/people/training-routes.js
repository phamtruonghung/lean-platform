/*
 * The Training record's HTTP surface (issue #287, ADR-0043). training.js owns
 * the SQL, the row shape and the validation of a record's own facts; this file
 * owns Express, the scope question and the error mapping.
 *
 * Writes follow AGENTS.md section 6's order — existence first, then scope —
 * so an administrator's typo is a 404, never a 500: required fields (400),
 * the Org Unit (404), the trainer Employee (404), then
 * `canAct({ write: true })` (403). Correcting resolves the record (404) and
 * its scope (403) before it looks at the record's status (409) and only then
 * at the body (400, 404).
 *
 * Reads: the register answers every approved Account, as ADR-0009 says of a
 * read, but a draft is shown only to a caller who could send it (an edit
 * Grant reaching its Org Unit, or an administrator) — the same predicate as
 * the write check. A draft the caller could not send reads as a 404 at its
 * own address rather than a 403, so the register is not a way to learn a
 * draft exists.
 */

const express = require('express');
const { authenticate, requireActive } = require('./middleware');
const authorization = require('./authorization');
const plant = require('./plant');
const directory = require('./directory');
const training = require('./training');
const { notFound, parseId, handleError, httpError, OUTSIDE_GRANTED_ORG_UNITS } = require('./errors');

const router = express.Router();

const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;

function requireQueryDate(field, value) {
  if (value === undefined) return null;
  if (typeof value !== 'string' || !DATE_PATTERN.test(value)) {
    throw httpError(400, `${field} must be a date in YYYY-MM-DD form`);
  }
  return value;
}

async function requireKnownTrainer(trainerEmployeeId) {
  if (trainerEmployeeId === null) return;
  const trainer = await directory.findEmployee(trainerEmployeeId);
  if (!trainer) throw notFound('Employee');
}

router.post('/training', authenticate, requireActive, async (req, res, next) => {
  try {
    const body = req.body ?? {};
    const orgUnitId = parseId(body.orgUnitId);
    if (orgUnitId === null) throw httpError(400, 'orgUnitId must be a valid Org Unit id');
    const facts = training.validateRaise(body);

    const orgUnit = await plant.getOrgUnit(orgUnitId); // 404s if it does not exist.
    await requireKnownTrainer(facts.trainerEmployeeId);

    const allowed = await authorization.canAct({
      account: req.account,
      orgUnitId: orgUnit.id,
      write: true
    });
    if (!allowed) {
      return res.status(403).json({ message: OUTSIDE_GRANTED_ORG_UNITS });
    }

    const record = await training.raiseTrainingRecord(req.account.id, orgUnit.id, facts);
    return res.status(201).json({ trainingRecord: record });
  } catch (error) {
    return handleError(error, res, next);
  }
});

router.patch('/training/:id', authenticate, requireActive, async (req, res, next) => {
  try {
    const record = await training.getTrainingRecord(req.params.id); // 404s.
    const allowed = await authorization.canAct({
      account: req.account,
      orgUnitId: record.orgUnitId,
      write: true
    });
    if (!allowed) {
      return res.status(403).json({ message: OUTSIDE_GRANTED_ORG_UNITS });
    }
    if (record.status !== 'draft') {
      throw httpError(409, 'A sent Training record cannot be changed here; correct it instead');
    }

    const changes = training.validateCorrection(req.body ?? {});
    if (changes.trainerEmployeeId !== undefined) {
      await requireKnownTrainer(changes.trainerEmployeeId);
    }
    const corrected = await training.correctTrainingRecord(req.account.id, record.id, changes);
    return res.json({ trainingRecord: corrected });
  } catch (error) {
    return handleError(error, res, next);
  }
});

router.get('/training', authenticate, requireActive, async (req, res, next) => {
  try {
    const from = requireQueryDate('from', req.query.from);
    const to = requireQueryDate('to', req.query.to);

    let orgUnitPath = null;
    if (req.query.orgUnitId !== undefined) {
      if (parseId(req.query.orgUnitId) === null) {
        throw httpError(400, 'orgUnitId must be a valid Org Unit id');
      }
      const orgUnit = await plant.getOrgUnit(req.query.orgUnitId); // 404s.
      orgUnitPath = orgUnit.path;
    }

    const trainingRecords = await training.listTrainingRecords({
      viewer: { accountId: req.account.id, isAdmin: authorization.isAdmin(req.account) },
      orgUnitPath,
      from,
      to
    });
    return res.json({ trainingRecords });
  } catch (error) {
    return handleError(error, res, next);
  }
});

router.get('/training/:id', authenticate, requireActive, async (req, res, next) => {
  try {
    const record = await training.getTrainingRecord(req.params.id); // 404s.
    if (record.status === 'draft') {
      const mayRead = await authorization.canAct({
        account: req.account,
        orgUnitId: record.orgUnitId,
        write: true
      });
      if (!mayRead) throw notFound('Training record');
    }
    return res.json({ trainingRecord: record });
  } catch (error) {
    return handleError(error, res, next);
  }
});

module.exports = router;
